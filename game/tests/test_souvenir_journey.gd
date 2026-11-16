extends "res://tests/test_flower_journey.gd"
## T071 natural souvenir journey (紀念票兌換裝飾): a FRESH single-player World plays
## from a brand-new save, through the chapter-one steps and the 渡口野餐, earns
## tickets in real 豐收接力 / 河岸釣魚會 / 家園布置題 rounds, redeems them at the
## 紀念品交換攤 and places the decorations at home through the normal build action.
## Also the first natural journey for 家園布置題 (showcase).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
## One player, one process, one World at a time (reloads are in-process
## World.new().load_world on the same save file). Everything goes through
## World.act (after walking cell by cell with World.move_player along passable
## tiles) and World.step(dt,true).
##
## WALKING IS FREE IN THIS HARNESS: World.move_player moves the avatar but never
## advances state.time. From the picnic on, this file advances the clock with
## World.step (same mechanism as the harvest-relay / fishing-meet journeys) by
##   * tiles_walked / 3.6 world seconds after every walking leg (3.6 tiles/s is the
##     full-input speed coded in World.move_player), and
##   * ACTION_SECONDS (1.0 s, an assumed click/animation cost) after every action
##     attempted (successes and refusals alike);
## the fish bite is waited for with World.step up to player.fishing.ready, and
## activity cooldowns are waited through with explicit World.step waits. Before
## the picnic the clock only moves through the reused chapter_one() waits.
##
## Prerequisite (reused parent logic, unmodified): test_flower_journey.chapter_one()
## — chapter one earned on a fresh world. Its act() calls are intercepted only to
## insert the pre-picnic booth refusals right before the picnic action.
## SKIPPED: chapters two to five; trading with another player (single player).
##
## Journey:
##  1. before the picnic: locked view, every redemption refused (LOCKED), state unchanged;
##  2. chapter one + picnic; booth unlocked at 37,25 and blocking;
##  3. at the booth with 0 tickets: every entry refused NOT_ENOUGH, state unchanged;
##  4. real rounds (interleaved, cooldowns waited) until 12 relay / 6 fishing /
##     6 showcase tickets: relay = crate -> basket trips, fishing = real casts and
##     catches in the meet waters, showcase = 16 props placed for the theme + full
##     bonus and 完成展示 (one prop removed and re-placed, one early finish refused);
##     backpack and coins unchanged by every round, tickets paid once;
##  5. booth: too far / wrong tile / unknown entry refusals, redemptions with
##     whole-inventory + coins diffs, view balance = earned - spent, ticket counters
##     unchanged, stale resend (same request id = stored receipt; new id = STALE),
##     save + reload mid-journey, more redemptions, NOT_ENOUGH refusals;
##  6. kit cannot be shipped, stall-listed or sold to 小栗;
##  7. four decorations built on free grass, one moved, one picked up (kit back, no
##     refund), no kit -> build refused, decorations walked through;
##  8. final save -> reload into a fresh World: position, inventory, coins,
##     souvenir record, tickets, placed objects, view.
## Every refusal: exact message, whole World.state unchanged (== and canonical
## var_to_bytes). NOT preset: this file writes no state field. Prints
## SOUVENIR_JOURNEY lines and SOUVENIR_JOURNEY_TESTS checks=N failures=M.

const H=preload("res://scripts/harvest_relay.gd")
const M=preload("res://scripts/fishing_meet.gd")
const S=preload("res://scripts/showcase.gd")
const SV=preload("res://scripts/souvenir_exchange.gd")
const MARKET=preload("res://scripts/market_stall.gd")
const WALK_TILES_PER_SECOND:=3.6
const ACTION_SECONDS:=1.0
const ADJACENT:=1.5
const BOOTH:=Vector2i(37,25)
const SHOP:=Vector2i(43,29)
const BOARD_CELL:=Vector2i(40,29)
const SHORE_SPOT:=Vector2i(54,36)
const SHORE_WATER:=Vector2i(55,36)
const ACTS:=["harvest_relay","fish_meet","showcase"]
const ACT_NAMES:={"harvest_relay":"豐收接力","fish_meet":"河岸釣魚會","showcase":"家園布置題"}
## Independent copy of the documented catalogue (souvenir_exchange.gd header).
const DOC_ORDER:=["veg_basket_rack","relay_crate_stack","carp_banner","float_garland","lantern_post","flower_arch","trio_keepsake"]
const DOC_NAMES:={"veg_basket_rack":"菜籃小架","relay_crate_stack":"接力菜箱堆","carp_banner":"鯽魚布旗","float_garland":"浮球串飾","lantern_post":"紙燈籠柱","flower_arch":"花草拱架","trio_keepsake":"三活動紀念牌"}
const DOC_COSTS:={"veg_basket_rack":{"harvest_relay":3},"relay_crate_stack":{"harvest_relay":6},"carp_banner":{"fish_meet":3},"float_garland":{"fish_meet":6},"lantern_post":{"showcase":3},"flower_arch":{"showcase":6},"trio_keepsake":{"harvest_relay":3,"fish_meet":3,"showcase":3}}
## Independent copy of the documented showcase theme order.
const DOC_THEMES:=["garden_tea","sea_breeze","warm_night","harvest_corner"]
## Tickets needed: veg_basket_rack + relay_crate_stack + trio (12 relay),
## carp_banner + trio (6 fishing), lantern_post + trio (6 showcase).
const TARGET:={"harvest_relay":12,"fish_meet":6,"showcase":6}
const REDEEM_BEFORE_SAVE:=["veg_basket_rack","carp_banner","lantern_post"]
const REDEEM_AFTER_SAVE:=["relay_crate_stack","trio_keepsake"]
const DECOR:=["veg_basket_rack","carp_banner","lantern_post","trio_keepsake"]
## Free grass west of the spawn (the 34..37,33..37 build area); chosen at run time
## among these only when empty, not protected and without a resource.
const DECOR_CANDIDATES:=[Vector2i(35,34),Vector2i(36,34),Vector2i(34,34),Vector2i(34,36),Vector2i(36,36),Vector2i(35,37),Vector2i(34,37),Vector2i(36,37)]
const SHOW_CELLS:=16

