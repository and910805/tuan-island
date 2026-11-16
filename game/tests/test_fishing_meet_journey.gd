extends "res://tests/test_flower_journey.gd"
## T071 natural fishing-meet journey (河岸釣魚會): a FRESH single-player World plays
## from a brand-new save, through the chapter-one steps and the 渡口野餐, to two
## settled fishing-meet rounds.
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
## One player, one process, one World at a time (reloads are in-process
## World.new().load_world on the same save file). Everything goes through
## World.act (after walking cell by cell with World.move_player along passable
## tiles) and World.step(dt,true).
##
## WALKING IS FREE IN THIS HARNESS: World.move_player moves the avatar but never
## advances state.time. So that the 300 s round is played against the clock, this
## file advances the clock with World.step (same mechanism as the harvest-relay and
## market journeys) by
##   * tiles_walked / 3.6 world seconds after every walking leg inside a round
##     (3.6 tiles/s is the full-input speed coded in World.move_player),
##   * ACTION_SECONDS (1.0 s, an assumed click/animation cost) after every action
##     attempted inside a round (meet actions, casts, easy catches, refusals), and
##   * TRACK_SECONDS (0.8 s, an assumed key-press cadence) after every press of the
##     standard (追魚影) tracking catch inside a round.
## The fish bite is waited for with World.step up to player.fishing.ready (the
## 3 s bite delay coded in World fish_start). Outside a round the clock only moves
## through chapter-one waits and explicit waits.
##
## Prerequisite (reused parent logic, unmodified): test_flower_journey.chapter_one()
## — chapter one earned on a fresh world. Its act() calls are intercepted only to
## insert the pre-picnic leg (three LOCKED refusals + one ordinary cast/catch in the
## future meet waters; no rod item exists in the game — fishing needs no tool)
## right before the picnic action. SKIPPED: chapters two to five.
##
## Meet leg (all via World.act, rules in res://scripts/fishing_meet.gd):
##  * refusals after the picnic: too far from the sign (at the notice board),
##    wrong tile (the rock beside the sign, a water cell), stale round id, join /
##    leave before any round, leave with an extra;
##  * round 1: start beside the sign, refusals while active, walk to the shore,
##    records by real fish_start -> bite wait -> fish_catch (easy + one standard),
##    whole player record (minus receipts/fishing/fish_meet) unchanged per record,
##    species sequence recomputed independently from ORDER; one cast outside WATERS
##    while joined (fish to the backpack by normal rules); save + in-process reload
##    with the line in the water mid-round; continue until the round settles;
##    tickets == tickets_for(species,records), paid once, later steps pay nothing;
##  * cooldown refusal, cooldown waited through; round 2: start (auto-join), leave,
##    rejoin with fish_meet_join, leave again, no catch, time-out, exactly one
##    participation ticket, later steps pay nothing;
##  * final save -> reload: round state, record, backpack, coins, position.
## Every refusal: exact message, whole World.state unchanged (canonicalized
## var_to_bytes compare). NOT preset: this file writes no state field (inventory,
## coins, flags, fish_meet, position, time). Prints FISH_MEET_JOURNEY lines and
## FISH_MEET_JOURNEY_TESTS checks=N failures=M.

const M=preload("res://scripts/fishing_meet.gd")
const WALK_TILES_PER_SECOND:=3.6
const ACTION_SECONDS:=1.0
const TRACK_SECONDS:=0.8
const ADJACENT:=1.5
## Independent copy of the documented species order (fishing_meet.gd header).
const DOC_ORDER:=["carp","minnow","carp","redfish","minnow","carp","loach","minnow"]
const SHORE_SPOT:=Vector2i(54,36)   # shore cell: 2.0 from the sign, 1.0 from water 55,36
const OUTSIDE:=Vector2i(55,33)      # river water just north of WATERS, 3.16 from SHORE_SPOT
const ROCK:=Vector2i(54,37)         # fixed rock right beside the sign
const BOARD_CELL:=Vector2i(40,29)

