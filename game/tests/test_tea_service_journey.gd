extends "res://tests/test_tea_revisit_journey.gd"
## Chapter 40「茶陶上桌」(tea_service.gd) natural journey: a FRESH temp world, ONE
## process, played only through World.act (after World.move_player along BFS routes)
## and World.step waits. Reloads are in-process (the parents' ex_reload: save, load
## into a fresh World through SaveSchema, whole canonical state compared, continue in
## the reloaded World).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
##
## Prerequisite reuse (disclosed): this file EXTENDS the unmodified
## test_tea_revisit_journey.gd (-> jinguashi revisit -> memory exhibit -> festival
## earned -> salt pan -> flower journeys). That chain earns chapter one and the
## 渡口野餐 (the shared table), the tea comparison, the island-wide 茶罐大單 (completed
## by A) and A's tea_ware_kit claim at the 鶯歌 potter (a real tea_revisit_claim with
## its own exact checks); the parent then builds the kit as a home decoration, moves,
## removes and builds it again, so A ends the parent with the kit placed at home and
## none in the bag.
##
## Hooks into the parent (no parent file is modified):
##  * chapter_one(): fresh world, BEFORE the picnic: all four tea_service actions are
##    refused with LOCKED (no walking: the picnic gate precedes every position check).
##  * act(): right before A's first tea_sell of the revisit jar cycles (A at home, the
##    revisit NOT completed yet — the earliest point the table and the revisit order
##    both exist): A walks to the shared table; place -> NOT_DONE, brew / sip / take ->
##    NOT_PLACED. The parent's tea_sell then walks A back to 小栗 as usual (this
##    detour only changes A's walking path, never a state field besides position).
##  * tr_claim_and_reload(): right after the real claim (A in 鶯歌 with one kit):
##    place -> WRONG_REGION while the pure place_block already says "" (only the
##    location blocks it).
##
## After the parent (A at home):
##  1. place -> NO_KIT (the kit is built as a decoration); A removes the decoration
##     (real `remove`, kit +1), TOO_FAR from there, WRONG_CELL, BAD_EXTRA, then
##     places it: kit leaves the bag, state.tea_service == {"lender":A}; ALREADY,
##     NO_ROUND, NO_TEA, BAD_STYLE; take back the unused set (allowed: no tea) and
##     place it again.
##  2. A rides to 貓空 (brew from there -> WRONG_REGION), picks leaves, roasts TWO
##     淺焙茶 and TWO 深焙茶 at the real roaster (the parent's tr_brew: pick, roast,
##     wait, take, exact bag deltas), rides home. Uses: light = first pot + shared
##     pot, deep = solo re-brew + final pot.
##  3. brew light: tea_light -1, round {style light, portions 6, claimed {}, day D}
##     with D == TeaService.today(state) at brew time; current_round adds left 6,
##     cold false; public round {style, portions, day}. Sip once (no item); SIPPED;
##     TEA_LEFT_BREW for both styles; take -> TEA_LEFT (same-day tea blocks both).
##  4. The festival's shared watermelon round coexists with the tea set (A claims one
##     platter if portions remain and A has not claimed yet, else the exact refusal;
##     serve while portions remain is refused). No hotpot exists in this chain (no
##     trout_hotpot is ever cooked upstream), so the hotpot is NOT exercised here.
##  5. save -> reload mid-round: whole canonical state identical, TeaService.valid,
##     SIPPED again after the reload.
##  6. SINGLE PLAYER (stated plainly): A alone can drink only one cup of a 6-cup pot.
##     The 5 left cups stay drinkable (and block take / re-brew) only on the world day
##     the pot was brewed; leftover tea goes COLD the next world day, after which it no
##     longer blocks re-brewing or taking the set back. Proven solo here, with real
##     World.step time only (the inherited wait(): World.step in 240 s chunks up to
##     next_midnight()+1 s, i.e. at most 1441 world seconds per overnight, twice):
##     overnight -> portions() 0, current_round().left 5, cold true, public keeps the
##     5 real cups, status is the cold sentence, A's sip -> COLD (COLD precedes
##     SIPPED) with state unchanged; save -> reload (cold record identical, valid,
##     still COLD); A re-brews 深焙茶 over the cold pot (round replaced: day D+1,
##     claimed {}, 6 cups, tea_deep -1), sips (5 left), SIPPED / TEA_LEFT_BREW /
##     TEA_LEFT again on that day; overnight -> cold deep pot, sip -> COLD, A takes the
##     set back with 5 cold cups in the pot (kit +1, state.tea_service removed);
##     save -> reload (still no record), sip -> NOT_PLACED.
##  7. Shared pot: A places the set again and brews the second 淺焙茶 (day E), sips;
##     then other REAL islanders finish it. They exist only because the upstream chain
##     created them (festival late member, exhibit newcomer, Jinguashi / tea revisit
##     late joiners, salt-pan players) through World.add_player (the Session join
##     path). Up to five are used: players not currently joined are re-joined with
##     World.add_player(token, their saved name) — the same call the parents use on
##     every reload — players away from home ride home with a real transit action,
##     then walk to the table and sip. SAME-DAY GUARANTEE: in World only World.step
##     advances state.time (move_player, act/transit and save/load never do), and this
##     segment never steps, so every sip happens on day E; each sip asserts
##     today == E. If fewer than five such players exist the journey asserts the 5-N
##     cups left and the TEA_LEFT refusal instead. Multi-player finishing with
##     fixtures is also covered by test_tea_service.gd / test_tea_service_session.gd.
##  8. Pot empty: A's own sip -> EMPTY, a non-lender take -> NOT_LENDER and brew deep
##     -> NO_TEA (if that player holds none), A takes the set back (kit +1, record
##     removed), brew / sip -> NOT_PLACED, A places it again, brews the second earned
##     深焙茶 (6 cups, day E) and sips once: 5 cups left -> TEA_LEFT (same day); final
##     save -> reload identical.
##
## Every refusal is checked with the exact message AND whole World.state unchanged
## (== on the live dictionary and the sorted canonical bytes, the parents' canon_bytes);
## pure *_block functions are compared where they cover the refusal. Every success is
## checked against a whole-state canonical diff that may only touch the listed paths
## (plus the actor's receipts and the commit counter), as the parents' tr_ok does.
##
## EARNED (World.act only): tea_service_place / take / brew / sip, remove (the kit
## decoration), transit, tea_pick / tea_roast / tea_take (the teas), claim_watermelon.
## NON-ACTION CALLS (none writes a field directly): World.move_player (walking along
## BFS routes), World.step via the inherited wait() (roast waits and the two
## overnights), World.save + World.load_world into a fresh World + add_player of the
## active tokens (the parents' ex_reload), World.add_player(token, saved name) to
## re-join existing upstream islanders, and the pure TeaService / TeaRevisit query
## functions. NO direct writes by this file to inventory, coins, flags, tea_service /
## tea_revisit / community records, objects, positions or time.
## Prints TEA_SERVICE_JOURNEY lines, a TEA_SERVICE_JOURNEY_TESTS checks=N failures=M
## line, then the parents' lines; the last checks=N failures=M line is the salt-pan
## base's (same totals).

