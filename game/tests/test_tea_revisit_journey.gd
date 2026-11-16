extends "res://tests/test_jinguashi_revisit_journey.gd"
## Chapter 40「貓空與鶯歌回訪・茶罐大單」+ 茶陶組 natural journey: a FRESH temp world,
## ONE player (A) for the whole journey (plus the late joiners the parents add) and
## one more late joiner B at the end, ONE process (reloads are in-process
## World.new().load_world on the same save; the journey continues in the reloaded World).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
##
## Prerequisite reuse (disclosed): this file EXTENDS the unmodified
## test_jinguashi_revisit_journey.gd (-> memory exhibit -> festival earned -> salt pan
## -> flower journeys). That chain earns chapter one, A's tea comparison (tea_intro,
## potter, kiln, a light:jar delivery and its reclaimed jar, a deep:fiber delivery,
## tea_discuss), the real 風鈴節 opening, the 分水木牌 and 礦燈 exhibits. It never
## touches state.tea_revisit. The extra jars, the jar delivery cycles, the roasted teas
## and the whole revisit are RE-DERIVED here from test_tea_ceramics_journey.gd.
##
## Hooks: chapter_one() (fresh world: A at home, the four tea_revisit actions answer
## WRONG_REGION, the pure blocks say NOT_READY) and act() (right before A's own first
## tea_discuss in 貓空: the comparison is not complete yet, fill/send answer NOT_READY
## at the packing table, jar/claim answer WRONG_REGION_YINGGE).
##
## Everything goes through World.act after World.move_player along BFS routes, and
## World.step (inherited wait()) for waits. NO direct writes by this file to
## inventory, coins, flags, tea / revisit / exhibit records, objects, positions or
## time. B joins with World.add_player (the Session join path).
## Prints TEA_REVISIT_JOURNEY lines before the parents' summary lines.

const TR=preload("res://scripts/tea_revisit.gd")
const TR_B:="tea-revisit-late-b"
const TR_B_NAME:="Teaware Late"
## Independent copy of the season order table from the rules report.
const TR_ORDER_TABLE:={
	"spring":{"light":4,"deep":2},
	"summer":{"light":5,"deep":1},
	"autumn":{"light":2,"deep":4},
	"winter":{"light":1,"deep":5},
}
const TR_NEW_JARS:=5
const TR_WARE_SPOTS:=[Vector2i(34,36),Vector2i(36,36),Vector2i(34,37),Vector2i(33,36),Vector2i(37,37),Vector2i(33,37),Vector2i(37,36)]

var tr_fresh_done:=false
var tr_pre_done:=false
var tr_started:=false
var tr_ms:=0
var tr_actions_start:=0
var tr_walk_start:=0
var tr_time_start:=0.0
var tr_checks_start:=0
var tr_reloads_start:=0
var tr_refusals:=[]
var tr_changed:=0
var tr_cycles:=0
var tr_info:={}
## Conceptual jar identities: R1 is the jar A fired and reclaimed in the parent chain;
## J1..J5 are fired here. Each entry: {"id","origin","trips":[...],"handed":...}.
var tr_jars:={}
var tr_jar_order:=[]

# ---------------------------------------------------------------- hooks

func chapter_one() -> void:
	if not tr_fresh_done:
		tr_fresh_done=true
		tr_fresh()
	super.chapter_one()

func act(action:String,target:Vector2i,extra:String="") -> Dictionary:
	if action=="tea_discuss" and tok==TOKEN_A and not tr_pre_done and not failed and world.state.players.has(TOKEN_A):
		var rec:=Tea.own_record(world.state,TOKEN_A)
		if not rec.comparison_complete and Tea.comparison_ready(rec):
			tr_pre_done=true
			tr_pre_comparison()
	return super.act(action,target,extra)

## Fresh world: A at home, no comparison.
func tr_fresh() -> void:
	var s:=world.state
	tr_check(world.player_region(tok)=="home" and not TR.player_ready(s,tok) and not s.has(TR.STATE_KEY),"fresh world: A at home, not ready, no record")
	tr_blocks_all(TR.NOT_READY,"fresh world")
	tr_check(ME.personal_hint_for(s,"tea_pottery",tok)==ME.HINT_TEA_NOT_DONE_NOT_READY and not ME.available(s,"tea_pottery"),"fresh world: teaware hint NOT_DONE_NOT_READY, no exhibit")
	tr_deny(TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.WRONG_REGION_YINGGE,"fresh world jar (at home)",false)
	tr_deny(TR.FILL_ACTION,TR.PACKER,"light",TR.WRONG_REGION_MAOKONG,"fresh world fill (at home)",false)
	tr_deny(TR.SEND_ACTION,TR.PACKER,"",TR.WRONG_REGION_MAOKONG,"fresh world send (at home)",false)
	tr_deny(TR.CLAIM_ACTION,TR.POTTER,"",TR.WRONG_REGION_YINGGE,"fresh world claim (at home)",false)

## In 貓空, both deliveries and the reclaim done, right before A's own tea_discuss.
func tr_pre_comparison() -> void:
	var s:=world.state
	var rec:=Tea.own_record(s,tok)
	tr_check(world.player_region(tok)==Tea.MAOKONG and rec.trials.jar==true and rec.trials.fiber==true and rec.reused==true and not rec.comparison_complete,"pre-comparison: A in 貓空, both trials and a reclaim done, comparison not complete")
	tr_check(int(bag().get("tea_returned_jar",0))==1,"pre-comparison: A holds the reclaimed tea_returned_jar")
	tr_blocks_all(TR.NOT_READY,"pre-comparison")
	tr_check(ME.personal_hint_for(s,"tea_pottery",tok)==ME.HINT_TEA_NOT_DONE_NOT_READY,"pre-comparison: hint NOT_DONE_NOT_READY")
	tr_deny(TR.FILL_ACTION,TR.PACKER,"light",TR.NOT_READY,"pre-comparison fill at the packer",true,true)
	tr_deny(TR.SEND_ACTION,TR.PACKER,"",TR.NOT_READY,"pre-comparison send at the packer",false,true)
	tr_deny(TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.WRONG_REGION_YINGGE,"pre-comparison jar (in 貓空)",false)
	tr_deny(TR.CLAIM_ACTION,TR.POTTER,"",TR.WRONG_REGION_YINGGE,"pre-comparison claim (in 貓空)",false)
	tr_check(not world.state.has(TR.STATE_KEY),"pre-comparison: no record written")

