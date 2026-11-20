extends RefCounted
## 打瞌睡石像 (plan section 16): cozy, non-combat windbell-tone puzzle in the B4 north cave.
##
## STANDALONE and PURE: no World/Session/UI references, no randomness, no clock. Every
## function returns new data and never mutates its arguments, so the host (World.act)
## stays the only authority and request-id receipts replay identically.
## Not wired in yet; see work/claude-agents/mine-guardian-prep/design.md for the handoff.
##
## Persisted per-player record (small, JSON-safe): {"round":0..2,"calm":0..3,"claimed":bool}
##   round 0 asleep, 1 first phrase echoed, 2 awake. The half-entered phrase is transient
##   (host memory only) and simply restarts after a reload.

const NAME:="打瞌睡石像"
const REGION:="mine_4"
const DEPTH:=4
## Dead-end nook of the B4 north cave (mine_layout Rect2i(32,10,4,1)).
const GUARDIAN:=Vector2i(34,10)
## Low / mid / high windbell. All stand in the cave room (Rect2i(31,11,7,3)), clear of the
## survey point (34,12) and the cave mouth column.
const BELLS:=[Vector2i(32,11),Vector2i(35,11),Vector2i(37,12)]
const REACH:=1.8
const ACTIONS:=["guardian_listen","guardian_ring","guardian_sit","guardian_claim"]
## Same information several ways, so no single sense is required: pitch, colour, shape, name.
const PITCH_HZ:=[329.63,392.0,493.88]
const COLORS:=[Color("d39c71"),Color("7fb59a"),Color("8d6f9c")]
const SHAPES:=["●","▲","■"]
const BELL_NAMES:=["低音鈴","中音鈴","高音鈴"]
const ROUNDS:=2
const CALM_NEEDED:=3
const REWARD_ITEM:="crystal_sand"
const REWARD_COUNT:=2
const ATLAS_PATH:="res://assets/mine/sleepy-stone-guardian.png"
const FRAME_SIZE:=Vector2i(32,40)
const FOOT:=Vector2i(16,38)

static func fresh() -> Dictionary:
	return {"round":0,"calm":0,"claimed":false}

static func _whole(value,top:int) -> bool:
	return (value is int or value is float) and is_finite(value) and floor(value)==value and value>=0 and value<=top

## Save validation for the player record (T064 wires this into save_schema).
static func valid(record) -> bool:
	if not record is Dictionary or record.size()!=3:return false
	if not _whole(record.get("round"),ROUNDS) or not _whole(record.get("calm"),CALM_NEEDED):return false
	if not record.get("claimed") is bool:return false
	var stage:=int(record.round)
	if int(record.calm)>=CALM_NEEDED and stage<ROUNDS:return false
	return not (record.claimed and stage<ROUNDS)

static func available(region:String,unlocked_depth:int) -> bool:
	return region==REGION and unlocked_depth>=DEPTH

static func near(pos:Vector2,cell:Vector2i) -> bool:
	return pos.distance_to(Vector2(cell)+Vector2(0.5,0.5))<=REACH

static func bell_at(cell:Vector2i) -> int:
	return BELLS.find(cell)

static func awake(record:Dictionary) -> bool:
	return int(record.get("round",0))>=ROUNDS

static func _seed(token:String) -> int:
	var h:=5381
	for byte in token.to_utf8_buffer():h=(h*33+byte)&0x7fffffff
	return h

## The phrase the guardian hums for this player: 2 notes, then 3 notes. Never repeats a
## bell twice in a row. Deterministic from the player id so replays and reloads agree.
static func phrase(token:String,stage:int) -> Array:
	var h:=_seed(token)
	var notes:Array=[h%3]
	for i in range(1,stage+2):
		notes.append((int(notes[i-1])+1+((h>>(i*3))&1))%3)
	return notes

