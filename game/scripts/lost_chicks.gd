extends RefCounted
## P05 合作活動「迷路小雞」（1～8 人，世界時間 180 秒）：把走散的小雞用飼料桶引回雞舍，
## 每隻帶回雞舍 +2 分。
##
## 渡口野餐後（state.picnic）解鎖，只在家園進行。沒有一般物品、鈴幣、背包、真雞變更，
## 也沒有個人獎勵：飼料桶是借用的（只存在於本輪成員紀錄），離開或斷線就歸還。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；時間只看 state.time。失敗時 state 完全不變
## （先在副本上檢查，最後才寫回）。存檔由 World 負責；step() 只改 state 並回傳「需要存檔的
## 變更」是否發生（見下）。
##
## 共用 state.lost_chicks（可省略；第一次開始才寫入），欄位固定：
##   {"round":int(1..1e9), "phase":"run"|"results", "mode":"solo"|"crew",
##    "started":float, "next":float,
##    "members":{token:{"joined":bool,"bucket":bool}}（1..8，累計不超過 8 位；
##        run 中 bucket==joined；results 時 bucket 一律 false）,
##    "chicks":[{"x":int,"y":int,"status":"lost"|"follow"|"home","by":token|""}]
##        （solo 2 隻、crew 6 隻，順序固定；follow 的 by 是跟隨的成員，其他為 ""；
##         home 一律在 PEN 格）,
##    "returned":int, "score":int（= returned * POINTS）}
##   mode 在開始時依「在線且在家園」的人數決定（>=2 為 crew），之後固定。
##   members 與 by 只在伺服器端；public_view 不含 token。
##
## 規則：
##   - "start" 開新輪並自動加入（拿到飼料桶）；中途 "join:<round>" 也領借用桶。
##     離開／斷線後必須明確再 join 才會恢復（不會自動重新加入）。
##   - 帶著桶的成員走近（<= LURE_RADIUS）自由的小雞會自動引誘，小雞開始跟隨；
##     每位成員同時最多帶 1 隻。
##   - 跟隨中的小雞以 4 方向單格跳躍靠近成員所在格（間隔 STEP_MIN..STEP_MIN+STEP_SPAN 秒，
##     由 state.time 決定，不會瞬移）。每一步是否能走由呼叫端 can_step(token,from,to)->bool 決定
##     （可檢查碰撞、邊界），會找圍欄與樹木旁可走的路。
##   - 成員走到圍欄附近，跟隨的小雞能跨進圍欄時才得分。
##   - 全部帶回來就提前結算；時間到（DURATION）則剩下的小雞自動回雞舍，但沒有分數。
##   - 全員離開不會結束這一輪：之後仍可有人中途加入，直到全部帶回或時間到。
##   - 離開、斷線、離開家園：成員 joined=false、桶歸還、帶的小雞留在原地變回 lost。
##
## step 的存檔語意：回傳 true 代表「持久內容有變」（成員、小雞位置／狀態、帶回數、結算）。
## 跳躍排程 next 是暫時值：每次跳躍嘗試才推進；若本次完全沒有移動（例如被 can_step 擋住），
## next 仍會在記憶體中推進。World 把純移動併入定時存檔，回圈和結算立即存檔。
##
## 指令 ACTION="lost_chicks"，extra（<round> 必須是目前這輪的正規十進位）：
##   "start"          at＝SIGN；idle／results 時開新輪並自動加入
##   "join:<round>"   at＝SIGN；run 中加入（或離開後回來），領借用飼料桶
##   "leave:<round>"  任何位置、任何區域；離開並歸還桶
##
## 公開 API：valid(state,candidate)、public_view(state)、view(state,token)、
##           apply(state,token,cell,extra,home,active_tokens)、step(state,active_tokens,can_step)。
## active_tokens 為 World.active_tokens（{token:true}；也接受 Array）。

