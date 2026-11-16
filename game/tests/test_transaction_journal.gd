extends SceneTree

## T015 persistent transaction journal + request dedupe (real World, no mocks).
## Written by Claude; NOT run by Claude. Codex runs and accepts it.
##
## Contract (game/scripts/transaction_ledger.gd, World.act / apply_blueprint):
##   - optional root state.ledger {seq,dropped,entries,rejected}; no save VERSION
##     bump; absent until the first journaled commit; never injected on load.
##   - committed row, request receipt and state change share one save(); a failed
##     save rolls all three back.
##   - rejected economy requests stay in memory and are saved by the next commit.
##   - pid = sha256(token)[0,16]; rid = sha256(request_id)[0,24]; no raw tokens.
##   - region_snapshot / Session.public_state never carry the ledger.
##
## Disclosed fixture presets (written directly into world.state, marked PRESET):
##   chest / private_chest / bench objects, inventory counts, player x/y/region.

const World = preload("res://scripts/world.gd")
const Schema = preload("res://scripts/save_schema.gd")
const Ledger = preload("res://scripts/transaction_ledger.gd")
const Shipping = preload("res://scripts/shipping.gd")
const Session = preload("res://scripts/session.gd")
const CELL := Vector2i(38, 33)
const PRIVATE_CELL := Vector2i(37, 34)
const BENCH_CELL := Vector2i(40, 33)
const SPOT := Vector2(39.5, 33.5)
const SHOP_CELL := Vector2i(43, 29)
const SAVE_FAILED := "保存失敗，這次操作未提交。請先檢查儲存空間。"
var checks := 0
var failures := 0
var sequence := 0
var sandbox := ""

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)

# ------------------------------------------------------------------ helpers --

func fresh(players: Array = ["alice", "bob"]):
	var w = World.new()
	for t in players:
		w.add_player(t, t)
		pose(w, t, SPOT)
	place(w, CELL, "chest", "alice", {})
	return w

func pose(w, token: String, at: Vector2) -> void:
	var p: Dictionary = w.state.players[token]
	p.region = World.REGIONS.HOME  # PRESET
	p.x = at.x  # PRESET
	p.y = at.y  # PRESET

func place(w, cell: Vector2i, kind: String, owner: String, contents: Dictionary) -> void:
	w.state.objects[World.key(cell)] = {"type": kind, "owner": owner, "items": contents.duplicate(true)}  # PRESET

func bag(w, token: String) -> Dictionary:
	var person = w.state.get("players", {}).get(token, {})
	if not person is Dictionary:return {}
	var inv = person.get("inventory", {})
	return inv if inv is Dictionary else {}

func held(w, token: String, item: String) -> int:
	return int(bag(w, token).get(item, 0))

func coins(w, token: String) -> int:
	var person = w.state.get("players", {}).get(token, {})
	return int(person.get("coins", 0)) if person is Dictionary else 0

func stored(w, cell: Vector2i, item: String) -> int:
	var box = w.state.objects.get(World.key(cell), {})
	if not box is Dictionary or not box.get("items") is Dictionary:return 0
	return int(box.items.get(item, 0))

func set_held(w, token: String, item: String, amount: int) -> void:
	bag(w, token)[item] = amount  # PRESET

func set_stored(w, cell: Vector2i, item: String, amount: int) -> void:
	var box = w.state.objects.get(World.key(cell), {})
	if box is Dictionary and box.get("items") is Dictionary:box.items[item] = amount  # PRESET

func ledger(w) -> Dictionary:
	var root = w.state.get("ledger")
	return root if root is Dictionary else {}

func entries(w) -> Array:
	var list = ledger(w).get("entries", [])
	return list if list is Array else []

func rejects(w) -> Array:
	var list = ledger(w).get("rejected", [])
	return list if list is Array else []

func last_entry(w) -> Dictionary:
	var list := entries(w)
	return list[-1] if not list.is_empty() and list[-1] is Dictionary else {}

func by_rid(w, id: String) -> Array:
	return entries(w).filter(func(e): return e is Dictionary and e.get("rid") == Ledger.rid(id))

func pid(token: String) -> String:
	return token.sha256_text().left(16)

