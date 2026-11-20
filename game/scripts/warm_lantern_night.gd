extends RefCounted
## 規劃書第 19 章季節活動「冬季暖燈夜」：三盞路燈、三句心願的合作點燈。
##
## 渡口野餐後（state.picnic），任何人在公告板開一輪；最多 8 位島民在公告板報名加入，
## 已報名者各自走到三處路燈（林徑燈、南路燈、港路燈）旁，為每盞燈選一句心願點亮；三盞都亮後，
## 已報名者回公告板「完成暖燈夜」，所有已報名者各得一枚永久紀念（player.warm_lantern_night=true）。
## 沒有鈴幣、背包或時鐘的副作用；沒有黃昏限制（畫面在夜裡較亮，但白天也能參加）；可隨時完成。
## 完成後燈與心願留在世界裡，直到下一輪開始才清空。
##
## 季節規則（世界時間，Weather 的冬季）：
##   * 尚未完成者：只能在冬天開一輪；已經開始的一輪過了冬天仍可加入、點燈、完成。
##   * 已完成者（永久紀念）：任何季節都可以從公告板再開一輪。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；失敗時 state 完全不變（先檢查完，最後才寫入）。
##
## 共用 state.warm_lantern_night（可省略；第一次開始才寫入）
##   {"round":int(1..1000000000), "phase":"lighting"|"celebrated",
##    "lamps":{station:wish_id}, "participants":[token,...]（1..8，不重複、必須是現有玩家）}
##   celebrated 時三盞燈必須齊全並保留；participants 全部已有 player.warm_lantern_night。
## 個人 player.warm_lantern_night（可省略）：true＝至少完成過一次。
##
## 動作 ACTION="warm_lantern_night"，extra：
##   "start"                         at＝公告板 BOARD；phase 不是 lighting 時開下一輪，開的人自動報名
##   "join:<round>"                  at＝公告板；報名目前這一輪
##   "light:<round>:<station>:<wish>" at＝該路燈格；已報名者點亮一盞還沒亮的燈
##   "finish:<round>"                at＝公告板；已報名者在三盞都亮後完成
##   <round> 必須是目前這輪的正規十進位（無正負號、無前導零、無空白），過期或重播都會被拒絕。
##
## 公開 API：valid(state)、public_view(state)（不含任何 token）、view(state,token)、
##           apply(state,token,at,extra,home)。

const Weather=preload("res://scripts/weather.gd")

const ACTION:="warm_lantern_night"
const KEY:="warm_lantern_night"
const VIEW_KEY:="own_warm_lantern_night"
const BOARD:=Vector2i(40,29)
const REACH:=3.2
const SEASON:="winter"
const MAX_PLAYERS:=8
const MAX_ROUND:=1000000000
const LIGHTING:="lighting"
const CELEBRATED:="celebrated"
const IDLE:="idle"
const STATIONS:={
	"grove":{"cell":Vector2i(34,27),"title":"林徑燈","hint":"公告板西北・林邊"},
	"lane":{"cell":Vector2i(44,35),"title":"南路燈","hint":"種子攤南邊・海風小徑"},
	"harbor":{"cell":Vector2i(49,32),"title":"港路燈","hint":"廣場東邊・往河邊"},
}
const WISHES:={
	"home":"願每盞燈都照得到回家的路。",
	"harvest":"願來年田裡也有足夠的收成。",
	"friends":"願下次相聚時，還能聽到大家的笑聲。",
}
const SHARED_KEYS:=["lamps","participants","phase","round"]

const LOCKED:="完成渡口野餐後，冬季暖燈夜才會開放。"
const WRONG_REGION:="冬季暖燈夜在家園，請回到家園再參加。"
const NO_PLAYER:="請重新加入世界再參加冬季暖燈夜。"
const BAD_RECORD:="冬季暖燈夜的紀錄無法讀取，請重新操作。"
const BAD_EXTRA:="請重新打開冬季暖燈夜。"
const WRONG_BOARD:="請走到家園的公告板前操作冬季暖燈夜。"
const WRONG_STATION:="請走到%s（%s）旁點燈。"
const TOO_FAR:="再靠近一點。"
const OFF_SEASON:="冬季暖燈夜只在冬天開始；已經完成過的人隨時可以再點一輪。"
const ALREADY_ACTIVE:="這一輪的燈還在點，到公告板報名加入吧。"
const ROUND_LIMIT:="冬季暖燈夜的輪數已到上限。"
const STALE:="暖燈夜已更新，請重新打開公告板。"
const NOT_ACTIVE:="這一輪暖燈夜已經圓滿了，到公告板開下一輪吧。"
const ALREADY_JOINED:="你已經報名這一輪了。"
const FULL:="這一輪已經有 8 位島民，等下一輪再加入吧。"
const NOT_JOINED:="先在公告板報名加入這一輪暖燈夜。"
const ALREADY_LIT:="「%s」已經亮著了，去點還沒亮的燈吧。"
const INCOMPLETE:="還有燈沒亮：%s。三盞都亮了再回公告板完成。"

