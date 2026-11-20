extends RefCounted
## P06 合作活動「礦車搬運」（1～4 人，世界時間 300 秒）：在獨立礦道（region "cart_gallery"）
## 把 3 箱模型貨箱用礦車從起點推到卸貨台，每箱卸貨 +2 分。
##
## 沒有一般物品、鈴幣、背包、圖層：分數只存在於本輪共用紀錄。
## 入口（金瓜石 (28,25)）與出口 (11,20) 的傳送由整合層負責；本檔不 preload World（避免循環）。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；時間只看 state.time（絕對時間存在紀錄裡，
## 不存「剩餘時間」，剩餘由 public_view 用 state.time 算出）。失敗時 state 完全不變
## （在深層副本上操作，成功才寫回）。
##
## 共用 state.party_cart（可省略；第一次開始才寫入），欄位固定：
##   {"round":int, "phase":"run"|"results", "started":float,
##    "members":{token:{"joined":bool}}（1..4，累計不超過 4 位）,
##    "stop":int(0..5), "to":int(-1 = 靜止), "departed":float, "arrives":float（靜止時皆 0.0）,
##    "branch":"north"|"south"（在岔路口選擇，跨車次保留，每輪重設為 north）,
##    "rocks":{"north":bool,"south":bool}（true = 仍有落石擋路；每輪重設）,
##    "delivered":int(0..3), "score":int（= delivered * POINTS）}
##
## 路線：0 起點 →1 岔路口 →(2 北 | 3 南) →4 匯合 →5 卸貨台。
##   - 要走某條支線前必須先清掉該支線的落石；另一條支線不受影響。
##   - "push:<round>"：站在目前靜止礦車所在格附近推車，車子自行跑完一段（SEGMENT 秒）；
##     移動中拒絕再推；任何成員都能推下一段；推車人斷線，車子仍會自然停到下一站。
##   - "unload:<round>"：礦車靜止在卸貨台時卸貨，+1 箱 +2 分，礦車歸位到起點（補貨以重設表示）；
##     第 3 箱後立即進入 results。
##   - 時間到（DURATION）進入 results；仍在移動的車不再給分，移動被取消。
##
## 指令 ACTION="party_cart"，extra（<round> 必須是目前這輪的正規十進位）：
##   "start"                     at＝SIGN；idle／results 時開新輪並自動加入
##   "join:<round>"              at＝SIGN；中途加入（或離開後回來）
##   "leave:<round>"             任何位置、任何區域
##   "push:<round>"              at＝目前礦車所在站格
##   "switch:<round>"            at＝STOPS[JUNCTION]，礦車靜止在岔路口時切換 north/south
##   "clear:<round>:north|south" at＝ROCKS[該支線]
##   "unload:<round>"            at＝STOPS[DOCK]，礦車靜止在卸貨台
## 除 leave 外都要求 in_gallery 與在線；push/switch/clear/unload 另外要求是目前成員。
##
## 公開 API：valid(state)、public_view(state)、view(state,token)、
##           apply(state,token,cell,extra,in_gallery,active_tokens)、step(state,active_tokens)、
##           return_member(state,token)。

const KEY:="party_cart"
const ACTION:="party_cart"
const VIEW_KEY:="own_party_cart"
const REGION:="cart_gallery"
const SURFACE:="jinguashi"
const SURFACE_PORTAL:=Vector2i(28,25)
const EXIT:=Vector2i(11,20)
const SIGN:=Vector2i(13,17)
const BOUNDS:=Rect2i(10,15,22,11)
const SPAWN:=Vector2(12.5,20.5)
const STOPS:=[Vector2i(15,20),Vector2i(19,20),Vector2i(22,18),Vector2i(22,22),Vector2i(25,20),Vector2i(28,20)]
const START:=0
const JUNCTION:=1
const NORTH_STOP:=2
const SOUTH_STOP:=3
const MERGE:=4
const DOCK:=5
const ROCKS:={"north":Vector2i(21,18),"south":Vector2i(21,22)}
const BRANCHES:=["north","south"]
const REACH:=3.2
const DURATION:=300.0
const SEGMENT:=1.8
const CRATES:=3
const POINTS:=2
const MAX_PLAYERS:=4
const MAX_ROUND:=1000000000
const EPSILON:=0.01
const IDLE:="idle"
const RUN:="run"
const RESULTS:="results"
const SHARED_KEYS:=["arrives","branch","delivered","departed","members","phase","rocks","round","score","started","stop","to"]

