extends RefCounted
## 第四章切片「海邊的飯香」：北門鹽風合作鹽田規則核心（W1）。
## Pure static rules, data and validation. No IO, no wall clock, no random.
## Must NOT preload world.gd / regions.gd / transit.gd / session.gd (they
## preload this file). Authority: work/salt/lead/contract-corrections.md over
## work/salt/implementation-contract.json. This is a chapter-4 increment only.
##
## Time model: every pan stores only {s,p,t,f}; progress is integrated lazily
## from (p,t) with advance(), and the state is written only at transitions
## (crystallise, flood/refill, rake/collect). step() is an exact event
## simulation, so one long step equals many short steps bit for bit.

const FlowerNursery=preload("res://scripts/flower_nursery.gd")
const WEATHER=preload("res://scripts/weather.gd")

const SAVE_VERSION:=26
const REGION:="beimen"
const HOME:="home"
const LABEL:="北門・鹽風合作鹽田"
## 設計選擇（非歷史產量）：晴天 480 秒成鹽、多雲 960 秒。
const NEED:=480.0
const YIELD:=3
const CAP_MIN:=3
const CAP_MAX:=999
const CAP_DEFAULT:=60
const LIMIT:=1000000000
const LOT_COUNT:=8
const PUBLIC_LOT:=8
const APPRENTICE_LOT:=9
const PAN_COUNT:=20
## 3 game days. A shift always ends (graduation, expiry or release); kits that
## do not fit the inventory go to the owner's escrow (`kit_box`), never lost.
const SHIFT_SECONDS:=4320.0
## World seconds the head of the apprentice waiting list may take a free shift
## before it passes on (first miss: back of the list; second miss: removed).
## World time only advances while someone is online, so this pauses with it.
const OFFER_SECONDS:=720.0
const MAX_TIME:=1.0e12
const MAX_EVENTS:=4096
const ADVANCE_MAX_SEGMENTS:=16
const RATES:={"sunny":1.0,"cloudy":0.5,"rainy":-0.25,"indoor":0.0}
const GATE_NEEDS_EACH:={"plank":6,"resin":1,"stone":4}
const GATE_MATERIALS:=["plank","resin","stone"]
const GATE_ROWS:=[13,20,27]
## Lots 0..7 private, 8 public manual pool (保留手作池), 9 apprentice (學徒區).
const LOT_ORIGINS:=[Vector2i(12,13),Vector2i(22,13),Vector2i(32,13),Vector2i(12,20),Vector2i(22,20),Vector2i(32,20),Vector2i(22,27),Vector2i(32,27),Vector2i(12,27),Vector2i(42,20)]
const APPRENTICE_CHEST:=Vector2i(47,23)
const LAND:=Rect2i(6,10,46,32)
const HERITAGE_VIEW:=Rect2i(14,34,22,5)
const HERITAGE_SIGN:=Vector2i(24,33)
const PUBLIC_SIGN:=Vector2i(16,30)
const SHED:=Rect2i(42,13,6,3)
const SALT_WORKER:=Vector2i(44,17)
## 第 40 章儲滷槽（規則在 salt_brine.gd）：工寮東側的一格，擋路。
const BRINE_TANK:=Vector2i(48,14)
const TRANSFER:=Vector2i(48,25)
## Roofed coastal bus shelter (96x64 sprite = 3 tiles wide); collision matches the art.
## The interaction/station cell stays TRANSFER (its west end); arrival (47,25) stays free.
const BUS_SHELTER:=Rect2i(48,25,3,1)
const ARRIVAL:=Vector2(47.5,25.5)
const XIAOLI_HOME:=FlowerNursery.RECEIVER_HOME

const ACTIONS:=["salt_letter","salt_intro","salt_gate_give","salt_flood","salt_rake","salt_claim","salt_release","salt_install","salt_uninstall","salt_auto_cfg","salt_auto_toggle","salt_note","salt_order","salt_report","salt_box_take"]
const HOME_ACTIONS:=["salt_letter","salt_order"]
const ITEMS:={"sea_salt":"海鹽","salt_wheel_kit":"鹽田水車組","salt_rake_kit":"收鹽台組","salt_grilled_fish":"香煎溪魚"}
const KITS:={"wheel":"salt_wheel_kit","rake":"salt_rake_kit"}
const FORWARD_IDS:=["sea_salt","salt_wheel_kit","salt_rake_kit","salt_grilled_fish","beimen","salt_pan"]
## 設計選擇：原料方向為規劃 §14（溪魚、海鹽）；數量、15 秒、產量為設計值。
const RECIPE:={"salt_grilled_fish":{"name":"香煎溪魚","ingredients":{"minnow":1,"sea_salt":1},"time":15.0,"yield":1}}
const CRAFT:={
	"salt_wheel_kit":{"name":"鹽田水車組","ingredients":{"plank":8,"copper_joint":2,"resin":2},"yield":1},
	"salt_rake_kit":{"name":"收鹽台組","ingredients":{"plank":6,"stone":6,"fiber":4,"copper_joint":1},"yield":1},
}
const CRAFT_LOCKED_MESSAGE:="鹽田水車組要先在北門親手收過一次鹽；收鹽台組要先收過一方水車引水的鹽田。"
const SALT_FISH_PRICE:=34
const ORDER:={"sea_salt":4,"salt_grilled_fish":2}
const ORDER_PAY:=120
const REJECT_MESSAGE:="合作鹽田只開放鹽田工作、收鹽箱與轉乘。"
const GATE_EVENT:="北門合作鹽田的三道閘門都修好了"
const RAIN_FLOOD_MESSAGE:="下雨天先不引水，雨停再來。"
const RAKED_MESSAGE:="這方鹽田剛被收完了，可以再引海水。"
const CLAIMED_MESSAGE:="這區剛被認領了，換一區看看吧。"
const FREE_LOT_MESSAGE:="還有空的鹽田區，請先認領自己的鹽田區。"
const BUSY_FORMAT:="學徒區正由另一位島民輪班，最晚約 %d 分鐘後開放；先到保留手作池收鹽吧。"
const CAP_MESSAGE:="存量上限至少要 3 份，收鹽台一次收 3 份鹽。"
const QUEUE_BUSY_FORMAT:="學徒區正由另一位島民輪班，最晚約 %d 分鐘後開放；你排在輪班名單第 %d 位，先到保留手作池收鹽吧。"
const QUEUE_HELD_FORMAT:="學徒區正保留給名單上前一位島民接班，最晚約 %d 分鐘後輪到下一位；你排在輪班名單第 %d 位。"
const OFFER_FORMAT:="學徒區輪到你了，請在約 %d 分鐘內來接班。"
const KIT_ESCROW_NOTE:="背包放不下的機器組已收進合作社收鹽箱，隨時可以來取。"
const PHASES:=["locked","letter","travel","intro","gates","first_salt","claim","wheel","rake","automate","order","report","complete"]
const RECORD:={"letter":false,"intro":false,"raked":0,"wheel_raked":0,"auto_raked":0,"note":false,"order":false,"complete":false}
const ROOT_KEYS:=["players","gates","givers","repaired_at","pans","lots","apprentice","coop_box","kit_box","waitlist"]
const KIT_IDS:=["salt_wheel_kit","salt_rake_kit"]
const PAN_STATES:=["empty","brine","salt"]
const STATUS_IDS:=["unset","off","invalid","owner","full","rain","waiting","running","wheel_only","reserve","manual"]
const STATUS_TEXT:={
	"unset":"收鹽台還沒選收鹽箱。",
	"off":"已暫停：水車與收鹽台都不動，成鹽會留在鹽田裡。",
	"invalid":"收鹽箱不在原位或已換成新箱子；放回原箱或重新選擇。",
	"owner":"這個位置現在是其他島民的私人箱，收鹽台不能使用。",
	"full":"收鹽箱再收一次（3 份）就會超過存量上限，成鹽先留在鹽田裡。",
	"rain":"下雨天水車暫停引水；已經成的鹽照常收進箱子，不會流失。",
	"waiting":"正在曬鹽。",
	"running":"水車與收鹽台運作中。",
	"wheel_only":"水車會自動引水，成鹽請親手來收。",
	"reserve":"這兩方是保留給大家手作的鹽田，不能接水車或收鹽台。",
	"manual":"還沒裝水車：鹽田要親手引海水、親手收鹽。",
}
## Journal replay, one original line per phase (client-side only).
const STORY:={
	"locked":"田尾公共花園開花之後，小栗的攤位會收到一封從臺南沿海寄來的信。",
	"letter":"小栗遞來一封沾著海風的信：「北門的合作鹽田閘門木板爛了，鹽曬不起來，南邊的攤子都在等鹽。」",
	"travel":"從田尾搭花圃接駁，經縱貫線鐵路一路南下，再轉沿海公車，就到北門的鹽風合作鹽田。",
	"intro":"阿曬把斗笠往後推：「海水要靠閘門引進來。三道閘門都換上新木板，鹽田才會醒過來。」",
	"gates":"閘門需要木板、樹脂和石材。大家可以分次帶來，修好一道算一道。",
	"first_salt":"閘門開了。選一方鹽田引海水，晴天曬得最快，下雨就先等等。結成白白的鹽再用耙子收起來。",
	"claim":"阿曬指著一排鹽田：「選一區自己照顧吧。最靠近我們這邊的兩方是保留給大家手作的。鹽田區都有人照顧時，合作社的學徒區可以輪班。」",
	"wheel":"「每天來回提水太累了。」阿曬畫了一張水車的圖，回家的工作台就能做。",
	"rake":"水車引的水曬成鹽了，你親手收過一次。接下來做一座收鹽台，讓鹽自己進箱子。",
	"automate":"在收鹽台旁放一個箱子，選好存量上限再啟用。箱子滿了或被搬走，收鹽台會停下來告訴你；下雨天只有水車暫停。",
	"order":"把海鹽帶回渡口，用銀線溪魚和海鹽做香煎溪魚，交給小栗。",
	"report":"小栗說南邊的攤子收到了。回北門告訴阿曬吧。",
	"complete":"阿曬望向觀景區那片老瓦盤：「機器替我們提水收鹽，我們才有空去看看前人留下的鹽田。」",
}
const NOTE_TEXT:="井仔腳是北門最早的鹽田，1818 年遷至現址；今日保留瓦盤鹽田，讓大家參觀傳統曬鹽的樣貌。觀景區只供觀賞，請別走進去。鹽風合作鹽田與阿曬是遊戲原創。"

