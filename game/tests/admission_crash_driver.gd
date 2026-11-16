extends SceneTree
const Store = preload("res://scripts/admission_store.gd")
const World = preload("res://scripts/world.gd")
const Membership = preload("res://scripts/world_membership.gd")

class PausedStore extends Store:
	var fault: String
	func checkpoint(stage: String) -> bool:
		if stage == fault:
			print("ADMISSION_PAUSED " + stage)
			while true:
				OS.delay_msec(250)
		return true

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := args[0]
	var world_path := folder.path_join("world.json")
	var member_path := folder.path_join("members.json")
	var world := World.new()
	var members := Membership.new()
	if args[1] == "recover":
		var ok := Store.recover(world_path, member_path, "crash-test") and not Store.has_pending(member_path)
		ok = ok and world.load_world(world_path) and members.open(member_path)
		ok = ok and world.state.players.has("guest-character") and members.read("guest").get("character") == "guest-character"
		quit(0 if ok else 1)
		return
	if not world.load_world(world_path) or not members.initialize(member_path, "Island", "owner", "Owner", "owner-character"):
		quit(1)
		return
	world.add_player("owner-character", "Owner")
	if not world.save():
		quit(1)
		return
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(member_path))
	roster.members.guest = Membership.member("Guest", "guest-character")
	world.add_player("guest-character", "Guest")
	var store := PausedStore.new()
	store.fault = args[1]
	quit(0 if store.commit(world_path, member_path, "crash-test", world.state, roster) else 1)
