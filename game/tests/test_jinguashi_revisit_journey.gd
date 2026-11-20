extends "res://tests/test_memory_exhibit_journey.gd"
## Chapter 40「金瓜石回訪・礦料調度」+ 礦燈 natural journey: a FRESH temp world, ONE
## player (A) for the whole journey (plus the late joiners the parents add) and one
## more late joiner B at the end, ONE process (reloads are in-process
## World.new().load_world on the same save; the journey continues in the reloaded World).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
##
## Prerequisite reuse (disclosed): this file EXTENDS the unmodified
## test_memory_exhibit_journey.gd (-> festival earned -> salt pan -> flower journeys).
## That chain earns chapter one (picnic), the tea route, Tianwei, Beimen, the Lanyang
## repair, the cooperative mine B1-B5 (B1-B4 commissions, unlocked 5), the dock, the
## kitchen, the shared meal, two lamps, the real 風鈴節 opening, the Lanyang revisit
## and the 分水木牌 exhibit. It never repairs the hoist and never sorts with Bobo.
## The B5 commission, the Q07 hoist repair, the Bobo sort and the strikes are
## RE-DERIVED here from test_bobo_journey.gd (different chain, so it cannot be
## inherited). UPDATE: the parent (festival earned) now also earns the B5 commission
## and the Q07 hoist repair, so this file only mines the ore it needs, rides the
## repaired hoist, sorts with Bobo and does the revisit.
##
## Hook: chapter_one() (fresh world, BEFORE the picnic): the three jg_revisit actions
## are refused (A cannot even be in Jinguashi yet: WRONG_REGION; the pure blocks say
## LOCKED). After the parents finish: LOCKED in Jinguashi before the hoist repair,
## NOT_READY after it but before A's own Bobo sort.
##
## Everything goes through World.act after World.move_player along BFS routes, and
## World.step (inherited wait()) for waits. NO direct writes by this file to
## inventory, coins, flags, mine progress, revisit / exhibit / bobo records, objects,
## positions or time. B joins with World.add_player (the Session join path).
## Prints JG_REVISIT_JOURNEY lines before the parents' summary lines.

const JG=preload("res://scripts/jinguashi_revisit.gd")
const JG_SURFACE=preload("res://scripts/jinguashi.gd")
const JG_B:="jg-revisit-late-b"
const JG_B_NAME:="Lantern Late"
## Independent copy of the season order table from the rules report.
const JG_ORDER_TABLE:={
	"spring":{"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"},
	"summer":{"bobo":"copper_ore","ferry":"gold_ore","depot":"stone"},
	"autumn":{"bobo":"gold_ore","ferry":"stone","depot":"copper_ore"},
	"winter":{"bobo":"copper_ore","ferry":"gold_ore","depot":"stone"},
}
const JG_AMOUNTS:={"gold_ore":2,"copper_ore":4,"stone":6}
const JG_SHIP_PLAN:=["bobo","depot","ferry"]
const JG_LANTERN_SPOTS:=[Vector2i(36,37),Vector2i(34,36),Vector2i(36,36),Vector2i(34,37),Vector2i(33,36),Vector2i(37,37)]

var jg_fresh_done:=false
var jg_started:=false
var jg_ms:=0
var jg_actions_start:=0
var jg_walk_start:=0
var jg_time_start:=0.0
var jg_checks_start:=0
var jg_refusals:=[]
var jg_changed:=0
var jg_strikes:={}
var jg_mined:={}
var jg_info:={}

# ---------------------------------------------------------------- hooks

func chapter_one() -> void:
	if not jg_fresh_done:
		jg_fresh_done=true
		jg_fresh()
	super.chapter_one()

## Fresh world, before the picnic: A is at home and cannot travel yet.
func jg_fresh() -> void:
	var s:=world.state
	var table:=JG.sort_cell(s)
	jg_check(not bool(s.picnic) and world.player_region(tok)=="home","fresh world: no picnic, A at home")
	jg_check(not JG.unlocked(s) and not JG.player_ready(s,tok) and not s.has(JG.STATE_KEY),"fresh world: revisit locked, A not ready, no record")
	jg_check(JG.sort_block(s,tok)==JG.LOCKED and JG.ship_block(s,"bobo",bag(),tok)==JG.LOCKED and JG.claim_block(s,bag(),tok)==JG.LOCKED,"fresh world: sort/ship/claim blocks all LOCKED")
	jg_check(ME.personal_hint_for(s,"jinguashi",tok)==ME.HINT_JG_LOCKED and not ME.available(s,"jinguashi"),"fresh world: lantern hint LOCKED, no lantern exhibit")
	# The actions themselves: A is not in Jinguashi (travel needs the picnic), so the
	# region check (before LOCKED in the documented order) answers.
	jg_deny(JG.SORT_ACTION,table,JG.sort_extra("bobo","gold_ore"),JG.WRONG_REGION,"fresh world sort (at home, before the picnic)",false)
	jg_deny(JG.SHIP_ACTION,JG.HOIST,"",JG.WRONG_REGION,"fresh world ship (at home, before the picnic)",false)
	jg_deny(JG.CLAIM_ACTION,table,"",JG.WRONG_REGION,"fresh world claim (at home, before the picnic)",false)

