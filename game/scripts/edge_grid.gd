extends RefCounted
## Pure edge-grid geometry for true boundary walls (C02/C03/C04). No World, no snapshot,
## no state: only integer math and canonical string keys. Nothing here is wired into the game.
##
## Sides are the four edges of a floor cell, clockwise from north (screen up = -y):
##   SIDE_N=0 (dy -1)   SIDE_E=1 (dx +1)   SIDE_S=2 (dy +1)   SIDE_W=3 (dx -1)
##
## One physical edge is shared by two cells: the S side of (x,y) IS the N side of (x,y+1),
## and the E side of (x,y) IS the W side of (x+1,y). To store it once, every edge has exactly
## one canonical key, always written from the cell that owns its N or W side:
##   "x,y,N"  north edge of cell (x,y)   (also south edge of (x,y-1))
##   "x,y,W"  west  edge of cell (x,y)   (also east  edge of (x-1,y))
## key(cell, side) gives the same string whichever of the two cells is used to ask.
## Cells on the map rim therefore have real outer edges: "x,H,N" and "W,y,W" exist.
##
## Bounds: a key is valid only when it touches at least one in-map cell (limits default to the
## 80x60 home map, x 0..79, y 0..59). Coordinates are plain decimal, no sign, no leading zeros,
## so "01,2,N", "+1,2,N", "-1,2,N", " 1,2,N", "1,2,n", "1,2,S" and "1,2,N," are all rejected.
## Every function returns "" / {} / [] on bad input instead of raising; never a half-valid result.
##
## Decoded edge = {"cell": Vector2i, "side": SIDE_N or SIDE_W}  (canonical form only).
## Round trip: decode(key(c, s)) -> canonical (cell, side); key(d.cell, d.side) == original key.

const SIDE_N := 0
const SIDE_E := 1
const SIDE_S := 2
const SIDE_W := 3
const SIDE_COUNT := 4
## Letter written in keys; only N and W are canonical.
const SIDE_LETTERS := ["N", "E", "S", "W"]
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## Home region defaults. Callers can supply the actual bounds for other regions or blueprints.
const MAP_SIZE := Vector2i(80, 60)
const MAX_DIGITS := 6

## True for an int side 0..3 (bool, float and string are not sides).
static func is_side(side) -> bool:
	return typeof(side) == TYPE_INT and side >= 0 and side < SIDE_COUNT

static func opposite(side: int) -> int:
	return (side + 2) % SIDE_COUNT if is_side(side) else -1

## Side after `turns` clockwise quarter turns (negative turns go counter-clockwise). -1 if bad.
static func rotate_side(side, turns) -> int:
	if not is_side(side) or typeof(turns) != TYPE_INT:
		return -1
	return posmod(side + turns, SIDE_COUNT)

## True if `cell` is an in-map cell.
static func in_bounds(cell, limits: Vector2i = MAP_SIZE) -> bool:
	return cell is Vector2i and cell.x >= 0 and cell.y >= 0 and cell.x < limits.x and cell.y < limits.y

## Cell on the other side of `side` of `cell` (no bounds check). Vector2i of cell if side is bad.
static func neighbor(cell: Vector2i, side: int) -> Vector2i:
	return cell + DIRS[side] if is_side(side) else cell

## Canonical form of (cell, side) as {"cell","side"} with side N or W, or {} when the edge
## touches no in-map cell or the arguments are bad.
static func canonical(cell, side, limits: Vector2i = MAP_SIZE) -> Dictionary:
	if not (cell is Vector2i) or not is_side(side):
		return {}
	var owner: Vector2i = cell
	var s: int = side
	if s == SIDE_S:
		owner = cell + Vector2i(0, 1)
		s = SIDE_N
	elif s == SIDE_E:
		owner = cell + Vector2i(1, 0)
		s = SIDE_W
	# The edge separates `owner` and `owner + DIRS[s]` (N/W neighbour); one must be in-map.
	if not (in_bounds(owner, limits) or in_bounds(owner + DIRS[s], limits)):
		return {}
	# Also reject anything with a negative owner coordinate (not a representable key).
	if owner.x < 0 or owner.y < 0:
		return {}
	return {"cell": owner, "side": s}

## Canonical key for the edge on `side` of `cell`, or "" if invalid. Independent of which
## adjacent cell is used: key(c, SIDE_S) == key(c + (0,1), SIDE_N).
static func key(cell, side, limits: Vector2i = MAP_SIZE) -> String:
	var c := canonical(cell, side, limits)
	if c.is_empty():
		return ""
	var o: Vector2i = c.cell
	# Owner coordinates may reach limits (rim edge) but never beyond, and never go negative.
	if o.x > limits.x or o.y > limits.y:
		return ""
	return "%d,%d,%s" % [o.x, o.y, SIDE_LETTERS[c.side]]

