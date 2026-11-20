extends "res://tests/test_lanyang_revisit_journey.gd"
## Chapter 40 home「水塔」water_tower natural journey: a FRESH temp world, ONE player,
## ONE process (reloads are in-process World.new().load_world on the same save file;
## after each reload the journey continues in the reloaded World).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
##
## Prerequisite reuse (disclosed): this file EXTENDS the unmodified
## test_lanyang_revisit_journey.gd (-> history -> garden -> regions -> chapter journeys).
## That chain earns chapter one, the Lanyang canal repair, the first 分水 memory, the
## plaque, the Lanyang revisit (completed + claimed), copper joints / planks / kits from
## gathered materials and the home pipe line
##   PUMP(53,20) TANK(52,20) PIPE_A(52,21) S1(52,22) GATE(52,23) PIPE_B(52,24) S2(52,25)
## with near crops (51,22)(53,22) and far crops (51,25)(53,25)(52,26); it ends with the
## gate on 「餘水」(low), the pump on and both sprinklers enabled.
##
## Hooks: checkpoint("grow") (fresh world) and the parent's first mill_batch() (real
## bench, before the revisit; the parent refuses the gate kit at the same point) also
## refuse the water_tower_kit craft with Industry.TOWER_LOCKED (whole state unchanged).
##
## After the parent: gather copper (borrowed public pick, practice vein), wood (trees),
## stone (rocks), mill 3 plank batches at the sawmill, craft 2 copper joints and one
## water_tower_kit at the bench; pick up PIPE_B and put the tower in its place (on the
## far side of the gate, in the pipe line). Fill rounds (gate low, pump on) are checked
## round by round against an independent model of the documented plan() order. Close
## the gate: day-by-day log of tower / far sprinkler / far crops until the tower and the
## sprinkler run dry; far crops replanted on a day the parent's tower-free line would
## already be dry grow to maturity; 只蓄水 holds the tower water while S2 drains;
## save -> reload with 只蓄水 + stored water; back to 出水; reopen (low) -> tower
## refills; remove (kit back, water gone) and place again.
##
## Everything goes through World.act after World.move_player along BFS routes and
## World.step(dt,true) for waits. NO direct writes by this file to inventory, coins,
## flags, revisit / irrigation fields, objects, crops, positions or time.
## Not reachable here (disclosed): the fifth-tower limit refusal would need four more
## kits (24 planks = 48 more wood, 8 joints, 24 stone) of gathering; the limit is
## covered by the rule test test_water_tower.gd. Moving a tower is also only covered there.
## WALKING IS FREE (parent rule): move_player never advances state.time.
## Prints TOWER_JOURNEY lines; the last checks=N failures=M line is the chapter base's.

const TW:=PIPE_B
const TW_MODEL_PUMP:=8
const TW_FAR_NEED:=3

var tw_fresh_done:=false
var tw_mill_done:=false
var tw_ms:=0
var tw_actions0:=0
var tw_walk0:=0
var tw_time0:=0.0
var tw_waited0:=0.0
var tw_reloads0:=0
var tw_rej0:=0
var tw_changed0:=0
var tw_checks0:=0
var tw_fill_log:=[]
var tw_day_log:=[]
var tw_info:={}

# ---------------------------------------------------------------- hooks

func checkpoint(stage:String) -> void:
	super.checkpoint(stage)
	if failed:return
	if stage=="grow" and not tw_fresh_done:
		tw_fresh_done=true
		var here:=Vector2i(floori(float(person().x)),floori(float(person().y)))
		deny("craft",here,IND.TOWER_KIT,IND.TOWER_LOCKED,"craft water_tower_kit on a fresh world",false)

func mill_batch(mill:Vector2i) -> void:
	super.mill_batch(mill)
	if failed or tw_mill_done:return
	tw_mill_done=true
	tw_check(not LR.tech_unlocked(world.state) and mill_hooked,"first sawmill batch: revisit not done, gate kit refused at this point too")
	deny("craft",BENCH,IND.TOWER_KIT,IND.TOWER_LOCKED,"craft water_tower_kit at the real bench before the revisit")

