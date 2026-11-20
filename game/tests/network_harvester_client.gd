extends SceneTree

const Session = preload("res://scripts/session.gd")
const FarmFeedback = preload("res://scripts/farm_feedback.gd")
const TOKENS := {"alpha": "network-alpha-test", "beta": "network-beta-test"}
var session: Node
var parent: Node2D
var role := ""
var address := "127.0.0.1"
var port := 28551
var barrier := ""
var tls: TLSOptions
var failures := 0
var welcomed := false
var notices: Array[bool] = []
var replies: Dictionary = {}
var feedback := FarmFeedback.new()
var previous_snapshot: Dictionary = {}
var observed: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL " + role + " " + message)

func wait_until(condition: Callable, message: String) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	var met: bool = condition.call()
	expect(met, message)
	return met

func player_id(which: String) -> String:
	return String(TOKENS[which]).sha256_text().left(16)

func person(which: String) -> Dictionary:
	return session.snapshot.get("players", {}).get(player_id(which), {})

func mark(stage: String) -> bool:
	var file := FileAccess.open("%s-%s.%s" % [barrier, role, stage], FileAccess.WRITE)
	if file == null:
		expect(false, "write barrier " + stage)
		return false
	file.store_string(stage)
	file.close()
	return true

func both_marked(stage: String) -> bool:
	return FileAccess.file_exists(barrier + "-alpha." + stage) and FileAccess.file_exists(barrier + "-beta." + stage)

func connect_client() -> bool:
	welcomed = false
	feedback.reset()
	previous_snapshot = {}
	observed.clear()
	replies.clear()
	session = Session.new()
	parent.add_child(session)
	session.connected_world.connect(func(): welcomed = true)
	session.notice.connect(func(_message: String, success: bool): notices.append(success); print(role, ": ", _message))
	session.action_completed.connect(func(sequence: int, action: String, result: Dictionary):
		if action == "harvest_area": replies[sequence] = result.get("ok", false))
	session.changed.connect(on_snapshot)
	var connected: bool = session.join(address, port, role, "integration-key", tls) == OK
	expect(connected, "start connection")
	if not connected:
		return false
	return await wait_until(func(): return welcomed and not person(role).is_empty(), "receive own snapshot")

func on_snapshot(snapshot: Dictionary, _id: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	feedback.observe(previous_snapshot,snapshot,now)
	for which in TOKENS:
		var operation := feedback.active(player_id(which),now)
		if operation.get("kind") == "harvester":
			var starts: Dictionary = observed.get(which,{})
			starts[operation.started] = operation
			observed[which] = starts
	previous_snapshot = snapshot

func close_client() -> void:
	session.shutdown()
	get_multiplayer().multiplayer_peer = null
	parent.remove_child(session)
	session.queue_free()


func nine_harvested(which: String) -> bool:
	var crops: Dictionary = session.snapshot.get("crops", {})
	var center := 42 if which == "alpha" else 46
	for y in range(35, 38):
		for x in range(center - 1, center + 2):
			var crop: Dictionary = crops.get("%d,%d" % [x, y], {})
			if crop.get("owner") != player_id(which) or crop.get("kind") != "":return false
	return true

func exercise() -> void:
	if not await connect_client():return
	if not mark("ready") or not await wait_until(func():return both_marked("ready"),"both ready"):return
	if role=="alpha":
		var accepted: int = session.perform("harvest_area",Vector2i(42,36))
		if not await wait_until(func():return notices.size()==1,"first pass answered"):return
		expect(notices[0],"first pass accepted")
		await wait_until(func():return replies.get(accepted,false),"requester receives its confirmed harvest result")
	if not await wait_until(func():return nine_harvested("alpha"),"nine alpha plots arrive"):return
	if role=="beta":
		var refused: int = session.perform("harvest_area",Vector2i(42,36))
		if not await wait_until(func():return notices.size()==1,"overlap answered"):return
		expect(not notices[0] and int(person(role).inventory.charcoal)==3 and not person(role).inventory.has("radish"),"overlap rejected without any charge")
		await wait_until(func():return replies.get(refused,true)==false,"requester receives its refused harvest result")
		var deadline := Time.get_ticks_msec() + 2000
		while float(person(role).x) < 46.2 and Time.get_ticks_msec() < deadline:
			session.input_direction(Vector2.RIGHT)
			await create_timer(0.05).timeout
		session.input_direction(Vector2.ZERO)
		expect(float(person(role).x) >= 46.2, "move to owned plot center")
		var accepted: int = session.perform("harvest_area",Vector2i(46,36))
		if not await wait_until(func():return notices.size()==2,"owned pass answered"):return
		expect(notices[1],"beta can harvest own plots")
		await wait_until(func():return replies.get(accepted,false),"requester receives its own harvest result")
	if not await wait_until(func():return nine_harvested("beta"),"nine beta plots arrive"):return
	expect(int(person(role).inventory.charcoal)==2 and int(person(role).inventory.radish)==9,"one charcoal charged and nine radishes awarded")
	if not mark("finished") or not await wait_until(func():return both_marked("finished"),"both pass checks"):return
	for which in TOKENS:
		var events: Dictionary = observed.get(which,{})
		expect(events.size()==1 and events.values()[0].cells.size()==9 and events.values()[0].items.values().all(func(item):return item=="radish"),
			"observe one animation with nine radishes for "+which)
	expect(replies.size()==(1 if role=="alpha" else 2),"remote results remain private")
	close_client()
	await create_timer(0.4).timeout
	if not await connect_client():return
	expect(nine_harvested("alpha") and nine_harvested("beta") and int(person(role).inventory.charcoal)==2 and int(person(role).inventory.radish)==9,"reconnect retains plots and supplies")
	expect(observed.is_empty(),"reconnecting does not replay the earlier harvest")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			for which in TOKENS:
				if arg.trim_prefix("--profile=") == TOKENS[which]:
					role = which
		if arg.begins_with("--address="):
			address = arg.trim_prefix("--address=")
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--barrier="):
			barrier = arg.trim_prefix("--barrier=")
		if arg.begins_with("--ca="):
			var certificate := X509Certificate.new()
			if certificate.load(arg.trim_prefix("--ca=")) != OK:
				push_error("Cannot load harvester test CA")
				quit(1)
				return
			tls = TLSOptions.client(certificate)
	if role.is_empty() or barrier.is_empty():
		push_error("Harvester test requires an alpha or beta profile and a barrier")
		quit(1)
		return
	parent = Node2D.new()
	parent.name = "Island"
	root.add_child(parent)
	await exercise()
	if session != null and get_multiplayer().multiplayer_peer != null:
		close_client()
	print("HARVESTER_NETWORK_TEST role=%s failures=%d" % [role, failures])
	quit(0 if failures == 0 else 1)
