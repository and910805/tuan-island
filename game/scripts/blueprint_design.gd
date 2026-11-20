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
const EdgeGrid = preload("res://scripts/edge_grid.gd")

const VERSION := 1
## Version 2 exists only for payloads that carry true edge pieces; edge-free payloads stay version 1.
const EDGE_VERSION := 2
const EDGE_KINDS: Array[String] = ["edge_wall", "edge_door", "edge_window"]
## Plan prices, same as EdgeConstruction.COSTS (not preloaded here: it would form a cycle with World).
const EDGE_COSTS := {
	"edge_wall": {"wood": 3},
	"edge_door": {"wood": 6, "fiber": 2},
	"edge_window": {"wood": 4, "glass": 1},
}
## 16x16 tiles on three layers (768) + 2*16*17 edges on a 16x16 box (544).
const MAX_PIECES_EDGE := 1312
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
const GROUND_KINDS: Array[String] = ["floor", "stone_floor", "path", "spring_pebble_path", Industry.LEAF_MAT]
const Greenhouse=preload("res://scripts/greenhouse_glass.gd")
const Terracotta = preload("res://scripts/terracotta_roof.gd")
const ROOF_KINDS: Array[String] = ["roof",Greenhouse.LEGACY_ROOF,Greenhouse.XINGHE_ROOF,Terracotta.KIND]
const Industry=preload("res://scripts/industry.gd")
const DOUBLE_BENCHES=preload("res://scripts/resident_goals.gd").DOUBLE_BENCHES
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
	var edges:Variant=snap.get("edges",{})
	if not edges is Dictionary:return _fail("世界快照的牆段資料有誤")
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
				var square_part:=Industry.square_part(obj)
				var is_square:=kind in Industry.FIXED_SQUARE_STATIONS or (kind in Industry.EXPANDABLE_STATIONS and obj.has(Industry.square_part_field(kind)))
				if is_square:
					if square_part<0 or square_part>=Industry.SQUARE_CELLS.size():return _fail("設備占地資料有誤。")
					var anchor:Vector2i=Vector2i(x,y)-Industry.SQUARE_CELLS[square_part]
					if not area.encloses(Rect2i(anchor,Vector2i(2,2))):return _fail("請把設備的四格都框進藍圖。")
					if square_part>0:continue
				if kind in Industry.ORIENTABLE_FOOTPRINTS:
					var offsets:=Industry.station_cells(kind,Industry.is_vertical(obj))
					if square_part<0 or square_part>=offsets.size():return _fail("家具占地資料有誤。")
					var origin:=Vector2i(x,y)-Vector2i(offsets[square_part])
					for offset:Vector2i in offsets:
						if not area.has_point(origin+offset):return _fail("請把家具的完整占地框進藍圖。")
					if square_part>0:continue
				# C13: a new 3x3 mill needs all nine cells inside the area and is captured once, from its anchor, with
				# its facing. A legacy 1x1 mill (no mill_part) stays a plain settings-less piece.
				var new_mill:=kind==Industry.MILL and square_part>=0
				var mill_facing:int=BAD_INT
				if new_mill:
					var mill_cells:=Industry.mill_cells()
					if square_part>=mill_cells.size():return _fail("磨坊占地資料有誤。")
					mill_facing=_as_int(obj.get(Industry.MILL_FACING),0,Industry.MILL_FACING_COUNT-1)
					if mill_facing==BAD_INT:return _fail("磨坊的方向資料有誤。")
					var mill_origin:=Vector2i(x,y)-Vector2i(mill_cells[square_part])
					for mill_offset:Vector2i in mill_cells:
						if not area.has_point(mill_origin+mill_offset):return _fail("請把磨坊的九格都框進藍圖。")
					if square_part>0:continue
				# C08: a captured legacy 1x1 bench (no workbench_part) stays a plain bench piece; a wide
				# bench needs both cells inside the area and is captured once, from its anchor.
				var wide_bench:=kind==Industry.WORKBENCH and square_part>=0
				if wide_bench:
					var bench_cells:=Industry.station_cells(kind,Industry.is_vertical(obj))
					if square_part>=bench_cells.size():return _fail("工作台占地資料有誤。")
					var bench_origin:=Vector2i(x,y)-Vector2i(bench_cells[square_part])
					for bench_offset_cell:Vector2i in bench_cells:
						if not area.has_point(bench_origin+bench_offset_cell):return _fail("請把工作台的兩格都框進藍圖。")
					if square_part>0:continue
				if kind in DOUBLE_BENCHES:
					var offset:=Vector2i.DOWN if obj.get("bench_vertical",false) else Vector2i.RIGHT
					if obj.get("bench_end",false):
						if not area.has_point(Vector2i(x,y)-offset):return _fail("請把長椅的兩格都框進藍圖。")
						continue
					if not area.has_point(Vector2i(x,y)+offset):return _fail("請把長椅的兩格都框進藍圖。")
				var piece: Dictionary = {"kind": kind, "x": x - x0, "y": y - y0}
				if obj.has("style"):piece.style=obj.style
				if kind in Industry.EXPANDABLE_STATIONS and is_square:piece.settings={"wide":true}
				if (kind in DOUBLE_BENCHES and obj.get("bench_vertical",false)) or (kind in Industry.ORIENTABLE_FOOTPRINTS and Industry.is_vertical(obj)):piece.settings={"vertical":true}
				if wide_bench:
					piece.settings={"wide":true}
					if Industry.is_vertical(obj):piece.settings.vertical=true
				if new_mill:piece.settings={"facing":mill_facing}
				if kind==Industry.LEAF_MAT and obj.has("leaf_mat_shade"):piece.settings={"leaf_mat_shade":obj.leaf_mat_shade}
				if kind==Industry.VINE_ARCH and obj.has("vine_color"):
					var settings:Dictionary=piece.get("settings",{})
					settings.vine_color=obj.vine_color
					piece.settings=settings
				if kind == CONVEYOR:
					var dir: int = _as_int(obj.get("dir"), 0, DIR_COUNT - 1)
					if dir == BAD_INT:
						return _fail("範圍內的輸送帶方向資料有誤 (%s)" % cell_key)
					var filter_value: Variant = obj.get("filter")
					if not _valid_filter(filter_value, names_map):
						return _fail("範圍內的輸送帶篩選資料有誤 (%s)" % cell_key)
					piece["settings"] = {"dir": dir, "filter": String(filter_value)}
				pieces.append(piece)
	# True edge pieces (v2). Every cell side in the area is asked for; an edge shared by two in-area
	# cells is seen twice and kept once. Rim edges count when one adjacent cell is inside.
	var edge_seen: Dictionary = {}
	var edge_count: int = 0
	if not edges.is_empty():
		for y: int in range(y0, y1 + 1):
			for x: int in range(x0, x1 + 1):
				for side: int in EdgeGrid.SIDE_COUNT:
					var id: String = EdgeGrid.key(Vector2i(x, y), side)
					if id == "" or edge_seen.has(id) or not edges.has(id):
						continue
					edge_seen[id] = true
					var row: Variant = edges[id]
					if not (row is Dictionary):
						return _fail("範圍內有損壞的牆段資料 (%s)" % id)
					var edge_kind: Variant = row.get("type")
					if not _is_text(edge_kind) or not is_edge_kind(String(edge_kind)):
						return _fail("範圍內有損壞的牆段資料 (%s)" % id)
					var edge_owner: Variant = row.get("owner")
					if not _is_text(edge_owner) or String(edge_owner) == "":
						return _fail("範圍內有擁有者不明的建物 (%s)" % id)
					if String(edge_owner) != owner:
						return _fail("範圍內有他人的建物，請縮小範圍 (%s)" % id)
					if row.has("open") and typeof(row["open"]) != TYPE_BOOL:
						return _fail("範圍內有損壞的牆段資料 (%s)" % id)
					var tile: Dictionary = _canon_edge(x - x0, y - y0, side, area.size.x, area.size.y)
					if tile.is_empty():
						return _fail("範圍內有損壞的牆段資料 (%s)" % id)
					pieces.append({"kind": String(edge_kind), "x": tile.x, "y": tile.y, "settings": {"side": tile.side}})
					edge_count += 1
	if pieces.is_empty():
		return _fail("範圍內沒有可存成藍圖的建物")
	var raw: Dictionary = {"version": EDGE_VERSION if edge_count > 0 else VERSION, "name": String(clean_name.value), "width": area.size.x, "height": area.size.y, "pieces": pieces}
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
		if is_edge_kind(piece.kind):
			# The in-area tile and its side turn together; normalize re-picks the canonical tile.
			var turned: Dictionary = EdgeGrid.rotate_cell(Vector2i(px, py), width, height, turns)
			if turned.is_empty():
				return _fail("牆段旋轉失敗")
			pieces.append({"kind": String(piece.kind), "x": turned.cell.x, "y": turned.cell.y, "settings": {"side": EdgeGrid.rotate_side(edge_side(piece), turns)}})
			continue
		var square:=is_square_piece(piece)
		var end:=Vector2i(px,py)+(Vector2i.ONE if square else bench_offset(piece))
		var rectangle:bool=piece.kind in [Industry.FOOT_BATH,Industry.COAST_AWNING,Industry.IMPERFECT_TEA_PAVILION]
		if rectangle or piece.kind in Industry.ARCHES:
			end=Vector2i(px,py)+Vector2i(Industry.station_cells(piece.kind,piece.get("settings",{}).get("vertical",false)).back())
		# C13: a new mill is a 3x3 whose facing advances one step per quarter turn (never a vertical flag).
		var mill:=is_mill_piece(piece)
		if mill:end=Vector2i(px,py)+Vector2i(Industry.mill_cells().back())
		var w: int = width
		var h: int = height
		for _turn: int in quarter_turns:
			var nx: int = h - 1 - py
			var ny: int = px
			end=Vector2i(h-1-end.y,end.x)
			px = nx
			py = ny
			var t: int = w
			w = h
			h = t
		var wide_bench:=is_wide_bench_piece(piece)
		var is_bench:bool=piece.kind in (DOUBLE_BENCHES+Industry.ORIENTABLE_FOOTPRINTS) or wide_bench
		var vertical:=absi(end.y-py)>absi(end.x-px) if rectangle else is_bench and end.y!=py
		var out: Dictionary = {"kind": String(piece.kind), "x": mini(px,end.x) if is_bench or square or mill else px, "y": mini(py,end.y) if is_bench or square or mill else py}
		if piece.has("style"):out.style=piece.style
		if vertical:out.settings={"vertical":true}
		if mill:out.settings={"facing":(int(piece.settings.facing)+quarter_turns)%Industry.MILL_FACING_COUNT}
		if wide_bench:out.settings={"wide":true,"vertical":true} if vertical else {"wide":true}
		if piece.kind==Industry.LEAF_MAT and piece.has("settings"):out.settings=piece.settings.duplicate()
		if piece.kind==Industry.VINE_ARCH and piece.get("settings",{}).has("vine_color"):
			var arch_settings:Dictionary=out.get("settings",{})
			arch_settings.vine_color=piece.settings.vine_color
			out.settings=arch_settings
		if piece.kind in Industry.EXPANDABLE_STATIONS and square:out.settings={"wide":true}
		if piece.kind==CONVEYOR and piece.has("settings"):
			var settings: Dictionary = piece.settings
			out["settings"] = {"dir": (int(settings.dir) + quarter_turns) % DIR_COUNT, "filter": String(settings.filter)}
		pieces.append(out)
	var new_w: int = width if quarter_turns % 2 == 0 else height
	var new_h: int = height if quarter_turns % 2 == 0 else width
	var rotated: Dictionary = {"version": int(bp.version), "name": String(bp.name), "width": new_w, "height": new_h, "pieces": pieces}
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
		# C13: a settings-less mill piece is the legacy 1x1 (captured from a kit mill): it keeps costing one
		# mill_kit, while a mill piece with settings.facing costs the new BUILD.mill materials.
		var cost_key: String = kind
		if kind == Industry.MILL and not is_mill_piece(piece):
			cost_key = kind + ":legacy"
		if not units_by_kind.has(cost_key):
			var source_recipe: Variant = edge_recipe(kind) if is_edge_kind(kind) else (Industry.LEGACY_MILL_COST if cost_key != kind else recipe_map[kind])
			var units: Dictionary = _recipe_units(source_recipe, names_map)
			if not bool(units.ok):
				return _fail("「%s」的建造配方有誤" % kind)
			units_by_kind[cost_key] = units.units
		var kind_units: Dictionary = units_by_kind[cost_key]
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
	var version: int = _as_int(values["version"], VERSION, EDGE_VERSION)
	if version == BAD_INT:
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
	var piece_cap: int = MAX_PIECES_EDGE if version == EDGE_VERSION else MAX_PIECES
	if raw_pieces.size() > piece_cap:
		return _bad("藍圖最多 %d 個建物" % piece_cap)
	# One slot per (layer, y, x): duplicate detection and the canonical
	# ground→objects→roofs, y, x order in one bounded pass (≤ 3×256 slots).
	var cells: int = width * height
	var slots: Array = []
	slots.resize(LAYERS.size() * cells)
	var edge_pieces: Dictionary = {}
	for entry: Variant in raw_pieces:
		var piece: Dictionary = _piece(entry, width, height, recipe_map, names_map, version)
		if not bool(piece.ok):
			return _bad(String(piece.reason))
		var out: Dictionary = piece.piece
		if is_edge_kind(out.kind):
			# Physically equivalent edges (same EdgeGrid id from either side) are one slot.
			var canon: Dictionary = _canon_edge(int(out.x), int(out.y), int(out.settings.side), width, height)
			if canon.is_empty():
				return _bad("牆段位置有誤")
			if edge_pieces.has(canon.id):
				return _bad("同一道牆段只能有一個建物 (%s)" % canon.id)
			edge_pieces[canon.id] = {"kind": String(out.kind), "x": canon.x, "y": canon.y, "settings": {"side": canon.side}}
			continue
		var layer: int = int(piece.layer)
		var px: int = int(out.x)
		var py: int = int(out.y)
		var index: int = layer * cells + py * width + px
		if slots[index] != null:
			return _bad("同一格同一層只能有一個建物 (%d,%d)" % [px, py])
		slots[index] = out
	var extra_cells:Dictionary={}
	for slot:Variant in slots:
		if slot==null or (slot.kind not in (DOUBLE_BENCHES+Industry.ORIENTABLE_FOOTPRINTS) and not is_square_piece(slot) and not is_wide_bench_piece(slot) and not is_mill_piece(slot)):continue
		var offsets:Array=[bench_offset(slot)] if slot.kind in DOUBLE_BENCHES else Industry.station_cells(slot.kind,slot.get("settings",{}).get("vertical",false)).slice(1)
		for offset:Vector2i in offsets:
			var end:=Vector2i(int(slot.x),int(slot.y))+offset
			if end.x>=width or end.y>=height:return _bad("家具的整個占地都需要在藍圖範圍內")
			var index:=_layer_index(slot.kind)*cells+end.y*width+end.x
			if slots[index]!=null or extra_cells.has(index):return _bad("多格家具不能和同層建物重疊")
			extra_cells[index]=true
	var pieces: Array = []
	for slot: Variant in slots:
		if slot != null:
			pieces.append(slot)
	if version == EDGE_VERSION:
		if edge_pieces.is_empty():
			return _bad("第二版藍圖必須包含牆段")
		var ordered: Array = edge_pieces.values()
		ordered.sort_custom(_edge_before)
		pieces.append_array(ordered)
	var blueprint: Dictionary = {"version": version, "name": String(clean_name.value), "width": width, "height": height, "pieces": pieces}
	return {"ok": true, "reason": "", "blueprint": blueprint}

