extends "res://tests/test_history_journey.gd"
## Chapter 40 金瓜石初訪「運礦路線」(ore_route.gd) natural journey: a FRESH temp world,
## ONE process, same machine (reloads are in-process World.new().load_world on the same
## save file; after each reload the journey continues in the reloaded World). This is
## single-process, same-machine program evidence, NOT a networked or multi-machine run.
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
## Time is fast-forwarded with World.step(dt,true) in 120 s chunks to the next world day
## (WEATHER.DAY_SECONDS calendar); walking and transit cost no world time.
##
## Prerequisite reuse (disclosed): this file EXTENDS the unmodified
## test_history_journey.gd (-> garden -> regions -> chapter journeys), the same parent as
## test_gold_panning_journey.gd (the template; its helpers are COPIED here with an or_
## prefix, nothing is imported from it). That chain earns the picnic (state.picnic, which
## opens transit) and ends in Lanyang, all through World.act with its own checks. It never
## crafts a reinforced_pick and this file never crafts one either.
##
## Directly written by this file: NOTHING in the world state. No writes to inventory,
## coins, flags, travel book, records, objects, positions, region or time. Player B joins
## with World.add_player (the Session join path). Movement is World.move_player along BFS
## routes (an or_walk copy of the template's token-parameterised walk); travel is the real
## "transit" action leg by leg (home ferry -> 頭城 -> 瑞芳 -> 九份 -> 金瓜石). Every ore-cart
## step goes through World.act(token,req,"ore_cart",cell,extra). Time only via World.step.
##
## Journey:
##  1. A (no reinforced pick) back home from Lanyang: ore_cart at home WRONG_REGION; rides
##     four legs to Jinguashi. No state.ore_route yet.
##  2. From the shuttle arrival: load at STOPS[0] TOO_FAR (state unchanged); walks to the
##     load platform; WRONG_CELL (stop 1), BAD_EXTRA ('dig'), NEED_LOAD (push/unload on the
##     empty cart) — still no record. Cart 1: load (then LOADED), push ×6 walking along
##     (NOT_THERE mid-route; at the 5th push: push without walking TOO_FAR, push at the old
##     cell WRONG_CELL), AT_END at the platform, unload: coins exactly +PAY, inventory
##     identical, count 1, total 1.
##  3. Cart 2 the same day; while it is mid-route A walks to the 淘砂處 and does ONE
##     gold_pan scoop (both records independent), walks back and finishes the cart.
##     Count 2. Walks back to the load platform: third load DAILY_DONE (verbatim).
##  4. World.step to the next world day: view count 0, raw record untouched. Load + two
##     pushes, save -> reload (whole canonical state identical, record ints, Route.valid),
##     continue in the reloaded World to the end, unload: count 1 (new day), total 3.
##  5. A loads cart 4, pushes two segments and transits home with it: ore_cart at home
##     WRONG_REGION (push and load), record unchanged. Late joiner B joins at home
##     (WRONG_REGION too), rides to Jinguashi, runs a full cart: B record {0,day,1,1},
##     B coins +PAY; A's whole player and ore record byte-identical through B's leg.
##  6. A rides back: cart still at stage 3; A walks to it and finishes it: count 2, total 4,
##     coins +PAY. Final save -> reload: both ore records and A's gold record intact.
## Every refusal: exact message, Route.step_block agrees where it is a pure step block, and
## the whole world state unchanged (== and canonical bytes). Every success: exact message
## from an independent model, exact record, view, coin/inventory deltas, and a whole-state
## diff limited to the actor's record (+ coins on unload, receipts, commit counter).
##
## NOT covered here: Session snapshots (own_ore_route), the UI page, world_view drawing,
## the PURSE_FULL branch (would need a coin write), malformed-record BAD_EXTRA branches,
## and networked/multi-process play. Prints ORE_ROUTE_JOURNEY lines; the last
## checks=N failures=M line is the parent's.

const ORE=preload("res://scripts/ore_route.gd")
const GOLD=preload("res://scripts/gold_panning.gd")
const WEATHER=preload("res://scripts/weather.gd")
const OR_B:="ore-cart-late-b"
const OR_B_NAME:="Cart Late"
const OR_TRIP:=[["home","ferry","toucheng"],["toucheng","rail","ruifang"],["ruifang","bus","jiufen"],["jiufen","shuttle","jinguashi"]]

var or_started:=false
var or_ms:=0
var or_checks0:=0
var or_actions0:=0
var or_walk0:=0
var or_time0:=0.0
var or_model:={}
var or_refusals:=[]
var or_changed:=0
var or_reloads:=0
var or_steps:=[]
var or_info:={}

# ---------------------------------------------------------------- journey

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	or_started=true
	or_ms=Time.get_ticks_msec()
	or_checks0=checks
	or_actions0=actions
	or_walk0=walking
	or_time0=or_now()
	print("ORE_ROUTE_JOURNEY prerequisite history chain passed (checks %d, actions %d, world_seconds %.1f, day %d)"%[checks,actions,or_now(),ORE.today(world.state)])
	or_arrive()
	if not failed:or_first_cart()
	if not failed:or_second_cart()
	if not failed:or_next_day()
	if not failed:or_leave_with_cart()
	if not failed:or_late_b()
	if not failed:or_return()
	if not failed:or_final()
	or_report()

