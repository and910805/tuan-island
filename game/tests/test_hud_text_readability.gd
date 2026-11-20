extends SceneTree
## Native-render readability audit for HUD, inventory and reachable modal panels.
## Checks: CJK glyph coverage, minimum font size, unscaled text, horizontal/vertical
## text cutoff (ellipsis, clipped lines, spill outside clip/viewport), pixel contrast
## of rendered text, and HUD obstruction of each other / of the central play area.
## Sizes: 1024x640 and 1280x800. Uses an in-memory World fixture only (no save file,
## no network host). Settings are read (never written) via the normal app path.
##
## Run (native renderer required; not --headless):
##   godot --path game --script res://tests/test_hud_text_readability.gd -- --village-art-preview
## Optional screenshots + JSON report (opt-in, absolute directory outside the project):
##   ... -- --village-art-preview --hud-readability-output=C:/tmp/hud-readability
## --text-scale=0..3 selects one of the in-game sizes; --scope=everyday checks HUD, inventory and settings.
## --scope=hud-full checks the full basic toolbar after the first crop guide.

const World = preload("res://scripts/world.gd")
const Opening = preload("res://scripts/wangan_opening_ui.gd")
const PLAYER := "readability"
const SIZES := [Vector2i(1024, 640), Vector2i(1280, 800)]
const PANELS := [
	["_pause_menu", []], ["_build_menu", []], ["_seed_menu", []], ["_shop", []],
	["_board", []], ["_resident_menu", ["aru"]], ["_journal", []], ["_collection_menu", []],
	["_festival_menu", []], ["_animal_menu", []], ["_orders_menu", []], ["_settings_menu", []],
	["_map_menu", []], ["_help", []], ["_quarry_menu", []],
]
const MIN_CJK_FONT := 12        # hard floor for any Chinese text
const COMFORT_CJK_FONT := 14    # below this is reported as a warning
const MIN_CONTRAST := 1.6       # rendered ink vs. background, hard floor (enabled text)
const MIN_CONTRAST_DISABLED := 1.25
const COMFORT_CONTRAST := 3.0   # below this is reported as a warning

var app
var world: World
var checks := 0
var failures := 0
var warnings := 0
var output_dir := ""
var pixels := true
var image: Image
var image_scale := Vector2.ONE
var report := {"sizes": {}, "failures": [], "warnings": []}
var current_size := ""

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, context: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + context)
		if report.failures.size() < 400:
			report.failures.append(current_size + " " + context)

func warn(context: String) -> void:
	warnings += 1
	if report.warnings.size() < 400:
		report.warnings.append(current_size + " " + context)

func user_arg(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="):
			return arg.trim_prefix("--" + name + "=")
	return ""

func settle() -> void:
	app._layout_preview()
	await process_frame
	await create_timer(0.35).timeout
	app._layout_preview()
	await process_frame
	await RenderingServer.frame_post_draw
	image = null
	if pixels:
		var texture := root.get_texture()
		image = texture.get_image() if texture != null else null
		if image != null and not image.is_empty():
			if image.is_compressed():
				image.decompress()
			image_scale = Vector2(image.get_size()) / root.get_visible_rect().size
		else:
			image = null

func shot(name: String) -> void:
	if output_dir.is_empty() or image == null:
		return
	var path := output_dir.path_join("%s-%s.png" % [current_size, name.trim_prefix("_")])
	expect(image.save_png(path) == OK, "screenshot saved " + path)

# ---------------------------------------------------------------- font helpers

func is_cjk(code: int) -> bool:
	return (code >= 0x2E80 and code <= 0x9FFF) or (code >= 0xF900 and code <= 0xFAFF) \
		or (code >= 0xFF00 and code <= 0xFFEF) or (code >= 0x20000 and code <= 0x2FA1F)

func control_text(control: Control) -> String:
	if control is RichTextLabel:
		return (control as RichTextLabel).get_parsed_text()
	if control is Label or control is Button:
		return str(control.text)
	return ""

func control_font(control: Control) -> Font:
	return control.get_theme_font("normal_font" if control is RichTextLabel else "font")

func control_font_size(control: Control) -> int:
	return control.get_theme_font_size("normal_font_size" if control is RichTextLabel else "font_size")

func text_width(control: Control, text: String) -> float:
	var font := control_font(control)
	var size := control_font_size(control)
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	return widest

func style_margins(control: Control) -> Vector2:
	var style: StyleBox = control.get_theme_stylebox("normal")
	if style == null:
		return Vector2.ZERO
	return Vector2(style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT),
		style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM))

