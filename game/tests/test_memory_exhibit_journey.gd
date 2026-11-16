extends "res://tests/test_festival_earned_journey.gd"
## Chapter 40「風鈴節廣場・地方記憶展」natural journey: a FRESH temp world, ONE
## player for the whole journey (plus the late joiners the parents add, and one
## newcomer at the end), ONE process (reloads are in-process World.new().load_world
## on the same save; after each reload the journey continues in the reloaded World).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
##
## Prerequisite reuse (disclosed): this file EXTENDS the unmodified
## test_festival_earned_journey.gd (-> salt pan -> flower journeys). The parent
## run earns chapter one, the tea route, the Tianwei garden, the Beimen salt pans,
## the Lanyang canal REPAIR, the deep mine B1-B5, the dock, the public kitchen, the
## shared meal, two lamps and the real 風鈴節 opening (all six projects, no project
## override), then two in-process restarts with a late festival member.
## The parent does NOT walk the personal first 分水 (history memory) and does NOT set
## the bridge plaque, so the exhibit is checked BEFORE the revisit (order A).
## The first 分水 + plaque + revisit + claim steps are RE-DERIVED here from
## test_history_journey.gd / test_lanyang_revisit_journey.gd (that chain extends a
## different base, so those functions cannot be inherited by this file); the demand
## is taken from the season the world clock is actually in.
##
## Hooks: chapter_one() (fresh-world LOCKED refusal, no walking, before the parent's
## chapter one) and act() (pre-opening refusal at the stand: right before the
## parent's own successful festival_story_open action).
##
## Everything goes through World.act after World.move_player along BFS routes, and
## World.step (inherited wait()) for waits. NO direct writes by this file to
## inventory, coins, flags, festival / revisit / history / exhibit fields, objects,
## crops, positions or time. Read-only helpers for assertions: MemoryExhibit.*,
## LanyangRevisit.*, HistoryMemory.distribution, World.blocked/protected/can_stand.
## WALKING IS FREE: World.move_player never advances state.time.
## The newcomer joins through World.add_player, the same call the Session join
## path and the parents' late joiners use.
## Prints MEMORY_EXHIBIT_JOURNEY lines before the parents' summary lines.

const ME=preload("res://scripts/memory_exhibit.gd")
const LR=preload("res://scripts/lanyang_revisit.gd")
const HM=preload("res://scripts/history_memory.gd")
const NEWCOMER:="exhibit-newcomer"
const NEWCOMER_NAME:="Exhibit Late"
const DOC_GATES:={"spring":[3,2],"summer":[2,1],"autumn":[1,3],"winter":[1,2]}
const PLAQUE_SPOTS:=[Vector2i(35,34),Vector2i(36,34),Vector2i(34,34),Vector2i(34,36),Vector2i(36,36),Vector2i(35,37),Vector2i(34,37),Vector2i(36,37)]

var ex_started:=false
var ex_fresh_done:=false
var ex_pre_done:=false
var ex_actions_start:=0
var ex_walk_start:=0
var ex_time_start:=0.0
var ex_checks_start:=0
var ex_ms:=0
var ex_rejections:=[]
var ex_changed:=0
var ex_reloads:=0
var ex_waited:=0.0
var ex_info:={}

# ---------------------------------------------------------------- hooks

func chapter_one() -> void:
	if not ex_fresh_done:
		ex_fresh_done=true
		fresh_locked()
	super.chapter_one()

func act(action:String,target:Vector2i,extra:String="") -> Dictionary:
	if action=="festival_story_open" and fest_started and not ex_pre_done and not failed:
		ex_pre_done=true
		pre_opening()
	return super.act(action,target,extra)

func fresh_locked() -> void:
	var s:=world.state
	var cell:=ME.cell_for(s)
	ex_check(not ME.unlocked(s) and ME.stand_cell(s)==ME.NO_CELL and ME.public(s).is_empty(),"fresh world: exhibit locked, no stand, no public block")
	ex_check(cell==ME.CANDIDATES[0] and not world.blocked(cell) and not ME.reserved(s,cell),"fresh world: first stand candidate %s free and not blocking"%str(cell))
	ex_check(ME.view_block(s,"lanyang",tok)==ME.LOCKED,"fresh world: view_block says LOCKED")
	ex_deny(ME.VIEW_ACTION,cell,"lanyang",ME.LOCKED,"fresh world exhibit_view (no walking)",false)