# ---------------------------------------------------------------- journey

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	tw_ms=Time.get_ticks_msec()
	tw_actions0=actions
	tw_walk0=walking
	tw_time0=now()
	tw_waited0=waited
	tw_reloads0=reloads
	tw_rej0=rejections.size()
	tw_changed0=rejections_changed
	tw_checks0=checks
	tw_check(tw_fresh_done and tw_mill_done,"both pre-revisit tower refusals ran (fresh world, real bench)")
	print("TOWER_JOURNEY prerequisite chain passed (checks %d, actions %d, world_seconds %.1f, day %d)"%[checks,actions,now(),day()])
	tw_materials_leg()
	if not failed:tw_place_leg()
	if not failed:tw_fill_leg()
	if not failed:tw_closed_leg()
	if not failed:tw_reopen_remove_leg()
	tw_report()

func tw_materials_leg() -> void:
	tw_check(world.player_region(TOKEN)=="home" and LR.tech_unlocked(world.state),"start: at home, Lanyang revisit completed")
	tw_check(str(obj(GATE).get("mode",""))=="low" and str(obj(TW).get("type",""))=="water_pipe" and obj(PUMP).get("enabled")==true and obj(S1).get("enabled")==true and obj(S2).get("enabled")==true,"parent network intact: gate low, pipe at %s, pump and both sprinklers on"%str(TW))
	tw_check(int(bag().get(IND.TOWER_KIT,0))==0 and int(bag().get("plank",0))==0 and int(bag().get("copper_joint",0))==0,"no tower kit, no planks, no joints yet")
	deny("craft",BENCH,IND.TOWER_KIT,"製作材料不足","craft the tower kit before gathering (no planks or joints)")
	var start:=bag().duplicate(true)
	if not person().get("borrowed_mine_pick",false) and int(bag().get("reinforced_pick",0))<1:
		act("borrow_mine_pick",World.COPPER_CELL)
	while int(bag().get("copper_ore",0))<4 and not failed:
		var ready:=float(world.state.copper.ready)
		if ready>now():wait_for(ready-now(),12.0)
		var before:=bag().duplicate(true)
		act("pick",World.COPPER_CELL)
		expect_bag(before,{"copper_ore":2},"practice vein gives copper_ore 2")
	gather("wood","tree","axe",14,3)
	gather("stone","rock","pick",6,2)
	if failed:return
	tw_info.gathered={"copper_ore":int(bag().get("copper_ore",0))-int(start.get("copper_ore",0)),"wood":int(bag().get("wood",0))-int(start.get("wood",0)),"stone":int(bag().get("stone",0))-int(start.get("stone",0))}
	for n in 3:
		var before:=bag().duplicate(true)
		mill_batch(MILL)
		expect_bag(before,{"wood":-4,"plank":2},"sawmill batch %d: wood 4 -> plank 2"%(n+1))
	for n in 2:
		var before:=bag().duplicate(true)
		act("craft",BENCH,"copper_joint")
		expect_bag(before,{"copper_ore":-2,"wood":-1,"copper_joint":1},"craft copper_joint %d"%(n+1))
	if failed:return
	tw_check(int(bag().get("plank",0))>=6 and int(bag().get("copper_joint",0))>=2 and int(bag().get("stone",0))>=6,"materials for one tower kit: plank %d joint %d stone %d"%[int(bag().get("plank",0)),int(bag().get("copper_joint",0)),int(bag().get("stone",0))])
	var before:=bag().duplicate(true)
	var r:=do("craft",BENCH,IND.TOWER_KIT)
	tw_check(str(r.get("message",""))=="製作完成：水塔","tower kit craft message: "+str(r.get("message","")))
	expect_bag(before,{"plank":-6,"copper_joint":-2,"stone":-6,IND.TOWER_KIT:1},"craft water_tower_kit: exact debit plank 6 / copper_joint 2 / stone 6, +1 kit")
	tw_info.kit_bag={"plank":int(bag().get("plank",0)),"copper_joint":int(bag().get("copper_joint",0)),"stone":int(bag().get("stone",0)),"kit":int(bag().get(IND.TOWER_KIT,0))}
	print("TOWER_JOURNEY materials gathered %s, kit crafted at world_seconds=%.1f, left %s"%[JSON.stringify(tw_info.gathered),now(),JSON.stringify(tw_info.kit_bag)])

