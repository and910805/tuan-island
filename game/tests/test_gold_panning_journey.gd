extends "res://tests/test_history_journey.gd"
## Chapter 40 金瓜石初訪「河邊淘砂金」(gold_panning.gd) natural journey: a FRESH temp world,
## ONE process, same machine (reloads are in-process World.new().load_world on the same
## save file; after each reload the journey continues in the reloaded World). This is
## single-process, same-machine program evidence, NOT a networked or multi-machine run.
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
## Time is fast-forwarded with World.step(dt,true) in 120 s chunks to the next world day
## (WEATHER.DAY_SECONDS calendar); walking and transit cost no world time.
##
## Prerequisite reuse (disclosed): this file EXTENDS the unmodified
## test_history_journey.gd (-> garden -> regions -> chapter journeys), the same parent
## as test_jinguashi_journey.gd. That chain earns the picnic (state.picnic, which opens
## transit) and ends in Lanyang, all through World.act with its own checks. It never
## crafts a reinforced_pick, never borrows the public pick and never holds gold_ore.
## Unlike test_jinguashi_journey.gd this file does NOT craft the reinforced pick.
##
## Directly written by this file: NOTHING in the world state. No writes to inventory,
## coins, flags, travel book, records, objects, positions or time. Player B joins with
## World.add_player (the Session join path). Movement is World.move_player along BFS
## routes (parent walk_to for A, an identical token-parameterised copy for B); travel is
## the real "transit" action leg by leg (home ferry -> 頭城 -> 瑞芳 -> 九份 -> 金瓜石), as
## first_mountain_trip() in test_jinguashi_journey.gd does.
##
## Journey:
##  1. A (no reinforced pick, no gold ore) travels from Lanyang home, is refused at home
##     (WRONG_REGION), rides to Jinguashi. No state.gold_panning yet.
##  2. A strikes a surface copper node without a pick: refused, bag and world unchanged.
##  3. A: TOO_FAR from the shuttle stop; walks to the west bank; WRONG_CELL, BAD_EXTRA,
##     NEED_SCOOP (sift/swirl/pick on an empty pan, still no record); pan 1 with wrong
##     orders in between (NOT_YET, NEED_SIFT, HAS_SAND, SIFTED, SWIRLED); pans 2 and 3.
##     gold_ore 1, 2, 3. Every refusal: exact message and whole world state unchanged;
##     every success: exact message, exact record, whole-state diff only under the actor's
##     record (+ gold_ore on pick, receipts, commit counter).
##  4. Fourth scoop the same day -> DAILY_DONE.
##  5. Bobo's table: bobo_sort_start (takes the three panned gold_ore), three answers,
##     claim -> gold_sample 1, gold_ore 0, bobo_workshop.done[A]==true.
##  6. World.step to the next world day: view count 0. Scoop + sift (stage 2), save ->
##     reload (whole canonical state identical, record ints, SaveSchema accepts it),
##     finish the pan in the reloaded World -> gold_ore 1, count 1, total 4.
##  7. A scoops + sifts again (stage 2) and transits home: gold_pan at home WRONG_REGION.
##     Late joiner B joins at home, rides to Jinguashi, pans one pan while A is home:
##     B's record independent; A's player and pan record byte-identical.
##  8. A rides back: the pan is still at stage 2; A finishes it (count 2, total 5).
##     Final save -> reload, both records intact.
## Prints GOLD_PANNING_JOURNEY lines; the last checks=N failures=M line is the parent's.

const GOLD=preload("res://scripts/gold_panning.gd")
const WEATHER=preload("res://scripts/weather.gd")
const GP_B:="gold-pan-late-b"
const GP_B_NAME:="Pan Late"
const GP_TRIP:=[["home","ferry","toucheng"],["toucheng","rail","ruifang"],["ruifang","bus","jiufen"],["jiufen","shuttle","jinguashi"]]

var gp_started:=false
var gp_ms:=0
var gp_checks0:=0
var gp_actions0:=0
var gp_walk0:=0
var gp_time0:=0.0
var gp_model:={}
var gp_refusals:=[]
var gp_changed:=0
var gp_reloads:=0
var gp_pans:=[]
var gp_info:={}

