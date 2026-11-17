extends SceneTree
## Native UI test for the 家園工坊 build folio (life_modal_layout = "build_folio").
## FIXTURE, not human play: the tester lives in a local World that is pushed to the
## app as a snapshot; the app is entered through its real _entered() /
## _state_changed() / _refresh_hud() path. Everything else is driven through the
## folio's public controls (tab / entry / place / HouseCheck / HouseBack signals).
## Optional: --qa-preview [--qa-output=DIR] saves folio PNGs per extent.

const World = preload("res://scripts/world.gd")
const HouseUI = preload("res://scripts/house_ui.gd")
const BuildThumbnail = preload("res://scripts/pixel_build_thumbnail.gd")
const EXTENTS := [Vector2i(1024, 640), Vector2i(1280, 800)]
const TABS := ["全部", "基礎", "家具", "生活"]
const LAYOUT := "build_folio"
const MAX_SIZE := Vector2(920, 590)
const NODE_CAP := 6000

var checks := 0
var failures := 0
var app
var world
var entered := false
var number_cache := {}

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

# --- bounded tree helpers -------------------------------------------------

## Breadth-first descendants of `node` (excluding itself), capped so a broken
## tree can never make the test walk forever.
func descendants(node: Node, cap: int = NODE_CAP) -> Array[Node]:
	var result: Array[Node] = []
	if node == null:
		return result
	var queue: Array[Node] = [node]
	var head := 0
	while head < queue.size() and result.size() < cap:
		var current: Node = queue[head]
		head += 1
		for child in current.get_children():
			result.append(child)
			queue.append(child)
			if result.size() >= cap:
				break
	return result

func text_of(node: Node) -> String:
	var parts := PackedStringArray()
	if node == null:
		return ""
	for d in [node] + descendants(node, 400):
		if (d is Label or d is Button) and d.is_visible_in_tree() and not str(d.text).is_empty():
			parts.append(str(d.text))
	return "\n".join(parts)

func folio_node(node_name: String) -> Control:
	if not is_instance_valid(app.modal):
		return null
	return app.modal.find_child(node_name, true, false) as Control

func has_number(text: String, value: int) -> bool:
	if not number_cache.has(value):
		var regex := RegEx.new()
		regex.compile("(?<!\\d)%d(?!\\d)" % value)
		number_cache[value] = regex
	return number_cache[value].search(text) != null

# --- folio queries ---------------------------------------------------------

func tab(label_text: String) -> Button:
	var shelf := folio_node("BuildShelf")
	for d in descendants(app.modal):
		if d is Button and d.is_visible_in_tree() and d.text == label_text and (shelf == null or not shelf.is_ancestor_of(d)):
			return d
	return null

func thumbnail_in(entry: Node) -> Node:
	for d in descendants(entry, 64):
		var script: Script = d.get_script()
		if script != null and (script == BuildThumbnail or script.get_base_script() == BuildThumbnail):
			return d
	return null

func kind_of(entry: Button) -> String:
	var thumb := thumbnail_in(entry)
	if thumb != null and World.BUILD.has(str(thumb.get("kind"))):
		return str(thumb.get("kind"))
	return ""

## Visible shelf entries on the current page: kind -> Array[Button].
func shelf_entries() -> Dictionary:
	var result := {}
	var shelf := folio_node("BuildShelf")
	if shelf == null:
		return result
	for d in descendants(shelf):
		if d is Button and d.is_visible_in_tree():
			var kind := kind_of(d)
			if kind != "":
				if not result.has(kind):
					result[kind] = []
				result[kind].append(d)
	return result

func recipe_text() -> String:
	return text_of(folio_node("BuildRecipe"))

func place_button() -> Button:
	return folio_node("BuildPlace") as Button

func press_tab(label_text: String) -> Dictionary:
	var button := tab(label_text)
	expect(button != null, "tab %s exists" % label_text)
	if button == null:
		return {}
	button.pressed.emit()
	await process_frame
	return shelf_entries()

## Selects a recipe through its shelf entry, switching to 全部 first if needed.
func select_recipe(kind: String) -> bool:
	var entries := shelf_entries()
	if not entries.has(kind):
		entries = await press_tab(TABS[0])
	if not entries.has(kind):
		expect(false, "%s reachable from the 全部 tab" % kind)
		return false
	entries[kind][0].pressed.emit()
	await process_frame
	return true

