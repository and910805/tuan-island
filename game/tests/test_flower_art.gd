extends SceneTree

# Standalone checks for scripts/flower_art.gd (no World, no registration).
const Art = preload("res://scripts/flower_art.gd")
const EXPECTED_ITEMS := [
	"bluebell", "orange_blossom", "chime_herb",
	"bluebell_seed", "orange_blossom_seed", "chime_herb_seed",
	"blue_dye", "sugar", "garden_cookie",
]
const INVALID_IDS := ["", "rose", "pumpkin", "Bluebell", "bluebell ", "blue_dye_seed", "orange"]
# Measured foot line (lowest row with alpha >= 64) per crop at 32px.
const FOOT_Y := {"bluebell": 31, "orange_blossom": 30, "chime_herb": 29}

var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func alpha_stats(image: Image) -> Dictionary:
	var solid := 0
	var bounds := Rect2i()
	var any := false
	for y in image.get_height():
		for x in image.get_width():
			var a := image.get_pixel(x, y).a8
			if a >= 224:
				solid += 1
			if a >= 64:
				var p := Rect2i(x, y, 1, 1)
				bounds = p if not any else bounds.merge(p)
				any = true
	return {"solid": solid, "bounds": bounds, "any": any}

func corners_clear(image: Image) -> bool:
	var w := image.get_width() - 1
	var h := image.get_height() - 1
	for p in [Vector2i(0, 0), Vector2i(w, 0), Vector2i(0, h), Vector2i(w, h)]:
		if image.get_pixelv(p).a8 >= 8:
			return false
	return true

# Every visible source pixel of a grid cell must fall inside the crop window, so
# the window never cuts a petal and neighbouring cells never leak in.
func window_encloses_cell(image: Image, cell: Rect2i, window: Rect2i, label: String) -> void:
	var outside := 0
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			if window.has_point(Vector2i(x, y)):
				continue
			if image.get_pixel(x, y).a8 > 16:
				outside += 1
	expect(outside == 0, "%s has no visible pixels outside its crop window (%d found)" % [label, outside])

func verify_sources() -> void:
	var growth := Art.source_image(Art.GROWTH_PATH)
	var items := Art.source_image(Art.ITEMS_PATH)
	expect(growth != null and growth.get_size() == Art.GROWTH_SOURCE_SIZE, "growth source loads at 1448x1086")
	expect(items != null and items.get_size() == Art.ITEMS_SOURCE_SIZE, "items source loads at 1278x1230")
	expect(Art.GROWTH_CELL * Vector2i(4, 3) == Art.GROWTH_SOURCE_SIZE, "growth grid is exactly 4x3 cells")
	expect(Art.ITEM_CELL * Vector2i(3, 3) == Art.ITEMS_SOURCE_SIZE, "items grid is exactly 3x3 cells")
	expect(Rect2i(Vector2i.ZERO, Art.GROWTH_CELL).encloses(Art.GROWTH_WINDOW), "growth window stays inside one cell")
	expect(Rect2i(Vector2i.ZERO, Art.ITEM_CELL).encloses(Art.ITEM_WINDOW), "item window stays inside one cell")
	expect(Art.GROWTH_WINDOW.size.x == Art.GROWTH_WINDOW.size.y and Art.ITEM_WINDOW.size.x == Art.ITEM_WINDOW.size.y, "crop windows are square (no aspect distortion)")
	if growth == null or items == null:
		return
	expect(growth.get_pixel(0, 0).a8 == 0 and items.get_pixel(0, 0).a8 == 0, "sources keep a transparent background")
	for row in Art.CROPS.size():
		for stage in Art.STAGE_COUNT:
			var cell := Rect2i(Vector2i(stage, row) * Art.GROWTH_CELL, Art.GROWTH_CELL)
			window_encloses_cell(growth, cell, Art.crop_region(Art.CROPS[row], stage), "%s stage %d" % [Art.CROPS[row], stage])
	for id in EXPECTED_ITEMS:
		var at: Vector2i = Art.ITEMS[id]
		window_encloses_cell(items, Rect2i(at * Art.ITEM_CELL, Art.ITEM_CELL), Art.item_region(id), "item " + id)

func verify_ids() -> void:
	expect(Art.CROPS == ["bluebell", "orange_blossom", "chime_herb"], "growth rows are bluebell, orange_blossom, chime_herb")
	expect(Art.STAGES.size() == Art.STAGE_COUNT and Art.STAGE_COUNT == 4, "four growth stages")
	expect(Art.ITEMS.keys() == EXPECTED_ITEMS, "nine item IDs in atlas order")
	expect(Art.ALIASES.is_empty(), "no aliases until the contract requires them")
	for crop in Art.CROPS:
		expect(Art.has_crop(crop), crop + " is a crop")
		expect(Art.has_item(crop), crop + " harvest icon exists")
		expect(Art.has_item(crop + "_seed"), crop + " seed packet exists")
		expect(not Art.has_crop(crop + "_seed"), crop + " seed is not a crop")
	for id in ["blue_dye", "sugar", "garden_cookie"]:
		expect(not Art.has_crop(id), id + " is not a crop")
	for id in INVALID_IDS:
		expect(not Art.has_item(id) and Art.item_texture(id) == null, "invalid item '%s' returns null" % id)
		expect(not Art.has_crop(id) and Art.crop_texture(id, 0) == null, "invalid crop '%s' returns null" % id)
	for crop in Art.CROPS:
		for stage in [-100, -1, 4, 5, 99]:
			expect(Art.crop_texture(crop, stage) == null, "%s stage %d is rejected, not clamped" % [crop, stage])
	expect(Art.crop_texture("blue_dye", 0) == null, "item-only ID has no growth sprite")

