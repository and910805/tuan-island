extends SceneTree

const Session = preload("res://scripts/session.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var island := Node.new()
	island.name = "Island"
	root.add_child(island)
	var session := Session.new()
	island.add_child(session)
	var cert := X509Certificate.new()
	if cert.load(settings.ca) != OK:
		quit(1)
		return
	var status := session.configure_identity(settings.api, settings.get("world_id","test-island"), FileAccess.get_file_as_string(settings.key), settings.members, settings.owner, false, TLSOptions.client(cert), settings.world)
	if status == OK and settings.has("directory"):
		status = session.configure_directory(settings.directory, "測試島")
	if status != OK or session.host(settings.port, "", settings.world, "", "127.0.0.1", true, "websocket") != OK:
		quit(1)
		return
	if settings.has("stop_file"):
		stop_on_request.call_deferred(session,settings.stop_file)
	if not settings.has("wire_proof"):return
	var transport:=session.multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	while true:
		for id:int in session.identities:
			var connection:=transport.get_peer(id)
			if connection==null:continue
			var request:=connection.get_requested_url()
			if not Session.SnapshotWire.accepts(request):continue
			var file:=FileAccess.open(settings.wire_proof,FileAccess.WRITE)
			if file!=null:file.store_string(request)
			return
		await create_timer(0.02).timeout

func stop_on_request(session:Session,path:String) -> void:
	while not FileAccess.file_exists(path):
		await create_timer(0.1).timeout
	quit(0 if session.shutdown() else 1)
