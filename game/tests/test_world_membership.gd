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
	var guest_id := Membership.management_id("legacy-peer")
	var third_id := Membership.management_id(reloaded.read("third").character)
	expect(reloaded.read("owner").members.any(func(row):return row.get("management_id") == guest_id) and reloaded.read("third").members.all(func(row):return not row.has("management_id")), "Management handles are scoped to the caller")
	expect(not reloaded.set_admin("guest", third_id, true) and not reloaded.set_admin("owner", Membership.management_id("legacy-owner"), false), "Member cannot promote and owner role is protected")
	expect(reloaded.set_admin("owner", guest_id, true) and reloaded.open(file) and reloaded.role("guest") == "admin", "Owner grant survives restart")
	expect(reloaded.managed_account("guest", third_id) == "third" and reloaded.managed_account("guest", Membership.management_id("legacy-owner")).is_empty(), "Admin can moderate a member and cannot target owner")
	expect(not reloaded.rotate("guest").ok and not reloaded.set_admin("guest", third_id, true), "Admin cannot alter invitations or assign roles")
	var published := reloaded.publish_snapshot([])
	expect(published.members.any(func(row):return row.account_id == "guest" and row.role == "admin" and not row.has("management_id")), "Directory receives role without moderation handle")
	expect(typeof(published.invite.generation)==TYPE_INT and published.invite.generation==second.generation
		and typeof(published.invite.expires)==TYPE_INT and published.invite.expires==second.expires,
		"Directory invitation fields retain their values and integer wire types after reopening")
	var third_character: String = reloaded.read("third").character
	expect(reloaded.set_blocked("third",guest_id,true).is_empty(), "Member cannot block another account")
	expect(reloaded.set_blocked("guest",third_id,true) == "third" and reloaded.open(file), "Administrator block survives roster reload")
	expect(reloaded.read("third").is_empty() and not reloaded.admit("third","Renamed",second.code)
		and reloaded.plan_admission("third","Renamed",second.code).code == "WORLD_BLOCKED", "Blocked account cannot bypass block with a valid invite or name change")
	var writable_path := reloaded.path
	reloaded.path = writable_path.path_join("missing").path_join("roster")
	expect(reloaded.set_blocked("guest",third_id,false).is_empty() and reloaded.is_blocked("third"), "Failed write leaves block effective")
	reloaded.path = writable_path
	expect(reloaded.set_blocked("guest",third_id,false) == "third" and reloaded.open(file)
		and reloaded.plan_admission("third","Renamed").character == third_character, "Unblock restores original character and requires no invitation")
	expect(reloaded.set_admin("owner", guest_id, false) and reloaded.open(file) and reloaded.managed_account("guest", third_id).is_empty(), "Revoke survives restart and removes moderation access")
	var history: Array = reloaded.read("owner").management_history
	expect(history.map(func(event):return event.action) == ["invite_rotate","invite_rotate","admin_grant","block","unblock","admin_revoke"], "Successful management changes persist in order; denied actions and failed saves leave no entries")
	expect(history[3].actor == "Renamed" and history[3].target == "Sam" and not reloaded.read("guest").has("management_history"), "Only owner receives named management history")
	var stored_audit: String = JSON.stringify(JSON.parse_string(FileAccess.get_file_as_string(file)).audit)
	expect(not stored_audit.contains(second.code) and not stored_audit.contains(second.code.sha256_text()) and not stored_audit.contains(third_character), "Audit excludes invite credentials and character credentials")
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
