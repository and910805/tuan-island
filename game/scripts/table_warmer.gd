extends RefCounted
## T067「暖岩片」保溫底座：風鈴渡口共餐桌（community.gd）的一次性、全世界共用的永久加裝。
##
## 來源：合作礦場第 12、13 層每次成功敲礦（mine_extract）額外得到暖岩片 warm_stone +1
## （mine_expansion_catalog.DEPTHS[12/13].finds；背包達上限時跳過，與赭土、脈石英相同）。
## 暖岩片不能出貨、不能在小栗攤位賣（不在任何價目表），可以放進箱子、可以交易，與赭土相同。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；失敗時 state 完全不變（先檢查完全部條件，
## 最後才寫入）。不 preload World（避免循環），只 preload community.gd。
##
## ── 世界紀錄 state.table_warmer（可省略；第一次加裝成功才寫入，舊存檔不需遷移，不升版）
##   {"installed": true}      # 唯一的鍵；存在時必須 picnic==true 且共餐桌有位置
## 公開快照：Session 原樣（白名單 public()）送出 snapshot.table_warmer = {"installed":true}；
## 沒有加裝時快照裡沒有這個鍵。不記錄是誰加裝的（沒有 token）。
##
## ── 保溫上桌的一輪 state.community.hotpot
##   {"portions":int,"claimed":{token:true},"total":6}   # 只有保溫上桌才有 total
##   一般 serve_hotpot 仍寫 {"portions":4,"claimed":{}}（沒有 total，舊存檔形狀）。
##   community.valid：portions == total − claimed.size()（沒有 total 時 total=4）；total 只能
##   出現在 hotpot、只能是 6。valid()（save_schema 頂層呼叫一次）：有 total 時底座必須已加裝。
##   西瓜（冷盤）沒有保溫版本。
##   公開快照照舊移除 claimed（只留 portions/total 與本人的 claimed_own）。
##
## ── 動作（World._apply 在 SOUVENIR 之後轉給 apply()）
##   warmer_install     p＝共餐桌格，extra＝""；成本從本人背包扣：暖岩片 6、銅接頭 2、石材 4。
##   serve_hotpot_warm  p＝共餐桌格，extra＝""；只在已加裝時；扣本人雪點鱒魚火鍋 6，
##                      餐桌 hotpot＝{"portions":6,"claimed":{},"total":6}。領取仍用既有的
##                      claim_hotpot（每人每輪一份）。一般 serve_hotpot（4 份）加裝後照常可用。
##   檢查順序：NO_PLAYER → LOCKED（野餐前）→ WRONG_REGION → NO_TABLE → WRONG_CELL →
##   TOO_FAR（REACH=3.2，與一般互動相同）→ BAD_EXTRA →
##     install：ALREADY → SHORT%（缺料文字）
##     serve  ：NOT_INSTALLED → STILL_SERVING（桌上還有火鍋）→ HOTPOT_SHORT
##
## ── 介面用的純函式（snapshot 可以是伺服器 state 或用戶端家園快照）
##   installed(snapshot) -> bool
##   install_cost() -> Dictionary                       # INSTALL_COST 的副本
##   materials(inventory) -> Array[{"item","name","have","need","short"}]（COST_ORDER 順序）
##   missing(inventory) -> Dictionary                   # 只列還差的 {item:差幾個}
##   missing_text(inventory) -> String                  # 「暖岩片 2、石材 1」；不缺時 ""
##   install_block(snapshot,inventory) -> String        # 不能加裝的原因（不看位置）；可以時 ""
##   can_install(snapshot,inventory) -> bool
##   serve_block(snapshot,inventory) -> String          # 不能保溫上桌的原因（不看位置）；可以時 ""
##   can_serve_warm(snapshot,inventory) -> bool
##   round_total(meal) -> int                           # meal.total，沒有時 4
##   public(state) -> Dictionary                        # 快照用；沒加裝時 {}
##   apply(state,token,action,p,extra,at_home) -> {"ok","message"}
##   valid(s) -> bool                                   # 存檔檢查（state.table_warmer＋保溫一輪需底座）

