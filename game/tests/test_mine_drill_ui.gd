extends SceneTree

const World=preload("res://scripts/world.gd")
const Drill=World.MINE_DRILL
const CELL:=Vector2i(28,24)
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
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Mine drill modal fits viewport %s" % root.size)
	for id in ["DrillLocation","DrillFeed_1","DrillFeed_5","DrillUnload","DrillToggle","DrillCollect","DrillFuel","DrillStatus","DrillProgress","DrillOutput","DrillBagOutput","DrillMachine"]:
		check(visible(control(id)),"Mine drill %s visible at %s" % [id,root.size])

	for label in app.modal.find_children("*","Label",true,false):
		if label.is_visible_in_tree():check(visible(label),"Visible label fits: %s at %s" % [label.name,root.size])
	check(visible(control("DrillHint")) and visible(app.modal_feedback),"Drill hint and receipt footer are visible")

func press(id:String)->void:
	var button:=control(id) as Button
	check(button!=null and not button.disabled and visible(button),"Usable button "+id)
	if button==null or button.disabled:return
	await create_timer(.13).timeout
	button.pressed.emit()
	app.automation_ui.refresh(app)
	app.logistics_ui.refresh(app)
	await frames()

func check_integrations(person:Dictionary,objects:Dictionary)->void:
	person.x=World.MINES.SERVICE.x+0.5
	person.y=World.MINES.SERVICE.y+1.5
	await refresh()
	app._interact()
	await frames()
	var note:=control("DrillUnlockNote") as Label
	check(visible(note) and note.text.contains("圖樣已解鎖") and note.text.contains("工作台"),"Mine 4 service shows visible unlocked recipe hint")
	app._close_modal()
	person.x=27.5
	person.y=24.5
	var bench:=Vector2i(26,24)
	objects["26,24"]={"type":"bench","owner":token,"items":{}}
	person.inventory.merge(Drill.COST,true)
	world.state.mine_depths.unlocked=4
	await refresh()
	app.automation_ui.workbench(app,bench)
	await frames()
	var recipe:Button=null
	for button in app.modal.find_children("*","Button",true,false):
		if button.text==World.CRAFT.mine_drill_kit.name:recipe=button;break
	check(recipe!=null,"Real workbench lists drill recipe")
	if recipe!=null:
		recipe.pressed.emit()
		await frames()
		check(control("CraftRecipe").disabled,"Mine four commission required despite materials")
		world.state.mine_depths.unlocked=5
		await refresh()
		check(not control("CraftRecipe").disabled and visible(control("CraftRecipe")),"Mine five unlock enables visible craft action")
	app._close_modal()
	objects["28,25"]={"type":"conveyor","owner":token,"items":{},"enabled":false,"dir":0,"filter":"charcoal"}
	objects["28,24"].fuel=16
	await refresh()
	app.logistics_ui.device(app,Vector2i(28,25))
	await frames()
	check(World.LOGISTICS.FILTERS.size()==11,"All eleven distinct conveyor filters exist")
	for label in app.modal.find_children("*","Label",true,false):
		if label.is_visible_in_tree():check(visible(label),"Logistics label fits at 1024: "+str(label.name))
	for item in World.LOGISTICS.FILTERS:
		check(visible(control("Filter_"+item)),"Filter visible at smallest resolution: "+item)
	check(app.modal.find_children("*","Label",true,false).any(func(label):return label.text.contains("燃料已滿")),"Full drill fuel destination feedback")
	await press("Filter_stone")
	check(app.modal.find_children("*","Label",true,false).any(func(label):return label.text.contains("只接收木炭")),"Wrong material destination feedback")
	app._close_modal()
	objects.erase("28,25")

func check_motion()->void:
	var preview=control("DrillMachine")
	var reduced:bool=app.sound.reduced_motion
	preview.set_process(false)
	app.sound.reduced_motion=false
	preview.elapsed=0.0
	preview._process(0.0)
	var first:Rect2=preview.texture.region
	preview._process(0.2)
	check(first.position.x>0 and preview.texture.region!=first,"Active drill preview changes texture")
	app.sound.reduced_motion=true
	preview._process(0.2)
	var still:Rect2=preview.texture.region
	preview._process(0.2)
	check(still.position.x==0 and preview.texture.region==still,"Reduced motion holds idle texture")
	app.sound.reduced_motion=reduced
	preview.set_process(true)

