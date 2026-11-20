extends Control

# N05-2 阿潮的渡口local航線圖 - compact procedural pixel nautical chart.
# Display only: no storage, no actions, no signals, no child nodes, ignores the mouse.
# The root (modal / life UI) owns every button and interaction.
#
# A schematic of the home region (風鈴渡口): the three ROUTE_SIGNS points are placed at
# their real World.achao_route_cell(site) cells, on the real home terrain
# (World.REGIONS.water / SIZE and the 河岸釣魚會 pond). Cell proportions are kept, so
# relative positions are true, but the chart is NOT a route: it draws no paths, no
# lines between points, and no travel or teleport affordance.
#
# Point shapes: board = square, ferry = diamond, river = pennant.
#   recorded   = filled gold with a check mark   (snapshot.own_achao_route_marks bit)
#   unrecorded = hollow outline
#   active     = ring around the point chosen by select_site(); a short (~0.6 s),
#                non-looping pulse, or a plain static ring when reduced motion is on.
#
# API:
#   static make(snapshot: Dictionary, reduced: bool) -> Control
#   select_site(site: String) -> void     ("" or an unknown key clears the highlight)
#   sync(snapshot: Dictionary) -> void    (refresh recorded marks)

const World = preload("res://scripts/world.gd")
const Goals = preload("res://scripts/resident_goals.gd")

const MIN_SIZE := Vector2(260, 180)
const ANIM_SECONDS := 0.6
const CAPTION_H := 19
const FONT_SIZE := 14
const ORDER: Array = ["board", "ferry", "river"]

# Window around the points, in cells (left, top, right, bottom margins).
const MARGIN := Rect2i(7, 5, 8, 6)

const C_FRAME := Color("2a3a3f")
const C_PAPER := Color("e6dcbc")
const C_INK := Color("23323a")
const C_WATER_A := Color("4f86a6")
const C_WATER_B := Color("5a92b0")
const C_WATER_LINE := Color("86b9cf")
const C_LAND_A := Color("a9b27a")
const C_LAND_B := Color("9fa971")
const C_SHORE := Color("7a5a3a")
const C_SHORE_LIGHT := Color("9a7650")
const C_COMPASS := Color("2b3b44")
const C_MARK_DONE := Color("e8b94a")
const C_MARK_OPEN := Color("f4efdc")
const C_ACTIVE := Color("fff2b0")
const C_LABEL_BG := Color(0.93, 0.89, 0.74, 0.92)

var _reduced := false
var _marks := 0
var _site := ""
var _anim_t := 1.0
var _sites: Dictionary = {}   # key -> Vector2i cell (only valid ones)
var _window := Rect2i()


static func make(snapshot: Dictionary, reduced: bool) -> Control:
	var chart := new()
	chart._reduced = reduced
	chart.sync(snapshot)
	return chart


func _init() -> void:
	custom_minimum_size = MIN_SIZE
	size = MIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(false)
	_load_sites()


func sync(snapshot: Dictionary) -> void:
	var marks := int(snapshot.get("own_achao_route_marks", 0)) & int(Goals.ROUTE_MASK)
	if marks == _marks:
		return
	_marks = marks
	_update_tooltip()
	queue_redraw()


func select_site(site: String) -> void:
	var next := site if _sites.has(site) else ""
	if next == _site:
		return
	_site = next
	_anim_t = 1.0
	set_process(false)
	if next != "" and not _reduced:
		_anim_t = 0.0
		set_process(true)
	_update_tooltip()
	queue_redraw()


func selected_site() -> String:
	return _site


func is_recorded(site: String) -> bool:
	if not Goals.ROUTE_SIGNS.has(site):
		return false
	return (_marks & int(Goals.ROUTE_SIGNS[site].bit)) != 0


func is_animating() -> bool:
	return _anim_t < 1.0


func _process(delta: float) -> void:
	_anim_t = minf(_anim_t + delta / ANIM_SECONDS, 1.0)
	if _anim_t >= 1.0:
		set_process(false)
	queue_redraw()


# ---------------------------------------------------------------- layout

func _load_sites() -> void:
	_sites.clear()
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for site: String in ORDER:
		if not Goals.ROUTE_SIGNS.has(site):
			continue
		var cell: Vector2i = World.achao_route_cell(site)
		if cell.x < 0 or cell.y < 0:
			continue
		_sites[site] = cell
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	if _sites.is_empty():
		_window = Rect2i(0, 0, 1, 1)
		return
	var top_left := lo - MARGIN.position
	var bottom_right := hi + Vector2i.ONE + MARGIN.size
	top_left = Vector2i(maxi(top_left.x, 0), maxi(top_left.y, 0))
	bottom_right = Vector2i(mini(bottom_right.x, World.REGIONS.SIZE.x), mini(bottom_right.y, World.REGIONS.SIZE.y))
	_window = Rect2i(top_left, bottom_right - top_left)


func _is_water(cell: Vector2i) -> bool:
	return World.REGIONS.water(cell, World.REGIONS.HOME) or World.FISH_MEET.WATERS.has_point(cell)


