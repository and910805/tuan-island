extends SceneTree
## C12 personal recipes D11 茶香布丁 (茶茶 熟悉 event) and D15 花園餅乾 (星禾 熟悉 event).
##
## Contract pinned here (the host World is the only authority; the cooking UI predicate is display only):
##   - on the 2x2 公共廚房灶台 a NEW job of tea_pudding / garden_cookie is accepted only for a player whose OWN
##     RESIDENT_GOALS.done(person, resident).has(2) is true (chacha / xinghe). The flag is set here through the
##     real RESIDENT_GOALS.apply, never by hand, and stage 1 / 3 of the same resident do not unlock;
##   - the gate is derived per player (no new save field), so two players on one stove are independent;
##   - a refused request changes nothing (bag, queue) and names the exact event to finish;
##   - the early one-cell stove keeps its old tables and jobs (tea_leaf pudding, old cookie), as does every
##     other C12 dish; D13 (has_recipe, 阿潮 event 3) and D16 (festival) are not changed by the shared predicate;
##   - the viewer's own snapshot (RESIDENT_GOALS.view, what Session attaches per player) drives the UI predicate
##     and agrees with the host; the cooking workbench shows the specific requirement text.
## Pure World + fake app dictionaries: works with --headless.

const World=preload("res://scripts/world.gd")
const K=World.KITCHEN_STOVE
const Goals=World.RESIDENT_GOALS
const Cooking=preload("res://scripts/cooking_queue_ui.gd")
const KIND:="kitchen_stove"
const PUDDING:="tea_pudding"
const COOKIE:="garden_cookie"
const BOARD:=Vector2i(40,29)
const HOME:=Vector2i(41,33)
const OLD:=Vector2i(43,33)
const STAND:=Vector2(41.5,36.5)
const EAST:=Vector2(43.5,34.5)
const MOVER:=Vector2(42.5,35.5)
const A:="personal-a"
const B:="personal-b"

var world:World
var path:String
var checks:=0
var failures:=0
var serial:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func act(who:String,verb:String,tile:Vector2i,extra:="")->Dictionary:
	serial+=1
	return world.act(who,"personal-recipes-%d"%serial,verb,tile,extra)

func person(who:String)->Dictionary:
	return world.state.players[who]

func bag(who:String,item:String)->int:
	return int(person(who).inventory.get(item,0))

func put(who:String,at:Vector2)->void:
	person(who).x=at.x
	person(who).y=at.y

func obj(tile:Vector2i)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func stock()->Dictionary:
	return {"wood":500,"stone":300,"fiber":100,"clay":30,"radish":20,"mist_tea":6,"tea_leaf":6,"milk":10,"egg":10,"flour":10,"sugar":10,"chime_herb":10,
		"bamboo":20,"cotton_cloth":6,"bluebell":6,"orange_blossom":6,"rice":6,"gold_shrimp":4,"minnow":4}

func fresh()->void:
	for x in range(38,51):
		for y in range(32,41):
			var k:=World.key(Vector2i(x,y))
			world.state.objects.erase(k)
			world.state.crops.erase(k)
			world.state.ground.erase(k)
	for who in [A,B]:
		var p:Dictionary=person(who)
		p.inventory=stock()
		p.builds=0
		p.region=World.REGIONS.HOME
		p.erase(Goals.RECORD_KEY)
		p.erase("bonds")
	world.state.public_kitchen=World.SAVE_SCHEMA.public_kitchen_fresh()
	put(A,STAND)
	put(B,EAST)

func open_island()->void:
	world.state.time=720.0
	var stories:Dictionary=person(A).get("stories",{})
	stories["aru"]=maxi(2,int(stories.get("aru",0)))
	person(A)["stories"]=stories
	for x in range(38,51):
		for y in range(32,41):world.state.removed[World.key(Vector2i(x,y))]=true
	put(A,Vector2(BOARD)+Vector2(0.5,1.5))
	expect(act(A,"donate",BOARD).ok and world.state.board==true,"fixture: Q03 through the real donate")
	person(A).inventory.merge(World.CHAPTER_ONE.PICNIC_PORTIONS,true)
	expect(act(A,"picnic",BOARD).ok and world.state.picnic==true,"fixture: the picnic through the real action")

