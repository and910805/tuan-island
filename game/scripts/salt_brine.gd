extends RefCounted
## 規劃書第 40 章臺南北門列「用儲滷槽和水車安排批次」：合作社工寮旁的「儲滷槽」。
## 自己照顧的鹽田區（或輪班中的學徒區）裝了水車，就能在儲滷槽旁請水車把鹽田裡曬到一半的
## 滷水抽進槽裡（收滷），之後再放回自己的鹽田（放滷）。下雨會把鹽田裡的滷水沖淡
## （SaltPan.RATES.rainy<0），槽裡的滷水不受天氣影響：下雨前先收滷、雨停再放回，
## 進度就不會白費；也可以把兩方鹽田的滷水集中到一方，先趕出一批鹽。
##
## 儲滷槽與收滷／放滷是遊戲裡的原創安排（DISCLAIMER），非史料；沒有新增北門、井仔腳的史實敘述。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；失敗時 state 完全不變（先檢查完全部條件才寫入）。
## 只在鹽田的「轉換點」寫入 pan.p／pan.t（與 SaltPan 的惰性時間模型相同）；鹽田一直維持
## "brine"，不改 pan.s／pan.f，所以水車、收鹽台與 SaltPan.step 的行為不變。
##
## ── 單位
##   1 桶 = BUCKET(48) 份曬鹽進度；一方鹽田從海水曬到成鹽是 SaltPan.NEED(480) = 10 桶。
##   槽容量 CAP = 30 桶（三方鹽田的量）。全島共用一座槽、一個水位；不記錄是誰收、誰放。
##   收滷：鹽田目前進度 p（先以 SaltPan.advance 積分到現在）取整桶 k=min(floor(p/48), CAP-level)，
##         k>=1；pan.p=p-48k、pan.t=now、level+=k。任何天氣都可以（下雨天正是要搶收）。
##   放滷：k=min(level, floor((NEED-1-p)/48))，k>=1；pan.p=p+48k、pan.t=now、level-=k。
##         下雨天不能放（會被沖淡）。鹽田要已經引了海水（"brine"）；空的先引海水、
##         已結成鹽的直接收鹽。放滷最多放到差一點結晶（p<=NEED-1），結晶仍靠日曬。
##   桶數守恆：鹽田少的進度恰等於槽裡多的桶數×48，反之亦然。
##
## ── 前提（檢查順序）
##   BAD_EXTRA（不是本模組的動作）→ NO_PLAYER → WRONG_REGION → LOCKED（三道閘門沒修好）→
##   NOT_READY（本人沒在北門親手收過鹽）→ BAD_EXTRA（紀錄壞掉）→ WRONG_CELL（p 不是 TANK）→
##   TOO_FAR → NO_UNIT（沒有自己的鹽田區、也沒在學徒區輪班）→ NO_WHEEL（那一區沒裝水車）→
##   BAD_PAN（extra 不是 "a"／"b"）→ 鹽田狀態：PAN_EMPTY / PAN_SALT →
##     store：TANK_FULL → THIN%[現有進度換算的十分之幾]
##     pour ：RAIN_POUR → TANK_EMPTY → PAN_RICH
##   成功：STORE_OK%[桶數,水位]（下雨天再接 STORE_RAIN_NOTE）、POUR_OK%[桶數,十分之幾,水位]。
##
## ── 動作（World._apply 在 SALT_REVISIT 之後、北門的 _salt_allowed 拒絕之前轉入）
##   salt_brine_store  p＝TANK，extra＝"a" 或 "b"（自己那一區的西側／東側鹽田）
##   salt_brine_pour   p＝TANK，extra＝"a" 或 "b"
##
## ── 世界紀錄 state.salt_brine（可省略；第一次成功收滷才寫入，舊存檔不需遷移，不升版）
##   {"level":int}   # 0..CAP 桶
##   公開快照 snapshot.salt_brine = {"level":int}（沒紀錄時沒有這個鍵）；沒有 token。
##
## ── 介面用的純函式（snapshot 可以是伺服器 state 或用戶端快照；token 只在伺服器 state 有用，
##    用戶端快照用 salt_pan.repaired、salt_pan.own.record.raked、salt_pan.own.unit、salt_pan.pans）
##   unlocked(snapshot) / player_ready(snapshot,token="") / level(snapshot) -> int
##   unit(snapshot,token="") -> {"index":int(-1 沒有),"kind":"lot"|"apprentice"|"","wheel":bool}
##   pan_ids(snapshot,token="") -> Array[int]（兩個；沒有鹽田區時 []）
##   pan_progress(snapshot,pan_id) -> {"s":"empty"|"brine"|"salt","p":float,"tenths":int}
##   rainy_now(snapshot) -> bool
##   rows(snapshot,token="") -> Array[{"id":"a"|"b","pan":int,"s","tenths","store":int,"pour":int,
##       "store_block":String,"pour_block":String}]   # store／pour＝現在按下去會移動的桶數
##   common_block(snapshot,token="") -> String   # LOCKED / NOT_READY / NO_UNIT / NO_WHEEL；可以時 ""
##   store_block(snapshot,side,token="") / pour_block(snapshot,side,token="") -> String（不看位置）
##   public(state) -> Dictionary / apply(state,token,action,p,extra,region) / valid(s) -> bool
##   TANK（槽的格子，擋路；SaltPan.BRINE_TANK 相同）、TANK_STAND（測試過的站位）

