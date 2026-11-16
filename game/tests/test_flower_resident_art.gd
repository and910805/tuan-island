extends SceneTree

# Standalone checks for scripts/flower_resident_art.gd (no World, no registration).
const Art = preload("res://scripts/flower_resident_art.gd")
const SOURCE_SHA256 := "6d14eb8e45a42141e3bc43757abcce319c40b96ac9283b56e1259ecbf53754d2"
const ORIGINAL_SOURCE := "../work/flowers/art-source/flower-resident-source.png"
const VISIBLE := 8   # source alpha above this counts as drawn content (below = haze)
const OPAQUE := 64   # native alpha at/above this counts as a visible pixel

var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func bounds_above(image: Image, area: Rect2i, threshold: int) -> Rect2i:
	var out := Rect2i()
	var any := false
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if image.get_pixel(x, y).a8 > threshold:
				var p := Rect2i(x, y, 1, 1)
				out = p if not any else out.merge(p)
				any = true
	return out

func count_outside(image: Image, area: Rect2i, window: Rect2i, threshold: int) -> int:
	var n := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if not window.has_point(Vector2i(x, y)) and image.get_pixel(x, y).a8 > threshold:
				n += 1
	return n

func alpha_stats(image: Image) -> Dictionary:
	var solid := 0
	var soft := 0
	var ghost := 0
	for y in image.get_height():
		for x in image.get_width():
			var a := image.get_pixel(x, y).a8
			if a >= 224:
				solid += 1
			elif a >= OPAQUE:
				soft += 1
			elif a > 0:
				ghost += 1
	return {"solid": solid, "soft": soft, "ghost": ghost,
		"bounds": bounds_above(image, Rect2i(Vector2i.ZERO, image.get_size()), OPAQUE - 1)}

func max_alpha_row(image: Image, y: int) -> int:
	var m := 0
	for x in image.get_width():
		m = maxi(m, image.get_pixel(x, y).a8)
	return m

func max_alpha_col(image: Image, x: int) -> int:
	var m := 0
	for y in image.get_height():
		m = maxi(m, image.get_pixel(x, y).a8)
	return m

func verify_source() -> Image:
	expect(FileAccess.get_sha256(Art.SOURCE_PATH) == SOURCE_SHA256, "asset PNG sha256 matches the delivered source")
	var original := ProjectSettings.globalize_path("res://").path_join(ORIGINAL_SOURCE)
	if FileAccess.file_exists(original):
		expect(FileAccess.get_sha256(original) == SOURCE_SHA256, "art-source PNG is byte-identical to the asset")
	else:
		print("NOTE art-source PNG not present; byte-identity checked against recorded sha only")
	var image := Art.source_image()
	expect(image != null, "source loads through the Godot import")
	if image == null:
		return null
	expect(image.get_size() == Art.SOURCE_SIZE, "source is 1774x887")
	expect(Art.PANEL * Vector2i(2, 1) == Art.SOURCE_SIZE, "source is exactly two equal square panels")
	var w := image.get_width() - 1
	var h := image.get_height() - 1
	for p in [Vector2i(0, 0), Vector2i(w, 0), Vector2i(0, h), Vector2i(w, h)]:
		expect(image.get_pixelv(p).a8 == 0, "source corner %s is transparent" % p)
	return image

