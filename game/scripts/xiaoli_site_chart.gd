extends Control

# N09-2 小栗 site chart - compact pixel map of the home plaza and dock region.
# Display only: no storage, no signals, no child nodes, no text, ignores the mouse.
# The surrounding game UI owns every label and button (accessible fonts); the chart only
# shows WHERE the places are, and the pin numbers 1-3 match the insertion order of `sites`.
#
# The map is the real home terrain around the given cells: World.REGIONS.water(HOME) plus the
# 河岸釣魚會 pond (World.FISH_MEET.WATERS) for water, VillageLayout.path_at for the plaza and
# lanes. Cell proportions are kept (integer pixels per cell, rounded coordinates).
#
# API:
#   static make(sites: Dictionary, reduced: bool) -> Control
#       sites = { id: { "cell": Vector2i, "name": String, "hint": String }, ... }
#       Only the first three valid entries are pinned, numbered by insertion order.
#       Known prop ids: "tree", "dock", "plaza" (others get a pin without a prop).
#   select_site(id: String) -> void   ("" or an unknown id clears the selection)
#   selected_site() -> String

const World = preload("res://scripts/world.gd")
const Layout = preload("res://scripts/village_layout.gd")

const MIN_SIZE := Vector2(325, 150)
const MAX_PINS := 3
const ANIM_SECONDS := 0.5
const DOCKED_BOAT := Vector2(56.15, 33.55)   # same spot the world view moors the boat
const BORDER := 3

const C_FRAME := Color("3a2c22")
const C_PAPER := Color("efe3c2")
const C_INK := Color("2a2018")
const C_GRASS_A := Color("c9c98f")
const C_GRASS_B := Color("c0c186")
const C_TUFT := Color("a3a86a")
const C_PATH_A := Color("e3c98f")
const C_PATH_B := Color("dcc085")
const C_PATH_EDGE := Color("b8975e")
const C_PEBBLE := Color("f3e2b4")
const C_WATER_A := Color("5d97a6")
const C_WATER_B := Color("6aa3b0")
const C_WATER_LINE := Color("a4d0d4")
const C_SHORE := Color("f1e4b8")
const C_SHORE_EDGE := Color("8a6a46")
const C_WOOD := Color("a9783f")
const C_WOOD_DARK := Color("6e4a28")
const C_WOOD_LIGHT := Color("c79a5c")
const C_LEAF_DARK := Color("3f6e3a")
const C_LEAF := Color("5f9246")
const C_LEAF_LIGHT := Color("8cb85a")
const C_STONE := Color("cdbd9a")
const C_STONE_DARK := Color("9d8c6a")
const C_AWNING_A := Color("c4543e")
const C_AWNING_B := Color("f6ecd2")
const C_PIN := Color("f8f1da")
const C_PIN_ON := Color("f2bd3a")
const C_RING := Color("fff0a8")
const C_SHADOW := Color(0.16, 0.12, 0.08, 0.28)

# 3x5 pixel digits, rows top to bottom.
const DIGITS: Dictionary = {
	1: ["010", "110", "010", "010", "111"],
	2: ["111", "001", "111", "100", "111"],
	3: ["111", "001", "111", "001", "111"],
}

var _reduced := false
var _site := ""
var _anim_t := 1.0
var _ids: Array[String] = []          # pinned ids in insertion order (index + 1 = pin number)
var _cells: Dictionary = {}           # id -> Vector2i
var _window := Rect2i()
var _cs := 8
var _origin := Vector2i.ZERO
var _map := Rect2i()


static func make(sites: Dictionary, reduced: bool) -> Control:
	var chart := new()
	chart._reduced = reduced
	chart._load_sites(sites)
	return chart


func _init() -> void:
	custom_minimum_size = MIN_SIZE
	size = MIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	set_process(false)


func select_site(id: String) -> void:
	var next := id if _cells.has(id) else ""
	if next == _site:
		return
	_site = next
	_anim_t = 1.0
	set_process(false)
	if next != "" and not _reduced:
		_anim_t = 0.0
		set_process(true)
	queue_redraw()


func selected_site() -> String:
	return _site


func _process(delta: float) -> void:
	_anim_t = minf(_anim_t + delta / ANIM_SECONDS, 1.0)
	if _anim_t >= 1.0:
		set_process(false)
	queue_redraw()


func _on_resized() -> void:
	_layout()
	queue_redraw()


# ---------------------------------------------------------------- layout