const TS=preload("res://scripts/tea_service.gd")
const TS_SIPPERS:=5

var ts_fresh_done:=false
var ts_pre_done:=false
var ts_claim_done:=false
var ts_started:=false
var ts_ms:=0
var ts_actions0:=0
var ts_walk0:=0
var ts_time0:=0.0
var ts_checks0:=0
var ts_reloads0:=0
var ts_refusals:=[]
var ts_changed:=0
var ts_rejoined:=[]
var ts_info:={}
var ts_light_day:=0
var ts_deep_day:=0
var ts_shared_day:=0
var ts_waited:=0.0

# ---------------------------------------------------------------- hooks

func chapter_one() -> void:
	if not ts_fresh_done:
		ts_fresh_done=true
		ts_fresh()
	super.chapter_one()

func act(action:String,target:Vector2i,extra:String="") -> Dictionary:
	if action=="tea_sell" and tok==TOKEN_A and tr_started and not ts_pre_done and not failed and world.player_region(tok)=="home" and not TR.completed(world.state):
		ts_pre_done=true
		ts_pre_revisit()
	return super.act(action,target,extra)

func tr_claim_and_reload() -> void:
	super.tr_claim_and_reload()
	if failed:return
	ts_claim_done=true
	var s:=world.state
	var table:=World.COMMUNITY.table_cell(s)
	ts_check(world.player_region(tok)==Tea.YINGGE and int(bag().get(TS.KIT,0))==1 and TR.TEAWARE_ITEM==TS.KIT,"after the claim: A in 鶯歌 holding one %s"%TS.KIT)
	ts_check(TS.place_block(s,bag())=="","after the claim: place_block is empty (only the location blocks placing)")
	ts_deny(TS.PLACE_ACTION,table,"",TS.WRONG_REGION,"place from 鶯歌 right after the claim",false)

## Fresh world, before the picnic.
func ts_fresh() -> void:
	var s:=world.state
	var cell:Vector2i=World.COMMUNITY.CANDIDATES[0]
	ts_check(s.get("picnic",false)!=true and World.COMMUNITY.table_cell(s)==World.COMMUNITY.NO_CELL and not s.has(TS.STATE_KEY),"fresh world: no picnic, no shared table, no tea_service record")
	ts_check(TS.place_block(s,bag())==TS.LOCKED and TS.brew_block(s,"light",bag())==TS.LOCKED and TS.sip_block(s,tok)==TS.LOCKED and TS.take_block(s,bag(),tok)==TS.LOCKED,"fresh world: all four pure blocks say LOCKED")
	ts_deny(TS.PLACE_ACTION,cell,"",TS.LOCKED,"fresh world place (before the picnic)",false)
	ts_deny(TS.BREW_ACTION,cell,"light",TS.LOCKED,"fresh world brew (before the picnic)",false)
	ts_deny(TS.SIP_ACTION,cell,"",TS.LOCKED,"fresh world sip (before the picnic)",false)
	ts_deny(TS.TAKE_ACTION,cell,"",TS.LOCKED,"fresh world take (before the picnic)",false)

## A at home during the first jar cycle: the table exists, the revisit is not done.
func ts_pre_revisit() -> void:
	var s:=world.state
	var table:=World.COMMUNITY.table_cell(s)
	ts_check(s.get("picnic")==true and table!=World.COMMUNITY.NO_CELL,"pre-revisit: earned picnic table at %s"%str(table))
	ts_check(not TR.completed(s) and not s.has(TS.STATE_KEY) and int(bag().get(TS.KIT,0))==0,"pre-revisit: revisit not completed, no tea_service record, no kit")
	ts_info.pre_revisit={"day":TR.today(s),"world_seconds":now(),"table":[table.x,table.y]}
	walk_to(table)
	if failed:return
	ts_check(ts_dist(table)<=TS.REACH,"pre-revisit: A %.2f tiles from the table"%ts_dist(table))
	ts_deny(TS.PLACE_ACTION,table,"",TS.NOT_DONE,"pre-revisit place",false,true)
	ts_deny(TS.BREW_ACTION,table,"light",TS.NOT_PLACED,"pre-revisit brew light",false,true)
	ts_deny(TS.SIP_ACTION,table,"",TS.NOT_PLACED,"pre-revisit sip",false,true)
	ts_deny(TS.TAKE_ACTION,table,"",TS.NOT_PLACED,"pre-revisit take",false,true)
	s=world.state
	ts_check(TS.public(s).is_empty() and TS.status_text(s)=="共餐桌上還沒有茶陶組。","pre-revisit: no public block, status text says no set")

# ---------------------------------------------------------------- journey

