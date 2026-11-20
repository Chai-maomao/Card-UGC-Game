"""Real rendered long runs; no clock acceleration; isolated profiles and source manifest."""
import argparse,hashlib,json,os,pathlib,subprocess,time

def main():
 p=argparse.ArgumentParser();p.add_argument("godot");p.add_argument("--mode",choices=["local","network"],default="local");p.add_argument("--seconds",type=int,default=7200);p.add_argument("--output",required=True);args=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1];out=(root/args.output).resolve();out.mkdir(parents=True,exist_ok=True)
 manifest={"mode":args.mode,"requested_seconds":args.seconds,"started":time.time(),"source_sha256":{},"clients":[]}
 for path in root.rglob("*.gd"):
  if any(part in path.parts for part in ["artifacts","build",".godot","node_modules"]):continue
  manifest["source_sha256"][path.relative_to(root).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
 processes=[];handles=[]
 try:
  for role in ([1,2] if args.mode=="network" else [0]):
   profile=out/("profile-"+str(role));profile.mkdir(exist_ok=True)
   env=os.environ.copy();env.update(APPDATA=str(profile),LOCALAPPDATA=str(profile))
   settings=profile/"Godot"/"app_userdata"/"CardUGCGame"/"settings.cfg";settings.parent.mkdir(parents=True,exist_ok=True);settings.write_text("[presentation]\nmute=true\nwindow_mode=1\n",encoding="utf8")
   log=out/("client-"+str(role)+".log");handle=log.open("w",encoding="utf8");handles.append(handle)
   command=[args.godot,"--path",str(root),"--position","-10000,-10000","--windowed","--rendering-method","gl_compatibility","--scene","res://tests/integration/"+("local_presentation_soak.tscn" if args.mode=="local" else "network_presentation_soak.tscn"),"--","--seconds="+str(args.seconds),"--role="+str(role),"--shared="+str(out/"network")]
   process=subprocess.Popen(command,cwd=root,env=env,stdout=handle,stderr=subprocess.STDOUT);processes.append(process)
   manifest["clients"].append({"role":role,"pid":process.pid,"command":command,"log":str(log)})
   (out/"verification.json").write_text(json.dumps(manifest,indent=2),encoding="utf8")
   if role==1:time.sleep(1)
  deadline=time.time()+args.seconds+80
  while any(process.poll() is None for process in processes) and time.time()<deadline:
   time.sleep(1)
   if any(process.poll() not in [None,0] for process in processes):break
  for process,client in zip(processes,manifest["clients"]):
   if process.poll() is None:process.kill();process.wait();client["timed_out_or_peer_failed"]=True
   client["exit"]=process.returncode
  for handle in handles:handle.close()
  manifest["finished"]=time.time()
  for client in manifest["clients"]:
   text=pathlib.Path(client["log"]).read_text(encoding="utf8",errors="replace")
   client["passed"]=client["exit"]==0 and "PRESENTATION_SOAK_OK" in text and not any(error in text for error in ["SCRIPT ERROR","ERROR:","SOAK_FAILED"])
  (out/"verification.json").write_text(json.dumps(manifest,indent=2),encoding="utf8")
  print(json.dumps(manifest["clients"],indent=2),flush=True)
  return 0 if all(client["passed"] for client in manifest["clients"]) else 1
 finally:
  for process in processes:
   if process.poll() is None:process.kill();process.wait()
  for handle in handles:
   if not handle.closed:handle.close()
if __name__=="__main__":raise SystemExit(main())
