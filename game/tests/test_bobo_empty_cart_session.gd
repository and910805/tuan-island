extends "res://tests/test_bobo_cart_unlock_session.gd"
## Same-host WebSocket fixture. Friendship and actor approaches are prepared. Progress,
## regular ore loading, and restart all run through the real multiplayer Session.

const EmptyCart=preload("res://scripts/bobo_empty_cart.gd")
const OreRoute=preload("res://scripts/ore_route.gd")

func stage_of(c:Client)->int:
	return EmptyCart.stage(c.session.snapshot)

func stand(token:String,cell:Vector2i)->void:
	var p:Dictionary=server.world.state.players[token]
	p.x=cell.x+0.5
	p.y=cell.y+0.5

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("bobo-empty-cart-net-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"Isolated save folder"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"Generate a valid Jinguashi fixture"):return false
	var port:=start_server()
	if not expect(port>0,"Start loopback WebSocket server"):return false
	server.world.state.players[REPAIRER].bonds.bobo.points=24
	repairer=await join("repairer",REPAIRER,port)
	guest=await join("guest",GUEST,port)
	if not expect(joined(repairer) and joined(guest),"Two clients joined"):return false
	if not expect(await wait_until(func():return repairer.session.snapshot.has(EmptyCart.OWN_KEY) and guest.session.snapshot.has(EmptyCart.OWN_KEY),4.0),"Both receive their own initial progress"):return false
	expect(stage_of(repairer)==0 and stage_of(guest)==0,"Initially neither islander is pushing")
	var started:=await act(repairer,EmptyCart.ACTION,bobo_cell,"start")
	if not expect(started.replied and started.ok,"Start the story over WebSocket"):return false
	if not expect(await wait_until(func():return stage_of(repairer)==1,4.0),"Story start reaches the owner"):return false
	stand(GUEST,OreRoute.STOPS[0])
	var loaded:=await act(guest,OreRoute.ACTION,OreRoute.STOPS[0],"load")
	expect(loaded.replied and loaded.ok,"Neighbor retains the regular ore route")
	stand(REPAIRER,EmptyCart.STOPS[0])
	var pushed:=await act(repairer,EmptyCart.ACTION,EmptyCart.STOPS[0],"push")
	expect(pushed.replied and pushed.ok,"The owner pushes a segment")
	expect(await wait_until(func():return stage_of(repairer)==2 and OreRoute.stage(guest.session.snapshot)==1,4.0),"Story and worker carts update independently")
	expect(stage_of(guest)==0 and OreRoute.stage(repairer.session.snapshot)==0,"The action does not leak progress into the other cart")
	for player:Dictionary in guest.session.snapshot.get("players",{}).values():
		expect(not player.has(EmptyCart.FIELD),"Public profiles never carry story progress")
	leave(repairer)
	leave(guest)
	await pause(0.2)
	if not expect(await stop_server(),"Save and stop the dedicated server"):return false
	port=start_server()
	if not expect(port>0,"Restart using the same file"):return false
	repairer=await join("repairer",REPAIRER,port)
	guest=await join("guest",GUEST,port)
	if not expect(joined(repairer) and joined(guest),"Both rejoin after restart"):return false
	expect(await wait_until(func():return stage_of(repairer)==2 and OreRoute.stage(guest.session.snapshot)==1,4.0),"Two different carts read back from disk")
	expect(stage_of(guest)==0,"The guest still has no story progress")
	print("BOBO_EMPTY_CART_NETWORK_SCENARIO_OK")
	return true

func run()->void:
	var completed:=await scenario()
	expect(completed,"Loopback scenario reached the last check")
	await teardown()
	if completed and failures==0:expect(remove_folder(),"Remove isolated save")
	finished=true
	print("BOBO_EMPTY_CART_SESSION checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
