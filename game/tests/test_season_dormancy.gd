extends SceneTree
## T048 四季休眠與再生作物（規劃書驗收「跨季不枯死，收成次數不重置」）。真正的 World，
## 動作都走 world.act()，時間都走 world.step()（大段 dt；weather.advance_plot 內部按日切段）。
##
## 1. 資料：cycles>1 的作物都有 regrow，0<regrow<time，World.regrow_start==time-regrow，
##    且等於本檔手抄表 HAND_REGROW；其他作物沒有 regrow、regrow_start==0。季節文字、
##    World.plot_dormant 的純函式規則（溫室、普通屋頂、成熟、全年、田尾育苗床）。
## 2. 世界 A（rhythm.json）：五種再生作物（霧竹茶在溪谷茶圃）各在當季非雨天：首熟剛好 time
##    濕潤秒、收成後 growth==time-regrow／remaining 2／乾、不澆水不長、澆水後早一秒不能收、
##    剛好 regrow 秒可收，三次後空田、可重種；黃瓜在再生途中存檔→新 World 讀檔比對。
##    舊存檔相容（growth 低於 regrow_start 的再生作物會長滿 time）、remaining 0 / >cycles
##    的存檔被 load 拒絕；手推收割機（harvest_area）與手動採收結果相同。
## 3. 世界 B（dormancy.json）：草莓、番茄、黃瓜、茄子（再生）與蘿蔔、南瓜、高麗菜（單收）在
##    各自季節的最後一天種下、（再生作物先收第一次）長到一半，跨午夜進入非當季：澆水、每天
##    取樣到季節回來前一秒，growth 完全相同、remaining 不變、沒有枯死、plot_dormant 為真、
##    採收被拒且整個 state 位元組不變；季節回來後補足剩下的秒數就成熟，總收成次數仍是 3。
##    另一株黃瓜成熟後放置 56 天（一整年），一直成熟、不休眠，秋天照常採收。第 48 天存檔讀檔比對。
## 4. 世界 C（greenhouse.json）：非當季播種訊息、溫室中的休眠作物會長並可收、拆掉溫室後又休眠
##    且 growth 保留、先蓋溫室再播種的訊息；田主離線、朋友在線時作物照長且成熟後不枯萎，
##    沒人在線（step(dt,false)）時什麼都不長。
##
## Direct writes in this suite（全部標 # PRESET）：
## - player.region / player.x / player.y：place() 瞬移站到種子攤、農田或茶圃旁（act 有距離檢查）。
## - player.coins=5000（每個 World 一次，用來在小栗種子攤買所有種子；買賣本身走 act）。
## - 世界 A 背包：harvester +1、charcoal +5（手推收割機與燃料）。
## - 世界 C 背包：glass +4、copper_joint +2（兩座溫室玻璃棚的材料）。
## - 世界 C world.active_tokens.clear()（模擬田主與朋友都離線；朋友與田主之後用 add_player 回來）。
## - 讀回來的 World 的 save_path（設成 "" 或暫存資料夾內的新檔，避免寫回同一個存檔）。
## - 暫存資料夾裡手工改寫的存檔 JSON：舊存檔 growth=0.0、tomato remaining 0/3/4、radish remaining 1/2。
## 沒有直接寫：live World 的作物 kind/growth/wet/remaining、屋頂、world time。

const World=preload("res://scripts/world.gd")
const Weather=preload("res://scripts/weather.gd")
const FlowerNursery=preload("res://scripts/flower_nursery.gd")

const TOKEN:="farmer"
const FRIEND:="friend"
const STALL:=Vector2i(43,29)
const STALL_STAND:=Vector2(43.5,30.5)
const TEA_REGION:="bamboo_grove"
const TEA_BED:=Vector2i(17,21)
const TEA_STAND:=Vector2(17.5,23.5)
const DAY:=1440.0
const START_OFFSET:=60.0
const UNWATERED_PROBE:=10.0
const FUNDS:=5000

const MSG_DORMANT:="作物正在休眠，等到適合的季節會繼續生長。"
const MSG_DRY:="還沒成熟，先澆點水吧"
const MSG_ONE_SECOND:="還沒成熟，再等 1 秒"
const MSG_WATER:="水分充足，幼苗會慢慢長大"

## 手抄自 crop_catalog.gd（T048）：再生作物首熟後每次再長的秒數。
const HAND_REGROW:={"tomato":60.0,"strawberry":84.0,"cucumber":80.0,"eggplant":82.5,"mist_tea":84.0}
## 手抄：World.crop_season_text 應回傳的季節文字（春夏秋冬順序，「、」分隔）。
const HAND_SEASON_TEXT:={"tomato":"夏","strawberry":"春","cucumber":"夏","eggplant":"夏、秋",
	"radish":"春、秋","pumpkin":"秋","cabbage":"冬","potato":"春、冬","wheat":"春、夏、秋",
	"mist_tea":"","star_mushroom":"","lettuce":"春、夏"}
## 世界 B：作物在第 d0 天（零起算，季節最後一天）種下，第 R 天季節回來（手算）。
const HAND_RETURN:={"strawberry":56,"radish":28,"tomato":70,"cucumber":70,"eggplant":70,"pumpkin":84,"cabbage":98}
const SETUP_DAYS:=[13,27,41,55]
const LAST_DAY:=98
const TWIN_HARVEST_DAY:=84
const RELOAD_DAY:=47

var checks:=0
var failures:=0
var seq:=0
var dir:=""
var wb
var entries:Array[Dictionary]=[]

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL "+message)
		push_error("FAIL "+message)

