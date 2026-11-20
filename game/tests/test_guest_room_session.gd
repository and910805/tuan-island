extends "res://tests/network_egg_basket.gd"
## N12-3: two isolated WebSocket clients share one finished home room and each registers
## it independently through the real GUEST_ROOM_ACTION.
## Fixture (authored, not played): the 3x3 room shell plus an OWNER-placed generic bed,
## lamp and chair, and both players at Warm Warm's trust stage. The guest's qualifying
## contribution is a mushroom stool placed through the normal networked `build` action.

const Goals=World.RESIDENT_GOALS
const Rooms=preload("res://scripts/house_rooms.gd")
const OWNER:="guest-room-owner"
const GUEST:="guest-room-guest"
const ORIGIN:=Vector2i(24,34)
const INTERIOR:=ORIGIN+Vector2i(1,1)
const BED:=ORIGIN+Vector2i(3,3)
const LAMP:=ORIGIN+Vector2i(3,1)
const CHAIR:=ORIGIN+Vector2i(1,3)
const STOOL:=ORIGIN+Vector2i(2,3)
const STOOL_KIND:=World.INDUSTRY.MUSHROOM_STOOL

func finish(code:int) -> void:
	Engine.time_scale=1.0
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("GUEST_ROOM_SESSION_TESTS checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func piece(kind:String,owner:String) -> Dictionary:
	var result:={"type":kind,"owner":owner,"items":{}}
	if kind=="door":result.open=false
	return result

func seed_room() -> bool:
	var world:=World.new()
	world.save_path=path
	for y in 5:
		for x in 5:
			var tile:=World.key(ORIGIN+Vector2i(x,y))
			world.state.removed[tile]=true
			if x in [1,2,3] and y in [1,2,3]:
				world.state.ground[tile]=piece("floor",OWNER)
				world.state.roofs[tile]=piece("roof",OWNER)
			else:
				world.state.objects[tile]=piece("door" if Vector2i(x,y)==Vector2i(1,0) else "wall",OWNER)
	world.state.objects[World.key(BED)]=piece("bed",OWNER)
	world.state.objects[World.key(LAMP)]=piece("lamp",OWNER)
	world.state.objects[World.key(CHAIR)]=piece("chair",OWNER)
	for token:String in [OWNER,GUEST]:
		world.add_player(token,token)
		var person:Dictionary=world.state.players[token]
		person.x=INTERIOR.x+0.5
		person.y=INTERIOR.y+0.5
		person.bonds={"nuannuan":{"points":14,"gift_day":-1,"talk_day":-1}}
	# Supply exactly the real build recipe (twice over) for the guest's stool.
	var supplies:Dictionary={}
	for item:String in World.BUILD[STOOL_KIND]:
		if item!="name":supplies[item]=int(World.BUILD[STOOL_KIND][item])*2
	world.state.players[GUEST].inventory.merge(supplies,true)
	return world.save()

func stand(host:Session,token:String,tile:Vector2i) -> void:
	var person:Dictionary=host.world.state.players[token]
	person.x=tile.x+0.5
	person.y=tile.y+0.5

func own_room(client:Session) -> bool:
	return client.snapshot.get("own_guest_room",false)==true

func saved_flag(token:String) -> Variant:
	var loaded:=World.new()
	if not loaded.load_world(path):return null
	return loaded.state.players[token].get(Goals.GUEST_ROOM_KEY,false)

func run() -> void:
	path="user://guest-room-network-%d.json"%OS.get_process_id()
	if not check(seed_room(),"Save a finished shared room owned by the first player"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var address:="ws://127.0.0.1:%d"%port
	var host:=make_session("RoomHost","guest-room-host")
	if not check(host.host(port,"客房",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a WebSocket host"):return
	host.set_physics_process(false)
	var owner:=make_session("RoomOwner",OWNER)
	var guest:=make_session("RoomGuest",GUEST)
	if not check(owner.join(address,port,"屋主",ROOM)==OK and guest.join(address,port,"客人",ROOM)==OK,"Connect both clients"):return
	if not check(await wait_for(func():return owner.snapshot.has("players") and guest.snapshot.has("players") and not owner.own_id.is_empty() and not guest.own_id.is_empty()),"Both clients entered the island"):return
	var players:Dictionary=host.world.state.players
	var objects:Dictionary=host.world.state.objects
	var room_before:=var_to_str(objects)
	var room:=Rooms.inspect(host.world.state,INTERIOR)
	if not check(room.complete,"Fixture room is a complete enclosure"):return
	if not check(Rooms.guest_room(host.world.state,room,INTERIOR,OWNER).ready,"Fixture satisfies the owner's contribution rule"):return
	if not check(not Rooms.guest_room(host.world.state,room,INTERIOR,GUEST).ready,"Fixture gives the guest no contribution yet"):return

	# 1. Guest has furnished nothing: rejected, room and position untouched.
	stand(host,GUEST,INTERIOR)
	var guest_x:float=players[GUEST].x
	var guest_y:float=players[GUEST].y
	if not check(not await action(guest,Goals.GUEST_ROOM_ACTION,INTERIOR),"Server rejects a guest without a furniture contribution"):return
	if not check(var_to_str(objects)==room_before,"Rejected registration leaves every room object intact"):return
	if not check(players[GUEST].x==guest_x and players[GUEST].y==guest_y and Vector2i(floori(players[GUEST].x),floori(players[GUEST].y))==INTERIOR,"Rejected registration leaves the guest exactly where they stood"):return
	if not check(not players[GUEST].has(Goals.GUEST_ROOM_KEY) and not own_room(guest),"Rejection records no progress"):return

	# 2. Owner registers; only the owner's snapshot and save show it.
	stand(host,OWNER,INTERIOR)
	if not check(await action(owner,Goals.GUEST_ROOM_ACTION,INTERIOR),"Owner registers the room"):return
	if not check(await wait_for(func():return own_room(owner)),"Owner's snapshot shows the registration"):return
	if not check(not own_room(guest) and not players[GUEST].has(Goals.GUEST_ROOM_KEY),"Guest's snapshot and record do not inherit it"):return
	for client:Session in [owner,guest]:
		for person:Dictionary in client.snapshot.get("players",{}).values():
			if not check(not person.has(Goals.GUEST_ROOM_KEY),"Public player entries omit private room progress"):return
	if not check(not await action(owner,Goals.GUEST_ROOM_ACTION,INTERIOR),"Owner cannot register twice"):return
	if not check(host.world.save() and saved_flag(OWNER)==true and saved_flag(GUEST)==false,"Save holds only the owner's registration"):return

	# 3. Guest contributes a precisely placed distinct themed piece through normal build.
	if not check(not objects.has(World.key(STOOL)),"The stool tile starts empty"):return
	var wood:int=int(players[GUEST].inventory.wood)
	stand(host,GUEST,INTERIOR)
	var built:=await action(guest,"build",STOOL,STOOL_KIND)
	var latest:String=str(notices[guest].back()) if not notices[guest].is_empty() else "no notice"
	if not check(built,"Guest builds a mushroom stool in the room; latest notice: "+latest):return
	var placed:Dictionary=objects.get(World.key(STOOL),{})
	if not check(placed.get("type")==STOOL_KIND and placed.get("owner")==GUEST,"Stool is a distinct mushroom_cap_stool owned by the guest at the exact tile"):return
	if not check(int(players[GUEST].inventory.wood)<wood,"Building the stool consumed the guest's materials"):return
	for kind:Array in [[BED,"bed"],[LAMP,"lamp"],[CHAIR,"chair"]]:
		if not check(objects[World.key(kind[0])].type==kind[1] and objects[World.key(kind[0])].owner==OWNER,"Owner's %s is unchanged"%kind[1]):return
	room=Rooms.inspect(host.world.state,INTERIOR)
	if not check(room.complete and Rooms.guest_room(host.world.state,room,INTERIOR,GUEST).ready,"The guest's stool qualifies the room for them"):return

	# 4. Guest registers independently; both persist.
	stand(host,GUEST,INTERIOR)
	if not check(await action(guest,Goals.GUEST_ROOM_ACTION,INTERIOR),"Guest registers after contributing"):return
	if not check(await wait_for(func():return own_room(guest) and own_room(owner)),"Each client sees its own registration"):return
	if not check(host.world.save() and saved_flag(OWNER)==true and saved_flag(GUEST)==true,"Save holds both registrations"):return
	var loaded:=World.new()
	if not check(loaded.load_world(path) and loaded.state.objects.get(World.key(STOOL),{}).get("type")==STOOL_KIND,"The guest's stool survives reload"):return
	finish(0)
