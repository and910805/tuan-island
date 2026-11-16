extends SceneTree

const World = preload("res://scripts/world.gd")
const STATION := Vector2i(36, 39)

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func find_all(node: Node, type_name: String) -> Array[Control]:
	var matches: Array[Control] = []
	if node is Control and node.is_visible_in_tree() and node.is_class(type_name):
		matches.append(node)
	for child in node.get_children():
		matches.append_array(find_all(child, type_name))
	return matches

func run() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.hud.show()
	var world = World.new()
	world.add_player("tester", "島民")
	var player: Dictionary = world.state.players.tester
	var key: String = World.key(STATION)
	var device: Dictionary = {"type": "forester", "owner": "tester", "items": {}}
	device.merge(World.FORESTRY.fresh(0.0))
	world.state.objects[key] = device
	app.session.snapshot = world.state
	app.session.own_id = "tester"
	app.forestry_ui.device(app, STATION)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for extent in [Vector2i(1024,640), Vector2i(1280,800), Vector2i(1920,1080)]:
		root.size = extent
		for frame in 4:await process_frame
		var bounds := root.get_visible_rect()
		expect(bounds.encloses(app.modal.get_global_rect()), "forestry modal fits %s" % extent)
		var scroll: ScrollContainer = app.modal.find_child("ModalScroll", true, false)
		for control in find_all(app.modal, "Button"):
			if control.text in ["啟用", "領取產物", "退回供料"]:
				expect(scroll.get_global_rect().encloses(control.get_global_rect()), "%s is visible without scrolling" % control.text)
	var buttons := find_all(app.modal, "Button")
	var supply := buttons.filter(func(button): return button.text == "補入")
	expect(supply.size() == 2 and supply[0].disabled and not supply[1].disabled, "charcoal unavailable, saplings available")
	player.inventory.charcoal = 4
	app.forestry_ui.refresh(app)
	expect(not supply[0].disabled, "new charcoal enables the same supply control")
	device.enabled = true
	device.next_cycle = 12.0
	device.fuel = 8
	device.items.wood = 6
	app.forestry_ui.refresh(app)
	var values := find_all(app.modal, "Label").map(func(label): return label.text)
	expect(values.has("下次檢查上方 · 12 秒") and values.has("6／48"), "timer and production counters update in place")
	expect(supply[0].disabled, "full fuel storage disables loading")
	expect(buttons.any(func(button): return button.text == "領取產物" and not button.disabled), "product can be collected")
	var open_tile := Vector2i(38, 34)
	world.state.removed[World.key(open_tile)] = true
	player.x = open_tile.x + 0.5
	player.y = open_tile.y + 0.5
	expect(app.forestry_ui.plot_summary(world, open_tile, device) == "有人站立 · 稍候", "visible player blocks an otherwise empty plot")
	world.state.forest[World.key(open_tile)] = {"owner": "tester", "growth": World.TREE_TIME, "mature": false}
	expect(app.forestry_ui.plot_summary(world, open_tile, device) == "等待讓出空間", "fully grown occupied tree has a useful status")
	device.owner = "other"
	app.forestry_ui.refresh(app)
	expect(buttons.filter(func(button): return button.text in ["停止", "補入", "退回供料", "領取產物"]).all(func(button): return button.disabled),
		"other owner's controls are disabled")
	for extent in [Vector2i(1024,640), Vector2i(1280,800)]:
		root.size = extent
		app.automation_ui.workbench(app, STATION)
		var recipes := find_all(app.modal, "Button")
		for recipe in recipes:
			if recipe.text == World.CRAFT.forester_kit.name:
				recipe.pressed.emit()
				break
		for frame in 4:await process_frame
		var scroll: ScrollContainer = app.modal.find_child("ModalScroll", true, false)
		for control in find_all(app.modal, "Button"):
			if control.text.begins_with("家園建造"):
				expect(scroll.get_global_rect().encloses(control.get_global_rect()), "five material recipe keeps build shortcut visible at %s" % extent)
	app._close_modal()
	app.forestry_ui.refresh(app)
	app.queue_free()
	await process_frame
	print("FORESTRY_UI_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
