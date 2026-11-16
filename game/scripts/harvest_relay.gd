extends RefCounted
## T071 第三個合作活動「豐收接力」（1～8 人，3 分鐘）：從模型菜箱拿模型蔬菜、
## 傳給隊友、分類放進根菜／葉菜／果菜三個籃子；結束時照完成量給紀念票。
##
## 規劃書第 19 章：活動區內工具暫時替換為活動道具，離開後還原；背包未被清空，
## 退出或斷線也可恢復。獎勵以一次性參與記錄發放。T071 驗收：退出活動後背包還原
## 且獎勵不重發。活動不發成長資源：紀念票只是 player.harvest_relay 裡的計數，
## 不是背包物品、也不是鈴幣。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；同樣的 state 與動作永遠得到同樣結果。
##
## ── 場地（家園座標，渡口野餐後解鎖，只在風鈴渡口）──────────────────────────
## 廣場石板橢圓與 (35..45,27..37) 的無樹石方塊裡，每一格都已是互動點、居民站位、
## 市集／出貨箱／共餐桌候選、節慶停靠點、出生點與其鄰格，或是玩家（與既有測試）
## 慣用的建地（出生點東南 41..43,34..37、西南 34..37,33..37、東北空地
## 46..51,22..29）。所以活動放在廣場西緣、市集攤位再往西的空地：
##   告示牌 SIGN (32,30)、模型菜箱 CRATE (30,28)、
##   分類籃 根菜 (30,33)／葉菜 (32,33)／果菜 (34,32)。
## 五格本身與正下方都沒有 base_resource 固定樹、石（也沒有草）；彼此不相鄰；
## 不碰（含 8 鄰格）任何既有互動點、居民站位、出生點 (39,33)、市集候選、
## 出貨箱候選、共餐桌候選、節慶點、公告板 (40,29)，且距出生點中心超過 3.2；
## 三個籃子距菜箱 5～5.7 格，一個人拿了菜要走一段路，所以傳遞有意義。
## 佔用處理：五格任一格的 objects/ground/roofs/crops/forest 有東西時活動
## 「暫停」（available()==false，所有動作除了離開都回 UNAVAILABLE）；解鎖後仍空著
## 的格子各自保留（World.protected/blocked：不能建造、不能穿越），已有東西的格子
## 不保留，所以舊存檔不會失效，清掉後該格就被保留、活動恢復。
##
## ── 共用回合 state.harvest_relay（可省略；舊存檔視為 fresh()，第一次成功開始才寫入）
##   {"round":int, "active":bool, "started":float, "ends":float(=started+DURATION),
##    "delivered":int, "relays":int, "index":int(已拿出的模型菜數),
##    "participants":{token:{"carry":kind 或 "", "relay":bool, "sorted":int,
##                           "passed":int, "joined":bool}},
##    "last":{} 或 {"round","delivered","relays","players","tickets","reason":"goal"/"time","finished"},
##    "ready":float(上一輪結束時間＋COOLDOWN)}
##   relay＝手上這個模型菜至少被傳過一次；分類時算一次接力（relays+1，只是展示用的
##   接力加分，不加獎勵）。participants 保留到下一輪開始（結算後供成果顯示）。
## ── 個人紀錄 player.harvest_relay（可省略；只在結算時寫入）
##   {"tickets":int, "rounds":int, "best":int, "paid_round":int}
##
## ── 規則 ──
## 模型菜序列：kind_at(round,index)=ORDER[posmod(round*5+index*3, 8)]（每 8 個一循環）。
## 活動道具永遠不進背包：手上的模型菜只存在 participants[token].carry；離開、斷線、
## 出遠門、時間到或完成時直接消失（放回菜箱），從不碰 player.inventory/coins。
## 斷線：Session 在玩家離線時呼叫 World.harvest_disconnect → drop()（立即存檔）；
## 另外 step() 每次都把「不在線（online 不含 token）或不在家園」的參加者設為
## joined=false、carry=""（伺服器重啟、出遠門等情況的保險），所以模型菜不會卡住
## 或重複。離開／斷線的人貢獻保留，結算照樣發票，可以再加入同一輪。
## 結算：達到 GOAL 時在 harvest_sort 裡立即結算，否則 step() 在 time>=ends 時結算。
## 每位參加者（含中途離開、離線者）得 tickets_for(delivered)=1+min(3,delivered/8)
## 張紀念票，每輪只發一次（paid_round 防重發），rounds+1，best=max。
## 時間到但 step 還沒跑時，動作回 ENDING（離開除外）。
##
## ── 公開 API（伺服器與介面共用）──
##   const ACTIONS, SIGN, CRATE, BASKETS{"root","leaf","fruit"->Vector2i}, BASKET_ORDER,
##         BASKET_NAMES, CELLS, KINDS{kind->{"name","basket","icon"}}, ORDER, NO_CELL,
##         GOAL=24, DURATION=180.0, COOLDOWN=60.0, MAX_PLAYERS=8, MAX_ENTRIES=32,
##         SIGN_REACH=3.2, HAND_REACH=1.6, PASS_REACH=1.6, TICKET_STEP=8, MAX_BONUS=3,
##         MAX_TICKETS, MAX_ROUNDS, 訊息常數（LOCKED, WRONG_REGION, UNAVAILABLE, ...）
##   static func unlocked(snapshot:Dictionary) -> bool
##   static func cell_free(snapshot:Dictionary,cell:Vector2i) -> bool
##   static func available(snapshot:Dictionary) -> bool          # 已解鎖且五格都空
##   static func reserved(snapshot:Dictionary,p:Vector2i) -> bool # 解鎖後空著的活動格
##   static func basket_at(p:Vector2i) -> String                  # 不是籃子時 ""
##   static func kind_at(round:int,index:int) -> String
##   static func kind_name(kind:String) -> String
##   static func basket_of(kind:String) -> String
##   static func tickets_for(delivered:int) -> int
##   static func fresh() -> Dictionary
##   static func round_state(state:Dictionary) -> Dictionary      # 唯讀，沒有時 fresh()
##   static func record(person:Dictionary) -> Dictionary          # 唯讀，沒有時 fresh_record()
##   static func view(state:Dictionary,token:String) -> Dictionary   # 本人用（data.own_harvest）
##   static func public(state:Dictionary) -> Dictionary           # 公開快照（無 token）
##   static func apply(state,token,action,p,extra,at_home:bool,online:Dictionary) -> Dictionary
##   static func step(state:Dictionary,online:Dictionary) -> bool
##   static func drop(state:Dictionary,token:String) -> bool
##   static func valid(s:Dictionary) -> bool                      # 存檔檢查（兩個欄位）
## World 另有 World.harvest_available(snapshot)、World.harvest_view(token)、
## World.harvest_disconnect(token) 包裝。
##
## 動作的 extra：harvest_start 與 harvest_join 必須是目前的 round 字串（view.round），
## 防止重複開始或加入到不同輪；其他四個動作 extra 必須是空字串。harvest_pass、
## harvest_leave 不看 p（傳給 PASS_REACH 內最近的空手隊友；同距離依 token 排序）。

