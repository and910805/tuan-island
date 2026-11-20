extends "res://tests/test_festival_earned_journey.gd"
## T067 natural deep-mine journey: a FRESH temp world earns its way from the
## surface to 金瓜石合作礦場・地下第 15 層 (B15).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
## Time: the deep section advances World time only through the inherited wait()
## (World.step(dt,true) in chunks); the reused chapter_one() calls World.step
## directly. Walking (World.move_player), transit and lift rides consume NO world
## time (move_player does not advance state.time), so "world seconds" reflect only
## explicit waits (processing jobs, node cooldowns, crop growth in chapter one).
##
## Prerequisite (reused parent logic, unmodified):
##  * test_flower_journey.chapter_one(): chapter one earned on a fresh world
##    (crops, ship, donate, irrigation, stove, picnic). The picnic opens transit
##    and the mine entry; nothing else of chapters two to five is needed.
##  * test_festival_earned_journey.commission_mine(false): B1→B5 earned (own
##    bench/sawmill/kiln, practice copper vein, pump/pipe/tank kits, B3 drained by
##    a real pump, transit there and back). Its B1–B4 commissions are checked by
##    act() success and the final unlocked==5 only, NOT by an exact debit; its
##    gathering/crafting goes through the salt-ledger helpers whose ledger is empty
##    here, so those are checked by act() success and "holding >= want" only.
##  SKIPPED on purpose (not needed for the mine, keeps the suite fast): the tea
##  route, the flower and salt chapters, Lanyang, the dock and the festival.
##
## Deep section (after B5 is open) — sources, all via World.act:
##  * wood/fiber/resin/stone: axe/pick on home trees, grass and rocks;
##  * plank: own sawmill; charcoal: own charcoal kiln (start/claim processing);
##  * copper_ore: practice vein at home and strikes on B6/B8/B10/B13 (+B7 finds);
##  * stone: home rocks plus B7/B9 strikes and B6/B12 finds;
##  * crystal_sand: B5 strikes, B9/B10/B11 finds and the glass furnace; gold_ore: B5 strikes (+B11..);
##  * copper_joint, pipe_kit, tank_kit, pump_kit, conveyor_kit, gold_sample and
##    B8's 4 glass: crafted at the own bench (World.CRAFT recipes);
##  * commissions 5..14 delivered at SERVICE, then the DOWN stairs; mine_energy is
##    only restored at the real REST station;
##  * ochre_earth (B6/B7 finds: 3 strikes each on trip one = 6) and vein_quartz
##    (B9/B10 finds: 3 strikes each on trip two = 6) arrive with the strikes and
##    are part of every exact whole-bag compare;
##  * Q07: 12 copper_joint + 4 plank (HOIST_COST) are gathered/crafted/sawn at home
##    on the second trip and delivered with mine_hoist_repair at the surface entry
##    sign (exact debit) after a refused, stuck surface-hoist attempt;
##  * glass furnace 玻璃爐 (unlocked by Q07): at the start of home visit 2 (ochre
##    already held, hoist still stuck) the build is refused with
##    GLASS_FURNACE_LOCKED_MSG. On home visit 3 (after the repair) the build is
##    first refused while short of a material (exact 材料不足 message), copper
##    joints/stone are then made/gathered, and the furnace is built at an open
##    home site for exactly stone 25 + iron_ingot 6. Its
##    personal queue (queue_processing / claim_processing) then runs: 2 vein
##    quartz → 3 crystal sand (claim refused early with the remaining seconds,
##    60 world s waited, claimed); two R17 glass jobs (3 crystal sand + 1 wood
##    each, 2×120 = 240 world s waited, two claims of 1 glass); an empty claim is
##    refused. Those 2 furnace glass pay the B12 commission (bench glass made is
##    asserted unchanged on that visit). The remaining 4 vein quartz are queued
##    as two crystal-sand jobs and left pending through the B15 save; the reload
##    compares the furnace object, rides home and claims them (+3 each).
##    Explicit furnace waits: 300 world seconds in total;
##  * transit home↔金瓜石 (ferry→rail→bus→shuttle, shuttle back home), the deep
##    LIFT to the surface and the (repaired) surface hoist to landings 6, 10 and 15.
## EXACT in the deep section (whole-backpack before/after compare, nothing else
## may change): every gather hit (non-final hits change nothing; the final hit
## gives the deterministic world.gd yield: tree wood 6/fiber 2/sapling 1/resin 1,
## rock stone 5, grass fiber 4), every craft (debits World.CRAFT ingredients,
## credits its yield), every processing start (debits ingredients) and claim
## (credits yield), every practice-vein pick (copper_ore +2), every mine strike
## (catalog ore/yield + finds, energy cost, 12 s cooldown), every commission
## (exact catalog cost, unlocked+1), the furnace build and every furnace queue
## start (inputs debited) and claim (product credited; these compares ignore
## zero-count entries because the queue rewrites the bag without empty stacks).
## The provenance totals gathered/made/mined/spent are MEASURED from those bag
## deltas; furnace products are tallied separately as furnace_made.
## NOT preset: no state field is written by this file (inventory, mine_depths,
## mine_energy, region, x/y, time). No helper used here teleports or presets.
## Negative gates (exact message, whole state unchanged): hoist before any landing,
## hoist repair before B6, stuck hoist to B6 before the repair, a second repair,
## hoist to B10/B15 before they open, DOWN stairs before each commission 5..14,
## commission refused at B8 and B12 while lacking glass — produced by this test's
## fetch plan (glass is fetched on the next home trip: bench glass for B8,
## furnace glass for B12), not by scarcity — no commission on B15, no DOWN exit at
## B15 (catalog exits.down is empty; the stairs refuse the unknown id mine_16 and
## the same floor mine_15), a cooling node after the reload, and the glass furnace
## gates: build before the Q07 repair, build while short of a material, claim
## before the crystal sand is done, claim with nothing finished (before the save
## and again after the reloaded pending jobs are claimed).
## Persistence: save at B15, then an IN-PROCESS reload into a plain
## World.new().load_world() (not a process restart), then lift + hoist on it,
## then lift up, ride home and claim the furnace jobs queued before the save.
## Prints MINE_DEEP evidence lines, a MINE_DEEP_JOURNEY provenance line (with the
## movement-vs-assertion check split) and MINE_DEEP_JOURNEY_TESTS checks=N failures=M.