func tr_blocks_all(want:String,label:String) -> void:
	var s:=world.state
	var inv:Dictionary=bag()
	tr_check(TR.jar_block(s,"tea_returned_jar",inv,tok)==want and TR.jar_block(s,"tea_worn_jar",inv,tok)==want and TR.fill_block(s,"light",inv,tok)==want and TR.fill_block(s,"deep",inv,tok)==want and TR.send_block(s,tok)==want and TR.claim_block(s,inv,tok)==want and not TR.can_claim(s,inv,tok),"%s: jar/fill/send/claim blocks all '%s'"%[label,want])

# ---------------------------------------------------------------- journey

func run() -> void:
	super.run()
	if failed:return
	tr_check(tr_fresh_done and tr_pre_done,"fresh-world and pre-comparison hooks ran")
	tr_started=true
	tr_ms=Time.get_ticks_msec()
	tr_actions_start=actions
	tr_walk_start=walking
	tr_time_start=now()
	tr_checks_start=checks
	tr_reloads_start=ex_reloads
	tok=TOKEN_A
	tr_info.start={"day":TR.today(world.state),"season":TR.order_season(world.state),"world_seconds":now(),"held":tr_held(),"region":world.player_region(tok)}
	print("TEA_REVISIT_JOURNEY prerequisite chain passed (checks %d, actions %d, world_seconds %.1f, day %d %s, A holds %s)"%[checks,actions,now(),TR.today(world.state),TR.order_season(world.state),JSON.stringify(tr_held())])
	tr_start()
	if not failed:tr_fire_jars()
	if not failed:tr_first_maokong()
	if not failed:tr_jar_cycles()
	if not failed:tr_fill_and_send()
	if not failed:tr_claim_and_reload()
	if not failed:tr_teaware_home()
	if not failed:tr_exhibit()
	if not failed:tr_late_b()

## A at home after the parents: ready, no record; refusals that do not need travel.
func tr_start() -> void:
	var s:=world.state
	var rec:=Tea.own_record(s,tok)
	tr_check(world.player_region(tok)=="home" and TR.player_ready(s,tok) and not s.has(TR.STATE_KEY),"start: A at home, comparison complete, no revisit record")
	tr_check(rec.potter==true and rec.packed.is_empty() and rec.outbound.is_empty() and rec.returning.is_empty() and rec.kiln.is_empty() and rec.roast.is_empty() and rec.auto==false and int(rec.empties)==0,"start: A's tea record idle (no packed/outbound/returning/kiln/roast, auto off)")
	var jars:={}
	for item in ["tea_jar","tea_returned_jar","tea_worn_jar","tea_spent_jar"]:jars[item]=int(bag().get(item,0))
	tr_info.start_jars=jars
	if not tr_check(jars=={"tea_jar":0,"tea_returned_jar":1,"tea_worn_jar":0,"tea_spent_jar":0},"start: A holds exactly the one reclaimed jar from the comparison %s"%JSON.stringify(jars)):return
	tr_jars["R1"]={"id":"R1","origin":"fired in 鶯歌 and reclaimed once in the parent chain's light:jar delivery","trips":[],"handed":""}
	tr_jar_order.append("R1")
	tr_check(ME.on_display_ids(s)==["lanyang","jinguashi"] and not ME.available(s,"tea_pottery") and ME.personal_hint_for(s,"tea_pottery",tok)==ME.HINT_TEA_NOT_DONE,"start: two exhibits on display, teaware hint NOT_DONE")
	tr_check(TR.jar_block(s,"tea_returned_jar",bag(),tok)=="" and TR.jar_block(s,"tea_worn_jar",bag(),tok)==TR.NO_JAR%"磨損陶罐" and TR.jar_block(s,"tea_jar",bag(),tok)==TR.NEW_JAR,"start: jar blocks (returned ok, worn NO_JAR, new NEW_JAR)")
	tr_check(TR.fill_block(s,"light",bag(),tok)==TR.NEED_JARS%[0,0] and TR.send_block(s,tok)==TR.NOT_FILLED%0 and TR.claim_block(s,bag(),tok)==TR.NOT_DONE,"start: fill NEED_JARS 0/0, send NOT_FILLED 0, claim NOT_DONE")
	var stand:=ME.stand_cell(s)
	tr_deny(ME.VIEW_ACTION,stand,"tea_pottery",ME.NOT_ON_DISPLAY,"view the tea pottery before the revisit")
	tr_deny(TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.WRONG_REGION_YINGGE,"jar at home (ready)",false)
	tr_deny(TR.CLAIM_ACTION,TR.POTTER,"",TR.WRONG_REGION_YINGGE,"claim at home (ready)",false)
	tr_deny(TR.FILL_ACTION,TR.PACKER,"light",TR.WRONG_REGION_MAOKONG,"fill at home (ready)",false)
	tr_deny(TR.SEND_ACTION,TR.PACKER,"",TR.WRONG_REGION_MAOKONG,"send at home (ready)",false)

