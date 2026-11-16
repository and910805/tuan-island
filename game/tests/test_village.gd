extends SceneTree
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
var w
var checks:=0
var failures:=0
var seq:=0
func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)
func act(action:String,p:Vector2i,extra:String="",who:String="alice") -> Dictionary:
	seq+=1
	return w.act(who,"village-%d"%seq,action,p,extra)
func near(p:Vector2i) -> void:
	w.state.players.alice.x=p.x+0.5
	w.state.players.alice.y=p.y+1.5
func submit(resident:String,stage:int) -> Dictionary:
	near(Village.NPCS[resident].cell)
	return act("quest",Village.NPCS[resident].cell,resident+":"+str(stage))
func order_status(who:String,id:String,world=null) -> String:
	for row in (w if world==null else world).order_board(who).get("rows",[]):
		if row.id==id:return str(row.status)
	return ""
func save_valid(text:String,mode:String) -> bool:
	var parsed=JSON.parse_string(text)
	var o:Dictionary=parsed.players.alice.orders
	match mode:
		"legacy":o.erase("active")
		"fresh":
			o.erase("active")
			o.day=-1
			o.done=[]
		"ghost":o.active["ghost"]=o.active.radish.duplicate()
		"long":o.active.radish.due=float(o.active.radish.accepted)+10.0*Village.DAY
		"text":o.active.radish.due="soon"
		"extra":o.active.radish.coins=999
		"list":o.active=[]
	return World.SAVE_SCHEMA.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)
