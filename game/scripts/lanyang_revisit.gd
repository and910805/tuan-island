extends RefCounted
## 規劃書第 40 章首段「蘭陽回訪・旱日分流」：宜蘭水圳修好、橋邊配水紀念牌設好之後，
## 星禾邀大家在放晴的日子回來，用岔口「真的」分流閘把水分給三塊田。三塊田在同一天
## 都確認過就永久完成；完成後每位（自己也完成過第一次分水練習的）島民可在星禾那裡
## 領一塊「分水木牌」(water_share_plaque_kit) 帶回家，家園工坊也解鎖「分流閘」
## (diversion_gate_kit，見 industry.gd 的 GATE_* 與 World.CRAFT)。
##
## 回訪情節與配水數字為原創（DISCLAIMER），非史料；史料只在 history_story.gd 既有的引用。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；只看 state.time（WEATHER 曆法）。失敗時 state
## 完全不變（先檢查完全部條件，最後才寫入）。不 preload World（避免循環）。
##
## ── 前提（世界）：state.lanyang_life.repaired==true 且 state.history_memory.plaque==true
## ── 前提（本人）：state.history_memory.players[token].completed==true（後來加入的島民
##    要先完成自己的第一次分水，才能幫忙或領木牌 → NOT_READY）
##
## ── 世界紀錄 state.lanyang_revisit（可省略；第一次成功調閘才寫入，舊存檔不需遷移，不升版）
##   {"gates":[a,b],          # 0..3，岔口真的分流閘（a＝上游閘、b＝中段閘）
##    "day":int,              # 閘門最後一次被設定的世界日（一起算，= WEATHER.at(time).day）
##    "checked":[field_id..], # 「day 那天」已確認的田（FIELDS 的子集，不重複，依確認順序）
##    "completed":bool,       # 三塊田同一天都確認過 → 永久 true
##    "claimed":{token:true}} # 已領分水木牌的島民（只在伺服器；公開快照不含）
##   不記錄是誰調閘、誰確認（沒有 token）。換日之後 checked 視為空（lazy；存檔裡保留舊值，
##   下一次調閘時清掉）。
##   分配：HistoryMemory.distribution(gates) = [2a, min(12−2a, 2b), 剩下]（上游／中段／田尾）。
##
## ── 今日需求（依季節；WEATHER.season_on_day）DEMANDS / REASONS
##   spring [6,4,2]  summer [4,2,6]  autumn [2,6,4]  winter [2,4,6]
##   對應閘門：春 a3 b2、夏 a2 b1、秋 a1 b3、冬 a1 b2。
##
## ── 地點（蘭陽試作田座標）
##   GATE_CELL (33,25) 岔口；FIELDS：upstream 上游 (33,22)、middle 中段＝星禾 SERVICE (33,29)、
##   tail 田尾 (33,32)；領木牌在 SERVICE (33,29)。REACH=3.2（與一般互動相同）。
##
## ── 動作（World._apply 在 TABLE_WARMER 之後、一般距離檢查之前轉給 apply()）
##   revisit_gate   p＝GATE_CELL，extra＝"a:0".."a:3" | "b:0".."b:3"
##                  設定共用閘門、記下今天、清掉 checked。同一天把閘門設成原本那一檔 → SAME_GATE。
##   revisit_check  p＝三塊田之一的格子，extra＝""。需要：今天放晴、閘門是今天設的、
##                  distribution(gates)==今日需求、這塊田今天還沒確認。任何人可確認任何田。
##                  三塊都確認 → completed=true。
##   revisit_claim  p＝SERVICE，extra＝""。completed 之後每人一次，背包 +1 water_share_plaque_kit。
##   檢查順序：BAD_EXTRA（不是本模組的動作）→ NO_PLAYER → WRONG_REGION → LOCKED → NOT_READY →
##     WRONG_GATE_CELL / WRONG_FIELD_CELL / WRONG_SERVICE_CELL → TOO_FAR →
##     gate ：ALREADY_DONE → BAD_GATE（extra 格式）→ RAINY → SAME_GATE
##     check：BAD_EXTRA（extra 非空）→ ALREADY_DONE → RAINY → NO_GATES_TODAY → ALREADY_CHECKED →
##            WRONG_SHARE%[田名,分到,需要] → OTHER_WRONG%[田名,份]
##     claim：BAD_EXTRA（extra 非空）→ NOT_DONE → CLAIMED → BAG_FULL
##
## ── 分水木牌（家園裝飾，與 T071 紀念品裝飾相同的規則）
##   背包物品 PLAQUE_ITEM="water_share_plaque_kit"，建造種類 PLAQUE_KIND="water_share_plaque"
##   (World.BUILD 名稱「分水木牌」)：不擋路、拆除退回 kit、可搬移、可放箱子；沒有價目
##   （不能出貨、不能在攤位賣、不能上市集），World.trade_items() 排除（不能交易）。
##   PLAQUE_SOURCE / PLAQUE_PROJECT / PLAQUE_BLURB 給介面顯示來源。
##
## ── 介面用的純函式（snapshot 可以是伺服器 state 或用戶端快照；token 只在伺服器 state 有用，
##    用戶端快照用 history_memory.own_memory 與 lanyang_revisit.claimed_own）
##   unlocked(snapshot) -> bool                    # 水圳修好且配水紀念牌已設
##   player_ready(snapshot,token="") -> bool       # 本人第一次分水已完成
##   record(snapshot) -> Dictionary                # 唯讀；沒有時 fresh()
##   completed(snapshot) -> bool / tech_unlocked(snapshot) -> bool（分流閘配方解鎖，= completed）
##   today(snapshot) -> int                        # 一起算的世界日
##   season(snapshot) -> String / raining(snapshot) -> bool（蘭陽今天下雨）
##   demand(snapshot) -> Array[int] / demand_for(season) -> Array[int]
##   reason(snapshot) -> String / reason_for(season) -> String
##   gates(snapshot) -> Array[int] / shares(snapshot) -> Array[int]（目前三塊田分到的份數）
##   gates_today(snapshot) -> bool                 # 閘門是今天設的
##   checked_today(snapshot) -> Array[String]      # 今天有效的已確認田
##   fields(snapshot) -> Array[{"id","name","cell","current","needed","checked","ok"}]
##   field_at(cell) -> String                      # 該格是哪塊田；不是時 ""
##   gate_extra(which:"a"|"b",level) -> String     # "a:2"
##   gate_block(snapshot,token="") -> String       # 不能調閘的原因（不看位置、不看哪一檔）；可以時 ""
##   check_block(snapshot,field_id,token="") -> String
##   claim_block(snapshot,inventory,token="") -> String / can_claim(snapshot,inventory,token="") -> bool
##   claimed_own(snapshot,token="") -> bool
##   public(state) -> Dictionary                   # 快照用：{"gates","day","checked","completed"}；沒紀錄時 {}
##   apply(state,token,action,p,extra,in_lanyang) -> {"ok","message"}
##   valid(s) -> bool                              # 存檔檢查（state.lanyang_revisit）
##   artifacts_valid(s) -> bool                    # 分流閘／分水木牌物件只能出現在完成之後
## Session：snapshot.lanyang_revisit = public(state)（沒紀錄時沒有這個鍵），
##   並只對收件人加上 lanyang_revisit.claimed_own（bool）。

