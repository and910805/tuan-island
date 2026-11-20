extends RefCounted
## P03 合作活動「廚房接力」（2～4 人組隊，世界時間 240 秒；也可單人練習）：
## 在備料台領取免費食材（每次最多托盤 2 樣）、到組裝台擺盤、到出餐台送出訂單，
## 每送出一份 +1 盤、+3 分，訂單依固定順序輪替。
##
## 渡口野餐後（state.picnic）解鎖，只在家園進行。沒有一般物品、鈴幣、食物、火源機制：
## 食材是無限免費供應，唯一的獎勵是個人紀念旗標 player.cooking_relay。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；時間只看 state.time。失敗時 state 完全不變
## （先在副本上檢查，最後才寫回）。存檔由 World 負責；step() 只改 state 並回傳是否有變更。
##
## 訂單：ORDER=["soup","salad","toast"]；目前要的菜 = ORDER[(round-1 + plates) mod 3]
## （第 round 輪從 ORDER 的第 (round-1) mod 3 道開始，每送出一盤就換下一道）。
##
## 共用 state.cooking_relay（可省略；第一次開始才寫入），欄位固定：
##   {"round":int, "phase":"lobby"|"run"|"results", "mode":"crew"|"practice"|"",
##    "started":float（run 開始時的世界時間；lobby 與重置後為 0）,
##    "members":{token:{"joined":bool,"acted":bool,"served":bool}},
##    "tray":Array[String]（0..2 樣，可含錯誤食材）, "plated":bool, "plates":int, "score":int}
##   lobby：mode=crew，members 1..4（離開即移除）。run：crew 2..4 人，practice 1 人。
##   results：時間到後的結果；mode 保留。若 lobby 最後一人離開，改為 results + mode ""（空紀錄），可立刻重開。
##   members 只在伺服器端；public_view 不含 token，只提供 guests（目前 joined 人數）。
##
## 個人 player.cooking_relay（可省略）：{"practice":true?, "crew":true?}，值只能是 true、至少一個。
##   結算（時間到）時發放，已有的不重複：
##   - crew：該輪「真的做過」備料／撤銷／擺盤／送出任一動作的成員 → crew。
##   - practice：單人練習中至少送出一盤的人 → practice（第一次練習紀念；練習不計排名，
##     mode="practice" 的紀錄請排行榜略過）。
##   只看過、沒動手的人什麼都沒有。離開、斷線者的貢獻仍保留並能領取。
##
## 指令 ACTION="cooking_relay"，extra（<round> 必須是目前這輪的正規十進位，無正負號、無前導零）：
##   "crew"           at＝SIGN；idle/results 時建立 lobby 並自動加入
##   "join:<round>"   at＝SIGN；只限 lobby，最多 4 人
##   "begin:<round>"  at＝SIGN；lobby 內 2～4 人且自己在其中時開始
##   "practice"       at＝SIGN；idle/results 時單人直接開始（不排名）
##   "leave:<round>"  任何位置、任何區域。lobby 離開即移除；run 離開只是 joined=false，
##                    備料與托盤保留（無法在 run 中重新加入）。斷線不改 state，重連仍保持原樣。
##   "prep:<round>:<item>"  at＝STATIONS.prep；托盤加一樣食材，最多 2 樣（可放錯的）；已擺盤時需先撤銷
##   "plate:<round>"  at＝STATIONS.assembly；托盤與目前訂單相符（不分順序）才擺盤，托盤保留
##   "undo:<round>"   at＝STATIONS.assembly；清空托盤並取消擺盤
##   "serve:<round>"  at＝STATIONS.serve；已擺盤才可送出：+1 盤、+3 分，托盤清空、訂單換下一道
##   run 中只有 joined 的組員能動手；其他人只能觀看。距離 <= REACH。
##
## 公開 API：valid(state)、public_view(state)、view(state,token)、apply(state,token,at,extra,home)、step(state)。

