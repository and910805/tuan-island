extends RefCounted
## T071 第四個合作活動「河岸釣魚會」（1～8 人，5 分鐘）：在河灣橋南邊指定的一段
## 河面一起釣魚，把釣到的魚記進共用的魚種卡後放回河裡；結束時發紀念票。
##
## 規劃書第 19 章：河岸釣魚會｜1～8 人，5 分鐘｜在指定水域共同記錄魚種｜沒釣到也有
## 參與紀錄。活動不出售不可替代的成長資源；背包未被清空，退出或斷線也可恢復。獎勵
## 以一次性參與記錄發放。T071 驗收：退出活動後背包維持原樣，且獎勵不重發。
## 紀念票只是 player.fish_meet 裡的計數，不是背包物品、也不是鈴幣，與豐收接力的
## 紀念票分開計算。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；同樣的 state 與動作永遠得到同樣結果；
## 失敗時 state 完全不變。
##
## ── 場地（家園座標，渡口野餐後解鎖，只在風鈴渡口）──────────────────────────
## 家園的河是 x=55..56 兩欄（河灣橋在 55..56,29..31）。河岸 x=54..57 本來就是
## World.protected 的公共河岸（不能建造），所以告示牌放在西岸上、橋南邊：
##   告示牌 SIGN (54,38)
##   指定水域 WATERS = Rect2i(55,34,2,6)：x 55..56、y 34..39 的 12 格河面（含既有
##     釣魚測試慣用的 (55,34)；離橋最近的一列 y=34 與橋隔兩列）。
##   岸邊站位 SHORE（介面提示用；不是規則限制）：西岸 (54,34)(54,35)(54,36)(54,39)
##     (54,40) 與再往西一格 (53,34)(53,36)(53,37)(53,38)(53,39)。每一格都能站、
##     在既有釣魚距離 3.2 內能對 WATERS 拋竿，距告示牌不超過 8 格（10 個位置，8 人站得下）。
## 告示牌本身與正下方 (54,39) 都沒有 base_resource 固定樹、石、草（(54,37) 是固定
## 岩石，所以牌子在它南邊）；不碰（含 8 鄰格）任何既有互動點、居民站位、出生點、
## 市集／出貨箱／共餐桌候選、節慶點、豐收接力五格、轉乘點、河灣橋、採石點與銅礦，
## 也不碰測試與預覽常用的水泵位 (53,36)、(53,33)。
## 佔用處理：告示牌格的 objects/ground/roofs/crops/forest 有東西時活動「暫停」
## （available()==false：開始／加入回 UNAVAILABLE，釣魚照一般規則進背包）；解鎖後
## 空著時保留（World.protected/blocked：不能建造、不能穿越）。已有東西不保留，所以
## 舊存檔不會失效，清掉後恢復。
##
## ── 共用回合 state.fish_meet（可省略；舊存檔視為 fresh()，第一次成功開始才寫入）
##   {"round":int, "active":bool, "started":float, "ends":float(=started+DURATION),
##    "records":int, "index":int(=records，已記錄的魚數),
##    "species":{"carp":int,"minnow":int,"redfish":int,"loach":int}（四鍵固定）,
##    "participants":{token:{"caught":int, "joined":bool}},
##    "last":{} 或 {"round","records","species"(種數),"players","tickets",
##             "reason":"goal"/"time","finished"},
##    "ready":float(上一輪結束時間＋COOLDOWN)}
##   participants 保留到下一輪開始（結算後供成果顯示）。
## ── 個人紀錄 player.fish_meet（可省略；只在結算時寫入）
##   {"tickets":int, "rounds":int, "best":int(最多筆數), "paid_round":int}
## 注意：player.fishing 是既有的拋竿狀態，與本活動無關、不會被本活動改動（除了
## 魚種卡記錄成功時照常收線＝erase）。
##
## ── 規則 ──
## 釣魚本身不變：同樣的 fish_start／fish_catch、輕鬆／標準（追魚影）兩種釣法。
## World 在 fish_catch 通過所有既有檢查（含標準釣法的追蹤進度）之後、發魚之前呼叫
## record_catch()：在家園、已加入進行中的一輪、拋竿格在 WATERS 內時，這一竿成為「釣魚會
## 紀錄」：魚種＝kind_at(round,index)；index+1、records+1、species[魚]+1、本人
## caught+1、收線（erase player.fishing）；玩家其他欄位全部不變——不進背包、不加
## fish_caught、不動保底計數、不記圖鑑、不給鈴幣。時間到但 step 還沒跑時回 ENDING
## （state 不變）。沒加入的人在 WATERS 釣魚、已加入的人在 WATERS 外釣魚，都照一般
## 規則（魚進背包）。
## 魚種序列（無亂數）：KINDS=["carp","minnow","redfish","loach"]（Collections.FISH 的
## 家園溪魚）；ORDER=["carp","minnow","carp","redfish","minnow","carp","loach","minnow"]；
## kind_at(round,index)=ORDER[posmod(round*3+index*5,8)]（5 與 8 互質，連續 8 筆一定
## 出現全部四種）。
## 結算：records 達 GOAL 時在 record_catch 裡立即結算（reason "goal"），否則 step() 在
## time>=ends 時結算（reason "time"）。每位參加者（含中途離開、離線、一條都沒釣到
## 的人）得 tickets_for(種數,筆數)=1+(四種都記到 ?1:0)+(筆數>=GOAL ?1:0) 張紀念票，
## 每輪只發一次（paid_round 防重發），rounds+1，best=max(best,records)。
## 離開／斷線／出遠門：entry.joined=false，貢獻保留，可再加入同一輪；拋竿狀態不動。
## 斷線：Session 呼叫 World.fish_meet_disconnect → drop()（隨後存檔）；step() 每次也
## 把不在線或不在家園的參加者設為 joined=false。
##
## ── 公開 API（伺服器與介面共用）──
##   const ACTIONS=["fish_meet_start","fish_meet_join","fish_meet_leave"], HOME, NO_CELL,
##         SIGN, WATERS(Rect2i), SHORE(Array[Vector2i]), KINDS, ORDER, GOAL=12,
##         DURATION=300.0, COOLDOWN=60.0, MAX_PLAYERS=8, MAX_ENTRIES=32, SIGN_REACH=3.2,
##         MAX_BONUS=2, MAX_TICKETS, MAX_ROUNDS, 訊息常數（LOCKED, WRONG_REGION,
##         UNAVAILABLE, WRONG_SIGN, TOO_FAR_SIGN, STALE, ALREADY_ACTIVE, COOLDOWN_MSG(%d),
##         NOT_ACTIVE, ENDING, ALREADY_JOINED, FULL(%d), TOO_MANY, NOT_JOINED, BAD_EXTRA,
##         NO_PLAYER）
##   static func unlocked(snapshot) -> bool                 # state.picnic==true
##   static func cell_free(snapshot,cell:Vector2i) -> bool
##   static func available(snapshot) -> bool                # 已解鎖且告示牌格空著
##   static func reserved(snapshot,p:Vector2i) -> bool      # 解鎖後空著的告示牌格
##   static func in_waters(p:Vector2i) -> bool
##   static func water_cells() -> Array                     # WATERS 的 12 格（列優先）
##   static func kind_at(round:int,index:int) -> String
##   static func kind_name(kind:String) -> String           # Collections.FISH 名稱
##   static func tickets_for(species_count:int,records:int) -> int
##   static func fresh() -> Dictionary
##   static func round_state(state) -> Dictionary           # 唯讀，沒有時 fresh()
##   static func record(person) -> Dictionary               # 唯讀，沒有時 fresh_record()
##   static func view(state,token) -> Dictionary            # 本人用（data.own_fish_meet）
##   static func public(state) -> Dictionary                # 公開快照（無 token）
##   static func apply(state,token,action,p,extra,at_home:bool) -> Dictionary
##   static func record_catch(state,token,p:Vector2i,at_home:bool) -> Dictionary
##                     # World 的 fish_catch 掛勾。{} = 不是釣魚會紀錄（照一般釣魚）；
##                     # 否則 {"ok","message"}，成功時另有 "fish_meet":魚種 id
##                     # （暫停中、未解鎖、不在家園、沒加入或不在 WATERS 都回 {}）
##   static func step(state,online:Dictionary) -> bool
##   static func drop(state,token) -> bool
##   static func valid(s:Dictionary) -> bool                # 存檔檢查（兩個欄位）
## World 另有 World.fish_meet_available(snapshot)、World.fish_meet_view(token)、
## World.fish_meet_disconnect(token) 包裝。
##
## view(state,token) 的鍵（data.own_fish_meet）：
##   unlocked, available, sign(Vector2i), waters(Array[Vector2i]), waters_rect(Rect2i),
##   shore(Array[Vector2i]), round, active, seconds_left, goal, records,
##   species{id:count}, species_names[{"id","name","count"}]（固定 KINDS 順序）,
##   species_count, species_total(=4), joined, caught(本人), participants[{"name",
##   "caught","joined","me"}]（依 token 排序，不含 token）, joined_count, max_players,
##   cooldown, can_start, last, tickets, rounds, best
## public(state)（快照 data.fish_meet）：round, active, started, ends, seconds_left,
##   records, goal, species{id:count}, species_count, ready, last,
##   participants{sha256(token).left(16):{"name","caught","joined"}}
##
## 動作的 extra：fish_meet_start 與 fish_meet_join 的 p 必須是 SIGN、extra 必須是目前的
## round 字串（view.round），防止重複開始或加入到不同輪；fish_meet_leave 的 extra 必須
## 是空字串（p 不看）。釣魚會紀錄沒有新動作：照常 fish_start(水面格, ""/"standard")、
## fish_catch(同一格)。

