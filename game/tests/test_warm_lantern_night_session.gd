extends "res://tests/network_egg_basket.gd"
## Warm Lantern Night over a real loopback dedicated WS room with two clients (alpha/beta).
##
## Contract under test (World.WARM_LANTERN_NIGHT = L): ACTION/KEY "warm_lantern_night", BOARD cell,
## VIEW_KEY "own_warm_lantern_night", STATIONS = {grove, lane, harbor} (station -> cell, or a
## dictionary holding "cell"), WISHES = home / harvest / friends. Extras: "start" at BOARD (auto-joins
## the starter), "join:<round>" and "finish:<round>" at BOARD, "light:<round>:<station>:<wish>" at the
## station. Public snapshot.warm_lantern_night = {round, phase, lamps, guests} with phase
## "idle"|"lighting"|"celebrated" and lamps station -> wish. Private view own_warm_lantern_night has
## in_season, unlocked, joined, completed, can_start.
##
## DISCLOSURE (preseeded fixtures, not played through):
##  * Saved fixture: picnic=true, board=true, world day 42 (first winter day). The dedicated server's
##    clock is written on host.world.state after each restart: winter again for the first restart and
##    day 56 (spring) for the second.
##  * Positions are set by writing x/y on host.world.state.players[token]; clients never walk, so this
##    does not prove the route to the board or the stations is unobstructed. Reach and cell rules are
##    still exercised through the real network action path.
##  * Request pacing: the server refuses more than 12 actions per 1000 ms (refusals count). This test
##    sends at most one request at a time and keeps MAX_WINDOW sends per 1.1 s per client.
const Weather=preload("res://scripts/weather.gd")
const L=World.WARM_LANTERN_NIGHT
const ALPHA:="lantern-night-alpha"
const BETA:="lantern-night-beta"
const WINTER_TIME:=42.0*Weather.DAY_SECONDS
const SPRING_TIME:=56.0*Weather.DAY_SECONDS
const MAX_WINDOW:=8
var host:Session
var address:=""
var sent:Dictionary={}
var completed:Dictionary={}

func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WARM_LANTERN_NIGHT_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)

func make_session(branch_name:String,token:String)->Session:
	var session:=super(branch_name,token)
	sent[session]=[]
	completed[session]={}
	session.action_completed.connect(func(sequence:int,_name:String,result:Dictionary):completed[session][sequence]=result)
	return session

func own(session:Session)->Dictionary:
	return session.snapshot.get(L.VIEW_KEY,{})

func pub(session:Session)->Dictionary:
	var value:Variant=session.snapshot.get(L.KEY,{})
	return value if value is Dictionary else {}

func station_cell(station:String)->Vector2i:
	return L.STATIONS.get(station,L.STATIONS.grove).cell

func place(token:String,cell:Vector2i)->void:
	var person:Dictionary=host.world.state.players[token]
	person.x=cell.x+0.5
	person.y=cell.y+0.5

func deep(value:Variant)->Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

func footprint(token:String)->Dictionary:
	var person:Dictionary=host.world.state.players[token]
	return {"coins":person.get("coins"),"inventory":deep(person.get("inventory",{})),"picnic":host.world.state.get("picnic")}

func lamps_of(session:Session)->Dictionary:
	var value:Variant=pub(session).get("lamps",{})
	return value if value is Dictionary else {}

func public_is(session:Session,phase:String,lamps:Dictionary)->bool:
	var data:=pub(session)
	return not data.is_empty() and str(data.get("phase",""))==phase and data.get("lamps") is Dictionary and lamps_of(session)==lamps

func wait_public(viewers:Array,phase:String,lamps:Dictionary)->bool:
	return await wait_for(func():
		for viewer in viewers:
			if not public_is(viewer,phase,lamps):return false
		return pub(viewers[0])==pub(viewers[1]))

func view_is(session:Session,joined:bool,done:bool)->bool:
	var view:=own(session)
	return not view.is_empty() and bool(view.get("joined",not joined))==joined and bool(view.get("completed",not done))==done

func wait_view(session:Session,joined:bool,done:bool)->bool:
	return await wait_for(func():return view_is(session,joined,done))

