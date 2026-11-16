extends SceneTree

const Library = preload("res://scripts/blueprint_library.gd")
const Design = preload("res://scripts/blueprint_design.gd")
const World = preload("res://scripts/world.gd")

var checks := 0
var failures := 0
var base := ""
var recipes: Dictionary = World.BUILD
var names: Dictionary = World.NAMES

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func id_for(index: int) -> String:
	return String.num_int64(index, 16).lpad(32, "0")

func design(label: String, shift: int = 0) -> Dictionary:
	return {"version": 1, "name": label, "width": 3, "height": 2, "pieces": [
		{"kind": "roof", "x": shift, "y": 0},
		{"kind": "wall", "x": 1, "y": 1},
		{"kind": "floor", "x": shift, "y": 0},
	]}

func entry(index: int, label: String = "") -> Dictionary:
	return {"id": id_for(index), "design": design(label if not label.is_empty() else "藍圖%d" % index, index % 3)}

func file(leaf: String) -> String:
	return base + "/" + leaf

func bytes_of(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)

func write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return false
	handle.store_buffer(bytes)
	handle.close()
	return true

func ids(entries: Array) -> Array:
	var out: Array = []
	for item in entries:
		out.append(item.id)
	return out

func only_files(expected: Array) -> bool:
	var actual := Array(DirAccess.get_files_at(base))
	actual.sort()
	var wanted := expected.duplicate()
	wanted.sort()
	return actual == wanted

