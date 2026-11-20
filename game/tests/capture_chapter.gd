extends SceneTree

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.session.profile.token=app.arg_value("qa-player","chapter-journey")
	var dimensions:String=app.arg_value("qa-size","1280x800")
	var parts:=dimensions.split("x")
	root.size=Vector2i(int(parts[0]),int(parts[1]))
	var save:String=app.arg_value("qa-save","")
	var output:String=app.arg_value("qa-output","")
	if save.is_empty() or output.is_empty():quit(1);return
	var err:int=app.session.host(int(app.arg_value("qa-port","30485")),"渡口新住民",save)
	if err!=OK:quit(1);return
	await create_timer(0.7).timeout
	var panel:String=app.arg_value("qa-panel","chapter")
	if panel in ["mill-world","mill-map"]:
		app._close_modal()
		var mill=app.session.world.MILL_RESTORATION
		if not app.session.snapshot.get(mill.SITE_VISIBLE,false):quit(1);return
		if panel=="mill-world":
			var person:Dictionary=app.session.world.state.players[app.session.profile.token]
			person.x=mill.APPROACH.x+0.5
			person.y=mill.APPROACH.y+0.5
			app.session._send_snapshot(1)
	match panel:
		"chapter":app._chapter_menu()
		"story-route":preload("res://scripts/life_ui_tasks.gd").story_route(app)
		"festival":app.LifeAlmanac.festival_story(app,true,clampi(int(app.arg_value("qa-scene","0")),0,3))
		"map":app._map_menu()
		"mill-map":
			app._map_menu()
			app.map_view.select_home_route("mill")
		"aru":app._resident_menu("aru")
		"world","mill-world":pass
		_:quit(1);return
	await create_timer(0.5).timeout
	app._refresh_hud()
	app._layout_preview()
	await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	if image.save_png(output)!=OK:quit(1);return
	print("CHAPTER_CAPTURE "+str(app.session.snapshot.chapter_one)+" "+output)
	app._close_modal()
	app.session.shutdown()
	await create_timer(0.8).timeout
	app.queue_free()
	await process_frame
	quit(0)