func pre_opening() -> void:
	var s:=world.state
	var plan:=world.festival_story_view()
	ex_check(not plan.opened and s.get("festival_story_open")!=true,"pre-opening: festival not opened yet (plan %s)"%JSON.stringify(plan))
	var cell:=ME.cell_for(s)
	ex_info.pre_open_cell=[cell.x,cell.y]
	ex_check(cell!=ME.NO_CELL and not ME.unlocked(s) and ME.stand_cell(s)==ME.NO_CELL,"pre-opening: stand locked, first free candidate %s"%str(cell))
	ex_check(not world.blocked(cell) and world.can_stand(Vector2(cell)+Vector2(0.5,0.5)) and not ME.reserved(s,cell),"pre-opening: stand cell %s does not block walking"%str(cell))
	walk_to(cell)
	ex_check(ex_dist(cell)<=ME.REACH,"pre-opening: standing %.2f tiles from the stand cell"%ex_dist(cell))
	ex_deny(ME.VIEW_ACTION,cell,"lanyang",ME.LOCKED,"pre-opening exhibit_view lanyang",false)
	ex_deny(ME.VIEW_ACTION,cell,"jinguashi",ME.LOCKED,"pre-opening exhibit_view jinguashi",false)

# ---------------------------------------------------------------- journey

func run() -> void:
	super.run()
	if failed:return
	ex_check(ex_fresh_done and ex_pre_done,"fresh-world and pre-opening hooks ran")
	ex_started=true
	ex_ms=Time.get_ticks_msec()
	ex_actions_start=actions
	ex_walk_start=walking
	ex_time_start=now()
	ex_checks_start=checks
	tok=TOKEN_A
	print("MEMORY_EXHIBIT_JOURNEY festival earned (checks %d, actions %d, world_seconds %.1f, day %d %s)"%[checks,actions,now(),LR.today(world.state),LR.season(world.state)])
	order_a()
	if not failed:first_share_and_revisit()
	if not failed:view_leg()
	if not failed:plaque_and_reload()
	if not failed:newcomer_leg()