const KEY:="lost_chicks"
const ACTION:="lost_chicks"
const VIEW_KEY:="own_lost_chicks"
const SIGN:=Vector2i(49,40)
const PEN:=Vector2i(51,40)
const AREA:=Rect2i(47,37,10,9)
const SOLO_SPOTS:=[Vector2i(49,42),Vector2i(52,42)]
const CREW_SPOTS:=[Vector2i(48,43),Vector2i(50,44),Vector2i(53,43),Vector2i(54,39),Vector2i(54,42),Vector2i(52,38)]
const REACH:=3.2
const DURATION:=180.0
const LURE_RADIUS:=1.5
const PEN_RADIUS:=1.5
const WALK_DIRECTIONS:=[Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]
const STEP_MIN:=0.3
const STEP_SPAN:=0.15
const POINTS:=2
const MAX_PLAYERS:=8
const MAX_ROUND:=1000000000
const EPSILON:=0.01
const HOME:="home"
const IDLE:="idle"
const RUN:="run"
const RESULTS:="results"
const SOLO:="solo"
const CREW:="crew"
const LOST:="lost"
const FOLLOW:="follow"
const AT_PEN:="home"
const SHARED_KEYS:=["chicks","members","mode","next","phase","returned","round","score","started"]
const CHICK_KEYS:=["by","status","x","y"]

const LOCKED:="完成渡口野餐後，迷路小雞才會開放。"
const WRONG_REGION:="迷路小雞在家園，請回到家園再參加。"
const NO_PLAYER:="請重新加入世界再參加迷路小雞。"
const BAD_RECORD:="迷路小雞的紀錄無法讀取，請重新操作。"
const BAD_EXTRA:="請重新操作迷路小雞。"
const WRONG_SIGN:="請走到雞舍旁的告示牌前開始或加入。"
const TOO_FAR:="再靠近一點。"
const NOT_ONLINE:="請先連線並回到家園再參加迷路小雞。"
const STALE:="迷路小雞已更新，請重新打開告示牌。"
const ALREADY_ACTIVE:="這一輪還在進行，到告示牌前加入吧。"
const ENDING:="這一輪的時間到了，正在結算。"
const ROUND_LIMIT:="迷路小雞的輪數已到上限。"
const NOT_ACTIVE:="這一輪已經結束了，到告示牌開下一輪吧。"
const ALREADY_JOINED:="你已經在這一輪裡了。"
const FULL:="這一輪已經有 8 位島民參加過，等下一輪再加入吧。"
const NOT_JOINED:="你不在這一輪裡。"

static func unlocked(state:Dictionary) -> bool:
	return state.get("picnic",false)==true

static func _now(state:Dictionary) -> float:
	var value:Variant=state.get("time",0.0)
	return float(value) if (value is int or value is float) and is_finite(float(value)) else 0.0

static func _whole(value:Variant,minimum:int,maximum:int) -> bool:
	if not (value is int or value is float):return false
	var number:=float(value)
	return is_finite(number) and floorf(number)==number and number>=float(minimum) and number<=float(maximum)

static func _total_of(mode:String) -> int:
	return SOLO_SPOTS.size() if mode==SOLO else CREW_SPOTS.size()

static func _is_active(active:Variant,token:String) -> bool:
	if active is Dictionary:return (active as Dictionary).has(token)
	if active is Array:return token in (active as Array)
	return false

static func _at_home(person:Variant) -> bool:
	return person is Dictionary and str((person as Dictionary).get("region",HOME))==HOME

## 人物目前位置（浮點格座標）；不是有限數字時回傳 null。
static func _position(person:Variant) -> Variant:
	if not person is Dictionary:return null
	var px:Variant=(person as Dictionary).get("x",0.0)
	var py:Variant=(person as Dictionary).get("y",0.0)
	if not (px is int or px is float) or not (py is int or py is float):return null
	if not is_finite(float(px)) or not is_finite(float(py)):return null
	return Vector2(float(px),float(py))

