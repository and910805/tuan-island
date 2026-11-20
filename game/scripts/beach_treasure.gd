extends RefCounted
## P08 合作活動「海灘尋寶」（1～8 人，世界時間 300 秒）：在六處可走到的海灘格子裡，
## 依線索找出三處埋寶點，每找到一處得 3 分。
##
## 渡口野餐後（state.picnic）解鎖，只在家園（風鈴渡口）進行。沒有一般物品、鈴幣、作物：
## 唯一的獎勵是永久紀念（player.beach_treasure=true）。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；時間只看 state.time。失敗時 state 完全不變
## （先在副本上檢查，最後才寫回）。存檔由 World 負責；step() 只改 state 並回傳是否有變更。
##
## 埋寶點：只有伺服器知道。第 round 輪用 TEMPLATES[round mod 3]（三組範本，每組 3 處）。
## 公開快照與本人摘要都不含目標清單；只有「已找到」的點會出現在 found。
##
## 線索：每個寶物恰好一句（Array[String]，順序＝範本順序）。精確度 level=0..3：
##   level = min(3, 經過的整分鐘數 + 挖錯的處數)；每 60 秒自動變清楚（單人也一樣），
##   每個挖錯的點也讓線索更清楚（同一點每輪只算一次，不會刷線索）。找到的寶物改顯示「已挖到」。
##   結算後（results）顯示最精確的線索。
##
## 共用 state.beach_treasure（可省略；第一次開始才寫入），欄位固定：
##   {"round":int(1..1e9), "phase":"search"|"results", "started":float, "reason":""|"goal"|"time",
##    "members":{token:{"joined":bool,"dug":bool}}（1..8，累計不超過 8 位，離開後貢獻保留）,
##    "found":{id:true}, "marks":{id:true}, "wrong":{id:true}}
##   reason：search 時為 ""；results 時 "goal"（三處全找到）或 "time"（時間到）。
##   結算（全找到或時間到）立即把 phase 設為 results、寫入 reason，並發紀念給
##   每位「至少挖過一次」的成員（挖對或挖錯都算；離開、斷線者也算），已有紀念者不重複。
## 個人 player.beach_treasure（可省略）：只能是布林 true＝至少完成過一次。
##
## 動作 ACTION="beach_treasure"，extra：
##   "start"        at＝告示牌 SIGN；不在 search 時開下一輪（可在結算後立刻再開），開的人自動加入
##   "join:<round>" at＝SIGN；加入目前這一輪（離開過的成員回來會恢復 joined 與貢獻）
##   "leave:<round>" 任何位置、任何區域；離開這一輪（貢獻保留）。斷線不改 state，重連仍是 joined。
##   "mark:<round>" at＝某個 SPOT 格，距離 <= REACH；為全隊標記該點（共用 marks）
##   "dig:<round>"  at＝某個 SPOT 格，距離 <= REACH；挖掘該點。每點每輪只能挖一次
##   <round> 必須是目前這輪的正規十進位（無正負號、無前導零、無空白），過期或重播都會被拒絕。
##
## 公開 API：valid(state)、public_view(state)（不含任何 token）、view(state,token)、
##           apply(state,token,at,extra,home)、step(state)、treasures_for(round)。

