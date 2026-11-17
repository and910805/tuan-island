extends SceneTree
const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const IslandMap=preload("res://scripts/island_map.gd")
const KIND:=World.INN_TEA_TABLE
const TEA:=World.INN_TEA_ITEM
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if ok:return
	failures+=1
	push_error(message)

func run() -> void:
	var app=Main.instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640)
	await process_frame
	var path:="user://inn-tea-%d.json"%OS.get_process_id()
	if app.session.host(0,"暖泉島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	var at:=Vector2i(41,36)
	var key:=World.key(at)
	person.x=41.5
	person.y=37.5
	person.inventory.hardwood=8
	person.inventory.clay=3
	person.inventory[TEA]=3
	app.session._send_snapshot(1)
	app._build_menu()
	await process_frame
	var furniture:=app.modal.find_child("BuildTab2",true,false) as Button
	if furniture:furniture.pressed.emit()
	var slot:=app.modal.find_child("BuildSlot_inn_tea_table_2",true,false) as Button
	expect(slot!=null and slot.is_visible_in_tree(),"The tea table is listed in the furniture page")
	app._close_modal()
	app.session.perform("build",at,KIND)
	var table:Dictionary=world.state.objects.get(key,{})
	expect(table.get("type")==KIND and world.blocked(at) and person.inventory.hardwood==0 and person.inventory.clay==0,
		"The one-cell table uses the exact planned recipe")
	for count in [1,2]:
		app._interact()
		var put:=app.modal.find_child("InnTeaPlace",true,false) as Button
		expect(put!=null and not put.disabled,"The owner can use an empty cup spot")
		if put:put.pressed.emit()
		expect(world.state.objects[key].items.get(TEA)==count and person.inventory[TEA]==3-count,"Displaying transfers exactly one existing tea")
	expect(not world.act(token,"full","inn_tea_place",at).ok and person.inventory[TEA]==1,"The two display spots cannot overflow")
	expect(not world.act(token,"full-remove","remove",at).ok,"A table with cups cannot be dismantled")
	world.add_player("guest","訪客")
	var guest:Dictionary=world.state.players.guest
	guest.x=person.x
	guest.y=person.y
	expect(not world.act("guest","take","inn_tea_take",at).ok,"A visitor cannot take the owner's cups")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects.get(key,{}).get("items",{}).get(TEA)==2,
		"Both cups persist in the primary save")
	person.x=40.5
	app.session._send_snapshot(1)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("inn-tea-table.png"))==OK,"Capture the two cups")
	for count in [1,0]:
		expect(world.act(token,"take-%d"%count,"inn_tea_take",at).ok and int(world.state.objects[key].items.get(TEA,0))==count,"The owner takes one existing cup")
	expect(person.inventory[TEA]==3 and not world.act(token,"empty","inn_tea_take",at).ok,"No additional tea is created")
	var stove:=at+Vector2i.LEFT
	var stove_key:=World.key(stove)
	world.state.objects[stove_key]={"type":"stove","owner":token,"items":{}}
	person.inventory.ginger=1
	person.inventory.sugar=1
	app.session._send_snapshot(1)
	app.session.perform("queue_cook",stove,World.GINGER_TEA)
	expect(person.inventory.ginger==0 and person.inventory.sugar==0 and int(person.inventory.get(World.GINGER_TEA,0))==0,
		"The normal stove queue charges one ginger and one sugar")
	world.step(59.0,true)
	expect(not world.act(token,"early-ginger-claim","claim_cook",stove).ok,"Ginger tea takes the full 60 seconds")
	world.step(1.1,true)
	expect(world.act(token,"ginger-claim","claim_cook",stove).ok and person.inventory.get(World.GINGER_TEA)==2,
		"Two cups can be claimed from the stove")
	expect(world.act(token,"ginger-display","inn_tea_place",at,World.GINGER_TEA).ok and world.act(token,"mist-display","inn_tea_place",at,TEA).ok
		and not world.act(token,"full-mixed","inn_tea_place",at,World.GINGER_TEA).ok,"The display shares its two spots between both kinds of tea")
	person.x=41.5
	app.session._send_snapshot(1)
	app._interact()
	var take_ginger:=app.modal.find_child("InnGingerTake",true,false) as Button
	expect(take_ginger!=null and not take_ginger.disabled,"The table UI recognizes the displayed ginger tea")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("ginger-tea-display.png"))==OK,"Capture both kinds of tea")
	app._close_modal()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects[key].items=={TEA:1,World.GINGER_TEA:1},
		"Both kinds of displayed tea survive reload")
	expect(world.act(token,"take-ginger","inn_tea_take",at,World.GINGER_TEA).ok and world.act(token,"take-mist","inn_tea_take",at,TEA).ok,
		"Each tea can be retrieved by type")
	expect(world.act(token,"remove","remove",at).ok and person.inventory.hardwood==8 and person.inventory.clay==3,"Empty table removal refunds materials")
	expect(not world.act(token,"outside-drink","drink_ginger_tea",Vector2i.ZERO).ok and person.inventory[World.GINGER_TEA]==2,
		"Trying to restore mine energy outside a mine consumes nothing")
	person.region="mine_1"
	person.mine_energy=73
	expect(world.act(token,"drink","drink_ginger_tea",Vector2i.ZERO).ok and person.mine_energy==93
		and person.inventory[World.GINGER_TEA]==1,"Drinking an existing cup restores 20 exploration energy")
	person.mine_energy=100
	expect(not world.act(token,"full-drink","drink_ginger_tea",Vector2i.ZERO).ok and person.inventory[World.GINGER_TEA]==1,
		"Drinking at full energy keeps the remaining cup")
	person.region=World.WARM_SPRINGS.REGION
	person.x=29.5
	person.y=26.5
	world.state.time=3.0*World.WEATHER.DAYS_PER_SEASON*World.WEATHER.DAY_SECONDS+600.0
	app.session._send_snapshot(1)
	app._refresh_hud()
	expect("冷泉一帶寒涼" in app.region_subtitle.text,"The winter cold-pool approach displays the cold hint")
	app._inventory()
	var bag=app.modal
	bag.select_item(World.GINGER_TEA)
	expect(bag.eat_rice_ball.visible and not bag.eat_rice_ball.disabled,"The backpack allows tea for warmth at full energy")
	bag.eat_rice_ball.pressed.emit()
	expect(person.inventory[World.GINGER_TEA]==0 and is_equal_approx(float(person.ginger_warm_until)-float(world.state.time),480.0),
		"The real backpack action consumes one cup and grants 480 world seconds")
	app._close_modal()
	app._refresh_hud()
	expect("保暖" in app.region_subtitle.text and "寒涼" not in app.region_subtitle.text,"Warmth replaces the cold-pool hint")
	expect(loaded.load_world(path) and not loaded.recovered_from_backup
		and loaded.state.players[token].get("ginger_warm_until")==person.ginger_warm_until,"The warmth deadline survives save and reload")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("ginger-tea-warmth.png"))==OK,"Capture the active warmth hint")
	world.step(479.0,true)
	app.session._send_snapshot(1)
	app._refresh_hud()
	expect("0:01" in app.region_subtitle.text,"Warmth is still active in the last second")
	world.step(1.0,true)
	app.session._send_snapshot(1)
	app._refresh_hud()
	expect("寒涼" in app.region_subtitle.text,"The cold hint returns when the eight minutes expire")
	var springs=World.WARM_SPRINGS
	var outside:=IslandMap.springs_sites(false,false)
	expect(outside.size()==6 and outside[0][0]==World.REGIONS.exit_cell(springs.REGION)
		and outside[2][0]==springs.INN_DOOR and str(outside[3][1]).ends_with("待修"),"Highland map identifies the return, inn and repair site")
	expect(outside[4][0]==springs.POOLS.spring.water.get_center() and outside[5][0]==springs.POOLS.upland.water.get_center(),
		"Both fishing sites match the actual pools")
	await capture_map(app,"jiaoxi-outdoor")
	person.x=springs.INN_DOOR.x+0.5
	person.y=springs.INN_DOOR.y+0.5
	app.session.perform(springs.INN_PORTAL,springs.INN_DOOR)
	expect(springs.in_inn(person) and IslandMap.springs_sites(true,false)[0][0]==springs.INN_EXIT,"Inn map uses the real indoor exit after entering")
	await capture_map(app,"jiaoxi-inn")
	person.region="home"
	person.x=41.5
	person.y=37.5
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("INN_TEA_TABLE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func capture_map(app,name:String)->void:
	app._map_menu()
	await process_frame
	await process_frame
	expect(app.map_view is IslandMap and app.modal.get_global_rect().size.x<=root.size.x,"Local map fits the compact game window")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await create_timer(0.25).timeout
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(name+".png"))==OK,"Captured "+name)
	app._close_modal()
