extends RefCounted
## Building blueprint data module, stage one (docs/blueprint-integration.md).
##
## Pure static data functions: capture / validate / rotate / base_cost.
## No World preload (callers pass World.BUILD and World.NAMES), no file I/O,
## no network or save changes. Every output is freshly built from primitive
## values, so no reference into caller-owned snapshots or payloads escapes.
## Untrusted input is size-checked before it is iterated, so huge arrays or
## dictionaries are rejected in O(1) instead of being scanned.
##
## All functions return {ok: bool, reason: String, ...}; on failure no
## blueprint/cost is attached.

## logistics.gd has no preloads, so this cannot form a cycle with World.
const LOGISTICS = preload("res://scripts/logistics.gd")

const VERSION := 1
const NAME_MIN := 1
const NAME_MAX := 32
const NAME_RAW_MAX := 256
const SIZE_MIN := 1
const SIZE_MAX := 16
const MAX_PIECES := 768
const MAX_AREA_CELLS := 256
const COORD_LIMIT := 10000
const MAX_TOTAL := 1000000000
const MAX_KIND_LEN := 64
const MAX_OWNER_LEN := 64
const MAX_RECIPE_KEYS := 64
const DIR_COUNT := 4
const LAYERS: Array[String] = ["ground", "objects", "roofs"]
const GROUND_KINDS: Array[String] = ["floor", "path"]
const ROOF_KINDS: Array[String] = ["roof","greenhouse_roof"]
const CONVEYOR := "conveyor"
const TOP_KEYS: Array[String] = ["version", "name", "width", "height", "pieces"]
const PIECE_KEYS: Array[String] = ["kind", "x", "y", "settings", "style"]
const BUILD_STYLES = preload("res://scripts/build_style_catalog.gd")
const SETTINGS_KEYS: Array[String] = ["dir", "filter"]
const BAD_INT := -4611686018427387904

# ---------------------------------------------------------------- public API

## Validates and normalises an untrusted blueprint payload.
static func validate(raw: Variant, recipes: Variant, item_names: Variant) -> Dictionary:
	var parsed: Dictionary = _normalize(raw, recipes, item_names)
	if not bool(parsed.ok):
		return _fail(String(parsed.reason))
	return {"ok": true, "reason": "", "blueprint": parsed.blueprint}

