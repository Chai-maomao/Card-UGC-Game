"""Local, unsigned Windows portable candidate. Does not publish or sign."""
import argparse, hashlib, json, os, pathlib, re, shutil, subprocess, sys, time, zipfile
from install_godot import WINDOWS_RELEASE_VERSION

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("godot")
    args=parser.parse_args()
    engine_version = subprocess.check_output([args.godot, "--version"], text=True, timeout=15).strip()
    template_version = f"{WINDOWS_RELEASE_VERSION}.stable"
    # Godot 4.7.2 fixes Windows frame stalls with high-polling-rate mice.
    if not engine_version.startswith(template_version + ".official."):
        parser.error(f"Windows builds require official Godot {template_version}; found {engine_version}")
    root=pathlib.Path(__file__).resolve().parents[1]
    version=re.search(r'const VERSION := "([^"]+)"',(root/"AppVersion.gd").read_text()).group(1)
    preset=(root/"export_presets.cfg").read_text(encoding="utf8")
    if f'application/product_version="{version}"' not in preset:
        raise ValueError("AppVersion and Windows product version differ")
    directory=root/"build"/"windows"/version; directory.mkdir(parents=True,exist_ok=True)
    binary=directory/"Cardex.exe"
    # Editor/export temporary files and settings must not touch the player's
    # profile. A failed project.binary write can otherwise still return exit 0.
    scratch=root/".godot"/"portable-export"
    temporary=scratch/"temp";temporary.mkdir(parents=True,exist_ok=True)
    profile=scratch/"profile";profile.mkdir(exist_ok=True)
    env=os.environ.copy()
    if sys.platform=="win32":
        templates=pathlib.Path(env["APPDATA"])/"Godot"/"export_templates"/template_version
        isolated=profile/"Godot"/"export_templates"/template_version;isolated.mkdir(parents=True,exist_ok=True)
        for name in ["windows_release_x86_64.exe","windows_debug_x86_64.exe"]:
            source=templates/name;target=isolated/name
            if source.exists() and (not target.exists() or source.stat().st_mtime_ns!=target.stat().st_mtime_ns): shutil.copy2(source,target)
    env.update(APPDATA=str(profile),LOCALAPPDATA=str(profile),TEMP=str(temporary),TMP=str(temporary))
    editor_version = WINDOWS_RELEASE_VERSION.rsplit(".", 1)[0]
    settings=profile/"Godot"/f"editor_settings-{editor_version}.tres"
    settings.parent.mkdir(parents=True,exist_ok=True)
    settings.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\nnetwork/tls/editor_tls_certificates = '+json.dumps((root/"res/network/cacert.pem").as_posix())+'\n',encoding="utf8")
    # Script-only mode omits autoload singletons. Compile through the real
    # startup path instead, with a bounded self-check and isolated user data.
    check=subprocess.run([args.godot,"--headless","--path",str(root),"--","--release-smoke","--no-audio"],cwd=root,env=env,capture_output=True,timeout=60)
    check_output=check.stdout+check.stderr
    (directory/"compile.log").write_bytes(check_output)
    if check.returncode or b"RELEASE_SELF_CHECK" not in check_output or b"ERROR:" in check_output or b"SCRIPT ERROR" in check_output:
        print(check_output.decode("utf8",errors="replace")); return 1
    command=[args.godot,"--headless","--path",str(root),"--export-release","Windows Desktop",str(binary)]
    result=subprocess.run(command,cwd=root,env=env,capture_output=True,timeout=300)
    (directory/"export.log").write_bytes(result.stdout+result.stderr)
    output=result.stdout+result.stderr
    errors=[line for line in output.splitlines() if b"ERROR:" in line or b"SCRIPT ERROR" in line]
    if result.returncode or errors or not binary.exists() or not binary.with_suffix(".pck").exists():
        print((result.stdout+result.stderr).decode(errors="replace")); return 1
    for name in ["LICENSE","legal","res/fonts/OFL.txt","res/fonts/NotoSerifSC-OFL.txt","RELEASE_NOTES.md"]:
        source=root/name
        if source.is_dir(): shutil.copytree(source,directory/name,dirs_exist_ok=True)
        else:
            target=directory/name; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(source,target)
    (directory/"Compatibility.cmd").write_text('@echo off\ncd /d "%~dp0"\nstart "CARDEX" "%~dp0Cardex.exe" --rendering-method gl_compatibility --rendering-driver opengl3\n',encoding="ascii")
    (directory/"README.txt").write_text("CARDEX "+version+" — Windows x64 portable prerelease (unsigned)\n\nRun Cardex.exe. If graphics fail, use Compatibility.cmd. Keep the exe and pck together.\nSaves: %APPDATA%/Godot/app_userdata/CardUGCGame. Back up this folder before updates. Deleting this portable folder does not delete saves.\nSupport, privacy, terms and UGC: Settings > Support. See legal/ for notices.\nNo installer, no administrative rights, no automatic updates. Prerelease testing build.\n",encoding="utf8")
    records={"version":version,"created":time.time(),"godot_version":engine_version,"export_preset":"Windows Desktop","exit":result.returncode,"signed":False,"files":{},"source_sha256":{}}
    excluded_dirs = {"artifacts", "build", ".godot", "node_modules", ".git"}
    source_suffixes = {".gd", ".tscn", ".godot", ".cfg", ".gdshader"}
    for folder, directories, filenames in os.walk(root):
        directories[:] = sorted(name for name in directories if name not in excluded_dirs)
        for name in sorted(filenames):
            path = pathlib.Path(folder) / name
            if path.suffix in source_suffixes and path.is_file():
                records["source_sha256"][path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    for path in sorted(directory.rglob("*")):
        if path.is_file() and path.name not in ["manifest.json","export.log","compile.log"]: records["files"][path.relative_to(directory).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
    (directory/"manifest.json").write_text(json.dumps(records,indent=2),encoding="utf8")
    archive=directory.parent/("CARDEX-"+version+"-windows-x64.zip")
    with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(directory.rglob("*")):
            if path.is_file() and path.name not in ["export.log","compile.log"]: bundle.write(path,path.relative_to(directory))
    print(json.dumps({"directory":str(directory),"zip":str(archive),"zip_sha256":hashlib.sha256(archive.read_bytes()).hexdigest()},indent=2))
    return 0
if __name__=="__main__": sys.exit(main())