const KEY:="cooking_relay"
const ACTION:="cooking_relay"
const VIEW_KEY:="own_cooking_relay"
const SIGN:=Vector2i(40,33)
const STATIONS:={"prep":Vector2i(38,35),"assembly":Vector2i(41,37),"serve":Vector2i(43,38)}
const AREA:=Rect2i(36,32,11,8)
const ITEMS:={"root":"根莖","green":"葉菜","fruit":"水果","grain":"穀物"}
const RECIPES:={
	"soup":{"title":"蔬菜湯","items":["root","green"]},
	"salad":{"title":"水果沙拉","items":["green","fruit"]},
	"toast":{"title":"水果吐司","items":["grain","fruit"]},
}
const ORDER:=["soup","salad","toast"]
const REACH:=3.2
const DURATION:=240.0
const MIN_CREW:=2
const MAX_CREW:=4
const TRAY_MAX:=2
const POINTS:=3
const MAX_ROUND:=1000000000
const MAX_PLATES:=100000
const EPSILON:=0.01
const IDLE:="idle"
const LOBBY:="lobby"
const RUN:="run"
const RESULTS:="results"
const CREW:="crew"
const PRACTICE:="practice"
const SHARED_KEYS:=["members","mode","phase","plated","plates","round","score","started","tray"]
const FLAG_KEYS:=["practice","crew"]

const LOCKED:="完成渡口野餐後，廚房接力才會開放。"
const WRONG_REGION:="廚房接力在家園，請回到家園再參加。"
const NO_PLAYER:="請重新加入世界再參加廚房接力。"
const BAD_RECORD:="廚房接力的紀錄無法讀取，請重新操作。"
const BAD_EXTRA:="請重新操作廚房接力。"
const WRONG_SIGN:="請走到廚房的接力告示牌前操作。"
const WRONG_STATION:="請走到對應的工作台再操作。"
const TOO_FAR:="再靠近一點。"
const STALE:="廚房接力已更新，請重新打開告示牌。"
const ALREADY_ACTIVE:="這一輪還在進行或集合中，先看看吧。"
const ENDING:="這一輪的時間到了，正在結算。"
const ROUND_LIMIT:="廚房接力的輪數已到上限。"
const NOT_LOBBY:="這一輪已經開始，不能再加入了。"
const NOT_ACTIVE:="這一輪已經結束了，到告示牌開下一輪吧。"
const NOT_RUN:="這一輪還沒開始。"
const ALREADY_JOINED:="你已經在這一輪裡了。"
const FULL:="這一輪已經有 4 位島民了。"
const NOT_JOINED:="你不在這一輪的組員名單裡，只能在旁邊觀看。"
const NEED_CREW:="需要 2～4 位島民才能開始接力。"
const TRAY_FULL:="托盤已經放滿 2 樣了，先到組裝台撤銷或擺盤。"
const IS_PLATED:="已經擺盤了，先到組裝台撤銷，或到出餐台送出。"
const NO_MATCH:="托盤上的食材和目前的訂單不符。"
const NOT_PLATED:="還沒有擺好的盤子可以送出。"
const NOTHING_TO_UNDO:="托盤是空的，沒有東西可以撤銷。"

static func unlocked(state:Dictionary) -> bool:
	return state.get("picnic",false)==true

static func _now(state:Dictionary) -> float:
	var value:Variant=state.get("time",0.0)
	return float(value) if (value is int or value is float) and is_finite(float(value)) else 0.0

static func _whole(value:Variant,minimum:int,maximum:int) -> bool:
	if not (value is int or value is float):return false
	var number:=float(value)
	return is_finite(number) and floorf(number)==number and number>=float(minimum) and number<=float(maximum)

## 個人旗標：非空字典，鍵只能是 practice/crew，值只能是 true。
static func _flags_ok(raw:Variant) -> bool:
	if not raw is Dictionary or raw.is_empty():return false
	for key in raw:
		if not key is String or key not in FLAG_KEYS:return false
		if not raw[key] is bool or raw[key]!=true:return false
	return true

static func _flag(person:Variant,name:String) -> bool:
	if not person is Dictionary:return false
	var flags:Variant=person.get(KEY)
	return flags is Dictionary and flags.get(name)==true

