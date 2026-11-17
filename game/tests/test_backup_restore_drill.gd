extends SceneTree
## T059/T089 backup / restore / migration rehearsal on DISPOSABLE COPIES.
##
## Every fixture is an on-disk project save under the repository `work/` tree
## (or passed with `-- --fixture=<abs path>`). The source file is only ever
## READ: it is hashed, copied into a fresh sandbox under the OS temp directory,
## and every World API call (load_world / save) targets the copy. The drill
## never writes under user:// (where live saves and profiles live), never opens
## a network peer and never touches deployment files.
##
## Per fixture it rehearses:
##   1. migration load of the copy (old schema -> SaveSchema.VERSION) with
##      inventory, stored items, buildings and story state preserved;
##   2. save() rotation: the pre-migration bytes become `.bak` verbatim and the
##      migrated save reloads to the same state (save/reload fixpoint);
##   3. corrupt-main recovery from `.bak`, then quarantine of the corrupt main
##      to `.rejected-*` on the next save while the known-good `.bak` is kept;
##   4. missing-main recovery from `.bak`;
##   5. rejection without adoption or file writes of: truncated JSON, a
##      non-dictionary JSON root, a future schema version, and main+bak both
##      corrupt;
##   6. the source fixture (stand-in for the live save) is byte-identical and
##      gains no `.bak` / `.tmp` / `.rejected-*` siblings.
## Summary line: BACKUP_RESTORE_DRILL fixtures=N checks=N failures=N unverified=N

const World = preload("res://scripts/world.gd")
const SaveSchema = preload("res://scripts/save_schema.gd")

## Real saves produced by earlier project runs, chosen to span schema versions
## (1, 6, 13, 23, 24) and to carry buildings, stored items and story progress.
const DEFAULT_FIXTURES := [
	"work/xiaoli/20261113-035419-645/world.json",
	"work/depths/journey-complete.json",
	"work/auto-freight/native-final-saved.json",
	"work/public-kitchen/journey-second/earned-kitchen-final.json",
	"work/weather/bakery-network/world-final.json",
]

var checks := 0
var failures := 0
var unverified: Array[String] = []
var fixtures_run := 0
var sandbox_root := ""
var current := ""

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL [%s] %s" % [current, description])