const ACTIONS:=["fish_meet_start","fish_meet_join","fish_meet_leave"]
const HOME:="home"
const NO_CELL:=Vector2i(-1,-1)
const SIGN:=Vector2i(54,38)
const WATERS:=Rect2i(55,34,2,6)
const SHORE:=[Vector2i(54,34),Vector2i(54,35),Vector2i(54,36),Vector2i(54,39),Vector2i(54,40),
	Vector2i(53,34),Vector2i(53,36),Vector2i(53,37),Vector2i(53,38),Vector2i(53,39)]
const KINDS:=["carp","minnow","redfish","loach"]
const ORDER:=["carp","minnow","carp","redfish","minnow","carp","loach","minnow"]
const GOAL:=12
const DURATION:=300.0
const COOLDOWN:=60.0
const MAX_PLAYERS:=8
const MAX_ENTRIES:=32
const SIGN_REACH:=3.2
const MAX_BONUS:=2
const MAX_TICKETS:=999999
const MAX_ROUNDS:=999999
const MAX_ROUND:=1000000000
const KEYS:=["active","ends","index","last","participants","ready","records","round","species","started"]
const ENTRY_KEYS:=["caught","joined"]
const LAST_KEYS:=["finished","players","reason","records","round","species","tickets"]
const RECORD_KEYS:=["best","paid_round","rounds","tickets"]
const EPSILON:=0.01
const Collections=preload("res://scripts/collections.gd")