func tw_place_leg() -> void:
	deny("build",S1,IND.TOWER_KIND,"這格有東西，請選空地","build the tower on the near sprinkler's cell (occupied)")
	var before:=bag().duplicate(true)
	act("remove",TW)
	expect_bag(before,{"pipe_kit":1},"picking up pipe B returns one pipe_kit")
	tw_check(not world.state.objects.has(World.key(TW)),"pipe B removed")
	before=bag().duplicate(true)
	var r:=do("build",TW,IND.TOWER_KIND)
	tw_check(str(r.get("message",""))=="放好了水塔，家園又多了一點你的心意","tower build message: "+str(r.get("message","")))
	expect_bag(before,{IND.TOWER_KIT:-1},"build tower: kit -1 only")
	tw_check(same(obj(TW),{"type":IND.TOWER_KIND,"owner":TOKEN,"items":{},"water":0,"enabled":true}),"new tower at %s: water 0, 出水, mine (%s)"%[str(TW),str(obj(TW))])
	tw_check(world.blocked(TW),"tower blocks walking")
	var group:=group_of(TW)
	tw_check((group.get("keys",[]) as Array).size()==7 and World.key(S2) in group.get("keys",[]) and World.key(TANK) in group.get("keys",[]),"tower joins the pipe line: one 7-piece network (%s)"%str(group.get("keys",[])))
	var rep:=IND.tower_report(world.state,World.key(TW))
	tw_check(rep.ok and rep.refill_zone=="low" and rep.enabled==true and int(rep.tanks)==1 and same(rep.consumers,[{"key":World.key(S2),"type":"sprinkler"}]),"tower_report: refill zone low (behind the 餘水 gate), feeds only S2 (%s)"%str(rep))
	tw_check(same(IND.zone_report(world.state,World.key(GATE)).get("towers"),[{"key":World.key(TW),"zone":"low"}]),"zone_report lists the tower in the low zone")
	deny(IND.TOWER_ACTION,GATE,"",IND.TOWER_NOT_OWNER,"tower_toggle on the diversion gate cell (not a tower)")
	walk_to(BENCH)
	tw_check(dist(TW)>3.2,"at the bench, %.2f tiles from the tower"%dist(TW))
	deny(IND.TOWER_ACTION,TW,"","靠近一點，才能和它互動","tower_toggle from the workbench (too far)",false)

## Independent model of one network round for this line (single tank, S1 always in the
## full zone, S2 + tower in the low zone when the gate is low; nothing reaches them when
## closed); returns [tank,S1,S2,tower]. Tower discharge only crosses an open gate, and
## here S2 sits on the tower's own side.
func tw_model(row:Array,gate:String) -> Array:
	var t:=int(row[0])
	var s1:=int(row[1])
	var s2:=int(row[2])
	var w:=int(row[3])
	t+=mini(TW_MODEL_PUMP,IND.TANK_CAPACITY-t)
	var a:=mini(12-s1,t)
	t-=a
	s1+=a
	if gate!="closed":
		var b:=mini(12-s2,t)
		t-=b
		s2+=b
		var c:=mini(IND.TOWER_CAPACITY-w,t)
		t-=c
		w+=c
	if obj(TW).get("enabled")==true:
		var d:=mini(w,12-s2)
		w-=d
		s2+=d
	return [t,s1,s2,w]

func tw_row() -> Array:
	return [int(obj(TANK).get("water",0)),int(obj(S1).get("water",0)),int(obj(S2).get("water",0)),int(obj(TW).get("water",0))]

func tw_dry(cells:Array) -> Array:
	var out:=[]
	for cell:Vector2i in cells:
		var c:=crop(cell)
		if str(c.kind)!="" and c.wet!=true:out.append(cell)
	return out

