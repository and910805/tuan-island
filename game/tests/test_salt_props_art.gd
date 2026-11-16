extends SceneTree

# Standalone checks for the salt prop adapter (game/scripts/salt_props_art.gd),
# adapted from work/salt/staged-art/test_salt_props_art.gd: only the adapter
# load and the byte-identity comparison now point at game/ (res://), and the two
# root paths are derived from the project instead of env vars. Prints one JSON line
# "SALT_PROPS_MEASURE {...}" with the quantitative results for result.json.
var Art: GDScript
var checks := 0
var failures := 0
var measure := {}

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func bounds(image: Image, region: Rect2i, threshold: int) -> Rect2i:
	var mn := Vector2i(1 << 20, 1 << 20)
	var mx := Vector2i(-1, -1)
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if image.get_pixel(x, y).a8 > threshold:
				mn = mn.min(Vector2i(x, y))
				mx = mx.max(Vector2i(x, y))
	if mx.x < 0:
		return Rect2i()
	return Rect2i(mn, mx - mn + Vector2i.ONE)

func count_visible(image: Image, region: Rect2i, threshold: int) -> int:
	var n := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if image.get_pixel(x, y).a8 > threshold:
				n += 1
	return n

func row_span(image: Image, y: int, threshold: int) -> Vector2i:
	var l := -1
	var r := -1
	for x in image.get_width():
		if image.get_pixel(x, y).a8 > threshold:
			if l < 0:
				l = x
			r = x
	return Vector2i(l, r)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var stage := ProjectSettings.globalize_path("res://assets/salt")
	var repo := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	Art = preload("res://scripts/salt_props_art.gd")
	expect(Art != null, "adapter script loads")
	if Art == null:
		finish()
		return
	var src_path := repo + "/work/salt/art-source/salt-props-source-v2.png"
	var hash_before := FileAccess.get_sha256(src_path)
	measure["source_sha256"] = hash_before
	expect(hash_before == FileAccess.get_sha256(stage + "/salt-props.png"), "game res:// copy is byte-identical to selected source")

	# --- default path is the eventual game path, not a machine path ---
	expect(Art.DEFAULT_SOURCE_PATH == "res://assets/salt/salt-props.png", "default source path is res://assets/salt/salt-props.png")
	expect(Art.source_path == Art.DEFAULT_SOURCE_PATH, "static source_path starts at default")

	# --- source quantitative checks ---
	var src := Image.load_from_file(src_path)
	expect(src != null and src.get_size() == Vector2i(1254, 1254), "source is 1254x1254")
	expect(src.detect_alpha() != Image.ALPHA_NONE, "source has alpha")
	src.convert(Image.FORMAT_RGBA8)
	var measured := {}
	for id in Art.IDS:
		var clip: Rect2i = Art.cell_clip(id)
		var b := bounds(src, clip, Art.ALPHA_VISIBLE)
		measured[id] = b
		measure[id] = {"cell": [clip.position.x, clip.position.y], "alpha8_bounds_abs": [b.position.x, b.position.y, b.end.x - 1, b.end.y - 1], "feet_y_abs": b.end.y - 1, "visible_px": count_visible(src, clip, Art.ALPHA_VISIBLE), "opaque128_px": count_visible(src, clip, 128)}
		var rel := Rect2i(b.position - clip.position, b.size)
		var expected: Rect2i = Art.VISIBLE_REL[id]
		# Gate entries are the union of both states; each state must be inside it, within 1px.
		expect(expected.encloses(rel), "%s measured bounds %s inside declared %s" % [id, rel, expected])
		expect(absi(rel.position.x - expected.position.x) <= 1 and absi(rel.end.x - expected.end.x) <= 1 and rel.position.y == expected.position.y and rel.end.y == expected.end.y, "%s declared bounds match measurement (+-1px x, exact y)" % id)
		# whole visible cell content lies inside the window (no cut-off art)
		var window: Rect2i = Art.source_window(id)
		var outside := 0
		for y in range(clip.position.y, clip.end.y):
			for x in range(clip.position.x, clip.end.x):
				if not window.has_point(Vector2i(x, y)) and src.get_pixel(x, y).a8 > Art.ALPHA_VISIBLE:
					outside += 1
		expect(outside == 0, "%s: no visible source px outside window (%d)" % [id, outside])
		expect(window.size == Art.WINDOW_SIZE, "%s window is 576x576" % id)
		expect(window.end.y - 1 - Art.FEET_PAD == b.end.y - 1, "%s window bottom anchored on visible feet, not raw cell bottom" % id)
	# gutters: grid lines carry no visible alpha (no object straddles a cell)
	var line_hits := 0
	for i in 1254:
		for p in [Vector2i(626, i), Vector2i(627, i), Vector2i(i, 626), Vector2i(i, 627)]:
			if src.get_pixelv(p).a8 > Art.ALPHA_VISIBLE:
				line_hits += 1
	expect(line_hits == 0, "cell lines x/y 626..627 are transparent (%d hits)" % line_hits)
	measure["gutter_line_hits"] = line_hits
	# gates sit high in their cells; machines low
	var gb: Rect2i = measured["gate_broken"]
	var gr: Rect2i = measured["gate_repaired"]
	expect(gb.end.y == gr.end.y and gb.position.y == gr.position.y, "both gate states share exact top/feet rows")
	expect(absi((gr.position.x - 627) - gb.position.x) <= 1 and absi((gr.end.x - 627) - gb.end.x) <= 1, "gate states share x bounds within 1px")
	expect(627 - gb.end.y > 100, "gate art has >100px transparent bottom in its cell (raw canvas bottom would misplace it)")
	expect(measured["waterwheel"].end.y == measured["salt_collector"].end.y, "bottom-row props share feet row")
	# broken gate gap: fewer opaque px than repaired inside the shared panel
	var b_op: int = measure["gate_broken"]["opaque128_px"]
	var r_op: int = measure["gate_repaired"]["opaque128_px"]
	measure["gate_opaque_ratio_broken_over_repaired"] = snappedf(float(b_op) / float(r_op), 0.001)
	expect(float(b_op) < 0.9 * float(r_op), "broken gate has visibly less material than repaired (%d vs %d)" % [b_op, r_op])

	# --- identical transforms for the two gate states ---
	var wb: Rect2i = Art.source_window("gate_broken")
	var wr: Rect2i = Art.source_window("gate_repaired")
	expect(wb.position - Art.cell_clip("gate_broken").position == wr.position - Art.cell_clip("gate_repaired").position and wb.size == wr.size, "gate windows identical cell-relative")
	expect(Art.foot_anchor("gate_broken") == Art.foot_anchor("gate_repaired"), "gate anchors identical")
	expect(Art.footprint_recommendation("gate_broken")["tiles"] == Art.footprint_recommendation("gate_repaired")["tiles"], "gate footprints identical")

	# --- unknown IDs ---
	for bad in ["", "gate", "Gate_broken", "gate_broken ", "pump", "salt_rake", "waterwheel_pump", "seed_saving_table"]:
		expect(Art.prop_texture(bad) == null, "unknown id '%s' -> null texture" % bad)
		expect(Art.prop_size(bad) == Vector2i.ZERO, "unknown id '%s' -> zero size" % bad)
		expect(Art.foot_anchor(bad) == Vector2i(-1, -1), "unknown id '%s' -> (-1,-1) anchor" % bad)
		expect(Art.footprint_recommendation(bad).is_empty(), "unknown id '%s' -> empty footprint" % bad)
		expect(Art.draw_rect_for(bad, Vector2(10, 10)) == Rect2(), "unknown id '%s' -> empty draw rect" % bad)
	expect(Art.cache.is_empty(), "unknown ids never populate cache")

	# --- missing / wrong-size sources return null, no cache poisoning ---
	Art.set_source_path(stage + "/does-not-exist.png")
	expect(Art.prop_texture("waterwheel") == null, "missing source -> null")
	Art.set_source_path("res://assets/salt/missing.png")
	expect(Art.prop_texture("waterwheel") == null, "missing res:// source -> null")
	Art.set_source_path(repo + "/game/assets/life-art/characters.png")
	expect(Art.prop_texture("waterwheel") == null, "wrong-size source -> null")
	expect(Art.cache.is_empty(), "failed loads leave cache empty")

	# --- native textures via absolute stage path ---
	Art.set_source_path(src_path)
	var natives := {}
	for id in Art.IDS:
		var tex: Texture2D = Art.prop_texture(id)
		expect(tex != null, "%s texture" % id)
		if tex == null:
			continue
		expect(tex is ImageTexture, "%s is in-memory ImageTexture" % id)
		expect(Vector2i(tex.get_size()) == Vector2i(64, 64), "%s is 64x64" % id)
		expect(Art.prop_texture(id) == tex, "%s cached instance reused" % id)
		expect(tex.get_meta("source_window") == Art.source_window(id), "%s meta window" % id)
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		natives[id] = img
	expect(Art.cache.size() == 4, "cache holds exactly 4 entries")

	# nearest check: every native px equals one source px on a fixed 9px lattice
	var lattice_offset := -1
	for off in Art.SCALE:
		var ok := true
		for id in Art.IDS:
			if not natives.has(id):
				ok = false
				break
			var window: Rect2i = Art.source_window(id)
			var canvas: Image = Art.windowed(src, Art.cell_clip(id), window)
			for y in 64:
				for x in 64:
					if natives[id].get_pixel(x, y) != canvas.get_pixel(x * Art.SCALE + off, y * Art.SCALE + off):
						ok = false
						break
				if not ok:
					break
			if not ok:
				break
		if ok:
			lattice_offset = off
			break
	expect(lattice_offset >= 0, "native textures are pure nearest samples of the source window (offset %d)" % lattice_offset)
	measure["nearest_lattice_offset"] = lattice_offset

	# native feet / anchor / footprint
	var feet_rows := {}
	var base_spans := {}
	for id in natives:
		var img: Image = natives[id]
		var nb := bounds(img, Rect2i(0, 0, 64, 64), Art.ALPHA_VISIBLE)
		var feet := nb.end.y - 1
		feet_rows[id] = feet
		var centre := nb.position.x + (nb.size.x - 1) / 2.0
		var base_l := 64
		var base_r := -1
		for y in range(feet - 2, feet + 1):
			var s := row_span(img, y, Art.ALPHA_VISIBLE)
			if s.x >= 0:
				base_l = mini(base_l, s.x)
				base_r = maxi(base_r, s.y)
		var base_px := base_r - base_l + 1
		var feet_span := row_span(img, feet, 128)
		measure[id]["native_alpha8_bounds"] = [nb.position.x, nb.position.y, nb.end.x - 1, nb.end.y - 1]
		measure[id]["native_feet_row"] = feet
		measure[id]["native_feet_row_opaque128_span"] = [feet_span.x, feet_span.y]
		measure[id]["native_visible_centre_x"] = centre
		measure[id]["native_base_px_bottom3rows"] = base_px
		measure[id]["native_visible_px"] = count_visible(img, Rect2i(0, 0, 64, 64), Art.ALPHA_VISIBLE)
		expect(feet == Art.FOOT_ANCHOR.y - 1, "%s visible feet on native row 63 (anchor y64), got %d" % [id, feet])
		expect(feet_span.x >= 0, "%s feet row has opaque (>128) pixels, not just haze" % id)
		expect(absf(centre - Art.FOOT_ANCHOR.x) <= 1.0, "%s visible centre within 1px of anchor x32 (%.1f)" % [id, centre])
		base_spans[id] = Vector2i(base_l, base_r)
		expect(nb.position.x >= 0 and nb.end.x <= 64 and nb.position.y >= 1, "%s fits canvas with headroom" % id)
	# footprint base: gates use the union of both states' ground spans
	if base_spans.size() == 4:
		var g: Vector2i = base_spans["gate_broken"]
		var g2: Vector2i = base_spans["gate_repaired"]
		var gate_base := maxi(g.y, g2.y) - mini(g.x, g2.x) + 1
		measure["gate_union_base_px"] = gate_base
		for id in Art.IDS:
			var want: int = gate_base if id.begins_with("gate_") else base_spans[id].y - base_spans[id].x + 1
			expect(Art.FOOTPRINT[id]["base_px"] == want, "%s footprint base_px %d matches measured %d" % [id, Art.FOOTPRINT[id]["base_px"], want])
			var tiles: Vector2i = Art.FOOTPRINT[id]["tiles"]
			expect(tiles.x * 32 >= want and (tiles.x - 1) * 32 < want, "%s recommended tile width covers base" % id)
	# equal visual feet across all four
	var rows_seen := {}
	for id in feet_rows:
		rows_seen[feet_rows[id]] = true
	expect(rows_seen.size() == 1, "all four props share one native feet row %s" % str(feet_rows))
	# draw rects for one ground y share the same bottom
	var bottoms := {}
	for id in Art.IDS:
		var r: Rect2 = Art.draw_rect_for(id, Vector2(100.4, 200.0))
		bottoms[r.end.y] = true
		expect(r.size == Vector2(64, 64) and r.position == Vector2(68, 136), "%s draw rect from ground" % id)
	expect(bottoms.size() == 1, "draw rects share one bottom")
	# gate states: identical native top row, identical post columns (frame stays put)
	if natives.has("gate_broken") and natives.has("gate_repaired"):
		var nb_b := bounds(natives["gate_broken"], Rect2i(0, 0, 64, 64), Art.ALPHA_VISIBLE)
		var nb_r := bounds(natives["gate_repaired"], Rect2i(0, 0, 64, 64), Art.ALPHA_VISIBLE)
		expect(nb_b.position.y == nb_r.position.y and nb_b.end.y == nb_r.end.y, "gate native top/feet rows identical")
		expect(absi(nb_b.position.x - nb_r.position.x) <= 1 and absi(nb_b.end.x - nb_r.end.x) <= 1, "gate native x extents within 1px")
		var vb: int = measure["gate_broken"]["native_visible_px"]
		var vr: int = measure["gate_repaired"]["native_visible_px"]
		var diff := 0
		for y in 64:
			for x in 64:
				if (natives["gate_broken"].get_pixel(x, y).a8 > 128) != (natives["gate_repaired"].get_pixel(x, y).a8 > 128):
					diff += 1
		measure["gate_native_opaque_mask_diff_px"] = diff
		expect(diff >= 150, "broken vs repaired differ by >=150 native px (gap readable at 64px), got %d" % diff)
		expect(vb < vr, "broken gate has fewer visible native px (%d < %d)" % [vb, vr])

	# --- cache invalidation on path change, res:// default import path ---
	var abs_tex: Texture2D = Art.prop_texture("gate_broken")
	Art.set_source_path(Art.DEFAULT_SOURCE_PATH)
	expect(Art.cache.is_empty(), "set_source_path clears cache")
	var res_tex: Texture2D = Art.prop_texture("gate_broken")
	expect(res_tex != null and res_tex != abs_tex, "res:// default path (imported copy) yields fresh texture")
	if res_tex != null:
		var all_equal := true
		for id in Art.IDS:
			Art.set_source_path(Art.DEFAULT_SOURCE_PATH)
			var a: Image = Art.prop_texture(id).get_image()
			a.convert(Image.FORMAT_RGBA8)
			for y in 64:
				for x in 64:
					if a.get_pixel(x, y).a8 != natives[id].get_pixel(x, y).a8:
						all_equal = false
		expect(all_equal, "res:// imported (lossless) path matches absolute-path alpha exactly")
		expect(res_tex.get_meta("source_png") == "res://assets/salt/salt-props.png", "meta records res:// source")
	Art.set_source_path(Art.DEFAULT_SOURCE_PATH)
	Art.clear_cache()
	expect(Art.cache.is_empty(), "clear_cache empties")

	# --- reference character (read-only): main player atlas + flower resident ---
	var chars := Image.load_from_file(repo + "/game/assets/life-art/characters.png")
	if chars != null:
		chars.convert(Image.FORMAT_RGBA8)
		var pb := bounds(chars, Rect2i(0, 0, 48, 48), Art.ALPHA_VISIBLE)
		measure["player_frame00_alpha8_bounds"] = [pb.position.x, pb.position.y, pb.end.x - 1, pb.end.y - 1]
		measure["player_frame_size_and_foot"] = "48x48 frame, FOOT (24,44) per character_sprite_art.gd"
		expect(pb.end.y - 1 <= 44, "player feet at or above declared FOOT y44")

	expect(FileAccess.get_sha256(src_path) == hash_before, "selected source PNG unchanged after tests")
	finish()

func finish() -> void:
	measure["checks"] = checks
	measure["failures"] = failures
	print("SALT_PROPS_MEASURE " + JSON.stringify(measure))
	print("SALT_PROPS_ART %s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
