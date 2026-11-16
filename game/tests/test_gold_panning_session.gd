extends SceneTree
## 第 40 章金瓜石初訪「河邊淘砂金」two-client Session acceptance over a real dedicated server
## and real WebSocket clients (modelled on test_salt_brine_session.gd and
## test_jinguashi_revisit_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha, beta, both standing on the
## bank next to GoldPanning.SITE in 金瓜石) and later a late joiner (gamma, at home) join over
## loopback, each in its own branch with its own SceneMultiplayer. Clients only read their own
## received snapshots. The server World is never touched after seeding; the on-disk save is
## read (file only) after shutdowns. This is same-machine single-process evidence only.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and validated
## with SaveSchema. WRITTEN directly: alpha and beta are fresh players whose region is set to
## "jinguashi" and whose x/y are set to standable bank cells within GoldPanning.REACH of SITE
## (found with World.can_stand in the Jinguashi layer); receipts cleared. Nothing is EARNED
## offline: no gold_panning key is preset, nobody holds gold_ore, nobody travelled there.
## World time starts at 0 (day 1) and only advances by the server's real-time ticks; the test
## never advances it (all pans happen on day 1).
## PLAYED over the network: every gold_pan step (scoop / sift / swirl / pick) of alpha, beta and
## gamma, through Session.perform → request_action.
## Replay: the raw request_action RPC re-sent with an already-used sequence number (scoop and
## pick, with extras that WOULD succeed if processed); Session drops it.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns only),
## day rollover of the daily count, TOO_FAR / BAG_FULL (rule level, test_gold_panning.gd if any),
## travelling into or out of Jinguashi over the network.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const GP=preload("res://scripts/gold_panning.gd")
const KEY:="gold-panning-session"
const ALPHA:="goldpan-session-alpha-token"
const BETA:="goldpan-session-beta-token"
const GAMMA:="goldpan-session-gamma-token"
const ORE:="gold_ore"

class Client:
	var label:=""
	var token:=""
	var branch:Node
	var session
	var notices:Array=[]
	var changes:=0
	func on_notice(message:String,success:bool)->void:
		notices.append([message,success])
	func on_changed(_data:Dictionary,_id:String)->void:
		changes+=1
	func me()->Dictionary:
		var people=session.snapshot.get("players",{})
		if not people is Dictionary or session.own_id.is_empty():return {}
		return people.get(session.own_id,{})
	func bag()->Dictionary:
		var inv=me().get("inventory",{})
		return inv if inv is Dictionary else {}
	func own()->Variant:
		return session.snapshot.get(GP.OWN_KEY,null)
	func ore()->int:
		return int(bag().get(ORE,0))

