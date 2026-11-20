extends "res://tests/test_public_kitchen_journey.gd"

# Earned bakery journey (Q05: work/claude-agents/bakery_core.txt +
# game/docs/bakery-contract.json). LABEL: scripted World-API journey, NOT human play.
#
# Continues the REAL chapter-one journey (test_chapter_journey.gd) and the REAL
# public-kitchen journey (test_public_kitchen_journey.gd) for the same single player.
# after_chapter() first runs super.after_chapter() unchanged (all parent checks,
# its reload and its late-member replay), then, only if nothing failed:
#   1. premise: kitchen really opened by the parent; contract values read from data;
#   2. site plan (read-only scratch planner): bench / sawmill / mill row + stand cell
#      that keeps every path and the donated kitchen reachable;
#   3. farming: buy a pumpkin seed (and missing wheat seeds) at the normal stall with
#      coins earned earlier (selling surplus produce / growing radish if short), sow
#      and water pumpkin + wheat;
#   4. natural gathering of every wood/stone/fiber unit the workshop needs;
#   5. own bench, reinforced pick, sawmill kit + sawmill, plank x8 through the
#      normal sawmill manual queue;
#   6. copper ore from the real home copper point (reinforced pick, 12 s restock),
#      copper_joint x4 at the bench;
#   7. mill_kit (plank 8, stone 16, copper_joint 4) and the mill itself;
#   8. harvest pumpkin + wheat; feed (stove) -> hen -> egg through the existing actions;
#   9. wheat 2 -> flour 1 through the mill's normal manual queue;
#  10. pumpkin pie on the parent's DONATED stove, claim 4;
#  11. normal primary-save reload (counts, collection, devices), a read-only late
#      member join of the reloaded in-process world, optional --checkpoint-dir= dump.
#
# Mutation rules: the live world changes only through World.act, World.move_player
# (inherited BFS walk_to plus a one-tile cardinal step onto the stand cell) and
# World.step (every call goes through bk_step, which prints the label and the
# SIMULATED world seconds — never wall clock). Nothing is seeded: no stock, flag,
# position, device, crop, recipe or reward state is written by this script. Scratch
# World instances are read-only planners (inherited layout_ok) and are never saved.
# Networking is NOT exercised: the late join is an in-process add_player only.
#
# Output (documented so nothing from the parents is misread):
#   KITCHEN ... / KITCHEN_JOURNEY ...   unchanged parent slice (runs first)
#   BAKERY ...                          one line per action / probe / step of this slice
#   BAKERY_JOURNEY ...                  slice summary (passed=... is the overall verdict)
#   BAKERY_JOURNEY_TESTS checks=N failures=N   CUMULATIVE with chapter + kitchen parts
#   then the chapter runner prints CHAPTER_JOURNEY / CHAPTER_JOURNEY_TESTS (also
#   cumulative), removes the temp save and its .bak, and quit(int(failed)).
# Any impossible step is an expect(false, "BLOCKER: ...") failure; later stages are
# skipped once anything failed; every loop is bounded.

const BK_LATE := "bakery-late-member"
const BK_NONE := Vector2i(-1,-1)
const BK_LEFT := Vector2i(-1,0)
const BK_RIGHT := Vector2i(1,0)
const BK_FAR := Vector2i(2,0)
const BK_DOWN := Vector2i(0,1)
const BK_SITE_RING := 12
const BK_MAX_SITE_TRIES := 24
const BK_MAX_SOURCES := 60
const BK_MAX_COPPER := 12
const BK_MAX_CRAFTS := 8
const BK_MAX_CASH_PLOTS := 10
const BK_MAX_BUYS := 12
const BK_CHICKEN := Vector2i(45,34)
const BK_PIE := "pumpkin_pie"
const BK_FINAL_STAGE := "bakery-final"
const BK_PLANKS := 8
const BK_JOINTS := 4

var bk_bench := BK_NONE
var bk_sawmill := BK_NONE
var bk_mill := BK_NONE
var bk_stand := BK_NONE
var bk_action_start := 0
var bk_walk_start := 0
var bk_coins_start := 0
var bk_probes := 0
var bk_steps := 0
var bk_seconds := 0.0
var bk_site_checks := 0
var bk_gather_sources := 0
var bk_gather_hits := 0
var bk_gathered := {}
var bk_bought := {}
var bk_sold := {}
var bk_harvested := {}
var bk_made := {}
var bk_copper_mines := 0
var bk_plots: Array = []
var bk_needs_feed := false
var bk_wheat_need := 0
var bk_need_pick := false
var bk_plank_jobs := 0
var bk_plank_done := 0.0

# --- checkpoint (parent behaviour kept, optional final dump added) --------------

func checkpoint(stage: String) -> void:
	super.checkpoint(stage)
	if stage != BK_FINAL_STAGE or failed:return
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--checkpoint-dir="):continue
		var dir := argument.trim_prefix("--checkpoint-dir=")
		if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
			expect(false, "--checkpoint-dir must name an existing directory (got '%s')" % dir)
			return
		var target := dir.path_join("bakery-final.json")
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			expect(false, "Open bakery checkpoint " + target)
			return
		file.store_string(JSON.stringify(world.state))
		file.flush()
		var status := file.get_error()
		file.close()
		expect(status == OK, "Write bakery checkpoint " + target)
		print("BAKERY checkpoint written=%s" % target)

# --- small helpers ------------------------------------------------------------

