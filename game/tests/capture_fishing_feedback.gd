extends SceneTree
const World = preload("res://scripts/world.gd")
const WATER := Vector2i(55,34)
var app
var directory := ""
var token := ""
var frames: Array = []

func _initialize() -> void: run.call_deferred()

func fish_count(person: Dictionary) -> int:
	var total := 0
	for id in World.FISH: total += int(person.inventory.get(id,0))
	return total

func capture(index: int, stage: String) -> void:
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var name := "%03d.png" % index
	assert(root.get_texture().get_image().save_png(directory.path_join(name)) == OK)
	var feedback: Dictionary = app.view.fishing_feedback.state_for(app.session.own_id, float(app.view.data.time), app.view.elapsed)
	frames.append({"file":name,"nominal_stage":stage,"actual_phase":feedback.get("phase", ""),"elapsed":app.view.elapsed,"timestamp_ms":Time.get_ticks_msec(),"time":app.session.world.state.time})

func run() -> void:
	app = preload("res://main.tscn").instantiate()
	app.village_art_preview = true
	root.add_child(app)
	app.session.profile.token = "chapter-journey"
	root.size = Vector2i(1280,800)
	root.title = "釣魚動態預覽"
	directory = app.arg_value("qa-dir", "")
	assert(not directory.is_empty() and DirAccess.make_dir_recursive_absolute(directory) == OK)
	assert(app.session.host(0,"渡口旅人",app.arg_value("qa-save","")) == OK)
	await create_timer(0.3).timeout
	if is_instance_valid(app.modal):app._close_modal()
	app.WanganUI.dismiss(app)
	app.session.set_physics_process(false)
	token = app.session.peers[1]
	var world = app.session.world
	var person: Dictionary = world.state.players[token]
	var dense_reel:bool=app.arg_value("qa-dense-reel","false")=="true"
	person.region = "home"
	person.x = 54.5
	person.y = 34.5
	if dense_reel:world.state.time=720.0
	world.switch_region("home")
	assert(world.can_stand(Vector2(person.x,person.y)) and world.water(WATER))
	var initial := fish_count(person)
	app.view.reduced_motion = app.arg_value("qa-reduced", "false") == "true"
	app.selected = "fish"
	app.view.selected = "fish"
	app.session._send_snapshot(1)
	await create_timer(0.3).timeout
	if app.arg_value("qa-springs","false")=="true":
		world.state.picnic=true
		person.x=46.5
		person.y=30.5
		app.session._send_snapshot(1)
		app.session.perform("transit",Vector2i(47,30),"toucheng")
		assert(person.region=="toucheng")
		person.x=24.5
		person.y=19.5
		app.session._send_snapshot(1)
		await create_timer(0.3).timeout
		app._travel_menu("rail")
		app.modal.set_meta("travel_selected","jiaoxi")
		preload("res://scripts/travel_ui.gd").refresh(app)
		await create_timer(0.3).timeout
		await capture(0,"toucheng")
		app._close_modal()
		app.session.perform("transit",Vector2i(25,19),"jiaoxi")
		assert(person.region=="jiaoxi")
		person.x=20.5
		person.y=22.5
		world.state.time=720.0
		app.session._send_snapshot(1)
		await create_timer(3.0).timeout
		app._map_menu()
		await create_timer(0.3).timeout
		await capture(3,"springs-map")
		app._close_modal()
		app._select_tool("fish")
		await capture(1,"springs")
		var pool:=Vector2i(20,21)
		app.session.perform("fish_start",pool)
		assert(world.step(3.1,true))
		app.session._send_snapshot(1)
		await create_timer(0.5).timeout
		app.session.perform("fish_catch",pool)
		assert(person.inventory.get("glass_shrimp",0)==1)
		app._refresh_hud()
		await capture(2,"catch")
		assert(app.session.shutdown())
		quit(0)
		return
	app._refresh_hud()
	app.toast.hide()
	app._layout_preview()
	if app.arg_value("qa-standard","false")=="true":
		app.sound.standard_fishing=true
		app._select_tool("fish")
		app._settings_menu()
		await capture(0,"settings")
		app._close_modal()
		app.session.perform("fish_start",WATER,"standard")
		world.step(3.1,true)
		app.session._send_snapshot(1)
		await create_timer(0.5).timeout
		for i in range(1,10):
			app._refresh_hud()
			app.toast.hide()
			await capture(i,"tracking" if person.has("fishing") else "catch")
			if not person.has("fishing"):break
			app.session.perform("fish_catch",WATER)
			world.step(0.8,true)
			app.session._send_snapshot(1)
			await create_timer(0.16).timeout
		assert(fish_count(person)==initial+1)
		app.session.shutdown()
		await create_timer(0.3).timeout
		quit(0)
		return
	app.session.perform("fish_start", WATER)
	assert(person.has("fishing"))
	var fishing_frames:=64 if dense_reel else 48
	for i in range(fishing_frames):
		var stage := "cast" if i < 5 else ("wait" if i < 30 else ("ready" if i < 36 else "catch"))
		if i == 36:
			assert(float(world.state.time) >= float(person.fishing.ready))
			app.session.perform("fish_catch", WATER)
			assert(not person.has("fishing") and fish_count(person) == initial+1)
		await capture(i, stage)
		if i < 36:
			assert(world.step(0.1,true))
			app.session._send_snapshot(1)
		await create_timer(0.04 if dense_reel and i>=36 else 0.1).timeout
	assert(world.save())
	var reopened := World.new()
	assert(reopened.load_world(world.save_path))
	assert(fish_count(reopened.state.players[token]) == initial+1)
	app.session.perform("fish_start", WATER)
	assert(person.has("fishing"))
	await create_timer(0.6).timeout
	await capture(fishing_frames,"before-cancel")
	world.move_player(token,Vector2.LEFT,0.1)
	assert(not person.has("fishing") and fish_count(person) == initial+1)
	app.session._send_snapshot(1)
	for i in range(1,9):
		if i==8:await create_timer(0.2).timeout
		await capture(fishing_frames+i,"cancel")
		await create_timer(0.04).timeout
	assert(frames[fishing_frames+1].actual_phase=="cancel" and frames[fishing_frames+8].actual_phase=="")
	var file := FileAccess.open(directory.path_join("sequence.json"),FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"scripted_position":[54.5,34.5],"target":[55,34],"reduced_motion":app.view.reduced_motion,"fish_before":initial,"fish_after":fish_count(person),"reload_preserved":true,"cancel_no_fish":true,"frames":frames}))
	file.close()
	print("FISHING_CAPTURE_PASS reduced=",app.view.reduced_motion," fish_before=",initial," fish_after=",fish_count(person))
	app.session.shutdown()
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	quit(0)