const COMMUNITY=preload("res://scripts/community.gd")

const INSTALL_ACTION:="warmer_install"
const SERVE_ACTION:="serve_hotpot_warm"
const ACTIONS:=[INSTALL_ACTION,SERVE_ACTION]
const STATE_KEY:="table_warmer"
const ITEM:="warm_stone"
const ITEM_NAME:="暖岩片"
const INSTALL_COST:={"warm_stone":6,"copper_joint":2,"stone":4}
const COST_ORDER:=["warm_stone","copper_joint","stone"]
const ITEM_NAMES:={"warm_stone":"暖岩片","copper_joint":"銅接頭","stone":"石材","trout_hotpot":"雪點鱒魚火鍋"}
const DISH:="hotpot"
const HOTPOT_ITEM:=COMMUNITY.HOTPOT
const WARM_PORTIONS:=COMMUNITY.WARM_HOTPOT_PORTIONS
const PLAIN_PORTIONS:=COMMUNITY.HOTPOT_PORTIONS
const REACH:=3.2
const HOME:="home"
const NAME:="保溫底座"

const NO_PLAYER:="請重新加入世界再使用共餐桌。"
const LOCKED:="完成渡口野餐後，才能替共餐桌加裝保溫底座。"
const WRONG_REGION:="共餐桌在風鈴渡口，請回到渡口再操作。"
const NO_TABLE:="渡口的共餐桌位置被占住了，先把廣場整理出來。"
const WRONG_CELL:="請走到風鈴渡口的共餐桌前再操作。"
const TOO_FAR:="再靠近共餐桌一點。"
const BAD_EXTRA:="請重新打開共餐桌。"
const ALREADY:="共餐桌已經裝好保溫底座了。"
const SHORT:="保溫底座的材料不夠，還差%s。"
const INSTALLED_OK:="共餐桌裝好保溫底座了！之後可以一次端上六份熱騰騰的火鍋。"
const NOT_INSTALLED:="共餐桌還沒有保溫底座，先用暖岩片鋪好底座。"
const STILL_SERVING:="餐桌上還有雪點鱒魚火鍋，先留給晚點回來的島民。"
const HOTPOT_SHORT:="需要六份雪點鱒魚火鍋才能用保溫底座上桌。"
const WARM_SERVED:="雪點鱒魚火鍋上桌了。保溫底座讓六份都熱著，島民可以各領一份。"

static func installed(snapshot:Dictionary) -> bool:
	var record:Variant=snapshot.get(STATE_KEY)
	return record is Dictionary and record.get("installed") is bool and record.installed==true

static func install_cost() -> Dictionary:
	return INSTALL_COST.duplicate()

static func _count(inventory:Variant,item:String) -> int:
	if not inventory is Dictionary:return 0
	var value:Variant=inventory.get(item,0)
	return int(value) if (value is int or value is float) else 0

static func materials(inventory:Variant) -> Array:
	var rows:=[]
	for item:String in COST_ORDER:
		var have:=_count(inventory,item)
		var need:=int(INSTALL_COST[item])
		rows.append({"item":item,"name":ITEM_NAMES[item],"have":have,"need":need,"short":maxi(0,need-have)})
	return rows

static func missing(inventory:Variant) -> Dictionary:
	var out:={}
	for row:Dictionary in materials(inventory):
		if int(row.short)>0:out[row.item]=int(row.short)
	return out

static func missing_text(inventory:Variant) -> String:
	var parts:=PackedStringArray()
	for row:Dictionary in materials(inventory):
		if int(row.short)>0:parts.append("%s %d"%[row.name,int(row.short)])
	return "、".join(parts)

static func install_block(snapshot:Dictionary,inventory:Variant) -> String:
	if snapshot.get("picnic",false)!=true:return LOCKED
	if COMMUNITY.table_cell(snapshot)==COMMUNITY.NO_CELL:return NO_TABLE
	if installed(snapshot):return ALREADY
	var short:=missing_text(inventory)
	if not short.is_empty():return SHORT%short
	return ""

static func can_install(snapshot:Dictionary,inventory:Variant) -> bool:
	return install_block(snapshot,inventory).is_empty()

