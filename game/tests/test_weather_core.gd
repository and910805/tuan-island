extends SceneTree
## T039 basic weather + calendar-day watering (core rules and World.step).
const Weather = preload("res://scripts/weather.gd")
const World = preload("res://scripts/world.gd")
const Mines = preload("res://scripts/mine_depths.gd")
const DAY := 1440.0
## Agreed contract: one-based day 1..7 then repeats.
const EXPECTED := ["sunny","cloudy","rainy","sunny","sunny","rainy","cloudy"]
const LABEL := {"sunny":"晴天","cloudy":"多雲","rainy":"小雨"}
const BIG := 1.0e9
var checks := 0
var failures := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 1e-6

func plot(layer: Dictionary, tile: String, kind: String, wet: bool, growth := 0.0) -> void:
	layer[tile] = {"kind":kind, "growth":growth, "wet":wet, "owner":"a", "remaining":1}

func fresh_world() -> Object:
	var w = World.new()
	w.add_player("a", "甲")
	return w

func _initialize() -> void:
	test_calendar()
	test_advance_plot()
	test_season_growth()
	test_world_rain_and_roofs()
	test_world_caves_and_regions()
	test_world_sprinklers()
	test_medium_sprinkler()
	test_rain_does_not_mark_unused_sprinkler()
	test_world_persistence_and_rollback()
	test_world_segmentation()
	print("WEATHER_CORE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_calendar() -> void:
	expect(Weather.DAY_SECONDS == 1440.0, "day length is 1440 world seconds")
	var first: Dictionary = Weather.at(0.0)
	expect(first.id == "sunny" and first.label == "晴天" and first.raining == false and first.day == 1, "world start is sunny day 1")
	expect(first.keys().size() == 4 and first.id is String and first.label is String and first.raining is bool and first.day is int, "contract fields and types")
	for d in range(21):
		var info: Dictionary = Weather.at(d * DAY + 700.0)
		var want: String = EXPECTED[d % 7]
		expect(info.id == want and info.label == LABEL[want] and info.raining == (want == "rainy") and info.day == d + 1, "cycle day %d is %s" % [d + 1, want])
	expect(Weather.at(DAY - 0.001).day == 1 and Weather.at(DAY - 0.001).id == "sunny", "last instant of day 1")
	expect(Weather.at(DAY).day == 2 and Weather.at(DAY).id == "cloudy", "midnight belongs to the new day")
	expect(Weather.at(2.0 * DAY).raining and Weather.at(2.0 * DAY - 0.001).raining == false, "rain starts exactly at day-3 midnight")
	expect(Weather.at(3.0 * DAY).raining == false, "rain ends exactly at day-4 midnight")
	# Same provisional weather in every outdoor region; mines are indoor.
	expect(Weather.INDOOR_REGIONS == Mines.IDS, "indoor list matches the five mine levels")
	for region in World.REGIONS.ALL:
		var info: Dictionary = Weather.at(2.0 * DAY + 1.0, region)
		if region in Mines.IDS:
			expect(info.id == "indoor" and info.label == "洞內" and info.raining == false and info.day == 3, "%s is a dry cave" % region)
		else:
			expect(info == Weather.at(2.0 * DAY + 1.0), "%s shares outdoor weather" % region)
	expect(Weather.at(2.0 * DAY + 1.0, "unknown_place").raining, "unknown regions fall back to outdoor weather")
	# Unsafe input clamps to day 1 rather than erroring or using a wall clock.
	for bad in [-1.0, -1.0e300, NAN, INF, -INF]:
		var info: Dictionary = Weather.at(bad)
		expect(info.day == 1 and info.id == "sunny", "unsafe time %s clamps to day 1" % str(bad))
	var huge: Dictionary = Weather.at(1.0e300)
	expect(huge.day >= 1 and huge.id in EXPECTED and huge.raining == (huge.id == "rainy"), "absurd finite time stays well formed")
	var far: Dictionary = Weather.at(1.0e6 * 7.0 * DAY + 2.0 * DAY)
	expect(far.id == "rainy" and far.raining and far.day == 7000003, "cycle arithmetic far in the future")
	expect(Weather.at(12345.0, "home") == Weather.at(12345.0, "home"), "deterministic")

func test_season_growth() -> void:
	expect(Weather.season_on_day(13.0) == "spring" and Weather.season_on_day(14.0) == "summer" and Weather.season_on_day(56.0) == "spring", "Seasons turn after fourteen days and wrap")
	var dormant := Weather.advance_plot(true, false, 20.0, 90.0, 14.0 * DAY, 10.0, ["spring"])
	expect(dormant.growth == 20.0 and dormant.wet, "Dormancy preserves progress and wetness")
	var sheltered := Weather.advance_plot(true, false, 20.0, 90.0, 14.0 * DAY, 10.0, ["spring"], true)
	expect(sheltered.growth == 30.0, "Watered greenhouse crop grows out of season")
	var midnight := Weather.advance_plot(true, true, 20.0, 90.0, 13.0 * DAY + DAY - 10.0, 20.0, ["spring"])
	expect(midnight.growth == 30.0 and not midnight.wet, "Growth counts only the spring portion across midnight")

func test_advance_plot() -> void:
	# Exposure off, measure wet duration with a large maturity need.
	var r: Dictionary = Weather.advance_plot(true, false, 0.0, BIG, 100.0, DAY - 100.0)
	expect(not r.wet and near(r.growth, DAY - 100.0), "step ending exactly at midnight dries and counts wet time up to it")
	r = Weather.advance_plot(true, false, 0.0, BIG, DAY, 10.0)
	expect(r.wet and near(r.growth, 10.0), "watering at midnight is not dried by the same midnight again")
	r = Weather.advance_plot(true, false, 0.0, BIG, DAY - 30.0, 60.0)
	expect(not r.wet and near(r.growth, 30.0), "growth stops at the midnight that dries the soil")
	r = Weather.advance_plot(true, false, 0.0, BIG, 0.0, 30.0 * DAY)
	expect(not r.wet and near(r.growth, DAY), "unexposed soil gets one day of watering only")
	# Rain.
	r = Weather.advance_plot(false, true, 0.0, BIG, 2.0 * DAY + 100.0, 50.0)
	expect(r.wet and near(r.growth, 50.0), "rain wets exposed dry soil at tick start")
	r = Weather.advance_plot(false, false, 0.0, BIG, 2.0 * DAY + 100.0, 50.0)
	expect(not r.wet and near(r.growth, 0.0), "covered soil stays dry in rain")
	r = Weather.advance_plot(false, true, 0.0, BIG, 2.0 * DAY - 30.0, 60.0)
	expect(r.wet and near(r.growth, 30.0), "rain at midnight wets only from the boundary on")
	r = Weather.advance_plot(true, true, 0.0, BIG, 0.0, 7.0 * DAY)
	expect(not r.wet and near(r.growth, 3.0 * DAY), "one week: watered day 1 plus rainy days 3 and 6")
	r = Weather.advance_plot(false, true, 0.0, BIG, 0.0, 7.0 * DAY + 1.0)
	expect(not r.wet and near(r.growth, 2.0 * DAY), "dry start: only the two rainy days count")
	r = Weather.advance_plot(false, true, 0.0, 0.0, 0.0, 2.0 * DAY)
	expect(r.wet and r.growth == 0.0, "unplanted soil is wetted by rain but never grows")
	# Maturity cap, no rot.
	r = Weather.advance_plot(true, true, 270.0, 270.0, 0.0, 100.0 * DAY)
	expect(near(r.growth, 270.0), "mature crop keeps full growth through dry days")
	r = Weather.advance_plot(true, true, 200.0, 270.0, 0.0, 500.0)
	expect(near(r.growth, 270.0), "growth caps at maturity")
	# Invalid dt is a no-op.
	for bad in [0.0, -5.0, NAN, INF]:
		r = Weather.advance_plot(true, true, 12.0, 90.0, 2.0 * DAY, bad)
		expect(r.wet == true and r.growth == 12.0, "dt %s changes nothing" % str(bad))
	# Huge finite dt is bounded and still lands on the correct final day.
	for start in [0.0, 5.0 * DAY + 3.0]:
		for dt in [1.0e7, 1.0e12, 1.0e15]:
			var end: float = start + dt
			var final_rain: bool = Weather.at(end).raining
			r = Weather.advance_plot(false, true, 0.0, 270.0, start, dt)
			expect(near(r.growth, 270.0) and r.wet == final_rain, "huge dt %s from %s exposed" % [str(dt), str(start)])
			r = Weather.advance_plot(true, false, 0.0, BIG, start, dt)
			expect(not r.wet and r.growth <= DAY, "huge dt %s unexposed dries" % str(dt))
	# Segmentation equivalence over many split patterns (binary fractions keep sums exact).
	var patterns := [[60.0], [1439.0, 1.0], [0.25, 33.5, 1406.25], [2879.5, 0.5, 7.0], [1440.0], [3.75, 1000.0, 999.0, 0.25]]
	for exposed in [true, false]:
		for wet0 in [true, false]:
			for start in [0.0, 1000.0, 2.0 * DAY - 0.5, 5.0 * DAY]:
				var total := 9.0 * DAY + 17.5
				var whole: Dictionary = Weather.advance_plot(wet0, exposed, 0.0, BIG, start, total)
				for pattern in patterns:
					var wet: bool = wet0
					var growth := 0.0
					var t: float = start
					var left := total
					var i := 0
					while left > 0.0:
						var size: float = minf(pattern[i % pattern.size()], left)
						var part: Dictionary = Weather.advance_plot(wet, exposed, growth, BIG, t, size)
						wet = part.wet
						growth = part.growth
						t += size
						left -= size
						i += 1
					expect(wet == whole.wet and near(growth, whole.growth), "split %s exposed=%s wet=%s start=%s matches one step" % [str(pattern), str(exposed), str(wet0), str(start)])

func test_world_rain_and_roofs() -> void:
	var w = fresh_world()
	var crops: Dictionary = w.state.crops
	# Day 1 sunny preserves onboarding: manual water grows, dry plots stay dry.
	plot(crops, "40,40", "radish", true)
	plot(crops, "41,40", "radish", false)
	expect(w.step(60.0, true), "day-1 tick")
	expect(crops["40,40"].wet and near(crops["40,40"].growth, 60.0) and not crops["41,40"].wet and crops["41,40"].growth == 0.0, "sunny first day keeps original watering behaviour")
	# Watering now lasts only to the next midnight (compatibility change for day > 1).
	w.state.time = DAY - 30.0
	crops["40,40"].growth = 0.0
	expect(w.step(60.0, true), "midnight tick")
	expect(not crops["40,40"].wet and near(crops["40,40"].growth, 30.0), "midnight dries soil and stops growth mid-tick")
	# Rainy day 3: exposed planted and unplanted plots get wet; roofs block rain.
	crops.clear()
	plot(crops, "40,40", "radish", false)
	plot(crops, "41,40", "", false)
	plot(crops, "42,40", "radish", false)
	w.state.roofs["42,40"] = {"type":"roof", "owner":"a", "items":{}}
	w.state.time = 2.0 * DAY - 10.0
	expect(w.step(25.0, true), "rain midnight tick")
	expect(crops["40,40"].wet and near(crops["40,40"].growth, 15.0), "exposed crop wet from the rainy midnight only")
	expect(crops["41,40"].wet and crops["41,40"].growth == 0.0, "rain wets exposed unplanted plot")
	expect(not crops["42,40"].wet and crops["42,40"].growth == 0.0, "roof keeps the plot dry")
	# Roof removal and placement act on the next tick.
	w.state.roofs.erase("42,40")
	expect(w.step(1.0, true) and crops["42,40"].wet, "removing the roof lets rain in next tick")
	w.state.roofs["41,40"] = {"type":"roof", "owner":"a", "items":{}}
	crops["41,40"].wet = false
	expect(w.step(1.0, true) and not crops["41,40"].wet, "new roof shields next tick")
	# Harvest-style drying during rain gets re-wetted on the next tick.
	crops["40,40"].wet = false
	expect(w.step(1.0, true) and crops["40,40"].wet, "rain re-wets an exposed plot during a rainy day")
	# Mature crops do not rot through many dry days.
	crops["43,40"] = {"kind":"radish", "growth":World.CROPS.radish.time, "wet":false, "owner":"a", "remaining":1}
	w.state.time = 3.0 * DAY
	expect(w.step(DAY * 1.5, true), "long dry tick")
	expect(crops["43,40"].kind == "radish" and crops["43,40"].growth == World.CROPS.radish.time, "mature crop keeps maturity")
	expect(w.step(1.0, false) and w.state.time == 4.5 * DAY, "inactive step stays a no-op")

func test_world_caves_and_regions() -> void:
	var w = fresh_world()
	var lanyang: Dictionary = w.state.regions.lanyang.crops
	var cave: Dictionary = w.state.regions.mine_1.crops
	plot(w.state.crops, "40,40", "radish", false)
	plot(lanyang, "13,20", "radish", false)
	plot(cave, "13,20", "radish", false)
	plot(cave, "14,20", "radish", true)
	w.state.time = 5.0 * DAY + 5.0 # rainy day 6
	expect(w.step(10.0, true), "regional rain tick")
	expect(w.state.crops["40,40"].wet and lanyang["13,20"].wet, "home and Lanyang share the rain")
	expect(not cave["13,20"].wet and cave["14,20"].wet and near(cave["14,20"].growth, 10.0), "caves never rain but manual water still works")
	w.state.time = 6.0 * DAY - 1.0
	expect(w.step(2.0, true), "cave midnight tick")
	expect(not cave["14,20"].wet and not w.state.crops["40,40"].wet and not lanyang["13,20"].wet, "every region dries at midnight into cloudy day 7")
	expect(w.state.time == 6.0 * DAY + 1.0, "world clock advances once for all regions")

func test_world_sprinklers() -> void:
	var w = fresh_world()
	var device := "42,34"
	w.state.objects[device] = {"type":"sprinkler", "owner":"a", "items":{}, "water":12, "enabled":true, "next_water":0.0, "last_water":-1.0}
	plot(w.state.crops, "42,33", "radish", false)
	var chapter_before: Dictionary = w.state.chapter_one.duplicate(true)
	w.state.time = 2.0 * DAY + 5.0
	expect(w.step(1.0, true), "rainy sprinkler tick")
	expect(w.state.crops["42,33"].wet and int(w.state.objects[device].water) == 12, "rain waters without consuming sprinkler water")
	expect(w.state.chapter_one == chapter_before, "rain grants no irrigation credit")
	w.state.time = 3.0 * DAY - 0.5
	expect(w.step(1.0, true) and w.state.crops["42,33"].wet and int(w.state.objects[device].water)==11, "due sprinkler immediately waters midnight-dried soil, consuming exactly one water")
	expect(w.step(10.0, true) and w.state.crops["42,33"].wet and int(w.state.objects[device].water) == 11, "sprinkler re-waters on its normal schedule")
	# Manual watering still works on a dry day.
	plot(w.state.crops, "45,40", "radish", false)
	w.state.crops["45,40"].wet = true
	expect(w.step(5.0, true) and w.state.crops["45,40"].wet and near(w.state.crops["45,40"].growth, 5.0), "manual water grows on sunny day 4")

func test_medium_sprinkler() -> void:
	var w = fresh_world()
	var center := Vector2i(42,34)
	var device_key := World.key(center)
	var device := {"type":"medium_sprinkler","owner":"a","items":{},"water":0,"enabled":true,"next_water":0.0,"last_water":-1.0}
	w.state.objects[device_key]=device
	w.state.objects["42,36"]={"type":"water_tank","owner":"a","items":{},"water":24}
	w.state.objects["42,35"]={"type":"water_pipe","owner":"a","items":{}}
	var neighbors:=World.INDUSTRY.sprinkler_offsets("medium_sprinkler")
	expect(neighbors.size()==8 and World.INDUSTRY.sprinkler_offsets("sprinkler").size()==4,"Distinct sprinkler patterns")
	for offset in neighbors:
		plot(w.state.crops,World.key(center+offset),"radish",false)
	w.state.crops["41,33"].owner="b"
	expect(w.step(1.0,true),"Connected medium sprinkler tick")
	expect(w.state.crops["43,35"].wet and not w.state.crops["41,33"].wet,"Waters own diagonal crops and skips another owner's crops")
	expect(device.water==17 and w.state.objects["42,36"].water==0,"Draws 24 tank units and consumes exactly seven")
	expect(w.state.objects[device_key].network_water==17,"Tracks remaining network water")

func test_rain_does_not_mark_unused_sprinkler() -> void:
	var w=fresh_world()
	var device:="42,34"
	w.state.time=2.0*DAY+5.0
	# Isolate irrigation use from a separate legitimate water-network tick.
	w.state.next_network_check=w.state.time+2.0
	w.state.next_logistics_check=w.state.time+2.0
	w.state.objects[device]={"type":"sprinkler","owner":"a","items":{},"water":12,"enabled":true,"next_water":0.0,"last_water":-1.0}
	plot(w.state.crops,"42,33","radish",false)
	w._undo_used={}
	w.step_region(1.0)
	expect(w.state.crops["42,33"].wet and w.state.objects[device].water==12,"rain settles before sprinkler target planning")
	expect(not w._undo_used.get("home",{}).has(device),"natural rain does not mark an unused sprinkler as construction use")

func test_world_persistence_and_rollback() -> void:
	var w = fresh_world()
	plot(w.state.crops, "40,40", "radish", false)
	plot(w.state.regions.lanyang.crops, "13,20", "radish", false)
	w.state.time = 2.0 * DAY - 10.0
	var before: Dictionary = w.state.duplicate(true)
	w.save_path = "user://missing-weather-dir/world.json"
	expect(not w.step(20.0, true), "save failure reports false")
	expect(w.state == before, "failed rain tick rolls back every region, time and growth")
	var path := "user://weather-core-%d.json" % Time.get_ticks_usec()
	w.save_path = path
	expect(w.step(20.0, true), "rain-only tick saves")
	var loaded = World.new()
	expect(loaded.load_world(path) and loaded.state.crops["40,40"].wet and loaded.state.regions.lanyang.crops["13,20"].wet and loaded.state.time == 2.0 * DAY + 10.0, "rain transition persisted in all regions")
	w.state.time = 3.0 * DAY - 1.0
	expect(w.step(2.0, true), "drying-only tick saves")
	loaded = World.new()
	expect(loaded.load_world(path) and not loaded.state.crops["40,40"].wet and not loaded.state.regions.lanyang.crops["13,20"].wet, "midnight drying persisted")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):DirAccess.remove_absolute(path + suffix)