## 第 round 輪、已送出 plates 盤時，目前要的菜 id。
static func dish_for(round_id:int,plates:int) -> String:
	return str(ORDER[posmod(round_id-1+plates,ORDER.size())])

static func _matches(tray:Array,dish:String) -> bool:
	var need:Array=((RECIPES[dish] as Dictionary).items as Array).duplicate()
	var have:Array=tray.duplicate()
	if have.size()!=need.size():return false
	need.sort()
	have.sort()
	return need==have

static func _blank(round_id:int) -> Dictionary:
	return {"round":round_id,"phase":RESULTS,"mode":"","started":0.0,"members":{},
		"tray":[],"plated":false,"plates":0,"score":0}

## 共用紀錄的形狀檢查；通過時回傳正規化後的深層副本，否則 null。
static func _shared_of(raw:Variant,players:Variant,now:float) -> Variant:
	if not raw is Dictionary or raw.size()!=SHARED_KEYS.size() or not players is Dictionary:return null
	for field in SHARED_KEYS:
		if not raw.has(field):return null
	if not _whole(raw.round,1,MAX_ROUND):return null
	if not raw.phase is String or raw.phase not in [LOBBY,RUN,RESULTS]:return null
	if not raw.mode is String or raw.mode not in [CREW,PRACTICE,""]:return null
	if not (raw.started is int or raw.started is float):return null
	var started:=float(raw.started)
	if not is_finite(started) or started<0.0 or started>now+EPSILON:return null
	if not _whole(raw.plates,0,MAX_PLATES) or not _whole(raw.score,0,MAX_PLATES*POINTS):return null
	var plates:=int(raw.plates)
	if int(raw.score)!=plates*POINTS:return null
	if not raw.plated is bool:return null
	if not raw.tray is Array or raw.tray.size()>TRAY_MAX:return null
	var tray:Array=[]
	for item in raw.tray:
		if not item is String or not ITEMS.has(item):return null
		tray.append(item)
	if not raw.members is Dictionary or raw.members.size()>MAX_CREW:return null
	var members:={}
	var any_acted:=false
	var any_served:=false
	var joined:=0
	for token in raw.members:
		if not token is String or not players.get(token) is Dictionary:return null
		var entry:Variant=raw.members[token]
		if not entry is Dictionary or entry.size()!=3:return null
		for field in ["joined","acted","served"]:
			if not entry.has(field) or not entry[field] is bool:return null
		if entry.served and not entry.acted:return null
		members[token]={"joined":entry.joined,"acted":entry.acted,"served":entry.served}
		if entry.joined:joined+=1
		if entry.acted:any_acted=true
		if entry.served:any_served=true
	var round_id:=int(raw.round)
	var mode:String=raw.mode
	var phase:String=raw.phase
	if phase==LOBBY:
		if mode!=CREW or members.size()<1 or joined!=members.size():return null
		if started!=0.0 or plates!=0 or not tray.is_empty() or raw.plated or any_acted:return null
	else:
		if mode=="":
			if phase!=RESULTS or not members.is_empty() or started!=0.0:return null
			if plates!=0 or not tray.is_empty() or raw.plated:return null
		elif mode==CREW:
			if members.size()<MIN_CREW:return null
		else:
			if members.size()!=1:return null
		if phase==RUN and mode=="":return null
		if (plates>0 and not any_served) or ((not tray.is_empty() or plates>0) and not any_acted):return null
		if raw.plated and not _matches(tray,dish_for(round_id,plates)):return null
	if phase==RESULTS:
		for token:String in members:
			var entry:Dictionary=members[token]
			if mode==CREW and entry.acted and not _flag(players[token],CREW):return null
			if mode==PRACTICE and entry.served and not _flag(players[token],PRACTICE):return null
	return {"round":round_id,"phase":phase,"mode":mode,"started":started,"members":members,
		"tray":tray,"plated":raw.plated,"plates":plates,"score":plates*POINTS}

## 目前的共用紀錄（已驗證的副本）；沒有或損壞時 null。
static func _load(state:Dictionary) -> Variant:
	if not state.has(KEY):return null
	return _shared_of(state[KEY],state.get("players"),_now(state))