const LOCKED:="完成渡口野餐後，河灣橋南邊的河岸釣魚會才會開放。"
const WRONG_REGION:="河岸釣魚會在風鈴渡口的河灣橋南岸，請回到渡口再參加。"
const UNAVAILABLE:="河岸釣魚會的告示牌位置被占住了，先把那一格整理出來。"
const WRONG_SIGN:="請走到河岸釣魚會的告示牌前開始或加入。"
const TOO_FAR_SIGN:="再靠近河岸釣魚會的告示牌一點。"
const STALE:="活動已更新，請重新打開活動面板。"
const ALREADY_ACTIVE:="河岸釣魚會已經開始了，在告示牌前按加入就能一起釣。"
const COOLDOWN_MSG:="魚種卡正在整理，約 %d 秒後能再開始。"
const NOT_ACTIVE:="現在沒有進行中的河岸釣魚會，先在告示牌開始一輪。"
const ENDING:="這一輪的時間到了，正在結算。"
const ALREADY_JOINED:="你已經在這一輪裡了。"
const FULL:="這一輪已經有 %d 位島民，等下一輪再加入吧。"
const TOO_MANY:="這一輪的參加名單已滿，等下一輪再加入吧。"
const NOT_JOINED:="先在告示牌加入河岸釣魚會。"
const BAD_EXTRA:="請重新操作河岸釣魚會。"
const NO_PLAYER:="請重新加入世界再參加河岸釣魚會。"

static func unlocked(snapshot:Dictionary) -> bool:
	return snapshot.get("picnic",false)==true

