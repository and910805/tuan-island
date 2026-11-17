extends "res://tests/test_chapter_journey.gd"

# Earned public-kitchen journey (T042), continuing the REAL chapter-one journey of
# test_chapter_journey.gd (farming, shipping, board donation, irrigation, stove,
# picnic) for the same single player, then:
#   1. Aru's story 0 (own bed + wood) and story 1 (board + wood/stone) through the
#      normal `quest` action, which is what unlocks the long_bench blueprint;
#   2. natural gathering for every remaining material (no gifts, no debug);
#   3. building an OWN new stove and two OWN long benches near the shared table;
#   4. explicit `kitchen_register` with the canonical seat extra;
#   5. growing (and buying the missing seeds of) the current recipe ingredients,
#      cooking every kitchen meal on the donated stove and `kitchen_contribute`;
#   6. normal primary-save reload, then a brand-new member joining the reloaded
#      world and replaying the unlocked story pages read-only, repeatedly.
#
# Mutation rules: the live world is only changed through World.act, World.move_player
# (via the inherited BFS walk_to), World.step (every call goes through advance(),
# which prints the label and the SIMULATED world seconds — never wall clock) and
# World.add_player; the reloaded world through load_world + add_player only. Scratch
# World instances are used purely as read-only planners (site reachability and the
# default starter stock) and are never saved.
#
# Output (documented so nothing from the parent is misread):
#   KITCHEN ...                 one line per action/step/probe of this slice
#   KITCHEN_JOURNEY ...         slice summary (passed=... is the overall verdict)
#   KITCHEN_JOURNEY_TESTS ...   checks/failures, CUMULATIVE with the chapter part
#   then the parent prints its own CHAPTER_JOURNEY / CHAPTER_JOURNEY_TESTS lines
#   (also cumulative: the parent's counters are shared) and removes the temp save
#   and its .bak. Those parent lines are retained on purpose; quit() code is the
#   parent's int(failed), which includes every failure of this slice.
# Any impossible step is reported as an expect(false, "BLOCKER: ...") failure; no
# prerequisite is ever granted or skipped.

const HOME := "home"
const LATE := "kitchen-late-member"
const NO_CELL := Vector2i(-1,-1)
const MAX_SOURCES := 60
const MAX_HITS := 4
const MAX_FOOD_ROUNDS := 3
const MAX_STOVE_TRIES := 14
const MAX_PAIR_TRIES := 10
const MAX_BED_TRIES := 30
const FARM_ANCHOR := Vector2i(41,35)
const REPLAYS := 3
const PK = World.PUBLIC_KITCHEN

var start_stock := {}
var start_coins := -1
var start_position := Vector2.ZERO
var start_kitchen := {}
var default_stock := {}
var default_coins := -1
var sim_steps := 0
var sim_seconds := 0.0
var probes := 0
var gather_hits := 0
var gather_sources := 0
var gathered := {}
var stove := NO_CELL
var seats: Array[Vector2i] = []
var bed := NO_CELL
var earned := {"soup":0, "bread":0, "salad":0}
var contributed := {"soup":0, "bread":0, "salad":0}
var seeds_bought := {}
var harvested := {}
var site_tests := 0

# --- start-of-run capture -----------------------------------------------------

# The parent calls checkpoint("grow") immediately after add_player and before the
# first action, so this is the only honest place to observe the starting stock.
func checkpoint(stage: String) -> void:
	if stage == "grow" and start_stock.is_empty():
		start_stock = bag().duplicate(true)
		start_coins = int(person().coins)
		start_position = Vector2(person().x, person().y)
		start_kitchen = world.state.public_kitchen.duplicate(true)
		var scratch := World.new()
		scratch.add_player("starter-probe", "Probe")
		default_stock = scratch.state.players["starter-probe"].inventory.duplicate(true)
		default_coins = int(scratch.state.players["starter-probe"].coins)
		expect(same_inventory(start_stock, default_stock) and start_coins == default_coins, "Journey starts from the normal add_player stock %s coins=%d (got %s coins=%d)" % [JSON.stringify(default_stock), default_coins, JSON.stringify(start_stock), start_coins])
		for meal in PK.MEALS:
			expect(int(start_stock.get(meal,0)) == 0, "No %s in the starting stock" % meal)
		expect(int(person().stories.aru) == 0 and not World.Village.unlocked(person(), "long_bench"), "Aru story starts at 0 with long_bench locked")
		expect(JSON.stringify(start_kitchen) == JSON.stringify(PK.fresh()) and PK.stage(world.state) == "locked" and PK.events(world.state).is_empty(), "Public kitchen starts fresh, locked and without story pages")
	super.checkpoint(stage)