## 存檔檢查：共用與個人紀錄都可省略。共用紀錄存在時需野餐已完成。
## 通過時把 JSON 讀回的浮點整數輪次正規化為 int。
static func valid(state:Dictionary) -> bool:
	var players:Variant=state.get("players")
	if not players is Dictionary:return false
	for token in players:
		var person:Variant=players[token]
		if person is Dictionary and person.has(KEY) and not _flags_ok(person[KEY]):return false
	if not state.has(KEY):return true
	if state.get("picnic")!=true:return false
	var shared:Variant=_load(state)
	if shared==null:return false
	state[KEY]["round"]=int(shared.round)
	return true

static func _joined_count(shared:Dictionary) -> int:
	var count:=0
	for token in shared.members:
		if shared.members[token].joined==true:count+=1
	return count

static func _remaining(shared:Dictionary,now:float) -> int:
	if shared.phase!=RUN:return 0
	return clampi(ceili(float(shared.started)+DURATION-now),0,int(DURATION))

static func _dish_of(shared:Dictionary) -> String:
	if shared.mode=="":return ""
	return dish_for(int(shared.round),int(shared.plates))

static func _tray_copy(tray:Array) -> Array[String]:
	var result:Array[String]=[]
	for item in tray:result.append(str(item))
	return result

static func _idle_public() -> Dictionary:
	var tray:Array[String]=[]
	return {"round":0,"phase":IDLE,"mode":"","remaining":0,"guests":0,"tray":tray,
		"dish":"","plated":false,"plates":0,"score":0}

## 公開快照：沒有 token。
static func _lobby_count(shared:Dictionary,online:Variant) -> int:
	if not online is Dictionary:return _joined_count(shared)
	var count:=0
	for token:String in shared.members:
		if online.has(token) and shared.members[token].joined:count+=1
	return count

static func public_view(state:Dictionary,online:Variant=null) -> Dictionary:
	var shared:Variant=_load(state)
	if shared==null:return _idle_public()
	return {"round":int(shared.round),"phase":str(shared.phase),"mode":str(shared.mode),
		"remaining":_remaining(shared,_now(state)),"guests":_lobby_count(shared,online) if shared.phase==LOBBY else _joined_count(shared),
		"tray":_tray_copy(shared.tray),"dish":_dish_of(shared),"plated":shared.plated==true,
		"plates":int(shared.plates),"score":int(shared.score)}

## 本人用摘要（Session 以 data.own_cooking_relay 送出）。
static func view(state:Dictionary,token:String,online:Variant=null) -> Dictionary:
	var open:=unlocked(state)
	var players:Variant=state.get("players",{})
	var person:Variant=players.get(token) if players is Dictionary else null
	var shared:Variant=_load(state)
	var joined:=false
	var busy:=false
	var capped:=false
	var can_begin:=false
	if shared!=null:
		var entry:Variant=shared.members.get(token)
		joined=entry is Dictionary and entry.joined==true and shared.phase!=RESULTS
		busy=shared.phase!=RESULTS
		capped=int(shared.round)>=MAX_ROUND
		can_begin=joined and shared.phase==LOBBY and _lobby_count(shared,online)>=MIN_CREW
	elif state.has(KEY):
		open=false
	return {"unlocked":open,"joined":joined,"practice":_flag(person,PRACTICE),"crew":_flag(person,CREW),
		"can_start":open and not busy and not capped,"can_begin":open and can_begin}

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

## 正規十進位輪次：1..MAX_ROUND、只有數字、沒有前導零；其他一律 -1。
static func _round_text(text:String) -> int:
	if text.is_empty() or text.length()>10 or text.begins_with("0"):return -1
	for i in range(text.length()):
		if text[i]<"0" or text[i]>"9":return -1
	var number:=int(text)
	return number if number>=1 and number<=MAX_ROUND else -1

