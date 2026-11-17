extends SceneTree

const Session = preload("res://scripts/session.gd")
const World = preload("res://scripts/world.gd")
var session: Session
var settings: Dictionary
var entered := false
var saved := false
var managing := false
var rejected := false
var pending_rotation := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	session = Session.new()
	var island := Node.new()
	island.name = "Island"
	root.add_child(island)
	island.add_child(session)
	session.connected_world.connect(func(): entered = true)
	session.disconnected_world.connect(func():
		if (settings.mode in ["logout", "kick_target"] and entered) or (settings.mode.begins_with("bad_tls") and not entered):
			finish(true))
	session.identity_status.connect(identity)
	session.notice.connect(func(_text: String, _ok: bool): if settings.mode == "legacy": rejected = true)
	var status: Error
	if settings.mode == "legacy":
		session.profile.token = "legacy-character-original"
		status = session.join(settings.address, 0, "Same Name", "")
	else:
		var tls: TLSOptions
		if not String(settings.get("ca", "")).is_empty():
			var cert := X509Certificate.new()
			if cert.load(settings.ca) != OK:
				finish(false)
				return
			tls = TLSOptions.client(cert, settings.get("expected_hostname", ""))
		status = session.join_authenticated(settings.address, 0, settings.ticket, settings.get("invite", ""), not settings.address.begins_with("wss://"), tls)
	if status != OK:
		finish(false)
		return
	var timeout := 80.0 if settings.mode in ["visit_guest","visit_other"] else (35.0 if settings.mode == "plot_live" else (16.0 if settings.mode == "logout" else 4.0))
	await create_timer(timeout).timeout
	finish(rejected and not entered if settings.mode in ["legacy", "denied"] else false)

func identity(info: Dictionary) -> void:
	if settings.mode in ["promote","demote"] and info.operation == "admin_change":
		finish(entered and info.ok and info.enabled == (settings.mode == "promote"))
		return
	if settings.mode == "moderator" and info.operation == "kick_member":
		finish(entered and info.ok)
		return
	if settings.mode in ["block","unblock"] and info.operation == "block_member":
		finish(entered and info.ok and info.enabled == (settings.mode == "block"))
		return
	if settings.mode in ["grant_plot","revoke_plot"] and info.operation == "public_builder":
		finish(entered and info.ok and info.enabled == (settings.mode == "grant_plot"))
		return
	if settings.mode == "blocked" and info.operation == "join":
		finish(not entered and not info.ok and info.code == "WORLD_BLOCKED")
		return
	if not info.ok:
		rejected = true
		if settings.mode == "denied":
			finish(not entered)
		elif info.operation == "rotate" and settings.mode == "member":
			finish(entered and saved)
		return
	if info.operation == "membership" and entered and not saved:
		saved = true
		var player: Dictionary = session.snapshot.players[session.own_id]
		if settings.mode == "owner":
			if not info.can_manage or player.coins != 271:
				finish(false)
			else:
				session.request_invite_rotation()
		elif settings.mode == "member":
			if info.can_manage or player.coins != 120 or info.members.size() != 2:
				finish(false)
			else:
				session.request_invite_rotation()
		elif settings.mode == "reconnect":
			finish(not info.can_manage and player.coins == 120 and info.members.size() == 2)
		elif settings.mode == "logout":
			FileAccess.open(settings.output, FileAccess.WRITE).close()
		elif settings.mode in ["promote","demote","moderator","block","unblock","grant_plot","revoke_plot"]:
			var target_id := str(settings.target_id)
			if not info.members.any(func(row):return row.get("management_id","") == target_id):
				finish(false)
			elif settings.mode == "moderator":
				session.request_member_kick(target_id)
			elif settings.mode in ["block","unblock"]:
				session.request_member_block(target_id, settings.mode == "block")
			elif settings.mode in ["grant_plot","revoke_plot"]:
				session.request_public_builder(target_id, settings.mode == "grant_plot")
			else:
				session.request_admin_change(target_id, settings.mode == "promote")
		elif settings.mode == "kick_target":
			FileAccess.open(settings.output, FileAccess.WRITE).close()
		elif settings.mode == "after_kick":
			finish(player.coins == 120 and not info.can_manage)
		elif settings.mode == "visit_join":
			finish(not info.can_manage)
		elif settings.mode == "audit_owner":
			var history: Array = info.get("management_history", [])
			finish(info.can_manage and history.map(func(event):return event.action).slice(-5) == ["invite_rotate","kick","block","unblock","admin_revoke"]
				and history.all(func(event):return event.size() == 4 and event.has("actor") and event.has("target")))
		elif settings.mode == "audit_member":
			finish(not info.can_manage and not info.has("management_history"))
		elif settings.mode == "plot_live":
			play_public_plot.call_deferred()
		elif settings.mode in ["visit_guest","visit_other"]:
			play_visit.call_deferred()
		elif settings.mode == "visit_policy":
			set_visit_policy.call_deferred()
		elif settings.mode == "visit_open_door":
			open_visit_door.call_deferred()
		elif settings.mode in ["plot_enabled","plot_disabled"]:
			finish(session.snapshot.get("can_build_public_plot",null) == (settings.mode == "plot_enabled"))
		elif settings.mode == "revoke":
			if info.can_manage:
				session.request_invite_revocation()
			else:
				finish(false)
	elif info.operation == "revoke" and settings.mode == "revoke" and info.get("synced", false):
		finish(entered and not info.has("code"))
	elif info.operation == "rotate" and settings.mode == "owner":
		if settings.get("directory", false):
			if not info.get("synced", false):
				pending_rotation = not info.has("code")
				return
			if not pending_rotation or not String(info.get("code", "")).begins_with("TI1."):
				finish(false)
				return
		var file := FileAccess.open(settings.output, FileAccess.WRITE)
		file.store_string(info.code)
		file.close()
		finish(true)

