extends RefCounted
## T036 explicit material sourcing: backpack plus ONE explicitly chosen,
## cardinal-adjacent chest for bench craft, stove queue and sawmill/kiln
## manual queue (game/docs/material-source-contract.json).
##
## Shared by World (prepare/perform, called from World._apply) and the client
## UI (candidates/digest/encode). Never preloads World: mutation helpers take
## the World instance. Holds no state between calls.
##
## Wire: plain recipe ID = legacy backpack-only action (never reaches here).
## Sourced extra = recipe|box_cell|box_id32|digest16 (<= WIRE_MAX ASCII bytes).

const MATERIAL_SUPPLY := preload("res://scripts/material_supply.gd")
const CONSTRUCTION_HISTORY := preload("res://scripts/construction_history.gd")

const PREPARE_ACTION := "prepare_material_box"
const ACTIONS := ["craft", "cook", "queue_cook", "start_processing", "queue_processing"]
const CANONICAL := {"craft":"craft", "cook":"queue_cook", "queue_cook":"queue_cook",
	"start_processing":"queue_processing", "queue_processing":"queue_processing"}
const STATION_FOR := {"craft":["bench"], "queue_cook":["stove"], "queue_processing":["sawmill", "charcoal_kiln", "mill", "seed_maker", "loom", "glass_furnace"]}
const STATIONS := ["bench", "stove", "sawmill", "charcoal_kiln", "mill", "seed_maker", "loom", "glass_furnace"]
## Processing stations are owner-only; bench and stove are shared by members.
const OWNER_ONLY := ["sawmill", "charcoal_kiln", "mill", "seed_maker", "loom", "glass_furnace"]
const BOXES := ["chest", "private_chest"]
const ID_LENGTH := 32
const DIGEST_LENGTH := 16
const DIGEST_VERSION := 1
const WIRE_MAX := 96
const RECIPE_MAX := 64
## Deterministic y-then-x order of the four cardinal neighbours.
const NEIGHBOURS := [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]

const MSG_WIRE := "材料來源資料無效，請重新選擇"
const MSG_STATION := "請靠近可使用的工作台、石灶或自己的加工設備"
const MSG_PROCESSOR := "只能使用自己的加工設備"
const MSG_ADJACENT := "只能選擇與設備上下左右相鄰的箱子"
const MSG_NO_BOX := "這裡沒有箱子"
const MSG_PRIVATE := "這是另一位島民的私人箱"
const MSG_CORRUPT := "箱子資料有誤，這次沒有變更"
const MSG_STALE := "箱子或材料分配已變動，請確認新的扣料方式"
const MSG_RECIPE := "找不到這份配方"
const MSG_ID := "無法建立箱子編號，請稍後再試"


# ------------------------------------------------------------- shared (UI)

## Eligible adjacent boxes for `actor` at `station_cell` in `objects` (one
## region layer). Shared chests for everyone, private chests only for their
## owner. Empty when the station itself is not usable by `actor`.
## Returns [{cell, type, id}] in y/x order; id "" when not yet prepared.
static func candidates(objects: Dictionary, actor: String, station_cell: Vector2i) -> Array:
	var out: Array = []
	if not _station_usable(objects.get(_key(station_cell)), actor):return out
	for offset: Vector2i in NEIGHBOURS:
		var k := _key(station_cell + offset)
		var box: Variant = objects.get(k)
		if not _box_usable(box, actor):continue
		var id: Variant = (box as Dictionary).get("box_id")
		out.append({"cell":k, "type":str(box.type), "id":str(id) if _is_lower_hex(id, ID_LENGTH) else ""})
	return out


## 16-hex quote digest over the canonical action, station, full recipe, chest
## and the exact positive split. cook/start_processing normalise to queue form.
static func digest(action: String, station_kind: String, station_key: String, recipe_id: String,
		recipe: Dictionary, chest_key: String, chest_id: String, allocation: Dictionary) -> String:
	var payload := {
		"v":DIGEST_VERSION,
		"action":str(CANONICAL.get(action, action)),
		"station":{"type":station_kind, "cell":station_key},
		"recipe_id":recipe_id,
		"recipe":recipe,
		"chest":{"cell":chest_key, "id":chest_id},
		"from_backpack":_positive(allocation.get("from_backpack", {})),
		"from_chest":_positive(allocation.get("from_chest", {})),
	}
	return CONSTRUCTION_HISTORY.canonical(payload).sha256_text().left(DIGEST_LENGTH)


static func encode(recipe_id: String, chest_key: String, chest_id: String, quote_digest: String) -> String:
	return "%s|%s|%s|%s" % [recipe_id, chest_key, chest_id, quote_digest]


# ------------------------------------------------------- World integration