static func fresh_shared() -> Dictionary:
	return {"round":0,"phase":IDLE,"lamps":{},"participants":[]}

static func unlocked(state:Dictionary) -> bool:
	return state.get("picnic",false)==true

static func in_season(state:Dictionary) -> bool:
	return Weather.season_on_day(Weather.day_index(state.get("time",0.0)))==SEASON

## 個人紀錄：只有真正的布林 true 才算完成（1、"true" 都不算）。
static func _done(person:Variant) -> bool:
	if not person is Dictionary:return false
	var flag:Variant=person.get(KEY)
	return flag is bool and flag==true

static func _whole(value:Variant,minimum:int,maximum:int) -> bool:
	if not (value is int or value is float):return false
	var number:=float(value)
	return is_finite(number) and floorf(number)==number and number>=float(minimum) and number<=float(maximum)

## 共用紀錄的形狀檢查；通過時回傳正規化後的副本，否則回傳 null。
static func _shared_of(raw:Variant,players:Variant) -> Variant:
	if not raw is Dictionary or raw.size()!=SHARED_KEYS.size():return null
	for field in SHARED_KEYS:
		if not raw.has(field):return null
	if not _whole(raw.round,1,MAX_ROUND):return null
	if not raw.phase is String or raw.phase not in [LIGHTING,CELEBRATED]:return null
	if not raw.lamps is Dictionary or not raw.participants is Array or not players is Dictionary:return null
	var lamps:={}
	for station in raw.lamps:
		if not station is String or not STATIONS.has(station):return null
		var wish:Variant=raw.lamps[station]
		if not wish is String or not WISHES.has(wish):return null
		lamps[station]=wish
	var people:Array=[]
	if raw.participants.size()<1 or raw.participants.size()>MAX_PLAYERS:return null
	for token in raw.participants:
		if not token is String or token in people or not players.get(token) is Dictionary:return null
		people.append(token)
	if raw.phase==CELEBRATED:
		if lamps.size()!=STATIONS.size():return null
		for token:String in people:
			if not _done(players[token]):return null
	return {"round":int(raw.round),"phase":raw.phase,"lamps":lamps,"participants":people}

static func _shared(state:Dictionary) -> Variant:
	if not state.has(KEY):return fresh_shared()
	return _shared_of(state[KEY],state.get("players"))

## 存檔檢查：共用紀錄與個人紀錄都可省略。共用紀錄存在時需野餐已完成；個人紀錄只能是 true。
## 通過時把 JSON 讀回的浮點整數輪次正規化為 int。
static func valid(state:Dictionary) -> bool:
	var players:Variant=state.get("players")
	if not players is Dictionary:return false
	for token in players:
		var person:Variant=players[token]
		if person is Dictionary and person.has(KEY) and not _done(person):return false
	if not state.has(KEY):return true
	if state.get("picnic")!=true:return false
	var shared:Variant=_shared_of(state[KEY],players)
	if shared==null:return false
	state[KEY]["round"]=int(shared.round)
	return true

## 公開快照：只有輪次、階段、燈上的心願 id 與參加人數；沒有任何 token 或姓名。
static func public_view(state:Dictionary) -> Dictionary:
	var shared:Variant=_shared(state)
	if shared==null or not state.has(KEY):return {"round":0,"phase":IDLE,"lamps":{},"guests":0}
	var lamps:={}
	for station:String in STATIONS:
		if shared.lamps.has(station):lamps[station]=str(shared.lamps[station])
	return {"round":int(shared.round),"phase":str(shared.phase),"lamps":lamps,"guests":shared.participants.size()}

## 本人用摘要（Session 以 data.own_warm_lantern_night 送出）。
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
		running=shared.phase==LIGHTING
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

static func _unlit_text(lamps:Dictionary) -> String:
	var parts:=PackedStringArray()
	for station:String in STATIONS:
		if not lamps.has(station):parts.append(str(STATIONS[station].title))
	return "、".join(parts)

