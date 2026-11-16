extends SceneTree
## T049／T093 作物成長與價格的一致性檢查，對真正的 World 規則跑一遍（純資料版本在
## tests/test_crop_economy.gd）。每種作物（24 種）用一般玩家動作 world.act() 走完：
## 小栗種子攤買一包種子 → 整地 → 播種 → 澆水 → 用 world.step() 推進時間到成熟
## （成熟前一秒仍不能收、剛好 time 秒可收）→ 採收（再生作物每次要重新澆水、
## 重新長滿 time 秒）→ 回種子攤賣掉全部收成。金額、收成數、成長秒數都要等於
## CropEconomy.row(kind)，CropEconomy.row 也要等於本檔手抄的對照表 EXPECTED。
##
## 季節（World.CROP_SEASONS 的 21 種作物）：先在「下一個季節第一天」的前一天
## （不在季節內）播種澆水，step 後 growth 仍為 0、採收回覆「作物正在休眠…」；
## 跨過午夜到季節第一天（一定是晴天：季節長 14 天＝兩個 7 天天氣循環），土已經乾了，
## 重新澆水後照常成長。每段種植都從當天 60 秒開始，最長 650 秒，不會跨過午夜；
## 推進到目標日都用 world.step(大段 dt)，不直接寫 state.time。
##
## 特殊作物：稻米只能在宜蘭水圳旁水田、霧竹茶只能在溪谷茶圃、星夜菇只能在金瓜石
## 第五層（洞內、不下雨、不分季節）。三種先在家園一般農田播種被拒（訊息完全相同、
## 整個 state 位元組不變），再到正確地點種完。田尾三種花在家園種子攤的購買鎖
## （FLOWER_NURSERY.home_seed_allowed）先驗證拒絕，再寫入第三章完成紀錄後購買。
##
## Direct state writes in this suite（全部標 # PRESET）：
## - player.region（在 home / lanyang / bamboo_grove / mine_5 之間瞬移，代替旅行與礦坑解鎖）
## - player.x / player.y（站到種子攤或農田旁，act() 有距離檢查）
## - state.flower_nursery.players[token]（第三章田尾完成紀錄：letter/intro/planted/
##   harvested/saved/shipped/complete；只為了通過 home_seed_allowed，公共花園未寫）
## 沒有直接寫：鈴幣、背包、作物的 growth/wet/kind、world time。買、整地、播種、澆水、
## 採收、出售都走 world.act，時間都走 world.step。

const World=preload("res://scripts/world.gd")
const CropEconomy=preload("res://scripts/crop_economy.gd")
const Weather=preload("res://scripts/weather.gd")
const FlowerNursery=preload("res://scripts/flower_nursery.gd")

const TOKEN:="farmer"
const STALL:=Vector2i(43,29)
const STALL_STAND:=Vector2(43.5,30.5)
const PADDY:=Vector2i(32,26)
const PADDY_STAND:=Vector2(31.5,26.5)
const TEA_BED:=Vector2i(17,21)
const TEA_BED_OTHER:=Vector2i(18,21)
const TEA_STAND:=Vector2(17.5,23.5)
const MUSHROOM_BED:=Vector2i(30,21)
const MUSHROOM_STAND:=Vector2(29.5,21.5)
const START_OFFSET:=60.0
const UNWATERED_PROBE:=10.0
const DORMANT_PROBE:=120.0

const MSG_DORMANT:="作物正在休眠，等到適合的季節會繼續生長。"
## T048：再生作物首熟之後每次再長出來的秒數（手抄；規劃書 2 天換成各作物的秒數）。
const HAND_REGROW:={"tomato":60.0,"strawberry":84.0,"cucumber":80.0,"eggplant":82.5,"mist_tea":84.0}
const MSG_DRY:="還沒成熟，先澆點水吧"
const MSG_ONE_SECOND:="還沒成熟，再等 1 秒"
const MSG_NOT_ON_SALE:="這件商品尚未上架"
const MSG_RICE:="月牙稻米要種在宜蘭水圳旁的水田"
const MSG_TEA:="霧竹茶要種在溪谷茶圃"
const MSG_TEA_ONLY:="溪谷茶圃只種霧竹茶"
const MSG_MUSHROOM:="星夜菇要種在金瓜石第五層的洞內菌床"