# ---------------------------------------------------------------- journey

func run() -> void:
	super.run()
	if failed:return
	jg_check(jg_fresh_done,"fresh-world hook ran")
	jg_started=true
	jg_ms=Time.get_ticks_msec()
	jg_actions_start=actions
	jg_walk_start=walking
	jg_time_start=now()
	jg_checks_start=checks
	tok=TOKEN_A
	jg_info.start={"day":JG.today(world.state),"season":JG.order_season(world.state),"world_seconds":now(),"held":jg_held()}
	print("JG_REVISIT_JOURNEY prerequisite chain passed (checks %d, actions %d, world_seconds %.1f, day %d %s, A holds %s)"%[checks,actions,now(),JG.today(world.state),JG.order_season(world.state),JSON.stringify(jg_held())])
	jg_prepare_parts()
	if not failed:jg_locked_in_jinguashi()
	if not failed:jg_open_b6()
	if not failed:jg_repair_hoist()
	if not failed:jg_not_ready()
	if not failed:jg_bobo_sort()
	if not failed:jg_revisit()
	if not failed:jg_claim_and_reload()
	if not failed:jg_lantern_home()
	if not failed:jg_exhibit()
	if not failed:jg_late_b()

## Home: earn the planks and copper joints for the B5 commission and the Q07 hoist.
func jg_prepare_parts() -> void:
	var s:=world.state
	# The parent chain (festival earned) now earns the B5 commission AND the Q07 hoist
	# repair for A through real actions. Only the Bobo sort and the revisit remain.
	jg_check(world.player_region(tok)=="home" and int(s.mine_depths.unlocked)==6 and World.MINES.hoist_ready(s.mine_depths),"start: A at home, B5 commission done (B6 open), hoist repaired by the parent chain")
	jg_check(JG.unlocked(s) and not s.has(JG.STATE_KEY) and not JG.player_ready(s,tok) and not (s.bobo_workshop.done as Dictionary).has(tok),"start: revisit unlocked, no record, A never sorted with Bobo")
	jg_check(not ME.available(s,"jinguashi") and ME.on_display_ids(s)==["lanyang"] and ME.personal_hint_for(s,"jinguashi",tok)==ME.HINT_JG_NOT_DONE_NOT_READY,"start: no lantern on the exhibit, hint NOT_DONE_NOT_READY")
	jg_info.parts={"held":jg_held(["plank","copper_joint","copper_ore","gold_ore","stone"])}

func jg_ride() -> void:
	travel(FERRY,"toucheng")
	travel(World.TRANSIT.points("toucheng").rail.cell,"ruifang")
	travel(World.TRANSIT.points("ruifang").bus.cell,"jiufen")
	travel(World.TRANSIT.points("jiufen").shuttle.cell,"jinguashi")

## In Jinguashi with the hoist already repaired by the parent: unlocked, but A has not
## sorted with Bobo, so every revisit action is NOT_READY at every point.
func jg_locked_in_jinguashi() -> void:
	jg_ride()
	if failed:return
	var s:=world.state
	var table:=JG.sort_cell(s)
	jg_check(table==World.BOBO_WORKSHOP.sites(s).table and table==Vector2i(23,20),"Bobo's table %s is the sort/claim cell"%str(table))
	jg_check(JG.dest_cell(s,"bobo")==table and JG.dest_cell(s,"ferry")==JG.SHUTTLE and JG.dest_cell(s,"depot")==JG.HOIST and JG.HOIST==World.MINES.ENTRY,"three ship points: table, shuttle %s, hoist %s"%[str(JG.SHUTTLE),str(JG.HOIST)])
	jg_deny(JG.SORT_ACTION,table,JG.sort_extra("bobo","copper_ore"),JG.NOT_READY,"sort before A's Bobo sort")
	jg_deny(JG.SHIP_ACTION,table,"",JG.NOT_READY,"ship bobo crate before A's Bobo sort",false)
	jg_deny(JG.CLAIM_ACTION,table,"",JG.NOT_READY,"claim before A's Bobo sort",false)
	jg_deny(JG.SHIP_ACTION,JG.SHUTTLE,"",JG.NOT_READY,"ship ferry crate before A's Bobo sort")
	jg_deny(JG.SHIP_ACTION,JG.HOIST,"",JG.NOT_READY,"ship depot crate before A's Bobo sort")
	jg_deny(World.HOIST_ACTION,World.MINES.ENTRY,"",World.HOIST_DONE_MSG,"hoist already repaired by the parent chain")