# ---------------------------------------------------------------- layout

static func land(p:Vector2i) -> bool:
	return LAND.has_point(p)

static func _channel(p:Vector2i) -> bool:
	for oy:int in GATE_ROWS:
		if Rect2i(8,oy,2,1).has_point(p) or Rect2i(8,oy+2,2,1).has_point(p):return true
	return false

const FISHING_SPOTS := {
	"pier":{"water":Rect2i(52,21,1,3),"label":"碼頭","fish":"moon_squid"},
	"tidepool":{"water":Rect2i(52,35,1,4),"label":"潮池","fish":"gold_shrimp"},
}

static func fishing_water(p:Vector2i) -> String:
	# The named bands extend east into the same water as their map pins.
	for id in FISHING_SPOTS:
		var area:Rect2i=FISHING_SPOTS[id].water
		if p.x>=area.position.x and p.y>=area.position.y and p.y<area.end.y:return id
	return "coast"

static func water(p:Vector2i) -> bool:
	return not land(p) or _channel(p)

static func gate_at(p:Vector2i) -> int:
	for g in GATE_ROWS.size():
		if Rect2i(8,int(GATE_ROWS[g])+1,2,1).has_point(p):return g
	return -1

static func _origin(lot:int) -> Vector2i:
	return LOT_ORIGINS[lot]

static func _machine_lot(lot:int) -> bool:
	return (lot>=0 and lot<LOT_COUNT) or lot==APPRENTICE_LOT

static func wheel_socket(lot:int) -> Rect2i:
	if not _machine_lot(lot):return Rect2i()
	var o:=_origin(lot)
	return Rect2i(o.x-1,o.y+1,2,1)

static func rake_socket(lot:int) -> Rect2i:
	if not _machine_lot(lot):return Rect2i()
	var o:=_origin(lot)
	return Rect2i(o.x+3,o.y+3,2,1)

static func chest_sockets(lot:int) -> Array[Vector2i]:
	var out:Array[Vector2i]=[]
	if lot<0 or lot>=LOT_COUNT:return out
	var o:=_origin(lot)
	out.append(Vector2i(o.x+2,o.y+3))
	out.append(Vector2i(o.x+5,o.y+3))
	return out

static func pan_rect(i:int) -> Rect2i:
	if i<0 or i>=PAN_COUNT:return Rect2i()
	var o:=_origin(i/2)
	return Rect2i(o.x+1+(i%2)*4,o.y,3,3)

static func lot_of_pan(i:int) -> int:
	return i/2 if i>=0 and i<PAN_COUNT else -1

static func pan_at(p:Vector2i) -> int:
	for i in PAN_COUNT:
		if pan_rect(i).has_point(p):return i
	return -1

static func chest_socket_lot(p:Vector2i) -> int:
	for lot in LOT_COUNT:
		if p in chest_sockets(lot):return lot
	return -1

static func _divider(lot:int) -> Rect2i:
	var o:=_origin(lot)
	return Rect2i(o.x+4,o.y,1,3)

## Any cell of a lot: pans, the walkable divider, machine sockets, the lot's
## chest sockets (private) or the cooperative chest (apprentice).
static func lot_at(p:Vector2i) -> int:
	var pan:=pan_at(p)
	if pan>=0:return lot_of_pan(pan)
	for lot in LOT_ORIGINS.size():
		if _divider(lot).has_point(p):return lot
		if _machine_lot(lot) and (wheel_socket(lot).has_point(p) or rake_socket(lot).has_point(p)):return lot
	var socket:=chest_socket_lot(p)
	if socket>=0:return socket
	if p==APPRENTICE_CHEST:return APPRENTICE_LOT
	return -1

static func _socket_kind(p:Vector2i) -> Array:
	for lot in LOT_ORIGINS.size():
		if not _machine_lot(lot):continue
		if wheel_socket(lot).has_point(p):return ["wheel",lot]
		if rake_socket(lot).has_point(p):return ["rake",lot]
	return ["",-1]

static func site_at(p:Vector2i) -> String:
	var g:=gate_at(p)
	if g>=0:return "gate:%d"%g
	var pan:=pan_at(p)
	if pan>=0:return "pan:%d"%pan
	var socket:=_socket_kind(p)
	if socket[0]!="":return "%s:%d"%[socket[0],socket[1]]
	if p==SALT_WORKER:return "worker"
	if p==HERITAGE_SIGN:return "heritage"
	if p==APPRENTICE_CHEST:return "coop_chest"
	if p==PUBLIC_SIGN:return "public_sign"
	if p==TRANSFER:return "transfer"
	if p==BRINE_TANK:return "brine_tank"
	return ""

static func blocked(p:Vector2i) -> bool:
	if not land(p) or _channel(p) or gate_at(p)>=0 or pan_at(p)>=0:return true
	if _socket_kind(p)[0]!="":return true
	if p in [PUBLIC_SIGN,HERITAGE_SIGN,SALT_WORKER,TRANSFER,APPRENTICE_CHEST,BRINE_TANK]:return true
	return HERITAGE_VIEW.has_point(p) or SHED.has_point(p) or BUS_SHELTER.has_point(p)

## Every beimen cell except the 16 private chest-socket cells (no building).
static func protected(p:Vector2i) -> bool:
	return chest_socket_lot(p)<0

# ---------------------------------------------------------------- time

## ctx is reserved for seasons (T048); today only the weather id matters.
static func evaporation_rate(weather_id:String,ctx:Dictionary={}) -> float:
	var _unused:=ctx
	return float(RATES.get(weather_id,0.0))

static func raining(now:float) -> bool:
	return WEATHER.outdoor_id(WEATHER.day_index(now))=="rainy"

## First instant >= x that is not on a rainy day (rain day -> next midnight).
static func first_dry(x:float) -> float:
	var day:=WEATHER.day_index(x)
	if WEATHER.outdoor_id(day)=="rainy":return (day+1.0)*WEATHER.DAY_SECONDS
	return x

## Exact piecewise integration of brine progress over [t0,t1]. A midnight
## belongs to the new day. Returns {ok,p,salt,at}: when salt, `at` is the exact
## crystallisation instant t* (independent of t1). ok:false on invalid input or
## when the segment guard is hit (never happens with the current calendar).
static func advance(p:Variant,t0:Variant,t1:Variant) -> Dictionary:
	if not (_number(p) and _number(t0) and _number(t1)):return {"ok":false,"p":0.0,"salt":false,"at":0.0}
	var start:=float(t0)
	var end:=float(t1)
	var cur:=float(p)
	if start<0.0 or end<start or end>MAX_TIME or cur<0.0 or cur>NEED:return {"ok":false,"p":cur,"salt":false,"at":start}
	if cur>=NEED:return {"ok":true,"p":NEED,"salt":true,"at":start}
	var cursor:=start
	var day:=WEATHER.day_index(start)
	for segment in ADVANCE_MAX_SEGMENTS:
		var boundary:=(day+1.0)*WEATHER.DAY_SECONDS
		var seg_end:=minf(boundary,end)
		var rate:=evaporation_rate(WEATHER.outdoor_id(day))
		if rate>0.0:
			var at:=cursor+(NEED-cur)/rate
			if at<=seg_end:return {"ok":true,"p":NEED,"salt":true,"at":at}
			cur=minf(cur+rate*(seg_end-cursor),NEED)
		elif rate<0.0:
			cur=maxf(0.0,cur+rate*(seg_end-cursor))
		if seg_end>=end:return {"ok":true,"p":cur,"salt":false,"at":end}
		cursor=boundary
		day+=1.0
	return {"ok":false,"p":float(p),"salt":false,"at":start}

## Display view of one pan at `now` (does not mutate).
static func pan_view(pan:Dictionary,now:float) -> Dictionary:
	var s:=str(pan.get("s","empty"))
	var p:=float(pan.get("p",0.0)) if _number(pan.get("p")) else 0.0
	var rain:=raining(now)
	var eta:=-1
	if s=="brine":
		var t:=float(pan.get("t",0.0)) if _number(pan.get("t")) else 0.0
		var cur:=advance(p,t,maxf(now,t))
		if cur.ok and cur.salt:
			s="salt"
			p=NEED
			eta=0
		elif cur.ok:
			p=float(cur.p)
			var future:=advance(p,maxf(now,t),maxf(now,t)+5.0*WEATHER.DAY_SECONDS)
			if future.ok and future.salt:eta=int(ceilf((float(future.at)-maxf(now,t))/60.0))
	elif s=="salt":
		eta=0
	return {"s":s,"ratio":clampf(p/NEED,0.0,1.0),"diluted":s=="brine" and rain,"covered":s=="salt" and rain,"eta_minutes":eta}

static func eta(pan:Dictionary,now:float) -> int:
	return int(pan_view(pan,now).eta_minutes)

# ---------------------------------------------------------------- records

static func fresh_pan() -> Dictionary:
	return {"s":"empty","p":0.0,"t":0.0,"f":""}

static func fresh_lot() -> Dictionary:
	return {"owner":"","wheel":false,"rake":false,"chest":"","box":"","cap":CAP_DEFAULT,"on":false}

static func fresh_apprentice() -> Dictionary:
	return {"tenant":"","since":0.0,"wheel":false,"rake":false,"cap":CAP_DEFAULT,"on":false}

static func fresh() -> Dictionary:
	var gates:Array=[]
	for g in GATE_ROWS.size():gates.append({"plank":0,"resin":0,"stone":0})
	var pans:Array=[]
	for i in PAN_COUNT:pans.append(fresh_pan())
	var lots:Array=[]
	for lot in LOT_COUNT:lots.append(fresh_lot())
	return {"players":{},"gates":gates,"givers":{},"repaired_at":-1.0,"pans":pans,"lots":lots,"apprentice":fresh_apprentice(),"coop_box":{},"kit_box":{},"waitlist":fresh_waitlist()}

## Apprentice waiting list: `order` = [{token, missed:0|1}] in turn order;
## `offer_at` = start of the head's window while the station is free (else 0).
static func fresh_waitlist() -> Dictionary:
	return {"order":[],"offer_at":0.0}

static func fresh_kit_box() -> Dictionary:
	return {"salt_wheel_kit":0,"salt_rake_kit":0}

