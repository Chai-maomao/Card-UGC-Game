"""Consistent online SQLite backup, retained for fourteen days."""
import argparse
import datetime
import sqlite3
from pathlib import Path


def backup(source, folder):
    target_dir = Path(folder)
    target_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    target = target_dir / ('workshop-' + timestamp + '.sqlite3')
    original = sqlite3.connect('file:' + str(Path(source).resolve()) + '?mode=ro', uri=True)
    copy = sqlite3.connect(target)
    try:
        original.backup(copy)
        if copy.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise RuntimeError('Backup integrity check failed')
    finally:
        copy.close()
        original.close()
    target.chmod(0o600)
    cutoff = datetime.datetime.now(datetime.timezone.utc).timestamp() - 14 * 86400
    for old in target_dir.glob('workshop-*.sqlite3'):
        if old.is_file() and old.stat().st_mtime < cutoff:
            old.unlink()
    print('Workshop backup verified:', target.name)
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', required=True)
    parser.add_argument('--folder', required=True)
    args = parser.parse_args()
    backup(args.db, args.folder)
