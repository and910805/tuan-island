extends RefCounted
## 規劃書第 19 章季節活動「秋季豐收宴」：真正的合作共享大盤。
##
## 渡口野餐後（state.picnic、共餐桌實際有位置），任何人在公告板開一輪；最多 8 位島民
## 在共餐桌報名加入，各自把背包裡的一個基礎作物放進大盤的空格，三個類別（根莖、青菜、
## 金色穀果）都到齊後，已報名者在共餐桌上菜，所有已報名者各得一頁首次完成的紀念
## （player.autumn_feast=true）。沒有計時、沒有鈴幣獎勵，放進大盤的作物不會被取回或移除。
##
## 季節規則（世界時間，Weather 的秋季）：
##   * 尚未完成者：只能在秋天開一輪；已經開始的一輪過了秋天仍可加入、放菜、上菜。
##   * 已完成者（永久紀念）：任何季節都可以從公告板再開一輪。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；失敗時 state 完全不變（先檢查完，最後才寫入）。
##
## 共用 state.autumn_feast（可省略；第一次開始才寫入）
##   {"round":int(1..1000000000), "phase":"collect"|"served",
##    "entries":{slot:item}, "participants":[token,...]（1..8，不重複、必須是現有玩家）}
##   served 時 entries 必須三格齊全並保留；participants 全部已有 player.autumn_feast。
## 個人 player.autumn_feast（可省略）：true＝至少完成過一次。
##
## 動作 ACTION="autumn_feast"，extra：
##   "start"            p＝公告板 BOARD；phase 不是 collect 時開下一輪，開的人自動報名
##   "join:<round>"     p＝共餐桌；報名目前這一輪
##   "give:<round>:<item>" p＝共餐桌；已報名者放一個 item（扣背包一個）到它類別的空格
##   "serve:<round>"    p＝共餐桌；已報名者在三格齊全時上菜
##   <round> 必須是目前這輪的正規十進位（無正負號、無前導零、無空白），過期或重播都會被拒絕。
##
## 公開 API：valid(state)、public_view(state)（不含任何 token）、view(state,token)、
##           apply(state,token,at,extra,home)。

const Weather=preload("res://scripts/weather.gd")
const Community=preload("res://scripts/community.gd")
const Crops=preload("res://scripts/crop_catalog.gd")

const ACTION:="autumn_feast"
const KEY:="autumn_feast"
const VIEW_KEY:="own_autumn_feast"
const BOARD:=Vector2i(40,29)
const REACH:=3.2
const SEASON:="autumn"
const MAX_PLAYERS:=8
const MAX_ROUND:=1000000000
const COLLECT:="collect"
const SERVED:="served"
const IDLE:="idle"
const SLOTS:={
	"roots":{"title":"根莖","items":["radish","carrot","sweet_potato"]},
	"greens":{"title":"青菜","items":["lettuce","cabbage","cauliflower"]},
	"gold":{"title":"金色穀果","items":["wheat","sweet_corn","pumpkin"]},
}
const SHARED_KEYS:=["entries","participants","phase","round"]

const LOCKED:="完成渡口野餐後，秋季豐收宴才會開放。"
const WRONG_REGION:="秋季豐收宴在家園，請回到家園再參加。"
const NO_PLAYER:="請重新加入世界再參加秋季豐收宴。"
const NO_TABLE:="渡口的共餐桌位置被占住了，先把廣場整理出來。"
const BAD_RECORD:="秋季豐收宴的紀錄無法讀取，請重新操作。"
const BAD_EXTRA:="請重新打開秋季豐收宴。"
const WRONG_BOARD:="請走到家園的公告板前開一輪秋季豐收宴。"
const WRONG_TABLE:="請走到風鈴渡口的共餐桌前操作秋季豐收宴。"
const TOO_FAR:="再靠近一點。"
const OFF_SEASON:="秋季豐收宴只在秋天開席；已經完成過的人隨時可以再開一輪。"
const ALREADY_ACTIVE:="大盤正在收集這一輪的食材，到共餐桌報名加入吧。"
const ROUND_LIMIT:="秋季豐收宴的輪數已到上限。"
const STALE:="豐收宴已更新，請重新打開共餐桌。"
const NOT_ACTIVE:="這一輪豐收宴已經上桌了，到公告板開下一輪吧。"
const ALREADY_JOINED:="你已經報名這一輪了。"
const FULL:="這一輪已經有 8 位島民，等下一輪再加入吧。"
const NOT_JOINED:="先在共餐桌報名加入這一輪豐收宴。"
const BAD_ITEM:="大盤只收根莖、青菜和金色穀果的基礎作物。"
const SLOT_TAKEN:="「%s」的位置已經有人放了，換另一類作物吧。"
const NO_STOCK:="背包裡沒有%s可以放。"
const INCOMPLETE:="大盤還缺%s，三類都到齊再上菜。"

static func fresh_shared() -> Dictionary:
	return {"round":0,"phase":IDLE,"entries":{},"participants":[]}

