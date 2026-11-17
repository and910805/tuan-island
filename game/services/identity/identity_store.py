"""Closed-beta identity core; no HTTP endpoint or public signup is exposed.

Provisioning methods are operator-only Python APIs, never client RPCs. Credentials
are generated 256-bit secrets, not user passwords. Client/server transport and
world membership authorization must be implemented before public deployment.
"""
from contextlib import contextmanager
import hashlib
import base64
import json
import secrets
import sqlite3
import time
import uuid
from urllib.parse import urlsplit


WORLD_CAPACITY = 8
STATUS_TTL = 35


class Denied(Exception):
    """Deliberately does not echo credentials or distinguish unknown accounts."""


class DirectoryError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def digest(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 256:
        raise Denied("invalid credential")
    try:
        encoded = value.encode("utf-8")
    except UnicodeEncodeError:
        raise Denied("invalid credential") from None
    return hashlib.sha256(encoded).hexdigest()


class IdentityStore:
    SESSION_TTL = 900
    SESSION_MAX_AGE = 28800
    TICKET_TTL = 30

    def __init__(self, path, clock=time.time):
        self.path = str(path)
        self.clock = clock
        with self.transaction() as db:
            version = db.execute("PRAGMA user_version").fetchone()[0]
            if version not in (0, 1, 2, 3, 4):
                raise ValueError("unsupported identity schema")
            # Never silently reinterpret an unrelated existing database.
            tables = db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
            if version == 0 and tables:
                raise ValueError("unrecognized identity database")
            expected = {"accounts": {"id", "name", "secret_hash", "active"},
                        "servers": {"world", "secret_hash"},
                        "sessions": {"hash", "account", "issued", "expires"},
                        "tickets": {"hash", "session", "world", "issued", "expires"}}
            if version >= 2:
                expected["admissions"] = {"id", "session", "world", "issued"}
            if version >= 3:
                expected["directory"] = {"world", "revision", "payload", "seen"}
                expected["directory_members"] = {"world", "account"}
            if version >= 4:
                expected["world_storage"] = {"world", "state", "last_saved", "seen"}
            if version:
                if {row[0] for row in tables} != set(expected):
                    raise ValueError("incomplete identity database")
                for table, columns in expected.items():
                    if {row[1] for row in db.execute("PRAGMA table_info(" + table + ")")} != columns:
                        raise ValueError("incompatible identity schema")
            for statement in (
                "CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL, secret_hash TEXT NOT NULL UNIQUE, active INTEGER NOT NULL CHECK(active IN (0,1)))",
                "CREATE TABLE IF NOT EXISTS servers (world TEXT PRIMARY KEY, secret_hash TEXT NOT NULL UNIQUE)",
                "CREATE TABLE IF NOT EXISTS sessions (hash TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id), issued REAL NOT NULL, expires REAL NOT NULL)",
                "CREATE TABLE IF NOT EXISTS tickets (hash TEXT PRIMARY KEY, session TEXT NOT NULL REFERENCES sessions(hash) ON DELETE CASCADE, world TEXT NOT NULL REFERENCES servers(world), issued REAL NOT NULL, expires REAL NOT NULL)",
                "CREATE TABLE IF NOT EXISTS admissions (id TEXT PRIMARY KEY, session TEXT NOT NULL REFERENCES sessions(hash) ON DELETE CASCADE, world TEXT NOT NULL REFERENCES servers(world), issued REAL NOT NULL)",
                "CREATE TABLE IF NOT EXISTS directory (world TEXT PRIMARY KEY REFERENCES servers(world), revision INTEGER NOT NULL, payload TEXT NOT NULL, seen REAL NOT NULL)",
                "CREATE TABLE IF NOT EXISTS directory_members (world TEXT NOT NULL REFERENCES directory(world) ON DELETE CASCADE, account TEXT NOT NULL REFERENCES accounts(id), PRIMARY KEY(world,account))",
                "CREATE TABLE IF NOT EXISTS world_storage (world TEXT PRIMARY KEY REFERENCES servers(world), state TEXT NOT NULL, last_saved INTEGER NOT NULL, seen REAL NOT NULL)",
            ):
                db.execute(statement)
            db.execute("PRAGMA user_version=4")

    @contextmanager
    def transaction(self):
        db = sqlite3.connect(self.path, isolation_level=None, timeout=5)
        db.row_factory = sqlite3.Row
        try:
            db.execute("PRAGMA foreign_keys=ON")
            db.execute("PRAGMA synchronous=FULL")
            db.execute("BEGIN IMMEDIATE")
            yield db
            db.execute("COMMIT")
        except BaseException:
            if db.in_transaction:
                db.execute("ROLLBACK")
            raise
        finally:
            db.close()

    @staticmethod
    def name(value):
        if not isinstance(value, str) or not value.strip() or len(value.strip()) > 12:
            raise ValueError("display name must contain 1-12 characters")
        if any(ord(c) < 32 for c in value):
            raise ValueError("display name contains control characters")
        return value.strip()

    def provision_account(self, name):
        """Operator-only. Return the generated credential once after commit."""
        account = str(uuid.uuid4())
        secret = secrets.token_urlsafe(32)
        with self.transaction() as db:
            db.execute("INSERT INTO accounts VALUES(?,?,?,1)", (account, self.name(name), digest(secret)))
        return {"account_id": account, "credential": secret}

    def provision_world(self, world):
        """Operator-only. Enroll/rotate this world's backend credential."""
        if not isinstance(world, str) or not 1 <= len(world) <= 64:
            raise ValueError("invalid world id")
        secret = secrets.token_urlsafe(32)
        with self.transaction() as db:
            db.execute("INSERT INTO servers VALUES(?,?) ON CONFLICT(world) DO UPDATE SET secret_hash=excluded.secret_hash", (world, digest(secret)))
            db.execute("DELETE FROM tickets WHERE world=?", (world,))
            db.execute("DELETE FROM admissions WHERE world=?", (world,))
            db.execute("UPDATE directory SET seen=0 WHERE world=?", (world,))
            db.execute("UPDATE world_storage SET seen=0 WHERE world=?", (world,))
        return secret

    def login(self, account, credential):
        token = secrets.token_urlsafe(32)
        with self.transaction() as db:
            now = self.clock()
            row = db.execute("SELECT * FROM accounts WHERE id=?", (account,)).fetchone()
            candidate = digest(credential)
            expected = row["secret_hash"] if row else "0" * 64
            if not secrets.compare_digest(candidate, expected) or not row or not row["active"]:
                raise Denied("invalid credential")
            db.execute("DELETE FROM sessions WHERE expires<=?", (now,))
            db.execute("INSERT INTO sessions VALUES(?,?,?,?)", (digest(token), account, now, now + self.SESSION_TTL))
        return {"session": token, "account_id": account, "display_name": row["name"], "expires": now + self.SESSION_TTL}

    def _session(self, db, token, now):
        row = db.execute("SELECT s.*,a.name,a.active FROM sessions s JOIN accounts a ON a.id=s.account WHERE s.hash=?", (digest(token),)).fetchone()
        if not row or not row["active"] or not row["issued"] <= now < row["expires"]:
            raise Denied("session expired or revoked")
        return row

    def rename(self, session, name):
        with self.transaction() as db:
            row = self._session(db, session, self.clock())
            db.execute("UPDATE accounts SET name=? WHERE id=?", (self.name(name), row["account"]))

    def logout(self, session):
        with self.transaction() as db:
            db.execute("DELETE FROM sessions WHERE hash=?", (digest(session),))

    def refresh(self, session):
        """Keep active play signed in, with an eight-hour absolute lifetime."""
        with self.transaction() as db:
            now = self.clock()
            row = self._session(db, session, now)
            expiry = min(now + self.SESSION_TTL, row["issued"] + self.SESSION_MAX_AGE)
            if expiry <= now:
                raise Denied("session expired or revoked")
            db.execute("UPDATE sessions SET expires=? WHERE hash=?", (expiry, row["hash"]))
        return {"session": session, "account_id": row["account"], "display_name": row["name"], "expires": expiry}

    def rotate_account(self, account):
        """Operator-only; existing sessions and their tickets are revoked."""
        secret = secrets.token_urlsafe(32)
        with self.transaction() as db:
            changed = db.execute("UPDATE accounts SET secret_hash=? WHERE id=?", (digest(secret), account)).rowcount
            if changed != 1:
                raise Denied("unknown account")
            db.execute("DELETE FROM sessions WHERE account=?", (account,))
        return secret

    def disable_account(self, account):
        """Operator-only, including revocation of outstanding join tickets."""
        with self.transaction() as db:
            if db.execute("UPDATE accounts SET active=0 WHERE id=?", (account,)).rowcount != 1:
                raise Denied("unknown account")
            db.execute("DELETE FROM sessions WHERE account=?", (account,))

    def issue_ticket(self, session, world):
        """Identity proof only. World server must separately authorize membership."""
        ticket = secrets.token_urlsafe(32)
        with self.transaction() as db:
            now = self.clock()
            row = self._session(db, session, now)
            if not db.execute("SELECT 1 FROM servers WHERE world=?", (world,)).fetchone():
                raise Denied("world unavailable")
            expiry = min(now + self.TICKET_TTL, row["expires"])
            db.execute("DELETE FROM tickets WHERE expires<=?", (now,))
            db.execute("INSERT INTO tickets VALUES(?,?,?,?,?)", (digest(ticket), row["hash"], world, now, expiry))
        return {"ticket": ticket, "world": world, "expires": expiry}

    def consume_ticket(self, world, server_credential, ticket):
        """Backend-only, atomic single redemption; credentials never reach client."""
        with self.transaction() as db:
            now = self.clock()
            server = db.execute("SELECT secret_hash FROM servers WHERE world=?", (world,)).fetchone()
            expected = server[0] if server else "0" * 64
            if not secrets.compare_digest(digest(server_credential), expected) or not server:
                raise Denied("invalid server credential")
            token_hash = digest(ticket)
            row = db.execute("SELECT t.*,s.account,s.issued AS session_issued,s.expires AS session_expires,a.active,a.name FROM tickets t JOIN sessions s ON s.hash=t.session JOIN accounts a ON a.id=s.account WHERE t.hash=? AND t.world=?", (token_hash, world)).fetchone()
            if not row or not row["active"] or not row["issued"] <= now < row["expires"] or not row["session_issued"] <= now < row["session_expires"]:
                raise Denied("ticket expired or revoked")
            db.execute("DELETE FROM tickets WHERE hash=?", (token_hash,))
            admission = secrets.token_urlsafe(24)
            db.execute("INSERT INTO admissions VALUES(?,?,?,?)", (admission, row["session"], world, now))
            claims = {"account_id": row["account"], "display_name": row["name"], "world": world,
                      "admission_id": admission, "expires": row["session_expires"]}
        return claims

    def validate_admission(self, world, server_credential, admission):
        """Backend heartbeat: logout/disable/rotation invalidates live access."""
        with self.transaction() as db:
            now = self.clock()
            server = db.execute("SELECT secret_hash FROM servers WHERE world=?", (world,)).fetchone()
            expected = server[0] if server else "0" * 64
            if not secrets.compare_digest(digest(server_credential), expected) or not server:
                raise Denied("invalid server credential")
            row = db.execute("SELECT d.*,s.account,s.issued AS session_issued,s.expires,a.active,a.name FROM admissions d JOIN sessions s ON s.hash=d.session JOIN accounts a ON a.id=s.account WHERE d.id=? AND d.world=?", (admission, world)).fetchone()
            if not row or not row["active"] or not row["issued"] <= now < row["expires"] or not row["session_issued"] <= now:
                raise Denied("admission expired or revoked")
            return {"account_id": row["account"], "display_name": row["name"], "world": world,
                    "admission_id": admission, "expires": row["expires"]}

    @staticmethod
    def _server(db, world, credential):
        row = db.execute("SELECT secret_hash FROM servers WHERE world=?", (world,)).fetchone()
        if not secrets.compare_digest(digest(credential), row[0] if row else "0" * 64) or not row:
            raise Denied("invalid server credential")

    @staticmethod
    def _text(value, maximum):
        if not isinstance(value, str) or not 1 <= len(value) <= maximum or not value.strip():
            raise ValueError("invalid text")
        if any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ValueError("invalid text")
        value.encode("utf-8")

    @staticmethod
    def _integer(value, minimum=0, maximum=9007199254740990):
        if type(value) is not int or not minimum <= value <= maximum:
            raise ValueError("invalid integer")

    @staticmethod
    def _validate_snapshot(data, allow_test_loopback):
        expected = {"world_id", "revision", "name", "address", "protocol", "mode", "members", "online", "invite"}
        if not isinstance(data, dict) or set(data) != expected:
            raise ValueError("invalid publication")
        for key, limit in (("world_id", 64), ("name", 64), ("address", 512)):
            IdentityStore._text(data[key], limit)
        IdentityStore._integer(data["revision"], 1)
        IdentityStore._integer(data["protocol"], 1, 100000)
        if data["mode"] not in ("生活", "冒險"):
            raise ValueError("unsupported play mode")
        address = data["address"]
        parsed = urlsplit(address)
        if (not parsed.hostname or parsed.username or parsed.password or "?" in address or "#" in address
                or "\\" in address or any(c.isspace() for c in address) or "%" in parsed.netloc):
            raise ValueError("invalid world address")
        port = parsed.port
        if port is not None and not 1 <= port <= 65535:
            raise ValueError("invalid world port")
        if parsed.scheme != "wss" and not (allow_test_loopback and parsed.scheme == "ws" and parsed.hostname == "127.0.0.1" and port):
            raise ValueError("secure world address required")
        if not isinstance(data["members"], list) or not 1 <= len(data["members"]) <= WORLD_CAPACITY:
            raise ValueError("invalid roster")
        accounts, owners = set(), 0
        for member in data["members"]:
            if not isinstance(member, dict) or set(member) != {"account_id", "name", "role", "last_activity"}:
                raise ValueError("invalid member")
            IdentityStore._text(member["account_id"], 128)
            IdentityStore._text(member["name"], 24)
            IdentityStore._integer(member["last_activity"])
            if member["account_id"] in accounts or member["role"] not in ("owner", "admin", "member"):
                raise ValueError("invalid member identity")
            owners += member["role"] == "owner"
            accounts.add(member["account_id"])
        online = data["online"]
        if owners != 1 or not isinstance(online, list) or not all(isinstance(v, str) for v in online) or len(set(online)) != len(online) or not set(online) <= accounts:
            raise ValueError("invalid presence")
        invitation = data["invite"]
        if not isinstance(invitation, dict) or set(invitation) != {"digest", "generation", "expires"}:
            raise ValueError("invalid invitation metadata")
        IdentityStore._integer(invitation["generation"])
        IdentityStore._integer(invitation["expires"])
        secret_hash = invitation["digest"]
        if not isinstance(secret_hash, str):
            raise ValueError("invalid invitation digest")
        if secret_hash:
            if len(secret_hash) != 64 or any(c not in "0123456789abcdef" for c in secret_hash) or not invitation["generation"] or not invitation["expires"]:
                raise ValueError("invalid invitation digest")
        elif invitation["expires"]:
            raise ValueError("revoked invitation must not expire")

    def publish_directory(self, credential, snapshot, allow_test_loopback=False):
        self._validate_snapshot(snapshot, allow_test_loopback)
        world = snapshot["world_id"]
        encoded = json.dumps(snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        with self.transaction() as db:
            now = self.clock()
            self._server(db, world, credential)
            previous = db.execute("SELECT * FROM directory WHERE world=?", (world,)).fetchone()
            if previous:
                if previous["revision"] == snapshot["revision"] and previous["payload"] == encoded:
                    return {"revision": snapshot["revision"]}  # ACK retry; no liveness extension.
                old = json.loads(previous["payload"])
                if previous["revision"] >= snapshot["revision"] or old["invite"]["generation"] > snapshot["invite"]["generation"]:
                    raise DirectoryError("DIRECTORY_STALE")
                if old["invite"]["generation"] == snapshot["invite"]["generation"] and old["invite"] != snapshot["invite"]:
                    raise DirectoryError("DIRECTORY_STALE")
            for member in snapshot["members"]:
                if not db.execute("SELECT 1 FROM accounts WHERE id=?", (member["account_id"],)).fetchone():
                    raise ValueError("unknown member account")
            db.execute("INSERT INTO directory VALUES(?,?,?,?) ON CONFLICT(world) DO UPDATE SET revision=excluded.revision,payload=excluded.payload,seen=excluded.seen", (world, snapshot["revision"], encoded, now))
            db.execute("DELETE FROM directory_members WHERE world=?", (world,))
            db.executemany("INSERT INTO directory_members VALUES(?,?)", [(world, member["account_id"]) for member in snapshot["members"]])
        return {"revision": snapshot["revision"]}

    @staticmethod
    def _world_card(row, account, now):
        data = json.loads(row["payload"])
        fresh = 0 <= now - row["seen"] < STATUS_TTL
        members = [{"name": m["name"], "role": m["role"], "online": fresh and m["account_id"] in data["online"]} for m in data["members"]]
        me = next((m for m in data["members"] if m["account_id"] == account), None)
        return {"world_id": data["world_id"], "name": data["name"], "address": data["address"], "protocol": data["protocol"], "mode": data["mode"],
                "online": len(data["online"]) if fresh else 0, "capacity": WORLD_CAPACITY, "members_count": len(members), "role": me["role"] if me else "guest",
                "last_activity": max(m["last_activity"] for m in data["members"]), "status": "online" if fresh else "offline", "members": members}

    def report_world_storage(self, credential, data):
        if not isinstance(data, dict) or set(data) != {"world_id", "state", "last_saved"}:
            raise ValueError("invalid storage report")
        world = data["world_id"]
        self._text(world, 64)
        if data["state"] not in ("running", "save_failed", "paused", "recovery_required"):
            raise ValueError("invalid storage state")
        self._integer(data["last_saved"])
        with self.transaction() as db:
            self._server(db, world, credential)
            db.execute("""INSERT INTO world_storage VALUES(?,?,?,?)
                          ON CONFLICT(world) DO UPDATE SET state=excluded.state,
                          last_saved=excluded.last_saved, seen=excluded.seen""",
                       (world, data["state"], data["last_saved"], self.clock()))
        return {}

    def operator_worlds(self, world=None):
        if world is not None:
            self._text(world, 64)
        with self.transaction() as db:
            rows = db.execute("""SELECT s.world, w.state, w.last_saved, w.seen
                                 FROM servers s LEFT JOIN world_storage w ON w.world=s.world
                                 WHERE (? IS NULL OR s.world=?) ORDER BY s.world""", (world, world)).fetchall()
            now = self.clock()
        results = []
        for row in rows:
            if row["seen"] is None:
                alert = "no_report"
            elif not 0 <= now - row["seen"] < STATUS_TTL:
                alert = "unreachable"
            elif row["state"] != "running":
                alert = row["state"]
            elif not row["last_saved"] or not -STATUS_TTL < now - row["last_saved"] < STATUS_TTL:
                alert = "save_unverified"
            else:
                alert = None
            results.append({"world_id": row["world"], "reported_state": row["state"],
                            "last_saved": row["last_saved"] or None, "last_report": int(row["seen"]) if row["seen"] else None,
                            "alert": alert})
        return results

    def list_worlds(self, session, cursor=0):
        self._integer(cursor, 0, 1000000)
        with self.transaction() as db:
            now = self.clock()
            account = self._session(db, session, now)["account"]
            rows = db.execute("SELECT d.* FROM directory d JOIN directory_members m ON m.world=d.world WHERE m.account=? ORDER BY d.world LIMIT 9 OFFSET ?", (account, cursor)).fetchall()
            return {"worlds": [self._world_card(row, account, now) for row in rows[:8]], "next_cursor": cursor + 8 if len(rows) > 8 else None}

    def resolve_invitation(self, session, invitation):
        with self.transaction() as db:
            now = self.clock()
            account = self._session(db, session, now)["account"]
            try:
                if not isinstance(invitation, str) or len(invitation) > 512:
                    raise ValueError()
                prefix, encoded_world, code = invitation.split(".")
                if prefix != "TI1" or not encoded_world or any(c not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" for c in encoded_world):
                    raise ValueError()
                if len(code) != 64 or any(c not in "0123456789abcdef" for c in code):
                    raise ValueError()
                world = base64.urlsafe_b64decode(encoded_world + "=" * (-len(encoded_world) % 4)).decode("utf-8")
                self._text(world, 64)
                if base64.urlsafe_b64encode(world.encode()).decode().rstrip("=") != encoded_world:
                    raise ValueError()
            except (ValueError, UnicodeError):
                raise DirectoryError("INVITE_INVALID") from None
            row = db.execute("SELECT * FROM directory WHERE world=?", (world,)).fetchone()
            if not row:
                raise DirectoryError("INVITE_INVALID")
            data = json.loads(row["payload"])
            invitation = data["invite"]
            if invitation["expires"] <= now or not secrets.compare_digest(invitation["digest"], digest(code)):
                raise DirectoryError("INVITE_INVALID")
            card = self._world_card(row, account, now)
            if card["status"] == "offline":
                raise DirectoryError("WORLD_OFFLINE")
            if card["role"] == "guest" and card["members_count"] >= WORLD_CAPACITY:
                raise DirectoryError("WORLD_FULL")
            # Resolving is discovery, never membership admission.
            return {"world": card, "invitation_code": code}
