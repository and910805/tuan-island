extends "res://tests/test_flower_journey.gd"
## T071 natural harvest-relay journey (豐收接力): a FRESH single-player World plays
## from a brand-new save, through the chapter-one steps and the 渡口野餐, to two
## settled relay rounds.
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
## One player, one process, one World at a time (reloads are in-process
## World.new().load_world on the same save file). Everything goes through
## World.act (after walking cell by cell with World.move_player along passable
## tiles) and World.step(dt,true).
##
## WALKING IS FREE IN THIS HARNESS: World.move_player moves the avatar but never
## advances state.time (on a real server time advances because the server ticks
## while the client walks). So that the 180 s round is played against the clock,
## this file advances the clock with World.step (the same wait() mechanism as the
## market journey) by
##   * tiles_walked / 3.6 world seconds after every walking leg inside a round
##     (3.6 tiles/s is the full-input speed coded in World.move_player), and
##   * ACTION_SECONDS (1.0 s, an assumed click/animation cost) after every relay
##     action attempted inside a round (successes and refusals alike).
## Outside a round (pre-round refusals, cooldown, waiting for time-out) the clock
## only moves through explicit waits.
##
## Prerequisite (reused parent logic, unmodified): test_flower_journey.chapter_one()
## — chapter one earned on a fresh world (crops, ship, donate, irrigation, stove,
## soup + bread, ferry picnic). Its act() calls are intercepted only to insert the
## six LOCKED refusals right before the picnic action. SKIPPED: chapters two to five.
##
## Relay leg (all via World.act, HARVEST rules in res://scripts/harvest_relay.gd):
##  * natural refusals after the picnic: start from too far, stale round id,
##    pick / sort / join / leave / pass before any round;
##  * round 1: start at the sign, empty-handed sort, then crate -> basket trips
##    with one hands-full pick and one wrong-basket sort; save + in-process reload
##    mid-round while carrying; continue on the reloaded world until the round
##    settles (goal or time, whichever a solo player really reaches);
##    tickets == tickets_for(delivered), paid once, further steps pay nothing,
##    backpack and coins equal their pre-round values;
##  * cooldown refusal, cooldown waited through; round 2: pick, leave while
##    holding, refusals after leaving, time-out, exactly one participation payout;
##  * final save -> reload: round state, records and tickets preserved.
## Every refusal: exact message, whole World.state unchanged, backpack and coins
## compared. NOT preset: this file writes no state field (inventory, coins, flags,
## harvest_relay, position, time). Prints HARVEST_JOURNEY lines and
## HARVEST_RELAY_JOURNEY_TESTS checks=N failures=M.

const H=preload("res://scripts/harvest_relay.gd")
const WALK_TILES_PER_SECOND:=3.6
const ACTION_SECONDS:=1.0
const ADJACENT:=1.5

var pre_picnic_done:=false
var refusals:=0
var relay_actions:=0
var clock_on:=false
var relay_walk_start:=0
var relay_time_start:=0.0
var walk_seconds:=0.0
var action_seconds:=0.0
var round_one:={}
var round_two:={}
var started_ms:=0

func expect(condition:bool,message:String) -> bool:
	checks+=1
	if not condition:
		failures+=1
		failed=true
		push_error("HARVEST_JOURNEY FAIL: "+message)
	return condition