## Captures the caller's own layout inside `area` from a CURRENT-REGION snapshot
## ({ground, objects, roofs} keyed by "x,y"). Only type, relative position and
## conveyor dir/filter are copied; nothing else from the source objects is read
## into the result.
static func capture(snapshot: Variant, owner: Variant, area: Variant, name: Variant, recipes: Variant, item_names: Variant) -> Dictionary:
	if not (recipes is Dictionary):
		return _fail("建造配方資料有誤")
	if not (item_names is Dictionary):
		return _fail("物品名稱資料有誤")
	if not _is_text(owner) or not _valid_owner(String(owner)):
		return _fail("無法確認藍圖擁有者")
	if not (area is Rect2i):
		return _fail("擷取範圍必須是整數格子矩形")
	if area.size.x < SIZE_MIN or area.size.y < SIZE_MIN:
		return _fail("擷取範圍必須有正數寬高")
	if area.size.x > SIZE_MAX or area.size.y > SIZE_MAX or area.size.x * area.size.y > MAX_AREA_CELLS:
		return _fail("擷取範圍最大 %d×%d 格" % [SIZE_MAX, SIZE_MAX])
	var x0: int = area.position.x
	var y0: int = area.position.y
	var x1: int = x0 + area.size.x - 1
	var y1: int = y0 + area.size.y - 1
	if absi(x0) > COORD_LIMIT or absi(y0) > COORD_LIMIT or absi(x1) > COORD_LIMIT or absi(y1) > COORD_LIMIT:
		return _fail("擷取範圍超出座標限制")
	var clean_name: Dictionary = _clean_name(name)
	if not bool(clean_name.ok):
		return _fail(String(clean_name.reason))
	if not (snapshot is Dictionary):
		return _fail("世界快照資料有誤")
	var snap: Dictionary = snapshot
	var recipe_map: Dictionary = recipes
	var names_map: Dictionary = item_names
	var layer_maps: Array[Dictionary] = []
	for layer_name: String in LAYERS:
		if not snap.has(layer_name):
			layer_maps.append({})
			continue
		var layer_value: Variant = snap[layer_name]
		if not (layer_value is Dictionary):
			return _fail("世界快照的%s層資料有誤" % layer_name)
		var layer_dict: Dictionary = layer_value
		layer_maps.append(layer_dict)
	var pieces: Array = []
	var omitted: int = 0
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var cell_key: String = "%d,%d" % [x, y]
			for li: int in LAYERS.size():
				var layer_dict: Dictionary = layer_maps[li]
				if not layer_dict.has(cell_key):
					continue
				var entry: Variant = layer_dict[cell_key]
				if not (entry is Dictionary):
					return _fail("範圍內有損壞的建物資料 (%s)" % cell_key)
				var obj: Dictionary = entry
				var kind_value: Variant = obj.get("type")
				if not _is_text(kind_value):
					return _fail("範圍內有損壞的建物資料 (%s)" % cell_key)
				var kind: String = String(kind_value)
				if kind.length() > MAX_KIND_LEN or not _known_kind(recipe_map, kind):
					return _fail("範圍內有無法建造的物件 (%s)" % cell_key)
				if _layer_index(kind) != li:
					return _fail("範圍內的建物圖層不符 (%s)" % cell_key)
				var owner_value: Variant = obj.get("owner")
				if not _is_text(owner_value) or String(owner_value) == "":
					return _fail("範圍內有擁有者不明的建物 (%s)" % cell_key)
				if String(owner_value) != owner:
					return _fail("範圍內有他人的建物，請縮小範圍 (%s)" % cell_key)
				if obj.has("auto"):
					var auto_value: Variant = obj["auto"]
					if typeof(auto_value) != TYPE_BOOL:
						return _fail("範圍內有損壞的屋頂資料 (%s)" % cell_key)
					if bool(auto_value):
						if kind not in ROOF_KINDS:
							return _fail("範圍內有損壞的建物資料 (%s)" % cell_key)
						omitted += 1
						continue
				var piece: Dictionary = {"kind": kind, "x": x - x0, "y": y - y0}
				if obj.has("style"):piece.style=obj.style
				if kind == CONVEYOR:
					var dir: int = _as_int(obj.get("dir"), 0, DIR_COUNT - 1)
					if dir == BAD_INT:
						return _fail("範圍內的輸送帶方向資料有誤 (%s)" % cell_key)
					var filter_value: Variant = obj.get("filter")
					if not _valid_filter(filter_value, names_map):
						return _fail("範圍內的輸送帶篩選資料有誤 (%s)" % cell_key)
					piece["settings"] = {"dir": dir, "filter": String(filter_value)}
				pieces.append(piece)
	if pieces.is_empty():
		return _fail("範圍內沒有可存成藍圖的建物")
	var raw: Dictionary = {"version": VERSION, "name": String(clean_name.value), "width": area.size.x, "height": area.size.y, "pieces": pieces}
	var parsed: Dictionary = _normalize(raw, recipes, item_names)
	if not bool(parsed.ok):
		return _fail(String(parsed.reason))
	return {"ok": true, "reason": "", "blueprint": parsed.blueprint, "auto_roofs_omitted": omitted}