const KEY:="beach_treasure"
const ACTION:="beach_treasure"
const VIEW_KEY:="own_beach_treasure"
const SIGN:=Vector2i(50,55)
const AREA:=Rect2i(44,51,11,8)
const SPOTS:={
	"a":{"cell":Vector2i(46,56),"title":"貝灘西側"},
	"b":{"cell":Vector2i(49,55),"title":"木板道西邊"},
	"c":{"cell":Vector2i(52,55),"title":"東邊潮線"},
	"d":{"cell":Vector2i(48,57),"title":"石滬旁沙地"},
	"e":{"cell":Vector2i(50,57),"title":"木板道南端"},
	"f":{"cell":Vector2i(52,57),"title":"沙嘴東端"},
}
## 三組範本（每組 3 處、彼此不同）；第 round 輪用 TEMPLATES[round mod 3]。
const TEMPLATES:=[["a","c","e"],["b","d","f"],["a","d","f"]]
## 每個點四級線索：0 籠統、1 外觀、2 鄰近地標、3 直指地名。
const CLUES:={
	"a":["海風從西邊吹來，沙灘上有東西閃著微光。","貝殼特別多的沙地，靠近灘地的西端。","在木板道更西邊，碎貝殼鋪成一圈的地方。","就在「貝灘西側」，碎貝殼堆的下面。"],
	"b":["有個東西埋在木頭氣味很重的地方附近。","木板道的影子落在沙上，旁邊的沙比較潮。","靠近木板道西側，釘子頭露出一點點。","就在「木板道西邊」，木板影子的邊緣。"],
	"c":["潮水留下的痕跡旁，似乎藏了什麼。","沙上有一條彎彎的濕線，海草散落其間。","在灘地偏東，浪退後最先變乾的地方。","就在「東邊潮線」，海草線的上方。"],
	"d":["靠近一圈石頭堆起來的地方。","圓石圍成弧形，旁邊的沙特別鬆。","靠近石滬內側，小魚剛游過的水窪邊。","就在「石滬旁沙地」，石頭圍牆旁邊。"],
	"e":["走到木頭路快要結束的那一頭看看。","木板的尾端伸進沙裡，旁邊有細細的小腳印。","在灘地南邊，木板道走到底、沙變白的地方。","就在「木板道南端」，木板盡頭的沙地。"],
	"f":["往海岸最尖、最偏東的地方找找。","沙子堆成細長的一條，三面都吹著海風。","在灘地東南，細長沙堆快接上海水的地方。","就在「沙嘴東端」，沙堆尖尖的末端。"],
}
const FOUND_CLUE:="已挖到：%s。"
const REACH:=3.2
const DURATION:=300.0
const CLUE_STEP:=60.0
const MAX_LEVEL:=3
const TREASURES:=3
const POINTS:=3
const MAX_PLAYERS:=8
const MAX_ROUND:=1000000000
const EPSILON:=0.01
const IDLE:="idle"
const SEARCH:="search"
const RESULTS:="results"
const SHARED_KEYS:=["found","marks","members","phase","reason","round","started","wrong"]

const LOCKED:="完成渡口野餐後，海灘尋寶才會開放。"
const WRONG_REGION:="海灘尋寶在家園的海灘，請回到家園再參加。"
const NO_PLAYER:="請重新加入世界再參加海灘尋寶。"
const BAD_RECORD:="海灘尋寶的紀錄無法讀取，請重新操作。"
const BAD_EXTRA:="請重新操作海灘尋寶。"
const WRONG_SIGN:="請走到海灘的尋寶告示牌前開始或加入。"
const WRONG_SPOT:="請走到海灘上的挖掘點再操作。"
const TOO_FAR:="再靠近一點。"
const STALE:="海灘尋寶已更新，請重新打開告示牌。"
const ALREADY_ACTIVE:="這一輪還在進行，到告示牌前加入吧。"
const ENDING:="這一輪的時間到了，正在結算。"
const ROUND_LIMIT:="海灘尋寶的輪數已到上限。"
const NOT_ACTIVE:="這一輪已經結束了，到告示牌開下一輪吧。"
const ALREADY_JOINED:="你已經在這一輪裡了。"
const FULL:="這一輪已經有 8 位島民參加過，等下一輪再加入吧。"
const NOT_JOINED:="先在告示牌加入這一輪海灘尋寶。"
const ALREADY_MARKED:="這裡已經標記過了。"
const DUG:="這裡已經挖過了，換個地方找找。"

static func unlocked(state:Dictionary) -> bool:
	return state.get("picnic",false)==true

## 第 round 輪的三處埋寶點（伺服器用；不進任何快照）。
static func treasures_for(round_id:int) -> Array:
	return (TEMPLATES[posmod(round_id,TEMPLATES.size())] as Array).duplicate()

static func _now(state:Dictionary) -> float:
	var value:Variant=state.get("time",0.0)
	return float(value) if (value is int or value is float) and is_finite(float(value)) else 0.0

