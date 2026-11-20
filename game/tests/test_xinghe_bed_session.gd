extends "res://tests/network_egg_basket.gd"
## T066 N07-2 over a real loopback WebSocket: the four-cell bed plan of 星禾's 〈空花圃的圖紙〉.
## Owner reports a spring layout; only the in-season flower is spent; retransmits and repeats never charge twice;
## a second client sees no completion, no flower-rack unlock and no cookie unlock; the owner really cooks the
## garden cookie on the public stove; reconnect and a real host restart (durable reload) keep exact isolation.
const Goals=World.RESIDENT_GOALS
const Weather=preload("res://scripts/weather.gd")
const Stove=preload("res://scripts/kitchen_stove.gd")
const KIND:="kitchen_stove"
const COOKIE:="garden_cookie"
const RACK:="greenhouse_rack"
const PLAN:="bluebell_orange-0110"
const RACK_LOCK:="完成星禾的「空花圃的圖紙」或「冬天也開花」後解鎖。"
const STOVE_CELL:=Vector2i(41,33)
const STOVE_PART:=Vector2i(42,34)
const STOVE_STAND:=Vector2(43.5,34.5)
const BUILD_STAND:=Vector2(41.5,36.5)
const RACK_CELL:=Vector2i(46,36)
const RACK_STAND:=Vector2(46.5,37.5)
var hub:Session

func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp",".staged",".writer-lock",".corrupt"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("XINGHE_BED_SESSION checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func send_all()->void:
	for peer in hub.peers:hub._send_snapshot(peer)

func spring_clock()->float:
	for day in range(0,120):
		if Weather.season_on_day(day)=="spring":return float(day)*Weather.DAY_SECONDS+720.0
	return -1.0

func free_port()->int:
	var listener:=TCPServer.new()
	if listener.listen(0,"127.0.0.1")!=OK:return 0
	var port:=listener.get_local_port()
	listener.stop()
	return port

func person(token:String)->Dictionary:
	return hub.world.state.players[token]

func held(token:String)->Dictionary:
	return person(token).inventory.duplicate(true)

func own_bag(session:Session)->Dictionary:
	return session.snapshot.get("players",{}).get(session.own_id,{}).get("inventory",{})

func same_bag(before:Dictionary,after:Dictionary,spent:Dictionary)->bool:
	var keys:Dictionary={}
	for key in before:keys[key]=true
	for key in after:keys[key]=true
	for key in spent:keys[key]=true
	for key in keys:
		var expected:=int(before.get(key,0))-int(spent.get(key,0))
		var got:=int(after.get(key,0))
		if str(key).begins_with("keepsake"):
			if got<expected:return false
		elif got!=expected:return false
	return true

func xinghe_cell()->Vector2i:
	return World.bond_place(hub.world.state,"xinghe")[1]

func xinghe_region()->String:
	return str(World.bond_place(hub.world.state,"xinghe")[0])

func place(session:Session,token:String,region:String,at:Vector2)->bool:
	var p:Dictionary=person(token)
	p.region=region
	p.x=at.x
	p.y=at.y
	send_all()
	return await wait_for(func():return str(session.snapshot.get("region_id","home"))==region)

func to_xinghe(session:Session,token:String)->bool:
	var cell:=xinghe_cell()
	return await place(session,token,xinghe_region(),Vector2(cell.x+0.5,cell.y+0.5))

func to_home(session:Session,token:String,at:Vector2)->bool:
	return await place(session,token,str(World.REGIONS.HOME),at)

func report_extra(choice:String)->String:
	return "xinghe:2:%s:"%choice

func last_message(session:Session)->String:
	return str(notices[session].back().message)

func goal_entry(session:Session)->Dictionary:
	return session.snapshot.get("resident_goals",{}).get("xinghe",{}).get("2",{})

func stove_locked(session:Session)->bool:
	return World.stove_dish_locked_in(session.snapshot,KIND,COOKIE)

func quiet(session:Session,frames:int=30)->void:
	for _i in frames:await process_frame

## A clean cell-for-cell reading of the layout string: "0" = first flower, "1" = second flower of the pair.
func cells_of(choice:String)->Array:
	var out:Array=[]
	var flowers:=["bluebell","orange_blossom"]
	for letter in Goals.choice_layout(choice):out.append(flowers[int(letter)])
	return out

