extends "res://tests/network_egg_basket.gd"
## Autumn Feast over a real loopback dedicated WS room with two clients (alpha/beta).
##
## Contract under test (World.AUTUMN_FEAST = F): ACTION/KEY "autumn_feast", BOARD (40,29), VIEW_KEY
## "own_autumn_feast". Extras: "start" at BOARD, "join:<round>", "give:<round>:<item>", "serve:<round>"
## (serve at the community table cell). Public snapshot.autumn_feast = {round, phase, entries, count}
## with phase "idle"|"collect"|"served" and entries slot -> item id. Private view own_autumn_feast has
## in_season, unlocked, completed, joined, can_start.
##
## DISCLOSURE (preseeded fixtures, not played through):
##  * Saved fixture: picnic=true, board=true, community.table = Community.CANDIDATES[0], world day 28
##    (first autumn day, 40320 s). After the restart the dedicated server's clock is written to day 45
##    (winter, 64800 s) on host.world.state.
##  * Positions are set by writing x/y on host.world.state.players[token]; clients never walk, so this
##    does not prove the route to the board or table is unobstructed. Reach and cell rules are still
##    exercised through the real network action path.
##  * Bags are seeded: Alpha radish x2 + wheat, Beta lettuce (all valid SLOTS crops). The second radish
##    exists only to drive the slot collision (same item, slot already filled). Before the winter replay
##    Alpha's bag is topped up on the host world to radish/wheat/lettuce x1 (fixture, not gameplay).
##  * Start is at the board; joining, giving and serving use the actual saved community table.
##  * The three seeded crops land in three distinct slots.
##  * Request pacing: the server refuses more than 12 actions per 1000 ms (refusals count). This test
##    never has more than MAX_WINDOW sends in flight per 1.1 s per client; the only burst is 3 requests,
##    matched in order to their authoritative notices (and to action_completed by sequence).
const Community=preload("res://scripts/community.gd")
const Weather=preload("res://scripts/weather.gd")
const F=World.AUTUMN_FEAST
const ALPHA:="autumn-feast-alpha"
const BETA:="autumn-feast-beta"
const AUTUMN_TIME:=40320.0  # day 28, first autumn day
const WINTER_TIME:=64800.0  # day 45, winter
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
	print("AUTUMN_FEAST_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)

func make_session(branch_name:String,token:String)->Session:
	var session:=super(branch_name,token)
	sent[session]=[]
	completed[session]={}
	session.action_completed.connect(func(sequence:int,_name:String,result:Dictionary):completed[session][sequence]=result)
	return session

func own(session:Session)->Dictionary:
	return session.snapshot.get(F.VIEW_KEY,{})

func pub(session:Session)->Dictionary:
	var value:Variant=session.snapshot.get(F.KEY,{})
	return value if value is Dictionary else {}

func table()->Vector2i:
	return Community.table_cell(host.world.state)

func place(token:String,cell:Vector2i)->void:
	var person:Dictionary=host.world.state.players[token]
	person.x=cell.x+0.5
	person.y=cell.y+0.5

func deep(value:Variant)->Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

func bag(token:String)->Dictionary:
	return deep(host.world.state.players[token].inventory)

func footprint(token:String)->Dictionary:
	var person:Dictionary=host.world.state.players[token]
	return {"coins":person.get("coins"),"inventory":deep(person.get("inventory",{})),"picnic":host.world.state.get("picnic")}

## The inventory after consuming exactly one `item`.
func minus_one(before:Dictionary,item:String)->Dictionary:
	var result:Dictionary=before.duplicate(true)
	result[item]=int(result.get(item,0))-1
	if int(result[item])<=0:result.erase(item)
	return result

func normalized(inventory:Dictionary)->Dictionary:
	var result:Dictionary={}
	for item in inventory:
		if int(inventory[item])!=0:result[item]=int(inventory[item])
	return result

func same_bag(a:Dictionary,b:Dictionary)->bool:
	return normalized(a)==normalized(b)

func items_of(session:Session)->Array:
	var entries:Variant=pub(session).get("entries",{})
	var result:=[]
	if entries is Dictionary:
		for slot in entries:result.append(str(entries[slot]))
	result.sort()
	return result

func public_is(session:Session,phase:String,count:int,items:Array)->bool:
	var data:=pub(session)
	var want:=items.duplicate()
	want.sort()
	return not data.is_empty() and str(data.get("phase",""))==phase and int(data.get("count",-1))==count and data.get("entries") is Dictionary and items_of(session)==want

func wait_public(sessions_to_check:Array,phase:String,count:int,items:Array)->bool:
	return await wait_for(func():
		for viewer in sessions_to_check:
			if not public_is(viewer,phase,count,items):return false
		return pub(sessions_to_check[0])==pub(sessions_to_check[1]))

func view_is(session:Session,joined:bool,done:bool)->bool:
	var view:=own(session)
	return not view.is_empty() and bool(view.get("joined",not joined))==joined and bool(view.get("completed",not done))==done

func wait_view(session:Session,joined:bool,done:bool)->bool:
	return await wait_for(func():return view_is(session,joined,done))

## Waits until sending `count` more requests keeps the last 1.1 s at or below MAX_WINDOW (<12/s).
func pace(session:Session,count:int)->void:
	while true:
		var now:=Time.get_ticks_msec()
		var recent:Array=sent[session].filter(func(at:int):return now-at<=1100)
		sent[session]=recent
		if recent.size()+count<=MAX_WINDOW:return
		await process_frame

## Sends steps=[[cell,extra],...] back to back; returns each step's authoritative ok in order.
func burst(session:Session,steps:Array)->Array:
	await pace(session,steps.size())
	var seen:int=notices[session].size()
	var sequences:=[]
	for step in steps:
		sent[session].append(Time.get_ticks_msec())
		sequences.append(session.perform(F.ACTION,step[0],step[1]))
	var count:=steps.size()
	if not check(await wait_for(func():return notices[session].size()>=seen+count),"Every request got an authoritative notice"):return []
	var results:=[]
	for index in count:
		var ok:bool=notices[session][seen+index].ok
		results.append(ok)
		if completed[session].has(sequences[index]):
			if not check(bool(completed[session][sequences[index]].get("ok",false))==ok,"Sequence-correlated result matches the notice"):return []
	return results

func act(session:Session,cell:Vector2i,extra:String)->bool:
	var results:=await burst(session,[[cell,extra]])
	return results.size()==1 and results[0]

func at_board(session:Session,token:String,extra:String)->bool:
	place(token,F.BOARD)
	return await act(session,F.BOARD,extra)

func join(session:Session,token:String,round:int)->bool:
	place(token,table())
	return await act(session,table(),"join:%d"%round)

func give(session:Session,token:String,round:int,item:String)->bool:
	place(token,table())
	return await act(session,table(),"give:%d:%s"%[round,item])

func serve(session:Session,token:String,round:int)->bool:
	place(token,table())
	return await act(session,table(),"serve:%d"%round)

func start_room(port:int)->bool:
	host=make_session("FeastHost%d"%sessions.size(),"autumn-feast-host")
	return host.host(port,"秋日盛宴",path,ROOM,"127.0.0.1",true,"websocket")==OK

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
			if row.has(F.KEY):return false
			text+=JSON.stringify(row)
		for token in [ALPHA,BETA]:
			if text.contains(token):return false
	return true

func run()->void:
	if not check(F.ACTION=="autumn_feast" and F.KEY=="autumn_feast" and F.VIEW_KEY=="own_autumn_feast" and F.BOARD==Vector2i(40,29),"Rules constants match the contract"):return
	if not check(Weather.season_on_day(Weather.day_index(AUTUMN_TIME))=="autumn" and Weather.season_on_day(Weather.day_index(WINTER_TIME))=="winter","Fixture clocks are autumn and winter"):return
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	fixture.state.board=true
	fixture.state.time=AUTUMN_TIME
	fixture.state.community={"table":Community.cell_key(Community.CANDIDATES[0])}
	for token in [ALPHA,BETA]:
		fixture.add_player(token,"秋日客")
		var person:Dictionary=fixture.state.players[token]
		person.x=F.BOARD.x+0.5
		person.y=F.BOARD.y+0.5
		person.coins=123
		person.inventory.wood=5
	fixture.state.players[ALPHA].inventory.radish=2
	fixture.state.players[ALPHA].inventory.wheat=1
	fixture.state.players[BETA].inventory.lettuce=1
	if not check(Community.valid(fixture.state) and fixture.save(),"Save a day-28 autumn world with picnic, board and community table"):return
	var port:=free_port()
	if not check(port>0,"Allocate loopback port"):return
	address="ws://127.0.0.1:%d"%port
	if not check(start_room(port),"Start real dedicated WS room"):return
	var alpha:=make_session("Alpha",ALPHA)
	var beta:=make_session("Beta",BETA)
	if not check(alpha.join(address,port,"秋日客",ROOM)==OK and beta.join(address,port,"秋日客",ROOM)==OK,"Join alpha and beta"):return
	if not check(await wait_for(func():return not alpha.own_id.is_empty() and not beta.own_id.is_empty() and not own(alpha).is_empty() and not own(beta).is_empty() and not pub(alpha).is_empty() and not pub(beta).is_empty()),"Both clients entered with private views and a public feast"):return
	if not check(table()!=Community.NO_CELL,"The community table is placed"):return
	for viewer in [alpha,beta]:
		var first:=own(viewer)
		if not check(first.get("unlocked")==true and first.get("in_season")==true and first.get("completed")==false and first.get("joined")==false and first.get("can_start")==true,"Autumn view allows a first start"):return
	if not check(await wait_public([alpha,beta],"idle",0,[]),"Public feast starts idle and empty"):return
	if not check(no_token([alpha,beta]),"No raw player token in the public projection"):return
	var alpha_before:=footprint(ALPHA)
	var beta_before:=footprint(BETA)
	var round:=int(pub(alpha).get("round",0))
	# Refusals while idle.
	if not check(not await give(alpha,ALPHA,round,"radish") and not await join(beta,BETA,round) and not await serve(alpha,ALPHA,round),"Nothing can be given, joined or served while idle"):return
	place(ALPHA,F.BOARD+Vector2i(10,0))
	if not check(not await act(alpha,F.BOARD,"start") and public_is(alpha,"idle",0,[]),"Cannot start from a distance"):return
	place(ALPHA,table())
	if not check(not await act(alpha,table(),"start") and public_is(alpha,"idle",0,[]),"Cannot start at the table"):return
	if not check(footprint(ALPHA)==alpha_before,"Idle refusals changed nothing"):return
	# Alpha starts and is auto-joined.
	if not check(await at_board(alpha,ALPHA,"start"),"Alpha starts at the board"):return
	if not check(await wait_public([alpha,beta],"collect",0,[]),"Both clients see the collecting phase"):return
	round=int(pub(alpha).get("round",-1))
	if not check(round>=1,"A started round has a positive number"):return
	if not check(await wait_view(alpha,true,false) and view_is(beta,false,false),"Alpha is auto-joined, beta is not"):return
	if not check(not await at_board(alpha,ALPHA,"start") and not await at_board(beta,BETA,"start"),"Starting during a collecting round is refused"):return
	# Non-participants, wrong rounds and bad requests change nothing.
	var beta_bag:=bag(BETA)
	if not check(not await give(beta,BETA,round,"lettuce") and same_bag(bag(BETA),beta_bag) and public_is(beta,"collect",0,[]),"A player who has not joined cannot donate"):return
	if not check(not await join(beta,BETA,round-1) and not await join(beta,BETA,round+1) and view_is(beta,false,false),"Joining a stale or future round is refused"):return
	var alpha_bag:=bag(ALPHA)
	if not check(not await give(alpha,ALPHA,round+1,"radish") and not await give(alpha,ALPHA,round-1,"radish"),"Wrong-round donations are refused"):return
	if not check(not await give(alpha,ALPHA,round,"wood") and not await give(alpha,ALPHA,round,"no_such_item") and not await give(alpha,ALPHA,round,"lettuce"),"Non-crop, unknown and unowned items are refused"):return
	place(ALPHA,table())
	if not check(not await act(alpha,table(),"give:%d"%round) and not await act(alpha,table(),"give:x:radish") and not await act(alpha,table(),"nonsense"),"Malformed extras are refused"):return
	place(ALPHA,table()+Vector2i(10,0))
	if not check(not await act(alpha,table(),"give:%d:radish"%round),"Cannot donate from a distance"):return
	if not check(same_bag(bag(ALPHA),alpha_bag) and public_is(alpha,"collect",0,[]),"Refusals spent nothing and filled no slot"):return
	# Alpha donates; a second radish collides with the filled slot.
	if not check(await give(alpha,ALPHA,round,"radish"),"Alpha donates a radish"):return
	if not check(await wait_public([alpha,beta],"collect",1,["radish"]),"Both clients see the radish slot filled"):return
	if not check(same_bag(bag(ALPHA),minus_one(alpha_bag,"radish")),"Exactly one radish was consumed"):return
	var after_radish:=bag(ALPHA)
	if not check(not await give(alpha,ALPHA,round,"radish"),"A second radish collides with the filled slot"):return
	if not check(same_bag(bag(ALPHA),after_radish) and public_is(beta,"collect",1,["radish"]),"The collision spent nothing and kept the slot"):return
	if not check(await give(alpha,ALPHA,round,"wheat") and await wait_public([alpha,beta],"collect",2,["radish","wheat"]),"Alpha donates wheat into the next slot"):return
	if not check(same_bag(bag(ALPHA),minus_one(after_radish,"wheat")),"Exactly one wheat was consumed"):return
	# Beta explicitly joins but has not donated yet; an incomplete feast cannot be served.
	if not check(await join(beta,BETA,round) and await wait_view(beta,true,false),"Beta joins explicitly"):return
	if not check(not await serve(alpha,ALPHA,round) and not await serve(beta,BETA,round),"An incomplete feast cannot be served"):return
	if not check(public_is(alpha,"collect",2,["radish","wheat"]) and same_bag(bag(BETA),beta_bag),"Refused serves changed nothing"):return
	if not check(no_token([alpha,beta]),"Still no raw token in the public projection"):return
	# Save and restart mid-collection, in winter.
	if not check(host.world.save(),"Save the room before restart"):return
	for session in [alpha,beta,host]:session.shutdown()
	var port2:=free_port()
	if not check(port2>0,"Allocate a second loopback port"):return
	address="ws://127.0.0.1:%d"%port2
	if not check(start_room(port2),"Restart the dedicated room from the save"):return
	host.world.state.time=WINTER_TIME # test fixture: jump the server clock to winter (day 45)
	sent={}
	var alpha2:=make_session("Alpha2",ALPHA)
	var beta2:=make_session("Beta2",BETA)
	if not check(alpha2.join(address,port2,"秋日客",ROOM)==OK and beta2.join(address,port2,"秋日客",ROOM)==OK,"Rejoin after restart"):return
	if not check(await wait_for(func():return not own(alpha2).is_empty() and not own(beta2).is_empty() and own(alpha2).get("in_season")==false),"Both see winter after the restart"):return
	if not check(await wait_public([alpha2,beta2],"collect",2,["radish","wheat"]) and int(pub(alpha2).get("round",-1))==round,"The partial round survived the restart"):return
	if not check(view_is(alpha2,true,false) and view_is(beta2,true,false),"Both players are still joined and not completed"):return
	if not check(same_bag(bag(ALPHA),minus_one(after_radish,"wheat")) and same_bag(bag(BETA),beta_bag),"Bags persisted exactly"):return
	# Beta finishes the feast after the restart.
	if not check(not await give(beta2,BETA,round,"radish") and not await give(beta2,BETA,round,"wheat"),"Beta holds neither filled-slot crop"):return
	if not check(await give(beta2,BETA,round,"lettuce") and await wait_public([alpha2,beta2],"collect",3,["radish","wheat","lettuce"]),"Beta donates lettuce after the restart"):return
	if not check(same_bag(bag(BETA),minus_one(beta_bag,"lettuce")),"Exactly one lettuce was consumed"):return
	var full_bag:=bag(ALPHA)
	if not check(not await give(alpha2,ALPHA,round,"radish") and same_bag(bag(ALPHA),full_bag) and public_is(alpha2,"collect",3,["radish","wheat","lettuce"]),"A full feast accepts no more items"):return
	# Serve only at the table, with the live round.
	place(ALPHA,table())
	if not check(not await act(alpha2,F.BOARD,"serve:%d"%round) and not await act(alpha2,table(),"serve:%d"%(round+1)) and not await act(alpha2,table(),"serve:%d"%(round-1)),"Serving at the board or with a stale round is refused"):return
	place(ALPHA,table()+Vector2i(10,0))
	if not check(not await act(alpha2,table(),"serve:%d"%round),"Cannot serve from a distance"):return
	if not check(public_is(alpha2,"collect",3,["radish","wheat","lettuce"]) and view_is(alpha2,true,false) and view_is(beta2,true,false),"Refusals left the feast collecting"):return
	if not check(await serve(alpha2,ALPHA,round),"Alpha serves the full feast at the community table"):return
	if not check(await wait_public([alpha2,beta2],"served",3,["radish","wheat","lettuce"]),"Both clients see the served phase and the crops"):return
	if not check(await wait_view(alpha2,true,true) and await wait_view(beta2,true,true),"Both participants completed the feast in winter"):return
	if not check(not await serve(beta2,BETA,round) and not await give(alpha2,ALPHA,round,"radish") and same_bag(bag(ALPHA),full_bag),"A served round accepts neither serves nor donations"):return
	if not check(own(alpha2).get("can_start")==true and own(beta2).get("can_start")==true and own(alpha2).get("in_season")==false,"Completed players may replay out of season"):return
	if not check(no_token([alpha2,beta2]),"No raw token after serving"):return
	# Alpha's personal winter replay.
	if not check(await at_board(alpha2,ALPHA,"start"),"Alpha replays in winter"):return
	if not check(await wait_public([alpha2,beta2],"collect",0,[]),"A fresh round replaces the served crops for both clients"):return
	var replay:=int(pub(alpha2).get("round",-1))
	if not check(replay>round,"The replay is a new round"):return
	if not check(await wait_view(alpha2,true,true) and view_is(beta2,false,true),"Alpha is joined again; beta keeps its completion but is not in the new round"):return
	var top_up:Dictionary=host.world.state.players[ALPHA].inventory # fixture: top up crops on the host world
	top_up.radish=1
	top_up.wheat=1
	top_up.lettuce=1
	var replay_bag:=bag(ALPHA)
	if not check(not await give(alpha2,ALPHA,round,"radish") and same_bag(bag(ALPHA),replay_bag),"A stale round cannot be donated to"):return
	place(ALPHA,table())
	var results:=await burst(alpha2,[[table(),"give:%d:wheat"%replay],[table(),"give:%d:lettuce"%replay],[table(),"give:%d:radish"%replay]])
	if not check(results==[true,true,true],"Burst answers arrive in order: three donations accepted"):return
	if not check(await wait_public([alpha2,beta2],"collect",3,["radish","wheat","lettuce"]),"Both clients see the replay filled"):return
	if not check(await serve(alpha2,ALPHA,replay) and await wait_public([alpha2,beta2],"served",3,["radish","wheat","lettuce"]),"Alpha serves the replay"):return
	if not check(await wait_view(alpha2,true,true) and view_is(beta2,false,true),"Alpha completed again; beta unaffected"):return
	# Economy guarantees.
	var alpha_end:=footprint(ALPHA)
	var beta_end:=footprint(BETA)
	if not check(alpha_end.coins==alpha_before.coins and beta_end.coins==beta_before.coins and alpha_end.picnic==true,"No coins or picnic state changed"):return
	if not check(int(alpha_end.inventory.get("wood",0))==5 and int(alpha_end.inventory.get("radish",0))==0 and int(alpha_end.inventory.get("wheat",0))==0 and int(alpha_end.inventory.get("lettuce",0))==0,"Alpha's final bag holds only the untouched wood"):return
	if not check(int(beta_end.inventory.get("wood",0))==5 and int(beta_end.inventory.get("lettuce",0))==0,"Beta's final bag holds only the untouched wood"):return
	if not check(no_token([alpha2,beta2]),"No raw player token leaked after the replay"):return
	finish(0)
