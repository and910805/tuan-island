extends "res://tests/network_egg_basket.gd"
## Real loopback WebSocket check of the per-player wildlife visitors
## (courtyard hedgehog + woodland squirrel) with two independent clients.
##
## FIXTURES (deliberately not production gameplay, so the test stays fast and
## deterministic; every wildlife action itself goes through the real client ->
## WebSocket -> Session -> World.act path):
##  * the saved room starts at 10:00 on day 0 with picnic enabled;
##  * radishes (grower 2, friend 1) and one starting acorn for the friend are
##    seeded in the save instead of farming/gathering them;
##  * the host world's clock is advanced with World.step() to reach "next
##    morning" / the next day instead of waiting in real time;
##  * players are placed beside the hedgehog dish / squirrel tree by editing the
##    host's player position instead of walking there.
const Hedgehog=preload("res://scripts/courtyard_hedgehog.gd")
const Squirrel=preload("res://scripts/woodland_squirrel.gd")
const DAY:=1440.0
const PRIVATE_FIELDS:=["hedgehog_visit_day","hedgehog_observed_day","squirrel_day","inventory"]
const WILDLIFE_ROOM:="wildlife-private-test"
## Mirrors the production per-client action limit in scripts/session.gd `_action`
## (12 accepted requests per sliding 1000 ms, then RATE_MESSAGE). The product has
## no named constants for these, so keep the three values in step with it.
const RATE_LIMIT:=12
const RATE_WINDOW_MSEC:=1000
const RATE_MARGIN_MSEC:=250
const RATE_MESSAGE:="操作太快了，稍等一下再試。"
var host:Session
var sent:Dictionary={}

## Waits until `session` can send `count` more requests without tripping the
## normal rate limit. The limit itself stays on; fixtures just pace like a player.
func pace(session:Session,count:int) -> void:
	if not sent.has(session):sent[session]=[]
	var stamps:Array=sent[session]
	while true:
		var now:=Time.get_ticks_msec()
		while not stamps.is_empty() and now-int(stamps[0])>RATE_WINDOW_MSEC+RATE_MARGIN_MSEC:stamps.pop_front()
		if stamps.size()+count<=RATE_LIMIT:return
		await process_frame

func send(session:Session,action:String,cell:Vector2i) -> void:
	if not sent.has(session):sent[session]=[]
	sent[session].append(Time.get_ticks_msec())
	session.perform(action,cell)

func finish(code:int) -> void:
	Engine.time_scale=1.0
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WILDLIFE_PRIVATE_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)

func dish() -> Vector2i:
	return Hedgehog.site(host.world.state)

func place(token:String,cell:Vector2i) -> void:
	var person:Dictionary=host.world.state.players[token]
	person.x=cell.x+0.5
	person.y=cell.y+0.5

func place_both(cell:Vector2i) -> void:
	place(GROWER,cell)
	place(FRIEND,cell)

func advance_to(target:float,watchers:Array) -> bool:
	var delta:=target-float(host.world.state.time)
	if delta<0.0 or not host.world.step(delta,true):return false
	return await wait_for(func():
		for watcher:Session in watchers:
			if float(watcher.snapshot.get("time",0.0))<target:return false
		return true)

func own(session:Session) -> Dictionary:
	return session.snapshot.get("players",{}).get(session.own_id,{})

func seen_by(observer:Session,subject:Session) -> Dictionary:
	return observer.snapshot.get("players",{}).get(subject.own_id,{})

func bag(session:Session,item:String) -> int:
	return int(own(session).get("inventory",{}).get(item,0))

func host_bag(token:String,item:String) -> int:
	return int(host.world.state.players[token].inventory.get(item,0))

## Sends several actions without waiting between them, then waits until every
## request has been answered. Returns {session:[ok,...]} in answer order.
func fire(requests:Array) -> Dictionary:
	var wanted:={}
	for request:Array in requests:
		var session:Session=request[0]
		wanted[session]=int(wanted.get(session,0))+int(request[3])
	for session:Session in wanted:
		await pace(session,int(wanted[session]))
	var starts:={}
	for session:Session in wanted:
		starts[session]=notices[session].size()
	for request:Array in requests:
		var session:Session=request[0]
		for i in int(request[3]):send(session,request[1],request[2])
	var answered:=await wait_for(func():
		for session:Session in wanted:
			if notices[session].size()<int(starts[session])+int(wanted[session]):return false
		return true)
	var results:={}
	for session:Session in wanted:
		results[session]=[]
		if not answered:continue
		for i in int(wanted[session]):results[session].append(bool(notices[session][int(starts[session])+i].ok))
	results["answered"]=answered
	return results