const ACTIONS:=["harvest_start","harvest_join","harvest_leave","harvest_pick","harvest_pass","harvest_sort"]
const HOME:="home"
const NO_CELL:=Vector2i(-1,-1)
const SIGN:=Vector2i(32,30)
const CRATE:=Vector2i(30,28)
const BASKETS:={"root":Vector2i(30,33),"leaf":Vector2i(32,33),"fruit":Vector2i(34,32)}
const BASKET_ORDER:=["root","leaf","fruit"]
const BASKET_NAMES:={"root":"根菜","leaf":"葉菜","fruit":"果菜"}
const CELLS:=[SIGN,CRATE,Vector2i(30,33),Vector2i(32,33),Vector2i(34,32)]
## 模型蔬菜：顯示名稱、所屬籃子、繪製用的既有物品圖示 id（InventoryItemArt.icon）。
const KINDS:={
	"radish":{"name":"模型蘿蔔","basket":"root","icon":"radish"},
	"carrot":{"name":"模型胡蘿蔔","basket":"root","icon":"carrot"},
	"potato":{"name":"模型馬鈴薯","basket":"root","icon":"potato"},
	"lettuce":{"name":"模型萵苣","basket":"leaf","icon":"lettuce"},
	"cabbage":{"name":"模型高麗菜","basket":"leaf","icon":"cabbage"},
	"tomato":{"name":"模型番茄","basket":"fruit","icon":"tomato"},
	"cucumber":{"name":"模型黃瓜","basket":"fruit","icon":"cucumber"},
	"eggplant":{"name":"模型茄子","basket":"fruit","icon":"eggplant"},
}
const ORDER:=["radish","lettuce","tomato","carrot","cabbage","cucumber","potato","eggplant"]
const GOAL:=24
const DURATION:=180.0
const COOLDOWN:=60.0
const MAX_PLAYERS:=8
const MAX_ENTRIES:=32
const SIGN_REACH:=3.2
const HAND_REACH:=1.6
const PASS_REACH:=1.6
const TICKET_STEP:=8
const MAX_BONUS:=3
const MAX_TICKETS:=999999
const MAX_ROUNDS:=999999
const MAX_ROUND:=1000000000
const MAX_INDEX:=1000000
const MAX_PASSED:=1000000
const KEYS:=["active","delivered","ends","index","last","participants","ready","relays","round","started"]
const ENTRY_KEYS:=["carry","joined","passed","relay","sorted"]
const LAST_KEYS:=["delivered","finished","players","reason","relays","round","tickets"]
const RECORD_KEYS:=["best","paid_round","rounds","tickets"]
const EPSILON:=0.01

