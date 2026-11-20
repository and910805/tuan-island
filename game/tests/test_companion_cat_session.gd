extends "res://tests/network_egg_basket.gd"

func run() -> void:
	path=OS.get_environment("TEMP").path_join("cat-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	var site:=World.Cat.site(fixture.state)
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"島民")
		fixture.state.players[token].x=site.x+0.5
		fixture.state.players[token].y=site.y+0.5
	if not check(fixture.save(),"Save a room with the resident cat available"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("CatHost","cat-host")
	if not check(host.host(port,"風鈴渡口",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a dedicated WebSocket room"):return
	var owner:=make_session("CatOwner",GROWER)
	var guest:=make_session("CatGuest",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(owner.join(address,port,"主人",ROOM)==OK and guest.join(address,port,"訪客",ROOM)==OK,"Connect the owner and guest"):return
	if not check(await wait_for(func():return not owner.own_id.is_empty() and not guest.own_id.is_empty()),"Both clients arrive"):return
	if not check(await action(owner,"cat_adopt",site),"Adopt the cat through the multiplayer action"):return
	if not check(await action(owner,"cat_pet",site),"Greet the cat through the multiplayer action"):return
	if not check(await wait_for(func():return sees_reaction(owner,guest,"pet")),"Guest receives the greeting within the animation window"):return
	host.world.step(World.Rabbit.PET_INTERVAL,true)
	if not check(await action(owner,"cat_yarn",site),"Play yarn through the multiplayer action"):return
	if not check(await wait_for(func():return sees_reaction(owner,guest,"yarn")),"Guest receives the yarn reaction within the animation window"):return
	var public_cat:Dictionary=guest.snapshot.players[owner.own_id][World.Cat.FIELD]
	if not check(public_cat.size()==3 and not public_cat.has("bond"),"Guest sees only the cat's presentation fields"):return
	if not check(int(owner.snapshot.players[owner.own_id][World.Cat.FIELD].bond)==2,"Owner retains the accrued bond"):return
	print("COMPANION_CAT_SESSION checks=%d failures=0"%checks)
	finish(0)

func sees_reaction(owner:Session,guest:Session,reaction:String) -> bool:
	var cat:Dictionary=guest.snapshot.get("players",{}).get(owner.own_id,{}).get(World.Cat.FIELD,{})
	var age:=float(guest.snapshot.get("time",0))-float(cat.get("last_pet",-30.0))
	return cat.get("following",false) and cat.get("last_play")==reaction and age>=0.0 and age<1.35
