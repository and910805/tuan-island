extends SceneTree

# Standalone checks for scripts/flower_scene_art.gd (no World, no registration).
const Art = preload("res://scripts/flower_scene_art.gd")
const SOURCE_SHA256 := "d8c55aec7b019f6796a11ccfb21a2c06eecdde88fc97fb47904608605614d311"
const EXPECTED_IDS := ["seed_saving_table", "dye_table", "community_flower_trellis", "nursery_shuttle_shelter"]
const EXPECTED_SIZES := {
	"seed_saving_table": Vector2i(64, 56),
	"dye_table": Vector2i(64, 56),
	"community_flower_trellis": Vector2i(64, 64),
	"nursery_shuttle_shelter": Vector2i(80, 80),
}
const INVALID_IDS := ["", "bench", "seed_table", "Dye_Table", "dye_table ", "trellis", "shuttle_sign", "nursery_net_shed", "bluebell"]
const VISIBLE := 8  # source alpha above this counts as visible (haze is 1..8)

var checks := 0
var failures := 0
var report: Array = []

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

func count_outside(image: Image, area: Rect2i, inner: Rect2i, threshold: int) -> int:
	var n := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if not inner.has_point(Vector2i(x, y)) and image.get_pixel(x, y).a8 > threshold:
				n += 1
	return n

func border_hits(image: Image, area: Rect2i, threshold: int) -> int:
	var n := 0
	for x in range(area.position.x, area.end.x):
		for y in [area.position.y, area.end.y - 1]:
			if image.get_pixel(x, y).a8 > threshold:
				n += 1
	for y in range(area.position.y, area.end.y):
		for x in [area.position.x, area.end.x - 1]:
			if image.get_pixel(x, y).a8 > threshold:
				n += 1
	return n

func verify_source() -> void:
	expect(FileAccess.get_sha256(Art.PROPS_PATH) == SOURCE_SHA256, "asset PNG is the byte-for-byte source (sha256)")
	var image := Art.source_image(Art.PROPS_PATH)
	expect(image != null and image.get_size() == Art.SOURCE_SIZE, "props source loads at 1254x1254")
	if image == null:
		return
	expect(image.get_pixel(0, 0).a8 == 0, "source keeps a transparent background")
	var full := Rect2i(Vector2i.ZERO, Art.SOURCE_SIZE)
	var area := 0
	var clips: Array = []
	for id in EXPECTED_IDS:
		var spec: Dictionary = Art.PROPS[id]
		var clip: Rect2i = spec.clip
		var window: Rect2i = spec.window
		var size: Vector2i = spec.size
		expect(full.encloses(clip), id + " clip lies inside the source")
		for other in clips:
			expect(not clip.intersects(other), id + " clip is disjoint from other clips")
		clips.append(clip)
		area += clip.get_area()
		# Exact aspect: window is an integer-free multiple of native size on both axes.
		expect(window.size.x * size.y == window.size.y * size.x, id + " window keeps native aspect exactly")
		var measured := bounds_above(image, clip, VISIBLE)
		expect(measured.has_area(), id + " has visible source pixels")
		# Zero clipped edges: no visible pixel of the clip falls outside the window,
		# and no visible pixel touches the clip border (gutters are real).
		expect(count_outside(image, clip, window, VISIBLE) == 0, id + " window encloses every visible source pixel")
		expect(border_hits(image, clip, VISIBLE) == 0, id + " clip border crosses no visible pixel (no cut at the gutter)")
		var feet_gap := window.end.y - measured.end.y
		expect(feet_gap >= 0 and feet_gap <= 4, "%s window is bottom-anchored on the feet (gap %d src px)" % [id, feet_gap])
		var centre_off := absf((window.position.x + window.size.x / 2.0) - (measured.position.x + measured.size.x / 2.0))
		expect(centre_off <= 1.0, "%s window is centred on the measured bounds (off %.1f)" % [id, centre_off])
		report.append("%s source_bounds=%s window=%s scale=%.2f" % [id, measured, window, float(window.size.x) / size.x])
	expect(area == full.get_area(), "clips partition the whole source")
	# Equal 627px cells would cut the shelter: prove why explicit clips exist.
	var shelter: Rect2i = bounds_above(image, Art.PROPS.nursery_shuttle_shelter.clip, VISIBLE)
	expect(shelter.position.x < 627, "shelter crosses the nominal x627 cell line (equal cells would clip it)")