const LOCKED:="完成渡口野餐後，廣場西側的豐收接力才會開放。"
const WRONG_REGION:="豐收接力在風鈴渡口的廣場西側，請回到渡口再參加。"
const UNAVAILABLE:="豐收接力的場地被占住了，先把告示牌、菜箱和分類籃的位置整理出來。"
const WRONG_SIGN:="請走到豐收接力的告示牌前開始或加入。"
const TOO_FAR_SIGN:="再靠近豐收接力的告示牌一點。"
const WRONG_CRATE:="請對準模型菜箱拿蔬菜。"
const TOO_FAR_CRATE:="走到模型菜箱旁邊，再拿蔬菜。"
const WRONG_BASKET_CELL:="請對準分類籃再放下蔬菜。"
const TOO_FAR_BASKET:="走到分類籃旁邊，再放下蔬菜。"
const STALE:="活動已更新，請重新打開活動面板。"
const ALREADY_ACTIVE:="豐收接力已經開始了，在告示牌前按加入就能一起玩。"
const COOLDOWN_MSG:="菜箱正在補貨，約 %d 秒後能再開始。"
const NOT_ACTIVE:="現在沒有進行中的豐收接力，先在告示牌開始一輪。"
const ENDING:="這一輪的時間到了，正在結算。"
const ALREADY_JOINED:="你已經在這一輪裡了。"
const FULL:="這一輪已經有 %d 位島民，等下一輪再加入吧。"
const TOO_MANY:="這一輪的參加名單已滿，等下一輪再加入吧。"
const NOT_JOINED:="先在告示牌加入豐收接力。"
const HANDS_FULL:="手上已經拿著模型蔬菜了，先傳給隊友或放進分類籃。"
const EMPTY_HANDS:="手上沒有模型蔬菜，先到菜箱拿一個。"
const NO_TARGET:="附近沒有空手的隊友，靠近一點再傳。"
const WRONG_BASKET:="%s是%s，要放進「%s」籃喔。"
const BAD_EXTRA:="請重新操作豐收接力。"
const NO_PLAYER:="請重新加入世界再參加豐收接力。"

static func unlocked(snapshot:Dictionary) -> bool:
	return snapshot.get("picnic",false)==true

static func cell_free(snapshot:Dictionary,cell:Vector2i) -> bool:
	var tile:="%d,%d"%[cell.x,cell.y]
	for field in ["objects","ground","roofs","crops","forest"]:
		var layer:Variant=snapshot.get(field,{})
		if layer is Dictionary and layer.has(tile):return false
	return true

## 已解鎖且五格都沒有被佔用。
static func available(snapshot:Dictionary) -> bool:
	if not unlocked(snapshot):return false
	for cell:Vector2i in CELLS:
		if not cell_free(snapshot,cell):return false
	return true

## 解鎖後仍空著的活動格（World 用來禁止建造與穿越）。
static func reserved(snapshot:Dictionary,p:Vector2i) -> bool:
	return p in CELLS and unlocked(snapshot) and cell_free(snapshot,p)

