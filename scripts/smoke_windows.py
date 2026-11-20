"""Verify manifest and run the extracted portable package in an isolated folder."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import zipfile

from visual_test_windows import keep_windows_behind


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--network", action="store_true", help="Read-only public relay health with normal TLS validation")
    parser.add_argument("--renderer", default="gl_compatibility")
    parser.add_argument("--output", type=Path, default=Path("artifacts/portable-smoke"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix="empty-extract-", dir=args.output.resolve()))
    with zipfile.ZipFile(args.archive) as bundle:
        for item in bundle.infolist():
            if not (directory / item.filename).resolve().is_relative_to(directory):
                raise RuntimeError("Invalid package path")
        bundle.extractall(directory)
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf8"))
    for name, digest in manifest["files"].items():
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != digest:
            raise RuntimeError("Package integrity failed: " + name)
    profile = (directory.parent / (directory.name + "-profile")).resolve()
    settings = profile / "Godot" / "app_userdata" / "CardUGCGame" / "settings.cfg"
    settings.parent.mkdir(parents=True, exist_ok=True)
    settings.write_text("[presentation]\nmute=true\nwindow_mode=1\n", encoding="utf8")
    env = os.environ.copy()
    env.update(APPDATA=str(profile), LOCALAPPDATA=str(profile))
    command = [str(directory / "Cardex.exe")]
    command += ["--headless"] if args.headless else ["--rendering-method", args.renderer]
    if not args.headless:
        command += ["--position", "-10000,-10000", "--resolution", "1280x720", "--windowed"]
    command += ["--", "--release-smoke"]
    if args.network: command += ["--release-network-smoke"]
    if not args.headless:
        keep_windows_behind()
        if os.name == "nt":
            command.append("--background-visual-test")
        command += ["--smoke-capture=" + str((args.output / "first-launch.png").resolve())]
    start = time.time()
    try:
        process = subprocess.run(command, cwd=directory, env=env, capture_output=True, timeout=60)
        code = process.returncode
        output = process.stdout + process.stderr
    except subprocess.TimeoutExpired as error:
        code = -999
        output = (error.stdout or b"") + (error.stderr or b"")
    (args.output / "run.log").write_bytes(output)
    result_path = settings.parent / "logs" / "release-self-check.json"
    check = json.loads(result_path.read_text(encoding="utf8")) if result_path.exists() else {"failures": ["no self-check report"]}
    passed = code == 0 and not check["failures"] and not any(text in output for text in [b"SCRIPT ERROR", b"ERROR:"])
    (args.output / "verification.json").write_text(json.dumps({"command": command, "exit": code, "seconds": time.time()-start, "extracted": str(directory), "profile": str(profile), "manifest_files_verified": len(manifest["files"]), "self_check": check, "passed": passed}, indent=2), encoding="utf8")
    print(json.dumps({"passed": passed, "exit": code, "self_check": check}, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
