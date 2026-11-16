extends SceneTree

## T013 item definitions and data validation (real World data, no mocks).
##
## Proves ItemCatalog (scripts/item_catalog.gd) is the one validation path for
## item IDs and per-item stack limits:
##   - the shipped catalog (= World.NAMES) loads with zero errors, keeps every
##     ID and name byte-for-byte and in order, and every limit is 1,000,000,000;
##   - duplicate IDs and negative stack limits are rejected, all-or-nothing,
##     including through a JSON text round trip;
##   - other malformed IDs / names / limits / records are rejected;
##   - the catalog agrees with SaveSchema.counts at and above the ceiling;
##   - IDs granted by shipped definitions and the on-disk legacy save fixtures
##     are all catalog IDs; unknown legacy IDs are reported, never refused.
## Legacy fixtures are only READ (FileAccess + JSON); nothing is loaded into a
## World, saved or written. A missing fixture is listed as unverified.
## Rejection paths return error records; nothing here expects engine errors.

const World = preload("res://scripts/world.gd")
const Schema = preload("res://scripts/save_schema.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const CAP := 1000000000
const LEGACY_FIXTURES := [
	"work/xiaoli/20261113-035419-645/world.json",
	"work/depths/journey-complete.json",
	"work/auto-freight/native-final-saved.json",
	"work/public-kitchen/journey-second/earned-kitchen-final.json",
	"work/weather/bakery-network/world-final.json",
	"work/salt/network/runs/20261114T054823Z/world-final.json",
]

var checks := 0
var failures := 0
var unverified: Array[String] = []

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)

func codes(result: Dictionary) -> Array:
	var out: Array = []
	for error in result.get("errors", []):
		out.append(error.code)
	return out

func rejected_with(records, code: String, label: String) -> Dictionary:
	var result: Dictionary = Catalog.load_definitions(records)
	expect(not result.ok, label + ": rejected")
	expect(code in codes(result), label + ": error code " + code + " (got " + str(codes(result)) + ")")
	expect(result.items.is_empty() and result.order.is_empty(), label + ": no partial catalog")
	return result

func one(id, name, limit = null) -> Dictionary:
	var record := {"id": id, "name": name}
	if limit != null:
		record["stack_limit"] = limit
	return record

func _initialize() -> void:
	shipped_catalog()
	duplicate_ids()
	negative_stack_limits()
	other_limits()
	ids_names_and_records()
	json_round_trip()
	save_schema_agreement()
	legacy_inventory_report()
	shipped_definitions_covered()
	fresh_world_inventory()
	legacy_fixtures()
	for note in unverified:
		print("UNVERIFIED " + note)
	print("ITEM_CATALOG checks=%d failures=%d unverified=%d" % [checks, failures, unverified.size()])
	quit(int(failures > 0))

func shipped_catalog() -> void:
	expect(Catalog.STACK_CEILING == CAP, "ceiling stays 1,000,000,000")
	expect(Catalog.ID_MAX_LENGTH == 64, "ID length limit matches SaveSchema.counts")
	var definitions: Array = Catalog.current_definitions()
	var result: Dictionary = Catalog.current()
	expect(result.ok, "shipped catalog loads")
	expect(result.errors.is_empty(), "shipped catalog has no errors: " + str(result.errors))
	expect(definitions.size() == World.NAMES.size() and result.items.size() == World.NAMES.size(), "catalog size == World.NAMES size (%d)" % World.NAMES.size())
	expect(result.order == World.NAMES.keys(), "catalog order == World.NAMES declared order")
	var same := true
	for id in World.NAMES:
		var item = result.items.get(id)
		if not item is Dictionary:
			same = false
			push_error("FAIL missing catalog id " + id)
			continue
		if String(item.name).to_utf8_buffer() != String(World.NAMES[id]).to_utf8_buffer() or int(item.stack_limit) != CAP:
			same = false
			push_error("FAIL catalog drift for " + id)
		if not Catalog.valid_id(id) or not Catalog.is_known(id) or Catalog.stack_limit(id) != CAP:
			same = false
			push_error("FAIL catalog lookup for " + id)
	expect(same, "every World.NAMES id/name byte-identical with limit 1,000,000,000")
	expect(Catalog.load_definitions(definitions) == result, "reload of shipped definitions is deterministic")
	expect(Catalog.current_definitions() == definitions, "loading did not mutate the definition records")