## Right after the opening, BEFORE any first 分水 / plaque / revisit.
func order_a() -> void:
	var s:=world.state
	ex_check(s.get("festival_story_open")==true and world.player_region(tok)=="home","festival open, A at home")
	ex_check(bool(s.lanyang_life.repaired) and not bool(s.history_memory.plaque) and not (s.history_memory.players as Dictionary).has(tok),"canal repaired by the festival steps; no first 分水 record, no bridge plaque")
	ex_check(not LR.unlocked(s) and not LR.completed(s) and not s.has(LR.STATE_KEY),"revisit still locked, no revisit record")
	var stand:=ME.stand_cell(s)
	ex_info.stand=[stand.x,stand.y]
	ex_check(stand!=ME.NO_CELL and [stand.x,stand.y]==ex_info.pre_open_cell,"stand cell %s is the pre-opening candidate"%str(stand))
	var pub:=ME.public(s)
	ex_check(pub.get("cell")==stand and pub.get("paused")==false and (pub.get("on_display") as Array).is_empty() and (pub.get("blocked_cells") as Array).is_empty(),"public block %s"%str(pub))
	ex_check(world.blocked(stand) and world.protected(stand) and not world.can_stand(Vector2(stand)+Vector2(0.5,0.5)),"after the opening the stand cell blocks and is protected")
	var rows:=ME.exhibits(s,tok)
	ex_check(rows.size()==4,"four exhibit rows")
	for row in rows:
		ex_check(row.on_display==false and row.unread==false and row.lines==[ME.EMPTY_LINE] and str(row.source)=="","%s empty before the revisit"%str(row.id))
	var me:=ME.personal(s,tok)
	ex_check(me.seen==[] and int(me.unread)==0 and me.first_share_done==false and me.plaque_claimed==false and str(me.hint)==ME.HINT_REVISIT_LOCKED,"personal before the revisit %s"%JSON.stringify(me))
	ex_check(ME.recap(s).is_empty() and ME.recap_pages("lanyang",s).is_empty(),"no recap before the revisit")
	ex_check(ME.view_block(s,"lanyang",tok)==ME.NOT_ON_DISPLAY,"view_block NOT_ON_DISPLAY")
	# Too far: stand near the stove south of the plaza.
	walk_to(stove_cell)
	ex_check(ex_dist(stand)>ME.REACH,"near the stove, %.2f tiles from the stand"%ex_dist(stand))
	ex_deny(ME.VIEW_ACTION,stand,"lanyang",ME.TOO_FAR,"view from the stove (too far)",false)
	walk_to(stand)
	ex_check(ex_dist(stand)<=ME.REACH,"at the stand (%.2f tiles)"%ex_dist(stand))
	for cell:Vector2i in ME.CANDIDATES:
		if cell!=stand:
			ex_deny(ME.VIEW_ACTION,cell,"lanyang",ME.WRONG_POINT,"view at the unused candidate %s"%str(cell),false)
			break
	ex_deny(ME.VIEW_ACTION,stand+Vector2i(1,0),"lanyang",ME.WRONG_POINT,"view at the cell beside the stand",false)
	for id:String in ME.EXHIBIT_ORDER:
		ex_deny(ME.VIEW_ACTION,stand,id,ME.NOT_ON_DISPLAY,"view %s before the revisit"%id,false)
	ex_deny(ME.VIEW_ACTION,stand,"lantern",ME.UNKNOWN_EXHIBIT,"view an unknown exhibit id",false)
	ex_deny(ME.VIEW_ACTION,stand,"",ME.UNKNOWN_EXHIBIT,"view with an empty exhibit id",false)
	ex_check(not (person() as Dictionary).has(ME.RECORD_KEY),"no exhibit record written by any refusal")