## Home: stone for the clay; 鶯歌: clay, five new jars at the kiln, refusals.
func tr_fire_jars() -> void:
	var clay_need:=maxi(0,TR_NEW_JARS*2-int(bag().get("clay",0)))
	var stone_need:=clay_need*2
	var before:=tr_held(["stone","clay"])
	var a0:=actions
	var t0:=now()
	if int(bag().get("stone",0))<stone_need:gather({"stone":stone_need})
	if failed:return
	tr_info.stone={"before":before,"after_gather":tr_held(["stone","clay"]),"clay_needed":clay_need,"actions":actions-a0,"world_seconds":now()-t0}
	travel(FERRY,Tea.YINGGE)
	if failed:return
	tr_check(Vector2(person().x,person().y)==World.TRANSIT.STATIONS.yingge.arrival,"arrived at the 鶯歌 stop")
	tr_check(tr_dist(TR.POTTER)>TR.REACH,"at the arrival, %.2f tiles from the potter"%tr_dist(TR.POTTER))
	tr_deny(TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.TOO_FAR,"jar from the 鶯歌 arrival (too far)",false)
	tr_deny(TR.FILL_ACTION,TR.PACKER,"light",TR.WRONG_REGION_MAOKONG,"fill in 鶯歌",false)
	tr_deny(TR.SEND_ACTION,TR.PACKER,"",TR.WRONG_REGION_MAOKONG,"send in 鶯歌",false)
	walk_to(TR.POTTER)
	tr_deny(TR.JAR_ACTION,Tea.KILN,"tea_returned_jar",TR.WRONG_JAR_CELL,"jar at the kiln (wrong cell)",false)
	tr_deny(TR.CLAIM_ACTION,Tea.KILN,"",TR.WRONG_CLAIM_CELL,"claim at the kiln (wrong cell)",false)
	tr_deny(TR.JAR_ACTION,TR.POTTER,"tea_worn_jar",TR.NO_JAR%"磨損陶罐","hand in a worn jar with none in the bag",false,true)
	tr_deny(TR.JAR_ACTION,TR.POTTER,"stone",TR.BAD_JAR,"hand in stone",false,true)
	tr_deny(TR.CLAIM_ACTION,TR.POTTER,"",TR.NOT_DONE,"claim before completion",false,true)
	# Clay at the supply (2 stone each, 10 s cooldown), then five firings.
	var clay_actions:=0
	while not failed and int(bag().get("clay",0))<TR_NEW_JARS*2:
		var ready:=float(Tea.own_record(world.state,tok).clay_ready)
		if ready>now():wait(ready-now()+0.1)
		var b:=bag().duplicate(true)
		act("tea_clay",Tea.CLAY)
		if failed:return
		var e:=b.duplicate(true)
		e["stone"]=int(b.get("stone",0))-2
		e["clay"]=int(b.get("clay",0))+1
		expect_same(bag(),e,"TEA_REVISIT_JOURNEY: tea_clay: whole bag delta stone -2, clay +1")
		clay_actions+=1
	for n in TR_NEW_JARS:
		if failed:return
		var b:=bag().duplicate(true)
		act("tea_fire",Tea.KILN)
		wait(Tea.KILN_SECONDS+0.1)
		var r:=act("tea_fire_take",Tea.KILN)
		if failed:return
		var e:=b.duplicate(true)
		e["clay"]=int(b.get("clay",0))-2
		e["tea_jar"]=int(b.get("tea_jar",0))+1
		expect_same(bag(),e,"TEA_REVISIT_JOURNEY: firing %d: whole bag delta clay -2, tea_jar +1"%(n+1))
		tr_check(str(r.message)=="製成一只可回收陶罐。","firing %d message"%(n+1))
		var id:="J%d"%(n+1)
		tr_jars[id]={"id":id,"origin":"fired here at the 鶯歌 kiln on day %d"%TR.today(world.state),"trips":[],"handed":""}
		tr_jar_order.append(id)
	tr_info.fired={"clay_actions":clay_actions,"jars":TR_NEW_JARS,"held":tr_held(["tea_jar","tea_returned_jar","clay","stone"])}
	tr_check(int(bag().get("tea_jar",0))==TR_NEW_JARS and int(bag().get("tea_returned_jar",0))==1,"holding %d new jars and R1"%TR_NEW_JARS)
	tr_deny(TR.JAR_ACTION,TR.POTTER,"tea_jar",TR.NEW_JAR,"hand in a new tea_jar",false,true)
	tr_check(not world.state.has(TR.STATE_KEY),"no record after the 鶯歌 refusals")
	travel(World.TRANSIT.points(Tea.YINGGE).transfer.cell,Tea.MAOKONG)

## First 貓空 visit: refusals before any jar is handed in.
func tr_first_maokong() -> void:
	tr_check(tr_dist(TR.PACKER)>TR.REACH,"at the 貓空 arrival, %.2f tiles from the packer"%tr_dist(TR.PACKER))
	tr_deny(TR.FILL_ACTION,TR.PACKER,"light",TR.TOO_FAR,"fill from the 貓空 arrival (too far)",false)
	tr_deny(TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.WRONG_REGION_YINGGE,"jar in 貓空",false)
	tr_deny(TR.CLAIM_ACTION,TR.POTTER,"",TR.WRONG_REGION_YINGGE,"claim in 貓空",false)
	walk_to(TR.PACKER)
	tr_deny(TR.FILL_ACTION,Tea.ROASTER,"light",TR.WRONG_FILL_CELL,"fill at the roaster (wrong cell)",false)
	tr_deny(TR.SEND_ACTION,Tea.ROASTER,"",TR.WRONG_SEND_CELL,"send at the roaster (wrong cell)",false)
	tr_deny(TR.FILL_ACTION,TR.PACKER,"oolong",TR.BAD_STYLE,"fill an unknown style",false,true)
	var msg:=TR.NEED_JARS%[0,0]
	tr_check(msg=="從鶯歌檢查好送來的空罐有 0 只，已經裝了 0 罐；再帶回收空罐到鶯歌交給陶師。","NEED_JARS text")
	tr_deny(TR.FILL_ACTION,TR.PACKER,"light",msg,"fill before any jar is handed in",false,true)
	tr_deny(TR.SEND_ACTION,TR.PACKER,"",TR.NOT_FILLED%0,"send before anything is filled",false,true)
	tr_deny(TR.SEND_ACTION,TR.PACKER,"now",TR.BAD_EXTRA,"send with a non-empty extra",false)
	tr_check(not world.state.has(TR.STATE_KEY),"no record after the 貓空 refusals")