func verify_crops() -> void:
	var regions := {}
	var pixels := {}
	for crop in Art.CROPS:
		var previous_solid := -1
		var foot := -1
		for stage in Art.STAGE_COUNT:
			var label := "%s stage %d" % [crop, stage]
			var texture := Art.crop_texture(crop, stage)
			expect(texture != null, label + " loads")
			if texture == null:
				continue
			expect(Vector2i(texture.get_size()) == Art.ICON_SIZE, label + " is 32x32")
			expect(texture.get_meta("source_png", "") == Art.GROWTH_PATH, label + " comes from the growth PNG")
			var region: Rect2i = texture.get_meta("source_region", Rect2i())
			var expected_cell := Rect2i(Vector2i(stage, Art.CROPS.find(crop)) * Art.GROWTH_CELL, Art.GROWTH_CELL)
			expect(expected_cell.encloses(region), label + " samples its own row/column cell")
			expect(not regions.has(region), label + " uses a unique region")
			regions[region] = label
			var image := texture.get_image()
			expect(image.get_format() == Image.FORMAT_RGBA8, label + " keeps RGBA alpha")
			expect(corners_clear(image), label + " has transparent corners")
			var stats := alpha_stats(image)
			expect(stats.any and stats.solid >= 40, label + " has visible solid pixels")
			expect(stats.solid > previous_solid, label + " grows larger than the previous stage")
			previous_solid = stats.solid
			var bounds: Rect2i = stats.bounds
			if foot < 0:
				foot = bounds.end.y - 1
			expect(bounds.end.y - 1 == foot and foot == FOOT_Y[crop], "%s shares foot line %d (got %d)" % [label, FOOT_Y[crop], bounds.end.y - 1])
			var center := bounds.position.x + bounds.size.x / 2.0
			expect(absf(center - 16.0) <= 2.5, "%s is horizontally centred (%.1f)" % [label, center])
			expect(bounds.position.y >= 0 and bounds.size.y <= 32, label + " fits in the tile")
			var data := image.get_data()
			expect(not pixels.has(data), label + " pixels differ from every other sprite")
			pixels[data] = label
	expect(regions.size() == 12, "12 distinct growth sprites")
	for crop in Art.CROPS:
		var sprout: Rect2i = alpha_stats(Art.crop_texture(crop, 0).get_image()).bounds
		var mature: Rect2i = alpha_stats(Art.crop_texture(crop, Art.MATURE).get_image()).bounds
		expect(mature.size.y >= 24 and sprout.size.y <= 12, crop + " mature is tall and sprout is small at 32px")

func verify_items() -> void:
	var regions := {}
	var pixels := {}
	for id in EXPECTED_ITEMS:
		var texture := Art.item_texture(id)
		expect(texture != null, id + " icon loads")
		if texture == null:
			continue
		expect(Vector2i(texture.get_size()) == Art.ICON_SIZE, id + " icon is 32x32")
		expect(texture.get_meta("source_png", "") == Art.ITEMS_PATH, id + " comes from the items PNG")
		var region: Rect2i = texture.get_meta("source_region", Rect2i())
		expect(Rect2i(Art.ITEMS[id] * Art.ITEM_CELL, Art.ITEM_CELL).encloses(region), id + " samples its own cell")
		expect(not regions.has(region), id + " uses a unique region")
		regions[region] = id
		var image := texture.get_image()
		expect(corners_clear(image), id + " has transparent corners")
		var stats := alpha_stats(image)
		expect(stats.solid >= 250, id + " icon is substantially filled (%d solid)" % stats.solid)
		var bounds: Rect2i = stats.bounds
		expect(bounds.size.x >= 22 and bounds.size.y >= 22, id + " icon spans most of the 32px slot")
		var data := image.get_data()
		expect(not pixels.has(data), id + " pixels differ from every other icon")
		pixels[data] = id
	expect(regions.size() == 9, "9 distinct item icons")
	var crop_pixels := Art.crop_texture("bluebell", Art.MATURE).get_image().get_data()
	expect(Art.item_texture("bluebell").get_image().get_data() != crop_pixels, "harvest icon is distinct from the mature plant")

func verify_cache() -> void:
	Art.clear_cache()
	expect(Art.cache.is_empty(), "cache clears")
	var first := Art.crop_texture("orange_blossom", 2)
	var again := Art.crop_texture("orange_blossom", 2)
	expect(first != null and first == again, "crop texture is cached (same instance)")
	var icon := Art.item_texture("sugar")
	expect(icon != null and icon == Art.item_texture("sugar"), "item texture is cached (same instance)")
	expect(Art.cache.size() == 2, "cache holds only requested sprites")
	Art.item_texture("rose")
	Art.crop_texture("bluebell", 9)
	expect(Art.cache.size() == 2, "invalid lookups do not populate the cache")
	expect(Art.cache.has("crop:orange_blossom:2") and Art.cache.has("item:sugar"), "cache keys are namespaced by kind")
	expect(Art.item_texture("orange_blossom") != Art.crop_texture("orange_blossom", Art.MATURE), "item and crop with the same ID are cached separately")
	Art.clear_cache()
	var rebuilt := Art.crop_texture("orange_blossom", 2)
	expect(rebuilt != null and rebuilt != first and rebuilt.get_image().get_data() == first.get_image().get_data(), "rebuilt texture is identical after clearing the cache")
	for crop in Art.CROPS:
		for stage in Art.STAGE_COUNT:
			Art.crop_texture(crop, stage)
	for id in EXPECTED_ITEMS:
		Art.item_texture(id)
	expect(Art.cache.size() == 21, "full set caches 12 growth sprites and 9 icons")

func _initialize() -> void:
	verify_sources()
	verify_ids()
	verify_crops()
	verify_items()
	verify_cache()
	print("FLOWER_ART_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