const Catalog=preload("res://scripts/mine_expansion_catalog.gd")
const Survey=preload("res://scripts/mine_survey.gd")
const CLOSED:="此礦道尚未開放，或你離入口太遠。"
const SHORT:="工程材料不足。"
const NO_WORK:="這一層沒有待完成的工程。"
const COOLING:="礦點正在整理。"
const MOVE_MSG:="movement followed a passable route"
const OBTAIN_ORDER:=["gold_sample","glass","pump_kit","pipe_kit","tank_kit","conveyor_kit","copper_joint","plank","charcoal","copper_ore","fiber","resin","stone","wood"]
const GATHER_YIELD:={"tree":{"wood":6,"fiber":2,"sapling":1,"resin":1},"rock":{"stone":5},"grass":{"fiber":4}}
const GATHER_TOOL:={"tree":"axe","rock":"pick","grass":"axe"}

var deep_started:=false
var deep_ms:=0
var deep_actions_start:=0
var deep_walk_start:=0
var deep_time_start:=0.0
var deep_checks_start:=0
var lift_rides:=0
var rests:=0
var vein_picks:=0
var deep_refusals:=0
var kiln_cell:=Vector2i(-1,-1)
var furnace_cell:=Vector2i(-1,-1)
var furnace_made:={}
var furnace_waited:=0.0
var pending_sand_jobs:=0
var arrived_by:=""
var mined:={}
var made:={}
var gathered:={}
var deep_spent:={}
var strikes:={}
## Check accounting: expect() calls by kind; the rest of `checks` are direct
## increments from the inherited salt bookkeeping (salt_check).
var move_checks:=0
var step_checks:=0
var act_ok_checks:=0
var other_checks:=0

func expect(condition:bool,message:String) -> bool:
	checks+=1
	if message==MOVE_MSG:move_checks+=1
	elif message.begins_with("world step ") or message.begins_with("advance ") or message.begins_with("Saw fresh"):step_checks+=1
	elif message.begins_with(tok+" ") and message.contains(" at ("):act_ok_checks+=1
	else:other_checks+=1
	if not condition:
		failures+=1
		failed=true
		push_error("MINE_DEEP_JOURNEY FAIL: "+message)
	return condition

func finish() -> void:
	var runtime:=Time.get_ticks_msec()-started_ms
	var t:=float(world.state.get("time",0.0))
	if deep_started:
		print("MINE_DEEP_JOURNEY label=\"%s\" unlocked=%d actions=%d deep_actions=%d walk_tiles=%d deep_walk_tiles=%d world_seconds=%.1f deep_world_seconds=%.1f lift_rides=%d reloads=%d rests=%d vein_picks=%d refusals=%d strikes=%s gathered=%s mined=%s made=%s spent=%s furnace_made=%s furnace_wait_s=%.1f runtime_ms=%d deep_runtime_ms=%d"%[SALT_LABEL,int(world.state.mine_depths.unlocked),actions,actions-deep_actions_start,walking,walking-deep_walk_start,t,t-deep_time_start,lift_rides,reloads,rests,vein_picks,deep_refusals,JSON.stringify(strikes),JSON.stringify(gathered),JSON.stringify(mined),JSON.stringify(made),JSON.stringify(deep_spent),JSON.stringify(furnace_made),furnace_waited,runtime,Time.get_ticks_msec()-deep_ms])
	print("MINE_DEEP_JOURNEY check_split total=%d movement_per_tile=%d world_step=%d action_ok=%d other_assertions=%d salt_bookkeeping=%d"%[checks,move_checks,step_checks,act_ok_checks,other_checks,checks-move_checks-step_checks-act_ok_checks-other_checks])
	print("MINE_DEEP_JOURNEY_TESTS checks=%d failures=%d (deep slice checks=%d)"%[checks,failures,checks-deep_checks_start])
	quit(1 if failures>0 else 0)

# ---------------------------------------------------------------- journey

func run() -> void:
	tok=TOKEN_A
	world.add_player(TOKEN_A,"Bloom A")
	names[TOKEN_A]="Bloom A"
	expect(int(world.state.mine_depths.unlocked)==1,"fresh world: mine unlocked 1")
	chapter_one()
	if failed:return
	commission_mine(false)
	if failed:return
	print("MINE_DEEP prerequisite B1-B5 earned (checks %d, actions %d, world_seconds %.1f, runtime_ms %d)"%[checks,actions,now(),Time.get_ticks_msec()-started_ms])
	deep_started=true
	deep_ms=Time.get_ticks_msec()
	deep_actions_start=actions
	deep_walk_start=walking
	deep_time_start=now()
	deep_checks_start=checks
	catalog_cross_check()
	kiln_cell=find_object("charcoal_kiln")
	if not expect(kiln_cell!=Vector2i(-1,-1) and saw_cells.has(tok) and bench_cell!=Vector2i(-1,-1),"own kiln, sawmill and bench from the earned prerequisite"):return
	trip_one()
	if failed:return
	trip_two()
	if failed:return
	trip_three()
	if failed:return
	lantern_hall()
	if failed:return
	persistence()

func catalog_cross_check() -> void:
	for d in range(5,15):
		expect_same(World.MINES.COSTS[d-1],Catalog.COMMISSIONS[d].cost,"live commission cost B%d matches catalog"%d)
	expect(World.MINES.LIFT==Catalog.LIFT and World.MINES.LIFT_LANDINGS==Catalog.LIFT_LANDINGS,"lift cell and landings match catalog")

