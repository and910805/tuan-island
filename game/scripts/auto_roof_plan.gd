extends RefCounted
## Pure transaction planner for automatic roofs over CURRENT-REGION snapshots.
## Used by World.act and the client construction quote; persistence stays in World.
##
## reconcile() compares a `before` and `after` snapshot (ground, objects, roofs
## and optional boundary edges) around the `touched` tiles and returns the roof delta
## that would keep auto roofs consistent with sealed rooms. It never writes to
## its inputs and never checks inventories; the server wrapper must validate the
## aggregate cost/refunds after the base action and apply everything atomically.
##
## Room semantics mirror house_rooms.gd / room_enclosure.gd: a room is a cardinal
## floor component (ground type "floor", excluding wall/window/door cells),
## capped at MAX_CELLS. `sealed` also requires at least one door.
## Auto roofs are CREATED for affected qualifying components; they are KEPT while the tile
## stays interior of a sealed component, and REMOVED (refunded to the roof's
## recorded payer) otherwise. Manual roofs (auto != true) are never touched.
##
## Settlement policy: the acting player
## voluntarily pays every added roof on closure; those roofs record that payer
## as owner and are refunded to that payer (even offline) when the room opens.
## This can roof floor owned by other players and must be shown explicitly in a
## future preview. No other player is ever charged.

const Enclosure = preload("res://scripts/room_enclosure.gd")
const Fixtures = preload("res://scripts/roof_fixtures.gd")
const MIN_AREA := Enclosure.MIN_AREA
const MAX_CELLS := Enclosure.MAX_CELLS
# A 16×16 edge blueprint can also touch 64 cells immediately outside its perimeter.
const MAX_TOUCHED := 320
const MAX_AFFECTED := 4000
const MAX_COORD := 1000000
const MAX_UNIT_COST := 1000000
const MAX_ACTOR_LEN := 64
const BOUNDARY := ["wall", "window", "door"]
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static func reconcile(before: Dictionary, after: Dictionary, touched: Array[Vector2i], actor: String, recipe: Dictionary) -> Dictionary:
	if not _valid_actor(actor):return _fail("無法確認施工者，屋頂沒有變更")
	var parsed := _recipe_units(recipe)
	if not parsed.ok:return _fail("屋頂材料設定有誤，屋頂沒有變更")
	var units: Dictionary = parsed.units
	var resources: Array[String] = parsed.resources
	if touched.size() > MAX_TOUCHED:return _fail("一次調整的範圍太大，屋頂沒有變更")
	for t in touched:
		if absi(t.x) > MAX_COORD or absi(t.y) > MAX_COORD:return _fail("施工位置超出範圍，屋頂沒有變更")
	var grounds := [_layer(before, "ground"), _layer(after, "ground")]
	var objects := [_layer(before, "objects"), _layer(after, "objects")]
	var snapshots := [before, after]
	var after_roofs := _layer(after, "roofs")
	# Closure: every floor component (in BOTH snapshots) reachable from touched
	# cells or their cardinal neighbours, re-expanded until each affected cell's
	# component is known in both snapshots. Splits and merges are captured.
	var maps := [{}, {}]
	var comps := [[], []]
	var queued := {}
	var queue: Array[Vector2i] = []
	var evaluate := {}
	for t in touched:
		evaluate[t] = true
		for c in [t, t + DIRS[0], t + DIRS[1], t + DIRS[2], t + DIRS[3]]:
			if not queued.has(c):
				queued[c] = true
				queue.append(c)
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for s in 2:
			if maps[s].has(c) or not _is_floor(grounds[s], objects[s], c):continue
			var comp := Enclosure.analyze(snapshots[s], c)
			if comp.truncated:return _fail("房間範圍超過 %d 格，請先確認牆面是否圍好；屋頂沒有變更" % MAX_CELLS)
			var idx: int = comps[s].size()
			comps[s].append(comp)
			for cell in comp.cells:
				maps[s][cell] = idx
				evaluate[cell] = true
				if not queued.has(cell):
					queued[cell] = true
					queue.append(cell)
			if evaluate.size() > MAX_AFFECTED:return _fail("影響範圍太大，屋頂沒有變更")
	# Which after-components should receive new roofs.
	var create := []
	for i in comps[1].size():
		var d: Dictionary = comps[1][i]
		create.append(d.sealed)
	var cells: Array[Vector2i] = []
	for c in evaluate:cells.append(c)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var add := {}
	var remove: Array[String] = []
	var removed_by_owner := {}
	for c in cells:
		var k := _key(c)
		var interior := false
		var may_create := false
		if maps[1].has(c):
			var idx: int = maps[1][c]
			interior = comps[1][idx].sealed
			may_create = create[idx]
		if after_roofs.has(k):
			# After layer is authoritative: manual/foreign/malformed entries are left alone.
			var roof = after_roofs[k]
			if not _is_auto_roof(roof) or interior:continue
			var payer = roof.get("owner")
			if typeof(payer) != TYPE_STRING or not _valid_actor(payer):return _fail("自動屋頂資料有誤，屋頂沒有變更")
			if objects[1].get(k,{}).get("type")==Fixtures.HANGING_POT:return _fail(Fixtures.REMOVE_MESSAGE)
			remove.append(k)
			removed_by_owner[payer] = int(removed_by_owner.get(payer, 0)) + 1
		elif may_create:
			add[k] = {"type": "roof", "owner": actor, "items": {}, "auto": true}
	var cost := {}
	if not add.is_empty():
		for r in resources:
			var amount: int = int(units[r]) * add.size()
			if amount > 0:cost[r] = amount
	var refunds := {}
	var owners: Array = removed_by_owner.keys()
	owners.sort()
	for o in owners:
		var back := {}
		for r in resources:
			var amount: int = int(units[r]) * int(removed_by_owner[o])
			if amount > 0:back[r] = amount
		if not back.is_empty():refunds[o] = back
	return {"ok": true, "message": _message(add.size(), remove.size()), "add": add, "remove": remove, "cost": cost, "refunds": refunds}

