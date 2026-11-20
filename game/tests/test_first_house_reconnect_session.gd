extends "res://tests/network_egg_basket.gd"
## First house over real WebSockets, then a host restart on the same save.
## Two real Session clients join a fresh dedicated host. The owner builds the guided
## first house (WorkshopLayouts.HOUSE_FLOOR/HOUSE_DOOR/HOUSE_BED: 4 floor, 11 wall, 1 door,
## 4 automatic roofs, 1 bed) with real `build` actions, opens the door, WALKS in through real
## movement RPCs, closes the door and places the bed. The host is then shut down, a new host
## loads the same save, both profiles rejoin and everything must be unchanged.
##
## Fixture (authored, not played; documented on purpose):
##  - a 5x5 patch of cleared land at ORIGIN (state.removed) and nothing else on the map;
##  - owner and guest start on legal, clear tiles outside the house. The owner walks
##    between build sites and into the room using real network movement;
##  - owner inventory is exactly WorkshopLayouts.cost(FIRST_HOUSE); no house piece is seeded;
##  - no chapter flag, no friendship/story state: floor, wall, door, roof and bed need none.

const Rooms=preload("res://scripts/house_rooms.gd")
const Layouts=preload("res://scripts/workshop_layouts.gd")
const OWNER:="first-house-owner"
const GUEST:="first-house-guest"
const ORIGIN:=Vector2i(24,34)
const PACE_MSEC:=100 # the host allows 12 actions/second per player; stay well below
const DIRECTIONS:=[Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]
const BUILD_WALK_DISTANCE:=2.75
var owner_public:=OWNER.sha256_text().left(16)
var guest_public:=GUEST.sha256_text().left(16)

