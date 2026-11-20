extends RefCounted
## C12 D14 彩虹蔬菜串 — the 夏季市集 tasting at the 渡口 market booth (content bible D14, source "夏季市集").
##
## It is a real, playable event, not a gift: every summer (WEATHER season "summer", 14 world days, every
## year) the existing 渡口 market stall (market_stall.gd, unlocked by the 渡口野餐) runs a 彩虹串試吃。 The
## player stands at the stall and cooks one demo skewer: 1 紫絨茄子 (a summer crop) plus ONE root
## vegetable chosen from three options, because 奶白蘿蔔 and 糖心胡蘿蔔 only grow in spring / autumn:
##   radish  — hand in 1 奶白蘿蔔            carrot — hand in 1 糖心胡蘿蔔
##   booth   — pay BOOTH_PRICE 鈴幣 for a root bundle the booth stocks for the event (summer alternative)
## The three options are equal for the unlock. The ingredients / coins are consumed, nothing is given
## back (no buy -> sell loop) and the recipe is retained: player.summer_market is a permanent personal
## record, never reset, never reduced, so the dish stays cookable in every later season / year.
##
## Nothing is missable: the event recurs every summer, the year-round market is untouched (this module
## never reads or writes player.market, market theme, prices or the stall cell), and D14 is a side
## recipe, not a progression requirement.
##
## Pure rules. No file access, no clock, no randomness, no World preload (world.gd preloads this).
## A failed apply() writes nothing. Retried requests are answered by World.act's per-request receipt
## (player.receipts[request_id]); a *new* request after success fails with ALREADY and spends nothing.
##
## Public API (state = World.state, token = player id, names = World.NAMES):
##   static func in_season(day:int) -> bool
##   static func days_left(day:int) -> int              # world days of the event left incl. today, 0 out of season
##   static func days_until(day:int) -> int             # 0 in season, else days until the next summer starts
##   static func recipe_known(person:Dictionary) -> bool
##   static func recipe_known_in(snapshot:Dictionary) -> bool   # client: snapshot.own_summer_market.recipe
##   static func gate_entry() -> Dictionary             # {"kind":"market","message","button","tip"} for the C12 stove
##   static func view(state,token,names={}) -> Dictionary      # own-only summary (Session: data.own_summer_market)
##   static func apply(state,token,extra,names={}) -> Dictionary   # {"ok","message"}; extra = a root option id
##   static func valid(record:Variant,now:float) -> bool        # SaveSchema (field may be omitted)
const WEATHER=preload("res://scripts/weather.gd")
const MARKET=preload("res://scripts/market_stall.gd")

const KEY:="summer_market"
const ACTION:="summer_market_taste"
const BUY_ROOTS:="summer_market_roots"
const ROOTS_PRICE:=96
const ROOTS_SOLD_OUT:="你今天已買過一組根菜，明天會再補貨。"
const DISH:="rainbow_skewer"
const SEASON:="summer"
const EGGPLANT:="eggplant"
const BOOTH:="booth"
const BOOTH_PRICE:=30
const ROOT_OPTIONS:=["radish","carrot",BOOTH]
const FALLBACK_NAMES:={"radish":"奶白蘿蔔","carrot":"糖心胡蘿蔔","eggplant":"紫絨茄子","rainbow_skewer":"彩虹蔬菜串"}
const BOOTH_NAME:="攤位的夏季根菜束"
const YEAR_DAYS:=56 # WEATHER.DAYS_PER_SEASON * WEATHER.SEASONS.size()
const RECORD_KEYS:=["day","recipe","root"]

const LOCKED:="完成渡口野餐、開放市集攤位後，夏季市集才會開張。"
const WRONG_REGION:="夏季市集在風鈴渡口的廣場，請回到渡口。"
const WRONG_CELL:="請走到廣場西側的市集攤位前參加試吃。"
const TOO_FAR:="再靠近市集攤位一點，才能參加試吃。"
const ALREADY:="你已經學會彩虹蔬菜串了，可以到公共廚房灶台煮。"
const GATE_MESSAGE:="彩虹蔬菜串要先在夏季市集學會：夏天到渡口市集攤位參加彩虹串試吃（茄子加一種根菜），才能在公共廚房灶台煮。"
const GATE_BUTTON:="夏季市集學會後解鎖"
const GATE_TIP:="（夏季到渡口市集攤位試吃：紫絨茄子 1，加奶白蘿蔔／糖心胡蘿蔔／攤位根菜束其一）"

static func name_of(item:String,names:Dictionary={}) -> String:
	return str(names.get(item,FALLBACK_NAMES.get(item,item)))

static func day_of(time:Variant) -> int:
	return int(WEATHER.day_index(time))

static func in_season(day:int) -> bool:
	return WEATHER.season_on_day(float(day))==SEASON