func run()->void:
	path=OS.get_environment("TEMP").path_join("xinghe-bed-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var clock:=spring_clock()
	if not check(clock>=0.0,"Calendar has a spring"):return
	# ------------------------------------------------------------------ fixture
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	fixture.state.board=true
	fixture.state.time=clock
	for x in range(38,51):
		for y in range(32,41):fixture.state.removed[World.key(Vector2i(x,y))]=true
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"星禾花圃")
		var person_data:Dictionary=fixture.state.players[token]
		person_data.bonds={"xinghe":{"points":6,"talk_day":-1,"gift_day":-1}}
		var stories:Dictionary=person_data.get("stories",{})
		stories["aru"]=maxi(2,int(stories.get("aru",0)))
		person_data["stories"]=stories
		person_data.inventory.merge({"stone":40,"wood":40,"clay":10,"plank":8,"fiber":6,"flour":3,"sugar":3,"chime_herb":3,"bluebell":2,"orange_blossom":2},true)
		person_data.x=BUILD_STAND.x
		person_data.y=BUILD_STAND.y
	var built:=fixture.act(GROWER,"xinghe-bed-stove","build",STOVE_CELL,KIND)
	if not check(bool(built.ok),"Fixture: public kitchen stove built by the real action: %s"%str(built.get("message",""))):return
	if not check(fixture.save(),"Save the room fixture"):return
	# ------------------------------------------------------------------ host + clients
	var port:=free_port()
	if not check(port>0,"Allocate a loopback port"):return
	hub=make_session("BedHost","bed-host")
	if not check(hub.host(port,"花圃",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a real WS dedicated host"):return
	hub.set_physics_process(false)
	var grower:=make_session("BedOwner",GROWER)
	var guest:=make_session("BedGuest",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(grower.join(address,port,"排花圃的人",ROOM)==OK and guest.join(address,port,"旁觀者",ROOM)==OK,"Join two independent clients"):return
	if not check(await wait_for(func():return not grower.own_id.is_empty() and not guest.own_id.is_empty()),"Both enter"):return
	var state:Dictionary=hub.world.state
	if not check(Goals.flower_in_season("bluebell",state) and not Goals.flower_in_season("orange_blossom",state) and Weather.season_on_day(Weather.day_index(float(state.time)))=="spring","Host clock is spring: bluebell grows, orange blossom does not"):return
	if not check(state.objects.get(World.key(STOVE_CELL),{}).get("type","")==KIND,"The saved public stove is on the host"):return
	# ------------------------------------------------------------------ before the report
	if not check(await to_xinghe(grower,GROWER) and await to_xinghe(guest,FRIEND),"Both clients stand next to 星禾"):return
	if not check(goal_entry(grower).get("state","")=="open" and goal_entry(guest).get("state","")=="open","Both start with the event open and empty"):return
	if not check(stove_locked(grower) and stove_locked(guest),"Cookie is locked for both before the plan"):return
	if not check(not Goals.flower_rack_unlocked(person(GROWER)) and not Goals.flower_rack_unlocked(person(FRIEND)),"Rack is locked for both on the host"):return
	# ------------------------------------------------------------------ refusals keep the bag
	var cell:=xinghe_cell()
	var start:=held(GROWER)
	for bad in ["bluebell_orange-0001","bluebell_orange-0111","bluebell_orange-01","bluebell_orange-0110-0","nope-0110"]:
		if not check(not await action(grower,Goals.ACTION,cell,report_extra(bad)),"Malformed plan refused over WS: "+bad):return
	if not check(same_bag(start,held(GROWER),{}) and Goals.done(person(GROWER),"xinghe").is_empty(),"Malformed plans changed neither bag nor record"):return
	person(GROWER).inventory.bluebell=1
	send_all()
	if not check(not await action(grower,Goals.ACTION,cell,report_extra(PLAN)) and "鈴蘭藍花" in last_message(grower),"One in-season bluebell is not enough: %s"%last_message(grower)):return
	if not check(int(person(GROWER).inventory.bluebell)==1 and int(person(GROWER).inventory.orange_blossom)==2 and Goals.done(person(GROWER),"xinghe").is_empty(),"Short refusal keeps the bag exactly"):return
	person(GROWER).inventory.bluebell=2
	send_all()
	if not check(await wait_for(func():return int(own_bag(grower).get("bluebell",0))==2),"Owner sees the restored bag"):return
	# Locked rack control: even with planks and fibre the owner is refused before the plan.
	if not check(await to_home(grower,GROWER,RACK_STAND),"Owner walks to the rack site"):return
	var rack_before:=held(GROWER)
	if not check(not await action(grower,"build",RACK_CELL,RACK) and last_message(grower)==RACK_LOCK and same_bag(rack_before,held(GROWER),{}),"Owner cannot build the rack before the plan: %s"%last_message(grower)):return
	if not check(await to_xinghe(grower,GROWER),"Owner returns to 星禾"):return
	cell=xinghe_cell()
	# ------------------------------------------------------------------ the spring plan
	var before:=held(GROWER)
	var guest_before:=held(FRIEND)
	if not check(await action(grower,Goals.ACTION,cell,report_extra(PLAN)),"Owner reports the spring four-cell plan: %s"%last_message(grower)):return
	var report_message:=last_message(grower)
	var sent:=grower.counter
	if not check("教學苗" in report_message,"The message names the tutorial seedlings: %s"%report_message):return
	if not check(Goals.done(person(GROWER),"xinghe").get(2,"")==PLAN and Goals.valid(person(GROWER).get(Goals.RECORD_KEY),person(GROWER)),"Host records the exact layout and the record validates"):return
	if not check(same_bag(before,held(GROWER),{"bluebell":2}) and int(person(GROWER).inventory.orange_blossom)==2,"Only the in-season bluebell x2 is spent; orange blossom x2 is kept"):return
	if not check(await wait_for(func():return goal_entry(grower).get("choice","")==PLAN),"Owner receives the exact layout in the private view"):return
	if not check(goal_entry(grower).get("state","")=="done" and Goals.choice_layout(goal_entry(grower).choice)=="0110",
		"Owner view is done with layout 0110"):return
	if not check(cells_of(str(goal_entry(grower).choice))==["bluebell","orange_blossom","orange_blossom","bluebell"],"Four cells decode to bluebell, orange, orange, bluebell"):return
	if not check(await wait_for(func():return int(own_bag(grower).get("bluebell",-1))==0 and int(own_bag(grower).get("orange_blossom",-1))==2),"Owner snapshot bag matches the host"):return
	if not check(not stove_locked(grower),"Owner snapshot unlocks the cookie"):return
	# ------------------------------------------------------------------ retransmit and repeat
	var settled:=held(GROWER)
	var notice_count:int=notices[grower].size()
	var region:=str(grower.snapshot.get("region_id","home"))
	var epoch:=int(grower.snapshot.get("players",{}).get(grower.own_id,{}).get("travel_epoch",0))
	grower.request_action.rpc_id(1,sent,Goals.ACTION,cell,report_extra(PLAN),region,epoch)
	await quiet(grower,40)
	if not check(notices[grower].size()==notice_count and same_bag(settled,held(GROWER),{}),"Same-sequence retransmit is dropped: no notice, no second deduction"):return
	if not check(not await action(grower,Goals.ACTION,cell,report_extra(PLAN)) and same_bag(settled,held(GROWER),{}),"A fresh repeat of the same layout is refused with no second deduction"):return
	if not check(not await action(grower,Goals.ACTION,cell,report_extra("bluebell_orange-1001")) and not await action(grower,Goals.ACTION,cell,report_extra("bluebell_chime-0011")) and same_bag(settled,held(GROWER),{}),"A different layout or option is refused too, bag unchanged"):return
	if not check(Goals.done(person(GROWER),"xinghe").get(2,"")==PLAN and Goals.done(person(GROWER),"xinghe").size()==1,"The first layout stays the only record"):return
	# ------------------------------------------------------------------ guest isolation
	send_all()
	await quiet(guest)
	if not check(goal_entry(guest).get("state","")=="open" and str(goal_entry(guest).get("choice",""))=="","Guest private view stays open with no choice"):return
	if not check(stove_locked(guest),"Guest snapshot keeps the cookie locked"):return
	var peer_view:Dictionary=guest.snapshot.get("players",{}).get(grower.own_id,{})
	if not check(not peer_view.has(Goals.RECORD_KEY) and not peer_view.has("greenhouse_reported"),"Guest receives no goal record on the owner's public player entry"):return
	if not check(not var_to_str(guest.snapshot).contains(PLAN),"The owner's layout string appears nowhere in the guest's snapshot"):return
	if not check(Goals.done(person(FRIEND),"xinghe").is_empty() and same_bag(guest_before,held(FRIEND),{}),"Host: guest has no record and an untouched bag"):return
	if not check(not Goals.flower_rack_unlocked(person(FRIEND)) and Goals.flower_rack_unlocked(person(GROWER)),"Host: rack unlock belongs to the owner only"):return
	if not check(await to_home(guest,FRIEND,RACK_STAND),"Guest walks to the rack site"):return
	guest_before=held(FRIEND)
	if not check(not await action(guest,"build",RACK_CELL,RACK) and last_message(guest)==RACK_LOCK and same_bag(guest_before,held(FRIEND),{}) and not state.objects.has(World.key(RACK_CELL)),"Guest cannot build the rack: %s"%last_message(guest)):return
	if not check(await to_home(guest,FRIEND,STOVE_STAND),"Guest walks to the stove"):return
	if not check(not await action(guest,"queue_cook",STOVE_PART,COOKIE) and last_message(guest)==Stove.EVENT_GATES[COOKIE].message and same_bag(guest_before,held(FRIEND),{}),"Guest cannot queue the cookie: %s"%last_message(guest)):return
	if not check(not state.objects[World.key(STOVE_CELL)].has("cooking"),"Guest refusal left the stove queue empty"):return
	# ------------------------------------------------------------------ owner builds the rack and cooks the cookie
	# The rapid retransmit checks above use most of the normal one-second input budget.
	await create_timer(1.05).timeout
	if not check(await to_home(grower,GROWER,RACK_STAND),"Owner walks to the rack site"):return
	var rack_start:=held(GROWER)
	if not check(await action(grower,"build",RACK_CELL,RACK),"Owner builds the unlocked rack: %s"%last_message(grower)):return
	if not check(same_bag(rack_start,held(GROWER),{"plank":4,"fiber":2}) and state.objects.get(World.key(RACK_CELL),{}).get("type","")==RACK,"Rack costs exactly 4 planks and 2 fibre and stands on the host"):return
	if not check(await to_home(grower,GROWER,STOVE_STAND),"Owner walks to the stove"):return
	var cook_start:=held(GROWER)
	if not check(await action(grower,"queue_cook",STOVE_PART,COOKIE),"Owner queues the garden cookie on the real stove: %s"%last_message(grower)):return
	if not check(same_bag(cook_start,held(GROWER),{"flour":1,"sugar":1,"chime_herb":1}),"Cookie takes exactly 1 flour, 1 sugar, 1 herb"):return
	var job:Dictionary=state.objects[World.key(STOVE_CELL)].get("cooking",{}).get("active",{})
	if not check(not job.is_empty() and job.kind==COOKIE and int(job["yield"])==4,"The stove runs one four-portion garden cookie job"):return
	if not check(not await action(guest,"queue_cook",STOVE_PART,COOKIE) and last_message(guest)==Stove.EVENT_GATES[COOKIE].message,"Guest is still refused while the owner's job runs"):return
	if not check(hub.world.step(95.0,true),"Advance authoritative time past the cooking job"):return
	send_all()
	var claim_start:=held(GROWER)
	if not check(await action(grower,"claim_cook",STOVE_PART),"Owner claims the cookies: %s"%last_message(grower)):return
	if not check(same_bag(claim_start,held(GROWER),{"garden_cookie":-4}),"Claim adds exactly four garden cookies"):return
	if not check(await wait_for(func():return int(own_bag(grower).get(COOKIE,0))==4),"Owner snapshot shows four cookies"):return
	if not check(int(person(FRIEND).inventory.get(COOKIE,0))==0 and int(own_bag(guest).get(COOKIE,0))==0,"Guest holds no cookie"):return
	# ------------------------------------------------------------------ reconnect
	grower.shutdown()
	if not check(await wait_for(func():return hub.peers.size()==1),"Host sees the owner leave"):return
	var returned:=make_session("BedReturned",GROWER)
	if not check(returned.join(address,port,"回來的人",ROOM)==OK,"Reconnect the owner profile"):return
	if not check(await wait_for(func():return not returned.own_id.is_empty() and goal_entry(returned).get("choice","")==PLAN),"Reconnect restores the exact layout"):return
	if not check(not stove_locked(returned) and stove_locked(guest) and int(own_bag(returned).get(COOKIE,0))==4,"Reconnected owner keeps the cookie unlock and cookies; guest does not"):return
	if not check(await to_xinghe(returned,GROWER),"Returned owner stands next to 星禾"):return
	var again:=held(GROWER)
	if not check(not await action(returned,Goals.ACTION,xinghe_cell(),report_extra(PLAN)) and same_bag(again,held(GROWER),{}),"After reconnect the same plan is refused with no deduction"):return
	send_all()
	await quiet(guest)
	if not check(goal_entry(guest).get("state","")=="open" and not var_to_str(guest.snapshot).contains(PLAN),"Guest still sees nothing after the owner reconnects"):return
	# ------------------------------------------------------------------ durable reload
	if not check(hub.world.save(),"Host saves the room"):return
	var loaded:=World.new()
	if not check(loaded.load_world(path),"The save loads in a fresh World"):return
	var saved_owner:Dictionary=loaded.state.players[GROWER]
	var saved_guest:Dictionary=loaded.state.players[FRIEND]
	if not check(Goals.done(saved_owner,"xinghe").get(2,"")==PLAN and Goals.valid(saved_owner.get(Goals.RECORD_KEY),saved_owner),"Saved owner keeps the exact layout"):return
	if not check(Goals.flower_rack_unlocked(saved_owner) and not loaded.stove_dish_locked(saved_owner,KIND,COOKIE),"Saved owner keeps the rack and cookie unlock"):return
	if not check(Goals.done(saved_guest,"xinghe").is_empty() and not Goals.flower_rack_unlocked(saved_guest) and loaded.stove_dish_locked(saved_guest,KIND,COOKIE),"Saved guest has none of them"):return
	if not check(int(saved_owner.inventory.get("bluebell",0))==0 and int(saved_owner.inventory.get("orange_blossom",0))==2 and int(saved_owner.inventory.get(COOKIE,0))==4,"Saved bag: no bluebell, 2 orange blossom, 4 cookies"):return
	if not check(int(saved_guest.inventory.get("bluebell",0))==2 and int(saved_guest.inventory.get("orange_blossom",0))==2 and int(saved_guest.inventory.get(COOKIE,0))==0,"Saved guest bag is untouched"):return
	if not check(loaded.state.objects.get(World.key(RACK_CELL),{}).get("type","")==RACK,"The built rack is in the save"):return
	# Real restart: every session closes, a new dedicated host loads the same file on a new port.
	for session in [returned,guest]:
		if not session.shutting_down:session.shutdown()
	hub.shutdown()
	await quiet(hub,20)
	var port2:=free_port()
	if not check(port2>0,"Allocate a second loopback port"):return
	hub=make_session("BedHostTwo","bed-host-two")
	if not check(hub.host(port2,"花圃",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Restart the dedicated host from the save"):return
	hub.set_physics_process(false)
	var address2:="ws://127.0.0.1:%d"%port2
	var owner_two:=make_session("BedOwnerTwo",GROWER)
	var guest_two:=make_session("BedGuestTwo",FRIEND)
	if not check(owner_two.join(address2,port2,"重開後的人",ROOM)==OK and guest_two.join(address2,port2,"重開後的旁觀者",ROOM)==OK,"Both clients join the restarted host"):return
	if not check(await wait_for(func():return not owner_two.own_id.is_empty() and not guest_two.own_id.is_empty() and goal_entry(owner_two).get("choice","")==PLAN),"Restarted owner sees the exact layout"):return
	if not check(goal_entry(owner_two).get("state","")=="done" and not stove_locked(owner_two) and int(own_bag(owner_two).get(COOKIE,0))==4,"Restarted owner keeps unlock and cookies"):return
	if not check(goal_entry(guest_two).get("state","")=="open" and str(goal_entry(guest_two).get("choice",""))=="" and stove_locked(guest_two),"Restarted guest is still locked and empty"):return
	if not check(not var_to_str(guest_two.snapshot).contains(PLAN),"Restarted guest snapshot has no trace of the layout"):return
	if not check(Goals.flower_rack_unlocked(person(GROWER)) and not Goals.flower_rack_unlocked(person(FRIEND)),"Restarted host: rack unlock is still the owner's alone"):return
	var restart_bag:=held(GROWER)
	if not check(await to_xinghe(owner_two,GROWER) and not await action(owner_two,Goals.ACTION,xinghe_cell(),report_extra(PLAN)) and same_bag(restart_bag,held(GROWER),{}),"After restart a repeat is refused with no deduction"):return
	finish(0)
