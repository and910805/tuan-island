extends RefCounted
## 規劃書第 40 章「金瓜石回訪・礦料調度」：合作礦場的升降台修好（T067 Q07）之後，波波邀大家
## 回金瓜石，把升降台送上來的礦料分揀到三個貨箱，再分頭送到對應的地方：
##   波波的整理桌（在整理桌交給波波）、渡口家園工坊（在山城接駁站寄運）、坑內礦務站（用升降台送下坑）。
## 三箱都送出就全島永久完成；完成後每位（自己也跟波波整理過一次礦樣的）島民可在波波的整理桌
## 領一盞「礦燈」(mine_lantern_kit) 帶回家擺放。礦燈只是裝飾，沒有照明機制。
##
## 回訪情節、訂單與數量為原創（DISCLAIMER），非史料；沒有新增任何金瓜石史實敘述。
## 三個目的地都是遊戲裡既有的地方（波波的整理桌、風鈴渡口的家園工坊、合作礦場的礦務站）。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；只看 state.time（WEATHER 曆法）。失敗時 state
## 完全不變（先檢查完全部條件，最後才寫入）。不 preload World（避免循環）。
##
## ── 前提（世界）：state.mine_depths.hoist==true（升降台已修好，MINES.hoist_ready）。
##    一般玩法：野餐後到金瓜石，合作礦場開到第 6 層，在下坑路牌交付銅接頭 12、木板 4。
## ── 前提（本人）：state.bobo_workshop.done[token]==true（跟波波完成過一次礦樣整理：
##    bobo_sort_start（含金礦料 3）→ bobo_sort_answer 0:large/1:medium/2:small → bobo_sort_claim）。
##    沒做過的人（含後來加入的島民）→ NOT_READY；做完就能幫忙或領礦燈。
##
## ── 世界紀錄 state.jinguashi_revisit（可省略；第一次成功分揀才寫入，舊存檔不需遷移，不升版）
##   {"crates":{"bobo":ore,"ferry":ore,"depot":ore},  # 每個貨箱分揀到的礦料；"" = 還沒分揀
##    "day":int,              # 第一箱送出的世界日（= 這批訂單的日子）；還沒送出時 0
##    "sent":[dest..],        # 已送出的貨箱（DESTS 的子集，不重複，依送出先後）
##    "completed":bool,       # 三箱都送出 → 永久 true
##    "done_day":int,         # 第三箱送出（完成）的世界日；未完成時 0
##    "claimed":{token:true}} # 已領礦燈的島民（只在伺服器；公開快照不含）
##   不記錄是誰分揀、誰送出（沒有 token）。
##   訂單：還沒有貨箱送出時看「今天」的季節；第一箱送出後鎖定為 day 那天的季節（之後換季也不變）。
##
## ── 訂單（依季節；WEATHER.season_on_day）ORDERS / REASONS；數量固定 AMOUNTS
##   含金礦料 2、銅礦 4、石材 6（每箱一種礦料）。
##   spring：波波 含金礦料、渡口 銅礦、礦務站 石材
##   summer：波波 銅礦、渡口 含金礦料、礦務站 石材
##   autumn：波波 含金礦料、渡口 石材、礦務站 銅礦
##   winter：波波 銅礦、渡口 含金礦料、礦務站 石材
##   完成一次共用掉：含金礦料 2、銅礦 4、石材 6（由各自送出那一箱的人從背包付）。
##
## ── 地點（金瓜石山城座標；都是既有設施）
##   分揀＝波波的整理桌 BOBO.sites(state).table（預設 (23,20)，整理桌本身擋路，站在旁邊）；
##   DEST 送出點：bobo＝整理桌、ferry＝山城接駁站 SHUTTLE (11,20)、depot＝下坑路牌 HOIST (28,19)
##   （= MINES.ENTRY，升降台修理處）；領礦燈在整理桌。REACH=3.2（與一般互動相同）。
##
## ── 動作（World._apply 在 LANYANG_REVISIT 之後、一般距離檢查之前轉給 apply()）
##   jg_revisit_sort  p＝整理桌，extra＝"<dest>:<ore>"（sort_extra(dest,ore)，例 "bobo:gold_ore"）
##                    把一個貨箱分揀成某種礦料（不扣材料）。可以重複分揀，直到第一箱送出。
##   jg_revisit_ship  p＝該貨箱的送出點，extra＝""。需要：這箱已分揀、三箱的分揀都符合訂單、
##                    這箱還沒送出、本人背包有訂單數量的礦料 → 扣掉、記入 sent。任何人可送任何一箱
##                    （可分頭進行）。三箱都送出 → completed=true、done_day=今天。
##   jg_revisit_claim p＝整理桌，extra＝""。completed 之後每人一次，背包 +1 mine_lantern_kit。
##   檢查順序：BAD_EXTRA（不是本模組的動作）→ NO_PLAYER → WRONG_REGION → LOCKED → NOT_READY →
##     BAD_EXTRA（紀錄壞掉）→ WRONG_SORT_CELL / WRONG_SHIP_CELL / WRONG_CLAIM_CELL → TOO_FAR →
##     sort ：ALREADY_DONE → BAD_SORT（extra 格式）→ SENT_LOCKED → SAME_SORT%礦料名
##     ship ：BAD_EXTRA（extra 非空）→ ALREADY_DONE → ALREADY_SENT%地點 → UNSORTED%地點 →
##            WRONG_ORE%[地點,分到的礦料,訂單的礦料] → OTHER_WRONG%地點 → SHORT%[礦料,需要,持有]
##     claim：BAD_EXTRA（extra 非空）→ NOT_DONE → CLAIMED → BAG_FULL
##   成功訊息：SORT_OK%[礦料,地點]、SHIP_OK%[地點,礦料,數量,已送出箱數]、COMPLETE_OK、CLAIM_OK。
##
## ── 礦燈（家園裝飾，與分水木牌相同的規則）
##   背包物品 LANTERN_ITEM="mine_lantern_kit"，建造種類 LANTERN_KIND="mine_lantern"
##   (World.BUILD 名稱「礦燈」)：不擋路、拆除退回 kit、可搬移、可放箱子；沒有價目
##   （不能出貨、不能在攤位賣、不能上市集），World.trade_items() 排除（不能交易）。
##   LANTERN_SOURCE / LANTERN_PROJECT / LANTERN_BLURB 給介面顯示來源。
##
## ── 介面用的純函式（snapshot 可以是伺服器 state 或用戶端快照；token 只在伺服器 state 有用，
##    用戶端快照用 bobo_workshop.own_done 與 jinguashi_revisit.claimed_own）
##   unlocked(snapshot) -> bool                    # 升降台已修好
##   player_ready(snapshot,token="") -> bool       # 本人跟波波整理過一次礦樣
##   record(snapshot) -> Dictionary                # 唯讀；沒有時 fresh()
##   completed(snapshot) -> bool
##   today(snapshot) -> int                        # 一起算的世界日
##   order_season(snapshot) -> String              # 這批訂單的季節（已送出時鎖定為 day 那天）
##   order(snapshot) -> {dest:ore} / order_for(season) -> {dest:ore}
##   reason(snapshot) -> String / reason_for(season) -> String
##   amount_for(ore) -> int
##   crates(snapshot) -> {dest:ore}（"" = 還沒分揀）/ sent(snapshot) -> Array[String]
##   dest_cell(snapshot,dest) -> Vector2i / dest_at(snapshot,cell) -> String（不是送出點時 ""）
##   sort_cell(snapshot) / claim_cell(snapshot) -> Vector2i（= 整理桌）
##   rows(snapshot,inventory=null) -> Array[{"id","name","how","cell","ore","ore_name","needed",
##       "needed_name","amount","have","sent","ok"}]（固定 DESTS 順序；have 只在給 inventory 時算，否則 -1）
##   sort_extra(dest,ore) -> String                # "bobo:gold_ore"
##   sort_block(snapshot,token="") -> String       # 不能分揀的原因（不看位置、不看選哪箱）；可以時 ""
##   ship_block(snapshot,dest,inventory,token="") -> String   # 不能送這一箱的原因（不看位置）
##   claim_block(snapshot,inventory,token="") -> String / can_claim(snapshot,inventory,token="") -> bool
##   claimed_own(snapshot,token="") -> bool
##   public(state) -> Dictionary                   # 快照用：{"crates","day","sent","completed","done_day"}；沒紀錄時 {}
##   apply(state,token,action,p,extra,in_jinguashi) -> {"ok","message"}
##   valid(s) -> bool                              # 存檔檢查（state.jinguashi_revisit）
##   artifacts_valid(s) -> bool                    # 礦燈物件與 kit 只能出現在完成之後
## Session：snapshot.jinguashi_revisit = public(state)（沒紀錄時沒有這個鍵），
##   並只對收件人加上 jinguashi_revisit.claimed_own（bool）。