func finish() -> void:
	print("HARVEST_JOURNEY label=\"%s\" actions=%d relay_actions=%d walk_tiles=%d relay_walk_tiles=%d world_seconds=%.1f relay_world_seconds=%.1f walk_seconds_added=%.1f action_seconds_added=%.1f reloads=%d refusals=%d round_one=%s round_two=%s runtime_ms=%d"%[LABEL,actions,relay_actions,walking,walking-relay_walk_start,float(world.state.get("time",0.0)),float(world.state.get("time",0.0))-relay_time_start,walk_seconds,action_seconds,reloads,refusals,JSON.stringify(round_one),JSON.stringify(round_two),Time.get_ticks_msec()-started_ms])
	print("HARVEST_RELAY_JOURNEY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ---------------------------------------------------------------- journey

func run() -> void:
	started_ms=Time.get_ticks_msec()
	tok=TOKEN_A
	world.add_player(TOKEN_A,"Bloom A")
	expect(not world.state.has("harvest_relay") and not person().has("harvest_relay") and not H.unlocked(world.state),"fresh world: relay locked, no round, no record")
	chapter_one()
	if failed:return
	if not expect(pre_picnic_done,"pre-picnic relay refusals ran"):return
	expect(world.state.picnic==true and H.unlocked(world.state) and World.harvest_available(world.state),"picnic done: relay unlocked and the five cells are free")
	expect(not world.state.has("harvest_relay") and not person().has("harvest_relay"),"picnic writes no relay field")
	print("HARVEST_JOURNEY chapter one + picnic done (checks %d, actions %d, world_seconds %.1f, walk_tiles %d)"%[checks,actions,now(),walking])
	relay_walk_start=walking
	relay_time_start=now()
	before_any_round()
	if failed:return
	play_round_one()
	if failed:return
	play_round_two()
	if failed:return
	persist("final")
	if failed:return
	var own:=H.record(person())
	expect(int(own.tickets)==int(round_one.tickets)+int(round_two.tickets) and int(own.rounds)==2 and int(own.paid_round)==2 and int(own.best)==maxi(int(round_one.delivered),int(round_two.delivered)),"final reload: record %s"%JSON.stringify(own))

## Intercepts the reused chapter_one() right before its picnic action.
func act(action:String,target:Vector2i,extra:String="") -> Dictionary:
	if action=="picnic" and not pre_picnic_done and not failed:
		pre_picnic_done=true
		pre_picnic()
	return super.act(action,target,extra)

func pre_picnic() -> void:
	expect(not world.state.picnic,"before the picnic: picnic false")
	var root:Vector2i=H.BASKETS.root
	var tries:=[["harvest_start",H.SIGN,"0"],["harvest_join",H.SIGN,"0"],["harvest_leave",H.SIGN,""],
		["harvest_pick",H.CRATE,""],["harvest_pass",H.CRATE,""],["harvest_sort",root,""]]
	for t in tries:
		walk_near(t[1])
		relay_refuse(t[0],t[1],t[2],H.LOCKED,"%s before the picnic"%t[0])
	expect(not world.state.has("harvest_relay") and not person().has("harvest_relay"),"no relay field written before the picnic")

# ---------------------------------------------------------------- refusals before round 1

func before_any_round() -> void:
	# The picnic leaves the player at the board (40,29), well away from the sign.
	var far:=Vector2(person().x,person().y).distance_to(Vector2(H.SIGN)+Vector2(0.5,0.5))
	expect(far>H.SIGN_REACH,"after the picnic the player stands %.2f tiles from the sign"%far)
	relay_refuse("harvest_start",H.SIGN,"0",H.TOO_FAR_SIGN,"start from the board, too far from the sign")
	walk_near(H.SIGN)
	relay_refuse("harvest_start",H.SIGN,"1",H.STALE,"start with a stale round id")
	relay_refuse("harvest_join",H.SIGN,"0",H.NOT_ACTIVE,"join before any round")
	relay_refuse("harvest_leave",H.SIGN,"",H.NOT_ACTIVE,"leave before any round")
	walk_near(H.CRATE)
	relay_refuse("harvest_pick",H.CRATE,"",H.NOT_ACTIVE,"pick before any round")
	relay_refuse("harvest_pass",H.CRATE,"",H.NOT_ACTIVE,"pass before any round")
	walk_near(H.BASKETS.leaf)
	relay_refuse("harvest_sort",H.BASKETS.leaf,"",H.NOT_ACTIVE,"sort with empty hands before any round")
	expect(not world.state.has("harvest_relay") and not person().has("harvest_relay"),"pre-round refusals wrote no relay field")

# ---------------------------------------------------------------- round 1

func play_round_one() -> void:
	walk_near(H.SIGN)
	var bag_start:=bag().duplicate(true)
	var coins_start:=int(person().coins)
	var walk_start:=walking
	var start_time:=now()
	var result:=relay_act("harvest_start",H.SIGN,str(int(world.harvest_view(tok).round)))
	if failed:return
	expect(str(result.message).begins_with("第 1 輪豐收接力開始！"),"start message: "+str(result.message))
	var relay:=H.round_state(world.state)
	expect(int(relay.round)==1 and relay.active==true and is_equal_approx(float(relay.started),start_time) and is_equal_approx(float(relay.ends),start_time+H.DURATION),"round 1 active, ends = started + %.0f"%H.DURATION)
	expect_same(relay.participants,{tok:H.fresh_entry()},"round 1: the starter is the only participant")
	expect(not person().has("harvest_relay"),"no personal record before settlement")
	clock_on=true
	relay_refuse("harvest_start",H.SIGN,"1",H.ALREADY_ACTIVE,"start again while active")
	relay_refuse("harvest_join",H.SIGN,"1",H.ALREADY_JOINED,"join a round already joined")
	relay_refuse("harvest_pass",H.SIGN,"",H.EMPTY_HANDS,"pass with empty hands")
	trip_walk(H.BASKETS.root)
	relay_refuse("harvest_sort",H.BASKETS.root,"",H.EMPTY_HANDS,"sort with empty hands")
	var trips:=0
	var reloaded:=false
	var wrong_done:=false
	var full_done:=false
	var no_target_done:=false
	for guard in 200:
		if failed or H.round_state(world.state).active!=true:break
		trip_walk(H.CRATE)
		if failed or H.round_state(world.state).active!=true:break
		var index:=int(H.round_state(world.state).index)
		var kind:=H.kind_at(1,index)
		result=relay_act("harvest_pick",H.CRATE,"")
		if failed:return
		var basket:=H.basket_of(kind)
		expect(str(result.message)=="拿到%s，送到「%s」籃，或傳給隊友。"%[H.kind_name(kind),str(H.BASKET_NAMES[basket])],"pick message: "+str(result.message))
		expect(str(world.harvest_view(tok).carry)==kind and int(H.round_state(world.state).index)==index+1,"carrying %s (index %d)"%[kind,index])
		expect_same(nonzero(bag()),nonzero(bag_start),"model vegetables never enter the backpack")
		if not full_done:
			full_done=true
			relay_refuse("harvest_pick",H.CRATE,"",H.HANDS_FULL,"pick again with full hands")
		if not no_target_done:
			no_target_done=true
			relay_refuse("harvest_pass",H.CRATE,"",H.NO_TARGET,"pass with no teammate nearby")
		if trips==10 and not reloaded:
			reloaded=true
			clock_on=false
			persist("mid-round carrying %s"%kind)
			clock_on=true
			if failed:return
			expect(str(world.harvest_view(tok).carry)==kind and H.round_state(world.state).active==true,"reloaded world still carries %s in round 1"%kind)
		if not wrong_done:
			wrong_done=true
			var wrong:String=H.BASKET_ORDER[(H.BASKET_ORDER.find(basket)+1)%H.BASKET_ORDER.size()]
			trip_walk(H.BASKETS[wrong])
			if failed or H.round_state(world.state).active!=true:break
			relay_refuse("harvest_sort",H.BASKETS[wrong],"",H.WRONG_BASKET%[H.kind_name(kind),str(H.BASKET_NAMES[basket]),str(H.BASKET_NAMES[basket])],"sort %s into the %s basket"%[kind,wrong])
		trip_walk(H.BASKETS[basket])
		if failed or H.round_state(world.state).active!=true:break
		var delivered:=int(H.round_state(world.state).delivered)
		result=relay_act("harvest_sort",H.BASKETS[basket],"")
		if failed:return
		trips+=1
		if delivered+1>=H.GOAL:
			expect(str(result.message)=="%s放進「%s」籃！%d 個全部分類完成，參加者各得 %d 張紀念票。"%[H.kind_name(kind),str(H.BASKET_NAMES[basket]),H.GOAL,H.tickets_for(H.GOAL)],"goal sort message: "+str(result.message))
		else:
			expect(str(result.message)=="%s放進「%s」籃！大家完成了 %d / %d。"%[H.kind_name(kind),str(H.BASKET_NAMES[basket]),delivered+1,H.GOAL],"sort message: "+str(result.message))
		expect(int(H.round_state(world.state).delivered)==delivered+1,"delivered %d -> %d"%[delivered,delivered+1])
	clock_on=false
	if failed:return
	expect(reloaded,"the mid-round reload happened")
	relay=H.round_state(world.state)
	if not expect(relay.active==false and int((relay.last as Dictionary).get("round",0))==1,"round 1 settled"):return
	var last:Dictionary=relay.last
	var delivered_total:=int(relay.delivered)
	var tickets:=H.tickets_for(delivered_total)
	expect(int(last.delivered)==delivered_total and int(last.tickets)==tickets and int(last.players)==1,"last: delivered %d tickets %d players 1"%[delivered_total,tickets])
	expect(str(last.reason)==("goal" if delivered_total>=H.GOAL else "time"),"settled by %s"%str(last.reason))
	expect_same(H.record(person()),{"tickets":tickets,"rounds":1,"best":delivered_total,"paid_round":1},"round 1 record: tickets_for(%d)=%d paid once"%[delivered_total,tickets])
	expect_same(nonzero(bag()),nonzero(bag_start),"after round 1 the whole backpack equals the pre-round backpack")
	expect(int(person().coins)==coins_start,"after round 1 coins equal the pre-round coins")
	round_one={"delivered":delivered_total,"trips":trips,"reason":str(last.reason),"tickets":tickets,
		"world_seconds":snappedf(float(last.finished)-start_time,0.01),"walk_tiles":walking-walk_start,
		"seconds_left":snappedf(float(relay.ends)-float(last.finished),0.01)}
	print("HARVEST_JOURNEY round 1 %s"%JSON.stringify(round_one))
	# Stepping further pays nothing.
	var record_before:=H.record(person()).duplicate(true)
	var relay_before:=H.round_state(world.state).duplicate(true)
	wait(30.0)
	expect_same(H.record(person()),record_before,"30 s later: no second payout")
	expect_same(H.round_state(world.state),relay_before,"30 s later: round 1 result unchanged")

# ---------------------------------------------------------------- round 2: leave while holding

func play_round_two() -> void:
	var relay:=H.round_state(world.state)
	walk_near(H.SIGN)
	var left:=float(relay.ready)-now()
	if expect(left>0.0,"still in the cooldown (%.1f s left)"%left):
		relay_refuse("harvest_start",H.SIGN,"1",H.COOLDOWN_MSG%ceili(left),"start during the cooldown")
	wait(float(H.round_state(world.state).ready)-now()+0.5)
	if failed:return
	expect(bool(world.harvest_view(tok).can_start),"cooldown waited through: can start")
	var bag_start:=bag().duplicate(true)
	var coins_start:=int(person().coins)
	var record_start:=H.record(person()).duplicate(true)
	var result:=relay_act("harvest_start",H.SIGN,str(int(world.harvest_view(tok).round)))
	if failed:return
	expect(str(result.message).begins_with("第 2 輪豐收接力開始！"),"round 2 start message: "+str(result.message))
	clock_on=true
	trip_walk(H.CRATE)
	var kind:=H.kind_at(2,0)
	relay_act("harvest_pick",H.CRATE,"")
	if failed:return
	expect(str(world.harvest_view(tok).carry)==kind,"round 2: carrying %s"%kind)
	result=relay_act("harvest_leave",H.CRATE,"")
	if failed:return
	expect(str(result.message)=="離開豐收接力。模型蔬菜放回菜箱，背包沒有變動；你的參與紀錄會保留到這一輪結算。","leave message: "+str(result.message))
	var entry:Dictionary=H.round_state(world.state).participants[tok]
	expect(entry.joined==false and str(entry.carry)=="" and entry.relay==false,"left: not joined, hands empty")
	expect_same(nonzero(bag()),nonzero(bag_start),"leaving while holding leaves the backpack unchanged")
	expect(int(person().coins)==coins_start,"leaving changes no coins")
	expect_same(H.record(person()),record_start,"leaving pays nothing yet")
	relay_refuse("harvest_pick",H.CRATE,"",H.NOT_JOINED,"pick after leaving")
	relay_refuse("harvest_leave",H.CRATE,"",H.NOT_JOINED,"leave twice")
	clock_on=false
	if failed:return
	walk_to(BOARD_CELL)
	wait(float(H.round_state(world.state).ends)-now()+0.5)
	if failed:return
	relay=H.round_state(world.state)
	if not expect(relay.active==false and int((relay.last as Dictionary).get("round",0))==2,"round 2 settled by time"):return
	var last:Dictionary=relay.last
	var tickets:=H.tickets_for(0)
	expect(str(last.reason)=="time" and int(last.delivered)==0 and int(last.tickets)==tickets and int(last.players)==1,"round 2 last: %s"%JSON.stringify(last))
	expect_same(H.record(person()),{"tickets":int(record_start.tickets)+tickets,"rounds":2,"best":int(record_start.best),"paid_round":2},"round 2: exactly one participation payout")
	expect_same(nonzero(bag()),nonzero(bag_start),"after round 2 the whole backpack equals the pre-round backpack")
	expect(int(person().coins)==coins_start,"after round 2 coins equal the pre-round coins")
	var record_after:=H.record(person()).duplicate(true)
	wait(120.0)
	expect_same(H.record(person()),record_after,"120 s after round 2: no second payout")
	round_two={"delivered":0,"reason":str(last.reason),"tickets":tickets,"carried_when_leaving":kind}
	print("HARVEST_JOURNEY round 2 %s record=%s"%[JSON.stringify(round_two),JSON.stringify(H.record(person()))])

const BOARD_CELL:=Vector2i(40,29)

# ---------------------------------------------------------------- persistence

func persist(label:String) -> void:
	if failed:return
	expect(world.save(),label+": explicit save")
	var expected:Dictionary=person().duplicate(true)
	var relay_before:Variant=world.state.get("harvest_relay",{}).duplicate(true)
	var view_before:=world.harvest_view(tok)
	var time_before:=now()
	var reopened:=World.new()
	if not expect(reopened.load_world(save_path) and not reopened.recovered_from_backup,label+": save loads in a plain in-process World"):return
	reopened.save_path=save_path
	reopened.add_player(TOKEN_A,"Bloom A")
	world=reopened
	reloads+=1
	for field in ["region","x","y","inventory","coins","harvest_relay"]:
		expect_same(person().get(field),expected.get(field),label+": player %s preserved"%field)
	expect_same(world.state.get("harvest_relay"),relay_before,label+": round state preserved")
	expect_same(world.harvest_view(tok),view_before,label+": relay view preserved")
	expect(absf(now()-time_before)<0.001,label+": world time preserved (%.3f vs %.3f)"%[now(),time_before])
	print("HARVEST_JOURNEY reload (%s) in-process World.new().load_world time=%.1f view_round=%d active=%s carry=%s delivered=%d"%[label,now(),int(world.harvest_view(tok).round),str(world.harvest_view(tok).active),str(world.harvest_view(tok).carry),int(world.harvest_view(tok).delivered)])

# ---------------------------------------------------------------- relay helpers

## Walk to a passable cell within `reach` (default: adjacent, inside HAND_REACH).
## Always routes (unlike walk_to, which stops 2.5 tiles out). Returns tiles walked.
func walk_near(target:Vector2i,reach:float=ADJACENT) -> int:
	if failed:return 0
	if Vector2(person().x,person().y).distance_to(Vector2(target)+Vector2(0.5,0.5))<=reach:return 0
	var path:=route(target,reach)
	if path.is_empty():
		expect(false,"no path to %s"%str(target))
		return 0
	for index in range(1,path.size()):
		var direction:=Vector2(path[index]-path[index-1])
		for s in range(4):world.move_player(tok,direction,0.25/3.6)
		walking+=1
		if not expect(Vector2(person().x,person().y).distance_to(Vector2(path[index])+Vector2(0.5,0.5))<=0.001,"movement followed a passable route"):return index
	return path.size()-1

## A walking leg inside a round: the free walk plus tiles/3.6 world seconds.
func trip_walk(target:Vector2i) -> void:
	var tiles:=walk_near(target)
	if failed or tiles<=0:return
	var seconds:=float(tiles)/WALK_TILES_PER_SECOND
	walk_seconds+=seconds
	wait(seconds)

func spend_action_time() -> void:
	if clock_on and not failed:
		action_seconds+=ACTION_SECONDS
		wait(ACTION_SECONDS)

## A successful relay action: never touches backpack or coins.
func relay_act(action:String,target:Vector2i,extra:String) -> Dictionary:
	if failed:return {"ok":false,"message":"skipped"}
	var before:=bag().duplicate(true)
	var coins:=int(person().coins)
	actions+=1
	relay_actions+=1
	var result:=world.act(tok,"harvest-journey-%d"%actions,action,target,extra)
	expect(result.ok,"%s %s at %s: %s"%[action,extra,str(target),str(result.message)])
	expect_same(nonzero(bag()),nonzero(before),action+": backpack unchanged")
	expect(int(person().coins)==coins,action+": coins unchanged")
	spend_action_time()
	return result

## Exact message, whole World.state unchanged, backpack and coins compared.
func relay_refuse(action:String,target:Vector2i,extra:String,message:String,label:String) -> void:
	if failed:return
	var before:=bag().duplicate(true)
	var coins:=int(person().coins)
	var state_before:=world.state.duplicate(true)
	actions+=1
	relay_actions+=1
	var result:=world.act(tok,"harvest-journey-%d"%actions,action,target,extra)
	expect(not result.ok and str(result.message)==message,"%s: '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	expect(world.state==state_before,label+": state unchanged")
	expect_same(nonzero(bag()),nonzero(before),label+": backpack unchanged")
	expect(int(person().coins)==coins,label+": coins unchanged")
	refusals+=1
	spend_action_time()

func nonzero(inv:Dictionary) -> Dictionary:
	var out:={}
	for item in inv:
		if int(inv[item])!=0:out[str(item)]=int(inv[item])
	return out

func now() -> float:
	return float(world.state.time)

func wait(seconds:float,chunk:float=240.0) -> void:
	var left:=seconds
	while left>0.000001 and not failed:
		var dt:=minf(chunk,left)
		expect(world.step(dt,true),"world step %.2f"%dt)
		left-=dt
