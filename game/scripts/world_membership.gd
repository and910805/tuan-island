extends RefCounted

const LIMIT := 8
const VERSION := 2
var path: String
var _state: Dictionary = {}

func open(file: String) -> bool:
	path = file
	_state = {}
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("version") == 1 and data.size() == 5 and not data.has("revision"):
		data.version = VERSION
		data.revision = 0
		return _commit(data)
	if not valid(data):
		return false
	_state = data
	return true

func initialize(file: String, world_name: String, owner: String, display_name: String, legacy_character: String = "") -> bool:
	if not _state.is_empty() or FileAccess.file_exists(file) or not valid_text(owner, 128) or not valid_text(world_name, 64) or not valid_text(display_name, 24):
		return false
	if not legacy_character.is_empty() and not valid_text(legacy_character, 128):
		return false
	var character := legacy_character if not legacy_character.is_empty() else new_character()
	if character.is_empty():
		return false
	path = file
	return _commit({"version": VERSION, "revision": 0, "world_name": world_name, "owner": owner,
		"members": {owner: member(display_name, character)}, "invite": {"digest": "", "generation": 0, "expires": 0}})

func read(account: String) -> Dictionary:
	if not has_member(account):
		return {}
	var roster: Array[Dictionary] = []
	for id in _state.members:
		var entry: Dictionary = _state.members[id]
		roster.append({"name": entry.name, "role": "owner" if id == _state.owner else "member",
			"last_activity": entry.last_activity})
	return {"world_name": _state.world_name, "members": roster, "capacity": LIMIT,
		"character": _state.members[account].character, "can_manage": account == _state.owner}

func rotate(account: String, ttl: int = 3600) -> Dictionary:
	if not is_owner(account) or ttl < 1 or ttl > 604800:
		return {"ok": false}
	var code := Crypto.new().generate_random_bytes(32).hex_encode()
	if code.length() != 64:
		return {"ok": false}
	var candidate := _state.duplicate(true)
	candidate.invite = {"digest": code.sha256_text(), "generation": int(_state.invite.generation) + 1,
		"expires": now() + ttl}
	if not _commit(candidate):
		return {"ok": false}
	return {"ok": true, "code": code, "generation": candidate.invite.generation, "expires": candidate.invite.expires}

func revoke(account: String) -> bool:
	if not is_owner(account):
		return false
	var candidate := _state.duplicate(true)
	candidate.invite = {"digest": "", "generation": int(_state.invite.generation) + 1, "expires": 0}
	return _commit(candidate)

func admit(account: String, display_name: String = "", code: String = "") -> bool:
	if _state.is_empty() or not valid_text(account, 128):
		return false
	if has_member(account):
		return rename(account, display_name) if not display_name.is_empty() else touch(account)
	var invite: Dictionary = _state.invite
	if not valid_text(display_name, 24) or not is_digest(code) or invite.expires <= now() or code.sha256_text() != invite.digest:
		return false
	return _add_member(account, display_name, new_character())

# Build the complete candidate without occupying a durable seat. Session commits
# this image together with the world before adopting it or welcoming the peer.
func plan_admission(account: String, display_name: String, code: String = "") -> Dictionary:
	if _state.is_empty() or not valid_text(account, 128) or not valid_text(display_name, 24):
		return {"ok": false, "code": "INVALID_ACCOUNT"}
	var candidate := _state.duplicate(true)
	if has_member(account):
		candidate.members[account].name = display_name
		candidate.members[account].last_activity = now()
	else:
		if not is_digest(code) or candidate.invite.expires <= now() or code.sha256_text() != candidate.invite.digest:
			return {"ok": false, "code": "INVITE_INVALID"}
		if candidate.members.size() >= LIMIT:
			return {"ok": false, "code": "WORLD_FULL"}
		candidate.members[account] = member(display_name, new_character())
	if not valid(candidate):
		return {"ok": false, "code": "INVALID_ACCOUNT"}
	return {"ok": true, "state": candidate, "character": candidate.members[account].character}

