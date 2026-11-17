extends SceneTree
## T049／T093 作物成長與價格的一致性檢查（純資料：不建立 World、不讀寫存檔）。
## 模型與沒有算進去的項目見 scripts/crop_economy.gd 檔頭。實際 World 的買種、種植、
## 收成、出售在 tests/test_crop_economy_world.gd。

const Econ=preload("res://scripts/crop_economy.gd")
const World=preload("res://scripts/world.gd")
const Weather=preload("res://scripts/weather.gd")
const Audit=preload("res://scripts/economy_audit.gd")

## 手算的對照表（不經過 Econ）：[一包種到底的收成數, 淨收益, 成長總秒數]。
const HAND:={
	"radish":[1,12,90],"lettuce":[1,14,75],"wheat":[2,20,120],"carrot":[1,22,105],"potato":[2,35,150],
	"tomato":[6,113,240],"pumpkin":[1,80,270],"cauliflower":[1,50,210],"sweet_corn":[2,10,210],
	"strawberry":[6,146,378],"cucumber":[6,92,280],"cabbage":[1,50,210],"sugar_beet":[1,36,165],
	"star_mushroom":[2,36,165],"sweet_potato":[2,36,165],"eggplant":[6,114,330],"rice":[2,30,165],
	"watermelon":[1,70,270],"ginger":[2,51,210],"cotton":[2,44,210],"mist_tea":[6,163,378],
	"bluebell":[2,28,150],"orange_blossom":[2,28,150],"chime_herb":[1,24,120],
}
## 手算的料理毛利（成品出貨價 − 材料出貨價，只列材料全是作物的幾道）。
const HAND_MARGINS:={"soup":16,"bread":10,"salad":16,"baked_potato":12,"carrot_soup":16,"cucumber_salad":8,
	"roasted_sweet_potato":14,"eggplant_rice":17,"mist_tea_brew":12,"watermelon_platter":17}

var checks:=0
var failures:=0

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _initialize() -> void:
	test_plan_table()
	test_detects_changes()
	test_rows()
	test_growth_times()
	test_regrow()
	test_seasons()
	test_season_growth_rule()
	test_recipes()
	report()
	print("CROP ECONOMY crops=%d checks=%d failures=%d"%[World.CROPS.size(),checks,failures])
	quit(1 if failures else 0)

## 遊戲的作物表與規劃書第 09 章逐欄相同。
func test_plan_table() -> void:
	expect(Econ.PLAN.size()==24,"the plan table has 24 crops (%d)"%Econ.PLAN.size())
	expect(World.CROPS.size()==24,"the game has 24 crops (%d)"%World.CROPS.size())
	for kind:String in Econ.PLAN:
		expect(World.CROPS.has(kind),"plan crop exists in the game: %s"%kind)
		var plan:Dictionary=Econ.PLAN[kind]
		expect(int(plan.days)>=2 and int(plan.days)<=6 and int(plan.seed)>0 and int(plan["yield"])>=1 and int(plan.price)>0,"plan row is sane: %s"%kind)
		for season in plan.seasons:
			expect(season in Weather.SEASONS,"plan season is a real season: %s %s"%[kind,str(season)])
	for kind:String in World.CROPS:
		expect(Econ.PLAN.has(kind),"game crop exists in the plan: %s"%kind)
	var differences:Array=Econ.plan_differences()
	expect(differences.is_empty(),"game crop data equals the plan table: %s"%str(differences))
	for kind:String in Econ.PLAN_REGROW:
		expect(Econ.PLAN.has(kind),"regrow crop is in the plan table: %s"%kind)
	for kind:String in Econ.PLACES:
		expect(World.CROPS.has(kind),"place-restricted crop exists: %s"%kind)