## 共用紀錄的形狀檢查；通過時回傳正規化後的深層副本，否則 null。
static func _shared_of(raw:Variant,players:Variant,now:float) -> Variant:
	if not raw is Dictionary or raw.size()!=SHARED_KEYS.size() or not players is Dictionary:return null
	for field in SHARED_KEYS:
		if not raw.has(field):return null
	if not _whole(raw.round,1,MAX_ROUND):return null
	if not raw.phase is String or raw.phase not in [RUN,RESULTS]:return null
	if not raw.mode is String or raw.mode not in [SOLO,CREW]:return null
	if not (raw.started is int or raw.started is float):return null
	var started:=float(raw.started)
	if not is_finite(started) or started<0.0 or started>now+EPSILON:return null
	if not (raw.next is int or raw.next is float):return null
	var next:=float(raw.next)
	if not is_finite(next) or next<0.0 or next>now+STEP_MIN+STEP_SPAN+EPSILON:return null
	var phase:String=raw.phase
	var mode:String=raw.mode
	var total:=_total_of(mode)
	if not raw.members is Dictionary or raw.members.size()<1 or raw.members.size()>MAX_PLAYERS:return null
	var members:={}
	for token in raw.members:
		if not token is String or not players.get(token) is Dictionary:return null
		var entry:Variant=raw.members[token]
		if not entry is Dictionary or entry.size()!=2 or not entry.has("joined") or not entry.has("bucket"):return null
		if not entry.joined is bool or not entry.bucket is bool:return null
		if phase==RUN and entry.bucket!=entry.joined:return null
		if phase==RESULTS and entry.bucket:return null
		members[token]={"joined":entry.joined,"bucket":entry.bucket}
	if not _whole(raw.returned,0,total) or not _whole(raw.score,0,total*POINTS):return null
	var returned:=int(raw.returned)
	if int(raw.score)!=returned*POINTS:return null
	if not raw.chicks is Array or raw.chicks.size()!=total:return null
	var chicks:Array=[]
	var home:=0
	var leaders:={}
	for source in raw.chicks:
		if not source is Dictionary or source.size()!=CHICK_KEYS.size():return null
		for field in CHICK_KEYS:
			if not source.has(field):return null
		if not _whole(source.x,AREA.position.x,AREA.end.x-1) or not _whole(source.y,AREA.position.y,AREA.end.y-1):return null
		if not source.status is String or source.status not in [LOST,FOLLOW,AT_PEN]:return null
		if not source.by is String:return null
		var cell:=Vector2i(int(source.x),int(source.y))
		var by:String=source.by
		if source.status==FOLLOW:
			if phase!=RUN or not members.has(by) or members[by].joined!=true or leaders.has(by):return null
			leaders[by]=true
		else:
			if by!="":return null
			if source.status==AT_PEN:
				if cell!=PEN:return null
				home+=1
		chicks.append({"x":cell.x,"y":cell.y,"status":source.status,"by":by})
	if phase==RUN:
		if home!=returned or returned>=total:return null
	else:
		if home!=total or returned>total or next!=0.0:return null
	return {"round":int(raw.round),"phase":phase,"mode":mode,"started":started,"next":next,
		"members":members,"chicks":chicks,"returned":returned,"score":returned*POINTS}

## 目前的共用紀錄（已驗證的副本）；沒有或損壞時 null。
static func _load(state:Dictionary) -> Variant:
	if not state.has(KEY):return null
	return _shared_of(state[KEY],state.get("players"),_now(state))

## 存檔檢查：共用紀錄可省略；存在時需野餐已完成。candidate 給定時改驗證那份新狀態
## （不是 Dictionary 一律不合法）。通過時把 JSON 讀回的浮點整數正規化為 int（寫回被檢查的狀態）。
static func valid(state:Dictionary,candidate:Variant=null) -> bool:
	var target:Dictionary=state
	if candidate!=null:
		if not candidate is Dictionary:return false
		target=candidate
	if not target.get("players") is Dictionary:return false
	if not target.has(KEY):return true
	if target.get("picnic")!=true:return false
	var shared:Variant=_load(target)
	if shared==null:return false
	target[KEY]=shared
	return true

static func _remaining(shared:Dictionary,now:float) -> int:
	if shared.phase!=RUN:return 0
	return clampi(ceili(float(shared.started)+DURATION-now),0,int(DURATION))

static func _idle_public() -> Dictionary:
	return {"phase":IDLE,"round":0,"mode":"","chicks":[],"score":0,"remaining":0,"returned":0,"total":0}

## 公開快照：沒有 token（by 不輸出）。
static func public_view(state:Dictionary) -> Dictionary:
	var shared:Variant=_load(state)
	if shared==null:return _idle_public()
	var chicks:Array=[]
	for chick:Dictionary in shared.chicks:
		chicks.append({"x":int(chick.x),"y":int(chick.y),"status":str(chick.status)})
	return {"phase":str(shared.phase),"round":int(shared.round),"mode":str(shared.mode),"chicks":chicks,
		"score":int(shared.score),"remaining":_remaining(shared,_now(state)),
		"returned":int(shared.returned),"total":_total_of(str(shared.mode))}

