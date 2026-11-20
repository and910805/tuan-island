extends RefCounted
## 規劃書第 19 章季節活動「夏季海風市集」（夏季海風市集）。
##
## 渡口野餐後（state.picnic）在家園公告板報名「試吃攤輪班」；走到市集攤位
## （Market.active_cell）依序接待三位客人，把他們的描述對到三樣借來的試吃品，
## 回公告板完成，留下一張永久紀念卡（completed）。
## 試吃品只是借來的展示，不碰背包、不給鈴幣、不動市集庫存與其他配方；
## 玩家之間互不影響（紀錄只存在 player.sea_breeze_fair）。
##
## 季節規則（世界時間，Weather 的夏季＝每 56 天循環的第 14..27 天）：
##   * 未完成者：只能在夏季「第一次開始」；已開始的輪班過了夏天仍可繼續。
##   * 已完成者：任何世界季節都可立刻從公告板再排一次班。
##
## 客人順序：DISHES 的插入順序依「開始當天的世界日 mod 3」輪轉，並存成 offset，
## 之後整班固定。第 i 位客人要的是 order[(offset+i)%3]。view 不含答案欄位。
## 錯誤、重複、距離不夠、不在市集攤位前：state 完全不變。
##
## 存檔 player.sea_breeze_fair（可省略＝inactive、served 0、offset 0、completed false）：
##   {"active":bool,"served":int(0..3),"offset":int(0..2),"completed":bool}（四鍵固定）
##   不變式：未進行（active=false）時 served 與 offset 必為 0。JSON 讀回的同值浮點整數也接受。
##
## 公開 API：
##   static func valid(raw:Variant) -> bool
##   static func apply(state,token,at:Vector2i,extra:String,home:bool) -> Dictionary
##   static func view(state,token) -> Dictionary
## extra：「start」「finish」（公告板）、「serve:<dish>」（市集攤位）。

const KEY:="sea_breeze_fair"
const ACTION:="sea_breeze_fair"
const BOARD:=Vector2i(40,29)
const VIEW_KEY:="own_sea_breeze_fair"
const DURATION_GUESTS:=3
const REACH:=3.2
const SERVE_PREFIX:="serve:"
const RECORD_KEYS:=["active","completed","offset","served"]
const DISHES:={
	"watermelon_platter":{"title":"夏日西瓜盤","hint":"冰涼切片"},
	"baked_potato":{"title":"烤馬鈴薯","hint":"爐烤撒鹽"},
	"strawberry_jam":{"title":"草莓果醬","hint":"果香抹醬"},
}
## 每個真正的選項對應一位客人（名字與描述）；描述只講感覺，不直接說出品名。
const GUESTS:={
	"watermelon_platter":{"name":"米露","clue":"我在灶前忙了一上午，想吃點清甜多汁、能消暑的。"},
	"baked_potato":{"name":"阿榆","clue":"剛搬完木板，來份熱騰騰、帶鹹香的點心吧。"},
	"strawberry_jam":{"name":"小栗","clue":"我帶了麵包。有沒有酸酸甜甜、可以抹上去的？"},
}
const Weather=preload("res://scripts/weather.gd")
const Market=preload("res://scripts/market_stall.gd")

const LOCKED:="完成渡口野餐後，夏季海風市集才會開放。"
const WRONG_REGION:="夏季海風市集在家園，請回到家園再參加。"
const NO_PLAYER:="請重新加入世界再參加夏季海風市集。"
const BAD_RECORD:="夏季海風市集的紀錄無法讀取，請重新操作。"
const BAD_EXTRA:="請重新操作夏季海風市集。"
const WRONG_BOARD:="請走到家園的公告板前報名或完成夏季海風市集。"
const WRONG_COUNTER:="請走到廣場西側的市集攤位前接待客人。"
const TOO_FAR:="再靠近一點。"
const OFF_SEASON:="夏季海風市集只在夏天開始；已經完成過的人隨時可以再排班。"
const ALREADY_ACTIVE:="你已經在輪班了，繼續接待客人吧。"
const NOT_ACTIVE:="先到公告板報名夏季海風市集。"
const DUPLICATE:="這份試吃品剛才已經送過了。"
const WRONG_DISH:="客人搖搖頭，這不是他想要的。"
const ALL_SERVED:="三位客人都接待完了，回公告板完成輪班吧。"
const INCOMPLETE:="還有客人在等，三位都接待完再回公告板。"

static func fresh() -> Dictionary:
	return {"active":false,"served":0,"offset":0,"completed":false}

static func unlocked(state:Dictionary) -> bool:
	return state.get("picnic",false)==true

static func in_season(state:Dictionary) -> bool:
	return Weather.season_on_day(Weather.day_index(state.get("time",0.0)))=="summer"

## 以世界日 mod 3 輪轉後的上菜順序。
static func order_for(offset:int) -> Array:
	var keys:=DISHES.keys()
	var result:=[]
	for i in range(keys.size()):
		result.append(keys[posmod(offset+i,keys.size())])
	return result

