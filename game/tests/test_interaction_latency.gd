extends "res://tests/test_manual_harvest_capacity_session.gd"
## T087 sampling of server-confirmed shared chest and crop operations.
## Positions, permitted season, building wood and maturity are test fixtures.
## Four real local WebSocket peers receive snapshots in one Godot process.

const SAMPLES_PER_ACTION:=50
const OBSERVER_TOKENS:=["interaction-latency-observer-one","interaction-latency-observer-two"]
var observers:Array[Client]=[]
var timings:Dictionary={}
var soak_seconds:=0.0

func _initialize()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--soak-seconds="):soak_seconds=maxf(0.0,float(argument.get_slice("=",1)))
	create_timer(150.0+soak_seconds,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func run()->void:
	var completed:=await scenario()
	expect(completed,"latency scenario completed")
	for observer in observers:
		await leave(observer)
	await teardown()
	if failures==0:expect(remove_folder(),"temp fixture removed")
	for action in timings:
		var samples:Array=timings[action]
		samples.sort()
		print("INTERACTION_TIMING action=%s count=%d p50_ms=%d p95_ms=%d max_ms=%d samples=%s"%[
			action,samples.size(),percentile(samples,0.5),percentile(samples,0.95),int(samples.back()),JSON.stringify(samples)])
	finished=true
	print("INTERACTION_LATENCY checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

static func percentile(samples:Array,fraction:float)->int:
	return int(samples[ceili(samples.size()*fraction)-1])

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("interaction-latency-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp world directory created"):return false
	save_path=folder.path_join("world.json")
	if not expect(find_layout(),"shared interaction cell found"):return false
	var w:=fresh_probe()
	w.state.time=T_SUMMER1
	w.state.players[ALPHA].x=a_spot.x
	w.state.players[ALPHA].y=a_spot.y
	w.state.players[BETA].x=b_spot.x
	w.state.players[BETA].y=b_spot.y
	w.state.players[ALPHA].inventory.wood+=20
	for token in OBSERVER_TOKENS:
		w.add_player(token,"observer")
		w.state.players[token].x=b_spot.x
		w.state.players[token].y=b_spot.y
	w.save_path=save_path
	if not expect(w.save() and disk_valid(read_disk()),"test fixture saved and validated"):return false
	var port:=start_server()
	if not expect(port>0,"WebSocket server listening"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	for index in OBSERVER_TOKENS.size():
		observers.append(await join("observer%d"%index,OBSERVER_TOKENS[index],port))
	if not expect(joined(alpha) and joined(beta) and observers.all(joined),"four WebSocket clients joined"):return false
	if not await measure(alpha,"build","chest",false):return false
	if not await measure(alpha,"deposit","wood",false):return false
	for index in SAMPLES_PER_ACTION:
		var client:=alpha if index%2==0 else beta
		if not await measure(client,"withdraw","wood",true):return false
		# Return the very same item through the production action.
		if not await measure(client,"deposit","wood",false):return false
	if not await measure(alpha,"withdraw","wood",false):return false
	if not await measure(alpha,"remove","",false):return false
	if not await measure(alpha,"hoe","",false):return false
	if not await measure(alpha,"seed","wheat",false):return false
	var ripe:=srv_crop(k1)
	ripe.merge({"growth":float(World.CROPS.wheat.time),"harvest_access":"island"},true)
	for index in SAMPLES_PER_ACTION:
		server.world.state.crops[k1]=ripe.duplicate(true)
		var client:=alpha if index%2==0 else beta
		if not await measure(client,"harvest","",true):return false
	expect(srv_wheat(ALPHA)==50 and srv_wheat(BETA)==50,"the fifty measured harvests each pay two wheat")
	expect(srv_crop(k1).kind=="","last plot consumed exactly once")
	expect(await wait_until(func():
		return wheat(alpha)==50 and wheat(beta)==50 and observers.all(func(c):return c.crop(k1).get("kind","missing")=="")
	,5.0),"balances and last harvested plot visible to clients")
	if soak_seconds>0.0:return await soak(port,ripe)
	return true

func soak(port:int,ripe:Dictionary)->bool:
	var nearby:=soak_build_sites()
	if not expect(nearby.size()>=2,"two buildable sites in reach of both islander positions"):return false
	var chest:Vector2i=nearby[0]
	var floor_tile:Vector2i=nearby[1]
	var chest_key:=World.key(chest)
	var floor_key:=World.key(floor_tile)
	for build in [[chest,"chest"],[floor_tile,"floor"]]:
		# Seed the phase's construction stock once. Transfers and construction use normal RPCs.
		for item in World.BUILD[build[1]]:
			if item!="name":World.give(srv_player(ALPHA).inventory,item,int(World.BUILD[build[1]][item]))
		if not await measure(alpha,"build",build[1],false,build[0]):return false
	if not await measure(alpha,"deposit","wood",false,chest):return false
	var people:Array[Client]=[alpha,beta]
	people.append_array(observers)
	var expected_wheat:Array[int]=[]
	var expected_wood:Array[int]=[]
	for client in people:
		expected_wheat.append(int(srv_player(client.token).inventory.get("wheat",0)))
		expected_wood.append(int(srv_player(client.token).inventory.get("wood",0)))
	var started:=Time.get_ticks_msec()
	var cycles:=0
	var next_report:=0
	var starting_changes:=people.map(func(client):return client.changes)
	while float(Time.get_ticks_msec()-started)<soak_seconds*1000.0:
		var index:=cycles%people.size()
		var actor:=people[index]
		if not await measure(actor,"withdraw","wood",false,chest):return false
		if not await measure(actor,"deposit","wood",false,chest):return false
		server.world.state.crops[k1]=ripe.duplicate(true)
		if not await measure(actor,"harvest","",false):return false
		expected_wheat[index]+=2
		if not await measure(alpha,"remove","",false,floor_tile):return false
		if not await measure(alpha,"build","floor",false,floor_tile):return false
		if not expect(int(server.world.state.objects[chest_key].items.wood)==1 and server.world.state.ground[floor_key].type=="floor","shared chest and floor consistent after cycle %d"%cycles):return false
		for player_index in people.size():
			var inv:Dictionary=srv_player(people[player_index].token).inventory
			if not expect(int(inv.get("wood",0))==expected_wood[player_index] and int(inv.get("wheat",0))==expected_wheat[player_index],"exact wood and wheat for player %d after cycle %d"%[player_index,cycles]):return false
		cycles+=1
		var elapsed:=int((Time.get_ticks_msec()-started)/1000.0)
		if elapsed>=next_report:
			print("INTERACTION_SOAK_PROGRESS elapsed=%d cycles=%d clients=%d"%[elapsed,cycles,people.size()])
			next_report=elapsed+60
		await pause(4.0)
	if not expect(await wait_until(func():
		for index in people.size():
			var client:=people[index]
			if client.session.own_id.is_empty() or client.changes<=starting_changes[index]:return false
			if not soak_snapshot(client,chest_key,floor_key,expected_wheat[index],expected_wood[index]):return false
		return true
	,8.0),"four clients see the same final boxes and buildings with correct bags"):return false
	var elapsed_ms:=Time.get_ticks_msec()-started
	await leave(observers.back())
	observers[-1]=await join("returned",OBSERVER_TOKENS.back(),port)
	if not expect(joined(observers.back()) and await wait_until(func():
		return soak_snapshot(observers.back(),chest_key,floor_key,expected_wheat.back(),expected_wood.back())
	,8.0),"fourth client rejoins with the same inventory and structures"):return false
	var disk:Variant=read_disk()
	if not expect(disk_valid(disk) and disk.objects[chest_key].items.wood==1 and disk.ground[floor_key].type=="floor","saved chest and floor validate"):return false
	for index in people.size():
		var inv:Dictionary=disk.players[people[index].token].inventory
		expect(int(inv.get("wood",0))==expected_wood[index] and int(inv.get("wheat",0))==expected_wheat[index],"saved totals match player %d"%index)
	print("INTERACTION_SOAK_COMPLETE elapsed_ms=%d cycles=%d clients=4"%[elapsed_ms,cycles])
	return true

func soak_snapshot(client:Client,chest_key:String,floor_key:String,wheat_held:int,wood_held:int)->bool:
	var snapshot:Dictionary=client.session.snapshot
	return (int(client.bag().get("wheat",0))==wheat_held and int(client.bag().get("wood",0))==wood_held
		and int(snapshot.get("objects",{}).get(chest_key,{}).get("items",{}).get("wood",0))==1
		and snapshot.get("ground",{}).get(floor_key,{}).get("type","")=="floor")

func soak_build_sites()->Array[Vector2i]:
	var w:World=server.world
	var candidates:Array[Vector2i]=[]
	for y in range(plot.y-2,plot.y+2):
		for x in range(plot.x-2,plot.x+2):
			var tile:=Vector2i(x,y)
			var at:=centre(tile)
			var key:=World.key(tile)
			var distance_a:=at.distance_to(a_spot)
			var distance_b:=at.distance_to(b_spot)
			if minf(distance_a,distance_b)<0.8 or maxf(distance_a,distance_b)>3.0:continue
			if not w.is_land(tile) or w.water(tile) or w.protected(tile) or w.resource(tile)!="":continue
			if w.state.crops.has(key) or w.state.objects.has(key) or w.state.ground.has(key):continue
			candidates.append(tile)
	return candidates

func measure(client:Client,action:String,extra:String,record:bool,target:=Vector2i(-1,-1))->bool:
	var mark:=client.notices.size()
	var started:=Time.get_ticks_usec()
	client.session.perform(action,plot if target.x<0 else target,extra)
	if not expect(await wait_until(func():return client.notices.size()>mark,5.0),action+" receives a server notice"):return false
	var elapsed:=roundi(float(Time.get_ticks_usec()-started)/1000.0)
	if not expect(bool(client.notices[mark][1]),action+" accepted: "+str(client.notices[mark][0])):return false
	if record:
		if not timings.has(action):timings[action]=[]
		timings[action].append(elapsed)
	return true
