extends RefCounted

const World = preload("res://scripts/world.gd")
const Schema = preload("res://scripts/save_schema.gd")
const Membership = preload("res://scripts/world_membership.gd")
const Retention = preload("res://scripts/admission_retention.gd")
const MISSING := "-"

static func canonical(path: String) -> String:
	return ProjectSettings.globalize_path(path).simplify_path()

static func journal_path(member_path: String) -> String:
	return canonical(member_path) + ".admission-wal"

static func has_pending(member_path: String) -> bool:
	var path := journal_path(member_path)
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

static func recover(world_path: String, member_path: String, world_id: String) -> bool:
	if not has_pending(member_path):
		return true
	var wal := journal_path(member_path)
	if DirAccess.dir_exists_absolute(wal):
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(wal)) != OK:
		return false
	var store := new()
	return store._apply(parser.data, canonical(world_path), canonical(member_path), world_id)

func commit(world_path: String, member_path: String, world_id: String, world_candidate: Dictionary, member_candidate: Dictionary) -> bool:
	var world := canonical(world_path)
	var member := canonical(member_path)
	if world_path.is_empty() or member_path.is_empty() or has_pending(member) or not safe_pair(world, member):
		return false
	var before: Array[Dictionary] = []
	for target in [world, world + ".bak", member]:
		if DirAccess.dir_exists_absolute(target):
			return false
		var file := FileAccess.open(target, FileAccess.READ)
		if file == null:
			if FileAccess.file_exists(target):
				return false
			before.append({"hash": MISSING, "data": ""})
			continue
		var bytes := file.get_buffer(file.get_length())
		if bytes.size() != file.get_length():
			return false
		before.append({"hash": hash_bytes(bytes), "data": Marshalls.raw_to_base64(bytes)})
	var record := {"version": 1, "world_path": world, "member_path": member, "world_id": world_id,
		"transaction": Crypto.new().generate_random_bytes(16).hex_encode(),
		"before": before, "world": JSON.stringify(world_candidate), "members": JSON.stringify(member_candidate)}
	if not valid_record(record, world, member, world_id) or not checkpoint("prejournal"):
		return false
	if not write_atomic(journal_path(member), JSON.stringify(record).to_utf8_buffer()):
		return false
	if not checkpoint("afterjournal"):
		return false
	return _apply(record, world, member, world_id)

func checkpoint(_stage: String) -> bool:
	return true

func _apply(record: Variant, world: String, member: String, world_id: String) -> bool:
	if not valid_record(record, world, member, world_id):
		return false
	var targets := [world, world + ".bak", member]
	var after: Array[PackedByteArray] = [record.world.to_utf8_buffer(), record.world.to_utf8_buffer(), record.members.to_utf8_buffer()]
	for index in targets.size():
		var current := file_hash(targets[index])
		if current != record.before[index].hash and current != hash_bytes(after[index]):
			return false
	for index in targets.size():
		var prior: Dictionary = record.before[index]
		if prior.hash == MISSING:
			continue
		var archive: String = targets[index] + ".admission-previous-" + record.transaction
		var existing := file_hash(archive)
		if existing == prior.hash:
			continue
		if existing != MISSING or not write_atomic(archive, Marshalls.base64_to_raw(prior.data)):
			return false
	for index in targets.size():
		var current := file_hash(targets[index])
		if current != hash_bytes(after[index]):
			if current != record.before[index].hash or not write_atomic(targets[index], after[index]):
				return false
		if index == 0 and not checkpoint("afterworld"):
			return false
	if not checkpoint("aftermembers") or not checkpoint("cleanup"):
		return false
	if DirAccess.remove_absolute(journal_path(member)) != OK:
		return false
	# Retention is maintenance after a completed transaction. It must never turn
	# an already committed admission into a reported save failure.
	var maintenance := Retention.record_completed(world,member,record)
	if not maintenance.ok:
		push_warning("Admission committed; previous-copy retention needs attention.")
	return true

static func safe_pair(world: String, member: String) -> bool:
	var paths := [world, world + ".bak", world + ".bak.staged", world + ".tmp", member, journal_path(member)]
	var seen := {}
	for path: String in paths:
		var comparison := path.to_lower() if OS.get_name() == "Windows" else path
		if seen.has(comparison):
			return false
		seen[comparison] = true
	return true

static func valid_record(record: Variant, world: String, member: String, world_id: String) -> bool:
	if not safe_pair(world, member) or not record is Dictionary or record.size() != 8 or record.get("version") != 1:
		return false
	if not Membership.valid_text(world_id, 64) or record.get("world_id") != world_id or record.get("world_path") != world or record.get("member_path") != member:
		return false
	var transaction = record.get("transaction")
	if not transaction is String or transaction.length() != 32 or not transaction.is_valid_hex_number(false):
		return false
	var before = record.get("before")
	if not before is Array or before.size() != 3:
		return false
	for entry in before:
		if not entry is Dictionary or entry.size() != 2 or not entry.get("data") is String:
			return false
		if entry.get("hash") == MISSING and entry.data.is_empty():
			continue
		if not Membership.is_digest(entry.get("hash")) or hash_bytes(Marshalls.base64_to_raw(entry.data)) != entry.hash:
			return false
	if not record.get("world") is String or not record.get("members") is String:
		return false
	var world_parser := JSON.new()
	var member_parser := JSON.new()
	if world_parser.parse(record.world) != OK or member_parser.parse(record.members) != OK:
		return false
	var state = world_parser.data
	var roster = member_parser.data
	if not state is Dictionary or not Schema.validate(state, World.CROPS, World.BUILD, World.RECIPES, World.SIZE, World.TREE_TIME) or not Membership.valid(roster):
		return false
	var previous_members := {}
	if before[2].hash != MISSING:
		var prior := JSON.new()
		if prior.parse(Marshalls.base64_to_raw(before[2].data).get_string_from_utf8()) != OK or not Membership.valid(prior.data):
			return false
		previous_members = prior.data.members
	for account in roster.members:
		var entry: Dictionary = roster.members[account]
		if previous_members.get(account) != entry and not state.players.has(entry.character):
			return false
	return true

static func hash_bytes(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func file_hash(path: String) -> String:
	if DirAccess.dir_exists_absolute(path):
		return ""
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else MISSING

static func write_atomic(path: String, bytes: PackedByteArray) -> bool:
	var staged := path + ".stage-" + Crypto.new().generate_random_bytes(12).hex_encode()
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var status := file.get_error()
	file.close()
	if status == OK and DirAccess.rename_absolute(staged, path) == OK:
		return true
	DirAccess.remove_absolute(staged)
	return false