## B1 -> B5 by the stairs: B3 stone strikes and B5 gold strikes (the earned ore for
## Bobo's sort and the order), then B6 (already open) and the hoist cage back up.
func jg_open_b6() -> void:
	act("mine_travel",World.MINES.ENTRY,"mine_1")
	for d in range(1,6):
		if failed:return
		jg_check(world.player_region(tok)=="mine_%d"%d,"on B%d"%d)
		if d==3:
			for i in 2:jg_strike(d,World.MINES.NODES[i])
		if d==5:
			for node:Vector2i in World.MINES.NODES:jg_strike(d,node)
		if d<5:act("mine_travel",World.MINES.DOWN,"mine_%d"%(d+1))
	if failed:return
	jg_check(int(world.state.mine_depths.unlocked)==6,"B6 already open from the parent's B5 commission")
	act("mine_travel",World.MINES.DOWN,"mine_6")
	jg_check(world.player_region(tok)=="mine_6","reached B6 by the stairs")
	act("mine_travel",World.MINES.LIFT,"jinguashi")
	jg_check(world.player_region(tok)=="jinguashi","B6 hoist cage back to the surface")

func jg_strike(d:int,node:Vector2i) -> void:
	if failed:return
	var cost:=World.MINES.energy_cost(d)
	if int(person().mine_energy)<=cost:
		act("mine_rest",World.MINES.REST)
		jg_check(int(person().mine_energy)==100,"rest station restores mine energy")
	var ready:=float(world.state.mine_depths.ready.get("mine_%d"%d,{}).get(World.key(node),0.0))
	if ready>now():wait(ready-now()+0.1)
	var ore:String=World.MINES.ORES[d-1]
	var amount:int=World.MINES.YIELDS[d-1]
	var before:=bag().duplicate(true)
	var energy:=int(person().mine_energy)
	act("pick",node)
	if failed:return
	var expected:=before.duplicate(true)
	expected[ore]=int(before.get(ore,0))+amount
	for found:String in World.MINES.finds(d):expected[found]=int(expected.get(found,0))+1
	expect_same(bag(),expected,"JG_REVISIT_JOURNEY: B%d pick at %s yields %s +%d and finds %s"%[d,str(node),ore,amount,str(World.MINES.finds(d))])
	jg_check(int(person().mine_energy)==energy-cost,"B%d strike spends %d energy"%[d,cost])
	jg_strikes["B%d"%d]=int(jg_strikes.get("B%d"%d,0))+1
	jg_mined[ore]=int(jg_mined.get(ore,0))+amount

## The surface hoist (repaired by the parent chain) really carries A to B6 and back.
func jg_repair_hoist() -> void:
	act("mine_travel",World.MINES.ENTRY,"mine_6")
	jg_check(world.player_region(tok)=="mine_6","repaired surface hoist lands on B6")
	act("mine_travel",World.MINES.LIFT,"jinguashi")
	jg_check(world.player_region(tok)=="jinguashi" and World.MINES.hoist_ready(world.state.mine_depths) and JG.unlocked(world.state),"back on the surface; hoist ready, revisit unlocked")

## Hoist repaired, A has not sorted with Bobo: NOT_READY.
func jg_not_ready() -> void:
	var s:=world.state
	jg_check(JG.unlocked(s) and not JG.player_ready(s,tok) and JG.sort_block(s,tok)==JG.NOT_READY,"unlocked, A not ready")
	jg_check(ME.personal_hint_for(s,"jinguashi",tok)==ME.HINT_JG_NOT_DONE_NOT_READY,"hint NOT_DONE_NOT_READY")
	jg_deny(JG.SHIP_ACTION,JG.HOIST,"",JG.NOT_READY,"ship depot crate before A's Bobo sort")
	var table:=JG.sort_cell(s)
	jg_deny(JG.SORT_ACTION,table,JG.sort_extra("bobo","copper_ore"),JG.NOT_READY,"sort before A's Bobo sort")
	jg_deny(JG.SHIP_ACTION,table,"",JG.NOT_READY,"ship bobo crate before A's Bobo sort",false)
	jg_deny(JG.CLAIM_ACTION,table,"",JG.NOT_READY,"claim before A's Bobo sort",false)
	jg_check(not world.state.has(JG.STATE_KEY),"no revisit record written by any refusal")

func jg_bobo_sort() -> void:
	var table:Vector2i=World.BOBO_WORKSHOP.sites(world.state).table
	var gold:=int(bag().get("gold_ore",0))
	var samples:=int(bag().get("gold_sample",0))
	jg_check(gold>=3,"holding %d earned gold ore for Bobo's sort"%gold)
	act("bobo_sort_start",table)
	jg_check(int(bag().get("gold_ore",0))==gold-3,"sort start takes 3 gold ore")
	jg_deny("bobo_sort_answer",table,"0:small","請依礦樣標籤選擇這一輪的格子。","Bobo sort wrong bin",false)
	act("bobo_sort_answer",table,"0:large")
	act("bobo_sort_answer",table,"1:medium")
	act("bobo_sort_answer",table,"2:small")
	act("bobo_sort_claim",table)
	if failed:return
	jg_check(world.state.bobo_workshop.done.get(tok)==true and int(bag().get("gold_sample",0))==samples+1,"A's own Bobo sort done, +1 gold sample")
	jg_check(JG.player_ready(world.state,tok) and JG.sort_block(world.state,tok)=="" and ME.personal_hint_for(world.state,"jinguashi",tok)==ME.HINT_JG_NOT_DONE,"A ready; hint NOT_DONE")