const HISTORY_MEMORY=preload("res://scripts/history_memory.gd")
const WEATHER=preload("res://scripts/weather.gd")

const STATE_KEY:="lanyang_revisit"
const REGION:="lanyang"
const GATE_ACTION:="revisit_gate"
const CHECK_ACTION:="revisit_check"
const CLAIM_ACTION:="revisit_claim"
const ACTIONS:=[GATE_ACTION,CHECK_ACTION,CLAIM_ACTION]
const RECORD_KEYS:=["checked","claimed","completed","day","gates"]
const REACH:=3.2
const GATE_CELL:=Vector2i(33,25)
const SERVICE:=Vector2i(33,29)
const FIELDS:=["upstream","middle","tail"]
const FIELD_CELLS:={"upstream":Vector2i(33,22),"middle":Vector2i(33,29),"tail":Vector2i(33,32)}
const FIELD_NAMES:={"upstream":"上游的田","middle":"中段的田","tail":"田尾的田"}
const GATE_NAMES:={"a":"上游閘","b":"中段閘"}
const MAX_LEVEL:=3
const MAX_ITEM:=1000000000
const DEMANDS:={"spring":[6,4,2],"summer":[4,2,6],"autumn":[2,6,4],"winter":[2,4,6]}
const REASONS:={
	"spring":"春耕插秧，上游的秧田最需要水；田尾還在整地，少一點就好。",
	"summer":"夏天日頭大，田尾的稻田最容易曬乾，要多分一些過去。",
	"autumn":"秋天中段的稻子正在抽穗，星禾說這時候最不能缺水。",
	"winter":"冬天田尾種了冬季菜，畦溝要保持濕潤；上游的田休耕。",
}
const DISCLAIMER:="回訪情節與配水數字為原創，非史料。"
const TITLE:="蘭陽回訪・旱日分流"

