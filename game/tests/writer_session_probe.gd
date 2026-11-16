extends SceneTree

const Session = preload("res://scripts/session.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var session := Session.new()
	root.add_child(session)
	var status := session.host(int(args[1]), "", args[2], "", "127.0.0.1", true, "websocket")
	print("WRITER_SESSION_RESULT ", status)
	if args[0] == "hold" and status == OK:
		print("LOCK_RESULT 0")
		print("LOCK_PID ", OS.get_process_id())
		while true:
			OS.delay_msec(100)
	if status == OK and not session.shutdown():
		quit(1)
		return
	quit(0)