## prepare_material_box: p = station cell, box_key = chest cell. Runs inside
## World._apply after its region/distance gates. Validates station, ownership,
## adjacency and box access BEFORE looking at or assigning any identity. A
## missing box_id is generated lazily here (only on this explicit success).
static func prepare(world, token: String, p: Vector2i, box_key: String) -> Dictionary:
	var objects: Dictionary = world.state.objects
	var station: Variant = objects.get(_key(p))
	var access := _access(objects, token, p, station, box_key)
	if not access.ok:return access
	var box: Dictionary = access.box
	var existing: Variant = box.get("box_id")
	var id := ""
	if box.has("box_id"):
		if not _is_lower_hex(existing, ID_LENGTH):return _fail(MSG_CORRUPT)
		id = str(existing)
	else:
		id = _new_box_id(world)
		if id == "":return _fail(MSG_ID)
		box.box_id = id
	return {"ok":true, "message":"已選擇相鄰的箱子作為材料來源", "source_cell":box_key, "source_id":id}


## Sourced craft/cook/queue_cook/start_processing/queue_processing. Called by
## World._apply (after its distance gate) only when `extra` carries a '|'.
## Stages the chest share into the live backpack, runs the canonical action
## with the plain recipe ID (all original checks), verifies the exact debit
## and only then commits the chest. Any failure restores the backpack; act()
## additionally rolls back the whole state on failure or save failure.
static func perform(world, token: String, action: String, p: Vector2i, extra: String) -> Dictionary:
	if not CANONICAL.has(action):return _fail(MSG_WIRE)
	var wire := parse_wire(extra)
	if not wire.ok:return wire
	var canonical: String = CANONICAL[action]
	var objects: Dictionary = world.state.objects
	var station_key := _key(p)
	var station: Variant = objects.get(station_key)
	if not station is Dictionary or str(station.get("type", "")) not in STATION_FOR[canonical]:
		return _fail(MSG_STATION)
	var box_key: String = wire.box_cell
	var access := _access(objects, token, p, station, box_key)
	if not access.ok:return access
	var box: Dictionary = access.box
	# Identity is examined only after permission: never reveals foreign IDs.
	if not _is_lower_hex(box.get("box_id"), ID_LENGTH) or str(box.box_id) != str(wire.box_id):return {"ok":false, "requote":true, "message":MSG_STALE}
	var station_kind := str(station.type)
	var recipe := _recipe(world, canonical, station_kind, wire.recipe)
	if recipe.is_empty():return _fail(MSG_RECIPE)
	# Q05: explain the public-kitchen gate before any material quote/shortage.
	if canonical == "craft" and wire.recipe in world.KITCHEN_GATED and not world.kitchen_opened():
		return _fail(world.MILL_LOCKED_MSG)
	var items: Variant = box.get("items")
	if not items is Dictionary:return _fail(MSG_CORRUPT)
	var inv: Dictionary = world.state.players[token].inventory
	var plan: Dictionary = MATERIAL_SUPPLY.plan(recipe.get("ingredients"), inv, items)
	if not plan.ok:
		if plan.has("missing"):
			var short: Dictionary = plan.missing
			return {"ok":false, "message":"材料不足，還缺 " + _describe(world, short), "missing":short.duplicate()}
		return _fail(MSG_CORRUPT)
	var expected := digest(canonical, station_kind, station_key, wire.recipe, recipe, box_key, wire.box_id, plan)
	if expected != wire.digest:
		return {"ok":false, "requote":true, "message":MSG_STALE,
			"from_backpack":(plan.from_backpack as Dictionary).duplicate(),
			"from_chest":(plan.from_chest as Dictionary).duplicate()}
	# Stage: live backpack temporarily holds only the chest top-ups.
	var saved_inv: Dictionary = inv.duplicate(true)
	var saved_items: Dictionary = (items as Dictionary).duplicate(true)
	_replace(inv, plan.supplied_inventory)
	var result: Dictionary = world._apply(token, canonical, p, wire.recipe)
	var after: Dictionary = plan.backpack_after
	var exact: bool = result.get("ok") == true
	if exact:
		for item: Variant in (recipe.ingredients as Dictionary):
			if int(inv.get(item, 0)) != int(after.get(item, 0)):
				exact = false
				break
	if not exact:
		_replace(inv, saved_inv)
		_replace(items, saved_items)
		if result.get("ok") == true:return _fail(MSG_CORRUPT)
		return result
	_replace(items, plan.chest_after)
	var from_backpack: Dictionary = (plan.from_backpack as Dictionary).duplicate()
	var from_chest: Dictionary = (plan.from_chest as Dictionary).duplicate()
	result.source_cell = box_key
	result.source_id = wire.box_id
	result.from_backpack = from_backpack
	result.from_chest = from_chest
	result.debit = {"from_backpack":from_backpack.duplicate(), "from_chest":from_chest.duplicate()}
	if not from_chest.is_empty():
		result.message = str(result.get("message", "")) + "；箱子 " + _describe(world, from_chest, "−")
	return result


