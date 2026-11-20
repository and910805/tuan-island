extends RefCounted
## Structural house-room check over one CURRENT-REGION snapshot.
## Pure and read-only: never mutates the snapshot, never touches World.
## This is a structural check only. It does not prove an exterior route,
## house safety, rewards, or auto roofing.

const SEARCH_RADIUS := 8
const Enclosure = preload("res://scripts/room_enclosure.gd")
const EdgeGrid = preload("res://scripts/edge_grid.gd")
const MIN_AREA := Enclosure.MIN_AREA
const Industry=preload("res://scripts/industry.gd")
# Matches World.blocked object collisions; checked against every BUILD entry in tests.
const SOLID_OBJECTS := ["ore_display", "wall", "window", "chest", "private_chest", "supply_box", "bench", Industry.STONE_WORKBENCH, "bed", Industry.CEDAR_BED, Industry.MUSHROOM_STOOL, Industry.MUSHROOM_TABLE, Industry.BAMBOO_TEA_TABLE, Industry.HOLLOW_BED, Industry.ACORN_CABINET, "inn_quilt_bed", "inn_stone_footbath", "table", Industry.ROUNDED_TABLE, Industry.GRID_BOOKCASE, "stove",Industry.KITCHEN_STOVE,"long_bench","master_bench","spring_stone_bench",preload("res://scripts/resident_goals.gd").COTTON_SOFA,preload("res://scripts/resident_goals.gd").BAMBOO_BENCH,"small_smelter","sofa","planter","guest_wardrobe","inn_lattice_wardrobe","coast_changing_booth","forest_wardrobe","inn_fabric_screen","wood_mailbox",Industry.MUSHROOM_POST,Industry.QUIET_BIRDHOUSE,"sketch_easel","rope_rack","sea_breeze_postcard_rack","towel_rack","inn_tea_table","inn_luggage_rack","flower_pot","greenhouse_rack","garden_basin","copper_garden_chair","crop_observation_desk",Industry.LEAF_DESK,Industry.SEED_CABINET,Industry.NURSERY_BOX,Industry.AQUARIUM,Industry.COAST_FISH_COUNTER,Industry.TEA_DISPLAY_CABINET,Industry.TEA_SNACK_SHELF,Industry.COAST_REGISTER,Industry.COAST_CART,Industry.BEACH_CHAIR,Industry.RIVERSIDE_SCREEN,Industry.BAMBOO_LOUNGER,Industry.SHELL_TABLE,Industry.GLASS_FLOWER_TABLE,Industry.VINE_ARCH,Industry.FOREST_ARCH,Industry.POT_RACK,"master_flower_bed","fish_display","author_sign","author_shelf","expedition_tent","sprinkler","medium_sprinkler","large_sprinkler","water_tank","water_tower","water_pump","waterworks","mine_drill","sawmill","charcoal_kiln","forester","mill","seed_maker","loom","glass_furnace","jam_pot","clay_kiln","dye_table","assembly_table","animal_collector"]
const Goals=preload("res://scripts/resident_goals.gd")
const WallFixtures=preload("res://scripts/wall_fixtures.gd")
## Actual placed types. Styles are a field on the same type, so "bed"/"chair" cover styled pieces.
const BED_KINDS:=["bed",Industry.CEDAR_BED,Industry.INN_BED,Industry.HOLLOW_BED]
## "star_garden_lamp" mirrors World.STAR_GARDEN_LAMP (World is not preloaded here).
const LAMP_KINDS:=["lamp",Industry.PAPER_TEA_LAMP,Industry.SPORE_LAMP,"star_garden_lamp",WallFixtures.LIGHT]
const SEAT_KINDS:=[Industry.WOOD_CHAIR,Goals.GARDEN_CHAIR,Industry.MUSHROOM_STOOL,Industry.INDIGO_CUSHION,
	Industry.BAMBOO_LOUNGER,Industry.BEACH_CHAIR,"long_bench","sofa"]+Goals.DOUBLE_BENCHES
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
		result.missing.append("附近 %d 格內沒有室內地板，請先鋪木地板或石地板" % SEARCH_RADIUS)
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
	var edges := _layer(snapshot, "edges")
	var edge_doors: Array = enclosure.get("edge_doors", [])
	var door_count := doors.size() + edge_doors.size()
	var gaps:int = enclosure.gap_count
	var roof_missing := 0
	var beds: Array[Vector2i] = []
	var bed_cells := {}
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
			if str(obj.get("type","")) in BED_KINDS:
				var footprint:=_piece_cells(objects,inside,c)
				if not footprint.is_empty():
					beds.append(c)
					for p in footprint:bed_cells[p]=true
	for b in boundary:_add_owner(owners, objects.get(_key(b)))
	for edge in enclosure.get("edge_boundary", []):_add_owner(owners, edges.get(edge))
	var reachable := _bed_reachable(cells, inside, objects, doors, edges, edge_doors, bed_cells)
	var contributors: Array[String] = []
	for o in owners:contributors.append(o)
	contributors.sort()
	var missing: Array[String] = []
	if truncated:missing.append("地板範圍超過 %d 格，請確認牆面是否圍好" % MAX_CELLS)
	if cells.size() < MIN_AREA:missing.append("室內地板只有 %d 格，至少需要 %d 格" % [cells.size(), MIN_AREA])
	if gaps > 0:missing.append("牆面有 %d 處缺口，請用牆、窗或門圍起來" % gaps)
	if door_count==0:missing.append("還沒有門，至少需要 1 扇門")
	if roof_missing > 0:missing.append("屋頂缺 %d 格" % roof_missing)
	if beds.is_empty():missing.append("室內還沒有床")
	elif door_count>0 and not reachable:missing.append("從門內走不到床邊，請挪開擋路的家具")
	result.found = true
	result.cells = cells
	result.area = cells.size()
	result.door_count = door_count
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
	var room_cells:Array=room.get("cells",[])
	var cell_set:={}
	for cell:Vector2i in room_cells:cell_set[cell]=true
	for cell:Vector2i in room_cells:
		var obj:Variant=objects.get(_key(cell))
		if not obj is Dictionary:continue
		var type:=str(obj.get("type",""))
		var kind:="bed" if type in BED_KINDS else "lamp" if type in LAMP_KINDS else "chair" if type in SEAT_KINDS else ""
		if kind.is_empty():continue
		# Only whole pieces inside the room count; orphan fillers and cut footprints do not.
		if _piece_cells(objects,cell_set,cell).is_empty():continue
		furnished[kind]=true
		if obj.get("owner","")==owner:contributed=true
	var inside:bool=at in room_cells
	return {"furnished":furnished,"inside":inside,"contributed":contributed,
		"ready":inside and room.get("complete",false) and contributed and furnished.values().all(func(value:bool):return value)}