func _load_sites(sites: Dictionary) -> void:
	_ids.clear()
	_cells.clear()
	var index := 0
	for key: Variant in sites:
		var number := index
		index += 1
		if number >= MAX_PINS:
			break
		var entry: Variant = sites[key]
		if not entry is Dictionary or not (entry as Dictionary).get("cell") is Vector2i:
			continue
		var cell: Vector2i = (entry as Dictionary).cell
		var id := str(key)
		_ids.append(id)
		_cells[id] = cell
	_layout()
	queue_redraw()


func _number(id: String) -> int:
	return int(_ids.find(id)) + 1


func _is_water(cell: Vector2i) -> bool:
	return World.REGIONS.water(cell, World.REGIONS.HOME) or World.FISH_MEET.WATERS.has_point(cell)


func _is_path(cell: Vector2i) -> bool:
	return Layout.path_at(Vector2(cell) + Vector2(0.5, 0.5))


## Integer pixels per cell; window is widened to fill the control and kept inside the region.
func _layout() -> void:
	_map = Rect2i(BORDER, BORDER, maxi(1, int(size.x) - BORDER * 2), maxi(1, int(size.y) - BORDER * 2))
	if _ids.is_empty():
		_window = Rect2i(0, 0, 1, 1)
		return
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for id in _ids:
		var c: Vector2i = _cells[id]
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	# Margin: 2 cells sideways, 3 above (pins stand over their cell), 2 below.
	var need := Vector2i(hi.x - lo.x + 1 + 4, hi.y - lo.y + 1 + 5)
	_cs = clampi(int(floorf(minf(float(_map.size.x) / need.x, float(_map.size.y) / need.y))), 1, 16)
	var cells := Vector2i(
		mini(_map.size.x / _cs, World.REGIONS.SIZE.x),
		mini(_map.size.y / _cs, World.REGIONS.SIZE.y))
	var center := Vector2i((lo.x + hi.x) / 2, (lo.y + hi.y) / 2 - 1)
	var top_left := center - cells / 2
	top_left.x = clampi(top_left.x, 0, World.REGIONS.SIZE.x - cells.x)
	top_left.y = clampi(top_left.y, 0, World.REGIONS.SIZE.y - cells.y)
	_window = Rect2i(top_left, cells)
	_origin = _map.position + (_map.size - cells * _cs) / 2


func _cell_rect(cell: Vector2i) -> Rect2i:
	return Rect2i(_origin + (cell - _window.position) * _cs, Vector2i(_cs, _cs))


## Pixel position of the cell's bottom-centre ("feet" of a prop standing on it).
func _foot(cell: Vector2i) -> Vector2i:
	var r := _cell_rect(cell)
	return Vector2i(r.position.x + _cs / 2, r.position.y + _cs)


func _noise(x: int, y: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663)) % 100


# ---------------------------------------------------------------- drawing

func _r(rect: Rect2i, c: Color) -> void:
	draw_rect(Rect2(rect), c)


func _disc(c: Vector2i, radius: int, color: Color) -> void:
	for dy in range(-radius, radius + 1):
		var w := int(floorf(sqrt(float(radius * radius - dy * dy) + 0.5)))
		_r(Rect2i(c.x - w, c.y + dy, w * 2 + 1, 1), color)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_FRAME)
	draw_rect(Rect2(_map).grow(1), C_PAPER)
	if _ids.is_empty():
		return
	_draw_terrain()
	_draw_boat()
	for id in _ids:
		_draw_prop(id)
	for id in _ids:
		if id != _site:
			_draw_pin(id, false)
	if _site != "":
		_draw_cell_frame(_cells[_site])
		_draw_pin(_site, true)
	# Paper frame lip drawn last to hide anything that bleeds past the map.
	var m := _map
	_r(Rect2i(0, 0, int(size.x), m.position.y), C_FRAME)
	_r(Rect2i(0, m.end.y, int(size.x), int(size.y) - m.end.y), C_FRAME)
	_r(Rect2i(0, 0, m.position.x, int(size.y)), C_FRAME)
	_r(Rect2i(m.end.x, 0, int(size.x) - m.end.x, int(size.y)), C_FRAME)
	draw_rect(Rect2(m).grow(1), C_INK, false, 1.0)


func _strip(rect: Rect2i, side: Vector2i, thick: int, color: Color) -> void:
	if side == Vector2i.UP:
		_r(Rect2i(rect.position, Vector2i(rect.size.x, thick)), color)
	elif side == Vector2i.DOWN:
		_r(Rect2i(rect.position + Vector2i(0, rect.size.y - thick), Vector2i(rect.size.x, thick)), color)
	elif side == Vector2i.LEFT:
		_r(Rect2i(rect.position, Vector2i(thick, rect.size.y)), color)
	else:
		_r(Rect2i(rect.position + Vector2i(rect.size.x - thick, 0), Vector2i(thick, rect.size.y)), color)