## Integer pixels per cell and the map's pixel origin.
func _geometry() -> Dictionary:
	var avail := Vector2(size.x - 8.0, size.y - 8.0 - CAPTION_H)
	var cs := maxi(1, int(floorf(minf(avail.x / _window.size.x, avail.y / _window.size.y))))
	var map_size := Vector2i(_window.size.x * cs, _window.size.y * cs)
	var origin := Vector2i(int((size.x - map_size.x) * 0.5), 4 + int((avail.y - map_size.y) * 0.5))
	return {"cs": cs, "origin": origin, "map": Rect2i(origin, map_size)}


func _cell_rect(cell: Vector2i, g: Dictionary) -> Rect2i:
	var cs: int = g.cs
	var o: Vector2i = g.origin
	return Rect2i(o.x + (cell.x - _window.position.x) * cs, o.y + (cell.y - _window.position.y) * cs, cs, cs)


func _center(cell: Vector2i, g: Dictionary) -> Vector2i:
	var r := _cell_rect(cell, g)
	return r.position + r.size / 2


# ---------------------------------------------------------------- drawing

func _r(rect: Rect2i, c: Color) -> void:
	draw_rect(Rect2(rect), c)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_FRAME)
	if _sites.is_empty():
		return
	var g := _geometry()
	var map: Rect2i = g.map
	draw_rect(Rect2(map.grow(2)), C_PAPER)
	_draw_terrain(g)
	_draw_compass(map)
	for site: String in ORDER:
		if _sites.has(site):
			_draw_label(site, g)
	for site: String in ORDER:
		if _sites.has(site):
			_draw_point(site, g)
	_draw_caption(map)


func _draw_terrain(g: Dictionary) -> void:
	var cs: int = g.cs
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var edge := maxi(1, cs / 4)
	for y in range(_window.position.y, _window.end.y):
		for x in range(_window.position.x, _window.end.x):
			var cell := Vector2i(x, y)
			var rect := _cell_rect(cell, g)
			var checker := (x + y) % 2 == 0
			if _is_water(cell):
				_r(rect, C_WATER_A if checker else C_WATER_B)
				if (x * 3 + y * 5) % 7 == 0:
					_r(Rect2i(rect.position + Vector2i(cs / 4, cs / 2), Vector2i(maxi(1, cs / 2), 1)), C_WATER_LINE)
				continue
			_r(rect, C_LAND_A if checker else C_LAND_B)
			# thin wooden shore on the sides that face water
			for d in dirs:
				if not _is_water(cell + d):
					continue
				var strip := Rect2i()
				if d == Vector2i.UP:
					strip = Rect2i(rect.position, Vector2i(cs, edge))
				elif d == Vector2i.DOWN:
					strip = Rect2i(rect.position + Vector2i(0, cs - edge), Vector2i(cs, edge))
				elif d == Vector2i.LEFT:
					strip = Rect2i(rect.position, Vector2i(edge, cs))
				else:
					strip = Rect2i(rect.position + Vector2i(cs - edge, 0), Vector2i(edge, cs))
				_r(strip, C_SHORE)
				if edge > 1:
					_r(Rect2i(strip.position, Vector2i(strip.size.x if d.y != 0 else 1, strip.size.y if d.x != 0 else 1)), C_SHORE_LIGHT)


func _draw_compass(map: Rect2i) -> void:
	# Thin cross with a north tick, top-right. Screen up = north (map y grows southward).
	var c := Vector2(map.end.x - 16, map.position.y + 20)
	draw_rect(Rect2(c.x - 10, c.y - 10, 20, 20).grow(2), Color(C_PAPER, 0.7))
	draw_line(c + Vector2(0, -9), c + Vector2(0, 9), C_COMPASS, 1.0)
	draw_line(c + Vector2(-9, 0), c + Vector2(9, 0), C_COMPASS, 1.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(-3, -3), c + Vector2(3, -3)]), C_COMPASS)
	var f := get_theme_default_font()
	draw_string(f, c + Vector2(-3, -12), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_INK)


func _shape_rows(site: String, h: int) -> Array:
	# Returns [dy, x0, x1] spans relative to the center, for the filled shape.
	var rows: Array = []
	match site:
		"ferry":
			for dy in range(-h, h + 1):
				var w := h - absi(dy)
				rows.append([dy, -w, w])
		_:
			for dy in range(-h, h + 1):
				rows.append([dy, -h, h])
	return rows


