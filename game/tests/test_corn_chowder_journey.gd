extends "res://tests/test_flower_journey.gd"
## 玉米濃湯 (corn_chowder) natural journey: a FRESH temp world, ONE process.
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
##
## Prerequisite reuse (same pattern as test_harvest_relay_journey.gd): this file
## EXTENDS the unmodified test_flower_journey.gd only for its helpers and its
## chapter_one() (hoe/seed/water/harvest, ship, buy, gather, donate, starter,
## irrigation, stove at (40,34), soup + bread, ferry picnic). Its act() calls are
## intercepted only to insert the pre-picnic refusals right before "picnic".
## SKIPPED: chapters two to five (tea, flowers, springs, commissions).
##
## Chowder leg (World.act after World.move_player along BFS routes; World.step
## for every wait; deltas of the whole backpack and coins checked after every
## action of the leg):
##  1. pre-picnic refusals: serve/claim chowder, feed the cow (locked).
##  2. post-picnic refusals: claim with nothing served, serve with 0 chowder,
##     non-empty extra, wrong cell, cook chowder with no corn, collect from the
##     cow before feeding, feed with no feed in the bag.
##  3. feed: wheat 1 + fiber 2 cooked on the own stove (claim-early refusal),
##     claimed 4 feed, one fed to 奶糖牛 (48,35); collect-early refusal.
##  4. wait to summer (World.step); the cow produced exactly one milk meanwhile.
##  5. buy one sweet_corn seed (coins -60), till a fresh home cell, sow, water,
##     harvest-early refusal, grow (watering after midnight drying), harvest 2.
##  6. cook refused without milk ("缺少鮮奶 1"), collect the milk, re-collect refused.
##  7. queue_cook corn_chowder on the stove (corn -2, milk -1), claim-early
##     refusal, wait 30 s, claim 4; collection.meals.corn_chowder recorded.
##  8. serve_chowder at the picnic table (4 portions), re-serve refused.
##  9. a second player joins and claims one (discovery recorded), re-claim refused;
##     the cook claims one, re-claim refused; 2 portions stay on the table.
## 10. sell the claimed bowl at 小栗's stall (+30), re-sell refused.
## 11. save -> reload into a fresh World: whole canonical state equal (numbers
##     within 1e-6, and canonical JSON text equal), round continues: both
##     re-claims and a re-serve refused after the reload.
## NOT preset: this file writes no state field. PRESETS stays empty.
## Note: sowing out of season is not a refusal in world.gd (seed has no season
## gate; the crop only goes dormant), so no out-of-season sow is attempted.
## Prints CORN_CHOWDER_JOURNEY lines and CORN_CHOWDER_JOURNEY_TESTS checks=N failures=M.

const C=preload("res://scripts/community.gd")
const L=preload("res://scripts/livestock.gd")
const CHOWDER:="corn_chowder"
const TOKEN_C:="chowder-journey-b"
const STOVE:=Vector2i(40,34)
const BOARD_CELL:=Vector2i(40,29)
const MSG_TABLE_WHERE:="請到風鈴渡口的共餐桌分食。"
const MSG_RANCH_LOCKED:="完成渡口野餐後，可照料牧場家畜。"
const MSG_NO_FEED:="飼料槽已滿，或背包沒有飼料。"
const MSG_NO_PRODUCT:="目前沒有可領取的產物。"
const MSG_FED:="已替奶糖牛補充一份飼料。"
const MSG_COLLECTED:="已領取一份產物。"
const MSG_SERVE_SHORT:="需要四份玉米濃湯才能上桌。"
const MSG_SERVE_BUSY:="餐桌上還有玉米濃湯，先留給晚點回來的島民。"
const MSG_EMPTY:="玉米濃湯已經分完了。"
const MSG_CLAIMED:="你已領過這一輪，剩下的留給其他島民。"
const MSG_SERVED:="玉米濃湯上桌了。四份會留在餐桌，島民可以各領一份。"
const MSG_CLAIM_OK:="已領取一份玉米濃湯。"
const MSG_NO_STOCK:="背包裡沒有這種收成"
## Every prerequisite written directly by this file would be listed here. None.
const PRESETS:=[]

