import hashlib
from pathlib import Path
import struct
import tempfile
import unittest

from audit_release_assets import GAME, NOTICES, audit


class AssetIntegrityTest(unittest.TestCase):
    def test_changes_to_asset_content_are_detected(self):
        asset = "assets/fixture/payload.png"
        original = b"synthetic asset payload"
        files = {name: (GAME / name).read_bytes() for name in NOTICES}
        files["release.json"] = b'{"build":24,"protocol":53}'
        files[asset] = original
        body = bytearray()
        records = bytearray()
        for name, payload in files.items():
            encoded_name = name.encode("utf-8")
            records.extend(struct.pack("<I", len(encoded_name)))
            records.extend(encoded_name)
            digest = hashlib.md5(payload).digest()
            records.extend(struct.pack("<QQ16sI", len(body), len(payload), digest, 0))
            body.extend(payload)
        directory = struct.pack("<I", len(files)) + records
        header_size = struct.calcsize("<4s5I2Q")
        header = struct.pack("<4s5I2Q", b"GDPC", 4, 4, 7, 2, 2, header_size, header_size + len(body))
        pack = header + body + directory
        footer = struct.pack("<Q4s", len(pack), b"GDPC")
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / "fixture.bin"
            binary.write_bytes(pack + footer)
            self.assertTrue(audit(binary)["passed_pack_checks"])
            offset = header_size + body.rfind(original)
            damaged = bytearray(pack)
            damaged[offset] ^= 1
            binary.write_bytes(damaged + footer)
            report = audit(binary)
            self.assertFalse(report["passed_pack_checks"])
            self.assertEqual(report["corrupted_asset_payloads"], [asset])
            self.assertEqual(report["missing_asset_payloads"], [])


if __name__ == "__main__":
    unittest.main()