func _initialize() -> void:
	base = "user://test-blueprint-library-" + Crypto.new().generate_random_bytes(8).hex_encode()
	if DirAccess.make_dir_absolute(base) != OK:
		push_error("FAIL could not create isolated test directory")
		quit(1)
		return
	run()
	cleanup()
	print("BLUEPRINT_LIBRARY_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))

func run() -> void:
	var lib := file("library.json")

	# 不存在的檔案：成功、空清單、missing:true，且不會建立檔案。
	var missing := Library.load_library(lib, recipes, names)
	expect(missing.ok and missing.missing == true and missing.entries == [], "missing library loads as empty success")
	expect(not FileAccess.file_exists(lib), "loading a missing library does not create it")

	# 實際寫入磁碟並重開：多份、順序保留、正規化與Design.validate一致。
	var three := [entry(1, "小屋"), entry(2), entry(3)]
	var saved := Library.save_library(lib, three, recipes, names)
	expect(saved.ok and saved.entries.size() == 3, "three entries save")
	expect(FileAccess.file_exists(lib), "library file exists on disk after save")
	var reopened := Library.load_library(lib, recipes, names)
	expect(reopened.ok and reopened.missing == false and reopened.entries == saved.entries, "disk roundtrip matches saved normalized entries")
	expect(ids(reopened.entries) == [id_for(1), id_for(2), id_for(3)], "entry order and ids are kept without renumbering")
	var expected_design: Dictionary = Design.validate(design("小屋", 1), recipes, names)
	expect(expected_design.ok and reopened.entries[0].design == expected_design.blueprint, "stored design equals Design.validate normalization")
	expect(reopened.entries[0].design.name == "小屋", "unicode name survives disk roundtrip")

	# 回傳值是深複製：修改回傳或輸入都不影響後續。
	saved.entries[0].design.name = "被改掉"
	three[1].design.pieces.clear()
	var again := Library.load_library(lib, recipes, names)
	expect(again.ok and again.entries == reopened.entries, "mutating returned or input entries does not alter disk")
	again.entries[0].id = "x"
	expect(Library.load_library(lib, recipes, names).entries[0].id == id_for(1), "loaded entries are independent copies")

	# JSON整數型浮點可接受。
	var floaty := entry(4)
	floaty.design.width = 3.0
	floaty.design.pieces[1].x = 1.0
	expect(Library.validate({"version": 1.0, "entries": [floaty]}, recipes, names).ok, "integral floats accepted for version and design")

	# 以儲存清單刪除一份與全部。
	var two := [entry(1, "小屋"), entry(3)]
	expect(Library.save_library(lib, two, recipes, names).ok, "saving a shorter list succeeds")
	var after_remove := Library.load_library(lib, recipes, names)
	expect(after_remove.ok and ids(after_remove.entries) == [id_for(1), id_for(3)], "removing one entry persists after reopen")
	expect(Library.save_library(lib, [], recipes, names).ok, "saving empty list succeeds")
	var emptied := Library.load_library(lib, recipes, names)
	expect(emptied.ok and emptied.missing == false and emptied.entries == [], "removing all entries persists as an existing empty library")
	var empty_parser := JSON.new()
	expect(empty_parser.parse(bytes_of(lib).get_string_from_utf8()) == OK
		and empty_parser.data == {"version": 1.0, "entries": []}, "empty library file has exact document shape")

	# 12份上限。
	var twelve: Array = []
	for index in 12:
		twelve.append(entry(index + 10))
	expect(Library.save_library(lib, twelve, recipes, names).ok, "twelve entries save")
	var full := Library.load_library(lib, recipes, names)
	expect(full.ok and full.entries.size() == 12, "twelve entries reopen")
	var full_bytes := bytes_of(lib)
	var thirteen := twelve.duplicate(true)
	thirteen.append(entry(40))
	var over := Library.save_library(lib, thirteen, recipes, names)
	expect(not over.ok and over.entries == [] and not over.reason.is_empty(), "thirteenth entry rejected with reason")
	expect(bytes_of(lib) == full_bytes, "over-limit save leaves file bytes unchanged")

	# 重複ID、非法ID、未知欄位、非法design：整份拒絕且原檔位元組不變。
	var dup := [entry(1), entry(1, "另一份")]
	expect(not Library.save_library(lib, dup, recipes, names).ok and bytes_of(lib) == full_bytes, "duplicate ids rejected, file preserved")
	var bad_ids := ["A" + id_for(1).substr(1), id_for(1).substr(1), id_for(1) + "0", "g" + id_for(1).substr(1), 7, null]
	for bad in bad_ids:
		var item := entry(1)
		item.id = bad
		expect(not Library.save_library(lib, [item], recipes, names).ok and bytes_of(lib) == full_bytes, "invalid id %s rejected" % str(bad))
	var extra_entry := entry(1)
	extra_entry.note = "x"
	expect(not Library.save_library(lib, [extra_entry], recipes, names).ok and bytes_of(lib) == full_bytes, "unknown entry field rejected")
	var missing_design := {"id": id_for(1)}
	expect(not Library.save_library(lib, [missing_design], recipes, names).ok, "entry without design rejected")
	expect(not Library.validate({"version": 1, "entries": [], "extra": 1}, recipes, names).ok, "unknown top-level field rejected")
	expect(not Library.validate({"version": 2, "entries": []}, recipes, names).ok, "unknown version rejected")
	expect(not Library.validate({"version": true, "entries": []}, recipes, names).ok, "bool version rejected")
	expect(not Library.validate({"version": 1.5, "entries": []}, recipes, names).ok, "fractional version rejected")
	expect(not Library.validate({"version": 1}, recipes, names).ok, "missing entries rejected")
	expect(not Library.validate([], recipes, names).ok and not Library.validate(null, recipes, names).ok, "non-dictionary root rejected")
	expect(not Library.save_library(lib, "nope", recipes, names).ok and not Library.save_library(lib, [3], recipes, names).ok,
		"non-array entries and non-dictionary entry rejected")
	var malformed: Array = []
	var no_name := entry(1)
	no_name.design.erase("name")
	malformed.append(no_name)
	var bad_kind := entry(1)
	bad_kind.design.pieces[0].kind = "no_such_kind"
	malformed.append(bad_kind)
	var out_of_bounds := entry(1)
	out_of_bounds.design.pieces[1].x = 99
	malformed.append(out_of_bounds)
	var extra_piece_field := entry(1)
	extra_piece_field.design.pieces[1].owner = "someone"
	malformed.append(extra_piece_field)
	var not_dict := {"id": id_for(1), "design": "藍圖"}
	malformed.append(not_dict)
	for index in malformed.size():
		var mixed := [entry(2), malformed[index]]
		var result := Library.save_library(lib, mixed, recipes, names)
		expect(not result.ok and result.entries == [] and bytes_of(lib) == full_bytes, "malformed design %d rejects whole library, file preserved" % index)

	# 非法路徑：不寫入、不建立資料夾。
	var folder := file("folder.json")
	expect(DirAccess.make_dir_absolute(folder) == OK, "fixture directory created")
	var no_parent := file("no-such-dir") + "/library.json"
	for bad_path in ["", "   ", base + "/", base + "\\", folder, no_parent, " " + lib, 42, null]:
		var save_try := Library.save_library(bad_path, [entry(1)], recipes, names)
		expect(not save_try.ok and not save_try.reason.is_empty(), "save to invalid path %s fails" % str(bad_path))
		var load_try := Library.load_library(bad_path, recipes, names)
		expect(not load_try.ok or load_try.get("missing") == true, "load from invalid path %s never reports data" % str(bad_path))
	expect(not Library.load_library(folder, recipes, names).ok, "directory path load fails rather than reporting missing")
	expect(not DirAccess.dir_exists_absolute(file("no-such-dir")), "save does not create missing parent directories")
	expect(DirAccess.dir_exists_absolute(folder) and DirAccess.get_files_at(folder).is_empty()
		and DirAccess.get_directories_at(folder).is_empty(), "directory target untouched by failed save")
	expect(bytes_of(lib) == full_bytes, "invalid path attempts leave real library bytes unchanged")

	# 損壞、未知欄位、非法design、過大檔案：load失敗並保留原位元組；非法save不覆寫。
	var corrupt := file("corrupt.json")
	var corrupt_bytes := "{\"version\":1,\"entries\":[".to_utf8_buffer()
	expect(write_bytes(corrupt, corrupt_bytes), "corrupt fixture written")
	var corrupt_load := Library.load_library(corrupt, recipes, names)
	expect(not corrupt_load.ok and corrupt_load.entries == [] and bytes_of(corrupt) == corrupt_bytes, "corrupt JSON fails and is preserved")
	expect(not Library.save_library(corrupt, [extra_entry], recipes, names).ok and bytes_of(corrupt) == corrupt_bytes,
		"invalid save does not overwrite corrupt file")

	var unknown := file("unknown.json")
	var unknown_bytes := JSON.stringify({"version": 1, "entries": [], "owner": "x"}).to_utf8_buffer()
	expect(write_bytes(unknown, unknown_bytes), "unknown-field fixture written")
	expect(not Library.load_library(unknown, recipes, names).ok and bytes_of(unknown) == unknown_bytes, "unknown top-level field on disk fails, preserved")
	var dup_disk := JSON.stringify({"version": 1, "entries": [entry(5), entry(5)]}).to_utf8_buffer()
	expect(write_bytes(unknown, dup_disk), "duplicate fixture written")
	expect(not Library.load_library(unknown, recipes, names).ok and bytes_of(unknown) == dup_disk, "duplicate ids on disk fail, preserved")
	var bad_design_disk := JSON.stringify({"version": 1, "entries": [entry(5), bad_kind]}).to_utf8_buffer()
	expect(write_bytes(unknown, bad_design_disk), "bad design fixture written")
	expect(not Library.load_library(unknown, recipes, names).ok and bytes_of(unknown) == bad_design_disk, "malformed design on disk fails, preserved")
	var array_root := "[]".to_utf8_buffer()
	expect(write_bytes(unknown, array_root), "array root fixture written")
	expect(not Library.load_library(unknown, recipes, names).ok and bytes_of(unknown) == array_root, "array JSON root fails, preserved")

	var head := "{\"version\":1,".to_utf8_buffer()
	var tail := "\"entries\":[]}".to_utf8_buffer()
	var exact := file("exact.json")
	var exact_bytes := PackedByteArray()
	exact_bytes.append_array(head)
	var padding := PackedByteArray()
	padding.resize(Library.MAX_BYTES - head.size() - tail.size())
	padding.fill(32)
	exact_bytes.append_array(padding)
	exact_bytes.append_array(tail)
	expect(exact_bytes.size() == Library.MAX_BYTES and write_bytes(exact, exact_bytes), "exact 2MiB fixture written")
	var exact_load := Library.load_library(exact, recipes, names)
	expect(exact_load.ok and exact_load.entries == [], "file of exactly 2MiB is accepted")
	var big := file("big.json")
	var big_bytes := exact_bytes.duplicate()
	big_bytes.insert(head.size(), 32)
	expect(big_bytes.size() == Library.MAX_BYTES + 1 and write_bytes(big, big_bytes), "2MiB+1 fixture written")
	var big_load := Library.load_library(big, recipes, names)
	expect(not big_load.ok and big_load.entries == [], "file over 2MiB rejected")
	expect(FileAccess.get_file_as_bytes(big) == big_bytes, "oversized file preserved byte-for-byte")

	# 有效save仍可正常取代既有檔案；不留暫存檔。
	expect(Library.save_library(lib, [entry(7)], recipes, names).ok, "valid save replaces existing library")
	var replaced := Library.load_library(lib, recipes, names)
	expect(replaced.ok and ids(replaced.entries) == [id_for(7)], "replacement reopens with new content")
	expect(only_files(["library.json", "corrupt.json", "unknown.json", "exact.json", "big.json"]),
		"no staged temp files left after successful and failed saves")

# 只刪除本測試建立的特定檔案與資料夾；不遞迴刪除。
func cleanup() -> void:
	for leaf in ["library.json", "corrupt.json", "unknown.json", "exact.json", "big.json"]:
		if FileAccess.file_exists(file(leaf)):
			DirAccess.remove_absolute(file(leaf))
	if DirAccess.dir_exists_absolute(file("folder.json")):
		DirAccess.remove_absolute(file("folder.json"))
	var leftover := DirAccess.remove_absolute(base)
	expect(leftover == OK, "isolated test directory removed (fails if unexpected files remain)")
