extends "res://tests/network_egg_basket.gd"
## N12-4: one primary occupant per Nuannuan bench, one visiting companion, private rewards.

const Springs=World.WARM_SPRINGS
const Goals=World.RESIDENT_GOALS
const RESIDENT:=World.RESIDENT_BOND.SPRING_CELL
const OWNER:="inn-seats-owner"
const GUEST:="inn-seats-guest"
const THIRD:="inn-seats-third"
const LEGACY:="inn-seats-legacy"
const NAMEPLATE:="keepsake_nuannuan_room"

func finish(code:int) -> void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("INN_STORY_SEATS_SESSION_TESTS checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func place(host:Session,token:String,tile:Vector2i) -> void:
	var person:Dictionary=host.world.state.players[token]
	person.x=tile.x+0.5
	person.y=tile.y+0.5

func seed_room(path_name:String) -> bool:
	var world:=World.new()
	world.save_path=path_name
	for token:String in [OWNER,GUEST,THIRD,LEGACY]:
		world.add_player(token,token)
		var person:Dictionary=world.state.players[token]
		person.region=Springs.REGION
		person.x=RESIDENT.x+0.5
		person.y=RESIDENT.y+0.5
		person.bonds={"nuannuan":{"points":24,"gift_day":-1,"talk_day":-1}}
	# A save from before the shared bench: the story is done, the nameplate was never recorded.
	world.state.players[LEGACY][Goals.RECORD_KEY]={"nuannuan":{"4":"stream"}}
	return world.save()

func seat_of(host:Session,token:String) -> String:
	return str(host.world.state.players[token].get(Springs.REST_SEAT_KEY,""))

func pos(host:Session,token:String) -> Vector2:
	var person:Dictionary=host.world.state.players[token]
	return Vector2(person.x,person.y)

func plates(host:Session,token:String) -> int:
	return int(host.world.state.players[token].inventory.get(Goals.keepsake_item(NAMEPLATE),0))

func story_done(host:Session,token:String) -> bool:
	return Goals.done(host.world.state.players[token],"nuannuan").has(4)

func public_view(viewer:Session,target:Session) -> Dictionary:
	return viewer.snapshot.get("players",{}).get(target.own_id,{})

func complete(host:Session,client:Session,token:String,choice:String) -> bool:
	place(host,token,RESIDENT)
	return await action(client,Goals.ACTION,RESIDENT,"nuannuan:4:%s:"%choice)

func join(host:Session,client:Session,token:String,cell:Vector2i,choice:String,stand:Vector2i) -> bool:
	place(host,token,stand)
	return await action(client,Springs.REST_JOIN,cell,choice)

func run() -> void:
	path="user://inn-story-seats-%d.json"%OS.get_process_id()
	if not check(seed_room(path),"Save four players ready for the N12-4 bench story"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("SeatHost","inn-seats-host")
	if not check(host.host(port,"礁溪",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a WebSocket host"):return
	var owner:=make_session("SeatOwner",OWNER)
	var guest:=make_session("SeatGuest",GUEST)
	var third:=make_session("SeatThird",THIRD)
	var legacy:=make_session("SeatLegacy",LEGACY)
	var address:="ws://127.0.0.1:%d"%port
	if not check(owner.join(address,port,"主人",ROOM)==OK and guest.join(address,port,"訪客",ROOM)==OK and third.join(address,port,"第三位",ROOM)==OK and legacy.join(address,port,"舊存檔",ROOM)==OK,"Connect four clients"):return
	if not check(await wait_for(func():return not owner.own_id.is_empty() and not guest.own_id.is_empty() and not third.own_id.is_empty() and not legacy.own_id.is_empty()),"All clients entered the island"):return
	var players:Dictionary=host.world.state.players
	var stream:Vector2i=Springs.REST_SEATS.stream
	var porch:Vector2i=Springs.REST_SEATS.porch
	var beside:=stream+Vector2i.DOWN

	# Helper contract.
	if not check(Springs.rest_choice("stream")=="stream" and Springs.rest_choice("friend:porch")=="porch" and Springs.rest_choice("")=="" and Springs.rest_choice("friend:nowhere")=="" and Springs.rest_choice("nowhere")=="","rest_choice reads primary and guest keys and nothing else"):return

	# Before any primary seat exists.
	if not check(not await join(host,guest,GUEST,stream,"stream",beside) and seat_of(host,GUEST)=="","A visitor cannot join an empty bench"):return
	if not check(not await action(owner,Springs.REST_REPLAY,RESIDENT) and seat_of(host,OWNER)=="","Replay is refused before the story is finished"):return
	if not check(not await action(owner,Goals.ACTION,RESIDENT,"nuannuan:4::") and not story_done(host,OWNER),"The story needs a bench choice"):return
	if not check(not await action(owner,Goals.ACTION,RESIDENT,"nuannuan:4:roof:") and not story_done(host,OWNER),"An unknown bench cannot finish the story"):return
	if not check(plates(host,OWNER)==0 and seat_of(host,OWNER)=="","Refusals give nothing and seat nobody"):return

	# First primary completion.
	if not check(await complete(host,owner,OWNER,"stream"),"Owner finishes the story at the stream bench"):return
	if not check(seat_of(host,OWNER)=="stream" and Vector2i(pos(host,OWNER))==stream,"Owner sits on the stream bench with the plain choice key"):return
	if not check(story_done(host,OWNER) and Goals.done(players[OWNER],"nuannuan")[4]=="stream","Owner's story records the chosen bench"):return
	if not check(plates(host,OWNER)==1 and Goals.keepsake_claimed(players[OWNER],NAMEPLATE),"Owner receives the nameplate exactly once"):return
	if not check(await wait_for(func():return Springs.rest_choice(str(public_view(guest,owner).get(Springs.REST_SEAT_KEY,"")))=="stream"),"Other clients see the owner seated"):return
	if not check(not public_view(guest,owner).has(Goals.RECORD_KEY) and not public_view(guest,owner).has(Goals.KEEPSAKE_KEY),"Public actors omit story progress and keepsake records"):return

	# A second primary completion at an occupied bench is atomic.
	place(host,GUEST,RESIDENT)
	var before:Dictionary=players[GUEST].duplicate(true)
	var coins:int=int(players[GUEST].coins)
	if not check(not await action(guest,Goals.ACTION,RESIDENT,"nuannuan:4:stream:"),"Occupied primary bench rejects another completion"):return
	if not check(players[GUEST]==before and int(players[GUEST].coins)==coins,"The rejected completion changes nothing for the guest"):return
	if not check(not story_done(host,GUEST) and plates(host,GUEST)==0 and seat_of(host,GUEST)=="" and plates(host,OWNER)==1 and seat_of(host,OWNER)=="stream","Neither story, reward nor seat moved"):return
	if not check(not await action(guest,Springs.REST_REPLAY,RESIDENT) and seat_of(host,GUEST)=="","Replay needs a finished story"):return

	# Invalid joins.
	if not check(not await join(host,guest,GUEST,porch,"porch",porch+Vector2i.DOWN),"No one can join an empty bench"):return
	if not check(not await join(host,guest,GUEST,porch,"stream",beside),"Place and choice must match (place elsewhere)"):return
	if not check(not await join(host,guest,GUEST,stream,"porch",beside),"Place and choice must match (choice elsewhere)"):return
	if not check(not await join(host,guest,GUEST,stream,"",beside),"A join needs a choice"):return
	if not check(not await join(host,guest,GUEST,stream,"friend:stream",beside),"The stored key is not an accepted choice"):return
	if not check(not await join(host,guest,GUEST,stream+Vector2i.RIGHT,"stream",beside),"A join must target the bench itself"):return
	var far:=RESIDENT if Vector2(RESIDENT).distance_to(Vector2(stream))>5.0 else Vector2i(stream.x,stream.y-12)
	if not check(not await join(host,guest,GUEST,stream,"stream",far) and seat_of(host,GUEST)=="","A visitor too far away cannot join"):return
	if not check(not story_done(host,GUEST) and plates(host,GUEST)==0 and players[GUEST].inventory==before.inventory,"Invalid joins leave the visitor's progress and bag unchanged"):return

	# Valid companion.
	if not check(await join(host,guest,GUEST,stream,"stream",beside),"A visitor joins the occupied stream bench"):return
	if not check(seat_of(host,GUEST)=="friend:stream" and Springs.rest_choice(seat_of(host,GUEST))=="stream","Companion uses the friend key for the same bench"):return
	var gap:=pos(host,GUEST).distance_to(pos(host,OWNER))
	if not check(gap>0.2 and gap<=1.6 and pos(host,GUEST).distance_to(Vector2(stream))<=2.0 and pos(host,GUEST).distance_to(Vector2(porch))>3.0,"Companion sits next to the owner, not on top of them"):return
	if not check(seat_of(host,OWNER)=="stream" and Vector2i(pos(host,OWNER))==stream,"Joining does not move the owner"):return
	if not check(not story_done(host,GUEST) and plates(host,GUEST)==0 and not Goals.keepsake_claimed(players[GUEST],NAMEPLATE),"Joining gives no story progress or reward"):return
	if not check(await wait_for(func():return Springs.rest_choice(str(public_view(owner,guest).get(Springs.REST_SEAT_KEY,"")))=="stream" and str(public_view(owner,guest).get(Springs.REST_SEAT_KEY))=="friend:stream"),"The owner's snapshot shows the visitor seated"):return
	if not check(guest.snapshot.get("resident_goals",{}).get("nuannuan",{}).get("4",{}).get("state")=="open" and owner.snapshot.get("resident_goals",{}).get("nuannuan",{}).get("4",{}).get("state")=="done","Each client's private story page shows only their own progress"):return

	# Third client: the bench is full, other benches are independent.
	if not check(not await join(host,third,THIRD,stream,"stream",beside) and seat_of(host,THIRD)=="","A third player cannot join a full bench"):return
	if not check(not await complete(host,third,THIRD,"stream") and not story_done(host,THIRD) and plates(host,THIRD)==0,"A third player cannot take the primary seat either"):return
	if not check(seat_of(host,OWNER)=="stream" and seat_of(host,GUEST)=="friend:stream","The two occupants are unchanged"):return
	if not check(await complete(host,third,THIRD,"porch") and seat_of(host,THIRD)=="porch" and plates(host,THIRD)==1,"Another bench is still free for its own primary story"):return
	if not check(plates(host,OWNER)==1 and plates(host,GUEST)==0,"Rewards stay with each story's owner"):return

	# Saves leave seats out.
	if not check(host.world.save(),"Save while three players are seated"):return
	var loaded:=World.new()
	if not check(loaded.load_world(path),"Reload the room"):return
	for token:String in [OWNER,GUEST,THIRD]:
		if not check(not loaded.state.players[token].has(Springs.REST_SEAT_KEY),"The seat marker is not saved for "+token):return
	if not check(Goals.done(loaded.state.players[OWNER],"nuannuan").get(4)=="stream" and Goals.done(loaded.state.players[THIRD],"nuannuan").get(4)=="porch" and not Goals.done(loaded.state.players[GUEST],"nuannuan").has(4),"Story progress is saved privately"):return
	if not check(int(loaded.state.players[OWNER].inventory.get(Goals.keepsake_item(NAMEPLATE),0))==1 and Goals.keepsake_claimed(loaded.state.players[OWNER],NAMEPLATE) and not Goals.keepsake_claimed(loaded.state.players[GUEST],NAMEPLATE),"The nameplate record is saved for the owner only"):return
	if not check(seat_of(host,OWNER)=="stream" and seat_of(host,GUEST)=="friend:stream","Saving does not stand anyone up in the live room"):return

	# Movement releases.
	guest.input_direction(Vector2.DOWN)
	if not check(await wait_for(func():return seat_of(host,GUEST)==""),"Moving releases the companion"):return
	guest.input_direction(Vector2.ZERO)
	if not check(seat_of(host,OWNER)=="stream" and await wait_for(func():return str(public_view(owner,guest).get(Springs.REST_SEAT_KEY,""))==""),"The owner stays seated and sees the visitor stand"):return
	if not check(await join(host,third,THIRD,stream,"stream",beside),"The freed companion place can be used again"):return
	if not check(seat_of(host,THIRD)=="friend:stream" and plates(host,THIRD)==1,"The third player joins as a companion without a second reward"):return
	third.input_direction(Vector2.DOWN)
	if not check(await wait_for(func():return seat_of(host,THIRD)==""),"Moving releases the new companion"):return
	third.input_direction(Vector2.ZERO)

	# Legacy replay: finished before the nameplate record existed.
	if not check(not await action(legacy,Springs.REST_REPLAY,RESIDENT) and seat_of(host,LEGACY)=="","Replay cannot take an occupied primary bench"):return
	owner.input_direction(Vector2.DOWN)
	if not check(await wait_for(func():return seat_of(host,OWNER)==""),"Moving releases the owner"):return
	owner.input_direction(Vector2.ZERO)
	place(host,LEGACY,RESIDENT)
	var bag:Dictionary=players[LEGACY].inventory.duplicate(true)
	if not check(await action(legacy,Springs.REST_REPLAY,RESIDENT),"A legacy finished story can replay at its bench"):return
	if not check(seat_of(host,LEGACY)=="stream" and Vector2i(pos(host,LEGACY))==stream,"Replay seats the legacy player as primary"):return
	if not check(players[LEGACY].inventory==bag and plates(host,LEGACY)==0 and not Goals.keepsake_claimed(players[LEGACY],NAMEPLATE),"Replay grants no reward"):return
	if not check(not await complete(host,owner,OWNER,"pool") and plates(host,OWNER)==1 and Goals.done(players[OWNER],"nuannuan").get(4)=="stream" and seat_of(host,OWNER)=="","The owner cannot finish the story again for a second reward"):return
	if not check(await join(host,guest,GUEST,stream,"stream",beside) and seat_of(host,GUEST)=="friend:stream" and plates(host,GUEST)==0,"A visitor may also join a replay seat"):return
	if not check(not players.values().any(func(person:Dictionary):return person.get(Springs.REST_SEAT_KEY,"") in ["pool","friend:pool"]),"The unused bench stays empty"):return
	finish(0)