## 1. Lanyang -> home -> four transit legs -> Jinguashi, no pick.
func or_arrive() -> void:
	act("travel",World.REGIONS.exit_cell("lanyang"),"home")
	if failed:return
	or_check(world.player_region(TOKEN)=="home","A back home from Lanyang")
	or_check(world.state.picnic==true,"picnic earned by the parent chain (transit open)")
	or_check(int(bag().get("reinforced_pick",0))==0 and person().get("crafted_reinforced_pick",false)!=true,"A has no reinforced pick and never crafted one")
	or_check(not world.state.has(ORE.STATE_KEY),"fresh world: no ore_route record")
	or_check(ORE.STOPS.size()==ORE.LAST and ORE.PUSHES==ORE.LAST-1,"STOPS has %d stops, %d pushes"%[ORE.STOPS.size(),ORE.PUSHES])
	var standable:=true
	var probe:=World.new()
	probe.state=world.region_snapshot(ORE.REGION)
	probe._region=ORE.REGION
	for cell:Vector2i in ORE.STOPS:
		if not probe.can_stand(Vector2(cell)+Vector2(0.5,0.5)):standable=false
	or_check(standable,"every STOP cell is standable ground in Jinguashi")
	or_deny(TOKEN,ORE.ACTION,ORE.STOPS[0],"load",ORE.WRONG_REGION,"A loads from home")
	var coins:=int(person().coins)
	var held:=or_nonzero(bag())
	or_trip(TOKEN)
	if failed:return
	or_check(world.player_region(TOKEN)==ORE.REGION,"A arrived in Jinguashi")
	or_check(int(person().coins)==coins and or_same(or_nonzero(bag()),held),"the mountain trip preserves coins and bag")
	or_check(not world.state.has(ORE.STATE_KEY),"arrival writes no ore_route record")
	or_check(or_same(ORE.view(world.state,TOKEN),{"stage":0,"count":0,"total":0}),"A's view on arrival: empty cart, 0 today, 0 total")
	or_check(ORE.cart_label(world.state,TOKEN)==ORE.LABEL_IDLE,"cart label on arrival: idle")
	or_info.arrival={"day":ORE.today(world.state),"world_seconds":or_now(),"x":float(person().x),"y":float(person().y)}

## 2. From the shuttle arrival to the load platform, refusals, then cart 1 with walking.
func or_first_cart() -> void:
	var day:=ORE.today(world.state)
	var load_cell:Vector2i=ORE.STOPS[0]
	or_check(or_dist(TOKEN,load_cell)>ORE.REACH,"at the shuttle arrival A is %.2f tiles from the load platform %s"%[or_dist(TOKEN,load_cell),str(load_cell)])
	or_deny(TOKEN,ORE.ACTION,load_cell,"load",ORE.TOO_FAR,"load from the shuttle arrival")
	or_check(not world.state.has(ORE.STATE_KEY),"TOO_FAR wrote no record")
	or_walk(TOKEN,load_cell)
	if failed:return
	or_check(or_dist(TOKEN,load_cell)<=ORE.REACH,"A walked to the load platform, %.2f tiles away"%or_dist(TOKEN,load_cell))
	or_deny(TOKEN,ORE.ACTION,ORE.STOPS[1],"load",ORE.WRONG_CELL,"load aimed at stop 1")
	or_deny(TOKEN,ORE.ACTION,load_cell,"dig",ORE.BAD_EXTRA,"unknown step 'dig'",false,true)
	or_deny(TOKEN,ORE.ACTION,load_cell,"push",ORE.NEED_LOAD,"push the empty cart",false,true)
	or_deny(TOKEN,ORE.ACTION,load_cell,"unload",ORE.NEED_LOAD,"unload the empty cart",false,true)
	or_check(not world.state.has(ORE.STATE_KEY),"refusals on the empty cart wrote no record")
	var coins0:=int(person().coins)
	var held:=or_nonzero(bag())
	or_step(TOKEN,"load","cart 1")
	or_deny(TOKEN,ORE.ACTION,load_cell,"load",ORE.LOADED,"load twice",false,true)
	or_deny(TOKEN,ORE.ACTION,load_cell,"unload",ORE.NOT_THERE,"unload at the load platform",false,true)
	for i in ORE.PUSHES:
		if failed:return
		var at:=ORE.stage(world.state,TOKEN)
		var cell:=ORE.cart_cell(at)
		if i==4:
			# The cart just moved from STOPS[3] (23,23) to STOPS[4] (20,23); A still stands
			# beside the old stop, approached from the east.
			var old:Vector2i=ORE.STOPS[at-2]
			or_check(or_dist(TOKEN,cell)>ORE.REACH,"before walking A is %.2f tiles from the cart at %s"%[or_dist(TOKEN,cell),str(cell)])
			or_deny(TOKEN,ORE.ACTION,cell,"push",ORE.TOO_FAR,"push without walking to the cart")
			or_deny(TOKEN,ORE.ACTION,old,"push",ORE.WRONG_CELL,"push at the old stop %s"%str(old))
		or_walk(TOKEN,cell)
		if failed:return
		or_check(or_dist(TOKEN,cell)<=ORE.REACH,"cart 1 push %d: A walked along to %s (%.2f)"%[i+1,str(cell),or_dist(TOKEN,cell)])
		if i==2:or_deny(TOKEN,ORE.ACTION,cell,"unload",ORE.NOT_THERE,"unload mid-route",false,true)
		or_step(TOKEN,"push","cart 1")
	if failed:return
	var end_cell:Vector2i=ORE.STOPS[ORE.LAST-1]
	or_check(ORE.stage(world.state,TOKEN)==ORE.LAST and ORE.cart_cell(ORE.LAST)==end_cell,"cart 1 at the unload platform %s"%str(end_cell))
	or_check(ORE.cart_label(world.state,TOKEN)==ORE.LABEL_END and ORE.stage_text(ORE.LAST)==ORE.STAGE_END,"label/stage text at the platform")
	or_walk(TOKEN,end_cell) # 最後一推把台車送到卸礦台，人要先跟過去（距離檢查在 AT_END 之前）
	if failed:return
	or_deny(TOKEN,ORE.ACTION,end_cell,"push",ORE.AT_END,"push past the unload platform",false,true)
	or_step(TOKEN,"unload","cart 1")
	if failed:return
	or_check(int(person().coins)==coins0+ORE.PAY,"cart 1: coins exactly +%d (%d -> %d)"%[ORE.PAY,coins0,int(person().coins)])
	or_check(or_same(or_nonzero(bag()),held),"cart 1: inventory unchanged")
	or_check(or_same(or_record(TOKEN),{"stage":0,"day":day,"count":1,"total":1}),"cart 1: record stage 0, day %d, count 1, total 1"%day)
	or_check(ORE.count_today(world.state,TOKEN)==1,"cart 1: view count 1")
	or_info.first_cart={"day":day,"coins":int(person().coins)}

