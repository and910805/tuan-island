extends RefCounted

# Display-only art for the flower-nursery resident A-Lei (fictional adult farmer).
# Standalone: no World preload, no registration, no child nodes.
# flower-resident.png is a built-in image_gen original copied byte-for-byte from
# work/flowers/art-source/flower-resident-source.png. Textures are rebuilt in
# memory with Image.get_region + INTERPOLATE_NEAREST resize and cached (same
# pipeline as flower_art.gd). Soft source alpha is kept as-is, not thresholded.
const SOURCE_PATH := "res://assets/flowers/flower-resident.png"

# 1774x887: two equal 887x887 panels, left = full body, right = portrait.
# Measured alpha (>8) bounds, absolute source px:
#   full body x 264..645, y 51..853 (382x803, feet at y853)
#   portrait  x 958..1669, y 64..845 (712x782)
# Faint haze (alpha 1-8) spreads across each panel; it is retained, not cleaned.
const SOURCE_SIZE := Vector2i(1774, 887)
const PANEL := Vector2i(887, 887)
const RESIDENT_ALPHA_BOUNDS := Rect2i(264, 51, 382, 803)
const PORTRAIT_ALPHA_BOUNDS := Rect2i(958, 64, 712, 782)

# Windows keep the native aspect exactly (no stretching the square panel into a
# tall sprite): 560x840 = 32x48 * 17.5, 832x832 = 64x64 * 13.
# Resident: centred on the body, bottom edge 2px under the feet so the boots land
# on the last native row (feet anchor = bottom centre, like tea_resident_art.gd).
# Portrait: centred on the bust, ~3 rows clear above the hat and ~1 below.
const RESIDENT_REGION := Rect2i(175, 16, 560, 840)
const PORTRAIT_REGION := Rect2i(898, 27, 832, 832)
const RESIDENT_SIZE := Vector2i(32, 48)
const PORTRAIT_SIZE := Vector2i(64, 64)
# Draw point inside the 32x48 texture that should sit on the world feet position.
const RESIDENT_FEET := Vector2i(16, 48)

static var cache: Dictionary = {}

static func source_image() -> Image:
	if not ResourceLoader.exists(SOURCE_PATH):
		return null
	var texture := load(SOURCE_PATH) as Texture2D
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

static func native(key: String, region: Rect2i, size: Vector2i) -> Texture2D:
	if cache.has(key):
		return cache[key]
	var image := source_image()
	if image == null:
		return null
	if not Rect2i(Vector2i.ZERO, image.get_size()).encloses(region):
		return null
	var cell := image.get_region(region)
	cell.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	var texture := ImageTexture.create_from_image(cell)
	texture.set_meta("source_png", SOURCE_PATH)
	texture.set_meta("source_region", region)
	cache[key] = texture
	return texture

# 32x48 full-body sprite; feet at RESIDENT_FEET (bottom centre).
static func resident_texture() -> Texture2D:
	return native("resident", RESIDENT_REGION, RESIDENT_SIZE)

# 64x64 dialogue portrait of the same character.
static func portrait_texture() -> Texture2D:
	return native("portrait", PORTRAIT_REGION, PORTRAIT_SIZE)

static func clear_cache() -> void:
	cache.clear()