static func cell_free(snapshot:Dictionary,cell:Vector2i) -> bool:
	var tile:="%d,%d"%[cell.x,cell.y]
	for field in ["objects","ground","roofs","crops","forest"]:
		var layer:Variant=snapshot.get(field,{})
		if layer is Dictionary and layer.has(tile):return false
	return true

## 已解鎖且告示牌格沒有被佔用。
static func available(snapshot:Dictionary) -> bool:
	return unlocked(snapshot) and cell_free(snapshot,SIGN)

## 解鎖後仍空著的告示牌格（World 用來禁止建造與穿越）。
static func reserved(snapshot:Dictionary,p:Vector2i) -> bool:
	return p==SIGN and unlocked(snapshot) and cell_free(snapshot,p)

static func in_waters(p:Vector2i) -> bool:
	return WATERS.has_point(p)

static func water_cells() -> Array:
	var out:=[]
	for y in range(WATERS.position.y,WATERS.end.y):
		for x in range(WATERS.position.x,WATERS.end.x):out.append(Vector2i(x,y))
	return out

static func kind_at(round_id:int,index:int) -> String:
	return str(ORDER[posmod(round_id*3+index*5,ORDER.size())])

static func kind_name(kind:String) -> String:
	return str(Collections.FISH[kind].name) if kind in KINDS else ""

static func tickets_for(species_count:int,records:int) -> int:
	return 1+(1 if species_count>=KINDS.size() else 0)+(1 if records>=GOAL else 0)

static func fresh_species() -> Dictionary:
	var out:={}
	for kind:String in KINDS:out[kind]=0
	return out

static func fresh() -> Dictionary:
	return {"round":0,"active":false,"started":0.0,"ends":0.0,"records":0,"index":0,"species":fresh_species(),"participants":{},"last":{},"ready":0.0}

static func fresh_record() -> Dictionary:
	return {"tickets":0,"rounds":0,"best":0,"paid_round":0}

static func fresh_entry() -> Dictionary:
	return {"caught":0,"joined":true}

static func round_state(state:Dictionary) -> Dictionary:
	var found:Variant=state.get("fish_meet")
	return found if found is Dictionary else fresh()

static func record(person:Dictionary) -> Dictionary:
	var found:Variant=person.get("fish_meet")
	return found if found is Dictionary else fresh_record()

## 種數：species 裡次數大於 0 的魚種數。
static func species_count(species:Variant) -> int:
	var count:=0
	if species is Dictionary:
		for kind:String in KINDS:
			if int(species.get(kind,0))>0:count+=1
	return count

## round 的前 n 筆紀錄各魚種的次數（存檔檢查用）。
static func species_after(round_id:int,n:int) -> Dictionary:
	var out:=fresh_species()
	for i in range(n):
		var kind:=kind_at(round_id,i)
		out[kind]=int(out[kind])+1
	return out

static func _name_of(state:Dictionary,token:String) -> String:
	var person:Variant=state.get("players",{}).get(token)
	return str(person.get("name","島民")) if person is Dictionary else "島民"

static func _joined_count(meet:Dictionary) -> int:
	var count:=0
	for token in meet.participants:
		if meet.participants[token].get("joined")==true:count+=1
	return count

static func _expired(state:Dictionary,meet:Dictionary) -> bool:
	return meet.active==true and float(state.get("time",0.0))>=float(meet.ends)

static func _species_copy(meet:Dictionary) -> Dictionary:
	var out:={}
	for kind:String in KINDS:out[kind]=int((meet.species as Dictionary).get(kind,0)) if meet.species is Dictionary else 0
	return out