## 本人用摘要（Session 以 data.own_lost_chicks 送出）。
static func view(state:Dictionary,token:String) -> Dictionary:
	var open:=unlocked(state)
	var shared:Variant=_load(state)
	var joined:=false
	if shared!=null:
		var entry:Variant=shared.members.get(token)
		joined=shared.phase==RUN and entry is Dictionary and entry.joined==true
	elif state.has(KEY):
		open=false
	return {"unlocked":open,"joined":joined}

static func _fail(text:String) -> Dictionary:
	return {"ok":false,"text":text}

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
	if parts.size()!=2 or parts[0] not in ["join","leave"]:return {}
	var round_id:=_round_text(parts[1])
	if round_id<0:return {}
	return {"kind":parts[0],"round":round_id}

## 在線且在家園的人數（開始時決定 solo／crew 用）。
static func _home_count(state:Dictionary,active:Variant) -> int:
	var players:Dictionary=state.players
	var count:=0
	for token in players:
		if token is String and _is_active(active,token) and _at_home(players[token]):count+=1
	return count

static func _release(shared:Dictionary,token:String) -> void:
	for chick:Dictionary in shared.chicks:
		if chick.status==FOLLOW and chick.by==token:
			chick.status=LOST
			chick.by=""

static func _leads(shared:Dictionary,token:String) -> bool:
	for chick:Dictionary in shared.chicks:
		if chick.status==FOLLOW and chick.by==token:return true
	return false

## 結算：所有小雞回雞舍（沒帶回的不給分）、桶歸還、phase 立即變 results。
static func _settle(state:Dictionary,shared:Dictionary) -> void:
	for chick:Dictionary in shared.chicks:
		chick.x=PEN.x
		chick.y=PEN.y
		chick.status=AT_PEN
		chick.by=""
	for token:String in shared.members:
		shared.members[token].bucket=false
	shared.phase=RESULTS
	shared.next=0.0
	state[KEY]=shared

## 一個動作。World 只負責把 actor 所在區域（home）與 active_tokens 傳進來；失敗時 state 完全不變。
static func apply(state:Dictionary,token:String,cell:Vector2i,extra:String,home:bool,active_tokens:Variant,can_step:=Callable()) -> Dictionary:
	if not unlocked(state):return _fail(LOCKED)
	var parsed:=_parse(extra)
	if parsed.is_empty():return _fail(BAD_EXTRA)
	var kind:String=parsed.kind
	if kind!="leave" and not home:return _fail(WRONG_REGION)
	var players:Variant=state.get("players")
	var person:Variant=players.get(token) if players is Dictionary else null
	if not person is Dictionary:return _fail(NO_PLAYER)
	var now:=_now(state)
	var shared:Variant=null
	if state.has(KEY):
		shared=_shared_of(state[KEY],players,now)
		if shared==null:return _fail(BAD_RECORD)
	if kind!="leave":
		if cell!=SIGN:return _fail(WRONG_SIGN)
		var at:Variant=_position(person)
		if at==null or (at as Vector2).distance_to(Vector2(SIGN)+Vector2(0.5,0.5))>REACH:return _fail(TOO_FAR)
		if not _is_active(active_tokens,token):return _fail(NOT_ONLINE)
	var expired:bool=shared!=null and shared.phase==RUN and now>=float(shared.started)+DURATION
	if kind=="start":
		var current:=0
		if shared!=null:
			if shared.phase==RUN:return _fail(ENDING if expired else ALREADY_ACTIVE)
			current=int(shared.round)
		if current>=MAX_ROUND:return _fail(ROUND_LIMIT)
		var mode:=CREW if _home_count(state,active_tokens)>=2 else SOLO
		var preferred:Array=CREW_SPOTS if mode==CREW else SOLO_SPOTS
		var spots:=_starting_spots(preferred,token,can_step)
		if spots.size()!=preferred.size():return _fail("圍欄附近沒有足夠的通路。先清出入口和周圍的空地吧。")
		var chicks:Array=[]
		for spot:Vector2i in spots:
			chicks.append({"x":spot.x,"y":spot.y,"status":LOST,"by":""})
		state[KEY]={"round":current+1,"phase":RUN,"mode":mode,"started":now,"next":0.0,
			"members":{token:{"joined":true,"bucket":true}},"chicks":chicks,"returned":0,"score":0}
		if mode==SOLO:
			return {"ok":true,"text":"第 %d 輪迷路小雞開始！拿著飼料桶靠近小雞，把 %d 隻都帶回雞舍。"%[current+1,chicks.size()]}
		return {"ok":true,"text":"第 %d 輪迷路小雞開始！%d 隻小雞散在各處，大家分頭帶回雞舍，晚到的也能加入。"%[current+1,chicks.size()]}
	if shared==null or int(parsed.round)!=int(shared.round):return _fail(STALE)
	if shared.phase!=RUN:return _fail(NOT_ACTIVE)
	var round_id:int=int(shared.round)
	var members:Dictionary=shared.members
	var entry:Variant=members.get(token)
	var joined:bool=entry is Dictionary and entry.joined==true
	if kind=="join":
		if expired:return _fail(ENDING)
		if joined:return _fail(ALREADY_JOINED)
		if entry==null and members.size()>=MAX_PLAYERS:return _fail(FULL)
		members[token]={"joined":true,"bucket":true}
		state[KEY]=shared
		return {"ok":true,"text":"加入第 %d 輪迷路小雞，借到一個飼料桶！"%round_id}
	if not joined:return _fail(NOT_JOINED)
	members[token]={"joined":false,"bucket":false}
	_release(shared,token)
	state[KEY]=shared
	return {"ok":true,"text":"離開迷路小雞，飼料桶已歸還，跟著你的小雞會停在原地。"}

