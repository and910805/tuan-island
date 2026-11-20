extends RefCounted

const LIMIT := 8
const VERSION := 2
const AUDIT_LIMIT := 100
const INVITE_AUDIT := ["invite_rotate", "invite_revoke"]
const MEMBER_AUDIT := ["admin_grant", "admin_revoke", "block", "unblock", "kick", "public_build_grant", "public_build_revoke"]
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
	if not has_member(account) or is_blocked(account):
		return {}
	var roster: Array[Dictionary] = []
	for id in _state.members:
		var entry: Dictionary = _state.members[id]
		var row := {"name": entry.name, "role": role(id), "last_activity": entry.last_activity}
		if can_moderate(account, id):
			row["management_id"] = management_id(entry.character)
			row["blocked"] = is_blocked(id)
			row["public_builder"] = entry.get("public_builder", false)
		roster.append(row)
	var info := {"world_name": _state.world_name, "members": roster, "capacity": LIMIT,
		"character": _state.members[account].character, "can_manage": account == _state.owner}
	if is_owner(account):
		var history: Array[Dictionary] = []
		for event in _state.get("audit", []):
			var target: String = event.target
			history.append({"action": event.action, "at": event.at, "actor": _state.members[event.actor].name,
				"target": "" if target.is_empty() else _state.members[target].name})
		info["management_history"] = history
	return info

func rotate(account: String, ttl: int = 3600) -> Dictionary:
	if not is_owner(account) or ttl < 1 or ttl > 604800:
		return {"ok": false}
	var code := Crypto.new().generate_random_bytes(32).hex_encode()
	if code.length() != 64:
		return {"ok": false}
	var candidate := _state.duplicate(true)
	candidate.invite = {"digest": code.sha256_text(), "generation": int(_state.invite.generation) + 1,
		"expires": now() + ttl}
	_append_audit(candidate, "invite_rotate", account)
	if not _commit(candidate):
		return {"ok": false}
	return {"ok": true, "code": code, "generation": candidate.invite.generation, "expires": candidate.invite.expires}

func revoke(account: String) -> bool:
	if not is_owner(account):
		return false
	var candidate := _state.duplicate(true)
	candidate.invite = {"digest": "", "generation": int(_state.invite.generation) + 1, "expires": 0}
	_append_audit(candidate, "invite_revoke", account)
	return _commit(candidate)

func admit(account: String, display_name: String = "", code: String = "") -> bool:
	if _state.is_empty() or not valid_text(account, 128) or is_blocked(account):
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
	if is_blocked(account):
		return {"ok": false, "code": "WORLD_BLOCKED"}
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

func is_blocked(account: String) -> bool:
	return has_member(account) and _state.members[account].get("blocked", false)

func role(account: String) -> String:
	if not has_member(account): return ""
	if is_owner(account): return "owner"
	return "admin" if _state.members[account].get("admin", false) else "member"

static func management_id(character: String) -> String:
	return ("membership-management:" + character).sha256_text()

func set_admin(actor: String, target_id: String, enabled: bool) -> bool:
	if not is_owner(actor):
		return false
	var account := managed_account(actor, target_id)
	if account.is_empty(): return false
	if _state.members[account].get("admin", false) == enabled: return true
	var candidate := _state.duplicate(true)
	if enabled:
		candidate.members[account]["admin"] = true
	else:
		candidate.members[account].erase("admin")
	_append_audit(candidate, "admin_grant" if enabled else "admin_revoke", actor, account)
	return _commit(candidate)

func managed_account(actor: String, target_id: String) -> String:
	var actor_role := role(actor)
	if actor_role not in ["owner", "admin"] or not is_digest(target_id): return ""
	for account in _state.members:
		if can_moderate(actor, account) and management_id(_state.members[account].character) == target_id:
			return account
	return ""

func can_moderate(actor: String, target: String) -> bool:
	if actor == target or is_blocked(actor): return false
	var target_role := role(target)
	return (role(actor) == "owner" and target_role in ["admin", "member"]) or (role(actor) == "admin" and target_role == "member")