func _initialize() -> void:
	dir=OS.get_environment("TEMP").path_join("tuantuan-season-dormancy-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	expect(DirAccess.make_dir_absolute(dir)==OK,"isolated save directory created at "+dir)
	expect(Weather.DAY_SECONDS==DAY and Weather.DAYS_PER_SEASON==14,"calendar: 1440 s days and 14-day seasons")
	print("SEASON DORMANCY NOTE presets: player.region/x/y teleports, coins=5000 per world, harvester+charcoal (world A), glass+copper_joint (world C), active_tokens.clear() (world C), fabricated save JSON files in the temp dir")
	test_data()
	test_world_a()
	test_world_b()
	test_world_c()
	cleanup()
	print("SEASON DORMANCY checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

# ---------------------------------------------------------------- helpers
func sorted_copy(values:Array) -> Array:
	var copy:Array=values.duplicate()
	copy.sort()
	return copy

func new_world(file_name:String):
	var made=World.new()
	made.save_path=dir.path_join(file_name)
	made.add_player(TOKEN,"農")
	var person:Dictionary=made.state.players[TOKEN]
	person["coins"]=FUNDS # PRESET (seed money for the stall purchases)
	return made

func do_act(wd,action:String,cell:Vector2i,extra:String="") -> Dictionary:
	seq+=1
	var result:Dictionary=wd.act(TOKEN,"season-%d"%seq,action,cell,extra)
	return result

func snap(wd) -> PackedByteArray:
	var copy:Dictionary=wd.state.duplicate(true)
	return var_to_bytes(copy)

func held(wd,item:String) -> int:
	var person:Dictionary=wd.state.players[TOKEN]
	var inv:Dictionary=person.inventory
	return int(inv.get(item,0))

func coins(wd) -> int:
	var person:Dictionary=wd.state.players[TOKEN]
	return int(person.coins)

func give_items(wd,items:Dictionary) -> void:
	var person:Dictionary=wd.state.players[TOKEN]
	var inv:Dictionary=person.inventory
	for item:String in items:
		inv[item]=int(inv.get(item,0))+int(items[item]) # PRESET (materials / tools)

## PRESET: teleport (region) and stand (x/y) instead of walking.
func place(wd,region:String,stand:Vector2) -> void:
	var person:Dictionary=wd.state.players[TOKEN]
	person["region"]=region # PRESET
	person["x"]=stand.x # PRESET
	person["y"]=stand.y # PRESET

func stand_of(region:String,cell:Vector2i) -> Vector2:
	if region==TEA_REGION:return TEA_STAND
	return Vector2(cell.x+0.5,cell.y+1.5)

func layer_of(wd,region:String,field:String) -> Dictionary:
	if region=="home":
		var home:Dictionary=wd.state[field]
		return home
	var regions:Dictionary=wd.state.regions
	var regional:Dictionary=regions.get(region,{})
	var found:Dictionary=regional.get(field,{})
	return found

func plot_at(wd,region:String,cell:Vector2i) -> Dictionary:
	var crops:Dictionary=layer_of(wd,region,"crops")
	var found:Dictionary=crops.get(World.key(cell),{})
	return found

func roof_at(wd,region:String,cell:Vector2i) -> Dictionary:
	var roofs:Dictionary=layer_of(wd,region,"roofs")
	var found:Dictionary=roofs.get(World.key(cell),{})
	return found

func now_of(wd) -> float:
	return float(wd.state.time)

func dormant_now(wd,region:String,cell:Vector2i) -> bool:
	return World.plot_dormant(plot_at(wd,region,cell),roof_at(wd,region,cell),region,cell,now_of(wd))

func rainy(day:int) -> bool:
	return Weather.outdoor_id(float(day))=="rainy"

func in_season(kind:String,day:int) -> bool:
	var seasons:Array=World.CROP_SEASONS.get(kind,[])
	return seasons.is_empty() or Weather.season_on_day(float(day)) in seasons

func season_name(day:int) -> String:
	return Weather.season_on_day(float(day))

func crop_time(kind:String) -> float:
	var crop:Dictionary=World.CROPS[kind]
	return float(crop.time)

func crop_yield(kind:String) -> int:
	var crop:Dictionary=World.CROPS[kind]
	return int(crop.get("yield",1))

func crop_cycles(kind:String) -> int:
	var crop:Dictionary=World.CROPS[kind]
	return int(crop.get("cycles",1))

func crop_label(kind:String) -> String:
	var crop:Dictionary=World.CROPS[kind]
	return str(crop.name)

## Hand value of the growth a regrowing crop restarts from (0 for single-harvest crops).
func hand_regrow_start(kind:String) -> float:
	if not HAND_REGROW.has(kind):return 0.0
	return crop_time(kind)-float(HAND_REGROW[kind])

func planted_message(kind:String,growing_now:bool) -> String:
	if growing_now:return "種下%s，記得澆水"%crop_label(kind)
	return "種下%s。現在不是它的季節，會休眠到%s季再生長。"%[crop_label(kind),str(HAND_SEASON_TEXT[kind])]

func refuse(wd,action:String,cell:Vector2i,extra:String,want:String,label:String) -> void:
	var before:PackedByteArray=snap(wd)
	var result:Dictionary=do_act(wd,action,cell,extra)
	expect(not bool(result.get("ok",true)),"%s: %s is refused"%[label,action])
	if not want.is_empty():
		expect(str(result.get("message",""))==want,"%s: refusal message is '%s', got '%s'"%[label,want,str(result.get("message",""))])
	expect(snap(wd)==before,"%s: whole state byte-identical after the refused %s"%[label,action])

func advance(wd,dt:float,label:String) -> bool:
	var stepped:bool=wd.step(dt,true)
	expect(stepped,"%s: world.step(%.2f) succeeds (%s)"%[label,dt,str(wd.step_error)])
	return stepped

func go_to(wd,target:float,label:String) -> bool:
	var now:float=now_of(wd)
	if target<now:
		expect(false,"%s: target time %.2f is not before now %.2f"%[label,target,now])
		return false
	if target==now:return true
	if not advance(wd,target-now,label):return false
	expect(now_of(wd)==target,"%s: world time is exactly %.2f (got %.2f)"%[label,target,now_of(wd)])
	return true

func buy_seed(wd,kind:String,label:String) -> bool:
	place(wd,"home",STALL_STAND)
	var coins_before:int=coins(wd)
	var seeds_before:int=held(wd,kind+"_seed")
	var bought:Dictionary=do_act(wd,"buy",STALL,kind)
	var ok_flag:bool=bool(bought.get("ok",false))
	expect(ok_flag,"%s: buy a %s seed packet, got '%s'"%[label,kind,str(bought.get("message",""))])
	if not ok_flag:return false
	var crop:Dictionary=World.CROPS[kind]
	expect(held(wd,kind+"_seed")==seeds_before+1,"%s: %s_seed +1"%[label,kind])
	expect(coins(wd)==coins_before-int(crop.seed_price),"%s: coins drop by the seed price %d"%[label,int(crop.seed_price)])
	return true

func water(wd,region:String,cell:Vector2i,label:String) -> bool:
	place(wd,region,stand_of(region,cell))
	var result:Dictionary=do_act(wd,"water",cell)
	var ok_flag:bool=bool(result.get("ok",false))
	expect(ok_flag and str(result.get("message",""))==MSG_WATER,"%s: water %s, got '%s'"%[label,World.key(cell),str(result.get("message",""))])
	expect(plot_at(wd,region,cell).get("wet",false)==true,"%s: plot is wet after watering"%label)
	return ok_flag

## Hoe (when the cell is not farmland yet) and sow with the real actions.
func sow(wd,region:String,cell:Vector2i,kind:String,label:String,want:String) -> bool:
	place(wd,region,stand_of(region,cell))
	if plot_at(wd,region,cell).is_empty():
		var hoed:Dictionary=do_act(wd,"hoe",cell)
		expect(bool(hoed.get("ok",false)),"%s: hoe %s, got '%s'"%[label,World.key(cell),str(hoed.get("message",""))])
		if not bool(hoed.get("ok",false)):return false
	var seeds_before:int=held(wd,kind+"_seed")
	var sown:Dictionary=do_act(wd,"seed",cell,kind)
	var ok_flag:bool=bool(sown.get("ok",false))
	expect(ok_flag,"%s: sow %s, got '%s'"%[label,kind,str(sown.get("message",""))])
	if not ok_flag:return false
	expect(str(sown.get("message",""))==want,"%s: planting message is '%s', got '%s'"%[label,want,str(sown.get("message",""))])
	expect(held(wd,kind+"_seed")==seeds_before-1,"%s: sowing uses one seed"%label)
	var plot:Dictionary=plot_at(wd,region,cell)
	expect(str(plot.get("kind",""))==kind and int(plot.get("remaining",-1))==crop_cycles(kind) and float(plot.get("growth",-1.0))==0.0 and plot.get("wet",true)==false,"%s: fresh plot %s/remaining %d/growth 0/dry: %s"%[label,kind,crop_cycles(kind),str(plot)])
	return true

## Water, grow exactly the outstanding seconds (refusing one second early) and harvest.
## Returns the items gained, -1 on failure.
func ripen_and_harvest(wd,region:String,cell:Vector2i,kind:String,label:String) -> int:
	var need:float=crop_time(kind)
	var per:int=crop_yield(kind)
	var crop_name:String=crop_label(kind)
	var plot:Dictionary=plot_at(wd,region,cell)
	if str(plot.get("kind",""))!=kind:
		expect(false,"%s: plot holds %s before ripening (%s)"%[label,kind,str(plot)])
		return -1
	var start:float=float(plot.get("growth",-1.0))
	var rem_before:int=int(plot.get("remaining",-1))
	if not water(wd,region,cell,label):return -1
	var outstanding:float=need-start
	if outstanding>1.0:
		if not advance(wd,outstanding-1.0,label+": grow to one second before ripe"):return -1
		plot=plot_at(wd,region,cell)
		expect(float(plot.get("growth",-1.0))==need-1.0,"%s: growth == %.2f one second early (got %s)"%[label,need-1.0,str(plot.get("growth"))])
		refuse(wd,"harvest",cell,"",MSG_ONE_SECOND,label+": one second early")
		if not advance(wd,1.0,label+": last second"):return -1
	elif outstanding>0.0:
		if not advance(wd,outstanding,label+": grow the outstanding seconds"):return -1
	plot=plot_at(wd,region,cell)
	expect(float(plot.get("growth",-1.0))==need,"%s: growth == time %.2f (got %s)"%[label,need,str(plot.get("growth"))])
	var have:int=held(wd,kind)
	var got:Dictionary=do_act(wd,"harvest",cell)
	var message:String=str(got.get("message",""))
	expect(bool(got.get("ok",false)),"%s: harvest when ripe, got '%s'"%[label,message])
	if not bool(got.get("ok",false)):return -1
	var gained:int=held(wd,kind)-have
	expect(gained==per,"%s: harvest gives exactly %d (got %d)"%[label,per,gained])
	expect(message.contains("收成了！%s +%d。"%[crop_name,per]),"%s: harvest message names crop and count: '%s'"%[label,message])
	plot=plot_at(wd,region,cell)
	if rem_before>1:
		expect(str(plot.get("kind",""))==kind and int(plot.get("remaining",-1))==rem_before-1,"%s: plot keeps %s with %d harvests left (%s)"%[label,kind,rem_before-1,str(plot)])
		expect(float(plot.get("growth",-1.0))==hand_regrow_start(kind) and float(plot.get("growth",-1.0))==World.regrow_start(kind),"%s: growth restarts at time-regrow %.2f (%s)"%[label,hand_regrow_start(kind),str(plot)])
		expect(plot.get("wet",true)==false,"%s: plot is dry after the harvest"%label)
		expect(message.contains("%s還能再收 %d 次"%[crop_name,rem_before-1]),"%s: message says %d harvests left: '%s'"%[label,rem_before-1,message])
	else:
		expect(str(plot.get("kind","?"))=="" and float(plot.get("growth",-1.0))==0.0 and plot.get("wet",true)==false and int(plot.get("remaining",-1))==0,"%s: plot is empty, dry, growth 0, remaining 0 after the last harvest (%s)"%[label,str(plot)])
		expect(message.contains("可以出售或帶去做料理") and not message.contains("還能再收"),"%s: final harvest message: '%s'"%[label,message])
	return gained

func compare_plot(copy:Dictionary,live:Dictionary,label:String) -> void:
	if live.is_empty():
		expect(copy.is_empty(),"%s: no farmland in the live world, none after reload (%s)"%[label,str(copy)])
		return
	expect(str(copy.get("kind","?"))==str(live.get("kind","!")),"%s: reloaded kind %s == live %s"%[label,str(copy.get("kind")),str(live.get("kind"))])
	expect(float(copy.get("growth",-1.0))==float(live.get("growth",-2.0)),"%s: reloaded growth %s == live %s"%[label,str(copy.get("growth")),str(live.get("growth"))])
	expect(int(copy.get("remaining",-1))==int(live.get("remaining",-2)),"%s: reloaded remaining %s == live %s"%[label,str(copy.get("remaining")),str(live.get("remaining"))])
	expect(bool(copy.get("wet",false))==bool(live.get("wet",true)) and copy.get("wet") is bool,"%s: reloaded wet %s == live %s"%[label,str(copy.get("wet")),str(live.get("wet"))])

func write_json(path:String,data:Dictionary) -> bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		expect(false,"cannot write fabricated save "+path)
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

# ---------------------------------------------------------------- 1. data
func test_data() -> void:
	var regrowing:Array=[]
	for kind:String in World.CROPS.keys():
		var crop:Dictionary=World.CROPS[kind]
		var need:float=float(crop.time)
		var cycles:int=int(crop.get("cycles",1))
		if cycles>1:
			regrowing.append(kind)
			expect(cycles==3,"%s: regrowing crop has 3 harvests (%d)"%[kind,cycles])
			expect(crop.has("regrow"),"%s: cycles>1 crop carries regrow seconds"%kind)
			var regrow:float=float(crop.get("regrow",0.0))
			expect(regrow>0.0 and regrow<need,"%s: 0 < regrow %.2f < time %.2f"%[kind,regrow,need])
			expect(World.regrow_start(kind)==need-regrow,"%s: regrow_start %.2f == time-regrow %.2f"%[kind,World.regrow_start(kind),need-regrow])
			expect(HAND_REGROW.has(kind) and regrow==float(HAND_REGROW.get(kind,-1.0)),"%s: catalog regrow %.2f == hand %s"%[kind,regrow,str(HAND_REGROW.get(kind))])
		else:
			expect(not crop.has("regrow"),"%s: single-harvest crop has no regrow"%kind)
			expect(World.regrow_start(kind)==0.0,"%s: regrow_start is 0 for a single-harvest crop"%kind)
	expect(sorted_copy(regrowing)==sorted_copy(HAND_REGROW.keys()),"regrowing crops %s == hand %s"%[str(sorted_copy(regrowing)),str(sorted_copy(HAND_REGROW.keys()))])
	expect(World.regrow_start("")==0.0 and World.regrow_start("no_such_crop")==0.0,"regrow_start of an empty/unknown kind is 0")
	for kind:String in HAND_SEASON_TEXT:
		expect(World.crop_season_text(kind)==str(HAND_SEASON_TEXT[kind]),"%s: crop_season_text '%s' == hand '%s'"%[kind,World.crop_season_text(kind),str(HAND_SEASON_TEXT[kind])])
	var cell:=Vector2i(36,34)
	var spring:=0.0
	var summer:=14.0*DAY
	var winter:=42.0*DAY
	var young:={"kind":"tomato","growth":30.0,"wet":true,"remaining":3}
	var ripe:={"kind":"tomato","growth":120.0,"wet":false,"remaining":3}
	expect(World.plot_dormant(young,{},"home",cell,spring),"plot_dormant: unripe tomato in spring is dormant")
	expect(not World.plot_dormant(young,{"type":"greenhouse_roof","owner":TOKEN,"items":{}},"home",cell,spring),"plot_dormant: a greenhouse roof keeps it growing")
	expect(World.plot_dormant(young,{"type":"roof","owner":TOKEN,"items":{}},"home",cell,spring),"plot_dormant: an ordinary roof does not lift dormancy")
	expect(not World.plot_dormant(young,{},"home",cell,summer),"plot_dormant: unripe tomato in summer is not dormant")
	expect(not World.plot_dormant(ripe,{},"home",cell,spring),"plot_dormant: a ripe tomato is never dormant")
	expect(not World.plot_dormant({"kind":"","growth":0.0,"wet":false,"remaining":0},{},"home",cell,spring),"plot_dormant: empty soil is not dormant")
	expect(not World.plot_dormant({"kind":"mist_tea","growth":0.0,"wet":false,"remaining":3},{},TEA_REGION,TEA_BED,winter),"plot_dormant: year-round mist tea is never dormant")
	var bed:Vector2i=FlowerNursery.NURSERY_BEDS.position
	var bluebell:={"kind":"bluebell","growth":10.0,"wet":true,"remaining":1}
	expect(not World.plot_dormant(bluebell,{},FlowerNursery.REGION,bed,summer),"plot_dormant: bluebell on a Tianwei nursery bed grows year-round")
	expect(World.plot_dormant(bluebell,{},"home",cell,summer),"plot_dormant: bluebell at home in summer is dormant")

# ---------------------------------------------------------------- 2. world A
func test_world_a() -> void:
	var wa=new_world("rhythm.json")
	rhythm(wa,"strawberry",0,"home",Vector2i(39,34),false)
	rhythm(wa,"mist_tea",1,TEA_REGION,TEA_BED,false)
	rhythm(wa,"tomato",14,"home",Vector2i(36,34),false)
	rhythm(wa,"cucumber",15,"home",Vector2i(37,34),true)
	rhythm(wa,"eggplant",17,"home",Vector2i(38,34),false)
	old_save(wa,18)
	area_harvest(wa,21)

func rhythm(wd,kind:String,day:int,region:String,cell:Vector2i,reload_mid:bool) -> void:
	var label:="%s rhythm"%kind
	if not go_to(wd,float(day)*DAY+START_OFFSET,"%s: reach day %d"%[label,day+1]):return
	expect(in_season(kind,day) and not rainy(day),"%s: day %d is in season (%s) and not rainy"%[label,day+1,season_name(day)])
	if not buy_seed(wd,kind,label):return
	if not sow(wd,region,cell,kind,label,planted_message(kind,true)):return
	refuse(wd,"harvest",cell,"",MSG_DRY,label+": harvest right after sowing")
	var need:float=crop_time(kind)
	var regrow:float=float(HAND_REGROW[kind])
	var have_start:int=held(wd,kind)
	var harvested:=0
	var count:=0
	for c in range(3):
		var tag:="%s harvest %d/3"%[kind,c+1]
		var expected_start:float=0.0 if c==0 else need-regrow
		var plot:Dictionary=plot_at(wd,region,cell)
		expect(float(plot.get("growth",-1.0))==expected_start,"%s: growth starts at %.2f (got %s)"%[tag,expected_start,str(plot.get("growth"))])
		expect(int(plot.get("remaining",-1))==3-c,"%s: remaining %d (got %s)"%[tag,3-c,str(plot.get("remaining"))])
		if c>0:
			if not advance(wd,UNWATERED_PROBE,tag+": unwatered step"):return
			plot=plot_at(wd,region,cell)
			expect(float(plot.get("growth",-1.0))==expected_start and plot.get("wet",true)==false,"%s: no growth without water (%s)"%[tag,str(plot)])
			refuse(wd,"harvest",cell,"",MSG_DRY,tag+": harvest before re-watering")
		var watered_at:float=now_of(wd)
		if c==1 and reload_mid:
			if not water(wd,region,cell,tag+": water before the reload"):return
			if not advance(wd,30.0,tag+": part of the regrow"):return
			reload_check(wd,region,cell,tag+" mid-regrow reload")
		var gained:int=ripen_and_harvest(wd,region,cell,kind,tag)
		if gained<0:return
		var wet_seconds:float=now_of(wd)-watered_at
		expect(wet_seconds==need-expected_start,"%s: ripened after exactly %.2f wet seconds (took %.2f)"%[tag,need-expected_start,wet_seconds])
		if c>0:expect(wet_seconds==regrow,"%s: regrowth took exactly regrow %.2f s"%[tag,regrow])
		harvested+=gained
		count+=1
	expect(count==3,"%s: exactly three harvests"%label)
	expect(harvested==crop_yield(kind)*3 and held(wd,kind)-have_start==crop_yield(kind)*3,"%s: lifetime harvest %d == 3*%d and inventory +%d"%[label,harvested,crop_yield(kind),held(wd,kind)-have_start])
	if not buy_seed(wd,kind,label+": replant"):return
	sow(wd,region,cell,kind,label+": replant on the emptied plot",planted_message(kind,true))

## A committed action saves; a fresh World reads the save back.
func reload_check(wd,region:String,cell:Vector2i,label:String) -> void:
	var saved:Dictionary=do_act(wd,"water",cell)
	expect(bool(saved.get("ok",false)),"%s: committed action (water) saves the world"%label)
	var loaded=World.new()
	var read_ok:bool=loaded.load_world(str(wd.save_path))
	loaded.save_path="" # PRESET (never write from the read-back copy)
	expect(read_ok and not bool(loaded.recovered_from_backup),"%s: fresh World loads the save"%label)
	compare_plot(plot_at(loaded,region,cell),plot_at(wd,region,cell),label)
	expect(float(loaded.state.time)==now_of(wd),"%s: reloaded time %.2f == live %.2f"%[label,float(loaded.state.time),now_of(wd)])

func old_save(wa,day:int) -> void:
	var cell:=Vector2i(36,36)
	var k:String=World.key(cell)
	var label:="old save"
	if not go_to(wa,float(day)*DAY+START_OFFSET,label+": reach day %d"%(day+1)):return
	expect(in_season("tomato",day) and not rainy(day),"%s: day %d is a dry summer day"%[label,day+1])
	if not buy_seed(wa,"tomato",label):return
	if not sow(wa,"home",cell,"tomato",label,planted_message("tomato",true)):return
	if ripen_and_harvest(wa,"home",cell,"tomato",label+": first tomato harvest")<0:return
	# The harvest act saved the world; build save files from the game's own JSON.
	var text:String=FileAccess.get_file_as_string(str(wa.save_path))
	var parsed=JSON.parse_string(text)
	expect(parsed is Dictionary,"%s: the live save parses as a JSON object"%label)
	if not parsed is Dictionary:return
	var base:Dictionary=parsed
	var base_crops:Dictionary=base.get("crops",{})
	expect(base_crops.has(k),"%s: the saved home crops contain %s"%[label,k])
	if not base_crops.has(k):return
	# Old saves reset a regrowing crop to growth 0 after a harvest.
	var old:Dictionary=base.duplicate(true)
	var old_crops:Dictionary=old["crops"]
	var old_plot:Dictionary=old_crops[k]
	old_plot["growth"]=0.0 # PRESET (fabricated pre-T048 save)
	var old_path:=dir.path_join("old_regrow.json")
	if not write_json(old_path,old):return
	var wo=World.new()
	var read_ok:bool=wo.load_world(old_path)
	expect(read_ok,"%s: a save with growth 0 below regrow_start loads"%label)
	if not read_ok:return
	wo.save_path=dir.path_join("old_regrow_loaded.json") # PRESET (separate save file)
	wo.add_player(TOKEN,"農")
	var plot:Dictionary=plot_at(wo,"home",cell)
	expect(str(plot.get("kind",""))=="tomato" and float(plot.get("growth",-1.0))==0.0 and int(plot.get("remaining",-1))==2,"%s: loaded plot tomato growth 0 remaining 2 (%s)"%[label,str(plot)])
	var watered_at:float=now_of(wo)
	var gained:int=ripen_and_harvest(wo,"home",cell,"tomato",label+": old-style regrow")
	expect(gained==2,"%s: the old-style plot is harvested (+%d)"%[label,gained])
	expect(now_of(wo)-watered_at==crop_time("tomato"),"%s: growth below regrow_start keeps growing to the full time (%.2f s)"%[label,now_of(wo)-watered_at])
	# Load rejects remaining 0 or remaining above the crop's cycles.
	load_variant(base,k,"control",{},true)
	load_variant(base,k,"tomato remaining 3",{"remaining":3},true)
	load_variant(base,k,"tomato remaining 0",{"remaining":0},false)
	load_variant(base,k,"tomato remaining 4",{"remaining":4},false)
	# Single-harvest crop (radish; pumpkin would also trip the bakery gate): 1 loads, 2 is rejected.
	load_variant(base,k,"radish remaining 1",{"kind":"radish","remaining":1},true)
	load_variant(base,k,"radish remaining 2",{"kind":"radish","remaining":2},false)

func load_variant(base:Dictionary,k:String,tag:String,changes:Dictionary,want:bool) -> void:
	var variant:Dictionary=base.duplicate(true)
	var layer:Dictionary=variant["crops"]
	var plot:Dictionary=layer[k]
	for field:String in changes:
		plot[field]=changes[field] # PRESET (fabricated save)
	var path:=dir.path_join("variant-%s.json"%tag.replace(" ","_"))
	if not write_json(path,variant):return
	var probe=World.new()
	var read_ok:bool=probe.load_world(path)
	probe.save_path="" # PRESET (never write)
	expect(read_ok==want,"save variant '%s': load_world returns %s (got %s)"%[tag,str(want),str(read_ok)])

func area_harvest(wa,day:int) -> void:
	var label:="area harvester"
	var twin:=Vector2i(40,35)
	var area_tomato:=Vector2i(42,35)
	var area_cucumber:=Vector2i(44,35)
	var center:=Vector2i(43,35)
	var machine_stand:=Vector2(43.5,36.5)
	if not go_to(wa,float(day)*DAY+START_OFFSET,label+": reach day %d"%(day+1)):return
	expect(in_season("tomato",day) and in_season("cucumber",day) and not rainy(day),"%s: day %d is a dry summer day"%[label,day+1])
	give_items(wa,{"harvester":1,"charcoal":5})
	for job:Array in [["tomato",twin],["tomato",area_tomato],["cucumber",area_cucumber]]:
		var kind:String=job[0]
		var cell:Vector2i=job[1]
		if not buy_seed(wa,kind,label):return
		if not sow(wa,"home",cell,kind,"%s %s"%[label,World.key(cell)],planted_message(kind,true)):return
	var tomato_before:int=held(wa,"tomato")
	var cucumber_before:int=held(wa,"cucumber")
	for c in range(3):
		var tag:="%s cycle %d/3"%[label,c+1]
		for cell:Vector2i in [twin,area_tomato,area_cucumber]:
			if not water(wa,"home",cell,tag):return
		var tomato_wait:float=crop_time("tomato") if c==0 else float(HAND_REGROW["tomato"])
		if not advance(wa,tomato_wait,tag+": tomatoes ripen"):return
		place(wa,"home",stand_of("home",twin))
		var manual:Dictionary=do_act(wa,"harvest",twin)
		expect(bool(manual.get("ok",false)),"%s: manual tomato harvest, got '%s'"%[tag,str(manual.get("message",""))])
		place(wa,"home",machine_stand)
		var cut:Dictionary=do_act(wa,"harvest_area",center)
		var cut_cells:int=2 if c==0 else 1
		expect(bool(cut.get("ok",false)) and str(cut.get("message","")).contains("收割 %d 格"%cut_cells),"%s: harvester cuts %d plots, got '%s'"%[tag,cut_cells,str(cut.get("message",""))])
		var by_hand:Dictionary=plot_at(wa,"home",twin)
		var by_machine:Dictionary=plot_at(wa,"home",area_tomato)
		compare_plot(by_machine,by_hand,tag+": machine tomato vs manual tomato")
		if c<2:
			expect(float(by_machine.get("growth",-1.0))==hand_regrow_start("tomato") and int(by_machine.get("remaining",-1))==2-c and by_machine.get("wet",true)==false,"%s: machine tomato growth time-regrow, remaining %d, dry (%s)"%[tag,2-c,str(by_machine)])
		else:
			expect(str(by_machine.get("kind","?"))=="" and float(by_machine.get("growth",-1.0))==0.0 and int(by_machine.get("remaining",-1))==0,"%s: machine tomato plot empty after the third cut (%s)"%[tag,str(by_machine)])
		if c>0:
			var waiting:Dictionary=plot_at(wa,"home",area_cucumber)
			expect(float(waiting.get("growth",-1.0))==hand_regrow_start("cucumber")+float(HAND_REGROW["tomato"]) and int(waiting.get("remaining",-1))==3-c,"%s: cucumber not ripe yet and skipped (%s)"%[tag,str(waiting)])
			var rest:float=float(HAND_REGROW["cucumber"])-float(HAND_REGROW["tomato"])
			if not advance(wa,rest,tag+": cucumber ripens"):return
			var second:Dictionary=do_act(wa,"harvest_area",center)
			expect(bool(second.get("ok",false)) and str(second.get("message","")).contains("收割 1 格"),"%s: harvester cuts the cucumber, got '%s'"%[tag,str(second.get("message",""))])
		var cucumber_plot:Dictionary=plot_at(wa,"home",area_cucumber)
		if c<2:
			expect(str(cucumber_plot.get("kind",""))=="cucumber" and float(cucumber_plot.get("growth",-1.0))==hand_regrow_start("cucumber") and int(cucumber_plot.get("remaining",-1))==2-c and cucumber_plot.get("wet",true)==false,"%s: machine cucumber growth time-regrow, remaining %d, dry (%s)"%[tag,2-c,str(cucumber_plot)])
		else:
			expect(str(cucumber_plot.get("kind","?"))=="" and float(cucumber_plot.get("growth",-1.0))==0.0 and int(cucumber_plot.get("remaining",-1))==0,"%s: machine cucumber plot empty after the third cut (%s)"%[tag,str(cucumber_plot)])
	expect(held(wa,"tomato")-tomato_before==12,"%s: tomatoes +12 (6 by hand, 6 by machine), got %d"%[label,held(wa,"tomato")-tomato_before])
	expect(held(wa,"cucumber")-cucumber_before==6,"%s: cucumbers +6, got %d"%[label,held(wa,"cucumber")-cucumber_before])
	expect(held(wa,"charcoal")==0,"%s: five machine passes used five charcoal (left %d)"%[label,held(wa,"charcoal")])

# ---------------------------------------------------------------- 3/4/8. world B
func make_entry(kind:String,cell:Vector2i,mode:String,d0:int) -> Dictionary:
	var back:=-1
	for d in range(d0+1,d0+1+112):
		if in_season(kind,d):
			back=d
			break
	return {"kind":kind,"cell":cell,"mode":mode,"d0":d0,"ret":back,"growth":0.0,"rem":0,"h":0.0,
		"harvests":0,"gained":0,"rain_refused":false,"done":false}

func label_of(e:Dictionary) -> String:
	var cell:Vector2i=e["cell"]
	return "%s %s@%s"%[str(e["kind"]),str(e["mode"]),World.key(cell)]

func test_world_b() -> void:
	wb=new_world("dormancy.json")
	entries=[
		make_entry("strawberry",Vector2i(36,34),"regrow",13),
		make_entry("radish",Vector2i(37,34),"single",13),
		make_entry("tomato",Vector2i(38,34),"regrow",27),
		make_entry("cucumber",Vector2i(39,34),"regrow",27),
		make_entry("cucumber",Vector2i(40,34),"ripe",27),
		make_entry("eggplant",Vector2i(41,34),"regrow",41),
		make_entry("pumpkin",Vector2i(42,34),"single",41),
		make_entry("cabbage",Vector2i(43,34),"single",55),
	]
	for e:Dictionary in entries:
		var kind:String=e["kind"]
		var d0:int=e["d0"]
		expect(in_season(kind,d0) and not in_season(kind,d0+1),"%s: day %d is the last day of its season"%[label_of(e),d0+1])
		if str(e["mode"])!="ripe":
			expect(int(e["ret"])==int(HAND_RETURN[kind]),"%s: season returns on day index %d (hand %d)"%[label_of(e),int(e["ret"]),int(HAND_RETURN[kind])])
	for day in range(13,LAST_DAY+1):
		var t:float=float(day)*DAY
		var returning:Array[Dictionary]=[]
		for e:Dictionary in entries:
			if str(e["mode"])!="ripe" and int(e["ret"])==day:returning.append(e)
		if not returning.is_empty():
			if not go_to(wb,t-1.0,"dormancy: one second before day %d"%(day+1)):break
			for e:Dictionary in returning:check_dormant(e,day-1,true,"one second before its season returns")
		if not go_to(wb,t,"dormancy: midnight into day %d"%(day+1)):break
		for e:Dictionary in entries:
			if int(e["d0"])==day-1:begin_dormancy(e,day)
		for e:Dictionary in returning:finish_entry(e,day)
		if day in SETUP_DAYS:
			if not go_to(wb,t+30.0,"dormancy: early on day %d"%(day+1)):break
			daily_checks(day)
			setup_group(day)
		else:
			if not go_to(wb,t+1200.0,"dormancy: afternoon of day %d"%(day+1)):break
			daily_checks(day)
			if day==TWIN_HARVEST_DAY:harvest_twin(day)
			if day==RELOAD_DAY:reload_dormancy()
	var totals:Dictionary={}
	for e:Dictionary in entries:
		var kind:String=e["kind"]
		totals[kind]=int(totals.get(kind,0))+int(e["gained"])
		if str(e["mode"])=="ripe":
			expect(int(e["harvests"])==1 and int(e["gained"])==crop_yield(kind),"%s: one out-of-season harvest after a year left ripe"%label_of(e))
			continue
		var lifetime:int=crop_cycles(kind)
		expect(bool(e["done"]),"%s: finished after its season returned"%label_of(e))
		expect(int(e["harvests"])==lifetime,"%s: total harvests over its life %d == %d (not reset, not reduced by dormancy)"%[label_of(e),int(e["harvests"]),lifetime])
		expect(int(e["gained"])==crop_yield(kind)*lifetime,"%s: lifetime yield %d == %d"%[label_of(e),int(e["gained"]),crop_yield(kind)*lifetime])
	for kind:String in totals:
		expect(held(wb,kind)==int(totals[kind]),"dormancy: inventory %s %d == harvested %d"%[kind,held(wb,kind),int(totals[kind])])

func check_dormant(e:Dictionary,day:int,probe:bool,why:String) -> void:
	var cell:Vector2i=e["cell"]
	var kind:String=e["kind"]
	var label:="%s day %d (%s, %s)"%[label_of(e),day+1,season_name(day),why]
	var plot:Dictionary=plot_at(wb,"home",cell)
	expect(str(plot.get("kind",""))==kind,"%s: still planted, not withered (%s)"%[label,str(plot)])
	expect(float(plot.get("growth",-1.0))==float(e["growth"]),"%s: growth exactly %.2f (got %s)"%[label,float(e["growth"]),str(plot.get("growth"))])
	expect(int(plot.get("remaining",-1))==int(e["rem"]),"%s: remaining %d (got %s)"%[label,int(e["rem"]),str(plot.get("remaining"))])
	expect(not in_season(kind,day),"%s: out of season"%label)
	expect(dormant_now(wb,"home",cell),"%s: World.plot_dormant is true"%label)
	if rainy(day):
		expect(plot.get("wet",false)==true,"%s: rain wets the dormant plot, still no growth"%label)
	if str(e["mode"])!="ripe" and day==int(e["d0"])+1:
		expect(plot.get("wet",false)==true,"%s: watered on its first dormant day, still no growth"%label)
	if probe:
		place(wb,"home",stand_of("home",cell))
		refuse(wb,"harvest",cell,"",MSG_DORMANT,label+": harvest")

func check_ripe(e:Dictionary,day:int) -> void:
	var cell:Vector2i=e["cell"]
	var kind:String=e["kind"]
	var label:="%s day %d (%s, left ripe)"%[label_of(e),day+1,season_name(day)]
	var plot:Dictionary=plot_at(wb,"home",cell)
	expect(str(plot.get("kind",""))==kind and float(plot.get("growth",-1.0))==crop_time(kind) and int(plot.get("remaining",-1))==3,"%s: stays ripe (growth %.2f, remaining 3): %s"%[label,crop_time(kind),str(plot)])
	expect(not dormant_now(wb,"home",cell),"%s: a ripe crop is not dormant"%label)

func daily_checks(day:int) -> void:
	for e:Dictionary in entries:
		var d0:int=e["d0"]
		if str(e["mode"])=="ripe":
			if day>d0 and day<=TWIN_HARVEST_DAY:check_ripe(e,day)
			elif day>TWIN_HARVEST_DAY:check_dormant(e,day,day==TWIN_HARVEST_DAY+1,"dormant after the out-of-season harvest")
		elif day>d0 and day<int(e["ret"]):
			var probe:bool=day==d0+1
			if rainy(day) and not bool(e["rain_refused"]):
				e["rain_refused"]=true
				probe=true
			check_dormant(e,day,probe,"daily sample")

func begin_dormancy(e:Dictionary,day:int) -> void:
	var cell:Vector2i=e["cell"]
	var kind:String=e["kind"]
	var label:="%s crossed into day %d (%s)"%[label_of(e),day+1,season_name(day)]
	var plot:Dictionary=plot_at(wb,"home",cell)
	expect(not rainy(day),"%s: the first off-season day is not rainy"%label)
	expect(str(plot.get("kind",""))==kind and float(plot.get("growth",-1.0))==float(e["growth"]) and int(plot.get("remaining",-1))==int(e["rem"]),"%s: growth %.2f remaining %d at midnight (%s)"%[label,float(e["growth"]),int(e["rem"]),str(plot)])
	expect(plot.get("wet",true)==false,"%s: soil dried at midnight"%label)
	if str(e["mode"])=="ripe":
		expect(not dormant_now(wb,"home",cell),"%s: ripe crop is not dormant"%label)
		return
	expect(not in_season(kind,day),"%s: now out of season"%label)
	expect(dormant_now(wb,"home",cell),"%s: plot_dormant true at the season change"%label)
	water(wb,"home",cell,label+": water the dormant plot")

func finish_entry(e:Dictionary,day:int) -> void:
	var cell:Vector2i=e["cell"]
	var kind:String=e["kind"]
	var label:="%s season back on day %d (%s)"%[label_of(e),day+1,season_name(day)]
	var plot:Dictionary=plot_at(wb,"home",cell)
	expect(in_season(kind,day) and not rainy(day),"%s: in season and not rainy"%label)
	expect(str(plot.get("kind",""))==kind and float(plot.get("growth",-1.0))==float(e["growth"]) and int(plot.get("remaining",-1))==int(e["rem"]),"%s: growth %.2f and remaining %d kept (%s)"%[label,float(e["growth"]),int(e["rem"]),str(plot)])
	expect(plot.get("wet",true)==false,"%s: soil dried at midnight"%label)
	expect(not dormant_now(wb,"home",cell),"%s: plot_dormant false once its season returns"%label)
	var outstanding:float=crop_time(kind)-float(e["growth"])
	var started:float=now_of(wb)
	var cycles:int=int(e["rem"])
	for c in range(cycles):
		var gained:int=ripen_and_harvest(wb,"home",cell,kind,"%s harvest %d"%[label,int(e["harvests"])+1])
		if gained<0:return
		if c==0:
			expect(now_of(wb)-started==outstanding,"%s: ripened after exactly the outstanding %.2f s (took %.2f)"%[label,outstanding,now_of(wb)-started])
		e["harvests"]=int(e["harvests"])+1
		e["gained"]=int(e["gained"])+gained
	plot=plot_at(wb,"home",cell)
	expect(str(plot.get("kind","?"))=="","%s: plot empty after the last harvest"%label)
	e["done"]=true

func setup_group(day:int) -> void:
	var t:float=float(day)*DAY
	var midnight:float=t+DAY
	var group:Array[Dictionary]=[]
	for e:Dictionary in entries:
		if int(e["d0"])==day:group.append(e)
	expect(not rainy(day),"dormancy setup day %d is not rainy"%(day+1))
	if not go_to(wb,t+START_OFFSET,"dormancy setup day %d"%(day+1)):return
	for e:Dictionary in group:
		var kind:String=e["kind"]
		var cell:Vector2i=e["cell"]
		if not buy_seed(wb,kind,label_of(e)):return
		if not sow(wb,"home",cell,kind,label_of(e)+": in-season sowing",planted_message(kind,true)):return
	for e:Dictionary in group:
		if str(e["mode"])!="regrow":continue
		var gained:int=ripen_and_harvest(wb,"home",e["cell"],str(e["kind"]),label_of(e)+": first harvest in season")
		if gained<0:return
		e["harvests"]=1
		e["gained"]=gained
	for e:Dictionary in group:
		var kind:String=e["kind"]
		var need:float=crop_time(kind)
		var base:=0.0
		var h:=0.0
		var rem:=0
		if str(e["mode"])=="regrow":
			base=hand_regrow_start(kind)
			h=float(HAND_REGROW[kind])/2.0
			rem=2
		elif str(e["mode"])=="single":
			h=need/2.0
			rem=1
		else:
			h=need
			rem=3
		e["h"]=h
		e["base"]=base
		e["growth"]=base+h
		e["rem"]=rem
	group.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a["h"])>float(b["h"]))
	for e:Dictionary in group:
		var cell:Vector2i=e["cell"]
		var target:float=midnight-float(e["h"])
		if not go_to(wb,target,"%s: watering slot %.2f s before midnight"%[label_of(e),float(e["h"])]):return
		var plot:Dictionary=plot_at(wb,"home",cell)
		expect(float(plot.get("growth",-1.0))==float(e["base"]) and plot.get("wet",true)==false,"%s: dry and unchanged at growth %.2f before its last watering (%s)"%[label_of(e),float(e["base"]),str(plot)])
		water(wb,"home",cell,label_of(e)+": last in-season watering")