## Six jar delivery cycles (pack :jar -> ship -> sell -> return -> reclaim). Pack
## happens before the previous jar is reclaimed, and every reclaimed jar is handed to
## the potter before the next pack, so pack (which prefers worn > returned > new jars)
## takes R1 on the first cycle and a new jar afterwards.
func tr_jar_cycles() -> void:
	tr_info.cycles=[]
	tr_info.handins=[]
	var coins0:=int(person().coins)
	var in_flight:=""
	for k in range(1,TR_NEW_JARS+2):
		if failed:return
		tr_check(world.player_region(tok)==Tea.MAOKONG,"cycle %d starts in 貓空"%k)
		tr_brew("light")
		if failed:return
		var expect_item:="tea_returned_jar" if k==1 else "tea_jar"
		var jar_id:="R1" if k==1 else "J%d"%(k-1)
		tr_check(int(bag().get("tea_worn_jar",0))==0 and int(bag().get("tea_returned_jar",0))==(1 if k==1 else 0),"cycle %d: no other recycled jar in the bag before packing"%k)
		var b:=bag().duplicate(true)
		act("tea_pack",Tea.PACKER,"light:jar")
		if failed:return
		var e:=b.duplicate(true)
		e[expect_item]=int(b.get(expect_item,0))-1
		e["tea_light"]=int(b.get("tea_light",0))-1
		expect_same(bag(),e,"TEA_REVISIT_JOURNEY: cycle %d pack light:jar takes exactly %s -1, tea_light -1"%[k,expect_item])
		var packed:Dictionary=Tea.own_record(world.state,tok).packed
		var back:String=Tea.RETURN_ITEM[expect_item]
		tr_check(str(packed.return_item)==back and str(packed.wrap)=="jar","cycle %d: %s will come back as %s"%[k,jar_id,back])
		act("tea_ship",Tea.PACKER)
		var cycle:={"k":k,"jar":jar_id,"packed_as":expect_item,"returns_as":back,"ship_day":TR.today(world.state)}
		tr_jars[jar_id]["trips"].append("%s -> %s (cycle %d)"%[expect_item,back,k])
		if in_flight!="":tr_reclaim(in_flight)
		if failed:return
		travel(World.TRANSIT.points(Tea.MAOKONG).transfer.cell,"home")
		var out:=float(Tea.own_record(world.state,tok).outbound.ready)
		if out>now():wait(out-now()+0.1)
		var c:=int(person().coins)
		act("tea_sell",Tea.RECEIVER)
		tr_check(int(person().coins)==c+Tea.price_for("light","jar"),"cycle %d: sale pays %d"%[k,Tea.price_for("light","jar")])
		act("tea_return",Tea.RECEIVER)
		if failed:return
		var ret:Dictionary=Tea.own_record(world.state,tok).returning
		tr_check(int(ret.count)==1 and same_canon(ret.items,{back:1}),"cycle %d: return batch is exactly one %s"%[k,back])
		in_flight=jar_id
		cycle.sell_day=TR.today(world.state)
		tr_info.cycles.append(cycle)
		tr_cycles+=1
		if tr_recycled_held()>0:
			travel(FERRY,Tea.YINGGE)
			tr_hand_in_all()
			if failed:return
			if k<TR_NEW_JARS+1:travel(World.TRANSIT.points(Tea.YINGGE).transfer.cell,Tea.MAOKONG)
		elif k<TR_NEW_JARS+1:
			travel(FERRY,Tea.MAOKONG)
		if k==TR_NEW_JARS+1:
			if world.player_region(tok)!=Tea.MAOKONG:
				if world.player_region(tok)==Tea.YINGGE:travel(World.TRANSIT.points(Tea.YINGGE).transfer.cell,Tea.MAOKONG)
				else:travel(FERRY,Tea.MAOKONG)
	if failed:return
	# Last jar: reclaim in 貓空, ride to 鶯歌 and hand it in (6/6).
	tr_reclaim(in_flight)
	if failed:return
	travel(World.TRANSIT.points(Tea.MAOKONG).transfer.cell,Tea.YINGGE)
	tr_hand_in_all()
	if failed:return
	tr_info.coins_from_cycles=int(person().coins)-coins0
	var s:=world.state
	tr_check(TR.jars_total(s)==TR.TOTAL and same_canon(TR.jars(s),{"tea_returned_jar":5,"tea_worn_jar":1}),"potter holds 6 jars: returned 5, worn 1 %s"%JSON.stringify(TR.jars(s)))
	tr_check(TR.filled_total(s)==0 and int(TR.record(s).day)==0,"nothing filled yet; order day 0")
	tr_deny(TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.JARS_FULL,"a seventh jar (with none in the bag)",false,true)
	tr_check(TR.jar_block(s,"tea_worn_jar",{"tea_worn_jar":1},tok)==TR.JARS_FULL,"jar_block says JARS_FULL even with a jar in hand")
	tr_deny(TR.JAR_ACTION,TR.POTTER,"tea_jar",TR.NEW_JAR,"new jar after 6 collected (NEW_JAR precedes JARS_FULL)",false,true)
	var held:={}
	for item in ["tea_jar","tea_returned_jar","tea_worn_jar","tea_spent_jar"]:held[item]=int(bag().get(item,0))
	tr_info.jars_after_cycles=held
	tr_check(held=={"tea_jar":0,"tea_returned_jar":0,"tea_worn_jar":0,"tea_spent_jar":0},"every jar handed in; no spent jar ever produced %s"%JSON.stringify(held))

func tr_reclaim(jar_id:String) -> void:
	var ret:Dictionary=Tea.own_record(world.state,tok).returning
	if not tr_check(not ret.is_empty(),"a return batch is in flight for %s"%jar_id):return
	var ready:=float(ret.ready)
	if ready>now():wait(ready-now()+0.1)
	var b:=bag().duplicate(true)
	var items:Dictionary=ret.items
	var r:=act("tea_reclaim",Tea.PACKER)
	if failed:return
	var e:=b.duplicate(true)
	for item:String in items:e[item]=int(b.get(item,0))+int(items[item])
	expect_same(bag(),e,"TEA_REVISIT_JOURNEY: reclaim of %s: whole bag delta %s"%[jar_id,JSON.stringify(items)])
	tr_check(str(r.message)=="已取回空罐，可以再裝下一批茶。","reclaim message for %s"%jar_id)
	var item:String=str(items.keys()[0])
	tr_jars[jar_id]["reclaimed_as"]=item
	tr_jars[jar_id]["reclaim_day"]=TR.today(world.state)

func tr_recycled_held() -> int:
	return int(bag().get("tea_returned_jar",0))+int(bag().get("tea_worn_jar",0))

## At the 鶯歌 potter: hand in every recycled jar held (one per cycle here).
func tr_hand_in_all() -> void:
	for item:String in TR.JAR_ITEMS:
		while not failed and int(bag().get(item,0))>0:
			var jar_id:=""
			for id:String in tr_jar_order:
				if str(tr_jars[id].get("reclaimed_as",""))==item and str(tr_jars[id].get("handed",""))=="":
					jar_id=id
					break
			var n:=TR.jars_total(world.state)
			var b:=bag().duplicate(true)
			var want:=TR.JAR_OK%[str(TR.JAR_NAMES[item]),n+1]
			var rid:=tr_ok(TR.JAR_ACTION,TR.POTTER,item,want,"hand in %s (%s)"%[jar_id,item],["state.%s"%TR.STATE_KEY,"state.players.%s.inventory.%s"%[tok,item]])
			if failed:return
			var e:=b.duplicate(true)
			e[item]=int(b.get(item,0))-1
			expect_same(bag(),e,"TEA_REVISIT_JOURNEY: hand-in %s: whole bag delta exactly %s -1"%[jar_id,item])
			tr_check(TR.jars_total(world.state)==n+1 and TR.filled_total(world.state)==0 and int(TR.record(world.state).day)==0,"jars %d/6, nothing filled"%(n+1))
			if jar_id!="":
				tr_jars[jar_id]["handed"]="%s on day %d (%d/6)"%[item,TR.today(world.state),n+1]
			tr_info.handins.append({"jar":jar_id,"item":item,"day":TR.today(world.state),"n":n+1})
			if n==0:
				var bytes:=canon_bytes(world.state)
				var again:=world.act(tok,rid,TR.JAR_ACTION,TR.POTTER,item)
				tr_check(again.ok==true and str(again.message)==want and canon_bytes(world.state)==bytes,"resend of the first hand-in %s returns the stored receipt, nothing applied twice"%rid)
				tr_check(same_canon(TR.public(world.state),{"jars":{"tea_returned_jar":0 if item=="tea_worn_jar" else 1,"tea_worn_jar":1 if item=="tea_worn_jar" else 0},"filled":{"light":0,"deep":0},"day":0,"completed":false,"done_day":0}),"first record %s"%JSON.stringify(TR.public(world.state)))

