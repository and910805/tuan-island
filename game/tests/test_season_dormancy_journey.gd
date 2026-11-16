extends SceneTree
## T048 四季休眠與再生作物 natural journey: a FRESH temp world, ONE process.
## Acceptance (plan): 跨季不枯死，收成次數不重置.
##
## EARNED ACTIONS, ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING. A brand-new
## World and player (120 coins, starter seeds) are driven only by World.act (after
## walking with World.move_player along passable tiles, same BFS walker as
## test_flower_journey.gd) and World.step(dt,true). NO state field is written by
## this file: PRESETS stays empty. Every successful action checks its reply text,
## the whole-backpack delta and the coin delta; every refusal checks the exact
## reply and that the canonical world state is byte-identical.
##
## Growth expectations come from this file's own small model of the weather rule
## (wet until each game midnight, rainy days re-wet exposed plots, growth only while
## wet and in season, capped at maturity), compared with the world after EVERY step.
## Calendar facts used by the model: WEATHER.CYCLE / DAY_SECONDS / DAYS_PER_SEASON /
## SEASONS and World.CROP_SEASONS. No day table is hard-coded.
##
## Journey (farm next to 小栗's stall; cells S=(41,34) T=(42,34) R=(41,35)):
##  1. spring day 1: hoe 3 cells, sow+water a starter radish, buy a strawberry seed
##     (120 -> 50), tomato seed refused (50 < 55), sow+water strawberry (normal
##     reply), radish ripens at 90 s, harvest, sell (+24), buy a tomato seed (-55),
##     sow it in spring -> NEW dormant reply naming 夏, water; dormant harvest refused.
##     Strawberry ripens after exactly 210 wet seconds; harvest 1 (+2, growth ==
##     regrow_start, 2 left). Dry plot does not regrow; watered across a midnight it
##     dries and must be re-watered; ripe again after exactly 84 wet seconds. The ripe
##     berry waits; harvest 2 on the last spring evening, watered once: mid-regrow.
##  2. summer: strawberry dormant (watered, frozen); tomato wakes: water, ripe after
##     120 wet seconds, harvest 1, rain alone regrows it (60 s), sits ripe until the
##     last summer evening, harvest 2, watered once: mid-regrow.
##  3. autumn + winter: both dormant (watered, frozen), refusals unchanged; mid-winter
##     save -> fresh World load -> identical crops; journey continues on it.
##  4. spring 2: strawberry resumes from its frozen growth, harvest 3 -> plot empty.
##     summer 2: tomato resumes, harvest 3 -> plot empty. 6 + 6 from one seed each,
##     sold at the stall; coins reconciled exactly.
## Prints SEASON_DORMANCY_JOURNEY lines and SEASON_DORMANCY_JOURNEY_TESTS checks=N failures=M.

const World=preload("res://scripts/world.gd")
const WEATHER=preload("res://scripts/weather.gd")

const TOKEN:="season-dormancy-a"
const PLAYER_NAME:="Season A"
const RECEIVER:=Vector2i(43,29)
const S_CELL:=Vector2i(41,34)
const T_CELL:=Vector2i(42,34)
const R_CELL:=Vector2i(41,35)
const LABEL:="earned actions, accelerated in-process clock"
const MSG_HOE:="農田準備好了，接著選種子播種"
const MSG_WATER:="水分充足，幼苗會慢慢長大"
const MSG_DORMANT:="作物正在休眠，等到適合的季節會繼續生長。"
const MSG_POOR:="鈴幣不足，可以先把收成帶來出售"
const MSG_NO_CROP:="這裡沒有作物"
const MSG_NO_STOCK:="背包裡沒有這種收成"
## Every prerequisite written directly by this file would be listed here. None.
const PRESETS:=[]

var world:=World.new()
var tok:=TOKEN
var checks:=0
var failures:=0
var failed:=false
var actions:=0
var rejections:=0
var walking:=0
var steps:=0
var reloads:=0
var advanced:=0.0
var save_path:=""
var started_ms:=0
var coins_start:=0
var coins_net:=0
var coin_log:=[]
## World.key(cell) -> {"kind","growth","wet","remaining"}: this file's expectation.
var model:={}
var frozen_s:=-1.0
var frozen_t:=-1.0
## Items gained per crop kind through harvest actions (summary line only).
var harvested:={}