func harvest_twin(day:int) -> void:
	for e:Dictionary in entries:
		if str(e["mode"])!="ripe":continue
		var cell:Vector2i=e["cell"]
		var kind:String=e["kind"]
		var label:="%s day %d (%s), ripe for %d days"%[label_of(e),day+1,season_name(day),day-int(e["d0"])-1]
		expect(day-int(e["d0"])-1>=56,"%s: left ripe for a whole year"%label)
		expect(not in_season(kind,day),"%s: harvested out of season"%label)
		place(wb,"home",stand_of("home",cell))
		var have:int=held(wb,kind)
		var got:Dictionary=do_act(wb,"harvest",cell)
		expect(bool(got.get("ok",false)),"%s: ripe crop harvests normally out of season, got '%s'"%[label,str(got.get("message",""))])
		if not bool(got.get("ok",false)):return
		var gained:int=held(wb,kind)-have
		expect(gained==crop_yield(kind),"%s: +%d (got %d)"%[label,crop_yield(kind),gained])
		var plot:Dictionary=plot_at(wb,"home",cell)
		expect(str(plot.get("kind",""))==kind and int(plot.get("remaining",-1))==2 and float(plot.get("growth",-1.0))==hand_regrow_start(kind) and plot.get("wet",true)==false,"%s: after the harvest remaining 2, growth time-regrow, dry (%s)"%[label,str(plot)])
		expect(dormant_now(wb,"home",cell),"%s: the regrowing plant is dormant out of season"%label)
		e["harvests"]=int(e["harvests"])+1
		e["gained"]=int(e["gained"])+gained
		e["growth"]=hand_regrow_start(kind)
		e["rem"]=2

