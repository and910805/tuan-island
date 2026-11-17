extends "res://tests/test_salt_pan_journey.gd"
## Chapter 40「北門合作鹽田・儲滷槽」(salt_brine.gd) natural journey: a FRESH temp world, ONE
## process, played only through World.act (after World.move_player along BFS routes),
## validated transit and World.step(dt,true) waits. Reloads are in-process
## (save -> World.new().load_world through SaveSchema; the journey continues in the
## reloaded World).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
##
## Prerequisite reuse (disclosed): this file EXTENDS the unmodified
## test_salt_pan_journey.gd (-> test_flower_journey.gd). That chain is the shortest one
## that earns the Beimen chapter (about 35 s of the 120 s budget on the last full run;
## test_salt_revisit_journey's chain is far longer). It ends with: gates repaired; A
## complete and holding the salt_wheel_kit + salt_rake_kit it uninstalled when it RELEASED
## lot 0; C..J owning lots 0..7 with NO wheel (phase "wheel"); K graduated from the
## apprentice station holding its own wheel + rake kits; B (flower late joiner) never raked.
## Nobody owns a unit with a wheel, so this segment re-creates two wheel units with real
## actions and the kits the chain already earned (no crafting needed):
##   C releases lot 0 (empty pans, no machines) -> A claims it and installs its own kit;
##   D releases lot 1 -> K claims it and installs its own kit.
## NO direct writes by this file to inventory, coins, flags, records, objects, positions
## or time; the tank level only changes through salt_brine_store / salt_brine_pour.
##
## Segment (A unless stated):
##  0. Refusals, each with the exact message, the pure *_block agreeing where the reason is
##     position independent, and the whole world state unchanged (== and sorted bytes):
##     A at home -> WRONG_REGION; B (never raked) at the tank -> NOT_READY; A (no unit) ->
##     NO_UNIT; C after releasing lot 0 -> NO_UNIT; E (lot 2, no wheel) -> NO_WHEEL;
##     A after claiming lot 0 -> NO_WHEEL; A at the wheel socket -> TOO_FAR; A at the tank:
##     p = 阿曬 -> WRONG_CELL, extra "c" -> BAD_PAN, empty pans -> PAN_EMPTY (store, pour).
##     LOCKED and NO_PLAYER cannot happen in this world (gates repaired upstream; World.act
##     rejects unknown tokens first): left to test_salt_brine.gd.
##  1. Start of a dry day: World.step(1 s) -> the wheel floods both empty pans; store ->
##     THIN (0 成), pour -> TANK_EMPTY (no record yet); wait until pan a holds >= 3
##     buckets, store: buckets = floor(p/48), pan p - 48k, level k (exact message).
##  2. The next rainy Beimen day found by stepping the real clock (CYCLE in weather.gd:
##     rain never lasts two days). 360 s before the rain: rake any salt pan (hand rake, +3
##     sea salt), store any brine pan holding >= 1 bucket, step 1 s (wheel refills).
##     30 s before the rain: store pan b (dry, no note). 1 s into the rain: store pan a ->
##     STORE_OK + STORE_RAIN_NOTE; pour -> RAIN_POUR on both pans (state unchanged);
##     save -> reload into a new World mid-rain (tank non-empty, both pans brine), both
##     worlds stepped 120 s in lockstep: identical salt_pan / salt_brine / pan progress;
##     the pans' left-over brine is diluted by exactly 0.25/s while the tank level and
##     record bytes stay unchanged.
##  3. Next (dry) day: pour everything the tank can give into pan a (the brine stored from
##     BOTH pans is concentrated into one), PAN_RICH on the next pour. The NO-TANK
##     ALTERNATIVE is computed with SaltPan.advance from the RECORDED progress of pan a at
##     the moment it was stored in the rain (what the pan would have done if left alone);
##     the observed crystallisation instant of pan a (pan.t written by World.step) must be
##     earlier and equal the prediction from the poured progress. At the tank: PAN_SALT
##     (store, pour); A hand-rakes that tank-fed batch (+3 sea salt) and, the revisit being
##     cheap here (gates repaired, A raked), stocks those 3 sea salt at 阿曬 with one real
##     salt_revisit_stock on that dry day.
##  4. A keeps storing from both pans (raking pans that crystallise) until the tank holds
##     30 buckets (a store limited by the remaining room is checked when it happens);
##     then store -> TANK_FULL.
##  5. D releases lot 1 and is refused NO_UNIT; K (no unit) -> NO_UNIT, claims lot 1 ->
##     NO_WHEEL, installs its own kit; on a dry day the wheel floods K's pans and K pours
##     A's stored brine from the shared tank into both pans (9 buckets each), PAN_RICH,
##     waits for the salt and hand-rakes it (+3 sea salt).
##  6. Final save -> reload (no advance). Bucket ledger: level == stored - poured.
## Prints SALT_BRINE_JOURNEY lines, then the inherited SALT_PAN_JOURNEY summary, and
## last SALT_BRINE_JOURNEY_TESTS checks=N failures=M; quits 1 on failure (once).

const SB=preload("res://scripts/salt_brine.gd")
const SR=preload("res://scripts/salt_revisit.gd")

var sb_started:=false
var sb_ms:=0
var sb_actions0:=0
var sb_walk0:=0
var sb_time0:=0.0
var sb_checks0:=0
var sb_reloads:=0
var sb_refusals:=[]
var sb_changed:=0
var sb_moves:=[]
var sb_rakes:=[]
var sb_info:={}
var sb_stored:=0
var sb_poured:=0
var sb_capped:=false
var sb_reasons:={}

