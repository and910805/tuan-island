extends SceneTree
## Old-protocol rejection over a real loopback WebSocket (ws://, NOT wss/TLS).
## Driven by work/house-rooms/network_blueprint.py --transport ws.
## Args (after `--`): <port> <room_key> <legacy_version>
## Registers with the given (old) protocol number through the normal unauthenticated
## register_player RPC and passes only if the server answers with the version
## rejection notice and never welcomes the client or sends a snapshot.
## Prints `PROTOCOL_<n>_REJECTION transport=websocket checks=<c> failures=<f>`.

const Session = preload("res://scripts/session.gd")
const WAIT_MSEC := 8000

class OldSession extends Session:
	var legacy_version := 36
	func _connected() -> void:
		register_player.rpc_id(1, legacy_version, profile.token, desired_name, room_key)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("BP_FAIL usage: <port> <room_key> <legacy_version>")
		quit(2)
		return
	var client := OldSession.new()
	client.legacy_version = int(args[2])
	var island := Node2D.new()
	island.name = "Island"
	root.add_child(island)
	island.add_child(client)
	client.notice.connect(func(message: String, success: bool):
		print("LEGACY_WS_NOTICE ok=%s: %s" % [str(success), message])
		if not success and message.contains("請更新遊戲後再加入"):
			client.set_meta("version_rejected", true))
	client.connected_world.connect(func(): client.set_meta("welcomed", true))
	var result := client.join("ws://127.0.0.1:%d" % int(args[0]), int(args[0]), "legacy", args[1])
	var failures := 0
	var checks := 0
	checks += 1
	if result != OK:
		failures += 1
		print("LEGACY_WS_CHECK FAIL join returned %d" % result)
	checks += 1
	var is_ws: bool = client.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	if not is_ws:
		failures += 1
		print("LEGACY_WS_CHECK FAIL client peer is not WebSocketMultiplayerPeer")
	var deadline := Time.get_ticks_msec() + WAIT_MSEC
	while result == OK and Time.get_ticks_msec() < deadline:
		if client.get_meta("version_rejected", false) or client.get_meta("welcomed", false):
			break
		await create_timer(0.05).timeout
	checks += 1
	var rejected: bool = client.get_meta("version_rejected", false) and not client.get_meta("welcomed", false) and client.snapshot.is_empty()
	if not rejected:
		failures += 1
		print("LEGACY_WS_CHECK FAIL protocol %d was not rejected (welcomed=%s snapshot=%d keys)" % [client.legacy_version, str(client.get_meta("welcomed", false)), client.snapshot.size()])
	client.shutdown()
	for _frame in 8:
		await process_frame
	print("PROTOCOL_%d_REJECTION transport=websocket checks=%d failures=%d" % [client.legacy_version, checks, failures])
	quit(0 if failures == 0 else 1)
