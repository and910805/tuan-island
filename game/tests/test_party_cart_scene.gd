extends "res://tests/test_spring_garden_scene.gd"

const Cart=World.PARTY_CART
const Art=preload("res://scripts/party_cart_art.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")

func shared()->Dictionary:
	return app.session.snapshot.get(Cart.KEY,{})

func reset_repair_fixture()->void:
	var person:Dictionary=world.state.players[player_id]
	world.state.erase(Cart.KEY)
	person.erase(World.RESIDENT_GOALS.RECORD_KEY)
	person.bonds={"bobo":{"points":6,"talk_day":-1,"gift_day":-1}}
	person.inventory.merge({"copper_ingot":4,"woodwork_parts":2},true)

func tick(seconds:float)->void:
	check(world.step(seconds,true),"World advance commits")
	refresh()
	await settle()

func center_on(cell:Vector2i)->void:
	app.view.camera=(Vector2(cell)+HALF)*32-Vector2(root.size)/(2.0*app.view.view_zoom())
	app.view.queue_redraw()

func open_at(cell:Vector2i,expected:String)->bool:
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	if not await walk_to(cell):return false
	await key(KEY_E)
	return check(is_instance_valid(app.modal) and app.modal.name=="PartyCartPanel" and app.modal.get_meta("partycart_point")==expected,
		"E opens %s, current focus %s" % [expected,app.view.interaction_focus()])

func fit_panel()->void:
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Panel fits")
	var scroller:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroller:
		var bar:=scroller.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Route and actions fit without scrolling")

func depart(from:int,arrival:int,shot:="")->bool:
	if from==Cart.JUNCTION:
		if not await open_at(Cart.STOPS[from],"junction"):return false
		if not await press("PartyCartPush"):return false
		await key(KEY_ESCAPE)
	else:
		if is_instance_valid(app.modal):await key(KEY_ESCAPE)
		if not await walk_to(Cart.STOPS[from]):return false
		await key(KEY_E)
		check(not is_instance_valid(app.modal),"One key pushes the cart without interrupting play")
	if not check(shared().stop==from and shared().to==arrival,"One push starts specified segment"):return false
	await tick(0.75)
	var at:=Art.cart_position(app.session.snapshot,false,float(world.state.time))
	check(at!=Vector2(Cart.STOPS[from])+HALF and at!=Vector2(Cart.STOPS[arrival])+HALF,"Cart appears between safe stops while rolling")
	check(Art.cart_position(app.session.snapshot,true,float(world.state.time))==Vector2(Cart.STOPS[arrival])+HALF,"Reduced motion shows a stable destination")
	if not shot.is_empty():
		center_on(Vector2i(at.floor()))
		await capture(shot)
	await tick(1.10)
	return check(shared().stop==arrival and shared().to==-1,"Cart automatically brakes at next stop")

