extends SceneTree

const Session = preload("res://scripts/session.gd")
const MILESTONE := "garden_sampler"
const TOKENS := {"alpha": "network-alpha-test", "beta": "network-beta-test"}
const CROPS := {
	"alpha": {"radish": true, "lettuce": true, "wheat": true},
	"beta": {"carrot": true, "potato": true, "tomato": true},
}

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

func rewarded() -> bool:
	var own := person(role)
	return own.get("coins") == 180 and own.get("inventory", {}).get("tomato_seed") == 2 and own.get("collection", {}).get("claimed", {}) == {MILESTONE: true}

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
	session.notice.connect(func(_message: String, success: bool): notices.append(success))
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
	if not await connect_client():
		return
	var other := "beta" if role == "alpha" else "alpha"
	if not await wait_until(func(): return not person(other).is_empty(), "both players visible"):
		return
	expect(session.own_id == player_id(role), "snapshot identifies the correct owner")
	expect(person(role).coins == 120 and not person(role).inventory.has("tomato_seed"), "fresh reward balance")
	expect(person(role).collection.claimed.is_empty() and person(other).collection.claimed.is_empty(), "both milestones start unclaimed")
	if not mark("ready") or not await wait_until(func(): return both_marked("ready"), "both clients ready"):
		return
	session.perform("claim_milestone", Vector2i.ZERO, MILESTONE)
	session.perform("claim_milestone", Vector2i.ZERO, MILESTONE)
	if not await wait_until(func(): return notices.size() >= 2 and rewarded(), "reward saved and both requests answered"):
		return
	expect(notices == [true, false], "first claim succeeds and distinct request is rejected")
	expect(person(role).collection.crops == CROPS[role] and person(other).get("collection", {}).get("crops", {}) == CROPS[other], "each player's discoveries stay distinct")
	if not mark("claimed") or not await wait_until(func(): return both_marked("claimed"), "both clients claimed"):
		return
	close_client()
	await create_timer(0.8).timeout
	notices.clear()
	if not await connect_client():
		return
	expect(rewarded(), "same identity retains exactly one reward after reconnect")
	expect(person(role).collection.crops == CROPS[role], "same identity retains its discoveries")
	session.perform("claim_milestone", Vector2i.ZERO, MILESTONE)
	if not await wait_until(func(): return not notices.is_empty(), "reconnect claim answered"):
		return
	expect(notices == [false] and rewarded(), "new session cannot claim again")

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
	print("COLLECTION_NETWORK_TEST role=%s failures=%d" % [role, failures])
	quit(0 if failures == 0 else 1)