## One 8 s step = one network round. Sprinklers water dry crops in the same step right
## after the plan is applied, so each crop that turned wet costs its sprinkler 1.
func tw_round(label:String,gate:String) -> Array:
	var pre:=tw_row()
	var want:=tw_model(pre,gate)
	var dry_near:=tw_dry(NEAR)
	var dry_far:=tw_dry(FAR)
	wait_for(IND.INTERVAL,IND.INTERVAL)
	want[1]=int(want[1])-(dry_near.size()-tw_dry(NEAR).size())
	want[2]=int(want[2])-(dry_far.size()-tw_dry(FAR).size())
	var got:=tw_row()
	tw_check(got==want,"%s: round tank/S1/S2/tower %s -> %s (model %s)"%[label,str(pre),str(got),str(want)])
	return got

func tw_fill_leg() -> void:
	tw_fill_log.append(tw_row())
	var full_at:=-1
	for n in 14:
		if failed:return
		var row:=tw_round("fill %d (gate low, pump on)"%(n+1),"low")
		tw_fill_log.append(row)
		if full_at<0 and int(row[3])==IND.TOWER_CAPACITY:full_at=n+1
		if full_at>0 and n+1>=full_at+2:break
	tw_check(full_at>0,"tower reached %d (rounds %d)"%[IND.TOWER_CAPACITY,full_at])
	var rose:=true
	for i in range(1,tw_fill_log.size()):
		if int(tw_fill_log[i][3])<int(tw_fill_log[i-1][3]):rose=false
	tw_check(rose and int(tw_fill_log[1][3])>0,"tower level never drops while filling, first round already > 0")
	var last:Array=tw_fill_log[-1]
	tw_check(int(last[0])>0 and int(last[3])==IND.TOWER_CAPACITY,"once the tower is full the tank keeps its pump water again (tank %d)"%int(last[0]))
	tw_info.fill={"rounds_to_full":full_at,"start_seconds":now()}
	print("TOWER_JOURNEY fill rounds tank/S1/S2/tower %s (full after %d rounds, %d s)"%[str(tw_fill_log),full_at,full_at*int(IND.INTERVAL)])

func tw_snap() -> Dictionary:
	var far_wet:=0
	var growth:=[]
	for cell:Vector2i in FAR:
		far_wet+=1 if crop(cell).wet else 0
		growth.append(float(crop(cell).growth))
	var near_wet:=0
	for cell:Vector2i in NEAR:near_wet+=1 if crop(cell).wet else 0
	return {"day":day(),"weather":weather(),"season":str(WEATHER.season_on_day(WEATHER.day_index(now()))),"tower":int(obj(TW).get("water",0)),"S2":int(obj(S2).get("water",0)),"S1":int(obj(S1).get("water",0)),"tank":int(obj(TANK).get("water",0)),"far_wet":far_wet,"near_wet":near_wet,"far_growth":growth,"out":obj(TW).get("enabled")==true}

## Advance to the next midnight + 120 s and check the far side against the previous
## observation (exactly one midnight crossed).
func tw_day(prev:Dictionary,label:String) -> Dictionary:
	wait_until(next_midnight()+120.0,60.0)
	var row:=tw_snap()
	row.phase=label
	var rainy:=WEATHER.rains(WEATHER.day_index(now()),"home")
	var prev_res:=int(prev.tower)+int(prev.S2)
	var res:=int(row.tower)+int(row.S2)
	tw_check(int(row.tower)<=int(prev.tower),"day %d %s: closed gate, tower never refilled (%d -> %d)"%[row.day,label,prev.tower,row.tower])
	tw_check(int(row.S1)==12 and int(row.tank)>0 and int(row.near_wet)==NEAR.size(),"day %d: near side fed by the tank (S1 %d, tank %d)"%[row.day,row.S1,row.tank])
	if rainy:
		tw_check(res==prev_res and int(row.far_wet)==FAR.size(),"day %d rain: far crops rain-wet, nothing used (tower %d S2 %d)"%[row.day,row.tower,row.S2])
	elif row.out:
		var used:=mini(TW_FAR_NEED,prev_res)
		tw_check(res==prev_res-used and int(row.far_wet)==used,"day %d dry 出水: tower+S2 %d -> %d waters %d far crops"%[row.day,prev_res,res,int(row.far_wet)])
		tw_check(int(row.tower)==0 or int(row.S2)==12,"day %d: the tower tops S2 back up to 12 (S2 %d, tower %d)"%[row.day,row.S2,row.tower])
	else:
		var used2:=mini(TW_FAR_NEED,int(prev.S2))
		tw_check(int(row.tower)==int(prev.tower) and int(row.S2)==int(prev.S2)-used2 and int(row.far_wet)==used2,"day %d dry 只蓄水: tower holds %d, S2 %d -> %d"%[row.day,row.tower,prev.S2,row.S2])
	row.rainy=rainy
	tw_day_log.append(row)
	return row

