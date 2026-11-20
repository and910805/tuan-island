extends SceneTree

const World=preload("res://scripts/world.gd")
const Art=preload("res://scripts/quiet_birdhouse_art.gd")
const KIND:=World.INDUSTRY.QUIET_BIRDHOUSE
const SITE:=Vector2i(42,34)
var app
var world:World
var owner:String
var path:String
var preferences:String
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

func widget(name:String)->Node:
	return app.modal.find_child(name,true,false) if is_instance_valid(app.modal) else null

func press(name:String)->bool:
	var control:=widget(name) as Button
	if not expect(control!=null and not control.disabled,"Available button "+name):return false
	control.pressed.emit()
	return true

func frame(name:String,elapsed:float)->Image:
	if DisplayServer.get_name()=="headless":return null
	app.view.elapsed=elapsed
	app.view.queue_redraw()
	await create_timer(0.28).timeout
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	if not output.is_empty() and not name.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		expect(image.save_png(output.path_join(name+".png"))==OK,"Screenshot "+name)
	return image

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.2).timeout
	for file in [path,path+".bak",path+".writer-lock",preferences,preferences+".bak",preferences+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("QUIET_BIRDHOUSE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func view_sample(offset:Vector2)->Vector2i:
	var scene:Vector2=app.view.screen(Vector2(SITE))+offset
	return Vector2i((scene*app.view.view_zoom()).round())

func identical(a:Image,b:Image,location:Vector2i)->bool:
	return a.get_pixelv(location).is_equal_approx(b.get_pixelv(location))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://quiet-birdhouse-%d.json"%Time.get_ticks_usec()
	preferences=path+".cfg"
	app.settings_path=preferences
	app.session.profile.token="quiet-birdhouse-owner"
	if app.session.host(0,"森林木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=41.5
	person.y=34.5
	person.inventory.merge({"wood":8,"fiber":4},true)
	world.state.time=720.0
	var key:=World.key(SITE)
	world.state.removed[key]=true
	app.session._send_snapshot(1)
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="蘑菇森林":
			entry.pressed.emit()
			press("BuildSlot_"+KIND+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	press("BuildPlace")
	app._perform_build_action("build",SITE,KIND)
	if not expect(world.state.objects.get(key,{}).get("type")==KIND,"Normal catalogue places one birdhouse"):
		await finish()
		return
	expect(person.inventory.wood==0 and person.inventory.fiber==0 and world.blocked(SITE),"The stand occupies just the one paid tile")
	expect(not world.state.objects[key].has("bird") and world.state.objects[key].items.is_empty(),"The decorative bird needs no gameplay inventory or animal record")
	var phase_offset:=float(posmod(SITE.x*17+SITE.y*31,80))*0.1
	var rest_time:=9.0-phase_offset
	var flight_time:=rest_time+5.9
	var still:=Art.pose(SITE,720.0,rest_time,true)
	var flying:=Art.pose(SITE,720.0,flight_time,false)
	expect(flying.frame=="fly" and flying.offset!=still.offset,"Daytime loop includes real flight motion")
	expect(Art.pose(SITE,720.0,flight_time,true)==still,"Reduced motion pins the bird to the perch")
	expect(Art.pose(SITE,359.0,rest_time,false).is_empty() and not Art.pose(SITE,360.0,rest_time,false).is_empty() and Art.pose(SITE,1080.0,rest_time,true).is_empty(),"Daytime window opens at 06:00 and closes at 18:00")
	app._select_tool("hoe")
	app.view.reduced_motion=false
	app.view.set_process(false)
	app.view.camera=(Vector2(SITE)+Vector2(0.5,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())
	var day:=await frame("birdhouse-day",rest_time)
	var flight:=await frame("birdhouse-flight",flight_time)
	if day!=null and flight!=null:
		expect(not identical(day,flight,view_sample(Art.PERCH_AT+Vector2(9,4))),"Rendering moves the ambient sprite away from its perch")
	app.LifeShell.settings(app)
	var motion:=widget("ReduceDecorativeMotion") as CheckBox
	if expect(motion!=null,"Comfort settings expose the existing reduced-motion toggle"):
		motion.set_pressed_no_signal(true)
		press("SaveComfort")
		expect(app.view.reduced_motion and FileAccess.file_exists(preferences),"Actual settings save enables quiet mode in the world and persists locally")
	app._close_modal()
	var quiet_a:=await frame("birdhouse-quiet",rest_time)
	var quiet_b:=await frame("",flight_time)
	if quiet_a!=null and quiet_b!=null:
		expect(identical(quiet_a,quiet_b,view_sample(Art.PERCH_AT+Vector2(9,4))),"The real quiet-mode render keeps the same bird on its perch")
	world.state.time=1260.0
	app.session._send_snapshot(1)
	await frame("birdhouse-evening",flight_time)
	var saved:=World.new()
	expect(saved.load_world(path) and saved.state.objects.get(key,{}).get("type")==KIND,"Reload keeps the house itself")
	var design:=World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i.ONE),"小鳥屋",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"The blueprint records only the furniture")
	expect(world.act(owner,"remove","remove",SITE).ok and person.inventory.wood==8 and person.inventory.fiber==4,"Removing the house refunds the original recipe")
	await finish()