## Pick (own harvest timers), roast, take one tea of `style`.
func tr_brew(style:String) -> void:
	if int(bag().get("tea_leaf",0))<2:
		var rec:=Tea.own_record(world.state,tok)
		var best:=0
		var best_ready:=INF
		for i in Tea.TEA_NODES.size():
			var r:=float(rec.harvest_ready.get(str(i),0.0))
			if r<best_ready:
				best_ready=r
				best=i
		if best_ready>now():wait(best_ready-now()+0.1)
		var leaves:=int(bag().get("tea_leaf",0))
		act("tea_pick",Tea.TEA_NODES[best])
		tr_check(int(bag().get("tea_leaf",0))==leaves+2,"pick gives 2 leaves")
	var b:=bag().duplicate(true)
	act("tea_roast",Tea.ROASTER,style)
	wait(float(Tea.ROAST_SECONDS[style])+0.1)
	act("tea_take",Tea.ROASTER)
	if failed:return
	var e:=b.duplicate(true)
	e["tea_leaf"]=int(b.get("tea_leaf",0))-2
	e["tea_"+style]=int(b.get("tea_"+style,0))+1
	expect_same(bag(),e,"TEA_REVISIT_JOURNEY: roast %s: whole bag delta tea_leaf -2, tea_%s +1"%[style,style])
	var brewed:Dictionary=tr_info.get("brewed",{})
	brewed[style]=int(brewed.get(style,0))+1
	tr_info.brewed=brewed

## 貓空: roast the season's mix, fill 6, send.
func tr_fill_and_send() -> void:
	travel(World.TRANSIT.points(Tea.YINGGE).transfer.cell,Tea.MAOKONG)
	if failed:return
	walk_to(TR.PACKER)
	tr_check(int(bag().get("tea_light",0))==0 and int(bag().get("tea_deep",0))==0,"no roasted tea in the bag before the order teas")
	tr_deny(TR.FILL_ACTION,TR.PACKER,"light",TR.NO_TEA%"淺焙茶","fill light with no tea",false,true)
	tr_deny(TR.FILL_ACTION,TR.PACKER,"deep",TR.NO_TEA%"深焙茶","fill deep with no tea",false,true)
	var s:=world.state
	var season:=TR.order_season(s)
	var order:=TR.order(s)
	tr_check(season==WEATHER.season_on_day(WEATHER.day_index(now())) and order==TR_ORDER_TABLE[season] and TR.order_for(season)==order,"%s order %s matches the copied table"%[season,JSON.stringify(order)])
	tr_check(TR.reason(s)==TR.reason_for(season) and not TR.reason(s).is_empty(),"reason set for %s"%season)
	var need_light:=int(order.light)
	var need_deep:=int(order.deep)
	for n in need_light:tr_brew("light")
	for n in need_deep:tr_brew("deep")
	if failed:return
	walk_to(TR.PACKER)
	s=world.state
	if not tr_check(TR.order_season(s)==season and TR.order(s)==order,"the season did not change while roasting (still %s)"%season):return
	tr_check(int(bag().get("tea_light",0))==need_light and int(bag().get("tea_deep",0))==need_deep,"holding exactly the order's teas: light %d deep %d"%[need_light,need_deep])
	tr_info.order={"day":TR.today(s),"season":season,"order":order,"world_seconds":now()}
	print("TEA_REVISIT_JOURNEY order day=%d season=%s order=%s held=%s"%[TR.today(s),season,JSON.stringify(order),JSON.stringify(tr_held())])
	# Fill the smaller quota first, then try it once more (QUOTA_FULL).
	var first:="deep" if need_deep<=need_light else "light"
	var other:="light" if first=="deep" else "deep"
	var fills:=[]
	for n in int(order[first]):fills.append(first)
	var quota_msg:=TR.QUOTA_FULL%[str(TR.STYLE_NAMES[first]),int(order[first]),int(order[first]),str(TR.STYLE_NAMES[other])]
	if season=="summer":tr_check(quota_msg=="這張單深焙只要 1 罐，已經裝了 1 罐；剩下的要淺焙。","QUOTA_FULL text (summer)")
	var done:={"light":0,"deep":0}
	var order_day:=0
	var step:=0
	var plan:=fills.duplicate()
	for n in int(order[other]):plan.append(other)
	for style:String in plan:
		if failed:return
		if step==int(order[first]):
			tr_deny(TR.FILL_ACTION,TR.PACKER,first,quota_msg,"fill %s beyond its quota"%first,false,true)
		if step==TR.TOTAL-1:
			tr_deny(TR.SEND_ACTION,TR.PACKER,"",TR.NOT_FILLED%5,"send with 5 filled",false,true)
		done[style]=int(done[style])+1
		step+=1
		var b:=bag().duplicate(true)
		var want:=TR.FILL_OK%[str(TR.TEA_NAMES[style]),step,int(done.light),int(done.deep)]
		var tea:String=TR.TEA_ITEMS[style]
		var rid:=tr_ok(TR.FILL_ACTION,TR.PACKER,style,want,"fill %d (%s)"%[step,style],["state.%s"%TR.STATE_KEY,"state.players.%s.inventory.%s"%[tok,tea]])
		if failed:return
		var e:=b.duplicate(true)
		e[tea]=int(b.get(tea,0))-1
		expect_same(bag(),e,"TEA_REVISIT_JOURNEY: fill %d: whole bag delta exactly %s -1"%[step,tea])
		if step==1:
			order_day=int(TR.record(world.state).day)
			tr_check(order_day==TR.today(world.state),"first fill stamps the order day %d"%order_day)
			var bytes:=canon_bytes(world.state)
			var again:=world.act(tok,rid,TR.FILL_ACTION,TR.PACKER,style)
			tr_check(again.ok==true and str(again.message)==want and canon_bytes(world.state)==bytes and TR.filled_total(world.state)==1,"resend of the first fill %s returns the stored receipt, nothing applied twice"%rid)
		tr_check(same_canon(TR.filled(world.state),done) and int(TR.record(world.state).day)==order_day,"filled %s, order day stays %d"%[JSON.stringify(done),order_day])
	tr_deny(TR.FILL_ACTION,TR.PACKER,"light",TR.ALL_FILLED,"fill a seventh jar",false,true)
	tr_check(TR.progress(world.state).ready_to_send==true and TR.send_block(world.state,tok)=="","ready to send")
	var rid2:=tr_ok(TR.SEND_ACTION,TR.PACKER,"",TR.COMPLETE_OK,"send the order",["state.%s"%TR.STATE_KEY])
	if failed:return
	var bytes2:=canon_bytes(world.state)
	var again2:=world.act(tok,rid2,TR.SEND_ACTION,TR.PACKER,"")
	tr_check(again2.ok==true and str(again2.message)==TR.COMPLETE_OK and canon_bytes(world.state)==bytes2,"resend of the send %s returns the stored receipt"%rid2)
	s=world.state
	var rec:=TR.record(s)
	tr_check(rec.completed==true and int(rec.done_day)==TR.today(s) and int(rec.day)==order_day and int(rec.done_day)>=int(rec.day) and (rec.claimed as Dictionary).is_empty(),"completed record %s"%JSON.stringify(TR.public(s)))
	tr_check(same_canon(TR.filled(s),order) and same_canon(TR.jars(s),{"tea_returned_jar":5,"tea_worn_jar":1}),"filled equals the order; jars returned 5 worn 1")
	tr_check(ME.available(s,"tea_pottery") and ME.on_display_ids(s)==["lanyang","jinguashi","tea_pottery"],"completion itself puts the tea pottery on the exhibit")
	tr_check(ME.personal_hint_for(s,"tea_pottery",tok)==ME.HINT_TEA_UNCLAIMED,"hint UNCLAIMED")
	tr_deny(TR.SEND_ACTION,TR.PACKER,"",TR.ALREADY_DONE,"send again (new request)",false,true)
	tr_deny(TR.FILL_ACTION,TR.PACKER,"light",TR.ALREADY_DONE,"fill after completion",false,true)
	var weather:="indoor" if WEATHER.is_indoor(TR.FILL_REGION) else WEATHER.outdoor_id(float(int(rec.done_day)-1))
	tr_info.revisit={"order_day":int(rec.day),"done_day":int(rec.done_day),"season":season,"order":order,"filled":TR.filled(s),"jars":TR.jars(s),"weather_done_day":weather,"world_seconds":now()}
	print("TEA_REVISIT_JOURNEY completed %s"%JSON.stringify(tr_info.revisit))

