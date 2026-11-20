extends SceneTree

const World:=preload("res://scripts/world.gd")

var app
var world:World
var token:String
var person:Dictionary
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func pad(id:JoyButton)->void:
	for down in [true,false]:
		var event:=InputEventJoypadButton.new()
		event.button_index=id
		event.pressed=down
		root.push_input(event)
	await process_frame

func run() -> void:
	root.size=Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://medium-sprinkler-%d.json"%OS.get_process_id()
	if app.session.host(0,"灑水島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var site:=Vector2i(40,34)
	var key:=World.key(site)
	person.inventory.merge({"iron_ingot":5,"copper_ingot":2},true)
	stand(site+Vector2i.DOWN)
	expect(not world.act(token,"early-build","build",site,"medium_sprinkler").ok,"Farming gate still enforced")
	person.harvests=World.FARMING_LEVEL_THRESHOLDS[World.MEDIUM_SPRINKLER_LEVEL-1]
	app._perform_build_action("build",site,"medium_sprinkler")
	await process_frame
	expect(person.inventory.iron_ingot==0 and person.inventory.copper_ingot==0,"Build consumes exactly five iron and two copper ingots")
	expect(world.state.objects.get(key,{}).get("sprinkler_daily",false),"Placed device uses the daily model")
	var industry:=World.INDUSTRY
	expect(industry.sprinkler_status(world.state.objects[key],0.0)=="已停止","New device reads stopped")
	expect(industry.sprinkler_status({"enabled":true,"water":0},0.0)=="等待補水","Empty enabled device waits for water")
	if not world.state.objects.has(key):
		quit(1)
		return
	var next_tile:=World.key(site+Vector2i.RIGHT)
	world.state.crops[next_tile]={"kind":"radish","growth":0.0,"wet":false,"owner":token,"remaining":1}
	stand(site+Vector2i.DOWN)
	app._interact()
	await process_frame
	expect(is_instance_valid(app.modal),"Interaction opens the sprinkler panel")
	var initial:int=app.session.counter
	await pad(JOY_BUTTON_X)
	expect(root.gui_get_focus_owner()==app.modal.find_child("SprinklerRefill",true,false) and app.session.counter==initial,"X focuses refill without acting")
	await pad(JOY_BUTTON_A)
	expect(world.state.objects[key].water==24 and not world.state.objects[key].enabled,"Refill does not toggle the sprinkler")
	await pad(JOY_BUTTON_X)
	expect(root.gui_get_focus_owner()==app.modal.find_child("SprinklerToggle",true,false),"X skips full refill and focuses enable")
	app.session.rates[1].clear()
	await pad(JOY_BUTTON_A)
	expect(world.state.objects[key].enabled and world.state.objects[key].water==24,"Panel enables and fills the sprinkler")
	expect(industry.sprinkler_status(world.state.objects[key],float(world.state.time))=="等待澆水","Filled device is ready to water")
	world.step(1.0,true)
	expect(world.state.crops[next_tile].wet and world.state.objects[key].next_water==World.WEATHER.DAY_SECONDS,"First run waters and schedules the next day")
	expect(industry.sprinkler_status(world.state.objects[key],float(world.state.time))=="今日已澆水","Successful daily watering updates the field status")
	expect(industry.sprinkler_status(world.state.objects[key],World.WEATHER.DAY_SECONDS)=="等待澆水","Daily field status resets tomorrow")
	app.session._send_snapshot(1)
	await create_timer(0.3).timeout
	var labels:Array=app.modal.find_children("*","Label",true,false)
	expect(labels.any(func(label): return label.text=="水量 23／24"),"Panel reflects water actually used")
	expect(labels.any(func(label): return label.text=="今天已澆水，明天再灑"),"Panel displays the next available watering day")
	await capture("medium-sprinkler.png")
	expect(world.save(),"Save the active sprinkler")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and reloaded.state.objects.get(key,{}).get("next_water")==World.WEATHER.DAY_SECONDS,"Reload preserves the daily schedule")
	app._close_modal()
	expect(world.act(token,"remove-new","remove",site).ok,"Dismantle daily sprinkler")
	expect(person.inventory.iron_ingot==5 and person.inventory.copper_ingot==2,"Daily sprinkler refunds its metal recipe")
	world.state.objects[key]={"type":"medium_sprinkler","owner":token,"items":{},"water":0,"enabled":false,
		"next_water":0.0,"last_water":-1.0}
	var legacy_before:=int(person.inventory.get("plank",0))
	expect(world.act(token,"remove-old","remove",site).ok,"Dismantle legacy sprinkler")
	expect(person.inventory.iron_ingot==5 and int(person.inventory.get("plank",0))==legacy_before+4,
		"Legacy sprinkler returns its original materials rather than metal")
	person.inventory.merge({"copper_ingot":4,"stone":4,"sprinkler_kit":1},true)
	app._perform_build_action("build",site,"sprinkler")
	expect(world.state.objects.get(key,{}).get("sprinkler_daily",false),"Small sprinkler made from metals uses daily schedule")
	expect(person.inventory.copper_ingot==0 and person.inventory.stone==0 and person.inventory.sprinkler_kit==1,"Default recipe spends four copper and four stone before considering the kit")
	var diagonal:=World.key(site+Vector2i.ONE)
	world.state.crops[diagonal]={"kind":"radish","growth":0.0,"wet":false,"owner":token,"remaining":1}
	world.state.crops[next_tile].wet=false
	app.session.rates[1].clear()
	world.act(token,"refill-small","refill_sprinkler",site)
	world.act(token,"enable-small","toggle_sprinkler",site)
	world.step(1.0,true)
	expect(world.state.crops[next_tile].wet and not world.state.crops[diagonal].wet,"Small daily sprinkler waters cardinal tiles only")
	expect(world.state.objects[key].water==11 and world.state.objects[key].next_water==World.WEATHER.DAY_SECONDS,"Small unit uses one water and waits until tomorrow")
	stand(site+Vector2i.DOWN)
	app._interact()
	await create_timer(0.3).timeout
	await capture("small-sprinkler.png")
	expect(world.save() and reloaded.load_world(path) and reloaded.state.objects[key].sprinkler_daily,"Small daily device survives save and load")
	app._close_modal()
	expect(world.act(token,"remove-small","remove",site).ok and person.inventory.copper_ingot==4 and person.inventory.stone==4,"Dismantling the metal model returns its own recipe")
	person.inventory.copper_ingot=0
	expect(world.act(token,"place-kit","build",site,"sprinkler").ok and world.state.objects[key].sprinkler_daily
		and world.state.objects[key].get(World.INDUSTRY.STARTER_SPRINKLER_FIELD)==true and person.inventory.sprinkler_kit==0,
		"The workbench kit places a daily model with kit provenance")
	stand(site+Vector2i.DOWN)
	app._interact()
	await create_timer(0.3).timeout
	expect(app.modal.find_children("*","Label",true,false).any(func(label):return label.text.contains("每天澆一次") and label.text.contains("不會穿過牆壁")),
		"The kit sprinkler panel explains the daily pass and wall blocking")
	await capture("starter-sprinkler.png")
	app._close_modal()
	expect(world.act(token,"remove-kit","remove",site).ok and person.inventory.sprinkler_kit==1,"Dismantling the kit model returns the kit")
	var bench:=Vector2i(37,34)
	world.state.objects[World.key(bench)]={"type":"bench","owner":token,"items":{}}
	person.inventory.merge({"plank":4,"hardwood":2,"iron_ingot":10,"glass":4},true)
	stand(bench+Vector2i.DOWN)
	expect(world.act(token,"woodwork-a","craft",bench,"woodwork_parts").ok and world.act(token,"woodwork-b","craft",bench,"woodwork_parts").ok,"Two workbench orders produce the four woodwork parts")
	expect(person.inventory.woodwork_parts==4 and person.inventory.plank==0 and person.inventory.hardwood==0,"Woodwork parts use only the shown materials")
	stand(site+Vector2i.DOWN)
	expect(not world.act(token,"large-locked","build",site,"large_sprinkler").ok,"Large sprinkler is locked before level eight")
	person.harvests=World.FARMING_LEVEL_THRESHOLDS[World.LARGE_SPRINKLER_LEVEL-1]
	app._perform_build_action("build",site,"large_sprinkler")
	expect(world.state.objects.get(key,{}).get("type")=="large_sprinkler" and world.blocked(site),"Large unit occupies one solid tile")
	expect(person.inventory.iron_ingot==0 and person.inventory.glass==0 and person.inventory.woodwork_parts==0,"Large unit costs exactly ten iron, four glass, and four woodwork parts")
	var far:=World.key(site+Vector2i(2,0))
	world.state.crops[far]={"kind":"radish","growth":0.0,"wet":false,"owner":token,"remaining":1}
	stand(site+Vector2i.DOWN)
	app._interact()
	await process_frame
	for node in app.modal.find_children("*","Button",true,false):
		if node.text in ["補滿水","啟用"]:node.pressed.emit()
	await process_frame
	expect(world.state.objects[key].water==48 and world.state.objects[key].enabled,"Large sprinkler is interactive and takes 48 water")
	world.step(1.0,true)
	expect(world.state.crops[far].wet,"Native game tick waters the tile two away")
	app.session._send_snapshot(1)
	await create_timer(0.3).timeout
	await capture("large-sprinkler-panel.png")
	app._close_modal()
	await capture("large-sprinkler-field.png")
	expect(app.view.sprinkler_sprays.has(key),"A real watering snapshot starts the sprinkler animation")
	var started:=float(app.view.sprinkler_sprays.get(key,-1.0))
	app.session._send_snapshot(1)
	await process_frame
	expect(float(app.view.sprinkler_sprays.get(key,-2.0))==started,"A repeated snapshot does not restart the spray")
	await create_timer(1.3).timeout
	app.session._send_snapshot(1)
	await capture("large-sprinkler-rest.png")
	expect(not app.view.sprinkler_sprays.has(key),"Spray expires in real time even if world time stands still")
	expect(world.save() and reloaded.load_world(path) and reloaded.state.objects[key].type=="large_sprinkler","Large sprinkler survives save and reload")
	app.session.shutdown()
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("MEDIUM_SPRINKLER_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
