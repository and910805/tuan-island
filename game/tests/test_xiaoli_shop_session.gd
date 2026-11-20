extends "res://tests/network_egg_basket.gd"

const SHOP:=World.XIAOLI_SHOP
const GOALS:=World.RESIDENT_GOALS
const OWNER_A:="xiaoli-sign-owner-a"
const OWNER_B:="xiaoli-sign-owner-b"

func shop(session:Session) -> Dictionary:
	return session.snapshot.get("own_xiaoli_shop",{})

func finish(code:int) -> void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("XIAOLI_SHOP_SESSION checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func run() -> void:
	path="user://xiaoli-shop-network-%d.json"%OS.get_process_id()
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	var at:Vector2i=World.bond_place(fixture.state,"xiaoli")[1]
	for token in [OWNER_A,OWNER_B]:
		fixture.add_player(token,"島民",Vector2(at)+Vector2(0.5,1.5))
		var person:Dictionary=fixture.state.players[token]
		person.bonds={"xiaoli":{"points":24,"talk_day":-1,"gift_day":-1}}
		person[GOALS.RECORD_KEY]={"xiaoli":{"3":""}}
		person.inventory.plank=2
	if not check(fixture.save(),"Save the two private story fixtures"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Reserve a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("ShopHost","shop-host")
	if not check(host.host(port,"渡口",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start the WebSocket room"):return
	host.set_physics_process(false)
	var a:=make_session("ShopA",OWNER_A)
	var b:=make_session("ShopB",OWNER_B)
	var address:="ws://127.0.0.1:%d"%port
	if not check(a.join(address,port,"小海",ROOM)==OK and b.join(address,port,"小栗子",ROOM)==OK,"Connect both clients"):return
	if not check(await wait_for(func():return not a.own_id.is_empty() and not b.own_id.is_empty()),"Both clients enter"):return
	if not check(not await action(a,SHOP.SCALE_ACTION,at),"The scale is refused before the sign is hung"):return
	if not check(await action(a,GOALS.ACTION,at,"xiaoli:4:none:海風栗子舖"),"A hangs a custom Chinese sign"):return
	if not check(await wait_for(func():return shop(a).get("name")=="海風栗子舖") and shop(b).is_empty(),"The named sign is visible only to A"):return
	if not check(await action(b,GOALS.ACTION,at,"xiaoli:4:none:"),"B finishes without choosing a name"):return
	if not check(await wait_for(func():return shop(b).get("name")==SHOP.DEFAULT_NAME),"B receives the default sign"):return
	if not check(not await action(b,SHOP.SIGN_ACTION,at,"有:冒號"),"Invalid punctuation is rejected on the server"):return
	if not check(await action(b,SHOP.SIGN_ACTION,at,"海邊種子舖"),"B changes their own sign"):return
	if not check(await wait_for(func():return shop(b).get("name")=="海邊種子舖") and shop(a).get("name")=="海風栗子舖","Each client keeps their own sign"):return
	if not check(await action(a,SHOP.SCALE_ACTION,at) and not await action(a,SHOP.SCALE_ACTION,at),"A can claim exactly once"):return
	if not check(await wait_for(func():return shop(a).get("scale",false)) and not shop(b).get("scale",false),"Each scale claim is personal"):return
	for client in [a,b]:
		var rows:=JSON.stringify(client.snapshot.players)
		if not check(not rows.contains(SHOP.NAME_KEY) and not rows.contains(SHOP.SCALE_KEY),"Player rows omit private shop fields"):return
	if not check(host.shutdown(),"Close and save the host"):return
	var saved:=World.new()
	if not check(saved.load_world(path),"Reload the saved room"):return
	if not check(saved.state.players[OWNER_A].get(SHOP.NAME_KEY)=="海風栗子舖" and saved.state.players[OWNER_B].get(SHOP.NAME_KEY)=="海邊種子舖","Both names survive the reload"):return
	if not check(int(saved.state.players[OWNER_A].inventory.get(SHOP.SCALE_ITEM,0))==1 and not saved.state.players[OWNER_B].has(SHOP.SCALE_KEY),"Only the claimant has the persisted scale"):return
	finish(0)