func tr_claim_and_reload() -> void:
	travel(World.TRANSIT.points(Tea.MAOKONG).transfer.cell,Tea.YINGGE)
	if failed:return
	tr_deny(TR.CLAIM_ACTION,TR.POTTER,"",TR.TOO_FAR,"claim from the 鶯歌 arrival (too far)",false)
	walk_to(TR.POTTER)
	tr_deny(TR.CLAIM_ACTION,TR.POTTER,"x",TR.BAD_EXTRA,"claim with a non-empty extra",false)
	var kits:=int(bag().get(TR.TEAWARE_ITEM,0))
	tr_check(kits==0,"no tea ware kit before claiming")
	var rid:=tr_ok(TR.CLAIM_ACTION,TR.POTTER,"",TR.CLAIM_OK,"claim the tea ware",["state.%s.claimed"%TR.STATE_KEY,"state.players.%s.inventory.%s"%[tok,TR.TEAWARE_ITEM]])
	if failed:return
	tr_check(int(bag().get(TR.TEAWARE_ITEM,0))==1 and TR.claimed_own(world.state,tok) and ME.personal_hint_for(world.state,"tea_pottery",tok)==ME.HINT_TEA_CLAIMED,"one tea ware kit; hint CLAIMED")
	var bytes:=canon_bytes(world.state)
	var again:=world.act(tok,rid,TR.CLAIM_ACTION,TR.POTTER,"")
	tr_check(again.ok==true and str(again.message)==TR.CLAIM_OK and canon_bytes(world.state)==bytes and int(bag().get(TR.TEAWARE_ITEM,0))==1,"resend of the claim %s: stored receipt, still one kit"%rid)
	tr_deny(TR.CLAIM_ACTION,TR.POTTER,"",TR.CLAIMED,"second claim (new request)",false,true)
	tr_deny(TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.ALREADY_DONE,"hand in a jar after completion",false,true)
	var rec:=canon_bytes(world.state[TR.STATE_KEY])
	ex_reload("after the tea ware claim (in 鶯歌)")
	if failed:return
	tr_check(canon_bytes(world.state[TR.STATE_KEY])==rec and typeof(world.state[TR.STATE_KEY].day)==TYPE_INT and typeof(world.state[TR.STATE_KEY].done_day)==TYPE_INT,"revisit record identical after reload (day/done_day int)")
	tr_check(world.player_region(tok)==Tea.YINGGE and int(bag().get(TR.TEAWARE_ITEM,0))==1,"A still in 鶯歌 with one kit after reload")
	tr_deny(TR.CLAIM_ACTION,TR.POTTER,"",TR.CLAIMED,"claim after the reload",true,true)

## Home: the tea ware is a keepsake, not currency; build / move / remove / build.
func tr_teaware_home() -> void:
	travel(World.TRANSIT.points(Tea.YINGGE).transfer.cell,"home")
	if failed:return
	var kit:=TR.TEAWARE_ITEM
	tr_check(not World.trade_items().has(kit) and World.NAMES.get(kit,"")==TR.TEAWARE_NAME,"tea ware kit excluded from trade items")
	tr_deny("sell",RECEIVER,kit,"這件商品尚未上架","小栗 refuses to buy the tea ware kit")
	tr_deny("ship",World.SHIPPING.cell_for(world.state),JSON.stringify([[[kit,1]],10]),"出貨項目重複或無法出售。","shipping bin refuses the tea ware kit")
	tr_deny("market_stock",World.MARKET.cell_for(world.state),kit+":1","%s不能擺上市集攤位；攤位只收農漁產、料理和花。"%TR.TEAWARE_NAME,"market stall refuses the tea ware kit")
	var spot:=Vector2i(-1,-1)
	for tile:Vector2i in TR_WARE_SPOTS:
		if ex_free(tile):
			spot=tile
			break
	if spot==Vector2i(-1,-1):spot=open_cell()
	if not tr_check(spot!=Vector2i(-1,-1),"free home cell for the tea ware %s"%str(spot)):return
	var before:=bag().duplicate(true)
	act("build",spot,TR.TEAWARE_KIND)
	if failed:return
	tr_check(int(bag().get(kit,0))==int(before.get(kit,0))-1,"build debits the kit")
	tr_check(same_canon(world.state.objects.get(World.key(spot),{}),{"type":TR.TEAWARE_KIND,"owner":tok,"items":{}}) and not world.blocked(spot),"茶陶組 placed at %s, walk-through"%str(spot))
	tr_deny("build",spot+Vector2i(0,1),TR.TEAWARE_KIND,"材料不足，需要%s 1"%TR.TEAWARE_NAME,"second tea ware without a kit",false)
	var dest:=Vector2i(-1,-1)
	for off:Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1)]:
		var c:=spot+off
		if ex_free(c) and tr_dist(c)<=3.0:
			dest=c
			break
	if not tr_check(dest!=Vector2i(-1,-1),"free cell beside the tea ware within reach"):return
	act("move_object",spot,"%d,%d"%[dest.x,dest.y])
	if failed:return
	tr_check(world.state.objects.has(World.key(dest)) and not world.state.objects.has(World.key(spot)) and str(world.state.objects[World.key(dest)].type)==TR.TEAWARE_KIND,"tea ware moved %s -> %s"%[str(spot),str(dest)])
	act("remove",dest)
	if failed:return
	tr_check(int(bag().get(kit,0))==1 and not world.state.objects.has(World.key(dest)),"remove returns the kit")
	act("build",spot,TR.TEAWARE_KIND)
	if failed:return
	tr_check(int(bag().get(kit,0))==0 and str(world.state.objects.get(World.key(spot),{}).get("type",""))==TR.TEAWARE_KIND,"tea ware placed again at %s"%str(spot))
	tr_info.teaware=[spot.x,spot.y]
	tr_info.teaware_moved_to=[dest.x,dest.y]
	ex_reload("after placing the tea ware at home")
	if failed:return
	tr_check(same_canon(world.state.objects.get(World.key(spot),{}),{"type":TR.TEAWARE_KIND,"owner":tok,"items":{}}),"tea ware persists after reload")

