extends SceneTree
const World:=preload("res://scripts/world.gd")
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func run() -> void:
	var app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://sketch-ui-%d.json"%OS.get_process_id()
	var host_error:int=app.session.host(0,"速寫旅人",path)
	expect(host_error==OK,"Open a temporary island")
	if host_error!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	# Fixture: the player has met Diandian. Everything else uses the game actions.
	person.bonds={"diandian":{"points":1,"talk_day":-1,"gift_day":-1}}
	var tile:=Vector2i(38,34)
	for kind:String in ["radish"]:
		person.x=tile.x+0.5
		person.y=tile.y+0.5
		app.session.rates[1].clear()
		app.session.perform("hoe",tile)
		app.session.perform("seed",tile,kind)
		app._interact()
		await process_frame
		var sow_access:=app.modal.find_child("PlotSowAccess",true,false) as Button
		expect(sow_access!=null and sow_access.text=="只限田主播種","The home plot exposes its independent sowing control")
		if sow_access:sow_access.pressed.emit()
		expect(app.session.snapshot.crops[World.key(tile)].get("owner_sow",false),"Plot control updates the public crop policy")
		app._interact()
		await process_frame
		var water_access:=app.modal.find_child("PlotWaterAccess",true,false) as Button
		expect(water_access!=null and water_access.text=="只限田主澆水","Watering has a separate control")
		if water_access:water_access.pressed.emit()
		expect(app.session.snapshot.crops[World.key(tile)].get("owner_water",false),"Watering control changes only its own policy")
		app._interact()
		await process_frame
		var button:=app.modal.find_child("CropSketch",true,false) as Button if is_instance_valid(app.modal) else null
		expect(button!=null and not button.disabled,"Ordinary plot interaction shows the crop sketch action")
		if button!=null:button.pressed.emit()
		await process_frame
		expect(app.session.snapshot.own_crop_sketches.has(kind),"Button records only the observed crop")
		tile+=Vector2i.RIGHT
	world.state.picnic=true
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	for id:String in ["chicken","cow"]:
		var animal_cell:Vector2i=World.CHICKEN_CELL if id=="chicken" else World.LIVESTOCK.ANIMALS[id].cell
		person.x=animal_cell.x+0.5
		person.y=animal_cell.y+0.5
		app.session._send_snapshot(1)
		app.session.rates[1].clear()
		app._interact()
		await process_frame
		var button:=app.modal.find_child("AnimalSketch",true,false) as Button if is_instance_valid(app.modal) else null
		expect(button!=null,"Animal menu exposes the sketch action for "+id)
		if button!=null:button.pressed.emit()
		await process_frame
		expect(app.session.snapshot.own_crop_sketches.has(id),"Animal observation counts toward the same goal")
	var at:Vector2i=World.bond_place(world.state,"diandian")[1]
	person.region=World.RESIDENT_BOND.GARDEN_REGION
	person.x=at.x+0.5
	person.y=at.y+0.5
	app.session._send_snapshot(1)
	app.session.rates[1].clear()
	app.session.perform("resident_goal",at,"diandian:1::")
	await process_frame
	expect(app.session.snapshot.resident_goals.diandian["1"].state=="done","The three sketches finish Diandian's event")
	var easel:=Vector2i(39,34)
	person.region=World.REGIONS.HOME
	person.x=easel.x+1.5
	person.y=easel.y+0.5
	app.session._send_snapshot(1)
	app.session.rates[1].clear()
	var before_wood:=int(person.inventory.wood)
	var before_fiber:=int(person.inventory.fiber)
	app.session.perform("build",easel,"sketch_easel")
	await process_frame
	expect(app.session.snapshot.objects.get(World.key(easel),{}).get("type")=="sketch_easel","Earned sketch easel is placeable")
	expect(int(person.inventory.wood)==before_wood-4 and int(person.inventory.fiber)==before_fiber-1,"Easel uses exactly the listed materials")
	await capture("sketch-easel")
	app._interact()
	await process_frame
	var visible_labels:=PackedStringArray()
	for label in app.modal.find_children("*","Label",true,false):
		if label.is_visible_in_tree():visible_labels.append(label.text)
	expect("點點的菜園貼紙" in visible_labels,"The crop almanac shows the unlocked sticker section")
	expect("糯米雞" in visible_labels and "奶糖牛" in visible_labels,"The mixed sketch collection shows both animal stickers")
	expect(app.session.snapshot.players[app.session.own_id].get("collection",{}).get("crops",{}).is_empty(),"Sketches do not mark unharvested crops as collected")
	await capture("crop-sketch-stickers")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.objects.get(World.key(easel),{}).get("type")=="sketch_easel","Built easel survives a full reload")
	expect(loaded.state.crops.get("38,34",{}).get("owner_sow",false),"The independent plot policy survives a full reload")
	expect(loaded.state.crops.get("38,34",{}).get("owner_water",false),"Watering policy survives the same reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("CROP_SKETCH_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))


func capture(name:String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var output:=arg.trim_prefix("--capture-dir=").path_join(name+".png")
			expect(root.get_texture().get_image().save_png(output)==OK,"Capture "+name)