const PLAQUE_KIND:="water_share_plaque"
const PLAQUE_ITEM:="water_share_plaque_kit"
const PLAQUE_NAME:="分水木牌"
const PLAQUE_SOURCE:="來源：宜蘭・蘭陽水圳回訪"
const PLAQUE_PROJECT:="對應工程：蘭陽水圳修復"
const PLAQUE_BLURB:="刻著三道水口的小木牌，紀念大家在旱日一起把水分給三塊田。"

const NO_PLAYER:="請重新加入世界再操作分流閘。"
const WRONG_REGION:="蘭陽回訪在宜蘭水圳，請先到蘭陽試作田。"
const LOCKED:="修好蘭陽水圳、在橋邊設置配水紀念牌之後，星禾才會邀大家回來調整分流。"
const NOT_READY:="先完成你自己的第一次分水練習（三處觀察、三輪配水），再來幫忙旱日分流。"
const RETURN_TOMORROW:="今天先讓水慢慢流進田裡。明天起，挑個放晴的日子再來找星禾。"
const WRONG_GATE_CELL:="請走到水圳岔口的分流閘旁。"
const WRONG_FIELD_CELL:="請走到要確認的那塊田旁。"
const WRONG_SERVICE_CELL:="請到橋邊找星禾。"
const TOO_FAR:="再靠近一點。"
const BAD_EXTRA:="請重新操作分流閘。"
const BAD_GATE:="閘門只能調整為零到三檔。"
const ALREADY_DONE:="旱日分流已經完成了，三塊田的水都配好了。"
const RAINY:="今天有雨，田裡不缺水。等放晴的日子再來調整分流。"
const SAME_GATE:="閘門已經在這一檔了。"
const NO_GATES_TODAY:="今天還沒有人調整岔口的分流閘，先到岔口設定閘門。"
const ALREADY_CHECKED:="這塊田今天已經確認過了。"
const WRONG_SHARE:="%s現在分到 %d 份水，今天需要 %d 份。回岔口再調整閘門。"
const OTHER_WRONG:="%s的 %d 份剛好，但另外兩塊田的水量還不對，回岔口再調整閘門。"
const GATE_OK:="已把%s調到 %d 檔。三塊田現在分到 %d／%d／%d 份。"
const CHECK_OK:="%s分到 %d 份水，剛好夠用。（今天已確認 %d／3 塊田）"
const COMPLETE_OK:="三塊田的水都配好了！星禾說，大家可以到橋邊領一塊分水木牌帶回家；家園工坊也能做分流閘了。"
const NOT_DONE:="三塊田的旱日分流還沒完成，完成後才能領分水木牌。"
const CLAIMED:="你已經領過分水木牌了。"
const BAG_FULL:="背包裡的分水木牌已經放不下了。"
const CLAIM_OK:="星禾把一塊分水木牌交給你。在家園工坊的「生活」頁選它就能擺到家園；拆除會收回背包。"

# ------------------------------------------------------------------ views --

static func fresh() -> Dictionary:
	return {"gates":[0,0],"day":0,"checked":[],"completed":false,"claimed":{}}

static func unlocked(snapshot:Dictionary) -> bool:
	var life:Variant=snapshot.get("lanyang_life")
	var memory:Variant=snapshot.get("history_memory")
	return life is Dictionary and life.get("repaired")==true and memory is Dictionary and memory.get("plaque")==true

static func _own_memory(snapshot:Dictionary,token:String) -> Dictionary:
	var memory:Variant=snapshot.get("history_memory")
	if not memory is Dictionary:return {}
	if not token.is_empty():
		var people:Variant=memory.get("players")
		if people is Dictionary and people.get(token) is Dictionary:return people[token]
	var own:Variant=memory.get("own_memory")
	return own if own is Dictionary else {}

static func player_ready(snapshot:Dictionary,token:String="") -> bool:
	return _own_memory(snapshot,token).get("completed")==true

static func record(snapshot:Dictionary) -> Dictionary:
	var found:Variant=snapshot.get(STATE_KEY)
	return found if found is Dictionary else fresh()

static func completed(snapshot:Dictionary) -> bool:
	return record(snapshot).get("completed")==true