# ---------------------------------------------------------------- journey

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	gp_started=true
	gp_ms=Time.get_ticks_msec()
	gp_checks0=checks
	gp_actions0=actions
	gp_walk0=walking
	gp_time0=gp_now()
	print("GOLD_PANNING_JOURNEY prerequisite history chain passed (checks %d, actions %d, world_seconds %.1f, day %d)"%[checks,actions,gp_now(),GOLD.today(world.state)])
	gp_arrive()
	if not failed:gp_no_pick()
	if not failed:gp_first_day()
	if not failed:gp_bobo()
	if not failed:gp_next_day()
	if not failed:gp_leave_with_pan()
	if not failed:gp_late_b()
	if not failed:gp_return()
	if not failed:gp_final()
	gp_report()

## 1. Lanyang -> home -> four transit legs -> Jinguashi, no pick, no gold ore.
func gp_arrive() -> void:
	act("travel",World.REGIONS.exit_cell("lanyang"),"home")
	if failed:return
	gp_check(world.player_region(TOKEN)=="home","A back home from Lanyang")
	gp_check(world.state.picnic==true,"picnic earned by the parent chain (transit open)")
	gp_check(int(bag().get("reinforced_pick",0))==0 and person().get("crafted_reinforced_pick",false)!=true and person().get("borrowed_mine_pick",false)!=true,"A has no reinforced pick, never crafted one, never borrowed the public pick")
	gp_check(int(bag().get(GOLD.ITEM,0))==0 and int(bag().get("gold_sample",0))==0,"A holds no gold_ore and no gold_sample")
	gp_check(not world.state.has(GOLD.STATE_KEY),"fresh world: no gold_panning record")
	gp_check(not (world.state.bobo_workshop.done as Dictionary).has(TOKEN) and not (world.state.bobo_workshop.jobs as Dictionary).has(TOKEN),"A never sorted with Bobo")
	gp_check(World.REGIONS.water(GOLD.SITE,GOLD.REGION) and not World.REGIONS.water(GOLD.SITE+Vector2i(1,0),GOLD.REGION),"淘砂處 %s is water with a bank cell east of it"%str(GOLD.SITE))
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"scoop",GOLD.WRONG_REGION,"A scoops from home")
	var coins:=int(person().coins)
	var held:=gp_nonzero(bag())
	gp_trip(TOKEN)
	if failed:return
	gp_check(world.player_region(TOKEN)==GOLD.REGION,"A arrived in Jinguashi")
	gp_check(int(person().coins)==coins and gp_same(gp_nonzero(bag()),held),"the mountain trip preserves coins and bag")
	gp_check(not world.state.has(GOLD.STATE_KEY),"arrival writes no gold_panning record")
	gp_check(gp_same(GOLD.view(world.state,TOKEN),{"stage":0,"count":0,"total":0}),"A's view on arrival: empty pan, 0 today, 0 total")
	gp_info.arrival={"day":GOLD.today(world.state),"world_seconds":gp_now(),"x":float(person().x),"y":float(person().y)}

## 2. Surface copper without a pick (tolerant: refused, bag and world unchanged).
func gp_no_pick() -> void:
	var node:Vector2i=World.JINGUASHI.NODES[0]
	walk_to(node)
	if failed:return
	var held:=gp_nonzero(bag())
	var result:=gp_deny(TOKEN,"pick",node,"","","A strikes surface copper %s without a pick"%str(node),false,true)
	gp_check(gp_same(gp_nonzero(bag()),held),"no-pick strike leaves the bag unchanged")
	gp_info.no_pick_message=str(result.get("message",""))

