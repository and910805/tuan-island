extends RefCounted

const CAST_DURATION := 0.42
const LANDING_DURATION := 0.30
const CATCH_DURATION := 0.85
const CANCEL_DURATION := 0.38
const SPECIES := preload("res://scripts/collections.gd").FISH

var region_id := ""
var local_id := ""
var last_world_time := -INF
var actors:Dictionary={}

func reset() -> void:
	region_id=""
	local_id=""
	last_world_time=-INF
	actors.clear()

func update(snapshot:Dictionary,player_id:String,elapsed:float) -> void:
	var region:=str(snapshot.get("region_id","home"))
	var world_time:=float(snapshot.get("time",0.0))
	if region!=region_id or player_id!=local_id or world_time<last_world_time:
		reset()
		region_id=region
		local_id=player_id
	last_world_time=world_time
	var players:Dictionary=snapshot.get("players",{})
	for actor_id in actors.keys():
		if not players.has(actor_id):actors.erase(actor_id)
	for actor_id in players:
		var player:Dictionary=players[actor_id]
		var fishing:Dictionary=player.get("fishing",{})
		var epoch:=int(player.get("travel_epoch",0))
		var peer:=int(player.get("peer",0))
		var caught:=int(player.get("fish_caught",0))
		var inventory:Dictionary=player.get("inventory",{})
		var fish_counts:Dictionary={}
		for fish:String in SPECIES:
			if inventory.has(fish):fish_counts[fish]=int(inventory[fish])
		var previous:Dictionary=actors.get(actor_id,{})
		var event:Dictionary={}
		var bite_started:=-INF
		if not previous.is_empty() and previous.epoch==epoch and previous.peer==peer and caught>=previous.caught:
			var old_fishing:Dictionary=previous.fishing
			if fishing.is_empty()!=old_fishing.is_empty() or (not fishing.is_empty() and (fishing.ready!=old_fishing.ready or target_of(fishing)!=target_of(old_fishing))):
				if not fishing.is_empty():
					event=make_event("cast",fishing,elapsed)
				elif not old_fishing.is_empty():
					event=make_event("catch" if caught>previous.caught else "cancel",old_fishing,elapsed)
					if event.phase=="catch":event.fish=added_species(previous.fish_counts,fish_counts)
			else:
				event=previous.event
				bite_started=float(previous.bite_started)
		if not fishing.is_empty() and world_time>=float(fishing.ready) and not is_finite(bite_started):
			bite_started=elapsed
		actors[actor_id]={"fishing":fishing.duplicate(),"epoch":epoch,"peer":peer,"caught":caught,"event":event,"fish_counts":fish_counts,"bite_started":bite_started}

func state_for(actor_id:String,world_time:float,elapsed:float) -> Dictionary:
	var actor:Dictionary=actors.get(actor_id,{})
	if actor.is_empty():return {}
	var event:Dictionary=actor.event
	if not event.is_empty():
		var age:=maxf(0.0,elapsed-float(event.started))
		var duration:float={"cast":CAST_DURATION,"catch":CATCH_DURATION,"cancel":CANCEL_DURATION}[event.phase]
		if age<duration:return {"phase":event.phase,"target":event.target,"age":age,"fish":event.get("fish","")}
	var fishing:Dictionary=actor.fishing
	if fishing.is_empty():return {}
	var phase:="ready" if world_time>=float(fishing.ready) else "wait"
	var state:={"phase":phase,"target":target_of(fishing),"age":0.0}
	if phase=="ready":
		state.age=maxf(0.0,elapsed-float(actor.bite_started)) if is_finite(float(actor.bite_started)) else 0.0
	if phase=="wait" and event.get("phase")=="cast":
		var landing_age:=elapsed-float(event.started)-CAST_DURATION
		if landing_age<LANDING_DURATION:state.landing_age=maxf(landing_age,0.0)
	return state

static func added_species(before:Dictionary,after:Dictionary) -> String:
	var added:=""
	for fish:String in SPECIES:
		if int(after.get(fish,0))<=int(before.get(fish,0)):continue
		if not added.is_empty():return ""
		added=fish
	return added

static func make_event(phase:String,fishing:Dictionary,elapsed:float) -> Dictionary:
	return {"phase":phase,"target":target_of(fishing),"started":elapsed}

static func target_of(fishing:Dictionary) -> Vector2:
	return Vector2(float(fishing.x)+0.5,float(fishing.y)+0.5)