## Home → B5 → B8 (B5, B6, B7 commissions); glass is fetched next trip → lift up.
func trip_one() -> void:
	expect(world.player_region(tok)=="home","trip 1 starts at home")
	obtain_all(costs_for([5,6,7]))
	if failed:return
	ride_to_mine_town()
	refuse_deep("mine_travel",World.MINES.ENTRY,"mine_6",CLOSED,"surface hoist to B6 refused while no landing is open (unlocked 5)")
	refuse_deep(World.HOIST_ACTION,World.MINES.ENTRY,"",World.HOIST_LOCKED_MSG,"Q07 hoist repair refused before B6 is open (unlocked 5)")
	act("mine_travel",World.MINES.ENTRY,"mine_1")
	for depth in range(1,5):
		act("mine_travel",World.MINES.DOWN,"mine_%d"%(depth+1))
	expect(world.player_region(tok)=="mine_5" and int(world.state.mine_depths.unlocked)==5,"back on B5 by the stairs")
	refuse_deep("mine_travel",World.MINES.DOWN,"mine_6",CLOSED,"B5 stairs down refused before the B5 commission")
	# Crystal sand for four glass panes comes only from B5 strikes before B9.
	var guard:=0
	while not failed and int(bag().get("crystal_sand",0))<4 and guard<12:
		strike(5,World.MINES.NODES[guard%3],"pick" if guard%2==0 else "mine_extract")
		guard+=1
	expect(int(bag().get("crystal_sand",0))>=4,"B5 strikes earned 4 crystal sand")
	deliver(5)
	for d in [6,7]:
		first_visit(d)
		if d==6:
			for i in range(6):
				if int(bag().get("iron_ore",0))>=6 or failed:break
				strike(6,World.MINES.NODES[i%3],"pick")
			expect(int(bag().get("iron_ore",0))>=6,"B6 supplied enough iron ore to build the glass furnace later")
		deliver(d)
	first_visit(8)
	if failed:return
	expect(short_of(8),"plan: B8 visited before glass is fetched (glass %d)"%int(bag().get("glass",0)))
	refuse_deep("mine_commission",World.MINES.SERVICE,"",SHORT,"B8 commission refused: test plan has not fetched glass yet")
	lift_up()
	travel(World.TRANSIT.STATIONS.jinguashi.cell,"home")

## Home (furnace refused: hoist still stuck; bench glass, Q07 repair parts etc.)
## → repair hoist → hoist B6 → stairs → B8..B11 commissions (B9/B10 strikes give
## vein quartz), B12 before glass → lift up.
func trip_two() -> void:
	furnace_refused_before_repair()
	if failed:return
	var want:=costs_for([8,9,10,11])
	for item in World.MINES.HOIST_COST:want[item]=int(want.get(item,0))+int(World.MINES.HOIST_COST[item])
	obtain_all(want)
	if failed:return
	ride_to_mine_town()
	refuse_deep("mine_travel",World.MINES.ENTRY,"mine_10",CLOSED,"surface hoist to B10 refused before B10 opens (unlocked 8)")
	refuse_deep("mine_travel",World.MINES.ENTRY,"mine_15",CLOSED,"surface hoist to B15 refused before B15 opens (unlocked 8)")
	repair_hoist()
	hoist(6)
	act("mine_travel",World.MINES.DOWN,"mine_7")
	act("mine_travel",World.MINES.DOWN,"mine_8")
	expect(world.player_region(tok)=="mine_8","stairs B6→B8")
	deliver(8)
	for d in [9,10,11]:
		first_visit(d)
		deliver(d)
	first_visit(12)
	if failed:return
	expect(short_of(12),"plan: B12 visited before its glass is fetched (glass %d)"%int(bag().get("glass",0)))
	refuse_deep("mine_commission",World.MINES.SERVICE,"",SHORT,"B12 commission refused: test plan has not fetched glass yet")
	lift_up()
	travel(World.TRANSIT.STATIONS.jinguashi.cell,"home")

## Home (glass furnace built and run: vein quartz → crystal sand → B12 glass;
## gold samples etc.) → hoist B10 → stairs → B12..B14 commissions → B15.
func trip_three() -> void:
	glass_furnace_leg()
	if failed:return
	var bench_glass:=int(made.get("glass",0))
	obtain_all(costs_for([12,13,14]))
	if failed:return
	expect(int(made.get("glass",0))==bench_glass and int(bag().get("glass",0))==int(furnace_made.get("glass",0)),"B12 glass comes from the furnace only: bench glass made stays %d, holding %d == furnace glass %d"%[bench_glass,int(bag().get("glass",0)),int(furnace_made.get("glass",0))])
	ride_to_mine_town()
	refuse_deep("mine_travel",World.MINES.ENTRY,"mine_15",CLOSED,"surface hoist to B15 refused before B15 opens (unlocked 12)")
	hoist(10)
	act("mine_travel",World.MINES.DOWN,"mine_11")
	act("mine_travel",World.MINES.DOWN,"mine_12")
	expect(world.player_region(tok)=="mine_12","stairs B10→B12")
	deliver(12)
	for d in [13,14]:
		first_visit(d)
		deliver(d)

func lantern_hall() -> void:
	expect(world.player_region(tok)=="mine_15" and int(world.state.mine_depths.unlocked)==15,"arrived on B15 with 15 floors open")
	print("MINE_DEEP arrive B15 via %s unlocked=%d energy=%d"%[arrived_by,int(world.state.mine_depths.unlocked),int(person().mine_energy)])
	refuse_deep("mine_commission",World.MINES.SERVICE,"",NO_WORK,"B15 has no commission (terminus)")
	expect(str(Catalog.DEPTHS[15].exits.down)=="" and World.MINES.IDS.size()==15 and not World.MINES.IDS.has("mine_16"),"B15 catalog has no down exit and no floor id mine_16 exists")
	refuse_deep("mine_travel",World.MINES.DOWN,"mine_16",CLOSED,"B15 DOWN stairs with the unknown floor id mine_16 refused")
	refuse_deep("mine_travel",World.MINES.DOWN,"mine_15",CLOSED,"B15 DOWN stairs to the same floor mine_15 refused")
	survey(15)
	lift_up()
	hoist(15)
	strike_all(15)
	var seen:Dictionary=Survey.own_record(world.state,tok).seen
	for d in range(6,16):expect(seen.get(str(d),false)==true,"survey page %d recorded"%d)

