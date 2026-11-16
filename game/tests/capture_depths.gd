extends SceneTree
const World=preload("res://scripts/world.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.session.profile.token="chapter-journey"
	root.title="糰糰島・五層礦場測試"
	var parts:String=app.arg_value("qa-size","1280x800")
	root.size=Vector2i(int(parts.split("x")[0]),int(parts.split("x")[1]))
	var save:String=app.arg_value("qa-save","")
	var output:String=app.arg_value("qa-output","")
	if save.is_empty() or app.session.host(int(app.arg_value("qa-port","0")),"渡口旅人",save)!=OK:quit(1);return
	await create_timer(0.3).timeout
	var panel:String=app.arg_value("qa-panel","world")
	var world=app.session.world
	var token:String=app.session.peers[1]
	var person:Dictionary=world.state.players[token]
	if str(person.region).begins_with("mine_"):
		var cell:=Vector2i(23,21)
		if panel=="pump":cell=Vector2i(29,22)
		elif panel=="service":cell=World.MINES.SERVICE+Vector2i.LEFT
		elif panel=="rest":cell=World.MINES.REST+Vector2i.DOWN
		elif panel=="strike":cell=World.MINES.NODES[0]+Vector2i.DOWN
		person.x=cell.x+0.5;person.y=cell.y+0.5
	app.session._send_snapshot(1)
	await create_timer(0.4).timeout
	if panel in ["service","rest"]:preload("res://scripts/mine_ui.gd").open(app,panel)
	elif panel=="inventory":app._inventory()
	elif panel=="map":app._map_menu()
	await create_timer(0.5).timeout
	if panel=="strike":
		var before:Dictionary=person.inventory.duplicate(true)
		app._select_tool("pick")
		app._interact()
		await create_timer(0.1).timeout
		if before==person.inventory:push_error("Strike did not award ore");quit(1);return
	app._refresh_hud();app._layout_preview()
	await process_frame
	await RenderingServer.frame_post_draw
	if not output.is_empty() and root.get_texture().get_image().save_png(output)!=OK:quit(1);return
	print("DEPTHS_CAPTURE "+panel+" "+output)
	if app.arg_value("qa-native","")=="true":await create_timer(600).timeout
	app._close_modal();app.session.shutdown()
	await create_timer(0.4).timeout
	app.queue_free();await process_frame;quit(0)