func set_blocked(actor: String, target_id: String, enabled: bool) -> String:
	var account := managed_account(actor, target_id)
	if account.is_empty(): return ""
	if is_blocked(account) == enabled: return account
	var candidate := _state.duplicate(true)
	if enabled:
		candidate.members[account]["blocked"] = true
	else:
		candidate.members[account].erase("blocked")
	_append_audit(candidate, "block" if enabled else "unblock", actor, account)
	return account if _commit(candidate) else ""

func can_build_public(character: String) -> bool:
	for account in _state.get("members", {}):
		var entry: Dictionary = _state.members[account]
		if entry.character == character:
			return not is_blocked(account) and (role(account) in ["owner", "admin"] or entry.get("public_builder", false))
	return false

func set_public_builder(actor: String, target_id: String, enabled: bool) -> bool:
	var account := managed_account(actor, target_id)
	if account.is_empty() or role(account) != "member": return false
	if _state.members[account].get("public_builder", false) == enabled: return true
	var candidate := _state.duplicate(true)
	if enabled:
		candidate.members[account]["public_builder"] = true
	else:
		candidate.members[account].erase("public_builder")
	_append_audit(candidate, "public_build_grant" if enabled else "public_build_revoke", actor, account)
	return _commit(candidate)

func record_kick(actor: String, target: String) -> bool:
	if not can_moderate(actor, target): return false
	var candidate := _state.duplicate(true)
	_append_audit(candidate, "kick", actor, target)
	return _commit(candidate)

static func _append_audit(candidate: Dictionary, action: String, actor: String, target := "") -> void:
	var history: Array = candidate.get("audit", [])
	history.append({"at": now(), "action": action, "actor": actor, "target": target})
	if history.size() > AUDIT_LIMIT: history.pop_front()
	candidate["audit"] = history

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
	if not data is Dictionary or data.size() != (7 if data.has("audit") else 6) or data.get("version") != VERSION or not whole(data.get("revision")) or not valid_text(data.get("world_name"), 64):
		return false
	var owner = data.get("owner")
	var roster = data.get("members")
	if not valid_text(owner, 128) or not roster is Dictionary or roster.is_empty() or roster.size() > LIMIT or not roster.has(owner):
		return false
	var seen := {}
	for account in roster:
		var entry = roster[account]
		if not valid_text(account, 128) or not entry is Dictionary or not valid_text(entry.get("name"), 24):
			return false
		var fields := 3
		for flag in ["admin", "blocked", "public_builder"]:
			if not entry.has(flag): continue
			if account == owner or not entry[flag] is bool or not entry[flag]: return false
			fields += 1
		if entry.size() != fields: return false
		var character = entry.get("character")
		if not valid_text(character, 64) or seen.has(character) or not whole(entry.get("last_activity")):
			return false
		seen[character] = true
	var invite = data.get("invite")
	if not invite is Dictionary or invite.size() != 3 or not whole(invite.get("generation")) or not whole(invite.get("expires")):
		return false
	if not ((invite.get("digest") == "" and invite.expires == 0) or (is_digest(invite.get("digest")) and invite.expires > 0 and invite.generation > 0)):
		return false
	return valid_audit(data.get("audit", []), roster)

static func valid_audit(history: Variant, roster: Dictionary) -> bool:
	if not history is Array or history.size() > AUDIT_LIMIT: return false
	for event in history:
		if not event is Dictionary or event.size() != 4 or not whole(event.get("at")): return false
		if not event.get("actor") is String or not roster.has(event.actor) or not event.get("target") is String: return false
		if event.get("action") in INVITE_AUDIT:
			if not event.target.is_empty(): return false
		elif event.get("action") in MEMBER_AUDIT:
			if event.actor == event.target or not roster.has(event.target): return false
		else: return false
	return true

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
		members.append({"account_id": account, "name": entry.name, "role": role(account), "last_activity": int(entry.last_activity)})
	# JSON save loading yields numeric floats; the directory requires integers.
	var invite: Dictionary = candidate.invite
	return {"revision": candidate.revision, "name": candidate.world_name, "members": members,
		"online": online.filter(func(account): return candidate.members.has(account)),
		"invite": {"digest": invite.digest, "generation": int(invite.generation), "expires": int(invite.expires)}}
