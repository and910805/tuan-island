extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.session.profile.token="chapter-journey"
	root.title=app.arg_value("qa-title","糰糰島・自動裝運測試")
	var dimensions:String=app.arg_value("qa-size","1280x800")
	root.size=Vector2i(int(dimensions.split("x")[0]),int(dimensions.split("x")[1]))
	var path:String=app.arg_value("qa-save","")
	if path.is_empty() or app.session.host(0,"渡口旅人",path)!=OK:quit(1);return
	await create_timer(0.3).timeout
	var person:Dictionary=app.session.world.state.players[app.session.peers[1]]
	var panel:String=app.arg_value("qa-panel","world")
	person.region="mine_4";person.x=33.5;person.y=20.5
	if app.arg_value("qa-native","")!="true":app.session.set_physics_process(false)
	var world=app.session.world
	var actor:String=app.session.peers[1]
	if panel=="paused":
		var result:Dictionary=world.act(actor,"capture-pause","mine_auto_toggle",Vector2i(34,20))
		if not result.ok:quit(1);return
	elif panel in ["missing","held"]:
		# Fault demonstrations use a disposable copy and simulated endpoint removal.
		var route:Dictionary=world.state.mine_auto_freight.routes[actor]
		world.state.objects.erase(route.target.cell)
		if panel=="held":world.step(61.0,true)
		else:world.state.mine_freight.jobs.erase(actor)
	app.session._send_snapshot(1)
	await create_timer(0.4).timeout
	if panel=="manual":app._freight_menu()
	else:app._auto_freight_menu()
	var expected_layout:="mine_freight" if panel=="manual" else "auto_freight"
	if not is_instance_valid(app.modal) or app.modal.get_meta("life_modal_layout","")!=expected_layout:quit(1);return
	await create_timer(0.4).timeout
	app._refresh_hud();app.toast.hide();app._layout_preview()
	if app.arg_value("qa-native","")!="true":
		app.set_process(false)
		app.view.show_target=false
	app.view.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	var output:String=app.arg_value("qa-output","")
	if not output.is_empty() and root.get_texture().get_image().save_png(output)!=OK:quit(1);return
	if app.arg_value("qa-debug","")=="true" and app.modal:
		for c in app.modal.find_children("*","Control",true,false):
			if c is Label:print(c.text, " ",c.get_global_rect())
	print("AUTO_FREIGHT_CAPTURE "+panel+" "+output)
	if app.arg_value("qa-native","")=="true":await create_timer(600).timeout
	app._close_modal();app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;quit(0)