# --- small helpers ------------------------------------------------------------

func held(item: String) -> int:
	return int(bag().get(item,0))

func same_inventory(a: Dictionary, b: Dictionary) -> bool:
	for item in a:
		if int(a[item]) != int(b.get(item,0)):return false
	for item in b:
		if int(b[item]) != int(a.get(item,0)):return false
	return true

func expect_delta(before: Dictionary, delta: Dictionary, label: String) -> void:
	var now := bag()
	var keys := {}
	for item in before:keys[item] = true
	for item in now:keys[item] = true
	for item in delta:keys[item] = true
	var wrong := []
	for item in keys:
		if int(now.get(item,0)) != int(before.get(item,0)) + int(delta.get(item,0)):
			wrong.append("%s:%d->%d(want %+d)" % [item, int(before.get(item,0)), int(now.get(item,0)), int(delta.get(item,0))])
	expect(wrong.is_empty(), "%s changed inventory by exactly %s %s" % [label, JSON.stringify(delta), "" if wrong.is_empty() else JSON.stringify(wrong)])

func cost_of(recipe: Dictionary) -> Dictionary:
	var out := {}
	for item in recipe:
		if item != "name":out[item] = int(recipe[item])
	return out

func negate(d: Dictionary) -> Dictionary:
	var out := {}
	for item in d:out[item] = -int(d[item])
	return out

# World.act through the inherited walk; same request-id space as the parent.
func run(action: String, target: Vector2i, extra: String = "") -> Dictionary:
	walk_to(target)
	if failed:return {}
	actions += 1
	var result := world.act(TOKEN, "journey-%d" % actions, action, target, extra)
	print("KITCHEN %d %s %s %s | ok=%s %s | wood=%d stone=%d fiber=%d coins=%d" % [actions, action, target, extra, result.get("ok"), result.get("message",""), held("wood"), held("stone"), held("fiber"), int(person().coins)])
	expect(bool(result.get("ok",false)), "World action failed: %s %s %s (%s)" % [action, target, extra, result.get("message","")])
	return result

# A request that MUST be rejected by the real rules and leave the world untouched.
func probe(action: String, target: Vector2i, extra: String, label: String, needle: String = "") -> Dictionary:
	walk_to(target)
	if failed:return {}
	var before := JSON.stringify(world.state)
	probes += 1
	var result := world.act(TOKEN, "kitchen-probe-%d" % probes, action, target, extra)
	print("KITCHEN probe %s %s %s | ok=%s %s" % [action, target, extra, result.get("ok"), result.get("message","")])
	expect(not bool(result.get("ok",true)) and JSON.stringify(world.state) == before, label + " is rejected without any state change")
	if not needle.is_empty():
		expect(str(result.get("message","")).contains(needle), "%s rejection names the real reason (%s)" % [label, needle])
	return result

func advance(seconds: float, label: String) -> void:
	if failed:return
	sim_steps += 1
	sim_seconds += seconds
	print("KITCHEN step %d '%s' simulated_world_seconds=%.1f (World.step, not wall clock)" % [sim_steps, label, seconds])
	expect(world.step(seconds, true), "World.step for " + label)

# --- site planning (read-only, scratch copies only) ----------------------------

func free_cell(c: Vector2i) -> bool:
	var k := World.key(c)
	if not world.is_land(c) or world.water(c) or world.protected(c) or world.blocked(c) or world.resource(c) != "":return false
	for layer in ["objects","ground","roofs","crops","forest"]:
		if world.state[layer].has(k):return false
	return true

func passable_component(target) -> Dictionary:
	var table := World.COMMUNITY.table_cell(target.state)
	var seen := {}
	var queue: Array[Vector2i] = []
	for d in PK.DIRS:
		var n: Vector2i = table + d
		if not target.blocked(n):
			seen[n] = true
			queue.append(n)
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in PK.DIRS:
			var n: Vector2i = c + d
			if seen.has(n) or n.x < 0 or n.y < 0 or n.x >= World.SIZE.x or n.y >= World.SIZE.y:continue
			if target.blocked(n):continue
			seen[n] = true
			queue.append(n)
	return seen

