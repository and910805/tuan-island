extends "res://tests/test_water_tower_journey.gd"
## Chapter 40「定量分區配水」natural journey: a FRESH temp world, ONE player, ONE process
## (reloads are in-process World.new().load_world on the same save file; after each
## reload the journey continues in the reloaded World).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
##
## Prerequisite reuse (disclosed): this file EXTENDS the unmodified
## test_water_tower_journey.gd (-> test_lanyang_revisit_journey.gd -> history -> garden
## -> regions -> chapter journeys), exactly as that file extends the Lanyang revisit
## journey. The whole chain (including the tower journey's own legs and report) runs
## first; this file continues in after_chapter() from the state it leaves:
##   PUMP(53,20) TANK(52,20) PIPE_A(52,21) S1(52,22) GATE(52,23) TOWER(52,24) S2(52,25),
##   near crops (51,22)(53,22), far crops (51,25)(53,25)(52,26) (mature), gate 「餘水」,
##   pump on, both sprinklers on, a freshly re-placed tower (出水, no settings).
##
## Everything goes through World.act (after World.move_player along BFS routes) and
## World.step(dt,true). NO direct writes by this file to inventory, coins, flags,
## objects, crops, positions or time. Disclosed exceptions / read-only helpers:
##  * After the mid-day save -> reload, the PREVIOUS (pre-reload) World instance is kept
##    as an unsaved in-memory continuation: its save_path is set to "" (World.save()
##    then writes nothing) and it is stepped in lock-step with the reloaded world; the
##    network objects, the 8 crops and the clocks are compared after every step. This
##    is a field of a discarded World object, not game state of the journey world.
##  * Expected numbers come from an independent per-step model (tq_model) of the
##    documented plan order (pump -> S1 (full zone) -> S2 (low zone) -> tower refill
##    above `reserve` -> tower discharge into S2 capped by today's `quota`), the
##    calendar wetness rule (wet ends at midnight, rain re-wets exposed plots) and the
##    sprinkler rule (one water per dry owned crop, offsets UP/RIGHT/DOWN/LEFT, only when
##    next_water <= step end). It reads the live state before each step and predicts
##    [tank,S1,S2,tower], the tower's quota_day/quota_used and every crop's wet flag.
##  * WALKING IS FREE (parent rule): move_player never advances state.time.
##  * Single player: another islander's tower (TOWER_NOT_OWNER for a foreign tower) and
##    the fifth-tower limit are not walkable here (rule/session tests cover them).
##
## Journey (derived expectations):
##  1. Upstream tower: none of reserve/quota/quota_day/quota_used; tower_report 0/0/-1.
##  2. Refusals, whole state unchanged each time: 12 malformed / off-panel extras
##     (TOWER_BAD_SETTING), "reserve:0" and "quota:0" on the fresh tower
##     (TOWER_SAME_SETTING), tower_set on the gate, S2 and a crop cell (TOWER_NOT_OWNER),
##     tower_set from the workbench (too far).
##  3. Gate 餘水, pump on, "reserve:24": per 8 s round the model gives the exact
##     [tank,S1,S2,tower]; with full sprinklers the tank climbs 8 per round to 24 while
##     the tower takes nothing, then the tank stays at exactly 24 and the tower gains the
##     pump's 8 per round. Every round in which the tower rose ends with tank >= 24
##     (== 24 unless the tower is full). Contrast: the same pre-state with reserve 0
##     (the upstream rule, whose recorded fill log has the tank at 0 while the tower
##     fills) leaves the tank at 0 in those rounds.
##  4. Gate 關閉, "quota:4" (quota_day = today, quota_used 0), 只蓄水 for whole days until
##     S2 has spent all its water on the 3 far crops (3 per dry day, 0 on rain): the
##     tower holds and the quota record is untouched (stale day reads as 0 sent).
##     Day A: back to 出水 -> the next round sends exactly 4 (S2 0 -> 4, tower -4,
##     quota_used 4) where the unlimited rule would send 12; then nothing more that day.
##  5. Day A: "quota:8" keeps today's 4 -> the next round sends 4 more (used 8); then
##     "quota:4" keeps used 8 -> nothing more is sent although S2 still needs water.
##  6. Save -> reload mid-day A: tower object (settings, quota_day, quota_used)
##     identical; stepping continues in lock-step with the unsaved world. The round
##     that crosses midnight still counts for day A (nothing sent); the first day-B round
##     sends min(4, need) with quota_used reset to that amount.
##     Then 4 more days under quota 4: each world day <= 4 sent, tower drops <= 4
##     between observations, and whenever S2 is below 12 after the morning the quota
##     (not the tower's stock) was the limit (upstream unlimited: S2 back to 12 daily).
##  7. Move the tower beside the line and back (move_object): the object, settings
##     included, is identical; no inventory change.
##  8. "quota:0" removes quota/quota_day/quota_used together, "reserve:0" removes reserve;
##     rounds then equal the upstream journey's own model (tw_model) exactly: closed ->
##     S2 topped up to 12 in one round, low -> tank leftovers all go into the tower.
##  9. Remove: exactly one kit back; place again: fresh tower without settings; final
##     save -> reload.
## Prints TOWER_QUOTA_JOURNEY lines; the last checks=N failures=M line is the chapter base's.

const TQ_RESERVE:=24
const TQ_QUOTA:=4
const TQ_RAISED:=8
const TQ_BASE_KEYS:=["enabled","items","owner","type","water"]
const TQ_SETTING_KEYS:=["reserve","quota","quota_day","quota_used"]
const TQ_MOVE_CANDIDATES:=[Vector2i(51,24),Vector2i(53,24),Vector2i(50,24),Vector2i(54,24)]
const TQ_BAD_EXTRAS:=["water:5","reserve:10","quota:5","quota:04","quota:-4","reserve:+12","reserve:12:1","reserve","QUOTA:4","quota:4.0","reserve:96",""]

