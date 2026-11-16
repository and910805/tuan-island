extends RefCounted

# 個人藍圖庫資料層：單一JSON檔，路徑完全由呼叫者指定，絕不由藍圖名稱或ID組成。
# 不依賴World或admission_store，避免循環preload；recipes/item_names由呼叫者傳入。
# 只支援單一寫入者；不宣稱並行編輯或斷電後的持久性保證。

const Design = preload("res://scripts/blueprint_design.gd")

const VERSION := 1
const MAX_ENTRIES := 12
const MAX_BYTES := 2 * 1024 * 1024
const ID_LENGTH := 32
const HEX := "0123456789abcdef"

static func validate(raw, recipes: Dictionary, item_names: Dictionary) -> Dictionary:
	if not raw is Dictionary:
		return fail("藍圖庫格式錯誤。")
	if raw.size() != 2 or not raw.has("version") or not raw.has("entries"):
		return fail("藍圖庫含有未知或缺少的欄位。")
	if not is_whole(raw.version) or int(raw.version) != VERSION:
		return fail("不支援的藍圖庫版本。")
	var list = raw.entries
	if not list is Array:
		return fail("藍圖庫清單格式錯誤。")
	if list.size() > MAX_ENTRIES:
		return fail("藍圖庫最多只能存放%d份藍圖。" % MAX_ENTRIES)
	var seen := {}
	var normalized: Array = []
	for index in list.size():
		var entry = list[index]
		var label := "第%d份藍圖" % (index + 1)
		if not entry is Dictionary or entry.size() != 2 or not entry.has("id") or not entry.has("design"):
			return fail(label + "含有未知或缺少的欄位。")
		if not valid_id(entry.id):
			return fail(label + "的ID必須是32字元小寫十六進位。")
		if seen.has(entry.id):
			return fail(label + "的ID重複。")
		seen[entry.id] = true
		var checked = Design.validate(entry.design, recipes, item_names)
		if not checked is Dictionary or checked.get("ok") != true or not checked.get("blueprint") is Dictionary:
			var why: String = str(checked.get("reason", "")) if checked is Dictionary else ""
			return fail(label + "的設計無效" + ("：" + why if not why.is_empty() else "。"))
		normalized.append({"id": String(entry.id), "design": checked.blueprint.duplicate(true)})
	return {"ok": true, "reason": "", "entries": normalized}

static func load_library(path, recipes: Dictionary, item_names: Dictionary) -> Dictionary:
	var bad_path := path_problem(path)
	if not bad_path.is_empty():
		return fail(bad_path)
	if DirAccess.dir_exists_absolute(path):
		return fail("藍圖庫路徑是資料夾，無法讀取。")
	if not FileAccess.file_exists(path):
		var empty := {"ok": true, "reason": "", "entries": [], "missing": true}
		return empty
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fail("無法讀取藍圖庫檔案。")
	var length := file.get_length()
	if length > MAX_BYTES:
		file.close()
		return fail("藍圖庫檔案過大，已保留原檔。")
	var bytes := file.get_buffer(length)
	var status := file.get_error()
	file.close()
	if bytes.size() != length or (status != OK and status != ERR_FILE_EOF):
		return fail("讀取藍圖庫檔案時發生錯誤。")
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return fail("藍圖庫檔案損壞，已保留原檔。")
	var checked := validate(parser.data, recipes, item_names)
	if not checked.ok:
		checked.reason = "藍圖庫內容無效，已保留原檔：" + checked.reason
		return checked
	checked.missing = false
	return checked

static func save_library(path, entries, recipes: Dictionary, item_names: Dictionary) -> Dictionary:
	var bad_path := path_problem(path)
	if not bad_path.is_empty():
		return fail(bad_path)
	var checked := validate({"version": VERSION, "entries": entries}, recipes, item_names)
	if not checked.ok:
		checked.reason = "未儲存藍圖庫：" + checked.reason
		return checked
	if DirAccess.dir_exists_absolute(path):
		return fail("藍圖庫路徑是資料夾，未儲存。")
	var bytes := JSON.stringify({"version": VERSION, "entries": checked.entries}).to_utf8_buffer()
	if bytes.size() > MAX_BYTES:
		return fail("藍圖庫超過2MiB上限，未儲存。")
	var problem := write_staged(path, bytes)
	if not problem.is_empty():
		return fail(problem)
	return {"ok": true, "reason": "已儲存藍圖庫。", "entries": checked.entries.duplicate(true)}

# 先寫入隨機尾碼的暫存檔、flush並檢查錯誤，再以rename取代目標。
# 失敗時只移除本次建立的那一個暫存檔，原檔不動；不做任何遞迴刪除。
static func write_staged(path: String, bytes: PackedByteArray) -> String:
	var staged := path + ".stage-" + Crypto.new().generate_random_bytes(12).hex_encode()
	if FileAccess.file_exists(staged) or DirAccess.dir_exists_absolute(staged):
		return "暫存檔名稱衝突，未儲存藍圖庫。"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return "無法建立藍圖庫暫存檔，已保留原檔。"
	file.store_buffer(bytes)
	file.flush()
	var status := file.get_error()
	file.close()
	if status != OK:
		DirAccess.remove_absolute(staged)
		return "寫入藍圖庫暫存檔失敗，已保留原檔。"
	if DirAccess.rename_absolute(staged, path) != OK:
		DirAccess.remove_absolute(staged)
		return "無法替換藍圖庫檔案，已保留原檔。"
	return ""

static func path_problem(path) -> String:
	if not path is String or path.strip_edges().is_empty() or path != path.strip_edges():
		return "藍圖庫路徑無效。"
	if path.ends_with("/") or path.ends_with("\\") or path.get_file().is_empty():
		return "藍圖庫路徑必須是完整檔案路徑。"
	if path.get_file() in [".", ".."]:
		return "藍圖庫路徑無效。"
	return ""

static func valid_id(value) -> bool:
	if not value is String or value.length() != ID_LENGTH:
		return false
	for character in value:
		if not HEX.contains(character):
			return false
	return true

static func is_whole(value) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and value == floor(value) and absf(value) <= 1e15

static func fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "entries": []}