static func _starting_spots(preferred:Array,token:String,can_step:Callable) -> Array:
	if not can_step.is_valid():return preferred
	if not can_step.call(token,PEN,PEN):return []
	var queue:Array[Vector2i]=[PEN]
	var visited:Dictionary={PEN:true}
	var i:=0
	while i<queue.size():
		var origin:=queue[i]
		i+=1
		for offset:Vector2i in WALK_DIRECTIONS:
			var to:=origin+offset
			if not AREA.has_point(to) or visited.has(to) or not can_step.call(token,origin,to):continue
			visited[to]=true
			queue.append(to)
	var available:=queue.filter(func(cell:Vector2i):
		return cell!=SIGN and not preferred.has(cell) and absi(cell.x-PEN.x)+absi(cell.y-PEN.y)>1)
	var spots:Array=[]
	for cell:Vector2i in preferred:
		if visited.has(cell):
			spots.append(cell)
		elif not available.is_empty():
			spots.append(available.pop_front())
	return spots

static func return_bucket(state:Dictionary,token:String) -> void:
	var shared:Variant=_load(state)
	if shared==null or shared.phase!=RUN:return
	if not shared.members.get(token,{}).get("joined",false):return
	shared.members[token]={"joined":false,"bucket":false}
	_release(shared,token)
	state[KEY]=shared

static func _hop(shared:Dictionary,index:int,origin:Vector2i,goal:Vector2i,token:String,can_step:Callable) -> Vector2i:
	var initial_distance:=absi(goal.x-origin.x)+absi(goal.y-origin.y)
	if initial_distance<=1 or not can_step.is_valid():return origin
	var occupied:Dictionary={}
	for i in range(shared.chicks.size()):
		var other:Dictionary=shared.chicks[i]
		if i!=index and other.status!=AT_PEN:occupied[Vector2i(other.x,other.y)]=true
	var queue:Array[Vector2i]=[origin]
	var first_step:Dictionary={origin:origin}
	var closest:=origin
	var closest_distance:=initial_distance
	var cursor:=0
	while cursor<queue.size():
		var from:=queue[cursor]
		cursor+=1
		for offset:Vector2i in WALK_DIRECTIONS:
			var to:=from+offset
			if not AREA.has_point(to) or occupied.has(to) or first_step.has(to):continue
			if not can_step.call(token,from,to):continue
			first_step[to]=to if from==origin else first_step[from]
			var distance:=absi(goal.x-to.x)+absi(goal.y-to.y)
			if distance<=1:return first_step[to]
			if distance<closest_distance:
				closest=to
				closest_distance=distance
			queue.append(to)
	return first_step[closest]