func first_share_and_revisit() -> void:
	act("travel",World.REGIONS.exit_cell("home"),"lanyang")
	ex_check(world.player_region(tok)=="lanyang","A in Lanyang")
	var stand:=Vector2i(ex_info.stand[0],ex_info.stand[1])
	ex_deny(ME.VIEW_ACTION,stand,"lanyang",ME.WRONG_REGION,"exhibit_view from Lanyang",false)
	ex_deny(LR.GATE_ACTION,LR.GATE_CELL,"a:1",LR.LOCKED,"revisit gate before the first 分水 and plaque")
	# First 分水 (re-derived from test_history_journey.after_chapter).
	for point:Vector2i in HM.OBSERVATIONS:act("memory_observe",point)
	ex_check((world.state.history_memory.players[tok].seen as Array).size()==3,"three observations")
	var pairings:=[[2,2],[1,3],[2,1]]
	for index in pairings.size():
		var gates:Array=pairings[index]
		ex_check(HM.distribution(gates)==HM.DEMANDS[index],"practice round %d gates %s"%[index+1,str(gates)])
		act("memory_gate",HM.SERVICE,"a:%d"%gates[0])
		act("memory_gate",HM.SERVICE,"b:%d"%gates[1])
		act("memory_flow",HM.SERVICE)
	ex_check(world.state.history_memory.players[tok].completed==true,"own first 分水 completed")
	ex_check(not LR.unlocked(world.state) and ME.personal_hint(world.state,tok)==ME.HINT_REVISIT_LOCKED,"memory done, plaque not yet: revisit locked")
	act("memory_plaque",HM.SERVICE)
	if failed:return
	var s:=world.state
	ex_check(LR.unlocked(s) and LR.player_ready(s,tok) and not LR.completed(s),"plaque set: revisit unlocked, A ready")
	ex_check(ME.personal_hint(s,tok)==ME.HINT_NOT_DONE and ME.on_display_ids(s).is_empty(),"exhibit still empty, hint NOT_DONE")
	# Rain: wait for a dry Lanyang day through real World.step.
	var rain_days:=0
	var wait_from:=now()
	while LR.raining(world.state) and not failed and rain_days<4:
		ex_deny(LR.GATE_ACTION,LR.GATE_CELL,"a:1",LR.RAINY,"revisit gate on rainy day %d"%LR.today(world.state))
		rain_days+=1
		var dt:=next_midnight()+1.0-now()
		wait(dt)
		ex_waited+=dt
	ex_check(not LR.raining(world.state),"a dry Lanyang day")
	ex_info.rain_days_waited=rain_days
	ex_info.rain_wait_seconds=now()-wait_from
	var season:=LR.season(world.state)
	var demand:=LR.demand(world.state)
	var need:Array=DOC_GATES[season]
	ex_check(HM.distribution(need)==demand,"%s gates %s give demand %s"%[season,str(need),str(demand)])
	ex_info.revisit={"day":LR.today(world.state),"season":season,"demand":demand,"gates":need,"weather":str(WEATHER.at(now(),"lanyang").id),"world_seconds":now()}
	print("MEMORY_EXHIBIT_JOURNEY revisit day=%d season=%s weather=%s demand=%s gates=a%d,b%d rain_days_waited=%d rain_wait_seconds=%.1f"%[LR.today(world.state),season,ex_info.revisit.weather,str(demand),int(need[0]),int(need[1]),rain_days,float(ex_info.rain_wait_seconds)])
	var up:Vector2i=LR.FIELD_CELLS.upstream
	ex_deny(LR.CHECK_ACTION,up,"",LR.NO_GATES_TODAY,"check before any gate setting")
	var wrong_a:=int(need[0])-1
	act(LR.GATE_ACTION,LR.GATE_CELL,LR.gate_extra("a",wrong_a))
	var split:=HM.distribution([wrong_a,0])
	ex_deny(LR.CHECK_ACTION,up,"",LR.WRONG_SHARE%[LR.FIELD_NAMES.upstream,int(split[0]),int(demand[0])],"check upstream with a:%d"%wrong_a)
	act(LR.GATE_ACTION,LR.GATE_CELL,LR.gate_extra("a",int(need[0])))
	act(LR.GATE_ACTION,LR.GATE_CELL,LR.gate_extra("b",int(need[1])))
	ex_check(LR.shares(world.state)==demand,"shares %s equal the demand"%str(LR.shares(world.state)))
	var order:=["upstream","middle","tail"]
	for i in order.size():
		var id:String=order[i]
		var r:=act(LR.CHECK_ACTION,LR.FIELD_CELLS[id],"")
		if failed:return
		if i<2:
			ex_check(not ME.available(world.state,"lanyang") and ME.on_display_ids(world.state).is_empty(),"after check %d/3 the exhibit is still empty"%(i+1))
		else:
			ex_check(str(r.message)==LR.COMPLETE_OK,"third check completes the revisit")
	s=world.state
	var rec:=LR.record(s)
	ex_check(rec.completed==true and rec.checked==order and LR.gates(s)==need and int(rec.day)==int(ex_info.revisit.day),"revisit record %s"%JSON.stringify(rec))
	ex_check(ME.on_display_ids(s)==["lanyang"] and ME.unread_count(s,tok)==1,"exhibit lit by the completion itself (no extra action)")
	ex_check(ME.personal_hint(s,tok)==ME.HINT_UNCLAIMED,"hint: plaque waiting at 星禾")
	var bag0:=(bag() as Dictionary).duplicate(true)
	var r2:=act(LR.CLAIM_ACTION,LR.SERVICE,"")
	ex_check(str(r2.get("message",""))==LR.CLAIM_OK and int(bag().get(LR.PLAQUE_ITEM,0))==int(bag0.get(LR.PLAQUE_ITEM,0))+1,"claimed one 分水木牌 kit")
	ex_check(ME.personal_hint(world.state,tok)==ME.HINT_CLAIMED,"hint: plaque claimed")
	ex_deny(LR.CLAIM_ACTION,LR.SERVICE,"",LR.CLAIMED,"second claim")
	act("travel",World.REGIONS.exit_cell("lanyang"),"home")
	ex_check(world.player_region(tok)=="home","back home")

