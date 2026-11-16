extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.session.profile.token="chapter-journey"
	root.title="糰糰島・金瓜石測試"
	var parts:String=app.arg_value("qa-size","1280x800")
	root.size=Vector2i(int(parts.split("x")[0]),int(parts.split("x")[1]))
	var save:String=app.arg_value("qa-save","");var output:String=app.arg_value("qa-output","")
	if save.is_empty():quit(1);return
	if app.session.host(int(app.arg_value("qa-port","30687")),"渡口旅人",save)!=OK:quit(1);return
	await create_timer(0.3).timeout
	var panel:String=app.arg_value("qa-panel","world")
	var world=app.session.world;var token:String=app.session.peers[1]
	if panel=="travel":world.state.players[token].x=46.5;world.state.players[token].y=30.5
	if panel in ["mine","strike"]:
		world.state.players[token].x=27.5;world.state.players[token].y=20.5
		app._select_tool("pick")
	app.session._send_snapshot(1);await create_timer(0.4).timeout
	if panel=="travel" or panel=="return":app._travel_menu()
	elif panel=="map":app._map_menu()
	elif panel=="inventory":app._inventory()
	elif panel=="craft":app.automation_ui.workbench(app,Vector2i(40,35))
	await create_timer(0.5).timeout
	if panel=="strike":
		app._interact()
		await create_timer(0.1).timeout
		if int(app.session.snapshot.players[app.session.own_id].inventory.get("copper_ore",0))<4:push_error("Mining interaction failed");quit(1);return
	app._refresh_hud();app._layout_preview();await process_frame;await RenderingServer.frame_post_draw
	if not output.is_empty():
		if root.get_texture().get_image().save_png(output)!=OK:quit(1);return
	print("JINGUASHI_CAPTURE "+panel+" "+output)
	if app.arg_value("qa-native","")=="true":
		await create_timer(600).timeout
	app._close_modal();app.session.shutdown();await create_timer(0.4).timeout
	app.queue_free();await process_frame;quit(0)
