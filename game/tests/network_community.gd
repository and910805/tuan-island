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
			var token: String = "community-" + role
			world.add_player(token, role)
			var p: Dictionary = world.state.players[token]
			p.x = 41.5
			p.y = 30.5
			p.inventory.soup = 2 if role == "alpha" else 0
			p.inventory.bread = 1 if role == "alpha" else 0
		world.state.board = true
		quit(0 if world.save() else 1)
		return
	var session := Session.new()
	var island := Node.new()
	island.name = "Island"
	root.add_child(island)
	island.add_child(session)
	session.profile.token = "community-" + args[2]
	var attempted := [false]
	session.connected_world.connect(func():
		if mode != "reconnect" and args[2] == "alpha":
			session.perform("picnic", Vector2i(40,29))
			session.perform("picnic", Vector2i(40,29))
	)
	session.notice.connect(func(message: String, ok: bool):
		if not ok and message.contains("野餐已經"):
			attempted[0] = true
	)
	session.changed.connect(func(state: Dictionary, own_id: String):
		var table := World.COMMUNITY.table_cell(state)
		if table == World.COMMUNITY.NO_CELL or (mode != "reconnect" and args[2] == "alpha" and not attempted[0]):
			return
		var person: Dictionary = state.players[own_id]
		var private := true
		for id in state.players:
			if id != own_id:
				private = private and not state.players[id].has("inventory")
		var mirror := World.new()
		mirror.state = state
		var passed: bool = private and table == Vector2i(39,30) and mirror.blocked(table) and person.inventory.radish_seed == 8 and state.picnic
		print("COMMUNITY_ENET mode=%s role=%s protocol=%d table=%s private=%s passed=%s" % [mode,args[2],Session.PROTOCOL,table,private,passed])
		quit(0 if passed else 1)
	)
	if session.join("127.0.0.1", int(args[1]), args[2], "community-test") != OK:
		quit(1)
	await create_timer(6).timeout
	quit(1)
