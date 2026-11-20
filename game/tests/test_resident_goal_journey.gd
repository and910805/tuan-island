extends "res://tests/test_flower_journey.gd"
## T066「一起做的事」(resident_goals.gd) natural journey: a FRESH single-player World
## plays from a brand-new save to five completed relationship goals (28 published).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
## One player, one process. Everything goes through World.act (after walking cell by
## cell with World.move_player along passable tiles, inherited walk_to) and
## World.step(dt,true). World time only advances through explicit waits: the reused
## chapter_one() and grow() call World.step directly, this file's rg_wait() steps in
## chunks of at most 240 world seconds (a new world day = rg_wait up to the next
## midnight + 1 s). Walking, acting, saving and loading never advance time.
##
## Prerequisite (reused parent logic, unmodified): test_flower_journey.chapter_one()
## — chapter one earned on a fresh world (crops, ship, donate, irrigation, stove,
## soup + bread, ferry picnic 渡口野餐). Its act() calls are intercepted here only to
## insert refusals right before the picnic action. Chapters two to five are skipped
## (not needed). Helper approach copied from test_market_stall_journey.gd (own-plot
## farming, seed buying with earned coins, stove cooking, whole-bag deltas).
##
## Route after the picnic (all at home):
##  1. Before any talk: 米露 milu:1:: / 鈴婆婆 lingpopo:2::102 / 洛洛 luoluo:3:aloud:
##     refused (stage not reached); malformed / unknown-stage / unknown-resident
##     extras, a wrong target cell beside 米露 and 米露's cell from 鈴婆婆's grass
##     (too far) refused. First talks with 米露, 鈴婆婆, 洛洛 (+1 each). 米露 is now
##     認識 but the bag holds no 蘿蔔湯 (the picnic took both bowls) -> refused
##     "還差蘿蔔湯 0／1。".
##  2. Radishes and wheat grown on the player's own chapter-one plots (seeds from the
##     picnic gift / start bag, wheat seeds bought from 小栗 with earned coins),
##     watered, waited, harvested (exact whole-bag deltas); 2 soups (4 bowls) and 4
##     breads cooked on the own stove (exact deltas).
##  3. 米露「忘記吃飯的人」milu:1:: succeeds: soup -1 exactly, player.bond_goals
##     {milu:{"1":""}}, bonds and every stage unchanged; repeat refused; gift a soup
##     to 米露 afterwards (+3) and talk to her on later days.
##  4. Day loop (World.step only): talk + liked gift each world day — 鈴婆婆 gets 蘿蔔湯
##     (+3), 洛洛 gets 麵包 (+3). Before each stage is reached the goal is refused with
##     the stage message. 鈴婆婆 at 熟悉: all five wrong bell orders refused with the
##     order message, malformed step strings refused, right order 102 succeeds
##     (no items), repeat refused. 洛洛 at 信任 (14 points, four world days): the loop
##     stops there; her stage-3 goal now waits for her stage-2 report (step 5): after it,
##     missing / unknown option and stray steps refused, option "aloud" succeeds (no
##     items), repeat refused; 洛洛 stage 4 refused with the 好友 stage message.
##  5. Batch-2 prerequisite (needs) 洛洛「沒有地址的信」luoluo:2:: (known_three):
##     洛洛 is past 熟悉 but only 米露 and 鈴婆婆 are known -> the view (built with the
##     world state) shows needs [{known_three,"…（目前 2 位）",met false}]; a stray
##     option / steps refused with the reopen message (checked before needs); the
##     goal refused with exactly "還不能一起做這件事：要先「認識洛洛以外的三位居民
##     （目前 2 位）」。", state unchanged. 阿榆 goal refused before meeting him; an
##     ordinary first talk with 阿榆 (home, 渡口長椅) makes him 認識 = the third known
##     resident -> needs met, label "（目前 3 位）", goal succeeds with no items, done
##     view carries no needs; repeat refused; save + reload; repeat refused again.
##     Before it, stage 3 (postcard_reported) syntax is refused first, then a valid
##     option is refused with the need message; afterwards the stage-3 leg runs.
##  6. Batch-2 prerequisite 阿榆「有點歪的第一塊板」aru:1:: (own_bed + 10 wood):
##     at 認識 with no bed of one's own -> needs own_bed met=false; stray option
##     refused; goal refused "還不能一起做這件事：要先「家園裡有一張你放的小床」。".
##     Wood and fiber gathered the way the parent journeys do (axe on the nearest
##     tree: exactly wood+6 fiber+2 sapling+1 resin+1 per felled tree; axe on grass:
##     exactly fiber+4), only up to the 小床 cost (15 wood, 10 fiber, read from
##     World.BUILD and checked against those literals); 小床 placed by the real
##     `build` action on an empty home cell found by search (away from every
##     resident stand, no neighbouring object/crop/floor, all four sides standable):
##     exact message, wood -15 fiber -10 exactly, objects[cell] {type bed, owner me}.
##     With fewer than 10 wood left: refused "還差木材 n／10。" (state unchanged;
##     skipped with a printed note only if the leftover wood is already >= 10). Trees
##     felled up to 10 wood; goal succeeds: wood exactly -10, keepsake_aru_kit +1
##     exactly (batch 3: the message gains the keepsake sentence, player.bond_keepsakes
##     {keepsake_aru:true}, view row carries keepsake{claimed true}), the bed stays;
##     repeat refused; save + reload (bed and own_bed still there); repeat refused again.
##  6b. Batch-3 keepsake 「有點歪的第一塊板」(keepsake_aru): the bag holds exactly one
##     keepsake_aru_kit; CLAIM_ACTION aru:1 at 阿榆's side refused "已經領過了" (state
##     unchanged), plus claim refusals for a goal without a keepsake (aru:2, milu:1),
##     a not-yet-done keepsake goal (milu:3) and a malformed extra. The kit is placed
##     by the real `build` action (extra keepsake_aru) on an empty home cell found by
##     the 小床 search: exact message, kit -1, builds +1, objects[cell]
##     {type keepsake_aru, owner me, items {}}, resident stands unchanged; the player
##     walks onto the object cell (walk-through); a second build on a free cell is
##     refused "材料不足，需要有點歪的第一塊板 1" (no kit, state unchanged); move_object
##     to a free cell within reach (exact message, no item change), walked onto again;
##     `remove` returns exactly one kit (object gone, claimed flag stays); placed again
##     on the first cell; save + reload: object, bond_keepsakes and inventory survive,
##     the object is still walk-through; 阿榆 1 again refused (no second kit) and the
##     claim again refused. Batch-3 claims are also part of the reload probes.
##     Non-keepsake goals (米露 1, 鈴婆婆 2, 洛洛 2 / 3): no kit, no "keepsake" key in
##     their view rows, bond_keepsakes untouched (the success diff does not allow it).
##  7. Save + in-process reload into a fresh World: position / inventory / coins /
##     bonds / bond_goals / stories byte-identical (canonical: sorted String keys,
##     integral floats as ints; x/y/time compared within 1e-6), Goals.view (both
##     without and with the world state + token, i.e. including needs rows) and
##     Bond.view identical; the same probes (5 completed goals, 3 not-yet-reached
##     goals, 3 keepsake claims: claimed / no keepsake / not done, a same-day second
##     talk) give the same refusal with state unchanged in
##     both worlds. Next world day in the reloaded world: talks and a gift still work;
##     final save + reload.
## Every refusal: exact message AND whole World.state unchanged (== and canonical
## bytes). Every success: exact message AND the whole canonical state diff only under
## the listed paths (plus the actor's receipts, state.committed and the shared
## construction-undo bookkeeping state.construction). Bond records of all twelve
## residents are checked against an independent model of the published rules after
## every talk, gift and goal.
##
## NOT covered (skipped on purpose): 阿榆 aru:2::012 (free-order steps; needs 4
## planks = bench + sawmill kit + sawmill + timber, and 3 world days of talk+common
## gift), 波波 bobo:1:: (needs the jinguashi route), and the other 21 of the 28 goals,
## including the four other prerequisite kinds (fair_weather 棉棉 4, glass_crafted
## 星禾 3, festival_done 鈴婆婆 4, market_round 小栗 3; festival_done is covered by
## test_resident_goal_session.gd with a disclosed direct write). Free-order steps are
## therefore NOT exercised (aru:2::012 only appears as a stage refusal). The needs
## rows are read here from Goals.view(person, world.state, token) directly; the
## per-player snapshot field data.resident_goals is the session test's job.
## Of the twelve batch-3 keepsakes only keepsake_aru is earned here; the other eleven
## are only checked against the published table (Goals.keepsake_kind for all 28
## goals). A successful CLAIM_ACTION (pre-batch-3 completions) needs an old save and
## is therefore not exercised in this fresh-save journey.
##
## NOT preset: this file writes no state field (inventory, coins, flags, bonds,
## bond_goals, positions, time). Non-action calls: World.move_player (walking),
## World.step (waits), World.save + World.new().load_world + add_player (reloads),
## and the pure query functions of resident_bond.gd / resident_goals.gd / World
## (incl. resource / water / protected / can_stand for the tree, grass and bed-cell
## searches). The 小床, wood and fiber come only from World.act (axe, build); the
## keepsake kit only from the 阿榆 goal (resident_goal) and back from `remove`.
## Prints RESIDENT_GOAL_JOURNEY lines and RESIDENT_GOAL_JOURNEY_TESTS checks=N failures=M.