static func _pen_check(shared:Dictionary,players:Dictionary,can_step:Callable) -> bool:
	var changed:=false
	var center:=Vector2(PEN)+Vector2(0.5,0.5)
	for chick:Dictionary in shared.chicks:
		if chick.status!=FOLLOW:continue
		var leader:String=chick.by
		var at:Variant=_position(players[leader])
		if at==null or (at as Vector2).distance_to(center)>PEN_RADIUS:continue
		var cell:=Vector2i(chick.x,chick.y)
		if cell!=PEN:
			if absi(cell.x-PEN.x)+absi(cell.y-PEN.y)!=1:continue
			if not can_step.is_valid() or not can_step.call(leader,cell,PEN):continue
		chick.status=AT_PEN
		chick.by=""
		chick.x=PEN.x
		chick.y=PEN.y
		shared.returned=int(shared.returned)+1
		shared.score=int(shared.returned)*POINTS
		changed=true
	return changed

static func _interval(now:float) -> float:
	return STEP_MIN+STEP_SPAN*float(posmod(int(floorf(now*10.0)),4))/3.0

## World.step 每個 tick 呼叫（見檔頭的存檔語意）。
static func step(state:Dictionary,active_tokens:Variant,can_step:Callable,persist_motion:=true) -> bool:
	var shared:Variant=_load(state)
	if shared==null or shared.phase!=RUN:return false
	var now:=_now(state)
	if now>=float(shared.started)+DURATION:
		_settle(state,shared)
		return true
	var players:Dictionary=state.players
	var changed:=false
	var tokens:Array=(shared.members as Dictionary).keys()
	tokens.sort()
	# 斷線／離開家園：歸還桶、放開小雞（要再明確 join 才會恢復）
	for token:String in tokens:
		var entry:Dictionary=shared.members[token]
		if entry.joined==true and not (_is_active(active_tokens,token) and _at_home(players[token])):
			entry.joined=false
			entry.bucket=false
			_release(shared,token)
			changed=true
	# 引誘：帶桶、手上沒有小雞的成員，最近的自由小雞
	for token:String in tokens:
		var entry:Dictionary=shared.members[token]
		if entry.joined!=true or entry.bucket!=true or _leads(shared,token):continue
		var at:Variant=_position(players[token])
		if at==null:continue
		var best:=-1
		var best_distance:=INF
		for i in range(shared.chicks.size()):
			var chick:Dictionary=shared.chicks[i]
			if chick.status!=LOST:continue
			var distance:=(at as Vector2).distance_to(Vector2(chick.x,chick.y)+Vector2(0.5,0.5))
			if distance<=LURE_RADIUS and distance<best_distance:
				best=i
				best_distance=distance
		if best>=0:
			shared.chicks[best].status=FOLLOW
			shared.chicks[best].by=token
			changed=true
	if _pen_check(shared,players,can_step):changed=true
	var wrote:=changed
	var moved:=false
	# 跳躍：到時間才走一格
	var followers:Array[int]=[]
	for i in range(shared.chicks.size()):
		if shared.chicks[i].status==FOLLOW and int(shared.returned)<_total_of(str(shared.mode)):followers.append(i)
	if int(shared.returned)<_total_of(str(shared.mode)) and not followers.is_empty() and now>=float(shared.next):
		for i in followers:
			var chick:Dictionary=shared.chicks[i]
			var at:Variant=_position(players[str(chick.by)])
			if at==null:continue
			var goal:=Vector2i(floori((at as Vector2).x),floori((at as Vector2).y))
			var from:=Vector2i(chick.x,chick.y)
			var to:=_hop(shared,i,from,goal,str(chick.by),can_step)
			if to!=from:
				chick.x=to.x
				chick.y=to.y
				moved=true
		shared.next=now+_interval(now)
		wrote=true
		if _pen_check(shared,players,can_step):changed=true
	if int(shared.returned)>=_total_of(str(shared.mode)):
		_settle(state,shared)
		return true
	if wrote:state[KEY]=shared
	return changed or (persist_motion and moved)
