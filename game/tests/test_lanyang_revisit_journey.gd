extends "res://tests/test_history_journey.gd"
## Chapter 40「蘭陽回訪・旱日分流」+ home 分流閘 natural journey: a FRESH temp world,
## ONE player, ONE process (reloads are in-process World.new().load_world on the
## same save file; after each reload the journey continues in the reloaded World).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
##
## Prerequisite reuse (disclosed): this file EXTENDS the unmodified
## test_history_journey.gd (-> garden -> regions -> chapter journeys). The parent
## run walks chapter one, the Lanyang canal repair (three blockages cleared, sawmill
## planks donated) and the personal first 分水 memory (three observations, three
## rounds) and sets the bridge plaque, all through World.act with its own checks.
## This file hooks checkpoint() (fresh world / before repair / repaired-no-plaque /
## memory-done-no-plaque refusals) and mill_batch() (gate-kit craft refused at the
## real bench), then continues after the parent's plaque.
##
## Everything goes through World.act after World.move_player along BFS routes, and
## World.step(dt,true) for waits. NO direct writes by this file to inventory, coins,
## flags, revisit / history / lanyang fields, objects, crops, positions or time.
## Read-only helpers used for assertions: LanyangRevisit.* views, Industry.zone_report
## and Industry.components (order check), World.resource/route lookups.
## Exceptions / shortcuts (disclosed):
##  * WALKING IS FREE: World.move_player moves the avatar but never advances
##    state.time; transit (travel) also costs no world time. The printed
##    walk_seconds_equiv = walk_tiles / 3.6 is NOT added to the clock.
##  * Waits use World.step in chunks (8 s around network events, 60 s for long
##    waits); the server steps with its frame delta, so pump/sprinkler cadence here
##    is per step (plan() runs once per step when due).
##  * Single player: NOT_READY (a second islander without their own memory) and
##    other islanders' claims are not walkable here (fixture rule tests cover them).
##
## Journey:
##  1. fresh world: revisit_gate/check/claim refused (WRONG_REGION at home), craft
##     diversion_gate_kit refused (GATE_LOCKED) on a fresh world and again at the real
##     bench; in Lanyang LOCKED before the repair, after the repair (no plaque) and
##     after the personal memory (no plaque). Every refusal: whole state unchanged.
##  2. parent: repair + memory + plaque.
##  3. revisit: rainy-day refusal + wait to a dry day only if today rains; season and
##     demand; NO_GATES_TODAY, WRONG_FIELD_CELL, TOO_FAR, BAD_GATE; wrong gate ->
##     WRONG_SHARE (份) and OTHER_WRONG refusals; SAME_GATE; right gates; three field
##     checks (ALREADY_CHECKED on a repeat) -> completed; ALREADY_DONE; claim once
##     (+1 kit, whole-bag diff), CLAIMED; save -> reload -> canonical whole-state equal.
##  4. pick up the Lanyang irrigation set, travel home, earn copper (borrowed pick,
##     practice vein), wood/stone, planks (sawmill), charcoal (kiln), craft joints,
##     a sprinkler kit, a pump kit and one diversion_gate_kit; build pump/tank/pipes,
##     far sprinkler S2 (built first), gate, near sprinkler S1.
##  5. low mode while the new tank fills from 0: S1 is filled before S2 gets water;
##     closed: S2 never refilled, its stored water used by 3 far crops day by day
##     (rain days consume nothing), then on a dry day with S2 empty freshly planted
##     far crops stay dry with growth 0 while near crops grow; reopen -> S2 refilled,
##     far crops watered and growing. Final mode low.
##  6. 分水木牌: ship / market stall / 小栗 refuse it; build, move, pick up, build again.
##  7. final save -> reload -> canonical equal; gate mode persists; in Lanyang the
##     claim is refused (CLAIMED) and the gate is ALREADY_DONE.
## Prints REVISIT_JOURNEY lines; the last checks=N failures=M line is the parent's.

const LR=preload("res://scripts/lanyang_revisit.gd")
const IND=preload("res://scripts/industry.gd")
const HM=preload("res://scripts/history_memory.gd")
const WEATHER=preload("res://scripts/weather.gd")
const MKT=preload("res://scripts/market_stall.gd")
const DOC_GATES:={"spring":[3,2],"summer":[2,1],"autumn":[1,3],"winter":[1,2]}
const BENCH:=GARDEN_JOURNEY_BENCH
const MILL:=Vector2i(40,36)
const SHOP:=Vector2i(43,29)
const KILN_CANDIDATES:=[Vector2i(41,37),Vector2i(42,37),Vector2i(43,37),Vector2i(43,36)]
const PLAQUE_CANDIDATES:=[Vector2i(35,34),Vector2i(36,34),Vector2i(34,34),Vector2i(34,36),Vector2i(36,36),Vector2i(35,37),Vector2i(34,37),Vector2i(36,37)]
const PUMP:=Vector2i(53,20)
const TANK:=Vector2i(52,20)
const PIPE_A:=Vector2i(52,21)
const S1:=Vector2i(52,22)
const GATE:=Vector2i(52,23)
const PIPE_B:=Vector2i(52,24)
const S2:=Vector2i(52,25)
const NEAR:=[Vector2i(51,22),Vector2i(53,22)]
const FAR:=[Vector2i(51,25),Vector2i(53,25),Vector2i(52,26)]

