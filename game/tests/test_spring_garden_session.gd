extends "res://tests/network_egg_basket.gd"
## Spring Garden Day over a real loopback dedicated WS room with two clients (alpha/beta).
## DISCLOSURE: positions are set by writing x/y on the dedicated server's world fixture
## (host.world.state.players[token]); clients do not walk between the stations here, so this
## test does not prove the walking route is unobstructed. Server-side reach/cell rules are
## still exercised for real through the network action path.
const G=preload("res://scripts/spring_garden_day.gd")
const ALPHA:="spring-garden-alpha"
const BETA:="spring-garden-beta"
const SPRING_TIME:=2880.0   # day index 2 -> spring
const WINTER_TIME:=64800.0  # day index 45 -> winter
var host:Session
var address:=""

func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SPRING_GARDEN_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)

func own(session:Session)->Dictionary:
	return session.snapshot.get("own_spring_garden",{})

func place(token:String,cell:Vector2i)->void:
	var person:Dictionary=host.world.state.players[token]
	person.x=cell.x+0.5
	person.y=cell.y+0.5

func spot(id:String)->Vector2i:
	return G.SPOTS[id].cell

func view_is(session:Session,active:bool,mask:int,completed:bool)->bool:
	var view:=own(session)
	return not view.is_empty() and bool(view.get("active",not active))==active and int(view.get("mask",-1))==mask and bool(view.get("completed",not completed))==completed

func wait_view(session:Session,active:bool,mask:int,completed:bool)->bool:
	return await wait_for(func():return view_is(session,active,mask,completed))

func stamp(session:Session,token:String,id:String)->bool:
	place(token,spot(id))
	return await action(session,G.ACTION,spot(id),id)

func board(session:Session,token:String,extra:String)->bool:
	place(token,G.BOARD)
	return await action(session,G.ACTION,G.BOARD,extra)

func economy(token:String)->Dictionary:
	var person:Dictionary=host.world.state.players[token]
	return {"coins":person.get("coins"),"inventory":person.get("inventory",{}).duplicate(true)}

func start_room(port:int)->bool:
	host=make_session("SpringHost%d"%sessions.size(),"spring-host")
	return host.host(port,"春季花園",path,ROOM,"127.0.0.1",true,"websocket")==OK

func free_port()->int:
	var listener:=TCPServer.new()
	if listener.listen(0,"127.0.0.1")!=OK:return 0
	var port:=listener.get_local_port()
	listener.stop()
	return port

