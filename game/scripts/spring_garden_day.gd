extends RefCounted
## 規劃書第 19 章季節活動「春季花園日」（春季花園日）。
##
## 渡口野餐後（state.picnic）在家園公告板報名，走訪三個固定地點、依任意順序蒐集
## 臨時的插畫花牌，回到公告板完成，保留一張首次完成的相簿頁（completed）。
## 不進背包、不給獎勵、不給鈴幣、不動農場、不碰其他玩家與行事曆；單人或多人同時
## 進行都互不影響（紀錄只存在 player.spring_garden）。
##
## 季節規則（世界時間，Weather 的春季＝每 56 天循環的前 14 天）：
##   * 未完成者：只能在春季「第一次開始」；已開始的行程過了春天仍可繼續走完。
##   * 已完成者：任何世界季節都可立刻從公告板重玩。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；失敗時 state 完全不變。
##
## 存檔 player.spring_garden（可省略＝active false、mask 0、completed false）：
##   {"active":bool, "mask":int(0..7), "completed":bool}（三鍵固定）
##   不變式：未進行（active=false）時 mask 必為 0。mask 的位元依 ORDER：
##   bluebell=1、orange=2、herb=4。

const ACTION:="spring_garden"
const KEY:="spring_garden"
const BOARD:=Vector2i(40,29)
const FULL_MASK:=7
const REACH:=3.2
const ORDER:=["bluebell","orange","herb"]
const SPOTS:={
	"bluebell":{"cell":Vector2i(34,28),"title":"鈴蘭花牌","hint":"公告板西邊・廣場草地","item":"bluebell"},
	"orange":{"cell":Vector2i(43,33),"title":"蜜橙花牌","hint":"種子攤南邊・廣場小徑","item":"orange_blossom"},
	"herb":{"cell":Vector2i(39,35),"title":"香草花牌","hint":"公告板南邊・海風小徑","item":"chime_herb"},
}
const Weather=preload("res://scripts/weather.gd")
const RECORD_KEYS:=["active","completed","mask"]

const LOCKED:="完成渡口野餐後，春季花園日才會開放。"
const WRONG_REGION:="春季花園日在家園，請回到家園再參加。"
const NO_PLAYER:="請重新加入世界再參加春季花園日。"
const BAD_RECORD:="春季花園日的紀錄無法讀取，請重新操作。"
const BAD_EXTRA:="請重新操作春季花園日。"
const WRONG_BOARD:="請走到家園的公告板前報名或完成春季花園日。"
const WRONG_SPOT:="這裡不是這張花牌的位置。"
const TOO_FAR:="再靠近一點。"
const OFF_SEASON:="春季花園日只在春天開始；已經完成過的人隨時可以重玩。"
const ALREADY_ACTIVE:="你已經在春季花園日的路上了，去找還沒蒐集的花牌吧。"
const NOT_ACTIVE:="先到公告板報名春季花園日。"
const DUPLICATE:="這張花牌你已經蒐集過了。"
const INCOMPLETE:="還有花牌沒蒐集，三張都蒐集到再回公告板。"

static func fresh() -> Dictionary:
	return {"active":false,"mask":0,"completed":false}

static func unlocked(state:Dictionary) -> bool:
	return state.get("picnic",false)==true

static func in_season(state:Dictionary) -> bool:
	return Weather.season_on_day(Weather.day_index(state.get("time",0.0)))=="spring"

static func has_stamp(mask:int,id:String) -> bool:
	var index:=ORDER.find(id)
	return index>=0 and (mask&(1<<index))!=0

static func stamp_count(mask:int) -> int:
	var count:=0
	for id:String in ORDER:
		if has_stamp(mask,id):count+=1
	return count

