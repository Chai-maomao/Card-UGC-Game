"""CARDEX workshop API. Bind locally behind an HTTPS reverse proxy in production."""
from __future__ import annotations
import argparse, base64, hashlib, hmac, json, math, os, re, secrets, sqlite3, threading, time
from collections import defaultdict, deque
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

MAX_BODY = 16 * 1024 * 1024
SESSION_AGE = 30 * 86400

class Rejected(Exception):
    def __init__(self, status, message): self.status, self.message = status, message

def clean_text(value, maximum, minimum=0):
    if not isinstance(value, str): raise Rejected(400, '请检查填写的内容')
    value = value.strip()
    if not minimum <= len(value) <= maximum or any(ord(c) < 32 and c not in '\n\t' for c in value):
        raise Rejected(400, '文字长度不合适')
    return value

def image_size(data, ext):
    if ext == 'png' and data.startswith(b'\x89PNG\r\n\x1a\n') and len(data) >= 24:
        return int.from_bytes(data[16:20],'big'), int.from_bytes(data[20:24],'big')
    if ext in ('jpg','jpeg') and data.startswith(b'\xff\xd8'):
        at = 2
        while at < len(data):
            if data[at] != 255: break
            while at < len(data) and data[at] == 255: at += 1
            if at >= len(data): break
            marker=data[at];at+=1
            if marker in (0x01,0xd8,0xd9) or 0xd0 <= marker <= 0xd7: continue
            if at+2 > len(data): break
            length=int.from_bytes(data[at:at+2],'big')
            if length<2 or at+length>len(data): break
            if marker in (0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf) and length>=8:
                return int.from_bytes(data[at+5:at+7],'big'), int.from_bytes(data[at+3:at+5],'big')
            at+=length
    if ext=='webp' and data[:4]==b'RIFF' and data[8:12]==b'WEBP' and len(data)>=30:
        kind=data[12:16]
        if kind==b'VP8X':return 1+int.from_bytes(data[24:27],'little'),1+int.from_bytes(data[27:30],'little')
        if kind==b'VP8L' and data[20]==0x2f:
            bits=int.from_bytes(data[21:25],'little');return 1+(bits&0x3fff),1+((bits>>14)&0x3fff)
        if kind==b'VP8 ' and data[23:26]==b'\x9d\x01\x2a':return int.from_bytes(data[26:28],'little')&0x3fff,int.from_bytes(data[28:30],'little')&0x3fff
    raise Rejected(400,'图片文件损坏')

def validated_cover(encoded):
    if not encoded:return ''
    if not isinstance(encoded,str) or len(encoded)>90000:raise Rejected(400,'封面过大')
    try:data=base64.b64decode(encoded,validate=True)
    except ValueError:raise Rejected(400,'封面文件损坏')
    width,height=image_size(data,'jpg')
    if not 0<width<=512 or not 0<height<=512:raise Rejected(400,'封面尺寸不正确')
    return encoded

