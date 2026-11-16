extends RefCounted
## Pure construction quote (base build/remove + automatic roof delta) over ONE
## current-region snapshot. Shared by the client preview and the server so the
## numbers a player sees match what World.act charges/refunds.
##
## quote(snapshot, actor, action, at, extra) ALWAYS returns:
##   ok:           bool        false = this action cannot be quoted / would be rejected
##   message:      String      player-facing; never contains owner ids or tokens
##   plan:         Dictionary  auto_roof_plan.reconcile() shaped {ok,message,add,remove,cost,refunds}
##   base_cost:    Dictionary  normal World.BUILD materials for the base build (x tiles)
##   total_cost:   Dictionary  base_cost + plan.cost (what the ACTOR pays; refunds NOT netted)
##   base_refund:  Dictionary  normal World.BUILD materials returned by the base remove
##   refunds:      Dictionary  owner => materials; plan.refunds merged with base_refund to actor
##   affected:     bool        plan.add or plan.remove non-empty
##
## Owners/actor are compared as opaque strings, so the client can pass its public
## hashed id against a public_state snapshot and the server the raw token against
## the real region snapshot. Nothing here reads inventories: affordability, reach,
## unlocks, natural resources, water/protected tiles and player positions remain
## server-authoritative. Players omitted from the snapshot are never consulted.
##
## Supported actions (anything else -> safe failure):
##   build       extra = floor | path | wall | window | door | roof
##   build_area  extra = "floor|path|roof" + "|endx|endy", 1..25 tiles, |end| <= 1000
##   remove      target = manual roof, else object, else ground (auto roofs skipped,
##               left in place for reconcile to keep or refund)
##
## Auto roofs are reconciled ONLY when the base delta changes room topology:
## a floor tile appears/disappears in ground, or a wall/window/door appears/disappears
## in objects. Roof builds, manual roof removals, paths and furniture never
## (re)charge or rebuild roofs ("只改家具、不改結構時不應重新收費或重建屋頂";
## manual roofs are never converted).
##
## Read-only: inputs are never mutated. Only the touched layer is shallow-copied
## (values shared, never written), so a per-frame preview does not deep-copy the world.

const Plan = preload("res://scripts/auto_roof_plan.gd")
const WORLD_PATH := "res://scripts/world.gd"
const BUILD_KINDS := ["floor", "path", "wall", "window", "door", "roof"]
const AREA_KINDS := ["floor", "path", "roof"]
const GROUND_KINDS := ["floor", "path"]
const BOUNDARY := ["wall", "window", "door"]
const MAX_AREA := 25
const MAX_AREA_END := 1000
const MAX_COORD := Plan.MAX_COORD
const LAYERS := ["ground", "objects", "roofs"]

const MSG_ACTOR := "無法確認施工者，請重新整理後再試"
const MSG_ACTION := "這個動作沒有施工預覽"
const MSG_DATA := "建物資料有誤，請稍後再試"
const MSG_AREA := "請重新選擇施工範圍"
const MSG_AREA_SIZE := "一次最多施工 25 格"
const MSG_RANGE := "施工位置超出範圍"

static func quote(snapshot: Dictionary, actor: String, action: String, at: Vector2i, extra: String = "") -> Dictionary:
	if not Plan._valid_actor(actor):return _fail(MSG_ACTOR)
	if absi(at.x) > MAX_COORD or absi(at.y) > MAX_COORD:return _fail(MSG_RANGE)
	var layers := {}
	for field in LAYERS:
		var layer = snapshot.get(field, {})
		if not (layer is Dictionary):return _fail(MSG_DATA)
		layers[field] = layer
	var build := _build_table()
	if build.is_empty():return _fail(MSG_DATA)
	match action:
		"build":
			if extra not in BUILD_KINDS:return _fail(MSG_ACTION)
			return _quote_build(snapshot, layers, build, actor, extra, [at])
		"build_area":
			var area := _parse_area(at, extra)
			if not area.ok:return _fail(area.message)
			return _quote_build(snapshot, layers, build, actor, area.kind, area.tiles)
		"remove":
			return _quote_remove(snapshot, layers, build, actor, at)
	return _fail(MSG_ACTION)

# --- build ------------------------------------------------------------------

