extends SceneTree

const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const Stool=World.INDUSTRY
const SEAT=World.RESIDENT_GOALS.MASTER_BENCH_SEAT
const SITE:=Vector2i(40,34)
const MOVED:=Vector2i(43,34)
var app
var world:World
var owner:String
var output:String
var path:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
	return ok

func press(name:String)->bool:
	var button:=app.modal.find_child(name,true,false) as Button if is_instance_valid(app.modal) else null
	if not expect(button!=null and not button.disabled,"Button is available: "+name):return false
	button.pressed.emit()
	return true

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.25).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("MUSHROOM_STOOL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://mushroom-stool-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="mushroom-stool-owner"
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
	person.inventory.merge({"wood":18,"star_mushroom":4},true)
	world.state.time=720.0
	for tile in [SITE,MOVED]:world.state.removed[World.key(tile)]=true
	app.session._send_snapshot(1)
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="蘑菇森林":
			entry.pressed.emit()
			press("BuildSlot_"+Stool.MUSHROOM_STOOL+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	press("BuildPlace")
	expect(app.building==Stool.MUSHROOM_STOOL and app.view.build_placement_offsets(Stool.MUSHROOM_STOOL)==[Vector2i.ZERO],"Build mode previews a single stool tile")
	app._perform_build_action("build",SITE,Stool.MUSHROOM_STOOL)
	var key:=World.key(SITE)
	if not expect(world.state.objects.get(key,{}).get("type")==Stool.MUSHROOM_STOOL,"The stool is placed"):
		finish()
		return
	expect(person.inventory.wood==12 and person.inventory.star_mushroom==3,"The stool consumes exactly six wood and one mushroom")
	expect(world.blocked(SITE) and not world.blocked(SITE+Vector2i.DOWN),"The independent seat occupies just its own tile")
	app._select_tool("hoe")
	await capture("stool-empty")
	app._interact()
	expect(person.get(SEAT,{})=={"cell":key,"side":0},"Interact sits down without opening a dialog")
	await capture("stool-seated")
	var guest:="mushroom-stool-guest"
	world.add_player(guest,"訪客",Vector2(41.5,33.5))
	var other:Dictionary=world.state.players[guest]
	expect(not world.act(guest,"busy",World.RESIDENT_GOALS.MASTER_BENCH_SIT,SITE).ok,"Only one person fits on the stool")
	expect(world.act(owner,"busy-move","move_object",SITE,World.key(MOVED)).message==Stool.MUSHROOM_STOOL_BUSY,"Cannot move an occupied stool")
	expect(world.act(owner,"busy-remove","remove",SITE).message==Stool.MUSHROOM_STOOL_BUSY,"Cannot dismantle an occupied stool")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.players[owner][SEAT].cell==key,"The stool and sitting pose survive a saved-world reload")
	var invalid:Dictionary=world.state.duplicate(true)
	invalid.players[guest][SEAT]={"cell":key,"side":0}
	expect(not World.SAVE_SCHEMA.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Save validation rejects duplicate stool occupants")
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i.ONE),"菇凳",World.BUILD,World.NAMES)
	expect(cut.ok and cut.blueprint.pieces[0].kind==Stool.MUSHROOM_STOOL,"Blueprint captures a standalone furniture item")
	app._interact()
	expect(not person.has(SEAT),"Interact again stands up")
	expect(world.act(guest,"guest-sit",World.RESIDENT_GOALS.MASTER_BENCH_SIT,SITE).ok,"Visitors are allowed to sit")
	world.move_player(guest,Vector2.UP,0.1)
	expect(not other.has(SEAT),"Movement gets a visitor up")
	var move:=world.act(owner,"move","move_object",SITE,World.key(MOVED))
	expect(move.ok and not world.state.objects.has(key) and world.state.objects.get(World.key(MOVED),{}).get("type")==Stool.MUSHROOM_STOOL,"Free stool may be moved")
	expect(world.act(owner,"remove","remove",MOVED).ok and person.inventory.wood==18 and person.inventory.star_mushroom==4,"Dismantling refunds the original recipe")
	finish()
