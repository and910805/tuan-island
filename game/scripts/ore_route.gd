extends RefCounted
## 規劃書第 40 章金瓜石初訪「沿運礦路線送一批礦料」：合作礦場坑口到山城接駁站之間的一段台車軌道。
## 任何到了金瓜石的島民都能幫忙推一車（不需要強化石鎬、不需要先認識波波、不需要升降台、
## 不需要自己的礦料——車上裝的是合作礦場的礦料）。一車分八步：
##   在坑口裝礦台裝車 load → 一段一段往前推 push ×6（人要走到台車旁）→ 在接駁站卸礦台卸礦 unload
## 卸完一車，合作礦場付運礦工資 PAY（12）鈴幣。每人每個世界日最多送 DAILY（2）車。
## 推到一半的台車會留在原地（離開、隔天、重登都還在）。每個人推的是自己的那一車，別人看不到。
##
## 軌道位置、台車玩法、每日車數與工資為遊戲設計（DISCLAIMER），非史料；這個模組沒有任何史實敘述
## （規劃書列的歷史頁要等來源查證後另做）。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；只看 state.time（WEATHER 曆法）。失敗時 state
## 完全不變（先檢查完全部條件，最後才寫入）。不 preload World（避免循環）。
##
## ── 世界紀錄 state.ore_route（可省略；第一次成功裝車才寫入，舊存檔不需遷移，不升版）
##   {"players":{token:{"stage":int,   # 0＝沒有在送（空車停在裝礦台 STOPS[0]）；
##                                     # 1..STOPS.size()＝裝好的台車停在 STOPS[stage-1]
##                                     # （stage==STOPS.size() 時在卸礦台，下一步是卸礦）
##                      "day":int,     # 最近一次卸完一車的世界日；還沒卸過時 0
##                      "count":int,   # day 那天卸完的車數（1..DAILY）；還沒卸過時 0
##                      "total":int}}} # 累計卸完的車數
##   只在伺服器；公開快照不含這個鍵（Session 只把本人的 view() 放進 snapshot.own_ore_route）。
##
## ── 地點：STOPS 七個停靠格（都是可以走的平地；台車與軌道不擋路、不佔格、不能互動以外的用途）。
##    TRACK 是依序相連的 23 格軌道（含所有 STOPS）。人站在台車所在格中心 REACH=2.0 以內才能動它。
##
## ── 動作 ore_cart（World._apply 在 GOLD_PANNING 之後、一般距離檢查之前轉給 apply()）
##   p＝台車現在所在的格 cart_cell(stage)，extra＝"load"／"push"／"unload"。
##   檢查順序：BAD_EXTRA（不是本模組的動作）→ NO_PLAYER → WRONG_REGION → BAD_EXTRA（extra 不是
##     三種之一，或紀錄壞掉）→ WRONG_CELL（p 不是台車現在的格）→ TOO_FAR → step_block()：
##     load  ：LOADED（車上已經有礦）→ DAILY_DONE
##     push  ：NEED_LOAD → AT_END（已到卸礦台）
##     unload：NEED_LOAD → NOT_THERE（還沒推到卸礦台）→ PURSE_FULL
##   成功訊息：LOAD_OK、PUSH_OK%[第幾段,還剩幾段]／PUSH_LAST、UNLOAD_OK%[工資,今天第幾車]。
##
## ── 介面用的純函式（snapshot 可以是伺服器 state 或用戶端快照；token 只在伺服器 state 有用，
##    用戶端快照讀 snapshot.own_ore_route）
##   view(snapshot,token="") -> {"stage","count","total"}   # count＝「今天」已卸完的車數
##   stage(snapshot,token="") / count_today(snapshot,token="") / total(snapshot,token="") -> int
##   today(snapshot) -> int
##   next_step(snapshot,token="") -> String        # step_at(stage)
##   step_at(stage) -> String                      # "load"／"push"／"unload"
##   cart_cell(stage) -> Vector2i                  # 台車現在停在哪一格
##   pushes_left(stage) -> int                     # 還要推幾段（0..PUSHES）
##   step_block(snapshot,step,person,token="") -> String   # 不能做這一步的原因（不看位置）；可以時 ""
##   stage_text(stage) -> String                   # 台車現在的狀況（頁面用）
##   cart_label(snapshot,token="") -> String       # 世界名牌（靠近台車時）
##   apply(state,token,action,p,extra,in_jinguashi) -> {"ok","message"}
##   valid(s) -> bool                              # 存檔檢查（state.ore_route）