static func waiting_for_return(snapshot:Dictionary,token:String="") -> bool:
	var first_visit:=_own_memory(snapshot,token)
	return not completed(snapshot) and first_visit.get("completed")==true \
		and int(first_visit.get("completed_day",-1))>=today(snapshot)-1

static func tech_unlocked(snapshot:Dictionary) -> bool:
	return completed(snapshot)

static func _day_index(snapshot:Dictionary) -> float:
	return WEATHER.day_index(snapshot.get("time",0.0))

static func today(snapshot:Dictionary) -> int:
	return int(_day_index(snapshot))+1

static func season(snapshot:Dictionary) -> String:
	return WEATHER.season_on_day(_day_index(snapshot))

static func raining(snapshot:Dictionary) -> bool:
	return WEATHER.rains(_day_index(snapshot),REGION)

static func demand_for(season_id:String) -> Array:
	return (DEMANDS.get(season_id,[4,4,4]) as Array).duplicate()

static func reason_for(season_id:String) -> String:
	return str(REASONS.get(season_id,""))

static func demand(snapshot:Dictionary) -> Array:
	return demand_for(season(snapshot))

static func reason(snapshot:Dictionary) -> String:
	return reason_for(season(snapshot))

static func gates(snapshot:Dictionary) -> Array:
	var raw:Variant=record(snapshot).get("gates")
	if not raw is Array or raw.size()!=2:return [0,0]
	return [clampi(int(raw[0]),0,MAX_LEVEL),clampi(int(raw[1]),0,MAX_LEVEL)]

static func shares(snapshot:Dictionary) -> Array:
	return HISTORY_MEMORY.distribution(gates(snapshot))

static func gates_today(snapshot:Dictionary) -> bool:
	return snapshot.get(STATE_KEY) is Dictionary and int(record(snapshot).get("day",0))==today(snapshot)

static func checked_today(snapshot:Dictionary) -> Array:
	var out:=[]
	if not gates_today(snapshot) and not completed(snapshot):return out
	var raw:Variant=record(snapshot).get("checked")
	if raw is Array:
		for id in raw:
			if str(id) in FIELDS and str(id) not in out:out.append(str(id))
	return out

static func field_at(cell:Vector2i) -> String:
	for id:String in FIELDS:
		if FIELD_CELLS[id]==cell:return id
	return ""

static func fields(snapshot:Dictionary) -> Array:
	var now:=shares(snapshot)
	var need:=demand(snapshot)
	var done:=checked_today(snapshot)
	var rows:=[]
	for i in FIELDS.size():
		var id:String=FIELDS[i]
		rows.append({"id":id,"name":str(FIELD_NAMES[id]),"cell":FIELD_CELLS[id],"current":int(now[i]),"needed":int(need[i]),
			"checked":id in done,"ok":int(now[i])==int(need[i])})
	return rows

static func gate_extra(which:String,level:int) -> String:
	return "%s:%d"%[which,level]

static func _common_block(snapshot:Dictionary,token:String) -> String:
	if not unlocked(snapshot):return LOCKED
	if not player_ready(snapshot,token):return NOT_READY
	if waiting_for_return(snapshot,token):return RETURN_TOMORROW
	return ""

static func gate_block(snapshot:Dictionary,token:String="") -> String:
	var common:=_common_block(snapshot,token)
	if not common.is_empty():return common
	if completed(snapshot):return ALREADY_DONE
	if raining(snapshot):return RAINY
	return ""

static func check_block(snapshot:Dictionary,field_id:String,token:String="") -> String:
	var common:=_common_block(snapshot,token)
	if not common.is_empty():return common
	return _check_problem(snapshot,field_id)

## check_block without the world/player prerequisites (apply() checked those).
static func _check_problem(snapshot:Dictionary,field_id:String) -> String:
	if completed(snapshot):return ALREADY_DONE
	if raining(snapshot):return RAINY
	if not gates_today(snapshot):return NO_GATES_TODAY
	var index:=FIELDS.find(field_id)
	if index<0:return WRONG_FIELD_CELL
	if field_id in checked_today(snapshot):return ALREADY_CHECKED
	var now:=shares(snapshot)
	var need:=demand(snapshot)
	if int(now[index])!=int(need[index]):return WRONG_SHARE%[str(FIELD_NAMES[field_id]),int(now[index]),int(need[index])]
	if now!=need:return OTHER_WRONG%[str(FIELD_NAMES[field_id]),int(now[index])]
	return ""