static func _done(person:Variant) -> bool:
	if not person is Dictionary:return false
	var flag:Variant=person.get(KEY)
	return flag is bool and flag==true

static func _whole(value:Variant,minimum:int,maximum:int) -> bool:
	if not (value is int or value is float):return false
	var number:=float(value)
	return is_finite(number) and floorf(number)==number and number>=float(minimum) and number<=float(maximum)

static func _ids_of(raw:Variant,allowed:Array) -> Variant:
	if not raw is Dictionary:return null
	var result:={}
	for id in raw:
		if not id is String or id not in allowed:return null
		if not raw[id] is bool or raw[id]!=true:return null
		result[id]=true
	return result

## 共用紀錄的形狀檢查；通過時回傳正規化後的深層副本，否則 null。
static func _shared_of(raw:Variant,players:Variant,now:float) -> Variant:
	if not raw is Dictionary or raw.size()!=SHARED_KEYS.size() or not players is Dictionary:return null
	for field in SHARED_KEYS:
		if not raw.has(field):return null
	if not _whole(raw.round,1,MAX_ROUND):return null
	if not raw.phase is String or raw.phase not in [SEARCH,RESULTS]:return null
	if not raw.reason is String or raw.reason not in ["","goal","time"]:return null
	if not (raw.started is int or raw.started is float):return null
	var started:=float(raw.started)
	if not is_finite(started) or started<0.0 or started>now+EPSILON:return null
	if not raw.members is Dictionary or raw.members.size()<1 or raw.members.size()>MAX_PLAYERS:return null
	var members:={}
	var any_dug:=false
	for token in raw.members:
		if not token is String or not players.get(token) is Dictionary:return null
		var entry:Variant=raw.members[token]
		if not entry is Dictionary or entry.size()!=2 or not entry.has("joined") or not entry.has("dug"):return null
		if not entry.joined is bool or not entry.dug is bool:return null
		members[token]={"joined":entry.joined,"dug":entry.dug}
		if entry.dug:any_dug=true
	var round_id:=int(raw.round)
	var targets:=treasures_for(round_id)
	var others:Array=[]
	for id:String in SPOTS:
		if id not in targets:others.append(id)
	var found:Variant=_ids_of(raw.found,targets)
	var wrong:Variant=_ids_of(raw.wrong,others)
	var marks:Variant=_ids_of(raw.marks,SPOTS.keys())
	if found==null or wrong==null or marks==null:return null
	if (found.size()+wrong.size())>0 and not any_dug:return null
	if raw.phase==SEARCH:
		if raw.reason!="" or found.size()>=TREASURES:return null
	else:
		if raw.reason=="goal" and found.size()!=TREASURES:return null
		if raw.reason=="time" and found.size()>=TREASURES:return null
		if raw.reason=="":return null
		for token:String in members:
			if members[token].dug and not _done(players[token]):return null
	return {"round":round_id,"phase":raw.phase,"started":started,"reason":raw.reason,
		"members":members,"found":found,"marks":marks,"wrong":wrong}

## 目前的共用紀錄（已驗證的副本）；沒有或損壞時 null。
static func _load(state:Dictionary) -> Variant:
	if not state.has(KEY):return null
	return _shared_of(state[KEY],state.get("players"),_now(state))

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
	if shared.phase!=SEARCH:return 0
	return clampi(ceili(float(shared.started)+DURATION-now),0,int(DURATION))

static func _level(shared:Dictionary,now:float) -> int:
	if shared.phase==RESULTS:return MAX_LEVEL
	var elapsed:=clampf(now-float(shared.started),0.0,DURATION)
	return mini(MAX_LEVEL,int(floorf(elapsed/CLUE_STEP))+(shared.wrong as Dictionary).size())

static func _clues(shared:Dictionary,now:float) -> Array[String]:
	var level:=_level(shared,now)
	var result:Array[String]=[]
	for id:String in treasures_for(int(shared.round)):
		if shared.found.has(id):result.append(FOUND_CLUE%str(SPOTS[id].title))
		else:result.append(str((CLUES[id] as Array)[level]))
	return result

