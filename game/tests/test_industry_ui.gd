extends SceneTree

const World = preload("res://scripts/world.gd")
const STATION := Vector2i(40, 33)
const TANK := Vector2i(43, 34)
const PUMP := Vector2i(45, 34)

var app
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func find_control(node: Node, value: String) -> Control:
	if node is Control and node.is_visible_in_tree():
		if (node is Button or node is Label) and node.text.contains(value):
			return node
	for child in node.get_children():
		var result := find_control(child, value)
		if result != null:return result
	return null

func enabled(title: String) -> bool:
	var control := find_control(app.modal, title) as Button
	return control != null and not control.disabled

func slot_enabled(node_name: String) -> bool:
	var button := app.modal.find_child(node_name, true, false) as Button
	return button != null and button.is_visible_in_tree() and not button.disabled

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.hud.show()
	var world = World.new()
	world.add_player("tester", "島民")
	app.session.snapshot = world.state
	app.session.own_id = "tester"
	var objects: Dictionary = world.state.objects
	var mill := {"type": "sawmill", "owner": "tester", "items": {}, "input_wood": 0, "auto_enabled": false}
	objects[World.key(STATION)] = mill
	var tank := {"type": "water_tank", "owner": "tester", "water": 0}
	objects[World.key(TANK)] = tank
	var pump := {"type": "water_pump", "owner": "tester", "enabled": false}
	objects[World.key(PUMP)] = pump
	objects[World.key(Vector2i(44, 34))] = {"type": "water_pipe", "owner": "tester"}
	app.industry_ui.device(app, STATION)
	expect(slot_enabled("ProcessingEnqueue"), "wood stock enables plank processing")
	var person: Dictionary = world.state.players.tester
	person.inventory.wood = 0
	app.industry_ui.refresh(app)
	expect(find_control(app.modal, "材料不足") != null and not slot_enabled("ProcessingEnqueue"), "missing wood disables processing")
	mill.job = {"kind": "plank", "ready": 12.0, "yield": 2, "owner": "tester", "ingredients": {"wood": 4}}
	app.industry_ui.refresh(app)
	expect(find_control(app.modal, "約剩 12 秒") != null and not slot_enabled("ProcessingClaim") and slot_enabled("ProcessingCancel_legacy"), "busy station shows countdown and cancellation")
	world.state.time = 12.0
	app.industry_ui.refresh(app)
	expect(slot_enabled("ProcessingClaim"), "finished job can be claimed")
	mill.owner = "other"
	app.industry_ui.refresh(app)
	expect(not slot_enabled("ProcessingClaim") and not slot_enabled("ProcessingCancel_legacy"), "other owner's station cannot be claimed or cancelled")
	app.industry_ui.device(app, TANK)
	expect(find_control(app.modal, "缺水") != null and enabled("補滿儲水桶"), "empty owned tank offers refill")
	expect(find_control(app.modal, "水泵 1") != null, "same-owner pipes connect tank and pump")
	tank.water = 48
	app.industry_ui.refresh(app)
	expect(find_control(app.modal, "管網水量 48") != null and not enabled("補滿儲水桶"), "full tank updates network total")
	app.industry_ui.device(app, PUMP)
	expect(enabled("啟用河水泵"), "owner can enable pump")
	pump.enabled = true
	app.industry_ui.refresh(app)
	expect(enabled("停止抽水"), "enabled pump updates its control")
	pump.owner = "other"
	app.industry_ui.refresh(app)
	expect(find_control(app.modal, "水桶 0") != null and not enabled("停止抽水"), "ownership separates networks and protects controls")
	app._close_modal()
	app.industry_ui.refresh(app)
	app.queue_free()
	await process_frame
	print("INDUSTRY_UI_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