static func claimed_own(snapshot:Dictionary,token:String="") -> bool:
	var found:Variant=snapshot.get(STATE_KEY)
	if not found is Dictionary:return false
	if not token.is_empty():
		var claimed:Variant=found.get("claimed")
		if claimed is Dictionary:return claimed.has(token)
	return found.get("claimed_own")==true

static func claim_block(snapshot:Dictionary,inventory:Variant,token:String="") -> String:
	var common:=_common_block(snapshot,token)
	if not common.is_empty():return common
	if not completed(snapshot):return NOT_DONE
	if claimed_own(snapshot,token):return CLAIMED
	if inventory is Dictionary and int(inventory.get(PLAQUE_ITEM,0))>=MAX_ITEM:return BAG_FULL
	return ""

static func can_claim(snapshot:Dictionary,inventory:Variant,token:String="") -> bool:
	return claim_block(snapshot,inventory,token).is_empty()

static func public(state:Dictionary) -> Dictionary:
	var found:Variant=state.get(STATE_KEY)
	if not found is Dictionary:return {}
	return {"gates":gates(state),"day":int(found.get("day",0)),"checked":(found.get("checked",[]) as Array).duplicate() if found.get("checked") is Array else [],
		"completed":found.get("completed")==true}

# ------------------------------------------------------------------ action --

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

static func _distance(person:Dictionary,cell:Vector2i) -> float:
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## World passes in_lanyang (actor's region is Lanyang). Every check runs before
## any write, so a failure leaves the whole state unchanged.
static func apply(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,in_lanyang:bool) -> Dictionary:
	if action not in ACTIONS:return _fail(BAD_EXTRA)
	var people:Variant=state.get("players",{})
	if not people is Dictionary or not people.get(token) is Dictionary:return _fail(NO_PLAYER)
	var person:Dictionary=people[token]
	if not in_lanyang:return _fail(WRONG_REGION)
	var blocked:=_common_block(state,token)
	if not blocked.is_empty():return _fail(blocked)
	if state.has(STATE_KEY) and not _shape_ok(state[STATE_KEY]):return _fail(BAD_EXTRA)
	var target:Vector2i
	if action==GATE_ACTION:
		if p!=GATE_CELL:return _fail(WRONG_GATE_CELL)
		target=GATE_CELL
	elif action==CHECK_ACTION:
		if field_at(p).is_empty():return _fail(WRONG_FIELD_CELL)
		target=p
	else:
		if p!=SERVICE:return _fail(WRONG_SERVICE_CELL)
		target=SERVICE
	if _distance(person,target)>REACH:return _fail(TOO_FAR)
	if action==GATE_ACTION:return _gate(state,extra)
	if not extra.is_empty():return _fail(BAD_EXTRA)
	if action==CHECK_ACTION:return _check(state,field_at(p))
	return _claim(state,token,person)

static func _gate(state:Dictionary,extra:String) -> Dictionary:
	if completed(state):return _fail(ALREADY_DONE)
	var parts:=extra.split(":")
	if parts.size()!=2 or parts[0] not in ["a","b"] or parts[1] not in ["0","1","2","3"]:return _fail(BAD_GATE)
	if raining(state):return _fail(RAINY)
	var index:=0 if parts[0]=="a" else 1
	var level:=int(parts[1])
	var now:=gates(state)
	if gates_today(state) and int(now[index])==level:return _fail(SAME_GATE)
	now[index]=level
	var own:Dictionary=record(state).duplicate(true)
	own.gates=now
	own.day=today(state)
	own.checked=[]
	state[STATE_KEY]=own
	var split:=HISTORY_MEMORY.distribution(now)
	return {"ok":true,"message":GATE_OK%[str(GATE_NAMES[parts[0]]),level,int(split[0]),int(split[1]),int(split[2])]}

static func _check(state:Dictionary,field_id:String) -> Dictionary:
	var block:=_check_problem(state,field_id)
	if not block.is_empty():return _fail(block)
	var own:Dictionary=state[STATE_KEY]
	var done:=checked_today(state)
	done.append(field_id)
	own.checked=done
	var index:=FIELDS.find(field_id)
	var got:=int(shares(state)[index])
	if done.size()==FIELDS.size():
		own.completed=true
		return {"ok":true,"message":COMPLETE_OK}
	return {"ok":true,"message":CHECK_OK%[str(FIELD_NAMES[field_id]),got,done.size()]}

