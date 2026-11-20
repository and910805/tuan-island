extends SceneTree

const FUTURE_WORDS:="私人回憶測試：給未來的自己，記得回渡口看老樹，去碼頭等船時也記得帶上那封信:這個標點要留下。"
## Luoluo's address letter (luoluo_address) over a real dedicated server Session and
## real loopback WebSocket clients, each client in its own SceneMultiplayer branch.
##
## Real actions only: luoluo_address take / deliver and the resident_goal luoluo 1
## completion go through Session.perform -> RPC -> World.act. Clients read only their
## own received snapshots.
## DISCLOSED DIRECT WRITES: (1) the seeded save (picnic, bond points, and for the
## third "legacy" player a luoluo 1 record with NO luoluo_address key, as an old save
## would hold it); (2) live server positions are written to stand next to a resident
## (cells are read from the live server world at every step). The server World is
## otherwise only READ, plus the on-disk save after shutdown.
## NOT covered: multiple processes, TLS, packet loss, crash durability.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Goals=World.RESIDENT_GOALS
const ROOM:="luoluo-address-loopback"
const ALPHA:="luoluo-address-alpha-token-41c9"
const BETA:="luoluo-address-beta-token-77de"
const LEGACY:="luoluo-address-legacy-token-9a02"
const MSG_FAR:="靠近一點，才能和它互動"
const MSG_NO_LETTER:="目前沒有待送的信。"
const MSG_TAKE_HERE:="請在洛洛身邊領取待送的信。"
const MSG_WALK:="要走到收件人身邊才能送信。"
const BOND:={"points":6,"talk_day":-1,"gift_day":-1}

var checks:=0
var failures:=0
var finished:=false
var path:=""
var host:Session
var alpha:Session
var beta:Session
var legacy:Session
var again:Session
var host_two:Session
var log_alpha:Array=[]
var log_beta:Array=[]
var log_legacy:Array=[]
var serial:=0