func run() -> void:
	super.run()
	if failed:return
	ts_check(ts_fresh_done and ts_pre_done and ts_claim_done,"fresh-world, pre-revisit and post-claim hooks ran")
	ts_started=true
	ts_ms=Time.get_ticks_msec()
	ts_actions0=actions
	ts_walk0=walking
	ts_time0=now()
	ts_checks0=checks
	ts_reloads0=ex_reloads
	tok=TOKEN_A
	print("TEA_SERVICE_JOURNEY prerequisite chain passed (checks %d, actions %d, world_seconds %.1f, day %d)"%[checks,actions,now(),TR.today(world.state)])
	ts_place_leg()
	if not failed:ts_roast_leg()
	if not failed:ts_round_leg()
	if not failed:ts_watermelon_leg()
	if not failed:ts_reload_leg()
	if not failed:ts_solo_leg()
	if not failed:ts_others_leg()

func ts_table() -> Vector2i:
	return World.COMMUNITY.table_cell(world.state)

## Kit home decoration -> bag -> shared table.
func ts_place_leg() -> void:
	var s:=world.state
	var table:=ts_table()
	ts_check(world.player_region(tok)=="home" and TR.completed(s) and TR.claimed_own(s,tok),"start: A at home, 茶罐大單 completed, A claimed the tea ware")
	ts_check(table!=World.COMMUNITY.NO_CELL and not s.has(TS.STATE_KEY),"start: shared table at %s, no tea_service record"%str(table))
	if not ts_check(tr_info.has("teaware"),"parent recorded where it built the tea ware"):return
	var spot:=Vector2i(int(tr_info.teaware[0]),int(tr_info.teaware[1]))
	var deco:Dictionary=s.objects.get(World.key(spot),{})
	if not ts_check(str(deco.get("type",""))==TR.TEAWARE_KIND and str(deco.get("owner",""))==tok,"the earned tea ware stands at %s as A's decoration"%str(spot)):return
	ts_check(int(bag().get(TS.KIT,0))==0,"no kit in the bag while it is built at home")
	ts_check(TS.place_block(s,bag())==TS.NO_KIT,"place_block says NO_KIT")
	walk_to(table)
	ts_deny(TS.PLACE_ACTION,table,"",TS.NO_KIT,"place with the kit built at home",false,true)
	ts_deny(TS.BREW_ACTION,table,"light",TS.NOT_PLACED,"brew before any set is placed",false,true)
	ts_deny(TS.SIP_ACTION,table,"",TS.NOT_PLACED,"sip before any set is placed",false,true)
	ts_deny(TS.TAKE_ACTION,table,"",TS.NOT_PLACED,"take before any set is placed",false,true)
	if failed:return
	# Pick the decoration up again (real remove): the kit returns to the bag.
	var before:Dictionary=bag().duplicate(true)
	act("remove",spot)
	if failed:return
	ts_bag(before,{TS.KIT:1},"remove the tea ware decoration: kit +1")
	ts_check(not world.state.objects.has(World.key(spot)),"decoration gone from %s"%str(spot))
	ts_info.removed_from=[spot.x,spot.y]
	var gap:=ts_dist(table)
	if ts_check(gap>TS.REACH,"beside the removed decoration, %.2f tiles from the table"%gap):
		ts_deny(TS.PLACE_ACTION,table,"",TS.TOO_FAR,"place from the decoration spot (too far)",false)
	walk_to(table)
	ts_deny(TS.PLACE_ACTION,BOARD,"",TS.WRONG_CELL,"place aimed at the dock board",false)
	ts_deny(TS.PLACE_ACTION,table+Vector2i(1,1),"",TS.WRONG_CELL,"place aimed beside the table",false)
	ts_deny(TS.PLACE_ACTION,table,"x",TS.BAD_EXTRA,"place with a non-empty extra",false)
	ts_place("first placement")
	if failed:return
	ts_deny(TS.PLACE_ACTION,table,"",TS.ALREADY,"second place (no kit left either)",false,true)
	ts_deny(TS.SIP_ACTION,table,"",TS.NO_ROUND,"sip before any brew",false,true)
	ts_deny(TS.SIP_ACTION,table,"x",TS.BAD_EXTRA,"sip with a non-empty extra",false)
	ts_deny(TS.BREW_ACTION,table,"oolong",TS.BAD_STYLE,"brew an unknown style",false,true)
	ts_deny(TS.BREW_ACTION,table,"",TS.BAD_STYLE,"brew with an empty style",false,true)
	if int(bag().get("tea_light",0))==0:
		ts_deny(TS.BREW_ACTION,table,"light",TS.NO_TEA%TS.STYLE_NAMES.light,"brew light with no 淺焙茶",false,true)
	if int(bag().get("tea_deep",0))==0:
		ts_deny(TS.BREW_ACTION,table,"deep",TS.NO_TEA%TS.STYLE_NAMES.deep,"brew deep with no 深焙茶",false,true)
	ts_check(TS.status_text(world.state)=="茶陶組擺在共餐桌上，茶壺還是空的。","status: set on the table, pot empty")
	# An unused set can go back to the lender (no tea left) and be placed again.
	ts_take("take the unused set back")
	if failed:return
	ts_deny(TS.TAKE_ACTION,table,"",TS.NOT_PLACED,"take again after taking it back",false,true)
	ts_place("place again")

func ts_place(label:String) -> void:
	var table:=ts_table()
	var before:Dictionary=bag().duplicate(true)
	ts_check(int(before.get(TS.KIT,0))>=1 and TS.place_block(world.state,before)=="","%s: place_block empty with a kit in the bag"%label)
	ts_ok(TS.PLACE_ACTION,table,"",TS.PLACED_OK,label,["state.%s"%TS.STATE_KEY,"state.players.%s.inventory.%s"%[tok,TS.KIT]])
	if failed:return
	ts_bag(before,{TS.KIT:-1},label+": kit leaves the bag")
	var s:=world.state
	ts_check(same_canon(s.get(TS.STATE_KEY),{"lender":TOKEN_A}),"%s: state.tea_service == {lender:A} (%s)"%[label,JSON.stringify(s.get(TS.STATE_KEY))])
	ts_check(TS.placed(s) and TS.lender_own(s,TOKEN_A) and same_canon(TS.public(s),{"placed":true}) and TS.current_round(s).is_empty() and TS.portions(s)==0,"%s: placed, A is the lender, public {placed:true}, no round"%label)

