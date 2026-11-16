from contextlib import closing
import sqlite3
import tempfile
import unittest
from pathlib import Path

from starlette.testclient import TestClient
from app import create_app


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "identity.sqlite"
        self.app = create_app(self.path)
        self.store = self.app.state.store
        self.account = self.store.provision_account("小糰")
        self.server = self.store.provision_world("test-island")
        self.client = TestClient(self.app, base_url="https://identity.test")

    def tearDown(self):
        self.client.close()
        self.temp.cleanup()

    def login(self):
        return self.client.post("/v1/login", json=self.account)

    def auth(self, token):
        return {"Authorization": "Bearer " + token}

    def flow(self):
        response = self.login()
        self.assertEqual(response.status_code, 200)
        session = response.json()["session"]
        response = self.client.post("/v1/tickets", headers=self.auth(session), json={"world_id": "test-island"})
        self.assertEqual(response.status_code, 200)
        return session, response.json()["ticket"]

    def test_login_ticket_redeem_validate_logout(self):
        session, ticket = self.flow()
        response = self.client.post("/v1/redeem", headers=self.auth(self.server), json={"world_id": "test-island", "ticket": ticket})
        self.assertEqual(response.status_code, 200)
        claims = response.json()
        self.assertEqual(claims["account_id"], self.account["account_id"])
        self.assertEqual(claims["world_id"], "test-island")
        query = {"world_id": "test-island", "admission_id": claims["admission_id"]}
        self.assertEqual(self.client.post("/v1/validate", headers=self.auth(self.server), json=query).status_code, 200)
        self.assertEqual(self.client.post("/v1/logout", headers=self.auth(session), json={}).status_code, 200)
        self.assertEqual(self.client.post("/v1/validate", headers=self.auth(self.server), json=query).status_code, 401)

    def test_ticket_cannot_be_replayed(self):
        _, ticket = self.flow()
        query = {"world_id": "test-island", "ticket": ticket}
        self.assertEqual(self.client.post("/v1/redeem", headers=self.auth(self.server), json=query).status_code, 200)
        self.assertEqual(self.client.post("/v1/redeem", headers=self.auth(self.server), json=query).status_code, 401)

    def test_invalid_login_no_secret_echo(self):
        response = self.client.post("/v1/login", json={"account_id": self.account["account_id"], "credential": "DO-NOT-ECHO-THIS"})
        self.assertEqual(response.status_code, 401)
        self.assertNotIn("DO-NOT-ECHO", response.text)
        self.assertEqual(response.headers["cache-control"], "no-store")

    def test_no_plain_http_and_forwarded_headers_not_trusted(self):
        with TestClient(self.app, base_url="http://identity.test") as client:
            result = client.post("/v1/login", json=self.account, headers={"X-Forwarded-Proto": "https"})
            self.assertEqual(result.status_code, 400)
            self.assertEqual(result.json()["error"], "HTTPS_REQUIRED")

    def test_explicit_loopback_test_mode(self):
        with TestClient(create_app(self.path, True)) as client:
            self.assertEqual(client.post("/v1/login", json=self.account).status_code, 200)

    def test_closed_schema_rejects_client_chosen_identity(self):
        session, _ = self.flow()
        query = {"world_id": "test-island", "account_id": "owner"}
        self.assertEqual(self.client.post("/v1/tickets", headers=self.auth(session), json=query).status_code, 400)

    def test_duplicate_json_keys_rejected(self):
        result = self.client.post("/v1/login", content='{"account_id":"a","account_id":"b","credential":"c"}', headers={"Content-Type": "application/json"})
        self.assertEqual(result.status_code, 400)

    def test_duplicate_authorization_rejected(self):
        session, _ = self.flow()
        result = self.client.post("/v1/tickets", json={"world_id": "test-island"}, headers=[("Authorization", "Bearer " + session), ("Authorization", "Bearer forged")])
        self.assertEqual(result.status_code, 401)

    def test_wrong_type_and_invalid_utf8(self):
        for credential in (42, None, [], "\ud800"):
            with self.subTest(type=type(credential).__name__):
                raw = __import__("json").dumps({"account_id": self.account["account_id"], "credential": credential})
                response = self.client.post("/v1/login", content=raw, headers={"Content-Type": "application/json"})
                self.assertEqual(response.status_code, 400)

    def test_body_limit_counts_received_bytes(self):
        result = self.client.post("/v1/login", content=b"x" * 8193, headers={"Content-Type": "application/json"})
        self.assertEqual(result.status_code, 413)

    def test_content_type_required(self):
        self.assertEqual(self.client.post("/v1/login", content="{}").status_code, 400)

    def test_rate_limit_has_retry_and_no_token(self):
        for _ in range(20):
            self.assertEqual(self.login().status_code, 200)
        response = self.login()
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.headers["retry-after"], "60")
        self.assertNotIn("session", response.json())

    def test_storage_failure_is_explicit_without_debug_details(self):
        with closing(sqlite3.connect(self.path)) as db, db:
            db.execute("CREATE TRIGGER fail_insert BEFORE INSERT ON sessions BEGIN SELECT RAISE(ABORT, 'PRIVATE INTERNAL DETAIL'); END")
        response = self.login()
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["error"], "STORAGE_UNAVAILABLE")
        self.assertNotIn("PRIVATE", response.text)

    def test_client_cannot_call_operator_endpoints(self):
        for path in ("/v1/provision", "/v1/disable", "/v1/rotate"):
            self.assertEqual(self.client.post(path, json={}).status_code, 404)

    def test_rename_keeps_authoritative_account(self):
        session, _ = self.flow()
        response = self.client.post("/v1/profile", headers=self.auth(session), json={"display_name": "改名"})
        self.assertEqual(response.status_code, 200)
        login = self.login().json()
        self.assertEqual(login["display_name"], "改名")
        self.assertEqual(login["account_id"], self.account["account_id"])

    def test_health_contains_no_account_data(self):
        result = self.client.get("/healthz")
        self.assertEqual(result.status_code, 200)
        self.assertEqual(set(result.json()), {"ok", "service", "schema"})

    def test_refresh_then_logout_cannot_refresh(self):
        session, _ = self.flow()
        response = self.client.post("/v1/refresh", headers=self.auth(session), json={})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["session"], session)
        self.client.post("/v1/logout", headers=self.auth(session), json={})
        self.assertEqual(self.client.post("/v1/refresh", headers=self.auth(session), json={}).status_code, 401)


if __name__ == "__main__":
    unittest.main(verbosity=2)
