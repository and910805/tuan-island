extends SceneTree

const Session = preload("res://scripts/session.gd")
var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var server := Session.new()
	var path := OS.get_environment("TEMP").path_join("identity-members-%s.json" % Crypto.new().generate_random_bytes(12).hex_encode())
	expect(server.configure_identity("http://127.0.0.1:8142", "island", "secret", path, "owner") == ERR_INVALID_PARAMETER, "Unencrypted identity API is refused by default")
	expect(server.configure_identity("http://127.0.0.1:8142@elsewhere", "island", "secret", path, "owner", true) == ERR_INVALID_PARAMETER, "Loopback test authority cannot contain userinfo")
	expect(server.configure_identity("http://localhost:8142", "island", "secret", path, "owner", true) == ERR_INVALID_PARAMETER, "Loopback test authority must be literal IPv4")
	expect(server.configure_identity("http://127.0.0.1:8142", "island", "secret", path, "owner", true, null, path+".world") == OK, "Explicit loopback identity configuration works")
	expect(server.configure_directory("ws://127.0.0.1:8143", "Island") == ERR_INVALID_PARAMETER, "Directory requires WSS by default")
	expect(server.configure_directory("ws://127.0.0.1:8143", "Island", "生活", true) == OK, "Isolated directory accepts explicit loopback")
	var published := server.membership.publish_snapshot(["owner", "unknown"])
	expect(published.revision == 1 and published.name == "Island" and published.online == ["owner"], "Publication saves revision and excludes unknown presence")
	expect(server.membership.open(path) and server.membership.publish_snapshot([]).revision == 2, "Publication revision survives restart")
	var original_path := server.membership.path
	server.membership.path = original_path.path_join("missing").path_join("roster.json")
	expect(server.membership.publish_snapshot([]).is_empty(), "Failed persistence produces no directory publication")
	server.membership.path = original_path
	expect(server.membership.publish_snapshot([]).revision == 3, "Failed publication preparation does not consume a revision")
	var legacy_path := path + ".legacy"
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({"version": 1, "world_name": "Old Island", "owner": "owner",
		"members": {"owner": {"name": "Owner", "character": "original-player", "last_activity": 42}},
		"invite": {"digest": "", "generation": 3, "expires": 0}}))
	legacy_file.close()
	var migrated := Session.Membership.new()
	expect(migrated.open(legacy_path) and migrated.read("owner").character == "original-player", "V1 membership migration preserves legacy character")
	var migration_disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(legacy_path))
	expect(migration_disk.version == 2 and migration_disk.revision == 0 and migration_disk.invite.generation == 3, "V1 migration persists revision and keeps invite generation")
	DirAccess.remove_absolute(legacy_path)
	expect(server.host(8143, "", "", "", "127.0.0.1", true, "enet") == ERR_INVALID_PARAMETER, "Identity host refuses ENet")
	expect(server.host(8143, "", "", "", "127.0.0.1", false, "websocket") == ERR_INVALID_PARAMETER, "Identity host requires dedicated operation")
	expect(server.join_authenticated("ws://127.0.0.1:8143", 8143, "ticket", "") == ERR_INVALID_PARAMETER, "Authenticated clients refuse cleartext by default")
	expect(server.join_authenticated("wss://127.0.0.1:8143", 8143, "ticket", "", false, TLSOptions.client_unsafe()) == ERR_INVALID_PARAMETER, "Authenticated clients refuse unsafe TLS")
	var claim := {"ok": true, "world_id": "island", "account_id": "owner", "display_name": "Owner", "admission_id": "admission", "expires": int(Time.get_unix_time_from_system()) + 30}
	expect(server.valid_identity_claim(claim), "A current matching claim is accepted")
	claim.world_id = "different"
	expect(not server.valid_identity_claim(claim), "Foreign world claims are denied")
	claim.world_id = "island"
	claim.expires = 0
	expect(not server.valid_identity_claim(claim), "Expired claims are denied")
	server.identities[2] = claim
	server.peers[2] = "test-character"
	server.sequences[2] = 0
	server.identity_requests[2] = 1
	expect(not server.identity_allows_play(2), "Expired cached claim blocks play during validation")
	server._action(2, 1, "hoe", Vector2i.ZERO, "")
	expect(server.sequences[2] == 0, "Expired action is dropped before consuming its sequence or mutating the world")
	claim.expires = Time.get_unix_time_from_system() + 30.5
	server.identity_requests.erase(2)
	expect(server.valid_identity_claim(claim) and server.identity_allows_play(2), "Refreshed claim restores play")
	server.free()
	DirAccess.remove_absolute(path)
	print("IDENTITY_SESSION_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
