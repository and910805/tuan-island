extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.session.profile.token="chapter-journey"
	var parts:String=app.arg_value("qa-size","1280x800")
	root.size=Vector2i(int(parts.split("x")[0]),int(parts.split("x")[1]))
	var save:String=app.arg_value("qa-save","")
	var output:String=app.arg_value("qa-output","")
	if save.is_empty() or output.is_empty():quit(1);return
	if app.session.host(int(app.arg_value("qa-port","30585")),"渡口新住民",save)!=OK:quit(1);return
	await create_timer(0.3).timeout
	var panel:String=app.arg_value("qa-panel","travel")
	var world=app.session.world
	var token:String=app.session.peers[1]
	# Explicit screenshot placement in an isolated migrated chapter checkpoint.
	if panel!="farm":
		world.state.players[token].x=46.5;world.state.players[token].y=30.5
	if panel not in ["home","farm"]:
		app.session.perform("travel",Vector2i(47,30),"lanyang")
		if world.player_region(token)!="lanyang":push_error("Travel failed");quit(1);return
	if panel=="field":
		world.state.players[token].x=30.5;world.state.players[token].y=28.5
	app.session._send_snapshot(1)
	await create_timer(0.4).timeout
	if panel in ["travel","home"]:app._travel_menu()
	elif panel=="map":app._map_menu()
	elif panel not in ["field","farm"]:quit(1);return
	await create_timer(0.5).timeout
	app._refresh_hud();app._layout_preview()
	await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output)!=OK:quit(1);return
	print("REGIONS_CAPTURE "+panel+" "+output)
	app._close_modal();app.session.shutdown()
	await create_timer(0.4).timeout
	app.queue_free();await process_frame
	quit(0)