## 只給本人看的摘要（Session 以 data.own_fish_meet 送給本人）。不含任何 token。
static func view(state:Dictionary,token:String) -> Dictionary:
	var meet:=round_state(state)
	var now:=float(state.get("time",0.0))
	var person:Variant=state.get("players",{}).get(token,{})
	var own:=record(person if person is Dictionary else {})
	var entry:Dictionary=meet.participants.get(token,{}) if meet.participants is Dictionary else {}
	var tokens:Array=meet.participants.keys()
	tokens.sort()
	var list:=[]
	for other:String in tokens:
		var e:Dictionary=meet.participants[other]
		list.append({"name":_name_of(state,other),"caught":int(e.caught),"joined":e.joined==true,"me":other==token})
	var species:=_species_copy(meet)
	var names:=[]
	for kind:String in KINDS:names.append({"id":kind,"name":kind_name(kind),"count":int(species[kind])})
	var active:bool=meet.active==true
	var cooldown:=0.0 if active else maxf(0.0,float(meet.ready)-now)
	var open:=available(state)
	return {"unlocked":unlocked(state),"available":open,
		"sign":SIGN,"waters":water_cells(),"waters_rect":WATERS,"shore":SHORE.duplicate(),
		"round":int(meet.round),"active":active,
		"seconds_left":maxf(0.0,float(meet.ends)-now) if active else 0.0,
		"goal":GOAL,"records":int(meet.records),"species":species,"species_names":names,
		"species_count":species_count(species),"species_total":KINDS.size(),
		"joined":entry.get("joined",false)==true,"caught":int(entry.get("caught",0)),
		"participants":list,"joined_count":_joined_count(meet),"max_players":MAX_PLAYERS,
		"cooldown":cooldown,"can_start":open and not active and cooldown<=0.0,
		"last":(meet.last as Dictionary).duplicate(true),
		"tickets":int(own.tickets),"rounds":int(own.rounds),"best":int(own.best)}

## 公開快照（每個區域、每位接收者都一樣）：參加者以 sha256(token) 前 16 碼為鍵，
## 與 Session 公開的 player id 相同。
static func public(state:Dictionary) -> Dictionary:
	var meet:=round_state(state)
	var now:=float(state.get("time",0.0))
	var people:={}
	for token in meet.participants:
		var e:Dictionary=meet.participants[token]
		people[String(token).sha256_text().left(16)]={"name":_name_of(state,str(token)),"caught":int(e.caught),"joined":e.joined==true}
	var active:bool=meet.active==true
	var species:=_species_copy(meet)
	return {"round":int(meet.round),"active":active,"started":float(meet.started),"ends":float(meet.ends),
		"seconds_left":maxf(0.0,float(meet.ends)-now) if active else 0.0,
		"records":int(meet.records),"goal":GOAL,"species":species,"species_count":species_count(species),
		"ready":float(meet.ready),"last":(meet.last as Dictionary).duplicate(true),"participants":people}

static func _distance(person:Dictionary,cell:Vector2i) -> float:
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## 三個活動動作。World 只負責把 actor 是否在家園（at_home）傳進來；
## 失敗時 state 完全不變（先在副本上操作，成功才寫回）。
static func apply(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,at_home:bool) -> Dictionary:
	if not unlocked(state):return _fail(LOCKED)
	if not at_home:return _fail(WRONG_REGION)
	var person:Variant=state.get("players",{}).get(token)
	if not person is Dictionary:return _fail(NO_PLAYER)
	if state.has("fish_meet") and not state.fish_meet is Dictionary:return _fail(BAD_EXTRA)
	if action!="fish_meet_leave" and not available(state):return _fail(UNAVAILABLE)
	var meet:Dictionary=round_state(state).duplicate(true)
	var now:=float(state.get("time",0.0))
	var entry:Dictionary=meet.participants.get(token,{})
	var message:=""
	if action=="fish_meet_start":
		if p!=SIGN:return _fail(WRONG_SIGN)
		if _distance(person,SIGN)>SIGN_REACH:return _fail(TOO_FAR_SIGN)
		if _expired(state,meet):return _fail(ENDING)
		if meet.active==true:return _fail(ALREADY_ACTIVE)
		if now<float(meet.ready):return _fail(COOLDOWN_MSG%ceili(float(meet.ready)-now))
		if extra!=str(int(meet.round)):return _fail(STALE)
		if int(meet.round)>=MAX_ROUND:return _fail(STALE)
		meet.round=int(meet.round)+1
		meet.active=true
		meet.started=now
		meet.ends=now+DURATION
		meet.records=0
		meet.index=0
		meet.species=fresh_species()
		meet.participants={token:fresh_entry()}
		message="第 %d 輪河岸釣魚會開始！在告示牌旁的河面拋竿，5 分鐘內一起記錄 %d 筆魚種。釣到的魚記進魚種卡後放回河裡，背包不會變動。"%[int(meet.round),GOAL]
	elif action=="fish_meet_join":
		if p!=SIGN:return _fail(WRONG_SIGN)
		if _distance(person,SIGN)>SIGN_REACH:return _fail(TOO_FAR_SIGN)
		if meet.active!=true:return _fail(NOT_ACTIVE)
		if _expired(state,meet):return _fail(ENDING)
		if extra!=str(int(meet.round)):return _fail(STALE)
		if entry.get("joined",false)==true:return _fail(ALREADY_JOINED)
		if _joined_count(meet)>=MAX_PLAYERS:return _fail(FULL%MAX_PLAYERS)
		if entry.is_empty():
			if meet.participants.size()>=MAX_ENTRIES:return _fail(TOO_MANY)
			entry=fresh_entry()
			meet.participants[token]=entry
		entry.joined=true
		message="加入第 %d 輪河岸釣魚會！在告示牌旁的河面釣到的魚會記進魚種卡後放回河裡，背包不會變動。"%int(meet.round)
	elif action=="fish_meet_leave":
		if not extra.is_empty():return _fail(BAD_EXTRA)
		if meet.active!=true:return _fail(NOT_ACTIVE)
		if entry.get("joined",false)!=true:return _fail(NOT_JOINED)
		entry.joined=false
		message="離開河岸釣魚會。背包沒有變動；你的參與紀錄會保留到這一輪結算。"
	else:
		return _fail(BAD_EXTRA)
	state.fish_meet=meet
	return {"ok":true,"message":message}