func row_items(entry: Dictionary, token: String) -> Dictionary:
	var row = entry.get("d", {}).get(pid(token), {})
	if not row is Dictionary:return {}
	var found = row.get("items", {})
	return found if found is Dictionary else {}

func row_coins(entry: Dictionary, token: String) -> int:
	var row = entry.get("d", {}).get(pid(token), {})
	return int(row.get("coins", 0)) if row is Dictionary else 0

func box_items(entry: Dictionary, cell: Vector2i, region: String = "home") -> Dictionary:
	for box in entry.get("box", []):
		if box is Dictionary and box.get("cell") == World.key(cell) and box.get("r") == region:
			return box.get("items", {}) if box.get("items") is Dictionary else {}
	return {}

func next_id() -> String:
	sequence += 1
	return "t015-%d" % sequence

func act(w, token: String, action: String, cell: Vector2i, extra: String = "", id: String = "") -> Dictionary:
	var raw = w.act(token, next_id() if id.is_empty() else id, action, cell, extra)
	return raw if raw is Dictionary else {"ok": false, "message": ""}

func canon(data) -> String:
	return JSON.stringify(data, "", true)

func json_copy(data) -> Dictionary:
	var parsed = JSON.parse_string(JSON.stringify(data))
	return parsed if parsed is Dictionary else {}

func schema_ok(candidate: Dictionary) -> bool:
	return Schema.validate(candidate, World.CROPS, World.BUILD, World.RECIPES, World.SIZE, World.TREE_TIME)

func no_secrets(data, secrets: Array) -> bool:
	var text := JSON.stringify(data)
	for secret in secrets:
		if text.contains(str(secret)):return false
	return true

func remove_save(path: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):DirAccess.remove_absolute(path + suffix)

# -------------------------------------------------------------------- cases --