# True when placing `placed` (cell -> type) keeps every currently reachable cell
# reachable and keeps the kitchen cells (if any) path-accessible from the table.
func layout_ok(base: Dictionary, placed: Dictionary, kitchen: Array[Vector2i]) -> bool:
	site_tests += 1
	var scratch := World.new()
	scratch.state = world.state.duplicate(true)
	for c in placed:
		scratch.state.objects[World.key(c)] = {"type":placed[c], "owner":TOKEN, "items":{}}
	var after := passable_component(scratch)
	for c in base:
		if not placed.has(c) and not after.has(c):return false
	return kitchen.is_empty() or PK.reachable(scratch, World.COMMUNITY.table_cell(scratch.state), kitchen)

func by_distance(cells: Array, origin: Vector2i) -> Array:
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: float = Vector2(a).distance_squared_to(Vector2(origin))
		var db: float = Vector2(b).distance_squared_to(Vector2(origin))
		if da != db:return da < db
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return cells

func plan_site() -> void:
	var table := World.COMMUNITY.table_cell(world.state)
	var base := passable_component(world)
	var range_s := int(PK.STOVE_RANGE)
	var range_b := int(PK.SEAT_RANGE)
	var stoves := []
	for y in range(table.y-range_s, table.y+range_s+1):
		for x in range(table.x-range_s, table.x+range_s+1):
			var c := Vector2i(x,y)
			if Vector2(c).distance_to(Vector2(table)) <= PK.STOVE_RANGE and free_cell(c):stoves.append(c)
	by_distance(stoves, table)
	for s in stoves.slice(0, MAX_STOVE_TRIES):
		var benches := []
		for y in range(s.y-range_b, s.y+range_b+1):
			for x in range(s.x-range_b, s.x+range_b+1):
				var c := Vector2i(x,y)
				if c != s and Vector2(c).distance_to(Vector2(s)) <= PK.SEAT_RANGE and free_cell(c):benches.append(c)
		by_distance(benches, s)
		var pair_tries := 0
		for i in benches.size():
			for j in range(i+1, benches.size()):
				pair_tries += 1
				if pair_tries > MAX_PAIR_TRIES:break
				var trial: Array[Vector2i] = [s, benches[i], benches[j]]
				if layout_ok(base, {s:"stove", benches[i]:"long_bench", benches[j]:"long_bench"}, trial):
					stove = s
					seats = [benches[i], benches[j]]
					break
			if stove != NO_CELL or pair_tries > MAX_PAIR_TRIES:break
		if stove != NO_CELL:break
	if stove == NO_CELL:
		expect(false, "BLOCKER: no free stove cell within %.0f of table %s with two free bench cells within %.0f that keep every path open" % [PK.STOVE_RANGE, table, PK.SEAT_RANGE])
		return
	var kitchen: Array[Vector2i] = [stove, seats[0], seats[1]]
	var aru: Vector2i = World.Village.NPCS.aru.cell
	var beds := []
	for y in range(aru.y-10, aru.y+11):
		for x in range(aru.x-10, aru.x+11):
			var c := Vector2i(x,y)
			if not c in kitchen and free_cell(c):beds.append(c)
	by_distance(beds, aru)
	var bed_tries := 0
	for c in beds:
		bed_tries += 1
		if bed_tries > MAX_BED_TRIES:break
		# Keep the bed off every cardinal neighbour of the kitchen site.
		var touching := false
		for k in kitchen:
			if (c - k).length_squared() == 1:touching = true
		if touching:continue
		if layout_ok(base, {stove:"stove", seats[0]:"long_bench", seats[1]:"long_bench", c:"bed"}, kitchen):
			bed = c
			break
	expect(bed != NO_CELL, "BLOCKER: no free bed cell near Aru that keeps every path open")
	print("KITCHEN site table=%s stove=%s seats=%s bed=%s layout_checks=%d" % [table, stove, JSON.stringify([World.key(seats[0]), World.key(seats[1])]), bed, site_tests])

# --- gathering ------------------------------------------------------------------

func gather(item: String, minimum: int, kinds: Array) -> void:
	var rounds := 0
	while held(item) < minimum and not failed:
		rounds += 1
		if rounds > MAX_SOURCES:
			expect(false, "BLOCKER: gathering %s exceeded %d sources" % [item, MAX_SOURCES])
			return
		var target := NO_CELL
		var kind := ""
		for candidate in kinds:
			target = find_resource(candidate)
			if target != NO_CELL:
				kind = candidate
				break
		if target == NO_CELL:
			expect(false, "BLOCKER: no reachable natural source for %s (need %d, hold %d)" % [item, minimum, held(item)])
			return
		var tool := "pick" if kind == "rock" else "axe"
		var hits := 0
		while world.resource(target) == kind and hits < MAX_HITS and not failed:
			run(tool, target)
			hits += 1
		expect(world.resource(target) == "", "Natural %s at %s fully gathered in %d hits" % [kind, target, hits])
		gather_hits += hits
		gather_sources += 1