static func basket_at(p:Vector2i) -> String:
	for basket:String in BASKET_ORDER:
		if BASKETS[basket]==p:return basket
	return ""

static func kind_at(round_id:int,index:int) -> String:
	return str(ORDER[posmod(round_id*5+index*3,ORDER.size())])

static func kind_name(kind:String) -> String:
	return str(KINDS[kind].name) if KINDS.has(kind) else ""

static func basket_of(kind:String) -> String:
	return str(KINDS[kind].basket) if KINDS.has(kind) else ""

static func tickets_for(delivered:int) -> int:
	return 1+mini(MAX_BONUS,maxi(delivered,0)/TICKET_STEP)

static func fresh() -> Dictionary:
	return {"round":0,"active":false,"started":0.0,"ends":0.0,"delivered":0,"relays":0,"index":0,"participants":{},"last":{},"ready":0.0}

static func fresh_record() -> Dictionary:
	return {"tickets":0,"rounds":0,"best":0,"paid_round":0}

static func fresh_entry() -> Dictionary:
	return {"carry":"","relay":false,"sorted":0,"passed":0,"joined":true}

static func round_state(state:Dictionary) -> Dictionary:
	var found:Variant=state.get("harvest_relay")
	return found if found is Dictionary else fresh()

static func record(person:Dictionary) -> Dictionary:
	var found:Variant=person.get("harvest_relay")
	return found if found is Dictionary else fresh_record()

static func _name_of(state:Dictionary,token:String) -> String:
	var person:Variant=state.get("players",{}).get(token)
	return str(person.get("name","島民")) if person is Dictionary else "島民"

static func _joined_count(relay:Dictionary) -> int:
	var count:=0
	for token in relay.participants:
		if relay.participants[token].get("joined")==true:count+=1
	return count

static func _expired(state:Dictionary,relay:Dictionary) -> bool:
	return relay.active==true and float(state.get("time",0.0))>=float(relay.ends)

## 只給本人看的摘要（Session 以 data.own_harvest 送給本人）。不含任何 token。
static func view(state:Dictionary,token:String) -> Dictionary:
	var relay:=round_state(state)
	var now:=float(state.get("time",0.0))
	var person:Variant=state.get("players",{}).get(token,{})
	var own:=record(person if person is Dictionary else {})
	var entry:Dictionary=relay.participants.get(token,{}) if relay.participants is Dictionary else {}
	var carry:=str(entry.get("carry",""))
	var tokens:Array=relay.participants.keys()
	tokens.sort()
	var list:=[]
	for other:String in tokens:
		var e:Dictionary=relay.participants[other]
		list.append({"name":_name_of(state,other),"sorted":int(e.sorted),"passed":int(e.passed),
			"carry":str(e.carry),"carry_name":kind_name(str(e.carry)),"joined":e.joined==true,"me":other==token})
	var active:bool=relay.active==true
	var cooldown:=0.0 if active else maxf(0.0,float(relay.ready)-now)
	var open:=available(state)
	return {"unlocked":unlocked(state),"available":open,
		"sign":SIGN,"crate":CRATE,"baskets":BASKETS.duplicate(),
		"round":int(relay.round),"active":active,
		"seconds_left":maxf(0.0,float(relay.ends)-now) if active else 0.0,
		"goal":GOAL,"delivered":int(relay.delivered),"relays":int(relay.relays),
		"joined":entry.get("joined",false)==true,"carry":carry,"carry_name":kind_name(carry),
		"carry_basket":basket_of(carry),"carry_basket_name":str(BASKET_NAMES.get(basket_of(carry),"")),
		"carry_icon":str(KINDS[carry].icon) if KINDS.has(carry) else "","carry_relay":entry.get("relay",false)==true,
		"participants":list,"joined_count":_joined_count(relay),"max_players":MAX_PLAYERS,
		"cooldown":cooldown,"can_start":open and not active and cooldown<=0.0,
		"last":(relay.last as Dictionary).duplicate(true),
		"tickets":int(own.tickets),"rounds":int(own.rounds),"best":int(own.best)}