## The revisit itself.
func jg_revisit() -> void:
	var s:=world.state
	var table:=JG.sort_cell(s)
	var season:=JG.order_season(s)
	var order:=JG.order(s)
	jg_check(order==JG_ORDER_TABLE[season] and JG.order_for(season)==order,"%s order %s matches the rules table"%[season,JSON.stringify(order)])
	jg_check(str(season)==WEATHER.season_on_day(WEATHER.day_index(now())) and JG.reason(s)==JG.reason_for(season) and not JG.reason(s).is_empty(),"order season is today's season; reason set")
	for ore:String in JG_AMOUNTS:jg_check(JG.amount_for(ore)==int(JG_AMOUNTS[ore]),"amount %s = %d"%[ore,int(JG_AMOUNTS[ore])])
	jg_info.order={"day":JG.today(s),"season":season,"order":order,"held":jg_held()}
	print("JG_REVISIT_JOURNEY order day=%d season=%s order=%s held=%s strikes=%s mined=%s"%[JG.today(s),season,JSON.stringify(order),JSON.stringify(jg_held()),JSON.stringify(jg_strikes),JSON.stringify(jg_mined)])
	walk_to(table)
	jg_deny(JG.SHIP_ACTION,table,"",JG.UNSORTED%JG.DEST_NAMES.bobo,"ship bobo crate before any sort",false)
	jg_deny(JG.CLAIM_ACTION,table,"",JG.NOT_DONE,"claim before completion",false)
	jg_deny(JG.SORT_ACTION,table,"bobo:diamond",JG.BAD_SORT,"sort with an unknown ore",false)
	# Sort the bobo crate wrong on purpose (with the ferry's ore), the others right.
	var wrong:String=order.ferry
	jg_check(wrong!=str(order.bobo),"wrong ore %s differs from bobo's %s"%[wrong,str(order.bobo)])
	jg_sort("bobo",wrong)
	jg_sort("ferry",str(order.ferry))
	jg_sort("depot",str(order.depot))
	var msg:=JG.WRONG_ORE%[JG.DEST_NAMES.bobo,JG.ORE_NAMES[wrong],JG.ORE_NAMES[order.bobo]]
	jg_check(msg=="波波的整理桌的貨箱現在分到%s，訂單要的是%s。回波波的整理桌重新分揀。"%[JG.ORE_NAMES[wrong],JG.ORE_NAMES[order.bobo]],"wrong-assignment text")
	jg_deny(JG.SHIP_ACTION,table,"",msg,"ship the wrongly sorted bobo crate",false)
	jg_deny(JG.SHIP_ACTION,JG.HOIST,"",JG.OTHER_WRONG%JG.DEST_NAMES.depot,"ship the right depot crate while bobo is wrong")
	walk_to(table)
	jg_sort("bobo",str(order.bobo))
	jg_deny(JG.SORT_ACTION,table,JG.sort_extra("bobo",str(order.bobo)),JG.SAME_SORT%JG.ORE_NAMES[order.bobo],"same sort twice",false)
	jg_check(JG.crates(world.state)==order,"crates now match the order")
	var npc:Vector2i=World.BOBO_WORKSHOP.sites(world.state).npc
	jg_deny(JG.SHIP_ACTION,npc,"",JG.WRONG_SHIP_CELL,"ship at Bobo himself (not a ship point)",false)
	jg_check(jg_dist(JG.SHUTTLE)>JG.REACH,"at the table, %.2f tiles from the shuttle"%jg_dist(JG.SHUTTLE))
	jg_deny(JG.SHIP_ACTION,JG.SHUTTLE,"",JG.TOO_FAR,"ship the ferry crate from the table (too far)",false)
	var first_rid:=""
	var copper_struck:=0
	var shipped:=[]
	jg_info.ships=[]
	for dest:String in JG_SHIP_PLAN:
		if failed:return
		var ore:String=order[dest]
		var amount:=int(JG_AMOUNTS[ore])
		var cell:=JG.dest_cell(world.state,dest)
		walk_to(cell)
		var source:="held"
		if int(bag().get(ore,0))<amount:
			jg_deny(JG.SHIP_ACTION,cell,"",JG.SHORT%[JG.ORE_NAMES[ore],amount,int(bag().get(ore,0))],"ship %s crate while short of %s (%d)"%[dest,ore,int(bag().get(ore,0))],false)
			if ore=="copper_ore":
				while not failed and int(bag().get(ore,0))<amount:
					jg_surface_copper()
					copper_struck+=1
				source="surface node strikes x%d"%copper_struck
				walk_to(cell)
			else:
				jg_check(false,"BLOCKER: short of %s at the %s point with no earned source planned"%[ore,dest])
				return
		var before:=bag().duplicate(true)
		var expected:=before.duplicate(true)
		expected[ore]=int(before.get(ore,0))-amount
		var done_before:=shipped.size()
		var want:=JG.COMPLETE_OK if done_before==2 else JG.SHIP_OK%[JG.DEST_NAMES[dest],JG.ORE_NAMES[ore],amount,done_before+1]
		var rid:=jg_ok(JG.SHIP_ACTION,cell,"",want,"ship %s crate (%s %d)"%[dest,ore,amount],["state.%s"%JG.STATE_KEY,"state.players.%s.inventory.%s"%[tok,ore]])
		if failed:return
		expect_same(bag(),expected,"JG_REVISIT_JOURNEY: ship %s: whole bag delta is exactly %s -%d"%[dest,ore,amount])
		shipped.append(dest)
		jg_info.ships.append({"dest":dest,"ore":ore,"amount":amount,"day":JG.today(world.state),"held_before":int(before.get(ore,0)),"source":source})
		jg_check(JG.sent(world.state)==shipped,"sent order %s"%str(shipped))
		if done_before==0:
			first_rid=rid
			jg_check(int(JG.record(world.state).day)==JG.today(world.state) and JG.order_season(world.state)==season,"first send stamps the order day %d"%JG.today(world.state))
			var bytes:=canon_bytes(world.state)
			var again:=world.act(tok,rid,JG.SHIP_ACTION,cell,"")
			jg_check(again.ok==true and str(again.message)==want and canon_bytes(world.state)==bytes,"resend of %s returns the stored receipt, nothing applied twice"%rid)
			jg_deny(JG.SHIP_ACTION,cell,"",JG.ALREADY_SENT%JG.DEST_NAMES[dest],"ship the %s crate again (new request)"%dest,false)
			jg_deny(JG.SORT_ACTION,table,JG.sort_extra("ferry","stone"),JG.SENT_LOCKED,"re-sort after the first send",false)
	var rec:=JG.record(world.state)
	jg_check(rec.completed==true and int(rec.done_day)==JG.today(world.state) and int(rec.done_day)>=int(rec.day) and rec.sent==shipped and (rec.claimed as Dictionary).is_empty(),"completed record %s"%JSON.stringify(JG.public(world.state)))
	jg_check(ME.available(world.state,"jinguashi") and ME.on_display_ids(world.state)==["lanyang","jinguashi"],"completion itself puts the lantern on the exhibit")
	jg_check(ME.personal_hint_for(world.state,"jinguashi",tok)==ME.HINT_JG_UNCLAIMED,"hint UNCLAIMED")
	var ferry_cell:=JG.dest_cell(world.state,str(shipped[-1]))
	jg_deny(JG.SHIP_ACTION,ferry_cell,"",JG.ALREADY_DONE,"ship after completion",false)
	jg_info.revisit={"order_day":int(rec.day),"done_day":int(rec.done_day),"season":season,"order":order,"sent":shipped,"copper_surface_strikes":copper_struck,"first_ship_rid":first_rid,"weather_done_day":WEATHER.outdoor_id(float(int(rec.done_day)-1))}
	print("JG_REVISIT_JOURNEY completed order_day=%d done_day=%d season=%s sent=%s ships=%s"%[int(rec.day),int(rec.done_day),season,str(shipped),JSON.stringify(jg_info.ships)])