## Rotates clockwise by 0..3 quarter turns: (x,y) -> (height-1-y, x), swapping
## width/height; conveyor dir advances by one per turn (mod 4). Placement
## feasibility at a new location is NOT checked here.
static func rotate(raw: Variant, quarter_turns: Variant, recipes: Variant, item_names: Variant) -> Dictionary:
	var turns:int=_as_int(quarter_turns,0,3)
	if turns==BAD_INT:
		return _fail("旋轉次數只能是 0 到 3")
	quarter_turns=turns
	var parsed: Dictionary = _normalize(raw, recipes, item_names)
	if not bool(parsed.ok):
		return _fail(String(parsed.reason))
	var bp: Dictionary = parsed.blueprint
	var width: int = int(bp.width)
	var height: int = int(bp.height)
	var source: Array = bp.pieces
	var pieces: Array = []
	for item: Variant in source:
		var piece: Dictionary = item
		var px: int = int(piece.x)
		var py: int = int(piece.y)
		var w: int = width
		var h: int = height
		for _turn: int in quarter_turns:
			var nx: int = h - 1 - py
			var ny: int = px
			px = nx
			py = ny
			var t: int = w
			w = h
			h = t
		var out: Dictionary = {"kind": String(piece.kind), "x": px, "y": py}
		if piece.has("style"):out.style=piece.style
		if piece.has("settings"):
			var settings: Dictionary = piece.settings
			out["settings"] = {"dir": (int(settings.dir) + quarter_turns) % DIR_COUNT, "filter": String(settings.filter)}
		pieces.append(out)
	var new_w: int = width if quarter_turns % 2 == 0 else height
	var new_h: int = height if quarter_turns % 2 == 0 else width
	var rotated: Dictionary = {"version": VERSION, "name": String(bp.name), "width": new_w, "height": new_h, "pieces": pieces}
	var again: Dictionary = _normalize(rotated, recipes, item_names)
	if not bool(again.ok):
		return _fail(String(again.reason))
	return {"ok": true, "reason": "", "blueprint": again.blueprint}

## Base material total of every piece's recipe. NOT a final price: automatic
## roofs and existing-ground differences must be quoted by the later
## authoritative preview.
static func base_cost(raw: Variant, recipes: Variant, item_names: Variant) -> Dictionary:
	var parsed: Dictionary = _normalize(raw, recipes, item_names)
	if not bool(parsed.ok):
		return _fail(String(parsed.reason))
	var bp: Dictionary = parsed.blueprint
	var recipe_map: Dictionary = recipes
	var names_map: Dictionary = item_names
	var units_by_kind: Dictionary = {}
	var totals: Dictionary = {}
	var source: Array = bp.pieces
	for item: Variant in source:
		var piece: Dictionary = item
		var kind: String = String(piece.kind)
		if not units_by_kind.has(kind):
			var units: Dictionary = _recipe_units(recipe_map[kind], names_map)
			if not bool(units.ok):
				return _fail("「%s」的建造配方有誤" % kind)
			units_by_kind[kind] = units.units
		var kind_units: Dictionary = units_by_kind[kind]
		for material: Variant in kind_units:
			var key: String = String(material)
			var next: int = int(totals.get(key, 0)) + int(kind_units[material])
			if next > MAX_TOTAL:
				return _fail("藍圖材料總量超出上限")
			totals[key] = next
	var keys: Array = totals.keys()
	keys.sort()
	var cost: Dictionary = {}
	for key: Variant in keys:
		cost[String(key)] = int(totals[key])
	return {"ok": true, "reason": "", "cost": cost}

# ---------------------------------------------------------------- internals

static func _normalize(raw: Variant, recipes: Variant, item_names: Variant) -> Dictionary:
	if not (recipes is Dictionary):
		return _bad("建造配方資料有誤")
	if not (item_names is Dictionary):
		return _bad("物品名稱資料有誤")
	if not (raw is Dictionary):
		return _bad("藍圖資料格式有誤")
	var recipe_map: Dictionary = recipes
	var names_map: Dictionary = item_names
	var top: Dictionary = raw
	if top.size() != TOP_KEYS.size():
		return _bad("藍圖欄位不正確")
	var fields: Dictionary = _fields(top, TOP_KEYS)
	if not bool(fields.ok):
		return _bad("藍圖欄位不正確")
	var values: Dictionary = fields.values
	for required: String in TOP_KEYS:
		if not values.has(required):
			return _bad("藍圖缺少欄位 %s" % required)
	if _as_int(values["version"], VERSION, VERSION) == BAD_INT:
		return _bad("不支援的藍圖版本")
	var clean_name: Dictionary = _clean_name(values["name"])
	if not bool(clean_name.ok):
		return _bad(String(clean_name.reason))
	var width: int = _as_int(values["width"], SIZE_MIN, SIZE_MAX)
	var height: int = _as_int(values["height"], SIZE_MIN, SIZE_MAX)
	if width == BAD_INT or height == BAD_INT:
		return _bad("藍圖寬高必須是 %d 到 %d 的整數" % [SIZE_MIN, SIZE_MAX])
	var pieces_value: Variant = values["pieces"]
	if not (pieces_value is Array):
		return _bad("藍圖片段格式有誤")
	var raw_pieces: Array = pieces_value
	if raw_pieces.is_empty():
		return _bad("藍圖至少需要一個建物")
	if raw_pieces.size() > MAX_PIECES:
		return _bad("藍圖最多 %d 個建物" % MAX_PIECES)
	# One slot per (layer, y, x): duplicate detection and the canonical
	# ground→objects→roofs, y, x order in one bounded pass (≤ 3×256 slots).
	var cells: int = width * height
	var slots: Array = []
	slots.resize(LAYERS.size() * cells)
	for entry: Variant in raw_pieces:
		var piece: Dictionary = _piece(entry, width, height, recipe_map, names_map)
		if not bool(piece.ok):
			return _bad(String(piece.reason))
		var out: Dictionary = piece.piece
		var layer: int = int(piece.layer)
		var px: int = int(out.x)
		var py: int = int(out.y)
		var index: int = layer * cells + py * width + px
		if slots[index] != null:
			return _bad("同一格同一層只能有一個建物 (%d,%d)" % [px, py])
		slots[index] = out
	var pieces: Array = []
	for slot: Variant in slots:
		if slot != null:
			pieces.append(slot)
	var blueprint: Dictionary = {"version": VERSION, "name": String(clean_name.value), "width": width, "height": height, "pieces": pieces}
	return {"ok": true, "reason": "", "blueprint": blueprint}

