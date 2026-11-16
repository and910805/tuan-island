extends RefCounted

# Display-only Tianwei nursery scene props. Standalone: no World preload, no
# registration, no gameplay IDs (the integrator maps these art IDs).
# flower-props.png is a built-in image_gen original copied byte-for-byte; it is a
# high-resolution source with soft alpha, NOT hand-placed native pixel art.
# Every texture handed out is rebuilt in memory with nearest sampling (same
# Image.get_region + INTERPOLATE_NEAREST pipeline as flower_art.gd/bakery_art.gd)
# and cached per ID.
const PROPS_PATH := "res://assets/flowers/flower-props.png"
const MARKET_PATH := "res://assets/flowers/flower-market.png"
const MARKET_SIZE := Vector2i(64,64)

# flower-props.png: 1254x1254, nominal 2x2 sheet (627px cells), but the objects
# are NOT on the equal-cell grid: the shuttle shelter starts at x606, left of the
# x627 cell line. Measured alpha (>8) bounds, absolute source px:
#   seed_saving_table        x43..591  y60..572   (feet y572)
#   dye_table                x635..1221 y63..571  (feet y571)
#   community_flower_trellis x51..562  y633..1197 (feet y1197)
#   nursery_shuttle_shelter  x606..1223 y645..1199 (feet y1199)
# Real gutters: top row x592..634, bottom row x563..605, rows y572..632.
# So each prop gets its own quadrant CLIP split at those gutters (x599, y602)
# and its own WINDOW (may overhang the clip/canvas; overhang is transparent).
# Windows keep the native aspect exactly (window = native * scale), are
# horizontally centred on the measured bounds and bottom-anchored 2-4 source px
# under the measured feet.
#
# Native sizes vs the proposal: tables 64x48 was rejected - at 1:1 aspect the
# tables (~1.07-1.15 w/h) would need squashing or a 51x48 squat sprite. Both
# tables share one scale (9.5 src px/native px) and are 64x56. Trellis 64x64
# (scale 9.0) and shelter 80x80 (scale 8.0) keep the proposed footprints.
const SOURCE_SIZE := Vector2i(1254, 1254)
const SPLIT := Vector2i(599, 602)
const PROPS := {
	"seed_saving_table": {
		"clip": Rect2i(0, 0, 599, 602),
		"window": Rect2i(13, 43, 608, 532),
		"size": Vector2i(64, 56),
	},
	"dye_table": {
		"clip": Rect2i(599, 0, 655, 602),
		"window": Rect2i(624, 43, 608, 532),
		"size": Vector2i(64, 56),
	},
	"community_flower_trellis": {
		"clip": Rect2i(0, 602, 599, 652),
		"window": Rect2i(18, 624, 576, 576),
		"size": Vector2i(64, 64),
	},
	"nursery_shuttle_shelter": {
		"clip": Rect2i(599, 602, 655, 652),
		"window": Rect2i(595, 562, 640, 640),
		"size": Vector2i(80, 80),
	},
}
const IDS := ["seed_saving_table", "dye_table", "community_flower_trellis", "nursery_shuttle_shelter"]

static var cache: Dictionary = {}

static func has_prop(id: String) -> bool:
	return PROPS.has(id)

static func prop_size(id: String) -> Vector2i:
	if not has_prop(id):
		return Vector2i.ZERO
	return PROPS[id]["size"]

# Native-pixel anchor for placement: bottom centre of the canvas (feet sit on
# the last 1-2 rows). Vector2i(-1, -1) for unknown IDs.
static func prop_anchor(id: String) -> Vector2i:
	if not has_prop(id):
		return Vector2i(-1, -1)
	var size: Vector2i = PROPS[id]["size"]
	return Vector2i(size.x / 2, size.y)

static func source_image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		if image.decompress() != OK:
			return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

# Window pixels inside the prop's clip, everything else transparent; then a
# nearest resize to the native size. Pure Godot Image ops, nothing saved.
static func windowed(image: Image, clip: Rect2i, window: Rect2i) -> Image:
	var canvas := Image.create_empty(window.size.x, window.size.y, false, Image.FORMAT_RGBA8)
	var take := window.intersection(clip)
	if take.has_area():
		canvas.blit_rect(image, take, take.position - window.position)
	return canvas

# Returns null for unknown IDs; never falls back to another sprite.
static func prop_texture(id: String) -> Texture2D:
	if not has_prop(id):
		return null
	if cache.has(id):
		return cache[id]
	var image := source_image(PROPS_PATH)
	if image == null or image.get_size() != SOURCE_SIZE:
		return null
	var spec: Dictionary = PROPS[id]
	var size: Vector2i = spec["size"]
	var cell := windowed(image, spec["clip"], spec["window"])
	cell.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	var texture := ImageTexture.create_from_image(cell)
	texture.set_meta("source_png", PROPS_PATH)
	texture.set_meta("source_window", spec["window"])
	texture.set_meta("source_clip", spec["clip"])
	cache[id] = texture
	return texture

static func clear_cache() -> void:
	cache.clear()

# Equal source cells deliberately share the same transform/anchor. Completion
# adds flowers without recentering or stretching the stall structure.
static func market_texture(completed:bool=false) -> Texture2D:
	var id:="market_complete" if completed else "market_daily"
	if cache.has(id):return cache[id]
	var image:=source_image(MARKET_PATH)
	if image==null or image.get_size()!=Vector2i(1774,887):return null
	var region:=Rect2i(887 if completed else 0,0,887,887)
	var cell:=image.get_region(region)
	cell.resize(MARKET_SIZE.x,MARKET_SIZE.y,Image.INTERPOLATE_NEAREST)
	var texture:=ImageTexture.create_from_image(cell)
	texture.set_meta("source_png",MARKET_PATH)
	texture.set_meta("source_window",region)
	cache[id]=texture
	return texture

static func market_anchor() -> Vector2i:
	return Vector2i(32,64)