static func _data(state:Dictionary) -> Dictionary:
	var data=state.get("salt_pan")
	if data is Dictionary and data.get("players") is Dictionary and data.get("pans") is Array and data.get("lots") is Array and data.get("apprentice") is Dictionary and data.get("coop_box") is Dictionary and data.get("gates") is Array and data.get("kit_box") is Dictionary and data.get("waitlist") is Dictionary and data.waitlist.get("order") is Array:return data
	return fresh()

# ---------------------------------------------------------------- waitlist

static func _queue_index(data:Dictionary,token:String) -> int:
	var order:Array=data.waitlist.order
	for i in order.size():
		if order[i] is Dictionary and order[i].get("token")==token:return i
	return -1

## 1-based place in the apprentice waiting list, 0 when not listed.
static func queue_position(state:Dictionary,token:String) -> int:
	if token=="":return 0
	return _queue_index(_data(state),token)+1

## Token offered the free station right now ("" when none).
static func _offer_head(data:Dictionary) -> String:
	if str(data.apprentice.get("tenant",""))!="":return ""
	var order:Array=data.waitlist.order
	if order.is_empty():return ""
	return str(order[0].get("token",""))

## Removes `token` from the list; a new head of a free station gets a fresh
## window from `now`, and an empty list clears the window.
static func _queue_remove(data:Dictionary,token:String,now:float) -> void:
	var i:=_queue_index(data,token)
	if i<0:return
	data.waitlist.order.remove_at(i)
	if data.waitlist.order.is_empty() or str(data.apprentice.tenant)!="":data.waitlist.offer_at=0.0
	elif i==0:data.waitlist.offer_at=now

static func _offer_minutes(data:Dictionary,now:float) -> int:
	var left:=float(data.waitlist.get("offer_at",0.0))+OFFER_SECONDS-now
	return maxi(1,int(ceilf(left/60.0)))

## Owner's escrowed (returned) kits, both ids always present.
static func escrow_of(state:Dictionary,token:String) -> Dictionary:
	var out:=fresh_kit_box()
	var box=_data(state).kit_box.get(token)
	if box is Dictionary:
		for kit:String in KIT_IDS:out[kit]=int(box.get(kit,0))
	return out

static func own_record(state:Dictionary,token:String) -> Dictionary:
	return _data(state).players.get(token,RECORD).duplicate(true)

static func route_open(state:Dictionary,token:String) -> bool:
	return yes(own_record(state,token).get("letter"))

static func unlocked(state:Dictionary,token:String) -> bool:
	return yes(FlowerNursery.own_record(state,token).get("complete"))

static func _visited(player:Variant) -> bool:
	if not player is Dictionary:return false
	var book=player.get("travel_book")
	return book is Dictionary and book.get("visited") is Dictionary and yes(book.visited.get(REGION))

static func repaired(state:Dictionary) -> bool:
	var at=_data(state).get("repaired_at",-1.0)
	return _number(at) and float(at)>=0.0

static func owned_lot(state:Dictionary,token:String) -> int:
	if token=="":return -1
	var lots:Array=_data(state).lots
	for lot in lots.size():
		if lots[lot] is Dictionary and lots[lot].get("owner")==token:return lot
	return -1

static func is_tenant(state:Dictionary,token:String) -> bool:
	return token!="" and _data(state).apprentice.get("tenant")==token

static func free_lots(state:Dictionary) -> int:
	var count:=0
	for lot in _data(state).lots:
		if lot is Dictionary and lot.get("owner")=="":count+=1
	return count

## The unit the player runs machines on: {kind:"lot"|"apprentice"|"", index}.
static func unit_of(state:Dictionary,token:String) -> Dictionary:
	var lot:=owned_lot(state,token)
	if lot>=0:return {"kind":"lot","index":lot}
	if is_tenant(state,token):return {"kind":"apprentice","index":APPRENTICE_LOT}
	return {"kind":"","index":-1}

static func _unit_config(data:Dictionary,unit:int) -> Dictionary:
	if unit==APPRENTICE_LOT:return data.apprentice
	return data.lots[unit]

static func phase(state:Dictionary,token:String) -> String:
	if not unlocked(state,token):return "locked"
	var record:=own_record(state,token)
	if not yes(record.letter):return "letter"
	if not _visited(state.get("players",{}).get(token)):return "travel"
	if not yes(record.intro):return "intro"
	if not repaired(state):return "gates"
	if int(record.raked)==0:return "first_salt"
	if int(record.auto_raked)==0:
		var unit:=unit_of(state,token)
		if unit.kind=="":return "claim"
		var cfg:=_unit_config(_data(state),int(unit.index))
		if not yes(cfg.get("wheel")):return "wheel"
		if not yes(cfg.get("rake")):return "rake"
		return "automate"
	if not yes(record.order):return "order"
	if not yes(record.complete):return "report"
	return "complete"

## Whether the player may hold a shift at all (ignores who holds it now).
static func apprentice_candidate(state:Dictionary,token:String) -> bool:
	if token=="" or not _data(state).players.has(token):return false
	var record:=own_record(state,token)
	if not yes(record.intro) or int(record.raked)<1 or int(record.auto_raked)!=0:return false
	return owned_lot(state,token)<0 and free_lots(state)==0

## Whether the player may take an apprentice shift right now: the station is
## free and either nobody is waiting or the player heads the waiting list.
static func apprentice_eligible(state:Dictionary,token:String) -> bool:
	var data:=_data(state)
	if not apprentice_candidate(state,token):return false
	if data.apprentice.get("tenant")!="":return false
	return data.waitlist.order.is_empty() or _offer_head(data)==token

static func _shift_minutes(data:Dictionary,now:float) -> int:
	var left:=float(data.apprentice.get("since",0.0))+SHIFT_SECONDS-now
	return maxi(1,int(ceilf(left/60.0)))

static func guidance(state:Dictionary,token:String) -> Dictionary:
	var current:=phase(state,token)
	var g:Dictionary
	match current:
		"locked":g={"text":"先讓田尾公共花園開花，完成第三章。","region":"","cell":Vector2i(-1,-1)}
		"letter":g={"text":"回到渡口，向小栗收下從臺南沿海寄來的信。","region":HOME,"cell":XIAOLI_HOME}
		"travel":g={"text":"從田尾的花圃接駁點轉乘南下，到北門的鹽風合作鹽田。","region":REGION,"cell":TRANSFER}
		"intro":g={"text":"到合作社工寮前和阿曬打聲招呼。","region":REGION,"cell":SALT_WORKER}
		"gates":g={"text":"把木板、樹脂和石材捐給海邊的閘門，三道都修好鹽田才能引水。","region":REGION,"cell":_gate_cell(state)}
		"first_salt":g={"text":"到保留手作池引海水，等鹽結成後親手收一次鹽。","region":REGION,"cell":pan_rect(PUBLIC_LOT*2).position}
		"claim":
			if free_lots(state)>0:g={"text":"選一區沒人照顧的鹽田區認領下來。","region":REGION,"cell":_free_lot_cell(state)}
			else:g={"text":"鹽田區都有人照顧了；到合作社學徒區輪班，用自己的水車和收鹽台練習。","region":REGION,"cell":pan_rect(APPRENTICE_LOT*2).position}
		"wheel":g={"text":"回家在工作台做一組鹽田水車組，裝到水車座上。","region":REGION,"cell":wheel_socket(int(unit_of(state,token).index)).position}
		"rake":g={"text":"親手收一方水車引水的鹽田，再做收鹽台組裝到收鹽台座。","region":REGION,"cell":rake_socket(int(unit_of(state,token).index)).position}
		"automate":g={"text":"選好收鹽箱和存量上限，啟用收鹽台，等它自動收一次鹽。","region":REGION,"cell":rake_socket(int(unit_of(state,token).index)).position}
		"order":g={"text":"帶海鹽 4 份和香煎溪魚 2 份回渡口交給小栗。","region":HOME,"cell":XIAOLI_HOME}
		"report":g={"text":"回北門告訴阿曬，南邊的攤子收到鹽了。","region":REGION,"cell":SALT_WORKER}
		_:g={"text":"北門這一段完成了，可以到觀景解說牌看看老瓦盤鹽田。","region":REGION,"cell":HERITAGE_SIGN}
	g.phase=current
	return g

static func _gate_cell(state:Dictionary) -> Vector2i:
	var gates:Array=_data(state).gates
	for g in gates.size():
		if not gate_full(gates[g]):return Vector2i(8,int(GATE_ROWS[g])+1)
	return Vector2i(8,int(GATE_ROWS[0])+1)

static func _free_lot_cell(state:Dictionary) -> Vector2i:
	var lots:Array=_data(state).lots
	for lot in lots.size():
		if lots[lot].get("owner")=="":return pan_rect(lot*2).position
	return pan_rect(0).position

static func craft_allowed(state:Dictionary,token:String,kit:String) -> bool:
	var record:=own_record(state,token)
	match kit:
		"salt_wheel_kit":return int(record.raked)>=1
		"salt_rake_kit":return int(record.wheel_raked)>=1
	return true

static func gate_full(gate:Variant) -> bool:
	if not gate is Dictionary:return false
	for item:String in GATE_MATERIALS:
		if int(gate.get(item,0))<int(GATE_NEEDS_EACH[item]):return false
	return true

# ---------------------------------------------------------------- chests

## {id:"ok"|"unset"|"invalid"|"owner", chest:Dictionary}. Never moves items.
static func chest_check(lot:Dictionary,objects:Variant) -> Dictionary:
	var cell:=str(lot.get("chest",""))
	if cell=="":return {"id":"unset","chest":{}}
	if not objects is Dictionary:return {"id":"invalid","chest":{}}
	var obj=objects.get(cell)
	if not obj is Dictionary or str(obj.get("type","")) not in ["chest","private_chest"] or not obj.get("items") is Dictionary:return {"id":"invalid","chest":{}}
	if not obj.get("box_id") is String or obj.box_id!=lot.get("box") or str(lot.get("box",""))=="":return {"id":"invalid","chest":{}}
	if obj.type=="private_chest" and obj.get("owner")!=lot.get("owner"):return {"id":"owner","chest":{}}
	return {"id":"ok","chest":obj}

static func _full(amount:int,cap:int) -> bool:
	return amount+YIELD>cap or amount+YIELD>LIMIT

# ---------------------------------------------------------------- status

static func status(state:Dictionary,token:String,objects:Variant,now:float) -> Dictionary:
	var unit:=unit_of(state,token)
	if unit.kind=="":return {"id":"","text":""}
	return unit_status(state,int(unit.index),objects,now)