## Waits until sending one more request keeps the last 1.1 s at or below MAX_WINDOW (<12/s).
func pace(session:Session)->void:
	while true:
		var now:=Time.get_ticks_msec()
		var recent:Array=sent[session].filter(func(at:int):return now-at<=1100)
		sent[session]=recent
		if recent.size()+1<=MAX_WINDOW:return
		await process_frame

## Sends one request and returns its authoritative ok, checking sequence-correlated completion.
func act(session:Session,cell:Vector2i,extra:String)->bool:
	await pace(session)
	var seen:int=notices[session].size()
	sent[session].append(Time.get_ticks_msec())
	var sequence:=session.perform(L.ACTION,cell,extra)
	if not check(await wait_for(func():return notices[session].size()>seen),"Every request got an authoritative notice"):return false
	var ok:bool=notices[session].back().ok
	if completed[session].has(sequence):
		if not check(bool(completed[session][sequence].get("ok",false))==ok,"Sequence-correlated result matches the notice"):return false
	return ok

func at_board(session:Session,token:String,extra:String)->bool:
	place(token,L.BOARD)
	return await act(session,L.BOARD,extra)

func light(session:Session,token:String,round:int,station:String,wish:String)->bool:
	place(token,station_cell(station))
	return await act(session,station_cell(station),"light:%d:%s:%s"%[round,station,wish])

func start_room(port:int)->bool:
	host=make_session("LanternHost%d"%sessions.size(),"lantern-night-host")
	var result:=host.host(port,"暖燈夜",path,ROOM,"127.0.0.1",true,"websocket")
	if result!=OK:print("Host restart failed: ",error_string(result)," ",notices[host])
	return result==OK

func free_port()->int:
	var listener:=TCPServer.new()
	if listener.listen(0,"127.0.0.1")!=OK:return 0
	var port:=listener.get_local_port()
	listener.stop()
	return port

## No raw player token in the public projection or in any public player row.
func no_token(viewers:Array)->bool:
	for viewer in viewers:
		var text:=JSON.stringify(pub(viewer))
		for row:Dictionary in viewer.snapshot.get("players",{}).values():
			if row.has(L.KEY) or row.has(L.VIEW_KEY):return false
			text+=JSON.stringify(row)
		for token in [ALPHA,BETA]:
			if text.contains(token):return false
	return true

## Restarts the dedicated room from its save with the server clock set to `time`; returns [alpha,beta].
func restart(time:float,tag:String)->Array:
	if not check(host.world.save(),"Save the room before restart"):return []
	for session in sessions.duplicate():
		if not session.shutting_down and not check(session.shutdown(),"The previous session closes and releases its save"):return []
	var port:=free_port()
	if not check(port>0,"Allocate a loopback port for restart"):return []
	address="ws://127.0.0.1:%d"%port
	if not check(start_room(port),"Restart the dedicated room from the save"):return []
	# Advance the fixture clock without making recorded action timestamps future-dated.
	host.world.state.time=maxf(float(host.world.state.time),time)
	sent={}
	var alpha:=make_session("Alpha"+tag,ALPHA)
	var beta:=make_session("Beta"+tag,BETA)
	if not check(alpha.join(address,port,"燈夜客",ROOM)==OK and beta.join(address,port,"燈夜客",ROOM)==OK,"Rejoin after restart"):return []
	if not check(await wait_for(func():return not own(alpha).is_empty() and not own(beta).is_empty() and not pub(alpha).is_empty() and not pub(beta).is_empty()),"Both clients re-entered with private views and a public lantern state"):return []
	return [alpha,beta]

