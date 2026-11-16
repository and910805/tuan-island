extends RefCounted
## 第四章外圍配對遠征：霧竹溪谷與暖泉高地各一件小型在地委託。
##
## 純 GDScript 輔助模組，不讀寫檔案、不連網，也不預載共用腳本。
## 除了 `complete()` 在 `apply == true` 且通過身分驗證時之外，所有函式都
## 不會修改傳入的 state（status／preview／journal 一律唯讀）。
##
## 整合契約（尚未接入 world.gd／session，見工作回報）：
##   - 呼叫端（伺服器 session）以連線解析出的 token 作為 `auth`，
##     不可採信客戶端自報身分；`auth != token` 一律拒絕。
##   - 完成紀錄存在 state[STATE_KEY].players[token][commission_id] = {"done":true}，
##     每位島民每件委託只能完成一次。此為新存檔鍵，需要存檔綱要接受。
##   - 只消耗既有物品 ID，只發放鈴幣，不新增物品。
##   - 先完整驗證、再一次性扣料與發酬；任何失敗都不改動 state。
##   - 抵達方式只影響敘述文字，不影響獎勵；只有輸入明確帶有合作小船抵達、
##     且碼頭已修好（dock_stage >= 2）時，才會描述「搭合作小船抵達」。
##
## 史實／虛構：霧竹溪谷、竹棚茶亭、高地足湯與兩位委託人皆為遊戲原創。
## 唯一的真實敘述只有「礁溪是宜蘭知名的溫泉地」這種一般常識，不附年份或史料宣稱。

const STATE_KEY:="outlying_commissions"
const REGION_BAMBOO:="bamboo_grove"   # == bamboo_grove.gd REGION
const REGION_SPRINGS:="jiaoxi"        # == warm_springs.gd REGION
const BOAT_MODE:="合作小船"            # == transit.gd boat option mode
const BOAT_DOCK_STAGE:=2               # == transit.gd boat_open threshold
const LIMIT:=1000000000                # same coin / stack ceiling as salt_pan.gd
const MAX_TOKEN_LENGTH:=128
const MAX_MODE_LENGTH:=32

## 物品 ID 皆來自 world.gd NAMES（mist_tea、bamboo_ayu、glass_shrimp、stone）。
const ITEM_NAMES:={"mist_tea":"霧竹茶","bamboo_ayu":"竹影香魚","glass_shrimp":"玻璃小蝦","stone":"石材"}

const DEFS:={
	"bamboo_tea_rest":{
		"region":REGION_BAMBOO,
		"place":"霧竹溪谷",
		"giver":"竹棚守望員・阿嵐",
		"title":"竹棚茶亭的晨間補給",
		"ask":"阿嵐想在竹棚茶亭擺一壺新茶，配一尾晨間的竹影香魚給走步道的旅人歇腳。",
		"needs":{"mist_tea":2,"bamboo_ayu":1},
		"reward_coins":120,
		"hint":"霧竹茶在溪谷茶圃採收；竹影香魚在竹澗晨間（06:00–11:00）較好釣。",
		"thanks":"阿嵐把茶葉收進竹簍：「早上的風一吹，茶香就會順著溪谷飄下去。」",
		"fiction_note":"霧竹溪谷、竹棚茶亭與阿嵐皆為遊戲原創，並非真實地點或人物。",
		"fact_note":"",
	},
	"springs_footbath":{
		"region":REGION_SPRINGS,
		"place":"暖泉高地",
		"giver":"高地足湯管理員・湧伯",
		"title":"高地足湯的踏石與小點心",
		"ask":"湧伯要替足湯邊補幾塊踏石，順便請泡腳的旅人嚐一隻剛撈起的玻璃小蝦。",
		"needs":{"glass_shrimp":1,"stone":3},
		"reward_coins":110,
		"hint":"玻璃小蝦白天在暖泉溪出現；石材可從家園採石取得。",
		"thanks":"湧伯把石材排在池邊：「腳踩穩了，泡起來才安心。」",
		"fiction_note":"暖泉高地的足湯、踏石委託與湧伯皆為遊戲原創。",
		"fact_note":"礁溪是宜蘭知名的溫泉地；遊戲中的地形與設施為簡化後的原創描寫。",
	},
}

const ORDER:=["bamboo_tea_rest","springs_footbath"]

# --- 基本驗證 -----------------------------------------------------------