static func _result(ok:bool,message:String,record:Dictionary,entered:Array,outcome:String) -> Dictionary:
	return {"ok":ok,"message":message,"record":record.duplicate(true),"entered":entered.duplicate(),"outcome":outcome}

## Hear the hum again. Unlimited and free; the notes come with shape/name/pitch so the
## phrase can be shown without sound.
static func listen(token:String,record:Dictionary) -> Dictionary:
	if awake(record):return _result(false,"牠已經醒了，正眨著琥珀色的眼睛看你。",record,[],"awake")
	var notes:Array=phrase(token,int(record.round))
	var view:Array=[]
	var words:Array=[]
	for n:int in notes:
		view.append({"bell":n,"hz":PITCH_HZ[n],"shape":SHAPES[n],"name":BELL_NAMES[n]})
		words.append(SHAPES[n]+BELL_NAMES[n])
	var out:=_result(true,"石像在睡夢中哼了 %d 個音：%s"%[notes.size()," ".join(words)],record,[],"listen")
	out["notes"]=view
	return out

## Ring one bell. A wrong bell only restarts the phrase: nothing is lost or punished.
static func ring(token:String,record:Dictionary,entered:Array,bell:int) -> Dictionary:
	if awake(record):return _result(false,"牠已經醒了，不用再敲鈴。",record,[],"awake")
	if bell<0 or bell>=BELLS.size():return _result(false,"那裡沒有風鈴。",record,entered,"invalid")
	var want:Array=phrase(token,int(record.round))
	var typed:Array=entered.duplicate()
	if typed.size()>=want.size():typed=[]
	typed.append(bell)
	if int(want[typed.size()-1])!=bell:
		return _result(true,"石像的眉毛皺了一下，翻個身。再聽一次牠的哼聲吧。",record,[],"wrong")
	if typed.size()<want.size():
		return _result(true,"石像的耳朵動了動。",record,typed,"progress")
	var next:=record.duplicate(true)
	next.round=int(record.round)+1
	if int(next.round)>=ROUNDS:
		return _result(true,"石像慢慢睜開眼睛，露出一個安心的微笑。",next,[],"awake")
	return _result(true,"石像呼嚕聲變小了。牠好像想再哼一段更長的。",next,[],"round")

## No-sound, no-timing fallback: sit with it three times. Same outcome, same reward.
static func sit(record:Dictionary) -> Dictionary:
	if awake(record):return _result(false,"牠已經醒了。",record,[],"awake")
	var next:=record.duplicate(true)
	next.calm=int(record.calm)+1
	if int(next.calm)>=CALM_NEEDED:
		next.round=ROUNDS
		return _result(true,"你安靜陪了牠一會兒，牠自己慢慢醒來，笑了一下。",next,[],"awake")
	return _result(true,"你在石像旁邊坐下。再陪牠一下下就好。",next,[],"sit")

## Optional reward; the host must still check inventory capacity before committing.
static func claim(record:Dictionary) -> Dictionary:
	if not awake(record):return _result(false,"石像還在睡，先陪牠一下。",record,[],"asleep")
	if bool(record.get("claimed",false)):return _result(false,"這份謝禮已經收下了。",record,[],"claimed")
	var next:=record.duplicate(true)
	next.claimed=true
	var out:=_result(true,"石像讓出身後的凹槽，裡面有一小撮晶砂。",next,[],"claim")
	out["reward"]={"item":REWARD_ITEM,"count":REWARD_COUNT}
	return out

## Atlas frame: 0/1 asleep (blink alternates), 2 first phrase echoed, 3 awake.
static func frame(record:Dictionary,blink:bool=false) -> int:
	var stage:=int(record.get("round",0))
	if stage>=ROUNDS:return 3
	if stage==1:return 2
	return 1 if blink else 0

static func frame_rect(index:int) -> Rect2i:
	return Rect2i(Vector2i(index%2,index/2)*FRAME_SIZE,FRAME_SIZE)