func _draw_terrain() -> void:
	var sides: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var thick := maxi(1, _cs / 5)
	for y in range(_window.position.y, _window.end.y):
		for x in range(_window.position.x, _window.end.x):
			var cell := Vector2i(x, y)
			var rect := _cell_rect(cell)
			var checker := (x + y) % 2 == 0
			if _is_water(cell):
				_r(rect, C_WATER_A if checker else C_WATER_B)
				if _noise(x, y) % 5 == 0:
					_r(Rect2i(rect.position + Vector2i(_cs / 4, _cs / 2), Vector2i(maxi(2, _cs / 2), 1)), C_WATER_LINE)
				continue
			var path := _is_path(cell)
			if path:
				_r(rect, C_PATH_A if checker else C_PATH_B)
				if _noise(x, y) % 4 == 0:
					_r(Rect2i(rect.position + Vector2i(_cs / 3, _cs / 3), Vector2i(maxi(1, _cs / 6), maxi(1, _cs / 6))), C_PEBBLE)
			else:
				_r(rect, C_GRASS_A if checker else C_GRASS_B)
				var n := _noise(x, y)
				if n % 6 == 0 and _cs >= 5:
					var p := rect.position + Vector2i(_cs / 4 + n % 3, _cs / 2)
					_r(Rect2i(p, Vector2i(1, maxi(2, _cs / 4))), C_TUFT)
					_r(Rect2i(p + Vector2i(2, 1), Vector2i(1, maxi(2, _cs / 4))), C_TUFT)
			for d in sides:
				var next := cell + d
				if _is_water(next):
					_strip(rect, d, thick, C_SHORE)
				elif path and not _is_path(next):
					_strip(rect, d, 1, C_PATH_EDGE)


func _draw_cell_frame(cell: Vector2i) -> void:
	var r := _cell_rect(cell).grow(2)
	draw_rect(Rect2(r), C_INK, false, 3.0)
	draw_rect(Rect2(r), C_RING, false, 1.0)


# ---------------------------------------------------------------- props

func _draw_boat() -> void:
	var cell := Vector2i(int(floorf(DOCKED_BOAT.x)), int(floorf(DOCKED_BOAT.y)))
	if not _window.has_point(cell):
		return
	var base := _cell_rect(cell)
	var p := base.position + Vector2i(int(round(fract(DOCKED_BOAT.x) * _cs)), int(round(fract(DOCKED_BOAT.y) * _cs)))
	var w := maxi(10, _cs + 4)
	_r(Rect2i(p.x - w / 2 - 1, p.y - 3, w + 2, 7), C_INK)
	_r(Rect2i(p.x - w / 2, p.y - 2, w, 5), C_WOOD)
	_r(Rect2i(p.x - w / 2, p.y - 2, w, 1), C_WOOD_LIGHT)
	_r(Rect2i(p.x - w / 2 + 2, p.y, w - 4, 2), C_WOOD_DARK)


func fract(v: float) -> float:
	return v - floorf(v)


func _draw_prop(id: String) -> void:
	var cell: Vector2i = _cells[id]
	if not _window.has_point(cell):
		return
	match id:
		"tree":
			_draw_tree(_foot(cell))
		"dock":
			_draw_dock(cell)
		"plaza":
			_draw_plaza(cell)


func _draw_tree(foot: Vector2i) -> void:
	_r(Rect2i(foot.x - 7, foot.y - 2, 14, 4), C_SHADOW)
	_r(Rect2i(foot.x - 2, foot.y - 8, 4, 9), C_INK)
	_r(Rect2i(foot.x - 1, foot.y - 8, 2, 8), C_WOOD)
	var top := Vector2i(foot.x, foot.y - 15)
	_disc(top, 9, C_INK)
	_disc(top, 8, C_LEAF_DARK)
	_disc(top + Vector2i(-1, -1), 6, C_LEAF)
	_disc(top + Vector2i(-3, -3), 3, C_LEAF_LIGHT)