const SaltPan=preload("res://scripts/salt_pan.gd")

const STATE_KEY:="salt_brine"
const REGION:="beimen"
const TANK:=Vector2i(48,14)          # = SaltPan.BRINE_TANK（工寮東側）
const TANK_STAND:=Vector2(48.5,15.5)
const STORE_ACTION:="salt_brine_store"
const POUR_ACTION:="salt_brine_pour"
const ACTIONS:=[STORE_ACTION,POUR_ACTION]
const SIDES:=["a","b"]
const SIDE_NAMES:={"a":"西側鹽田","b":"東側鹽田"}
const REACH:=3.2
const BUCKET:=48.0
const CAP:=30
const PAN_BUCKETS:=10
const NAME:="儲滷槽"
const TITLE:="北門合作鹽田・儲滷槽"
const DISCLAIMER:="儲滷槽的收滷與放滷是遊戲裡的原創安排，非史料。"
const BLURB:="下雨會把鹽田裡的滷水沖淡，槽裡的不會。下雨前請水車把滷水抽進槽裡，雨停再放回鹽田；也可以把滷水集中到一方鹽田，先趕出一批鹽。"

const NO_PLAYER:="請重新加入世界再使用儲滷槽。"
const WRONG_REGION:="儲滷槽在北門合作鹽田的工寮旁。"
const LOCKED:="北門合作鹽田的三道閘門修好之後，儲滷槽才有滷水可以存。"
const NOT_READY:="先在北門親手收一次鹽，阿曬才會讓你用儲滷槽。"
const WRONG_CELL:="請到合作社工寮旁的儲滷槽。"
const TOO_FAR:="再靠近一點。"
const BAD_EXTRA:="請重新操作儲滷槽。"
const NO_UNIT:="儲滷槽靠水車抽滷水：先認領一塊鹽田區（或在學徒區輪班）並裝上水車。保留手作池不接儲滷槽。"
const NO_WHEEL:="你的鹽田區還沒裝水車，抽不動滷水；先裝好鹽田水車組。"
const BAD_PAN:="請選西側或東側的鹽田。"
const PAN_EMPTY:="這方鹽田是空的，先引海水。"
const PAN_SALT:="這方鹽田已經結成鹽了，直接收鹽就好。"
const TANK_FULL:="儲滷槽已經滿了（30／30 桶），先把滷水放回鹽田。"
const THIN:="這方鹽田的滷水還太淡（曬了約 %d 成），抽不滿一桶。"
const RAIN_POUR:="下雨天先不放滷，放回鹽田會被雨水沖淡；雨停再來。"
const TANK_EMPTY:="儲滷槽是空的，沒有滷水可以放。"
const PAN_RICH:="這方鹽田的滷水已經快結晶了，不用再加。"
const STORE_OK:="水車把 %d 桶滷水抽進儲滷槽。（槽裡 %d／30 桶）"
const STORE_RAIN_NOTE:="槽裡的滷水不怕雨，雨停再放回鹽田。"
const POUR_OK:="放回 %d 桶滷水，這方鹽田現在約 %d 成。（槽裡 %d／30 桶）"

