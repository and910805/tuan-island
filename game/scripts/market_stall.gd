extends RefCounted
## T071 市集營業（第一批）：風鈴渡口廣場西側的共用「市集攤位」。
##
## 規劃書第 20 章：玩家把農漁產、料理和花擺上自己的攤位；客人依「世界日」與
## 「當天開張的攤位數」產生，不隨在線人數倍增；固定價目表加上一點當日主題加成；
## 固定的營業輪次與庫存上限。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數。每位玩家的紀錄存在自己的
## player.market（第一次成功的市集操作才寫入），舊存檔不需遷移：
##   player.market = {"stock":{item:int}, "open_day":int, "pending":bool,
##                    "till":int, "total":int, "report":{} 或 REPORT_KEYS 六欄}
## 結算由 World.step 呼叫 step(state)，只改 state；離線玩家的攤位也會結算。
##
## 公開 API（伺服器與介面共用；`prices` 省略時用 sale_prices()）：
##   static func sale_prices() -> Dictionary                      # SHIPPING.prices(CROPS,FISH,OTHER_SALES)
##   static func category_of(item:String,prices:Dictionary={}) -> String   # "produce"/"dish"/"flower"/""
##   static func sellable(item:String,prices:Dictionary={}) -> bool
##   static func sellable_items(prices:Dictionary={}) -> Array    # 已排序
##   static func day(now:float) -> int
##   static func theme_of(day:int) -> String
##   static func price_for(base:int,category:String,day:int) -> int
##   static func visitors_for(stalls:int) -> int
##   static func unlocked(snapshot:Dictionary) -> bool
##   static func cell_for(snapshot:Dictionary) -> Vector2i       # 全被佔用時回傳 NO_CELL
##   static func active_cell(snapshot:Dictionary) -> Vector2i    # 未解鎖時回傳 NO_CELL
##   static func record(person:Dictionary) -> Dictionary         # 唯讀，沒有紀錄時回傳 fresh()
##   static func stalls_on(state:Dictionary,day:int) -> int
##   static func view(state:Dictionary,token:String,prices:Dictionary={}) -> Dictionary
##   static func stockable(view:Dictionary,item:String) -> bool
##   static func apply(state:Dictionary,token:String,action:String,extra:String,names:Dictionary={}) -> Dictionary
##   static func step(state:Dictionary,prices:Dictionary={}) -> bool
##   static func valid(market:Variant,now:float,prices:Dictionary) -> bool
## World 另有 World.market_cell(snapshot) 與 World.market_view(token) 包裝。
const SHIPPING=preload("res://scripts/shipping.gd")
const WEATHER=preload("res://scripts/weather.gd")
const CROPS=preload("res://scripts/crop_catalog.gd").CROPS
const FISH=preload("res://scripts/collections.gd").FISH

const ACTIONS:=["market_stock","market_take","market_open","market_collect"]
const NO_CELL:=Vector2i(-1,-1)
## 攤位候選（家園座標），在廣場石板地西緣（path_at 的廣場橢圓內）。依序取第一個
## objects/ground/roofs/crops/forest 都沒有東西的格子，全被佔用時回傳 NO_CELL
## （與 SHIPPING.cell_for 相同），所以舊存檔若已在這些格子蓋了東西不會失效。
## 四格與其 8 鄰格都不碰既有互動點（阿榆 (38,29)、風鈴節訪客 (38,28)、
## 節慶停靠點 (38,30)、共餐桌候選 (39,30)…、出貨箱候選、洛洛／鈴婆婆／棉棉／
## 阿潮站位、公告板、出生點 (39,33) 等）；位於 base_resource 不長樹石的
## 廣場區 (35..45,27..37)，所以本身與正下方都沒有固定的樹或石頭；也不在
## 出生點東側常用的建地 (40,33)、(41,34) 一帶。
const CANDIDATES:=[Vector2i(36,30),Vector2i(36,29),Vector2i(36,31),Vector2i(35,30)]
const LOCKED:="完成渡口野餐後，廣場的市集攤位才會開放。"
const WRONG_REGION:="市集攤位在風鈴渡口的廣場，請回到渡口再擺攤。"
const WRONG_CELL:="請走到廣場西側的市集攤位前再整理攤位。"
const TOO_FAR:="再靠近市集攤位一點，才能整理攤位。"
const NO_STALL:="攤位的位置被占住了，先把廣場西側的空地整理出來。"