## Status of one unit (lot 0..7, PUBLIC_LOT or APPRENTICE_LOT) at `now`.
static func unit_status(state:Dictionary,unit:int,objects:Variant,now:float) -> Dictionary:
	if unit==PUBLIC_LOT:return _status("reserve")
	if not _machine_lot(unit):return {"id":"","text":""}
	var data:=_data(state)
	var cfg:=_unit_config(data,unit)
	if not yes(cfg.get("wheel")):return _status("manual")
	if not yes(cfg.get("rake")):return _status("wheel_only")
	var amount:=0
	if unit==APPRENTICE_LOT:
		amount=int(data.coop_box.get(str(cfg.get("tenant","")),0))
	else:
		if str(cfg.get("chest",""))=="":return _status("unset")
	if not yes(cfg.get("on")):return _status("off")
	if unit!=APPRENTICE_LOT:
		var check:=chest_check(cfg,objects)
		if check.id!="ok":return _status(check.id)
		amount=int(check.chest.items.get("sea_salt",0))
	if _full(amount,int(cfg.get("cap",CAP_DEFAULT))):return _status("full")
	if raining(now):return _status("rain")
	var all_brine:=true
	for i in [unit*2,unit*2+1]:
		if data.pans[i].get("s")!="brine":all_brine=false
	return _status("waiting" if all_brine else "running")

static func _status(id:String) -> Dictionary:
	return {"id":id,"text":STATUS_TEXT[id]}

# ---------------------------------------------------------------- actions

static func _site_ok(action:String,region:String,p:Vector2i) -> bool:
	if action in HOME_ACTIONS:return region==HOME and p==XIAOLI_HOME
	if region!=REGION:return false
	match action:
		"salt_intro","salt_report":return p==SALT_WORKER
		"salt_note":return p==HERITAGE_SIGN
		"salt_gate_give":return gate_at(p)>=0
		"salt_flood","salt_rake":return pan_at(p)>=0
		"salt_claim","salt_release":return lot_at(p)>=0
		"salt_install","salt_uninstall":return _socket_kind(p)[0]!="" or lot_at(p)==PUBLIC_LOT
		"salt_auto_cfg","salt_auto_toggle":return _socket_kind(p)[0]=="rake" or lot_at(p)==PUBLIC_LOT
		"salt_box_take":return p==APPRENTICE_CHEST
	return false

## World guarantees region and reach; this still verifies the exact site.
## Every check runs before any change, so a failure leaves state untouched.
static func apply(state:Dictionary,token:String,action:String,region:String,p:Vector2i,extra:String,objects:Variant,now:float) -> Dictionary:
	if action not in ACTIONS:return fail("無法執行鹽田作業。")
	if not _site_ok(action,region,p):
		return fail("請到渡口小栗的攤位。" if action in HOME_ACTIONS else "請到北門合作鹽田對應的地方。")
	if not _number(now) or now<0.0 or now>MAX_TIME:return fail("鹽田的時間還沒準備好，請稍後再試。")
	var data=state.get("salt_pan")
	if not data is Dictionary or not data.get("players") is Dictionary:return fail("鹽田資料尚未就緒。")
	var player=state.get("players",{}).get(token)
	if not player is Dictionary or not player.get("inventory") is Dictionary:return fail("找不到島民資料。")
	if not unlocked(state,token):return fail(STORY.locked)
	var objs:Dictionary=objects if objects is Dictionary else {}
	if action=="salt_letter":
		if data.players.has(token) and yes(data.players[token].get("letter")):return fail("北門的信已收下，可從手帳重看。")
		var created:=RECORD.duplicate(true)
		created.letter=true
		data.players[token]=created
		return ok("收下北門寄來的信；轉乘時可以選擇前往北門了。")
	if not data.players.has(token):return fail("先在渡口向小栗收下北門寄來的信。")
	var record:Dictionary=data.players[token]
	var inv:Dictionary=player.inventory
	match action:
		"salt_intro":
			if not _visited(player):return fail("先經轉乘抵達北門合作鹽田。")
			if yes(record.intro):return ok("阿曬：" + _echo(state,token))
			record.intro=true
			return ok("阿曬：「海水要靠閘門引進來。三道閘門都換上新木板，鹽田才會醒過來。」")
		"salt_note":
			record.note=true
			return ok(NOTE_TEXT)
		"salt_order":
			if yes(record.order):return fail("海鹽委託已經交過了。")
			if phase(state,token)!="order":return fail("先讓自己的收鹽台自動收一次鹽，再來交委託。")
			var short:PackedStringArray=[]
			for item:String in ORDER:
				var held:=int(inv.get(item,0))
				if held<int(ORDER[item]):short.append("%s還差 %d"%[ITEMS[item],int(ORDER[item])-held])
			if not short.is_empty():return fail("委託還不夠：%s。"%"、".join(short))
			if int(player.get("coins",0))>LIMIT-ORDER_PAY:return fail("鈴幣已達上限，委託暫不結算。")
			for item:String in ORDER:inv[item]=int(inv[item])-int(ORDER[item])
			player.coins=int(player.get("coins",0))+ORDER_PAY
			record.order=true
			return ok("把海鹽和香煎溪魚交給小栗，鈴幣 +%d。"%ORDER_PAY)
		"salt_report":
			if yes(record.complete):return fail("北門這一段已經完成，可從手帳重看。")
			if phase(state,token)!="report":return fail("先把海鹽委託交給渡口的小栗。")
			record.complete=true
			return ok("阿曬笑著點頭：「鹽送到了就好。」手帳加上了北門瓦盤鹽田與阿曬的頁面。")
		"salt_box_take":return _box_take(data,inv,token)
	if not yes(record.intro):return fail("先到合作社工寮前和阿曬打聲招呼。")
	match action:
		"salt_gate_give":return _gate_give(state,data,record,inv,token,p,extra,now)
		"salt_flood":return _flood(data,token,p,now)
		"salt_rake":return _rake(data,record,inv,token,p,now)
		"salt_claim":return _claim(state,data,record,token,p,now)
		"salt_release":return _release(state,data,token,p,objs,now)
		"salt_install":return _install(data,inv,token,p,extra)
		"salt_uninstall":return _uninstall(data,inv,token,p,extra)
		"salt_auto_cfg":return _auto_cfg(data,token,p,extra,objs)
		"salt_auto_toggle":return _auto_toggle(data,token,p)
	return fail("無法執行鹽田作業。")

## Moves the caller's own compartment (salt and returned kits) into the
## inventory, each item bounded by LIMIT; whatever does not fit stays. Only
## `token`'s compartment is ever read or written.
static func _box_take(data:Dictionary,inv:Dictionary,token:String) -> Dictionary:
	var held:=int(data.coop_box.get(token,0))
	var box=data.kit_box.get(token)
	var kits:=fresh_kit_box()
	if box is Dictionary:
		for kit:String in KIT_IDS:kits[kit]=int(box.get(kit,0))
	var kit_count:=int(kits.salt_wheel_kit)+int(kits.salt_rake_kit)
	if held<=0 and kit_count<=0:return fail("合作社收鹽箱裡沒有你的海鹽或機器組。")
	var take:=maxi(0,mini(held,LIMIT-int(inv.get("sea_salt",0))))
	var kit_take:={}
	var moved:=take
	for kit:String in KIT_IDS:
		kit_take[kit]=maxi(0,mini(int(kits[kit]),LIMIT-int(inv.get(kit,0))))
		moved+=int(kit_take[kit])
	if moved<=0:return fail("背包的海鹽已達上限。" if kit_count<=0 else "背包的這些物品已達上限，先整理背包再來取。")
	var parts:PackedStringArray=[]
	var left:PackedStringArray=[]
	if take>0:
		inv.sea_salt=int(inv.get("sea_salt",0))+take
		parts.append("海鹽 ×%d"%take)
	if held>0:
		if held-take>0:
			data.coop_box[token]=held-take
			left.append("海鹽 %d 份"%(held-take))
		else:data.coop_box.erase(token)
	if kit_count>0:
		var rest:=fresh_kit_box()
		for kit:String in KIT_IDS:
			var n:=int(kit_take[kit])
			if n>0:
				inv[kit]=int(inv.get(kit,0))+n
				parts.append("%s ×%d"%[ITEMS[kit],n])
			rest[kit]=int(kits[kit])-n
			if int(rest[kit])>0:left.append("%s %d 組"%[ITEMS[kit],int(rest[kit])])
		if int(rest.salt_wheel_kit)+int(rest.salt_rake_kit)>0:data.kit_box[token]=rest
		else:data.kit_box.erase(token)
	if kit_count<=0:
		if held-take>0:return ok("從合作社收鹽箱取出海鹽 ×%d，其餘 %d 份先留在箱裡。"%[take,held-take])
		return ok("從合作社收鹽箱取出海鹽 ×%d。"%take)
	if left.is_empty():return ok("從合作社收鹽箱取出%s。"%"、".join(parts))
	return ok("從合作社收鹽箱取出%s；背包放不下的%s先留在箱裡。"%["、".join(parts),"、".join(left)])

static func _echo(state:Dictionary,token:String) -> String:
	return str(guidance(state,token).text)

static func _gate_give(state:Dictionary,data:Dictionary,record:Dictionary,inv:Dictionary,token:String,p:Vector2i,extra:String,now:float) -> Dictionary:
	if extra not in GATE_MATERIALS:return fail("請選擇要捐的材料：木板、樹脂或石材。")
	var gate:Dictionary=data.gates[gate_at(p)]
	var missing:=int(GATE_NEEDS_EACH[extra])-int(gate.get(extra,0))
	if missing<=0:return fail("這道閘門已經不缺這項材料。")
	var held:=int(inv.get(extra,0))
	if held<=0:return fail("背包沒有這項材料。")
	var take:=mini(missing,held)
	inv[extra]=held-take
	gate[extra]=int(gate.get(extra,0))+take
	data.givers[token]=true
	var names:={"plank":"木板","resin":"樹脂","stone":"石材"}
	var result:=ok("捐給閘門：%s ×%d。"%[names[extra],take])
	if float(data.repaired_at)<0.0:
		var all_full:=true
		for g in data.gates:
			if not gate_full(g):all_full=false
		if all_full:
			data.repaired_at=now
			result.message+="三道閘門都修好了，海水可以引進鹽田了！"
			result.event=GATE_EVENT
			if state.get("events") is Array:state.events.append(GATE_EVENT)
	return result

