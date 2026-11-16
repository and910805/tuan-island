extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var app = preload("res://main.tscn").instantiate()
	app.village_art_preview = true
	root.add_child(app)
	app.session.profile.token = "chapter-journey"
	root.title = "糰糰島・礦層場景預覽"
	var dimensions: PackedStringArray = app.arg_value("qa-size", "1280x800").split("x")
	if dimensions.size() != 2:
		quit(1)
		return
	root.size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	var path: String = app.arg_value("qa-save", "")
	var floor_number := int(app.arg_value("qa-floor", "0"))
	if path.is_empty() or floor_number < 1 or floor_number > 5 or app.session.host(0, "渡口旅人", path) != OK:
		quit(1)
		return
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	var person: Dictionary = app.session.world.state.players[app.session.peers[1]]
	person.region = "mine_%d" % floor_number
	person.x = float(app.arg_value("qa-x", "24.5"))
	person.y = float(app.arg_value("qa-y", "23.5"))
	var tile := Vector2i(floori(person.x), floori(person.y))
	var world = app.session.world
	var previous_region: String = world._region
	world.switch_region(person.region)
	var valid: bool = world.is_land(tile) and not world.blocked(tile)
	world.switch_region(previous_region)
	if not valid:
		push_error("Capture position is blocked or outside land: %s %s" % [person.region, tile])
		quit(1)
		return
	app.session._send_snapshot(1)
	await create_timer(0.4).timeout
	app._refresh_hud()
	app.toast.hide()
	app._layout_preview()
	app.set_process(false)
	app.view.show_target = false
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var output: String = app.arg_value("qa-output", "")
	if output.is_empty() or root.get_texture().get_image().save_png(output) != OK:
		quit(1)
		return
	print("MINE_ENVIRONMENT_CAPTURE floor=", floor_number, " ", output)
	app.session.shutdown()
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	quit(0)