func reload_dormancy() -> void:
	var first:Dictionary=entries[0]
	var cell:Vector2i=first["cell"]
	place(wb,"home",stand_of("home",cell))
	var saved:Dictionary=do_act(wb,"water",cell)
	expect(bool(saved.get("ok",false)),"mid-dormancy reload: committed action (water) saves the world")
	var loaded=World.new()
	var read_ok:bool=loaded.load_world(str(wb.save_path))
	loaded.save_path="" # PRESET (never write from the read-back copy)
	expect(read_ok and not bool(loaded.recovered_from_backup),"mid-dormancy reload: fresh World loads the save")
	expect(float(loaded.state.time)==now_of(wb),"mid-dormancy reload: time %.2f == live %.2f"%[float(loaded.state.time),now_of(wb)])
	for e:Dictionary in entries:
		var at:Vector2i=e["cell"]
		compare_plot(plot_at(loaded,"home",at),plot_at(wb,"home",at),"mid-dormancy reload "+label_of(e))
		if str(e["mode"])=="regrow" and int(e["d0"])<RELOAD_DAY and int(e["ret"])>RELOAD_DAY:
			expect(World.plot_dormant(plot_at(loaded,"home",at),{},"home",at,float(loaded.state.time)),"mid-dormancy reload %s: still dormant after reload"%label_of(e))