const MINES=preload("res://scripts/mine_depths.gd")
const BOBO=preload("res://scripts/bobo_workshop.gd")
const WEATHER=preload("res://scripts/weather.gd")

const STATE_KEY:="jinguashi_revisit"
const REGION:="jinguashi"
const SORT_ACTION:="jg_revisit_sort"
const SHIP_ACTION:="jg_revisit_ship"
const CLAIM_ACTION:="jg_revisit_claim"
const ACTIONS:=[SORT_ACTION,SHIP_ACTION,CLAIM_ACTION]
const RECORD_KEYS:=["claimed","completed","crates","day","done_day","sent"]
const REACH:=3.2
const HOIST:=Vector2i(28,19)     # = MINES.ENTRY 下坑路牌（升降台）
const SHUTTLE:=Vector2i(11,20)   # 山城接駁站（Transit jinguashi shuttle）
const DESTS:=["bobo","ferry","depot"]
const DEST_NAMES:={"bobo":"波波的整理桌","ferry":"渡口家園工坊","depot":"坑內礦務站"}
const DEST_HOW:={"bobo":"在波波的整理桌交給波波","ferry":"在山城接駁站寄往風鈴渡口","depot":"用下坑路牌旁的升降台送下坑"}
const ORES:=["stone","copper_ore","gold_ore"]
const ORE_NAMES:={"stone":"石材","copper_ore":"銅礦","gold_ore":"含金礦料"}
const AMOUNTS:={"stone":6,"copper_ore":4,"gold_ore":2}
const MAX_ITEM:=1000000000
const ORDERS:={
	"spring":{"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"},
	"summer":{"bobo":"copper_ore","ferry":"gold_ore","depot":"stone"},
	"autumn":{"bobo":"gold_ore","ferry":"stone","depot":"copper_ore"},
	"winter":{"bobo":"copper_ore","ferry":"gold_ore","depot":"stone"},
}
const REASONS:={
	"spring":"春天渡口要裝新的灑水器，家園工坊等銅礦做銅接頭；波波想整理一批新的金礦樣；雨後的坑道要補強，石材送下坑。",
	"summer":"夏天波波要比對銅礦的成色，請送銅礦來；渡口家園工坊有人想做金工收藏樣本，需要含金礦料；坑道照常要石材補強。",
	"autumn":"秋天渡口要砌新石灶，家園工坊需要石材；波波繼續整理金礦樣；坑內的軌道要換銅件，銅礦送下坑。",
	"winter":"冬天坑道滲水，礦務站要石材墊高步道；渡口家園工坊趕做年節的金工收藏樣本，需要含金礦料；波波趁冬天比對銅礦標本。",
}
const DISCLAIMER:="回訪情節與礦料訂單為原創，非史料。"
const TITLE:="金瓜石回訪・礦料調度"