func ts_take(label:String) -> void:
	var table:=ts_table()
	var before:Dictionary=bag().duplicate(true)
	ts_check(TS.take_block(world.state,before,tok)=="","%s: take_block empty"%label)
	ts_ok(TS.TAKE_ACTION,table,"",TS.TAKEN_OK,label,["state.%s"%TS.STATE_KEY,"state.players.%s.inventory.%s"%[tok,TS.KIT]])
	if failed:return
	ts_bag(before,{TS.KIT:1},label+": kit back in the bag")
	ts_check(not world.state.has(TS.STATE_KEY) and not TS.placed(world.state) and TS.public(world.state).is_empty(),"%s: tea_service record removed"%label)

## Earn one 淺焙茶 and one 深焙茶 at the real 貓空 roaster.
func ts_roast_leg() -> void:
	var held0:=tr_held(["tea_leaf","tea_light","tea_deep"])
	ts_info.tea_before_roast=held0
	travel(FERRY,Tea.MAOKONG)
	if failed:return
	ts_deny(TS.BREW_ACTION,ts_table(),"light",TS.WRONG_REGION,"brew from 貓空",false)
	ts_deny(TS.SIP_ACTION,ts_table(),"",TS.WRONG_REGION,"sip from 貓空",false)
	var t0:=now()
	for style:String in ["light","deep","light","deep"]:
		tr_brew(style)
		if failed:return
	ts_check(int(bag().get("tea_light",0))==int(held0.tea_light)+2 and int(bag().get("tea_deep",0))==int(held0.tea_deep)+2,"roasted two light and two deep (%s -> %s)"%[JSON.stringify(held0),JSON.stringify(tr_held(["tea_leaf","tea_light","tea_deep"]))])
	ts_info.roast={"world_seconds":now()-t0,"held":tr_held(["tea_leaf","tea_light","tea_deep"])}
	travel(World.TRANSIT.points(Tea.MAOKONG).transfer.cell,"home")

## Brew light, sip once, the refusals of a single-player pot.
func ts_round_leg() -> void:
	var table:=ts_table()
	walk_to(table)
	if failed:return
	var before:Dictionary=bag().duplicate(true)
	ts_check(TS.brew_block(world.state,"light",before)=="","brew_block light empty")
	ts_ok(TS.BREW_ACTION,table,"light",TS.BREWED_OK%TS.STYLE_NAMES.light,"brew 淺焙茶",["state.%s.round"%TS.STATE_KEY,"state.players.%s.inventory.tea_light"%tok])
	if failed:return
	ts_bag(before,{"tea_light":-1},"brew light: tea_light -1")
	var s:=world.state
	ts_light_day=TS.today(s)
	ts_info.light_brew={"day":ts_light_day,"world_seconds":now()}
	ts_check(ts_light_day>=1 and ts_light_day==TR.today(s),"brew day %d is the 1-based world day (same as tea_revisit.today)"%ts_light_day)
	ts_check(same_canon(s.get(TS.STATE_KEY),{"lender":TOKEN_A,"round":{"style":"light","portions":TS.CUPS,"claimed":{},"day":ts_light_day}}),"after brewing: %s"%JSON.stringify(s.get(TS.STATE_KEY)))
	ts_check(TS.portions(s)==TS.CUPS and same_canon(TS.current_round(s),{"style":"light","portions":TS.CUPS,"day":ts_light_day,"left":TS.CUPS,"cold":false}) and same_canon(TS.public(s),{"placed":true,"round":{"style":"light","portions":TS.CUPS,"day":ts_light_day}}) and TS.status_text(s)=="桌上有一壺淺焙茶，還剩 6／6 杯。","6 cups of 淺焙茶 on the table, current_round/public/status agree (%s / %s)"%[JSON.stringify(TS.current_round(s)),JSON.stringify(TS.public(s))])
	before=bag().duplicate(true)
	ts_check(TS.sip_block(world.state,tok)=="" and not TS.sipped_own(world.state,tok),"A has not sipped yet")
	ts_ok(TS.SIP_ACTION,table,"",TS.SIP_OK%[TS.STYLE_NAMES.light,TS.CUPS-1],"A sips",["state.%s.round"%TS.STATE_KEY])
	if failed:return
	ts_check(same_canon(bag(),before),"sip gives no item (bag identical)")
	var claimed:={}
	claimed[TOKEN_A]=true
	s=world.state
	ts_check(same_canon(s.get(TS.STATE_KEY),{"lender":TOKEN_A,"round":{"style":"light","portions":TS.CUPS-1,"claimed":claimed,"day":ts_light_day}}) and TS.sipped_own(s,TOKEN_A),"after A's sip: 5 cups, claimed {A}, day %d (%s)"%[ts_light_day,JSON.stringify(s.get(TS.STATE_KEY))])
	ts_deny(TS.SIP_ACTION,table,"",TS.SIPPED,"A sips again",false,true)
	ts_deny(TS.BREW_ACTION,table,"light",TS.TEA_LEFT_BREW,"brew light while tea is left",false,true)
	ts_deny(TS.BREW_ACTION,table,"deep",TS.TEA_LEFT_BREW,"brew deep while tea is left (A holds 深焙茶)",false,true)
	ts_deny(TS.TAKE_ACTION,table,"",TS.TEA_LEFT,"lender takes the set back while tea is left",false,true)
	ts_deny(TS.PLACE_ACTION,table,"",TS.ALREADY,"place while a round is on the table",false,true)