var pre_picnic_done:=false
var rejections:=0
var leg_actions:=0
var leg_time_start:=0.0
var leg_coins_start:=0
var coins_net:=0
var coin_log:=[]
var waited:=0.0
var table:=Vector2i(-1,-1)
var corn_plot:=Vector2i(-1,-1)
var leg_started:=false
var started_ms:=0

func finish() -> void:
	var t:=float(world.state.get("time",0.0))
	print("CORN_CHOWDER_JOURNEY label=\"%s\" actions=%d leg_actions=%d rejections=%d walk_tiles=%d world_seconds=%.1f leg_world_seconds=%.1f waited_seconds=%.1f reloads=%d table=%s corn_plot=%s presets=%d runtime_ms=%d"%[LABEL,actions,leg_actions,rejections,walking,t,(t-leg_time_start) if leg_started else 0.0,waited,reloads,str(table),str(corn_plot),PRESETS.size(),Time.get_ticks_msec()-started_ms])
	print("CORN_CHOWDER_JOURNEY coins start=%d net=%+d log=%s"%[leg_coins_start,coins_net,JSON.stringify(coin_log)])
	print("CORN_CHOWDER_JOURNEY presets=%s"%JSON.stringify(PRESETS))
	print("CORN_CHOWDER_JOURNEY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ---------------------------------------------------------------- journey

func run() -> void:
	started_ms=Time.get_ticks_msec()
	tok=TOKEN_A
	world.add_player(TOKEN_A,"Bloom A")
	print("CORN_CHOWDER_JOURNEY fresh world season=%s time=%.1f"%[WEATHER.season_on_day(WEATHER.day_index(now())),now()])
	expect(not bool(world.state.get("picnic",false)),"fresh world: no picnic")
	for item in [CHOWDER,"sweet_corn","sweet_corn_seed","milk","feed"]:
		expect(int(bag().get(item,0))==0,"fresh backpack holds no %s"%item)
	expect(not person().collection.meals.has(CHOWDER),"fresh: corn_chowder not discovered")
	var herd:Dictionary=world.state.get("livestock",{})
	expect(not herd.has("cow"),"fresh: no cow record")
	expect(cow_cell()==Vector2i(48,35),"cow station at (48,35) per livestock.gd")
	chapter_one()
	if failed:return
	if not expect(pre_picnic_done,"pre-picnic refusals ran"):return
	table=World.COMMUNITY.table_cell(world.state)
	if not expect(bool(world.state.picnic) and table!=World.COMMUNITY.NO_CELL,"earned picnic placed the shared table at %s"%str(table)):return
	var community:Dictionary=world.state.community
	expect(not community.has("chowder"),"picnic serves no chowder")
	leg_started=true
	leg_time_start=now()
	leg_coins_start=int(person().coins)
	print("CORN_CHOWDER_JOURNEY chapter one + picnic done (checks %d, actions %d, world_seconds %.1f, coins %d, wheat %d, fiber %d)"%[checks,actions,now(),leg_coins_start,int(bag().get("wheat",0)),int(bag().get("fiber",0))])
	after_picnic_refusals()
	if failed:return
	feed_the_cow()
	if failed:return
	wait_for_summer()
	if failed:return
	var animal:=cow()
	expect(int(animal.get("ready",-1))==1 and int(animal.get("feed",-1))==0 and float(animal.get("next",0.0))<0.0,"one feed became exactly one milk while waiting (%s)"%JSON.stringify(animal))
	grow_corn()
	if failed:return
	milk_and_cook()
	if failed:return
	serve_and_claim()
	if failed:return
	sell_leftover()
	if failed:return
	chowder_reload()
	if failed:return
	expect(int(person().coins)==leg_coins_start+coins_net,"coins reconciled: %d == start %d %+d"%[int(person().coins),leg_coins_start,coins_net])

## Intercepts the reused chapter_one() right before its picnic action.
func act(action:String,target:Vector2i,extra:String="") -> Dictionary:
	if action=="picnic" and not pre_picnic_done and not failed:
		pre_picnic_done=true
		pre_picnic()
	return super.act(action,target,extra)

func pre_picnic() -> void:
	expect(not bool(world.state.picnic),"before the picnic: picnic false")
	crefuse("serve_chowder",BOARD_CELL,"",MSG_TABLE_WHERE,"serve chowder before the picnic")
	crefuse("claim_chowder",BOARD_CELL,"",MSG_TABLE_WHERE,"claim chowder before the picnic")
	if route(cow_cell()).is_empty():
		print("CORN_CHOWDER_JOURNEY note: cow not reachable before the picnic; pre-picnic ranch refusal skipped")
		return
	crefuse("livestock_feed",cow_cell(),"cow",MSG_RANCH_LOCKED,"feed the cow before the picnic")

func after_picnic_refusals() -> void:
	crefuse("claim_chowder",table,"",MSG_EMPTY,"claim chowder before any was served")
	crefuse("serve_chowder",table,"",MSG_SERVE_SHORT,"serve with 0 chowder")
	crefuse("serve_chowder",table,"x",MSG_TABLE_WHERE,"serve with a non-empty extra")
	crefuse("serve_chowder",BOARD_CELL,"",MSG_TABLE_WHERE,"serve aimed at the board, not the table")
	crefuse("queue_cook",STOVE,CHOWDER,"缺少甜玉米 2","cook chowder with no corn and no milk")
	crefuse("livestock_collect",cow_cell(),"cow",L.NOT_ADOPTED_MESSAGE,"collect from the cow before adopting it")

# ---------------------------------------------------------------- feed + cow

func feed_the_cow() -> void:
	ensure_wheat()
	if failed:return
	gather_for_dock("fiber","grass","axe",2,1)
	if failed:return
	var recipe:Dictionary=World.RECIPES.feed
	expect(int(bag().get("wheat",0))>=1 and int(bag().get("fiber",0))>=2,"holding wheat %d / fiber %d for feed"%[int(bag().get("wheat",0)),int(bag().get("fiber",0))])
	var stove:Dictionary=world.state.objects.get(World.key(STOVE),{})
	expect(str(stove.get("type",""))=="stove" and not stove.has("job"),"own idle chapter-one stove at %s"%str(STOVE))
	play("cook",STOVE,"feed",{"wheat":-1,"fiber":-2},0)
	crefuse("claim_cook",STOVE,"","還要 %d 秒就好了"%ceili(float(recipe.time)),"claim feed before it is ready")
	wait(float(recipe.time))
	play("claim_cook",STOVE,"",{"feed":int(recipe["yield"])},0,"完成了！混合飼料 +%d"%int(recipe["yield"]))
	expect(not person().collection.meals.has("feed"),"feed is not a meal discovery")
	crefuse("livestock_feed",cow_cell(),"cow",L.NOT_ADOPTED_MESSAGE,"feed the cow before adopting it")
	if not expect(int(person().coins)>=int(L.ADOPTION_COST.cow),"earned coins %d cover the cow adoption fee"%int(person().coins)):return
	play("livestock_adopt",cow_cell(),"cow",{},-int(L.ADOPTION_COST.cow))
	play("livestock_feed",cow_cell(),"cow",{"feed":-1},0,MSG_FED)
	var animal:=cow()
	expect(int(animal.get("feed",-1))==1 and int(animal.get("ready",-1))==0,"cow trough holds 1 feed, nothing ready (%s)"%JSON.stringify(animal))
	expect(is_equal_approx(float(animal.get("next",-1.0)),now()+L.DAY*int(L.ANIMALS.cow.days)),"cow produces one day after feeding")
	crefuse("livestock_collect",cow_cell(),"cow",MSG_NO_PRODUCT,"collect right after feeding")

func ensure_wheat() -> void:
	if int(bag().get("wheat",0))>=1:return
	print("CORN_CHOWDER_JOURNEY note: no wheat left after chapter one; growing one plot for feed")
	if int(bag().get("wheat_seed",0))<1:
		play("buy",RECEIVER,"wheat",{"wheat_seed":1},-int(World.CROPS.wheat.seed_price))
	var plot:=empty_home_plot()
	if not expect(plot!=Vector2i(-1,-1),"own empty plot for feed wheat"):return
	expect(World.crop_grows_in_season("wheat","home",plot,now()),"wheat grows in the current season")
	play("seed",plot,"wheat",{"wheat_seed":-1},0)
	play("water",plot,"",{},0)
	grow([plot])
	play("harvest",plot,"",{"wheat":int(World.CROPS.wheat["yield"])},0)

func wait_for_summer() -> void:
	var season_len:=float(WEATHER.DAYS_PER_SEASON)*WEATHER.DAY_SECONDS
	var year:=season_len*4.0
	var pos:=fposmod(now(),year)
	var dt:=0.0
	# Leave at least half a season of summer for growth (210 s) and cooking.
	if pos<season_len:dt=season_len-pos+60.0
	elif pos>season_len*1.5:dt=year-pos+season_len+60.0
	if dt>0.0:wait(dt,720.0)
	expect(WEATHER.season_on_day(WEATHER.day_index(now()))=="summer","world clock reached summer (t=%.1f, waited %.1f)"%[now(),dt])

# ---------------------------------------------------------------- corn

func grow_corn() -> void:
	var price:=int(World.CROPS.sweet_corn.seed_price)
	expect(price==60,"sweet corn seed costs 60 (catalog %d)"%price)
	if not expect(int(person().coins)>=price,"earned coins %d cover a sweet corn seed (%d)"%[int(person().coins),price]):return
	play("buy",RECEIVER,"sweet_corn",{"sweet_corn_seed":1},-price,"買到一包甜玉米種子")
	corn_plot=open_farm_cell()
	if not expect(corn_plot!=Vector2i(-1,-1),"fresh home cell to till for corn"):return
	play("hoe",corn_plot,"",{},0)
	var plot:Dictionary=world.state.crops.get(World.key(corn_plot),{})
	expect(str(plot.get("kind","?"))=="" and str(plot.get("owner",""))==tok,"tilled own empty plot at %s"%str(corn_plot))
	expect(World.crop_grows_in_season("sweet_corn","home",corn_plot,now()),"sweet corn grows now (summer)")
	play("seed",corn_plot,"sweet_corn",{"sweet_corn_seed":-1},0)
	play("water",corn_plot,"",{},0)
	crefuse("harvest",corn_plot,"","還沒成熟，再等 %d 秒"%ceili(float(World.CROPS.sweet_corn.time)),"harvest corn right after sowing")
	grow([corn_plot])
	if failed:return
	expect(WEATHER.season_on_day(WEATHER.day_index(now())) in ["summer","autumn"],"corn matured in its season")
	play("harvest",corn_plot,"",{"sweet_corn":int(World.CROPS.sweet_corn["yield"])},0)
	expect(int(bag().get("sweet_corn",0))==2,"holding exactly 2 earned sweet corn")
	expect(person().collection.crops.has("sweet_corn"),"sweet corn crop discovery recorded")
	plot=world.state.crops.get(World.key(corn_plot),{})
	expect(str(plot.get("kind","?"))=="","corn plot empty after the single harvest")

# ---------------------------------------------------------------- milk + cook

func milk_and_cook() -> void:
	crefuse("queue_cook",STOVE,CHOWDER,"缺少鮮奶 1","cook chowder with 2 corn but no milk")
	play("livestock_collect",cow_cell(),"cow",{"milk":1},0,MSG_COLLECTED)
	expect(int(cow().get("ready",-1))==0,"cow emptied")
	crefuse("livestock_collect",cow_cell(),"cow",MSG_NO_PRODUCT,"collect a second milk")
	var recipe:Dictionary=World.RECIPES[CHOWDER]
	expect_same(recipe,{"name":"玉米濃湯","ingredients":{"sweet_corn":2,"milk":1},"time":30.0,"yield":4},"corn_chowder recipe as specified")
	expect(not person().collection.meals.has(CHOWDER),"chowder not discovered before the stove claim")
	var island:Dictionary=world.state.get("island_meals_discoveries",{})
	expect(not island.has(CHOWDER),"no island chowder discovery before the stove claim")
	var cooked:=int(person().get("cooked",0))
	play("queue_cook",STOVE,CHOWDER,{"sweet_corn":-2,"milk":-1},0)
	crefuse("claim_cook",STOVE,"","還要 %d 秒就好了"%ceili(float(recipe.time)),"claim chowder before it is ready")
	crefuse("serve_chowder",table,"",MSG_SERVE_SHORT,"serve while the chowder is still cooking")
	wait(float(recipe.time))
	play("claim_cook",STOVE,"",{CHOWDER:int(recipe["yield"])},0,"完成了！玉米濃湯 +%d"%int(recipe["yield"]))
	expect(int(bag().get(CHOWDER,0))==4,"holding 4 cooked chowder")
	expect(person().collection.meals.has(CHOWDER),"collection.meals.corn_chowder recorded for the cook")
	expect(int(person().get("cooked",0))==cooked+1,"cooked counter +1")
	island=world.state.get("island_meals_discoveries",{})
	var first:Dictionary=island.get(CHOWDER,{})
	expect(str(first.get("name",""))=="Bloom A","island chowder discovery credited to the cook (%s)"%JSON.stringify(first))

# ---------------------------------------------------------------- table

func serve_and_claim() -> void:
	play("serve_chowder",table,"",{CHOWDER:-4},0,MSG_SERVED)
	expect_same(world.state.community.get("chowder"),{"portions":4,"claimed":{}},"four chowder portions on the table")
	expect(World.COMMUNITY.valid(world.state),"community record valid after serving")
	crefuse("serve_chowder",table,"",MSG_SERVE_BUSY,"serve again while portions remain")
	var cook_discovery:Variant=person().get("meals_discoveries",{}).get(CHOWDER,{}).duplicate(true)
	# Second islander joins and claims.
	world.add_player(TOKEN_C,"Bowl B")
	tok=TOKEN_C
	expect(int(person().coins)==120 and int(bag().get(CHOWDER,0))==0,"second player starts fresh (120 coins, no chowder)")
	expect(not person().collection.meals.has(CHOWDER),"second player has not discovered chowder")
	play("claim_chowder",table,"",{CHOWDER:1},0,MSG_CLAIM_OK)
	expect(person().collection.meals.has(CHOWDER),"collection.meals.corn_chowder recorded for the second player on the table claim")
	var claimed:={}
	claimed[TOKEN_C]=true
	expect_same(world.state.community.chowder,{"portions":3,"claimed":claimed},"3 left after the second player's claim")
	crefuse("claim_chowder",table,"",MSG_CLAIMED,"second player claims twice")
	# The cook claims one too.
	tok=TOKEN_A
	play("claim_chowder",table,"",{CHOWDER:1},0,MSG_CLAIM_OK)
	claimed[TOKEN_A]=true
	expect_same(world.state.community.chowder,{"portions":2,"claimed":claimed},"2 left after both claims")
	expect_same(person().get("meals_discoveries",{}).get(CHOWDER,{}),cook_discovery,"cook's discovery entry unchanged by the table claim")
	crefuse("claim_chowder",table,"",MSG_CLAIMED,"cook claims twice")
	crefuse("serve_chowder",table,"",MSG_SERVE_BUSY,"serve while 2 portions remain")
	expect(World.COMMUNITY.valid(world.state),"community record valid after claims")

func sell_leftover() -> void:
	expect(int(bag().get(CHOWDER,0))==1,"cook holds the one claimed bowl")
	var price:=int(World.OTHER_SALES[CHOWDER])
	expect(price==30,"chowder sells for 30")
	play("sell",RECEIVER,CHOWDER,{CHOWDER:-1},price,"售出 1 個，獲得 %d 鈴幣"%price)
	crefuse("sell",RECEIVER,CHOWDER,MSG_NO_STOCK,"sell chowder with none left")
	expect(int(world.state.community.chowder.portions)==2,"the table still keeps 2 portions")

# ---------------------------------------------------------------- reload

func chowder_reload() -> void:
	if failed:return
	tok=TOKEN_A
	expect(world.save(),"final save")
	# 讀檔會替舊玩家補上預設欄位（例如第二位玩家還沒有的 fish_caught），所以先讀一次、
	# 再存一次，讓兩邊都是補齊後的形狀，再做「存檔→重讀」的逐欄比對。
	var warm:=World.new()
	if not expect(warm.load_world(save_path) and not warm.recovered_from_backup,"warm-up load of the final save"):return
	warm.save_path=save_path
	expect(close_diff(_canon(warm.state.community),_canon(world.state.community),"community")=="","warm-up load keeps the community record")
	for token in [TOKEN_A,TOKEN_C]:
		for field in ["region","x","y","inventory","coins","collection"]:
			expect(close_diff(_canon(warm.state.players[token].get(field)),_canon(world.state.players[token].get(field)),field)=="","%s %s kept by the warm-up load"%[token,field])
	expect(warm.save(),"warm-up save")
	var live:Variant=_canon(warm.state)
	var live_json:=canon_json(warm.state)
	var players_before:Dictionary=world.state.players.duplicate(true)
	var reopened:=World.new()
	if not expect(reopened.load_world(save_path) and not reopened.recovered_from_backup,"fresh World loads the save"):return
	var diff:=close_diff(live,_canon(reopened.state),"state")
	expect(diff=="","whole canonical state equal after reload %s"%diff)
	expect(canon_json(reopened.state)==live_json,"canonical JSON text equal after reload")
	reopened.save_path=save_path
	reopened.add_player(TOKEN_A,"Bloom A")
	reopened.add_player(TOKEN_C,"Bowl B")
	for token in [TOKEN_A,TOKEN_C]:
		var before:Dictionary=players_before[token]
		var after:Dictionary=reopened.state.players[token]
		for field in ["region","x","y","inventory","coins","collection"]:
			expect(close_diff(_canon(after.get(field)),_canon(before.get(field)),field)=="","%s %s kept after rejoin"%[token,field])
	world=reopened
	reloads+=1
	var claimed:={}
	claimed[TOKEN_C]=true
	claimed[TOKEN_A]=true
	expect_same(world.state.community.get("chowder"),{"portions":2,"claimed":claimed},"reloaded round: 2 portions, both claims kept")
	expect(World.COMMUNITY.table_cell(world.state)==table,"reloaded table cell unchanged")
	tok=TOKEN_C
	expect(person().collection.meals.has(CHOWDER),"second player's chowder discovery survives reload")
	crefuse("claim_chowder",table,"",MSG_CLAIMED,"second player claims again after reload")
	tok=TOKEN_A
	crefuse("claim_chowder",table,"",MSG_CLAIMED,"cook claims again after reload")
	# Two portions are still on the table, so the "still on the table" refusal comes first.
	crefuse("serve_chowder",table,"",MSG_SERVE_BUSY,"serve after reload")

# ---------------------------------------------------------------- helpers

func cow_cell() -> Vector2i:
	return L.ANIMALS.cow.cell

func cow() -> Dictionary:
	var herd:Dictionary=world.state.get("livestock",{})
	var animal:Dictionary=herd.get("cow",{})
	return animal

## A successful leg action: exact whole-bag delta, exact coin delta, optional message.
func play(action:String,target:Vector2i,extra:String,delta:Dictionary,coin_delta:int,message:String="") -> Dictionary:
	if failed:return {"ok":false,"message":"skipped"}
	walk_to(target)
	if failed:return {"ok":false,"message":"skipped"}
	var before:=bag().duplicate(true)
	var coins:=int(person().coins)
	var result:=act(action,target,extra)
	leg_actions+=1
	if failed:return result
	if message!="":expect(str(result.message)==message,"%s message '%s' (got '%s')"%[action,message,str(result.message)])
	expect_delta(before,delta,"%s %s at %s"%[action,extra,str(target)])
	expect(int(person().coins)==coins+coin_delta,"%s coins %d -> %d (want %+d)"%[action,coins,int(person().coins),coin_delta])
	if coin_delta!=0:
		coins_net+=coin_delta
		coin_log.append("%s %s %+d -> %d"%[action,extra,coin_delta,int(person().coins)])
	return result

## Refused with the exact message; canonical world state unchanged.
func crefuse(action:String,target:Vector2i,extra:String,message:String,label:String) -> void:
	if failed:return
	walk_to(target)
	if failed:return
	actions+=1
	leg_actions+=1
	var before:=canon_bytes(world.state)
	var snapshot:Variant=_canon(world.state)
	var result:=world.act(tok,"chowder-journey-%d"%actions,action,target,extra)
	expect(not result.ok and str(result.message)==message,"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var after:=canon_bytes(world.state)
	expect(after==before,"%s: canonical world state unchanged %s"%[label,"" if after==before else first_diff(snapshot,_canon(world.state),"state")])
	rejections+=1

func expect_delta(before:Dictionary,delta:Dictionary,label:String) -> bool:
	var keys:={}
	for k in before:keys[str(k)]=true
	for k in bag():keys[str(k)]=true
	for k in delta:keys[str(k)]=true
	var wrong:=[]
	for k in keys:
		var got:int=int(bag().get(k,0))-int(before.get(k,0))
		var want:int=int(delta.get(k,0))
		if got!=want:wrong.append("%s %+d (want %+d)"%[str(k),got,want])
	return expect(wrong.is_empty(),"%s: whole-bag delta %s %s"%[label,JSON.stringify(delta),str(wrong)])

## Fresh, tillable home cell near the chapter-one farm (not a table candidate,
## stall, board, stove or the cow station).
func open_farm_cell() -> Vector2i:
	var origin:=Vector2i(41,34)
	for distance in range(1,9):
		for y in range(origin.y-distance,origin.y+distance+1):
			for x in range(origin.x-distance,origin.x+distance+1):
				if maxi(absi(x-origin.x),absi(y-origin.y))!=distance:continue
				var c:=Vector2i(x,y)
				if farm_ok(c):return c
	return Vector2i(-1,-1)

func farm_ok(c:Vector2i) -> bool:
	if c==BOARD_CELL or c==RECEIVER or c==STOVE or c==FERRY or c==cow_cell() or c==L.collector_cell("cow"):return false
	if c in C.CANDIDATES:return false
	if not world.is_land(c) or world.water(c) or world.protected(c) or world.resource(c)!="" or world.blocked(c):return false
	var k:=World.key(c)
	for layer in ["crops","objects","ground","roofs","forest"]:
		var layer_dict:Dictionary=world.state.get(layer,{})
		if layer_dict.has(k):return false
	return not route(c).is_empty()

func now() -> float:
	return float(world.state.time)

func wait(seconds:float,chunk:float=240.0) -> void:
	var left:=seconds
	while left>0.000001 and not failed:
		var dt:=minf(chunk,left)
		expect(world.step(dt,true),"world step %.2f"%dt)
		left-=dt
		waited+=dt

func canon_bytes(v:Variant) -> PackedByteArray:
	return var_to_bytes(_canon(v))

func _canon(v:Variant) -> Variant:
	if v is Dictionary:
		var keys:Array=v.keys()
		keys.sort_custom(func(x,y):return str(x)<str(y))
		var out:={}
		for k in keys:out[str(k)]=_canon(v[k])
		return out
	if v is Array:
		var out:=[]
		for item in v:out.append(_canon(item))
		return out
	return v

## JSON round trip (numbers become floats, keys strings) then sorted keys.
func canon_json(v:Variant) -> String:
	var parsed:Variant=JSON.parse_string(JSON.stringify(v))
	return JSON.stringify(_canon(parsed))

## First differing path including Variant types (diagnostics only).
func first_diff(a:Variant,b:Variant,path:String) -> String:
	if typeof(a)!=typeof(b):return "%s: %s(%s) vs %s(%s)"%[path,type_string(typeof(a)),str(a).left(80),type_string(typeof(b)),str(b).left(80)]
	if a is Dictionary:
		if a.keys()!=b.keys():return "%s keys %s vs %s"%[path,str(a.keys()).left(200),str(b.keys()).left(200)]
		for k in a:
			var d:=first_diff(a[k],b[k],path+"."+str(k))
			if d!="":return d
		return ""
	if a is Array:
		if a.size()!=b.size():return "%s size %d vs %d"%[path,a.size(),b.size()]
		for i in a.size():
			var d:=first_diff(a[i],b[i],"%s[%d]"%[path,i])
			if d!="":return d
		return ""
	return "" if a==b else "%s: %s vs %s"%[path,str(a),str(b)]

## "" when equal; numbers compare with 1e-6 tolerance (JSON turns ints into floats).
func close_diff(a:Variant,b:Variant,path:String) -> String:
	var na:=a is int or a is float
	var nb:=b is int or b is float
	if na and nb:return "" if absf(float(a)-float(b))<=1e-6 else "%s: %s vs %s"%[path,str(a),str(b)]
	if typeof(a)!=typeof(b):return "%s: %s(%s) vs %s(%s)"%[path,type_string(typeof(a)),str(a).left(80),type_string(typeof(b)),str(b).left(80)]
	if a is Dictionary:
		if a.keys()!=b.keys():return "%s keys %s vs %s"%[path,str(a.keys()).left(200),str(b.keys()).left(200)]
		for k in a:
			var d:=close_diff(a[k],b[k],path+"."+str(k))
			if d!="":return d
		return ""
	if a is Array:
		if a.size()!=b.size():return "%s size %d vs %d"%[path,a.size(),b.size()]
		for i in a.size():
			var d:=close_diff(a[i],b[i],"%s[%d]"%[path,i])
			if d!="":return d
		return ""
	return "" if a==b else "%s: %s vs %s"%[path,str(a).left(80),str(b).left(80)]