## 檢查器本身：把資料改壞，逐項都要亮。
func test_detects_changes() -> void:
	var seasons:Dictionary=World.CROP_SEASONS.duplicate(true)
	var cases:=[["price",29,"radish: price"],["seed_price",13,"radish: seed price"],["yield",2,"radish: yield"],["cycles",3,"radish: harvests"],["name","蘿蔔","radish: name"]]
	for change:Array in cases:
		var altered:Dictionary=World.CROPS.duplicate(true)
		altered.radish[str(change[0])]=change[1]
		var found:Array=Econ.plan_differences(altered,seasons)
		expect(found.size()==1 and str(found[0]).begins_with(str(change[2])),"changing radish %s is reported once: %s"%[str(change[0]),str(found)])
	var crops:Dictionary=World.CROPS.duplicate(true)
	crops.tomato.erase("cycles")
	var lines:Array=Econ.plan_differences(crops,seasons)
	expect(lines.size()==1 and str(lines[0]).begins_with("tomato: harvests 1 vs plan 3"),"a tomato that no longer regrows is reported: %s"%str(lines))
	crops=World.CROPS.duplicate(true)
	crops.erase("ginger")
	lines=Econ.plan_differences(crops,seasons)
	expect(lines.size()==2 and "ginger: in the plan, missing from the game" in lines and "ginger: has seasons but is not a crop" in lines,"a missing crop is reported: %s"%str(lines))
	crops=World.CROPS.duplicate(true)
	crops["moon_bean"]={"name":"月豆","time":90.0,"price":10,"seed_price":5,"yield":1}
	lines=Econ.plan_differences(crops,seasons)
	expect(lines==["moon_bean: in the game, missing from the plan"],"an extra crop is reported: %s"%str(lines))
	var shifted:Dictionary=World.CROP_SEASONS.duplicate(true)
	shifted.cabbage=["winter","spring"]
	lines=Econ.plan_differences(World.CROPS,shifted)
	expect(lines.size()==1 and str(lines[0]).begins_with("cabbage: seasons"),"an added season is reported: %s"%str(lines))
	shifted=World.CROP_SEASONS.duplicate(true)
	shifted.erase("pumpkin")
	lines=Econ.plan_differences(World.CROPS,shifted)
	expect(lines.size()==1 and str(lines[0]).begins_with("pumpkin: seasons"),"a crop that lost its seasons is reported: %s"%str(lines))
	shifted=World.CROP_SEASONS.duplicate(true)
	shifted["chime_herb"]=["spring"]
	lines=Econ.plan_differences(World.CROPS,shifted)
	expect(lines.size()==1 and str(lines[0]).begins_with("chime_herb: seasons"),"a year-round crop that gained a season is reported: %s"%str(lines))
	# 輸入沒有被改動。
	expect(Econ.plan_differences().is_empty(),"the real tables are still clean after the mutations")
	# 成長時間順序：把 2 天的蘿蔔改得比 6 天的南瓜還久。
	crops=World.CROPS.duplicate(true)
	crops.radish.time=300.0
	var breaks:Array=Econ.time_order_breaks(crops)
	expect(["radish","pumpkin"] in breaks and ["radish","carrot"] in breaks,"a 2-day crop slower than longer crops is reported: %s"%str(breaks))

