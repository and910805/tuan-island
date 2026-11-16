extends SceneTree

const Membership = preload("res://scripts/world_membership.gd")
var checks := 0
var failures := 0

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var file := OS.get_environment("TEMP").path_join("membership-%s.json" % Membership.new_character())
	var model := Membership.new()
	expect(model.initialize(file, "Test Island", "owner", "Sam", "legacy-owner"), "Initialize with owner and legacy mapping")
	expect(model.read("stranger").is_empty(), "Non-member cannot inspect private world")
	expect(model.read("owner").character == "legacy-owner", "Owner retains old character")
	expect(not model.rotate("stranger").ok and not model.revoke("stranger"), "Non-member cannot manage invites")
	var first: Dictionary = model.rotate("owner")
	expect(first.ok and first.code.length() == 64, "Issue 32-byte invite")
	var raw := FileAccess.get_file_as_string(file)
	expect(not raw.contains(first.code) and raw.contains(first.code.sha256_text()), "Only digest is persisted")
	expect(not model.link_legacy("stranger", "guest", "Sam", "legacy-peer"), "Stranger cannot assign old character")
	expect(model.link_legacy("owner", "guest", "Sam", "legacy-peer"), "Owner explicitly maps a verified account")
	expect(not model.link_legacy("owner", "other", "Sam", "legacy-peer"), "Old character cannot be assigned twice")
	expect(model.rename("guest", "Renamed") and model.read("guest").character == "legacy-peer" and not model.read("guest").can_manage, "Rename retains character and member role")
	expect(not model.rename("guest", "Bad\nName"), "Names reject line breaks")
	var second: Dictionary = model.rotate("owner")
	expect(second.ok and second.generation == first.generation + 1, "Rotation increments generation")
	var reloaded := Membership.new()
	expect(reloaded.open(file), "Reload valid roster")
	expect(not reloaded.admit("third", "Sam", first.code), "Rotation rejects old code after restart")
	expect(reloaded.admit("third", "Sam", second.code), "New code joins third seat")
	expect(reloaded.read("third").character != reloaded.read("owner").character, "Identical names use separate characters")
	expect(reloaded.admit("third") and reloaded.read("third").members.size() == 3, "Member reconnects without code and takes no extra seat")
	expect(reloaded.admit("fourth", "Fourth", second.code), "Fourth seat works")
	for i in range(5,9):
		expect(reloaded.admit("member-%d"%i, "Member %d"%i, second.code), "Seat %d works"%i)
	expect(reloaded.open(file) and reloaded.read("owner").members.size()==8, "Eight members survive reload")
	expect(not reloaded.admit("ninth", "Ninth", second.code), "Ninth member rejected")
	expect(reloaded.revoke("owner") and reloaded.open(file), "Revocation persists")
	expect(reloaded.admit("third"), "Member can still reconnect after revocation")
	expect(reloaded.read("third").members[0].has("last_activity"), "Member view contains activity")
	# Exercise persistence failures on a second world with open seats.
	var other := file + ".other"
	var failure := Membership.new()
	expect(failure.initialize(other, "Other Island", "owner", "Sam"), "Initialize second world")
	var code: Dictionary = failure.rotate("owner")
	failure.path = other.path_join("missing").path_join("world.json")
	expect(not failure.rotate("owner").ok and not failure.revoke("owner") and not failure.admit("beta", "Beta", code.code), "Save failures do not acknowledge changes")
	expect(failure.read("owner").members.size() == 1, "Failed admission does not change roster")
	failure.path = other
	expect(failure.admit("beta", "Beta", code.code), "Previous code survives failed rotation/revocation")
	expect(failure.revoke("owner") and failure.open(other) and not failure.admit("new", "New", code.code), "Revoked code fails on restart even with free seats")
	var expired_code: Dictionary = failure.rotate("owner")
	var expired: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(other))
	expired.invite.expires = Membership.now() - 1
	var expired_file := FileAccess.open(other, FileAccess.WRITE)
	expired_file.store_string(JSON.stringify(expired))
	expired_file.close()
	expect(failure.open(other) and not failure.admit("new", "New", expired_code.code), "Expired invite cannot fill a free seat after restart")
	var corrupt := other + ".corrupt"
	var bad := FileAccess.open(corrupt, FileAccess.WRITE)
	bad.store_string("{}")
	bad.close()
	expect(not failure.open(corrupt) and not failure.initialize(corrupt, "New", "owner", "Sam"), "Invalid save cannot be initialized over")
	expect(FileAccess.get_file_as_string(corrupt) == "{}", "Corrupt file preserved")
	for item in [file, other, corrupt]:
		DirAccess.remove_absolute(item)
	print("WORLD_MEMBERSHIP checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