func _initialize() -> void:
	var repo := _norm(ProjectSettings.globalize_path("res://")).trim_suffix("/").get_base_dir()
	var sources: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="):
			sources.append(_norm(arg.trim_prefix("--fixture=")))
	if sources.is_empty():
		for rel in DEFAULT_FIXTURES:
			sources.append(repo.path_join(rel))
	sandbox_root = _norm(OS.get_temp_dir()).path_join("bridge-backup-drill-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(sandbox_root) != OK:
		push_error("Cannot create sandbox " + sandbox_root)
		quit(1)
		return
	var index := 0
	for source in sources:
		index += 1
		current = source.get_file() + "#%d" % index
		if not FileAccess.file_exists(source):
			unverified.append("missing fixture, not exercised: " + source)
			continue
		var refusal := _refuse(source, repo)
		if not refusal.is_empty():
			failures += 1
			push_error("REFUSED [%s] %s" % [current, refusal])
			continue
		var dir := sandbox_root.path_join("f%d" % index)
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			expect(false, "sandbox subdirectory created")
			continue
		_drill(source, dir)
		fixtures_run += 1
	_cleanup()
	expect(fixtures_run > 0, "at least one real project fixture was exercised")
	for note in unverified:
		print("UNVERIFIED " + note)
	print("BACKUP_RESTORE_DRILL fixtures=%d checks=%d failures=%d unverified=%d" % [fixtures_run, checks, failures, unverified.size()])
	quit(0 if failures == 0 else 1)

# --- safety guards -----------------------------------------------------------

func _norm(path: String) -> String:
	return path.replace("\\", "/").simplify_path()

func _key(path: String) -> String:
	# Windows paths are case-insensitive; compare lowered forms there.
	return _norm(path).to_lower() if OS.get_name() == "Windows" else _norm(path)

func _under(path: String, root: String) -> bool:
	var r := _key(root).trim_suffix("/") + "/"
	return _key(path).begins_with(r)

## Returns a non-empty reason when the source must not be used.
func _refuse(source: String, repo: String) -> String:
	if source.get_extension().to_lower() != "json":
		return "fixture must be a .json save"
	if _under(source, OS.get_user_data_dir()):
		return "fixture is inside the user:// data dir (live saves); refusing"
	if not _under(source, repo):
		return "fixture is outside the repository; refusing"
	if _under(source, sandbox_root):
		return "fixture is inside the drill sandbox"
	return ""

# --- the drill ---------------------------------------------------------------

func _drill(source: String, dir: String) -> void:
	var source_sha := FileAccess.get_sha256(source)
	var source_bytes := FileAccess.get_file_as_bytes(source)
	var source_mtime := FileAccess.get_modified_time(source)
	var siblings_before := _artefacts_beside(source)
	var expected = JSON.parse_string(source_bytes.get_string_from_utf8())
	expect(expected is Dictionary, "source parses as a save dictionary")
	if not expected is Dictionary:
		return
	var source_version := int(expected.get("version", 0))

	# 1. Disposable copy + migration load.
	var copy := dir.path_join("world.json")
	expect(DirAccess.copy_absolute(source, copy) == OK, "fixture copied into sandbox")
	expect(FileAccess.get_sha256(copy) == source_sha, "copy is byte-identical to fixture")
	var first := World.new()
	var loaded := first.load_world(copy)
	expect(loaded, "copy loads under current schema (from v%d)" % source_version)
	if not loaded:
		return
	expect(not first.recovered_from_backup, "clean copy did not need backup recovery")
	expect(int(first.state.get("version", 0)) == SaveSchema.VERSION, "state migrated to v%d" % SaveSchema.VERSION)
	_expect_preserved(expected, first.state, "after migration load")
	expect(FileAccess.get_sha256(copy) == source_sha, "loading alone does not rewrite the copy")

	# 2. save() rotation and fixpoint reload.
	expect(first.save(), "migrated copy saves: " + first.save_error)
	expect(FileAccess.get_sha256(copy + ".bak") == source_sha, ".bak holds the pre-migration bytes verbatim")
	expect(not FileAccess.file_exists(copy + ".tmp"), "no .tmp left after save")
	var on_disk = JSON.parse_string(FileAccess.get_file_as_string(copy))
	expect(on_disk is Dictionary and int(on_disk.get("version", 0)) == SaveSchema.VERSION, "main file now carries current version")
	var second := World.new()
	expect(second.load_world(copy) and not second.recovered_from_backup, "migrated main reloads without backup")
	_expect_preserved(expected, second.state, "after save and reload")
	expect(_same(first.state, second.state), "save -> reload is a fixpoint (migration idempotent)")
	var migrated_sha := FileAccess.get_sha256(copy)

	# 3. Corrupt main -> restore from .bak -> quarantine on next save.
	var corrupt := source_bytes.slice(0, maxi(1, int(source_bytes.size() * 0.5)))
	_write(copy, corrupt)
	var corrupt_sha := FileAccess.get_sha256(copy)
	var restored := World.new()
	expect(restored.load_world(copy), "truncated main restores from .bak")
	expect(restored.recovered_from_backup, "restore is flagged recovered_from_backup")
	_expect_preserved(expected, restored.state, "after restore from .bak")
	expect(FileAccess.get_sha256(copy) == corrupt_sha, "restore does not overwrite the corrupt main before save")
	expect(restored.save(), "recovered world saves: " + restored.save_error)
	expect(not restored.rejected_path.is_empty() and FileAccess.get_sha256(restored.rejected_path) == corrupt_sha, "corrupt main quarantined byte-for-byte")
	expect(FileAccess.get_sha256(copy + ".bak") == source_sha, "known-good .bak kept through recovery save")
	var after_recovery := World.new()
	expect(after_recovery.load_world(copy) and not after_recovery.recovered_from_backup, "post-recovery main loads directly")
	_expect_preserved(expected, after_recovery.state, "after recovery save")

	# 4. Missing main, .bak only.
	DirAccess.remove_absolute(copy)
	var from_bak := World.new()
	expect(from_bak.load_world(copy) and from_bak.recovered_from_backup, "missing main recovers from .bak")
	_expect_preserved(expected, from_bak.state, "after missing-main recovery")
	expect(from_bak.save() and FileAccess.file_exists(copy), "missing-main recovery writes a new main")
	expect(FileAccess.get_sha256(copy + ".bak") == source_sha, ".bak untouched by missing-main recovery save")

	# A process can stop between moving the primary and publishing the backup.
	# The staged primary is newer than the existing backup in this layout.
	var staged_before := read_previous_rotation(copy, from_bak)
	expect(not staged_before.is_empty(), "staged primary recovery preserves newest state")

	# 5. Rejections: no adoption, no writes.
	var migrated_text := JSON.stringify(second.state)
	var future = JSON.parse_string(migrated_text)
	future.version = SaveSchema.VERSION + 1
	_expect_rejected(dir.path_join("truncated.json"), migrated_text.left(int(migrated_text.length() * 0.5)).to_utf8_buffer(), PackedByteArray(), "truncated JSON, no backup")
	_expect_rejected(dir.path_join("array.json"), "[]".to_utf8_buffer(), PackedByteArray(), "non-dictionary root")
	_expect_rejected(dir.path_join("future.json"), JSON.stringify(future).to_utf8_buffer(), PackedByteArray(), "future schema version")
	_expect_rejected(dir.path_join("both.json"), corrupt, "{\"version\":".to_utf8_buffer(), "main and .bak both corrupt")
	expect(not migrated_sha.is_empty(), "migrated snapshot hash recorded")

	# 6. The source (live stand-in) is untouched.
	expect(FileAccess.get_sha256(source) == source_sha, "source fixture bytes unchanged")
	expect(FileAccess.get_modified_time(source) == source_mtime, "source fixture mtime unchanged")
	expect(_artefacts_beside(source) == siblings_before, "no .bak/.tmp/.rejected-* created beside source")

func read_previous_rotation(path:String,world) -> String:
	world.state.committed+=1
	expect(world.save(),"publish newer primary before interrupted rotation")
	var staged:=path+".bak.staged"
	var newest:=FileAccess.get_sha256(path)
	var older:=FileAccess.get_sha256(path+".bak")
	expect(newest!=older and DirAccess.rename_absolute(path,staged)==OK,"simulate interrupted rotation with distinct backup generations")
	var reopened:=World.new()
	if not reopened.load_world(path):
		expect(false,"load staged primary")
		return ""
	expect(reopened.recovered_from_backup and reopened.state.committed==world.state.committed,"load newest committed state from staged primary")
	expect(reopened.save() and FileAccess.get_sha256(staged)==newest and FileAccess.get_sha256(path+".bak")==older,"recovery saves primary and retains both backups")
	expect(reopened.save() and not FileAccess.file_exists(staged),"next normal save resolves staged backup")
	return FileAccess.get_sha256(path)

func _expect_rejected(path: String, main_bytes: PackedByteArray, bak_bytes: PackedByteArray, label: String) -> void:
	_write(path, main_bytes)
	if not bak_bytes.is_empty():
		_write(path + ".bak", bak_bytes)
	var before := _listing(path.get_base_dir())
	var main_sha := FileAccess.get_sha256(path)
	var world := World.new()
	var fresh_players: int = world.state.players.size()
	expect(not world.load_world(path), "rejects " + label)
	expect(world.state.players.size() == fresh_players and not world.recovered_from_backup, "rejected snapshot not adopted: " + label)
	expect(FileAccess.get_sha256(path) == main_sha and _listing(path.get_base_dir()) == before, "rejection writes nothing: " + label)

# --- preservation checks -----------------------------------------------------

func _expect_preserved(expected: Dictionary, state: Dictionary, stage: String) -> void:
	var src_players: Dictionary = expected.get("players", {})
	var got_players: Dictionary = state.get("players", {})
	expect(src_players.size() == got_players.size(), "player count kept " + stage)
	var inventory_ok := true
	var story_ok := true
	var coins_ok := true
	var extras: Array[String] = []
	for token in src_players:
		var src: Dictionary = src_players[token]
		var got: Dictionary = got_players.get(token, {})
		if got.is_empty():
			inventory_ok = false
			continue
		if not _items_kept(src.get("inventory", {}), got.get("inventory", {})):inventory_ok = false
		for item in got.get("inventory", {}):
			if int(got.inventory[item]) > 0 and int(src.get("inventory", {}).get(item, 0)) <= 0:
				extras.append("%s:%s" % [token, item])
		if int(src.get("coins", 0)) != int(got.get("coins", 0)):coins_ok = false
		var src_stories: Dictionary = src.get("stories", {})
		for story in src_stories:
			if not _same(src_stories[story], got.get("stories", {}).get(story)):story_ok = false
	expect(inventory_ok, "every player inventory count kept " + stage)
	expect(coins_ok, "coins kept " + stage)
	expect(story_ok, "per-player story progress kept " + stage)
	if not extras.is_empty() and stage == "after migration load":
		unverified.append("%s: migration added inventory items not in source (not judged): %s" % [current, ", ".join(PackedStringArray(extras))])
	# Buildings and stored items: home layer plus every regional layer.
	var src_layers := _object_layers(expected)
	var got_layers := _object_layers(state)
	var building_ok := true
	var stored_ok := true
	var count := 0
	for layer in src_layers:
		var got_layer: Dictionary = got_layers.get(layer, {})
		for k in src_layers[layer]:
			count += 1
			var a: Dictionary = src_layers[layer][k]
			var b = got_layer.get(k)
			if not b is Dictionary or str(b.get("type", "")) != str(a.get("type", "")):
				building_ok = false
				continue
			if a.get("items") is Dictionary and not _items_kept(a.items, b.get("items", {})):stored_ok = false
	expect(building_ok, "all %d buildings kept with type %s" % [count, stage])
	expect(stored_ok, "items stored in buildings kept " + stage)
	# World story / progress.
	var src_events: Array = expected.get("events", [])
	var got_events: Array = state.get("events", [])
	expect(got_events.size() >= src_events.size() and _same(src_events, got_events.slice(0, src_events.size())), "event log kept as prefix " + stage)
	expect(bool(expected.get("board", false)) == bool(state.get("board", false)), "board/bridge progress kept " + stage)
	# Migrations may ADD fields; every source field must survive unchanged.
	expect(_kept(expected.get("donations", {}), state.get("donations", {})), "donations kept " + stage)
	if expected.has("chapter_one"):
		expect(_kept(expected.chapter_one, state.get("chapter_one")), "chapter_one story state kept " + stage)

## Every key in `src` exists in `got` with an equal value (extra keys allowed).
func _kept(src, got) -> bool:
	if not (src is Dictionary and got is Dictionary):return _same(src, got)
	var by_name := {}
	for k in got:by_name[str(k)] = got[k]
	for k in src:
		if not by_name.has(str(k)) or not _same(src[k], by_name[str(k)]):return false
	return true

func _object_layers(s: Dictionary) -> Dictionary:
	var layers := {"home": s.get("objects", {})}
	var regions = s.get("regions", {})
	if regions is Dictionary:
		for r in regions:
			if regions[r] is Dictionary and regions[r].get("objects") is Dictionary:
				layers[str(r)] = regions[r].objects
	return layers

func _items_kept(src, got) -> bool:
	if not src is Dictionary:return true
	if not got is Dictionary:return src.is_empty()
	for item in src:
		if int(src[item]) != int(got.get(item, 0)):return false
	return true

## Deep equality tolerant of JSON's int/float and String/StringName mixing.
func _same(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if (a is String or a is StringName) and (b is String or b is StringName):
		return str(a) == str(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():return false
		var by_name := {}
		for k in b:by_name[str(k)] = b[k]
		for k in a:
			if not by_name.has(str(k)) or not _same(a[k], by_name[str(k)]):return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():return false
		for i in a.size():
			if not _same(a[i], b[i]):return false
		return true
	return typeof(a) == typeof(b) and a == b

# --- file helpers (sandbox only) ---------------------------------------------

func _write(path: String, bytes: PackedByteArray) -> void:
	if not _under(path, sandbox_root):
		push_error("refusing write outside sandbox: " + path)
		failures += 1
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		expect(false, "sandbox write " + path)
		return
	f.store_buffer(bytes)
	f.close()

func _listing(dir: String) -> Array:
	var names := Array(DirAccess.get_files_at(dir))
	names.sort()
	var out := []
	for n in names:out.append([n, FileAccess.get_sha256(dir.path_join(n))])
	return out

func _artefacts_beside(source: String) -> Array:
	var stem := source.get_file()
	var out := []
	for n in DirAccess.get_files_at(source.get_base_dir()):
		if n.begins_with(stem + "."):out.append(n)
	out.sort()
	return out

func _cleanup() -> void:
	if sandbox_root.is_empty() or not _under(sandbox_root, OS.get_temp_dir()) or not sandbox_root.get_file().begins_with("bridge-backup-drill-"):
		unverified.append("sandbox not removed (guard): " + sandbox_root)
		return
	for sub in DirAccess.get_directories_at(sandbox_root):
		var d := sandbox_root.path_join(sub)
		for n in DirAccess.get_files_at(d):DirAccess.remove_absolute(d.path_join(n))
		DirAccess.remove_absolute(d)
	DirAccess.remove_absolute(sandbox_root)
	if DirAccess.dir_exists_absolute(sandbox_root):
		unverified.append("sandbox left behind: " + sandbox_root)