static func valid_token(token:Variant)->bool:
	return token is String and not (token as String).is_empty() and (token as String).length()<=MAX_TOKEN_LENGTH

static func yes(value:Variant)->bool:
	return value is bool and value

static func ids()->Array:
	return ORDER.duplicate()

## 將背包或鈴幣數值轉為安全整數；JSON 讀回的整數浮點可接受，
## 布林、字串、負數、小數、NaN、超過上限一律視為無效（回傳 -1）。
static func count_of(value:Variant)->int:
	if value is int:
		return value if value>=0 and value<=LIMIT else -1
	if value is float:
		var f:float=value
		if is_nan(f) or is_inf(f) or f<0.0 or f>float(LIMIT) or f!=floorf(f):return -1
		return int(f)
	return -1

static func _player(state:Variant,token:String)->Variant:
	if not state is Dictionary:return null
	var players=(state as Dictionary).get("players")
	if not players is Dictionary:return null
	var p=(players as Dictionary).get(token)
	return p if p is Dictionary else null

static func _visited(player:Dictionary,region:String)->bool:
	var book=player.get("travel_book")
	if not book is Dictionary:return false
	var visited=(book as Dictionary).get("visited")
	return visited is Dictionary and yes((visited as Dictionary).get(region))

static func done(state:Variant,token:String,id:String)->bool:
	if not state is Dictionary:return false
	var data=(state as Dictionary).get(STATE_KEY)
	if not data is Dictionary:return false
	var players=(data as Dictionary).get("players")
	if not players is Dictionary:return false
	var rec=(players as Dictionary).get(token)
	if not rec is Dictionary:return false
	var entry=(rec as Dictionary).get(id)
	return entry is Dictionary and yes((entry as Dictionary).get("done"))

# --- 抵達方式（只影響文字） ---------------------------------------------

## 回傳 "boat"（確認搭合作小船抵達）、"land"（輸入帶有其他交通方式）、
## "unverified_boat"（宣稱小船但碼頭未修好或地區不符）或 "unknown"（未提供）。
static func arrival_kind(state:Variant,id:String,arrival:Variant)->String:
	if not arrival is Dictionary or not DEFS.has(id):return "unknown"
	var a:Dictionary=arrival
	var mode=a.get("mode")
	var region=a.get("region")
	if not mode is String or (mode as String).is_empty() or (mode as String).length()>MAX_MODE_LENGTH:return "unknown"
	var target:String=DEFS[id].region
	var here:bool=region is String and (region as String)==target
	if (mode as String)==BOAT_MODE:
		var stage:=-1
		if state is Dictionary:stage=count_of((state as Dictionary).get("dock_stage",0))
		if here and stage>=BOAT_DOCK_STAGE:return "boat"
		return "unverified_boat"
	return "land" if here else "unknown"

static func arrival_text(state:Variant,id:String,arrival:Variant)->String:
	if not DEFS.has(id):return ""
	var place:String=DEFS[id].place
	match arrival_kind(state,id,arrival):
		"boat":return "你搭合作小船從渡口直接抵達%s。"%place
		"land":return "你經%s轉乘抵達%s。"%[str((arrival as Dictionary).mode),place]
	return "你來到%s。"%place

# --- 唯讀查詢 -----------------------------------------------------------

static func _missing(inv:Dictionary,needs:Dictionary)->Dictionary:
	var short:={}
	for item:String in needs:
		var held:=count_of(inv.get(item,0))
		if held<0:held=0
		if held<int(needs[item]):short[item]=int(needs[item])-held
	return short

static func _needs_text(needs:Dictionary)->String:
	var parts:PackedStringArray=[]
	for item:String in needs:parts.append("%s ×%d"%[ITEM_NAMES.get(item,item),int(needs[item])])
	return "、".join(parts)

