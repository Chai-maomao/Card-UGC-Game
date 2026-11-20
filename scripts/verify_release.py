"""Isolated Godot scene verification, strict exits/markers/errors, JSON evidence."""
import argparse, hashlib, json, os, pathlib, re, subprocess, time
from visual_test_windows import keep_windows_behind

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("godot")
    parser.add_argument("--suite",choices=["logic","visual"],default="logic")
    parser.add_argument("--scene",default="Test*.tscn")
    parser.add_argument("--output",default="artifacts/release-verification")
    parser.add_argument("--timeout",type=int,default=100)
    parser.add_argument("--simulation-timeout",type=int,default=900,help="Timeout for the 1,000-game battle simulation")
    args=parser.parse_args()
    background = args.suite == "visual" and os.name == "nt"
    if background:
        keep_windows_behind()
    root=pathlib.Path(__file__).resolve().parents[1]
    output=(root/args.output).resolve(); output.mkdir(parents=True,exist_ok=True)
    result={"started":time.time(),"suite":args.suite,"scenes":[],"source_sha256":{}}
    ignored = {"artifacts", ".godot", "build", "node_modules"}
    source_paths = []
    for directory, subdirs, files in os.walk(root):
        subdirs[:] = [name for name in subdirs if name not in ignored]
        source_paths.extend(pathlib.Path(directory) / name for name in files if name.endswith(".gd"))
    for path in sorted(source_paths):
        result["source_sha256"][str(path.relative_to(root))]=hashlib.sha256(path.read_bytes()).hexdigest()
    scenes=[p for p in sorted(root.glob(args.scene)) if p.stem.endswith("Visual")== (args.suite=="visual")]
    for scene in scenes:
        profile=output/"profiles"/scene.stem; profile.mkdir(parents=True,exist_ok=True)
        env=os.environ.copy()
        for key in ["APPDATA","LOCALAPPDATA","XDG_DATA_HOME","XDG_CONFIG_HOME"]: env[key]=str(profile)
        command=[args.godot,"--path",str(root),"--audio-driver","Dummy"]
        command+= ["--headless"] if args.suite=="logic" else ["--rendering-method","gl_compatibility","--rendering-driver","opengl3"]
        if background:
            command += ["--windowed", "--position", "-10000,-10000"]
        command += ["--scene","res://"+scene.name,"--","--no-audio"]
        if background:
            command.append("--background-visual-test")
        start=time.time()
        try:
            timeout=max(args.timeout,args.simulation_timeout) if scene.name=="TestBattleSimulator.tscn" else args.timeout
            process=subprocess.run(command,env=env,cwd=root,capture_output=True,timeout=timeout)
            code=process.returncode; content=process.stdout+process.stderr
        except subprocess.TimeoutExpired as error:
            code=-999; content=(error.stdout or b"")+(error.stderr or b"")
        text=content.decode("utf8",errors="replace")
        (output/(scene.stem+".log")).write_bytes(content)
        marker=re.findall(r"TEST_[A-Z0-9_]+_OK",text)
        errors=bool(re.search(r"SCRIPT ERROR|Parse Error|ERROR:|TEST_[A-Z0-9_]+_FAILED",text))
        passed=code==0 and bool(marker) and not errors
        record={"scene":scene.name,"command":command,"exit":code,"seconds":round(time.time()-start,3),"markers":marker,"passed":passed}
        result["scenes"].append(record)
        print(("PASS " if passed else "FAIL ")+scene.name+" exit="+str(code),flush=True)
        (output/"verification.json").write_text(json.dumps(result,indent=2),encoding="utf8")
    result["finished"]=time.time(); result["discovered"]=len(scenes)
    result["passed"]=sum(s["passed"] for s in result["scenes"])
    result["failed"]=len(scenes)-result["passed"]
    (output/"verification.json").write_text(json.dumps(result,indent=2),encoding="utf8")
    print(f"Ran {len(scenes)} scenes; passed {result['passed']}; failed {result['failed']}",flush=True)
    return 0 if scenes and not result["failed"] else 1
if __name__=="__main__": raise SystemExit(main())