func tw_closed_leg() -> void:
	act(IND.GATE_ACTION,GATE,"closed")
	var rep:=IND.tower_report(world.state,World.key(TW))
	tw_check(rep.ok and rep.refill_zone=="cut" and int(rep.water)==IND.TOWER_CAPACITY and same(rep.consumers,[{"key":World.key(S2),"type":"sprinkler"}]),"closed: tower cut off from the tank, still feeds S2 (%s)"%str(rep))
	var prev:=tw_snap()
	prev.phase="closed"
	tw_day_log.append(prev)
	tw_info.closed={"day":day(),"seconds":now()}
	# Phase A: 出水 until a dry day on which the parent's tower-free S2 would already
	# have been empty (S2's own 12 used up on earlier days).
	var used_far:=0
	var proof:={}
	for guard in 20:
		if failed:return
		var before_used:=used_far
		var row:=tw_day(prev,"出水")
		if not row.rainy:used_far+=int(prev.tower)+int(prev.S2)-int(row.tower)-int(row.S2)
		prev=row
		if not row.rainy and before_used>=12:
			proof=row
			break
	if not tw_check(not proof.is_empty(),"reached a dry day beyond the far sprinkler's own 12"):return
	tw_check(int(proof.far_wet)==FAR.size() and int(proof.tower)>0,"day %d: far crops watered although S2's own 12 was used up (%d used so far), tower %d"%[proof.day,used_far-TW_FAR_NEED,proof.tower])
	tw_info.proof_day=proof.day
	# A sprinkler that already watered today waits until midnight. Replant
	# before a dry morning so rain cannot stand in for the tower.
	if WEATHER.rains(WEATHER.day_index(now())+1.0,"home"):
		prev=tw_day(prev,"出水，等待晴天")
	if not tw_check(not WEATHER.rains(WEATHER.day_index(now())+1.0,"home"),"replanting leads into a dry morning"):return
	for cell:Vector2i in FAR:
		var c:=crop(cell)
		tw_check(str(c.kind)!="" and float(c.growth)>=float(World.CROPS[c.kind].time),"far crop %s mature before replanting (%s %.0f)"%[str(cell),str(c.kind),float(c.growth)])
		act("harvest",cell)
	for cell:Vector2i in FAR:plant(cell)
	if failed:return
	var tower0:=int(obj(TW).water)
	wait_until(next_midnight(),60.0)
	var t0:=now()
	wait_for(200.0,20.0)
	var grown:=[]
	for cell:Vector2i in FAR:
		var c:=crop(cell)
		grown.append([str(c.kind),float(c.growth)])
		tw_check(float(c.growth)==float(World.CROPS[c.kind].time) and c.wet==true,"replanted far %s %s grows to maturity on tower water (%.0f/%.0f)"%[str(cell),str(c.kind),float(c.growth),float(World.CROPS[c.kind].time)])
	tw_check(int(obj(S2).water)==12 and int(obj(TW).water)==tower0-FAR.size(),"S2 back to 12, tower paid the 3 new waterings (%d -> %d)"%[tower0,int(obj(TW).water)])
	tw_info.replant={"day":day(),"seconds":now()-t0,"crops":grown,"tower":int(obj(TW).water)}
	prev=tw_snap()
	prev.phase="replanted"
	tw_day_log.append(prev)
	print("TOWER_JOURNEY replant day %d: far crops %s after %.0f s, tower %d"%[day(),JSON.stringify(grown),now()-t0,int(obj(TW).water)])
	# Phase B: more 出水 days until the tower is below 72.
	for guard in 20:
		if failed or int(prev.tower)<72:break
		prev=tw_day(prev,"出水")
	# Phase C: 只蓄水 holds the tower water while S2 drains.
	var r:=do(IND.TOWER_ACTION,TW,"")
	tw_check(str(r.get("message",""))=="水塔已設為「只蓄水」" and obj(TW).get("enabled")==false,"toggle: 只蓄水 (%s)"%str(r.get("message","")))
	tw_check(IND.tower_report(world.state,World.key(TW)).enabled==false,"tower_report shows 只蓄水")
	prev=tw_snap()
	prev.phase="toggled 只蓄水"
	tw_day_log.append(prev)
	var held:=int(prev.tower)
	for guard in 4:
		if failed:return
		prev=tw_day(prev,"只蓄水")
		if not prev.rainy:break
	tw_check(int(prev.tower)==held and int(prev.S2)<12,"只蓄水: S2 not refilled (%d) while the tower keeps %d"%[prev.S2,held])
	reload_compare("tower 只蓄水 holding %d"%held)
	if failed:return
	tw_check(same(obj(TW),{"type":IND.TOWER_KIND,"owner":TOKEN,"items":{},"water":held,"enabled":false}),"after reload: tower water %d and 只蓄水 persist (%s)"%[held,str(obj(TW))])
	tw_check(str(obj(GATE).get("mode",""))=="closed","after reload: gate still closed")
	prev=tw_snap()
	prev.phase="reloaded"
	for guard in 4:
		if failed:return
		prev=tw_day(prev,"只蓄水 after reload")
		if not prev.rainy:break
	tw_check(int(prev.tower)==held,"behaviour continues after reload: tower still %d, S2 %d"%[held,prev.S2])
	r=do(IND.TOWER_ACTION,TW,"")
	tw_check(str(r.get("message",""))=="水塔已設為「出水」" and obj(TW).get("enabled")==true,"toggle back: 出水 (%s)"%str(r.get("message","")))
	var s2_low:=int(obj(S2).water)
	wait_for(2*IND.INTERVAL,IND.INTERVAL)
	tw_check(int(obj(S2).water)==12 and int(obj(TW).water)==held-(12-s2_low),"出水 again: S2 %d -> 12, tower %d -> %d"%[s2_low,held,int(obj(TW).water)])
	prev=tw_snap()
	prev.phase="toggled 出水"
	tw_day_log.append(prev)
	# Phase D: 出水 until the tower and S2 run dry and a dry day leaves the far crops dry.
	var tower_out_day:=-1
	var s2_out_day:=-1
	var dry_day:=-1
	var after_dry:=0
	for guard in 70:
		if failed:return
		prev=tw_day(prev,"出水")
		if tower_out_day<0 and int(prev.tower)==0:tower_out_day=prev.day
		if s2_out_day<0 and int(prev.tower)+int(prev.S2)==0:s2_out_day=prev.day
		if dry_day<0 and not prev.rainy and int(prev.far_wet)==0:dry_day=prev.day
		if dry_day>0:
			after_dry+=1
			if after_dry>=3:break
	tw_check(tower_out_day>0 and s2_out_day>=tower_out_day and dry_day>s2_out_day,"tower ran out on day %d, S2 on day %d, first dry day with dry far crops %d"%[tower_out_day,s2_out_day,dry_day])
	var fed:=0
	for row in tw_day_log:
		if row.has("rainy") and not row.rainy and int(row.far_wet)==FAR.size():fed+=1
	tw_check(fed>=8,"far crops sprinkler-watered on %d dry days with the gate closed (S2's own 12 alone covers 4)"%fed)
	tw_info.closed.merge({"tower_out_day":tower_out_day,"s2_out_day":s2_out_day,"first_dry_far_day":dry_day,"dry_days_fed":fed,"days_logged":tw_day_log.size()})
	var compact:=[]
	for row in tw_day_log:
		compact.append("d%d %s %s %s tower=%d S2=%d far_wet=%d %s"%[int(row.day),str(row.season),str(row.weather),str(row.phase),int(row.tower),int(row.S2),int(row.far_wet),"出水" if row.out else "只蓄水"])
	for line in compact:print("TOWER_JOURNEY day "+line)