func verify_ids() -> void:
	expect(Art.PROPS.keys() == EXPECTED_IDS and Art.IDS == EXPECTED_IDS, "four prop IDs in sheet order")
	for id in EXPECTED_IDS:
		expect(Art.has_prop(id), id + " is a prop")
		expect(Art.prop_size(id) == EXPECTED_SIZES[id], "%s native size %s" % [id, EXPECTED_SIZES[id]])
		expect(Art.prop_anchor(id) == Vector2i(EXPECTED_SIZES[id].x / 2, EXPECTED_SIZES[id].y), id + " anchor is bottom centre")
	for id in INVALID_IDS:
		expect(not Art.has_prop(id), "invalid '%s' is not a prop" % id)
		expect(Art.prop_texture(id) == null, "invalid '%s' returns null" % id)
		expect(Art.prop_size(id) == Vector2i.ZERO and Art.prop_anchor(id) == Vector2i(-1, -1), "invalid '%s' has no size/anchor" % id)

func alpha_stats(image: Image) -> Dictionary:
	var solid := 0
	var ghost := 0
	var fringe := 0
	var bounds := Rect2i()
	var any := false
	for y in image.get_height():
		for x in image.get_width():
			var a := image.get_pixel(x, y).a8
			if a >= 224:
				solid += 1
			elif a >= 8 and a < 64:
				fringe += 1
			elif a > 0 and a < 8:
				ghost += 1
			if a >= 64:
				var p := Rect2i(x, y, 1, 1)
				bounds = p if not any else bounds.merge(p)
				any = true
	return {"solid": solid, "ghost": ghost, "fringe": fringe, "bounds": bounds, "any": any}

func verify_textures() -> void:
	var pixels := {}
	var windows := {}
	var solids := {}
	var source := Art.source_image(Art.PROPS_PATH)
	for id in EXPECTED_IDS:
		var texture := Art.prop_texture(id)
		expect(texture != null, id + " loads")
		if texture == null:
			continue
		var size: Vector2i = EXPECTED_SIZES[id]
		expect(Vector2i(texture.get_size()) == size, "%s is %s" % [id, size])
		expect(texture.get_meta("source_png", "") == Art.PROPS_PATH, id + " comes from the props PNG")
		var window: Rect2i = texture.get_meta("source_window", Rect2i())
		expect(window == Art.PROPS[id].window and not windows.has(window), id + " uses its own window")
		windows[window] = id
		var image := texture.get_image()
		expect(image.get_format() == Image.FORMAT_RGBA8, id + " keeps RGBA alpha")
		var stats := alpha_stats(image)
		var b: Rect2i = stats.bounds
		var w := size.x
		var h := size.y
		expect(stats.any and stats.solid >= size.x * size.y / 3, "%s is substantially filled (%d solid)" % [id, stats.solid])
		for p in [Vector2i(0, 0), Vector2i(w - 1, 0)]:
			expect(image.get_pixelv(p).a8 < 8, "%s top corner %s is transparent" % [id, p])
		# Anchors: feet on the last rows, horizontally centred, nothing cut at the
		# canvas top/left/right (only the bottom may touch).
		expect(b.end.y >= h - 2, "%s feet sit on the bottom rows (foot row %d of %d)" % [id, b.end.y - 1, h])
		var centre := b.position.x + b.size.x / 2.0
		expect(absf(centre - w / 2.0) <= 1.5, "%s is horizontally centred (%.1f vs %.1f)" % [id, centre, w / 2.0])
		expect(b.position.y >= 1 and b.position.x >= 1 and b.end.x <= w - 1, "%s has a clear margin on top/left/right %s" % [id, b])
		# Aspect preserved against the measured source silhouette (alpha>64).
		if source != null:
			var src_b := bounds_above(source, Art.PROPS[id].clip, 64)
			var src_ratio := float(src_b.size.x) / src_b.size.y
			var nat_ratio := float(b.size.x) / b.size.y
			expect(absf(nat_ratio - src_ratio) <= 0.06, "%s keeps silhouette aspect (%.3f vs source %.3f)" % [id, nat_ratio, src_ratio])
		var data := image.get_data()
		expect(not pixels.has(data), id + " pixels differ from every other prop")
		pixels[data] = id
		solids[id] = stats.solid
		report.append("%s native=%dx%d opaque_bounds=%s solid=%d fringe8-63=%d ghost1-7=%d" % [id, w, h, b, stats.solid, stats.fringe, stats.ghost])
	if solids.size() == 4:
		expect(solids.nursery_shuttle_shelter > solids.seed_saving_table and solids.nursery_shuttle_shelter > solids.dye_table, "shelter is the largest prop")
		var trellis: Rect2i = alpha_stats(Art.prop_texture("community_flower_trellis").get_image()).bounds
		expect(trellis.size.y > trellis.size.x, "trellis stays taller than wide")
		for id in ["seed_saving_table", "dye_table"]:
			var t: Rect2i = alpha_stats(Art.prop_texture(id).get_image()).bounds
			expect(t.size.y >= 48, "%s is not squashed into a squat sprite (%d px tall)" % [id, t.size.y])
	expect(pixels.size() == 4, "4 distinct prop sprites")