const WEATHER=preload("res://scripts/weather.gd")

const STATE_KEY:="ore_route"
const OWN_KEY:="own_ore_route"
const REGION:="jinguashi"
const ACTION:="ore_cart"
const ACTIONS:=[ACTION]
const REACH:=2.0
const DAILY:=2
const PAY:=12
const LIMIT:=1000000000
const STEP_IDS:=["load","push","unload"]
const STEP_NAMES:={"load":"裝車","push":"推台車","unload":"卸礦"}
const RECORD_KEYS:=["count","day","stage","total"]
## 停靠格：坑口裝礦台 → 五個中途停靠點 → 接駁站卸礦台。
const STOPS:=[Vector2i(31,20),Vector2i(28,21),Vector2i(26,23),Vector2i(23,23),Vector2i(20,23),Vector2i(16,23),Vector2i(14,21)]
const PUSHES:=6 # = STOPS.size()-1
const LAST:=7   # = STOPS.size()：台車在卸礦台
## 依序相連的軌道格（相鄰兩格只差一格、不走斜線），STOPS 依序出現在其中。
const TRACK:=[
	Vector2i(31,20),Vector2i(31,21),Vector2i(30,21),Vector2i(29,21),Vector2i(28,21),
	Vector2i(27,21),Vector2i(26,21),Vector2i(26,22),Vector2i(26,23),
	Vector2i(25,23),Vector2i(24,23),Vector2i(23,23),
	Vector2i(22,23),Vector2i(21,23),Vector2i(20,23),
	Vector2i(19,23),Vector2i(18,23),Vector2i(17,23),Vector2i(16,23),
	Vector2i(16,22),Vector2i(16,21),Vector2i(15,21),Vector2i(14,21),
]
const TITLE:="金瓜石・運礦路線"
const LOAD_NAME:="坑口裝礦台"
const UNLOAD_NAME:="接駁站卸礦台"
const CART_NAME:="運礦台車"
const BLURB:="合作礦場的礦料要從坑口用台車送到山城接駁站。在裝礦台裝好一車，沿著軌道一段一段往前推，到卸礦台卸下來，礦場會付一點運礦工資。"
const HOW:="裝好車之後關掉這一頁，走到台車旁按互動鍵往前推。"
const DISCLAIMER:="軌道位置、台車玩法、每日車數與工資為遊戲設計，非史料。"

const NO_PLAYER:="請重新加入世界再推台車。"
const WRONG_REGION:="運礦台車在金瓜石山城的合作礦場坑口，請先到金瓜石。"
const BAD_EXTRA:="請重新操作運礦台車。"
const WRONG_CELL:="台車不在那裡，請走到台車現在停的地方。"
const TOO_FAR:="再靠近台車一點。"
const LOADED:="台車已經裝好礦料了，沿著軌道往前推吧。"
const DAILY_DONE:="今天已經送了 2 車，礦場的人說剩下的明天再送。"
const NEED_LOAD:="台車還是空的，先到坑口的裝礦台裝車。"
const AT_END:="台車已經到接駁站的卸礦台了，把礦料卸下來吧。"
const NOT_THERE:="台車還沒推到接駁站的卸礦台，不能在半路卸礦。"
const PURSE_FULL:="鈴幣已達上限，礦料先留在車上。"
const LOAD_OK:="礦料裝上台車了。沿著軌道往接駁站推，一共六段。"
const PUSH_OK:="台車往前推了一段（第 %d／6 段，還剩 %d 段）。"
const PUSH_LAST:="台車推到接駁站的卸礦台了！把礦料卸下來。"
const UNLOAD_OK:="礦料卸到接駁站了，領到運礦工資 %d 鈴幣（今天第 %d／2 車）。空車由礦場的人推回坑口。"
const STAGE_IDLE:="空台車停在坑口的裝礦台。"
const STAGE_MOVING:="裝好的台車停在軌道上（已推 %d／6 段）。"
const STAGE_END:="台車停在接駁站的卸礦台，等著卸礦。"
const LABEL_IDLE:="坑口裝礦台・幫忙送一車礦料"
const LABEL_FULL:="坑口裝礦台・今天已送 2 車"
const LABEL_PUSH:="運礦台車・往前推（已推 %d／6 段）"
const LABEL_END:="接駁站卸礦台・卸礦"