func finish(code:int) -> void:
	Engine.time_scale=1.0
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("FIRST_HOUSE_RECONNECT_SESSION_TESTS checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func tile(local:Vector2i) -> Vector2i:
	return ORIGIN+local

func center(cell:Vector2i) -> Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

func kind_at(local:Vector2i) -> String:
	if local==Layouts.HOUSE_DOOR:return "door"
	if local in Layouts.HOUSE_FLOOR:return "floor"
	return "wall"

## The ordered real build plan: floors, walls, door (completes the enclosure, so the four
## automatic roofs are charged here to the builder), then the bed.
func plan() -> Array:
	var steps:Array=[]
	for cell:Vector2i in Layouts.HOUSE_FLOOR:steps.append({"cell":cell,"kind":"floor"})
	for y in 4:
		for x in 4:
			var cell:=Vector2i(x,y)
			if kind_at(cell)=="wall":steps.append({"cell":cell,"kind":"wall"})
	steps.append({"cell":Layouts.HOUSE_DOOR,"kind":"door"})
	steps.append({"cell":Layouts.HOUSE_BED,"kind":"bed"})
	return steps

func step_cost(step:Dictionary) -> Dictionary:
	var cost:Dictionary={}
	var recipes:Array=[World.BUILD[step.kind]]
	if step.kind=="door":
		for _roof in Layouts.HOUSE_FLOOR.size():recipes.append(World.BUILD.roof)
	for recipe:Dictionary in recipes:
		for item:String in recipe:
			if item!="name":cost[item]=int(cost.get(item,0))+int(recipe[item])
	return cost

func seed_world() -> bool:
	var world:=World.new()
	world.save_path=path
	for y in 5:
		for x in 5:world.state.removed[World.key(tile(Vector2i(x,y)))]=true
	for token:String in [OWNER,GUEST]:world.add_player(token,token)
	var owner_start:=tile(Layouts.HOUSE_DOOR+Vector2i.DOWN)
	var guest_start:=tile(Vector2i(4,4))
	world.state.players[OWNER].x=center(owner_start).x
	world.state.players[OWNER].y=center(owner_start).y
	world.state.players[GUEST].x=center(guest_start).x
	world.state.players[GUEST].y=center(guest_start).y
	# Exactly what the guided house costs (floors, walls, door, bed and four auto roofs), nothing more.
	world.state.players[OWNER].inventory=Layouts.cost(Layouts.FIRST_HOUSE).duplicate()
	if world.state.players[OWNER].inventory.is_empty():return false
	for start:Vector2i in [owner_start,guest_start]:
		if not world.can_stand(center(start)) or world.protected(start):return false
	for y in 5:
		for x in 5:
			if world.protected(tile(Vector2i(x,y))) or world.resource(tile(Vector2i(x,y)))!="":return false
	for layer:String in ["objects","ground","roofs"]:
		if not world.state[layer].is_empty():return false
	return world.save()

func house_pieces(state:Dictionary) -> Dictionary:
	var found:Dictionary={}
	for layer:String in ["objects","ground","roofs"]:
		for y in 5:
			for x in 5:
				var cell_key:=World.key(tile(Vector2i(x,y)))
				var piece:Dictionary=state[layer].get(cell_key,{})
				if piece.is_empty():continue
				found["%s|%s"%[layer,cell_key]]="%s|%s|%s|%s"%[piece.get("type"),str(piece.get("owner")),str(piece.get("open","-")),str(piece.get("auto","-"))]
	return found

func expected_pieces(owner_id:String,door_open:bool) -> Dictionary:
	var expected:Dictionary={}
	for step:Dictionary in plan():
		var cell_key:=World.key(tile(step.cell))
		match step.kind:
			"floor":
				expected["ground|"+cell_key]="floor|%s|-|-"%owner_id
				expected["roofs|"+cell_key]="roof|%s|-|true"%owner_id
			"wall":expected["objects|"+cell_key]="wall|%s|-|-"%owner_id
			"door":expected["objects|"+cell_key]="door|%s|%s|-"%[owner_id,str(door_open)]
			"bed":expected["objects|"+cell_key]="bed|%s|-|-"%owner_id
	return expected

func same_inventory(actual:Dictionary,expected:Dictionary) -> bool:
	var names:Dictionary={}
	for item in actual:names[item]=true
	for item in expected:names[item]=true
	for item in names:
		if int(actual.get(item,0))!=int(expected.get(item,0)):return false
	return true

func server_inventory(host:Session,token:String) -> Dictionary:
	return host.world.state.players[token].inventory

func client_inventory(client:Session) -> Dictionary:
	return client.snapshot.get("players",{}).get(client.own_id,{}).get("inventory",{})

func client_pieces(client:Session) -> Dictionary:
	return house_pieces(client.snapshot)

func position_of(host:Session,token:String) -> Vector2:
	var person:Dictionary=host.world.state.players[token]
	return Vector2(float(person.x),float(person.y))

func pause(msec:int=PACE_MSEC) -> void:
	var until:=Time.get_ticks_msec()+msec
	while Time.get_ticks_msec()<until:await process_frame

func act(client:Session,name:String,cell:Vector2i,extra:String="") -> bool:
	await pause()
	return await action(client,name,cell,extra)

func last_notice(client:Session) -> String:
	return str(notices[client].back().message) if not notices[client].is_empty() else "no notice"

## Path planning reads the world's walkability. Every step still sends movement
## through the client and waits for the dedicated host to move the player.
func walk_to(host:Session,client:Session,destination:Callable) -> bool:
	var start:=Vector2i(position_of(host,OWNER).floor())
	var bounds:=Rect2i(ORIGIN-Vector2i.ONE,Vector2i(7,7))
	var queue:Array[Vector2i]=[start]
	var previous:Dictionary={start:start}
	while not queue.is_empty():
		var current:Vector2i=queue.pop_front()
		if destination.call(current):
			var cells:Array[Vector2i]=[]
			while current!=start:
				cells.push_front(current)
				current=previous[current]
			for cell:Vector2i in cells:
				if not await walk_step(host,client,center(cell)):return false
			return true
		for direction:Vector2i in DIRECTIONS:
			var next:=current+direction
			if not previous.has(next) and bounds.has_point(next) and host.world.can_stand(center(next)):
				previous[next]=current
				queue.append(next)
	return false

func walk_step(host:Session,client:Session,target:Vector2) -> bool:
	var deadline:=Time.get_ticks_msec()+3000
	while Time.get_ticks_msec()<deadline:
		var delta:=target-position_of(host,OWNER)
		if delta.length()<0.10:break
		client.input_direction(delta.normalized())
		await pause(24)
	client.input_direction(Vector2.ZERO)
	await pause(100)
	return position_of(host,OWNER).distance_to(target)<0.20

func run() -> void:
	path="user://first-house-reconnect-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	if not check(seed_world(),"Save a fresh world with cleared land, two outside players and only the house materials"):return
	var door:=tile(Layouts.HOUSE_DOOR)
	var interior:=tile(Layouts.HOUSE_FLOOR[2]) # (1,2): the floor tile just inside the door
	var budget:Dictionary=Layouts.cost(Layouts.FIRST_HOUSE).duplicate()
	var all_steps:Array=plan()
	if not check(all_steps.size()==Layouts.HOUSE_FLOOR.size()+11+1+1 and not budget.is_empty(),"Plan is 4 floor, 11 wall, 1 door and 1 bed with a known cost"):return
	var summed:Dictionary={}
	for step:Dictionary in all_steps:
		var cost:=step_cost(step)
		for item:String in cost:summed[item]=int(summed.get(item,0))+int(cost[item])
	if not check(same_inventory(summed,budget),"Per-piece real recipes add up to the guided house cost"):return

	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var address:="ws://127.0.0.1:%d"%port
	var host:=make_session("HouseHost","first-house-host")
	if not check(host.host(port,"小屋",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a WebSocket host"):return
	var owner:=make_session("HouseOwner",OWNER)
	var guest:=make_session("HouseGuest",GUEST)
	if not check(owner.join(address,port,"屋主",ROOM)==OK and guest.join(address,port,"客人",ROOM)==OK,"Connect both clients"):return
	if not check(await wait_for(func():return owner.snapshot.has("players") and guest.snapshot.has("players") and owner.own_id==owner_public and guest.own_id==guest_public),"Both clients entered with their hashed stable ids"):return
	if not check(house_pieces(host.world.state).is_empty() and house_pieces(owner.snapshot).is_empty(),"No house piece exists before the first build"):return
	var guest_bag:Dictionary=server_inventory(host,GUEST).duplicate(true)
	var guest_spot:=position_of(host,GUEST)
	var owner_start:=position_of(host,OWNER)
	if not check(Vector2i(owner_start.floor())==tile(Layouts.HOUSE_DOOR+Vector2i.DOWN),"Owner starts on the tile outside the door gap"):return
	if not check(same_inventory(server_inventory(host,OWNER),budget) and await wait_for(func():return same_inventory(client_inventory(owner),budget)),"Owner holds exactly the house materials on server and client"):return

	# 1. Build every piece through the normal networked action; each is charged exactly once.
	var expected:=budget.duplicate()
	var built:=0
	for step:Dictionary in all_steps:
		var cell:Vector2i=tile(step.cell)
		var kind:String=step.kind
		if kind=="door":
			if not check(await walk_to(host,owner,func(at:Vector2i):return at==door+Vector2i.DOWN),"Walk outside through the gap before building the door"):return
		elif kind=="bed":
			if not check(await act(owner,"door",door),"Owner opens the door; latest notice: "+last_notice(owner)):return
			if not check(host.world.state.objects[World.key(door)].open==true,"Host shows the door open"):return
			if not check(await walk_to(host,owner,func(at:Vector2i):return at==interior),"Owner walks in through the open door over real WebSocket movement"):return
			var inside:=position_of(host,OWNER)
			if not check(Vector2i(inside.floor())==interior,"Owner stopped inside the house on the floor tile beside the bed spot, got %s"%str(inside)):return
			if not check(await act(owner,"door",door),"Owner closes the door from inside; latest notice: "+last_notice(owner)):return
			if not check(host.world.state.objects[World.key(door)].open==false,"Host shows the door closed with the builder inside"):return
		elif not check(await walk_to(host,owner,func(at:Vector2i):return at!=cell and center(at).distance_to(center(cell))<=BUILD_WALK_DISTANCE),"Walk within reach of %s at %s"%[kind,cell]):return
		if not check(not host.world.state.objects.has(World.key(cell)) or kind=="floor","The %s tile starts free"%kind):return
		if not check(await act(owner,"build",cell,kind),"Build %s at %s; latest notice: %s"%[kind,str(cell),last_notice(owner)]):return
		built+=1
		var cost:=step_cost(step)
		for item:String in cost:expected[item]=int(expected.get(item,0))-int(cost[item])
		if not check(same_inventory(server_inventory(host,OWNER),expected),"Server charged %s exactly once (step %d)"%[kind,built]):return
		if not check(await wait_for(func():return same_inventory(client_inventory(owner),expected)),"Owner's client shows the single charge for %s (step %d)"%[kind,built]):return
		if not check(same_inventory(server_inventory(host,GUEST),guest_bag),"Guest's server inventory untouched after %s"%kind):return
		if kind=="door":
			if not check(host.world.state.roofs.size()==Layouts.HOUSE_FLOOR.size(),"The door completes the room and adds exactly four automatic roofs"):return
		else:
			if not check(host.world.state.roofs.size()==(Layouts.HOUSE_FLOOR.size() if built>all_steps.size()-2 else 0),"Roof count only changes with the door"):return
	if not check(expected.values().all(func(count):return int(count)==0),"Every seeded material was spent, none created or lost"):return

	# 2. Server and both clients agree on the structure, with hashed ownership only.
	if not check(house_pieces(host.world.state)==expected_pieces(OWNER,false),"Host holds the exact 4 floor, 11 wall, closed door, 4 roof and bed layout"):return
	var expected_public:=expected_pieces(owner_public,false)
	if not check(await wait_for(func():return client_pieces(owner)==expected_public and client_pieces(guest)==expected_public),"Both clients see the same structure owned by the hashed public id"):return
	for client:Session in [owner,guest]:
		for layer:String in ["objects","ground","roofs"]:
			if not check(not var_to_str(client.snapshot[layer]).contains(OWNER),"%s snapshot layer never carries the raw owner token"%layer):return
	if not check(await wait_for(func():return same_inventory(client_inventory(guest),guest_bag)),"Guest's client inventory is unchanged"):return
	if not check(position_of(host,GUEST).is_equal_approx(guest_spot),"Guest never moved"):return
	var guest_view:Dictionary=guest.snapshot.players[owner_public]
	if not check(not guest_view.has("inventory"),"Guest cannot see the builder's inventory"):return

	# 3. Builder is inside with the door closed; capture what must survive, and prove it is saved.
	var inside_at:=position_of(host,OWNER)
	if not check(Vector2i(inside_at.floor())==interior,"Builder is still inside before shutdown"):return
	var final_bag:Dictionary=server_inventory(host,OWNER).duplicate(true)
	var final_guest_bag:Dictionary=server_inventory(host,GUEST).duplicate(true)
	owner.disconnected_world.connect(func():owner.set_meta("server_stopped",true))
	guest.disconnected_world.connect(func():guest.set_meta("server_stopped",true))
	if not check(host.shutdown() and host.shutting_down,"Original host shuts down and saves with the builder inside"):return
	if not check(await wait_for(func():return owner.get_meta("server_stopped",false) and guest.get_meta("server_stopped",false)),"Both clients receive the server disconnect signal"):return
	owner.shutdown()
	guest.shutdown()
	var saved:=World.new()
	if not check(saved.load_world(path) and not saved.recovered_from_backup,"The primary save loads after shutdown"):return
	if not check(house_pieces(saved.state)==expected_pieces(OWNER,false) and saved.state.objects[World.key(door)].open==false,"Save holds the complete house with a closed door"):return
	var saved_at:=Vector2(float(saved.state.players[OWNER].x),float(saved.state.players[OWNER].y))
	if not check(saved_at.is_equal_approx(inside_at) and same_inventory(saved.state.players[OWNER].inventory,final_bag) and same_inventory(saved.state.players[GUEST].inventory,final_guest_bag),"Save holds the builder's position and both inventories"):return

	# 4. Start a new host on the same port and save, then rejoin.
	var host2:=make_session("HouseHost2","first-house-host")
	if not check(host2.host(port,"小屋",path,ROOM,"127.0.0.1",true,"websocket")==OK,"A new host reuses the port and loads the same save"):return
	if not check(house_pieces(host2.world.state)==expected_pieces(OWNER,false),"New host holds the identical house before anyone rejoins"):return
	var owner2:=make_session("HouseOwner2",OWNER)
	var guest2:=make_session("HouseGuest2",GUEST)
	if not check(owner2.join(address,port,"屋主",ROOM)==OK and guest2.join(address,port,"客人",ROOM)==OK,"Reconnect both stable profile tokens"):return
	if not check(await wait_for(func():return owner2.snapshot.has("players") and guest2.snapshot.has("players") and owner2.own_id==owner_public and guest2.own_id==guest_public),"Both rejoin with the same hashed ids"):return
	if not check(host2.world.state.players.size()==2,"Rejoin reused the two profiles, no extra player was created"):return

	# 5. Everything identical, verified BEFORE any post-rejoin build.
	var door_piece:Dictionary=host2.world.state.objects[World.key(door)]
	if not check(door_piece.open==false and house_pieces(host2.world.state)==expected_pieces(OWNER,false),"Saved closed door and complete house on the new host"):return
	if not check(same_inventory(server_inventory(host2,OWNER),final_bag) and same_inventory(server_inventory(host2,GUEST),final_guest_bag),"Server inventories are identical after rejoin"):return
	if not check(await wait_for(func():return same_inventory(client_inventory(owner2),final_bag) and same_inventory(client_inventory(guest2),final_guest_bag)),"Each client sees its own identical inventory"):return
	var back_at:=position_of(host2,OWNER)
	if not check(back_at.is_equal_approx(inside_at) and Vector2i(back_at.floor())==interior,"Builder rejoins exactly where they stood, inside the house"):return
	if not check(position_of(host2,GUEST).is_equal_approx(guest_spot),"Guest rejoins exactly where they stood"):return
	if not check(await wait_for(func():return client_pieces(owner2)==expected_public and client_pieces(guest2)==expected_public),"Both clients see the identical hashed-owner house after rejoin"):return
	if not check(guest2.snapshot.objects[World.key(door)].open==false,"The guest's client sees the door closed"):return
	var own_back:Dictionary=owner2.snapshot.players[owner_public]
	if not check(absf(float(own_back.x)-inside_at.x)<0.05 and absf(float(own_back.y)-inside_at.y)<0.05,"The builder's client sees them at the saved spot"):return
	var room:=Rooms.inspect(host2.world.state,interior)
	if not check(room.complete,"The original room is still a complete enclosure after the restart"):return
	if not check(host2.world.state.roofs.size()==Layouts.HOUSE_FLOOR.size() and host2.world.state.objects[World.key(tile(Layouts.HOUSE_BED))].type=="bed","All four roofs and the bed survived"):return
	if not check(await act(owner2,"door",door),"Returned owner can open the restored door from indoors"):return
	if not check(await walk_to(host2,owner2,func(at:Vector2i):return at==door+Vector2i.DOWN),"Returned owner can walk outside through the restored door"):return
	var open_public:=expected_pieces(owner_public,true)
	if not check(await wait_for(func():return client_pieces(owner2)==open_public and client_pieces(guest2)==open_public),"Both clients see the reopened door and unchanged structure"):return
	if not check(same_inventory(server_inventory(host2,OWNER),final_bag) and same_inventory(server_inventory(host2,GUEST),final_guest_bag),"Reopening the saved door charges no materials"):return
	finish(0)