## 手抄自 scripts/crop_catalog.gd（獨立於 CropEconomy）：
## [名稱, 種子價, 每次產量, 收成次數, 售價, 成長秒數, 一包種到底的淨收益（手算）]
const EXPECTED:={
	"radish":["奶白蘿蔔",12,1,1,24,90.0,12],
	"lettuce":["圓葉萵苣",14,1,1,28,75.0,14],
	"wheat":["星點小麥",18,2,1,19,120.0,20],
	"carrot":["糖心胡蘿蔔",20,1,1,42,105.0,22],
	"potato":["小馬鈴薯",25,2,1,30,150.0,35],
	"tomato":["太陽番茄",55,2,3,28,120.0,113],
	"pumpkin":["琥珀南瓜",70,1,1,150,270.0,80],
	"cauliflower":["雲朵花椰菜",45,1,1,95,210.0,50],
	"sweet_corn":["甜玉米",60,2,1,35,210.0,10],
	"strawberry":["蜜香草莓",70,2,3,36,210.0,146],
	"cucumber":["波點黃瓜",40,2,3,22,120.0,92],
	"cabbage":["雪白高麗菜",44,1,1,94,210.0,50],
	"sugar_beet":["霜糖甜菜",30,1,1,66,165.0,36],
	"star_mushroom":["星夜菇",36,2,1,36,165.0,36],
	"sweet_potato":["栗香地瓜",32,2,1,34,165.0,36],
	"eggplant":["紫絨茄子",48,2,3,27,165.0,114],
	"rice":["月牙稻米",28,2,1,29,165.0,30],
	"watermelon":["小圓西瓜",65,1,1,135,270.0,70],
	"ginger":["暖泉薑",45,2,1,48,210.0,51],
	"cotton":["棉球花",40,2,1,42,210.0,44],
	"mist_tea":["霧竹茶",65,2,3,38,210.0,163],
	"bluebell":["鈴蘭藍花",28,2,1,28,150.0,28],
	"orange_blossom":["蜜橙花",28,2,1,28,150.0,28],
	"chime_herb":["風鈴香草",24,1,1,48,120.0,24],
}
## 手抄自 world.gd CROP_SEASONS；沒列的作物不分季節。
const HAND_SEASONS:={
	"radish":["spring","autumn"],"lettuce":["spring","summer"],"wheat":["spring","summer","autumn"],
	"carrot":["spring","autumn"],"potato":["spring","winter"],"tomato":["summer"],"pumpkin":["autumn"],
	"cauliflower":["spring","winter"],"sweet_corn":["summer","autumn"],"strawberry":["spring"],
	"cucumber":["summer"],"cabbage":["winter"],"sugar_beet":["winter"],"sweet_potato":["autumn"],
	"eggplant":["summer","autumn"],"rice":["summer","autumn"],"watermelon":["summer"],"ginger":["winter"],
	"cotton":["spring","summer"],"bluebell":["spring"],"orange_blossom":["summer","autumn"],
}
const HAND_PLACE:={"mist_tea":"bamboo_tea_beds","rice":"lanyang_paddy","star_mushroom":"mine_5"}
const FLOWERS:=["bluebell","orange_blossom","chime_herb"]
## 一般家園作物 → 田尾三種花（先驗證購買鎖）→ 只能種在特定地點的三種。
const ORDER:=["radish","lettuce","wheat","carrot","potato","tomato","pumpkin","cauliflower","sweet_corn",
	"strawberry","cucumber","cabbage","sugar_beet","sweet_potato","eggplant","watermelon","ginger","cotton",
	"bluebell","orange_blossom","chime_herb","rice","mist_tea","star_mushroom"]

