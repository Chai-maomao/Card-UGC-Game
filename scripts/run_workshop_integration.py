"""Run real Godot UI/import flows against temporary local workshop servers."""
import argparse,os,pathlib,shutil,subprocess,sys,tempfile,threading

ROOT=pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
from workshop.server import Store,Server

class ObservingStore(Store):
    def dispatch(self,method,path,query,body,token,ip):
        if path=='/v1/header_probe':return {'sent_token':bool(token)}
        return super().dispatch(method,path,query,body,token,ip)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--godot',default=os.environ.get('GODOT_BIN') or shutil.which('godot') or 'D:/XunLeiXiaZai/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe')
    parser.add_argument('--case',choices=['all','ui','import'],default='all')
    parser.add_argument('--import-project',action='store_true')
    args=parser.parse_args()
    logs=ROOT/'artifacts/workshop-integration';logs.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cardex-workshop-tests-') as temporary:
        base=pathlib.Path(temporary)
        if args.import_project:
            env=os.environ.copy();env.update(APPDATA=str(base),LOCALAPPDATA=str(base))
            result=subprocess.run([args.godot,'--headless','--path',str(ROOT),'--editor','--quit'],cwd=ROOT,env=env,capture_output=True,timeout=90)
            content=(result.stdout+result.stderr).decode(errors='replace');(logs/'import.log').write_text(content,encoding='utf-8')
            if result.returncode or 'ERROR:' in content:raise SystemExit('Project import failed. See '+str(logs/'import.log'))
        cases=['ui','import'] if args.case=='all' else [args.case]
        for case in cases:
            run=base/case;run.mkdir();profile=run/'profile';profile.mkdir()
            env=os.environ.copy();env.update(APPDATA=str(profile),LOCALAPPDATA=str(profile))
            store=Store(run/'workshop.sqlite3',admin_token='local-test-only',invite='friend-test-invite',require_review=case=='ui')
            servers=[Server(('127.0.0.1',0),store,True),Server(('127.0.0.1',0),ObservingStore(run/'observer.sqlite3'),True)]
            threads=[threading.Thread(target=s.serve_forever,daemon=True) for s in servers]
            for thread in threads:thread.start()
            scene='ui_flow' if case=='ui' else 'import_flow'
            marker='TEST_WORKSHOP_UI_FLOW_OK' if case=='ui' else 'TEST_WORKSHOP_GAME_IMPORT_OK'
            try:
                result=subprocess.run([args.godot,'--headless','--path',str(ROOT),'--quit-after','1500','--scene','res://tests/integration/workshop/'+scene+'.tscn','--','--no-audio','--workshop-url=http://127.0.0.1:'+str(servers[0].server_port),'--workshop-other-origin=http://127.0.0.1:'+str(servers[1].server_port)],cwd=ROOT,env=env,capture_output=True,timeout=30)
                content=(result.stdout+result.stderr).decode(errors='replace');(logs/(case+'.log')).write_text(content,encoding='utf-8')
                if result.returncode or 'ERROR:' in content or marker not in content:
                    print(content[-3000:]);raise SystemExit(case+' failed')
                print(case+': '+marker)
            finally:
                for server in servers:server.shutdown();server.server_close()
                for thread in threads:thread.join()

if __name__=='__main__':main()