## Smallest visible row in BuildRecipe that shows the material with held and needed counts.
func count_row(item: String, held: int, need: int) -> bool:
	var recipe := folio_node("BuildRecipe")
	if recipe == null:
		return false
	for d in descendants(recipe, 600):
		if not (d is Control and d.is_visible_in_tree()):
			continue
		var row_text := text_of(d)
		if row_text.length() > 60 or not has_number(row_text, held) or not has_number(row_text, need):
			continue
		if row_text.contains(World.NAMES[item]):
			return true
	return false

# --- fixture ----------------------------------------------------------------

func publish() -> void:
	app.session.snapshot = world.region_snapshot("home")
	if not entered:
		app._entered()
		entered = true
	app._state_changed(app.session.snapshot, app.session.own_id)
	app._refresh_hud()

func set_bag(values: Dictionary) -> void:
	for item in values:
		world.state.players.tester.inventory[item] = values[item]
	publish()
	await process_frame

func open_folio(case_name: String) -> void:
	app._build_menu()
	for frame in 4:
		await process_frame
	expect(is_instance_valid(app.modal) and app.modal.get_meta("life_modal_layout", "") == LAYOUT,
		"%s: build menu opens the build_folio layout" % case_name)

func settle() -> void:
	for frame in 4:
		await process_frame

# --- checks ------------------------------------------------------------------

func verify_structure(case_name: String) -> void:
	if not is_instance_valid(app.modal):
		expect(false, "%s: folio open" % case_name)
		return
	expect(app.modal.get_meta("catalog", false), "%s: still a catalog modal" % case_name)
	var folio := folio_node("BuildFolio")
	var shelf := folio_node("BuildShelf")
	var recipe := folio_node("BuildRecipe")
	var place := place_button()
	expect(folio != null and shelf != null and recipe != null and place != null, "%s: BuildFolio/BuildShelf/BuildRecipe/BuildPlace present" % case_name)
	if folio == null or shelf == null or recipe == null or place == null:
		return
	expect(folio.is_ancestor_of(shelf) and folio.is_ancestor_of(recipe) and folio.is_ancestor_of(place), "%s: shelf, recipe and place live in the folio" % case_name)
	expect(not shelf.is_ancestor_of(recipe) and not recipe.is_ancestor_of(shelf), "%s: shelf and recipe page are separate" % case_name)
	for label_text in TABS:
		expect(tab(label_text) != null, "%s: tab %s present" % [case_name, label_text])
	var house: Button = folio_node("HouseCheck") as Button
	expect(house != null and house.is_visible_in_tree() and not house.disabled, "%s: HouseCheck entry present and enabled" % case_name)

func verify_tabs() -> void:
	var all_kinds: Array = World.BUILD.keys()
	var seen := {}
	var sub_owner := {}
	for index in TABS.size():
		var label_text: String = TABS[index]
		var entries: Dictionary = await press_tab(label_text)
		var button := tab(label_text)
		expect(button != null and (not button.toggle_mode or button.button_pressed), "tab %s shows as active after press" % label_text)
		for other in TABS:
			var other_button := tab(other)
			if other != label_text and other_button != null and other_button.toggle_mode:
				expect(not other_button.button_pressed, "tab %s inactive while %s active" % [other, label_text])
		expect(not entries.is_empty(), "tab %s lists recipes" % label_text)
		for kind in entries:
			expect(entries[kind].size() == 1, "tab %s lists %s once" % [label_text, kind])
			seen[kind] = true
			if index > 0:
				expect(not sub_owner.has(kind), "%s appears in exactly one category tab (also in %s)" % [kind, sub_owner.get(kind, "")])
				sub_owner[kind] = label_text
		if index == 0:
			expect(entries.size() == all_kinds.size(), "全部 lists every World.BUILD recipe (%d/%d)" % [entries.size(), all_kinds.size()])
		# Every entry on the page is actually selectable through its own signal.
		for kind in entries:
			entries[kind][0].pressed.emit()
			await process_frame
			expect(recipe_text().contains(World.BUILD[kind].name), "tab %s: selecting %s shows its recipe page" % [label_text, kind])
			expect(tab(label_text) != null and shelf_entries().has(kind), "tab %s: selecting %s keeps the tab" % [label_text, kind])
	for kind in all_kinds:
		expect(seen.has(kind), "%s reachable through the four tabs" % kind)
		expect(sub_owner.has(kind), "%s sorted into 基礎/家具/生活" % kind)
	expect(sub_owner.get("floor", "") == "基礎" and sub_owner.get("bed", "") == "家具" and sub_owner.get("sprinkler", "") == "生活",
		"floor/bed/sprinkler keep their existing categories")
	await press_tab(TABS[0])