func jg_sort(dest:String,ore:String) -> void:
	var table:=JG.sort_cell(world.state)
	jg_ok(JG.SORT_ACTION,table,JG.sort_extra(dest,ore),JG.SORT_OK%[JG.ORE_NAMES[ore],JG.DEST_NAMES[dest]],"sort %s:%s"%[dest,ore],["state.%s"%JG.STATE_KEY])
	if not failed:jg_check(str(JG.crates(world.state)[dest])==ore,"%s crate holds %s"%[dest,ore])

func jg_surface_copper() -> void:
	var node:Vector2i=JG_SURFACE.NODES[0]
	var ready:=float(world.state.jinguashi.ready.get(World.key(node),0.0))
	if ready>now():wait(ready-now()+0.1)
	var before:=bag().duplicate(true)
	act("pick",node)
	if failed:return
	var expected:=before.duplicate(true)
	expected["copper_ore"]=int(before.get("copper_ore",0))+JG_SURFACE.YIELD
	expect_same(bag(),expected,"JG_REVISIT_JOURNEY: Jinguashi surface node %s gives copper_ore +%d"%[str(node),JG_SURFACE.YIELD])
	jg_strikes["surface"]=int(jg_strikes.get("surface",0))+1
	jg_mined["copper_ore"]=int(jg_mined.get("copper_ore",0))+JG_SURFACE.YIELD

