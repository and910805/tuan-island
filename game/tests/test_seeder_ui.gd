extends SceneTree

const World = preload("res://scripts/world.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text.begins_with(caption):return node
	for child in node.get_children():
		var found := find_button(child, caption)
		if found != null:return found
	return null

func visible_without_clipping(button: Button) -> bool:
	if button == null or not button.is_visible_in_tree():return false
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(button.get_global_rect()):
			return false
		parent = parent.get_parent()
	return true

func run() -> void:
	var app = load("res://main.tscn").instantiate()
	var shell = load("res://scripts/life_ui_shell.gd")
	root.add_child(app)
	expect(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "preview uses native pixel scaling on launch")
	expect(root.min_size == Vector2i(1024, 640), "preview sets the supported minimum window size on launch")
	app.set_process(false)
	app.hud.show()
	app.playing = true
	app.menu.hide()
	var world = World.new()
	world.add_player("tester", "島民")
	app.session.snapshot = world.state
	app.session.own_id = "tester"
	app.session.world = world
	app.session.peers[1] = "tester"
	app.session.set_physics_process(false)
	var player: Dictionary = world.state.players.tester
	# Fixture beyond the first-crop guide: chapter one already shipped (and no personal start),
	# so first_crop_step() is empty and the full, uncompacted toolbar is shown.
	world.state.chapter_one.shipped = true
	expect(World.CHAPTER_ONE.first_crop_step(world.state, "tester").is_empty(), "fixture is past the first-crop guide")
	var slot: Button = app.preview_toolbar.find_child("SeederSlot", true, false)
	var tiller_slot: Button = app.preview_toolbar.find_child("TillerSlot", true, false)
	var toggle: Button = app.preview_toolbar.find_child("AllToolsToggle", true, false)
	var rod: Button = app.preview_toolbar.find_child("FishingSlot", true, false)
	for extent in [Vector2i(1024,640), Vector2i(1280,800), Vector2i(1920,1080)]:
		root.size = extent
		for portable in ["tiller", "seeder", "harvester"]:player.inventory.erase(portable)
		app._select_tool("hoe")
		shell.refresh_hud(app, world.state, player)
		for frame in 4:await process_frame
		var base: float = app.preview_toolbar.size.x
		expect(not slot.visible and base > 0.0, "unowned seeder stays hidden at %s" % extent)
		expect(app.tool_buttons.all(func(button): return button.visible) and rod.visible and not toggle.visible,
			"all basic tools stay visible without the first-crop compact guide at %s" % extent)
		player.inventory.seeder = 1
		shell.refresh_hud(app, world.state, player)
		for frame in 4:await process_frame
		var step: float = slot.get_combined_minimum_size().x + 4.0
		expect(slot.visible and slot.get_combined_minimum_size().x > 0.0 and is_equal_approx(app.preview_toolbar.size.x, base + step),
			"seeder expands toolbar by its own button at %s (%s -> %s)" % [extent, base, app.preview_toolbar.size.x])
		var toolbar: Rect2 = app.preview_toolbar.get_global_rect()
		expect(root.get_visible_rect().encloses(toolbar) and absf(toolbar.get_center().x - extent.x * 0.5) < 1,
			"expanded toolbar fits and remains centered")
		slot.pressed.emit()
		shell.refresh_hud(app, world.state, player)
		expect(app.selected == "seed_area" and slot.button_pressed and app.selected_label.text.contains("播種機"),
			"click selects seeder and shows its tool hint")
		app._select_tool("hoe")
		var shortcut := InputEventKey.new()
		shortcut.keycode = KEY_I
		shortcut.physical_keycode = KEY_I
		shortcut.pressed = true
		app._unhandled_input(shortcut)
		expect(app.selected == "seed_area", "I equips the owned seeder")
		player.inventory.tiller = 1
		shell.refresh_hud(app, world.state, player)
		for frame in 4:await process_frame
		var both: Rect2 = app.preview_toolbar.get_global_rect()
		var shortcuts: Control = app.hud.get_node("LifeShortcuts")
		var both_step: float = step + tiller_slot.get_combined_minimum_size().x + 4.0
		expect(tiller_slot.visible and is_equal_approx(both.size.x, base + both_step) and root.get_visible_rect().encloses(both),
			"both portable tools fit and add their own widths at %s" % extent)
		expect(not both.intersects(shortcuts.get_global_rect()), "portable tools never overlap shortcuts")
	app._inventory()
	expect(app.modal.category_for("seeder") == 4, "portable seeder appears under other items")
	app._close_modal()
	var bench := Vector2i(40, 33)
	world.state.objects[World.key(bench)] = {"type": "bench", "owner": "tester", "items": {}}
	for extent in [Vector2i(1024,640), Vector2i(1280,800)]:
		root.size = extent
		player.inventory.merge(World.CRAFT.seeder.ingredients, true)
		app.automation_ui.workbench(app, bench)
		var recipe := find_button(app.modal, World.CRAFT.seeder.name)
		recipe.pressed.emit()
		for frame in 6:await process_frame
		expect(recipe.button_pressed and visible_without_clipping(recipe), "selected recipe and caption fit at %s" % extent)
		for caption in ["製作", "拿起播種機", "家園建造"]:
			expect(visible_without_clipping(find_button(app.modal, caption)), "%s fits at %s" % [caption, extent])
	app._close_modal()
	app.automation_ui.refresh(app)
	app.playing = false
	app.queue_free()
	await process_frame
	print("SEEDER_UI_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