# ---------------------------------------------------------------- journey

func run() -> void:
	super.run()
	if failed:return
	sb_started=true
	sb_ms=Time.get_ticks_msec()
	sb_actions0=actions
	sb_walk0=walking
	sb_time0=now()
	sb_checks0=checks
	print("SALT_BRINE_JOURNEY prerequisite salt-pan chain passed (checks %d, actions %d, world_seconds %.1f, day %d %s)"%[checks,actions,now(),int(WEATHER.day_index(now())),WEATHER.outdoor_id(WEATHER.day_index(now()))])
	sb_start()
	if not failed:sb_first_store()
	if not failed:sb_rain()
	if not failed:sb_after_rain()
	if not failed:sb_fill()
	if not failed:sb_second_islander()
	if not failed:sb_complete_batch()
	if not failed:sb_final()

## The inherited end state, then refusals that need no wheel.
func sb_start() -> void:
	var s:=world.state
	var c:=tk("c")
	var d:=tk("d")
	var e:=tk("e")
	var k:=tk("k")
	sb_check(not s.has(SB.STATE_KEY) and SB.level(s)==0 and SB.unlocked(s),"start: gates repaired, no tank record, level 0")
	sb_check(S.owned_lot(s,c)==0 and S.owned_lot(s,d)==1 and S.owned_lot(s,e)==2,"start: C, D, E own lots 0, 1, 2")
	for lot in S.LOT_COUNT:sb_check(s.salt_pan.lots[lot].wheel==false,"start: lot %d has no wheel"%lot)
	sb_check(str(s.salt_pan.apprentice.tenant)=="","start: apprentice station free")
	sb_check(int(SB.unit(s,TOKEN_A).index)==-1 and SB.player_ready(s,TOKEN_A),"start: A raked, no unit")
	sb_check(int(s.players[TOKEN_A].inventory.get("salt_wheel_kit",0))==1,"start: A holds the wheel kit it uninstalled")
	sb_check(int(s.players[k].inventory.get("salt_wheel_kit",0))==1 and int(SB.unit(s,k).index)==-1,"start: K holds its own wheel kit, no unit")
	sb_check(not SB.player_ready(s,TOKEN_B) and world.player_region(TOKEN_B)==S.REGION,"start: B in 北門, never raked")
	for i in 4:sb_check(str(s.salt_pan.pans[i].s)=="empty","start: pan %d empty"%i)
	sb_info.start={"day":int(WEATHER.day_index(now())),"weather":WEATHER.outdoor_id(WEATHER.day_index(now())),"world_seconds":now()}
	# A at home: WRONG_REGION (position checks come later; the pure block is NO_UNIT).
	tok=TOKEN_A
	expect(world.player_region(tok)==S.REGION,"A ends the parent in 北門")
	sb_check(SB.common_block(world.state,tok)==SB.NO_UNIT,"A pure common block NO_UNIT")
	strav(S.TRANSFER,"home")
	if failed:return
	sb_deny(SB.STORE_ACTION,SB.TANK,"a",SB.WRONG_REGION,"A store from home",false)
	sb_deny(SB.POUR_ACTION,SB.TANK,"a",SB.WRONG_REGION,"A pour from home",false)
	strav(FERRY,S.REGION)
	if failed:return
	# B never raked by hand.
	tok=TOKEN_B
	sb_deny(SB.STORE_ACTION,SB.TANK,"a",SB.NOT_READY,"B (never raked) store",true,true)
	sb_deny(SB.POUR_ACTION,SB.TANK,"b",SB.NOT_READY,"B (never raked) pour",true,true)
	# A has no unit.
	tok=TOKEN_A
	sb_deny(SB.STORE_ACTION,SB.TANK,"a",SB.NO_UNIT,"A (no unit) store",true,true)
	# C gives lot 0 back; C is now unit-less.
	tok=c
	sact("salt_release",pan_cell(0))
	sb_check(str(world.state.salt_pan.lots[0].owner)=="","C released lot 0")
	sb_deny(SB.POUR_ACTION,SB.TANK,"a",SB.NO_UNIT,"C (released) pour",true,true)
	# E owns lot 2 without a wheel.
	tok=e
	sb_deny(SB.STORE_ACTION,SB.TANK,"a",SB.NO_WHEEL,"E (lot without wheel) store",true,true)
	# A claims lot 0 and installs its own wheel kit.
	tok=TOKEN_A
	sact("salt_claim",pan_cell(0))
	sb_check(S.owned_lot(world.state,tok)==0 and S.phase(world.state,tok)=="complete","A owns lot 0 again (phase stays complete)")
	sb_deny(SB.STORE_ACTION,SB.TANK,"a",SB.NO_WHEEL,"A (lot, no wheel) store",true,true)
	sact("salt_install",S.wheel_socket(0).position,"wheel",{"salt_wheel_kit":-1})
	sb_check(world.state.salt_pan.lots[0].wheel==true and world.state.salt_pan.lots[0].rake==false,"A's lot 0: wheel only")
	var unit:=SB.unit(world.state,tok)
	sb_check(int(unit.index)==0 and str(unit.kind)=="lot" and unit.wheel==true and SB.pan_ids(world.state,tok)==[0,1],"A's unit: lot 0 with wheel, pans [0,1]")
	sb_check(sb_dist(SB.TANK)>SB.REACH,"A at the wheel socket is out of reach (%.2f)"%sb_dist(SB.TANK))
	sb_deny(SB.STORE_ACTION,SB.TANK,"a",SB.TOO_FAR,"A store from the wheel socket",false)
	walk_to(SB.TANK)
	if failed:return
	sb_check(sb_dist(SB.TANK)<=SB.REACH,"A at the tank (%.2f)"%sb_dist(SB.TANK))
	sb_deny(SB.STORE_ACTION,S.SALT_WORKER,"a",SB.WRONG_CELL,"A store aimed at 阿曬",false)
	sb_deny(SB.STORE_ACTION,SB.TANK,"c",SB.BAD_PAN,"A store side c",false,true)
	sb_deny(SB.STORE_ACTION,SB.TANK,"a",SB.PAN_EMPTY,"A store an empty pan",false,true)
	sb_deny(SB.POUR_ACTION,SB.TANK,"b",SB.PAN_EMPTY,"A pour into an empty pan",false,true)
	sb_check(not world.state.has(SB.STATE_KEY),"no tank record after the refusals")