def validate_package(package):
    if not isinstance(package, dict) or package.get('version') != 2 or package.get('type') not in ('deck', 'cards'):
        raise Rejected(400, '这不是可用的 CARDEX 卡包')
    cards = package.get('cards')
    if not isinstance(cards, list) or not 1 <= len(cards) <= 200: raise Rejected(400, '卡包需要包含 1–200 张卡牌')
    # Data only: never store local paths, workspace state or executable objects.
    stack = [(package, 0)]
    nodes = 0
    while stack:
        obj, depth = stack.pop(); nodes += 1
        if depth > 32 or nodes > 100000: raise Rejected(400, '卡包内容过于复杂')
        if isinstance(obj, dict):
            for key in list(obj):
                if key in ('art_path', 'damaged_art_path'): obj[key] = ''
                elif key == '_workspace': del obj[key]
            stack.extend((v, depth + 1) for v in obj.values())
        elif isinstance(obj, list): stack.extend((v, depth + 1) for v in obj)
        elif not isinstance(obj, (str, int, float, bool, type(None))): raise Rejected(400, '卡包格式不正确')
    for card in cards:
        if not isinstance(card, dict): raise Rejected(400, '卡牌格式不正确')
        clean_text(card.get('name'), 80, 1)
        if card.get('card_type') not in ('minion', 'spell', 'parasite'): raise Rejected(400, '卡牌类型不正确')
        for field in ('cost', 'max_hp', 'atk'):
            value = card.get(field)
            if type(value) not in (int,float) or not math.isfinite(value) or not 0 <= value <= 100000 or value != int(value): raise Rejected(400, '卡牌数值不正确')
            card[field] = int(value)
        for art in ('art', 'damaged_art'):
            data = card.get(art + '_base64', '')
            if not data: continue
            if not isinstance(data, str) or len(data) > 2800000: raise Rejected(400, '单张卡图不能超过 2 MB')
            try: decoded = base64.b64decode(data, validate=True)
            except (ValueError, TypeError): raise Rejected(400, '卡图文件损坏')
            if not 0 < len(decoded) <= 2 * 1024 * 1024: raise Rejected(400, '单张卡图不能超过 2 MB')
            ext = card.get(art + '_ext')
            valid = (ext == 'png' and decoded.startswith(b'\x89PNG\r\n\x1a\n')) or (ext in ('jpg', 'jpeg') and decoded.startswith(b'\xff\xd8\xff')) or (ext == 'webp' and decoded[:4] == b'RIFF' and decoded[8:12] == b'WEBP')
            if not valid: raise Rejected(400, '卡图格式不正确')
            width,height=image_size(decoded,ext)
            if not 0<width<=4096 or not 0<height<=4096 or width*height>4194304:raise Rejected(400,'卡图过大，请在编辑器中重新裁切')
    if package['type'] == 'deck' and not isinstance(package.get('deck'), dict): raise Rejected(400, '缺少卡组信息')
    return package