## 公開快照（每個區域、每位接收者都一樣）：參加者以 sha256(token) 前 16 碼為鍵，
## 與 Session 公開的 player id 相同，讓用戶端畫出誰手上拿著什麼。
static func public(state:Dictionary) -> Dictionary:
	var relay:=round_state(state)
	var now:=float(state.get("time",0.0))
	var people:={}
	for token in relay.participants:
		var e:Dictionary=relay.participants[token]
		people[String(token).sha256_text().left(16)]={"name":_name_of(state,str(token)),"carry":str(e.carry),
			"joined":e.joined==true,"sorted":int(e.sorted),"passed":int(e.passed)}
	var active:bool=relay.active==true
	return {"round":int(relay.round),"active":active,"started":float(relay.started),"ends":float(relay.ends),
		"seconds_left":maxf(0.0,float(relay.ends)-now) if active else 0.0,
		"delivered":int(relay.delivered),"relays":int(relay.relays),"goal":GOAL,"ready":float(relay.ready),
		"last":(relay.last as Dictionary).duplicate(true),"participants":people}

static func _distance(person:Dictionary,cell:Vector2i) -> float:
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## 六個活動動作。World 只負責把 actor 所在區域（at_home）和在線名單傳進來；
## 失敗時 state 完全不變（先在副本上操作，成功才寫回）。
static func apply(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,at_home:bool,online:Dictionary) -> Dictionary:
	if not unlocked(state):return _fail(LOCKED)
	if not at_home:return _fail(WRONG_REGION)
	var person:Variant=state.get("players",{}).get(token)
	if not person is Dictionary:return _fail(NO_PLAYER)
	if state.has("harvest_relay") and not state.harvest_relay is Dictionary:return _fail(BAD_EXTRA)
	if action!="harvest_leave" and not available(state):return _fail(UNAVAILABLE)
	var relay:Dictionary=round_state(state).duplicate(true)
	var now:=float(state.get("time",0.0))
	var entry:Dictionary=relay.participants.get(token,{})
	var message:=""
	if action=="harvest_start":
		if p!=SIGN:return _fail(WRONG_SIGN)
		if _distance(person,SIGN)>SIGN_REACH:return _fail(TOO_FAR_SIGN)
		if _expired(state,relay):return _fail(ENDING)
		if relay.active==true:return _fail(ALREADY_ACTIVE)
		if now<float(relay.ready):return _fail(COOLDOWN_MSG%ceili(float(relay.ready)-now))
		if extra!=str(int(relay.round)):return _fail(STALE)
		if int(relay.round)>=MAX_ROUND:return _fail(STALE)
		relay.round=int(relay.round)+1
		relay.active=true
		relay.started=now
		relay.ends=now+DURATION
		relay.delivered=0
		relay.relays=0
		relay.index=0
		relay.participants={token:fresh_entry()}
		message="第 %d 輪豐收接力開始！到菜箱拿模型蔬菜，傳給隊友、分類入籃，3 分鐘內一起完成 %d 個。活動道具不會放進背包。"%[int(relay.round),GOAL]
	elif action=="harvest_join":
		if p!=SIGN:return _fail(WRONG_SIGN)
		if _distance(person,SIGN)>SIGN_REACH:return _fail(TOO_FAR_SIGN)
		if relay.active!=true:return _fail(NOT_ACTIVE)
		if _expired(state,relay):return _fail(ENDING)
		if extra!=str(int(relay.round)):return _fail(STALE)
		if entry.get("joined",false)==true:return _fail(ALREADY_JOINED)
		if _joined_count(relay)>=MAX_PLAYERS:return _fail(FULL%MAX_PLAYERS)
		if entry.is_empty():
			if relay.participants.size()>=MAX_ENTRIES:return _fail(TOO_MANY)
			entry=fresh_entry()
			relay.participants[token]=entry
		entry.joined=true
		entry.carry=""
		entry.relay=false
		message="加入第 %d 輪豐收接力！活動道具只在活動裡使用，不會放進背包。"%int(relay.round)
	elif action=="harvest_leave":
		if not extra.is_empty():return _fail(BAD_EXTRA)
		if relay.active!=true:return _fail(NOT_ACTIVE)
		if entry.get("joined",false)!=true:return _fail(NOT_JOINED)
		entry.joined=false
		entry.carry=""
		entry.relay=false
		message="離開豐收接力。模型蔬菜放回菜箱，背包沒有變動；你的參與紀錄會保留到這一輪結算。"
	elif action=="harvest_pick":
		if not extra.is_empty():return _fail(BAD_EXTRA)
		if p!=CRATE:return _fail(WRONG_CRATE)
		if _distance(person,CRATE)>HAND_REACH:return _fail(TOO_FAR_CRATE)
		if relay.active!=true:return _fail(NOT_ACTIVE)
		if _expired(state,relay):return _fail(ENDING)
		if entry.get("joined",false)!=true:return _fail(NOT_JOINED)
		if not str(entry.carry).is_empty():return _fail(HANDS_FULL)
		if int(relay.index)>=MAX_INDEX:return _fail(ENDING)
		var kind:=kind_at(int(relay.round),int(relay.index))
		relay.index=int(relay.index)+1
		entry.carry=kind
		entry.relay=false
		message="拿到%s，送到「%s」籃，或傳給隊友。"%[kind_name(kind),BASKET_NAMES[basket_of(kind)]]
	elif action=="harvest_pass":
		if not extra.is_empty():return _fail(BAD_EXTRA)
		if relay.active!=true:return _fail(NOT_ACTIVE)
		if _expired(state,relay):return _fail(ENDING)
		if entry.get("joined",false)!=true:return _fail(NOT_JOINED)
		var kind:=str(entry.carry)
		if kind.is_empty():return _fail(EMPTY_HANDS)
		var target:=_pass_target(state,relay,token,person,online)
		if target.is_empty():return _fail(NO_TARGET)
		var receiver:Dictionary=relay.participants[target]
		receiver.carry=kind
		receiver.relay=true
		entry.carry=""
		entry.relay=false
		entry.passed=mini(MAX_PASSED,int(entry.passed)+1)
		message="把%s傳給%s。"%[kind_name(kind),_name_of(state,target)]
	elif action=="harvest_sort":
		if not extra.is_empty():return _fail(BAD_EXTRA)
		var basket:=basket_at(p)
		if basket.is_empty():return _fail(WRONG_BASKET_CELL)
		if _distance(person,p)>HAND_REACH:return _fail(TOO_FAR_BASKET)
		if relay.active!=true:return _fail(NOT_ACTIVE)
		if _expired(state,relay):return _fail(ENDING)
		if entry.get("joined",false)!=true:return _fail(NOT_JOINED)
		var kind:=str(entry.carry)
		if kind.is_empty():return _fail(EMPTY_HANDS)
		var right:=basket_of(kind)
		if right!=basket:return _fail(WRONG_BASKET%[kind_name(kind),BASKET_NAMES[right],BASKET_NAMES[right]])
		var relayed:bool=entry.relay==true
		entry.carry=""
		entry.relay=false
		entry.sorted=int(entry.sorted)+1
		relay.delivered=int(relay.delivered)+1
		if relayed:relay.relays=int(relay.relays)+1
		var bonus:="（接力加分 +1）" if relayed else ""
		if int(relay.delivered)>=GOAL:
			state.harvest_relay=relay
			_finish(state,relay,"goal")
			return {"ok":true,"message":"%s放進「%s」籃%s！%d 個全部分類完成，參加者各得 %d 張紀念票。"%[kind_name(kind),BASKET_NAMES[basket],bonus,GOAL,tickets_for(GOAL)]}
		message="%s放進「%s」籃%s！大家完成了 %d / %d。"%[kind_name(kind),BASKET_NAMES[basket],bonus,int(relay.delivered),GOAL]
	else:
		return _fail(BAD_EXTRA)
	state.harvest_relay=relay
	return {"ok":true,"message":message}

