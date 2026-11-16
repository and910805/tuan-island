extends RefCounted

# Display-only flower art. Standalone: no World preload, no registration.
# Source PNGs are built-in image_gen originals copied byte-for-byte; every texture
# handed out is rebuilt in memory at 32x32 with nearest sampling (same pipeline
# as bakery_art.gd) and cached per key.
const GROWTH_PATH := "res://assets/flowers/flower-growth.png"
const ITEMS_PATH := "res://assets/flowers/flower-items.png"
const ICON_SIZE := Vector2i(32, 32)

# flower-growth.png: 1448x1086, 4 columns (stages) x 3 rows (crops), 362px cells.
# Measured alpha (>16) bounds: every sprite stays inside its own cell with clear
# gutters; union of local bounds is x 12..310, y 36..325, and every sprite in a row
# shares one base line (row0 y325, row1 y318, row2 y312-313). One shared square
# window per cell keeps scale and foot anchor identical across all 12 stages.
const GROWTH_SOURCE_SIZE := Vector2i(1448, 1086)
const GROWTH_CELL := Vector2i(362, 362)
const GROWTH_WINDOW := Rect2i(9, 24, 304, 304)
const CROPS := ["bluebell", "orange_blossom", "chime_herb"]
const STAGES := ["sprout", "juvenile", "bud", "mature"]
const STAGE_COUNT := 4
const MATURE := 3

# flower-items.png: 1278x1230, 3x3 grid of 426x410 cells. Union of local alpha
# bounds is x 18..397, y 11..384; the 392px window below encloses all of it.
const ITEMS_SOURCE_SIZE := Vector2i(1278, 1230)
const ITEM_CELL := Vector2i(426, 410)
const ITEM_WINDOW := Rect2i(12, 2, 392, 392)
const ITEMS := {
	"bluebell": Vector2i(0, 0),
	"orange_blossom": Vector2i(1, 0),
	"chime_herb": Vector2i(2, 0),
	"bluebell_seed": Vector2i(0, 1),
	"orange_blossom_seed": Vector2i(1, 1),
	"chime_herb_seed": Vector2i(2, 1),
	"blue_dye": Vector2i(0, 2),
	"sugar": Vector2i(1, 2),
	"garden_cookie": Vector2i(2, 2),
}
# Optional alternate names -> canonical ID above. Empty until the implementation
# contract names something differently; canonical IDs are never renamed.
const ALIASES := {}

static var cache: Dictionary = {}

static func canonical(id: String) -> String:
	return String(ALIASES.get(id, id))

static func has_item(id: String) -> bool:
	return ITEMS.has(canonical(id))

static func has_crop(id: String) -> bool:
	return CROPS.has(canonical(id))

static func valid_stage(stage: int) -> bool:
	return stage >= 0 and stage < STAGE_COUNT

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

static func native(key: String, path: String, region: Rect2i, size: Vector2i) -> Texture2D:
	if cache.has(key):
		return cache[key]
	var image := source_image(path)
	if image == null:
		return null
	if not Rect2i(Vector2i.ZERO, image.get_size()).encloses(region):
		return null
	var cell := image.get_region(region)
	cell.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	var texture := ImageTexture.create_from_image(cell)
	texture.set_meta("source_png", path)
	texture.set_meta("source_region", region)
	cache[key] = texture
	return texture

static func item_region(id: String) -> Rect2i:
	var at: Vector2i = ITEMS[canonical(id)]
	return Rect2i(at * ITEM_CELL + ITEM_WINDOW.position, ITEM_WINDOW.size)

static func crop_region(id: String, stage: int) -> Rect2i:
	var row := CROPS.find(canonical(id))
	return Rect2i(Vector2i(stage, row) * GROWTH_CELL + GROWTH_WINDOW.position, GROWTH_WINDOW.size)

# Returns null for unknown IDs; never falls back to another sprite.
static func item_texture(id: String) -> Texture2D:
	if not has_item(id):
		return null
	var key := canonical(id)
	return native("item:" + key, ITEMS_PATH, item_region(key), ICON_SIZE)

# Stage 0 sprout, 1 juvenile, 2 bud, 3 mature. Out-of-range stages return null
# (no clamping) so callers notice contract mismatches.
static func crop_texture(id: String, stage: int) -> Texture2D:
	if not has_crop(id) or not valid_stage(stage):
		return null
	var key := canonical(id)
	return native("crop:%s:%d" % [key, stage], GROWTH_PATH, crop_region(key, stage), ICON_SIZE)

static func clear_cache() -> void:
	cache.clear()
