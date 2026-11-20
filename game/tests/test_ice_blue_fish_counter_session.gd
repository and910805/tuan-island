extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const OWNER:="counter-ws-owner-qa"
const GUEST:="counter-ws-guest-qa"
const SITE:=Vector2i(40,34)
const ROOM:="ice-counter-loopback"
var checks:=0
var failures:=0
var server:Session
var owner:Session
var guest:Session
var guest_notices:Array[bool]=[]
var path:String

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
	return ok

func new_session(branch_name:String)->Session:
	var branch:=Node.new()
	branch.name=branch_name
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(),branch.get_path())
	var session:=Session.new()
	branch.add_child(session)
	return session

func wait_for(condition:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await process_frame
	return condition.call()

func displayed(session:Session)->Dictionary:
	return session.snapshot.get("objects",{}).get(World.key(SITE),{}).get("items",{})

func run()->void:
	path="user://fish-counter-ws-%d.json"%Time.get_ticks_usec()
	await scenario()
	for session:Session in [guest,owner,server]:
		if session!=null:session.shutdown()
	await process_frame
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("ICE_BLUE_FISH_COUNTER_SESSION checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func scenario()->void:
	var fixture:=World.new()
	fixture.save_path=path
	fixture.add_player(OWNER,"台主")
	fixture.add_player(GUEST,"訪客")
	var host:Dictionary=fixture.state.players[OWNER]
	host.x=40.5
	host.y=33.5
	host.inventory.merge({"wood":20,"stone":10,"sardine":1},true)
	var visitor:Dictionary=fixture.state.players[GUEST]
	visitor.x=41.5
	visitor.y=33.5
	if not expect(fixture.save(),"Save the isolated multiplayer fixture"):return
	server=new_session("CounterServer")
	var port:=0
	for attempt in 8:
		var trial:=randi_range(31000,58000)
		if server.host(trial,"",path,ROOM,"127.0.0.1",true,"websocket")==OK:
			port=trial
			break
	if not expect(port>0,"Start a real WebSocket server"):return
	owner=new_session("CounterOwner")
	guest=new_session("CounterGuest")
	owner.profile.token=OWNER
	guest.profile.token=GUEST
	guest.notice.connect(func(_text:String,ok:bool):guest_notices.append(ok))
	var address:="ws://127.0.0.1:%d"%port
	if not expect(owner.join(address,port,"台主",ROOM)==OK and guest.join(address,port,"訪客",ROOM)==OK,"Connect two clients via loopback"):return
	if not expect(await wait_for(func():return owner.own_id!="" and guest.own_id!=""),"Both clients receive their identities"):return
	owner.perform("build",SITE,Industry.COAST_FISH_COUNTER)
	if not expect(await wait_for(func():return guest.snapshot.get("objects",{}).get(World.key(SITE),{}).get("type")==Industry.COAST_FISH_COUNTER),"Guest receives the real counter build"):return
	owner.perform(Industry.COUNTER_PUT,SITE+Vector2i.RIGHT,"sardine")
	expect(await wait_for(func():return displayed(guest)=={"sardine":1} and displayed(owner)=={"sardine":1}),"Both clients see the same displayed fish")
	expect(not JSON.stringify(guest.snapshot.objects[World.key(SITE)]).contains(OWNER),"Shared object contains a public owner ID")
	var prior:=guest_notices.size()
	guest.perform(Industry.COUNTER_TAKE,SITE,"sardine")
	expect(await wait_for(func():return guest_notices.size()>prior and not guest_notices.back()),"Server rejects the visitor's take request")
	expect(displayed(guest)=={"sardine":1} and int(server.world.state.players[GUEST].inventory.get("sardine",0))==0,"Rejected withdrawal changes neither container nor bag")
	owner.perform(Industry.COUNTER_TAKE,SITE,"sardine")
	expect(await wait_for(func():return displayed(guest).is_empty() and int(owner.snapshot.get("players",{}).get(owner.own_id,{}).get("inventory",{}).get("sardine",0))==1),"Owner retrieves one fish and both clients see the empty counter")
