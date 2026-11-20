extends RefCounted
## One room's B15 event. The host supplies the clock and active player positions.
## Only the claiming right is persistent. A missed round can be retried.

const Meadow=preload("res://scripts/meadow_guardian.gd")
const VIEW:="meadow_adventure"
const ACTION:="meadow_adventure"
const WAKE:="wake"
const CALM:="calm"
const LIGHT:="light"
const WAKE_POINT:="meadow_wake"
const CALM_POINT:="meadow_calm"
const LIGHT_PREFIX:="meadow_light:"
const PULSE_SECONDS:=3.0
const ROUND_SECONDS:=100.0
const PULSE_RADIUS:=2.35
const TEAM_RADIUS:=5.0
const ROOM_RADIUS:=7.0
const LANTERN_REACH:=1.55

enum Phase { WARNING, LANTERNS, CALMING }

static func interaction_points(snapshot:Dictionary,person:Dictionary)->Dictionary:
	var personal:=Meadow.interaction_points(snapshot,person)
	if not snapshot.has(VIEW) or person.is_empty() or int(person.get(Meadow.FIELD,0))>=Meadow.ALL_TABLES:return personal
	var round:Dictionary=snapshot[VIEW]
	var at:=Vector2(person.x,person.y)
	match int(round.get("phase",-1)):
		-1:
			if at.distance_to(Meadow.FACE)<=Meadow.REACH:return {WAKE_POINT:Meadow.FACE}
		Phase.LANTERNS:
			if round.get("eligible",false):
				var points:Dictionary={}
				for index in Meadow.TABLES.size():
					var foot:=Meadow.table_feet(Meadow.TABLES[index])
					if not round.lamps[index] and at.distance_to(foot)<=LANTERN_REACH:points[LIGHT_PREFIX+str(index)]=foot
				return points
		Phase.CALMING:
			if round.get("can_calm",false) and at.distance_to(Meadow.FACE)<=Meadow.REACH:return {CALM_POINT:Meadow.FACE}
	return {}

static func begin(tokens:Array,now:float)->Dictionary:
	if tokens.is_empty():return {}
	return {
		"phase":Phase.WARNING,"pulse_at":now+PULSE_SECONDS,"ends_at":now+ROUND_SECONDS,
		"eligible":tokens.duplicate(),"required":mini(tokens.size(),Meadow.TABLES.size()),
		"lanterns":{},"calmed":{},
	}

## A missed stomp makes the player sit out. The group size requirement is fixed
## when the round begins, including if someone leaves or disconnects.
static func step(round:Dictionary,positions:Dictionary,now:float)->Dictionary:
	if round.is_empty() or now>=float(round.ends_at):return {}
	if round.phase!=Phase.WARNING:
		for token in round.lanterns.values():
			if not positions.has(token):return {}
	var present:Array=round.eligible.filter(func(token):return positions.has(token))
	if present.size()<int(round.required):return {}
	if round.phase!=Phase.WARNING or now<float(round.pulse_at):return round
	var safe:=present.filter(func(token):return positions[token].distance_to(Meadow.FACE)>=PULSE_RADIUS)
	if safe.size()<int(round.required):return {}
	var next:=round.duplicate(true)
	next.eligible=safe
	next.phase=Phase.LANTERNS
	return next

static func light(round:Dictionary,token:String,tile:Vector2i,at:Vector2)->Dictionary:
	if round.is_empty() or round.phase!=Phase.LANTERNS:return refuse("等毛球踏地後，再點亮供品台。")
	if token not in round.eligible:return refuse("等這一輪結束後，可以一起再試。")
	var index:=Meadow.TABLES.find(tile)
	if index<0 or at.distance_to(Meadow.table_feet(tile))>LANTERN_REACH:return refuse("走近一座供品台。")
	if round.lanterns.has(index):return refuse("這座供品台已經點亮。")
	var own_lit:int=round.lanterns.values().count(token)
	var lit:Dictionary=round.lanterns
	var contributors:=lit.values()
	var distinct:=0
	for member in round.eligible:
		if member in contributors:distinct+=1
	if own_lit>0 and Meadow.TABLES.size()-lit.size()==int(round.required)-distinct:
		return refuse("留一座供品台給還沒點燈的同伴。")
	var next:=round.duplicate(true)
	next.lanterns[index]=token
	if next.lanterns.size()==Meadow.TABLES.size():
		next.phase=Phase.CALMING
		return advance(next,"三盞燈都亮了。點過燈的島民，一起靠近安撫毛球。")
	return advance(next,"點亮了一盞燈。")

static func calm(round:Dictionary,token:String,tile:Vector2i,at:Vector2)->Dictionary:
	if round.is_empty() or round.phase!=Phase.CALMING:return refuse("供品台都亮了才能安撫毛球。")
	if tile!=Meadow.CENTER or at.distance_to(Meadow.FACE)>Meadow.REACH:return refuse("請靠近毛球。")
	if token not in round.lanterns.values():return refuse("毛球正聽著點過燈的島民。")
	if round.calmed.has(token):return refuse("你已經安撫過毛球，等同伴到齊。")
	var next:=round.duplicate(true)
	next.calmed[token]=true
	for member in next.lanterns.values():
		if not next.calmed.has(member):return advance(next,"毛球安靜下來了，還有同伴在路上。")
	return advance({},"毛球放鬆了。參與點燈與安撫的島民都能領謝禮。",next.calmed.keys())

static func public_view(round:Dictionary,token:String)->Dictionary:
	if round.is_empty():return {}
	var lamps:Array=[]
	for index in Meadow.TABLES.size():
		lamps.append(round.lanterns.has(index))
	return {
		"phase":round.phase,"pulse_at":round.pulse_at,"ends_at":round.ends_at,"lamps":lamps,
		"eligible":token in round.eligible,"can_calm":token in round.lanterns.values() and not round.calmed.has(token),
		"required":round.required,"calmed":round.calmed.size(),
	}

static func refuse(message:String)->Dictionary:
	return {"ok":false,"message":message}

static func advance(round:Dictionary,message:String,completed:Array=[])->Dictionary:
	return {"ok":true,"message":message,"round":round,"completed":completed}
