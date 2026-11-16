extends SceneTree
## Focused tests for scripts/fishing_pity.gd plus a parity check against the
## live rules in Collections.fishing_result and the inline World fish_catch path.
## Run: godot --headless --path game --script res://tests/test_fishing_pity.gd

const Pity := preload("res://scripts/fishing_pity.gd")
const Collections := preload("res://scripts/collections.gd")
const World := preload("res://scripts/world.gd")
const CANAL := Vector2i(33, 26)

const EXPECTED_FISH := ["bamboo_ayu","carp","flounder","glass_shrimp","gold_shrimp","loach","minnow","moon_squid","redfish","sardine","snow_trout","star_spot"]
const EXPECTED_WATERS := {
	"bamboo_grove": ["bamboo_ayu", "bamboo_ayu_misses"],
	"beimen": ["flounder", "beimen_flounder_misses"],
	"jiaoxi": ["snow_trout", "jiaoxi_trout_misses"],
	"lanyang": ["loach", "rare_fishing_misses"],
	"star_garden": ["star_spot", "star_spot_misses"],
}

var checks := 0
var failures := 0
var sequence := 0


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)


func _initialize() -> void:
	catalog()
	sanitizing()
	eligibility()
	parity()
	progression()
	isolation()
	failed_actions()
	world_inline()
	print("FISHING_PITY_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))


func catalog() -> void:
	var ids: Array = Collections.FISH.keys()
	ids.sort()
	expect(ids == EXPECTED_FISH, "Fish catalog keeps the twelve current IDs: %s" % [ids])
	expect(Pity.regions() == EXPECTED_WATERS.keys(), "Pity covers exactly the five rare waters")
	for region in EXPECTED_WATERS:
		expect(Pity.rare_fish_for(region) == EXPECTED_WATERS[region][0], "Rare fish ID unchanged for " + region)
		expect(Pity.counter_for(region) == EXPECTED_WATERS[region][1], "Save counter key unchanged for " + region)
		expect(Collections.FISH.has(Pity.rare_fish_for(region)), "Rare fish exists in catalog for " + region)
	expect(Pity.counter_for("home") == "" and Pity.rare_fish_for("jinguashi") == "", "Waters without pity have no counter")
	expect(Pity.LIMIT == 20 and Pity.MAX_MISSES == 19, "Guarantee on 20th eligible catch")


func sanitizing() -> void:
	for good in [0, 1, 19, 19.0, 7.0]:
		expect(Pity.valid_misses(good) and Pity.sanitize_misses(good) == int(good), "Valid misses accepted: %s" % [good])
	for bad in [-1, 20, 7.5, "5", true, null, INF, -INF, NAN, 1000000000, [], {}]:
		expect(not Pity.valid_misses(bad) and Pity.sanitize_misses(bad) == 0, "Invalid misses read as zero: %s" % [bad])
	var raw := {"rare_fishing_misses": 4.0, "star_spot_misses": "19", "jiaoxi_trout_misses": 25, "coins": 999, "fishing": {"x": 1}}
	var before := raw.duplicate(true)
	var clean := Pity.sanitize(raw)
	expect(raw == before, "sanitize does not mutate the player")
	expect(clean.keys().size() == 5 and clean.keys().all(func(k): return k in Pity.counters()), "sanitize keeps only the five counters")
	expect(clean.values().all(func(v): return v is int), "sanitize returns ints after JSON-float reload")
	expect(clean.rare_fishing_misses == 4 and clean.star_spot_misses == 0 and clean.jiaoxi_trout_misses == 0 and clean.bamboo_ayu_misses == 0, "sanitize values")
	expect(Pity.sanitize(null) == Pity.sanitize({}) and Pity.sanitize({}).values().all(func(v): return v == 0), "Non-dictionary players sanitize to zeros")
	expect(Pity.sanitize({"beimen_fishing_misses": 12}).beimen_flounder_misses == 12, "Legacy Beimen counter folds in")
	expect(Pity.sanitize({"beimen_fishing_misses": 12, "beimen_flounder_misses": 3}).beimen_flounder_misses == 3, "Modern counter wins over legacy")
	expect(Pity.valid_state({"rare_fishing_misses": 19.0}) and Pity.valid_state({}), "valid_state accepts sane saves")
	expect(not Pity.valid_state({"star_spot_misses": 20}) and not Pity.valid_state({"beimen_fishing_misses": -1}) and not Pity.valid_state("x"), "valid_state rejects bad counters like save_schema")
	var legacy := {"beimen_fishing_misses": 9}
	expect(Pity.migrate(legacy) and legacy == {"beimen_flounder_misses": 9}, "migrate renames legacy counter")
	var both := {"beimen_fishing_misses": 9, "beimen_flounder_misses": 2}
	expect(Pity.migrate(both) and both == {"beimen_flounder_misses": 2}, "migrate keeps modern value and drops legacy")
	var broken := {"beimen_fishing_misses": 40}
	expect(not Pity.migrate(broken) and broken == {"beimen_fishing_misses": 40}, "migrate refuses invalid legacy without mutating")


func eligibility() -> void:
	expect(Pity.eligible("lanyang", "autumn") and Pity.eligible("lanyang", "spring", 720.0, "coast", true), "Canal: autumn or rain")
	expect(not Pity.eligible("lanyang", "spring") and not Pity.eligible("home", "autumn", 720.0, "coast", true), "Canal dry spring / home rain ineligible")
	expect(Pity.eligible("beimen", "summer", 1300.0) and Pity.eligible("beimen", "summer", 100.0), "Beimen coast at night")
	expect(not Pity.eligible("beimen", "summer", 720.0), "Beimen day gives sardine without pity")
	expect(not Pity.eligible("beimen", "summer", 1300.0, "pier") and not Pity.eligible("beimen", "summer", 1300.0, "tidepool"), "Pier/tidepool never use flounder pity")
	expect(Pity.eligible("jiaoxi", "winter", 720.0, "upland") and not Pity.eligible("jiaoxi", "summer", 720.0, "upland") and not Pity.eligible("jiaoxi", "winter", 100.0, "spring"), "Cold pool only in winter")
	expect(Pity.eligible("bamboo_grove", "spring", 360.0) and not Pity.eligible("bamboo_grove", "spring", 660.0) and not Pity.eligible("bamboo_grove", "spring", 359.0), "Bamboo 06:00-11:00 breeze")
	expect(Pity.eligible("star_garden", "spring", 1200.0) and not Pity.eligible("star_garden", "spring", 720.0), "Star pool at night")
	expect(not Pity.eligible("jinguashi", "autumn", 1300.0, "upland", true), "Unknown regions never eligible")


## Exhaustive grid: the standalone rules must agree with the live function.
func parity() -> void:
	var minutes := [0.0, 359.0, 360.0, 659.0, 660.0, 720.0, 1199.0, 1200.0, 1439.0]
	var spots := ["coast", "tidepool", "pier", "spring", "upland"]
	for region in ["home", "lanyang", "beimen", "jiaoxi", "bamboo_grove", "star_garden"]:
		var mismatches := 0
		var first := ""
		var cases := 0
		for season in ["spring", "summer", "autumn", "winter"]:
			for minute in minutes:
				for spot in spots:
					for raining in [false, true]:
						for total in [0, 1, 21, 22, 45]:
							for misses in [0, 5, 18, 19]:
								cases += 1
								var person := {}
								for counter in Pity.counters():
									person[counter] = misses
								var live := Collections.fishing_result(region, season, total, person, minute, spot, raining)
								var mine := Pity.resolve(region, season, total, person, minute, spot, raining)
								var same: bool = live.has("counter") == mine.eligible
								if same and mine.eligible:
									same = live.counter == mine.counter and int(live.misses) == mine.misses and (live.id == mine.fish) == mine.hit
								if not same:
									mismatches += 1
									if first.is_empty():
										first = "%s/%s/%s/%s/%s/%s/%s live=%s mine=%s" % [region, season, minute, spot, raining, total, misses, live, mine]
		expect(mismatches == 0, "Parity with Collections.fishing_result for %s (%d cases) %s" % [region, cases, first])


func progression() -> void:
	var runs := []
	for attempt in 2:
		var person := {}
		var trace := []
		for total in range(LIMIT_SAFE_TOTAL_START, LIMIT_SAFE_TOTAL_START + 20):
			var outcome := Pity.resolve("lanyang", "autumn", total, person)
			expect(Pity.commit(person, outcome, true), "Eligible landed catch commits")
			trace.append([outcome.hit, person.rare_fishing_misses])
		runs.append(trace)
	expect(runs[0] == runs[1], "Same inputs give identical progression")
	var steps: Array = runs[0]
	var climbing := true
	for index in 19:
		climbing = climbing and steps[index] == [false, index + 1]
	expect(climbing, "Nineteen eligible misses count 1..19")
	expect(steps[19] == [true, 0], "Twentieth eligible catch is the rare and resets")
	expect(Pity.catches_until_guarantee({"rare_fishing_misses": 19}, "lanyang") == 1 and Pity.catches_until_guarantee({}, "lanyang") == 20, "Remaining-catch hint")
	var lucky := Pity.resolve("star_garden", "spring", 22, {"star_spot_misses": 3}, 1300.0)
	expect(lucky.hit and lucky.misses == 0 and lucky.fish == "star_spot", "Lucky 23rd lifetime catch hits early")
	var paused := {"star_spot_misses": 19}
	var day := Pity.resolve("star_garden", "spring", 0, paused, 720.0)
	expect(not day.eligible and not Pity.commit(paused, day, true) and paused.star_spot_misses == 19, "Ineligible catches preserve progress")


## Chosen so totals 0..19 never hit total%23==22 and only the limit can fire.
const LIMIT_SAFE_TOTAL_START := 0


func isolation() -> void:
	var alice := {"rare_fishing_misses": 5, "beimen_flounder_misses": 11}
	var bob := {"rare_fishing_misses": 5}
	var bob_before := bob.duplicate(true)
	var outcome := Pity.resolve("lanyang", "autumn", 0, alice)
	expect(Pity.commit(alice, outcome, true) and alice.rare_fishing_misses == 6, "Alice advances")
	expect(bob == bob_before, "Bob is untouched by Alice's commit")
	expect(alice.beimen_flounder_misses == 11, "Canal catch leaves Beimen counter alone")
	var bob_outcome := Pity.resolve("lanyang", "autumn", 0, bob)
	expect(bob_outcome.misses == 6 and outcome.misses == 6, "Equal inputs, independent results")
	var shared := {"rare_fishing_misses": 2}
	var forked := Pity.resolve("lanyang", "autumn", 0, shared)
	shared.rare_fishing_misses = 18
	expect(forked.misses == 3, "Outcome does not alias the player dictionary")


func failed_actions() -> void:
	var person := {"rare_fishing_misses": 19}
	var outcome := Pity.resolve("lanyang", "autumn", 0, person)
	expect(outcome.hit and not Pity.commit(person, outcome, false) and person.rare_fishing_misses == 19, "Failed catch spends no guarantee")
	expect(not Pity.commit(person, {"eligible": false}, true) and person.rare_fishing_misses == 19, "Ineligible outcome writes nothing")
	expect(not Pity.commit(person, {"eligible": true, "counter": "coins", "misses": 0}, true) and not person.has("coins"), "Unknown counter rejected")
	expect(not Pity.commit(person, {"eligible": true, "counter": "rare_fishing_misses", "misses": 25}, true) and person.rare_fishing_misses == 19, "Out-of-range misses rejected")
	expect(not Pity.commit(person, {}, true) and person == {"rare_fishing_misses": 19}, "Empty outcome rejected")


func reel(w, actor: String, action: String, cell: Vector2i = CANAL) -> Dictionary:
	sequence += 1
	return w.act(actor, "pity-%s-%d" % [actor, sequence], action, cell)


## Exercises the CURRENT inline World path and checks it matches the module.
func world_inline() -> void:
	var w = World.new()
	for actor in ["alice", "bob"]:
		w.add_player(actor, actor)
		var person: Dictionary = w.state.players[actor]
		person.region = "lanyang"
		person.x = 32.5
		person.y = 26.5
		person.fish_caught = 0
	w.state.time = 2 * World.WEATHER.DAYS_PER_SEASON * World.WEATHER.DAY_SECONDS
	var alice: Dictionary = w.state.players.alice
	var bob: Dictionary = w.state.players.bob
	expect(World.WEATHER.season_on_day(World.WEATHER.day_index(float(w.state.time))) == "autumn", "World clock is autumn")
	var counter := "rare_fishing_misses"
	expect(not reel(w, "alice", "fish_catch").ok and int(alice.get(counter, 0)) == 0, "Reel without cast fails, no pity")
	expect(reel(w, "alice", "fish_start").ok, "Alice casts")
	expect(not reel(w, "alice", "fish_catch").ok and int(alice.get(counter, 0)) == 0, "Early reel fails, no pity")
	w.step(3.1, true)
	expect(not reel(w, "alice", "fish_catch", CANAL + Vector2i(1, 0)).ok and int(alice.get(counter, 0)) == 0, "Reel at another cell fails, no pity")
	var predicted := Pity.resolve("lanyang", "autumn", int(alice.fish_caught), alice)
	sequence += 1
	var request := "pity-alice-%d" % sequence
	var landed: Dictionary = w.act("alice", request, "fish_catch", CANAL)
	expect(landed.ok and int(alice[counter]) == predicted.misses and int(alice[counter]) == 1, "Live catch matches module prediction")
	var caught := int(alice.fish_caught)
	expect(w.act("alice", request, "fish_catch", CANAL) == landed and int(alice[counter]) == 1 and int(alice.fish_caught) == caught, "Replayed request does not advance pity")
	expect(int(bob.get(counter, 0)) == 0, "Bob's pity untouched by Alice")
	expect(reel(w, "bob", "fish_start").ok and w.step(3.1, true) and reel(w, "bob", "fish_catch").ok, "Bob lands a catch")
	expect(int(bob[counter]) == 1 and int(alice[counter]) == 1, "Each player keeps a separate counter")
	alice[counter] = 19
	expect(reel(w, "alice", "fish_start").ok and w.step(3.1, true), "Alice casts at 19")
	expect(not reel(w, "alice", "fish_catch", CANAL + Vector2i(1, 0)).ok and int(alice[counter]) == 19, "Wrong-cell reel keeps the guarantee")
	var loach := int(alice.inventory.get("loach", 0))
	expect(reel(w, "alice", "fish_catch").ok and int(alice.inventory.get("loach", 0)) == loach + 1 and int(alice[counter]) == 0, "Guarantee awards loach and resets")
	expect(int(bob[counter]) == 1, "Bob still at 1 after Alice's guarantee")
