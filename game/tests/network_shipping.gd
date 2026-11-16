extends SceneTree
const Session = preload("res://scripts/session.gd")
const World = preload("res://scripts/world.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0]
	if mode == "seed":
		var world := World.new()
		world.save_path = args[1]
		for role in ["alpha", "beta"]:
			var token: String = "shipping-" + role
			world.add_player(token, role)
			var p: Dictionary = world.state.players[token]
			p.x = 42.5
			p.y = 32.5
			p.inventory.radish = 4
		quit(0 if world.save() else 1)
		return
	var session := Session.new()
	var island := Node.new()
	island.name = "Island"
	root.add_child(island)
	island.add_child(session)
	session.profile.token = "shipping-" + args[2]
	var quantity := 2 if args[2] == "alpha" else 1
	var expected := quantity * 24 + 6
	session.connected_world.connect(func():
		if mode == "reconnect":
			var person: Dictionary = session.snapshot.players[session.own_id]
			quit(0 if person.coins == 120 + expected and person.inventory.radish == 4 - quantity else 1)
		else:
			var payload := JSON.stringify([[["radish", quantity], ["wood", 3]], expected])
			session.perform("ship", World.SHIPPING.CELL, payload + " ".repeat(70))
	)
	session.action_completed.connect(func(sequence: int, action: String, result: Dictionary):
		var person: Dictionary = session.snapshot.players[session.own_id]
		var private := true
		for id in session.snapshot.players:
			if id != session.own_id:
				private = private and not session.snapshot.players[id].has("coins")
		quit(0 if sequence == 1 and action == "ship" and result.ok and result.total == expected and person.coins == 120 + expected and private else 1)
	)
	if session.join("127.0.0.1", int(args[1]), args[2], "shipping-test") != OK:
		quit(1)
	await create_timer(6).timeout
	quit(1)

