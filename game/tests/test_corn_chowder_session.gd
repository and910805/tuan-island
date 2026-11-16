extends SceneTree
## 玉米濃湯（corn_chowder，第三道共餐桌分享餐）two-client Session acceptance over a real
## dedicated server and real WebSocket clients (harness copied from
## test_table_warmer_session.gd / test_tea_service_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha, beta) and, after a
## restart, two late joiners (gamma, delta) join over loopback, each in its own branch with
## its own SceneMultiplayer. Clients only read their own received snapshots. The server World
## is never written after seeding; it is only READ (server.world.state) to assert the
## authoritative community / bags next to both client snapshots. The on-disk save is read
## (file only) after shutdowns.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and
## validated with SaveSchema. The picnic is EARNED there through World.act "picnic"
## (board=true and soup 2 / bread 1 written first), so the shared table sits at 39,30.
## Every direct write goes through preset() and is marked # PRESET; the count is printed.
## Written directly: board, positions (alpha 40.5,30.5; beta 38.5,30.5), soup/bread for the
## picnic, exact bags — alpha {corn_chowder 5, trout_hotpot 4}, beta {corn_chowder 3,
## watermelon_platter 4} — and emptied receipts. Cooking the chowder is rule level
## (RECIPES); no community dish key is ever preset. gamma / delta are fresh players that
## spawn at World.SPAWN (probed standable and within the 3.2 reach of world.gd's act).
## Replay: the raw request_action RPC re-sent with an already-used sequence number (alpha's
## serve, beta's claim); Session drops both, so each applies once.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns
## only), cooking the chowder, BAG_FULL, wrong-region refusals (rule level). Time does not
## need to advance.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Community=preload("res://scripts/community.gd")
const KEY:="corn-chowder-session"
const ALPHA:="chowder-session-alpha-token"
const BETA:="chowder-session-beta-token"
const GAMMA:="chowder-session-gamma-token"
const DELTA:="chowder-session-delta-token"
const TABLE:=Vector2i(39,30)
const BOARD:=Vector2i(40,29)
const A_SPOT:=Vector2(40.5,30.5)
const B_SPOT:=Vector2(38.5,30.5)
## world.gd act(): `if dist>3.2: return fail("靠近一點，才能和它互動")` for community actions.
const REACH:=3.2
const ALPHA_BAG:={"corn_chowder":5,"trout_hotpot":4}
const BETA_BAG:={"corn_chowder":3,"watermelon_platter":4}
## Literal strings from community.gd share_dish / world.gd COMMUNITY branch.
const ALREADY:="你已領過這一輪，剩下的留給其他島民。"
const WRONG_TABLE:="請到風鈴渡口的共餐桌分食。"

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
		var mine=people.get(session.own_id,{})
		return mine if mine is Dictionary else {}
	func bag()->Dictionary:
		var inv=me().get("inventory",{})
		return inv if inv is Dictionary else {}
	func community()->Dictionary:
		var c=session.snapshot.get("community",{})
		return c if c is Dictionary else {}
	func meal(dish:String)->Dictionary:
		var m=community().get(dish,{})
		return m if m is Dictionary else {}