func verify_counts() -> void:
	var recipe: Dictionary = World.BUILD.bench
	var wood_need := int(recipe.wood)
	var stone_need := int(recipe.stone)
	await set_bag({"wood": 7, "stone": 3})
	var found: bool = await select_recipe("bench")
	if not found:
		return
	expect(count_row("wood", 7, wood_need) and count_row("stone", 3, stone_need), "bench shows held/required from the snapshot (7/%d, 3/%d)" % [wood_need, stone_need])
	var place := place_button()
	expect(place != null and not place.disabled, "bench short on materials is still selectable")
	# A new snapshot while the folio stays open updates the counts in place.
	var modal_before = app.modal
	await set_bag({"wood": 26, "stone": 9})
	expect(app.modal == modal_before and recipe_text().contains(recipe.name), "snapshot refresh keeps the folio and selected recipe")
	expect(count_row("wood", 26, wood_need) and count_row("stone", 9, stone_need), "counts update to 26/%d and 9/%d" % [wood_need, stone_need])
	expect(not count_row("wood", 7, wood_need), "stale wood count replaced")
	expect(place_button() != null and not place_button().disabled, "bench with enough materials selectable")

func verify_locked() -> void:
	world.state.players.tester.erase("stories")
	publish()
	await process_frame
	var found: bool = await select_recipe("sofa")
	if not found:
		return
	var place := place_button()
	expect(place != null and place.disabled, "locked sofa plan cannot be chosen")
	expect(recipe_text().contains(World.BUILD.sofa.name), "locked plan still shows its recipe page")
	var mine: Dictionary = app.session.snapshot.get("mine_depths", {})
	if int(mine.get("unlocked", 1)) < 4:
		await select_recipe("waterworks")
		expect(place_button() != null and place_button().disabled, "waterworks locked before the mine pump work")
	# Unlocking through the snapshot enables the plan without reopening.
	world.state.players.tester["stories"] = {"aru": 4}
	publish()
	await process_frame
	await select_recipe("sofa")
	expect(place_button() != null and not place_button().disabled, "sofa becomes selectable once unlocked in the snapshot")
	world.state.players.tester.erase("stories")
	publish()
	await process_frame

func verify_sample_cost() -> void:
	world.state.players.tester["stories"]={"bobo":3}
	await set_bag({"wood":100,"stone":100,"gold_sample":0})
	await select_recipe("ore_display")
	var required:int=World.BUILD.ore_display.gold_sample
	expect(count_row("gold_sample",0,required),"display includes its gold sample cost")
	expect(not place_button().disabled and place_button().text=="材料不足，仍可選擇","missing sample remains selectable but explicitly short")
	await set_bag({"wood":100,"stone":100,"gold_sample":required})
	expect(count_row("gold_sample",required,required) and place_button().text=="選擇配方","sample arrival refreshes all-material affordability")
	await capture("sample")
	await select_recipe("waterworks")
	await capture("machine-locked")
	await set_bag({"wood":26,"stone":9,"fiber":10})

func verify_select_short() -> void:
	await set_bag({"wood": 5})
	expect(int(World.BUILD.chest.wood) > 5, "fixture: chest needs more wood than held")
	var found: bool = await select_recipe("chest")
	if not found:
		return
	var place := place_button()
	expect(place != null and not place.disabled, "unlocked chest without materials is still selectable")
	if place == null or place.disabled:
		return
	app.building = "floor"
	app.selected = "hoe"
	var state_before: Dictionary = world.state.duplicate(true)
	var snapshot_before: Dictionary = app.session.snapshot.duplicate(true)
	place.pressed.emit()
	await process_frame
	expect(app.building == "chest" and app.selected == "build", "place selects the chest recipe with the build tool")
	expect(app.modal == null, "place closes the folio")
	expect(world.state == state_before and app.session.snapshot == snapshot_before, "choosing a recipe never mutates the World or snapshot")

func verify_house_round_trip() -> void:
	await open_folio("house")
	var house: Button = folio_node("HouseCheck") as Button
	if house == null:
		expect(false, "HouseCheck present for round trip")
		return
	house.pressed.emit()
	await settle()
	expect(is_instance_valid(app.modal) and app.modal.get_meta("life_modal_layout", "") == HouseUI.LAYOUT, "HouseCheck opens the house check")
	var back: Button = folio_node("HouseBack") as Button
	expect(back != null, "house check offers HouseBack")
	if back != null:
		back.pressed.emit()
		await settle()
	expect(is_instance_valid(app.modal) and app.modal.get_meta("life_modal_layout", "") == LAYOUT and folio_node("BuildFolio") != null,
		"HouseBack returns to the build folio")
	verify_structure("after house back")

