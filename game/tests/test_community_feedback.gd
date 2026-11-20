extends SceneTree

# Behavioral tests for res://scripts/community_feedback.gd (pure presentation helper).
# The helper is built by a parallel worker, so it is loaded at runtime instead of
# preloaded: a missing script reports a clean failure rather than a parse error.
const HELPER_PATH := "res://scripts/community_feedback.gd"
const STOVE := "37,30"
const SEATS := ["36,30", "37,29"]

var checks := 0
var failures := 0
var Helper: Script

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func finish() -> void:
	print("COMMUNITY_FEEDBACK_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))

func home(meals: Dictionary = {}, opened := false) -> Dictionary:
	var counts := {"soup": 0, "bread": 0, "salad": 0}
	counts.merge(meals, true)
	return {"region_id": "home", "public_kitchen": {
		"stove": STOVE, "seats": SEATS.duplicate(), "meals": counts, "opened": opened}}

func with_region(state: Dictionary, region: String) -> Dictionary:
	var copy: Dictionary = state.duplicate(true)
	copy.region_id = region
	return copy

func fresh():
	var helper = Helper.new()
	helper.reset()
	return helper

func near(a, b) -> bool:
	return typeof(a) == TYPE_FLOAT and is_equal_approx(a, b)

func sorted_meals(event: Dictionary) -> Array:
	var meals: Array = event.get("meals", []).duplicate()
	meals.sort()
	return meals

func valid_event(event: Dictionary) -> bool:
	if not (event.get("kind") in ["contribute", "opened"]) or typeof(event.get("age")) != TYPE_FLOAT:
		return false
	if typeof(event.get("meals")) != TYPE_ARRAY:
		return false
	for meal in event.meals:
		if typeof(meal) != TYPE_STRING:
			return false
	return true

func run() -> void:
	expect(ResourceLoader.exists(HELPER_PATH), "helper script exists at " + HELPER_PATH)
	if not ResourceLoader.exists(HELPER_PATH):
		finish()
		return
	Helper = load(HELPER_PATH)
	expect(Helper != null, "helper script loads")
	if Helper == null:
		finish()
		return
	var source := FileAccess.get_file_as_string(HELPER_PATH)
	expect(not source.contains("scripts/world.gd"), "presentation helper does not depend on World")
	var constants: Dictionary = Helper.get_script_constant_map()
	var contribute_time: float = float(constants.get("DURATION_CONTRIBUTE", -1.0))
	var opened_time: float = float(constants.get("DURATION_OPENED", -1.0))
	expect(is_equal_approx(contribute_time, 2.0), "contribution feedback lasts 2 seconds")
	expect(is_equal_approx(opened_time, 4.0), "opened feedback lasts 4 seconds")
	var probe = Helper.new()
	expect(probe is RefCounted, "helper is a RefCounted instance")
	expect(probe.sample(0.0, false) == {}, "fresh helper is inactive")

	test_partials_and_completion(contribute_time, opened_time)
	test_unrelated_and_repeated(contribute_time)
	test_reduced_motion()
	test_initial_and_reconnect()
	test_region_mismatch()
	test_site_changes()
	test_decrease_and_reset()
	test_invalid_time()
	test_input_untouched()
	test_no_everlasting_event(contribute_time, opened_time)
	test_shared_plates()
	finish()

func test_shared_plates()->void:
	var fb=fresh()
	var empty:={"region_id":"home","time":100.0,"community":{"table":"39,30"}}
	var served:=empty.duplicate(true)
	served.community.chowder={"portions":4}
	served.community.watermelon={"portions":4}
	fb.observe({},served,20.0)
	expect(fb.sample_shared(20.5,false)=={},"initial snapshot never replays a serving")
	fb.observe(empty,served,21.0)
	expect(fb.sample_shared(21.4,false).keys()==["watermelon_platter","corn_chowder"],"two dishes served between snapshots share the animation")
	expect(fb.sample_shared(21.4,true)=={},"reduced motion hides the serving animation")
	var with_hotpot:=served.duplicate(true)
	with_hotpot.community.hotpot={"portions":4}
	fb.observe(served,with_hotpot,21.5)
	var overlapping:Dictionary=fb.sample_shared(21.9,false)
	expect(overlapping.size()==3 and overlapping.get("corn_chowder",0.0)>overlapping.get("trout_hotpot",1.0),"later serving leaves earlier cues at their own age")
	expect(fb.sample_shared(22.5,false).keys()==["trout_hotpot"],"each cue expires by its own start time")
	var claimed:=served.duplicate(true)
	claimed.community.chowder.portions=3
	fb.observe(served,claimed,22.0)
	fb.observe(claimed,claimed,22.1)
	expect(fb.sample_shared(23.0,false)=={},"claims and repeated snapshots do not extend or replay the cue")
	fb.observe(empty,served,30.0)
	var rewind:=served.duplicate(true)
	rewind.time=90.0
	fb.observe(served,rewind,30.2)
	expect(fb.sample_shared(30.2,false)=={},"returning to an earlier save clears the cue")
	fb.observe(empty,served,40.0)
	var only_hotpot:=empty.duplicate(true)
	only_hotpot.community.hotpot={"portions":4}
	fb.observe(served,only_hotpot,40.3)
	expect(fb.sample_shared(40.5,false).keys()==["trout_hotpot"],"Dishes removed from the table stop animating while a new dish arrives")
	var hotpot_claimed:=only_hotpot.duplicate(true)
	hotpot_claimed.community.hotpot.portions=3
	fb.observe(only_hotpot,hotpot_claimed,40.6)
	expect(fb.sample_claims(40.7,false).has("trout_hotpot"),"A dish still on the table shows its portion being taken")
	fb.observe(hotpot_claimed,empty,40.8)
	expect(fb.sample_claims(40.9,false).is_empty(),"A removed dish stops showing its previous claim cue")

func test_partials_and_completion(contribute_time: float, opened_time: float) -> void:
	var fb = fresh()
	var empty := home()
	var one := home({"soup": 1})
	fb.observe(empty, one, 10.0)
	var event: Dictionary = fb.sample(10.5, false)
	expect(valid_event(event), "partial contribution has the documented shape")
	expect(event.get("kind") == "contribute" and sorted_meals(event) == ["soup"], "partial soup contribution names soup only")
	expect(near(event.get("age"), 0.5), "age measures time since the contribution")
	expect(fb.sample(10.0 + contribute_time - 0.25, false).get("kind") == "contribute", "contribution visible before duration")
	expect(fb.sample(10.0 + contribute_time, false) == {}, "contribution expires exactly at its duration")

	var more := home({"soup": 1, "bread": 2, "salad": 1})
	fb.observe(one, more, 20.0)
	event = fb.sample(20.0, false)
	expect(event.get("kind") == "contribute" and sorted_meals(event) == ["bread", "salad"],
		"multi-meal contribution lists only meals that actually rose")
	expect(near(event.get("age"), 0.0), "new contribution starts at its own observe time")

	var full := home({"soup": 3, "bread": 2, "salad": 2})
	var opened := home({"soup": 4, "bread": 2, "salad": 2}, true)
	fb.observe(more, full, 21.0)
	expect(fb.sample(21.0, false).get("kind") == "contribute", "final contribution before opening plays")
	fb.observe(full, opened, 21.5)
	event = fb.sample(21.5, false)
	expect(valid_event(event) and event.get("kind") == "opened", "opened false->true supersedes contribution")
	expect(fb.sample(21.5 + contribute_time + 0.25, false).get("kind") == "opened", "opened outlasts contribution duration")
	expect(near(fb.sample(23.5, false).get("age"), 2.0), "opened age tracks its own start")
	expect(fb.sample(21.5 + opened_time, false) == {}, "opened expires exactly at its duration")

	# A single snapshot that both adds the last meal and opens the kitchen celebrates opening.
	var fb2 = fresh()
	fb2.observe(more, opened, 30.0)
	expect(fb2.sample(30.0, false).get("kind") == "opened", "completing contribution in one snapshot shows opened")

func test_unrelated_and_repeated(contribute_time: float) -> void:
	var fb = fresh()
	var before := home({"soup": 1})
	var after := home({"soup": 2})
	fb.observe(before, after, 40.0)
	fb.observe(before, after, 40.25)
	expect(near(fb.sample(40.5,false).get("age"),0.5),"replayed original snapshot pair does not restart a cue")
	var tick: Dictionary = after.duplicate(true)
	tick["time"] = 123.0
	tick["weather"] = "rain"
	fb.observe(after, tick, 40.5)
	var event: Dictionary = fb.sample(40.5, false)
	expect(event.get("kind") == "contribute" and near(event.get("age"), 0.5), "unrelated change/time tick neither restarts nor clears")
	fb.observe(tick, tick.duplicate(true), 41.0)
	fb.observe(tick, tick.duplicate(true), 41.5)
	expect(near(fb.sample(41.5, false).get("age"), 1.5), "repeated snapshot does not extend contribution")
	expect(fb.sample(40.0 + contribute_time, false) == {}, "repeated snapshots still expire on original schedule")
	fb.observe(tick, tick.duplicate(true), 43.0)
	expect(fb.sample(43.0, false) == {}, "repeated snapshot after expiry does not replay")
	fb.observe(before,after,44.0)
	expect(fb.sample(44.0,false)=={},"replayed original snapshot pair after expiry stays silent")

	var quiet = fresh()
	quiet.observe(before, before.duplicate(true), 50.0)
	expect(quiet.sample(50.0, false) == {}, "identical snapshot produces no event")
	var opened := home({"soup": 4, "bread": 2, "salad": 2}, true)
	quiet.observe(opened, opened.duplicate(true), 51.0)
	expect(quiet.sample(51.0, false) == {}, "identical opened snapshot produces no celebration")

func test_reduced_motion() -> void:
	var fb = fresh()
	fb.observe(home(), home({"bread": 1}), 60.0)
	expect(fb.sample(60.25, true) == {}, "reduced motion suppresses contribution")
	expect(fb.sample(60.25, false).get("kind") == "contribute", "reduced sample does not consume the event")
	fb.observe(home({"bread": 2, "soup": 2, "salad": 1}), home({"bread": 2, "soup": 4, "salad": 2}, true), 61.0)
	expect(fb.sample(61.0, true) == {}, "reduced motion suppresses opened")

func test_initial_and_reconnect() -> void:
	var fb = fresh()
	fb.observe({}, home({"soup": 4, "bread": 2, "salad": 2}, true), 70.0)
	expect(fb.sample(70.0, false) == {}, "initial opened snapshot does not celebrate")
	fb.observe({}, home({"soup": 1}), 71.0)
	expect(fb.sample(71.0, false) == {}, "initial snapshot with meals is not a contribution")
	fb.observe(home({"soup": 1}), home({"soup": 2}), 72.0)
	fb.reset()
	expect(fb.sample(72.0, false) == {}, "reset clears active event")
	fb.observe({}, home({"soup": 3}), 72.5)
	expect(fb.sample(72.5, false) == {}, "reconnect without previous snapshot stays silent")

func test_region_mismatch() -> void:
	var fb = fresh()
	var low := home({"salad": 1})
	var high := home({"salad": 2})
	fb.observe(with_region(low, "forest"), high, 80.0)
	expect(fb.sample(80.0, false) == {}, "returning to home region does not replay meals")
	fb.observe(low, with_region(high, "forest"), 81.0)
	expect(fb.sample(81.0, false) == {}, "leaving home does not celebrate")
	fb.observe(with_region(low, "forest"), with_region(high, "forest"), 82.0)
	expect(fb.sample(82.0, false) == {}, "non-home region kitchen changes are ignored")
	fb.observe(low, high, 83.0)
	expect(fb.sample(83.0, false).get("kind") == "contribute", "home contribution after mismatches still works")
	fb.observe(high, with_region(high, "forest"), 83.5)
	expect(fb.sample(83.5, false) == {}, "region change clears active event")
	var missing: Dictionary = high.duplicate(true)
	missing.erase("region_id")
	fb.observe(low, missing, 84.0)
	expect(fb.sample(84.0, false).get("kind") == "contribute", "root snapshot defaults to home like WorldView")
	fb.observe(with_region(low,"forest"),high,84.5)
	expect(fb.sample(84.5,false)=={},"explicit previous foreign region clears cached home animation")
	fb.observe(low,high,85.0)
	fb.observe({},high,85.5)
	expect(fb.sample(85.5,false)=={},"reconnect clears a live animation rather than keeping the cached cue")

func test_site_changes() -> void:
	var fb = fresh()
	var low := home({"soup": 1})
	var moved := home({"soup": 2})
	moved.public_kitchen.stove = "40,30"
	fb.observe(low, moved, 90.0)
	expect(fb.sample(90.0, false) == {}, "changed stove does not celebrate")
	var reseated := home({"soup": 2})
	reseated.public_kitchen.seats = ["36,30", "38,29"]
	fb.observe(low, reseated, 91.0)
	expect(fb.sample(91.0, false) == {}, "changed seats do not celebrate")
	var unregistered_low := home({"soup": 1})
	unregistered_low.public_kitchen.stove = ""
	unregistered_low.public_kitchen.seats = []
	var unregistered_high: Dictionary = unregistered_low.duplicate(true)
	unregistered_high.public_kitchen.meals.soup = 2
	fb.observe(unregistered_low, unregistered_high, 92.0)
	expect(fb.sample(92.0, false) == {}, "unregistered kitchen does not celebrate")
	var no_kitchen := {"region_id": "home"}
	fb.observe(no_kitchen, home({"soup": 2}), 93.0)
	expect(fb.sample(93.0, false) == {}, "newly registered kitchen does not celebrate")
	fb.observe(low, home({"soup": 2}), 94.0)
	fb.observe(home({"soup": 2}), moved, 94.5)
	expect(fb.sample(94.5, false) == {}, "site change clears active event")

func test_decrease_and_reset() -> void:
	var fb = fresh()
	fb.observe(home({"soup": 1}), home({"soup": 2}), 100.0)
	fb.observe(home({"soup": 2}), home({"soup": 1}), 100.5)
	expect(fb.sample(100.5, false) == {}, "meal decrease clears active event")
	fb.observe(home({"soup": 1}), home({"soup": 0, "bread": 1}), 101.0)
	expect(fb.sample(101.0, false) == {}, "mixed decrease is treated as reset, not contribution")
	var opened := home({"soup": 4, "bread": 2, "salad": 2}, true)
	fb.observe(home({"soup": 2, "bread": 2, "salad": 1}), opened, 102.0)
	fb.observe(opened, home(), 103.0)
	expect(fb.sample(103.0, false) == {}, "kitchen reset clears opened celebration")
	fb.observe(opened, home({"soup": 2, "bread": 2, "salad": 2}), 104.0)
	expect(fb.sample(104.0, false) == {}, "opened true->false never celebrates")

func test_invalid_time() -> void:
	for when in [-1.0, -0.001, NAN, INF, -INF]:
		var fb = fresh()
		fb.observe(home(), home({"soup": 1}), when)
		expect(fb.sample(0.0, false) == {} and fb.sample(1.0, false) == {}, "invalid observe time %s yields no event" % when)
	var later = fresh()
	later.observe(home(), home({"soup": 1}), 0.0)
	expect(later.sample(0.0, false).get("kind") == "contribute", "time zero is a valid observe time")

func test_input_untouched() -> void:
	var fb = fresh()
	var before := home({"soup": 1})
	var after := home({"soup": 2, "bread": 1}, false)
	var before_copy: Dictionary = before.duplicate(true)
	var after_copy: Dictionary = after.duplicate(true)
	fb.observe(before, after, 110.0)
	expect(before == before_copy and after == after_copy, "observe leaves inputs deeply unchanged")
	var event: Dictionary = fb.sample(110.0, false)
	if typeof(event.get("meals")) == TYPE_ARRAY:
		event.meals.append("cake")
	event["kind"] = "tampered"
	var again: Dictionary = fb.sample(110.0, false)
	expect(again.get("kind") == "contribute" and sorted_meals(again) == ["bread", "soup"], "mutating a sample does not alter helper state")
	after.public_kitchen.meals.soup = 9
	expect(sorted_meals(fb.sample(110.0, false)) == ["bread", "soup"], "helper does not alias caller snapshots")

func test_no_everlasting_event(contribute_time: float, opened_time: float) -> void:
	var fb = fresh()
	var low := home({"soup": 1, "bread": 1, "salad": 1})
	var mid := home({"soup": 2, "bread": 1, "salad": 1})
	var opened := home({"soup": 4, "bread": 2, "salad": 2}, true)
	fb.observe(low, mid, 120.0)
	fb.observe(mid, opened, 120.5)
	expect(fb.sample(120.5 + opened_time, false) == {}, "opened expires at boundary")
	expect(fb.sample(120.5 + opened_time + 0.25, false) == {}, "superseded contribution is not queued after opened")
	expect(fb.sample(10000.0, false) == {}, "no event remains forever")
	fb.observe(opened, opened.duplicate(true), 200.0)
	expect(fb.sample(200.0, false) == {}, "later repeated opened snapshot does not replay")
	var other = fresh()
	other.observe(low, mid, 300.0)
	expect(other.sample(300.0 + contribute_time + 1000.0, false) == {}, "contribution is not everlasting")
