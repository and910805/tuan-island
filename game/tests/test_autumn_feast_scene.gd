extends "res://tests/test_spring_garden_scene.gd"
## The Windows renderer drives the board and common table through E/Esc and
## real buttons. The picnic, starting crops, clock and arrival are seeded.
const Feast=World.AUTUMN_FEAST
const AUTUMN_DAY:=28
const OFFERINGS:=["radish","lettuce","wheat"]
const OFFERS:={"roots":"radish","greens":"lettuce","gold":"wheat"}

func own()->Dictionary:
	return app.session.snapshot.get(Feast.VIEW_KEY,{})

func public_round()->Dictionary:
	return app.session.snapshot.get(Feast.KEY,{})

func fit_feast()->void:
	if not check(is_instance_valid(app.modal),"Autumn feast modal is open"):return
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Feast modal fits the window")
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroll:
		var vertical:=scroll.get_v_scroll_bar()
		check(vertical.max_value<=vertical.page+1.0,"Feast modal fits without outer scrolling")

func board_open()->bool:
	if not await walk_to(Feast.BOARD):return false
	await key(KEY_E)
	return await press("AutumnFeastBoardLink")

func table_open(table:Vector2i)->bool:
	if not await walk_to(table):return false
	await key(KEY_E)
	return await press("AutumnFeastTableLink")

func grow_radish()->bool:
	var plots:=World.CHAPTER_ONE.starter_plot_free(world.state)
	if not check(not plots.is_empty(),"There is a free starter plot"):return false
	var plot:Vector2i=plots[0]
	if not await walk_to(plot):return false
	var suffix:=":autumn-native:"+size_tag
	for action:String in ["hoe","seed","water"]:
		var result:=world.act(player_id,action+suffix,action,plot,"radish" if action=="seed" else "")
		if not check(result.ok,"Planting action "+action+": "+str(result.message)):return false
	if not check(world.step(float(World.CROPS.radish.time)+2.0,true),"World tick grows the watered radish"):return false
	var harvest:=world.act(player_id,"harvest"+suffix,"harvest",plot)
	return check(harvest.ok and int(world.state.players[player_id].inventory.get("radish",0))==1,"Harvested crop is available for the feast")

func exercise()->void:
	world.state.erase(Feast.KEY)
	var person:Dictionary=world.state.players[player_id]
	person.erase(Feast.KEY)
	for crop:String in OFFERINGS:person.inventory[crop]=2
	person.inventory.radish=0
	person.inventory.radish_seed=1
	if not await grow_radish():return
	person=world.state.players[player_id]
	var start_bag:Dictionary=person.inventory.duplicate(true)
	var normal_table:Dictionary=world.state.community.duplicate(true)
	var table:=World.COMMUNITY.table_cell(world.state)
	refresh()
	await settle()
	if not await board_open():return
	fit_feast()
	await capture("01-feast-posting")
	if not await press("AutumnFeastStart"):return
	if not check(public_round().get("phase")=="collect" and own().get("joined",false),"The board begins a shared feast"):return
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	if not await table_open(table):return
	fit_feast()
	var serve_button:=button("AutumnFeastServe")
	check(serve_button!=null and serve_button.disabled,"Serving is locked while produce is missing")
	for item:String in OFFERINGS:
		if not await press("AutumnFeastGive_"+item):return
		check(int(world.state.players[player_id].inventory.get(item,0))==int(start_bag[item])-1,"Offering one "+item+" consumes exactly one")
	check(public_round().get("entries",{})==OFFERS,"The three actual crops are on the shared board")
	await capture("02-offerings-on-the-table")
	if not await press("AutumnFeastServe"):return
	check(public_round().get("phase")=="served" and own().get("completed",false),"Feast serves and records the first keepsake")
	var keepsake:=app.modal.find_child("AutumnFeastKeepsake",true,false) as Label
	check(keepsake!=null and keepsake.visible,"Personal keepsake is visible after serving")
	for crop:String in OFFERINGS:start_bag[crop]-=1
	check(world.state.players[player_id].inventory==start_bag and world.state.community==normal_table,"No other items or regular table meals changed")
	fit_feast()
	await capture("03-feast-served")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	app.toast.hide()
	app.view.camera=(Vector2(table)+HALF)*32-Vector2(root.size)/(2.0*app.view.view_zoom())
	app.view.queue_redraw()
	await capture("04-celebration-platter")

func run()->void:
	create_timer(85.0).timeout.connect(func():check(false,"Native test watchdog");finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../outputs/autumn-feast")
	DirAccess.make_dir_recursive_absolute(output)
	if not check(DisplayServer.get_name()!="headless","Native renderer"):finish();return
	path=OS.get_environment("TEMP").path_join("autumn-feast-native-%d.json"%OS.get_process_id())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if not check(app.session.host(0,"豐收宴旅人",path)==OK,"Start isolated native save"):finish();return
	world=app.session.world
	player_id=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	world.state.time=AUTUMN_DAY*World.WEATHER.DAY_SECONDS+480.0
	world.state.community={"table":World.COMMUNITY.cell_key(World.COMMUNITY.CANDIDATES[0])}
	var safe:=world.safe_arrival(Vector2(Feast.BOARD)+Vector2(0.5,1.5),player_id)
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
	print("AUTUMN_FEAST_SCENE checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