var tq_ms:=0
var tq_actions0:=0
var tq_walk0:=0
var tq_time0:=0.0
var tq_waited0:=0.0
var tq_reloads0:=0
var tq_rej0:=0
var tq_changed0:=0
var tq_checks0:=0
var tq_steps:=0
var tq_shadow=null
var tq_shadow_steps:=0
var tq_midnight_blocked:=0
var tq_sent_by_day:={}
var tq_day_log:=[]
var tq_info:={}

# ---------------------------------------------------------------- journey

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	tq_ms=Time.get_ticks_msec()
	tq_actions0=actions
	tq_walk0=walking
	tq_time0=now()
	tq_waited0=waited
	tq_reloads0=reloads
	tq_rej0=rejections.size()
	tq_changed0=rejections_changed
	tq_checks0=checks
	print("TOWER_QUOTA_JOURNEY prerequisite chain passed (checks %d, actions %d, world_seconds %.1f, day %d)"%[checks,actions,now(),day()])
	tq_fresh_leg()
	if not failed:tq_refusal_leg()
	if not failed:tq_reserve_leg()
	if not failed:tq_quota_leg()
	if not failed:tq_move_leg()
	if not failed:tq_reset_leg()
	if not failed:tq_remove_leg()
	tq_shadow=null
	tq_report()

func tq_fresh_leg() -> void:
	var tower:=obj(TW)
	tq_check(world.player_region(TOKEN)=="home","start: at home")
	tq_check(str(tower.get("type",""))==IND.TOWER_KIND and tower.get("owner")==TOKEN and tower.get("enabled")==true,"upstream left my tower at %s, 出水 (%s)"%[str(TW),str(tower)])
	tq_check(tq_settings(tower).is_empty() and tq_keys(tower)==TQ_BASE_KEYS,"before any setting the tower has none of reserve/quota/quota_day/quota_used (%s)"%str(tq_keys(tower)))
	var rep:=IND.tower_report(world.state,World.key(TW))
	tq_check(rep.ok and int(rep.reserve)==0 and int(rep.quota)==0 and int(rep.quota_used)==0 and int(rep.quota_left)==-1,"tower_report: reserve 0, quota 0 (不限), quota_left -1 (%s)"%str(rep))
	tq_check(str(obj(GATE).get("mode",""))=="low" and obj(PUMP).get("enabled")==true and obj(S1).get("enabled")==true and obj(S2).get("enabled")==true and IND.near_river(world,PUMP),"upstream network: gate low, pump on near the river, both sprinklers on")
	tq_check(is_equal_approx(IND.TOWER_DAY,WEATHER.DAY_SECONDS),"quota world day = calendar day (%.0f s)"%IND.TOWER_DAY)
	for cell:Vector2i in NEAR+FAR:
		var c:=crop(cell)
		tq_check(str(c.kind)!="" and str(c.get("owner",""))==TOKEN and not world.state.roofs.has(World.key(cell)),"crop %s is mine and exposed (%s)"%[str(cell),str(c.kind)])
	tq_info.start={"seconds":now(),"day":day(),"row":tw_row()}

func tq_refusal_leg() -> void:
	for extra:String in TQ_BAD_EXTRAS:
		deny(IND.TOWER_SET_ACTION,TW,extra,IND.TOWER_BAD_SETTING,"tower_set '%s' (not a panel value)"%extra)
	deny(IND.TOWER_SET_ACTION,TW,"reserve:0",IND.TOWER_SAME_SETTING,"reserve:0 on a fresh tower",false)
	deny(IND.TOWER_SET_ACTION,TW,"quota:0",IND.TOWER_SAME_SETTING,"quota:0 on a fresh tower",false)
	deny(IND.TOWER_SET_ACTION,GATE,"reserve:12",IND.TOWER_NOT_OWNER,"tower_set on the diversion gate")
	deny(IND.TOWER_SET_ACTION,S2,"quota:4",IND.TOWER_NOT_OWNER,"tower_set on the far sprinkler")
	deny(IND.TOWER_SET_ACTION,FAR[0],"quota:4",IND.TOWER_NOT_OWNER,"tower_set on a crop cell (no object)")
	walk_to(BENCH)
	tq_check(dist(TW)>3.2,"at the bench, %.2f tiles from the tower"%dist(TW))
	deny(IND.TOWER_SET_ACTION,TW,"reserve:12","靠近一點，才能和它互動","tower_set from the workbench (too far)",false)
	tq_check(tq_keys(obj(TW))==TQ_BASE_KEYS,"after all refusals the tower still has no settings")

