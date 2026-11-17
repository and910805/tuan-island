extends SceneTree

const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const KIND:="spring_pebble_path"
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
	var save_path:="user://pebble-road-%d.json"%OS.get_process_id()
	if app.session.host(0,"暖泉路工",save_path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	var first:=Vector2i(41,36)
	var second:=first+Vector2i.RIGHT
	var placement:="%s|%d|%d"%[KIND,second.x,second.y]
	person.x=41.5
	person.y=37.5
	person.inventory.stone=4
	person.inventory.clay=1
	app.session._send_snapshot(1)
	app._build_menu()
	await process_frame
	var tab:=app.modal.find_child("BuildTab1",true,false) as Button
	if tab:tab.pressed.emit()
	var slot:=app.modal.find_child("BuildSlot_spring_pebble_path_1",true,false) as Button
	expect(slot!=null and slot.is_visible_in_tree(),"The road is available from the foundations page")
	if slot:slot.pressed.emit()
	await process_frame
	var title:=app.modal.find_child("BuildTitle",true,false) as Label
	expect(title!=null and title.text.contains("泉邊卵石路"),"The construction preview selects the planned road")
	app._close_modal()
	var rejected:=world.act(token,"shortfall","build_area",first,placement)
	expect(not rejected.ok and person.inventory.stone==4 and person.inventory.clay==1 and not world.state.ground.has(World.key(first)),"Clay shortfall leaves the whole batch and materials untouched")
	person.inventory.clay=2
	app.session.perform("build_area",first,placement)
	expect(person.inventory.stone==0 and person.inventory.clay==0,"A two-tile batch charges four stone and two clay")
	for tile in [first,second]:
		var road:Dictionary=world.state.ground.get(World.key(tile),{})
		expect(road.get("type")==KIND and not world.blocked(tile),"Each road tile is walkable ground")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("spring-pebble-path.png"))==OK,"Capture the new road in game")
	var loaded:=World.new()
	expect(loaded.load_world(save_path) and loaded.state.ground.get(World.key(first),{}).get("type")==KIND,"The road survives a save reload")
	var undo:Dictionary=world.undo_summary(token)
	expect(undo.has("id") and world.act(token,"rollback","undo_build",first,undo.get("id","")).ok,"Construction undo accepts the new ground kind")
	expect(person.inventory.stone==4 and person.inventory.clay==2 and not world.state.ground.has(World.key(second)),"Undo refunds the exact batch recipe")
	expect(world.act(token,"place-once","build",first,KIND).ok and world.act(token,"remove-once","remove",first).ok
		and person.inventory.stone==4 and person.inventory.clay==2,"Single placement and removal refund both materials")
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(save_path+suffix):DirAccess.remove_absolute(save_path+suffix)
	print("SPRING_PEBBLE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