## Real bond stage (熟悉 needs 6 points) then the real event action of ResidentGoals.
func bond(who:String,resident:String,points:int)->void:
	var bonds:Dictionary=person(who).get("bonds",{})
	bonds[resident]={"points":points,"talk_day":-1,"gift_day":-1}
	person(who)["bonds"]=bonds

func complete(who:String,resident:String,stage:int,choice:="",steps:="")->Dictionary:
	return Goals.apply(person(who),person(who).inventory,PackedStringArray([resident,str(stage),choice,steps]),World.NAMES,world.state,who)

func complete_chacha(who:String)->Dictionary:
	bond(who,"chacha",6)
	return complete(who,"chacha",2,"","012")

func complete_xinghe(who:String)->Dictionary:
	bond(who,"xinghe",6)
	return complete(who,"xinghe",2,"bluebell_orange")

func snap_of(who:String)->Dictionary:
	# What Session attaches to this player's own snapshot (session.gd: data.resident_goals).
	return {"objects":{World.key(HOME):{"type":KIND}},"resident_goals":Goals.view(person(who),world.state,who),"festival_story":{"opened":false,"projects":0}}

func cancel_all(who:String,tile:=HOME)->void:
	for repeat in 3:
		if not act(who,"cancel_cook",tile).ok:break