## 3. Cart 2 the same day with one gold_pan scoop interleaved; then DAILY_DONE.
func or_second_cart() -> void:
	var day:=ORE.today(world.state)
	var coins0:=int(person().coins)
	var held:=or_nonzero(bag())
	or_go(TOKEN,"load","cart 2")
	or_go(TOKEN,"push","cart 2")
	or_go(TOKEN,"push","cart 2")
	if failed:return
	or_check(ORE.stage(world.state,TOKEN)==3,"cart 2 mid-route at stage 3")
	or_gold_scoop()
	if failed:return
	while ORE.stage(world.state,TOKEN)<ORE.LAST and not failed:or_go(TOKEN,"push","cart 2")
	or_go(TOKEN,"unload","cart 2")
	if failed:return
	or_check(ORE.today(world.state)==day,"both carts on the arrival day %d"%day)
	or_check(int(person().coins)==coins0+ORE.PAY,"cart 2: coins exactly +%d"%ORE.PAY)
	or_check(or_same(or_nonzero(bag()),held),"cart 2: inventory unchanged")
	or_check(or_same(or_record(TOKEN),{"stage":0,"day":day,"count":2,"total":2}),"cart 2: record count 2, total 2")
	or_check(or_same(ORE.view(world.state,TOKEN),{"stage":0,"count":2,"total":2}),"view after two carts: 2 today, 2 total")
	or_check(ORE.cart_label(world.state,TOKEN)==ORE.LABEL_FULL,"cart label: done for today")
	or_walk(TOKEN,ORE.STOPS[0])
	if failed:return
	or_deny(TOKEN,ORE.ACTION,ORE.STOPS[0],"load",ORE.DAILY_DONE,"third load the same day",false,true)
	or_check(ORE.DAILY_DONE=="今天已經送了 2 車，礦場的人說剩下的明天再送。","DAILY_DONE text verbatim")
	or_info.first_day={"day":day,"record":or_canon(or_record(TOKEN))}

