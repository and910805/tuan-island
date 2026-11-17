extends RefCounted
## Structural house-room check over one CURRENT-REGION snapshot.
## Pure and read-only: never mutates the snapshot, never touches World.
## This is a structural check only. It does not prove an exterior route,
## house safety, rewards, or auto roofing.

const SEARCH_RADIUS := 8
const Enclosure = preload("res://scripts/room_enclosure.gd")
const MIN_AREA := Enclosure.MIN_AREA
const Industry=preload("res://scripts/industry.gd")
# Matches World.blocked object collisions; checked against every BUILD entry in tests.
const SOLID_OBJECTS := ["ore_display", "wall", "window", "chest", "private_chest", "supply_box", "bench", "bed", "inn_quilt_bed", "inn_stone_footbath", "table", "stove","long_bench","master_bench","spring_stone_bench","small_smelter","sofa","planter","guest_wardrobe","inn_lattice_wardrobe","inn_fabric_screen","wood_mailbox","sketch_easel","rope_rack","towel_rack","inn_tea_table","inn_luggage_rack","flower_pot","greenhouse_rack","master_flower_bed","fish_display","author_sign","author_shelf","expedition_tent","sprinkler","medium_sprinkler","large_sprinkler","water_tank","water_tower","water_pump","waterworks","mine_drill","sawmill","charcoal_kiln","forester","mill","seed_maker","loom","glass_furnace","jam_pot","clay_kiln","dye_table","assembly_table","animal_collector"]
const MAX_CELLS := Enclosure.MAX_CELLS
const BOUNDARY := ["wall", "window", "door"]
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static func inspect(snapshot: Dictionary, at: Vector2i) -> Dictionary:
	var ground := _layer(snapshot, "ground")
	var objects := _layer(snapshot, "objects")
	var roofs := _layer(snapshot, "roofs")
	var start_found := false
	var start := at
	if _is_floor(ground, objects, at):
		start_found = true
	else:
		var best_d2 := SEARCH_RADIUS * SEARCH_RADIUS + 1
		# Row-major scan with strict < gives a (distance, y, x) tie-break.
		for dy in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			for dx in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
				var d2 := dx * dx + dy * dy
				if d2 >= best_d2:continue
				var p := at + Vector2i(dx, dy)
				if _is_floor(ground, objects, p):
					best_d2 = d2
					start = p
					start_found = true
	var result := _empty()
	if not start_found:
		result.missing.append("附近 %d 格內沒有室內木地板，請先鋪木地板" % SEARCH_RADIUS)
		return result
	# The live inspector and automatic-roof planner share one topology definition.
	var enclosure := Enclosure.analyze(snapshot,start)
	var cells: Array[Vector2i] = enclosure.cells
	var inside := {}
	for c in cells:inside[c]=true
	var truncated:bool = enclosure.truncated
	var boundary := {}
	for c in enclosure.boundary:boundary[c]=true
	var doors := {}
	for c in enclosure.doors:doors[c]=true
	var gaps:int = enclosure.gap_count
	var roof_missing := 0
	var beds: Array[Vector2i] = []
	var owners := {}
	for c in cells:
		var tile := _key(c)
		_add_owner(owners, ground.get(tile))
		var roof = roofs.get(tile)
		if roof is Dictionary:
			_add_owner(owners, roof)
		else:
			roof_missing += 1
		var obj = objects.get(tile)
		if obj is Dictionary:
			_add_owner(owners, obj)
			if obj.get("type","")=="bed" or (obj.get("type","")==Industry.INN_BED and Industry.square_part(obj)==0):beds.append(c)
	for b in boundary:_add_owner(owners, objects.get(_key(b)))
	var reachable := _bed_reachable(cells, inside, objects, doors, beds)
	var contributors: Array[String] = []
	for o in owners:contributors.append(o)
	contributors.sort()
	var missing: Array[String] = []
	if truncated:missing.append("地板範圍超過 %d 格，請確認牆面是否圍好" % MAX_CELLS)
	if cells.size() < MIN_AREA:missing.append("室內地板只有 %d 格，至少需要 %d 格" % [cells.size(), MIN_AREA])
	if gaps > 0:missing.append("牆面有 %d 處缺口，請用牆、窗或門圍起來" % gaps)
	if doors.is_empty():missing.append("還沒有門，至少需要 1 扇門")
	if roof_missing > 0:missing.append("屋頂缺 %d 格" % roof_missing)
	if beds.is_empty():missing.append("室內還沒有床")
	elif not doors.is_empty() and not reachable:missing.append("從門內走不到床邊，請挪開擋路的家具")
	result.found = true
	result.cells = cells
	result.area = cells.size()
	result.door_count = doors.size()
	result.roof_missing = roof_missing
	result.gap_count = gaps
	result.bed_count = beds.size()
	result.reachable_bed = reachable
	result.contributors = contributors
	result.missing = missing
	result.complete = missing.is_empty()
	return result