func finish()->void:
	for suffix in ["",".bak",".tmp",".staged",".writer-lock",".corrupt"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("C12_PERSONAL_RECIPES_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# -------------------------------------------------------------- scenarios --

func rule_scenario()->void:
	expect(K.dish(PUDDING).source=="茶茶熟悉事件" and K.dish(COOKIE).source=="星禾熟悉事件","D11 / D15 keep their content-bible sources")
	expect(K.EVENT_GATES.tea_pudding.resident=="chacha" and K.EVENT_GATES.tea_pudding.stage==2 and K.EVENT_GATES.garden_cookie.resident=="xinghe" and K.EVENT_GATES.garden_cookie.stage==2,"the gates are 茶茶 / 星禾 stage 2 (熟悉)")
	expect(Goals.GOALS.chacha[2].title=="漏下來的一束光" and Goals.GOALS.xinghe[2].title=="空花圃的圖紙","stage 2 is the event named in the requirement text")
	expect(K.EVENT_GATES.tea_pudding.message.contains("漏下來的一束光") and K.EVENT_GATES.tea_pudding.message.contains("竹材") and K.EVENT_GATES.garden_cookie.message.contains("空花圃的圖紙") and K.EVENT_GATES.garden_cookie.message.contains("星禾"),"the texts say which event and what to bring")
	expect(K.gate("stove",PUDDING).is_empty() and K.gate("stove",COOKIE).is_empty(),"the early stove has no gate")
	expect(K.gate(KIND,"soup").is_empty() and K.gate(KIND,"seafood_rice").is_empty(),"unrelated dishes (D13 included) are not in the shared gate")
	expect(K.gate(KIND,"forest_mushroom_soup").get("kind","")=="forest" and K.gate("stove","forest_mushroom_soup").is_empty(),"D05 forest soup is explicitly forest-gated on the C12 stove only, not an event gate")
	expect(K.gate(KIND,"trout_hotpot").kind=="festival" and K.gate(KIND,PUDDING).kind=="event","one gate table: D16 festival + D11 / D15 events")
	expect(K.festival_gated(KIND,"trout_hotpot") and not K.festival_gated(KIND,PUDDING),"the D16 predicate keeps its meaning")
	expect(K.locked(KIND,PUDDING,true,false) and not K.locked(KIND,PUDDING,false,true),"an event gate reads the event, not the festival")
	expect(K.locked(KIND,"trout_hotpot",false,true) and not K.locked(KIND,"trout_hotpot",true,false),"the festival gate reads the festival, not an event")
	expect(not K.locked("stove",PUDDING,false,false) and not K.locked(KIND,"soup",false,false),"no gate, never locked")
	expect(World.RECIPES[PUDDING].ingredients=={"tea_leaf":1,"milk":1,"egg":1} and World.stove_recipes("stove").has(PUDDING),"the old tea_leaf pudding table is unchanged")
	expect(World.stove_recipes(KIND)[PUDDING].ingredients=={"mist_tea":1,"milk":1,"egg":1},"the C12 table keeps the canonical D11 numbers")

func host_scenario()->void:
	fresh()
	expect(act(A,"build",HOME,KIND).ok,"fixture: C12 stove built")
	put(A,EAST)
	var snapshot_before:=var_to_str(person(A).inventory)
	# Locked for both: the host names the exact event and changes nothing.
	for who in [A,B]:
		for entry in [[PUDDING,"mist_tea"],[COOKIE,"sugar"]]:
			var dish:String=entry[0]
			var held:=bag(who,entry[1])
			var refused:=act(who,"queue_cook",HOME+Vector2i.ONE,dish)
			expect(not refused.ok and refused.message==K.EVENT_GATES[dish].message,"%s locked for %s: %s"%[dish,who,str(refused.get("message",""))])
			expect(bag(who,entry[1])==held and not obj(HOME).has("cooking"),"%s locked for %s: bag and queue untouched"%[dish,who])
			expect(not act(who,"cook",HOME,dish).ok and not obj(HOME).has("cooking"),"%s locked for %s: the older cook verb is gated too"%[dish,who])
	expect(var_to_str(person(A).inventory)==snapshot_before,"refusals never touch the backpack")
	# Not an event: stage 1 / 3 (or too few bond points) does not unlock, and the real event refuses without 熟悉.
	bond(A,"chacha",1)
	expect(not complete(A,"chacha",2,"","012").ok and not Goals.done(person(A),"chacha").has(2),"fixture: the real event refuses before 熟悉")
	expect(not act(A,"queue_cook",HOME,PUDDING).ok,"bond points alone do not unlock the pudding")
	# Other stages of the same resident (records written as the real action stores them) do not unlock.
	person(A)[Goals.RECORD_KEY]={"chacha":{"1":"","3":"","4":""}}
	expect(Goals.done(person(A),"chacha").has(1) and not Goals.done(person(A),"chacha").has(2) and not act(A,"queue_cook",HOME,PUDDING).ok,"chacha stages 1, 3 and 4 do not unlock the pudding")
	person(A)[Goals.RECORD_KEY]={"xinghe":{"2":"bluebell_orange"}}
	expect(not act(A,"queue_cook",HOME,PUDDING).ok,"another resident's stage 2 does not unlock the pudding")
	person(A)[Goals.RECORD_KEY]={"chacha":{"1":"","3":""}}
	# The real 熟悉 event.
	var bamboo:=bag(A,"bamboo")
	var done:=complete_chacha(A)
	expect(done.ok and Goals.done(person(A),"chacha").has(2) and bag(A,"bamboo")==bamboo-8,"fixture: 〈漏下來的一束光〉 completed through the real action: "+str(done.get("message","")))
	var mist:=bag(A,"mist_tea")
	var queued:=act(A,"queue_cook",HOME,PUDDING)
	expect(queued.ok and bag(A,"mist_tea")==mist-1 and bag(A,"milk")==9 and bag(A,"egg")==9,"unlocked: exactly 1 mist tea, 1 milk, 1 egg: "+str(queued.get("message","")))
	var job:Dictionary=obj(HOME).get("cooking",{}).get("active",{})
	expect(not job.is_empty() and job.kind==PUDDING and float(job.duration)==120.0 and int(job["yield"])==3 and job.ingredients=={"mist_tea":1,"milk":1,"egg":1},"the job is the canonical 120 s / 3 portions snapshot")
	# The other personal dish stays locked for the same player.
	var sugar:=bag(A,"sugar")
	expect(not act(A,"queue_cook",HOME,COOKIE).ok and bag(A,"sugar")==sugar,"星禾's dish is still locked after only 茶茶's event")
	# A queued job outlives the gate: it finishes and is claimed even if a player could not queue it again.
	expect(world.step(121.0,true) and act(A,"claim_cook",HOME).ok and bag(A,PUDDING)==3,"a finished job is claimed: 3 portions of the stable item id")

func two_player_scenario()->void:
	fresh()
	expect(act(A,"build",HOME,KIND).ok,"fixture: C12 stove built")
	put(A,EAST)
	put(B,EAST+Vector2(-0.5,0.0))
	expect(complete_chacha(A).ok,"fixture: A finishes 茶茶's event")
	expect(act(A,"queue_cook",HOME,PUDDING).ok,"A cooks the pudding")
	var mist_b:=bag(B,"mist_tea")
	var refused:=act(B,"queue_cook",HOME,PUDDING)
	expect(not refused.ok and refused.message==K.EVENT_GATES[PUDDING].message and bag(B,"mist_tea")==mist_b,"B on the same stove is still locked: A's event is not B's")
	expect(not act(A,"queue_cook",HOME,COOKIE).ok,"A is still locked for the cookie")
	cancel_all(A)
	# B finishes the other event: B gets the cookie, A and B's pudding stay as they were.
	expect(complete_xinghe(B).ok and Goals.done(person(B),"xinghe").has(2),"fixture: B finishes 星禾's event")
	expect(not Goals.done(person(A),"xinghe").has(2) and not Goals.done(person(B),"chacha").has(2),"the records are per player")
	var flour:=bag(B,"flour")
	var cookie:=act(B,"queue_cook",HOME,COOKIE)
	expect(cookie.ok and bag(B,"flour")==flour-1 and bag(B,"sugar")==9 and bag(B,"chime_herb")==9,"B cooks the cookie: 1 flour, 1 sugar, 1 chime herb: "+str(cookie.get("message","")))
	var job:Dictionary=obj(HOME).get("cooking",{}).get("active",{})
	expect(job.kind==COOKIE and float(job.duration)==90.0 and int(job["yield"])==4,"the cookie job is the canonical 90 s / 4 portions snapshot")
	expect(not act(B,"queue_cook",HOME,PUDDING).ok and not act(A,"queue_cook",HOME,COOKIE).ok,"each player is locked for the other's dish")
	cancel_all(B)
	expect(act(A,"queue_cook",HOME,PUDDING).ok,"A can still cook the pudding")
	# Reload: nothing new is stored, the unlock comes back from the saved event records.
	expect(world.save(),"the world saves")
	var back:=World.new()
	expect(back.load_world(path) and back.stove_dish_locked(back.state.players[A],KIND,COOKIE) and not back.stove_dish_locked(back.state.players[A],KIND,PUDDING),"reload: A's gate comes from the saved event")
	expect(not back.stove_dish_locked(back.state.players[B],KIND,COOKIE) and back.stove_dish_locked(back.state.players[B],KIND,PUDDING),"reload: B's gate is its own")
	var shape:=World.new().state.duplicate(true)
	expect(not shape.has("recipe_unlocks") and not shape.has("personal_recipes"),"no new save field exists")

func legacy_scenario()->void:
	fresh()
	put(A,MOVER)
	expect(act(A,"build",OLD,"stove").ok and obj(OLD).type=="stove","fixture: the early one-cell stove")
	var leaf:=bag(A,"tea_leaf")
	expect(not Goals.done(person(A),"chacha").has(2) and not Goals.done(person(A),"xinghe").has(2),"fixture: no event done")
	var pudding:=act(A,"cook",OLD,PUDDING)
	expect(pudding.ok and bag(A,"tea_leaf")==leaf-1 and obj(OLD).has("job") and obj(OLD).job.kind==PUDDING,"the early stove still cooks the old tea_leaf pudding as a legacy job: "+str(pudding.get("message","")))
	expect(act(A,"cancel_cook",OLD).ok and bag(A,"tea_leaf")==leaf,"and cancels with an exact refund")
	var sugar:=bag(A,"sugar")
	var cookie:=act(A,"queue_cook",OLD,COOKIE)
	expect(cookie.ok and bag(A,"sugar")==sugar-1 and float(obj(OLD).cooking.active.duration)==60.0,"the early stove keeps the old 60 s cookie: "+str(cookie.get("message","")))
	# Other C12 dishes and D13 are untouched by the shared predicate.
	cancel_all(A,OLD)
	put(A,EAST)
	expect(act(A,"build",HOME,KIND).ok,"fixture: C12 stove built")
	var radish:=bag(A,"radish")
	expect(act(A,"queue_cook",HOME,"soup").ok and bag(A,"radish")==radish-2,"soup is never gated on the C12 stove")
	cancel_all(A)
	var rice:=bag(A,"rice")
	var locked_rice:=act(A,"queue_cook",HOME,"seafood_rice")
	expect(not locked_rice.ok and locked_rice.message=="還沒有這份食譜" and bag(A,"rice")==rice,"D13 keeps its own rule (阿潮 event 3) and message")
	var records:Dictionary=person(A).get(Goals.RECORD_KEY,{})
	records["achao"]={"3":""}
	person(A)[Goals.RECORD_KEY]=records
	expect(act(A,"queue_cook",HOME,"seafood_rice").ok and bag(A,"rice")==rice-2,"D13 unlocks on that event exactly as before")
	cancel_all(A)

func snapshot_scenario()->void:
	fresh()
	world.add_player("personal-c","第三位")
	# The client predicate reads the viewer's own snapshot and agrees with the host for every state.
	expect(World.stove_dish_locked_in({},KIND,PUDDING) and World.stove_dish_locked_in({"resident_goals":"junk"},KIND,COOKIE),"a missing or malformed snapshot stays locked")
	expect(not World.stove_dish_locked_in({},KIND,"soup") and not World.stove_dish_locked_in({},"stove",PUDDING),"no gate, no lock (even without a snapshot)")
	expect(World.stove_dish_locked_in(snap_of(A),KIND,PUDDING) and World.stove_dish_locked_in(snap_of(A),KIND,COOKIE),"own snapshot before any event: both locked")
	expect(complete_chacha(A).ok,"fixture: A completes 茶茶's event")
	expect(not World.stove_dish_locked_in(snap_of(A),KIND,PUDDING) and World.stove_dish_locked_in(snap_of(A),KIND,COOKIE),"A's own snapshot shows the completed event unlock")
	expect(World.stove_dish_locked_in(snap_of(B),KIND,PUDDING),"a peer's own snapshot is not changed by A's event")
	expect(complete_xinghe(B).ok,"fixture: B completes 星禾's event")
	expect(not World.stove_dish_locked_in(snap_of(B),KIND,COOKIE) and World.stove_dish_locked_in(snap_of(B),KIND,PUDDING) and World.stove_dish_locked_in(snap_of(A),KIND,COOKIE),"each peer's own snapshot shows its own gate")
	for who in [A,B,"personal-c"]:
		for dish in [PUDDING,COOKIE,"soup","trout_hotpot","seafood_rice"]:
			expect(world.stove_dish_locked(person(who),KIND,dish)==World.stove_dish_locked_in(snap_of(who),KIND,dish),"client and host agree: %s / %s"%[who,dish])
	# D16 still reads the festival fact through the same predicate.
	var snap:=snap_of(A)
	expect(World.stove_dish_locked_in(snap,KIND,"trout_hotpot"),"D16 locked before the festival preparation")
	snap.festival_story_open=true
	expect(not World.stove_dish_locked_in(snap,KIND,"trout_hotpot") and World.stove_dish_locked_in(snap,KIND,COOKIE),"D16 opens with the festival and does not open the personal dishes")

func ui_scenario()->void:
	fresh()
	expect(complete_chacha(A).ok,"fixture: A completes 茶茶's event")
	var c:=Cooking.Controller.new()
	c.cell=HOME
	var snap:=snap_of(B)
	c.app={"session":{"snapshot":snap}}
	expect(c.festival_locked(PUDDING) and c.festival_locked(COOKIE) and not c.festival_locked("soup") and not c.festival_locked("seafood_rice"),"C12 workbench: the two personal dishes are held back, D13 is not shown through this gate")
	expect(c.gate_of(PUDDING).button==K.EVENT_GATES.tea_pudding.button and c.gate_of(COOKIE).message==K.EVENT_GATES.garden_cookie.message,"the workbench shows the specific requirement of each dish")
	expect(c.gate_of(PUDDING).button!=c.gate_of(COOKIE).button and not str(c.gate_of(PUDDING).button).contains("風鈴節"),"the texts differ and are not the festival text")
	expect(c.gate_of("trout_hotpot").button==K.LOCKED_BUTTON,"D16 keeps its festival text")
	c.app={"session":{"snapshot":snap_of(A)}}
	expect(not c.festival_locked(PUDDING) and c.festival_locked(COOKIE),"the workbench follows the viewer's own completed event")
	var old_snap:=snap_of(B)
	old_snap.objects[World.key(HOME)].type="stove"
	c.app={"session":{"snapshot":old_snap}}
	expect(not c.festival_locked(PUDDING) and not c.festival_locked(COOKIE) and c.gate_of(PUDDING).is_empty(),"early-stove workbench: never held back, no requirement shown")
	c.free()

func run()->void:
	path="user://c12-personal-recipes-%d.json"%Time.get_ticks_usec()
	world=World.new()
	world.save_path=path
	world.add_player(A,"甲")
	world.add_player(B,"乙")
	world.state.players[A].inventory=stock()
	open_island()
	rule_scenario()
	host_scenario()
	two_player_scenario()
	legacy_scenario()
	snapshot_scenario()
	ui_scenario()
	finish()