## 唯讀狀態。stage 依序為 unknown／no_player／not_visited／elsewhere／done／
## gathering（材料不足）／ready（可交付）。
static func status(state:Variant,token:Variant,id:String,context:Dictionary={})->Dictionary:
	var out:={"id":id,"stage":"unknown","can_complete":false,"done":false,"missing":{},"text":"","fiction_note":"","fact_note":""}
	if not DEFS.has(id):
		out.text="沒有這件委託。"
		return out
	var def:Dictionary=DEFS[id]
	out.fiction_note=def.fiction_note
	out.fact_note=def.fact_note
	if not valid_token(token):
		out.stage="no_player"
		out.text="找不到島民資料。"
		return out
	var player=_player(state,token)
	if not player is Dictionary or not (player as Dictionary).get("inventory") is Dictionary:
		out.stage="no_player"
		out.text="找不到島民資料。"
		return out
	if done(state,token,id):
		out.stage="done"
		out.done=true
		out.text="「%s」已完成，可從手帳重看。"%def.title
		return out
	if not _visited(player,def.region):
		out.stage="not_visited"
		out.text="先經轉乘抵達%s，才能接下「%s」。"%[def.place,def.title]
		return out
	if str((player as Dictionary).get("region",""))!=def.region:
		out.stage="elsewhere"
		out.text="回到%s找%s交付委託。"%[def.place,def.giver]
		return out
	var short:=_missing((player as Dictionary).inventory,def.needs)
	out.missing=short
	if not short.is_empty():
		out.stage="gathering"
		out.text="%s：%s 還差 %s。%s"%[def.giver,def.ask,_needs_text(short),def.hint]
		return out
	out.stage="ready"
	out.can_complete=true
	out.text="%s%s：%s 需要 %s，報酬 %d 鈴幣。"%[arrival_text(state,id,context.get("arrival")),def.giver,def.ask,_needs_text(def.needs),int(def.reward_coins)]
	return out

## 手帳用：兩件委託的唯讀摘要。
static func journal(state:Variant,token:Variant,context:Dictionary={})->Array:
	var rows:=[]
	for id:String in ORDER:
		var s:=status(state,token,id,context)
		rows.append({"id":id,"title":DEFS[id].title,"place":DEFS[id].place,"stage":s.stage,"done":s.done,"fiction_note":s.fiction_note,"fact_note":s.fact_note})
	return rows

# --- 一次性完成（唯一可能修改 state 的入口） ---------------------------

static func _fail(text:String)->Dictionary:
	return {"ok":false,"applied":false,"text":text,"consume":{},"coins":0}

## 預設為試算（不修改 state）。只有 context.apply == true 且 context.auth 與
## token 完全一致時才會扣料、發酬並寫入一次性完成紀錄。
static func complete(state:Variant,token:Variant,id:String,context:Dictionary={})->Dictionary:
	if not DEFS.has(id):return _fail("沒有這件委託。")
	if not valid_token(token):return _fail("找不到島民資料。")
	var apply:bool=yes(context.get("apply"))
	var auth=context.get("auth")
	if apply and not (auth is String and (auth as String)==(token as String)):
		return _fail("身分驗證未通過，委託不結算。")
	var s:=status(state,token,id,context)
	if s.stage=="done":return _fail("「%s」已經交過了。"%DEFS[id].title)
	if not s.can_complete:return _fail(s.text)
	var def:Dictionary=DEFS[id]
	var player:Dictionary=_player(state,token)
	var coins:=count_of(player.get("coins",0))
	if coins<0:return _fail("鈴幣資料異常，委託暫不結算。")
	if coins>LIMIT-int(def.reward_coins):return _fail("鈴幣已達上限，委託暫不結算。")
	var inv:Dictionary=player.inventory
	for item:String in def.needs:
		if count_of(inv.get(item,0))<int(def.needs[item]):return _fail("材料資料異常，委託暫不結算。")
	var data=(state as Dictionary).get(STATE_KEY)
	if typeof(data)!=TYPE_NIL and not (data is Dictionary and (data as Dictionary).get("players",{}) is Dictionary):
		return _fail("委託資料異常，暫不結算。")
	var result:={"ok":true,"applied":false,"consume":(def.needs as Dictionary).duplicate(),"coins":int(def.reward_coins),
		"text":"%s 交給%s，鈴幣 +%d。%s"%[_needs_text(def.needs),def.giver,int(def.reward_coins),def.thanks]}
	if not apply:return result
	# 全部驗證完成，以下才開始修改。
	for item:String in def.needs:inv[item]=count_of(inv[item])-int(def.needs[item])
	player.coins=coins+int(def.reward_coins)
	if typeof(data)==TYPE_NIL:
		data={"players":{}}
		(state as Dictionary)[STATE_KEY]=data
	if not (data as Dictionary).has("players"):(data as Dictionary).players={}
	var players:Dictionary=(data as Dictionary).players
	if not players.get(token) is Dictionary:players[token]={}
	players[token][id]={"done":true}
	result.applied=true
	return result