static func _idle_public() -> Dictionary:
	var clues:Array[String]=[]
	return {"round":0,"phase":IDLE,"remaining":0,"found":{},"marks":{},"searched":{},"clues":clues,"score":0,"guests":0,"reason":""}

## 公開快照：沒有 token、沒有尚未找到的目標；found/marks 以挖掘點 id 為鍵。
static func public_view(state:Dictionary) -> Dictionary:
	var shared:Variant=_load(state)
	if shared==null:return _idle_public()
	var now:=_now(state)
	return {"round":int(shared.round),"phase":str(shared.phase),"remaining":_remaining(shared,now),
		"found":(shared.found as Dictionary).duplicate(),"marks":(shared.marks as Dictionary).duplicate(),
		"searched":(shared.wrong as Dictionary).duplicate(),
		"clues":_clues(shared,now),"score":(shared.found as Dictionary).size()*POINTS,
		"guests":_joined_count(shared),"reason":str(shared.reason)}

## 本人用摘要（Session 以 data.own_beach_treasure 送出）。
static func view(state:Dictionary,token:String) -> Dictionary:
	var open:=unlocked(state)
	var players:Variant=state.get("players",{})
	var person:Variant=players.get(token) if players is Dictionary else null
	var shared:Variant=_load(state)
	var joined:=false
	var dug:=false
	var running:=false
	var capped:=false
	if shared!=null:
		var entry:Variant=shared.members.get(token)
		if entry is Dictionary:
			joined=entry.joined==true
			dug=entry.dug==true
		running=shared.phase==SEARCH
		capped=int(shared.round)>=MAX_ROUND
	elif state.has(KEY):
		open=false
	return {"unlocked":open,"joined":joined,"completed":_done(person),"dug":dug,
		"can_start":open and not running and not capped}

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

## 正規十進位輪次：1..MAX_ROUND、只有數字、沒有前導零；其他一律 -1。
static func _round_text(text:String) -> int:
	if text.is_empty() or text.length()>10 or text.begins_with("0"):return -1
	for i in range(text.length()):
		if text[i]<"0" or text[i]>"9":return -1
	var number:=int(text)
	return number if number>=1 and number<=MAX_ROUND else -1

## 回傳 {"kind","round"}；格式錯誤回傳空字典。
static func _parse(extra:String) -> Dictionary:
	if extra=="start":return {"kind":"start","round":-1}
	var parts:=extra.split(":")
	if parts.size()!=2 or parts[0] not in ["join","leave","mark","dig"]:return {}
	var round_id:=_round_text(parts[1])
	if round_id<0:return {}
	return {"kind":parts[0],"round":round_id}

static func _spot_at(at:Vector2i) -> String:
	for id:String in SPOTS:
		if SPOTS[id].cell==at:return id
	return ""

## 結算：發紀念給每位挖過的成員，phase 立即變 results。
static func _settle(state:Dictionary,shared:Dictionary,reason:String) -> void:
	var players:Dictionary=state.players
	for token:String in shared.members:
		if shared.members[token].dug==true:players[token][KEY]=true
	shared.phase=RESULTS
	shared.reason=reason
	state[KEY]=shared