## Start of a dry day: the wheel floods, THIN / TANK_EMPTY, first store.
func sb_first_store() -> void:
	tok=TOKEN_A
	# 協調者修正：水車在裝好後的第一個 step 起點就引水（不是等到隔天早上），所以直接在
	# 裝好水車的這個乾日檢查「剛引水＝太淡」，不先等到下一個早晨。
	sb_check(not raining(),"the day the wheel was installed is dry (%s)"%sb_weather())
	if failed:return
	var ids:Array=SB.pan_ids(world.state,tok)
	var flood_at:=now()
	wait(1.0)
	for i in ids:
		var pan:Dictionary=world.state.salt_pan.pans[int(i)]
		sb_check(str(pan.s)=="brine" and str(pan.f)=="wheel" and is_equal_approx(float(pan.t),flood_at),"the wheel flooded pan %d at %.1f (s=%s f=%s t=%.1f)"%[int(i),flood_at,str(pan.s),str(pan.f),float(pan.t)])
	var thin:=int(floorf(float(SB.pan_progress(world.state,int(ids[0])).p)/SB.BUCKET))
	sb_check(thin==0,"fresh brine holds 0 buckets")
	sb_deny(SB.STORE_ACTION,SB.TANK,"a",SB.THIN%thin,"store fresh brine (thin)",true,true)
	sb_check(not world.state.has(SB.STATE_KEY),"THIN wrote no record")
	sb_deny(SB.POUR_ACTION,SB.TANK,"a",SB.TANK_EMPTY,"pour from the empty tank",true,true)
	var pa:int=int(ids[0])
	wait_until(func():return float(SB.pan_progress(world.state,pa).p)>=3.0*SB.BUCKET,30.0,1200.0,"pan a holds 3 buckets")
	if failed:return
	var moved:=sb_ok(SB.STORE_ACTION,"a","first store (%s day)"%sb_weather())
	sb_check(moved>=3 and SB.level(world.state)==moved,"first store: %d buckets, level %d"%[moved,SB.level(world.state)])
	sb_info.first={"day":int(WEATHER.day_index(now())),"weather":sb_weather(),"buckets":moved}

## The next rainy Beimen day.
func sb_rain() -> void:
	tok=TOKEN_A
	var day:=WEATHER.DAY_SECONDS
	var d:=WEATHER.day_index(now())+1.0
	while WEATHER.outdoor_id(d)!="rainy" or d*day-360.0<now():d+=1.0
	var rain_start:=d*day
	sb_info.rain={"day":int(d),"rain_start":rain_start,"day_before":WEATHER.outdoor_id(d-1.0),"day_after":WEATHER.outdoor_id(d+1.0)}
	sb_check(WEATHER.outdoor_id(d-1.0)!="rainy" and WEATHER.outdoor_id(d+1.0)!="rainy","rain day %d is a single rainy day"%int(d))
	wait(rain_start-360.0-now())
	if failed:return
	sb_check(not raining(),"360 s before the rain it is dry")
	var ids:Array=SB.pan_ids(world.state,tok)
	var prep:=[]
	for at in 2:
		var side:String=SB.SIDES[at]
		var pan:int=int(ids[at])
		var view:=SB.pan_progress(world.state,pan)
		if str(view.s)=="salt":
			sb_rake(pan,"before the rain")
			prep.append("%s raked"%side)
		elif str(view.s)=="brine" and int(view.tenths)>=1:
			prep.append("%s stored %d"%[side,sb_ok(SB.STORE_ACTION,side,"store before the rain (prep)")])
		else:prep.append("%s %s %.1f"%[side,str(view.s),float(view.p)])
	if failed:return
	wait(1.0)
	for i in ids:sb_check(str(world.state.salt_pan.pans[int(i)].s)=="brine","pan %d brine before the rain"%int(i))
	sb_info.rain.prep=prep
	wait(rain_start-30.0-now())
	if failed:return
	sb_check(not raining(),"30 s before the rain it is still dry")
	var pb:int=int(ids[1])
	var pa:int=int(ids[0])
	var kb:=sb_ok(SB.STORE_ACTION,"b","store pan b 30 s before the rain")
	wait(rain_start+1.0-now())
	if failed:return
	sb_check(raining(),"it rains in 北門 now")
	var p_a0:=float(SB.pan_progress(world.state,pa).p)
	var t_s:=now()
	var ka:=sb_ok(SB.STORE_ACTION,"a","store pan a in the rain")
	if failed:return
	var alt:=S.advance(p_a0,t_s,t_s+10.0*day)
	sb_check(alt.ok==true and alt.salt==true,"no-tank alternative of pan a crystallises within 10 days")
	sb_info.rain.store={"b_buckets":kb,"a_buckets":ka,"a_progress_at_store":p_a0,"store_time":t_s,"no_tank_salt_at":float(alt.at)}
	sb_info.p_a0=p_a0
	sb_info.t_s=t_s
	sb_info.alt_at=float(alt.at)
	sb_deny(SB.POUR_ACTION,SB.TANK,"a",SB.RAIN_POUR,"pour into pan a in the rain",true,true)
	sb_deny(SB.POUR_ACTION,SB.TANK,"b",SB.RAIN_POUR,"pour into pan b in the rain",true,true)
	var rem_a:=float(SB.pan_progress(world.state,pa).p)
	var rem_b:=float(SB.pan_progress(world.state,pb).p)
	var level0:=SB.level(world.state)
	var record0:=canon_bytes(world.state.get(SB.STATE_KEY))
	sb_check(level0>0 and level0<SB.CAP and rem_a<SB.BUCKET and rem_b<SB.BUCKET,"mid-rain: tank %d buckets, left-over brine a %.2f b %.2f"%[level0,rem_a,rem_b])
	sb_reload("mid-rain",120.0)
	if failed:return
	var rate:=float(S.RATES.rainy)
	sb_check(is_equal_approx(rate,-0.25),"rain rate -0.25/s")
	var now_a:=float(SB.pan_progress(world.state,pa).p)
	var now_b:=float(SB.pan_progress(world.state,pb).p)
	sb_check(is_equal_approx(now_a,maxf(0.0,rem_a+rate*120.0)) and is_equal_approx(now_b,maxf(0.0,rem_b+rate*120.0)),"rain dilutes the left-over brine: a %.2f -> %.2f, b %.2f -> %.2f"%[rem_a,now_a,rem_b,now_b])
	sb_check(str(world.state.salt_pan.pans[pa].s)=="brine" and str(world.state.salt_pan.pans[pb].s)=="brine","both pans stay brine in the rain")
	sb_check(SB.level(world.state)==level0 and canon_bytes(world.state.get(SB.STATE_KEY))==record0,"the tank is not diluted (level %d, record bytes unchanged)"%level0)
	sb_info.rain.dilution={"a":[rem_a,now_a],"b":[rem_b,now_b],"level":level0}
	wait(next_midnight()-now()+1.0)
	sb_check(not raining(),"the rain stopped at midnight")

