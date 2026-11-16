extends RefCounted
## 規劃書第 40 章金瓜石初訪「在河邊體驗淘砂金」：金瓜石山城西側水邊的淘砂處，任何到了金瓜石的
## 島民都能玩（不需要強化石鎬、不需要先認識波波、不需要升降台）。一盤分六步：
##   舀砂 scoop → 揀石礫 sift → 搖盤 swirl ×3 → 揀金砂 pick
## 淘完一盤，背包 +1 含金礦料（gold_ore，既有物品；三份可以拿去波波的整理桌整理礦樣）。
## 每人每個世界日最多淘 DAILY（3）盤。沒做完的一盤會留著（離開、隔天、重登都還在）。
##
## 淘砂的步驟、每日盤數與收穫為遊戲設計（DISCLAIMER），非史料；這個模組沒有任何史實敘述
## （規劃書列的歷史頁要等來源查證後另做）。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；只看 state.time（WEATHER 曆法）。失敗時 state
## 完全不變（先檢查完全部條件，最後才寫入）。不 preload World（避免循環）。
##
## ── 世界紀錄 state.gold_panning（可省略；第一次成功舀砂才寫入，舊存檔不需遷移，不升版）
##   {"players":{token:{"stage":int,   # 0..5＝下一步是 STEPS[stage]；0＝盤子是空的
##                      "day":int,     # 最近一次淘完一盤的世界日；還沒淘完過時 0
##                      "count":int,   # day 那天淘完的盤數（1..DAILY）；還沒淘完過時 0
##                      "total":int}}} # 累計淘完的盤數
##   只在伺服器；公開快照不含這個鍵（Session 只把本人的 view() 放進 snapshot.own_gold_panning）。
##
## ── 地點：SITE (5,26) 是山城西岸外的一格水面（不能走、不能蓋），人站在岸上 REACH=3.2 以內。
##
## ── 動作 gold_pan（World._apply 在 JINGUASHI_REVISIT 之後、一般距離檢查之前轉給 apply()）
##   p＝SITE，extra＝"scoop"／"sift"／"swirl"／"pick"。
##   檢查順序：BAD_EXTRA（不是本模組的動作）→ NO_PLAYER → WRONG_REGION → BAD_EXTRA（extra 不是
##     四種之一，或紀錄壞掉）→ WRONG_CELL → TOO_FAR → step_block()：
##     scoop：HAS_SAND（盤裡還有砂）→ DAILY_DONE
##     sift ：NEED_SCOOP → SIFTED（已揀過）
##     swirl：NEED_SCOOP → NEED_SIFT → SWIRLED（已搖完三次）
##     pick ：NEED_SCOOP → NOT_YET（還沒搖完）→ BAG_FULL
##   成功訊息：SCOOP_OK、SIFT_OK、SWIRL_OK%剩下次數／SWIRL_LAST、PICK_OK%今天第幾盤。
##
## ── 介面用的純函式（snapshot 可以是伺服器 state 或用戶端快照；token 只在伺服器 state 有用，
##    用戶端快照讀 snapshot.own_gold_panning）
##   view(snapshot,token="") -> {"stage","count","total"}   # count＝「今天」已淘完的盤數
##   stage(snapshot,token="") / count_today(snapshot,token="") / total(snapshot,token="") -> int
##   today(snapshot) -> int
##   next_step(snapshot,token="") -> String        # STEPS[stage]
##   swirls_left(stage) -> int                     # 還要搖幾次（0..3）
##   step_block(snapshot,step,inventory,token="") -> String   # 不能做這一步的原因（不看位置）；可以時 ""
##   stage_text(stage) -> String                   # 盤裡現在的樣子
##   apply(state,token,action,p,extra,in_jinguashi) -> {"ok","message"}
##   valid(s) -> bool                              # 存檔檢查（state.gold_panning）

const WEATHER=preload("res://scripts/weather.gd")

const STATE_KEY:="gold_panning"
const OWN_KEY:="own_gold_panning"
const REGION:="jinguashi"
const ACTION:="gold_pan"
const ACTIONS:=[ACTION]
const SITE:=Vector2i(5,26)
const REACH:=3.2
const DAILY:=3
const ITEM:="gold_ore"
const ITEM_NAME:="含金礦料"
const LIMIT:=1000000000
const STEPS:=["scoop","sift","swirl","swirl","swirl","pick"]
const STEP_IDS:=["scoop","sift","swirl","pick"]
const STEP_NAMES:={"scoop":"舀砂","sift":"揀石礫","swirl":"搖盤","pick":"揀金砂"}
const RECORD_KEYS:=["count","day","stage","total"]
const TITLE:="金瓜石・河邊淘砂金"
const SITE_NAME:="淘砂處"
const BLURB:="舀一盤河砂，揀掉石礫，在水裡搖三次把輕的砂洗掉，盤底剩下的就是比較重的金砂。"
const DISCLAIMER:="淘砂的步驟、每日盤數與收穫為遊戲設計，非史料。"
const STAGE_TEXT:=[
	"盤子是空的。",
	"盤裡是剛舀起來的河砂，上面蓋著大石礫。",
	"石礫揀掉了，盤裡是滿滿的砂。",
	"洗掉一層砂，盤裡的砂少了一些。",
	"又洗掉一層，砂只剩薄薄一層。",
	"盤底只剩黑砂，裡面有一點金光。",
]

