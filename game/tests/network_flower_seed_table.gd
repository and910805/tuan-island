extends "res://tests/network_flowers.gd"

const RECIPES := {"alpha":"bluebell","beta":"orange_blossom"}

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3 or not read_secrets():
		quit(2)
		return
	role=args[0]
	phase=test_phase()
	handoff=args[2]
	create_timer(30).timeout.connect(func():finish(false,"seed-table watchdog"))
	if role=="server":
		await host_fixture(int(args[1]))
	else:
		var island:=Node.new()
		root.add_child(island)
		session=Session.new()
		island.add_child(session)
		session.profile.token=tokens[role]
		session.changed.connect(_on_changed)
		session.notice.connect(_on_notice)
		session.action_completed.connect(_on_completed)
		var port:=int(args[1])
		var joined:=session.join("ws://127.0.0.1:%d"%port,port,role,OS.get_environment("FN_ROOM_KEY"))
		if not check(joined==OK,"started room-key WebSocket connection"):return
		var both:=await until(func():return online_max>=2 and not me().is_empty(),JOIN_WAIT)
		if not check(both and peer_class()=="WebSocketMultiplayerPeer","two real clients joined"):return
		if await exercise_table():finish(true,"")

func test_phase()->String:
	return "seed-table"

func host_fixture(port:int) -> void:
	var save_path:=handoff.path_join("world.json")
	var world:=World.new()
	world.save_path=save_path
	world.state.board=true
	world.state.picnic_materials={"soup":2,"bread":1}
	world.state.picnic=true
	world.state.community={"table":k(TABLE)}
	world.state.chapter_one={"shipped":true,"watered":true,"harvests":{},"starter_claims":{}}
	world.switch_region(Flower.REGION)
	var stand:=Vector2(Flower.SEED_TABLE)+Vector2(0.5,1.5)
	if not check(world.can_stand(stand),"fixture stand beside seed table"):return
	for who in RECIPES:
		var token:String=tokens[who]
		world.add_player(token,who)
		var person:Dictionary=world.state.players[token]
		person.region=Flower.REGION
		person.x=stand.x
		person.y=stand.y
		for stop in ["maokong","yingge",Flower.REGION]:
			person.travel_book.visited[stop]=true
		person.inventory={RECIPES[who]:3}
		var tea:Dictionary=Tea.FRESH.duplicate(true)
		tea.intro=true
		tea.potter=true
		tea.reused=true
		tea.reuse_count=1
		tea.trials={"jar":true,"fiber":true}
		tea.tea_discussed=true
		tea.comparison_complete=true
		world.state.tea_ceramics.players[token]=tea
		var record:Dictionary=Flower.FRESH.duplicate(true)
		record.letter=true
		record.intro=true
		record.planted[RECIPES[who]]=true
		record.harvested[RECIPES[who]]=4
		world.state.flower_nursery.players[token]=record
	world.switch_region("home")
	if not check(world.save(),"isolated fixture saved"):return
	var island:=Node.new()
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	var code:=session.host(port,"QA",save_path,OS.get_environment("FN_ROOM_KEY"),"127.0.0.1",true,"websocket")
	if not check(code==OK,"dedicated session reloaded fixture, result %d"%code):return
	print("SEED_TABLE_SERVER_READY")
	var advance_path:=handoff.path_join("advance")
	var ready:=await until(func():return FileAccess.file_exists(advance_path),18)
	if not check(ready,"both clients attempted early collection"):return
	for who in RECIPES:
		var record:=Flower.own_record(session.world.state,tokens[who])
		if not check(record.saving.get("kind")==RECIPES[who],"independent pending job on server for "+who):return
	if not check(session.world.step(Flower.SAVE_SECONDS,true),"advanced real world clock past due time"):return
	print("SEED_TABLE_CLOCK_ADVANCED")
	var done_path:=handoff.path_join("done")
	var done:=await until(func():return FileAccess.file_exists(done_path),12)
	if not check(done,"both clients completed"):return
	if not check(session.shutdown(),"server saved and shut down normally"):return
	var loaded:=World.new()
	if not check(loaded.load_world(save_path) and not loaded.recovered_from_backup,"reopened final primary save"):return
	for who in RECIPES:
		var token:String=tokens[who]
		var kind:String=RECIPES[who]
		var actual:Dictionary=loaded.state.players[token].inventory
		var record:=Flower.own_record(loaded.state,token)
		if not check(ints(actual)=={kind:1,Flower.SEEDS[kind]:1} and record.saved.has(kind) and record.saving.is_empty(),"persisted exact inventory and claim for "+who):return
	session=null
	finish(true,"")

func exercise_table()->bool:
	var kind:String=RECIPES[role]
	var seed_id:String=Flower.SEEDS[kind]
	expect_inv={kind:3}
	expect_coins=coins()
	if not check(inv_ok() and own_record().saving.is_empty(),"own fixture inventory and idle table"):return false
	if not await barrier("start",true):return false
	var job:=await act_notice("flower_save",Flower.SEED_TABLE,kind)
	expect_inv={kind:1}
	if not check(job.get("ok")==true and inv_ok() and own_record().saving.get("kind")==kind,"both starts charge two flowers and report only the player's own job"):return false
	if not await refused("collect before due","flower_save_take",Flower.SEED_TABLE,"","留種台上沒有完成的工作。",false):return false
	if not await barrier("advance",true):return false
	var claim:=await act_notice("flower_save_take",Flower.SEED_TABLE)
	expect_inv[seed_id]=1
	if not check(claim.get("ok")==true and inv_ok() and own_record().saving.is_empty(),"each claim returns one seed and clears only its job"):return false
	if not await refused("claim a second time","flower_save_take",Flower.SEED_TABLE,"","留種台上沒有完成的工作。",false):return false
	if not await refused("one flower is below the recipe","flower_save",Flower.SEED_TABLE,kind,"留種需要 2 份%s。"%Flower.NAMES[kind],false):return false
	return check(violation.is_empty(),"snapshot privacy held")