## 一個動作。World 只負責把 actor 所在區域（home）傳進來；失敗時 state 完全不變。
static func apply(state:Dictionary,token:String,at:Vector2i,extra:String,home:bool) -> Dictionary:
	if not unlocked(state):return _fail(LOCKED)
	var parsed:=_parse(extra)
	if parsed.is_empty():return _fail(BAD_EXTRA)
	var kind:String=parsed.kind
	if kind!="leave" and not home:return _fail(WRONG_REGION)
	var players:Variant=state.get("players")
	var person:Variant=players.get(token) if players is Dictionary else null
	if not person is Dictionary:return _fail(NO_PLAYER)
	if person.has(KEY) and not _done(person):return _fail(BAD_RECORD)
	var now:=_now(state)
	var shared:Variant=null
	if state.has(KEY):
		shared=_shared_of(state[KEY],players,now)
		if shared==null:return _fail(BAD_RECORD)
	var spot_id:=""
	if kind!="leave":
		var target:=SIGN
		if kind=="mark" or kind=="dig":
			spot_id=_spot_at(at)
			if spot_id.is_empty():return _fail(WRONG_SPOT)
			target=SPOTS[spot_id].cell
		elif at!=SIGN:
			return _fail(WRONG_SIGN)
		var px:=float(person.get("x",0.0))
		var py:=float(person.get("y",0.0))
		if not is_finite(px) or not is_finite(py):return _fail(TOO_FAR)
		if Vector2(px,py).distance_to(Vector2(target)+Vector2(0.5,0.5))>REACH:return _fail(TOO_FAR)
	var expired:bool=shared!=null and shared.phase==SEARCH and now>=float(shared.started)+DURATION
	if kind=="start":
		var current:=0
		if shared!=null:
			if shared.phase==SEARCH:return _fail(ENDING if expired else ALREADY_ACTIVE)
			current=int(shared.round)
		if current>=MAX_ROUND:return _fail(ROUND_LIMIT)
		state[KEY]={"round":current+1,"phase":SEARCH,"started":now,"reason":"",
			"members":{token:{"joined":true,"dug":false}},"found":{},"marks":{},"wrong":{}}
		return {"ok":true,"message":"第 %d 輪海灘尋寶開始！5 分鐘內找出 %d 處寶物，線索會隨時間和挖錯的地方越來越清楚。"%[current+1,TREASURES]}
	if shared==null or int(parsed.round)!=int(shared.round):return _fail(STALE)
	if shared.phase!=SEARCH:return _fail(NOT_ACTIVE)
	var round_id:=int(shared.round)
	var members:Dictionary=shared.members
	var entry:Variant=members.get(token)
	var joined:bool=entry is Dictionary and entry.joined==true
	if kind=="join":
		if expired:return _fail(ENDING)
		if joined:return _fail(ALREADY_JOINED)
		if entry==null and members.size()>=MAX_PLAYERS:return _fail(FULL)
		members[token]={"joined":true,"dug":entry is Dictionary and entry.dug==true}
		state[KEY]=shared
		return {"ok":true,"message":"加入第 %d 輪海灘尋寶！大家共用線索和標記。"%round_id}
	if not joined:return _fail(NOT_JOINED)
	if kind=="leave":
		members[token].joined=false
		state[KEY]=shared
		return {"ok":true,"message":"離開海灘尋寶。你的貢獻會保留，隨時可以回到告示牌再加入。"}
	if expired:return _fail(ENDING)
	var title:String=SPOTS[spot_id].title
	if kind=="mark":
		if shared.marks.has(spot_id):return _fail(ALREADY_MARKED)
		if shared.found.has(spot_id) or shared.wrong.has(spot_id):return _fail(DUG)
		shared.marks[spot_id]=true
		state[KEY]=shared
		return {"ok":true,"message":"在「%s」插上標記，全隊都看得到。"%title}
	# dig
	if shared.found.has(spot_id) or shared.wrong.has(spot_id):return _fail(DUG)
	members[token].dug=true
	if spot_id in treasures_for(round_id):
		shared.found[spot_id]=true
		var total:int=(shared.found as Dictionary).size()
		if total>=TREASURES:
			_settle(state,shared,"goal")
			return {"ok":true,"message":"在「%s」挖到寶物！三處全找到了，共 %d 分，挖過的島民各收下一份紀念。"%[title,total*POINTS]}
		state[KEY]=shared
		return {"ok":true,"message":"在「%s」挖到寶物！+%d 分，已找到 %d / %d 處。"%[title,POINTS,total,TREASURES]}
	shared.wrong[spot_id]=true
	state[KEY]=shared
	return {"ok":true,"message":"「%s」什麼也沒有，沒有扣分，但線索變得更清楚了。"%title}

## World.step 每個 tick 呼叫：搜尋中且時間到就結算。只改 state，有變更時回傳 true；
## World 負責存檔。
static func step(state:Dictionary) -> bool:
	var shared:Variant=_load(state)
	if shared==null or shared.phase!=SEARCH:return false
	if _now(state)<float(shared.started)+DURATION:return false
	_settle(state,shared,"time")
	return true