## The festival's watermelon round still behaves next to the tea set.
func ts_watermelon_leg() -> void:
	var table:=ts_table()
	var title:=str(World.NAMES["watermelon_platter"])
	var community:Dictionary=world.state.get("community",{})
	var found:Variant=community.get("watermelon")
	var tea_bytes:=canon_bytes(world.state.get(TS.STATE_KEY))
	if not found is Dictionary:
		ts_info.watermelon="no watermelon round on the table (skipped)"
		print("TEA_SERVICE_JOURNEY watermelon: no round on the table, skipped")
		return
	var wm:Dictionary=found
	var left:=int(wm.get("portions",0))
	var mine:=(wm.get("claimed",{}) as Dictionary).has(TOKEN_A)
	ts_info.watermelon_before={"portions":left,"claimed_by_A":mine}
	if left>0:
		ts_deny("serve_watermelon",table,"","餐桌上還有%s，先留給晚點回來的島民。"%title,"serve watermelon while portions remain",false)
	if left>0 and not mine:
		var before:Dictionary=bag().duplicate(true)
		ts_ok("claim_watermelon",table,"","已領取一份%s。"%title,"A claims a festival watermelon portion",["state.community.watermelon","state.players.%s.inventory.watermelon_platter"%tok,"state.players.%s.collection"%tok,"state.players.%s.meals_discoveries"%tok,"state.island_meals_discoveries"])
		if failed:return
		ts_bag(before,{"watermelon_platter":1},"watermelon claim: platter +1")
		ts_check(int(world.state.community.watermelon.portions)==left-1 and (world.state.community.watermelon.claimed as Dictionary).has(TOKEN_A),"watermelon portions %d -> %d"%[left,left-1])
		ts_deny("claim_watermelon",table,"","你已領過這一輪，剩下的留給其他島民。","A claims watermelon again",false)
	elif left>0:
		ts_deny("claim_watermelon",table,"","你已領過這一輪，剩下的留給其他島民。","A claims watermelon again (claimed upstream)",false)
	else:
		ts_deny("claim_watermelon",table,"","%s已經分完了。"%title,"claim from a finished watermelon round",false)
	ts_check(canon_bytes(world.state.get(TS.STATE_KEY))==tea_bytes,"watermelon actions leave the tea round byte-identical")
	ts_info.watermelon_after=JSON.stringify(world.state.community.get("watermelon"))

## Save + reload mid-round.
func ts_reload_leg() -> void:
	var rec:=canon_bytes(world.state.get(TS.STATE_KEY))
	var kit:=int(bag().get(TS.KIT,0))
	ex_reload("mid tea round (5 of 6 cups left)")
	if failed:return
	var s:=world.state
	ts_check(canon_bytes(s.get(TS.STATE_KEY))==rec,"tea_service record identical after reload")
	ts_check(TS.valid(s) and TS.portions(s)==TS.CUPS-1 and TS.sipped_own(s,TOKEN_A) and TS.lender_own(s,TOKEN_A),"reloaded tea_service valid: 5 cups, A sipped, A lender")
	ts_check(TS.today(s)==ts_light_day and int(TS.current_round(s).get("day",0))==ts_light_day and TS.current_round(s).get("cold")==false,"still the brew day %d after the reload (no World.step since the brew), tea not cold"%ts_light_day)
	ts_check(int(bag().get(TS.KIT,0))==kit and world.player_region(tok)=="home","A still home, kit count %d"%kit)
	var table:=ts_table()
	walk_to(table)
	ts_deny(TS.SIP_ACTION,table,"",TS.SIPPED,"A sips after the reload",false,true)
	ts_deny(TS.TAKE_ACTION,table,"",TS.TEA_LEFT,"take after the reload",false,true)

