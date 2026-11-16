extends SceneTree

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.session.profile.token="chapter-journey"
	var dimensions:String=app.arg_value("qa-size","1280x800")
	var parts:=dimensions.split("x")
	root.size=Vector2i(int(parts[0]),int(parts[1]))
	var save:String=app.arg_value("qa-save","")
	var output:String=app.arg_value("qa-output","")
	if save.is_empty() or output.is_empty():quit(1);return
	var err:int=app.session.host(int(app.arg_value("qa-port","30485")),"渡口新住民",save)
	if err!=OK:quit(1);return
	await create_timer(0.7).timeout
	var panel:String=app.arg_value("qa-panel","world")
	var world=app.session.world
	var table:Vector2i=app.World.COMMUNITY.table_cell(world.state)
	var player:Dictionary=world.state.players[app.session.peers[1]]
	var cell:=Vector2i(39,30) if table==app.World.COMMUNITY.NO_CELL else table
	var nearby:=cell+Vector2i(1,0)
	if world.blocked(nearby):nearby=cell+Vector2i(0,1)
	if world.blocked(nearby):quit(1);return
	player.x=nearby.x+0.5
	player.y=nearby.y+0.82
	app.session._send_snapshot(1)
	await create_timer(0.4).timeout
	match panel:
		"community":
			if app.view.interaction_focus()!="community":quit(1);return
			app._interact()
			if app.modal==null or app.modal.get_meta("life_modal_layout","")!="community_table":quit(1);return
		"milu":app._resident_menu("milu")
		"world":pass
		_:quit(1);return
	await create_timer(0.5).timeout
	app._refresh_hud()
	app._layout_preview()
	await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	if image.save_png(output)!=OK:quit(1);return
	print("COMMUNITY_CAPTURE "+panel+" "+output)
	app._close_modal()
	app.session.shutdown()
	await create_timer(0.8).timeout
	app.queue_free()
	await process_frame
	quit(0)