## JSON 讀回的 mask 也可以是同值的浮點整數。
static func valid(raw:Variant) -> bool:
	if raw==null:return true
	if not raw is Dictionary or raw.size()!=RECORD_KEYS.size():return false
	for field in RECORD_KEYS:
		if not raw.has(field):return false
	if not raw.active is bool or not raw.completed is bool:return false
	var mask:Variant=raw.mask
	if not (mask is int or mask is float):return false
	var number:=float(mask)
	if not is_finite(number) or floorf(number)!=number or number<0.0 or number>float(FULL_MASK):return false
	if raw.active!=true and int(number)!=0:return false
	return true

static func _record(state:Dictionary,token:String) -> Dictionary:
	var players:Variant=state.get("players",{})
	var person:Variant=players.get(token) if players is Dictionary else null
	if not person is Dictionary:return fresh()
	var found:Variant=person.get(KEY)
	if found is Dictionary and valid(found):
		return {"active":found.active,"mask":int(found.mask),"completed":found.completed}
	return fresh()

## 本人用摘要（Session 以私人資料送出）。
static func view(state:Dictionary,token:String) -> Dictionary:
	var own:=_record(state,token)
	var open:=unlocked(state)
	var season:=in_season(state)
	var active:bool=own.active
	var done:bool=own.completed
	return {"unlocked":open,"in_season":season,"active":active,"mask":int(own.mask),"completed":done,
		"can_start":open and not active and (season or done)}

static func apply(state:Dictionary,token:String,at:Vector2i,extra:String,home:bool) -> Dictionary:
	if not unlocked(state):return _fail(LOCKED)
	if not home:return _fail(WRONG_REGION)
	var players:Variant=state.get("players")
	var person:Variant=players.get(token) if players is Dictionary else null
	if not person is Dictionary:return _fail(NO_PLAYER)
	var own:=fresh()
	if person.has(KEY):
		var raw:Variant=person[KEY]
		if not raw is Dictionary:return _fail(BAD_RECORD)
		own=raw.duplicate()
		if not valid(own):return _fail(BAD_RECORD)
	var at_board:=extra=="start" or extra=="finish"
	if not at_board and not SPOTS.has(extra):return _fail(BAD_EXTRA)
	var target:Vector2i=BOARD if at_board else SPOTS[extra].cell
	if at!=target:return _fail(WRONG_BOARD if at_board else WRONG_SPOT)
	var px:=float(person.get("x",0.0))
	var py:=float(person.get("y",0.0))
	if not is_finite(px) or not is_finite(py):return _fail(TOO_FAR)
	if Vector2(px,py).distance_to(Vector2(target)+Vector2(0.5,0.5))>REACH:return _fail(TOO_FAR)
	var mask:=int(own.mask)
	var message:=""
	if extra=="start":
		if own.active==true:return _fail(ALREADY_ACTIVE)
		if own.completed!=true and not in_season(state):return _fail(OFF_SEASON)
		own.active=true
		own.mask=0
		message="春季花園日開始了！去廣場周圍找三張花牌。"
	elif extra=="finish":
		if own.active!=true:return _fail(NOT_ACTIVE)
		if mask!=FULL_MASK:return _fail(INCOMPLETE)
		var first:bool=own.completed!=true
		own.active=false
		own.mask=0
		own.completed=true
		message="春季花園日完成！三張花牌收進相簿，留下了一頁春天的紀念。" if first else "春季花園日又完成一次！花牌放回花園，相簿頁依舊留著。"
	else:
		if own.active!=true:return _fail(NOT_ACTIVE)
		if has_stamp(mask,extra):return _fail(DUPLICATE)
		own.mask=mask|(1<<ORDER.find(extra))
		var left:=ORDER.size()-stamp_count(int(own.mask))
		message="蒐集到%s！"%SPOTS[extra].title
		message+="還差 %d 張。"%left if left>0 else "三張都到齊了，回公告板完成吧。"
	person[KEY]={"active":own.active==true,"mask":int(own.mask),"completed":own.completed==true}
	return {"ok":true,"message":message}

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}
