extends RefCounted

# STAGED display-only adapter for the Tainan salt-pan props (static art only).
# Standalone: no World preload, no registration, no child nodes, no collision.
# NOT an automation implementation and NOT animated: the source is one static
# frame per prop; no animation frames are delivered yet.
#
# Source: built-in image_gen original work/salt/art-source/salt-props-source-v2.png
# (to be copied byte-for-byte to res://assets/salt/salt-props.png at integration).
# 1254x1254 RGBA, true 2x2 grid of 627px cells (gutters verified, no object
# crosses a cell line). Soft alpha haze (1..8) covers every cell; it is kept,
# not cleaned. Textures are rebuilt in memory (Image.get_region/blit +
# INTERPOLATE_NEAREST resize, same pipeline as flower_scene_art.gd) and cached.
#
# Art ID -> source cell (mapping contract for the integrator; gameplay IDs are
# NOT defined here):
#   gate_broken    top-left     (0,0)
#   gate_repaired  top-right    (627,0)
#   waterwheel     bottom-left  (0,627)    waterwheel pump
#   salt_collector bottom-right (627,627)  salt rake collector workstation
#
# Measured alpha (>8) bounds, absolute source px (see staged-art/result.json):
#   gate_broken    x56..569   y126..470   (feet y470; 156px transparent below)
#   gate_repaired  x683..1197 y126..470   (= broken +627 x, +-1px)
#   waterwheel     x72..563   y690..1190  (feet y1190)
#   salt_collector x638..1212 y703..1190  (feet y1190)
#
# Placement rule (no per-state autocrop => no jitter):
# * ONE scale for all four props (9 source px per native px, window 576x576 ->
#   64x64) so their relative physical size from the source is preserved.
# * Every window is bottom-anchored on that prop's measured visible feet
#   (window bottom = feet + 1 + FEET_PAD), NOT on the raw canvas bottom, so the
#   gates (which sit in the upper part of their cells) land on the same native
#   foot row as the bottom-row machines.
# * gate_broken and gate_repaired use the IDENTICAL cell-relative window and
#   clip (window derived from the union of both states' bounds), so swapping
#   state never moves posts, crossbeam or handwheel.
# * Windows are horizontally centred on the visible bounds.
const DEFAULT_SOURCE_PATH := "res://assets/salt/salt-props.png"
const SOURCE_SIZE := Vector2i(1254, 1254)
const CELL := 627
const NATIVE_SIZE := Vector2i(64, 64)
const SCALE := 9
const WINDOW_SIZE := Vector2i(576, 576) # NATIVE_SIZE * SCALE, aspect kept exactly
const FEET_PAD := 2 # source px under the feet (< half a native px)
const ALPHA_VISIBLE := 8

# Cell-relative measured visible bounds (alpha > 8). Gate entry is the union of
# both gate states; the tests re-measure these from the PNG.
const IDS := ["gate_broken", "gate_repaired", "waterwheel", "salt_collector"]
const CELL_ORIGIN := {
	"gate_broken": Vector2i(0, 0),
	"gate_repaired": Vector2i(627, 0),
	"waterwheel": Vector2i(0, 627),
	"salt_collector": Vector2i(627, 627),
}
const VISIBLE_REL := {
	"gate_broken": Rect2i(56, 126, 515, 345),     # x56..570 y126..470 (union)
	"gate_repaired": Rect2i(56, 126, 515, 345),
	"waterwheel": Rect2i(72, 63, 492, 501),       # x72..563 y63..563
	"salt_collector": Rect2i(11, 76, 575, 488),   # x11..585 y76..563
}

# Native foot anchor: the draw point inside the 64x64 texture that sits on the
# world ground position. y=64 is the bottom edge (visible feet occupy row 63
# for every prop); x=32 is the visible centre. Identical for all four, so equal
# visual feet align when drawn at the same ground y.
const FOOT_ANCHOR := Vector2i(32, 64)

# Footprint RECOMMENDATION only (32px world tiles). This adapter never touches
# collision; the integrator decides. base_px = visible (alpha>8) width of the
# lowest 3 native rows (ground contact) measured from the textures; gate
# states share the union so they share one footprint. Verified by tests.
const FOOTPRINT := {
	"gate_broken": {"tiles": Vector2i(2, 1), "base_px": 57, "note": "sluice gate across a 2-tile channel; base = union of both gate states (broken 57, repaired 56)"},
	"gate_repaired": {"tiles": Vector2i(2, 1), "base_px": 57, "note": "same footprint/origin as gate_broken"},
	"waterwheel": {"tiles": Vector2i(2, 1), "base_px": 41, "note": "wheel+trough base; upper wheel is wider than the ground contact"},
	"salt_collector": {"tiles": Vector2i(2, 1), "base_px": 56, "note": "rake arm overhangs to the full 64px canvas width above the base"},
}