# --- farming / cooking ----------------------------------------------------------

func own_crop_keys() -> Array:
	var out := []
	for k in world.state.crops:
		if world.state.crops[k].get("owner","") == TOKEN:out.append(k)
	out.sort()
	return out

func raw_needed() -> Dictionary:
	var raw := {}
	var outstanding := PK.outstanding(world.state)
	for meal in PK.MEALS:
		var recipe: Dictionary = World.RECIPES[meal]
		var cooks := ceili(float(maxi(0, int(outstanding.get(meal,0)) - held(meal))) / float(recipe["yield"]))
		for item in recipe.ingredients:
			raw[item] = int(raw.get(item,0)) + cooks * int(recipe.ingredients[item])
	return raw

func hoe_cell(reserved: Dictionary) -> Vector2i:
	var cells := []
	for y in range(FARM_ANCHOR.y-8, FARM_ANCHOR.y+9):
		for x in range(FARM_ANCHOR.x-8, FARM_ANCHOR.x+9):
			var c := Vector2i(x,y)
			if not reserved.has(c) and free_cell(c):cells.append(c)
	by_distance(cells, FARM_ANCHOR)
	for c in cells:
		if not route(c).is_empty():return c
	return NO_CELL

# Wait through the actual world clock, then water on a day with enough
# remaining time to complete this batch before midnight dries its soil.
func wait_for_crop_window(kind: String, duration: float) -> void:
	var weather = World.WEATHER
	var now := float(world.state.time)
	var day := int(weather.day_index(now))
	var day_end: float = (day + 1) * weather.DAY_SECONDS
	if World.crop_grows_in_season(kind, "home", FARM_ANCHOR, now) and now + duration < day_end:
		return
	for offset in range(1, weather.DAYS_PER_SEASON * weather.SEASONS.size() + 1):
		var morning: float = (day + offset) * weather.DAY_SECONDS
		if World.crop_grows_in_season(kind, "home", FARM_ANCHOR, morning):
			advance(morning - now, "wait for %s growing season" % kind)
			return
	expect(false, "No growing season for " + kind)

func grow_food() -> void:
	var reserved := {stove:true, seats[0]:true, seats[1]:true, bed:true}
	for pass_index in range(MAX_FOOD_ROUNDS):
		if failed:return
		var raw := raw_needed()
		var pending := {}
		for k in own_crop_keys():
			var crop: Dictionary = world.state.crops[k]
			if crop.kind != "":pending[crop.kind] = int(pending.get(crop.kind,0)) + int(World.CROPS[crop.kind]["yield"])
		var plots := {}
		for item in raw:
			if not World.CROPS.has(item):
				expect(false, "BLOCKER: recipe ingredient %s is not a crop this journey can grow" % item)
				return
			var short := int(raw[item]) - held(item) - int(pending.get(item,0))
			if short > 0:plots[item] = ceili(float(short) / float(World.CROPS[item]["yield"]))
		print("KITCHEN food round=%d raw=%s pending=%s new_plots=%s" % [pass_index, JSON.stringify(raw), JSON.stringify(pending), JSON.stringify(plots)])
		var enough := true
		for item in raw:
			if held(item) < int(raw[item]):enough = false
		if enough:return
		for crop in plots:
			var seed_item: String = crop + "_seed"
			while held(seed_item) < int(plots[crop]) and not failed:
				var price := int(World.CROPS[crop].seed_price)
				if int(person().coins) < price:
					expect(false, "BLOCKER: %d coins cannot buy %s (%d) and no seed source remains" % [int(person().coins), seed_item, price])
					return
				var before := bag().duplicate(true)
				var coins := int(person().coins)
				run("buy", World.Village.NPCS.xiaoli.cell, crop)
				expect_delta(before, {seed_item:1}, "Buying " + seed_item)
				expect(coins - int(person().coins) == price, "%s cost its seed_price %d" % [seed_item, price])
				seeds_bought[seed_item] = int(seeds_bought.get(seed_item,0)) + 1
			for n in int(plots[crop]):
				if failed:return
				var plot := NO_CELL
				for k in own_crop_keys():
					if world.state.crops[k].kind == "":
						plot = World.cell(k)
						break
				if plot == NO_CELL:
					plot = hoe_cell(reserved)
					if plot == NO_CELL:
						expect(false, "BLOCKER: no free reachable farm cell for " + crop)
						return
					run("hoe", plot)
				var before := bag().duplicate(true)
				run("seed", plot, crop)
				expect_delta(before, {seed_item:-1}, "Sowing " + crop)
		for item in raw:
			var batch := own_crop_keys().filter(func(k): return world.state.crops[k].kind == item)
			if batch.is_empty():continue
			var duration := float(World.CROPS[item].time)
			wait_for_crop_window(item, duration)
			for k in batch:
				if not world.state.crops[k].wet:run("water", World.cell(k))
			advance(duration, "crop growth round %d: %s" % [pass_index, item])
		for k in own_crop_keys():
			var crop: Dictionary = world.state.crops[k]
			if crop.kind == "" or float(crop.growth) < float(World.CROPS[crop.kind].time):continue
			var kind: String = crop.kind
			var before := bag().duplicate(true)
			run("harvest", World.cell(k))
			expect_delta(before, {kind:int(World.CROPS[kind]["yield"])}, "Harvesting " + kind)
			harvested[kind] = int(harvested.get(kind,0)) + int(World.CROPS[kind]["yield"])
	var final_raw := raw_needed()
	for item in final_raw:
		expect(held(item) >= int(final_raw[item]), "BLOCKER: still short of %s after %d farming rounds" % [item, MAX_FOOD_ROUNDS])

