extends RefCounted
## 32 px cozy pixel art for boundary-edge walls, windows and doors (EdgeGrid rows {type,owner,open}).
## Pure drawing: no state, no snapshot access. `at` is the screen top-left of the CANONICAL edge's
## cell, `side` is EdgeGrid.SIDE_N (horizontal wall on the cell's top line, front face toward the
## viewer) or EdgeGrid.SIDE_W (vertical wall on the cell's left line, seen as a slim top strip
## plus its south end face). Palette matches world_view's wooden wall / window / door sprites.

const SIDE_N := 0
const SIDE_W := 3
const KINDS := ["edge_wall", "edge_window", "edge_door"]

const WOOD_DARK := Color("8d694c")
const WOOD_BODY := Color("946c4f")
const WOOD_PLANK := Color("c29468")
const WOOD_CAP := Color("deba83")
const WOOD_HI := Color("f1d6a2")
const BASE_SHADOW := Color("6f5039")
const GLASS := Color("b5d8c8")
const GLASS_EDGE := Color("6c9290")
const GLASS_GLINT := Color("e8f4ea")
const MULLION := Color("dfb985")
const DOOR_PANEL := Color("aa7e53")
const DOOR_LEAF := Color("d0a36c")
const DOOR_GREEN := Color("728e64")
const DOOR_KNOB := Color("f3d794")
const DOORWAY := Color("5a4636")
const SPILL := Color("f0dba0")
const GROUND_SHADOW := Color(0.25, 0.18, 0.12, 0.28)

static func is_kind(kind: String) -> bool:
	return kind in KINDS

## Screen-space bounds (relative to `at`) that a drawn edge can touch, for culling / highlights.
static func bounds(side: int) -> Rect2:
	if side == SIDE_N:
		return Rect2(-3, -16, 38, 22)
	return Rect2(-4, -16, 8, 50)

## Draw one edge. `tint` multiplies the wood (build_tint of the row style), `alpha` fades it (ghosts,
## "player standing behind it"), `open` only matters for edge_door.
static func draw_edge(canvas: CanvasItem, at: Vector2, side: int, kind: String, open := false, tint := Color.WHITE, alpha := 1.0) -> void:
	if not is_kind(kind):
		return
	if side == SIDE_N:
		_north(canvas, at.round(), kind, open, tint, alpha)
	else:
		_west(canvas, at.round(), kind, open, tint, alpha)

## Outline (and optional wash) around an edge: hover / remove marker.
static func draw_marker(canvas: CanvasItem, at: Vector2, side: int, color: Color, wash := 0.0) -> void:
	var box := bounds(side)
	box.position += at.round()
	if wash > 0.0:
		canvas.draw_rect(box, Color(color, wash))
	canvas.draw_rect(box, color, false, 1.0)
	var mid := box.get_center()
	if wash > 0.0:
		canvas.draw_line(mid + Vector2(-4, -4), mid + Vector2(4, 4), Color(1, 0.86, 0.78), 2.0)
		canvas.draw_line(mid + Vector2(4, -4), mid + Vector2(-4, 4), Color(1, 0.86, 0.78), 2.0)

static func _fill(canvas: CanvasItem, at: Vector2, x: int, y: int, w: int, h: int, color: Color, tint: Color, alpha: float) -> void:
	var shaded := color * tint
	shaded.a = color.a * alpha
	canvas.draw_rect(Rect2(at + Vector2(x, y), Vector2(w, h)), shaded)

