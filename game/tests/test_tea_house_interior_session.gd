extends "res://tests/network_egg_basket.gd"
## Maokong tea house interior: real loopback WebSocket clients enter, exit and share chairs.

const House=World.TEA_HOUSE_INTERIOR
const Revisit=World.TEA_REVISIT
const ONE:="tea-interior-one"
const TWO:="tea-interior-two"

func finish(code:int) -> void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("TEA_HOUSE_INTERIOR_SESSION_TESTS checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func place(host:Session,token:String,tile:Vector2i) -> void:
	var person:Dictionary=host.world.state.players[token]
	person.x=tile.x+0.5
	person.y=tile.y+0.5

func pos(host:Session,token:String) -> Vector2:
	var person:Dictionary=host.world.state.players[token]
	return Vector2(person.x,person.y)

func seat_of(host:Session,token:String) -> String:
	return str(host.world.state.players[token].get(House.SEAT_KEY,""))

func seat_name(chair:Vector2i) -> String:
	return "%s:%d,%d"%[House.SIT,chair.x,chair.y]

func inside(host:Session,token:String) -> bool:
	return House.inside(host.world.state.players[token])

func seed_room(path_name:String) -> bool:
	var world:=World.new()
	world.save_path=path_name
	# The tea house opens after the festival story and the big tea order.
	world.state.festival_story_open=true
	world.state[Revisit.STATE_KEY]={"jars":{"tea_returned_jar":2,"tea_worn_jar":4},"filled":{"light":4,"deep":2},"day":1,"completed":true,"done_day":1,"claimed":{}}
	for token:String in [ONE,TWO]:
		world.add_player(token,token)
		var person:Dictionary=world.state.players[token]
		person.region=House.REGION
		person.x=House.DOOR.x+0.5
		person.y=House.DOOR.y+1.5
	var trail:Dictionary=World.TEA_CERAMICS.FRESH.duplicate(true)
	trail.merge({"intro":true,"potter":true,"reused":true,"trials":{"jar":true,"fiber":true},"tea_discussed":true,"comparison_complete":true},true)
	world.state.tea_ceramics.players[ONE]=trail
	return world.save()

func sit(host:Session,client:Session,token:String,chair:Vector2i) -> bool:
	place(host,token,House.SEAT_FEET[chair])
	return await action(client,House.SIT,chair)

func stand_up(host:Session,client:Session,token:String) -> bool:
	# Try each direction in turn so a chair beside a wall still counts as a real move.
	var released:=false
	for direction:Vector2 in [Vector2.DOWN,Vector2.UP,Vector2.LEFT,Vector2.RIGHT]:
		client.input_direction(direction)
		released=await wait_for(func():return seat_of(host,token)=="",1.5)
		client.input_direction(Vector2.ZERO)
		if released:break
	return released

func run() -> void:
	path="user://tea-house-interior-%d.json"%OS.get_process_id()
	if not check(seed_room(path),"Save an opened Maokong tea house with two islanders"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("TeaHost","tea-interior-host")
	if not check(host.host(port,"貓空",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a WebSocket host"):return
	var one:=make_session("TeaOne",ONE)
	var two:=make_session("TeaTwo",TWO)
	var address:="ws://127.0.0.1:%d"%port
	if not check(one.join(address,port,"客一",ROOM)==OK and two.join(address,port,"客二",ROOM)==OK,"Connect two clients"):return
	if not check(await wait_for(func():return not one.own_id.is_empty() and not two.own_id.is_empty()),"Both clients entered the island"):return
	var players:Dictionary=host.world.state.players

	# Contract.
	if not check(House.REGION=="maokong" and House.DOOR==Vector2i(19,22) and House.EXIT==Vector2i(63,27),"The contract names Maokong, the outer door and the inner exit"):return
	if not check(not House.PORTAL.is_empty() and not House.SIT.is_empty() and not House.SEAT_KEY.is_empty() and House.PORTAL!=House.SIT,"Portal, sit and seat key are distinct names"):return
	var chairs:Array=House.SEAT_FEET.keys()
	chairs.sort_custom(func(a:Vector2i,b:Vector2i):return a.x<b.x or (a.x==b.x and a.y<b.y))
	if not check(chairs.size()>=4,"The tea house has at least four chairs"):return
	var feet_ok:=true
	for chair:Vector2i in chairs:
		var foot:Vector2i=House.SEAT_FEET[chair]
		feet_ok=feet_ok and House.ROOM.has_point(foot) and not House.blocked(foot) and foot!=chair
	if not check(feet_ok,"Every chair has a free standing tile inside the room"):return
	var first:Vector2i=chairs[0]
	var second:Vector2i=chairs[1]

	# Base region, far from the outdoor door.
	if not check(players[ONE].region==House.REGION and House.ROOM.has_point(House.EXIT) and Vector2(House.DOOR).distance_to(Vector2(House.EXIT))>20.0,"The interior shares the base region far from the outer door"):return
	if not check(not inside(host,ONE) and not inside(host,TWO),"Both islanders start outdoors"):return

	# Outdoor players cannot reach indoor things.
	if not check(not await action(one,House.SIT,first) and seat_of(host,ONE)=="" and not inside(host,ONE),"Outdoors cannot use a chair"):return
	if not check(not await action(one,House.PORTAL,House.EXIT) and not inside(host,ONE),"Outdoors cannot address the interior exit"):return
	if not check(not await action(one,House.PORTAL,House.DOOR,"extra") and not inside(host,ONE),"The portal takes no extra"):return
	if not check(not await action(one,House.SIT,first,"extra") and seat_of(host,ONE)=="","Sitting takes no extra"):return
	place(host,ONE,House.DOOR+Vector2i(0,12))
	if not check(not await action(one,House.PORTAL,House.DOOR) and not inside(host,ONE),"A far-away islander cannot use the door"):return
	place(host,ONE,House.DOOR+Vector2i.DOWN)

	# Independent entry.
	if not check(await action(one,House.PORTAL,House.DOOR) and inside(host,ONE),"One walks into the tea house"):return
	if not check(players[ONE].region==House.REGION and House.ROOM.has_point(Vector2i(pos(host,ONE))),"One is inside the room in the base region"):return
	if not check(not inside(host,TWO) and Vector2(pos(host,TWO)).distance_to(Vector2(House.DOOR))<3.0,"Two stays outdoors by the door"):return
	if not check(not await action(one,House.PORTAL,House.DOOR) and inside(host,ONE),"Inside, the outer door is out of reach"):return
	if not check(not await action(one,Revisit.HOUSE_DISPLAY,Revisit.HOUSE_SITE) and not await action(one,Revisit.HOUSE_RECLAIM,Revisit.HOUSE_SITE),"Distance blocks the outdoor display table from inside"):return
	if not check(await action(two,House.PORTAL,House.DOOR) and inside(host,TWO) and inside(host,ONE),"Two enters on their own without moving One"):return

	# Independent exit.
	place(host,ONE,House.EXIT+Vector2i.UP)
	if not check(await action(one,House.PORTAL,House.EXIT) and not inside(host,ONE) and inside(host,TWO),"One leaves while Two stays inside"):return
	if not check(Vector2(pos(host,ONE)).distance_to(Vector2(House.DOOR))<4.0 and seat_of(host,ONE)=="","One is back outdoors beside the door"):return
	if not check(not await action(one,House.SIT,first) and seat_of(host,ONE)=="","One outdoors still cannot sit after leaving"):return
	if not check(await action(one,House.PORTAL,House.DOOR) and inside(host,ONE),"One can come back in"):return
	await create_timer(1.05).timeout

	# Chairs: one occupant each, two different chairs work.
	var live_one:Vector2
	if not check(await sit(host,one,ONE,first),"One sits in the first chair"):return
	if not check(seat_of(host,ONE)==seat_name(first) and Vector2i(pos(host,ONE))==House.SEAT_FEET[first],"One's seat key names the chair and One stands on its foot tile"):return
	var before_two:=Vector2(House.SEAT_FEET[first])+Vector2(0.5,0.5)
	place(host,TWO,House.SEAT_FEET[first])
	if not check(not await action(two,House.SIT,first) and seat_of(host,TWO)=="" and pos(host,TWO)==before_two,"Two cannot take the occupied chair and does not move"):return
	if not check(seat_of(host,ONE)==seat_name(first),"The refusal leaves One seated"):return
	if not check(await sit(host,two,TWO,second),"Two sits in a different chair at the same time"):return
	if not check(seat_of(host,TWO)==seat_name(second) and seat_of(host,ONE)==seat_name(first) and seat_of(host,ONE)!=seat_of(host,TWO),"Both islanders hold distinct seats"):return
	live_one=pos(host,ONE)
	var live_two:=pos(host,TWO)

	# Save keeps places, not seats.
	if not check(host.world.save(),"Save while both are seated"):return
	var loaded:=World.new()
	if not check(loaded.load_world(path),"Reload the room"):return
	for token:String in [ONE,TWO]:
		var saved:Dictionary=loaded.state.players[token]
		if not check(not saved.has(House.SEAT_KEY) and saved.region==House.REGION and House.inside(saved),"The saved %s is inside the tea house with no seat marker"%token):return
	if not check(Vector2(loaded.state.players[ONE].x,loaded.state.players[ONE].y)==live_one and Vector2(loaded.state.players[TWO].x,loaded.state.players[TWO].y)==live_two,"Saved positions match where each islander sat"):return
	if not check(seat_of(host,ONE)==seat_name(first) and seat_of(host,TWO)==seat_name(second),"Saving does not stand anyone up live"):return

	# Movement releases and frees the chair.
	if not check(await stand_up(host,one,ONE),"Moving releases One"):return
	if not check(seat_of(host,TWO)==seat_name(second) and inside(host,ONE),"Two keeps the seat and One is still inside"):return
	if not check(await sit(host,two,TWO,first) and seat_of(host,TWO)==seat_name(first),"The freed chair can be taken (Two moves to it)"):return
	if not check(await sit(host,one,ONE,second) and seat_of(host,ONE)==seat_name(second),"One takes the chair Two left"):return
	if not check(await stand_up(host,two,TWO),"Moving releases Two"):return
	if not check(await sit(host,two,TWO,chairs[2]) and seat_of(host,TWO)==seat_name(chairs[2]),"A third chair is also usable"):return

	# Leaving through the door releases the seat.
	place(host,ONE,House.EXIT+Vector2i.UP)
	if not check(await action(one,House.PORTAL,House.EXIT) and seat_of(host,ONE)=="" and not inside(host,ONE),"Leaving releases a held seat"):return
	if not check(seat_of(host,TWO)==seat_name(chairs[2]) and inside(host,TWO),"Two is unaffected by One leaving"):return
	finish(0)