## Pour back, compare with the no-tank alternative, rake the tank-fed batch, revisit stock.
func sb_after_rain() -> void:
	tok=TOKEN_A
	var day:=WEATHER.DAY_SECONDS
	var ids:Array=SB.pan_ids(world.state,tok)
	var pa:int=int(ids[0])
	var p_a1:=float(SB.pan_progress(world.state,pa).p)
	var level0:=SB.level(world.state)
	var poured:=sb_ok(SB.POUR_ACTION,"a","pour the stored brine of both pans into pan a")
	if failed:return
	var p_after:=float(SB.pan_progress(world.state,pa).p)
	var alt_now:=S.advance(float(sb_info.p_a0),float(sb_info.t_s),now())
	sb_check(alt_now.ok==true and alt_now.salt==false,"no-tank alternative is still brine now")
	sb_check(p_after>float(alt_now.p),"after the pour pan a holds %.2f, the no-tank alternative %.2f"%[p_after,float(alt_now.p)])
	var with_tank:=S.advance(p_after,now(),now()+10.0*day)
	sb_check(with_tank.ok==true and with_tank.salt==true and float(with_tank.at)<float(sb_info.alt_at),"predicted salt with the tank at %.1f, without at %.1f"%[float(with_tank.at),float(sb_info.alt_at)])
	sb_info.after_rain={"weather":sb_weather(),"pan_a_after_rain":p_a1,"level_before":level0,"poured":poured,"pan_a_after_pour":p_after,"no_tank_progress_now":float(alt_now.p),"predicted_salt_at":float(with_tank.at),"no_tank_salt_at":float(sb_info.alt_at)}
	var left:=SB.level(world.state)
	if left>0 and int(floorf((S.NEED-1.0-p_after)/SB.BUCKET))<1:
		sb_deny(SB.POUR_ACTION,SB.TANK,"a",SB.PAN_RICH,"pour into the concentrated pan a",true,true)
	elif left==0:
		sb_deny(SB.POUR_ACTION,SB.TANK,"a",SB.TANK_EMPTY,"pour after the tank ran dry",true,true)
	wait_until(func():return str(world.state.salt_pan.pans[pa].s)=="salt",20.0,1440.0,"tank-fed pan a crystallises")
	if failed:return
	var at_obs:=float(world.state.salt_pan.pans[pa].t)
	sb_check(is_equal_approx(at_obs,float(with_tank.at)) and at_obs<float(sb_info.alt_at),"observed salt at %.1f (predicted %.1f) is %.1f s before the no-tank alternative %.1f"%[at_obs,float(with_tank.at),float(sb_info.alt_at)-at_obs,float(sb_info.alt_at)])
	sb_check(str(world.state.salt_pan.pans[int(ids[1])].s)=="brine","pan b (its brine went into the tank) is still brine")
	sb_info.after_rain.observed_salt_at=at_obs
	sb_info.after_rain.saved_seconds=float(sb_info.alt_at)-at_obs
	sb_deny(SB.STORE_ACTION,SB.TANK,"a",SB.PAN_SALT,"store a crystallised pan",true,true)
	sb_deny(SB.POUR_ACTION,SB.TANK,"a",SB.PAN_SALT,"pour into a crystallised pan",true,true)
	sb_rake(pa,"tank-fed batch")
	if failed:return
	# 鹽籃批次: stock exactly those 3 sea salt at 阿曬 (dry day; the day after a rain day
	# and the one after it are never rainy in weather.gd's CYCLE).
	if raining():
		sb_info.revisit="skipped: raining when the batch was raked"
		return
	var w:=SR.weather_today(world.state)
	var total:=SR.stocked_total(world.state)
	var held:=int(bag().get("sea_salt",0))
	sb_check(SR.stock_block(world.state,bag(),tok)=="","revisit stock allowed (pure block)")
	consumed_salt+=SR.LOT_SALT
	var result:=sact(SR.STOCK_ACTION,SR.WORKER,"",{"sea_salt":-SR.LOT_SALT})
	sb_check(str(result.get("message",""))==SR.STOCK_OK%[SR.LOT_SALT,str(WEATHER.LABELS[w]),total+1],"revisit stock message: "+str(result.get("message","")))
	sb_check(SR.stocked_total(world.state)==total+1 and int(bag().get("sea_salt",0))==held-SR.LOT_SALT,"the tank-fed batch is stocked as one %s lot"%w)
	sb_info.revisit={"weather":w,"stocked_total":SR.stocked_total(world.state)}