## PASS_REACH 內、已加入、空手、在線且在家園的其他參加者中最近的一位；同距離依 token。
static func _pass_target(state:Dictionary,relay:Dictionary,token:String,person:Dictionary,online:Dictionary) -> String:
	var here:=Vector2(float(person.get("x",0.0)),float(person.get("y",0.0)))
	var best:=""
	var best_distance:=INF
	var tokens:Array=relay.participants.keys()
	tokens.sort()
	for other:String in tokens:
		if other==token or not online.has(other):continue
		var e:Dictionary=relay.participants[other]
		if e.joined!=true or not str(e.carry).is_empty():continue
		var who:Variant=state.get("players",{}).get(other)
		if not who is Dictionary or str(who.get("region",HOME))!=HOME:continue
		var d:=here.distance_to(Vector2(float(who.get("x",0.0)),float(who.get("y",0.0))))
		if d<=PASS_REACH and d<best_distance:
			best=other
			best_distance=d
	return best

## 結算目前這一輪：每位參加者（含離開、離線者）各發一次紀念票。只改 state。
static func _finish(state:Dictionary,relay:Dictionary,reason:String) -> void:
	var round_id:=int(relay.round)
	var delivered:=int(relay.delivered)
	var tickets:=tickets_for(delivered)
	var players:Variant=state.get("players",{})
	for token in relay.participants:
		var entry:Dictionary=relay.participants[token]
		entry.joined=false
		entry.carry=""
		entry.relay=false
		var person:Variant=players.get(token) if players is Dictionary else null
		if not person is Dictionary:continue
		var own:Dictionary=record(person).duplicate(true)
		if int(own.paid_round)>=round_id:continue
		own.tickets=mini(MAX_TICKETS,int(own.tickets)+tickets)
		own.rounds=mini(MAX_ROUNDS,int(own.rounds)+1)
		own.best=maxi(int(own.best),delivered)
		own.paid_round=round_id
		person.harvest_relay=own
	var now:=float(state.get("time",0.0))
	relay.active=false
	relay.last={"round":round_id,"delivered":delivered,"relays":int(relay.relays),"players":relay.participants.size(),
		"tickets":tickets,"reason":reason,"finished":now}
	relay.ready=now+COOLDOWN

