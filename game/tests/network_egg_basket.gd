extends SceneTree
## Runs a dedicated host and isolated client MultiplayerAPIs over real loopback WS.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Industry=preload("res://scripts/industry.gd")
const HEN:=World.CHICKEN_CELL
const BENCH:=HEN+Vector2i.LEFT
const COLLECTOR_SITE:=HEN+Vector2i.DOWN
const COLLECTOR_KEY:="animal_collector_kit"
const PEN_SITE:=Vector2i(48,36)
const ROOM:="basket-test"
const GROWER:="egg-network-grower"
const FRIEND:="egg-network-friend"
var sessions:Array[Session]=[]
var notices:Dictionary={}
var path:="user://egg-network-%d.json"%OS.get_process_id()
var checks:=0

func _initialize() -> void:
	run.call_deferred()

func make_session(branch_name:String,token:String) -> Session:
	var branch:=Node.new()
	branch.name=branch_name
	root.add_child(branch)
	set_multiplayer(MultiplayerAPI.create_default_interface(),branch.get_path())
	var session:=Session.new()
	branch.add_child(session)
	session.profile={"token":token}
	sessions.append(session)
	notices[session]=[]
	session.notice.connect(func(message:String,ok:bool):notices[session].append({"message":message,"ok":ok}))
	return session

func wait_for(predicate:Callable,seconds:float=10.0) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await process_frame
	return predicate.call()

func check(condition:bool,message:String) -> bool:
	checks+=1
	if condition:return true
	push_error(message)
	finish(1)
	return false

func finish(code:int) -> void:
	Engine.time_scale=1.0
	for i in range(sessions.size()-1,-1,-1):
		if not sessions[i].shutting_down:sessions[i].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("EGG_BASKET_NETWORK checks=%d exit=%d"%[checks,code])
	quit(code)

func seeded_world() -> bool:
	var world:=World.new()
	world.save_path=path
	world.state.picnic=true
	for token in [GROWER,FRIEND]:
		world.add_player(token,"Farmer")
		world.state.players[token].x=HEN.x+0.5
		world.state.players[token].y=HEN.y+0.5
	var bag:Dictionary=world.state.players[GROWER].inventory
	bag.wood=16
	bag.fiber=12
	bag.feed=2
	bag[COLLECTOR_KEY]=1
	world.state.objects[World.key(BENCH)]={"type":"bench","owner":GROWER,"items":{}}
	return world.save()

func eggs(session:Session) -> int:
	return int(session.snapshot.get("players",{}).get(session.own_id,{}).get("inventory",{}).get("egg",0))

func stored(session:Session) -> int:
	return int(session.snapshot.get("animal",{}).get("basket_eggs",-1))

func machine_count(session:Session) -> int:
	var obj:Dictionary=session.snapshot.get("objects",{}).get(World.key(COLLECTOR_SITE),{})
	return int(obj.get("collector_count",-1))

func pen_basket(session:Session) -> Dictionary:
	return session.snapshot.get("objects",{}).get(World.key(PEN_SITE),{}).get("collector_items",{})

func inventory(session:Session) -> Dictionary:
	return session.snapshot.get("players",{}).get(session.own_id,{}).get("inventory",{})

func action(session:Session,name:String,cell:Vector2i,extra:String="") -> bool:
	var seen:int=notices[session].size()
	session.perform(name,cell,extra)
	if not await wait_for(func():return notices[session].size()>seen):return false
	return notices[session].back().ok

