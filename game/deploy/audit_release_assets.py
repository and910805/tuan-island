"""Inventory the resources actually shipped in Godot 4.7 desktop exports."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import struct


GAME = Path(__file__).resolve().parents[1]
NOTICES = ("assets/fonts/OFL.txt", "native/world_lock/LICENSE.txt")
ASSET_EXTENSIONS = {".png", ".svg", ".jpg", ".jpeg", ".webp", ".ttf", ".otf", ".ogg", ".wav", ".mp3"}


def read_fields(stream, layout):
    return struct.unpack(layout, stream.read(struct.calcsize(layout)))


def pack_index(stream):
    stream.seek(-12, 2)
    footer = stream.tell()
    length, magic = read_fields(stream, "<Q4s")
    start = footer - length
    if magic != b"GDPC" or start < 0:
        raise ValueError("expected an executable with an embedded Godot pack")
    stream.seek(start)
    magic, version, major, minor, _, flags, data_base, directory = read_fields(stream, "<4s5I2Q")
    if magic != b"GDPC" or (version, major, minor, flags) != (4, 4, 7, 2):
        raise ValueError("expected an unencrypted Godot 4.7 pack with relative offsets")
    if not 40 <= data_base <= directory < length:
        raise ValueError("pack directory is out of bounds")
    stream.seek(start + directory)
    count, = read_fields(stream, "<I")
    if count > (footer - stream.tell()) // 41:
        raise ValueError("pack entry count is out of bounds")
    entries = {}
    for _ in range(count):
        path_bytes, = read_fields(stream, "<I")
        if not 0 < path_bytes <= footer - stream.tell() - 36:
            raise ValueError("pack path length is out of bounds")
        name = stream.read(path_bytes).rstrip(b"\x00").decode("utf-8")
        offset, size, digest, entry_flags = read_fields(stream, "<QQ16sI")
        if name in entries or entry_flags != 0 or offset + size > directory - data_base:
            raise ValueError(f"invalid pack entry: {name}")
        entries[name] = (start + data_base + offset, size, digest.hex())
    return entries


def read_entry(stream, entry):
    offset, size, _ = entry
    stream.seek(offset)
    return stream.read(size)


def is_forbidden(path):
    parts = PurePosixPath(path).parts
    return (
        parts[0] in {"work", "tests", "docs"}
        or path.startswith("assets/") and "source" in parts[2:-1]
        or "editor_settings" in parts[-1]
    )


def related_source(path):
    source = GAME / path
    base = source.parent
    # These records are leads for human review. A folder record may describe
    # its initial atlas only, while later sprites have independent sources.
    exact = base / f"{source.stem}-source.md"
    records = sorted(base.glob("*provenance.json")) + sorted(base.glob("*generation-record.json"))
    if (base / "README.md").is_file():
        records.append(base / "README.md")
    if path == "assets/fonts/NotoSansTC-VF.ttf":
        return [NOTICES[0]]
    if path.startswith("assets/music/") and source.suffix == ".ogg":
        recipe = (base / "compose.py").read_text(encoding="utf-8")
        cave_floor = source.stem.removeprefix("mine_") if source.stem.startswith("mine_") else ""
        if f'"{source.stem}":' in recipe or cave_floor in {str(floor) for floor in range(1, 16)}:
            records.append(base / "compose.py")
    if exact.is_file():
        records.insert(0, exact)
    return [record.relative_to(GAME).as_posix() for record in records]


def audit(binary):
    with binary.open("rb") as stream:
        entries = pack_index(stream)
        forbidden = sorted(name for name in entries if is_forbidden(name))
        notice_status = {
            path: path in entries and read_entry(stream, entries[path]) == (GAME / path).read_bytes()
            for path in NOTICES
        }
        assets = []
        missing_payloads = []
        payload_checks = {}
        for name, entry in sorted(entries.items()):
            if not name.startswith("assets/"):
                continue
            resource = name.removesuffix(".import")
            extension = PurePosixPath(resource).suffix.lower()
            if extension not in ASSET_EXTENSIONS:
                continue
            payloads = [name]
            if name.endswith(".import"):
                text = read_entry(stream, entry).decode("utf-8")
                payloads = [line.split('"')[1].removeprefix("res://") for line in text.splitlines()
                            if line.startswith(("path=", "path.")) and '"res://' in line]
                if not payloads or any(path not in entries for path in payloads):
                    missing_payloads.append(resource)
            present = {path: entries[path][2] for path in payloads if path in entries}
            for path, expected in present.items():
                if path not in payload_checks:
                    payload_checks[path] = hashlib.md5(read_entry(stream, entries[path])).hexdigest() == expected
            assets.append({
                "resource": resource,
                "payloads": present,
                "related_source_records": related_source(resource),
            })
        if "release.json" not in entries:
            raise ValueError("missing embedded release.json")
        release = json.loads(read_entry(stream, entries["release.json"]))
    with binary.open("rb") as stream:
        checksum = hashlib.file_digest(stream, "sha256").hexdigest()
    corrupted_payloads = sorted(path for path, valid in payload_checks.items() if not valid)
    return {
        "binary": binary.name,
        "sha256": checksum,
        "build": release["build"],
        "protocol": release["protocol"],
        "pack_entries": len(entries),
        "notices_match_source": notice_status,
        "forbidden_entries": forbidden,
        "missing_asset_payloads": missing_payloads,
        "corrupted_asset_payloads": corrupted_payloads,
        "assets": assets,
        "passed_pack_checks": (
            bool(assets) and not forbidden and not missing_payloads
            and not corrupted_payloads and all(notice_status.values())
        ),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path, nargs="+")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    reports = [audit(binary) for binary in args.export]
    args.output.write_text(json.dumps(reports, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for report in reports:
        print(f"{report['binary']}: {len(report['assets'])} assets, "
              f"{len(report['forbidden_entries'])} excluded entries, "
              f"pack checks {'passed' if report['passed_pack_checks'] else 'failed'}")
    return 0 if all(report["passed_pack_checks"] for report in reports) else 1


if __name__ == "__main__":
    raise SystemExit(main())
