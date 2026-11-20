extends SceneTree
## T071 市集攤位 (market stall) two-client Session acceptance: personal stalls on
## the shared ferry plaza, over a real dedicated server and real WebSocket clients.
##
## LEVEL: one machine, ONE Godot process. Inside the single SceneTree a real
## dedicated server Session listens on a free 127.0.0.1 port with the WebSocket
## transport (WebSocketMultiplayerPeer); separate client Session nodes join it
## over loopback, each in its own branch with its own SceneMultiplayer, so every
## request, notice and snapshot travels the RPC + WebSocket path. Clients only
## read their own received snapshots (data.own_market, their own player entry);
## the server World is never touched after seeding, except for reading the
## on-disk save after each normal shutdown.
##
## SEEDED FIXTURE (disclosed; written to a fresh TEMP folder and validated with
## SaveSchema before the server starts): picnic=true; state.time=3*1440-240
## (world day 2, theme "flower", 240 world seconds before the day-3 boundary);
## alpha and beta stand on two distinct standable spots within 3.2 of the stall
## cell (cell from MARKET.cell_for on a probe save loaded like the server's);
## beta also owns an empty whitewood register near the shared plaza.
## exact bags alpha {radish 10, soup 1, bluebell 2, egg 1, carrot 1, wood 5,
## radish_seed 2}, beta {radish 4, carrot 2, wood 2}; islander "delta" at home
## out of reach of the stall, islander "epsilon" in star_garden (wrong region).
## No player.market is ever preset. Second short run (case 9): separate save with
## picnic=false and islander "zeta" beside the stall cell holding {radish 2}.
## Everything after the seed goes through client Sessions over the network:
## stock/take/open/collect, every refusal, disconnect/rejoin, the sequence
## replay, shutdowns and restarts.
## Clock: world time only advances on the live server. The day boundary comes
## from the preset state.time plus a temporary Engine.time_scale (TIME_SCALE)
## while alpha is offline; a guard check asserts day 2 just before it.
## Replay (case 5): the raw `request_action` RPC with an already-used sequence
## number (pattern of test_resident_bond_session); Session drops it before World.
## Stall guests + journal card (T071 presentation, market_visitors.gd): at the
## natural points of the cases above, each client's OWN received snapshot is fed
## to MarketVisitors.plan(own_market, snapshot.time) and
## MarketVisitors.summary_lines(own_market, World.NAMES) -- exactly the inputs
## world_view.gd / life_ui_tasks.gd use. Nothing about guests is preset or
## injected: the 2-guest / 3-guest plans come from alpha's and beta's real
## market_open requests raising the island-wide stalls_today in both snapshots;
## the 5-line card comes from the real midnight settlement. Checked: plans are
## empty while nobody is open / after settlement / when locked (zeta), equal
## (var_to_str) across clients on the same day, unchanged by the case 5 replay;
## cards show only the reader's own stock/till/report, and are identical before
## and after the case 8 restart. The snapshot carries no guest-related top-level
## key and own_market has exactly the MARKET.view keys (guests are derived on
## the client). Same machine, single process; no rendering is exercised here.
## Stall display (T071 「攤位布置」, market_display.gd, presentation only): each
## client's OWN received own_market is fed to MarketDisplay.shelf / remark /
## remark_line(own_market, World.NAMES). Nothing display-related is preset: the
## shelves come from the real market_stock/market_take requests above, the remarks
## from the real market_open requests (alpha's themed bluebell line, beta's
## "other" carrot line, CLOSED for a not-yet-open reader while another stall is
## open) and the empty remark from the real midnight settlement. Expected shelves
## (item/count sorted by id, slot index, themed flag) and remark lines are
## recomputed independently in this file from each client's own stock and the
## market rules. Checked: shelf shows only the reader's own goods and the reader's
## market fields never carry the other's stocked counts; remark "" before anyone
## opens / after settlement / when locked (zeta); two sequence replays (a stock
## before opening and beta's market_open after both opened) change no shelf or
## remark; shelf + remark_line identical across the case 8 restart; no
## shelf/remark/display top-level snapshot key (own_market keys unchanged).
## Same-machine single-process evidence only; drawing of the tags is not tested.
## Stall decor (market_decor, T071 「攤位布置」): alpha alone customises, through real
## market_decor requests ("cloth|indigo" then "sign|flower") while her stall is open
## on day 2 (end of case 4, before the first shutdown). Checked: no own_market.decor
## key for anyone by default / for locked zeta / after any refusal (default-valued,
## malformed, unknown kind/choice, wrong cell, too far, wrong region, locked); only
## alpha's own_market gains exactly the key "decor" (never a players entry or a
## top-level key; beta/others keep OWN_MARKET_KEYS); bag, coins, stock, prices, till,
## total and the register ownership on disk are unchanged; alpha's open themed
## remark_line gains World.MARKET_DECOR.remark (beta's does not); decor survives
## alpha's offline settlement and the case 8 restart (disk market_decor exact).
## NOT covered: multiple processes, cross-machine, TLS/wss, latency/packet loss
## injection, crash durability (only normal shutdowns with a final save), the
## NO_STALL refusal (all four candidate cells occupied) and wallet-cap refusals
## (rule level only, test_market_stall.gd).
const Session=preload("res://scripts/session.gd")
const MarketVisitors=preload("res://scripts/market_visitors.gd")
const MarketDisplay=preload("res://scripts/market_display.gd")
const OWN_MARKET_KEYS:=["day","next_theme","open","pending","prices","report","stalls_today","stock","stock_count","theme","till","total","unlocked","visitors_estimate"]
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const MARKET=preload("res://scripts/market_stall.gd")
const Regions=preload("res://scripts/regions.gd")
const KEY:="market-stall-session"
const ALPHA:="market-session-alpha-token"
const BETA:="market-session-beta-token"
const GAMMA:="market-session-gamma-token"
const DELTA:="market-session-delta-token"
const EPSILON:="market-session-epsilon-token"
const ZETA:="market-session-zeta-token"
const DAY:=1440.0
const START_DAY:=2
const START_TIME:=3.0*DAY-240.0
const TIME_SCALE:=30.0
const HALF:=Vector2(0.5,0.5)
const GARDEN_REGION:="star_garden"
const EPSILON_AT:=Vector2(30.5,29.5)
const ALPHA_BAG:={"radish":10,"soup":1,"bluebell":2,"egg":1,"carrot":1,"wood":5,"radish_seed":2}
const BETA_BAG:={"radish":4,"carrot":2,"wood":2}
const REGISTER:=Vector2i(37,32)
const DELTA_BAG:={"radish":2}
const EPSILON_BAG:={"radish":2}
const ZETA_BAG:={"radish":2}
## Alpha's stall on day 2 (theme flower): 7 pieces, visitors_for(2)=5. Settlement
## order is themed first, then by id: bluebell, egg, radish, soup, bluebell.
const ALPHA_STOCK:={"radish":3,"soup":1,"bluebell":2,"egg":1}
const ALPHA_SOLD:={"bluebell":2,"egg":1,"radish":1,"soup":1}
const ALPHA_LEFT:={"radish":2}
## Beta's stall: radish 3 + carrot 1, then takes back 1 radish -> 3 pieces, all sold.
const BETA_STOCK:={"radish":2,"carrot":1}
const BETA_SOLD:={"carrot":1,"radish":2}

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
	func region()->String:
		return str(session.snapshot.get("region_id",""))
	func pos()->Vector2:
		var p:=me()
		return Vector2(float(p.get("x",-99.0)),float(p.get("y",-99.0)))
	func bag()->Dictionary:
		var inv=me().get("inventory",{})
		return inv if inv is Dictionary else {}
	func coins()->int:
		return int(me().get("coins",-1))
	func clock()->float:
		return float(session.snapshot.get("time",-1.0))
	func market()->Dictionary:
		var v=session.snapshot.get("own_market",null)
		return v if v is Dictionary else {}