# ---------------------------------------------------------------- 5/6. world C
func test_world_c() -> void:
	var wc=new_world("greenhouse.json")
	var gh_tomato:=Vector2i(36,34)
	var eggplant_cell:=Vector2i(37,34)
	var radish_cell:=Vector2i(38,34)
	var cabbage_cell:=Vector2i(39,34)
	var gh_first:=Vector2i(40,34)
	var strawberry_cell:=Vector2i(41,34)
	var label:="greenhouse"
	if not go_to(wc,START_OFFSET,label+": day 1"):return
	expect(season_name(0)=="spring" and not rainy(0),"%s: day 1 is a dry spring day"%label)
	for kind:String in ["tomato","tomato","eggplant","cabbage","radish","strawberry"]:
		if not buy_seed(wc,kind,label):return
	if not sow(wc,"home",gh_tomato,"tomato","out-of-season tomato",planted_message("tomato",false)):return
	expect(planted_message("tomato",false)=="種下太陽番茄。現在不是它的季節，會休眠到夏季再生長。","hand wording for the dormant tomato")
	sow(wc,"home",eggplant_cell,"eggplant","out-of-season eggplant",planted_message("eggplant",false))
	sow(wc,"home",cabbage_cell,"cabbage","out-of-season cabbage",planted_message("cabbage",false))
	sow(wc,"home",radish_cell,"radish","in-season radish",planted_message("radish",true))
	sow(wc,"home",strawberry_cell,"strawberry","in-season strawberry",planted_message("strawberry",true))
	expect(dormant_now(wc,"home",gh_tomato) and dormant_now(wc,"home",eggplant_cell) and dormant_now(wc,"home",cabbage_cell),"%s: out-of-season sowings are dormant"%label)
	expect(not dormant_now(wc,"home",radish_cell) and not dormant_now(wc,"home",strawberry_cell),"%s: in-season sowings are not dormant"%label)
	# A dormant outdoor tomato does not grow even when watered.
	if not water(wc,"home",gh_tomato,label):return
	if not advance(wc,100.0,label+": watered dormant tomato"):return
	expect(float(plot_at(wc,"home",gh_tomato).get("growth",-1.0))==0.0,"%s: dormant tomato stays at growth 0"%label)
	refuse(wc,"harvest",gh_tomato,"",MSG_DORMANT,label+": dormant tomato harvest")
	# Move it into a greenhouse: build the glass roof over the plot.
	give_items(wc,{"glass":4,"copper_joint":2})
	place(wc,"home",stand_of("home",gh_tomato))
	var glass_before:int=held(wc,"glass")
	var joint_before:int=held(wc,"copper_joint")
	var built:Dictionary=do_act(wc,"build",gh_tomato,"greenhouse_roof")
	expect(bool(built.get("ok",false)),"%s: build a greenhouse roof over the dormant tomato, got '%s'"%[label,str(built.get("message",""))])
	if not bool(built.get("ok",false)):return
	expect(str(roof_at(wc,"home",gh_tomato).get("type",""))=="greenhouse_roof","%s: roof is a greenhouse_roof"%label)
	expect(held(wc,"glass")==glass_before-2 and held(wc,"copper_joint")==joint_before-1,"%s: roof uses 2 glass and 1 copper joint"%label)
	expect(not dormant_now(wc,"home",gh_tomato),"%s: plot_dormant false under the greenhouse"%label)
	refuse(wc,"harvest",gh_tomato,"","還沒成熟，再等 120 秒",label+": unripe greenhouse tomato")
	var gained:int=ripen_and_harvest(wc,"home",gh_tomato,"tomato",label+": out-of-season tomato under glass")
	expect(gained==2,"%s: greenhouse tomato harvested out of season (+%d)"%[label,gained])
	var person:Dictionary=wc.state.players[TOKEN]
	expect(str(person.get("greenhouse_cross_season_crop",""))=="tomato","%s: cross-season greenhouse harvest recorded"%label)
	expect(not dormant_now(wc,"home",gh_tomato),"%s: regrowing tomato under glass is not dormant"%label)
	# Grow part of the regrow under glass, then take the glass away.
	if not water(wc,"home",gh_tomato,label+": regrow under glass"):return
	if not advance(wc,30.0,label+": 30 s of regrow under glass"):return
	var kept:float=hand_regrow_start("tomato")+30.0
	expect(float(plot_at(wc,"home",gh_tomato).get("growth",-1.0))==kept,"%s: growth %.2f under glass"%[label,kept])
	place(wc,"home",stand_of("home",gh_tomato))
	glass_before=held(wc,"glass")
	joint_before=held(wc,"copper_joint")
	var removed:Dictionary=do_act(wc,"remove",gh_tomato)
	expect(bool(removed.get("ok",false)),"%s: remove the greenhouse roof over the growing tomato, got '%s'"%[label,str(removed.get("message",""))])
	if bool(removed.get("ok",false)):
		expect(roof_at(wc,"home",gh_tomato).is_empty(),"%s: roof gone"%label)
		expect(held(wc,"glass")==glass_before+2 and held(wc,"copper_joint")==joint_before+1,"%s: roof materials refunded"%label)
		var plot:Dictionary=plot_at(wc,"home",gh_tomato)
		expect(str(plot.get("kind",""))=="tomato" and float(plot.get("growth",-1.0))==kept and int(plot.get("remaining",-1))==2,"%s: tomato kept with growth %.2f and 2 harvests left (%s)"%[label,kept,str(plot)])
		expect(dormant_now(wc,"home",gh_tomato),"%s: unripe out-of-season tomato is dormant again without glass"%label)
		refuse(wc,"harvest",gh_tomato,"",MSG_DORMANT,label+": harvest after removing the glass")
		if water(wc,"home",gh_tomato,label+": water without glass"):
			if advance(wc,200.0,label+": 200 s without glass"):
				expect(float(plot_at(wc,"home",gh_tomato).get("growth",-1.0))==kept,"%s: growth stays %.2f without glass"%[label,kept])
	# Greenhouse first, then sow: the ordinary wording.
	place(wc,"home",stand_of("home",gh_first))
	var hoed:Dictionary=do_act(wc,"hoe",gh_first)
	expect(bool(hoed.get("ok",false)),"%s: hoe the second plot"%label)
	var built_first:Dictionary=do_act(wc,"build",gh_first,"greenhouse_roof")
	expect(bool(built_first.get("ok",false)),"%s: build a greenhouse roof on empty farmland, got '%s'"%[label,str(built_first.get("message",""))])
	if bool(built_first.get("ok",false)):
		if sow(wc,"home",gh_first,"tomato","tomato sown under glass in spring",planted_message("tomato",true)):
			expect(not dormant_now(wc,"home",gh_first),"%s: tomato sown under glass is not dormant"%label)
			ripen_and_harvest(wc,"home",gh_first,"tomato",label+": tomato sown under glass")
	absent_owner(wc,radish_cell,strawberry_cell)

