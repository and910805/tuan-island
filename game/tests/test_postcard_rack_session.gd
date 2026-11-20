extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Cards=World.POSTCARDS
const SITE:=Vector2i(40,34)
const OWNER:="postcard-traveler-owner"
const GUEST:="postcard-traveler-guest"
const ROOM:="postcards-loopback"
var checks:=0
var failures:=0
var path:String
var host:Session
var owner:Session
var guest:Session
var notices:Array[bool]=[]

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
	return ok

func session_at(name:String)->Session:
	var branch:=Node.new()
	branch.name=name
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(),branch.get_path())
	var session:=Session.new()
	branch.add_child(session)
	return session

func wait_for(condition:Callable)->bool:
	var until:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<until:
		if condition.call():return true
		await process_frame
	return condition.call()

func placed(client:Session)->Dictionary:
	return client.snapshot.get("objects",{}).get(World.key(SITE),{})

func run()->void:
	path="user://postcard-socket-%d.json"%Time.get_ticks_usec()
	await scenario()
	for session:Session in [guest,owner,host]:
		if session!=null:session.shutdown()
	await process_frame
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("POSTCARD_RACK_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func scenario()->void:
	var fixture:=World.new()
	fixture.save_path=path
	fixture.add_player(OWNER,"旅人")
	fixture.add_player(GUEST,"訪客")
	var traveler:Dictionary=fixture.state.players[OWNER]
	traveler.x=40.5
	traveler.y=33.5
	traveler.travel_book.visited.merge({"toucheng":true,"yingge":true})
	traveler.bonds={"luoluo":{"points":6,"talk_day":-1,"gift_day":-1}}
	traveler.bond_goals={"luoluo":{"2":""}}
	var visitor:Dictionary=fixture.state.players[GUEST]
	visitor.x=41.5
	visitor.y=33.5
	visitor.travel_book.visited.maokong=true
	if not expect(fixture.save(),"Save isolated legitimate travel histories"):return
	host=session_at("PostcardServer")
	var port:=0
	for attempt in 8:
		var trial:=randi_range(31000,58000)
		if host.host(trial,"",path,ROOM,"127.0.0.1",true,"websocket")==OK:
			port=trial
			break
	if not expect(port>0,"Host a real WebSocket endpoint"):return
	owner=session_at("Traveler")
	guest=session_at("Observer")
	owner.profile.token=OWNER
	guest.profile.token=GUEST
	guest.notice.connect(func(_message:String,ok:bool):notices.append(ok))
	var address:="ws://127.0.0.1:%d"%port
	if not expect(owner.join(address,port,"旅人",ROOM)==OK and guest.join(address,port,"訪客",ROOM)==OK,"Connect two real clients"):return
	if not expect(await wait_for(func():return not owner.own_id.is_empty() and not guest.own_id.is_empty()),"Both clients have snapshots"):return
	expect(owner.snapshot.get("own_postcards",[])==["toucheng","yingge"] and guest.snapshot.get("own_postcards",[])==["maokong"],"Each client's collection is private and specific to its own travel")
	owner.perform("build",SITE,Cards.RACK)
	if not expect(await wait_for(func():return placed(guest).get("type")==Cards.RACK),"Guest receives the live placed rack"):return
	owner.perform(Cards.PUT,SITE,"toucheng")
	expect(await wait_for(func():return placed(guest).get(Cards.SLOTS,[])==["toucheng"]),"Visitor sees exactly the card chosen for display")
	var public_owner:Dictionary=guest.snapshot.get("players",{}).get(owner.own_id,{})
	var public_data:=JSON.stringify([public_owner,placed(guest)])
	expect(not public_owner.is_empty() and not public_data.contains(OWNER) and not public_data.contains("yingge"),"No raw player identity or unshown destination is leaked")
	var old:=notices.size()
	guest.perform(Cards.TAKE,SITE,"toucheng")
	expect(await wait_for(func():return notices.size()>old and not notices.back()) and placed(owner).get(Cards.SLOTS,[])==["toucheng"],"Visitor selection cannot change the owner's display")
	owner.perform(Cards.TAKE,SITE,"toucheng")
	expect(await wait_for(func():return placed(guest).get(Cards.SLOTS,[]).is_empty()) and owner.snapshot.get("own_postcards",[]).has("toucheng"),"Removing the shared display card preserves the owner's private collection")
