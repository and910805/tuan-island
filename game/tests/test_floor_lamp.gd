extends SceneTree

const World=preload("res://scripts/world.gd")
const LAMP:=Vector2i(42,34)
const NEIGHBOR:=Vector2i(46,34)
const NEW_SITE:=Vector2i(43,35)
const ACTION:="floor_lamp_toggle"
var checks:=0
var failures:=0
var app
var output:String

func _initialize()->void:
	run.call_deferred()

func expect(condition:bool,message:String)->void:
	checks+=1
	if condition:return
	failures+=1
	push_error(message)

func capture(name:String)->Image:
	if DisplayServer.get_name()=="headless":return null
	app.view.queue_redraw()
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		expect(image.save_png(output.path_join(name+".png"))==OK,"Save screenshot "+name)
	return image

func sample(image:Image,cell:Vector2i)->Color:
	var point:Vector2=app.view.screen(Vector2(cell)+Vector2(0.5,0.65))+Vector2(18,8)
	return image.get_pixelv(Vector2i((point*app.view.view_zoom()).round()))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	var path:="user://floor-lamp-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="floor-lamp-owner"
	if app.session.host(0,"木工",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	var world:World=app.session.world
	var owner:String=app.session.peers[1]
	var lamp_key:=World.key(LAMP)
	var neighbor_key:=World.key(NEIGHBOR)
	var person:Dictionary=world.state.players[owner]
	person.inventory.merge({"wood":10,"stone":4},true)
	for cell:Vector2i in [LAMP,NEIGHBOR,NEW_SITE]:world.state.removed[World.key(cell)]=true
	person.x=44.5
	person.y=34.5
	world.state.time=1260.0
	app.session._send_snapshot(1)
	app._perform_build_action("build",LAMP,"lamp")
	app._perform_build_action("build",NEIGHBOR,"lamp")
	expect(world.state.objects.has(lamp_key) and world.state.objects.has(neighbor_key) and person.inventory.wood==0 and person.inventory.stone==0,"Normal build spends two exact recipes")
	expect(not world.blocked(LAMP),"Existing lamp tiles are still walkable")
	person.x=41.5
	app.session._send_snapshot(1)
	app.view.set_process(false)
	app.view.camera=(Vector2(LAMP)+Vector2(2.0,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())
	app._select_tool("hoe")
	var before:=await capture("both-lamps-on")
	app._interact()
	expect(world.state.objects[lamp_key].get("lamp_off",false) and not world.state.objects[neighbor_key].get("lamp_off",false),"Interact turns off only the closest owned lamp")
	var after:=await capture("left-lamp-off")
	var stable:=await capture("left-lamp-off-stable")
	if before!=null and after!=null and stable!=null:
		expect(sample(before,LAMP).r>sample(after,LAMP).r+0.04,"Left lamp loses its rendered glow")
		expect(sample(before,NEIGHBOR).is_equal_approx(sample(after,NEIGHBOR)),"Right lamp retains its glow")
		expect(sample(stable,NEIGHBOR).is_equal_approx(sample(after,NEIGHBOR)),"Right lamp renders steady light across frames")
	world.add_player("visitor","來客",LAMP+Vector2i.DOWN)
	expect(not world.act("visitor","visitor-toggle",ACTION,LAMP).ok,"Visitor cannot alter the owner's lamp")
	expect(not world.act(owner,"far-toggle",ACTION,NEIGHBOR).ok,"Distant switch is rejected")
	var saved:=World.new()
	expect(saved.load_world(path) and saved.state.objects.get(lamp_key,{}).get("lamp_off",false),"Explicit off state survives disk reload")
	var moving:=world.act(owner,"move","move_object",LAMP,World.key(NEW_SITE))
	expect(moving.ok and world.state.objects.get(World.key(NEW_SITE),{}).get("lamp_off",false),"Moving the lamp keeps its switch state")
	var turned_on:=world.act(owner,"on",ACTION,NEW_SITE)
	expect(turned_on.ok and not world.state.objects.get(World.key(NEW_SITE),{}).get("lamp_off",false),"Owner can turn the same lamp back on")
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.2).timeout
	for file in [path,path+".bak",path+".writer-lock"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("FLOOR_LAMP_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