static func _whole(value:Variant,low:int,high:int) -> bool:
	if not (value is int or value is float):return false
	var number:=float(value)
	if not is_finite(number) or floorf(number)!=number:return false
	return number>=float(low) and number<=float(high)

## 嚴格檢查存檔紀錄；null（沒有紀錄）也合法。
static func valid(raw:Variant) -> bool:
	if raw==null:return true
	if not raw is Dictionary or raw.size()!=RECORD_KEYS.size():return false
	for field in RECORD_KEYS:
		if not raw.has(field):return false
	if not raw.active is bool or not raw.completed is bool:return false
	if not _whole(raw.served,0,DURATION_GUESTS) or not _whole(raw.offset,0,DISHES.size()-1):return false
	if raw.active!=true and (int(raw.served)!=0 or int(raw.offset)!=0):return false
	return true

static func _record(state:Dictionary,token:String) -> Dictionary:
	var players:Variant=state.get("players",{})
	var person:Variant=players.get(token) if players is Dictionary else null
	if not person is Dictionary:return fresh()
	var found:Variant=person.get(KEY)
	if found is Dictionary and valid(found):
		return {"active":found.active,"served":int(found.served),"offset":int(found.offset),"completed":found.completed}
	return fresh()

## 本人用摘要（Session 以 VIEW_KEY 私人送出）；不含答案欄位。
static func view(state:Dictionary,token:String) -> Dictionary:
	var own:=_record(state,token)
	var open:=unlocked(state)
	var season:=in_season(state)
	var active:bool=own.active
	var done:bool=own.completed
	var served:int=own.served
	var phase:="idle"
	if active:phase="visit" if served<DURATION_GUESTS else "return"
	var result:={"unlocked":open,"in_season":season,"active":active,"completed":done,
		"can_start":open and not active and (season or done),"served":served,"phase":phase}
	if phase=="visit":
		var dish:String=order_for(int(own.offset))[served]
		result["guest"]={"name":GUESTS[dish].name,"clue":GUESTS[dish].clue}
	return result

static func apply(state:Dictionary,token:String,at:Vector2i,extra:String,home:bool) -> Dictionary:
	if not unlocked(state):return _fail(LOCKED)
	if not home:return _fail(WRONG_REGION)
	var players:Variant=state.get("players")
	var person:Variant=players.get(token) if players is Dictionary else null
	if not person is Dictionary:return _fail(NO_PLAYER)
	var own:=fresh()
	if person.has(KEY):
		var raw:Variant=person[KEY]
		if not raw is Dictionary or not valid(raw):return _fail(BAD_RECORD)
		own={"active":raw.active,"served":int(raw.served),"offset":int(raw.offset),"completed":raw.completed}
	var serving:=extra.begins_with(SERVE_PREFIX)
	var dish:=extra.substr(SERVE_PREFIX.length()) if serving else ""
	if serving:
		if not DISHES.has(dish):return _fail(BAD_EXTRA)
	elif extra!="start" and extra!="finish":
		return _fail(BAD_EXTRA)
	var target:=BOARD
	if serving:
		target=Market.active_cell(state)
		if target==Market.NO_CELL or at!=target:return _fail(WRONG_COUNTER)
	elif at!=BOARD:
		return _fail(WRONG_BOARD)
	var px:=float(person.get("x",0.0))
	var py:=float(person.get("y",0.0))
	if not is_finite(px) or not is_finite(py):return _fail(TOO_FAR)
	if Vector2(px,py).distance_to(Vector2(target)+Vector2(0.5,0.5))>REACH:return _fail(TOO_FAR)
	var message:=""
	if extra=="start":
		if own.active==true:return _fail(ALREADY_ACTIVE)
		if own.completed!=true and not in_season(state):return _fail(OFF_SEASON)
		own.active=true
		own.served=0
		own.offset=posmod(int(Weather.day_index(state.get("time",0.0))),DISHES.size())
		message="海風市集開張！到市集攤位接待三位客人。"
	elif extra=="finish":
		if own.active!=true:return _fail(NOT_ACTIVE)
		if int(own.served)<DURATION_GUESTS:return _fail(INCOMPLETE)
		var first:bool=own.completed!=true
		own.active=false
		own.served=0
		own.offset=0
		own.completed=true
		message="夏季海風市集完成！紀念卡收好了。" if first else "又完成一班！紀念卡依舊留著。"
	else:
		if own.active!=true:return _fail(NOT_ACTIVE)
		var served:int=own.served
		if served>=DURATION_GUESTS:return _fail(ALL_SERVED)
		var order:=order_for(int(own.offset))
		if order.find(dish)<served:return _fail(DUPLICATE)
		if dish!=order[served]:return _fail(WRONG_DISH)
		own.served=served+1
		var left:=DURATION_GUESTS-int(own.served)
		message="%s滿意地收下了%s。"%[GUESTS[dish].name,DISHES[dish].title]
		message+="還有 %d 位。"%left if left>0 else "客人都招呼完了，回公告板吧。"
	person[KEY]={"active":own.active==true,"served":int(own.served),"offset":int(own.offset),"completed":own.completed==true}
	return {"ok":true,"message":message}

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}