func duplicate_ids() -> void:
	var records: Array = Catalog.current_definitions()
	var size := records.size()
	records.append(one("wood", "另一種木材"))
	var result := rejected_with(records, Catalog.CODE_DUPLICATE_ID, "shipped set + second wood")
	var dup: Array = result.errors.filter(func(e): return e.code == Catalog.CODE_DUPLICATE_ID)
	expect(dup.size() == 1 and dup[0].index == size and dup[0].id == "wood", "duplicate reported once at the later index")
	rejected_with([one("wood", "木材"), one("wood", "木材")], Catalog.CODE_DUPLICATE_ID, "identical duplicate record")
	rejected_with([one("stone", "石材"), one("wood", "木材"), one("stone", "石材", 5)], Catalog.CODE_DUPLICATE_ID, "non-adjacent duplicate")
	var triple := rejected_with([one("fiber", "纖維"), one("fiber", "纖維"), one("fiber", "纖維")], Catalog.CODE_DUPLICATE_ID, "triple")
	expect(codes(triple).count(Catalog.CODE_DUPLICATE_ID) == 2, "every repeat after the first is reported")
	expect(Catalog.load_definitions([one("wood", "木材"), one("wood_seed", "x")]).ok, "prefix-sharing IDs are not duplicates")
	expect(Catalog.current().ok and Catalog.current().items.size() == size, "rejected loads leave the shipped catalog untouched")

func negative_stack_limits() -> void:
	for limit in [-1, -1.0, -CAP, -2147483649, -0.5]:
		var code: String = Catalog.CODE_NEGATIVE_LIMIT if float(limit) == floorf(float(limit)) else Catalog.CODE_LIMIT_NOT_WHOLE
		rejected_with([one("wood", "木材", limit)], code, "stack_limit " + str(limit))
	var records: Array = Catalog.current_definitions()
	records[records.size() - 1].stack_limit = -1
	var result := rejected_with(records, Catalog.CODE_NEGATIVE_LIMIT, "shipped set with last limit -1")
	expect(result.errors.size() == 1 and result.errors[0].index == records.size() - 1, "only the negative record is reported")

func other_limits() -> void:
	# Run 1 (Codex, 4.7.2) failed all four of these with one combined
	# `... and x is int` assertion. Split into separate checks, use the Variant
	# type API (typeof / TYPE_INT), never index a missing key, and print the
	# observed values so a failure is self-describing.
	for limit in [1, CAP, 1.0, float(CAP)]:
		var ok: Dictionary = Catalog.load_definitions([one("wood", "木材", limit)])
		var label := "stack_limit %s (%s)" % [str(limit), type_string(typeof(limit))]
		expect(ok.get("ok") == true, label + ": accepted; errors=" + str(ok.get("errors")))
		var item = ok.get("items", {}).get("wood")
		var stored = item.get("stack_limit") if item is Dictionary else null
		expect(typeof(stored) == TYPE_INT, label + ": stored as TYPE_INT (got %s %s)" % [type_string(typeof(stored)), str(stored)])
		expect(typeof(stored) == TYPE_INT and stored == int(limit), label + ": stored value == %d (got %s)" % [int(limit), str(stored)])
	expect(Catalog.load_definitions([one("wood", "木材")]).items.get("wood", {}).get("stack_limit") == CAP, "missing stack_limit means the ceiling")
	rejected_with([one("wood", "木材", 0)], Catalog.CODE_ZERO_LIMIT, "stack_limit 0")
	rejected_with([one("wood", "木材", CAP + 1)], Catalog.CODE_LIMIT_OVER_CEILING, "stack_limit ceiling+1")
	for bad in [2.5, "10", true, null, NAN, INF, [], {}]:
		rejected_with([{"id": "wood", "name": "木材", "stack_limit": bad}], Catalog.CODE_LIMIT_NOT_WHOLE, "stack_limit " + var_to_str(bad))

