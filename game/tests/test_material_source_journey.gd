extends "res://tests/test_chapter_journey.gd"
## T036 material-source EARNED journey (docs/material-source-contract.json).
## LABEL: scripted World-API journey, NOT human play. One fresh player with the
## normal starting supplies only. Every change goes through World.act (real
## reach/collision/costs) or World.move_player along BFS routes inherited from
## test_chapter_journey.gd; world time only moves through World.step (SIMULATED
## seconds, not wall clock). No inventory/flag/object/position writes, no gifts,
## no teleport. Sourced wires are built exactly like the client: MaterialSupply
## .plan over the live backpack + chosen chest, MaterialSources.digest/encode.
## Layout (C = shared chest):   . B .      B bench, S sawmill, K charcoal kiln
##                              S C K      P stand cell (reaches all four)
##                              . P .
const Sources := preload("res://scripts/material_sources.gd")
const Supply := preload("res://scripts/material_supply.gd")
const LABEL := "material-source-journey/scripted-world-api-not-human-play"
const NONE := Vector2i(-1,-1)
const UP := Vector2i(0,-1)
const LEFT := Vector2i(-1,0)
const RIGHT := Vector2i(1,0)
const DOWN := Vector2i(0,1)
const KEEP := 2 # backpack units deliberately kept so the chest covers a real shortfall
const MAX_SOURCES := 40
const MAX_DEPOSITS := 120
const MAX_STEPS := 120
const SITE_RING := 16
const LAYERS := ["objects","ground","roofs","crops","forest"]
var chest := NONE
var bench := NONE
var sawmill := NONE
var kiln := NONE
var stand := NONE
var box := ""
var last_extra := ""
var trees := 0
var rocks := 0
var hits := 0
var deposits := 0
var steps := 0
var sim_seconds := 0.0

func _initialize() -> void:
	var base := OS.get_environment("TEMP")
	if base.is_empty():base = OS.get_user_data_dir()
	var path := base.path_join("material-source-journey-%s.json" % Crypto.new().generate_random_bytes(8).hex_encode())
	# Never adopt or later delete a save this run did not create.
	if FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"):
		expect(false, "Journey save path already exists: " + path)
		finish("")
		return
	world.save_path = path
	world.add_player(TOKEN, "Island")
	print("MATERIAL_SOURCE_JOURNEY label=%s scripted_world_api=true human_play=false" % LABEL)
	premise()
	for stage in ["choose_site","gather_all","bench_and_chest","craft_kits","build_stations","process_and_cancel","reload_mid","simulate_and_claim","reload_final"]:
		if failed:break
		call(stage)
	print("MATERIAL_SOURCE_JOURNEY label=%s actions=%d walk_tiles=%d gather_hits=%d trees=%d rocks=%d deposits=%d world_steps=%d simulated_world_seconds=%.1f(World.step,not_wall_clock) site=%s box_id=%s inventory=%s passed=%s" % [LABEL, actions, walking, hits, trees, rocks, deposits, steps, sim_seconds, chest, box, JSON.stringify(bag()), not failed])
	finish(path)

