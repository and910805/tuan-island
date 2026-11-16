"""Native-game identity API. Run behind TLS or use explicit loopback QA mode."""
import asyncio
from collections import defaultdict, deque
import json
import sqlite3
import time

from starlette.applications import Starlette
from starlette.concurrency import run_in_threadpool
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

from identity_store import Denied, DirectoryError, IdentityStore


MESSAGES = {
    "INVALID_REQUEST": "資料格式不正確，請重新輸入。",
    "AUTH_INVALID": "身分憑證無效或已到期，請重新登入。",
    "RATE_LIMITED": "操作太頻繁，請稍後再試。",
    "STORAGE_UNAVAILABLE": "身分服務暫時無法保存，請稍後重試。",
    "HTTPS_REQUIRED": "請使用安全連線。",
    "BODY_TOO_LARGE": "資料超過允許大小。",
    "REQUEST_TIMEOUT": "連線逾時，請重試。",
    "INVITE_INVALID": "這封邀請已過期、已撤銷或無效，請向朋友索取新邀請。",
    "WORLD_OFFLINE": "這座島暫時沒有回應，請稍後再試。",
    "WORLD_FULL": "這座島的四個成員席位已滿。",
    "DIRECTORY_STALE": "目錄版本衝突，尚未發布這次變更。",
}


def reply(data, status=200):
    return JSONResponse(data, status_code=status, headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"})


def error(code, status):
    return reply({"ok": False, "error": code, "message": MESSAGES[code]}, status)


class BadRequest(Exception):
    pass


class TooLarge(Exception):
    pass


def strict_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise BadRequest()
        result[key] = value
    return result


async def payload(request):
    if request.headers.get("content-type", "").split(";", 1)[0].strip().lower() != "application/json":
        raise BadRequest()
    body = bytearray()
    async with asyncio.timeout(5):
        async for chunk in request.stream():
            if len(body) + len(chunk) > 8192:
                raise TooLarge()
            body.extend(chunk)
    data = json.loads(bytes(body).decode("utf-8"), object_pairs_hook=strict_object)
    if not isinstance(data, dict):
        raise BadRequest()
    return data


def fields(data, expected):
    if set(data) != set(expected):
        raise BadRequest()
    for name, limit in expected.items():
        value = data[name]
        if not isinstance(value, str) or not 1 <= len(value) <= limit:
            raise BadRequest()
        try:
            value.encode("utf-8")
        except UnicodeEncodeError:
            raise BadRequest() from None
        if any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise BadRequest()


def bearer(request):
    if len(request.headers.getlist("authorization")) != 1:
        raise Denied()
    parts = request.headers["authorization"].split(" ")
    if len(parts) != 2 or parts[0] != "Bearer" or not 1 <= len(parts[1]) <= 256:
        raise Denied()
    return parts[1]


class RateLimit:
    """Per-process bounded buckets; deploy a single service worker initially."""
    def __init__(self):
        self.entries = defaultdict(deque)

    def allow(self, key, limit, now):
        for stale in [k for k, q in self.entries.items() if not q or q[-1] <= now - 60]:
            del self.entries[stale]
        if key not in self.entries and len(self.entries) >= 4096:
            return False
        bucket = self.entries[key]
        while bucket and bucket[0] <= now - 60:
            bucket.popleft()
        if len(bucket) >= limit:
            return False
        bucket.append(now)
        return True


def create_app(database, allow_test_loopback=False):
    store = IdentityStore(database)
    limiter = RateLimit()

    async def endpoint(request: Request):
        # Uvicorn must trust forwarded scheme/IP only from configured TLS proxy.
        # No X-Forwarded-* interpretation here and no wildcard proxy trust.
        host = request.client.host if request.client else ""
        if request.url.scheme != "https" and not (allow_test_loopback and host in ("127.0.0.1", "::1", "testclient")):
            return error("HTTPS_REQUIRED", 400)
        operation = request.url.path.rsplit("/", 1)[-1]
        limit = 20 if operation == "login" else 180
        if not limiter.allow((host, operation), limit, time.monotonic()):
            response = error("RATE_LIMITED", 429)
            response.headers["Retry-After"] = "60"
            return response
        try:
            data = await payload(request)
            if operation == "login":
                fields(data, {"account_id": 128, "credential": 256})
                result = await run_in_threadpool(store.login, data["account_id"], data["credential"])
            elif operation == "logout":
                fields(data, {})
                await run_in_threadpool(store.logout, bearer(request))
                result = {}
            elif operation == "refresh":
                fields(data, {})
                result = await run_in_threadpool(store.refresh, bearer(request))
            elif operation == "profile":
                fields(data, {"display_name": 12})
                await run_in_threadpool(store.rename, bearer(request), data["display_name"])
                result = {"display_name": data["display_name"].strip()}
            elif operation == "tickets":
                fields(data, {"world_id": 64})
                result = await run_in_threadpool(store.issue_ticket, bearer(request), data["world_id"])
            elif operation == "publish":
                result = await run_in_threadpool(store.publish_directory, bearer(request), data, allow_test_loopback)
            elif operation == "worlds":
                if set(data) not in (set(), {"cursor"}):
                    raise BadRequest()
                result = await run_in_threadpool(store.list_worlds, bearer(request), data.get("cursor", 0))
            elif operation == "resolve":
                fields(data, {"invitation": 512})
                result = await run_in_threadpool(store.resolve_invitation, bearer(request), data["invitation"])
            elif operation == "redeem":
                fields(data, {"world_id": 64, "ticket": 256})
                result = await run_in_threadpool(store.consume_ticket, data["world_id"], bearer(request), data["ticket"])
            else:
                fields(data, {"world_id": 64, "admission_id": 256})
                result = await run_in_threadpool(store.validate_admission, data["world_id"], bearer(request), data["admission_id"])
            if isinstance(result.get("world"), str):
                result["world_id"] = result.pop("world")
            return reply({"ok": True, **result})
        except DirectoryError as problem:
            return error(problem.code, 404 if problem.code == "INVITE_INVALID" else 409)
        except Denied:
            return error("AUTH_INVALID", 401)
        except TooLarge:
            return error("BODY_TOO_LARGE", 413)
        except TimeoutError:
            return error("REQUEST_TIMEOUT", 408)
        except (BadRequest, ValueError, UnicodeError, RecursionError):
            return error("INVALID_REQUEST", 400)
        except (sqlite3.Error, OSError):
            return error("STORAGE_UNAVAILABLE", 503)

    async def health(_request):
        try:
            with store.transaction() as db:
                db.execute("SELECT COUNT(*) FROM accounts").fetchone()
            return reply({"ok": True, "service": "tuan-identity", "schema": 3})
        except (sqlite3.Error, OSError):
            return error("STORAGE_UNAVAILABLE", 503)

    routes = [Route("/v1/" + name, endpoint, methods=["POST"]) for name in ("login", "logout", "refresh", "profile", "tickets", "redeem", "validate", "publish", "worlds", "resolve")]
    routes.append(Route("/healthz", health, methods=["GET"]))
    app = Starlette(routes=routes, debug=False)
    app.state.store = store
    return app
