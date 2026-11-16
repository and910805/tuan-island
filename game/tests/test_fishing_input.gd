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
	world.state.time=person.fishing.ready
	app.session._send_snapshot(1)
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
	await click(WATER)
	expect(person.has("fishing") and fish_count(person)==count+1,"Another click starts a fresh cast without duplicating fish")
	var binding:Dictionary=app.bindings.rebind("fish_catch",KEY_F9)
	expect(binding.ok,"Catch binding can be changed")
	world.state.time=person.fishing.ready
	app.session._send_snapshot(1)
	app._refresh_hud()
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
	app.session.shutdown()
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings",".settings"]:DirAccess.remove_absolute(path+suffix)
	print("FISHING_INPUT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
