import base64
from contextlib import closing
from copy import deepcopy
import hashlib
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from starlette.testclient import TestClient
from app import create_app
from identity_store import Denied, DirectoryError, IdentityStore


class DirectoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "identity.sqlite"
        self.app = create_app(self.path)
        self.store = self.app.state.store
        self.now = 1000.0
        self.store.clock = lambda: self.now
        self.owner = self.store.provision_account("同名")
        self.guest = self.store.provision_account("同名")
        self.owner_session = self.login(self.owner)
        self.guest_session = self.login(self.guest)
        self.world = "台灣小島"
        self.key = self.store.provision_world(self.world)
        self.code = "a" * 64
        self.snapshot = {"world_id": self.world, "revision": 1, "name": "風鈴渡口", "address": "wss://island.example/game", "protocol": 15, "mode": "生活",
            "members": [self.member(self.owner, "owner")], "online": [self.owner["account_id"]],
            "invite": {"digest": hashlib.sha256(self.code.encode()).hexdigest(), "generation": 1, "expires": 1600}}
        self.publish()

    def tearDown(self):
        self.temp.cleanup()

    def member(self, account, role="member"):
        return {"account_id": account["account_id"], "name": "同名", "role": role, "last_activity": 990}

    def login(self, account):
        return self.store.login(account["account_id"], account["credential"])["session"]

    def invitation(self, code=None, world=None):
        encoded = base64.urlsafe_b64encode((world or self.world).encode()).decode().rstrip("=")
        return "TI1." + encoded + "." + (code or self.code)

    def publish(self, snapshot=None):
        return self.store.publish_directory(self.key, snapshot or self.snapshot)

    def resolve(self, code=None):
        return self.store.resolve_invitation(self.guest_session, code or self.invitation())

    def test_private_listing_and_no_implicit_admission(self):
        self.assertEqual(self.store.list_worlds(self.guest_session)["worlds"], [])
        card = self.resolve()["world"]
        self.assertEqual(card["role"], "guest")
        self.assertEqual(self.store.list_worlds(self.guest_session)["worlds"], [])
        self.assertEqual(self.store.list_worlds(self.owner_session)["worlds"][0]["role"], "owner")

    def test_redacted_card_and_distinct_counts(self):
        self.snapshot["revision"] += 1
        self.snapshot["members"].append(self.member(self.guest))
        self.publish()
        card = self.store.list_worlds(self.guest_session)["worlds"][0]
        self.assertEqual((card["online"], card["members_count"]), (1, 2))
        self.assertEqual([m["online"] for m in card["members"]], [True, False])
        encoded = json.dumps(card)
        for secret in (self.owner["account_id"], self.guest["account_id"], self.code, self.snapshot["invite"]["digest"], self.key):
            self.assertNotIn(secret, encoded)

    def test_same_revision_retry_does_not_renew_liveness(self):
        self.now += 34
        self.assertEqual(self.publish()["revision"], 1)
        self.now += 1
        card = self.store.list_worlds(self.owner_session)["worlds"][0]
        self.assertEqual((card["status"], card["online"]), ("offline", 0))
        with self.assertRaisesRegex(DirectoryError, "WORLD_OFFLINE"):
            self.resolve()

    def test_fresh_revision_recovers_after_offline(self):
        self.now += 36
        self.snapshot["revision"] += 1
        self.publish()
        self.assertEqual(self.resolve()["world"]["status"], "online")

    def test_revision_regression_and_changed_equal_revision_rejected(self):
        older = deepcopy(self.snapshot)
        self.snapshot["revision"] = 2
        self.publish()
        with self.assertRaisesRegex(DirectoryError, "DIRECTORY_STALE"):
            self.publish(older)
        changed = deepcopy(self.snapshot)
        changed["name"] = "unexpected replacement"
        with self.assertRaisesRegex(DirectoryError, "DIRECTORY_STALE"):
            self.publish(changed)
        self.assertEqual(self.resolve()["world"]["name"], "風鈴渡口")

    def test_rotation_and_revocation_survive_restart(self):
        old = self.invitation()
        self.snapshot["revision"] += 1
        self.snapshot["invite"] = {"digest": hashlib.sha256(("b" * 64).encode()).hexdigest(), "generation": 2, "expires": 1600}
        self.publish()
        with self.assertRaisesRegex(DirectoryError, "INVITE_INVALID"):
            self.resolve(old)
        self.resolve(self.invitation("b" * 64))
        self.snapshot["revision"] += 1
        self.snapshot["invite"] = {"digest": "", "generation": 3, "expires": 0}
        self.publish()
        self.store = IdentityStore(self.path, lambda: self.now)
        with self.assertRaisesRegex(DirectoryError, "INVITE_INVALID"):
            self.resolve(self.invitation("b" * 64))
        self.assertEqual(len(self.store.list_worlds(self.owner_session)["worlds"]), 1)

    def test_cannot_reintroduce_revoked_generation_with_higher_revision(self):
        old = deepcopy(self.snapshot)
        self.snapshot["revision"] += 1
        self.snapshot["invite"] = {"digest": "", "generation": 2, "expires": 0}
        self.publish()
        old["revision"] = 100
        with self.assertRaisesRegex(DirectoryError, "DIRECTORY_STALE"):
            self.publish(old)
        old["invite"]["generation"] = 2
        with self.assertRaisesRegex(DirectoryError, "DIRECTORY_STALE"):
            self.publish(old)

    def test_invitation_expiration_boundary(self):
        self.snapshot["revision"] += 1
        self.snapshot["invite"]["generation"] += 1
        self.snapshot["invite"]["expires"] = 1001
        self.publish()
        self.now = 1001
        with self.assertRaisesRegex(DirectoryError, "INVITE_INVALID"):
            self.resolve()

    def test_eight_persistent_members_prevent_ninth_even_if_offline_members(self):
        self.snapshot["revision"] += 1
        for _ in range(7):
            self.snapshot["members"].append(self.member(self.store.provision_account("島民")))
        self.publish()
        with self.assertRaisesRegex(DirectoryError, "WORLD_FULL"):
            self.resolve()
        self.assertEqual(self.store.resolve_invitation(self.owner_session, self.invitation())["world"]["online"], 1)

    def test_wrong_server_and_player_credentials_cannot_publish(self):
        other_key = self.store.provision_world("different")
        for wrong in (other_key, self.owner_session, self.owner["credential"]):
            with self.assertRaises(Denied):
                self.store.publish_directory(wrong, self.snapshot)

    def test_failed_snapshot_replacement_preserves_invitation_and_membership_index(self):
        self.snapshot["revision"] += 1
        self.snapshot["members"].append(self.member(self.guest))
        self.snapshot["invite"] = {"digest": "", "generation": 2, "expires": 0}
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("CREATE TRIGGER fail_member BEFORE INSERT ON directory_members BEGIN SELECT RAISE(ABORT, 'injected write error'); END")
        with self.assertRaises(sqlite3.DatabaseError):
            self.publish()
        self.assertEqual(self.resolve()["world"]["members_count"], 1)
        self.assertEqual(self.store.list_worlds(self.guest_session)["worlds"], [])

    def test_unknown_account_does_not_change_directory(self):
        self.snapshot["revision"] += 1
        self.snapshot["members"].append(self.member({"account_id": "unverified-identity"}))
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(self.resolve()["world"]["members_count"], 1)

    def test_pagination_only_contains_my_worlds(self):
        for index in range(9):
            world = "world-%02d" % index
            secret = self.store.provision_world(world)
            snapshot = deepcopy(self.snapshot)
            snapshot["world_id"] = world
            self.store.publish_directory(secret, snapshot)
        first = self.store.list_worlds(self.owner_session)
        second = self.store.list_worlds(self.owner_session, first["next_cursor"])
        self.assertEqual((len(first["worlds"]), len(second["worlds"])), (8, 2))
        self.assertIsNone(second["next_cursor"])
        self.assertEqual(len({w["world_id"] for w in first["worlds"] + second["worlds"]}), 10)
        self.assertEqual(self.store.list_worlds(self.guest_session)["worlds"], [])

    def test_invalid_presence_roster_and_boolean_revision_are_rejected(self):
        changes = ({"online": [self.guest["account_id"]]}, {"revision": True}, {"members": [self.member(self.owner, "member")]}, {"members": [self.member(self.owner, "owner"), self.member(self.owner)]})
        for change in changes:
            with self.subTest(change=list(change)):
                with self.assertRaises(ValueError):
                    self.publish({**self.snapshot, **change})

    def test_unsafe_address_and_test_mode_are_separate(self):
        for address in ("http://world.test", "ws://127.0.0.1:90", "ws://remote.test:90", "wss://a@world.test", "wss://world.test/#", "wss://world.test/?", "wss://world.test:99999", "wss://world.test\\evil"):
            with self.subTest(address=address), self.assertRaises(ValueError):
                self.publish({**self.snapshot, "address": address})
        snapshot = {**self.snapshot, "revision": 2, "address": "ws://127.0.0.1:9000"}
        self.store.publish_directory(self.key, snapshot, allow_test_loopback=True)

    def test_invalid_invitation_forms_never_reveal_world(self):
        for value in ("", "not-an-invite", self.invitation().replace("TI1.", "TI2."), "TI1.a." + self.code, "TI1.====." + self.code, self.invitation("c" * 64)):
            with self.subTest(form=value[:10]), self.assertRaises(DirectoryError):
                self.resolve(value if value else " ")

    def test_unicode_world_id_maximum_roundtrip(self):
        world = "島" * 64
        secret = self.store.provision_world(world)
        snapshot = {**self.snapshot, "world_id": world}
        self.store.publish_directory(secret, snapshot)
        self.assertEqual(self.resolve(self.invitation(world=world))["world"]["world_id"], world)

    def test_logout_denies_list_and_resolve(self):
        self.store.logout(self.owner_session)
        self.store.logout(self.guest_session)
        with self.assertRaises(Denied):
            self.store.list_worlds(self.owner_session)
        with self.assertRaises(Denied):
            self.resolve()

    def test_schema_two_migrates_directory_without_losing_account(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("DROP TABLE directory_members")
            db.execute("DROP TABLE directory")
            db.execute("PRAGMA user_version=2")
        self.store = IdentityStore(self.path, lambda: self.now)
        self.assertEqual(self.store.list_worlds(self.owner_session)["worlds"], [])
        self.publish()
        self.assertEqual(len(self.store.list_worlds(self.owner_session)["worlds"]), 1)

    def test_real_api_shapes_error_codes_and_authority(self):
        with TestClient(self.app, base_url="https://identity.test") as client:
            owner = {"Authorization": "Bearer " + self.owner_session}
            guest = {"Authorization": "Bearer " + self.guest_session}
            self.assertEqual(client.post("/v1/worlds", headers=guest, json={}).json()["worlds"], [])
            response = client.post("/v1/resolve", headers=guest, json={"invitation": self.invitation()})
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json()["world"]["world_id"], self.world)
            self.assertEqual(response.json()["invitation_code"], self.code)
            self.assertEqual(client.post("/v1/publish", headers=owner, json=self.snapshot).status_code, 401)
            self.assertEqual(client.post("/v1/worlds", headers=owner, json={"cursor": True}).status_code, 400)
            response = client.post("/v1/resolve", headers=guest, json={"invitation": self.invitation("c" * 64)})
            self.assertEqual((response.status_code, response.json()["error"]), (404, "INVITE_INVALID"))
            self.now += 35
            response = client.post("/v1/resolve", headers=guest, json={"invitation": self.invitation()})
            self.assertEqual((response.status_code, response.json()["error"]), (409, "WORLD_OFFLINE"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