var rejections:=[]
var rejections_changed:=0
var rev_started:=false
var seg_actions:=0
var seg_walk:=0
var seg_time:=0.0
var wall_start:=0
var waited:=0.0
var mill_hooked:=false
var reloads:=0
var day_log:=[]
var low_log:=[]
var growth_log:=[]
var revisit_info:={}

# ---------------------------------------------------------------- hooks

func checkpoint(stage:String) -> void:
	super.checkpoint(stage)
	if failed:return
	match stage:
		"grow":fresh_refusals()
		"newbefore":locked_refusals("in Lanyang before the canal repair")
		"repaired":locked_refusals("canal repaired, no plaque yet")
		"memory-complete":locked_refusals("own memory complete, no plaque yet")

func mill_batch(mill:Vector2i) -> void:
	super.mill_batch(mill)
	if failed or mill_hooked:return
	mill_hooked=true
	deny("craft",BENCH,IND.GATE_KIT,IND.GATE_LOCKED,"craft diversion_gate_kit at the real bench before the revisit")

func fresh_refusals() -> void:
	wall_start=Time.get_ticks_msec()
	check(not world.state.has(LR.STATE_KEY) and not LR.unlocked(world.state),"fresh world: no revisit record, revisit locked")
	for action:String in LR.ACTIONS:
		var target:Vector2i=LR.GATE_CELL if action==LR.GATE_ACTION else LR.SERVICE
		var extra:="a:3" if action==LR.GATE_ACTION else ""
		deny(action,target,extra,LR.WRONG_REGION,"fresh world %s from home"%action,false)
	var here:=Vector2i(floori(float(person().x)),floori(float(person().y)))
	deny("craft",here,IND.GATE_KIT,IND.GATE_LOCKED,"craft diversion_gate_kit on a fresh world",false)

func locked_refusals(label:String) -> void:
	check(world.player_region(TOKEN)=="lanyang","%s: player is in Lanyang"%label)
	deny(LR.GATE_ACTION,LR.GATE_CELL,"a:3",LR.LOCKED,"gate "+label,false)
	deny(LR.CHECK_ACTION,LR.FIELD_CELLS.upstream,"",LR.LOCKED,"check "+label,false)
	deny(LR.CLAIM_ACTION,LR.SERVICE,"",LR.LOCKED,"claim "+label,false)

# ---------------------------------------------------------------- journey

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	rev_started=true
	seg_actions=actions
	seg_walk=walking
	seg_time=now()
	revisit_leg()
	if not failed:home_materials_leg()
	if not failed:network_leg()
	if not failed:plaque_leg()
	if not failed:final_leg()
	finish_report()

