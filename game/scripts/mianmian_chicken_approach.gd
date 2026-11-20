extends RefCounted
## T066 N06-1: purely local draw offset for the ranch chicken after the viewer's own first feed.
##
## Reads only the private snapshot field own_mianmian_feed_time (server world seconds; absent
## outside the home region and before the first feed), so another player's feed time is never
## used. It never changes collision, position authority or saved state.
## Timeline from the feed: a short pause, three small steps toward the viewer, a rest, then
## a gentle return. Reduced motion keeps the chicken at its normal place.

const Goals=preload("res://scripts/resident_goals.gd")
const TILE:=32.0
const PAUSE:=1.0
const STEPS:=3
const STEP_SECONDS:=0.9
const HOLD:=2.5
const RETURN_SECONDS:=2.0
const MAX_PIXELS:=14.0 # under half a tile

## chicken_feet: the chicken's resting position in home tiles. Returns a pixel offset.
static func shift(snapshot:Dictionary,own_id:String,chicken_feet:Vector2,reduced_motion:bool,now:float) -> Vector2:
	if reduced_motion:return Vector2.ZERO
	var fed:Variant=snapshot.get("own_mianmian_feed_time")
	if not (fed is float or fed is int):return Vector2.ZERO
	var players:Variant=snapshot.get("players")
	if not players is Dictionary:return Vector2.ZERO
	var person:Variant=players.get(own_id)
	if not person is Dictionary or not (person.get("x") is float or person.get("x") is int) or not (person.get("y") is float or person.get("y") is int):return Vector2.ZERO
	var to_player:=Vector2(float(person.x),float(person.y))-chicken_feet
	if to_player.length()<0.75:return Vector2.ZERO # already close; do not crowd the avatar
	var since:=now-float(fed)
	var walking_end:=PAUSE+STEPS*STEP_SECONDS
	var end:=walking_end+HOLD+RETURN_SECONDS
	if since<PAUSE or since>=end:return Vector2.ZERO
	var amount:=1.0
	if since<walking_end:
		amount=float(floori((since-PAUSE)/STEP_SECONDS)+1)/float(STEPS)
	elif since>=walking_end+HOLD:
		amount=1.0-(since-walking_end-HOLD)/RETURN_SECONDS
	var hop:=0.0
	if since<walking_end:hop=-absf(sin((since-PAUSE)/STEP_SECONDS*PI))*3.0
	return to_player.normalized()*MAX_PIXELS*clampf(amount,0.0,1.0)+Vector2(0,hop)