const NO_PLAYER:="請重新加入世界再淘砂。"
const WRONG_REGION:="淘砂處在金瓜石山城西側的水邊，請先到金瓜石。"
const BAD_EXTRA:="請重新操作淘砂盤。"
const WRONG_CELL:="請到金瓜石山城西側水邊的淘砂處。"
const TOO_FAR:="再靠近水邊的淘砂處一點。"
const HAS_SAND:="盤裡還有砂，先把這一盤淘完。"
const DAILY_DONE:="今天已經淘了 3 盤，淘砂盤留給別人用，明天再來。"
const NEED_SCOOP:="盤子是空的，先舀一盤河砂。"
const SIFTED:="石礫已經揀乾淨了，接著搖盤。"
const NEED_SIFT:="大石礫還在盤裡，先把石礫揀掉再搖。"
const SWIRLED:="砂已經洗得差不多了，再搖金砂也會流走，把金砂揀起來吧。"
const NOT_YET:="盤裡的砂還太多，看不到金光，再淘一淘。"
const BAG_FULL:="背包裡的含金礦料已經放不下了，金砂先留在盤裡。"
const SCOOP_OK:="舀起一盤河砂。先把上面的大石礫揀掉。"
const SIFT_OK:="石礫揀掉了。把盤子浸在水裡搖一搖，讓輕的砂流走。"
const SWIRL_OK:="洗掉一層砂（還要搖 %d 次）。"
const SWIRL_LAST:="盤底只剩黑砂，裡面有一點金光！把金砂揀起來。"
const PICK_OK:="揀出一份含金礦料（今天第 %d／3 盤）。"

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
			return {"stage":clampi(_number(sent.get("stage")),0,STEPS.size()-1),"count":clampi(_number(sent.get("count")),0,DAILY),"total":clampi(_number(sent.get("total")),0,LIMIT)}
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

static func next_step(snapshot:Dictionary,token:String="") -> String:
	return str(STEPS[stage(snapshot,token)])

static func swirls_left(at_stage:int) -> int:
	return clampi(STEPS.size()-1-at_stage,0,3) if at_stage>=2 else (3 if at_stage==1 else 0)

static func stage_text(at_stage:int) -> String:
	return str(STAGE_TEXT[clampi(at_stage,0,STAGE_TEXT.size()-1)])

static func step_block(snapshot:Dictionary,step:String,inventory:Variant,token:String="") -> String:
	if step not in STEP_IDS:return BAD_EXTRA
	var now:=view(snapshot,token)
	return _step_problem(int(now.stage),int(now.count),step,inventory)

static func _step_problem(at_stage:int,done_today:int,step:String,inventory:Variant) -> String:
	var expected:=str(STEPS[at_stage])
	match step:
		"scoop":
			if at_stage>0:return HAS_SAND
			if done_today>=DAILY:return DAILY_DONE
		"sift":
			if at_stage==0:return NEED_SCOOP
			if expected!="sift":return SIFTED
		"swirl":
			if at_stage==0:return NEED_SCOOP
			if expected=="sift":return NEED_SIFT
			if expected!="swirl":return SWIRLED
		"pick":
			if at_stage==0:return NEED_SCOOP
			if expected!="pick":return NOT_YET
			if inventory is Dictionary and int(inventory.get(ITEM,0))>LIMIT-1:return BAG_FULL
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
	if p!=SITE:return _fail(WRONG_CELL)
	if _distance(person,SITE)>REACH:return _fail(TOO_FAR)
	if not person.get("inventory") is Dictionary:return _fail(NO_PLAYER)
	var inv:Dictionary=person.inventory
	var own:=_record(state,token)
	if own.is_empty():own=fresh_record()
	var now_day:=today(state)
	var at_stage:=int(own.stage)
	var done_today:=int(own.count) if int(own.day)==now_day else 0
	var block:=_step_problem(at_stage,done_today,extra,inv)
	if not block.is_empty():return _fail(block)
	var message:=""
	if extra=="pick":
		own.stage=0
		own.day=now_day
		own.count=mini(done_today+1,DAILY) # 存檔被改成「今天已滿又有一盤在淘」時也不會寫出超過上限的盤數
		own.total=mini(int(own.total)+1,LIMIT)
		inv[ITEM]=int(inv.get(ITEM,0))+1
		message=PICK_OK%int(own.count)
	else:
		own.stage=at_stage+1
		match extra:
			"scoop":message=SCOOP_OK
			"sift":message=SIFT_OK
			_:message=SWIRL_LAST if str(STEPS[int(own.stage)])=="pick" else SWIRL_OK%swirls_left(int(own.stage))
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
	return _whole(own.stage,0,STEPS.size()-1) and _whole(own.day,0,LIMIT) and _whole(own.count,0,DAILY) and _whole(own.total,0,LIMIT)

## state.gold_panning (optional). Exactly {"players":{token:record}}; every token a known
## player; record keys exact; stage 0..5; day 0..today; count 0..DAILY; total 0..LIMIT;
## total==0 <=> day==0 <=> count==0 (nothing finished yet); count<=total.
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
