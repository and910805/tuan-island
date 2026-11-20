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
##   edge_boundary: Array[String] deduplicated canonical edge keys (snapshot.edges rows of type
##                               edge_wall/edge_window/edge_door) on a component cell's side.
##                               An edge is a flood barrier even with floor on both sides and
##                               regardless of door "open" (open affects movement only). Edges
##                               are checked before legacy wall and before gap counting.
##   edge_doors: Array[String]  subset of edge_boundary of type edge_door. Sorted lexically.
##   area:      int              cells.size()
##   gap_count: int              exposed cardinal edges: (cell, dir) pairs whose neighbour
##                               is neither in the component nor a boundary object.
##   truncated: bool             traversal hit MAX_CELLS with more floor still reachable.
##   sealed:    bool             area >= MIN_AREA and gap_count == 0 and (doors >= 1 or
##                               edge_doors >= 1) of THIS room, and not truncated.
## Arrays are sorted by y, then x. Beds, roofs, furniture, paths and ownership are not
## enclosure conditions (paths are simply not floor, so they read as gaps).

const EdgeGrid = preload("res://scripts/edge_grid.gd")
## Typed edge rows stored in snapshot.edges[canonical EdgeGrid key] = {"type": ...}.
const EDGE_TYPES := ["edge_wall", "edge_window", "edge_door"]
const MIN_AREA := 4
const MAX_CELLS := 400
const BOUNDARY := ["wall", "window", "door"]
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## C09: the single definition of a structural (room-forming, roof-supporting) ground kind.
## Wood floor ("floor") and stone floor ("stone_floor") are interchangeable for enclosure,
## roof support and floor permissions. Paths (path / spring_pebble_path) never qualify.
const WOOD_FLOOR := "floor"
const STONE_FLOOR := "stone_floor"
const FLOOR_KINDS := ["floor", "stone_floor"]

## True for a ground `type` value that is a structural floor. Non-strings are never floors.
static func is_floor_kind(kind) -> bool:
	return (typeof(kind) == TYPE_STRING or typeof(kind) == TYPE_STRING_NAME) and String(kind) in FLOOR_KINDS

## True when a ground entry (Dictionary with a "type") is a structural floor.
static func is_floor_piece(piece) -> bool:
	return piece is Dictionary and is_floor_kind(piece.get("type"))

static func analyze(snapshot: Dictionary, seed: Vector2i) -> Dictionary:
	var ground := _layer(snapshot, "ground")
	var objects := _layer(snapshot, "objects")
	var edges := _layer(snapshot, "edges")
	if not _is_floor(ground, objects, seed):
		return _result([], [], [], [], [], 0, false)
	var inside := {seed: true}
	var queue: Array[Vector2i] = [seed]
	var head := 0
	var truncated := false
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for side in DIRS.size():
			var n: Vector2i = c + DIRS[side]
			# An edge row is a barrier even with floor on both sides (open affects movement only).
			if _edge_type(edges, c, side) != "":continue
			if inside.has(n) or not _is_floor(ground, objects, n):continue
			if inside.size() >= MAX_CELLS:
				truncated = true
				continue
			inside[n] = true
			queue.append(n)
	var boundary := {}
	var doors := {}
	var edge_boundary := {}
	var edge_doors := {}
	var gaps := 0
	for c in queue:
		for side in DIRS.size():
			var n: Vector2i = c + DIRS[side]
			# Edge boundary is counted first: before legacy wall and before gap.
			var et := _edge_type(edges, c, side)
			if et != "":
				var ek := EdgeGrid.key(c, side)
				edge_boundary[ek] = true
				if et == "edge_door":edge_doors[ek] = true
				continue
			if inside.has(n):continue
			var t := _type(objects, n)
			if t in BOUNDARY:
				boundary[n] = true
				if t == "door":doors[n] = true
			else:
				gaps += 1
	return _result(queue, boundary.keys(), doors.keys(), edge_boundary.keys(), edge_doors.keys(), gaps, truncated)

## Edge row type ("edge_wall"/"edge_window"/"edge_door") on `side` of `cell`, or "" when none.
## Looked up by the canonical EdgeGrid key, so both neighbours see the same row.
static func _edge_type(edges: Dictionary, cell: Vector2i, side: int) -> String:
	if edges.is_empty():return ""
	var k := EdgeGrid.key(cell, side)
	if k == "":return ""
	var row = edges.get(k)
	if not (row is Dictionary):return ""
	var t := str(row.get("type", ""))
	return t if t in EDGE_TYPES else ""

static func _result(cells_in: Array, boundary_in: Array, doors_in: Array, edge_boundary_in: Array, edge_doors_in: Array, gaps: int, truncated: bool) -> Dictionary:
	var cells := _sorted(cells_in)
	var boundary := _sorted(boundary_in)
	var doors := _sorted(doors_in)
	var edge_boundary: Array[String] = []
	for k in edge_boundary_in:edge_boundary.append(k)
	edge_boundary.sort()
	var edge_doors: Array[String] = []
	for k in edge_doors_in:edge_doors.append(k)
	edge_doors.sort()
	var area := cells.size()
	var has_door := doors.size() >= 1 or edge_doors.size() >= 1
	var sealed := area >= MIN_AREA and gaps == 0 and has_door and not truncated
	return {"cells": cells, "boundary": boundary, "doors": doors, "edge_boundary": edge_boundary, "edge_doors": edge_doors, "area": area, "gap_count": gaps, "truncated": truncated, "sealed": sealed}

static func _sorted(source: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in source:out.append(p)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out

static func _is_floor(ground: Dictionary, objects: Dictionary, p: Vector2i) -> bool:
	var g = ground.get(_key(p))
	if not is_floor_piece(g):return false
	return _type(objects, p) not in BOUNDARY

static func _type(objects: Dictionary, p: Vector2i) -> String:
	var o = objects.get(_key(p))
	return str(o.get("type", "")) if o is Dictionary else ""

static func _layer(snapshot: Dictionary, field: String) -> Dictionary:
	var layer = snapshot.get(field, {})
	return layer if layer is Dictionary else {}

static func _key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]