static func _piece(entry: Variant, width: int, height: int, recipe_map: Dictionary, names_map: Dictionary) -> Dictionary:
	if not (entry is Dictionary):
		return _bad("藍圖片段格式有誤")
	var raw_piece: Dictionary = entry
	if raw_piece.size() < 3 or raw_piece.size() > PIECE_KEYS.size():
		return _bad("藍圖片段欄位不正確")
	var fields: Dictionary = _fields(raw_piece, PIECE_KEYS)
	if not bool(fields.ok):
		return _bad("藍圖片段欄位不正確")
	var values: Dictionary = fields.values
	if not values.has("kind") or not values.has("x") or not values.has("y"):
		return _bad("藍圖片段缺少 kind/x/y")
	var kind_value: Variant = values["kind"]
	if not _is_text(kind_value):
		return _bad("藍圖片段種類有誤")
	var kind: String = String(kind_value)
	if kind.length() > MAX_KIND_LEN or not _known_kind(recipe_map, kind):
		return _bad("藍圖含有目前無法建造的物件")
	var x: int = _as_int(values["x"], 0, width - 1)
	var y: int = _as_int(values["y"], 0, height - 1)
	if x == BAD_INT or y == BAD_INT:
		return _bad("藍圖片段座標超出範圍")
	var out: Dictionary = {"kind": kind, "x": x, "y": y}
	if values.has("style"):
		var style: Variant = values.style
		if not style is String or style.length()>16 or BUILD_STYLES.entry(style+"."+kind).is_empty():
			return _bad("藍圖片段的建築風格無效")
		out.style=style
	if values.has("settings"):
		if kind != CONVEYOR:
			return _bad("只有輸送帶可以附帶設定")
		var settings_value: Variant = values["settings"]
		if not (settings_value is Dictionary):
			return _bad("輸送帶設定格式有誤")
		var raw_settings: Dictionary = settings_value
		if raw_settings.size() != SETTINGS_KEYS.size():
			return _bad("輸送帶設定欄位不正確")
		var setting_fields: Dictionary = _fields(raw_settings, SETTINGS_KEYS)
		if not bool(setting_fields.ok):
			return _bad("輸送帶設定欄位不正確")
		var settings: Dictionary = setting_fields.values
		if not settings.has("dir") or not settings.has("filter"):
			return _bad("輸送帶設定缺少 dir/filter")
		var dir: int = _as_int(settings["dir"], 0, DIR_COUNT - 1)
		if dir == BAD_INT:
			return _bad("輸送帶方向必須是 0 到 3")
		var filter_value: Variant = settings["filter"]
		if not _valid_filter(filter_value, names_map):
			return _bad("輸送帶篩選物品無效")
		out["settings"] = {"dir": dir, "filter": String(filter_value)}
	elif kind == CONVEYOR:
		# Materialise default orientation before any rotation. Otherwise an
		# omitted-settings belt stays UP while the surrounding layout rotates.
		var defaults:Dictionary=LOGISTICS.fresh()
		if not _valid_filter(defaults.filter,names_map):return _bad("輸送帶預設篩選物品無效")
		out["settings"]={"dir":int(defaults.dir),"filter":String(defaults.filter)}
	return {"ok": true, "reason": "", "piece": out, "layer": _layer_index(kind)}