## World 在 fish_catch 通過既有檢查後、發魚之前呼叫。p＝拋竿格（== player.fishing）。
## 回傳 {}：不是釣魚會紀錄，照一般釣魚。回傳 ok：已記錄並收線，玩家其他欄位不變。
## 回傳 fail（ENDING）：state 不變。
static func record_catch(state:Dictionary,token:String,p:Vector2i,at_home:bool) -> Dictionary:
	if not at_home or not in_waters(p) or not available(state):return {}
	var found:Variant=state.get("fish_meet")
	if not found is Dictionary or found.get("active")!=true:return {}
	var person:Variant=state.get("players",{}).get(token)
	if not person is Dictionary:return {}
	var entry:Variant=(found.participants as Dictionary).get(token) if found.get("participants") is Dictionary else null
	if not entry is Dictionary or entry.get("joined")!=true:return {}
	if _expired(state,found):return _fail(ENDING)
	if int(found.records)>=GOAL:return _fail(ENDING)
	var meet:Dictionary=found.duplicate(true)
	var mine:Dictionary=meet.participants[token]
	var kind:=kind_at(int(meet.round),int(meet.index))
	meet.index=int(meet.index)+1
	meet.records=int(meet.records)+1
	meet.species[kind]=int(meet.species.get(kind,0))+1
	mine.caught=int(mine.caught)+1
	state.fish_meet=meet
	person.erase("fishing")
	var count:=species_count(meet.species)
	if int(meet.records)>=GOAL:
		_finish(state,meet,"goal")
		return {"ok":true,"message":"釣到了%s！記進釣魚會的魚種卡後放回河裡，背包沒有變動。%d 筆紀錄全部完成，參加者各得 %d 張紀念票。"%[kind_name(kind),GOAL,tickets_for(count,GOAL)],"fish_meet":kind}
	return {"ok":true,"message":"釣到了%s！記進釣魚會的魚種卡後放回河裡，背包沒有變動。大家記錄了 %d / %d 筆、%d / %d 種。"%[kind_name(kind),int(meet.records),GOAL,count,KINDS.size()],"fish_meet":kind}

## 結算目前這一輪：每位參加者（含離開、離線、沒釣到的人）各發一次紀念票。只改 state。
static func _finish(state:Dictionary,meet:Dictionary,reason:String) -> void:
	var round_id:=int(meet.round)
	var records:=int(meet.records)
	var count:=species_count(meet.species)
	var tickets:=tickets_for(count,records)
	var players:Variant=state.get("players",{})
	for token in meet.participants:
		var entry:Dictionary=meet.participants[token]
		entry.joined=false
		var person:Variant=players.get(token) if players is Dictionary else null
		if not person is Dictionary:continue
		var own:Dictionary=record(person).duplicate(true)
		if int(own.paid_round)>=round_id:continue
		own.tickets=mini(MAX_TICKETS,int(own.tickets)+tickets)
		own.rounds=mini(MAX_ROUNDS,int(own.rounds)+1)
		own.best=maxi(int(own.best),records)
		own.paid_round=round_id
		person.fish_meet=own
	var now:=float(state.get("time",0.0))
	meet.active=false
	meet.last={"round":round_id,"records":records,"species":count,"players":meet.participants.size(),
		"tickets":tickets,"reason":reason,"finished":now}
	meet.ready=now+COOLDOWN