## One gold_pan scoop while the ore cart waits mid-route; records stay independent.
func or_gold_scoop() -> void:
	var ore_bytes:=var_to_bytes(or_canon(world.state.get(ORE.STATE_KEY)))
	or_check(not world.state.has(GOLD.STATE_KEY),"no gold_panning record before the interleave")
	or_walk(TOKEN,GOLD.SITE)
	if failed:return
	or_check(or_dist(TOKEN,GOLD.SITE)<=GOLD.REACH,"A on the bank, %.2f tiles from the 淘砂處"%or_dist(TOKEN,GOLD.SITE))
	or_check(GOLD.step_block(world.state,"scoop",bag(),TOKEN)=="","scoop allowed (pure)")
	var before:Variant=or_canon(world.state)
	actions+=1
	var result:=world.act(TOKEN,"ore-journey-%d"%actions,GOLD.ACTION,GOLD.SITE,"scoop")
	or_check(result.ok==true and str(result.message)==GOLD.SCOOP_OK,"interleaved gold scoop ok (got ok=%s '%s')"%[str(result.ok),str(result.message)])
	var diffs:=[]
	or_all_diffs(before,or_canon(world.state),"state",diffs)
	var other:=[]
	for row:Dictionary in diffs:
		var path:=str(row.path)
		if not (path=="state.%s"%GOLD.STATE_KEY or path.begins_with("state.%s."%GOLD.STATE_KEY) or path.begins_with("state.players.%s.receipts"%TOKEN) or path=="state.committed"):other.append(row)
	or_check(other.is_empty() and not diffs.is_empty(),"gold scoop: whole-state diff only under gold_panning/receipts/committed (other %s)"%JSON.stringify(other.slice(0,5)))
	or_check(var_to_bytes(or_canon(world.state.get(ORE.STATE_KEY)))==ore_bytes and ORE.stage(world.state,TOKEN)==3,"gold scoop left the ore_route record byte-identical (stage 3)")
	or_check(or_same(GOLD.view(world.state,TOKEN),{"stage":1,"count":0,"total":0}),"gold record: stage 1, 0 today, 0 total")
	or_info.gold_record=or_canon(or_gold_record(TOKEN))
	or_steps.append("interleave | %s gold_pan scoop | %s"%[TOKEN,str(result.message)])

## 4. Next world day, two pushes, save -> reload, finish in the reloaded World.
func or_next_day() -> void:
	var day0:=ORE.today(world.state)
	var gold_bytes:=var_to_bytes(or_canon(world.state.get(GOLD.STATE_KEY)))
	var target:=(WEATHER.day_index(or_now())+1.0)*WEATHER.DAY_SECONDS+1.0
	or_wait_until(target)
	if failed:return
	var day1:=ORE.today(world.state)
	or_check(day1==day0+1,"fast-forwarded to world day %d (from %d)"%[day1,day0])
	or_check(or_same(ORE.view(world.state,TOKEN),{"stage":0,"count":0,"total":2}),"new day: view count 0, total 2")
	or_check(or_same(or_record(TOKEN),{"stage":0,"day":day0,"count":2,"total":2}),"raw record still day %d count 2 (nothing written by the clock)"%day0)
	or_check(var_to_bytes(or_canon(world.state.get(GOLD.STATE_KEY)))==gold_bytes,"the clock did not touch the gold record")
	or_check(ORE.step_block(world.state,"load",person(),TOKEN)=="","load allowed again on the new day (pure)")
	var coins0:=int(person().coins)
	var held:=or_nonzero(bag())
	or_go(TOKEN,"load","day-2 cart 1")
	or_go(TOKEN,"push","day-2 cart 1")
	or_go(TOKEN,"push","day-2 cart 1")
	if failed:return
	or_check(or_same(or_record(TOKEN),{"stage":3,"day":day0,"count":2,"total":2}),"mid-route record: stage 3, day/count of the last finished cart")
	or_check(ORE.count_today(world.state,TOKEN)==0 and ORE.total(world.state,TOKEN)==2,"mid-route view: 0 today, 2 total")
	var spot:=Vector2(float(person().x),float(person().y))
	or_reload("mid-route on day %d"%day1)
	if failed:return
	var rec:Dictionary=or_record(TOKEN)
	or_check(or_same(rec,{"stage":3,"day":day0,"count":2,"total":2}),"record survives the reload: stage 3")
	var ints:=true
	for field:String in ORE.RECORD_KEYS:
		if typeof(rec.get(field))!=TYPE_INT:ints=false
	or_check(ints,"reloaded record fields are ints %s"%JSON.stringify(rec))
	or_check(ORE.next_step(world.state,TOKEN)=="push" and ORE.pushes_left(3)==4,"after reload: next step push, 4 pushes left")
	or_check(world.player_region(TOKEN)==ORE.REGION and Vector2(float(person().x),float(person().y)).distance_to(spot)<=0.001,"A still in Jinguashi at the same spot after reload")
	while ORE.stage(world.state,TOKEN)<ORE.LAST and not failed:or_go(TOKEN,"push","day-2 cart 1 (after reload)")
	or_go(TOKEN,"unload","day-2 cart 1 (after reload)")
	if failed:return
	or_check(int(person().coins)==coins0+ORE.PAY and or_same(or_nonzero(bag()),held),"day-2 cart 1: coins +%d, inventory unchanged"%ORE.PAY)
	or_check(or_same(ORE.view(world.state,TOKEN),{"stage":0,"count":1,"total":3}),"day-2 view: count 1 (new day), total 3")
	or_check(or_same(or_record(TOKEN),{"stage":0,"day":day1,"count":1,"total":3}),"record day moved to %d"%day1)

