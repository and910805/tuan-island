extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not ClassDB.class_exists("IslandFileLock"):
		quit(2)
		return
	var lock = ClassDB.instantiate("IslandFileLock")
	if args[0] == "invalid":
		var invalid: bool = lock.acquire("") == ERR_INVALID_PARAMETER and lock.acquire("wrong.txt") == ERR_INVALID_PARAMETER
		print("LOCK_RESULT ", ERR_INVALID_PARAMETER if invalid else -1)
		quit(0 if invalid else 1)
		return
	var status: int = lock.acquire(args[1])
	print("LOCK_PID ", OS.get_process_id())
	print("LOCK_RESULT ", status)
	if args[0] == "hold" and status == OK:
		while true:
			OS.delay_msec(100)
	elif args[0] == "lifecycle" and status == OK:
		var other = ClassDB.instantiate("IslandFileLock")
		assert(lock.is_held() and lock.acquire(args[1]) == ERR_ALREADY_IN_USE)
		assert(other.acquire(args[1]) == ERR_ALREADY_IN_USE)
		lock = null
		assert(other.acquire(args[1]) == OK)
		other.release()
		assert(not other.is_held())
	quit(0)