class Store:
    def __init__(self, path, *, admin_token='', invite='', require_review=True):
        self.path, self.admin_token, self.invite, self.require_review = str(path), admin_token, invite, require_review
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.lock = threading.Lock(); self.limits = defaultdict(deque)
        with self.db() as db:
            db.executescript('''
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, name TEXT UNIQUE COLLATE NOCASE, salt TEXT, password TEXT, created INTEGER);
            CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, user TEXT, expires INTEGER);
            CREATE TABLE IF NOT EXISTS packages(id TEXT PRIMARY KEY, owner TEXT, title TEXT, description TEXT, payload TEXT, count INTEGER, status TEXT, downloads INTEGER DEFAULT 0, created INTEGER, updated INTEGER, revision INTEGER DEFAULT 1);
            CREATE TABLE IF NOT EXISTS reports(id TEXT PRIMARY KEY, package TEXT, reporter TEXT, reason TEXT, created INTEGER, UNIQUE(package,reporter));
            CREATE INDEX IF NOT EXISTS package_status_date ON packages(status,created);
            CREATE INDEX IF NOT EXISTS package_owner ON packages(owner);
            ''')
            if 'preview' not in {r['name'] for r in db.execute('PRAGMA table_info(packages)')}:
                db.execute("ALTER TABLE packages ADD COLUMN preview TEXT NOT NULL DEFAULT '{}'")
    @contextmanager
    def db(self):
        db = sqlite3.connect(self.path, timeout=10); db.row_factory = sqlite3.Row
        try:
            with db: yield db
        finally: db.close()
    def rate(self, key, count, seconds):
        now = time.monotonic()
        with self.lock:
            if len(self.limits) > 10000:
                self.limits = defaultdict(deque, {k:v for k,v in self.limits.items() if v and now-v[-1]<3600})
            q = self.limits[key]
            while q and q[0] <= now-seconds: q.popleft()
            if len(q) >= count: raise Rejected(429, '操作太频繁，请稍后再试')
            q.append(now)
    def user(self, token, required=True):
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.db() as db:
            user = db.execute('SELECT u.id,u.name FROM sessions s JOIN users u ON u.id=s.user WHERE s.token=? AND s.expires>?', (digest,int(time.time()))).fetchone()
        if required and not user: raise Rejected(401, '请先登录')
        return dict(user) if user else None
    def session(self, user):
        token = secrets.token_urlsafe(32)
        with self.db() as db:
            db.execute('DELETE FROM sessions WHERE expires<?', (int(time.time()),))
            db.execute('INSERT INTO sessions VALUES(?,?,?)', (hashlib.sha256(token.encode()).hexdigest(),user['id'],int(time.time())+SESSION_AGE))
        return {'token': token, 'user': dict(user)}
    def dispatch(self, method, path, query, body, token, ip):
        self.rate(('all',ip), 180, 60)
        if method=='GET' and path=='/v1/health': return {'ok':True}
        if method=='POST' and path in ('/v1/register','/v1/login'):
            self.rate(('auth',ip), 12, 600)
            name = clean_text(body.get('name'), 24, 3)
            if not re.fullmatch(r'[\w-]{3,24}', name): raise Rejected(400, '用户名只能包含文字、数字、下划线或短横线')
            password = body.get('password','')
            if not isinstance(password,str) or not 12 <= len(password) <= 128: raise Rejected(400, '密码需要 12–128 个字符')
            if path=='/v1/register':
                self.rate(('register',ip), 3, 3600)
                if self.invite and not hmac.compare_digest(str(body.get('invite','')),self.invite): raise Rejected(403, '邀请码不正确')
                salt = secrets.token_hex(16)
                hashed = hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(salt),600000).hex()
                user = {'id':secrets.token_hex(16),'name':name}
                try:
                    with self.db() as db: db.execute('INSERT INTO users VALUES(?,?,?,?,?)',(user['id'],name,salt,hashed,int(time.time())))
                except sqlite3.IntegrityError: raise Rejected(409, '这个用户名已被使用')
            else:
                with self.db() as db: row = db.execute('SELECT * FROM users WHERE name=?',(name,)).fetchone()
                hashed = hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(row['salt']) if row else b'0'*16,600000).hex()
                if not row or not hmac.compare_digest(hashed,row['password']): raise Rejected(401, '用户名或密码不正确')
                user = {'id':row['id'],'name':row['name']}
            return self.session(user)
        if path=='/v1/me' and method=='GET': return {'user':self.user(token)}
        if path=='/v1/logout' and method=='POST':
            with self.db() as db: db.execute('DELETE FROM sessions WHERE token=?',(hashlib.sha256(token.encode()).hexdigest(),))
            return {'ok':True}
        if path=='/v1/packages' and method=='GET':
            mine = query.get('mine',['0'])[0]=='1'
            user = self.user(token) if mine else None
            q = clean_text(query.get('q',[''])[0],80)
            try: offset = max(0,min(100000,int(query.get('offset',['0'])[0])))
            except ValueError: raise Rejected(400, '页码不正确')
            where, args = ('p.owner=? AND p.status<>?', [user['id'],'deleted']) if mine else ('p.status=?',['published'])
            where += ' AND (p.title LIKE ? OR p.description LIKE ?)'; args += ['%'+q+'%','%'+q+'%']
            order = 'p.downloads DESC,p.created DESC,p.id' if query.get('sort',['new'])[0]=='popular' else 'p.created DESC,p.id'
            with self.db() as db:
                rows=db.execute(f'SELECT p.id,p.owner,p.title,p.description,p.count,p.status,p.downloads,p.created,p.updated,p.revision,p.preview,u.name AS author FROM packages p JOIN users u ON p.owner=u.id WHERE {where} ORDER BY {order} LIMIT 21 OFFSET ?',args+[offset]).fetchall()
            items=[]
            for row in rows[:20]:
                item=dict(row);item['preview']=json.loads(item['preview']);items.append(item)
            return {'items':items,'has_more':len(rows)>20,'offset':offset}
        if path=='/v1/packages' and method=='POST':
            user=self.user(token);self.rate(('upload',user['id']),10,3600)
            title=clean_text(body.get('title'),80,1);description=clean_text(body.get('description',''),1200)
            package=validate_package(body.get('package'))
            first=package['cards'][0]
            preview={k:first.get(k) for k in ('name','cost','max_hp','atk','card_type','gender')}
            preview['cover']=validated_cover(body.get('cover',''))
            attribution=package.get('provenance',{})
            if not isinstance(attribution,dict): raise Rejected(400,'卡包格式不正确')
            package['provenance']={
                'author':clean_text(attribution.get('author',''),80) or user['name'],
                'revision':clean_text(attribution.get('revision','1'),40) or '1',
                'source':clean_text(attribution.get('source',''),240) or 'CARDEX 创意工坊'}
            payload=json.dumps(package,ensure_ascii=False,separators=(',',':'),allow_nan=False)
            if len(payload.encode())>MAX_BODY: raise Rejected(413,'卡包不能超过 16 MB')
            ident=secrets.token_hex(16);now=int(time.time());status='pending' if self.require_review else 'published'
            with self.db() as db:
                db.execute('BEGIN IMMEDIATE')
                count=db.execute('SELECT COUNT(*) FROM packages WHERE owner=? AND status<>?',(user['id'],'deleted')).fetchone()[0]
                if count>=100: raise Rejected(409,'最多上传 100 个卡包，请先下架不再使用的内容')
                db.execute('INSERT INTO packages(id,owner,title,description,payload,count,status,created,updated,preview) VALUES(?,?,?,?,?,?,?,?,?,?)',(ident,user['id'],title,description,payload,len(package['cards']),status,now,now,json.dumps(preview,ensure_ascii=False)))
            return {'id':ident,'status':status}
        match=re.fullmatch(r'/v1/packages/([0-9a-f]{32})(/download|/report)?',path)
        if match:
            ident,action=match.groups()
            with self.db() as db: row=db.execute('SELECT * FROM packages WHERE id=?',(ident,)).fetchone()
            if not row or row['status']=='deleted': raise Rejected(404,'这个卡包已不存在')
            user=self.user(token,False)
            own=bool(user and user['id']==row['owner'])
            if row['status']!='published' and not own: raise Rejected(404,'这个卡包暂不可用')
            if method=='GET' and action=='/download':
                with self.db() as db: db.execute('UPDATE packages SET downloads=downloads+1 WHERE id=?',(ident,))
                return {'package':json.loads(row['payload']),'id':ident,'title':row['title']}
            if method=='DELETE' and not action:
                if not own: raise Rejected(403,'只能下架自己的卡包')
                with self.db() as db: db.execute("UPDATE packages SET status='deleted',payload='{}',updated=? WHERE id=?",(int(time.time()),ident))
                return {'ok':True}
            if method=='POST' and action=='/report':
                user=self.user(token);self.rate(('report',user['id']),10,3600);reason=clean_text(body.get('reason'),500,1)
                with self.db() as db:
                    try: db.execute('INSERT INTO reports VALUES(?,?,?,?,?)',(secrets.token_hex(16),ident,user['id'],reason,int(time.time())))
                    except sqlite3.IntegrityError: raise Rejected(409,'已经收到你的举报')
                return {'ok':True}
        if path.startswith('/v1/admin/'):
            if not self.admin_token or not hmac.compare_digest(token,self.admin_token): raise Rejected(403,'无权执行此操作')
            if path=='/v1/admin/review' and method=='GET':
                with self.db() as db:
                    pending=[dict(r) for r in db.execute("SELECT id,title,owner,count,created FROM packages WHERE status='pending' ORDER BY created LIMIT 100")]
                    reports=[dict(r) for r in db.execute('SELECT * FROM reports ORDER BY created DESC LIMIT 100')]
                return {'pending':pending,'reports':reports}
            match=re.fullmatch(r'/v1/admin/packages/([0-9a-f]{32})',path)
            if match and method=='GET':
                with self.db() as db: row=db.execute('SELECT * FROM packages WHERE id=?',(match[1],)).fetchone()
                if not row or row['status']=='deleted': raise Rejected(404,'卡包不存在')
                return {'id':row['id'],'title':row['title'],'description':row['description'],'package':json.loads(row['payload'])}
            if match and method=='POST':
                status=body.get('status')
                if status not in ('published','hidden'): raise Rejected(400,'状态不正确')
                with self.db() as db:
                    result=db.execute("UPDATE packages SET status=?,updated=? WHERE id=? AND status<>'deleted'",(status,int(time.time()),match[1]))
                    if not result.rowcount: raise Rejected(404,'卡包不存在')
                return {'ok':True}
        raise Rejected(404,'找不到这个页面')

