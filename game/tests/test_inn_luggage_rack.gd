extends SceneTree

const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const KIND:=World.INDUSTRY.LUGGAGE_RACK
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
	var path:="user://inn-luggage-%d.json"%OS.get_process_id()
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
	person.x=42.5
	person.y=37.5
	person.inventory.hardwood=12
	person.inventory.fiber=4
	person.inventory.carp=2
	person.inventory.tea_jar=1
	app.session._send_snapshot(1)
	app.session.perform("build",at,KIND)
	expect(person.inventory.hardwood==0 and person.inventory.fiber==0 and world.blocked(at) and world.blocked(end),
		"The two-cell rack takes the planned recipe")
	app._interact()
	var picker_button:=app.modal.find_child("LuggageOpenPicker",true,false) as Button
	expect(picker_button!=null and app.modal.find_child("LuggageItemPicker",true,false)==null,"Opening the display does not list backpack contents")
	if picker_button:picker_button.pressed.emit()
	var picker:=app.modal.find_child("LuggageItemPicker",true,false) as OptionButton
	var slot:=-1
	if picker:
		for index in picker.item_count:
			if picker.get_item_metadata(index)=="carp":slot=index
	expect(slot>=0,"The explicit picker offers a held item")
	var put:=app.modal.find_child("LuggagePlace",true,false) as Button
	if slot>=0 and put:
		picker.select(slot)
		put.pressed.emit()
	expect(person.inventory.carp==1 and world.state.objects[key].items.get("carp")==1,"The UI transfers exactly one selected item")
	expect(world.act(token,"second","inn_luggage_place",end,"tea_jar").ok and person.inventory.tea_jar==0,"The far end accesses the second display position")
	expect(not world.act(token,"overflow","inn_luggage_place",end,"carp").ok and person.inventory.carp==1,"A full rack refuses another item without consuming it")
	world.add_player("guest","訪客")
	var guest:Dictionary=world.state.players.guest
	guest.x=person.x
	guest.y=person.y
	expect(not world.act("guest","take","inn_luggage_take",end,"tea_jar").ok,"A visitor cannot claim displayed items")
	expect(not world.act(token,"full-remove","remove",end).ok,"A loaded rack must be emptied before dismantling")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects.get(key,{}).get("items")=={"carp":1,"tea_jar":1},
		"The primary save retains both display items")
	app.session._send_snapshot(1)
	app._refresh_hud()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("inn-luggage-rack.png"))==OK,"Capture both display items")
	for item in ["tea_jar","carp"]:
		expect(world.act(token,"take-"+item,"inn_luggage_take",end,item).ok,"The owner can retrieve "+item)
	expect(person.inventory.carp==2 and person.inventory.tea_jar==1 and world.state.objects[key].items.is_empty(),"The two original objects are conserved")
	expect(world.act(token,"remove","remove",end).ok and person.inventory.hardwood==12 and person.inventory.fiber==4,"Dismantling refunds one recipe")
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("INN_LUGGAGE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