func cook_meal(meal: String, first: bool) -> void:
	var recipe: Dictionary = World.RECIPES[meal]
	var before := bag().duplicate(true)
	var started := float(world.state.time)
	run("cook", stove, meal)
	if failed:return
	expect_delta(before, negate(recipe.ingredients), "Cooking %s consumed its recipe ingredients" % meal)
	var job: Dictionary = world.state.objects[World.key(stove)].get("job", {})
	expect(job.get("kind","") == meal and is_equal_approx(float(job.get("ready",-1.0)) - started, float(recipe.time)) and int(job.get("yield",0)) == int(recipe["yield"]), "%s job takes recipe time %.1fs and yields %d" % [meal, float(recipe.time), int(recipe["yield"])])
	if first:
		probe("claim_cook", stove, "", "Claiming %s before its recipe time" % meal, "秒")
	advance(float(recipe.time), "cook " + meal)
	var held_before := bag().duplicate(true)
	run("claim_cook", stove)
	if failed:return
	expect_delta(held_before, {meal:int(recipe["yield"])}, "Claiming %s" % meal)
	earned[meal] = int(earned[meal]) + int(recipe["yield"])

func contribute(label: String) -> Dictionary:
	var before := bag().duplicate(true)
	var meals_before: Dictionary = world.state.public_kitchen.meals.duplicate()
	var result := run(PK.CONTRIBUTE, stove, "")
	if failed:return result
	var given: Dictionary = result.get("contributed", {})
	var expected := {}
	for meal in PK.MEALS:
		var take := mini(int(PK.REQUIREMENTS[meal]) - int(meals_before[meal]), int(before.get(meal,0)))
		if take > 0:expected[meal] = take
	expect(JSON.stringify(given) == JSON.stringify(expected), "%s contributed min(held, outstanding) = %s (got %s)" % [label, JSON.stringify(expected), JSON.stringify(given)])
	expect_delta(before, negate(expected), label)
	for meal in expected:contributed[meal] = int(contributed[meal]) + int(expected[meal])
	return result

# --- journey --------------------------------------------------------------------

