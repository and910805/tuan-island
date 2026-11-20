extends SceneTree

const World = preload("res://scripts/world.gd")
const Session = preload("res://scripts/session.gd")
const CLIENTS := 8
const WOOD := 48
const SEEDS := 500
const KEY := "local-soak-room"
const WALK_SPAN := 0.85
const ARRIVAL_RADIUS := 0.13
const MINIMUM_TRAVEL := 0.2

var directory: String
var port: int
var player: int
var session: Node
var island: Node
var assignment: Dictionary
var responses: Array[Dictionary] = []
var joined := false
var lost := false
var rounds := 0
var harvests := 0
var reconnects := 0
var snapshots := 0
var keyframes := 0
var delta_frames := 0
var last_frame := 0
var last_snapshot_ms := -1
var largest_snapshot_gap_ms := 0
var workload_start_ms := 0
var joins := 0
var last_peer := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		quit(2)
		return
	directory = args[1]
	port = int(args[2])
	island = Node.new()
	island.name = "Island"
	root.add_child(island)
	match args[0]:
		"seed": quit(0 if seed_world() else 1)
		"server": await serve(int(args[3]) if args.size()>3 else 60)
		"client":
			player = int(args[3])
			var ok: bool = await play(float(args[4]), float(args[5]))
			if not ok:
				print("SOAK_CLIENT_EXIT player=%d peer=%d unix=%.3f early=true rounds=%d snapshots=%d lost=%s" %
					[player, last_peer, Time.get_unix_time_from_system(), rounds, snapshots, lost])
			quit(0 if ok else 1)
		"verify": quit(0 if verify_world() else 1)
		_: quit(2)

func token(index: int) -> String:
	return "mixed-soak-fixture-%02d" % index

func file(name: String) -> String:
	return directory.path_join(name)

func write_result(name: String, value: Dictionary) -> bool:
	var output := FileAccess.open(file(name + ".tmp"), FileAccess.WRITE)
	if output == null: return false
	var written := output.store_string(JSON.stringify(value))
	output.close()
	return written and DirAccess.rename_absolute(file(name + ".tmp"), file(name)) == OK

func fail(reason: String) -> bool:
	push_error("SOAK_FAILURE player=%d peer=%d unix=%.3f round=%d lost=%s %s" % [player, last_peer, Time.get_unix_time_from_system(), rounds, lost, reason])
	return false

func peer_id() -> int:
	# The numeric multiplayer peer id is not a credential; the token is never logged.
	if not is_instance_valid(session) or session.multiplayer == null or session.multiplayer.multiplayer_peer == null:
		return 0
	return session.multiplayer.get_unique_id()

func fixture_clear(world: World, tile: Vector2i) -> bool:
	var key := World.key(tile)
	return not world.water(tile) and not world.protected(tile) and world.resource(tile).is_empty() and not world.state.objects.has(key) and not world.state.crops.has(key)

func seed_world() -> bool:
	var world := World.new()
	world.save_path = file("world.json")
	var plots := {}
	var index := 1
	for y in range(21, 53, 5):
		for x in range(19, 52, 5):
			var center := Vector2i(x, y)
			var crop := center + Vector2i.UP
			var chest := center + Vector2i.LEFT
			var floor_tile := center + Vector2i.DOWN
			if not [center, crop, chest, floor_tile, center + Vector2i.RIGHT].all(func(tile): return fixture_clear(world, tile)): continue
			var feet:=Vector2(center)+Vector2(0.5,0.5)
			if not [0.0,0.25,0.5,0.75,1.0].all(func(fraction):return world.can_stand(feet+Vector2.RIGHT*WALK_SPAN*fraction)): continue
			var actor := token(index)
			world.add_player(actor, "測試島民%d" % index, feet)
			var inventory: Dictionary = world.state.players[actor].inventory
			inventory.wood = WOOD
			inventory.radish_seed = SEEDS
			world.state.objects[World.key(chest)] = {"type":"chest", "owner":actor, "items":{}}
			# The fixture roof keeps the same crop test valid through all four seasons.
			world.state.roofs[World.key(crop)] = {"type":"greenhouse_roof", "owner":actor, "items":{}}
			plots[str(index)] = {"center": World.key(center), "crop": World.key(crop), "chest": World.key(chest), "floor": World.key(floor_tile)}
			index += 1
			if index > CLIENTS: break
		if index > CLIENTS: break
	if plots.size() != CLIENTS or not world.save(): return fail("could not save eight fixtures")
	var reopened := World.new()
	return reopened.load_world(file("world.json")) and write_result("plots.json", plots)