const CATEGORY_NAMES:={"produce":"農漁產","dish":"料理","flower":"花"}
const THEMES:=["produce","dish","flower"]
const FLOWERS:=["bluebell","orange_blossom","chime_herb"]
## 有出貨價、但不屬於作物或魚的農牧產品。
const PRODUCE_EXTRA:=["egg","milk","wool"]
## 原料不上市集（只能出貨）。
const RAW:=["wood","stone","fiber","resin"]
const MAX_KINDS:=4
const MAX_STOCK:=12
const MAX_ITEM:=1000000000
const MAX_STALLS:=100000
const REPORT_KEYS:=["coins","day","sold","stalls","theme","visitors"]
const KEYS:=["open_day","pending","report","stock","till","total"]

static var _prices_cache:Dictionary={}

## 出貨價表（與出貨箱相同）。延遲載入 World 的常數，避免互相 preload。
static func sale_prices() -> Dictionary:
	if _prices_cache.is_empty():
		var world_script=load("res://scripts/world.gd")
		_prices_cache=SHIPPING.prices(world_script.CROPS,world_script.FISH,world_script.OTHER_SALES)
	return _prices_cache

static func _table(prices:Dictionary) -> Dictionary:
	return prices if not prices.is_empty() else sale_prices()

## "produce"、"dish"、"flower"；不能擺攤的東西回傳空字串（種子、原料、套件、
## 沒有出貨價的物品）。
static func category_of(item:String,prices:Dictionary={}) -> String:
	if item.is_empty() or item.ends_with("_seed") or item in RAW:return ""
	if not SHIPPING.integer_in(_table(prices).get(item),1,SHIPPING.MAX_COINS):return ""
	if item in FLOWERS:return "flower"
	if CROPS.has(item) or FISH.has(item) or item in PRODUCE_EXTRA:return "produce"
	return "dish"

static func sellable(item:String,prices:Dictionary={}) -> bool:
	return not category_of(item,prices).is_empty()

static func sellable_items(prices:Dictionary={}) -> Array:
	var table:=_table(prices)
	var result:=[]
	for item in table:
		if item is String and sellable(item,table):result.append(item)
	result.sort()
	return result

## 與 RESIDENT_BOND.day 相同的世界日定義（WEATHER.DAY_SECONDS == Village.DAY）。
static func day(now:float) -> int:
	return int(floor(now/WEATHER.DAY_SECONDS))

static func theme_of(day_index:int) -> String:
	return str(THEMES[posmod(day_index,THEMES.size())])

## 市集價＝出貨價 ×1.1 無條件進位；當日主題類別 ×1.3 無條件進位。整數運算。
static func price_for(base:int,category:String,day_index:int) -> int:
	if category==theme_of(day_index):return (base*13+9)/10
	return (base*11+9)/10

## 每個攤位的客人數：1→8、2→5、3→4、4→3、5..7→2、8 以上→1。
static func visitors_for(stalls:int) -> int:
	var count:=maxi(stalls,1)
	return maxi(1,mini(6+2*count,14)/count)

static func unlocked(snapshot:Dictionary) -> bool:
	return snapshot.get("picnic",false)==true

## 第一個沒被佔用的候選格；全被佔用時回傳 NO_CELL。
static func cell_for(snapshot:Dictionary) -> Vector2i:
	for cell:Vector2i in CANDIDATES:
		var tile:="%d,%d"%[cell.x,cell.y]
		var occupied:=false
		for field in ["objects","ground","roofs","crops","forest"]:
			var layer:Variant=snapshot.get(field,{})
			if layer is Dictionary and layer.has(tile):
				occupied=true
				break
		if not occupied:return cell
	return NO_CELL

## 解鎖後的攤位格（保留給攤位，不能建造）；未解鎖時回傳 NO_CELL。
static func active_cell(snapshot:Dictionary) -> Vector2i:
	return cell_for(snapshot) if unlocked(snapshot) else NO_CELL