# ------------------------------------------------------------------ views --

static func fresh_record() -> Dictionary:
	return {"stage":0,"day":0,"count":0,"total":0}

static func today(snapshot:Dictionary) -> int:
	return int(WEATHER.day_index(snapshot.get("time",0.0)))+1

## The server-side record of `token` (a copy); {} when there is none or it is malformed.
static func _record(state:Dictionary,token:String) -> Dictionary:
	var found:Variant=state.get(STATE_KEY)
	if not found is Dictionary or not found.get("players") is Dictionary:return {}
	var own:Variant=found.players.get(token)
	if not _record_ok(own):return {}
	return (own as Dictionary).duplicate()

static func view(snapshot:Dictionary,token:String="") -> Dictionary:
	if token.is_empty():
		var sent:Variant=snapshot.get(OWN_KEY)
		if sent is Dictionary:
			return {"stage":clampi(_number(sent.get("stage")),0,LAST),"count":clampi(_number(sent.get("count")),0,DAILY),"total":clampi(_number(sent.get("total")),0,LIMIT)}
		return {"stage":0,"count":0,"total":0}
	var own:=_record(snapshot,token)
	if own.is_empty():return {"stage":0,"count":0,"total":0}
	return {"stage":int(own.stage),"count":int(own.count) if int(own.day)==today(snapshot) else 0,"total":int(own.total)}

## A finite number as int; anything else (missing, text, arrays, NaN) is 0.
static func _number(value:Variant) -> int:
	if (value is int or value is float) and is_finite(float(value)):return int(clampf(float(value),-float(LIMIT),float(LIMIT)))
	return 0

static func stage(snapshot:Dictionary,token:String="") -> int:
	return int(view(snapshot,token).stage)

static func count_today(snapshot:Dictionary,token:String="") -> int:
	return int(view(snapshot,token).count)

static func total(snapshot:Dictionary,token:String="") -> int:
	return int(view(snapshot,token).total)

static func step_at(at_stage:int) -> String:
	var at:=clampi(at_stage,0,LAST)
	if at==0:return "load"
	return "unload" if at==LAST else "push"

static func next_step(snapshot:Dictionary,token:String="") -> String:
	return step_at(stage(snapshot,token))

static func cart_cell(at_stage:int) -> Vector2i:
	return STOPS[clampi(at_stage,1,LAST)-1]

static func preferred_interaction(snapshot:Dictionary,position:Vector2,closest:String,points:Dictionary) -> String:
	var at:=stage(snapshot)
	if at<=0 or not closest.begins_with("mine:"):return closest
	var center:=Vector2(cart_cell(at))+Vector2(0.5,0.5)
	var mineral:Vector2=points[closest]
	if center.distance_squared_to(mineral)<=1.0 and position.distance_squared_to(center)<=REACH*REACH:return ACTION
	return closest

static func pushes_left(at_stage:int) -> int:
	var at:=clampi(at_stage,0,LAST)
	return PUSHES if at==0 else LAST-at

static func stage_text(at_stage:int) -> String:
	var at:=clampi(at_stage,0,LAST)
	if at==0:return STAGE_IDLE
	if at==LAST:return STAGE_END
	return STAGE_MOVING%(at-1)

static func cart_label(snapshot:Dictionary,token:String="") -> String:
	var now:=view(snapshot,token)
	var at:=int(now.stage)
	if at==0:return LABEL_FULL if int(now.count)>=DAILY else LABEL_IDLE
	if at==LAST:return LABEL_END
	return LABEL_PUSH%(at-1)

## `person` is the player's record (only "coins" is read); anything else skips the purse check.
static func step_block(snapshot:Dictionary,step:String,person:Variant,token:String="") -> String:
	if step not in STEP_IDS:return BAD_EXTRA
	var now:=view(snapshot,token)
	return _step_problem(int(now.stage),int(now.count),step,person)

