extends SceneTree

const World = preload("res://scripts/world.gd")
const BELT := Vector2i(39, 37)
const MILL := Vector2i(40, 37)
var checks := 0
var failures := 0
var app

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func control(node: Node, title: String) -> Control:
	if (node is Button or node is Label) and node.is_visible_in_tree() and node.text.contains(title):
		return node
	for child in node.get_children():
		var found := control(child, title)
		if found != null:return found
	return null

func enabled(title: String) -> bool:
	var button := find_button(app.modal, title)
	return button != null and not button.disabled

func find_button(node: Node, title: String) -> Button:
	if node is Button and node.is_visible_in_tree() and node.text == title:return node
	for child in node.get_children():
		var found := find_button(child, title)
		if found != null:return found
	return null

func named(title: String) -> Button:
	return app.modal.find_child(title, true, false) as Button

func usable(title: String) -> bool:
	var button := named(title)
	return button != null and button.is_visible_in_tree() and not button.disabled

func inside(title: String) -> bool:
	var button := named(title)
	return button != null and button.is_visible_in_tree() and app.modal.get_global_rect().encloses(button.get_global_rect()) and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(button.get_global_rect())

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.hud.show()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1024, 640)
	var world = World.new()
	world.add_player("tester", "島民")
	var objects: Dictionary = world.state.objects
	var belt := {"type": "conveyor", "owner": "tester", "dir": 1, "enabled": false, "filter": "wood", "items": {}}
	var mill := {"type": "sawmill", "owner": "tester", "items": {}, "input_wood": 0, "auto_enabled": false}
	objects[World.key(BELT)] = belt
	objects[World.key(MILL)] = mill
	app.session.snapshot = world.state
	app.session.own_id = "tester"
	app.logistics_ui.device(app, BELT)
	expect(enabled("←") and enabled("啟用"), "owner can configure an empty stopped belt")
	expect(control(app.modal, "目的地　鋸木台") != null, "route displays its receiving station")
	belt.items.wood = 1
	app.logistics_ui.refresh(app)
	expect(not enabled("←") and enabled("取回物品"), "occupied belt locks settings but allows unloading")
	belt.enabled = true
	app.logistics_ui.refresh(app)
	expect(not enabled("←") and enabled("停止"), "running belt stays unconfigurable")
	mill.input_wood = 32
	app.logistics_ui.refresh(app)
	expect(control(app.modal, "阻塞 · 加工料槽已滿") != null, "loaded belt names the full destination")
	belt.items.clear()
	objects[World.key(BELT + Vector2i.DOWN)] = {"type": "conveyor", "owner": "tester", "dir": 0, "filter": "wood", "enabled": true, "items": {"wood": 1}}
	app.logistics_ui.refresh(app)
	expect(control(app.modal, "接入輸送帶 1 段") != null, "a perpendicular belt pointing here is an input")
	objects[World.key(BELT + Vector2i.DOWN)].dir = 1
	app.logistics_ui.refresh(app)
	expect(control(app.modal, "等待 · 未接通來源") != null, "a neighboring belt pointed elsewhere is not an input")
	belt.owner = "other"
	app.logistics_ui.refresh(app)
	expect(not enabled("停止") and not enabled("取回物品"), "other owner's belt is read-only")
	app.industry_ui.device(app, MILL)
	expect(usable("ProcessingEnqueue") and usable("ProcessingAutoTab"), "manual queue offers automatic buffer tab")
	for frame in 4:await process_frame
	expect(inside("ProcessingEnqueue") and inside("ProcessingClaim"), "manual fixed controls fit at 1024×640")
	named("ProcessingAutoTab").pressed.emit()
	for frame in 4:await process_frame
	expect(usable("ProcessingToggleAuto") and inside("ProcessingCollect"), "automatic buffer tab retains toggle and output action")
	mill.auto_enabled = true
	app.industry_ui.refresh(app)
	expect(not usable("ProcessingEnqueue") and usable("ProcessingToggleAuto"), "automatic mode cannot enqueue manual work")
	for frame in 4:await process_frame
	expect(inside("ProcessingCollect") and inside("ProcessingToggleAuto"), "automatic controls fit at 1024×640")
	mill.job = {"kind": "plank", "ready": 0.0, "yield": 2, "auto": true}
	app.industry_ui.refresh(app)
	expect(not usable("ProcessingClaim") and named("ProcessingCancel_legacy") == null, "automatic job has no manual claim or cancel")
	mill.erase("job")
	mill.items.plank = 2
	app.industry_ui.refresh(app)
	expect(usable("ProcessingCollect"), "completed automatic output can be collected")
	mill.owner = "other"
	app.industry_ui.refresh(app)
	expect(not usable("ProcessingCollect") and not usable("ProcessingFeed"), "other owner's processing buffers are read-only")
	app._close_modal()
	app.logistics_ui.refresh(app)
	app.industry_ui.refresh(app)
	app.queue_free()
	await process_frame
	print("LOGISTICS_UI_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
