import concurrent.futures
from contextlib import closing
import sqlite3
import tempfile
import threading
import unittest
from unittest.mock import patch
from pathlib import Path

from identity_store import Denied, IdentityStore


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "identity.sqlite"
        self.now = 1000.0
        self.store = IdentityStore(self.path, lambda: self.now)
        self.account = self.store.provision_account("小糰")
        self.server = self.store.provision_world("island-a")

    def tearDown(self):
        self.temp.cleanup()

    def login(self):
        return self.store.login(self.account["account_id"], self.account["credential"])["session"]

    def ticket(self, session=None):
        return self.store.issue_ticket(session or self.login(), "island-a")["ticket"]

    def consume(self, ticket):
        return self.store.consume_ticket("island-a", self.server, ticket)

    def test_same_name_does_not_share_identity(self):
        other = self.store.provision_account("小糰")
        self.assertNotEqual(other["account_id"], self.account["account_id"])
        with self.assertRaises(Denied):
            self.store.login(self.account["account_id"], other["credential"])

    def test_client_chosen_old_profile_is_not_login(self):
        with self.assertRaises(Denied):
            self.store.login("legacy-profile", "legacy-profile")

    def test_rename_preserves_account_and_current_ticket(self):
        session = self.login()
        ticket = self.ticket(session)
        self.store.rename(session, "新名字")
        claims = self.consume(ticket)
        self.assertEqual({key: claims[key] for key in ("account_id", "display_name", "world")}, {"account_id": self.account["account_id"], "display_name": "新名字", "world": "island-a"})

    def test_invitation_is_not_session(self):
        with self.assertRaises(Denied):
            self.store.issue_ticket("world-invitation", "island-a")

    def test_session_expiry_boundary(self):
        session = self.login()
        self.now += 900
        with self.assertRaises(Denied):
            self.ticket(session)

    def test_ticket_expiry_boundary(self):
        ticket = self.ticket()
        self.now += 30
        with self.assertRaises(Denied):
            self.consume(ticket)

    def test_clock_rollback_rejects_future_tokens(self):
        session = self.login()
        ticket = self.ticket(session)
        self.now -= 1
        with self.assertRaises(Denied):
            self.ticket(session)
        with self.assertRaises(Denied):
            self.consume(ticket)

    def test_ticket_cannot_outlive_session(self):
        session = self.login()
        self.now += 895
        ticket = self.store.issue_ticket(session, "island-a")
        self.assertEqual(ticket["expires"], 1900)
        self.now = 1900
        with self.assertRaises(Denied):
            self.consume(ticket["ticket"])

    def test_wrong_world_and_wrong_server_do_not_burn_ticket(self):
        other_server = self.store.provision_world("island-b")
        ticket = self.ticket()
        with self.assertRaises(Denied):
            self.store.consume_ticket("island-b", other_server, ticket)
        with self.assertRaises(Denied):
            self.store.consume_ticket("island-a", other_server, ticket)
        self.assertEqual(self.consume(ticket)["world"], "island-a")

    def test_single_use_and_restart(self):
        ticket = self.ticket()
        self.store = IdentityStore(self.path, lambda: self.now)
        self.consume(ticket)
        self.store = IdentityStore(self.path, lambda: self.now)
        with self.assertRaises(Denied):
            self.consume(ticket)

    def test_concurrent_redemption_one_success(self):
        ticket = self.ticket()
        def redeem(_):
            try:
                return bool(self.consume(ticket))
            except Denied:
                return False
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            self.assertEqual(sum(pool.map(redeem, range(8))), 1)

    def test_logout_revokes_unredeemed_tickets(self):
        session = self.login()
        ticket = self.ticket(session)
        self.store.logout(session)
        with self.assertRaises(Denied):
            self.consume(ticket)

    def test_account_rotation_revokes_old_login_session_ticket(self):
        session = self.login()
        ticket = self.ticket(session)
        replacement = self.store.rotate_account(self.account["account_id"])
        with self.assertRaises(Denied):
            self.login()
        with self.assertRaises(Denied):
            self.ticket(session)
        with self.assertRaises(Denied):
            self.consume(ticket)
        self.assertEqual(self.store.login(self.account["account_id"], replacement)["account_id"], self.account["account_id"])

    def test_disabled_account_revokes_all_sessions(self):
        ticket = self.ticket()
        self.store.disable_account(self.account["account_id"])
        with self.assertRaises(Denied):
            self.login()
        with self.assertRaises(Denied):
            self.consume(ticket)

    def test_server_rotation_invalidates_previous_tickets(self):
        ticket = self.ticket()
        self.server = self.store.provision_world("island-a")
        with self.assertRaises(Denied):
            self.consume(ticket)
        self.consume(self.ticket())

    def test_database_has_no_raw_credentials(self):
        session = self.login()
        ticket = self.ticket(session)
        with closing(sqlite3.connect(self.path)) as db, db:
            dump = "\n".join(db.iterdump())
        for secret in (self.account["credential"], self.server, session, ticket):
            self.assertNotIn(secret, dump)

    def test_failed_redemption_is_rolled_back_before_claims(self):
        ticket = self.ticket()
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("CREATE TRIGGER fail_delete BEFORE DELETE ON tickets BEGIN SELECT RAISE(ABORT, 'injected disk transaction error'); END")
        with self.assertRaises(sqlite3.DatabaseError):
            self.consume(ticket)
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("DROP TRIGGER fail_delete")
        self.consume(ticket)

    def test_failed_login_does_not_return_session(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("CREATE TRIGGER fail_insert BEFORE INSERT ON sessions BEGIN SELECT RAISE(ABORT, 'injected error'); END")
        with self.assertRaises(sqlite3.DatabaseError):
            self.login()
        with closing(sqlite3.connect(self.path)) as db, db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM sessions").fetchone()[0], 0)

    def test_corrupt_file_is_not_replaced(self):
        corrupt = Path(self.temp.name) / "broken.sqlite"
        corrupt.write_bytes(b"preserve this corrupt original")
        with self.assertRaises(sqlite3.DatabaseError):
            IdentityStore(corrupt)
        self.assertEqual(corrupt.read_bytes(), b"preserve this corrupt original")

    def test_unrelated_database_is_not_migrated(self):
        unrelated = Path(self.temp.name) / "other.sqlite"
        with closing(sqlite3.connect(unrelated)) as db, db:
            db.execute("CREATE TABLE important (value TEXT)")
            db.execute("INSERT INTO important VALUES('keep')")
        with self.assertRaises(ValueError):
            IdentityStore(unrelated)
        with closing(sqlite3.connect(unrelated)) as db, db:
            self.assertEqual(db.execute("SELECT * FROM important").fetchone()[0], "keep")
            self.assertEqual(db.execute("PRAGMA user_version").fetchone()[0], 0)

    def test_invalid_utf8_credential_is_denied(self):
        with self.assertRaises(Denied):
            self.store.login(self.account["account_id"], "\ud800")

    def wait_across_expiry(self, operation, expired_time):
        # Observe BEGIN from a second real connection while the first owns the
        # writer lock. No timing sleeps; advance the clock before releasing it.
        connect = sqlite3.connect
        attempted = threading.Event()
        def observed_connect(*args, **kwargs):
            db = connect(*args, **kwargs)
            db.set_trace_callback(lambda sql: attempted.set() if sql == "BEGIN IMMEDIATE" else None)
            return db
        with closing(connect(self.path, isolation_level=None)) as blocker:
            blocker.execute("BEGIN IMMEDIATE")
            with patch("identity_store.sqlite3.connect", observed_connect):
                with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                    future = pool.submit(operation)
                    try:
                        self.assertTrue(attempted.wait(2), "worker must reach transaction begin")
                        self.now = expired_time
                    finally:
                        blocker.execute("COMMIT")
                    with self.assertRaises(Denied):
                        future.result(timeout=3)

    def test_ticket_expires_while_waiting_for_writer_lock(self):
        ticket = self.ticket()
        self.now = 1029
        self.wait_across_expiry(lambda: self.consume(ticket), 1030)

    def test_session_expires_while_waiting_to_issue_ticket(self):
        session = self.login()
        self.now = 1899
        self.wait_across_expiry(lambda: self.ticket(session), 1900)

    def test_live_admission_logout_revoke(self):
        session = self.login()
        admission = self.consume(self.ticket(session))["admission_id"]
        self.assertEqual(self.store.validate_admission("island-a", self.server, admission)["account_id"], self.account["account_id"])
        self.store.logout(session)
        with self.assertRaises(Denied):
            self.store.validate_admission("island-a", self.server, admission)

    def test_live_admission_requires_backend_secret_and_world(self):
        admission = self.consume(self.ticket())["admission_id"]
        other = self.store.provision_world("island-b")
        with self.assertRaises(Denied):
            self.store.validate_admission("island-b", other, admission)
        with self.assertRaises(Denied):
            self.store.validate_admission("island-a", "bad", admission)

    def test_live_admission_expiry(self):
        admission = self.consume(self.ticket())["admission_id"]
        self.now = 1900
        with self.assertRaises(Denied):
            self.store.validate_admission("island-a", self.server, admission)

    def test_live_admission_disabled(self):
        admission = self.consume(self.ticket())["admission_id"]
        self.store.disable_account(self.account["account_id"])
        with self.assertRaises(Denied):
            self.store.validate_admission("island-a", self.server, admission)

    def test_schema_one_migrates_preserving_identity(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("DROP TABLE directory_members")
            db.execute("DROP TABLE directory")
            db.execute("DROP TABLE admissions")
            db.execute("PRAGMA user_version=1")
        self.store = IdentityStore(self.path, lambda: self.now)
        self.assertTrue(self.login())
        self.consume(self.ticket())

    def test_missing_table_fails_closed_instead_of_recreating_accounts(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("DROP TABLE accounts")
        with self.assertRaises(ValueError):
            IdentityStore(self.path)
        with closing(sqlite3.connect(self.path)) as db, db:
            self.assertIsNone(db.execute("SELECT name FROM sqlite_master WHERE name='accounts'").fetchone())

    def test_refresh_extends_live_admission_without_relogin(self):
        session = self.login()
        admission = self.consume(self.ticket(session))["admission_id"]
        self.now = 1800
        response = self.store.refresh(session)
        self.assertEqual(response["session"], session)
        self.assertEqual(response["expires"], 2700)
        self.now = 2000
        self.assertEqual(self.store.validate_admission("island-a", self.server, admission)["expires"], 2700)

    def test_refresh_cannot_revive_logged_out_or_expired_session(self):
        session = self.login()
        self.store.logout(session)
        with self.assertRaises(Denied):
            self.store.refresh(session)
        session = self.login()
        self.now = 1900
        with self.assertRaises(Denied):
            self.store.refresh(session)

    def test_continuous_refresh_stops_at_eight_hour_absolute_limit(self):
        session = self.login()
        for elapsed in range(600, 28800, 600):
            self.now = 1000 + elapsed
            self.assertLessEqual(self.store.refresh(session)["expires"], 29800)
        self.now = 29800
        with self.assertRaises(Denied):
            self.store.refresh(session)


if __name__ == "__main__":
    unittest.main(verbosity=2)
