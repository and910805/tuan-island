extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var settings:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	root.size=Vector2i(1024,640)
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.port_input.text=str(settings.port)
	app._host(false)
	await process_frame
	if app.playing or app.session.world!=null or not app.toast.text.contains("另一個視窗"):
		printerr("Storage contention was not visibly refused")
		quit(1)
		return
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(settings.output)!=OK:
		quit(1)
		return
	print("WRITER_FAILURE_UI_PASS")
	quit()