static func unlocked(state:Dictionary) -> bool:
	return state.get("picnic",false)==true and Community.table_cell(state)!=Community.NO_CELL

static func in_season(state:Dictionary) -> bool:
	return Weather.season_on_day(Weather.day_index(state.get("time",0.0)))==SEASON

static func slot_of(item:String) -> String:
	for slot:String in SLOTS:
		if item in SLOTS[slot].items:return slot
	return ""

static func item_name(item:String) -> String:
	return str(Crops.CROPS.get(item,{}).get("name",item))

## 個人紀錄：只有真正的布林 true 才算完成（1、"true" 都不算）。
static func _done(person:Variant) -> bool:
	if not person is Dictionary:return false
	var flag:Variant=person.get(KEY)
	return flag is bool and flag==true

static func _whole(value:Variant,minimum:int,maximum:int) -> bool:
	if not (value is int or value is float):return false
	var number:=float(value)
	return is_finite(number) and floorf(number)==number and number>=float(minimum) and number<=float(maximum)

## 共用紀錄的形狀檢查（不看玩家名單）；通過時回傳正規化後的副本，否則回傳 null。
static func _shared_of(raw:Variant,players:Variant) -> Variant:
	if not raw is Dictionary or raw.size()!=SHARED_KEYS.size():return null
	for field in SHARED_KEYS:
		if not raw.has(field):return null
	if not _whole(raw.round,1,MAX_ROUND):return null
	if not raw.phase is String or raw.phase not in [COLLECT,SERVED]:return null
	if not raw.entries is Dictionary or not raw.participants is Array or not players is Dictionary:return null
	var entries:={}
	for slot in raw.entries:
		if not slot is String or not SLOTS.has(slot):return null
		var item:Variant=raw.entries[slot]
		if not item is String or item not in SLOTS[slot].items:return null
		entries[slot]=item
	var people:Array=[]
	if raw.participants.size()<1 or raw.participants.size()>MAX_PLAYERS:return null
	for token in raw.participants:
		if not token is String or token in people or not players.get(token) is Dictionary:return null
		people.append(token)
	if raw.phase==SERVED:
		if entries.size()!=SLOTS.size():return null
		for token:String in people:
			if not _done(players[token]):return null
	return {"round":int(raw.round),"phase":raw.phase,"entries":entries,"participants":people}

static func _shared(state:Dictionary) -> Variant:
	if not state.has(KEY):return fresh_shared()
	return _shared_of(state[KEY],state.get("players"))

## 存檔檢查：共用紀錄與個人紀錄都可省略（舊存檔）。存在時共用紀錄需野餐已完成、共餐桌
## 實際有位置；個人紀錄只能是 true。通過時把 JSON 讀回的浮點整數正規化為 int。
static func valid(state:Dictionary) -> bool:
	var players:Variant=state.get("players")
	if not players is Dictionary:return false
	for token in players:
		var person:Variant=players[token]
		if person is Dictionary and person.has(KEY) and not _done(person):return false
	if not state.has(KEY):return true
	if state.get("picnic")!=true or Community.table_cell(state)==Community.NO_CELL:return false
	var shared:Variant=_shared_of(state[KEY],players)
	if shared==null:return false
	state[KEY]["round"]=int(shared.round)
	return true

## 公開快照：只有輪次、階段、大盤上的食材 id 與數量；沒有任何 token 或姓名。
static func public_view(state:Dictionary) -> Dictionary:
	var shared:Variant=_shared(state)
	if shared==null or not state.has(KEY):return {"round":0,"phase":IDLE,"entries":{},"count":0,"guests":0}
	var entries:={}
	for slot:String in SLOTS:
		if shared.entries.has(slot):entries[slot]=str(shared.entries[slot])
	return {"round":int(shared.round),"phase":str(shared.phase),"entries":entries,"count":entries.size(),"guests":shared.participants.size()}

## 本人用摘要（Session 以 data.own_autumn_feast 送出）。
static func view(state:Dictionary,token:String) -> Dictionary:
	var open:=unlocked(state)
	var season:=in_season(state)
	var players:Variant=state.get("players",{})
	var person:Variant=players.get(token) if players is Dictionary else null
	var done:=_done(person)
	var shared:Variant=_shared(state)
	var joined:=false
	var running:=false
	var capped:=false
	if shared!=null and state.has(KEY):
		joined=token in shared.participants
		running=shared.phase==COLLECT
		capped=int(shared.round)>=MAX_ROUND
	return {"in_season":season,"unlocked":open,"completed":done,"joined":joined,
		"can_start":open and shared!=null and not running and not capped and (season or done)}

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

## 正規十進位輪次：1..MAX_ROUND、只有數字、沒有前導零；其他一律 -1。
static func _round_text(text:String) -> int:
	if text.is_empty() or text.length()>10 or text.begins_with("0"):return -1
	for i in range(text.length()):
		if text[i]<"0" or text[i]>"9":return -1
	var number:=int(text)
	return number if number>=1 and number<=MAX_ROUND else -1