## 3 + 4. Three pans on the arrival day, wrong orders in between, then DAILY_DONE.
func gp_first_day() -> void:
	var day:=GOLD.today(world.state)
	var spawn:Vector2=World.REGIONS.spawn(GOLD.REGION)
	walk_to(World.REGIONS.exit_cell(GOLD.REGION))
	if failed:return
	gp_check(gp_dist(TOKEN,GOLD.SITE)>GOLD.REACH,"at the shuttle stop A is %.2f tiles from the 淘砂處 (spawn %s)"%[gp_dist(TOKEN,GOLD.SITE),str(spawn)])
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"scoop",GOLD.TOO_FAR,"scoop from the shuttle stop")
	walk_to(GOLD.SITE)
	if failed:return
	gp_check(gp_dist(TOKEN,GOLD.SITE)<=GOLD.REACH,"A on the bank, %.2f tiles from the 淘砂處"%gp_dist(TOKEN,GOLD.SITE))
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE+Vector2i(1,0),"scoop",GOLD.WRONG_CELL,"scoop aimed at the bank cell")
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"dig",GOLD.BAD_EXTRA,"unknown step 'dig'")
	for step:String in ["sift","swirl","pick"]:
		gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,step,GOLD.NEED_SCOOP,"%s on an empty pan"%step,false,false,true)
	gp_check(not world.state.has(GOLD.STATE_KEY),"refusals on an empty pan wrote no record")
	# Pan 1, with wrong orders in between.
	gp_pan(TOKEN,"scoop","pan 1")
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"pick",GOLD.NOT_YET,"pick right after scooping",false,false,true)
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"swirl",GOLD.NEED_SIFT,"swirl before sifting",false,false,true)
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"scoop",GOLD.HAS_SAND,"scoop with sand in the pan",false,false,true)
	gp_pan(TOKEN,"sift","pan 1")
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"sift",GOLD.SIFTED,"sift twice",false,false,true)
	gp_pan(TOKEN,"swirl","pan 1")
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"pick",GOLD.NOT_YET,"pick after one swirl",false,false,true)
	gp_pan(TOKEN,"swirl","pan 1")
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"pick",GOLD.NOT_YET,"pick after two swirls",false,false,true)
	gp_pan(TOKEN,"swirl","pan 1")
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"swirl",GOLD.SWIRLED,"a fourth swirl",false,false,true)
	gp_pan(TOKEN,"pick","pan 1")
	if failed:return
	gp_check(int(bag().get(GOLD.ITEM,0))==1,"after pan 1 A holds 1 gold_ore")
	gp_full_pan(TOKEN,"pan 2")
	if failed:return
	gp_check(int(bag().get(GOLD.ITEM,0))==2,"after pan 2 A holds 2 gold_ore")
	gp_full_pan(TOKEN,"pan 3")
	if failed:return
	gp_check(int(bag().get(GOLD.ITEM,0))==3,"after pan 3 A holds 3 gold_ore")
	gp_check(GOLD.today(world.state)==day,"all three pans on the arrival day %d"%day)
	gp_check(gp_same(GOLD.view(world.state,TOKEN),{"stage":0,"count":3,"total":3}),"view after three pans: stage 0, 3 today, 3 total")
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"scoop",GOLD.DAILY_DONE,"fourth scoop the same day",false,false,true)
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"sift",GOLD.NEED_SCOOP,"sift after the daily limit",false,false,true)
	gp_info.first_day={"day":day,"record":gp_canon(gp_record(TOKEN))}

## 5. Bobo's sort with the three panned gold_ore.
func gp_bobo() -> void:
	var table:Vector2i=World.BOBO_WORKSHOP.sites(world.state).table
	var pan_bytes:=var_to_bytes(gp_canon(world.state.get(GOLD.STATE_KEY)))
	var samples:=int(bag().get("gold_sample",0))
	gp_check(int(bag().get(GOLD.ITEM,0))==World.BOBO_WORKSHOP.INPUT,"A brings exactly %d panned gold_ore to Bobo's table %s"%[World.BOBO_WORKSHOP.INPUT,str(table)])
	gp_act_ok(TOKEN,"bobo_sort_start",table,"","請按照標籤將礦樣分格。")
	gp_check(int(bag().get(GOLD.ITEM,0))==0,"sort start takes the three panned gold_ore")
	gp_deny(TOKEN,"bobo_sort_answer",table,"0:small","請依礦樣標籤選擇這一輪的格子。","Bobo sort wrong bin")
	gp_act_ok(TOKEN,"bobo_sort_answer",table,"0:large","已放入對應格子。")
	gp_act_ok(TOKEN,"bobo_sort_answer",table,"1:medium","已放入對應格子。")
	gp_act_ok(TOKEN,"bobo_sort_answer",table,"2:small","已放入對應格子。")
	gp_act_ok(TOKEN,"bobo_sort_claim",table,"","已領取金工收藏樣本。")
	if failed:return
	gp_check(int(bag().get("gold_sample",0))==samples+1 and samples==0 and int(bag().get(GOLD.ITEM,0))==0,"A: gold_sample 1, gold_ore 0")
	gp_check(world.state.bobo_workshop.done.get(TOKEN)==true and not (world.state.bobo_workshop.jobs as Dictionary).has(TOKEN),"bobo_workshop.done[A]==true, no open job")
	gp_check(var_to_bytes(gp_canon(world.state.get(GOLD.STATE_KEY)))==pan_bytes,"the sort did not touch the gold_panning record")