## Single player: leftover tea goes cold the next world day (header item 6).
func ts_solo_leg() -> void:
	tok=TOKEN_A
	var table:=ts_table()
	var s:=world.state
	ts_check(TS.today(s)==ts_light_day and TS.portions(s)==TS.CUPS-1 and TS.current_round(s).get("cold")==false,"solo: still brew day %d, 5 cups drinkable before any World.step"%ts_light_day)
	var light_left:=TS.CUPS-1
	ts_next_day("solo: overnight after the light pot")
	if failed:return
	ts_cold("light",ts_light_day,light_left,"solo, day after the light pot")
	walk_to(table)
	ts_deny(TS.SIP_ACTION,table,"",TS.COLD,"A sips the cold light pot (already sipped; COLD comes before SIPPED)",false,true)
	if failed:return
	var cold_rec:=canon_bytes(world.state.get(TS.STATE_KEY))
	ex_reload("solo: cold light pot (5 cups left)")
	if failed:return
	ts_check(canon_bytes(world.state.get(TS.STATE_KEY))==cold_rec and TS.valid(world.state),"cold light record identical and valid after reload")
	ts_cold("light",ts_light_day,light_left,"solo, cold light pot after reload")
	walk_to(table)
	ts_deny(TS.SIP_ACTION,table,"",TS.COLD,"A sips the cold light pot after the reload",false,true)
	if failed:return
	# Re-brew the other style over the cold cups.
	var before:Dictionary=bag().duplicate(true)
	ts_check(int(before.get("tea_deep",0))>=1 and TS.brew_block(world.state,"deep",before)=="","solo: brew_block deep empty over the cold pot")
	ts_ok(TS.BREW_ACTION,table,"deep",TS.BREWED_OK%TS.STYLE_NAMES.deep,"re-brew 深焙茶 over the cold light pot",["state.%s.round"%TS.STATE_KEY,"state.players.%s.inventory.tea_deep"%tok])
	if failed:return
	ts_bag(before,{"tea_deep":-1},"re-brew deep: tea_deep -1")
	s=world.state
	ts_deep_day=TS.today(s)
	ts_check(ts_deep_day==ts_light_day+1,"re-brew day %d is the day after the light pot (%d)"%[ts_deep_day,ts_light_day])
	ts_check(same_canon(s.get(TS.STATE_KEY),{"lender":TOKEN_A,"round":{"style":"deep","portions":TS.CUPS,"claimed":{},"day":ts_deep_day}}),"round replaced (new day, claimed empty, 6 cups): %s"%JSON.stringify(s.get(TS.STATE_KEY)))
	ts_check(same_canon(TS.current_round(s),{"style":"deep","portions":TS.CUPS,"day":ts_deep_day,"left":TS.CUPS,"cold":false}) and not TS.sipped_own(s,TOKEN_A) and TS.status_text(s)=="桌上有一壺深焙茶，還剩 6／6 杯。","fresh deep pot: 6 drinkable cups, A not marked as sipped")
	before=bag().duplicate(true)
	ts_ok(TS.SIP_ACTION,table,"",TS.SIP_OK%[TS.STYLE_NAMES.deep,TS.CUPS-1],"A sips the re-brewed deep pot",["state.%s.round"%TS.STATE_KEY])
	if failed:return
	ts_check(same_canon(bag(),before),"deep sip gives no item (bag identical)")
	ts_deny(TS.SIP_ACTION,table,"",TS.SIPPED,"A sips the deep pot again (same day)",false,true)
	ts_deny(TS.BREW_ACTION,table,"light",TS.TEA_LEFT_BREW,"brew light over the same-day deep pot",false,true)
	ts_deny(TS.TAKE_ACTION,table,"",TS.TEA_LEFT,"take with the same-day deep pot at 5 cups",false,true)
	if failed:return
	ts_next_day("solo: overnight after the deep pot")
	if failed:return
	ts_cold("deep",ts_deep_day,TS.CUPS-1,"solo, day after the deep pot")
	walk_to(table)
	ts_deny(TS.SIP_ACTION,table,"",TS.COLD,"A sips the cold deep pot",false,true)
	if failed:return
	var kit:=int(bag().get(TS.KIT,0))
	ts_take("lender takes the set back with 5 cold cups in the pot")
	if failed:return
	ts_check(int(bag().get(TS.KIT,0))==kit+1 and not world.state.has(TS.STATE_KEY),"solo take: kit %d -> %d, state.tea_service gone"%[kit,int(bag().get(TS.KIT,0))])
	ex_reload("solo: set taken back over cold tea")
	if failed:return
	ts_check(not world.state.has(TS.STATE_KEY) and int(bag().get(TS.KIT,0))==kit+1 and TS.valid(world.state),"after reload: no tea_service record, kit %d"%(kit+1))
	walk_to(table)
	ts_deny(TS.SIP_ACTION,table,"",TS.NOT_PLACED,"sip after the solo take",false,true)
	ts_info.solo={"light_day":ts_light_day,"deep_day":ts_deep_day,"took_back_day":TS.today(world.state),"overnight_world_seconds":ts_waited}

## One overnight through World.step only (inherited wait(): 240 s chunks up to
## next_midnight()+1 s).
func ts_next_day(label:String) -> void:
	if failed:return
	var day0:=TS.today(world.state)
	var t0:=now()
	wait(next_midnight()+1.0-now())
	if failed:return
	var spent:=now()-t0
	ts_waited+=spent
	ts_check(TS.today(world.state)==day0+1,"%s: world day %d -> %d after %.1f world seconds of World.step"%[label,day0,TS.today(world.state),spent])

## The pot brewed on `day` is cold today: no drinkable cups, `left` real cups stay.
func ts_cold(style:String,day:int,left:int,label:String) -> void:
	var s:=world.state
	var tea_name:=TS.style_name(style)
	var now_round:Dictionary=TS.current_round(s)
	ts_check(TS.today(s)>day,"%s: today %d is after brew day %d"%[label,TS.today(s),day])
	ts_check(same_canon(now_round,{"style":style,"portions":0,"day":day,"left":left,"cold":true}),"%s: current_round cold %s"%[label,JSON.stringify(now_round)])
	ts_check(TS.portions(s)==0 and int(now_round.get("left",-1))==left,"%s: portions() 0 while current_round().left is %d"%[label,left])
	ts_check(same_canon(TS.public(s),{"placed":true,"round":{"style":style,"portions":left,"day":day}}),"%s: public keeps the real cups %s"%[label,JSON.stringify(TS.public(s))])
	ts_check(TS.status_text(s)=="前一天泡的%s已經涼了，可以重新泡一壺。"%tea_name,"%s: cold status '%s'"%[label,TS.status_text(s)])
	ts_check(TS.sip_block(s,TOKEN_A)==TS.COLD and TS.take_block(s,bag(),TOKEN_A)=="","%s: sip_block COLD, take_block empty (cold cups do not block taking)"%label)
	var other:String="deep" if style=="light" else "light"
	var other_item:String=str(TS.TEA_ITEMS[other])
	if int(bag().get(other_item,0))>=1:
		ts_check(TS.brew_block(s,other,bag())=="","%s: brew_block %s empty (cold cups do not block brewing)"%[label,other])