var pre_picnic_done:=false
var refusals:=0
var meet_actions:=0
var clock_on:=false
var meet_walk_start:=0
var meet_time_start:=0.0
var walk_seconds:=0.0
var action_seconds:=0.0
var bite_seconds:=0.0
var round_one:={}
var round_two:={}
var pre_picnic_fish:=""
var started_ms:=0

func expect(condition:bool,message:String) -> bool:
	checks+=1
	if not condition:
		failures+=1
		failed=true
		push_error("FISH_MEET_JOURNEY FAIL: "+message)
	return condition

func finish() -> void:
	print("FISH_MEET_JOURNEY label=\"%s\" actions=%d meet_actions=%d walk_tiles=%d meet_walk_tiles=%d world_seconds=%.1f meet_world_seconds=%.1f walk_seconds_added=%.1f action_seconds_added=%.1f bite_seconds_waited=%.1f reloads=%d refusals=%d pre_picnic_fish=%s round_one=%s round_two=%s runtime_ms=%d"%[LABEL,actions,meet_actions,walking,walking-meet_walk_start,float(world.state.get("time",0.0)),float(world.state.get("time",0.0))-meet_time_start,walk_seconds,action_seconds,bite_seconds,reloads,refusals,pre_picnic_fish,JSON.stringify(round_one),JSON.stringify(round_two),Time.get_ticks_msec()-started_ms])
	print("FISH_MEET_JOURNEY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ---------------------------------------------------------------- journey

func run() -> void:
	started_ms=Time.get_ticks_msec()
	tok=TOKEN_A
	world.add_player(TOKEN_A,"Bloom A")
	expect(not world.state.has("fish_meet") and not person().has("fish_meet") and not M.unlocked(world.state),"fresh world: meet locked, no round, no record")
	expect(independent_order_matches(),"documented ORDER/kind_at formula equals fishing_meet.kind_at for rounds 1..3")
	chapter_one()
	if failed:return
	if not expect(pre_picnic_done,"pre-picnic leg ran"):return
	expect(world.state.picnic==true and M.unlocked(world.state) and World.fish_meet_available(world.state),"picnic done: meet unlocked and the sign cell is free")
	expect(world.blocked(M.SIGN),"after the picnic the sign cell is reserved (blocked)")
	expect(not world.state.has("fish_meet") and not person().has("fish_meet"),"picnic writes no fish_meet field")
	print("FISH_MEET_JOURNEY chapter one + picnic done (checks %d, actions %d, world_seconds %.1f, walk_tiles %d)"%[checks,actions,now(),walking])
	meet_walk_start=walking
	meet_time_start=now()
	before_any_round()
	if failed:return
	play_round_one()
	if failed:return
	play_round_two()
	if failed:return
	var bag_final:=nonzero(bag())
	var coins_final:=int(person().coins)
	var pos_final:=Vector2(person().x,person().y)
	persist("final")
	if failed:return
	var own:=M.record(person())
	expect_same(own,{"tickets":int(round_one.tickets)+int(round_two.tickets),"rounds":2,"best":maxi(int(round_one.records),0),"paid_round":2},"final reload: record")
	var v:=world.fish_meet_view(tok)
	expect(int(v.tickets)==int(own.tickets) and int(v.rounds)==2 and int(v.best)==int(own.best) and int(v.round)==2 and v.active==false,"final reload: view tickets/rounds/best/round agree (%s)"%JSON.stringify([v.tickets,v.rounds,v.best,v.round,v.active]))
	expect_same(nonzero(bag()),bag_final,"final reload: backpack")
	expect(int(person().coins)==coins_final,"final reload: coins")
	expect(Vector2(person().x,person().y).distance_to(pos_final)<0.001,"final reload: position")

func independent_order_matches() -> bool:
	for r in range(1,4):
		for i in range(16):
			if str(DOC_ORDER[(r*3+i*5)%8])!=M.kind_at(r,i):return false
	return true

func expected_kind(round_id:int,index:int) -> String:
	return str(DOC_ORDER[(round_id*3+index*5)%8])

## Intercepts the reused chapter_one() right before its picnic action.
func act(action:String,target:Vector2i,extra:String="") -> Dictionary:
	if action=="picnic" and not pre_picnic_done and not failed:
		pre_picnic_done=true
		pre_picnic()
	return super.act(action,target,extra)

func pre_picnic() -> void:
	expect(not world.state.picnic,"before the picnic: picnic false")
	walk_near(M.SIGN)
	meet_refuse("fish_meet_start",M.SIGN,"0",M.LOCKED,"start before the picnic")
	meet_refuse("fish_meet_join",M.SIGN,"0",M.LOCKED,"join before the picnic")
	meet_refuse("fish_meet_leave",M.SIGN,"",M.LOCKED,"leave before the picnic")
	expect(not world.blocked(M.SIGN),"before the picnic the sign cell is not reserved")
	go_shore()
	if failed:return
	var caught:=normal_catch(Vector2i(55,36),"pre-picnic cast in the future meet waters")
	pre_picnic_fish=caught
	expect(not world.state.has("fish_meet") and not person().has("fish_meet"),"no fish_meet field written before the picnic")

# ---------------------------------------------------------------- refusals before round 1

func before_any_round() -> void:
	var far:=Vector2(person().x,person().y).distance_to(Vector2(M.SIGN)+Vector2(0.5,0.5))
	expect(far>M.SIGN_REACH,"after the picnic the player stands %.2f tiles from the sign"%far)
	meet_refuse("fish_meet_start",M.SIGN,"0",M.TOO_FAR_SIGN,"start from the notice board, too far from the sign")
	meet_refuse("fish_meet_join",M.SIGN,"0",M.TOO_FAR_SIGN,"join from the notice board, too far from the sign")
	walk_near(M.SIGN)
	if failed:return
	meet_refuse("fish_meet_start",ROCK,"0",M.WRONG_SIGN,"start on the rock tile beside the sign")
	meet_refuse("fish_meet_start",Vector2i(55,37),"0",M.WRONG_SIGN,"start on a water tile")
	meet_refuse("fish_meet_start",M.SIGN,"1",M.STALE,"start with a stale round id")
	meet_refuse("fish_meet_join",M.SIGN,"0",M.NOT_ACTIVE,"join before any round")
	meet_refuse("fish_meet_leave",M.SIGN,"",M.NOT_ACTIVE,"leave before any round")
	meet_refuse("fish_meet_leave",M.SIGN,"x",M.BAD_EXTRA,"leave with an extra")
	expect(not world.state.has("fish_meet") and not person().has("fish_meet"),"pre-round refusals wrote no fish_meet field")

# ---------------------------------------------------------------- round 1

func play_round_one() -> void:
	var bag_start:=nonzero(bag())
	var coins_start:=int(person().coins)
	var core_start:=core()
	var walk_start:=walking
	var start_time:=now()
	var result:=meet_act("fish_meet_start",M.SIGN,str(int(world.fish_meet_view(tok).round)))
	if failed:return
	clock_on=true
	spend(ACTION_SECONDS)
	expect(str(result.message)=="第 1 輪河岸釣魚會開始！在告示牌旁的河面拋竿，5 分鐘內一起記錄 12 筆魚種。釣到的魚記進魚種卡後放回河裡，背包不會變動。","start message: "+str(result.message))
	var meet:=M.round_state(world.state)
	expect(int(meet.round)==1 and meet.active==true and is_equal_approx(float(meet.started),start_time) and is_equal_approx(float(meet.ends),start_time+M.DURATION),"round 1 active, ends = started + %.0f"%M.DURATION)
	expect_same(meet.participants,{tok:M.fresh_entry()},"round 1: the starter is the only participant")
	expect(not person().has("fish_meet"),"no personal record before settlement")
	meet_refuse("fish_meet_start",M.SIGN,"1",M.ALREADY_ACTIVE,"start again while active")
	meet_refuse("fish_meet_join",M.SIGN,"1",M.ALREADY_JOINED,"join a round already joined")
	meet_refuse("fish_meet_join",M.SIGN,"0",M.STALE,"join with a stale round id")
	trip_shore()
	if failed:return
	var casts:=water_cells_in_reach()
	if not expect(casts.size()>=4,"at least four WATERS cells within 3.2 of the shore spot (%d)"%casts.size()):return
	var records:=0
	var sequence:=[]
	var outside_done:=false
	var reloaded:=false
	var standard_done:=false
	var outside_fish:=""
	for guard in 40:
		if failed or M.round_state(world.state).active!=true:break
		if records==3 and not outside_done:
			outside_done=true
			outside_fish=normal_catch(OUTSIDE,"joined, cast outside WATERS")
			if failed:return
			continue
		var mode:=""
		if records==4 and not standard_done:
			standard_done=true
			mode="standard"
		var reload_label:=""
		if records==6 and not reloaded:
			reloaded=true
			reload_label="mid-round, line in the water (record %d next)"%(records+1)
		var kind:=meet_record(casts[records%casts.size()],mode,reload_label)
		if failed:return
		if kind.is_empty():break
		sequence.append(kind)
		records+=1
	clock_on=false
	if failed:return
	expect(reloaded and outside_done and standard_done,"round 1 included the reload, the outside cast and a standard catch")
	meet=M.round_state(world.state)
	if not expect(meet.active==false and int((meet.last as Dictionary).get("round",0))==1,"round 1 settled"):return
	var last:Dictionary=meet.last
	var total:=int(meet.records)
	var species:=M.species_count(meet.species)
	var tickets:=M.tickets_for(species,total)
	expect(total==records,"round state records %d == records made %d"%[total,records])
	var expected_seq:=[]
	for i in range(total):expected_seq.append(expected_kind(1,i))
	expect_same(sequence,expected_seq,"round 1 species sequence equals the independently computed ORDER sequence")
	expect_same(meet.species,species_after_doc(1,total),"round 1 species card equals the independent count")
	expect(int(last.records)==total and int(last.species)==species and int(last.tickets)==tickets and int(last.players)==1,"last: records %d species %d tickets %d players 1 (%s)"%[total,species,tickets,JSON.stringify(last)])
	expect(str(last.reason)==("goal" if total>=M.GOAL else "time"),"settled by %s"%str(last.reason))
	expect(is_equal_approx(float(meet.ready),float(last.finished)+M.COOLDOWN),"ready = finished + cooldown")
	expect_same(M.record(person()),{"tickets":tickets,"rounds":1,"best":total,"paid_round":1},"round 1 record: tickets_for(%d,%d)=%d paid once"%[species,total,tickets])
	expect(int(person().coins)==coins_start,"after round 1 coins equal the pre-round coins")
	# The only backpack change is the single outside-WATERS fish.
	var expected_bag:=bag_start.duplicate()
	expected_bag[outside_fish]=int(expected_bag.get(outside_fish,0))+1
	expect_same(nonzero(bag()),expected_bag,"after round 1 the backpack is the pre-round backpack + the one outside fish (%s)"%outside_fish)
	expect(int(person().get("fish_caught",0))==int(core_start.get("fish_caught",0))+1,"fish_caught grew only by the outside catch")
	round_one={"records":total,"species":species,"reason":str(last.reason),"tickets":tickets,
		"world_seconds":snappedf(float(last.finished)-start_time,0.01),"walk_tiles":walking-walk_start,
		"seconds_left":snappedf(float(meet.ends)-float(last.finished),0.01),"outside_fish":outside_fish,"sequence":sequence}
	print("FISH_MEET_JOURNEY round 1 %s"%JSON.stringify(round_one))
	var record_before:=M.record(person()).duplicate(true)
	var meet_before:=M.round_state(world.state).duplicate(true)
	wait(30.0)
	expect_same(M.record(person()),record_before,"30 s later: no second payout")
	expect_same(M.round_state(world.state),meet_before,"30 s later: round 1 result unchanged")

func species_after_doc(round_id:int,n:int) -> Dictionary:
	var out:={"carp":0,"minnow":0,"redfish":0,"loach":0}
	for i in range(n):
		var k:=expected_kind(round_id,i)
		out[k]=int(out[k])+1
	return out

# ---------------------------------------------------------------- round 2: join, leave, no catch

func play_round_two() -> void:
	var meet:=M.round_state(world.state)
	walk_near(M.SIGN,M.SIGN_REACH)
	var left:=float(meet.ready)-now()
	if expect(left>0.0,"still in the cooldown (%.1f s left)"%left):
		meet_refuse("fish_meet_start",M.SIGN,"1",M.COOLDOWN_MSG%ceili(left),"start during the cooldown")
	var v:=world.fish_meet_view(tok)
	expect(v.can_start==false and float(v.cooldown)>0.0,"view: cooldown %.1f, cannot start"%float(v.cooldown))
	wait(float(M.round_state(world.state).ready)-now()+0.5)
	if failed:return
	expect(bool(world.fish_meet_view(tok).can_start),"cooldown waited through: can start")
	var bag_start:=nonzero(bag())
	var coins_start:=int(person().coins)
	var core_start:=core()
	var record_start:=M.record(person()).duplicate(true)
	var result:=meet_act("fish_meet_start",M.SIGN,str(int(world.fish_meet_view(tok).round)))
	if failed:return
	clock_on=true
	spend(ACTION_SECONDS)
	expect(str(result.message).begins_with("第 2 輪河岸釣魚會開始！"),"round 2 start message: "+str(result.message))
	expect(int(M.round_state(world.state).last.round)==1,"round 2 keeps round 1 as the last result")
	meet_refuse("fish_meet_join",M.SIGN,"2",M.ALREADY_JOINED,"join round 2 already joined by starting")
	result=meet_act("fish_meet_leave",M.SIGN,"")
	spend(ACTION_SECONDS)
	expect(str(result.message)=="離開河岸釣魚會。背包沒有變動；你的參與紀錄會保留到這一輪結算。","leave message: "+str(result.message))
	meet_refuse("fish_meet_leave",M.SIGN,"",M.NOT_JOINED,"leave twice")
	result=meet_act("fish_meet_join",M.SIGN,"2")
	spend(ACTION_SECONDS)
	expect(str(result.message)=="加入第 2 輪河岸釣魚會！在告示牌旁的河面釣到的魚會記進魚種卡後放回河裡，背包不會變動。","join message: "+str(result.message))
	expect_same(M.round_state(world.state).participants,{tok:{"caught":0,"joined":true}},"rejoined: same entry, caught 0")
	result=meet_act("fish_meet_leave",M.SIGN,"")
	spend(ACTION_SECONDS)
	var entry:Dictionary=M.round_state(world.state).participants[tok]
	expect(entry.joined==false and int(entry.caught)==0,"left: not joined, nothing caught")
	expect_same(M.record(person()),record_start,"leaving pays nothing yet")
	if failed:return
	var walked:=trip_walk(BOARD_CELL,2.0)
	clock_on=false
	expect(walked>0,"walked back toward the notice board (%d tiles)"%walked)
	wait(float(M.round_state(world.state).ends)-now()+0.5)
	if failed:return
	meet=M.round_state(world.state)
	if not expect(meet.active==false and int((meet.last as Dictionary).get("round",0))==2,"round 2 settled by time"):return
	var last:Dictionary=meet.last
	var tickets:=M.tickets_for(0,0)
	expect(tickets==1 and str(last.reason)=="time" and int(last.records)==0 and int(last.species)==0 and int(last.tickets)==tickets and int(last.players)==1,"round 2 last: %s"%JSON.stringify(last))
	expect_same(M.record(person()),{"tickets":int(record_start.tickets)+1,"rounds":2,"best":int(record_start.best),"paid_round":2},"round 2: exactly one participation ticket")
	expect_same(nonzero(bag()),bag_start,"after round 2 the whole backpack equals the pre-round backpack")
	expect(int(person().coins)==coins_start,"after round 2 coins equal the pre-round coins")
	var core_now:=core()
	core_now.erase("x")
	core_now.erase("y")
	core_start.erase("x")
	core_start.erase("y")
	expect(same(core_now,core_start),"after round 2 the player record (minus position/receipts/fishing/fish_meet) is unchanged")
	var record_after:=M.record(person()).duplicate(true)
	wait(120.0)
	expect_same(M.record(person()),record_after,"120 s after round 2: no second payout")
	round_two={"records":0,"reason":str(last.reason),"tickets":tickets,"walk_tiles":walked}
	print("FISH_MEET_JOURNEY round 2 %s record=%s"%[JSON.stringify(round_two),JSON.stringify(M.record(person()))])

# ---------------------------------------------------------------- fishing

## WATERS cells within the fishing reach of the shore spot (row order).
func water_cells_in_reach() -> Array:
	var out:=[]
	var centre:=Vector2(SHORE_SPOT)+Vector2(0.5,0.5)
	for cell:Vector2i in M.water_cells():
		if centre.distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2 and world.water(cell):out.append(cell)
	return out

## One meet record by a real cast. Returns the recorded kind ("" when the round
## ended before the catch). The whole player record minus receipts / fishing /
## fish_meet is compared before the cast and after the catch.
func meet_record(cell:Vector2i,mode:String,reload_label:String) -> String:
	if failed:return ""
	var before:=core()
	var meet:=M.round_state(world.state)
	var index:=int(meet.index)
	var kind:=expected_kind(int(meet.round),index)
	expect(kind==M.kind_at(int(meet.round),index),"independent kind %s == kind_at(%d,%d)"%[kind,int(meet.round),index])
	var cast:=plain_act("fish_start",cell,mode)
	if failed:return ""
	expect(str(cast.message)=="魚竿放好了。等提示出現，再按空白鍵收竿","cast message: "+str(cast.message))
	spend(ACTION_SECONDS)
	if not reload_label.is_empty():
		var line:Dictionary=person().fishing.duplicate(true)
		var was:=clock_on
		clock_on=false
		persist(reload_label)
		clock_on=was
		if failed:return ""
		expect_same(person().get("fishing"),line,"reloaded world keeps the cast line")
		expect(M.round_state(world.state).active==true and int(M.round_state(world.state).records)==index,"reloaded world: round 1 still active with %d records"%index)
	var ready:=float(person().fishing.ready)
	if now()<ready:
		bite_seconds+=ready-now()
		wait(ready-now())
	if failed:return ""
	if M.round_state(world.state).active!=true:
		expect(false,"the round ended while waiting for a bite (records %d)"%index)
		return ""
	var result:={}
	if mode=="standard":
		var adjustments:=0
		for attempt in range(30):
			result=plain_act("fish_catch",cell,"")
			if failed:return ""
			if not person().has("fishing"):break
			adjustments+=1
			expect(str(result.message)=="已對準魚影。留在亮帶內會累積進度，滿格後收竿。","tracking adjustment message: "+str(result.message))
			expect(int(M.round_state(world.state).records)==index,"a tracking adjustment is not a record")
			spend(TRACK_SECONDS)
		expect(not person().has("fishing"),"standard tracking completed")
		expect(adjustments>=1,"standard catch needed %d tracking adjustments"%adjustments)
		print("FISH_MEET_JOURNEY standard catch after %d tracking adjustments"%adjustments)
	else:
		result=plain_act("fish_catch",cell,"")
	if failed:return ""
	spend(ACTION_SECONDS)
	var after:=M.round_state(world.state)
	var records:=index+1
	if records>=M.GOAL:
		expect(str(result.message)=="釣到了%s！記進釣魚會的魚種卡後放回河裡，背包沒有變動。%d 筆紀錄全部完成，參加者各得 %d 張紀念票。"%[M.kind_name(kind),M.GOAL,M.tickets_for(M.species_count(species_after_doc(int(after.round),records)),M.GOAL)],"goal catch message: "+str(result.message))
	else:
		var count:=M.species_count(species_after_doc(int(after.round),records))
		expect(str(result.message)=="釣到了%s！記進釣魚會的魚種卡後放回河裡，背包沒有變動。大家記錄了 %d / %d 筆、%d / %d 種。"%[M.kind_name(kind),records,M.GOAL,count,M.KINDS.size()],"catch message %d: %s"%[records,str(result.message)])
	expect(str(result.get("fish_meet",""))==kind,"result names the recorded kind %s"%kind)
	expect(int(after.records)==records and int(after.index)==records and int(after.participants[tok].caught)==records,"records %d -> %d"%[index,records])
	expect_same(after.species,species_after_doc(int(after.round),records),"species card after %d records"%records)
	expect(not person().has("fishing"),"line reeled in after record %d"%records)
	expect(same(core(),before),"record %d (%s): whole player record unchanged (bag, coins, fish_caught, pity, collection)"%[records,kind])
	return kind

## An ordinary cast + catch: exactly one fish into the backpack, fish_caught +1,
## the meet card untouched. Returns the fish id.
func normal_catch(cell:Vector2i,label:String) -> String:
	if failed:return ""
	var bag_before:=nonzero(bag())
	var caught:=int(person().get("fish_caught",0))
	var meet_before:Variant=world.state.get("fish_meet",{}).duplicate(true)
	plain_act("fish_start",cell,"")
	spend(ACTION_SECONDS)
	if failed:return ""
	var ready:=float(person().fishing.ready)
	if now()<ready:
		bite_seconds+=ready-now()
		wait(ready-now())
	var result:=plain_act("fish_catch",cell,"")
	spend(ACTION_SECONDS)
	if failed:return ""
	var fish:=""
	var diff:={}
	var after:=nonzero(bag())
	for item in after:
		var d:=int(after[item])-int(bag_before.get(item,0))
		if d!=0:diff[item]=d
	for item in bag_before:
		if not after.has(item):diff[item]=-int(bag_before[item])
	if diff.size()==1:fish=str(diff.keys()[0])
	expect(diff.size()==1 and int(diff.values()[0])==1 and World.Collections.FISH.has(fish),"%s: exactly one fish entered the backpack (%s)"%[label,JSON.stringify(diff)])
	expect(str(result.message).begins_with("釣到了") and str(result.message).contains("種子攤") and not result.has("fish_meet"),"%s: ordinary catch message (%s)"%[label,str(result.message)])
	expect(int(person().get("fish_caught",0))==caught+1,"%s: fish_caught +1"%label)
	expect(person().collection.fish.has(fish),"%s: %s in the collection"%[label,fish])
	expect_same(world.state.get("fish_meet",{}),meet_before,"%s: meet card untouched"%label)
	print("FISH_MEET_JOURNEY %s -> %s (%s)"%[label,fish,str(result.message)])
	return fish

# ---------------------------------------------------------------- persistence

func persist(label:String) -> void:
	if failed:return
	expect(world.save(),label+": explicit save")
	var expected:Dictionary=person().duplicate(true)
	var meet_before:Variant=world.state.get("fish_meet",{}).duplicate(true)
	var view_before:=world.fish_meet_view(tok)
	var time_before:=now()
	var reopened:=World.new()
	if not expect(reopened.load_world(save_path) and not reopened.recovered_from_backup,label+": save loads in a plain in-process World"):return
	reopened.save_path=save_path
	reopened.add_player(TOKEN_A,"Bloom A")
	world=reopened
	reloads+=1
	for field in ["region","x","y","inventory","coins","fish_caught","collection","fish_meet","fishing"]:
		expect_same(person().get(field),expected.get(field),label+": player %s preserved"%field)
	expect_same(world.state.get("fish_meet",{}),meet_before,label+": round state preserved")
	expect_same(world.fish_meet_view(tok),view_before,label+": meet view preserved")
	expect(absf(now()-time_before)<0.001,label+": world time preserved (%.3f vs %.3f)"%[now(),time_before])
	var v:=world.fish_meet_view(tok)
	print("FISH_MEET_JOURNEY reload (%s) time=%.1f round=%d active=%s joined=%s records=%d tickets=%d"%[label,now(),int(v.round),str(v.active),str(v.joined),int(v.records),int(v.tickets)])

# ---------------------------------------------------------------- helpers

## Walk to a passable cell within `reach` of target. Returns tiles walked.
func walk_near(target:Vector2i,reach:float=ADJACENT) -> int:
	if failed:return 0
	if Vector2(person().x,person().y).distance_to(Vector2(target)+Vector2(0.5,0.5))<=reach:return 0
	var path:=route(target,reach)
	if path.is_empty():
		expect(false,"no path to %s (reach %.1f)"%[str(target),reach])
		return 0
	for index in range(1,path.size()):
		var direction:=Vector2(path[index]-path[index-1])
		for s in range(4):world.move_player(tok,direction,0.25/3.6)
		walking+=1
		if not expect(Vector2(person().x,person().y).distance_to(Vector2(path[index])+Vector2(0.5,0.5))<=0.001,"movement followed a passable route"):return index
	return path.size()-1

## Stand exactly on the shore spot (the only standable cell within 1.0 of 55,36).
func go_shore() -> int:
	var tiles:=walk_near(Vector2i(55,36),1.0)
	expect(Vector2(person().x,person().y).distance_to(Vector2(SHORE_SPOT)+Vector2(0.5,0.5))<=0.001,"standing on the shore spot %s"%str(SHORE_SPOT))
	return tiles

func trip_shore() -> void:
	var tiles:=go_shore()
	if tiles>0 and clock_on:
		walk_seconds+=float(tiles)/WALK_TILES_PER_SECOND
		wait(float(tiles)/WALK_TILES_PER_SECOND)

func trip_walk(target:Vector2i,reach:float=ADJACENT) -> int:
	var tiles:=walk_near(target,reach)
	if failed or tiles<=0:return tiles
	if clock_on:
		walk_seconds+=float(tiles)/WALK_TILES_PER_SECOND
		wait(float(tiles)/WALK_TILES_PER_SECOND)
	return tiles

func spend(seconds:float) -> void:
	if clock_on and not failed:
		action_seconds+=seconds
		wait(seconds)

## Any successful action (fishing or meet) through World.act.
func plain_act(action:String,target:Vector2i,extra:String) -> Dictionary:
	if failed:return {"ok":false,"message":"skipped"}
	actions+=1
	meet_actions+=1
	var result:=world.act(tok,"fishmeet-journey-%d"%actions,action,target,extra)
	expect(result.ok,"%s %s at %s: %s"%[action,extra,str(target),str(result.message)])
	return result

## A successful meet action: never touches backpack, coins or the player core.
func meet_act(action:String,target:Vector2i,extra:String) -> Dictionary:
	if failed:return {"ok":false,"message":"skipped"}
	var before:=core()
	var result:=plain_act(action,target,extra)
	expect(same(core(),before),action+": player record (minus receipts/fishing/fish_meet) unchanged")
	return result

## Exact message and the whole World.state unchanged (canonical compare).
func meet_refuse(action:String,target:Vector2i,extra:String,message:String,label:String) -> void:
	if failed:return
	var state_before:=world.state.duplicate(true)
	var bytes_before:=var_to_bytes(canon(world.state))
	actions+=1
	meet_actions+=1
	var result:=world.act(tok,"fishmeet-journey-%d"%actions,action,target,extra)
	expect(not result.ok and str(result.message)==message,"%s: '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	expect(var_to_bytes(canon(world.state))==bytes_before and world.state==state_before,label+": whole world state unchanged")
	refusals+=1
	spend(ACTION_SECONDS)

## The player record minus fields an action legitimately touches outside the
## activity: request receipts, the cast line and the activity record itself.
func core() -> Dictionary:
	var p:Dictionary=person().duplicate(true)
	for field in ["receipts","fishing","fish_meet"]:p.erase(field)
	return p

## Recursively canonicalizes JSON-ish data: sorted String keys, whole floats as ints.
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
	if value is float and is_finite(value) and floorf(value)==value:return int(value)
	return value

static func same(a:Variant,b:Variant) -> bool:
	return var_to_bytes(canon(a))==var_to_bytes(canon(b))

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