func view_leg() -> void:
	var stand:=Vector2i(ex_info.stand[0],ex_info.stand[1])
	walk_to(stand)
	var s:=world.state
	ex_check(ME.stand_cell(s)==stand and ME.public(s).on_display==["lanyang"],"public block lists lanyang at %s"%str(stand))
	var rows:=ME.exhibits(s,tok)
	var row:Dictionary=rows[0]
	ex_check(row.id=="lanyang" and row.on_display==true and row.seen==false and row.unread==true and str(row.source)==LR.PLAQUE_SOURCE and str(row.project)==LR.PLAQUE_PROJECT and str(row.disclaimer)==LR.DISCLAIMER,"lanyang row on display and unread")
	for i in range(1,4):ex_check(rows[i].on_display==false and rows[i].lines==[ME.EMPTY_LINE],"%s still empty"%str(rows[i].id))
	var me:=ME.personal(s,tok)
	ex_check(me.seen==[] and int(me.unread)==1 and me.first_share_done==true and me.plaque_claimed==true and str(me.hint)==ME.HINT_CLAIMED,"personal before viewing %s"%JSON.stringify(me))
	var rv:Dictionary=ex_info.revisit
	var recap:=ME.recap(s)
	var day:=int(rv.day)
	ex_check(int(recap.day)==day and str(recap.season)==str(rv.season) and recap.demand==rv.demand and recap.gates==rv.gates and recap.order==["upstream","middle","tail"],"recap matches what was done %s"%JSON.stringify(recap))
	ex_check(str(recap.weather)==str(rv.weather) and str(recap.weather)!="rainy" and str(recap.weather)==WEATHER.outdoor_id(float(day-1)),"recap weather %s is the revisit day's"%str(recap.weather))
	ex_check(str(recap.reason)==LR.reason_for(str(rv.season)),"recap reason is the season's")
	var gates:Array=rv.gates
	var need:Array=rv.demand
	ex_check(row.lines.size()==7 and str(row.lines[3])=="完成那天：第 %d 日・%s・%s"%[day,str(recap.season_label),str(recap.weather_label)] and str(row.lines[4])=="三塊田需要：上游 %d／中段 %d／田尾 %d 份"%[int(need[0]),int(need[1]),int(need[2])] and str(row.lines[5])=="岔口的閘：上游閘 %d 檔、中段閘 %d 檔"%[int(gates[0]),int(gates[1])],"exhibit lines %s"%JSON.stringify(row.lines))
	ex_check(ME.recap_pages("lanyang",s).size()==4 and ME.view_block(s,"lanyang",tok)=="","4 recap pages, view allowed")
	for id:String in ["jinguashi","tea_pottery","beimen"]:ex_deny(ME.VIEW_ACTION,stand,id,ME.NOT_ON_DISPLAY,"view %s after the revisit"%id,false)
	var rid:=ex_view_ok(stand,"lanyang","first view by A")
	if failed:return
	ex_check(same_canon(person().get(ME.RECORD_KEY),{"seen":["lanyang"]}),"A's record is {seen:[lanyang]}")
	# Resend the same request id: same reply, nothing applied twice.
	var before:=canon_bytes(world.state)
	var again:=world.act(tok,rid,ME.VIEW_ACTION,stand,"lanyang")
	ex_check(again.ok==true and str(again.message)==ME.VIEW_OK%"分水木牌" and canon_bytes(world.state)==before,"resend of %s returns the stored receipt, state unchanged"%rid)
	ex_deny(ME.VIEW_ACTION,stand,"lanyang",ME.ALREADY_SEEN,"view lanyang again (new request)",false)
	me=ME.personal(world.state,tok)
	ex_check(me.seen==["lanyang"] and int(me.unread)==0 and ME.view_block(world.state,"lanyang",tok)==ME.ALREADY_SEEN,"personal after viewing %s"%JSON.stringify(me))
	var late:=ME.personal(world.state,LATE)
	ex_check(late.seen==[] and int(late.unread)==1 and str(late.hint)==ME.HINT_NOT_READY,"festival late member still unread, NOT_READY hint %s"%JSON.stringify(late))
	# The own block also carries the 礦燈 keys (金瓜石回訪); this journey never sorts with Bobo.
	ex_check(ME.own(world.state,tok)=={"seen":["lanyang"],"first_share_done":true,"plaque_claimed":true,"sorting_done":false,"lantern_claimed":false,"comparison_done":true,"teaware_claimed":false,"raking_done":true,"basket_claimed":false},"own block for A")