func revisit_leg() -> void:
	var s:=world.state
	check(world.player_region(TOKEN)=="lanyang","revisit starts in Lanyang after the plaque")
	check(LR.unlocked(s) and LR.player_ready(s,TOKEN),"revisit unlocked: canal repaired, plaque set, own memory completed")
	check(not s.has(LR.STATE_KEY),"no revisit record before the first gate setting")
	check(LR.waiting_for_return(s,TOKEN),"The first day of practice invites a later return")
	deny(LR.GATE_ACTION,LR.GATE_CELL,"a:1",LR.RETURN_TOMORROW,"the practice day cannot start the dry-day round")
	deny(LR.CHECK_ACTION,LR.FIELD_CELLS.upstream,"",LR.RETURN_TOMORROW,"the practice day cannot mark fields")
	var reopened:=World.new()
	check(reopened.load_world(world.save_path) and LR.waiting_for_return(reopened.state,TOKEN),"Reopening the save on the same day preserves the invitation")
	wait_until(next_midnight()+1.0,60.0)
	check(not LR.waiting_for_return(world.state,TOKEN),"Crossing midnight opens the window for a dry-day return")
	var rain_days:=0
	while LR.raining(world.state) and not failed and rain_days<4:
		deny(LR.GATE_ACTION,LR.GATE_CELL,"a:1",LR.RAINY,"gate on rainy day %d"%LR.today(world.state))
		rain_days+=1
		wait_until(next_midnight()+1.0,60.0)
	revisit_info.rain_days_waited=rain_days
	var season:=LR.season(world.state)
	var demand:=LR.demand(world.state)
	var need:Array=DOC_GATES[season]
	check(HM.distribution(need)==demand,"documented %s gates %s give the demand %s"%[season,str(need),str(demand)])
	revisit_info.merge({"day":LR.today(world.state),"season":season,"demand":demand,"gates":need,"time":now(),"weather":WEATHER.at(now(),"lanyang").id})
	print("REVISIT_JOURNEY revisit day=%d season=%s weather=%s demand=%s needed_gates=a%d,b%d world_seconds=%.1f"%[LR.today(world.state),season,str(revisit_info.weather),str(demand),int(need[0]),int(need[1]),now()])
	var up:Vector2i=LR.FIELD_CELLS.upstream
	walk_to(up)
	deny(LR.CHECK_ACTION,up,"",LR.NO_GATES_TODAY,"check upstream before any gate setting",false)
	deny(LR.CHECK_ACTION,up+Vector2i(0,1),"",LR.WRONG_FIELD_CELL,"check a cell beside the upstream field",false)
	check(dist(LR.SERVICE)>LR.REACH,"standing at the upstream field, %.2f tiles from 星禾"%dist(LR.SERVICE))
	deny(LR.CLAIM_ACTION,LR.SERVICE,"",LR.TOO_FAR,"claim from the upstream field",false)
	walk_to(LR.GATE_CELL)
	deny(LR.CLAIM_ACTION,LR.SERVICE,"",LR.NOT_DONE,"claim before completion",true)
	walk_to(LR.GATE_CELL)
	deny(LR.GATE_ACTION,LR.GATE_CELL,"a:4",LR.BAD_GATE,"gate to level 4",false)
	# Wrong first setting: upstream share differs from the demand -> 份 message.
	var wrong_a:=int(need[0])-1 if int(need[0])>0 else 1
	var r:=do(LR.GATE_ACTION,LR.GATE_CELL,LR.gate_extra("a",wrong_a))
	var split:=HM.distribution([wrong_a,0])
	check(str(r.get("message",""))==LR.GATE_OK%["上游閘",wrong_a,split[0],split[1],split[2]],"wrong gate message: "+str(r.get("message","")))
	check(LR.gates(world.state)==[wrong_a,0] and LR.gates_today(world.state) and LR.checked_today(world.state).is_empty(),"record gates %s set today"%str(LR.gates(world.state)))
	deny(LR.CHECK_ACTION,up,"",LR.WRONG_SHARE%[LR.FIELD_NAMES.upstream,int(split[0]),int(demand[0])],"check upstream with a:%d (wrong share)"%wrong_a)
	walk_to(LR.GATE_CELL)
	do(LR.GATE_ACTION,LR.GATE_CELL,LR.gate_extra("a",int(need[0])))
	deny(LR.GATE_ACTION,LR.GATE_CELL,LR.gate_extra("a",int(need[0])),LR.SAME_GATE,"same upstream level again",false)
	var partial:=HM.distribution([int(need[0]),0])
	if partial!=demand:
		deny(LR.CHECK_ACTION,up,"",LR.OTHER_WRONG%[LR.FIELD_NAMES.upstream,int(partial[0])],"check upstream with b:0 (other fields wrong)")
		walk_to(LR.GATE_CELL)
	r=do(LR.GATE_ACTION,LR.GATE_CELL,LR.gate_extra("b",int(need[1])))
	check(str(r.get("message",""))==LR.GATE_OK%["中段閘",int(need[1]),demand[0],demand[1],demand[2]],"right gate message: "+str(r.get("message","")))
	check(LR.shares(world.state)==demand,"shares %s equal the demand"%str(LR.shares(world.state)))
	var order:=["upstream","middle","tail"]
	for i in order.size():
		var id:String=order[i]
		var cell:Vector2i=LR.FIELD_CELLS[id]
		var before:=bag().duplicate(true)
		r=do(LR.CHECK_ACTION,cell,"")
		if failed:return
		expect_bag(before,{},"field check %s changes no inventory"%id)
		if i<2:
			check(str(r.message)==LR.CHECK_OK%[LR.FIELD_NAMES[id],int(demand[i]),i+1],"check %s message: %s"%[id,str(r.message)])
		else:
			check(str(r.message)==LR.COMPLETE_OK,"third check completes: "+str(r.message))
		if i==0:deny(LR.CHECK_ACTION,cell,"",LR.ALREADY_CHECKED,"upstream checked twice",false)
	var rec:=LR.record(world.state)
	check(rec.completed==true and rec.checked==order and LR.gates(world.state)==need and int(rec.day)==LR.today(world.state) and (rec.claimed as Dictionary).is_empty(),"record completed %s"%JSON.stringify(rec))
	check(LR.tech_unlocked(world.state),"diversion gate recipe unlocked by completion")
	deny(LR.CHECK_ACTION,LR.FIELD_CELLS.tail,"",LR.ALREADY_DONE,"check after completion",false)
	walk_to(LR.GATE_CELL)
	deny(LR.GATE_ACTION,LR.GATE_CELL,"a:1",LR.ALREADY_DONE,"gate after completion",false)
	walk_to(LR.SERVICE)
	var bag0:=bag().duplicate(true)
	var coins0:=int(person().coins)
	r=do(LR.CLAIM_ACTION,LR.SERVICE,"")
	check(str(r.get("message",""))==LR.CLAIM_OK,"claim message")
	expect_bag(bag0,{LR.PLAQUE_ITEM:1},"claim: whole bag changed only by water_share_plaque_kit +1")
	check(int(person().coins)==coins0,"claim costs no coins")
	check(LR.claimed_own(world.state,TOKEN),"claimed recorded for this islander")
	deny(LR.CLAIM_ACTION,LR.SERVICE,"",LR.CLAIMED,"second claim",false)
	revisit_info.completed_at=now()
	reload_compare("after the revisit")