const Bond=preload("res://scripts/resident_bond.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const RG_STOVE:=Vector2i(40,34)
const RG_TALK:="resident_talk"
const RG_GIFT:="resident_gift"
const RG_TOO_FAR:="靠近一點，才能和它互動"
const RG_WALK_UP:="請走到這位居民身邊。"
const RG_REOPEN:="請重新打開關係事件。"
const RG_STEPS_MSG:="三個步驟都要做過一次。"
const RG_CHOOSE:="請先選一個做法。"
const RG_ORDER:="順序不太對。鈴婆婆說不急，再看一次圖示。"
const RG_NEED_MSG:="還不能一起做這件事：要先「%s」。"
const RG_CLUES_TEXT:="向已認識的居民詢問線索（目前 %d／3 位）"
const RG_TOTAL:=48
const RG_VILLAGE=preload("res://scripts/village.gd")
## World.gd literals: what one felled tree / one grass tile gives, the 小床 message.
const RG_TREE_YIELD:={"wood":6,"fiber":2,"sapling":1,"resin":1}
const RG_GRASS_YIELD:={"fiber":4}
const RG_BED_MSG:="放好了小床，家園又多了一點你的心意"
## Radish: 2 soup cooks (4 radish -> 4 bowls: 米露's goal 1, a gift to 米露 1, two
## liked gifts to 鈴婆婆) + 1 common gift after the reload. Wheat: 4 breads for 洛洛.
const RG_NEED:={"radish":5,"wheat":8}
const RG_SOUP_COOKS:=2
const RG_BREAD_COOKS:=4
const RG_DAY_LIMIT:=8
## Batch 3 (independent copy of the published table): resident -> the one stage whose
## goal also grants a placeable keepsake "keepsake_<resident>" (item "<kind>_kit").
const RG_KEEPSAKE_STAGES:={"aru":1,"milu":3,"bobo":1,"chacha":2,"achao":1,"mianmian":3,"xinghe":2,"lingpopo":3,"xiaoli":4,"luoluo":4,"diandian":2,"nuannuan":1}
const RG_KIT_MSG:="紀念小物也放進背包了，在家園工坊的「生活」頁可以擺到家園。"
const RG_ARU_KS:="keepsake_aru"
const RG_ARU_KIT:="keepsake_aru_kit"
const RG_ARU_KS_NAME:="有點歪的第一塊板"
const RG_NO_KEEPSAKE:="這件事的紀念收在手帳裡，沒有可以領的小物。"
const RG_REMOVE_MSG:="已拆除，建造材料完整退還"
const RG_MOVE_MSG:="搬好了！家具與箱內物品一起保存，沒有額外扣料"

var rg_pre_done:=false
var rg_started:=false
var rg_refusals:=0
var rg_ms:=0
var rg_actions0:=0
var rg_walk0:=0
var rg_time0:=0.0
var rg_model:={}
var rg_goal_model:={}
var rg_talks:=0
var rg_gifts:=0
var rg_goals:=0
var rg_days:=0
var rg_seeds_bought:=0
var rg_info:={}
var rg_keepsake_model:={}
var rg_ks_cell:=Vector2i(-1,-1)
var rg_ks_builds:=0
var rg_ks_moves:=0
var rg_ks_removes:=0

func expect(condition:bool,message:String) -> bool:
	checks+=1
	if not condition:
		failures+=1
		failed=true
		push_error("RESIDENT_GOAL_JOURNEY FAIL: "+message)
	return condition

func finish() -> void:
	var t:=float(world.state.get("time",0.0))
	var leg_actions:=actions-rg_actions0 if rg_started else 0
	var leg_walk:=walking-rg_walk0 if rg_started else 0
	var leg_time:=t-rg_time0 if rg_started else 0.0
	var ks_kits:=0
	var ks_objects:=0
	var players:Variant=world.state.get("players")
	if players is Dictionary and players.has(tok):
		var inv:Variant=players[tok].get("inventory")
		if inv is Dictionary:
			for item:String in Goals.keepsake_items():ks_kits+=int(inv.get(item,0))
	var objects:Variant=world.state.get("objects")
	if objects is Dictionary:
		for obj:Variant in objects.values():
			if obj is Dictionary and Goals.is_keepsake_kind(str(obj.get("type",""))) and str(obj.get("owner",""))==tok:ks_objects+=1
	print("RESIDENT_GOAL_JOURNEY info=%s"%JSON.stringify(rg_info))
	print("RESIDENT_GOAL_JOURNEY stats label=\"%s\" actions=%d rejections=%d walk_tiles=%d world_seconds=%.1f reloads=%d goal_leg_actions=%d goal_leg_walk_tiles=%d goal_leg_world_seconds=%.1f talks=%d gifts=%d goals_completed=%d days_crossed=%d seeds_bought=%d waters=%d keepsake_builds=%d keepsake_moves=%d keepsake_removes=%d keepsake_kits_held=%d keepsake_objects_placed=%d runtime_ms=%d reached_goal_leg=%s"%[LABEL,actions,rg_refusals,walking,t,reloads,leg_actions,leg_walk,leg_time,rg_talks,rg_gifts,rg_goals,rg_days,rg_seeds_bought,waters,rg_ks_builds,rg_ks_moves,rg_ks_removes,ks_kits,ks_objects,Time.get_ticks_msec()-rg_ms,str(rg_started)])
	print("RESIDENT_GOAL_JOURNEY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ---------------------------------------------------------------- journey

func run() -> void:
	rg_ms=Time.get_ticks_msec()
	tok=TOKEN_A
	world.add_player(TOKEN_A,"Bloom A")
	expect(not person().has("bonds") and not person().has(Goals.RECORD_KEY),"fresh world: no bonds, no bond_goals")
	expect(Goals.total()==RG_TOTAL and Goals.completed(person())==0,"%d goals published (got %d), none completed"%[RG_TOTAL,Goals.total()])
	rg_keepsake_table()
	chapter_one()
	if failed:return
	if not expect(rg_pre_done,"pre-picnic refusals ran"):return
	expect(world.state.get("picnic",false)==true,"picnic done: 洛洛 and 鈴婆婆 present")
	expect(Bond.present(world.state,"luoluo") and Bond.present(world.state,"lingpopo"),"locked_reason empty for 洛洛 and 鈴婆婆 after the picnic")
	rg_started=true
	rg_actions0=actions
	rg_walk0=walking
	rg_time0=rg_now()
	print("RESIDENT_GOAL_JOURNEY chapter one + picnic done (checks %d, actions %d, world_seconds %.1f, day %d, walk_tiles %d)"%[checks,actions,rg_now(),Bond.day(rg_now()),walking])
	rg_first_meetings()
	if failed:return
	rg_grow(RG_NEED)
	if failed:return
	rg_cook_all()
	if failed:return
	rg_milu_goal()
	if failed:return
	rg_day_round()
	if failed:return
	rg_daily()
	if failed:return
	rg_known_three()
	if failed:return
	rg_luoluo_goal()
	if failed:return
	rg_aru_bed()
	if failed:return
	rg_aru_keepsake()
	if failed:return
	rg_reload_leg()
	if failed:return
	rg_after_reload_day()

## Intercepts the reused chapter_one() right before its picnic action.
func act(action:String,target:Vector2i,extra:String="") -> Dictionary:
	if action=="picnic" and not rg_pre_done and not failed:
		rg_pre_done=true
		rg_pre_picnic()
	return super.act(action,target,extra)

func rg_pre_picnic() -> void:
	expect(world.state.get("picnic",false)!=true,"before the picnic: picnic not done yet")
	expect(Bond.locked_reason(world.state,"luoluo")==Bond.POST_LOCKED and Bond.locked_reason(world.state,"lingpopo")==Bond.BELL_LOCKED,"before the picnic: 洛洛 and 鈴婆婆 not present")
	rg_deny(Goals.ACTION,rg_cell("luoluo"),"luoluo:3:aloud:","完成渡口野餐後，洛洛才會到出貨箱附近收信。","pre-picnic: 洛洛 goal (not present yet)")
	rg_deny(Goals.ACTION,rg_cell("lingpopo"),"lingpopo:2::102","完成渡口野餐後，鈴婆婆才會到廣場北側的草地修鈴。","pre-picnic: 鈴婆婆 goal (not present yet)")
	rg_deny(RG_TALK,rg_cell("lingpopo"),"lingpopo","完成渡口野餐後，鈴婆婆才會到廣場北側的草地修鈴。","pre-picnic: talk to 鈴婆婆 (not present yet)")
	rg_deny(Goals.ACTION,rg_cell("milu"),"milu:1::","和米露的關係到「認識」之後，才能一起做這件事。","pre-picnic: 米露 goal before any talk")
	expect(not person().has("bonds") and not person().has(Goals.RECORD_KEY),"pre-picnic refusals wrote no bonds / bond_goals")

# ---------------------------------------------------------------- first meetings

func rg_first_meetings() -> void:
	expect(world.player_region(tok)=="home","goal leg starts at home")
	expect(Bond.story_count(person(),"milu")==0 and Bond.story_count(person(),"aru")==0 and Bond.story_count(person(),"lingpopo")==0 and Bond.story_count(person(),"luoluo")==0,"no story points for 米露 / 阿榆 / 鈴婆婆 / 洛洛 (no village quest done)")
	var view:=Goals.view(person())
	expect(str(view["milu"]["1"]["state"])=="locked" and str(view["lingpopo"]["2"]["state"])=="locked" and str(view["luoluo"]["3"]["state"])=="locked","goal view: the three goals are locked before any talk")
	var milu:=rg_cell("milu")
	rg_deny(Goals.ACTION,milu,"milu:1::","和米露的關係到「認識」之後，才能一起做這件事。","米露 goal before the first talk")
	rg_deny(Goals.ACTION,milu,"milu:2::","和米露的關係到「熟悉」之後，才能一起做這件事。","米露 stage 2 is still locked")
	rg_deny(Goals.ACTION,milu,"milu:x::",RG_REOPEN,"米露 goal with a non-numeric stage")
	rg_deny(Goals.ACTION,milu,"milu:1:",RG_REOPEN,"米露 goal with three fields")
	rg_deny(Goals.ACTION,milu,"nobody:1::",RG_WALK_UP,"goal for an unknown resident")
	if failed:return
	# A wrong target cell right beside 米露 (in reach).
	walk_to(milu)
	if failed:return
	var beside:=rg_beside(milu)
	if expect(rg_dist(beside)<=3.2,"beside cell %s is within reach (%.2f)"%[str(beside),rg_dist(beside)]):
		rg_deny(Goals.ACTION,beside,"milu:1::",RG_WALK_UP,"米露 goal aimed at %s beside her"%str(beside),false)
	rg_deny(Goals.ACTION,rg_cell("lingpopo"),"lingpopo:2::102","和鈴婆婆的關係到「熟悉」之後，才能一起做這件事。","鈴婆婆 goal before the first talk")
	if failed:return
	# Standing on 鈴婆婆's grass, aiming at 米露's cell: too far.
	var gap:=rg_dist(milu)
	rg_info.far_gap=snappedf(gap,0.01)
	if expect(gap>3.2,"鈴婆婆's grass is %.2f tiles from 米露 (> 3.2)"%gap):
		rg_deny(Goals.ACTION,milu,"milu:1::",RG_TOO_FAR,"米露 goal from %.2f tiles away"%gap,false)
	rg_deny(Goals.ACTION,rg_cell("luoluo"),"luoluo:3:aloud:","和洛洛的關係到「信任」之後，才能一起做這件事。","洛洛 goal before the first talk")
	if failed:return
	expect(not person().has("bonds") and not person().has(Goals.RECORD_KEY),"goal refusals wrote no bonds / bond_goals")
	rg_talk("milu")
	if failed:return
	expect(Bond.stage(person(),"milu")==1,"米露 is 認識 after the first talk")
	view=Goals.view(person())
	expect(str(view["milu"]["1"]["state"])=="open","goal view: 米露's stage-1 goal is open")
	var soup:=int(bag().get("soup",0))
	rg_info.soup_after_picnic=soup
	if soup==0:
		rg_deny(Goals.ACTION,milu,"milu:1::","還差蘿蔔湯 0／1。","米露 goal at 認識 with no soup in the bag")
	else:
		print("RESIDENT_GOAL_JOURNEY no-soup refusal skipped: the bag holds %d soup after the picnic"%soup)
	expect(not person().has(Goals.RECORD_KEY),"no bond_goals before any goal succeeds")
	rg_talk("lingpopo")
	rg_talk("luoluo")
	print("RESIDENT_GOAL_JOURNEY first meetings day=%d points=%s time=%.1f"%[Bond.day(rg_now()),JSON.stringify(rg_points()),rg_now()])

# ---------------------------------------------------------------- produce

func rg_own_plots() -> Array:
	var out:=[]
	for k in world.state.crops:
		if str(world.state.crops[k].get("owner",""))==tok:out.append(World.cell(k))
	out.sort()
	return out

func rg_growing(kind:String) -> int:
	var n:=0
	for c:Vector2i in rg_own_plots():
		if str(world.state.crops[World.key(c)].get("kind",""))==kind:n+=int(World.CROPS[kind].yield)
	return n

func rg_short(kind:String,need:Dictionary) -> int:
	return int(need[kind])-int(bag().get(kind,0))-rg_growing(kind)

func rg_grow(need:Dictionary) -> void:
	if not expect(rg_own_plots().size()>=3,"own chapter-one plots: %d"%rg_own_plots().size()):return
	var grown:={}
	for pass_index in 6:
		if failed:return
		for c:Vector2i in rg_own_plots():
			if failed:return
			if str(world.state.crops[World.key(c)].get("kind",""))!="":continue
			var kind:=""
			for want:String in ["radish","wheat"]:
				if kind.is_empty() and rg_short(want,need)>0:kind=want
			if kind.is_empty():break
			if not expect(World.crop_grows_in_season(kind,"home",c,rg_now()),"%s is in season at %.1f"%[kind,rg_now()]):return
			if int(bag().get(kind+"_seed",0))<=0:rg_buy_seed(kind)
			if failed:return
			var before:Dictionary=bag().duplicate(true)
			act("seed",c,kind)
			rg_bag_delta(before,{kind+"_seed":-1},"seed %s at %s"%[kind,str(c)])
			act("water",c)
			waters+=1
		var planted:=[]
		for c:Vector2i in rg_own_plots():
			if str(world.state.crops[World.key(c)].get("kind",""))!="":planted.append(c)
		if planted.is_empty():break
		grow(planted)
		for c:Vector2i in planted:
			if failed:return
			var plot:Dictionary=world.state.crops[World.key(c)]
			var crop_kind:=str(plot.get("kind",""))
			var before:Dictionary=bag().duplicate(true)
			var yield_n:=int(World.CROPS[crop_kind].yield)
			var expected:Dictionary={crop_kind:yield_n}
			var quality:=World.quality_crop(plot,World.has_crop_guarantee(person()))
			if not quality.is_empty():expected[quality]=1
			act("harvest",c)
			rg_bag_delta(before,expected,"harvest %s at %s"%[crop_kind,str(c)])
			grown[crop_kind]=int(grown.get(crop_kind,0))+yield_n
		var enough:=true
		for want:String in need:
			if int(bag().get(want,0))<int(need[want]):enough=false
		if enough:break
	for want:String in need:
		expect(int(bag().get(want,0))>=int(need[want]),"grew %s %d >= %d"%[want,int(bag().get(want,0)),int(need[want])])
	rg_info.grown=grown
	print("RESIDENT_GOAL_JOURNEY grown=%s seeds_bought=%d radish=%d wheat=%d time=%.1f day=%d"%[JSON.stringify(grown),rg_seeds_bought,int(bag().get("radish",0)),int(bag().get("wheat",0)),rg_now(),Bond.day(rg_now())])

func rg_buy_seed(kind:String) -> void:
	var price:=int(World.CROPS[kind].seed_price)
	if not expect(int(person().coins)>=price,"earned coins %d cover a %s seed (%d)"%[int(person().coins),kind,price]):return
	var before:Dictionary=bag().duplicate(true)
	var coins:=int(person().coins)
	act("buy",RECEIVER,kind)
	rg_bag_delta(before,{kind+"_seed":1},"buy %s seed"%kind)
	expect(int(person().coins)==coins-price,"%s seed costs exactly %d"%[kind,price])
	rg_seeds_bought+=1

func rg_cook(recipe_id:String) -> void:
	if failed:return
	var recipe:Dictionary=World.RECIPES[recipe_id]
	var before:Dictionary=bag().duplicate(true)
	act("cook",RG_STOVE,recipe_id)
	var delta:={}
	for item in recipe.ingredients:delta[str(item)]=-int(recipe.ingredients[item])
	rg_bag_delta(before,delta,"cook %s debits %s"%[recipe_id,JSON.stringify(recipe.ingredients)])
	rg_wait(float(recipe.time)+0.5)
	if failed:return
	before=bag().duplicate(true)
	act("claim_cook",RG_STOVE)
	rg_bag_delta(before,{recipe_id:int(recipe.yield)},"claim %s +%d"%[recipe_id,int(recipe.yield)])

func rg_cook_all() -> void:
	var soup0:=int(bag().get("soup",0))
	var bread0:=int(bag().get("bread",0))
	for i in RG_SOUP_COOKS:rg_cook("soup")
	for i in RG_BREAD_COOKS:rg_cook("bread")
	if failed:return
	expect(int(bag().get("soup",0))==soup0+RG_SOUP_COOKS*int(World.RECIPES.soup.yield),"cooked soup: %d"%int(bag().get("soup",0)))
	expect(int(bag().get("bread",0))==bread0+RG_BREAD_COOKS*int(World.RECIPES.bread.yield),"baked bread: %d"%int(bag().get("bread",0)))
	print("RESIDENT_GOAL_JOURNEY cooked soup=%d bread=%d radish=%d time=%.1f day=%d"%[int(bag().get("soup",0)),int(bag().get("bread",0)),int(bag().get("radish",0)),rg_now(),Bond.day(rg_now())])

# ---------------------------------------------------------------- goals

func rg_milu_goal() -> void:
	var milu:=rg_cell("milu")
	expect(Bond.stage(person(),"milu")==1 and int(bag().get("soup",0))>=1,"米露 at 認識 and soup in the bag")
	rg_deny(Goals.ACTION,milu,"milu:1:soup:",RG_REOPEN,"米露 goal with an option it does not have")
	rg_deny(Goals.ACTION,milu,"milu:1::012",RG_REOPEN,"米露 goal with steps it does not have")
	rg_goal_ok("milu",1,"","",{"soup":-1})
	if failed:return
	rg_deny(Goals.ACTION,milu,"milu:1::","〈忘記吃飯的人〉已經一起完成了，手帳可以重看。","米露 goal again")
	rg_deny(Goals.ACTION,milu,"milu:1:soup:","〈忘記吃飯的人〉已經一起完成了，手帳可以重看。","米露 goal again with another extra (done comes first)")
	rg_deny(Goals.ACTION,milu,"milu:3:soup:","和米露的關係到「信任」之後，才能一起做這件事。","米露 stage-3 goal at 認識")
	if failed:return
	# Talking and gifting still work after the goal.
	if int(rg_rec("milu").talk_day)>=Bond.day(rg_now()):
		rg_deny(RG_TALK,milu,"milu","今天已經和米露聊過了，明天再來坐坐。","talk to 米露 a second time today")
	else:
		rg_talk("milu")
	rg_gift("milu","soup")

func rg_lingpopo_goal() -> void:
	var r:="lingpopo"
	var cell:=rg_cell(r)
	expect(Bond.stage(person(),r)==2,"鈴婆婆 is exactly 熟悉 (%d points)"%Bond.points(person(),r))
	for steps:String in ["012","021","120","201","210"]:
		rg_deny(Goals.ACTION,cell,"lingpopo:2::"+steps,RG_ORDER,"鈴婆婆 bells in the wrong order "+steps)
	for steps:String in ["11","123","abc","","1102","112","1 2"]:
		rg_deny(Goals.ACTION,cell,"lingpopo:2::"+steps,RG_STEPS_MSG,"鈴婆婆 malformed steps '%s'"%steps)
	rg_deny(Goals.ACTION,cell,"lingpopo:2:soup:102",RG_REOPEN,"鈴婆婆 goal with an option it does not have")
	rg_deny(Goals.ACTION,cell,"lingpopo:2::102:0",RG_REOPEN,"鈴婆婆 goal with five fields")
	if failed:return
	rg_goal_ok(r,2,"","102",{})
	if failed:return
	rg_deny(Goals.ACTION,cell,"lingpopo:2::102","〈分不清的節拍〉已經一起完成了，手帳可以重看。","鈴婆婆 goal again")
	rg_deny(Goals.ACTION,cell,"lingpopo:2::012","〈分不清的節拍〉已經一起完成了，手帳可以重看。","鈴婆婆 goal again in a wrong order (done comes first)")
	rg_deny(Goals.ACTION,cell,"lingpopo:3:soup:","和鈴婆婆的關係到「信任」之後，才能一起做這件事。","鈴婆婆 stage-3 goal at 熟悉")

func rg_luoluo_goal() -> void:
	var r:="luoluo"
	var cell:=rg_cell(r)
	expect(Bond.stage(person(),r)==3,"洛洛 is exactly 信任 (%d points)"%Bond.points(person(),r))
	rg_expect_row(r,3,{"state":"open","choice":"","needs":[{"id":"postcard_reported","label":str(Goals.NEEDS.postcard_reported),"met":true}]},"stage 3 after the report")
	rg_deny(Goals.ACTION,cell,"luoluo:3::",RG_CHOOSE,"洛洛 goal without an option")
	rg_deny(Goals.ACTION,cell,"luoluo:3:sing:",RG_CHOOSE,"洛洛 goal with an unknown option")
	rg_deny(Goals.ACTION,cell,"luoluo:3:aloud:012",RG_REOPEN,"洛洛 goal with steps it does not have")
	if failed:return
	rg_goal_ok(r,3,"aloud","",{})
	if failed:return
	rg_deny(Goals.ACTION,cell,"luoluo:3:letter:","〈想說卻沒送出的話〉已經一起完成了，手帳可以重看。","洛洛 goal again with the other option")
	rg_deny(Goals.ACTION,cell,"luoluo:4::",rg_stage_msg(r,4),"洛洛 stage-4 goal at 信任 (batch 2 added it)")
	rg_deny(Goals.ACTION,cell,"luoluo:1::","〈寫得太小的地址〉已經一起完成了，手帳可以重看。","The first letter remains delivered")

# ---------------------------------------------------------------- prerequisites (batch 2)

## The goal row of the player's own view built WITH the world state and token
## (the form Session sends as data.resident_goals), canonical.
func rg_full_row(r:String,stage:int) -> Variant:
	var full:Dictionary=Goals.view(person(),world.state,tok)
	return rg_canon(full[r][str(stage)])

func rg_expect_row(r:String,stage:int,want:Dictionary,label:String) -> void:
	expect(var_to_bytes(rg_full_row(r,stage))==var_to_bytes(rg_canon(want)),"%s: view row %s %d == %s (got %s)"%[label,r,stage,JSON.stringify(want),JSON.stringify(rg_full_row(r,stage))])

## 洛洛「沒有地址的信」: refused while only two other residents are known, done after
## an ordinary first talk with 阿榆 makes him the third.
func rg_known_three() -> void:
	if failed:return
	var r:="luoluo"
	var cell:=rg_cell(r)
	var done_msg:="〈%s〉已經一起完成了，手帳可以重看。"%str(Goals.goal(r,2).title)
	expect(Bond.stage(person(),r)>=2 and not rg_done(r,2),"洛洛 at %d points (stage %d >= 熟悉), stage-2 goal not done"%[Bond.points(person(),r),Bond.stage(person(),r)])
	var known:=Goals.known_count(person(),r)
	rg_info.known_before_aru=known
	if not expect(known==2 and Bond.stage(person(),"milu")>=1 and Bond.stage(person(),"lingpopo")>=1 and Bond.stage(person(),"aru")==0,"before meeting 阿榆: %d residents other than 洛洛 known (米露, 鈴婆婆) stages %s"%[known,JSON.stringify(rg_stages())]):return
	var label:="%s（目前 %d 位）"%[str(Goals.NEEDS.known_three),known]
	expect(label=="認識洛洛以外的三位居民（目前 2 位）","known_three label with the count: %s"%label)
	expect(not Goals.need_met("known_three",world.state,tok),"known_three not met yet")
	rg_expect_row(r,2,{"state":"open","choice":"","needs":[{"id":"known_three","label":label,"met":false},{"id":"postcard_clues","label":RG_CLUES_TEXT%0,"met":false}]},"two known")
	rg_deny(Goals.ACTION,cell,"luoluo:2:aloud:",RG_REOPEN,"洛洛 stage-2 goal with an option it does not have (checked before needs)")
	rg_deny(Goals.ACTION,cell,"luoluo:2::012",RG_REOPEN,"洛洛 stage-2 goal with steps it does not have (checked before needs)")
	rg_deny(Goals.ACTION,cell,"luoluo:2::",RG_NEED_MSG%label,"洛洛 stage-2 goal knowing only %d residents"%known)
	# Stage 3 (reached) waits for the stage-2 report: syntax first, then the need, even for a valid option.
	var report_label:=str(Goals.NEEDS.postcard_reported)
	expect(report_label=="完成洛洛的〈沒有地址的信〉" and not Goals.need_met("postcard_reported",world.state,tok),"postcard_reported label and not met before luoluo 2")
	rg_expect_row(r,3,{"state":"open","choice":"","needs":[{"id":"postcard_reported","label":report_label,"met":false}]},"stage 3 waits for the report")
	rg_deny(Goals.ACTION,cell,"luoluo:3::",RG_CHOOSE,"洛洛 stage-3 goal without an option (checked before needs)")
	rg_deny(Goals.ACTION,cell,"luoluo:3:aloud:012",RG_REOPEN,"洛洛 stage-3 goal with steps (checked before needs)")
	rg_deny(Goals.ACTION,cell,"luoluo:3:aloud:",RG_NEED_MSG%report_label,"洛洛 stage-3 goal with a valid option before stage 2 is done")
	rg_deny(Goals.ACTION,cell,"luoluo:3:letter:",RG_NEED_MSG%report_label,"洛洛 stage-3 goal with the other valid option before stage 2 is done")
	expect(not rg_done(r,2) and not person().get(Goals.RECORD_KEY,{}).get(r,{}).has("2"),"the refused prerequisite goal wrote no record")
	if failed:return
	# 阿榆 lives at home (渡口長椅); an ordinary first talk makes him 認識.
	var aru:=rg_cell("aru")
	rg_deny(Goals.ACTION,aru,"aru:1::",rg_stage_msg("aru",1),"阿榆 stage-1 goal before the first talk")
	rg_talk("aru")
	if failed:return
	expect(Bond.stage(person(),"aru")==1,"阿榆 is 認識 after one talk (%d points)"%Bond.points(person(),"aru"))
	known=Goals.known_count(person(),r)
	expect(known==3 and Goals.need_met("known_three",world.state,tok),"three residents other than 洛洛 known now (%d)"%known)
	label="%s（目前 %d 位）"%[str(Goals.NEEDS.known_three),3]
	var clue_label:=RG_CLUES_TEXT%0
	rg_expect_row(r,2,{"state":"open","choice":"","needs":[{"id":"known_three","label":label,"met":true},{"id":"postcard_clues","label":clue_label,"met":false}]},"three known, no clues")
	rg_deny(Goals.ACTION,cell,"luoluo:2::",RG_NEED_MSG%clue_label,"洛洛 stage-2 goal with three known but no clues asked")
	if failed:return
	var address_change:=["state.players.%s.%s"%[tok,Goals.ADDRESS_KEY]]
	rg_deny(Goals.ACTION,cell,"luoluo:1::","還不能一起做這件事：要先「把洛洛的信交給正確的收件人」。","洛洛 first event waits for letter delivery")
	rg_deny(Goals.POSTCARD_CLUE_ACTION,aru,"aru","先和洛洛完成〈寫得太小的地址〉。","Interviews wait for the first letter")
	rg_ok(Goals.ADDRESS_ACTION,cell,"take","你收下了洛洛的信，可以打開信封查看線索。","Take the first letter",address_change)
	rg_ok(Goals.ADDRESS_ACTION,aru,"aru","阿榆收下了信，回去告訴洛洛吧。","Deliver the first letter",address_change)
	rg_goal_ok(r,1,"","",{})
	if failed:return
	# Ask for clues through the real action; 阿榆 stands right here after the talk.
	rg_ask_clue("aru")
	rg_ask_clue("aru") # duplicate: the field must keep counting 阿榆 once, whatever the message
	for other:String in ["milu","lingpopo"]:
		var place:Array=World.bond_place(world.state,other)
		if str(place[0])==world.player_region(tok):rg_ask_clue(other)
	if failed:return
	var clues:Array=rg_clues()
	expect(clues.count("aru")==1 and not clues.has("luoluo"),"clue field keeps 阿榆 once, never 洛洛 (%s)"%JSON.stringify(clues))
	if clues.size()<3:
		# FIXTURE: residents that are not standing in this region are seeded, not located.
		for other:String in ["aru","milu","lingpopo"]:
			if not clues.has(other):clues.append(other)
		person()[Goals.POSTCARD_CLUES_KEY]=clues
	rg_expect_row(r,2,{"state":"open","choice":"","needs":[{"id":"known_three","label":label,"met":true},{"id":"postcard_clues","label":RG_CLUES_TEXT%3,"met":true}]},"three known, three clues")
	rg_goal_ok(r,2,"","",{})
	if failed:return
	rg_expect_row(r,2,{"state":"done","choice":""},"洛洛 stage 2 done (no needs row once done)")
	rg_deny(Goals.ACTION,cell,"luoluo:2::",done_msg,"洛洛 stage-2 goal again")
	rg_reload("luoluo 2 done")
	if failed:return
	rg_expect_row(r,2,{"state":"done","choice":""},"after reload: 洛洛 stage 2 done")
	rg_deny(Goals.ACTION,rg_cell(r),"luoluo:2::",done_msg,"after reload: 洛洛 stage-2 goal again")

func rg_clues() -> Array:
	var field:Variant=person().get(Goals.POSTCARD_CLUES_KEY,[])
	var out:Array=[]
	if field is Array:out.assign(field)
	return out

## Asks `r` (standing in the player's region) for a postcard clue; the message is not pinned,
## only that the field ends up holding `r` exactly once.
func rg_ask_clue(r:String) -> void:
	if failed:return
	var cell:=rg_cell(r)
	walk_to(cell)
	if failed:return
	actions+=1
	var result:=world.act(tok,"rg-journey-%d"%actions,Goals.POSTCARD_CLUE_ACTION,cell,r)
	var clues:=rg_clues()
	expect(clues.count(r)==1,"clue action on %s: field holds it once (ok=%s '%s', %s)"%[r,str(result.ok),str(result.message),JSON.stringify(clues)])

func rg_owns_bed() -> bool:
	for obj in world.state.objects.values():
		if obj is Dictionary and str(obj.get("type",""))=="bed" and str(obj.get("owner",""))==tok:return true
	return false

## Fell trees (axe, 3 hits) or cut grass (axe, 1 hit) until `item` >= needed;
## each source gives exactly its published yield.
func rg_gather(item:String,source:String,needed:int) -> void:
	var hits:=3 if source=="tree" else 1
	var yields:Dictionary=RG_TREE_YIELD if source=="tree" else RG_GRASS_YIELD
	var guard:=0
	while not failed and int(bag().get(item,0))<needed:
		guard+=1
		if not expect(guard<=40,"gathering %s ends within 40 sources"%item):return
		var tile:=find_resource(source)
		if not expect(tile!=Vector2i(-1,-1),"a reachable %s for %s"%[source,item]):return
		var before:Dictionary=bag().duplicate(true)
		for hit in hits:
			if failed or world.resource(tile)!=source:break
			act("axe",tile)
		if failed:return
		rg_bag_delta(before,yields,"axe on %s at %s gives exactly %s"%[source,str(tile),JSON.stringify(yields)])
		expect(world.resource(tile)!=source,"%s at %s is gone after %d hits"%[source,str(tile),hits])
		if source=="tree":rg_info.trees_felled=int(rg_info.get("trees_felled",0))+1
		else:rg_info.grass_cut=int(rg_info.get("grass_cut",0))+1

## An empty home cell for the 小床: not water / protected / a resource, three or more
## tiles from every resident stand and candidate stand, no object / crop / floor /
## roof on it or its eight neighbours, standable on it and its four sides, reachable.
func rg_avoid() -> Array[Vector2i]:
	var avoid:Array[Vector2i]=[RG_STOVE,RECEIVER,FERRY]
	for r:String in Bond.RESIDENTS:
		var place:Array=World.bond_place(world.state,r)
		if str(place[0])==world.player_region(tok):avoid.append(place[1])
	for list:Array in [Bond.POST_CELLS,Bond.BELL_CELLS,Bond.RANCH_CELLS,Bond.DOCK_CELLS,RG_VILLAGE.FESTIVAL_SPOTS.values()]:
		for c:Vector2i in list:avoid.append(c)
	return avoid

func rg_bed_cell() -> Vector2i:
	var avoid:=rg_avoid()
	var origin:=Vector2i(int(person().x),int(person().y))
	for distance in range(2,25):
		for y in range(origin.y-distance,origin.y+distance+1):
			for x in range(origin.x-distance,origin.x+distance+1):
				if maxi(absi(x-origin.x),absi(y-origin.y))!=distance:continue
				var tile:=Vector2i(x,y)
				if rg_bed_ok(tile,avoid):return tile
	return Vector2i(-1,-1)

func rg_bed_ok(tile:Vector2i,avoid:Array[Vector2i]) -> bool:
	if tile.x<2 or tile.y<2 or tile.x>World.SIZE.x-3 or tile.y>World.SIZE.y-3:return false
	if world.water(tile) or world.protected(tile) or world.resource(tile)!="":return false
	for near:Vector2i in avoid:
		if Vector2(tile).distance_to(Vector2(near))<3.0:return false
	for dy in range(-1,2):
		for dx in range(-1,2):
			var k:=World.key(tile+Vector2i(dx,dy))
			for layer:String in ["objects","crops","ground","roofs"]:
				var found:Variant=world.state.get(layer)
				if found is Dictionary and found.has(k):return false
	if not world.can_stand(Vector2(tile)+Vector2(0.5,0.5)):return false
	for offset:Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
		if not world.can_stand(Vector2(tile+offset)+Vector2(0.5,0.5)):return false
	return not route(tile).is_empty()

## 阿榆「有點歪的第一塊板」: refused without a bed, a 小床 gathered for and built, refused
## for wood, then done with exactly 10 wood.
func rg_aru_bed() -> void:
	if failed:return
	var r:="aru"
	var cell:=rg_cell(r)
	var done_msg:="〈%s〉已經一起完成了，手帳可以重看。"%str(Goals.goal(r,1).title)
	var need:=int(Goals.cost(Goals.goal(r,1),"").get("wood",0))
	if not expect(Bond.stage(person(),r)==1 and not rg_done(r,1),"阿榆 is 認識 and the stage-1 goal is not done"):return
	expect(need==10 and str(World.NAMES.wood)=="木材","阿榆 stage 1 costs 10 木材 (got %d %s)"%[need,str(World.NAMES.wood)])
	var bed_wood:=int(World.BUILD.bed.wood)
	var bed_fiber:=int(World.BUILD.bed.fiber)
	expect(bed_wood==15 and bed_fiber==10 and str(World.BUILD.bed.name)=="小床","小床 costs 15 wood + 10 fiber (got %d / %d)"%[bed_wood,bed_fiber])
	if not expect(not rg_owns_bed() and not Goals.need_met("own_bed",world.state,tok),"no 小床 of one's own yet"):return
	var label:=str(Goals.NEEDS.own_bed)
	expect(label=="家園裡有一張你放的小床","own_bed label: %s"%label)
	rg_expect_row(r,1,{"state":"open","choice":"","needs":[{"id":"own_bed","label":label,"met":false}],"keepsake":rg_aru_ks_row(false)},"no bed")
	rg_deny(Goals.ACTION,cell,"aru:1:bed:",RG_REOPEN,"阿榆 stage-1 goal with an option it does not have")
	rg_deny(Goals.ACTION,cell,"aru:1::",RG_NEED_MSG%label,"阿榆 stage-1 goal without a bed (wood %d)"%int(bag().get("wood",0)))
	rg_deny(Goals.CLAIM_ACTION,cell,"aru:1","先和阿榆一起完成〈%s〉，才有紀念小物。"%str(Goals.goal(r,1).title),"claim 阿榆's keepsake before the goal is done")
	if failed:return
	rg_info.bed_materials_before={"wood":int(bag().get("wood",0)),"fiber":int(bag().get("fiber",0))}
	rg_gather("wood","tree",bed_wood)
	rg_gather("fiber","grass",bed_fiber)
	if failed:return
	var spot:=rg_bed_cell()
	if not expect(spot!=Vector2i(-1,-1),"an empty home cell for the 小床"):return
	rg_info.bed_cell=[spot.x,spot.y]
	var stands0:={}
	for resident:String in Bond.RESIDENTS:stands0[resident]=str(World.bond_place(world.state,resident))
	var before:Dictionary=bag().duplicate(true)
	var built:=act("build",spot,"bed")
	expect(str(built.get("message",""))==RG_BED_MSG,"build 小床 at %s: '%s'"%[str(spot),str(built.get("message",""))])
	rg_bag_delta(before,{"wood":-bed_wood,"fiber":-bed_fiber},"小床 costs exactly wood %d fiber %d"%[bed_wood,bed_fiber])
	var obj:Variant=world.state.objects.get(World.key(spot))
	expect(obj is Dictionary and str(obj.get("type",""))=="bed" and str(obj.get("owner",""))==tok,"objects[%s] is my 小床 (%s)"%[str(spot),JSON.stringify(obj)])
	var stands_same:=true
	for resident:String in Bond.RESIDENTS:
		if str(World.bond_place(world.state,resident))!=str(stands0[resident]):stands_same=false
	expect(stands_same,"the 小床 moved no resident's stand")
	expect(rg_owns_bed() and Goals.need_met("own_bed",world.state,tok),"own_bed met after building")
	rg_expect_row(r,1,{"state":"open","choice":"","needs":[{"id":"own_bed","label":label,"met":true}],"keepsake":rg_aru_ks_row(false)},"bed placed")
	if failed:return
	var wood:=int(bag().get("wood",0))
	rg_info.wood_after_bed=wood
	if wood<need:
		rg_deny(Goals.ACTION,cell,"aru:1::","還差木材 %d／%d。"%[wood,need],"阿榆 stage-1 goal with a bed but %d wood"%wood)
	else:
		print("RESIDENT_GOAL_JOURNEY short-wood refusal skipped: %d wood left after the 小床"%wood)
	if failed:return
	rg_gather("wood","tree",need)
	if failed:return
	expect(int(bag().get(RG_ARU_KIT,0))==0 and not Goals.keepsake_claimed(person(),RG_ARU_KS),"before 阿榆 1: no %s, keepsake not claimed"%RG_ARU_KIT)
	rg_goal_ok(r,1,"","",{"wood":-need})
	if failed:return
	expect(int(bag().get(RG_ARU_KIT,0))==1 and Goals.keepsake_claimed(person(),RG_ARU_KS),"after 阿榆 1: exactly one %s in the bag (%d), keepsake claimed"%[RG_ARU_KIT,int(bag().get(RG_ARU_KIT,0))])
	obj=world.state.objects.get(World.key(spot))
	expect(obj is Dictionary and str(obj.get("type",""))=="bed" and str(obj.get("owner",""))==tok and Goals.need_met("own_bed",world.state,tok),"the 小床 stays after the goal")
	rg_expect_row(r,1,{"state":"done","choice":"","keepsake":rg_aru_ks_row(true)},"阿榆 stage 1 done (no needs row once done, keepsake claimed)")
	rg_deny(Goals.ACTION,cell,"aru:1::",done_msg,"阿榆 stage-1 goal again (no second kit)")
	rg_reload("aru 1 done")
	if failed:return
	obj=world.state.objects.get(World.key(spot))
	expect(obj is Dictionary and str(obj.get("type",""))=="bed" and str(obj.get("owner",""))==tok and Goals.need_met("own_bed",world.state,tok),"after reload: the 小床 is still mine")
	rg_expect_row(r,1,{"state":"done","choice":"","keepsake":rg_aru_ks_row(true)},"after reload: 阿榆 stage 1 done, keepsake claimed")
	expect(int(bag().get(RG_ARU_KIT,0))==1,"after reload: still exactly one %s"%RG_ARU_KIT)
	rg_deny(Goals.ACTION,rg_cell(r),"aru:1::",done_msg,"after reload: 阿榆 stage-1 goal again")
	print("RESIDENT_GOAL_JOURNEY prerequisites done bed=%s trees=%d grass=%d wood_after_bed=%d time=%.1f day=%d"%[str(spot),int(rg_info.get("trees_felled",0)),int(rg_info.get("grass_cut",0)),wood,rg_now(),Bond.day(rg_now())])

# ---------------------------------------------------------------- keepsakes (batch 3)

## "keepsake_<r>" when (r, stage) is the goal with a placeable keepsake, else "".
func rg_kind(r:String,stage:int) -> String:
	if r=="bobo" and stage==4:return "keepsake_bobo_cart"
	if r=="nuannuan" and stage==4:return "keepsake_nuannuan_room"
	if r=="lingpopo" and stage==4:return "keepsake_lingpopo_memorial"
	if r=="xinghe" and stage==4:return "keepsake_xinghe_sign"
	if r=="achao" and stage==4:return "keepsake_achao_oar"
	if r=="aru" and stage==4:return "keepsake_aru_bird"
	return "keepsake_"+r if int(RG_KEEPSAKE_STAGES.get(r,0))==stage else ""

## The published keepsake table matches the independent copy for all 28 goals.
func rg_keepsake_table() -> void:
	expect(Goals.KEEPSAKES.size()==18 and Goals.keepsake_items().size()==18,"eighteen keepsakes published (%d)"%Goals.KEEPSAKES.size())
	var bad:=[]
	var with_kit:=0
	for r:String in Goals.GOALS:
		var stages:Dictionary=Goals.GOALS[r]
		for stage:int in stages:
			var want:=rg_kind(r,stage)
			if not want.is_empty():with_kit+=1
			if Goals.keepsake_kind(r,stage)!=want:bad.append("%s:%d"%[r,stage])
			if not want.is_empty() and not (World.BUILD.has(want) and int(World.BUILD[want].get(want+"_kit",0))==1 and World.NAMES.has(want+"_kit")):bad.append("build %s"%want)
	expect(bad.is_empty() and with_kit==18,"keepsake goals match the published table (%d with a kit, mismatches %s)"%[with_kit,JSON.stringify(bad)])

func rg_aru_ks_row(claimed:bool) -> Dictionary:
	return {"kind":RG_ARU_KS,"item":RG_ARU_KIT,"name":RG_ARU_KS_NAME,"claimed":claimed}

func rg_expect_keepsake_obj(tile:Vector2i,label:String) -> void:
	var obj:Variant=world.state.objects.get(World.key(tile))
	expect(var_to_bytes(rg_canon(obj))==var_to_bytes(rg_canon({"type":RG_ARU_KS,"owner":tok,"items":{}})),"%s: objects[%s] is my keepsake_aru (%s)"%[label,str(tile),JSON.stringify(obj)])

func rg_stands() -> Dictionary:
	var out:={}
	for resident:String in Bond.RESIDENTS:out[resident]=str(World.bond_place(world.state,resident))
	return out

## An empty home cell (nothing on it in any layer, not water / protected / a
## resource, standable on it and its four sides, away from every stand) within
## 1.0..2.4 tiles of the player, so acting on it needs no walking.
func rg_near_free(exclude:Vector2i,avoid:Array[Vector2i]) -> Vector2i:
	# 找緊鄰紀念小物那一格的空地（那一格四周原本就是空的）。紀念小物不擋路，
	# 所以這裡不套用「離居民站位三格」的限制；avoid 只排除站位本身。
	var here:=Vector2i(floori(float(person().x)),floori(float(person().y)))
	var none:Array[Vector2i]=[]
	for dy in range(-1,2):
		for dx in range(-1,2):
			var tile:=exclude+Vector2i(dx,dy)
			if tile==exclude or tile==here or tile in avoid:continue
			if rg_free_tile(tile,none):return tile
	return Vector2i(-1,-1)

func rg_free_tile(tile:Vector2i,avoid:Array[Vector2i]) -> bool:
	if tile.x<2 or tile.y<2 or tile.x>World.SIZE.x-3 or tile.y>World.SIZE.y-3:return false
	if world.water(tile) or world.protected(tile) or world.blocked(tile) or world.resource(tile)!="":return false
	for near:Vector2i in avoid:
		if Vector2(tile).distance_to(Vector2(near))<3.0:return false
	var k:=World.key(tile)
	for layer:String in ["objects","crops","ground","roofs"]:
		var found:Variant=world.state.get(layer)
		if found is Dictionary and found.has(k):return false
	if not world.can_stand(Vector2(tile)+Vector2(0.5,0.5)):return false
	for offset:Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
		if not world.can_stand(Vector2(tile+offset)+Vector2(0.5,0.5)):return false
	return true

## Walk cell by cell (World.move_player only) to an orthogonal neighbour of `tile`,
## then step onto `tile` itself: proves the cell is walk-through.
func rg_walk_onto(tile:Vector2i,label:String) -> void:
	if failed:return
	var here:=Vector2i(floori(float(person().x)),floori(float(person().y)))
	if here!=tile:
		var path:=route(tile,1.0)
		if not expect(not path.is_empty(),"%s: a route next to %s"%[label,str(tile)]):return
		path.append(tile)
		for index in range(1,path.size()):
			var direction:=Vector2(path[index]-path[index-1])
			for s in range(4):world.move_player(tok,direction,0.25/3.6)
			walking+=1
			if not expect(Vector2(float(person().x),float(person().y)).distance_to(Vector2(path[index])+Vector2(0.5,0.5))<=0.001,"%s: movement followed a passable route to %s"%[label,str(path[index])]):return
	expect(rg_dist(tile)<=0.001 and not world.blocked(tile) and world.can_stand(Vector2(tile)+Vector2(0.5,0.5)),"%s: standing on %s (walk-through, %.3f)"%[label,str(tile),rg_dist(tile)])

## 阿榆's keepsake kit, earned by the goal: claim refusals, placed with `build`,
## walked through, a kitless second build refused, moved, removed, placed again,
## saved and reloaded.
func rg_aru_keepsake() -> void:
	if failed:return
	var kind:=RG_ARU_KS
	var kit:=RG_ARU_KIT
	var cell:=rg_cell("aru")
	var done_msg:="〈%s〉已經一起完成了，手帳可以重看。"%str(Goals.goal("aru",1).title)
	var claimed_msg:="「%s」已經領過了。"%RG_ARU_KS_NAME
	var place_msg:="放好了%s，家園又多了一點你的心意"%RG_ARU_KS_NAME
	expect(var_to_bytes(rg_canon(World.BUILD.get(kind,{})))==var_to_bytes(rg_canon({"name":RG_ARU_KS_NAME,kit:1})),"World.BUILD.%s is {name, %s:1} (%s)"%[kind,kit,JSON.stringify(World.BUILD.get(kind,{}))])
	expect(str(World.NAMES.get(kit,""))==RG_ARU_KS_NAME and not World.UNDO_SOLID.has(kind),"%s is named %s and is not a solid object"%[kit,RG_ARU_KS_NAME])
	if not expect(int(bag().get(kit,0))==1 and Goals.keepsake_claimed(person(),kind),"the bag holds exactly one %s (%d) and the keepsake is claimed"%[kit,int(bag().get(kit,0))]):return
	rg_expect_row("aru",1,{"state":"done","choice":"","keepsake":rg_aru_ks_row(true)},"keepsake leg start")
	# Claims: already granted by the goal; goals without a keepsake; not done yet.
	rg_deny(Goals.CLAIM_ACTION,cell,"aru:1",claimed_msg,"claim 阿榆's keepsake again (the goal already gave it)")
	rg_deny(Goals.CLAIM_ACTION,cell,"aru:1:",RG_REOPEN,"keepsake claim with three fields")
	rg_deny(Goals.CLAIM_ACTION,cell,"aru:x",RG_REOPEN,"keepsake claim with a non-numeric stage")
	rg_deny(Goals.CLAIM_ACTION,cell,"aru:2",RG_NO_KEEPSAKE,"keepsake claim for 阿榆 stage 2 (no keepsake)")
	rg_deny(Goals.CLAIM_ACTION,cell,"milu:1",RG_WALK_UP,"米露 keepsake claim at 阿榆's cell")
	rg_deny(Goals.CLAIM_ACTION,rg_cell("milu"),"milu:1",RG_NO_KEEPSAKE,"keepsake claim for 米露's done stage-1 goal (no keepsake)")
	rg_deny(Goals.CLAIM_ACTION,rg_cell("milu"),"milu:3","先和米露一起完成〈%s〉，才有紀念小物。"%str(Goals.goal("milu",3).title),"keepsake claim for 米露 stage 3 (not done)")
	if failed:return
	# Back beside 阿榆 (渡口長椅, home) and place the kit on an empty cell nearby.
	walk_to(cell)
	if failed:return
	var avoid:=rg_avoid()
	var spot:=rg_bed_cell()
	if not expect(spot!=Vector2i(-1,-1),"an empty home cell for the keepsake"):return
	rg_ks_cell=spot
	rg_info.keepsake_cell=[spot.x,spot.y]
	var stands0:=rg_stands()
	var bag0:Dictionary=bag().duplicate(true)
	var builds0:=int(person().get("builds",0))
	var inv_path:="state.players.%s.inventory.%s"%[tok,kit]
	var builds_path:="state.players.%s.builds"%tok
	if not rg_ok("build",spot,kind,place_msg,"place 阿榆's keepsake at %s"%str(spot),[inv_path,"state.objects.%s"%World.key(spot),builds_path]):return
	rg_ks_builds+=1
	rg_bag_delta(bag0,{kit:-1},"placing the keepsake uses exactly one kit")
	expect(int(person().get("builds",0))==builds0+1,"placing the keepsake counts one build")
	rg_expect_keepsake_obj(spot,"placed")
	expect(var_to_bytes(rg_stands())==var_to_bytes(stands0),"the keepsake moved no resident's stand")
	expect(Goals.keepsake_claimed(person(),kind) and var_to_bytes(rg_canon(person().get(Goals.KEEPSAKE_KEY)))==var_to_bytes(rg_canon(rg_keepsake_model)),"placing keeps bond_keepsakes %s"%JSON.stringify(person().get(Goals.KEEPSAKE_KEY)))
	rg_expect_row("aru",1,{"state":"done","choice":"","keepsake":rg_aru_ks_row(true)},"keepsake placed")
	if failed:return
	# No kit left: a second one is refused on a free cell.
	var other:=rg_near_free(spot,avoid)
	if expect(other!=Vector2i(-1,-1),"a free cell within reach for a second keepsake"):
		rg_deny("build",other,kind,"材料不足，需要%s 1"%RG_ARU_KS_NAME,"a second keepsake at %s without a kit"%str(other))
	if failed:return
	rg_walk_onto(spot,"walk onto the placed keepsake")
	if failed:return
	# Move it to a free cell within reach.
	var dest:=rg_near_free(spot,avoid)
	if not expect(dest!=Vector2i(-1,-1),"a free cell within reach to move the keepsake to"):return
	rg_info.keepsake_moved_to=[dest.x,dest.y]
	bag0=bag().duplicate(true)
	if not rg_ok("move_object",spot,"%d,%d"%[dest.x,dest.y],RG_MOVE_MSG,"move the keepsake %s -> %s"%[str(spot),str(dest)],["state.objects.%s"%World.key(spot),"state.objects.%s"%World.key(dest)]):return
	rg_ks_moves+=1
	rg_bag_delta(bag0,{},"moving the keepsake changes no item")
	expect(not world.state.objects.has(World.key(spot)),"nothing left at %s after the move"%str(spot))
	rg_expect_keepsake_obj(dest,"moved")
	rg_walk_onto(dest,"walk onto the moved keepsake")
	if failed:return
	# Pick it up: exactly one kit back, the claimed flag stays.
	bag0=bag().duplicate(true)
	if not rg_ok("remove",dest,"",RG_REMOVE_MSG,"remove the keepsake at %s"%str(dest),[inv_path,"state.objects.%s"%World.key(dest)]):return
	rg_ks_removes+=1
	rg_bag_delta(bag0,{kit:1},"removing the keepsake returns exactly one kit")
	expect(not world.state.objects.has(World.key(dest)),"the keepsake object is gone from %s"%str(dest))
	expect(Goals.keepsake_claimed(person(),kind),"removing keeps the claimed flag")
	rg_deny(Goals.CLAIM_ACTION,rg_cell("aru"),"aru:1",claimed_msg,"claim again while the kit is back in the bag")
	if failed:return
	# Place it again on the first cell.
	bag0=bag().duplicate(true)
	builds0=int(person().get("builds",0))
	if not rg_ok("build",spot,kind,place_msg,"place 阿榆's keepsake again at %s"%str(spot),[inv_path,"state.objects.%s"%World.key(spot),builds_path]):return
	rg_ks_builds+=1
	rg_bag_delta(bag0,{kit:-1},"placing again uses exactly one kit")
	expect(int(person().get("builds",0))==builds0+1,"placing again counts one build")
	rg_expect_keepsake_obj(spot,"placed again")
	rg_reload("aru keepsake placed")
	if failed:return
	rg_expect_keepsake_obj(spot,"after reload")
	expect(int(bag().get(kit,0))==0 and Goals.keepsake_claimed(person(),kind),"after reload: no kit in the bag, keepsake still claimed")
	expect(var_to_bytes(rg_canon(person().get(Goals.KEEPSAKE_KEY)))==var_to_bytes(rg_canon(rg_keepsake_model)),"after reload: bond_keepsakes %s"%JSON.stringify(person().get(Goals.KEEPSAKE_KEY)))
	rg_expect_row("aru",1,{"state":"done","choice":"","keepsake":rg_aru_ks_row(true)},"after reload: keepsake claimed")
	rg_walk_onto(spot,"after reload: walk onto the keepsake")
	if failed:return
	rg_deny(Goals.ACTION,rg_cell("aru"),"aru:1::",done_msg,"after reload: 阿榆 stage-1 goal again (no second kit)")
	rg_deny(Goals.CLAIM_ACTION,rg_cell("aru"),"aru:1",claimed_msg,"after reload: claim 阿榆's keepsake again")
	expect(int(bag().get(kit,0))==0,"after reload: still no second kit")
	print("RESIDENT_GOAL_JOURNEY keepsake keepsake_aru placed=%s moved_to=%s builds=%d moves=%d removes=%d time=%.1f"%[str(spot),str(dest),rg_ks_builds,rg_ks_moves,rg_ks_removes,rg_now()])

## A successful goal: exact message, exact whole-bag delta, coins / bonds / every
## stage unchanged, bond_goals equals the independent record model.
func rg_goal_ok(r:String,stage:int,choice:String,steps:String,delta:Dictionary) -> void:
	if failed:return
	var entry:Dictionary=Goals.goal(r,stage)
	if not expect(not entry.is_empty(),"%s has a stage-%d goal"%[r,stage]):return
	var cost:={}
	for item:String in delta:cost[item]=-int(delta[item])
	expect(var_to_bytes(rg_canon(Goals.cost(entry,choice)))==var_to_bytes(rg_canon(cost)),"%s stage-%d published cost %s == expected %s"%[r,stage,JSON.stringify(Goals.cost(entry,choice)),JSON.stringify(cost)])
	var cell:=rg_cell(r)
	walk_to(cell)
	if failed:return
	var bag0:Dictionary=bag().duplicate(true)
	var coins0:=int(person().coins)
	var bonds0:=var_to_bytes(rg_canon(person().get("bonds",{})))
	var stages0:=rg_stages()
	var kind:=rg_kind(r,stage)
	expect(Goals.keepsake_kind(r,stage)==kind,"%s stage-%d keepsake kind '%s' (published '%s')"%[r,stage,kind,Goals.keepsake_kind(r,stage)])
	var kit:=kind+"_kit" if not kind.is_empty() else ""
	var msg:="%s：「%s」你們一起完成了〈%s〉，手帳記下紀念「%s」。"%[Bond.name_of(r),str(entry.quote[0]),str(entry.title),str(entry.keepsake)]
	if not kind.is_empty():msg+=RG_KIT_MSG
	var allowed:=["state.players.%s.%s"%[tok,Goals.RECORD_KEY]]
	for item:String in delta:allowed.append("state.players.%s.inventory.%s"%[tok,item])
	var bag_delta:Dictionary=delta.duplicate()
	if not kind.is_empty():
		allowed.append("state.players.%s.inventory.%s"%[tok,kit])
		allowed.append("state.players.%s.%s"%[tok,Goals.KEEPSAKE_KEY])
		allowed.append("state.players.%s.collection_acquired.%s"%[tok,kit])
		bag_delta[kit]=int(bag_delta.get(kit,0))+1
	var ks_before:Variant=rg_canon(person().get(Goals.KEEPSAKE_KEY))
	if not rg_ok(Goals.ACTION,cell,rg_extra(r,stage,choice,steps),msg,"%s stage-%d goal %s"%[r,stage,rg_extra(r,stage,choice,steps)],allowed):return
	rg_bag_delta(bag0,bag_delta,"%s stage-%d goal: exact bag delta %s"%[r,stage,JSON.stringify(bag_delta)])
	if kind.is_empty():
		expect(var_to_bytes(rg_canon(person().get(Goals.KEEPSAKE_KEY)))==var_to_bytes(ks_before),"%s goal (no keepsake): bond_keepsakes untouched (%s)"%[r,JSON.stringify(person().get(Goals.KEEPSAKE_KEY))])
	else:
		rg_keepsake_model[kind]=true
		expect(int(bag().get(kit,0))==1,"%s goal: exactly one %s in the bag (%d)"%[r,kit,int(bag().get(kit,0))])
		expect(bool(person().get("collection_acquired",{}).get(kit,false)),"%s goal: keepsake is recorded in the collection"%r)
		expect(var_to_bytes(rg_canon(person().get(Goals.KEEPSAKE_KEY)))==var_to_bytes(rg_canon(rg_keepsake_model)),"%s goal: player.bond_keepsakes %s == %s"%[r,JSON.stringify(person().get(Goals.KEEPSAKE_KEY)),JSON.stringify(rg_keepsake_model)])
	expect(int(person().coins)==coins0,"%s goal: coins unchanged"%r)
	expect(var_to_bytes(rg_canon(person().get("bonds",{})))==bonds0,"%s goal: bond records byte-identical (no points)"%r)
	expect(rg_stages()==stages0,"%s goal: every resident's stage unchanged %s"%[r,JSON.stringify(rg_stages())])
	rg_check_bonds("%s goal"%r)
	var own:Dictionary=rg_goal_model.get(r,{})
	own[str(stage)]=choice
	rg_goal_model[r]=own
	expect(var_to_bytes(rg_canon(person().get(Goals.RECORD_KEY)))==var_to_bytes(rg_canon(rg_goal_model)),"%s goal: player.bond_goals %s == %s"%[r,JSON.stringify(person().get(Goals.RECORD_KEY)),JSON.stringify(rg_goal_model)])
	var view:=Goals.view(person())
	expect(str(view[r][str(stage)]["state"])=="done" and str(view[r][str(stage)]["choice"])==choice,"%s goal: view says done with choice '%s'"%[r,choice])
	var row:Dictionary=view[r][str(stage)]
	if kind.is_empty():
		expect(not row.has("keepsake"),"%s stage-%d goal (no keepsake): no keepsake key in the view row (%s)"%[r,stage,JSON.stringify(row)])
	else:
		var want_ks:={"kind":kind,"item":kit,"name":str(Goals.KEEPSAKES[kind].name),"claimed":true}
		expect(var_to_bytes(rg_canon(row.get("keepsake")))==var_to_bytes(rg_canon(want_ks)),"%s stage-%d goal: view keepsake %s == %s"%[r,stage,JSON.stringify(row.get("keepsake")),JSON.stringify(want_ks)])
	expect(Goals.completed(person())==rg_goals+1,"completed count %d"%Goals.completed(person()))
	rg_goals+=1
	rg_info["goal_%s_%d"%[r,stage]]={"day":Bond.day(rg_now()),"points":Bond.points(person(),r),"world_seconds":rg_now()}
	print("RESIDENT_GOAL_JOURNEY goal %s stage %d done day=%d points=%d"%[r,stage,Bond.day(rg_now()),Bond.points(person(),r)])

# ---------------------------------------------------------------- days

## One world day's visits: talk once to each of the three, the liked gift to the
## residents whose goal is not done yet, the stage refusal while short, the goal once
## the stage is reached.
func rg_day_round() -> void:
	if failed:return
	if int(rg_rec("milu").talk_day)<Bond.day(rg_now()):rg_talk("milu")
	rg_resident_round("lingpopo",2,"","102")
	rg_resident_round("luoluo",3,"aloud","")
	print("RESIDENT_GOAL_JOURNEY day %d points=%s soup=%d bread=%d time=%.1f"%[Bond.day(rg_now()),JSON.stringify(rg_points()),int(bag().get("soup",0)),int(bag().get("bread",0)),rg_now()])

func rg_resident_round(r:String,stage:int,choice:String,steps:String) -> void:
	if failed:return
	var today:=Bond.day(rg_now())
	if int(rg_rec(r).talk_day)<today:rg_talk(r)
	if failed or rg_done(r,stage):return
	if Bond.stage(person(),r)<stage:
		rg_deny(Goals.ACTION,rg_cell(r),rg_extra(r,stage,choice,steps),rg_stage_msg(r,stage),"%s goal at %d points (stage %d < %d)"%[r,Bond.points(person(),r),Bond.stage(person(),r),stage])
		if int(rg_rec(r).gift_day)<today:
			var item:=rg_pick_gift(r)
			if item.is_empty():print("RESIDENT_GOAL_JOURNEY no gift for %s on day %d"%[r,today])
			else:rg_gift(r,item)
	if failed:return
	if Bond.stage(person(),r)>=stage:
		# 洛洛's stage-3 goal now waits for her stage-2 report: run later by rg_luoluo_goal() after rg_known_three().
		if r=="lingpopo":rg_lingpopo_goal()

func rg_daily() -> void:
	for guard in RG_DAY_LIMIT:
		if failed:return
		if rg_done("lingpopo",2) and Bond.stage(person(),"luoluo")>=3:break
		rg_next_day()
		rg_day_round()
	if failed:return
	expect(rg_done("lingpopo",2) and Bond.stage(person(),"luoluo")>=3 and not rg_done("luoluo",3),"鈴婆婆 goal done and 洛洛 at 信任 (goal not yet done) within %d world days (points %s)"%[RG_DAY_LIMIT,JSON.stringify(rg_points())])

func rg_next_day() -> void:
	if failed:return
	var day0:=Bond.day(rg_now())
	var t0:=rg_now()
	rg_wait(rg_next_midnight()-rg_now()+1.0)
	if failed:return
	rg_days+=1
	expect(Bond.day(rg_now())==day0+1,"world day %d -> %d after %.1f world seconds of World.step"%[day0,Bond.day(rg_now()),rg_now()-t0])

# ---------------------------------------------------------------- reload

func rg_probes() -> Array:
	var out:=[
		[Goals.ACTION,"milu","milu:1::","〈忘記吃飯的人〉已經一起完成了，手帳可以重看。"],
		[Goals.ACTION,"lingpopo","lingpopo:2::102","〈分不清的節拍〉已經一起完成了，手帳可以重看。"],
		[Goals.ACTION,"luoluo","luoluo:3:aloud:","〈想說卻沒送出的話〉已經一起完成了，手帳可以重看。"],
		[Goals.ACTION,"luoluo","luoluo:2::","〈沒有地址的信〉已經一起完成了，手帳可以重看。"],
		[Goals.ACTION,"aru","aru:1::","〈有點歪的第一塊板〉已經一起完成了，手帳可以重看。"],
		[Goals.ACTION,"milu","milu:3:soup:","和米露的關係到「信任」之後，才能一起做這件事。"],
		[Goals.ACTION,"lingpopo","lingpopo:3:soup:","和鈴婆婆的關係到「信任」之後，才能一起做這件事。"],
		[Goals.ACTION,"aru","aru:2::012","和阿榆的關係到「熟悉」之後，才能一起做這件事。"],
		[Goals.CLAIM_ACTION,"aru","aru:1","「%s」已經領過了。"%RG_ARU_KS_NAME],
		[Goals.CLAIM_ACTION,"milu","milu:1",RG_NO_KEEPSAKE],
		[Goals.CLAIM_ACTION,"luoluo","luoluo:4","先和洛洛一起完成〈%s〉，才有紀念小物。"%str(Goals.goal("luoluo",4).title)],
	]
	if int(rg_rec("milu").talk_day)==Bond.day(rg_now()):
		out.append([RG_TALK,"milu","milu","今天已經和米露聊過了，明天再來坐坐。"])
	return out

func rg_run_probes(label:String) -> void:
	expect(Bond.stage(person(),"milu")<3 and Bond.stage(person(),"lingpopo")<3 and Bond.stage(person(),"aru")<2,"%s: 米露 / 鈴婆婆 below 信任, 阿榆 below 熟悉 (%s)"%[label,JSON.stringify(rg_points())])
	for probe:Array in rg_probes():
		if failed:return
		rg_deny(str(probe[0]),rg_cell(str(probe[1])),str(probe[2]),str(probe[3]),"%s: %s %s"%[label,str(probe[0]),str(probe[2])])

func rg_reload_leg() -> void:
	rg_run_probes("before reload")
	if failed:return
	rg_reload("six goals done")
	if failed:return
	rg_run_probes("after reload")

func rg_after_reload_day() -> void:
	rg_next_day()
	if failed:return
	rg_talk("milu")
	rg_talk("lingpopo")
	rg_talk("luoluo")
	rg_talk("aru")
	if failed:return
	var item:=rg_pick_gift("lingpopo")
	if item.is_empty():print("RESIDENT_GOAL_JOURNEY no gift left for 鈴婆婆 after the reload")
	else:rg_gift("lingpopo",item)
	if failed:return
	expect(Goals.completed(person())==6 and rg_goals==6,"six goals completed in total (%d)"%Goals.completed(person()))
	expect(var_to_bytes(rg_canon(person().get(Goals.RECORD_KEY)))==var_to_bytes(rg_canon({"milu":{"1":""},"lingpopo":{"2":""},"luoluo":{"1":"","2":"","3":"aloud"},"aru":{"1":""}})),"bond_goals is exactly the six goals (%s)"%JSON.stringify(person().get(Goals.RECORD_KEY)))
	expect(var_to_bytes(rg_canon(person().get(Goals.KEEPSAKE_KEY)))==var_to_bytes(rg_canon({RG_ARU_KS:true})),"bond_keepsakes is exactly {keepsake_aru:true} (%s)"%JSON.stringify(person().get(Goals.KEEPSAKE_KEY)))
	rg_expect_keepsake_obj(rg_ks_cell,"final day")
	expect(int(bag().get(RG_ARU_KIT,0))==0,"final day: the only kit is placed, none in the bag")
	rg_reload("final")
	if failed:return
	rg_expect_keepsake_obj(rg_ks_cell,"after the final reload")
	expect(int(bag().get(RG_ARU_KIT,0))==0 and Goals.keepsake_claimed(person(),RG_ARU_KS),"after the final reload: kit 0, keepsake claimed")
	rg_info.final_points=rg_points()
	rg_info.final_bond_goals=person().get(Goals.RECORD_KEY)
	print("RESIDENT_GOAL_JOURNEY final day=%d points=%s bond_goals=%s time=%.1f"%[Bond.day(rg_now()),JSON.stringify(rg_points()),JSON.stringify(person().get(Goals.RECORD_KEY)),rg_now()])

## Save, load into a fresh World, re-join, compare, continue in the reloaded World.
func rg_reload(label:String) -> void:
	if failed:return
	if not expect(world.save(),label+": explicit save"):return
	var expected:Dictionary=person().duplicate(true)
	var goals_view:=var_to_bytes(rg_canon(Goals.view(person())))
	var goals_full:=var_to_bytes(rg_canon(Goals.view(person(),world.state,tok)))
	var bond_view:=var_to_bytes(rg_canon(Bond.view(person(),rg_now())))
	var t:=rg_now()
	var old_state:Variant=rg_canon(world.state)
	var reopened:=World.new()
	if not expect(reopened.load_world(save_path) and not reopened.recovered_from_backup,label+": save loads in a fresh in-process World"):return
	var diffs:=[]
	rg_diffs(old_state,rg_canon(reopened.state),"state",diffs)
	reopened.save_path=save_path
	reopened.add_player(TOKEN_A,"Bloom A")
	world=reopened
	reloads+=1
	for field:String in ["region","inventory","coins","bonds",Goals.RECORD_KEY,Goals.KEEPSAKE_KEY,"stories"]:
		expect(var_to_bytes(rg_canon(person().get(field)))==var_to_bytes(rg_canon(expected.get(field))),"%s: player %s byte-identical after reload (%s vs %s)"%[label,field,JSON.stringify(person().get(field)).left(300),JSON.stringify(expected.get(field)).left(300)])
	for axis:String in ["x","y"]:
		expect(absf(float(person().get(axis))-float(expected.get(axis)))<0.000001,"%s: player %s %.4f preserved"%[label,axis,float(person().get(axis))])
	expect(absf(rg_now()-t)<0.000001,"%s: world time %.3f preserved"%[label,rg_now()])
	expect(var_to_bytes(rg_canon(Goals.view(person())))==goals_view,"%s: goal view identical"%label)
	expect(var_to_bytes(rg_canon(Goals.view(person(),world.state,tok)))==goals_full,"%s: goal view with world state (needs rows) identical"%label)
	expect(var_to_bytes(rg_canon(Bond.view(person(),rg_now())))==bond_view,"%s: bond view identical"%label)
	rg_check_bonds(label+" reload")
	var report:=[]
	for row in diffs:report.append("%s %s"%[str(row.path),str(row.kind)])
	rg_info["reload_%d_state_diffs"%reloads]=report.slice(0,10)
	print("RESIDENT_GOAL_JOURNEY reload (%s) in-process World.new().load_world time=%.1f bond_goals=%s whole_state_diffs(info only)=%d %s"%[label,rg_now(),JSON.stringify(person().get(Goals.RECORD_KEY)),diffs.size(),JSON.stringify(report.slice(0,10))])

# ---------------------------------------------------------------- bond helpers

func rg_rec(r:String) -> Dictionary:
	if not rg_model.has(r):rg_model[r]=Bond.record(person(),r)
	return rg_model[r]

func rg_story(r:String) -> int:
	return Bond.STORY_POINTS*Bond.story_count(person(),r)

func rg_model_stage(r:String) -> int:
	return Bond.stage_for(mini(Bond.LIMIT,int(rg_rec(r).points)+rg_story(r)))

func rg_talk(r:String) -> void:
	if failed:return
	var cell:=rg_cell(r)
	walk_to(cell)
	if failed:return
	var today:=Bond.day(rg_now())
	var m:Dictionary=rg_rec(r)
	if not expect(int(m.talk_day)<today,"%s not talked to yet today (%d)"%[r,today]):return
	var before:=rg_model_stage(r)
	m.points=mini(Bond.LIMIT,int(m.points)+Bond.TALK_POINTS)
	m.talk_day=today
	var after:=rg_model_stage(r)
	var lines:Array=Bond.TALK_LINES[r]
	var msg:="%s：%s"%[Bond.name_of(r),str(lines[posmod(today,lines.size())])]
	var raised:=Bond.stage_up_text(r,before,after)
	if not raised.is_empty():msg+=" "+raised
	var bag0:Dictionary=bag().duplicate(true)
	if not rg_ok(RG_TALK,cell,r,msg,"talk to %s on day %d"%[r,today],["state.players.%s.bonds"%tok]):return
	rg_bag_delta(bag0,{},"talk to %s moves no item"%r)
	rg_check_bonds("talk to %s"%r)
	rg_talks+=1

func rg_gift(r:String,item:String) -> void:
	if failed:return
	var cell:=rg_cell(r)
	walk_to(cell)
	if failed:return
	var today:=Bond.day(rg_now())
	var m:Dictionary=rg_rec(r)
	var before:=rg_model_stage(r)
	var npc:=Bond.name_of(r)
	var item_name:=str(World.NAMES.get(item,item))
	var msg:=""
	if int(m.gift_day)>=today:
		msg="%s收下了%s。今天的心意已經記過，好感明天再算。"%[npc,item_name]
	else:
		var fav:=Bond.liked(r,item)
		m.gift_day=today
		m.points=mini(Bond.LIMIT,int(m.points)+(Bond.LIKED_POINTS if fav else Bond.GIFT_POINTS))
		msg=("%s很喜歡%s，小心地收了起來。" if fav else "%s收下了%s，向你道謝。")%[npc,item_name]
	var after:=rg_model_stage(r)
	var raised:=Bond.stage_up_text(r,before,after)
	if not raised.is_empty():msg+=" "+raised
	var bag0:Dictionary=bag().duplicate(true)
	if not rg_ok(RG_GIFT,cell,"%s:%s"%[r,item],msg,"gift %s to %s on day %d"%[item,r,today],["state.players.%s.bonds"%tok,"state.players.%s.inventory.%s"%[tok,item]]):return
	rg_bag_delta(bag0,{item:-1},"gift %s to %s takes exactly one"%[item,r])
	rg_check_bonds("gift %s to %s"%[item,r])
	rg_gifts+=1

func rg_pick_gift(r:String) -> String:
	var liked:Array=Bond.LIKES.get(r,[])
	for item:String in liked:
		if int(bag().get(item,0))>0:return item
	for item:String in Bond.COMMON_GIFTS:
		if int(bag().get(item,0))>0:return item
	return ""

## Every resident's stored record equals the model; every stage follows from it.
func rg_check_bonds(label:String) -> void:
	var got:={}
	var want:={}
	var stages_ok:=true
	for r:String in Bond.RESIDENTS:
		got[r]=Bond.record(person(),r)
		want[r]=rg_model[r] if rg_model.has(r) else {"points":0,"talk_day":-1,"gift_day":-1}
		var model_points:=mini(Bond.LIMIT,int(want[r].points)+rg_story(r))
		if Bond.stage(person(),r)!=Bond.stage_for(model_points) or Bond.points(person(),r)!=model_points:stages_ok=false
	expect(var_to_bytes(rg_canon(got))==var_to_bytes(rg_canon(want)),"%s: bond records %s == model %s"%[label,JSON.stringify(rg_canon(got)),JSON.stringify(rg_canon(want))])
	expect(stages_ok,"%s: points and stages follow the model"%label)

func rg_stages() -> Dictionary:
	var out:={}
	for r:String in Bond.RESIDENTS:out[r]=Bond.stage(person(),r)
	return out

func rg_points() -> Dictionary:
	var out:={}
	for r:String in ["milu","lingpopo","luoluo","aru"]:out[r]=Bond.points(person(),r)
	return out

func rg_done(r:String,stage:int) -> bool:
	return Goals.done(person(),r).has(stage)

func rg_extra(r:String,stage:int,choice:String,steps:String) -> String:
	return "%s:%d:%s:%s"%[r,stage,choice,steps]

func rg_stage_msg(r:String,stage:int) -> String:
	return "和%s的關係到「%s」之後，才能一起做這件事。"%[Bond.name_of(r),Bond.stage_name(stage)]

func rg_cell(r:String) -> Vector2i:
	var place:Array=World.bond_place(world.state,r)
	expect(str(place[0])==world.player_region(tok),"%s stands in the player's region (%s / %s)"%[r,str(place[0]),world.player_region(tok)])
	var spot:Vector2i=place[1]
	return spot

func rg_dist(c:Vector2i) -> float:
	return Vector2(float(person().x),float(person().y)).distance_to(Vector2(c)+Vector2(0.5,0.5))

func rg_beside(c:Vector2i) -> Vector2i:
	var best:=c+Vector2i(1,0)
	for offset:Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
		if rg_dist(c+offset)<rg_dist(best):best=c+offset
	return best

# ---------------------------------------------------------------- action helpers

## Refused with the exact message; whole World.state unchanged (== and canonical bytes).
func rg_deny(action:String,target:Vector2i,extra:String,message:String,label:String,walk:bool=true) -> void:
	if failed:return
	if walk:walk_to(target)
	if failed:return
	actions+=1
	var state_before:Dictionary=world.state.duplicate(true)
	var bytes_before:=var_to_bytes(rg_canon(world.state))
	var result:=world.act(tok,"rg-journey-%d"%actions,action,target,extra)
	expect(not result.ok and str(result.message)==message,"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var unchanged:bool=world.state==state_before and var_to_bytes(rg_canon(world.state))==bytes_before
	expect(unchanged,label+": whole world state unchanged")
	rg_refusals+=1

## A success with the exact message; the canonical state diff stays under `allowed`
## (plus the actor's receipts, state.committed and state.construction).
func rg_ok(action:String,target:Vector2i,extra:String,message:String,label:String,allowed:Array) -> bool:
	if failed:return false
	walk_to(target)
	if failed:return false
	actions+=1
	var before:Variant=rg_canon(world.state)
	var result:=world.act(tok,"rg-journey-%d"%actions,action,target,extra)
	var good:=expect(result.ok==true and str(result.message)==message,"%s: ok '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var diffs:=[]
	rg_diffs(before,rg_canon(world.state),"state",diffs)
	var prefixes:=allowed.duplicate()
	prefixes.append("state.players.%s.receipts"%tok)
	prefixes.append("state.committed")
	prefixes.append("state.construction")
	prefixes.append("state.ledger")
	var other:=[]
	for row in diffs:
		var inside:=false
		for prefix:String in prefixes:
			if str(row.path)==prefix or str(row.path).begins_with(prefix+"."):inside=true
		if not inside:other.append("%s %s"%[str(row.path),str(row.kind)])
	var clean:=expect(other.is_empty(),"%s: whole-state diff only under %s (other %s)"%[label,str(allowed),JSON.stringify(other.slice(0,5))])
	return good and clean

## Whole-bag compare (zero-count stacks ignored on both sides).
func rg_bag_delta(before:Dictionary,delta:Dictionary,label:String) -> void:
	if failed:return
	var expected:={}
	for item in before:expected[str(item)]=int(before[item])
	for item in delta:expected[str(item)]=int(expected.get(str(item),0))+int(delta[item])
	expect_same(rg_nonzero(bag()),rg_nonzero(expected),label)

func rg_nonzero(inv:Dictionary) -> Dictionary:
	var out:={}
	for item in inv:
		if int(inv[item])!=0:out[str(item)]=int(inv[item])
	return out

func rg_now() -> float:
	return float(world.state.time)

func rg_next_midnight() -> float:
	return (WEATHER.day_index(rg_now())+1.0)*WEATHER.DAY_SECONDS

func rg_wait(seconds:float,chunk:float=240.0) -> void:
	var left:=seconds
	while left>0.000001 and not failed:
		var dt:=minf(chunk,left)
		expect(world.step(dt,true),"world step %.1f"%dt)
		left-=dt

## Canonical form: String keys sorted, integral floats as ints, Vector2i as [x,y].
func rg_canon(value:Variant) -> Variant:
	if value is Dictionary:
		var keys:Array=value.keys()
		keys.sort_custom(func(x,y):return str(x)<str(y))
		var out:={}
		for k in keys:out[str(k)]=rg_canon(value[k])
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(rg_canon(item))
		return list
	if value is Vector2i:return [value.x,value.y]
	if value is float and is_finite(value) and floorf(value)==value:return int(value)
	return value

## Every difference (up to 40): {"path","kind":"changed"|"removed"|"added"}.
func rg_diffs(a:Variant,b:Variant,path:String,out:Array) -> void:
	if out.size()>=40:return
	if (a is int or a is float) and (b is int or b is float):
		if absf(float(a)-float(b))>0.000001:out.append({"path":path,"kind":"changed"})
		return
	if typeof(a)!=typeof(b):
		out.append({"path":path,"kind":"changed"})
		return
	if a is Dictionary:
		for k in a:
			if not b.has(k):out.append({"path":"%s.%s"%[path,str(k)],"kind":"removed"})
			else:rg_diffs(a[k],b[k],"%s.%s"%[path,str(k)],out)
		for k in b:
			if not a.has(k):out.append({"path":"%s.%s"%[path,str(k)],"kind":"added"})
		return
	if a is Array:
		if a.size()!=b.size():
			out.append({"path":path,"kind":"changed"})
			return
		for i in a.size():rg_diffs(a[i],b[i],"%s[%d]"%[path,i],out)
		return
	if a!=b:out.append({"path":path,"kind":"changed"})
