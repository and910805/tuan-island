extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.session.profile.token="chapter-journey"
	root.title=app.arg_value("qa-title","糰糰島・礦脈採掘測試")
	var dimensions:String=app.arg_value("qa-size","1280x800")
	root.size=Vector2i(int(dimensions.split("x")[0]),int(dimensions.split("x")[1]))
	var path:String=app.arg_value("qa-save","")
	if path.is_empty() or app.session.host(0,"渡口旅人",path)!=OK:quit(1);return
	await create_timer(0.3).timeout
	var person:Dictionary=app.session.world.state.players[app.session.peers[1]]
	var panel:String=app.arg_value("qa-panel","world")
	if panel not in ["workbench","build"]:
		person.region="mine_4";person.x=29.5;person.y=24.5
	elif panel=="workbench":
		person.region="home";person.x=40.5;person.y=36.5
	if app.arg_value("qa-native","")!="true" and app.arg_value("qa-live","")!="true":
		app.session.set_physics_process(false)
	if panel=="placement":
		var token:String=app.session.peers[1]
		var result:Dictionary=app.session.world.act(token,"capture-refund","remove",Vector2i(28,24))
		if not result.get("ok",false) or int(person.inventory.get("mine_drill_kit",0))!=1:
			push_error("Could not recover existing drill kit for placement preview.")
			quit(1)
			return
	app.session._send_snapshot(1);await create_timer(0.4).timeout
	if panel=="drilling":
		app.MineDrillUI.open(app,Vector2i(28,24))
		if not is_instance_valid(app.modal) or app.modal.get_meta("life_modal_layout","")!="mine_drill":quit(1);return
	elif panel=="workbench":app.automation_ui.workbench(app,Vector2i(40,35))
	elif panel=="build":app._build_menu()
	elif panel in ["copper-filter","coal-filter"]:
		app.logistics_ui.device(app,Vector2i(27,24) if panel=="copper-filter" else Vector2i(28,25))
	elif panel=="placement":
		app.building="mine_drill"
		app._select_tool("build")
	await create_timer(0.4).timeout
	app._refresh_hud();app.toast.hide();app._layout_preview()
	if app.arg_value("qa-native","")!="true":
		app.set_process(false)
		app.view.show_target=panel=="placement"
		if panel=="placement":app.view.target=Vector2i(28,24)
	app.view.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	var output:String=app.arg_value("qa-output","")
	if not output.is_empty() and root.get_texture().get_image().save_png(output)!=OK:quit(1);return
	if app.arg_value("qa-debug","")=="true" and app.modal:
		for c in app.modal.find_children("*","Control",true,false):
			if c is Label:print(c.text, " ",c.get_global_rect())
	print("MINE_DRILL_CAPTURE "+panel+" "+output)
	if app.arg_value("qa-native","")=="true":await create_timer(600).timeout
	app._close_modal();app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;quit(0)
