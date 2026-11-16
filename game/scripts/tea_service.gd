extends RefCounted
## 第 40 章「陶器可用於上菜」：把貓空與鶯歌回訪領到的茶陶組借給風鈴渡口的共餐桌，
## 用一份焙好的茶泡一壺，分成六杯，島民各喝一杯。
##
## 與規劃的差距：只有共餐桌泡茶這一種上菜用途，沒有茶屋佈置；喝茶沒有數值效果、
## 不進圖鑑、不給物品（只是共享的一輪）；火鍋與西瓜不使用茶陶組。杯數與用量為實作選擇。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；失敗時 state 完全不變（先檢查完全部條件，
## 最後才寫入）。不 preload World（避免循環），只 preload community.gd 與 tea_revisit.gd。
##
## ── 世界紀錄 state.tea_service（可省略；第一次擺上桌才寫入，收回時整個移除；
##    舊存檔不需遷移，不升版）
##   {"lender":token}                                   # 茶陶組在桌上，還沒泡過
##   {"lender":token,"round":{"style":"light"|"deep","portions":int,"claimed":{token:true},"day":int}}
##   每一壺固定 CUPS=6 杯：portions == CUPS − claimed.size()；day＝泡茶當天的世界日（1 起算）。
##   喝完的一輪（portions 0）留著，直到下一次泡茶覆寫或茶陶組被收回。
##   隔夜茶：世界日超過 round.day 之後，剩下的茶「涼了」——不能再喝，也不再擋住重新泡茶與
##   收回茶陶組（單人世界一壺喝不完六杯，隔天就能重泡或收回）。portions() 回傳「還能喝的杯數」，
##   涼掉時為 0；current_round().left 是壺裡實際剩下的杯數。
##   存在時必須：picnic==true、共餐桌有位置、茶罐大單已完成、lender 與 claimed 都是世界裡的玩家。
##   茶陶組是個人紀念物（不能交易）：擺上桌扣出借人背包 1 組，只有出借人能收回（背包 +1）。
##
## ── 公開快照（Session.public_state 用 public()；token 不外流）
##   snapshot.tea_service = {"placed":true}                              # 沒泡過
##                        = {"placed":true,"round":{"style","portions","day"}} # 泡過（portions＝實際剩下）
##   收件人另外拿到 "lender_own":bool 與 "sipped_own":bool（Session._send_snapshot 用
##   lender_own()/sipped_own()）。桌上沒有茶陶組時快照沒有這個鍵。
##
## ── 動作（World._apply 在 TABLE_WARMER 之後轉給 apply()；p 一律是共餐桌格）
##   tea_service_place  extra＝""：扣本人茶陶組 1，state.tea_service={"lender":token}
##   tea_service_take   extra＝""：只有出借人；桌上沒有當天泡的剩茶時；本人茶陶組 +1，移除紀錄
##   tea_service_brew   extra＝"light"|"deep"：任何島民；桌上沒有當天泡的剩茶時；扣本人淺焙茶／深焙茶 1，
##                      round={"style":extra,"portions":6,"claimed":{},"day":今天}
##   tea_service_sip    extra＝""：每人每壺一杯；portions −1、claimed[token]=true（不給物品）
##   檢查順序：NO_PLAYER → LOCKED（野餐前）→ WRONG_REGION → NO_TABLE → WRONG_CELL → TOO_FAR
##   （REACH=3.2）→ 各動作：
##     place：BAD_EXTRA → NOT_DONE（茶罐大單未完成）→ ALREADY → NO_KIT
##     take ：BAD_EXTRA → NOT_PLACED → NOT_LENDER → TEA_LEFT → BAG_FULL
##     brew ：BAD_STYLE → NOT_PLACED → TEA_LEFT_BREW → NO_TEA%
##     sip  ：BAD_EXTRA → NOT_PLACED → NO_ROUND → EMPTY → COLD → SIPPED
##
## ── 介面用的純函式（snapshot 可以是伺服器 state（給 token）或用戶端家園快照（token＝""））
##   placed(snapshot) -> bool
##   lender_own(snapshot,token="") -> bool
##   current_round(snapshot) -> Dictionary    # {"style","portions","day","left","cold"}；沒泡過時 {}
##                                            # portions＝還能喝的杯數（涼掉為 0），left＝實際剩下
##   today(snapshot) -> int                   # 世界日（與茶罐大單相同算法）
##   portions(snapshot) -> int                # 還能喝的杯數
##   style_name(style) -> String              # 淺焙茶／深焙茶
##   sipped_own(snapshot,token="") -> bool
##   place_block(snapshot,inventory) -> String
##   take_block(snapshot,inventory,token="") -> String
##   brew_block(snapshot,style,inventory) -> String
##   sip_block(snapshot,token="") -> String    # 以上四個都不看位置；可以時 ""
##   status_text(snapshot) -> String           # 一句目前狀態
##   public(state) -> Dictionary               # 快照用；沒擺時 {}
##   apply(state,token,action,p,extra,at_home) -> {"ok","message"}
##   valid(s) -> bool                          # 存檔檢查（save_schema 頂層呼叫一次）