## Store from both pans until the tank is full; TANK_FULL.
func sb_fill() -> void:
	tok=TOKEN_A
	var ids:Array=SB.pan_ids(world.state,tok)
	var deadline:=now()+5.0*WEATHER.DAY_SECONDS
	var t0:=now()
	var stores:=0
	while not failed and SB.level(world.state)<SB.CAP:
		if now()>deadline:
			sb_check(false,"tank not full by world second %.1f (level %d)"%[deadline,SB.level(world.state)])
			return
		for at in 2:
			if failed or SB.level(world.state)>=SB.CAP:break
			var pan:int=int(ids[at])
			var view:=SB.pan_progress(world.state,pan)
			if str(view.s)=="salt":sb_rake(pan,"while filling the tank")
			elif str(view.s)=="brine" and int(view.tenths)>=mini(8,SB.CAP-SB.level(world.state)):
				sb_ok(SB.STORE_ACTION,str(SB.SIDES[at]),"fill the tank")
				stores+=1
		if failed or SB.level(world.state)>=SB.CAP:break
		if raining():wait(next_midnight()-now()+1.0)
		else:wait(60.0)
	if failed:return
	sb_check(SB.level(world.state)==SB.CAP,"tank full: %d buckets"%SB.level(world.state))
	var side:=""
	for at in 2:
		if side=="" and str(SB.pan_progress(world.state,int(ids[at])).s)=="brine":side=str(SB.SIDES[at])
	if sb_check(side!="","a brine pan to try with the full tank"):
		sb_deny(SB.STORE_ACTION,SB.TANK,side,SB.TANK_FULL,"store into the full tank",true,true)
	sb_info.fill={"stores":stores,"world_seconds":now()-t0,"capped_store_seen":sb_capped}

## D releases lot 1, K takes it, installs its own wheel and pours A's brine.
func sb_second_islander() -> void:
	var d:=tk("d")
	var k:=tk("k")
	tok=d
	sact("salt_release",pan_cell(2))
	sb_check(str(world.state.salt_pan.lots[1].owner)=="","D released lot 1")
	sb_deny(SB.STORE_ACTION,SB.TANK,"a",SB.NO_UNIT,"D (released) store",true,true)
	tok=k
	sb_deny(SB.POUR_ACTION,SB.TANK,"a",SB.NO_UNIT,"K (no unit) pour",true,true)
	sact("salt_claim",pan_cell(2))
	sb_check(S.owned_lot(world.state,k)==1,"K owns lot 1")
	sb_deny(SB.POUR_ACTION,SB.TANK,"a",SB.NO_WHEEL,"K (lot, no wheel) pour",true,true)
	# 協調者修正：水車裝好後的第一個 step 起點就引水，所以先等到乾日且離午夜夠遠，再裝水車。
	while not failed and (raining() or next_midnight()-now()<600.0):wait(next_midnight()-now()+1.0)
	if failed:return
	sact("salt_install",S.wheel_socket(1).position,"wheel",{"salt_wheel_kit":-1})
	sb_check(SB.pan_ids(world.state,k)==[2,3] and SB.unit(world.state,k).wheel==true,"K's unit: lot 1 with wheel, pans [2,3]")
	var flood_at:=now()
	wait(1.0)
	for i in [2,3]:sb_check(str(world.state.salt_pan.pans[i].s)=="brine" and is_equal_approx(float(world.state.salt_pan.pans[i].t),flood_at),"K's wheel flooded pan %d"%i)
	var level0:=SB.level(world.state)
	var ka:=sb_ok(SB.POUR_ACTION,"a","K pours the shared tank into pan a")
	sb_deny(SB.POUR_ACTION,SB.TANK,"a",SB.PAN_RICH,"K pours into a nearly-crystallised pan",true,true)
	var kb:=sb_ok(SB.POUR_ACTION,"b","K pours the shared tank into pan b")
	if failed:return
	sb_check(ka==9 and kb==9 and SB.level(world.state)==level0-18,"K poured 9 + 9 of A's buckets (level %d -> %d)"%[level0,SB.level(world.state)])
	wait_until(func():return str(world.state.salt_pan.pans[2].s)=="salt",15.0,600.0,"K's pan crystallises")
	if failed:return
	sb_rake(2,"K's batch from A's brine")
	sb_info.second={"weather":sb_weather(),"poured":[ka,kb],"level_after":SB.level(world.state)}

