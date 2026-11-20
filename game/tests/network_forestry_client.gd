extends SceneTree

const Session = preload("res://scripts/session.gd")
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
	session = Session.new()
	parent.add_child(session)
	session.connected_world.connect(func(): welcomed = true)
	session.notice.connect(func(_message: String, success: bool): notices.append(success); print(role, ": ", _message))
	var connected: bool = session.join(address, port, role, "integration-key", tls) == OK
	expect(connected, "start connection")
	if not connected:
		return false
	return await wait_until(func(): return welcomed and not person(role).is_empty(), "receive own snapshot")

func close_client() -> void:
	session.shutdown()
	get_multiplayer().multiplayer_peer = null
	parent.remove_child(session)
	session.queue_free()


func exercise() -> void:
	if not await connect_client(): return
	var station:=Vector2i(41,34)
	if role=="beta":
		for action in ["toggle_forester","collect_forester","unload_forester"]:
			session.perform(action,station)
		if not await wait_until(func(): return notices.size()>=3,"foreign requests answered"):return
		expect(notices==[false,false,false],"foreign forestry operations denied")
	if not mark("denied") or not await wait_until(func(): return both_marked("denied"),"both ready"):return
	if role=="alpha":
		session.perform("collect_forester",station)
		session.perform("collect_forester",station)
		session.perform("load_forester",station,"charcoal")
		session.perform("toggle_forester",station)
		if not await wait_until(func(): return notices.size()>=4,"owner requests answered"):return
		expect(notices==[true,false,true,true],"owner gets one payout and can load and enable")
		if not await wait_until(func():
			var tree:Dictionary=session.snapshot.get("forest",{}).get("41,32",{})
			return not tree.is_empty() and not tree.mature,"station replants"):return
	if not mark("done") or not await wait_until(func(): return both_marked("done"),"all completed"):return
	close_client()
	await create_timer(0.4).timeout
	if not await connect_client():return
	var device:Dictionary=session.snapshot.objects["41,34"]
	expect(device.enabled and device.fuel==3 and not session.snapshot.forest["41,32"].mature,"reconnect retains consumed fuel and young tree")
	if role=="alpha":
		expect(person(role).inventory.get("wood",0)==18 and person(role).inventory.get("resin",0)==1,"reconnect retains exact first collection")

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
				push_error("Cannot load collection test CA")
				quit(1)
				return
			tls = TLSOptions.client(certificate)
	if role.is_empty() or barrier.is_empty():
		push_error("Collection test requires an alpha or beta profile and a barrier")
		quit(1)
		return
	parent = Node2D.new()
	parent.name = "Island"
	root.add_child(parent)
	await exercise()
	if session != null and get_multiplayer().multiplayer_peer != null:
		close_client()
	print("FORESTRY_NETWORK_TEST role=%s failures=%d" % [role, failures])
	quit(0 if failures == 0 else 1)