func tq_reserve_leg() -> void:
	tq_check(str(obj(GATE).get("mode",""))=="low" and obj(PUMP).get("enabled")==true,"reserve leg: gate 餘水 so the tower refills, pump on")
	var r:=do(IND.TOWER_SET_ACTION,TW,"reserve:%d"%TQ_RESERVE)
	tq_check(str(r.get("message",""))=="水塔已設為「儲水桶留 24 份」","reserve message: "+str(r.get("message","")))
	var t:=obj(TW)
	tq_check(tq_keys(t)==["enabled","items","owner","reserve","type","water"] and int(tq_get(t,"reserve",0))==TQ_RESERVE,"tower has reserve 24 and no quota fields (%s)"%str(t))
	deny(IND.TOWER_SET_ACTION,TW,"reserve:%d"%TQ_RESERVE,IND.TOWER_SAME_SETTING,"reserve:24 again",false)
	var rep:=IND.tower_report(world.state,World.key(TW))
	tq_check(int(rep.reserve)==TQ_RESERVE and int(rep.quota)==0 and int(rep.quota_left)==-1,"tower_report reserve 24, quota 不限 (%s)"%str(rep))
	var rows:=[tw_row()]
	var cf_rows:=[]
	var rose_rounds:=0
	var cf_zero:=0
	var first_take:=-1
	for n in 40:
		if failed:return
		var res:=tq_step(IND.INTERVAL,"reserve 24 round %d (gate low, pump on)"%(n+1))
		var pre:Dictionary=res.pre
		var got:Dictionary=res.got
		var cf:=tq_model(tq_override(pre,{"reserve":0}),IND.INTERVAL)
		rows.append([int(got.tank),int(got.s1),int(got.s2),int(got.w)])
		cf_rows.append(cf.plan)
		if int(got.w)>int(pre.w):
			rose_rounds+=1
			if first_take<0:first_take=n+1
			tq_check(int(got.tank)>=TQ_RESERVE,"round %d: the tower rose (%d -> %d) and the tank still holds %d >= 24"%[n+1,int(pre.w),int(got.w),int(got.tank)])
			if int(got.w)<IND.TOWER_CAPACITY:tq_check(int(got.tank)==TQ_RESERVE,"round %d: tower not full, so it took exactly the excess above 24 (tank %d)"%[n+1,int(got.tank)])
			if int(cf.plan[0])==0:cf_zero+=1
		if n+1>=6 and int(got.w)>=64:break
	tq_check(rose_rounds>=1 and cf_zero>=1,"reserve: tower filled on %d rounds keeping 24 in the tank; without reserve the same rounds would leave the tank at 0 (%d rounds)"%[rose_rounds,cf_zero])
	var upstream_zero:=0
	for i in range(1,tw_fill_log.size()):
		if int(tw_fill_log[i][0])==0 and int(tw_fill_log[i][3])<IND.TOWER_CAPACITY:upstream_zero+=1
	tq_check(upstream_zero>=1,"upstream fill log (no reserve) had %d rounds with the tank at 0 while the tower filled"%upstream_zero)
	tq_info.reserve={"rounds":rows,"without_reserve_model":cf_rows,"first_round_tower_took":first_take,"upstream_fill_log":tw_fill_log}
	print("TOWER_QUOTA_JOURNEY reserve 24 rounds tank/S1/S2/tower %s; same pre-states without reserve (model plan) %s; upstream no-reserve fill log %s"%[str(rows),str(cf_rows),str(tw_fill_log)])