## Maps String/StringName keys to their values, rejecting non-text keys,
## unknown keys and String/StringName duplicates. Callers check size first.
static func _fields(source: Dictionary, allowed: Array[String]) -> Dictionary:
	var values: Dictionary = {}
	for key: Variant in source:
		if not _is_text(key):
			return {"ok": false}
		var name: String = String(key)
		if name not in allowed or values.has(name):
			return {"ok": false}
		values[name] = source[key]
	return {"ok": true, "values": values}

static func _layer_index(kind: String) -> int:
	if kind in GROUND_KINDS:
		return 0
	if kind in ROOF_KINDS:
		return 2
	return 1

static func _known_kind(recipe_map: Dictionary, kind: String) -> bool:
	if kind == "" or not recipe_map.has(kind):
		return false
	return recipe_map[kind] is Dictionary

## Current game conveyors accept only LOGISTICS.FILTERS (see
## World.operate_logistics); the id must also exist in the caller's item names.
static func _valid_filter(value: Variant, names_map: Dictionary) -> bool:
	if not _is_text(value):
		return false
	var filter: String = String(value)
	if filter.length() > MAX_KIND_LEN:
		return false
	return filter in LOGISTICS.FILTERS and names_map.has(filter)

static func _recipe_units(recipe_value: Variant, names_map: Dictionary) -> Dictionary:
	if not (recipe_value is Dictionary):
		return {"ok": false}
	var recipe: Dictionary = recipe_value
	if recipe.size() > MAX_RECIPE_KEYS:
		return {"ok": false}
	var units: Dictionary = {}
	for key: Variant in recipe:
		if not _is_text(key):
			return {"ok": false}
		var material: String = String(key)
		if material == "name":
			continue
		if units.has(material) or not names_map.has(material):
			return {"ok": false}
		var amount: int = _as_int(recipe[key], 1, MAX_TOTAL)
		if amount == BAD_INT:
			return {"ok": false}
		units[material] = amount
	if units.is_empty():
		return {"ok": false}
	return {"ok": true, "units": units}

static func _clean_name(value: Variant) -> Dictionary:
	if not _is_text(value):
		return _bad("藍圖名稱必須是文字")
	var text: String = String(value)
	if text.length() > NAME_RAW_MAX:
		return _bad("藍圖名稱最多 %d 字" % NAME_MAX)
	if _has_control(text):
		return _bad("藍圖名稱不可含控制字元")
	var stripped: String = text.strip_edges()
	if stripped.length() < NAME_MIN or stripped.length() > NAME_MAX:
		return _bad("藍圖名稱需為 %d 到 %d 字" % [NAME_MIN, NAME_MAX])
	return {"ok": true, "reason": "", "value": stripped}

static func _valid_owner(owner: String) -> bool:
	if owner == "" or owner.length() > MAX_OWNER_LEN or owner.strip_edges() != owner:
		return false
	return not _has_control(owner)

static func _has_control(text: String) -> bool:
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		if code < 32 or (code >= 127 and code <= 159):
			return true
	return false

static func _is_text(value: Variant) -> bool:
	var t: int = typeof(value)
	return t == TYPE_STRING or t == TYPE_STRING_NAME

## Strict integer: int, or finite integral float (JSON); bool and anything else
## rejected. Returns BAD_INT when invalid or outside [lo, hi].
static func _as_int(value: Variant, lo: int, hi: int) -> int:
	var n: int = BAD_INT
	var t: int = typeof(value)
	if t == TYPE_INT:
		n = int(value)
	elif t == TYPE_FLOAT:
		var f: float = float(value)
		if is_nan(f) or is_inf(f) or f != floorf(f) or absf(f) > 1.0e15:
			return BAD_INT
		n = int(f)
	else:
		return BAD_INT
	if n < lo or n > hi:
		return BAD_INT
	return n

static func _bad(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
