extends "res://tests/network_egg_basket.gd"
## Real loopback WebSocket check of the T064 public tiller loan with a dedicated
## host and two independent clients. Every borrow / till request goes through the
## real client -> WebSocket -> Session -> World.act path, under the normal
## per-client rate limit (this test never sends more than a few requests a second).
##
## FIXTURES (deliberately not production gameplay, so the test stays fast and
## deterministic):
##  * the saved room starts at 10:00 on day 0 with picnic already true, so the
##    loan is open from the start;
##  * charcoal is seeded in the save: grower 3, friend 2 (nobody owns a tiller);
##  * players are placed beside the rack / on the till grounds by editing the
##    host's player position instead of walking there;
##  * the till grounds are picked on the fixture world with World.TILLER.plan
##    (free 3x3 blocks of open land) and re-verified on the host before use;
##  * the 0.8 s tiller cooldown is waited out in real time (host world clock);
##  * the host restart reuses the same save file on a freshly allocated port.
const PublicTiller=preload("res://scripts/public_tiller.gd")
const TILLER_ROOM:="public-tiller-test"
const NO_FUEL:="耕田機需要木炭，這次沒有施工"
const COOLING:="耕田機正在收起滾輪，稍候再試"
const NOTHING:="範圍內沒有可整地的空地，未消耗木炭"
var host:Session
var grower_id:=GROWER.sha256_text().left(16)
var friend_id:=FRIEND.sha256_text().left(16)

