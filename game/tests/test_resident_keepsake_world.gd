extends SceneTree
## T066「一起做的事」第三批（紀念小物）world-rule suite: the 12 resident keepsake
## decorations (res://scripts/resident_goals.gd KEEPSAKES / KEEPSAKE_ORDER) and their
## World.BUILD / World.NAMES / trade / shipping / market / chest / SaveSchema integration.
## Modelled on test_souvenir_exchange.gd (same placement rules for *_kit decor) and the
## chest checks of test_jinguashi_revisit.gd.
##
## REAL ACTIONS (through World.act): build (keepsakes, a shared chest, a bed), remove,
## move_object, deposit, withdraw, sell, ship, market_stock, resident_goal (aru 1) and
## resident_keepsake (claim), plus every refusal; World.save / World.load_world.
## PRESET (written straight into world state, disclosed):
##   - placement world: one "<kind>_kit" put into ALPHA's bag per kind (the kits are
##     NOT earned there), wood for the chest, state.picnic=true (market stall / shipping
##     box open) and state.time, player x/y/region (standing spots, no walking action);
##   - earned case: EARN's bond points with 阿榆 (stage 1, never earned by talking),
##     wood/fiber counts for the bed and the goal; the bed itself is built with the real
##     build action and aru 1 is completed with the real resident_goal action, which
##     grants keepsake_aru_kit; that earned kit is then placed with the real build action;
##   - legacy claim: LEGACY's bond points and a bond_goals record {"aru":{"1":""}}
##     (a goal finished before batch 3), then claimed with the real resident_keepsake;
##   - tampered copies of saved JSON for the schema cases.
## Placement in other regions is not tested: the souvenir suites only place at home.
## There is no movement helper in the souvenir suites; walkability is asserted with the
## same World.blocked / World.can_stand checks they use.
const World=preload("res://scripts/world.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Market=preload("res://scripts/market_stall.gd")
const Souv=preload("res://scripts/souvenir_exchange.gd")
const Village=preload("res://scripts/village.gd")
const Schema=preload("res://scripts/save_schema.gd")
const START:=1000.0
const HALF:=Vector2(0.5,0.5)
const ORIGIN:=Vector2i(36,35)
const ALPHA:="keepsake-alpha-token-1a2b"
const BETA:="keepsake-beta-token-3c4d"
const EARN:="keepsake-earn-token-5e6f"
const LEGACY:="keepsake-legacy-token-7a8b"
const SHIP_REFUSED:="出貨項目重複或無法出售。"
const NOT_LISTED:="這件商品尚未上架"
const REMOVED_MSG:="已拆除，建造材料完整退還"
var checks:=0
var failures:=0
var serial:=0
var _cleanup:Array[String]=[]
var build_tile:=Vector2i(-1,-1)
var move_tile:=Vector2i(-1,-1)
var chest_tile:=Vector2i(-1,-1)
var work_spot:=Vector2(-1,-1)
var bulk:Array=[]

func expect(value:bool,message:String)->bool:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)
	return value

