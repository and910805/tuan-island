extends SceneTree

const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const Bed=World.INDUSTRY
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
	print("HOLLOW_BED_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://hollow-bed-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="hollow-bed-owner"
	if app.session.host(0,"森林木匠",path,"","127.0.0.1",false,"enet",true)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=41.5
	person.y=33.5
	person.mine_energy=27
	person.inventory.merge({"hardwood":42,"cotton_cloth":10,"fiber":18},true)
	world.state.time=720.0
	for origin in [SITE,MOVED]:
		for offset:Vector2i in Bed.SQUARE_CELLS:world.state.removed[World.key(origin+offset)]=true
	app.session._send_snapshot(1)
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="蘑菇森林":
			entry.pressed.emit()
			press("BuildSlot_"+Bed.HOLLOW_BED+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	press("BuildPlace")
	expect(app.building==Bed.HOLLOW_BED and app.view.build_placement_offsets(Bed.HOLLOW_BED)==Bed.SQUARE_CELLS,"Normal build previews the four tiles")
	app._perform_build_action("build",SITE,Bed.HOLLOW_BED)
	var key:=World.key(SITE)
	if not expect(world.state.objects.get(key,{}).get("type")==Bed.HOLLOW_BED,"The bed is placed"):
		finish()
		return
	expect(person.inventory.hardwood==24 and person.inventory.cotton_cloth==5 and person.inventory.fiber==10,"The bed charges the plan's recipe")
	for offset:Vector2i in Bed.SQUARE_CELLS:
		expect(world.blocked(SITE+offset) and World.station_anchor(world.state.objects,SITE+offset)==SITE,"One solid bed across all four cells")
	app._select_tool("hoe")
	await capture("bed-available")
	app._interact()
	expect(is_instance_valid(app.modal) and app.modal.has_meta("life_modal_layout"),"Interact from the second column opens the bed menu")
	if not press("HollowBedRest"):
		finish()
		return
	expect(person.get(SEAT,{})=={"cell":key,"side":0} and person.mine_energy==100,"Lying down restores energy and reserves the bed")
	expect(app.view.occupied_hollow_beds.get(key)==app.session.own_id,"World renderer uses the sleeper at the bed")
	await capture("bed-sleeping")
	var guest:="hollow-guest"
	world.add_player(guest,"訪客",Vector2(42.5,33.5))
	var other:Dictionary=world.state.players[guest]
	expect(not world.act(guest,"busy","hollow_bed_rest",SITE+Vector2i.RIGHT).ok,"No second sleeper while occupied")
	expect(world.act(owner,"busy-remove","remove",SITE+Vector2i.DOWN).message==Bed.HOLLOW_BUSY,"No dismantling via a child tile while occupied")
	expect(world.act(owner,"busy-move","move_object",SITE+Vector2i.ONE,World.key(MOVED)).message==Bed.HOLLOW_BUSY,"No moving via a child tile while occupied")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.players[owner][SEAT].cell==key,"Resting pose and bed anchor survive reload")
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,2)),"樹洞",World.BUILD,World.NAMES)
	expect(cut.ok and cut.blueprint.pieces.size()==1 and cut.blueprint.pieces[0].kind==Bed.HOLLOW_BED,"Blueprint treats the whole bed as one piece")
	app._interact()
	expect(not person.has(SEAT),"Interact gets the player up")
	expect(world.act(guest,"guest-rest",Bed.HOLLOW_REST,SITE+Vector2i.RIGHT).ok,"Guest can use the free bed")
	world.move_player(guest,Vector2.UP,0.1)
	expect(not other.has(SEAT),"Moving gets a guest up")
	var result:=world.act(owner,"move","move_object",SITE+Vector2i.ONE,World.key(MOVED))
	expect(result.ok,"Free bed moves with its full footprint: "+str(result.get("message","")))
	for offset:Vector2i in Bed.SQUARE_CELLS:
		expect(not world.state.objects.has(World.key(SITE+offset)) and World.station_anchor(world.state.objects,MOVED+offset)==MOVED,"Bed parts move together")
	person.x=44.5
	person.y=33.5
	world.state.time=World.REST_DAWN-0.2
	app.session._send_snapshot(1)
	app._interact()
	if press("HollowBedNight"):press("NightRestConfirm")
	expect(is_equal_approx(float(world.state.time),World.REST_DAWN),"Overnight uses the existing solo sleep and dawn simulation")
	expect(world.act(owner,"remove","remove",MOVED+Vector2i.RIGHT).ok and person.inventory.hardwood==42 and person.inventory.cotton_cloth==10 and person.inventory.fiber==18,"Removal refunds exactly one recipe")
	finish()
