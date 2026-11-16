extends RefCounted
## Durable "submitted but not yet confirmed" blueprint record
## (docs/blueprint-client-contract.md「Controller 與本機保存」).
##
## One file per (personal library, world scope):
##   library_path + ".pending-" + scope.sha256_text().left(16) + ".json"
## The path is never derived from player / blueprint names. Version 1 holds
## exactly: version, scope, actor, nonce, design, origin{x,y}, turns, hash,
## region, epoch. `actor` is the PUBLIC own_id (16 lowercase hex); no raw
## token, ticket, password or credential is ever stored.
##
## Pure static helpers: no World preload (callers pass World.BUILD/World.NAMES),
## no signals, no network. Saving goes through Library.write_staged (temp file,
## flush, rename). A corrupt / foreign file is never overwritten or deleted by
## these helpers; callers surface the reason and keep the file.

const Design = preload("res://scripts/blueprint_design.gd")
const Library = preload("res://scripts/blueprint_library.gd")
const Regions = preload("res://scripts/regions.gd")

const VERSION := 1
const MAX_BYTES := 256 * 1024
const MAX_SCOPE := 1024
const ACTOR_LENGTH := 16
const NONCE_LENGTH := 32
const HASH_LENGTH := 64
const MAX_EPOCH := 1000000000000
const KEYS: Array[String] = ["version", "scope", "actor", "nonce", "design", "origin", "turns", "hash", "region", "epoch"]

## Pending file path for this library and world scope; "" when either is invalid.
static func path_for(library_path: Variant, scope: Variant) -> String:
	if not Library.path_problem(library_path).is_empty() or not valid_scope(scope):
		return ""
	return String(library_path) + ".pending-" + String(scope).sha256_text().left(16) + ".json"

## Builds and fully validates a fresh record. {ok, reason, record}.
static func make(scope: String, actor: String, nonce: String, design: Variant, origin: Vector2i, turns: int, hash: String, region: String, epoch: int, recipes: Dictionary, item_names: Dictionary) -> Dictionary:
	var raw := {"version": VERSION, "scope": scope, "actor": actor, "nonce": nonce,
		"design": design, "origin": {"x": origin.x, "y": origin.y}, "turns": turns,
		"hash": hash, "region": region, "epoch": epoch}
	return validate(raw, scope, recipes, item_names)

## Strict validation. Unknown/missing fields, wrong types, a different scope or
## an invalid design reject the whole record. {ok, reason, record}.
static func validate(raw: Variant, expected_scope: Variant, recipes: Dictionary, item_names: Dictionary) -> Dictionary:
	if not raw is Dictionary:
		return _fail("待確認施工記錄格式錯誤。")
	var source: Dictionary = raw
	if source.size() != KEYS.size():
		return _fail("待確認施工記錄含有未知或缺少的欄位。")
	for key in source:
		if typeof(key) != TYPE_STRING or not KEYS.has(String(key)):
			return _fail("待確認施工記錄含有未知的欄位。")
	for key in KEYS:
		if not source.has(key):
			return _fail("待確認施工記錄缺少欄位 %s。" % key)
	if Design._as_int(source.version, VERSION, VERSION) == Design.BAD_INT:
		return _fail("不支援的待確認施工記錄版本。")
	if not valid_scope(source.scope) or not valid_scope(expected_scope) or String(source.scope) != String(expected_scope):
		return _fail("待確認施工記錄不屬於目前的世界。")
	if not lower_hex(source.actor, ACTOR_LENGTH):
		return _fail("待確認施工記錄的島民識別無效。")
	if not lower_hex(source.nonce, NONCE_LENGTH):
		return _fail("待確認施工記錄的施工編號無效。")
	if not lower_hex(source.hash, HASH_LENGTH):
		return _fail("待確認施工記錄的報價資料無效。")
	var checked: Dictionary = Design.validate(source.design, recipes, item_names)
	if checked.get("ok") != true or not checked.get("blueprint") is Dictionary:
		return _fail("待確認施工記錄的藍圖無效：" + str(checked.get("reason", "")))
	var origin_value: Variant = source.origin
	if not origin_value is Dictionary or (origin_value as Dictionary).size() != 2:
		return _fail("待確認施工記錄的位置格式錯誤。")
	var origin_dict: Dictionary = origin_value
	for key in origin_dict:
		if typeof(key) != TYPE_STRING or not String(key) in ["x", "y"]:
			return _fail("待確認施工記錄的位置格式錯誤。")
	if not origin_dict.has("x") or not origin_dict.has("y"):
		return _fail("待確認施工記錄的位置格式錯誤。")
	var x: int = Design._as_int(origin_dict.x, -Design.COORD_LIMIT, Design.COORD_LIMIT)
	var y: int = Design._as_int(origin_dict.y, -Design.COORD_LIMIT, Design.COORD_LIMIT)
	if x == Design.BAD_INT or y == Design.BAD_INT:
		return _fail("待確認施工記錄的位置超出範圍。")
	var turns: int = Design._as_int(source.turns, 0, 3)
	if turns == Design.BAD_INT:
		return _fail("待確認施工記錄的旋轉次數無效。")
	if typeof(source.region) != TYPE_STRING or not Regions.ALL.has(String(source.region)):
		return _fail("待確認施工記錄的區域無效。")
	var epoch: int = Design._as_int(source.epoch, 0, MAX_EPOCH)
	if epoch == Design.BAD_INT:
		return _fail("待確認施工記錄的旅程編號無效。")
	var record := {"version": VERSION, "scope": String(source.scope), "actor": String(source.actor),
		"nonce": String(source.nonce), "design": (checked.blueprint as Dictionary).duplicate(true),
		"origin": {"x": x, "y": y}, "turns": turns, "hash": String(source.hash),
		"region": String(source.region), "epoch": epoch}
	return {"ok": true, "reason": "", "record": record}

