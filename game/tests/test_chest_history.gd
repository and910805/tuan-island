extends SceneTree

const ChestHistory = preload("res://scripts/chest_history.gd")
const World = preload("res://scripts/world.gd")
const Items := {"wood": "木材", "stone": "石材"}

var failures := 0
var checks := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func known_item(item: String) -> bool:
	return Items.has(item)

func private_access() -> void:
	var world := World.new()
	var cell := Vector2i(38, 34)
	var nearby := Vector2(38.5, 35.5)
	world.add_player("owner", "小栗", nearby)
	world.add_player("visitor", "阿榆", nearby)
	world.state.removed[World.key(cell)] = true
	world.state.players.owner.inventory.wood = 40
	var do := func(token: String, id: String, action: String, extra := "") -> Dictionary:
		return world.act(token, id, action, cell, extra)
	expect(do.call("owner", "build", "build", "private_chest").ok, "Builds a real private chest")
	expect(do.call("owner", "allow", "box_deposit_access", "island").ok, "Enables deposit-only permissions")
	expect(do.call("visitor", "transfer", "deposit_exact", "wood:2").ok, "Visitor can still make a deposit")
	var denied: Dictionary = do.call("visitor", "read", ChestHistory.READ_ACTION)
	expect(not denied.ok and not denied.has("rows"), "Deposit-only guest cannot learn history")
	expect(do.call("owner", "allow-take", "box_withdraw_access", "friend:" + "visitor".sha256_text().left(16)).ok, "Grants the visitor withdrawal permission")
	var read: Dictionary = do.call("visitor", "read", ChestHistory.READ_ACTION)
	expect(read.ok and read.rows.size() == 1 and read.rows[0].actor == "阿榆" and read.rows[0].amount == 2, "Granted viewer can read the real transfer without an account token")
	expect(do.call("owner", "revoke", "box_withdraw_access", "owner").ok, "Revokes withdrawal permission")
	expect(not do.call("visitor", "after-revoke", ChestHistory.READ_ACTION).ok, "Revocation closes the history endpoint")
	world.state.players.owner.x = nearby.x + 6.0
	expect(not do.call("owner", "away", ChestHistory.READ_ACTION).ok, "An owner far from the chest cannot inspect it")

func _initialize() -> void:
	var box := {"type": "chest", "items": {}}
	expect(ChestHistory.valid(box, known_item), "Legacy chests need no history field")
	for index in range(205):
		ChestHistory.record(box, "小栗", "wood", index + 1, index % 2 == 0, float(index))
	var rows: Array = box[ChestHistory.FIELD]
	expect(rows.size() == 200 and rows.front().amount == 6 and rows.back().amount == 205, "Only the latest 200 transfers survive, in their committed order")
	expect(not rows.front().depositing and rows.back().depositing, "Both directions remain readable")
	expect(ChestHistory.valid(JSON.parse_string(JSON.stringify(box)), known_item), "Saved JSON keeps valid history")
	var private_box := {"type": "private_chest"}
	ChestHistory.record(private_box, "阿榆", "stone", 2, true, 5.0)
	expect(ChestHistory.valid(private_box, known_item) and private_box[ChestHistory.FIELD][0].actor == "阿榆", "Private chests keep transfer history")
	var non_chest := {"type": "mill"}
	ChestHistory.record(non_chest, "阿榆", "wood", 2, true, 0.0)
	expect(not non_chest.has(ChestHistory.FIELD), "Machine buffers never get this history field")
	var invalid: Dictionary = private_box.duplicate(true)
	for malformed: Dictionary in [{"item": "unknown"}, {"amount": 1.5}, {"amount": -1}, {"depositing": 1}, {"time": -0.01}, {"actor": "abcdefghijklmnop"}, {"token": "private-account-key"}]:
		invalid[ChestHistory.FIELD][0] = private_box[ChestHistory.FIELD][0].duplicate()
		invalid[ChestHistory.FIELD][0].merge(malformed, true)
		expect(not ChestHistory.valid(invalid, known_item), "Rejects a malformed transfer row: %s" % str(malformed.keys()))
	invalid[ChestHistory.FIELD] = rows.duplicate()
	invalid[ChestHistory.FIELD].append(rows[0])
	expect(not ChestHistory.valid(invalid, known_item), "History may hold at most 200 transfers")
	private_access()
	print("CHEST_HISTORY_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
