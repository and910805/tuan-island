extends SceneTree

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const SITE:=Vector2i(50,35)
const TOKEN:="rabbit-adopter"
const VIEWER:="companion-viewer"
var failures:=0
var checks:=0

func expect(ok:bool,description:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(description)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world:=World.new()
	world.add_player(TOKEN,"牧場")
	var player:Dictionary=world.state.players[TOKEN]
	player.x=SITE.x+0.5
	player.y=SITE.y+0.5
	expect(not world.act(TOKEN,"locked","rabbit_adopt",SITE).ok,"The picnic unlocks the adoption")
	world.state.picnic=true
	player.x-=8
	expect(not world.act(TOKEN,"far-away","rabbit_adopt",SITE).ok,"Adoption requires reaching the ranch")
	player.x=SITE.x+0.5
	expect(world.act(TOKEN,"adopt","rabbit_adopt",SITE).ok and player.companion_rabbit.following,"Adoption starts companionship")
	expect(not world.act(TOKEN,"adopt-again","rabbit_adopt",SITE).ok,"Each player can only adopt once")
	player.x-=8
	expect(world.act(TOKEN,"pet","rabbit_pet",SITE).ok and int(player.companion_rabbit.bond)==1,"A following rabbit can be petted away from the ranch")
	expect(not world.act(TOKEN,"pet-too-soon","rabbit_pet",SITE).ok,"Petting observes the cooldown")
	expect(world.act(TOKEN,"rest","rabbit_rest",SITE).ok,"A following rabbit can be sent to rest")
	expect(not world.act(TOKEN,"pet-resting-afar","rabbit_pet",SITE).ok,"A resting rabbit can only be petted at the ranch")
	var path:="user://rabbit-%d.json"%Time.get_ticks_usec()
	world.save_path=path
	expect(world.save() and world.load_world(path),"Rabbit data is saveable")
	player=world.state.players[TOKEN]
	expect(not player.companion_rabbit.following and int(player.companion_rabbit.bond)==1,"Resting and bond persist")
	expect(world.act(TOKEN,"follow","rabbit_follow",SITE).ok and player.companion_rabbit.following,"The rabbit can rejoin the player")
	expect(World.Rabbit.texture(0.0,true)==World.Rabbit.texture(2.2,true),"Reduced motion freezes the nose animation")
	expect(World.Rabbit.texture(0.0,true)!=World.Rabbit.texture(0.0,true,true),"The sleeping rabbit has a separate sprite")
	if DisplayServer.get_name()!="headless":
		await verify_scene(world)
	var cat_site:=World.Cat.site(world.state)
	expect(not world.act(TOKEN,"cat-far","cat_adopt",cat_site).ok,"Cat adoption requires the courtyard")
	player.x=cat_site.x+0.5
	player.y=cat_site.y+0.5
	expect(world.act(TOKEN,"cat-adopt","cat_adopt",cat_site).ok and player.companion_cat.following
		and not player.companion_rabbit.following,"Adopting the cat sends the rabbit to rest")
	expect(world.act(TOKEN,"cat-greet","cat_pet",cat_site).ok and player.companion_cat.last_play=="pet","The cat responds to greetings")
	verify_guest_reaction(world,"pet")
	expect(not world.act(TOKEN,"cat-yarn-cooldown","cat_yarn",cat_site).ok,"Yarn play respects the shared cooldown")
	world.step(World.Rabbit.PET_INTERVAL,true)
	expect(world.act(TOKEN,"cat-yarn","cat_yarn",cat_site).ok and player.companion_cat.last_play=="yarn","The cat plays with yarn")
	verify_guest_reaction(world,"yarn")
	expect(world.save() and world.load_world(path),"Both selected pet and cat interaction survive reloading")
	player=world.state.players[TOKEN]
	expect(int(player.companion_cat.bond)==2 and player.companion_cat.following and not player.companion_rabbit.following,
		"Only the cat is following after reload")
	if DisplayServer.get_name()!="headless":
		await verify_scene(world,true)
	expect(world.act(TOKEN,"rabbit-again","rabbit_follow",SITE).ok and not player.companion_cat.following
		and player.companion_rabbit.following,"Switching back to rabbit is atomic")
	var dog_site:=World.Dog.SITE
	player.x=dog_site.x+0.5
	player.y=dog_site.y+0.5
	expect(world.act(TOKEN,"dog-adopt","dog_adopt",dog_site).ok and player.companion_dog.following
		and not player.companion_rabbit.following and not player.companion_cat.following,"Adopting the dog sends both other pets to rest")
	expect(world.act(TOKEN,"dog-toy","dog_toy",dog_site).ok and player.companion_dog.last_play=="toy","Dog carries a toy after playing")
	expect(not world.act(TOKEN,"dog-repeat","dog_toy",dog_site).ok,"Toy interaction observes the cooldown")
	expect(world.save() and world.load_world(path),"Dog state saves and reloads")
	player=world.state.players[TOKEN]
	expect(player.companion_dog.following and player.companion_dog.last_play=="toy" and int(player.companion_dog.bond)==1,
		"The dog and its toy persist")
	if DisplayServer.get_name()!="headless":
		await verify_dog_photo(world)
	expect(world.act(TOKEN,"cat-after-dog","cat_follow",cat_site).ok and not player.companion_dog.following,
		"Switching to the cat safely dismisses the dog")
	await verify_fox(world,path)
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("COMPANION_RABBIT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_guest_reaction(world:World,reaction:String) -> void:
	if not world.state.players.has(VIEWER):world.add_player(VIEWER,"訪客")
	var session:=Session.new()
	session.world=world
	session.peers={1:VIEWER,2:TOKEN}
	session._send_snapshot(1)
	var visible_cat:Dictionary=session.snapshot.get("players",{}).get(Session._public_actor(TOKEN),{}).get(World.Cat.FIELD,{})
	var own_cat:Dictionary=world.state.players[TOKEN][World.Cat.FIELD]
	expect(visible_cat.get("following",false) and visible_cat.get("last_play")==reaction
		and visible_cat.get("last_pet")==own_cat.last_pet,"The visitor sees the cat's %s reaction"%reaction)
	expect(not visible_cat.is_empty() and not visible_cat.has("bond") and own_cat.has("bond"),"The cat's bond stays private without altering the saved record")
	session.free()

func verify_scene(world:World,cat:=false) -> void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.world=world
	app.session.peers[1]=TOKEN
	app.session.own_id=TOKEN
	app.session.snapshot=world.state.duplicate(true)
	app.view.update_snapshot(app.session.snapshot,TOKEN)
	app.playing=true
	app.menu.hide()
	app.hud.show()
	await process_frame
	var option:="--cat-preview=" if cat else "--rabbit-preview="
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with(option):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix(option))==OK,"Capture the native companion scene")
	if cat:app._interact()
	else:app._rabbit_menu()
	await create_timer(0.27).timeout
	var labels:Array=app.modal.find_children("*","Label",true,false)
	expect(labels.any(func(node):return node.text.contains("正在同行")),"Pet card shows the correct companion status")
	if cat:
		var buttons:Array=app.modal.find_children("*","Button",true,false)
		expect(buttons.any(func(node):return node.text=="一起玩毛線球"),"Cat card offers yarn play")
		for arg:String in OS.get_cmdline_user_args():
			if not arg.begins_with("--cat-perch-preview="):continue
			app._close_modal()
			var resting_snapshot:Dictionary=world.state.duplicate(true)
			resting_snapshot.players[TOKEN][World.Cat.FIELD].following=false
			app.view.update_snapshot(resting_snapshot,TOKEN)
			await process_frame
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--cat-perch-preview="))==OK,"Capture the cat resting on the old house window sill")
	app.queue_free()
	await process_frame

