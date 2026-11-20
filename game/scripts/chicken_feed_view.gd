extends RefCounted

const World=preload("res://scripts/world.gd")
const Follow=World.CHICKEN_FEED_FOLLOW
const SPEED:=1.45
const STOP_DISTANCE:=0.8

var probe:=World.new()
var actor:=""
var position:=Follow.HOME
var target:=Follow.HOME
var stride:=0.0
var moving:=false

func observe(snapshot:Dictionary,recenter:bool) -> void:
	actor=Follow.holder(snapshot)
	if recenter:
		position=Follow.HOME
		stride=0.0
		moving=false
	if actor.is_empty() and position==Follow.HOME:
		target=Follow.HOME
		probe.state={}
		return
	probe.state=snapshot
	if not probe.can_stand(position):position=Follow.HOME
	var wanted:=Follow.HOME
	if not actor.is_empty() and Follow.age(snapshot)<Follow.SECONDS-Follow.RETURN_SECONDS:
		var person:Dictionary=snapshot.players[actor]
		var direction:=Vector2(person.x,person.y)-Follow.HOME
		var distance:=direction.length()
		if distance>STOP_DISTANCE and distance<=Follow.RADIUS+1.4:
			wanted+=direction.normalized()*minf(Follow.RADIUS,distance-STOP_DISTANCE)
	target=position
	if clear_route(position,wanted):target=wanted
	elif clear_route(position,Follow.HOME):target=Follow.HOME
	elif actor.is_empty():
		position=Follow.HOME
		target=Follow.HOME

func clear_route(from:Vector2,to:Vector2) -> bool:
	var steps:=maxi(1,ceili(from.distance_to(to)/0.125))
	for i in range(steps+1):
		var foot:=from.lerp(to,float(i)/steps)
		if not probe.can_stand(foot):return false
	return true

func advance(delta:float) -> void:
	var next:=position.move_toward(target,delta*SPEED)
	var distance:=position.distance_to(next)
	moving=distance>0.0
	stride+=distance
	position=next

func active() -> bool:
	return not actor.is_empty() or position!=Follow.HOME

func foot(quiet:bool) -> Vector2:
	if quiet:return Follow.HOME
	var hop:=absf(sin(stride*21.0))*2.0/32.0 if moving else 0.0
	return position-Vector2(0,hop)