func verify_thumbnails(case_name: String) -> void:
	var shelf := folio_node("BuildShelf")
	var entries := shelf_entries()
	expect(entries.size() == World.BUILD.size(), "%s: 全部 page shows all entries" % case_name)
	var shelf_rect := shelf.get_global_rect() if shelf != null else Rect2()
	for kind in entries:
		var entry: Button = entries[kind][0]
		var rect := entry.get_global_rect().grow(0.5)
		# Horizontal scrolling is not part of the folio: slots stay within shelf width.
		expect(rect.position.x >= shelf_rect.position.x - 0.5 and rect.end.x <= shelf_rect.end.x + 0.5, "%s: %s slot within shelf width" % [case_name, kind])
		var thumb: CanvasItem = thumbnail_in(entry) as CanvasItem
		if thumb == null:
			expect(false, "%s: %s slot has a build thumbnail" % [case_name, kind])
			continue
		var scale := thumb.get_global_transform().get_scale()
		var whole := is_equal_approx(scale.x, roundf(scale.x)) and is_equal_approx(scale.x, scale.y) and scale.x >= 1.0
		expect(whole, "%s: %s thumbnail at integer scale (%s)" % [case_name, kind, scale])
		# The control framing the thumbnail (or the slot itself) must hold it inside the slot.
		var frame: Control = thumb.get_parent() as Control
		# Actual draw extents from the world sprite renderers, including machine overhang.
		var sprite_rect:=Rect2(0,0,32,48)
		if kind in ["waterworks","ore_display"]:sprite_rect=Rect2(-8,0,48,48)
		elif kind=="mine_drill":sprite_rect=Rect2(-8,8,48,48)
		var drawn_rect:Rect2=thumb.get_global_transform()*sprite_rect
		var width := sprite_rect.size.x * scale.x
		if frame != null and frame != entry:
			expect(rect.encloses(frame.get_global_rect()), "%s: %s thumbnail frame fits its slot" % [case_name, kind])
			expect(frame.size.x + 0.5 >= width, "%s: %s frame wide enough for the scaled thumbnail" % [case_name, kind])
		expect(rect.encloses(drawn_rect), "%s: %s complete sprite drawn inside its slot" % [case_name, kind])

func verify_layout(case_name: String) -> void:
	var modal_before = app.modal
	var selected_name: String = World.BUILD.bench.name
	await press_tab(TABS[0])
	await select_recipe("bench")
	for extent in EXTENTS + [EXTENTS[0]]:
		root.size = extent
		await settle()
		expect(app.modal == modal_before and is_instance_valid(app.modal), "%s: resize to %s keeps the same folio" % [case_name, extent])
		if not is_instance_valid(app.modal):
			return
		expect(app.modal.get_meta("life_modal_layout", "") == LAYOUT, "%s: layout hook kept at %s" % [case_name, extent])
		var bounds := root.get_visible_rect()
		var modal_rect: Rect2 = app.modal.get_global_rect()
		expect(bounds.encloses(modal_rect), "%s: folio fits %s" % [case_name, extent])
		expect(modal_rect.size.x <= MAX_SIZE.x + 0.5 and modal_rect.size.y <= MAX_SIZE.y + 0.5, "%s: folio capped at 920x590 at %s (%s)" % [case_name, extent, modal_rect.size])
		var outer: ScrollContainer = folio_node("ModalScroll") as ScrollContainer
		var area := outer.get_global_rect() if outer != null else modal_rect
		for node_name in ["BuildFolio", "BuildShelf", "BuildRecipe"]:
			var control := folio_node(node_name)
			expect(control != null and control.is_visible_in_tree() and modal_rect.grow(0.5).encloses(control.get_global_rect()), "%s: %s inside the folio at %s" % [case_name, node_name, extent])
		var reachable: Array[Control] = [place_button(), folio_node("HouseCheck")]
		for label_text in TABS:
			reachable.append(tab(label_text))
		for control in reachable:
			var shown := control != null and control.is_visible_in_tree()
			expect(shown and area.grow(0.5).encloses(control.get_global_rect()) and bounds.encloses(control.get_global_rect()),
				"%s: %s visible without scrolling at %s" % [case_name, control.name if control != null else "control", extent])
		expect(recipe_text().contains(selected_name), "%s: selection survives resize to %s" % [case_name, extent])
		verify_thumbnails("%s %s" % [case_name, extent])

