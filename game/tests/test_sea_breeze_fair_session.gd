extends "res://tests/network_egg_basket.gd"
## Sea Breeze Fair over a real loopback dedicated WS room with two clients (alpha/beta).
##
## Contract under test (World.SEA_BREEZE_FAIR = F): ACTION/KEY "sea_breeze_fair", VIEW_KEY
## "own_sea_breeze_fair", BOARD (40,29), DISHES (Dictionary, insertion order watermelon_platter,
## baked_potato, strawberry_jam). Extras: "start"/"finish" at BOARD, "serve:<dish>" at the market
## stall cell Market.active_cell(world.state). The required dish order is DISHES rotated left by
## (signup world day % 3); the order is pinned at signup, so a run started on day 14 keeps its
## order after the world clock jumps to winter, while a winter replay (day 45) uses offset 0.
##
## DISCLOSURE (preseeded fixtures, not played through):
##  * World time is written into the saved fixture (day 14 = first summer day, 20160 s) and,
##    after the restart, into the dedicated server's world (day 45 = winter, 64800 s).
##  * Positions are set by writing x/y on host.world.state.players[token]; clients never walk, so
##    this test does not prove the walking route to the board or stall is unobstructed. Reach and
##    cell rules are still exercised for real through the network action path.
##  * The fixture preseeds picnic=true (unlocks the market stall) plus coins and a small bag so any
##    wallet/bag change is detectable. The fair's loan ingredients are never given to the player:
##    the test asserts the whole inventory is identical after every action, including each serve.
##  * Request pacing: the server refuses more than 12 actions in 1000 ms (refusals count). This test
##    tracks its own sends and never has more than MAX_WINDOW in flight per 1.1 s; the only burst
##    is 3 requests, sent back to back and matched in order to their authoritative notices (and to
##    action_completed by exact sequence if the server also sends one).
const Market=preload("res://scripts/market_stall.gd")
const F=World.SEA_BREEZE_FAIR
const ALPHA:="sea-breeze-alpha"
const BETA:="sea-breeze-beta"
const SIGNUP_TIME:=20160.0  # day 14 -> first summer day, 14 % 3 == 2
const WINTER_TIME:=64800.0  # day 45 -> winter, 45 % 3 == 0
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
	print("SEA_BREEZE_FAIR_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)

func make_session(branch_name:String,token:String)->Session:
	var session:=super(branch_name,token)
	sent[session]=[]
	completed[session]={}
	session.action_completed.connect(func(sequence:int,_name:String,result:Dictionary):completed[session][sequence]=result)
	return session

func own(session:Session)->Dictionary:
	return session.snapshot.get(F.VIEW_KEY,{})

func dish_ids()->Array:
	return F.DISHES.keys()

## DISHES rotated left by `offset`: the serving order for a run signed up on a day with day % 3 == offset.
func order_for(offset:int)->Array:
	var ids:=dish_ids()
	var result:=[]
	for index in ids.size():result.append(ids[(index+offset)%ids.size()])
	return result

func stall()->Vector2i:
	return Market.active_cell(host.world.state)

func place(token:String,cell:Vector2i)->void:
	var person:Dictionary=host.world.state.players[token]
	person.x=cell.x+0.5
	person.y=cell.y+0.5

func deep(value:Variant)->Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

func footprint(token:String)->Dictionary:
	var person:Dictionary=host.world.state.players[token]
	return {"coins":person.get("coins"),"inventory":deep(person.get("inventory",{})),"market":deep(person.get("market")),
		"spring":deep(person.get("spring_garden")),"picnic":host.world.state.get("picnic")}

func view_is(session:Session,active:bool,served:int,done:bool)->bool:
	var view:=own(session)
	return not view.is_empty() and bool(view.get("active",not active))==active and int(view.get("served",-1))==served and bool(view.get("completed",not done))==done

func wait_view(session:Session,active:bool,served:int,done:bool)->bool:
	return await wait_for(func():return view_is(session,active,served,done))

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

func serve(session:Session,token:String,dish:String)->bool:
	place(token,stall())
	return await act(session,stall(),"serve:"+dish)

func start_room(port:int)->bool:
	host=make_session("SeaHost%d"%sessions.size(),"sea-breeze-host")
	return host.host(port,"海風市集",path,ROOM,"127.0.0.1",true,"websocket")==OK

func free_port()->int:
	var listener:=TCPServer.new()
	if listener.listen(0,"127.0.0.1")!=OK:return 0
	var port:=listener.get_local_port()
	listener.stop()
	return port

func no_raw_key(viewers:Array)->bool:
	for viewer in viewers:
		if viewer.snapshot.has(F.KEY):return false
		for row in viewer.snapshot.get("players",{}).values():
			if row.has(F.KEY):return false
	return true

func guest_ok(session:Session)->bool:
	var guest:Variant=own(session).get("guest")
	return guest is Dictionary and not str(guest.get("name","")).is_empty() and not str(guest.get("clue","")).is_empty()

func run()->void:
	path=OS.get_environment("TEMP").path_join("sea-breeze-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	if not check(F.ACTION=="sea_breeze_fair" and F.KEY=="sea_breeze_fair" and F.VIEW_KEY=="own_sea_breeze_fair" and F.BOARD==Vector2i(40,29),"Rules constants match the contract"):return
	if not check(dish_ids()==["watermelon_platter","baked_potato","strawberry_jam"],"Dishes keep their insertion order"):return
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	fixture.state.time=SIGNUP_TIME
	for token in [ALPHA,BETA]:
		fixture.add_player(token,"海風客")
		var person:Dictionary=fixture.state.players[token]
		person.x=F.BOARD.x+0.5
		person.y=F.BOARD.y+0.5
		person.coins=123
		person.inventory.wood=5
	if not check(fixture.save(),"Save a day-14 summer world with the picnic done"):return
	var summer:=order_for(14%3)
	var winter_trap:String=order_for(0)[1]
	if not check(summer!=order_for(0) and winter_trap!=summer[1],"Day 14 and day 45 orders differ"):return
	var port:=free_port()
	if not check(port>0,"Allocate loopback port"):return
	address="ws://127.0.0.1:%d"%port
	if not check(start_room(port),"Start real dedicated WS room"):return
	var alpha:=make_session("Alpha",ALPHA)
	var beta:=make_session("Beta",BETA)
	if not check(alpha.join(address,port,"海風客",ROOM)==OK and beta.join(address,port,"海風客",ROOM)==OK,"Join alpha and beta"):return
	if not check(await wait_for(func():return not alpha.own_id.is_empty() and not beta.own_id.is_empty() and not own(alpha).is_empty() and not own(beta).is_empty()),"Both clients entered with a private fair view"):return
	if not check(stall()!=Market.NO_CELL,"The market stall is unlocked after the picnic"):return
	for viewer in [alpha,beta]:
		var first:=own(viewer)
		if not check(first.get("unlocked")==true and first.get("in_season")==true and first.get("active")==false and int(first.get("served",-1))==0 and first.get("completed")==false and first.get("can_start")==true and first.has("phase"),"Summer view allows a first start"):return
	if not check(no_raw_key([alpha,beta]),"Public rows and snapshots carry no raw fair record"):return
	var alpha_before:=footprint(ALPHA)
	var beta_before:=footprint(BETA)
	# Refusals before signup.
	place(ALPHA,F.BOARD+Vector2i(10,0))
	if not check(not await act(alpha,F.BOARD,"start") and view_is(alpha,false,0,false),"Cannot start from a distance"):return
	if not check(not await serve(alpha,ALPHA,summer[0]) and view_is(alpha,false,0,false),"Cannot serve before signing up"):return
	if not check(not await at_board(alpha,ALPHA,"finish"),"Cannot finish before signing up"):return
	if not check(await at_board(alpha,ALPHA,"start") and await wait_view(alpha,true,0,false),"Alpha signs up at the board"):return
	if not check(guest_ok(alpha),"The active run shows a guest with name and clue"):return
	if not check(not await at_board(alpha,ALPHA,"start"),"A second start is refused"):return
	# Wrong order and bad requests change nothing.
	var frozen:=own(alpha).duplicate(true)
	var frozen_cost:=footprint(ALPHA)
	if not check(not await serve(alpha,ALPHA,summer[1]) and not await serve(alpha,ALPHA,summer[2]),"Out-of-order dishes are refused"):return
	if not check(not await serve(alpha,ALPHA,"no_such_dish"),"An unknown dish is refused"):return
	place(ALPHA,F.BOARD)
	if not check(not await act(alpha,stall(),"serve:"+summer[0]),"Cannot serve from the board's distance"):return
	place(ALPHA,stall())
	if not check(not await act(alpha,F.BOARD,"serve:"+summer[0]),"Cannot serve at the board cell"):return
	if not check(not await at_board(alpha,ALPHA,"finish"),"Cannot finish with nothing served"):return
	if not check(own(alpha)==frozen and view_is(alpha,true,0,false) and footprint(ALPHA)==frozen_cost,"Refusals left view, wallet, bag and market untouched"):return
	# Correct first dish, then beta independently (with a 3-request burst: ok, duplicate refused, ok).
	if not check(await serve(alpha,ALPHA,summer[0]) and await wait_view(alpha,true,1,false),"Alpha serves the first dish in rotated order"):return
	if not check(footprint(ALPHA)==frozen_cost,"Loan ingredients did not touch alpha's inventory"):return
	if not check(view_is(beta,false,0,false),"Beta is untouched by alpha's progress"):return
	if not check(await at_board(beta,BETA,"start") and await wait_view(beta,true,0,false),"Beta signs up independently"):return
	place(BETA,stall())
	var results:=await burst(beta,[[stall(),"serve:"+summer[0]],[stall(),"serve:"+summer[0]],[stall(),"serve:"+summer[1]]])
	if not check(results==[true,false,true],"Burst answers arrive in order: serve, duplicate refused, serve"):return
	if not check(await wait_view(beta,true,2,false) and view_is(alpha,true,1,false),"Beta has two served, alpha still one"):return
	if not check(no_raw_key([alpha,beta]) and footprint(ALPHA)==alpha_before and footprint(BETA)==beta_before,"Still no raw key, wallet, bag or market change"):return
	# Persist and restart in winter.
	if not check(host.world.save(),"Save the room before restart"):return
	var saved:=World.new()
	if not check(saved.load_world(path) and saved.state.players[ALPHA].has(F.KEY) and saved.state.players[BETA].has(F.KEY),"Saved file holds both partial runs"):return
	for session in [alpha,beta,host]:session.shutdown()
	var port2:=free_port()
	if not check(port2>0,"Allocate a second loopback port"):return
	address="ws://127.0.0.1:%d"%port2
	if not check(start_room(port2),"Restart the dedicated room from the save"):return
	host.world.state.time=WINTER_TIME # test fixture: jump the server clock to winter (day 45)
	sent={}
	var alpha2:=make_session("Alpha2",ALPHA)
	var beta2:=make_session("Beta2",BETA)
	if not check(alpha2.join(address,port2,"海風客",ROOM)==OK and beta2.join(address,port2,"海風客",ROOM)==OK,"Rejoin after restart"):return
	if not check(await wait_for(func():return not own(alpha2).is_empty() and not own(beta2).is_empty() and own(alpha2).get("in_season")==false),"Both see winter after the restart"):return
	if not check(view_is(alpha2,true,1,false) and own(alpha2).can_start==false,"Alpha's partial run persisted"):return
	if not check(view_is(beta2,true,2,false) and own(beta2).can_start==false,"Beta's partial run persisted"):return
	# The signup-day order is pinned: the winter day's order must not apply to the old run.
	if not check(not await serve(alpha2,ALPHA,winter_trap) and view_is(alpha2,true,1,false),"A started run keeps its signup-day order in winter"):return
	place(ALPHA,stall())
	results=await burst(alpha2,[[stall(),"serve:"+summer[2]],[stall(),"serve:"+summer[1]],[stall(),"serve:"+summer[2]]])
	if not check(results.size()==3,"Alpha's burst was answered"):return
	if not check(results==[false,true,true],"Burst: skipping ahead refused, then both remaining dishes accepted"):return
	if not check(await wait_view(alpha2,true,3,false),"Alpha has served all three"):return
	if not check(await at_board(alpha2,ALPHA,"finish") and await wait_view(alpha2,false,0,true),"Alpha finishes the run started in summer"):return
	if not check(not await at_board(alpha2,ALPHA,"finish") and view_is(alpha2,false,0,true),"A duplicate finish is refused"):return
	if not check(view_is(beta2,true,2,false),"Beta's run is unaffected by alpha finishing"):return
	if not check(await serve(beta2,BETA,summer[2]) and await wait_view(beta2,true,3,false) and await at_board(beta2,BETA,"finish") and await wait_view(beta2,false,0,true),"Beta completes after summer ended"):return
	if not check(own(alpha2).can_start==true and own(beta2).can_start==true,"Completed players may replay in winter"):return
	# Winter replay uses day 45 offset 0.
	var replay:=order_for(0)
	if not check(await at_board(alpha2,ALPHA,"start") and await wait_view(alpha2,true,0,true),"Alpha replays in winter"):return
	if not check(view_is(beta2,false,0,true),"Beta is independent of alpha's replay"):return
	if not check(not await serve(alpha2,ALPHA,summer[0]) and view_is(alpha2,true,0,true),"Winter replay uses its own rotated order"):return
	for dish in replay:
		if not check(await serve(alpha2,ALPHA,dish),"Replay serves %s"%dish):return
	if not check(await wait_view(alpha2,true,3,true) and await at_board(alpha2,ALPHA,"finish") and await wait_view(alpha2,false,0,true),"Alpha completes the replay"):return
	# Whole-test economy and existing-feature guarantees.
	if not check(footprint(ALPHA)==alpha_before and footprint(BETA)==beta_before,"No coins, bags, market or picnic state changed for either client"):return
	if not check(no_raw_key([alpha2,beta2]),"No raw fair record leaked after restart"):return
	finish(0)
