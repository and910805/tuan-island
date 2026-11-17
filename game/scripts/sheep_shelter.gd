extends RefCounted
## Local presentation of the shared rain/shelter state. No saved animal AI or
## collision is moved. The original feed station remains the interaction point.
const World=preload("res://scripts/world.gd")
const Weather=preload("res://scripts/weather.gd")
const HOME:=Vector2(World.LIVESTOCK.ANIMALS.sheep.cell)+Vector2(0.5,0.9)
const SHELTER_OFFSET:=Vector2(32,0)
const SECONDS:=2.2
var probe:=World.new()
var initialized:=false
var origin:=Vector2.ZERO
var destination:=Vector2.ZERO
var started:=-INF
var last_time:=-1.0
var status:=""

func reset()->void:
	initialized=false
	origin=Vector2.ZERO
	destination=Vector2.ZERO
	started=-INF
	last_time=-1.0
	status=""

func route_clear(snapshot:Dictionary)->bool:
	# Same terrain, natural resources, solid-object and door rules as movement.
	# can_stand is read-only; probe never steps or saves this snapshot.
	probe.state=snapshot
	probe._region="home"
	for step in range(9):
		var point:=HOME+SHELTER_OFFSET*float(step)/8.0/32.0
		if snapshot.get("ground",{}).get(World.key(Vector2i(point.floor())),{}).get("owner_visit",false):return false
		if not probe.can_stand(point):return false
	return true

func observe(snapshot:Dictionary,elapsed:float,recenter:=false)->void:
	var home:bool=str(snapshot.get("region_id","home"))=="home" and snapshot.get("picnic",false)
	var now:=float(snapshot.get("time",0.0))
	if recenter or now<last_time:reset()
	last_time=now
	var covered:bool=home and (int(snapshot.get("sheep_comfort_fixtures",0))&1)!=0
	var rainy:bool=home and Weather.at(now,"home").raining
	var clear:bool=covered and route_clear(snapshot)
	status="棚前有障礙，請留一格通道。" if covered and not clear else ("在棚下躲雨，飼料和羊毛仍在原飼料站。" if covered and rainy else "雨天會走到已搭好的遮雨棚下。")
	var next:=SHELTER_OFFSET if covered and rainy and clear else Vector2.ZERO
	if not initialized or not clear:
		origin=next
		destination=next
		initialized=true
	elif next!=destination:
		# New construction across a route must not make the animal walk through
		# a wall. Snap back to its feed station when the route becomes blocked.
		origin=offset(elapsed,false) if clear else Vector2.ZERO
		destination=next
		started=elapsed

func offset(elapsed:float,quiet:bool)->Vector2:
	if quiet or origin==destination:return destination
	var progress:=clampf((elapsed-started)/SECONDS,0.0,1.0)
	return origin.lerp(destination,smoothstep(0.0,1.0,progress)).round()

func walking(elapsed:float,quiet:bool)->bool:
	return not quiet and origin!=destination and elapsed>=started and elapsed-started<SECONDS

func walking_frame(elapsed:float,quiet:bool)->int:
	return int(floorf((elapsed-started)/0.16))%2 if walking(elapsed,quiet) else -1

func facing_right()->bool:
	return destination.x>origin.x