## 6. Next world day, half a pan, save -> reload, finish in the reloaded World.
func gp_next_day() -> void:
	var day0:=GOLD.today(world.state)
	var target:=(WEATHER.day_index(gp_now())+1.0)*WEATHER.DAY_SECONDS+1.0
	gp_wait_until(target)
	if failed:return
	var day1:=GOLD.today(world.state)
	gp_check(day1==day0+1,"fast-forwarded to world day %d (from %d)"%[day1,day0])
	gp_check(gp_same(GOLD.view(world.state,TOKEN),{"stage":0,"count":0,"total":3}),"new day: view count 0, total 3")
	gp_check(gp_same(gp_record(TOKEN),{"stage":0,"day":day0,"count":3,"total":3}),"raw record still day %d count 3 (nothing written by the clock)"%day0)
	gp_check(GOLD.step_block(world.state,"scoop",bag(),TOKEN)=="","scoop allowed again on the new day (pure)")
	walk_to(GOLD.SITE)
	gp_pan(TOKEN,"scoop","day-2 pan 1")
	gp_pan(TOKEN,"sift","day-2 pan 1")
	if failed:return
	gp_check(gp_same(gp_record(TOKEN),{"stage":2,"day":day0,"count":3,"total":3}),"mid-pan record: stage 2, day/count of the last finished pan")
	gp_check(GOLD.count_today(world.state,TOKEN)==0 and GOLD.total(world.state,TOKEN)==3,"mid-pan view: 0 today, 3 total")
	gp_reload("mid-pan on day %d"%day1)
	if failed:return
	var rec:Dictionary=gp_record(TOKEN)
	gp_check(gp_same(rec,{"stage":2,"day":day0,"count":3,"total":3}),"record survives the reload: stage 2, total 3, count 3 of day %d"%day0)
	var ints:=true
	for field:String in GOLD.RECORD_KEYS:
		if typeof(rec.get(field))!=TYPE_INT:ints=false
	gp_check(ints,"reloaded record fields are ints %s"%JSON.stringify(rec))
	gp_check(GOLD.stage(world.state,TOKEN)==2 and GOLD.next_step(world.state,TOKEN)=="swirl" and GOLD.count_today(world.state,TOKEN)==0,"after reload: next step swirl, 0 today")
	gp_check(world.player_region(TOKEN)==GOLD.REGION and gp_dist(TOKEN,GOLD.SITE)<=GOLD.REACH,"A still on the bank after reload")
	for i in 3:gp_pan(TOKEN,"swirl","day-2 pan 1 (after reload)")
	gp_pan(TOKEN,"pick","day-2 pan 1 (after reload)")
	if failed:return
	gp_check(int(bag().get(GOLD.ITEM,0))==1,"day-2 pan 1: gold_ore 1")
	gp_check(gp_same(GOLD.view(world.state,TOKEN),{"stage":0,"count":1,"total":4}),"day-2 view: count 1 (new day), total 4")
	gp_check(gp_same(gp_record(TOKEN),{"stage":0,"day":day1,"count":1,"total":4}),"record day moved to %d"%day1)

## 7a. A starts another pan and leaves Jinguashi with it unfinished.
func gp_leave_with_pan() -> void:
	walk_to(GOLD.SITE)
	gp_pan(TOKEN,"scoop","day-2 pan 2 (left unfinished)")
	gp_pan(TOKEN,"sift","day-2 pan 2 (left unfinished)")
	if failed:return
	gp_info.left_record=gp_canon(gp_record(TOKEN))
	var rec_bytes:=var_to_bytes(gp_canon(gp_record(TOKEN)))
	gp_act_ok(TOKEN,"transit",World.REGIONS.exit_cell(GOLD.REGION),"home")
	if failed:return
	gp_check(world.player_region(TOKEN)=="home","A transited home with a half-done pan")
	for step:String in ["swirl","scoop","pick"]:
		gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,step,GOLD.WRONG_REGION,"A %s from home"%step)
	gp_check(var_to_bytes(gp_canon(gp_record(TOKEN)))==rec_bytes and GOLD.stage(world.state,TOKEN)==2,"A's pan stays at stage 2 at home")