func persistence() -> void:
	expect(world.save(),"explicit save on B15")
	var expected:Dictionary=person().duplicate(true)
	var depths:Dictionary=world.state.mine_depths.duplicate(true)
	var record:=Survey.own_record(world.state,tok)
	var furnace:Dictionary=world.state.objects.get(World.key(furnace_cell),{}).duplicate(true)
	expect(str(furnace.get("type",""))=="glass_furnace" and furnace.get("processing") is Dictionary,"own glass furnace with its pending queue at save time")
	var cooling:=Vector2i(-1,-1)
	for node:Vector2i in World.MINES.NODES:
		if float(depths.ready.get("mine_15",{}).get(World.key(node),0.0))>now():cooling=node
	expect(cooling!=Vector2i(-1,-1),"a B15 node is cooling at save time")
	var reopened:=World.new()
	if not expect(reopened.load_world(save_path) and not reopened.recovered_from_backup,"B15 save loads in a plain in-process World"):return
	reopened.save_path=save_path
	expect(int(reopened.state.version)==int(World.SAVE_SCHEMA.VERSION),"saved version %s == SaveSchema.VERSION %d"%[str(reopened.state.version),int(World.SAVE_SCHEMA.VERSION)])
	expect(int(reopened.state.mine_depths.unlocked)==15,"reload: mine_depths.unlocked == 15")
	expect(reopened.state.mine_depths.get("hoist")==true,"reload: repaired hoist persists")
	reopened.add_player(TOKEN_A,"Bloom A")
	world=reopened
	reloads+=1
	for field in ["region","x","y","inventory","mine_energy","coins"]:
		expect_same(person().get(field),expected.get(field),"reload: player %s preserved"%field)
	expect_same(world.state.mine_depths.ready,depths.ready,"reload: node cooldowns preserved")
	expect_same(Survey.own_record(world.state,tok),record,"reload: survey pages preserved")
	expect_same(world.state.objects.get(World.key(furnace_cell),{}),furnace,"reload: glass furnace and its pending queue preserved")
	var ready_now:=float(world.state.mine_depths.ready.get("mine_15",{}).get(World.key(cooling),0.0))
	print("MINE_DEEP reload in-process World.new().load_world version=%d unlocked pre=%d post=%d region pre=%s post=%s xy pre=(%.2f,%.2f) post=(%.2f,%.2f) items pre=%d post=%d survey_pages pre=%d post=%d energy pre=%d post=%d cooling_node=%s ready=%.1f time=%.1f"%[int(world.state.version),int(depths.unlocked),int(world.state.mine_depths.unlocked),str(expected.region),str(person().region),float(expected.x),float(expected.y),float(person().x),float(person().y),(expected.inventory as Dictionary).size(),(person().inventory as Dictionary).size(),record.seen.size(),Survey.own_record(world.state,tok).seen.size(),int(expected.mine_energy),int(person().mine_energy),str(cooling),ready_now,now()])
	if cooling!=Vector2i(-1,-1):refuse_deep("pick",cooling,"",COOLING,"reloaded B15 node %s still cooling"%str(cooling))
	lift_up()
	hoist(15)
	expect(world.player_region(tok)=="mine_15","reloaded world: surface lift and hoist back to B15")
	# Reloaded world: ride home and claim the crystal sand queued before the save.
	lift_up()
	travel(World.TRANSIT.STATIONS.jinguashi.cell,"home")
	for i in pending_sand_jobs:furnace_claim("crystal_sand")
	refuse_deep("claim_processing",furnace_cell,"","目前沒有完成的加工","reloaded furnace: nothing left to claim")
	print("MINE_DEEP reload furnace claimed_pending_jobs=%d furnace_made=%s"%[pending_sand_jobs,JSON.stringify(furnace_made)])

# ---------------------------------------------------------------- floors

func first_visit(d:int) -> void:
	if failed:return
	expect(world.player_region(tok)=="mine_%d"%d,"arrived on B%d"%d)
	expect(int(world.state.mine_depths.unlocked)==d,"B%d is the deepest open floor"%d)
	print("MINE_DEEP arrive B%d via %s unlocked=%d energy=%d"%[d,arrived_by,int(world.state.mine_depths.unlocked),int(person().mine_energy)])
	refuse_deep("mine_travel",World.MINES.DOWN,"mine_%d"%(d+1),CLOSED,"B%d stairs down refused before the B%d commission"%[d,d])
	strike_all(d)
	survey(d)

func deliver(d:int) -> void:
	if failed:return
	var cost:Dictionary=Catalog.COMMISSIONS[d].cost
	expect(not short_of(d),"holding B%d commission cost %s (bag %s)"%[d,JSON.stringify(cost),JSON.stringify(pick_items(cost))])
	var before:=bag().duplicate(true)
	act("mine_commission",World.MINES.SERVICE)
	if failed:return
	var expected:=before.duplicate(true)
	var debited:={}
	for item in cost:
		expected[item]=int(before.get(item,0))-int(cost[item])
		var delta:=int(before.get(item,0))-int(bag().get(item,0))
		debited[item]=delta
		deep_spent[item]=int(deep_spent.get(item,0))+delta
	expect_same(bag(),expected,"B%d commission debits exactly %s"%[d,JSON.stringify(cost)])
	expect(int(world.state.mine_depths.unlocked)==d+1,"B%d commission opens B%d"%[d,d+1])
	print("MINE_DEEP commission B%d \"%s\" debited=%s unlocked=%d"%[d,str(Catalog.COMMISSIONS[d].title),JSON.stringify(debited),int(world.state.mine_depths.unlocked)])
	act("mine_travel",World.MINES.DOWN,"mine_%d"%(d+1))
	expect(world.player_region(tok)=="mine_%d"%(d+1),"DOWN stairs to B%d"%(d+1))
	arrived_by="stairs from B%d"%d