static func serve_block(snapshot:Dictionary,inventory:Variant) -> String:
	if snapshot.get("picnic",false)!=true:return LOCKED
	if COMMUNITY.table_cell(snapshot)==COMMUNITY.NO_CELL:return NO_TABLE
	if not installed(snapshot):return NOT_INSTALLED
	var community:Variant=snapshot.get("community",{})
	var meal:Variant=community.get(DISH,{}) if community is Dictionary else {}
	if meal is Dictionary and int(meal.get("portions",0))>0:return STILL_SERVING
	if _count(inventory,HOTPOT_ITEM)<WARM_PORTIONS:return HOTPOT_SHORT
	return ""

static func can_serve_warm(snapshot:Dictionary,inventory:Variant) -> bool:
	return serve_block(snapshot,inventory).is_empty()

static func round_total(meal:Variant) -> int:
	if meal is Dictionary and meal.has("total"):return int(meal.total)
	return PLAIN_PORTIONS

static func public(state:Dictionary) -> Dictionary:
	return {"installed":true} if installed(state) else {}

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

static func apply(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,at_home:bool) -> Dictionary:
	if action not in ACTIONS:return _fail(BAD_EXTRA)
	var people:Variant=state.get("players",{})
	if not people is Dictionary or not people.has(token) or not people[token] is Dictionary:return _fail(NO_PLAYER)
	var player:Dictionary=people[token]
	if state.get("picnic",false)!=true:return _fail(LOCKED)
	if not at_home:return _fail(WRONG_REGION)
	var table:=COMMUNITY.table_cell(state)
	if table==COMMUNITY.NO_CELL:return _fail(NO_TABLE)
	if p!=table:return _fail(WRONG_CELL)
	var at:=Vector2(float(player.get("x",0.0)),float(player.get("y",0.0)))
	if at.distance_to(Vector2(table)+Vector2(0.5,0.5))>REACH:return _fail(TOO_FAR)
	if not extra.is_empty():return _fail(BAD_EXTRA)
	if not player.get("inventory") is Dictionary:return _fail(NO_PLAYER)
	var inventory:Dictionary=player.inventory
	if action==INSTALL_ACTION:
		if installed(state):return _fail(ALREADY)
		var short:=missing_text(inventory)
		if not short.is_empty():return _fail(SHORT%short)
		for item:String in COST_ORDER:inventory[item]=_count(inventory,item)-int(INSTALL_COST[item])
		state[STATE_KEY]={"installed":true}
		return {"ok":true,"message":INSTALLED_OK}
	# SERVE_ACTION
	if not installed(state):return _fail(NOT_INSTALLED)
	var community:Dictionary=state.community
	var meal:Variant=community.get(DISH,{})
	if meal is Dictionary and int(meal.get("portions",0))>0:return _fail(STILL_SERVING)
	var count:=_count(inventory,HOTPOT_ITEM)
	if count<WARM_PORTIONS:return _fail(HOTPOT_SHORT)
	inventory[HOTPOT_ITEM]=count-WARM_PORTIONS
	community[DISH]={"portions":WARM_PORTIONS,"claimed":{},"total":WARM_PORTIONS}
	return {"ok":true,"message":WARM_SERVED}

## Save check for state.table_warmer (absent is fine). Called ONCE at top level by
## save_schema.validate (never inside validate_region: region projections replace
## `community` with {"table":""}). community.valid already checked the meal shape
## (total only on hotpot, ==6, portions==total−claimed); here a `total` additionally
## requires the installed base.
static func valid(s:Dictionary) -> bool:
	var community:Variant=s.get("community",{})
	var meal:Variant=community.get(DISH) if community is Dictionary else null
	if meal is Dictionary and meal.has("total") and not installed(s):return false
	if not s.has(STATE_KEY):return true
	var record:Variant=s[STATE_KEY]
	if not record is Dictionary or record.size()!=1 or not record.has("installed"):return false
	if not record.installed is bool or record.installed!=true:return false
	if s.get("picnic")!=true:return false
	return COMMUNITY.table_cell(s)!=COMMUNITY.NO_CELL