static func _drop_entry(meet:Dictionary,token:String) -> bool:
	var entry:Variant=meet.participants.get(token)
	if not entry is Dictionary or entry.joined!=true:return false
	entry.joined=false
	return true

## Session 在玩家離線時呼叫（經 World.fish_meet_disconnect）。有變更時回傳 true。
static func drop(state:Dictionary,token:String) -> bool:
	var meet:Variant=state.get("fish_meet")
	if not meet is Dictionary or not meet.get("participants") is Dictionary:return false
	return _drop_entry(meet,token)

## World.step 每個 tick 呼叫：不在線或不在家園的參加者退出；時間到時結算（含離線
## 者）。只改 state，有變更時回傳 true。
static func step(state:Dictionary,online:Dictionary) -> bool:
	var meet:Variant=state.get("fish_meet")
	if not meet is Dictionary or not meet.get("participants") is Dictionary:return false
	var changed:=false
	var players:Variant=state.get("players",{})
	for token in meet.participants:
		var person:Variant=players.get(token) if players is Dictionary else null
		var away:bool=not online.has(token) or not person is Dictionary or str(person.get("region",HOME))!=HOME
		if away and _drop_entry(meet,token):changed=true
	if _expired(state,meet):
		_finish(state,meet,"time")
		changed=true
	return changed

# ------------------------------------------------------------------ schema --

## 存檔檢查：state.fish_meet 與每位 player.fish_meet 都可省略；存在時檢查型別、
## 上限、已知魚種、各數量一致（Σcaught==records==Σspecies==index，species 與魚種
## 序列重算相同）、joined 只在進行中、paid_round、時間不在未來。通過時把 JSON 讀回
## 的浮點整數正規化為 int。s.picnic 必須已由 validate_region 補好。
static func valid(s:Dictionary) -> bool:
	var players:Variant=s.get("players")
	if not players is Dictionary:return false
	var now:=float(s.get("time",0.0))
	var has_round:=s.has("fish_meet")
	var meet:Dictionary={}
	if has_round:
		if s.get("picnic")!=true:return false
		if not _valid_round(s.fish_meet,players,now):return false
		meet=s.fish_meet
	var limit:=0
	if has_round:limit=int(meet.round)-(1 if meet.active else 0)
	for token in players:
		var person:Variant=players[token]
		if not person is Dictionary or not person.has("fish_meet"):continue
		if not has_round:return false
		if not _valid_record(person.fish_meet,limit):return false
	if has_round and int(meet.round)>=1 and not meet.active:
		for token in meet.participants:
			var person:Dictionary=players[token]
			if not person.has("fish_meet") or int(person.fish_meet.paid_round)!=int(meet.round):return false
	return true

static func _valid_species(species:Variant) -> bool:
	if not species is Dictionary or species.size()!=KINDS.size():return false
	for kind:String in KINDS:
		if not species.has(kind) or not _whole(species[kind],0,GOAL):return false
	return true

static func _same_species(species:Dictionary,expected:Dictionary) -> bool:
	for kind:String in KINDS:
		if int(species[kind])!=int(expected[kind]):return false
	return true