func tq_quota_leg() -> void:
	act(IND.GATE_ACTION,GATE,"closed")
	var rep:=IND.tower_report(world.state,World.key(TW))
	tq_check(rep.ok and rep.refill_zone=="cut" and same(rep.consumers,[{"key":World.key(S2),"type":"sprinkler"}]),"gate closed: tower cut from the tank, feeds only S2 (%s)"%str(rep))
	var set_day:=tq_today()
	var r:=do(IND.TOWER_SET_ACTION,TW,"quota:%d"%TQ_QUOTA)
	tq_check(str(r.get("message",""))=="水塔已設為「每日配水 4 份」","quota message: "+str(r.get("message","")))
	var t:=obj(TW)
	tq_check(tq_keys(t)==["enabled","items","owner","quota","quota_day","quota_used","reserve","type","water"] and int(tq_get(t,"quota",0))==TQ_QUOTA and int(tq_get(t,"quota_day",-1))==set_day and int(tq_get(t,"quota_used",-1))==0 and int(tq_get(t,"reserve",0))==TQ_RESERVE,"quota 4 set: quota_day %d (today), quota_used 0, reserve kept (%s)"%[set_day,str(t)])
	rep=IND.tower_report(world.state,World.key(TW))
	tq_check(int(rep.quota)==TQ_QUOTA and int(rep.quota_used)==0 and int(rep.quota_left)==TQ_QUOTA and int(rep.reserve)==TQ_RESERVE,"tower_report quota 4, used 0, left 4 (%s)"%str(rep))
	deny(IND.TOWER_SET_ACTION,TW,"quota:%d"%TQ_QUOTA,IND.TOWER_SAME_SETTING,"quota:4 again",false)
	r=do(IND.TOWER_ACTION,TW,"")
	tq_check(str(r.get("message",""))=="水塔已設為「只蓄水」" and obj(TW).get("enabled")==false,"toggle 只蓄水 (%s)"%str(r.get("message","")))
	var held:=int(obj(TW).water)
	var drain:=[]
	for guard in 12:
		if failed:return
		var row:=tq_day("只蓄水 drain")
		drain.append("d%d %s S2=%d tower=%d"%[int(row.day),str(row.weather),int(row.S2),int(row.tower)])
		tq_check(int(row.tower)==held and int(row.quota_day)==set_day and int(row.quota_used)==0,"day %d 只蓄水: tower holds %d, quota record untouched (day %d used %d)"%[int(row.day),int(row.tower),int(row.quota_day),int(row.quota_used)])
		if int(row.S2)==0:break
	if not tq_check(int(obj(S2).water)==0,"S2 spent all its water on the far crops while the tower held (%s)"%str(drain)):return
	var day_a:=tq_today()
	rep=IND.tower_report(world.state,World.key(TW))
	tq_check(day_a>set_day and int(tq_get(obj(TW),"quota_day",-1))==set_day and int(rep.quota_used)==0 and int(rep.quota_left)==TQ_QUOTA,"day A %d: the stored record of day %d reads as 0 sent today (%s)"%[day_a,set_day,str(rep)])
	tq_info.drain=drain
	# Day A: 出水 under quota 4.
	r=do(IND.TOWER_ACTION,TW,"")
	tq_check(str(r.get("message",""))=="水塔已設為「出水」" and obj(TW).get("enabled")==true,"toggle back to 出水 (%s)"%str(r.get("message","")))
	var w0:=int(obj(TW).water)
	var s0:=int(obj(S2).water)
	tq_check(w0>=12,"the tower holds %d, so only the quota can limit today's sending"%w0)
	var first:=tq_step(IND.INTERVAL,"day A first 出水 round, quota 4")
	var fw:Dictionary=first.want
	var unlimited:=tq_model(tq_override(first.pre,{"quota":0}),IND.INTERVAL)
	t=obj(TW)
	tq_check(int(fw.sent)==TQ_QUOTA and int(fw.plan[2])==s0+TQ_QUOTA and int(t.water)==w0-TQ_QUOTA and int(tq_get(t,"quota_day",-1))==day_a and int(tq_get(t,"quota_used",-1))==TQ_QUOTA,"day A: sends exactly 4 (S2 %d -> %d, tower %d -> %d, record day %d used %d)"%[s0,int(fw.plan[2]),w0,int(t.water),int(tq_get(t,"quota_day",-1)),int(tq_get(t,"quota_used",-1))])
	tq_check(int(unlimited.sent)==12-s0 and int(unlimited.plan[2])==12,"the unlimited rule would have sent %d (S2 to 12) in the same round"%int(unlimited.sent))
	var day_a_rows:=[[int(first.got.tank),int(first.got.s1),int(first.got.s2),int(first.got.w)]]
	for n in 4:
		if failed:return
		var res:=tq_step(IND.INTERVAL,"day A after the 4 are sent %d"%(n+1))
		var cf:=tq_model(tq_override(res.pre,{"quota":0}),IND.INTERVAL)
		tq_check(int(res.want.sent)==0 and int(cf.sent)>0,"day A round %d: quota used up, nothing sent although S2 needs %d"%[n+1,int(cf.sent)])
		day_a_rows.append(tw_row())
	# Item 5: raise to 8 (keeps today's 4), then lower back to 4 (keeps used 8).
	r=do(IND.TOWER_SET_ACTION,TW,"quota:%d"%TQ_RAISED)
	tq_check(str(r.get("message",""))=="水塔已設為「每日配水 8 份」","raise message: "+str(r.get("message","")))
	t=obj(TW)
	tq_check(int(tq_get(t,"quota",0))==TQ_RAISED and int(tq_get(t,"quota_day",-1))==day_a and int(tq_get(t,"quota_used",-1))==TQ_QUOTA,"raised to 8 mid-day: today's 4 kept (%s)"%str(t))
	rep=IND.tower_report(world.state,World.key(TW))
	tq_check(int(rep.quota_used)==TQ_QUOTA and int(rep.quota_left)==TQ_RAISED-TQ_QUOTA,"tower_report after raising: used 4, left 4 (%s)"%str(rep))
	var raised:=tq_step(IND.INTERVAL,"day A after raising to 8")
	t=obj(TW)
	tq_check(int(raised.want.sent)==TQ_RAISED-TQ_QUOTA and int(tq_get(t,"quota_used",-1))==TQ_RAISED,"raised: the next round sends 4 more (used %d)"%int(tq_get(t,"quota_used",-1)))
	day_a_rows.append(tw_row())
	for n in 2:
		if failed:return
		var res:=tq_step(IND.INTERVAL,"day A, quota 8 used up %d"%(n+1))
		var cf:=tq_model(tq_override(res.pre,{"quota":0}),IND.INTERVAL)
		tq_check(int(res.want.sent)==0 and int(cf.sent)>0,"day A quota 8 round %d: nothing more, S2 still short by %d"%[n+1,int(cf.sent)])
	r=do(IND.TOWER_SET_ACTION,TW,"quota:%d"%TQ_QUOTA)
	tq_check(str(r.get("message",""))=="水塔已設為「每日配水 4 份」","lower message: "+str(r.get("message","")))
	t=obj(TW)
	tq_check(int(tq_get(t,"quota",0))==TQ_QUOTA and int(tq_get(t,"quota_day",-1))==day_a and int(tq_get(t,"quota_used",-1))==TQ_RAISED,"lowered to 4 mid-day: the 8 already sent are kept (%s)"%str(t))
	rep=IND.tower_report(world.state,World.key(TW))
	tq_check(int(rep.quota_used)==TQ_RAISED and int(rep.quota_left)==0,"tower_report after lowering: used 8, left 0 (%s)"%str(rep))
	for n in 4:
		if failed:return
		var res:=tq_step(IND.INTERVAL,"day A after lowering to 4 %d"%(n+1))
		var cf:=tq_model(tq_override(res.pre,{"quota":0}),IND.INTERVAL)
		tq_check(int(res.want.sent)==0 and int(cf.sent)>0 and int(res.got.w)==int(res.pre.w),"day A lowered round %d: nothing sent (unlimited would send %d)"%[n+1,int(cf.sent)])
	day_a_rows.append(tw_row())
	tq_check(int(tq_sent_by_day.get(day_a,0))==TQ_RAISED and int(obj(S2).water)<12,"day A total sent 8 (4 + 4 after raising), S2 left at %d"%int(obj(S2).water))
	tq_info.day_a={"day":day_a+1,"rows":day_a_rows,"sent":int(tq_sent_by_day.get(day_a,0)),"unlimited_first_round":int(unlimited.sent)}
	print("TOWER_QUOTA_JOURNEY day A (quota 4 -> 8 -> 4) rows tank/S1/S2/tower %s; unlimited would send %d in the first round"%[str(day_a_rows),int(unlimited.sent)])
	# Item 6: save -> reload mid-day, continue in lock-step with the unsaved world.
	var before:=obj(TW).duplicate(true)
	var shadow=world
	reload_compare("tower quota lowered mid-day")
	if failed:return
	shadow.save_path=""
	tq_shadow=shadow
	tq_check(same(obj(TW),before),"after reload: tower settings, quota_day and quota_used identical (%s)"%str(obj(TW)))
	rep=IND.tower_report(world.state,World.key(TW))
	tq_check(int(rep.reserve)==TQ_RESERVE and int(rep.quota)==TQ_QUOTA and int(rep.quota_used)==TQ_RAISED and int(rep.quota_left)==0,"after reload tower_report reserve 24 quota 4 used 8 left 0 (%s)"%str(rep))
	tq_check(str(obj(GATE).get("mode",""))=="closed" and obj(TW).get("enabled")==true,"after reload: gate closed, tower 出水")
	var row_b:=tq_day("day B after reload (lock-step)")
	var day_b:=int(row_b.plan_day)
	var sent_b:=int(tq_sent_by_day.get(day_b,0))
	tq_check(day_b==day_a+1 and int(tq_sent_by_day.get(day_a,0))==TQ_RAISED,"the round crossing midnight still counted for day A: day A total stays 8")
	tq_check(tq_midnight_blocked>=1,"the midnight round was blocked by day A's record although a fresh day would have sent (%d)"%tq_midnight_blocked)
	tq_check(sent_b>=1 and sent_b<=TQ_QUOTA and int(row_b.quota_day)==day_b and int(row_b.quota_used)==sent_b,"day B resumes: sent %d, record day %d used %d"%[sent_b,int(row_b.quota_day),int(row_b.quota_used)])
	if int(row_b.S2)<12 and int(row_b.tower)>0:tq_check(sent_b==TQ_QUOTA,"day B: S2 %d < 12 so the quota was binding (sent %d)"%[int(row_b.S2),sent_b])
	for n in 2:
		if failed:return
		tq_step(IND.INTERVAL,"day B lock-step round %d"%(n+1))
	tq_check(tq_shadow_steps>0,"unsaved continuation stepped %d times in lock-step"%tq_shadow_steps)
	tq_shadow=null
	# Item 4: several world days under quota 4.
	var prev:=row_b
	var limited:=1 if int(row_b.S2)<12 else 0
	for n in 4:
		if failed:return
		var row:=tq_day("quota 4")
		var d:=int(row.plan_day)
		var sent:=int(tq_sent_by_day.get(d,0))
		tq_check(sent<=TQ_QUOTA and int(row.quota_used)<=TQ_QUOTA and int(prev.tower)-int(row.tower)<=TQ_QUOTA and int(row.tower)<=int(prev.tower),"day %d: sent %d <= 4, tower %d -> %d"%[int(row.day),sent,int(prev.tower),int(row.tower)])
		if sent>0:tq_check(int(row.quota_day)==d and int(row.quota_used)==sent,"day %d: record reset after midnight (day %d used %d)"%[int(row.day),int(row.quota_day),int(row.quota_used)])
		if int(row.S2)<12 and int(row.tower)>0:
			limited+=1
			tq_check(sent==TQ_QUOTA,"day %d: S2 %d < 12 with the tower at %d, so the quota was the limit (sent %d)"%[int(row.day),int(row.S2),int(row.tower),sent])
		prev=row
	var days_max:=0
	for d in tq_sent_by_day:
		if int(d)>day_a:days_max=maxi(days_max,int(tq_sent_by_day[d]))
	tq_check(days_max<=TQ_QUOTA,"every world day after day A sent at most 4 (max %d)"%days_max)
	tq_info.quota={"set_day":set_day+1,"day_a":day_a+1,"sent_by_day":tq_sent_by_day,"limited_days_after_a":limited,"midnight_rounds_blocked":tq_midnight_blocked,"lockstep_steps":tq_shadow_steps}
	for row in tq_day_log:
		print("TOWER_QUOTA_JOURNEY day d%d %s %s tower=%d S2=%d far_wet=%d sent_today=%d quota=%d record=%d/%d %s"%[int(row.day),str(row.weather),str(row.phase),int(row.tower),int(row.S2),int(row.far_wet),int(row.sent_today),int(row.quota),int(row.quota_day),int(row.quota_used),"出水" if row.out else "只蓄水"])