func ids_names_and_records() -> void:
	var long_ok := "a".repeat(64)
	expect(Catalog.load_definitions([one(long_ok, "長")]).ok, "64-char ID accepted")
	for bad in ["", "Wood", "wood-1", " wood", "wood ", "木材", "a".repeat(65), 5, null, &"wood"]:
		rejected_with([one(bad, "名")], Catalog.CODE_INVALID_ID, "id " + var_to_str(bad))
	for bad in ["", null, 3, &"名"]:
		rejected_with([one("wood", bad)], Catalog.CODE_INVALID_NAME, "name " + var_to_str(bad))
	rejected_with([{"id": "wood"}], Catalog.CODE_INVALID_NAME, "missing name")
	rejected_with([{"name": "木材"}], Catalog.CODE_INVALID_ID, "missing id")
	rejected_with([{"id": "wood", "name": "木材", "stack": 99}], Catalog.CODE_UNKNOWN_FIELD, "unknown field")
	rejected_with([one("wood", "木材"), "stone"], Catalog.CODE_NOT_RECORD, "non-dictionary record")
	rejected_with({"wood": "木材"}, Catalog.CODE_NOT_ARRAY, "Dictionary instead of Array")
	rejected_with(null, Catalog.CODE_NOT_ARRAY, "null definitions")
	var empty: Dictionary = Catalog.load_definitions([])
	expect(empty.ok and empty.items.is_empty(), "empty Array is a valid empty catalog")
	var mixed := rejected_with([one("wood", "木材", -3), one("wood", "", 5)], Catalog.CODE_NEGATIVE_LIMIT, "several faults")
	expect(Catalog.CODE_DUPLICATE_ID in codes(mixed) and Catalog.CODE_INVALID_NAME in codes(mixed), "all faults are reported, not only the first")
	var input := [one("wood", "木材", -1)]
	var copy := input.duplicate(true)
	Catalog.load_definitions(input)
	expect(input == copy, "rejected input is not mutated")

func json_round_trip() -> void:
	var text := JSON.stringify(Catalog.current_definitions())
	var parsed = JSON.parse_string(text)
	var result: Dictionary = Catalog.load_definitions(parsed)
	expect(result.ok and result.items == Catalog.current().items and result.order == Catalog.current().order, "JSON round trip keeps the catalog (float limits become int)")
	rejected_with(JSON.parse_string('[{"id":"wood","name":"木材"},{"id":"wood","name":"木材二"}]'), Catalog.CODE_DUPLICATE_ID, "JSON duplicate id")
	rejected_with(JSON.parse_string('[{"id":"wood","name":"木材","stack_limit":-1}]'), Catalog.CODE_NEGATIVE_LIMIT, "JSON negative limit")
	rejected_with(JSON.parse_string('[{"id":"wood","name":"木材","stack_limit":1e9},{"id":"stone","name":"石材","stack_limit":1000000001}]'), Catalog.CODE_LIMIT_OVER_CEILING, "JSON over ceiling")