## Qualifies a furnished room at its actual interior tile, even if the broader
## structure inspection can also be opened from outside.
static func guest_room(snapshot:Dictionary,room:Dictionary,at:Vector2i,owner:String) -> Dictionary:
	var furnished:={"bed":false,"lamp":false,"chair":false}
	var contributed:=false
	var objects:=_layer(snapshot,"objects")
	for cell:Vector2i in room.get("cells",[]):
		var obj:Dictionary=objects.get(_key(cell),{})
		var kind:=str(obj.get("type",""))
		if kind not in furnished:continue
		furnished[kind]=true
		if obj.get("owner","")==owner:contributed=true
	var inside:bool=at in room.get("cells",[])
	return {"furnished":furnished,"inside":inside,"contributed":contributed,
		"ready":inside and room.get("complete",false) and contributed and furnished.values().all(func(value:bool):return value)}

static func _bed_reachable(cells: Array[Vector2i], inside: Dictionary, objects: Dictionary, doors: Dictionary, beds: Array[Vector2i]) -> bool:
	if doors.is_empty() or beds.is_empty():return false
	var bed_set := {}
	for b in beds:bed_set[b] = true
	var seen := {}
	var queue: Array[Vector2i] = []
	for c in cells:
		if not _walkable(inside, objects, c):continue
		for d in DIRS:
			if doors.has(c + d):
				seen[c] = true
				queue.append(c)
				break
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in DIRS:
			if bed_set.has(c + d):return true
		for d in DIRS:
			var n: Vector2i = c + d
			if seen.has(n) or not _walkable(inside, objects, n):continue
			seen[n] = true
			queue.append(n)
	return false

static func _walkable(inside: Dictionary, objects: Dictionary, p: Vector2i) -> bool:
	# Match actual object collisions: chairs, lamps, signs and pipes remain walkable.
	return inside.has(p) and _type(objects,p) not in SOLID_OBJECTS

static func _is_floor(ground: Dictionary, objects: Dictionary, p: Vector2i) -> bool:
	var g = ground.get(_key(p))
	if not (g is Dictionary) or str(g.get("type", "")) != "floor":return false
	return _type(objects, p) not in BOUNDARY

static func _type(objects: Dictionary, p: Vector2i) -> String:
	var o = objects.get(_key(p))
	return str(o.get("type", "")) if o is Dictionary else ""

static func _add_owner(owners: Dictionary, entry) -> void:
	if not (entry is Dictionary):return
	var o = entry.get("owner", "")
	if o is String and o != "":owners[o] = true

static func _layer(snapshot: Dictionary, field: String) -> Dictionary:
	var layer = snapshot.get(field, {})
	return layer if layer is Dictionary else {}

static func _key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]

static func _empty() -> Dictionary:
	var cells: Array[Vector2i] = []
	var contributors: Array[String] = []
	var missing: Array[String] = []
	return {"found": false, "cells": cells, "area": 0, "door_count": 0, "roof_missing": 0, "gap_count": 0, "bed_count": 0, "reachable_bed": false, "complete": false, "contributors": contributors, "missing": missing}