static func _valid_round(meet:Variant,players:Dictionary,now:float) -> bool:
	if not meet is Dictionary or meet.size()!=KEYS.size():return false
	for field in KEYS:
		if not meet.has(field):return false
	if not _whole(meet.round,0,MAX_ROUND) or not meet.active is bool:return false
	for field in ["started","ends","ready"]:
		if not _number(meet[field],0.0,1.0e12):return false
	if not _whole(meet.records,0,GOAL) or not _whole(meet.index,0,GOAL):return false
	if not _valid_species(meet.species):return false
	var round_id:=int(meet.round)
	var records:=int(meet.records)
	if int(meet.index)!=records:return false
	if not _same_species(meet.species,species_after(round_id,records)):return false
	if meet.active and (round_id<1 or records>=GOAL):return false
	if round_id==0 and (records!=0 or float(meet.started)!=0.0 or float(meet.ends)!=0.0 or float(meet.ready)!=0.0):return false
	if round_id>=1:
		if float(meet.started)>now+EPSILON or absf(float(meet.ends)-float(meet.started)-DURATION)>EPSILON:return false
	var participants:Variant=meet.participants
	if not participants is Dictionary or participants.size()>MAX_ENTRIES:return false
	if round_id==0 and not participants.is_empty():return false
	if round_id>=1 and participants.is_empty():return false
	var caught_total:=0
	var joined:=0
	for token in participants:
		if not token is String or not players.has(token):return false
		var e:Variant=participants[token]
		if not e is Dictionary or e.size()!=ENTRY_KEYS.size():return false
		for field in ENTRY_KEYS:
			if not e.has(field):return false
		if not e.joined is bool or not _whole(e.caught,0,GOAL):return false
		if e.joined and not meet.active:return false
		if e.joined:joined+=1
		caught_total+=int(e.caught)
	if joined>MAX_PLAYERS or caught_total!=records:return false
	var last:Variant=meet.last
	if not last is Dictionary:return false
	var finished_round:=round_id if not meet.active else round_id-1
	if finished_round<=0:
		if not last.is_empty():return false
	else:
		if last.size()!=LAST_KEYS.size():return false
		for field in LAST_KEYS:
			if not last.has(field):return false
		if not _whole(last.round,1,MAX_ROUND) or int(last.round)!=finished_round:return false
		if not _whole(last.records,0,GOAL) or not _whole(last.species,0,KINDS.size()):return false
		if int(last.species)!=species_count(species_after(int(last.round),int(last.records))):return false
		if not _whole(last.players,1,MAX_ENTRIES) or not _whole(last.tickets,1,1+MAX_BONUS):return false
		if int(last.tickets)!=tickets_for(int(last.species),int(last.records)):return false
		if not last.reason is String or last.reason not in ["goal","time"]:return false
		if last.reason=="goal" and int(last.records)!=GOAL:return false
		if last.reason=="time" and int(last.records)>=GOAL:return false
		if not _number(last.finished,0.0,now+EPSILON):return false
		if absf(float(meet.ready)-float(last.finished)-COOLDOWN)>EPSILON:return false
		if not meet.active:
			# The finished round is the current one: its numbers and roster must agree.
			if int(last.records)!=records or int(last.players)!=participants.size():return false
			if float(last.finished)+EPSILON<float(meet.started):return false
			if last.reason=="time" and float(last.finished)+EPSILON<float(meet.ends):return false
		elif float(meet.started)+EPSILON<float(last.finished)+COOLDOWN:
			return false
	for field in ["round","records","index"]:meet[field]=int(meet[field])
	for field in ["started","ends","ready"]:meet[field]=float(meet[field])
	for kind:String in KINDS:meet.species[kind]=int(meet.species[kind])
	for token in participants:
		var e:Dictionary=participants[token]
		e.caught=int(e.caught)
	if not last.is_empty():
		for field in ["round","records","species","players","tickets"]:last[field]=int(last[field])
		last.finished=float(last.finished)
	return true

static func _valid_record(own:Variant,limit:int) -> bool:
	if not own is Dictionary or own.size()!=RECORD_KEYS.size():return false
	for field in RECORD_KEYS:
		if not own.has(field):return false
	if not _whole(own.rounds,1,MAX_ROUNDS) or not _whole(own.tickets,1,MAX_TICKETS):return false
	if not _whole(own.best,0,GOAL) or not _whole(own.paid_round,1,maxi(limit,0)):return false
	if int(own.tickets)<int(own.rounds) or int(own.tickets)>mini(MAX_TICKETS,int(own.rounds)*(1+MAX_BONUS)):return false
	for field in RECORD_KEYS:own[field]=int(own[field])
	return true

static func _number(value:Variant,minimum:float,maximum:float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum

static func _whole(value:Variant,minimum:int,maximum:int) -> bool:
	return _number(value,float(minimum),float(maximum)) and floorf(float(value))==float(value)

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}
