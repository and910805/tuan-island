extends SceneTree

const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const KIND:=Industry.INN_BED
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if ok:return
	failures+=1
	push_error(message)

func run() -> void:
	var app=Main.instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640)
	await process_frame
	var path:="user://inn-quilt-bed-%d.json"%OS.get_process_id()
	if app.session.host(0,"旅舍工匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	var at:=Vector2i(41,36)
	var foot:=at+Vector2i.DOWN
	var bed_key:=World.key(at)
	person.x=42.5
	person.y=37.5
	person.inventory.hardwood=12
	person.inventory.cotton_cloth=6
	person.inventory.wool_cloth=3
	person.inventory.blue_dye=1
	app.session._send_snapshot(1)
	app._build_menu()
	await process_frame
	var tab:=app.modal.find_child("BuildTab2",true,false) as Button
	if tab:tab.pressed.emit()
	var slot:=app.modal.find_child("BuildSlot_inn_quilt_bed_2",true,false) as Button
	expect(slot!=null and slot.is_visible_in_tree(),"The bed is listed as furniture")
	app._close_modal()
	app.session.perform("build",at,KIND)
	expect(world.state.objects.get(bed_key,{}).get("inn_bed_vertical")==true and world.state.objects.get(World.key(foot),{}).get("inn_bed_part")==1
		and world.blocked(at) and world.blocked(foot),"Placing a bed uses a vertical two-cell footprint")
	expect(person.inventory.hardwood==0 and person.inventory.cotton_cloth==0 and person.inventory.wool_cloth==0,"The exact textile and hardwood recipe is charged")
	person.mine_energy=56
	var before:=float(world.state.time)
	app.session._send_snapshot(1)
	app._interact()
	expect(person.mine_energy==100 and float(world.state.time)==before,"Interacting at the foot restores energy without advancing the shared day")
	var dye:=Vector2i(38,36)
	world.state.objects[World.key(dye)]={"type":Industry.DYE_TABLE,"owner":token,"items":{},"dye_part":0}
	world.state.objects[World.key(dye+Vector2i.RIGHT)]={"type":Industry.DYE_TABLE,"owner":token,"items":{},"dye_part":1}
	person.x=39.5
	person.y=37.5
	var dyeable:=World.nearby_dye_furniture(world.state.objects,token,dye)
	expect(bed_key in dyeable and World.key(foot) not in dyeable,"The dye table lists the bed as one object")
	app.session._send_snapshot(1)
	app.session.perform("dye_furniture",dye,bed_key+"|blue_dye")
	expect(world.state.objects.get(bed_key,{}).get("dye")=="blue_dye" and person.inventory.blue_dye==0,"The quilt can be dyed through the normal action")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects.get(bed_key,{}).get("dye")=="blue_dye",
		"The dyed bed survives a primary save reload")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("inn-quilt-bed.png"))==OK,"Capture the dyed quilt bed")
	person.x=42.5
	expect(world.act(token,"remove-foot","remove",foot).ok and not world.blocked(foot)
		and person.inventory.hardwood==12 and person.inventory.cotton_cloth==6 and person.inventory.wool_cloth==3,"Removing from the foot dismantles the entire bed once")
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("INN_QUILT_BED_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
