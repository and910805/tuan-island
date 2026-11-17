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

func belt_frame(world:World,file:String,blocked:bool)->void:
	app.view.update_snapshot(world.state.duplicate(true),"operator")
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var view=app.view
	var viewport:=Rect2(Vector2.ZERO,Vector2(root.size)/view.view_zoom())
	var labels:Array=view.world_label_placements(viewport)
	expect(labels.any(func(entry):return entry.id==World.key(BELT) and entry.active and entry.title.contains("前方進料槽已滿")==blocked),"Belt label matches the actual buffer state")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file))==OK,"Capture "+file)

func check_belt_render()->void:
	var world:=World.new()
	world.add_player("operator","物流島民")
	var person:Dictionary=world.state.players.operator
	person.x=39.5
	person.y=38.5
	var belt:={"type":"conveyor","owner":"operator","dir":1,"enabled":true,"filter":"wood","items":{"wood":1}}
	var mill:={"type":"sawmill","owner":"operator","items":{},"input_wood":32,"auto_enabled":false}
	world.state.objects[World.key(BELT)]=belt
	world.state.objects[World.key(MILL)]=mill
	app.menu.hide()
	await belt_frame(world,"belt-blocked.png",true)
	expect(world.act("operator","clear-inlet","unload_processing_input",MILL).ok,"Operator clears the receiving buffer")
	expect(world.step(2.0,true) and int(world.state.objects[World.key(MILL)].input_wood)==1 and world.state.objects[World.key(BELT)].items.is_empty(),"Actual logistics moves the retained item into the freed buffer")
	await belt_frame(world,"belt-resumed.png",false)

func tap_pad(id:JoyButton)->void:
	for down in [true,false]:
		var event:=InputEventJoypadButton.new()
		event.button_index=id
		event.pressed=down
		root.push_input(event)
	for frame in 4:await process_frame

func check_controller()->void:
	var path:="user://conveyor-pad-%d.json"%OS.get_process_id()
	var started:bool=app.session.host(0,"物流島民",path)==OK
	expect(started,"Conveyor pad test starts a local island")
	if not started:return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	person.x=39.5
	person.y=38.5
	var belt:={"type":"conveyor","owner":token,"dir":1,"enabled":true,"filter":"wood","items":{"wood":1}}
	world.state.objects[World.key(BELT)]=belt
	app.session._send_snapshot(1)
	app.logistics_ui.device(app,BELT)
	for frame in 4:await process_frame
	var initial:int=app.session.counter
	var wood:int=person.inventory.wood
	await tap_pad(JOY_BUTTON_X)
	expect(root.gui_get_focus_owner()==named("ConveyorUnload") and app.session.counter==initial,"X focuses unloading without moving cargo")
	await tap_pad(JOY_BUTTON_A)
	expect(belt.items.is_empty() and int(person.inventory.wood)==wood+1,"A moves the retained wood to the backpack")
	await tap_pad(JOY_BUTTON_X)
	expect(root.gui_get_focus_owner()==named("ConveyorToggle"),"X focuses the toggle after unloading")
	await tap_pad(JOY_BUTTON_B)
	expect(app.modal==null,"B closes the conveyor panel")
	app.session.shutdown()
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)

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
	expect(app.modal.find_child("ConveyorDestinationIcon",true,false).texture!=null,"Route uses the actual receiving station icon")
	for frame in 4:await process_frame
	var advice:=app.modal.find_child("ConveyorAdvice",true,false) as Label
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	expect(scroll.get_global_rect().encloses(advice.get_global_rect()),"Next-action advice is visible without scrolling at 1024")
	belt.items.wood = 1
	app.logistics_ui.refresh(app)
	expect(not enabled("←") and enabled("取回物品"), "occupied belt locks settings but allows unloading")
	belt.enabled = true
	app.logistics_ui.refresh(app)
	expect(not enabled("←") and enabled("停止"), "running belt stays unconfigurable")
	mill.input_wood = 32
	app.logistics_ui.refresh(app)
	expect(control(app.modal, "阻塞 · 前方進料槽已滿") != null, "Loaded belt names the same full destination reason as the world prompt")
	expect(advice.text.contains("啟用自動加工") and advice.text.contains("保留"),"Full inlet explains recovery and cargo retention")
	belt.items.clear()
	objects[World.key(BELT + Vector2i.DOWN)] = {"type": "conveyor", "owner": "tester", "dir": 0, "filter": "wood", "enabled": true, "items": {"wood": 1}}
	app.logistics_ui.refresh(app)
	expect(control(app.modal, "接入輸送帶 1 段") != null, "a perpendicular belt pointing here is an input")
	objects[World.key(BELT + Vector2i.DOWN)].dir = 1
	app.logistics_ui.refresh(app)
	expect(control(app.modal, "等待 · 未接通來源") != null, "a neighboring belt pointed elsewhere is not an input")
	expect(advice.text.contains("箭頭後方"),"Disconnected source explains the physical input side")
	var rear_key:=World.key(BELT+Vector2i.LEFT)
	objects[rear_key]={"type":"charcoal_kiln","owner":"tester","items":{},"input_wood":0,"auto_enabled":false}
	belt.filter="charcoal"
	app.logistics_ui.refresh(app)
	expect(advice.text.contains("手動加工") and app.modal.find_child("ConveyorSourceIcon",true,false).texture!=null,"Manual source explains backpack output and shows real source art")
	objects[rear_key].auto_enabled=true
	objects[rear_key].job={"kind":"charcoal","ready":30.0,"auto":true}
	app.logistics_ui.refresh(app)
	expect(advice.text.contains("正在加工") and not advice.text.contains("需使用自動模式"),"Active automatic source is not falsely told to enable auto")
	belt.filter="plank"
	app.logistics_ui.refresh(app)
	expect(advice.text.contains("產出木炭") and advice.text.contains("改篩選"),"Incorrect source filter is explained")
	objects.erase(rear_key)
	belt.filter="wood"
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
	if DisplayServer.get_name()!="headless":await check_belt_render()
	await check_controller()
	app.queue_free()
	await process_frame
	print("LOGISTICS_UI_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