var w
var checks:=0
var failures:=0
var seq:=0
var looped:=0
var dir:=""
var home_cells:Array[Vector2i]=[]
var refuse_plot:=Vector2i(44,36)

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+message)

func _initialize() -> void:
	dir=OS.get_environment("TEMP").path_join("tuantuan-crop-world-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	expect(DirAccess.make_dir_absolute(dir)==OK,"isolated save directory created at "+dir)
	for y in [34,35,36]:
		for x in range(36,45):
			home_cells.append(Vector2i(x,y))
	refuse_plot=home_cells[home_cells.size()-1]
	test_tables()
	w=World.new()
	w.save_path=dir.path_join("crop_world.json")
	w.add_player(TOKEN,"農")
	expect(w.player_region(TOKEN)=="home","the farmer starts in the home region")
	expect(float(w.state.time)==0.0,"world time starts at 0")
	print("CROP WORLD NOTE presets: player.region/x/y teleports (lanyang, bamboo_grove, mine_5, home) and the chapter-3 Tianwei completion record; no coins, inventory, crop or time writes")
	# An ordinary home plot used for the refused plantings.
	place("home",Vector2(refuse_plot.x+0.5,refuse_plot.y+1.5))
	var tilled:Dictionary=do_act("hoe",refuse_plot)
	expect(bool(tilled.get("ok",false)),"ordinary home refusal plot is tilled, got '%s'"%str(tilled.get("message","")))
	var home_index:=0
	for kind:String in ORDER:
		if kind==FLOWERS[0]:unlock_flowers()
		var cell:=Vector2i(-1,-1)
		if not HAND_PLACE.has(kind):
			cell=home_cells[home_index]
			home_index+=1
		if loop_crop(kind,cell):looped+=1
		else:print("CROP WORLD NOTE %s: the buy-grow-sell loop did not complete (see FAIL lines)"%kind)
	expect(looped==World.CROPS.size(),"every crop completed the real buy-grow-sell loop (%d/%d)"%[looped,World.CROPS.size()])
	cleanup()
	print("CROP WORLD crops=%d looped=%d checks=%d failures=%d"%[World.CROPS.size(),looped,checks,failures])
	quit(1 if failures else 0)

# ---------------------------------------------------------------- helpers
func sorted_copy(values:Array) -> Array:
	var copy:Array=values.duplicate()
	copy.sort()
	return copy

func do_act(action:String,cell:Vector2i,extra:String="") -> Dictionary:
	seq+=1
	var result:Dictionary=w.act(TOKEN,"crop-world-%d"%seq,action,cell,extra)
	return result

func snap() -> PackedByteArray:
	var copy:Dictionary=w.state.duplicate(true)
	return var_to_bytes(copy)

func coins() -> int:
	var person:Dictionary=w.state.players[TOKEN]
	return int(person.coins)

func held(item:String) -> int:
	var person:Dictionary=w.state.players[TOKEN]
	var inv:Dictionary=person.inventory
	return int(inv.get(item,0))

## PRESET: teleport (region) and stand (x/y) instead of travelling.
func place(region:String,stand:Vector2) -> void:
	var person:Dictionary=w.state.players[TOKEN]
	person["region"]=region # PRESET
	person["x"]=stand.x # PRESET
	person["y"]=stand.y # PRESET
	expect(w.player_region(TOKEN)==region,"farmer is in region %s"%region)

func plot_at(region:String,cell:Vector2i) -> Dictionary:
	var layer:Dictionary
	if region=="home":
		layer=w.state.crops
	else:
		var regional:Dictionary=w.state.regions[region]
		layer=regional.crops
	var found:Dictionary=layer.get(World.key(cell),{})
	return found

## A refused action: exact message (when given) and a byte-identical state.
func refuse(action:String,cell:Vector2i,extra:String,want:String,label:String) -> void:
	var before:PackedByteArray=snap()
	var result:Dictionary=do_act(action,cell,extra)
	expect(not bool(result.get("ok",true)),"%s: %s %s is refused"%[label,action,extra])
	if not want.is_empty():
		expect(str(result.get("message",""))==want,"%s: refusal message is '%s', got '%s'"%[label,want,str(result.get("message",""))])
	expect(snap()==before,"%s: whole state byte-identical after the refused %s"%[label,action])

func advance(dt:float,label:String) -> bool:
	var stepped:bool=w.step(dt,true)
	expect(stepped,"%s: world.step(%.1f) succeeds (%s)"%[label,dt,str(w.step_error)])
	return stepped

func go_to(target:float,label:String) -> bool:
	var now:float=float(w.state.time)
	if target<=now:
		expect(false,"%s: target time %.1f is after now %.1f"%[label,target,now])
		return false
	var arrived:=advance(target-now,label)
	expect(float(w.state.time)==target,"%s: world time is exactly %.1f (got %.1f)"%[label,target,float(w.state.time)])
	return arrived

func current_day() -> int:
	return int(Weather.day_index(float(w.state.time)))

func season_of(day:int) -> String:
	return Weather.season_on_day(float(day))

## Non-seasonal: the next non-rainy day. Seasonal: the next first day of an open
## season whose previous day is out of season (and is not rainy), at least two days
## ahead so the out-of-season day before it is still in the future.
func pick_day(seasons:Array) -> int:
	var first:int=current_day()+(1 if seasons.is_empty() else 2)
	var span:int=Weather.DAYS_PER_SEASON*Weather.SEASONS.size()*2
	for d in range(first,first+span):
		if Weather.outdoor_id(float(d))=="rainy":continue
		if seasons.is_empty():return d
		if season_of(d) in seasons and not (season_of(d-1) in seasons):return d
	return -1

# ---------------------------------------------------------------- tables
func test_tables() -> void:
	expect(World.CROPS.size()==24,"World.CROPS has 24 crops (%d)"%World.CROPS.size())
	expect(EXPECTED.size()==24 and ORDER.size()==24,"hand table and order list cover 24 crops")
	expect(sorted_copy(ORDER)==sorted_copy(World.CROPS.keys()),"order list names exactly the World crops")
	expect(sorted_copy(EXPECTED.keys())==sorted_copy(World.CROPS.keys()),"hand table names exactly the World crops")
	expect(sorted_copy(HAND_SEASONS.keys())==sorted_copy(World.CROP_SEASONS.keys()),"hand season table names exactly the seasonal crops")
	for kind:String in ORDER:
		var e:Array=EXPECTED[kind]
		var crop:Dictionary=World.CROPS[kind]
		var lifetime:int=int(e[2])*int(e[3])
		expect(lifetime*int(e[4])-int(e[1])==int(e[6]),"%s: hand profit %d == %d*%d - %d"%[kind,int(e[6]),lifetime,int(e[4]),int(e[1])])
		expect(str(crop.name)==str(e[0]),"%s: catalog name %s == hand %s"%[kind,str(crop.name),str(e[0])])
		expect(int(crop.seed_price)==int(e[1]),"%s: catalog seed price %d == hand %d"%[kind,int(crop.seed_price),int(e[1])])
		expect(int(crop.get("yield",0))==int(e[2]),"%s: catalog yield == hand %d"%[kind,int(e[2])])
		expect(int(crop.get("cycles",1))==int(e[3]),"%s: catalog harvests == hand %d"%[kind,int(e[3])])
		expect(int(crop.price)==int(e[4]),"%s: catalog price %d == hand %d"%[kind,int(crop.price),int(e[4])])
		expect(float(crop.time)==float(e[5]),"%s: catalog time %.1f == hand %.1f"%[kind,float(crop.time),float(e[5])])
		var game_seasons:Array=World.CROP_SEASONS.get(kind,[])
		var hand_seasons:Array=HAND_SEASONS.get(kind,[])
		expect(sorted_copy(game_seasons)==sorted_copy(hand_seasons),"%s: CROP_SEASONS %s == hand %s"%[kind,str(game_seasons),str(hand_seasons)])
		var row:Dictionary=CropEconomy.row(kind)
		expect(str(row.kind)==kind and str(row.name)==str(e[0]),"%s: row kind/name"%kind)
		expect(int(row.seed_price)==int(e[1]),"%s: row seed_price %d == hand %d"%[kind,int(row.seed_price),int(e[1])])
		expect(int(row["yield"])==int(e[2]),"%s: row yield %d == hand %d"%[kind,int(row["yield"]),int(e[2])])
		expect(int(row.cycles)==int(e[3]),"%s: row cycles %d == hand %d"%[kind,int(row.cycles),int(e[3])])
		expect(int(row.price)==int(e[4]),"%s: row price %d == hand %d"%[kind,int(row.price),int(e[4])])
		expect(float(row.time)==float(e[5]),"%s: row time %.1f == hand %.1f"%[kind,float(row.time),float(e[5])])
		expect(int(row.lifetime)==lifetime,"%s: row lifetime %d == hand %d"%[kind,int(row.lifetime),lifetime])
		expect(int(row.gross)==lifetime*int(e[4]),"%s: row gross %d == hand %d"%[kind,int(row.gross),lifetime*int(e[4])])
		expect(int(row.profit)==int(e[6]),"%s: row profit %d == hand %d"%[kind,int(row.profit),int(e[6])])
		var hand_grow:float=float(e[5])+float(HAND_REGROW.get(kind,e[5]))*float(int(e[3])-1)
		expect(float(row.grow_seconds)==hand_grow,"%s: row grow_seconds %.1f == hand %.1f"%[kind,float(row.grow_seconds),hand_grow])
		var row_seasons:Array=row.seasons
		expect(row_seasons==sorted_copy(hand_seasons),"%s: row seasons %s == hand %s"%[kind,str(row_seasons),str(sorted_copy(hand_seasons))])
		expect(str(row.place)==str(HAND_PLACE.get(kind,"")),"%s: row place '%s' == hand '%s'"%[kind,str(row.place),str(HAND_PLACE.get(kind,""))])

# ---------------------------------------------------------------- flowers lock
func unlock_flowers() -> void:
	place("home",STALL_STAND)
	for kind:String in FLOWERS:
		refuse("buy",STALL,kind,World.FLOWER_HOME_SEED_MSG,"%s home seed lock"%kind)
	var record:Dictionary=FlowerNursery.FRESH.duplicate(true)
	record["letter"]=true
	record["intro"]=true
	record["shipped"]=true
	record["complete"]=true
	var planted:Dictionary=record["planted"]
	var harvested:Dictionary=record["harvested"]
	var saved:Dictionary=record["saved"]
	for kind:String in FLOWERS:
		planted[kind]=true
		harvested[kind]=1
		saved[kind]=true
	var nursery:Dictionary=w.state.flower_nursery
	var players:Dictionary=nursery.players
	players[TOKEN]=record # PRESET (chapter-3 Tianwei completion record)
	print("CROP WORLD NOTE flowers: home stall purchase lock checked, then the chapter-3 completion record was written directly (PRESET) instead of playing the Tianwei chapter")
	for kind:String in FLOWERS:
		expect(FlowerNursery.home_seed_allowed(w.state,TOKEN,kind),"%s: home seed purchase allowed after the chapter-3 record"%kind)

# ---------------------------------------------------------------- one crop
func loop_crop(kind:String,home_cell:Vector2i) -> bool:
	var e:Array=EXPECTED[kind]
	var label_name:String=str(e[0])
	var seed_price:int=int(e[1])
	var per:int=int(e[2])
	var cycles:int=int(e[3])
	var price:int=int(e[4])
	var grow:float=float(e[5])
	var regrow:float=float(HAND_REGROW.get(kind,grow))
	var profit:int=int(e[6])
	var row:Dictionary=CropEconomy.row(kind)
	var seasons:Array=HAND_SEASONS.get(kind,[])
	var seasonal:bool=not seasons.is_empty()
	var seed_item:String=kind+"_seed"
	var region:="home"
	var cell:=home_cell
	var stand:=Vector2(home_cell.x+0.5,home_cell.y+1.5)
	if kind=="rice":
		region="lanyang"
		cell=PADDY
		stand=PADDY_STAND
	elif kind=="mist_tea":
		region="bamboo_grove"
		cell=TEA_BED
		stand=TEA_STAND
	elif kind=="star_mushroom":
		region="mine_5"
		cell=MUSHROOM_BED
		stand=MUSHROOM_STAND
	# Choose the day: the in-season day `day`, planted the (out-of-season) day before.
	var day:int=pick_day(seasons)
	expect(day>=0,"%s: a suitable non-rainy day exists"%kind)
	if day<0:return false
	var start_day:int=day-1 if seasonal else day
	if not go_to(float(start_day)*Weather.DAY_SECONDS+START_OFFSET,"%s: reach day %d"%[kind,start_day+1]):return false
	# 1. Buy one packet at Xiaoli's seed stall.
	place("home",STALL_STAND)
	var coins_start:int=coins()
	var seeds_before:int=held(seed_item)
	var bought:Dictionary=do_act("buy",STALL,kind)
	expect(bool(bought.get("ok",false)),"%s: buy one seed packet, got '%s'"%[kind,str(bought.get("message",""))])
	if not bool(bought.get("ok",false)):return false
	expect(str(bought.get("message",""))=="買到一包"+label_name+"種子","%s: buy message names the crop, got '%s'"%[kind,str(bought.get("message",""))])
	expect(coins()==coins_start-seed_price,"%s: coins drop by exactly %d (%d -> %d)"%[kind,seed_price,coins_start,coins()])
	expect(coins_start-coins()==int(row.seed_price),"%s: coin drop == row.seed_price"%kind)
	expect(held(seed_item)==seeds_before+1,"%s: %s +1 (%d -> %d)"%[kind,seed_item,seeds_before,held(seed_item)])
	# Place-locked crops: refused on an ordinary home plot first.
	if kind in HAND_PLACE:
		place("home",Vector2(refuse_plot.x+0.5,refuse_plot.y+1.5))
		var want:String=MSG_RICE if kind=="rice" else (MSG_TEA if kind=="mist_tea" else MSG_MUSHROOM)
		refuse("seed",refuse_plot,kind,want,"%s on an ordinary home plot"%kind)
		expect(held(seed_item)==seeds_before+1,"%s: refused planting keeps the seed"%kind)
		expect(str(plot_at("home",refuse_plot).get("kind","?"))=="","%s: the home plot stays empty"%kind)
		print("CROP WORLD NOTE %s: teleported to %s (PRESET region/x/y) instead of travelling there"%[kind,region])
	# 2. Hoe, seed, (refused early harvest), water.
	place(region,stand)
	if kind=="mist_tea":
		refuse("seed",TEA_BED_OTHER,"radish",MSG_TEA_ONLY,"radish on the bamboo tea bed")
	var hoed:Dictionary=do_act("hoe",cell)
	expect(bool(hoed.get("ok",false)),"%s: hoe %s in %s, got '%s'"%[kind,World.key(cell),region,str(hoed.get("message",""))])
	if not bool(hoed.get("ok",false)):return false
	var sown:Dictionary=do_act("seed",cell,kind)
	expect(bool(sown.get("ok",false)),"%s: seed, got '%s'"%[kind,str(sown.get("message",""))])
	if not bool(sown.get("ok",false)):return false
	expect(held(seed_item)==seeds_before,"%s: sowing uses the bought packet"%kind)
	var plot:Dictionary=plot_at(region,cell)
	expect(str(plot.get("kind",""))==kind and int(plot.get("remaining",-1))==cycles and float(plot.get("growth",-1.0))==0.0 and plot.get("wet",true)==false,"%s: fresh plot kind/remaining %d/growth 0/dry: %s"%[kind,cycles,str(plot)])
	refuse("harvest",cell,"",MSG_DORMANT if seasonal else MSG_DRY,"%s: harvest right after sowing"%kind)
	var watered:Dictionary=do_act("water",cell)
	expect(bool(watered.get("ok",false)),"%s: water, got '%s'"%[kind,str(watered.get("message",""))])
	if not bool(watered.get("ok",false)):return false
	# 5. Season rule: no growth out of season, growth resumes in season.
	if seasonal:
		var off_season:String=season_of(start_day)
		expect(not (off_season in seasons),"%s: day %d is out of season (%s not in %s)"%[kind,start_day+1,off_season,str(seasons)])
		if not advance(DORMANT_PROBE,"%s: out-of-season step"%kind):return false
		plot=plot_at(region,cell)
		expect(float(plot.get("growth",-1.0))==0.0,"%s: watered plot does not grow in %s (growth %s)"%[kind,off_season,str(plot.get("growth"))])
		refuse("harvest",cell,"",MSG_DORMANT,"%s: harvest in %s"%[kind,off_season])
		if not go_to(float(day)*Weather.DAY_SECONDS+START_OFFSET,"%s: reach in-season day %d"%[kind,day+1]):return false
		var on_season:String=season_of(day)
		expect(on_season in seasons,"%s: day %d is in season (%s in %s)"%[kind,day+1,on_season,str(seasons)])
		plot=plot_at(region,cell)
		expect(float(plot.get("growth",-1.0))==0.0,"%s: still no growth after crossing into %s (growth %s)"%[kind,on_season,str(plot.get("growth"))])
		expect(plot.get("wet",true)==false,"%s: the plot dried at midnight (sunny day %d)"%[kind,day+1])
		var rewatered:Dictionary=do_act("water",cell)
		expect(bool(rewatered.get("ok",false)),"%s: water again in %s"%[kind,on_season])
		if not bool(rewatered.get("ok",false)):return false
	expect(Weather.outdoor_id(float(day))!="rainy","%s: growing day %d is not rainy"%[kind,day+1])
	# 3. Grow to maturity with the real step; harvest each cycle.
	var harvested:=0
	var wet_total:=0.0
	for c in range(cycles):
		var tag:String="%s cycle %d/%d"%[kind,c+1,cycles]
		# T048: the first ripening takes the whole time; later ones only the hand regrow seconds.
		var need:float=grow if c==0 else regrow
		if c>0:
			if not advance(UNWATERED_PROBE,tag+": unwatered step"):return false
			plot=plot_at(region,cell)
			expect(float(plot.get("growth",-1.0))==grow-regrow and plot.get("wet",true)==false,"%s: no growth until re-watered (%s)"%[tag,str(plot)])
			refuse("harvest",cell,"",MSG_DRY,tag+": harvest before re-watering")
			var again:Dictionary=do_act("water",cell)
			expect(bool(again.get("ok",false)),"%s: re-water"%tag)
			if not bool(again.get("ok",false)):return false
		if not advance(need-1.0,tag+": grow to one second before maturity"):return false
		plot=plot_at(region,cell)
		expect(float(plot.get("growth",-1.0))==grow-1.0,"%s: growth == %.1f (got %s)"%[tag,grow-1.0,str(plot.get("growth"))])
		refuse("harvest",cell,"",MSG_ONE_SECOND,tag+": one second early")
		if not advance(1.0,tag+": last second"):return false
		plot=plot_at(region,cell)
		var growth:float=float(plot.get("growth",-1.0))
		expect(growth==grow,"%s: growth == time %.1f (got %.1f)"%[tag,grow,growth])
		wet_total+=need
		var have:int=held(kind)
		var got:Dictionary=do_act("harvest",cell)
		var message:String=str(got.get("message",""))
		expect(bool(got.get("ok",false)),"%s: harvest at maturity, got '%s'"%[tag,message])
		if not bool(got.get("ok",false)):return false
		var gained:int=held(kind)-have
		harvested+=gained
		expect(gained==per,"%s: harvest gives exactly %d (got %d)"%[tag,per,gained])
		expect(message.contains("收成了！%s +%d。"%[label_name,per]),"%s: harvest message names the crop and count: '%s'"%[tag,message])
		var left:int=cycles-c-1
		plot=plot_at(region,cell)
		if left>0:
			expect(str(plot.get("kind",""))==kind and int(plot.get("remaining",-1))==left,"%s: plot stays planted with %d left (%s)"%[tag,left,str(plot)])
			expect(float(plot.get("growth",-1.0))==grow-regrow and plot.get("wet",true)==false,"%s: growth restarts at time-regrow %.1f and dry (%s)"%[tag,grow-regrow,str(plot)])
			expect(message.contains("%s還能再收 %d 次"%[label_name,left]),"%s: message says '%s還能再收 %d 次': '%s'"%[tag,label_name,left,message])
			if kind!="tomato":
				expect(not message.contains("番茄"),"%s: regrow message does not mention 番茄: '%s'"%[tag,message])
			if kind=="strawberry" and c==0:
				expect(message.contains("蜜香草莓還能再收 2 次"),"strawberry: first regrow message literally contains 蜜香草莓還能再收 2 次: '%s'"%message)
		else:
			expect(str(plot.get("kind","?"))=="","%s: plot is empty after the last harvest (%s)"%[tag,str(plot)])
			expect(message.contains("可以出售或帶去做料理"),"%s: final harvest message: '%s'"%[tag,message])
			expect(not message.contains("還能再收"),"%s: final harvest has no regrow note: '%s'"%[tag,message])
	expect(current_day()==day,"%s: the whole growing run stayed inside day %d (now day %d)"%[kind,day+1,current_day()+1])
	expect(harvested==per*cycles,"%s: total harvested %d == hand lifetime %d"%[kind,harvested,per*cycles])
	expect(harvested==int(row.lifetime),"%s: total harvested %d == row.lifetime %d"%[kind,harvested,int(row.lifetime)])
	expect(wet_total==grow+regrow*float(cycles-1),"%s: wet growth %.1f == hand %.1f"%[kind,wet_total,grow+regrow*float(cycles-1)])
	expect(wet_total==float(row.grow_seconds),"%s: wet growth %.1f == row.grow_seconds %.1f"%[kind,wet_total,float(row.grow_seconds)])
	# 4. Sell the whole harvest back at the stall; seeds cannot be sold.
	place("home",STALL_STAND)
	refuse("sell",STALL,seed_item,MSG_NOT_ON_SALE,"%s: sell a seed packet"%kind)
	var coins_before_sale:int=coins()
	var sold:Dictionary=do_act("sell",STALL,kind)
	expect(bool(sold.get("ok",false)),"%s: sell the harvest, got '%s'"%[kind,str(sold.get("message",""))])
	if not bool(sold.get("ok",false)):return false
	expect(str(sold.get("message",""))=="售出 %d 個，獲得 %d 鈴幣"%[harvested,harvested*price],"%s: sale message, got '%s'"%[kind,str(sold.get("message",""))])
	expect(coins()==coins_before_sale+harvested*price,"%s: coins rise by %d*%d (got %d -> %d)"%[kind,harvested,price,coins_before_sale,coins()])
	expect(coins()-coins_before_sale==int(row.gross),"%s: sale == row.gross %d"%[kind,int(row.gross)])
	expect(held(kind)==0,"%s: harvest stack emptied by the sale"%kind)
	expect(coins()-coins_start==profit,"%s: net coin change %d == hand profit %d"%[kind,coins()-coins_start,profit])
	expect(coins()-coins_start==int(row.profit),"%s: net coin change %d == row.profit %d"%[kind,coins()-coins_start,int(row.profit)])
	return true

# ---------------------------------------------------------------- cleanup
func cleanup() -> void:
	var access:=DirAccess.open(dir)
	if access!=null:
		for file_name in access.get_files():
			DirAccess.remove_absolute(dir.path_join(file_name))
	DirAccess.remove_absolute(dir)