func run()->void:
	path=OS.get_environment("TEMP").path_join("spring-garden-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	fixture.state.time=SPRING_TIME
	for token in [ALPHA,BETA]:
		fixture.add_player(token,"花園客")
		fixture.state.players[token].x=G.BOARD.x+0.5
		fixture.state.players[token].y=G.BOARD.y+0.5
	if not check(fixture.save(),"Save a spring world with the picnic done"):return
	var port:=free_port()
	if not check(port>0,"Allocate loopback port"):return
	address="ws://127.0.0.1:%d"%port
	if not check(start_room(port),"Start real dedicated WS room"):return
	var alpha:=make_session("Alpha",ALPHA)
	var beta:=make_session("Beta",BETA)
	if not check(alpha.join(address,port,"花園客",ROOM)==OK and beta.join(address,port,"花園客",ROOM)==OK,"Join alpha and beta"):return
	if not check(await wait_for(func():return not alpha.own_id.is_empty() and not beta.own_id.is_empty() and not own(alpha).is_empty() and not own(beta).is_empty()),"Both clients entered with a private garden view"):return
	# Board start state + privacy.
	var first:=own(alpha)
	if not check(first.get("unlocked")==true and first.get("in_season")==true and first.get("active")==false and int(first.get("mask",-1))==0 and first.get("completed")==false and first.get("can_start")==true,"Spring board view allows a first start"):return
	for viewer in [alpha,beta]:
		for row in viewer.snapshot.get("players",{}).values():
			if not check(not row.has(World.SPRING_GARDEN.KEY),"Public player rows carry no raw spring_garden record"):return
	var alpha_before:=economy(ALPHA)
	var beta_before:=economy(BETA)
	# Distance and ordering refusals.
	place(ALPHA,G.BOARD+Vector2i(10,0))
	if not check(not await action(alpha,G.ACTION,G.BOARD,"start") and view_is(alpha,false,0,false),"Cannot start from a distance"):return
	if not check(not await stamp(alpha,ALPHA,"bluebell") and view_is(alpha,false,0,false),"Cannot stamp before signing up"):return
	if not check(not await board(alpha,ALPHA,"finish"),"Cannot finish before signing up"):return
	if not check(await board(alpha,ALPHA,"start") and await wait_view(alpha,true,0,false),"Alpha starts at the board"):return
	if not check(not await board(alpha,ALPHA,"start"),"A second start is refused"):return
	# Stamp: distance, wrong spot, duplicate.
	place(ALPHA,G.BOARD)
	if not check(not await action(alpha,G.ACTION,spot("bluebell"),"bluebell") and view_is(alpha,true,0,false),"Cannot stamp at the board's distance"):return
	place(ALPHA,spot("orange"))
	if not check(not await action(alpha,G.ACTION,spot("bluebell"),"bluebell") and not await action(alpha,G.ACTION,spot("orange"),"herb"),"Standing at one spot cannot stamp another"):return
	if not check(await stamp(alpha,ALPHA,"bluebell") and await wait_view(alpha,true,1,false),"Alpha stamps bluebell in range"):return
	if not check(not await stamp(alpha,ALPHA,"bluebell") and view_is(alpha,true,1,false),"Duplicate stamp is refused with the mask unchanged"):return
	if not check(not await board(alpha,ALPHA,"finish") and view_is(alpha,true,1,false),"Incomplete finish is rejected and keeps progress"):return
	# Concurrency: beta independent of alpha.
	if not check(view_is(beta,false,0,false),"Beta is untouched by alpha's progress"):return
	if not check(await board(beta,BETA,"start") and await wait_view(beta,true,0,false),"Beta starts independently"):return
	if not check(await stamp(beta,BETA,"orange") and await stamp(beta,BETA,"herb") and await wait_view(beta,true,6,false),"Beta stamps orange and herb in a different order"):return
	if not check(view_is(alpha,true,1,false),"Alpha still has only bluebell"):return
	# This earlier refusal-heavy flow sends twelve requests in one second.
	await create_timer(1.05).timeout
	if not check(await stamp(alpha,ALPHA,"orange") and await stamp(alpha,ALPHA,"herb") and await wait_view(alpha,true,7,false),"Alpha collects all three"):return
	if not check(await board(alpha,ALPHA,"finish") and await wait_view(alpha,false,0,true),"Alpha completes"):return
	if not check(await wait_view(beta,true,6,false) and not await board(beta,BETA,"finish"),"Beta's incomplete run is unaffected and cannot finish"):return
	if not check(not await board(alpha,ALPHA,"finish") and view_is(alpha,false,0,true),"A duplicate finish is refused"):return
	# No coin or inventory side effects.
	if not check(economy(ALPHA)==alpha_before and economy(BETA)==beta_before,"No coins or inventory changed for either client"):return
	# Persistence across a server restart, then winter replay.
	if not check(host.world.save(),"Save the room before restart"):return
	var saved:=World.new()
	if not check(saved.load_world(path) and G.view(saved.state,ALPHA).completed==true and int(G.view(saved.state,BETA).mask)==6,"Saved file holds alpha's completion and beta's progress"):return
	for session in [alpha,beta,host]:session.shutdown()
	var port2:=free_port()
	if not check(port2>0,"Allocate a second loopback port"):return
	address="ws://127.0.0.1:%d"%port2
	if not check(start_room(port2),"Restart the dedicated room from the save"):return
	host.world.state.time=WINTER_TIME # test fixture: jump the server clock to winter
	var alpha2:=make_session("Alpha2",ALPHA)
	var beta2:=make_session("Beta2",BETA)
	if not check(alpha2.join(address,port2,"花園客",ROOM)==OK and beta2.join(address,port2,"花園客",ROOM)==OK,"Rejoin after restart"):return
	if not check(await wait_for(func():return not own(alpha2).is_empty() and not own(beta2).is_empty() and own(alpha2).get("in_season")==false),"Both see winter after the restart"):return
	if not check(view_is(alpha2,false,0,true) and own(alpha2).can_start==true,"Completion persisted and replay is offered in winter"):return
	if not check(view_is(beta2,true,6,false) and own(beta2).can_start==false,"Beta's in-progress run persisted"):return
	if not check(await board(alpha2,ALPHA,"start") and await wait_view(alpha2,true,0,true),"Alpha replays in winter"):return
	if not check(not await board(alpha2,ALPHA,"start"),"Replay cannot be started twice"):return
	if not check(await stamp(beta2,BETA,"bluebell") and await wait_view(beta2,true,7,false),"Beta finishes collecting in winter"):return
	if not check(await board(beta2,BETA,"finish") and await wait_view(beta2,false,0,true),"Beta's started run completes after spring ends"):return
	if not check(view_is(alpha2,true,0,true),"Alpha's replay is independent of beta"):return
	if not check(economy(ALPHA)==alpha_before and economy(BETA)==beta_before,"Replay and restart still change no coins or inventory"):return
	finish(0)
