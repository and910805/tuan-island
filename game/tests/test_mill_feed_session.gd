extends "res://tests/test_corn_chowder_session.gd"
## Reuse the loopback Session fixture. The mill, materials and position are
## seeded; every processing operation goes through a connected client.

const MILL:=Vector2i(41,34)

func seed_world(path:String)->bool:
	var w:=World.new()
	for token in [ALPHA,BETA]:
		w.add_player(token,"mill tester")
		var person:Dictionary=w.state.players[token]
		preset(person,"x",40.5)
		preset(person,"y",34.5)
	preset(w.state.players[ALPHA].inventory,"sweet_corn",2)
	preset(w.state.players[ALPHA].inventory,"fiber",4)
	preset(w.state.objects,World.key(MILL),{"type":"mill","owner":ALPHA,"items":{},"input_wheat":0,"auto_enabled":false})
	w.save_path=path
	return w.save()

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("mill-feed-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"create isolated test directory"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"seed isolated mill and materials"):return false
	var port:=start_server()
	if not expect(port>0,"host WebSocket server"):return false
	alpha=await join("owner",ALPHA,port)
	beta=await join("guest",BETA,port)
	if not expect(joined(alpha) and joined(beta),"both clients joined"):return false
	var queued:=await act(alpha,"queue_processing",MILL,"feed")
	expect(queued.ok,"owner queues corn feed")
	alpha.session.request_action.rpc_id(1,int(queued.sequence),"queue_processing",MILL,"feed","home",int(alpha.me().get("travel_epoch",0)))
	await settle([alpha,beta])
	expect(alpha.bag().get("sweet_corn",0)==1 and alpha.bag().get("fiber",0)==2,"replayed request cannot charge a second batch")
	expect(not (await act(alpha,"claim_processing",MILL)).ok,"owner cannot claim early")
	expect(server.world.step(60.0,true),"advance world clock for completed job")
	await settle([alpha,beta])
	var mill:Dictionary=beta.session.snapshot.get("objects",{}).get(World.key(MILL),{})
	var ready:Array=mill.get("processing",{}).get("ready",[])
	expect(ready.size()==1 and ready[0].get("kind")=="feed","guest sees one ready feed job")
	expect(not (await act(beta,"claim_processing",MILL)).ok and beta.bag().get("feed",0)==0,"guest cannot take feed")
	expect((await act(alpha,"claim_processing",MILL)).ok and alpha.bag().get("feed",0)==4,"owner receives four feed")
	expect(not (await act(alpha,"claim_processing",MILL)).ok and alpha.bag().get("feed",0)==4,"owner cannot claim twice")
	return true