static func _claim(state:Dictionary,token:String,person:Dictionary) -> Dictionary:
	if not completed(state):return _fail(NOT_DONE)
	if claimed_own(state,token):return _fail(CLAIMED)
	if not person.get("inventory") is Dictionary:return _fail(NO_PLAYER)
	var inv:Dictionary=person.inventory
	if int(inv.get(PLAQUE_ITEM,0))>=MAX_ITEM:return _fail(BAG_FULL)
	var own:Dictionary=state[STATE_KEY]
	own.claimed[token]=true
	inv[PLAQUE_ITEM]=int(inv.get(PLAQUE_ITEM,0))+1
	return {"ok":true,"message":CLAIM_OK}

## Runtime shape check (full consistency is valid()'s job at load time).
static func _shape_ok(own:Variant) -> bool:
	if not own is Dictionary or own.size()!=RECORD_KEYS.size():return false
	for field:String in RECORD_KEYS:
		if not own.has(field):return false
	return own.gates is Array and own.gates.size()==2 and own.checked is Array and own.claimed is Dictionary and own.completed is bool

# ------------------------------------------------------------------ schema --

static func _whole(value:Variant,minimum:float,maximum:float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum and floorf(float(value))==float(value)

## state.lanyang_revisit (optional). Exact keys; gates 0..3; day 1..today; checked a
## duplicate-free subset of FIELDS; completed <=> all three checked; any check or a
## completion implies that day was dry in Lanyang and the gates matched that day's
## seasonal demand; the record needs the repaired canal + plaque; claimed only after
## completion, values true, keys known players whose own first memory is completed.
## Normalises JSON floats (gates/day) to int on success.
static func valid(s:Dictionary) -> bool:
	if not s.has(STATE_KEY):return true
	var own:Variant=s[STATE_KEY]
	if not _shape_ok(own):return false
	if not unlocked(s):return false
	if not _whole(own.gates[0],0,MAX_LEVEL) or not _whole(own.gates[1],0,MAX_LEVEL):return false
	var now_day:=int(WEATHER.day_index(s.get("time",0.0)))+1
	if not _whole(own.day,1,now_day):return false
	var seen:={}
	for id in own.checked:
		if not id is String or id not in FIELDS or seen.has(id):return false
		seen[id]=true
	if own.completed!=(seen.size()==FIELDS.size()):return false
	var day_index:=float(int(own.day)-1)
	if not seen.is_empty():
		if WEATHER.rains(day_index,REGION):return false
		var split:=HISTORY_MEMORY.distribution([int(own.gates[0]),int(own.gates[1])])
		if split!=demand_for(WEATHER.season_on_day(day_index)):return false
	var players:Variant=s.get("players")
	var memory:Dictionary=s.history_memory
	for token in own.claimed:
		if not own.completed or not token is String or own.claimed[token]!=true:return false
		if not players is Dictionary or not players.has(token):return false
		var mine:Variant=memory.players.get(token)
		if not mine is Dictionary or mine.get("completed")!=true:return false
	own.gates=[int(own.gates[0]),int(own.gates[1])]
	own.day=int(own.day)
	return true

## Diversion gates and placed water-share plaques exist only after the revisit
## (both unlock with completion). Checks home and every regional object layer.
## `items` (chapter 40 water tower: [Industry.TOWER_KIT]) must also be absent from every
## player's inventory and every object's `items` (chests) until completion.
static func artifacts_valid(s:Dictionary,kinds:Array,items:Array=[]) -> bool:
	if completed(s):return true
	var layers:=[s.get("objects",{})]
	var regions:Variant=s.get("regions",{})
	if regions is Dictionary:
		for region in regions:
			var local:Variant=regions[region]
			if local is Dictionary:layers.append(local.get("objects",{}))
	for layer:Variant in layers:
		if not layer is Dictionary:continue
		for obj:Variant in layer.values():
			if obj is Dictionary and str(obj.get("type","")) in kinds:return false
			if obj is Dictionary and obj.get("items") is Dictionary:
				for item:String in items:
					if _holds(obj.items,item):return false
	if items.is_empty():return true
	var players:Variant=s.get("players",{})
	if players is Dictionary:
		for token in players:
			var person:Variant=players[token]
			if not person is Dictionary or not person.get("inventory") is Dictionary:continue
			for item:String in items:
				if _holds(person.inventory,item):return false
	return true

## A present entry counts unless it is a numeric zero.
static func _holds(bag:Dictionary,item:String) -> bool:
	if not bag.has(item):return false
	var amount:Variant=bag[item]
	return not ((amount is int or amount is float) and amount==0)