## World days of this summer left, counting today. 0 outside summer.
static func days_left(day:int) -> int:
	if not in_season(day):return 0
	var into:=posmod(day,YEAR_DAYS)-WEATHER.DAYS_PER_SEASON
	return WEATHER.DAYS_PER_SEASON-into

## 0 during summer, else days from `day` to the first day of the next summer.
static func days_until(day:int) -> int:
	if in_season(day):return 0
	var into:=posmod(day,YEAR_DAYS)
	if into<WEATHER.DAYS_PER_SEASON:return WEATHER.DAYS_PER_SEASON-into
	return YEAR_DAYS-into+WEATHER.DAYS_PER_SEASON

static func recipe_known(person:Dictionary) -> bool:
	var record:Variant=person.get(KEY)
	return record is Dictionary and record.get("recipe") is bool and record.recipe

## Client side: `snapshot` is the viewer's own snapshot (Session attaches own_summer_market).
static func recipe_known_in(snapshot:Dictionary) -> bool:
	var own:Variant=snapshot.get("own_summer_market",{})
	return own is Dictionary and own.get("recipe") is bool and own.recipe

## Same shape as KitchenStove.gate() entries. kind "market" = learned at the 夏季市集 (recipe_known).
static func gate_entry() -> Dictionary:
	return {"kind":"market","message":GATE_MESSAGE,"button":GATE_BUTTON,"tip":GATE_TIP}

static func _person(state:Dictionary,token:String) -> Dictionary:
	var players:Variant=state.get("players",{})
	var person:Variant=players.get(token,{}) if players is Dictionary else {}
	return person if person is Dictionary else {}

static func _bag(person:Dictionary) -> Dictionary:
	var bag:Variant=person.get("inventory",{})
	return bag if bag is Dictionary else {}

static func _root_row(id:String,bag:Dictionary,coins:int,names:Dictionary) -> Dictionary:
	if id==BOOTH:
		return {"id":id,"name":BOOTH_NAME,"price":BOOTH_PRICE,"have":coins,"ok":coins>=BOOTH_PRICE}
	var have:=int(bag.get(id,0))
	return {"id":id,"name":name_of(id,names),"price":0,"have":have,"ok":have>=1}

## Own-only summary. `can_taste` already includes every rule apply() enforces except position.
static func view(state:Dictionary,token:String,names:Dictionary={}) -> Dictionary:
	var person:=_person(state,token)
	var bag:=_bag(person)
	var today:=day_of(state.get("time",0.0))
	var coins:=int(person.get("coins",0))
	var known:=recipe_known(person)
	var record:Variant=person.get(KEY)
	var roots:Array=[]
	for id:String in ROOT_OPTIONS:roots.append(_root_row(id,bag,coins,names))
	var eggplant:=int(bag.get(EGGPLANT,0))
	var unlocked:=MARKET.unlocked(state)
	var season:=in_season(today)
	var roots_sold_out: bool=known and int(record.get("roots_day",-1))==today
	var any_root:=false
	for row:Dictionary in roots:any_root=any_root or bool(row.ok)
	var reason:=""
	if known:reason=ALREADY
	elif not unlocked:reason=LOCKED
	elif not season:reason="夏季市集要等夏天：還有 %d 天。奶白蘿蔔和糖心胡蘿蔔在春秋才長，先留意夏季的茄子。"%days_until(today)
	elif eggplant<1:reason="還缺 1 個%s：夏天種茄子（種子攤有賣），收成後帶來。"%name_of(EGGPLANT,names)
	elif not any_root:reason="還缺一種根菜：帶 1 個蘿蔔或胡蘿蔔，或準備 %d 鈴幣買攤位的根菜束。"%BOOTH_PRICE
	var guidance:=""
	if known:guidance="已學會〈彩虹蔬菜串〉（奶白蘿蔔、糖心胡蘿蔔、紫絨茄子各 1）。可到公共廚房灶台煮，一次 3 份。"
	elif not unlocked:guidance=LOCKED
	elif season:guidance="把夏天的茄子和一種根菜帶來，小栗會教你做彩虹蔬菜串。"
	else:guidance="夏季市集每年夏天開張。距離下個夏天還有 %d 天。"%days_until(today)
	return {"unlocked":unlocked,"in_season":season,"days_left":days_left(today),"days_until":days_until(today),
		"day":today,"recipe":known,"root":str(record.get("root","")) if record is Dictionary and known else "",
		"eggplant":eggplant,"eggplant_name":name_of(EGGPLANT,names),"roots":roots,"price":BOOTH_PRICE,
		"roots_price":ROOTS_PRICE,"roots_sold_out":roots_sold_out,"can_buy_roots":known and season and not roots_sold_out and coins>=ROOTS_PRICE,
		"can_taste":reason.is_empty(),"reason":reason,"guidance":guidance,"dish":DISH,"dish_name":name_of(DISH,names)}

