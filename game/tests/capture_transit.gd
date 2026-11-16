extends SceneTree
const World=preload("res://scripts/world.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.session.profile.token="chapter-journey"
	root.title="糰糰島・北部交通測試"
	var size:String=app.arg_value("qa-size","1280x800")
	root.size=Vector2i(int(size.split("x")[0]),int(size.split("x")[1]))
	var path:String=app.arg_value("qa-save","")
	if path.is_empty() or app.session.host(0,"渡口旅人",path)!=OK:quit(1);return
	await create_timer(0.3).timeout
	var panel:String=app.arg_value("qa-panel","world")
	var station:String=app.arg_value("qa-station","")
	var person:Dictionary=app.session.world.state.players[app.session.peers[1]]
	var region:=str(person.region)
	if not station.is_empty():
		var cell:Vector2i=World.TRANSIT.points(region)[station].cell
		person.x=cell.x-0.5;person.y=cell.y+1.5
	app.session._send_snapshot(1);await create_timer(0.4).timeout
	if panel in ["ticket","ride"]:
		app._travel_menu(station)
		var destination:String=app.arg_value("qa-destination","")
		if not destination.is_empty():
			var select=app.modal.find_child("SelectRoute_"+destination,true,false)
			if select==null:push_error("Destination missing "+destination);quit(1);return
			select.pressed.emit()
	elif panel=="map":app._map_menu()
	await create_timer(0.4).timeout
	if panel=="ride":
		var button=app.modal.find_child("TravelDepart",true,false)
		if button==null or button.disabled:push_error("Departure unavailable");quit(1);return
		app.sound.reduced_motion=false
		button.pressed.emit();await create_timer(0.2).timeout
		if str(person.region)==region:push_error("Ride not committed");quit(1);return
	app._refresh_hud();app._layout_preview();await process_frame;await RenderingServer.frame_post_draw
	var output:String=app.arg_value("qa-output","")
	if not output.is_empty() and root.get_texture().get_image().save_png(output)!=OK:quit(1);return
	print("TRANSIT_CAPTURE "+panel+" "+output)
	if app.arg_value("qa-native","")=="true":await create_timer(600).timeout
	app._close_modal();app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;quit(0)