func plaque_and_reload() -> void:
	var stand:=Vector2i(ex_info.stand[0],ex_info.stand[1])
	var spot:=Vector2i(-1,-1)
	for tile:Vector2i in PLAQUE_SPOTS:
		if ex_free(tile):
			spot=tile
			break
	if spot==Vector2i(-1,-1):spot=open_cell()
	if not ex_check(spot!=Vector2i(-1,-1) and spot not in ME.CANDIDATES,"free home cell for the plaque %s"%str(spot)):return
	var before:=(bag() as Dictionary).duplicate(true)
	act("build",spot,LR.PLAQUE_KIND)
	if failed:return
	ex_check(int(bag().get(LR.PLAQUE_ITEM,0))==int(before.get(LR.PLAQUE_ITEM,0))-1,"build debits the plaque kit")
	var o:Dictionary=world.state.objects.get(World.key(spot),{})
	ex_check(str(o.get("type",""))==LR.PLAQUE_KIND and str(o.get("owner",""))==tok and not world.blocked(spot),"分水木牌 placed at %s, not blocking"%str(spot))
	ex_check(ME.stand_cell(world.state)==stand and ME.on_display_ids(world.state)==["lanyang"],"memento and exhibit coexist; stand unchanged")
	ex_info.plaque=[spot.x,spot.y]
	var snap:=ex_exhibit_snapshot()
	ex_reload("after the view and the plaque")
	if failed:return
	ex_check(same_canon(ex_exhibit_snapshot(),snap),"stand, on-display, seen and personal status identical after reload")
	ex_check(str(world.state.objects.get(World.key(spot),{}).get("type",""))==LR.PLAQUE_KIND,"plaque persists")
	walk_to(stand)
	ex_deny(ME.VIEW_ACTION,stand,"lanyang",ME.ALREADY_SEEN,"view after reload",false)

func newcomer_leg() -> void:
	var stand:=Vector2i(ex_info.stand[0],ex_info.stand[1])
	ex_check(not world.state.players.has(NEWCOMER),"newcomer not in the save yet")
	world.add_player(NEWCOMER,NEWCOMER_NAME)
	var a_before:=canon_bytes(world.state.players[TOKEN_A])
	tok=NEWCOMER
	ex_check(world.player_region(tok)=="home" and not person().has(ME.RECORD_KEY) and not (world.state.history_memory.players as Dictionary).has(tok),"newcomer joined at home with no exhibit or 分水 record")
	walk_to(stand)
	var s:=world.state
	var me:=ME.personal(s,tok)
	ex_check(me.seen==[] and int(me.unread)==1 and me.first_share_done==false and me.plaque_claimed==false and str(me.hint)==ME.HINT_NOT_READY,"newcomer personal %s"%JSON.stringify(me))
	var row:=ME.exhibit(s,"lanyang",tok)
	ex_check(row.on_display==true and row.unread==true and row.lines.size()==7,"newcomer sees lanyang on display, unread")
	ex_check(ME.recap_pages("lanyang",s).size()==4,"newcomer can page the 4-page recap")
	ex_view_ok(stand,"lanyang","newcomer view")
	if failed:return
	ex_deny(ME.VIEW_ACTION,stand,"lanyang",ME.ALREADY_SEEN,"newcomer views again",false)
	ex_check(canon_bytes(world.state.players[TOKEN_A])==a_before,"A's whole player record untouched by the newcomer")
	me=ME.personal(world.state,tok)
	ex_check(me.seen==["lanyang"] and int(me.unread)==0 and str(me.hint)==ME.HINT_NOT_READY,"newcomer after viewing %s"%JSON.stringify(me))
	var snap:=ex_exhibit_snapshot()
	ex_reload("after the newcomer")
	if failed:return
	ex_check(same_canon(ex_exhibit_snapshot(),snap),"both players' exhibit status identical after reload")
	for token in [TOKEN_A,NEWCOMER]:
		tok=token
		walk_to(stand)
		ex_deny(ME.VIEW_ACTION,stand,"lanyang",ME.ALREADY_SEEN,"%s views after the final reload"%token,false)
	tok=TOKEN_A

