extends SceneTree
## T066 N03-2: Bobo stage 2 ("動不了的礦車") costs 4 copper ingots + 2 woodwork parts (option ids
## entrance / siding / shed unchanged) and opens the Jinguashi PartyCart surface portal for EVERY
## player of the world once ONE saved player has bond_goals.bobo["2"], or a legacy cart round
## (state.party_cart.round>0) already exists. World-level only (World.act / save / load_world).
##
## PRESET (disclosed): player region/x/y teleports (Bobo's table, the portal), bond points set to
## stage 2 (6), inventories set directly, the "old complete" fixtures write bond_goals by hand.
## Every unlock that is claimed as "earned" goes through the real resident_goal action.
## NOT covered here: Session snapshot publishing (test_party_cart_session / _scene check the
## snapshot bool party_cart_unlocked over the real path), UI text.
const World=preload("res://scripts/world.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Cart=preload("res://scripts/party_cart.gd")
const Route=preload("res://scripts/ore_route.gd")
const Art=preload("res://scripts/party_cart_art.gd")
const ALPHA:="bobo-cart-alpha"
const BETA:="bobo-cart-beta"
const GAMMA:="bobo-cart-gamma"
const OPTIONS:=["entrance","siding","shed"]
const COST:={"copper_ingot":4,"woodwork_parts":2}

var checks:=0
var failures:=0
var serial:=0
var temp_files:Array[String]=[]

func expect(value:bool,message:String)->bool:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)
	return value