## 每一列的算術對手算表，且每種作物都有賺。
func test_rows() -> void:
	expect(HAND.size()==World.CROPS.size(),"hand table covers every crop")
	var rows:Array=Econ.rows()
	expect(rows.size()==World.CROPS.size(),"one row per crop")
	var prices:Dictionary=Audit.sale_table()
	var previous:=""
	for row:Dictionary in rows:
		var kind:String=row.kind
		expect(previous<kind,"rows are sorted: %s"%kind)
		previous=kind
		var crop:Dictionary=World.CROPS[kind]
		expect(HAND.has(kind),"hand row exists: %s"%kind)
		var hand:Array=HAND.get(kind,[0,0,0])
		expect(int(row.lifetime)==int(hand[0]),"%s lifetime harvest %d (hand %d)"%[kind,int(row.lifetime),int(hand[0])])
		expect(int(row.profit)==int(hand[1]),"%s profit %d (hand %d)"%[kind,int(row.profit),int(hand[1])])
		expect(is_equal_approx(float(row.grow_seconds),float(hand[2])),"%s growing seconds %.1f (hand %d)"%[kind,float(row.grow_seconds),int(hand[2])])
		expect(int(row.gross)==int(row.lifetime)*int(crop.price) and int(row.profit)==int(row.gross)-int(crop.seed_price),"%s gross and profit add up"%kind)
		expect(is_equal_approx(float(row.profit_per_hour),float(hand[1])*3600.0/float(hand[2])),"%s profit per hour"%kind)
		expect(is_equal_approx(float(row.roi),float(hand[1])/float(crop.seed_price)),"%s return on the seed price"%kind)
		expect(int(row.profit)>0,"%s grown to the end sells for more than its seed (%d)"%[kind,int(row.profit)])
		expect(float(row.time)>0.0 and is_equal_approx(fmod(float(row.time),15.0),0.0),"%s growth time is a positive multiple of 15 s (%.1f)"%[kind,float(row.time)])
		expect(int(row["yield"])>=1 and int(row["yield"])<=2 and int(row.cycles) in [1,3],"%s yield and harvest count are in range"%kind)
		expect(int(prices.get(kind,0))==int(crop.price),"%s ships at its table price"%kind)
		expect(int(row.best_gross)>=int(row.gross),"%s market best is at least the shipping gross"%kind)
		expect(int(row.days_open)==(56 if (row.seasons as Array).is_empty() else 14*(row.seasons as Array).size()),"%s open days per year"%kind)
		expect(str(row.place)==str(Econ.PLACES.get(kind,"")),"%s place"%kind)
		expect(World.NAMES.has(kind) and World.NAMES.has(kind+"_seed"),"%s and its seed have item names"%kind)
		# 同一列用改過的表再算，不會讀到真實表。
	var doubled:Dictionary=World.CROPS.duplicate(true)
	doubled.radish.price=48
	expect(int(Econ.row("radish",doubled).profit)==36 and int(Econ.row("radish").profit)==12,"row() uses the table it is given")
	# 已知、釘住的觀察：甜玉米是每小時淨收益最低的作物，而且不到第二低的一半
	# （規劃書的數字本來如此；它在規劃書的用途「飼料、烤玉米」遊戲裡都還沒有）。
	var by_rate:=rows.duplicate()
	by_rate.sort_custom(func(a:Dictionary,b:Dictionary) -> bool:return float(a.profit_per_hour)<float(b.profit_per_hour))
	expect(str(by_rate[0].kind)=="sweet_corn","the weakest crop per growing hour is sweet corn (%s)"%str(by_rate[0].kind))
	expect(float(by_rate[0].profit_per_hour)*2.0<float(by_rate[1].profit_per_hour),"sweet corn earns less than half of the next weakest (%.0f vs %.0f %s)"%[float(by_rate[0].profit_per_hour),float(by_rate[1].profit_per_hour),str(by_rate[1].kind)])
	expect(str(by_rate[by_rate.size()-1].kind)=="tomato","the strongest crop per growing hour is tomato (%s)"%str(by_rate[by_rate.size()-1].kind))
	# 除了甜玉米，其餘 23 種的每小時淨收益最高與最低相差 3.4–3.6 倍（T048 再生節奏照
	# 規劃書之後由不到 2.5 倍拉大；五種再生作物成為前五名）。釘住，數值一改就會亮。
	var top_rate:float=float(by_rate[by_rate.size()-1].profit_per_hour)
	expect(top_rate<3.6*float(by_rate[1].profit_per_hour) and top_rate>3.4*float(by_rate[1].profit_per_hour),"apart from sweet corn the spread is between 3.4x and 3.6x (%.0f vs %.0f)"%[top_rate,float(by_rate[1].profit_per_hour)])
	var top_five:=[]
	for i in range(by_rate.size()-5,by_rate.size()):top_five.append(str(by_rate[i].kind))
	top_five.sort()
	expect(top_five==Econ.sorted_copy(Econ.PLAN_REGROW),"the five regrowing crops are the five strongest per growing hour: %s"%str(top_five))
	# 種子價不超過一包種到底的收成的一半售價（甜玉米除外）。
	for row:Dictionary in rows:
		if str(row.kind)=="sweet_corn":
			expect(int(row.seed_price)*2>int(row.gross),"sweet corn seed costs more than half of what it sells for (pinned)")
		else:
			expect(int(row.seed_price)*2<=int(row.gross),"%s seed costs at most half of its lifetime sale (%d vs %d)"%[str(row.kind),int(row.seed_price),int(row.gross)])