## Strict decode. Returns {"cell": Vector2i, "side": SIDE_N|SIDE_W} or {} for anything that is
## not exactly a canonical key (wrong type, wrong shape, S/E letters, bad digits, out of map).
static func decode(k, limits: Vector2i = MAP_SIZE) -> Dictionary:
	if typeof(k) != TYPE_STRING:
		return {}
	var parts: PackedStringArray = (k as String).split(",", true)
	if parts.size() != 3:
		return {}
	if not _is_plain_uint(parts[0]) or not _is_plain_uint(parts[1]):
		return {}
	var side := -1
	if parts[2] == "N":
		side = SIDE_N
	elif parts[2] == "W":
		side = SIDE_W
	else:
		return {}
	var cell := Vector2i(int(parts[0]), int(parts[1]))
	# Re-encode and compare: guarantees decode accepts only what key() would emit.
	if key(cell, side, limits) != k:
		return {}
	return {"cell": cell, "side": side}

static func is_valid_key(k, limits: Vector2i = MAP_SIZE) -> bool:
	return not decode(k, limits).is_empty()

## The two cells an edge separates, as [first, second] ordered N->S or W->E:
## "x,y,N" -> [(x,y-1), (x,y)];  "x,y,W" -> [(x-1,y), (x,y)]. Cells may lie off-map on the rim
## (use in_bounds to filter). [] if the key is invalid.
static func cells_of(k, limits: Vector2i = MAP_SIZE) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := decode(k, limits)
	if d.is_empty():
		return out
	var c: Vector2i = d.cell
	out.append(c + DIRS[d.side])
	out.append(c)
	return out

## Edge keys of the four sides of `cell` in N, E, S, W order. [] if the cell is off-map.
static func edges_of_cell(cell, limits: Vector2i = MAP_SIZE) -> Array[String]:
	var out: Array[String] = []
	if not in_bounds(cell, limits):
		return out
	for s in SIDE_COUNT:
		out.append(key(cell, s, limits))
	return out

## The 2 to 6 edge keys that share a corner end with this edge (the other edges that touch it
## at its two endpoints, excluding itself); used later to close corners. [] if invalid.
## Order is deterministic: sorted lexically.
static func touching(k, limits: Vector2i = MAP_SIZE) -> Array[String]:
	var out: Array[String] = []
	var d := decode(k, limits)
	if d.is_empty():
		return out
	var c: Vector2i = d.cell
	var cands: Array[String] = []
	if d.side == SIDE_N:
		# Corners at (x,y) and (x+1,y): edges W/N/W around them.
		cands = [key(c, SIDE_W, limits), key(c + Vector2i(0, -1), SIDE_W, limits),
			key(c + Vector2i(1, 0), SIDE_W, limits), key(c + Vector2i(1, -1), SIDE_W, limits),
			key(c + Vector2i(-1, 0), SIDE_N, limits), key(c + Vector2i(1, 0), SIDE_N, limits)]
	else:
		cands = [key(c, SIDE_N, limits), key(c + Vector2i(-1, 0), SIDE_N, limits),
			key(c + Vector2i(0, 1), SIDE_N, limits), key(c + Vector2i(-1, 1), SIDE_N, limits),
			key(c + Vector2i(0, -1), SIDE_W, limits), key(c + Vector2i(0, 1), SIDE_W, limits)]
	for s in cands:
		if s != "" and not out.has(s):
			out.append(s)
	out.sort()
	return out

## Rotate a cell clockwise by `turns` quarter turns inside a w x h blueprint box, using the
## same formula as BlueprintDesign.rotate: one turn maps (x,y) -> (h-1-y, x) and swaps w/h.
## Works for off-box cells too (rim edges). Returns {"cell", "w", "h"} or {} on bad input.
static func rotate_cell(cell, w, h, turns) -> Dictionary:
	if not (cell is Vector2i) or typeof(w) != TYPE_INT or typeof(h) != TYPE_INT or typeof(turns) != TYPE_INT:
		return {}
	if w < 1 or h < 1:
		return {}
	var c: Vector2i = cell
	var cw: int = w
	var ch: int = h
	for i in posmod(turns, 4):
		c = Vector2i(ch - 1 - c.y, c.x)
		var t := cw
		cw = ch
		ch = t
	return {"cell": c, "w": cw, "h": ch}

## Rotate an edge given as (cell, side) clockwise by `turns` inside a w x h box. Result is the
## canonical {"cell","side"} of the rotated edge, or {} when invalid. Because the formula is
## linear, rotating via either adjacent cell gives the same canonical edge.
static func rotate_edge(cell, side, w, h, turns, limits: Vector2i = MAP_SIZE) -> Dictionary:
	if not is_side(side):
		return {}
	var r := rotate_cell(cell, w, h, turns)
	if r.is_empty():
		return {}
	return canonical(r.cell, rotate_side(side, turns), limits)

## Rotate a canonical key; returns the rotated canonical key or "" for a bad key or result.
static func rotate_key(k, w, h, turns, limits: Vector2i = MAP_SIZE) -> String:
	var d := decode(k, limits)
	if d.is_empty():
		return ""
	var r := rotate_edge(d.cell, d.side, w, h, turns, limits)
	if r.is_empty():
		return ""
	return key(r.cell, r.side, limits)

## Plain decimal non-negative integer: "0" or [1-9][0-9]*, at most MAX_DIGITS digits.
static func _is_plain_uint(s: String) -> bool:
	var n := s.length()
	if n == 0 or n > MAX_DIGITS:
		return false
	if n > 1 and s[0] == "0":
		return false
	for i in n:
		var code := s.unicode_at(i)
		if code < 48 or code > 57:
			return false
	return true