# ------------------------------------------------------------ edge pieces

static func is_edge_kind(kind: Variant) -> bool:
	return _is_text(kind) and String(kind) in EDGE_KINDS

## Side 0..3 (EdgeGrid order N,E,S,W) of an edge piece's in-area tile, or -1.
static func edge_side(piece: Variant) -> int:
	if not (piece is Dictionary) or not is_edge_kind(piece.get("kind")):
		return -1
	var settings: Variant = piece.get("settings")
	if not (settings is Dictionary):
		return -1
	var side: int = _as_int(settings.get("side"), 0, EdgeGrid.SIDE_COUNT - 1)
	return -1 if side == BAD_INT else side

## Fresh copy of the plan price of an edge kind, {} for anything else.
static func edge_recipe(kind: Variant) -> Dictionary:
	if not is_edge_kind(kind):
		return {}
	return (EDGE_COSTS[String(kind)] as Dictionary).duplicate()

## Canonical placement of the edge on `side` of in-box tile (x,y): N/W of the owning cell if that
## cell is inside the w×h box, otherwise the adjacent in-box tile with the opposite side.
static func _canon_edge(x: int, y: int, side: int, w: int, h: int) -> Dictionary:
	var limits := Vector2i(w, h)
	var tile := Vector2i(x, y)
	if not EdgeGrid.in_bounds(tile, limits) or not EdgeGrid.is_side(side):
		return {}
	var id: String = EdgeGrid.key(tile, side, limits)
	var canon: Dictionary = EdgeGrid.canonical(tile, side, limits)
	if id == "" or canon.is_empty():
		return {}
	var owner_cell: Vector2i = canon.cell
	if EdgeGrid.in_bounds(owner_cell, limits):
		return {"id": id, "x": owner_cell.x, "y": owner_cell.y, "side": int(canon.side)}
	var inside: Vector2i = owner_cell + EdgeGrid.DIRS[canon.side]
	if not EdgeGrid.in_bounds(inside, limits):
		return {}
	return {"id": id, "x": inside.x, "y": inside.y, "side": EdgeGrid.opposite(int(canon.side))}