func adopt_committed(candidate: Dictionary) -> void:
	assert(valid(candidate))
	_state = candidate.duplicate(true)

func link_legacy(owner: String, verified_account: String, display_name: String, character: String) -> bool:
	if not is_owner(owner):
		return false
	return _add_member(verified_account, display_name, character)

func rename(account: String, display_name: String) -> bool:
	if not has_member(account) or not valid_text(display_name, 24):
		return false
	var candidate := _state.duplicate(true)
	candidate.members[account].name = display_name
	candidate.members[account].last_activity = now()
	return _commit(candidate)

func touch(account: String) -> bool:
	if not has_member(account):
		return false
	var candidate := _state.duplicate(true)
	candidate.members[account].last_activity = now()
	return _commit(candidate)

func _add_member(account: String, display_name: String, character: String) -> bool:
	if has_member(account) or _state.members.size() >= LIMIT:
		return false
	var candidate := _state.duplicate(true)
	candidate.members[account] = member(display_name, character)
	return _commit(candidate)

func has_member(account: String) -> bool:
	return not _state.is_empty() and _state.members.has(account)

func is_owner(account: String) -> bool:
	return has_member(account) and _state.owner == account

func _commit(candidate: Dictionary) -> bool:
	if not valid(candidate):
		return false
	var staged := path + "." + Crypto.new().generate_random_bytes(12).hex_encode() + ".tmp"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(candidate))
	file.flush()
	var status := file.get_error()
	file.close()
	if status != OK or DirAccess.rename_absolute(staged, path) != OK:
		DirAccess.remove_absolute(staged)
		return false
	_state = candidate
	return true

static func member(display_name: String, character: String) -> Dictionary:
	return {"name": display_name, "character": character, "last_activity": now()}

static func new_character() -> String:
	return Crypto.new().generate_random_bytes(24).hex_encode()

static func now() -> int:
	return int(Time.get_unix_time_from_system())

static func valid_text(value: Variant, limit: int) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length() > limit:
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if code < 32 or code == 127:
			return false
	return true

static func whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value <= 9007199254740990 and floor(value) == value

static func is_digest(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number(false)

static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 6 or data.get("version") != VERSION or not whole(data.get("revision")) or not valid_text(data.get("world_name"), 64):
		return false
	var owner = data.get("owner")
	var roster = data.get("members")
	if not valid_text(owner, 128) or not roster is Dictionary or roster.is_empty() or roster.size() > LIMIT or not roster.has(owner):
		return false
	var seen := {}
	for account in roster:
		var entry = roster[account]
		if not valid_text(account, 128) or not entry is Dictionary or entry.size() != 3 or not valid_text(entry.get("name"), 24):
			return false
		var character = entry.get("character")
		if not valid_text(character, 64) or seen.has(character) or not whole(entry.get("last_activity")):
			return false
		seen[character] = true
	var invite = data.get("invite")
	if not invite is Dictionary or invite.size() != 3 or not whole(invite.get("generation")) or not whole(invite.get("expires")):
		return false
	return (invite.get("digest") == "" and invite.expires == 0) or (is_digest(invite.get("digest")) and invite.expires > 0 and invite.generation > 0)

func set_world_name(value: String) -> bool:
	if _state.is_empty() or not valid_text(value, 64):
		return false
	if _state.world_name == value:
		return true
	var candidate := _state.duplicate(true)
	candidate.world_name = value
	return _commit(candidate)

func publish_snapshot(online: Array) -> Dictionary:
	if _state.is_empty():
		return {}
	var candidate := _state.duplicate(true)
	candidate.revision = int(candidate.revision) + 1
	if not _commit(candidate):
		return {}
	var members: Array[Dictionary] = []
	for account in candidate.members:
		var entry: Dictionary = candidate.members[account]
		members.append({"account_id": account, "name": entry.name, "role": "owner" if account == candidate.owner else "member", "last_activity": int(entry.last_activity)})
	return {"revision": candidate.revision, "name": candidate.world_name, "members": members,
		"online": online.filter(func(account): return candidate.members.has(account)), "invite": candidate.invite.duplicate()}