## 規劃書天數越多，遊戲成長秒數不會越少。
func test_growth_times() -> void:
	expect(Econ.time_order_breaks().is_empty(),"growth seconds follow the plan's day order: %s"%str(Econ.time_order_breaks()))
	var scale:Dictionary=Econ.seconds_per_plan_day()
	expect(scale.size()==24,"every crop has a seconds-per-plan-day figure")
	var lowest:=INF
	var highest:=0.0
	var lowest_kind:=""
	for kind:String in scale:
		var value:float=float(scale[kind])
		if value<lowest:
			lowest=value
			lowest_kind=kind
		highest=maxf(highest,value)
	expect(is_equal_approx(highest,45.0),"the slowest scale is 45 s per plan day (%.2f)"%highest)
	expect(is_equal_approx(lowest,30.0) and lowest_kind=="tomato","the fastest scale is tomato at 30 s per plan day (%s %.2f)"%[lowest_kind,lowest])
	for kind:String in scale:
		if kind!="tomato":expect(float(scale[kind])>=35.0-0.001,"%s is at least 35 s per plan day (%.2f)"%[kind,float(scale[kind])])
	# 最慢的作物也遠短於一個世界日：成長時間本身不會跨午夜變乾。
	for kind:String in World.CROPS:
		expect(float(World.CROPS[kind].time)*4.0<Weather.DAY_SECONDS,"%s matures in under a quarter of a world day"%kind)

func test_regrow() -> void:
	var regrowing:=[]
	for kind:String in World.CROPS:
		if int(World.CROPS[kind].get("cycles",1))>1:regrowing.append(kind)
	regrowing.sort()
	expect(regrowing==Econ.sorted_copy(Econ.PLAN_REGROW),"the regrowing crops are the plan's five: %s"%str(regrowing))
	for kind:String in regrowing:
		expect(int(World.CROPS[kind].cycles)==Econ.PLAN_HARVESTS,"%s gives three harvests"%kind)
	# T048 之後與規劃書相同：首熟後每 2 天（換成該作物自己的秒數）再收一次。
	var schedule:Dictionary=Econ.plan_schedule()
	expect(schedule.size()==5,"five regrow schedules")
	var hand_schedule:={"strawberry":[9,9],"tomato":[8,8],"cucumber":[7,7],"eggplant":[8,8],"mist_tea":[9,9]}
	for kind:String in hand_schedule:
		var entry:Dictionary=schedule.get(kind,{})
		expect(int(entry.get("plan_days",0))==int(hand_schedule[kind][0]) and int(entry.get("game_days",0))==int(hand_schedule[kind][1]),"%s regrow schedule plan %d days vs game-equivalent %d (same as the plan): %s"%[kind,int(hand_schedule[kind][0]),int(hand_schedule[kind][1]),str(entry)])