## 7b. Late joiner B pans one pan while A is home.
func gp_late_b() -> void:
	gp_check(not world.state.players.has(GP_B),"B not in the save yet")
	world.add_player(GP_B,GP_B_NAME)
	var b:Dictionary=world.state.players[GP_B]
	gp_check(world.player_region(GP_B)=="home" and int(b.inventory.get("reinforced_pick",0))==0 and int(b.inventory.get(GOLD.ITEM,0))==0,"B joined at home with no pick and no gold ore")
	gp_check(not (world.state[GOLD.STATE_KEY].players as Dictionary).has(GP_B) and gp_same(GOLD.view(world.state,GP_B),{"stage":0,"count":0,"total":0}),"B has no pan record")
	var a_bytes:=var_to_bytes(gp_canon(world.state.players[TOKEN]))
	var a_rec:=var_to_bytes(gp_canon(gp_record(TOKEN)))
	gp_deny(GP_B,GOLD.ACTION,GOLD.SITE,"scoop",GOLD.WRONG_REGION,"B scoops from home")
	gp_trip(GP_B)
	if failed:return
	gp_check(world.player_region(GP_B)==GOLD.REGION and world.player_region(TOKEN)=="home","B in Jinguashi, A at home")
	gp_walk(GP_B,GOLD.SITE)
	if failed:return
	gp_full_pan(GP_B,"B's pan")
	if failed:return
	var day:=GOLD.today(world.state)
	gp_check(int(world.state.players[GP_B].inventory.get(GOLD.ITEM,0))==1,"B holds 1 gold_ore")
	gp_check(gp_same(gp_record(GP_B),{"stage":0,"day":day,"count":1,"total":1}) and gp_same(GOLD.view(world.state,GP_B),{"stage":0,"count":1,"total":1}),"B's own record: 1 today, 1 total")
	gp_check(var_to_bytes(gp_canon(world.state.players[TOKEN]))==a_bytes,"A's whole player record byte-identical through B's leg")
	gp_check(var_to_bytes(gp_canon(gp_record(TOKEN)))==a_rec and GOLD.stage(world.state,TOKEN)==2 and GOLD.count_today(world.state,TOKEN)==1,"A's pan record unchanged by B (stage 2, 1 today)")
	gp_check((world.state[GOLD.STATE_KEY].players as Dictionary).size()==2,"two records: A and B")

## 8. A rides back; the pan is still at stage 2; A finishes it.
func gp_return() -> void:
	var rec_bytes:=var_to_bytes(gp_canon(gp_record(TOKEN)))
	gp_trip(TOKEN)
	if failed:return
	gp_check(world.player_region(TOKEN)==GOLD.REGION,"A back in Jinguashi")
	gp_check(var_to_bytes(gp_canon(gp_record(TOKEN)))==rec_bytes and GOLD.stage(world.state,TOKEN)==2 and GOLD.next_step(world.state,TOKEN)=="swirl","the unfinished pan is still at stage 2 after the round trip")
	walk_to(GOLD.SITE)
	gp_deny(TOKEN,GOLD.ACTION,GOLD.SITE,"scoop",GOLD.HAS_SAND,"scoop over the kept pan",false,false,true)
	for i in 3:gp_pan(TOKEN,"swirl","day-2 pan 2 (after the round trip)")
	gp_pan(TOKEN,"pick","day-2 pan 2 (after the round trip)")
	if failed:return
	gp_check(int(bag().get(GOLD.ITEM,0))==2,"A holds 2 gold_ore")
	gp_check(gp_same(GOLD.view(world.state,TOKEN),{"stage":0,"count":2,"total":5}),"A's view: 2 today, 5 total")

func gp_final() -> void:
	var a_rec:Variant=gp_canon(gp_record(TOKEN))
	var b_rec:Variant=gp_canon(gp_record(GP_B))
	gp_reload("final")
	if failed:return
	gp_check(gp_same(gp_record(TOKEN),a_rec) and gp_same(gp_record(GP_B),b_rec),"both records identical after the final reload")
	gp_check(gp_same(GOLD.view(world.state,TOKEN),{"stage":0,"count":2,"total":5}) and gp_same(GOLD.view(world.state,GP_B),{"stage":0,"count":1,"total":1}),"final views A {0,2,5} B {0,1,1}")
	gp_check(gp_changed==0,"every refusal left the world unchanged")

# ---------------------------------------------------------------- report

