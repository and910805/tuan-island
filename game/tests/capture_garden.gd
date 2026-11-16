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
	if app.session.host(int(app.arg_value("qa-port","30685")),"渡口新住民",save)!=OK:quit(1);return
	await create_timer(0.3).timeout
	var panel:String=app.arg_value("qa-panel","canal")
	var world=app.session.world
	var token:String=app.session.peers[1]
	world.state.players[token].x=32.5
	world.state.players[token].y=22.5 if panel=="clear" else 29.5
	app.session._send_snapshot(1)
	await create_timer(0.4).timeout
	if panel=="clear":
		if app.view.interaction_focus()!="ditch:33,22":push_error("Wrong blockage focus");quit(1);return
		app._interact()
	elif panel=="canal":app._gardener_menu()
	elif panel=="nursery":app.LanyangUI.open(app,"nursery")
	elif panel=="journal":app._journal("xinghe")
	elif panel=="map":app._map_menu()
	elif panel!="world":quit(1);return
	await create_timer(0.5).timeout
	app._refresh_hud();app._layout_preview()
	await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output)!=OK:quit(1);return
	print("GARDEN_CAPTURE "+panel+" "+output)
	app._close_modal();app.session.shutdown()
	await create_timer(0.4).timeout
	app.queue_free();await process_frame
	quit(0)