## 5a. A loads another cart, pushes two segments and leaves Jinguashi with it.
func or_leave_with_cart() -> void:
	or_go(TOKEN,"load","day-2 cart 2 (left mid-route)")
	or_go(TOKEN,"push","day-2 cart 2 (left mid-route)")
	or_go(TOKEN,"push","day-2 cart 2 (left mid-route)")
	if failed:return
	or_info.left_record=or_canon(or_record(TOKEN))
	var rec_bytes:=var_to_bytes(or_canon(or_record(TOKEN)))
	or_act_ok(TOKEN,"transit",World.REGIONS.exit_cell(ORE.REGION),"home")
	if failed:return
	or_check(world.player_region(TOKEN)=="home","A transited home with a cart mid-route")
	or_deny(TOKEN,ORE.ACTION,ORE.cart_cell(3),"push",ORE.WRONG_REGION,"A pushes from home")
	or_deny(TOKEN,ORE.ACTION,ORE.STOPS[0],"load",ORE.WRONG_REGION,"A loads from home")
	or_check(var_to_bytes(or_canon(or_record(TOKEN)))==rec_bytes and ORE.stage(world.state,TOKEN)==3,"A's cart stays at stage 3 while A is home")

## 5b. Late joiner B runs a full cart while A is home.
func or_late_b() -> void:
	or_check(not world.state.players.has(OR_B),"B not in the save yet")
	world.add_player(OR_B,OR_B_NAME)
	var b:Dictionary=world.state.players[OR_B]
	or_check(world.player_region(OR_B)=="home" and int(b.inventory.get("reinforced_pick",0))==0,"B joined at home with no pick")
	or_check(not (world.state[ORE.STATE_KEY].players as Dictionary).has(OR_B) and or_same(ORE.view(world.state,OR_B),{"stage":0,"count":0,"total":0}),"B has no ore record")
	var a_bytes:=var_to_bytes(or_canon(world.state.players[TOKEN]))
	var a_rec:=var_to_bytes(or_canon(or_record(TOKEN)))
	or_deny(OR_B,ORE.ACTION,ORE.STOPS[0],"load",ORE.WRONG_REGION,"B loads from home")
	or_trip(OR_B)
	if failed:return
	or_check(world.player_region(OR_B)==ORE.REGION and world.player_region(TOKEN)=="home","B in Jinguashi, A at home")
	or_check(or_dist(OR_B,ORE.STOPS[0])>ORE.REACH,"B arrives %.2f tiles from the load platform"%or_dist(OR_B,ORE.STOPS[0]))
	or_deny(OR_B,ORE.ACTION,ORE.STOPS[0],"load",ORE.TOO_FAR,"B loads from the shuttle arrival")
	or_check(ORE.cart_cell(ORE.stage(world.state,OR_B))==ORE.STOPS[0],"B's own cart is at the load platform, not at A's stop")
	var coins0:=int(world.state.players[OR_B].coins)
	var held:=or_nonzero(or_bag(OR_B))
	or_go(OR_B,"load","B's cart")
	while ORE.stage(world.state,OR_B)<ORE.LAST and not failed:or_go(OR_B,"push","B's cart")
	or_go(OR_B,"unload","B's cart")
	if failed:return
	var day:=ORE.today(world.state)
	or_check(int(world.state.players[OR_B].coins)==coins0+ORE.PAY and or_same(or_nonzero(or_bag(OR_B)),held),"B: coins exactly +%d, inventory unchanged"%ORE.PAY)
	or_check(or_same(or_record(OR_B),{"stage":0,"day":day,"count":1,"total":1}) and or_same(ORE.view(world.state,OR_B),{"stage":0,"count":1,"total":1}),"B's own record: 1 today, 1 total")
	or_check(var_to_bytes(or_canon(world.state.players[TOKEN]))==a_bytes,"A's whole player record byte-identical through B's leg")
	or_check(var_to_bytes(or_canon(or_record(TOKEN)))==a_rec and ORE.stage(world.state,TOKEN)==3 and ORE.count_today(world.state,TOKEN)==1,"A's ore record unchanged by B (stage 3, 1 today)")
	or_check((world.state[ORE.STATE_KEY].players as Dictionary).size()==2,"two ore records: A and B")

## 6. A rides back; the cart is still at stage 3; A walks to it and finishes it.
func or_return() -> void:
	var rec_bytes:=var_to_bytes(or_canon(or_record(TOKEN)))
	or_trip(TOKEN)
	if failed:return
	or_check(world.player_region(TOKEN)==ORE.REGION,"A back in Jinguashi")
	or_check(var_to_bytes(or_canon(or_record(TOKEN)))==rec_bytes and ORE.stage(world.state,TOKEN)==3 and ORE.next_step(world.state,TOKEN)=="push","the cart is still at stage 3 after the round trip")
	var cell:=ORE.cart_cell(3)
	or_check(or_dist(TOKEN,cell)>ORE.REACH,"from the shuttle arrival A is %.2f tiles from the kept cart"%or_dist(TOKEN,cell))
	or_deny(TOKEN,ORE.ACTION,cell,"push",ORE.TOO_FAR,"push the kept cart from the shuttle arrival")
	var coins0:=int(person().coins)
	var held:=or_nonzero(bag())
	while ORE.stage(world.state,TOKEN)<ORE.LAST and not failed:or_go(TOKEN,"push","day-2 cart 2 (after the round trip)")
	or_go(TOKEN,"unload","day-2 cart 2 (after the round trip)")
	if failed:return
	or_check(int(person().coins)==coins0+ORE.PAY and or_same(or_nonzero(bag()),held),"A: coins exactly +%d, inventory unchanged"%ORE.PAY)
	or_check(or_same(ORE.view(world.state,TOKEN),{"stage":0,"count":2,"total":4}),"A's view: 2 today, 4 total")
	or_check(ORE.step_block(world.state,"load",person(),TOKEN)==ORE.DAILY_DONE,"A done for day 2 (pure DAILY_DONE)")