func verify_cache() -> void:
	Art.clear_cache()
	expect(Art.cache.is_empty(), "cache clears")
	var first := Art.prop_texture("dye_table")
	expect(first != null and first == Art.prop_texture("dye_table"), "texture is cached (same instance)")
	expect(Art.cache.size() == 1, "cache holds only requested props")
	for id in INVALID_IDS:
		Art.prop_texture(id)
	expect(Art.cache.size() == 1, "invalid lookups do not populate the cache")
	Art.clear_cache()
	var rebuilt := Art.prop_texture("dye_table")
	expect(rebuilt != null and rebuilt != first and rebuilt.get_image().get_data() == first.get_image().get_data(), "rebuilt texture is identical after clearing the cache")
	for id in EXPECTED_IDS:
		Art.prop_texture(id)
	expect(Art.cache.size() == 4 and Art.cache.keys().all(func(k): return EXPECTED_IDS.has(k)), "full set caches exactly 4 props")
	Art.clear_cache()

func verify_market() -> void:
	Art.clear_cache()
	var source:=Art.source_image(Art.MARKET_PATH)
	expect(source!=null and source.get_size()==Vector2i(1774,887),"market source has two equal cells")
	if source==null:return
	var variants:Array=[]
	for completed in [false,true]:
		var texture:=Art.market_texture(completed)
		expect(texture!=null,"market state loads")
		if texture==null:continue
		expect(texture.get_size()==Vector2(64,64),"market logical size stays64px")
		expect(texture==Art.market_texture(completed),"market cached without repeat decoding")
		expect(texture.get_meta("source_png","")==Art.MARKET_PATH,"market source provenance")
		var image:=texture.get_image()
		expect(not image.is_invisible() and image.detect_alpha()!=Image.ALPHA_NONE,"market visible with transparent background")
		variants.append(image.get_data())
	expect(variants.size()==2 and variants[0]!=variants[1],"garden completion changes actual pixels")
	expect(Art.market_anchor()==Vector2i(32,64),"both market variants share baseline anchor")
	Art.clear_cache()
	expect(Art.cache.is_empty(),"market textures included in cache lifecycle")

func _initialize() -> void:
	verify_source()
	verify_ids()
	verify_textures()
	verify_cache()
	verify_market()
	for line in report:
		print("PROP " + line)
	print("FLOWER_SCENE_ART_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