func finish(code:int) -> void:
	Engine.time_scale=1.0
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("PUBLIC_TILLER_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)

func place(token:String,cell:Vector2i) -> void:
	var person:Dictionary=host.world.state.players[token]
	person.x=cell.x+0.5
	person.y=cell.y+0.5

func own(session:Session) -> Dictionary:
	return session.snapshot.get("players",{}).get(session.own_id,{})

func bag(session:Session,item:String) -> int:
	return int(own(session).get("inventory",{}).get(item,0))

func host_bag(token:String,item:String) -> int:
	return int(host.world.state.players[token].inventory.get(item,0))

func host_flag(token:String) -> bool:
	return host.world.state.players[token].get(PublicTiller.FIELD,false)==true

func flag(session:Session) -> bool:
	return own(session).get(PublicTiller.FIELD,false)==true

func block(center:Vector2i) -> Array:
	var keys:=[]
	for y in range(center.y-1,center.y+2):
		for x in range(center.x-1,center.x+2):keys.append(World.key(Vector2i(x,y)))
	return keys

## Number of the given cells that are farmland with exactly this owner.
func owned(crops:Dictionary,keys:Array,owner:String) -> int:
	var count:=0
	for tile:String in keys:
		var crop:Dictionary=crops.get(tile,{})
		if not crop.is_empty() and crop.get("owner")==owner:count+=1
	return count

func tilled(crops:Dictionary,keys:Array) -> int:
	var count:=0
	for tile:String in keys:count+=int(crops.has(tile))
	return count

func sees(session:Session,keys:Array,owner_id:String) -> bool:
	return owned(session.snapshot.get("crops",{}),keys,owner_id)==keys.size()

## One request, awaited. Returns {"answered","ok","message"}.
func ask(session:Session,name:String,cell:Vector2i) -> Dictionary:
	var seen:int=notices[session].size()
	session.perform(name,cell)
	if not await wait_for(func():return notices[session].size()>seen):return {"answered":false,"ok":false,"message":""}
	var reply:Dictionary=notices[session][seen]
	return {"answered":true,"ok":bool(reply.ok),"message":String(reply.message)}

func refused(reply:Dictionary,message:String) -> bool:
	return reply.answered and not reply.ok and reply.message==message

func describe(reply:Dictionary) -> String:
	return " (answered=%s ok=%s message=%s)"%[reply.answered,reply.ok,reply.message]

func cooled(token:String) -> bool:
	return await wait_for(func():
		return float(host.world.state.time)-float(host.world.state.players[token].get("last_till",{}).get("at",-10.0))>=World.TILLER.COOLDOWN+0.15)

func full_plan(world:World,token:String,center:Vector2i) -> bool:
	world.state.players[token].x=center.x+0.5
	world.state.players[token].y=center.y+0.5
	return World.TILLER.plan(world,token,center).cells.size()==9

func saved_matches(check:Callable,seconds:float=20.0) -> bool:
	return await wait_for(func():
		var saved:=World.new()
		return saved.load_world(path) and check.call(saved.state),seconds)

func free_port() -> int:
	var listener:=TCPServer.new()
	if listener.listen(0,"127.0.0.1")!=OK:return 0
	var port:=listener.get_local_port()
	listener.stop()
	return port

func settle() -> void:
	for i in 20:await process_frame

func run() -> void:
	path="user://public-tiller-session-%d.json"%OS.get_process_id()
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	fixture.state.time=600.0
	for token in [GROWER,FRIEND]:fixture.add_player(token,"Farmer")
	fixture.state.players[GROWER].inventory.charcoal=3
	fixture.state.players[FRIEND].inventory.charcoal=2
	var rack:=PublicTiller.site(fixture.state)
	var loan:=PublicTiller.loan_cell(fixture.state)
	if not check(rack!=PublicTiller.NO_SITE and loan==rack and rack==PublicTiller.SITES[0],"The fixture room has the rack on its first site"):return
	var stand:=PublicTiller.NO_SITE
	for offset:Vector2i in [Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP]:
		var cell:Vector2i=rack+offset
		if fixture.is_land(cell) and not fixture.blocked(cell):
			stand=cell
			break
	if not check(stand!=PublicTiller.NO_SITE,"A walkable cell exists next to the rack"):return
	# Till grounds: a free 5x3 strip (g1 plus the friend's overlapping pass two
	# cells to the right) and three more free 3x3 blocks, all pairwise disjoint.
	var grounds:Array[Vector2i]=[]
	var used:={}
	var overlap:=Vector2i.ZERO
	for y in range(20,52):
		for x in range(24,66):
			if grounds.size()>=4:break
			var center:=Vector2i(x,y)
			var cells:=block(center)
			if grounds.is_empty():cells.append_array(block(center+Vector2i(2,0)))
			var clear:=true
			for tile:String in cells:
				if used.has(tile):clear=false
			for site:Vector2i in PublicTiller.SITES:
				if World.key(site) in cells or site==center:clear=false
			if World.key(stand) in cells:clear=false
			if not clear or not full_plan(fixture,GROWER,center):continue
			if grounds.is_empty() and not full_plan(fixture,GROWER,center+Vector2i(2,0)):continue
			if grounds.is_empty():overlap=center+Vector2i(2,0)
			grounds.append(center)
			for tile:String in cells:used[tile]=true
	if not check(grounds.size()==4,"The fixture island has four free till grounds (found %d)"%grounds.size()):return
	var g1:=grounds[0]
	var g2:=grounds[1]
	var g3:=grounds[2]
	var g4:=grounds[3]
	var fresh:=[] # the six cells of the friend's overlapping pass that are not in g1
	for tile:String in block(overlap):
		if tile not in block(g1):fresh.append(tile)
	for token in [GROWER,FRIEND]:
		fixture.state.players[token].x=stand.x+0.5
		fixture.state.players[token].y=stand.y+0.5
	if not check(fixture.state.crops.is_empty() or tilled(fixture.state.crops,used.keys())==0,"The chosen grounds start untilled"):return
	if not check(fixture.save(),"Save a picnic room with two fuel-carrying players"):return

	var port:=free_port()
	if not check(port>0,"Allocate a loopback port"):return
	var address:="ws://127.0.0.1:%d"%port
	host=make_session("TillHost","public-tiller-host")
	if not check(host.host(port,"Host",path,TILLER_ROOM,"127.0.0.1",true,"websocket")==OK,"Start a dedicated WebSocket room"):return
	var grower:=make_session("TillOne",GROWER)
	var friend:=make_session("TillTwo",FRIEND)
	if not check(grower.join(address,port,"One",TILLER_ROOM)==OK and friend.join(address,port,"Two",TILLER_ROOM)==OK,"Connect two WebSocket clients"):return
	if not check(await wait_for(func():return not own(grower).is_empty() and not own(friend).is_empty()),"Both clients entered the island"):return
	await settle()
	if not check(grower.own_id==grower_id and friend.own_id==friend_id,"Client ids are the public hashes of the tokens"):return
	if not check(PublicTiller.loan_cell(host.world.state)==loan and bool(host.world.state.picnic),"The host has the loan open at the rack"):return
	if not check(not host_flag(GROWER) and not host_flag(FRIEND) and host_bag(GROWER,"tiller")==0 and host_bag(FRIEND,"tiller")==0,"Nobody starts with a loan or a tiller"):return
	if not check(bag(grower,"charcoal")==3 and bag(friend,"charcoal")==2,"Clients see their seeded charcoal"):return

	# --- 1. No machine yet -----------------------------------------------------
	place(GROWER,g1)
	if not check(World.TILLER.plan(host.world,GROWER,g1).cells.size()==9,"Host agrees g1 is nine free cells"):return
	var reply:=await ask(grower,"till_area",g1)
	if not check(refused(reply,PublicTiller.NEED_MACHINE),"Tilling without a machine is refused"+describe(reply)):return
	if not check(tilled(host.world.state.crops,block(g1))==0 and host_bag(GROWER,"charcoal")==3,"The refused pass tilled nothing and cost no charcoal"):return

	# --- 2. Grower borrows -----------------------------------------------------
	place(GROWER,stand)
	place(FRIEND,stand)
	reply=await ask(grower,PublicTiller.ACTION,loan)
	if not check(reply.answered and reply.ok and reply.message==PublicTiller.OPENED,"The grower borrows the public tiller"+describe(reply)):return
	reply=await ask(grower,PublicTiller.ACTION,loan)
	if not check(refused(reply,PublicTiller.ALREADY),"A duplicate borrow is refused"+describe(reply)):return
	if not check(host_flag(GROWER) and host_bag(GROWER,"tiller")==0 and not host.world.state.players[GROWER].inventory.has(PublicTiller.FIELD),"Host holds a flag, not an inventory item"):return
	if not check(host_bag(GROWER,"charcoal")==3,"Borrowing costs no charcoal"):return
	if not check(await wait_for(func():return flag(grower)),"The grower's own snapshot shows the loan flag"):return
	if not check(bag(grower,"tiller")==0,"The grower's snapshot bag has no tiller"):return
	if not check(not host_flag(FRIEND) and not flag(friend) and host_bag(FRIEND,"tiller")==0,"The friend's flag stays false on host and in their own snapshot"):return

	# --- 3. The loan is personal ------------------------------------------------
	place(FRIEND,g2)
	reply=await ask(friend,"till_area",g2)
	if not check(refused(reply,PublicTiller.NEED_MACHINE),"The friend cannot use the grower's loan"+describe(reply)):return
	if not check(tilled(host.world.state.crops,block(g2))==0 and host_bag(FRIEND,"charcoal")==2 and not host_flag(FRIEND),"The friend's refused pass changed nothing"):return

	# --- 4. Grower tills with fuel, cooldown, fresh ground ---------------------
	place(GROWER,g1)
	reply=await ask(grower,"till_area",g1)
	if not check(reply.answered and reply.ok,"The grower's first pass succeeds"+describe(reply)):return
	place(GROWER,g2)
	var hasty:=await ask(grower,"till_area",g2)
	if not check(host_bag(GROWER,"charcoal")==2,"Exactly one charcoal was spent (host has %d)"%host_bag(GROWER,"charcoal")):return
	if not check(owned(host.world.state.crops,block(g1),GROWER)==9,"Nine new plots are owned by the grower's token"):return
	if not check(refused(hasty,COOLING),"An immediate second pass is refused by the cooldown"+describe(hasty)):return
	if not check(tilled(host.world.state.crops,block(g2))==0,"The cooldown refusal tilled nothing"):return
	if not check(await wait_for(func():return sees(grower,block(g1),grower_id) and sees(friend,block(g1),grower_id)),"Both clients see the grower's nine plots"):return
	if not check(await wait_for(func():return bag(grower,"charcoal")==2),"The grower's snapshot shows charcoal 2"):return
	if not check(await cooled(GROWER),"The cooldown passes"):return
	reply=await ask(grower,"till_area",g2)
	if not check(reply.answered and reply.ok and host_bag(GROWER,"charcoal")==1 and owned(host.world.state.crops,block(g2),GROWER)==9,"After the cooldown a pass on fresh ground succeeds for one more charcoal"+describe(reply)):return

	# --- 5. Friend borrows independently ---------------------------------------
	place(FRIEND,stand)
	reply=await ask(friend,PublicTiller.ACTION,loan)
	if not check(reply.answered and reply.ok and reply.message==PublicTiller.OPENED,"The friend borrows independently"+describe(reply)):return
	reply=await ask(friend,PublicTiller.ACTION,loan)
	if not check(refused(reply,PublicTiller.ALREADY),"The friend's duplicate borrow is refused"+describe(reply)):return
	if not check(host_flag(FRIEND) and host_flag(GROWER) and host_bag(FRIEND,"tiller")==0 and host_bag(FRIEND,"charcoal")==2,"Both flags are set, still no tiller item, no fuel spent"):return
	if not check(await wait_for(func():return flag(friend) and flag(grower)),"Each client sees their own flag"):return
	place(FRIEND,g1)
	reply=await ask(friend,"till_area",g1)
	if not check(refused(reply,NOTHING),"A pass entirely over the grower's plots tills nothing"+describe(reply)):return
	if not check(host_bag(FRIEND,"charcoal")==2 and owned(host.world.state.crops,block(g1),GROWER)==9,"That pass spent nothing and left the owners alone"):return
	place(FRIEND,overlap)
	reply=await ask(friend,"till_area",overlap)
	if not check(reply.answered and reply.ok and reply.message.contains("6 格"),"The friend's overlapping pass tills only the six free cells"+describe(reply)):return
	if not check(host_bag(FRIEND,"charcoal")==1 and host_bag(GROWER,"charcoal")==1,"The friend paid their own charcoal"):return
	if not check(owned(host.world.state.crops,fresh,FRIEND)==6,"The six new plots are owned by the friend"):return
	if not check(owned(host.world.state.crops,block(g1),GROWER)==9 and owned(host.world.state.crops,block(g2),GROWER)==9,"The grower's plots keep their owner"):return
	if not check(await wait_for(func():return sees(grower,fresh,friend_id) and sees(friend,fresh,friend_id) and sees(grower,block(g1),grower_id) and sees(friend,block(g1),grower_id) and sees(friend,block(g2),grower_id)),"Both clients agree on every plot owner"):return

	# --- 6. Reconnect ----------------------------------------------------------
	grower.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host saw the grower disconnect"):return
	if not check(host_flag(GROWER),"The flag survives the disconnect on the host"):return
	var returned:=make_session("TillReturned",GROWER)
	if not check(returned.join(address,port,"One",TILLER_ROOM)==OK,"Reconnect the grower's profile"):return
	if not check(await wait_for(func():return not own(returned).is_empty() and flag(returned)),"The reconnected snapshot still has the loan flag"):return
	await settle()
	if not check(bag(returned,"tiller")==0 and host_bag(GROWER,"tiller")==0 and bag(returned,"charcoal")==1,"Reconnecting created no tiller item and kept the charcoal"):return
	place(GROWER,stand)
	reply=await ask(returned,PublicTiller.ACTION,loan)
	if not check(refused(reply,PublicTiller.ALREADY),"Re-borrowing after reconnect is refused"+describe(reply)):return
	if not check(await cooled(GROWER),"Cooldown is over before the reconnected pass"):return
	place(GROWER,g3)
	reply=await ask(returned,"till_area",g3)
	if not check(reply.answered and reply.ok and host_bag(GROWER,"charcoal")==0 and owned(host.world.state.crops,block(g3),GROWER)==9,"The reconnected grower tills with the last charcoal"+describe(reply)):return
	if not check(await wait_for(func():return sees(returned,block(g3),grower_id) and sees(friend,block(g3),grower_id)),"Both clients see the reconnected grower's plots"):return
	if not check(await cooled(GROWER),"Cooldown is over before the no-fuel pass"):return
	place(GROWER,g4)
	reply=await ask(returned,"till_area",g4)
	if not check(refused(reply,NO_FUEL),"With no charcoal the next pass is refused"+describe(reply)):return
	if not check(tilled(host.world.state.crops,block(g4))==0 and host_bag(GROWER,"charcoal")==0 and host_flag(GROWER),"The no-fuel pass tilled nothing and the loan stays"):return

	# --- 7. Save, then restart the host from the same file ---------------------
	var saved_ok:=func(state:Dictionary) -> bool:
		var a:Dictionary=state.players[GROWER]
		var b:Dictionary=state.players[FRIEND]
		return (a.get(PublicTiller.FIELD)==true and b.get(PublicTiller.FIELD)==true
			and not a.inventory.has("tiller") and not b.inventory.has("tiller")
			and int(a.inventory.get("charcoal",0))==0 and int(b.inventory.get("charcoal",0))==1
			and owned(state.crops,block(g1),GROWER)==9 and owned(state.crops,block(g2),GROWER)==9
			and owned(state.crops,block(g3),GROWER)==9 and owned(state.crops,fresh,FRIEND)==6
			and tilled(state.crops,block(g4))==0 and state.crops.size()==33)
	if not check(await saved_matches(saved_ok),"The periodic room save holds both flags, no tiller items, fuel and plot owners"):return
	returned.shutdown()
	friend.shutdown()
	if not check(await wait_for(func():return host.peers.is_empty()),"Host saw both clients leave"):return
	if not check(host.shutdown(),"The first host saves and shuts down"):return
	await settle()
	if not check(await saved_matches(saved_ok,2.0),"The final save of the first host still matches"):return
	var port2:=free_port()
	if not check(port2>0,"Allocate a second loopback port"):return
	var address2:="ws://127.0.0.1:%d"%port2
	host=make_session("TillHostTwo","public-tiller-host")
	if not check(host.host(port2,"Host",path,TILLER_ROOM,"127.0.0.1",true,"websocket")==OK,"Restart a host from the same save"):return
	if not check(host_flag(GROWER) and host_flag(FRIEND) and host_bag(GROWER,"tiller")==0 and host_bag(FRIEND,"tiller")==0,"The restarted host loaded both flags and no tiller items"):return
	var grower2:=make_session("TillOneAgain",GROWER)
	var friend2:=make_session("TillTwoAgain",FRIEND)
	if not check(grower2.join(address2,port2,"One",TILLER_ROOM)==OK and friend2.join(address2,port2,"Two",TILLER_ROOM)==OK,"Rejoin both clients after the restart"):return
	if not check(await wait_for(func():return not own(grower2).is_empty() and not own(friend2).is_empty() and flag(grower2) and flag(friend2)),"Both rejoined snapshots still have the loan flag"):return
	await settle()
	if not check(bag(grower2,"tiller")==0 and bag(friend2,"tiller")==0 and bag(grower2,"charcoal")==0 and bag(friend2,"charcoal")==1,"Rejoined bags have no tiller and the saved charcoal"):return
	if not check(sees(grower2,block(g1),grower_id) and sees(friend2,fresh,friend_id) and sees(friend2,block(g3),grower_id),"Rejoined clients see the saved plot owners"):return
	place(GROWER,stand)
	place(FRIEND,stand)
	reply=await ask(grower2,PublicTiller.ACTION,loan)
	if not check(refused(reply,PublicTiller.ALREADY),"Re-borrowing after the restart is refused"+describe(reply)):return
	place(GROWER,g4)
	reply=await ask(grower2,"till_area",g4)
	if not check(refused(reply,NO_FUEL) and tilled(host.world.state.crops,block(g4))==0,"After the restart the grower still has the loan but no fuel"+describe(reply)):return
	place(FRIEND,g4)
	reply=await ask(friend2,"till_area",g4)
	if not check(reply.answered and reply.ok and host_bag(FRIEND,"charcoal")==0 and owned(host.world.state.crops,block(g4),FRIEND)==9,"After the restart the friend tills with the surviving loan"+describe(reply)):return
	if not check(await wait_for(func():return sees(grower2,block(g4),friend_id) and sees(friend2,block(g4),friend_id)),"Both clients see the friend's post-restart plots"):return
	if not check(owned(host.world.state.crops,block(g1),GROWER)==9 and host.world.state.crops.size()==42,"No other plot changed owner (42 plots in total)"):return
	finish(0)