func exercise()->void:
	reset_repair_fixture()
	app._select_tool("water")
	world.switch_region(World.REGIONS.JINGUASHI)
	if not await walk_to(Cart.SURFACE_PORTAL):return
	center_on(Cart.SURFACE_PORTAL)
	await capture("01-jinguashi-entrance")
	check(app.view.interaction_focus()=="party_cart_portal","The surface portal has its own hint")
	check(not world.party_cart_unlocked() and Art.portal_locked(app.session.snapshot),"Fresh world: the portal is locked and the snapshot says so")
	await key(KEY_E)
	await settle()
	check(world.player_region(player_id)==World.REGIONS.JINGUASHI and app.session.snapshot.get("region_id","")==World.REGIONS.JINGUASHI,"Locked portal keeps the player in Jinguashi")
	await capture("01a-locked-location-hint")
	var bobo:Vector2i=World.bond_place(world.state,"bobo")[1]
	# Position at the quest giver to exercise the real choice and hand-in controls.
	var person:Dictionary=world.state.players[player_id]
	var previous:=Vector2(person.x,person.y)
	person.x=bobo.x+0.5
	person.y=bobo.y+1.5
	refresh()
	await settle()
	Tasks.bond_goal(app,"bobo",2)
	await settle()
	if not await press("BondGoalOption_siding"):return
	await capture("01b-bobo-repair-choice")
	if not await press("BondGoalDo"):return
	var inventory:Dictionary=world.state.players[player_id].inventory
	check(int(inventory.get("copper_ingot",0))==0 and int(inventory.get("woodwork_parts",0))==0,"Repair pays the displayed materials")
	Tasks.bond_goal(app,"bobo",2)
	await settle()
	check(is_instance_valid(app.modal) and app.modal.find_child("BoboCartUnlockLine",true,false)!=null,"Repair page names the unlocked entrance")
	await capture("01c-bobo-repair-complete")
	await key(KEY_ESCAPE)
	person.x=previous.x
	person.y=previous.y
	if not await walk_to(Cart.SURFACE_PORTAL):return
	refresh()
	await settle()
	check(world.party_cart_unlocked() and app.session.snapshot.get("party_cart_unlocked",false)==true and not Art.portal_locked(app.session.snapshot),"Bobo stage 2 unlocks the portal in the snapshot")
	await key(KEY_M)
	check(is_instance_valid(app.map_view),"Map opens at the cart portal")
	await capture("01d-unlocked-local-map")
	await key(KEY_ESCAPE)
	await key(KEY_E)
	await settle()
	check(world.player_region(player_id)==Cart.REGION,"Unlocked portal enters the gallery through the real key path")
	world.switch_region(Cart.REGION)
	refresh()
	await settle()
	if not check(app._in_cart_gallery() and not app.preview_toolbar.visible,"Entering gallery hides farm tools"):return
	check(app.sound.music.scene_id==Cart.REGION,"Entering starts the gallery BGM")
	var player:Dictionary=world.state.players[player_id]
	var bag:Dictionary=player.inventory.duplicate(true)
	var coins:int=player.coins
	check(not world.act(player_id,"test-gallery-build-"+size_tag,"build",Vector2i(16,19),"floor").ok,"Building cannot modify a gallery tile")
	check(not world.act(player_id,"test-gallery-plant-"+size_tag,"hoe",Vector2i(16,19)).ok,"Farming cannot modify a gallery tile")
	world.switch_region(Cart.REGION)
	if not await open_at(Cart.SIGN,"sign"):return
	fit_panel()
	await capture("02-route-card")
	if not await press("PartyCartStart"):return
	var round_id:int=shared().round
	for crate in range(Cart.CRATES):
		if not await depart(Cart.START,Cart.JUNCTION,"03-cart-moving" if crate==0 else ""):return
		if crate==1:
			if not await open_at(Cart.STOPS[Cart.JUNCTION],"junction"):return
			if not await press("PartyCartSwitch"):return
			check(shared().branch=="south","Switch stays latched to south")
		var side:="north" if crate==0 else "south"
		if crate<2:
			if not await open_at(Cart.STOPS[Cart.JUNCTION],"junction"):return
			var push:=button("PartyCartPush")
			check(push!=null and push.disabled,"Blocked branch cannot push")
			if crate==0:
				fit_panel()
				await capture("04-junction")
			if not await open_at(Cart.ROCKS[side],side):return
			if not await press("PartyCartClear"):return
			check(not shared().rocks[side],"Clear selected branch")
		check(shared().branch==side,"Selected line persists across crates")
		var branch_stop:=Cart.NORTH_STOP if side=="north" else Cart.SOUTH_STOP
		if not await depart(Cart.JUNCTION,branch_stop):return
		if not await depart(branch_stop,Cart.MERGE):return
		if not await depart(Cart.MERGE,Cart.DOCK):return
		if not await walk_to(Cart.STOPS[Cart.DOCK]):return
		await key(KEY_E)
		check(not is_instance_valid(app.modal),"One key unloads at the docking stop")
		check(shared().delivered==crate+1 and shared().score==2*(crate+1) and shared().round==round_id,"Only unloading awards points")
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	if not check(shared().phase=="results" and player.inventory==bag and player.coins==coins,"All three delivered with no changes to normal inventory"):return
	world.switch_region(World.REGIONS.HOME)
	check(world.state.regions[Cart.REGION]==World.REGIONS.fresh(),"Gallery layers remain empty")
	world.switch_region(Cart.REGION)
	if not await open_at(Cart.SIGN,"sign"):return
	fit_panel()
	await capture("05-results")
	await key(KEY_ESCAPE)
	if not await walk_to(Cart.EXIT):return
	await key(KEY_E)
	refresh()
	await settle()
	check(world.player_region(player_id)==World.REGIONS.JINGUASHI and app.preview_toolbar.visible and app.selected=="water","Exit restores original tool without changing the surface")

func run()->void:
	create_timer(160.0).timeout.connect(func():check(false,"Native suite watchdog");finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../outputs/party-cart")
	DirAccess.make_dir_recursive_absolute(output)
	if not check(DisplayServer.get_name()!="headless","Native renderer"):finish();return
	path=OS.get_environment("TEMP").path_join("party-cart-native-%d.json"%OS.get_process_id())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if not check(app.session.host(0,"台車旅人",path)==OK,"Start isolated native save"):finish();return
	world=app.session.world
	player_id=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	world.state.time=490.0
	world.state.players[player_id].region=World.REGIONS.JINGUASHI
	world.state.players[player_id].x=27.5
	world.state.players[player_id].y=25.5
	app.playing=true
	refresh()
	await settle()
	for window_size:Vector2i in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=window_size
		size_tag="%dx%d"%[window_size.x,window_size.y]
		await exercise()
	finish()

func finish()->void:
	if finished:return
	finished=true
	if is_instance_valid(app):app.session.shutdown()
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("PARTY_CART_SCENE checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
