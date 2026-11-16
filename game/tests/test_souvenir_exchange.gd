extends SceneTree
## T071 regression suite for res://scripts/souvenir_exchange.gd (紀念票兌換裝飾) and its
## World, SaveSchema, Session-snapshot and build-placement integration.
##
## EARNED (not seeded): every ticket used for redemption is earned through the three
## activities' real World.act start/join actions and World.step round settlement (each
## timed-out round pays each participant 1 ticket). Alpha earns 12 per activity, beta
## 3 harvest / 3 fishing / 2 showcase.
## PRESET (written straight into world state): state.picnic (and board/festival for the
## site check), state.time (assigned to jump to deadlines and past cooldowns), player
## positions x/y and region (wrong-region case), an inventory count set to the per-item
## cap (bag-full case), objects written onto booth candidate cells (fallback / pause),
## tampered copies of saved JSON for the schema cases, and a synthetic state for the
## per-entry redemption LIMIT (module level). Everything else goes through World.act,
## World.step, World.save/load_world and Session._send_snapshot.
const World=preload("res://scripts/world.gd")
const Souv=preload("res://scripts/souvenir_exchange.gd")
const Show=preload("res://scripts/showcase.gd")
const Meet=preload("res://scripts/fishing_meet.gd")
const Harvest=preload("res://scripts/harvest_relay.gd")
const Market=preload("res://scripts/market_stall.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Village=preload("res://scripts/village.gd")
const Session=preload("res://scripts/session.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Art=preload("res://scripts/souvenir_art.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const START:=1000.0
const HALF:=Vector2(0.5,0.5)
const BOOTH:=Vector2i(37,25)
const NEAR_SPOT:=Vector2(37.5,27.5)   # plaza tile 37,27: 2.0 from the booth centre
const FAR_SPOT:=Vector2(39.5,33.5)    # player spawn: 8.2 from the booth centre
const BUILD_SPOT:=Vector2(35.5,35.5)
const BUILD_TILE:=Vector2i(35,34)
const MOVE_TILE:=Vector2i(36,34)
const PROTECTED_MSG:="這裡是水域或公共通道，請換個位置"
const VIEW_KEYS:=["activities","available","balance","can_redeem","candidates","earned","entries","point","reach","redeemed_total","spent","unlocked"]
const ENTRY_KEYS:=["affordable","blurb","cost","cost_text","extra","held","id","item","name","placed","redeemed","short"]
const BUILD_PLOTS:=[Rect2i(41,34,3,4),Rect2i(34,33,4,5),Rect2i(46,22,6,8)]
const FIRST_FIELD:=Rect2i(45,26,3,2)
const SIGNS:={"harvest_relay":Harvest.SIGN,"fish_meet":Meet.SIGN,"showcase":Show.SIGN}
const PREFIXES:={"harvest_relay":"harvest","fish_meet":"fish_meet","showcase":"showcase"}
var checks:=0
var failures:=0
var serial:=0
var _cleanup:Array[String]=[]

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	for file in _cleanup:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("SOUVENIR_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func temp_path(tag:String)->String:
	return OS.get_environment("TEMP").path_join("souvenir-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])

static func pl(w,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

static func msg(r:Dictionary)->String:
	return str(r.get("message",""))

static func stand(w,token:String,at:Vector2)->void:
	var p:Dictionary=pl(w,token)
	p.x=at.x
	p.y=at.y

## Recursively canonicalizes JSON-ish data: sorted String keys, whole floats as ints.
static func canon(value:Variant)->Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			var source:Variant=value[k] if value.has(k) else value[StringName(k)]
			out[k]=canon(source)
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(canon(item))
		return list
	if value is float and is_finite(value) and floorf(value)==value:return int(value)
	return value

static func same(a:Variant,b:Variant)->bool:
	return var_to_bytes(canon(a))==var_to_bytes(canon(b))

func act(w,token:String,action:String,cell:Vector2i,extra:String="",request:String="")->Dictionary:
	serial+=1
	var id:String=request if not request.is_empty() else "souvenir-req-%d"%serial
	var r:Dictionary=w.act(token,id,action,cell,extra)
	return r

func ok(w,token:String,action:String,cell:Vector2i,extra:String,label:String)->Dictionary:
	var r:=act(w,token,action,cell,extra)
	expect(bool(r.get("ok",false)),label+" ("+msg(r)+")")
	return r

func write_fixture(path:String,data:Dictionary)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

## A rejected action leaves the whole world state byte-identical.
func expect_rejected(w,token:String,action:String,cell:Vector2i,extra:String,label:String,expected:String="")->void:
	var before:PackedByteArray=var_to_bytes(w.state)
	var had:bool=pl(w,token).has("souvenir")
	var r:Dictionary=act(w,token,action,cell,extra)
	expect(not bool(r.get("ok",true)),label+": rejected")
	expect(not msg(r).is_empty(),label+": rejection explains itself ("+msg(r)+")")
	if not expected.is_empty():expect(msg(r)==expected,label+": message is '%s' (got '%s')"%[expected,msg(r)])
	expect(var_to_bytes(w.state)==before,label+": world state byte-identical")
	expect(pl(w,token).has("souvenir")==had,label+": no souvenir field invented")

func make_world(tokens:Array,picnic:bool=true)->World:
	var w:=World.new()
	for token:String in tokens:w.add_player(token,token.left(6))
	w.state.picnic=picnic
	w.state.time=START
	for token:String in tokens:
		stand(w,token,NEAR_SPOT)
		var inv:Dictionary=pl(w,token).inventory
		for item in ["carp","radish","wood"]:inv[item]=int(inv.get(item,0))+3
	return w

## Plays `rounds` real rounds of `activity` (start by the first token, join by the rest),
## each settled by World.step after its deadline: every participant earns 1 ticket.
func earn(w,activity:String,tokens:Array,rounds:int)->void:
	var sign:Vector2i=SIGNS[activity]
	var prefix:String=PREFIXES[activity]
	var keep:={}
	for token:String in tokens:keep[token]=Vector2(float(pl(w,token).x),float(pl(w,token).y))
	for r in rounds:
		var current:Variant=w.state.get(activity)
		var round_id:=int(current.get("round",0)) if current is Dictionary else 0
		if current is Dictionary:w.state.time=maxf(float(w.state.time),float(current.get("ready",0.0)))+1.0
		for token:String in tokens:stand(w,token,Vector2(sign)+Vector2(0.5,1.5))
		ok(w,str(tokens[0]),prefix+"_start",sign,str(round_id),"%s round %d starts"%[activity,round_id+1])
		for i in range(1,tokens.size()):ok(w,str(tokens[i]),prefix+"_join",sign,str(round_id+1),"%s round %d joined by %s"%[activity,round_id+1,tokens[i]])
		w.state.time=float(w.state[activity].ends)+0.25
		w.step(0.5,true)
		expect(w.state[activity].active==false,"%s round %d settled by World.step"%[activity,round_id+1])
	for token:String in tokens:stand(w,token,keep[token])

static func tickets(w,token:String,activity:String)->int:
	var r:Variant=pl(w,token).get(activity)
	return int(r.get("tickets",0)) if r is Dictionary else 0

static func view(w,token:String)->Dictionary:
	var v:Dictionary=w.souvenir_view(token)
	return v

static func entry_view(v:Dictionary,entry:String)->Dictionary:
	for e:Dictionary in v.get("entries",[]):
		if e.id==entry:return e
	return {}

func redeem(w,token:String,entry:String,label:String)->Dictionary:
	stand(w,token,NEAR_SPOT)
	return ok(w,token,"souvenir_redeem",Souv.active_cell(w.state),Souv.extra_for(entry,pl(w,token)),label)

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_constants()
	test_site()
	if failures>0:
		finish()
		return
	test_locked()
	var w:=test_earn_and_redeem()
	if w!=null:
		test_rejections(w)
		test_replay(w)
		test_placement(w)
		test_not_currency(w)
		test_save_reload_and_schema(w)
		await test_snapshot_privacy(w)
	test_fallback_and_pause()
	test_limit_module()
	finish()

# 1. Catalogue, item ids, build recipes, art.
func test_constants()->void:
	expect(Souv.ACTIONS==["souvenir_redeem"],"One redemption action")
	expect(Souv.ACTIVITIES==["harvest_relay","fish_meet","showcase"],"Three ticket sources")
	expect(Souv.ENTRY_ORDER.size()==7 and Souv.ENTRIES.size()==7,"Seven catalogue entries")
	expect(Souv.CANDIDATES==[Vector2i(37,25),Vector2i(35,26),Vector2i(39,24)] and is_equal_approx(Souv.REACH,3.2),"Booth candidates and reach")
	var single:={}
	var mixed:=0
	var names:={}
	for entry:String in Souv.ENTRY_ORDER:
		expect(Souv.ENTRIES.has(entry),"%s is in ENTRIES"%entry)
		var e:Dictionary=Souv.ENTRIES[entry]
		var cost:Dictionary=e.cost
		expect(not cost.is_empty(),"%s has a cost"%entry)
		for activity in cost:expect(activity in Souv.ACTIVITIES and int(cost[activity])>=1,"%s costs a positive number of %s tickets"%[entry,activity])
		if cost.size()==1:single[cost.keys()[0]]=int(single.get(cost.keys()[0],0))+1
		else:mixed+=1
		var item:=Souv.item_of(entry)
		expect(item==entry+"_kit" and Souv.entry_of_item(item)==entry and Souv.is_item(item) and Souv.is_kind(entry),"%s item id %s"%[entry,item])
		expect(World.NAMES.has(item) and str(World.NAMES[item])==str(e.name),"%s item has a name in World.NAMES"%entry)
		expect(World.BUILD.has(entry) and same(World.BUILD[entry],{"name":str(e.name),item:1}),"%s places 1:1 from its kit via World.BUILD"%entry)
		expect(not entry in World.UNDO_SOLID,"%s is walk-through decor"%entry)
		expect(not str(e.blurb).is_empty() and not Souv.cost_text(entry).is_empty(),"%s has a blurb and cost text"%entry)
		names[str(e.name)]=true
		expect(Art.has_kind(entry) and Art.has_item(item),"%s has placeholder art"%entry)
		var icon:Texture2D=ItemArt.icon(item)
		expect(icon!=null and icon.get_size()==Vector2(32,32) and icon.get_image()!=null and not icon.get_image().is_invisible(),"%s inventory icon is a visible 32x32 image"%item)
	expect(names.size()==7,"Seven distinct names")
	for activity:String in Souv.ACTIVITIES:expect(int(single.get(activity,0))==2,"Two themed single-activity entries for %s"%activity)
	expect(mixed==1 and same(Souv.ENTRIES.trio_keepsake.cost,{"harvest_relay":3,"fish_meet":3,"showcase":3}),"One mixed entry needing all three ticket kinds")
	expect(Souv.cost_text("trio_keepsake")=="豐收接力 3、河岸釣魚會 3、家園布置題 3 張" and Souv.cost_text("veg_basket_rack")=="豐收接力 3 張","Cost text")
	expect(Souv.items().size()==7 and not Souv.is_item("wood") and not Souv.is_item("supply_box_kit") and Souv.entry_of_item("bogus_kit")=="","items() and negative lookups")
	var other:=Show.ACTIONS+Meet.ACTIONS+Harvest.ACTIONS+Market.ACTIONS+["fish_start","fish_catch","build","remove","emote","ship","sell","buy"]
	expect(not "souvenir_redeem" in other,"Action does not collide with an existing action")
	expect(Session.extra_allowed("souvenir_redeem","relay_crate_stack|9999"),"Longest redemption extra passes the transport bound")

## Every fixed home landmark the booth must neither stand on nor touch (mirrors
## test_showcase.home_landmarks, plus the three activity sites and the first field).
static func home_landmarks()->Dictionary:
	var marks:Dictionary={}
	for npc:String in Village.NPCS:
		if str(Village.NPCS[npc].get("region","home"))=="home":marks["npc "+npc]=Village.NPCS[npc].cell
	for npc:String in Village.FESTIVAL_SPOTS:marks["festival spot "+npc]=Village.FESTIVAL_SPOTS[npc]
	for cell:Vector2i in World.Festival.VISITORS:marks["festival visitor "+str(World.Festival.VISITORS[cell])]=cell
	for index in range(World.Festival.STOPS.size()):marks["festival stop %d"%index]=World.Festival.STOPS[index]
	marks["wind-chime tree"]=World.Festival.TREE_CELL
	marks["notice board"]=Vector2i(40,29)
	marks["seed shop"]=Vector2i(43,29)
	marks["chapter starter"]=World.CHAPTER_ONE.STARTER_CELL
	for index in range(World.SHIPPING.CANDIDATES.size()):marks["shipping candidate %d"%index]=World.SHIPPING.CANDIDATES[index]
	for index in range(World.COMMUNITY.CANDIDATES.size()):marks["community table candidate %d"%index]=World.COMMUNITY.CANDIDATES[index]
	for index in range(Market.CANDIDATES.size()):marks["market candidate %d"%index]=Market.CANDIDATES[index]
	for index in range(Harvest.CELLS.size()):marks["harvest relay cell %d"%index]=Harvest.CELLS[index]
	marks["fishing meet sign"]=Meet.SIGN
	for cell:Vector2i in Meet.SHORE:marks["fishing meet shore "+str(cell)]=cell
	for cell:Vector2i in Meet.water_cells():marks["fishing meet water "+str(cell)]=cell
	for cell:Vector2i in Show.cells():marks["showcase "+str(cell)]=cell
	for animal:String in World.LIVESTOCK.ANIMALS:
		marks["livestock "+animal]=World.LIVESTOCK.ANIMALS[animal].cell
		marks["livestock collector "+animal]=World.LIVESTOCK.collector_cell(animal)
	for index in range(Bond.RANCH_CELLS.size()):marks["ranch cell %d"%index]=Bond.RANCH_CELLS[index]
	for index in range(Bond.DOCK_CELLS.size()):marks["dock cell %d"%index]=Bond.DOCK_CELLS[index]
	for index in range(Bond.POST_CELLS.size()):marks["post cell %d"%index]=Bond.POST_CELLS[index]
	for index in range(Bond.BELL_CELLS.size()):marks["bell cell %d"%index]=Bond.BELL_CELLS[index]
	var transit:Dictionary=World.TRANSIT.points(World.REGIONS.HOME)
	for point:String in transit:marks["transit "+point]=transit[point].cell
	marks["home exit"]=World.REGIONS.exit_cell(World.REGIONS.HOME)
	marks["home arrival"]=Vector2i(World.REGIONS.spawn(World.REGIONS.HOME))
	marks["player spawn"]=Vector2i(World.SPAWN)
	marks["chicken"]=Vector2i(45,34)
	marks["quarry"]=Vector2i(54,25)
	marks["copper"]=World.COPPER_CELL
	for y in range(29,32):
		for x in [55,56]:marks["bridge %d,%d"%[x,y]]=Vector2i(x,y)
	marks["pump plot 53,36 (preview fixtures)"]=Vector2i(53,36)
	marks["station plot 53,33 (queue session tests)"]=Vector2i(53,33)
	for y in range(24,29):
		for x in [52,53]:marks["industry plot %d,%d"%[x,y]]=Vector2i(x,y)
	return marks

## Tiles reachable on foot from the spawn (4-neighbour flood over can_stand tile centres).
static func reachable(w)->Dictionary:
	var seen:={Vector2i(World.SPAWN):true}
	var queue:=[Vector2i(World.SPAWN)]
	while not queue.is_empty():
		var c:Vector2i=queue.pop_front()
		for d:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var n:=c+d
			if seen.has(n) or n.x<0 or n.y<0 or n.x>=World.SIZE.x or n.y>=World.SIZE.y:continue
			if not w.can_stand(Vector2(n)+HALF):continue
			seen[n]=true
			queue.append(n)
	return seen

# 2. Site: terrain of every candidate, landmark distances, reservation only after the picnic.
func test_site()->void:
	var plain:=World.new()
	var busy:=World.new()
	# PRESET: a mid-game home (bridge, picnic, festival story open).
	busy.state.board=true
	busy.state.picnic=true
	busy.state.festival_story_open=true
	var marks:=home_landmarks()
	for cell:Vector2i in Souv.CANDIDATES:
		for w in [plain,busy]:
			expect(w.is_land(cell) and not w.water(cell),"candidate %s is land, not water"%str(cell))
			expect(w.resource(cell)=="","candidate %s has no resource"%str(cell))
		expect(World.land(cell) and World.base_resource(cell)=="","candidate %s: island land with no fixed tree/rock/grass"%str(cell))
		for mark:String in marks:
			var at:Vector2i=marks[mark]
			expect(maxi(absi(cell.x-at.x),absi(cell.y-at.y))>=2,"candidate %s is not on or touching %s %s"%[str(cell),mark,str(at)])
		for rect:Rect2i in BUILD_PLOTS:
			expect(not rect.grow(1).has_point(cell),"candidate %s does not touch build plot %s"%[str(cell),str(rect)])
		expect(not FIRST_FIELD.grow(1).has_point(cell),"candidate %s does not touch the first field"%str(cell))
		expect(not plain.protected(cell) and not plain.blocked(cell),"candidate %s free before the picnic"%str(cell))
		expect(Vector2(World.SPAWN).distance_to(Vector2(cell)+HALF)<=10.0,"candidate %s within 10 tiles of the spawn"%str(cell))
	expect(Souv.active_cell(plain.state)==Souv.NO_CELL and not Souv.available(plain.state) and Souv.cell_for(plain.state)==BOOTH,"Before the picnic: no active booth (first free candidate would be 37,25)")
	expect(Souv.active_cell(busy.state)==BOOTH and World.souvenir_cell(busy.state)==BOOTH and Souv.available(busy.state),"After the picnic the booth is at 37,25")
	expect(busy.protected(BOOTH) and busy.blocked(BOOTH) and Souv.reserved(busy.state,BOOTH) and Souv.blocks(busy.state,BOOTH),"Active booth tile reserved and blocking after the picnic")
	for cell:Vector2i in Souv.CANDIDATES.slice(1):
		expect(not busy.protected(cell) and not busy.blocked(cell) and not Souv.reserved(busy.state,cell),"Unused candidate %s stays free"%str(cell))
	for y in range(BOOTH.y-1,BOOTH.y+2):
		for x in range(BOOTH.x-1,BOOTH.x+2):
			var p:=Vector2i(x,y)
			if p==BOOTH:continue
			expect(not Souv.reserved(busy.state,p) and busy.blocked(p)==plain.blocked(p) and busy.protected(p)==plain.protected(p),"Neighbour %s of the booth is not reserved (blocking unchanged by the picnic)"%str(p))
	var flood:=reachable(busy)
	expect(busy.can_stand(NEAR_SPOT) and flood.has(Vector2i(NEAR_SPOT)) and NEAR_SPOT.distance_to(Vector2(BOOTH)+HALF)<=Souv.REACH,"Plaza tile 37,27 is walkable, reachable from the spawn and within reach of the booth")
	for cell:Vector2i in Souv.CANDIDATES:
		var touching:=false
		for d:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			if flood.has(cell+d) and (Vector2(cell+d)+HALF).distance_to(Vector2(cell)+HALF)<=Souv.REACH:touching=true
		expect(touching,"candidate %s has a reachable standing tile next to it"%str(cell))
	expect(FAR_SPOT.distance_to(Vector2(BOOTH)+HALF)>Souv.REACH,"Spawn is out of reach of the booth")

# 3. Before the picnic every redemption is refused and nothing is written.
func test_locked()->void:
	var w:=make_world(["ann"],false)
	expect(view(w,"ann").unlocked==false and view(w,"ann").can_redeem==false and view(w,"ann").point==Souv.NO_CELL,"Locked view")
	for entry:String in Souv.ENTRY_ORDER:
		expect_rejected(w,"ann","souvenir_redeem",BOOTH,entry+"|0","locked "+entry,Souv.LOCKED)
	expect_rejected(w,"ann","souvenir_redeem",BOOTH,"bogus|0","locked unknown entry",Souv.LOCKED)
	expect(not w.protected(BOOTH) and not w.blocked(BOOTH),"Booth tile free before the picnic")

# 4. Tickets earned in real rounds; every entry redeemed; balances.
func test_earn_and_redeem()->World:
	var w:=make_world(["alpha","beta"])
	earn(w,"harvest_relay",["alpha","beta"],3)
	earn(w,"harvest_relay",["alpha"],9)
	earn(w,"fish_meet",["alpha","beta"],3)
	earn(w,"fish_meet",["alpha"],9)
	earn(w,"showcase",["alpha","beta"],2)
	earn(w,"showcase",["alpha"],10)
	var want_a:={"harvest_relay":12,"fish_meet":12,"showcase":12}
	var want_b:={"harvest_relay":3,"fish_meet":3,"showcase":2}
	for activity:String in Souv.ACTIVITIES:
		expect(tickets(w,"alpha",activity)==int(want_a[activity]),"alpha earned %d %s tickets in real rounds (%d)"%[int(want_a[activity]),activity,tickets(w,"alpha",activity)])
		expect(tickets(w,"beta",activity)==int(want_b[activity]),"beta earned %d %s tickets in real rounds (%d)"%[int(want_b[activity]),activity,tickets(w,"beta",activity)])
	if failures>0:return null
	stand(w,"alpha",NEAR_SPOT)
	stand(w,"beta",NEAR_SPOT)
	var v:=view(w,"alpha")
	var keys:Array=v.keys()
	keys.sort()
	expect(keys==VIEW_KEYS,"View keys (%s)"%str(keys))
	var ekeys:Array=(v.entries[0] as Dictionary).keys()
	ekeys.sort()
	expect(ekeys==ENTRY_KEYS,"Entry keys (%s)"%str(ekeys))
	expect(v.unlocked==true and v.available==true and v.can_redeem==true and v.point==BOOTH and (v.entries as Array).size()==7 and int(v.redeemed_total)==0,"Fresh unlocked view")
	expect(same(v.earned,want_a) and same(v.balance,want_a) and same(v.spent,{"harvest_relay":0,"fish_meet":0,"showcase":0}),"alpha's earned = balance before spending")
	expect(same(v.activities[0],{"id":"harvest_relay","name":"豐收接力","earned":12,"spent":0,"balance":12}),"activities rows")
	expect(not pl(w,"alpha").has("souvenir"),"No record before the first redemption")
	var records_before:={}
	for activity:String in Souv.ACTIVITIES:records_before[activity]=(pl(w,"alpha")[activity] as Dictionary).duplicate(true)
	var coins:=int(pl(w,"alpha").coins)
	var beta_before:Dictionary=pl(w,"beta").duplicate(true)
	var spent:={"harvest_relay":0,"fish_meet":0,"showcase":0}
	var order:=["veg_basket_rack","relay_crate_stack","carp_banner","float_garland","lantern_post","flower_arch"]
	for entry:String in order:
		var before:Dictionary=w.state.duplicate(true)
		var e:=entry_view(view(w,"alpha"),entry)
		expect(e.affordable==true and same(e.short,{}) and e.extra==entry+"|0" and int(e.held)==0 and int(e.redeemed)==0,"%s affordable before redeeming"%entry)
		var r:=redeem(w,"alpha",entry,"alpha redeems "+entry)
		var item:=Souv.item_of(entry)
		expect(msg(r).contains(str(Souv.ENTRIES[entry].name)) and msg(r).contains("不會退票"),"%s success message (%s)"%[entry,msg(r)])
		for activity in Souv.ENTRIES[entry].cost:spent[activity]=int(spent[activity])+int(Souv.ENTRIES[entry].cost[activity])
		var rec:Dictionary=pl(w,"alpha").souvenir
		expect(same(rec.spent,spent),"%s: spent now %s (%s)"%[entry,str(spent),str(rec.spent)])
		expect(int(rec.redeemed[entry])==1,"%s: redeemed count 1"%entry)
		expect(int(pl(w,"alpha").inventory.get(item,0))==1,"%s: one %s in the bag"%[entry,item])
		# Whole-state diff: only alpha's bag item, souvenir record, receipts and committed changed.
		var after:Dictionary=w.state.duplicate(true)
		for s:Dictionary in [before,after]:
			s.erase("committed")
			var who:Dictionary=s.players.alpha
			who.erase("receipts")
			who.erase("souvenir")
			who.inventory.erase(item)
		expect(same(before,after),"%s: nothing else in the world changed"%entry)
		var bal:Dictionary=view(w,"alpha").balance
		for activity:String in Souv.ACTIVITIES:expect(int(bal[activity])==int(want_a[activity])-int(spent[activity]),"%s: %s balance = earned - spent"%[entry,activity])
	for activity:String in Souv.ACTIVITIES:
		expect(same(pl(w,"alpha")[activity],records_before[activity]),"%s ticket record (earned counter) unchanged by spending"%activity)
	expect(int(pl(w,"alpha").coins)==coins,"Coins unchanged by redemptions")
	expect(same(pl(w,"beta"),beta_before),"Beta's whole player record unaffected by alpha's redemptions")
	expect(same(view(w,"alpha").balance,{"harvest_relay":3,"fish_meet":3,"showcase":3}),"Balance 3/3/3 before the mixed entry")
	var again:=entry_view(view(w,"alpha"),"relay_crate_stack")
	expect(again.affordable==false and same(again.short,{"harvest_relay":3}) and again.extra=="relay_crate_stack|1","relay_crate_stack now short by 3 harvest tickets")
	expect_rejected(w,"alpha","souvenir_redeem",BOOTH,"relay_crate_stack|1","alpha re-redeems relay_crate_stack without enough tickets",Souv.NOT_ENOUGH%"豐收接力的紀念票 3 張")
	redeem(w,"alpha","trio_keepsake","alpha redeems the mixed trio_keepsake")
	expect(same(pl(w,"alpha").souvenir.spent,want_a) and same(view(w,"alpha").balance,{"harvest_relay":0,"fish_meet":0,"showcase":0}),"Mixed entry spends 3 of each: balance 0/0/0")
	expect(int(view(w,"alpha").redeemed_total)==7 and int(pl(w,"alpha").inventory.trio_keepsake_kit)==1,"Seven redemptions, trio kit in the bag")
	expect_rejected(w,"alpha","souvenir_redeem",BOOTH,"trio_keepsake|1","trio again with balance 0/0/0",Souv.NOT_ENOUGH%"豐收接力的紀念票 3 張、河岸釣魚會的紀念票 3 張、家園布置題的紀念票 3 張")
	# Beta (3/3/2): the mixed entry is short only on showcase.
	var bt:=entry_view(view(w,"beta"),"trio_keepsake")
	expect(bt.affordable==false and same(bt.short,{"showcase":1}),"Beta's trio is short 1 showcase ticket only")
	expect_rejected(w,"beta","souvenir_redeem",BOOTH,"trio_keepsake|0","beta trio with 3/3/2",Souv.NOT_ENOUGH%"家園布置題的紀念票 1 張")
	expect(not pl(w,"beta").has("souvenir"),"Beta has no record after a refusal")
	redeem(w,"beta","carp_banner","beta redeems carp_banner")
	expect(same(pl(w,"beta").souvenir,{"spent":{"harvest_relay":0,"fish_meet":3,"showcase":0},"redeemed":{"carp_banner":1}}),"Beta's exact record")
	expect(same(view(w,"alpha").balance,{"harvest_relay":0,"fish_meet":0,"showcase":0}) and int(view(w,"alpha").redeemed_total)==7,"Beta's redemption does not touch alpha")
	return w

# 5. Every other rejection leaves the whole world state byte-identical.
func test_rejections(w)->void:
	# Beta still has 3 harvest / 0 fish / 2 showcase.
	stand(w,"beta",NEAR_SPOT)
	expect_rejected(w,"beta","souvenir_redeem",Vector2i(35,26),"veg_basket_rack|0","wrong point (another candidate)",Souv.WRONG_POINT)
	expect_rejected(w,"beta","souvenir_redeem",Vector2i(40,29),"veg_basket_rack|0","wrong point (notice board)",Souv.WRONG_POINT)
	stand(w,"beta",FAR_SPOT)
	expect_rejected(w,"beta","souvenir_redeem",BOOTH,"veg_basket_rack|0","too far",Souv.TOO_FAR)
	stand(w,"beta",NEAR_SPOT)
	expect_rejected(w,"beta","souvenir_redeem",BOOTH,"bonfire|0","unknown entry",Souv.UNKNOWN_ENTRY)
	expect_rejected(w,"beta","souvenir_redeem",BOOTH,"veg_basket_rack_kit|0","item id is not an entry",Souv.UNKNOWN_ENTRY)
	expect_rejected(w,"beta","souvenir_redeem",BOOTH,"veg_basket_rack|1","stale count",Souv.STALE)
	expect_rejected(w,"beta","souvenir_redeem",BOOTH,"carp_banner|0","stale count after a redemption",Souv.STALE)
	for bad:String in ["","veg_basket_rack","veg_basket_rack|x","veg_basket_rack|0|1","|0"]:
		expect_rejected(w,"beta","souvenir_redeem",BOOTH,bad,"bad extra '%s'"%bad,Souv.UNKNOWN_ENTRY if bad=="|0" else Souv.BAD_EXTRA)
	expect_rejected(w,"beta","souvenir_redeem",BOOTH,"float_garland|0","insufficient fish tickets",Souv.NOT_ENOUGH%"河岸釣魚會的紀念票 6 張")
	expect_rejected(w,"beta","souvenir_redeem",BOOTH,"flower_arch|0","insufficient showcase tickets",Souv.NOT_ENOUGH%"家園布置題的紀念票 4 張")
	# Full bag: the kit count is at the per-item cap (PRESET).
	var inv:Dictionary=pl(w,"beta").inventory
	inv["veg_basket_rack_kit"]=Souv.MAX_ITEM
	expect_rejected(w,"beta","souvenir_redeem",BOOTH,"veg_basket_rack|0","bag full of that item",Souv.BAG_FULL%"菜籃小架")
	inv.erase("veg_basket_rack_kit")
	# Wrong region (PRESET: beta moved to Lanyang).
	var p:Dictionary=pl(w,"beta")
	p.region=World.REGIONS.LANYANG
	var at:Vector2=World.REGIONS.spawn(World.REGIONS.LANYANG)
	stand(w,"beta",at)
	expect_rejected(w,"beta","souvenir_redeem",BOOTH,"veg_basket_rack|0","wrong region",Souv.WRONG_REGION)
	p.region=World.REGIONS.HOME
	stand(w,"beta",NEAR_SPOT)
	expect(Souv.view(w.state,"beta").balance.harvest_relay==3,"Beta's harvest balance intact after all refusals")
	# Build on the booth tile is refused (reserved).
	pl(w,"beta").inventory["wood"]=20
	expect_rejected(w,"beta","build",BOOTH,"lamp","build a lamp on the booth tile",PROTECTED_MSG)
	expect_rejected(w,"beta","hoe",BOOTH,"","till the booth tile",PROTECTED_MSG)

# 6. Resent request ids are idempotent; a second request with the same count is stale.
func test_replay(w)->void:
	stand(w,"beta",NEAR_SPOT)
	var first:Dictionary=w.act("beta","souvenir-replay-1","souvenir_redeem",BOOTH,"veg_basket_rack|0")
	expect(first.ok==true,"beta redeems veg_basket_rack (%s)"%msg(first))
	var snapshot:PackedByteArray=var_to_bytes(w.state)
	var second:Dictionary=w.act("beta","souvenir-replay-1","souvenir_redeem",BOOTH,"veg_basket_rack|0")
	expect(second==first,"Resent request id returns the stored receipt")
	expect(var_to_bytes(w.state)==snapshot,"Resent request id changes nothing")
	expect(int(pl(w,"beta").inventory.veg_basket_rack_kit)==1 and int(pl(w,"beta").souvenir.spent.harvest_relay)==3,"Applied once: one kit, 3 harvest tickets spent")
	expect_rejected(w,"beta","souvenir_redeem",BOOTH,"veg_basket_rack|0","new request with the old count",Souv.STALE)

# 7. Redeemed decor is placed, moved and picked up through the real build actions.
func test_placement(w)->void:
	stand(w,"alpha",BUILD_SPOT)
	var bag:Dictionary=pl(w,"alpha").inventory
	expect(int(bag.get("veg_basket_rack_kit",0))==1,"alpha holds one veg_basket_rack_kit")
	expect_rejected(w,"alpha","build",BUILD_TILE,"souvenir_redeem","build with a non-catalogue kind")
	var spent:Dictionary=pl(w,"alpha").souvenir.duplicate(true)
	ok(w,"alpha","build",BUILD_TILE,"veg_basket_rack","alpha places the basket rack")
	expect(int(bag.get("veg_basket_rack_kit",0))==0,"Placing consumes the kit")
	expect(same(w.state.objects.get(World.key(BUILD_TILE),{}),{"type":"veg_basket_rack","owner":"alpha","items":{}}),"Object written to the home objects layer")
	expect(not w.blocked(BUILD_TILE) and w.can_stand(Vector2(BUILD_TILE)+HALF),"Decor is walk-through")
	var e:=entry_view(view(w,"alpha"),"veg_basket_rack")
	expect(int(e.placed)==1 and int(e.held)==0 and int(e.redeemed)==1,"View: placed 1, held 0")
	expect_rejected(w,"alpha","build",MOVE_TILE,"veg_basket_rack","second placement without a kit")
	ok(w,"alpha","move_object",BUILD_TILE,"%d,%d"%[MOVE_TILE.x,MOVE_TILE.y],"alpha moves the rack")
	expect(w.state.objects.has(World.key(MOVE_TILE)) and not w.state.objects.has(World.key(BUILD_TILE)),"Rack moved")
	ok(w,"alpha","remove",MOVE_TILE,"","alpha picks the rack up")
	expect(int(bag.get("veg_basket_rack_kit",0))==1 and not w.state.objects.has(World.key(MOVE_TILE)),"Removing returns the kit")
	expect(same(pl(w,"alpha").souvenir,spent),"Picking up does not refund tickets")
	# Beta cannot remove alpha's decor.
	ok(w,"alpha","build",BUILD_TILE,"veg_basket_rack","alpha places the rack again")
	stand(w,"beta",BUILD_SPOT)
	expect_rejected(w,"beta","remove",BUILD_TILE,"","beta removes alpha's rack")
	# Place two more for the save test (one stays placed, others in the bag).
	ok(w,"alpha","build",MOVE_TILE,"trio_keepsake","alpha places the trio keepsake")
	expect(int(entry_view(view(w,"alpha"),"trio_keepsake").placed)==1,"View counts the placed trio keepsake")

# 8. Not a currency loophole: cannot ship, sell, stock or trade the kits.
func test_not_currency(w)->void:
	var prices:=World.SHIPPING.prices(World.CROPS,World.FISH,World.OTHER_SALES)
	var tradable:=World.trade_items()
	for item:String in Souv.items():
		expect(not prices.has(item),"%s has no shipping price"%item)
		expect(not World.CROPS.has(item) and not World.FISH.has(item) and not World.OTHER_SALES.has(item),"%s is not a crop/fish/other sale"%item)
		expect(not Market.sellable(item) and not item in Market.sellable_items(),"%s is not stall-listable"%item)
		expect(not tradable.has(item),"%s is not tradeable"%item)
		var q:=World.SHIPPING.quote([[item,1]],{item:1},prices)
		expect(q.ok==false,"%s: shipping quote refused"%item)
	expect(not tradable.has("veg_basket_rack") and tradable.has("wood"),"Trade list keeps ordinary items")
	var bag:Dictionary=pl(w,"alpha").inventory
	expect(int(bag.get("relay_crate_stack_kit",0))==1,"alpha holds a relay_crate_stack_kit")
	# Seed-shop sale.
	stand(w,"alpha",Vector2(43.5,30.5))
	expect_rejected(w,"alpha","sell",Vector2i(43,29),"relay_crate_stack_kit","sell a kit at the seed shop","這件商品尚未上架")
	# Shipping box.
	var box:=World.SHIPPING.cell_for(w.state)
	stand(w,"alpha",Vector2(box)+Vector2(0.5,1.5))
	expect_rejected(w,"alpha","ship",box,JSON.stringify([[["relay_crate_stack_kit",1]],10]),"ship a kit","出貨項目重複或無法出售。")
	# Market stall.
	var stall:=Market.cell_for(w.state)
	stand(w,"alpha",Vector2(stall)+Vector2(1.5,0.5))
	expect_rejected(w,"alpha","market_stock",stall,"relay_crate_stack_kit:1","stock a kit on the market stall","接力菜箱堆不能擺上市集攤位；攤位只收農漁產、料理和花。")
	stand(w,"alpha",NEAR_SPOT)

# 9. Save -> reload, legacy saves, schema tampering.
func test_save_reload_and_schema(w)->void:
	var path:=temp_path("world")
	var fixture:=temp_path("fixture")
	_cleanup.append(path)
	_cleanup.append(fixture)
	w.save_path=path
	expect(w.save(),"World saves")
	var reloaded:=World.new()
	expect(reloaded.load_world(path),"Fresh world reloads the save")
	if failures>0:return
	for field in ["objects","harvest_relay","fish_meet","showcase","picnic","time"]:
		expect(same(reloaded.state.get(field),w.state.get(field)),"state.%s survives reload (canonical)"%field)
	for token in ["alpha","beta"]:
		# Loading backfills fish_caught=0 (existing migration, not this feature).
		var a:Dictionary=pl(reloaded,token).duplicate(true)
		var b:Dictionary=pl(w,token).duplicate(true)
		expect(int(a.get("fish_caught",0))==int(b.get("fish_caught",0)),"%s fish_caught consistent"%token)
		a.erase("fish_caught")
		b.erase("fish_caught")
		expect(same(a,b),"%s's whole player record survives reload (canonical, minus the fish_caught backfill)"%token)
	for token in ["alpha","beta"]:
		expect(same(view(reloaded,token),view(w,token)),"%s view identical after reload"%token)
	var rec:Dictionary=pl(reloaded,"alpha").souvenir
	expect(typeof(rec.spent.harvest_relay)==TYPE_INT and typeof(rec.redeemed.trio_keepsake)==TYPE_INT,"Validation normalizes reloaded numbers to ints")
	expect(same(reloaded.state.objects.get(World.key(BUILD_TILE),{}),{"type":"veg_basket_rack","owner":"alpha","items":{}}) and str(reloaded.state.objects.get(World.key(MOVE_TILE),{}).get("type",""))=="trio_keepsake","Placed decor survives reload")
	# Reloaded world keeps working: pick up and re-place.
	reloaded.active_tokens={"alpha":true,"beta":true}
	stand(reloaded,"alpha",BUILD_SPOT)
	ok(reloaded,"alpha","remove",BUILD_TILE,"","alpha picks the rack up after reload")
	expect(int(pl(reloaded,"alpha").inventory.veg_basket_rack_kit)==1,"Kit back in the bag after reload")
	var base:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	# Legacy save without the souvenir fields loads and starts fresh.
	var old:Dictionary=base.duplicate(true)
	for token in ["alpha","beta"]:(old.players[token] as Dictionary).erase("souvenir")
	expect(write_fixture(fixture,old),"Write legacy fixture")
	var legacy:=World.new()
	expect(legacy.load_world(fixture),"Save without souvenir fields loads")
	expect(not pl(legacy,"alpha").has("souvenir") and same(view(legacy,"alpha").balance,{"harvest_relay":12,"fish_meet":12,"showcase":12}),"Legacy world: no record invented, full balance")
	var fresh:=World.new()
	fresh.add_player("solo","solo")
	expect(Schema.validate(JSON.parse_string(JSON.stringify(fresh.state)),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"A brand-new pre-picnic world still validates")
	expect(write_fixture(fixture,base) and World.new().load_world(fixture),"Control fixture loads")
	var probe:=World.new()
	var pristine:Dictionary=probe.state.duplicate(true)
	var labels:=["spent above earned","spent not matching redeemed","unknown entry","extra record key","missing spent","extra spent key","missing spent key",
		"spent is a string","redeemed is a list","record is a list","count is a string","fractional count","fractional spent","negative spent","zero count",
		"negative count","empty redeemed","count above the limit","record without a picnic","beta spends tickets she never earned","kit id as entry","record is null"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_fixture(fixture,bad),"Write tampered fixture: "+label)
		expect(not probe.load_world(fixture),"Schema rejects "+label)
		expect(probe.state==pristine,"Rejected load leaves the world untouched: "+label)
	expect(labels.size()>=20,"At least 20 tamper cases (%d)"%labels.size())

func tampered(base:Dictionary,label:String)->Dictionary:
	var s:Dictionary=base.duplicate(true)
	var a:Dictionary=s.players.alpha
	var rec:Dictionary=a.souvenir
	match label:
		"spent above earned":
			rec.redeemed.relay_crate_stack=2
			rec.spent.harvest_relay=18
		"spent not matching redeemed":rec.spent.fish_meet=11
		"unknown entry":
			rec.redeemed.bonfire=1
		"extra record key":rec.bonus=1
		"missing spent":rec.erase("spent")
		"extra spent key":rec.spent.festival=0
		"missing spent key":rec.spent.erase("showcase")
		"spent is a string":rec.spent="12"
		"redeemed is a list":rec.redeemed=["veg_basket_rack"]
		"record is a list":a.souvenir=[]
		"count is a string":rec.redeemed.veg_basket_rack="1"
		"fractional count":rec.redeemed.veg_basket_rack=1.5
		"fractional spent":rec.spent.showcase=11.5
		"negative spent":
			rec.spent.showcase=-1
		"zero count":rec.redeemed.veg_basket_rack=0
		"negative count":rec.redeemed.veg_basket_rack=-1
		"empty redeemed":
			rec.redeemed={}
			rec.spent={"harvest_relay":0,"fish_meet":0,"showcase":0}
		"count above the limit":rec.redeemed.veg_basket_rack=Souv.MAX_REDEEMED+1
		"record without a picnic":s.picnic=false
		"beta spends tickets she never earned":
			s.players.beta.souvenir={"spent":{"harvest_relay":3,"fish_meet":6,"showcase":3},"redeemed":{"carp_banner":1,"trio_keepsake":1}}
		"kit id as entry":
			rec.redeemed.erase("veg_basket_rack")
			rec.redeemed.veg_basket_rack_kit=1
		"record is null":a.souvenir=null
	return s

# 10. Snapshot privacy through Session (in process).
func test_snapshot_privacy(w)->void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=w
	w.save_path=""
	session.peers={1:"alpha",2:"beta"}
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		var text:=JSON.stringify(public)
		expect(not text.contains("\"souvenir\"") and not text.contains("own_souvenir") and not text.contains("redeemed"),"public_state(%s) carries no souvenir record"%region)
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.has("own_souvenir") and same(snap.own_souvenir,w.souvenir_view("alpha")),"own_souvenir equals alpha's own view")
	expect(int(snap.own_souvenir.redeemed_total)==7 and same(snap.own_souvenir.spent,{"harvest_relay":12,"fish_meet":12,"showcase":12}),"own_souvenir shows alpha's spending")
	var people:Dictionary=snap.get("players",{})
	var clean:=true
	for id in people:
		if (people[id] as Dictionary).has("souvenir"):clean=false
	expect(clean,"No players entry carries a souvenir record")
	expect(JSON.stringify(snap).count("\"own_souvenir\"")==1,"Exactly one own_souvenir in the snapshot")
	expect(not JSON.stringify(snap.own_souvenir).contains("alpha") and not JSON.stringify(snap.own_souvenir).contains("beta"),"own_souvenir carries no token")
	expect(snap.has("own_showcase") and snap.has("own_harvest") and snap.has("own_fish_meet"),"Sibling activity views still sent")
	# Same host peer id now bound to beta: beta receives only beta's view.
	session.peers={1:"beta",2:"alpha"}
	session._send_snapshot(1)
	var beta_snap:Dictionary=session.snapshot
	expect(same(beta_snap.own_souvenir,w.souvenir_view("beta")) and int(beta_snap.own_souvenir.redeemed_total)==2,"Beta's snapshot carries beta's own view")
	expect(not same(beta_snap.own_souvenir,snap.own_souvenir),"Beta's view differs from alpha's")
	session.world=null
	session.queue_free()
	await process_frame

# 11. Occupied booth falls back to the next candidate; all occupied pauses.
func test_fallback_and_pause()->void:
	var w:=make_world(["cat"])
	earn(w,"harvest_relay",["cat"],3)
	stand(w,"cat",NEAR_SPOT)
	# PRESET: something already built on the first candidate (old save shape).
	w.state.objects[World.key(BOOTH)]={"type":"lamp","owner":"cat","items":{}}
	var second:Vector2i=Souv.CANDIDATES[1]
	expect(Souv.active_cell(w.state)==second and view(w,"cat").point==second,"Occupied 37,25: booth falls back to 35,26")
	expect(w.protected(second) and w.blocked(second) and not Souv.reserved(w.state,BOOTH),"Fallback tile reserved; the occupied tile is not")
	stand(w,"cat",Vector2(35.5,27.5))
	expect_rejected(w,"cat","souvenir_redeem",BOOTH,"veg_basket_rack|0","old booth tile after fallback",Souv.WRONG_POINT)
	ok(w,"cat","souvenir_redeem",second,"veg_basket_rack|0","cat redeems at the fallback booth")
	for cell:Vector2i in Souv.CANDIDATES:w.state.objects[World.key(cell)]={"type":"lamp","owner":"cat","items":{}}
	expect(Souv.active_cell(w.state)==Souv.NO_CELL and not Souv.available(w.state) and view(w,"cat").can_redeem==false,"All candidates occupied: booth paused")
	for cell:Vector2i in Souv.CANDIDATES:expect(not Souv.reserved(w.state,cell),"Paused booth reserves nothing (%s)"%str(cell))
	expect_rejected(w,"cat","souvenir_redeem",second,"veg_basket_rack|1","redeem while paused",Souv.NO_POINT)
	w.state.objects.erase(World.key(BOOTH))
	expect(Souv.active_cell(w.state)==BOOTH,"Clearing 37,25 brings the booth back")

# 12. Module-level limits on a synthetic state (not reachable by real play).
func test_limit_module()->void:
	var state:={"picnic":true,"time":0.0,"objects":{},"players":{"x":{"x":37.5,"y":27.5,"inventory":{},
		"harvest_relay":{"tickets":40000,"rounds":20000,"best":0,"paid_round":1},
		"souvenir":{"spent":{"harvest_relay":Souv.MAX_REDEEMED*3,"fish_meet":0,"showcase":0},"redeemed":{"veg_basket_rack":Souv.MAX_REDEEMED}}}}}
	var before:=var_to_bytes(state)
	var r:=Souv.apply(state,"x","souvenir_redeem",BOOTH,"veg_basket_rack|%d"%Souv.MAX_REDEEMED,true)
	expect(r.ok==false and msg(r)==Souv.LIMIT and var_to_bytes(state)==before,"Per-entry redemption limit refused without writing")
	var r2:=Souv.apply(state,"x","souvenir_redeem",BOOTH,"veg_basket_rack|0",true)
	expect(r2.ok==false and msg(r2)==Souv.STALE,"Stale count refused at module level")
	var r3:=Souv.apply(state,"x","harvest_start",BOOTH,"veg_basket_rack|0",true)
	expect(r3.ok==false and msg(r3)==Souv.BAD_EXTRA,"Foreign action refused")
	var r4:=Souv.apply(state,"nobody","souvenir_redeem",BOOTH,"veg_basket_rack|0",true)
	expect(r4.ok==false and msg(r4)==Souv.NO_PLAYER,"Unknown player refused")
	state.players.x.souvenir="broken"
	var r5:=Souv.apply(state,"x","souvenir_redeem",BOOTH,"veg_basket_rack|0",true)
	expect(r5.ok==false and msg(r5)==Souv.BAD_EXTRA,"Corrupt record refused")
