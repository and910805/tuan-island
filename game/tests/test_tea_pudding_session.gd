extends "res://tests/test_corn_chowder_session.gd"
## WebSocket loopback with a seeded stove, positions and ingredients.

const STOVE:=Vector2i(42,34)
const DISH:="tea_pudding"

func seed_world(path:String)->bool:
	var w:=World.new()
	for token in [ALPHA,BETA]:
		w.add_player(token,"pudding tester")
		var person:Dictionary=w.state.players[token]
		preset(person,"x",41.5)
		preset(person,"y",34.5)
	for item in ["tea_leaf","milk","egg"]:
		preset(w.state.players[ALPHA].inventory,item,1)
	preset(w.state.objects,World.key(STOVE),{"type":"stove","owner":ALPHA,"items":{}})
	w.save_path=path
	return w.save()

func queue_for(c:Client)->Dictionary:
	return c.session.snapshot.get("objects",{}).get(World.key(STOVE),{}).get("cooking",{})

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("tea-pudding-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"create isolated test directory"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"seed stove and ingredients"):return false
	var port:=start_server()
	if not expect(port>0,"host WebSocket server"):return false
	alpha=await join("cook",ALPHA,port)
	beta=await join("guest",BETA,port)
	if not expect(joined(alpha) and joined(beta),"cook and guest joined"):return false
	var queued:=await act(alpha,"queue_cook",STOVE,DISH)
	expect(queued.ok and queued.message.contains("茶香布丁"),"cook receives pudding queue acknowledgement")
	for item in ["tea_leaf","milk","egg"]:
		expect(alpha.bag().get(item,0)==0,"cook pays one "+item)
	await settle([alpha,beta])
	expect(queue_for(beta).get("active",{}).get("kind")==DISH,"guest sees active pudding")
	expect(not (await act(beta,"claim_cook",STOVE)).ok,"guest cannot claim before it finishes")
	expect(server.world.step(120.0,true),"advance cooking time")
	await settle([alpha,beta])
	var ready:Array=queue_for(beta).get("ready",[])
	expect(ready.size()==1 and ready[0].get("kind")==DISH,"guest sees ready pudding")
	var claimed:=await act(beta,"claim_cook",STOVE)
	expect(claimed.ok and claimed.message.contains("茶香布丁"),"guest receives pudding claim acknowledgement")
	expect(beta.bag().get(DISH,0)==3 and alpha.bag().get(DISH,0)==0,"only guest receives three puddings")
	expect(not (await act(alpha,"claim_cook",STOVE)).ok,"cook cannot claim the same batch")
	expect((queue_for(alpha).get("ready",[]) as Array).is_empty(),"cook sees batch removed")
	leave(alpha)
	leave(beta)
	if not expect(await stop_server(),"normal server shutdown"):return false
	port=start_server()
	if not expect(port>0,"restart WebSocket server from same save"):return false
	beta=await join("guest",BETA,port)
	if not expect(joined(beta),"guest reconnects"):return false
	expect(beta.bag().get(DISH,0)==3 and (queue_for(beta).get("ready",[]) as Array).is_empty(),"reconnect retains pudding and no claimable batch")
	return true