func tq_move_leg() -> void:
	var before:=obj(TW).duplicate(true)
	tq_check(tq_settings(before)==TQ_SETTING_KEYS,"settings present before moving (%s)"%str(tq_keys(before)))
	var dest:=Vector2i(-1,-1)
	for cell:Vector2i in TQ_MOVE_CANDIDATES:
		if free_grass(cell):
			dest=cell
			break
	if dest==Vector2i(-1,-1):
		for cell:Vector2i in TQ_MOVE_CANDIDATES:
			var k:=World.key(cell)
			var empty:=true
			for layer in ["objects","ground","roofs","crops","forest"]:
				if (world.state[layer] as Dictionary).has(k):empty=false
			if empty and world.resource(cell) in ["tree","rock","grass"] and not world.protected(cell) and not world.water(cell):
				clear(cell)
				dest=cell
				break
	if not tq_check(dest!=Vector2i(-1,-1),"a free cell beside the tower to move it to"):return
	walk_to(dest,1.5)
	tq_check(dist(dest)>=0.8 and dist(dest)<=3.2 and dist(TW)<=3.2,"standing %.2f from the tower and %.2f from %s"%[dist(TW),dist(dest),str(dest)])
	var bag0:=bag().duplicate(true)
	var r:=tq_act_here("move_object",TW,"%d,%d"%[dest.x,dest.y])
	tq_check(str(r.get("message",""))=="搬好了！家具與箱內物品一起保存，沒有額外扣料","move message: "+str(r.get("message","")))
	tq_check(not world.state.objects.has(World.key(TW)) and same(obj(dest),before),"moved to %s with water, reserve, quota and today's record (%s)"%[str(dest),str(obj(dest))])
	var rep:=IND.tower_report(world.state,World.key(dest))
	tq_check(rep.ok and int(rep.reserve)==TQ_RESERVE and int(rep.quota)==TQ_QUOTA,"tower_report at the new cell keeps reserve 24 / quota 4 (%s)"%str(rep))
	r=tq_act_here("move_object",dest,"%d,%d"%[TW.x,TW.y])
	tq_check(not world.state.objects.has(World.key(dest)) and same(obj(TW),before),"moved back into the line, identical (%s)"%str(obj(TW)))
	expect_bag(bag0,{},"moving the tower twice changes no inventory")
	var group:=group_of(TW)
	tq_check((group.get("keys",[]) as Array).size()==7,"back in the 7-piece network")
	tq_info.move={"to":[dest.x,dest.y]}