func bk_here() -> Vector2i:
	return Vector2i(floori(person().x), floori(person().y))

func bk_near(target: Vector2i, limit: float = 3.0) -> bool:
	return Vector2(person().x, person().y).distance_to(Vector2(target)+Vector2(0.5,0.5)) <= limit

func bk_sum(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for item in b:out[item] = int(out.get(item,0)) + int(b[item])
	return out

func bk_count(store: Dictionary, item: String, amount: int) -> void:
	store[item] = int(store.get(item,0)) + amount

func bk_obj(c: Vector2i) -> Dictionary:
	return world.state.objects.get(World.key(c), {})

func bk_queue_ids(c: Vector2i) -> Array:
	var out := []
	var q = bk_obj(c).get("processing")
	if not q is Dictionary:return out
	if not (q.active as Dictionary).is_empty():out.append(str(q.active.id))
	for list in [q.waiting, q.ready]:
		for entry in list:out.append(str(entry.id))
	return out

func bk_reserved() -> Dictionary:
	var out := {}
	for c in [stove, seats[0], seats[1], bed, bk_bench, bk_sawmill, bk_mill, bk_stand]:
		if c != BK_NONE:out[c] = true
	if bk_bench != BK_NONE:out[bk_bench + BK_RIGHT] = true
	return out

# One real World.act; walks the inherited BFS route only when out of reach.
func bk_run(action: String, target: Vector2i, extra: String = "") -> Dictionary:
	if failed:return {}
	if not bk_near(target):walk_to(target)
	if failed:return {}
	actions += 1
	var result: Dictionary = world.act(TOKEN, "journey-%d" % actions, action, target, extra)
	print("BAKERY %d %s %s %s | ok=%s %s | wood=%d stone=%d fiber=%d plank=%d ore=%d joint=%d wheat=%d coins=%d" % [actions, action, target, extra, result.get("ok"), result.get("message",""), held("wood"), held("stone"), held("fiber"), held("plank"), held("copper_ore"), held("copper_joint"), held("wheat"), int(person().coins)])
	expect(bool(result.get("ok",false)), "Bakery action failed: %s %s %s (%s)" % [action, target, extra, result.get("message","")])
	return result

# Labelled failure probe: MUST be rejected by the real rules with no state change.
func bk_probe(action: String, target: Vector2i, extra: String, label: String, needle: String = "") -> Dictionary:
	if failed:return {}
	if not bk_near(target):walk_to(target)
	if failed:return {}
	var before := JSON.stringify(world.state)
	bk_probes += 1
	var result: Dictionary = world.act(TOKEN, "bakery-probe-%d" % bk_probes, action, target, extra)
	print("BAKERY probe %d [%s] %s %s %s | ok=%s %s" % [bk_probes, label, action, target, extra, result.get("ok"), result.get("message","")])
	expect(not bool(result.get("ok",true)) and JSON.stringify(world.state) == before, "PROBE " + label + " is rejected without any state change")
	if not needle.is_empty():
		expect(str(result.get("message","")).contains(needle), "PROBE %s names the real reason (%s)" % [label, needle])
	return result

func bk_step(seconds: float, label: String) -> void:
	if failed or seconds <= 0.0:return
	bk_steps += 1
	bk_seconds += seconds
	var t0 := float(world.state.time)
	print("BAKERY step %d '%s' simulated_world_seconds=%.1f world_time=%.1f->%.1f (World.step, not wall clock)" % [bk_steps, label, seconds, t0, t0 + seconds])
	expect(world.step(seconds, true), "World.step for " + label)

# Walk onto `tile`: inherited route to a cardinal neighbour, then one real step.
func bk_stand_at(tile: Vector2i) -> void:
	if failed or bk_here() == tile:return
	walk_to(tile, 1.0)
	if failed:return
	var d := Vector2(tile - bk_here())
	if not is_equal_approx(d.length(), 1.0):
		expect(false, "BLOCKER: no cardinal approach onto stand cell %s" % tile)
		return
	for i in 4:world.move_player(TOKEN, d, 0.25/3.6)
	walking += 1
	expect(bk_here() == tile, "Walked onto stand cell %s" % tile)

func bk_buy(crop: String, want: int) -> void:
	var seed_item := crop + "_seed"
	var price := int(World.CROPS[crop].seed_price)
	var tries := 0
	while held(seed_item) < want and not failed:
		tries += 1
		if tries > BK_MAX_BUYS:
			expect(false, "BLOCKER: buying %s exceeded %d purchases" % [seed_item, BK_MAX_BUYS])
			return
		if int(person().coins) < price:
			expect(false, "BLOCKER: %d coins cannot buy %s (%d)" % [int(person().coins), seed_item, price])
			return
		var snap := bag().duplicate(true)
		var coins := int(person().coins)
		bk_run("buy", World.Village.NPCS.xiaoli.cell, crop)
		if failed:return
		expect_delta(snap, {seed_item:1}, "Buying " + seed_item)
		expect(coins - int(person().coins) == price, "%s cost its seed_price %d at the stall" % [seed_item, price])
		bk_count(bk_bought, seed_item, 1)

# Sow `count` plots of `crop` (reusing own empty plots first), water each.
func bk_sow(crop: String, count: int) -> Array:
	var keys := []
	var seed_item := crop + "_seed"
	for n in count:
		if failed:return keys
		var plot := BK_NONE
		for k in own_crop_keys():
			if world.state.crops[k].kind == "":
				plot = World.cell(k)
				break
		if plot == BK_NONE:
			plot = hoe_cell(bk_reserved())
			if plot == BK_NONE:
				expect(false, "BLOCKER: no free reachable farm cell for " + crop)
				return keys
			bk_run("hoe", plot)
		var snap := bag().duplicate(true)
		bk_run("seed", plot, crop)
		if failed:return keys
		expect_delta(snap, {seed_item:-1}, "Sowing " + crop)
		bk_run("water", plot)
		var placed: Dictionary = world.state.crops.get(World.key(plot), {})
		expect(placed.get("kind","") == crop and bool(placed.get("wet",false)) and placed.get("owner","") == TOKEN, "%s sown and watered at %s" % [crop, plot])
		keys.append(World.key(plot))
	return keys

func bk_harvest(keys: Array, label: String) -> void:
	var batches := {}
	for k in keys:
		var kind: String = world.state.crops.get(k, {}).get("kind", "")
		if kind.is_empty():
			expect(false, "BLOCKER: own plot %s lost its crop before harvest" % k)
			return
		if not batches.has(kind):batches[kind] = []
		batches[kind].append(k)
	for kind in batches:
		var duration := float(World.CROPS[kind].time)
		wait_for_crop_window(kind, duration)
		for k in batches[kind]:
			if not world.state.crops[k].wet:bk_run("water", World.cell(k))
		bk_step(duration, label + ": " + kind)
	for k in keys:
		if failed:return
		var plot:Dictionary=world.state.crops[k]
		var kind:String=plot.kind
		var snap := bag().duplicate(true)
		var gain:=int(World.CROPS[kind]["yield"])
		var delta:Dictionary={kind:gain}
		var quality:=World.quality_crop(plot,World.has_crop_guarantee(person()))
		if not quality.is_empty():delta[quality]=1
		bk_run("harvest", World.cell(k))
		if failed:return
		expect_delta(snap,delta,"Harvesting "+kind)
		bk_count(bk_harvested, kind, gain)

func bk_gather(item: String, minimum: int, kinds: Array) -> void:
	var rounds := 0
	while held(item) < minimum and not failed:
		rounds += 1
		if rounds > BK_MAX_SOURCES:
			expect(false, "BLOCKER: gathering %s exceeded %d sources" % [item, BK_MAX_SOURCES])
			return
		var target := BK_NONE
		var kind := ""
		for candidate in kinds:
			target = find_resource(candidate)
			if target != BK_NONE:
				kind = candidate
				break
		if target == BK_NONE:
			expect(false, "BLOCKER: no reachable natural source for %s (need %d, hold %d)" % [item, minimum, held(item)])
			return
		var tool := "pick" if kind == "rock" else "axe"
		var hits := 0
		while world.resource(target) == kind and hits < MAX_HITS and not failed:
			bk_run(tool, target)
			hits += 1
		expect(world.resource(target) == "", "Natural %s at %s fully gathered in %d hits" % [kind, target, hits])
		if not failed:collect_gathered(target)
		bk_gather_hits += hits
		bk_gather_sources += 1

func bk_craft(recipe_id: String, target_count: int) -> void:
	var recipe: Dictionary = World.CRAFT[recipe_id]
	var n := 0
	while held(recipe_id) < target_count and not failed:
		n += 1
		if n > BK_MAX_CRAFTS:
			expect(false, "BLOCKER: crafting %s exceeded %d crafts" % [recipe_id, BK_MAX_CRAFTS])
			return
		var snap := bag().duplicate(true)
		bk_run("craft", bk_bench, recipe_id)
		if failed:return
		expect_delta(snap, bk_sum(negate(recipe.ingredients), {recipe_id:int(recipe["yield"])}), "Crafting " + recipe_id)
		bk_count(bk_made, recipe_id, int(recipe["yield"]))

func bk_build(cell: Vector2i, kind: String) -> void:
	bk_stand_at(bk_stand)
	var snap := bag().duplicate(true)
	bk_run("build", cell, kind)
	if failed:return
	expect_delta(snap, negate(cost_of(World.BUILD[kind])), "Build %s at %s" % [kind, cell])
	expect(bk_obj(cell).get("type","") == kind and bk_obj(cell).get("owner","") == TOKEN and world.blocked(cell), "%s at %s is owned by the builder and solid" % [kind, cell])

# --- journey --------------------------------------------------------------------

func after_chapter() -> void:
	super.after_chapter()
	if failed:
		print("BAKERY_JOURNEY skipped=parent_failed passed=false")
		print("BAKERY_JOURNEY_TESTS checks=%d failures=%d (cumulative with chapter and kitchen parts)" % [checks, failures])
		return
	bk_action_start = actions
	bk_walk_start = walking
	bk_coins_start = int(person().coins)
	for stage in ["bk_premise", "bk_plan_site", "bk_farm", "bk_materials", "bk_workshop", "bk_copper", "bk_mill_build", "bk_harvest_crops", "bk_egg", "bk_flour", "bk_pie", "bk_persist"]:
		if failed:
			print("BAKERY stopped_before=%s (earlier failure)" % stage)
			break
		call(stage)
	print("BAKERY_JOURNEY label=scripted-world-api-not-human-play actions=%d(total %d) walk_tiles=%d(total %d) gather_sources=%d gather_hits=%d gathered=%s seeds_bought=%s sold=%s harvested=%s copper_mines=%d made=%s probes=%d world_steps=%d simulated_world_seconds=%.1f(World.step,not_wall_clock) total_world_time=%.1f coins=%d->%d bench=%s sawmill=%s mill=%s stand=%s donated_stove=%s pies=%d network=not_exercised inventory=%s passed=%s" % [actions - bk_action_start, actions, walking - bk_walk_start, walking, bk_gather_sources, bk_gather_hits, JSON.stringify(bk_gathered), JSON.stringify(bk_bought), JSON.stringify(bk_sold), JSON.stringify(bk_harvested), bk_copper_mines, JSON.stringify(bk_made), bk_probes, bk_steps, bk_seconds, float(world.state.time), bk_coins_start, int(person().coins), bk_bench, bk_sawmill, bk_mill, bk_stand, stove, held(BK_PIE), JSON.stringify(bag()), not failed])
	print("BAKERY_JOURNEY_TESTS checks=%d failures=%d (cumulative with chapter and kitchen parts)" % [checks, failures])

func bk_premise() -> void:
	print("BAKERY start inventory=%s coins=%d world_time=%.1f" % [JSON.stringify(bag()), int(person().coins), float(world.state.time)])
	expect(world.kitchen_opened() and bool(world.state.public_kitchen.opened), "Parent journey really opened the public kitchen (mill unlock)")
	expect("mill_kit" in World.KITCHEN_GATED and "mill" in World.KITCHEN_GATED, "mill_kit and mill are kitchen-gated in data")
	var pumpkin: Dictionary = World.CROPS.get("pumpkin", {})
	expect(is_equal_approx(float(pumpkin.get("time",0)), 270.0) and int(pumpkin.get("seed_price",0)) == 70 and int(pumpkin.get("price",0)) == 150 and int(pumpkin.get("yield",0)) == 1, "Contract: pumpkin 270 s, seed 70, price 150, yield 1")
	# C13: the 3x3 mill is built from materials; mill_kit is no longer craftable. This journey keeps exercising the
	# legacy 1x1 placement (plain "mill" build while a kit is held) so its single-cell site layout stays valid; the
	# 3x3 world/logistics/blueprint/save contracts are covered by test_mill_c13*.gd.
	expect(not World.CRAFT.has("mill_kit"), "Contract: mill_kit is no longer a bench recipe")
	expect(World.BUILD.has("mill") and same_inventory(cost_of(World.BUILD.mill), {"wood":25, "stone":15, "woodwork_parts":4}), "Contract: the new mill costs wood 25 + stone 15 + woodwork_parts 4")
	expect(same_inventory(cost_of(World.LEGACY_MILL_COST), {"mill_kit":1}), "Contract: a legacy 1x1 mill is built from / refunds one mill_kit")
	var flour: Dictionary = World.INDUSTRY.PROCESS.get("flour", {})
	expect(flour.get("station","") == "mill" and same_inventory(flour.get("ingredients",{}), {"wheat":2}) and is_equal_approx(float(flour.get("time",0)), 60.0) and int(flour.get("yield",0)) == 1, "Contract: flour at mill, wheat 2, 60 s, yield 1")
	var pie: Dictionary = World.RECIPES.get(BK_PIE, {})
	expect(same_inventory(pie.get("ingredients",{}), {"pumpkin":1, "flour":1, "egg":1}) and is_equal_approx(float(pie.get("time",0)), 120.0) and int(pie.get("yield",0)) == 4 and int(World.OTHER_SALES.get(BK_PIE,0)) == 80, "Contract: pumpkin_pie = pumpkin+flour+egg, 120 s, yield 4, sells 80")
	var plank: Dictionary = World.INDUSTRY.PROCESS.get("plank", {})
	expect(plank.get("station","") == "sawmill" and same_inventory(World.CRAFT.copper_joint.ingredients, {"copper_ore":2, "wood":1}), "Premise: plank from sawmill; copper_joint = copper_ore 2 + wood 1 (unchanged)")
	for item in ["pumpkin", "pumpkin_seed", "flour", BK_PIE, "mill_kit"]:
		expect(held(item) == 0, "No %s in the bag before the bakery slice" % item)
	var mills := 0
	for k in world.state.objects:
		if world.state.objects[k].get("type","") == "mill":mills += 1
	expect(mills == 0, "No mill exists before the bakery slice")
	var coll: Dictionary = person().collection
	expect(not coll.meals.has(BK_PIE) and not coll.crops.has("pumpkin"), "Collection has no pumpkin or pumpkin pie yet")
	expect(stove != BK_NONE and bk_obj(stove).get("type","") == "stove" and PK.is_site_cell(world.state, stove), "Parent's donated stove %s is available" % stove)

func bk_plan_site() -> void:
	var base := passable_component(world)
	var kitchen: Array[Vector2i] = [stove, seats[0], seats[1]]
	var taken := {stove:true, seats[0]:true, seats[1]:true, bed:true}
	var cands := []
	for y in range(stove.y-BK_SITE_RING, stove.y+BK_SITE_RING+1):
		for x in range(stove.x-BK_SITE_RING, stove.x+BK_SITE_RING+1):
			var c := Vector2i(x,y)
			var ok := base.has(c + BK_DOWN)
			for t in [c, c+BK_LEFT, c+BK_RIGHT, c+BK_DOWN, c+BK_FAR]: # C08: the workbench is 2x1 (c, c+RIGHT); the mill moves one cell right
				if not ok:break
				if taken.has(t) or not free_cell(t):ok = false
			if ok:cands.append(c)
	by_distance(cands, stove)
	for cand in cands.slice(0, BK_MAX_SITE_TRIES):
		var c: Vector2i = cand
		bk_site_checks += 1
		if layout_ok(base, {c:"bench", c+BK_RIGHT:"bench", c+BK_LEFT:"sawmill", c+BK_FAR:"mill"}, kitchen):
			bk_bench = c
			bk_sawmill = c + BK_LEFT
			bk_mill = c + BK_FAR
			bk_stand = c + BK_DOWN
			break
	if bk_bench == BK_NONE:
		expect(false, "BLOCKER: no free bench/sawmill/mill row within %d of the stove that keeps every path open (%d candidates, %d checked)" % [BK_SITE_RING, cands.size(), bk_site_checks])
		return
	print("BAKERY site bench=%s sawmill=%s mill=%s stand=%s candidates=%d layout_checks=%d" % [bk_bench, bk_sawmill, bk_mill, bk_stand, cands.size(), bk_site_checks])

func bk_farm() -> void:
	bk_needs_feed = float(world.state.animal.egg_ready) < 0.0 and held("feed") < 1
	var flour_wheat := int(World.INDUSTRY.PROCESS.flour.ingredients.wheat)
	var feed_wheat := int(World.RECIPES.feed.ingredients.wheat)
	bk_wheat_need = flour_wheat + (feed_wheat if bk_needs_feed else 0)
	var wheat_short := maxi(0, bk_wheat_need - held("wheat"))
	var wheat_plots := ceili(float(wheat_short) / float(World.CROPS.wheat["yield"]))
	var pumpkin_plots := 1
	var buy_pumpkin := maxi(0, pumpkin_plots - held("pumpkin_seed"))
	var buy_wheat := maxi(0, wheat_plots - held("wheat_seed"))
	var required := buy_pumpkin * int(World.CROPS.pumpkin.seed_price) + buy_wheat * int(World.CROPS.wheat.seed_price)
	print("BAKERY farm_plan wheat_need=%d (feed=%s) wheat_held=%d wheat_plots=%d pumpkin_plots=%d seeds_to_buy=%s coins=%d required=%d" % [bk_wheat_need, bk_needs_feed, held("wheat"), wheat_plots, pumpkin_plots, JSON.stringify({"pumpkin_seed":buy_pumpkin, "wheat_seed":buy_wheat}), int(person().coins), required])
	bk_ensure_coins(required)
	if failed:return
	bk_buy("pumpkin", pumpkin_plots)
	bk_buy("wheat", wheat_plots)
	if failed:return
	expect(int(bk_bought.get("pumpkin_seed",0)) >= 1, "Pumpkin seed came from the vendor, paid with earned coins")
	bk_plots = bk_sow("pumpkin", pumpkin_plots)
	bk_plots.append_array(bk_sow("wheat", wheat_plots))

# Earn coins only if short: sell surplus earned goods, then (bounded) radish for sale.
func bk_ensure_coins(required: int) -> void:
	if int(person().coins) >= required or failed:return
	var stall: Vector2i = World.Village.NPCS.xiaoli.cell
	var keep := {"wheat":true, "pumpkin":true, "egg":true, "feed":true, "flour":true, BK_PIE:true}
	var sellable := []
	for group in [World.CROPS, World.FISH, World.OTHER_SALES]:
		for item in group:
			if not keep.has(item) and item not in sellable:sellable.append(item)
	for item in sellable:
		if int(person().coins) >= required or failed:break
		if held(item) <= 0:continue
		bk_sell(stall, item)
	var short := required - int(person().coins)
	if short <= 0 or failed:return
	var price := int(World.CROPS.radish.price)
	var plots := mini(BK_MAX_CASH_PLOTS, ceili(float(short) / float(price - int(World.CROPS.radish.seed_price))))
	print("BAKERY coin_shortfall=%d growing radish plots=%d for sale" % [short, plots])
	var affordable := held("radish_seed") + floori(float(person().coins) / float(World.CROPS.radish.seed_price))
	plots = mini(plots, affordable)
	if plots <= 0:
		expect(false, "BLOCKER: short %d coins with nothing to sell and no radish seed source" % short)
		return
	bk_buy("radish", plots)
	var keys := bk_sow("radish", plots)
	bk_harvest(keys, "radish cash crop")
	bk_sell(stall, "radish")
	expect(int(person().coins) >= required, "BLOCKER: still short of %d coins after selling surplus and one radish round" % required)

func bk_sell(stall: Vector2i, item: String) -> void:
	var count := held(item)
	var coins := int(person().coins)
	var snap := bag().duplicate(true)
	bk_run("sell", stall, item)
	if failed:return
	expect_delta(snap, {item:-count}, "Selling all %s" % item)
	expect(int(person().coins) > coins, "Selling %s paid coins" % item)
	bk_count(bk_sold, item, count)

func bk_materials() -> void:
	bk_need_pick = held("reinforced_pick") < 1
	if bk_need_pick and bool(person().get("crafted_reinforced_pick", false)):
		expect(false, "BLOCKER: reinforced pick already crafted once but not in the bag; it cannot be re-crafted")
		return
	bk_plank_jobs = ceili(float(maxi(0, BK_PLANKS - held("plank"))) / float(World.INDUSTRY.PROCESS.plank["yield"]))
	var joints := maxi(0, BK_JOINTS - held("copper_joint"))
	var need := {}
	var plan := [cost_of(World.BUILD.bench), World.CRAFT.sawmill_kit.ingredients]
	if bk_need_pick:plan.append(World.CRAFT.reinforced_pick.ingredients)
	if bk_needs_feed:plan.append(World.RECIPES.feed.ingredients)
	for part in plan:
		for item in part:
			if item in ["wood","stone","fiber"]:need[item] = int(need.get(item,0)) + int(part[item])
	need.wood = int(need.get("wood",0)) + bk_plank_jobs * int(World.INDUSTRY.PROCESS.plank.ingredients.wood) + joints * int(World.CRAFT.copper_joint.ingredients.wood)
	print("BAKERY material_plan=%s holding=%s plank_jobs=%d joints=%d pick_needed=%s" % [JSON.stringify(need), JSON.stringify(bag()), bk_plank_jobs, joints, bk_need_pick])
	var before := bag().duplicate(true)
	var sources := {"wood":["tree"], "stone":["rock"], "fiber":["grass","tree"]}
	for item in ["stone","wood","fiber"]:
		if need.has(item):bk_gather(item, int(need[item]), sources[item])
		if failed:return
	for item in ["wood","stone","fiber"]:
		bk_gathered[item] = held(item) - int(before.get(item,0))
	print("BAKERY gathered=%s sources=%d hits=%d" % [JSON.stringify(bk_gathered), bk_gather_sources, bk_gather_hits])

func bk_workshop() -> void:
	if bk_need_pick:
		bk_probe("mine_copper", World.COPPER_CELL, "", "Mining copper without a reinforced pick", "強化石鎬")
	bk_build(bk_bench, "bench")
	if failed:return
	bk_probe("craft", bk_bench, "mill_kit", "Crafting mill_kit (no longer a bench recipe)")
	bk_probe("craft", bk_bench, "woodwork_parts", "Crafting woodwork_parts without planks/hardwood", "材料不足")
	if bk_need_pick:bk_craft("reinforced_pick", 1)
	bk_craft("sawmill_kit", 1)
	bk_build(bk_sawmill, "sawmill")
	if failed:return
	bk_probe("queue_processing", bk_sawmill, "flour", "Queuing flour on a sawmill", "不能加工")
	var plank: Dictionary = World.INDUSTRY.PROCESS.plank
	var first := float(world.state.time)
	for j in bk_plank_jobs:
		var snap := bag().duplicate(true)
		bk_run("queue_processing", bk_sawmill, "plank")
		if failed:return
		expect_delta(snap, negate(plank.ingredients), "Queuing plank job %d" % (j+1))
	bk_plank_done = first + float(bk_plank_jobs) * float(plank.time)
	expect(bk_queue_ids(bk_sawmill).size() == bk_plank_jobs, "Sawmill manual queue holds %d plank jobs" % bk_plank_jobs)

func bk_copper() -> void:
	var target := 2 * maxi(0, BK_JOINTS - held("copper_joint"))
	var mines := 0
	while held("copper_ore") < target and not failed:
		mines += 1
		if mines > BK_MAX_COPPER:
			expect(false, "BLOCKER: copper mining exceeded %d attempts" % BK_MAX_COPPER)
			return
		if not bk_near(World.COPPER_CELL):walk_to(World.COPPER_CELL)
		var wait := float(world.state.copper.ready) - float(world.state.time)
		if wait > 0.0:bk_step(wait, "copper point restock")
		var snap := bag().duplicate(true)
		bk_run("mine_copper", World.COPPER_CELL)
		if failed:return
		var gain := held("copper_ore") - int(snap.get("copper_ore",0))
		expect(gain > 0, "Mining the copper point yielded ore (+%d)" % gain)
		expect_delta(snap, {"copper_ore":gain}, "Copper mining changed only copper_ore")
		bk_copper_mines += 1
		if mines == 1:
			bk_probe("mine_copper", World.COPPER_CELL, "", "Mining copper again before restock", "補充")
	bk_craft("copper_joint", BK_JOINTS)

func bk_mill_build() -> void:
	bk_step(bk_plank_done - float(world.state.time), "sawmill planks")
	var plank: Dictionary = World.INDUSTRY.PROCESS.plank
	for j in bk_plank_jobs:
		var snap := bag().duplicate(true)
		bk_run("claim_processing", bk_sawmill)
		if failed:return
		expect_delta(snap, {"plank":int(plank["yield"])}, "Claiming plank job %d" % (j+1))
		bk_count(bk_made, "plank", int(plank["yield"]))
	expect(held("plank") >= BK_PLANKS and bk_queue_ids(bk_sawmill).is_empty(), "Sawmill queue drained; %d planks held" % held("plank"))
	expect(held("copper_joint") >= BK_JOINTS, "Copper joints earned (joint %d)" % held("copper_joint"))
	# FIXTURE (disclosed, C13): one legacy mill_kit, as a pre-C13 player still carries. A plain "mill" build while
	# a kit is held is the legacy 1x1 placement and consumes exactly that kit.
	person().inventory.mill_kit = 1
	bk_stand_at(bk_stand)
	var kit_snap := bag().duplicate(true)
	bk_run("build", bk_mill, "mill")
	if failed:return
	expect_delta(kit_snap, {"mill_kit":-1}, "Build the legacy 1x1 mill from the kit at %s" % bk_mill)
	expect(bk_obj(bk_mill).get("type","") == "mill" and bk_obj(bk_mill).get("owner","") == TOKEN and world.blocked(bk_mill) and not bk_obj(bk_mill).has("mill_part"), "Kit mill at %s is owned by the builder, solid and a legacy 1x1" % bk_mill)
	var mill := bk_obj(bk_mill)
	expect(not bool(mill.get("auto_enabled", true)) and not mill.has("processing") and not mill.has("job"), "New mill starts idle with automation off")
	var recipes := World.processing_recipes("mill")
	expect(recipes.has("flour") and not recipes.has("plank") and not recipes.has("charcoal"), "Mill processes flour only")

func bk_harvest_crops() -> void:
	bk_harvest(bk_plots, "pumpkin and wheat growth")
	if failed:return
	expect(held("pumpkin") >= 1 and held("wheat") >= bk_wheat_need, "Harvested pumpkin %d and wheat %d (need %d)" % [held("pumpkin"), held("wheat"), bk_wheat_need])
	expect(person().collection.crops.has("pumpkin"), "Pumpkin recorded in the crop collection by the real harvest")

func bk_egg() -> void:
	if float(world.state.animal.egg_ready) < 0.0:
		bk_probe("egg", BK_CHICKEN, "", "Collecting an egg before feeding", "還沒有雞蛋")
		if held("feed") < 1:
			var feed: Dictionary = World.RECIPES.feed
			var snap := bag().duplicate(true)
			bk_run("cook", stove, "feed")
			if failed:return
			expect_delta(snap, negate(feed.ingredients), "Cooking feed on the donated stove")
			bk_step(float(feed.time), "cook feed")
			snap = bag().duplicate(true)
			bk_run("claim_cook", stove)
			if failed:return
			expect_delta(snap, {"feed":int(feed["yield"])}, "Claiming feed")
			bk_count(bk_made, "feed", int(feed["yield"]))
		var before := bag().duplicate(true)
		bk_run("feed", BK_CHICKEN)
		if failed:return
		expect_delta(before, {"feed":-1}, "Feeding the hen")
	bk_step(float(world.state.animal.egg_ready) - float(world.state.time), "hen lays")
	var snap2 := bag().duplicate(true)
	bk_run("egg", BK_CHICKEN)
	if failed:return
	expect_delta(snap2, {"egg":1}, "Collecting the egg")

func bk_flour() -> void:
	var flour: Dictionary = World.INDUSTRY.PROCESS.flour
	var snap := bag().duplicate(true)
	var r := bk_run("queue_processing", bk_mill, "flour")
	if failed:return
	expect_delta(snap, negate(flour.ingredients), "Queuing flour consumed wheat 2")
	expect(bool(r.get("started", false)) and bk_queue_ids(bk_mill).size() == 1, "Flour job started at once in the mill's manual queue")
	bk_probe("claim_processing", bk_mill, "", "Claiming flour before 60 s", "還要")
	bk_step(float(flour.time), "mill grinds flour")
	snap = bag().duplicate(true)
	bk_run("claim_processing", bk_mill)
	if failed:return
	expect_delta(snap, {"flour":int(flour["yield"])}, "Claiming flour")
	bk_count(bk_made, "flour", int(flour["yield"]))
	expect(bk_queue_ids(bk_mill).is_empty(), "Mill queue empty after claiming")
	expect(not person().collection.meals.has("flour"), "Flour is not recorded as a meal")

func bk_pie() -> void:
	var pie: Dictionary = World.RECIPES[BK_PIE]
	var snap := bag().duplicate(true)
	bk_run("queue_cook", stove, BK_PIE)
	if failed:return
	expect_delta(snap, negate(pie.ingredients), "Cooking pumpkin pie consumed pumpkin, flour and egg")
	var active:Dictionary=bk_obj(stove).cooking.active
	var job_id:String=active.id
	bk_probe("claim_cook", stove, "", "Claiming pumpkin pie before 120 s", "秒")
	bk_step(float(pie.time)*0.5, "pumpkin pie half baked")
	var paid_bag:=bag().duplicate(true)
	var saved_time:=float(world.state.time)
	expect(world.save(),"Graceful shutdown saves the current cooking clock")
	var reopened:=World.new()
	expect(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,"Mid-bake reload opens the primary save")
	if failed:return
	world=reopened
	world.add_player(TOKEN,str(person().name))
	expect(is_equal_approx(float(world.state.time),saved_time),"Mid-bake reload restores the saved world time")
	var restored:Dictionary=bk_obj(stove).cooking.active
	expect(restored.get("id")==job_id and is_equal_approx(float(restored.get("finish",0)),float(active.finish)),"Mid-bake reload preserves the queued pie and deadline")
	expect(same_inventory(bag(),paid_bag),"Mid-bake reload does not debit ingredients again")
	bk_step(float(pie.time)*0.5, "finish pumpkin pie after reload")
	var ready:Array=bk_obj(stove).cooking.ready
	expect(ready.size()==1 and ready[0].id==job_id,"Exactly one pie batch is ready after the original deadline")
	snap = bag().duplicate(true)
	bk_run("claim_cook", stove, job_id)
	if failed:return
	expect_delta(snap, {BK_PIE:int(pie["yield"])}, "Claiming pumpkin pie")
	bk_count(bk_made, BK_PIE, int(pie["yield"]))
	expect(held(BK_PIE) == 4, "Exactly 4 pumpkin pies held (got %d)" % held(BK_PIE))
	expect(person().collection.meals.has(BK_PIE), "Pumpkin pie recorded in the meal collection")
	expect(bk_obj(stove).cooking.active.is_empty() and bk_obj(stove).cooking.ready.is_empty() and PK.is_site_cell(world.state, stove) and world.kitchen_opened(), "Donated stove free again and still donated; kitchen open")
	bk_probe("claim_cook", stove, job_id, "Claiming the same pie batch twice", "沒有料理")

func bk_persist() -> void:
	checkpoint(BK_FINAL_STAGE)
	if failed:return
	var path := world.save_path
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	var disk_ok := parsed is Dictionary and int(parsed.get("version",0)) == World.SAVE_SCHEMA.VERSION
	if disk_ok:
		var disk_player: Dictionary = parsed.get("players",{}).get(TOKEN,{})
		var disk_mill: Dictionary = parsed.get("objects",{}).get(World.key(bk_mill),{})
		disk_ok = same_inventory(disk_player.get("inventory",{}), bag()) and int(disk_player.get("inventory",{}).get(BK_PIE,0)) == 4 and disk_mill.get("type","") == "mill" and disk_mill.get("owner","") == TOKEN
	expect(disk_ok, "Primary save on disk (schema %d) holds 4 pies, the bag and the owned mill" % World.SAVE_SCHEMA.VERSION)
	var reload := World.new()
	expect(reload.load_world(path) and not reload.recovered_from_backup, "Bakery world reloads from the primary save")
	if failed:return
	var saved: Dictionary = reload.state.players[TOKEN]
	expect(same_inventory(saved.inventory, bag()) and int(saved.coins) == int(person().coins), "Reloaded inventory and coins equal the live ones")
	print("BAKERY reload counts pumpkin_pie=%d flour=%d pumpkin=%d egg=%d plank=%d copper_joint=%d mill_kit=%d reinforced_pick=%d" % [int(saved.inventory.get(BK_PIE,0)), int(saved.inventory.get("flour",0)), int(saved.inventory.get("pumpkin",0)), int(saved.inventory.get("egg",0)), int(saved.inventory.get("plank",0)), int(saved.inventory.get("copper_joint",0)), int(saved.inventory.get("mill_kit",0)), int(saved.inventory.get("reinforced_pick",0))])
	expect(int(saved.inventory.get(BK_PIE,0)) == 4 and int(saved.inventory.get("mill_kit",0)) == 0, "Reloaded bag has 4 pies and no leftover mill_kit")
	expect(saved.collection.crops.has("pumpkin") and saved.collection.meals.has(BK_PIE), "Collection (pumpkin crop, pumpkin pie meal) persisted")
	for piece in [[bk_bench,"bench"], [bk_sawmill,"sawmill"], [bk_mill,"mill"]]:
		var obj: Dictionary = reload.state.objects.get(World.key(piece[0]), {})
		expect(obj.get("type","") == piece[1] and obj.get("owner","") == TOKEN, "%s at %s persisted with its owner" % [piece[1], piece[0]])
	expect(reload.kitchen_opened() and PK.is_site_cell(reload.state, stove), "Opened kitchen and donated stove persisted")

	# Late join of the reloaded in-process world (normal add_player, read-only, no network).
	var file_before := FileAccess.get_file_as_string(path)
	reload.add_player(BK_LATE, "Late")
	var late: Dictionary = reload.state.players[BK_LATE]
	expect(same_inventory(late.inventory, default_stock) and int(late.coins) == default_coins, "Late member starts with the normal stock (no pies, flour or kits)")
	expect(not late.collection.meals.has(BK_PIE) and not late.collection.crops.has("pumpkin"), "Late member's collection is their own (no pie/pumpkin)")
	var view := reload.region_snapshot(HOME)
	var mill_view: Dictionary = (view.objects as Dictionary).get(World.key(bk_mill), {})
	expect(mill_view.get("type","") == "mill" and reload.blocked(bk_mill), "Late member's home view shows the solid mill")
	expect(PK.stage(view) == "open", "Late member's view shows the kitchen open")
	expect(FileAccess.get_file_as_string(path) == file_before, "Late join without actions did not write the save")
	print("BAKERY late_join member=%s in_process_world=true network=not_exercised mill_visible=%s" % [BK_LATE, mill_view.get("type","") == "mill"])
	if failed:return

	var bag_before:=bag().duplicate(true)
	var coins_before:=int(person().coins)
	var price:=int(World.OTHER_SALES[BK_PIE])
	bk_run("ship",World.SHIPPING.cell_for(world.state),JSON.stringify([[[BK_PIE,1]],price]))
	if failed:return
	expect_delta(bag_before,{BK_PIE:-1},"Ship exactly one home-baked pie")
	expect(int(person().coins)==coins_before+price,"Shipping one pie pays its displayed price")
	var shipped_world:=World.new()
	expect(shipped_world.load_world(path) and not shipped_world.recovered_from_backup,"Packed pie reloads from the primary save")
	if failed:return
	var shipped:Dictionary=shipped_world.state.players[TOKEN]
	expect(same_inventory(shipped.inventory,bag()) and int(shipped.coins)==coins_before+price,"Shipped pie and payment persist")
	expect(shipped.collection.meals.has(BK_PIE),"Shipping a pie preserves its collection entry")