func short_of(d:int) -> bool:
	var cost:Dictionary=Catalog.COMMISSIONS[d].cost
	for item in cost:
		if int(bag().get(item,0))<int(cost[item]):return true
	return false

func strike_all(d:int) -> void:
	for i in World.MINES.NODES.size():
		strike(d,World.MINES.NODES[i],"mine_extract" if i==1 else "pick")

func strike(d:int,node:Vector2i,how:String) -> void:
	if failed:return
	var cost:=10 if d<=5 else roundi(10.0*float(Catalog.HAZARDS[Catalog.DEPTHS[d].hazard].energy_multiplier))
	expect(cost==World.MINES.energy_cost(d),"B%d energy cost %d matches catalog hazard"%[d,cost])
	if int(person().mine_energy)<=cost:
		act("mine_rest",World.MINES.REST)
		rests+=1
		expect(int(person().mine_energy)==100,"rest station restores mine energy")
	var ready:=float(world.state.mine_depths.ready.get("mine_%d"%d,{}).get(World.key(node),0.0))
	if ready>now():wait(ready-now()+0.1)
	var ore:String=World.MINES.ORES[4] if d<=5 else str(Catalog.DEPTHS[d].ore)
	var amount:int=World.MINES.YIELDS[d-1] if d<=5 else int(Catalog.DEPTHS[d]["yield"])
	var finds:Array=["crystal_sand"] if d==5 else Catalog.DEPTHS[d].finds
	var before:=bag().duplicate(true)
	var energy:=int(person().mine_energy)
	act(how,node)
	if failed:return
	var expected:=before.duplicate(true)
	expected[ore]=int(before.get(ore,0))+amount
	for found:String in finds:expected[found]=int(expected.get(found,0))+1
	expect_same(bag(),expected,"B%d %s at %s yields %s +%d and finds %s"%[d,how,str(node),ore,amount,str(finds)])
	measure(before,mined)
	expect(int(person().mine_energy)==energy-cost,"B%d strike spends %d energy (%d -> %d)"%[d,cost,energy,int(person().mine_energy)])
	expect(is_equal_approx(float(world.state.mine_depths.ready["mine_%d"%d][World.key(node)]),now()+World.MINES.COOLDOWN),"B%d node %s cools for %.0f s"%[d,str(node),World.MINES.COOLDOWN])
	strikes[str(d)]=int(strikes.get(str(d),0))+1

func survey(d:int) -> void:
	if failed:return
	var point:Vector2i=Survey.POINTS[d]
	var result:=act("survey_observe",point)
	if failed:return
	expect(str(result.message)=="已記下「%s」。"%str(Catalog.DEPTHS[d].survey.title),"B%d survey page recorded by walking to %s: %s"%[d,str(point),str(result.message)])
	expect(Survey.own_record(world.state,tok).seen.get(str(d),false)==true,"B%d survey key saved"%d)

# ---------------------------------------------------------------- travel

func ride_to_mine_town() -> void:
	travel(FERRY,"toucheng")
	travel(World.TRANSIT.points("toucheng").rail.cell,"ruifang")
	travel(World.TRANSIT.points("ruifang").bus.cell,"jiufen")
	travel(World.TRANSIT.points("jiufen").shuttle.cell,"jinguashi")

func lift_up() -> void:
	if failed:return
	var from:=world.player_region(tok)
	act("mine_travel",World.MINES.LIFT,"jinguashi")
	expect(world.player_region(tok)=="jinguashi","lift from %s reaches the surface"%from)
	lift_rides+=1
	print("MINE_DEEP lift ride=%d from=%s to=jinguashi landing=surface entry"%[lift_rides,from])

## Q07 「卡住的升降台」: the surface hoist refuses with the stuck message, then the
## earned copper joints and planks are delivered at the entry sign (exact debit).
func repair_hoist() -> void:
	if failed:return
	expect(not World.MINES.hoist_ready(world.state.mine_depths),"hoist is still stuck before the Q07 repair")
	refuse_deep("mine_travel",World.MINES.ENTRY,"mine_6",World.HOIST_STUCK_MSG,"surface hoist to B6 refused while the hoist is stuck (unlocked 8)")
	if failed:return
	var cost:Dictionary=World.MINES.HOIST_COST
	expect(int(bag().get("copper_joint",0))>=int(cost.copper_joint) and int(bag().get("plank",0))>=int(cost.plank),"holding earned hoist repair parts %s (bag %s)"%[JSON.stringify(cost),JSON.stringify(pick_items(cost))])
	var before:=bag().duplicate(true)
	var result:=act(World.HOIST_ACTION,World.MINES.ENTRY)
	if failed:return
	expect(str(result.message)==World.HOIST_OK_MSG,"hoist repair message: %s"%str(result.message))
	var expected:=before.duplicate(true)
	for item in cost:
		expected[item]=int(before.get(item,0))-int(cost[item])
		deep_spent[item]=int(deep_spent.get(item,0))+int(before.get(item,0))-int(bag().get(item,0))
	expect_same(bag(),expected,"hoist repair debits exactly %s"%JSON.stringify(cost))
	expect(World.MINES.hoist_ready(world.state.mine_depths),"hoist repaired (shared world progress)")
	print("MINE_DEEP hoist repaired debited=%s unlocked=%d"%[JSON.stringify(cost),int(world.state.mine_depths.unlocked)])
	refuse_deep(World.HOIST_ACTION,World.MINES.ENTRY,"",World.HOIST_DONE_MSG,"second hoist repair refused")