## Strict sourced-wire parser: {ok, recipe, box_cell, box_id, digest}.
static func parse_wire(extra: String) -> Dictionary:
	if extra.length() > WIRE_MAX or not _ascii(extra):return _fail(MSG_WIRE)
	var parts := extra.split("|")
	if parts.size() != 4:return _fail(MSG_WIRE)
	var recipe := parts[0]
	if recipe.is_empty() or recipe.length() > RECIPE_MAX:return _fail(MSG_WIRE)
	if not CONSTRUCTION_HISTORY.parse_tile(parts[1]).ok:return _fail(MSG_WIRE)
	if not _is_lower_hex(parts[2], ID_LENGTH) or not _is_lower_hex(parts[3], DIGEST_LENGTH):return _fail(MSG_WIRE)
	return {"ok":true, "recipe":recipe, "box_cell":parts[1], "box_id":parts[2], "digest":parts[3]}


# ---------------------------------------------------------------- internals

static func _fail(message: String) -> Dictionary:
	return {"ok":false, "message":message}


static func _key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


static func _ascii(text: String) -> bool:
	for i in text.length():
		var ch := text.unicode_at(i)
		if ch < 32 or ch > 126:return false
	return true


static func _is_lower_hex(value: Variant, length: int) -> bool:
	if not value is String:return false
	var text: String = value
	if text.length() != length:return false
	for i in length:
		var ch := text.unicode_at(i)
		if not ((ch >= 48 and ch <= 57) or (ch >= 97 and ch <= 102)):return false
	return true


static func _station_usable(station: Variant, actor: String) -> bool:
	if not station is Dictionary:return false
	var kind := str(station.get("type", ""))
	if kind not in STATIONS:return false
	return kind not in OWNER_ONLY or station.get("owner") == actor


static func _box_usable(box: Variant, actor: String) -> bool:
	if not box is Dictionary:return false
	var kind := str(box.get("type", ""))
	if kind not in BOXES:return false
	return kind == "chest" or box.get("owner") == actor


## Station / owner / adjacency / box access checks shared by prepare and
## perform. Never inspects box_id. {ok, box} or a failure.
static func _access(objects: Dictionary, token: String, p: Vector2i, station: Variant, box_key: String) -> Dictionary:
	if not station is Dictionary or str(station.get("type", "")) not in STATIONS:return _fail(MSG_STATION)
	if str(station.type) in OWNER_ONLY and station.get("owner") != token:return _fail(MSG_PROCESSOR)
	var parsed: Dictionary = CONSTRUCTION_HISTORY.parse_tile(box_key)
	if not parsed.ok:return _fail(MSG_WIRE)
	var offset: Vector2i = (parsed.cell as Vector2i) - p
	if not NEIGHBOURS.has(offset):return _fail(MSG_ADJACENT)
	var box: Variant = objects.get(box_key)
	if not box is Dictionary or str(box.get("type", "")) not in BOXES:return _fail(MSG_NO_BOX)
	if box.type == "private_chest" and box.get("owner") != token:return _fail(MSG_PRIVATE)
	return {"ok":true, "box":box}


## Recipe definition from World's own catalogs, filtered by station.
static func _recipe(world, canonical: String, station_kind: String, recipe_id: String) -> Dictionary:
	var catalog: Dictionary
	match canonical:
		"craft":catalog = world.CRAFT
		"queue_cook":catalog = world.RECIPES
		"queue_processing":catalog = world.processing_recipes(station_kind)
		_:return {}
	var recipe: Variant = catalog.get(recipe_id)
	if not recipe is Dictionary or not (recipe as Dictionary).get("ingredients") is Dictionary:return {}
	return recipe


## Fresh lowercase 32-hex box id unique across every live regional layer
## (state.objects plus each state.regions[*].objects covers any orientation).
static func _new_box_id(world) -> String:
	var taken := {}
	var layers: Array = [world.state.get("objects", {})]
	var regions: Variant = world.state.get("regions", {})
	if regions is Dictionary:
		for region: Variant in (regions as Dictionary).values():
			if region is Dictionary:layers.append((region as Dictionary).get("objects", {}))
	for layer: Variant in layers:
		if not layer is Dictionary:continue
		for obj: Variant in (layer as Dictionary).values():
			if obj is Dictionary and (obj as Dictionary).get("box_id") is String:taken[obj.box_id] = true
	var crypto := Crypto.new()
	for attempt in 8:
		var id := crypto.generate_random_bytes(16).hex_encode()
		if _is_lower_hex(id, ID_LENGTH) and not taken.has(id):return id
	return ""


## Replaces contents in place so every live reference stays valid.
static func _replace(target: Dictionary, contents: Dictionary) -> void:
	var copy := contents.duplicate(true)
	target.clear()
	target.merge(copy)


static func _positive(counts: Variant) -> Dictionary:
	var out := {}
	if not counts is Dictionary:return out
	for item: Variant in counts:
		var amount: Variant = counts[item]
		if (amount is int or amount is float) and is_finite(float(amount)) and float(amount) > 0.0:
			out[str(item)] = int(amount)
	return out


static func _describe(world, counts: Dictionary, mark: String = "") -> String:
	var names: Array = counts.keys()
	names.sort()
	var parts: PackedStringArray = []
	for item: Variant in names:
		parts.append("%s %s%d" % [str(world.NAMES.get(item, item)), mark, int(counts[item])])
	return "、".join(parts)