static func _quote_build(snapshot: Dictionary, layers: Dictionary, build: Dictionary, actor: String, kind: String, tiles: Array) -> Dictionary:
	var ground: Dictionary = layers.ground
	var objects: Dictionary = layers.objects
	var roofs: Dictionary = layers.roofs
	var crops = _optional(snapshot, "crops")
	var forest = _optional(snapshot, "forest")
	if crops == null or forest == null:return _fail(MSG_DATA)
	var area := tiles.size() > 1
	for t in tiles:
		var k := _key(t)
		for layer in [ground, objects, roofs]:
			if layer.has(k) and not _entry_ok(layer[k]):return _fail(MSG_DATA)
		if kind == "roof":
			var g = ground.get(k)
			if roofs.has(k):return _fail("整片屋頂都需要自己的木地板，且不能重疊屋頂" if area else "這裡已經有屋頂")
			if not (g is Dictionary) or g.type != "floor":return _fail("整片屋頂都需要自己的木地板，且不能重疊屋頂" if area else "先鋪木地板，再蓋上屋頂")
			if g.owner != actor:return _fail("整片屋頂都需要自己的木地板，且不能重疊屋頂" if area else "只能在自己的地板上蓋屋頂")
			continue
		var occupied: bool = crops.has(k) or forest.has(k) or objects.has(k)
		if area and ground.has(k):occupied = true
		if occupied:return _fail("範圍裡有東西，這次沒有放置或扣料" if area else "這格有東西，請選空地")
		if kind in GROUND_KINDS and ground.has(k):return _fail("這裡已經鋪好了")
	if not build.has(kind) or not (build[kind] is Dictionary):return _fail(MSG_DATA)
	var base_cost := _scaled(build[kind], tiles.size())
	# Structural delta: only floor (ground) and wall/window/door (objects) change rooms.
	if kind == "floor" or kind in BOUNDARY:
		var field := "ground" if kind == "floor" else "objects"
		var copy: Dictionary = (layers[field] as Dictionary).duplicate(false)
		for t in tiles:
			var obj := {"type": kind, "owner": actor, "items": {}}
			if kind == "door":obj.open = false
			copy[_key(t)] = obj
		var after := {"ground": ground, "objects": objects, "roofs": roofs}
		after[field] = copy
		return _finish(layers, after, tiles, actor, build, base_cost, {})
	return _finish_static(base_cost, {}, actor, "可以施工，屋頂不需要調整")

static func _parse_area(at: Vector2i, extra: String) -> Dictionary:
	var parts := extra.split("|")
	if parts.size() != 3 or parts[0] not in AREA_KINDS or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return {"ok": false, "message": MSG_AREA}
	var end := Vector2i(int(parts[1]), int(parts[2]))
	if absi(end.x) > MAX_AREA_END or absi(end.y) > MAX_AREA_END:return {"ok": false, "message": MSG_AREA_SIZE}
	var a := Vector2i(mini(at.x, end.x), mini(at.y, end.y))
	var b := Vector2i(maxi(at.x, end.x), maxi(at.y, end.y))
	var w := b.x - a.x + 1
	var h := b.y - a.y + 1
	if w < 1 or h < 1 or w > MAX_AREA or h > MAX_AREA or w * h > MAX_AREA:return {"ok": false, "message": MSG_AREA_SIZE}
	var tiles: Array[Vector2i] = []
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):tiles.append(Vector2i(x, y))
	return {"ok": true, "kind": parts[0], "tiles": tiles}

# --- remove -----------------------------------------------------------------

static func _quote_remove(snapshot: Dictionary, layers: Dictionary, build: Dictionary, actor: String, at: Vector2i) -> Dictionary:
	var k := _key(at)
	var crops = _optional(snapshot, "crops")
	var forest = _optional(snapshot, "forest")
	if crops == null or forest == null:return _fail(MSG_DATA)
	if forest.has(k) or crops.has(k):return _fail("這格不是建物，沒有建材或屋頂預覽")
	var ground: Dictionary = layers.ground
	var objects: Dictionary = layers.objects
	var roofs: Dictionary = layers.roofs
	var field := ""
	if roofs.has(k):
		if not _entry_ok(roofs[k]):return _fail(MSG_DATA)
		if not Plan._is_auto_roof(roofs[k]):field = "roofs"
	if field == "" and objects.has(k):field = "objects"
	if field == "" and ground.has(k):field = "ground"
	if field == "":return _fail("這裡沒有可拆除的建物")
	var obj = (layers[field] as Dictionary)[k]
	if not _entry_ok(obj):return _fail(MSG_DATA)
	if obj.owner != actor:return _fail("只能拆除自己放置的物件")
	if obj.has("job"):return _fail("設備仍在工作，先領取或取消再拆除")
	if obj.type == "conveyor" and typeof(obj.get("enabled")) == TYPE_BOOL and obj.enabled:return _fail("請停用並清空輸送帶")
	var items = obj.get("items", {})
	if not (items is Dictionary):return _fail(MSG_DATA)
	for amount in items.values():
		if (typeof(amount) == TYPE_INT or typeof(amount) == TYPE_FLOAT) and amount > 0:return _fail("箱子還有物品，先取出再拆除")
	if not build.has(obj.type):return _fail("這裡沒有可拆除的建物")
	var base_refund := _scaled(build[obj.type], 1)
	var structural: bool = (field == "ground" and obj.type == "floor") or (field == "objects" and obj.type in BOUNDARY)
	if not structural:return _finish_static({}, base_refund, actor, "可以拆除，屋頂不需要調整")
	var copy: Dictionary = (layers[field] as Dictionary).duplicate(false)
	copy.erase(k)
	# Any auto roof above stays in `after`; reconcile decides keep vs refund.
	var after := {"ground": ground, "objects": objects, "roofs": roofs}
	after[field] = copy
	return _finish(layers, after, [at], actor, build, {}, base_refund)

