import copy,json,tempfile,threading,unittest
from urllib.request import Request,urlopen
from urllib.error import HTTPError
from workshop.server import Store,Server

CARD={'name':'弓箭手','card_type':'minion','cost':3,'max_hp':3,'atk':2,'skills':[],'art_path':'C:/private/name.png','damaged_art_path':'C:/private/hurt.png','_workspace':{'secret':'local'}}
PACKAGE={'version':2,'type':'cards','cards':[CARD]}
class WorkshopHttpTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.store=Store(self.tmp.name+'/db.sqlite3',admin_token='test-admin-secret')
        self.server=Server(('127.0.0.1',0),self.store,True)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.url='http://127.0.0.1:'+str(self.server.server_port)
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join();self.tmp.cleanup()
    def api(self,path,method='GET',body=None,token=''):
        data=json.dumps(body).encode() if body is not None else None
        req=Request(self.url+path,data=data,method=method,headers={'Content-Type':'application/json','Authorization':'Bearer '+token})
        try:
            with urlopen(req,timeout=5) as r:return r.status,json.load(r)
        except HTTPError as e:
            with e:return e.code,json.load(e)
    def register(self,name):
        status,data=self.api('/v1/register','POST',{'name':name,'password':'long-test-password'})
        self.assertEqual(status,200,data);return data['token']
    def publish(self,ident):
        self.assertEqual(self.api('/v1/admin/packages/'+ident,'POST',{'status':'published'},'test-admin-secret')[0],200)
    def test_upload_review_download_report_and_ownership(self):
        owner=self.register('author');other=self.register('reader')
        code,item=self.api('/v1/packages','POST',{'title':'远征卡包','description':'自制卡牌','package':copy.deepcopy(PACKAGE)},owner)
        self.assertEqual(code,200,item);ident=item['id'];self.assertEqual(item['status'],'pending')
        self.assertEqual(self.api('/v1/packages')[1]['items'],[])
        self.assertEqual(self.api('/v1/packages/'+ident+'/download')[0],404)
        review=self.api('/v1/admin/packages/'+ident,token='test-admin-secret')[1]
        self.assertEqual(review['package']['cards'][0]['art_path'],'')
        self.assertNotIn('_workspace',review['package']['cards'][0])
        self.publish(ident)
        listed=self.api('/v1/packages?q='+__import__('urllib.parse',fromlist=['quote']).quote('远征'))[1]
        self.assertEqual(listed['items'][0]['author'],'author')
        downloaded=self.api('/v1/packages/'+ident+'/download')[1]['package']
        self.assertEqual(downloaded['cards'][0]['name'],'弓箭手')
        self.assertEqual(downloaded['provenance']['author'],'author')
        self.assertEqual(self.api('/v1/packages/'+ident,'DELETE',token=other)[0],403)
        self.assertEqual(self.api('/v1/packages/'+ident+'/report','POST',{'reason':'疑似侵权'},other)[0],200)
        self.assertEqual(self.api('/v1/packages/'+ident+'/report','POST',{'reason':'重复'},other)[0],409)
        self.assertEqual(len(self.api('/v1/admin/review',token='test-admin-secret')[1]['reports']),1)
        self.assertEqual(self.api('/v1/packages/'+ident,'DELETE',token=owner)[0],200)
        self.assertEqual(self.api('/v1/packages/'+ident+'/download')[0],404)
    def test_auth_and_logout(self):
        token=self.register('player')
        self.assertEqual(self.api('/v1/me',token=token)[0],200)
        self.assertEqual(self.api('/v1/login','POST',{'name':'player','password':'wrong-password'})[0],401)
        self.assertEqual(self.api('/v1/logout','POST',{},token)[0],200)
        self.assertEqual(self.api('/v1/me',token=token)[0],401)
        self.assertEqual(self.api('/v1/register','POST',{'name':'PLAYER','password':'another-password'})[0],409)
    def test_invalid_content_and_invite(self):
        self.store.invite='invitation'
        self.assertEqual(self.api('/v1/register','POST',{'name':'stranger','password':'long-test-password'})[0],403)
        self.store.invite='';token=self.register('uploader')
        for package in [{},dict(PACKAGE,cards=[]),dict(PACKAGE,cards=[dict(CARD,art_base64='broken',art_ext='png')])]:
            self.assertEqual(self.api('/v1/packages','POST',{'title':'Bad','package':package},token)[0],400)
        self.assertEqual(self.api('/v1/packages','POST',{'title':'No login','package':PACKAGE})[0],401)
        self.assertEqual(self.api('/v1/admin/review',token=token)[0],403)
    def test_pagination_and_restart_persistence(self):
        owner=self.register('collector')
        # Use persisted rows to exercise real SQL paging without the upload throttle.
        with self.store.db() as db:
            uid=self.store.user(owner)['id']
            for i in range(24):
                db.execute('INSERT INTO packages(id,owner,title,description,payload,count,status,created,updated) VALUES(?,?,?,?,?,?,?,?,?)',(f'{i:032x}',uid,f'Pack {i}','',json.dumps(PACKAGE),1,'published',i,i))
        first=self.api('/v1/packages')[1];second=self.api('/v1/packages?offset=20')[1]
        self.assertTrue(first['has_more']);self.assertEqual(len(first['items']),20);self.assertEqual(len(second['items']),4)
        self.assertFalse(set(x['id'] for x in first['items']) & set(x['id'] for x in second['items']))
        reopened=Store(self.store.path)
        self.assertEqual(reopened.user(owner)['name'],'collector')
        self.assertEqual(len(reopened.dispatch('GET','/v1/packages',{}, {},'', 'test')['items']),20)

    def test_attribution_and_image_bounds(self):
        token=self.register('curator')
        package=copy.deepcopy(PACKAGE)
        package['provenance']={'author':'Original Artist','revision':'2','source':'https://example.com/art-permission'}
        status,item=self.api('/v1/packages','POST',{'title':'Credited pack','package':package},token)
        self.assertEqual(status,200,item)
        received=self.api('/v1/packages/'+item['id']+'/download',token=token)[1]['package']
        self.assertEqual(received['provenance'],package['provenance'])
        # Reject tiny compressed files that claim a huge decoded image.
        import base64,struct,zlib
        def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
        png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',50000,50000,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b'\x00'*5))+chunk(b'IEND',b'')
        package['cards'][0].update(art_base64=base64.b64encode(png).decode(),art_ext='png')
        self.assertEqual(self.api('/v1/packages','POST',{'title':'Huge image','package':package},token)[0],400)
    def test_body_limit_and_backup_restore(self):
        import http.client,sqlite3
        from workshop.backup import backup
        connection=http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=5)
        try:
            connection.putrequest('POST','/v1/packages')
            connection.putheader('Content-Length',str(16*1024*1024+1));connection.endheaders()
            response=connection.getresponse();self.assertEqual(response.status,413);response.read()
        finally:connection.close()
        token=self.register('backup_user')
        target=backup(self.store.path,self.tmp.name+'/backups')
        restored=Store(target)
        self.assertEqual(restored.user(token)['name'],'backup_user')
        with restored.db() as db:self.assertEqual(db.execute('PRAGMA integrity_check').fetchone()[0],'ok')

if __name__=='__main__':unittest.main()