func _draw_dock(cell: Vector2i) -> void:
	# Plank pier running out over the water from the dock cell.
	var r := _cell_rect(cell)
	var pier_len := maxi(_cs * 3, 24)
	var h := maxi(7, _cs - 2)
	var pier := Rect2i(r.position.x + _cs / 2 - 2, r.position.y + (_cs - h) / 2, pier_len, h)
	_r(pier.grow(1), C_INK)
	_r(pier, C_WOOD)
	var x := pier.position.x + 3
	while x < pier.end.x:
		_r(Rect2i(x, pier.position.y, 1, pier.size.y), C_WOOD_DARK)
		x += 4
	_r(Rect2i(pier.position, Vector2i(pier.size.x, 1)), C_WOOD_LIGHT)
	for px in [pier.position.x + 1, pier.end.x - 3]:
		_r(Rect2i(px, pier.end.y, 2, 3), C_WOOD_DARK)
	# Little lamp post at the root of the pier.
	_r(Rect2i(pier.position.x + 1, pier.position.y - 6, 2, 6), C_INK)
	_r(Rect2i(pier.position.x - 1, pier.position.y - 9, 6, 4), C_INK)
	_r(Rect2i(pier.position.x, pier.position.y - 8, 4, 2), C_RING)


func _draw_plaza(cell: Vector2i) -> void:
	var c := _cell_rect(cell).position + Vector2i(_cs / 2, _cs / 2)
	# Paved ring with a centre stone.
	var ry := maxi(4, int(round(_cs * 0.9)))
	var rx := ry * 2
	for dy in range(-ry, ry + 1):
		var w := int(round(rx * sqrt(maxf(0.0, 1.0 - float(dy * dy) / float(ry * ry)))))
		_r(Rect2i(c.x - w - 1, c.y + dy, w * 2 + 3, 1), C_STONE_DARK)
	for dy in range(-ry + 1, ry):
		var w := int(round((rx - 1) * sqrt(maxf(0.0, 1.0 - float(dy * dy) / float((ry - 1) * (ry - 1))))))
		_r(Rect2i(c.x - w, c.y + dy, w * 2 + 1, 1), C_STONE)
	_r(Rect2i(c.x - 3, c.y - 1, 7, 3), C_STONE_DARK)
	# Striped market awning at the back of the square.
	var a := Vector2i(c.x - 9, c.y - ry - 8)
	_r(Rect2i(a.x - 1, a.y - 1, 20, 9), C_INK)
	for i in 6:
		_r(Rect2i(a.x + i * 3, a.y, 3, 4), C_AWNING_A if i % 2 == 0 else C_AWNING_B)
	_r(Rect2i(a.x, a.y + 4, 18, 3), C_WOOD)


# ---------------------------------------------------------------- pins

func _draw_pin(id: String, active: bool) -> void:
	var cell: Vector2i = _cells[id]
	if not _window.has_point(cell):
		return
	var tip := _foot(cell) - Vector2i(0, _cs / 2)
	var radius := 11 if active else 9
	var lift := radius + 8
	var pulse := 0
	if active and is_animating():
		pulse = int(round(3.0 * sin(clampf(_anim_t, 0.0, 1.0) * PI)))
		radius += pulse
	var head := Vector2i(tip.x, tip.y - lift)
	head.x = clampi(head.x, _map.position.x + radius + 3, _map.end.x - radius - 3)
	head.y = clampi(head.y, _map.position.y + radius + 3, _map.end.y - radius - 3)
	var fill := C_PIN_ON if active else C_PIN
	# ground shadow + needle
	_r(Rect2i(tip.x - 4, tip.y - 1, 9, 3), C_SHADOW)
	var needle_top := head.y + radius - 3
	var tip_y := maxi(tip.y, needle_top + 3)
	for y in range(needle_top, tip_y + 1):
		var t := float(y - needle_top) / float(maxi(1, tip_y - needle_top))
		var half := int(round(lerpf(5.0, 0.0, t)))
		_r(Rect2i(head.x - half - 1, y, half * 2 + 3, 1), C_INK)
	for y in range(needle_top, tip_y):
		var t2 := float(y - needle_top) / float(maxi(1, tip_y - needle_top))
		var half2 := int(round(lerpf(5.0, 0.0, t2)))
		_r(Rect2i(head.x - half2, y, half2 * 2 + 1, 1), fill)
	# head
	if active:
		_disc(head, radius + 3, C_INK)
		_disc(head, radius + 2, C_RING)
	_disc(head, radius + 1, C_INK)
	_disc(head, radius, fill)
	_draw_digit(_number(id), head)


func _draw_digit(n: int, center: Vector2i) -> void:
	if not DIGITS.has(n):
		return
	var rows: Array = DIGITS[n]
	var s := 2
	var origin := Vector2i(center.x - (3 * s) / 2, center.y - (5 * s) / 2)
	for ry in 5:
		var row: String = rows[ry]
		for rx in 3:
			if row[rx] == "1":
				_r(Rect2i(origin.x + rx * s, origin.y + ry * s, s, s), C_INK)


func is_animating() -> bool:
	return _anim_t < 1.0
