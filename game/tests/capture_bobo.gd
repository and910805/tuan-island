extends SceneTree
const World=preload("res://scripts/world.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.session.profile.token="chapter-journey"
	root.title="糰糰島・礦山故事測試"
	var size:String=app.arg_value("qa-size","1280x800")
	root.size=Vector2i(int(size.split("x")[0]),int(size.split("x")[1]))
	var path:String=app.arg_value("qa-save","")
	if path.is_empty() or app.session.host(0,"渡口旅人",path)!=OK:quit(1);return
	await create_timer(0.3).timeout
	var panel:String=app.arg_value("qa-panel","world")
	var world=app.session.world
	var person:Dictionary=world.state.players[app.session.peers[1]]
	var sites:Dictionary=World.BOBO_WORKSHOP.sites(world.state)
	var at:Vector2i=sites.table+Vector2i.DOWN if panel=="sort" else sites.npc+Vector2i.DOWN
	person.x=at.x+0.5;person.y=at.y+0.5
	app.session._send_snapshot(1);await create_timer(0.4).timeout
	if panel=="sort":app._interact()
	elif panel=="resident":app._resident_menu("bobo")
	elif panel=="journal":app._journal("bobo")
	elif panel=="inventory":app._inventory()
	await create_timer(0.4).timeout
	app._refresh_hud();app._layout_preview();await process_frame;await RenderingServer.frame_post_draw
	var output:String=app.arg_value("qa-output","")
	if not output.is_empty() and root.get_texture().get_image().save_png(output)!=OK:quit(1);return
	print("BOBO_CAPTURE "+panel+" "+output)
	if app.arg_value("qa-native","")=="true":await create_timer(600).timeout
	app._close_modal();app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;quit(0)