## 讓一位參加者放下手上的模型菜並退出（斷線、出遠門）；貢獻保留。
static func _drop_entry(relay:Dictionary,token:String) -> bool:
	var entry:Variant=relay.participants.get(token)
	if not entry is Dictionary or (entry.joined!=true and str(entry.carry).is_empty() and entry.relay!=true):return false
	entry.joined=false
	entry.carry=""
	entry.relay=false
	return true

## Session 在玩家離線時呼叫（經 World.harvest_disconnect）。有變更時回傳 true。
static func drop(state:Dictionary,token:String) -> bool:
	var relay:Variant=state.get("harvest_relay")
	if not relay is Dictionary or not relay.get("participants") is Dictionary:return false
	return _drop_entry(relay,token)

## World.step 每個 tick 呼叫：不在線或不在家園的參加者退出並放下模型菜；
## 時間到時結算（含離線者）。只改 state，有變更時回傳 true。
static func step(state:Dictionary,online:Dictionary) -> bool:
	var relay:Variant=state.get("harvest_relay")
	if not relay is Dictionary or not relay.get("participants") is Dictionary:return false
	var changed:=false
	var players:Variant=state.get("players",{})
	for token in relay.participants:
		var person:Variant=players.get(token) if players is Dictionary else null
		var away:bool=not online.has(token) or not person is Dictionary or str(person.get("region",HOME))!=HOME
		if away and _drop_entry(relay,token):changed=true
	if _expired(state,relay):
		_finish(state,relay,"time")
		changed=true
	return changed

# ------------------------------------------------------------------ schema --

## 存檔檢查：state.harvest_relay 與每位 player.harvest_relay 都可省略；存在時檢查
## 型別、上限、已知模型菜、carry 只在 joined 時、數量一致、時間不在未來。通過時
## 把 JSON 讀回的浮點整數正規化為 int。s.picnic 必須已由 validate_region 補好。
static func valid(s:Dictionary) -> bool:
	var players:Variant=s.get("players")
	if not players is Dictionary:return false
	var now:=float(s.get("time",0.0))
	var has_round:=s.has("harvest_relay")
	var relay:Dictionary={}
	if has_round:
		if s.get("picnic")!=true:return false
		if not _valid_round(s.harvest_relay,players,now):return false
		relay=s.harvest_relay
	var limit:=0
	if has_round:limit=int(relay.round)-(1 if relay.active else 0)
	for token in players:
		var person:Variant=players[token]
		if not person is Dictionary or not person.has("harvest_relay"):continue
		if not has_round:return false
		if not _valid_record(person.harvest_relay,limit):return false
	if has_round and int(relay.round)>=1 and not relay.active:
		for token in relay.participants:
			var person:Dictionary=players[token]
			if not person.has("harvest_relay") or int(person.harvest_relay.paid_round)!=int(relay.round):return false
	return true