var pre_picnic_done:=false
var refusals:=0
var clock_on:=false
var walk_seconds:=0.0
var action_seconds:=0.0
var bite_seconds:=0.0
var cooldown_seconds:=0.0
var picnic_time:=0.0
var picnic_actions:=0
var picnic_walk:=0
var earn_end_time:=0.0
var earn_actions:=0
var earn_walk:=0
var rounds:={"harvest_relay":[],"fish_meet":[],"showcase":[]}
var paid_after:={}
var spent:={"harvest_relay":0,"fish_meet":0,"showcase":0}
var redeemed:={}
var redemptions:=0
var decor_tiles:={}
var started_ms:=0

func expect(condition:bool,message:String) -> bool:
	checks+=1
	if not condition:
		failures+=1
		failed=true
		push_error("SOUVENIR_JOURNEY FAIL: "+message)
	return condition

func finish() -> void:
	var counts:={}
	for a:String in ACTS:counts[a]=(rounds[a] as Array).size()
	var earned:=earned_now() if world.state.players.has(TOKEN_A) else {}
	print("SOUVENIR_JOURNEY label=\"%s\" actions=%d walk_tiles=%d world_seconds=%.1f post_picnic_actions=%d post_picnic_walk_tiles=%d post_picnic_world_seconds=%.1f earning_actions=%d earning_walk_tiles=%d earning_world_seconds=%.1f cooldown_wait_seconds=%.1f walk_seconds_added=%.1f action_seconds_added=%.1f bite_seconds_waited=%.1f rounds=%s tickets_earned=%s tickets_spent=%s redemptions=%d decor=%s reloads=%d refusals=%d runtime_ms=%d"%[LABEL,actions,walking,float(world.state.get("time",0.0)),actions-picnic_actions,walking-picnic_walk,float(world.state.get("time",0.0))-picnic_time,earn_actions,earn_walk,earn_end_time-picnic_time,cooldown_seconds,walk_seconds,action_seconds,bite_seconds,JSON.stringify(counts),JSON.stringify(earned),JSON.stringify(spent),redemptions,JSON.stringify(decor_tiles),reloads,refusals,Time.get_ticks_msec()-started_ms])
	for a:String in ACTS:print("SOUVENIR_JOURNEY rounds %s %s"%[a,JSON.stringify(rounds[a])])
	print("SOUVENIR_JOURNEY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ---------------------------------------------------------------- journey

func run() -> void:
	started_ms=Time.get_ticks_msec()
	tok=TOKEN_A
	world.add_player(TOKEN_A,"Bloom A")
	expect(not person().has("souvenir") and not SV.unlocked(world.state),"fresh world: booth locked, no souvenir record")
	expect(SV.ENTRY_ORDER==DOC_ORDER,"catalogue order equals the documented order")
	for entry:String in DOC_ORDER:
		expect(same(SV.ENTRIES[entry].cost,DOC_COSTS[entry]) and str(SV.ENTRIES[entry].name)==str(DOC_NAMES[entry]),"%s cost/name equal the documented catalogue"%entry)
	chapter_one()
	if failed:return
	if not expect(pre_picnic_done,"pre-picnic booth refusals ran"):return
	var v:=world.souvenir_view(tok)
	expect(world.state.picnic==true and v.unlocked==true and v.available==true and v.can_redeem==true and v.point==BOOTH,"picnic done: booth unlocked at %s"%str(v.point))
	expect(world.blocked(BOOTH) and world.protected(BOOTH),"after the picnic the booth tile blocks movement and is protected")
	expect(same(v.earned,zero()) and same(v.balance,zero()) and same(v.spent,zero()) and int(v.redeemed_total)==0,"picnic done: no tickets yet")
	expect(not person().has("souvenir"),"picnic writes no souvenir record")
	print("SOUVENIR_JOURNEY chapter one + picnic done (checks %d, actions %d, world_seconds %.1f, walk_tiles %d)"%[checks,actions,now(),walking])
	picnic_time=now()
	picnic_actions=actions
	picnic_walk=walking
	clock_on=true
	booth_with_no_tickets()
	if failed:return
	earn_tickets()
	if failed:return
	redeem_leg()
	if failed:return
	not_currency()
	if failed:return
	place_leg()
	if failed:return
	persist("final")
	if failed:return
	var record:=SV.record(person())
	expect(same(record.spent,spent) and same(record.redeemed,redeemed),"final reload: souvenir record spent %s redeemed %s"%[JSON.stringify(record.spent),JSON.stringify(record.redeemed)])

## Intercepts the reused chapter_one() right before its picnic action.
func act(action:String,target:Vector2i,extra:String="") -> Dictionary:
	if action=="picnic" and not pre_picnic_done and not failed:
		pre_picnic_done=true
		pre_picnic()
	return super.act(action,target,extra)

# ---------------------------------------------------------------- 1. before the picnic

func pre_picnic() -> void:
	expect(not world.state.picnic,"before the picnic: picnic false")
	var v:=world.souvenir_view(tok)
	expect(v.unlocked==false and v.available==false and v.can_redeem==false and v.point==SV.NO_CELL,"before the picnic the view says locked (%s)"%JSON.stringify([v.unlocked,v.available,v.can_redeem,v.point]))
	expect(not world.blocked(BOOTH) and not world.protected(BOOTH),"before the picnic the booth tile is ordinary grass")
	walk_near(BOOTH,2.0)
	for entry:String in DOC_ORDER:
		deny("souvenir_redeem",BOOTH,entry+"|0",SV.LOCKED,"%s before the picnic"%entry)
	deny("souvenir_redeem",BOOTH,"bonfire|0",SV.LOCKED,"unknown entry before the picnic")
	expect(not person().has("souvenir"),"no souvenir record written before the picnic")

# ---------------------------------------------------------------- 3. booth, no tickets

func booth_with_no_tickets() -> void:
	go(BOOTH,2.0)
	expect(distance_to(BOOTH)<=SV.REACH,"standing within reach of the booth (%.2f)"%distance_to(BOOTH))
	var v:=world.souvenir_view(tok)
	for e:Dictionary in v.entries:
		expect(e.affordable==false and int(e.held)==0 and int(e.redeemed)==0 and str(e.extra)==str(e.id)+"|0","%s not affordable with 0 tickets"%str(e.id))
	for entry:String in DOC_ORDER:
		deny("souvenir_redeem",BOOTH,entry+"|0",SV.NOT_ENOUGH%short_text(entry,zero()),"%s with 0 tickets"%entry)
	expect(not person().has("souvenir"),"zero-ticket refusals wrote no souvenir record")

# ---------------------------------------------------------------- 4. earning

func earn_tickets() -> void:
	var start_actions:=actions
	var start_walk:=walking
	for guard in 12:
		if failed or enough():break
		for activity:String in ACTS:
			if failed:return
			if int(earned_now()[activity])>=int(TARGET[activity]):continue
			match activity:
				"harvest_relay":play_harvest()
				"fish_meet":play_fish()
				"showcase":play_showcase()
	if failed:return
	expect(enough(),"earned enough tickets: %s"%JSON.stringify(earned_now()))
	earn_end_time=now()
	earn_actions=actions-start_actions
	earn_walk=walking-start_walk
	var sums:={}
	for a:String in ACTS:
		var total:=0
		for r:Dictionary in rounds[a]:total+=int(r.tickets)
		sums[a]=total
	expect(same(earned_now(),sums),"earned tickets equal the sum of the settled rounds (%s)"%JSON.stringify(sums))
	var v:=world.souvenir_view(tok)
	expect(same(v.earned,sums) and same(v.balance,sums) and same(v.spent,zero()),"view: earned = balance = %s before spending"%JSON.stringify(sums))
	print("SOUVENIR_JOURNEY earning done: tickets %s, rounds %s, world_seconds since picnic %.1f, actions %d, walk_tiles %d"%[JSON.stringify(sums),JSON.stringify(round_counts()),earn_end_time-picnic_time,earn_actions,earn_walk])

func enough() -> bool:
	var got:=earned_now()
	for a:String in ACTS:
		if int(got[a])<int(TARGET[a]):return false
	return true

## Waits through the activity cooldown (explicit World.step) and checks that no
## second payout happened since the previous round of the same activity.
func before_round(activity:String,round_state:Dictionary) -> float:
	var waited:=0.0
	if paid_after.has(activity):
		expect(same(activity_record(activity),paid_after[activity]),"%s: no second payout since the last round"%activity)
	if round_state.active!=true and now()<float(round_state.ready):
		waited=float(round_state.ready)-now()+0.5
		cooldown_seconds+=waited
		wait(waited)
	return waited

func play_harvest() -> void:
	go(H.SIGN)
	var waited:=before_round("harvest_relay",H.round_state(world.state))
	if failed:return
	var bag0:=nonzero(bag())
	var coins0:=int(person().coins)
	var rec0:=H.record(person()).duplicate(true)
	var round_id:=int(world.harvest_view(tok).round)+1
	var t0:=now()
	var walk0:=walking
	var actions0:=actions
	var result:=do("harvest_start",H.SIGN,str(round_id-1))
	if failed:return
	expect(str(result.message).begins_with("第 %d 輪豐收接力開始！"%round_id),"relay start message: "+str(result.message))
	var trips:=0
	for guard in 120:
		if failed or H.round_state(world.state).active!=true:break
		go(H.CRATE)
		if failed or H.round_state(world.state).active!=true:break
		do("harvest_pick",H.CRATE,"")
		if failed:return
		var kind:=str(world.harvest_view(tok).carry)
		if not expect(H.KINDS.has(kind),"carrying a model vegetable (%s)"%kind):return
		expect(same(nonzero(bag()),bag0),"relay pick: model vegetables never enter the backpack")
		var basket:=H.basket_of(kind)
		go(H.BASKETS[basket])
		if failed or H.round_state(world.state).active!=true:break
		do("harvest_sort",H.BASKETS[basket],"")
		if failed:return
		trips+=1
		expect(same(nonzero(bag()),bag0) and int(person().coins)==coins0,"relay sort %d: backpack and coins unchanged"%trips)
	if failed:return
	var rs:=H.round_state(world.state)
	if not expect(rs.active==false and int((rs.last as Dictionary).get("round",0))==round_id,"relay round %d settled"%round_id):return
	var last:Dictionary=rs.last
	var tickets:=H.tickets_for(int(last.delivered))
	expect(int(last.tickets)==tickets and int(last.players)==1,"relay last: delivered %d tickets %d (%s)"%[int(last.delivered),tickets,JSON.stringify(last)])
	expect(same(H.record(person()),{"tickets":int(rec0.tickets)+tickets,"rounds":int(rec0.rounds)+1,"best":maxi(int(rec0.best),int(last.delivered)),"paid_round":round_id}),"relay round %d paid tickets_for(%d)=%d once"%[round_id,int(last.delivered),tickets])
	expect(same(nonzero(bag()),bag0) and int(person().coins)==coins0,"after relay round %d backpack and coins equal the pre-round values"%round_id)
	paid_after["harvest_relay"]=H.record(person()).duplicate(true)
	var row:={"round":round_id,"delivered":int(last.delivered),"trips":trips,"reason":str(last.reason),"tickets":tickets,"world_seconds":snappedf(float(last.finished)-t0,0.01),"walk_tiles":walking-walk0,"actions":actions-actions0,"cooldown_waited":snappedf(waited,0.01)}
	rounds.harvest_relay.append(row)
	print("SOUVENIR_JOURNEY relay %s"%JSON.stringify(row))

func play_fish() -> void:
	go(M.SIGN)
	var waited:=before_round("fish_meet",M.round_state(world.state))
	if failed:return
	var bag0:=nonzero(bag())
	var coins0:=int(person().coins)
	var rec0:=M.record(person()).duplicate(true)
	var round_id:=int(world.fish_meet_view(tok).round)+1
	var t0:=now()
	var walk0:=walking
	var actions0:=actions
	var result:=do("fish_meet_start",M.SIGN,str(round_id-1))
	if failed:return
	expect(str(result.message).begins_with("第 %d 輪河岸釣魚會開始！"%round_id),"fishing start message: "+str(result.message))
	go(SHORE_WATER,1.0)
	expect(Vector2(person().x,person().y).distance_to(Vector2(SHORE_SPOT)+Vector2(0.5,0.5))<=0.001,"standing on the shore spot %s"%str(SHORE_SPOT))
	var casts:=[]
	var centre:=Vector2(SHORE_SPOT)+Vector2(0.5,0.5)
	for cell:Vector2i in M.water_cells():
		if centre.distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2 and world.water(cell):casts.append(cell)
	if not expect(casts.size()>=4,"at least four meet waters within reach (%d)"%casts.size()):return
	var records:=0
	for guard in 40:
		if failed or M.round_state(world.state).active!=true:break
		var cell:Vector2i=casts[records%casts.size()]
		var before:=core()
		var kind:=M.kind_at(round_id,records)
		do("fish_start",cell,"")
		if failed:return
		var ready:=float(person().fishing.ready)
		if now()<ready:
			bite_seconds+=ready-now()
			wait(ready-now())
		if not expect(M.round_state(world.state).active==true,"the round is still running when the fish bites"):return
		result=do("fish_catch",cell,"")
		if failed:return
		records+=1
		expect(str(result.get("fish_meet",""))==kind and int(M.round_state(world.state).records)==records,"record %d is %s"%[records,kind])
		expect(same(core(),before),"record %d: whole player record unchanged (backpack, coins, fish_caught, collection)"%records)
	if failed:return
	var rs:=M.round_state(world.state)
	if not expect(rs.active==false and int((rs.last as Dictionary).get("round",0))==round_id,"fishing round %d settled"%round_id):return
	var last:Dictionary=rs.last
	var tickets:=M.tickets_for(int(last.species),int(last.records))
	expect(int(last.tickets)==tickets and int(last.records)==records and int(last.players)==1,"fishing last: records %d species %d tickets %d (%s)"%[records,int(last.species),tickets,JSON.stringify(last)])
	expect(same(M.record(person()),{"tickets":int(rec0.tickets)+tickets,"rounds":int(rec0.rounds)+1,"best":maxi(int(rec0.best),int(last.records)),"paid_round":round_id}),"fishing round %d paid %d once"%[round_id,tickets])
	expect(same(nonzero(bag()),bag0) and int(person().coins)==coins0,"after fishing round %d backpack and coins equal the pre-round values"%round_id)
	paid_after["fish_meet"]=M.record(person()).duplicate(true)
	var row:={"round":round_id,"records":int(last.records),"species":int(last.species),"reason":str(last.reason),"tickets":tickets,"world_seconds":snappedf(float(last.finished)-t0,0.01),"walk_tiles":walking-walk0,"actions":actions-actions0,"cooldown_waited":snappedf(waited,0.01)}
	rounds.fish_meet.append(row)
	print("SOUVENIR_JOURNEY fishing %s"%JSON.stringify(row))

## Kinds for one showcase round: the theme's needs first, then filler up to 16.
func show_plan(theme:String) -> Array:
	var by_category:={"flower":["flower_pot","flower_box","fern"],"seat":["stool","bench","cushion"],"light":["lantern","string_lights"]}
	var need:Dictionary=S.THEMES[theme].need
	var out:=[]
	for category:String in S.CATEGORIES:
		var kinds:Array=by_category[category]
		for i in int(need[category]):out.append(kinds[i%kinds.size()])
	var j:=0
	while out.size()<SHOW_CELLS:
		out.append(S.KIND_ORDER[j%S.KIND_ORDER.size()])
		j+=1
	return out

func play_showcase() -> void:
	go(S.SIGN)
	var waited:=before_round("showcase",S.round_state(world.state))
	if failed:return
	expect(S.round_state(world.state).pieces.is_empty(),"the plot is empty before the round (props cleared after the cooldown)")
	var bag0:=nonzero(bag())
	var coins0:=int(person().coins)
	var rec0:=S.record(person()).duplicate(true)
	var round_id:=int(world.showcase_view(tok).round)+1
	var theme:=str(DOC_THEMES[(round_id-1)%DOC_THEMES.size()])
	var t0:=now()
	var walk0:=walking
	var actions0:=actions
	var result:=do("showcase_start",S.SIGN,str(round_id-1))
	if failed:return
	expect(str(result.message).begins_with("第 %d 輪家園布置題開始！本輪主題「%s」"%[round_id,S.theme_name(theme)]),"showcase start message: "+str(result.message))
	var v:=world.showcase_view(tok)
	expect(str(v.theme)==theme and v.active==true and v.joined==true,"showcase round %d theme %s (documented order)"%[round_id,theme])
	var plan:=show_plan(theme)
	var cells:Array=S.plot_cells().slice(0,SHOW_CELLS)
	var met_at:=-1
	var first_round:=(rounds.showcase as Array).is_empty()
	for i in SHOW_CELLS:
		if failed:return
		var cell:Vector2i=cells[i]
		var kind:=str(plan[i])
		go(cell)
		if not expect(S.round_state(world.state).active==true,"showcase round still running at placement %d"%(i+1)):return
		if first_round and i==0:
			deny("showcase_finish",cell,str(round_id),S.NOT_MET,"finish before the theme is met")
		var was_met:=S.theme_met(theme,S.round_state(world.state).pieces)
		result=do("showcase_place",cell,"%d|%s"%[round_id,kind])
		if failed:return
		expect(str(result.message).begins_with("擺上%s。"%S.kind_name(kind)),"place message: "+str(result.message))
		var now_met:=S.theme_met(theme,S.round_state(world.state).pieces)
		if now_met and not was_met:
			met_at=i+1
			expect(str(result.message).contains("主題完成了！"),"theme-met message at placement %d"%(i+1))
		expect(same(nonzero(bag()),bag0) and int(person().coins)==coins0,"placement %d (%s): props never enter the backpack, coins unchanged"%[i+1,kind])
		if first_round and i==0:
			result=do("showcase_remove",cell,str(round_id))
			if failed:return
			expect(str(result.message).begins_with("收起%s。"%S.kind_name(kind)) and not S.round_state(world.state).pieces.has(S.cell_key(cell)),"prop removed again: "+str(result.message))
			expect(same(nonzero(bag()),bag0),"removing a prop leaves the backpack unchanged")
			deny("showcase_remove",cell,str(round_id),S.NO_PIECE,"remove from an empty plot cell")
			result=do("showcase_place",cell,"%d|%s"%[round_id,kind])
			if failed:return
			deny("showcase_place",cell,"%d|%s"%[round_id,kind],S.TILE_TAKEN,"place on an occupied plot cell")
	v=world.showcase_view(tok)
	expect(v.theme_met==true and v.full==true and int(v.pieces_count)==SHOW_CELLS and int(v.placed)==SHOW_CELLS+(1 if first_round else 0) and int(v.shown)==SHOW_CELLS,"showcase round %d: theme met (at placement %d), full display, %d pieces (%s)"%[round_id,met_at,int(v.pieces_count),JSON.stringify([v.theme_met,v.full,v.placed,v.shown])])
	expect(v.can_finish==true,"view: can finish")
	result=do("showcase_finish",Vector2i(int(person().x),int(person().y)),str(round_id))
	if failed:return
	var tickets:=S.tickets_for(true,true)
	expect(str(result.message)=="「%s」布置完成！地塊上共 %d 件，參加者各得 %d 張紀念票。展示會保留到冷卻結束。"%[S.theme_name(theme),SHOW_CELLS,tickets],"finish message: "+str(result.message))
	var rs:=S.round_state(world.state)
	var last:Dictionary=rs.last
	expect(rs.active==false and int(last.round)==round_id and str(last.reason)=="goal" and last.met==true and last.full==true and int(last.tickets)==tickets and int(last.players)==1,"showcase last: %s"%JSON.stringify(last))
	expect(same(S.record(person()),{"tickets":int(rec0.tickets)+tickets,"rounds":int(rec0.rounds)+1,"best":maxi(int(rec0.best),SHOW_CELLS),"paid_round":round_id}),"showcase round %d paid %d once"%[round_id,tickets])
	expect(same(nonzero(bag()),bag0) and int(person().coins)==coins0,"after showcase round %d backpack and coins equal the pre-round values"%round_id)
	deny("showcase_finish",S.SIGN,str(round_id),S.NOT_ACTIVE,"finish twice")
	paid_after["showcase"]=S.record(person()).duplicate(true)
	var row:={"round":round_id,"theme":theme,"pieces":int(last.pieces),"met_at":met_at,"full":last.full,"reason":str(last.reason),"tickets":tickets,"world_seconds":snappedf(float(last.finished)-t0,0.01),"walk_tiles":walking-walk0,"actions":actions-actions0,"cooldown_waited":snappedf(waited,0.01)}
	rounds.showcase.append(row)
	print("SOUVENIR_JOURNEY showcase %s"%JSON.stringify(row))

# ---------------------------------------------------------------- 5. redemption

func redeem_leg() -> void:
	var counters:=ticket_records()
	if expect(distance_to(BOOTH)>SV.REACH,"after earning the player stands %.2f tiles from the booth"%distance_to(BOOTH)):
		deny("souvenir_redeem",BOOTH,"veg_basket_rack|0",SV.TOO_FAR,"redeem from too far")
	go(BOOTH,2.0)
	expect(distance_to(BOOTH)<=SV.REACH,"at the booth (%.2f)"%distance_to(BOOTH))
	deny("souvenir_redeem",Vector2i(35,26),"veg_basket_rack|0",SV.WRONG_POINT,"redeem on another candidate tile")
	deny("souvenir_redeem",BOARD_CELL,"veg_basket_rack|0",SV.WRONG_POINT,"redeem on the notice board tile")
	deny("souvenir_redeem",BOOTH,"bonfire|0",SV.UNKNOWN_ENTRY,"unknown entry")
	deny("souvenir_redeem",BOOTH,"veg_basket_rack_kit|0",SV.UNKNOWN_ENTRY,"kit id instead of an entry")
	deny("souvenir_redeem",BOOTH,"veg_basket_rack|1",SV.STALE,"count ahead of the record")
	var first:=true
	for entry:String in REDEEM_BEFORE_SAVE:
		var request:=redeem(entry)
		if failed:return
		if first:
			first=false
			# Resending the very same request id returns the stored receipt.
			var receipt:Dictionary=person().receipts[request].duplicate(true)
			var state_before:=world.state.duplicate(true)
			var resend:=world.act(tok,request,"souvenir_redeem",BOOTH,entry+"|0")
			expect(same(resend,receipt) and world.state==state_before,"same request id resent: stored receipt, nothing applied twice")
			spend(ACTION_SECONDS)
			deny("souvenir_redeem",BOOTH,entry+"|0",SV.STALE,"new request with the same extra (stale count)")
	expect(same(ticket_records(),counters),"ticket counters unchanged by the first redemptions")
	persist("mid-journey after %d redemptions"%redemptions)
	if failed:return
	for entry:String in REDEEM_AFTER_SAVE:
		redeem(entry)
		if failed:return
	expect(same(ticket_records(),counters),"ticket counters unchanged by all redemptions")
	# Not enough for the next one.
	var balance:Dictionary=world.souvenir_view(tok).balance
	var tried:=0
	for entry:String in DOC_ORDER:
		var short:=short_text(entry,balance)
		if short.is_empty():continue
		deny("souvenir_redeem",BOOTH,"%s|%d"%[entry,int(redeemed.get(entry,0))],SV.NOT_ENOUGH%short,"%s not affordable with balance %s"%[entry,JSON.stringify(balance)])
		tried+=1
	expect(tried>=1,"at least one entry was refused as not enough (%d)"%tried)
	print("SOUVENIR_JOURNEY redemptions done: %d, spent %s, balance %s, record %s"%[redemptions,JSON.stringify(spent),JSON.stringify(balance),JSON.stringify(SV.record(person()))])

## One redemption at the booth. Returns the request id.
func redeem(entry:String) -> String:
	if failed:return ""
	var e:=entry_view(entry)
	var count:=int(redeemed.get(entry,0))
	expect(e.affordable==true and same(e.short,{}) and str(e.extra)=="%s|%d"%[entry,count] and int(e.redeemed)==count,"%s affordable, extra %s"%[entry,str(e.extra)])
	var inv0:=nonzero(bag())
	var coins0:=int(person().coins)
	var counters:=ticket_records()
	var kit:=entry+"_kit"
	actions+=1
	var request:="souvenir-journey-%d"%actions
	var result:=world.act(tok,request,"souvenir_redeem",BOOTH,str(e.extra))
	expect(result.ok,"redeem %s: %s"%[entry,str(result.message)])
	spend(ACTION_SECONDS)
	if failed:return request
	redemptions+=1
	var cost:Dictionary=DOC_COSTS[entry]
	for a:String in ACTS:spent[a]=int(spent[a])+int(cost.get(a,0))
	redeemed[entry]=count+1
	expect(str(result.message)=="用%s換到「%s」，已放進背包。在家園工坊的「生活」頁選它就能擺到家園；拆除會收回背包，不會退票。"%[spent_text(entry),str(DOC_NAMES[entry])],"redeem %s message: %s"%[entry,str(result.message)])
	var want:=inv0.duplicate()
	want[kit]=int(want.get(kit,0))+1
	expect(same(nonzero(bag()),want),"redeem %s: the whole inventory changed only by %s +1"%[entry,kit])
	expect(int(person().coins)==coins0,"redeem %s: coins unchanged"%entry)
	expect(same(ticket_records(),counters),"redeem %s: the three ticket counters are unchanged"%entry)
	var v:=world.souvenir_view(tok)
	var earned:=earned_now()
	var balance:={}
	for a:String in ACTS:balance[a]=int(earned[a])-int(spent[a])
	expect(same(v.earned,earned) and same(v.spent,spent) and same(v.balance,balance),"redeem %s: view balance %s = earned %s - spent %s"%[entry,JSON.stringify(v.balance),JSON.stringify(earned),JSON.stringify(spent)])
	expect(same(person().souvenir,{"spent":spent,"redeemed":redeemed}),"redeem %s: record %s"%[entry,JSON.stringify(person().souvenir)])
	var after:=entry_view(entry)
	expect(int(after.redeemed)==count+1 and int(after.held)==int(want[kit]) and str(after.extra)=="%s|%d"%[entry,count+1],"redeem %s: entry view redeemed %d held %d"%[entry,int(after.redeemed),int(after.held)])
	return request

# ---------------------------------------------------------------- 6. not a currency

func not_currency() -> void:
	var kit:="relay_crate_stack_kit"
	if not expect(int(bag().get(kit,0))==1,"holding one %s"%kit):return
	var box:=World.SHIPPING.cell_for(world.state)
	go(box)
	deny("ship",box,JSON.stringify([[[kit,1]],1]),"出貨項目重複或無法出售。","ship a kit at the shipping box")
	var stall:=MARKET.cell_for(world.state)
	go(stall)
	deny("market_stock",stall,kit+":1","%s不能擺上市集攤位；攤位只收農漁產、料理和花。"%str(DOC_NAMES.relay_crate_stack),"list a kit on the market stall")
	go(SHOP)
	deny("sell",SHOP,kit,"這件商品尚未上架","sell a kit to 小栗")
	expect(int(bag().get(kit,0))==1,"the kit is still in the backpack")

# ---------------------------------------------------------------- 7. placement

func free_grass(tile:Vector2i) -> bool:
	var k:=World.key(tile)
	for layer in ["objects","ground","roofs","crops","forest"]:
		if (world.state[layer] as Dictionary).has(k):return false
	return world.resource(tile)=="" and not world.protected(tile) and not world.blocked(tile) and not world.water(tile)

func place_leg() -> void:
	var tiles:=[]
	for tile:Vector2i in DECOR_CANDIDATES:
		if free_grass(tile):tiles.append(tile)
	if not expect(tiles.size()>=DECOR.size()+1,"enough free grass for the decorations (%d free)"%tiles.size()):return
	var record0:Dictionary=SV.record(person()).duplicate(true)
	var counters:=ticket_records()
	for i in DECOR.size():
		var kind:String=DECOR[i]
		var tile:Vector2i=tiles[i]
		go(tile)
		var inv0:=nonzero(bag())
		var coins0:=int(person().coins)
		var result:=do("build",tile,kind)
		if failed:return
		decor_tiles[kind]=tile
		expect(str(result.message)=="放好了%s，家園又多了一點你的心意"%str(DOC_NAMES[kind]),"build %s message: %s"%[kind,str(result.message)])
		var want:=inv0.duplicate()
		want[kind+"_kit"]=int(want[kind+"_kit"])-1
		if int(want[kind+"_kit"])==0:want.erase(kind+"_kit")
		expect(same(nonzero(bag()),want) and int(person().coins)==coins0,"build %s: inventory changed only by the kit -1, coins unchanged"%kind)
		expect(same(world.state.objects.get(World.key(tile),{}),{"type":kind,"owner":tok,"items":{}}),"build %s: object on %s"%[kind,str(tile)])
		expect(not world.blocked(tile) and world.can_stand(Vector2(tile)+Vector2(0.5,0.5)),"%s does not block walking"%kind)
	# No kit left for a second rack.
	var spare:Vector2i=tiles[DECOR.size()]
	go(spare)
	deny("build",spare,"veg_basket_rack","材料不足，需要%s 1"%str(DOC_NAMES.veg_basket_rack),"second rack without a kit")
	# Move the banner next to where it stands.
	var from:Vector2i=decor_tiles.carp_banner
	go(from)
	var dest:=Vector2i(-1,-1)
	for tile:Vector2i in DECOR_CANDIDATES:
		var d:=Vector2(person().x,person().y).distance_to(Vector2(tile)+Vector2(0.5,0.5))
		if tile!=from and free_grass(tile) and d>=0.8 and d<=3.0:
			dest=tile
			break
	if not expect(dest!=Vector2i(-1,-1),"a free tile to move the banner to"):return
	var inv_move:=nonzero(bag())
	var result:=do("move_object",from,"%d,%d"%[dest.x,dest.y])
	if failed:return
	expect(str(result.message)=="搬好了！家具與箱內物品一起保存，沒有額外扣料","move message: "+str(result.message))
	expect(not world.state.objects.has(World.key(from)) and same(world.state.objects.get(World.key(dest),{}),{"type":"carp_banner","owner":tok,"items":{}}),"banner moved %s -> %s"%[str(from),str(dest)])
	expect(same(nonzero(bag()),inv_move),"moving changes no inventory")
	decor_tiles.carp_banner=dest
	# Pick the lantern post up again: kit back, no refund.
	var lantern:Vector2i=decor_tiles.lantern_post
	go(lantern)
	var inv_pick:=nonzero(bag())
	do("remove",lantern,"")
	if failed:return
	decor_tiles.erase("lantern_post")
	var want_pick:=inv_pick.duplicate()
	want_pick["lantern_post_kit"]=int(want_pick.get("lantern_post_kit",0))+1
	expect(not world.state.objects.has(World.key(lantern)) and same(nonzero(bag()),want_pick),"picking up returns exactly one lantern_post_kit")
	expect(same(SV.record(person()),record0) and same(ticket_records(),counters),"placing, moving and picking up refund no tickets")
	var v:=world.souvenir_view(tok)
	var balance:={}
	for a:String in ACTS:balance[a]=int(earned_now()[a])-int(spent[a])
	expect(same(v.balance,balance),"balance unchanged by placement (%s)"%JSON.stringify(v.balance))
	var placed:={"veg_basket_rack":1,"carp_banner":1,"trio_keepsake":1,"lantern_post":0,"relay_crate_stack":0}
	var held:={"veg_basket_rack":0,"carp_banner":0,"trio_keepsake":0,"lantern_post":1,"relay_crate_stack":1}
	for entry:String in placed:
		var e:=entry_view(entry)
		expect(int(e.placed)==int(placed[entry]) and int(e.held)==int(held[entry]),"view %s: placed %d held %d (got %d/%d)"%[entry,int(placed[entry]),int(held[entry]),int(e.placed),int(e.held)])
	# Walk onto every placed decoration.
	for kind:String in decor_tiles:
		walk_onto(decor_tiles[kind])
		if failed:return
	print("SOUVENIR_JOURNEY decorations placed %s (lantern_post picked up)"%JSON.stringify(decor_tiles))

func walk_onto(tile:Vector2i) -> void:
	go(tile,1.0)
	if failed:return
	var here:=Vector2i(floori(float(person().x)),floori(float(person().y)))
	if here!=tile:
		var direction:=Vector2(tile-here)
		if not expect(absi(tile.x-here.x)+absi(tile.y-here.y)==1,"next to %s before stepping on it"%str(tile)):return
		for s in range(4):world.move_player(tok,direction,0.25/3.6)
		walking+=1
		walk_seconds+=1.0/WALK_TILES_PER_SECOND
		wait(1.0/WALK_TILES_PER_SECOND)
	expect(Vector2(person().x,person().y).distance_to(Vector2(tile)+Vector2(0.5,0.5))<=0.001,"walked onto the decoration at %s"%str(tile))

# ---------------------------------------------------------------- persistence

func persist(label:String) -> void:
	if failed:return
	expect(world.save(),label+": explicit save")
	var expected:Dictionary=person().duplicate(true)
	var view_before:=world.souvenir_view(tok)
	var objects_before:Dictionary=world.state.objects.duplicate(true)
	var rounds_before:={}
	for a:String in ACTS:rounds_before[a]=world.state.get(a,{}).duplicate(true)
	var time_before:=now()
	var reopened:=World.new()
	if not expect(reopened.load_world(save_path) and not reopened.recovered_from_backup,label+": save loads in a plain in-process World"):return
	reopened.save_path=save_path
	reopened.add_player(TOKEN_A,"Bloom A")
	world=reopened
	reloads+=1
	for field in ["region","x","y","coins","souvenir","harvest_relay","fish_meet","showcase"]:
		kept(person().get(field),expected.get(field),label+": player "+field)
	expect(same(nonzero(person().inventory),nonzero(expected.inventory)),label+": inventory preserved exactly")
	kept(world.souvenir_view(tok),view_before,label+": souvenir view")
	kept(world.state.objects,objects_before,label+": placed objects")
	for kind:String in decor_tiles:
		expect(same(world.state.objects.get(World.key(decor_tiles[kind]),{}),{"type":kind,"owner":tok,"items":{}}),label+": %s still at %s"%[kind,str(decor_tiles[kind])])
	for a:String in ACTS:
		kept(world.state.get(a,{}),rounds_before[a],label+": %s round state"%a)
	expect(absf(now()-time_before)<0.001,label+": world time preserved (%.3f vs %.3f)"%[now(),time_before])
	print("SOUVENIR_JOURNEY reload (%s) time=%.1f balance=%s redeemed_total=%d"%[label,now(),JSON.stringify(world.souvenir_view(tok).balance),int(world.souvenir_view(tok).redeemed_total)])

# ---------------------------------------------------------------- helpers

## Preserved across a save/reload: canonical equality, numbers within 1e-6.
func kept(after:Variant,before:Variant,label:String) -> void:
	var d:=first_diff(canon(after),canon(before),"value")
	expect(d.is_empty(),label+" preserved (first difference: %s)"%d)

func zero() -> Dictionary:
	return {"harvest_relay":0,"fish_meet":0,"showcase":0}

func activity_record(activity:String) -> Dictionary:
	match activity:
		"harvest_relay":return H.record(person()).duplicate(true)
		"fish_meet":return M.record(person()).duplicate(true)
	return S.record(person()).duplicate(true)

func ticket_records() -> Dictionary:
	var out:={}
	for a:String in ACTS:out[a]=activity_record(a)
	return out

func earned_now() -> Dictionary:
	var out:={}
	for a:String in ACTS:out[a]=int(activity_record(a).tickets)
	return out

func round_counts() -> Dictionary:
	var out:={}
	for a:String in ACTS:out[a]=(rounds[a] as Array).size()
	return out

func entry_view(entry:String) -> Dictionary:
	for e:Dictionary in world.souvenir_view(tok).entries:
		if str(e.id)==entry:return e
	return {}

## Documented shortfall text for an entry at a balance ("" when affordable).
func short_text(entry:String,balance:Dictionary) -> String:
	var parts:=PackedStringArray()
	var cost:Dictionary=DOC_COSTS[entry]
	for a:String in ACTS:
		if cost.has(a) and int(balance[a])<int(cost[a]):parts.append("%s的紀念票 %d 張"%[ACT_NAMES[a],int(cost[a])-int(balance[a])])
	return "、".join(parts)

func spent_text(entry:String) -> String:
	var parts:=PackedStringArray()
	var cost:Dictionary=DOC_COSTS[entry]
	for a:String in ACTS:
		if cost.has(a):parts.append("%s的紀念票 %d 張"%[ACT_NAMES[a],int(cost[a])])
	return "、".join(parts)

func distance_to(cell:Vector2i) -> float:
	return Vector2(person().x,person().y).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## Walk to a passable cell within `reach` of target. Returns tiles walked.
func walk_near(target:Vector2i,reach:float=ADJACENT) -> int:
	if failed:return 0
	if distance_to(target)<=reach:return 0
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

## A walking leg: the free walk plus tiles/3.6 world seconds once the clock is on.
func go(target:Vector2i,reach:float=ADJACENT) -> int:
	var tiles:=walk_near(target,reach)
	if failed or tiles<=0 or not clock_on:return tiles
	var seconds:=float(tiles)/WALK_TILES_PER_SECOND
	walk_seconds+=seconds
	wait(seconds)
	return tiles

func spend(seconds:float) -> void:
	if clock_on and not failed:
		action_seconds+=seconds
		wait(seconds)

## A successful action through World.act (no walking).
func do(action:String,target:Vector2i,extra:String) -> Dictionary:
	if failed:return {"ok":false,"message":"skipped"}
	actions+=1
	var result:=world.act(tok,"souvenir-journey-%d"%actions,action,target,extra)
	expect(result.ok,"%s %s at %s: %s"%[action,extra,str(target),str(result.message)])
	spend(ACTION_SECONDS)
	return result

## Exact message and the whole World.state unchanged (== and canonical bytes).
func deny(action:String,target:Vector2i,extra:String,message:String,label:String) -> void:
	if failed:return
	var state_before:=world.state.duplicate(true)
	var bytes_before:=var_to_bytes(canon(world.state))
	actions+=1
	refusals+=1
	var result:=world.act(tok,"souvenir-journey-%d"%actions,action,target,extra)
	expect(not result.ok and str(result.message)==message,"%s: '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	expect(world.state==state_before and var_to_bytes(canon(world.state))==bytes_before,label+": whole world state unchanged")
	spend(ACTION_SECONDS)

## The player record minus fields a cast legitimately touches: request receipts,
## the cast line and the meet record.
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
	if value is Vector2i:return [value.x,value.y]
	if value is float and is_finite(value) and floorf(value)==value:return int(value)
	return value

## Path and values of the first difference between two canonical values ("" if equal).
## Numbers equal within 1e-6 (JSON saves keep ~15 significant digits).
static func first_diff(a:Variant,b:Variant,path:String) -> String:
	if (a is int or a is float) and (b is int or b is float):
		return "" if absf(float(a)-float(b))<=0.000001 else "%s: %s vs %s"%[path,str(a),str(b)]
	if typeof(a)!=typeof(b):return "%s: %s(%s) vs %s(%s)"%[path,type_string(typeof(a)),str(a).left(80),type_string(typeof(b)),str(b).left(80)]
	if a is Dictionary:
		for k in a:
			if not b.has(k):return "%s.%s missing after reload"%[path,str(k)]
			var d:=first_diff(a[k],b[k],"%s.%s"%[path,str(k)])
			if not d.is_empty():return d
		for k in b:
			if not a.has(k):return "%s.%s missing in reloaded"%[path,str(k)]
		return ""
	if a is Array:
		if a.size()!=b.size():return "%s: size %d vs %d"%[path,a.size(),b.size()]
		for i in a.size():
			var d:=first_diff(a[i],b[i],"%s[%d]"%[path,i])
			if not d.is_empty():return d
		return ""
	return "" if a==b else "%s: %s vs %s"%[path,str(a),str(b)]

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