func home_materials_leg() -> void:
	# Pick up the irrigation set the regions journey left on the Lanyang trial field.
	var lan:Dictionary=world.state.regions.lanyang.objects
	var picked:=[]
	for k in lan.keys():
		var obj:Dictionary=lan[k]
		if str(obj.get("owner",""))==TOKEN and str(obj.get("type","")) in ["sprinkler","water_pipe","water_tank"]:picked.append(World.cell(k))
	check(picked.size()==4,"own Lanyang irrigation set: %s"%str(picked))
	for cell:Vector2i in picked:
		var kind:=str(world.state.regions.lanyang.objects[World.key(cell)].type)
		var kit:String={"sprinkler":"sprinkler_kit","water_pipe":"pipe_kit","water_tank":"tank_kit"}[kind]
		var before:=bag().duplicate(true)
		act("remove",cell)
		expect_bag(before,{kit:1},"pick up Lanyang %s returns one %s"%[kind,kit])
	act("travel",World.REGIONS.exit_cell("lanyang"),"home")
	check(world.player_region(TOKEN)=="home","back home by the normal exit")
	# Copper from the practice vein with the borrowed public pick.
	if not person().get("borrowed_mine_pick",false) and int(bag().get("reinforced_pick",0))<1:
		act("borrow_mine_pick",World.COPPER_CELL)
	while int(bag().get("copper_ore",0))<10 and not failed:
		var ready:=float(world.state.copper.ready)
		if ready>now():wait_for(ready-now(),12.0)
		var before:=bag().duplicate(true)
		act("pick",World.COPPER_CELL)
		expect_bag(before,{"copper_ore":2},"practice vein gives copper_ore 2")
	gather("wood","tree","axe",26,3)
	gather("stone","rock","pick",14,2)
	if failed:return
	for n in 5:
		var before:=bag().duplicate(true)
		act("craft",BENCH,"copper_joint")
		expect_bag(before,{"copper_ore":-2,"wood":-1,"copper_joint":1},"craft copper_joint %d"%(n+1))
	act("craft",BENCH,"sprinkler_kit")
	act("craft",BENCH,"kiln_kit")
	var kiln:=free_from(KILN_CANDIDATES)
	if not check(kiln!=Vector2i(-1,-1),"a free cell for the kiln"):return
	act("build",kiln,"charcoal_kiln")
	act("start_processing",kiln,"charcoal")
	wait_for(IND.PROCESS.charcoal.time,8.0)
	act("claim_processing",kiln)
	mill_batch(MILL)
	check(int(bag().get("plank",0))>=4 and int(bag().get("charcoal",0))>=2,"planks %d charcoal %d earned"%[int(bag().get("plank",0)),int(bag().get("charcoal",0))])
	act("craft",BENCH,"pump_kit")
	var before:=bag().duplicate(true)
	var r:=do("craft",BENCH,IND.GATE_KIT)
	check(str(r.get("message",""))=="製作完成：分流閘","gate kit craft message")
	expect_bag(before,{"plank":-2,"copper_joint":-1,"stone":-2,IND.GATE_KIT:1},"craft diversion_gate_kit: exact debit plank 2 / copper_joint 1 / stone 2")
	for item in ["sprinkler_kit","pipe_kit","tank_kit","pump_kit",IND.GATE_KIT]:
		var want:=2 if item in ["sprinkler_kit","pipe_kit"] else 1
		check(int(bag().get(item,0))>=want,"holding %s x%d (has %d)"%[item,want,int(bag().get(item,0))])
	print("REVISIT_JOURNEY materials earned at world_seconds=%.1f bag=%s"%[now(),JSON.stringify(nonzero(bag()))])