func or_final() -> void:
	var a_rec:Variant=or_canon(or_record(TOKEN))
	var b_rec:Variant=or_canon(or_record(OR_B))
	var gold:Variant=or_canon(or_gold_record(TOKEN))
	or_reload("final")
	if failed:return
	or_check(or_same(or_record(TOKEN),a_rec) and or_same(or_record(OR_B),b_rec),"both ore records identical after the final reload")
	or_check(or_same(ORE.view(world.state,TOKEN),{"stage":0,"count":2,"total":4}) and or_same(ORE.view(world.state,OR_B),{"stage":0,"count":1,"total":1}),"final views A {0,2,4} B {0,1,1}")
	or_check(or_same(or_gold_record(TOKEN),gold) and or_same(gold,or_info.get("gold_record",{})),"A's gold record (one scoop) untouched by every ore step and both reloads")
	or_check(or_changed==0,"every refusal left the world unchanged")

# ---------------------------------------------------------------- report

func or_report() -> void:
	if not or_started:
		print("ORE_ROUTE_JOURNEY did not reach the ore-cart segment")
		return
	print("ORE_ROUTE_JOURNEY info=%s"%JSON.stringify(or_info))
	for row in or_steps:print("ORE_ROUTE_JOURNEY step %s"%row)
	for i in or_refusals.size():print("ORE_ROUTE_JOURNEY refusal %d %s"%[i+1,or_refusals[i]])
	print("ORE_ROUTE_JOURNEY stats segment_actions=%d segment_walk_tiles=%d segment_world_seconds=%.1f segment_reloads=%d segment_refusals=%d all_refusals_state_unchanged=%s segment_check_count=%d segment_ms=%d passed=%s"%[actions-or_actions0,walking-or_walk0,or_now()-or_time0,or_reloads,or_refusals.size(),str(or_changed==0),checks-or_checks0,Time.get_ticks_msec()-or_ms,str(not failed)])

# ---------------------------------------------------------------- helpers

func or_check(condition:bool,message:String) -> bool:
	expect(condition,"ORE_ROUTE_JOURNEY: "+message)
	return condition

func or_now() -> float:
	return float(world.state.time)

func or_bag(token:String) -> Dictionary:
	return world.state.players[token].inventory

func or_dist(token:String,cell:Vector2i) -> float:
	var who:Dictionary=world.state.players[token]
	return Vector2(float(who.x),float(who.y)).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## The raw server ore record of `token` ({} when absent).
func or_record(token:String) -> Dictionary:
	var whole:Variant=world.state.get(ORE.STATE_KEY)
	if not whole is Dictionary or not whole.get("players") is Dictionary:return {}
	var own:Variant=whole.players.get(token)
	if not own is Dictionary:return {}
	return own

func or_gold_record(token:String) -> Dictionary:
	var whole:Variant=world.state.get(GOLD.STATE_KEY)
	if not whole is Dictionary or not whole.get("players") is Dictionary:return {}
	var own:Variant=whole.players.get(token)
	if not own is Dictionary:return {}
	return own

func or_wait_until(target:float) -> void:
	while or_now()<target-0.000001 and not failed:
		var dt:=minf(120.0,target-or_now())
		or_check(world.step(dt,true),"world step %.1f (%s)"%[dt,str(world.step_error)])

func or_trip(token:String) -> void:
	for leg:Array in OR_TRIP:
		if failed:return
		var points:Dictionary=World.TRANSIT.points(str(leg[0]))
		var cell:Vector2i=points[str(leg[1])].cell
		or_act_ok(token,"transit",cell,str(leg[2]))
		or_check(world.player_region(token)==str(leg[2]),"%s reached %s"%[token,str(leg[2])])

## Walk (real movement) to the cart's current cell, then do `step` there.
func or_go(token:String,step:String,label:String) -> void:
	if failed:return
	var cell:=ORE.cart_cell(ORE.stage(world.state,token))
	or_walk(token,cell)
	if failed:return
	or_check(or_dist(token,cell)<=ORE.REACH,"%s %s: %s walked to the cart at %s (%.2f)"%[label,step,token,str(cell),or_dist(token,cell)])
	or_step(token,step,label)

