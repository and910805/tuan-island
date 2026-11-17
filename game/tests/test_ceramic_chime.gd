extends SceneTree

const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const KIND:=World.RESIDENT_GOALS.CERAMIC_CHIME
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
	var path:="user://ceramic-chime-%d.json"%OS.get_process_id()
	if app.session.host(0,"暖泉陶作",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	var at:=Vector2i(41,36)
	var wall:=at+Vector2i.UP
	var key:=World.key(at)
	person.x=41.5
	person.y=37.5
	person.inventory.clay=4
	person.inventory.fiber=2
	expect(not world.act(token,"orphan","build",at,KIND).ok and person.inventory.clay==4,"No wall leaves the build and materials untouched")
	expect(world.act(token,"wall","build",wall,"wall").ok,"Build the attachment wall through normal rules")
	app.session._send_snapshot(1)
	app._build_menu()
	await process_frame
	var tab:=app.modal.find_child("BuildTab2",true,false) as Button
	if tab:tab.pressed.emit()
	var slot:=app.modal.find_child("BuildSlot_ceramic_eave_chime_2",true,false) as Button
	expect(slot!=null and slot.is_visible_in_tree(),"The chime is listed as furniture")
	if slot:slot.pressed.emit()
	var title:=app.modal.find_child("BuildTitle",true,false) as Label
	expect(title!=null and title.text.contains("簷下陶風鈴"),"The selected furniture has a preview")
	app._close_modal()
	app.session.perform("build",at,KIND)
	expect(world.state.objects.get(key,{}).get("type")==KIND and person.inventory.clay==0 and person.inventory.fiber==0
		and not world.blocked(at),"The wall-mounted chime uses the exact recipe and keeps access clear")
	expect(not world.act(token,"remove-wall","remove",wall).ok,"The support cannot be removed while the chime is attached")
	expect(not world.act(token,"move-orphan","move_object",at,"42,36").ok,"Moving the chime also requires a wall")
	app.sound.master_volume=1.0
	app.sound.ambience_volume=0.25
	app.sound.volume=0.0
	app.sound.refresh_gains()
	await create_timer(0.28).timeout
	app._interact()
	await create_timer(0.26).timeout
	expect(world.state.objects[key].has("bell_at") and app.sound.player.stream==app.sound.sounds.ceramic_chime
		and app.sound.cue_kind=="ceramic_chime" and is_equal_approx(app.sound.player.volume_db,linear_to_db(0.25)),
		"World interaction plays the ceramic chime through environment gain")
	expect(not world.act(token,"spam",World.RESIDENT_GOALS.FESTIVAL_BELL_RING,at).ok,"Repeat strikes are briefly throttled")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("ceramic-chime.png"))==OK,"Capture the chime on the wall")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.objects.get(key,{}).get("type")==KIND,"The placed chime survives reloading")
	app.sound.ambience_volume=0.0
	app.sound.refresh_gains()
	world.step(1.6,true)
	app.session.perform(World.RESIDENT_GOALS.FESTIVAL_BELL_RING,at)
	expect(world.state.objects[key].bell_at==world.state.time and not app.sound.player.playing and "陶風鈴" in app.toast.text,
		"Muting environment audio keeps the successful ring and its text feedback")
	expect(world.act(token,"remove-chime","remove",at).ok and person.inventory.clay==4 and person.inventory.fiber==2,
		"Removing the chime returns both materials")
	var lamp_kind:=World.WALL_FIXTURES.LIGHT
	var second:=at+Vector2i.RIGHT
	var second_wall:=second+Vector2i.UP
	person.inventory.stone=6
	person.inventory.glass=2
	expect(not world.act(token,"unsupported-lamp","build",second,lamp_kind).ok and person.inventory.glass==2,"Unsupported light keeps its recipe materials")
	app.session._send_snapshot(1)
	app._build_menu()
	await process_frame
	tab=app.modal.find_child("BuildTab2",true,false) as Button
	if tab:tab.pressed.emit()
	slot=app.modal.find_child("BuildSlot_warm_lamp_niche_2",true,false) as Button
	expect(slot!=null and slot.is_visible_in_tree(),"The niche is available in the furniture catalog")
	if slot:slot.pressed.emit()
	title=app.modal.find_child("BuildTitle",true,false) as Label
	expect(title!=null and "暖燈壁龕" in title.text,"The niche has a selectable preview")
	app._close_modal()
	app.session.perform("build",at,lamp_kind)
	expect(world.state.objects[key].type==lamp_kind and not world.blocked(at) and person.inventory.stone==0
		and person.inventory.glass==0,"The lamp uses the planned recipe and does not block passage")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("warm-lamp-niche.png"))==OK,"Capture the lit wall niche")
	expect(not world.act(token,"blocked-wall-lamp","remove",wall).ok,"The original wall stays until the niche is removed or moved")
	expect(world.act(token,"extra-wall","build",second_wall,"wall").ok,"Build a second wall mount")
	expect(world.act(token,"move-lamp","move_object",at,World.key(second)).ok,"Move the niche to a different supported tile")
	expect(loaded.load_world(path) and not loaded.recovered_from_backup
		and loaded.state.objects.get(World.key(second),{}).get("type")==lamp_kind,"The moved niche survives reload from the primary save")
	var undo:=world.undo_summary(token)
	expect(world.act(token,"undo-lamp-move","undo_build",second,undo.get("id","")).ok and world.state.objects[key].type==lamp_kind,
		"Undo of the move restores the original mount")
	expect(world.act(token,"remove-lamp","remove",at).ok and person.inventory.stone==6 and person.inventory.glass==2,"Removing the lamp refunds the full recipe")
	expect(world.act(token,"remove-wall-clear","remove",wall).ok,"The support can be removed once the fixture is gone")
	var shell_item:=World.WANGAN_COAST.SHELL_ITEM
	var shell_kind:=World.RESIDENT_GOALS.SHELL_CHIME
	person.inventory[shell_item]=2
	person.inventory.wood=4
	person.inventory.fiber=2
	app.session._send_snapshot(1)
	app._build_menu()
	await process_frame
	tab=app.modal.find_child("BuildTab2",true,false) as Button
	if tab:tab.pressed.emit()
	slot=app.modal.find_child("BuildSlot_shell_chime_2",true,false) as Button
	expect(slot!=null and slot.is_visible_in_tree(),"The shell chime is in the furniture catalog")
	if slot:slot.pressed.emit()
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	expect(place!=null and not place.disabled,"The shell recipe can be selected with its three materials")
	if place:place.pressed.emit()
	await process_frame
	expect(app.building==shell_kind,"Choosing the recipe activates shell chime placement")
	app.session.perform("build",at,app.building)
	expect(world.state.objects.get(key,{}).get("type")==shell_kind and not world.blocked(at)
		and int(person.inventory.get(shell_item,0))==0 and int(person.inventory.wood)==0 and int(person.inventory.fiber)==0,
		"The freestanding shell chime spends exactly two shells, four wood and two fiber")
	app.sound.ambience_volume=0.25
	app.sound.refresh_gains()
	await create_timer(0.28).timeout
	app._interact()
	await create_timer(0.25).timeout
	expect(world.state.objects[key].has("bell_at") and app.sound.cue_kind=="shell_chime"
		and app.sound.player.playing,"Ringing the chime plays its own quiet cue")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("shell-chime.png"))==OK,"Capture the shell chime")
	expect(loaded.load_world(path) and loaded.state.objects[key].type==shell_kind,"The shell chime and ring timestamp survive reload")
	expect(world.act(token,"remove-shell-chime","remove",at).ok and int(person.inventory.get(shell_item,0))==2,"Dismantling the chime returns both shells")
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("CERAMIC_CHIME_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