const LANTERN_KIND:="mine_lantern"
const LANTERN_ITEM:="mine_lantern_kit"
const LANTERN_NAME:="礦燈"
const LANTERN_SOURCE:="來源：金瓜石回訪"
const LANTERN_PROJECT:="對應工程：合作礦場升降台修復"
const LANTERN_BLURB:="提把磨得發亮的小礦燈，紀念大家把升降台送上來的礦料分揀好、送到三處地方。"

const NO_PLAYER:="請重新加入世界再調度礦料。"
const WRONG_REGION:="金瓜石回訪在金瓜石山城，請先到合作礦場。"
const LOCKED:="修好合作礦場的升降台之後，波波才會邀大家回來調度礦料。"
const NOT_READY:="先跟波波完成一次礦樣整理（三份含金礦料分成大、中、小三格），再來幫忙調度礦料。"
const WRONG_SORT_CELL:="請到波波的整理桌分揀貨箱。"
const WRONG_SHIP_CELL:="請走到貨箱的送出地點：波波的整理桌、下坑路牌旁的升降台，或山城接駁站。"
const WRONG_CLAIM_CELL:="請到波波的整理桌找波波。"
const TOO_FAR:="再靠近一點。"
const BAD_EXTRA:="請重新操作礦料調度。"
const BAD_SORT:="請選擇一個貨箱和一種礦料（石材、銅礦或含金礦料）。"
const ALREADY_DONE:="礦料調度已經完成了，三個貨箱都送到了。"
const SENT_LOCKED:="已經有貨箱送出了，這批訂單的分揀不能再改。"
const SAME_SORT:="這個貨箱已經分揀成%s了。"
const ALREADY_SENT:="%s的貨箱已經送出了。"
const UNSORTED:="%s的貨箱還沒分揀，先到波波的整理桌選礦料。"
const WRONG_ORE:="%s的貨箱現在分到%s，訂單要的是%s。回波波的整理桌重新分揀。"
const OTHER_WRONG:="%s的貨箱分對了，但另外的貨箱還不符合訂單，回波波的整理桌重新分揀。"
const SHORT:="這一箱要%s %d，你的背包只有 %d。"
const SORT_OK:="已把%s分揀到%s的貨箱。"
const SHIP_OK:="%s的貨箱送出了（%s %d）。（已送出 %d／3 箱）"
const COMPLETE_OK:="三個貨箱都送到了！波波說，大家可以到整理桌領一盞礦燈帶回家。"
const NOT_DONE:="三個貨箱還沒全部送出，完成後才能領礦燈。"
const CLAIMED:="你已經領過礦燈了。"
const BAG_FULL:="背包裡的礦燈已經放不下了。"
const CLAIM_OK:="波波把一盞礦燈交給你。在家園工坊的「生活」頁選它就能擺到家園；拆除會收回背包。"