const COMMUNITY=preload("res://scripts/community.gd")
const TEA_REVISIT=preload("res://scripts/tea_revisit.gd")

const PLACE_ACTION:="tea_service_place"
const TAKE_ACTION:="tea_service_take"
const BREW_ACTION:="tea_service_brew"
const SIP_ACTION:="tea_service_sip"
const ACTIONS:=[PLACE_ACTION,TAKE_ACTION,BREW_ACTION,SIP_ACTION]
const STATE_KEY:="tea_service"
const KIT:="tea_ware_kit"
const KIT_NAME:="茶陶組"
const STYLES:=["light","deep"]
const TEA_ITEMS:={"light":"tea_light","deep":"tea_deep"}
const STYLE_NAMES:={"light":"淺焙茶","deep":"深焙茶"}
const CUPS:=6
const REACH:=3.2
const LIMIT:=1000000000
const NAME:="茶陶上桌"
const DISCLAIMER:="共餐桌泡茶是遊戲裡的原創玩法，非史料。"

const NO_PLAYER:="請重新加入世界再使用共餐桌。"
const LOCKED:="完成渡口野餐後，共餐桌才能擺茶陶組。"
const WRONG_REGION:="共餐桌在風鈴渡口，請回到渡口再操作。"
const NO_TABLE:="渡口的共餐桌位置被占住了，先把廣場整理出來。"
const WRONG_CELL:="請走到風鈴渡口的共餐桌前再操作。"
const TOO_FAR:="再靠近共餐桌一點。"
const BAD_EXTRA:="請重新打開共餐桌。"
const NOT_DONE:="貓空與鶯歌回訪的茶罐大單寄出後，陶師送的茶陶組才能擺上共餐桌。"
const ALREADY:="共餐桌上已經有一組茶陶組了。"
const NO_KIT:="你的背包裡沒有茶陶組。擺在家園的要先拆除收回背包，或到鶯歌陶坊找陶師領一組。"
const PLACED_OK:="茶陶組擺上共餐桌了。帶一份淺焙茶或深焙茶來，就能泡一壺分給六位島民。"
const NOT_PLACED:="共餐桌上還沒有茶陶組。"
const NOT_LENDER:="這組茶陶組是別的島民借給共餐桌的，只有出借的人能收回。"
const TEA_LEFT:="壺裡還有茶，等大家喝完再收回茶陶組。"
const BAG_FULL:="背包裡的茶陶組已經放不下了。"
const TAKEN_OK:="你把茶陶組從共餐桌收回背包了。"
const BAD_STYLE:="請選淺焙茶或深焙茶。"
const TEA_LEFT_BREW:="壺裡還有茶，先留給晚點回來的島民。"
const NO_TEA:="你的背包裡沒有%s。到貓空合作茶園的焙茶爐焙一份再來。"
const BREWED_OK:="%s泡好了，六杯留在共餐桌，島民可以各喝一杯。"
const NO_ROUND:="茶壺還是空的，先泡一壺茶。"
const EMPTY:="這一壺已經喝完了，再泡一壺吧。"
const SIPPED:="你已經喝過這一壺，剩下的留給其他島民。"
const COLD:="這一壺是前一天泡的，已經涼了。重新泡一壺吧。"
const SIP_OK:="你喝了一杯%s。（這一壺還剩 %d 杯）"

static func _record(snapshot:Dictionary) -> Dictionary:
	var found:Variant=snapshot.get(STATE_KEY)
	return found if found is Dictionary else {}