class Handler(BaseHTTPRequestHandler):
    server_version='CardexWorkshop'
    def setup(self):
        super().setup(); self.connection.settimeout(20)
    def log_message(self, *_): pass  # Never log authorization headers or request bodies.
    def do_GET(self): self.handle_api()
    def do_POST(self): self.handle_api()
    def do_DELETE(self): self.handle_api()
    def handle_api(self):
        try:
            parts=urlsplit(self.path)
            if self.headers.get('Transfer-Encoding'): raise Rejected(400,'不支持此上传方式')
            try: length=int(self.headers.get('Content-Length','0'))
            except ValueError: raise Rejected(400,'请求格式不正确')
            if not 0<=length<=MAX_BODY: raise Rejected(413,'卡包不能超过 16 MB')
            if self.command!='GET' and not self.server.allow_http and self.headers.get('X-Forwarded-Proto')!='https':
                raise Rejected(403,'请使用 HTTPS 连接')
            body={}
            if length:
                if self.headers.get_content_type()!='application/json': raise Rejected(415,'请上传 JSON 卡包')
                raw=self.rfile.read(length)
                if len(raw)!=length: raise Rejected(400,'上传未完成，请重试')
                try: body=json.loads(raw,parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
                except (ValueError,RecursionError): raise Rejected(400,'卡包文件损坏')
                if not isinstance(body,dict): raise Rejected(400,'请求格式不正确')
            auth=self.headers.get('Authorization','')
            token=auth[7:] if auth.startswith('Bearer ') else ''
            ip=self.client_address[0]
            if ip in ('127.0.0.1','::1') and self.headers.get('X-Real-IP'):
                ip=self.headers['X-Real-IP'][:80]
            result=self.server.store.dispatch(self.command,parts.path,parse_qs(parts.query),body,token,ip)
            self.respond(200,result)
        except Rejected as e: self.respond(e.status,{'error':e.message})
        except (BrokenPipeError,ConnectionResetError,TimeoutError): self.close_connection=True
        except Exception:
            self.respond(500,{'error':'服务暂时不可用，请稍后再试'})
    def respond(self,status,body):
        data=json.dumps(body,ensure_ascii=False,allow_nan=False,separators=(',',':')).encode()
        self.send_response(status);self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff');self.send_header('Connection','close');self.end_headers()
        self.wfile.write(data);self.close_connection=True

class Server(ThreadingHTTPServer):
    daemon_threads=True
    def __init__(self,address,store,allow_http=False):
        super().__init__(address,Handler);self.store=store;self.allow_http=allow_http
        self.capacity=threading.BoundedSemaphore(4)
    def process_request(self,request,address):
        if not self.capacity.acquire(False): request.close();return
        try: super().process_request(request,address)
        except Exception: self.capacity.release();raise
    def process_request_thread(self,request,address):
        try: super().process_request_thread(request,address)
        finally: self.capacity.release()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--host',default='127.0.0.1');parser.add_argument('--port',type=int,default=8765);parser.add_argument('--db',default='workshop-data/workshop.sqlite3');parser.add_argument('--allow-http',action='store_true');args=parser.parse_args()
    if args.host not in ('127.0.0.1','::1'):
        raise SystemExit('Bind to loopback and use the provided HTTPS reverse-proxy configuration.')
    store=Store(args.db,admin_token=os.environ.get('CARDEX_WORKSHOP_ADMIN_TOKEN',''),invite=os.environ.get('CARDEX_WORKSHOP_INVITE',''))
    server=Server((args.host,args.port),store,args.allow_http)
    print(f'CARDEX workshop listening on {args.host}:{args.port}',flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()

if __name__=='__main__': main()
