"""Check the public identity HTTPS and world WebSocket entry points."""
import argparse
import base64
import hashlib
import json
import os
import socket
import ssl
import sys
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, HTTPSHandler, build_opener


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def endpoint(value, scheme):
    if any(ord(char) <= 32 or ord(char) > 126 for char in value):
        raise ValueError("Endpoint must use an ASCII URL without whitespace")
    url = urlsplit(value)
    if url.scheme != scheme or not url.hostname or url.username or url.password or url.fragment:
        raise ValueError(f"Expected a {scheme} URL without credentials or fragment")
    return url


def check_identity(url, context):
    opener = build_opener(NoRedirect(), HTTPSHandler(context=context))
    with opener.open(url.geturl(), timeout=8) as response:
        if response.status != 200:
            raise ValueError("Identity health did not return HTTPS 200")
        data = response.read(8193)
    if len(data) > 8192:
        raise ValueError("Identity health response is too large")
    health = json.loads(data)
    if (not isinstance(health, dict) or health.get("ok") is not True
        or health.get("service") != "tuan-identity" or type(health.get("schema")) is not int):
        raise ValueError("Unexpected identity health response")


def check_world(url, context):
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    expected = base64.b64encode(
        hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
    ).decode("ascii")
    target = url.path or "/"
    if url.query:
        target += "?" + url.query
    host = url.netloc
    request = (
        f"GET {target} HTTP/1.1\r\nHost: {host}\r\n"
        "Upgrade: websocket\r\nConnection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
    )
    with socket.create_connection((url.hostname, url.port or 443), timeout=8) as tcp:
        with context.wrap_socket(tcp, server_hostname=url.hostname) as stream:
            stream.sendall(request.encode("ascii"))
            data = b""
            while b"\r\n\r\n" not in data and len(data) < 16384:
                chunk = stream.recv(4096)
                if not chunk:
                    break
                data += chunk
    header, separator, _ = data.partition(b"\r\n\r\n")
    if not separator:
        raise ValueError("Incomplete WebSocket response")
    status, *fields = header.decode("iso-8859-1").split("\r\n")
    headers = dict((name.lower(), value.strip()) for name, value in (f.split(":", 1) for f in fields))
    if (status.split()[1:2] != ["101"]
        or headers.get("upgrade", "").lower() != "websocket"
        or "upgrade" not in {x.strip().lower() for x in headers.get("connection", "").split(",")}
        or headers.get("sec-websocket-accept") != expected):
        raise ValueError(f"WebSocket upgrade failed ({status})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity-health", help="Full https:// URL for /healthz")
    parser.add_argument("--world", help="Public wss:// world URL")
    parser.add_argument("--ca-file", help="Optional CA for a local test certificate")
    args = parser.parse_args()
    if not args.identity_health and not args.world:
        parser.error("provide --identity-health, --world, or both")
    context = ssl.create_default_context(cafile=args.ca_file)
    checks = (
        (args.identity_health, "https", check_identity, "identity HTTPS and certificate"),
        (args.world, "wss", check_world, "world WSS upgrade and certificate"),
    )
    failed = False
    for url, scheme, check, label in checks:
        if not url:
            continue
        try:
            check(endpoint(url, scheme), context)
        except (OSError, ValueError) as exc:
            print(f"FAIL {label}: {exc}", file=sys.stderr)
            failed = True
        else:
            print(f"PASS {label}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
