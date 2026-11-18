"""Export, verify, and restore stopped authenticated islands or explicit world-only rooms."""
import argparse
from contextlib import closing, contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import stat
import tempfile


WORLD_FILES = ("world.json", "world.json.bak", "world.json.bak.staged", "members.json")
WORLD_GENERATIONS = WORLD_FILES[:3]
REQUIRED = {"world/members.json", "identity/identity.sqlite"}
ALLOWED = {f"world/{name}" for name in WORLD_FILES} | REQUIRED
MANIFEST = "manifest.json"


@contextmanager
def offline_world(folder):
    """Hold the same OS-level lock as the native WorldWriteGuard, not a stale-file test."""
    if folder.is_symlink() or not folder.is_dir():
        raise ValueError("Expected an existing regular world directory")
    path = folder / "world.json.writer-lock"
    if path.is_symlink():
        raise ValueError("World lock must not be a symbolic link")
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes

        class FileInfo(ctypes.Structure):
            _fields_ = [("attributes", wintypes.DWORD), ("created", wintypes.FILETIME),
                        ("accessed", wintypes.FILETIME), ("written", wintypes.FILETIME),
                        ("volume", wintypes.DWORD), ("size_high", wintypes.DWORD),
                        ("size_low", wintypes.DWORD), ("links", wintypes.DWORD),
                        ("index_high", wintypes.DWORD), ("index_low", wintypes.DWORD)]

        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                      ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p]
        kernel.CreateFileW.restype = wintypes.HANDLE
        kernel.GetFileInformationByHandle.argtypes = [wintypes.HANDLE, ctypes.POINTER(FileInfo)]
        kernel.GetFileInformationByHandle.restype = wintypes.BOOL
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel.CloseHandle.restype = wintypes.BOOL
        handle = kernel.CreateFileW(str(path.absolute()), 0xC0000000, 0, None, 4, 0x80 | 0x200000, None)
        if handle == ctypes.c_void_p(-1).value:
            error = ctypes.get_last_error()
            if error in (32, 33):
                raise ValueError("World is still running: stop it before exporting")
            raise OSError(error, "Cannot acquire the world writer lock")
        try:
            info = FileInfo()
            if not kernel.GetFileInformationByHandle(handle, ctypes.byref(info)) or info.attributes & (0x10 | 0x400):
                raise ValueError("World lock is not a regular file")
            yield
        finally:
            kernel.CloseHandle(handle)
    else:
        import fcntl
        fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
        try:
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                raise ValueError("World lock is not a regular file")
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise ValueError("World is still running: stop it before exporting") from error
            yield
        finally:
            os.close(fd)


def digest(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Expected a regular file: {path.name}")
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def copy_private(source, destination):
    with source.open("rb") as original, open(destination, "xb", opener=private_file) as copied:
        shutil.copyfileobj(original, copied)


def private_file(path, flags):
    return os.open(path, flags, 0o600)


@contextmanager
def new_tree(output):
    if output.exists() or output.is_symlink():
        raise ValueError("Output already exists; choose an empty destination name")
    with tempfile.TemporaryDirectory(prefix=".tuan-backup-", dir=output.parent) as work:
        staging = Path(work) / "payload"
        staging.mkdir(mode=0o700)
        for name in ("world", "identity"):
            (staging / name).mkdir(mode=0o700)
        yield staging
        # Reserve the final name before moving data under it. Existing folders are never overwritten.
        output.mkdir(mode=0o700)
        try:
            staging.rename(output / "data")
        except OSError:
            output.rmdir()
            raise


def identity_matches(path, world_id, roster):
    with closing(sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)) as db:
        if db.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
            raise ValueError("Identity database failed the integrity check")
        if not db.execute("SELECT 1 FROM servers WHERE world=?", (world_id,)).fetchone():
            raise ValueError("Identity database has no server with the requested world ID")
        if not db.execute("SELECT 1 FROM accounts WHERE id=?", (roster.get("owner"),)).fetchone():
            raise ValueError("Island owner is missing from the identity database")
        tables = db.execute("SELECT name FROM sqlite_master WHERE name='directory'").fetchone()
        published = db.execute("SELECT revision FROM directory WHERE world=?", (world_id,)).fetchone() if tables else None
        if published and published[0] > roster.get("revision", 0):
            raise ValueError("The identity directory is newer than the roster")