func test_seasons() -> void:
	var table:Dictionary=Econ.season_table()
	expect(table["all"]==["chime_herb","mist_tea","star_mushroom"],"three crops ignore seasons: %s"%str(table["all"]))
	var hand:={
		"spring":["bluebell","carrot","cauliflower","cotton","lettuce","potato","radish","strawberry","wheat"],
		"summer":["cotton","cucumber","eggplant","lettuce","orange_blossom","rice","sweet_corn","tomato","watermelon","wheat"],
		"autumn":["carrot","eggplant","orange_blossom","pumpkin","radish","rice","sweet_corn","sweet_potato","wheat"],
		"winter":["cabbage","cauliflower","ginger","potato","sugar_beet"],
	}
	for season:String in Weather.SEASONS:
		expect(table[season]==hand[season],"%s crops: %s"%[season,str(table[season])])
		expect((table[season] as Array).size()>=5,"%s has at least five seasonal crops"%season)
		# 每一季都有不受地點限制、種子 25 鈴幣以內的作物，且有再收益不低於蘿蔔的選擇。
		var cheap:=0
		var best_profit:=0
		for kind:String in table[season]:
			if Econ.PLACES.has(kind):continue
			if int(World.CROPS[kind].seed_price)<=25:cheap+=1
			best_profit=maxi(best_profit,int(Econ.row(kind).profit))
		expect(cheap>=1,"%s has a seed for 25 coins or less"%season)
		expect(best_profit>=50,"%s has a crop that nets at least 50 a packet (%d)"%[season,best_profit])
	for kind:String in World.CROP_SEASONS:
		var open:Array=World.CROP_SEASONS[kind]
		expect(World.CROPS.has(kind),"seasonal entry is a crop: %s"%kind)
		expect(not open.is_empty() and open.size()<4,"%s lists one to three seasons"%kind)
		var seen:={}
		for season in open:
			expect(season in Weather.SEASONS and not seen.has(season),"%s season %s is valid and listed once"%[kind,str(season)])
			seen[season]=true
	# 一年 56 天，每季 14 天，順序春夏秋冬。
	expect(Weather.SEASONS==["spring","summer","autumn","winter"] and Weather.DAYS_PER_SEASON==14,"calendar constants")
	for day in 112:
		expect(Weather.season_on_day(float(day))==Weather.SEASONS[(day%56)/14],"day %d season"%day)

## 實際的成長規則（Weather.advance_plot 與 World.crop_grows_in_season）：每種作物在一年
## 56 天的每一天，濕潤的田只在當季（或溫室）成長，而且剛好 time 秒長滿。
func test_season_growth_rule() -> void:
	for kind:String in World.CROPS:
		var need:float=float(World.CROPS[kind].time)
		var open:Array=World.CROP_SEASONS.get(kind,[])
		for day in 56:
			var season:String=Weather.season_on_day(float(day))
			var start:float=float(day)*Weather.DAY_SECONDS+300.0
			var grows:bool=open.is_empty() or season in open
			var result:Dictionary=Weather.advance_plot(true,false,0.0,need,start,need,open,false)
			expect(is_equal_approx(float(result.growth),need if grows else 0.0),"%s day %d (%s): wet plot grows %s"%[kind,day,season,"to maturity" if grows else "not at all"])
			expect(World.crop_grows_in_season(kind,"home",Vector2i(10,10),start)==grows,"%s day %d: World.crop_grows_in_season"%[kind,day])
			if day%14==0:
				# 少一秒還沒熟；乾的田不長；溫室不分季節。
				var short:Dictionary=Weather.advance_plot(true,false,0.0,need,start,need-1.0,open,false)
				expect(float(short.growth)<need,"%s day %d: one second short is not mature"%[kind,day])
				var dry:Dictionary=Weather.advance_plot(false,false,0.0,need,start,need,open,false)
				expect(is_equal_approx(float(dry.growth),0.0),"%s day %d: a dry roofed plot does not grow"%[kind,day])
				var glass:Dictionary=Weather.advance_plot(true,false,0.0,need,start,need,open,true)
				expect(is_equal_approx(float(glass.growth),need),"%s day %d: a greenhouse plot matures in any season"%[kind,day])
				var over:Dictionary=Weather.advance_plot(true,false,0.0,need,start,need*3.0,open,true)
				expect(is_equal_approx(float(over.growth),need),"%s day %d: growth stops at maturity"%[kind,day])
		# 濕潤只到午夜：午夜前 30 秒澆的水只長 30 秒。
		var late:Dictionary=Weather.advance_plot(true,false,0.0,need,Weather.DAY_SECONDS*4.0-30.0,need,[],false)
		expect(is_equal_approx(float(late.growth),30.0) and not bool(late.wet),"%s: a roofed plot watered 30 s before midnight grows 30 s and dries"%kind)