func save_schema_agreement() -> void:
	var full := {}
	for id in Catalog.current().order:
		full[id] = Catalog.stack_limit(id)
	expect(Schema.counts(full.duplicate()), "SaveSchema.counts accepts every catalog item at its stack limit")
	expect(Catalog.inventory_report(full).ok, "inventory_report accepts every catalog item at its stack limit")
	var agree := true
	for id in Catalog.current().order:
		var limit := Catalog.stack_limit(id)
		for count in [0, 1, limit - 1, limit, limit + 1, -1, 1.5]:
			if Schema.counts({id: count}) != Catalog.can_hold(id, count):
				agree = false
				push_error("FAIL SaveSchema/Catalog disagree on %s=%s" % [id, str(count)])
	expect(agree, "SaveSchema.counts and Catalog.can_hold agree at 0/1/limit-1/limit/limit+1/-1/1.5 for every item")
	expect(not Catalog.can_hold("wood", true) and not Catalog.can_hold("wood", "3") and not Catalog.can_hold("wood", NAN), "can_hold refuses non-numbers")
	var same_limit := true
	for id in Catalog.current().order:
		if Catalog.saved_count_limit(id) != Catalog.stack_limit(id):
			same_limit = false
			push_error("FAIL saved_count_limit/stack_limit disagree on " + id)
	expect(same_limit, "saved_count_limit == stack_limit for every shipped item")
	expect(Catalog.saved_count_limit("legacy_mystery") == CAP and Catalog.saved_count_limit("") == CAP, "saved_count_limit keeps the 1e9 ceiling for unknown legacy keys (incl. the empty key counts() always accepted)")
	expect(Schema.counts({"": 2}), "SaveSchema.counts still accepts the empty key (legacy behaviour unchanged)")
	invalid_catalog_fails_closed()

## A broken shipped catalog must never make the loader permissive.
func invalid_catalog_fails_closed() -> void:
	var broken: Dictionary = Catalog.load_definitions([one("wood", "木材"), one("wood", "木材")])
	expect(not broken.ok, "fixture: duplicate catalog is rejected")
	Catalog.override_current(broken)
	var bag := {"wood": 3.0, "legacy_mystery": 1}
	expect(not Schema.counts(bag), "invalid catalog: SaveSchema.counts refuses even a normal inventory")
	expect(typeof(bag.wood) == TYPE_FLOAT, "invalid catalog: counts() rejects before normalising the dictionary")
	expect(not Schema.counts({}), "invalid catalog: even an empty inventory is refused")
	expect(Catalog.stack_limit("wood") == 0 and Catalog.stack_limit("legacy_mystery") == 0, "invalid catalog: stack_limit is 0 for known and unknown IDs")
	expect(Catalog.saved_count_limit("wood") == -1 and Catalog.saved_count_limit("legacy_mystery") == -1, "invalid catalog: saved_count_limit is -1")
	expect(not Catalog.can_hold("legacy_mystery", 1) and not Catalog.inventory_report({"wood": 1}).ok, "invalid catalog: can_hold / inventory_report fail closed")
	Catalog.reset_current()
	expect(Catalog.current().ok and Catalog.current().items.size() == World.NAMES.size(), "reset_current re-validates World.NAMES")
	expect(Schema.counts({"wood": 3}) and Catalog.stack_limit("wood") == CAP, "after reset counts() accepts again with the 1e9 limit")

func legacy_inventory_report() -> void:
	var bag := {"wood": 3, "legacy_mystery": 7}
	var report: Dictionary = Catalog.inventory_report(bag)
	expect(report.ok and report.unknown == ["legacy_mystery"] and report.over.is_empty(), "unknown legacy ID is listed, not refused")
	expect(Catalog.stack_limit("legacy_mystery") == CAP and Catalog.can_hold("legacy_mystery", CAP), "unknown legacy ID keeps the existing ceiling")
	expect(Schema.counts(bag.duplicate()), "SaveSchema.counts still accepts the unknown legacy ID")
	expect(bag == {"wood": 3, "legacy_mystery": 7}, "inventory_report does not mutate the bag")
	var over: Dictionary = Catalog.inventory_report({"wood": CAP + 1})
	expect(not over.ok and over.over == ["wood"], "count above the stack limit is reported as over")
	var invalid: Dictionary = Catalog.inventory_report({"wood": -1, "stone": 1.5, "x".repeat(65): 1, "fiber": "2"})
	expect(not invalid.ok and invalid.invalid.size() == 4 and invalid.over.is_empty(), "negative / fractional / long-key / string counts are invalid")
	expect(not Catalog.inventory_report([]).ok, "non-Dictionary bag is not ok")
	expect(Catalog.stack_limit("") == 0 and Catalog.stack_limit(5) == 0 and not Catalog.is_known(&"wood"), "keys no save could hold have no limit")