func serve(diagnostic_fps:int) -> void:
	session = Session.new()
	island.add_child(session)
	var error: int = session.host(port, "", file("world.json"), KEY, "127.0.0.1", true, "websocket", false)
	if error != OK:
		quit(1)
		return
	session.multiplayer.peer_connected.connect(func(peer:int): log_peer("connected",peer))
	session.multiplayer.peer_disconnected.connect(func(peer:int): log_peer("disconnected",peer))
	var previous:=Time.get_ticks_msec()
	var profile_gaps:=OS.get_environment("T090_PROFILE")=="1"
	var previous_physics_frame:=Engine.get_physics_frames()
	var previous_world_time:=float(session.world.state.time)
	var previous_log_ms:=0
	var next_report:=previous+5000
	var next_stop_check:=previous
	var largest_gap:=0
	var cap_from:=0
	var resumed:=false
	while true:
		await process_frame
		var now:=Time.get_ticks_msec()
		var gap:=now-previous
		largest_gap=maxi(largest_gap,gap)
		previous=now
		if profile_gaps:
			var physics_frame:=Engine.get_physics_frames()
			var world_time:=float(session.world.state.time)
			var last_log_ms:=previous_log_ms
			previous_log_ms=0
			if gap>=250:
				print("SOAK_SERVER_FRAME_GAP %s"%JSON.stringify({
					"unix":Time.get_unix_time_from_system(),"gap_ms":gap,
					"physics_ticks":physics_frame-previous_physics_frame,
					"world_delta":world_time-previous_world_time,"previous_log_ms":last_log_ms,
					"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
					"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0}))
				previous_log_ms=Time.get_ticks_msec()-now
			previous_physics_frame=physics_frame
			previous_world_time=world_time
		if now>=next_stop_check:
			if FileAccess.file_exists(file("stop")):break
			next_stop_check=now+500
			if diagnostic_fps!=60 and cap_from==0 and FileAccess.file_exists(file("start")):
				cap_from=now+15000
		if cap_from>0 and now>=cap_from and not resumed:
			var cap:=60 if now>=cap_from+10000 else diagnostic_fps
			if Engine.max_fps!=cap:
				Engine.max_fps=cap
				print("SOAK_HOST_FRAME_CAP unix=%.3f fps=%d"%[Time.get_unix_time_from_system(),cap])
			resumed=cap==60
		if now<next_report:continue
		var log_started:=Time.get_ticks_msec() if profile_gaps else 0
		print("SOAK_SERVER_HEARTBEAT %s"%JSON.stringify({"unix":Time.get_unix_time_from_system(),
			"peers":session.peers.size(),"accepting":session.accepting,"storage_paused":session.storage_paused,
			"last_saved":session.world.last_saved_at,"world_seconds":session.world.state.time,
			"save_error":session.world.save_error,"step_error":session.world.step_error,"max_frame_gap_ms":largest_gap}))
		if profile_gaps:previous_log_ms+=Time.get_ticks_msec()-log_started
		next_report=now+5000
		largest_gap=0
	quit(0 if session.shutdown() else 1)

func log_peer(event:String,peer:int) -> void:
	print("SOAK_SERVER_PEER event=%s peer=%d unix=%.3f"%[event,peer,Time.get_unix_time_from_system()])

func connect_room() -> bool:
	if is_instance_valid(session):
		session.shutdown()
		session.free()
		await create_timer(1.2).timeout
	joined = false
	lost = false
	last_frame = 0
	last_snapshot_ms = -1
	largest_snapshot_gap_ms = 0
	session = Session.new()
	island.add_child(session)
	session.profile.token = token(player)
	session.connected_world.connect(func(): joined = true)
	session.disconnected_world.connect(func():
		lost=true
		print("SOAK_DISCONNECT player=%d unix=%.3f workload_seconds=%.3f round=%d snapshots=%d"%
			[player,Time.get_unix_time_from_system(),-1.0 if workload_start_ms==0 else (Time.get_ticks_msec()-workload_start_ms)/1000.0,rounds,snapshots]))
	session.changed.connect(observe_snapshot)
	session.notice.connect(func(message: String, ok: bool): responses.append({"ok":ok, "message":message}))
	var address := "ws://127.0.0.1:%d" % port
	if session.join(address, port, "測試島民%d" % player, KEY) != OK: return fail("join failed")
	if not await wait_for(func(): return joined and not own().is_empty()): return fail("no admitted snapshot")
	if last_frame<=0:return fail("first joined snapshot has no full WebSocket baseline")
	last_peer = peer_id()
	print("SOAK_PEER event=%s player=%d peer=%d unix=%.3f" % ["join" if joins == 0 else "rejoin", player, last_peer, Time.get_unix_time_from_system()])
	joins += 1
	return true

func observe_snapshot(_data:Dictionary,_own:String) -> void:
	snapshots+=1
	var now:=Time.get_ticks_msec()
	if last_snapshot_ms>=0:largest_snapshot_gap_ms=maxi(largest_snapshot_gap_ms,now-last_snapshot_ms)
	last_snapshot_ms=now
	var frame:int=session._received_snapshot_frame
	if frame<=0:return
	if frame!=last_frame:keyframes+=1
	else:delta_frames+=1
	last_frame=frame

func wait_for(condition: Callable, seconds := 8.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call():
		if lost or Time.get_ticks_msec() >= until: return false
		await create_timer(0.05).timeout
	return true

func own() -> Dictionary:
	return session.snapshot.get("players", {}).get(session.own_id, {})

func bag() -> Dictionary:
	return own().get("inventory", {})

func act(kind: String, tile: String, extra := "") -> bool:
	responses.clear()
	session.perform(kind, World.cell(tile), extra)
	if not await wait_for(func(): return not responses.is_empty()): return fail("no reply for " + kind)
	if not responses[0].ok: return fail("%s: %s" % [kind, responses[0].message])
	return true

func verify_values() -> bool:
	var box: Dictionary = session.snapshot.get("objects", {}).get(assignment.chest, {})
	return bag().get("wood", 0) == WOOD and bag().get("radish", 0) == harvests and box.get("type") == "chest" and box.get("items", {}).get("wood", 0) == 0 and not session.snapshot.get("ground", {}).has(assignment.floor)

func farming() -> bool:
	var crop: Dictionary = session.snapshot.crops[assignment.crop]
	if crop.get("kind", "") == "radish" and float(crop.growth) >= float(World.CROPS.radish.time):
		if not await act("harvest", assignment.crop): return false
		harvests += 1
		if not await wait_for(func(): return bag().get("radish", 0) == harvests): return fail("harvest count mismatch")
		crop = session.snapshot.crops[assignment.crop]
	if crop.get("kind", "").is_empty():
		if not await act("seed", assignment.crop, "radish"): return false
		if not await wait_for(func(): return session.snapshot.crops[assignment.crop].get("kind") == "radish"): return fail("plant did not appear")
		crop = session.snapshot.crops[assignment.crop]
	if not crop.get("wet", false) and not await act("water", assignment.crop): return false
	return true

func play(duration: float, reconnect_every: float) -> bool:
	var plots = JSON.parse_string(FileAccess.get_file_as_string(file("plots.json")))
	assignment = plots[str(player)]
	if not await connect_room(): return false
	if not write_result("ready-%d.json" % player, {"snapshot":session.own_id}): return fail("cannot record readiness")
	if not await wait_for(func(): return FileAccess.file_exists(file("start")) and int(session.snapshot.get("room_population", 0)) == CLIENTS, 35.0): return fail("eight peers did not start")
	if not await act("hoe", assignment.crop): return false
	if not await wait_for(func(): return session.snapshot.get("crops", {}).has(assignment.crop)): return fail("tilled plot missing")
	var started := Time.get_ticks_msec()
	workload_start_ms=started
	var next_reconnect := reconnect_every + player * 2.0
	while Time.get_ticks_msec() - started < duration * 1000.0:
		var ago := (Time.get_ticks_msec() - started) / 1000.0
		if ago >= next_reconnect:
			var previous_id: String = session.own_id
			var expected_seeds: int = bag().get("radish_seed", 0)
			if not await connect_room(): return false
			if session.own_id != previous_id or bag().get("radish_seed", 0) != expected_seeds or not verify_values(): return fail("reconnect lost player progress")
			reconnects += 1
			next_reconnect += reconnect_every
			print("SOAK_RECONNECT player=%d elapsed=%.1f snapshots=%d" % [player, ago, snapshots])
		if not await mixed_round(): return false
		rounds += 1
		if rounds == 1 or rounds % 10 == 0:
			print("SOAK_PROGRESS player=%d rounds=%d harvests=%d reconnects=%d snapshots=%d" % [player, rounds, harvests, reconnects, snapshots])
		await create_timer(4.0 + player * 0.07).timeout
	if rounds == 0 or harvests == 0 or reconnects == 0: return fail("missing gameplay or reconnect coverage")
	var result := {"seconds":(Time.get_ticks_msec() - started) / 1000.0,"rounds":rounds,"harvests":harvests,"reconnects":reconnects,"snapshots":snapshots,"keyframes":keyframes,"delta_frames":delta_frames,"seeds":bag().get("radish_seed",0)}
	session.shutdown()
	return write_result("result-%d.json" % player, result)

func mixed_round() -> bool:
	var center := Vector2(World.cell(assignment.center)) + Vector2(0.5, 0.5)
	var target := center + Vector2(WALK_SPAN if rounds % 2 == 0 else 0.0, 0)
	var position := Vector2(float(own().x), float(own().y))
	var origin := position
	var started := Time.get_ticks_msec()
	var deadline := started + 5000
	var inputs:=0
	var start_snapshots:=snapshots
	var longest_wait_ms:=0
	largest_snapshot_gap_ms=0
	if player==1 and rounds==2 and OS.get_environment("T090_WALK_SIGNAL")=="1":
		print("SOAK_WALK_ARMED unix=%.3f"%Time.get_unix_time_from_system())
	while position.distance_to(target) > ARRIVAL_RADIUS and not lost and Time.get_ticks_msec() < deadline:
		var sent_at:=Time.get_ticks_msec()
		session.input_direction(((target - position) * 1.5).limit_length(0.55))
		inputs+=1
		await create_timer(0.11).timeout
		longest_wait_ms=maxi(longest_wait_ms,Time.get_ticks_msec()-sent_at)
		position = Vector2(float(own().x), float(own().y))
	if lost:return fail("connection lost during movement from %s toward %s"%[origin,target])
	session.input_direction(Vector2.ZERO)
	var remaining:=position.distance_to(target)
	var travelled:=position.distance_to(origin)
	if remaining>ARRIVAL_RADIUS or travelled<MINIMUM_TRAVEL:
		var now:=Time.get_ticks_msec()
		print("SOAK_WALK_DIAG player=%d round=%d unix=%.3f duration_ms=%d inputs=%d snapshots=%d longest_timer_ms=%d snapshot_age_ms=%d max_snapshot_gap_ms=%d"%[
			player,rounds,Time.get_unix_time_from_system(),now-started,inputs,snapshots-start_snapshots,longest_wait_ms,now-last_snapshot_ms if last_snapshot_ms>=0 else -1,largest_snapshot_gap_ms])
		return fail("movement from %s toward %s stopped at %s (remaining=%.4f, travelled=%.4f)" % [origin,target,position,remaining,travelled])
	if not await act("deposit_exact", assignment.chest, "wood:5"): return false
	if not await wait_for(func(): return bag().get("wood", 0) == WOOD - 5): return fail("deposit mismatch")
	if not await act("withdraw_exact", assignment.chest, "wood:5"): return false
	if not await act("build", assignment.floor, "floor"): return false
	if not await wait_for(func(): return session.snapshot.ground.get(assignment.floor, {}).get("type") == "floor"): return fail("floor placement missing")
	if not await act("remove", assignment.floor): return false
	if not await farming(): return false
	return await wait_for(verify_values) or fail("room inventory or construction mismatch")

func verify_world() -> bool:
	var world := World.new()
	if not world.load_world(file("world.json")) or world.recovered_from_backup: return fail("final primary save could not load")
	var plots = JSON.parse_string(FileAccess.get_file_as_string(file("plots.json")))
	if world.state.players.size() != CLIENTS: return fail("unexpected saved player count")
	for index in range(1, CLIENTS + 1):
		var report = JSON.parse_string(FileAccess.get_file_as_string(file("result-%d.json" % index)))
		if not report is Dictionary: return fail("missing client report")
		var map: Dictionary = plots[str(index)]
		var resident: Dictionary = world.state.players[token(index)]
		var inventory: Dictionary = resident.inventory
		var box: Dictionary = world.state.objects[map.chest]
		if inventory.get("wood", 0) != WOOD or inventory.get("radish", 0) != report.harvests or inventory.get("radish_seed", 0) != report.seeds or box.items.get("wood", 0) != 0 or world.state.ground.has(map.floor):
			return fail("persisted progress mismatch for client %d" % index)
		var plot: Dictionary = world.state.crops.get(map.crop, {})
		if report.seeds + report.harvests != SEEDS - 1 or plot.get("kind") != "radish" or plot.get("owner") != token(index) or not resident.get("collection", {}).get("crops", {}).get("radish", false):
			return fail("planting and discovery records do not match client %d" % index)
	return write_result("verified.json", {"players":CLIENTS,"world_seconds":world.state.time})