static func _north(c: CanvasItem, at: Vector2, kind: String, open: bool, t: Color, a: float) -> void:
	_fill(c, at, -2, 3, 36, 3, GROUND_SHADOW, Color.WHITE, a)
	_fill(c, at, -2, -13, 36, 17, WOOD_BODY, t, a)
	for j in 3:
		_fill(c, at, -1, -12 + j * 5, 34, 4, WOOD_PLANK, t, a)
		for k in 2:
			_fill(c, at, 6 + j * 9 + k * 16, -12 + j * 5, 1, 4, WOOD_BODY, t, a)
	if kind == "edge_window":
		_fill(c, at, 6, -12, 20, 14, WOOD_DARK, t, a)
		_fill(c, at, 8, -10, 16, 10, GLASS, t, a)
		_fill(c, at, 8, -10, 16, 2, GLASS_EDGE, t, a)
		_fill(c, at, 15, -10, 2, 10, MULLION, t, a)
		_fill(c, at, 10, -7, 2, 3, GLASS_GLINT, t, a)
		_fill(c, at, 5, 2, 22, 2, WOOD_CAP, t, a)
	elif kind == "edge_door":
		_fill(c, at, 3, -13, 26, 17, WOOD_DARK, t, a)
		if open:
			_fill(c, at, 5, -12, 22, 16, DOORWAY, t, a)
			_fill(c, at, 8, 2, 16, 2, SPILL, Color.WHITE, a * 0.7)
			_fill(c, at, 5, -12, 6, 16, DOOR_LEAF, t, a)
			_fill(c, at, 9, -12, 2, 16, DOOR_GREEN, t, a)
			_fill(c, at, 10, -5, 1, 2, DOOR_KNOB, t, a)
		else:
			_fill(c, at, 5, -12, 22, 16, DOOR_PANEL, t, a)
			for x in [11, 17, 23]:
				_fill(c, at, x, -12, 1, 16, WOOD_DARK, t, a)
			_fill(c, at, 22, -5, 3, 3, DOOR_KNOB, t, a)
		_fill(c, at, 3, 3, 26, 2, WOOD_CAP, t, a)
	_fill(c, at, -2, -16, 36, 3, WOOD_CAP, t, a)
	_fill(c, at, -2, -16, 36, 1, WOOD_HI, t, a)
	# Corner posts close the joints with neighbouring edges.
	_fill(c, at, -2, -13, 4, 17, WOOD_DARK, t, a)
	_fill(c, at, 30, -13, 4, 17, WOOD_DARK, t, a)
	_fill(c, at, -2, 2, 36, 2, BASE_SHADOW, t, a)

static func _west(c: CanvasItem, at: Vector2, kind: String, open: bool, t: Color, a: float) -> void:
	_fill(c, at, 4, 0, 3, 32, GROUND_SHADOW, Color.WHITE, a)
	# Top strip of the wall (its height read upward), then the south end face.
	_fill(c, at, -4, -16, 8, 32, WOOD_PLANK, t, a)
	for y in [-8, 0, 8]:
		_fill(c, at, -3, y, 6, 1, WOOD_BODY, t, a)
	_fill(c, at, -4, -16, 1, 32, WOOD_CAP, t, a)
	_fill(c, at, 3, -16, 1, 32, WOOD_BODY, t, a)
	_fill(c, at, -4, 16, 8, 16, WOOD_BODY, t, a)
	for j in 3:
		_fill(c, at, -3, 17 + j * 5, 6, 4, WOOD_PLANK, t, a)
	if kind == "edge_window":
		_fill(c, at, -3, -11, 6, 22, WOOD_DARK, t, a)
		_fill(c, at, -2, -9, 4, 18, GLASS, t, a)
		_fill(c, at, -2, -9, 1, 18, GLASS_EDGE, t, a)
		_fill(c, at, -2, -1, 4, 2, MULLION, t, a)
		_fill(c, at, 0, -7, 1, 3, GLASS_GLINT, t, a)
	elif kind == "edge_door":
		_fill(c, at, -4, -14, 8, 4, WOOD_CAP, t, a)
		_fill(c, at, -4, 10, 8, 4, WOOD_CAP, t, a)
		if open:
			_fill(c, at, -3, -10, 6, 20, DOORWAY, t, a)
			_fill(c, at, -1, -8, 2, 16, SPILL, Color.WHITE, a * 0.6)
			_fill(c, at, 4, -10, 13, 4, DOOR_LEAF, t, a)
			_fill(c, at, 4, -8, 13, 2, DOOR_GREEN, t, a)
			_fill(c, at, 15, -10, 2, 4, DOOR_KNOB, t, a)
		else:
			_fill(c, at, -3, -10, 6, 20, DOOR_PANEL, t, a)
			for y in [-4, 2, 8]:
				_fill(c, at, -3, y, 6, 1, WOOD_DARK, t, a)
			_fill(c, at, 1, 5, 2, 2, DOOR_KNOB, t, a)
	_fill(c, at, -4, -16, 8, 1, WOOD_HI, t, a)
	_fill(c, at, -4, 30, 8, 2, BASE_SHADOW, t, a)