func run() -> void:
	sandbox = OS.get_temp_dir().path_join("t015-journal-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sandbox)
	case_migration()
	case_legacy_fixture()
	case_malformed()
	case_resend()
	case_economy_rows()
	case_save_fault()
	case_rotation()
	case_race()
	case_visibility()
	case_request_ids()
	case_snapshot()
	print("TRANSACTION_JOURNAL checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))

## 1. Current-version save without a ledger loads unchanged; the first economy
## commit creates it lazily; reload round-trips it exactly; no VERSION bump.
func case_migration() -> void:
	var path := sandbox.path_join("migrate.json")
	var w = fresh()
	w.save_path = path
	expect(w.save(), "Baseline save written")
	expect(not w.state.has("ledger"), "New world has no ledger root")
	var plain = World.new()
	expect(plain.load_world(path) and not plain.recovered_from_backup, "Ledger-less save loads")
	expect(not plain.state.has("ledger"), "Load never injects a ledger root")
	expect(int(plain.state.version) == Schema.VERSION, "Save version is unchanged by T015")
	set_held(plain, "alice", "wood", 6)
	var r := act(plain, "alice", "deposit_half", CELL, "wood", "mig-1")
	expect(r.get("ok", false), "First deposit commits")
	var root := ledger(plain)
	expect(int(root.get("seq", -1)) == 1 and int(root.get("dropped", -1)) == 0 and entries(plain).size() == 1 and rejects(plain).is_empty(), "First journaled commit creates ledger seq 1")
	var e := last_entry(plain)
	expect(e.get("kind") == "container" and e.get("act") == "deposit_half" and e.get("by") == pid("alice") and e.get("rid") == Ledger.rid("mig-1"), "Entry identifies kind, action, actor pseudonym, request digest")
	expect(int(e.get("c", -1)) == int(plain.state.committed) and e.get("ok") == true, "Entry carries the world commit number")
	expect(int(row_items(e, "alice").get("wood", 0)) == -3 and int(box_items(e, CELL).get("wood", 0)) == 3, "Deposit_half deltas: backpack -3, box +3")
	var reloaded = World.new()
	expect(reloaded.load_world(path), "Journaled save reloads")
	expect(canon(reloaded.state.get("ledger")) == canon(plain.state.get("ledger")), "Ledger survives JSON round trip exactly")
	expect(int(reloaded.state.version) == Schema.VERSION, "Reloaded version stays current")
	remove_save(path)

## 1b. Older real saves (pre-26) migrate and then journal normally.
func case_legacy_fixture() -> void:
	var repo := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var ran := 0
	for rel in ["work/depths/journey-complete.json", "work/weather/bakery-network/world-final.json"]:
		var source := repo.path_join(rel)
		if not FileAccess.file_exists(source):
			print("UNVERIFIED legacy fixture missing: " + rel)
			continue
		var copy := sandbox.path_join("legacy-%d.json" % ran)
		var bytes := FileAccess.get_file_as_bytes(source)
		var f := FileAccess.open(copy, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		ran += 1
		var w = World.new()
		expect(w.load_world(copy) and not w.recovered_from_backup, "Legacy fixture loads: " + rel)
		expect(not w.state.has("ledger"), "Legacy fixture gains no ledger on load: " + rel)
		if w.state.get("players", {}).is_empty():continue
		var tok: String = w.state.players.keys()[0]
		pose(w, tok, SPOT)
		place(w, CELL, "chest", tok, {})
		set_held(w, tok, "wood", 4)
		var r := act(w, tok, "deposit", CELL, "wood", "legacy-%d" % ran)
		expect(r.get("ok", false) and entries(w).size() == 1, "Legacy world journals its first deposit: " + rel)
		var again = World.new()
		expect(again.load_world(copy) and canon(again.state.get("ledger")) == canon(w.state.get("ledger")), "Migrated legacy save reloads with ledger: " + rel)
		expect(int(again.state.version) == Schema.VERSION, "Legacy save stamped current version: " + rel)
		remove_save(copy)
	expect(ran > 0, "At least one legacy fixture was exercised")

## 2. Malformed ledger roots reject the whole save (loader then uses .bak).
func case_malformed() -> void:
	var w = fresh()
	set_held(w, "alice", "wood", 6)
	act(w, "alice", "deposit", CELL, "wood")
	act(w, "alice", "deposit", CELL, "wood")
	set_held(w, "bob", "wood", 0)
	act(w, "bob", "deposit", CELL, "wood")  # refused -> pending rejection
	act(w, "alice", "deposit", CELL, "wood")
	var good := json_copy(w.state)
	expect(schema_ok(json_copy(good)), "Positive control: valid ledger passes schema")
	expect(rejects(w).size() == 1, "Pending rejection persisted by the next commit")
	var mutations := {
		"root not dict": func(s): s.ledger = [],
		"missing seq": func(s): s.ledger.erase("seq"),
		"missing rejected": func(s): s.ledger.erase("rejected"),
		"extra root key": func(s): s.ledger.extra = 1,
		"seq fractional": func(s): s.ledger.seq = 1.5,
		"seq negative": func(s): s.ledger.seq = -1,
		"dropped negative": func(s): s.ledger.dropped = -1,
		"entries not array": func(s): s.ledger.entries = {},
		"entry missing rid": func(s): s.ledger.entries[0].erase("rid"),
		"entry raw token key": func(s): s.ledger.entries[0].token = "alice",
		"entry seq not increasing": func(s): s.ledger.entries[1].seq = s.ledger.entries[0].seq,
		"entry seq beyond root": func(s): s.ledger.entries[-1].seq = float(s.ledger.seq) + 5.0,
		"by not hex": func(s): s.ledger.entries[0].by = "ZZZZZZZZZZZZZZZZ",
		"by too short": func(s): s.ledger.entries[0].by = "abc",
		"rid too long": func(s): s.ledger.entries[0].rid = "a".repeat(25),
		"kind unknown": func(s): s.ledger.entries[0].kind = "gift",
		"ok false in entries": func(s): s.ledger.entries[0].ok = false,
		"c beyond committed": func(s): s.ledger.entries[0].c = float(s.committed) + 1.0,
		"items fractional": func(s): s.ledger.entries[0].d.values()[0].items = {"wood": 1.5},
		"box cell malformed": func(s): s.ledger.entries[0].box[0].cell = "a,b",
		"box region unknown": func(s): s.ledger.entries[0].box[0].r = "atlantis",
		"reason too long": func(s): s.ledger.rejected[0].reason = "x".repeat(49),
		"rejected carries d": func(s): s.ledger.rejected[0].d = {},
	}
	for label in mutations:
		var candidate := json_copy(good)
		(mutations[label] as Callable).call(candidate)
		expect(not schema_ok(candidate), "Malformed ledger rejected: " + label)
	# Capacity: CAP+1 otherwise-valid rows (fresh seq) are rejected; CAP rows pass.
	for size in [Ledger.CAP + 1, Ledger.CAP]:
		var candidate := json_copy(good)
		var template: Dictionary = candidate.ledger.entries[0]
		var list: Array = []
		for i in range(size):
			var row := template.duplicate(true)
			row.seq = i + 1
			list.append(row)
		candidate.ledger.entries = list
		candidate.ledger.rejected = []
		candidate.ledger.dropped = 0
		candidate.ledger.seq = size
		expect(schema_ok(candidate) == (size == Ledger.CAP), "Capacity bound enforced at %d rows" % size)
	# .bak fallback: the loader recovers the last good file.
	var path := sandbox.path_join("malformed.json")
	w.save_path = path
	expect(w.save() and w.save(), "Main and .bak written")
	var bad := json_copy(w.state)
	bad.ledger.seq = -3
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(bad))
	f.close()
	var back = World.new()
	expect(back.load_world(path) and back.recovered_from_backup, "Corrupt ledger falls back to .bak")
	var expected := json_copy(w.state)
	expect(schema_ok(expected), "Good copy remains valid after JSON round trip")
	expect(canon(back.state.get("ledger")) == canon(expected.get("ledger")), "Recovered ledger equals the good copy")
	remove_save(path)
	for name in DirAccess.get_files_at(sandbox):
		if name.begins_with("malformed.json.rejected-"):DirAccess.remove_absolute(sandbox.path_join(name))

## 3. Resending a committed request: same receipt, one row, one effect.
## Failed then retried: one rejection, then exactly one committed row.
func case_resend() -> void:
	var w = fresh()
	set_held(w, "alice", "wood", 8)
	var first := act(w, "alice", "deposit_half", CELL, "wood", "dup-1")
	for i in range(3):
		expect(act(w, "alice", "deposit_half", CELL, "wood", "dup-1") == first, "Resend returns the stored receipt")
	expect(act(w, "alice", "withdraw_all", CELL, "wood", "dup-1") == first, "Resend with other arguments still returns the first receipt")
	expect(held(w, "alice", "wood") == 4 and stored(w, CELL, "wood") == 4, "Effect applied exactly once")
	expect(by_rid(w, "dup-1").size() == 1 and entries(w).size() == 1, "Exactly one journal row for the request")
	set_held(w, "alice", "stone", 0)
	var refused := act(w, "alice", "deposit", CELL, "stone", "ft-1")
	expect(not refused.get("ok", true) and not w.state.players.alice.receipts.has("ft-1"), "Refused request stores no receipt")
	set_held(w, "alice", "stone", 2)
	var ok := act(w, "alice", "deposit", CELL, "stone", "ft-1")
	expect(ok.get("ok", false) and by_rid(w, "ft-1").size() == 1, "Retry after refusal commits once")
	var rej := rejects(w).filter(func(e): return e.get("rid") == Ledger.rid("ft-1"))
	expect(rej.size() == 1 and rej[0].get("ok") == false and rej[0].get("act") == "deposit", "Refusal recorded once as rejected")
	expect(act(w, "alice", "deposit", CELL, "stone", "ft-1") == ok and by_rid(w, "ft-1").size() == 1 and stored(w, CELL, "stone") == 1, "Second resend is a no-op")
	var keys_ok := true
	for e in entries(w):
		var keys: Array = []
		for key in e.keys():keys.append(str(key))
		keys.sort()
		var want: Array = Ledger.COMMITTED_KEYS.duplicate()
		want.sort()
		if keys != want:
			keys_ok = false
	expect(keys_ok, "Committed rows have exactly the documented keys")
	expect(no_secrets(w.state.get("ledger"), ["alice", "bob", "dup-1", "ft-1"]), "Ledger holds no raw token or raw request id")

## 4. Trade, chest partial, shipping sale, purchase, crafting: one row each,
## deltas equal the observed inventory/coin changes.
func case_economy_rows() -> void:
	# Trade (same flow as test_trade_world).
	var w = World.new()
	for t in ["alice", "bob"]:
		w.add_player(t, t)
		w.state.players[t].inventory.wood = 4  # PRESET
	expect(act(w, "alice", "trade_open", Vector2i.ZERO, "bob", "offer").get("ok", false), "Trade opened")
	act(w, "alice", "trade_edit", Vector2i.ZERO, JSON.stringify({"offer": "offer", "items": [["wood", 2]], "coins": 0}))
	act(w, "bob", "trade_edit", Vector2i.ZERO, JSON.stringify({"offer": "offer", "items": [], "coins": 12}))
	var confirmation := JSON.stringify({"offer": "offer", "revision": 2})
	act(w, "alice", "trade_confirm", Vector2i.ZERO, confirmation)
	expect(entries(w).is_empty(), "Open/edit/first confirm move nothing and write no committed row")
	expect(act(w, "bob", "trade_confirm", Vector2i.ZERO, confirmation, "settle").get("ok", false), "Trade settles")
	act(w, "bob", "trade_confirm", Vector2i.ZERO, confirmation, "settle")
	expect(entries(w).size() == 1, "Settled trade journaled once, retry adds none")
	var e := last_entry(w)
	expect(e.get("kind") == "trade" and e.get("by") == pid("bob"), "Trade row kind and actor")
	expect(int(row_items(e, "alice").get("wood", 0)) == -2 and row_coins(e, "alice") == 12, "Trade row: alice -2 wood +12 coins")
	expect(int(row_items(e, "bob").get("wood", 0)) == 2 and row_coins(e, "bob") == -12, "Trade row: bob +2 wood -12 coins")
	expect(held(w, "alice", "wood") == 2 and held(w, "bob", "wood") == 6 and coins(w, "alice") == 132 and coins(w, "bob") == 108, "Trade row matches inventories")
	# Chest partial access.
	w = fresh()
	set_stored(w, CELL, "wood", 7)
	var before := held(w, "alice", "wood")
	expect(act(w, "alice", "withdraw_half", CELL, "wood").get("ok", false), "withdraw_half commits")
	e = last_entry(w)
	expect(e.get("kind") == "container" and int(box_items(e, CELL).get("wood", 0)) == -4 and int(row_items(e, "alice").get("wood", 0)) == 4, "Partial withdraw row: box -4, backpack +4")
	expect(held(w, "alice", "wood") == before + 4 and stored(w, CELL, "wood") == 3, "Partial withdraw row matches state")
	# Shipping sale.
	w = fresh()
	var actor: Dictionary = w.state.players.alice
	actor.x = Shipping.CELL.x + 0.5  # PRESET
	actor.y = Shipping.CELL.y + 0.5  # PRESET
	actor.inventory.radish = 4  # PRESET
	var lines := [["radish", 2], ["wood", 3]]
	var prices := Shipping.prices(World.CROPS, World.FISH, World.OTHER_SALES)
	var quote := Shipping.quote(lines, actor.inventory, prices)
	var coins_before := coins(w, "alice")
	var sold := act(w, "alice", "ship", Shipping.CELL, JSON.stringify([lines, int(quote.get("total", 0))]))
	expect(sold.get("ok", false), "Shipment commits")
	e = last_entry(w)
	expect(e.get("kind") == "sale" and row_coins(e, "alice") == coins(w, "alice") - coins_before and row_coins(e, "alice") > 0, "Sale row coins equal wallet change")
	expect(int(row_items(e, "alice").get("radish", 0)) == -2 and int(row_items(e, "alice").get("wood", 0)) == -3 and not e.d.has(pid("bob")), "Sale row items exact, neighbour absent")
	# Purchase at the seed stall.
	pose(w, "alice", Vector2(SHOP_CELL.x + 0.5, SHOP_CELL.y + 1.5))
	coins_before = coins(w, "alice")
	var bought := act(w, "alice", "buy", SHOP_CELL, "radish")
	expect(bought.get("ok", false), "Seed purchase commits")
	e = last_entry(w)
	expect(e.get("kind") == "purchase" and row_coins(e, "alice") == coins(w, "alice") - coins_before and int(row_items(e, "alice").get("radish_seed", 0)) == 1, "Purchase row matches wallet and seed")
	# Crafting with ingredient deduction.
	w = fresh()
	w.state.objects[World.key(BENCH_CELL)] = {"type": "bench", "owner": "alice"}  # PRESET
	set_held(w, "alice", "wood", 6)
	set_held(w, "alice", "stone", 4)
	set_held(w, "alice", "fiber", 2)
	var crafted := act(w, "alice", "craft", BENCH_CELL, "reinforced_pick")
	expect(crafted.get("ok", false), "Crafting commits")
	e = last_entry(w)
	var got := row_items(e, "alice")
	expect(e.get("kind") == "craft" and int(got.get("wood", 0)) == -6 and int(got.get("stone", 0)) == -4 and int(got.get("fiber", 0)) == -2 and int(got.get("reinforced_pick", 0)) == 1, "Craft row: ingredients out, product in")
	expect(held(w, "alice", "wood") == 0 and held(w, "alice", "reinforced_pick") == 1, "Craft row matches inventory")
	# Classification rules on synthetic home-oriented states (pure function).
	var s0 := {"players": {"alice": {"coins": 10, "inventory": {"wood": 5}}}, "objects": {}, "regions": {}}
	var s1 := s0.duplicate(true)
	s1.players.alice.inventory.wood = 4
	expect(Ledger.committed_entry("build", "alice", "b-1", s0, s1).is_empty(), "Routine build spending is not journaled")
	expect(Ledger.committed_entry("cook", "alice", "c-1", s0, s1).get("kind") == "consume", "Ingredient deduction is journaled as consume")
	var s2 := s0.duplicate(true)
	s2.players.alice.inventory.wood = 9
	expect(Ledger.committed_entry("harvest", "alice", "h-1", s0, s2).is_empty(), "Pure self gain is not journaled")

## 5. Save fault: no partial state, no row, no receipt; retry after recovery and
## after restart applies once.
func case_save_fault() -> void:
	var path := sandbox.path_join("fault.json")
	var w = fresh()
	w.save_path = path
	set_held(w, "alice", "wood", 6)
	expect(act(w, "alice", "deposit", CELL, "wood", "pre").get("ok", false), "Pre-fault commit saved")
	var pristine: Dictionary = w.state.duplicate(true)
	w.save_path = sandbox.path_join("missing").path_join("world.json")
	var failed := act(w, "alice", "withdraw_half", CELL, "wood", "sf-1")
	expect(not failed.get("ok", true) and failed.get("message") == SAVE_FAILED, "Save fault reports failure")
	expect(w.state == pristine, "Save fault leaves no partial state, row or receipt")
	w.save_path = path
	var cold = World.new()
	expect(cold.load_world(path), "Restart after fault loads")
	expect(by_rid(cold, "sf-1").is_empty() and not cold.state.players.alice.receipts.has("sf-1"), "Restart has no trace of the failed commit")
	expect(stored(cold, CELL, "wood") == 1 and held(cold, "alice", "wood") == 5, "Restart has pre-fault counts")
	pose(cold, "alice", SPOT)
	var retried := act(cold, "alice", "withdraw_half", CELL, "wood", "sf-1")
	expect(retried.get("ok", false) and by_rid(cold, "sf-1").size() == 1, "Retry after restart commits once")
	var save_rejects := rejects(cold).filter(func(r): return r.get("rid") == Ledger.rid("sf-1"))
	expect(save_rejects.is_empty(), "Rejection pending in the crashed process is not resurrected")
	var again = World.new()
	expect(again.load_world(path), "Reload after retry")
	var persisted := act(again, "alice", "withdraw_half", CELL, "wood", "sf-1")
	expect(persisted.get("ok", false) and persisted.get("message") == retried.get("message"), "Persisted retry returns the stored receipt")
	expect(by_rid(again, "sf-1").size() == 1 and stored(again, CELL, "wood") == 0, "No duplicate effect or row after restart")
	# In-process fault followed by success keeps the save-failure rejection.
	var w2 = fresh()
	w2.save_path = sandbox.path_join("missing2").path_join("world.json")
	set_held(w2, "alice", "wood", 2)
	act(w2, "alice", "deposit", CELL, "wood", "sf-2")
	expect(not w2.state.has("ledger"), "Failed first commit creates no ledger")
	w2.save_path = ""
	expect(act(w2, "alice", "deposit", CELL, "wood", "sf-2").get("ok", false), "Same id commits after recovery")
	var reasons := rejects(w2).filter(func(r): return r.get("rid") == Ledger.rid("sf-2") and r.get("reason") == SAVE_FAILED.left(Ledger.REASON_MAX))
	expect(reasons.size() == 1 and by_rid(w2, "sf-2").size() == 1, "Save failure journaled as rejection, success journaled once")
	remove_save(path)

## 6. Capacity and rotation.
func case_rotation() -> void:
	var w = fresh()
	set_held(w, "alice", "wood", 1)
	var extra := 7
	for i in range(Ledger.CAP + extra):
		act(w, "alice", "deposit" if i % 2 == 0 else "withdraw", CELL, "wood", "rot-%d" % i)
	var list := entries(w)
	var root := ledger(w)
	expect(list.size() == Ledger.CAP and int(root.get("dropped", 0)) == extra, "Entries capped, dropped counts rotation")
	expect(int(root.get("seq", 0)) == Ledger.CAP + extra and int(list[0].get("seq", 0)) == extra + 1, "Oldest rows rotated out first")
	var contiguous := true
	for i in range(1, list.size()):
		if int(list[i].seq) != int(list[i - 1].seq) + 1:contiguous = false
	expect(contiguous, "Sequence numbers stay contiguous")
	expect(w.state.players.alice.receipts.size() <= 128, "Receipt dedupe window stays 128")
	set_held(w, "alice", "stone", 0)
	for i in range(Ledger.REJECT_CAP + 5):
		act(w, "alice", "deposit", CELL, "stone", "rej-%d" % i)
	set_held(w, "alice", "wood", 1)
	expect(act(w, "alice", "deposit", CELL, "wood", "flush").get("ok", false), "Flush commit succeeds")
	expect(rejects(w).size() == Ledger.REJECT_CAP, "Rejections capped separately")
	expect(entries(w).size() == Ledger.CAP, "Rejection flood never evicts committed rows beyond rotation")
	expect(schema_ok(json_copy(w.state)), "Ledger at capacity is a valid save")

## 7. Two players on the same chest + the same request id, 100 rounds.
func case_race() -> void:
	var w = fresh()
	set_held(w, "alice", "wood", 50)
	set_held(w, "bob", "wood", 50)
	set_stored(w, CELL, "wood", 50)
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	var negative := false
	var conserved := true
	var committed_ids := {}
	for i in range(100):
		for t in ["alice", "bob"]:
			var id := "%s-%d" % [t, i]
			var r := act(w, t, "deposit_half" if rng.randi() % 2 == 0 else "withdraw_half", CELL, "wood", id)
			if r.get("ok", false):committed_ids[id] = true
		act(w, "alice" if i % 2 == 0 else "bob", "withdraw", CELL, "wood", "race-1")
		if held(w, "alice", "wood") < 0 or held(w, "bob", "wood") < 0 or stored(w, CELL, "wood") < 0:negative = true
		if held(w, "alice", "wood") + held(w, "bob", "wood") + stored(w, CELL, "wood") != 150:conserved = false
	expect(not negative, "No negative counts under contention")
	expect(conserved, "Wood conserved across 100 contended rounds")
	# Receipts are per player: "race-1" is one request for alice and one for bob.
	for t in ["alice", "bob"]:
		expect(by_rid(w, "race-1").filter(func(e): return e.get("by") == pid(t)).size() <= 1, "Repeated request id journaled at most once for " + t)
	var sums := {"alice": 0, "bob": 0, "box": 0}
	for e in entries(w):
		sums.alice += int(row_items(e, "alice").get("wood", 0))
		sums.bob += int(row_items(e, "bob").get("wood", 0))
		sums.box += int(box_items(e, CELL).get("wood", 0))
	expect(sums.alice == held(w, "alice", "wood") - 50 and sums.bob == held(w, "bob", "wood") - 50 and sums.box == stored(w, CELL, "wood") - 50, "Journal deltas reconstruct final counts")
	var ok_rows := 0
	for e in entries(w):
		if e.get("rid") != Ledger.rid("race-1"):ok_rows += 1
	expect(ok_rows == committed_ids.size(), "One row per committed request id")

## 8. Visibility: private box details only for the owner.
func case_visibility() -> void:
	var w = fresh(["alice", "bob", "carol"])
	place(w, PRIVATE_CELL, "private_chest", "alice", {})
	set_held(w, "alice", "stone", 3)
	act(w, "alice", "deposit", PRIVATE_CELL, "stone", "priv-1")
	set_held(w, "alice", "wood", 3)
	act(w, "alice", "deposit", CELL, "wood", "shared-1")
	expect(not act(w, "bob", "withdraw", PRIVATE_CELL, "stone", "steal-1").get("ok", true), "Bob cannot open alice's private box")
	var private_rid := Ledger.rid("priv-1")
	var alice_view: Array = w.ledger_view("alice")
	var bob_view: Array = w.ledger_view("bob")
	var carol_view: Array = w.ledger_view("carol")
	expect(alice_view.any(func(e): return e.get("rid") == private_rid), "Owner sees her private box row")
	expect(not bob_view.any(func(e): return e.get("rid") == private_rid), "Other player cannot see private box row")
	expect(not carol_view.any(func(e): return e.get("rid") == private_rid), "Third player cannot see private box row")
	expect(carol_view.any(func(e): return e.get("rid") == Ledger.rid("shared-1")), "Shared chest rows are visible to members")
	var leaked := false
	for e in carol_view:
		if e.get("rid") == Ledger.rid("shared-1") and e.get("d", {}).has(pid("alice")):leaked = true
	expect(not leaked, "Non-actor viewer does not receive the actor's backpack delta")
	expect(not bob_view.any(func(e): return e.get("ok") == false and e.get("by") != pid("bob")), "Rejections only visible to their actor")
	expect(w.ledger_view("stranger").is_empty(), "Unknown token gets nothing")
	if not alice_view.is_empty():alice_view[0].kind = "tampered"
	expect(not entries(w).any(func(e): return e.get("kind") == "tampered"), "View returns copies")
	expect(no_secrets([alice_view, bob_view, carol_view], ["alice", "bob", "carol", "priv-1", "shared-1"]), "Views carry no raw token or request id")

## 9. Invalid request ids are refused without receipt, row or rejection.
func case_request_ids() -> void:
	var w = fresh()
	set_held(w, "alice", "wood", 3)
	for id in ["", "x".repeat(81)]:
		var committed := int(w.state.committed)
		var r = w.act("alice", id, "deposit", CELL, "wood")
		expect(r is Dictionary and not r.get("ok", true) and int(w.state.committed) == committed and not w.state.has("ledger"), "Invalid request id refused cleanly (len %d)" % id.length())
	var boundary := "y".repeat(80)
	expect(act(w, "alice", "deposit", CELL, "wood", boundary).get("ok", false) and by_rid(w, boundary).size() == 1, "80-character id accepted and journaled")
	expect(rejects(w).is_empty(), "Invalid ids never reach the rejection journal")

## 10. Snapshots never carry the ledger.
func case_snapshot() -> void:
	var session := Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	var w = fresh()
	session.world = w
	session.peers = {1: "alice", 2: "bob"}
	set_held(w, "alice", "wood", 3)
	act(w, "alice", "deposit", CELL, "wood", "snap-1")
	set_held(w, "bob", "stone", 0)
	act(w, "bob", "deposit", CELL, "stone", "snap-2")
	act(w, "alice", "deposit", CELL, "wood", "snap-3")
	var before := canon(w.state)
	var public: Dictionary = session.public_state("home")
	expect(not public.has("ledger") and not w.region_snapshot("home").has("ledger"), "Public state and region snapshot drop the ledger")
	expect(no_secrets(public, [Ledger.rid("snap-1"), Ledger.rid("snap-2")]), "No journal row leaks into the public snapshot")
	expect(canon(w.state) == before, "Building snapshots does not touch the ledger")
	session.queue_free()