## Other REAL upstream islanders finish a fresh shared pot (header items 7-8).
func ts_others_leg() -> void:
	tok=TOKEN_A
	var table:=ts_table()
	ts_place("place the set for the shared pot")
	if failed:return
	var light_before:Dictionary=bag().duplicate(true)
	ts_check(int(light_before.get("tea_light",0))>=1,"A still holds a roasted 淺焙茶 for the shared pot")
	ts_ok(TS.BREW_ACTION,table,"light",TS.BREWED_OK%TS.STYLE_NAMES.light,"brew the shared 淺焙茶 pot",["state.%s.round"%TS.STATE_KEY,"state.players.%s.inventory.tea_light"%tok])
	if failed:return
	ts_bag(light_before,{"tea_light":-1},"shared pot: tea_light -1")
	ts_shared_day=TS.today(world.state)
	ts_info.shared_brew={"day":ts_shared_day,"world_seconds":now(),"seconds_to_midnight":next_midnight()-now()}
	ts_check(same_canon(world.state.get(TS.STATE_KEY),{"lender":TOKEN_A,"round":{"style":"light","portions":TS.CUPS,"claimed":{},"day":ts_shared_day}}),"shared pot: %s"%JSON.stringify(world.state.get(TS.STATE_KEY)))
	ts_ok(TS.SIP_ACTION,table,"",TS.SIP_OK%[TS.STYLE_NAMES.light,TS.CUPS-1],"A sips the shared pot",["state.%s.round"%TS.STATE_KEY])
	if failed:return
	var sippers:=ts_pick_sippers(TS_SIPPERS)
	ts_info.sippers=sippers.duplicate()
	print("TEA_SERVICE_JOURNEY sippers %s (players in save %d)"%[JSON.stringify(sippers),world.state.players.size()])
	var n:=0
	for who:String in sippers:
		if failed:return
		if not world.active_tokens.has(who):
			world.add_player(who,str(world.state.players[who].name))
			ts_rejoined.append(who)
		tok=who
		var region:=world.player_region(who)
		if region!="home":
			travel(ts_way_home(region),"home")
			if failed:return
		walk_to(table)
		if failed:return
		var left:=TS.portions(world.state)
		ts_check(TS.today(world.state)==ts_shared_day and TS.current_round(world.state).get("cold")==false,"%s reaches the table on the shared brew day %d (walking/transit never advance world time)"%[who,ts_shared_day])
		ts_check(TS.sip_block(world.state,tok)=="" and not TS.lender_own(world.state,tok),"%s may sip (%d left), is not the lender"%[who,left])
		var sip_bag:Dictionary=bag().duplicate(true)
		ts_ok(TS.SIP_ACTION,table,"",TS.SIP_OK%[TS.STYLE_NAMES.light,left-1],"%s sips"%who,["state.%s.round"%TS.STATE_KEY])
		if failed:return
		ts_check(same_canon(bag(),sip_bag) and TS.sipped_own(world.state,who),"%s: no item, marked as sipped"%who)
		n+=1
		if n==1:
			ts_deny(TS.SIP_ACTION,table,"",TS.SIPPED,"%s sips again"%who,false,true)
			ts_deny(TS.TAKE_ACTION,table,"",TS.NOT_LENDER,"%s (not the lender) takes while tea is left"%who,false,true)
	tok=TOKEN_A
	var s:=world.state
	ts_info.cups_left_after_others=TS.portions(s)
	if sippers.size()<TS_SIPPERS:
		print("TEA_SERVICE_JOURNEY only %d other islanders could reach the table; the pot keeps %d cups"%[sippers.size(),TS.CUPS-1-sippers.size()])
		ts_check(TS.portions(s)==TS.CUPS-1-sippers.size(),"%d cups left after A and %d others"%[TS.CUPS-1-sippers.size(),sippers.size()])
		walk_to(table)
		ts_deny(TS.TAKE_ACTION,table,"",TS.TEA_LEFT,"lender take with tea still left",false,true)
		ex_reload("final (pot not finished)")
		return
	ts_check(TS.portions(s)==0 and (s[TS.STATE_KEY].round.claimed as Dictionary).size()==TS.CUPS and TS.status_text(s)=="上一壺淺焙茶已經喝完了。","pot finished by A + %d islanders; status says finished"%sippers.size())
	ts_check(TS.valid(s),"finished round is a valid save record")
	walk_to(table)
	ts_deny(TS.SIP_ACTION,table,"",TS.EMPTY,"A sips from the finished pot",false,true)
	tok=str(sippers[0])
	ts_deny(TS.TAKE_ACTION,table,"",TS.NOT_LENDER,"%s takes the set from the finished pot (not the lender)"%tok,false,true)
	if int(bag().get("tea_deep",0))==0:
		ts_deny(TS.BREW_ACTION,table,"deep",TS.NO_TEA%TS.STYLE_NAMES.deep,"%s brews deep with no 深焙茶"%tok,false,true)
	tok=TOKEN_A
	if failed:return
	ts_take("lender takes the set back after the pot is finished")
	if failed:return
	ts_deny(TS.BREW_ACTION,table,"deep",TS.NOT_PLACED,"brew after the set was taken back",false,true)
	ts_deny(TS.SIP_ACTION,table,"",TS.NOT_PLACED,"sip after the set was taken back",false,true)
	ts_place("place the set again after the shared pot")
	if failed:return
	var deep_before:Dictionary=bag().duplicate(true)
	ts_ok(TS.BREW_ACTION,table,"deep",TS.BREWED_OK%TS.STYLE_NAMES.deep,"brew the second earned 深焙茶",["state.%s.round"%TS.STATE_KEY,"state.players.%s.inventory.tea_deep"%tok])
	if failed:return
	ts_bag(deep_before,{"tea_deep":-1},"brew deep: tea_deep -1")
	ts_check(TS.today(world.state)==ts_shared_day,"final deep pot brewed on the shared day %d (no World.step in this segment)"%ts_shared_day)
	ts_check(same_canon(world.state.get(TS.STATE_KEY),{"lender":TOKEN_A,"round":{"style":"deep","portions":TS.CUPS,"claimed":{},"day":TS.today(world.state)}}),"fresh deep round: %s"%JSON.stringify(world.state.get(TS.STATE_KEY)))
	ts_ok(TS.SIP_ACTION,table,"",TS.SIP_OK%[TS.STYLE_NAMES.deep,TS.CUPS-1],"A sips the deep pot",["state.%s.round"%TS.STATE_KEY])
	if failed:return
	ts_deny(TS.TAKE_ACTION,table,"",TS.TEA_LEFT,"lender take with the deep pot at 5 cups",false,true)
	ts_check(TS.status_text(world.state)=="桌上有一壺深焙茶，還剩 5／6 杯。","status: 5 of 6 cups of 深焙茶")
	var rec:=canon_bytes(world.state.get(TS.STATE_KEY))
	ex_reload("final (deep pot, 5 cups)")
	if failed:return
	ts_check(canon_bytes(world.state.get(TS.STATE_KEY))==rec and TS.valid(world.state),"final tea_service record identical and valid after reload")