func tq_reset_leg() -> void:
	var r:=do(IND.TOWER_SET_ACTION,TW,"quota:0")
	tq_check(str(r.get("message",""))=="水塔已設為「每日配水不限」","quota:0 message: "+str(r.get("message","")))
	tq_check(tq_keys(obj(TW))==["enabled","items","owner","reserve","type","water"],"quota:0 removes quota, quota_day and quota_used together (%s)"%str(obj(TW)))
	deny(IND.TOWER_SET_ACTION,TW,"quota:0",IND.TOWER_SAME_SETTING,"quota:0 again",false)
	r=do(IND.TOWER_SET_ACTION,TW,"reserve:0")
	tq_check(str(r.get("message",""))=="水塔已設為「不保留桶水」","reserve:0 message: "+str(r.get("message","")))
	tq_check(tq_keys(obj(TW))==TQ_BASE_KEYS,"reserve:0 removes reserve: plain tower again (%s)"%str(obj(TW)))
	deny(IND.TOWER_SET_ACTION,TW,"reserve:0",IND.TOWER_SAME_SETTING,"reserve:0 again",false)
	var rep:=IND.tower_report(world.state,World.key(TW))
	tq_check(int(rep.reserve)==0 and int(rep.quota)==0 and int(rep.quota_left)==-1,"tower_report back to 0/0/-1 (%s)"%str(rep))
	var rows:=[tw_row()]
	for n in 2:
		if failed:return
		var pre_row:=tw_row()
		var upstream:=tw_model(pre_row,"closed")
		var res:=tq_step(IND.INTERVAL,"unlimited again, gate closed %d"%(n+1))
		tq_check(upstream==(res.want.plan as Array),"closed round %d equals the upstream model %s (got plan %s)"%[n+1,str(upstream),str(res.want.plan)])
		if n==0 and int(pre_row[3])>=12:tq_check(int(res.want.plan[2])==12,"unlimited: S2 topped up to 12 in one round (%d -> 12)"%int(pre_row[2]))
		rows.append(tw_row())
	act(IND.GATE_ACTION,GATE,"low")
	for n in 3:
		if failed:return
		var pre_row:=tw_row()
		var upstream:=tw_model(pre_row,"low")
		var res:=tq_step(IND.INTERVAL,"unlimited again, gate low %d"%(n+1))
		tq_check(upstream==(res.want.plan as Array),"low round %d equals the upstream model %s (got plan %s)"%[n+1,str(upstream),str(res.want.plan)])
		if int(res.want.plan[3])<IND.TOWER_CAPACITY:tq_check(int(res.got.tank)==0,"low round %d: no reserve, the tank leftovers all go into the tower (tank %d)"%[n+1,int(res.got.tank)])
		rows.append(tw_row())
	tq_info.reset=rows
	print("TOWER_QUOTA_JOURNEY settings cleared: rounds tank/S1/S2/tower %s (closed x2, then low x3)"%str(rows))

func tq_remove_leg() -> void:
	var stored:=int(obj(TW).water)
	var bag0:=bag().duplicate(true)
	act("remove",TW)
	expect_bag(bag0,{IND.TOWER_KIT:1},"removing the tower returns exactly one kit")
	tq_check(not world.state.objects.has(World.key(TW)) and not world.blocked(TW),"tower gone (%d water discarded), cell walkable"%stored)
	bag0=bag().duplicate(true)
	act("build",TW,IND.TOWER_KIND)
	expect_bag(bag0,{IND.TOWER_KIT:-1},"tower placed again")
	tq_check(same(obj(TW),{"type":IND.TOWER_KIND,"owner":TOKEN,"items":{},"water":0,"enabled":true}),"placed again: no reserve/quota fields (%s)"%str(obj(TW)))
	deny(IND.TOWER_SET_ACTION,TW,"quota:0",IND.TOWER_SAME_SETTING,"quota:0 on the re-placed tower",false)
	tq_info.removed={"water_discarded":stored}
	reload_compare("final quota tower")
	if failed:return
	tq_check(tq_keys(obj(TW))==TQ_BASE_KEYS and str(obj(GATE).get("mode",""))=="low","final tower (no settings) and gate low persist")

func tq_report() -> void:
	var own:=rejections.slice(tq_rej0)
	print("TOWER_QUOTA_JOURNEY info=%s"%JSON.stringify(tq_info))
	for i in own.size():print("TOWER_QUOTA_JOURNEY rejection %d %s"%[i+1,own[i]])
	print("TOWER_QUOTA_JOURNEY stats segment_actions=%d segment_walk_tiles=%d segment_world_seconds=%.1f segment_step_wait_seconds=%.1f segment_modeled_steps=%d segment_lockstep_steps=%d segment_rejections=%d segment_rejections_state_changed=%d segment_reloads=%d segment_checks=%d actions_total=%d walk_tiles_total=%d world_seconds_total=%.1f rejections_total=%d wall_ms=%d passed=%s"%[actions-tq_actions0,walking-tq_walk0,now()-tq_time0,waited-tq_waited0,tq_steps,tq_shadow_steps,own.size(),rejections_changed-tq_changed0,reloads-tq_reloads0,checks-tq_checks0,actions,walking,now(),rejections.size(),Time.get_ticks_msec()-tq_ms,str(not failed)])

