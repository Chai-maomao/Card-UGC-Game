"""Local operator utility. Keep the admin token on the server, never in the game."""
import argparse,json,os
from urllib.request import Request,urlopen

def main():
    p=argparse.ArgumentParser();p.add_argument('action',choices=['review','download','publish','hide']);p.add_argument('id',nargs='?');p.add_argument('--url',default='http://127.0.0.1:8765');p.add_argument('--output',default='review-package.json');a=p.parse_args()
    token=os.environ.get('CARDEX_WORKSHOP_ADMIN_TOKEN','')
    if not token:raise SystemExit('Set CARDEX_WORKSHOP_ADMIN_TOKEN in the operator environment.')
    path='/v1/admin/review' if a.action=='review' else '/v1/admin/packages/'+(a.id or '')
    method='POST' if a.action in ('publish','hide') else 'GET'
    body=json.dumps({'status':'published' if a.action=='publish' else 'hidden'}).encode() if method=='POST' else None
    req=Request(a.url+path,method=method,data=body,headers={'Authorization':'Bearer '+token,'Content-Type':'application/json','X-Forwarded-Proto':'https'})
    with urlopen(req,timeout=30) as r:result=json.load(r)
    if a.action=='download':
        from pathlib import Path
        Path(a.output).write_text(json.dumps(result['package'],ensure_ascii=False,indent=2),encoding='utf-8')
        print('Saved package for review:',a.output)
    else:print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