func network_leg() -> void:
	for cell:Vector2i in [S2,PIPE_B,GATE,S1,PIPE_A,TANK,PUMP]+NEAR+FAR:
		clear(cell)
		if failed:return
	# Far sprinkler first, so the gate-free supply order would serve it first.
	var builds:=[[S2,"sprinkler"],[PIPE_B,"water_pipe"],[GATE,IND.GATE_KIND],[S1,"sprinkler"],[PIPE_A,"water_pipe"],[TANK,"water_tank"],[PUMP,"water_pump"]]
	for row in builds:
		var before:=bag().duplicate(true)
		var kit:String=World.build_recipe(row[1],before).keys().filter(func(x):return x!="name")[0]
		act("build",row[0],row[1])
		expect_bag(before,{kit:-1},"build %s debits one %s"%[row[1],kit])
	if failed:return
	check(str(obj(GATE).get("mode",""))=="open" and obj(GATE).get("owner")==TOKEN,"new gate is open and mine")
	var group:=group_of(GATE)
	check(group.size()>0 and (group.sprinklers as Array).find(World.key(S2))<(group.sprinklers as Array).find(World.key(S1)),"original consumer order lists S2 before S1 (%s)"%str(group.get("sprinklers",[])))
	deny(IND.GATE_ACTION,GATE,"open",IND.GATE_SAME_MODE,"gate already open")
	deny(IND.GATE_ACTION,GATE,"half",IND.GATE_BAD_MODE,"gate to an unknown mode",false)
	act(IND.GATE_ACTION,GATE,"low")
	check(zones()=={World.key(S1):IND.ZONE_FULL,World.key(S2):IND.ZONE_LOW},"low: S1 full, S2 low %s"%str(zones()))
	act("toggle_sprinkler",S1)
	act("toggle_sprinkler",S2)
	act("toggle_pump",PUMP)
	if failed:return
	# Low mode while the new tank fills from 0 at 8 per pump tick.
	var saw_near_only:=false
	for tick in 16:
		wait_for(IND.INTERVAL,IND.INTERVAL)
		var row:=[int(obj(TANK).water),int(obj(S1).water),int(obj(S2).water)]
		low_log.append(row)
		check(row[2]==0 or row[1]==12,"low tick %d: far gets water only once near is full (tank/S1/S2 %s)"%[tick,str(row)])
		if row[1]>0 and row[2]==0:saw_near_only=true
		if row[1]==12 and row[2]==12:break
	check(saw_near_only,"low: a tick where S1 had water and S2 none %s"%str(low_log))
	check(int(obj(S1).water)==12 and int(obj(S2).water)==12,"both sprinklers full after %d ticks"%low_log.size())
	print("REVISIT_JOURNEY low-mode fill ticks tank/S1/S2 %s"%str(low_log))
	# Close the gate, plant both zones from owned/bought seeds.
	act(IND.GATE_ACTION,GATE,"closed")
	check(zones()=={World.key(S1):IND.ZONE_FULL,World.key(S2):IND.ZONE_CUT},"closed: S1 full, S2 cut")
	for cell:Vector2i in NEAR+FAR:
		act("hoe",cell)
		plant(cell)
	if failed:return
	wait_for(2*IND.INTERVAL,IND.INTERVAL)
	for cell:Vector2i in NEAR+FAR:check(crop(cell).wet==true,"planted %s watered by its sprinkler"%str(cell))
	var s2:=int(obj(S2).water)
	check(s2==12-FAR.size(),"S2 used one water per far crop (%d)"%s2)
	day_log.append({"day":day(),"weather":weather(),"S1":int(obj(S1).water),"S2":s2,"tank":int(obj(TANK).water),"note":"planted"})
	# Closed: day by day until a dry day starts with S2 empty.
	var proof:=false
	for guard in 14:
		if failed:return
		var prev:=s2
		wait_until(next_midnight()+120.0,60.0)
		s2=int(obj(S2).water)
		var rainy:=WEATHER.rains(WEATHER.day_index(now()),"home")
		var far_wet:=0
		for cell:Vector2i in FAR:far_wet+=1 if crop(cell).wet else 0
		var near_wet:=0
		for cell:Vector2i in NEAR:near_wet+=1 if crop(cell).wet else 0
		day_log.append({"day":day(),"weather":weather(),"S1":int(obj(S1).water),"S2":s2,"tank":int(obj(TANK).water),"far_wet":far_wet,"near_wet":near_wet})
		check(s2<=prev,"closed: S2 never refilled (%d -> %d)"%[prev,s2])
		check(int(obj(S1).water)==12 and int(obj(TANK).water)>0,"closed: S1 refilled to 12 from the tank (%d)"%int(obj(TANK).water))
		check(near_wet==NEAR.size(),"near crops wet on day %d"%day())
		if rainy:
			check(s2==prev and far_wet==FAR.size(),"rain day %d: crops rain-wet, S2 not consumed (%d)"%[day(),s2])
		else:
			check(s2==maxi(0,prev-FAR.size()) and far_wet==mini(prev,FAR.size()),"dry day %d: S2 %d -> %d waters %d far crops"%[day(),prev,s2,far_wet])
			if prev==0:
				proof=true
				break
	if not check(proof,"reached a dry day with S2 empty"):return
	print("REVISIT_JOURNEY closed-gate days %s"%JSON.stringify(day_log))
	# Proof day: harvest the mature crops and replant both zones.
	for cell:Vector2i in NEAR+FAR:
		var c:=crop(cell)
		if str(c.kind)!="" and float(c.growth)>=float(World.CROPS[c.kind].time):act("harvest",cell)
	for cell:Vector2i in NEAR+FAR:plant(cell)
	if failed:return
	# S1 already spent today's watering on the crops
	# just harvested, so fresh near crops are re-wetted at the next midnight tick.
	# Wait to the next dry-weather day's start; the far zone stays cut and empty.
	var proof_day:=int(WEATHER.day_index(now()))+1
	if not check(not WEATHER.rains(proof_day,"home"),"the day after the proof day is not rainy (day %d)"%(proof_day+1)):return
	wait_until(next_midnight(),60.0)
	var t0:=now()
	wait_for(150.0,30.0)
	var near_g:=[]
	var far_g:=[]
	for cell:Vector2i in NEAR:near_g.append(float(crop(cell).growth))
	for cell:Vector2i in FAR:far_g.append(float(crop(cell).growth))
	for g in near_g:check(g>0.0,"near crop grows while the gate is closed (%.1f)"%g)
	for cell:Vector2i in FAR:check(float(crop(cell).growth)==0.0 and crop(cell).wet==false,"far crop %s dry, growth 0 while closed and S2 empty"%str(cell))
	check(int(obj(S2).water)==0 and int(obj(TANK).water)>0,"S2 stays empty although the tank holds %d"%int(obj(TANK).water))
	growth_log.append({"phase":"closed","day":day(),"weather":weather(),"seconds":now()-t0,"near":near_g,"far":far_g,"S2":int(obj(S2).water)})
	act(IND.GATE_ACTION,GATE,"open")
	check(zones()=={World.key(S1):IND.ZONE_FULL,World.key(S2):IND.ZONE_FULL},"open: both zones full")
	wait_for(2*IND.INTERVAL,IND.INTERVAL)
	# The second network tick tops S2 up after the daily watering.
	check(int(obj(S2).water)==12,"reopened: S2 refilled from the tank (%d)"%int(obj(S2).water))
	for cell:Vector2i in FAR:check(crop(cell).wet==true,"reopened: far crop %s watered by S2"%str(cell))
	t0=now()
	wait_for(150.0,30.0)
	var far_after:=[]
	for cell:Vector2i in FAR:
		far_after.append(float(crop(cell).growth))
		check(float(crop(cell).growth)>0.0,"far crop %s grows after reopening (%.1f)"%[str(cell),float(crop(cell).growth)])
	growth_log.append({"phase":"reopened","day":day(),"weather":weather(),"seconds":now()-t0,"far":far_after,"S2":int(obj(S2).water)})
	print("REVISIT_JOURNEY growth %s"%JSON.stringify(growth_log))
	act(IND.GATE_ACTION,GATE,"low")
	check(str(obj(GATE).mode)=="low","final gate mode low")

