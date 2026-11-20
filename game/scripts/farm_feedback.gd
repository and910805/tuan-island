extends RefCounted

const Crops=preload("res://scripts/crop_catalog.gd")
const ViewProjection=preload("res://scripts/view_projection.gd")
const DURATION:=1.4
const SPROUT_DURATION:=0.42
const RIPEN_DURATION:=1.1
const EVENTS:={"tiller":"last_till","seeder":"last_seed","harvester":"last_harvest"}
var seen:Dictionary={}
var operations:Dictionary={}
var sprouts:Dictionary={}
var ripened:Dictionary={}
var initialized:=false
var last_world_time:=0.0

func reset() -> void:
	seen.clear()
	operations.clear()
	sprouts.clear()
	ripened.clear()
	initialized=false

func observe(previous:Dictionary,snapshot:Dictionary,elapsed:float,own:="") -> void:
	var world_time:=float(snapshot.get("time",0.0))
	if world_time<last_world_time:reset()
	observe_ripening(previous.get("crops",{}),snapshot.get("crops",{}),elapsed,
		initialized and world_time>last_world_time,ViewProjection.packet_rect(previous),own)
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

func observe_ripening(previous:Dictionary,current:Dictionary,elapsed:float,advanced:bool,prior_rect:=Rect2i(),own:="") -> void:
	for cell in ripened.keys():
		var crop:Dictionary=current.get(cell,{})
		var event:Dictionary=ripened[cell]
		if elapsed-float(event.started)>=RIPEN_DURATION or crop.get("kind","")!=event.kind or float(crop.get("growth",0.0))<float(Crops.CROPS[event.kind].time):
			ripened.erase(cell)
	if not advanced:return
	for cell in current:
		var old_crop:Dictionary=previous.get(cell,{})
		var crop:Dictionary=current[cell]
		var kind:String=crop.get("kind","")
		if old_crop.get("kind","")!=kind or not Crops.CROPS.has(kind):continue
		var maturity:=float(Crops.CROPS[kind].time)
		if float(old_crop.get("growth",0.0))<maturity and float(crop.get("growth",0.0))>=maturity:
			# A newly loaded plot may have matured any time since it left view.
			if prior_rect.has_area() and not ViewProjection.exact("crops",old_crop,own) and not prior_rect.has_point(ViewProjection.cell(cell)):continue
			ripened[cell]={"kind":kind,"started":elapsed}

func ripening_age(cell:String,elapsed:float) -> float:
	if not ripened.has(cell):return -1.0
	var age:=elapsed-float(ripened[cell].started)
	return age if age>=0.0 and age<RIPEN_DURATION else -1.0

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