func run() -> void:
	if not check(seeded_world(),"Save a room with a bench and supplies"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var address:="ws://127.0.0.1:%d"%port
	var host:=make_session("Host","egg-network-host")
	if not check(host.host(port,"Host",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a dedicated WebSocket room"):return
	var grower:=make_session("Grower",GROWER)
	var friend:=make_session("Friend",FRIEND)
	if not check(grower.join(address,port,"Grower",ROOM)==OK and friend.join(address,port,"Friend",ROOM)==OK,"Connect two WebSocket clients"):return
	if not check(await wait_for(func():return not grower.own_id.is_empty() and not friend.own_id.is_empty()),"Both clients entered the island"):return
	if not check(await action(grower,"craft",BENCH,"egg_basket"),"Craft through the remote workbench"):return
	if not check(await action(grower,"install_egg_basket",HEN),"Install through the remote chicken panel action"):return
	if not check(await action(grower,"feed",HEN),"Feed the chicken once"):return
	if not check(stored(friend)==0 and float(host.world.state.animal.egg_ready)>float(host.world.state.time),"Disconnect before the egg is due"):return
	grower.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host saw the original grower disconnect"):return
	Engine.time_scale=10.0
	if not check(await wait_for(func():return stored(friend)==1,15.0),"Remaining player sees exactly one egg reach the basket"):return
	Engine.time_scale=1.0
	var returned:=make_session("Returned",GROWER)
	if not check(returned.join(address,port,"Grower",ROOM)==OK,"Reconnect the original profile"):return
	if not check(await wait_for(func():return stored(returned)==1),"Reconnected client sees the one pending egg"):return
	var returned_notices:int=notices[returned].size()
	var friend_notices:int=notices[friend].size()
	returned.perform("egg",HEN)
	friend.perform("egg",HEN)
	if not check(await wait_for(func():return notices[returned].size()>returned_notices and notices[friend].size()>friend_notices),"Both remote claims were answered"):return
	if not check(await wait_for(func():return stored(returned)==0 and stored(friend)==0 and eggs(returned)+eggs(friend)==1),"Both clients agree that only one egg was collected"):return
	if not check(notices[returned].back().ok!=notices[friend].back().ok,"Exactly one player won the claim"):return
	var saved:=World.new()
	if not check(saved.load_world(path) and int(saved.state.animal.basket_eggs)==0 and int(saved.state.players[GROWER].inventory.get("egg",0))+int(saved.state.players[FRIEND].inventory.get("egg",0))==1,"The room save contains precisely one awarded egg"):return
	if not check(await action(returned,"craft",BENCH,"egg_basket"),"Craft another basket for the new machine"):return
	if not check(await action(returned,"build",COLLECTOR_SITE,Industry.ANIMAL_COLLECTOR),"Place the collector remotely"):return
	if not check(await action(returned,"collector_bind",COLLECTOR_SITE,"chicken"),"Bind the chicken remotely"):return
	if not check(await wait_for(func():return machine_count(friend)==0),"Friend sees the installed empty basket"):return
	var feed_confirmations:={"owner":0,"guest":0}
	returned.action_completed.connect(func(_sequence:int,name:String,result:Dictionary):
		if name=="feed" and result.ok:feed_confirmations.owner+=1)
	friend.action_completed.connect(func(_sequence:int,name:String,result:Dictionary):
		if name=="feed" and result.ok:feed_confirmations.guest+=1)
	if not check(await action(returned,"feed",HEN),"Feed the chicken for the new collector"):return
	if not check(await wait_for(func():return feed_confirmations.owner==1),"Feeding sends the actor an authoritative cue confirmation"):return
	Engine.time_scale=10.0
	if not check(await wait_for(func():return machine_count(friend)==1 and machine_count(returned)==1,15.0),"Both clients see the new egg reach the machine"):return
	Engine.time_scale=1.0
	if not check(stored(friend)==0,"The legacy basket did not receive a duplicate egg"):return
	if not check(feed_confirmations.guest==0 and feed_confirmations.owner==1,"The direct feeding cue is not broadcast or repeated"):return
	if not check(not await action(friend,"collector_collect",COLLECTOR_SITE) and machine_count(friend)==1,"A guest cannot take the owner's egg"):return
	if not check(await action(returned,"collector_collect",COLLECTOR_SITE),"Owner takes the egg through the remote action"):return
	if not check(await wait_for(func():return machine_count(friend)==0 and machine_count(returned)==0 and eggs(returned)+eggs(friend)==2),"Both clients agree exactly two eggs were awarded in total"):return
	if not check(saved.load_world(path) and int(saved.state.objects[World.key(COLLECTOR_SITE)].collector_count)==0
		and int(saved.state.players[GROWER].inventory.get("egg",0))+int(saved.state.players[FRIEND].inventory.get("egg",0))==2,"The room save agrees with both clients"):return
	if not await verify_pen_basket(host,returned,friend,saved):return
	finish(0)

func verify_pen_basket(host:Session,owner:Session,guest:Session,saved:World) -> bool:
	var world:World=host.world
	var objects:Dictionary=world.state.objects
	var key:=World.key(PEN_SITE)
	for tile:Vector2i in [Vector2i(47,35),Vector2i(47,36),Vector2i(51,35),Vector2i(51,36),
			Vector2i(49,34),Vector2i(48,37),Vector2i(49,37),Vector2i(50,37)]:
		objects[World.key(tile)]={"type":"wall","owner":GROWER,"items":{}}
	for tile:Vector2i in [Vector2i(48,34),Vector2i(50,34)]:
		objects[World.key(tile)]={"type":"door","owner":GROWER,"items":{},"open":false}
	for token:String in [GROWER,FRIEND]:
		var actor:Dictionary=world.state.players[token]
		actor.x=49.5
		actor.y=36.5
	var bag:Dictionary=world.state.players[GROWER].inventory
	bag[COLLECTOR_KEY]=1
	bag.egg_basket=1
	if not check(await action(owner,"build",PEN_SITE,Industry.ANIMAL_COLLECTOR),"Owner places a second collector inside the shared pen"):return false
	if not check(await action(owner,"collector_bind",PEN_SITE,World.AnimalCollector.PEN),"Owner binds the whole pen remotely"):return false
	if not check(await wait_for(func():return guest.snapshot.get("objects",{}).get(key,{}).get("collector_animal","")==World.AnimalCollector.PEN),"Guest receives the pen binding"):return false
	world.state.livestock.cow={"feed":0,"ready":3,"ready_quality":1,"next":-1.0}
	world.state.livestock.sheep={"feed":0,"ready":4,"ready_quality":1,"next":-1.0}
	var full:Dictionary={"milk":2,"quality_milk":1,"wool":2,"quality_wool":1}
	if not check(await wait_for(func():return pen_basket(owner)==full and pen_basket(guest)==full),"Both clients receive the quantities of all four item IDs"):return false
	if not check(int(world.state.livestock.sheep.ready)==1,"The seventh product stays with the sheep"):return false
	if not check(not await action(guest,"collector_collect",PEN_SITE) and pen_basket(guest)==full,"A guest cannot take any of the mixed basket products"):return false
	if not check(await action(owner,"collector_collect",PEN_SITE),"Owner collects all four IDs in one action"):return false
	if not check(await wait_for(func():return pen_basket(owner)=={"wool":1} and pen_basket(guest)=={"wool":1}),"Both clients see only the seventh product after collection resumes"):return false
	if not check(await action(owner,"collector_collect",PEN_SITE),"Owner collects the seventh product"):return false
	if not check(await wait_for(func():return pen_basket(owner).is_empty() and pen_basket(guest).is_empty() and int(inventory(owner).get("wool",0))==3),"Both clients see the empty basket and the owner sees all the wool"):return false
	if not check(not await action(owner,"collector_collect",PEN_SITE),"A repeated collection cannot duplicate any product"):return false
	if not check(saved.load_world(path) and saved.state.objects[key].collector_items.is_empty(),"The save also preserves the empty pen basket"):return false
	var saved_bag:Dictionary=saved.state.players[GROWER].inventory
	return check(int(saved_bag.milk)==2 and int(saved_bag.quality_milk)==1 and int(saved_bag.wool)==3 and int(saved_bag.quality_wool)==1,"The save includes exactly the seven products the owner received")