# ---------------------------------------------------------------- model + steps

## Snapshot of everything the model needs (read-only).
func tq_read(w) -> Dictionary:
	var objects:Dictionary=w.state.objects
	var tower:Dictionary=objects.get(World.key(TW),{})
	var s1:Dictionary=objects.get(World.key(S1),{})
	var s2:Dictionary=objects.get(World.key(S2),{})
	var tank:Dictionary=objects.get(World.key(TANK),{})
	var pump:Dictionary=objects.get(World.key(PUMP),{})
	var gate:Dictionary=objects.get(World.key(GATE),{})
	var crops:={}
	for sprinkler:Vector2i in [S1,S2]:
		for offset:Vector2i in IND.sprinkler_offsets("sprinkler"):
			var k:=World.key(sprinkler+offset)
			var c:Variant=w.state.crops.get(k)
			if c is Dictionary and str(c.get("kind",""))!="":
				crops[k]={"owner":str(c.get("owner","")),"wet":c.get("wet",false)==true}
	var keys:=tq_keys(tower)
	return {"time":float(w.state.time),"net_due":float(w.state.next_network_check),
		"tank":int(tq_get(tank,"water",0)),"s1":int(tq_get(s1,"water",0)),"s2":int(tq_get(s2,"water",0)),"w":int(tq_get(tower,"water",0)),
		"pump_on":tq_get(pump,"enabled",false)==true,"s1_on":tq_get(s1,"enabled",false)==true,"s2_on":tq_get(s2,"enabled",false)==true,"w_on":tq_get(tower,"enabled",false)==true,
		"s1_next":float(tq_get(s1,"next_water",0.0)),"s2_next":float(tq_get(s2,"next_water",0.0)),
		"gate":str(tq_get(gate,"mode","open")),
		"reserve":int(tq_get(tower,"reserve",0)),"quota":int(tq_get(tower,"quota",0)),
		"has_quota_day":"quota_day" in keys,"quota_day":int(tq_get(tower,"quota_day",-1)),"quota_used":int(tq_get(tower,"quota_used",0)),
		"tower_keys":keys,"crops":crops}

## Independent model of one World.step of length dt for this line (gate low or closed).
## Plan uses the world day of the step START; crops dry at each midnight inside the
## step and rain re-wets them; sprinklers then water dry owned crops one water each.
func tq_model(p:Dictionary,dt:float) -> Dictionary:
	var start:=float(p.time)
	var end:=start+dt
	var plan_day:=int(floor(start/WEATHER.DAY_SECONDS))
	var cap:=int(IND.SPRINKLER_CAPACITIES.sprinkler)
	var tank:=int(p.tank)
	var s1:=int(p.s1)
	var s2:=int(p.s2)
	var w:=int(p.w)
	var quota:=int(p.quota)
	var used:=0
	if quota>0 and bool(p.has_quota_day) and int(p.quota_day)==plan_day:used=int(p.quota_used)
	var sent:=0
	var took:=0
	var due:=end>=float(p.net_due)
	if due:
		if bool(p.pump_on):tank+=mini(TW_MODEL_PUMP,IND.TANK_CAPACITY-tank)
		if bool(p.s1_on):
			var a:=mini(cap-s1,tank)
			tank-=a
			s1+=a
		if str(p.gate)=="low":
			if bool(p.s2_on):
				var b:=mini(cap-s2,tank)
				tank-=b
				s2+=b
			var c:=mini(mini(IND.TOWER_CAPACITY-w,tank-int(p.reserve)),tank)
			if c>0:
				tank-=c
				w+=c
				took=c
		if bool(p.w_on) and bool(p.s2_on) and w>0 and (quota==0 or used<quota):
			var d:=mini(w,cap-s2)
			if quota>0:d=mini(d,quota-used)
			if d>0:
				w-=d
				s2+=d
				sent=d
	var q_has:=bool(p.has_quota_day)
	var q_day:=int(p.quota_day)
	var q_used:=int(p.quota_used)
	if quota>0 and sent>0:
		q_has=true
		q_day=plan_day
		q_used=used+sent
	var plan:=[tank,s1,s2,w]
	var d0:=WEATHER.day_index(start)
	var d1:=WEATHER.day_index(end)
	var crops:Dictionary=p.crops
	var wet:={}
	for k in crops:
		var was:bool=crops[k].wet==true
		wet[k]=WEATHER.rains(d1,"home") if d1>d0 else (was or WEATHER.rains(d0,"home"))
	var levels:={"s1":s1,"s2":s2}
	for row in [[S1,"s1"],[S2,"s2"]]:
		var which:String=row[1]
		var level:=int(levels[which])
		if not bool(p[which+"_on"]) or level==0 or float(p[which+"_next"])>end:continue
		for offset:Vector2i in IND.sprinkler_offsets("sprinkler"):
			var k:=World.key((row[0] as Vector2i)+offset)
			if not wet.has(k) or wet[k]==true or str(crops[k].owner)!=TOKEN:continue
			if level==0:break
			wet[k]=true
			level-=1
		levels[which]=level
	return {"plan":plan,"row":[tank,int(levels.s1),int(levels.s2),w],"sent":sent,"took":took,"plan_day":plan_day,"due":due,
		"has_quota_day":q_has,"quota_day":q_day,"quota_used":q_used,"wet":wet}

func tq_override(p:Dictionary,changes:Dictionary) -> Dictionary:
	var out:=p.duplicate(true)
	for k in changes:out[k]=changes[k]
	return out

