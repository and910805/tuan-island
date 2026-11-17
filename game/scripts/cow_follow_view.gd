extends RefCounted
## Short care response, like the sheep shelter. The feed station stays usable.
const World=preload("res://scripts/world.gd")
const HOME:=Vector2(World.LIVESTOCK.ANIMALS.cow.cell)+Vector2(0.5,0.9)
const RADIUS:=2.0
const SPEED:=0.65
var probe:=World.new()
var initialized:=false
var position:=HOME
var destination:=HOME
var moving:=false
var face_right:=false
var gait:=0.0
var status:="摸頭後會在飼料站附近慢慢跟幾步。"

func reset()->void:
	initialized=false
	position=HOME
	destination=HOME
	moving=false
	gait=0.0

func clear_route(from:Vector2,to:Vector2)->bool:
	var steps:=maxi(1,ceili(from.distance_to(to)/0.125))
	for i in range(steps+1):
		var point:=from.lerp(to,float(i)/steps)
		# The feet occupy a tile-wide strip; the head can overhang like other sprites.
		for dx in [-0.25,0.0,0.25]:
			var foot:=point+Vector2(dx,0)
			if probe.state.get("ground",{}).get(World.key(Vector2i(foot.floor())),{}).get("owner_visit",false) or not probe.can_stand(foot):return false
	return true

func observe(snapshot:Dictionary,recenter:=false)->void:
	if recenter:reset()
	probe.state=snapshot
	probe._region="home"
	var actor:=World.COW_CARE.active_actor(snapshot)
	var wanted:=HOME
	if snapshot.get("region_id","home")=="home" and not actor.is_empty():
		var person:Dictionary=snapshot.players[actor]
		var toward:=Vector2(person.x,person.y)-HOME
		if toward.length()<=RADIUS+1.0:
			wanted=HOME+toward.normalized()*minf(RADIUS,maxf(0.0,toward.length()-0.85))
	var origin:=position if initialized else HOME
	if not clear_route(origin,wanted):
		wanted=HOME if clear_route(origin,HOME) else origin
		status="前面有障礙，奶糖牛會等在安全的位置。"
	else:status="正在飼料站附近陪你散步；牛奶仍在原站領取。" if wanted!=HOME else "摸頭後會在飼料站附近慢慢跟幾步。"
	destination=wanted
	if not initialized:
		position=destination
		initialized=true

func advance(delta:float)->void:
	moving=false
	if not initialized or position.distance_to(destination)<0.01:return
	var next:=position.move_toward(destination,maxf(0.0,delta)*SPEED)
	if not clear_route(position,next):
		destination=position
		return
	face_right=next.x>position.x if not is_equal_approx(next.x,position.x) else face_right
	gait+=position.distance_to(next)
	moving=true
	position=next

func offset(quiet:bool)->Vector2:
	return ((destination if quiet else position)-HOME)*32.0

func walking_frame(quiet:bool)->int:
	return int(gait/0.12)%2 if moving and not quiet else -1