func hoist(d:int) -> void:
	if failed:return
	act("mine_travel",World.MINES.ENTRY,"mine_%d"%d)
	var arrival:=Vector2(World.MINES.LIFT)+Vector2(0.5,1.5)
	expect(world.player_region(tok)=="mine_%d"%d and Vector2(person().x,person().y).distance_to(arrival)<=1.5,"surface hoist lowers to B%d beside the lift (%.1f,%.1f)"%[d,float(person().x),float(person().y)])
	lift_rides+=1
	arrived_by="surface hoist"
	print("MINE_DEEP lift ride=%d from=jinguashi to=mine_%d landing=B%d unlocked=%d"%[lift_rides,d,d,int(world.state.mine_depths.unlocked)])

# ---------------------------------------------------------------- glass furnace

func furnace_cost() -> Dictionary:
	var cost:={}
	for item in World.BUILD.glass_furnace:
		if item!="name":cost[item]=int(World.BUILD.glass_furnace[item])
	return cost

## Home visit 2, before the Q07 repair: iron ore from B6 is already in the
## bag, but the blueprint is still locked behind the stuck hoist.
func furnace_refused_before_repair() -> void:
	if failed:return
	expect(world.player_region(tok)=="home","home visit 2 starts at home")
	var iron:=int(bag().get("iron_ore",0))
	expect(not World.MINES.hoist_ready(world.state.mine_depths) and iron>=6,"before Q07: hoist stuck, iron ore from B6 already held")
	var cell:=open_square_site()
	if not expect(cell!=Vector2i(-1,-1),"open home cell for a glass furnace"):return
	refuse_deep("build",cell,"glass_furnace",World.GLASS_FURNACE_LOCKED_MSG,"glass furnace refused before the Q07 hoist repair")

## Home visit 3, after the Q07 repair: refused while short of a build material,
## then built at exact cost; 2 vein quartz → 3 crystal sand (claim refused
## early, 60 s waited), two R17 glass jobs (240 s waited) for the B12
## commission, and the remaining vein quartz queued and left pending.
func glass_furnace_leg() -> void:
	if failed:return
	expect(world.player_region(tok)=="home","home visit 3 starts at home")
	var cost:=furnace_cost()
	expect_same(cost,{"stone":25,"iron_ingot":6},"glass furnace build cost")
	expect(World.MINES.hoist_ready(world.state.mine_depths),"hoist repaired: glass furnace blueprint unlocked")
	expect(int(bag().get("iron_ore",0))>=6 and int(bag().get("vein_quartz",0))>=2,"Holding raw iron from B6 and vein quartz from B9/B10")
	var short:=""
	for item in cost:
		if int(bag().get(item,0))<int(cost[item]):
			short=item
			break
	var cell:=open_square_site()
	if not expect(cell!=Vector2i(-1,-1),"open home cell for the glass furnace"):return
	stand_for_square_station(cell)
	if expect(short!="","home visit 3 arrives short of a furnace material (bag %s)"%JSON.stringify(pick_items(cost))):
		refuse_deep("build",cell,"glass_furnace","材料不足，需要%s %d"%[str(World.NAMES[short]),int(cost[short])],"glass furnace refused while short of %s (has %d)"%[short,int(bag().get(short,0))])
	smelt_furnace_iron()
	obtain("stone",int(cost.stone))
	if failed:return
	for item in cost:expect(int(bag().get(item,0))>=int(cost[item]),"holding furnace %s >= %d (has %d)"%[item,int(cost[item]),int(bag().get(item,0))])
	furnace_cell=open_square_site()
	if not expect(furnace_cell!=Vector2i(-1,-1),"open home cell for the glass furnace"):return
	var before:=bag().duplicate(true)
	stand_for_square_station(furnace_cell)
	act("build",furnace_cell,"glass_furnace")
	if failed:return
	var delta:={}
	for item in cost:
		delta[item]=-int(cost[item])
		deep_spent[item]=int(deep_spent.get(item,0))+int(cost[item])
	expect_delta(before,delta,"glass furnace build debits exactly %s"%JSON.stringify(cost))
	var furnace:Dictionary=world.state.objects.get(World.key(furnace_cell),{})
	expect(str(furnace.get("type",""))=="glass_furnace" and str(furnace.get("owner",""))==tok,"own idle glass furnace at %s"%str(furnace_cell))
	print("MINE_DEEP glass furnace built at %s debited=%s (refused first while short of %s)"%[str(furnace_cell),JSON.stringify(cost),short])
	var sand_name:=str(World.NAMES.crystal_sand)
	var glass_name:=str(World.NAMES.glass)
	furnace_queue("crystal_sand","開始加工："+sand_name)
	refuse_deep("claim_processing",furnace_cell,"","加工尚未完成，還要 %d 秒"%ceili(float(World.processing_recipes("glass_furnace").crystal_sand.time)),"furnace claim refused before the crystal sand is done")
	furnace_wait(float(World.processing_recipes("glass_furnace").crystal_sand.time))
	furnace_claim("crystal_sand")
	var glass_jobs:=int(Catalog.COMMISSIONS[12].cost.glass)
	var per_job:Dictionary=World.processing_recipes("glass_furnace").glass.ingredients
	obtain("wood",int(per_job.wood)*glass_jobs)
	if failed:return
	expect(int(bag().get("crystal_sand",0))>=int(per_job.crystal_sand)*glass_jobs,"holding crystal sand %d for %d furnace glass jobs"%[int(bag().get("crystal_sand",0)),glass_jobs])
	for i in glass_jobs:
		furnace_queue("glass","開始加工："+glass_name if i==0 else "已排入加工：%s（共 %d 份）"%[glass_name,i+1])
	furnace_wait(float(World.processing_recipes("glass_furnace").glass.time)*glass_jobs)
	for i in glass_jobs:furnace_claim("glass")
	if failed:return
	refuse_deep("claim_processing",furnace_cell,"","目前沒有完成的加工","furnace claim refused with nothing left")
	# The rest of the vein quartz is queued and left pending through the B15 save.
	var queued:=0
	while not failed and int(bag().get("vein_quartz",0))>=2:
		furnace_queue("crystal_sand","開始加工："+sand_name if queued==0 else "已排入加工：%s（共 %d 份）"%[sand_name,queued+1])
		queued+=1
	pending_sand_jobs=queued
	print("MINE_DEEP glass furnace made=%s waited=%.1f pending_crystal_sand_jobs=%d"%[JSON.stringify(furnace_made),furnace_waited,pending_sand_jobs])

