extends SceneTree
const Main=preload("res://scripts/main.gd")
var app
var fixture:Dictionary
var capture_mode:=false

func _initialize() -> void:
	run.call_deferred()

func wait_for(predicate:Callable) -> bool:
	for attempt in range(150):
		if predicate.call():return true
		await create_timer(0.08).timeout
	return false

func capture(name:String) -> bool:
	if not capture_mode:return true
	await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	return image.save_png(fixture.output.path_join(name+"-"+fixture.size+".png"))==OK

func run() -> void:
	fixture=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	capture_mode=fixture.has("output")
	if capture_mode:
		var dimensions:String=fixture.size
		var sides:=dimensions.split("x")
		root.size=Vector2i(int(sides[0]),int(sides[1]))
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app._open_identity()
	var entry=app.identity_entry
	if not await capture("login"):quit(1);return
	entry.api.text=fixture.api
	entry.account.text=fixture.account_id
	entry.credential.text=fixture.credential
	entry.login()
	if not await wait_for(func():return not entry.busy) or not entry.world_page.visible or not entry.credential.text.is_empty():
		printerr("Login control did not complete: ",entry.status.text)
		quit(1)
		return
	entry.world.text=fixture.world
	entry.address.text=fixture.address
	entry.update_destination()
	if not await capture("world"):quit(1);return
	entry.join_world()
	if not await wait_for(func():return app.playing and not app.island_passport.is_empty()):
		printerr("Join control did not complete: ",entry.status.text)
		quit(1)
		return
	var previous_expiry:float=entry.expires
	entry.refresh_remaining=0.0
	if not await wait_for(func():return entry.expires>previous_expiry and not entry.busy):
		printerr("Live refresh did not extend the session")
		quit(1)
		return
	app._passport_menu()
	if not is_instance_valid(app.passport_code) or not app.passport_code.secret:
		printerr("Owner invitation control missing")
		quit(1)
		return
	if not await capture("passport"):quit(1);return
	app.session.request_invite_rotation()
	if not await wait_for(func():return not app.passport_code.text.is_empty()) or not app.passport_code.secret:
		printerr("Owner invitation rotation did not complete")
		quit(1)
		return
	app.session.request_invite_revocation()
	if not await wait_for(func():return app.passport_code.text.is_empty()):
		printerr("Owner invitation revocation did not complete")
		quit(1)
		return
	var revoked_token:String=entry.token
	entry.logout()
	if not await wait_for(func():return not entry.busy) or not entry.token.is_empty():
		printerr("Live logout did not clear the session")
		quit(1)
		return
	var revoked:Dictionary=await entry.request("/v1/refresh",{},revoked_token)
	if not revoked.get("expired",false):
		printerr("Logged-out session could still refresh")
		quit(1)
		return
	app.session.shutdown()
	app.queue_free()
	await process_frame
	print("IDENTITY_UI_NETWORK_PASS")
	quit()