func _initialize() -> void:
	w=World.new();w.add_player("alice","小米");w.add_player("bob","豆豆")
	var person:Dictionary=w.state.players.alice
	person.inventory.wood=200;person.inventory.stone=100;person.inventory.fiber=100
	expect(not act("build",Vector2i(38,34),"sofa").ok,"story furniture locked before its reward")
	expect(not submit("aru",0).ok,"bed requirement enforced")
	w.state.objects["37,33"]={"type":"bed","owner":"bob","items":{}}
	expect(not submit("aru",0).ok,"other player's furniture does not satisfy personal story")
	w.state.objects["37,33"].owner="alice"
	var coins:int=person.coins
	expect(submit("aru",0).ok,"first story completes with owned bed")
	expect(person.coins==coins+60 and person.inventory.carrot_seed==3,"story reward committed once")
	expect(not submit("aru",0).ok,"stale quest stage cannot claim again or advance next stage")
	expect(not submit("aru",1).ok,"next stage respects world prerequisite")
	w.state.board=true
	expect(submit("aru",1).ok and Village.unlocked(person,"long_bench"),"bridge story unlocks bench")
	near(Vector2i(38,34))
	expect(act("build",Vector2i(37,34),"long_bench").ok,"earned recipe can be built")
	expect(act("build",Vector2i(38,33),"lamp").ok,"lamp prepared")
	expect(submit("aru",2).ok and Village.unlocked(person,"sign"),"decorating advances resident relationship")
	expect(not submit("aru",3).ok,"final story cannot bypass picnic")
	w.state.picnic=true;person.trees_planted=2
	expect(submit("aru",3).ok and Village.unlocked(person,"sofa"),"final carpenter story unlocks sofa")
	expect(not submit("aru",4).ok,"complete chain has no repeat reward")
	person.inventory.radish=2
	expect(submit("milu",0).ok and person.inventory.radish==0,"cook story consumes exact ingredient")
	expect(person.inventory.potato_seed==3,"story gives seeds usable in next loop")
	person.inventory.bread=1;person.inventory.salad=2
	expect(submit("milu",1).ok and Village.unlocked(person,"planter"),"food delivery unlocks decorative planter")
	person.inventory.baked_potato=2;person.inventory.grilled_fish=1
	expect(submit("milu",2).ok,"third cook story accepts varied meals")
	expect(not submit("milu",3).ok,"cooking participation required")
	person.cooked=3
	expect(submit("milu",3).ok,"cook story ends after personal participation")
	expect(w.state.players.bob.stories.milu==0,"one player's story does not overwrite neighbor progress")
	# T055 daily orders: accept -> deliver within 3 world days; world time only.
	var board:=Vector2i(40,29)
	near(board);person.inventory.radish=9
	coins=person.coins
	expect(not act("order",board,"radish").ok,"delivery requires accepting the order first")
	expect(person.inventory.radish==9 and person.coins==coins,"rejected delivery leaves backpack and coins untouched")
	expect(not act("order_accept",board,"ghost").ok,"unknown order cannot be accepted")
	expect(act("order_accept",board,"radish").ok,"daily order accepted at the board")
	expect(person.orders.get("active",{}).has("radish") and person.inventory.radish==9 and person.coins==coins,"accepting takes no materials or coins")
	expect(not act("order_accept",board,"radish").ok,"same order cannot be accepted twice")
	expect(order_status("alice","radish")=="active" and order_status("bob","radish")=="open","order board is per player")
	expect(act("order_cancel",board,"radish").ok and not person.orders.active.has("radish"),"accepted order can be cancelled")
	expect(person.inventory.radish==9 and person.coins==coins,"cancelling keeps materials and charges nothing")
	expect(not act("order_cancel",board,"radish").ok,"nothing left to cancel")
	expect(act("order_accept",board,"radish").ok,"cancelled order can be accepted again the same day")
	person.inventory.radish=2
	expect(not act("order",board,"radish").ok,"short delivery is refused")
	expect(person.inventory.radish==2 and person.coins==coins and person.orders.active.has("radish"),"short delivery mutates nothing and keeps the order")
	person.inventory.radish=9
	expect(act("order",board,"radish").ok,"daily order completes")
	expect(person.inventory.radish==6 and person.coins==coins+90,"daily order pays listed amount")
	expect(not person.orders.active.has("radish") and order_status("alice","radish")=="done","delivered order leaves the active list")
	expect(not act("order",board,"radish").ok,"daily reward cannot be repeated")
	expect(not act("order_accept",board,"radish").ok,"completed order cannot be re-accepted the same day")
	w.step(1441,false)
	expect(not act("order_accept",board,"radish").ok,"offline time does not refresh orders")
	w.step(1441,true)
	expect(act("order_accept",board,"radish").ok and act("order",board,"radish").ok,"next active world day refreshes order")
	# Expiry: overdue orders are cancelled lazily, never penalised.
	person.inventory.carp=1;person.inventory.minnow=1
	expect(act("order_accept",board,"fish").ok,"fish order accepted")
	var due:=float(person.orders.active.fish.due)
	expect(is_equal_approx(due-float(w.state.time),3.0*Village.DAY),"deadline is three world days")
	w.step(due-float(w.state.time)+1.0,false)
	expect(order_status("alice","fish")=="active","an empty world pauses the deadline")
	w.step(due-float(w.state.time)+1.0,true)
	expect((w.order_board("alice").expired as Array).has("fish"),"overdue order is reported as expired")
	coins=person.coins
	expect(not act("order",board,"fish").ok,"expired order cannot be delivered")
	expect(person.inventory.carp==1 and person.inventory.minnow==1 and person.coins==coins,"expiry keeps materials and coins")
	expect(act("order_accept",board,"fish").ok and person.orders.active.has("fish"),"expired order can be taken again when offered")
	expect(act("order_cancel",board,"fish").ok,"re-taken order can be cancelled")
	# Renewable shared stone source: a single payout and a world-time cooldown.
	var quarry:=Vector2i(54,25)
	near(quarry);var stone:int=person.inventory.stone
	for i in range(3):expect(act("quarry",quarry).ok,"quarry work progresses")
	expect(person.inventory.stone==stone+6,"quarry gives exactly six stone")
	expect(not act("pick",quarry).ok,"cooldown stops additional payout")
	w.step(46,false)
	expect(not act("quarry",quarry).ok,"empty world pauses quarry regeneration")
	w.step(46,true)
	expect(act("pick",quarry).ok,"pickaxe works when deposit is ready again")
	# Tomato stays for three harvests, with water required each time.
	var summer := World.WEATHER.DAYS_PER_SEASON * World.WEATHER.DAY_SECONDS
	expect(w.step(summer - float(w.state.time), true), "wait until summer for tomatoes")
	var plot:=Vector2i(41,35)
	near(plot);person.inventory.tomato_seed=1
	expect(act("hoe",plot).ok and act("seed",plot,"tomato").ok,"new crop can be planted")
	for cycle in range(3):
		w.step(121,true)
		expect(not act("harvest",plot).ok,"tomato requires water after each harvest")
		act("water",plot);w.step(121,true)
		expect(act("harvest",plot).ok,"tomato harvest succeeds")
		expect(person.inventory.tomato==2*(cycle+1),"correct recurrent yield")
	expect(w.state.crops[World.key(plot)].kind=="","plant retires after three yields")
	# T055 gating: summer never dispatches radish unless the requesting player
	# owns a greenhouse roof standing on a plot they own.
	var glass:=World.key(plot)
	expect(order_status("alice","radish")=="unavailable","out-of-season radish is not dispatched")
	expect(order_status("alice","fish")=="open","year-round fish order stays on the board")
	near(board)
	var radish_left:int=person.inventory.radish
	expect(not act("order_accept",board,"radish").ok and person.inventory.radish==radish_left,"undispatched order cannot be accepted")
	w.state.roofs[glass]={"type":"greenhouse_roof","owner":"bob","items":{}}
	expect(order_status("alice","radish")=="unavailable","another player's greenhouse does not unlock orders")
	w.state.roofs[glass].owner="alice";w.state.crops[glass].owner="bob"
	expect(order_status("alice","radish")=="unavailable","own glass over someone else's plot does not count")
	w.state.crops[glass].owner="alice"
	expect(order_status("alice","radish")=="open","own usable greenhouse dispatches radish")
	expect(order_status("bob","radish")=="unavailable","greenhouse gating is per player")
	coins=person.coins
	expect(act("order_accept",board,"radish").ok and person.inventory.radish==radish_left and person.coins==coins,"greenhouse radish order accepted")
	var path:="user://village-test-%d.json"%Time.get_ticks_usec()
	w.save_path=path;expect(w.save(),"village state saved")
	# Save schema: optional `active`, legacy books stay valid, bad entries refused.
	var text:=FileAccess.get_file_as_string(path)
	expect(save_valid(text,""),"save with an active order validates")
	expect(save_valid(text,"legacy"),"legacy order book without active validates")
	expect(save_valid(text,"fresh"),"fresh legacy order book validates")
	expect(not save_valid(text,"ghost"),"unknown active order id is rejected")
	expect(not save_valid(text,"long"),"over-long deadline is rejected")
	expect(not save_valid(text,"text"),"non-numeric deadline is rejected")
	expect(not save_valid(text,"extra"),"extra active fields are rejected")
	expect(not save_valid(text,"list"),"non-dictionary active list is rejected")
	var loaded=World.new();expect(loaded.load_world(path),"village state reloaded")
	expect(loaded.state.players.alice.stories.aru==4 and loaded.state.players.alice.stories.milu==4,"all story rewards survive restart")
	expect(loaded.state.quarry.hits==1,"shared quarry work survives restart")
	var reloaded:Dictionary=loaded.state.players.alice
	expect(reloaded.orders.get("active",{}).has("radish") and order_status("alice","radish",loaded)=="active","accepted order survives restart")
	reloaded.inventory.radish=3
	coins=int(reloaded.coins)
	expect(loaded.act("alice","village-reload-1","order",board,"radish").ok,"accepted order delivers after restart")
	expect(int(reloaded.inventory.radish)==0 and int(reloaded.coins)==coins+90,"reloaded delivery deducts exactly and pays once")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("VILLAGE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
