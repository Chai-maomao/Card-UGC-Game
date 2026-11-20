"""Keep Godot windows opened by a Windows test runner underneath desktop apps."""
import os
from pathlib import Path
import shutil
import subprocess


def keep_windows_behind() -> None:
    if os.name != "nt":
        return
    script = Path(__file__).with_name("keep_godot_windows_behind.ps1")
    shell = shutil.which("pwsh") or "powershell.exe"
    subprocess.Popen(
        [shell, "-NoProfile", "-File", str(script), "-RootProcessId", str(os.getpid())],
        creationflags=subprocess.CREATE_NO_WINDOW,
    )