func tw_reopen_remove_leg() -> void:
	act(IND.GATE_ACTION,GATE,"low")
	tw_check(IND.tower_report(world.state,World.key(TW)).refill_zone=="low","reopened to 餘水: tower back in the low refill zone")
	var refill:=[tw_row()]
	for n in 3:refill.append(tw_round("refill after reopening %d"%(n+1),"low"))
	tw_check(int(refill[-1][3])>0 and int(refill[-1][2])==12,"tower refilled from tank leftovers (%s)"%str(refill))
	tw_info.reopen=refill
	print("TOWER_JOURNEY reopened (low) rounds tank/S1/S2/tower %s"%str(refill))
	var stored:=int(obj(TW).water)
	var total_before:=0
	for v in tw_row():total_before+=int(v)
	var before:=bag().duplicate(true)
	act("remove",TW)
	expect_bag(before,{IND.TOWER_KIT:1},"removing the tower returns exactly one kit")
	var total_after:=int(obj(TANK).water)+int(obj(S1).water)+int(obj(S2).water)
	tw_check(not world.state.objects.has(World.key(TW)) and total_after==total_before-stored and not world.blocked(TW),"tower gone, its %d water discarded (network %d -> %d), cell walkable"%[stored,total_before,total_after])
	before=bag().duplicate(true)
	act("build",TW,IND.TOWER_KIND)
	expect_bag(before,{IND.TOWER_KIT:-1},"tower placed again")
	tw_check(same(obj(TW),{"type":IND.TOWER_KIND,"owner":TOKEN,"items":{},"water":0,"enabled":true}),"placed again: water 0, 出水 (%s)"%str(obj(TW)))
	var again:=[tw_row()]
	for n in 2:again.append(tw_round("refill after placing again %d"%(n+1),"low"))
	tw_info.placed_again=again
	print("TOWER_JOURNEY removed (water %d discarded), placed again rounds %s"%[stored,str(again)])
	reload_compare("final tower")
	if failed:return
	tw_check(str(obj(TW).get("type",""))==IND.TOWER_KIND and int(obj(TW).water)==int(again[-1][3]) and str(obj(GATE).mode)=="low","final tower and gate persist")

func tw_report() -> void:
	var own:=rejections.slice(tw_rej0)
	print("TOWER_JOURNEY info=%s"%JSON.stringify(tw_info))
	print("TOWER_JOURNEY hook rejections: fresh-world craft + real-bench craft (TOWER_LOCKED), listed with the parent's rejections above")
	for i in own.size():print("TOWER_JOURNEY rejection %d %s"%[i+1,own[i]])
	print("TOWER_JOURNEY stats segment_actions=%d segment_walk_tiles=%d segment_world_seconds=%.1f segment_step_wait_seconds=%.1f segment_rejections=%d (+2 in hooks) segment_rejections_state_changed=%d segment_reloads=%d segment_checks=%d actions_total=%d walk_tiles_total=%d world_seconds_total=%.1f rejections_total=%d wall_ms=%d passed=%s"%[actions-tw_actions0,walking-tw_walk0,now()-tw_time0,waited-tw_waited0,own.size(),rejections_changed-tw_changed0,reloads-tw_reloads0,checks-tw_checks0,actions,walking,now(),rejections.size(),Time.get_ticks_msec()-tw_ms,str(not failed)])

func tw_check(condition:bool,message:String) -> bool:
	expect(condition,"TOWER_JOURNEY: "+message)
	return condition
