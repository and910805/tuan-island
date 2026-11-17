extends RefCounted
const FIELD:="follow_actor"
const SECONDS:=18.0

static func active_actor(state:Dictionary,active:Variant=null)->String:
	var cow:Dictionary=state.get("livestock",{}).get("cow",{})
	var actor:=str(cow.get(FIELD,""))
	var age:=float(state.get("time",0))-float(cow.get("last_pet",-30))
	if actor.is_empty() or not state.get("picnic",false) or age<0.0 or age>=SECONDS:return ""
	var person:Dictionary=state.get("players",{}).get(actor,{})
	if person.is_empty() or person.get("region","home")!="home" or person.get("at_sea",false):return ""
	if active is Dictionary and not active.has(actor):return ""
	return actor

static func clear(state:Dictionary)->void:
	state.get("livestock",{}).get("cow",{}).erase(FIELD)