func run()->void:
	if not check(L.ACTION=="warm_lantern_night" and L.KEY=="warm_lantern_night" and L.VIEW_KEY=="own_warm_lantern_night","Rules constants match the contract"):return
	var stations:Array=L.STATIONS.keys()
	stations.sort()
	if not check(stations==["grove","harbor","lane"] and L.BOARD is Vector2i,"Three stations and a board cell exist"):return
	var wishes:Array=[]
	for wish in L.WISHES:wishes.append(str(wish)) # iterates keys for a Dictionary, items for an Array
	wishes.sort()
	if not check(wishes==["friends","harvest","home"],"Wishes are home, harvest and friends"):return
	if not check(Weather.season_on_day(Weather.day_index(WINTER_TIME))=="winter" and Weather.season_on_day(Weather.day_index(SPRING_TIME))=="spring","Fixture clocks are winter and spring"):return
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	fixture.state.board=true
	fixture.state.time=WINTER_TIME
	for token in [ALPHA,BETA]:
		fixture.add_player(token,"燈夜客")
		var person:Dictionary=fixture.state.players[token]
		person.x=L.BOARD.x+0.5
		person.y=L.BOARD.y+0.5
		person.coins=123
		person.inventory.wood=5
	if not check(fixture.save(),"Save a day-42 winter world with picnic and board"):return
	var port:=free_port()
	if not check(port>0,"Allocate loopback port"):return
	address="ws://127.0.0.1:%d"%port
	if not check(start_room(port),"Start real dedicated WS room"):return
	var alpha:=make_session("Alpha",ALPHA)
	var beta:=make_session("Beta",BETA)
	if not check(alpha.join(address,port,"燈夜客",ROOM)==OK and beta.join(address,port,"燈夜客",ROOM)==OK,"Join alpha and beta"):return
	if not check(await wait_for(func():return not alpha.own_id.is_empty() and not beta.own_id.is_empty() and not own(alpha).is_empty() and not own(beta).is_empty() and not pub(alpha).is_empty() and not pub(beta).is_empty()),"Both clients entered with private views and a public lantern state"):return
	host.world.state.time=WINTER_TIME
	for viewer in [alpha,beta]:
		var first:=own(viewer)
		if not check(first.get("unlocked")==true and first.get("in_season")==true and first.get("completed")==false and first.get("joined")==false and first.get("can_start")==true,"Winter view allows a first start"):return
	if not check(await wait_public([alpha,beta],"idle",{}),"Public lantern night starts idle with no lamps"):return
	if not check(no_token([alpha,beta]),"No raw player token in the public projection"):return
	var alpha_before:=footprint(ALPHA)
	var beta_before:=footprint(BETA)
	var round:=int(pub(alpha).get("round",0))
	# Refusals while idle.
	if not check(not await at_board(beta,BETA,"join:%d"%round) and not await at_board(alpha,ALPHA,"finish:%d"%round) and not await light(alpha,ALPHA,round,"grove","home"),"Nothing can be joined, lit or finished while idle"):return
	place(ALPHA,L.BOARD+Vector2i(10,0))
	if not check(not await act(alpha,L.BOARD,"start") and public_is(alpha,"idle",{}),"Cannot start from a distance"):return
	place(ALPHA,station_cell("grove"))
	if not check(not await act(alpha,station_cell("grove"),"start") and public_is(alpha,"idle",{}),"Cannot start at a station"):return
	if not check(footprint(ALPHA)==alpha_before,"Idle refusals changed nothing"):return
	# Alpha starts and is auto-joined.
	if not check(await at_board(alpha,ALPHA,"start"),"Alpha starts at the board"):return
	if not check(await wait_public([alpha,beta],"lighting",{}),"Both clients see the lighting phase"):return
	round=int(pub(alpha).get("round",-1))
	if not check(round>=1,"A started round has a positive number"):return
	if not check(await wait_view(alpha,true,false) and view_is(beta,false,false),"Alpha is auto-joined, beta is not"):return
	if not check(not await at_board(alpha,ALPHA,"start") and not await at_board(beta,BETA,"start"),"Starting during a lighting round is refused"):return
	# Non-participants, wrong rounds, wrong places and bad requests change nothing.
	if not check(not await light(beta,BETA,round,"lane","friends") and public_is(beta,"lighting",{}),"A player who has not joined cannot light"):return
	if not check(not await at_board(beta,BETA,"join:%d"%(round-1)) and not await at_board(beta,BETA,"join:%d"%(round+1)) and view_is(beta,false,false),"Joining a stale or future round is refused"):return
	place(BETA,station_cell("lane"))
	if not check(not await act(beta,station_cell("lane"),"join:%d"%round) and view_is(beta,false,false),"Joining is only possible at the board"):return
	if not check(not await at_board(alpha,ALPHA,"finish:%d"%round) and public_is(alpha,"lighting",{}),"An unlit night cannot be finished"):return
	if not check(not await light(alpha,ALPHA,round+1,"grove","home") and not await light(alpha,ALPHA,round-1,"grove","home"),"Stale and future rounds cannot light"):return
	if not check(not await light(alpha,ALPHA,round,"nowhere","home") and not await light(alpha,ALPHA,round,"grove","wealth"),"Unknown stations and wishes are refused"):return
	place(ALPHA,station_cell("grove"))
	if not check(not await act(alpha,station_cell("grove"),"light:%d"%round) and not await act(alpha,station_cell("grove"),"light:%d:grove"%round) and not await act(alpha,station_cell("grove"),"light:x:grove:home") and not await act(alpha,station_cell("grove"),"nonsense"),"Malformed extras are refused"):return
	place(ALPHA,station_cell("lane"))
	if not check(not await act(alpha,station_cell("grove"),"light:%d:grove:home"%round) and not await act(alpha,station_cell("lane"),"light:%d:grove:home"%round),"Lighting a station from another station's cell is refused"):return
	place(ALPHA,station_cell("grove")+Vector2i(10,0))
	if not check(not await act(alpha,station_cell("grove"),"light:%d:grove:home"%round),"Cannot light from a distance"):return
	place(ALPHA,L.BOARD)
	if not check(not await act(alpha,L.BOARD,"light:%d:grove:home"%round),"Cannot light at the board"):return
	if not check(public_is(alpha,"lighting",{}) and footprint(ALPHA)==alpha_before,"Refusals lit nothing and changed nothing"):return
	# Alpha lights the grove; both clients observe.
	if not check(await light(alpha,ALPHA,round,"grove","home"),"Alpha lights the grove lamp"):return
	if not check(await wait_public([alpha,beta],"lighting",{"grove":"home"}),"Both clients see the grove lamp"):return
	if not check(not await light(alpha,ALPHA,round,"grove","home") and not await light(alpha,ALPHA,round,"grove","harvest"),"A lit station cannot be lit again"):return
	if not check(public_is(beta,"lighting",{"grove":"home"}),"Duplicates kept the lamp"):return
	# Beta joins explicitly at the board.
	if not check(await at_board(beta,BETA,"join:%d"%round) and await wait_view(beta,true,false),"Beta joins at the board"):return
	if not check(not await at_board(beta,BETA,"join:%d"%round),"Joining twice is refused"):return
	if not check(not await at_board(alpha,ALPHA,"finish:%d"%round) and not await at_board(beta,BETA,"finish:%d"%round),"A partly lit night cannot be finished"):return
	if not check(no_token([alpha,beta]),"Still no raw token in the public projection"):return
	# Restart between lights (still winter).
	var again:=await restart(WINTER_TIME,"2")
	if again.is_empty():return
	var alpha2:Session=again[0]
	var beta2:Session=again[1]
	if not check(await wait_public([alpha2,beta2],"lighting",{"grove":"home"}) and int(pub(alpha2).get("round",-1))==round,"The partial round survived the restart"):return
	if not check(view_is(alpha2,true,false) and view_is(beta2,true,false) and own(alpha2).get("in_season")==true,"Both players are still joined and not completed"):return
	# Beta lights the lane; alpha observes.
	if not check(await light(beta2,BETA,round,"lane","friends"),"Beta lights the lane lamp after the restart"):return
	if not check(await wait_public([alpha2,beta2],"lighting",{"grove":"home","lane":"friends"}),"Both clients see two lamps"):return
	if not check(not await light(alpha2,ALPHA,round,"lane","home") and not await light(beta2,BETA,round,"grove","friends") and not await light(beta2,BETA,round-1,"harbor","harvest"),"Duplicates and stale rounds are refused after the restart"):return
	if not check(public_is(alpha2,"lighting",{"grove":"home","lane":"friends"}) and not await at_board(alpha2,ALPHA,"finish:%d"%round),"One lamp short cannot finish"):return
	if not check(await light(alpha2,ALPHA,round,"harbor","harvest"),"Alpha lights the harbor lamp"):return
	var all_lit:={"grove":"home","lane":"friends","harbor":"harvest"}
	if not check(await wait_public([alpha2,beta2],"lighting",all_lit),"Both clients see every lamp"):return
	if not check(view_is(alpha2,true,false) and view_is(beta2,true,false),"Lighting alone completes nobody"):return
	# Restart again, into spring, and finish.
	var spring:=await restart(SPRING_TIME,"3")
	if spring.is_empty():return
	var alpha3:Session=spring[0]
	var beta3:Session=spring[1]
	if not check(await wait_for(func():return own(alpha3).get("in_season")==false and own(beta3).get("in_season")==false),"Both see spring after the restart"):return
	if not check(await wait_public([alpha3,beta3],"lighting",all_lit) and int(pub(alpha3).get("round",-1))==round,"The fully lit round survived into spring"):return
	if not check(view_is(alpha3,true,false) and view_is(beta3,true,false),"Both players are still joined and not completed"):return
	if not check(not await at_board(alpha3,ALPHA,"finish:%d"%(round+1)) and not await at_board(alpha3,ALPHA,"finish:%d"%(round-1)),"Finishing a stale round is refused"):return
	place(ALPHA,L.BOARD+Vector2i(10,0))
	if not check(not await act(alpha3,L.BOARD,"finish:%d"%round),"Cannot finish from a distance"):return
	place(ALPHA,station_cell("grove"))
	if not check(not await act(alpha3,station_cell("grove"),"finish:%d"%round),"Cannot finish at a station"):return
	if not check(public_is(alpha3,"lighting",all_lit) and view_is(beta3,true,false),"Refusals left the night lighting"):return
	if not check(await at_board(alpha3,ALPHA,"finish:%d"%round),"Alpha finishes the lantern night in spring"):return
	if not check(await wait_public([alpha3,beta3],"celebrated",all_lit),"Both clients see the celebration and every lamp"):return
	if not check(await wait_view(alpha3,true,true) and await wait_view(beta3,true,true),"Both participants completed it in spring"):return
	if not check(not await at_board(beta3,BETA,"finish:%d"%round) and not await light(beta3,BETA,round,"grove","home") and not await at_board(beta3,BETA,"join:%d"%round),"A celebrated round accepts no more finishes, lights or joins"):return
	if not check(own(alpha3).get("can_start")==true and own(beta3).get("can_start")==true and own(alpha3).get("in_season")==false,"Completed players may start again out of season"):return
	if not check(no_token([alpha3,beta3]),"No raw token after the celebration"):return
	# A new round in spring.
	if not check(await at_board(alpha3,ALPHA,"start"),"Alpha starts a new round in spring"):return
	if not check(await wait_public([alpha3,beta3],"lighting",{}),"A fresh round clears the lamps for both clients"):return
	var next:=int(pub(alpha3).get("round",-1))
	if not check(next>round,"The new round has a higher number"):return
	if not check(await wait_view(alpha3,true,true) and view_is(beta3,false,true),"Alpha is joined again; beta keeps its completion but is not in the new round"):return
	if not check(not await light(alpha3,ALPHA,round,"grove","home") and not await light(beta3,BETA,next,"grove","home") and public_is(beta3,"lighting",{}),"Old rounds and non-participants cannot light the new round"):return
	if not check(await light(alpha3,ALPHA,next,"grove","friends") and await wait_public([alpha3,beta3],"lighting",{"grove":"friends"}),"Alpha lights a lamp in the new round"):return
	# Economy guarantees.
	var alpha_end:=footprint(ALPHA)
	var beta_end:=footprint(BETA)
	if not check(alpha_end.coins==alpha_before.coins and beta_end.coins==beta_before.coins and alpha_end.picnic==true and beta_end.picnic==true,"No coins or picnic state changed"):return
	if not check(alpha_end.inventory==alpha_before.inventory and beta_end.inventory==beta_before.inventory,"Bags are untouched"):return
	if not check(no_token([alpha3,beta3]),"No raw player token leaked after the new round"):return
	finish(0)