## Other players created upstream: joined first, home first, then by token order.
func ts_pick_sippers(need:int) -> Array:
	var groups:=[[],[],[],[]]
	var tokens:Array=[]
	for t in world.state.players:tokens.append(str(t))
	tokens.sort()
	for t:String in tokens:
		if t==TOKEN_A:continue
		var region:=world.player_region(t)
		var home:=region=="home"
		if not home and ts_way_home(region)==Vector2i(-1,-1):continue
		var index:=(0 if world.active_tokens.has(t) else 2)+(0 if home else 1)
		(groups[index] as Array).append(t)
	var out:=[]
	for group in groups:out.append_array(group)
	return out.slice(0,need)

## The transit gate each upstream journey uses to ride home from that region.
func ts_way_home(region:String) -> Vector2i:
	if region==Tea.YINGGE:return World.TRANSIT.points(Tea.YINGGE).transfer.cell
	if region==Tea.MAOKONG:return World.TRANSIT.points(Tea.MAOKONG).transfer.cell
	if region=="jinguashi":return World.TRANSIT.STATIONS.jinguashi.cell
	if region==S.REGION:return S.TRANSFER
	if region==F.REGION:return tianwei_cell()
	return Vector2i(-1,-1)

# ---------------------------------------------------------------- report

func finish() -> void:
	if ts_started:
		print("TEA_SERVICE_JOURNEY info=%s"%JSON.stringify(ts_info))
		print("TEA_SERVICE_JOURNEY rejoined (World.add_player of existing upstream players) %s"%JSON.stringify(ts_rejoined))
		for i in ts_refusals.size():print("TEA_SERVICE_JOURNEY refusal %d %s"%[i+1,ts_refusals[i]])
		var t:=float(world.state.get("time",0.0))
		print("TEA_SERVICE_JOURNEY stats segment_actions=%d segment_rejections=%d (all, incl. hooks) all_rejections_state_unchanged=%s segment_walk_tiles=%d segment_world_seconds=%.1f segment_reloads=%d segment_checks=%d segment_ms=%d actions_total=%d walk_tiles_total=%d world_seconds_total=%.1f passed=%s"%[actions-ts_actions0,ts_refusals.size(),str(ts_changed==0),walking-ts_walk0,t-ts_time0,ex_reloads-ts_reloads0,checks-ts_checks0,Time.get_ticks_msec()-ts_ms,actions,walking,t,str(not failed)])
		print("TEA_SERVICE_JOURNEY_TESTS checks=%d failures=%d (tea service slice checks=%d)"%[checks,failures,checks-ts_checks0])
	else:
		print("TEA_SERVICE_JOURNEY did not reach the tea service segment (refusals so far %d, fresh=%s pre=%s claim=%s)"%[ts_refusals.size(),str(ts_fresh_done),str(ts_pre_done),str(ts_claim_done)])
	super.finish()

# ---------------------------------------------------------------- helpers

func ts_check(condition:bool,message:String) -> bool:
	return expect(condition,"TEA_SERVICE_JOURNEY: "+message)

func ts_dist(cell:Vector2i) -> float:
	return Vector2(person().x,person().y).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## Whole bag equals `before` plus `delta` (an item that reaches 0 is absent).
func ts_bag(before:Dictionary,delta:Dictionary,label:String) -> void:
	var want:Dictionary=before.duplicate(true)
	for item:String in delta:
		var v:=int(want.get(item,0))+int(delta[item])
		if v==0:want.erase(item)
		else:want[item]=v
	ts_check(same_canon(bag(),want),"%s: whole bag delta %s"%[label,JSON.stringify(delta)])

func ts_block(action:String,extra:String) -> String:
	var s:=world.state
	if action==TS.PLACE_ACTION:return TS.place_block(s,bag())
	if action==TS.TAKE_ACTION:return TS.take_block(s,bag(),tok)
	if action==TS.BREW_ACTION:return TS.brew_block(s,extra,bag())
	if action==TS.SIP_ACTION:return TS.sip_block(s,tok)
	return "?"

## Refused with the exact message; whole World.state unchanged (== and sorted bytes).
## pure: the position-independent *_block function must say the same.
func ts_deny(action:String,target:Vector2i,extra:String,message:String,label:String,walk:=true,pure:=false) -> void:
	if failed:return
	if walk:walk_to(target)
	if failed:return
	if pure:
		var block:=ts_block(action,extra)
		ts_check(block==message,"%s: pure block agrees '%s' (got '%s')"%[label,message,block])
	actions+=1
	var state_before:Dictionary=world.state.duplicate(true)
	var bytes_before:=canon_bytes(world.state)
	var result:=world.act(tok,"ts-journey-%d"%actions,action,target,extra)
	ts_check(not result.ok and str(result.message)==message,"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var unchanged:=world.state==state_before and canon_bytes(world.state)==bytes_before
	ts_check(unchanged,label+": whole world state unchanged")
	if not unchanged:ts_changed+=1
	ts_refusals.append("%s | %s %s %s | %s | %s | state_unchanged=%s"%[label,action,str(target),extra,tok,str(result.message),str(unchanged)])

## A successful action with the exact message; the whole canonical state may differ
## only under `allowed` (plus the actor's receipts and the commit counter).
func ts_ok(action:String,target:Vector2i,extra:String,message:String,label:String,allowed:Array) -> String:
	if failed:return ""
	walk_to(target)
	if failed:return ""
	actions+=1
	var rid:="ts-journey-%d"%actions
	var before:Variant=ex_canon(world.state)
	var result:=world.act(tok,rid,action,target,extra)
	ts_check(result.ok==true and str(result.message)==message,"%s: ok '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
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
	ts_check(other.is_empty() and not diffs.is_empty(),"%s: whole-state diff only under %s (other %s)"%[label,str(allowed),JSON.stringify(other.slice(0,5))])
	return rid