func after_chapter() -> void:
	if failed:
		print("KITCHEN_JOURNEY skipped=chapter_failed passed=false")
		return
	var walked_before := walking
	var position_before := Vector2(person().x, person().y)
	var table := World.COMMUNITY.table_cell(world.state)
	var post_chapter := bag().duplicate(true)
	print("KITCHEN post_chapter inventory=%s coins=%d table=%s" % [JSON.stringify(post_chapter), int(person().coins), table])
	expect(world.state.picnic and table != NO_CELL and PK.stage(world.state) == "register" and not PK.registered(world.state), "Real picnic opened kitchen registration (stage register)")
	var ev := PK.events(world.state)
	expect(ev.size() == 1 and ev[0].id == "kitchen_invitation", "Only the picnic invitation page is unlocked before registration")
	for meal in PK.MEALS:
		expect(held(meal) == 0, "Picnic consumed every %s; kitchen meals must be cooked anew" % meal)
	expect(JSON.stringify(PK.REQUIREMENTS) == JSON.stringify({"soup":4, "bread":2, "salad":2}), "Kitchen requirements are 4 soup, 2 bread, 2 salad")

	plan_site()
	if failed:return

	# Long bench is gated by Aru's story: the real build is refused first.
	expect(not World.Village.unlocked(person(), "long_bench"), "long_bench still locked after the chapter")
	probe("build", seats[0], "long_bench", "Building a long bench before Aru's story", "委託")

	# Materials: bed + Aru story items + stove + two long benches, all from data.
	var quests: Array = World.Village.QUESTS.aru
	var need := {}
	var plan := [cost_of(World.BUILD.bed), quests[0].items, quests[1].items, cost_of(World.BUILD.stove), cost_of(World.BUILD.long_bench), cost_of(World.BUILD.long_bench)]
	for part in plan:
		for item in part:need[item] = int(need.get(item,0)) + int(part[item])
	print("KITCHEN material_plan=%s holding=%s" % [JSON.stringify(need), JSON.stringify(post_chapter)])
	var sources := {"wood":["tree"], "stone":["rock"], "fiber":["grass","tree"]}
	var before_gather := bag().duplicate(true)
	for item in need:
		if not sources.has(item):
			expect(false, "BLOCKER: no natural source known for " + item)
			return
		gather(item, int(need[item]), sources[item])
		if failed:return
	for item in ["wood","stone","fiber"]:
		gathered[item] = held(item) - int(before_gather.get(item,0))
	expect(gather_hits > 0 and gather_sources > 0 and int(gathered.wood) > 0, "Real gathering was needed and performed (%d sources, %d hits, %s)" % [gather_sources, gather_hits, JSON.stringify(gathered)])

	# Aru story 0: own bed + wood.
	var aru_cell: Vector2i = World.Village.NPCS.aru.cell
	var snap := bag().duplicate(true)
	run("build", bed, "bed")
	expect_delta(snap, negate(cost_of(World.BUILD.bed)), "Bed build")
	for stage in [0, 1]:
		var quest: Dictionary = quests[stage]
		var coins := int(person().coins)
		snap = bag().duplicate(true)
		run("quest", aru_cell, "aru:%d" % stage)
		if failed:return
		var delta := negate(quest.items)
		for item in quest.reward:delta[item] = int(delta.get(item,0)) + int(quest.reward[item])
		expect_delta(snap, delta, "Aru story %d" % stage)
		expect(int(person().coins) - coins == int(quest.coins) and int(person().stories.aru) == stage + 1, "Aru story %d paid %d coins and advanced" % [stage, int(quest.coins)])
	expect(World.Village.unlocked(person(), "long_bench") and quests[1].get("unlock","") == "long_bench", "Aru story 1 unlocked the long_bench blueprint normally")

	# Own stove + two long benches near the shared table.
	for piece in [[stove, "stove"], [seats[0], "long_bench"], [seats[1], "long_bench"]]:
		snap = bag().duplicate(true)
		run("build", piece[0], piece[1])
		if failed:return
		expect_delta(snap, negate(cost_of(World.BUILD[piece[1]])), "Build %s at %s" % [piece[1], piece[0]])
		var obj: Dictionary = world.state.objects.get(World.key(piece[0]), {})
		expect(obj.get("type","") == piece[1] and obj.get("owner","") == TOKEN, "%s at %s is owned by the builder" % [piece[1], piece[0]])
	var home_view := world.region_snapshot(HOME)
	expect(PK.key(stove) in PK.candidate_stoves(home_view, TOKEN), "New stove is a registration candidate")
	var seat_options := PK.candidate_seats(home_view, TOKEN, stove)
	expect(PK.key(seats[0]) in seat_options and PK.key(seats[1]) in seat_options, "Both new benches are seat candidates for the stove")
	probe(PK.CONTRIBUTE, stove, "", "Contributing before registration", "還沒有登記")

	# Explicit registration.
	snap = bag().duplicate(true)
	var coins_before := int(person().coins)
	var reg := run(PK.REGISTER, stove, PK.seat_extra(seats[0], seats[1]))
	if failed:return
	expect_delta(snap, {}, "Registration (donation costs nothing)")
	expect(int(person().coins) == coins_before, "Registration costs no coins")
	expect(reg.get("stove","") == PK.key(stove) and PK.stage(world.state) == "collect" and JSON.stringify(PK.outstanding(world.state)) == JSON.stringify(PK.REQUIREMENTS), "Kitchen registered at %s and collecting the full requirements" % stove)
	var sorted_seats := [PK.key(seats[0]), PK.key(seats[1])]
	sorted_seats.sort()
	expect(JSON.stringify(world.state.public_kitchen.seats) == JSON.stringify(sorted_seats), "Recorded seats are exactly the two chosen benches")
	for c in [stove, seats[0], seats[1]]:
		expect(world.protected(c) and PK.is_site_cell(world.state, c), "Donated cell %s is protected" % c)
	ev = PK.events(world.state)
	expect(ev.size() == 2 and ev[1].id == "kitchen_registration", "Registration page unlocked")
	probe("remove", seats[0], "", "Removing a donated bench", PK.MSG_LOCKED)
	probe("move_object", stove, "%d,%d" % [stove.x, stove.y+1], "Moving the donated stove", PK.MSG_LOCKED)
	probe(PK.CONTRIBUTE, stove, "", "Contributing with no meals in the bag", "背包裡沒有")

	# Grow / buy / cook every kitchen meal on the donated stove.
	grow_food()
	if failed:return
	for meal in PK.MEALS:
		var cooks := ceili(float(maxi(0, int(PK.outstanding(world.state)[meal]) - held(meal))) / float(World.RECIPES[meal]["yield"]))
		for n in cooks:
			cook_meal(meal, n == 0 and meal == "soup")
			if failed:return
		if meal == "soup":
			var partial := contribute("Partial soup contribution")
			expect(not bool(partial.get("opened", true)) and PK.stage(world.state) == "collect", "Kitchen stays closed after a partial contribution")
	var closing := contribute("Final contribution")
	if failed:return
	expect(bool(closing.get("opened",false)) and PK.stage(world.state) == "open" and world.state.public_kitchen.opened, "Kitchen opened")
	for meal in PK.MEALS:
		expect(int(world.state.public_kitchen.meals[meal]) == int(PK.REQUIREMENTS[meal]) and int(contributed[meal]) == int(PK.REQUIREMENTS[meal]), "%s filled exactly to %d" % [meal, int(PK.REQUIREMENTS[meal])])
		expect(int(earned[meal]) >= int(contributed[meal]) and int(post_chapter.get(meal,0)) == 0, "Every contributed %s was cooked in this journey (earned %d)" % [meal, int(earned[meal])])
	ev = PK.events(world.state)
	expect(ev.size() == 3 and ev[2].id == "kitchen_opening", "Opening page unlocked")
	probe(PK.CONTRIBUTE, stove, "", "Contributing after opening", "開張")
	expect(World.CHAPTER_ONE.phase(world.state) == "complete", "Chapter one stays complete")
	expect(walking > walked_before and Vector2(person().x, person().y).distance_to(position_before) > 0.0, "Kitchen slice walked real tiles (%d)" % (walking - walked_before))
	checkpoint("kitchen-final")

	verify_reload_and_replay()
	print("KITCHEN_JOURNEY actions=%d walk_tiles=%d gather_sources=%d gather_hits=%d gathered=%s seeds_bought=%s harvested=%s earned=%s contributed=%s probes=%d world_steps=%d simulated_world_seconds=%.1f(World.step,not_wall_clock) total_world_time=%.1f stove=%s seats=%s bed=%s inventory=%s passed=%s" % [actions, walking, gather_sources, gather_hits, JSON.stringify(gathered), JSON.stringify(seeds_bought), JSON.stringify(harvested), JSON.stringify(earned), JSON.stringify(contributed), probes, sim_steps, sim_seconds, float(world.state.time), stove, JSON.stringify(sorted_seats), bed, JSON.stringify(bag()), not failed])
	print("KITCHEN_JOURNEY_TESTS checks=%d failures=%d (cumulative with chapter part)" % [checks, failures])

