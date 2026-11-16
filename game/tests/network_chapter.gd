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
			var token: String = "chapter-" + role
			world.add_player(token, role)
			var p: Dictionary = world.state.players[token]
			p.x = 39.5
			p.y = 30.5
			p.inventory.stone = 8
		world.state.board = true
		world.state.chapter_one.shipped = true
		quit(0 if world.save() else 1)
		return
	var session := Session.new()
	var island := Node.new()
	island.name = "Island"
	root.add_child(island)
	island.add_child(session)
	session.profile.token = "chapter-" + args[2]
	session.connected_world.connect(func():
		if mode != "reconnect":
			session.perform("chapter_starter", World.CHAPTER_ONE.STARTER_CELL)
	)
	session.changed.connect(func(state: Dictionary, own_id: String):
		var claims: Dictionary = state.chapter_one.starter_claims
		var person: Dictionary = state.players[own_id]
		if claims.size() != 2:
			return
		var private := true
		for id in state.players:
			if id != own_id:
				private = private and not state.players[id].has("inventory")
		var redacted := claims.has(own_id) and not claims.has("chapter-alpha") and not claims.has("chapter-beta")
		var passed: bool = private and redacted and World.CHAPTER_ONE.phase(state) == "water" and person.inventory.pipe_kit == 2 and person.inventory.wood == 0
		print("CHAPTER_ENET mode=%s role=%s protocol=%d phase=%s claims=%d private=%s passed=%s" % [mode, args[2], Session.PROTOCOL, World.CHAPTER_ONE.phase(state), claims.size(), private, passed])
		quit(0 if passed else 1)
	)
	if session.join("127.0.0.1", int(args[1]), args[2], "chapter-test") != OK:
		quit(1)
	await create_timer(6).timeout
	quit(1)

