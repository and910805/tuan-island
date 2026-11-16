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

func run() -> void:
	var app = load("res://main.tscn").instantiate()
	var shell = load("res://scripts/life_ui_shell.gd")
	root.add_child(app)
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
	var slot: Button = app.preview_toolbar.find_child("TillerSlot", true, false)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for extent in [Vector2i(1024,640), Vector2i(1280,800), Vector2i(1920,1080)]:
		root.size = extent
		player.inventory.erase("tiller")
		app._select_tool("hoe")
		shell.refresh_hud(app, world.state, player)
		for frame in 4:await process_frame
		expect(not slot.visible and app.preview_toolbar.size.x == 700, "unowned tiller stays hidden at %s" % extent)
		player.inventory.tiller = 1
		shell.refresh_hud(app, world.state, player)
		for frame in 4:await process_frame
		expect(slot.visible and app.preview_toolbar.size.x == 776, "tiller expands toolbar at %s" % extent)
		var toolbar: Rect2 = app.preview_toolbar.get_global_rect()
		expect(root.get_visible_rect().encloses(toolbar) and absf(toolbar.get_center().x - extent.x * 0.5) < 1,
			"expanded toolbar fits and remains centered")
		slot.pressed.emit()
		shell.refresh_hud(app, world.state, player)
		expect(app.selected == "till_area" and slot.button_pressed and app.selected_label.text.contains("耕田機"),
			"click selects tiller and shows its tool hint")
		app._select_tool("hoe")
		var shortcut := InputEventKey.new()
		shortcut.keycode = KEY_U
		shortcut.physical_keycode = KEY_U
		shortcut.pressed = true
		app._unhandled_input(shortcut)
		expect(app.selected == "till_area", "U equips the owned tiller")
	app._inventory()
	expect(app.modal.category_for("tiller") == 4, "portable tiller appears under other items")
	app._close_modal()
	app.playing = false
	app.queue_free()
	await process_frame
	print("TILLER_UI_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