var checks:=0
var failures:=0
var serial:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var alpha:Client
var beta:Client
var gamma:Client

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func _initialize()->void:
	create_timer(115.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("GOLD_PANNING_SESSION watchdog fired before completion")
	print("GOLD_PANNING_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("GOLD_PANNING_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("GOLD_PANNING_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("GOLD_PANNING_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func place(w:World,token:String,region:String,at:Vector2)->void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y

## Standable bank positions (cell centres) within reach of the panning site, nearest first.
func bank_spots(w:World)->Array:
	var centre:=Vector2(GP.SITE)+Vector2(0.5,0.5)
	var out:Array=[]
	w.switch_region(GP.REGION)
	for dy in range(-3,4):
		for dx in range(-3,4):
			var pos:=Vector2(GP.SITE.x+dx,GP.SITE.y+dy)+Vector2(0.5,0.5)
			var d:=pos.distance_to(centre)
			if d<0.9 or d>GP.REACH-0.4:continue
			if w.can_stand(pos):out.append(pos)
	w.switch_region("home")
	out.sort_custom(func(a:Vector2,b:Vector2):return a.distance_to(centre)<b.distance_to(centre))
	return out

func seed_world(path:String)->bool:
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	var spots:=bank_spots(w)
	if spots.size()<2:
		push_error("no two standable bank spots near the panning site: %s"%str(spots))
		return false
	place(w,ALPHA,GP.REGION,spots[0])
	place(w,BETA,GP.REGION,spots[1])
	for token in [ALPHA,BETA]:
		w.state.players[token]["receipts"]={}
		w.state.players[token].inventory.erase(ORE)
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.has(GP.STATE_KEY) or float(parsed.time)+300.0>=1440.0:return false
	return Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

# ------------------------------------------------------------- transport --

func new_branch(prefix:String)->Node:
	serial+=1
	var branch:=Node.new()
	branch.name="%s%d"%[prefix,serial]
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(),branch.get_path())
	return branch

func start_server()->int:
	server_branch=new_branch("Server")
	server=Session.new()
	server_branch.add_child(server)
	for attempt in 8:
		var port:=randi_range(31000,58000)
		if server.host(port,"",save_path,KEY,"127.0.0.1",true,"websocket")==OK:return port
	return 0

func stop_server()->bool:
	var ok:bool=server.shutdown()
	await pause(0.2)
	server_branch.queue_free()
	await process_frame
	return ok

func join(label:String,token:String,port:int)->Client:
	var c:=Client.new()
	c.label=label
	c.token=token
	c.branch=new_branch("Client_%s_"%label)
	c.session=Session.new()
	c.branch.add_child(c.session)
	c.session.profile["token"]=token
	c.session.notice.connect(c.on_notice)
	c.session.changed.connect(c.on_changed)
	if c.session.join("ws://127.0.0.1:%d"%port,port,label,KEY)!=OK:return c
	await wait_until(func():return joined(c),8.0)
	return c

func joined(c:Client)->bool:
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.get("salt_pan") is Dictionary

func leave(c:Client)->void:
	if c==null or not is_instance_valid(c.session):return
	if not c.session.shutting_down:c.session.shutdown()
	await process_frame
	c.branch.queue_free()

func wait_until(condition:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await process_frame
	return condition.call()

func pause(seconds:float)->void:
	await create_timer(seconds,true,false,true).timeout

func settle(clients:Array)->void:
	var marks:Array=clients.map(func(c):return c.changes)
	await wait_until(func():
		for i in clients.size():
			if clients[i].changes<int(marks[i])+2:return false
		return true,3.0)

func act(c:Client,action:String,p:Vector2i,extra:String="")->Dictionary:
	var before:=c.notices.size()
	var sequence:int=c.session.perform(action,p,extra)
	var replied:=await wait_until(func():return c.notices.size()>before,4.0)
	if not replied:return {"replied":false,"ok":false,"message":"","sequence":sequence}
	await settle([c])
	var reply:Array=c.notices[before]
	return {"replied":true,"ok":bool(reply[1]),"message":str(reply[0]),"sequence":sequence}

# ---------------------------------------------------------------- helpers --

static func canon(d:Variant)->Dictionary:
	var out:={}
	if not d is Dictionary:return {"<invalid>":-1}
	for item in d:
		if int(d[item])!=0:out[str(item)]=int(d[item])
	return out

static func text(d:Variant)->String:
	return JSON.stringify(d,"",true)

static func view(stage:int,count:int,total:int)->String:
	return text({"stage":stage,"count":count,"total":total})

func own_text(c:Client)->String:
	return text(c.own())

func region_of(c:Client)->String:
	return str(c.session.snapshot.get("region_id",""))

## Own panning view and the bag, as text.
func marks_of(clients:Array)->Array:
	return clients.map(func(x):return [text(x.own()),text(canon(x.bag()))])

## Every dictionary key anywhere in `v` whose name mentions "panning".
static func panning_keys(v:Variant,out:Array)->void:
	if v is Dictionary:
		for k in v:
			if str(k).contains("panning"):out.append(str(k))
			panning_keys(v[k],out)
	elif v is Array:
		for x in v:panning_keys(x,out)

func pan(c:Client,step:String)->Dictionary:
	return await act(c,GP.ACTION,GP.SITE,step)

func refuse(c:Client,step:String,p:Vector2i,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,GP.ACTION,p,step)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: own_gold_panning and bags unchanged in every watching snapshot"%label)

func succeed(c:Client,step:String,message:String,label:String,watchers:Array)->Dictionary:
	var r:=await pan(c,step)
	expect(r.replied and r.ok and str(r.message)==message,"%s: ok with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle([c]+watchers)
	return r

## Raw re-send of an already-used sequence number: no notice anywhere, nothing changes.
func resend(c:Client,sequence:int,step:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var counts:Array=everyone.map(func(x):return x.notices.size())
	var before:=marks_of(everyone)
	c.session.request_action.rpc_id(1,sequence,GP.ACTION,GP.SITE,step,region_of(c),int(c.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle(everyone)
	expect(everyone.map(func(x):return x.notices.size())==counts,"%s: re-sent sequence %d ('%s') gets no notice"%[label,sequence,step])
	expect(marks_of(everyone)==before,"%s: re-sent sequence %d ('%s') changes nothing on any end"%[label,sequence,step])

## Privacy: no raw token, no gold_panning key anywhere; the only panning key is the
## recipient's own_gold_panning (only in Jinguashi) with exactly stage/count/total.
func private_check(c:Client,in_jinguashi:bool,label:String)->void:
	var dump:=JSON.stringify(c.session.snapshot)
	var leaked:=false
	for t:String in [ALPHA,BETA,GAMMA]:
		if dump.contains(t):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no raw token"%[label,c.label])
	expect(not c.session.snapshot.has(GP.STATE_KEY) and not dump.contains("\"%s\""%GP.STATE_KEY),"%s: %s's snapshot has no '%s' key anywhere"%[label,c.label,GP.STATE_KEY])
	var found:Array=[]
	panning_keys(c.session.snapshot,found)
	var want:Array=[GP.OWN_KEY] if in_jinguashi else []
	expect(found==want,"%s: %s's only panning keys are %s (got %s)"%[label,c.label,str(want),str(found)])
	if in_jinguashi:
		var o=c.own()
		var keys:Array=[]
		if o is Dictionary:
			for k in o:keys.append(str(k))
		keys.sort()
		expect(keys==["count","stage","total"],"%s: %s's own_gold_panning has exactly stage/count/total (got %s)"%[label,c.label,str(keys)])

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

static func disk_record(disk:Variant,token:String)->String:
	if not disk is Dictionary:return "<no save>"
	var whole=disk.get(GP.STATE_KEY)
	if not whole is Dictionary or not whole.get("players") is Dictionary:return "<no record>"
	var own=whole.players.get(token)
	if not own is Dictionary:return "<no record>"
	var out:={}
	for field in own:out[str(field)]=int(own[field])
	return text(out)

static func record(stage:int,day:int,count:int,total:int)->String:
	return text({"stage":stage,"day":day,"count":count,"total":total})

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("gold-panning-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (alpha/beta written into Jinguashi on the bank by the panning site; nothing earned; no gold_panning) accepted by SaveSchema"):return false
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback"):return false
	expect(server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,"server and clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World")
	await settle([alpha,beta])
	expect(region_of(alpha)==GP.REGION and region_of(beta)==GP.REGION,"alpha and beta are in 金瓜石 (%s / %s)"%[region_of(alpha),region_of(beta)])
	for c:Client in [alpha,beta]:
		var at:=Vector2(float(c.me().get("x",-99.0)),float(c.me().get("y",-99.0)))
		expect(at.distance_to(Vector2(GP.SITE)+Vector2(0.5,0.5))<=GP.REACH,"%s stands within reach of the panning site (%s)"%[c.label,str(at)])
	print("GOLD_PANNING_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(region+spot written; nothing earned) shutdown=normal-only"%port)

	# 1. Fresh: both see their own zero view; no server record anywhere.
	for c:Client in [alpha,beta]:
		expect(own_text(c)==view(0,0,0),"case 1 %s: own_gold_panning is zeros (%s)"%[c.label,own_text(c)])
		expect(c.ore()==0,"case 1 %s holds no gold_ore"%c.label)
		expect(GP.next_step(c.session.snapshot)=="scoop" and GP.step_block(c.session.snapshot,"scoop",c.bag())=="","case 1 %s's client helper: next step scoop, not blocked"%c.label)
		expect(GP.today(c.session.snapshot)==1,"case 1 %s: world day 1"%c.label)
		private_check(c,true,"case 1")

	# 2. Refusals at stage 0 leave both ends unchanged.
	await refuse(alpha,"dig",GP.SITE,GP.BAD_EXTRA,"case 2 alpha unknown step",[beta])
	await refuse(alpha,"scoop",GP.SITE+Vector2i(1,0),GP.WRONG_CELL,"case 2 alpha scoops on the bank cell",[beta])
	await refuse(alpha,"sift",GP.SITE,GP.NEED_SCOOP,"case 2 alpha sifts an empty pan",[beta])
	await refuse(alpha,"pick",GP.SITE,GP.NEED_SCOOP,"case 2 alpha picks from an empty pan",[beta])

	# 3. Alpha scoops: only alpha's own view moves.
	var scoop:=await succeed(alpha,"scoop",GP.SCOOP_OK,"case 3 alpha scoops",[beta])
	await wait_until(func():return own_text(alpha)==view(1,0,0),3.0)
	expect(own_text(alpha)==view(1,0,0),"case 3 alpha sees stage 1 (%s)"%own_text(alpha))
	expect(GP.stage(alpha.session.snapshot)==1 and GP.next_step(alpha.session.snapshot)=="sift","case 3 alpha's client helper: stage 1, next sift")
	expect(own_text(beta)==view(0,0,0),"case 3 beta's own view stays zeros (%s)"%own_text(beta))
	for c:Client in [alpha,beta]:private_check(c,true,"case 3")

	# 4. Replay and out-of-order steps at stage 1 change nothing.
	await resend(alpha,int(scoop.sequence),"sift","case 4 scoop sequence as sift",[beta])
	await resend(alpha,int(scoop.sequence),"scoop","case 4 scoop sequence as scoop",[beta])
	expect(own_text(alpha)==view(1,0,0),"case 4 alpha still at stage 1 after the replays")
	await refuse(alpha,"pick",GP.SITE,GP.NOT_YET,"case 4 alpha picks at stage 1",[beta])
	await refuse(alpha,"swirl",GP.SITE,GP.NEED_SIFT,"case 4 alpha swirls before sifting",[beta])
	await refuse(alpha,"scoop",GP.SITE,GP.HAS_SAND,"case 4 alpha scoops a full pan",[beta])

	# 5. Alpha finishes the pan: sift, swirl ×3, pick.
	await succeed(alpha,"sift",GP.SIFT_OK,"case 5 alpha sifts",[beta])
	expect(own_text(alpha)==view(2,0,0),"case 5 alpha at stage 2 (%s)"%own_text(alpha))
	await refuse(alpha,"sift",GP.SITE,GP.SIFTED,"case 5 alpha sifts twice",[beta])
	await succeed(alpha,"swirl",GP.SWIRL_OK%2,"case 5 alpha swirl 1",[beta])
	expect(own_text(alpha)==view(3,0,0),"case 5 alpha at stage 3 (%s)"%own_text(alpha))
	await succeed(alpha,"swirl",GP.SWIRL_OK%1,"case 5 alpha swirl 2",[beta])
	expect(own_text(alpha)==view(4,0,0),"case 5 alpha at stage 4 (%s)"%own_text(alpha))
	await succeed(alpha,"swirl",GP.SWIRL_LAST,"case 5 alpha swirl 3",[beta])
	expect(own_text(alpha)==view(5,0,0),"case 5 alpha at stage 5 (%s)"%own_text(alpha))
	await refuse(alpha,"swirl",GP.SITE,GP.SWIRLED,"case 5 alpha swirls a fourth time",[beta])
	expect(own_text(beta)==view(0,0,0),"case 5 beta's own view still zeros while alpha pans")
	var picked:=await succeed(alpha,"pick",GP.PICK_OK%1,"case 5 alpha picks",[beta])
	await wait_until(func():return alpha.ore()==1,3.0)
	expect(alpha.ore()==1,"case 5 alpha's snapshot: gold_ore 1 (%d)"%alpha.ore())
	expect(own_text(alpha)==view(0,1,1),"case 5 alpha's view {stage 0, count 1, total 1} (%s)"%own_text(alpha))
	expect(own_text(beta)==view(0,0,0) and beta.ore()==0,"case 5 beta unchanged (%s, ore %d)"%[own_text(beta),beta.ore()])
	await resend(alpha,int(picked.sequence),"pick","case 5 pick sequence as pick",[beta])
	await resend(alpha,int(picked.sequence),"scoop","case 5 pick sequence as scoop",[beta])
	await resend(alpha,int(scoop.sequence),"scoop","case 5 first scoop sequence at an empty pan",[beta])
	expect(alpha.ore()==1 and own_text(alpha)==view(0,1,1),"case 5 replays gave no second gold_ore and no new pan")
	for c:Client in [alpha,beta]:private_check(c,true,"case 5")

	# 6. Interleaved: beta pans a whole pan while alpha pans to stage 3.
	var steps:=[
		[beta,"scoop",GP.SCOOP_OK,view(1,0,0),view(0,1,1)],
		[alpha,"scoop",GP.SCOOP_OK,view(1,1,1),view(1,0,0)],
		[beta,"sift",GP.SIFT_OK,view(2,0,0),view(1,1,1)],
		[alpha,"sift",GP.SIFT_OK,view(2,1,1),view(2,0,0)],
		[beta,"swirl",GP.SWIRL_OK%2,view(3,0,0),view(2,1,1)],
		[alpha,"swirl",GP.SWIRL_OK%2,view(3,1,1),view(3,0,0)],
		[beta,"swirl",GP.SWIRL_OK%1,view(4,0,0),view(3,1,1)],
		[beta,"swirl",GP.SWIRL_LAST,view(5,0,0),view(3,1,1)],
		[beta,"pick",GP.PICK_OK%1,view(0,1,1),view(3,1,1)],
	]
	for i in steps.size():
		var s:Array=steps[i]
		var who:Client=s[0]
		var other:Client=beta if who==alpha else alpha
		await succeed(who,str(s[1]),str(s[2]),"case 6 step %d %s %s"%[i,who.label,str(s[1])],[other])
		var want_b:String=str(s[3]) if who==beta else str(s[4])
		var want_a:String=str(s[3]) if who==alpha else str(s[4])
		await wait_until(func():return own_text(alpha)==want_a and own_text(beta)==want_b,3.0)
		expect(own_text(alpha)==want_a and own_text(beta)==want_b,"case 6 step %d: alpha %s / beta %s (got %s / %s)"%[i,want_a,want_b,own_text(alpha),own_text(beta)])
	await refuse(beta,"swirl",GP.SITE,GP.NEED_SCOOP,"case 6 beta swirls an empty pan while alpha's pan is at stage 3",[alpha])
	await refuse(alpha,"pick",GP.SITE,GP.NOT_YET,"case 6 alpha picks at stage 3",[beta])
	expect(alpha.ore()==1 and beta.ore()==1,"case 6 one gold_ore each (alpha %d, beta %d)"%[alpha.ore(),beta.ore()])
	for c:Client in [alpha,beta]:private_check(c,true,"case 6")

	# 7. A client at home sees no panning view and cannot pan.
	gamma=await join("gamma",GAMMA,port)
	if not expect(joined(gamma),"case 7 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	expect(region_of(gamma)=="home","case 7 gamma is at home (%s)"%region_of(gamma))
	expect(not gamma.session.snapshot.has(GP.OWN_KEY),"case 7 gamma's snapshot has no own_gold_panning key")
	private_check(gamma,false,"case 7")
	await refuse(gamma,"scoop",GP.SITE,GP.WRONG_REGION,"case 7 gamma (at home) scoops",[alpha,beta])
	await refuse(gamma,"pick",GP.SITE,GP.WRONG_REGION,"case 7 gamma (at home) picks",[alpha,beta])
	expect(own_text(alpha)==view(3,1,1) and own_text(beta)==view(0,1,1),"case 7 alpha/beta views unchanged by gamma")
	await leave(gamma)
	gamma=null

	# 8. Reconnect, then a server restart: the unfinished pan and the counts survive.
	await settle([alpha,beta])
	var before8:=marks_of([alpha,beta])
	await leave(alpha)
	alpha=null
	await pause(0.3)
	alpha=await join("alpha",ALPHA,port)
	if not expect(joined(alpha),"case 8 alpha reconnects"):return false
	await settle([alpha,beta])
	await wait_until(func():return alpha.own() is Dictionary,3.0)
	expect(marks_of([alpha,beta])==before8,"case 8 reconnect: own views and bags equal the pre-reconnect snapshots (%s vs %s)"%[str(marks_of([alpha,beta])),str(before8)])
	expect(own_text(alpha)==view(3,1,1),"case 8 reconnected alpha still at stage 3 (%s)"%own_text(alpha))
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 8 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 8 save parses"):return false
	expect(disk_valid(disk),"case 8 saved world passes SaveSchema")
	expect(GP.valid(disk.duplicate(true)),"case 8 GoldPanning.valid accepts the saved record")
	var day:=GP.today(disk)
	expect(day==1,"case 8 save is still day 1 (%d)"%day)
	expect(disk_record(disk,ALPHA)==record(3,day,1,1),"case 8 save: alpha's record (%s)"%disk_record(disk,ALPHA))
	expect(disk_record(disk,BETA)==record(0,day,1,1),"case 8 save: beta's record (%s)"%disk_record(disk,BETA))
	expect(disk_record(disk,GAMMA)=="<no record>","case 8 save: gamma has no panning record")
	expect(int(disk.players[ALPHA].inventory.get(ORE,0))==1 and int(disk.players[BETA].inventory.get(ORE,0))==1,"case 8 save: one gold_ore each")
	var port2:=start_server()
	if not expect(port2>0,"case 8 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 8 both rejoin after the restart"):return false
	await settle([alpha,beta])
	await wait_until(func():return alpha.own() is Dictionary and beta.own() is Dictionary,3.0)
	expect(marks_of([alpha,beta])==before8,"case 8 restart: own views and bags equal the pre-restart snapshots (%s vs %s)"%[str(marks_of([alpha,beta])),str(before8)])
	for c:Client in [alpha,beta]:private_check(c,true,"case 8")

	# 9. Daily limit over the wire: alpha finishes pans 2 and 3; the fourth scoop is refused.
	await succeed(alpha,"swirl",GP.SWIRL_OK%1,"case 9 alpha resumes: swirl 2",[beta])
	await succeed(alpha,"swirl",GP.SWIRL_LAST,"case 9 alpha swirl 3",[beta])
	await succeed(alpha,"pick",GP.PICK_OK%2,"case 9 alpha picks pan 2",[beta])
	expect(own_text(alpha)==view(0,2,2) and alpha.ore()==2,"case 9 after pan 2 (%s, ore %d)"%[own_text(alpha),alpha.ore()])
	await succeed(alpha,"scoop",GP.SCOOP_OK,"case 9 pan 3 scoop",[beta])
	await succeed(alpha,"sift",GP.SIFT_OK,"case 9 pan 3 sift",[beta])
	await succeed(alpha,"swirl",GP.SWIRL_OK%2,"case 9 pan 3 swirl 1",[beta])
	await succeed(alpha,"swirl",GP.SWIRL_OK%1,"case 9 pan 3 swirl 2",[beta])
	await succeed(alpha,"swirl",GP.SWIRL_LAST,"case 9 pan 3 swirl 3",[beta])
	await succeed(alpha,"pick",GP.PICK_OK%3,"case 9 alpha picks pan 3",[beta])
	await wait_until(func():return alpha.ore()==3,3.0)
	expect(own_text(alpha)==view(0,3,3) and alpha.ore()==3,"case 9 after pan 3 (%s, ore %d)"%[own_text(alpha),alpha.ore()])
	expect(GP.today(alpha.session.snapshot)==1,"case 9 still day 1 (time never advanced by the test)")
	expect(GP.step_block(alpha.session.snapshot,"scoop",alpha.bag())==GP.DAILY_DONE,"case 9 alpha's client helper predicts DAILY_DONE")
	await refuse(alpha,"scoop",GP.SITE,GP.DAILY_DONE,"case 9 alpha's fourth scoop",[beta])
	expect(own_text(beta)==view(0,1,1) and beta.ore()==1,"case 9 beta untouched by alpha's pans (%s, ore %d)"%[own_text(beta),beta.ore()])
	expect(GP.step_block(beta.session.snapshot,"scoop",beta.bag())=="","case 9 beta may still scoop (her own count is 1)")
	for c:Client in [alpha,beta]:private_check(c,true,"case 9")
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 9 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after),"case 9 final save passes SaveSchema")
	var day2:int=GP.today(after) if after is Dictionary else -1
	expect(disk_record(after,ALPHA)==record(0,day2,3,3) and disk_record(after,BETA)==record(0,day2,1,1),"case 9 final save: alpha %s, beta %s"%[disk_record(after,ALPHA),disk_record(after,BETA)])
	expect(after is Dictionary and int(after.players[ALPHA].inventory.get(ORE,0))==3 and int(after.players[BETA].inventory.get(ORE,0))==1,"case 9 final save: gold_ore 3 / 1")
	return true

func teardown()->void:
	for c in [alpha,beta,gamma]:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in [alpha,beta,gamma]:
		if c!=null and is_instance_valid(c.branch):c.branch.queue_free()
	if is_instance_valid(server_branch):server_branch.queue_free()
	await process_frame

func remove_folder()->bool:
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):return false
	var dir:=DirAccess.open(folder)
	if dir==null:return false
	for file in dir.get_files():
		if DirAccess.remove_absolute(folder.path_join(file))!=OK:return false
	return DirAccess.remove_absolute(folder)==OK and not DirAccess.dir_exists_absolute(folder)
