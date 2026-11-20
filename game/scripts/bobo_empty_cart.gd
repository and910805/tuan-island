extends RefCounted
## T066 N03-4「最後一趟空車」：波波好感第四階（好友）的行動前半——陪波波把祖父的空礦車
## 沿金瓜石運礦軌道推到展覽位。推到之後（need bobo_cart_arrived）才能在波波身邊選紀念牌
## 文字並完成既有的〈最後一趟空車〉，領既有的一次性紀念小物（祖父的礦車）。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數。失敗時 state 完全不變（先檢查完，最後才寫入）。
## 不 preload World（避免循環）；波波的實際站位／在場由 World 傳入。
##
## ── 個人紀錄 player.bobo_empty_cart_stage（FIELD；可省略＝0；存在時整數 1..7）
##   1..6＝空礦車停在 STOPS[stage-1]，正在推；7＝已推到展覽位（STOPS 末格，卸礦側展示位）。
##   只寫本人；公開快照一律不含這個鍵（Session 只在本人位於金瓜石時送 OWN_KEY＝本人那個整數，沒有紀錄為 0）。
##   不碰材料、鈴幣、背包、運礦路線紀錄與任何統計。
##
## ── 動作 bobo_empty_cart（World._apply 在 ORE_ROUTE 之前轉給 apply()）
##   extra＝"start"：p＝波波現在的站位格（伺服器自己再算一次對照）。檢查順序：
##     BAD_EXTRA → NO_PLAYER → WRONG_REGION（本人與波波都要在金瓜石）→ NOT_HERE（波波不在場／p 不是他的站位）
##     → TOO_FAR_BOBO → BAD_RECORD → NEED_BOND（好感未到第四階）→ ALREADY_DONE（第四階已完成）
##     → STARTED（已經開始過，含已到展覽位）→ ORE_BUSY（本人有單人運礦路線的車在路上）
##     成功：stage=1，空礦車在 STOPS[0]。
##   extra＝"push"：p＝空礦車現在的格 cart_cell。BAD_EXTRA → NO_PLAYER → WRONG_REGION → BAD_RECORD
##     → NOT_PUSHING（stage 不在 1..6）→ WRONG_CELL → TOO_FAR（與運礦台車同樣 REACH=2.0）。
##     成功：stage+1（走 STOPS 一步），推六次到 stage=7。
##   本人推車期間（active，stage 1..6），World 拒絕本人的一般運礦路線動作；別人不受影響。
##
## ── 介面用的純函式（snapshot＝用戶端快照，讀 snapshot.own_bobo_empty_cart）
##   stage(snapshot)->int  active(snapshot)->bool（1..6）  cart_cell(snapshot)->Vector2i  label(snapshot)->String
##   person_stage(person)->int  person_active(person)->bool（伺服器端讀本人紀錄）
##   valid_person(person)->bool（存檔檢查，正規化 JSON 浮點數為 int）
const Bond=preload("res://scripts/resident_bond.gd")
const ORE=preload("res://scripts/ore_route.gd")

const ACTION:="bobo_empty_cart"
const ACTIONS:=[ACTION]
const FIELD:="bobo_empty_cart_stage"
const OWN_KEY:="own_bobo_empty_cart"
const REGION:="jinguashi"
const RESIDENT:="bobo"
const NEED_ID:="bobo_cart_arrived"
const GOAL_STAGE:=4
const STOPS:=ORE.STOPS
const PUSHES:=6
const LAST:=7
const REACH:=ORE.REACH
const BOBO_REACH:=3.2
const KEEPSAKE_KIND:="keepsake_bobo_cart"
const KEEPSAKE_ITEM:="keepsake_bobo_cart_kit"
const KEEPSAKE_NAME:="祖父的礦車"
const START_STEP:="start"
const PUSH_STEP:="push"
const STEPS:=[START_STEP,PUSH_STEP]

const NO_PLAYER:="請重新加入世界再推礦車。"
const WRONG_REGION:="波波和祖父的礦車都在金瓜石山城，請先到金瓜石。"
const BAD_EXTRA:="請重新操作波波的礦車。"
const NOT_HERE:="波波不在這裡，請走到他身邊。"
const TOO_FAR_BOBO:="再靠近波波一點。"
const BAD_RECORD:="礦車的紀錄有誤，請重新加入世界。"
const NEED_BOND:="和波波成為好友之後，才能陪他推最後一趟空車。"
const ALREADY_DONE:="〈最後一趟空車〉已經一起完成了，手帳可以重看。"
const STARTED:="空礦車已經在軌道上了，沿著軌道往前推吧。"
const ARRIVED:="空礦車已經推到展覽位了，回去找波波選紀念牌的字。"
const ORE_BUSY:="你有一車礦料在路上，先把礦料卸下來，再陪波波推空車。"
const NOT_PUSHING:="還沒有開始推空礦車，先找波波說一聲。"
const WRONG_CELL:="礦車不在那裡，請走到礦車現在停的地方。"
const TOO_FAR:="再靠近礦車一點。"
const ORE_BLOCKED:="你正陪波波推他祖父的空礦車，先把它推到展覽位，再送礦。"
const START_OK:="波波把祖父的空礦車停在坑口裝礦台，沿著軌道往前推，一共六段。"
const PUSH_OK:="空礦車往前推了一段（第 %d／6 段，還剩 %d 段）。"
const PUSH_LAST:="空礦車推到展覽位了！回去找波波，替紀念牌選一句話。"
const LABEL_PUSH:="祖父的空車・推一段 %d／6"
const LABEL_END:="祖父的空車・已到展覽位"

