extends RefCounted
## 害羞菇 (plan section 16): cozy, non-combat "stand still, then water" encounter in the B2 east cave.
##
## STANDALONE and PURE: no World/Session/UI references, no randomness, no clock. The host passes
## `now` (state.time) and the player position in; every function returns new data and never mutates
## its arguments, so World.act stays the only authority and request-id receipts replay identically.
## Not wired in yet; see work/claude-agents/shy-mushroom-prep/design.md for the handoff.
##
## This is the LIFE-mode solution. The plan's adventure alternative ("avoid the slow spores") is a
## later, additive variant of the same stage ladder and reward; adventure mode is NOT removed.
##
## Persisted per-player record (JSON-safe): {"stage":0..2,"claimed":bool}
##   stage 0 hidden under the cap, 1 peeking (after the quiet wait), 2 open (after watering).
## The wait anchor ("watch") is transient host memory: {} or {"x":f,"y":f,"since":f}. A reload simply
## starts the wait over; nothing is lost.

const NAME:="害羞菇"
const REGION:="mine_2"
const DEPTH:=2
## Dead-end corner of the B2 east cave nook (mine_layout Rect2i(45,19,2,5)).
const MUSHROOM:=Vector2i(46,23)
const REACH:=1.8
## Interact action (normal interact key) and the ordinary watering-can action the host routes here.
const WAIT_ACTION:="shy_wait"
const CLAIM_ACTION:="shy_claim"
const WATER_ACTION:="water"
const ACTIONS:=["shy_wait","shy_claim"]
## Short wait. Moving more than DRIFT tiles only restarts the wait: no penalty, no failure, no limit.
const WAIT_SECONDS:=4.0
const DRIFT:=0.75
const REWARD_ITEM:="fiber"
const REWARD_COUNT:=4
## Audio cue ids for soft_audio.gd (T064 adds the synthesis); the visual cue is the atlas frame.
const CUE_RUSTLE:="shy_rustle"
const CUE_PEEK:="shy_peek"
const CUE_SPLASH:="shy_splash"
const CUE_OPEN:="shy_open"
const ATLAS_PATH:="res://assets/mine/shy-mushroom.png"
const ATLAS_SIZE:=Vector2i(64,80)
const FRAME_SIZE:=Vector2i(32,40)
const FOOT:=Vector2i(16,38)
const FRAME_HIDDEN:=0
const FRAME_PEEK:=1
const FRAME_WATER:=2
const FRAME_OPEN:=3

static func fresh() -> Dictionary:
	return {"stage":0,"claimed":false}

static func valid(record) -> bool:
	if not record is Dictionary or record.size()!=2:return false
	var stage=record.get("stage")
	if not (stage is int or stage is float) or not is_finite(stage) or floor(stage)!=stage or stage<0 or stage>2:return false
	var claimed=record.get("claimed")
	if not claimed is bool:return false
	return not (claimed and int(stage)<2)

static func available(region:String,unlocked_depth:int) -> bool:
	return region==REGION and unlocked_depth>=DEPTH

static func near(pos:Vector2) -> bool:
	return pos.distance_to(Vector2(MUSHROOM)+Vector2(0.5,0.5))<=REACH

static func open(record:Dictionary) -> bool:
	return int(record.get("stage",0))>=2

static func _result(ok:bool,message:String,record:Dictionary,watch:Dictionary,outcome:String,cues:Array=[]) -> Dictionary:
	return {"ok":ok,"message":message,"record":record.duplicate(true),"watch":watch.duplicate(true),
		"outcome":outcome,"cues":cues.duplicate(),"remaining":0.0,"consume_water":false}

## Host may call this every tick with the player's position: walking off clears the wait anchor.
static func watch_hold(watch:Dictionary,pos:Vector2) -> Dictionary:
	if watch.is_empty():return {}
	if pos.distance_to(Vector2(float(watch.get("x",0.0)),float(watch.get("y",0.0))))>DRIFT:return {}
	return watch.duplicate()

