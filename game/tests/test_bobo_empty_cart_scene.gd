extends "res://tests/test_spring_garden_scene.gd"
## Native Windows regression. Bobo friendship and the region arrivals are prepared. In Jinguashi
## we walk to the six stops and back to Bobo, using the live UI/session for the quest and reward.

const Cart=preload("res://scripts/bobo_empty_cart.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const Route=preload("res://scripts/ore_route.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const KIND:="keepsake_bobo_cart"
const KIT:="keepsake_bobo_cart_kit"

func stand_near(site:Vector2i)->void:
	var p:Dictionary=world.state.players[player_id]
	var position:=Vector2(site)+HALF
	for offset:Vector2i in [Vector2i.ZERO,Vector2i.DOWN,Vector2i.UP,Vector2i.RIGHT,Vector2i.LEFT]:
		var candidate:=Vector2(site+offset)+HALF
		if world.can_stand(candidate):
			position=candidate
			break
	p.x=position.x
	p.y=position.y
	await frame_site(site)

func frame_site(site:Vector2i)->void:
	refresh()
	preload("res://scripts/travel_ui.gd").dismiss_arrival(app)
	app.view.camera=(Vector2(site)+HALF)*32-Vector2(root.size)/(2.0*app.view.view_zoom())
	app.view.queue_redraw()
	await settle()

func walk_near(site:Vector2i)->bool:
	world.switch_region(world.player_region(player_id))
	var start:=Vector2i(point().floor())
	var queue:Array[Vector2i]=[start]
	var came_from:Dictionary={start:start}
	var index:=0
	while index<queue.size():
		var cell:=queue[index]
		index+=1
		if Vector2(cell-site).length()<=1.0:
			var path_cells:Array[Vector2i]=[cell]
			while cell!=start:
				cell=came_from[cell]
				path_cells.push_front(cell)
			for i in range(1,path_cells.size()):
				var motion:=Vector2(path_cells[i]-path_cells[i-1])
				for step in 4:world.move_player(player_id,motion,0.25/3.6)
				if not check(point().distance_to(Vector2(path_cells[i])+HALF)<0.001,"Walk through %s"%path_cells[i]):return false
			await frame_site(site)
			return true
		for direction:Vector2i in OFFSETS:
			var next:=cell+direction
			if came_from.has(next):continue
			var open:=true
			for step in range(1,5):
				if not world.can_stand(Vector2(cell)+HALF+Vector2(direction)*float(step)*0.25):open=false;break
			if open:
				came_from[next]=cell
				queue.append(next)
	return check(false,"No walkable approach to %s"%site)

func journey()->void:
	var p:Dictionary=world.state.players[player_id]
	p.region=World.REGIONS.JINGUASHI
	p.bonds={"bobo":{"points":24,"talk_day":-1,"gift_day":-1}}
	p.erase(Cart.FIELD)
	p.erase(Goals.RECORD_KEY)
	p.erase(Goals.KEEPSAKE_KEY)
	p.inventory.erase(KIT)
	world.switch_region(p.region)
	var giver:Vector2i=World.bond_place(world.state,"bobo")[1]
	await stand_near(giver)
	var opening_coins:int=p.coins
	Tasks.bond_goal(app,"bobo",4)
	await settle()
	if not await press("BondGoalOption_home"):return
	var early_finish:=button("BondGoalDo")
	check(early_finish!=null and early_finish.disabled,"Cannot complete before pushing the empty cart")
	await capture("01-before-pushing")
	if not await press("BoboEmptyCartStart"):return
	if is_instance_valid(app.modal):await key(KEY_ESCAPE)
	if not check(Cart.stage(app.session.snapshot)==1,"Start puts the empty cart at the pit mouth"):return
	for index in range(Cart.STOPS.size()-1):
		if not await walk_near(Cart.STOPS[index]):return
		if index==1:await capture("02-empty-cart-on-rails")
		await key(KEY_E)
		if not check(Cart.stage(app.session.snapshot)==index+2,"Interact pushes stop %d exactly once"%(index+1)):return
		if index==0:
			var elapsed:float=app.view.elapsed
			var reduced:bool=app.view.reduced_motion
			var started:float=app.view.ore_cart_push_started
			check(is_finite(started),"Story push starts the rail animation")
			app.view.elapsed=started+app.view.ore_cart_travel_seconds(2)*0.5
			app.view.reduced_motion=false
			var midpoint:Vector2=app.view.ore_cart_position(2)
			check(midpoint!=Vector2(Cart.STOPS[0]) and midpoint!=Vector2(Cart.STOPS[1]),"Cart is rendered between the two stops")
			app.view.reduced_motion=true
			check(app.view.ore_cart_position(2)==Vector2(Cart.STOPS[1]),"Reduced motion uses the confirmed stop")
			app.view.elapsed=elapsed
			app.view.reduced_motion=reduced
	check(not Cart.active(app.session.snapshot) and Route.stage(app.session.snapshot)==0,"Delivered story cart frees normal ore hauling")
	check(p.coins==opening_coins,"Pushing the keepsake cart grants no wages")
	if not await walk_near(giver):return
	Tasks.bond_goal(app,"bobo",4)
	await settle()
	if not await press("BondGoalOption_home"):return
	if not await press("BondGoalDo"):return
	check(Goals.done(p,"bobo").get(4,"")=="home" and int(p.inventory.get(KIT,0))==1,"Selected inscription and one display are recorded")
	Tasks.bond_goal(app,"bobo",4)
	await settle()
	await capture("03-inscription-and-display")
	await key(KEY_ESCAPE)
	var display:=Vector2i(39,34)
	p.region=World.REGIONS.HOME
	world.switch_region(p.region)
	await stand_near(display+Vector2i(2,0))
	app.session.perform("build",display,KIND)
	await settle()
	check(world.state.objects.get(World.key(display),{}).get("type","")==KIND and int(p.inventory.get(KIT,0))==0,
		"Place the earned display in the home region")
	app.view.camera=(Vector2(display)+HALF)*32-Vector2(root.size)/(2.0*app.view.view_zoom())
	app.view.queue_redraw()
	await capture("04-grandfathers-display")
	world.state.objects.erase(World.key(display))

func run()->void:
	create_timer(100.0).timeout.connect(func():check(false,"Native suite timed out");finish())
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../work/bobo-n034/native")
	DirAccess.make_dir_recursive_absolute(output)
	if not check(DisplayServer.get_name()!="headless","Native renderer required"):finish();return
	path=OS.get_environment("TEMP").path_join("bobo-empty-cart-scene-%d.json"%OS.get_process_id())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if not check(app.session.host(0,"礦車旅人",path)==OK,"Start isolated native save"):finish();return
	world=app.session.world
	player_id=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	world.state.time=490.0
	app.playing=true
	preload("res://scripts/wangan_opening_ui.gd").dismiss(app)
	for window_size:Vector2i in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=window_size
		size_tag="%dx%d"%[window_size.x,window_size.y]
		await journey()
	finish()

func finish()->void:
	if finished:return
	finished=true
	if is_instance_valid(app):app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("BOBO_EMPTY_CART_SCENE checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