# ---------------------------------------------------------------- report

func finish() -> void:
	if ex_started:
		print("MEMORY_EXHIBIT_JOURNEY info=%s"%JSON.stringify(ex_info))
		for i in ex_rejections.size():print("MEMORY_EXHIBIT_JOURNEY rejection %d %s"%[i+1,ex_rejections[i]])
		var t:=float(world.state.get("time",0.0))
		print("MEMORY_EXHIBIT_JOURNEY stats actions_total=%d walk_tiles_total=%d world_seconds_total=%.1f exhibit_segment_actions=%d exhibit_segment_walk_tiles=%d exhibit_segment_world_seconds=%.1f rain_wait_seconds=%.1f rejections=%d all_rejections_state_unchanged=%s reloads=%d segment_checks=%d segment_ms=%d passed=%s"%[actions,walking,t,actions-ex_actions_start,walking-ex_walk_start,t-ex_time_start,ex_waited,ex_rejections.size(),str(ex_changed==0),ex_reloads,checks-ex_checks_start,Time.get_ticks_msec()-ex_ms,str(not failed)])
	else:
		print("MEMORY_EXHIBIT_JOURNEY did not reach the exhibit segment (rejections so far %d)"%ex_rejections.size())
	super.finish()

# ---------------------------------------------------------------- helpers

func ex_check(condition:bool,message:String) -> bool:
	return expect(condition,"MEMORY_EXHIBIT_JOURNEY: "+message)

func ex_dist(cell:Vector2i) -> float:
	return Vector2(person().x,person().y).distance_to(Vector2(cell)+Vector2(0.5,0.5))

func ex_free(tile:Vector2i) -> bool:
	var k:=World.key(tile)
	for layer in ["objects","ground","roofs","crops","forest"]:
		if (world.state[layer] as Dictionary).has(k):return false
	return tile not in ME.CANDIDATES and world.resource(tile)=="" and not world.protected(tile) and not world.blocked(tile) and not world.water(tile) and not route(tile).is_empty()

