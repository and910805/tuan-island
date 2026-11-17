extends RefCounted

const DURATION:=1.4
const SPROUT_DURATION:=0.42
const EVENTS:={"tiller":"last_till","seeder":"last_seed","harvester":"last_harvest"}
var seen:Dictionary={}
var operations:Dictionary={}
var sprouts:Dictionary={}
var initialized:=false
var last_world_time:=0.0

func reset() -> void:
	seen.clear()
	operations.clear()
	sprouts.clear()
	initialized=false

func observe(previous:Dictionary,snapshot:Dictionary,elapsed:float) -> void:
	var world_time:=float(snapshot.get("time",0.0))
	if world_time<last_world_time:reset()
	for cell in sprouts.keys():
		if elapsed-float(sprouts[cell])>=SPROUT_DURATION:sprouts.erase(cell)
	for actor in operations.keys():
		if not snapshot.get("players",{}).has(actor) or elapsed-float(operations[actor].started)>=DURATION:
			operations.erase(actor)
	for actor in snapshot.get("players",{}):
		var player:Dictionary=snapshot.players[actor]
		var known:bool=seen.has(actor)
		var timestamps:Dictionary=seen.get(actor,{})
		var newest:Dictionary={}
		for kind in EVENTS:
			var event:Dictionary=player.get(EVENTS[kind],{})
			if event.is_empty():continue
			var stamp:=float(event.at)
			if stamp<=float(timestamps.get(kind,-1.0)):continue
			timestamps[kind]=stamp
			# Joining players can carry historical operations. Observe the baseline once.
			if not initialized or not known or event.get("cells",[]).is_empty():continue
			if kind=="seeder":
				for cell in event.cells:mark_sprout(cell,previous,snapshot,elapsed)
			if newest.is_empty() or stamp>float(newest.event.at):newest={"kind":kind,"event":event}
		seen[actor]=timestamps
		if newest.is_empty():continue
		var event:Dictionary=newest.event
		var items:Dictionary={}
		for cell in event.cells:
			var prior:Dictionary=previous.get("crops",{}).get(cell,{})
			if newest.kind=="harvester":items[cell]=prior.get("kind","")
			if newest.kind=="seeder":items[cell]=event.get("kind","")+"_seed"
		operations[actor]={"kind":newest.kind,"started":elapsed,"center":Vector2i(event.x,event.y),
			"cells":event.cells.duplicate(),"items":items,"origin":Vector2(player.x,player.y)}
	initialized=true
	last_world_time=world_time

func mark_sprout(cell:String,previous:Dictionary,snapshot:Dictionary,elapsed:float) -> void:
	var before:Dictionary=previous.get("crops",{}).get(cell,{})
	var after:Dictionary=snapshot.get("crops",{}).get(cell,{})
	if str(before.get("kind","")).is_empty() and not str(after.get("kind","")).is_empty():
		sprouts[cell]=elapsed

func sprout_offset(cell:String,elapsed:float,reduced_motion:bool) -> Vector2:
	if reduced_motion or not sprouts.has(cell):return Vector2.ZERO
	var age:=elapsed-float(sprouts[cell])
	if age<0.0 or age>=SPROUT_DURATION:return Vector2.ZERO
	# Land on the soil in whole pixels, keeping the ground and camera fixed.
	var remaining:=1.0-age/SPROUT_DURATION
	return Vector2(0,-roundf(7.0*remaining*remaining))

func active(actor:String,elapsed:float) -> Dictionary:
	var operation:Dictionary=operations.get(actor,{})
	if operation.is_empty() or elapsed-float(operation.started)>=DURATION:return {}
	return operation