# ------------------------------------------------------------------ views --

static func fresh() -> Dictionary:
	return {"crates":{"bobo":"","ferry":"","depot":""},"day":0,"sent":[],"completed":false,"done_day":0,"claimed":{}}

static func unlocked(snapshot:Dictionary) -> bool:
	var depths:Variant=snapshot.get("mine_depths")
	return depths is Dictionary and depths.get("hoist")==true

static func player_ready(snapshot:Dictionary,token:String="") -> bool:
	var workshop:Variant=snapshot.get("bobo_workshop")
	if not workshop is Dictionary:return false
	if not token.is_empty():
		var done:Variant=workshop.get("done")
		return done is Dictionary and done.get(token)==true
	return workshop.get("own_done")==true

static func record(snapshot:Dictionary) -> Dictionary:
	var found:Variant=snapshot.get(STATE_KEY)
	return found if found is Dictionary else fresh()

static func completed(snapshot:Dictionary) -> bool:
	return record(snapshot).get("completed")==true

static func _day_index(snapshot:Dictionary) -> float:
	return WEATHER.day_index(snapshot.get("time",0.0))

static func today(snapshot:Dictionary) -> int:
	return int(_day_index(snapshot))+1

static func sent(snapshot:Dictionary) -> Array:
	var out:=[]
	var raw:Variant=record(snapshot).get("sent")
	if raw is Array:
		for id in raw:
			if str(id) in DESTS and str(id) not in out:out.append(str(id))
	return out

static func order_season(snapshot:Dictionary) -> String:
	var day:=int(record(snapshot).get("day",0))
	if not sent(snapshot).is_empty() and day>=1:return WEATHER.season_on_day(float(day-1))
	return WEATHER.season_on_day(_day_index(snapshot))