static func _edge_before(a: Dictionary, b: Dictionary) -> bool:
	if a.y != b.y:
		return a.y < b.y
	if a.x != b.x:
		return a.x < b.x
	return a.settings.side < b.settings.side

static func is_square_piece(piece:Dictionary) -> bool:
	return piece.kind in Industry.FIXED_SQUARE_STATIONS or (piece.kind in Industry.EXPANDABLE_STATIONS and piece.get("settings",{}).get("wide",false))

## C08: only a bench piece carrying settings.wide is the 2x1 workbench; settings-less bench pieces
## (legacy blueprints and captured 1x1 benches) stay one cell.
static func is_wide_bench_piece(piece:Dictionary) -> bool:
	return piece.get("kind")==Industry.WORKBENCH and piece.get("settings",{}).get("wide",false)==true

## C13: only a mill piece carrying settings.facing is the new 3x3 mill; a settings-less mill piece (legacy
## blueprints and captured kit mills) stays one cell and one mill_kit.
static func is_mill_piece(piece:Dictionary) -> bool:
	return piece.get("kind")==Industry.MILL and piece.get("settings",{}).has("facing")

static func bench_offset(piece:Dictionary) -> Vector2i:
	return Vector2i.DOWN if piece.get("settings",{}).get("vertical",false) else Vector2i.RIGHT

