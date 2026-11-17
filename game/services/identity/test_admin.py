import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from identity_store import Denied, IdentityStore


class AdminTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)
        self.database = self.folder / "identity.sqlite"

    def tearDown(self):
        self.temp.cleanup()

    def call(self, *args):
        return subprocess.run([sys.executable, str(Path(__file__).with_name("admin.py")), "--database", str(self.database), *args], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=5)

    def test_create_writes_secret_file_without_printing_it(self):
        output = self.folder / "account.json"
        result = self.call("account-create", "--name", "Tester", "--output-file", str(output))
        self.assertEqual(result.returncode, 0)
        account = json.loads(output.read_text(encoding="utf-8"))
        self.assertNotIn(account["credential"], result.stdout + result.stderr)
        self.assertEqual(IdentityStore(self.database).login(**{"account": account["account_id"], "credential": account["credential"]})["account_id"], account["account_id"])

    def test_existing_output_is_preserved_without_creating_account(self):
        output = self.folder / "account.json"
        output.write_text("keep original", encoding="utf-8")
        result = self.call("account-create", "--name", "Tester", "--output-file", str(output))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(output.read_text(encoding="utf-8"), "keep original")
        with IdentityStore(self.database).transaction() as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM accounts").fetchone()[0], 0)

    def test_operator_disable_revokes_login(self):
        store = IdentityStore(self.database)
        account = store.provision_account("Tester")
        result = self.call("account-disable", "--account-id", account["account_id"])
        self.assertEqual(result.returncode, 0)
        with self.assertRaises(Denied):
            store.login(account["account_id"], account["credential"])

    def test_world_status_filters_only_alerts_or_one_world(self):
        store = IdentityStore(self.database)
        key = store.provision_world("healthy")
        store.provision_world("missing")
        store.report_world_storage(key, {"world_id": "healthy", "state": "running", "last_saved": int(store.clock())})
        result = self.call("world-status", "--alerts-only")
        self.assertEqual(result.returncode, 0)
        self.assertEqual([row["world_id"] for row in json.loads(result.stdout)], ["missing"])
        selected = self.call("world-status", "--world-id", "healthy")
        self.assertEqual(selected.returncode, 0)
        self.assertIsNone(json.loads(selected.stdout)[0]["alert"])
        self.assertNotIn(key, selected.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
