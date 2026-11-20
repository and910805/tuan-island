extends SceneTree
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const FRAME:=World.WALL_FIXTURES.BARK_FRAME
const FRAME_SITE:=Vector2i(42,35)
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func run() -> void:
	root.size=Vector2i(1280,800) if "--wide" in OS.get_cmdline_user_args() else Vector2i(1024,640)
	var app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	if "--large-text" in OS.get_cmdline_user_args():
		app.sound.preferred_text_scale=3
		app._apply_font_scale_tree()
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
	app.session._send_snapshot(1)
	app._journal()
	await press(app,"DiandianSketchBookmark")
	var count:=app.modal.find_child("DiandianSketchCount",true,false) as Label
	expect(count!=null and count.text.ends_with("0／3"),"The handbook opens an empty sketchbook with the correct count")
	await capture("01-empty-sketchbook")
	app._close_modal()
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
		var crop_before:Dictionary=world.state.crops[World.key(tile)].duplicate(true)
		var button:=app.modal.find_child("CropSketch",true,false) as Button if is_instance_valid(app.modal) else null
		expect(button!=null and not button.disabled,"Ordinary plot interaction shows the crop sketch action")
		if button!=null:button.pressed.emit()
		await process_frame
		expect(app.session.snapshot.own_crop_sketches.has(kind),"Button records only the observed crop")
		expect(world.state.crops[World.key(tile)]==crop_before,"A sketch leaves the crop and its permissions unchanged")
		expect(not world.act(token,"repeat-crop-sketch",Goals.SKETCH_ACTION,tile).ok,"The same crop cannot count twice")
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
		if id=="cow":
			expect(not world.act(token,"sketch-before-adoption",Goals.SKETCH_ACTION,animal_cell,id).ok,"The empty cow station cannot count as an animal")
			await press(app,"LivestockAdopt")
			expect(World.LIVESTOCK.adopted(world.state.get("livestock",{}),id),"Adoption uses the real feeding station")
			app._interact()
			await process_frame
		var animals_before:Dictionary=world.state.get("livestock",{}).duplicate(true)
		var button:=app.modal.find_child("AnimalSketch",true,false) as Button if is_instance_valid(app.modal) else null
		expect(button!=null,"Animal menu exposes the sketch action for "+id)
		if button!=null:button.pressed.emit()
		await process_frame
		expect(app.session.snapshot.own_crop_sketches.has(id),"Animal observation counts toward the same goal")
		expect(world.state.get("livestock",{})==animals_before,"Sketching leaves the animals and their care state unchanged")
	var at:Vector2i=World.bond_place(world.state,"diandian")[1]
	person.region=World.RESIDENT_BOND.GARDEN_REGION
	person.x=at.x+0.5
	person.y=at.y+0.5
	app.session._send_snapshot(1)
	app.session.rates[1].clear()
	Tasks.bond_goal(app,"diandian",1)
	await press(app,"DiandianSketchBook")
	count=app.modal.find_child("DiandianSketchCount",true,false) as Label
	expect(count!=null and count.text.ends_with("3／3"),"The sketchbook shows all three subjects before reporting")
	await capture("02-complete-sketchbook")
	await press(app,"BookcaseBack")
	await press(app,"BondGoalDo")
	expect(app.session.snapshot.resident_goals.diandian["1"].state=="done","The three sketches finish Diandian's event")
	await press(app,"DiandianSketchStickerAlbum")
	expect(app.modal.find_child("CollectionTab1",true,false)!=null,"The reward goes straight to the crop almanac")
	await capture("03-reward-stickers")
	Tasks.bond_goal(app,"diandian",1)
	await press(app,"DiandianSketchEaselPattern")
	var title:=app.modal.find_child("BuildTitle",true,false) as Label
	expect(title!=null and title.text==World.BUILD.sketch_easel.name,"The reward opens the real workshop recipe")
	await press(app,"BuildPlace")
	var easel:=Vector2i(39,34)
	person.region=World.REGIONS.HOME
	person.x=easel.x+1.5
	person.y=easel.y+0.5
	app.session._send_snapshot(1)
	app.session.rates[1].clear()
	var before_wood:=int(person.inventory.wood)
	var before_fiber:=int(person.inventory.fiber)
	app._perform_build_action("build",easel,"sketch_easel")
	await process_frame
	expect(app.session.snapshot.objects.get(World.key(easel),{}).get("type")=="sketch_easel","Earned sketch easel is placeable")
	expect(int(person.inventory.wood)==before_wood-4 and int(person.inventory.fiber)==before_fiber-1,"Easel uses exactly the listed materials")
	await capture("sketch-easel")
	person.x=easel.x+1.1
	app.session._send_snapshot(1)
	app._interact()
	await process_frame
	var visible_labels:=PackedStringArray()
	for label in app.modal.find_children("*","Label",true,false):
		if label.is_visible_in_tree():visible_labels.append(label.text)
	expect("點點的菜園貼紙" in visible_labels,"The crop almanac shows the unlocked sticker section")
	expect("糯米雞" in visible_labels and "奶糖牛" in visible_labels,"The mixed sketch collection shows both animal stickers")
	expect(app.session.snapshot.players[app.session.own_id].get("collection",{}).get("crops",{}).is_empty(),"Sketches do not mark unharvested crops as collected")
	await capture("crop-sketch-stickers")
	var pose:="cup" if "--wide" in OS.get_cmdline_user_args() else "grass"
	await visit_pose(app,world,token,person,pose)
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.objects.get(World.key(easel),{}).get("type")=="sketch_easel","Built easel survives a full reload")
	expect(loaded.state.players[token].get(Goals.SKETCH_KEY,{})=={"radish":true,"chicken":true,"cow":true} and Goals.done(loaded.state.players[token],"diandian").has(1),"Personal sketches and the completed reward survive reload")
	expect(Goals.done(loaded.state.players[token],"diandian").get(2)==pose and loaded.state.objects.get(World.key(FRAME_SITE),{}).get(World.BARK_FRAME.FIELD)==World.BARK_FRAME.SKETCH,"The chosen pose and displayed frame survive reload")
	expect(loaded.state.crops.get("38,34",{}).get("owner_sow",false),"The independent plot policy survives a full reload")
	expect(loaded.state.crops.get("38,34",{}).get("owner_water",false),"Watering policy survives the same reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("CROP_SKETCH_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func visit_pose(app,world:World,token:String,person:Dictionary,pose:String) -> void:
	app._close_modal()
	# F08 friendship is earned through World.act. Fixture limits: the two bluebells are put in the bag,
	# the player is set on Diandian's cell and the clock is moved one game day. No points are written.
	const bond:=World.RESIDENT_BOND
	var post_cell:Vector2i=bond.GARDEN_CELL
	var today:int=bond.day(float(world.state.time))
	person.inventory["bluebell"]=int(person.inventory.get("bluebell",0))+2
	var bluebells:=int(person.inventory.bluebell)
	person.region=bond.GARDEN_REGION
	person.x=post_cell.x+0.5
	person.y=post_cell.y+0.5
	expect(bond.record(person,"diandian")=={"points":1,"talk_day":-1,"gift_day":-1} and bond.stage(person,"diandian")==1,"Before F08 Diandian holds only the first-meeting record: no daily talk, no gift, below the second stage")
	expect(world.act(token,"f08-talk-day-1","resident_talk",post_cell,"diandian").ok and bond.points(person,"diandian")==1+bond.TALK_POINTS,"The first talk of the day earns one point")
	expect(not world.act(token,"f08-talk-day-1-again","resident_talk",post_cell,"diandian").ok and bond.points(person,"diandian")==1+bond.TALK_POINTS,"A second talk on the same day is refused and earns nothing")
	expect(world.act(token,"f08-gift-day-1","resident_gift",post_cell,"diandian:bluebell").ok and bond.points(person,"diandian")==1+bond.TALK_POINTS+bond.LIKED_POINTS,"A liked bluebell earns the liked-gift points once")
	expect(world.act(token,"f08-gift-day-1-again","resident_gift",post_cell,"diandian:bluebell").ok and bond.points(person,"diandian")==1+bond.TALK_POINTS+bond.LIKED_POINTS and int(person.inventory.bluebell)==bluebells-2,"A second gift on the same day is accepted and consumed but earns nothing")
	expect(bond.stage(person,"diandian")==1,"One day of talk and gifts stays below the second stage")
	world.state.time=float(world.state.time)+World.Village.DAY
	expect(world.act(token,"f08-talk-day-2","resident_talk",post_cell,"diandian").ok and bond.record(person,"diandian")=={"points":bond.THRESHOLDS[1],"talk_day":today+1,"gift_day":today} and bond.stage(person,"diandian")==2,"The next day's talk reaches the second stage through earned points only")
	person.region=World.REGIONS.HOME
	person.inventory.wood+=12
	person.inventory["resin"]=int(person.inventory.get("resin",0))+2
	var post:=World.RESIDENT_BOND.GARDEN_CELL
	var support:=FRAME_SITE+Vector2i.UP
	for at:Vector2i in [FRAME_SITE,support]:world.state.removed[World.key(at)]=true
	person.x=FRAME_SITE.x+0.5
	person.y=FRAME_SITE.y+1.3
	expect(world.act(token,"pose-support","build",support,"wall").ok,"Build a real wall for the eventual reward")
	var early:=world.act(token,"frame-early","build",FRAME_SITE,FRAME)
	expect(not early.ok and early.message==Goals.BARK_FRAME_LOCK,"An unfinished story keeps the frame pattern locked even with a wall")
	var blueprint:={"version":1,"name":"樹皮畫框","width":1,"height":1,"pieces":[{"kind":FRAME,"x":0,"y":0}]}
	expect(not world.quote_blueprint(token,blueprint,FRAME_SITE).ok,"A blueprint cannot bypass the frame unlock")
	person.region=World.RESIDENT_BOND.GARDEN_REGION
	person.x=post.x+0.5
	person.y=post.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)
	Tasks.bond_goal(app,"diandian",2)
	await press(app,"BondGoalOption_"+pose)
	var finish:=app.modal.find_child("BondGoalDo",true,false) as Button
	expect(finish!=null and finish.disabled,"A pose choice alone is not enough")
	await press(app,"DiandianSit")
	expect(person.get(Goals.DIANDIAN_SEAT_KEY,false) and Vector2i(floori(person.x),floori(person.y)) in Goals.DIANDIAN_SEATS,"Sit on the bank through the game control")
	for id:String in ["knees","grass","cup"]:
		var option:=app.modal.find_child("BondGoalOption_"+id,true,false) as Button
		expect(option!=null and option.icon!=null,"Pose has a distinct illustration: "+id)
	await capture("04-pose-options")
	app._close_modal()
	await capture("05-seated-at-the-pond")
	Tasks.bond_goal(app,"diandian",2)
	await press(app,"BondGoalOption_"+pose)
	await press(app,"BondGoalDo")
	expect(Goals.done(person,"diandian").get(2)==pose and not person.has(Goals.DIANDIAN_SEAT_KEY),"Finishing preserves the pose and ends sitting")
	var reward:=app.modal.find_child("DiandianBarkFramePattern",true,false) as Button
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	expect(reward!=null and scroll!=null and scroll.get_global_rect().encloses(reward.get_global_rect()),"The frame pattern button stays fully visible")
	await capture("06-pose-reward")
	await press(app,"DiandianBarkFramePattern")
	var title:=app.modal.find_child("BuildTitle",true,false) as Label
	expect(title!=null and title.text==World.BUILD[FRAME].name,"Event opens the frame recipe")
	person.region=World.REGIONS.HOME
	person.x=FRAME_SITE.x+0.5
	person.y=FRAME_SITE.y+1.3
	app.session._send_snapshot(1)
	app.session.rates[1].clear()
	expect(world.quote_blueprint(token,blueprint,FRAME_SITE).ok,"The same blueprint is available once earned")
	# Visit the same unlocked recipe once back at home to place it.
	app._close_modal()
	app.life_panels.build_menu(app,FRAME)
	await press(app,"BuildPlace")
	app._perform_build_action("build",FRAME_SITE,FRAME)
	expect(world.state.objects.get(World.key(FRAME_SITE),{}).get("type")==FRAME,"Unlocked frame mounts on the wooden wall")
	app._select_tool("hoe")
	app._interact()
	await press(app,"BarkFrameSketch")
	expect(world.state.objects.get(World.key(FRAME_SITE),{}).get(World.BARK_FRAME.FIELD)==World.BARK_FRAME.SKETCH,"The frame can display the earned drawing")
	await capture("07-bark-frame")

func press(app,id:String) -> void:
	var button:=app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null
	expect(button!=null and not button.disabled,"Enabled action: "+id)
	if button!=null and not button.disabled:button.pressed.emit()
	await process_frame
	await process_frame

func capture(name:String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await create_timer(0.25).timeout
			await RenderingServer.frame_post_draw
			var output:=arg.trim_prefix("--capture-dir=").path_join(name+".png")
			expect(root.get_texture().get_image().save_png(output)==OK,"Capture "+name)