## 回傳 {"kind","round","item"}；格式錯誤回傳空字典。
static func _parse(extra:String) -> Dictionary:
	if extra=="crew" or extra==PRACTICE:return {"kind":extra,"round":-1,"item":""}
	var parts:=extra.split(":")
	if parts.size()==3:
		if parts[0]!="prep" or not ITEMS.has(parts[2]):return {}
		var prep_round:=_round_text(parts[1])
		return {} if prep_round<0 else {"kind":"prep","round":prep_round,"item":parts[2]}
	if parts.size()!=2 or parts[0] not in ["join","begin","leave","plate","undo","serve"]:return {}
	var round_id:=_round_text(parts[1])
	if round_id<0:return {}
	return {"kind":parts[0],"round":round_id,"item":""}

static func _target_of(kind:String) -> Vector2i:
	match kind:
		"prep":return STATIONS.prep
		"plate","undo":return STATIONS.assembly
		"serve":return STATIONS.serve
	return SIGN

static func _new_member() -> Dictionary:
	return {"joined":true,"acted":false,"served":false}

## 結算：發旗標給動過手的成員，phase 立即變 results。
static func _settle(state:Dictionary,shared:Dictionary) -> void:
	var players:Dictionary=state.players
	for token:String in shared.members:
		var entry:Dictionary=shared.members[token]
		var earned:=""
		if shared.mode==CREW and entry.acted==true:earned=CREW
		elif shared.mode==PRACTICE and entry.served==true:earned=PRACTICE
		if earned.is_empty():continue
		var flags:Dictionary=(players[token].get(KEY) as Dictionary).duplicate() if players[token].get(KEY) is Dictionary else {}
		flags[earned]=true
		players[token][KEY]=flags
	shared.phase=RESULTS
	state[KEY]=shared

