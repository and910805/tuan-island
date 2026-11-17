"""Build the Windows update manifest from a finished release ZIP."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
from urllib.parse import unquote, urlsplit
from zipfile import BadZipFile, ZipFile

VERSION = re.compile(r"([0-9]{1,9})\.([0-9]{1,9})(?:\.([0-9]{1,9}))?(?:[-+][0-9A-Za-z.-]+)?")
CLIENTS = {"TuanIsland.exe", "糰糰島.exe"}
LOCK_LIBRARY = "island_world_lock.dll"


def version_parts(version):
    match = VERSION.fullmatch(version)
    if not match:
        raise ValueError(f"Invalid game version: {version}")
    return tuple(int(component or 0) for component in match.groups())


def https_url(value):
    if any(ord(char) <= 32 or ord(char) == 127 for char in value) or any(char in value for char in "\\?#"):
        raise ValueError("Release URLs must be plain HTTPS URLs")
    url = urlsplit(value)
    if url.scheme != "https" or not url.hostname or url.username is not None or "%" in url.netloc:
        raise ValueError("Release URLs must be plain HTTPS URLs")
    return url


def packaged_version(release_metadata):
    version = release_metadata["version"]
    version_parts(version)
    build = release_metadata.get("build")
    if not version.endswith("-dev") or version.count(".") != 1 or build is None:
        return version
    if type(build) not in (int, float) or not 1 <= build <= 999999 or int(build) != build:
        raise ValueError("The development build must be a whole number between 1 and 999999")
    return f"{version.removesuffix('-dev')}.{int(build)}-dev"


def build_manifest(archive, release_metadata, minimum, download_url, archive_url):
    latest = packaged_version(release_metadata)
    if version_parts(minimum) > version_parts(latest):
        raise ValueError("The minimum version cannot be higher than the packaged release")
    https_url(download_url)
    file_url = https_url(archive_url)
    if unquote(PurePosixPath(file_url.path).name) != archive.name:
        raise ValueError("Archive URL must name the exact Windows package")
    with ZipFile(archive) as package:
        entries = [item.filename for item in package.infolist() if not item.is_dir()]
        if any("\\" in name or ":" in name or any(part in ("", ".", "..") for part in name.split("/")) for name in entries):
            raise ValueError("The ZIP contains an invalid Windows install path")
        if len({name.casefold() for name in entries}) != len(entries):
            raise ValueError("The ZIP repeats a Windows install path")
        files = {PurePosixPath(name) for name in entries}
        clients = [item for item in files if item.name in CLIENTS]
        if len(clients) != 1 or clients[0].with_name(LOCK_LIBRARY) not in files:
            raise ValueError("The ZIP must contain one game executable with its storage DLL beside it")
        damaged = package.testzip()
        if damaged is not None:
            raise ValueError(f"The ZIP failed integrity validation: {damaged}")
        binaries = {}
        for entry, output in ((clients[0], "TuanIsland.exe"), (clients[0].with_name(LOCK_LIBRARY), LOCK_LIBRARY)):
            with package.open(str(entry)) as stream:
                binaries[output] = hashlib.file_digest(stream, "sha256").hexdigest()
    with archive.open("rb") as stream:
        size = os.fstat(stream.fileno()).st_size
        sha256 = hashlib.file_digest(stream, "sha256").hexdigest()
    return {
        "latest_version": latest,
        "minimum_version": minimum,
        "download_url": download_url,
        "windows_archive_url": archive_url,
        "windows_archive_bytes": size,
        "windows_archive_sha256": sha256,
        "windows_binary_sha256": binaries,
    }


def sign_manifest(payload, signing_key_path):
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding, rsa

    key = serialization.load_pem_private_key(signing_key_path.read_bytes(), password=None)
    if not isinstance(key, rsa.RSAPrivateKey) or key.key_size < 2048:
        raise ValueError("The release signing key must be RSA with at least 2048 bits")
    signature = key.sign(payload, padding.PKCS1v15(), hashes.SHA256())
    return {
        "algorithm": "rsa-sha256",
        "payload": base64.b64encode(payload).decode("ascii"),
        "signature": base64.b64encode(signature).decode("ascii"),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--release", type=Path, required=True, help="release.json used for the export")
    parser.add_argument("--minimum-version", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--archive-url", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--signing-key", type=Path, help="Private release key in PEM format")
    args = parser.parse_args()
    try:
        metadata = json.loads(args.release.read_text(encoding="utf-8"))
        manifest = build_manifest(args.archive, metadata, args.minimum_version, args.download_url, args.archive_url)
        if args.signing_key:
            payload = json.dumps(manifest, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            manifest = sign_manifest(payload, args.signing_key)
        args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except (BadZipFile, ImportError, ValueError, OSError, KeyError, TypeError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
