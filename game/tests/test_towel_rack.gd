extends SceneTree

const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const KIND:="towel_rack"
var checks:=0
var failures:=0

func _initialize() -> void:
	run.call_deferred()

func expect(condition:bool,message:String) -> void:
	checks+=1
	if condition:return
	failures+=1
	push_error(message)

func run() -> void:
	var app=Main.instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640)
	await process_frame
	var path:="user://towel-rack-%d.json"%OS.get_process_id()
	if app.session.host(0,"旅舍工匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	var at:=Vector2i(41,36)
	var next:=at+Vector2i.RIGHT
	var key:=World.key(at)
	person.x=41.5
	person.y=37.5
	person.inventory.wood=10
	person.inventory.cotton_cloth=5
	expect(not world.act(token,"short","build",at,KIND).ok and person.inventory.wood==10
		and person.inventory.cotton_cloth==5 and not world.state.objects.has(key),"Missing cloth does not consume wood or place the object")
	person.inventory.cotton_cloth=6
	app.session._send_snapshot(1)
	app._build_menu()
	await process_frame
	var tab:=app.modal.find_child("BuildTab2",true,false) as Button
	if tab:tab.pressed.emit()
	var slot:=app.modal.find_child("BuildSlot_towel_rack_2",true,false) as Button
	expect(slot!=null and slot.is_visible_in_tree(),"Find the rack on the furniture page")
	if slot:slot.pressed.emit()
	var title:=app.modal.find_child("BuildTitle",true,false) as Label
	expect(title!=null and title.text.contains("浴巾收納架"),"The selected rack appears in the live preview")
	app._close_modal()
	app.session.perform("build",at,KIND)
	var rack:Dictionary=world.state.objects.get(key,{})
	expect(rack.get("type")==KIND and rack.items.is_empty() and person.inventory.wood==0 and person.inventory.cotton_cloth==0,
		"The exact recipe places a decorative rack without towel inventory")
	expect(world.blocked(at) and not world.blocked(next),"The rack occupies exactly one blocked tile")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("towel-rack.png"))==OK,"Capture the placed rack")
	expect(world.act(token,"move","move_object",at,World.key(next)).ok and not world.blocked(at) and world.blocked(next),"Moving updates collision")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup
		and loaded.state.objects.get(World.key(next),{}).get("type")==KIND,"The primary save preserves the moved rack")
	expect(world.act(token,"remove","remove",next).ok and person.inventory.wood==10 and person.inventory.cotton_cloth==6
		and not world.blocked(next),"Removal refunds the recipe and frees the tile")
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("TOWEL_RACK_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