func plaque_leg() -> void:
	var kit:=LR.PLAQUE_ITEM
	check(int(bag().get(kit,0))==1,"holding the claimed 分水木牌 kit")
	check(not World.trade_items().has(kit),"kit is excluded from trade_items()")
	var box:=World.SHIPPING.cell_for(world.state)
	deny("ship",box,JSON.stringify([[[kit,1]],1]),"出貨項目重複或無法出售。","ship the plaque kit")
	var stall:=MKT.cell_for(world.state)
	deny("market_stock",stall,kit+":1","%s不能擺上市集攤位；攤位只收農漁產、料理和花。"%LR.PLAQUE_NAME,"list the plaque kit on the market stall")
	deny("sell",SHOP,kit,"這件商品尚未上架","sell the plaque kit to 小栗")
	var tiles:=[]
	for tile:Vector2i in PLAQUE_CANDIDATES:
		if free_grass(tile):tiles.append(tile)
	if not check(tiles.size()>=3,"free grass for the plaque (%d)"%tiles.size()):return
	var spot:Vector2i=tiles[0]
	var before:=bag().duplicate(true)
	var r:=do("build",spot,LR.PLAQUE_KIND)
	check(str(r.get("message",""))=="放好了%s，家園又多了一點你的心意"%LR.PLAQUE_NAME,"plaque build message")
	expect_bag(before,{kit:-1},"build plaque: kit -1 only")
	check(same(obj(spot),{"type":LR.PLAQUE_KIND,"owner":TOKEN,"items":{}}),"plaque object at %s"%str(spot))
	check(not world.blocked(spot),"plaque does not block walking")
	deny("build",tiles[1],LR.PLAQUE_KIND,"材料不足，需要%s 1"%LR.PLAQUE_NAME,"second plaque without a kit")
	var dest:=Vector2i(-1,-1)
	walk_to(spot)
	for tile:Vector2i in tiles.slice(1):
		var d:=dist(tile)
		if d>=0.8 and d<=3.0:
			dest=tile
			break
	if not check(dest!=Vector2i(-1,-1),"a free tile to move the plaque to"):return
	before=bag().duplicate(true)
	r=do("move_object",spot,"%d,%d"%[dest.x,dest.y])
	check(not world.state.objects.has(World.key(spot)) and str(obj(dest).get("type",""))==LR.PLAQUE_KIND,"plaque moved %s -> %s"%[str(spot),str(dest)])
	expect_bag(before,{},"moving changes no inventory")
	before=bag().duplicate(true)
	act("remove",dest)
	expect_bag(before,{kit:1},"picking the plaque up returns exactly one kit")
	check(not world.state.objects.has(World.key(dest)),"plaque removed")
	before=bag().duplicate(true)
	act("build",spot,LR.PLAQUE_KIND)
	expect_bag(before,{kit:-1},"plaque placed again")
	revisit_info.plaque=[spot.x,spot.y]

func final_leg() -> void:
	reload_compare("final")
	if failed:return
	check(str(obj(GATE).get("mode",""))=="low","gate mode low persists through reload")
	check(LR.completed(world.state) and LR.claimed_own(world.state,TOKEN),"completion and claim persist")
	check(str(obj(Vector2i(revisit_info.plaque[0],revisit_info.plaque[1])).get("type",""))==LR.PLAQUE_KIND,"plaque persists")
	act("travel",World.REGIONS.exit_cell("home"),"lanyang")
	deny(LR.CLAIM_ACTION,LR.SERVICE,"",LR.CLAIMED,"claim again after reload")
	deny(LR.GATE_ACTION,LR.GATE_CELL,"a:1",LR.ALREADY_DONE,"revisit gate after reload")
	act("travel",World.REGIONS.exit_cell("lanyang"),"home")

