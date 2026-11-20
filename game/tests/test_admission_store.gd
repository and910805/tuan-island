extends SceneTree

const Store = preload("res://scripts/admission_store.gd")
const World = preload("res://scripts/world.gd")
const Membership = preload("res://scripts/world_membership.gd")

class InterruptedStore extends Store:
	var fault: String
	func checkpoint(stage: String) -> bool:
		return stage != fault

var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _initialize() -> void:
	expect(not Store.safe_pair("/world.json", "/world.json.tmp"), "Roster cannot alias the normal world save staging file")
	var root_dir := OS.get_environment("TEMP").path_join("admission-" + Membership.new_character())
	DirAccess.make_dir_recursive_absolute(root_dir)
	for stage in ["", "prejournal", "afterjournal", "afterworld", "aftermembers", "cleanup"]:
		var folder := root_dir.path_join(stage if not stage.is_empty() else "success")
		DirAccess.make_dir_recursive_absolute(folder)
		var world_path := folder.path_join("world.json")
		var member_path := folder.path_join("members.json")
		var world := World.new()
		world.load_world(world_path)
		world.add_player("owner-character", "Owner")
		var members := Membership.new()
		expect(members.initialize(member_path, "Island", "owner", "Owner", "owner-character"), "Initial membership is saved")
		var before_members := FileAccess.get_file_as_string(member_path)
		var roster: Dictionary = JSON.parse_string(before_members)
		roster.members["new-account"] = Membership.member("Guest", "guest-character")
		var world_before := JSON.stringify(world.state)
		write(world_path + ".bak", world_before)
		if stage != "afterworld":
			write(world_path, world_before)
		world.add_player("guest-character", "Guest")
		var after_world := JSON.stringify(world.state)
		var writer := InterruptedStore.new()
		writer.fault = stage
		if stage.is_empty():
			var inconsistent := roster.duplicate(true)
			inconsistent.members["new-account"].character = "absent-character"
			expect(not writer.commit(world_path, member_path, "world", world.state, inconsistent) and not Store.has_pending(member_path), "New roster entry must refer to an existing player")
			inconsistent = roster.duplicate(true)
			inconsistent.members.owner.character = "absent-character"
			inconsistent.members.owner.last_activity += 1
			expect(not writer.commit(world_path, member_path, "world", world.state, inconsistent), "Changed roster entry must refer to an existing player")
		expect(writer.commit(world_path, member_path, "world", world.state, roster) == stage.is_empty(), "Commit result reflects interruption at " + stage)
		var pending: bool = stage not in ["", "prejournal"]
		expect(Store.has_pending(member_path) == pending, "WAL remains exactly when decision is pending")
		if stage == "prejournal":
			expect(FileAccess.get_file_as_string(world_path) == world_before and FileAccess.get_file_as_string(member_path) == before_members, "No pre-commit file changes")
		else:
			if pending:
				expect(not Store.recover(world_path, member_path, "wrong") and Store.has_pending(member_path), "Wrong world cannot consume WAL")
				expect(not Store.recover(world_path + ".other", member_path, "world"), "Wrong file pair cannot replay WAL")
			if stage == "afterjournal":
				write(world_path, "external update")
				expect(not Store.recover(world_path, member_path, "world") and FileAccess.get_file_as_string(world_path) == "external update", "Recovery preserves unexpected target update")
				write(world_path, world_before)
			expect(Store.recover(world_path, member_path, "world") and Store.recover(world_path, member_path, "world"), "Recovery is repeatable")
			expect(FileAccess.get_file_as_string(world_path) == after_world and FileAccess.get_file_as_string(world_path + ".bak") == after_world, "Primary and fallback carry guest")
			expect(members.open(member_path) and members.read("new-account").character == "guest-character", "Recovered roster and world agree")
			var retained := false
			for entry in DirAccess.get_files_at(folder):
				if entry.begins_with("world.json.bak.admission-previous-"):
					retained = FileAccess.get_file_as_string(folder.path_join(entry)) == world_before
			expect(retained, "Independent previous backup remains available")
		for entry in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(folder.path_join(entry))
		DirAccess.remove_absolute(folder)
	var blocker := Store.journal_path(root_dir.path_join("members.json"))
	write(blocker, "{}")
	expect(not Store.recover(root_dir.path_join("world.json"), root_dir.path_join("members.json"), "world") and FileAccess.file_exists(blocker), "Corrupt WAL is retained")
	DirAccess.remove_absolute(blocker)
	DirAccess.make_dir_absolute(blocker)
	expect(Store.has_pending(root_dir.path_join("members.json")) and not Store.recover(root_dir.path_join("world.json"), root_dir.path_join("members.json"), "world"), "Directory at journal path fails closed")
	DirAccess.remove_absolute(blocker)
	DirAccess.remove_absolute(root_dir)
	print("ADMISSION_STORE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
