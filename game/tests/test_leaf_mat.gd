extends SceneTree

const World=preload("res://scripts/world.gd")
const Design=World.BLUEPRINT_DESIGN
const Industry=World.INDUSTRY
const SITE:=Vector2i(40,34)
const COPY:=Vector2i(43,34)
const END:=SITE+Vector2i.ONE
var app
var world:World
var owner:String
var output:String
var path:String
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

func press(name:String)->bool:
	var control:=app.modal.find_child(name,true,false) as Button if is_instance_valid(app.modal) else null
	if not expect(control!=null and not control.disabled,"Available button "+name):return false
	control.pressed.emit()
	return true

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Screenshot "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.22).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("LEAF_MAT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func mat_shade(at:Vector2i)->String:
	return world.state.ground.get(World.key(at),{}).get("leaf_mat_shade","light")

func valid_save(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://leaf-floor-mat-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="leaf-mat-owner"
	if app.session.host(0,"森林木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=40.5
	person.y=33.5
	person.inventory.merge({"fiber":24,"chime_herb":6},true)
	world.state.time=720.0
	for origin:Vector2i in [SITE,COPY]:
		for offset:Vector2i in Industry.SQUARE_CELLS:
			world.state.removed[World.key(origin+offset)]=true
	var ground_key:=World.key(END)
	world.state.ground[ground_key]={"type":"path","owner":owner,"items":{}}
	expect(not world.act(owner,"overlap","build",SITE,Industry.LEAF_MAT).ok,"Cannot cover an existing path even on the far corner")
	expect(world.state.ground.size()==1 and person.inventory.fiber==24,"Refused placement writes no parts or costs")
	world.state.ground.erase(ground_key)
	app.session._send_snapshot(1)
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="蘑菇森林":
			entry.pressed.emit()
			press("BuildSlot_"+Industry.LEAF_MAT+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	press("BuildPlace")
	expect(app.building==Industry.LEAF_MAT and app.view.build_placement_offsets(Industry.LEAF_MAT)==Industry.SQUARE_CELLS,"Catalogue selects a 2×2 ground item")
	app._perform_build_action("build",SITE,Industry.LEAF_MAT)
	if not expect(world.state.ground.get(World.key(SITE),{}).get("type")==Industry.LEAF_MAT,"Mat is placed through the game UI"):
		await finish()
		return
	expect(person.inventory.fiber==12 and person.inventory.chime_herb==3 and person.builds==1,"One placement costs 12 fiber and 3 herbs")
	for offset:Vector2i in Industry.SQUARE_CELLS:
		var tile:=SITE+offset
		expect(World.station_anchor(world.state.ground,tile)==SITE and not world.blocked(tile),"Every part belongs to the same walkable mat")
	world.move_player(owner,Vector2.DOWN,0.55)
	world.move_player(owner,Vector2.RIGHT,0.28)
	expect(Vector2i(Vector2(person.x,person.y).floor())==END,"Character actually crosses the rug to the far corner")
	app.session._send_snapshot(1)
	app._select_tool("hoe")
	expect(app.view.interaction_focus()=="leaf_mat","The world advertises the context interaction on the mat")
	await capture("mat-light")
	app._interact()
	var light:=app.modal.find_child("LeafMat_light",true,false) as Button if is_instance_valid(app.modal) else null
	expect(light!=null and light.disabled,"The menu marks the existing shade")
	await capture("mat-colors")
	press("LeafMat_dark")
	expect(mat_shade(SITE)=="dark" and person.inventory.fiber==12 and person.inventory.chime_herb==3 and person.builds==1,"Changing color costs nothing and leaves one placement")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.ground.get(World.key(SITE),{}).get("leaf_mat_shade")=="dark","Reopening the save restores the shade and footprint")
	var broken:Dictionary=world.state.duplicate(true)
	broken.ground.erase(ground_key)
	expect(not valid_save(broken),"Incomplete mats are rejected on load")
	broken=world.state.duplicate(true)
	broken.ground[ground_key].leaf_mat_shade="dark"
	expect(not valid_save(broken),"Shade is valid only on the anchor")
	var design:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,2)),"苔綠葉片",World.BUILD,World.NAMES)
	expect(not Design.capture(world.region_snapshot("home"),owner,Rect2i(END,Vector2i.ONE),"切角",World.BUILD,World.NAMES).ok,"A captured blueprint cannot cut through a mat")
	if expect(design.ok and design.blueprint.pieces.size()==1 and design.blueprint.pieces[0].settings.leaf_mat_shade=="dark","A single blueprint piece remembers all four tiles and shade"):
		var quote:=world.quote_blueprint(owner,design.blueprint,COPY,1)
		if expect(quote.ok,"Rotated mat blueprint has a valid quote: "+str(quote.message)):
			var result:=world.apply_blueprint(owner,"a".repeat(32),design.blueprint,COPY,1,quote.hash)
			expect(result.ok and mat_shade(COPY)=="dark" and person.inventory.fiber==0,"Rotated blueprint installs and charges for one dark mat")
	expect(world.act(owner,"back-to-light",Industry.MAT_SHADE_ACTION,END,"light").ok and mat_shade(SITE)=="light","Reverting to light succeeds through a corner")
	world.move_player(owner,Vector2.DOWN,0.28)
	app.session._send_snapshot(1)
	await create_timer(3.1).timeout
	await capture("mat-in-world")
	var guest:="leaf-mat-guest"
	world.add_player(guest,"訪客",Vector2(41.5,35.5))
	expect(not world.act(guest,"paint",Industry.MAT_SHADE_ACTION,END,"dark").ok,"Guest cannot recolor another player's mat")
	expect(not world.act(guest,"lift","remove",END).ok,"Guest cannot dismantle another player's mat")
	var dismantle:=world.act(owner,"lift","remove",END)
	expect(dismantle.ok and world.state.players[owner].inventory.fiber==12,"Dismantling any corner refunds one recipe once")
	for offset:Vector2i in Industry.SQUARE_CELLS:
		expect(not world.state.ground.has(World.key(SITE+offset)),"Dismantling removes the complete rug")
	var undo:=world.undo_summary(owner)
	if expect(undo.get("available",false),"Last removal may be undone"):
		var restored:=world.act(owner,"restore",World.UNDO_ACTION,SITE,undo.id)
		expect(restored.ok and world.state.ground.has(ground_key),"Undo restores the complete footprint")
	await finish()