func _initialize() -> void:
	started_ms=Time.get_ticks_msec()
	var temp:=OS.get_environment("TEMP")
	if temp.is_empty():
		expect(false,"TEMP must point at an isolated directory")
		finish()
		return
	save_path=temp.path_join("season-dormancy-journey-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	if FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path+".bak"):
		expect(false,"journey save path already exists")
		finish()
		return
	world.save_path=save_path
	run()
	for file in [save_path,save_path+".bak",save_path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	finish()

func finish() -> void:
	var t:=float(world.state.get("time",0.0))
	print("SEASON_DORMANCY_JOURNEY label=\"%s\" actions=%d rejections=%d walk_tiles=%d steps=%d world_seconds=%.1f advanced_seconds=%.1f reloads=%d harvested=%s presets=%d runtime_ms=%d"%[LABEL,actions,rejections,walking,steps,t,advanced,reloads,JSON.stringify(harvested),PRESETS.size(),Time.get_ticks_msec()-started_ms])
	print("SEASON_DORMANCY_JOURNEY coins start=%d net=%+d log=%s"%[coins_start,coins_net,JSON.stringify(coin_log)])
	print("SEASON_DORMANCY_JOURNEY presets=%s"%JSON.stringify(PRESETS))
	print("SEASON_DORMANCY_JOURNEY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ---------------------------------------------------------------- journey

func run() -> void:
	world.add_player(TOKEN,PLAYER_NAME)
	print("SEASON_DORMANCY_JOURNEY fresh world season=%s time=%.1f"%[season_now(),now()])
	expect(now()==0.0,"fresh world starts at time 0")
	expect(season_now()=="spring" and my_season(0)=="spring","day 1 is spring")
	expect(int(person().coins)==120,"fresh player holds 120 coins (got %d)"%int(person().coins))
	for item in ["strawberry","tomato","strawberry_seed","tomato_seed","radish"]:
		expect(int(bag().get(item,0))==0,"fresh backpack holds no %s"%item)
	expect(int(bag().get("radish_seed",0))>=1,"fresh backpack holds a starter radish seed")
	expect(world.state.crops.is_empty(),"fresh world has no farmland")
	# Catalog facts this journey relies on (checked, never written).
	var straw:Dictionary=World.CROPS.strawberry
	var tomato:Dictionary=World.CROPS.tomato
	expect(int(straw.get("cycles",1))==3 and float(straw.get("regrow",0.0))==84.0 and float(straw.time)==210.0 and int(straw["yield"])==2,"strawberry: 210 s, regrow 84 s, 3 harvests of 2 (%s)"%JSON.stringify(straw))
	expect(int(tomato.get("cycles",1))==3 and float(tomato.get("regrow",0.0))==60.0 and float(tomato.time)==120.0 and int(tomato["yield"])==2,"tomato: 120 s, regrow 60 s, 3 harvests of 2 (%s)"%JSON.stringify(tomato))
	expect(World.regrow_start("strawberry")==126.0 and World.regrow_start("tomato")==60.0,"regrow_start = time - regrow (126 / 60)")
	expect(World.regrow_start("radish")==0.0,"non-regrowing radish restarts from 0")
	var straw_seasons:Array=World.CROP_SEASONS.strawberry
	var tomato_seasons:Array=World.CROP_SEASONS.tomato
	expect(straw_seasons==["spring"] and tomato_seasons==["summer"],"strawberry is a spring crop, tomato a summer crop")
	expect(World.crop_season_text("tomato")=="夏","tomato season text 夏")
	for d in [0,13,14,27,28,41,42,55,56,70]:
		expect(my_season(d)==WEATHER.season_on_day(float(d)),"own calendar agrees with weather.gd on day index %d"%d)
		expect(my_rains(d)==WEATHER.rains(float(d),"home"),"own rain rule agrees with weather.gd on day index %d"%d)
	coins_start=int(person().coins)
	spring_one()
	if failed:return
	summer_one()
	if failed:return
	autumn()
	if failed:return
	winter()
	if failed:return
	spring_two()
	if failed:return
	summer_two()
	if failed:return
	sell_all()

# ---------------------------------------------------------------- spring 1

func spring_one() -> void:
	play("hoe",S_CELL,"",{},0,MSG_HOE)
	model_hoe(S_CELL)
	play("hoe",T_CELL,"",{},0,MSG_HOE)
	model_hoe(T_CELL)
	play("hoe",R_CELL,"",{},0,MSG_HOE)
	model_hoe(R_CELL)
	if failed:return
	# Earn the missing coins with a starter radish.
	play("seed",R_CELL,"radish",{"radish_seed":-1},0,"種下奶白蘿蔔，記得澆水")
	model_seed(R_CELL,"radish")
	play("water",R_CELL,"",{},0,MSG_WATER)
	model_water(R_CELL)
	var straw_price:int=int(World.CROPS.strawberry.seed_price)
	var tomato_price:int=int(World.CROPS.tomato.seed_price)
	expect(straw_price==70 and tomato_price==55,"seed prices strawberry 70, tomato 55")
	play("buy",RECEIVER,"strawberry",{"strawberry_seed":1},-straw_price,"買到一包蜜香草莓種子")
	expect(int(person().coins)<tomato_price,"after the strawberry seed the player cannot afford a tomato seed (%d)"%int(person().coins))
	crefuse("buy",RECEIVER,"tomato",MSG_POOR,"buy a tomato seed with too few coins")
	play("seed",S_CELL,"strawberry",{"strawberry_seed":-1},0,"種下蜜香草莓，記得澆水")
	model_seed(S_CELL,"strawberry")
	expect_crop(S_CELL,"strawberry",0.0,3,"strawberry sown in spring")
	expect(not dormant(S_CELL),"strawberry is not dormant in spring")
	play("water",S_CELL,"",{},0,MSG_WATER)
	model_water(S_CELL)
	crefuse("harvest",S_CELL,"",unripe_msg(S_CELL),"harvest strawberry right after sowing")
	if failed:return
	advance(float(World.CROPS.radish.time))
	expect_crop(R_CELL,"radish",90.0,1,"radish ripe after 90 wet seconds")
	expect_crop(S_CELL,"strawberry",90.0,3,"strawberry grew alongside")
	play("harvest",R_CELL,"",{"radish":1},0,harvest_msg("radish",0))
	model_harvest(R_CELL)
	expect(str(crop_at(R_CELL).get("kind","?"))=="","radish plot empty after its single harvest")
	var radish_price:int=int(World.CROPS.radish.price)
	play("sell",RECEIVER,"radish",{"radish":-1},radish_price,"售出 1 個，獲得 %d 鈴幣"%radish_price)
	expect(int(person().coins)>=tomato_price,"radish sale covers the tomato seed (%d)"%int(person().coins))
	play("buy",RECEIVER,"tomato",{"tomato_seed":1},-tomato_price,"買到一包太陽番茄種子")
	play("seed",T_CELL,"tomato",{"tomato_seed":-1},0,"種下太陽番茄。現在不是它的季節，會休眠到夏季再生長。")
	model_seed(T_CELL,"tomato")
	expect_crop(T_CELL,"tomato",0.0,3,"tomato sown out of season")
	expect(dormant(T_CELL),"World.plot_dormant true for the spring tomato")
	play("water",T_CELL,"",{},0,MSG_WATER)
	model_water(T_CELL)
	crefuse("harvest",T_CELL,"",MSG_DORMANT,"harvest the dormant tomato")
	if failed:return
	# Strawberry: exactly 210 wet seconds (watered at sowing, same calendar day).
	var straw_need:=float(World.CROPS.strawberry.time)
	advance(straw_need-float(growth_of(S_CELL))-1.0)
	expect_crop(S_CELL,"strawberry",straw_need-1.0,3,"strawberry one second before ripe")
	crefuse("harvest",S_CELL,"",unripe_msg(S_CELL),"harvest strawberry one second early")
	advance(1.0)
	expect_crop(S_CELL,"strawberry",straw_need,3,"strawberry ripe after exactly 210 wet seconds")
	expect(bool(crop_at(T_CELL).get("wet",false)) and float(crop_at(T_CELL).get("growth",-1.0))==0.0,"watered spring tomato stayed at growth 0")
	expect(dormant(T_CELL),"tomato still dormant in spring")
	play("harvest",S_CELL,"",{"strawberry":2},0,harvest_msg("strawberry",2))
	model_harvest(S_CELL)
	expect_crop(S_CELL,"strawberry",World.regrow_start("strawberry"),2,"strawberry harvest 1 keeps the plant at regrow_start")
	expect(not bool(crop_at(S_CELL).get("wet",true)),"harvest leaves the soil dry")
	crefuse("harvest",S_CELL,"",unripe_msg(S_CELL),"harvest the dry regrowing strawberry")
	if failed:return
	# A dry plot does not regrow; a watered one dries at midnight and needs water again.
	expect(not my_rains(0) and not my_rains(1),"premise: day index 0 and 1 are dry days")
	advance_to(day_start(1)-40.0)
	expect_crop(S_CELL,"strawberry",126.0,2,"dry regrowing strawberry did not grow all evening")
	play("water",S_CELL,"",{},0,MSG_WATER)
	model_water(S_CELL)
	advance_to(day_start(1))
	expect_crop(S_CELL,"strawberry",166.0,2,"40 wet seconds before midnight")
	expect(not bool(crop_at(S_CELL).get("wet",true)),"soil dried at midnight")
	advance(100.0)
	expect_crop(S_CELL,"strawberry",166.0,2,"no regrowth while dry after midnight")
	crefuse("harvest",S_CELL,"",unripe_msg(S_CELL),"harvest the dried strawberry")
	play("water",S_CELL,"",{},0,MSG_WATER)
	model_water(S_CELL)
	crefuse("harvest",S_CELL,"",unripe_msg(S_CELL),"harvest the re-watered strawberry early")
	advance(straw_need-float(growth_of(S_CELL))-1.0)
	expect_crop(S_CELL,"strawberry",straw_need-1.0,2,"regrow one second before ripe")
	advance(1.0)
	expect_crop(S_CELL,"strawberry",straw_need,2,"ripe again after exactly 40+44 = 84 wet seconds")
	if failed:return
	# The ripe berry waits (ripe crops never rot); harvest 2 on the last spring evening.
	var last_spring:=WEATHER.DAYS_PER_SEASON-1
	advance_to(day_start(last_spring)+1380.0)
	expect(season_now()=="spring","still spring on day index %d"%day_now())
	expect_crop(S_CELL,"strawberry",straw_need,2,"ripe strawberry waited through the spring rains")
	expect_crop(T_CELL,"tomato",0.0,3,"spring tomato still at 0 after all spring rains")
	expect(dormant(T_CELL),"tomato dormant all spring")
	play("harvest",S_CELL,"",{"strawberry":2},0,harvest_msg("strawberry",1))
	model_harvest(S_CELL)
	expect_crop(S_CELL,"strawberry",126.0,1,"strawberry harvest 2: one harvest left")
	play("water",S_CELL,"",{},0,MSG_WATER)
	model_water(S_CELL)
	advance_to(day_start(WEATHER.DAYS_PER_SEASON))
	expect(season_now()=="summer","clock reached summer (t=%.1f)"%now())
	expect_crop(S_CELL,"strawberry",186.0,1,"strawberry mid-regrow (60 wet seconds) at the end of spring")
	frozen_s=float(growth_of(S_CELL))

# ---------------------------------------------------------------- summer 1

func summer_one() -> void:
	expect_frozen(S_CELL,"strawberry",frozen_s,1,"summer start")
	crefuse("harvest",S_CELL,"",MSG_DORMANT,"harvest the summer-dormant strawberry")
	expect(not dormant(T_CELL),"tomato wakes in summer")
	expect(not my_rains(day_now()),"premise: first summer day is dry")
	var tomato_need:=float(World.CROPS.tomato.time)
	play("water",T_CELL,"",{},0,MSG_WATER)
	model_water(T_CELL)
	crefuse("harvest",T_CELL,"",unripe_msg(T_CELL),"harvest the waking tomato")
	advance(tomato_need-1.0)
	expect_crop(T_CELL,"tomato",tomato_need-1.0,3,"summer tomato one second before ripe")
	crefuse("harvest",T_CELL,"",unripe_msg(T_CELL),"harvest tomato one second early")
	advance(1.0)
	expect_crop(T_CELL,"tomato",tomato_need,3,"tomato ripe after exactly 120 summer wet seconds")
	play("harvest",T_CELL,"",{"tomato":2},0,harvest_msg("tomato",2))
	model_harvest(T_CELL)
	expect_crop(T_CELL,"tomato",World.regrow_start("tomato"),2,"tomato harvest 1 keeps the plant at regrow_start")
	# Water the dormant strawberry in summer: it must not grow.
	play("water",S_CELL,"",{},0,MSG_WATER)
	model_water(S_CELL)
	if failed:return
	# Rain alone regrows the tomato on the next rainy summer day.
	var rain_day:=next_rainy_day(day_now()+1)
	expect(rain_day>day_now() and my_season(rain_day)=="summer","a rainy summer day follows (day index %d)"%rain_day)
	advance_to(day_start(rain_day))
	expect_crop(T_CELL,"tomato",60.0,2,"unwatered tomato did not regrow before the rain")
	expect(bool(crop_at(T_CELL).get("wet",false)),"rain wet the tomato at midnight")
	expect_frozen(S_CELL,"strawberry",frozen_s,1,"summer, after watering and rain")
	crefuse("harvest",S_CELL,"",MSG_DORMANT,"harvest the watered summer-dormant strawberry")
	advance(float(World.CROPS.tomato.regrow)-1.0)
	expect_crop(T_CELL,"tomato",tomato_need-1.0,2,"rain-wet tomato one second before ripe")
	advance(1.0)
	expect_crop(T_CELL,"tomato",tomato_need,2,"tomato ripe again after exactly 60 rain-wet seconds")
	if failed:return
	var last_summer:=2*WEATHER.DAYS_PER_SEASON-1
	advance_to(day_start(last_summer)+1410.0)
	expect(season_now()=="summer","still summer on day index %d"%day_now())
	expect_crop(T_CELL,"tomato",tomato_need,2,"ripe tomato waited through summer")
	expect_frozen(S_CELL,"strawberry",frozen_s,1,"end of summer")
	play("harvest",T_CELL,"",{"tomato":2},0,harvest_msg("tomato",1))
	model_harvest(T_CELL)
	expect_crop(T_CELL,"tomato",60.0,1,"tomato harvest 2: one harvest left")
	play("water",T_CELL,"",{},0,MSG_WATER)
	model_water(T_CELL)
	advance_to(day_start(2*WEATHER.DAYS_PER_SEASON))
	expect(season_now()=="autumn","clock reached autumn (t=%.1f)"%now())
	expect_crop(T_CELL,"tomato",90.0,1,"tomato mid-regrow (30 wet seconds) at the end of summer")
	frozen_t=float(growth_of(T_CELL))

# ---------------------------------------------------------------- autumn / winter

func both_frozen_season(label:String) -> void:
	expect_frozen(S_CELL,"strawberry",frozen_s,1,label+" start")
	expect_frozen(T_CELL,"tomato",frozen_t,1,label+" start")
	crefuse("harvest",S_CELL,"",MSG_DORMANT,"harvest dormant strawberry in "+label)
	crefuse("harvest",T_CELL,"",MSG_DORMANT,"harvest dormant tomato in "+label)
	play("water",S_CELL,"",{},0,MSG_WATER)
	model_water(S_CELL)
	play("water",T_CELL,"",{},0,MSG_WATER)
	model_water(T_CELL)
	advance(float(WEATHER.DAY_SECONDS))
	expect_frozen(S_CELL,"strawberry",frozen_s,1,label+" after watering + one day")
	expect_frozen(T_CELL,"tomato",frozen_t,1,label+" after watering + one day")

func autumn() -> void:
	both_frozen_season("autumn")
	if failed:return
	advance_to(day_start(3*WEATHER.DAYS_PER_SEASON))
	expect(season_now()=="winter","clock reached winter (t=%.1f)"%now())

func winter() -> void:
	both_frozen_season("winter")
	if failed:return
	advance_to(day_start(3*WEATHER.DAYS_PER_SEASON+7)+700.0)
	expect(season_now()=="winter","mid-winter save point (t=%.1f)"%now())
	reload_mid_winter()
	if failed:return
	expect_frozen(S_CELL,"strawberry",frozen_s,1,"after reload")
	expect_frozen(T_CELL,"tomato",frozen_t,1,"after reload")
	crefuse("harvest",S_CELL,"",MSG_DORMANT,"harvest dormant strawberry after reload")
	crefuse("harvest",T_CELL,"",MSG_DORMANT,"harvest dormant tomato after reload")
	play("water",S_CELL,"",{},0,MSG_WATER)
	model_water(S_CELL)
	advance(float(WEATHER.DAY_SECONDS))
	expect_frozen(S_CELL,"strawberry",frozen_s,1,"reloaded world, watered, one winter day later")
	advance_to(day_start(4*WEATHER.DAYS_PER_SEASON))
	expect(season_now()=="spring","clock reached the next spring (t=%.1f)"%now())

func reload_mid_winter() -> void:
	expect(world.save(),"explicit mid-winter save")
	var crops_json:=canon_json(world.state.crops)
	var crops_live:Variant=_canon(JSON.parse_string(JSON.stringify(world.state.crops)))
	var player_before:Dictionary=world.state.players[TOKEN].duplicate(true)
	var time_before:=now()
	var reopened:=World.new()
	if not expect(reopened.load_world(save_path) and not reopened.recovered_from_backup,"fresh World loads the mid-winter save"):return
	expect(float(reopened.state.time)==time_before,"reloaded time %.1f == %.1f"%[float(reopened.state.time),time_before])
	var diff:=close_diff(crops_live,_canon(reopened.state.crops),"crops")
	expect(diff=="","reloaded crop layer equal %s"%diff)
	expect(canon_json(reopened.state.crops)==crops_json,"reloaded crop layer canonical JSON equal")
	for c in [S_CELL,T_CELL]:
		var k:String=World.key(c)
		var a:Dictionary=world.state.crops.get(k,{})
		var b:Dictionary=reopened.state.crops.get(k,{})
		for field in ["kind","growth","wet","remaining","owner"]:
			expect(close_diff(a.get(field),b.get(field),field)=="","%s %s kept by reload (%s vs %s)"%[k,field,str(a.get(field)),str(b.get(field))])
	reopened.add_player(TOKEN,PLAYER_NAME)
	var after:Dictionary=reopened.state.players[TOKEN]
	for field in ["region","x","y","inventory","coins","collection","harvests"]:
		expect(close_diff(_canon(after.get(field)),_canon(player_before.get(field)),field)=="","player %s kept after reload + rejoin"%field)
	if failed:return
	world=reopened
	reloads+=1
	expect(world.save_path==save_path,"reloaded world keeps saving to the temp save")

# ---------------------------------------------------------------- spring 2 / summer 2

func spring_two() -> void:
	expect(not dormant(S_CELL),"strawberry wakes in the next spring")
	expect_crop(S_CELL,"strawberry",frozen_s,1,"strawberry resumes from its frozen growth")
	expect(dormant(T_CELL),"tomato dormant in the next spring")
	var straw_need:=float(World.CROPS.strawberry.time)
	var left:=straw_need-frozen_s
	play("water",S_CELL,"",{},0,MSG_WATER)
	model_water(S_CELL)
	crefuse("harvest",S_CELL,"",unripe_msg(S_CELL),"harvest the waking strawberry")
	if left>1.0:advance(left-1.0)
	expect_crop(S_CELL,"strawberry",straw_need-1.0,1,"strawberry one second before its third ripening")
	crefuse("harvest",S_CELL,"",unripe_msg(S_CELL),"harvest strawberry one second early (spring 2)")
	advance(1.0)
	expect_crop(S_CELL,"strawberry",straw_need,1,"strawberry ripe after exactly the outstanding %.1f wet seconds"%left)
	play("harvest",S_CELL,"",{"strawberry":2},0,harvest_msg("strawberry",0))
	model_harvest(S_CELL)
	var plot:=crop_at(S_CELL)
	expect(str(plot.get("kind","?"))=="" and float(plot.get("growth",-1.0))==0.0 and int(plot.get("remaining",-1))==0,"third strawberry harvest empties the plot (%s)"%JSON.stringify(plot))
	crefuse("harvest",S_CELL,"",MSG_NO_CROP,"harvest the emptied strawberry plot")
	expect(int(bag().get("strawberry",0))==6,"6 strawberries from one seed (got %d)"%int(bag().get("strawberry",0)))
	expect_frozen(T_CELL,"tomato",frozen_t,1,"spring 2 start")
	play("water",T_CELL,"",{},0,MSG_WATER)
	model_water(T_CELL)
	advance(float(WEATHER.DAY_SECONDS))
	expect_frozen(T_CELL,"tomato",frozen_t,1,"spring 2, watered, one day later")
	crefuse("harvest",T_CELL,"",MSG_DORMANT,"harvest dormant tomato in spring 2")
	if failed:return
	advance_to(day_start(5*WEATHER.DAYS_PER_SEASON))
	expect(season_now()=="summer","clock reached the next summer (t=%.1f)"%now())

func summer_two() -> void:
	expect(not dormant(T_CELL),"tomato wakes in the next summer")
	expect_crop(T_CELL,"tomato",frozen_t,1,"tomato resumes from its frozen growth")
	var need:=float(World.CROPS.tomato.time)
	var left:=need-frozen_t
	play("water",T_CELL,"",{},0,MSG_WATER)
	model_water(T_CELL)
	if left>1.0:advance(left-1.0)
	expect_crop(T_CELL,"tomato",need-1.0,1,"tomato one second before its third ripening")
	crefuse("harvest",T_CELL,"",unripe_msg(T_CELL),"harvest tomato one second early (summer 2)")
	advance(1.0)
	expect_crop(T_CELL,"tomato",need,1,"tomato ripe after exactly the outstanding %.1f wet seconds"%left)
	play("harvest",T_CELL,"",{"tomato":2},0,harvest_msg("tomato",0))
	model_harvest(T_CELL)
	var plot:=crop_at(T_CELL)
	expect(str(plot.get("kind","?"))=="" and float(plot.get("growth",-1.0))==0.0 and int(plot.get("remaining",-1))==0,"third tomato harvest empties the plot (%s)"%JSON.stringify(plot))
	crefuse("harvest",T_CELL,"",MSG_NO_CROP,"harvest the emptied tomato plot")
	expect(int(bag().get("tomato",0))==6,"6 tomatoes from one seed (got %d)"%int(bag().get("tomato",0)))
	expect(int(person().get("harvests",0))==7,"harvest counter: 1 radish + 3 strawberry + 3 tomato (got %d)"%int(person().get("harvests",0)))
	expect(person().collection.crops.has("strawberry") and person().collection.crops.has("tomato"),"strawberry and tomato discoveries recorded")

func sell_all() -> void:
	var straw_price:int=int(World.CROPS.strawberry.price)
	var tomato_price:int=int(World.CROPS.tomato.price)
	expect(straw_price==36 and tomato_price==28,"sale prices strawberry 36, tomato 28")
	play("sell",RECEIVER,"strawberry",{"strawberry":-6},6*straw_price,"售出 6 個，獲得 %d 鈴幣"%(6*straw_price))
	play("sell",RECEIVER,"tomato",{"tomato":-6},6*tomato_price,"售出 6 個，獲得 %d 鈴幣"%(6*tomato_price))
	crefuse("sell",RECEIVER,"strawberry",MSG_NO_STOCK,"sell strawberries with none left")
	crefuse("sell",RECEIVER,"tomato",MSG_NO_STOCK,"sell tomatoes with none left")
	var want:int=120-70+24-55+6*36+6*28
	expect(want==403,"ledger arithmetic 403")
	expect(int(person().coins)==want and int(person().coins)==coins_start+coins_net,"coins reconciled: %d == %d == start %d %+d"%[int(person().coins),want,coins_start,coins_net])

# ---------------------------------------------------------------- model

func my_rains(day:int) -> bool:
	return str(WEATHER.CYCLE[posmod(day,WEATHER.CYCLE.size())])=="rainy"

func my_season(day:int) -> String:
	var year_days:int=WEATHER.DAYS_PER_SEASON*WEATHER.SEASONS.size()
	var index:int=int(floorf(float(posmod(day,year_days))/float(WEATHER.DAYS_PER_SEASON)))
	return str(WEATHER.SEASONS[index])

func next_rainy_day(from_day:int) -> int:
	for d in range(from_day,from_day+WEATHER.CYCLE.size()+1):
		if my_rains(d):return d
	return -1

func model_hoe(c:Vector2i) -> void:
	model[World.key(c)]={"kind":"","growth":0.0,"wet":false,"remaining":0}

func model_seed(c:Vector2i,kind:String) -> void:
	var m:Dictionary=model[World.key(c)]
	m.kind=kind
	m.growth=0.0
	m.remaining=int(World.CROPS[kind].get("cycles",1))

func model_water(c:Vector2i) -> void:
	var m:Dictionary=model[World.key(c)]
	m.wet=true

func model_harvest(c:Vector2i) -> void:
	var m:Dictionary=model[World.key(c)]
	var kind:String=str(m.kind)
	var crop:Dictionary=World.CROPS[kind]
	harvested[kind]=int(harvested.get(kind,0))+int(crop["yield"])
	m.remaining=int(m.remaining)-1
	if int(m.remaining)<=0:
		m.remaining=0
		m.kind=""
		m.growth=0.0
	elif crop.has("regrow"):m.growth=float(crop.time)-float(crop.regrow)
	else:m.growth=0.0
	m.wet=false

## Own rule: rain wets an exposed plot at the start of a tick on a rainy day; every
## midnight dries it and a rainy new day re-wets it; growth accrues only while wet
## and in season, capped at maturity.
func model_advance(m:Dictionary,start:float,dt:float) -> void:
	var kind:String=str(m.kind)
	var need:float=float(World.CROPS[kind].time) if World.CROPS.has(kind) else 0.0
	var seasons:Array=World.CROP_SEASONS.get(kind,[])
	var day_len:float=float(WEATHER.DAY_SECONDS)
	var end:=start+dt
	var day:int=int(floorf(start/day_len))
	var wet:bool=bool(m.wet)
	if my_rains(day):wet=true
	var growth:float=float(m.growth)
	var cursor:=start
	while true:
		var boundary:=float(day+1)*day_len
		var seg_end:=minf(boundary,end)
		var in_season:bool=seasons.is_empty() or my_season(day) in seasons
		if wet and need>0.0 and in_season and seg_end>cursor:
			growth=minf(growth+(seg_end-cursor),need)
		if boundary>end:break
		day+=1
		cursor=boundary
		wet=my_rains(day)
	m.wet=wet
	m.growth=growth

func compare_model(label:String) -> void:
	for k in model:
		var m:Dictionary=model[k]
		var crop:Dictionary=world.state.crops.get(k,{})
		var got_kind:String=str(crop.get("kind","?"))
		var got_growth:float=float(crop.get("growth",-1.0))
		var got_wet:bool=crop.get("wet")==true
		var got_rem:int=int(crop.get("remaining",0))
		var same:bool=got_kind==str(m.kind) and absf(got_growth-float(m.growth))<=1e-6 and got_wet==bool(m.wet) and got_rem==int(m.remaining) and str(crop.get("owner",""))==TOKEN
		expect(same,"%s: plot %s %s matches model %s"%[label,str(k),JSON.stringify(crop),JSON.stringify(m)])

func advance(dt:float) -> void:
	advance_to(now()+dt)

## World.step in chunks of at most one game day; the model and the crop layer are
## compared after every chunk; time passing never moves coins or berries/tomatoes.
func advance_to(target:float,chunk:float=1440.0) -> void:
	while not failed and now()<target:
		var start:=now()
		var dt:=minf(chunk,target-start)
		var coins:int=int(person().coins)
		var held:Array=[int(bag().get("strawberry",0)),int(bag().get("tomato",0))]
		if not expect(world.step(dt,true),"world step %.1f at t=%.1f (%s)"%[dt,start,world.step_error]):return
		steps+=1
		advanced+=dt
		expect(now()==start+dt,"clock advanced exactly %.1f s (t=%.1f)"%[dt,now()])
		for k in model:model_advance(model[k],start,dt)
		compare_model("step %.1f -> t=%.1f (%s)"%[dt,now(),season_now()])
		var held_now:Array=[int(bag().get("strawberry",0)),int(bag().get("tomato",0))]
		expect(int(person().coins)==coins and held_now==held,"waiting moved no coins or crops at t=%.1f"%now())

# ---------------------------------------------------------------- crop helpers

func crop_at(c:Vector2i) -> Dictionary:
	var crop:Dictionary=world.state.crops.get(World.key(c),{})
	return crop

func growth_of(c:Vector2i) -> float:
	return float(crop_at(c).get("growth",-1.0))

func dormant(c:Vector2i) -> bool:
	var k:String=World.key(c)
	var crop:Dictionary=world.state.crops.get(k,{})
	var roof:Dictionary=world.state.roofs.get(k,{})
	return World.plot_dormant(crop,roof,"home",c,now())

func expect_crop(c:Vector2i,kind:String,growth:float,remaining:int,label:String) -> void:
	var crop:=crop_at(c)
	expect(str(crop.get("kind",""))==kind and absf(float(crop.get("growth",-1.0))-growth)<=1e-6 and int(crop.get("remaining",-1))==remaining and str(crop.get("owner",""))==TOKEN,"%s: want %s growth %.1f remaining %d (got %s)"%[label,kind,growth,remaining,JSON.stringify(crop)])

## Dormant, unchanged growth and harvest count, still planted (not withered).
func expect_frozen(c:Vector2i,kind:String,growth:float,remaining:int,label:String) -> void:
	expect_crop(c,kind,growth,remaining,"%s: %s frozen, not withered"%[label,kind])
	expect(dormant(c),"%s: World.plot_dormant true for %s in %s"%[label,kind,season_now()])
	expect(not World.crop_grows_in_season(kind,"home",c,now()),"%s: %s out of season"%[label,kind])

func unripe_msg(c:Vector2i) -> String:
	var crop:=crop_at(c)
	var kind:String=str(crop.get("kind",""))
	if crop.get("wet")!=true:return "還沒成熟，先澆點水吧"
	return "還沒成熟，再等 %d 秒"%ceili(float(World.CROPS[kind].time)-float(crop.get("growth",0.0)))

func harvest_msg(kind:String,left:int) -> String:
	var crop_name:String=str(World.CROPS[kind].name)
	var count:int=int(World.CROPS[kind]["yield"])
	if left>0:return "收成了！%s +%d。%s還能再收 %d 次，記得重新澆水"%[crop_name,count,crop_name,left]
	return "收成了！%s +%d。可以出售或帶去做料理"%[crop_name,count]

func day_start(day:int) -> float:
	return float(day)*float(WEATHER.DAY_SECONDS)

func day_now() -> int:
	return int(floorf(now()/float(WEATHER.DAY_SECONDS)))

func season_now() -> String:
	return str(WEATHER.season_on_day(WEATHER.day_index(now())))

func now() -> float:
	return float(world.state.time)

# ---------------------------------------------------------------- actions

## A successful action: exact whole-bag delta, exact coin delta, exact reply.
func play(action:String,target:Vector2i,extra:String,delta:Dictionary,coin_delta:int,message:String) -> Dictionary:
	if failed:return {"ok":false,"message":"skipped"}
	walk_to(target)
	if failed:return {"ok":false,"message":"skipped"}
	var before:Dictionary=bag().duplicate(true)
	var coins:int=int(person().coins)
	actions+=1
	var result:Dictionary=world.act(tok,"season-dormancy-%d"%(actions+rejections),action,target,extra)
	if not expect(bool(result.ok),"%s %s at %s succeeds (got '%s')"%[action,extra,str(target),str(result.message)]):return result
	expect(str(result.message)==message,"%s message '%s' (got '%s')"%[action,message,str(result.message)])
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
	rejections+=1
	var before:=canon_bytes(world.state)
	var snapshot:Variant=_canon(world.state)
	var result:Dictionary=world.act(tok,"season-dormancy-%d"%(actions+rejections),action,target,extra)
	expect(not bool(result.ok) and str(result.message)==message,"%s: refused '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	var after:=canon_bytes(world.state)
	expect(after==before,"%s: canonical world state unchanged %s"%[label,"" if after==before else first_diff(snapshot,_canon(world.state),"state")])

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

func person() -> Dictionary:
	return world.state.players[tok]

func bag() -> Dictionary:
	return person().inventory

# ---------------------------------------------------------------- movement (test_flower_journey.gd walker)

func route(target:Vector2i,reach:float=2.0) -> Array:
	var local_world:=World.new()
	local_world.state=world.region_snapshot(world.player_region(tok))
	local_world._region=world.player_region(tok)
	var start:=Vector2i(int(person().x),int(person().y))
	var queue:=[start]
	var previous:={start:start}
	var index:=0
	while index<queue.size():
		var tile:Vector2i=queue[index]
		index+=1
		if tile!=target and Vector2(tile-target).length()<=reach:
			var path:=[tile]
			while tile!=start:
				tile=previous[tile]
				path.push_front(tile)
			return path
		for offset in World.INDUSTRY.NEIGHBORS:
			var next:Vector2i=tile+offset
			if not previous.has(next) and local_world.can_stand(Vector2(next)+Vector2(0.5,0.5)):
				previous[next]=tile
				queue.append(next)
	return []

func walk_to(target:Vector2i,reach:float=2.0) -> void:
	if failed:return
	if Vector2(person().x,person().y).distance_to(Vector2(target)+Vector2(0.5,0.5))<=2.5:return
	var path:=route(target,reach)
	if path.is_empty():
		expect(false,"%s: no path to %s in %s"%[tok,str(target),world.player_region(tok)])
		return
	for index in range(1,path.size()):
		var a:Vector2i=path[index-1]
		var b:Vector2i=path[index]
		var direction:=Vector2(b-a)
		for i in range(4):world.move_player(tok,direction,0.25/3.6)
		walking+=1
		if not expect(Vector2(person().x,person().y).distance_to(Vector2(b)+Vector2(0.5,0.5))<=0.001,"movement followed a passable route"):return

# ---------------------------------------------------------------- canonical compare

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

# ---------------------------------------------------------------- assertions

func expect(condition:bool,message:String) -> bool:
	checks+=1
	if not condition:
		failures+=1
		failed=true
		push_error("SEASON_DORMANCY_JOURNEY FAIL: "+message)
		print("SEASON_DORMANCY_JOURNEY FAIL: "+message)
	return condition
