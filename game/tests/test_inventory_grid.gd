extends SceneTree

const Slot = preload("res://scripts/item_slot.gd")
const World = preload("res://scripts/world.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)

func key(main: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	var previous: Control = main.modal
	main._input(event)
	if main.modal == previous:
		main._unhandled_input(event)

func layout_frames() -> void:
	await process_frame
	await process_frame

func collect_slots(parent: Node, visible_only: bool = false) -> Array[Button]:
	var found: Array[Button] = []
	for child in parent.get_children():
		if child is Slot and (not visible_only or child.is_visible_in_tree()):
			found.append(child)
		found.append_array(collect_slots(child, visible_only))
	return found

func check_layout(panel: Control, size: Vector2i) -> void:
	var bounds := panel.get_global_rect()
	for detail in [panel.detail_icon, panel.detail_name, panel.detail_count, panel.detail_use, panel.detail_value]:
		expect(detail.is_visible_in_tree() and bounds.encloses(detail.get_global_rect()), "item detail fits at %s" % size)
	var footer: Label
	for label in panel.find_children("*", "Label", true, false):
		if label.text.contains("Esc 返回"):
			footer = label
			break
	expect(footer != null and footer.is_visible_in_tree() and bounds.encloses(footer.get_global_rect()),
		"keyboard footer fits at %s" % size)
	expect(panel.scroller.get_global_rect().encloses(collect_slots(panel, true)[0].get_global_rect()),
		"first slot is fully visible in the grid at %s" % size)

func check_categories(main: Node, panel: Control, point: Vector2) -> void:
	var expected := [World.NAMES.keys(), ["orange_dye","fired_brick","woodwork_parts","rope","copper_ingot","iron_ore","iron_ingot","hardwood","crystal_sand", "ochre_earth", "vein_quartz", "warm_stone", "glass", "clay", "tea_jar", "tea_returned_jar", "tea_worn_jar", "tea_spent_jar", "wood", "stone", "fiber", "copper_ore", "copper_joint", "plank", "resin", "charcoal", "flour", "blue_dye", "sugar","cotton_cloth","wool_cloth"], [], [], []]
	for id in World.NAMES:
		if id.begins_with("quality_") and int(panel.inventory.get(id,0))==0:
			expected[0].erase(id)
			continue
		if id.ends_with("_seed") or id == "sapling":
			expected[2].append(id)
		elif World.CROPS.has(id) or World.FISH.has(id) or id in ["egg", "tea_leaf", "tea_light", "tea_deep"]:
			expected[3].append(id)
		elif id not in expected[1]:
			expected[4].append(id)
	expect(panel.tabs.size() == 5, "five category tabs exist")
	for index in range(panel.tabs.size()):
		panel.tabs[index].pressed.emit()
		await layout_frames()
		var ids := collect_slots(panel, true).map(func(slot): return slot.item_id)
		ids.sort()
		expected[index].sort()
		expect(ids == expected[index], "category %d contains exactly its items, including zeros" % index)
		expect(panel.tabs[index].button_pressed and not main._world_pointer_allowed(point),
			"category selection stays in the modal")
		key(main, KEY_M)
		expect(main.modal == panel, "map shortcut does not replace the inventory")
	panel.tabs[0].pressed.emit()
	await layout_frames()

func check_amount(slot: Button, amount: int) -> void:
	var label: Label = slot.quantity
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var text_width := font.get_string_size(str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	expect(label.text == str(amount) and label.get_line_count() == 1, "amount displays exactly %d" % amount)
	expect(label.size.x >= text_width and slot.get_global_rect().encloses(label.get_global_rect()),
		"amount %d fits inside its slot" % amount)

func check_icon_alpha(atlas: Image) -> void:
	if atlas == null or atlas.get_size() != Vector2i(192, 160):
		expect(false, "item PNG uses six by five 32x32 cells")
		return
	for index in range(30):
		var origin := Vector2i((index % 6) * 32, floori(index / 6.0) * 32)
		var corners_clear := true
		for corner in [Vector2i.ZERO, Vector2i(31, 0), Vector2i(0, 31), Vector2i(31, 31)]:
			corners_clear = corners_clear and atlas.get_pixelv(origin + corner).a == 0.0
		var central_transparent := 0
		var opaque := 0
		for y in range(2, 30):
			for x in range(2, 30):
				var alpha := atlas.get_pixelv(origin + Vector2i(x, y)).a
				opaque += int(alpha >= 0.95)
				if x >= 5 and x < 27 and y >= 5 and y < 27:
					central_transparent += int(alpha == 0.0)
		expect(corners_clear and central_transparent >= 20 and opaque >= 63,
			"atlas cell %02d has clear corners and usable interior alpha (%d clear, %d opaque)" %
			[index + 1, central_transparent, opaque])

func run() -> void:
	create_timer(10.0).timeout.connect(func(): quit(1))
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main.sound.volume = 0.0
	var world := World.new()
	world.add_player("inventory-grid-test", "島民")
	main.session.snapshot = world.state
	main.session.world = world
	main.session.set_physics_process(false)
	main.session.own_id = "inventory-grid-test"
	main.session.peers[1] = main.session.own_id
	main._entered()
	main._refresh_hud()
	expect(main.village_art_preview, "preview flag enabled")
	var hud_children: int = main.hud.get_child_count()
	for size in [Vector2i(1280, 800), Vector2i(1280, 720), Vector2i(1024, 640), Vector2i(1920, 1080)]:
		root.content_scale_size = size
		root.size = size
		await layout_frames()
		main.preview_tracker.visible = size.y == 720
		var hud_visibility: Array[bool] = []
		for control in main.preview_controls:
			hud_visibility.append(control.visible)
		var world_point := root.get_visible_rect().get_center()
		expect(main._world_pointer_allowed(world_point), "world targeting available at %s before Tab" % size)
		key(main, KEY_TAB)
		await layout_frames()
		var panel: Control = main.modal
		expect(is_instance_valid(panel), "Tab opens inventory at %s" % size)
		if not is_instance_valid(panel):
			continue
		expect(root.get_visible_rect().encloses(panel.get_global_rect()), "inventory fits %s: %s" % [size, panel.get_global_rect()])
		expect(not main.preview_tracker.visible, "inventory hides the underlying quest tracker")
		expect(not main._world_pointer_allowed(world_point), "inventory blocks world targeting")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = world_point
		main.action_clock = 0.0
		main._unhandled_input(click)
		expect(main.action_clock == 0.0, "open inventory rejects a world click")
		var slots := collect_slots(panel, true)
		var all_slots := collect_slots(panel, false)
		expect(all_slots.size() == World.NAMES.size(), "all item slots exist at %s" % size)
		expect(all_slots.all(func(slot):return slot.visible==(not slot.item_id.begins_with("quality_") or slot.count>0)), "only unheld quality tiers are hidden from the all-items tab")
		var saw_unheld:=false
		for slot in slots:
			if slot.count==0:saw_unheld=true
			elif saw_unheld:
				expect(false,"Held items must appear before zero-count items on first open")
				break
		expect(not slots.is_empty() and slots[0].item_id=="wood","Default wood selection is on the first row")
		if not slots.is_empty():
			expect(panel.get_global_rect().encloses(slots[0].get_global_rect()), "first slot fits inventory at %s" % size)
			check_layout(panel, size)
		if size == Vector2i(1280, 800):
			var frame_style := panel.get_theme_stylebox("panel")
			expect(frame_style is StyleBoxTexture and frame_style.texture != null, "panel has a textured frame")
			expect(panel.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "panel uses nearest-neighbor filtering")
			var ids := {}
			var barn_icons:Dictionary={}
			var barn_items:=["milk","wool","cotton_cloth","wool_cloth"]
			var atlas_pixels := Image.load_from_file("res://assets/ui-inventory/items.png")
			expect(atlas_pixels != null and not atlas_pixels.is_empty(), "item PNG decodes")
			check_icon_alpha(atlas_pixels)
			for slot in all_slots:
				ids[slot.item_id] = true
				var texture: Texture2D = slot.artwork.texture
				var pixels: Image = texture.get_image() if texture != null else null
				expect(texture != null and pixels != null and not pixels.is_empty() and not pixels.is_invisible(),
					"%s has decoded visible art" % slot.item_id)
				if slot.item_id in barn_items and pixels!=null:
					expect(pixels.get_size()==Vector2i(32,32),"%s uses a 32px source"%slot.item_id)
					barn_icons[Marshalls.raw_to_base64(pixels.get_data())]=true
			expect(barn_icons.size()==barn_items.size(),"milk, wool and both cloths have distinguishable pixel art")
			expect(ids.size() == all_slots.size() and ids.size() == World.NAMES.size() and World.NAMES.keys().all(func(id): return ids.has(id)), "all catalog item IDs appear exactly once")
			var original: Dictionary = world.state.duplicate(true)
			await check_categories(main, panel, world_point)
			for slot in slots:
				if slot.item_id != "stone":
					continue
				var selected_style: StyleBox = slot.get_theme_stylebox("pressed")
				var hover_style: StyleBox = slot.get_theme_stylebox("hover")
				expect(selected_style is StyleBoxTexture and hover_style is StyleBoxTexture
					and selected_style.texture != null and hover_style.texture != null
					and selected_style.texture != hover_style.texture, "selection and hover use distinct pixel textures")
				expect(slot.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "slot uses nearest-neighbor filtering")
				slot.grab_focus()
				slot.pressed.emit()
				main._refresh_hud()
				expect(root.gui_get_focus_owner() == slot and panel.selected_id == "stone",
					"refresh preserves selected item and keyboard focus")
				expect(panel.detail_name.text == World.NAMES.stone and panel.detail_icon.texture == slot.artwork.texture
					and panel.detail_count.text.ends_with("4"), "selection updates right-hand detail")
				expect(world.state == original, "slot selection and refresh preserve authoritative snapshot")
				for amount in [0, 1, 999, 12345, 1000000000]:
					var snapshot: Dictionary = world.state.duplicate(true)
					snapshot.players["inventory-grid-test"].inventory.stone = amount
					var unchanged := snapshot.duplicate(true)
					panel.refresh(snapshot, "inventory-grid-test")
					await layout_frames()
					check_amount(slot, amount)
					expect(panel.detail_count.text.ends_with(str(amount)) and snapshot == unchanged, "refresh retains exact amount without mutation")
				break
		if size==Vector2i(1024,640):
			var expected_width:=minf(900.0,float(size.x)-32.0)
			expect(is_equal_approx(panel.size.x,expected_width) and panel.grid.columns==6,
				"backpack opens at the intended width and column count for %s"%size)
			for arg in OS.get_cmdline_user_args():
				if not arg.begins_with("--capture-dir="):continue
				var preview_state:Dictionary=world.state.duplicate(true)
				preview_state.players[main.session.own_id].inventory={"milk":4,"wool":3,"cotton_cloth":2,"wool_cloth":1}
				key(main,KEY_ESCAPE)
				await layout_frames()
				main.session.snapshot=preview_state
				key(main,KEY_TAB)
				panel=main.modal
				main.view.update_snapshot(preview_state,main.session.own_id)
				await layout_frames()
				panel.slots.milk.grab_focus()
				panel.select_item("milk")
				await layout_frames()
				await RenderingServer.frame_post_draw
				var path:=arg.trim_prefix("--capture-dir=").path_join("inventory-%dx%d.png"%[size.x,size.y])
				expect(root.get_texture().get_image().save_png(path)==OK,"inventory screenshot captured at %s"%size)
				main.session.snapshot=world.state
		var close_key := KEY_TAB if size.x <= 1280 and size.y == 720 else KEY_ESCAPE
		key(main, close_key)
		await layout_frames()
		expect(main.modal == null and main._world_pointer_allowed(world_point),
			"%s closes inventory and restores targeting at %s" % [OS.get_keycode_string(close_key), size])
		var restored_visibility: Array[bool] = []
		for control in main.preview_controls:
			restored_visibility.append(control.visible)
		expect(restored_visibility == hud_visibility, "HUD and tracker return to their prior visibility")
		expect(not is_instance_valid(panel) and main.hud.get_child_count() == hud_children,
			"repeated opening and closing releases the inventory and shade")
	main.playing = false
	main.queue_free()
	await process_frame
	print("INVENTORY_GRID_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
