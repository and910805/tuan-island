extends RefCounted
## Decides which roof tiles fade for the LOCAL player over one CURRENT-REGION snapshot.
## Pure and read-only: never mutates the snapshot, never touches World or the scene.
## Returns {tile_key: true}. Malformed or missing input returns {}.
##
## Two independent reasons fade a roof tile:
## 1. Shelter: the local player's foot cell is roofed. The faded set is the roofed
##    component reachable from the foot cell by cardinal steps that never enter a
##    structural boundary cell (wall/window/door, same set as HouseRooms.BOUNDARY),
##    plus the roofed boundary cells directly framing that component. An interior
##    room therefore fades on its own; a neighbouring room behind a wall or door
##    keeps its roof. An open roof terrace (roofs without walls) fades as one
##    bounded component, as before, but stops at walls.
## 2. Occlusion: a roof tile's drawn rect overlaps the local player's drawn body
##    rect, so feet just south of / beside a roof are never hidden.
## Other players never contribute to either rule.

const HouseRooms = preload("res://scripts/house_rooms.gd")
const EdgeGrid = preload("res://scripts/edge_grid.gd")
const TILE := 32.0
const MAX_CELLS := 512
# world_view.roof_sprite: Rect2(at+Vector2(0,-8),Vector2(32,32)) where at=screen(cell).
const ROOF_OFFSET := Vector2(0, -8)
const ROOF_SIZE := Vector2(32, 32)
# character_sprite_art.draw_person: Rect2(foot.round()-FOOT(24,44), FRAME_SIZE(48,48)).
# The procedural fallback (world_pixel_art.person) spans x -14..14, y -39..5 around the
# foot; the union of both is used so either renderer is covered.
const BODY_RECT := Rect2(-24, -44, 48, 49)
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## visual_position: the tile-space position the body is actually drawn at
## (world_view.display_positions). Defaults to the snapshot position when not finite.
static func faded(snapshot: Dictionary, player_id: String, visual_position := Vector2.INF) -> Dictionary:
	var result := {}
	if player_id.is_empty():return result
	var players = snapshot.get("players")
	var roofs = snapshot.get("roofs")
	if not (players is Dictionary) or not (roofs is Dictionary) or roofs.is_empty():return result
	var person = players.get(player_id)
	if not (person is Dictionary):return result
	var px = person.get("x")
	var py = person.get("y")
	if not (_is_number(px) and _is_number(py)):return result
	var logical := Vector2(float(px), float(py))
	if not logical.is_finite():return result
	var objects = snapshot.get("objects", {})
	if not (objects is Dictionary):objects = {}
	var edges = snapshot.get("edges", {})
	if not (edges is Dictionary):edges = {}
	var drawn := visual_position if visual_position.is_finite() else logical
	# Use the same interpolated foot for both rules, avoiding an early room switch
	# when the newest server snapshot is ahead of the rendered character.
	_shelter(result, roofs, objects, edges, Vector2i(drawn.floor()))
	_occlusion(result, roofs, drawn)
	return result

static func _shelter(result: Dictionary, roofs: Dictionary, objects: Dictionary, edges: Dictionary, foot: Vector2i) -> void:
	if not roofs.has(_key(foot)):return
	var seeds: Array[Vector2i] = []
	if _is_boundary(objects, foot):
		# Standing in a doorway: fade the doorway itself plus the roofed spaces it joins.
		result[_key(foot)] = true
		for side in DIRS.size():
			if _edge_between(edges, foot, side):continue
			var n: Vector2i = foot + DIRS[side]
			if roofs.has(_key(n)) and not _is_boundary(objects, n):seeds.append(n)
	else:
		seeds.append(foot)
	var inside := {}
	var queue: Array[Vector2i] = []
	for s in seeds:
		if inside.has(s) or inside.size() >= MAX_CELLS:continue
		inside[s] = true
		queue.append(s)
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for side in DIRS.size():
			if _edge_between(edges, c, side):continue
			var n: Vector2i = c + DIRS[side]
			if inside.has(n) or not roofs.has(_key(n)) or _is_boundary(objects, n):continue
			if inside.size() >= MAX_CELLS:break
			inside[n] = true
			queue.append(n)
	for c in queue:
		result[_key(c)] = true
		# Roofed walls/windows/doors framing the space fade with it so its edges read clearly.
		for side in DIRS.size():
			if _edge_between(edges, c, side):continue
			var n: Vector2i = c + DIRS[side]
			if result.size() >= MAX_CELLS * 2:return
			if not inside.has(n) and _is_boundary(objects, n) and roofs.has(_key(n)):result[_key(n)] = true

static func _edge_between(edges: Dictionary, c: Vector2i, side: int) -> bool:
	return not edges.is_empty() and edges.has(EdgeGrid.key(c, side))

static func _occlusion(result: Dictionary, roofs: Dictionary, drawn: Vector2) -> void:
	# Camera is integer-rounded in world_view, so the drawn foot in world pixels is round(p*TILE).
	var body := Rect2((drawn * TILE).round() + BODY_RECT.position, BODY_RECT.size)
	var x0 := floori((body.position.x - ROOF_OFFSET.x - ROOF_SIZE.x) / TILE)
	var x1 := ceili((body.end.x - ROOF_OFFSET.x) / TILE)
	var y0 := floori((body.position.y - ROOF_OFFSET.y - ROOF_SIZE.y) / TILE)
	var y1 := ceili((body.end.y - ROOF_OFFSET.y) / TILE)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell := Vector2i(x, y)
			var k := _key(cell)
			if not roofs.has(k):continue
			if Rect2(Vector2(cell) * TILE + ROOF_OFFSET, ROOF_SIZE).intersects(body):result[k] = true

static func _is_boundary(objects: Dictionary, p: Vector2i) -> bool:
	var o = objects.get(_key(p))
	return o is Dictionary and str(o.get("type", "")) in HouseRooms.BOUNDARY

static func _is_number(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

static func _key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]
