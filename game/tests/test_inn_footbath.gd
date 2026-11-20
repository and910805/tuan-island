extends SceneTree

const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const KIND:=Industry.FOOT_BATH
const SEAT:=World.RESIDENT_GOALS.MASTER_BENCH_SEAT
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if ok:return
	failures+=1
	push_error(message)

func travel(world:World,token:String,station:String,destination:String) -> bool:
	var origin:=world.player_region(token)
	var cell:Vector2i=World.TRANSIT.points(origin)[station].cell
	var person:Dictionary=world.state.players[token]
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	var result:=world.act(token,"bath-trip-"+origin+"-"+destination,"transit",cell,destination)
	var arrived:bool=result.ok and world.player_region(token)==destination
	expect(arrived,"Travel %s to %s: %s"%[origin,destination,result.message])
	return arrived

func capture(app,file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		var arrival:Control=app.hud.get_node_or_null("TravelArrival")
		if arrival:arrival.hide()
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func run() -> void:
	var app=Main.instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800) if "--wide" in OS.get_cmdline_user_args() else Vector2i(1024,640)
	await process_frame
	var path:="user://footbath-%d.json"%OS.get_process_id()
	if app.session.host(0,"旅舍工匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	var at:=Vector2i(41,36)
	var far:=at+Vector2i(2,1)
	var near:=at+Vector2i.DOWN
	var key:=World.key(at)
	person.x=41.5
	person.y=38.5
	person.inventory.stone=24
	person.inventory.clay=8
	person.inventory.hardwood=8
	person.mine_energy=67
	app.session._send_snapshot(1)
	expect(not world.act(token,"early-bath","build",at,KIND).ok,"Server requires the crack repair before construction")
	person=world.state.players[token]
	var resident:=World.RESIDENT_BOND.SPRING_CELL
	var springs:=World.WARM_SPRINGS
	# Begin after the opening picnic. Gift and building materials are supplied by the fixture.
	world.state.picnic=true
	if not travel(world,token,"ferry","toucheng") or not travel(world,token,"rail",springs.REGION):
		quit(1)
		return
	person=world.state.players[token]
	person.x=springs.BATH_ENTRANCE.x+0.5
	person.y=springs.BATH_ENTRANCE.y+0.5
	expect(not world.act(token,"closed-public-bath",springs.BATH_ACTION,springs.BATH_ENTRANCE).ok,"The cracked public bath cannot be used")
	app.session._send_snapshot(1)
	app.WanganUI.dismiss(app)
	await process_frame
	await capture(app,"inn-public-bath-closed.png")
	person.x=resident.x+0.5
	person.y=resident.y+1.5
	person.inventory.ginger=3
	person.inventory.stone=36
	person.inventory.clay=16
	expect(not person.get("bonds",{}).has("nuannuan"),"The trip starts with no relationship record")
	var greeting:=world.act(token,"bath-greeting","resident_talk",resident,"nuannuan")
	expect(greeting.ok,"Greet Nuannuan in Jiaoxi: "+str(greeting.message))
	var first_gift:=world.act(token,"bath-gift-first","resident_gift",resident,"nuannuan:ginger")
	person=world.state.players[token]
	expect(first_gift.ok and person.get("bonds",{}).get("nuannuan",{}).get("points",0)==4,"The greeting and a favorite gift earn four points")
	var repeat_gift:=world.act(token,"bath-gift-same-day","resident_gift",resident,"nuannuan:ginger")
	person=world.state.players[token]
	expect(repeat_gift.ok and person.inventory.get("ginger",0)==1 and person.bonds.nuannuan.points==4,"A repeated gift is accepted but earns no additional points on the same day")
	expect(world.step(World.WEATHER.DAY_SECONDS,true),"Advance the world to the next day")
	var next_gift:=world.act(token,"bath-gift-next-day","resident_gift",resident,"nuannuan:ginger")
	person=world.state.players[token]
	expect(next_gift.ok and person.get("bonds",{}).get("nuannuan",{}).get("points",0)==7 and person.inventory.get("ginger",0)==0,"The next day's gift crosses the six-point threshold")
	app.session._send_snapshot(1)
	Tasks.bond_goal(app,"nuannuan",2)
	await process_frame
	var finish:=app.modal.find_child("BondGoalDo",true,false) as Button
	expect(finish!=null and finish.disabled,"The story cannot be turned in before all three marks")
	var early:=world.act(token,"early-cracks",World.RESIDENT_GOALS.ACTION,resident,"nuannuan:2::201")
	expect(not early.ok,"A supplied permutation does not replace field observation")
	app._close_modal()
	person=world.state.players[token]
	var expected_mask:=0
	for index in [2,0,1]:
		var site:Vector2i=springs.CRACK_SITES[index]
		person.x=site.x+0.5
		person.y=site.y+0.5
		app.session._send_snapshot(1)
		await process_frame
		if index==2:await capture(app,"01-crack-field-marker.png")
		app._interact()
		expected_mask|=1<<index
		expect(int(app.session.snapshot.own_inn_cracks)==expected_mask,"This real interaction records only crack %d"%index)
		if index==2:
			var partial:=World.new()
			expect(partial.load_world(path) and int(partial.state.players[token].get(springs.CRACK_KEY,0))==expected_mask,"Partial survey survives a save reload")
			expect(not world.act(token,"repeat-crack",springs.CRACK_ACTION,site).ok,"Already marked crack cannot count twice")
			person=world.state.players[token]
	person.x=resident.x+0.5
	person.y=resident.y+1.5
	app.session._send_snapshot(1)
	Tasks.bond_goal(app,"nuannuan",2)
	await process_frame
	await capture(app,"02-ready-to-repair.png")
	finish=app.modal.find_child("BondGoalDo",true,false) as Button
	expect(finish!=null and not finish.disabled,"All three marked cracks allow submission")
	if finish:finish.pressed.emit()
	person=world.state.players[token]
	expect(World.RESIDENT_GOALS.done(person,"nuannuan").has(2) and person.inventory.clay==8 and person.inventory.stone==24,
		"The real story submission consumes 8 clay and 12 stone and grants the unlock")
	expect(app.session.snapshot.get(springs.BATH_KEY,false),"The repair opens the public bath on the shared snapshot")
	expect((int(app.session.snapshot.island_news.completed) & (4<<World.ISLAND_NOTES.PROJECTS.size()))!=0,"The repaired bath appears on the island news snapshot")
	Tasks.bond_goal(app,"nuannuan",2)
	await process_frame
	var pattern:=app.modal.find_child("NuannuanFootBathPattern",true,false) as Button
	expect(pattern!=null,"The completed event offers the bath drawing")
	if pattern:pattern.pressed.emit()
	await process_frame
	app._close_modal()
	for i in range(5):
		var guest_id:="spring-guest-%d"%i
		world.add_player(guest_id,"泉邊訪客")
		var visitor:Dictionary=world.state.players[guest_id]
		visitor.region=springs.REGION
		visitor.x=springs.BATH_ENTRANCE.x+0.5
		visitor.y=springs.BATH_ENTRANCE.y+0.5
		var sit:=world.act(guest_id,"public-soak",springs.BATH_ACTION,springs.BATH_ENTRANCE)
		expect(sit.ok==(i<4),"Public seats are shared and a fifth visitor must wait")
		if i<4:expect(Vector2(visitor.x,visitor.y)==Vector2(springs.BATH_ORIGIN)+springs.BATH_SEATS[i],"Public visitors receive different seats")
	world.move_player("spring-guest-1",Vector2.DOWN,0.1)
	person.x=springs.BATH_ENTRANCE.x+0.5
	person.y=springs.BATH_ENTRANCE.y+0.5
	app.session._send_snapshot(1)
	app._interact()
	expect(person.get(springs.REST_SEAT_KEY)==springs.BATH_ACTION,"The arrival interaction reuses the newly freed seat")
	app.session.peers[2]="spring-guest-0"
	app.session.peers[3]="spring-guest-2"
	app.session.peers[4]="spring-guest-3"
	app.session._send_snapshot(1)
	await capture(app,"inn-public-bath.png")
	for id in [2,3,4]:app.session.peers.erase(id)
	world.move_player(token,Vector2.DOWN,0.1)
	if not travel(world,token,"rail","toucheng") or not travel(world,token,"street",World.REGIONS.HOME):
		quit(1)
		return
	person=world.state.players[token]
	person.x=41.5
	person.y=38.5
	app.session._send_snapshot(1)
	app.session.perform("build",at,KIND)
	expect(person.inventory.stone==0 and person.inventory.clay==0 and person.inventory.hardwood==0,"The planned construction recipe is charged")
	for offset:Vector2i in Industry.station_cells(KIND):
		var cell:=at+offset
		expect(world.blocked(cell) and World.station_anchor(world.state.objects,cell)==at,"Each footprint tile is solid and belongs to the same bath")
	app._interact()
	var seat_button:=app.modal.find_child("FootBathSeat0",true,false) as Button if is_instance_valid(app.modal) else null
	expect(seat_button!=null and not seat_button.disabled,"The real interaction presents available seats")
	if seat_button:seat_button.pressed.emit()
	expect(person.get(SEAT)=={"cell":key,"side":0} and person.mine_energy==67,"Sitting keeps exploration energy unchanged")
	for i in [1,2,3,4]:
		var name:="bath-guest-%d"%i
		world.add_player(name,"訪客 %d"%i)
		var guest:Dictionary=world.state.players[name]
		guest.x=person.x
		guest.y=person.y
		var choice:=world.act(name,"first","inn_pool_sit",near,str(i%4))
		expect(choice.ok==(i<4),"Four players can sit and the fifth cannot take an occupied seat")
		if i<4:app.session.peers[i+1]=name
	app.session._send_snapshot(1)
	app.WanganUI.dismiss(app)
	app._refresh_hud()
	await capture(app,"inn-footbath.png")
	for i in [2,3,4]:app.session.peers.erase(i)
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.players["bath-guest-3"].get(SEAT,{}).get("side")==3,
		"The primary save retains the multi-cell bath and fourth seat")
	expect(loaded.state.get(springs.BATH_KEY,false) and not loaded.state.players["spring-guest-0"].has(springs.REST_SEAT_KEY),
		"The shared pool remains open after reload and active seats are transient")
	var old_path:=path+".before-public-bath"
	var old_save:=FileAccess.open(old_path,FileAccess.WRITE)
	loaded.state.erase(springs.BATH_KEY)
	loaded.state.players[token].erase(springs.CRACK_KEY)
	old_save.store_string(JSON.stringify(loaded.state))
	old_save.close()
	var migrated:=World.new()
	expect(migrated.load_world(old_path) and migrated.state.get(springs.BATH_KEY,false),"An older completed story opens the public bath on load")
	DirAccess.remove_absolute(old_path)
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,token,Rect2i(at,Vector2i(3,2)),"旅舍泡腳池",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces.size()==1,"The full bath is captured as one piece")
	expect(world.act(token,"remove","remove",far).ok and not world.blocked(far)
		and person.inventory.stone==24 and person.inventory.clay==8 and person.inventory.hardwood==8,"Removing at the far edge refunds one recipe")
	for id in [token,"bath-guest-1","bath-guest-2","bath-guest-3"]:
		expect(not world.state.players[id].has(SEAT),"Dismantling releases a seat")
	if design.ok:
		var rotated_origin:=at+Vector2i.RIGHT
		var visitor:Dictionary=world.state.players["bath-guest-1"]
		visitor.inventory.stone=24
		visitor.inventory.clay=8
		visitor.inventory.hardwood=8
		var locked_quote:=world.quote_blueprint("bath-guest-1",design.blueprint,rotated_origin,1)
		var locked_build:=world.apply_blueprint("bath-guest-1","a".repeat(32),design.blueprint,rotated_origin,1,locked_quote.get("hash",""))
		expect(not locked_build.ok and not locked_quote.ok and not locked_quote.problems.is_empty()
			and "池邊的裂縫" in locked_quote.problems[0].reason
			and world.state.players["bath-guest-1"].inventory.stone==24,"A shared blueprint cannot bypass the personal unlock or charge materials")
		var quote:=world.quote_blueprint(token,design.blueprint,rotated_origin,1)
		var built:=world.apply_blueprint(token,"b".repeat(32),design.blueprint,rotated_origin,1,quote.hash)
		expect(built.ok and Industry.is_vertical(world.state.objects.get(World.key(rotated_origin),{}))
			and world.state.objects.get(World.key(rotated_origin+Vector2i(1,2)),{}).get("bath_part")==5,"Rotated blueprint builds a two-by-three bath: "+str(built.message))
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("INN_FOOTBATH_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