static func _valid_round(relay:Variant,players:Dictionary,now:float) -> bool:
	if not relay is Dictionary or relay.size()!=KEYS.size():return false
	for field in KEYS:
		if not relay.has(field):return false
	if not _whole(relay.round,0,MAX_ROUND) or not relay.active is bool:return false
	for field in ["started","ends","ready"]:
		if not _number(relay[field],0.0,1.0e12):return false
	if not _whole(relay.delivered,0,GOAL) or not _whole(relay.relays,0,GOAL) or not _whole(relay.index,0,MAX_INDEX):return false
	var round_id:=int(relay.round)
	var delivered:=int(relay.delivered)
	if int(relay.relays)>delivered:return false
	if relay.active and (round_id<1 or delivered>=GOAL):return false
	if round_id==0 and (delivered!=0 or int(relay.index)!=0 or float(relay.started)!=0.0 or float(relay.ends)!=0.0 or float(relay.ready)!=0.0):return false
	if round_id>=1:
		if float(relay.started)>now+EPSILON or absf(float(relay.ends)-float(relay.started)-DURATION)>EPSILON:return false
	var participants:Variant=relay.participants
	if not participants is Dictionary or participants.size()>MAX_ENTRIES:return false
	if round_id==0 and not participants.is_empty():return false
	if round_id>=1 and participants.is_empty():return false
	var sorted_total:=0
	var carried:=0
	var joined:=0
	var relayed_carries:=0
	for token in participants:
		if not token is String or not players.has(token):return false
		var e:Variant=participants[token]
		if not e is Dictionary or e.size()!=ENTRY_KEYS.size():return false
		for field in ENTRY_KEYS:
			if not e.has(field):return false
		if not e.carry is String or not e.joined is bool or not e.relay is bool:return false
		if not _whole(e.sorted,0,GOAL) or not _whole(e.passed,0,MAX_PASSED):return false
		if e.joined and not relay.active:return false
		if not e.carry.is_empty():
			if not KINDS.has(e.carry) or not e.joined:return false
			carried+=1
			if e.relay:relayed_carries+=1
		elif e.relay:return false
		if e.joined:joined+=1
		sorted_total+=int(e.sorted)
	if joined>MAX_PLAYERS or sorted_total!=delivered:return false
	if delivered+carried>int(relay.index):return false
	var last:Variant=relay.last
	if not last is Dictionary:return false
	var finished_round:=round_id if not relay.active else round_id-1
	if finished_round<=0:
		if not last.is_empty():return false
	else:
		if last.size()!=LAST_KEYS.size():return false
		for field in LAST_KEYS:
			if not last.has(field):return false
		if not _whole(last.round,1,MAX_ROUND) or int(last.round)!=finished_round:return false
		if not _whole(last.delivered,0,GOAL) or not _whole(last.relays,0,GOAL) or int(last.relays)>int(last.delivered):return false
		if not _whole(last.players,1,MAX_ENTRIES) or not _whole(last.tickets,1,1+MAX_BONUS):return false
		if int(last.tickets)!=tickets_for(int(last.delivered)):return false
		if not last.reason is String or last.reason not in ["goal","time"]:return false
		if last.reason=="goal" and int(last.delivered)!=GOAL:return false
		if not _number(last.finished,0.0,now+EPSILON):return false
		if absf(float(relay.ready)-float(last.finished)-COOLDOWN)>EPSILON:return false
		if not relay.active:
			# The finished round is the current one: its numbers and roster must agree.
			if int(last.delivered)!=delivered or int(last.relays)!=int(relay.relays) or int(last.players)!=participants.size():return false
			if float(last.finished)+EPSILON<float(relay.started):return false
			if last.reason=="time" and float(last.finished)+EPSILON<float(relay.ends):return false
		elif float(relay.started)+EPSILON<float(last.finished)+COOLDOWN:
			return false
	for field in ["round","delivered","relays","index"]:relay[field]=int(relay[field])
	for field in ["started","ends","ready"]:relay[field]=float(relay[field])
	for token in participants:
		var e:Dictionary=participants[token]
		e.sorted=int(e.sorted)
		e.passed=int(e.passed)
	if not last.is_empty():
		for field in ["round","delivered","relays","players","tickets"]:last[field]=int(last[field])
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
