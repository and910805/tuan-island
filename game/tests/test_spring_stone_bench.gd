extends SceneTree

const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const Goals=World.RESIDENT_GOALS
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
	var path:="user://stone-bench-%d.json"%OS.get_process_id()
	if app.session.host(0,"暖泉工匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	var region:=World.WARM_SPRINGS.REGION
	var at:=Vector2i(27,26)
	var end:=at+Vector2i.RIGHT
	var key:=World.key(at)
	person.region=region
	person.x=27.5
	person.y=27.5
	person.inventory.stone=8
	person.inventory.hardwood=8
	world.add_player("visitor","來泡茶的朋友")
	world.add_player("third","另一位訪客")
	for visitor in ["visitor","third"]:
		var guest:Dictionary=world.state.players[visitor]
		guest.region=region
		guest.x=28.5
		guest.y=27.5
	app.session._send_snapshot(1)
	expect(not world.act(token,"protect-clearing","build",at,"floor").ok,"Other construction remains restricted at the spring")
	app.session.perform("build",at,Goals.STONE_BENCH)
	var objects:Dictionary=world.state.regions[region].objects
	expect(objects.get(key,{}).get("type")==Goals.STONE_BENCH and objects.get(World.key(end),{}).get("bench_end",false)
		and person.inventory.stone==0 and person.inventory.hardwood==0,"Build two cells with the exact recipe in Jiaoxi")
	if not objects.has(key):
		app.session.shutdown()
		quit(1)
		return
	world.switch_region(region)
	expect(world.blocked(at) and world.blocked(end),"Both bench cells have collision")
	world.switch_region(World.REGIONS.HOME)
	app._interact()
	var sit:=app.modal.find_child("MasterBenchSeat_0",true,false) as Button
	expect(sit!=null,"The real bench interaction offers a left-hand seat")
	if sit:sit.pressed.emit()
	expect(person.get(Goals.MASTER_BENCH_SEAT,{}).get("side")==0,"The player sits on the left")
	expect(world.act("visitor","right",Goals.MASTER_BENCH_SIT,end).ok
		and world.state.players.visitor.get(Goals.MASTER_BENCH_SEAT,{}).get("side")==1,"A friend can sit on the right at the same time")
	expect(not world.act("third","occupied",Goals.MASTER_BENCH_SIT,end).ok,"A third player cannot take the occupied seat")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.players[token].has(Goals.MASTER_BENCH_SEAT)
		and loaded.state.players.visitor.has(Goals.MASTER_BENCH_SEAT),"The primary save preserves both seats in the highlands")
	app.session.peers[2]="visitor"
	app.session._send_snapshot(1)
	app._refresh_hud()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await create_timer(1.9).timeout
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("spring-stone-bench.png"))==OK,"Capture both seated players")
	app.session.peers.erase(2)
	expect(world.act(token,"remove-end","remove",end).ok and world.state.regions[region].objects.is_empty()
		and person.inventory.stone==8 and person.inventory.hardwood==8,"Removal from the far end refunds once")
	expect(not person.has(Goals.MASTER_BENCH_SEAT) and not world.state.players.visitor.has(Goals.MASTER_BENCH_SEAT),"Removing the bench releases both seats")
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SPRING_STONE_BENCH_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
