"""No provisioning or account management endpoints are exposed."""
import argparse
import ipaddress
import uvicorn
from app import create_app


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8081)
    parser.add_argument("--tls-cert")
    parser.add_argument("--tls-key")
    parser.add_argument("--trusted-proxy", action="append", default=[])
    parser.add_argument("--test-loopback", action="store_true")
    args = parser.parse_args()
    if bool(args.tls_cert) != bool(args.tls_key):
        parser.error("TLS requires both certificate and key")
    if args.test_loopback and args.host not in ("127.0.0.1", "::1"):
        parser.error("test mode may only bind loopback")
    for proxy in args.trusted_proxy:
        try:
            ipaddress.ip_address(proxy)
        except ValueError:
            parser.error("trusted proxy must be a specific IP, never a wildcard")
    if not args.test_loopback and not args.tls_cert and not args.trusted_proxy:
        parser.error("configure TLS or explicit trusted TLS proxy")
    uvicorn.run(create_app(args.database, args.test_loopback), host=args.host, port=args.port,
                ssl_certfile=args.tls_cert, ssl_keyfile=args.tls_key,
                proxy_headers=bool(args.trusted_proxy), forwarded_allow_ips=",".join(args.trusted_proxy),
                access_log=False, limit_concurrency=64, timeout_keep_alive=5)


if __name__ == "__main__":
    main()