func _initialize()->void:
	test_constants()
	test_locked_and_refusals()
	test_exact_debit_and_world_unlock()
	test_make_repair_materials()
	test_old_complete_fixtures()
	test_legacy_round()
	test_restore()
	test_ore_route_unaffected()
	for file in temp_files:
		for suffix in ["",".bak",".tmp",".writer-lock"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("bobo_cart_unlock checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

# ------------------------------------------------------------------ helpers --

func new_world(names:Array=[ALPHA,BETA])->World:
	var w:=World.new()
	for token:String in names:
		w.add_player(token,"礦車旅人")
		to_portal(w,token)
	return w

func person(w:World,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

func to_portal(w:World,token:String)->void:
	var p:=person(w,token)
	p.region=World.REGIONS.JINGUASHI
	p.x=Cart.SURFACE_PORTAL.x+0.5
	p.y=Cart.SURFACE_PORTAL.y+0.5

func bobo_cell(w:World)->Vector2i:
	var place:Array=World.bond_place(w.state,"bobo")
	var cell:Vector2i=place[1]
	return cell

func to_bobo(w:World,token:String)->Vector2i:
	var place:Array=World.bond_place(w.state,"bobo")
	var cell:Vector2i=place[1]
	var p:=person(w,token)
	p.region=str(place[0])
	p.x=float(cell.x)+0.5
	p.y=float(cell.y)+1.5
	return cell

func set_bobo_points(w:World,token:String,points:int)->void:
	var p:=person(w,token)
	var bonds:Dictionary={}
	if p.get("bonds") is Dictionary:bonds=p.bonds
	bonds["bobo"]={"points":points,"talk_day":-1,"gift_day":-1}
	p["bonds"]=bonds

func bag(w:World,token:String,items:Dictionary)->void:
	var inv:Dictionary=person(w,token).inventory
	for item:String in ["copper_ingot","woodwork_parts","copper_joint","plank","stone"]:inv[item]=0
	for item:String in items:inv[item]=int(items[item])

func held(w:World,token:String,item:String)->int:
	return int(person(w,token).inventory.get(item,0))

func request()->String:
	serial+=1
	return "bobo-cart-%d"%serial

func goal(w:World,token:String,extra:String)->Dictionary:
	var cell:=to_bobo(w,token)
	return w.act(token,request(),Goals.ACTION,cell,extra)

func enter(w:World,token:String)->Dictionary:
	to_portal(w,token)
	return w.act(token,request(),Cart.ACTION,Cart.SURFACE_PORTAL,"enter")

func leave(w:World,token:String)->Dictionary:
	var p:=person(w,token)
	p.x=Cart.EXIT.x+0.5
	p.y=Cart.EXIT.y+0.5
	return w.act(token,request(),Cart.ACTION,Cart.EXIT,"exit")

func dump(w:World)->String:
	return JSON.stringify(w.state,"",true)

func goals_of(w:World,token:String)->Variant:
	var p:=person(w,token)
	return p.get(Goals.RECORD_KEY)

## The whole world must be byte-identical after a refused action.
func refuses(w:World,call:Callable,label:String)->void:
	var before:=dump(w)
	var r:Dictionary=call.call()
	expect(r.get("ok",true)==false and not str(r.get("message","")).is_empty(),label+": refused with a message")
	expect(dump(w)==before,label+": world state unchanged")

func region_of(w:World,token:String)->String:
	return w.player_region(token)

# -------------------------------------------------------------------- tests --

func test_constants()->void:
	var entry:Dictionary=Goals.goal("bobo",2)
	expect(Goals.cost(entry,"siding")==COST,"bobo 2 cost is copper_ingot:4 + woodwork_parts:2")
	for id in OPTIONS:expect(Goals.cost(entry,id)==COST,"bobo 2 option %s keeps the same cost"%id)
	var ids:Array=[]
	for option:Dictionary in entry.options:ids.append(str(option.id))
	expect(ids==OPTIONS,"bobo 2 option ids unchanged (%s)"%str(ids))
	expect(not Goals.cost(entry,"siding").has("copper_joint") and not Goals.cost(entry,"siding").has("plank"),"old cost items are gone")
	expect(not Art.portal_locked({"party_cart_unlocked":true}) and Art.portal_locked({"party_cart_unlocked":false}) and Art.portal_locked({}),"The client requires a positive unlock in the snapshot")

func test_locked_and_refusals()->void:
	var w:=new_world()
	expect(not w.party_cart_unlocked(),"fresh world: gallery locked")
	for token in [ALPHA,BETA]:
		refuses(w,func():return enter(w,token),"locked portal for %s"%token)
		expect(region_of(w,token)==World.REGIONS.JINGUASHI,"%s stays in Jinguashi when locked"%token)
	set_bobo_points(w,ALPHA,6)
	to_bobo(w,ALPHA)
	# Insufficient materials: each shortage, and the OLD cost items cannot stand in.
	for held_items:Dictionary in [{"copper_ingot":3,"woodwork_parts":2},{"copper_ingot":4,"woodwork_parts":1},{},{"copper_joint":2,"plank":2},{"copper_joint":2,"plank":2,"copper_ingot":3,"woodwork_parts":1}]:
		bag(w,ALPHA,held_items)
		refuses(w,func():return goal(w,ALPHA,"bobo:2:siding:"),"short materials %s"%str(held_items))
		expect(goals_of(w,ALPHA)==null,"no record after a short refusal %s"%str(held_items))
		expect(not w.party_cart_unlocked(),"still locked after a short refusal %s"%str(held_items))
	# Invalid choices with full materials.
	bag(w,ALPHA,{"copper_ingot":4,"woodwork_parts":2})
	for extra in ["bobo:2::","bobo:2:bogus:","bobo:2:Siding:","bobo:2:siding_extra:","bobo:2:soup:"]:
		refuses(w,func():return goal(w,ALPHA,extra),"invalid choice '%s'"%extra)
	expect(held(w,ALPHA,"copper_ingot")==4 and held(w,ALPHA,"woodwork_parts")==2 and goals_of(w,ALPHA)==null and not w.party_cart_unlocked(),"invalid choices debit nothing and keep the gallery locked")
	refuses(w,func():return enter(w,BETA),"beta still locked after alpha's failed attempts")

func test_exact_debit_and_world_unlock()->void:
	var w:=new_world([ALPHA,BETA,GAMMA])
	set_bobo_points(w,ALPHA,6)
	bag(w,ALPHA,{"copper_ingot":5,"woodwork_parts":3,"copper_joint":2,"plank":2,"stone":7})
	var beta_before:Dictionary=person(w,BETA).inventory.duplicate(true)
	var gamma_bonds:Variant=person(w,GAMMA).get("bonds")
	var r:=goal(w,ALPHA,"bobo:2:siding:")
	expect(bool(r.get("ok",false)),"bobo 2 siding completes with the new materials (%s)"%str(r.get("message","")))
	expect(held(w,ALPHA,"copper_ingot")==1 and held(w,ALPHA,"woodwork_parts")==1,"exact debit: 4 ingots + 2 parts only")
	expect(held(w,ALPHA,"copper_joint")==2 and held(w,ALPHA,"plank")==2 and held(w,ALPHA,"stone")==7,"old cost items and other goods are untouched")
	expect(JSON.stringify(goals_of(w,ALPHA))==JSON.stringify({"bobo":{"2":"siding"}}),"alpha's own record holds bobo 2 siding")
	expect(w.party_cart_unlocked(),"completion unlocks the world")
	# Replay is refused and costs nothing more.
	refuses(w,func():return goal(w,ALPHA,"bobo:2:siding:"),"replay of bobo 2")
	expect(held(w,ALPHA,"copper_ingot")==1 and held(w,ALPHA,"woodwork_parts")==1,"replay debits nothing")
	# Cross-player availability: players who never did the goal walk in, in either order.
	for token in [BETA,GAMMA,ALPHA]:
		var e:=enter(w,token)
		expect(bool(e.get("ok",false)) and region_of(w,token)==Cart.REGION,"%s enters the gallery (%s)"%[token,str(e.get("message",""))])
	# No gift of persistent public state: the unlock is derived, never written onto other players.
	for token in [BETA,GAMMA]:
		var p:=person(w,token)
		expect(not p.has(Goals.RECORD_KEY) and not p.has(Goals.KEEPSAKE_KEY),"%s received no bond_goals / keepsake record"%token)
		expect(not p.get("bonds",{}).has("bobo"),"%s received no bobo bond"%token)
		expect(held(w,token,"copper_ingot")==0 and held(w,token,"woodwork_parts")==0,"%s inventory untouched"%token)
	expect(person(w,GAMMA).get("bonds")==gamma_bonds,"gamma's bonds are exactly what they were")
	expect(not w.state.has("bobo_cart") and not w.state.has("party_cart_unlocked"),"no new world-level unlock field was saved")
	expect(person(w,BETA).inventory==beta_before,"beta inventory identical to before")
	for token in [ALPHA,BETA,GAMMA]:
		expect(bool(leave(w,token).get("ok",false)) and region_of(w,token)==World.REGIONS.JINGUASHI,"%s leaves the gallery"%token)
	expect(w.party_cart_unlocked(),"still unlocked after everyone left")

func test_make_repair_materials()->void:
	var w:=new_world([ALPHA])
	var p:=person(w,ALPHA)
	p.region=World.REGIONS.HOME
	w.switch_region(World.REGIONS.HOME)
	# Raw materials and a previously built stone workbench are set up for this journey.
	bag(w,ALPHA,{"wood":20,"stone":30,"copper_ore":9,"charcoal":2,"plank":2,"hardwood":1})
	preload("res://tests/stone_station_fixture.gd").install(w,ALPHA)
	var furnace:=Vector2i(40,34)
	p.x=furnace.x+0.5
	p.y=furnace.y+2.5
	if not expect(w.act(ALPHA,request(),"build",furnace,World.INDUSTRY.SMELTER).ok,"Build the furnace through construction"):return
	for batch in 2:
		if not expect(w.act(ALPHA,request(),"queue_processing",furnace,"copper_ingot").ok,"Queue copper batch %d"%(batch+1)):return
	if not expect(w.step(100.0,true),"Advance through both copper batches"):return
	for batch in 2:
		if not expect(w.act(ALPHA,request(),"claim_processing",furnace).ok,"Claim copper batch %d"%(batch+1)):return
	var bench:=Vector2i(37,34)
	p.x=bench.x+0.5
	p.y=bench.y+1.5
	if not expect(w.act(ALPHA,request(),"build",bench,"bench").ok,"Build the woodworking bench"):return
	if not expect(w.act(ALPHA,request(),"craft",bench,"woodwork_parts").ok,"Make the woodworking parts"):return
	expect(held(w,ALPHA,"copper_ingot")==4 and held(w,ALPHA,"woodwork_parts")==2,"Both stations make the exact hand-in materials")
	set_bobo_points(w,ALPHA,6)
	expect(goal(w,ALPHA,"bobo:2:entrance:").ok and w.party_cart_unlocked(),"The station-made materials open the gallery")

func test_old_complete_fixtures()->void:
	# Saves written when bobo 2 cost copper_joint + plank carry the same record shape: they stay valid.
	for option in OPTIONS:
		var w:=new_world()
		set_bobo_points(w,ALPHA,6)
		person(w,ALPHA)[Goals.RECORD_KEY]={"bobo":{"2":option}}
		expect(Goals.valid(person(w,ALPHA)[Goals.RECORD_KEY],person(w,ALPHA)),"old complete fixture '%s' is a valid record"%option)
		expect(w.party_cart_unlocked(),"old complete fixture '%s' unlocks without any payment"%option)
		expect(bool(enter(w,BETA).get("ok",false)),"old fixture '%s': another player enters"%option)
		expect(held(w,ALPHA,"copper_ingot")==0 and held(w,ALPHA,"woodwork_parts")==0,"old fixture '%s' costs nothing now"%option)
	# Records that do NOT mean "bobo 2 done" keep it locked.
	var cases:Dictionary={
		"bobo stage 1 only":{"bobo":{"1":""}},
		"bobo stages 3 and 4 only":{"bobo":{"3":"","4":"home"}},
		"another resident's stage 2":{"aru":{"2":""}},
		"unknown option":{"bobo":{"2":"bogus"}},
		"empty option":{"bobo":{"2":""}},
	}
	for label:String in cases:
		var w:=new_world()
		set_bobo_points(w,ALPHA,24)
		set_bobo_points(w,BETA,24)
		var p:=person(w,ALPHA)
		var bonds:Dictionary=p.bonds
		bonds["aru"]={"points":24,"talk_day":-1,"gift_day":-1}
		p[Goals.RECORD_KEY]=cases[label]
		expect(not w.party_cart_unlocked(),"%s: not an unlock"%label)
		refuses(w,func():return enter(w,BETA),"%s: portal stays locked"%label)

func test_legacy_round()->void:
	var w:=new_world()
	expect(not w.party_cart_unlocked(),"before the legacy round: locked")
	# A world that already ran a cart round (saved before this gate) must keep working: PRESET by
	# putting alpha in the gallery and starting a round through the real action.
	var p:=person(w,ALPHA)
	p.region=Cart.REGION
	p.x=Cart.SIGN.x+0.5
	p.y=Cart.SIGN.y+0.5
	expect(bool(w.act(ALPHA,request(),Cart.ACTION,Cart.SIGN,"start").get("ok",false)),"legacy round starts")
	to_portal(w,ALPHA)
	expect(w.party_cart_unlocked(),"an existing cart round unlocks the portal")
	expect(not person(w,BETA).has(Goals.RECORD_KEY) and not person(w,ALPHA).has(Goals.RECORD_KEY),"no Bobo record anywhere in the legacy world")
	expect(bool(enter(w,BETA).get("ok",false)) and region_of(w,BETA)==Cart.REGION,"beta enters a legacy world")

func test_restore()->void:
	var done:=new_world()
	set_bobo_points(done,ALPHA,6)
	bag(done,ALPHA,COST)
	expect(bool(goal(done,ALPHA,"bobo:2:shed:").get("ok",false)),"restore fixture: bobo 2 shed done through the action")
	var done_path:="user://bobo-cart-done-%d.json"%OS.get_process_id()
	temp_files.append(done_path)
	done.save_path=done_path
	expect(done.save(),"unlocked world saves")
	var back:=World.new()
	expect(back.load_world(done_path),"unlocked world reloads")
	expect(back.party_cart_unlocked(),"reloaded world is still unlocked")
	expect(JSON.stringify(goals_of(back,ALPHA))==JSON.stringify({"bobo":{"2":"shed"}}),"reloaded record keeps the chosen option")
	back.add_player(GAMMA,"新旅人")
	to_portal(back,GAMMA)
	expect(bool(enter(back,GAMMA).get("ok",false)) and region_of(back,GAMMA)==Cart.REGION,"a new player after restore enters")
	expect(not person(back,GAMMA).has(Goals.RECORD_KEY),"restore gifts the new player no record")
	var locked:=new_world()
	var locked_path:="user://bobo-cart-locked-%d.json"%OS.get_process_id()
	temp_files.append(locked_path)
	locked.save_path=locked_path
	expect(locked.save(),"locked world saves")
	var again:=World.new()
	expect(again.load_world(locked_path) and not again.party_cart_unlocked(),"a world with no completion reloads locked")
	refuses(again,func():return enter(again,ALPHA),"reloaded locked world refuses the portal")

func test_ore_route_unaffected()->void:
	var w:=new_world()
	expect(not w.party_cart_unlocked(),"ore route runs in a locked world")
	var p:=person(w,ALPHA)
	p.region=World.REGIONS.JINGUASHI
	p.x=31.5
	p.y=20.5
	var r:=w.act(ALPHA,request(),Route.ACTION,Route.STOPS[0],"load")
	expect(bool(r.get("ok",false)),"ore_route load works while the gallery is locked (%s)"%str(r.get("message","")))
	expect(w.state.has(Route.STATE_KEY) and not w.party_cart_unlocked(),"ore_route progress does not unlock the gallery")
	# And unlocking the gallery leaves the ore route record alone.
	set_bobo_points(w,BETA,6)
	bag(w,BETA,COST)
	var route_before:=JSON.stringify(w.state[Route.STATE_KEY],"",true)
	expect(bool(goal(w,BETA,"bobo:2:entrance:").get("ok",false)) and w.party_cart_unlocked(),"unlock through bobo 2")
	expect(JSON.stringify(w.state[Route.STATE_KEY],"",true)==route_before,"unlocking leaves ore_route state byte-identical")
