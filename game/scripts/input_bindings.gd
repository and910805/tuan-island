extends RefCounted

const DEFAULTS := {
	"move_up": KEY_W, "move_down": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"hoe": KEY_1, "seed": KEY_2, "water": KEY_3, "harvest": KEY_4, "axe": KEY_5,
	"pick": KEY_6, "build": KEY_7, "remove": KEY_8, "fish": KEY_F, "plant_tree": KEY_T,
	"till_area": KEY_U, "seed_area": KEY_I, "harvest_area": KEY_O, "move_object": KEY_R,
	"build_menu": KEY_B, "inventory": KEY_TAB, "interact": KEY_E, "seeds": KEY_C,
	"journal": KEY_J, "festival": KEY_G, "collection": KEY_L, "map": KEY_M, "zoom": KEY_Z,
	"fish_catch": KEY_SPACE, "area_modifier": KEY_SHIFT, "social": KEY_Q,
}
const LABELS := {
	"move_up": "向上移動", "move_down": "向下移動", "move_left": "向左移動", "move_right": "向右移動",
	"hoe": "鋤頭", "seed": "播種", "water": "澆水", "harvest": "採收", "axe": "斧頭",
	"pick": "十字鎬", "build": "建造工具", "remove": "拆除", "fish": "釣竿", "plant_tree": "種樹",
	"till_area": "手推耕田機", "seed_area": "手推播種機", "harvest_area": "手推收割機", "move_object": "搬移家具",
	"build_menu": "建造目錄", "inventory": "背包", "interact": "互動", "seeds": "選種子",
	"journal": "島民手帳", "festival": "風鈴接力", "collection": "生活圖鑑", "map": "地圖", "zoom": "切換視野",
	"fish_catch": "收竿", "area_modifier": "範圍操作修飾鍵", "social": "招呼與地圖標記",
}
const GROUPS := {
	"移動與互動": ["move_up", "move_down", "move_left", "move_right", "interact", "zoom"],
	"工具": ["hoe", "seed", "water", "harvest", "axe", "pick", "build", "remove", "fish", "fish_catch",
		"plant_tree", "till_area", "seed_area", "harvest_area", "move_object", "area_modifier"],
	"選單": ["inventory", "build_menu", "seeds", "journal", "festival", "collection", "map", "social"],
}
const MODIFIERS := [KEY_SHIFT, KEY_CTRL, KEY_ALT]
const PUNCTUATION := [KEY_MINUS, KEY_EQUAL, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_BACKSLASH,
	KEY_SEMICOLON, KEY_APOSTROPHE, KEY_COMMA, KEY_PERIOD, KEY_SLASH, KEY_QUOTELEFT]
const VERSION := 1

var path := "user://input-bindings.cfg"
var keys: Dictionary = DEFAULTS.duplicate()
# Physical codes currently held by events that had no logical keycode (the
# event_key() fallback). Input tracks logical and physical sets separately,
# so this keeps held polling on the same identity rule as matches().
var _fallback_held := {}

func load_preferences(file_path: String) -> bool:
	path = file_path
	keys = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(path) != OK or config.get_value("input", "version", 0) != VERSION:
		return false
	var candidate = config.get_value("input", "keys", {})
	if not candidate is Dictionary:
		return false
	if candidate.size() == DEFAULTS.size()-1 and not candidate.has("social"):
		candidate.social = KEY_NONE if KEY_Q in candidate.values() else KEY_Q
	if candidate.size() != DEFAULTS.size():
		return false
	var seen := {}
	for action in DEFAULTS:
		var key = candidate.get(action)
		if not key is int or (key != KEY_NONE and (not allowed(action, key) or seen.has(key))):
			return false
		if key != KEY_NONE:
			seen[key] = true
	keys = candidate
	return true

func rebind(action: String, key: int, transfer: bool = false) -> Dictionary:
	if not DEFAULTS.has(action):
		return result(false, "找不到這項操作。")
	if not allowed(action, key):
		return result(false, "請使用 Shift、Ctrl 或 Alt。" if action == "area_modifier" else "此鍵保留給介面，或無法用來綁定。")
	var candidate := keys.duplicate()
	for existing in keys:
		if existing == action or keys[existing] != key:
			continue
		if not transfer:
			var conflict := result(false, "此鍵已用於「%s」。" % LABELS[existing])
			conflict.conflict = existing
			return conflict
		candidate[existing] = KEY_NONE
	candidate[action] = key
	return commit(candidate)

func clear(action: String) -> Dictionary:
	if not DEFAULTS.has(action):
		return result(false, "找不到這項操作。")
	var candidate := keys.duplicate()
	candidate[action] = KEY_NONE
	return commit(candidate)

func restore_defaults() -> Dictionary:
	return commit(DEFAULTS.duplicate())

func label(action: String) -> String:
	var key: int = keys.get(action, KEY_NONE)
	return "未設定" if key == KEY_NONE else OS.get_keycode_string(key)

## Binding identity of a key event: exactly one code per event, so a key can
## never trigger two actions when its logical and physical codes disagree.
## Stored bindings and UI labels (OS.get_keycode_string) are logical keycodes,
## i.e. the unshifted key label of the active layout. Native Windows events
## always carry it, while physical_keycode can be unrelated (observed:
## keycode=KEY_5, physical_keycode=KEY_PAUSE). physical_keycode is used only
## when the event carries no usable logical code (synthetic/IME events).
static func event_key(event: InputEventKey) -> int:
	var logical: int = event.keycode
	if logical != KEY_NONE and logical != KEY_UNKNOWN:
		return logical
	var physical: int = event.physical_keycode
	if physical == KEY_UNKNOWN:
		return KEY_NONE
	return physical

func matches(action: String, event: InputEventKey) -> bool:
	var key: int = keys.get(action, KEY_NONE)
	if key == KEY_NONE or not event.pressed or event.echo or event_key(event) != key:
		return false
	return action == "area_modifier" or not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed)

## Feed every key event (main._input) so held polling can honour the fallback.
func observe(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	var physical: int = key_event.physical_keycode
	if physical == KEY_NONE:
		return
	if key_event.pressed and key_event.keycode in [KEY_NONE, KEY_UNKNOWN]:
		_fallback_held[physical] = true
	else:
		_fallback_held.erase(physical)

func pressed(action: String) -> bool:
	var key: int = keys.get(action, KEY_NONE)
	if key == KEY_NONE:
		return false
	if Input.is_key_pressed(key):
		return true
	# Input clears its physical set on focus loss, so a missed release cannot latch.
	return _fallback_held.has(key) and Input.is_physical_key_pressed(key)

static func allowed(action: String, key: int) -> bool:
	if action == "area_modifier":
		return key in MODIFIERS
	if key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		return action.begins_with("move_") and action != "move_object"
	return (key >= KEY_A and key <= KEY_Z) or (key >= KEY_0 and key <= KEY_9) or (
		key >= KEY_F1 and key <= KEY_F12) or key in [KEY_TAB, KEY_SPACE] or key in PUNCTUATION

func commit(candidate: Dictionary) -> Dictionary:
	var config := ConfigFile.new()
	config.set_value("input", "version", VERSION)
	config.set_value("input", "keys", candidate)
	var staged := path + ".tmp"
	if config.save(staged) != OK:
		return result(false, "無法儲存按鍵設定，已保留目前配置。")
	if DirAccess.rename_absolute(staged, path) != OK:
		DirAccess.remove_absolute(staged)
		return result(false, "無法更新按鍵設定，已保留目前配置。")
	keys = candidate
	return result(true, "已儲存按鍵設定。")

static func result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}