func finish(path: String) -> void:
	if not path.is_empty():
		for file in [path, path+".bak", path+".tmp"]:
			if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("MATERIAL_SOURCE_JOURNEY_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failed))

# ------------------------------------------------------------------ helpers --

func held(item: String) -> int:return int(bag().get(item,0))
func obj(c: Vector2i) -> Dictionary:return world.state.objects.get(World.key(c),{})
func box_items() -> Dictionary:return obj(chest).get("items",{})
func in_box(item: String) -> int:return int(box_items().get(item,0))
func here_cell() -> Vector2i:return Vector2i(floori(person().x), floori(person().y))
func proc(kind: String) -> Dictionary:return World.INDUSTRY.PROCESS[kind]
func queue(c: Vector2i) -> Dictionary:
	var q = obj(c).get("processing")
	return q if q is Dictionary else {}
func ids(q: Dictionary) -> Array:
	var out := []
	if q.is_empty():return out
	if not (q.active as Dictionary).is_empty():out.append(str(q.active.id))
	for list in [q.waiting, q.ready]:
		for entry in list:out.append(str(entry.id))
	return out
func same(a: Dictionary, b: Dictionary) -> bool:
	for k in a.keys()+b.keys():
		if int(a.get(k,0)) != int(b.get(k,0)):return false
	return true

## One real World.act submission; walks a BFS route first only when out of reach.
func doact(action: String, target: Vector2i, extra: String = "", rid: String = "") -> Dictionary:
	if failed:return {"ok":false, "skipped":true, "message":"skipped after earlier failure"}
	if Vector2(person().x,person().y).distance_to(Vector2(target)+Vector2(0.5,0.5)) > 3.0:walk_to(target)
	if failed:return {"ok":false, "skipped":true, "message":"walk failed"}
	actions += 1
	if rid.is_empty():rid = "msj-%d" % actions
	var r: Dictionary = world.act(TOKEN, rid, action, target, extra)
	print("MSJ %d %s %s %s | ok=%s %s | wood=%d stone=%d" % [actions, action, target, extra.left(24), r.get("ok"), r.get("message",""), held("wood"), held("stone")])
	return r

func must(action: String, target: Vector2i, extra: String, label: String, rid: String = "") -> Dictionary:
	var r := doact(action, target, extra, rid)
	if not r.get("skipped",false):expect(r.get("ok") == true, label + ": " + str(r.get("message","")))
	return r

## Walk onto `tile` (route to a cardinal neighbour, then one real step).
func stand_at(tile: Vector2i) -> void:
	if failed or here_cell() == tile:return
	walk_to(tile, 1.0)
	if failed:return
	var d := Vector2(tile - here_cell())
	if not is_equal_approx(d.length(), 1.0):
		expect(false, "No cardinal approach onto %s" % tile)
		return
	for i in 4:world.move_player(TOKEN, d, 0.25/3.6)
	walking += 1
	expect(here_cell() == tile, "Walked onto stand cell %s" % tile)

func recipe_def(action: String, recipe: String) -> Dictionary:
	return World.CRAFT.get(recipe,{}) if action == "craft" else World.INDUSTRY.PROCESS.get(recipe,{})

## Client-equivalent quote: MaterialSupply split + MaterialSources digest/encode.
func quote(action: String, station: Vector2i, recipe: String) -> Dictionary:
	var def := recipe_def(action, recipe)
	var plan: Dictionary = Supply.plan(def.get("ingredients",{}), bag(), box_items())
	var alloc := {"from_backpack":plan.get("from_backpack",{}), "from_chest":plan.get("from_chest",{})}
	var d: String = Sources.digest(action, str(obj(station).get("type","")), World.key(station), recipe, def, World.key(chest), box, alloc)
	return {"plan":plan, "extra":Sources.encode(recipe, World.key(chest), box, d)}

func sourced(action: String, station: Vector2i, recipe: String, bp: Dictionary, ch: Dictionary, label: String, rid: String = "") -> Dictionary:
	var q := quote(action, station, recipe)
	var plan: Dictionary = q.plan
	expect(plan.get("ok") == true and plan.get("from_backpack") == bp and plan.get("from_chest") == ch, label + ": quoted split %s / %s" % [plan.get("from_backpack"), plan.get("from_chest")])
	var bag0: Dictionary = bag().duplicate()
	var box0: Dictionary = box_items().duplicate()
	last_extra = q.extra
	var r := must(action, station, q.extra, label, rid)
	if failed:return r
	expect(r.get("source_cell") == World.key(chest) and r.get("source_id") == box and r.get("from_backpack") == bp and r.get("from_chest") == ch, label + ": server reports the confirmed box and split")
	var exact := true
	for item in recipe_def(action, recipe).ingredients:
		if int(bag0.get(item,0)) - held(item) != int(bp.get(item,0)) or int(box0.get(item,0)) - in_box(item) != int(ch.get(item,0)):exact = false
	expect(exact, label + ": backpack and chest each debited exactly their share")
	return r

func deposit_down_to(item: String, keep: int) -> void:
	var total := held(item) + in_box(item)
	var n := 0
	while held(item) > keep and not failed:
		n += 1
		if n > MAX_DEPOSITS:
			expect(false, "Depositing %s exceeded %d actions" % [item, MAX_DEPOSITS])
			return
		must("deposit", chest, item, "deposit earned %s" % item)
		deposits += 1
	expect(held(item) == keep and in_box(item) == total - keep, "Normal deposits moved earned %s into the chest, backpack keeps %d" % [item, keep])

# ------------------------------------------------------------------- stages --

func premise() -> void:
	var inv := bag()
	expect(held("wood") == 12 and held("stone") == 4 and held("fiber") == 10 and int(person().coins) == 120, "Fresh player holds only the normal starting supplies")
	expect(held("sawmill_kit") + held("kiln_kit") + held("plank") + held("charcoal") == 0 and world.state.objects.is_empty() and world.state.players.size() == 1, "No kits, products, objects or other players at start")
	expect(World.BUILD.bench.wood == 20 and World.BUILD.bench.stone == 5 and World.BUILD.chest.wood == 20, "Premise: bench 20 wood + 5 stone, chest 20 wood")
	expect(World.CRAFT.sawmill_kit.ingredients == {"wood":8,"stone":4} and World.CRAFT.kiln_kit.ingredients == {"stone":8,"wood":4}, "Premise: sawmill_kit 8w+4s, kiln_kit 4w+8s")
	expect(proc("plank").ingredients == {"wood":4} and proc("charcoal").ingredients == {"wood":4} and proc("plank").station == "sawmill" and proc("charcoal").station == "charcoal_kiln", "Premise: plank/charcoal cost 4 wood at their stations")
	expect(World.BUILD.sawmill == {"name":World.BUILD.sawmill.name,"sawmill_kit":1} and World.BUILD.charcoal_kiln.get("kiln_kit") == 1, "Premise: stations are built from one kit")
	print("MATERIAL_SOURCE_JOURNEY start inventory=%s" % JSON.stringify(inv))

func site_ok(c: Vector2i) -> bool:
	# C08: the workbench is now 2x1, so the cell right of it (UP+RIGHT) must be clear too.
	for off in [UP, UP+RIGHT, LEFT, Vector2i.ZERO, RIGHT, DOWN, DOWN+LEFT, DOWN+RIGHT]:
		var t: Vector2i = c + off
		if not world.is_land(t) or world.water(t) or world.protected(t) or world.blocked(t) or world.resource(t) != "":return false
		for layer in LAYERS:
			if world.state[layer].has(World.key(t)):return false
	return not route(c + DOWN, 1.0).is_empty()

func choose_site() -> void:
	var o := here_cell()
	for d in range(SITE_RING + 1):
		for y in range(o.y-d, o.y+d+1):
			for x in range(o.x-d, o.x+d+1):
				if maxi(absi(x-o.x), absi(y-o.y)) != d or not site_ok(Vector2i(x,y)):continue
				chest = Vector2i(x,y)
				bench = chest + UP
				sawmill = chest + LEFT
				kiln = chest + RIGHT
				stand = chest + DOWN
				print("MATERIAL_SOURCE_JOURNEY site chest=%s bench=%s sawmill=%s kiln=%s stand=%s" % [chest, bench, sawmill, kiln, stand])
				return
	expect(false, "No legal, clear, reachable station site near spawn")

func gather(item: String, minimum: int, kind: String) -> void:
	var rounds := 0
	while held(item) < minimum and not failed:
		rounds += 1
		if rounds > MAX_SOURCES:
			expect(false, "Gathering %s exceeded %d sources" % [item, MAX_SOURCES])
			return
		var t := find_resource(kind)
		if t == NONE:
			expect(false, "No reachable natural %s" % kind)
			return
		var n := 3 if kind == "tree" else 2
		for i in n:must("axe" if kind == "tree" else "pick", t, "", "gather %s at %s" % [kind, t])
		if not failed:collect_gathered(t)
		hits += n
		if kind == "tree":trees += 1
		else:rocks += 1
		expect(world.resource(t) == "", "Natural %s at %s fully gathered" % [kind, t])

func gather_all() -> void:
	gather("stone", int(World.BUILD.bench.stone) + 4 + 8, "rock")
	gather("wood", int(World.BUILD.bench.wood) + int(World.BUILD.chest.wood) + 8 + 4 + 3*4 + 4, "tree")
	print("MATERIAL_SOURCE_JOURNEY gathered trees=%d rocks=%d hits=%d inventory=%s" % [trees, rocks, hits, JSON.stringify(bag())])

func bench_and_chest() -> void:
	stand_at(stand)
	must("build", bench, "bench", "build workbench with earned materials")
	must("build", chest, "chest", "build shared chest beside the bench")
	if failed:return
	expect(obj(bench).get("type") == "bench" and obj(chest).get("type") == "chest" and obj(chest).get("owner") == TOKEN and not obj(chest).has("box_id"), "Bench and shared chest built; new chest has no box_id yet (lazy)")
	expect(Sources.candidates(world.state.objects, TOKEN, bench) == [{"cell":World.key(chest),"type":"chest","id":""}], "Bench sees exactly the one adjacent chest, unprepared")
	deposit_down_to("stone", KEEP)
	var r := must("prepare_material_box", bench, World.key(chest), "explicit prepare at the bench")
	box = str(obj(chest).get("box_id",""))
	expect(World._is_lower_hex(box, 32) and r.get("source_cell") == World.key(chest) and r.get("source_id") == box, "prepare assigned and returned a lowercase 32-hex box_id")

func craft_kits() -> void:
	var bag0: Dictionary = bag().duplicate()
	var box0: Dictionary = box_items().duplicate()
	var plain := doact("craft", bench, "sawmill_kit")
	expect(plain.get("ok") == false and same(bag(), bag0) and same(box_items(), box0), "Plain recipe ID stays backpack-only: short backpack refused, chest untouched")
	var r := sourced("craft", bench, "sawmill_kit", {"wood":8,"stone":KEEP}, {"stone":4-KEEP}, "sourced sawmill_kit (mixed split)", "msj-kit-sawmill")
	var after_bag: Dictionary = bag().duplicate()
	var replay := doact("craft", bench, last_extra, "msj-kit-sawmill")
	expect(replay == r and same(bag(), after_bag) and held("sawmill_kit") == 1, "Same request replays its receipt; debited and crafted once")
	sourced("craft", bench, "kiln_kit", {"wood":4}, {"stone":8}, "sourced kiln_kit (stone from chest)")
	expect(held("sawmill_kit") == 1 and held("kiln_kit") == 1 and held("stone") == 0, "Both kits crafted from earned materials")

func build_stations() -> void:
	must("build", sawmill, "sawmill", "build sawmill from earned kit")
	must("build", kiln, "charcoal_kiln", "build charcoal kiln from earned kit")
	if failed:return
	expect(held("sawmill_kit") == 0 and held("kiln_kit") == 0 and obj(sawmill).get("owner") == TOKEN and obj(kiln).get("type") == "charcoal_kiln", "Kits consumed, stations owned by the builder")
	for st in [sawmill, kiln]:
		expect(Sources.candidates(world.state.objects, TOKEN, st) == [{"cell":World.key(chest),"type":"chest","id":box}], "Station %s sees the shared chest with its id" % st)
		var r := must("prepare_material_box", st, World.key(chest), "explicit prepare at station %s" % st)
		expect(r.get("source_id") == box and obj(chest).get("box_id") == box, "prepare at %s is idempotent (same box_id)" % st)
	deposit_down_to("wood", KEEP)

func process_and_cancel() -> void:
	sourced("start_processing", sawmill, "plank", {"wood":KEEP}, {"wood":4-KEEP}, "start plank (backpack + chest shortfall)")
	for i in 2:sourced("queue_processing", sawmill, "plank", {}, {"wood":4}, "queue plank %d from chest" % (i+2))
	sourced("queue_processing", kiln, "charcoal", {}, {"wood":4}, "queue charcoal from chest")
	if failed:return
	var q := queue(sawmill)
	expect(q.active.get("kind") == "plank" and q.waiting.size() == 2 and q.ready.is_empty() and queue(kiln).active.get("kind") == "charcoal", "Sawmill: 1 active + 2 waiting plank; kiln: 1 active charcoal")
	var job := str(q.waiting.back().id)
	var w0 := held("wood")
	var c0 := in_box("wood")
	var rc := must("cancel_processing_job", sawmill, job, "cancel last pending plank", "msj-cancel")
	expect(rc.get("refunded") == {"wood":4} and held("wood") == w0 + 4 and in_box("wood") == c0, "Full stored cost refunded to backpack, chest unchanged")
	expect(not ids(queue(sawmill)).has(job) and ids(queue(sawmill)).size() == 2, "Cancelled job removed, two plank jobs remain")
	expect(doact("cancel_processing_job", sawmill, job, "msj-cancel") == rc and held("wood") == w0 + 4, "Replayed cancel returns receipt; refunded once")
	var again := doact("cancel_processing_job", sawmill, job)
	expect(again.get("ok") == false and held("wood") == w0 + 4, "Fresh cancel of the same job refused; no double refund")

func reload_mid() -> void:
	var bag0: Dictionary = bag().duplicate()
	var box0: Dictionary = box_items().duplicate()
	var saw: Dictionary = queue(sawmill).duplicate(true)
	var kq := ids(queue(kiln))
	var reload := World.new()
	expect(reload.load_world(world.save_path) and not reload.recovered_from_backup, "Mid-journey world reloads from the primary save")
	if failed:return
	reload.add_player(TOKEN, "Island")
	world = reload
	expect(same(bag(), bag0) and same(box_items(), box0) and obj(chest).get("box_id") == box, "Reload: backpack, chest stock and box_id persisted")
	var q := queue(sawmill)
	expect(ids(q) == ids(saw) and ids(queue(kiln)) == kq and is_equal_approx(float(q.active.finish), float(saw.active.finish)) and str(q.active.owner) == TOKEN, "Reload: queue ids, order, finish time and owner persisted")

func done() -> bool:
	var s := queue(sawmill)
	var k := queue(kiln)
	if s.is_empty() or k.is_empty():return false
	return (s.active as Dictionary).is_empty() and s.waiting.is_empty() and s.ready.size() == 2 and (k.active as Dictionary).is_empty() and k.ready.size() == 1

func simulate_and_claim() -> void:
	var saved := true
	while not done() and steps < MAX_STEPS:
		if not world.step(1.0, true):saved = false
		steps += 1
		sim_seconds += 1.0
	var want := maxf(2.0*float(proc("plank").time), float(proc("charcoal").time))
	expect(saved and done() and is_equal_approx(sim_seconds, want), "SIMULATED %.1f s via World.step completes every job (expected %.1f)" % [sim_seconds, want])
	for i in 2:must("claim_processing", sawmill, "", "claim plank %d" % (i+1))
	must("claim_processing", kiln, "", "claim charcoal")
	expect(held("plank") == 2*int(proc("plank").yield) and held("charcoal") == int(proc("charcoal").yield), "Claimed outputs landed in the backpack")
	expect(doact("claim_processing", sawmill).get("ok") == false and ids(queue(sawmill)).is_empty() and ids(queue(kiln)).is_empty(), "Nothing left to claim; both queues empty")

func reload_final() -> void:
	var bag0: Dictionary = bag().duplicate()
	var box0: Dictionary = box_items().duplicate()
	var reload := World.new()
	expect(reload.load_world(world.save_path) and not reload.recovered_from_backup, "Final world reloads from the primary save")
	if failed:return
	reload.add_player(TOKEN, "Island")
	world = reload
	expect(same(bag(), bag0) and same(box_items(), box0) and obj(chest).get("box_id") == box and ids(queue(sawmill)).is_empty() and ids(queue(kiln)).is_empty(), "Final reload: inventory, chest, box_id and empty queues persisted")
	# Conservation ledger: everything held or stored was either starting supply or gathered.
	var spent_wood := int(World.BUILD.bench.wood) + int(World.BUILD.chest.wood) + 8 + 4 + 2*4 + 4
	var spent_stone := int(World.BUILD.bench.stone) + 4 + 8
	expect(12 + 6*trees == held("wood") + in_box("wood") + spent_wood, "Wood ledger: start + %d trees = held + chest + spent" % trees)
	expect(4 + 5*rocks == held("stone") + in_box("stone") + spent_stone, "Stone ledger: start + %d rocks = held + chest + spent" % rocks)
	expect(10 + 2*trees == held("fiber"), "Fiber ledger: only starting supply plus gathering")
