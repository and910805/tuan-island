extends SceneTree

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const Picture=World.BARK_FRAME
const KIND:=World.WALL_FIXTURES.BARK_FRAME
const SITE:=Vector2i(42,35)
const COPY:=Vector2i(43,35)
const SUPPORT:=SITE+Vector2i.UP
var app
var world:World
var owner:String
var path:String
var photo_path:String
var output:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(success:bool,label:String)->bool:
	checks+=1
	if not success:
		failures+=1
		push_error(label)
	return success

func button(name:String)->Button:
	return app.modal.find_child(name,true,false) as Button if is_instance_valid(app.modal) else null

func press(name:String)->bool:
	var control:=button(name)
	if not expect(control!=null and not control.disabled,"Available button "+name):return false
	control.pressed.emit()
	return true

func frame(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await create_timer(0.34).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Screenshot "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.2).timeout
	for file in [path,path+".bak",path+".writer-lock",photo_path]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("BARK_FRAME_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func display(tile:=SITE)->String:
	return world.state.objects.get(World.key(tile),{}).get(Picture.FIELD,"")

func valid_save(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://bark-frame-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="bark-frame-%d"%Time.get_ticks_usec()
	if app.session.host(0,"森林木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=42.5
	person.y=36.3
	person.inventory.merge({"wood":60,"resin":4},true)
	world.state.time=720.0
	for target in [SITE,COPY,SUPPORT,COPY+Vector2i.UP]:
		world.state.removed[World.key(target)]=true
	var earned:={"diandian":{"1":"","2":"knees"}}
	person.bonds={"diandian":{"points":10,"talk_day":-1,"gift_day":-1}}
	person.bond_goals=earned.duplicate(true)
	expect(not world.act(owner,"unmounted","build",SITE,KIND).ok,"An unsupported frame cannot be built even with Diandian 2 done")
	person.erase("bond_goals")
	expect(world.act(owner,"wall","build",SUPPORT,"wall").ok and world.act(owner,"wall2","build",COPY+Vector2i.UP,"wall").ok,"Builds two actual wood wall sections")
	var wood_before:=int(person.inventory.wood)
	var resin_before:=int(person.inventory.resin)
	# Frame construction needs the player's own finished Diandian 2: refused on a supported wall, with nothing spent.
	var locked:=world.act(owner,"locked","build",SITE,KIND)
	expect(not locked.ok and locked.get("message","")==World.RESIDENT_GOALS.BARK_FRAME_LOCK,"A supported frame is refused until Diandian 2 is done")
	expect(not world.state.objects.has(World.key(SITE)) and person.inventory.wood==wood_before and person.inventory.resin==resin_before,"The refused frame consumes nothing and places nothing")
	app.session._send_snapshot(1)
	app._perform_build_action("build",SITE,KIND)
	expect(not world.state.objects.has(World.key(SITE)) and person.inventory.resin==resin_before,"The build folio path is refused by the same server rule")
	# FIXTURE: a legacy frame already stored in the world (built before the rule) keeps working, but its sketch stays locked.
	world.state.objects[World.key(COPY)]={"type":KIND,"owner":owner,"items":{}}
	expect(not world.act(owner,"legacy-sketch",Picture.ACTION,COPY,Picture.SKETCH).ok and display(COPY).is_empty(),"A legacy frame cannot show the sketch before Diandian 2")
	world.state.objects.erase(World.key(COPY))
	person.bond_goals=earned.duplicate(true)
	app.session._send_snapshot(1)
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="蘑菇森林":
			entry.pressed.emit()
			press("BuildSlot_"+KIND+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	press("BuildPlace")
	app._perform_build_action("build",SITE,KIND)
	if not expect(world.state.objects.get(World.key(SITE),{}).get("type")==KIND,"Uses ordinary build folio hand placement"):
		await finish()
		return
	expect(person.inventory.wood==wood_before-8 and person.inventory.resin==resin_before-2,"Consumes only recipe costs")
	expect(not world.blocked(SITE) and not world.act(owner,"remove-wall","remove",SUPPORT).ok,"Front remains walkable and the occupied support cannot be removed")
	app._select_tool("hoe")
	app.session._send_snapshot(1)
	app._interact()
	var sketch:=button("BarkFrameSketch")
	expect(sketch!=null and not sketch.disabled,"Sketch option is open for a frame built after the story")
	press("BarkFrameSketch")
	expect(display()==Picture.SKETCH,"Earned Diandian sketch displays in the frame")
	await frame("bark-frame-sketch")
	photo_path=app.LifeTasks.aru_photo_path(app)
	if DisplayServer.get_name()=="headless":
		var synthetic:=Image.create_empty(64,40,false,Image.FORMAT_RGB8)
		synthetic.fill(Color("8fbd9f"))
		expect(synthetic.save_png(photo_path)==OK,"Creates a codec fixture")
	else:
		expect(await app.LifeTasks.capture_island_photo(app,photo_path),"Normal photo capture writes a saved island photograph")
	app._interact()
	press("BarkPhoto_0")
	var mounted:=display()
	expect(mounted.begins_with("photo:") and Picture.photo_bytes(mounted).size()==Picture.PHOTO_BYTES,"Chooser mounts the saved photograph as a bounded world thumbnail")
	expect(Session.extra_allowed(Picture.ACTION,mounted) and not Session.extra_allowed("buy",mounted),"Photo exceptions are limited to this action")
	await frame("bark-frame-photo-world")
	app._interact()
	var preview:=app.modal.find_child("BarkFramePicture",true,false) as TextureRect if is_instance_valid(app.modal) else null
	expect(preview!=null and preview.texture.get_size()==Vector2(Picture.SIZE),"Close-up shows the world thumbnail")
	await frame("bark-frame-photo-view")
	app._close_modal()
	DirAccess.remove_absolute(photo_path)
	app._interact()
	preview=app.modal.find_child("BarkFramePicture",true,false)
	expect(preview.texture.get_size()==Vector2(Picture.SIZE) and button("BarkPhoto_0")==null,"Deleting the album file leaves the mounted copy intact")
	app._close_modal()
	var guest:="bark-frame-guest"
	world.add_player(guest,"訪客",Vector2(43.5,36.3))
	expect(app.session.public_state("home",guest).objects[World.key(SITE)][Picture.FIELD]==mounted,"Visitors receive the displayed thumbnail")
	expect(not world.act(guest,"change",Picture.ACTION,SITE,"").ok and display()==mounted,"Visitor cannot take down or replace the picture")
	expect(not world.act(owner,"invalid",Picture.ACTION,SITE,"photo:xyz").ok and display()==mounted,"Malformed uploads leave the old image in place")
	var invalid:Dictionary=world.state.duplicate(true)
	invalid.objects[World.key(SITE)][Picture.FIELD]="photo:xyz"
	expect(not valid_save(invalid),"Save loader rejects damaged photo records")
	var saved:=World.new()
	expect(saved.load_world(path) and saved.state.objects[World.key(SITE)][Picture.FIELD]==mounted,"Reopening the world retains the photo independently of the local PNG")
	var design:=World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i.ONE),"畫框",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"Blueprints carry the wooden frame without the personal image")
	expect(world.act(owner,"move","move_object",SITE,World.key(COPY)).ok and display(COPY)==mounted,"Moving to another owned wall retains the displayed image")
	expect(world.act(owner,"clear",Picture.ACTION,COPY).ok and display(COPY).is_empty(),"Owner may clear the frame")
	expect(world.act(owner,"remove","remove",COPY).ok and person.inventory.resin==resin_before,"The frame returns the recipe once dismantled")
	await finish()