func verify_regions(image: Image) -> void:
	var left := Rect2i(Vector2i.ZERO, Art.PANEL)
	var right := Rect2i(Vector2i(Art.PANEL.x, 0), Art.PANEL)
	expect(left.encloses(Art.RESIDENT_REGION), "resident window lies inside the left panel")
	expect(right.encloses(Art.PORTRAIT_REGION), "portrait window lies inside the right panel")
	expect(not Art.RESIDENT_REGION.intersects(Art.PORTRAIT_REGION), "the two windows do not overlap")
	# Same scale on both axes = native aspect preserved (no square-to-tall stretch).
	expect(Art.RESIDENT_REGION.size.x * Art.RESIDENT_SIZE.y == Art.RESIDENT_REGION.size.y * Art.RESIDENT_SIZE.x, "resident window has the exact 32:48 aspect")
	expect(Art.PORTRAIT_REGION.size.x * Art.PORTRAIT_SIZE.y == Art.PORTRAIT_REGION.size.y * Art.PORTRAIT_SIZE.x, "portrait window has the exact 1:1 aspect")
	if image == null:
		return
	var body := bounds_above(image, left, VISIBLE)
	var bust := bounds_above(image, right, VISIBLE)
	expect(body == Art.RESIDENT_ALPHA_BOUNDS, "measured full-body bounds still match the recorded %s (got %s)" % [Art.RESIDENT_ALPHA_BOUNDS, body])
	expect(bust == Art.PORTRAIT_ALPHA_BOUNDS, "measured portrait bounds still match the recorded %s (got %s)" % [Art.PORTRAIT_ALPHA_BOUNDS, bust])
	expect(Art.RESIDENT_REGION.encloses(body), "resident window encloses the whole body (hat to boots)")
	expect(Art.PORTRAIT_REGION.encloses(bust), "portrait window encloses hat, ribbon and shoulders")
	expect(count_outside(image, left, Art.RESIDENT_REGION, VISIBLE) == 0, "no visible full-body pixel is clipped by the window")
	expect(count_outside(image, right, Art.PORTRAIT_REGION, VISIBLE) == 0, "no visible portrait pixel is clipped by the window")
	# Neither window reaches visible content of the other panel.
	expect(bounds_above(image, Art.RESIDENT_REGION.intersection(right), VISIBLE).size == Vector2i.ZERO, "resident window samples nothing from the portrait panel")
	# Foot anchor in source: window bottom sits within one native row under the feet.
	var scale := float(Art.RESIDENT_REGION.size.y) / Art.RESIDENT_SIZE.y
	var gap: int = Art.RESIDENT_REGION.end.y - body.end.y
	expect(gap >= 0 and gap < scale, "window bottom is less than one native row below the feet (%d src px)" % gap)
	var centre_offset := absf((body.position.x + body.size.x / 2.0) - (Art.RESIDENT_REGION.position.x + Art.RESIDENT_REGION.size.x / 2.0))
	expect(centre_offset <= 2.0, "body is horizontally centred in its window (%.1f src px)" % centre_offset)

func check_texture(texture: Texture2D, size: Vector2i, region: Rect2i, label: String) -> Image:
	expect(texture != null, label + " loads")
	if texture == null:
		return null
	expect(texture is ImageTexture, label + " is an in-memory ImageTexture")
	expect(Vector2i(texture.get_size()) == size, "%s is %dx%d" % [label, size.x, size.y])
	expect(texture.get_meta("source_png", "") == Art.SOURCE_PATH, label + " records its source PNG")
	expect(texture.get_meta("source_region", Rect2i()) == region, label + " records its source region")
	var image := texture.get_image()
	expect(image.get_format() == Image.FORMAT_RGBA8, label + " keeps RGBA alpha")
	var w := image.get_width() - 1
	var h := image.get_height() - 1
	for p in [Vector2i(0, 0), Vector2i(w, 0), Vector2i(0, h), Vector2i(w, h)]:
		expect(image.get_pixelv(p).a8 < 8, "%s corner %s is transparent" % [label, p])
	return image