## 一個動作。World 只負責把 actor 所在區域（home）傳進來；失敗時 state 完全不變。
static func apply(state:Dictionary,token:String,at:Vector2i,extra:String,home:bool,online:Variant=null) -> Dictionary:
	if not unlocked(state):return _fail(LOCKED)
	var parsed:=_parse(extra)
	if parsed.is_empty():return _fail(BAD_EXTRA)
	var kind:String=parsed.kind
	if kind!="leave" and not home:return _fail(WRONG_REGION)
	var players:Variant=state.get("players")
	var person:Variant=players.get(token) if players is Dictionary else null
	if not person is Dictionary:return _fail(NO_PLAYER)
	if person.has(KEY) and not _flags_ok(person[KEY]):return _fail(BAD_RECORD)
	var now:=_now(state)
	var shared:Variant=null
	if state.has(KEY):
		shared=_shared_of(state[KEY],players,now)
		if shared==null:return _fail(BAD_RECORD)
	if kind!="leave":
		var target:=_target_of(kind)
		if at!=target:return _fail(WRONG_SIGN if target==SIGN else WRONG_STATION)
		var px:Variant=person.get("x",0.0)
		var py:Variant=person.get("y",0.0)
		if not (px is int or px is float) or not (py is int or py is float):return _fail(TOO_FAR)
		if not is_finite(float(px)) or not is_finite(float(py)):return _fail(TOO_FAR)
		if Vector2(float(px),float(py)).distance_to(Vector2(target)+Vector2(0.5,0.5))>REACH:return _fail(TOO_FAR)
	var expired:bool=shared!=null and shared.phase==RUN and now>=float(shared.started)+DURATION
	if kind=="crew" or kind==PRACTICE:
		var current:=0
		if shared!=null:
			if shared.phase!=RESULTS:return _fail(ENDING if expired else ALREADY_ACTIVE)
			current=int(shared.round)
		if current>=MAX_ROUND:return _fail(ROUND_LIMIT)
		var next:=current+1
		if kind=="crew":
			state[KEY]={"round":next,"phase":LOBBY,"mode":CREW,"started":0.0,"members":{token:_new_member()},
				"tray":[],"plated":false,"plates":0,"score":0}
			return {"ok":true,"message":"第 %d 輪廚房接力集合中！2～4 位島民到告示牌加入後即可開始。"%next}
		state[KEY]={"round":next,"phase":RUN,"mode":PRACTICE,"started":now,"members":{token:_new_member()},
			"tray":[],"plated":false,"plates":0,"score":0}
		return {"ok":true,"message":"單人練習開始！%d 秒內盡量多出餐，練習不計排名。"%int(DURATION)}
	if shared==null or int(parsed.round)!=int(shared.round):return _fail(STALE)
	var round_id:=int(shared.round)
	var phase:String=shared.phase
	var members:Dictionary=shared.members
	var entry:Variant=members.get(token)
	var joined:bool=entry is Dictionary and entry.joined==true
	if kind=="leave":
		if phase==RESULTS:return _fail(NOT_ACTIVE)
		if not joined:return _fail(NOT_JOINED)
		if phase==LOBBY:
			members.erase(token)
			state[KEY]=shared if not members.is_empty() else _blank(round_id)
			return {"ok":true,"message":"離開了這一輪的集合。"}
		members[token].joined=false
		state[KEY]=shared
		return {"ok":true,"message":"離開廚房接力。你做的備料會保留。"}
	if kind=="join":
		if phase!=LOBBY:return _fail(NOT_LOBBY if phase==RUN else NOT_ACTIVE)
		if entry!=null:return _fail(ALREADY_JOINED)
		if online is Dictionary:
			for member:String in members.keys():
				if not online.has(member):members.erase(member)
		if members.size()>=MAX_CREW:return _fail(FULL)
		members[token]=_new_member()
		state[KEY]=shared
		return {"ok":true,"message":"加入第 %d 輪廚房接力！"%round_id}
	if kind=="begin":
		if phase!=LOBBY:return _fail(NOT_LOBBY if phase==RUN else NOT_ACTIVE)
		if not joined:return _fail(NOT_JOINED)
		if _lobby_count(shared,online)<MIN_CREW or members.size()>MAX_CREW:return _fail(NEED_CREW)
		if online is Dictionary:
			for member:String in members.keys():
				if not online.has(member):members.erase(member)
		shared.phase=RUN
		shared.started=now
		state[KEY]=shared
		return {"ok":true,"message":"廚房接力開始！%d 秒內盡量多出餐。"%int(DURATION)}
	# 以下是 run 中的動手指令
	if phase!=RUN:return _fail(NOT_RUN if phase==LOBBY else NOT_ACTIVE)
	if expired:return _fail(ENDING)
	if not joined:return _fail(NOT_JOINED)
	var tray:Array=shared.tray
	var dish:=dish_for(round_id,int(shared.plates))
	var dish_title:String=RECIPES[dish].title
	var message:=""
	match kind:
		"prep":
			if shared.plated==true:return _fail(IS_PLATED)
			if tray.size()>=TRAY_MAX:return _fail(TRAY_FULL)
			tray.append(str(parsed.item))
			message="拿了一份%s放上托盤。"%str(ITEMS[parsed.item])
		"plate":
			if shared.plated==true:return _fail(IS_PLATED)
			if not _matches(tray,dish):return _fail(NO_MATCH)
			shared.plated=true
			message="擺好「%s」，送到出餐台吧！"%dish_title
		"undo":
			if tray.is_empty() and shared.plated!=true:return _fail(NOTHING_TO_UNDO)
			tray.clear()
			shared.plated=false
			message="托盤清空了，食材可以重新領取。"
		_:
			if shared.plated!=true:return _fail(NOT_PLATED)
			shared.plates=int(shared.plates)+1
			shared.score=int(shared.plates)*POINTS
			tray.clear()
			shared.plated=false
			members[token].served=true
			message="送出「%s」！+%d 分，已送出 %d 盤。下一道：%s。"%[dish_title,POINTS,int(shared.plates),
				str(RECIPES[dish_for(round_id,int(shared.plates))].title)]
	members[token].acted=true
	state[KEY]=shared
	return {"ok":true,"message":message}

## World.step 每個 tick 呼叫：進行中且時間到就結算。只改 state，有變更時回傳 true；World 負責存檔。
static func step(state:Dictionary) -> bool:
	var shared:Variant=_load(state)
	if shared==null or shared.phase!=RUN:return false
	if _now(state)<float(shared.started)+DURATION:return false
	_settle(state,shared)
	return true
