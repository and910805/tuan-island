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
	var status := session.configure_identity(settings.api, "test-island", FileAccess.get_file_as_string(settings.key), settings.members, settings.owner, false, TLSOptions.client(cert), settings.world)
	if status == OK and settings.has("directory"):
		status = session.configure_directory(settings.directory, "測試島")
	if status != OK or session.host(settings.port, "", settings.world, "", "127.0.0.1", true, "websocket") != OK:
		quit(1)
