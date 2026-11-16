extends SceneTree

const Session = preload("res://scripts/session.gd")

class OldSession extends Session:
	var legacy_version := 35
	func _connected() -> void:
		register_player.rpc_id(1, legacy_version, profile.token, desired_name, room_key)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [2,3]:
		quit(1)
		return
	var client := OldSession.new()
	if args.size()==3:client.legacy_version=int(args[2])
	var island := Node2D.new()
	island.name = "Island"
	root.add_child(island)
	island.add_child(client)
	var rejected := false
	client.notice.connect(func(message: String, success: bool):
		if not success and message.contains("請更新遊戲後再加入"):
			client.set_meta("version_rejected", true))
	client.connected_world.connect(func(): client.set_meta("welcomed", true))
	var result := client.join("127.0.0.1", int(args[0]), "legacy", args[1])
	var deadline := Time.get_ticks_msec() + 5000
	while result == OK and Time.get_ticks_msec() < deadline:
		if client.get_meta("version_rejected", false) or client.get_meta("welcomed", false):
			break
		await create_timer(0.05).timeout
	rejected = client.get_meta("version_rejected", false) and not client.get_meta("welcomed", false) and client.snapshot.is_empty()
	client.shutdown()
	print("PROTOCOL_%d_REJECTION checks=1 failures=%d" % [client.legacy_version,0 if rejected else 1])
	quit(0 if rejected else 1)