func finish_report() -> void:
	var ra:=actions-seg_actions
	var rw:=walking-seg_walk
	print("REVISIT_JOURNEY revisit=%s"%JSON.stringify(revisit_info))
	for i in rejections.size():print("REVISIT_JOURNEY rejection %d %s"%[i+1,rejections[i]])
	print("REVISIT_JOURNEY stats actions_total=%d walk_tiles_total=%d world_seconds_total=%.1f revisit_segment_actions=%d revisit_segment_walk_tiles=%d revisit_segment_world_seconds=%.1f walk_seconds_equiv_not_on_clock=%.1f step_wait_seconds=%.1f rejections=%d all_rejections_state_unchanged=%s reloads=%d wall_ms=%d passed=%s"%[actions,walking,now(),ra,rw,now()-seg_time,float(walking)/3.6,waited,rejections.size(),str(rejections_changed==0),reloads,Time.get_ticks_msec()-wall_start,str(not failed)])

# ---------------------------------------------------------------- helpers

func check(condition:bool,message:String) -> bool:
	expect(condition,"REVISIT_JOURNEY: "+message)
	return condition

func now() -> float:
	return float(world.state.time)

func day() -> int:
	return int(WEATHER.day_index(now()))+1

func weather() -> String:
	return str(WEATHER.at(now(),"home").id)

func next_midnight() -> float:
	return (WEATHER.day_index(now())+1.0)*WEATHER.DAY_SECONDS

func dist(cell:Vector2i) -> float:
	return Vector2(person().x,person().y).distance_to(Vector2(cell)+Vector2(0.5,0.5))

func wait_for(seconds:float,chunk:float) -> void:
	wait_until(now()+seconds,chunk)

func wait_until(target:float,chunk:float) -> void:
	while now()<target-0.000001 and not failed:
		var dt:=minf(chunk,target-now())
		var stepped:=world.step(dt,true)
		expect(stepped,"REVISIT_JOURNEY world step %.2f (%s)"%[dt,str(world.step_error)])
		waited+=dt

func obj(cell:Vector2i) -> Dictionary:
	return world.state.objects.get(World.key(cell),{})

func crop(cell:Vector2i) -> Dictionary:
	return world.state.crops.get(World.key(cell),{"kind":"","growth":0.0,"wet":false})

func group_of(cell:Vector2i) -> Dictionary:
	for group in IND.components(world.state):
		if World.key(cell) in group["keys"]:return group
	return {}

func zones() -> Dictionary:
	var report:=IND.zone_report(world.state,World.key(GATE))
	var out:={}
	for row in report.get("consumers",[]):out[str(row.key)]=str(row.zone)
	return out

func clear(cell:Vector2i) -> void:
	match world.resource(cell):
		"tree":
			for hit in 3:act("axe",cell)
		"rock":
			for hit in 2:act("pick",cell)
		"grass":act("axe",cell)
	var k:=World.key(cell)
	check(world.resource(cell)=="" and not world.protected(cell) and not world.water(cell) and not world.state.objects.has(k) and not world.state.ground.has(k),"cell %s is clear land"%str(cell))

func plant(cell:Vector2i) -> void:
	if failed:return
	var kind:=""
	for option in ["radish","lettuce","wheat"]:
		if int(bag().get(option+"_seed",0))>0 and World.crop_grows_in_season(option,"home",cell,now()):
			kind=option
			break
	if kind=="":
		for option in ["radish","lettuce","potato"]:
			if World.crop_grows_in_season(option,"home",cell,now()):
				kind=option
				break
		if not check(not kind.is_empty(),"The shop has a seed for the current growing season"):return
		var coins:=int(person().coins)
		act("buy",SHOP,kind)
		var price:=int(World.CROPS[kind].seed_price)
		check(int(person().coins)==coins-price,"bought a %s seed for %d"%[kind,price])
	var before:=bag().duplicate(true)
	act("seed",cell,kind)
	expect_bag(before,{kind+"_seed":-1},"seed %s at %s"%[kind,str(cell)])

func free_from(candidates:Array) -> Vector2i:
	for tile:Vector2i in candidates:
		if free_grass(tile):return tile
	return Vector2i(-1,-1)

func free_grass(tile:Vector2i) -> bool:
	var k:=World.key(tile)
	for layer in ["objects","ground","roofs","crops","forest"]:
		if (world.state[layer] as Dictionary).has(k):return false
	return world.resource(tile)=="" and not world.protected(tile) and not world.blocked(tile) and not world.water(tile)

## A successful action through World.act after walking near the target.
func do(action:String,target:Vector2i,extra:String) -> Dictionary:
	walk_to(target)
	if failed:return {"ok":false,"message":"skipped"}
	actions+=1
	var result:=world.act(TOKEN,"revisit-%d"%actions,action,target,extra)
	print("%d %s %s %s | %s" % [actions,action,target,extra,result.message])
	check(result.ok,"%s %s at %s: %s"%[action,extra,str(target),str(result.message)])
	return result

