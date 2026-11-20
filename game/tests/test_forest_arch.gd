extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const Art=preload("res://scripts/forest_arch_art.gd")
const KIND:=Industry.FOREST_ARCH
const SITE:=Vector2i(38,34)
const CENTER:=SITE+Vector2i.RIGHT
const FAR_POST:=SITE+Vector2i(2,0)
const ROTATED:=Vector2i(42,33)
const MOVED:=Vector2i(38,36)
var app
var world:World
var owner:String
var path:String
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

func press(name:String)->bool:
	var control:=app.modal.find_child(name,true,false) as Button if is_instance_valid(app.modal) else null
	if not expect(control!=null and not control.disabled,"Available button "+name):return false
	control.pressed.emit()
	return true

func frame(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Screenshot "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.2).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("FOREST_ARCH_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func set_position(person:Dictionary,at:Vector2)->void:
	person.x=at.x
	person.y=at.y

func walk(direction:Vector2)->void:
	for step in 15:world.move_player(owner,direction,0.04)

func has_arch(tile:Vector2i)->bool:
	return world.state.objects.get(World.key(tile),{}).get("type")==KIND

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://forest-arch-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="forest-arch-owner"
	if app.session.host(0,"森林木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.inventory.merge({"hardwood":32,"fiber":12,"chime_herb":8},true)
	world.state.time=700.0
	set_position(person,Vector2(39.5,33.4))
	for origin:Vector2i in [SITE,MOVED,ROTATED]:
		for offset:Vector2i in Industry.station_cells(KIND,origin==ROTATED):
			world.state.removed[World.key(origin+offset)]=true
	app.session._send_snapshot(1)
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="蘑菇森林":
			entry.pressed.emit()
			press("BuildSlot_"+KIND+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	await frame("forest-arch-catalogue")
	press("BuildPlace")
	expect(app.building==KIND and app.view.build_placement_offsets(KIND)==Industry.station_cells(KIND),"Builder reserves all three horizontal tiles")
	app._perform_build_action("build",SITE,KIND)
	if not expect(has_arch(SITE) and has_arch(CENTER) and has_arch(FAR_POST),"Normal placement writes all three linked parts"):
		await finish()
		return
	expect(person.inventory.hardwood==16 and person.inventory.fiber==6 and person.inventory.chime_herb==4,"Only one recipe is charged for the three tiles")
	expect(world.blocked(SITE) and not world.blocked(CENTER) and world.blocked(FAR_POST),"Only the posts have collision")
	walk(Vector2.DOWN)
	expect(person.y>35.4,"Ordinary southbound movement passes through the opening")
	walk(Vector2.UP)
	expect(person.y<34.0,"Ordinary northbound movement also passes")
	for post:Vector2i in [SITE,FAR_POST]:
		set_position(person,Vector2(post)+Vector2(0.5,-0.55))
		walk(Vector2.DOWN)
		expect(person.y<34.0,"The character stops at the post "+World.key(post))
	var rooms:=preload("res://scripts/house_rooms.gd")
	expect(rooms._walkable({CENTER:true},world.state.objects,CENTER) and not rooms._walkable({FAR_POST:true},world.state.objects,FAR_POST),"Indoor walkability agrees with the two posts and open middle")
	app._select_tool("hoe")
	set_position(person,Vector2(CENTER)+Vector2(0.5,0.62))
	app.session._send_snapshot(1)
	await frame("forest-arch-passage")
	var design:=World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(3,1)),"森林拱門",World.BUILD,World.NAMES)
	expect(not World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,1)),"半道門",World.BUILD,World.NAMES).ok,"A capture cannot cut the arch in half")
	if expect(design.ok and design.blueprint.pieces.size()==1,"One blueprint piece contains the whole arch"):
		set_position(person,Vector2(41.5,34.5))
		var quote:=world.quote_blueprint(owner,design.blueprint,ROTATED,1)
		if expect(quote.ok,"Rotated blueprint can be built: "+str(quote.message)):
			var applied:=world.apply_blueprint(owner,"a".repeat(32),design.blueprint,ROTATED,1,quote.hash)
			expect(applied.ok and Industry.is_vertical(world.state.objects[World.key(ROTATED)]),"Rotated instance commits all three parts")
	expect(world.blocked(ROTATED) and not world.blocked(ROTATED+Vector2i.DOWN) and world.blocked(ROTATED+Vector2i(0,2)),"The vertical version also leaves only its center open")
	walk(Vector2.RIGHT)
	expect(person.x>43.5,"A character can walk east through the rotated version")
	set_position(person,Vector2(ROTATED+Vector2i.DOWN)+Vector2(0.5,0.5))
	app.session._send_snapshot(1)
	await frame("forest-arch-rotated")
	var restored:=World.new()
	expect(restored.load_world(path) and not restored.blocked(CENTER) and restored.blocked(FAR_POST) and Industry.is_vertical(restored.state.objects[World.key(ROTATED)]),"Reload retains both orientations and collision")
	var invalid:=world.state.duplicate(true)
	invalid.objects.erase(World.key(CENTER))
	expect(not World.SAVE_SCHEMA.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Save refuses orphaned posts")
	var visitor:="forest-arch-guest"
	world.add_player(visitor,"訪客",Vector2(39.5,34.5))
	set_position(person,Vector2(40.5,35.6))
	expect(not world.act(visitor,"cannot-remove","remove",FAR_POST).ok,"A visitor cannot remove a post of someone else's arch")
	expect(world.act(owner,"remove","remove",FAR_POST).ok and not has_arch(SITE) and not has_arch(CENTER) and person.inventory.hardwood==16,"Dismantling any part lifts the whole arch and refunds one recipe")
	var undo:=world.undo_summary(owner)
	expect(undo.available and world.act(owner,"restore",World.UNDO_ACTION,Vector2i.ZERO,undo.id).ok and not world.blocked(CENTER),"Undo remounts both side posts while a visitor stands in the legal opening")
	set_position(world.state.players[visitor],Vector2(37.5,35.5))
	person=world.state.players[owner]
	set_position(person,Vector2(40.5,35.6))
	expect(world.act(owner,"move","move_object",FAR_POST,World.key(MOVED)).ok and not has_arch(FAR_POST) and World.station_anchor(world.state.objects,MOVED+Vector2i(2,0))==MOVED,"Moving by a far post preserves the linked assembly")
	expect(not world.blocked(MOVED+Vector2i.RIGHT),"The moved assembly still has an open center")
	expect(Art.WIDE.get_image().get_pixel(48,55).a==0.0 and Art.TALL.get_image().get_pixel(23,78).a==0.0,"Both art directions have an actual transparent passage")
	await finish()