func jg_claim_and_reload() -> void:
	var table:=JG.sort_cell(world.state)
	walk_to(table)
	var kits:=int(bag().get(JG.LANTERN_ITEM,0))
	jg_check(kits==0,"no lantern kit before claiming")
	var rid:=jg_ok(JG.CLAIM_ACTION,table,"",JG.CLAIM_OK,"claim the lantern",["state.%s.claimed"%JG.STATE_KEY,"state.players.%s.inventory.%s"%[tok,JG.LANTERN_ITEM]])
	if failed:return
	jg_check(int(bag().get(JG.LANTERN_ITEM,0))==1 and JG.claimed_own(world.state,tok) and ME.personal_hint_for(world.state,"jinguashi",tok)==ME.HINT_JG_CLAIMED,"one lantern kit; hint CLAIMED")
	var bytes:=canon_bytes(world.state)
	var again:=world.act(tok,rid,JG.CLAIM_ACTION,table,"")
	jg_check(again.ok==true and str(again.message)==JG.CLAIM_OK and canon_bytes(world.state)==bytes and int(bag().get(JG.LANTERN_ITEM,0))==1,"resend of the claim %s: stored receipt, still one kit"%rid)
	jg_deny(JG.CLAIM_ACTION,table,"",JG.CLAIMED,"second claim (new request)",false)
	jg_deny(JG.SORT_ACTION,table,JG.sort_extra("bobo","stone"),JG.ALREADY_DONE,"sort after completion",false)
	var rec:=canon_bytes(world.state[JG.STATE_KEY])
	ex_reload("after the lantern claim (in Jinguashi)")
	if failed:return
	jg_check(canon_bytes(world.state[JG.STATE_KEY])==rec and typeof(world.state[JG.STATE_KEY].day)==TYPE_INT and typeof(world.state[JG.STATE_KEY].done_day)==TYPE_INT,"revisit record identical after reload (day/done_day int)")
	jg_check(world.player_region(tok)=="jinguashi" and int(bag().get(JG.LANTERN_ITEM,0))==1,"A still in Jinguashi with one kit after reload")
	jg_deny(JG.CLAIM_ACTION,table,"",JG.CLAIMED,"claim after the reload")

## Home: the lantern is a keepsake, not currency; build / move / remove / build.
func jg_lantern_home() -> void:
	travel(World.TRANSIT.STATIONS.jinguashi.cell,"home")
	if failed:return
	var kit:=JG.LANTERN_ITEM
	jg_check(not World.trade_items().has(kit) and World.NAMES.has(kit),"lantern kit excluded from trade items")
	jg_deny("sell",RECEIVER,kit,"這件商品尚未上架","小栗 refuses to buy the lantern kit")
	jg_deny("ship",World.SHIPPING.cell_for(world.state),JSON.stringify([[[kit,1]],10]),"出貨項目重複或無法出售。","shipping bin refuses the lantern kit")
	jg_deny("market_stock",World.MARKET.cell_for(world.state),kit+":1","%s不能擺上市集攤位；攤位只收農漁產、料理和花。"%JG.LANTERN_NAME,"market stall refuses the lantern kit")
	var spot:=Vector2i(-1,-1)
	for tile:Vector2i in JG_LANTERN_SPOTS:
		if ex_free(tile):
			spot=tile
			break
	if spot==Vector2i(-1,-1):spot=open_cell()
	if not jg_check(spot!=Vector2i(-1,-1),"free home cell for the lantern %s"%str(spot)):return
	var before:=bag().duplicate(true)
	act("build",spot,JG.LANTERN_KIND)
	if failed:return
	jg_check(int(bag().get(kit,0))==int(before.get(kit,0))-1,"build debits the kit")
	jg_check(same_canon(world.state.objects.get(World.key(spot),{}),{"type":JG.LANTERN_KIND,"owner":tok,"items":{}}) and not world.blocked(spot),"礦燈 placed at %s, walk-through"%str(spot))
	jg_deny("build",spot+Vector2i(0,1),JG.LANTERN_KIND,"材料不足，需要%s 1"%JG.LANTERN_NAME,"second lantern without a kit",false)
	var dest:=Vector2i(-1,-1)
	for off:Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1)]:
		var c:=spot+off
		if ex_free(c) and jg_dist(c)<=3.0:
			dest=c
			break
	if not jg_check(dest!=Vector2i(-1,-1),"free cell beside the lantern within reach"):return
	act("move_object",spot,"%d,%d"%[dest.x,dest.y])
	if failed:return
	jg_check(world.state.objects.has(World.key(dest)) and not world.state.objects.has(World.key(spot)) and str(world.state.objects[World.key(dest)].type)==JG.LANTERN_KIND,"lantern moved %s -> %s"%[str(spot),str(dest)])
	act("remove",dest)
	if failed:return
	jg_check(int(bag().get(kit,0))==1 and not world.state.objects.has(World.key(dest)),"remove returns the kit")
	act("build",spot,JG.LANTERN_KIND)
	if failed:return
	jg_check(int(bag().get(kit,0))==0 and str(world.state.objects.get(World.key(spot),{}).get("type",""))==JG.LANTERN_KIND,"lantern placed again at %s"%str(spot))
	jg_info.lantern=[spot.x,spot.y]
	ex_reload("after placing the lantern at home")
	if failed:return
	jg_check(same_canon(world.state.objects.get(World.key(spot),{}),{"type":JG.LANTERN_KIND,"owner":tok,"items":{}}),"lantern persists after reload")

