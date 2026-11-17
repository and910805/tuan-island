extends SceneTree

const World=preload("res://scripts/world.gd")
const Duck=World.LIVESTOCK.Duck
const TOKEN:="river-duck-observer"
var checks:=0
var failures:=0

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var world:=World.new()
	world.add_player(TOKEN,"河畔飼養員")
	var player:Dictionary=world.state.players[TOKEN]
	player.x=Duck.SITE.x-0.45
	player.y=Duck.SITE.y+0.55
	player.inventory.feed=6
	expect(world.is_land(Duck.SITE) and not world.blocked(Vector2i(Vector2(player.x,player.y).floor())),
		"The feeder is reachable from the bank")
	expect(not world.act(TOKEN,"pre-picnic","livestock_feed",Duck.SITE,"duck").ok,"The picnic opens duck care")
	world.state.picnic=true
	for i in World.LIVESTOCK.BONUS_BOND:
		expect(world.act(TOKEN,"pet-%d"%i,"livestock_pet",Duck.SITE,"duck").ok,"Pet the duck")
		world.step(World.LIVESTOCK.PET_INTERVAL,true)
	expect(world.act(TOKEN,"feed","livestock_feed",Duck.SITE,"duck").ok,"Feed the duck")
	world.step(World.LIVESTOCK.DAY-1.0,true)
	expect(not world.act(TOKEN,"early","livestock_collect",Duck.SITE,"duck").ok,"The first duck egg takes a day")
	world.step(1.0,true)
	expect(world.act(TOKEN,"collect","livestock_collect",Duck.SITE,"duck").ok and int(player.inventory[Duck.EGG])==1,
		"Gather the first duck egg by hand")
	for i in World.LIVESTOCK.BONUS_INTERVAL-1:
		expect(world.act(TOKEN,"feed-next-%d"%i,"livestock_feed",Duck.SITE,"duck").ok,"Refill for the next day")
		world.step(World.LIVESTOCK.DAY,true)
	var station:Dictionary=world.state.livestock.duck
	expect(int(station.ready)==4 and int(station.ready_quality)==1,"At bond five a fourth production gives an extra premium egg")
	var collector:=World.LIVESTOCK.collector_cell("duck")
	var key:=World.key(collector)
	expect(not world.protected(collector) and not world.water(collector),"Duck collector site is on the buildable bank")
	player.x=collector.x-0.5
	player.inventory.animal_collector_kit=1
	var built:=world.act(TOKEN,"build-collector","build",collector,"animal_collector")
	expect(built.ok,"Build the duck collector through the normal tool: "+str(built.message))
	if not built.ok:
		quit(1)
		return
	player.inventory.egg_basket=1
	expect(world.act(TOKEN,"bind","collector_bind",collector,"duck").ok,"The standard machine supports ducks")
	world.step(1.0,true)
	expect(int(world.state.objects[key].collector_count)==4 and int(world.state.objects[key].collector_count_quality)==1,
		"The machine collects both grades")
	var path:="user://river-duck-%d.json"%Time.get_ticks_usec()
	world.save_path=path
	expect(world.save() and world.load_world(path),"The duck and collector survive reloading")
	player=world.state.players[TOKEN]
	expect(world.act(TOKEN,"take","collector_collect",collector).ok
		and int(player.inventory[Duck.EGG])==4 and int(player.inventory[Duck.QUALITY_EGG])==1,"The bag preserves grades")
	expect(World.MARKET.category_of(Duck.QUALITY_EGG)=="produce","Premium duck eggs are market produce")
	expect(Duck.swim_position(10.0,false)!=Duck.swim_position(11.0,false),"The duck moves while swimming")
	expect(Duck.swim_position(10.0,true)==Duck.swim_position(11.0,true),"Reduced motion keeps it still")
	for tick in range(30):
		expect(world.water(Vector2i(Duck.swim_position(float(tick),false).floor())),"The swimming route stays within water")
	if DisplayServer.get_name()!="headless":await verify_scene(world)
	var stall:=Vector2i(43,29)
	player.x=stall.x+0.5
	player.y=stall.y+0.5
	var coins:=int(player.coins)
	expect(world.act(TOKEN,"sell-quality","sell",stall,Duck.QUALITY_EGG).ok and int(player.coins)==coins+42
		and int(player.inventory[Duck.EGG])==4,"A quality duck egg sells for 42 without consuming ordinary eggs")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("RIVER_DUCK_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_scene(world:World)->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.world=world
	app.session.peers[1]=TOKEN
	app.session.own_id=TOKEN
	app.session.snapshot=world.region_snapshot("home")
	app.session.snapshot.time=510.0
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app._state_changed(app.session.snapshot,TOKEN)
	app._refresh_hud()
	await process_frame
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with("--duck-preview="):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--duck-preview="))==OK,"Capture the native scene")
	app._interact()
	await create_timer(0.27).timeout
	var buttons:Array=app.modal.find_children("*","Button",true,false) if is_instance_valid(app.modal) else []
	expect(buttons.any(func(node):return node.text=="摸摸花斑鴨"),"River bank interaction opens duck care")
	app.queue_free()
	await process_frame