func capture(case_name: String) -> void:
	if not "--qa-preview" in OS.get_cmdline_user_args():
		return
	var directory: String = app.arg_value("qa-output", "user://build-folio-qa")
	DirAccess.make_dir_recursive_absolute(directory)
	for extent in EXTENTS:
		root.size = extent
		for frame in 3:
			await process_frame
		app.toast_time = 0.0
		app.toast.hide()
		for frame in 30:
			if app.modal.modulate.a >= 1.0:
				break
			await process_frame
		await RenderingServer.frame_post_draw
		expect(app.playing and not app.menu.visible and is_instance_valid(app.modal) and app.modal.is_visible_in_tree(),
			"%s: capture shows the folio over the entered island at %s" % [case_name, extent])
		var image := root.get_texture().get_image()
		var path := directory.path_join("build-folio-%s-%dx%d.png" % [case_name, extent.x, extent.y])
		expect(image != null and image.save_png(path) == OK, "qa capture saved " + path)

func press_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	app._input(event)

func run() -> void:
	app = load("res://main.tscn").instantiate()
	app.village_art_preview = true
	root.add_child(app)
	app.set_process(false)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = EXTENTS[0]
	world = World.new()
	world.add_player("tester", "島民")
	app.session.set_physics_process(false)
	app.session.own_id = "tester"
	app.session.world = world
	app.session.peers[1] = "tester"
	publish()
	expect(app.playing and not app.menu.visible and app.hud.visible, "fixture entered the island through _entered()")

	await open_folio("open")
	verify_structure("open")
	await verify_tabs()
	var styles = preload("res://scripts/build_style_catalog.gd")
	for style_id: String in styles.style_ids():
		var label_text: String = styles.style(style_id).name
		var entries: Dictionary = await press_tab(label_text)
		expect(entries.size()==styles.kinds(style_id).size(),"Style lists only its catalog recipes")
		for kind: String in styles.kinds(style_id):
			expect(entries.has(kind),"Style exposes "+kind)
		expect(recipe_text().contains("搭配建議"),"Style recipe shows its design note")
	var inn_entries:=await press_tab("暖泉旅舍")
	var inn_order:=["inn_quilt_bed","inn_stone_footbath","inn_lattice_wardrobe","inn_fabric_screen","inn_tea_table",
		"spring_stone_bench","towel_rack","ceramic_eave_chime","warm_lamp_niche","inn_luggage_rack","spring_pebble_path","inn_welcome_sign"]
	expect(inn_entries.size()==inn_order.size(),"The inn page has exactly the twelve planned pieces")
	for index in inn_order.size():
		var kind:String=inn_order[index]
		expect(inn_entries.has(kind),"The inn page exposes "+kind)
		if not inn_entries.has(kind):continue
		var entry:Button=inn_entries[kind][0]
		expect(entry.get_index()==index,"Pieces are in the inn collection's plan order")
		entry.pressed.emit()
		await process_frame
		expect(recipe_text().contains(World.BUILD[kind].name),"The inn page opens the real recipe for "+kind)
	if inn_entries.has(World.INDUSTRY.FOOT_BATH):
		inn_entries[World.INDUSTRY.FOOT_BATH][0].pressed.emit()
		expect(place_button().disabled and recipe_text().contains("池邊的裂縫"),"The inn collection explains the locked bath")
		app.session.snapshot["resident_goals"]={"nuannuan":{"2":{"state":"done"}}}
		inn_entries[World.INDUSTRY.FOOT_BATH][0].pressed.emit()
		await capture("warm-springs-inn")
		place_button().pressed.emit()
		expect(app.building==World.INDUSTRY.FOOT_BATH and app.building_style.is_empty(),"The inn collection selects normal placement without applying another style")
		await open_folio("after inn selection")
	await press_tab("全部")
	await verify_counts()
	await verify_locked()
	await verify_sample_cost()
	await verify_layout("layout")
	await select_recipe("bed")
	await capture("bed")
	press_escape()
	await process_frame
	expect(app.modal == null, "Esc closes the folio")

	await open_folio("select")
	await verify_select_short()
	await verify_house_round_trip()
	finish()

func finish() -> void:
	if is_instance_valid(app):
		app._close_modal()
		app.queue_free()
	await process_frame
	print("BUILD_FOLIO_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
