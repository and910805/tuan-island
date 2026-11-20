extends "res://tests/network_egg_basket.gd"

const Workshop=preload("res://scripts/pottery_workshop_interior.gd")
const Tea=World.TEA_CERAMICS
const POTTER:="pottery-room-potter"
const GUEST:="pottery-room-guest"

func finish(code:int) -> void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("POTTERY_WORKSHOP_SESSION checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func seed_workshop() -> bool:
	var world:=World.new()
	world.save_path=path
	world.state.board=true
	world.state.picnic=true
	world.state.chapter_one.shipped=true
	world.state.chapter_one.watered=true
	for token in [POTTER,GUEST]:
		world.add_player(token,token)
		var person:Dictionary=world.state.players[token]
		person.region=Workshop.REGION
		person.x=Workshop.DOOR.x+0.5
		person.y=Workshop.DOOR.y+1.5
		var record:Dictionary=Tea.FRESH.duplicate(true)
		record.intro=true
		record.potter=true
		world.state.tea_ceramics.players[token]=record
	world.state.players[POTTER].inventory.clay=2
	world.state.players[GUEST].inventory.clay=Tea.POT_CLAY+1
	world.state.players[GUEST].inventory.tea_spent_jar=1
	return world.save()

func place(host:Session,token:String,tile:Vector2i) -> void:
	var person:Dictionary=host.world.state.players[token]
	person.x=tile.x+0.5
	person.y=tile.y+0.5

func reflected_inside(client:Session) -> bool:
	return Workshop.inside(client.snapshot.get("players",{}).get(client.own_id,{}))

func client_job(client:Session) -> Dictionary:
	return client.snapshot.get("tea_ceramics",{}).get("own_record",{}).get("kiln",{})

func run() -> void:
	path="user://pottery-workshop-network-%d.json"%OS.get_process_id()
	if not check(seed_workshop(),"Persist two chapter-complete visitors at the workshop entrance"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("WorkshopHost","workshop-network-host")
	if not check(host.host(port,"鶯歌",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start the WebSocket workshop host"):return
	var potter:=make_session("WorkshopPotter",POTTER)
	var guest:=make_session("WorkshopGuest",GUEST)
	var address:="ws://127.0.0.1:%d"%port
	if not check(potter.join(address,port,"入窯",ROOM)==OK and guest.join(address,port,"來客",ROOM)==OK,"Join from two clients"):return
	if not check(await wait_for(func():return not potter.own_id.is_empty() and not guest.own_id.is_empty()),"Both profiles load"):return

	var kiln:=Workshop.station_cell("kiln")
	if not check(not await action(potter,"tea_fire",kiln),"The indoor kiln is out of range outside"):return
	if not check(await action(potter,Workshop.PORTAL,Workshop.DOOR),"The potter enters the workshop"):return
	if not check(await wait_for(func():return reflected_inside(potter)) and not reflected_inside(guest),"Only the entering client moves indoors"):return
	if not check(not await action(potter,"tea_fire",kiln),"The kiln is also out of range from the indoor entrance"):return
	if not check(await action(guest,Workshop.PORTAL,Workshop.DOOR),"The guest can independently enter"):return
	if not check(await wait_for(func():return reflected_inside(guest)),"The guest receives the indoor snapshot"):return
	place(host,POTTER,kiln+Vector2i.DOWN)
	place(host,GUEST,kiln+Vector2i.DOWN)
	if not check(await action(potter,"tea_fire",kiln),"Start a batch from the indoor kiln over WebSocket"):return
	if not check(await wait_for(func():return not client_job(potter).is_empty()),"The firing job arrives in the owner's world snapshot"):return
	if not check(client_job(guest).is_empty() and not await action(guest,"tea_fire_take",kiln),"Another visitor cannot see or claim the private batch"):return

	place(host,POTTER,Workshop.EXIT+Vector2i.UP)
	if not check(await action(potter,Workshop.PORTAL,Workshop.EXIT),"The owner walks out before the job completes"):return
	if not check(await wait_for(func():return not reflected_inside(potter)) and reflected_inside(guest),"The guest remains indoors"):return
	place(host,POTTER,Tea.KILN+Vector2i.DOWN)
	host.world.step(Tea.KILN_SECONDS,true)
	if not check(await action(potter,"tea_fire_take",Tea.KILN),"The outdoor kiln collects the same job"):return
	var bag:Dictionary=host.world.state.players[POTTER].inventory
	if not check(int(bag.get("tea_jar",0))==1 and int(bag.get("clay",0))==0,"The shared batch consumes two clay and yields one jar"):return
	if not check(not await action(potter,"tea_fire_take",Tea.KILN),"The collected batch can only be claimed once"):return
	if not check(await action(guest,"tea_repair",kiln),"The indoor kiln can repair a spent jar"):return
	host.world.step(Tea.KILN_SECONDS,true)
	if not check(await action(guest,"tea_fire_take",kiln),"The repaired jar can be collected indoors"):return
	if not check(await action(guest,"tea_fire_pot",kiln),"The indoor kiln also accepts the flower-pot recipe"):return
	host.world.step(Tea.POT_SECONDS,true)
	if not check(await action(guest,"tea_fire_take",kiln),"The finished pot can be collected indoors"):return
	var guest_bag:Dictionary=host.world.state.players[GUEST].inventory
	if not check(int(guest_bag.get("tea_jar",0))==1 and int(guest_bag.get("flower_pot",0))==1 and int(guest_bag.get("tea_spent_jar",0))==0 and int(guest_bag.get("clay",0))==0,"Both indoor recipes deliver their own items and consume the correct materials"):return
	var reopened:=World.new()
	if not check(host.world.save() and reopened.load_world(path),"Save and load after collecting"):return
	if not check(Workshop.inside(reopened.state.players[GUEST]) and not Workshop.inside(reopened.state.players[POTTER]),"Indoor and outdoor positions survive reloading"):return
	finish(0)
