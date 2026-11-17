extends SceneTree
const World=preload("res://scripts/world.gd")
var app
var directory:=""
var checks:=0
var failures:=0
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func shot(name:String)->void:
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800) if app.arg_value("qa-size","")=="1280" else Vector2i(1024,640)
	directory=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="chicken-cuddle-native-qa"
	expect(app.session.host(0,"抱抱糯米雞",directory.path_join("world.json"))==OK,"Host normal-stock isolated world")
	await create_timer(0.25).timeout
	app.session.set_physics_process(false)
	app.set_process(false)
	var world=app.session.world
	var token:String=app.session.peers[1]
	world.state.players[token].x=45.5
	world.state.players[token].y=35.5
	expect(world.can_stand(Vector2(45.5,35.5)),"Standing position is collision-valid")
	app.session._send_snapshot(1)
	preload("res://scripts/wangan_opening_ui.gd").dismiss(app)
	app.view.set_process(false)
	app.view.reduced_motion=app.arg_value("qa-reduced","")=="true"
	app.view.photograph_mode=app.arg_value("qa-photo","")=="true"
	app._animal_menu()
	app._layout_preview()
	await create_timer(0.3).timeout
	var hug:=app.modal.find_child("ChickenHug",true,false) as Button
	expect(hug!=null and not hug.disabled,"Real animal menu has enabled hug button")
	await shot("menu")
	var bag:Dictionary=world.state.players[token].inventory.duplicate(true)
	hug.pressed.emit()
	app.session._send_snapshot(1)
	await create_timer(0.3).timeout # Let the closing modal finish its fade before sampling.
	expect(World.CHICKEN_CUDDLE.holder(world.state,world.active_tokens)==token,"Button actually claims shared chicken")
	app._refresh_hud()
	expect(not app.selected_label.visible,"Conflicting tool hint is hidden while cuddling")
	var before:Dictionary=world.state.duplicate(true)
	var camera:Vector2=app.view.camera
	var start:float=app.view.elapsed
	for frame in 20:
		app.view.elapsed=start+frame*0.06
		await shot("hug_%02d"%frame)
		expect(app.view.chicken_draw_stats.carried==1 and app.view.chicken_draw_stats.ground==0,"Exactly one chicken is drawn, held only")
		expect(world.state==before and app.view.camera==camera,"Decorative foot kicks never mutate world or camera")
	app._use_selected_at(Vector2i(44,35))
	expect(world.state==before,"Clicking a tool cannot act while cuddling")
	world.move_player(token,Vector2.DOWN,0.1)
	expect(float(world.state.players[token].y)>35.5,"Actual collision-checked movement works while carrying")
	app.session._send_snapshot(1)
	app.view._process(0.2)
	await shot("walk")
	app._interact()
	app.session._send_snapshot(1)
	app._refresh_hud()
	await shot("released")
	expect(app.selected_label.visible,"Original tool hint returns after release")
	expect(app.view.chicken_draw_stats.carried==0 and app.view.chicken_draw_stats.ground==1,"Interaction key returns the only hen")
	expect(world.state.players[token].inventory==bag and world.state.animal.bond==1,"Release keeps inventory and exactly one bond")
	world.step(30.1,true)
	app.session.rates[1].clear()
	app.session.perform("chicken_hug",World.CHICKEN_CELL)
	expect(World.CHICKEN_CUDDLE.holder(world.state,world.active_tokens)==token,"Second hug after real cooldown")
	expect(world.step(8.1,true),"Run actual timeout tick")
	app.session._send_snapshot(1)
	app._refresh_hud()
	await shot("timeout")
	expect(app.selected_label.visible,"Original tool hint returns after timeout")
	expect(app.view.chicken_draw_stats.carried==0 and app.view.chicken_draw_stats.ground==1,"Timeout returns hen without duplication")
	app.session.shutdown()
	print("CHICKEN_CUDDLE_NATIVE checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