## Who may work a pan: public pool -> anyone with intro; private lot -> owner;
## apprentice -> current tenant only. "" when allowed.
static func _pan_denied(data:Dictionary,token:String,lot:int) -> String:
	if lot==PUBLIC_LOT:return ""
	if lot==APPRENTICE_LOT:
		var tenant:=str(data.apprentice.get("tenant",""))
		if tenant==token:return ""
		if tenant=="":return "學徒區要先輪班才能使用。"
		return "學徒區正由另一位島民輪班。"
	var owner:=str(data.lots[lot].get("owner",""))
	if owner==token:return ""
	if owner=="":return "這區還沒有人認領，先認領才能照顧。"
	return "這是其他島民照顧的鹽田區。"

static func _flood(data:Dictionary,token:String,p:Vector2i,now:float) -> Dictionary:
	if float(data.repaired_at)<0.0:return fail("閘門還沒修好，海水引不進來。")
	var i:=pan_at(p)
	var denied:=_pan_denied(data,token,lot_of_pan(i))
	if denied!="":return fail(denied)
	var pan:Dictionary=data.pans[i]
	if pan.s!="empty":return fail("這方鹽田已經有海水或鹽了。")
	if now<float(pan.t):return fail("鹽田的時間還沒準備好，請稍後再試。")
	if raining(now):return fail(RAIN_FLOOD_MESSAGE)
	pan.s="brine"
	pan.p=0.0
	pan.t=now
	pan.f="hand"
	return ok("引進海水了。晴天約 8 分鐘結成鹽，多雲會慢一些。")

static func _rake(data:Dictionary,record:Dictionary,inv:Dictionary,token:String,p:Vector2i,now:float) -> Dictionary:
	if float(data.repaired_at)<0.0:return fail("閘門還沒修好，鹽田還是空的。")
	var i:=pan_at(p)
	var lot:=lot_of_pan(i)
	var denied:=_pan_denied(data,token,lot)
	if denied!="":return fail(denied)
	var pan:Dictionary=data.pans[i]
	if pan.s=="empty":return fail(RAKED_MESSAGE if lot==PUBLIC_LOT else "這方鹽田還是空的，先引海水。")
	if now<float(pan.t):return fail("鹽田的時間還沒準備好，請稍後再試。")
	if pan.s=="brine":
		var cur:=advance(pan.p,pan.t,now)
		if not cur.ok:return fail("鹽田的時間還沒準備好，請稍後再試。")
		if not cur.salt:
			var minutes:=eta(pan,now)
			return fail("鹽還沒結成，約 %d 分鐘後再來。"%maxi(1,minutes) if minutes>0 else "鹽還沒結成，等天晴再來。")
	if int(inv.get("sea_salt",0))>LIMIT-YIELD:return fail("背包的海鹽已達上限。")
	inv.sea_salt=int(inv.get("sea_salt",0))+YIELD
	var by_wheel:bool=pan.f=="wheel"
	pan.s="empty"
	pan.p=0.0
	pan.t=now
	pan.f=""
	record.raked=mini(LIMIT,int(record.raked)+1)
	if by_wheel:record.wheel_raked=mini(LIMIT,int(record.wheel_raked)+1)
	return ok("收起海鹽 ×%d。"%YIELD)

static func _claim(state:Dictionary,data:Dictionary,record:Dictionary,token:String,p:Vector2i,now:float) -> Dictionary:
	var lot:=lot_at(p)
	if lot==PUBLIC_LOT:return fail(STATUS_TEXT.reserve)
	if float(data.repaired_at)<0.0 or int(record.raked)<1:return fail("先在保留手作池親手收一次鹽，阿曬才會分鹽田區給你。")
	if lot==APPRENTICE_LOT:
		var tenant:=str(data.apprentice.tenant)
		if tenant==token:return fail("你正在學徒區輪班。")
		if owned_lot(state,token)>=0:return fail("你已經有自己的鹽田區了，學徒區留給還沒有鹽田區的島民。")
		if int(record.auto_raked)>0:return fail("你已經會用收鹽台了，學徒區留給還在學的島民。")
		if free_lots(state)>0:return fail(FREE_LOT_MESSAGE)
		var order:Array=data.waitlist.order
		if tenant=="" and (order.is_empty() or _offer_head(data)==token):
			if not order.is_empty():order.remove_at(0)
			data.waitlist.offer_at=0.0
			data.apprentice.tenant=token
			data.apprentice.since=now
			return ok("開始在學徒區輪班（最長 3 天）。用自己做的水車和收鹽台練習，收鹽台自動收過一次鹽就算出師。")
		# Busy, or held for the list head: join (or confirm presence in) the list.
		var at:=_queue_index(data,token)
		if at<0:
			order.append({"token":token,"missed":0})
			at=order.size()-1
		elif int(order[at].get("missed",0))==0:
			return fail(_wait_text(data,at+1,now))
		else:order[at].missed=0
		return ok(_wait_text(data,at+1,now))
	var owner:=str(data.lots[lot].owner)
	if owner==token:return fail("這區已經是你照顧的鹽田區。")
	if owner!="":return fail(CLAIMED_MESSAGE)
	if owned_lot(state,token)>=0:return fail("每位島民只能照顧一區鹽田區。")
	if is_tenant(state,token):return fail("你正在學徒區輪班，先歸還學徒區，再認領自己的鹽田區。")
	data.lots[lot].owner=token
	_queue_remove(data,token,now)
	return ok("認領了這區鹽田區，兩方鹽田由你照顧。")

static func _wait_text(data:Dictionary,position:int,now:float) -> String:
	if str(data.apprentice.tenant)!="":return QUEUE_BUSY_FORMAT%[_shift_minutes(data,now),position]
	return QUEUE_HELD_FORMAT%[_offer_minutes(data,now),position]

static func _release(state:Dictionary,data:Dictionary,token:String,p:Vector2i,objects:Dictionary,now:float) -> Dictionary:
	var lot:=lot_at(p)
	if lot==PUBLIC_LOT:return fail(STATUS_TEXT.reserve)
	if lot==APPRENTICE_LOT:
		if not is_tenant(state,token):
			if _queue_index(data,token)>=0:
				_queue_remove(data,token,now)
				return ok("離開了學徒區輪班名單；想輪班時再來登記。")
			return fail("你沒有在學徒區輪班。")
		var escrowed:=_end_shift(data,state.players,{},false,now)
		if escrowed.is_empty():return ok("結束學徒區輪班，水車和收鹽台已收回背包。合作社收鹽箱裡的鹽仍為你保留。")
		return ok("結束學徒區輪班。"+KIT_ESCROW_NOTE)
	var cfg:Dictionary=data.lots[lot]
	if cfg.owner!=token:return fail("這不是你照顧的鹽田區。")
	if yes(cfg.wheel) or yes(cfg.rake):return fail("先把水車和收鹽台拆回背包，再歸還鹽田區。")
	for i in [lot*2,lot*2+1]:
		if data.pans[i].s!="empty":return fail("先把兩方鹽田的鹽收完，再歸還鹽田區。")
	for cell in chest_sockets(lot):
		if objects.has(key(cell)):return fail("先把收鹽台旁的箱子搬走，再歸還鹽田區。")
	data.lots[lot]=fresh_lot()
	return ok("歸還了鹽田區，其他島民可以認領了。")

## Returns [kind, unit] for an install/uninstall/cfg/toggle target, or a
## failure message in [""..., msg].
static func _machine_target(data:Dictionary,token:String,p:Vector2i) -> Dictionary:
	if lot_at(p)==PUBLIC_LOT:return fail(STATUS_TEXT.reserve)
	var socket:=_socket_kind(p)
	var unit:int=socket[1]
	if unit==APPRENTICE_LOT:
		if data.apprentice.tenant!=token:return fail("學徒區要先輪班才能裝設機器。" if data.apprentice.tenant=="" else "學徒區正由另一位島民輪班。")
	elif data.lots[unit].owner!=token:return fail("這不是你照顧的鹽田區。")
	return {"ok":true,"kind":socket[0],"unit":unit,"message":""}

static func _install(data:Dictionary,inv:Dictionary,token:String,p:Vector2i,extra:String) -> Dictionary:
	if extra not in KITS:return fail("請選擇要安裝水車或收鹽台。")
	var target:=_machine_target(data,token,p)
	if not target.ok:return target
	if target.kind!=extra:return fail("水車要裝在水車座，收鹽台要裝在收鹽台座。")
	var cfg:=_unit_config(data,int(target.unit))
	var kit:String=KITS[extra]
	if extra=="wheel":
		if yes(cfg.wheel):return fail("這裡已經裝好水車了。")
	else:
		if not yes(cfg.wheel):return fail("先裝好水車，再裝收鹽台。")
		if yes(cfg.rake):return fail("這裡已經裝好收鹽台了。")
	if int(inv.get(kit,0))<1:return fail("背包沒有%s，回家在工作台做一組。"%ITEMS[kit])
	# The shift must always be able to end: keep room in the owner's escrow.
	if int(target.unit)==APPRENTICE_LOT:
		var box=data.kit_box.get(token)
		if box is Dictionary and int(box.get(kit,0))>LIMIT-1:return fail("合作社收鹽箱裡你的%s已達上限，先取出再安裝。"%ITEMS[kit])
	inv[kit]=int(inv[kit])-1
	cfg[extra]=true
	if extra=="wheel":return ok("裝好鹽田水車了，晴天會自動把海水引進空的鹽田。")
	return ok("裝好收鹽台了。選好收鹽箱和存量上限，再啟用。")

static func _uninstall(data:Dictionary,inv:Dictionary,token:String,p:Vector2i,extra:String) -> Dictionary:
	if extra not in KITS:return fail("請選擇要拆下水車或收鹽台。")
	var target:=_machine_target(data,token,p)
	if not target.ok:return target
	if target.kind!=extra:return fail("水車在水車座，收鹽台在收鹽台座。")
	var cfg:=_unit_config(data,int(target.unit))
	var kit:String=KITS[extra]
	if not yes(cfg[extra]):return fail("這裡沒有裝%s。"%("水車" if extra=="wheel" else "收鹽台"))
	if extra=="rake" and yes(cfg.on):return fail("先暫停收鹽台，再拆回背包。")
	if extra=="wheel" and yes(cfg.rake):return fail("先拆下收鹽台，再拆水車。")
	if int(inv.get(kit,0))>LIMIT-1:return fail("背包的%s已達上限。"%ITEMS[kit])
	inv[kit]=int(inv.get(kit,0))+1
	cfg[extra]=false
	if extra=="rake" and int(target.unit)!=APPRENTICE_LOT:
		cfg.chest=""
		cfg.box=""
	return ok("把%s拆回背包了。"%ITEMS[kit])