func _draw_point(site: String, g: Dictionary) -> void:
	var cs: int = g.cs
	var c: Vector2i = _center(_sites[site], g)
	var h := maxi(3, int(round(cs * 0.6)))
	var done := is_recorded(site)
	if site == "river":
		# pole + pennant
		_r(Rect2i(c.x - h, c.y - h, 2, h * 2 + 1), C_INK)
		var flag_c := C_MARK_DONE if done else C_MARK_OPEN
		for dy in range(0, h + 1):
			var w := (h * 2 - dy * 2) if dy < h else 0
			if w > 0:
				_r(Rect2i(c.x - h + 2, c.y - h + dy, w + 1, 1), C_INK)
				if w > 2 and dy > 0:
					_r(Rect2i(c.x - h + 3, c.y - h + dy, w - 1, 1), flag_c)
	else:
		var rows := _shape_rows(site, h)
		for row in rows:
			_r(Rect2i(c.x + row[1] - 1, c.y + row[0], row[2] - row[1] + 3, 1), C_INK)
		for row in rows:
			if absi(row[0]) == h and site != "board":
				continue
			var inner := Rect2i(c.x + row[1], c.y + row[0], row[2] - row[1] + 1, 1)
			if site == "board" and absi(row[0]) == h:
				inner = Rect2i(c.x + row[1] + 1, c.y + row[0], row[2] - row[1] - 1, 1)
			_r(inner, C_MARK_DONE if done else Color(C_PAPER, 0.0))
		if site == "board":
			_r(Rect2i(c.x - h + 1, c.y - h + 1, h * 2 - 1, h * 2 - 1), C_MARK_DONE if done else C_MARK_OPEN)
		elif not done:
			for row in rows:
				if absi(row[0]) < h and row[2] - row[1] >= 2:
					_r(Rect2i(c.x + row[1] + 1, c.y + row[0], row[2] - row[1] - 1, 1), C_MARK_OPEN)
	if done:
		var k := maxi(1, h / 3)
		draw_polyline(PackedVector2Array([Vector2(c.x - k - 1, c.y), Vector2(c.x - 1, c.y + k + 1), Vector2(c.x + k + 2, c.y - k)]), C_INK, 2.0)
	if site == _site:
		_draw_ring(c, h)


func _draw_ring(c: Vector2i, h: int) -> void:
	var grow := 3
	var alpha := 1.0
	if is_animating():
		var t := clampf(_anim_t, 0.0, 1.0)
		grow = 3 + int(round(3.0 * sin(t * PI)))   # out and back, once
		alpha = 0.6 + 0.4 * t
	var r := Rect2i(c.x - h - grow, c.y - h - grow, (h + grow) * 2 + 1, (h + grow) * 2 + 1)
	var col := Color(C_ACTIVE, alpha)
	_r(Rect2i(r.position, Vector2i(r.size.x, 2)), C_INK)
	_r(Rect2i(r.position + Vector2i(0, r.size.y - 2), Vector2i(r.size.x, 2)), C_INK)
	_r(Rect2i(r.position, Vector2i(2, r.size.y)), C_INK)
	_r(Rect2i(r.position + Vector2i(r.size.x - 2, 0), Vector2i(2, r.size.y)), C_INK)
	var inner := r.grow(-1)
	draw_rect(Rect2(inner), col, false, 1.0)


func _draw_label(site: String, g: Dictionary) -> void:
	var f := get_theme_default_font()
	var map: Rect2i = g.map
	var cs: int = g.cs
	var c: Vector2i = _center(_sites[site], g)
	var text: String = str(Goals.ROUTE_SIGNS[site].name)
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var th := f.get_height(FONT_SIZE)
	var gap := int(cs * 0.6) + 6
	var pos := Vector2(c.x - tw * 0.5, 0)
	match site:
		"board":
			pos.y = c.y - gap - th          # above
		"ferry":
			pos.y = c.y + gap               # below
		_:
			pos = Vector2(c.x - gap - tw, c.y - th * 0.5)   # left of the pennant (pond lies right)
	pos.x = clampf(pos.x, map.position.x + 3, map.end.x - tw - 3)
	pos.y = clampf(pos.y, map.position.y + 2, map.end.y - th - 2)
	draw_rect(Rect2(pos - Vector2(3, 1), Vector2(tw + 6, th + 2)), C_LABEL_BG)
	var col := C_INK
	if site == _site:
		draw_rect(Rect2(pos - Vector2(3, 1), Vector2(tw + 6, th + 2)), C_INK, false, 1.0)
	draw_string(f, pos + Vector2(0, f.get_ascent(FONT_SIZE)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)


func _draw_caption(map: Rect2i) -> void:
	var f := get_theme_default_font()
	var count := 0
	for site: String in _sites:
		if is_recorded(site):
			count += 1
	var text := "渡口位置示意　已記 %d／%d" % [count, _sites.size()]
	var y := float(map.end.y + 3) + f.get_ascent(12)
	draw_string(f, Vector2(map.position.x, y), text, HORIZONTAL_ALIGNMENT_LEFT, map.size.x, 12, Color("cfd9d6"))


func _update_tooltip() -> void:
	var parts := PackedStringArray()
	for site: String in ORDER:
		if not _sites.has(site):
			continue
		parts.append("%s %s%s" % ["✓" if is_recorded(site) else "○", Goals.ROUTE_SIGNS[site].name, "（目前）" if site == _site else ""])
	tooltip_text = "\n".join(parts)