## Learns the recipe. World already checked: HOME region, the stall cell, reach. All-or-nothing: every
## check runs before the first write, so a failure leaves the player byte-identical.
static func apply(state:Dictionary,token:String,extra:String,names:Dictionary={}) -> Dictionary:
	if not MARKET.unlocked(state):return _fail(LOCKED)
	var players:Variant=state.get("players",{})
	var person:Variant=players.get(token) if players is Dictionary else null
	if not person is Dictionary or not person.get("inventory") is Dictionary:return _fail("請重新加入世界再參加試吃。")
	if person.has(KEY) and not valid(person[KEY],float(state.get("time",0.0))):return _fail("夏季市集紀錄有誤，這次沒有變更。")
	if recipe_known(person):return _fail(ALREADY)
	var today:=day_of(state.get("time",0.0))
	if not in_season(today):
		return _fail("夏季市集只在夏天開張，還有 %d 天。學會前不用擔心，每年夏天都會再開。"%days_until(today))
	if extra not in ROOT_OPTIONS:return _fail("請重新選擇一種根菜：蘿蔔、胡蘿蔔或攤位的根菜束。")
	var inv:Dictionary=person.inventory
	if int(inv.get(EGGPLANT,0))<1:return _fail("背包裡沒有%s，夏天收成後再來試吃。"%name_of(EGGPLANT,names))
	var coins:=int(person.get("coins",0))
	if extra==BOOTH:
		if coins<BOOTH_PRICE:return _fail("鈴幣不夠：攤位的根菜束要 %d 鈴幣。"%BOOTH_PRICE)
	elif int(inv.get(extra,0))<1:
		return _fail("背包裡沒有%s，換一種根菜或買攤位的根菜束。"%name_of(extra,names))
	inv[EGGPLANT]=int(inv[EGGPLANT])-1
	if int(inv[EGGPLANT])<=0:inv.erase(EGGPLANT)
	var cost_text:=""
	if extra==BOOTH:
		person.coins=coins-BOOTH_PRICE
		cost_text="付了 %d 鈴幣買根菜束"%BOOTH_PRICE
	else:
		inv[extra]=int(inv[extra])-1
		if int(inv[extra])<=0:inv.erase(extra)
		cost_text="交出 1 個%s"%name_of(extra,names)
	person[KEY]={"recipe":true,"root":extra,"day":today}
	return {"ok":true,"message":"夏季市集試吃：%s和 1 個%s串成彩虹串。學會〈%s〉了！之後隨時能在公共廚房灶台煮。"%[cost_text,name_of(EGGPLANT,names),name_of(DISH,names)]}

static func buy_roots(state: Dictionary, token: String) -> Dictionary:
	var person:=_person(state,token)
	if not MARKET.unlocked(state) or not recipe_known(person):return _fail("先參加夏季市集試吃，再來買根菜組。")
	var now:=float(state.get("time",0.0))
	var record: Dictionary=person[KEY]
	if not valid(record,now):return _fail("夏季市集紀錄有誤，這次沒有變更。")
	var today:=day_of(now)
	if not in_season(today):return _fail("根菜組在夏季市集供應。")
	if int(record.get("roots_day",-1))==today:return _fail(ROOTS_SOLD_OUT)
	var coins:=int(person.get("coins",0))
	if coins<ROOTS_PRICE:return _fail("根菜組要 %d 鈴幣。"%ROOTS_PRICE)
	var bag:=_bag(person)
	for item in ["radish","carrot"]:
		if int(bag.get(item,0))>=1000000000:return _fail("背包的根菜數量已達上限。")
	for item in ["radish","carrot"]:
		bag[item]=int(bag.get(item,0))+1
	person.coins=coins-ROOTS_PRICE
	record["roots_day"]=today
	return {"ok":true,"message":"買到蘿蔔 ×1、胡蘿蔔 ×1，可搭配茄子製作彩虹蔬菜串。"}

## SaveSchema: the optional roots_day keeps today's purchase on the same personal market record.
## Normalises the JSON float day to int.
static func valid(record:Variant,now:float) -> bool:
	if not record is Dictionary or record.size()!=RECORD_KEYS.size()+int(record.has("roots_day")):return false
	for field in RECORD_KEYS:
		if not record.has(field):return false
	if not record.recipe is bool or not record.recipe or not record.root is String or record.root not in ROOT_OPTIONS:return false
	var day_value:Variant=record.day
	if not (day_value is int or day_value is float) or not is_finite(float(day_value)):return false
	if floorf(float(day_value))!=float(day_value) or float(day_value)<0.0 or float(day_value)>float(day_of(now)):return false
	record.day=int(day_value)
	if record.has("roots_day"):
		var roots_day: Variant=record.roots_day
		if not (roots_day is int or roots_day is float) or not is_finite(float(roots_day)) or float(roots_day)!=floorf(float(roots_day)):return false
		if float(roots_day)<float(record.day) or float(roots_day)>float(day_of(now)) or not in_season(int(roots_day)):return false
		record.roots_day=int(roots_day)
	return true

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}
