extends SceneTree
## N09-1 Xiaoli first-trade receipts.
##
## One file, two modes:
##  * no user args  -> local World / Session checks, then a real WebSocket run in which this
##    process is the dedicated server and spawns two client processes (alpha / beta) of this
##    same script (user args: role port run_id). Client results come back through user:// files.
##  * role port run_id -> one WebSocket client.
## Contract under test: player[World.TRANSACTION_LEDGER.FIRST_SHOP_KEY] = {sale?, seed?}, each
## {action,time,coins,items} with the same signed deltas as TRANSACTION_LEDGER.shop_history.
## The snapshot sends it only as own_first_shop_trade (after xiaoli:1) and never in player rows.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Ledger=World.TRANSACTION_LEDGER
const Goals=World.RESIDENT_GOALS
const KEY:=Ledger.FIRST_SHOP_KEY
const OWN:="own_first_shop_trade"
const STALL:=Vector2i(43,29)
const SPRING:=720.0
const WINTER:=61200.0 # day 42, noon: first winter day (14 days per season)
const PASSWORD:="trade-receipts-network"
const SCRIPT:="res://tests/test_xiaoli_trade_receipts.gd"

var role:="main"
var run_id:=""
var checks:=0
var failures:=0
var serial:=0
var client:Session
var net_session:Session
var notices:Array[bool]=[]

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(role+": "+label)
	return ok