# ------------------------------------------------------------------ views --

static func _whole(value:Variant,minimum:float,maximum:float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum and floorf(float(value))==float(value)

## A finite integer 1..LAST as int; anything else (missing, text, NaN, fractions, out of range) is 0.
static func clean(value:Variant) -> int:
	return int(value) if _whole(value,1,LAST) else 0

static func person_stage(person:Variant) -> int:
	return clean(person.get(FIELD)) if person is Dictionary else 0

static func person_active(person:Variant) -> bool:
	var at:=person_stage(person)
	return at>=1 and at<=PUSHES

static func stage(snapshot:Dictionary) -> int:
	return clean(snapshot.get(OWN_KEY))

static func active(snapshot:Dictionary) -> bool:
	var at:=stage(snapshot)
	return at>=1 and at<=PUSHES

static func _cell_at(at:int) -> Vector2i:
	return STOPS[clampi(at,1,LAST)-1]

## Where the story cart stands. Without a cart (stage 0) there is no cell: (-1,-1).
static func cart_cell(snapshot:Dictionary) -> Vector2i:
	var at:=stage(snapshot)
	return _cell_at(at) if at>0 else Vector2i(-1,-1)

static func label(snapshot:Dictionary) -> String:
	var at:=stage(snapshot)
	if at<=0:return ""
	return LABEL_END if at>=LAST else LABEL_PUSH%(at-1)

## The value Session sends to its owner: only the player's own integer (0 if missing/malformed).
static func own_value(person:Variant) -> int:
	return person_stage(person)

# ------------------------------------------------------------------ action --

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

static func _distance(person:Dictionary,cell:Vector2i) -> float:
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## World passes: region (the actor's region id), bobo_spot ([region,cell] from World.bond_place),
## bobo_present (RESIDENT_BOND.present). Every check runs before the single write.
static func apply(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,region:String,bobo_spot:Array,bobo_present:bool) -> Dictionary:
	if action not in ACTIONS or extra not in STEPS:return _fail(BAD_EXTRA)
	var people:Variant=state.get("players",{})
	if not people is Dictionary or not people.get(token) is Dictionary:return _fail(NO_PLAYER)
	var person:Dictionary=people[token]
	if region!=REGION:return _fail(WRONG_REGION)
	if person.has(FIELD) and not _whole(person[FIELD],1,LAST):return _fail(BAD_RECORD)
	var at:=person_stage(person)
	if extra==START_STEP:
		if bobo_spot.size()!=2 or str(bobo_spot[0])!=REGION or not bobo_spot[1] is Vector2i:return _fail(WRONG_REGION)
		if not bobo_present or p!=bobo_spot[1]:return _fail(NOT_HERE)
		if _distance(person,bobo_spot[1])>BOBO_REACH:return _fail(TOO_FAR_BOBO)
		if Bond.stage(person,RESIDENT)<GOAL_STAGE:return _fail(NEED_BOND)
		var goals:Variant=person.get("bond_goals")
		if goals is Dictionary and goals.get(RESIDENT) is Dictionary and (goals[RESIDENT] as Dictionary).has(str(GOAL_STAGE)):return _fail(ALREADY_DONE)
		if at>0:return _fail(ARRIVED if at>=LAST else STARTED)
		if ORE.stage(state,token)>0:return _fail(ORE_BUSY)
		person[FIELD]=1
		return {"ok":true,"message":START_OK}
	if at<1 or at>PUSHES:return _fail(ARRIVED if at>=LAST else NOT_PUSHING)
	var cart:=_cell_at(at)
	if p!=cart:return _fail(WRONG_CELL)
	if _distance(person,cart)>REACH:return _fail(TOO_FAR)
	person[FIELD]=at+1
	return {"ok":true,"message":PUSH_LAST if at+1>=LAST else PUSH_OK%[at,LAST-(at+1)]}

# ------------------------------------------------------------------ schema --

## One player's record (optional). Present: finite integer 1..7 and Bobo bond at the fourth stage;
## normalises a JSON float to int on success.
static func valid_person(person:Dictionary) -> bool:
	if not person.has(FIELD):return true
	if not _whole(person[FIELD],1,LAST) or Bond.stage(person,RESIDENT)<GOAL_STAGE:return false
	person[FIELD]=int(person[FIELD])
	return true
