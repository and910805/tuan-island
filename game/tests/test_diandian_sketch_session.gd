extends "res://tests/network_egg_basket.gd"
## Diandian's sketch quest over real loopback WebSocket: two independent players observe the same crop and
## animals, records stay private, the report/easel unlock is gated per player, and everything persists.
const Goals=World.RESIDENT_GOALS
const Bond=World.RESIDENT_BOND
const COW:Vector2i=World.LIVESTOCK.ANIMALS.cow.cell
const SHEEP:Vector2i=World.LIVESTOCK.ANIMALS.sheep.cell
const CROP:=Vector2i(COW.x-2,COW.y)
const EASEL_SPOTS:=[Vector2i(1,2),Vector2i(2,2),Vector2i(-1,2),Vector2i(-2,2),Vector2i(1,-2),Vector2i(2,-2)]
func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("DIANDIAN_SKETCH_SESSION checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)
## SEEDED: teleport a player on the authoritative host (position/region are not what is under test).
func stand(host:Session,token:String,cell:Vector2i,region:String=World.REGIONS.HOME)->void:
	var person:Dictionary=host.world.state.players[token]
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	person.region=region
## Both players act in the same frame; each reply is awaited independently.
func pair(a:Session,a_cell:Vector2i,a_extra:String,b:Session,b_cell:Vector2i,b_extra:String)->Array:
	var seen_a:int=notices[a].size()
	var seen_b:int=notices[b].size()
	a.perform(Goals.SKETCH_ACTION,a_cell,a_extra)
	b.perform(Goals.SKETCH_ACTION,b_cell,b_extra)
	if not await wait_for(func():return notices[a].size()>seen_a and notices[b].size()>seen_b):return [false,false,false]
	return [true,notices[a].back().ok,notices[b].back().ok]
func mine(session:Session)->Dictionary:
	return session.snapshot.get("own_crop_sketches",{})
func goal_state(session:Session)->String:
	return str(session.snapshot.get("resident_goals",{}).get("diandian",{}).get("1",{}).get("state",""))
func visit(host:Session,session:Session,token:String,cell:Vector2i,region:String)->bool:
	stand(host,token,cell,region)
	for peer in host.peers:
		if host.peers[peer]==token:host._send_snapshot(peer)
	return await wait_for(func():return session.snapshot.get("region_id")==region)

func report(host:Session,session:Session,token:String)->bool:
	if not await visit(host,session,token,Bond.GARDEN_CELL,Bond.GARDEN_REGION):return false
	var cell:Vector2i=World.bond_place(session.snapshot,"diandian")[1]
	var accepted:bool=await action(session,Goals.ACTION,cell,"diandian:1::")
	if not await visit(host,session,token,COW,World.REGIONS.HOME):return false
	return accepted
func build_easel(host:Session,session:Session,token:String,skip:Array=[])->Vector2i:
	for offset:Vector2i in EASEL_SPOTS:
		var spot:Vector2i=COW+offset
		if skip.has(spot):continue
		stand(host,token,COW)
		if await action(session,"build",spot,"sketch_easel"):return spot
	return Vector2i(-1,-1)
func run()->void:
	path=OS.get_environment("TEMP").path_join("diandian-sketch-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	fixture.state.community={"table":World.COMMUNITY.choose_table(fixture.state)}
	# SEEDED: absent unadopted cow (record removed), one shared radish, first bond, coins and easel materials.
	fixture.state.livestock.erase("cow")
	fixture.state.crops[World.key(CROP)]={"kind":"radish","owner":GROWER,"wet":false,"growth":0,"remaining":1}
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"速寫者")
		fixture.state.players[token].x=COW.x+0.5
		fixture.state.players[token].y=COW.y+0.5
		fixture.state.players[token].coins=100
		fixture.state.players[token].inventory.wood=12
		fixture.state.players[token].inventory.fiber=4
		fixture.state.players[token].bonds={"diandian":{"points":1,"talk_day":-1,"gift_day":-1}}
	if not check(fixture.save(),"Save the fixture"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("SketchHost","sketch-host")
	if not check(host.host(port,"屋簷",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start real WS dedicated host"):return
	host.set_physics_process(false)
	var owner:=make_session("SketchOne",GROWER)
	var friend:=make_session("SketchTwo",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(owner.join(address,port,"畫家一號",ROOM)==OK and friend.join(address,port,"畫家二號",ROOM)==OK,"Join two clients"):return
	if not check(await wait_for(func():return not owner.own_id.is_empty() and not friend.own_id.is_empty()),"Both enter"):return
	var state:Dictionary=host.world.state
	var crops_before:Dictionary=state.crops.duplicate(true)
	if not check(mine(owner).is_empty() and mine(friend).is_empty() and not state.livestock.has("cow"),"Start empty with the cow absent"):return

	# Wrong tile, wrong distance, absent cow: all refused with no record.
	var replies:Array=await pair(owner,CROP+Vector2i.RIGHT,"",friend,CROP,"cow")
	if not check(replies[0] and not replies[1] and not replies[2],"Empty tile and absent unadopted cow are refused"):return
	stand(host,GROWER,Vector2i(CROP.x+10,CROP.y))
	if not check(not await action(owner,Goals.SKETCH_ACTION,CROP),"Out-of-reach crop sketch refused"):return
	stand(host,GROWER,COW)
	if not check(not await action(owner,Goals.SKETCH_ACTION,COW+Vector2i.RIGHT,"cow"),"Wrong animal tile refused"):return
	if not check(not await action(owner,Goals.SKETCH_ACTION,COW,"cow") and mine(owner).is_empty() and mine(friend).is_empty(),"Absent cow cannot be observed"):return

	# Same crop, observed independently and simultaneously; crop untouched.
	replies=await pair(owner,CROP,"",friend,CROP,"")
	if not check(replies[0] and replies[1] and replies[2],"Both sketch the same crop in one frame"):return
	if not check(await wait_for(func():return mine(owner).has("radish") and mine(friend).has("radish")),"Each receives own radish record"):return
	if not check(state.crops==crops_before,"Observing leaves the crop untouched (no harvest/mutation)"):return
	if not check(not await action(owner,Goals.SKETCH_ACTION,CROP),"Repeat crop sketch refused"):return

	# Real adoption makes the cow observable; the fee is paid once, the guest then sketches it too.
	if not check(await action(owner,"livestock_adopt",COW,"cow") and state.livestock.has("cow") and int(state.players[GROWER].coins)==40,"Owner really adopts the cow"):return
	replies=await pair(owner,COW,"cow",friend,COW,"cow")
	if not check(replies[0] and replies[1] and replies[2] and int(state.players[FRIEND].coins)==100,"Both sketch the adopted cow; guest pays nothing"):return

	# Private snapshots: nobody sees another's sketches.
	if not check(await wait_for(func():return mine(owner).has("cow") and mine(friend).has("cow")),"Cow records arrive"):return
	for host_peer in host.peers:host._send_snapshot(host_peer)
	await process_frame
	await process_frame
	if not check(not friend.snapshot.players.get(owner.own_id,{}).has(Goals.SKETCH_KEY) and not owner.snapshot.players.get(friend.own_id,{}).has(Goals.SKETCH_KEY),"Sketch records are absent from the other player's view"):return

	# Owner finishes with a distinct third subject and cap 3; guest stays at two.
	stand(host,GROWER,World.CHICKEN_CELL)
	if not check(await action(owner,Goals.SKETCH_ACTION,World.CHICKEN_CELL,"chicken"),"Owner sketches the chicken"):return
	stand(host,GROWER,SHEEP)
	if not check(not await action(owner,Goals.SKETCH_ACTION,SHEEP,"sheep") and mine(owner).size()==3,"Fourth distinct subject refused at the cap"):return
	if not check(mine(friend).size()==2 and goal_state(friend)!="done","Guest still has two sketches"):return
	await create_timer(1.05).timeout
	stand(host,GROWER,COW)

	# Reward gated per player: guest cannot report or build yet.
	var locked_spot:=COW+EASEL_SPOTS[0]
	if not check(not await action(owner,"build",locked_spot,"sketch_easel"),"Owner cannot build the easel before reporting"):return
	if not check(not await report(host,friend,FRIEND) and not Goals.done(state.players[FRIEND],"diandian").has(1),"Guest report refused with two sketches"):return
	if not check(await report(host,owner,GROWER),"Owner reports at diandian's garden place"):return
	if not check(await wait_for(func():return goal_state(owner)=="done") and goal_state(friend)!="done","Only the owner's goal is done"):return
	var owner_spot:=await build_easel(host,owner,GROWER)
	if not check(owner_spot.x>=0 and state.objects[World.key(owner_spot)].type=="sketch_easel","Owner builds the unlocked easel"):return
	if not check(not await action(friend,"build",COW+EASEL_SPOTS[5],"sketch_easel"),"Guest easel still locked"):return

	# Guest's own third sketch (sheep), own report, own build.
	stand(host,FRIEND,SHEEP)
	if not check(await action(friend,Goals.SKETCH_ACTION,SHEEP,"sheep") and mine(friend).size()==3 and mine(owner).size()==3,"Guest completes a different third subject"):return
	if not check(await report(host,friend,FRIEND) and await wait_for(func():return goal_state(friend)=="done"),"Guest reports independently"):return
	var friend_spot:=await build_easel(host,friend,FRIEND,[owner_spot])
	if not check(friend_spot.x>=0 and friend_spot!=owner_spot,"Guest builds their own easel"):return
	if not await sketches_at_the_pond(host,owner,friend):return
	if not await painting_invites_over_network(host,owner,friend):return
	if not await network_mural_n114(host,owner,friend,address,port):return

	# Persistence: live save reload, and a reconnecting owner keeps the private state.
	owner.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host sees owner leave"):return
	var returned:=make_session("SketchReturned",GROWER)
	if not check(returned.join(address,port,"回來的畫家",ROOM)==OK and await wait_for(func():return not returned.own_id.is_empty() and goal_state(returned)=="done" and mine(returned).size()==3),"Reconnect keeps sketches and completion"):return
	var loaded:=World.new()
	if not check(host.world.save() and loaded.load_world(path),"Save and load the room"):return
	for token in [GROWER,FRIEND]:
		if not check(Goals.done(loaded.state.players[token],"diandian").has(1) and loaded.state.players[token].get(Goals.SKETCH_KEY,{}).size()==3,"Completion and sketches persist for %s"%token):return
	if not check(Goals.done(loaded.state.players[GROWER],"diandian").get(2)=="knees" and Goals.done(loaded.state.players[FRIEND],"diandian").get(2)=="cup","Both saved pose choices survive reload"):return
	if not check(loaded.state.objects[World.key(owner_spot)].type=="sketch_easel" and loaded.state.objects[World.key(friend_spot)].type=="sketch_easel" and loaded.state.livestock.has("cow") and loaded.state.crops==crops_before,"Easels, adoption and untouched crop persist"):return
	finish(0)

func sketches_at_the_pond(host:Session,owner:Session,friend:Session)->bool:
	await create_timer(1.05).timeout
	var players:Dictionary=host.world.state.players
	for token:String in [GROWER,FRIEND]:
		players[token].bonds.diandian.points=6 # Fixture: both have reached the second bond tier.
	var pond:=Bond.GARDEN_CELL
	if not check(await visit(host,owner,GROWER,pond,Bond.GARDEN_REGION) and await visit(host,friend,FRIEND,pond,Bond.GARDEN_REGION),"Both clients reach the garden"):return false
	if not check(not await action(friend,Goals.ACTION,pond,"diandian:2:cup:"),"A guest must choose a seat for their own session"):return false
	if not check(await action(owner,Goals.DIANDIAN_SEAT_ACTION,pond) and await action(friend,Goals.DIANDIAN_SEAT_ACTION,pond),"Both can sit next to Diandian"):return false
	var first:=Vector2(players[GROWER].x,players[GROWER].y)
	var second:=Vector2(players[FRIEND].x,players[FRIEND].y)
	if not check(first!=second,"Concurrent guests have distinct seats"):return false
	var checkpoint:=World.new()
	if not check(host.world.save() and checkpoint.load_world(path) and not checkpoint.state.players[GROWER].has(Goals.DIANDIAN_SEAT_KEY),"The temporary sit pose is cleared when restoring a save"):return false
	if not check(await wait_for(func():return friend.snapshot.players.get(owner.own_id,{}).get(Goals.DIANDIAN_SEAT_KEY,false)),"The friend's view sees the seated pose"):return false
	host.world.move_player(GROWER,Vector2.LEFT,0.1)
	if not check(not players[GROWER].has(Goals.DIANDIAN_SEAT_KEY) and not await action(owner,Goals.ACTION,pond,"diandian:2:knees:"),"Walking away cancels the reference pose"):return false
	if not check(await action(owner,Goals.DIANDIAN_SEAT_ACTION,pond),"The owner can sit again"):return false
	if not check(await action(friend,Goals.ACTION,pond,"diandian:2:cup:") and not Goals.done(players[GROWER],"diandian").has(2),"A guest completing a pose only unlocks their own pattern"):return false
	if not check(await action(owner,Goals.ACTION,pond,"diandian:2:knees:") and players[GROWER].inventory.get("keepsake_diandian_kit")==players[FRIEND].inventory.get("keepsake_diandian_kit"),"Either pose gives the same keepsake"):return false
	return true

const PAINT_SHARED:=["aru","nuannuan"] # both players invite these two (home + jiaoxi: different regions)
const PAINT_OWNER_THIRD:="milu"
const PAINT_FRIEND_THIRD:="xiaoli"

func paint_invites(session:Session)->Array:
	return session.snapshot.get("own_diandian_invites",[])
func host_invites(host:Session,token:String)->Array:
	return host.world.state.players[token].get(Goals.PAINT_INVITES_KEY,[])
func goal_state_of(session:Session,stage:int)->String:
	return str(session.snapshot.get("resident_goals",{}).get("diandian",{}).get(str(stage),{}).get("state",""))
## Walk to the resident's authoritative place and ask. Place comes from the host state (what the server checks).
func invite(host:Session,session:Session,token:String,id:String)->bool:
	var place:Array=World.bond_place(host.world.state,id)
	var cell:Vector2i=place[1]
	if not await visit(host,session,token,cell,str(place[0])):return false
	return await action(session,Goals.PAINT_INVITE_ACTION,cell,id)
## Same as report() but for N11-3. Leaves the player in the garden.
func report_painting(host:Session,session:Session,token:String)->bool:
	if not await visit(host,session,token,Bond.GARDEN_CELL,Bond.GARDEN_REGION):return false
	return await action(session,Goals.ACTION,World.bond_place(session.snapshot,"diandian")[1],"diandian:3::")

func painting_invites_over_network(host:Session,owner:Session,friend:Session)->bool:
	await create_timer(1.05).timeout # per-peer limit is 12 actions/second; keep every burst well below it
	var state:Dictionary=host.world.state
	var players:Dictionary=state.players
	for token:String in [GROWER,FRIEND]:
		players[token].bonds.diandian.points=14 # Fixture: both reached trust tier 3 (THRESHOLDS[2]).
	if not check(Bond.stage(players[GROWER],"diandian")==3 and Bond.stage(players[FRIEND],"diandian")==3,"Both are at trust tier 3 (not 4: the public mural stays out of scope)"):return false
	if not check(Goals.done(players[GROWER],"diandian").has(2) and Goals.done(players[FRIEND],"diandian").has(2) and not Goals.done(players[GROWER],"diandian").has(3),"Both finished N11-2 and neither has N11-3 yet"):return false
	if not check(paint_invites(owner).is_empty() and paint_invites(friend).is_empty() and not state.has(Goals.MURAL_KEY),"Nobody has invited anyone and no public mural exists"):return false

	# Gate: inviting needs the player's OWN N11-2. TEMPORARY FIXTURE: hide the friend's N11-2 record in the host's
	# in-memory state only (host physics/autosave is off, nothing is saved in between), try once, restore exactly.
	# Trust is already tier 3 and the friend stands at Aru, so the only possible refusal reason is the missing N11-2.
	var book:Dictionary=players[FRIEND][Goals.RECORD_KEY].diandian
	var pose:String=str(book["2"])
	book.erase("2")
	var early:bool=await invite(host,friend,FRIEND,PAINT_SHARED[0])
	book["2"]=pose
	if not check(not early and host_invites(host,FRIEND).is_empty() and Goals.done(players[FRIEND],"diandian").get(2)==pose,"Invite before the player's own N11-2 is refused, and the fixture was restored"):return false
	await create_timer(1.05).timeout

	# Guards, owner only.
	if not check(await visit(host,owner,GROWER,Bond.GARDEN_CELL,Bond.GARDEN_REGION) and not await action(owner,Goals.PAINT_INVITE_ACTION,Bond.GARDEN_CELL,"diandian"),"Cannot invite Diandian herself"):return false
	if not check(not await action(owner,Goals.PAINT_INVITE_ACTION,Bond.GARDEN_CELL,"not_a_resident"),"Unknown resident id is refused"):return false
	var aru:Array=World.bond_place(state,"aru")
	var aru_cell:Vector2i=aru[1]
	# Wrong region: standing in the garden while naming Aru's tile.
	if not check(not await action(owner,Goals.PAINT_INVITE_ACTION,aru_cell,"aru") and host_invites(host,GROWER).is_empty(),"Wrong region is refused"):return false
	# Out of range: right region, ten tiles away from Aru, asking for Aru's tile.
	stand(host,GROWER,aru_cell+Vector2i(10,0),str(aru[0]))
	if not check(not await action(owner,Goals.PAINT_INVITE_ACTION,aru_cell,"aru") and host_invites(host,GROWER).is_empty(),"Out-of-range invite is refused"):return false
	# Right region and distance but the wrong resident's id for this tile.
	stand(host,GROWER,aru_cell,str(aru[0]))
	if not check(not await action(owner,Goals.PAINT_INVITE_ACTION,aru_cell,"nuannuan") and host_invites(host,GROWER).is_empty(),"Naming someone who is not at this tile is refused"):return false
	await create_timer(1.05).timeout

	# Independence + mutual NPCs, in DIFFERENT orders: owner aru,nuannuan ; friend nuannuan,aru.
	if not check(await invite(host,owner,GROWER,PAINT_SHARED[0]),"Owner invites Aru"):return false
	if not check(await wait_for(func():return paint_invites(owner)==["aru"]) and host_invites(host,FRIEND).is_empty() and paint_invites(friend).is_empty(),"Owner's first invite does not touch the friend"):return false
	if not check(await invite(host,friend,FRIEND,PAINT_SHARED[1]),"Friend invites Nuannuan first"):return false
	if not check(await wait_for(func():return paint_invites(friend)==["nuannuan"]) and paint_invites(owner)==["aru"],"Friend's first invite does not touch the owner"):return false
	# Duplicate guard.
	if not check(not await invite(host,owner,GROWER,"aru") and host_invites(host,GROWER)==["aru"],"The same resident cannot take a second place"):return false
	await create_timer(1.05).timeout
	if not check(await invite(host,owner,GROWER,PAINT_SHARED[1]) and await invite(host,friend,FRIEND,PAINT_SHARED[0]),"Both invite the second shared resident (already asked by the other player)"):return false
	if not check(await wait_for(func():return paint_invites(owner)==["aru","nuannuan"] and paint_invites(friend)==["nuannuan","aru"]),"Same two residents, opposite order, each list private to its owner"):return false
	await create_timer(1.05).timeout

	# Reporting with two of three is refused for either player.
	if not check(not await report_painting(host,owner,GROWER) and not Goals.done(players[GROWER],"diandian").has(3),"Report with two invites is refused"):return false

	# Distinct third residents.
	if not check(await invite(host,owner,GROWER,PAINT_OWNER_THIRD) and await invite(host,friend,FRIEND,PAINT_FRIEND_THIRD),"Each invites a different third resident"):return false
	if not check(await wait_for(func():return paint_invites(owner)==["aru","nuannuan","milu"] and paint_invites(friend)==["nuannuan","aru","xiaoli"]),"Own invite lists stay independent"):return false
	if not check(host_invites(host,GROWER)==["aru","nuannuan","milu"] and host_invites(host,FRIEND)==["nuannuan","aru","xiaoli"],"Host state matches the clients' private views"):return false
	await create_timer(1.05).timeout
	# Cap guard (third residents swapped, so a 4th is a genuinely new resident for each).
	if not check(not await invite(host,owner,GROWER,PAINT_FRIEND_THIRD) and not await invite(host,friend,FRIEND,PAINT_OWNER_THIRD) and host_invites(host,GROWER).size()==3 and host_invites(host,FRIEND).size()==3,"A fourth resident is refused at the cap"):return false

	# Privacy of the key in the shared snapshot.
	for host_peer in host.peers:host._send_snapshot(host_peer)
	await process_frame
	await process_frame
	for viewer:Session in [owner,friend]:
		for person:Dictionary in viewer.snapshot.players.values():
			if not check(not person.has(Goals.PAINT_INVITES_KEY),"Invite list is absent from every player entry in the snapshot"):return false
	await create_timer(1.05).timeout

	# Reports, each player on their own. Owner first; friend must still be open.
	if not check(await report_painting(host,owner,GROWER) and await wait_for(func():return goal_state_of(owner,3)=="done"),"Owner reports with diandian:3::"):return false
	if not check(goal_state_of(friend,3)!="done" and not Goals.done(players[FRIEND],"diandian").has(3),"Owner's report does not complete the friend's N11-3"):return false
	if not check(await report_painting(host,friend,FRIEND) and await wait_for(func():return goal_state_of(friend,3)=="done"),"Friend reports with diandian:3::"):return false
	if not check(not await report_painting(host,owner,GROWER),"A finished N11-3 cannot be reported twice"):return false

	# Personal first mural: private to each player's own book; nothing is hung publicly (that is N11-4, tier 4).
	for token:String in [GROWER,FRIEND]:
		if not check(Goals.done(players[token],"diandian").has(3),"N11-3 record saved for %s"%token):return false
	if not check(not state.has(Goals.MURAL_KEY) and not owner.snapshot.get("own_diandian_mural",false) and not friend.snapshot.get("own_diandian_mural",false),"No public mural is hung; the first mural stays personal"):return false

	# Persistence of the invite lists and both completions.
	var loaded:=World.new()
	if not check(host.world.save() and loaded.load_world(path),"Save and load with N11-3 done"):return false
	if not check(loaded.state.players[GROWER][Goals.PAINT_INVITES_KEY]==["aru","nuannuan","milu"] and loaded.state.players[FRIEND][Goals.PAINT_INVITES_KEY]==["nuannuan","aru","xiaoli"],"Invite lists persist per player"):return false
	for token:String in [GROWER,FRIEND]:
		if not check(Goals.done(loaded.state.players[token],"diandian").has(3),"N11-3 completion persists for %s"%token):return false
	return true

const MURAL_PLACE:=Goals.MURAL_SITE # (40,29) in HOME

## Both players ask in the same frame; every reply is awaited. Like pair(), but for an arbitrary action at one cell.
func race(a:Session,b:Session,name:String)->Array:
	var seen_a:int=notices[a].size()
	var seen_b:int=notices[b].size()
	a.perform(name,MURAL_PLACE,"")
	b.perform(name,MURAL_PLACE,"")
	if not await wait_for(func():return notices[a].size()>seen_a and notices[b].size()>seen_b):return [false,false,false]
	return [true,notices[a].back().ok,notices[b].back().ok]
## Go to the board / to Diandian's garden, then act. Leaves the player in HOME at the board afterwards only for hang/sign.
func at_board(host:Session,session:Session,token:String)->bool:
	return await visit(host,session,token,MURAL_PLACE,World.REGIONS.HOME)
func report_stage(host:Session,session:Session,token:String,stage:int)->bool:
	if not await visit(host,session,token,Bond.GARDEN_CELL,Bond.GARDEN_REGION):return false
	return await action(session,Goals.ACTION,World.bond_place(session.snapshot,"diandian")[1],"diandian:%d::"%stage)

func network_mural_n114(host:Session,owner:Session,friend:Session,address:String,port:int)->bool:
	await create_timer(1.05).timeout # stay below the per-peer 12 actions/second limit
	var state:Dictionary=host.world.state
	var players:Dictionary=state.players
	var by_session:={GROWER:owner,FRIEND:friend}
	if not check(Bond.stage(players[GROWER],"diandian")==3 and Goals.done(players[FRIEND],"diandian").has(3) and not state.has(Goals.MURAL_KEY),"Start at trust tier 3 with N11-3 done and no mural"):return false

	# Before the exhibit opens, neither hanging nor reporting is available.
	if not check(await at_board(host,owner,GROWER) and not await action(owner,Goals.MURAL_HANG_ACTION,MURAL_PLACE),"Hang is refused below trust tier 4"):return false
	if not check(not await action(owner,Goals.MURAL_SIGN_ACTION,MURAL_PLACE) and not state.has(Goals.MURAL_KEY),"Sign is refused while no mural is up"):return false
	if not check(not await report_stage(host,owner,GROWER,4) and not Goals.done(players[GROWER],"diandian").has(4),"N11-4 report is refused before the stage opens"):return false
	await create_timer(1.05).timeout
	for token:String in [GROWER,FRIEND]:
		players[token].bonds.diandian.points=24 # Fixture: trust tier 4 (THRESHOLDS[3]).
	if not check(Bond.stage(players[GROWER],"diandian")==4 and Bond.stage(players[FRIEND],"diandian")==4,"Both reach trust tier 4"):return false
	if not check(not await report_stage(host,friend,FRIEND,4) and not state.has(Goals.MURAL_KEY),"Tier 4 alone does not complete N11-4 without a mural contribution"):return false
	await create_timer(1.05).timeout

	# --- Race to hang: exactly one author, no replacement. ---
	if not check(await at_board(host,owner,GROWER) and await at_board(host,friend,FRIEND),"Both stand at the board"):return false
	var invites_before:={GROWER:host_invites(host,GROWER).duplicate(),FRIEND:host_invites(host,FRIEND).duplicate()}
	var replies:Array=await race(owner,friend,Goals.MURAL_HANG_ACTION)
	if not check(replies[0] and int(replies[1])+int(replies[2])==1,"Exactly one of two simultaneous hangs is accepted"):return false
	var author:String=str(state[Goals.MURAL_KEY].author)
	var other:String=FRIEND if author==GROWER else GROWER
	var hung:Dictionary=state[Goals.MURAL_KEY].duplicate(true)
	if not check(author==(GROWER if replies[1] else FRIEND) and hung.subjects==invites_before[author] and hung.signatures.is_empty(),"The accepted player is the sole author with their own invites and nobody has signed"):return false
	await create_timer(1.05).timeout
	if not check(not await action(by_session[other],Goals.MURAL_HANG_ACTION,MURAL_PLACE) and not await action(by_session[author],Goals.MURAL_HANG_ACTION,MURAL_PLACE) and state[Goals.MURAL_KEY]==hung,"A later hang cannot replace the mural or change the author"):return false
	if not check(not await action(by_session[author],Goals.MURAL_SIGN_ACTION,MURAL_PLACE) and state[Goals.MURAL_KEY]==hung,"The author cannot also sign"):return false

	# --- Personal completion: the author is done, the other player still is not. ---
	await create_timer(1.05).timeout
	if not check(await report_stage(host,by_session[author],author,4) and await wait_for(func():return goal_state_of(by_session[author],4)=="done"),"Author reports N11-4"):return false
	if not check(not await report_stage(host,by_session[other],other,4) and goal_state_of(by_session[other],4)!="done" and not Goals.done(players[other],"diandian").has(4),"The other player is not credited by the author's mural"):return false
	await create_timer(1.05).timeout

	# --- The other player signs once, then reports. ---
	if not check(goal_state_of(by_session[other],4)!="done","The author report does not complete the other player's story"):return false
	if not check(await at_board(host,by_session[other],other) and await action(by_session[other],Goals.MURAL_SIGN_ACTION,MURAL_PLACE),"The other player signs the mural"):return false
	if not check(not await action(by_session[other],Goals.MURAL_SIGN_ACTION,MURAL_PLACE) and state[Goals.MURAL_KEY].signatures.size()==1 and state[Goals.MURAL_KEY].signatures.has(other) and state[Goals.MURAL_KEY].author==author,"A second signature is refused and the author is unchanged"):return false
	await create_timer(1.05).timeout
	if not check(await report_stage(host,by_session[other],other,4) and await wait_for(func():return goal_state_of(by_session[other],4)=="done"),"The signer reports N11-4"):return false

	# --- Public privacy: the shared snapshot carries names and subjects only, never tokens or invite lists. ---
	for host_peer in host.peers:host._send_snapshot(host_peer)
	if not check(await wait_for(func():return friend.snapshot.get(Goals.MURAL_KEY,{}).get("names",[]).size()==1 and owner.snapshot.get(Goals.MURAL_KEY,{}).get("names",[]).size()==1),"Both clients receive the public mural"):return false
	for viewer:Session in [owner,friend]:
		var shown:Dictionary=viewer.snapshot[Goals.MURAL_KEY]
		if not check(shown.keys().size()==3 and shown.has("subjects") and shown.has("author_name") and shown.has("names"),"Public mural exposes exactly subjects, author_name and names"):return false
		if not check(shown.author_name==str(players[author].name).left(12) and shown.names==[str(players[other].name).left(12)] and shown.subjects==hung.subjects,"Public mural shows display names and the author's subjects"):return false
		var text:=var_to_str(shown)
		if not check(not text.contains(GROWER) and not text.contains(FRIEND),"Public mural does not leak player tokens"):return false
		for person:Dictionary in viewer.snapshot.players.values():
			if not check(not person.has(Goals.PAINT_INVITES_KEY),"Invite lists stay absent from every player entry"):return false
	if not check(owner.snapshot.get("own_diandian_mural",false) and friend.snapshot.get("own_diandian_mural",false),"Each player's private flag says they contributed"):return false

	# --- Stable credit: save, load, reconnect. ---
	var loaded:=World.new()
	if not check(host.world.save() and loaded.load_world(path),"Save and load with N11-4 done"):return false
	if not check(loaded.state[Goals.MURAL_KEY]==state[Goals.MURAL_KEY] and Goals.mural_contributed(loaded.state,GROWER) and Goals.mural_contributed(loaded.state,FRIEND),"Mural, author and signature persist and both are still credited"):return false
	for token:String in [GROWER,FRIEND]:
		if not check(Goals.done(loaded.state.players[token],"diandian").has(4),"N11-4 completion persists for %s"%token):return false
	var expected_record:Dictionary=state[Goals.MURAL_KEY].duplicate(true)
	var expected_public:=Goals.mural_public(state)
	friend.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host sees the friend leave"):return false
	var again:=make_session("SketchFriendAgain",FRIEND)
	if not check(again.join(address,port,"再回來的畫家",ROOM)==OK and await wait_for(func():return not again.own_id.is_empty() and goal_state_of(again,4)=="done" and again.snapshot.get("own_diandian_mural",false)),"Reconnect keeps N11-4 done and the personal credit"):return false
	if not check(again.snapshot.get(Goals.MURAL_KEY,{})==expected_public,"Reconnected client still sees the same public mural"):return false
	if not check(await at_board(host,again,FRIEND) and not await action(again,Goals.MURAL_SIGN_ACTION,MURAL_PLACE) and not await action(again,Goals.MURAL_HANG_ACTION,MURAL_PLACE) and state[Goals.MURAL_KEY]==expected_record,"After reconnect nothing can be signed or hung twice and the record is unchanged"):return false
	return true