static func order_for(season_id:String) -> Dictionary:
	return (ORDERS.get(season_id,ORDERS.spring) as Dictionary).duplicate()

static func reason_for(season_id:String) -> String:
	return str(REASONS.get(season_id,""))

static func order(snapshot:Dictionary) -> Dictionary:
	return order_for(order_season(snapshot))

static func reason(snapshot:Dictionary) -> String:
	return reason_for(order_season(snapshot))

static func amount_for(ore:String) -> int:
	return int(AMOUNTS.get(ore,0))

static func crates(snapshot:Dictionary) -> Dictionary:
	var out:={}
	var raw:Variant=record(snapshot).get("crates")
	for dest:String in DESTS:
		var ore:=""
		if raw is Dictionary and str(raw.get(dest,"")) in ORES:ore=str(raw.get(dest,""))
		out[dest]=ore
	return out

static func sort_cell(snapshot:Dictionary) -> Vector2i:
	return BOBO.sites(snapshot).table

static func claim_cell(snapshot:Dictionary) -> Vector2i:
	return sort_cell(snapshot)

static func dest_cell(snapshot:Dictionary,dest:String) -> Vector2i:
	match dest:
		"bobo":return sort_cell(snapshot)
		"ferry":return SHUTTLE
		"depot":return HOIST
	return Vector2i(-1,-1)

static func dest_at(snapshot:Dictionary,cell:Vector2i) -> String:
	for dest:String in DESTS:
		if dest_cell(snapshot,dest)==cell:return dest
	return ""

static func sort_extra(dest:String,ore:String) -> String:
	return "%s:%s"%[dest,ore]

static func rows(snapshot:Dictionary,inventory:Variant=null) -> Array:
	var now:=crates(snapshot)
	var need:=order(snapshot)
	var done:=sent(snapshot)
	var out:=[]
	for dest:String in DESTS:
		var ore:String=now[dest]
		var wanted:String=need[dest]
		out.append({"id":dest,"name":str(DEST_NAMES[dest]),"how":str(DEST_HOW[dest]),"cell":dest_cell(snapshot,dest),
			"ore":ore,"ore_name":str(ORE_NAMES.get(ore,"")),"needed":wanted,"needed_name":str(ORE_NAMES[wanted]),
			"amount":amount_for(wanted),"have":int(inventory.get(wanted,0)) if inventory is Dictionary else -1,
			"sent":dest in done,"ok":ore==wanted})
	return out

static func _common_block(snapshot:Dictionary,token:String) -> String:
	if not unlocked(snapshot):return LOCKED
	if not player_ready(snapshot,token):return NOT_READY
	return ""

static func sort_block(snapshot:Dictionary,token:String="") -> String:
	var common:=_common_block(snapshot,token)
	if not common.is_empty():return common
	if completed(snapshot):return ALREADY_DONE
	if not sent(snapshot).is_empty():return SENT_LOCKED
	return ""

static func ship_block(snapshot:Dictionary,dest:String,inventory:Variant,token:String="") -> String:
	var common:=_common_block(snapshot,token)
	if not common.is_empty():return common
	return _ship_problem(snapshot,dest,inventory)

## ship_block without the world/player prerequisites (apply() checked those).
static func _ship_problem(snapshot:Dictionary,dest:String,inventory:Variant) -> String:
	if completed(snapshot):return ALREADY_DONE
	if dest not in DESTS:return WRONG_SHIP_CELL
	var place:=str(DEST_NAMES[dest])
	if dest in sent(snapshot):return ALREADY_SENT%place
	var now:=crates(snapshot)
	var need:=order(snapshot)
	var ore:String=now[dest]
	if ore.is_empty():return UNSORTED%place
	if ore!=str(need[dest]):return WRONG_ORE%[place,str(ORE_NAMES[ore]),str(ORE_NAMES[need[dest]])]
	for other:String in DESTS:
		if str(now[other])!=str(need[other]):return OTHER_WRONG%place
	var have:=int(inventory.get(ore,0)) if inventory is Dictionary else 0
	if have<amount_for(ore):return SHORT%[str(ORE_NAMES[ore]),amount_for(ore),have]
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
	if inventory is Dictionary and int(inventory.get(LANTERN_ITEM,0))>=MAX_ITEM:return BAG_FULL
	return ""

