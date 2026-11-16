extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var app = preload("res://main.tscn").instantiate()
	app.village_art_preview = true
	root.add_child(app)
	app.session.profile.token = "chapter-journey"
	root.title = "側洞探索預覽"
	var size: PackedStringArray = app.arg_value("qa-size", "1280x800").split("x")
	root.size = Vector2i(int(size[0]), int(size[1]))
	if app.session.host(0, "渡口旅人", app.arg_value("qa-save", "")) != OK:
		quit(1)
		return
	await create_timer(0.4).timeout
	app.session.set_physics_process(false)
	app.session._send_snapshot(1)
	await create_timer(0.4).timeout
	var observing: bool = app.arg_value("qa-observe", "false") == "true"
	app.MineSurveyUI.open(app, int(app.arg_value("qa-page", "1")), observing, "")
	await create_timer(0.4).timeout
	app._refresh_hud()
	app.toast.hide()
	app._layout_preview()
	app.set_process(false)
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var output: String = app.arg_value("qa-output", "")
	if not is_instance_valid(app.modal) or app.modal.get_meta("life_modal_layout", "") != "mine_survey" or root.get_texture().get_image().save_png(output) != OK:
		quit(1)
		return
	print("SURVEY_CAPTURE ", output)
	app._close_modal()
	app.session.shutdown()
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	quit(0)