const BAD_RECORD:="礦車搬運的紀錄無法讀取，請重新操作。"
const BAD_EXTRA:="請重新操作礦車搬運。"
const WRONG_REGION:="礦車搬運在礦道裡，請進入礦道再操作。"
const NO_PLAYER:="請重新加入世界再參加礦車搬運。"
const NOT_ONLINE:="請先連線再參加礦車搬運。"
const WRONG_SIGN:="請走到礦道入口的告示牌前開始或加入。"
const WRONG_CELL:="請走到正確的位置再操作。"
const TOO_FAR:="再靠近一點。"
const STALE:="礦車搬運已更新，請重新打開告示牌。"
const ALREADY_ACTIVE:="這一輪還在進行，到告示牌前加入吧。"
const ENDING:="這一輪的時間到了，正在結算。"
const ROUND_LIMIT:="礦車搬運的輪數已到上限。"
const NOT_ACTIVE:="這一輪已經結束了，到告示牌開下一輪吧。"
const ALREADY_JOINED:="你已經在這一輪裡了。"
const FULL:="這一輪已經有 4 位島民參加過，等下一輪再加入吧。"
const NOT_JOINED:="你不在這一輪裡。"
const MOVING:="礦車還在移動，等它停下來。"
const AT_DOCK:="礦車已經到卸貨台，請卸貨。"
const ROCK_BLOCKED:="這條支線的落石還沒清掉，先清除落石或換另一條支線。"
const NOT_AT_JUNCTION:="礦車要靜止在岔路口才能切換支線。"
const NOT_AT_DOCK:="礦車要靜止在卸貨台才能卸貨。"
const ROCK_CLEAR:="這條支線的落石已經清掉了。"

static func _now(state:Dictionary) -> float:
	var value:Variant=state.get("time",0.0)
	return float(value) if (value is int or value is float) and is_finite(float(value)) else 0.0

