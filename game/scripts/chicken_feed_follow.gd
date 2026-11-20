extends RefCounted

const FIELD:="feed_follow_actor"
const EGG_SECONDS:=60.0
const SECONDS:=10.0
const RETURN_SECONDS:=2.5
const HOME:=Vector2(45.7,33.8)
const RADIUS:=1.7

static func age(state:Dictionary) -> float:
	return float(state.get("time",0))-float(state.get("animal",{}).get("egg_ready",-1))+EGG_SECONDS

static func holder(state:Dictionary,active:Variant=null) -> String:
	if state.get("region_id","home")!="home":return ""
	var actor:=str(state.get("animal",{}).get(FIELD,""))
	if actor.is_empty() or (active is Dictionary and not active.has(actor)):return ""
	var elapsed:=age(state)
	if elapsed<0.0 or elapsed>=SECONDS:return ""
	var person:Dictionary=state.get("players",{}).get(actor,{})
	return actor if not person.is_empty() and person.get("region","home")=="home" else ""
