extends "res://tests/network_egg_basket.gd"
## A dedicated host and isolated WebSocket clients. Board positions and
## inventory are seeded; all exhibit changes go through the session.

const BOARD:=Vector2i(40,29)

func finish(code:int) -> void:
	for i in range(sessions.size()-1,-1,-1):
		if not sessions[i].shutting_down:sessions[i].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("COLLECTION_GALLERY_SESSION_TESTS checks=%d failures=%d"%[checks,code])
	quit(code)

func exhibit(client:Session,id:String) -> Array:
	return client.snapshot.get("collection_exhibits",{}).get(id,{}).get("items",[])

func run() -> void:
	path="user://gallery-session-%d.json"%OS.get_process_id()
	var world:=World.new()
	world.save_path=path
	for token in [GROWER,FRIEND]:
		world.add_player(token,"Gallery Resident")
		world.state.players[token].x=BOARD.x+0.5
		world.state.players[token].y=BOARD.y+1.5
	world.state.players[GROWER].inventory.merge({"radish":2,"quality_radish":1,"gold_sample":1},true)
	if not check(world.save(),"Save isolated gallery fixture"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var address:="ws://127.0.0.1:%d"%port
	var host:=make_session("Host","gallery-network-host")
	if not check(host.host(port,"Host",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a dedicated room"):return
	var owner:=make_session("Owner",GROWER)
	var visitor:=make_session("Visitor",FRIEND)
	if not check(owner.join(address,port,"Collector",ROOM)==OK and visitor.join(address,port,"Visitor",ROOM)==OK,"Connect two clients"):return
	if not check(await wait_for(func():return not owner.own_id.is_empty() and visitor.snapshot.get("players",{}).has(owner.own_id)),
		"Both islanders appear together"):return
	var id:=owner.own_id
	var rejected:=not await action(owner,"collection_donate",BOARD,"quality_radish")
	if not check(rejected and str(notices[owner].back().message).contains("普通收藏"),"Quality crop cannot be donated"):return
	var donated:=await action(owner,"collection_donate",BOARD,"radish")
	if not check(donated,"Donate the normal crop through the client: "+str(notices[owner].back())):return
	if not check(not await action(owner,"collection_donate",BOARD,"radish"),"A fresh request cannot charge twice for the same donation"):return
	if not check(await action(owner,"collection_donate",BOARD,"gold_sample"),"Register a keepsake through the client"):return
	if not check(exhibit(visitor,id).is_empty(),"Donating alone does not show either item publicly"):return
	for item in ["radish","gold_sample"]:
		if not check(await action(owner,"collection_display",BOARD,item),"Publish "+item):return
	if not check(await wait_for(func():return exhibit(visitor,id)==["radish","gold_sample"]),"A visitor sees both displayed pieces"):return
	if not check(not visitor.snapshot.players[id].has("collection_donations") and not visitor.snapshot.players[id].has("inventory"),
		"The display does not reveal private donations or inventory"):return
	if not check(not await action(visitor,"collection_unshow",BOARD,"radish") and exhibit(visitor,id)==["radish","gold_sample"],
		"The visitor cannot remove the owner's exhibit"):return
	owner.shutdown()
	if not check(await wait_for(func():return not visitor.snapshot.get("players",{}).has(id) and exhibit(visitor,id)==["radish","gold_sample"]),
		"The exhibit stays visible after its owner disconnects"):return
	visitor.shutdown()
	host.shutdown()
	var reopened:=World.new()
	if not check(reopened.load_world(path) and not reopened.recovered_from_backup,"Reload the main save after host shutdown"):return
	var saved:Dictionary=reopened.state.players[GROWER]
	if not check(int(saved.inventory.radish)==1 and int(saved.inventory.quality_radish)==1 and int(saved.inventory.gold_sample)==1,
		"One ordinary crop is charged and the other grades and keepsake survive"):return
	if not check(saved.collection_display==["radish","gold_sample"] and saved.collection_donations.size()==2,
		"The public and private collection records are durable"):return
	finish(0)