## The exhibit at the festival plaza (the festival opening was earned by the parents).
func tr_exhibit() -> void:
	var s:=world.state
	tr_check(s.get("festival_story_open")==true,"festival opened by the earned parent steps")
	var stand:=ME.stand_cell(s)
	walk_to(stand)
	s=world.state
	var rv:Dictionary=tr_info.revisit
	var row:=ME.exhibit(s,"tea_pottery",tok)
	tr_check(row.on_display==true and row.unread==true and row.seen==false and str(row.source)==TR.TEAWARE_SOURCE and str(row.project)==TR.TEAWARE_PROJECT and str(row.blurb)==TR.TEAWARE_BLURB and str(row.disclaimer)==TR.DISCLAIMER,"陶器 slot on display and unread %s"%JSON.stringify(row))
	var recap:=ME.recap_for(s,"tea_pottery")
	var returned:=0
	var worn:=0
	for h:Dictionary in tr_info.handins:
		if str(h.item)=="tea_returned_jar":returned+=1
		else:worn+=1
	tr_check(returned==5 and worn==1,"hand-in log: returned %d worn %d"%[returned,worn])
	tr_check(int(recap.day)==int(rv.done_day) and int(recap.order_day)==int(rv.order_day) and str(recap.season)==str(rv.season) and same_canon(recap.order,rv.order) and int(recap.returned)==returned and int(recap.worn)==worn and int(recap.light)==int(rv.order.light) and int(recap.deep)==int(rv.order.deep) and str(recap.weather)==str(rv.weather_done_day),"recap matches what happened %s"%JSON.stringify(recap))
	tr_check(str(recap.reason)==TR.reason_for(str(rv.season)) and str(recap.weather_label)==str(WEATHER.LABELS[str(rv.weather_done_day)]) and str(recap.season_label)==str(WEATHER.SEASON_LABELS[str(rv.season)])+"季","recap reason / labels")
	var lines:Array=row.lines
	var want:=[TR.TEAWARE_BLURB,TR.TEAWARE_SOURCE,TR.TEAWARE_PROJECT,
		"完成那天：第 %d 日・貓空%s"%[int(rv.done_day),str(WEATHER.LABELS[str(rv.weather_done_day)])],
		"%s季的訂單：淺焙 %d 罐／深焙 %d 罐"%[str(WEATHER.SEASON_LABELS[str(rv.season)]),int(rv.order.light),int(rv.order.deep)],
		"回收的空罐：回收陶罐 %d 只、磨損陶罐 %d 只"%[returned,worn],
		TR.DISCLAIMER]
	tr_check(lines==want,"exhibit lines %s"%JSON.stringify(lines))
	var pages:=ME.recap_pages("tea_pottery",s)
	tr_check(pages.size()==4 and str(pages[2].lines[2])=="展台沒有記錄是誰交罐、誰裝茶、誰寄出。" and str(pages[1].lines[0])=="第 %d 日裝下第一罐，照的是%s季的訂單。"%[int(rv.order_day),str(WEATHER.SEASON_LABELS[str(rv.season)])] and str(pages[3].lines[-1])==TR.DISCLAIMER,"4 recap pages %s"%JSON.stringify(pages).left(400))
	tr_check(ME.view_block(s,"tea_pottery",tok)=="","view allowed")
	var me:=ME.personal(s,tok)
	tr_check(me.seen==["lanyang","jinguashi"] and int(me.unread)==1 and me.comparison_done==true and me.teaware_claimed==true and str(me.teaware_hint)==ME.HINT_TEA_CLAIMED,"A personal before viewing %s"%JSON.stringify(me))
	ex_view_ok(stand,"tea_pottery","A views the tea pottery")
	if failed:return
	tr_check(same_canon(person().get(ME.RECORD_KEY),{"seen":["lanyang","jinguashi","tea_pottery"]}),"A's record {seen:[lanyang, jinguashi, tea_pottery]}")
	tr_deny(ME.VIEW_ACTION,stand,"tea_pottery",ME.ALREADY_SEEN,"A views the tea pottery again",false)
	tr_check(ME.own(world.state,tok)=={"seen":["lanyang","jinguashi","tea_pottery"],"first_share_done":true,"plaque_claimed":true,"sorting_done":true,"lantern_claimed":true,"comparison_done":true,"teaware_claimed":true,"raking_done":true,"basket_claimed":false},"own block for A")
	tr_check(int(ME.personal(world.state,tok).unread)==0,"A has nothing unread")

