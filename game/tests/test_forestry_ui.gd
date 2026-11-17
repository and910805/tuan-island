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

func tap_pad(id:JoyButton)->void:
	for pressed in [true,false]:
		var event:=InputEventJoypadButton.new()
		event.button_index=id
		event.pressed=pressed
		root.push_input(event)
	for frame in 4:await process_frame

func check_controller(app)->void:
	var path:="user://forestry-pad-%d.json"%OS.get_process_id()
	var started:bool=app.session.host(0,"林務試玩",path)==OK
	expect(started,"Local Session starts")
	if not started:return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var tile:=Vector2i(41,34)
	var person:Dictionary=world.state.players[token]
	person.x=41.5
	person.y=35.5
	person.inventory.forester_kit=1
	person.inventory.charcoal=4
	expect(world.act(token,"place-station","build",tile,"forester").ok,"Place the station through the actual build rules")
	var station:Dictionary=world.state.objects.get(World.key(tile),{})
	if not station.is_empty():
		station.items={"wood":6,"fiber":2,"resin":1}
		app.session._send_snapshot(1)
		app.forestry_ui.device(app,tile)
		for frame in 4:await process_frame
		var current:int=app.session.counter
		var wood:int=person.inventory.wood
		await tap_pad(JOY_BUTTON_X)
		expect(root.gui_get_focus_owner().name=="ForestryCollect" and app.session.counter==current,"X focuses collection without claiming")
		await tap_pad(JOY_BUTTON_A)
		expect(station.items.is_empty() and int(person.inventory.wood)==wood+6,"A claims the stored materials")
		app.forestry_ui.refresh(app)
		await tap_pad(JOY_BUTTON_X)
		expect(root.gui_get_focus_owner().name=="ForestryLoad_charcoal","With no output, X focuses charcoal loading")
		app.session.rates[1].clear()
		await tap_pad(JOY_BUTTON_A)
		expect(station.fuel==4 and int(person.inventory.get("charcoal",0))==0,"A loads the charcoal into the station")
	app._close_modal()
	app.session.shutdown()
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)

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
	expect(World.FORESTRY.field_status(device)=="已停止","Stopped forest station reports stopped")
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
	expect(World.FORESTRY.field_status(device)=="缺木炭及樹苗","An enabled station can run out of both supplies")
	device.next_cycle = 12.0
	device.fuel = 8
	device.items.wood = 6
	expect(World.FORESTRY.field_status(device)=="木炭 8 · 樹苗 0 · 木材 6 待領","Field prompt shows supplies and available wood together")
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
	# Fixture-only obstruction cases: explain the actual reason, never recommend
	# clearing another player's planted tree or a retained farm plot.
	var open_key:=World.key(open_tile)
	world.state.forest[open_key].owner="friend"
	expect(app.forestry_ui.plot_summary(world,open_tile,device)=="他人樹木 · 保留不動","Foreign grove is preserved, not presented as a natural tree to cut")
	world.state.forest.erase(open_key)
	world.state.objects[open_key]={"type":"sawmill","owner":"tester"}
	expect(app.forestry_ui.plot_summary(world,open_tile,device)=="鋸木台占格","Occupied plot identifies the actual machine")
	world.state.objects.erase(open_key)
	world.state.crops[open_key]={"owner":"tester","kind":"","growth":0,"wet":false}
	expect(app.forestry_ui.plot_summary(world,open_tile,device)=="農田 · 保留不動","Farm obstruction has a useful preservation message")
	world.state.crops.erase(open_key)
	for resource in ["tree","rock","grass"]:
		var found:=false
		for y in range(10,48):
			for x in range(10,54):
				var tile:=Vector2i(x,y)
				if world.protected(tile) or world.water(tile) or world.resource(tile)!=resource:continue
				if World.FORESTRY.plot_status(world,tile,"tester")!="blocked":continue
				var expected:String={"tree":"天然樹 · 先清理","rock":"石頭 · 先清理","grass":"雜草 · 先清理"}[resource]
				expect(app.forestry_ui.plot_summary(world,tile,device)==expected,"Natural "+resource+" explicitly needs manual clearing")
				found=true
				break
			if found:break
		expect(found,"World contains a real obstruction source for "+resource)
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
	await check_controller(app)
	app.queue_free()
	await process_frame
	print("FORESTRY_UI_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