static func can_claim(snapshot:Dictionary,inventory:Variant,token:String="") -> bool:
	return claim_block(snapshot,inventory,token).is_empty()

static func public(state:Dictionary) -> Dictionary:
	var found:Variant=state.get(STATE_KEY)
	if not found is Dictionary:return {}
	return {"crates":crates(state),"day":int(found.get("day",0)),"sent":sent(state),
		"completed":found.get("completed")==true,"done_day":int(found.get("done_day",0))}

# ------------------------------------------------------------------ action --

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

static func _distance(person:Dictionary,cell:Vector2i) -> float:
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## World passes in_jinguashi (actor's region is the Jinguashi surface). Every check
## runs before any write, so a failure leaves the whole state unchanged.
static func apply(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,in_jinguashi:bool) -> Dictionary:
	if action not in ACTIONS:return _fail(BAD_EXTRA)
	var people:Variant=state.get("players",{})
	if not people is Dictionary or not people.get(token) is Dictionary:return _fail(NO_PLAYER)
	var person:Dictionary=people[token]
	if not in_jinguashi:return _fail(WRONG_REGION)
	if not unlocked(state):return _fail(LOCKED)
	if not player_ready(state,token):return _fail(NOT_READY)
	if state.has(STATE_KEY) and not _shape_ok(state[STATE_KEY]):return _fail(BAD_EXTRA)
	var target:Vector2i
	if action==SORT_ACTION:
		target=sort_cell(state)
		if p!=target:return _fail(WRONG_SORT_CELL)
	elif action==SHIP_ACTION:
		if dest_at(state,p).is_empty():return _fail(WRONG_SHIP_CELL)
		target=p
	else:
		target=claim_cell(state)
		if p!=target:return _fail(WRONG_CLAIM_CELL)
	if _distance(person,target)>REACH:return _fail(TOO_FAR)
	if action==SORT_ACTION:return _sort(state,extra)
	if not extra.is_empty():return _fail(BAD_EXTRA)
	if action==SHIP_ACTION:return _ship(state,dest_at(state,p),person)
	return _claim(state,token,person)

static func _sort(state:Dictionary,extra:String) -> Dictionary:
	if completed(state):return _fail(ALREADY_DONE)
	var parts:=extra.split(":")
	if parts.size()!=2 or parts[0] not in DESTS or parts[1] not in ORES:return _fail(BAD_SORT)
	if not sent(state).is_empty():return _fail(SENT_LOCKED)
	var dest:String=parts[0]
	var ore:String=parts[1]
	var now:=crates(state)
	if str(now[dest])==ore:return _fail(SAME_SORT%str(ORE_NAMES[ore]))
	var own:Dictionary=record(state).duplicate(true)
	now[dest]=ore
	own.crates=now
	state[STATE_KEY]=own
	return {"ok":true,"message":SORT_OK%[str(ORE_NAMES[ore]),str(DEST_NAMES[dest])]}

static func _ship(state:Dictionary,dest:String,person:Dictionary) -> Dictionary:
	if not person.get("inventory") is Dictionary:return _fail(NO_PLAYER)
	var inv:Dictionary=person.inventory
	var block:=_ship_problem(state,dest,inv)
	if not block.is_empty():return _fail(block)
	var own:Dictionary=state[STATE_KEY]
	var ore:=str(crates(state)[dest])
	var amount:=amount_for(ore)
	var done:=sent(state)
	if done.is_empty():own.day=today(state)
	done.append(dest)
	own.sent=done
	inv[ore]=int(inv.get(ore,0))-amount
	if done.size()==DESTS.size():
		own.completed=true
		own.done_day=today(state)
		return {"ok":true,"message":COMPLETE_OK}
	return {"ok":true,"message":SHIP_OK%[str(DEST_NAMES[dest]),str(ORE_NAMES[ore]),amount,done.size()]}