func same(a:Variant,b:Variant)->bool:
	if (a is int or a is float) and (b is int or b is float):return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for k in a:
			if not b.has(k) or not same(a[k],b[k]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not same(a[i],b[i]):return false
		return true
	return typeof(a)==typeof(b) and a==b

func wait_for(condition:Callable,message:String,seconds:=7.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline:
		await create_timer(0.03).timeout
	return expect(bool(condition.call()),message)

func remove_save(path:String)->void:
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func write_fixture(path:String,data:Dictionary)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

# ------------------------------------------------------------------ local world helpers

func fresh(tokens:Array)->World:
	var w:=World.new()
	for t:String in tokens:
		w.add_player(t,t)
		var p:Dictionary=w.state.players[t]
		p.x=STALL.x+0.5
		p.y=STALL.y+1.5
		p.coins=500
	w.state.time=SPRING
	return w

func act(w:World,t:String,action:String,cell:Vector2i,extra:String="")->Dictionary:
	serial+=1
	return w.act(t,"receipt-%d"%serial,action,cell,extra)

func pins(w:World,t:String)->Dictionary:
	var v:Variant=w.state.players[t].get(KEY,{})
	return v if v is Dictionary else {"__invalid":true}

func no_pins(w:World,t:String)->bool:
	var v:Dictionary=pins(w,t)
	return not v.has("sale") and not v.has("seed") and not v.has("__invalid")

func newest(w:World,t:String)->Dictionary:
	var h:Array=Ledger.shop_history(w.state,t)
	return h[0] if not h.is_empty() else {}

func entry_is(e:Variant,action:String,coins:int,items:Dictionary,time:float,label:String)->void:
	if not expect(e is Dictionary and e.size()==4 and e.has_all(["action","time","coins","items"]),label+": exact {action,time,coins,items} shape"):return
	expect(e.action==action,label+": action")
	expect(same(e.coins,coins),label+": signed coins %d (got %s)"%[coins,str(e.coins)])
	expect(same(e.items,items),label+": signed items "+str(items)+" (got "+str(e.items)+")")
	expect(same(e.time,time),label+": time")

func ship_extra(lines:Array,total:int)->String:
	return JSON.stringify([lines,total])

func unlock(w:World,t:String)->bool:
	var p:Dictionary=w.state.players[t]
	if not p.has("bonds"):p.bonds={}
	p.bonds.xiaoli={"points":1,"talk_day":-1,"gift_day":-1}
	var place:Vector2i=World.bond_place(w.state,"xiaoli")[1]
	p.x=place.x+0.5
	p.y=place.y+0.5
	var result:=act(w,t,"resident_goal",place,"xiaoli:1::")
	p.x=STALL.x+0.5
	p.y=STALL.y+1.5
	return result.ok

## Genuine sale (qty radish) then genuine in-season radish seed; returns false if a step is rejected.
func flow(w:World,t:String,qty:int,at:float)->bool:
	var p:Dictionary=w.state.players[t]
	p.inventory.radish=qty
	w.state.time=at
	var sold:=act(w,t,"sell",STALL,"radish")
	w.state.time=at+1.0
	var bought:=act(w,t,"buy",STALL,"radish")
	return expect(sold.ok and bought.ok,"flow: sale and seed purchase are accepted for "+t)

# ------------------------------------------------------------------ local scenarios

func scenario_stall()->void:
	var w:=fresh(["alice"])
	var a:Dictionary=w.state.players.alice
	var price:int=int(World.CROPS.radish.price)
	var seed_price:int=int(World.CROPS.radish.seed_price)
	var potato_price:int=int(World.CROPS.potato.seed_price)
	expect(typeof(KEY)==TYPE_STRING and not String(KEY).is_empty(),"FIRST_SHOP_KEY is a non-empty string")
	expect(World.crop_grows_in_season("radish",World.REGIONS.HOME,STALL,SPRING) and not World.crop_grows_in_season("radish",World.REGIONS.HOME,STALL,WINTER),"Fixture: radish seed is in season in spring and off season in winter")
	expect(World.crop_grows_in_season("potato",World.REGIONS.HOME,STALL,SPRING),"Fixture: potato seed is in season in spring")
	expect(not a.has(KEY) or pins(w,"alice").is_empty(),"A new account has no pins")

	# Buying a seed before any sale pins nothing.
	w.state.time=SPRING
	expect(act(w,"alice","buy",STALL,"radish").ok,"Buying a seed before any sale is accepted")
	expect(no_pins(w,"alice"),"A seed bought before the first sale never pins (neither sale nor seed)")

	# Normal shop sell.
	a.inventory.radish=3
	w.state.time=SPRING+5.0
	var coins:int=a.coins
	var sold:=act(w,"alice","sell",STALL,"radish")
	expect(sold.ok and a.coins==coins+3*price,"Shop sell pays 3 radishes exactly")
	var pin:Dictionary=pins(w,"alice")
	expect(pin.has("sale") and not pin.has("seed"),"First sale pins sale only")
	entry_is(pin.get("sale"),"sell",3*price,{"radish":-3},SPRING+5.0,"Shop sale pin")
	expect(same(pin.get("sale"),newest(w,"alice")),"Sale pin equals the matching shop_history entry")
	for k in pin:expect(k in ["sale","seed"],"Pin dictionary only uses sale and seed keys")

	# Off season: sale already recorded, a winter seed must not pin.
	w.state.time=WINTER
	expect(act(w,"alice","buy",STALL,"radish").ok,"An off-season seed is still sold")
	expect(not pins(w,"alice").has("seed") and int(a.get(Goals.CROP_TRADE_KEY,0))==Goals.CROP_SOLD,"Off-season seed never pins and leaves the story step open")

	# Rejected seed transactions after the sale never pin.
	w.state.time=SPRING+10.0
	var wallet:int=a.coins
	a.coins=0
	expect(not act(w,"alice","buy",STALL,"radish").ok and not pins(w,"alice").has("seed"),"Seed rejected for coins never pins")
	a.coins=wallet
	expect(not act(w,"alice","buy",STALL+Vector2i.RIGHT,"radish").ok and not pins(w,"alice").has("seed"),"Seed bought away from the stall never pins")
	expect(not act(w,"alice","buy",STALL,"not_a_seed").ok and not pins(w,"alice").has("seed"),"Unknown purchase never pins")
	expect(not act(w,"alice","buy",STALL,"sapling_missing").ok and a.coins==wallet,"Rejected purchases charge nothing")

	# First qualifying seed.
	w.state.time=SPRING+20.0
	wallet=a.coins
	expect(act(w,"alice","buy",STALL,"radish").ok and a.coins==wallet-seed_price,"In-season seed after the sale is bought")
	pin=pins(w,"alice")
	entry_is(pin.get("seed"),"buy",-seed_price,{"radish_seed":1},SPRING+20.0,"Seed pin")
	expect(same(pin.get("seed"),newest(w,"alice")),"Seed pin equals the matching shop_history entry")
	expect(int(a.get(Goals.CROP_TRADE_KEY,0))==Goals.SEED_BOUGHT,"The existing story step records the same seed")
	entry_is(pin.get("sale"),"sell",3*price,{"radish":-3},SPRING+5.0,"Sale pin survives the seed")

	# Later trades never rewrite either pin.
	var kept:Dictionary=pin.duplicate(true)
	a.inventory.radish=2
	a.inventory.wood=4
	w.state.time=SPRING+40.0
	expect(act(w,"alice","buy",STALL,"potato").ok and a.inventory.potato_seed>=1,"A second in-season seed is bought")
	expect(act(w,"alice","sell",STALL,"radish").ok,"A second sale is accepted")
	expect(act(w,"alice","ship",World.SHIPPING.cell_for(w.state),ship_extra([["wood",4]],4*int(World.SHIPPING.MATERIAL_PRICES.wood))).ok,"A later shipment is accepted")
	expect(same(pins(w,"alice"),kept),"Seed is pinned only once and the sale pin never moves")
	expect(newest(w,"alice").action=="ship" and potato_price>0,"History moved on while pins stayed")

func scenario_ship()->void:
	var w:=fresh(["bob"])
	var b:Dictionary=w.state.players.bob
	var box:=World.SHIPPING.cell_for(w.state)
	var price:int=int(World.CROPS.radish.price)
	var wood:int=int(World.SHIPPING.MATERIAL_PRICES.wood)
	b.inventory.radish=2
	b.inventory.wood=3
	var total:=2*price+3*wood
	w.state.time=SPRING+7.0
	var coins:int=b.coins
	var result:=act(w,"bob","ship",box,ship_extra([["radish",2],["wood",3]],total))
	expect(result.ok and int(result.get("total",-1))==total and b.coins==coins+total,"Mixed shipment pays the exact total")
	expect(b.inventory.radish==0 and b.inventory.wood==0,"Mixed shipment removes the exact quantities")
	var pin:Dictionary=pins(w,"bob")
	expect(pin.has("sale") and not pin.has("seed"),"A shipment that includes a crop pins sale only")
	entry_is(pin.get("sale"),"ship",total,{"radish":-2,"wood":-3},SPRING+7.0,"Mixed shipment pin")
	expect(same(pin.get("sale"),newest(w,"bob")),"Shipment pin equals the shop_history entry")
	# Off-season seed after a shipment does not pin either, an in-season one does.
	w.state.time=WINTER
	expect(act(w,"bob","buy",STALL,"radish").ok and not pins(w,"bob").has("seed"),"Off-season seed after a shipment does not pin")
	w.state.time=SPRING+30.0
	expect(act(w,"bob","buy",STALL,"radish").ok,"In-season seed after a shipment is bought")
	entry_is(pins(w,"bob").get("seed"),"buy",-int(World.CROPS.radish.seed_price),{"radish_seed":1},SPRING+30.0,"Seed pin after shipment")
	entry_is(pins(w,"bob").get("sale"),"ship",total,{"radish":-2,"wood":-3},SPRING+7.0,"Shipment pin survives")

func scenario_rejected()->void:
	var w:=fresh(["carol"])
	var c:Dictionary=w.state.players.carol
	var box:=World.SHIPPING.cell_for(w.state)
	var price:int=int(World.CROPS.radish.price)
	c.coins=0
	c.inventory.radish=0
	c.inventory.wood=0
	expect(not act(w,"carol","sell",STALL,"radish").ok,"Selling a crop you do not hold is rejected")
	expect(not act(w,"carol","buy",STALL,"radish").ok,"Buying without coins is rejected")
	c.inventory.radish=1
	c.inventory.wood=1
	expect(not act(w,"carol","sell",STALL+Vector2i.RIGHT,"radish").ok,"Selling away from the stall is rejected")
	expect(not act(w,"carol","sell",STALL,"not_a_real_item").ok,"Selling an unlisted item is rejected")
	expect(not act(w,"carol","ship",box,ship_extra([["radish",1]],price+1)).ok,"A stale shipment total is rejected")
	expect(not act(w,"carol","ship",box,ship_extra([["radish",5]],5*price)).ok,"Shipping more than held is rejected")
	expect(not act(w,"carol","ship",box,ship_extra([["radish",1],["radish",1]],2*price)).ok,"Duplicate shipment lines are rejected")
	expect(not act(w,"carol","ship",box,"not json").ok,"A malformed shipment is rejected")
	expect(not act(w,"carol","ship",STALL,ship_extra([["radish",1]],price)).ok,"Shipping away from the box is rejected")
	expect(c.inventory.radish==1 and c.inventory.wood==1 and c.coins==0,"Rejected transactions change nothing")
	expect(no_pins(w,"carol"),"Rejected transactions never pin")
	w.save_path="user://missing-trade-receipts-%d/world.json"%Time.get_ticks_usec()
	var valid_order:=ship_extra([["radish",1]],price)
	var failed:=act(w,"carol","ship",box,valid_order)
	expect(not failed.ok and failed.message==World.SAVE_FAILED_MSG,"A qualifying shipment fails if it cannot be saved")
	c=w.state.players.carol
	expect(c.inventory.radish==1 and c.coins==0 and no_pins(w,"carol") and not c.has(Goals.CROP_TRADE_KEY),"Save failure rolls back the sale, receipt, and story milestone together")
	w.save_path=""
	expect(act(w,"carol","ship",box,ship_extra([["radish",1]],price)).ok and pins(w,"carol").has("sale"),"The same fixture pins once a valid shipment is made")

func scenario_cap_and_reload()->void:
	var w:=fresh(["alice","bob"])
	var a:Dictionary=w.state.players.alice
	var box:=World.SHIPPING.cell_for(w.state)
	var wood:int=int(World.SHIPPING.MATERIAL_PRICES.wood)
	if not expect(flow(w,"alice",2,SPRING),"Cap fixture: pins are earned"):return
	var earned:Dictionary=pins(w,"alice").duplicate(true)
	expect(earned.has("sale") and earned.has("seed"),"Cap fixture: both pins exist")
	var bob:Dictionary=w.state.players.bob
	bob.inventory.radish=1
	bob.inventory.wood=0
	expect(act(w,"bob","ship",box,ship_extra([["radish",1]],int(World.CROPS.radish.price))).ok,"Cap fixture: a neighbour pins separately")
	a.inventory.wood=1000
	var rounds:=Ledger.CAP+14
	var accepted:=0
	for i in rounds:
		w.state.time=SPRING+100.0+i
		if act(w,"alice","ship",box,ship_extra([["wood",1]],wood)).ok:accepted+=1
	expect(accepted==rounds,"Cap fixture: every filler shipment is accepted")
	var root:Dictionary=w.state.get(Ledger.STATE_KEY,{})
	expect(root.get("entries",[]).size()==Ledger.CAP and int(root.get("dropped",0))>0,"The journal is at its cap and has evicted older entries")
	expect(not root.get("entries",[]).any(func(e:Dictionary):return e.by==Ledger.pid("alice") and e.act in ["sell","buy"]),"The sale and seed entries were evicted from the journal")
	expect(Ledger.shop_history(w.state,"alice").size()==10,"The visible history still lists only the newest ten")
	expect(same(pins(w,"alice"),earned),"Pins survive history cap eviction unchanged")
	expect(pins(w,"bob").has("sale") and not pins(w,"bob").has("seed") and not same(pins(w,"bob"),earned),"Eviction of one player's rows does not touch another player's pins")

	var path:="user://trade-receipts-world-%d.json"%Time.get_ticks_usec()
	w.save_path=path
	expect(w.save(),"The world saves with pins")
	var restored:=World.new()
	if expect(restored.load_world(path),"The world reloads with pins"):
		expect(same(pins(restored,"alice"),earned),"Reload preserves both pins exactly")
		expect(pins(restored,"bob").has("sale") and not pins(restored,"bob").has("seed"),"Reload preserves a sale-only pin")
		expect(same(restored.state.players.alice.get(KEY),w.state.players.alice.get(KEY)),"Reloaded field equals the saved field")
	var legacy:Dictionary=w.state.duplicate(true)
	legacy.players.alice.erase(KEY)
	write_fixture(path,legacy)
	var old:=World.new()
	if expect(old.load_world(path),"A save without the optional field still loads"):
		expect(not old.state.players.alice.has(KEY) or pins(old,"alice").is_empty(),"A legacy account stays without pins after load")
		expect(old.state.players.bob.has(KEY) and pins(old,"bob").has("sale"),"Legacy load keeps other accounts' pins")
	remove_save(path)

func scenario_session()->void:
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	var s:=Session.new()
	island.add_child(s)
	var path:="user://trade-receipts-local-%d.json"%Time.get_ticks_usec()
	s.profile.token="trade-receipt-owner"
	if not expect(s.host(0,"收據攤主",path)==OK,"The local session hosts"):
		island.queue_free()
		return
	s.set_physics_process(false)
	var w:World=s.world
	var owner:String=s.peers[1]
	var other:="trade-receipt-neighbor"
	w.add_player(other,"鄰居")
	for t:String in [owner,other]:
		var p:Dictionary=w.state.players[t]
		p.x=STALL.x+0.5
		p.y=STALL.y+1.5
		p.coins=500
	var price:int=int(World.CROPS.radish.price)
	s._send_snapshot(1)
	await process_frame
	expect(not s.snapshot.has(OWN),"A locked trade book sends no first-trade field")
	expect(flow(w,owner,3,SPRING),"The owner earns a sale and a seed pin")
	expect(flow(w,other,5,SPRING+50.0),"The neighbour earns different pins")
	s._send_snapshot(1)
	await process_frame
	expect(not s.snapshot.has(OWN) and not s.snapshot.has("own_shop_history"),"Pins alone do not unlock the snapshot field before xiaoli:1")
	expect(unlock(w,owner),"The owner reports to Xiaoli (xiaoli:1)")
	s._send_snapshot(1)
	await process_frame
	var mine:Variant=s.snapshot.get(OWN)
	expect(mine is Dictionary and same(mine,pins(w,owner)),"Snapshot after xiaoli:1 carries the recipient's own pins")
	if mine is Dictionary and mine.has("sale"):
		expect(same(mine.sale.coins,3*price) and same(mine.sale.items,{"radish":-3}),"Snapshot sale pin shows the owner's quantities")
		expect(not same(mine,pins(w,other)) and same(pins(w,other).sale.coins,5*price),"The neighbour's different pins are not what the owner receives")
	var stray:=false
	for row:Dictionary in s.snapshot.players.values():
		if row.has(KEY) or row.has(OWN):stray=true
	expect(not stray,"No player row in the owner's snapshot carries the field")
	var encoded:=JSON.stringify(s.snapshot.players)
	expect(not encoded.contains(String(KEY)) and not encoded.contains(OWN),"The raw field name never appears in the public player rows")
	for viewer:String in [owner,other,""]:
		var view:Dictionary=s.public_state("home",viewer)
		var leak:=view.has(OWN) or JSON.stringify(view).contains(String(KEY))
		expect(not leak,"public_state for recipient '%s' never carries the field"%viewer.left(8))
	# A legacy account that already finished xiaoli:1 gets an empty dictionary.
	w.state.players[owner].erase(KEY)
	s._send_snapshot(1)
	await process_frame
	expect(s.snapshot.get(OWN) is Dictionary and s.snapshot.get(OWN).is_empty(),"A legacy account receives an empty own_first_shop_trade")
	s.shutdown()
	remove_save(path)
	island.queue_free()
	await process_frame

# ------------------------------------------------------------------ real two-client WebSocket

func token(which:String)->String:
	return "trade-receipts-%s-%s"%[run_id,which]

func marker_path(who:String,stage:String)->String:
	return "user://trade-receipts-%s-%s.%s"%[run_id,who,stage]

func marker(who:String,stage:String)->bool:
	return FileAccess.file_exists(marker_path(who,stage))

func mark(who:String,stage:String)->void:
	var file:=FileAccess.open(marker_path(who,stage),FileAccess.WRITE)
	if expect(file!=null,"Writes coordination marker "+stage):file.close()

func expected_pins(which:String)->Dictionary:
	var price:int=int(World.CROPS.radish.price)
	if which=="alpha":
		return {"sale":{"action":"sell","coins":3*price,"items":{"radish":-3}},
			"seed":{"action":"buy","coins":-int(World.CROPS.radish.seed_price),"items":{"radish_seed":1}}}
	return {"sale":{"action":"ship","coins":2*price+3*int(World.SHIPPING.MATERIAL_PRICES.wood),"items":{"radish":-2,"wood":-3}},
		"seed":{"action":"buy","coins":-int(World.CROPS.potato.seed_price),"items":{"potato_seed":1}}}

func without_time(pin:Variant)->Dictionary:
	var out:Dictionary={}
	if pin is Dictionary:
		for k in pin:
			if k!="time":out[k]=pin[k]
	return out

func scenario_network()->void:
	run_id=str(Time.get_ticks_usec())
	var listener:=TCPServer.new()
	if not expect(listener.listen(0,"127.0.0.1")==OK,"The test can reserve a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	net_session=Session.new()
	island.add_child(net_session)
	var path:="user://trade-receipts-network-%s.json"%run_id
	var started:=net_session.host(port,"收據連線驗收",path,PASSWORD,"127.0.0.1",true,"websocket")
	if not expect(started==OK,"Starts a dedicated WebSocket server"):
		island.queue_free()
		return
	var w:World=net_session.world
	w.state.time=SPRING
	for which:String in ["alpha","beta"]:
		w.add_player(token(which),which,Vector2(STALL.x+0.5,STALL.y+1.5))
		var p:Dictionary=w.state.players[token(which)]
		p.coins=500
		p.inventory.merge({"radish":3,"wood":3},true)
	var pids:Array[int]=[]
	for which:String in ["alpha","beta"]:
		var args:=PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script",SCRIPT,"--",which,str(port),run_id])
		var pid:=OS.create_process(OS.get_executable_path(),args)
		expect(pid>0,"Spawns the %s client process"%which)
		pids.append(pid)
	if pids.all(func(pid:int):return pid>0) and await wait_for(func():return net_session.peers.size()==2,"Two distinct clients connect",25.0):
		if await wait_for(func():return marker("alpha","traded") and marker("beta","traded"),"Both clients finish their own shop trades",25.0):
			var unlocked:=true
			for which:String in ["alpha","beta"]:
				unlocked=unlock(w,token(which)) and unlocked
			expect(unlocked,"The server completes xiaoli:1 for both players")
			for id:int in net_session.peers.keys():net_session._send_snapshot(id)
			mark("server","unlocked")
		await wait_for(func():return net_session.peers.is_empty(),"Both clients finish and disconnect",25.0)
	for which:String in ["alpha","beta"]:
		var want:Dictionary=expected_pins(which)
		var got:Dictionary=pins(w,token(which))
		expect(same(without_time(got.get("sale")),want.sale) and same(without_time(got.get("seed")),want.seed),"Server world holds exactly %s's own pins"%which)
	expect(not same(pins(w,token("alpha")),pins(w,token("beta"))),"The two players hold different pins")
	for i in pids.size():
		var which:String="alpha" if i==0 else "beta"
		if pids[i]<=0:continue
		var deadline:=Time.get_ticks_msec()+15000
		while OS.is_process_running(pids[i]) and Time.get_ticks_msec()<deadline:
			await create_timer(0.1).timeout
		if OS.is_process_running(pids[i]):
			OS.kill(pids[i])
			expect(false,"The %s client process exits on its own"%which)
		var result_path:=marker_path(which,"result")
		if expect(FileAccess.file_exists(result_path),"The %s client reported results"%which):
			var parts:PackedStringArray=FileAccess.get_file_as_string(result_path).split(" ")
			var client_checks:=int(parts[0]) if parts.size()==2 else 0
			var client_failures:=int(parts[1]) if parts.size()==2 else 1
			expect(client_checks>0 and client_failures==0,"%s client: checks=%d failures=%d"%[which,client_checks,client_failures])
			checks+=client_checks
			failures+=client_failures
	expect(net_session.shutdown(),"Server closes and saves cleanly")
	var reopened:=World.new()
	if expect(reopened.load_world(path),"Reopen the saved WebSocket world"):
		for which:String in ["alpha","beta"]:
			expect(same(pins(reopened,token(which)),pins(w,token(which))),"Reopened world retains both receipts for "+which)
	remove_save(path)
	for who:String in ["alpha","beta","server"]:
		for stage:String in ["traded","unlocked","result"]:
			if FileAccess.file_exists(marker_path(who,stage)):DirAccess.remove_absolute(marker_path(who,stage))
	island.queue_free()
	await process_frame

func actor(which:String)->Dictionary:
	return client.snapshot.get("players",{}).get(Session._public_actor(token(which)),{})

func request(verb:String,tile:Vector2i,extra:String)->bool:
	var target:=notices.size()
	client.perform(verb,tile,extra)
	if not await wait_for(func():return notices.size()>target,"%s receives an action result"%verb):return false
	return expect(notices[target],verb+" is accepted by the server")

func exercise(which:String,port:int)->void:
	role=which
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	client=Session.new()
	island.add_child(client)
	client.profile.token=token(which)
	client.notice.connect(func(_message:String,success:bool):notices.append(success))
	if not expect(client.join("ws://127.0.0.1:%d"%port,port,which,PASSWORD)==OK,"Starts a WebSocket connection"):return
	if not await wait_for(func():return not actor("alpha").is_empty() and not actor("beta").is_empty(),"Both players are visible",15.0):return
	expect(not client.snapshot.has(OWN),"Before xiaoli:1 the snapshot has no first-trade field")
	var radish:=int(World.CROPS.radish.price)
	var wood:=int(World.SHIPPING.MATERIAL_PRICES.wood)
	if which=="alpha":
		if not await request("sell",STALL,"radish"):return
		if not await request("buy",STALL,"radish"):return
	else:
		if not await request("ship",World.SHIPPING.CELL,ship_extra([["radish",2],["wood",3]],2*radish+3*wood)):return
		if not await request("buy",STALL,"potato"):return
	expect(not client.snapshot.has(OWN),"Earned pins stay hidden until xiaoli:1 is reported")
	mark(which,"traded")
	if not await wait_for(func():return client.snapshot.has(OWN),"The snapshot after xiaoli:1 carries the first-trade field",25.0):return
	var own:Variant=client.snapshot.get(OWN)
	var want:Dictionary=expected_pins(which)
	var other:String="beta" if which=="alpha" else "alpha"
	if expect(own is Dictionary,"The field is a dictionary"):
		expect(own.has("sale") and own.has("seed") and own.size()==2,"Recipient sees exactly sale and seed")
		expect(same(without_time(own.get("sale")),want.sale),"Recipient's sale pin is its own trade")
		expect(same(without_time(own.get("seed")),want.seed),"Recipient's seed pin is its own purchase")
		expect(not same(without_time(own.get("sale")),expected_pins(other).sale),"Recipient never receives the other player's sale")
		expect(own.has("sale") and own.has("seed") and (own.sale.time is float or own.sale.time is int) and float(own.sale.time)<=float(own.seed.time),"Pin times are numbers in trade order")
	var stray:=false
	for row:Dictionary in client.snapshot.players.values():
		if row.has(KEY) or row.has(OWN):stray=true
	expect(not stray,"No player row (own or other) carries the field")
	expect(not JSON.stringify(client.snapshot.players).contains(String(KEY)),"Raw field name is absent from every player row")
	client.shutdown()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3 and args[0] in ["alpha","beta"]:
		run_id=args[2]
		await exercise(args[0],int(args[1]))
		var file:=FileAccess.open(marker_path(args[0],"result"),FileAccess.WRITE)
		if file:
			file.store_string("%d %d"%[checks,failures])
			file.close()
		print("XIAOLI_TRADE_RECEIPTS_NETWORK role=%s checks=%d failures=%d"%[args[0],checks,failures])
		quit(int(failures>0))
		return
	scenario_stall()
	scenario_ship()
	scenario_rejected()
	scenario_cap_and_reload()
	await scenario_session()
	await scenario_network()
	print("XIAOLI_TRADE_RECEIPTS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
