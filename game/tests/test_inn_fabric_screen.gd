extends SceneTree

const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const KIND:=Industry.FABRIC_SCREEN
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if ok:return
	failures+=1
	push_error(message)

func capture(file:String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file))==OK,"Capture "+file)

func run() -> void:
	var app=Main.instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640)
	await process_frame
	var path:="user://inn-screen-%d.json"%OS.get_process_id()
	if app.session.host(0,"旅舍工匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	var at:=Vector2i(41,36)
	var end:=at+Vector2i.RIGHT
	var key:=World.key(at)
	person.x=41.5
	person.y=37.5
	person.inventory.hardwood=10
	person.inventory.cotton_cloth=5
	world.state.objects[World.key(end)]={"type":"bench","owner":token,"items":{}}
	app.session._send_snapshot(1)
	app._build_menu()
	await process_frame
	var tab:=app.modal.find_child("BuildTab2",true,false) as Button
	if tab:tab.pressed.emit()
	var slot:=app.modal.find_child("BuildSlot_inn_fabric_screen_2",true,false) as Button
	expect(slot!=null and slot.is_visible_in_tree(),"The screen is in the furniture page")
	app._close_modal()
	app.set_process(false)
	app.view.selected="build"
	app.view.building=KIND
	app.view.target=at
	app.view.show_target=true
	app.view.queue_redraw()
	await capture("screen-blocked-preview.png")
	expect(not world.act(token,"blocked","build",at,KIND).ok and person.inventory.hardwood==10 and person.inventory.cotton_cloth==5,
		"An occupied second tile prevents all placement and material debit")
	world.state.objects.erase(World.key(end))
	app.session.perform("build",at,KIND)
	expect(world.state.objects.get(key,{}).get("type")==KIND and world.state.objects.get(World.key(end),{}).get("screen_part")==1
		and world.blocked(at) and world.blocked(end) and person.inventory.hardwood==0 and person.inventory.cotton_cloth==0,
		"The exact recipe places one two-cell solid divider")
	app.view.show_target=false
	app.view.queue_redraw()
	await capture("fabric-screen.png")
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,token,Rect2i(at,Vector2i(2,1)),"旅舍屏風",World.BUILD,World.NAMES)
	expect(design.ok and design.get("blueprint",{}).get("pieces",[]).size()==1,"Capturing the whole screen produces one blueprint piece")
	expect(world.act(token,"remove","remove",end).ok and person.inventory.hardwood==10 and person.inventory.cotton_cloth==5,
		"Removing from the second cell refunds a single recipe")
	if design.ok:
		var turn_origin:=at+Vector2i.RIGHT
		var quote:=world.quote_blueprint(token,design.blueprint,turn_origin,1)
		var built:=world.apply_blueprint(token,"a".repeat(32),design.blueprint,turn_origin,1,quote.hash)
		var root_piece:Dictionary=world.state.objects.get(World.key(turn_origin),{})
		var far_piece:Dictionary=world.state.objects.get(World.key(turn_origin+Vector2i.DOWN),{})
		expect(built.ok and root_piece.get("screen_vertical",false) and far_piece.get("screen_part")==1,"A rotated blueprint places a vertical screen: "+str(built.message))
		var loaded:=World.new()
		expect(loaded.load_world(path) and not loaded.recovered_from_backup
			and loaded.state.objects.get(World.key(turn_origin+Vector2i.DOWN),{}).get("screen_part")==1,"The vertical screen persists in the primary save")
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("INN_FABRIC_SCREEN_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