static func apply(state:Dictionary,token:String,at:Vector2i,extra:String,home:bool) -> Dictionary:
	if state.get("picnic",false)!=true:return _fail(LOCKED)
	if not home:return _fail(WRONG_REGION)
	var players:Variant=state.get("players")
	var person:Variant=players.get(token) if players is Dictionary else null
	if not person is Dictionary:return _fail(NO_PLAYER)
	if person.has(KEY) and not _done(person):return _fail(BAD_RECORD)
	var shared:Variant=_shared(state)
	if shared==null:return _fail(BAD_RECORD)
	# 解析 extra：動作種類與輪次必須是正規字串。
	var kind:=""
	var round_id:=-1
	var station:=""
	var wish:=""
	if extra=="start":
		kind="start"
	else:
		var parts:=extra.split(":")
		kind=parts[0] if parts.size()>0 else ""
		var expected:=4 if kind=="light" else 2
		if kind not in ["join","light","finish"] or parts.size()!=expected:return _fail(BAD_EXTRA)
		round_id=_round_text(parts[1])
		if round_id<0:return _fail(BAD_EXTRA)
		if kind=="light":
			station=parts[2]
			wish=parts[3]
			if not STATIONS.has(station) or not WISHES.has(wish):return _fail(BAD_EXTRA)
	var target:Vector2i=STATIONS[station].cell if kind=="light" else BOARD
	if at!=target:
		return _fail(WRONG_STATION%[STATIONS[station].title,STATIONS[station].hint] if kind=="light" else WRONG_BOARD)
	var px:=float(person.get("x",0.0))
	var py:=float(person.get("y",0.0))
	if not is_finite(px) or not is_finite(py):return _fail(TOO_FAR)
	if Vector2(px,py).distance_to(Vector2(target)+Vector2(0.5,0.5))>REACH:return _fail(TOO_FAR)
	var done:=_done(person)
	var current:=int(shared.round)
	if kind=="start":
		if shared.phase==LIGHTING:return _fail(ALREADY_ACTIVE)
		if not done and not in_season(state):return _fail(OFF_SEASON)
		if current>=MAX_ROUND:return _fail(ROUND_LIMIT)
		state[KEY]={"round":current+1,"phase":LIGHTING,"lamps":{},"participants":[token]}
		return {"ok":true,"message":"第 %d 輪冬季暖燈夜開始了！到林徑、南路和港路三盞燈旁許願點燈。"%(current+1)}
	if not state.has(KEY) or round_id!=current:return _fail(STALE)
	if shared.phase!=LIGHTING:return _fail(NOT_ACTIVE)
	var people:Array=shared.participants.duplicate()
	var lamps:Dictionary=shared.lamps.duplicate()
	var joined:bool=token in people
	if kind=="join":
		if joined:return _fail(ALREADY_JOINED)
		if people.size()>=MAX_PLAYERS:return _fail(FULL)
		people.append(token)
		state[KEY]={"round":current,"phase":LIGHTING,"lamps":lamps,"participants":people}
		return {"ok":true,"message":"加入第 %d 輪冬季暖燈夜！去三盞路燈旁許願點燈吧。"%current}
	if not joined:return _fail(NOT_JOINED)
	if kind=="light":
		if lamps.has(station):return _fail(ALREADY_LIT%STATIONS[station].title)
		lamps[station]=wish
		state[KEY]={"round":current,"phase":LIGHTING,"lamps":lamps,"participants":people}
		var left:=_unlit_text(lamps)
		var tail:="還有%s沒亮。"%left if not left.is_empty() else "三盞都亮了，回公告板完成吧。"
		return {"ok":true,"message":"叮——暖燈亮了！%s已掛上祝福。%s"%[STATIONS[station].title,tail]}
	# finish
	if lamps.size()!=STATIONS.size():return _fail(INCOMPLETE%_unlit_text(lamps))
	for who:String in people:
		if not players.get(who) is Dictionary:return _fail(BAD_RECORD)
	var first_completion:=false
	for who:String in people:
		if not _done(players[who]):first_completion=true
		players[who][KEY]=true
	state[KEY]={"round":current,"phase":CELEBRATED,"lamps":lamps,"participants":people}
	return {"ok":true,"message":"暖燈夜圓滿了！第一次參與的島民收下了冬天的紀念。" if first_completion else "暖燈夜再次圓滿！大家的冬夜紀念仍在。"}
