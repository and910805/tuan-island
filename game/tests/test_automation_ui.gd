extends SceneTree

const World = preload("res://scripts/world.gd")
const BENCH := Vector2i(40, 33)
const DEVICE := Vector2i(43, 34)
const SIZES := [Vector2i(1024, 640), Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1920, 1080)]

var checks := 0
var failures := 0
var app
var world

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func controls(node: Node) -> Array[Control]:
	var found: Array[Control] = []
	if node is Control and node.is_visible_in_tree():
		found.append(node)
	for child in node.get_children():
		found.append_array(controls(child))
	return found

func button(title: String) -> Button:
	for control in controls(app.modal):
		if control is Button and control.text == title:
			return control
	push_error("Missing button: " + title)
	failures += 1
	return Button.new()

func has_label(title: String) -> bool:
	for control in controls(app.modal):
		if control is Label and control.text == title:
			return true
	return false

func verify_layout(title: String) -> void:
	for frame in 4:
		await process_frame
	expect(root.get_visible_rect().encloses(app.modal.get_global_rect()), title + " fits viewport")
	for control in controls(app.modal):
		if control is Label and String(control.name).begins_with("MaterialAmount"):
			expect(control.size.x >= 110 and control.size.y < 40 and control.get_line_count() == 1,
				"material quantity stays on one readable line: " + control.text)
		if control is Label and control.text.length() >= 8:
			expect(control.size.x >= 100 and control.get_line_count() <= 4, title + " has readable label: " + control.text)

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.hud.show()
	world = World.new()
	world.add_player("tester", "島民")
	app.session.snapshot = world.state
	app.session.own_id = "tester"
	var player: Dictionary = world.state.players.tester
	world.state.objects[World.key(BENCH)] = {"type": "bench", "owner": "tester"}
	var device := {"type": "sprinkler", "owner": "tester", "water": 0, "enabled": false}
	world.state.objects[World.key(DEVICE)] = device
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for resolution in SIZES:
		root.size = resolution
		player.inventory.copper_ore = 0
		player.inventory.reinforced_pick = 0
		world.state.copper.ready = 0.0
		device.merge({"owner": "tester", "water": 0, "enabled": false}, true)
		app.automation_ui.workbench(app, BENCH)
		button(World.CRAFT.copper_joint.name).pressed.emit()
		await verify_layout("workbench %s" % resolution)
		expect(button("材料不足").disabled, "copper shortage disables crafting")
		player.inventory.copper_ore = 2
		app.automation_ui.refresh(app)
		expect(not button("製作 1 件").disabled, "live recipe requirements enable crafting")
		button(World.CRAFT.sprinkler_kit.name).pressed.emit()
		expect(button("材料不足").disabled, "switching recipes updates requirements")
		app.automation_ui.sprinkler(app, DEVICE)
		await verify_layout("sprinkler %s" % resolution)
		expect(not button("補滿水").disabled and not button("啟用").disabled, "owner controls empty sprinkler")
		device.water = World.SPRINKLER_CAPACITY
		device.enabled = true
		app.automation_ui.refresh(app)
		expect(has_label("水量 12／12") and button("補滿水").disabled and not button("停止").disabled, "full active sprinkler updates in place")
		device.owner = "other"
		app.automation_ui.refresh(app)
		expect(button("補滿水").disabled and button("停止").disabled, "another owner's controls are disabled")
		app.automation_ui.copper(app)
		await verify_layout("copper %s" % resolution)
		expect(button("採掘銅礦").disabled, "mining requires the reinforced pick")
		player.inventory.reinforced_pick = 1
		app.automation_ui.refresh(app)
		expect(not button("採掘銅礦").disabled, "equipped pick enables mining")
		world.state.copper.ready = 8.0
		app.automation_ui.refresh(app)
		expect(button("採掘銅礦").disabled and has_label("等待補貨 · 約剩 8 秒"), "imported practice material cooldown disables mining and shows time")
	app._close_modal()
	app.automation_ui.refresh(app)
	app.queue_free()
	await process_frame
	print("AUTOMATION_UI_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
