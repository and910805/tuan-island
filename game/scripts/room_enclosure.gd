extends RefCounted
## Pure room-enclosure topology over one CURRENT-REGION snapshot (top-level
## "ground" and "objects" layers only). Intended for planned automatic roofs.
## Read-only: never mutates the snapshot, never touches World.
##
## analyze(snapshot, seed) ALWAYS returns:
##   cells:     Array[Vector2i]  cardinal-connected floor component from the EXACT seed
##                               (no nearest search). Cells holding a wall/window/door
##                               object are excluded even when floor lies beneath them.
##   boundary:  Array[Vector2i]  deduplicated wall/window/door cells cardinally adjacent
##                               to a component cell.
##   doors:     Array[Vector2i]  subset of boundary whose object is a door (open or shut).
##   area:      int              cells.size()
##   gap_count: int              exposed cardinal edges: (cell, dir) pairs whose neighbour
##                               is neither in the component nor a boundary object.
##   truncated: bool             traversal hit MAX_CELLS with more floor still reachable.
##   sealed:    bool             area >= MIN_AREA and gap_count == 0 and doors >= 1
##                               and not truncated.
## Arrays are sorted by y, then x. Beds, roofs, furniture, paths and ownership are not
## enclosure conditions (paths are simply not floor, so they read as gaps).

const MIN_AREA := 4
const MAX_CELLS := 400
const BOUNDARY := ["wall", "window", "door"]
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static func analyze(snapshot: Dictionary, seed: Vector2i) -> Dictionary:
	var ground := _layer(snapshot, "ground")
	var objects := _layer(snapshot, "objects")
	if not _is_floor(ground, objects, seed):
		return _result([], [], [], 0, false)
	var inside := {seed: true}
	var queue: Array[Vector2i] = [seed]
	var head := 0
	var truncated := false
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in DIRS:
			var n: Vector2i = c + d
			if inside.has(n) or not _is_floor(ground, objects, n):continue
			if inside.size() >= MAX_CELLS:
				truncated = true
				continue
			inside[n] = true
			queue.append(n)
	var boundary := {}
	var doors := {}
	var gaps := 0
	for c in queue:
		for d in DIRS:
			var n: Vector2i = c + d
			if inside.has(n):continue
			var t := _type(objects, n)
			if t in BOUNDARY:
				boundary[n] = true
				if t == "door":doors[n] = true
			else:
				gaps += 1
	return _result(queue, boundary.keys(), doors.keys(), gaps, truncated)

static func _result(cells_in: Array, boundary_in: Array, doors_in: Array, gaps: int, truncated: bool) -> Dictionary:
	var cells := _sorted(cells_in)
	var boundary := _sorted(boundary_in)
	var doors := _sorted(doors_in)
	var area := cells.size()
	var sealed := area >= MIN_AREA and gaps == 0 and doors.size() >= 1 and not truncated
	return {"cells": cells, "boundary": boundary, "doors": doors, "area": area, "gap_count": gaps, "truncated": truncated, "sealed": sealed}

static func _sorted(source: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in source:out.append(p)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out

static func _is_floor(ground: Dictionary, objects: Dictionary, p: Vector2i) -> bool:
	var g = ground.get(_key(p))
	if not (g is Dictionary) or str(g.get("type", "")) != "floor":return false
	return _type(objects, p) not in BOUNDARY

static func _type(objects: Dictionary, p: Vector2i) -> String:
	var o = objects.get(_key(p))
	return str(o.get("type", "")) if o is Dictionary else ""

static func _layer(snapshot: Dictionary, field: String) -> Dictionary:
	var layer = snapshot.get(field, {})
	return layer if layer is Dictionary else {}

static func _key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]