static func _missing_text(entries:Dictionary) -> String:
	var parts:=PackedStringArray()
	for slot:String in SLOTS:
		if not entries.has(slot):parts.append(str(SLOTS[slot].title))
	return "、".join(parts)

static func apply(state:Dictionary,token:String,at:Vector2i,extra:String,home:bool) -> Dictionary:
	if state.get("picnic",false)!=true:return _fail(LOCKED)
	if not home:return _fail(WRONG_REGION)
	var players:Variant=state.get("players")
	var person:Variant=players.get(token) if players is Dictionary else null
	if not person is Dictionary:return _fail(NO_PLAYER)
	var table:=Community.table_cell(state)
	if table==Community.NO_CELL:return _fail(NO_TABLE)
	if person.has(KEY) and not _done(person):return _fail(BAD_RECORD)
	var shared:Variant=_shared(state)
	if shared==null:return _fail(BAD_RECORD)
	# 解析 extra：動作種類與目前輪次必須是正規字串。
	var kind:=""
	var round_id:=-1
	var item:=""
	if extra=="start":
		kind="start"
	else:
		var parts:=extra.split(":")
		kind=parts[0] if parts.size()>0 else ""
		var expected:=3 if kind=="give" else 2
		if kind not in ["join","give","serve"] or parts.size()!=expected:return _fail(BAD_EXTRA)
		round_id=_round_text(parts[1])
		if round_id<0:return _fail(BAD_EXTRA)
		if kind=="give":
			item=parts[2]
			if slot_of(item).is_empty():return _fail(BAD_ITEM)
	var target:=BOARD if kind=="start" else table
	if at!=target:return _fail(WRONG_BOARD if kind=="start" else WRONG_TABLE)
	var px:=float(person.get("x",0.0))
	var py:=float(person.get("y",0.0))
	if not is_finite(px) or not is_finite(py):return _fail(TOO_FAR)
	if Vector2(px,py).distance_to(Vector2(target)+Vector2(0.5,0.5))>REACH:return _fail(TOO_FAR)
	var done:=_done(person)
	var current:=int(shared.round)
	if kind=="start":
		if shared.phase==COLLECT:return _fail(ALREADY_ACTIVE)
		if not done and not in_season(state):return _fail(OFF_SEASON)
		if current>=MAX_ROUND:return _fail(ROUND_LIMIT)
		state[KEY]={"round":current+1,"phase":COLLECT,"entries":{},"participants":[token]}
		return {"ok":true,"message":"第 %d 輪秋季豐收宴開始備料了！到共餐桌帶上三類作物。"%(current+1)}
	if not state.has(KEY) or round_id!=current:return _fail(STALE)
	if shared.phase!=COLLECT:return _fail(NOT_ACTIVE)
	var people:Array=shared.participants.duplicate()
	var entries:Dictionary=shared.entries.duplicate()
	var joined:bool=token in people
	if kind=="join":
		if joined:return _fail(ALREADY_JOINED)
		if people.size()>=MAX_PLAYERS:return _fail(FULL)
		people.append(token)
		state[KEY]={"round":current,"phase":COLLECT,"entries":entries,"participants":people}
		return {"ok":true,"message":"加入第 %d 輪秋季豐收宴！把背包裡的作物放進大盤吧。"%current}
	if not joined:return _fail(NOT_JOINED)
	if kind=="give":
		var slot:=slot_of(item)
		if entries.has(slot):return _fail(SLOT_TAKEN%SLOTS[slot].title)
		var inventory:Variant=person.get("inventory")
		if not inventory is Dictionary:return _fail(NO_PLAYER)
		var have:Variant=inventory.get(item,0)
		if not (have is int or have is float) or float(have)<1.0:return _fail(NO_STOCK%item_name(item))
		entries[slot]=item
		inventory[item]=int(have)-1
		state[KEY]={"round":current,"phase":COLLECT,"entries":entries,"participants":people}
		var left:=_missing_text(entries)
		return {"ok":true,"message":"放進大盤的「%s」格。%s"%[SLOTS[slot].title,("還缺%s。"%left) if not left.is_empty() else "三類都到齊了，已報名的人可以在共餐桌上菜。"]}
	# serve
	if entries.size()!=SLOTS.size():return _fail(INCOMPLETE%_missing_text(entries))
	for who:String in people:
		if not players.get(who) is Dictionary:return _fail(BAD_RECORD)
	var first_completion:=false
	for who:String in people:
		if not _done(players[who]):first_completion=true
		players[who][KEY]=true
	state[KEY]={"round":current,"phase":SERVED,"entries":entries,"participants":people}
	return {"ok":true,"message":"豐收宴上桌了！第一次參與的島民收下了秋天的紀念。" if first_completion else "豐收宴再次上桌！大家的秋收紀念仍在。"}