var checks:=0
var failures:=0
var serial:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var stall:=Vector2i.ZERO
var stand_a:=Vector2.ZERO
var stand_b:=Vector2.ZERO
var wrong:=Vector2i.ZERO
var far_spot:=Vector2.ZERO
var lock_stall:=Vector2i.ZERO
var lock_stand:=Vector2.ZERO
var prices:Dictionary={}

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
	Engine.time_scale=1.0
	print("MARKET_STALL_SESSION watchdog fired before completion")
	print("MARKET_STALL_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	Engine.time_scale=1.0
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("MARKET_STALL_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("MARKET_STALL_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("MARKET_STALL_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

static func stand_near(w,cell:Vector2i,skip:Vector2=Vector2.INF)->Vector2:
	for off:Vector2 in [Vector2(0.5,1.5),Vector2(1.5,1.5),Vector2(-0.5,1.5),Vector2(1.5,0.5),Vector2(-0.5,0.5),Vector2(0.5,-0.5),Vector2(1.5,-0.5),Vector2(-0.5,-0.5)]:
		var at:Vector2=Vector2(cell)+off
		if at!=skip and w.can_stand(at):return at
	return Vector2.ZERO

func plan()->bool:
	var probe:=folder.path_join("probe.json")
	if not expect(seed_world(probe,true,{}),"probe fixture saved"):return false
	var w:=World.new()
	if not expect(w.load_world(probe),"probe fixture loads like the server's save"):return false
	stall=MARKET.cell_for(w.state)
	expect(stall in MARKET.CANDIDATES and stall==World.market_cell(w.state) and stall==MARKET.active_cell(w.state),"stall cell %s is a MARKET candidate on the picnic probe"%str(stall))
	stand_a=stand_near(w,stall)
	stand_b=stand_near(w,stall,stand_a)
	for spot:Array in [["alpha",stand_a],["beta",stand_b]]:
		var at:Vector2=spot[1]
		if not expect(at!=Vector2.ZERO and at.distance_to(Vector2(stall)+HALF)<=3.2,"%s stand %s is standable and within 3.2 of the stall"%[spot[0],str(at)]):return false
	wrong=stall
	for step:Vector2i in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.DOWN,Vector2i.UP]:
		if stand_a.distance_to(Vector2(stall+step)+HALF)<=3.2:
			wrong=stall+step
			break
	if not expect(wrong!=stall,"a neighbour cell %s of the stall within alpha's reach"%str(wrong)):return false
	for dx in range(5,12):
		for dy in [0,1,-1,2,-2]:
			var at:=Vector2(stall+Vector2i(dx,dy))+HALF
			if far_spot==Vector2.ZERO and w.can_stand(at):far_spot=at
	if not expect(far_spot!=Vector2.ZERO and far_spot.distance_to(Vector2(stall)+HALF)>3.2,"a standable home spot %s out of the stall's reach"%str(far_spot)):return false
	var probe_locked:=folder.path_join("probe-locked.json")
	if not expect(seed_world(probe_locked,false,{}),"picnic-less probe fixture saved"):return false
	var lw:=World.new()
	if not expect(lw.load_world(probe_locked),"picnic-less probe loads like the server's save"):return false
	lock_stall=MARKET.cell_for(lw.state)
	expect(MARKET.active_cell(lw.state)==MARKET.NO_CELL,"picnic-less probe has no active stall cell")
	lock_stand=stand_near(lw,lock_stall)
	return expect(lock_stall in MARKET.CANDIDATES and lock_stand!=Vector2.ZERO,"picnic-less stand %s beside candidate cell %s"%[str(lock_stand),str(lock_stall)])

func seed_world(path:String,picnic:bool,people:Dictionary)->bool:
	var w:=World.new()
	w.save_path=path
	w.state["picnic"]=picnic
	w.state["time"]=START_TIME
	for token:String in people:
		var spec:Dictionary=people[token]
		w.add_player(token,str(spec.name))
		var p:Dictionary=w.state.players[token]
		var at:Vector2=spec.at
		p["x"]=at.x
		p["y"]=at.y
		p["inventory"]=(spec.inv as Dictionary).duplicate()
		if spec.has("region"):p["region"]=str(spec.region)
	if people.has(BETA):
		for part in range(2):
			w.state.objects[World.key(REGISTER+Vector2i(part,0))]={
				"type":World.INDUSTRY.COAST_REGISTER,"owner":BETA,"items":{},"register_part":part,
			}
	w.active_tokens.clear()
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:return false
	for token:String in people:
		if parsed.players.get(token,{}).has("market"):return false
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
	await wait_until(func():return not c.session.own_id.is_empty() and not c.me().is_empty() and not c.market().is_empty(),8.0)
	return c

func joined(c:Client)->bool:
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and not c.market().is_empty()

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

func fast_forward(condition:Callable,seconds:float)->bool:
	Engine.time_scale=TIME_SCALE
	var ok:=await wait_until(condition,seconds)
	Engine.time_scale=1.0
	await pause(0.2)
	return ok

# ---------------------------------------------------------------- helpers --

static func canon(d:Variant)->Dictionary:
	var out:={}
	if not d is Dictionary:return {"<invalid>":-1}
	for item in d:
		if int(d[item])!=0:out[str(item)]=int(d[item])
	return out

static func plus(a:Dictionary,b:Dictionary,sign:int=1)->Dictionary:
	var out:=canon(a)
	for item in b:
		out[str(item)]=int(out.get(str(item),0))+sign*int(b[item])
		if int(out[str(item)])==0:out.erase(str(item))
	return out

static func text(d:Variant)->String:
	return JSON.stringify(d,"",true)

static func norm_report(r:Variant)->Variant:
	if not r is Dictionary:return "<invalid>"
	if r.is_empty():return {}
	return {"day":int(r.get("day",-99)),"visitors":int(r.get("visitors",-99)),"stalls":int(r.get("stalls",-99)),
		"theme":str(r.get("theme","")),"coins":int(r.get("coins",-99)),"sold":canon(r.get("sold",null)),"keys":r.size()}

## Received own_market view normalised (prices omitted; they are checked separately).
static func mrow(v:Dictionary)->Dictionary:
	if v.is_empty():return {"<missing>":true}
	return {"unlocked":v.get("unlocked"),"day":int(v.get("day",-99)),"theme":str(v.get("theme","")),
		"open":v.get("open"),"pending":v.get("pending"),"stalls_today":int(v.get("stalls_today",-99)),
		"visitors_estimate":int(v.get("visitors_estimate",-99)),"stock":canon(v.get("stock",null)),
		"stock_count":int(v.get("stock_count",-99)),"till":int(v.get("till",-99)),"total":int(v.get("total",-99)),
		"report":norm_report(v.get("report",null))}

static func pieces(stock:Dictionary)->int:
	var n:=0
	for item in stock:n+=int(stock[item])
	return n

static func want_row(day:int,stock:Dictionary,opened:bool,pending:bool,stalls:int,till:int,total:int,report:Dictionary)->Dictionary:
	var est:=MARKET.visitors_for(maxi(stalls,1)) if opened else MARKET.visitors_for(stalls+1)
	return {"unlocked":true,"day":day,"theme":MARKET.theme_of(day),"open":opened,"pending":pending,"stalls_today":stalls,
		"visitors_estimate":est,"stock":canon(stock),"stock_count":pieces(stock),"till":till,"total":total,"report":norm_report(report)}

func price(item:String,day:int)->int:
	return MARKET.price_for(int(prices[item]),MARKET.category_of(item,prices),day)

func coins_for(sold:Dictionary,day:int)->int:
	var n:=0
	for item in sold:n+=price(item,day)*int(sold[item])
	return n

func expect_row(c:Client,want:Dictionary,label:String)->bool:
	var got:=text(mrow(c.market()))
	return expect(got==text(want),"%s: %s's own_market is exactly %s (got %s)"%[label,c.label,text(want),got])

static func label_of(item:String)->String:
	return str(World.NAMES.get(item,item))

static func stock_msg(item:String,count:int)->String:
	return "%s ×%d 擺上攤位了。"%[label_of(item),count]

static func take_msg(item:String,count:int)->String:
	return "收回%s ×%d，放回背包了。"%[label_of(item),count]

static func open_msg(day:int,stalls:int)->String:
	return "攤位開張了！今天的主題是「%s」，預計有 %d 位客人來逛，換日時結算。"%[MARKET.CATEGORY_NAMES[MARKET.theme_of(day)],MARKET.visitors_for(stalls)]

static func unsellable_msg(item:String)->String:
	return "%s不能擺上市集攤位；攤位只收農漁產、料理和花。"%label_of(item)

static func short_msg(item:String)->String:
	return "背包裡的%s不夠，先去收成或料理再來上架。"%label_of(item)

const MSG_KINDS:="攤位最多擺 4 種東西，先收回一種再上架。"
const MSG_OPENED:="今天已經開張了，明天再來開下一輪。"
const MSG_EMPTY_OPEN:="攤位上還沒有東西，先上架再開張。"
const MSG_EMPTY_TILL:="錢箱裡還沒有鈴幣，開張營業、換日結算後再來收。"
const MSG_BAD_STOCK:="請重新選擇要上架的物品和數量。"
const MSG_BAD_TAKE:="請重新選擇要收回的物品和數量。"
const MSG_BAD_OP:="請重新操作市集攤位。"

## Exact refusal; whole bag, coins and own_market unchanged for the actor and every watcher.
func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:Array=everyone.map(func(x):return [text(canon(x.bag())),x.coins(),text(mrow(x.market()))])
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	var same:=true
	for i in everyone.size():
		var x:Client=everyone[i]
		if [text(canon(x.bag())),x.coins(),text(mrow(x.market()))]!=marks[i]:same=false
	expect(same,"%s: every bag, coin purse and own_market unchanged in all watching snapshots"%label)

## Successful stock/take: exact message, exact bag delta, exact stock delta; watchers unchanged.
func move(c:Client,action:String,item:String,count:int,label:String,watchers:Array,site:=MARKET.NO_CELL)->Dictionary:
	await settle([c]+watchers)
	var bag:=canon(c.bag())
	var stock:=canon(c.market().get("stock",{}))
	var others:Array=watchers.map(func(x):return [text(canon(x.bag())),x.coins(),text(mrow(x.market()))])
	var r:=await act(c,action,stall if site==MARKET.NO_CELL else site,"%s:%d"%[item,count])
	var stocking:=action=="market_stock"
	expect(r.ok and r.message==(stock_msg(item,count) if stocking else take_msg(item,count)),"%s: %s %s ×%d over the network (%s)"%[label,action,item,count,r.message])
	await settle([c]+watchers)
	var sign:=-1 if stocking else 1
	expect(canon(c.bag())==plus(bag,{item:count},sign),"%s: %s's bag changed by exactly %+d %s (%s)"%[label,c.label,sign*count,item,text(canon(c.bag()))])
	expect(canon(c.market().get("stock",{}))==plus(stock,{item:count},-sign),"%s: %s's stall stock changed by exactly %+d %s (%s)"%[label,c.label,-sign*count,item,text(canon(c.market().get("stock",{})))])
	var same:=true
	for i in watchers.size():
		var x:Client=watchers[i]
		if [text(canon(x.bag())),x.coins(),text(mrow(x.market()))]!=others[i]:same=false
	expect(same,"%s: watchers' bags, coins and own_market unchanged"%label)
	return r

## Privacy of `c`'s received snapshot.
func private_check(c:Client,others:Array,label:String)->void:
	var people=c.session.snapshot.get("players",{})
	var clean:=people is Dictionary
	if clean:
		for id in people:
			var person=people[id]
			if not person is Dictionary or person.has("market") or person.has("own_market") or person.has("till") or person.has("stock"):clean=false
	expect(clean,"%s: no players entry in %s's snapshot carries market / own_market / till / stock"%[label,c.label])
	for o:Client in others:
		expect(people is Dictionary and people.has(o.session.own_id),"%s: %s's snapshot lists %s publicly"%[label,c.label,o.label])
	var dump:=JSON.stringify(c.session.snapshot)
	expect(dump.count("\"own_market\"")==1 and dump.count("\"till\"")==1,"%s: %s's snapshot carries exactly one own_market and one till (its own)"%[label,c.label])
	expect(not dump.contains("\"open_day\""),"%s: %s's snapshot carries no raw player.market record field (open_day)"%[label,c.label])
	var leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no private token"%[label,c.label])

static func disk_market(person:Variant)->Variant:
	if not person is Dictionary or not person.has("market"):return null
	var m=person.market
	if not m is Dictionary:return "<invalid>"
	var keys:Array=m.keys().map(func(k):return str(k))
	keys.sort()
	return {"keys":keys,"stock":canon(m.get("stock",null)),"open_day":int(m.get("open_day",-99)),"pending":m.get("pending"),
		"till":int(m.get("till",-99)),"total":int(m.get("total",-99)),"report":norm_report(m.get("report",null))}

## Stall guests drawn by `c` from its own received snapshot (as world_view.gd does).
static func guests(c:Client)->Array:
	return MarketVisitors.plan(c.market(),c.clock())

## Journal 「我的市集攤位」 card lines `c` builds from its own snapshot (as life_ui_tasks.gd does).
static func card(c:Client)->Array:
	return MarketVisitors.summary_lines(c.market(),World.NAMES)

## Exact guest count; when non-empty: distinct slots, exactly one wish, of today's theme.
func expect_guests(c:Client,count:int,label:String)->void:
	var g:Array=guests(c)
	if count==0:
		expect(g.is_empty(),"%s: %s's own snapshot draws no stall guests (stalls_today %d, got %d)"%[label,c.label,int(c.market().get("stalls_today",-1)),g.size()])
		return
	var slots:Array=[]
	var wishes:Array=[]
	for guest in g:
		var row:Dictionary=guest if guest is Dictionary else {}
		slots.append(int(row.get("slot",-1)))
		if not str(row.get("wish","")).is_empty():wishes.append(str(row.get("wish","")))
	var distinct:={}
	for s in slots:distinct[s]=true
	var today:=MARKET.day(c.clock())
	var themed:bool=wishes.size()==1 and MARKET.category_of(str(wishes[0]))==MARKET.theme_of(today)
	expect(g.size()==count and distinct.size()==count and themed,"%s: %s's own snapshot draws %d guests in distinct slots, one wishing for a %s item (got %d, slots %s, wishes %s)"%[label,c.label,count,MARKET.theme_of(today),g.size(),str(slots),str(wishes)])

## Expected card lines from the reader's own data (formats of market_visitors.gd).
static func want_card(day:int,status:String,till:int,total:int,report:Dictionary)->Array:
	var lines:Array=[]
	lines.append("今日主題：%s（主題商品＋30%%） · 明日主題：%s"%[MARKET.CATEGORY_NAMES[MARKET.theme_of(day)],MARKET.CATEGORY_NAMES[MARKET.theme_of(day+1)]])
	lines.append(status)
	var money:="待領營收 %d 鈴幣 · 累計營收 %d 鈴幣"%[till,total]
	if till>0:money+="（到攤位領取）"
	lines.append(money)
	if report.is_empty():
		lines.append("上一輪結算：還沒有結算紀錄")
		return lines
	var theme_id:=str(report.get("theme",""))
	lines.append("上一輪結算・第 %d 日（%s）：來客 %d 位 · %d 攤同場 · 收入 %d 鈴幣"%[int(report.get("day",0))+1,str(MARKET.CATEGORY_NAMES.get(theme_id,theme_id)),int(report.get("visitors",0)),int(report.get("stalls",0)),int(report.get("coins",0))])
	var sold:Dictionary=report.get("sold",{}) if report.get("sold",{}) is Dictionary else {}
	var keys:Array=sold.keys()
	keys.sort()
	var parts:=PackedStringArray()
	for item in keys:parts.append("%s ×%d"%[label_of(str(item)),int(sold[item])])
	lines.append("賣出：%s"%("、".join(parts) if not parts.is_empty() else "這一輪沒有賣出"))
	return lines

static func status_closed(count:int)->String:
	return "今天還沒開張 · 攤上有 %d 件，到廣場西側的攤位開張"%count if count>0 else "今天還沒開張 · 攤上沒有東西"

static func status_open(count:int,stalls:int)->String:
	return "今天營業中 · 攤上 %d 件 · 全島 %d 攤開張 · 預估來客 %d 位，午夜結算"%[count,stalls,MARKET.visitors_for(maxi(stalls,1))]

func expect_card(c:Client,want:Array,label:String)->bool:
	var got:=text(card(c))
	return expect(got==text(want),"%s: %s's journal market card is exactly %s (got %s)"%[label,c.label,text(want),got])

## Market visitors are derived client-side. Guest-room progression is unrelated to the market.
func expect_no_guest_keys(c:Client,label:String)->void:
	var extra:Array=[]
	for k in c.session.snapshot.keys():
		var key:=str(k).to_lower()
		if key in ["own_guest_room","own_guest_cloth"]:continue
		if key.contains("guest") or key.contains("visitor") or key.contains("customer"):extra.append(str(k))
	expect(extra.is_empty(),"%s: %s's snapshot has no guest/visitor/customer top-level key (found %s)"%[label,c.label,str(extra)])
	var mk:Array=c.market().keys().map(func(k):return str(k))
	mk.sort()
	expect(mk==OWN_MARKET_KEYS,"%s: %s's own_market has exactly the MARKET.view keys (got %s)"%[label,c.label,str(mk)])

## Stall tags `c` draws from its own snapshot (as the world view does).
static func shelf_of(c:Client)->Array:
	return MarketDisplay.shelf(c.market())

static func remark_of(c:Client)->String:
	return MarketDisplay.remark(c.market(),World.NAMES)

static func remark_line_of(c:Client)->String:
	return MarketDisplay.remark_line(c.market(),World.NAMES)

## Whole displayed state (shelf tags incl. slot/offset/themed + panel line).
static func display(c:Client)->String:
	return var_to_str(shelf_of(c))+"\n"+remark_line_of(c)

static func shelf_rows(c:Client)->Array:
	var rows:Array=[]
	for e in shelf_of(c):
		var d:Dictionary=e if e is Dictionary else {}
		rows.append([str(d.get("item","")),int(d.get("count",-1))])
	return rows

static func want_shelf(stock:Dictionary)->Array:
	var own:Dictionary=canon(stock)
	var keys:Array=own.keys()
	keys.sort()
	var rows:Array=[]
	for item in keys:rows.append([str(item),int(own[item])])
	return rows

## Shelf equals `stock` sorted by id; slots 0..n-1; themed flag = today's theme.
func expect_shelf(c:Client,stock:Dictionary,label:String)->bool:
	var got:String=text(shelf_rows(c))
	var want:String=text(want_shelf(stock))
	var theme:String=MARKET.theme_of(int(c.market().get("day",-99)))
	var shape:=true
	var entries:Array=shelf_of(c)
	for i in entries.size():
		var d:Dictionary=entries[i] if entries[i] is Dictionary else {}
		var item:String=str(d.get("item",""))
		var themed:bool=MARKET.category_of(item,prices)==theme
		if int(d.get("slot",-1))!=i or d.get("themed")!=themed or not d.get("offset") is Vector2:shape=false
	return expect(got==want and shape,"%s: %s's stall shelf shows exactly its own stock %s in id order with slot/themed/offset (got %s, shape ok %s)"%[label,c.label,want,got,str(shape)])

## Expected remark recomputed from the reader's own stock and the market rules.
func want_remark(day:int,stock:Dictionary,opened:bool,stalls:int)->String:
	if stalls<=0:return ""
	if not opened:return MarketDisplay.REMARK_CLOSED
	var own:Dictionary=canon(stock)
	var keys:Array=own.keys()
	keys.sort()
	if keys.is_empty():return MarketDisplay.REMARK_EMPTY
	var theme:String=MARKET.theme_of(day)
	var theme_name:String=str(MARKET.CATEGORY_NAMES.get(theme,theme))
	var themed:Array=[]
	for item in keys:
		if MARKET.category_of(str(item),prices)==theme:themed.append(str(item))
	if not themed.is_empty():
		return MarketDisplay.REMARK_THEMED%[theme_name,label_of(str(themed[posmod(day,themed.size())]))]
	if keys.size()>=MarketDisplay.VARIETY_KINDS:return MarketDisplay.REMARK_VARIETY
	return MarketDisplay.REMARK_OTHER%[label_of(str(keys[posmod(day,keys.size())])),theme_name]

func expect_remark(c:Client,want:String,label:String,accent:String="")->bool:
	var got:String=remark_of(c)
	var line:String=remark_line_of(c)
	var want_line:String="" if want.is_empty() else MarketDisplay.REMARK_PREFIX+want+(" "+accent if not accent.is_empty() else "")+MarketDisplay.REMARK_NOTE
	return expect(got==want and line==want_line,"%s: %s's stall remark is exactly '%s' (got '%s', line '%s')"%[label,c.label,want,got,line])

## `reader`'s market fields (minus the reader's own settlement report) never carry
## `owner_stock`'s counts (unless it is the reader's own identical count) and its
## shelf shows none of the owner-only items.
func expect_shelf_private(reader:Client,owner_stock:Dictionary,reader_stock:Dictionary,label:String)->void:
	var own:Dictionary=canon(reader_stock)
	var needles:Array=[]
	for item in owner_stock:
		if int(own.get(str(item),0))!=int(owner_stock[item]):needles.append("\"%s\":%d"%[str(item),int(owner_stock[item])])
	if pieces(owner_stock)!=pieces(own):needles.append("\"stock_count\":%d"%pieces(owner_stock))
	var hits:Array=[]
	var fields:Array=[]
	for k in reader.session.snapshot.keys():
		if not str(k).to_lower().contains("market"):continue
		fields.append(str(k))
		var value:Variant=reader.session.snapshot[k]
		if value is Dictionary and (value as Dictionary).has("report"):
			# The reader's own settlement report may coincide with the other's counts (e.g. sold radish ×2).
			value=(value as Dictionary).duplicate(true)
			(value as Dictionary).erase("report")
		var dump:String=JSON.stringify(value)
		for n in needles:
			if dump.contains(str(n)):hits.append("%s:%s"%[str(k),str(n)])
	expect(fields.has("own_market") and hits.is_empty(),"%s: %s's market fields %s carry none of the other stall's stocked counts %s (hits %s)"%[label,reader.label,str(fields),str(needles),str(hits)])
	var shown:Array=[]
	for row in shelf_rows(reader):
		if not own.has(str(row[0])):shown.append(row[0])
	expect(shown.is_empty(),"%s: %s's shelf shows no goods outside its own stock (got %s)"%[label,reader.label,str(shown)])

## The display is derived client-side: no shelf/remark/display/decor top-level key.
func expect_no_display_keys(c:Client,label:String)->void:
	var extra:Array=[]
	for k in c.session.snapshot.keys():
		var key:=str(k).to_lower()
		if key.contains("shelf") or key.contains("remark") or key.contains("display") or key.contains("decor"):extra.append(str(k))
	expect(extra.is_empty(),"%s: %s's snapshot has no shelf/remark/display/decor top-level key (found %s)"%[label,c.label,str(extra)])
	var mk:Array=c.market().keys().map(func(k):return str(k))
	mk.sort()
	expect(mk==OWN_MARKET_KEYS,"%s: %s's own_market keys unchanged by the stall display (got %s)"%[label,c.label,str(mk)])

## Everything decor must never change: bag, purse, whole own_market view, prices, till, total.
static func fp(c:Client,with_decor:bool=true)->String:
	var m:Dictionary=c.market()
	var parts:Array=[canon(c.bag()),c.coins(),mrow(m),m.get("prices",null),m.get("till",null),m.get("total",null)]
	if with_decor:parts.append(m.get("decor","<none>"))
	return text(parts)

## `want` null = no decor key at all; otherwise own_market has exactly OWN_MARKET_KEYS+"decor" == want.
## Never a public players field or top-level snapshot key.
func expect_decor(c:Client,want:Variant,label:String)->void:
	var m:Dictionary=c.market()
	var keys:Array=m.keys().map(func(k):return str(k))
	keys.sort()
	var want_keys:Array=OWN_MARKET_KEYS.duplicate()
	if want!=null:want_keys.append("decor")
	want_keys.sort()
	var ok:bool=keys==want_keys
	if want==null:ok=ok and not m.has("decor")
	else:ok=ok and text(m.get("decor"))==text(want)
	expect(ok,"%s: %s's own_market decor is %s with keys %s (got %s)"%[label,c.label,text(want),str(want_keys),text(m.get("decor","<none>"))])
	var people=c.session.snapshot.get("players",{})
	var clean:=people is Dictionary
	if clean:
		for id in people:
			var person=people[id]
			if not person is Dictionary or person.has("decor") or person.has("market_decor"):clean=false
	for k in c.session.snapshot.keys():
		if str(k).to_lower().contains("decor"):clean=false
	expect(clean,"%s: %s's snapshot has no decor / market_decor in any players entry or top-level key"%[label,c.label])

## Refused market_decor: reply exact, decor state (absent or not) and everything else unchanged.
func decor_refuse(c:Client,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:Array=everyone.map(func(x):return fp(x))
	await refuse(c,"market_decor",p,extra,message,label,watchers)
	var same:=true
	for i in everyone.size():
		if fp(everyone[i])!=marks[i]:same=false
	expect(same,"%s: bag, purse, stock, prices, till, total and decor all unchanged for every client"%label)

## Accepted market_decor: exact message, own decor == want, nothing else changes, watchers get no decor.
func decor_set(c:Client,extra:String,message:String,want:Dictionary,watchers:Array,label:String)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:Array=everyone.map(func(x):return fp(x,false))
	var r:=await act(c,"market_decor",stall,extra)
	expect(r.replied and r.ok and str(r.message)==message,"%s: '%s' accepted with '%s' (got ok=%s '%s')"%[label,extra,message,str(r.ok),str(r.message)])
	await settle(everyone)
	var same:=true
	for i in everyone.size():
		if fp(everyone[i],false)!=marks[i]:same=false
	expect(same,"%s: bag, purse, stock, prices, till and total unchanged for every client"%label)
	expect_decor(c,want,label)
	for w:Client in watchers:expect_decor(w,null,label+" watcher (never receives the customiser's decor)")

# --------------------------------------------------------------- scenario --

var alpha:Client
var beta:Client
var gamma:Client
var delta:Client
var epsilon:Client
var zeta:Client

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("market-stall-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	prices=MARKET.sale_prices()
	# Fixture guards for the chosen items and day.
	expect(MARKET.theme_of(START_DAY)=="flower" and MARKET.day(START_TIME)==START_DAY,"fixture day %d has theme flower"%START_DAY)
	expect(MARKET.category_of("radish")=="produce" and MARKET.category_of("carrot")=="produce" and MARKET.category_of("egg")=="produce" and MARKET.category_of("soup")=="dish" and MARKET.category_of("bluebell")=="flower","fixture items: radish/carrot/egg produce, soup dish, bluebell flower")
	expect(not MARKET.sellable("wood") and not MARKET.sellable("radish_seed"),"fixture items: wood and radish_seed are not sellable")
	if not plan():return false
	save_path=folder.path_join("world.json")
	var seeded:=seed_world(save_path,true,{ALPHA:{"name":"alpha","at":stand_a,"inv":ALPHA_BAG},BETA:{"name":"beta","at":stand_b,"inv":BETA_BAG},
		DELTA:{"name":"delta","at":far_spot,"inv":DELTA_BAG},EPSILON:{"name":"epsilon","at":EPSILON_AT,"inv":EPSILON_BAG,"region":GARDEN_REGION}})
	if not expect(seeded,"SEEDED FIXTURE (picnic, time, positions, bags; no market) written to TEMP and accepted by SaveSchema.validate"):return false
	var port:=start_server()
	expect(port>0,"server Session hosts on 127.0.0.1 with the websocket transport")
	if port==0:return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback and received their own snapshot with own_market")
	if not joined(alpha) or not joined(beta):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and beta.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws,"server and both clients use WebSocketMultiplayerPeer")
	expect(server.multiplayer.is_server() and not alpha.session.multiplayer.is_server() and not beta.session.multiplayer.is_server(),"one server, two remote clients")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World (snapshots only)")
	await settle([alpha,beta])
	print("MARKET_STALL_SESSION_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d clients=2(+late joiner,+2 refusal islanders,+picnic-less run) fixture=SEEDED(picnic,time=%.0f,positions,bags) stall=%s clock=Engine.time_scale %.0fx for the day boundary shutdown=normal-only(not crash durability)"%["websocket" if ws else "UNEXPECTED",port,START_TIME,str(stall),TIME_SCALE])
	var S:=stall
	var fresh:=want_row(START_DAY,{},false,false,0,0,0,{})

	# 1. Fresh, private own_market for each client.
	for c:Client in [alpha,beta]:
		var other:Client=beta if c==alpha else alpha
		expect(c.region()==Regions.HOME and MARKET.day(c.clock())==START_DAY,"%s at home on world day %d (%.1f)"%[c.label,START_DAY,c.clock()])
		expect(World.market_cell(c.session.snapshot)==S,"%s derives the same stall cell %s from its own snapshot"%[c.label,str(S)])
		expect(c.pos().distance_to(Vector2(S)+HALF)<=3.2,"%s stands within reach of the stall (%s)"%[c.label,str(c.pos())])
		expect_row(c,fresh,"case 1 fresh")
		var pv=c.market().get("prices",{})
		expect(pv is Dictionary and pv.has("bluebell") and int(pv.bluebell.get("price",-1))==price("bluebell",START_DAY) and pv.bluebell.get("themed")==true and not pv.has("wood"),"%s's own price list: themed bluebell %d, no wood"%[c.label,price("bluebell",START_DAY)])
		private_check(c,[other],"case 1")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and canon(beta.bag())==canon(BETA_BAG),"preset bags arrive unchanged in the own snapshots")
	# Stall guests / journal card on fresh clients: nobody open, identical own data.
	var fresh_card:=want_card(START_DAY,status_closed(0),0,0,{})
	for c:Client in [alpha,beta]:
		expect_guests(c,0,"case 1 fresh")
		expect(card(c).size()==4,"case 1 %s's journal market card has 4 lines (got %d)"%[c.label,card(c).size()])
		expect_card(c,fresh_card,"case 1 fresh")
		expect_no_guest_keys(c,"case 1")
	expect(text(card(alpha))==text(card(beta)),"case 1 alpha's and beta's cards are identical while their own data is identical")
	# Stall display on fresh clients: empty shelf, no remark (nobody open), no display keys.
	for c:Client in [alpha,beta]:
		expect_shelf(c,{},"case 1 fresh")
		expect_remark(c,"","case 1 fresh (nobody open)")
		expect_no_display_keys(c,"case 1")
		expect_decor(c,null,"case 1 fresh (no decor by default)")
	var coins_a0:=alpha.coins()
	var coins_b0:=beta.coins()

	# 2. Alpha stocks a crop, a dish, a flower and an egg; only alpha changes.
	var r_radish:=await move(alpha,"market_stock","radish",3,"case 2 alpha",[beta])
	await move(alpha,"market_stock","soup",1,"case 2 alpha uses beta's register",[beta],REGISTER+Vector2i.RIGHT)
	await move(alpha,"market_stock","bluebell",2,"case 2 alpha",[beta])
	await move(alpha,"market_stock","egg",1,"case 2 alpha",[beta])
	expect_row(alpha,want_row(START_DAY,ALPHA_STOCK,false,false,0,0,0,{}),"case 2 alpha after stocking")
	expect_row(beta,fresh,"case 2 beta after alpha's stocking")
	expect(canon(alpha.bag())==plus(canon(ALPHA_BAG),ALPHA_STOCK,-1),"case 2 alpha's whole bag (%s)"%text(canon(alpha.bag())))
	expect(canon(beta.bag())==canon(BETA_BAG),"case 2 beta's whole bag untouched")
	private_check(beta,[alpha],"case 2 beta")
	private_check(alpha,[beta],"case 2 alpha")
	# Stocking is not opening: still no guests; only alpha's own status line changes.
	for c:Client in [alpha,beta]:expect_guests(c,0,"case 2 after alpha's stocking")
	expect_card(alpha,want_card(START_DAY,status_closed(pieces(ALPHA_STOCK)),0,0,{}),"case 2 alpha after stocking")
	expect_card(beta,fresh_card,"case 2 beta after alpha's stocking")
	var ca2:=card(alpha)
	var cb2:=card(beta)
	expect(ca2.size()==4 and cb2.size()==4 and ca2[0]==cb2[0] and ca2[2]==cb2[2] and ca2[3]==cb2[3] and ca2[1]!=cb2[1],"case 2 the two cards differ only in the status line (own stock count)")
	# Stall display after alpha's real stocking: alpha's shelf = her stock, beta's empty; no remark yet.
	expect_shelf(alpha,ALPHA_STOCK,"case 2 alpha after stocking")
	expect_shelf(beta,{},"case 2 beta after alpha's stocking")
	expect(shelf_of(beta).is_empty(),"case 2 beta's shelf is empty (got %s)"%var_to_str(shelf_of(beta)))
	expect_shelf_private(beta,ALPHA_STOCK,{},"case 2 beta")
	for c:Client in [alpha,beta]:expect_remark(c,"","case 2 stocked but nobody open")

	# 5. Replay of the radish stock's sequence number (raw request_action RPC).
	var bag_a:=canon(alpha.bag())
	var row_a:=text(mrow(alpha.market()))
	var marks:=[alpha.notices.size(),beta.notices.size()]
	var shown5:=[var_to_str(guests(alpha)),var_to_str(guests(beta)),text(card(alpha)),text(card(beta))]
	var display5:Array=[display(alpha),display(beta)]
	alpha.session.request_action.rpc_id(1,int(r_radish.sequence),"market_stock",S,"radish:3",alpha.region(),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==marks[0] and beta.notices.size()==marks[1],"case 5 re-sent radish stock (same sequence %d) gets no notice"%int(r_radish.sequence))
	expect(canon(alpha.bag())==bag_a and text(mrow(alpha.market()))==row_a,"case 5 re-sent stock moves no second radish (bag radish %d, stall radish %d)"%[int(alpha.bag().get("radish",0)),int(alpha.market().get("stock",{}).get("radish",0))])
	expect_row(beta,fresh,"case 5 beta after alpha's replay")
	var shown5_after:=[var_to_str(guests(alpha)),var_to_str(guests(beta)),text(card(alpha)),text(card(beta))]
	expect(shown5_after==shown5,"case 5 re-sent stock changes neither client's stall guests nor journal card")
	var display5_after:Array=[display(alpha),display(beta)]
	expect(display5_after==display5,"case 5 re-sent stock changes neither client's stall shelf nor remark (before %s, after %s)"%[str(display5),str(display5_after)])
	expect_shelf(alpha,ALPHA_STOCK,"case 5 alpha after the replay")
	expect_shelf(beta,{},"case 5 beta after alpha's replay")

	# 3a. Beta: open with an empty stall refused; then stock and take back.
	await refuse(beta,"market_open",S,"",MSG_EMPTY_OPEN,"case 3 beta opens an empty stall",[alpha])
	await move(beta,"market_stock","radish",3,"case 3 beta uses her register",[alpha],REGISTER)
	await move(beta,"market_stock","carrot",1,"case 3 beta",[alpha])
	await move(beta,"market_take","radish",1,"case 3 beta",[alpha])
	expect_row(beta,want_row(START_DAY,BETA_STOCK,false,false,0,0,0,{}),"case 3 beta after stocking")
	expect_row(alpha,want_row(START_DAY,ALPHA_STOCK,false,false,0,0,0,{}),"case 3 alpha after beta's stocking")
	expect_shelf(beta,BETA_STOCK,"case 3 beta after stocking and taking back")
	expect_shelf(alpha,ALPHA_STOCK,"case 3 alpha after beta's stocking")
	expect_shelf_private(beta,ALPHA_STOCK,BETA_STOCK,"case 3 beta")
	expect_shelf_private(alpha,BETA_STOCK,ALPHA_STOCK,"case 3 alpha")
	for c:Client in [alpha,beta]:expect_remark(c,"","case 3 both stocked, nobody open")

	# 3b. Rejections, state unchanged on both ends.
	await refuse(alpha,"market_stock",S,"wood:1",unsellable_msg("wood"),"case 3 alpha stocks raw wood",[beta])
	await refuse(alpha,"market_stock",S,"radish_seed:1",unsellable_msg("radish_seed"),"case 3 alpha stocks a radish_seed",[beta])
	await refuse(alpha,"market_stock",S,"carrot:2",short_msg("carrot"),"case 3 alpha stocks 2 carrots holding 1",[beta])
	await refuse(alpha,"market_stock",S,"soup:1",short_msg("soup"),"case 3 alpha stocks soup she no longer holds",[beta])
	await refuse(alpha,"market_stock",S,"carrot:1",MSG_KINDS,"case 3 alpha stocks a 5th kind (carrot)",[beta])
	await refuse(alpha,"market_stock",S,"radish:6","攤位最多擺 %d 件，現在還能再放 %d 件。"%[MARKET.MAX_STOCK,MARKET.MAX_STOCK-pieces(ALPHA_STOCK)],"case 3 alpha overfills past MAX_STOCK (7+6)",[beta])
	await refuse(alpha,"market_take",S,"soup:2","攤位上的%s沒有這麼多，請重新選擇數量。"%label_of("soup"),"case 3 alpha takes back more soup than stocked",[beta])
	await refuse(alpha,"market_stock",wrong,"radish:1",MARKET.WRONG_CELL,"case 3 alpha aims at the neighbour cell %s"%str(wrong),[beta])
	await refuse(alpha,"market_collect",S,"",MSG_EMPTY_TILL,"case 3 alpha collects an empty till",[beta])
	for bad:String in ["radish","radish:0","radish:13","radish:x",":1","radish:1:1","radish:01"]:
		await refuse(alpha,"market_stock",S,bad,MSG_BAD_STOCK,"case 3 malformed stock extra '%s'"%bad,[beta])
	await refuse(beta,"market_take",S,"radish:-1",MSG_BAD_TAKE,"case 3 malformed take extra 'radish:-1'",[alpha])
	await refuse(beta,"market_open",S,"now",MSG_BAD_OP,"case 3 open with an extra",[alpha])
	await refuse(beta,"market_collect",S,"all",MSG_BAD_OP,"case 3 collect with an extra",[alpha])
	# market_decor refusals (default-valued, malformed, unknown, wrong cell): no decor key appears.
	await decor_refuse(alpha,S,"cloth|natural","攤位已經是「原色棉布」了。","case 3 decor: default cloth again",[beta])
	await decor_refuse(alpha,S,"sign|plain","攤位已經是「素木招牌」了。","case 3 decor: default sign again",[beta])
	for bad:Array in [["","請選擇攤位布置。"],["cloth|indigo|x","請選擇攤位布置。"],["roof|indigo","沒有這種布置。"],["cloth|nope","沒有這個樣式。"],["cloth|plain","沒有這個樣式。"],["sign|indigo","沒有這個樣式。"],["cloth|","沒有這個樣式。"]]:
		await decor_refuse(alpha,S,str(bad[0]),str(bad[1]),"case 3 decor: invalid extra '%s'"%str(bad[0]),[beta])
	await decor_refuse(alpha,wrong,"cloth|indigo",MARKET.WRONG_CELL,"case 3 decor: wrong cell %s"%str(wrong),[beta])
	expect_decor(alpha,null,"case 3 alpha after every decor refusal")
	expect_decor(beta,null,"case 3 beta after alpha's decor refusals")
	# Too far (delta, home, out of reach) and wrong region (epsilon, star_garden).
	delta=await join("delta",DELTA,port)
	epsilon=await join("epsilon",EPSILON,port)
	expect(joined(delta) and joined(epsilon),"case 3 refusal islanders delta and epsilon join")
	if not joined(delta) or not joined(epsilon):return false
	await settle([alpha,beta,delta,epsilon])
	expect(delta.region()==Regions.HOME and delta.pos().distance_to(Vector2(S)+HALF)>3.2,"case 3 delta stands at home out of reach (%.1f tiles)"%delta.pos().distance_to(Vector2(S)+HALF))
	expect(epsilon.region()==GARDEN_REGION,"case 3 epsilon is in star_garden (%s)"%epsilon.region())
	await refuse(delta,"market_stock",S,"radish:1",MARKET.TOO_FAR,"case 3 delta stocks from too far",[alpha,beta])
	await refuse(epsilon,"market_stock",S,"radish:1",MARKET.WRONG_REGION,"case 3 epsilon stocks from star_garden",[alpha,beta])
	await decor_refuse(delta,S,"cloth|indigo",MARKET.TOO_FAR,"case 3 decor: delta from too far",[alpha,beta])
	await decor_refuse(epsilon,S,"cloth|indigo",MARKET.WRONG_REGION,"case 3 decor: epsilon from star_garden",[alpha,beta])
	for c:Client in [delta,epsilon]:
		expect_row(c,fresh,"case 3 %s after its refusal"%c.label)
		expect_decor(c,null,"case 3 %s after its decor refusal"%c.label)
	await leave(delta)
	await leave(epsilon)
	delta=null
	epsilon=null
	expect(await wait_until(func():return int(alpha.session.snapshot.get("room_population",0))==2,4.0),"case 3 delta and epsilon left (room population 2)")
	expect(canon(alpha.bag())==plus(canon(ALPHA_BAG),ALPHA_STOCK,-1) and canon(beta.bag())==plus(canon(BETA_BAG),BETA_STOCK,-1),"case 3 both bags exact after all refusals")

	# 4. Both open the same day.
	var r:=await act(alpha,"market_open",S)
	expect(r.ok and r.message==open_msg(START_DAY,1),"case 4 alpha opens first (%s)"%r.message)
	await settle([alpha,beta])
	expect_row(alpha,want_row(START_DAY,ALPHA_STOCK,true,true,1,0,0,{}),"case 4 alpha after opening")
	expect_row(beta,want_row(START_DAY,BETA_STOCK,false,false,1,0,0,{}),"case 4 beta sees one stall open")
	# One stall open: both snapshots draw the same 2 guests (island-wide data only).
	for c:Client in [alpha,beta]:expect_guests(c,2,"case 4 one stall open")
	var g4a:=var_to_str(guests(alpha))
	var g4b:=var_to_str(guests(beta))
	expect(g4a==g4b,"case 4 alpha's and beta's guest plans are identical with one stall open (alpha %s, beta %s)"%[g4a,g4b])
	expect_card(alpha,want_card(START_DAY,status_open(pieces(ALPHA_STOCK),1),0,0,{}),"case 4 alpha open")
	expect_card(beta,want_card(START_DAY,status_closed(pieces(BETA_STOCK)),0,0,{}),"case 4 beta not yet open")
	var cb4:=card(beta)
	var beta_text:="\n".join(PackedStringArray(cb4))
	var leak4:Array=[]
	for item in ALPHA_STOCK:
		if not BETA_STOCK.has(item) and beta_text.contains(label_of(str(item))):leak4.append(item)
	if beta_text.contains("攤上 %d 件"%pieces(ALPHA_STOCK)) or beta_text.contains("攤上有 %d 件"%pieces(ALPHA_STOCK)) or beta_text.contains("今天營業中"):leak4.append("alpha's stock count / open status")
	expect(cb4.size()==4 and str(cb4[1]).begins_with("今天還沒開張") and leak4.is_empty(),"case 4 beta's card says 今天還沒開張 and shows none of alpha's items, stock count or status (leaks %s)"%str(leak4))
	var ca4:=card(alpha)
	expect(ca4.size()==4 and str(ca4[1]).begins_with("今天營業中"),"case 4 alpha's card says 今天營業中")
	# Stall display with only alpha open: alpha's own remark, beta hears CLOSED.
	var flower_name:String=str(MARKET.CATEGORY_NAMES.get("flower","flower"))
	var remark_a4:String=want_remark(START_DAY,ALPHA_STOCK,true,1)
	expect(remark_a4==MarketDisplay.REMARK_THEMED%[flower_name,label_of("bluebell")],"case 4 fixture: alpha's expected remark is the themed bluebell line (%s)"%remark_a4)
	expect_remark(alpha,remark_a4,"case 4 alpha open")
	expect(not remark_of(alpha).is_empty() and remark_of(alpha)!=MarketDisplay.REMARK_CLOSED,"case 4 alpha's remark is non-empty and not CLOSED (%s)"%remark_of(alpha))
	expect_remark(beta,MarketDisplay.REMARK_CLOSED,"case 4 beta not yet open")
	expect_shelf(alpha,ALPHA_STOCK,"case 4 alpha open")
	expect_shelf(beta,BETA_STOCK,"case 4 beta not yet open")
	expect_shelf_private(beta,ALPHA_STOCK,BETA_STOCK,"case 4 beta while alpha is open")
	r=await act(beta,"market_open",S)
	expect(r.ok and r.message==open_msg(START_DAY,2),"case 4 beta opens second (%s)"%r.message)
	var beta_open_seq:int=int(r.sequence)
	await settle([alpha,beta])
	expect_row(alpha,want_row(START_DAY,ALPHA_STOCK,true,true,2,0,0,{}),"case 4 alpha with two stalls open")
	expect_row(beta,want_row(START_DAY,BETA_STOCK,true,true,2,0,0,{}),"case 4 beta with two stalls open")
	# Two stalls open: 3 guests for both, identical plans; cards show own stock only.
	for c:Client in [alpha,beta]:
		expect_guests(c,3,"case 4 two stalls open")
		expect_no_guest_keys(c,"case 4 two stalls open")
	expect(var_to_str(guests(alpha))==var_to_str(guests(beta)),"case 4 alpha's and beta's guest plans are identical with two stalls open")
	expect_card(alpha,want_card(START_DAY,status_open(pieces(ALPHA_STOCK),2),0,0,{}),"case 4 alpha with two stalls open")
	expect_card(beta,want_card(START_DAY,status_open(pieces(BETA_STOCK),2),0,0,{}),"case 4 beta with two stalls open")
	# Stall display with both open: each hears its own remark, sees only its own goods.
	var remark_b4:String=want_remark(START_DAY,BETA_STOCK,true,2)
	expect(remark_b4==MarketDisplay.REMARK_OTHER%[label_of("carrot"),flower_name],"case 4 fixture: beta's expected remark is the 'other' carrot line (%s)"%remark_b4)
	expect_remark(alpha,want_remark(START_DAY,ALPHA_STOCK,true,2),"case 4 alpha with two stalls open")
	expect_remark(beta,remark_b4,"case 4 beta with two stalls open")
	for c:Client in [alpha,beta]:
		var said:String=remark_of(c)
		expect(not said.is_empty() and said!=MarketDisplay.REMARK_CLOSED,"case 4 %s's remark is non-empty and not CLOSED with both open (%s)"%[c.label,said])
		expect_no_display_keys(c,"case 4 two stalls open")
	expect(remark_of(alpha)!=remark_of(beta),"case 4 alpha's and beta's remarks differ (own goods only)")
	expect_shelf(alpha,ALPHA_STOCK,"case 4 alpha with two stalls open")
	expect_shelf(beta,BETA_STOCK,"case 4 beta with two stalls open")
	expect_shelf_private(beta,ALPHA_STOCK,BETA_STOCK,"case 4 beta with two stalls open")
	expect_shelf_private(alpha,BETA_STOCK,ALPHA_STOCK,"case 4 alpha with two stalls open")
	# Replay of beta's market_open sequence (raw RPC): dropped, display unchanged.
	var display4:Array=[display(alpha),display(beta)]
	var rows4:Array=[text(mrow(alpha.market())),text(mrow(beta.market()))]
	var marks4:Array=[alpha.notices.size(),beta.notices.size()]
	beta.session.request_action.rpc_id(1,beta_open_seq,"market_open",S,"",beta.region(),int(beta.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==int(marks4[0]) and beta.notices.size()==int(marks4[1]),"case 4 re-sent market_open (same sequence %d) gets no notice"%beta_open_seq)
	expect([text(mrow(alpha.market())),text(mrow(beta.market()))]==rows4,"case 4 re-sent market_open changes neither own_market")
	var display4_after:Array=[display(alpha),display(beta)]
	expect(display4_after==display4,"case 4 re-sent market_open changes neither client's stall shelf nor remark (before %s, after %s)"%[str(display4),str(display4_after)])
	await refuse(alpha,"market_open",S,"",MSG_OPENED,"case 4 alpha opens twice the same day",[beta])
	await refuse(beta,"market_open",S,"",MSG_OPENED,"case 4 beta opens twice the same day",[alpha])
	await refuse(alpha,"market_collect",S,"",MSG_EMPTY_TILL,"case 4 alpha collects before settlement",[beta])
	private_check(alpha,[beta],"case 4 alpha")
	private_check(beta,[alpha],"case 4 beta")
	# 4b. Alpha customises her open themed stall: only her own_market gains decor.
	var remark_a4b:String=want_remark(START_DAY,ALPHA_STOCK,true,2)
	var shown4b:=[var_to_str(guests(alpha)),var_to_str(guests(beta)),text(card(alpha)),text(card(beta)),text(shelf_rows(alpha)),text(shelf_rows(beta))]
	var decor1:={"cloth":"indigo","sign":"plain"}
	var decor2:={"cloth":"indigo","sign":"flower"}
	var accent1:String=World.MARKET_DECOR.remark(decor1)
	var accent2:String=World.MARKET_DECOR.remark(decor2)
	expect(not accent1.is_empty() and not accent2.is_empty() and accent1!=accent2,"case 4 fixture: World.MARKET_DECOR has distinct remarks for indigo|plain and indigo|flower")
	await decor_set(alpha,"cloth|indigo","攤位換成「藍染布」了。",decor1,[beta],"case 4 alpha cloth|indigo")
	expect_remark(alpha,remark_a4b,"case 4 alpha's open stall with indigo cloth",accent1)
	expect(remark_line_of(alpha).contains(accent1),"case 4 alpha's open remark_line includes World.MARKET_DECOR.remark (%s)"%remark_line_of(alpha))
	expect_remark(beta,remark_b4,"case 4 beta's open remark carries no decor accent","")
	await decor_refuse(alpha,S,"cloth|indigo","攤位已經是「藍染布」了。","case 4 decor: same cloth again",[beta])
	await decor_set(alpha,"sign|flower","攤位換成「花飾招牌」了。",decor2,[beta],"case 4 alpha sign|flower")
	expect_remark(alpha,remark_a4b,"case 4 alpha's open stall with indigo cloth and flower sign",accent2)
	expect(remark_line_of(alpha).contains(accent2) and not remark_line_of(alpha).contains(accent1),"case 4 alpha's remark_line carries the new combination's remark")
	expect_remark(beta,remark_b4,"case 4 beta still has no decor accent","")
	var closed_view:Dictionary=alpha.market().duplicate(true)
	closed_view["open"]=false
	var closed_plain:Dictionary=closed_view.duplicate(true)
	closed_plain.erase("decor")
	expect(MarketDisplay.remark_line(closed_view,World.NAMES)==MarketDisplay.remark_line(closed_plain,World.NAMES),"case 4 the decor accent only shows on an open stall")
	expect(shown4b==[var_to_str(guests(alpha)),var_to_str(guests(beta)),text(card(alpha)),text(card(beta)),text(shelf_rows(alpha)),text(shelf_rows(beta))],"case 4 decor changes no guest plan, journal card or shelf")
	expect_row(alpha,want_row(START_DAY,ALPHA_STOCK,true,true,2,0,0,{}),"case 4 alpha after decor")
	expect_row(beta,want_row(START_DAY,BETA_STOCK,true,true,2,0,0,{}),"case 4 beta after alpha's decor")
	expect(canon(alpha.bag())==plus(canon(ALPHA_BAG),ALPHA_STOCK,-1) and alpha.coins()==coins_a0 and canon(beta.bag())==plus(canon(BETA_BAG),BETA_STOCK,-1) and beta.coins()==coins_b0,"case 4 decor leaves both bags and purses exact")
	private_check(alpha,[beta],"case 4 alpha after decor")
	private_check(beta,[alpha],"case 4 beta after alpha's decor")

	# 6. Alpha goes offline; the day boundary settles both stalls.
	var bag_a6:=canon(alpha.bag())
	var bag_b6:=canon(beta.bag())
	expect(MARKET.day(alpha.clock())==START_DAY and MARKET.day(beta.clock())==START_DAY,"guard: still world day %d before the fast-forward (time %.1f)"%[START_DAY,beta.clock()])
	await leave(alpha)
	expect(await wait_until(func():return int(beta.session.snapshot.get("room_population",0))==1,4.0),"case 6 server sees alpha leave (room population 1)")
	var crossed:=await fast_forward(func():
		var m:=beta.market()
		return int(m.get("day",-1))>=START_DAY+1 and m.get("report") is Dictionary and not (m.report as Dictionary).is_empty(),20.0)
	expect(crossed,"case 6 world day %d begins and beta's stall settles (time scale %.0fx)"%[START_DAY+1,TIME_SCALE])
	await settle([beta])
	var visitors:=MARKET.visitors_for(2)
	var coins_a:=coins_for(ALPHA_SOLD,START_DAY)
	var coins_b:=coins_for(BETA_SOLD,START_DAY)
	var report_a:={"day":START_DAY,"visitors":visitors,"stalls":2,"theme":MARKET.theme_of(START_DAY),"sold":ALPHA_SOLD,"coins":coins_a}
	var report_b:={"day":START_DAY,"visitors":visitors,"stalls":2,"theme":MARKET.theme_of(START_DAY),"sold":BETA_SOLD,"coins":coins_b}
	print("MARKET_STALL_SESSION_SETTLE visitors=%d alpha_coins=%d beta_coins=%d"%[visitors,coins_a,coins_b])
	expect(coins_a>0 and coins_b>0 and visitors==5,"case 6 expected settlement: 5 visitors each, alpha %d coins, beta %d coins"%[coins_a,coins_b])
	expect_row(beta,want_row(START_DAY+1,{},false,false,0,coins_b,coins_b,report_b),"case 6 beta after settlement (sold out)")
	expect(canon(beta.bag())==bag_b6 and beta.coins()==coins_b0,"case 6 settlement puts nothing in beta's bag or purse (till only)")
	expect_guests(beta,0,"case 6 beta after the midnight settlement")
	var rb:Dictionary=beta.market().get("report",{}) if beta.market().get("report",{}) is Dictionary else {}
	expect_card(beta,want_card(START_DAY+1,status_closed(0),coins_b,coins_b,rb),"case 6 beta after settlement (from her received report)")
	alpha=await join("alpha",ALPHA,port)
	expect(joined(alpha),"case 6 alpha rejoins with the same token")
	if not joined(alpha):return false
	await settle([alpha,beta])
	expect_row(alpha,want_row(START_DAY+1,ALPHA_LEFT,false,false,0,coins_a,coins_a,report_a),"case 6 alpha after offline settlement")
	expect(int(alpha.market().get("till",0))>0 and canon(alpha.market().get("stock",{}))==canon(ALPHA_LEFT),"case 6 alpha's till > 0 and unsold radish ×2 still on the stall")
	expect(canon(alpha.bag())==bag_a6 and alpha.coins()==coins_a0,"case 6 alpha's bag and purse unchanged by settlement")
	expect_row(beta,want_row(START_DAY+1,{},false,false,0,coins_b,coins_b,report_b),"case 6 beta unaffected by alpha's rejoin")
	# After settlement: no guests anywhere; each card carries only its reader's own report.
	for c:Client in [alpha,beta]:expect_guests(c,0,"case 6 after the midnight settlement")
	var ra:Dictionary=alpha.market().get("report",{}) if alpha.market().get("report",{}) is Dictionary else {}
	var ca6:=card(alpha)
	var cb6:=card(beta)
	expect(ca6.size()==5,"case 6 alpha's card has 5 lines after settlement (got %d)"%ca6.size())
	expect_card(alpha,want_card(START_DAY+1,status_closed(pieces(ALPHA_LEFT)),coins_a,coins_a,ra),"case 6 alpha after settlement (from her received report)")
	expect_card(alpha,want_card(START_DAY+1,status_closed(pieces(ALPHA_LEFT)),coins_a,coins_a,report_a),"case 6 alpha's card matches the expected settlement report")
	expect(ca6.size()==5 and str(ca6[3]).contains("收入 %d 鈴幣"%int(ra.get("coins",-1))) and str(ca6[3]).contains("來客 %d 位"%int(ra.get("visitors",-1))),"case 6 alpha's report line carries her received coins %d and visitors %d"%[int(ra.get("coins",-1)),int(ra.get("visitors",-1))])
	var beta_text6:="\n".join(PackedStringArray(cb6))
	var leak6:Array=[]
	if ca6.size()==5:
		for i in [3,4]:
			if cb6.has(ca6[i]):leak6.append(ca6[i])
	for item in ALPHA_SOLD:
		if not BETA_SOLD.has(item) and beta_text6.contains(label_of(str(item))):leak6.append(item)
	if coins_a!=coins_b and beta_text6.contains("收入 %d 鈴幣"%coins_a):leak6.append("alpha's coins")
	expect(cb6.size()==5 and leak6.is_empty(),"case 6 beta's card never shows alpha's report (leaks %s)"%str(leak6))
	expect_decor(alpha,decor2,"case 6 alpha's decor survives her offline settlement and rejoin")
	expect_decor(beta,null,"case 6 beta still has no decor")
	private_check(alpha,[beta],"case 6 alpha after rejoin")
	private_check(beta,[alpha],"case 6 beta")
	# Stall display after the midnight settlement: no remark; shelves = remaining stock.
	for c:Client in [alpha,beta]:expect_remark(c,"","case 6 after the midnight settlement")
	expect_shelf(alpha,ALPHA_LEFT,"case 6 alpha's unsold goods after settlement")
	expect_shelf(beta,{},"case 6 beta sold out")
	expect_shelf_private(beta,ALPHA_LEFT,{},"case 6 beta after settlement")

	# 7. Beta's actions leave alpha's till alone; alpha collects exactly once.
	var row_a7:=text(mrow(alpha.market()))
	await move(beta,"market_stock","radish",1,"case 7 beta restocks on day %d"%(START_DAY+1),[alpha])
	expect(text(mrow(alpha.market()))==row_a7,"case 7 alpha's till/stock untouched by beta's restock")
	r=await act(alpha,"market_collect",S)
	expect(r.ok and r.message=="從錢箱收下 %d 鈴幣。"%coins_a,"case 7 alpha collects her till (%s)"%r.message)
	await settle([alpha,beta])
	expect(alpha.coins()==coins_a0+coins_a,"case 7 alpha's coins rose by exactly the till %d (%d -> %d)"%[coins_a,coins_a0,alpha.coins()])
	expect_row(alpha,want_row(START_DAY+1,ALPHA_LEFT,false,false,0,0,coins_a,report_a),"case 7 alpha after collecting (till 0, total kept)")
	expect(beta.coins()==coins_b0 and int(beta.market().get("till",-1))==coins_b,"case 7 beta's purse and till untouched by alpha's collect")
	await refuse(alpha,"market_collect",S,"",MSG_EMPTY_TILL,"case 7 alpha's second collect",[beta])
	var beta_row:=want_row(START_DAY+1,{"radish":1},false,false,0,coins_b,coins_b,report_b)
	expect_row(beta,beta_row,"case 7 beta's own_market after the collect round")
	expect_shelf(beta,{"radish":1},"case 7 beta after restocking")
	expect_shelf(alpha,ALPHA_LEFT,"case 7 alpha after collecting")
	for c:Client in [alpha,beta]:expect_remark(c,"","case 7 nobody open on day %d"%(START_DAY+1))

	# 8. Normal shutdown, exact save, restart, rejoin, late joiner.
	await settle([alpha,beta])
	var final_rows:={ALPHA:text(mrow(alpha.market())),BETA:text(mrow(beta.market()))}
	var final_bags:={ALPHA:canon(alpha.bag()),BETA:canon(beta.bag())}
	var final_cards:={ALPHA:text(card(alpha)),BETA:text(card(beta))}
	var final_displays:Dictionary={ALPHA:display(alpha),BETA:display(beta)}
	expect(card(alpha).size()==5 and card(beta).size()==5,"case 8 both journal cards carry a settlement report before the shutdown")
	for c:Client in [alpha,beta]:expect_guests(c,0,"case 8 before the shutdown")
	await leave(alpha)
	await leave(beta)
	expect(await stop_server(),"case 8 server Session shuts down with a final save")
	var disk=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	expect(disk is Dictionary,"case 8 save file parses")
	if not disk is Dictionary:return false
	expect(Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"case 8 saved world passes SaveSchema")
	var keys:Array=MARKET.KEYS.duplicate()
	keys.sort()
	var want_a:={"keys":keys,"stock":canon(ALPHA_LEFT),"open_day":START_DAY,"pending":false,"till":0,"total":coins_a,"report":norm_report(report_a)}
	var want_b:={"keys":keys,"stock":canon({"radish":1}),"open_day":START_DAY,"pending":false,"till":coins_b,"total":coins_b,"report":norm_report(report_b)}
	var got_a=disk_market(disk.players.get(ALPHA,{}))
	var got_b=disk_market(disk.players.get(BETA,{}))
	expect(text(got_a)==text(want_a),"case 8 save holds alpha's exact player.market %s (got %s)"%[text(want_a),text(got_a)])
	expect(text(got_b)==text(want_b),"case 8 save holds beta's exact player.market %s (got %s)"%[text(want_b),text(got_b)])
	for token in [DELTA,EPSILON]:
		expect(not disk.players.get(token,{}).has("market"),"case 8 refused islander %s has no market field on disk"%token.get_slice("-",2))
	expect(text(disk.players.get(ALPHA,{}).get("market_decor",null))==text(decor2),"case 8 save holds alpha's exact market_decor %s"%text(decor2))
	for token in [BETA,DELTA,EPSILON]:
		expect(not disk.players.get(token,{}).has("market_decor"),"case 8 save holds no market_decor for %s"%token.get_slice("-",2))
	var own_ok:=true
	for part in range(2):
		var obj=disk.get("objects",{}).get(World.key(REGISTER+Vector2i(part,0)),{})
		if not obj is Dictionary or str(obj.get("owner",""))!=BETA:own_ok=false
	expect(own_ok,"case 8 save keeps beta as owner of both register parts (decor changed no ownership)")
	for token in [ALPHA,BETA]:
		expect(canon(disk.players.get(token,{}).get("inventory",{}))==final_bags[token],"case 8 save holds %s's exact bag"%token.get_slice("-",2))
	expect(int(disk.players.get(ALPHA,{}).get("coins",-1))==coins_a0+coins_a and int(disk.players.get(BETA,{}).get("coins",-1))==coins_b0,"case 8 save holds both purses")
	var port2:=start_server()
	expect(port2>0,"case 8 a new server Session hosts the same save")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	expect(joined(alpha) and joined(beta),"case 8 both clients rejoin the restarted server")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	expect(MARKET.day(alpha.clock())==START_DAY+1,"case 8 restarted world is still on day %d"%(START_DAY+1))
	expect(text(mrow(alpha.market()))==final_rows[ALPHA],"case 8 alpha's whole own_market identical after restart (%s)"%text(mrow(alpha.market())))
	expect(text(mrow(beta.market()))==final_rows[BETA],"case 8 beta's whole own_market identical after restart (%s)"%text(mrow(beta.market())))
	expect(canon(alpha.bag())==final_bags[ALPHA] and canon(beta.bag())==final_bags[BETA],"case 8 both bags identical after restart")
	expect(text(card(alpha))==final_cards[ALPHA],"case 8 alpha's journal market card identical after restart (%s)"%text(card(alpha)))
	expect(text(card(beta))==final_cards[BETA],"case 8 beta's journal market card identical after restart (%s)"%text(card(beta)))
	for c:Client in [alpha,beta]:expect_guests(c,0,"case 8 after restart (nobody open on day %d)"%(START_DAY+1))
	expect(display(alpha)==str(final_displays[ALPHA]),"case 8 alpha's stall shelf and remark line identical after restart (%s)"%display(alpha))
	expect(display(beta)==str(final_displays[BETA]),"case 8 beta's stall shelf and remark line identical after restart (%s)"%display(beta))
	expect_shelf(alpha,ALPHA_LEFT,"case 8 alpha after restart")
	expect_shelf(beta,{"radish":1},"case 8 beta after restart")
	expect_decor(alpha,decor2,"case 8 alpha's decor persists after the restart")
	expect_decor(beta,null,"case 8 beta still has no decor after the restart")
	gamma=await join("gamma",GAMMA,port2)
	expect(joined(gamma),"case 8 late joiner gamma joins with a fresh token")
	if not joined(gamma):return false
	await settle([alpha,beta,gamma])
	expect_row(gamma,want_row(START_DAY+1,{},false,false,0,0,0,{}),"case 8 late joiner's fresh empty stall")
	private_check(gamma,[alpha,beta],"case 8 gamma")
	# Alpha reopens the unsold radish on day 3: every client counts one stall today.
	r=await act(alpha,"market_open",S)
	expect(r.ok and r.message==open_msg(START_DAY+1,1),"case 8 alpha reopens on day %d (%s)"%[START_DAY+1,r.message])
	await settle([alpha,beta,gamma])
	expect_row(alpha,want_row(START_DAY+1,ALPHA_LEFT,true,true,1,0,coins_a,report_a),"case 8 alpha after reopening")
	expect_row(gamma,want_row(START_DAY+1,{},false,false,1,0,0,{}),"case 8 gamma sees stalls_today 1")
	expect(int(beta.market().get("stalls_today",-1))==1,"case 8 beta sees stalls_today 1")
	for c:Client in [alpha,beta,gamma]:expect_guests(c,2,"case 8 alpha reopened after restart")
	var g8:=var_to_str(guests(alpha))
	expect(var_to_str(guests(beta))==g8 and var_to_str(guests(gamma))==g8,"case 8 alpha's, beta's and late joiner gamma's guest plans are identical")
	var public_booth:Dictionary=alpha.session.snapshot.get("market_plaza",{})
	var visible_goods:Array=ALPHA_LEFT.keys()
	visible_goods.sort()
	expect(public_booth=={"vendor":alpha.session.own_id,"name":"alpha","style":decor2,"goods":visible_goods},"case 8 public stall shows its owner's saved cloth, sign and product kinds only")
	for c:Client in [beta,gamma]:expect(c.session.snapshot.get("market_plaza",{})==public_booth,"case 8 %s sees the same public stall without taking ownership of it"%c.label)
	# Stall display after the restart: alpha's reopened remark, CLOSED for the others.
	expect_remark(alpha,want_remark(START_DAY+1,ALPHA_LEFT,true,1),"case 8 alpha reopened after restart (with her persisted decor accent)",accent2)
	expect_decor(gamma,null,"case 8 late joiner gamma sees no decor")
	expect(not remark_of(alpha).is_empty() and remark_of(alpha)!=MarketDisplay.REMARK_CLOSED,"case 8 alpha's reopened remark is non-empty and not CLOSED (%s)"%remark_of(alpha))
	expect_remark(beta,MarketDisplay.REMARK_CLOSED,"case 8 beta not open on day %d"%(START_DAY+1))
	expect_remark(gamma,MarketDisplay.REMARK_CLOSED,"case 8 late joiner gamma not open")
	expect_shelf(gamma,{},"case 8 late joiner gamma")
	expect_shelf_private(gamma,ALPHA_LEFT,{},"case 8 gamma while alpha is open")
	expect_shelf_private(beta,ALPHA_LEFT,{"radish":1},"case 8 beta while alpha is open")
	expect_no_display_keys(gamma,"case 8 gamma")
	# Beta collects her till after the restart.
	r=await act(beta,"market_collect",S)
	expect(r.ok and r.message=="從錢箱收下 %d 鈴幣。"%coins_b,"case 8 beta collects her saved till (%s)"%r.message)
	await settle([alpha,beta,gamma])
	expect(beta.coins()==coins_b0+coins_b and int(beta.market().get("till",-1))==0,"case 8 beta's coins rose by exactly %d and till is 0"%coins_b)
	expect(alpha.coins()==coins_a0+coins_a and int(alpha.market().get("till",-1))==0,"case 8 alpha's purse and till untouched by beta's collect")
	await refuse(beta,"market_collect",S,"",MSG_EMPTY_TILL,"case 8 beta's second collect",[alpha,gamma])
	private_check(alpha,[beta,gamma],"case 8 alpha")
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	expect(await stop_server(),"case 8 restarted server shuts down cleanly")

	# 9. Picnic-less world: market actions refused with LOCKED, nothing written.
	save_path=folder.path_join("locked.json")
	if not expect(seed_world(save_path,false,{ZETA:{"name":"zeta","at":lock_stand,"inv":ZETA_BAG}}),"case 9 picnic-less fixture written and accepted by SaveSchema"):return false
	var port3:=start_server()
	expect(port3>0,"case 9 picnic-less server hosts")
	if port3==0:return false
	zeta=await join("zeta",ZETA,port3)
	expect(joined(zeta),"case 9 zeta joins the picnic-less world")
	if not joined(zeta):return false
	await settle([zeta])
	expect(zeta.session.snapshot.get("picnic")==false and zeta.market().get("unlocked")==false,"case 9 zeta's snapshot: picnic=false, own_market.unlocked=false")
	expect(zeta.pos().distance_to(Vector2(lock_stall)+HALF)<=3.2,"case 9 zeta stands beside candidate cell %s"%str(lock_stall))
	expect_guests(zeta,0,"case 9 locked (picnic=false)")
	expect(card(zeta).is_empty(),"case 9 locked zeta's journal market card is empty (got %s)"%text(card(zeta)))
	expect(shelf_of(zeta).is_empty(),"case 9 locked zeta's stall shelf is empty (got %s)"%var_to_str(shelf_of(zeta)))
	expect_remark(zeta,"","case 9 locked (picnic=false)")
	expect_no_display_keys(zeta,"case 9 zeta")
	await refuse(zeta,"market_stock",lock_stall,"radish:1",MARKET.LOCKED,"case 9 stock before the picnic",[])
	await refuse(zeta,"market_open",lock_stall,"",MARKET.LOCKED,"case 9 open before the picnic",[])
	await refuse(zeta,"market_collect",lock_stall,"",MARKET.LOCKED,"case 9 collect before the picnic",[])
	expect_decor(zeta,null,"case 9 locked zeta has no decor")
	await decor_refuse(zeta,lock_stall,"cloth|indigo",MARKET.LOCKED,"case 9 decor before the picnic",[])
	expect_decor(zeta,null,"case 9 locked zeta still has no decor after the refused request")
	expect(canon(zeta.bag())==canon(ZETA_BAG),"case 9 zeta keeps the exact preset bag")
	expect(guests(zeta).is_empty() and card(zeta).is_empty(),"case 9 after the LOCKED refusals zeta still draws no guests and no card")
	expect(shelf_of(zeta).is_empty() and remark_line_of(zeta).is_empty(),"case 9 after the LOCKED refusals zeta still shows no shelf and no remark")
	await leave(zeta)
	zeta=null
	expect(await stop_server(),"case 9 picnic-less server shuts down with a final save")
	var locked=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	expect(locked is Dictionary and locked.players.has(ZETA) and not locked.players[ZETA].has("market") and not locked.players[ZETA].has("market_decor"),"case 9 picnic-less save writes no market or market_decor field for zeta")
	if locked is Dictionary:
		expect(canon(locked.players.get(ZETA,{}).get("inventory",{}))==canon(ZETA_BAG),"case 9 picnic-less save keeps zeta's exact bag")
	return true

func teardown()->void:
	Engine.time_scale=1.0
	for c in [alpha,beta,gamma,delta,epsilon,zeta]:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in [alpha,beta,gamma,delta,epsilon,zeta]:
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