func sb_stock_batch_lot() -> void:
	if raining():sb_dry_morning()
	if failed:return
	var before:=SR.stocked_total(world.state)
	consumed_salt+=SR.LOT_SALT
	sact(SR.STOCK_ACTION,SR.WORKER,"",{"sea_salt":-SR.LOT_SALT})
	sb_check(SR.stocked_total(world.state)==before+1,"Exactly one lot joins the shared order")

func sb_complete_batch() -> void:
	if not sb_check(SR.stocked_total(world.state)==1,"The order already contains A's tank-fed salt"):return
	# K's prior harvest used shared brine produced by A. Stock it before earning any other salt.
	tok=tk("k")
	sb_stock_batch_lot()
	if failed:return
	tok=TOKEN_A
	var pan:=int(SB.pan_ids(world.state,tok)[0])
	while not failed and SR.stocked_total(world.state)<SR.TOTAL:
		if int(bag().get(SR.SALT_ITEM,0))<SR.LOT_SALT:
			if raining():sb_dry_morning()
			if SB.pan_progress(world.state,pan).s=="empty":sact("salt_flood",pan_cell(pan))
			if failed:return
			if SB.pour_block(world.state,"a",tok).is_empty():sb_ok(SB.POUR_ACTION,"a","prepare the next lot for the basket order")
			wait_until(func()->bool:return SB.pan_progress(world.state,pan).s=="salt",60.0,4.0*WEATHER.DAY_SECONDS,"salt for the basket order")
			sb_rake(pan,"basket order")
		if not failed:sb_stock_batch_lot()
	if failed:return
	var needed_fiber:=SR.TOTAL*SR.FIBER_PER_BASKET
	if int(bag().get(SR.FIBER_ITEM,0))<needed_fiber:
		strav(S.TRANSFER,"home")
		while not failed and int(bag().get(SR.FIBER_ITEM,0))<needed_fiber:
			hit_resource("tree")
		strav(FERRY,S.REGION)
	wait_until(func()->bool:return raining(),60.0,8.0*WEATHER.DAY_SECONDS,"rain for basket packing")
	if failed:return
	var order:=SR.order(world.state)
	for kind:String in SR.KINDS:
		for index in int(order[kind]):sact(SR.PACK_ACTION,SR.CHEST,kind,{"fiber":-SR.FIBER_PER_BASKET})
	if not sb_check(SR.packed(world.state)==order and SR.rain_packs(world.state)==SR.TOTAL,"All six baskets match the order and were packed in rain"):return
	sact(SR.SEND_ACTION,SR.STOP)
	sact(SR.CLAIM_ACTION,SR.WORKER)
	if not sb_check(SR.completed(world.state) and SR.claimed_own(world.state,tok) and int(bag().get(SR.BASKET_ITEM,0))==1,
		"A ships the order and earns exactly one salt basket"):return
	sb_info.baskets={"ingredients":order,"packed_in_rain":SR.rain_packs(world.state),"shipped_day":SR.record(world.state).done_day}
	sb_reload("shipped basket order",0.0)
	if not failed:sb_check(SR.completed(world.state) and SR.claimed_own(world.state,tok) and int(bag().get(SR.BASKET_ITEM,0))==1,
		"Shipment and reward survive reload")

func sb_final() -> void:
	sb_reload("final",0.0)
	if failed:return
	sb_check(SB.level(world.state)==sb_stored-sb_poured,"bucket ledger: level %d == stored %d - poured %d"%[SB.level(world.state),sb_stored,sb_poured])
	sb_check(sb_changed==0,"every refusal left the world unchanged")
	var reasons:=[SB.WRONG_REGION,SB.NOT_READY,SB.NO_UNIT,SB.NO_WHEEL,SB.TOO_FAR,SB.WRONG_CELL,SB.BAD_PAN,SB.PAN_EMPTY,SB.PAN_SALT,SB.TANK_EMPTY,SB.RAIN_POUR,SB.PAN_RICH,SB.TANK_FULL]
	var missing:=[]
	for r in reasons:
		if not sb_reasons.has(r):missing.append(r)
	sb_check(missing.is_empty() and sb_reasons.has("THIN"),"every reachable refusal happened (missing %s)"%JSON.stringify(missing))

# ---------------------------------------------------------------- helpers

func sb_check(condition:bool,message:String) -> bool:
	return expect(condition,"SALT_BRINE_JOURNEY: "+message)

func sb_dist(cell:Vector2i) -> float:
	return Vector2(person().x,person().y).distance_to(Vector2(cell)+Vector2(0.5,0.5))

func sb_weather() -> String:
	return WEATHER.outdoor_id(WEATHER.day_index(now()))

## Waits (World.step) to 1 s after the start of a dry Beimen day.
func sb_dry_morning() -> void:
	for guard in 8:
		if failed:return
		var into:=now()-WEATHER.day_index(now())*WEATHER.DAY_SECONDS
		if not raining() and into<=60.0:return
		wait(next_midnight()-now()+1.0)
	sb_check(false,"no dry morning within 8 days")

func sb_rake(pan_id:int,label:String) -> void:
	if failed:return
	var held:=int(bag().get("sea_salt",0))
	sact("salt_rake",pan_cell(pan_id),"",{"sea_salt":S.YIELD})
	sb_check(int(bag().get("sea_salt",0))==held+S.YIELD and str(world.state.salt_pan.pans[pan_id].s)=="empty","%s rakes pan %d (%s): +%d sea salt"%[tok,pan_id,label,S.YIELD])
	sb_rakes.append({"who":tok,"pan":pan_id,"label":label,"day":int(WEATHER.day_index(now())),"weather":sb_weather(),"world_seconds":now()})