static func fresh() -> Dictionary:
	return {"stock":{},"open_day":-1,"pending":false,"till":0,"total":0,"report":{}}

## 讀取（不寫入）玩家的攤位紀錄。
static func record(person:Dictionary) -> Dictionary:
	var found:Variant=person.get("market")
	return found if found is Dictionary else fresh()

static func stock_count(stock:Dictionary) -> int:
	var count:=0
	for item in stock:count+=int(stock[item])
	return count

## 指定世界日開張、仍待結算且攤位上有貨的攤位數（不含任何身分）。
static func stalls_on(state:Dictionary,day_index:int) -> int:
	var count:=0
	var players:Variant=state.get("players",{})
	if not players is Dictionary:return 0
	for token in players:
		var person:Variant=players[token]
		if not person is Dictionary:continue
		var market:Variant=person.get("market")
		if not market is Dictionary or market.get("pending")!=true or int(market.get("open_day",-1))!=day_index:continue
		if market.get("stock") is Dictionary and stock_count(market.stock)>0:count+=1
	return count

## 只給本人看的攤位摘要（Session 以 data.own_market 送給本人）。
static func view(state:Dictionary,token:String,prices:Dictionary={}) -> Dictionary:
	var table:=_table(prices)
	var now:=float(state.get("time",0.0))
	var today:=day(now)
	var person:Variant=state.get("players",{}).get(token,{})
	var own:=record(person if person is Dictionary else {})
	var stock:Dictionary=own.get("stock",{}).duplicate(true) if own.get("stock") is Dictionary else {}
	var opened:=int(own.get("open_day",-1))==today
	var stalls:=stalls_on(state,today)
	var price_view:={}
	for item:String in sellable_items(table):
		var category:=category_of(item,table)
		price_view[item]={"base":int(table[item]),"price":price_for(int(table[item]),category,today),"category":category,"themed":category==theme_of(today)}
	var report:Dictionary=own.get("report",{}).duplicate(true) if own.get("report") is Dictionary else {}
	return {"unlocked":unlocked(state),"day":today,"theme":theme_of(today),"next_theme":theme_of(today+1),
		"open":opened,"pending":own.get("pending",false)==true,"stalls_today":stalls,
		"visitors_estimate":visitors_for(maxi(stalls,1)) if opened else visitors_for(stalls+1),
		"stock":stock,"stock_count":stock_count(stock),"till":int(own.get("till",0)),"total":int(own.get("total",0)),
		"prices":price_view,"report":report}

## 介面用：這樣東西現在還能不能再擺上攤位（不檢查背包數量）。
static func stockable(market_view:Dictionary,item:String) -> bool:
	var prices:Variant=market_view.get("prices",{})
	if not prices is Dictionary or not prices.has(item):return false
	var stock:Variant=market_view.get("stock",{})
	if not stock is Dictionary:return false
	if not stock.has(item) and stock.size()>=MAX_KINDS:return false
	return int(market_view.get("stock_count",0))<MAX_STOCK

## "item:count" → {"ok":true,"item":..,"count":..}；格式不對時 ok=false。
static func parse(extra:String) -> Dictionary:
	var parts:=extra.split(":")
	if parts.size()!=2 or parts[0].is_empty() or not parts[1].is_valid_int():return {"ok":false}
	var count:=int(parts[1])
	if str(count)!=parts[1] or count<1 or count>MAX_STOCK:return {"ok":false}
	return {"ok":true,"item":str(parts[0]),"count":count}

