extends SceneTree

const World = preload("res://scripts/world.gd")
const Session = preload("res://scripts/session.gd")
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
		if (settings.mode == "logout" and entered) or (settings.mode.begins_with("bad_tls") and not entered):
			finish(true))
	session.identity_status.connect(identity)
	session.action_completed.connect(func(sequence: int, action: String, result: Dictionary):
		if settings.mode != "ship":
			return
		var player: Dictionary = session.snapshot.players[session.own_id]
		finish(sequence == 1 and action == "ship" and result.ok and result.total == 6 and player.coins == 277 and player.inventory.wood == 9)
	)
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
	await create_timer(16.0 if settings.mode == "logout" else 4.0).timeout
	finish(rejected and not entered if settings.mode in ["legacy", "denied"] else false)

func identity(info: Dictionary) -> void:
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
		elif settings.mode == "ship":
			if not info.can_manage or player.coins != 271:
				finish(false)
			else:
				session.perform("ship", World.SHIPPING.CELL, JSON.stringify([[["wood", 3]], 6]))
		elif settings.mode == "ship_reconnect":
			finish(info.can_manage and player.coins == 277 and player.inventory.wood == 9)
		elif settings.mode == "member":
			if info.can_manage or player.coins != 120 or info.members.size() != 2:
				finish(false)
			else:
				session.request_invite_rotation()
		elif settings.mode == "reconnect":
			finish(not info.can_manage and player.coins == 120 and info.members.size() == 2)
		elif settings.mode == "logout":
			FileAccess.open(settings.output, FileAccess.WRITE).close()
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

func finish(ok: bool) -> void:
	print("IDENTITY_E2E_CLIENT ok=%s" % ok)
	quit(0 if ok else 1)
