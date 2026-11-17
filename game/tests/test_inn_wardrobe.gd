extends SceneTree

const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const KIND:=World.RESIDENT_GOALS.INN_WARDROBE
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
	var path:="user://inn-wardrobe-%d.json"%OS.get_process_id()
	if app.session.host(0,"暖泉島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	var at:=Vector2i(41,36)
	person.x=41.5
	person.y=37.5
	person.inventory.hardwood=14
	person.inventory.cotton_cloth=2
	app.session._send_snapshot(1)
	app.session.perform("build",at,KIND)
	expect(world.state.objects.get(World.key(at),{}).get("type")==KIND and world.blocked(at)
		and person.inventory.hardwood==0 and person.inventory.cotton_cloth==0,"The planned recipe places a solid one-cell cabinet")
	expect(not world.act(token,"locked","inn_outfit",at,"blue").ok,"The cabinet cannot unlock the undyed outfit")
	person.blue_outfit=true # Older save with the already dyed work clothes equipped.
	app.session._send_snapshot(1)
	app._interact()
	var outfit:=app.modal.find_child("InnWardrobeOutfit",true,false) as Button
	expect(outfit!=null and outfit.text=="換回原色工作服","The real cabinet interaction recognizes the previous blue outfit")
	if outfit:outfit.pressed.emit()
	expect(not person.has("blue_outfit") and person.blue_outfit_unlocked,"Changing back preserves the unlock")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.players[token].blue_outfit_unlocked,
		"The primary save retains the outfit unlock while the original outfit is worn")
	app._interact()
	outfit=app.modal.find_child("InnWardrobeOutfit",true,false) as Button
	expect(outfit!=null and outfit.text=="換上藍染工作服","The unlocked blue outfit is selectable")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("inn-wardrobe.png"))==OK,"Capture the cabinet UI")
	if outfit:outfit.pressed.emit()
	expect(person.blue_outfit and int(person.inventory.get("blue_dye",0))==0,"Changing to the unlocked color consumes no dye")
	world.add_player("friend","訪客")
	var guest:Dictionary=world.state.players.friend
	guest.x=person.x
	guest.y=person.y
	expect(not world.act("friend","locked-guest","inn_outfit",at,"blue").ok and person.blue_outfit,"The owner's unlock does not transfer to a guest")
	guest.blue_outfit_unlocked=true
	expect(world.act("friend","guest-change","inn_outfit",at,"blue").ok and guest.blue_outfit and person.blue_outfit,
		"An eligible guest can change their own work clothes")
	expect(world.act(token,"remove","remove",at).ok and person.inventory.hardwood==14 and person.inventory.cotton_cloth==2,
		"Removing the cabinet refunds both materials")
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("INN_WARDROBE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