func gp_report() -> void:
	if not gp_started:
		print("GOLD_PANNING_JOURNEY did not reach the panning segment")
		return
	print("GOLD_PANNING_JOURNEY info=%s"%JSON.stringify(gp_info))
	for row in gp_pans:print("GOLD_PANNING_JOURNEY pan %s"%row)
	for i in gp_refusals.size():print("GOLD_PANNING_JOURNEY refusal %d %s"%[i+1,gp_refusals[i]])
	print("GOLD_PANNING_JOURNEY stats segment_actions=%d segment_walk_tiles=%d segment_world_seconds=%.1f segment_reloads=%d segment_refusals=%d all_refusals_state_unchanged=%s segment_check_count=%d segment_ms=%d passed=%s"%[actions-gp_actions0,walking-gp_walk0,gp_now()-gp_time0,gp_reloads,gp_refusals.size(),str(gp_changed==0),checks-gp_checks0,Time.get_ticks_msec()-gp_ms,str(not failed)])

# ---------------------------------------------------------------- helpers

func gp_check(condition:bool,message:String) -> bool:
	expect(condition,"GOLD_PANNING_JOURNEY: "+message)
	return condition

func gp_now() -> float:
	return float(world.state.time)

func gp_bag(token:String) -> Dictionary:
	return world.state.players[token].inventory

func gp_dist(token:String,cell:Vector2i) -> float:
	var who:Dictionary=world.state.players[token]
	return Vector2(float(who.x),float(who.y)).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## The raw server record of `token` ({} when absent).
func gp_record(token:String) -> Dictionary:
	var whole:Variant=world.state.get(GOLD.STATE_KEY)
	if not whole is Dictionary or not whole.get("players") is Dictionary:return {}
	var own:Variant=whole.players.get(token)
	if not own is Dictionary:return {}
	return own

func gp_wait_until(target:float) -> void:
	while gp_now()<target-0.000001 and not failed:
		var dt:=minf(120.0,target-gp_now())
		gp_check(world.step(dt,true),"world step %.1f (%s)"%[dt,str(world.step_error)])

func gp_trip(token:String) -> void:
	for leg:Array in GP_TRIP:
		if failed:return
		var points:Dictionary=World.TRANSIT.points(str(leg[0]))
		var cell:Vector2i=points[str(leg[1])].cell
		gp_act_ok(token,"transit",cell,str(leg[2]))
		gp_check(world.player_region(token)==str(leg[2]),"%s reached %s"%[token,str(leg[2])])

## One complete pan: scoop, sift, swirl x3, pick.
func gp_full_pan(token:String,label:String) -> void:
	for step:String in GOLD.STEPS:
		if failed:return
		gp_pan(token,step,label)

## A successful gold_pan step: exact message from an independent model, exact record,
## gold_ore delta, view, and a whole-state diff limited to the actor's record (+ the
## gold_ore slot on pick, the actor's receipts and the commit counter).
func gp_pan(token:String,step:String,label:String) -> void:
	if failed:return
	var s:=world.state
	var today:=GOLD.today(s)
	var start:Dictionary=gp_model.get(token,{"stage":0,"day":0,"count":0,"total":0})
	var model:Dictionary=start.duplicate()
	gp_check(GOLD.next_step(s,token)==step,"%s %s: next step is %s (got %s)"%[label,step,step,GOLD.next_step(s,token)])
	gp_check(GOLD.step_block(s,step,gp_bag(token),token)=="","%s %s: pure block empty (got '%s')"%[label,step,GOLD.step_block(s,step,gp_bag(token),token)])
	var message:=""
	if step=="pick":
		var done:=int(model["count"]) if int(model["day"])==today else 0
		model["stage"]=0
		model["day"]=today
		model["count"]=done+1
		model["total"]=int(model["total"])+1
		message=GOLD.PICK_OK%int(model["count"])
	else:
		model["stage"]=int(model["stage"])+1
		match step:
			"scoop":message=GOLD.SCOOP_OK
			"sift":message=GOLD.SIFT_OK
			_:message=GOLD.SWIRL_LAST if int(model.stage)==5 else GOLD.SWIRL_OK%(5-int(model.stage))
	var gold_before:=int(gp_bag(token).get(GOLD.ITEM,0))
	var had_key:=world.state.has(GOLD.STATE_KEY)
	var before:Variant=gp_canon(world.state)
	actions+=1
	var result:=world.act(token,"gold-journey-%d"%actions,GOLD.ACTION,GOLD.SITE,step)
	gp_check(result.ok==true and str(result.message)==message,"%s %s: ok '%s' (got ok=%s '%s')"%[label,step,message,str(result.ok),str(result.message)])
	gp_check(gp_same(gp_record(token),model),"%s %s: record %s (want %s)"%[label,step,JSON.stringify(gp_canon(gp_record(token))),JSON.stringify(gp_canon(model))])
	var gold_after:=int(gp_bag(token).get(GOLD.ITEM,0))
	gp_check(gold_after==gold_before+(1 if step=="pick" else 0),"%s %s: gold_ore %d -> %d"%[label,step,gold_before,gold_after])
	var shown:={"stage":int(model.stage),"count":int(model.count) if int(model.day)==today else 0,"total":int(model.total)}
	gp_check(gp_same(GOLD.view(world.state,token),shown),"%s %s: view %s"%[label,step,JSON.stringify(shown)])
	var allowed:=["state.%s.players.%s"%[GOLD.STATE_KEY,token],"state.players.%s.receipts"%token,"state.committed"]
	if not had_key:allowed.append("state.%s"%GOLD.STATE_KEY)
	if step=="pick":allowed.append("state.players.%s.inventory.%s"%[token,GOLD.ITEM])
	var diffs:=[]
	gp_all_diffs(before,gp_canon(world.state),"state",diffs)
	var other:=[]
	for row:Dictionary in diffs:
		var ok:=false
		for prefix:String in allowed:
			if str(row.path)==prefix or str(row.path).begins_with(prefix+"."):ok=true
		if not ok:other.append(row)
	gp_check(other.is_empty() and not diffs.is_empty(),"%s %s: whole-state diff only under %s (other %s)"%[label,step,str(allowed),JSON.stringify(other.slice(0,5))])
	gp_model[token]=model
	gp_pans.append("%s | %s %s | %s | day %d | record %s | gold_ore %d"%[label,token,step,str(result.message),today,JSON.stringify(gp_canon(model)),gold_after])