func successes(list:Array) -> int:
	var count:=0
	for ok:bool in list:count+=int(ok)
	return count

func leaks_nothing(observer:Session,subject:Session,fields:Array) -> bool:
	var view:=seen_by(observer,subject)
	if view.is_empty():return false
	for field:String in fields:
		if view.has(field):return false
	return true

func saved_matches(check:Callable) -> bool:
	return await wait_for(func():
		var saved:=World.new()
		return saved.load_world(path) and check.call(saved.state))

func run() -> void:
	path="user://wildlife-private-%d.json"%OS.get_process_id()
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	fixture.state.time=600.0
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"Farmer")
	fixture.state.players[GROWER].inventory.radish=2
	fixture.state.players[FRIEND].inventory.radish=1
	fixture.state.players[FRIEND].inventory[Squirrel.ACORN]=1
	var dish_cell:=Hedgehog.site(fixture.state)
	for token in [GROWER,FRIEND]:
		fixture.state.players[token].x=dish_cell.x+0.5
		fixture.state.players[token].y=dish_cell.y+0.5
	if not check(fixture.save(),"Save a room with two wildlife visitors' players"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var address:="ws://127.0.0.1:%d"%port
	host=make_session("WildHost","wildlife-host")
	if not check(host.host(port,"Host",path,WILDLIFE_ROOM,"127.0.0.1",true,"websocket")==OK,"Start a dedicated WebSocket room"):return
	var grower:=make_session("WildOne",GROWER)
	var friend:=make_session("WildTwo",FRIEND)
	if not check(grower.join(address,port,"One",WILDLIFE_ROOM)==OK and friend.join(address,port,"Two",WILDLIFE_ROOM)==OK,"Connect two WebSocket clients"):return
	if not check(await wait_for(func():return not grower.own_id.is_empty() and not friend.own_id.is_empty() and not own(grower).is_empty() and not own(friend).is_empty()),"Both clients entered the island"):return
	if not check(float(host.world.state.time)>=600.0 and float(host.world.state.time)<640.0,"Fixture clock is still mid-morning on day 0"):return
	if not check(dish_cell==dish() and Hedgehog.phase(host.world.state.players[GROWER],float(host.world.state.time))=="empty","Neither player has a hedgehog visit yet"):return

	# --- Courtyard hedgehog: same-time independent food -----------------------
	place_both(dish())
	var food:=await fire([[grower,"hedgehog_leave_food",dish(),2],[friend,"hedgehog_leave_food",dish(),1]])
	if not check(food.answered,"Both simultaneous food requests were answered"):return
	if not check(successes(food[grower])==1 and successes(food[friend])==1,"Each player leaves food once; the grower's duplicate retry is refused"):return
	if not check(host_bag(GROWER,"radish")==1 and host_bag(FRIEND,"radish")==0,"The retry cost no extra radish and each player paid their own"):return
	if not check(int(host.world.state.players[GROWER].hedgehog_visit_day)==1 and int(host.world.state.players[FRIEND].hedgehog_visit_day)==1,"Both private visits are booked for the next morning"):return
	if not check(await wait_for(func():return int(own(grower).get("hedgehog_visit_day",-1))==1 and int(own(friend).get("hedgehog_visit_day",-1))==1 and bag(grower,"radish")==1 and bag(friend,"radish")==0),"Each client sees their own booking and radish count"):return
	if not check(leaks_nothing(grower,friend,PRIVATE_FIELDS) and leaks_nothing(friend,grower,PRIVATE_FIELDS),"Neither client receives the other's hedgehog booking or inventory"):return
	var early:=await fire([[grower,"hedgehog_observe",dish(),1],[friend,"hedgehog_observe",dish(),1]])
	if not check(early.answered and successes(early[grower])+successes(early[friend])==0,"Observing before the next morning is refused for both"):return

	# --- Woodland squirrel, day 0 (still 10:00): simultaneous daily acorn -----
	place_both(Squirrel.SITE)
	var first:=await fire([[grower,"squirrel_observe",Squirrel.SITE,2],[friend,"squirrel_observe",Squirrel.SITE,1]])
	if not check(first.answered and successes(first[grower])==1 and successes(first[friend])==1,"Each player takes exactly one acorn on day 0, retry refused"):return
	if not check(host_bag(GROWER,Squirrel.ACORN)==1 and host_bag(FRIEND,Squirrel.ACORN)==2,"Acorn counts are independent and the retry added nothing"):return
	if not check(await wait_for(func():return int(own(grower).get("squirrel_day",-1))==0 and int(own(friend).get("squirrel_day",-1))==0 and bag(grower,Squirrel.ACORN)==1 and bag(friend,Squirrel.ACORN)==2),"Each client sees only their own acorn state"):return
	if not check(leaks_nothing(grower,friend,PRIVATE_FIELDS) and leaks_nothing(friend,grower,PRIVATE_FIELDS),"Neither client receives the other's squirrel history"):return
	var cannot:=await fire([[grower,"squirrel_exchange",Squirrel.SITE,1],[friend,"squirrel_exchange",Squirrel.SITE,1]])
	if not check(cannot.answered and successes(cannot[grower])+successes(cannot[friend])==0 and host_bag(FRIEND,Squirrel.ACORN)==2,"Two acorns are not enough to trade; nothing is spent"):return

	# --- Hedgehog next-morning observation ------------------------------------
	if not check(await advance_to(DAY+400.0,[grower,friend]),"Advance the fixture clock to 06:40 on day 1"):return
	place_both(dish())
	if not check(Hedgehog.phase(host.world.state.players[GROWER],float(host.world.state.time))=="visiting" and Hedgehog.phase(host.world.state.players[FRIEND],float(host.world.state.time))=="visiting","Both visits are now open"):return
	var look:=await fire([[grower,"hedgehog_observe",dish(),2],[friend,"hedgehog_observe",dish(),1]])
	if not check(look.answered and successes(look[grower])==1 and successes(look[friend])==1,"Each player observes once; the grower's retry cannot reuse the visit"):return
	if not check(int(host.world.state.players[GROWER].hedgehog_observed_day)==1 and int(host.world.state.players[FRIEND].hedgehog_observed_day)==1,"Each private observation is recorded for day 1"):return
	if not check(await wait_for(func():return int(own(grower).get("hedgehog_observed_day",-1))==1 and int(own(friend).get("hedgehog_observed_day",-1))==1),"Each client sees their own observation"):return
	if not check(leaks_nothing(grower,friend,PRIVATE_FIELDS) and leaks_nothing(friend,grower,PRIVATE_FIELDS),"Observation days are not leaked either"):return
	var again:=await fire([[grower,"hedgehog_observe",dish(),1],[friend,"hedgehog_observe",dish(),1]])
	if not check(again.answered and successes(again[grower])+successes(again[friend])==0,"Later retries from either player fail"):return
	var refill:=await fire([[grower,"hedgehog_leave_food",dish(),1]])
	if not check(refill.answered and not refill[grower][0] and host_bag(GROWER,"radish")==1,"The grower's leftover radish was not spent on a visited dish"):return

	# --- Squirrel days 1 and 2, then own trade costs --------------------------
	for day in [1,2]:
		if not check(await advance_to(DAY*day+600.0,[grower,friend]),"Advance the fixture clock to 10:00 on day %d"%day):return
		place_both(Squirrel.SITE)
		var daily:=await fire([[grower,"squirrel_observe",Squirrel.SITE,2],[friend,"squirrel_observe",Squirrel.SITE,2]])
		if not check(daily.answered and successes(daily[grower])==1 and successes(daily[friend])==1,"Day %d: one acorn per player despite same-time retries"%day):return
		if not check(host_bag(GROWER,Squirrel.ACORN)==day+1 and host_bag(FRIEND,Squirrel.ACORN)==day+2,"Day %d: acorn counts match one per player"%day):return
	if not check(host_bag(GROWER,Squirrel.ACORN)==3 and host_bag(FRIEND,Squirrel.ACORN)==4,"Grower has 3 acorns and the fixture friend has 4"):return
	if not check(await wait_for(func():return bag(grower,Squirrel.ACORN)==3 and bag(friend,Squirrel.ACORN)==4 and int(own(grower).get("squirrel_day",-1))==2),"Clients see their own day-2 totals"):return

	# --- Normal rate limit: a 13-request burst is refused, then service resumes -
	# The friend already took today's acorn, so every accepted request is refused
	# by the world and changes nothing; only the 13th should hit the rate limit.
	await pace(friend,RATE_LIMIT)
	var burst_start:int=notices[friend].size()
	for i in RATE_LIMIT+1:send(friend,"squirrel_observe",Squirrel.SITE)
	var limited:=func() -> int:
		var count:=0
		for i in range(burst_start,notices[friend].size()):
			if String(notices[friend][i].message)==RATE_MESSAGE and not bool(notices[friend][i].ok):count+=1
		return count
	if not check(await wait_for(func():return notices[friend].size()>=burst_start+RATE_LIMIT+1 and int(limited.call())>=1),"A burst of %d requests gets the rate-limit refusal"%(RATE_LIMIT+1)):return
	var world_answers:=0
	var burst_ok:=0
	for i in range(burst_start,notices[friend].size()):
		if String(notices[friend][i].message)!=RATE_MESSAGE:world_answers+=1
		burst_ok+=int(bool(notices[friend][i].ok))
	if not check(world_answers==RATE_LIMIT and int(limited.call())==1 and burst_ok==0,"Exactly %d requests reach the world and only the next one is rate limited"%RATE_LIMIT):return
	if not check(host_bag(FRIEND,Squirrel.ACORN)==4 and host_bag(GROWER,Squirrel.ACORN)==3,"The refused burst changed no acorn counts"):return
	if not check(leaks_nothing(grower,friend,PRIVATE_FIELDS),"The burst leaked nothing to the other client"):return
	var resumed:=await fire([[friend,"squirrel_observe",Squirrel.SITE,1]])
	if not check(resumed.answered and not resumed[friend][0] and String(notices[friend].back().message)!=RATE_MESSAGE,"After the window passes the friend gets the normal same-day answer again"):return
	var trade:=await fire([[grower,"squirrel_exchange",Squirrel.SITE,2],[friend,"squirrel_exchange",Squirrel.SITE,1]])
	if not check(trade.answered and successes(trade[grower])==1 and successes(trade[friend])==1,"Each player trades once; the grower's duplicate cannot afford a second kit"):return
	if not check(host_bag(GROWER,Squirrel.ACORN)==0 and host_bag(GROWER,Squirrel.KIT)==1,"The grower paid exactly three acorns for one kit"):return
	if not check(host_bag(FRIEND,Squirrel.ACORN)==1 and host_bag(FRIEND,Squirrel.KIT)==1,"The friend paid their own three acorns and kept the fourth"):return
	if not check(await wait_for(func():return bag(grower,Squirrel.ACORN)==0 and bag(grower,Squirrel.KIT)==1 and bag(friend,Squirrel.ACORN)==1 and bag(friend,Squirrel.KIT)==1),"Both clients show their own post-trade bags"):return
	if not check(leaks_nothing(grower,friend,PRIVATE_FIELDS) and leaks_nothing(friend,grower,PRIVATE_FIELDS),"Trade results stay private"):return

	# --- Reconnect and save ---------------------------------------------------
	grower.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host saw the grower disconnect"):return
	var returned:=make_session("WildReturned",GROWER)
	if not check(returned.join(address,port,"One",WILDLIFE_ROOM)==OK,"Reconnect the grower's profile"):return
	if not check(await wait_for(func():return not returned.own_id.is_empty() and int(own(returned).get("squirrel_day",-1))==2 and int(own(returned).get("hedgehog_observed_day",-1))==1),"Reconnected client recovers its private wildlife history"):return
	if not check(bag(returned,Squirrel.ACORN)==0 and bag(returned,Squirrel.KIT)==1,"Reconnected bag keeps the trade result"):return
	if not check(await wait_for(func():return leaks_nothing(friend,returned,PRIVATE_FIELDS)),"The reconnected grower is still hidden from the friend"):return
	place(GROWER,Squirrel.SITE)
	var after:=await fire([[returned,"squirrel_observe",Squirrel.SITE,1],[returned,"squirrel_exchange",Squirrel.SITE,1]])
	if not check(after.answered and successes(after[returned])==0 and host_bag(GROWER,Squirrel.ACORN)==0 and host_bag(GROWER,Squirrel.KIT)==1,"Reconnecting cannot repeat the day's acorn or the trade"):return
	if not check(await saved_matches(func(state:Dictionary):
		var a:Dictionary=state.players[GROWER]
		var b:Dictionary=state.players[FRIEND]
		return (int(a.inventory.get(Squirrel.ACORN,0))==0 and int(a.inventory.get(Squirrel.KIT,0))==1 and int(a.inventory.get("radish",0))==1
			and int(b.inventory.get(Squirrel.ACORN,0))==1 and int(b.inventory.get(Squirrel.KIT,0))==1 and int(b.inventory.get("radish",0))==0
			and int(a.squirrel_day)==2 and int(b.squirrel_day)==2
			and int(a.hedgehog_visit_day)==1 and int(a.hedgehog_observed_day)==1
			and int(b.hedgehog_visit_day)==1 and int(b.hedgehog_observed_day)==1)),"The room save holds each player's own wildlife state exactly once"):return
	finish(0)