static func _auto_cfg(data:Dictionary,token:String,p:Vector2i,extra:String,objects:Dictionary) -> Dictionary:
	var target:=_machine_target(data,token,p)
	if not target.ok:return target
	var unit:int=target.unit
	var cfg:=_unit_config(data,unit)
	if not yes(cfg.rake):return fail("先裝好收鹽台，再選收鹽箱。")
	if yes(cfg.on):return fail("先暫停收鹽台，再更換收鹽箱或上限。")
	var parsed:=parse_cfg(extra)
	if not parsed.ok:return fail("請重新選擇收鹽箱與存量上限。")
	var cap:int=parsed.cap
	if cap<CAP_MIN:return fail(CAP_MESSAGE)
	if cap>CAP_MAX:return fail("存量上限最多 999 份。")
	var cell:Vector2i=parsed.cell
	if unit==APPRENTICE_LOT:
		if cell!=APPRENTICE_CHEST:return fail("學徒區的鹽會收進合作社收鹽箱。")
		cfg.cap=cap
		return ok("收鹽台會把鹽收進合作社收鹽箱，存量上限 %d 份。"%cap)
	if cell not in chest_sockets(unit):return fail("請選擇這區收鹽台旁的箱位。")
	var obj=objects.get(key(cell))
	if not obj is Dictionary or str(obj.get("type","")) not in ["chest","private_chest"] or not obj.get("items") is Dictionary:return fail("請先在收鹽台旁的箱位放一個箱子。")
	if obj.type=="private_chest" and obj.get("owner")!=token:return fail(STATUS_TEXT.owner)
	if not _hex32(obj.get("box_id")):return fail("這個箱子還沒準備好，請再試一次。")
	cfg.chest=key(cell)
	cfg.box=str(obj.box_id)
	cfg.cap=cap
	return ok("收鹽台會把鹽收進這個箱子，存量上限 %d 份。"%cap)

static func _auto_toggle(data:Dictionary,token:String,p:Vector2i) -> Dictionary:
	var target:=_machine_target(data,token,p)
	if not target.ok:return target
	var cfg:=_unit_config(data,int(target.unit))
	if not yes(cfg.rake):return fail("先裝好收鹽台。")
	if int(target.unit)!=APPRENTICE_LOT and str(cfg.chest)=="":return fail(STATUS_TEXT.unset)
	cfg.on=not yes(cfg.on)
	return ok("收鹽台啟用了。" if cfg.on else "收鹽台暫停了，成鹽會留在鹽田裡。")

## "x,y|cap" with 1-2 digit coordinates and a 1-3 digit cap.
static func parse_cfg(extra:String) -> Dictionary:
	var regex:=RegEx.new()
	regex.compile("^(\\d{1,2}),(\\d{1,2})\\|(\\d{1,3})$")
	var m:=regex.search(extra)
	if m==null:return {"ok":false}
	return {"ok":true,"cell":Vector2i(int(m.get_string(1)),int(m.get_string(2))),"cap":int(m.get_string(3))}