## A successful ore_cart step at the cart's current cell (no walking): exact message
## from an independent model, exact record, view, coin delta (+PAY on unload only),
## inventory identical, and a whole-state diff limited to the actor's record (+ coins
## on unload, the actor's receipts and the commit counter).
func or_step(token:String,step:String,label:String) -> void:
	if failed:return
	var s:=world.state
	var today:=ORE.today(s)
	var start:Dictionary=or_model.get(token,{"stage":0,"day":0,"count":0,"total":0})
	var model:Dictionary=start.duplicate()
	var who:Dictionary=s.players[token]
	or_check(ORE.next_step(s,token)==step,"%s %s: next step is %s (got %s)"%[label,step,step,ORE.next_step(s,token)])
	or_check(ORE.step_block(s,step,who,token)=="","%s %s: pure block empty (got '%s')"%[label,step,ORE.step_block(s,step,who,token)])
	var cell:=ORE.cart_cell(int(model["stage"]))
	or_check(ORE.cart_cell(ORE.stage(s,token))==cell,"%s %s: model cart cell %s matches"%[label,step,str(cell)])
	var message:=""
	var old_stage:=int(model["stage"])
	match step:
		"load":
			model["stage"]=1
			message=ORE.LOAD_OK
		"push":
			model["stage"]=old_stage+1
			message=ORE.PUSH_LAST if old_stage+1==ORE.LAST else ORE.PUSH_OK%[old_stage,ORE.LAST-(old_stage+1)]
		_:
			var done:=int(model["count"]) if int(model["day"])==today else 0
			model["stage"]=0
			model["day"]=today
			model["count"]=done+1
			model["total"]=int(model["total"])+1
			message=ORE.UNLOAD_OK%[ORE.PAY,int(model["count"])]
	var coins_before:=int(who.coins)
	var held:=or_nonzero(or_bag(token))
	var had_key:=world.state.has(ORE.STATE_KEY)
	var before:Variant=or_canon(world.state)
	actions+=1
	var result:=world.act(token,"ore-journey-%d"%actions,ORE.ACTION,cell,step)
	or_check(result.ok==true and str(result.message)==message,"%s %s: ok '%s' (got ok=%s '%s')"%[label,step,message,str(result.ok),str(result.message)])
	or_check(or_same(or_record(token),model),"%s %s: record %s (want %s)"%[label,step,JSON.stringify(or_canon(or_record(token))),JSON.stringify(or_canon(model))])
	var coins_after:=int(world.state.players[token].coins)
	or_check(coins_after==coins_before+(ORE.PAY if step=="unload" else 0),"%s %s: coins %d -> %d"%[label,step,coins_before,coins_after])
	or_check(or_same(or_nonzero(or_bag(token)),held),"%s %s: inventory unchanged"%[label,step])
	var shown:={"stage":int(model.stage),"count":int(model.count) if int(model.day)==today else 0,"total":int(model.total)}
	or_check(or_same(ORE.view(world.state,token),shown),"%s %s: view %s"%[label,step,JSON.stringify(shown)])
	var allowed:=["state.%s.players.%s"%[ORE.STATE_KEY,token],"state.players.%s.receipts"%token,"state.committed"]
	allowed.append("state.ledger")
	if not had_key:allowed.append("state.%s"%ORE.STATE_KEY)
	if step=="unload":allowed.append("state.players.%s.coins"%token)
	var diffs:=[]
	or_all_diffs(before,or_canon(world.state),"state",diffs)
	var other:=[]
	for row:Dictionary in diffs:
		var ok:=false
		for prefix:String in allowed:
			if str(row.path)==prefix or str(row.path).begins_with(prefix+"."):ok=true
		if not ok:other.append(row)
	or_check(other.is_empty() and not diffs.is_empty(),"%s %s: whole-state diff only under %s (other %s)"%[label,step,str(allowed),JSON.stringify(other.slice(0,5))])
	or_model[token]=model
	or_steps.append("%s | %s %s at %s | %s | day %d | record %s | coins %d"%[label,token,step,str(cell),str(result.message),today,JSON.stringify(or_canon(model)),coins_after])

