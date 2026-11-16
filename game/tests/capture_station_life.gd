extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.session.profile.token="chapter-journey"
	root.title="糰糰島・三站便箋測試"
	var dimensions:String=app.arg_value("qa-size","1280x800")
	root.size=Vector2i(int(dimensions.split("x")[0]),int(dimensions.split("x")[1]))
	var path:String=app.arg_value("qa-save","")
	if path.is_empty() or app.session.host(0,"渡口旅人",path)!=OK:quit(1);return
	await create_timer(0.3).timeout
	var person:Dictionary=app.session.world.state.players[app.session.peers[1]]
	var region:String=person.region
	var Life=preload("res://scripts/station_life.gd")
	if Life.RESIDENTS.has(region):
		var cell:Vector2i=Life.RESIDENTS[region].cell
		person.x=cell.x+1.5;person.y=cell.y+1.5
	app.session._send_snapshot(1);await create_timer(0.4).timeout
	var panel:String=app.arg_value("qa-panel","world")
	if panel=="dialogue":app._interact()
	elif panel=="memory":app.StationLifeUI.memory(app)
	elif panel=="journal":app._journal()
	await create_timer(0.4).timeout
	app._refresh_hud();app._layout_preview();await process_frame;await RenderingServer.frame_post_draw
	var output:String=app.arg_value("qa-output","")
	if not output.is_empty() and root.get_texture().get_image().save_png(output)!=OK:quit(1);return
	if app.arg_value("qa-debug","")=="true" and app.modal:
		for c in app.modal.find_children("*","Control",true,false):
			if c is Label:print(c.text, " ",c.get_global_rect())
	print("STATION_LIFE_CAPTURE "+panel+" "+output)
	if app.arg_value("qa-native","")=="true":await create_timer(600).timeout
	app._close_modal();app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;quit(0)
