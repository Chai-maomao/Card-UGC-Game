"""Install pinned official Godot binaries/templates for reproducible CI checks."""
import argparse
import hashlib
import os
from pathlib import Path
import platform
import urllib.request
import zipfile

VERSION = "4.6.3"
BASE = f"https://github.com/godotengine/godot/releases/download/{VERSION}-stable/"


def digest(path):
    result = hashlib.sha512()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(4*1024*1024), b""):
            result.update(chunk)
    return result.hexdigest()


def download(name, cache, checksums):
    destination = cache / name
    expected = checksums[name]
    if not destination.exists() or digest(destination) != expected:
        urllib.request.urlretrieve(BASE + name, destination)
    if digest(destination) != expected:
        raise RuntimeError("Official checksum mismatch: " + name)
    return destination


def extract_checked(archive, directory, selected=None):
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as bundle:
        for item in bundle.infolist():
            if selected is not None and item.filename not in selected:
                continue
            target = (directory / item.filename).resolve()
            if not target.is_relative_to(directory):
                raise RuntimeError("Invalid archive path")
            bundle.extract(item, directory)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", default=".godot/ci-engine")
    parser.add_argument("--windows-templates", action="store_true")
    args = parser.parse_args()
    directory = Path(args.directory).resolve()
    cache = directory / "downloads"
    cache.mkdir(parents=True, exist_ok=True)
    sums = urllib.request.urlopen(BASE + "SHA512-SUMS.txt", timeout=60).read().decode()
    checksums = {}
    for line in sums.splitlines():
        fields = line.split()
        if len(fields) >= 2:
            checksums[fields[-1].lstrip("*")] = fields[0]
    windows = platform.system() == "Windows"
    stem = f"Godot_v{VERSION}-stable_" + ("win64.exe" if windows else "linux.x86_64")
    archive = download(stem + ".zip", cache, checksums)
    extract_checked(archive, directory / "bin")
    binary = directory / "bin" / stem
    if not windows:
        binary.chmod(0o755)
    if args.windows_templates:
        template = download(f"Godot_v{VERSION}-stable_export_templates.tpz", cache, checksums)
        target = Path(os.environ["APPDATA"]) / "Godot" / "export_templates" / f"{VERSION}.stable"
        target.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(template) as bundle:
            for name in ["windows_release_x86_64.exe", "windows_debug_x86_64.exe", "version.txt"]:
                (target / name).write_bytes(bundle.read("templates/" + name))
    print(binary)


if __name__ == "__main__":
    main()