## The exhibit at the festival plaza (the festival opening was earned by the parents).
func jg_exhibit() -> void:
	var s:=world.state
	jg_check(s.get("festival_story_open")==true,"festival opened by the earned parent steps")
	var stand:=ME.stand_cell(s)
	walk_to(stand)
	s=world.state
	var rv:Dictionary=jg_info.revisit
	var row:=ME.exhibit(s,"jinguashi",tok)
	jg_check(row.on_display==true and row.unread==true and row.seen==false and str(row.source)==JG.LANTERN_SOURCE and str(row.project)==JG.LANTERN_PROJECT and str(row.disclaimer)==JG.DISCLAIMER,"礦燈 slot on display and unread %s"%JSON.stringify(row))
	var recap:=ME.recap_for(s,"jinguashi")
	var crates:=[]
	for dest:String in JG.DESTS:crates.append(str(rv.order[dest]))
	var recap_crates:=[]
	for c:Dictionary in recap.crates:recap_crates.append(str(c.ore))
	jg_check(int(recap.day)==int(rv.done_day) and int(recap.order_day)==int(rv.order_day) and str(recap.season)==str(rv.season) and recap_crates==crates and recap.sent==rv.sent and str(recap.weather)==str(rv.weather_done_day),"recap matches what happened %s"%JSON.stringify(recap))
	jg_check(str(recap.reason)==JG.reason_for(str(rv.season)),"recap reason is the order season's")
	var names:=[]
	for dest in rv.sent:names.append(str(JG.DEST_NAMES[dest]))
	jg_check(row.lines.size()==7 and str(row.lines[3])=="完成那天：第 %d 日・%s"%[int(rv.done_day),str(recap.weather_label)] and str(row.lines[5])=="送出的先後：%s"%"、".join(PackedStringArray(names)) and str(row.lines[4]).begins_with(str(recap.season_label)+"的訂單："),"exhibit lines %s"%JSON.stringify(row.lines))
	jg_check(ME.recap_pages("jinguashi",s).size()==4 and ME.view_block(s,"jinguashi",tok)=="","4 recap pages; view allowed")
	var me:=ME.personal(s,tok)
	jg_check(me.seen==["lanyang"] and int(me.unread)==1 and me.sorting_done==true and me.lantern_claimed==true and str(me.lantern_hint)==ME.HINT_JG_CLAIMED,"A personal before viewing %s"%JSON.stringify(me))
	ex_view_ok(stand,"jinguashi","A views the lantern")
	if failed:return
	jg_check(same_canon(person().get(ME.RECORD_KEY),{"seen":["lanyang","jinguashi"]}),"A's record {seen:[lanyang, jinguashi]}")
	jg_deny(ME.VIEW_ACTION,stand,"jinguashi",ME.ALREADY_SEEN,"A views the lantern again",false)
	jg_check(ME.own(world.state,tok)=={"seen":["lanyang","jinguashi"],"first_share_done":true,"plaque_claimed":true,"sorting_done":true,"lantern_claimed":true,"comparison_done":true,"teaware_claimed":false,"raking_done":true,"basket_claimed":false},"own block for A")

## Late joiner B: never sorted with Bobo.
func jg_late_b() -> void:
	var stand:=ME.stand_cell(world.state)
	jg_check(not world.state.players.has(JG_B),"B not in the save yet")
	world.add_player(JG_B,JG_B_NAME)
	var a_bytes:=canon_bytes(world.state.players[TOKEN_A])
	var rec_bytes:=canon_bytes(world.state[JG.STATE_KEY])
	tok=JG_B
	jg_check(world.player_region(tok)=="home" and not person().has(ME.RECORD_KEY) and not JG.player_ready(world.state,tok),"B joined at home, no exhibit record, no Bobo sort")
	walk_to(stand)
	var s:=world.state
	jg_check(ME.personal_hint_for(s,"jinguashi",tok)==ME.HINT_JG_NOT_READY,"B sees the 補做 hint")
	var row:=ME.exhibit(s,"jinguashi",tok)
	jg_check(row.on_display==true and row.unread==true and row.lines.size()==7,"B sees the lantern on display, unread")
	ex_view_ok(stand,"jinguashi","B views the lantern")
	if failed:return
	jg_check(ME.personal(world.state,tok).seen==["jinguashi"] and str(ME.personal(world.state,tok).lantern_hint)==ME.HINT_JG_NOT_READY,"B seen [jinguashi], hint still NOT_READY")
	jg_ride()
	if failed:return
	var table:=JG.sort_cell(world.state)
	jg_deny(JG.CLAIM_ACTION,table,"",JG.NOT_READY,"B claims the lantern without a Bobo sort")
	jg_deny(JG.SORT_ACTION,table,JG.sort_extra("bobo","stone"),JG.NOT_READY,"B sorts without a Bobo sort",false)
	jg_check(canon_bytes(world.state.players[TOKEN_A])==a_bytes,"A's whole player record byte-identical through B's leg")
	jg_check(canon_bytes(world.state[JG.STATE_KEY])==rec_bytes and not JG.claimed_own(world.state,tok),"revisit record byte-identical; B has no lantern")
	tok=TOKEN_A
	ex_reload("after the late joiner")
	if failed:return
	tok=JG_B
	jg_deny(JG.CLAIM_ACTION,table,"",JG.NOT_READY,"B claims after the final reload")
	tok=TOKEN_A
	jg_check(JG.claimed_own(world.state,TOKEN_A) and not JG.claimed_own(world.state,JG_B),"final: only A claimed")