## Item IDs that shipped definitions can put into an inventory or chest.
func shipped_item_ids() -> Dictionary:
	var ids := {}
	for id in World.CRAFT:
		ids[id] = "CRAFT"
		for item in World.CRAFT[id].ingredients:
			ids[item] = "CRAFT ingredient of " + id
	for id in World.RECIPES:
		ids[id] = "RECIPES"
		for item in World.RECIPES[id].ingredients:
			ids[item] = "RECIPES ingredient of " + id
	for id in World.BUILD:
		for item in World.BUILD[id]:
			if item != "name":
				ids[item] = "BUILD cost of " + id
	for id in World.OTHER_SALES:
		ids[id] = "OTHER_SALES"
	for id in World.CROPS:
		ids[id] = "CROPS yield"
		ids[id + "_seed"] = "CROPS seed (seed_maker.gd / buy_seed)"
	for id in World.FISH:
		ids[id] = "FISH"
	return ids

func shipped_definitions_covered() -> void:
	var missing: Array = []
	var sources := shipped_item_ids()
	for id in sources:
		if not Catalog.is_known(id):
			missing.append("%s (%s)" % [id, sources[id]])
	expect(sources.size() > 100, "shipped item sources gathered (%d IDs)" % sources.size())
	expect(missing.is_empty(), "CRAFT/RECIPES/BUILD/OTHER_SALES/CROPS/FISH item IDs are catalog IDs; missing: " + str(missing))

func fresh_world_inventory() -> void:
	var world = World.new()
	world.add_player("t013", "物品")
	var bag: Dictionary = world.state.players.t013.inventory
	var report: Dictionary = Catalog.inventory_report(bag)
	expect(not bag.is_empty() and report.ok and report.unknown.is_empty(), "fresh player inventory uses only catalog IDs: " + str(report))

func legacy_fixtures() -> void:
	var repo := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").get_base_dir()
	var exercised := 0
	for rel in LEGACY_FIXTURES:
		var path: String = repo.path_join(rel)
		if not FileAccess.file_exists(path):
			unverified.append("missing legacy fixture " + rel)
			continue
		var before := FileAccess.get_sha256(path)
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		expect(data is Dictionary, rel + ": parses as a JSON object")
		if not data is Dictionary:
			continue
		var bags: Array = []
		collect_bags(data, "", bags)
		var unknown: Array = []
		var bad: Array = []
		for entry in bags:
			var report: Dictionary = Catalog.inventory_report(entry.bag)
			for id in report.unknown:
				unknown.append(entry.path + "." + id)
			if not report.ok or not Schema.counts(entry.bag.duplicate()):
				bad.append(entry.path)
		expect(not bags.is_empty(), rel + ": has item-count dictionaries")
		expect(unknown.is_empty(), rel + ": every stored item ID is a catalog ID; unknown: " + str(unknown))
		expect(bad.is_empty(), rel + ": every item-count dictionary is within stack limits: " + str(bad))
		expect(FileAccess.get_sha256(path) == before, rel + ": fixture unchanged (read only)")
		exercised += 1
	expect(exercised > 0, "at least one legacy fixture exercised")

## Every Dictionary stored under an "inventory" or "items" key whose values are
## all numbers (player bags, chest / machine contents).
func collect_bags(node, path: String, out: Array) -> void:
	if node is Dictionary:
		for key in node:
			var child = node[key]
			var child_path := path + "/" + str(key)
			if (str(key) == "inventory" or str(key) == "items") and child is Dictionary and not child.is_empty():
				var numeric := true
				for value in child.values():
					numeric = numeric and (value is int or value is float)
				if numeric:
					out.append({"path": child_path, "bag": child})
					continue
			collect_bags(child, child_path, out)
	elif node is Array:
		for i in node.size():
			collect_bags(node[i], path + "/" + str(i), out)