## Refused with the exact message (any message when any_message); whole World.state
## unchanged (== and canonical bytes). pure: GOLD.step_block must say the same.
func gp_deny(token:String,action:String,target:Vector2i,extra:String,message:String,label:String,walk:=false,any_message:=false,pure:=false) -> Dictionary:
	if failed:return {}
	if walk:gp_walk(token,target)
	if failed:return {}
	if pure:
		var block:=GOLD.step_block(world.state,extra,gp_bag(token),token)
		gp_check(block==message,"%s: pure block agrees '%s' (got '%s')"%[label,message,block])
	actions+=1
	var state_before:=world.state.duplicate(true)
	var bytes_before:=var_to_bytes(gp_canon(world.state))
	var result:=world.act(token,"gold-journey-%d"%actions,action,target,extra)
	gp_check(not result.ok and (any_message or str(result.message)==message),"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var unchanged:=world.state==state_before and var_to_bytes(gp_canon(world.state))==bytes_before
	gp_check(unchanged,label+": whole world state unchanged")
	if not unchanged:gp_changed+=1
	gp_refusals.append("%s | %s %s %s %s | %s | state_unchanged=%s"%[label,token,action,str(target),extra,str(result.message),str(unchanged)])
	return result

## A successful action by `token` after walking near the target; exact message unless "".
func gp_act_ok(token:String,action:String,target:Vector2i,extra:String,message:="") -> Dictionary:
	if failed:return {}
	gp_walk(token,target)
	if failed:return {}
	actions+=1
	var result:=world.act(token,"gold-journey-%d"%actions,action,target,extra)
	print("%d %s %s %s %s | %s"%[actions,token,action,str(target),extra,str(result.message)])
	gp_check(result.ok==true and (message.is_empty() or str(result.message)==message),"%s %s %s at %s: ok '%s' (got ok=%s '%s')"%[token,action,extra,str(target),message,str(result.ok),str(result.message)])
	return result

## Same BFS walk as the parent's walk_to/route, for any token.
func gp_walk(token:String,target:Vector2i,reach:float=2.0) -> void:
	if failed:return
	var path:=gp_route(token,target,reach)
	if path.is_empty():
		gp_check(false,"%s: no path to %s"%[token,str(target)])
		return
	for index in range(1,path.size()):
		var direction:=Vector2(path[index]-path[index-1])
		for step in range(4):world.move_player(token,direction,0.25/3.6)
		walking+=1
		var who:Dictionary=world.state.players[token]
		var cell:Vector2i=path[index]
		if not gp_check(Vector2(float(who.x),float(who.y)).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=0.001,"%s movement followed the passable route"%token):return

func gp_route(token:String,target:Vector2i,reach:float) -> Array:
	var region:=world.player_region(token)
	var local_world:=World.new()
	local_world.state=world.region_snapshot(region)
	local_world._region=region
	var who:Dictionary=world.state.players[token]
	var start:=Vector2i(int(float(who.x)),int(float(who.y)))
	var queue:=[start]
	var previous:={start:start}
	var index:=0
	while index<queue.size():
		var tile:Vector2i=queue[index]
		index+=1
		if tile!=target and Vector2(tile-target).length()<=reach:
			var path:=[tile]
			while tile!=start:
				tile=previous[tile]
				path.push_front(tile)
			return path
		for offset:Vector2i in World.INDUSTRY.NEIGHBORS:
			var next:Vector2i=tile+offset
			if not previous.has(next) and local_world.can_stand(Vector2(next)+Vector2(0.5,0.5)):
				previous[next]=tile
				queue.append(next)
	return []

## Save, reload into a fresh World through SaveSchema, compare the WHOLE canonical state
## (numbers 1e-6; only zero load defaults may appear), check the pan record, rejoin the
## active tokens and continue in the reloaded World.
func gp_reload(label:String) -> void:
	if failed:return
	gp_check(world.save(),label+": explicit save")
	var reopened:=World.new()
	if not gp_check(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,label+": fresh World loads the primary save through SaveSchema"):return
	var diffs:=[]
	gp_all_diffs(gp_canon(world.state),gp_canon(reopened.state),"state",diffs)
	var defaults:=[]
	var real:=[]
	for row:Dictionary in diffs:
		if str(row.kind)=="added_on_load" and (row.value is int or row.value is float) and float(row.value)==0.0:defaults.append(row.path)
		else:real.append(row)
	gp_check(real.is_empty(),label+": whole canonical state identical after reload %s"%JSON.stringify(real.slice(0,5)))
	gp_check(var_to_bytes(gp_canon(world.state.get(GOLD.STATE_KEY)))==var_to_bytes(gp_canon(reopened.state.get(GOLD.STATE_KEY))),label+": gold_panning record identical")
	var copy:Dictionary=reopened.state.duplicate(true)
	gp_check(GOLD.valid(copy),label+": reloaded gold_panning passes GoldPanning.valid")
	reopened.save_path=world.save_path
	for token in world.active_tokens:reopened.add_player(str(token),str(world.state.players[token].name))
	world=reopened
	gp_reloads+=1
	print("GOLD_PANNING_JOURNEY reload (%s) world_seconds=%.1f identical=%s load_defaults=%s"%[label,gp_now(),str(real.is_empty()),str(defaults)])

func gp_nonzero(inv:Dictionary) -> Dictionary:
	var out:={}
	for item in inv:
		if int(inv[item])!=0:out[str(item)]=int(inv[item])
	return out

func gp_same(a:Variant,b:Variant) -> bool:
	return var_to_bytes(gp_canon(a))==var_to_bytes(gp_canon(b))

## Every difference (up to 40): {"path","kind":"changed"|"added_on_load"|"lost_on_load","value"}.
static func gp_all_diffs(a:Variant,b:Variant,path:String,out:Array) -> void:
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
			else:gp_all_diffs(a[k],b[k],"%s.%s"%[path,str(k)],out)
		for k in b:
			if not a.has(k):out.append({"path":"%s.%s"%[path,str(k)],"kind":"added_on_load","value":b[k]})
		return
	if a is Array:
		if a.size()!=b.size():
			out.append({"path":path,"kind":"changed","value":"size %d vs %d"%[a.size(),b.size()]})
			return
		for i in a.size():gp_all_diffs(a[i],b[i],"%s[%d]"%[path,i],out)
		return
	if a!=b:out.append({"path":path,"kind":"changed","value":"%s vs %s"%[str(a).left(60),str(b).left(60)]})

## Sorted String keys, Vector2i as [x,y], integral floats as int (JSON reload safe).
static func gp_canon(value:Variant) -> Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			var source:Variant=value[k] if value.has(k) else value[StringName(k)]
			out[k]=gp_canon(source)
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(gp_canon(item))
		return list
	if value is Vector2i:return [value.x,value.y]
	if value is float and is_finite(value) and floorf(value)==value:return int(value)
	return value