## 四個市集動作。呼叫前 World 已確認：已解鎖、在家園、對準攤位格、距離夠近。
## 失敗時不寫入任何東西。
static func apply(state:Dictionary,token:String,action:String,extra:String,names:Dictionary={}) -> Dictionary:
	if not unlocked(state):return _fail(LOCKED)
	var person:Variant=state.get("players",{}).get(token)
	if not person is Dictionary or not person.get("inventory") is Dictionary:return _fail("請重新加入世界再擺攤。")
	if person.has("market") and not person.market is Dictionary:return _fail("攤位紀錄有誤，這次沒有變更。")
	var inv:Dictionary=person.inventory
	var own:Dictionary=record(person).duplicate(true)
	var stock:Dictionary=own.stock
	var today:=day(float(state.get("time",0.0)))
	var message:=""
	if action=="market_stock" or action=="market_take":
		var parsed:=parse(extra)
		if not parsed.ok:return _fail("請重新選擇要%s的物品和數量。"%("上架" if action=="market_stock" else "收回"))
		var item:String=parsed.item
		var count:int=parsed.count
		var label:=str(names.get(item,item))
		if action=="market_stock":
			if not sellable(item):return _fail("%s不能擺上市集攤位；攤位只收農漁產、料理和花。"%label)
			if int(inv.get(item,0))<count:return _fail("背包裡的%s不夠，先去收成或料理再來上架。"%label)
			if not stock.has(item) and stock.size()>=MAX_KINDS:return _fail("攤位最多擺 %d 種東西，先收回一種再上架。"%MAX_KINDS)
			var room:=MAX_STOCK-stock_count(stock)
			if count>room:
				if room<=0:return _fail("攤位已經擺滿 %d 件了，先收回一些再上架。"%MAX_STOCK)
				return _fail("攤位最多擺 %d 件，現在還能再放 %d 件。"%[MAX_STOCK,room])
			inv[item]=int(inv[item])-count
			stock[item]=int(stock.get(item,0))+count
			message="%s ×%d 擺上攤位了。"%[label,count]
		else:
			if int(stock.get(item,0))<count:return _fail("攤位上的%s沒有這麼多，請重新選擇數量。"%label)
			if int(inv.get(item,0))>MAX_ITEM-count:return _fail("背包裡的%s已達上限，先用掉一些再收回。"%label)
			stock[item]=int(stock[item])-count
			if int(stock[item])<=0:stock.erase(item)
			inv[item]=int(inv.get(item,0))+count
			message="收回%s ×%d，放回背包了。"%[label,count]
	elif action=="market_open":
		if not extra.is_empty():return _fail("請重新操作市集攤位。")
		if int(own.open_day)==today:return _fail("今天已經開張了，明天再來開下一輪。")
		if own.pending==true:return _fail("上一輪營業還在結算，稍等一下再開張。")
		if stock_count(stock)<=0:return _fail("攤位上還沒有東西，先上架再開張。")
		own.open_day=today
		own.pending=true
		var stalls:=stalls_on(state,today)+1
		message="攤位開張了！今天的主題是「%s」，預計有 %d 位客人來逛，換日時結算。"%[CATEGORY_NAMES[theme_of(today)],visitors_for(stalls)]
	elif action=="market_collect":
		if not extra.is_empty():return _fail("請重新操作市集攤位。")
		var till:=int(own.till)
		if till<=0:return _fail("錢箱裡還沒有鈴幣，開張營業、換日結算後再來收。")
		if int(person.get("coins",0))>SHIPPING.MAX_COINS-till:return _fail("鈴幣錢包已達上限，先花掉一些再來收。")
		person.coins=int(person.get("coins",0))+till
		own.till=0
		message="從錢箱收下 %d 鈴幣。"%till
	else:
		return _fail("請重新操作市集攤位。")
	own.stock=stock
	person.market=own
	return {"ok":true,"message":message}

## 結算所有「開張日早於今天」且仍待結算的攤位（含離線玩家）。只改 state。
static func step(state:Dictionary,prices:Dictionary={}) -> bool:
	var players:Variant=state.get("players")
	if not players is Dictionary:return false
	var today:=day(float(state.get("time",0.0)))
	var groups:={}
	for token in players:
		var person:Variant=players[token]
		if not person is Dictionary:continue
		var market:Variant=person.get("market")
		if not market is Dictionary or market.get("pending")!=true:continue
		var opened:=int(market.get("open_day",-1))
		if opened>=today:continue
		if not groups.has(opened):groups[opened]=[]
		groups[opened].append(token)
	if groups.is_empty():return false
	var table:=_table(prices)
	for opened:int in groups:
		var stalls:=stalls_on(state,opened)
		for token in groups[opened]:
			_settle(players[token].market,opened,stalls,table)
	return true