func seg_world(start: float) -> Object:
	var w = fresh_world()
	w.state.time = start
	plot(w.state.crops, "40,40", "pumpkin", false)
	plot(w.state.crops, "41,40", "pumpkin", true)
	plot(w.state.crops, "42,40", "", false)
	plot(w.state.crops, "43,40", "pumpkin", true)
	w.state.roofs["43,40"] = {"type":"roof", "owner":"a", "items":{}}
	plot(w.state.regions.mine_2.crops, "13,20", "pumpkin", true)
	plot(w.state.regions.lanyang.crops, "13,20", "carrot", false)
	return w

func crop_view(w) -> Dictionary:
	return {"home":w.state.crops.duplicate(true), "mine_2":w.state.regions.mine_2.crops.duplicate(true), "lanyang":w.state.regions.lanyang.crops.duplicate(true), "time":w.state.time}

func test_world_segmentation() -> void:
	for start in [DAY - 200.0, 2.0 * DAY - 100.0, 4.0 * DAY + 1300.0]:
		for total in [150.0, 300.0, 3.0 * DAY + 60.0]:
			var one = seg_world(start)
			expect(one.step(total, true), "single step")
			var many = seg_world(start)
			var left: float = total
			var sizes := [0.5, 37.25, 1439.0, 1.0, 12.0]
			var i := 0
			while left > 0.0:
				var size: float = minf(sizes[i % sizes.size()], left)
				many.step(size, true)
				left -= size
				i += 1
			expect(crop_view(one) == crop_view(many), "World crops identical for one step vs %d steps (start %s, total %s)" % [i, str(start), str(total)])
	# Large multi-day tick stays bounded and lands on the right calendar state.
	var w = seg_world(0.0)
	expect(w.step(1.0e7, true), "very large tick completes")
	var rain: bool = Weather.at(1.0e7).raining
	expect(w.state.crops["40,40"].wet == rain and w.state.crops["40,40"].growth == World.CROPS.pumpkin.time, "exposed crop matured and wetness follows final day")
	expect(not w.state.crops["43,40"].wet and w.state.crops["43,40"].growth <= DAY, "roofed crop only had its initial watering")
	expect(not w.state.regions.mine_2.crops["13,20"].wet, "cave crop dried")