## Refused with the exact message; whole World.state unchanged (== and sorted bytes).
func ex_deny(action:String,target:Vector2i,extra:String,message:String,label:String,walk:=true) -> void:
	if failed:return
	if walk:walk_to(target)
	if failed:return
	actions+=1
	var state_before:=world.state.duplicate(true)
	var bytes_before:=canon_bytes(world.state)
	var result:=world.act(tok,"exhibit-journey-%d"%actions,action,target,extra)
	ex_check(not result.ok and str(result.message)==message,"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var unchanged:=world.state==state_before and canon_bytes(world.state)==bytes_before
	ex_check(unchanged,label+": whole world state unchanged")
	if not unchanged:ex_changed+=1
	ex_rejections.append("%s | %s %s | %s | state_unchanged=%s"%[label,action,extra,message,str(unchanged)])

## A successful exhibit_view; the whole state may differ only in the viewer's
## memory_exhibit, the viewer's receipts and the commit counter. Returns the request id.
func ex_view_ok(stand:Vector2i,id:String,label:String) -> String:
	if failed:return ""
	ex_check(ex_dist(stand)<=ME.REACH,label+": within reach")
	actions+=1
	var rid:="exhibit-journey-%d"%actions
	var before:Variant=ex_canon(world.state)
	var result:=world.act(tok,rid,ME.VIEW_ACTION,stand,id)
	print("%d %s %s %s | %s"%[actions,ME.VIEW_ACTION,stand,id,str(result.message)])
	ex_check(result.ok==true and str(result.message)==ME.VIEW_OK%str(ME.EXHIBITS[id].name),"%s: VIEW_OK (%s)"%[label,str(result.message)])
	var diffs:=[]
	ex_all_diffs(before,ex_canon(world.state),"state",diffs)
	var allowed:=["state.players.%s.%s"%[tok,ME.RECORD_KEY],"state.players.%s.receipts"%tok,"state.committed"]
	var other:=[]
	var saw_record:=false
	for row in diffs:
		var ok:=false
		for prefix:String in allowed:
			if str(row.path)==prefix or str(row.path).begins_with(prefix+"."):ok=true
		if not ok:other.append(row)
		if str(row.path).begins_with(allowed[0]):saw_record=true
	ex_check(other.is_empty() and saw_record,"%s: whole-state diff only the viewer's memory_exhibit/receipt/commit (other %s)"%[label,JSON.stringify(other.slice(0,5))])
	ex_check(same_canon(person().receipts.get(rid),result),label+": receipt stored")
	return rid

## Exhibit-related view of the state for every player in the save.
func ex_exhibit_snapshot() -> Dictionary:
	var s:=world.state
	var out:={"stand":ME.stand_cell(s),"public":ME.public(s),"on_display":ME.on_display_ids(s),"recap":ME.recap(s),"players":{}}
	for token in s.players:
		out.players[str(token)]={"personal":ME.personal(s,str(token)),"own":ME.own(s,str(token)),"exhibits":ME.exhibits(s,str(token))}
	return out

## Save, reload into a fresh World, compare the WHOLE canonical state (numbers 1e-6;
## only accepted difference: zero counters the load schema adds), rejoin the active
## players, continue in the reloaded World.
func ex_reload(label:String) -> void:
	if failed:return
	ex_check(world.save(),label+": save")
	var reopened:=World.new()
	if not ex_check(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,label+": fresh World loads the primary save"):return
	var diffs:=[]
	ex_all_diffs(ex_canon(world.state),ex_canon(reopened.state),"state",diffs)
	var defaults:=[]
	var real:=[]
	for row in diffs:
		if row.kind=="added_on_load" and (row.value is int or row.value is float) and float(row.value)==0.0:defaults.append(row.path)
		else:real.append(row)
	ex_check(real.is_empty(),label+": whole canonical state identical after reload %s"%JSON.stringify(real.slice(0,5)))
	reopened.save_path=world.save_path
	for token in world.active_tokens:
		reopened.add_player(token,str(world.state.players[token].name))
		var pd:=[]
		ex_all_diffs(ex_canon(xc_players(world,token)),ex_canon(xc_players(reopened,token)),"player",pd)
		ex_check(pd.is_empty(),label+": rejoin %s changes nothing but load defaults %s"%[token,JSON.stringify(pd.slice(0,5))])
	world=reopened
	ex_reloads+=1
	print("MEMORY_EXHIBIT_JOURNEY reload (%s) world_seconds=%.1f identical=%s load_defaults=%s"%[label,now(),str(real.is_empty()),str(defaults)])

func xc_players(w:World,token:String) -> Dictionary:
	var p:Dictionary=(w.state.players[token] as Dictionary).duplicate(true)
	for k in ["harvests","builds","fish_caught"]:
		if float(p.get(k,0))==0.0:p.erase(k)
	return p

func same_canon(a:Variant,b:Variant) -> bool:
	return var_to_bytes(ex_canon(a))==var_to_bytes(ex_canon(b))

## Every difference (up to 40): {"path","kind":"changed"|"added_on_load"|"lost_on_load","value"}.
static func ex_all_diffs(a:Variant,b:Variant,path:String,out:Array) -> void:
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
			else:ex_all_diffs(a[k],b[k],"%s.%s"%[path,str(k)],out)
		for k in b:
			if not a.has(k):out.append({"path":"%s.%s"%[path,str(k)],"kind":"added_on_load","value":b[k]})
		return
	if a is Array:
		if a.size()!=b.size():
			out.append({"path":path,"kind":"changed","value":"size %d vs %d"%[a.size(),b.size()]})
			return
		for i in a.size():ex_all_diffs(a[i],b[i],"%s[%d]"%[path,i],out)
		return
	if a!=b:out.append({"path":path,"kind":"changed","value":"%s vs %s"%[str(a).left(60),str(b).left(60)]})

static func ex_canon(value:Variant) -> Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			var source:Variant=value[k] if value.has(k) else value[StringName(k)]
			out[k]=ex_canon(source)
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(ex_canon(item))
		return list
	if value is Vector2i:return [value.x,value.y]
	if value is float and is_finite(value) and floorf(value)==value:return int(value)
	return value