func verify_dog_photo(world:World) -> void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.world=world
	app.session.peers[1]=TOKEN
	app.session.own_id=TOKEN
	app.session.snapshot=world.state.duplicate(true)
	app.view.update_snapshot(app.session.snapshot,TOKEN)
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app._interact()
	await create_timer(0.25).timeout
	var buttons:Array=app.modal.find_children("*","Button",true,false) if is_instance_valid(app.modal) else []
	var photo_button:Button=null
	for button:Button in buttons:
		if button.text=="和小柴犬合照":photo_button=button
	expect(photo_button!=null,"The ranch interaction opens the dog photo control")
	var path:=preload("res://scripts/life_ui_almanac.gd").dog_photo_path(app)
	if photo_button!=null:
		photo_button.pressed.emit()
		await create_timer(0.3).timeout
		expect(FileAccess.file_exists(path),"Taking the photo saves it to this device")
		app._dog_menu()
		buttons=app.modal.find_children("*","Button",true,false)
		expect(buttons.any(func(node):return node.text=="翻看柴犬合照"),"The dog menu can reopen the photo")
		for arg:String in OS.get_cmdline_user_args():
			if arg.begins_with("--dog-preview=") and FileAccess.file_exists(path):
				expect(Image.load_from_file(path).save_png(arg.trim_prefix("--dog-preview="))==OK,"Export the dog photo preview")
	if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	app.queue_free()
	await process_frame