## 0..1 fill for the stillness ring drawn around the mushroom (visual cue for the wait).
static func progress(watch:Dictionary,now:float) -> float:
	if watch.is_empty():return 0.0
	return clampf((now-float(watch.get("since",now)))/WAIT_SECONDS,0.0,1.0)

## Interact: stand still near the mushroom. First press starts the quiet wait; a later press after
## WAIT_SECONDS (without wandering off) makes it peek out. Pressing too early is harmless.
static func wait(record:Dictionary,watch:Dictionary,pos:Vector2,now:float) -> Dictionary:
	if open(record):return _result(false,"害羞菇已經完全打開帽子，正開心地看著你。",record,{},"open")
	if int(record.get("stage",0))==1:return _result(true,"牠探出頭了。用水壺給牠一點點水吧。",record,{},"peeking")
	if not near(pos):return _result(false,"請靠近害羞菇。",record,watch,"far")
	var anchor:=Vector2(float(watch.get("x",0.0)),float(watch.get("y",0.0)))
	var restart:=watch.is_empty() or pos.distance_to(anchor)>DRIFT or now<float(watch.get("since",now))
	if restart:
		var started:={"x":pos.x,"y":pos.y,"since":now}
		var out:=_result(true,"你停下腳步，安靜等著。帽子下傳來窸窸窣窣的聲音。",record,started,"start",[CUE_RUSTLE])
		out["remaining"]=WAIT_SECONDS
		return out
	var left:=WAIT_SECONDS-(now-float(watch.since))
	if left>0.0:
		var out:=_result(true,"再安靜一下下。",record,watch,"waiting",[CUE_RUSTLE])
		out["remaining"]=left
		return out
	var next:=record.duplicate(true)
	next.stage=1
	return _result(true,"帽子慢慢掀起一條縫，兩顆小眼睛偷偷看你。",next,{},"peek",[CUE_PEEK])

## Ordinary watering-can input on the mushroom cell. The host should spend water only when
## `consume_water` is true; a too-early splash costs nothing and loses nothing.
static func water(record:Dictionary,pos:Vector2) -> Dictionary:
	if open(record):return _result(false,"害羞菇已經喝飽了。",record,{},"open")
	if not near(pos):return _result(false,"請靠近害羞菇。",record,{},"far")
	if int(record.get("stage",0))<1:
		return _result(false,"水滴從帽緣滑開，牠縮得更小了。先停下來，安靜等一下。",record,{},"too_early",[CUE_RUSTLE])
	var next:=record.duplicate(true)
	next.stage=2
	var out:=_result(true,"牠伸出小手接住水滴，帽子完全打開，露出笑臉。",next,{},"water",[CUE_SPLASH,CUE_OPEN])
	out["consume_water"]=true
	return out

## Optional one-time personal gift. The host must still check inventory capacity before committing.
static func claim(record:Dictionary,pos:Vector2) -> Dictionary:
	if not near(pos):return _result(false,"請靠近害羞菇。",record,{},"far")
	if not open(record):return _result(false,"牠還躲在帽子下，先安靜陪牠一下。",record,{},"hidden")
	if bool(record.get("claimed",false)):return _result(false,"這份小禮物已經收下了。",record,{},"claimed")
	var next:=record.duplicate(true)
	next.claimed=true
	var out:=_result(true,"牠從帽子底下推出一小把乾淨的纖維。",next,{},"claim")
	out["reward"]={"item":REWARD_ITEM,"count":REWARD_COUNT}
	return out

## Atlas frame for a record. `responding` shows the water-response frame for the splash moment only.
static func frame(record:Dictionary,responding:bool=false) -> int:
	var stage:=int(record.get("stage",0))
	if stage>=2:return FRAME_WATER if responding else FRAME_OPEN
	return FRAME_PEEK if stage==1 else FRAME_HIDDEN

static func frame_rect(index:int) -> Rect2i:
	return Rect2i(Vector2i(index%2,index/2)*FRAME_SIZE,FRAME_SIZE)
