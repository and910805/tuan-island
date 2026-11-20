extends RefCounted
## B4 personal adventure. The statue telegraphs two perpendicular strikes.
const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
const KEY:="guardian_trial"
const START:="start"
const FINISH:="finish"
const ARENA:=Rect2(31.0,10.0,7.0,4.0)
const WIDTH:=2.0
const WARNING:=1.9
const IMPACT:=0.55
const FOOT_MARGIN:=0.16

enum Phase { WARNING, IMPACT, SAFE, MISSED }

static func begin(at:Vector2,now:float)->Dictionary:
	return warning(0,at,now)

static func warning(attack:int,at:Vector2,now:float)->Dictionary:
	var bounds:Rect2
	if attack==0:
		var x:=clampf(at.x-WIDTH*0.5,ARENA.position.x,ARENA.end.x-WIDTH)
		bounds=Rect2(x,ARENA.position.y,WIDTH,ARENA.size.y)
	else:
		var y:=clampf(at.y-WIDTH*0.5,ARENA.position.y,ARENA.end.y-WIDTH)
		bounds=Rect2(ARENA.position.x,y,ARENA.size.x,WIDTH)
	return {"phase":Phase.WARNING,"attack":attack,"strike_at":now+WARNING,"bounds":bounds}

static func step(run:Dictionary,at:Vector2,now:float)->Dictionary:
	if run.is_empty() or not ARENA.has_point(at):return {}
	match int(run.phase):
		Phase.WARNING:
			if now<float(run.strike_at):return run
			var danger:Rect2=run.bounds
			if danger.grow(FOOT_MARGIN).has_point(at):return {"phase":Phase.MISSED}
			var next:=run.duplicate()
			next.phase=Phase.IMPACT
			return next
		Phase.IMPACT:
			if now<float(run.strike_at)+IMPACT:return run
			return warning(1,at,now) if int(run.attack)==0 else {"phase":Phase.SAFE}
	return run

static func view(run:Dictionary)->Dictionary:
	if run.is_empty():return {}
	var out:Dictionary={"phase":run.phase}
	if run.phase in [Phase.WARNING,Phase.IMPACT]:
		var danger:Rect2=run.bounds
		out["bounds"]=[danger.position.x,danger.position.y,danger.size.x,danger.size.y]
		out["attack"]=run.attack
		out["strike_at"]=run.strike_at
	return out
