extends "res://tests/network_egg_basket.gd"

const Goals=World.RESIDENT_GOALS
const OWNER:="aru-park-photographer"
const DECORATOR:="aru-park-decorator"
const BIRD:="keepsake_aru_bird"

func finish(code:int) -> void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("ARU_PARK_PHOTO_SESSION_TESTS checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func seed_park() -> bool:
	var world:=World.new()
	world.save_path=path
	for token in [OWNER,DECORATOR]:
		world.add_player(token,token)
		var person:Dictionary=world.state.players[token]
		person.x=Goals.ARU_PARK_VIEW.x+0.5
		person.y=Goals.ARU_PARK_VIEW.y+0.5
		person.bonds={"aru":{"points":24,"talk_day":-1,"gift_day":-1}}
		person.stories.aru=2
		person.inventory.merge({"wood":40,"stone":20,"fiber":12},true)
	return world.save()

func confirmed_photo(client:Session,site:Vector2i) -> Dictionary:
	var reply:={}
	var expected:=client.counter+1
	var on_result:=func(sequence:int,name:String,result:Dictionary):
		if sequence==expected and name==Goals.ARU_PARK_PHOTO:reply.merge(result,true)
	client.action_completed.connect(on_result)
	client.perform(Goals.ARU_PARK_PHOTO,site)
	await wait_for(func():return not reply.is_empty(),3.0)
	client.action_completed.disconnect(on_result)
	return reply

func place(host:Session,token:String,site:Vector2i) -> void:
	var person:Dictionary=host.world.state.players[token]
	person.x=site.x+0.5
	person.y=site.y+0.5

func run() -> void:
	path="user://aru-park-network-%d.json"%OS.get_process_id()
	if not check(seed_park(),"Save two islanders at the public plot"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("AruParkHost","aru-park-network-host")
	if not check(host.host(port,"公園",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start the WebSocket host"):return
	var one:=make_session("Photographer",OWNER)
	var two:=make_session("Decorator",DECORATOR)
	var address:="ws://127.0.0.1:%d"%port
	if not check(one.join(address,port,"拍照",ROOM)==OK and two.join(address,port,"布置",ROOM)==OK,"Join from two clients"):return
	if not check(await wait_for(func():return not one.own_id.is_empty() and not two.own_id.is_empty()),"Both profiles load"):return

	var before:=await confirmed_photo(one,Goals.ARU_PARK_VIEW)
	if not check(before.get("ok",true)==false,"The incomplete plot returns a correlated refusal"):return
	if not check(await action(one,Goals.ARU_PARK_PLACE,Goals.ARU_PARK_SLOTS.long_bench,"long_bench"),"One islander puts down the bench"):return
	if not check(await action(two,Goals.ARU_PARK_PLACE,Goals.ARU_PARK_SLOTS.lamp,"lamp"),"Another islander places the lamp"):return
	if not check(await wait_for(func():return Goals.aru_park_has(one.snapshot.get("objects",{}),"lamp") and Goals.aru_park_has(two.snapshot.get("objects",{}),"long_bench")),"Both clients see both pieces"):return
	var bench:Vector2i=Goals.ARU_PARK_SLOTS.long_bench
	if not check(await action(one,Goals.MASTER_BENCH_SIT,bench) and await action(two,Goals.MASTER_BENCH_SIT,bench),"Two people can sit at the donated bench"):return
	var one_seat:Dictionary=host.world.state.players[OWNER].get(Goals.MASTER_BENCH_SEAT,{})
	var two_seat:Dictionary=host.world.state.players[DECORATOR].get(Goals.MASTER_BENCH_SEAT,{})
	if not check(one_seat.get("side",-1)==0 and two_seat.get("side",-1)==1,"Each islander has a distinct seat"):return
	var seated_save:=World.new()
	if not check(seated_save.load_world(path) and not seated_save.state.players[OWNER].has(Goals.MASTER_BENCH_SEAT),"Public seats clear when loaded from disk"):return
	if not check(await action(one,Goals.MASTER_BENCH_SIT,bench) and await action(two,Goals.MASTER_BENCH_SIT,bench),"Both stand up to take the photo"):return
	place(host,OWNER,Goals.ARU_PARK_VIEW+Vector2i(0,8))
	var far:=await confirmed_photo(one,Goals.ARU_PARK_VIEW)
	if not check(far.get("ok",true)==false and not host.world.state.players[OWNER].get(Goals.ARU_PHOTO_KEY,false),"Distance refuses the same photo request without setting progress"):return
	place(host,OWNER,Goals.ARU_PARK_VIEW)
	var accepted:=await confirmed_photo(one,Goals.ARU_PARK_VIEW)
	if not check(accepted.get("ok",false)==true,"A confirmed capture receives its own request acknowledgement"):return
	if not check(host.world.state.players[OWNER].get(Goals.ARU_PHOTO_KEY,false) and not host.world.state.players[DECORATOR].get(Goals.ARU_PHOTO_KEY,false),"Only the requesting islander earns the photo flag"):return
	var aru:Vector2i=World.bond_place(host.world.state,"aru")[1]
	place(host,OWNER,aru)
	place(host,DECORATOR,aru)
	if not check(not await action(two,Goals.ACTION,aru,"aru:4::"),"A friend who helped build still needs a photo"):return
	if not check(await action(one,Goals.ACTION,aru,"aru:4::"),"The photographer can report to Aru"):return
	var kit:=Goals.keepsake_item(BIRD)
	if not check(int(host.world.state.players[OWNER].inventory.get(kit,0))==1 and int(host.world.state.players[DECORATOR].inventory.get(kit,0))==0,"The carving is awarded once to the photographer"):return
	if not check(not await action(one,Goals.ACTION,aru,"aru:4::"),"Reporting twice never duplicates the carving"):return
	var reopened:=World.new()
	if not check(host.world.save() and reopened.load_world(path) and Goals.done(reopened.state.players[OWNER],"aru").has(4),"Finished relationship event reloads"):return
	finish(0)