func _initialize()->void:
	create_timer(90.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("LUOLUO_ADDRESS_SESSION watchdog fired before completion")
	print("LUOLUO_ADDRESS_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func session_at(prefix:String)->Session:
	serial+=1
	var branch:=Node.new()
	branch.name="%s%d"%[prefix,serial]
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(),branch.get_path())
	var session:=Session.new()
	branch.add_child(session)
	return session

func wait_for(condition:Callable,seconds:float=5.0)->bool:
	var until:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<until:
		if condition.call():return true
		await process_frame
	return condition.call()

func pause(seconds:float)->void:
	await create_timer(seconds,true,false,true).timeout

func start_host(prefix:String)->Array:
	var server:=session_at(prefix)
	for attempt in 8:
		var trial:=randi_range(31000,58000)
		if server.host(trial,"",path,ROOM,"127.0.0.1",true,"websocket")==OK:return [server,trial]
	return [server,0]

func connect_client(token:String,name:String,port:int,log:Array)->Session:
	var client:=session_at("Client")
	client.profile.token=token
	client.notice.connect(func(message:String,ok:bool):log.append([message,ok]))
	client.join("ws://127.0.0.1:%d"%port,port,name,ROOM)
	await wait_for(func():return not client.own_id.is_empty() and client.snapshot.has("own_luoluo_address"),8.0)
	return client

# ---------------------------------------------------------------- helpers --

func live(token:String)->Dictionary:
	return host.world.state.players[token]

func post()->Vector2i:
	return World.RESIDENT_BOND.post_cell(host.world.state)

func home(id:String)->Vector2i:
	return World.Village.resident_cell(host.world.state,id)

func stand(token:String,cell:Vector2i)->void:
	var player:Dictionary=live(token)
	player.x=float(cell.x)+0.5
	player.y=float(cell.y)+0.5

func apart(a:Vector2i,b:Vector2i)->float:
	return Vector2(a).distance_to(Vector2(b))

func own(c:Session)->int:
	return int(c.snapshot.get("own_luoluo_address",-1))

func saved(token:String)->int:
	return int(live(token).get(Goals.ADDRESS_KEY,0))

func goal_state(c:Session)->String:
	var all:Variant=c.snapshot.get("resident_goals",{})
	if not all is Dictionary:return ""
	var rows:Variant=all.get("luoluo",{})
	if not rows is Dictionary:return ""
	var row:Variant=rows.get("1",{})
	return str(row.get("state","")) if row is Dictionary else ""

func seen(c:Session,value:int)->bool:
	return await wait_for(func():return own(c)==value)

func act(c:Session,log:Array,action:String,cell:Vector2i,extra:String="")->Dictionary:
	var before:=log.size()
	c.perform(action,cell,extra)
	if not await wait_for(func():return log.size()>before):
		return {"replied":false,"ok":false,"message":"<no reply>"}
	return {"replied":true,"ok":bool(log[before][1]),"message":str(log[before][0])}

func refuse(c:Session,log:Array,token:String,cell:Vector2i,extra:String,message:String,label:String,action:String=Goals.ADDRESS_ACTION)->void:
	var before:=saved(token)
	var shown:=own(c)
	var rows:=goal_state(c)
	var r:Dictionary=await act(c,log,action,cell,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await pause(0.2)
	expect(saved(token)==before and own(c)==shown and goal_state(c)==rows,"%s: letter stage and goal row unchanged"%label)

func private_check(c:Session,others:Array,tokens:Array,label:String)->void:
	var people:Variant=c.snapshot.get("players",{})
	for other:Session in others:
		var them:Variant=people.get(other.own_id,null) if people is Dictionary else null
		expect(them is Dictionary and not them.has(Goals.ADDRESS_KEY) and not them.has("own_luoluo_address"),"%s: another player's public entry has no letter state"%label)
	var mine:Variant=people.get(c.own_id,{}) if people is Dictionary else {}
	expect(mine is Dictionary and not mine.has(Goals.ADDRESS_KEY),"%s: own public entry carries no raw luoluo_address either"%label)
	var dump:=JSON.stringify(c.snapshot)
	expect(not dump.contains("\"%s\":"%Goals.ADDRESS_KEY),"%s: snapshot never carries a raw luoluo_address key"%label)
	expect(dump.count("\"own_luoluo_address\":")==1,"%s: exactly one own_luoluo_address (its own)"%label)
	var leaked:=false
	for token:String in tokens:
		if dump.contains(token):leaked=true
	expect(not leaked,"%s: snapshot contains no private token"%label)

# --------------------------------------------------------------- scenario --

func run()->void:
	path="user://luoluo-address-session-%d.json"%Time.get_ticks_usec()
	await scenario()
	for session:Session in [again,legacy,beta,alpha]:
		if session!=null and is_instance_valid(session) and not session.shutting_down:session.shutdown()
	for server:Session in [host_two,host]:
		if server!=null and is_instance_valid(server) and not server.shutting_down:server.shutdown()
	await process_frame
	for suffix:String in ["",".bak",".tmp",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	if finished:return
	finished=true
	print("LUOLUO_ADDRESS_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

func scenario()->void:
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state["picnic"]=true
	for pair:Array in [[ALPHA,"甲"],[BETA,"乙"],[LEGACY,"舊檔"]]:
		fixture.add_player(str(pair[0]),str(pair[1]))
		fixture.state.players[pair[0]].bonds={"luoluo":BOND.duplicate()}
	# Legacy save: luoluo 1 recorded as done, no luoluo_address key at all.
	fixture.state.players[LEGACY].bond_goals={"luoluo":{"1":""}}
	if not expect(fixture.save(),"Save seeded fixture"):return
	var started:Array=start_host("Server")
	host=started[0]
	var port:int=started[1]
	if not expect(port>0,"Host a real WebSocket endpoint"):return
	alpha=await connect_client(ALPHA,"甲",port,log_alpha)
	beta=await connect_client(BETA,"乙",port,log_beta)
	legacy=await connect_client(LEGACY,"舊檔",port,log_legacy)
	if not expect(not alpha.own_id.is_empty() and not beta.own_id.is_empty() and not legacy.own_id.is_empty(),"Three real clients received their own snapshots"):return
	expect(host.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and beta.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,"Server and clients use WebSocketMultiplayerPeer")
	expect(alpha.world==null and beta.world==null and legacy.world==null,"Client Sessions hold no World")
	var tokens:Array=[ALPHA,BETA,LEGACY]
	var aru:=home("aru")
	var milu:=home("milu")
	var xiaoli:=home("xiaoli")
	var luoluo:=post()
	expect(apart(aru,milu)>3.2 and apart(aru,luoluo)>3.2 and milu!=luoluo,"The trial has distinct locations and positions outside interaction range")
	expect(own(alpha)==0 and own(beta)==0 and goal_state(alpha)=="open" and goal_state(beta)=="open","Fresh clients start with no letter and an open luoluo 1")

	# Legacy completed: done luoluo 1 without the key reads as delivered, no new letter.
	expect(await seen(legacy,Goals.ADDRESS_DELIVERED) and goal_state(legacy)=="done","Legacy completed player's own snapshot reads delivered and done")
	stand(LEGACY,luoluo)
	await refuse(legacy,log_legacy,LEGACY,luoluo,"take",MSG_TAKE_HERE,"Legacy player cannot take a second letter")
	expect(not live(LEGACY).has(Goals.ADDRESS_KEY),"Legacy save is not rewritten with a letter key")

	# Nothing to deliver yet.
	stand(BETA,aru)
	await refuse(beta,log_beta,BETA,aru,"aru",MSG_NO_LETTER,"Deliver before taking a letter")

	# Take: outside distance, then independent takes.
	stand(ALPHA,aru)
	await refuse(alpha,log_alpha,ALPHA,luoluo,"take",MSG_FAR,"Take from outside reach")
	stand(ALPHA,luoluo)
	var r:Dictionary=await act(alpha,log_alpha,Goals.ADDRESS_ACTION,luoluo,"take")
	expect(r.ok and await seen(alpha,Goals.ADDRESS_CARRIED) and saved(ALPHA)==Goals.ADDRESS_CARRIED,"Alpha takes the letter")
	await pause(0.3)
	expect(own(beta)==0 and saved(BETA)==0,"Alpha's letter does not touch beta")
	await refuse(alpha,log_alpha,ALPHA,luoluo,"take",MSG_TAKE_HERE,"Alpha cannot take a second letter")
	await refuse(alpha,log_alpha,ALPHA,luoluo,"luoluo:1::","還不能一起做這件事：要先「%s」。"%str(Goals.NEEDS.address_delivered),"Report before delivering","resident_goal")
	stand(BETA,luoluo)
	r=await act(beta,log_beta,Goals.ADDRESS_ACTION,luoluo,"take")
	expect(r.ok and await seen(beta,Goals.ADDRESS_CARRIED) and own(alpha)==Goals.ADDRESS_CARRIED,"Beta takes their own letter independently")

	# Wrong candidates, wrong places, then the right one after moving.
	stand(ALPHA,milu)
	await refuse(alpha,log_alpha,ALPHA,milu,"milu","%s說這封不是自己的，信仍由你保管。"%World.RESIDENT_BOND.name_of("milu"),"Wrong candidate milu")
	await refuse(alpha,log_alpha,ALPHA,milu,"aru",MSG_WALK,"Right name at the wrong resident's cell")
	await refuse(alpha,log_alpha,ALPHA,aru,"aru",MSG_FAR,"Right recipient but out of reach")
	await refuse(alpha,log_alpha,ALPHA,xiaoli,"xiaoli",MSG_FAR if apart(xiaoli,milu)>4.0 else "%s說這封不是自己的，信仍由你保管。"%World.RESIDENT_BOND.name_of("xiaoli"),"Other candidate xiaoli from milu's side")
	expect(own(alpha)==Goals.ADDRESS_CARRIED and own(beta)==Goals.ADDRESS_CARRIED,"Refused deliveries keep both letters")

	# Beta delivers first; alpha's letter is untouched.
	stand(BETA,aru)
	r=await act(beta,log_beta,Goals.ADDRESS_ACTION,aru,"aru")
	expect(r.ok and await seen(beta,Goals.ADDRESS_DELIVERED) and saved(BETA)==Goals.ADDRESS_DELIVERED,"Beta delivers to the right recipient")
	await pause(0.3)
	expect(own(alpha)==Goals.ADDRESS_CARRIED and saved(ALPHA)==Goals.ADDRESS_CARRIED and goal_state(alpha)=="open","Beta's delivery leaves alpha still carrying")

	# Alpha moves to the recipient and delivers.
	stand(ALPHA,aru)
	r=await act(alpha,log_alpha,Goals.ADDRESS_ACTION,aru,"aru")
	expect(r.ok and await seen(alpha,Goals.ADDRESS_DELIVERED) and saved(ALPHA)==Goals.ADDRESS_DELIVERED,"Alpha delivers after moving to the recipient")
	await refuse(alpha,log_alpha,ALPHA,aru,"aru",MSG_NO_LETTER,"Cannot deliver twice")

	# Completion over the network.
	stand(ALPHA,luoluo)
	r=await act(alpha,log_alpha,Goals.ACTION,luoluo,"luoluo:1::")
	expect(r.ok and await wait_for(func():return goal_state(alpha)=="done"),"Alpha completes luoluo 1 after delivering (%s)"%str(r.message))
	expect(Goals.done(live(ALPHA),"luoluo").has(1) and goal_state(beta)!="done","Alpha's completion is recorded for alpha only")
	stand(BETA,luoluo)
	r=await act(beta,log_beta,Goals.ACTION,luoluo,"luoluo:1::")
	expect(r.ok and await wait_for(func():return goal_state(beta)=="done"),"Beta completes luoluo 1 independently (%s)"%str(r.message))
	expect(own(alpha)==Goals.ADDRESS_DELIVERED and own(beta)==Goals.ADDRESS_DELIVERED and own(legacy)==Goals.ADDRESS_DELIVERED,"All three players read delivered")
	await refuse(alpha,log_alpha,ALPHA,luoluo,"take",MSG_TAKE_HERE,"Completed player cannot take another letter")
	await postcard_interviews(luoluo,aru,milu,xiaoli)
	await memory_letters(luoluo,aru)
	await future_letters(luoluo)

	# Privacy.
	private_check(alpha,[beta,legacy],tokens,"alpha")
	private_check(beta,[alpha,legacy],tokens,"beta")
	private_check(legacy,[alpha,beta],tokens,"legacy")

	# Reload: save, load the file, then restart a server and rejoin.
	for session:Session in [legacy,beta,alpha]:
		session.shutdown()
	await process_frame
	expect(host.shutdown(),"Server shuts down and saves")
	await pause(0.3)
	var loaded:=World.new()
	if not expect(loaded.load_world(path),"Reload the saved island"):return
	for token:String in [ALPHA,BETA]:
		var record:Dictionary=loaded.state.players[token]
		expect(int(record.get(Goals.ADDRESS_KEY,0))==Goals.ADDRESS_DELIVERED and Goals.done(record,"luoluo").has(1),"Delivered letter and completion survive reload")
	var old:Dictionary=loaded.state.players[LEGACY]
	expect(not old.has(Goals.ADDRESS_KEY) and Goals.address_progress(old)==Goals.ADDRESS_DELIVERED,"Legacy completion still reads delivered after reload")
	expect(Goals.postcard_clues(loaded.state.players[ALPHA])==["milu","aru","xiaoli"] and Goals.done(loaded.state.players[ALPHA],"luoluo").has(2),"A finished interview and its order survive restart")
	expect(Goals.postcard_clues(loaded.state.players[BETA])==["aru"] and not Goals.done(loaded.state.players[BETA],"luoluo").has(2),"Someone else's partial notes survive separately")
	expect(Goals.done(loaded.state.players[ALPHA],"luoluo").get(3)=="aloud" and Goals.done(old,"luoluo").get(3)=="letter","Both choices survive restart under their own profiles")
	expect(Goals.future_note(loaded.state.players[ALPHA])==FUTURE_WORDS and Goals.done(old,"luoluo").get(4)=="blank","A personal letter and a skipped letter survive separately")
	var invalid:=loaded.state.duplicate(true)
	invalid.players[ALPHA][Goals.FUTURE_NOTE_KEY]="壞資料".repeat(41)
	expect(not World.SAVE_SCHEMA.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"An over-limit future letter invalidates a save")
	invalid.players[ALPHA].erase(Goals.FUTURE_NOTE_KEY)
	expect(not World.SAVE_SCHEMA.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"A write record must retain the message")
	var restarted:Array=start_host("ServerAgain")
	host_two=restarted[0]
	if not expect(int(restarted[1])>0,"Restart a WebSocket endpoint on the saved island"):return
	again=await connect_client(ALPHA,"甲",int(restarted[1]),[])
	expect(await seen(again,Goals.ADDRESS_DELIVERED) and goal_state(again)=="done","Rejoined client sees the delivered letter and finished goal")
	expect(again.snapshot.get("own_luoluo_postcard_clues",[])==["milu","aru","xiaoli"],"Rejoined client can read their own interviews")
	expect(again.snapshot.resident_goals.luoluo["3"].choice=="aloud","Only the client's own saved delivery is available")
	expect(again.snapshot.get("own_luoluo_future_note","")==FUTURE_WORDS and again.snapshot.players[again.own_id].get(Goals.COURIER_CAP_KEY,false),"The same world restores own writing and equipped hat")

func postcard_interviews(luoluo:Vector2i,aru:Vector2i,milu:Vector2i,xiaoli:Vector2i) -> void:
	for token:String in [ALPHA,BETA]:
		var person:=live(token)
		person.bonds.luoluo.points=6
		for resident:String in ["aru","milu","xiaoli"]:
			person.bonds[resident]={"points":1,"talk_day":-1,"gift_day":-1}
	stand(ALPHA,luoluo)
	var r:=await act(alpha,log_alpha,Goals.ACTION,luoluo,"luoluo:2::")
	expect(not r.ok,"Three acquaintances without interviews do not complete the event")
	stand(ALPHA,milu)
	r=await act(alpha,log_alpha,Goals.POSTCARD_CLUE_ACTION,milu,"aru")
	expect(not r.ok,"Client may not substitute a different resident at this site")
	r=await act(alpha,log_alpha,Goals.POSTCARD_CLUE_ACTION,aru,"aru")
	expect(not r.ok,"Client may not interview from outside interaction range")
	r=await act(alpha,log_alpha,Goals.POSTCARD_CLUE_ACTION,milu,"milu")
	expect(r.ok and await wait_for(func():return alpha.snapshot.get("own_luoluo_postcard_clues",[])==["milu"]),"First interview goes to the interviewing client")
	r=await act(alpha,log_alpha,Goals.POSTCARD_CLUE_ACTION,milu,"milu")
	expect(not r.ok and Goals.postcard_clues(live(ALPHA))==["milu"],"Replaying an interview does not add a clue")
	stand(BETA,aru)
	r=await act(beta,log_beta,Goals.POSTCARD_CLUE_ACTION,aru,"aru")
	expect(r.ok and await wait_for(func():return beta.snapshot.get("own_luoluo_postcard_clues",[])==["aru"]),"Second client records their own interview")
	expect(alpha.snapshot.own_luoluo_postcard_clues==["milu"],"The second client's interview stays private")
	for id:String in ["aru","xiaoli"]:
		var site:=aru if id=="aru" else xiaoli
		stand(ALPHA,site)
		r=await act(alpha,log_alpha,Goals.POSTCARD_CLUE_ACTION,site,id)
		expect(r.ok,"Record a clue from "+id)
	stand(ALPHA,luoluo)
	r=await act(alpha,log_alpha,Goals.ACTION,luoluo,"luoluo:2::")
	expect(r.ok and Goals.done(live(ALPHA),"luoluo").has(2) and not Goals.done(live(BETA),"luoluo").has(2),"The rack unlock belongs to the person who did the work")
	for session:Session in [alpha,beta,legacy]:
		for public_person:Dictionary in session.snapshot.get("players",{}).values():
			expect(not public_person.has(Goals.POSTCARD_CLUES_KEY),"No public player row leaks interview records")

func memory_letters(luoluo:Vector2i,aru:Vector2i) -> void:
	await pause(1.1)
	for token:String in [ALPHA,BETA,LEGACY]:
		live(token).bonds.luoluo.points=14
	live(LEGACY)[Goals.RECORD_KEY].luoluo["2"]="" # Older completed event without interview entries.
	stand(BETA,luoluo)
	var rejected:=await act(beta,log_beta,Goals.ACTION,luoluo,"luoluo:3:letter:")
	expect(not rejected.ok and rejected.message.contains(str(Goals.NEEDS.postcard_reported)) and not Goals.done(live(BETA),"luoluo").has(3),"The shared host requires this person's previous report")
	stand(ALPHA,aru)
	await refuse(alpha,log_alpha,ALPHA,luoluo,"luoluo:3:aloud:",MSG_FAR,"Memory letter completion checks distance",Goals.ACTION)
	var before:Dictionary=live(ALPHA).inventory.duplicate(true)
	var second_bag:Dictionary=live(LEGACY).inventory.duplicate(true)
	stand(ALPHA,luoluo)
	var spoken:=await act(alpha,log_alpha,Goals.ACTION,luoluo,"luoluo:3:aloud:")
	stand(LEGACY,luoluo)
	var written:=await act(legacy,log_legacy,Goals.ACTION,luoluo,"luoluo:3:letter:")
	expect(spoken.ok and written.ok and spoken.message==written.message,"Both choices grant the same result")
	expect(live(ALPHA).inventory==before and live(LEGACY).inventory==second_bag,"Both routes have the same zero material cost")
	expect(await wait_for(func():
		return alpha.snapshot.resident_goals.luoluo["3"].get("choice")=="aloud" and legacy.snapshot.resident_goals.luoluo["3"].get("choice")=="letter"),"Clients receive only the selected route for their own memory")
	expect(beta.snapshot.resident_goals.luoluo["3"].get("state")=="open" and beta.snapshot.resident_goals.luoluo["3"].get("choice")=="" and host.world.state.get("island_notes",[]).is_empty(),"Neither completion affects the other player or posts a public message")
	stand(ALPHA,luoluo)
	var duplicate:=await act(alpha,log_alpha,Goals.ACTION,luoluo,"luoluo:3:letter:")
	expect(not duplicate.ok and Goals.done(live(ALPHA),"luoluo").get(3)=="aloud","A repeated request cannot replace the saved route")

func future_letters(luoluo:Vector2i) -> void:
	await pause(1.1)
	for token:String in [ALPHA,BETA,LEGACY]:
		live(token).bonds.luoluo.points=24
	stand(BETA,luoluo)
	var r:=await act(beta,log_beta,Goals.ACTION,luoluo,"luoluo:4:blank:")
	expect(not r.ok and r.message.contains(str(Goals.NEEDS.memory_shared)),"The prior memory is required even when leaving a blank")
	r=await act(beta,log_beta,Goals.COURIER_CAP_ACTION,luoluo,"wear")
	expect(not r.ok,"A story-locked player cannot wear the cap")
	stand(ALPHA,luoluo)
	r=await act(alpha,log_alpha,Goals.ACTION,luoluo,Goals.FUTURE_PREFIX+"\n")
	expect(not r.ok and not live(ALPHA).has(Goals.FUTURE_NOTE_KEY),"Invalid text is refused before the event is written")
	expect(not Session.extra_allowed(Goals.ACTION,Goals.FUTURE_PREFIX+"字".repeat(121)),"Long wire payload allowance is bounded")
	r=await act(alpha,log_alpha,Goals.ACTION,luoluo,Goals.FUTURE_PREFIX+FUTURE_WORDS)
	expect(r.ok and await wait_for(func():return alpha.snapshot.get("own_luoluo_future_note","")==FUTURE_WORDS),"The full private message retains punctuation and passes the multiplayer length gate")
	stand(LEGACY,luoluo)
	r=await act(legacy,log_legacy,Goals.ACTION,luoluo,"luoluo:4:blank:")
	expect(r.ok and not live(LEGACY).has(Goals.FUTURE_NOTE_KEY) and int(live(ALPHA).inventory.get("keepsake_luoluo_kit",0))==int(live(LEGACY).inventory.get("keepsake_luoluo_kit",0)),"Blank and custom routes grant the same keepsake")
	r=await act(alpha,log_alpha,Goals.COURIER_CAP_ACTION,luoluo,"wear")
	expect(r.ok and await wait_for(func():return beta.snapshot.players.get(alpha.own_id,{}).get(Goals.COURIER_CAP_KEY,false)),"Other players can see the equipped cap")
	r=await act(legacy,log_legacy,Goals.COURIER_CAP_ACTION,luoluo,"wear")
	expect(r.ok,"Skipping the message also unlocks a wearable cap")
	live(ALPHA).bonds["mianmian"]={"points":24,"talk_day":-1,"gift_day":-1}
	live(ALPHA)[Goals.RECORD_KEY]["mianmian"]={"4":""} # Existing earned wool hat.
	r=await act(alpha,log_alpha,Goals.WOOL_HAT_ACTION,luoluo)
	expect(r.ok and live(ALPHA).get(Goals.WOOL_HAT_KEY,false) and not live(ALPHA).has(Goals.COURIER_CAP_KEY),"Equipping the wool hat switches headwear")
	r=await act(alpha,log_alpha,Goals.COURIER_CAP_ACTION,luoluo,"wear")
	expect(r.ok and not live(ALPHA).has(Goals.WOOL_HAT_KEY) and live(ALPHA).get(Goals.COURIER_CAP_KEY,false),"The two hats never stack")
	r=await act(alpha,log_alpha,Goals.ACTION,luoluo,Goals.FUTURE_PREFIX+"重送")
	expect(not r.ok and Goals.future_note(live(ALPHA))==FUTURE_WORDS,"Duplicate submission cannot overwrite a finished letter")
	for session:Session in [beta,legacy]:
		expect(session.snapshot.get("own_luoluo_future_note","").is_empty() and not JSON.stringify(session.snapshot).contains(FUTURE_WORDS),"Other players' snapshots cannot read Alpha's future message")
	for session:Session in [alpha,beta,legacy]:
		for public_person:Dictionary in session.snapshot.get("players",{}).values():
			expect(not public_person.has(Goals.FUTURE_NOTE_KEY),"Public player rows contain no private writing")
	expect(host.world.state.get("island_notes",[]).is_empty(),"Future messages do not enter the island board")