static func _step_problem(at_stage:int,done_today:int,step:String,person:Variant) -> String:
	match step:
		"load":
			if at_stage>0:return LOADED
			if done_today>=DAILY:return DAILY_DONE
		"push":
			if at_stage==0:return NEED_LOAD
			if at_stage>=LAST:return AT_END
		"unload":
			if at_stage==0:return NEED_LOAD
			if at_stage<LAST:return NOT_THERE
			if person is Dictionary and _number(person.get("coins"))>LIMIT-PAY:return PURSE_FULL
	return ""

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
	if extra not in STEP_IDS:return _fail(BAD_EXTRA)
	if state.has(STATE_KEY):
		var whole:Variant=state[STATE_KEY]
		if not whole is Dictionary or whole.size()!=1 or not whole.get("players") is Dictionary:return _fail(BAD_EXTRA)
		if whole.players.has(token) and not _record_ok(whole.players[token]):return _fail(BAD_EXTRA)
	var own:=_record(state,token)
	if own.is_empty():own=fresh_record()
	var at_stage:=int(own.stage)
	var cart:=cart_cell(at_stage)
	if p!=cart:return _fail(WRONG_CELL)
	if _distance(person,cart)>REACH:return _fail(TOO_FAR)
	if not (person.get("coins") is int or person.get("coins") is float):return _fail(NO_PLAYER)
	var now_day:=today(state)
	var done_today:=int(own.count) if int(own.day)==now_day else 0
	var block:=_step_problem(at_stage,done_today,extra,person)
	if not block.is_empty():return _fail(block)
	var message:=""
	match extra:
		"load":
			own.stage=1
			message=LOAD_OK
		"push":
			own.stage=at_stage+1
			message=PUSH_LAST if int(own.stage)==LAST else PUSH_OK%[at_stage,LAST-int(own.stage)]
		_:
			own.stage=0
			own.day=now_day
			own.count=mini(done_today+1,DAILY) # 存檔被改成「今天已滿又有一車在路上」時也不會寫出超過上限的車數
			own.total=mini(int(own.total)+1,LIMIT)
			person.coins=int(person.coins)+PAY
			message=UNLOAD_OK%[PAY,int(own.count)]
	if not state.has(STATE_KEY):state[STATE_KEY]={"players":{}}
	state[STATE_KEY].players[token]=own
	return {"ok":true,"message":message}

# ------------------------------------------------------------------ schema --

static func _whole(value:Variant,minimum:float,maximum:float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum and floorf(float(value))==float(value)

## Runtime shape check of one player's record (full consistency is valid()'s job).
static func _record_ok(own:Variant) -> bool:
	if not own is Dictionary or own.size()!=RECORD_KEYS.size():return false
	for field:String in RECORD_KEYS:
		if not own.has(field):return false
	return _whole(own.stage,0,LAST) and _whole(own.day,0,LIMIT) and _whole(own.count,0,DAILY) and _whole(own.total,0,LIMIT)

## state.ore_route (optional). Exactly {"players":{token:record}}; every token a known
## player; record keys exact; stage 0..LAST; day 0..today; count 0..DAILY; total 0..LIMIT;
## total==0 <=> day==0 <=> count==0 (nothing delivered yet); count<=total.
## Normalises JSON floats to int on success.
static func valid(s:Dictionary) -> bool:
	if not s.has(STATE_KEY):return true
	var whole:Variant=s[STATE_KEY]
	if not whole is Dictionary or whole.size()!=1 or not whole.get("players") is Dictionary:return false
	var players:Variant=s.get("players")
	if not players is Dictionary:return false
	var now_day:=today(s)
	for token in whole.players:
		if not token is String or not players.has(token):return false
		var own:Variant=whole.players[token]
		if not _record_ok(own):return false
		if int(own.day)>now_day:return false
		var none:=int(own.total)==0
		if none!=(int(own.day)==0) or none!=(int(own.count)==0):return false
		if int(own.count)>int(own.total):return false
	for token in whole.players:
		var own:Dictionary=whole.players[token]
		for field:String in RECORD_KEYS:own[field]=int(own[field])
	return true
