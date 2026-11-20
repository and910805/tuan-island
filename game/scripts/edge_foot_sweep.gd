extends RefCounted
## Pure edge-wall collision geometry for the player's foot rectangle. No World, no state, not wired
## into the game yet. Companion to EdgeGrid (edge keys) and INDUSTRY.FOOT_BOX (foot offsets).
##
## Coordinates: continuous world units, cell (x,y) covers [x,x+1) x [y,y+1), y grows downward.
## Edges live on integer grid lines and are finite unit segments (see EdgeGrid):
##   "x,y,N" is the horizontal segment on line Y=y spanning X in [x,x+1]
##   "x,y,W" is the vertical   segment on line X=x spanning Y in [y,y+1]
## `edges` maps canonical key -> {"type": "edge_wall"|"edge_door"|"edge_window", "owner": String, "open": bool}.
## A present row blocks unless it is an "edge_door" whose "open" is exactly true. Walls and windows
## always block. A present row that is malformed (not a Dictionary, unknown type) fails closed
## and blocks. Keys EdgeGrid rejects for `bounds` (off map) are ignored, so rim edges work.
##
## Foot: the bounding rectangle of `foot_offsets` (Array of Vector2) around the position. Empty
## or non-Vector2 offsets degrade to a point foot at the position.
##
## Touching: a foot side lying exactly on a grid line, or a foot segment overlap of zero length
## (the foot ending exactly where a segment starts), is NOT a collision. Only a positive-length
## overlap with a segment counts, and only a foot side strictly passing a line counts as crossing.
##
## can_stand: false when the foot rectangle's interior is straddled by a closed segment, i.e. a
## grid line passes strictly inside the foot and the segment overlaps the foot by a positive length.
##
## blocks_axis(from, to, ...): the move must be strictly axis aligned (from.x == to.x exactly,
## or from.y == to.y exactly). Behaviour:
##   - from == to: false (no movement, nothing crossed).
##   - diagonal or non-finite input: true (fail closed; callers must split axes like World.move_player).
##   - otherwise true when the swept foot would (a) cross, with its leading side, any grid line
##     perpendicular to the motion at a closed segment that the foot overlaps, a line the leading
##     side starts exactly on counts as crossed when moving away from it into it, one it ends
##     exactly on does not; or (b) newly overlap a closed segment lying parallel to the motion
##     (inside the foot's width) anywhere along the sweep. Overlaps already present at `from`
##     are ignored, so a foot stuck astride a wall can still move out. Every line in the sweep is
##     tested, so large steps cannot tunnel. Line/segment ranges are clamped to the map, so cost is
##     bounded by the map size, not the step length.
## Empty `edges` returns immediately. Lookups reuse the one dictionary; only short key strings are made.

const EdgeGrid := preload("res://scripts/edge_grid.gd")
const CLAMP := 1.0e9

static func can_stand(pos: Vector2, edges: Dictionary, bounds: Vector2i, foot_offsets: Array) -> bool:
	if not (is_finite(pos.x) and is_finite(pos.y)):
		return false
	if edges.is_empty():
		return true
	var f := _foot(foot_offsets)
	var x0 := pos.x + f.x
	var y0 := pos.y + f.y
	var x1 := pos.x + f.z
	var y1 := pos.y + f.w
	if _wall_hit(edges, bounds, true, _fl(x0) + 1, _ce(x1) - 1, y0, y1):
		return false
	if _wall_hit(edges, bounds, false, _fl(y0) + 1, _ce(y1) - 1, x0, x1):
		return false
	return true

static func blocks_axis(from: Vector2, to: Vector2, edges: Dictionary, bounds: Vector2i, foot_offsets: Array) -> bool:
	if not (is_finite(from.x) and is_finite(from.y) and is_finite(to.x) and is_finite(to.y)):
		return true
	var horiz := from.y == to.y
	if not horiz and from.x != to.x:
		return true
	if from == to:
		return false
	if edges.is_empty():
		return false
	var f := _foot(foot_offsets)
	var af: float
	var at: float
	var p: float
	var lo_a: float
	var hi_a: float
	var lo_p: float
	var hi_p: float
	if horiz:
		af = from.x; at = to.x; p = from.y
		lo_a = f.x; hi_a = f.z; lo_p = f.y; hi_p = f.w
	else:
		af = from.y; at = to.y; p = from.x
		lo_a = f.y; hi_a = f.w; lo_p = f.x; hi_p = f.z
	# Lines perpendicular to motion crossed by the leading side.
	var first: int
	var last: int
	if at > af:
		first = _ce(af + hi_a)
		last = _ce(at + hi_a) - 1
	else:
		first = _fl(at + lo_a) + 1
		last = _fl(af + lo_a)
	if _wall_hit(edges, bounds, horiz, first, last, p + lo_p, p + hi_p):
		return true
	# Segments parallel to motion that the foot would newly overlap anywhere along the sweep.
	var src_lo := af + lo_a
	var src_hi := af + hi_a
	return _wall_hit(edges, bounds, not horiz, _fl(p + lo_p) + 1, _ce(p + hi_p) - 1,
		minf(af, at) + lo_a, maxf(af, at) + hi_a, true, src_lo, src_hi)

## True when a blocking segment exists on any line l0..l1 (inclusive ints) at a segment index
## overlapping the open interval (a,b) by positive length. `vertical` selects "x,y,W" lines on X
## (segments along Y) versus "x,y,N" lines on Y (segments along X). With `skip`, segments
## overlapping the open interval (sa,sb) are ignored.
static func _wall_hit(edges: Dictionary, bounds: Vector2i, vertical: bool, l0: int, l1: int,
		a: float, b: float, skip := false, sa := 0.0, sb := 0.0) -> bool:
	var line_max := bounds.x if vertical else bounds.y
	var seg_max := (bounds.y if vertical else bounds.x) - 1
	var lo := maxi(l0, 0)
	var hi := mini(l1, line_max)
	if lo > hi:
		return false
	var first := _fl(a)
	var last := (_ce(b) - 1) if b > a else first
	var s0 := maxi(first, 0)
	var s1 := mini(last, seg_max)
	for line in range(lo, hi + 1):
		for seg in range(s0, s1 + 1):
			if skip and seg + 1 > sa and seg < sb:
				continue
			var k: String
			if vertical:
				k = EdgeGrid.key(Vector2i(line, seg), EdgeGrid.SIDE_W, bounds)
			else:
				k = EdgeGrid.key(Vector2i(seg, line), EdgeGrid.SIDE_N, bounds)
			if k != "" and edges.has(k) and _row_blocks(edges[k]):
				return true
	return false

static func _row_blocks(row) -> bool:
	if typeof(row) != TYPE_DICTIONARY:
		return true
	var d: Dictionary = row
	if d.get("type") == "edge_door":
		var opened:Variant=d.get("open")
		return not (opened is bool and opened)
	return true

## Bounding box of the offsets as Vector4(min_x, min_y, max_x, max_y).
static func _foot(offsets: Array) -> Vector4:
	var any := false
	var r := Vector4.ZERO
	for o in offsets:
		if not (o is Vector2):
			continue
		if not any:
			r = Vector4(o.x, o.y, o.x, o.y)
			any = true
		else:
			r.x = minf(r.x, o.x)
			r.y = minf(r.y, o.y)
			r.z = maxf(r.z, o.x)
			r.w = maxf(r.w, o.y)
	return r

static func _fl(v: float) -> int:
	return int(floorf(clampf(v, -CLAMP, CLAMP)))

static func _ce(v: float) -> int:
	return int(ceilf(clampf(v, -CLAMP, CLAMP)))
