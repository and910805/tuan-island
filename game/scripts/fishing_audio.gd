extends RefCounted

var context:Array=[]
var previous_fishing:Dictionary={}
var previous_time:float=-INF
var previous_caught:int=0
var observed_cast:bool=false

func reset() -> void:
	context.clear()
	previous_fishing.clear()
	previous_time=-INF
	previous_caught=0
	observed_cast=false

func update(snapshot:Dictionary,own_id:String) -> Array[String]:
	var cues:Array[String]=[]
	var player:Dictionary=snapshot.get("players",{}).get(own_id,{})
	if own_id.is_empty() or player.is_empty():
		reset()
		return cues

	var fishing:Dictionary=player.get("fishing",{})
	var time:=float(snapshot.get("time",0.0))
	var caught:=int(player.get("fish_caught",0))
	var next_context:=[own_id,snapshot.get("region_id","home"),player.get("travel_epoch",0),player.get("peer",0)]
	if next_context!=context or time<previous_time or caught<previous_caught:
		observed_cast=false
	elif not fishing.is_empty() and previous_fishing.is_empty():
		cues.append("fish_cast")
		observed_cast=true
	elif fishing.is_empty() and not previous_fishing.is_empty():
		if caught>previous_caught:cues.append("fish_catch")
		observed_cast=false
	elif fishing!=previous_fishing:
		observed_cast=false
	elif observed_cast and not fishing.is_empty():
		var ready:=float(fishing.ready)
		if previous_time<ready and time>=ready:cues.append("fish_bite")

	context=next_context
	previous_fishing=fishing.duplicate()
	previous_time=time
	previous_caught=caught
	return cues