def verify(tree):
    index = tree / MANIFEST
    if index.is_symlink() or not index.is_file() or index.stat().st_size > 8192:
        raise ValueError("Backup manifest is missing or invalid")
    meta = json.loads(index.read_bytes())
    if not isinstance(meta, dict) or type(meta.get("format")) is not int or not isinstance(meta.get("world_id"), str):
        raise ValueError("Unknown backup manifest")
    world_only = meta["format"] == 2 and meta.get("mode") == "world-only"
    if meta["format"] != 1 and not world_only:
        raise ValueError("Unknown backup manifest")
    files = meta.get("sha256")
    required = set() if world_only else REQUIRED
    allowed = {f"world/{name}" for name in WORLD_GENERATIONS} if world_only else ALLOWED
    if not isinstance(files, dict) or not required <= files.keys() <= allowed:
        raise ValueError("Unexpected backup file list")
    for name in ("world", "identity"):
        child = tree / name
        if child.is_symlink() or not child.is_dir():
            raise ValueError(f"Invalid backup directory: {name}")
    actual = {f"{child.name}/{file.name}" for child in (tree / "world", tree / "identity")
              for file in child.iterdir()}
    if actual != files.keys():
        raise ValueError("Backup files do not match the manifest")
    for name, expected in files.items():
        if digest(tree / name) != expected:
            raise ValueError(f"Checksum mismatch: {name}")
    states = 0
    for name in set(files) & {f"world/{name}" for name in WORLD_GENERATIONS}:
        try:
            state = json.loads((tree / name).read_bytes())
        except (ValueError, UnicodeError):
            continue
        states += int(isinstance(state, dict) and isinstance(state.get("players"), dict))
    if not states:
        raise ValueError("Backup has no readable world generation")
    if world_only:
        return meta
    roster = json.loads((tree / "world/members.json").read_bytes())
    if not isinstance(roster, dict):
        raise ValueError("Invalid roster")
    identity_matches(tree / "identity/identity.sqlite", meta["world_id"], roster)
    return meta


def world_sources(folder):
    pending = folder / "members.json.admission-wal"
    if pending.exists() or pending.is_symlink():
        raise ValueError("Pending admission journal: replay it at the original location first")
    return {name: digest(folder / name) for name in WORLD_FILES
            if (folder / name).exists() or (folder / name).is_symlink()}


def _export_authenticated(folder, database, world_id, output):
    if not database.is_file() or database.is_symlink():
        raise ValueError("Expected an existing identity database")
    before = world_sources(folder)
    with new_tree(output) as staging:
        for name in before:
            copy_private(folder / name, staging / "world" / name)
        target = staging / "identity/identity.sqlite"
        with open(target, "xb", opener=private_file):
            pass
        with closing(sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True)) as source:
            with closing(sqlite3.connect(target)) as copied:
                source.backup(copied)
                copied.execute("PRAGMA journal_mode=DELETE")
        if world_sources(folder) != before:
            raise ValueError("World files changed while exporting")
        files = {f"world/{name}": checksum for name, checksum in before.items()}
        files["identity/identity.sqlite"] = digest(target)
        meta = {"format": 1, "world_id": world_id, "created_at": datetime.now(timezone.utc).isoformat(), "sha256": files}
        with open(staging / MANIFEST, "x", encoding="utf-8", opener=private_file) as stream:
            json.dump(meta, stream, indent=2)
        verify(staging)


def export_backup(folder, database, world_id, output):
    with offline_world(folder):
        _export_authenticated(folder, database, world_id, output)


def require_world_only(folder):
    if any(folder.glob("members.json*")):
        raise ValueError("Member data exists: use authenticated export with the matching identity database")


def export_world(folder, world_id, output):
    if not isinstance(world_id, str) or not world_id.strip():
        raise ValueError("Provide a nonempty room/world label")
    with offline_world(folder):
        require_world_only(folder)
        before = world_sources(folder)
        with new_tree(output) as staging:
            for name in before:
                copy_private(folder / name, staging / "world" / name)
            require_world_only(folder)
            if world_sources(folder) != before:
                raise ValueError("World files changed while exporting")
            meta = {"format": 2, "mode": "world-only", "world_id": world_id,
                    "created_at": datetime.now(timezone.utc).isoformat(),
                    "sha256": {f"world/{name}": checksum for name, checksum in before.items()}}
            with open(staging / MANIFEST, "x", encoding="utf-8", opener=private_file) as stream:
                json.dump(meta, stream, indent=2)
            verify(staging)


def restore_backup(backup, output):
    meta = verify(backup)
    with new_tree(output) as staging:
        for name in [*meta["sha256"], MANIFEST]:
            copy_private(backup / name, staging / name)
        verify(staging)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    export = commands.add_parser("export")
    export.add_argument("--world-directory", required=True, type=Path)
    export.add_argument("--identity-database", required=True, type=Path)
    export.add_argument("--world-id", required=True)
    export.add_argument("--output", required=True, type=Path)
    room = commands.add_parser("export-world", help="Stopped password room, without identity or member files")
    room.add_argument("--world-directory", required=True, type=Path)
    room.add_argument("--world-id", required=True, help="Operator's room label, not an identity-service world ID")
    room.add_argument("--output", required=True, type=Path)
    verify_command = commands.add_parser("verify")
    verify_command.add_argument("backup", type=Path)
    restore = commands.add_parser("restore")
    restore.add_argument("backup", type=Path)
    restore.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.command == "export":
            export_backup(args.world_directory, args.identity_database, args.world_id, args.output)
        elif args.command == "export-world":
            export_world(args.world_directory, args.world_id, args.output)
        elif args.command == "verify":
            verify(args.backup / "data")
        else:
            restore_backup(args.backup / "data", args.output)
    except (OSError, ValueError, TypeError, sqlite3.Error) as error:
        parser.exit(1, f"Backup check failed: {error}\n")
    print(f"Backup {args.command} passed")


if __name__ == "__main__":
    main()