## Cells of the complete furnishing anchored at `c`, or [] when it is not a whole piece inside
## `inside` (a cell set). Multi-cell pieces follow Industry.station_cells/square_part (part i sits at
## offset i, same type); two-seat benches follow bench_end/bench_vertical. Fillers never anchor.
static func _piece_cells(objects: Dictionary, inside: Dictionary, c: Vector2i) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	var obj = objects.get(_key(c))
	if not obj is Dictionary or not inside.has(c):return none
	var kind := str(obj.get("type", ""))
	var found: Array[Vector2i] = [c]
	if kind==Industry.BEACH_CHAIR and obj.get("beach_chair_folded",false):return none
	if kind in Goals.DOUBLE_BENCHES:
		if obj.get("bench_end", false) == true:return none
		var vertical:bool = obj.get("bench_vertical", false) == true
		var end_cell := c + (Vector2i.DOWN if vertical else Vector2i.RIGHT)
		var end = objects.get(_key(end_cell))
		if not inside.has(end_cell) or not end is Dictionary or end.get("type") != kind or end.get("owner") != obj.get("owner") or end.get("bench_end", false) != true or (end.get("bench_vertical", false) == true) != vertical:return none
		found.append(end_cell)
		return found
	if Industry.square_part_field(kind).is_empty():return found
	if Industry.square_part(obj) != 0:return none
	var offsets := Industry.station_cells(kind, Industry.is_vertical(obj))
	for i in range(1, offsets.size()):
		var p: Vector2i = c + offsets[i]
		var other = objects.get(_key(p))
		if not inside.has(p) or not other is Dictionary or other.get("type") != kind or other.get("owner") != obj.get("owner") or Industry.square_part(other) != i or Industry.is_vertical(other)!=Industry.is_vertical(obj):return none
		found.append(p)
	return found

static func _bed_reachable(cells: Array[Vector2i], inside: Dictionary, objects: Dictionary, doors: Dictionary, edges: Dictionary, edge_doors: Array, bed_set: Dictionary) -> bool:
	if (doors.is_empty() and edge_doors.is_empty()) or bed_set.is_empty():return false
	var seen := {}
	var queue: Array[Vector2i] = []
	for edge in edge_doors:
		for c in EdgeGrid.cells_of(edge):
			if seen.has(c) or not _walkable(inside, objects, c):continue
			seen[c] = true
			queue.append(c)
	for c in cells:
		if seen.has(c) or not _walkable(inside, objects, c):continue
		for side in DIRS.size():
			if doors.has(c + DIRS[side]) and not _edge_between(edges, c, side):
				seen[c] = true
				queue.append(c)
				break
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for side in DIRS.size():
			if _edge_between(edges, c, side):continue
			var n: Vector2i = c + DIRS[side]
			if bed_set.has(n):return true
			if seen.has(n) or not _walkable(inside, objects, n):continue
			seen[n] = true
			queue.append(n)
	return false

static func _edge_between(edges: Dictionary, c: Vector2i, side: int) -> bool:
	return not edges.is_empty() and edges.has(EdgeGrid.key(c, side))

static func _walkable(inside: Dictionary, objects: Dictionary, p: Vector2i) -> bool:
	# Match actual object collisions: chairs, lamps, signs and pipes remain walkable.
	return inside.has(p) and (_type(objects,p) not in SOLID_OBJECTS or Industry.is_folded_passage(objects.get(_key(p),{})))

static func _is_floor(ground: Dictionary, objects: Dictionary, p: Vector2i) -> bool:
	var g = ground.get(_key(p))
	if not Enclosure.is_floor_piece(g):return false
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