static func placed(snapshot:Dictionary) -> bool:
	var record:=_record(snapshot)
	return record.get("placed")==true or record.get("lender") is String

static func lender_own(snapshot:Dictionary,token:String="") -> bool:
	var record:=_record(snapshot)
	if record.has("lender_own"):return record.lender_own==true
	return not token.is_empty() and record.get("lender") is String and record.lender==token

static func current_round(snapshot:Dictionary) -> Dictionary:
	var found:Variant=_record(snapshot).get("round")
	if not found is Dictionary or not STYLES.has(found.get("style")):return {}
	var raw:Variant=found.get("portions",0)
	var left:int=int(raw) if (raw is int or raw is float) else 0
	var brewed:Variant=found.get("day",0)
	var day:int=int(brewed) if (brewed is int or brewed is float) else 0
	var cold:bool=day>0 and today(snapshot)>day
	return {"style":str(found.style),"portions":0 if cold else left,"day":day,"left":left,"cold":cold}

static func today(snapshot:Dictionary) -> int:
	return TEA_REVISIT.today(snapshot)

static func portions(snapshot:Dictionary) -> int:
	return int(current_round(snapshot).get("portions",0))

static func style_name(style:String) -> String:
	return str(STYLE_NAMES.get(style,"茶"))

static func sipped_own(snapshot:Dictionary,token:String="") -> bool:
	var record:=_record(snapshot)
	if record.has("sipped_own"):return record.sipped_own==true
	var found:Variant=record.get("round")
	if token.is_empty() or not found is Dictionary or not found.get("claimed") is Dictionary:return false
	return found.claimed.has(token)

static func _count(inventory:Variant,item:String) -> int:
	if not inventory is Dictionary:return 0
	var value:Variant=inventory.get(item,0)
	return int(value) if (value is int or value is float) else 0

static func _site_block(snapshot:Dictionary) -> String:
	if snapshot.get("picnic",false)!=true:return LOCKED
	if COMMUNITY.table_cell(snapshot)==COMMUNITY.NO_CELL:return NO_TABLE
	return ""

static func place_block(snapshot:Dictionary,inventory:Variant) -> String:
	var site:=_site_block(snapshot)
	if not site.is_empty():return site
	if not TEA_REVISIT.completed(snapshot):return NOT_DONE
	if placed(snapshot):return ALREADY
	if _count(inventory,KIT)<1:return NO_KIT
	return ""

static func take_block(snapshot:Dictionary,inventory:Variant,token:String="") -> String:
	var site:=_site_block(snapshot)
	if not site.is_empty():return site
	if not placed(snapshot):return NOT_PLACED
	if not lender_own(snapshot,token):return NOT_LENDER
	if portions(snapshot)>0:return TEA_LEFT
	if _count(inventory,KIT)>=LIMIT:return BAG_FULL
	return ""

static func brew_block(snapshot:Dictionary,style:String,inventory:Variant) -> String:
	var site:=_site_block(snapshot)
	if not site.is_empty():return site
	if not STYLES.has(style):return BAD_STYLE
	if not placed(snapshot):return NOT_PLACED
	if portions(snapshot)>0:return TEA_LEFT_BREW
	if _count(inventory,TEA_ITEMS[style])<1:return NO_TEA%STYLE_NAMES[style]
	return ""

static func sip_block(snapshot:Dictionary,token:String="") -> String:
	var site:=_site_block(snapshot)
	if not site.is_empty():return site
	if not placed(snapshot):return NOT_PLACED
	var now:=current_round(snapshot)
	if now.is_empty():return NO_ROUND
	if int(now.left)<=0:return EMPTY
	if now.cold:return COLD
	if sipped_own(snapshot,token):return SIPPED
	return ""

static func status_text(snapshot:Dictionary) -> String:
	if not placed(snapshot):return "共餐桌上還沒有茶陶組。"
	var now:=current_round(snapshot)
	if now.is_empty():return "茶陶組擺在共餐桌上，茶壺還是空的。"
	if int(now.left)<=0:return "上一壺%s已經喝完了。"%style_name(now.style)
	if now.cold:return "前一天泡的%s已經涼了，可以重新泡一壺。"%style_name(now.style)
	return "桌上有一壺%s，還剩 %d／%d 杯。"%[style_name(now.style),int(now.portions),CUPS]