static func _num(value:Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _whole(value:Variant,minimum:int,maximum:int) -> bool:
	if not _num(value):return false
	var number:=float(value)
	return floorf(number)==number and number>=float(minimum) and number<=float(maximum)

static func _is_active(active:Variant,token:String) -> bool:
	if active is Dictionary:return (active as Dictionary).has(token)
	if active is Array:return token in (active as Array)
	return false

static func _position(person:Variant) -> Variant:
	if not person is Dictionary:return null
	var px:Variant=(person as Dictionary).get("x",0.0)
	var py:Variant=(person as Dictionary).get("y",0.0)
	if not _num(px) or not _num(py):return null
	return Vector2(float(px),float(py))

static func _in_reach(person:Variant,cell:Vector2i) -> bool:
	var at:Variant=_position(person)
	return at!=null and (at as Vector2).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=REACH

## 下一站；5（卸貨台）沒有下一段。
static func _next(stop:int,branch:String) -> int:
	match stop:
		START:return JUNCTION
		JUNCTION:return NORTH_STOP if branch=="north" else SOUTH_STOP
		NORTH_STOP,SOUTH_STOP:return MERGE
		MERGE:return DOCK
	return -1

static func _fresh_rocks() -> Dictionary:
	return {"north":true,"south":true}

## 共用紀錄的形狀檢查；通過時回傳正規化後的深層副本，否則 null。
static func _shared_of(raw:Variant,players:Variant,now:float) -> Variant:
	if not raw is Dictionary or raw.size()!=SHARED_KEYS.size() or not players is Dictionary:return null
	for field in SHARED_KEYS:
		if not raw.has(field):return null
	if not _whole(raw.round,1,MAX_ROUND):return null
	if not raw.phase is String or raw.phase not in [RUN,RESULTS]:return null
	var phase:String=raw.phase
	if not _num(raw.started):return null
	var started:=float(raw.started)
	if started<0.0 or started>now+EPSILON:return null
	if not raw.members is Dictionary or raw.members.size()<1 or raw.members.size()>MAX_PLAYERS:return null
	var members:={}
	for token in raw.members:
		if not token is String or not players.get(token) is Dictionary:return null
		var entry:Variant=raw.members[token]
		if not entry is Dictionary or entry.size()!=1 or not entry.has("joined") or not entry.joined is bool:return null
		if phase==RESULTS and entry.joined:return null
		members[token]={"joined":entry.joined}
	if not _whole(raw.stop,START,DOCK) or not _whole(raw.to,-1,DOCK):return null
	var stop:=int(raw.stop)
	var to:=int(raw.to)
	if not raw.branch is String or raw.branch not in BRANCHES:return null
	var branch:String=raw.branch
	if not raw.rocks is Dictionary or raw.rocks.size()!=2:return null
	if not raw.rocks.get("north") is bool or not raw.rocks.get("south") is bool:return null
	var rocks:Dictionary={"north":raw.rocks.north,"south":raw.rocks.south}
	if not _whole(raw.delivered,0,CRATES) or not _whole(raw.score,0,CRATES*POINTS):return null
	var delivered:=int(raw.delivered)
	if int(raw.score)!=delivered*POINTS:return null
	if phase==RUN and delivered>=CRATES:return null
	if phase==RESULTS and delivered<CRATES and now<started+DURATION-EPSILON:return null
	if not _num(raw.departed) or not _num(raw.arrives):return null
	var departed:=float(raw.departed)
	var arrives:=float(raw.arrives)
	if to==-1:
		if departed!=0.0 or arrives!=0.0:return null
	else:
		if phase!=RUN:return null
		if to!=_next(stop,branch):return null
		if departed<started-EPSILON or departed>now+EPSILON:return null
		if absf(arrives-departed-SEGMENT)>EPSILON:return null
		if stop==JUNCTION and rocks[branch]:return null
	# 在支線上（含正要進入）時，閂鎖的支線必須與該站一致且落石已清
	for pair:Array in [[NORTH_STOP,"north"],[SOUTH_STOP,"south"]]:
		if stop==pair[0] or to==pair[0]:
			if branch!=pair[1] or rocks[pair[1]]:return null
	return {"round":int(raw.round),"phase":phase,"started":started,"members":members,
		"stop":stop,"to":to,"departed":departed,"arrives":arrives,"branch":branch,"rocks":rocks,
		"delivered":delivered,"score":delivered*POINTS}

## 目前的共用紀錄（已驗證的副本）；沒有或損壞時 null。
static func _load(state:Dictionary) -> Variant:
	if not state.has(KEY):return null
	return _shared_of(state[KEY],state.get("players"),_now(state))

## 存檔檢查：共用紀錄可省略；通過時把 JSON 讀回的浮點整數正規化（寫回被檢查的狀態）。
static func valid(state:Dictionary) -> bool:
	if not state.get("players") is Dictionary:return false
	if not state.has(KEY):return true
	var shared:Variant=_load(state)
	if shared==null:return false
	state[KEY]=shared
	return true

static func _remaining(shared:Dictionary,now:float) -> int:
	if shared.phase!=RUN:return 0
	return clampi(ceili(float(shared.started)+DURATION-now),0,int(DURATION))

static func _joined_count(shared:Dictionary) -> int:
	var count:=0
	for token in shared.members:
		if shared.members[token].joined==true:count+=1
	return count

## 公開快照：沒有 token。
static func public_view(state:Dictionary) -> Dictionary:
	var shared:Variant=_load(state)
	if shared==null:
		return {"phase":IDLE,"round":0,"remaining":0,"stop":START,"to":-1,"departed":0.0,"arrives":0.0,
			"branch":"north","rocks":_fresh_rocks(),"delivered":0,"score":0,"total":CRATES,"players":0}
	return {"phase":str(shared.phase),"round":int(shared.round),"remaining":_remaining(shared,_now(state)),
		"stop":int(shared.stop),"to":int(shared.to),"departed":float(shared.departed),"arrives":float(shared.arrives),
		"branch":str(shared.branch),"rocks":{"north":shared.rocks.north==true,"south":shared.rocks.south==true},
		"delivered":int(shared.delivered),"score":int(shared.score),"total":CRATES,"players":_joined_count(shared)}

## 本人用摘要（Session 以 data.own_party_cart 送出）。
static func view(state:Dictionary,token:String) -> Dictionary:
	var shared:Variant=_load(state)
	var joined:=false
	if shared!=null:
		var entry:Variant=shared.members.get(token)
		joined=shared.phase==RUN and entry is Dictionary and entry.joined==true
	return {"joined":joined}

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

static func _ok(message:String) -> Dictionary:
	return {"ok":true,"message":message}

## 正規十進位輪次：1..MAX_ROUND、只有數字、沒有前導零；其他一律 -1。
static func _round_text(text:String) -> int:
	if text.is_empty() or text.length()>10 or text.begins_with("0"):return -1
	for i in range(text.length()):
		if text[i]<"0" or text[i]>"9":return -1
	var number:=int(text)
	return number if number>=1 and number<=MAX_ROUND else -1

## 回傳 {"kind","round","branch"}；格式錯誤回傳空字典。
static func _parse(extra:String) -> Dictionary:
	if extra=="start":return {"kind":"start","round":-1,"branch":""}
	var parts:=extra.split(":")
	if parts.size()<2 or parts.size()>3:return {}
	var kind:=parts[0]
	if kind=="clear":
		if parts.size()!=3 or parts[2] not in BRANCHES:return {}
	elif parts.size()!=2 or kind not in ["join","leave","push","switch","unload"]:
		return {}
	var round_id:=_round_text(parts[1])
	if round_id<0:return {}
	return {"kind":kind,"round":round_id,"branch":parts[2] if parts.size()==3 else ""}

## 時間到或第 3 箱：進入 results；移動取消、成員全部歸隊。
static func _settle(shared:Dictionary) -> void:
	shared.phase=RESULTS
	shared.to=-1
	shared.departed=0.0
	shared.arrives=0.0
	for token:String in shared.members:
		shared.members[token].joined=false

## 到站：把已跑完的一段落成靜止。
static func _arrive(shared:Dictionary,now:float) -> bool:
	if int(shared.to)<0 or now<float(shared.arrives):return false
	shared.stop=int(shared.to)
	shared.to=-1
	shared.departed=0.0
	shared.arrives=0.0
	return true

## 一個動作。World 只傳入 actor 是否在礦道（in_gallery）與 active_tokens；失敗時 state 完全不變。
static func apply(state:Dictionary,token:String,cell:Vector2i,extra:String,in_gallery:bool,active_tokens:Dictionary) -> Dictionary:
	var parsed:=_parse(extra)
	if parsed.is_empty():return _fail(BAD_EXTRA)
	var kind:String=parsed.kind
	if kind!="leave" and not in_gallery:return _fail(WRONG_REGION)
	var players:Variant=state.get("players")
	var person:Variant=players.get(token) if players is Dictionary else null
	if not person is Dictionary:return _fail(NO_PLAYER)
	var now:=_now(state)
	var shared:Variant=null
	if state.has(KEY):
		shared=_shared_of(state[KEY],players,now)
		if shared==null:return _fail(BAD_RECORD)
	if kind!="leave" and not _is_active(active_tokens,token):return _fail(NOT_ONLINE)
	var expired:bool=shared!=null and shared.phase==RUN and now>=float(shared.started)+DURATION
	if kind=="start":
		if cell!=SIGN:return _fail(WRONG_SIGN)
		if not _in_reach(person,SIGN):return _fail(TOO_FAR)
		var current:=0
		if shared!=null:
			if shared.phase==RUN:return _fail(ENDING if expired else ALREADY_ACTIVE)
			current=int(shared.round)
		if current>=MAX_ROUND:return _fail(ROUND_LIMIT)
		state[KEY]={"round":current+1,"phase":RUN,"started":now,"members":{token:{"joined":true}},
			"stop":START,"to":-1,"departed":0.0,"arrives":0.0,"branch":"north","rocks":_fresh_rocks(),
			"delivered":0,"score":0}
		return _ok("第 %d 輪礦車搬運開始！清掉落石，把 %d 箱貨箱推到卸貨台。"%[current+1,CRATES])
	if shared==null or int(parsed.round)!=int(shared.round):return _fail(STALE)
	if shared.phase!=RUN:return _fail(NOT_ACTIVE)
	var round_id:int=int(shared.round)
	var members:Dictionary=shared.members
	var entry:Variant=members.get(token)
	var joined:bool=entry is Dictionary and entry.joined==true
	if kind=="leave":
		if not joined:return _fail(NOT_JOINED)
		members[token]={"joined":false}
		state[KEY]=shared
		return _ok("離開礦車搬運；礦車維持原狀，其他人可以繼續。")
	if expired:return _fail(ENDING)
	if kind=="join":
		if cell!=SIGN:return _fail(WRONG_SIGN)
		if not _in_reach(person,SIGN):return _fail(TOO_FAR)
		if joined:return _fail(ALREADY_JOINED)
		if entry==null and members.size()>=MAX_PLAYERS:return _fail(FULL)
		members[token]={"joined":true}
		state[KEY]=shared
		return _ok("加入第 %d 輪礦車搬運！"%round_id)
	if not joined:return _fail(NOT_JOINED)
	_arrive(shared,now)
	var stop:int=int(shared.stop)
	var branch:String=shared.branch
	var idle:bool=int(shared.to)<0
	match kind:
		"push":
			if not idle:return _fail(MOVING)
			if stop==DOCK:return _fail(AT_DOCK)
			if cell!=STOPS[stop]:return _fail(WRONG_CELL)
			if not _in_reach(person,cell):return _fail(TOO_FAR)
			if stop==JUNCTION and shared.rocks[branch]==true:return _fail(ROCK_BLOCKED)
			shared.to=_next(stop,branch)
			shared.departed=now
			shared.arrives=now+SEGMENT
			state[KEY]=shared
			return _ok("礦車出發了！")
		"switch":
			if not idle or stop!=JUNCTION:return _fail(NOT_AT_JUNCTION)
			if cell!=STOPS[JUNCTION]:return _fail(WRONG_CELL)
			if not _in_reach(person,cell):return _fail(TOO_FAR)
			shared.branch="south" if branch=="north" else "north"
			state[KEY]=shared
			return _ok("岔路已切換到%s線。"%("南" if shared.branch=="south" else "北"))
		"clear":
			var side:String=parsed.branch
			if cell!=ROCKS[side]:return _fail(WRONG_CELL)
			if not _in_reach(person,cell):return _fail(TOO_FAR)
			if shared.rocks[side]!=true:return _fail(ROCK_CLEAR)
			shared.rocks[side]=false
			state[KEY]=shared
			return _ok("清掉了%s線的落石！"%("南" if side=="south" else "北"))
		"unload":
			if not idle or stop!=DOCK:return _fail(NOT_AT_DOCK)
			if cell!=STOPS[DOCK]:return _fail(WRONG_CELL)
			if not _in_reach(person,cell):return _fail(TOO_FAR)
			shared.delivered=int(shared.delivered)+1
			shared.score=int(shared.delivered)*POINTS
			shared.stop=START
			var message:="卸下一箱貨箱，+%d 分！礦車回到起點補貨。"%POINTS
			if int(shared.delivered)>=CRATES:
				_settle(shared)
				message="%d 箱貨箱全部送達，共 %d 分！"%[CRATES,int(shared.score)]
			state[KEY]=shared
			return _ok(message)
	return _fail(BAD_EXTRA)

## 成員離開礦道／斷線時由整合層呼叫：只清 joined，不動運送中的礦車與分數。
static func return_member(state:Dictionary,token:String) -> void:
	var shared:Variant=_load(state)
	if shared==null or shared.phase!=RUN:return
	if not shared.members.get(token,{}).get("joined",false):return
	shared.members[token]={"joined":false}
	state[KEY]=shared

## World.step 每個 tick 呼叫；回傳 true 代表持久內容有變（到站、結算、成員離線）。
static func step(state:Dictionary,active_tokens:Dictionary) -> bool:
	var shared:Variant=_load(state)
	if shared==null or shared.phase!=RUN:return false
	var now:=_now(state)
	if now>=float(shared.started)+DURATION:
		_settle(shared)
		state[KEY]=shared
		return true
	var changed:=_arrive(shared,now)
	var tokens:Array=(shared.members as Dictionary).keys()
	tokens.sort()
	for token:String in tokens:
		if shared.members[token].joined==true and not _is_active(active_tokens,token):
			shared.members[token].joined=false
			changed=true
	if changed:state[KEY]=shared
	return changed