func walk_to(destination:Vector2i,area:Rect2i) -> bool:
	var floor_map := World.new()
	for layer in ["objects","ground","removed"]:
		floor_map.state[layer]=session.snapshot[layer]
	var grid := AStarGrid2D.new()
	grid.region = area
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in range(grid.region.position.y, grid.region.end.y):
		for x in range(grid.region.position.x, grid.region.end.x):
			var tile := Vector2i(x,y)
			var center:=Vector2(tile)+Vector2(0.5,0.5)
			grid.set_point_solid(tile,not floor_map.can_stand(center) or not floor_map.can_enter_room_floor(session.own_id,center))
	var person: Dictionary = session.snapshot.players[session.own_id]
	var start := Vector2i(floori(person.x), floori(person.y))
	var route := grid.get_id_path(start,destination)
	if route.is_empty():return false
	print("WALK from=%s to=%s steps=%d" % [start,destination,route.size()])
	for tile in route:
		var point := Vector2(tile)+Vector2(0.5,0.5)
		var deadline:=Time.get_ticks_msec()+5500
		while true:
			person = session.snapshot.players[session.own_id]
			var position:=Vector2(person.x,person.y)
			var toward := point-position
			if toward.length() < 0.14: break
			if Time.get_ticks_msec()>deadline:
				print("WALK_STALLED at=%s next=%s" % [position,point])
				session.input_direction(Vector2.ZERO)
				return false
			session.input_direction((toward*3.0).limit_length())
			await create_timer(0.10).timeout
	session.input_direction(Vector2.ZERO)
	return true

func play_public_plot() -> void:
	var plot := World.PUBLIC_BUILD_PLOT.position
	if not await walk_to(plot+Vector2i.DOWN,Rect2i(36,22,18,12)):
		finish(false)
		return
	var wood := int(session.snapshot.players[session.own_id].inventory.wood)
	var target := World.key(plot)
	session.perform("build",plot,"chair")
	var denied: Array = await session.notice
	if denied[1] or denied[0] != World.PUBLIC_BUILD_DENIED or session.snapshot.objects.has(target):
		finish(false)
		return
	FileAccess.open(settings.output,FileAccess.WRITE).close()
	while not session.snapshot.get("can_build_public_plot",false):
		await session.changed
	session.perform("build",plot,"chair")
	var placed: Array = await session.notice
	if not placed[1]:
		finish(false)
		return
	while not session.snapshot.objects.has(target):
		await session.changed
	var piece: Dictionary = session.snapshot.objects[target]
	if piece.type != "chair" or piece.owner != session.own_id or session.snapshot.players[session.own_id].inventory.wood != wood-6:
		finish(false)
		return
	FileAccess.open(settings.output+".placed",FileAccess.WRITE).close()
	while session.snapshot.get("can_build_public_plot",true):
		await session.changed
	var neighbor := plot+Vector2i.RIGHT
	session.perform("build",neighbor,"chair")
	var revoked: Array = await session.notice
	finish(not revoked[1] and revoked[0] == World.PUBLIC_BUILD_DENIED and not session.snapshot.objects.has(World.key(neighbor))
		and session.snapshot.players[session.own_id].inventory.wood == wood-6)

func set_visit_policy() -> void:
	session.perform("room_visit_access",Vector2i(27,21),settings.policy)
	var result:Array=await session.notice
	finish(result[1])

func open_visit_door() -> void:
	session.perform("door",Vector2i(26,21))
	var result:Array=await session.notice
	finish(result[1])

func visit_attempt(direction:Vector2) -> float:
	for step in range(12):
		session.input_direction(direction)
		await create_timer(0.1).timeout
	session.input_direction(Vector2.ZERO)
	await create_timer(0.15).timeout
	return float(session.snapshot.players[session.own_id].x)

func play_visit() -> void:
	var indoor:bool=settings.get("indoor",false)
	var approach:=Vector2i(25 if indoor else 26,21)
	if not await walk_to(approach,Rect2i(25,19,29,14)):
		finish(false)
		return
	var tile:="27,21"
	if not session.snapshot.ground[tile].get("owner_visit",false):
		finish(false)
		return
	if await visit_attempt(Vector2.RIGHT)>=27.0:
		finish(false)
		return
	FileAccess.open(settings.output,FileAccess.WRITE).close()
	print("VISIT_BOUNDARY_REACHED")
	if settings.mode=="visit_other":
		while not FileAccess.file_exists(settings.granted):
			await create_timer(0.1).timeout
		finish(await visit_attempt(Vector2.RIGHT)<27.0 and not session.snapshot.ground[tile].has("visit_guest"))
		return
	while session.snapshot.ground[tile].get("visit_guest")!=session.own_id:
		await session.changed
	# Nudge over the boundary while stopping inside the two-tile deck.
	session.input_direction(Vector2.RIGHT)
	while float(session.snapshot.players[session.own_id].x)<27.4:
		await session.changed
	session.input_direction(Vector2.ZERO)
	FileAccess.open(settings.output+".entered",FileAccess.WRITE).close()
	while session.snapshot.ground[tile].has("visit_guest"):
		await session.changed
	var leave:float=await visit_attempt(Vector2.LEFT)
	if leave>=approach.x+1.0 or not await walk_to(approach,Rect2i(22,19,8,5)):
		finish(false)
		return
	finish(await visit_attempt(Vector2.RIGHT)<27.0)

func finish(ok: bool) -> void:
	print("IDENTITY_E2E_CLIENT ok=%s" % ok)
	quit(0 if ok else 1)