func finish()->void:
	for file in _cleanup:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("RESIDENT_KEEPSAKE_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_catalog()
	test_static_not_currency()
	var w:World=test_placement()
	if w!=null:
		test_actions_not_currency(w)
		test_placement_saves(w)
	test_earned()
	finish()

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String)->String:
	var path:=OS.get_environment("TEMP").path_join("resident-keepsake-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])
	_cleanup.append(path)
	return path

## Recursively canonicalizes JSON-ish data: sorted String keys, whole floats as ints.
static func canon(value:Variant)->Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			out[k]=canon(value[k] if value.has(k) else value[StringName(k)])
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(canon(item))
		return list
	if value is float and is_equal_approx(value,roundf(value)) and absf(value)<9.0e15:return int(value)
	if value is StringName:return str(value)
	return value

static func same(a:Variant,b:Variant)->bool:
	return var_to_bytes(canon(a))==var_to_bytes(canon(b))

static func pl(w,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

static func bag(w,token:String)->Dictionary:
	var inv:Dictionary=pl(w,token).inventory
	return inv

static func msg(r:Dictionary)->String:
	return str(r.get("message",""))

static func put(w,token:String,at:Vector2,region:String="home")->void:
	var p:Dictionary=pl(w,token)
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y

static func cell_of(w,resident:String)->Vector2i:
	var st:Dictionary=w.state
	var place:Array=World.bond_place(st,resident)
	var found:Vector2i=place[1]
	return found

static func region_of(w,resident:String)->String:
	var st:Dictionary=w.state
	var place:Array=World.bond_place(st,resident)
	return str(place[0])

## Stand one tile below the resident's cell (as test_resident_goal does).
static func go(w,token:String,resident:String)->Vector2i:
	var cell:=cell_of(w,resident)
	put(w,token,Vector2(float(cell.x)+0.5,float(cell.y)+1.5),region_of(w,resident))
	return cell

## PRESET: the bond record written directly (no talk/gift).
static func set_points(w,token:String,resident:String,points:int)->void:
	var p:Dictionary=pl(w,token)
	var bonds:Dictionary={}
	if p.get("bonds") is Dictionary:bonds=p.bonds
	bonds[resident]={"points":points,"talk_day":-1,"gift_day":-1}
	p["bonds"]=bonds

func act(w,token:String,action:String,cell:Vector2i,extra:String="")->Dictionary:
	serial+=1
	var r:Dictionary=w.act(token,"keepsake-req-%d"%serial,action,cell,extra)
	return r

func ok(w,token:String,action:String,cell:Vector2i,extra:String,label:String)->Dictionary:
	var r:=act(w,token,action,cell,extra)
	expect(bool(r.get("ok",false)),label+" ("+msg(r)+")")
	return r

## Rejected (exact message unless `message` is empty) and the whole world state
## byte-identical after canonicalisation.
func refuse(w,token:String,action:String,cell:Vector2i,extra:String,message:String,label:String)->void:
	var before:=var_to_bytes(canon(w.state))
	var r:=act(w,token,action,cell,extra)
	expect(not bool(r.get("ok",true)) and not msg(r).is_empty() and (message.is_empty() or msg(r)==message),"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),msg(r)])
	expect(var_to_bytes(canon(w.state))==before,"%s: whole world state byte-identical"%label)

func validates(data:Variant)->bool:
	var parsed:Variant=JSON.parse_string(JSON.stringify(data))
	if not parsed is Dictionary:return false
	return Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func write_fixture(path:String,data:Variant)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

## Saves `w` to `path` and returns the parsed JSON ({} when anything failed).
func saved(w,path:String,label:String)->Dictionary:
	w.save_path=path
	if not expect(w.save(),label+": World saves"):return {}
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(parsed is Dictionary,label+": saved file parses"):return {}
	var data:Dictionary=parsed
	return data

## Fixed home cells a keepsake must not be dropped on in this suite (NPC / resident
## standing cells, activity candidates, spawn); protected/blocked tiles are excluded
## separately by tile_free.
static func reserved_cells(w)->Array:
	var st:Dictionary=w.state
	var out:Array=[]
	for npc:String in Village.NPCS:
		var found:Variant=(Village.NPCS[npc] as Dictionary).get("cell")
		if found is Vector2i:out.append(found)
	for npc:String in Village.FESTIVAL_SPOTS:out.append(Village.FESTIVAL_SPOTS[npc])
	for resident:String in Bond.RESIDENTS:
		var place:Array=World.bond_place(st,resident)
		out.append(place[1])
	for list in [Bond.RANCH_CELLS,Bond.DOCK_CELLS,Bond.POST_CELLS,Bond.BELL_CELLS,Market.CANDIDATES,World.SHIPPING.CANDIDATES,World.COMMUNITY.CANDIDATES,Souv.CANDIDATES]:
		for c in list:out.append(c)
	out.append(Vector2i(World.SPAWN))
	return out

static func tile_free(w,c:Vector2i)->bool:
	if not World.land(c) or w.water(c) or w.protected(c) or w.blocked(c) or str(w.resource(c))!="":return false
	var k:String=World.key(c)
	for layer:String in ["objects","crops","ground","roofs","forest"]:
		var d:Dictionary=w.state[layer]
		if d.has(k):return false
	return true

## Free home tiles in rings around `origin` (closest first).
static func free_tiles(w,origin:Vector2i,count:int,skip:Array)->Array:
	var out:Array=[]
	for radius in range(0,9):
		for y in range(origin.y-radius,origin.y+radius+1):
			for x in range(origin.x-radius,origin.x+radius+1):
				if maxi(absi(x-origin.x),absi(y-origin.y))!=radius:continue
				var c:=Vector2i(x,y)
				if c in skip or c in out or not tile_free(w,c):continue
				out.append(c)
				if out.size()>=count:return out
	return out

## A standable tile centre 1.0–3.0 from every tile in `tiles` (reach 3.2; never on
## top of a tile so the "someone is standing here" guards cannot trigger).
static func spot_for(w,tiles:Array)->Vector2:
	var first:Vector2i=tiles[0]
	for radius in range(1,5):
		for y in range(first.y-radius,first.y+radius+1):
			for x in range(first.x-radius,first.x+radius+1):
				var at:=Vector2(float(x),float(y))+HALF
				if not w.can_stand(at):continue
				var fits:=true
				for t:Vector2i in tiles:
					var d:float=at.distance_to(Vector2(t)+HALF)
					if d<1.0 or d>3.0:fits=false
				if fits:return at
	return Vector2(-1,-1)

static func chest_items(w,cell:Vector2i)->Dictionary:
	var obj:Dictionary=w.state.objects.get(World.key(cell),{})
	var items:Dictionary=obj.get("items",{})
	return items

# ------------------------------------------------------------------ catalog --

func test_catalog()->void:
	expect(Goals.KEEPSAKE_ORDER.size()==18 and Goals.KEEPSAKES.size()==18,"Eighteen keepsakes in KEEPSAKES and KEEPSAKE_ORDER")
	expect(World.RESIDENT_GOALS.KEEPSAKES==Goals.KEEPSAKES,"World wires the same RESIDENT_GOALS keepsake catalogue")
	expect(Goals.keepsake_items().size()==18 and Goals.keepsake_items().has("keepsake_bobo_cart_kit"),"keepsake_items() lists eighteen kits including keepsake_bobo_cart_kit")
	var residents:={}
	var names:={}
	var other_names:={}
	for b:String in World.BUILD:
		if not Goals.KEEPSAKES.has(b):other_names[str(World.BUILD[b].name)]=b
	for item:String in World.NAMES:
		if not Goals.is_keepsake_item(item):other_names[str(World.NAMES[item])]=item
	for kind:String in Goals.KEEPSAKE_ORDER:
		expect(Goals.KEEPSAKES.has(kind),"%s is in KEEPSAKES"%kind)
		var e:Dictionary=Goals.KEEPSAKES[kind]
		var name:=str(e.name)
		var item:=Goals.keepsake_item(kind)
		var resident:=str(e.resident)
		var stage:=int(e.stage)
		expect(item==kind+"_kit" and Goals.is_keepsake_kind(kind) and Goals.is_keepsake_item(item) and not Goals.is_keepsake_item(kind),"%s item id %s"%[kind,item])
		expect(Goals.keepsake_items()[Goals.KEEPSAKE_ORDER.find(kind)]==item,"%s: keepsake_items() keeps KEEPSAKE_ORDER"%kind)
		expect(resident in Bond.RESIDENTS and Goals.has_goal(resident,stage),"%s belongs to an existing goal %s %d"%[kind,resident,stage])
		expect(Goals.keepsake_kind(resident,stage)==kind,"%s: keepsake_kind(%s,%d) finds it"%[kind,resident,stage])
		if kind=="keepsake_bobo_cart":expect(name=="祖父的礦車","%s is named 祖父的礦車 (the goal's journal text may differ)"%kind)
		else:expect(str(Goals.goal(resident,stage).keepsake)==name,"%s: name equals the goal's journal keepsake text"%kind)
		expect(not str(e.blurb).is_empty(),"%s has a blurb"%kind)
		residents[resident]=true
		names[name]=true
		# BUILD / NAMES wiring.
		expect(World.BUILD.has(kind) and same(World.BUILD[kind],{"name":name,item:1}),"%s places 1:1 from its kit via World.BUILD"%kind)
		expect(World.BUILD.has(kind) and str(World.BUILD[kind].name)==name and World.NAMES.has(item) and str(World.NAMES[item])==name,"%s: BUILD name == KEEPSAKES name == NAMES[kit]"%kind)
		expect(not kind in World.UNDO_SOLID,"%s is walk-through decor (not in UNDO_SOLID)"%kind)
		# No collisions with other features.
		expect(not World.NAMES.has(kind),"%s is not an inventory item id"%kind)
		expect(not World.BUILD.has(item),"%s is not a build kind"%item)
		expect(not World.RECIPES.has(item),"%s cannot be crafted"%item)
		expect(not Souv.ENTRIES.has(kind) and not item in Souv.items(),"%s does not collide with a souvenir entry"%kind)
		var users:=0
		for b:String in World.BUILD:
			if (World.BUILD[b] as Dictionary).has(item):users+=1
		expect(users==1,"%s is consumed by exactly one BUILD recipe (%d)"%[item,users])
		expect(not other_names.has(name),"%s: name '%s' not used by another BUILD kind or item (%s)"%[kind,name,str(other_names.get(name,""))])
	expect(residents.size()==12,"All twelve residents have keepsakes (%d residents)"%residents.size())
	expect(names.size()==18,"Eighteen distinct names")
	expect(Goals.keepsake_kind("aru",2)=="" and Goals.keepsake_item("bogus")=="" and not Goals.is_keepsake_item("wood") and not Goals.is_keepsake_item("trio_keepsake_kit"),"Negative lookups")

# 2. Not a currency: no price, not tradeable, not stall-listable, no shipping quote.
func test_static_not_currency()->void:
	var prices:=World.SHIPPING.prices(World.CROPS,World.FISH,World.OTHER_SALES)
	var tradable:=World.trade_items()
	for item:String in Goals.keepsake_items():
		expect(not prices.has(item),"%s has no shipping price"%item)
		expect(not World.CROPS.has(item) and not World.FISH.has(item) and not World.OTHER_SALES.has(item),"%s is not a crop/fish/other sale"%item)
		expect(not Market.sellable(item) and not item in Market.sellable_items(),"%s is not stall-listable"%item)
		expect(not tradable.has(item),"%s is not tradeable"%item)
		var q:Dictionary=World.SHIPPING.quote([[item,1]],{item:1},prices)
		expect(not bool(q.get("ok",true)),"%s: shipping quote refused"%item)
	expect(tradable.has("wood"),"Trade list keeps ordinary items")

# ---------------------------------------------------------------- placement --

func test_placement()->World:
	var w:=World.new()
	w.add_player(ALPHA,"甲")
	w.add_player(BETA,"乙")
	w.state["picnic"]=true  # PRESET: plaza features (market stall, shipping) open
	w.state["time"]=START   # PRESET
	var tiles:Array=free_tiles(w,ORIGIN,21,reserved_cells(w))  # 3 work tiles + one bulk tile per keepsake (18)
	if not expect(tiles.size()==21,"Twenty-one free home tiles near %s (%d)"%[str(ORIGIN),tiles.size()]):return null
	build_tile=tiles[0]
	move_tile=tiles[1]
	chest_tile=tiles[2]
	bulk=tiles.slice(3)
	work_spot=spot_for(w,[build_tile,move_tile,chest_tile])
	if not expect(work_spot.x>=0.0,"A standing spot within reach of build/move/chest tiles %s %s %s"%[str(build_tile),str(move_tile),str(chest_tile)]):return null
	put(w,ALPHA,work_spot)
	put(w,BETA,work_spot)
	var inv:=bag(w,ALPHA)
	inv["wood"]=int(inv.get("wood",0))+20  # PRESET: wood for the chest
	ok(w,ALPHA,"build",chest_tile,"chest","alpha builds a shared chest")
	expect(str(w.state.objects.get(World.key(chest_tile),{}).get("type",""))=="chest","chest on the home layer")
	for kind:String in Goals.KEEPSAKE_ORDER:place_cycle(w,kind)
	for item:String in Goals.keepsake_items():
		expect(int(bag(w,ALPHA).get(item,0))==1,"after its cycle alpha holds exactly one %s"%item)
	return w

## Build / refuse / move / foreign remove / owner remove / chest for one kind.
func place_cycle(w,kind:String)->void:
	var item:=Goals.keepsake_item(kind)
	var name:=str(Goals.KEEPSAKES[kind].name)
	var short:="材料不足，需要%s 1"%name
	put(w,ALPHA,work_spot)
	put(w,BETA,work_spot)
	var held:=bag(w,ALPHA)
	held.erase(item)
	refuse(w,ALPHA,"build",build_tile,kind,short,kind+": build without a kit")
	expect(not w.state.objects.has(World.key(build_tile)),kind+": nothing placed without a kit")
	held=bag(w,ALPHA)
	held[item]=1  # PRESET: one kit in the bag (not earned in this world)
	var before:Dictionary=bag(w,ALPHA).duplicate(true)
	ok(w,ALPHA,"build",build_tile,kind,"alpha places "+kind)
	var want:Dictionary=before.duplicate(true)
	want[item]=0
	expect(same(bag(w,ALPHA),want),kind+": build consumes exactly one kit and nothing else")
	expect(same(w.state.objects.get(World.key(build_tile),{}),{"type":kind,"owner":ALPHA,"items":{}}),kind+": object type == kind, owner == alpha, on the home objects layer")
	expect(not w.blocked(build_tile) and w.can_stand(Vector2(build_tile)+HALF),kind+": tile stays walkable (not blocked, can_stand)")
	refuse(w,ALPHA,"build",move_tile,kind,short,kind+": second placement without a kit")
	# Another player can neither pick it up nor move it.
	refuse(w,BETA,"remove",build_tile,"","",kind+": beta removes alpha's keepsake")
	refuse(w,BETA,"move_object",build_tile,"%d,%d"%[move_tile.x,move_tile.y],"",kind+": beta moves alpha's keepsake")
	# Owner moves it.
	var before_move:Dictionary=bag(w,ALPHA).duplicate(true)
	ok(w,ALPHA,"move_object",build_tile,"%d,%d"%[move_tile.x,move_tile.y],"alpha moves "+kind)
	expect(same(w.state.objects.get(World.key(move_tile),{}),{"type":kind,"owner":ALPHA,"items":{}}) and not w.state.objects.has(World.key(build_tile)),kind+": moved (at the new tile, none at the old)")
	expect(same(bag(w,ALPHA),before_move),kind+": moving changes no kit count")
	expect(not w.blocked(move_tile) and not w.blocked(build_tile),kind+": both tiles walkable after the move")
	# Owner picks it up: exactly one kit back.
	var before_remove:Dictionary=bag(w,ALPHA).duplicate(true)
	var r:=ok(w,ALPHA,"remove",move_tile,"","alpha picks up "+kind)
	expect(msg(r)==REMOVED_MSG,kind+": removal message (%s)"%msg(r))
	var back:Dictionary=before_remove.duplicate(true)
	back[item]=int(back.get(item,0))+1
	expect(same(bag(w,ALPHA),back) and int(bag(w,ALPHA).get(item,0))==1,kind+": removal returns exactly 1 kit")
	expect(not w.state.objects.has(World.key(move_tile)) and not w.state.objects.has(World.key(build_tile)),kind+": object deleted")
	# Chest: in and out.
	ok(w,ALPHA,"deposit",chest_tile,item,kind+": kit goes into the chest")
	expect(int(bag(w,ALPHA).get(item,0))==0 and int(chest_items(w,chest_tile).get(item,0))==1,kind+": kit stored in the chest")
	ok(w,ALPHA,"withdraw",chest_tile,item,kind+": kit comes back out of the chest")
	expect(int(bag(w,ALPHA).get(item,0))==1 and int(chest_items(w,chest_tile).get(item,0))==0,kind+": kit back in the bag")

# Real sell / ship / market_stock actions are refused for every kit.
func test_actions_not_currency(w)->void:
	var box:Vector2i=World.SHIPPING.cell_for(w.state)
	var stall:Vector2i=Market.cell_for(w.state)
	for item:String in Goals.keepsake_items():
		expect(int(bag(w,ALPHA).get(item,0))==1,"alpha holds one %s for the currency checks"%item)
		put(w,ALPHA,Vector2(43.5,30.5))
		refuse(w,ALPHA,"sell",Vector2i(43,29),item,NOT_LISTED,"sell %s at the seed shop"%item)
		put(w,ALPHA,Vector2(box)+Vector2(0.5,1.5))
		refuse(w,ALPHA,"ship",box,JSON.stringify([[[item,1]],10]),SHIP_REFUSED,"ship %s"%item)
		put(w,ALPHA,Vector2(stall)+Vector2(1.5,0.5))
		refuse(w,ALPHA,"market_stock",stall,item+":1","%s不能擺上市集攤位；攤位只收農漁產、料理和花。"%str(World.NAMES[item]),"stock %s on the market stall"%item)
		expect(int(bag(w,ALPHA).get(item,0))==1,"%s still in the bag after the refusals"%item)
	put(w,ALPHA,work_spot)

# Saves with kits in the bag, in a chest, and placed; reload round trip.
func test_placement_saves(w)->void:
	var path:=temp_path("place")
	# a) All kits in the bag.
	var data:=saved(w,path,"kits in bag")
	expect(not data.is_empty() and validates(data),"Save with 18 keepsake kits in the bag validates")
	# b) Check every kit through the real 16-slot chest and a save/reload, in batches.
	put(w,ALPHA,work_spot)
	const CAPACITY=preload("res://scripts/box_capacity.gd").SLOTS
	var items:=Goals.keepsake_items()
	for offset in range(0,items.size(),CAPACITY):
		var batch:=items.slice(offset,offset+CAPACITY)
		for item:String in batch:ok(w,ALPHA,"deposit",chest_tile,item,"deposit %s"%item)
		for item:String in batch:expect(int(chest_items(w,chest_tile).get(item,0))==1 and int(bag(w,ALPHA).get(item,0))==0,"%s sits in the chest"%item)
		data=saved(w,path,"kits in chest")
		expect(not data.is_empty() and validates(data),"Save with the deposited kits validates")
		var mid:=World.new()
		expect(mid.load_world(path),"Save with kits in a chest reloads")
		expect(same(chest_items(mid,chest_tile),chest_items(w,chest_tile)),"Chest contents survive reload (canonical)")
		for item:String in batch:ok(w,ALPHA,"withdraw",chest_tile,item,"withdraw %s"%item)
	# c) All kits placed.
	var index:=0
	for kind:String in Goals.KEEPSAKE_ORDER:
		var tile:Vector2i=bulk[index]
		index+=1
		var spot:=spot_for(w,[tile])
		if not expect(spot.x>=0.0,"standing spot for %s at %s"%[kind,str(tile)]):continue
		put(w,ALPHA,spot)
		ok(w,ALPHA,"build",tile,kind,"alpha places %s at %s for the save test"%[kind,str(tile)])
		expect(str(w.state.objects.get(World.key(tile),{}).get("type",""))==kind,"%s placed at %s"%[kind,str(tile)])
	for item:String in Goals.keepsake_items():expect(int(bag(w,ALPHA).get(item,0))==0,"%s consumed by the bulk placement"%item)
	# Trivial: a world tick with all 12 placed does not error or disturb them.
	w.save_path=""
	w.step(0.5,true)
	var placed:=0
	for obj in w.state.objects.values():
		if obj is Dictionary and Goals.is_keepsake_kind(str(obj.get("type",""))):placed+=1
	expect(placed==18,"Eighteen keepsakes placed after a world tick (%d)"%placed)
	data=saved(w,path,"kits placed")
	expect(not data.is_empty() and validates(data),"Save with 18 keepsakes placed validates")
	var reloaded:=World.new()
	if not expect(reloaded.load_world(path),"Fresh world reloads the placement save"):return
	expect(same(reloaded.state.objects,w.state.objects),"state.objects survives reload (canonical)")
	for token:String in [ALPHA,BETA]:
		expect(same(bag(reloaded,token),bag(w,token)),"%s inventory survives reload (canonical)"%token.left(14))
	# Reloaded world keeps working: the owner picks one up and gets the kit back.
	reloaded.active_tokens={ALPHA:true,BETA:true}
	var first:Vector2i=bulk[0]
	var first_kind:String=Goals.KEEPSAKE_ORDER[0]
	put(reloaded,ALPHA,spot_for(reloaded,[first]))
	ok(reloaded,ALPHA,"remove",first,"","alpha picks %s up after reload"%first_kind)
	expect(int(bag(reloaded,ALPHA).get(Goals.keepsake_item(first_kind),0))==1,"Kit back in the bag after reload")

# ------------------------------------------------------------------- earned --

func test_earned()->void:
	var w:=World.new()
	w.add_player(EARN,"丙")
	w.add_player(LEGACY,"丁")
	var tiles:Array=free_tiles(w,ORIGIN,2,reserved_cells(w))
	if not expect(tiles.size()==2,"Two free home tiles for the earned case"):return
	var bed_tile:Vector2i=tiles[0]
	var ks_tile:Vector2i=tiles[1]
	var spot:=spot_for(w,[bed_tile,ks_tile])
	if not expect(spot.x>=0.0,"Standing spot for the bed and the keepsake"):return
	var kind:="keepsake_aru"
	var item:=Goals.keepsake_item(kind)
	var name:=str(Goals.KEEPSAKES[kind].name)
	set_points(w,EARN,"aru",int(Bond.THRESHOLDS[0]))  # PRESET: bond stage 1 with 阿榆
	expect(Bond.stage(pl(w,EARN),"aru")==1,"preset bond is exactly stage 1")
	var inv:=bag(w,EARN)
	inv["wood"]=25  # PRESET: 15 for the bed + 10 for aru 1
	inv["fiber"]=10  # PRESET: for the bed
	# Without a bed the goal is refused (own_bed).
	var aru:=go(w,EARN,"aru")
	refuse(w,EARN,Goals.ACTION,aru,"aru:1::","還不能一起做這件事：要先「%s」。"%str(Goals.NEEDS["own_bed"]),"aru 1 before the bed")
	refuse(w,EARN,Goals.CLAIM_ACTION,aru,"aru:1","先和%s一起完成〈%s〉，才有紀念小物。"%[Bond.name_of("aru"),str(Goals.goal("aru",1).title)],"claim before aru 1 is done")
	put(w,EARN,spot)
	put(w,LEGACY,spot)
	ok(w,EARN,"build",bed_tile,"bed","earn builds a bed")
	expect(Goals.need_met("own_bed",w.state,EARN),"own_bed now holds")
	aru=go(w,EARN,"aru")
	var before:Dictionary=bag(w,EARN).duplicate(true)
	var r:=ok(w,EARN,Goals.ACTION,aru,"aru:1::","earn completes aru 1 through resident_goal")
	expect(msg(r).contains("紀念小物也放進背包了"),"success message mentions the keepsake (%s)"%msg(r))
	var want:Dictionary=before.duplicate(true)
	want["wood"]=int(before.get("wood",0))-10
	want[item]=1
	expect(same(bag(w,EARN),want),"aru 1 takes 10 wood and grants exactly one %s (%s)"%[item,str(bag(w,EARN))])
	expect(same(pl(w,EARN).get(Goals.RECORD_KEY),{"aru":{"1":""}}),"bond_goals records aru 1")
	expect(same(pl(w,EARN).get(Goals.KEEPSAKE_KEY),{kind:true}),"bond_keepsakes records keepsake_aru")
	expect(Goals.keepsake_claimed(pl(w,EARN),kind),"keepsake_claimed sees it")
	refuse(w,EARN,Goals.CLAIM_ACTION,aru,"aru:1","「%s」已經領過了。"%name,"claim after earning")
	# Place the earned kit.
	put(w,EARN,spot)
	ok(w,EARN,"build",ks_tile,kind,"earn places the earned keepsake")
	expect(same(w.state.objects.get(World.key(ks_tile),{}),{"type":kind,"owner":EARN,"items":{}}),"earned keepsake on the home layer, owned by earn")
	expect(int(bag(w,EARN).get(item,0))==0,"earned kit consumed")
	expect(not w.blocked(ks_tile) and w.can_stand(Vector2(ks_tile)+HALF),"earned keepsake is walk-through")
	var gallery_board:=Vector2i(40,29)
	put(w,EARN,Vector2(40.5,30.5))
	ok(w,EARN,"collection_donate",gallery_board,item,"catalog the earned keepsake while it is placed")
	ok(w,EARN,"collection_display",gallery_board,item,"publicly exhibit the record")
	expect(w.state.objects.get(World.key(ks_tile),{}).get("type")==kind and int(bag(w,EARN).get(item,0))==0,
		"The gallery leaves the original furniture in place and does not mint a second copy")
	# Legacy completion (before batch 3) claimed later.
	set_points(w,LEGACY,"aru",int(Bond.THRESHOLDS[0]))  # PRESET
	var leg_cell:=go(w,LEGACY,"aru")
	refuse(w,LEGACY,Goals.CLAIM_ACTION,leg_cell,"aru:2","這件事的紀念收在手帳裡，沒有可以領的小物。","claim for a goal without a keepsake")
	var legacy_person:=pl(w,LEGACY)
	legacy_person[Goals.RECORD_KEY]={"aru":{"1":""}}  # PRESET: aru 1 finished before batch 3
	var leg_before:Dictionary=bag(w,LEGACY).duplicate(true)
	r=ok(w,LEGACY,Goals.CLAIM_ACTION,leg_cell,"aru:1","legacy claims the keepsake")
	expect(msg(r)=="%s把紀念小物「%s」交給你，已放進背包。在家園工坊的「生活」頁選它就能擺到家園。"%[Bond.name_of("aru"),name],"claim message (%s)"%msg(r))
	var leg_want:Dictionary=leg_before.duplicate(true)
	leg_want[item]=1
	expect(same(bag(w,LEGACY),leg_want),"claim grants exactly one kit")
	expect(same(pl(w,LEGACY).get(Goals.KEEPSAKE_KEY),{kind:true}),"claim records bond_keepsakes")
	refuse(w,LEGACY,Goals.CLAIM_ACTION,leg_cell,"aru:1","「%s」已經領過了。"%name,"second claim")
	put(w,LEGACY,spot)
	earned_saves(w,ks_tile,spot)

func earned_saves(w,ks_tile:Vector2i,spot:Vector2)->void:
	var path:=temp_path("earned")
	var fixture:=temp_path("fixture")
	var base:=saved(w,path,"earned world")
	if base.is_empty():return
	expect(validates(base),"Earned world (bond_keepsakes present, goal done) validates")
	var without:Dictionary=base.duplicate(true)
	(without.players[EARN] as Dictionary).erase(Goals.KEEPSAKE_KEY)
	(without.players[LEGACY] as Dictionary).erase(Goals.KEEPSAKE_KEY)
	expect(validates(without),"Same save without bond_keepsakes (goal done) validates")
	expect(write_fixture(fixture,without) and World.new().load_world(fixture),"Save without bond_keepsakes loads")
	expect(write_fixture(fixture,base) and World.new().load_world(fixture),"Control fixture loads")
	var probe:=World.new()
	var pristine:Dictionary=probe.state.duplicate(true)
	var labels:=["empty record","unknown kind","kit id as kind","value false","value 1","value string","goal not done","goal record removed",
		"record is a list","record is a string","record is null","record is a number"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(not validates(bad),"Schema rejects bond_keepsakes: "+label)
		expect(write_fixture(fixture,bad),"Write tampered fixture: "+label)
		expect(not probe.load_world(fixture),"load_world rejects bond_keepsakes: "+label)
		expect(probe.state==pristine,"Rejected load leaves the world untouched: "+label)
	# Round trip.
	var reloaded:=World.new()
	if not expect(reloaded.load_world(path),"Fresh world reloads the earned save"):return
	expect(same(reloaded.state.objects,w.state.objects),"Earned world objects survive reload")
	for token:String in [EARN,LEGACY]:
		expect(same(bag(reloaded,token),bag(w,token)),"%s inventory survives reload"%token.left(14))
		expect(same(pl(reloaded,token).get(Goals.KEEPSAKE_KEY),pl(w,token).get(Goals.KEEPSAKE_KEY)),"%s bond_keepsakes survive reload"%token.left(14))
		expect(same(pl(reloaded,token).get(Goals.RECORD_KEY),pl(w,token).get(Goals.RECORD_KEY)),"%s bond_goals survive reload"%token.left(14))
	expect(Goals.keepsake_claimed(pl(reloaded,EARN),"keepsake_aru") and pl(reloaded,EARN)[Goals.KEEPSAKE_KEY]["keepsake_aru"] is bool,"Reloaded claim flag is a real bool true")
	expect(pl(reloaded,EARN).get("collection_display",[])==["keepsake_aru_kit"],"The displayed story entry survives reloading")
	reloaded.active_tokens={EARN:true,LEGACY:true}
	put(reloaded,EARN,spot)
	ok(reloaded,EARN,"remove",ks_tile,"","earn picks the earned keepsake up after reload")
	expect(int(bag(reloaded,EARN).get("keepsake_aru_kit",0))==1 and not reloaded.state.objects.has(World.key(ks_tile)),"Earned kit back in the bag after reload")

func tampered(base:Dictionary,label:String)->Dictionary:
	var s:Dictionary=base.duplicate(true)
	var p:Dictionary=s.players[EARN]
	match label:
		"empty record":p[Goals.KEEPSAKE_KEY]={}
		"unknown kind":p[Goals.KEEPSAKE_KEY]={"keepsake_aru":true,"keepsake_bogus":true}
		"kit id as kind":p[Goals.KEEPSAKE_KEY]={"keepsake_aru_kit":true}
		"value false":p[Goals.KEEPSAKE_KEY]={"keepsake_aru":false}
		"value 1":p[Goals.KEEPSAKE_KEY]={"keepsake_aru":1}
		"value string":p[Goals.KEEPSAKE_KEY]={"keepsake_aru":"true"}
		"goal not done":p[Goals.KEEPSAKE_KEY]={"keepsake_aru":true,"keepsake_milu":true}
		"goal record removed":p.erase(Goals.RECORD_KEY)
		"record is a list":p[Goals.KEEPSAKE_KEY]=["keepsake_aru"]
		"record is a string":p[Goals.KEEPSAKE_KEY]="keepsake_aru"
		"record is null":p[Goals.KEEPSAKE_KEY]=null
		"record is a number":p[Goals.KEEPSAKE_KEY]=1
	return s