func furnace_queue(kind:String,message:String) -> void:
	if failed:return
	var recipe:Dictionary=World.processing_recipes("glass_furnace")[kind]
	var before:=bag().duplicate(true)
	var result:=act("queue_processing",furnace_cell,kind)
	if failed:return
	expect(str(result.message)==message,"furnace queue %s message '%s' (got '%s')"%[kind,message,str(result.message)])
	var delta:={}
	for item in recipe.ingredients:
		delta[item]=-int(recipe.ingredients[item])
		deep_spent[item]=int(deep_spent.get(item,0))+int(recipe.ingredients[item])
	expect_delta(before,delta,"furnace queue %s debits exactly %s"%[kind,JSON.stringify(recipe.ingredients)])

func furnace_claim(kind:String) -> void:
	if failed:return
	var amount:=int(World.processing_recipes("glass_furnace")[kind]["yield"])
	var before:=bag().duplicate(true)
	var result:=act("claim_processing",furnace_cell)
	if failed:return
	expect(str(result.message)=="已領取：%s ×%d"%[str(World.NAMES[kind]),amount],"furnace claim message for %s (got '%s')"%[kind,str(result.message)])
	expect_delta(before,{kind:amount},"furnace claim credits exactly %s +%d"%[kind,amount])
	furnace_made[kind]=int(furnace_made.get(kind,0))+amount

func open_square_site() -> Vector2i:
	var origin:=Vector2i(int(person().x),int(person().y))
	for distance in range(3,14):
		for y in range(origin.y-distance,origin.y+distance+1):
			for x in range(origin.x-distance,origin.x+distance+1):
				var site:=Vector2i(x,y)
				if maxi(absi(x-origin.x),absi(y-origin.y))!=distance:continue
				var clear:=true
				for offset:Vector2i in World.INDUSTRY.SQUARE_CELLS:
					var tile:=site+offset
					var key:=World.key(tile)
					if world.water(tile) or world.protected(tile) or world.resource(tile)!="" or world.state.objects.has(key) or world.state.crops.has(key):
						clear=false
						break
				if not clear:continue
				var footprint:=Rect2i(site,Vector2i(2,2))
				if not route(site,2.5,func(tile:Vector2i):return not footprint.has_point(tile)).is_empty():return site
	return Vector2i(-1,-1)

func stand_for_square_station(site:Vector2i) -> void:
	if failed:return
	var footprint:=Rect2i(site,Vector2i(2,2))
	var current:=Vector2(person().x,person().y)
	if not footprint.has_point(Vector2i(current)) and current.distance_to(Vector2(site)+Vector2(0.5,0.5))<=2.5:return
	var path:=route(site,2.5,func(tile:Vector2i):return not footprint.has_point(tile))
	if not expect(not path.is_empty(),"Access to four-tile construction site %s"%site):return
	var last:Vector2i=path.back()
	for index in range(1,path.size()):
		var direction:=Vector2(path[index]-path[index-1])
		for tick in range(4):world.move_player(tok,direction,0.25/3.6)
		walking+=1
	expect(Vector2(person().x,person().y).distance_to(Vector2(last)+Vector2(0.5,0.5))<=0.001,
		"Reach the outside of the four-tile construction site")

func smelt_furnace_iron() -> void:
	obtain("stone",25)
	obtain("copper_ore",5)
	obtain("charcoal",3)
	if failed:return
	var smelter:=open_square_site()
	if not expect(smelter.x>=0,"Open four-cell site for the metal smelter"):return
	stand_for_square_station(smelter)
	# C11: labelled fixture, the island's stone workbench (earned path: test_stone_workbench).
	preload("res://tests/stone_station_fixture.gd").install(world,tok)
	act("build",smelter,"small_smelter")
	for batch in range(3):act("queue_processing",smelter,"iron_ingot")
	wait(180.1)
	for batch in range(3):act("claim_processing",smelter)
	expect(int(bag().get("iron_ingot",0))==6,"Smelt all six required iron ingots from the B6 ore")

func furnace_wait(seconds:float) -> void:
	wait(seconds)
	furnace_waited+=seconds

## Whole-bag compare after applying `delta`; zero entries are ignored on both
## sides (the processing queue rewrites the bag without empty stacks).
func expect_delta(before:Dictionary,delta:Dictionary,label:String) -> void:
	var expected:={}
	for item in before:expected[str(item)]=int(before[item])
	for item in delta:expected[str(item)]=int(expected.get(str(item),0))+int(delta[item])
	expect_same(nonzero(bag()),nonzero(expected),label)

func nonzero(inv:Dictionary) -> Dictionary:
	var out:={}
	for item in inv:
		if int(inv[item])!=0:out[str(item)]=int(inv[item])
	return out

# ---------------------------------------------------------------- production at home

func costs_for(depths:Array) -> Dictionary:
	var want:={}
	for d in depths:
		var cost:Dictionary=Catalog.COMMISSIONS[d].cost
		for item in cost:want[item]=int(want.get(item,0))+int(cost[item])
	return want

## Top up holdings to `want`. Kits first, then intermediates, then raw materials,
## so a later step never consumes something an earlier step topped up.
func obtain_all(want:Dictionary) -> void:
	expect(world.player_region(tok)=="home","materials are prepared at home")
	var order:Array=OBTAIN_ORDER.duplicate()
	for item in want:
		if item not in order:order.append(item)
	for item in order:
		if want.has(item):obtain(item,int(want[item]))
		if failed:return
	for item in want:
		expect(int(bag().get(item,0))>=int(want[item]),"holding %s >= %d (has %d)"%[item,int(want[item]),int(bag().get(item,0))])

