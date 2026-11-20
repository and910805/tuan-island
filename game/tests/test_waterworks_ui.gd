extends SceneTree

const World=preload("res://scripts/world.gd")
const Works=World.WATERWORKS
const CELL:=Vector2i(31,24)
var app
var world:World
var token:String
var checks:=0
var failures:=0

func _initialize()->void:run.call_deferred()

func check(condition:bool,message:String)->void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func frames()->void:
	for i in range(6):await process_frame
	app._layout_preview()
	await process_frame

func refresh()->void:
	app.session._send_snapshot(1)
	app.automation_ui.refresh(app)
	app.logistics_ui.refresh(app)
	await frames()

func control(id:String)->Control:
	return app.modal.find_child(id,true,false)

func visible(item:Control)->bool:
	if item==null or not item.is_visible_in_tree() or not root.get_visible_rect().encloses(item.get_global_rect()):return false
	var parent:=item.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(item.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func layout()->void:
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Waterworks modal fits viewport %s" % root.size)
	for id in ["WorksFeed_wood_1","WorksFeed_wood_5","WorksFeed_copper_ore_1","WorksFeed_copper_ore_5","WorksUnload","WorksToggle","WorksCollect","WorksDrain","WorksWater","WorksNetwork","WorksStatus","WorksProgress","WorksOutput"]:
		check(visible(control(id)),"Waterworks %s visible at %s" % [id,root.size])

func tap_pad(id:JoyButton)->void:
	for down in [true,false]:
		var event:=InputEventJoypadButton.new()
		event.button_index=id
		event.pressed=down
		root.push_input(event)
	await frames()

func press(id:String,with_pad:=false)->void:
	var button:=control(id) as Button
	check(button!=null and not button.disabled and visible(button),"Usable button "+id)
	if button==null or button.disabled:return
	await create_timer(.13).timeout
	if with_pad:
		var sequence:int=app.session.counter
		await tap_pad(JOY_BUTTON_X)
		check(root.gui_get_focus_owner()==button and app.session.counter==sequence,"X only focuses "+id)
		await tap_pad(JOY_BUTTON_A)
	else:button.pressed.emit()
	app.automation_ui.refresh(app)
	app.logistics_ui.refresh(app)
	await frames()

func check_integrations(person:Dictionary,objects:Dictionary)->void:
	var bench:=Vector2i(30,25)
	objects["30,25"]={"type":"bench","owner":token,"items":{}}
	person.inventory.merge(Works.COST,true)
	world.state.mine_depths.unlocked=3
	await refresh()
	app.automation_ui.workbench(app,bench)
	await frames()
	var recipe:Button=null
	for child in app.modal.find_children("*","Button",true,false):
		if child.text==World.CRAFT.waterworks_kit.name:recipe=child;break
	check(recipe!=null,"Waterworks recipe exists at real workbench")
	if recipe!=null:
		recipe.pressed.emit()
		await frames()
		check(control("CraftRecipe").disabled,"Enough materials do not bypass mine drainage")
		world.state.mine_depths.unlocked=4
		await refresh()
		check(not control("CraftRecipe").disabled and visible(control("CraftRecipe")),"Completing drainage enables visible craft control")
	app._close_modal()
	var belt:=Vector2i(30,24)
	objects["30,24"]={"type":"conveyor","owner":token,"items":{},"enabled":false,"dir":1,"filter":"copper_ore"}
	var machine:Dictionary=objects["31,24"]
	machine.input.copper_ore=32
	await refresh()
	app.logistics_ui.device(app,belt)
	await frames()
	check(World.LOGISTICS.FILTERS==["wood","fiber","resin","plank","charcoal","copper_ore","copper_joint","stone","gold_ore","wheat","flour"],"All eleven filters exist")
	for item in World.LOGISTICS.FILTERS:
		check(visible(control("Filter_"+item)),"Filter visible at smallest resolution: "+item)
	check(app.modal.find_children("*","Label",true,false).any(func(label):return label.text.contains("前方進料槽已滿")),"Live endpoints explain capacity")
	await press("Filter_copper_joint")
	check(app.modal.find_children("*","Label",true,false).any(func(label):return label.text.contains("前方不收這種材料")),"Live endpoints reject wrong material")
	app._close_modal()
	machine.items.copper_joint=1
	objects["32,24"]={"type":"conveyor","owner":token,"items":{},"enabled":false,"dir":1,"filter":"copper_joint"}
	await refresh()
	app.logistics_ui.device(app,Vector2i(32,24))
	await frames()
	check(app.modal.find_children("*","Label",true,false).any(func(label):return label.text.contains("來源　水力加工台")),"Finished copper joint is reported as ready source")
	app._close_modal()

func check_motion()->void:
	var preview=control("WorksMachine")
	var reduced:bool=app.sound.reduced_motion
	preview.set_process(false)
	app.sound.reduced_motion=false
	preview.elapsed=0.0
	preview._process(0.0)
	var first:Rect2=preview.texture.region
	preview._process(0.2)
	check(first.position.x>0 and preview.texture.region!=first,"Active work changes atlas frame")
	app.sound.reduced_motion=true
	preview._process(0.2)
	var still:Rect2=preview.texture.region
	preview._process(0.2)
	check(still.position.x==0 and preview.texture.region==still,"Reduced motion remains on idle frame")
	app.sound.reduced_motion=reduced
	preview.set_process(true)

func run()->void:
	var path:=OS.get_environment("TEMP").path_join("waterworks-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if app.session.host(0,"加工旅人",path)!=OK:check(false,"Host starts");quit(1);return
	world=app.session.world
	token=app.session.profile.token
	world.state.mine_depths.unlocked=4
	world.state.mine_depths.pumped=24
	world.add_player("other-worker","其他島民")
	var person:Dictionary=world.state.players[token]
	person.region="lanyang"
	person.y=25.5
	for dimensions in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions
		person.x=31.5
		person.inventory.merge({"wood":8,"copper_ore":8,"copper_joint":0},true)
		var machine:=Works.fresh()
		machine.merge({"type":"waterworks","owner":token,"water":6},true)
		var objects:Dictionary=world.state.regions.lanyang.objects
		objects["31,24"]=machine
		objects["32,24"]={"type":"water_tank","owner":token,"water":10,"items":{}}
		await refresh()
		app._interact()
		await frames()
		if app.modal==null or not app.modal.has_meta("waterworks_cell"):
			check(false,"E interaction opens real waterworks modal")
			break
		await layout()
		check(control("WorksWater").text.contains("6 / 12") and control("WorksNetwork").text.contains("10"),"Live internal and network water displayed")
		objects["32,24"]={"type":"diversion_gate","owner":token,"mode":"closed","items":{}}
		objects["33,24"]={"type":"water_tower","owner":token,"water":24,"enabled":true,"items":{}}
		await refresh()
		check(control("WorksNetwork").text.contains("水塔 1 · 蓄水 24") and control("WorksNetwork").text.contains("此處被分流閘隔開"),"Tower storage and blocked supply appear together")
		await layout()
		objects.erase("33,24")
		objects["32,24"]={"type":"water_tank","owner":token,"water":10,"items":{}}
		await refresh()
		check(control("WorksCollect").disabled and control("WorksUnload").disabled,"Empty buffers disable withdrawals")
		await press("WorksFeed_copper_ore_5")
		await press("WorksFeed_wood_1",true)
		check(machine.input.wood==1 and machine.input.copper_ore==5 and person.inventory.wood==7 and person.inventory.copper_ore==3,"Feed buttons use correct item and quantity")
		check(control("WorksInput_copper_ore").text.contains("5 / 32"),"Feed counter updates from host snapshot")
		person.x=12.5
		await refresh()
		check(control("WorksToggle").disabled and control("WorksUnload").disabled and control("WorksDrain").disabled,"Moving away disables nearby operations")
		person.x=31.5
		machine.owner="other-worker"
		await refresh()
		check(control("WorksFeed_wood_1").disabled and control("WorksToggle").disabled and control("WorksDrain").disabled,"Foreign device is read-only")
		machine.owner=token
		await refresh()
		await press("WorksToggle")
		check(machine.enabled and control("WorksDrain").disabled,"Enable starts auto mode and disallows drain")
		check(world.step(0.1,true) and machine.has("job"),"Host begins a batch")
		await refresh()
		if dimensions.x==1024:check_motion()
		await press("WorksToggle")
		check(not machine.enabled and machine.has("job") and control("WorksStatus").text.contains("完成後停止") and control("WorksDrain").disabled,"Stopping preserves current batch and explains it")
		await layout()
		check(world.step(12.0,true) and not machine.has("job"),"Host finishes stopped batch")
		await refresh()
		check(control("WorksOutput").text.contains("1 / 32"),"Completed quantity displayed")
		await press("WorksCollect",true)
		check(control("WorksBagOutput").text.contains("1"),"Output bag quantity updates after collect")
		var receipt:String=app.modal_feedback.text
		check(receipt.contains("已取回物品"),"Collect confirms the committed action")
		objects["32,24"].water=3
		await refresh()
		check(control("WorksNetwork").text.contains("3") and app.modal_feedback.text==receipt,"Water network refresh preserves collect receipt")
		await press("WorksUnload")
		await press("WorksDrain")
		check(person.inventory.copper_joint==1 and person.inventory.copper_ore==6 and Works.can_move(machine),"Collect, unload and drain leave the correct inventory and empty machine")
		check(control("WorksCollect").disabled and control("WorksUnload").disabled and control("WorksDrain").disabled,"Emptied controls refresh to disabled")
		app._close_modal()
		if dimensions.x==1024:await check_integrations(person,objects)
	app.session.shutdown()
	await create_timer(.35).timeout
	app.queue_free()
	await process_frame
	for suffix in ["",".bak",".tmp",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("WATERWORKS_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