## Missing file: {ok:true, missing:true, record:{}}. Directory, unreadable,
## oversized, corrupt or foreign-scope files fail and are left untouched.
static func load_pending(path: Variant, expected_scope: Variant, recipes: Dictionary, item_names: Dictionary) -> Dictionary:
	var bad := Library.path_problem(path)
	if not bad.is_empty():
		return _fail("待確認施工記錄路徑無效。")
	if DirAccess.dir_exists_absolute(path):
		return _fail("待確認施工記錄路徑是資料夾，已保留原狀。")
	if not FileAccess.file_exists(path):
		return {"ok": true, "reason": "", "record": {}, "missing": true}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("無法讀取待確認施工記錄，已保留原檔。")
	var length := file.get_length()
	if length > MAX_BYTES:
		file.close()
		return _fail("待確認施工記錄過大，已保留原檔。")
	var bytes := file.get_buffer(length)
	var status := file.get_error()
	file.close()
	if bytes.size() != length or (status != OK and status != ERR_FILE_EOF):
		return _fail("讀取待確認施工記錄時發生錯誤，已保留原檔。")
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return _fail("待確認施工記錄損壞，已保留原檔。")
	var checked := validate(parser.data, expected_scope, recipes, item_names)
	if not checked.ok:
		checked.reason = String(checked.reason) + "已保留原檔。"
		return checked
	checked.missing = false
	return checked

## Writes a NEW record atomically. Refuses to replace any existing file so a
## corrupt or older record is never silently lost. "" on success, else reason.
static func save_pending(path: Variant, record: Variant, recipes: Dictionary, item_names: Dictionary) -> String:
	var bad := Library.path_problem(path)
	if not bad.is_empty():
		return "待確認施工記錄路徑無效，未送出施工。"
	if not record is Dictionary:
		return "待確認施工記錄格式錯誤，未送出施工。"
	var checked := validate(record, (record as Dictionary).get("scope"), recipes, item_names)
	if not checked.ok:
		return "待確認施工記錄無效，未送出施工：" + String(checked.reason)
	if DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path):
		return "已有另一筆待確認施工記錄，未送出施工。"
	var bytes := JSON.stringify(checked.record).to_utf8_buffer()
	if bytes.size() > MAX_BYTES:
		return "待確認施工記錄超過256KiB上限，未送出施工。"
	var problem := Library.write_staged(path, bytes)
	if not problem.is_empty():
		return "無法保存待確認施工記錄，未送出施工。"
	return ""

## Deletes the record file. "" when it is gone afterwards (including when it was
## already missing), else a reason and the file is kept.
static func remove_pending(path: Variant) -> String:
	if not Library.path_problem(path).is_empty():
		return "待確認施工記錄路徑無效，無法清除。"
	if DirAccess.dir_exists_absolute(path):
		return "待確認施工記錄路徑是資料夾，無法清除。"
	if not FileAccess.file_exists(path):
		return ""
	if DirAccess.remove_absolute(path) != OK or FileAccess.file_exists(path):
		return "無法刪除待確認施工記錄，已保留記錄。"
	return ""

static func valid_scope(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = value
	if text.is_empty() or text.length() > MAX_SCOPE or text.strip_edges() != text:
		return false
	return not Design._has_control(text)

static func lower_hex(value: Variant, length: int) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = value
	if text.length() != length:
		return false
	for i in length:
		var ch := text.unicode_at(i)
		if not ((ch >= 48 and ch <= 57) or (ch >= 97 and ch <= 102)):
			return false
	return true

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "record": {}}