func test_recipes() -> void:
	var rows:Array=Econ.recipe_rows()
	expect(rows.size()==World.RECIPES.size(),"one row per recipe")
	var by_id:={}
	var unpriced:=[]
	for row:Dictionary in rows:
		by_id[str(row.id)]=row
		if not bool(row.priced):
			unpriced.append(str(row.id))
			continue
		expect(int(row.margin)>=0,"cooking %s does not lose sale value (%d -> %d)"%[str(row.id),int(row.in_sale),int(row.out_sale)])
		expect(float(row.time)>0.0,"%s has a cooking time"%str(row.id))
	unpriced.sort()
	# 材料或成品沒有售價的料理（飼料、糖是中間產物；其餘用到麵粉、糖、海鹽或鮮奶）。
	expect(unpriced==["feed","garden_cookie","ginger_tea","pumpkin_pie","salt_grilled_fish","seafood_rice","star_rice_ball","strawberry_jam","strawberry_toast","sugar","tea_pudding"],"recipes with an unpriced ingredient or product: %s"%str(unpriced))
	for id:String in HAND_MARGINS:
		var row:Dictionary=by_id.get(id,{})
		expect(bool(row.get("priced",false)) and int(row.get("margin",-1))==int(HAND_MARGINS[id]),"%s margin %d (hand %d)"%[id,int(row.get("margin",-1)),int(HAND_MARGINS[id])])
	# 把麵包改成賣 30：會被看到是賠的。
	var prices:Dictionary=Audit.sale_table().duplicate()
	prices.bread=30
	for row:Dictionary in Econ.recipe_rows(World.RECIPES,prices):
		if str(row.id)=="bread":expect(int(row.margin)==-8,"a bread price of 30 shows a margin of -8 (%d)"%int(row.margin))

## 不算失敗、給平衡檢查看的表。
func report() -> void:
	var rows:Array=Econ.rows()
	rows.sort_custom(func(a:Dictionary,b:Dictionary) -> bool:return float(a.profit_per_hour)>float(b.profit_per_hour))
	for row:Dictionary in rows:
		print("CROP ROW %s seed=%d harvest=%dx%d price=%d profit=%d grow=%ds per_hour=%.0f roi=%.2f seasons=%s%s"%[str(row.kind),int(row.seed_price),int(row["yield"]),int(row.cycles),int(row.price),int(row.profit),int(row.grow_seconds),float(row.profit_per_hour),float(row.roi),"/".join(row.seasons) if not (row.seasons as Array).is_empty() else "all",(" place="+str(row.place)) if str(row.place)!="" else ""])
	var recipes:Array=Econ.recipe_rows()
	recipes.sort_custom(func(a:Dictionary,b:Dictionary) -> bool:return float(a.margin_per_minute)>float(b.margin_per_minute))
	for row:Dictionary in recipes:
		if bool(row.priced):print("RECIPE ROW %s in=%d out=%d margin=%d time=%ds per_minute=%.0f"%[str(row.id),int(row.in_sale),int(row.out_sale),int(row.margin),int(row.time),float(row.margin_per_minute)])
	print("CROP NOTE seconds per plan day: %s"%str(Econ.seconds_per_plan_day()))
	print("CROP NOTE regrow schedule (plan days vs game-equivalent days): %s"%str(Econ.plan_schedule()))