func run()->void:
	var path:=OS.get_environment("TEMP").path_join("mine-drill-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if app.session.host(0,"礦工旅人",path)!=OK:check(false,"Host starts");quit(1);return
	world=app.session.world
	token=app.session.profile.token
	world.state.mine_depths.unlocked=5
	world.state.mine_depths.pumped=24
	world.add_player("other-miner","其他島民")
	var person:Dictionary=world.state.players[token]
	var objects:Dictionary=world.state.regions.mine_4.objects
	for dimensions in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions
		person.region="mine_4"
		person.x=27.5
		person.y=24.5
		person.inventory.merge({"charcoal":8,"copper_ore":0},true)
		world.state.mine_depths.ready.erase("mine_4")
		var machine:=Drill.fresh(0)
		machine.merge({"type":"mine_drill","owner":token,"fuel":14},true)
		objects["28,24"]=machine
		var schema=preload("res://scripts/save_schema.gd")
		check(schema.validate(world.state.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Fixture is persistable")
		await refresh()
		app._interact()
		await frames()
		if app.modal==null or not app.modal.has_meta("mine_drill_cell"):
			check(false,"Real interaction opens drill work card")
			break
		await layout()
		check(control("DrillLocation").text.contains("4") and control("DrillFuel").text.contains("14 / 16") and control("DrillOutput").text.contains("銅礦"),"Regional output and fuel counters match live state")
		check(control("DrillStatus").text.contains("停用") and control("DrillCollect").disabled,"Stopped state and empty output")
		await press("DrillFeed_1")
		await press("DrillFeed_5")
		check(machine.fuel==16 and person.inventory.charcoal==6 and control("DrillFeed_1").disabled and control("DrillFuel").text.contains("背包 6"),"One and five feed controls respect remaining capacity")
		person.x=12.5
		await refresh()
		check(control("DrillToggle").disabled and control("DrillUnload").disabled,"Remote operation is disabled")
		person.x=27.5
		machine.owner="other-miner"
		await refresh()
		check(control("DrillToggle").disabled and control("DrillUnload").disabled,"Foreign machine is read-only")
		machine.owner=token
		await refresh()
		await press("DrillToggle")
		check(machine.enabled and world.step(.1,true) and machine.has("job"),"Button enables actual batch")
		await refresh()
		check(control("DrillStatus").text.contains("採掘中") and control("DrillStatus").text.contains("20"),"Active job countdown is visible")
		if dimensions.x==1024:check_motion()
		var toggle_bounds:Rect2=control("DrillToggle").get_global_rect()
		await press("DrillToggle")
		check(not machine.enabled and machine.has("job") and control("DrillStatus").text.contains("完成後停止"),"Stopping preserves active batch")
		check(control("DrillToggle").get_global_rect()==toggle_bounds,"Stop-running status does not move toggle")
		await layout()
		check(world.step(20,true) and machine.items.copper_ore==4,"Stopped job finishes")
		await refresh()
		check(control("DrillOutput").text.contains("4 / 32"),"Output counter updates on batch completion")
		await press("DrillCollect")
		var receipt:String=app.modal_feedback.text
		check(receipt.contains("已取回物品") and control("DrillBagOutput").text.contains("背包 4"),"Collect receipt and bag count update")
		check(world.step(1,true),"World clock continues")
		await refresh()
		check(app.modal_feedback.text==receipt,"Clock refresh keeps receipt")
		await press("DrillToggle")
		check(control("DrillStatus").text.contains("恢復"),"Shared cooldown visible while enabled")
		await press("DrillToggle")
		await press("DrillUnload")
		check(Drill.can_move(machine) and person.inventory.charcoal==21,"Unload recovers remaining fuel and leaves empty machine")
		person.region="home"
		await refresh()
		if app.modal!=null:check(control("DrillToggle")==null,"Leaving the region removes actionable controls")
		else:check(true,"Leaving the region closes actionable controls")
		person.region="mine_4"
		await refresh()
		if app.modal==null:
			app._interact()
			await frames()
		app.session.perform("remove",CELL)
		await frames()
		check(not objects.has("28,24") and (app.modal==null or control("DrillToggle")==null),"Actual dismantling removes operation controls")
		app._close_modal()
		if dimensions.x==1024:
			objects["28,24"]=machine
			await check_integrations(person,objects)
			objects.erase("28,24")
			objects.erase("26,24")
	app.session.shutdown()
	await create_timer(.35).timeout
	app.queue_free()
	await process_frame
	for suffix in ["",".bak",".tmp",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("MINE_DRILL_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