## Refused with the exact message; whole World.state unchanged (== and canonical bytes).
func deny(action:String,target:Vector2i,extra:String,message:String,label:String,walk:=true) -> void:
	if failed:return
	if walk:walk_to(target)
	if failed:return
	actions+=1
	var state_before:=world.state.duplicate(true)
	var bytes_before:=var_to_bytes(canon(world.state))
	var result:=world.act(TOKEN,"revisit-%d"%actions,action,target,extra)
	check(not result.ok and str(result.message)==message,"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var unchanged:=world.state==state_before and var_to_bytes(canon(world.state))==bytes_before
	check(unchanged,label+": whole world state unchanged")
	if not unchanged:rejections_changed+=1
	rejections.append("%s | %s | %s | state_unchanged=%s"%[label,action,message,str(unchanged)])

func expect_bag(before:Dictionary,delta:Dictionary,label:String) -> void:
	var want:=nonzero(before)
	for item in delta:
		want[item]=int(want.get(item,0))+int(delta[item])
		if int(want[item])==0:want.erase(item)
	var got:=nonzero(bag())
	check(same(got,want),"%s (diff %s)"%[label,first_diff(canon(got),canon(want),"bag")])

func nonzero(inv:Dictionary) -> Dictionary:
	var out:={}
	for item in inv:
		if int(inv[item])!=0:out[str(item)]=int(inv[item])
	return out

## Save, reload into a fresh World, compare the WHOLE canonical state (numbers 1e-6),
## then continue the journey in the reloaded World.
func reload_compare(label:String) -> void:
	if failed:return
	check(world.save(),label+": save")
	var reopened:=World.new()
	if not check(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,label+": fresh World loads the primary save"):return
	var diffs:=[]
	all_diffs(canon(world.state),canon(reopened.state),"state",diffs)
	# Only accepted difference: a counter absent in the live state that the load
	# schema (save_schema.gd players: harvests/builds/fish_caught) defaults to 0.
	var defaults:=[]
	var real:=[]
	for row in diffs:
		if row.kind=="added_on_load" and (row.value is int or row.value is float) and float(row.value)==0.0:defaults.append(row.path)
		else:real.append(row)
	check(real.is_empty(),label+": whole canonical state identical after reload %s"%JSON.stringify(real.slice(0,5)))
	reopened.save_path=world.save_path
	reopened.add_player(TOKEN,"Island")
	var d2:=first_diff(canon(reopened.state.players[TOKEN]),canon(world.state.players[TOKEN]),"player")
	check(d2.is_empty() or d2.ends_with("missing in second"),label+": rejoin changes nothing but load defaults "+d2)
	world=reopened
	reloads+=1
	print("REVISIT_JOURNEY reload (%s) world_seconds=%.1f identical=%s load_defaults=%s"%[label,now(),str(real.is_empty()),str(defaults)])

## Every difference (up to 40): {"path","kind":"changed"|"added_on_load"|"lost_on_load","value"}.
static func all_diffs(a:Variant,b:Variant,path:String,out:Array) -> void:
	if out.size()>=40:return
	if (a is int or a is float) and (b is int or b is float):
		if absf(float(a)-float(b))>0.000001:out.append({"path":path,"kind":"changed","value":"%s vs %s"%[str(a),str(b)]})
		return
	if typeof(a)!=typeof(b):
		out.append({"path":path,"kind":"changed","value":"%s vs %s"%[str(a).left(60),str(b).left(60)]})
		return
	if a is Dictionary:
		for k in a:
			if not b.has(k):out.append({"path":"%s.%s"%[path,str(k)],"kind":"lost_on_load","value":a[k]})
			else:all_diffs(a[k],b[k],"%s.%s"%[path,str(k)],out)
		for k in b:
			if not a.has(k):out.append({"path":"%s.%s"%[path,str(k)],"kind":"added_on_load","value":b[k]})
		return
	if a is Array:
		if a.size()!=b.size():
			out.append({"path":path,"kind":"changed","value":"size %d vs %d"%[a.size(),b.size()]})
			return
		for i in a.size():all_diffs(a[i],b[i],"%s[%d]"%[path,i],out)
		return
	if a!=b:out.append({"path":path,"kind":"changed","value":"%s vs %s"%[str(a).left(60),str(b).left(60)]})

static func canon(value:Variant) -> Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			var source:Variant=value[k] if value.has(k) else value[StringName(k)]
			out[k]=canon(source)
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(canon(item))
		return list
	if value is Vector2i:return [value.x,value.y]
	if value is float and is_finite(value) and floorf(value)==value:return int(value)
	return value

static func first_diff(a:Variant,b:Variant,path:String) -> String:
	if (a is int or a is float) and (b is int or b is float):
		return "" if absf(float(a)-float(b))<=0.000001 else "%s: %s vs %s"%[path,str(a),str(b)]
	if typeof(a)!=typeof(b):return "%s: %s(%s) vs %s(%s)"%[path,type_string(typeof(a)),str(a).left(80),type_string(typeof(b)),str(b).left(80)]
	if a is Dictionary:
		for k in a:
			if not b.has(k):return "%s.%s missing in second"%[path,str(k)]
			var d:=first_diff(a[k],b[k],"%s.%s"%[path,str(k)])
			if not d.is_empty():return d
		for k in b:
			if not a.has(k):return "%s.%s missing in first"%[path,str(k)]
		return ""
	if a is Array:
		if a.size()!=b.size():return "%s: size %d vs %d"%[path,a.size(),b.size()]
		for i in a.size():
			var d:=first_diff(a[i],b[i],"%s[%d]"%[path,i])
			if not d.is_empty():return d
		return ""
	return "" if a==b else "%s: %s vs %s"%[path,str(a).left(80),str(b).left(80)]

static func same(a:Variant,b:Variant) -> bool:
	return var_to_bytes(canon(a))==var_to_bytes(canon(b))