func kitchen_text(state: Dictionary) -> String:
	var data: Dictionary = state.public_kitchen
	var meals := {}
	for meal in PK.MEALS:meals[meal] = int(data.meals[meal])
	return JSON.stringify({"stove":str(data.stove), "seats":data.seats, "meals":meals, "opened":bool(data.opened)})

func verify_reload_and_replay() -> void:
	if failed:return
	var path := world.save_path
	var live_kitchen := kitchen_text(world.state)
	var live_events := JSON.stringify(PK.events(world.state))
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	expect(parsed is Dictionary and parsed.get("public_kitchen", {}).get("opened", false) == true and int(parsed.get("version",0)) == World.SAVE_SCHEMA.VERSION, "Primary save file on disk holds the opened kitchen at the current schema version")
	var reload := World.new()
	expect(reload.load_world(path) and not reload.recovered_from_backup, "Kitchen world reloads from the primary save")
	if failed:return
	expect(kitchen_text(reload.state) == live_kitchen, "Reloaded public_kitchen equals the live one")
	expect(JSON.stringify(PK.events(reload.state)) == live_events and PK.events(reload.state).size() == 3, "Reloaded world unlocks the same three story pages")
	for c in [stove, seats[0], seats[1]]:
		var obj: Dictionary = reload.state.objects.get(World.key(c), {})
		expect(obj.get("owner","") == TOKEN and reload.protected(c), "Donated %s at %s persisted and stays protected" % [obj.get("type","?"), c])
	var saved_player: Dictionary = reload.state.players[TOKEN]
	expect(same_inventory(saved_player.inventory, bag()) and int(saved_player.coins) == int(person().coins) and int(saved_player.stories.aru) == 2, "Builder inventory, coins and Aru story persisted")

	# Brand-new member joins the reloaded world (normal add_player) and replays.
	reload.add_player(LATE, "Late")
	var late: Dictionary = reload.state.players[LATE]
	expect(same_inventory(late.inventory, default_stock) and int(late.coins) == default_coins, "Late member starts with the normal stock and no meals")
	expect(reload.player_region(LATE) == HOME, "Late member arrives at home")
	var state_before := JSON.stringify(reload.state)
	var file_before := FileAccess.get_file_as_string(path)
	var first := ""
	var replays_equal := true
	for i in REPLAYS:
		var view := reload.region_snapshot(HOME)
		var pages := PK.events(view)
		var replay := JSON.stringify({"pages":pages, "stage":PK.stage(view), "outstanding":PK.outstanding(view), "aru":World.COMMUNITY.resident_line(view,"aru"), "milu":World.COMMUNITY.resident_line(view,"milu")})
		if i == 0:
			first = replay
			expect(pages.size() == 3 and JSON.stringify(pages) == live_events and PK.stage(view) == "open", "Late member sees all three unlocked pages and the open stage")
			expect(not JSON.stringify(view.public_kitchen).contains(TOKEN), "Kitchen snapshot carries no player id")
		elif replay != first:
			replays_equal = false
	print("KITCHEN replay member=late pages=%d replays=%d" % [PK.events(reload.region_snapshot(HOME)).size(), REPLAYS])
	expect(replays_equal, "Repeated replays are identical")
	expect(JSON.stringify(reload.state) == state_before, "Replaying %d times did not mutate the world" % REPLAYS)
	expect(FileAccess.get_file_as_string(path) == file_before and file_before == text, "Replaying did not write the save")
	verify_late_cooking(reload)