## Late joiner B: never did the tea comparison.
func tr_late_b() -> void:
	var stand:=ME.stand_cell(world.state)
	tr_check(not world.state.players.has(TR_B),"B not in the save yet")
	world.add_player(TR_B,TR_B_NAME)
	var a_bytes:=canon_bytes(world.state.players[TOKEN_A])
	var rec_bytes:=canon_bytes(world.state[TR.STATE_KEY])
	tok=TR_B
	tr_check(world.player_region(tok)=="home" and not person().has(ME.RECORD_KEY) and not TR.player_ready(world.state,tok) and not (world.state.tea_ceramics.players as Dictionary).has(tok),"B joined at home, no exhibit or tea record")
	walk_to(stand)
	var s:=world.state
	tr_check(ME.personal_hint_for(s,"tea_pottery",tok)==ME.HINT_TEA_NOT_READY,"B sees the 補做 hint")
	tr_blocks_all(TR.NOT_READY,"B")
	var row:=ME.exhibit(s,"tea_pottery",tok)
	tr_check(row.on_display==true and row.unread==true and row.lines.size()==7 and ME.recap_pages("tea_pottery",s).size()==4,"B sees the tea pottery on display, unread, 4 pages")
	ex_view_ok(stand,"tea_pottery","B views the tea pottery")
	if failed:return
	var me:=ME.personal(world.state,tok)
	tr_check(me.seen==["tea_pottery"] and str(me.teaware_hint)==ME.HINT_TEA_NOT_READY and me.comparison_done==false and me.teaware_claimed==false,"B seen [tea_pottery], hint still NOT_READY %s"%JSON.stringify(me))
	travel(FERRY,"toucheng")
	travel(World.TRANSIT.points("toucheng").rail.cell,"ruifang")
	travel(World.TRANSIT.points("ruifang").rail.cell,Tea.MAOKONG)
	if failed:return
	tr_deny(TR.FILL_ACTION,TR.PACKER,"light",TR.NOT_READY,"B fills without the comparison",true,true)
	tr_deny(TR.SEND_ACTION,TR.PACKER,"",TR.NOT_READY,"B sends without the comparison",false,true)
	travel(World.TRANSIT.points(Tea.MAOKONG).transfer.cell,Tea.YINGGE)
	if failed:return
	tr_deny(TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.NOT_READY,"B hands in a jar without the comparison",true,true)
	tr_deny(TR.CLAIM_ACTION,TR.POTTER,"",TR.NOT_READY,"B claims the tea ware without the comparison",false,true)
	tr_check(canon_bytes(world.state.players[TOKEN_A])==a_bytes,"A's whole player record byte-identical through B's leg")
	tr_check(canon_bytes(world.state[TR.STATE_KEY])==rec_bytes and not TR.claimed_own(world.state,tok),"revisit record byte-identical; B has no tea ware")
	tok=TOKEN_A
	ex_reload("after the tea late joiner")
	if failed:return
	tok=TR_B
	tr_deny(TR.CLAIM_ACTION,TR.POTTER,"",TR.NOT_READY,"B claims after the final reload",false,true)
	tok=TOKEN_A
	tr_check(TR.claimed_own(world.state,TOKEN_A) and not TR.claimed_own(world.state,TR_B) and (world.state[TR.STATE_KEY].claimed as Dictionary).size()==1,"final: only A claimed")

# ---------------------------------------------------------------- report

func finish() -> void:
	if tr_started:
		print("TEA_REVISIT_JOURNEY info=%s"%JSON.stringify(tr_info))
		for id:String in tr_jar_order:print("TEA_REVISIT_JOURNEY jar %s"%JSON.stringify(tr_jars[id]))
		for i in tr_refusals.size():print("TEA_REVISIT_JOURNEY refusal %d %s"%[i+1,tr_refusals[i]])
		var t:=float(world.state.get("time",0.0))
		print("TEA_REVISIT_JOURNEY stats actions_total=%d walk_tiles_total=%d world_seconds_total=%.1f segment_actions=%d segment_walk_tiles=%d segment_world_seconds=%.1f refusals=%d all_refusals_state_unchanged=%s jar_cycles=%d segment_reloads=%d segment_checks=%d segment_ms=%d passed=%s"%[actions,walking,t,actions-tr_actions_start,walking-tr_walk_start,t-tr_time_start,tr_refusals.size(),str(tr_changed==0),tr_cycles,ex_reloads-tr_reloads_start,checks-tr_checks_start,Time.get_ticks_msec()-tr_ms,str(not failed)])
	else:
		print("TEA_REVISIT_JOURNEY did not reach the revisit segment (refusals so far %d, fresh=%s pre=%s)"%[tr_refusals.size(),str(tr_fresh_done),str(tr_pre_done)])
	super.finish()

# ---------------------------------------------------------------- helpers

func tr_check(condition:bool,message:String) -> bool:
	return expect(condition,"TEA_REVISIT_JOURNEY: "+message)

func tr_dist(cell:Vector2i) -> float:
	return Vector2(person().x,person().y).distance_to(Vector2(cell)+Vector2(0.5,0.5))

func tr_held(items:Array=["tea_jar","tea_returned_jar","tea_worn_jar","tea_spent_jar","tea_leaf","tea_light","tea_deep","clay","stone","tea_ware_kit"]) -> Dictionary:
	var out:={}
	for item in items:out[item]=int(bag().get(item,0))
	return out

## Refused with the exact message; whole World.state unchanged (== and sorted bytes).
## pure: the position-independent *_block function for this action must say the same.
func tr_deny(action:String,target:Vector2i,extra:String,message:String,label:String,walk:=true,pure:=false) -> void:
	if failed:return
	if walk:walk_to(target)
	if failed:return
	if pure:
		var s:=world.state
		var block:="?"
		if action==TR.JAR_ACTION:block=TR.jar_block(s,extra,bag(),tok)
		elif action==TR.FILL_ACTION:block=TR.fill_block(s,extra,bag(),tok)
		elif action==TR.SEND_ACTION:block=TR.send_block(s,tok)
		elif action==TR.CLAIM_ACTION:block=TR.claim_block(s,bag(),tok)
		tr_check(block==message,"%s: pure block agrees '%s' (got '%s')"%[label,message,block])
	actions+=1
	var state_before:=world.state.duplicate(true)
	var bytes_before:=canon_bytes(world.state)
	var result:=world.act(tok,"tr-journey-%d"%actions,action,target,extra)
	tr_check(not result.ok and str(result.message)==message,"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var unchanged:=world.state==state_before and canon_bytes(world.state)==bytes_before
	tr_check(unchanged,label+": whole world state unchanged")
	if not unchanged:tr_changed+=1
	tr_refusals.append("%s | %s %s %s | %s | state_unchanged=%s"%[label,action,str(target),extra,str(result.message),str(unchanged)])

## A successful action with the exact message; the whole canonical state may differ
## only under `allowed` (plus the actor's receipts and the commit counter).
func tr_ok(action:String,target:Vector2i,extra:String,message:String,label:String,allowed:Array) -> String:
	if failed:return ""
	walk_to(target)
	if failed:return ""
	actions+=1
	var rid:="tr-journey-%d"%actions
	var before:Variant=ex_canon(world.state)
	var result:=world.act(tok,rid,action,target,extra)
	tr_check(result.ok==true and str(result.message)==message,"%s: ok '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
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
	tr_check(other.is_empty() and not diffs.is_empty(),"%s: whole-state diff only under %s (other %s)"%[label,str(allowed),JSON.stringify(other.slice(0,5))])
	return rid
