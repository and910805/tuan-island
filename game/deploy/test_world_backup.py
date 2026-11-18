import json
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

import world_backup as backup


class BackupModes(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tuan-room-backup-test-")
        self.root = Path(self.temp.name).resolve()
        assert self.root.is_relative_to(Path(tempfile.gettempdir()).resolve()) and self.root.name.startswith("tuan-room-backup-test-")
        self.source = self.root / "source"
        self.source.mkdir()
        self.world = {"players": {"fixture-owner": {"coins": 257}}, "objects": {"4,5": {"type": "chest", "items": {"wood": 3}}}}
        (self.source / "world.json").write_text(json.dumps(self.world), encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def export(self, name="export"):
        target = self.root / name
        backup.export_world(self.source, "fixture-room", target)
        return target

    def test_world_only_roundtrip_and_stale_lock(self):
        before = (self.source / "world.json").read_bytes()
        exported = self.export()
        meta = backup.verify(exported / "data")
        self.assertEqual((meta["format"], meta["mode"]), (2, "world-only"))
        self.assertEqual(set(meta["sha256"]), {"world/world.json"})
        restored = self.root / "restored"
        backup.restore_backup(exported / "data", restored)
        self.assertEqual((restored / "data/world/world.json").read_bytes(), before)
        self.assertEqual((self.source / "world.json").read_bytes(), before)
        self.assertTrue((self.source / "world.json.writer-lock").exists())
        self.export("second")  # Persisted native lock file is not evidence of a live writer.

    def test_held_native_style_lock_rejected_without_output(self):
        with backup.offline_world(self.source):
            with self.assertRaisesRegex(ValueError, "still running"):
                self.export()
        self.assertFalse((self.root / "export").exists())

    def test_members_or_journal_cannot_silently_be_omitted(self):
        for name in ["members.json", "members.json.bak", "members.json.admission-wal"]:
            with self.subTest(name=name):
                path = self.source / name
                path.write_text("{}", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "Member data"):
                    self.export()
                path.unlink()
                self.assertFalse((self.root / "export").exists())

    def test_no_overwrite_on_export_or_restore(self):
        exported = self.export()
        sentinel = exported / "keep.txt"
        sentinel.write_text("keep", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.export()
        with self.assertRaisesRegex(ValueError, "already exists"):
            backup.restore_backup(exported / "data", exported)
        self.assertEqual(sentinel.read_text(), "keep")

    def test_valid_backup_generation_can_survive_corrupt_main(self):
        (self.source / "world.json.bak.staged").write_text(json.dumps(self.world))
        (self.source / "world.json").write_text("broken")
        exported = self.export()
        self.assertEqual(len(backup.verify(exported / "data")["sha256"]), 2)

    def test_all_corrupt_generations_refused(self):
        (self.source / "world.json").write_text("broken")
        with self.assertRaisesRegex(ValueError, "no readable"):
            self.export()
        self.assertFalse((self.root / "export").exists())

    def test_tampering_and_unlisted_files_refused(self):
        exported = self.export()
        (exported / "data/world/world.json").write_text("modified")
        with self.assertRaisesRegex(ValueError, "Checksum"):
            backup.verify(exported / "data")
        clean = self.export("clean")
        (clean / "data/world/extra.txt").write_text("unlisted")
        with self.assertRaisesRegex(ValueError, "do not match"):
            backup.verify(clean / "data")

    def test_mode_confusion_and_path_escape_refused(self):
        exported = self.export()
        index = exported / "data/manifest.json"
        meta = json.loads(index.read_bytes())
        meta["sha256"]["world/../../outside"] = "0" * 64
        index.write_text(json.dumps(meta))
        with self.assertRaisesRegex(ValueError, "file list"):
            backup.verify(exported / "data")
        del meta["sha256"]["world/../../outside"]
        meta["format"] = 1
        index.write_text(json.dumps(meta))
        with self.assertRaisesRegex(ValueError, "file list"):
            backup.verify(exported / "data")

    def test_changed_source_aborts_before_publish(self):
        copy = backup.copy_private
        def race(source, target):
            copy(source, target)
            if source.name == "world.json":
                source.write_text(json.dumps({"players": {}, "changed": True}))
        with patch.object(backup, "copy_private", side_effect=race):
            with self.assertRaisesRegex(ValueError, "changed"):
                self.export()
        self.assertFalse((self.root / "export").exists())

    def test_authenticated_format_one_still_roundtrips(self):
        roster = {"owner": "owner-account", "revision": 1}
        (self.source / "members.json").write_text(json.dumps(roster))
        database = self.root / "identity.sqlite"
        with closing(sqlite3.connect(database)) as db:
            db.executescript("CREATE TABLE servers(world TEXT); CREATE TABLE accounts(id TEXT); INSERT INTO servers VALUES ('auth-world'); INSERT INTO accounts VALUES ('owner-account');")
            db.commit()
        target = self.root / "authenticated"
        backup.export_backup(self.source, database, "auth-world", target)
        self.assertEqual(backup.verify(target / "data")["format"], 1)
        backup.restore_backup(target / "data", self.root / "auth-restored")
        self.assertTrue((self.root / "auth-restored/data/identity/identity.sqlite").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