func absent_owner(wc,radish_cell:Vector2i,strawberry_cell:Vector2i) -> void:
	var label:="absent owner"
	wc.add_player(FRIEND,"友")
	expect(wc.active_tokens.has(TOKEN) and wc.active_tokens.has(FRIEND),"%s: owner and friend both online"%label)
	if not water(wc,"home",radish_cell,label):return
	if not water(wc,"home",strawberry_cell,label):return
	var t0:float=now_of(wc)
	var today:int=int(Weather.day_index(t0))
	expect(in_season("radish",today) and in_season("strawberry",today),"%s: radish and strawberry are in season"%label)
	# Nobody on the island: the session passes active=false, nothing happens.
	wc.active_tokens.clear() # PRESET (everyone offline)
	var stepped:bool=wc.step(500.0,false)
	expect(stepped and now_of(wc)==t0,"%s: step with nobody present leaves time at %.2f (got %.2f)"%[label,t0,now_of(wc)])
	expect(float(plot_at(wc,"home",radish_cell).get("growth",-1.0))==0.0 and float(plot_at(wc,"home",strawberry_cell).get("growth",-1.0))==0.0,"%s: nothing grows with nobody present"%label)
	# The friend comes online, the owner stays offline.
	wc.add_player(FRIEND,"友")
	expect(wc.active_tokens.has(FRIEND) and not wc.active_tokens.has(TOKEN),"%s: only the friend is online"%label)
	var radish_time:float=crop_time("radish")
	var strawberry_time:float=crop_time("strawberry")
	if not advance(wc,radish_time-1.0,label+": radish nearly ripe"):return
	expect(float(plot_at(wc,"home",radish_cell).get("growth",-1.0))==radish_time-1.0,"%s: owner's radish grows while the owner is offline"%label)
	if not advance(wc,1.0,label+": radish ripe"):return
	if not advance(wc,strawberry_time-radish_time-1.0,label+": strawberry nearly ripe"):return
	expect(float(plot_at(wc,"home",strawberry_cell).get("growth",-1.0))==strawberry_time-1.0,"%s: owner's strawberry grows while the owner is offline"%label)
	expect(float(plot_at(wc,"home",radish_cell).get("growth",-1.0))==radish_time,"%s: ripe radish is capped at its time"%label)
	if not advance(wc,1.0,label+": strawberry ripe"):return
	# Leave both ripe through several days, rain and the change into summer.
	if not go_to(wc,20.0*DAY+600.0,label+": day 21 (summer)"):return
	expect(season_name(20)=="summer","%s: day 21 is summer"%label)
	var straw:Dictionary=plot_at(wc,"home",strawberry_cell)
	var radish:Dictionary=plot_at(wc,"home",radish_cell)
	expect(str(straw.get("kind",""))=="strawberry" and float(straw.get("growth",-1.0))==strawberry_time and int(straw.get("remaining",-1))==3,"%s: strawberry still ripe after days offline (%s)"%[label,str(straw)])
	expect(str(radish.get("kind",""))=="radish" and float(radish.get("growth",-1.0))==radish_time and int(radish.get("remaining",-1))==1,"%s: radish still ripe after days offline (%s)"%[label,str(radish)])
	expect(not dormant_now(wc,"home",strawberry_cell) and not dormant_now(wc,"home",radish_cell),"%s: ripe crops are not dormant out of season"%label)
	# The owner comes back and harvests.
	wc.add_player(TOKEN,"農")
	expect(wc.active_tokens.has(TOKEN),"%s: owner back online"%label)
	place(wc,"home",stand_of("home",strawberry_cell))
	var have:int=held(wc,"strawberry")
	var got:Dictionary=do_act(wc,"harvest",strawberry_cell)
	expect(bool(got.get("ok",false)) and held(wc,"strawberry")-have==2,"%s: owner harvests the ripe strawberry in summer, got '%s'"%[label,str(got.get("message",""))])
	straw=plot_at(wc,"home",strawberry_cell)
	expect(int(straw.get("remaining",-1))==2 and float(straw.get("growth",-1.0))==hand_regrow_start("strawberry"),"%s: strawberry remaining 2, growth time-regrow (%s)"%[label,str(straw)])
	expect(dormant_now(wc,"home",strawberry_cell),"%s: the regrowing strawberry is dormant in summer"%label)
	place(wc,"home",stand_of("home",radish_cell))
	have=held(wc,"radish")
	got=do_act(wc,"harvest",radish_cell)
	expect(bool(got.get("ok",false)) and held(wc,"radish")-have==1,"%s: owner harvests the ripe radish in summer, got '%s'"%[label,str(got.get("message",""))])
	expect(str(plot_at(wc,"home",radish_cell).get("kind","?"))=="","%s: radish plot empty"%label)

# ---------------------------------------------------------------- cleanup
func cleanup() -> void:
	var access:=DirAccess.open(dir)
	if access!=null:
		for file_name in access.get_files():
			DirAccess.remove_absolute(dir.path_join(file_name))
	DirAccess.remove_absolute(dir)