# ------------------------------------------------------------------ views --

static func _number(v:Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func _salt(snapshot:Dictionary) -> Dictionary:
	var salt:Variant=snapshot.get("salt_pan")
	return salt if salt is Dictionary else {}

static func _server(salt:Dictionary) -> bool:
	return salt.has("repaired_at")

static func unlocked(snapshot:Dictionary) -> bool:
	var salt:=_salt(snapshot)
	if _server(salt):
		var at:Variant=salt.repaired_at
		return _number(at) and float(at)>=0.0
	return salt.get("repaired")==true

static func player_ready(snapshot:Dictionary,token:String="") -> bool:
	var salt:=_salt(snapshot)
	var rec:Variant
	if not token.is_empty():
		var players:Variant=salt.get("players")
		rec=players.get(token) if players is Dictionary else null
	else:
		var own:Variant=salt.get("own")
		rec=own.get("record") if own is Dictionary else null
	if not rec is Dictionary:return false
	var raked:Variant=rec.get("raked")
	return _number(raked) and float(raked)>=1.0

static func level(snapshot:Dictionary) -> int:
	var found:Variant=snapshot.get(STATE_KEY)
	if not found is Dictionary:return 0
	var v:Variant=found.get("level",0)
	return clampi(int(v),0,CAP) if _number(v) else 0

static func _now(snapshot:Dictionary) -> float:
	var t:Variant=snapshot.get("time",0.0)
	return clampf(float(t),0.0,SaltPan.MAX_TIME) if _number(t) else 0.0

static func rainy_now(snapshot:Dictionary) -> bool:
	return SaltPan.raining(_now(snapshot))

## The actor's own unit: a claimed private lot (0..7) or the apprentice lot while on shift.
static func unit(snapshot:Dictionary,token:String="") -> Dictionary:
	var none:={"index":-1,"kind":"","wheel":false}
	var salt:=_salt(snapshot)
	if salt.is_empty():return none
	if _server(salt):
		if token.is_empty() or not salt.get("lots") is Array or not salt.get("apprentice") is Dictionary:return none
		for i in salt.lots.size():
			var cfg:Variant=salt.lots[i]
			if cfg is Dictionary and str(cfg.get("owner",""))==token:return {"index":i,"kind":"lot","wheel":cfg.get("wheel")==true}
		if str(salt.apprentice.get("tenant",""))==token:return {"index":SaltPan.APPRENTICE_LOT,"kind":"apprentice","wheel":salt.apprentice.get("wheel")==true}
		return none
	var own:Variant=salt.get("own")
	if not own is Dictionary or not own.get("unit") is Dictionary:return none
	var view:Dictionary=own.unit
	var kind:=str(view.get("kind",""))
	var index:Variant=view.get("index",-1)
	if kind not in ["lot","apprentice"] or not _number(index) or int(index)<0 or int(index)>=SaltPan.LOT_ORIGINS.size() or int(index)==SaltPan.PUBLIC_LOT:return none
	return {"index":int(index),"kind":kind,"wheel":view.get("wheel")==true}

static func pan_ids(snapshot:Dictionary,token:String="") -> Array:
	var own:=unit(snapshot,token)
	if int(own.index)<0:return []
	return [int(own.index)*2,int(own.index)*2+1]

static func _pan(snapshot:Dictionary,pan_id:int) -> Dictionary:
	var pans:Variant=_salt(snapshot).get("pans")
	if not pans is Array or pan_id<0 or pan_id>=pans.size() or not pans[pan_id] is Dictionary:return {}
	return pans[pan_id]

## Progress of one pan integrated to the snapshot's time (does not mutate).
static func pan_progress(snapshot:Dictionary,pan_id:int) -> Dictionary:
	var pan:=_pan(snapshot,pan_id)
	var s:=str(pan.get("s","empty"))
	if s=="salt":return {"s":"salt","p":SaltPan.NEED,"tenths":PAN_BUCKETS}
	if s!="brine" or not _number(pan.get("p")) or not _number(pan.get("t")):return {"s":"empty","p":0.0,"tenths":0}
	var now:=_now(snapshot)
	var cur:=SaltPan.advance(pan.p,pan.t,maxf(now,float(pan.t)))
	if not cur.ok:return {"s":"empty","p":0.0,"tenths":0}
	if cur.salt:return {"s":"salt","p":SaltPan.NEED,"tenths":PAN_BUCKETS}
	return {"s":"brine","p":float(cur.p),"tenths":int(floorf(float(cur.p)/BUCKET))}

static func _store_amount(p:float,held:int) -> int:
	return mini(int(floorf(p/BUCKET)),CAP-held)

static func _pour_amount(p:float,held:int) -> int:
	return mini(held,int(floorf((SaltPan.NEED-1.0-p)/BUCKET)))

static func common_block(snapshot:Dictionary,token:String="") -> String:
	if not unlocked(snapshot):return LOCKED
	if not player_ready(snapshot,token):return NOT_READY
	var own:=unit(snapshot,token)
	if int(own.index)<0:return NO_UNIT
	if not own.wheel:return NO_WHEEL
	return ""

static func _side_pan(snapshot:Dictionary,side:String,token:String) -> int:
	var ids:=pan_ids(snapshot,token)
	var at:=SIDES.find(side)
	return int(ids[at]) if at>=0 and ids.size()==2 else -1

static func _store_problem(snapshot:Dictionary,pan_id:int) -> String:
	var view:=pan_progress(snapshot,pan_id)
	if view.s=="empty":return PAN_EMPTY
	if view.s=="salt":return PAN_SALT
	if level(snapshot)>=CAP:return TANK_FULL
	if _store_amount(float(view.p),level(snapshot))<1:return THIN%int(floorf(float(view.p)/BUCKET))
	return ""

static func _pour_problem(snapshot:Dictionary,pan_id:int) -> String:
	var view:=pan_progress(snapshot,pan_id)
	if view.s=="empty":return PAN_EMPTY
	if view.s=="salt":return PAN_SALT
	if rainy_now(snapshot):return RAIN_POUR
	if level(snapshot)<1:return TANK_EMPTY
	if _pour_amount(float(view.p),level(snapshot))<1:return PAN_RICH
	return ""

static func store_block(snapshot:Dictionary,side:String,token:String="") -> String:
	var common:=common_block(snapshot,token)
	if not common.is_empty():return common
	var pan_id:=_side_pan(snapshot,side,token)
	if pan_id<0:return BAD_PAN
	return _store_problem(snapshot,pan_id)

static func pour_block(snapshot:Dictionary,side:String,token:String="") -> String:
	var common:=common_block(snapshot,token)
	if not common.is_empty():return common
	var pan_id:=_side_pan(snapshot,side,token)
	if pan_id<0:return BAD_PAN
	return _pour_problem(snapshot,pan_id)

static func rows(snapshot:Dictionary,token:String="") -> Array:
	var out:=[]
	var ids:=pan_ids(snapshot,token)
	if ids.size()!=2:return out
	var held:=level(snapshot)
	for at in SIDES.size():
		var side:String=SIDES[at]
		var view:=pan_progress(snapshot,int(ids[at]))
		var store_why:=store_block(snapshot,side,token)
		var pour_why:=pour_block(snapshot,side,token)
		out.append({"id":side,"name":str(SIDE_NAMES[side]),"pan":int(ids[at]),"s":str(view.s),"tenths":int(view.tenths),
			"store":_store_amount(float(view.p),held) if store_why.is_empty() else 0,
			"pour":_pour_amount(float(view.p),held) if pour_why.is_empty() else 0,
			"store_block":store_why,"pour_block":pour_why})
	return out

static func public(state:Dictionary) -> Dictionary:
	if not state.get(STATE_KEY) is Dictionary:return {}
	return {"level":level(state)}

# ------------------------------------------------------------------ action --

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

static func _shape_ok(own:Variant) -> bool:
	return own is Dictionary and own.size()==1 and _number(own.get("level")) and float(own.level)>=0.0 and float(own.level)<=CAP and floorf(float(own.level))==float(own.level)

## World passes region (the actor's current region id) after SaltPan.step has run up to
## state.time. Every check runs before any write, so a failure leaves the state unchanged.
static func apply(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,region:String) -> Dictionary:
	if action not in ACTIONS:return _fail(BAD_EXTRA)
	var people:Variant=state.get("players",{})
	if not people is Dictionary or not people.get(token) is Dictionary:return _fail(NO_PLAYER)
	var person:Dictionary=people[token]
	if region!=REGION:return _fail(WRONG_REGION)
	if not unlocked(state):return _fail(LOCKED)
	if not player_ready(state,token):return _fail(NOT_READY)
	if state.has(STATE_KEY) and not _shape_ok(state[STATE_KEY]):return _fail(BAD_EXTRA)
	if not _number(state.get("time")) or float(state.time)<0.0 or float(state.time)>SaltPan.MAX_TIME:return _fail(BAD_EXTRA)
	if p!=TANK:return _fail(WRONG_CELL)
	if Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(TANK)+Vector2(0.5,0.5))>REACH:return _fail(TOO_FAR)
	var own:=unit(state,token)
	if int(own.index)<0:return _fail(NO_UNIT)
	if not own.wheel:return _fail(NO_WHEEL)
	if extra not in SIDES:return _fail(BAD_PAN)
	var pan_id:=_side_pan(state,extra,token)
	var pan:=_pan(state,pan_id)
	if pan.is_empty():return _fail(BAD_EXTRA)
	var now:=float(state.time)
	if pan.get("s")=="brine" and (not _number(pan.get("t")) or now<float(pan.t)):return _fail(BAD_EXTRA)
	var problem:=_store_problem(state,pan_id) if action==STORE_ACTION else _pour_problem(state,pan_id)
	if not problem.is_empty():return _fail(problem)
	var view:=pan_progress(state,pan_id)
	var held:=level(state)
	var cur:=float(view.p)
	if action==STORE_ACTION:
		var k:=_store_amount(cur,held)
		pan.p=maxf(0.0,cur-BUCKET*k)
		pan.t=now
		state[STATE_KEY]={"level":held+k}
		var message:=STORE_OK%[k,held+k]
		if rainy_now(state):message+=STORE_RAIN_NOTE
		return {"ok":true,"message":message}
	var n:=_pour_amount(cur,held)
	var after:=minf(cur+BUCKET*n,SaltPan.NEED-1.0)
	pan.p=after
	pan.t=now
	state[STATE_KEY]={"level":held-n}
	return {"ok":true,"message":POUR_OK%[n,int(floorf(after/BUCKET)),held-n]}

# ------------------------------------------------------------------ schema --

## state.salt_brine (optional): exactly {"level": whole 0..CAP}; the Beimen gates must be
## repaired and at least one known player must have raked by hand (only such players can
## write it). Must run after SaltPan.valid. Normalises a JSON float to int on success.
static func valid(s:Dictionary) -> bool:
	if not s.has(STATE_KEY):return true
	var own:Variant=s[STATE_KEY]
	if not _shape_ok(own):return false
	if not unlocked(s):return false
	var players:Variant=s.get("players")
	if not players is Dictionary:return false
	var anyone:=false
	for token in players:
		if player_ready(s,str(token)):anyone=true
	if not anyone:return false
	own.level=int(own.level)
	return true
