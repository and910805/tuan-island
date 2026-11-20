extends SceneTree

const World=preload("res://scripts/world.gd")
const WATER:=Vector2i(55,34)
var app
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func click(cell:Vector2i)->void:
	app.action_clock=0
	var point:Vector2=app.view.screen(Vector2(cell)+Vector2(0.5,0.5))*app.view.view_zoom()
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	event.position=point
	event.global_position=point
	root.push_input(event,true)
	event=event.duplicate()
	event.pressed=false
	root.push_input(event,true)
	await process_frame

func fish_count(person:Dictionary)->int:
	var total:=0
	for id in World.FISH:total+=int(person.inventory.get(id,0))
	return total

func tap_pad(button:JoyButton)->void:
	var event:=InputEventJoypadButton.new()
	event.button_index=button
	event.pressed=true
	root.push_input(event,true)
	var release:=event.duplicate() as InputEventJoypadButton
	release.pressed=false
	root.push_input(release,true)
	await process_frame

func run()->void:
	root.size=Vector2i(1280,800)
	var path:=OS.get_environment("TEMP").path_join("fish-input-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"釣魚旅人",path)!=OK:
		expect(false,"Host starts")
		quit(1)
		return
	app.set_process(false)
	app.session.set_physics_process(false)
	var bindings_path:=path+".bindings"
	app.bindings.load_preferences(bindings_path)
	var world=app.session.world
	var person:Dictionary=world.state.players[app.session.peers[1]]
	person.x=54.5
	person.y=34.5
	app.session._send_snapshot(1)
	app._select_tool("fish")
	await process_frame
	await process_frame
	var count:=fish_count(person)
	await click(WATER)
	expect(person.has("fishing") and fish_count(person)==count,"Mouse casts at the water tile")
	if not person.has("fishing"):
		quit(1)
		return
	var sequence:int=app.session.counter
	await click(WATER)
	expect(app.session.counter==sequence+1 and person.has("fishing") and fish_count(person)==count and "還沒咬鉤" in app.toast.text,"Early click reaches the server and is rejected")
	app.sound.master_volume=0.0
	app.sound.refresh_gains()
	world.state.time=person.fishing.ready
	app.session._send_snapshot(1)
	expect(app.activity_caption.visible and "魚咬鉤了" in app.activity_caption.text,"The bite caption is visible with all sound muted")
	sequence=app.session.counter
	await click(WATER+Vector2i.DOWN)
	expect(app.session.counter==sequence and person.has("fishing"),"Different water tile never sends a catch")
	app._inventory()
	await process_frame
	await click(WATER)
	expect(app.session.counter==sequence and person.has("fishing"),"Modal blocks the mouse catch before dispatch")
	app._close_modal()
	await process_frame
	await click(WATER)
	expect(app.session.counter==sequence+1 and not person.has("fishing") and fish_count(person)==count+1,"Ready click reels in exactly one fish")
	expect(app.activity_caption.visible and "魚已收入背包" in app.activity_caption.text,"Catching the fish replaces the bite caption")
	expect("點水面拋竿" in app.selected_label.text and not "魚咬鉤了" in app.selected_label.text,
		"Catch snapshot immediately clears the old toolbar prompt with periodic refresh disabled")
	await click(WATER)
	expect(person.has("fishing") and fish_count(person)==count+1,"Another click starts a fresh cast without duplicating fish")
	var binding:Dictionary=app.bindings.rebind("fish_catch",KEY_F9)
	expect(binding.ok,"Catch binding can be changed")
	world.state.time=person.fishing.ready
	app.session._send_snapshot(1)
	expect("點浮標或按 F9" in app.selected_label.text,"Mouse and remapped key appear in the live ready prompt")
	var key:=InputEventKey.new()
	key.keycode=KEY_F9
	key.physical_keycode=KEY_F9
	key.pressed=true
	root.push_input(key,true)
	expect(not person.has("fishing") and fish_count(person)==count+2,"Remapped keyboard action still reels in a ready fish")
	var settings_path:=path+".settings"
	expect(app.sound.save_preferences(settings_path,0.0,true,2,null,true),"Standard mode can be saved")
	app.sound.standard_fishing=false
	expect(app.sound.load_preferences(settings_path) and app.sound.standard_fishing,"Saved mode survives loading preferences")
	# Reset the two anglers so the standard and relaxed catches can be
	# compared from the same fish rotation and world conditions.
	person.fish_caught=0
	person.collection.fish.clear()
	for species in World.FISH:person.inventory.erase(species)
	for index in range(4):
		app.session.rates[1].clear() # Test advances world time without waiting on the wall clock.
		await click(WATER)
		expect(person.get("fishing",{}).has("band"),"Selected standard mode reaches the server from a world click")
		if not person.has("fishing"):
			quit(1)
			return
		world.state.time=person.fishing.ready
		app.session._send_snapshot(1)
		await click(WATER)
		expect(fish_count(person)==index and person.has("fishing"),"First adjustment cannot award a fish")
		world.state.time+=20.0
		app.session._send_snapshot(1)
		await click(WATER)
		expect(fish_count(person)==index,"Waiting without tracking cannot complete the catch")
		for adjustment in range(12):
			if not person.has("fishing"):break
			world.state.time+=0.8
			app.session._send_snapshot(1)
			await click(WATER)
		expect(fish_count(person)==index+1 and not person.has("fishing"),"Staying near the fish and reeling grants one catch")
		if person.has("fishing"):
			quit(1)
			return
	var standard_collection:Dictionary=person.collection.fish.duplicate()
	expect(standard_collection.size()==4,"Standard mode unlocks all four freshwater entries")
	person.fish_caught=0
	person.collection.fish.clear()
	app.sound.standard_fishing=false
	for index in range(4):
		app.session.rates[1].clear()
		await click(WATER)
		expect(person.has("fishing") and not person.fishing.has("band"),"Relaxed mode casts without tracking data")
		if not person.has("fishing"):
			quit(1)
			return
		world.state.time=float(person.fishing.ready)+20.0
		app.session._send_snapshot(1)
		await click(WATER)
		expect(fish_count(person)==5+index,"Relaxed mode awards the same single catch after a long wait")
	expect(person.collection.fish==standard_collection,"Both modes complete the same freshwater collection")
	app.session.rates[1].clear()
	app.controller_offset=Vector2i.DOWN
	await tap_pad(JOY_BUTTON_DPAD_UP)
	await tap_pad(JOY_BUTTON_DPAD_RIGHT)
	app.action_clock=0
	await tap_pad(JOY_BUTTON_X)
	var cast:Dictionary=person.get("fishing",{})
	expect(not cast.is_empty() and Vector2i(cast.get("x",0),cast.get("y",0))==WATER,"D-pad and X cast at the river tile")
	expect("手把 X" in app.toast.text,"Cast feedback shows the button for the active input device")
	if not cast.is_empty():
		await tap_pad(JOY_BUTTON_DPAD_DOWN)
		world.state.time=float(cast.ready)
		app.session._send_snapshot(1)
		expect("手把 X" in app.selected_label.text and "手把 X" in app.activity_caption.text,"The bite hint and caption show the controller button")
		var previous_catch:=fish_count(person)
		app.action_clock=0
		await tap_pad(JOY_BUTTON_X)
		expect(not person.has("fishing") and fish_count(person)==previous_catch+1,"X reels the active cast even after aiming elsewhere")
		expect("十字鍵" in app.selected_label.text,"Controller hint immediately returns to cast guidance")
	if failures==0:await verify_rod_preview(world,person)
	app.session.shutdown()
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings",".settings"]:DirAccess.remove_absolute(path+suffix)
	print("FISHING_INPUT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_rod_preview(world:World,person:Dictionary)->void:
	app.session.rates[1].clear()
	app.sound.standard_fishing=true
	person.inventory.precision_rod=1
	app.controller_aim=false
	app.controller_navigation=false
	app.session._send_snapshot(1)
	app._refresh_hud()
	var rod_button:Button=app.preview_toolbar.find_child("FishingSlot",true,false)
	expect(rod_button.tooltip_text.begins_with("精製釣竿") and app.selected_label.text.contains("精製釣竿"),"The action hint and slot show the equipped rod")
	await click(WATER)
	var cast:Dictionary=person.get("fishing",{})
	expect(cast.get("rod")=="precision_rod" and is_equal_approx(float(cast.get("ready",-1.0))-float(world.state.time),1.8),"The real world click starts a precision cast")
	if cast.is_empty():return
	world.state.time=float(cast.ready)+0.5
	app.session._send_snapshot(1)
	app.view.selected="fish"
	app.view.hide_interaction_prompt=false
	app.toast_time=0.0
	app.toast.hide()
	app.activity_caption_time=0.0
	app.activity_caption.hide()
	app.view.queue_redraw()
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--rod-preview=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--rod-preview="))==OK,"Capture the precision tracking band")