func clip_ancestor(control: Control) -> Control:
	var node := control.get_parent()
	while node is Control:
		if (node as Control).clip_contents or node is ScrollContainer:
			return node
		node = node.get_parent()
	return null

func in_scroll(control: Control, stop: Node) -> bool:
	var node := control.get_parent()
	while node != null and node != stop:
		if node is ScrollContainer:
			return true
		node = node.get_parent()
	return false

func readable_visible(control: Control) -> bool:
	if not control.is_visible_in_tree() or control.size.x < 1 or control.size.y < 1:
		return false
	var alpha := 1.0
	var node: Node = control
	while node is CanvasItem:
		alpha *= (node as CanvasItem).modulate.a * (node as CanvasItem).self_modulate.a
		node = node.get_parent()
	return alpha >= 0.5

## Approximate rect actually covered by glyphs (logical coords).
func ink_rect(control: Control) -> Rect2:
	var rect := control.get_global_rect()
	var text := control_text(control)
	if text.strip_edges().is_empty() or control is RichTextLabel:
		return rect
	var font := control_font(control)
	var size := control_font_size(control)
	var margins := style_margins(control)
	var width := minf(text_width(control, text), maxf(rect.size.x - margins.x, 1.0))
	var lines := 1
	if control is Label:
		lines = maxi(1, (control as Label).get_visible_line_count())
	var height := minf(font.get_height(size) * lines, rect.size.y)
	var align := HORIZONTAL_ALIGNMENT_CENTER
	var valign := VERTICAL_ALIGNMENT_CENTER
	if control is Label:
		align = (control as Label).horizontal_alignment
		valign = (control as Label).vertical_alignment
	elif control is Button:
		align = (control as Button).alignment
	if control is Label and (control as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
		width = maxf(rect.size.x - margins.x, 1.0)
	var x := rect.position.x + margins.x * 0.5
	match align:
		HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_FILL:
			x = rect.position.x + (rect.size.x - width) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			x = rect.end.x - margins.x * 0.5 - width
	var y := rect.position.y
	match valign:
		VERTICAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_FILL:
			y = rect.position.y + (rect.size.y - height) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM:
			y = rect.end.y - height
	return Rect2(x, y, width, height)

func luminance(color: Color) -> float:
	var c := color.srgb_to_linear()
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

## Contrast ratio between the brightest and darkest rendered pixels in the ink box.
func rendered_contrast(area: Rect2) -> float:
	if image == null:
		return -1.0
	var px := Rect2(area.position * image_scale, area.size * image_scale)
	px = px.intersection(Rect2(Vector2.ZERO, Vector2(image.get_size())))
	if px.size.x < 2 or px.size.y < 2:
		return -1.0
	var step_x := maxf(1.0, px.size.x / 64.0)
	var step_y := maxf(1.0, px.size.y / 16.0)
	var low := 2.0
	var high := -1.0
	var y := px.position.y
	while y < px.end.y:
		var x := px.position.x
		while x < px.end.x:
			var value := luminance(image.get_pixel(int(x), int(y)))
			low = minf(low, value)
			high = maxf(high, value)
			x += step_x
		y += step_y
	return (high + 0.05) / (low + 0.05)

# ------------------------------------------------------------- text auditing

func audit_text(scope: String, owner: Control, viewport: Rect2, stats: Dictionary) -> void:
	var controls: Array[Control] = []
	if owner is Label or owner is Button or owner is RichTextLabel:
		controls.append(owner)
	for kind in ["Label", "Button", "RichTextLabel"]:
		for node in owner.find_children("*", kind, true, false):
			if node is Control:
				controls.append(node)
	for control in controls:
		if not readable_visible(control):
			continue
		var text := control_text(control)
		if text.strip_edges().is_empty():
			continue
		var name := "%s/%s「%s」" % [scope, control.name, text.replace("\n", "⏎").left(24)]
		stats.texts += 1
		var font := control_font(control)
		var size := control_font_size(control)
		var has_cjk := false
		var missing := ""
		var missing_symbol := ""
		for i in text.length():
			var code := text.unicode_at(i)
			if code <= 32 or code == 0xFE0F:
				continue
			var cjk := is_cjk(code)
			has_cjk = has_cjk or cjk
			if not font.has_char(code):
				if cjk:
					missing += char(code)
				elif missing_symbol.length() < 8:
					missing_symbol += char(code)
		expect(missing.is_empty(), name + " CJK glyphs present in UI font (missing: %s)" % missing)
		if not missing_symbol.is_empty():
			warn(name + " symbol relies on system fallback: " + missing_symbol)
		if has_cjk:
			stats.cjk_texts += 1
			stats.min_cjk_font = mini(int(stats.min_cjk_font), size)
			expect(size >= MIN_CJK_FONT, "%s Chinese font size %d >= %d" % [name, size, MIN_CJK_FONT])
			if size < COMFORT_CJK_FONT:
				warn("%s Chinese font size %d below comfort %d" % [name, size, COMFORT_CJK_FONT])
		var scale := control.get_global_transform_with_canvas().get_scale()
		expect(absf(scale.x - 1.0) < 0.01 and absf(scale.y - 1.0) < 0.01,
			"%s rendered unscaled (scale %s) for crisp glyphs" % [name, scale])
		var gp := control.get_global_rect().position
		if absf(gp.x - roundf(gp.x)) > 0.01 or absf(gp.y - roundf(gp.y)) > 0.01:
			stats.fractional += 1
		# --- cutoff
		var rect := control.get_global_rect()
		var margins := style_margins(control)
		var needed := text_width(control, text)
		var available := rect.size.x - margins.x
		if control is Button:
			var button := control as Button
			if button.icon != null and not button.expand_icon:
				var icon_width := button.icon.get_width()
				var max_icon_width := button.get_theme_constant("icon_max_width")
				if max_icon_width > 0:
					icon_width = mini(icon_width, max_icon_width)
				available -= icon_width + button.get_theme_constant("h_separation")
			expect(needed <= available + 1.0, "%s button text fits (%.0f > %.0f)" % [name, needed, available])
		elif control is Label:
			var label := control as Label
			if label.visible_ratio < 1.0:
				continue
			if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
				if label.clip_text or label.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
					expect(needed <= available + 1.0, "%s not truncated (%.0f > %.0f)" % [name, needed, available])
			expect(label.get_visible_line_count() >= label.get_line_count(),
				"%s all %d lines visible (%d shown)" % [name, label.get_line_count(), label.get_visible_line_count()])
		elif control is RichTextLabel:
			var rich := control as RichTextLabel
			if not rich.scroll_active and not rich.fit_content:
				expect(rich.get_content_height() <= rich.size.y + 1.0,
					"%s rich text not cut (%d > %.0f)" % [name, rich.get_content_height(), rich.size.y])
		var ink := ink_rect(control)
		if control is Label and (control as Label).autowrap_mode == TextServer.AUTOWRAP_OFF and needed > available:
			ink.size.x = needed  # spilled text past its own rect
		var clip := clip_ancestor(control)
		var bounds := viewport
		while clip != null:
			bounds = bounds.intersection(clip.get_global_rect())
			clip = clip_ancestor(clip)
		var scrolled := in_scroll(control, owner)
		if scrolled:
			# Vertical scroll position is a user choice; only horizontal cut is a defect,
			# and only for text currently within the scroll's vertical window.
			if bounds.has_area() and ink.end.y > bounds.position.y and ink.position.y < bounds.end.y:
				expect(ink.position.x >= bounds.position.x - 1.0 and ink.end.x <= bounds.end.x + 1.0,
					"%s horizontally inside scroll/viewport %s vs %s" % [name, ink, bounds])
		else:
			expect(bounds.grow(1.0).encloses(ink), "%s ink inside clip/viewport %s vs %s" % [name, ink, bounds])
		# --- rendered contrast
		var visible_ink := ink.intersection(bounds)
		if scrolled and visible_ink.size.y < ink.size.y - 1.0:
			continue # At a scroll edge, a glyph may be only partially visible.
		var contrast := rendered_contrast(visible_ink)
		if contrast >= 0.0:
			stats.measured += 1
			stats.min_contrast = minf(float(stats.min_contrast), contrast)
			var disabled := control is Button and (control as Button).disabled
			var floor_value := MIN_CONTRAST_DISABLED if disabled else MIN_CONTRAST
			expect(contrast >= floor_value, "%s rendered contrast %.2f >= %.2f" % [name, contrast, floor_value])
			if contrast < COMFORT_CONTRAST and not disabled:
				warn("%s rendered contrast %.2f below %.1f" % [name, contrast, COMFORT_CONTRAST])

func new_stats() -> Dictionary:
	return {"texts": 0, "cjk_texts": 0, "min_cjk_font": 999, "measured": 0, "min_contrast": 99.0, "fractional": 0}

# --------------------------------------------------------------- HUD checks

func hud_blocks() -> Array:
	var blocks := []
	var title: Control = app.hud.find_child("RegionTitle", true, false)
	for entry in [
		["location", title.get_parent() if title != null else null],
		["tracker", app.preview_tracker],
		["calendar", app.preview_top],
		["forecast_tip", app.hud.get_node_or_null("WeatherForecastTip")],
		["selected_tool", app.selected_label],
		["toolbar", app.preview_toolbar],
		["shortcuts", app.hud.get_node_or_null("LifeShortcuts")],
		["toast", app.toast],
	]:
		var control = entry[1]
		if is_instance_valid(control) and control is Control and readable_visible(control):
			var rect: Rect2 = ink_rect(control) if control is Label else control.get_global_rect()
			if control is Label and str(control.text).strip_edges().is_empty():
				continue
			blocks.append([entry[0], control, rect])
	return blocks

func check_hud(label: String, viewport: Rect2) -> void:
	await settle()
	expect(app.modal == null, label + " no modal over HUD")
	var stats := new_stats()
	audit_text("hud", app.hud, viewport, stats)
	if is_instance_valid(app.toast) and app.toast.get_parent() != app.hud and app.toast.is_visible_in_tree():
		audit_text("toast", app.toast, viewport, stats)
	var blocks := hud_blocks()
	var names := []
	for block in blocks:
		names.append(block[0])
	for wanted in ["location", "calendar", "toolbar"]:
		expect(wanted in names, "%s HUD shows %s" % [label, wanted])
	var arrival := Opening.card(app)
	if is_instance_valid(arrival) and arrival.is_visible_in_tree():
		var arrival_rect := arrival.get_global_rect()
		expect(viewport.encloses(arrival_rect), "%s arrival card inside viewport" % label)
		expect(not arrival_rect.intersects(app.preview_top.get_global_rect()), "%s arrival card clears the calendar" % label)
	var play := Rect2(viewport.get_center() - viewport.size * 0.18, viewport.size * 0.36)
	for i in blocks.size():
		var a: Rect2 = blocks[i][2]
		expect(viewport.grow(0.5).encloses(a), "%s %s inside viewport %s" % [label, blocks[i][0], a])
		expect(not a.intersects(play), "%s %s clear of central play area %s vs %s" % [label, blocks[i][0], a, play])
		for j in range(i + 1, blocks.size()):
			var b: Rect2 = blocks[j][2]
			var overlap := a.intersection(b)
			expect(overlap.size.x <= 1.0 or overlap.size.y <= 1.0,
				"%s %s does not overlap %s (%s)" % [label, blocks[i][0], blocks[j][0], overlap])
	report.sizes[current_size][label] = stats
	shot(label)

# ------------------------------------------------------------- panel checks

func check_panel(label: String, viewport: Rect2) -> void:
	await settle()
	var panel: Control = app.modal
	expect(is_instance_valid(panel), label + " opened")
	if not is_instance_valid(panel):
		return
	var rect := panel.get_global_rect()
	expect(viewport.grow(0.5).encloses(rect), "%s panel inside viewport %s" % [label, rect])
	var stats := new_stats()
	audit_text(label, panel, viewport, stats)
	# HUD text that stays visible over a panel must not be covered by it.
	for block in hud_blocks():
		if block[1] == app.toast:
			continue
		var hud_rect: Rect2 = block[2]
		var overlap := hud_rect.intersection(rect)
		expect(overlap.size.x <= 1.0 or overlap.size.y <= 1.0,
			"%s panel does not cover visible HUD %s" % [label, block[0]])
	report.sizes[current_size][label] = stats
	shot(label)

func check_inventory(viewport: Rect2) -> void:
	app._inventory()
	await check_panel("inventory", viewport)
	var panel = app.modal
	if not is_instance_valid(panel) or not panel.has_method("select_category"):
		expect(false, "inventory is the grid InventoryPanel (needs --village-art-preview)")
		return
	var longest := ""
	for id in World.NAMES:
		if longest.is_empty() or str(World.NAMES[id]).length() > str(World.NAMES[longest]).length():
			longest = id
	for index in panel.tabs.size():
		panel.select_category(index)
		await settle()
		var stats := new_stats()
		audit_text("inventory_tab%d" % index, panel, viewport, stats)
		report.sizes[current_size]["inventory_tab%d" % index] = stats
		if index == 0:
			shot("inventory-tab0")
	panel.select_category(0)
	if panel.slots.has(longest):
		panel.select_item(longest)
		await settle()
		var stats := new_stats()
		audit_text("inventory_longest", panel, viewport, stats)
		expect(str(panel.detail_name.text).contains(str(World.NAMES[longest])) or not panel.detail_name.is_visible_in_tree(),
			"inventory details show longest item name " + str(World.NAMES[longest]))
		report.sizes[current_size]["inventory_longest"] = stats
		shot("inventory-longest")
	app._notice("背包測試：已整理好「%s」等長名稱物品。" % World.NAMES[longest], true)
	await settle()
	var notice_stats := new_stats()
	audit_text("inventory_notice", panel, viewport, notice_stats)
	report.sizes[current_size]["inventory_notice"] = notice_stats
	app._close_modal()
	await settle()

# --------------------------------------------------------------------- run

func fixture() -> void:
	world = World.new()
	world.add_player(PLAYER, "測試島民長名字")
	var person: Dictionary = world.state.players[PLAYER]
	person.coins = 9999999
	for id in World.NAMES:
		person.inventory[id] = 999
	world.state.time = 1440 * 87 + 23 * 60 + 59  # late on a long-running day for widest status text

func run() -> void:
	create_timer(150.0).timeout.connect(func():
		push_error("FAIL timeout")
		quit(1))
	output_dir = user_arg("hud-readability-output")
	var scope := user_arg("scope")
	if not output_dir.is_empty():
		if output_dir.begins_with("res://") or output_dir.begins_with("user://") or not output_dir.is_absolute_path():
			push_error("FAIL --hud-readability-output must be an absolute OS path outside res:// and user://")
			print("HUD_TEXT_READABILITY_TESTS checks=0 failures=1")
			quit(1)
			return
		if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
			push_error("FAIL cannot create " + output_dir)
			quit(1)
			return
	if DisplayServer.get_name() == "headless":
		push_error("FAIL native renderer required: run without --headless for pixel metrics")
		print("HUD_TEXT_READABILITY_TESTS checks=0 failures=1")
		quit(1)
		return
	app = load("res://main.tscn").instantiate()
	app.village_art_preview = true
	root.add_child(app)
	app.set_process(false)
	app.sound.volume = 0.0
	var scale_arg := user_arg("text-scale")
	if not scale_arg.is_empty():
		expect(scale_arg.is_valid_int() and int(scale_arg) in range(4), "valid text scale index")
		app.sound.preferred_text_scale = clampi(int(scale_arg), 0, 3)
		app._apply_font_scale_tree()
	fixture()
	if scope == "hud-full":
		world.state.chapter_one.shipped = true
		var bag: Dictionary = world.state.players[PLAYER].inventory
		for portable in ["tiller", "seeder", "harvester"]:bag.erase(portable)
	app.session.snapshot = world.state
	app.session.world = world
	app.session.set_physics_process(false)
	app.session.own_id = PLAYER
	app.session.peers[1] = app.session.own_id
	app._entered()
	app._refresh_hud()
	report["font"] = {"resolved": preload("res://scripts/island_type.gd").regular().get_font_name(),
		"scale": app.font_scale_factor(),
		"reduced_motion": app.sound.reduced_motion}
	for size in SIZES:
		current_size = "%dx%d" % [size.x, size.y]
		report.sizes[current_size] = {}
		root.content_scale_size = size
		root.size = size
		await settle()
		var viewport := root.get_visible_rect()
		expect(Vector2i(viewport.size) == size, "logical viewport matches " + current_size)
		if image != null:
			expect(absf(image_scale.x - image_scale.y) < 0.01, current_size + " uniform screenshot scale " + str(image_scale))
		app._refresh_hud()
		if scope == "hud-full":
			var shortcuts: Control = app.hud.get_node("LifeShortcuts")
			var total_tools := int(app.tool_buttons.filter(func(button): return button.visible).size())
			expect(total_tools == 8, "%s shows all eight basic tools" % current_size)
			for button: Button in shortcuts.get_children():
				expect(button.visible and button.size.x >= 44.0, "%s has a visible 44px shortcut target" % current_size)
				expect(button.get_global_rect().encloses(button.get_node("ShortcutTitle").get_global_rect()),
					"%s shortcut label stays inside the button" % current_size)
		await check_hud("hud", viewport)
		app._notice("已把「%s」放進背包，記得到渡口看看下一步。" % World.NAMES.values()[0], true)
		await check_hud("hud_toast", viewport)
		app.toast.visible = false
		if scope in ["hud", "hud-full"]:
			continue
		if scope not in ["build", "help"]:
			await check_inventory(viewport)
		for entry in PANELS:
			if scope == "everyday" and entry[0] != "_settings_menu":
				continue
			if scope == "build" and entry[0] != "_build_menu":
				continue
			if scope == "help" and entry[0] != "_help":
				continue
			if not app.has_method(entry[0]):
				warn("panel %s not available" % entry[0])
				continue
			app.callv(entry[0], entry[1])
			await check_panel(entry[0], viewport)
			if scope == "help":
				var advanced: Label
				for node in app.modal.find_children("*", "Label", true, false):
					if node.text == "做大一點的工坊":advanced = node
				expect(advanced != null, "Guide has a separate workshop section")
				if advanced != null:
					var guide_scroll := clip_ancestor(advanced)
					if guide_scroll is ScrollContainer:
						guide_scroll.set_v_scroll(int(advanced.position.y))
					await check_panel("help_automation", viewport)
			if scope == "build":
				var long_name := app.modal.find_child("BuildSlot_keepsake_xinghe_0", true, false) as Button
				expect(long_name != null, "Build folio includes the long-name keepsake")
				if long_name != null:
					long_name.pressed.emit()
					var shelf := clip_ancestor(long_name)
					if shelf is ScrollContainer:
						await process_frame
						shelf.ensure_control_visible(long_name)
					await check_panel("build_long_name", viewport)
					var title := app.modal.find_child("BuildTitle", true, false) as Label
					expect(title != null and title.text == World.BUILD.keepsake_xinghe.name,
						"The selected keepsake retains its full title")
					var place := app.modal.find_child("BuildPlace", true, false) as Button
					var body_clip := clip_ancestor(place)
					expect(body_clip == null or body_clip.get_global_rect().grow(1.0).encloses(place.get_global_rect()),
						"The recipe button remains fully visible with the long title")
			app._close_modal()
			await process_frame
		expect(app.modal == null, current_size + " all panels closed")
	report["summary"] = {"checks": checks, "failures": failures, "warnings": warnings,
		"pixel_metrics": image != null}
	if not output_dir.is_empty():
		var file := FileAccess.open(output_dir.path_join("report.json"), FileAccess.WRITE)
		expect(file != null, "report written")
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
	app.playing = false
	app.queue_free()
	await process_frame
	print("HUD_TEXT_READABILITY warnings=%d pixel_metrics=%s output=%s" % [warnings, image != null, output_dir])
	print("HUD_TEXT_READABILITY_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 and checks > 0 else 1)