# --- assembly ---------------------------------------------------------------

static func _finish(before: Dictionary, after: Dictionary, tiles: Array, actor: String, build: Dictionary, base_cost: Dictionary, base_refund: Dictionary) -> Dictionary:
	if not build.has("roof") or not (build.roof is Dictionary):return _fail(MSG_DATA)
	var touched: Array[Vector2i] = []
	for t in tiles:touched.append(t)
	var plan := Plan.reconcile(before, after, touched, actor, (build.roof as Dictionary).duplicate(true))
	if not plan.ok:return _fail(plan.message)
	var affected: bool = not plan.add.is_empty() or not plan.remove.is_empty()
	var refunds := {}
	for owner in plan.refunds:refunds[owner] = (plan.refunds[owner] as Dictionary).duplicate(true)
	if not base_refund.is_empty():refunds[actor] = _sum(refunds.get(actor, {}), base_refund)
	var message: String = plan.message if affected else ("可以拆除，屋頂不需要調整" if base_cost.is_empty() else "可以施工，屋頂不需要調整")
	return {"ok": true, "message": message, "plan": plan, "base_cost": base_cost, "total_cost": _sum(base_cost, plan.cost), "base_refund": base_refund, "refunds": refunds, "affected": affected}

static func _finish_static(base_cost: Dictionary, base_refund: Dictionary, actor: String, message: String) -> Dictionary:
	var refunds := {}
	if not base_refund.is_empty():refunds[actor] = base_refund.duplicate()
	return {"ok": true, "message": message, "plan": _empty_plan(true, "屋頂不需要調整"), "base_cost": base_cost, "total_cost": base_cost.duplicate(), "base_refund": base_refund, "refunds": refunds, "affected": false}

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "plan": _empty_plan(false, message), "base_cost": {}, "total_cost": {}, "base_refund": {}, "refunds": {}, "affected": false}

static func _empty_plan(ok: bool, message: String) -> Dictionary:
	var remove: Array[String] = []
	return {"ok": ok, "message": message, "add": {}, "remove": remove, "cost": {}, "refunds": {}}

# --- helpers ----------------------------------------------------------------

static func _build_table() -> Dictionary:
	# Loaded lazily (not preloaded) so world.gd may preload this script without a cycle.
	var script = load(WORLD_PATH)
	if script == null:return {}
	var table = script.get_script_constant_map().get("BUILD")
	return table if table is Dictionary else {}

## recipe materials * n as fresh {item: int}, skipping "name" and zero amounts.
static func _scaled(recipe, n: int) -> Dictionary:
	var out := {}
	if not (recipe is Dictionary):return out
	for item in recipe:
		if String(item) == "name":continue
		var amount := int(recipe[item]) * n
		if amount != 0:out[String(item)] = amount
	return out

static func _sum(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for item in a:out[item] = int(a[item])
	for item in b:out[item] = int(out.get(item, 0)) + int(b[item])
	return out

## Optional layer: missing -> {}, present but not a Dictionary -> null (malformed).
static func _optional(snapshot: Dictionary, field: String):
	var layer = snapshot.get(field, {})
	return layer if layer is Dictionary else null

static func _entry_ok(entry) -> bool:
	return entry is Dictionary and typeof(entry.get("type")) == TYPE_STRING and typeof(entry.get("owner")) == TYPE_STRING

static func _key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]