static func _piece(entry: Variant, width: int, height: int, recipe_map: Dictionary, names_map: Dictionary, version: int = VERSION) -> Dictionary:
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
	if is_edge_kind(kind):
		return _edge_piece(values, kind, width, height, version)
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
	if kind==Industry.LEAF_MAT and values.has("settings"):
		var mat:Variant=values.settings
		if not mat is Dictionary or mat.size()!=1 or not mat.get("leaf_mat_shade") is String or not Industry.MAT_SHADES.has(mat.leaf_mat_shade):
			return _bad("葉片地墊的色彩設定無效")
		if mat.leaf_mat_shade!="light":out.settings={"leaf_mat_shade":mat.leaf_mat_shade}
	elif kind==Industry.VINE_ARCH and values.has("settings"):
		if not values.settings is Dictionary:return _bad("藤蔓花門的設定無效")
		var arch_fields:=_fields(values.settings,["vertical","vine_color"])
		if not arch_fields.ok:return _bad("藤蔓花門的設定無效")
		var arch:Dictionary=arch_fields.values
		if not arch.get("vertical",false) is bool:return _bad("藤蔓花門的方向無效")
		var flower:Variant=arch.get("vine_color","pink")
		if not flower is String or not Industry.VINE_COLORS.has(flower):return _bad("藤蔓花門的花色無效")
		var settings:Dictionary={}
		if arch.get("vertical",false):settings.vertical=true
		if flower!="pink":settings.vine_color=flower
		if not settings.is_empty():out.settings=settings
	elif kind==Industry.WORKBENCH and values.has("settings"):
		if not values.settings is Dictionary:return _bad("工作台的占地設定無效")
		var bench_fields:=_fields(values.settings,["wide","vertical"])
		if not bench_fields.ok:return _bad("工作台的占地設定無效")
		var bench:Dictionary=bench_fields.values
		if typeof(bench.get("wide"))!=TYPE_BOOL or not bench.wide:return _bad("工作台的占地設定無效")
		if bench.has("vertical") and typeof(bench.vertical)!=TYPE_BOOL:return _bad("工作台的方向設定無效")
		out.settings={"wide":true}
		if bench.get("vertical",false):out.settings.vertical=true
	elif kind==Industry.MILL and values.has("settings"):
		if not values.settings is Dictionary:return _bad("磨坊的方向設定無效")
		var mill_fields:=_fields(values.settings,["facing"])
		if not mill_fields.ok:return _bad("磨坊的方向設定無效")
		var mill_facing:=_as_int(mill_fields.values.get("facing"),0,Industry.MILL_FACING_COUNT-1)
		if mill_facing==BAD_INT:return _bad("磨坊的方向只能是 0 到 3")
		out.settings={"facing":mill_facing}
	elif kind in (DOUBLE_BENCHES+Industry.ORIENTABLE_FOOTPRINTS) and values.has("settings"):
		var seat=values.settings
		if not seat is Dictionary or seat.size()!=1 or not seat.get("vertical") is bool:return _bad("雙格家具的方向設定無效")
		if kind==Industry.TOOL_BOARD and seat.vertical:return _bad("壁掛工具板需要橫跨兩段相連的木牆。")
		if kind==Industry.IMPERFECT_TEA_PAVILION and seat.vertical:return _bad("不完美的茶亭是 3×3 方形，不需要旋轉設定。")
		if seat.vertical:out.settings={"vertical":true}
	elif kind in Industry.EXPANDABLE_STATIONS and values.has("settings"):
		var footprint=values.settings
		if not footprint is Dictionary or footprint.size()!=1 or typeof(footprint.get("wide"))!=TYPE_BOOL or not footprint.wide:
			return _bad("加工設備的占地設定無效")
		out.settings={"wide":true}
	elif values.has("settings"):
		if kind != CONVEYOR:
			return _bad("只有輸送帶、雙格長椅與多格加工設備可以附帶設定")
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

## Strict edge piece: exactly {kind,x,y,settings:{side}}; no style, owner or open; version 2 only.
static func _edge_piece(values: Dictionary, kind: String, width: int, height: int, version: int) -> Dictionary:
	if version != EDGE_VERSION:
		return _bad("牆段需要第二版藍圖")
	if values.size() != 4 or not values.has("settings"):
		return _bad("牆段欄位不正確")
	var x: int = _as_int(values["x"], 0, width - 1)
	var y: int = _as_int(values["y"], 0, height - 1)
	if x == BAD_INT or y == BAD_INT:
		return _bad("藍圖片段座標超出範圍")
	var settings: Variant = values["settings"]
	if not (settings is Dictionary) or settings.size() != 1:
		return _bad("牆段設定不正確")
	var setting_fields: Dictionary = _fields(settings, ["side"])
	if not bool(setting_fields.ok):
		return _bad("牆段設定不正確")
	var side: int = _as_int(setting_fields.values.get("side"), 0, EdgeGrid.SIDE_COUNT - 1)
	if side == BAD_INT:
		return _bad("牆段方向必須是 0 到 3")
	return {"ok": true, "reason": "", "piece": {"kind": kind, "x": x, "y": y, "settings": {"side": side}}, "layer": -1}

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
