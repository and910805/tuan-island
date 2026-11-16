extends SceneTree
## Real site interaction, using fixture travel, bond and chapter progress.
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func run() -> void:
	var app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://achao-route-%d.json"%OS.get_process_id()
	if app.session.host(0,"航線旅人",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var man:Dictionary=world.state.players[token]
	world.state.board=true
	world.state.picnic=true
	world.state.dock_stage=1
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	man.bonds={"achao":{"points":6,"talk_day":-1,"gift_day":-1}}
	for site:String in Goals.ROUTE_SIGNS:
		var at:=World.achao_route_cell(site)
		man.x=at.x+0.5
		man.y=at.y+0.5
		app.session._send_snapshot(1)
		app._interact()
		await process_frame
		var marker:=app.modal.find_child("AchaoRouteMarker",true,false) as Button if is_instance_valid(app.modal) else null
		expect(marker!=null,"The ordinary site page has a marker: "+site)
		if marker!=null:marker.pressed.emit()
		await process_frame
		expect((int(app.session.snapshot.own_achao_route_marks)&int(Goals.ROUTE_SIGNS[site].bit))!=0,"Marks are synced for "+site)
		expect(not world.act(token,"repeat-"+site,Goals.ROUTE_ACTION,at,site).ok,"One sign counts only once")
	var achao:Vector2i=World.bond_place(world.state,"achao")[1]
	man.x=achao.x+0.5
	man.y=achao.y+0.5
	app.session.rates[1].clear()
	app.session.perform(Goals.ACTION,achao,"achao:2::")
	await process_frame
	expect(app.session.snapshot.resident_goals.achao["2"].state=="done","Report all three landmarks")
	app._resident_bond_menu("achao")
	await process_frame
	var map_button:=app.modal.find_child("AchaoRouteBook",true,false) as Button
	expect(map_button!=null,"Achao offers the hand-drawn map")
	if map_button!=null:map_button.pressed.emit()
	await process_frame
	var title_found:=false
	for label in app.modal.find_children("*","Label",true,false):
		if label.text=="阿潮的手繪群島地圖":title_found=true
	expect(title_found,"Unlocked view shows Achao's map")
	for resolution in [Vector2i(1280,800),Vector2i(1024,640)]:
		root.size=resolution
		await process_frame
		await process_frame
		var map:=app.modal.find_child("AchaoChart",true,false) as Control
		var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
		expect(map!=null and scroll!=null and scroll.get_global_rect().encloses(map.get_global_rect()),"Whole travel map fits at "+str(resolution))
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				var output:=arg.trim_prefix("--capture-dir=").path_join("achao-route-map-%dx%d.png"%[resolution.x,resolution.y])
				expect(root.get_texture().get_image().save_png(output)==OK,"Capture the unlocked map")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path) and int(loaded.state.players[token].get(Goals.ROUTE_KEY,0))==Goals.ROUTE_MASK,"All three marks survive a reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ACHAO_ROUTE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
