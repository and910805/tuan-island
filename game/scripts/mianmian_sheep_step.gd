extends RefCounted
## T066 N06-4: purely local presentation of the sheep stepping out from under its eave after
## the viewer's own quiet watch. Reads only the private snapshot field own_mianmian_step_time
## (server world seconds; absent outside the home region and before the watch).
## It never moves the saved animal, collision or the feed station; it only replaces the sheep's
## draw offset for a few seconds. Reduced motion shows the finished pose straight away.

const Goals=preload("res://scripts/resident_goals.gd")
const UNDER_EAVE:=32.0 # the same offset the rain shelter uses
const ONE_STEP:=16.0 # a single stride out
const WALK_IN:=1.0
const PAUSE:=1.0
const STEP_OUT:=1.0
const HOLD:=2.5
const TOTAL:=WALK_IN+PAUSE+STEP_OUT+HOLD

## True while the watch presentation owns the sheep's offset.
static func active(snapshot:Dictionary,now:float) -> bool:
	var watched:Variant=snapshot.get("own_mianmian_step_time")
	if not (watched is float or watched is int):return false
	var since:=now-float(watched)
	return since>=0.0 and since<TOTAL

## Absolute pixel offset from the feed station; only meaningful while active().
static func offset(snapshot:Dictionary,reduced_motion:bool,now:float) -> Vector2:
	if not active(snapshot,now):return Vector2.ZERO
	if reduced_motion:return Vector2(ONE_STEP,0)
	var since:=now-float(snapshot.own_mianmian_step_time)
	if since<WALK_IN:return Vector2(UNDER_EAVE*smoothstep(0.0,1.0,since/WALK_IN),0).round()
	if since<WALK_IN+PAUSE:return Vector2(UNDER_EAVE,0)
	if since<WALK_IN+PAUSE+STEP_OUT:
		var t:=(since-WALK_IN-PAUSE)/STEP_OUT
		return Vector2(lerpf(UNDER_EAVE,ONE_STEP,smoothstep(0.0,1.0,t)),0).round()
	return Vector2(ONE_STEP,0)

## True during the moments the sheep is actually walking (for the walking frames).
static func walking(snapshot:Dictionary,reduced_motion:bool,now:float) -> bool:
	if reduced_motion or not active(snapshot,now):return false
	var since:=now-float(snapshot.own_mianmian_step_time)
	return since<WALK_IN or (since>=WALK_IN+PAUSE and since<WALK_IN+PAUSE+STEP_OUT)