func obtain(item:String,count:int) -> void:
	var guard:=0
	while not failed and int(bag().get(item,0))<count:
		guard+=1
		if not expect(guard<=200,"obtain %s x%d makes progress"%[item,count]):return
		if item in ["wood","fiber","resin","stone"]:
			gather_one(item)
		elif item=="copper_ore":
			vein_copper()
		elif item in ["crystal_sand","gold_ore"]:
			expect(false,"%s must come from mine strikes before this home visit (have %d, need %d)"%[item,int(bag().get(item,0)),count])
			return
		elif item in ["plank","charcoal"]:
			# Own sawmill / charcoal kiln. Glass reaching this branch-chain comes
			# from the bench (B8); B12's glass is made beforehand in the glass
			# furnace (glass_furnace_leg), so obtain_all finds it already held.
			process(item)
		elif World.CRAFT.has(item):
			var recipe:Dictionary=World.CRAFT[item]
			for ingredient in recipe.ingredients:obtain(ingredient,int(recipe.ingredients[ingredient]))
			if failed:return
			deep_craft(item)
		else:
			expect(false,"BLOCKER: no earned source known for "+item)
			return

## Fell one tree / break one rock / cut one grass tuft with exact whole-bag deltas.
func gather_one(item:String) -> void:
	var kind:="rock" if item=="stone" else "tree"
	if item=="fiber" and find_resource("grass")!=Vector2i(-1,-1):kind="grass"
	var target:=find_resource(kind)
	if not expect(target!=Vector2i(-1,-1),"reachable %s for %s"%[kind,item]):return
	for hit in 4:
		if failed or world.resource(target)!=kind:return
		var before:=bag().duplicate(true)
		act(str(GATHER_TOOL[kind]),target)
		if failed:return
		var expected:=before.duplicate(true)
		var final:=world.resource(target)!=kind
		if final:
			for got in GATHER_YIELD[kind]:expected[got]=int(expected.get(got,0))+int(GATHER_YIELD[kind][got])
		expect_same(bag(),expected,"%s hit %d on %s at %s: %s"%[kind,hit+1,item,str(target),"final yield "+JSON.stringify(GATHER_YIELD[kind]) if final else "no items yet"])
		measure(before,gathered)
	expect(false,"%s at %s did not finish within 4 hits"%[kind,str(target)])

func deep_craft(recipe_id:String) -> void:
	var recipe:Dictionary=World.CRAFT[recipe_id]
	var before:=bag().duplicate(true)
	act("craft",bench_cell,recipe_id)
	if failed:return
	var expected:=before.duplicate(true)
	for item in recipe.ingredients:expected[item]=int(expected.get(item,0))-int(recipe.ingredients[item])
	expected[recipe_id]=int(expected.get(recipe_id,0))+int(recipe.yield)
	expect_same(bag(),expected,"craft %s debits %s and credits %d"%[recipe_id,JSON.stringify(recipe.ingredients),int(recipe.yield)])
	made[recipe_id]=int(made.get(recipe_id,0))+int(bag().get(recipe_id,0))-int(before.get(recipe_id,0))

func process(product:String) -> void:
	var recipe:Dictionary=World.INDUSTRY.PROCESS[product]
	var cell:Vector2i=saw_cells[tok] if product=="plank" else kiln_cell
	for ingredient in recipe.ingredients:obtain(ingredient,int(recipe.ingredients[ingredient]))
	if failed:return
	var before:=bag().duplicate(true)
	act("start_processing",cell,product)
	if failed:return
	var expected:=before.duplicate(true)
	for item in recipe.ingredients:expected[item]=int(expected.get(item,0))-int(recipe.ingredients[item])
	expect_same(bag(),expected,"%s job start debits %s"%[product,JSON.stringify(recipe.ingredients)])
	wait(float(recipe.time))
	before=bag().duplicate(true)
	act("claim_processing",cell)
	if failed:return
	expected=before.duplicate(true)
	expected[product]=int(expected.get(product,0))+int(recipe.yield)
	expect_same(bag(),expected,"%s job claim credits %d"%[product,int(recipe.yield)])
	made[product]=int(made.get(product,0))+int(bag().get(product,0))-int(before.get(product,0))

func vein_copper() -> void:
	var ready:=float(world.state.copper.ready)-now()
	if ready>0.0:wait(ready)
	var before:=bag().duplicate(true)
	act("pick",World.COPPER_CELL)
	if failed:return
	var expected:=before.duplicate(true)
	expected["copper_ore"]=int(before.get("copper_ore",0))+2
	expect_same(bag(),expected,"practice vein gives exactly 2 copper ore")
	measure(before,mined)
	vein_picks+=1

func find_object(kind:String) -> Vector2i:
	for k in world.state.objects:
		var obj:Variant=world.state.objects[k]
		if obj is Dictionary and str(obj.get("type",""))==kind:return World.cell(k)
	return Vector2i(-1,-1)

# ---------------------------------------------------------------- helpers

## Add positive bag deltas since `before` into `tally`.
func measure(before:Dictionary,tally:Dictionary) -> void:
	for item in bag():
		var delta:=int(bag().get(item,0))-int(before.get(item,0))
		if delta>0:tally[item]=int(tally.get(item,0))+delta

## Same contract as the inherited refuse() (exact message, whole state unchanged)
## with a descriptive label.
func refuse_deep(action:String,target:Vector2i,extra:String,message:String,label:String) -> void:
	if failed:return
	walk_to(target)
	if failed:return
	actions+=1
	var before:=world.state.duplicate(true)
	var result:=world.act(tok,"flower-journey-%d"%actions,action,target,extra)
	expect(not result.ok and str(result.message)==message,"%s: '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	expect(world.state==before,label+": state unchanged")
	deep_refusals+=1

func pick_items(cost:Dictionary) -> Dictionary:
	var out:={}
	for item in cost:out[item]=int(bag().get(item,0))
	return out