static func public(state:Dictionary) -> Dictionary:
	if not placed(state):return {}
	var out:={"placed":true}
	var now:=current_round(state)
	if not now.is_empty():out["round"]={"style":now.style,"portions":int(now.left),"day":int(now.day)}
	return out

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
	if not player.get("inventory") is Dictionary:return _fail(NO_PLAYER)
	var inventory:Dictionary=player.inventory
	if action==BREW_ACTION:
		if not STYLES.has(extra):return _fail(BAD_STYLE)
	elif not extra.is_empty():return _fail(BAD_EXTRA)
	match action:
		PLACE_ACTION:
			if not TEA_REVISIT.completed(state):return _fail(NOT_DONE)
			if placed(state):return _fail(ALREADY)
			var kits:=_count(inventory,KIT)
			if kits<1:return _fail(NO_KIT)
			if kits==1:inventory.erase(KIT)
			else:inventory[KIT]=kits-1
			state[STATE_KEY]={"lender":token}
			return {"ok":true,"message":PLACED_OK}
		TAKE_ACTION:
			if not placed(state):return _fail(NOT_PLACED)
			if not lender_own(state,token):return _fail(NOT_LENDER)
			if portions(state)>0:return _fail(TEA_LEFT)
			var held:=_count(inventory,KIT)
			if held>=LIMIT:return _fail(BAG_FULL)
			inventory[KIT]=held+1
			state.erase(STATE_KEY)
			return {"ok":true,"message":TAKEN_OK}
		BREW_ACTION:
			if not placed(state):return _fail(NOT_PLACED)
			if portions(state)>0:return _fail(TEA_LEFT_BREW)
			var item:String=TEA_ITEMS[extra]
			var tea:=_count(inventory,item)
			if tea<1:return _fail(NO_TEA%STYLE_NAMES[extra])
			if tea==1:inventory.erase(item)
			else:inventory[item]=tea-1
			state[STATE_KEY]["round"]={"style":extra,"portions":CUPS,"claimed":{},"day":today(state)}
			return {"ok":true,"message":BREWED_OK%STYLE_NAMES[extra]}
	# SIP_ACTION
	if not placed(state):return _fail(NOT_PLACED)
	var record:Dictionary=state[STATE_KEY]
	var now:Variant=record.get("round")
	if not now is Dictionary:return _fail(NO_ROUND)
	if int(now.get("portions",0))<=0:return _fail(EMPTY)
	if current_round(state).cold:return _fail(COLD)
	if now.claimed.has(token):return _fail(SIPPED)
	now.claimed[token]=true
	now.portions=int(now.portions)-1
	return {"ok":true,"message":SIP_OK%[STYLE_NAMES[now.style],int(now.portions)]}

## Save check for state.tea_service (absent is fine). Call ONCE at top level from
## save_schema.validate, next to table_warmer.valid (region projections replace
## `community`, so never inside validate_region).
static func valid(s:Dictionary) -> bool:
	if not s.has(STATE_KEY):return true
	var record:Variant=s[STATE_KEY]
	if not record is Dictionary or not record.get("lender") is String:return false
	var players:Variant=s.get("players",{})
	if not players is Dictionary or not players.has(record.lender):return false
	if s.get("picnic")!=true or COMMUNITY.table_cell(s)==COMMUNITY.NO_CELL:return false
	if not TEA_REVISIT.completed(s):return false
	if record.size()==1:return true
	if record.size()!=2 or not record.get("round") is Dictionary:return false
	var now:Dictionary=record.round
	if now.size()!=4 or not now.get("style") is String or not STYLES.has(now.style):return false
	var day:Variant=now.get("day")
	if not (day is int or day is float) or day!=float(int(day)) or day<1 or day>today(s):return false
	var left:Variant=now.get("portions")
	var claimed:Variant=now.get("claimed")
	if not (left is int or left is float) or not claimed is Dictionary:return false
	if left!=float(int(left)) or left<0 or left!=CUPS-claimed.size():return false
	for who:Variant in claimed:
		if not who is String or not players.has(who) or not claimed[who] is bool or claimed[who]!=true:return false
	now.portions=int(left)
	now.day=int(day)
	return true