static var source_path: String = DEFAULT_SOURCE_PATH
static var cache: Dictionary = {}

static func has_prop(id: String) -> bool:
	return CELL_ORIGIN.has(id)

# Stage testing hook: point at an absolute PNG or another res:// path. Clears
# the cache so a stale texture from a previous path is never returned.
static func set_source_path(path: String) -> void:
	if path == source_path:
		return
	source_path = path
	cache.clear()

static func clear_cache() -> void:
	cache.clear()

static func prop_size(id: String) -> Vector2i:
	return NATIVE_SIZE if has_prop(id) else Vector2i.ZERO

static func foot_anchor(id: String) -> Vector2i:
	return FOOT_ANCHOR if has_prop(id) else Vector2i(-1, -1)

# Rect to pass to draw_texture_rect for a world ground point (feet).
static func draw_rect_for(id: String, ground: Vector2) -> Rect2:
	if not has_prop(id):
		return Rect2()
	return Rect2(ground.round() - Vector2(FOOT_ANCHOR), Vector2(NATIVE_SIZE))

static func footprint_recommendation(id: String) -> Dictionary:
	if not has_prop(id):
		return {}
	return FOOTPRINT[id].duplicate()

static func cell_clip(id: String) -> Rect2i:
	if not has_prop(id):
		return Rect2i()
	return Rect2i(CELL_ORIGIN[id], Vector2i(CELL, CELL))

# Absolute source window. May overhang the cell/canvas; overhang is transparent
# (clipped to the prop's own cell, so neighbours never leak in).
static func source_window(id: String) -> Rect2i:
	if not has_prop(id):
		return Rect2i()
	var vis: Rect2i = VISIBLE_REL[id]
	var centre_x := vis.position.x + vis.size.x / 2
	var bottom := vis.end.y + FEET_PAD # vis.end.y = feet + 1
	var rel := Rect2i(centre_x - WINDOW_SIZE.x / 2, bottom - WINDOW_SIZE.y, WINDOW_SIZE.x, WINDOW_SIZE.y)
	return Rect2i(rel.position + CELL_ORIGIN[id], rel.size)

static func source_image(path: String = source_path) -> Image:
	var image: Image = null
	if path.begins_with("res://") or path.begins_with("user://"):
		if not ResourceLoader.exists(path):
			return null
		var texture := load(path) as Texture2D
		if texture == null:
			return null
		image = texture.get_image()
	else:
		if not FileAccess.file_exists(path):
			return null
		image = Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	if image.is_compressed() and image.decompress() != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func windowed(image: Image, clip: Rect2i, window: Rect2i) -> Image:
	var canvas := Image.create_empty(window.size.x, window.size.y, false, Image.FORMAT_RGBA8)
	var take := window.intersection(clip).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if take.has_area():
		canvas.blit_rect(image, take, take.position - window.position)
	return canvas

# Nearest 64x64 texture, or null for unknown IDs / missing or wrong-size
# source. Never falls back to another sprite or a procedural drawing.
static func prop_texture(id: String) -> Texture2D:
	if not has_prop(id):
		return null
	if cache.has(id):
		return cache[id]
	var image := source_image(source_path)
	if image == null or image.get_size() != SOURCE_SIZE:
		return null
	var window := source_window(id)
	var cell := windowed(image, cell_clip(id), window)
	cell.resize(NATIVE_SIZE.x, NATIVE_SIZE.y, Image.INTERPOLATE_NEAREST)
	var texture := ImageTexture.create_from_image(cell)
	texture.set_meta("source_png", source_path)
	texture.set_meta("source_window", window)
	texture.set_meta("source_clip", cell_clip(id))
	texture.set_meta("art_id", id)
	cache[id] = texture
	return texture

# Convenience for canvases; returns false when the texture is unavailable so
# callers can keep their existing fallback.
static func draw_prop(canvas: CanvasItem, id: String, ground: Vector2) -> bool:
	var texture := prop_texture(id)
	if texture == null:
		return false
	canvas.draw_texture_rect(texture, draw_rect_for(id, ground), false)
	return true