## Refused with the exact message; whole World.state unchanged (== and sorted bytes).
## pure: the position-independent store_block / pour_block must say the same.
func sb_deny(action:String,target:Vector2i,side:String,message:String,label:String,walk:=true,pure:=false) -> void:
	if failed:return
	if walk:walk_to(target)
	if failed:return
	if pure:
		var block:String=SB.store_block(world.state,side,tok) if action==SB.STORE_ACTION else SB.pour_block(world.state,side,tok)
		sb_check(block==message,"%s: pure block agrees '%s' (got '%s')"%[label,message,block])
	actions+=1
	var state_before:=world.state.duplicate(true)
	var bytes_before:=canon_bytes(world.state)
	var result:=world.act(tok,"sb-journey-%d"%actions,action,target,side)
	sb_check(not result.ok and str(result.message)==message,"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var unchanged:=world.state==state_before and canon_bytes(world.state)==bytes_before
	sb_check(unchanged,label+": whole world state unchanged")
	if not unchanged:sb_changed+=1
	var reason:="THIN" if message.begins_with("這方鹽田的滷水還太淡") else message
	sb_reasons[reason]=true
	sb_refusals.append("%s | %s %s %s | %s | %s day %d %s | state_unchanged=%s"%[label,action,str(target),side,str(result.message),tok,int(WEATHER.day_index(now())),sb_weather(),str(unchanged)])
	salt_check("refused "+action)

## A successful store / pour by `tok` on its own `side`: exact message, exact bucket
## arithmetic (computed beforehand with the pure views), and a whole-state diff limited
## to state.salt_brine, that one pan, the actor's receipts and the commit counter.
func sb_ok(action:String,side:String,label:String) -> int:
	if failed:return 0
	walk_to(SB.TANK)
	if failed:return 0
	var s:=world.state
	var ids:Array=SB.pan_ids(s,tok)
	var at:=SB.SIDES.find(side)
	if not sb_check(ids.size()==2 and at>=0,"%s: %s has a unit and side %s"%[label,tok,side]):return 0
	var pan_id:int=int(ids[at])
	var view:=SB.pan_progress(s,pan_id)
	var held:=SB.level(s)
	var cur:=float(view.p)
	var rainy:=SB.rainy_now(s)
	var store:=action==SB.STORE_ACTION
	var k:=0
	var after:=0.0
	var message:=""
	if store:
		var full:=int(floorf(cur/SB.BUCKET))
		k=mini(full,SB.CAP-held)
		if k<full:sb_capped=true
		after=maxf(0.0,cur-SB.BUCKET*k)
		message=SB.STORE_OK%[k,held+k]+(SB.STORE_RAIN_NOTE if rainy else "")
	else:
		k=mini(held,int(floorf((S.NEED-1.0-cur)/SB.BUCKET)))
		after=minf(cur+SB.BUCKET*k,S.NEED-1.0)
		message=SB.POUR_OK%[k,int(floorf(after/SB.BUCKET)),held-k]
	sb_check(str(view.s)=="brine" and k>=1,"%s: pan %d brine with buckets to move (s=%s p=%.2f level %d k %d)"%[label,pan_id,str(view.s),cur,held,k])
	var block:String=SB.store_block(s,side,tok) if store else SB.pour_block(s,side,tok)
	sb_check(block=="","%s: pure block empty (got '%s')"%[label,block])
	var row:Dictionary=SB.rows(s,tok)[at]
	sb_check(int(row.store if store else row.pour)==k and int(row.pan)==pan_id,"%s: rows() shows %d buckets"%[label,k])
	actions+=1
	var before:Variant=_canon(world.state)
	var result:=world.act(tok,"sb-journey-%d"%actions,action,SB.TANK,side)
	sb_check(result.ok==true and str(result.message)==message,"%s: ok '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var pan:Dictionary=world.state.salt_pan.pans[pan_id]
	sb_check(str(pan.s)=="brine" and is_equal_approx(float(pan.p),after) and float(pan.t)==now(),"%s: pan %d p %.2f -> %.2f at t=now (got s=%s p=%.4f t=%.1f)"%[label,pan_id,cur,after,str(pan.s),float(pan.p),float(pan.t)])
	sb_check(is_equal_approx(absf(float(pan.p)-cur),SB.BUCKET*k),"%s: pan changed by exactly 48 x %d"%[label,k])
	var record:Variant=world.state.get(SB.STATE_KEY)
	var want_level:=held+k if store else held-k
	sb_check(record is Dictionary and record.size()==1 and SB.level(world.state)==want_level,"%s: tank level %d -> %d"%[label,held,want_level])
	var diffs:=[]
	sb_diffs(before,_canon(world.state),"state",diffs)
	var prefixes:=["state.%s"%SB.STATE_KEY,"state.salt_pan.pans.%d"%pan_id,"state.players.%s.receipts"%tok,"state.committed"]
	var other:=[]
	for path in diffs:
		var allowed:=false
		for prefix:String in prefixes:
			if str(path)==prefix or str(path).begins_with(prefix+"."):allowed=true
		if not allowed:other.append(path)
	sb_check(other.is_empty() and not diffs.is_empty(),"%s: whole-state diff only under %s (other %s)"%[label,str(prefixes),JSON.stringify(other.slice(0,5))])
	if store:sb_stored+=k
	else:sb_poured+=k
	sb_moves.append({"label":label,"who":tok,"action":action,"side":side,"pan":pan_id,"buckets":k,"p_before":cur,"p_after":after,"level":want_level,"day":int(WEATHER.day_index(now())),"weather":sb_weather(),"world_seconds":now()})
	salt_check("%s %s %s"%[tok,action,side])
	return k

## Differing leaf paths of two canonical values (bounded).
func sb_diffs(a:Variant,b:Variant,path:String,out:Array) -> void:
	if out.size()>=40:return
	if typeof(a)!=typeof(b):
		out.append(path)
		return
	if a is Dictionary:
		for key in a:
			if not b.has(key):out.append(path+"."+str(key))
			else:sb_diffs(a[key],b[key],path+"."+str(key),out)
		for key in b:
			if not a.has(key):out.append(path+"."+str(key))
		return
	if a is Array:
		if a.size()!=b.size():
			out.append(path)
			return
		for i in a.size():sb_diffs(a[i],b[i],"%s.%d"%[path,i],out)
		return
	if a!=b:out.append(path)

## Save, reload into a NEW World through SaveSchema, compare (salt_pan, beimen chests,
## inventories via the parent's compare_worlds, plus the tank record and every owned
## pan's integrated progress), optionally run both worlds `advance` seconds in lockstep
## and compare again, then continue in the reloaded World.
func sb_reload(label:String,advance:float) -> void:
	if failed:return
	sb_check(world.save(),label+": explicit save")
	var reopened:=World.new()
	if not sb_check(reopened.load_world(save_path) and not reopened.recovered_from_backup,label+": save loads through SaveSchema"):return
	sb_check(int(reopened.state.version)==int(World.SAVE_SCHEMA.VERSION),label+": saved version is SaveSchema.VERSION")
	for token in world.active_tokens:reopened.add_player(token,str(names.get(token,world.state.players[token].name)))
	compare_worlds(world,reopened,label+" (on load)")
	sb_compare(world,reopened,label+" (on load)")
	var copy:Dictionary=reopened.state.duplicate(true)
	sb_check(SB.valid(copy),label+": reloaded tank record valid")
	var record:Variant=reopened.state.get(SB.STATE_KEY)
	sb_check(not record is Dictionary or typeof(record.get("level"))==TYPE_INT,label+": reloaded level is an int")
	if advance>0.0:
		var old:World=world
		old.save_path=""
		var left:=advance
		while left>0.000001 and not failed:
			var dt:=minf(120.0,left)
			sb_check(old.step(dt,true) and reopened.step(dt,true),label+": both worlds step")
			left-=dt
		compare_worlds(old,reopened,label+" (after %.0f s)"%advance)
		sb_compare(old,reopened,label+" (after %.0f s)"%advance)
	world=reopened
	salt_reloads+=1
	sb_reloads+=1
	salt_check("reload "+label)

func sb_compare(a:World,b:World,label:String) -> void:
	sb_check(a.state.has(SB.STATE_KEY)==b.state.has(SB.STATE_KEY) and canon_bytes(a.state.get(SB.STATE_KEY))==canon_bytes(b.state.get(SB.STATE_KEY)),label+": tank record identical (%s vs %s)"%[JSON.stringify(a.state.get(SB.STATE_KEY)),JSON.stringify(b.state.get(SB.STATE_KEY))])
	for token in [TOKEN_A,tk("k")]:
		for pan in SB.pan_ids(a.state,token):
			var pa:=SB.pan_progress(a.state,int(pan))
			var pb:=SB.pan_progress(b.state,int(pan))
			sb_check(str(pa.s)==str(pb.s) and is_equal_approx(float(pa.p),float(pb.p)),label+": pan %d progress identical (%s %.4f vs %s %.4f)"%[int(pan),str(pa.s),float(pa.p),str(pb.s),float(pb.p)])

func finish() -> void:
	if sb_started:
		print("SALT_BRINE_JOURNEY info=%s"%JSON.stringify(sb_info))
		for r in sb_moves:print("SALT_BRINE_JOURNEY move %s"%JSON.stringify(r))
		for r in sb_rakes:print("SALT_BRINE_JOURNEY rake %s"%JSON.stringify(r))
	for i in sb_refusals.size():print("SALT_BRINE_JOURNEY refusal %d %s"%[i+1,sb_refusals[i]])
	if sb_started:
		var t:=float(world.state.get("time",0.0))
		print("SALT_BRINE_JOURNEY stats segment_actions=%d segment_refusals=%d all_refusals_state_unchanged=%s segment_walk_tiles=%d segment_world_seconds=%.1f segment_reloads=%d segment_checks=%d segment_ms=%d stored=%d poured=%d level=%d actions_total=%d walk_tiles_total=%d world_seconds_total=%.1f passed=%s"%[actions-sb_actions0,sb_refusals.size(),str(sb_changed==0),walking-sb_walk0,t-sb_time0,sb_reloads,checks-sb_checks0,Time.get_ticks_msec()-sb_ms,sb_stored,sb_poured,SB.level(world.state),actions,walking,t,str(not failed)])
	else:
		print("SALT_BRINE_JOURNEY did not reach the brine segment (refusals so far %d)"%sb_refusals.size())
	# The inherited summary (printed here instead of super.finish() so the brine line is
	# last and quit() runs once).
	var runtime:=Time.get_ticks_msec()-started_ms
	print("SALT_PAN_JOURNEY label=\"%s\" actions=%d walk_tiles=%d reloads=%d salt_reloads=%d world_seconds=%.1f runtime_ms=%d"%[SALT_LABEL,actions,walking,reloads,salt_reloads,float(world.state.get("time",0.0)),runtime])
	print("SALT_BRINE_JOURNEY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