static func _claim(state:Dictionary,token:String,person:Dictionary) -> Dictionary:
	if not completed(state):return _fail(NOT_DONE)
	if claimed_own(state,token):return _fail(CLAIMED)
	if not person.get("inventory") is Dictionary:return _fail(NO_PLAYER)
	var inv:Dictionary=person.inventory
	if int(inv.get(LANTERN_ITEM,0))>=MAX_ITEM:return _fail(BAG_FULL)
	var own:Dictionary=state[STATE_KEY]
	own.claimed[token]=true
	inv[LANTERN_ITEM]=int(inv.get(LANTERN_ITEM,0))+1
	return {"ok":true,"message":CLAIM_OK}

## Runtime shape check (full consistency is valid()'s job at load time).
static func _shape_ok(own:Variant) -> bool:
	if not own is Dictionary or own.size()!=RECORD_KEYS.size():return false
	for field:String in RECORD_KEYS:
		if not own.has(field):return false
	if not own.crates is Dictionary or own.crates.size()!=DESTS.size():return false
	for dest:String in DESTS:
		if not own.crates.has(dest) or not own.crates[dest] is String:return false
	return own.sent is Array and own.claimed is Dictionary and own.completed is bool

# ------------------------------------------------------------------ schema --

static func _whole(value:Variant,minimum:float,maximum:float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum and floorf(float(value))==float(value)

## state.jinguashi_revisit (optional). Exact keys; crates exactly the three
## destinations, each "" or a known ore; day/done_day 0..today; sent a duplicate-free
## subset of DESTS; day==0 <=> nothing sent; completed <=> all three sent <=> done_day>0
## (and done_day >= day); once anything is sent every crate matches the order of
## day's season; the record needs the repaired hoist; claimed only after completion,
## values true, keys known players who finished their own Bobo sort.
## Normalises JSON floats (day/done_day) to int on success.
static func valid(s:Dictionary) -> bool:
	if not s.has(STATE_KEY):return true
	var own:Variant=s[STATE_KEY]
	if not _shape_ok(own):return false
	if not unlocked(s):return false
	for dest:String in DESTS:
		var ore:String=own.crates[dest]
		if not ore.is_empty() and ore not in ORES:return false
	var now_day:=int(WEATHER.day_index(s.get("time",0.0)))+1
	if not _whole(own.day,0,now_day) or not _whole(own.done_day,0,now_day):return false
	var seen:={}
	for id in own.sent:
		if not id is String or id not in DESTS or seen.has(id):return false
		seen[id]=true
	if (int(own.day)==0)!=seen.is_empty():return false
	if own.completed!=(seen.size()==DESTS.size()):return false
	if own.completed!=(int(own.done_day)>0):return false
	if own.completed and int(own.done_day)<int(own.day):return false
	if not seen.is_empty():
		var wanted:=order_for(WEATHER.season_on_day(float(int(own.day)-1)))
		for dest:String in DESTS:
			if str(own.crates[dest])!=str(wanted[dest]):return false
	var players:Variant=s.get("players")
	var workshop:Variant=s.get("bobo_workshop")
	var done:Variant=workshop.get("done") if workshop is Dictionary else null
	for token in own.claimed:
		if not own.completed or not token is String or own.claimed[token]!=true:return false
		if not players is Dictionary or not players.has(token):return false
		if not done is Dictionary or done.get(token)!=true:return false
	own.day=int(own.day)
	own.done_day=int(own.done_day)
	return true

## Placed mine lanterns and lantern kits exist only after the revisit. Checks home
## and every regional object layer (placed objects and container items) plus every
## player's inventory.
static func artifacts_valid(s:Dictionary) -> bool:
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
			if not obj is Dictionary:continue
			if str(obj.get("type",""))==LANTERN_KIND:return false
			var items:Variant=obj.get("items")
			if items is Dictionary and int(items.get(LANTERN_ITEM,0))!=0:return false
	var players:Variant=s.get("players",{})
	if players is Dictionary:
		for token in players:
			var person:Variant=players[token]
			if person is Dictionary and person.get("inventory") is Dictionary and int(person.inventory.get(LANTERN_ITEM,0))!=0:return false
	return true