## Refused with the exact message; whole World.state unchanged (== and canonical bytes).
## pure: Route.step_block must say the same.
func or_deny(token:String,action:String,target:Vector2i,extra:String,message:String,label:String,walk:=false,pure:=false) -> Dictionary:
	if failed:return {}
	if walk:or_walk(token,target)
	if failed:return {}
	if pure:
		var block:=ORE.step_block(world.state,extra,world.state.players[token],token)
		or_check(block==message,"%s: pure block agrees '%s' (got '%s')"%[label,message,block])
	actions+=1
	var state_before:=world.state.duplicate(true)
	var bytes_before:=var_to_bytes(or_canon(world.state))
	var result:=world.act(token,"ore-journey-%d"%actions,action,target,extra)
	or_check(not result.ok and str(result.message)==message,"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var unchanged:=world.state==state_before and var_to_bytes(or_canon(world.state))==bytes_before
	or_check(unchanged,label+": whole world state unchanged")
	if not unchanged:or_changed+=1
	or_refusals.append("%s | %s %s %s %s | %s | state_unchanged=%s"%[label,token,action,str(target),extra,str(result.message),str(unchanged)])
	return result

## A successful action by `token` after walking near the target; exact message unless "".
func or_act_ok(token:String,action:String,target:Vector2i,extra:String,message:="") -> Dictionary:
	if failed:return {}
	or_walk(token,target)
	if failed:return {}
	actions+=1
	var result:=world.act(token,"ore-journey-%d"%actions,action,target,extra)
	print("%d %s %s %s %s | %s"%[actions,token,action,str(target),extra,str(result.message)])
	or_check(result.ok==true and (message.is_empty() or str(result.message)==message),"%s %s %s at %s: ok '%s' (got ok=%s '%s')"%[token,action,extra,str(target),message,str(result.ok),str(result.message)])
	return result

## Same BFS walk as the parent's walk_to/route, for any token.
func or_walk(token:String,target:Vector2i,reach:float=2.0) -> void:
	if failed:return
	var path:=or_route(token,target,reach)
	if path.is_empty():
		or_check(false,"%s: no path to %s"%[token,str(target)])
		return
	for index in range(1,path.size()):
		var direction:=Vector2(path[index]-path[index-1])
		for step in range(4):world.move_player(token,direction,0.25/3.6)
		walking+=1
		var who:Dictionary=world.state.players[token]
		var cell:Vector2i=path[index]
		if not or_check(Vector2(float(who.x),float(who.y)).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=0.001,"%s movement followed the passable route"%token):return

func or_route(token:String,target:Vector2i,reach:float) -> Array:
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
## (numbers 1e-6; only zero load defaults may appear), check the ore/gold records, rejoin
## the active tokens and continue in the reloaded World.
func or_reload(label:String) -> void:
	if failed:return
	or_check(world.save(),label+": explicit save")
	var reopened:=World.new()
	if not or_check(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,label+": fresh World loads the primary save through SaveSchema"):return
	var diffs:=[]
	or_all_diffs(or_canon(world.state),or_canon(reopened.state),"state",diffs)
	var defaults:=[]
	var real:=[]
	for row:Dictionary in diffs:
		if str(row.kind)=="added_on_load" and (row.value is int or row.value is float) and float(row.value)==0.0:defaults.append(row.path)
		else:real.append(row)
	or_check(real.is_empty(),label+": whole canonical state identical after reload %s"%JSON.stringify(real.slice(0,5)))
	or_check(var_to_bytes(or_canon(world.state.get(ORE.STATE_KEY)))==var_to_bytes(or_canon(reopened.state.get(ORE.STATE_KEY))),label+": ore_route record identical")
	or_check(var_to_bytes(or_canon(world.state.get(GOLD.STATE_KEY)))==var_to_bytes(or_canon(reopened.state.get(GOLD.STATE_KEY))),label+": gold_panning record identical")
	var copy:Dictionary=reopened.state.duplicate(true)
	or_check(ORE.valid(copy),label+": reloaded ore_route passes Route.valid")
	reopened.save_path=world.save_path
	for token in world.active_tokens:reopened.add_player(str(token),str(world.state.players[token].name))
	world=reopened
	or_reloads+=1
	print("ORE_ROUTE_JOURNEY reload (%s) world_seconds=%.1f identical=%s load_defaults=%s"%[label,or_now(),str(real.is_empty()),str(defaults)])

func or_nonzero(inv:Dictionary) -> Dictionary:
	var out:={}
	for item in inv:
		if int(inv[item])!=0:out[str(item)]=int(inv[item])
	return out

func or_same(a:Variant,b:Variant) -> bool:
	return var_to_bytes(or_canon(a))==var_to_bytes(or_canon(b))

## Every difference (up to 40): {"path","kind":"changed"|"added_on_load"|"lost_on_load","value"}.
static func or_all_diffs(a:Variant,b:Variant,path:String,out:Array) -> void:
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
			else:or_all_diffs(a[k],b[k],"%s.%s"%[path,str(k)],out)
		for k in b:
			if not a.has(k):out.append({"path":"%s.%s"%[path,str(k)],"kind":"added_on_load","value":b[k]})
		return
	if a is Array:
		if a.size()!=b.size():
			out.append({"path":path,"kind":"changed","value":"size %d vs %d"%[a.size(),b.size()]})
			return
		for i in a.size():or_all_diffs(a[i],b[i],"%s[%d]"%[path,i],out)
		return
	if a!=b:out.append({"path":path,"kind":"changed","value":"%s vs %s"%[str(a).left(60),str(b).left(60)]})

## Sorted String keys, Vector2i as [x,y], integral floats as int (JSON reload safe).
static func or_canon(value:Variant) -> Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			var source:Variant=value[k] if value.has(k) else value[StringName(k)]
			out[k]=or_canon(source)
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(or_canon(item))
		return list
	if value is Vector2i:return [value.x,value.y]
	if value is float and is_finite(value) and floorf(value)==value:return int(value)
	return value