var checks:=0
var failures:=0
var serial:=0
var presets:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var alpha:Client
var beta:Client
var gamma:Client
var delta:Client

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func _initialize()->void:
	create_timer(110.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("CORN_CHOWDER_SESSION watchdog fired before completion")
	print("CORN_CHOWDER_SESSION presets=%d"%presets)
	print("CORN_CHOWDER_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("CORN_CHOWDER_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("CORN_CHOWDER_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("CORN_CHOWDER_SESSION presets=%d"%presets)
	print("CORN_CHOWDER_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

## Every direct state write in the fixture goes through here (counted, marked # PRESET).
func preset(d:Dictionary,field:String,value:Variant)->void:
	d[field]=value
	presets+=1

func seed_world(path:String)->bool:
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	preset(w.state,"board",true) # PRESET
	var a:Dictionary=w.state.players[ALPHA]
	preset(a,"x",A_SPOT.x) # PRESET
	preset(a,"y",A_SPOT.y) # PRESET
	preset(a.inventory,"soup",2) # PRESET
	preset(a.inventory,"bread",1) # PRESET
	var b:Dictionary=w.state.players[BETA]
	preset(b,"x",B_SPOT.x) # PRESET
	preset(b,"y",B_SPOT.y) # PRESET
	var picnic:Dictionary=w.act(ALPHA,"seed-picnic","picnic",BOARD)
	if not bool(picnic.get("ok",false)):
		push_error("seed picnic failed: %s"%str(picnic.get("message","")))
		return false
	if Community.table_cell(w.state)!=TABLE:return false
	preset(a,"inventory",ALPHA_BAG.duplicate()) # PRESET
	preset(b,"inventory",BETA_BAG.duplicate()) # PRESET
	preset(a,"receipts",{}) # PRESET
	preset(b,"receipts",{}) # PRESET
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:return false
	var com=parsed.get("community",{})
	if not com is Dictionary:return false
	for dish in Community.DISHES:
		if com.has(dish):return false
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
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.get("community") is Dictionary

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

static func key_list(d:Variant)->Array:
	var keys:Array=[]
	if not d is Dictionary:return keys
	for k in d:keys.append(str(k))
	keys.sort()
	return keys

static func with_key(keys:Array,extra:String)->Array:
	var out:Array=keys.duplicate()
	if not out.has(extra):out.append(extra)
	out.sort()
	return out

static func title(dish:String)->String:
	return str(World.NAMES[Community.DISHES[dish]])

static func msg_served(dish:String)->String:
	return title(dish)+"上桌了。四份會留在餐桌，島民可以各領一份。"

static func msg_still(dish:String)->String:
	return "餐桌上還有"+title(dish)+"，先留給晚點回來的島民。"

static func msg_need(dish:String)->String:
	return "需要四份"+title(dish)+"才能上桌。"

static func msg_gone(dish:String)->String:
	return title(dish)+"已經分完了。"

static func msg_claimed(dish:String)->String:
	return "已領取一份"+title(dish)+"。"

## Client view of one dish round: key set, portions, own flag.
static func client_row(m:Dictionary)->String:
	if m.is_empty():return "none"
	return text({"keys":key_list(m),"portions":int(m.get("portions",-1)),"claimed_own":m.get("claimed_own")})

static func want_client(portions:int,own:bool)->String:
	return text({"keys":["claimed_own","portions"],"portions":portions,"claimed_own":own})

## Authoritative / stored view of one dish round: key set, portions, sorted claimants.
static func stored_row(m:Variant)->String:
	if not m is Dictionary or m.is_empty():return "none"
	var claimed=m.get("claimed")
	var all_true:=claimed is Dictionary
	if claimed is Dictionary:
		for who in claimed:
			if claimed[who]!=true:all_true=false
	return text({"keys":key_list(m),"portions":int(m.get("portions",-1)),"claimed":key_list(claimed),"flags_true":all_true})

static func want_stored(portions:int,claimers:Array)->String:
	var sorted:Array=claimers.duplicate()
	sorted.sort()
	return text({"keys":["claimed","portions"],"portions":portions,"claimed":sorted,"flags_true":true})

func server_ok()->bool:
	return server!=null and is_instance_valid(server) and server.world!=null

func srv_meal(dish:String)->Dictionary:
	if not server_ok():return {"<no server>":true}
	var com=server.world.state.get("community",{})
	var m=com.get(dish,{}) if com is Dictionary else {}
	return m.duplicate(true) if m is Dictionary else {}

func srv_bag(token:String)->Dictionary:
	if not server_ok():return {"<no server>":-1}
	var people=server.world.state.get("players",{})
	var p=people.get(token,{}) if people is Dictionary else {}
	var inv=p.get("inventory",{}) if p is Dictionary else {}
	return canon(inv)

func server_marks()->Array:
	var out:Array=[]
	for dish in Community.DISHES:out.append(stored_row(srv_meal(dish)))
	for t:String in [ALPHA,BETA,GAMMA,DELTA]:out.append(text(srv_bag(t)))
	return out

func marks_of(clients:Array)->Array:
	var out:Array=clients.map(func(x):
		var row:Array=[text(canon(x.bag()))]
		for dish in Community.DISHES:row.append(client_row(x.meal(dish)))
		return row)
	out.append(server_marks())
	return out

## Every listed client sees `portions` left of `dish`.
func sees(clients:Array,dish:String,portions:int)->bool:
	for c in clients:
		if c==null or int(c.meal(dish).get("portions",-1))!=portions:return false
	return true

func refuse(c:Client,action:String,p:Vector2i,message:String,label:String,watchers:Array)->Dictionary:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: bags and every dish round unchanged on the server and in every watching snapshot"%label)
	return r

func succeed(c:Client,action:String,p:Vector2i,message:String,label:String,watchers:Array)->Dictionary:
	var r:=await act(c,action,p)
	expect(r.replied and r.ok and str(r.message)==message,"%s: ok with '%s' (got ok=%s '%s')"%[label,message,str(r.ok),str(r.message)])
	await settle([c]+watchers)
	return r

## Re-send an already-used sequence number over the raw RPC; Session must drop it.
func replay(c:Client,sequence:int,action:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var counts:Array=everyone.map(func(x):return x.notices.size())
	var before:=marks_of(everyone)
	c.session.request_action.rpc_id(1,sequence,action,TABLE,"",str(c.session.snapshot.get("region_id","")),int(c.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle(everyone)
	expect(everyone.map(func(x):return x.notices.size())==counts,"%s: re-sent sequence %d gets no notice"%[label,sequence])
	expect(marks_of(everyone)==before,"%s: re-sent sequence %d changes nothing on the server or either client (applied once)"%[label,sequence])

func private_check(c:Client,others:Array,label:String)->void:
	var dump:=JSON.stringify(c.session.snapshot)
	var leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no raw token"%[label,c.label])
	var maps:=false
	for dish in Community.DISHES:
		if c.meal(dish).has("claimed"):maps=true
	expect(not maps,"%s: %s's snapshot carries no claim map for any dish"%[label,c.label])

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

static func disk_meal(disk:Variant,dish:String)->Variant:
	if not disk is Dictionary:return null
	var com=disk.get("community",{})
	return com.get(dish) if com is Dictionary else null

static func disk_bag(disk:Variant,token:String)->Dictionary:
	if not disk is Dictionary:return {"<invalid>":-1}
	var people=disk.get("players",{})
	var p=people.get(token,{}) if people is Dictionary else {}
	return canon(p.get("inventory",{}) if p is Dictionary else {})

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	expect(Community.DISHES.get("chowder","")=="corn_chowder" and "serve_chowder" in Community.ACTIONS and "claim_chowder" in Community.ACTIONS,"static: chowder registered as a shared-table dish with serve/claim actions")
	expect(title("chowder")=="玉米濃湯" and int(World.RECIPES.corn_chowder.yield)==Community.HOTPOT_PORTIONS,"static: 玉米濃湯 name, recipe yields one 4-portion round")
	folder=OS.get_environment("TEMP").path_join("corn-chowder-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (picnic earned offline; positions and bags written; no dish round) accepted by SaveSchema"):return false
	var probe:=World.new()
	if not expect(probe.load_world(save_path),"probe: seeded save loads"):return false
	var centre:=Vector2(TABLE)+Vector2(0.5,0.5)
	for spot:Vector2 in [A_SPOT,B_SPOT,World.SPAWN]:
		expect(probe.can_stand(spot) and spot.distance_to(centre)<=REACH,"probe: %s standable and within reach of the table"%str(spot))
	probe=null
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback"):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws,"server and clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World")
	await settle([alpha,beta])
	print("CORN_CHOWDER_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+2 late joiners after restart) fixture=SEEDED(picnic earned offline,positions,bags) shutdown=normal-only"%port)

	# 1. Fresh: no dish round anywhere; remember the top-level snapshot keys.
	var keys_a0:Array=key_list(alpha.session.snapshot)
	var keys_b0:Array=key_list(beta.session.snapshot)
	for c:Client in [alpha,beta]:
		expect(key_list(c.community())==["table"],"case 1 %s: community holds only the table (%s)"%[c.label,text(key_list(c.community()))])
		expect(Community.table_cell(c.session.snapshot)==TABLE,"case 1 %s: table cell 39,30 computable from the snapshot"%c.label)
		private_check(c,[beta if c==alpha else alpha],"case 1")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and canon(beta.bag())==canon(BETA_BAG),"case 1 preset bags arrive unchanged on the clients")
	expect(srv_bag(ALPHA)==canon(ALPHA_BAG) and srv_bag(BETA)==canon(BETA_BAG),"case 1 server bags equal the presets")
	expect(stored_row(srv_meal("chowder"))=="none" and stored_row(srv_meal("hotpot"))=="none" and stored_row(srv_meal("watermelon"))=="none","case 1 server community has no dish round")

	# 2. Refusals before any round: fewer than four, empty table, wrong cell.
	await refuse(beta,"serve_chowder",TABLE,msg_need("chowder"),"case 2 beta serves with only 3 chowder",[alpha])
	await refuse(alpha,"claim_chowder",TABLE,msg_gone("chowder"),"case 2 claim before any chowder is served",[beta])
	await refuse(alpha,"serve_chowder",Vector2i(40,31),WRONG_TABLE,"case 2 serve at a cell that is not the table",[beta])
	expect(stored_row(srv_meal("chowder"))=="none","case 2 server still has no chowder round")

	# 3. Alpha serves four; both clients and the server see 4, no tokens, bag -4 only for alpha.
	var served:=await succeed(alpha,"serve_chowder",TABLE,msg_served("chowder"),"case 3 alpha serves four chowder",[beta])
	await wait_until(func():return sees([alpha,beta],"chowder",4),3.0)
	for c:Client in [alpha,beta]:
		expect(client_row(c.meal("chowder"))==want_client(4,false),"case 3 %s sees 4 portions, unclaimed, no claim map (%s)"%[c.label,client_row(c.meal("chowder"))])
		private_check(c,[beta if c==alpha else alpha],"case 3")
	expect(stored_row(srv_meal("chowder"))==want_stored(4,[]),"case 3 server: chowder {portions 4, claimed {}} (%s)"%stored_row(srv_meal("chowder")))
	expect(canon(alpha.bag())==canon({"corn_chowder":1,"trout_hotpot":4}) and srv_bag(ALPHA)==canon({"corn_chowder":1,"trout_hotpot":4}),"case 3 alpha's bag lost exactly 4 chowder (client %s, server %s)"%[text(canon(alpha.bag())),text(srv_bag(ALPHA))])
	expect(canon(beta.bag())==canon(BETA_BAG) and srv_bag(BETA)==canon(BETA_BAG),"case 3 beta's bag unchanged on client and server")
	expect(key_list(alpha.session.snapshot)==keys_a0 and key_list(beta.session.snapshot)==keys_b0,"case 3 top-level snapshot keys unchanged by the chowder round")
	expect(key_list(alpha.community())==["chowder","table"],"case 3 community gained only the chowder key")

	# 3b. Replay of alpha's serve sequence is dropped.
	await replay(alpha,int(served.sequence),"serve_chowder","case 3b replay serve",[beta])

	# 4. Serving again while portions remain is refused (alpha has 1, beta has 3).
	await refuse(alpha,"serve_chowder",TABLE,msg_still("chowder"),"case 4 alpha serves again while 4 remain",[beta])
	await refuse(beta,"serve_chowder",TABLE,msg_still("chowder"),"case 4 beta serves while 4 remain",[alpha])

	# 5. Beta claims one; own flag only on beta; second claim refused; replay dropped.
	var claimed:=await succeed(beta,"claim_chowder",TABLE,msg_claimed("chowder"),"case 5 beta claims chowder",[alpha])
	await wait_until(func():return sees([alpha,beta],"chowder",3),3.0)
	expect(client_row(beta.meal("chowder"))==want_client(3,true),"case 5 beta sees 3 left and claimed_own true (%s)"%client_row(beta.meal("chowder")))
	expect(client_row(alpha.meal("chowder"))==want_client(3,false),"case 5 alpha sees 3 left and claimed_own false (%s)"%client_row(alpha.meal("chowder")))
	expect(stored_row(srv_meal("chowder"))==want_stored(3,[BETA]),"case 5 server: 3 left, claimed by beta only (%s)"%stored_row(srv_meal("chowder")))
	expect(canon(beta.bag())==canon({"corn_chowder":4,"watermelon_platter":4}) and srv_bag(BETA)==canon({"corn_chowder":4,"watermelon_platter":4}),"case 5 beta gained exactly one chowder (client and server)")
	expect(srv_bag(ALPHA)==canon({"corn_chowder":1,"trout_hotpot":4}),"case 5 alpha's server bag unchanged")
	for c:Client in [alpha,beta]:private_check(c,[beta if c==alpha else alpha],"case 5")
	await refuse(beta,"claim_chowder",TABLE,ALREADY,"case 5 beta claims a second time",[alpha])
	await replay(beta,int(claimed.sequence),"claim_chowder","case 5 replay claim",[alpha])
	# The first claim of any meal records the island's first discovery (world.gd
	# _record_discovery -> state.island_meals_discoveries); that is the only new top-level key.
	var keys_a5:Array=with_key(keys_a0,"island_meals_discoveries")
	var keys_b5:Array=with_key(keys_b0,"island_meals_discoveries")
	expect(key_list(alpha.session.snapshot)==keys_a5 and key_list(beta.session.snapshot)==keys_b5,"case 5 top-level snapshot keys: only island_meals_discoveries added by the first claim (%s)"%text(key_list(alpha.session.snapshot)))

	# 6. Hotpot and watermelon rounds on the same table stay independent.
	await succeed(alpha,"serve_hotpot",TABLE,msg_served("hotpot"),"case 6 alpha serves hotpot",[beta])
	await succeed(beta,"serve_watermelon",TABLE,msg_served("watermelon"),"case 6 beta serves watermelon",[alpha])
	await wait_until(func():return sees([alpha,beta],"hotpot",4) and sees([alpha,beta],"watermelon",4),3.0)
	for c:Client in [alpha,beta]:
		expect(client_row(c.meal("hotpot"))==want_client(4,false) and client_row(c.meal("watermelon"))==want_client(4,false),"case 6 %s sees fresh 4-portion hotpot and watermelon rounds"%c.label)
		expect(client_row(c.meal("chowder"))==want_client(3,c==beta),"case 6 %s: chowder round untouched by the other serves"%c.label)
	await succeed(beta,"claim_hotpot",TABLE,msg_claimed("hotpot"),"case 6 beta claims hotpot",[alpha])
	await succeed(alpha,"claim_watermelon",TABLE,msg_claimed("watermelon"),"case 6 alpha claims watermelon",[beta])
	await wait_until(func():return sees([alpha,beta],"hotpot",3) and sees([alpha,beta],"watermelon",3),3.0)
	expect(client_row(alpha.meal("hotpot"))==want_client(3,false) and client_row(alpha.meal("watermelon"))==want_client(3,true) and client_row(alpha.meal("chowder"))==want_client(3,false),"case 6 alpha: hotpot 3 (not own), watermelon 3 (own), chowder 3 (not own)")
	expect(client_row(beta.meal("hotpot"))==want_client(3,true) and client_row(beta.meal("watermelon"))==want_client(3,false) and client_row(beta.meal("chowder"))==want_client(3,true),"case 6 beta: hotpot 3 (own), watermelon 3 (not own), chowder 3 (own)")
	expect(stored_row(srv_meal("hotpot"))==want_stored(3,[BETA]) and stored_row(srv_meal("watermelon"))==want_stored(3,[ALPHA]) and stored_row(srv_meal("chowder"))==want_stored(3,[BETA]),"case 6 server: three independent rounds (hotpot %s, watermelon %s, chowder %s)"%[stored_row(srv_meal("hotpot")),stored_row(srv_meal("watermelon")),stored_row(srv_meal("chowder"))])
	var alpha_bag6:={"corn_chowder":1,"watermelon_platter":1}
	var beta_bag6:={"corn_chowder":4,"trout_hotpot":1}
	expect(canon(alpha.bag())==canon(alpha_bag6) and srv_bag(ALPHA)==canon(alpha_bag6),"case 6 alpha bag exact on client and server (%s)"%text(srv_bag(ALPHA)))
	expect(canon(beta.bag())==canon(beta_bag6) and srv_bag(BETA)==canon(beta_bag6),"case 6 beta bag exact on client and server (%s)"%text(srv_bag(BETA)))
	await refuse(beta,"claim_hotpot",TABLE,ALREADY,"case 6 beta claims hotpot twice",[alpha])
	await refuse(beta,"claim_chowder",TABLE,ALREADY,"case 6 beta still cannot re-claim chowder",[alpha])
	for c:Client in [alpha,beta]:private_check(c,[beta if c==alpha else alpha],"case 6")
	expect(key_list(alpha.session.snapshot)==keys_a5 and key_list(beta.session.snapshot)==keys_b5,"case 6 top-level snapshot keys unchanged with three rounds on the table")
	expect(key_list(alpha.community())==["chowder","hotpot","table","watermelon"],"case 6 community keys are exactly the table and three dishes")

	# 7. Normal shutdown -> save carries chowder with its claimant and passes the schema.
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 7 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 7 save parses"):return false
	expect(disk_valid(disk),"case 7 saved world passes SaveSchema")
	expect(stored_row(disk_meal(disk,"chowder"))==want_stored(3,[BETA]),"case 7 save: chowder 3 left, claimed by beta (%s)"%stored_row(disk_meal(disk,"chowder")))
	expect(stored_row(disk_meal(disk,"hotpot"))==want_stored(3,[BETA]) and stored_row(disk_meal(disk,"watermelon"))==want_stored(3,[ALPHA]),"case 7 save: hotpot and watermelon rounds saved independently")
	expect(disk_bag(disk,ALPHA)==canon(alpha_bag6) and disk_bag(disk,BETA)==canon(beta_bag6),"case 7 save: both exact bags")
	expect(str(disk.get("community",{}).get("table",""))=="39,30","case 7 save: the table did not move")

	# 8. Restart: beta still cannot claim; late joiners claim; the fifth claim is refused.
	var port2:=start_server()
	if not expect(port2>0,"case 8 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 8 both rejoin"):return false
	await settle([alpha,beta])
	expect(client_row(alpha.meal("chowder"))==want_client(3,false) and client_row(beta.meal("chowder"))==want_client(3,true),"case 8 restart consistent: 3 left, only beta's own flag")
	expect(stored_row(srv_meal("chowder"))==want_stored(3,[BETA]),"case 8 restarted server: chowder 3 left, claimed by beta")
	await refuse(beta,"claim_chowder",TABLE,ALREADY,"case 8 beta cannot claim again after restart",[alpha])
	gamma=await join("gamma",GAMMA,port2)
	if not expect(joined(gamma),"case 8 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	var gpos:=Vector2(float(gamma.me().get("x",-99.0)),float(gamma.me().get("y",-99.0)))
	expect(gpos.distance_to(centre)<=REACH,"case 8 gamma spawned within reach of the table (%s)"%str(gpos))
	expect(client_row(gamma.meal("chowder"))==want_client(3,false),"case 8 gamma sees 3 portions, unclaimed (%s)"%client_row(gamma.meal("chowder")))
	private_check(gamma,[alpha,beta],"case 8")
	await succeed(gamma,"claim_chowder",TABLE,msg_claimed("chowder"),"case 8 gamma claims chowder",[alpha,beta])
	await wait_until(func():return sees([alpha,beta,gamma],"chowder",2),3.0)
	expect(client_row(gamma.meal("chowder"))==want_client(2,true) and client_row(alpha.meal("chowder"))==want_client(2,false) and client_row(beta.meal("chowder"))==want_client(2,true),"case 8 everyone sees 2 left with their own flags")
	expect(stored_row(srv_meal("chowder"))==want_stored(2,[BETA,GAMMA]),"case 8 server: 2 left, beta and gamma claimed")
	expect(int(srv_bag(GAMMA).get("corn_chowder",0))==1 and int(gamma.bag().get("corn_chowder",0))==1,"case 8 gamma holds exactly one chowder (client and server)")
	await refuse(gamma,"claim_chowder",TABLE,ALREADY,"case 8 gamma claims twice",[alpha,beta])
	await succeed(alpha,"claim_chowder",TABLE,msg_claimed("chowder"),"case 8 alpha (who served) claims one too",[beta,gamma])
	await wait_until(func():return sees([alpha,beta,gamma],"chowder",1),3.0)
	delta=await join("delta",DELTA,port2)
	if not expect(joined(delta),"case 8 late joiner delta joins"):return false
	await settle([alpha,beta,gamma,delta])
	expect(client_row(delta.meal("chowder"))==want_client(1,false),"case 8 delta sees the last portion (%s)"%client_row(delta.meal("chowder")))
	await succeed(delta,"claim_chowder",TABLE,msg_claimed("chowder"),"case 8 delta claims the last portion",[alpha,beta,gamma])
	await wait_until(func():return sees([alpha,beta,gamma,delta],"chowder",0),3.0)
	for c:Client in [alpha,beta,gamma,delta]:
		expect(client_row(c.meal("chowder"))==want_client(0,true),"case 8 %s sees 0 left and its own claim (%s)"%[c.label,client_row(c.meal("chowder"))])
		private_check(c,[alpha,beta,gamma,delta],"case 8 all claimed")
	expect(stored_row(srv_meal("chowder"))==want_stored(0,[ALPHA,BETA,GAMMA,DELTA]),"case 8 server: all four portions claimed (%s)"%stored_row(srv_meal("chowder")))
	var gone:=await refuse(beta,"claim_chowder",TABLE,msg_gone("chowder"),"case 8 claim after all four are gone",[alpha,gamma,delta])
	expect(str(gone.message)=="玉米濃湯已經分完了。","case 8 refusal text is the server's own notice (%s)"%str(gone.message))
	await refuse(delta,"claim_chowder",TABLE,msg_gone("chowder"),"case 8 delta claims again after the round ended",[alpha,beta,gamma])
	expect(stored_row(srv_meal("hotpot"))==want_stored(3,[BETA]) and stored_row(srv_meal("watermelon"))==want_stored(3,[ALPHA]),"case 8 hotpot and watermelon rounds untouched by the chowder claims")
	for c:Client in [gamma,delta,alpha,beta]:await leave(c)
	gamma=null
	delta=null
	alpha=null
	beta=null
	expect(await stop_server(),"case 8 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after),"case 8 final save passes SaveSchema")
	expect(stored_row(disk_meal(after,"chowder"))==want_stored(0,[ALPHA,BETA,GAMMA,DELTA]),"case 8 final save: chowder 0 left, four claimants (%s)"%stored_row(disk_meal(after,"chowder")))
	expect(disk_bag(after,ALPHA)==canon({"corn_chowder":2,"watermelon_platter":1}) and disk_bag(after,BETA)==canon(beta_bag6),"case 8 final save: alpha +1 chowder, beta unchanged")
	expect(int(disk_bag(after,GAMMA).get("corn_chowder",0))==1 and int(disk_bag(after,DELTA).get("corn_chowder",0))==1,"case 8 final save: gamma and delta recorded with one chowder each")
	return true

func teardown()->void:
	for c in [alpha,beta,gamma,delta]:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in [alpha,beta,gamma,delta]:
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