func verify_resident() -> Image:
	var image := check_texture(Art.resident_texture(), Art.RESIDENT_SIZE, Art.RESIDENT_REGION, "resident")
	if image == null:
		return null
	var s := alpha_stats(image)
	var b: Rect2i = s.bounds
	print("RESIDENT native=32x48 opaque_bounds=%s solid=%d soft64-223=%d ghost1-63=%d" % [b, s.solid, s.soft, s.ghost])
	expect(s.solid >= 500, "resident has a substantial solid silhouette (%d)" % s.solid)
	expect(s.soft + s.ghost > 0, "soft source alpha is retained, not thresholded")
	expect(max_alpha_row(image, 0) < OPAQUE, "top row is clear: hat is not clipped")
	expect(max_alpha_col(image, 0) < OPAQUE and max_alpha_col(image, Art.RESIDENT_SIZE.x - 1) < OPAQUE, "side columns are clear: shoulders/ribbon not clipped")
	expect(b.end.y == Art.RESIDENT_FEET.y, "boots land on the last row (feet anchor y48, got %d)" % b.end.y)
	expect(b.position.y >= 1 and b.size.y >= 44, "full body spans hat to boots at native height (%d rows)" % b.size.y)
	var centre := b.position.x + b.size.x / 2.0
	expect(absf(centre - Art.RESIDENT_FEET.x) <= 1.5, "resident is centred on the feet anchor x16 (%.1f)" % centre)
	# Aspect of the silhouette matches the source silhouette (no stretch).
	var src_ratio := float(Art.RESIDENT_ALPHA_BOUNDS.size.x) / Art.RESIDENT_ALPHA_BOUNDS.size.y
	var ratio := float(b.size.x) / b.size.y
	expect(absf(ratio - src_ratio) <= 0.05, "silhouette aspect %.3f matches source %.3f" % [ratio, src_ratio])
	# The bottom rows hold two separate boots (gap between them at the centre).
	var feet_row := b.end.y - 1
	expect(image.get_pixel(Art.RESIDENT_FEET.x, feet_row).a8 < OPAQUE or image.get_pixel(Art.RESIDENT_FEET.x - 1, feet_row).a8 < OPAQUE, "a gap separates the two boots on the feet row")
	return image

func verify_portrait() -> Image:
	var image := check_texture(Art.portrait_texture(), Art.PORTRAIT_SIZE, Art.PORTRAIT_REGION, "portrait")
	if image == null:
		return null
	var s := alpha_stats(image)
	var b: Rect2i = s.bounds
	print("PORTRAIT native=64x64 opaque_bounds=%s solid=%d soft64-223=%d ghost1-63=%d" % [b, s.solid, s.soft, s.ghost])
	expect(s.solid >= 2000, "portrait has a substantial solid bust (%d)" % s.solid)
	expect(s.soft + s.ghost > 0, "soft source alpha is retained, not thresholded")
	expect(max_alpha_row(image, 0) < OPAQUE, "portrait top row clear: hat not clipped")
	expect(max_alpha_row(image, Art.PORTRAIT_SIZE.y - 1) < OPAQUE, "portrait bottom row clear: shoulders end inside the frame")
	expect(max_alpha_col(image, 0) < OPAQUE and max_alpha_col(image, Art.PORTRAIT_SIZE.x - 1) < OPAQUE, "portrait side columns clear: brim and ribbon not clipped")
	expect(b.size.y >= 56, "portrait fills the frame height (%d rows)" % b.size.y)
	var centre := b.position.x + b.size.x / 2.0
	expect(absf(centre - 32.0) <= 1.5, "portrait is horizontally centred (%.1f)" % centre)
	var src_ratio := float(Art.PORTRAIT_ALPHA_BOUNDS.size.x) / Art.PORTRAIT_ALPHA_BOUNDS.size.y
	var ratio := float(b.size.x) / b.size.y
	expect(absf(ratio - src_ratio) <= 0.05, "portrait aspect %.3f matches source %.3f" % [ratio, src_ratio])
	return image

func verify_cache(resident: Image, portrait: Image) -> void:
	var r1 := Art.resident_texture()
	var p1 := Art.portrait_texture()
	expect(r1 == Art.resident_texture(), "resident texture is cached (same instance)")
	expect(p1 == Art.portrait_texture(), "portrait texture is cached (same instance)")
	expect(r1 != p1, "resident and portrait are different textures")
	expect(Art.cache.size() == 2, "cache holds exactly two entries")
	Art.clear_cache()
	expect(Art.cache.is_empty(), "clear_cache empties the cache")
	var r2 := Art.resident_texture()
	var p2 := Art.portrait_texture()
	expect(r2 != r1 and p2 != p1, "after clear_cache new textures are built")
	if resident != null and portrait != null:
		expect(r2.get_image().get_data() == resident.get_data(), "rebuilt resident is pixel-identical")
		expect(p2.get_image().get_data() == portrait.get_data(), "rebuilt portrait is pixel-identical")
		expect(resident.get_data() != portrait.get_data(), "the two regions produce different pixels")

func _init() -> void:
	Art.clear_cache()
	var source := verify_source()
	verify_regions(source)
	var resident := verify_resident()
	var portrait := verify_portrait()
	verify_cache(resident, portrait)
	print("FLOWER_RESIDENT_ART_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