static func _settle(market:Dictionary,day_index:int,stalls:int,prices:Dictionary) -> void:
	var stock:Dictionary=market.get("stock",{}) if market.get("stock") is Dictionary else {}
	var theme:=theme_of(day_index)
	var visitors:=visitors_for(stalls) if stock_count(stock)>0 else 0
	var order:=[]
	for item in stock:
		if int(stock[item])>0:order.append(("0" if category_of(item,prices)==theme else "1")+str(item))
	order.sort()
	var items:=[]
	for entry:String in order:items.append(entry.substr(1))
	var sold:={}
	var coins:=0
	var till:=int(market.get("till",0))
	var left:=visitors
	var capped:=false
	while left>0 and not capped:
		var any:=false
		for item:String in items:
			if left<=0:break
			if int(stock.get(item,0))<=0:continue
			var price:=price_for(int(prices.get(item,0)),category_of(item,prices),day_index)
			if till+coins+price>SHIPPING.MAX_COINS:
				capped=true
				break
			stock[item]=int(stock[item])-1
			sold[item]=int(sold.get(item,0))+1
			coins+=price
			left-=1
			any=true
		if not any:break
	for item in stock.keys():
		if int(stock[item])<=0:stock.erase(item)
	market.stock=stock
	market.till=till+coins
	market.total=mini(SHIPPING.MAX_COINS,int(market.get("total",0))+coins)
	market.pending=false
	market.report={"day":day_index,"visitors":visitors,"stalls":stalls,"theme":theme,"sold":sold,"coins":coins}

## 存檔檢查：欄位可省略；存在時型別、上限、只含可擺攤物品。通過時把 JSON 讀回
## 的浮點數正規化為整數。
static func valid(market:Variant,now:float,prices:Dictionary) -> bool:
	if not market is Dictionary or market.size()!=KEYS.size():return false
	for field in KEYS:
		if not market.has(field):return false
	var today:=day(now)
	var stock:Variant=market.stock
	if not stock is Dictionary or stock.size()>MAX_KINDS:return false
	var pieces:=0
	for item in stock:
		if not item is String or not sellable(item,prices) or not _whole(stock[item],1,MAX_STOCK):return false
		pieces+=int(stock[item])
	if pieces>MAX_STOCK:return false
	if not _whole(market.open_day,-1,today) or not market.pending is bool:return false
	if market.pending and int(market.open_day)<0:return false
	if not _whole(market.till,0,SHIPPING.MAX_COINS) or not _whole(market.total,0,SHIPPING.MAX_COINS):return false
	if int(market.till)>int(market.total):return false
	var report:Variant=market.report
	if not report is Dictionary:return false
	if not report.is_empty():
		if report.size()!=REPORT_KEYS.size():return false
		for field in REPORT_KEYS:
			if not report.has(field):return false
		if not _whole(report.day,0,today-1) or int(report.day)>int(market.open_day):return false
		if market.pending and int(report.day)>=int(market.open_day):return false
		if not _whole(report.visitors,0,visitors_for(1)) or not _whole(report.stalls,0,MAX_STALLS):return false
		if not report.theme is String or report.theme!=theme_of(int(report.day)):return false
		if not _whole(report.coins,0,SHIPPING.MAX_COINS):return false
		var sold:Variant=report.sold
		if not sold is Dictionary or sold.size()>MAX_KINDS:return false
		var sold_pieces:=0
		for item in sold:
			if not item is String or not sellable(item,prices) or not _whole(sold[item],1,MAX_STOCK):return false
			sold_pieces+=int(sold[item])
		if sold_pieces>int(report.visitors) or (int(report.visitors)>0 and int(report.stalls)<1):return false
		for field in ["day","visitors","stalls","coins"]:report[field]=int(report[field])
		for item in sold:sold[item]=int(sold[item])
	for item in stock:stock[item]=int(stock[item])
	for field in ["open_day","till","total"]:market[field]=int(market[field])
	return true

static func _whole(value:Variant,minimum:int,maximum:int) -> bool:
	if not (value is int or value is float) or not is_finite(float(value)):return false
	return floorf(float(value))==float(value) and float(value)>=minimum and float(value)<=maximum

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}