## One World.step(dt) checked against tq_model (and the unsaved twin when present).
func tq_step(dt:float,label:String) -> Dictionary:
	var pre:=tq_read(world)
	if str(pre.gate) not in ["low","closed"]:tq_check(false,"%s: model covers gate low/closed only (%s)"%[label,str(pre.gate)])
	var want:=tq_model(pre,dt)
	if int(pre.quota)>0 and WEATHER.day_index(float(pre.time)+dt)>WEATHER.day_index(float(pre.time)):
		var fresh:=tq_model(tq_override(pre,{"quota_used":0}),dt)
		if int(want.sent)==0 and int(fresh.sent)>0:tq_midnight_blocked+=1
	var stepped:=world.step(dt,true)
	waited+=dt
	tq_steps+=1
	tq_check(stepped,"%s: world step %.2f (%s)"%[label,dt,str(world.step_error)])
	var got:=tq_read(world)
	var row:=[int(got.tank),int(got.s1),int(got.s2),int(got.w)]
	var want_wet:Dictionary=want.wet
	var got_crops:Dictionary=got.crops
	var wet_ok:=true
	for k in want_wet:
		if not got_crops.has(k) or bool(got_crops[k].wet)!=bool(want_wet[k]):wet_ok=false
	var q_ok:bool=got.tower_keys==pre.tower_keys and int(got.reserve)==int(pre.reserve) and int(got.quota)==int(pre.quota) and bool(got.has_quota_day)==bool(want.has_quota_day)
	if bool(want.has_quota_day):q_ok=q_ok and int(got.quota_day)==int(want.quota_day) and int(got.quota_used)==int(want.quota_used)
	tq_check(row==(want.row as Array) and wet_ok and q_ok,"%s: t=%.0f tank/S1/S2/tower %s -> %s (model %s, sent %d, took %d), record %d/%d (model %d/%d), crops %s (model %s)"%[label,float(pre.time),str([pre.tank,pre.s1,pre.s2,pre.w]),str(row),str(want.row),int(want.sent),int(want.took),int(got.quota_day),int(got.quota_used),int(want.quota_day),int(want.quota_used),str(got_crops),str(want_wet)])
	var plan_day:=int(want.plan_day)
	tq_sent_by_day[plan_day]=int(tq_sent_by_day.get(plan_day,0))+int(want.sent)
	if tq_shadow!=null:tq_shadow_step(dt,label)
	return {"pre":pre,"want":want,"got":got}

func tq_shadow_step(dt:float,label:String) -> void:
	var stepped:bool=tq_shadow.step(dt,true)
	tq_shadow_steps+=1
	var diffs:=[]
	all_diffs(canon(tq_net(tq_shadow)),canon(tq_net(world)),"net",diffs)
	tq_check(stepped and diffs.is_empty(),"%s: the unsaved continuation matches the reloaded world %s"%[label,JSON.stringify(diffs.slice(0,3))])

## Network objects, the 8 crops and the clocks of a World (for the lock-step compare).
func tq_net(w) -> Dictionary:
	var objects:Dictionary=w.state.objects
	var crops:Dictionary=w.state.crops
	var net:={}
	for cell:Vector2i in [PUMP,TANK,PIPE_A,S1,GATE,TW,S2]:net[World.key(cell)]=objects.get(World.key(cell),{})
	var plots:={}
	for cell:Vector2i in NEAR+FAR:plots[World.key(cell)]=crops.get(World.key(cell),{})
	return {"time":float(w.state.time),"next_network_check":float(w.state.next_network_check),"objects":net,"crops":plots}

func tq_until(target:float,chunk:float,label:String) -> void:
	while now()<target-0.000001 and not failed:
		tq_step(minf(chunk,target-now()),label)

## Modeled 60 s steps to the next midnight + 120 s, then one observation row.
func tq_day(label:String) -> Dictionary:
	tq_until(next_midnight()+120.0,60.0,label)
	var t:=obj(TW)
	var d:=tq_today()
	var row:={"day":day(),"plan_day":d,"weather":weather(),"phase":label,"tower":int(tq_get(t,"water",0)),"S2":int(obj(S2).get("water",0)),
		"S1":int(obj(S1).get("water",0)),"tank":int(obj(TANK).get("water",0)),"far_wet":FAR.size()-tw_dry(FAR).size(),
		"sent_today":int(tq_sent_by_day.get(d,0)),"quota":int(tq_get(t,"quota",0)),"quota_day":int(tq_get(t,"quota_day",-1)),
		"quota_used":int(tq_get(t,"quota_used",-1)),"out":tq_get(t,"enabled",false)==true,"rainy":WEATHER.rains(WEATHER.day_index(now()),"home")}
	tq_day_log.append(row)
	return row

# ---------------------------------------------------------------- helpers

## A successful action at `target` from where the player already stands (no walking).
func tq_act_here(action:String,target:Vector2i,extra:String) -> Dictionary:
	if failed:return {"ok":false,"message":"skipped"}
	actions+=1
	var result:=world.act(TOKEN,"quota-%d"%actions,action,target,extra)
	print("%d %s %s %s | %s"%[actions,action,target,extra,result.message])
	tq_check(result.ok,"%s %s at %s: %s"%[action,extra,str(target),str(result.message)])
	return result

func tq_today() -> int:
	return int(floor(now()/WEATHER.DAY_SECONDS))

## Value of `field` whether the key is a String or a StringName.
func tq_get(d:Dictionary,field:String,default:Variant) -> Variant:
	for k in d:
		if str(k)==field:return d[k]
	return default

func tq_keys(d:Dictionary) -> Array:
	var out:=[]
	for k in d:out.append(str(k))
	out.sort()
	return out

func tq_settings(d:Dictionary) -> Array:
	var keys:=tq_keys(d)
	var out:=[]
	for k:String in TQ_SETTING_KEYS:
		if k in keys:out.append(k)
	return out

func tq_check(condition:bool,message:String) -> bool:
	expect(condition,"TOWER_QUOTA_JOURNEY: "+message)
	return condition