static func key(p:Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

## Ends the apprentice shift. ALWAYS succeeds: each installed kit goes to the
## tenant's inventory when it fits under LIMIT (`pending` holds kits already
## promised this step), otherwise into the tenant's escrow `kit_box` (room is
## guaranteed by the install guard and validation). Resets the station, marks
## non-empty pans as hand pans and opens the list head's window at `at`.
## When `defer` is true inventory kits are recorded in `pending` (committed by
## step only on success); otherwise they go straight into the inventory.
## Returns the escrowed kits ({} when everything fit).
static func _end_shift(data:Dictionary,players:Variant,pending:Dictionary,defer:bool,at:float) -> Dictionary:
	var app:Dictionary=data.apprentice
	var tenant:=str(app.tenant)
	if tenant=="":return {}
	var inv=null
	if players is Dictionary and players.get(tenant) is Dictionary and players[tenant].get("inventory") is Dictionary:inv=players[tenant].inventory
	var owed:Dictionary=pending.get(tenant,{})
	var escrow:={}
	for part:String in KITS:
		if not yes(app[part]):continue
		var kit:String=KITS[part]
		if inv is Dictionary and int(inv.get(kit,0))+int(owed.get(kit,0))<=LIMIT-1:
			if defer:owed[kit]=int(owed.get(kit,0))+1
			else:inv[kit]=int(inv.get(kit,0))+1
		else:escrow[kit]=1
	if defer and not owed.is_empty():pending[tenant]=owed
	if not escrow.is_empty():
		var box:=fresh_kit_box()
		var old=data.kit_box.get(tenant)
		if old is Dictionary:
			for kit:String in KIT_IDS:box[kit]=int(old.get(kit,0))
		for kit:String in escrow:box[kit]=int(box[kit])+int(escrow[kit])
		data.kit_box[tenant]=box
	data.apprentice=fresh_apprentice()
	for i in [APPRENTICE_LOT*2,APPRENTICE_LOT*2+1]:
		if data.pans[i].s!="empty":data.pans[i].f="hand"
	data.waitlist.offer_at=0.0 if data.waitlist.order.is_empty() else at
	return escrow

# ---------------------------------------------------------------- automation

## Exact event simulation over [t0,t1] for every lot (crystallisation for all
## pans; wheel refills and collector deliveries for private lots and the
## apprentice). Atomic: on any invalid input or guard hit returns
## {ok:false,changed:false} and leaves salt_pan, chests and inventories as-is.
static func step(state:Dictionary,t0:Variant,t1:Variant,objects:Variant) -> Dictionary:
	var no:={"ok":false,"changed":false}
	if not (_number(t0) and _number(t1)):return no
	var a:=float(t0)
	var b:=float(t1)
	if a<0.0 or b<a or b>MAX_TIME:return no
	var data=state.get("salt_pan")
	if not data is Dictionary or not _step_shape(data):return no
	if not state.get("players") is Dictionary:return no
	var objs:Dictionary=objects if objects is Dictionary else {}
	if not _quick_busy(data):return {"ok":true,"changed":false}
	var work:Dictionary=data.duplicate(true)
	var deposits:={}
	var pending:={}
	var changed:=false
	for unit in LOT_ORIGINS.size():
		var r:=_simulate(work,unit,a,b,objs,state.players,deposits,pending)
		if not r.ok:return no
		if r.changed:changed=true
	if not changed:return {"ok":true,"changed":false}
	for cell:String in deposits:
		var items:Dictionary=objs[cell].items
		items.sea_salt=int(items.get("sea_salt",0))+int(deposits[cell])
	for tenant in pending:
		var inv:Dictionary=state.players[tenant].inventory
		for kit:String in pending[tenant]:inv[kit]=int(inv.get(kit,0))+int(pending[tenant][kit])
	data.clear()
	data.merge(work)
	return {"ok":true,"changed":true}

## Nothing can happen when every pan is empty and no wheel/shift is active.
static func _quick_busy(data:Dictionary) -> bool:
	for pan in data.pans:
		if pan.s!="empty":return true
	if data.apprentice.tenant!="" or not data.waitlist.order.is_empty():return true
	for lot in data.lots:
		if yes(lot.wheel):return true
	return false

static func _step_shape(data:Dictionary) -> bool:
	for field:String in ROOT_KEYS:
		if not data.has(field):return false
	if not (data.players is Dictionary and data.pans is Array and data.lots is Array and data.apprentice is Dictionary and data.coop_box is Dictionary and _number(data.repaired_at)):return false
	if data.pans.size()!=PAN_COUNT or data.lots.size()!=LOT_COUNT:return false
	for pan in data.pans:
		if not pan is Dictionary or pan.get("s") not in PAN_STATES or not _number(pan.get("p")) or not _number(pan.get("t")) or not pan.get("f") is String:return false
		if float(pan.p)<0.0 or float(pan.p)>NEED or float(pan.t)<0.0 or float(pan.t)>MAX_TIME:return false
	for cfg in data.lots+[data.apprentice]:
		if not cfg is Dictionary:return false
		if not (cfg.get("wheel") is bool and cfg.get("rake") is bool and cfg.get("on") is bool and _number(cfg.get("cap"))):return false
		if float(cfg.cap)<CAP_MIN or float(cfg.cap)>CAP_MAX:return false
	for cfg in data.lots:
		if not (cfg.get("owner") is String and cfg.get("chest") is String and cfg.get("box") is String):return false
	if not (data.apprentice.get("tenant") is String and _number(data.apprentice.get("since"))):return false
	for token in data.coop_box:
		if not _number(data.coop_box[token]) or float(data.coop_box[token])<0.0 or float(data.coop_box[token])>LIMIT:return false
	if not (data.kit_box is Dictionary and data.waitlist is Dictionary and data.waitlist.get("order") is Array and _number(data.waitlist.get("offer_at"))):return false
	for token in data.kit_box:
		var box=data.kit_box[token]
		if not box is Dictionary:return false
		for kit:String in KIT_IDS:
			if not _number(box.get(kit)) or float(box[kit])<0.0 or float(box[kit])>LIMIT:return false
	# escrow room for every installed apprentice kit: the shift end is total
	var tenant:=str(data.apprentice.tenant)
	if tenant!="" and data.kit_box.get(tenant) is Dictionary:
		for part:String in KITS:
			if yes(data.apprentice[part]) and float(data.kit_box[tenant][KITS[part]])>LIMIT-1:return false
	for entry in data.waitlist.order:
		if not entry is Dictionary or not entry.get("token") is String or not _number(entry.get("missed")):return false
	return true

static func _simulate(work:Dictionary,unit:int,a:float,b:float,objects:Dictionary,players:Dictionary,deposits:Dictionary,pending:Dictionary) -> Dictionary:
	var pans:Array=work.pans
	var ids:=[unit*2,unit*2+1]
	var events:=0
	var changed:=false
	var is_app:=unit==APPRENTICE_LOT
	var seawater:=float(work.repaired_at)>=0.0
	if is_app and work.apprentice.tenant!="":
		var record=work.players.get(work.apprentice.tenant)
		var graduated:=record is Dictionary and int(record.get("auto_raked",0))>=1
		if graduated or float(work.apprentice.since)+SHIFT_SECONDS<=a:
			_end_shift(work,players,pending,true,a)
			changed=true
	while true:
		var occupant:=""
		var cfg:Dictionary={}
		if unit<LOT_COUNT:
			cfg=work.lots[unit]
			occupant=str(cfg.owner)
		elif is_app:
			cfg=work.apprentice
			occupant=str(cfg.tenant)
		var best_time:=INF
		var best_kind:=99
		var best_pan:=-1
		# kind 0: shift expiry
		if is_app and occupant!="":
			var expiry:=maxf(float(cfg.since)+SHIFT_SECONDS,a)
			if expiry<=b:
				best_time=expiry
				best_kind=0
		# kind 4: the free station's waiting-list window lapses
		elif is_app and not work.waitlist.order.is_empty():
			var lapse:=maxf(float(work.waitlist.offer_at)+OFFER_SECONDS,a)
			if lapse<=b:
				best_time=lapse
				best_kind=4
		var collector:=false
		var cell:=""
		var amount:=0
		if occupant!="" and yes(cfg.rake) and yes(cfg.on):
			if is_app:
				amount=int(work.coop_box.get(occupant,0))
				collector=true
			else:
				var check:=chest_check(cfg,objects)
				if check.id=="ok":
					cell=str(cfg.chest)
					amount=int(check.chest.items.get("sea_salt",0))+int(deposits.get(cell,0))
					collector=true
			if collector and _full(amount,int(cfg.cap)):collector=false
		var wheel:=seawater and occupant!="" and yes(cfg.wheel) and (yes(cfg.on) or not yes(cfg.rake))
		for i:int in ids:
			var pan:Dictionary=pans[i]
			var when:=INF
			var kind:=99
			if pan.s=="brine":
				var adv:=advance(pan.p,pan.t,b)
				if not adv.ok:return {"ok":false,"changed":false}
				if adv.salt:
					when=float(adv.at)
					kind=1
			elif pan.s=="salt":
				if collector:
					when=maxf(float(pan.t),a)
					kind=2
			elif wheel:
				var refill:=first_dry(maxf(float(pan.t),a))
				if refill<=b:
					when=refill
					kind=3
			if kind==99:continue
			if when<best_time or (when==best_time and kind<best_kind):
				best_time=when
				best_kind=kind
				best_pan=i
		if best_kind==99:break
		events+=1
		if events>MAX_EVENTS:return {"ok":false,"changed":false}
		changed=true
		match best_kind:
			0:
				_end_shift(work,players,pending,true,best_time)
			4:
				# Head missed its window: first miss -> back of the list, second
				# miss -> removed (may rejoin with salt_claim). Never blocks.
				var order:Array=work.waitlist.order
				var head:Dictionary=order.pop_front()
				if int(head.missed)==0:
					head.missed=1
					order.append(head)
				work.waitlist.offer_at=0.0 if order.is_empty() else best_time
			1:
				var pan:Dictionary=pans[best_pan]
				pan.s="salt"
				pan.p=NEED
				pan.t=best_time
			2:
				var pan:Dictionary=pans[best_pan]
				pan.s="empty"
				pan.p=0.0
				pan.t=best_time
				pan.f=""
				if is_app:work.coop_box[occupant]=amount+YIELD
				else:deposits[cell]=int(deposits.get(cell,0))+YIELD
				var record:Dictionary=work.players[occupant]
				record.auto_raked=mini(LIMIT,int(record.auto_raked)+1)
				if is_app:_end_shift(work,players,pending,true,best_time)
			3:
				var pan:Dictionary=pans[best_pan]
				pan.s="brine"
				pan.p=0.0
				pan.t=best_time
				pan.f="wheel"
	return {"ok":true,"changed":changed}

# ---------------------------------------------------------------- schema

## Whole-state validation (salt_pan, its references into players/time and the
## beimen region layers). Any failure rejects the whole save. On success JSON
## floats are normalised to ints/floats in place.
static func valid(state:Dictionary) -> bool:
	var data=state.get("salt_pan")
	if not data is Dictionary or data.size()!=ROOT_KEYS.size():return false
	for field:String in ROOT_KEYS:
		if not data.has(field):return false
	var players=state.get("players")
	if not players is Dictionary or not _number(state.get("time")):return false
	var now:=float(state.time)
	if now<0.0 or now>MAX_TIME:return false
	if not data.players is Dictionary or not data.givers is Dictionary or not data.gates is Array or not data.pans is Array or not data.lots is Array or not data.apprentice is Dictionary or not data.coop_box is Dictionary:return false
	# records
	for token in data.players:
		var record=data.players[token]
		if not token is String or token=="" or not players.has(token) or not record is Dictionary or record.size()!=RECORD.size():return false
		for field:String in RECORD:
			if not record.has(field):return false
			if RECORD[field] is bool:
				if not record[field] is bool:return false
			elif not whole(record[field],0):return false
		if not record.letter:return false
		if not yes(FlowerNursery.own_record(state,token).get("complete")):return false
		if record.intro and not _visited(players[token]):return false
		if int(record.raked)>0 and not record.intro:return false
		if int(record.wheel_raked)>int(record.raked):return false
		if int(record.auto_raked)>0 and int(record.raked)<1:return false
		if record.order and int(record.raked)<1:return false
		if record.complete and not record.order:return false
	for token in players:
		var player=players[token]
		if player is Dictionary and player.get("region")==REGION:
			var record=data.players.get(token)
			if not record is Dictionary or not yes(record.get("letter")):return false
	# gates
	if data.gates.size()!=GATE_ROWS.size():return false
	var all_full:=true
	var donated:=0
	for gate in data.gates:
		if not gate is Dictionary or gate.size()!=GATE_MATERIALS.size():return false
		for item:String in GATE_MATERIALS:
			if not gate.has(item) or not whole(gate[item],0) or int(gate[item])>int(GATE_NEEDS_EACH[item]):return false
			donated+=int(gate[item])
		if not gate_full(gate):all_full=false
	for token in data.givers:
		if not token is String or not players.has(token) or not yes(data.givers[token]):return false
		var record=data.players.get(token)
		if not record is Dictionary or not yes(record.get("intro")):return false
	if donated>0 and data.givers.is_empty():return false
	if not _number(data.repaired_at):return false
	var fixed:=float(data.repaired_at)
	if all_full:
		if fixed<0.0 or fixed>now:return false
	elif fixed!=-1.0:return false
	# pans
	if data.pans.size()!=PAN_COUNT:return false
	for pan in data.pans:
		if not pan is Dictionary or pan.size()!=4:return false
		if pan.get("s") not in PAN_STATES or not _number(pan.get("p")) or not _number(pan.get("t")) or not pan.get("f") is String:return false
		var t:=float(pan.t)
		var p:=float(pan.p)
		if t<0.0 or t>now:return false
		match pan.s:
			"empty":
				if p!=0.0 or pan.f!="":return false
			"brine":
				if p<0.0 or p>=NEED or pan.f not in ["hand","wheel"]:return false
			"salt":
				if p!=NEED or pan.f not in ["hand","wheel"]:return false
		if fixed<0.0 and pan.s!="empty":return false
	# lots
	if data.lots.size()!=LOT_COUNT:return false
	var owners:={}
	for lot in LOT_COUNT:
		var cfg=data.lots[lot]
		if not cfg is Dictionary or cfg.size()!=7:return false
		for field in ["owner","chest","box"]:
			if not cfg.get(field) is String:return false
		for field in ["wheel","rake","on"]:
			if not cfg.get(field) is bool:return false
		if not whole(cfg.get("cap"),0):return false
		if cfg.owner=="":
			if cfg.wheel or cfg.rake or cfg.on or cfg.chest!="" or cfg.box!="" or int(cfg.cap)!=CAP_DEFAULT:return false
			continue
		if owners.has(cfg.owner) or not players.has(cfg.owner):return false
		owners[cfg.owner]=true
		var record=data.players.get(cfg.owner)
		if not record is Dictionary or int(record.get("raked",0))<1:return false
		if cfg.rake and not cfg.wheel:return false
		if int(cfg.cap)<CAP_MIN or int(cfg.cap)>CAP_MAX:return false
		if (cfg.chest=="")!=(cfg.box==""):return false
		if cfg.chest!="":
			var matched:=false
			for cell in chest_sockets(lot):
				if key(cell)==cfg.chest:matched=true
			if not matched or not _hex32(cfg.box):return false
			if not cfg.rake:return false
		if cfg.on and (not cfg.rake or cfg.chest==""):return false
	# apprentice
	var app:Dictionary=data.apprentice
	if app.size()!=6:return false
	if not app.get("tenant") is String or not _number(app.get("since")) or not whole(app.get("cap"),0):return false
	for field in ["wheel","rake","on"]:
		if not app.get(field) is bool:return false
	if app.tenant=="":
		if float(app.since)!=0.0 or app.wheel or app.rake or app.on or int(app.cap)!=CAP_DEFAULT:return false
	else:
		if not players.has(app.tenant) or owners.has(app.tenant):return false
		var record=data.players.get(app.tenant)
		if not record is Dictionary or int(record.get("raked",0))<1:return false
		if float(app.since)<0.0 or float(app.since)>now:return false
		if app.rake and not app.wheel:return false
		if app.on and not app.rake:return false
		if int(app.cap)<CAP_MIN or int(app.cap)>CAP_MAX:return false
	# cooperative box
	for token in data.coop_box:
		if not token is String or not players.has(token) or not whole(data.coop_box[token],1):return false
		if not data.players.has(token):return false
	# returned-kit escrow: owner compartments only, both ids, never empty
	if not data.kit_box is Dictionary:return false
	for token in data.kit_box:
		var box=data.kit_box[token]
		if not token is String or not players.has(token) or not data.players.has(token):return false
		if not box is Dictionary or box.size()!=KIT_IDS.size():return false
		var held:=0
		for kit:String in KIT_IDS:
			if not box.has(kit) or not whole(box[kit],0):return false
			held+=int(box[kit])
		if held<1:return false
	if app.tenant!="" and data.kit_box.has(app.tenant):
		for part:String in KITS:
			if app[part] and int(data.kit_box[app.tenant][KITS[part]])>LIMIT-1:return false
	# apprentice waiting list
	var wl=data.waitlist
	if not wl is Dictionary or wl.size()!=2 or not wl.get("order") is Array or not _number(wl.get("offer_at")):return false
	var listed:={}
	for entry in wl.order:
		if not entry is Dictionary or entry.size()!=2 or not entry.get("token") is String or not whole(entry.get("missed"),0) or int(entry.missed)>1:return false
		var who:String=entry.token
		if who=="" or listed.has(who) or not players.has(who) or who==app.tenant or owners.has(who):return false
		listed[who]=true
		var record=data.players.get(who)
		if not record is Dictionary or not yes(record.get("intro")) or int(record.get("raked",0))<1 or int(record.get("auto_raked",0))!=0:return false
	var offer:=float(wl.offer_at)
	if app.tenant=="" and not wl.order.is_empty():
		if offer<0.0 or offer>now:return false
	elif offer!=0.0:return false
	# beimen region layers
	var regions=state.get("regions")
	if regions is Dictionary and regions.has(REGION):
		var layer=regions[REGION]
		if not layer is Dictionary:return false
		for field in ["crops","ground","roofs","forest","removed","damage"]:
			if layer.has(field) and (not layer[field] is Dictionary or not layer[field].is_empty()):return false
		var objects=layer.get("objects",{})
		if not objects is Dictionary:return false
		for cell in objects:
			var obj=objects[cell]
			if not cell is String or not obj is Dictionary or str(obj.get("type","")) not in ["chest","private_chest"] or not obj.get("items") is Dictionary:return false
			var parsed:=_parse_cell(cell)
			if not parsed.ok or chest_socket_lot(parsed.cell)<0:return false
	# normalise JSON numbers once everything is known to be valid
	for record in data.players.values():
		for field in ["raked","wheel_raked","auto_raked"]:record[field]=int(record[field])
	for gate in data.gates:
		for item:String in GATE_MATERIALS:gate[item]=int(gate[item])
	data.repaired_at=float(data.repaired_at)
	for pan in data.pans:
		pan.p=float(pan.p)
		pan.t=float(pan.t)
	for cfg in data.lots:cfg.cap=int(cfg.cap)
	app.cap=int(app.cap)
	app.since=float(app.since)
	for token in data.coop_box:data.coop_box[token]=int(data.coop_box[token])
	for box in data.kit_box.values():
		for kit:String in KIT_IDS:box[kit]=int(box[kit])
	for entry in wl.order:entry.missed=int(entry.missed)
	wl.offer_at=float(wl.offer_at)
	return true

static func _parse_cell(cell:String) -> Dictionary:
	var parts:=cell.split(",")
	if parts.size()!=2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():return {"ok":false}
	return {"ok":true,"cell":Vector2i(int(parts[0]),int(parts[1]))}

static func _hex32(value:Variant) -> bool:
	if not value is String or value.length()!=32:return false
	for c in value:
		if c not in "0123456789abcdef":return false
	return true

## For saves written before SAVE_VERSION: true only when no forward id appears
## anywhere such a save could carry it (whole-file rejection rule).
static func legacy_clean(s:Dictionary) -> bool:
	if s.has("salt_pan"):return false
	var regions=s.get("regions",{})
	if regions is Dictionary and regions.has(REGION):return false
	var players=s.get("players",{})
	if players is Dictionary:
		for player in players.values():
			if not player is Dictionary:continue
			if player.get("region")==REGION:return false
			if _has_forward_key(player.get("inventory")):return false
			var book=player.get("travel_book")
			if book is Dictionary and book.get("visited") is Dictionary and book.visited.has(REGION):return false
			var collection=player.get("collection")
			if collection is Dictionary:
				for category in collection.values():
					if _has_forward_key(category):return false
	var layers:Array=[s]
	if regions is Dictionary:
		for region in regions.values():
			if region is Dictionary:layers.append(region)
	for layer in layers:
		var objects=layer.get("objects",{})
		if objects is Dictionary:
			for obj in objects.values():
				if obj is Dictionary and not _object_clean(obj):return false
	return true

static func _object_clean(obj:Dictionary) -> bool:
	if _has_forward_key(obj.get("items")):return false
	if not _job_clean(obj.get("job")):return false
	for field in ["cooking","processing"]:
		var queue=obj.get(field)
		if not queue is Dictionary:continue
		var records:Array=[]
		var active=queue.get("active")
		if active is Dictionary and not active.is_empty():records.append(active)
		for bucket in ["waiting","ready"]:
			if queue.get(bucket) is Array:records.append_array(queue[bucket])
		for record in records:
			if not _job_clean(record):return false
	return true

static func _job_clean(job:Variant) -> bool:
	if not job is Dictionary:return true
	for field in ["kind","recipe","item","output"]:
		if str(job.get(field,"")) in FORWARD_IDS:return false
	return not _has_forward_key(job.get("ingredients")) and not _has_forward_key(job.get("outputs"))

static func _has_forward_key(table:Variant) -> bool:
	if not table is Dictionary:return false
	for id in FORWARD_IDS:
		if table.has(id):return true
	return false

# ---------------------------------------------------------------- snapshots

## Token-free shared projection (identical for every region and recipient).
static func public(state:Dictionary,now:float) -> Dictionary:
	var data:=_data(state)
	var gates:Array=[]
	for gate in data.gates:gates.append({"plank":int(gate.get("plank",0)),"resin":int(gate.get("resin",0)),"stone":int(gate.get("stone",0))})
	var pans:Array=[]
	for pan in data.pans:pans.append({"s":str(pan.get("s","empty")),"p":float(pan.get("p",0.0)),"t":float(pan.get("t",0.0)),"f":str(pan.get("f",""))})
	var lots:Array=[]
	for cfg in data.lots:lots.append({"taken":cfg.get("owner","")!="","wheel":yes(cfg.get("wheel")),"rake":yes(cfg.get("rake")),"active":_active(cfg),"mine":false})
	var app:Dictionary=data.apprentice
	var taken:bool=app.get("tenant","")!=""
	var weather:=WEATHER.at(now,REGION)
	return {
		"gates":gates,"needs":GATE_NEEDS_EACH.duplicate(true),"repaired":repaired(state),"giver_count":data.givers.size(),
		"pans":pans,"lots":lots,
		"apprentice":{"taken":taken,"wheel":yes(app.get("wheel")),"rake":yes(app.get("rake")),"active":_active(app),"ends_at":float(app.get("since",0.0))+SHIFT_SECONDS if taken else -1.0},
		"weather":{"id":weather.id,"label":weather.label,"raining":weather.raining},
	}

static func _active(cfg:Dictionary) -> bool:
	return yes(cfg.get("wheel")) and (yes(cfg.get("on")) or not yes(cfg.get("rake")))

## The recipient's own view. Never contains tokens, givers or other players'
## chests/caps.
static func own_view(state:Dictionary,token:String,objects:Variant,now:float) -> Dictionary:
	var data:=_data(state)
	var unit:=unit_of(state,token)
	var unit_view:={"kind":unit.kind,"index":unit.index,"wheel":false,"rake":false,"chest":"","cap":CAP_DEFAULT,"on":false,"status":{"id":"","text":""}}
	if unit.kind!="":
		var cfg:=_unit_config(data,int(unit.index))
		unit_view.wheel=yes(cfg.get("wheel"))
		unit_view.rake=yes(cfg.get("rake"))
		unit_view.chest=key(APPRENTICE_CHEST) if unit.kind=="apprentice" else str(cfg.get("chest",""))
		unit_view.cap=int(cfg.get("cap",CAP_DEFAULT))
		unit_view.on=yes(cfg.get("on"))
		unit_view.status=status(state,token,objects,now)
	var app:Dictionary=data.apprentice
	var tenant:=str(app.get("tenant",""))
	var mine:=tenant!="" and tenant==token
	var busy:=tenant!="" and not mine
	var eligible:=apprentice_eligible(state,token)
	var minutes:int=_shift_minutes(data,now) if tenant!="" else 0
	var position:=queue_position(state,token)
	var offer:=eligible and _offer_head(data)==token
	var offer_minutes:int=_offer_minutes(data,now) if offer else 0
	var held_for_other:bool=tenant=="" and not data.waitlist.order.is_empty() and not offer
	var can_join:bool=position==0 and not mine and (busy or held_for_other) and apprentice_candidate(state,token)
	var message:=""
	if mine:message="你正在學徒區輪班，最晚約 %d 分鐘後結束。"%minutes
	elif offer:message=OFFER_FORMAT%offer_minutes
	elif position>0:message=_wait_text(data,position,now)
	elif busy:message=BUSY_FORMAT%minutes
	elif held_for_other and can_join:message="學徒區正保留給名單上的島民接班；可以先排進輪班名單。"
	elif eligible:message="學徒區空著，可以來輪班。"
	elif free_lots(state)>0 and owned_lot(state,token)<0:message=FREE_LOT_MESSAGE
	var player=state.get("players",{}).get(token)
	var inv:Dictionary=player.inventory if player is Dictionary and player.get("inventory") is Dictionary else {}
	var have:={}
	for item:String in ORDER:have[item]=int(inv.get(item,0))
	return {
		"record":own_record(state,token),"phase":phase(state,token),"guidance":guidance(state,token),
		"lot":owned_lot(state,token),"unit":unit_view,
		"apprentice":{"eligible":eligible,"busy":busy,"mine":mine,"ends_in_minutes":minutes,"message":message,
			"queued":position>0,"position":position,"waiting":data.waitlist.order.size(),"offer":offer,"offer_minutes":offer_minutes,"can_join":can_join,
			"kits":escrow_of(state,token)},
		"coop_box":int(data.coop_box.get(token,0)),"free_lots":free_lots(state),
		"can_craft":{"salt_wheel_kit":craft_allowed(state,token,"salt_wheel_kit"),"salt_rake_kit":craft_allowed(state,token,"salt_rake_kit")},
		"order":{"need":ORDER.duplicate(true),"have":have,"pay":ORDER_PAY},
	}

# ---------------------------------------------------------------- helpers

static func _number(value:Variant) -> bool:
	return (value is int or value is float) and is_finite(value)

static func whole(value:Variant,minimum:int) -> bool:
	return _number(value) and value>=minimum and value<=LIMIT and floorf(value)==value

static func ok(message:String) -> Dictionary:
	return {"ok":true,"message":message}

static func fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

## Strict boolean truth (never compares a JSON number with a bool).
static func yes(value:Variant) -> bool:
	return value is bool and value
