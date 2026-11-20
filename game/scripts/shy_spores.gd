extends RefCounted
## Personal B2 adventure. Two slow spores travel up adjacent lanes.
const Shy=preload("res://scripts/shy_mushroom.gd")
const ACTION:="shy_spores"
const VIEW:="shy_spores"
const FIELD:="shy_mushroom"
const ENTER:="start"
const FINISH:="finish"
const ARENA:=Rect2(45.0,19.0,2.0,5.0)
const LANES:=[45.5,46.5]
const ORIGIN_Y:=23.5
const EXIT_Y:=19.5
const WARNING_TIME:=1.25
const PASS_TIME:=3.0
const PHASE_TIME:=WARNING_TIME+PASS_TIME
const HIT_RADIUS:=0.46

enum Phase { WARNING, PASSING, FINISHED, MISSED }

static func begin(at:Vector2,now:float)->Dictionary:
	if not ARENA.has_point(at) or not Shy.near(at):return {}
	return {"since":now,"first_lane":0 if at.x<46.0 else 1}

static func view(run:Dictionary,now:float)->Dictionary:
	if run.is_empty():return {}
	if run.get("missed",false):return {"phase":Phase.MISSED}
	var elapsed:=maxf(0.0,now-float(run.since))
	if elapsed>=PHASE_TIME*2.0:return {"phase":Phase.FINISHED}
	var wave:=int(elapsed>=PHASE_TIME)
	var phase_elapsed:=elapsed-wave*PHASE_TIME
	var lane:float=LANES[(int(run.first_lane)+wave)%LANES.size()]
	if phase_elapsed<WARNING_TIME:
		return {"phase":Phase.WARNING,"lane":lane,"wave":wave,"remaining":WARNING_TIME-phase_elapsed}
	var travel:=clampf((phase_elapsed-WARNING_TIME)/PASS_TIME,0.0,1.0)
	return {"phase":Phase.PASSING,"lane":lane,"wave":wave,"y":lerpf(ORIGIN_Y,EXIT_Y,travel)}

static func step(run:Dictionary,at:Vector2,now:float)->Dictionary:
	if run.is_empty() or not ARENA.has_point(at):return {}
	var current:=view(run,now)
	if current.phase==Phase.PASSING and at.distance_to(Vector2(current.lane,current.y))<=HIT_RADIUS:
		return {"since":run.since,"first_lane":run.first_lane,"missed":true}
	return run