static func _is_auto_roof(roof) -> bool:
	if not (roof is Dictionary):return false
	var flag = roof.get("auto")
	var kind = roof.get("type")
	return typeof(flag) == TYPE_BOOL and flag and typeof(kind) == TYPE_STRING and kind == "roof"

static func _recipe_units(recipe: Dictionary) -> Dictionary:
	var bad := {"ok": false}
	var units := {}
	var resources: Array[String] = []
	for raw in recipe.keys():
		if typeof(raw) != TYPE_STRING and typeof(raw) != TYPE_STRING_NAME:return bad
		var name := String(raw)
		var value = recipe[raw]
		if name == "name":
			if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:return bad
			continue
		if name == "" or name.strip_edges() != name or units.has(name):return bad
		var n := 0
		if typeof(value) == TYPE_INT:
			n = value
		elif typeof(value) == TYPE_FLOAT:
			var f: float = value
			if is_nan(f) or is_inf(f) or f != floorf(f) or absf(f) > MAX_UNIT_COST:return bad
			n = int(f)
		else:
			return bad
		if n < 0 or n > MAX_UNIT_COST:return bad
		units[name] = n
		resources.append(name)
	if resources.is_empty():return bad
	resources.sort()
	return {"ok": true, "units": units, "resources": resources}

static func _valid_actor(actor: String) -> bool:
	if actor == "" or actor.length() > MAX_ACTOR_LEN or actor.strip_edges() != actor:return false
	for i in actor.length():
		var ch := actor.unicode_at(i)
		if ch < 32 or ch == 127:return false
	return true

static func _message(added: int, removed: int) -> String:
	if added > 0 and removed > 0:return "自動屋頂調整：新增 %d 格、拆除 %d 格，拆除的材料退回原出資者" % [added, removed]
	if added > 0:return "房間圍好了，自動蓋上 %d 格屋頂" % added
	if removed > 0:return "房間打開了，拆除 %d 格自動屋頂，材料退回原出資者" % removed
	return "屋頂不需要調整"

static func _fail(message: String) -> Dictionary:
	var remove: Array[String] = []
	return {"ok": false, "message": message, "add": {}, "remove": remove, "cost": {}, "refunds": {}}

static func _is_floor(ground: Dictionary, objects: Dictionary, p: Vector2i) -> bool:
	var g = ground.get(_key(p))
	if not (g is Dictionary):return false
	if not Enclosure.is_floor_kind(g.get("type")):return false
	return _type(objects, p) not in BOUNDARY

static func _type(objects: Dictionary, p: Vector2i) -> String:
	var o = objects.get(_key(p))
	if not (o is Dictionary):return ""
	var t = o.get("type")
	return t if typeof(t) == TYPE_STRING else ""

static func _layer(snapshot: Dictionary, field: String) -> Dictionary:
	var layer = snapshot.get(field, {})
	return layer if layer is Dictionary else {}

static func _key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]
