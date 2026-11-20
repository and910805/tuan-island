extends "res://tests/test_spring_garden_scene.gd"
## Walk the native shore, start from the sign, add a shared mark and find three
## treasures with the temporary shovel. Picnic/arrival are isolated fixtures.
const Hunt=World.BEACH_TREASURE

func own()->Dictionary:
	return app.session.snapshot.get(Hunt.VIEW_KEY,{})

func shared()->Dictionary:
	return app.session.snapshot.get(Hunt.KEY,{})

func fit_panel()->void:
	if not check(is_instance_valid(app.modal),"Treasure panel opens"):return
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Treasure panel fits")
	var outer:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if outer:
		var scrollbar:=outer.get_v_scroll_bar()
		check(scrollbar.max_value<=scrollbar.page+1.0,"Treasure panel fits without outer scrolling")

func click_cell(cell:Vector2i)->void:
	var target_point:Vector2=app.view.screen(Vector2(cell)+HALF)*app.view.view_zoom()
	app.action_clock=0.0
	for down:bool in [true,false]:
		var click:=InputEventMouseButton.new()
		click.position=target_point
		click.global_position=target_point
		click.button_index=MOUSE_BUTTON_LEFT
		click.pressed=down
		root.push_input(click)
	await settle()

func sign_open()->bool:
	if not await walk_to(Hunt.SIGN):return false
	await key(KEY_E)
	return check(is_instance_valid(app.modal),"Coast activity sign opens")

func exercise()->void:
	world.state.erase(Hunt.KEY)
	world.state.players[player_id].erase(Hunt.KEY)
	var initial_bag:Dictionary=world.state.players[player_id].inventory.duplicate(true)
	app._select_tool("water")
	refresh()
	await settle()
	if not await sign_open():return
	fit_panel()
	await capture("01-shore-sign")
	if not await press("BeachTreasureStart"):return
	if not check(shared().get("phase")=="search" and int(shared().get("remaining",0))==300,"Search starts with five minutes"):return
	fit_panel()
	await capture("02-shared-clues")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	app._refresh_hud()
	if not check(app._beach_shovel_active() and not app.preview_toolbar.visible,"Coast replaces the normal tool belt with the event shovel"):return
	var first:Vector2i=Hunt.SPOTS.a.cell
	if not await walk_to(first):return
	await key(KEY_E)
	if not await press("BeachTreasureMark"):return
	check(shared().get("marks",{}).has("a"),"A map mark is public")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	app._refresh_hud()
	app.toast.hide()
	app.view.camera=(Vector2(Hunt.SIGN)+HALF)*32-Vector2(root.size)/(2.0*app.view.view_zoom())
	app.view.queue_redraw()
	await capture("03-marked-sand")
	for spot:String in Hunt.SPOTS:
		if shared().get("phase")!="search":break
		var site:Vector2i=Hunt.SPOTS[spot].cell
		if not await walk_to(site):return
		app.view.camera=(Vector2(site)+HALF)*32-Vector2(root.size)/(2.0*app.view.view_zoom())
		var score_before:=int(shared().get("score",0))
		await click_cell(site)
		var gained:=int(shared().get("score",0))-score_before
		check(gained==0 or gained==3,"An excavation scores either zero or three")
		if not check(own().get("dug",false) or shared().get("phase")=="results","A viewport click uses the event shovel"):return
	if not check(shared().get("phase")=="results" and int(shared().get("score",0))==9 and own().get("completed",false),"Three finds settle the round once"):return
	app._refresh_hud()
	check(app.preview_toolbar.visible and app.selected=="water","The original watering can returns after settlement")
	check(world.state.players[player_id].inventory==initial_bag,"The event changes no ordinary inventory")
	if not await sign_open():return
	fit_panel()
	await capture("04-treasure-results")
	if not await press("BeachTreasureStart"):return
	check(world.step(291.0,true),"Advance the real world clock to the last nine seconds")
	refresh()
	await settle()
	var countdown:=app.modal.find_child("BeachTreasureTimer",true,false) as Label
	check(countdown!=null and countdown.visible and countdown.text.contains("9"),"Only the final seconds show a countdown")
	check(world.step(10.0,true),"World tick settles the timeout")
	refresh()
	await settle()
	check(shared().get("phase")=="results" and shared().get("reason")=="time","The next round closes once at the deadline")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)

func run()->void:
	create_timer(100.0).timeout.connect(func():check(false,"Native suite watchdog");finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../outputs/beach-treasure")
	DirAccess.make_dir_recursive_absolute(output)
	if not check(DisplayServer.get_name()!="headless","Native renderer"):finish();return
	path=OS.get_environment("TEMP").path_join("beach-treasure-native-%d.json"%OS.get_process_id())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if not check(app.session.host(0,"尋寶旅人",path)==OK,"Start isolated native save"):finish();return
	world=app.session.world
	player_id=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	world.state.time=500.0
	var safe:=world.safe_arrival(Vector2(Hunt.SIGN)+Vector2(0.5,-0.5),player_id)
	world.state.players[player_id].x=safe.x
	world.state.players[player_id].y=safe.y
	app.playing=true
	refresh()
	await settle()
	if app.WanganUI.card_open(app):await key(KEY_E)
	for size:Vector2i in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		size_tag="%dx%d"%[size.x,size.y]
		await exercise()
	finish()

func finish()->void:
	if finished:return
	finished=true
	if is_instance_valid(app):app.session.shutdown()
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("BEACH_TREASURE_SCENE checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