# ---------------------------------------------------------------- report

func finish() -> void:
	if jg_started:
		print("JG_REVISIT_JOURNEY info=%s"%JSON.stringify(jg_info))
		print("JG_REVISIT_JOURNEY strikes=%s mined=%s"%[JSON.stringify(jg_strikes),JSON.stringify(jg_mined)])
		for i in jg_refusals.size():print("JG_REVISIT_JOURNEY refusal %d %s"%[i+1,jg_refusals[i]])
		var t:=float(world.state.get("time",0.0))
		print("JG_REVISIT_JOURNEY stats actions_total=%d walk_tiles_total=%d world_seconds_total=%.1f segment_actions=%d segment_walk_tiles=%d segment_world_seconds=%.1f refusals=%d all_refusals_state_unchanged=%s segment_checks=%d segment_ms=%d passed=%s"%[actions,walking,t,actions-jg_actions_start,walking-jg_walk_start,t-jg_time_start,jg_refusals.size(),str(jg_changed==0),checks-jg_checks_start,Time.get_ticks_msec()-jg_ms,str(not failed)])
	else:
		print("JG_REVISIT_JOURNEY did not reach the revisit segment (refusals so far %d)"%jg_refusals.size())
	super.finish()

# ---------------------------------------------------------------- helpers

func jg_check(condition:bool,message:String) -> bool:
	return expect(condition,"JG_REVISIT_JOURNEY: "+message)

func jg_dist(cell:Vector2i) -> float:
	return Vector2(person().x,person().y).distance_to(Vector2(cell)+Vector2(0.5,0.5))

func jg_held(items:Array=["gold_ore","copper_ore","stone"]) -> Dictionary:
	var out:={}
	for item in items:out[item]=int(bag().get(item,0))
	return out

## Refused with the exact message (any message when any_message); whole World.state
## unchanged (== and sorted bytes).
func jg_deny(action:String,target:Vector2i,extra:String,message:String,label:String,walk:=true,any_message:=false) -> void:
	if failed:return
	if walk:walk_to(target)
	if failed:return
	actions+=1
	var state_before:=world.state.duplicate(true)
	var bytes_before:=canon_bytes(world.state)
	var result:=world.act(tok,"jg-journey-%d"%actions,action,target,extra)
	jg_check(not result.ok and (any_message or str(result.message)==message),"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var unchanged:=world.state==state_before and canon_bytes(world.state)==bytes_before
	jg_check(unchanged,label+": whole world state unchanged")
	if not unchanged:jg_changed+=1
	jg_refusals.append("%s | %s %s %s | %s | state_unchanged=%s"%[label,action,str(target),extra,str(result.message),str(unchanged)])

## A successful action with the exact message; the whole canonical state may differ
## only under `allowed` (plus the actor's receipts and the commit counter).
func jg_ok(action:String,target:Vector2i,extra:String,message:String,label:String,allowed:Array) -> String:
	if failed:return ""
	walk_to(target)
	if failed:return ""
	actions+=1
	var rid:="jg-journey-%d"%actions
	var before:Variant=ex_canon(world.state)
	var result:=world.act(tok,rid,action,target,extra)
	jg_check(result.ok==true and str(result.message)==message,"%s: ok '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var diffs:=[]
	ex_all_diffs(before,ex_canon(world.state),"state",diffs)
	var prefixes:=allowed.duplicate()
	prefixes.append("state.players.%s.receipts"%tok)
	prefixes.append("state.committed")
	prefixes.append("state.ledger")
	var other:=[]
	for row in diffs:
		var ok:=false
		for prefix:String in prefixes:
			if str(row.path)==prefix or str(row.path).begins_with(prefix+"."):ok=true
		if not ok:other.append(row)
	jg_check(other.is_empty() and not diffs.is_empty(),"%s: whole-state diff only under %s (other %s)"%[label,str(allowed),JSON.stringify(other.slice(0,5))])
	return rid