func verify_fox(world:World,path:String) -> void:
	var player:Dictionary=world.state.players[TOKEN]
	var site:=World.Fox.SITE
	player.region=World.Fox.REGION
	player.x=site.x+0.5
	player.y=site.y+0.5
	expect(not world.act(TOKEN,"fox-adopt-early","fox_adopt",site).ok,"Fox requires finishing both observations")
	expect(world.act(TOKEN,"fox-start","fox_track",site).ok and World.Fox.points(player).size()==3,"Starting the trail exposes two observation points")
	if DisplayServer.get_name()!="headless":await verify_fox_scene(world)
	for cell:Vector2i in World.Fox.TRACKS:
		expect(World.REGIONS.land(cell,World.Fox.REGION),"A track is on usable land")
		player.x=cell.x+0.5
		player.y=cell.y+0.5
		expect(world.act(TOKEN,"track-"+World.key(cell),"fox_track",cell).ok,"The player can inspect each track")
		expect(not world.act(TOKEN,"duplicate-"+World.key(cell),"fox_track",cell).ok,"The same track cannot advance the quest twice")
	player.x=site.x+0.5
	player.y=site.y+0.5
	expect(world.act(TOKEN,"fox-adopt","fox_adopt",site).ok and player.companion_fox.following and not player.companion_cat.following,
		"Finishing the trail lets the fox follow instead of the cat")
	expect(not world.act(TOKEN,"hint-in-grove","fox_hint",site).ok,"The coast hints require going home")
	player.region="home"
	player.x=World.SEAWEED_CELL.x+0.5
	player.y=World.SEAWEED_CELL.y+0.5
	expect(world.act(TOKEN,"hint-at-home","fox_hint",site).ok and World.Fox.home_clues(World,world.state).has(World.SEAWEED_CELL),
		"The fox reveals a currently available seaweed patch")
	if DisplayServer.get_name()!="headless":await verify_fox_scene(world,true)
	expect(world.act(TOKEN,"follow-clue",World.SEAWEED_POINT,World.SEAWEED_CELL).ok and int(player.inventory.seaweed)==1
		and not World.Fox.home_clues(World,world.state).has(World.SEAWEED_CELL),"Gathering seaweed removes the hint until regrowth")
	expect(world.save() and world.load_world(path) and int(world.state.players[TOKEN].fox_tracks)==7
		and world.state.players[TOKEN].companion_fox.following,"The trail and active fox persist")

func verify_fox_scene(world:World,map_view:=false) -> void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.world=world
	app.session.peers[1]=TOKEN
	app.session.own_id=TOKEN
	app.session.snapshot=world.region_snapshot("home" if map_view else World.Fox.REGION)
	if not map_view:
		app.session.snapshot.players[TOKEN].x+=1.0
		app.session.snapshot.time=480.0
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app._state_changed(app.session.snapshot,TOKEN)
	app._refresh_hud()
	if map_view:
		app._map_menu()
		await create_timer(0.27).timeout
	var option:="--fox-map-preview=" if map_view else "--fox-preview="
	await process_frame
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with(option):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix(option))==OK,"Capture the native fox scene")
	if not map_view:
		app._interact()
		await create_timer(0.27).timeout
		var labels:Array=app.modal.find_children("*","Label",true,false) if is_instance_valid(app.modal) else []
		expect(labels.any(func(node):return node.text=="已記錄 0／2 處"),"The visible fox opens the trail card")
	app.queue_free()
	await process_frame
