extends SceneTree

const World=preload("res://scripts/world.gd")
const LAMP:=World.INDUSTRY.SPORE_LAMP
const SITE:=Vector2i(42,34)
const MAT_COST:={"wood":4,"glass":1,"star_mushroom":2}
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

func frame(capture_name:="")->Image:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	if not output.is_empty() and not capture_name.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		expect(image.save_png(output.path_join(capture_name+".png"))==OK,"Screenshot "+capture_name)
	return image

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.22).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SPORE_LAMP_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func inventory_has(amounts:Dictionary)->bool:
	var inventory:Dictionary=world.state.players[owner].inventory
	for item:String in amounts:
		if inventory.get(item,0)!=amounts[item]:return false
	return true

func has_lamp(at:Vector2i)->bool:
	return world.state.objects.get(World.key(at),{}).get("type")==LAMP

func glow_point()->Vector2i:
	var local:Vector2=app.view.screen(Vector2(SITE)+Vector2(0.97,0.65))
	return Vector2i((local*app.view.view_zoom()).round())

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://spore-lamp-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="spore-lamp-owner"
	if app.session.host(0,"森林木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=41.5
	person.y=33.5
	person.inventory.merge(MAT_COST,true)
	world.state.time=720.0
	var key:=World.key(SITE)
	world.state.removed[key]=true
	app.session._send_snapshot(1)
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="蘑菇森林":
			entry.pressed.emit()
			press("BuildSlot_"+LAMP+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	press("BuildPlace")
	expect(app.building==LAMP and app.view.build_placement_offsets(LAMP)==[Vector2i.ZERO],"The forest catalogue selects a one-cell lamp")
	app._perform_build_action("build",SITE,LAMP)
	if not expect(has_lamp(SITE),"Placed through the normal build flow"):
		await finish()
		return
	expect(inventory_has({"wood":0,"glass":0,"star_mushroom":0}),"One placement consumes the exact recipe")
	expect(not world.blocked(SITE),"The small nightlight is passable")
	var saved:=World.new()
	expect(saved.load_world(path) and saved.state.objects.get(key,{}).get("type")==LAMP,"The lamp survives save and reload")
	var plan:=World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i.ONE),"蘑菇夜燈",World.BUILD,World.NAMES)
	expect(plan.ok and plan.blueprint.pieces==[{"kind":LAMP,"x":0,"y":0}],"Blueprint captures a single lamp")
	var guest:="spore-lamp-guest"
	world.add_player(guest,"訪客",Vector2(42.5,33.5))
	expect(not world.act(guest,"cannot-remove","remove",SITE).ok,"A visitor cannot dismantle someone else's lamp")
	app._select_tool("hoe")
	var graphical:=DisplayServer.get_name()!="headless"
	var day:Image
	if graphical:day=await frame("spore-lamp-day")
	world.state.time=1260.0
	app.session._send_snapshot(1)
	var lit:Color
	var sample:Vector2i
	var day_lit:Color
	if graphical:
		var night:=await frame("spore-lamp-night")
		sample=glow_point()
		lit=night.get_pixelv(sample)
		day_lit=day.get_pixelv(sample)
		var next:=await frame()
		var steady:=next.get_pixelv(sample)
		expect(absf(lit.g-steady.g)<0.015 and absf(lit.b-steady.b)<0.015,"The ground light remains steady across rendered frames")
	expect(world.act(owner,"remove-lamp","remove",SITE).ok and inventory_has(MAT_COST) and not has_lamp(SITE),"Owner dismantles the lamp and receives exactly one refund")
	app.session._send_snapshot(1)
	if graphical:
		var bare:=await frame()
		var dark:=bare.get_pixelv(sample)
		expect(lit.g-dark.g>0.10 and lit.b-dark.b>0.12,"The lamp adds a measurable teal halo over the night ground")
		world.state.time=720.0
		app.session._send_snapshot(1)
		var daylight:=await frame()
		var bare_day:=daylight.get_pixelv(sample)
		expect(absf(day_lit.g-bare_day.g)<0.025 and absf(day_lit.b-bare_day.b)<0.025,"The same spot has no visible pool in daylight")
	await finish()