func verify_late_cooking(reloaded:World) -> void:
	if failed:return
	var original:=world
	var late_path:String=reloaded.save_path+".late"
	reloaded.save_path=late_path
	world=reloaded
	var growth:=float(World.CROPS.radish.time)
	wait_for_crop_window("radish",growth+2.0)
	var plots:Array[Vector2i]=[]
	for y in range(33,40):
		for x in range(36,46):
			var tile:=Vector2i(x,y)
			if free_cell(tile) and not route(tile,2.0,LATE).is_empty():plots.append(tile)
			if plots.size()==2:break
		if plots.size()==2:break
	expect(plots.size()==2,"Late member can walk to two unclaimed farm tiles")
	for tile in plots:
		late_action("hoe",tile)
		late_action("seed",tile,"radish")
		late_action("water",tile)
	advance(growth+0.1,"late member grows starter radishes")
	for tile in plots:late_action("harvest",tile)
	var newcomer:Dictionary=world.state.players[LATE]
	expect(int(newcomer.inventory.get("radish",0))>=2 and int(newcomer.get("crafting_points",0))==0,
		"Late member harvested required crops without inherited crafting experience")
	late_action("queue_cook",stove,"soup")
	advance(float(World.RECIPES.soup.time),"late member cooks at the public stove")
	late_action("claim_cook",stove)
	expect(int(world.state.players[LATE].inventory.get("soup",0))==2 and int(world.state.players[LATE].coins)==default_coins,
		"Late member prepares and collects two bowls using only starter seeds")
	expect(world.load_world(late_path) and int(world.state.players[LATE].inventory.get("soup",0))==2,"Late member's meal survives reloading")
	world=original
	for file in [late_path,late_path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)

func late_action(action:String,tile:Vector2i,extra:="") -> void:
	walk_to(tile,2.0,LATE)
	if failed:return
	actions+=1
	var result:=world.act(LATE,"late-%d"%actions,action,tile,extra)
	expect(result.ok,"Late member %s: %s"%[action,result.message])
