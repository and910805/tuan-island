extends SceneTree
func _initialize()->void:
	run.call_deferred()
func wait_until(predicate:Callable)->bool:
	for attempt in range(150):
		if predicate.call():return true
		await create_timer(0.08).timeout
	return false
func run()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	root.size=Vector2i(1024,640)
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app._open_identity()
	var entry=app.identity_entry
	entry.api.text=data.api
	entry.account.text=data.account_id
	entry.credential.text=data.credential
	entry.login()
	if not await wait_until(func():return not entry.busy and entry.world_cards.get_child_count()>0 and entry.world_cards.get_child(0) is PanelContainer):
		printerr("Failure fixture world not published")
		quit(1)
		return
	entry.world_cards.get_child(0).get_child(0).pressed.emit()
	entry.world_detail.get_child(0).get_child(0).get_child(-1).pressed.emit()
	if not await wait_until(func():return not entry.joining and entry.status.text.contains("暫停寫入")) or app.playing or not entry.status.is_visible_in_tree():
		printerr("Recovery rejection was not visible")
		quit(1)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(data.output)!=OK:quit(1);return
	print("ADMISSION_FAILURE_UI_PASS")
	quit()
