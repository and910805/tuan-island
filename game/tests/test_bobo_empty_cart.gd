extends SceneTree
## T066 N03-4「最後一趟空車」acceptance for res://scripts/bobo_empty_cart.gd through the REAL
## World actions (World.act: bobo_empty_cart start / push, ore_cart, resident_goal,
## resident_keepsake), World.save / load_world, SaveSchema and an in-process Session snapshot.
##
## REAL ACTIONS: every start, every push (all 6 stops), every refusal, the ordinary ore_cart
## load / push / unload used for the "does not disturb the work cart" checks, the bobo 4
## resident_goal that grants keepsake_bobo_cart_kit, and the resident_keepsake claim.
## PRESET (written straight into world state, disclosed): the Bobo bond points
## (player.bonds.bobo={points,talk_day:-1,gift_day:-1}), player region/x/y (standing spots,
## no travel action), and in the legacy test the old completion record
## player.bond_goals={"bobo":{"4":"home"}} WITHOUT bond_keepsakes / kit (a goal finished before
## this wave). Tampered copies of a saved JSON are the schema fixtures.
## Nothing here reads the real clock; temp file names are the only randomness.
const World=preload("res://scripts/world.gd")
const Cart=preload("res://scripts/bobo_empty_cart.gd")
const Ore=preload("res://scripts/ore_route.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const FIELD:="bobo_empty_cart_stage"
const OWN:="own_bobo_empty_cart"
const KIND:="keepsake_bobo_cart"
const ITEM:="keepsake_bobo_cart_kit"
const NEED_LABEL:="在金瓜石把祖父的空礦車推到展覽位"
const ALPHA:="bobo-cart-alpha-token-31c2"
const BETA:="bobo-cart-beta-token-77d0"
const GAMMA:="bobo-cart-gamma-token-9e41"
const OLD:="bobo-cart-old-token-5b08"
const SAVER:="bobo-cart-saver-token-a6f3"
var checks:=0
var failures:=0
var serial:=0
var _cleanup:Array[String]=[]

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
	print("BOBO_EMPTY_CART_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_contract()
	test_accessors()
	test_journey()
	test_refusals()
	test_persistence()
	test_legacy_reward()
	await test_snapshot()
	finish()

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String)->String:
	var path:=OS.get_environment("TEMP").path_join("bobo-cart-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])
	_cleanup.append(path)
	return path

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

static func bytes(value:Variant)->PackedByteArray:
	return var_to_bytes(canon(value))

static func pl(w,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

static func msg(r:Dictionary)->String:
	return str(r.get("message",""))

static func bobo_cell(w)->Vector2i:
	var place:Array=World.bond_place(w.state,"bobo")
	var cell:Vector2i=place[1]
	return cell

static func stand(w,token:String,cell:Vector2i)->void:
	var p:Dictionary=pl(w,token)
	p["x"]=float(cell.x)+0.5
	p["y"]=float(cell.y)+1.5

static func go(w,token:String,region:String,cell:Vector2i)->void:
	pl(w,token)["region"]=region
	stand(w,token,cell)

## PRESET: the Bobo bond at `points` (no talk/gift).
static func bond(w,token:String,points:int)->void:
	var p:Dictionary=pl(w,token)
	var bonds:Dictionary={}
	if p.get("bonds") is Dictionary:bonds=p.bonds
	bonds["bobo"]={"points":points,"talk_day":-1,"gift_day":-1}
	p["bonds"]=bonds

static func stage_of(w,token:String)->int:
	return int(pl(w,token).get(FIELD,0))

func act(w,token:String,action:String,cell:Vector2i,extra:String,request:String="")->Dictionary:
	serial+=1
	var id:String=request if not request.is_empty() else "cart-req-%d"%serial
	var r:Dictionary=w.act(token,id,action,cell,extra)
	return r

func start(w,token:String,request:String="")->Dictionary:
	return act(w,token,Cart.ACTION,bobo_cell(w),"start",request)

func push(w,token:String,cell:Vector2i,request:String="")->Dictionary:
	return act(w,token,Cart.ACTION,cell,"push",request)

## Rejected with `message` (exact unless empty) and the whole world state byte-identical.
func refuse(w,token:String,action:String,cell:Vector2i,extra:String,message:String,label:String)->void:
	var before:=bytes(w.state)
	var r:=act(w,token,action,cell,extra)
	expect(not bool(r.get("ok",true)) and (message.is_empty() or msg(r)==message),"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),msg(r)])
	expect(bytes(w.state)==before,"%s: whole world state byte-identical"%label)

func refuse_cart(w,token:String,cell:Vector2i,extra:String,message:String,label:String)->void:
	refuse(w,token,Cart.ACTION,cell,extra,message,label)

func need_msg()->String:
	return "還不能一起做這件事：要先「%s」。"%NEED_LABEL

func write_fixture(path:String,data:Variant)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func validates(data:Variant)->bool:
	var parsed:Variant=JSON.parse_string(JSON.stringify(data))
	if not parsed is Dictionary:return false
	return Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

## The parts of a player record a story push must never change (no coins, bag, bond or goal record).
static func ledger(p:Dictionary)->Dictionary:
	return {"coins":p.get("coins"),"inventory":(p.get("inventory",{}) as Dictionary).duplicate(true),"bonds":(p.get("bonds",{}) as Dictionary).duplicate(true),
		"bond_goals":p.get("bond_goals"),"bond_keepsakes":p.get("bond_keepsakes")}

# ----------------------------------------------------------------- contract --

func test_contract()->void:
	expect(World.BOBO_EMPTY_CART==Cart,"World.BOBO_EMPTY_CART is the bobo_empty_cart.gd module")
	expect(Cart.ACTION=="bobo_empty_cart" and Cart.FIELD==FIELD and Cart.OWN_KEY==OWN,"ACTION bobo_empty_cart, FIELD bobo_empty_cart_stage, OWN_KEY own_bobo_empty_cart")
	expect(Cart.STOPS==Ore.STOPS and Ore.STOPS.size()==7 and Cart.PUSHES==6 and Cart.LAST==7,"STOPS is OreRoute.STOPS (7 cells), 6 pushes, arrives at stage 7")
	expect(Cart.ACTION not in Ore.ACTIONS and Cart.ACTION not in Goals.ACTIONS,"the story action is its own action (not ore_cart, not a resident goal action)")
	expect(Cart.KEEPSAKE_KIND==KIND and Cart.KEEPSAKE_ITEM==ITEM and Cart.KEEPSAKE_NAME=="祖父的礦車","keepsake kind / item / name constants")
	expect(Goals.keepsake_kind("bobo",4)==KIND and Goals.keepsake_item(KIND)==ITEM,"bobo 4 maps to keepsake_bobo_cart / keepsake_bobo_cart_kit")
	expect(World.BUILD.get(KIND)=={"name":"祖父的礦車",ITEM:1} and World.NAMES.get(ITEM)=="祖父的礦車","World.BUILD / NAMES register the cart keepsake (1 kit, 祖父的礦車)")
	expect(not World.trade_items().has(ITEM) and not World.OTHER_SALES.has(ITEM) and not World.CROPS.has(ITEM),"the cart kit has no price and cannot be traded")
	expect(Goals.goal("bobo",4).get("needs")==["bobo_cart_arrived"] and Goals.goal("bobo",4).get("options",[]).size()==3,"bobo 4 needs bobo_cart_arrived and keeps its three inscription options")
	expect(Goals.cost(Goals.goal("bobo",4),"home").is_empty(),"bobo 4 costs no items")
	expect(Session.PROTOCOL==53,"Session.PROTOCOL is 53")
	var release:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://release.json"))
	expect(release is Dictionary and int(release.get("protocol",0))==53,"release.json protocol is 53")

func test_accessors()->void:
	expect(Cart.stage({})==0 and not Cart.active({}) and Cart.cart_cell({})==Vector2i(-1,-1) and Cart.label({})=="","empty snapshot: stage 0, idle, no cart cell, no label")
	for at in range(1,8):
		var snap:Dictionary={OWN:at}
		expect(Cart.stage(snap)==at and Cart.active(snap)==(at<=6),"snapshot stage %d: active only for 1..6"%at)
		expect(Cart.cart_cell(snap)==Ore.STOPS[at-1],"snapshot stage %d: cart stands at STOPS[%d]"%[at,at-1])
		expect(not Cart.label(snap).is_empty() and (at<7 or Cart.label(snap)==Cart.LABEL_END),"snapshot stage %d: label"%at)
	expect(Cart.stage({OWN:3.0})==3,"a whole float counts as its integer")
	for bad:Variant in [0,-1,8,100,2.5,"3",true,null,[3],{},INF,NAN]:
		var snap:Dictionary={OWN:bad}
		expect(Cart.stage(snap)==0 and not Cart.active(snap) and Cart.label(snap)=="" and Cart.cart_cell(snap)==Vector2i(-1,-1),"snapshot value %s is read as no cart"%str(bad))
	expect(Cart.own_value({FIELD:4})==4 and Cart.own_value({})==0 and Cart.own_value({FIELD:"4"})==0 and Cart.own_value(null)==0,"own_value is the integer or 0")

# ------------------------------------------------------------------ journey --

func test_journey()->void:
	var w:=World.new()
	w.add_player(ALPHA,"甲")
	w.add_player(BETA,"乙")
	w.add_player(GAMMA,"丙")
	bond(w,ALPHA,int(Bond.THRESHOLDS[3]))
	bond(w,BETA,int(Bond.THRESHOLDS[3]))
	bond(w,GAMMA,int(Bond.THRESHOLDS[2]))
	var bobo:=bobo_cell(w)
	expect(str(World.bond_place(w.state,"bobo")[0])=="jinguashi","control: bobo stands in jinguashi")
	for token:String in [ALPHA,BETA,GAMMA]:go(w,token,"jinguashi",bobo)
	var stops:Array=Ore.STOPS
	# GAMMA is one stage short of the fourth: cannot start.
	refuse_cart(w,GAMMA,bobo,"start",Cart.NEED_BOND,"rank 3 cannot start")
	# ALPHA starts. Nothing but the one field changes.
	var gamma_bytes:=bytes(pl(w,GAMMA))
	var beta_bytes:=bytes(pl(w,BETA))
	var before:=ledger(pl(w,ALPHA))
	var r:=start(w,ALPHA,"cart-start-alpha")
	expect(bool(r.get("ok",false)) and msg(r)==Cart.START_OK,"alpha starts the empty cart (got '%s')"%msg(r))
	expect(stage_of(w,ALPHA)==1 and typeof(pl(w,ALPHA)[FIELD])==TYPE_INT,"stage is the integer 1 and the cart waits at STOPS[0]")
	expect(ledger(pl(w,ALPHA))==before,"start changes no coins, bag, bond or goal record")
	expect(bytes(pl(w,BETA))==beta_bytes and bytes(pl(w,GAMMA))==gamma_bytes,"start leaves the other players' whole records byte-identical")
	expect(not w.state.has("ore_route"),"start does not write the work cart's ore_route record")
	# Replaying the same request id applies nothing a second time.
	var after_start:=bytes(w.state)
	var replay:=start(w,ALPHA,"cart-start-alpha")
	expect(replay==r and bytes(w.state)==after_start and stage_of(w,ALPHA)==1,"replayed start request returns the stored receipt and changes nothing")
	refuse_cart(w,ALPHA,bobo,"start",Cart.STARTED,"a second start while pushing")
	# The goal stays shut until arrival.
	refuse(w,ALPHA,Goals.ACTION,bobo,"bobo:4:home:",need_msg(),"goal at stage 1")
	# Six pushes, one STOPS step each.
	for at in range(1,7):
		var cart:Vector2i=stops[at-1]
		expect(stage_of(w,ALPHA)==at,"before push %d the stage is %d"%[at,at])
		stand(w,ALPHA,cart)
		for bad_extra:String in ["","PUSH","push ","go","push:1","start:1"," push"]:
			refuse_cart(w,ALPHA,cart,bad_extra,Cart.BAD_EXTRA,"push %d: extra '%s'"%[at,bad_extra])
		var wrong:Array=[stops[at],stops[(at+2)%7],stops[(at+4)%7],cart+Vector2i.RIGHT,cart+Vector2i.DOWN,cart+Vector2i.LEFT+Vector2i.UP,Vector2i(-1,-1),Vector2i(0,0),Vector2i(2147483647,2147483647),Vector2i(-2147483648,-2147483648)]
		for cell:Vector2i in wrong:
			if cell==cart:continue
			# Cells outside the map may be refused earlier by World with its own text: any refusal counts there.
			refuse_cart(w,ALPHA,cell,"push",Cart.WRONG_CELL if cell.x>=0 and cell.x<1000 and cell.y>=0 and cell.y<1000 else "","push %d: cell %s is not where the cart stands"%[at,str(cell)])
		var away:=pl(w,ALPHA)
		away["x"]=float(cart.x)+0.5+4.0
		away["y"]=float(cart.y)+0.5
		refuse_cart(w,ALPHA,cart,"push",Cart.TOO_FAR,"push %d: four tiles from the cart"%at)
		stand(w,ALPHA,cart)
		if at==3:
			# While pushing, the same user's ordinary work cart is blocked; other players' are not.
			refuse(w,ALPHA,Ore.ACTION,stops[0],"load",Cart.ORE_BLOCKED,"alpha's ore_cart load while pushing the story cart")
			stand(w,ALPHA,cart)
			work_cart_unaffected(w,BETA,stops)
			stand(w,ALPHA,cart)
			gamma_bytes=bytes(pl(w,GAMMA))
		before=ledger(pl(w,ALPHA))
		r=push(w,ALPHA,cart)
		var want:String=Cart.PUSH_LAST if at==6 else (Cart.PUSH_OK%[at,6-at])
		expect(bool(r.get("ok",false)) and msg(r)==want,"push %d succeeds with '%s' (got '%s')"%[at,want,msg(r)])
		expect(stage_of(w,ALPHA)==at+1 and typeof(pl(w,ALPHA)[FIELD])==TYPE_INT,"push %d moves the cart to stage %d (STOPS[%d])"%[at,at+1,at])
		expect(Cart.cart_cell({OWN:stage_of(w,ALPHA)})==stops[at],"push %d: the cart now stands at STOPS[%d]"%[at,at])
		expect(ledger(pl(w,ALPHA))==before,"push %d: no coins, bag, bond or goal change"%at)
		if at<6:
			go(w,ALPHA,"jinguashi",bobo)
			refuse(w,ALPHA,Goals.ACTION,bobo,"bobo:4:home:",need_msg(),"goal after push %d (not arrived yet)"%at)
	expect(stage_of(w,ALPHA)==7,"six pushes end at the display stage 7")
	expect(bytes(pl(w,GAMMA))==gamma_bytes,"gamma (never started) is untouched by alpha's six pushes")
	# Arrived: no more pushes, no restart, even at the right cell.
	stand(w,ALPHA,stops[6])
	refuse_cart(w,ALPHA,stops[6],"push",Cart.ARRIVED,"push after arrival")
	go(w,ALPHA,"jinguashi",bobo)
	refuse_cart(w,ALPHA,bobo,"start",Cart.ARRIVED,"start after arrival")
	# Arrived is not active any more: the work cart is free again for alpha.
	stand(w,ALPHA,stops[0])
	r=act(w,ALPHA,Ore.ACTION,stops[0],"load")
	expect(bool(r.get("ok",false)) and Ore.stage(w.state,ALPHA)==1 and stage_of(w,ALPHA)==7,"after arrival alpha's ore_cart works again and the story stage stays 7 (got '%s')"%msg(r))
	# The goal: a choice is still required; it grants the keepsake once and charges nothing.
	go(w,ALPHA,"jinguashi",bobo)
	refuse(w,ALPHA,Goals.ACTION,bobo,"bobo:4::","請先選一個做法。","goal without an inscription")
	refuse(w,ALPHA,Goals.ACTION,bobo,"bobo:4:nope:","請先選一個做法。","goal with an unknown inscription")
	var p:=pl(w,ALPHA)
	var coins:=int(p.coins)
	var bag_before:Dictionary=(p.inventory as Dictionary).duplicate(true)
	r=act(w,ALPHA,Goals.ACTION,bobo,"bobo:4:rest:")
	expect(bool(r.get("ok",false)),"alpha completes bobo 4 with an inscription (got '%s')"%msg(r))
	p=pl(w,ALPHA)
	var want_bag:Dictionary=bag_before.duplicate(true)
	want_bag[ITEM]=1
	expect(p.inventory==want_bag and int(p.coins)==coins,"completion adds exactly one keepsake_bobo_cart_kit; no coins, no other item")
	expect(p.get("bond_goals",{}).get("bobo",{})=={"4":"rest"} and p.get("bond_keepsakes")=={KIND:true},"bond_goals bobo 4 'rest' and bond_keepsakes {keepsake_bobo_cart:true}")
	refuse(w,ALPHA,Goals.ACTION,bobo,"bobo:4:home:","〈最後一趟空車〉已經一起完成了，手帳可以重看。","a second completion")
	refuse(w,ALPHA,Goals.CLAIM_ACTION,bobo,"bobo:4","「祖父的礦車」已經領過了。","a claim right after completing")
	refuse_cart(w,ALPHA,bobo,"start",Cart.ALREADY_DONE,"start once the goal is done")
	# BETA started their own story cart after the work delivery (work_cart_unaffected) and is still at stage 1;
	# GAMMA never started one. Alpha's whole run touched neither.
	expect(stage_of(w,BETA)==1 and not pl(w,GAMMA).has(FIELD) and bytes(pl(w,GAMMA))==gamma_bytes,"beta is at their own stage 1 and gamma never had a story cart")
	expect(not Goals.need_met("bobo_cart_arrived",w.state,BETA) and Goals.need_met("bobo_cart_arrived",w.state,ALPHA),"bobo_cart_arrived holds for alpha only")

## BETA runs a whole ordinary delivery while ALPHA is pushing the story cart: unaffected, +PAY coins,
## and a story start is refused (ORE_BUSY) until the delivery is unloaded.
func work_cart_unaffected(w,token:String,stops:Array)->void:
	var coins_before:=int(pl(w,token).coins)
	stand(w,token,stops[0])
	var r:=act(w,token,Ore.ACTION,stops[0],"load")
	expect(bool(r.get("ok",false)) and Ore.stage(w.state,token)==1,"beta's ore_cart load works while alpha pushes the story cart (got '%s')"%msg(r))
	go(w,token,"jinguashi",bobo_cell(w))
	refuse_cart(w,token,bobo_cell(w),"start",Cart.ORE_BUSY,"beta cannot start the story cart with a work cart on the rails")
	for at in range(1,7):
		stand(w,token,stops[at-1])
		r=act(w,token,Ore.ACTION,stops[at-1],"push")
		expect(bool(r.get("ok",false)),"beta's work cart push %d works (got '%s')"%[at,msg(r)])
	stand(w,token,stops[6])
	r=act(w,token,Ore.ACTION,stops[6],"unload")
	expect(bool(r.get("ok",false)) and int(pl(w,token).coins)==coins_before+Ore.PAY,"beta unloads the work cart for the normal %d coins (got '%s')"%[Ore.PAY,msg(r)])
	expect(stage_of(w,token)==0,"beta's story stage is still absent")
	go(w,token,"jinguashi",bobo_cell(w))
	r=start(w,token)
	expect(bool(r.get("ok",false)) and stage_of(w,token)==1,"after the delivery beta starts a story cart of their own (got '%s')"%msg(r))
	expect(stage_of(w,ALPHA)==3,"beta's start and work delivery leave alpha's stage at 3")

# ---------------------------------------------------------------- refusals --

func test_refusals()->void:
	var w:=World.new()
	w.add_player(ALPHA,"甲")
	w.add_player(BETA,"乙")
	var bobo:=bobo_cell(w)
	var stops:Array=Ore.STOPS
	bond(w,ALPHA,int(Bond.THRESHOLDS[3]))
	bond(w,BETA,int(Bond.THRESHOLDS[3]))
	go(w,ALPHA,"jinguashi",bobo)
	# Not started yet: a push is not a start, whatever the cell.
	refuse_cart(w,ALPHA,stops[0],"push",Cart.NOT_PUSHING,"push before starting (at STOPS[0])")
	refuse_cart(w,ALPHA,bobo,"push",Cart.NOT_PUSHING,"push before starting (at bobo)")
	for bad:String in ["","START","start ","begin","start:1","push:start"]:
		refuse_cart(w,ALPHA,bobo,bad,Cart.BAD_EXTRA,"start with extra '%s'"%bad)
	# Start from a cell that is not Bobo's, or from too far away.
	for cell:Vector2i in [bobo+Vector2i.RIGHT,bobo+Vector2i.DOWN,bobo+Vector2i(-1,-1),stops[0],Vector2i(-1,-1),Vector2i(2147483647,2147483647)]:
		refuse_cart(w,ALPHA,cell,"start",Cart.NOT_HERE if cell.x>=0 and cell.x<1000 and cell.y>=0 and cell.y<1000 else "","start aimed at %s"%str(cell))
	var away:=pl(w,ALPHA)
	away["x"]=float(bobo.x)+0.5+6.0
	away["y"]=float(bobo.y)+0.5
	refuse_cart(w,ALPHA,bobo,"start",Cart.TOO_FAR_BOBO,"start six tiles from bobo")
	go(w,ALPHA,"jinguashi",bobo)
	# Wrong regions, for a start and for a push in progress.
	for region:String in ["home","lanyang","maokong"]:
		go(w,ALPHA,region,bobo)
		refuse_cart(w,ALPHA,bobo,"start",Cart.WRONG_REGION,"start from %s"%region)
	go(w,ALPHA,"jinguashi",bobo)
	# Rank 3 and below.
	for points in [0,1,int(Bond.THRESHOLDS[1]),int(Bond.THRESHOLDS[2])]:
		bond(w,BETA,points)
		go(w,BETA,"jinguashi",bobo)
		refuse_cart(w,BETA,bobo,"start",Cart.NEED_BOND,"start with %d bond points"%points)
	var no_bond:=pl(w,BETA)
	no_bond.erase("bonds")
	refuse_cart(w,BETA,bobo,"start",Cart.NEED_BOND,"start with no bond record")
	# Unknown player.
	var r:Dictionary=w.act("nobody-token","cart-nobody",Cart.ACTION,bobo,"start")
	expect(not bool(r.get("ok",true)),"an unknown player cannot start")
	# Start, then leave the region mid-push: the push is refused where the cart is not.
	r=start(w,ALPHA)
	expect(bool(r.get("ok",false)),"control: alpha starts (got '%s')"%msg(r))
	stand(w,ALPHA,stops[0])
	for region:String in ["home","lanyang"]:
		pl(w,ALPHA)["region"]=region
		refuse_cart(w,ALPHA,stops[0],"push",Cart.WRONG_REGION,"push from %s"%region)
	pl(w,ALPHA)["region"]="jinguashi"
	# Tampered record read by a live action: refused, nothing written.
	for bad:Variant in [0,8,-1,2.5,"3",true,[1],{}]:
		var saved:Variant=pl(w,ALPHA).get(FIELD)
		pl(w,ALPHA)[FIELD]=bad
		refuse_cart(w,ALPHA,stops[0],"push",Cart.BAD_RECORD,"push with a tampered record %s"%str(bad))
		refuse_cart(w,ALPHA,bobo,"start",Cart.BAD_RECORD,"start with a tampered record %s"%str(bad))
		pl(w,ALPHA)[FIELD]=saved
	# The story cart does not give the player a free work cart: ore_cart stays where it was refused.
	refuse(w,ALPHA,Ore.ACTION,stops[0],"load",Cart.ORE_BLOCKED,"ore_cart load while pushing")
	refuse(w,ALPHA,Ore.ACTION,stops[0],"push",Cart.ORE_BLOCKED,"ore_cart push while pushing")
	expect(stage_of(w,ALPHA)==1 and not w.state.has("ore_route"),"the refusals left the story stage at 1 and wrote no ore_route record")

# -------------------------------------------------------------- persistence --

func test_persistence()->void:
	var path:=temp_path("world")
	var fixture:=temp_path("fixture")
	var w:=World.new()
	w.save_path=path
	w.add_player(SAVER,"存")
	w.add_player(BETA,"乙")
	bond(w,SAVER,int(Bond.THRESHOLDS[3]))
	var bobo:=bobo_cell(w)
	var stops:Array=Ore.STOPS
	go(w,SAVER,"jinguashi",bobo)
	expect(bool(start(w,SAVER).get("ok",false)),"saver starts")
	for at in range(1,3):
		stand(w,SAVER,stops[at-1])
		expect(bool(push(w,SAVER,stops[at-1]).get("ok",false)),"saver push %d"%at)
	expect(stage_of(w,SAVER)==3 and not pl(w,BETA).has(FIELD),"live: saver at stage 3, beta has no field")
	expect(w.save(),"mid-push world saves")
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(parsed is Dictionary,"mid-push save parses"):return
	var base:Dictionary=parsed
	expect(validates(base),"mid-push save passes SaveSchema")
	expect(not (base.players[BETA] as Dictionary).has(FIELD),"the save carries the field only for the player who has it")
	var restored:=World.new()
	if not expect(restored.load_world(path),"mid-push save reloads"):return
	expect(stage_of(restored,SAVER)==3 and typeof(pl(restored,SAVER)[FIELD])==TYPE_INT,"stage 3 survives the reload as an integer")
	expect(not pl(restored,BETA).has(FIELD),"reload does not invent the field for other players")
	# Unfinished stage persists: the push goes on exactly where it was left.
	stand(restored,SAVER,stops[2])
	refuse_cart(restored,SAVER,stops[1],"push",Cart.WRONG_CELL,"after reload: the previous stop is not the cart's cell")
	for at in range(3,7):
		stand(restored,SAVER,stops[at-1])
		var r:=push(restored,SAVER,stops[at-1])
		expect(bool(r.get("ok",false)),"after reload: push %d (got '%s')"%[at,msg(r)])
	expect(stage_of(restored,SAVER)==7,"after reload the cart still arrives at stage 7")
	expect(Goals.need_met("bobo_cart_arrived",restored.state,SAVER) and not Goals.need_met("bobo_cart_arrived",restored.state,BETA),"bobo_cart_arrived holds for the saver only")
	restored.save_path=path
	expect(restored.save(),"arrived world saves")
	var again:=World.new()
	if not expect(again.load_world(path),"arrived save reloads"):return
	expect(stage_of(again,SAVER)==7,"stage 7 survives a second reload")
	go(again,SAVER,"jinguashi",bobo)
	var done:=act(again,SAVER,Goals.ACTION,bobo,"bobo:4:name:")
	expect(bool(done.get("ok",false)) and int(pl(again,SAVER).inventory.get(ITEM,0))==1,"after reload the goal completes and grants the kit (got '%s')"%msg(done))
	# JSON float normalisation: a 3.0 written by an external tool is accepted and becomes int 3.
	var floaty:Dictionary=base.duplicate(true)
	(floaty.players[SAVER] as Dictionary)[FIELD]=3.0
	expect(validates(floaty) and write_fixture(fixture,floaty),"stage written as 3.0 passes the schema")
	var floaty_world:=World.new()
	expect(floaty_world.load_world(fixture) and stage_of(floaty_world,SAVER)==3 and typeof(pl(floaty_world,SAVER)[FIELD])==TYPE_INT,"stage 3.0 loads as the integer 3")
	# Legal boundary values load.
	for ok_value:int in [1,2,6,7]:
		var good:Dictionary=base.duplicate(true)
		(good.players[SAVER] as Dictionary)[FIELD]=ok_value
		expect(validates(good),"stage %d is accepted"%ok_value)
	# Tampering: each case differs from the control only by its field.
	expect(write_fixture(fixture,base),"write control fixture")
	var control:=World.new()
	expect(control.load_world(fixture) and stage_of(control,SAVER)==3,"control: the untampered fixture loads")
	var probe:=World.new()
	var pristine:=bytes(probe.state)
	var cases:Dictionary={"stage 0":0,"stage 8":8,"stage -1":-1,"stage 2.5":2.5,"stage 7.5":7.5,"stage as text":"3","stage true":true,"stage null":null,"stage list":[3],"stage object":{"v":3},"stage huge":1000000000000}
	for label:String in cases:
		var bad:Dictionary=base.duplicate(true)
		(bad.players[SAVER] as Dictionary)[FIELD]=cases[label]
		expect(not validates(bad),"schema rejects: "+label)
		expect(write_fixture(fixture,bad),"write tampered fixture: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(bytes(probe.state)==pristine,"rejected load leaves the world untouched: "+label)
	# The field needs the fourth bond stage under it.
	for points in [0,int(Bond.THRESHOLDS[2])]:
		var low:Dictionary=base.duplicate(true)
		var low_bonds:Dictionary=(low.players[SAVER] as Dictionary).bonds
		(low_bonds.bobo as Dictionary)["points"]=points
		expect(not validates(low),"schema rejects stage 3 with only %d bond points"%points)
		expect(write_fixture(fixture,low) and not probe.load_world(fixture) and bytes(probe.state)==pristine,"load_world rejects stage 3 with only %d bond points and stays untouched"%points)
	var no_bond:Dictionary=base.duplicate(true)
	((no_bond.players[SAVER] as Dictionary).bonds as Dictionary).erase("bobo")
	expect(not validates(no_bond),"schema rejects a stage with no bobo bond")

# ------------------------------------------------------------ legacy reward --

func test_legacy_reward()->void:
	var path:=temp_path("legacy")
	var w:=World.new()
	w.save_path=path
	w.add_player(OLD,"舊")
	w.add_player(BETA,"乙")
	bond(w,OLD,int(Bond.THRESHOLDS[3]))
	var bobo:=bobo_cell(w)
	# FIXTURE: bobo 4 finished before this wave — bond_goals only, no cart stage, no bond_keepsakes, no kit.
	pl(w,OLD)["bond_goals"]={"bobo":{"4":"home"}}
	expect(Goals.valid(pl(w,OLD).bond_goals,pl(w,OLD)) and not pl(w,OLD).has(FIELD) and not pl(w,OLD).has("bond_keepsakes"),"fixture: old completion without cart, record or kit")
	expect(w.save(),"old-style world saves")
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(parsed is Dictionary and validates(parsed),"an old completion without any cart field passes SaveSchema"):return
	var reloaded:=World.new()
	if not expect(reloaded.load_world(path),"old completion save loads"):return
	expect(not pl(reloaded,OLD).has(FIELD) and not pl(reloaded,OLD).has("bond_keepsakes"),"loading invents neither a cart stage nor a keepsake record")
	var row:Dictionary=Goals.view(pl(reloaded,OLD),reloaded.state,OLD).bobo["4"]
	expect(row=={"state":"done","choice":"home","keepsake":{"kind":KIND,"item":ITEM,"name":"祖父的礦車","claimed":false}},"old done bobo 4 shows done with an unclaimed cart keepsake (%s)"%str(row))
	go(reloaded,OLD,"jinguashi",bobo)
	var coins:=int(pl(reloaded,OLD).coins)
	var bag_before:Dictionary=(pl(reloaded,OLD).inventory as Dictionary).duplicate(true)
	refuse(reloaded,OLD,Goals.CLAIM_ACTION,bobo+Vector2i.RIGHT,"bobo:4","請走到這位居民身邊。","claim aimed at the tile beside bobo")
	refuse(reloaded,OLD,Goals.CLAIM_ACTION,bobo,"bobo:5","這件事的紀念收在手帳裡，沒有可以領的小物。","claim of a stage without a keepsake")
	var r:=act(reloaded,OLD,Goals.CLAIM_ACTION,bobo,"bobo:4")
	expect(bool(r.get("ok",false)),"the old completion claims the cart keepsake without ever pushing a cart (got '%s')"%msg(r))
	var want_bag:Dictionary=bag_before.duplicate(true)
	want_bag[ITEM]=1
	expect(pl(reloaded,OLD).inventory==want_bag and int(pl(reloaded,OLD).coins)==coins,"claim adds exactly one keepsake_bobo_cart_kit; no coins, no other item")
	expect(pl(reloaded,OLD).get("bond_keepsakes")=={KIND:true} and not pl(reloaded,OLD).has(FIELD),"claim writes the keepsake record and no cart stage")
	expect(pl(reloaded,OLD).bond_goals=={"bobo":{"4":"home"}},"claim leaves the old goal record alone")
	refuse(reloaded,OLD,Goals.CLAIM_ACTION,bobo,"bobo:4","「祖父的礦車」已經領過了。","a second claim")
	refuse_cart(reloaded,OLD,bobo,"start",Cart.ALREADY_DONE,"the old completion cannot start a cart")
	refuse_cart(reloaded,OLD,bobo,"push",Cart.NOT_PUSHING,"the old completion has no cart to push")
	expect(not pl(reloaded,BETA).has("bond_keepsakes") and int(pl(reloaded,BETA).inventory.get(ITEM,0))==0,"another player gets nothing from the claim")
	reloaded.save_path=path
	expect(reloaded.save(),"claimed world saves")
	var final:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(final is Dictionary and validates(final),"the claimed save passes SaveSchema")
	var last:=World.new()
	expect(last.load_world(path) and pl(last,OLD).get("bond_keepsakes")=={KIND:true} and int(pl(last,OLD).inventory.get(ITEM,0))==1,"the claim and its kit survive a reload")
	go(last,OLD,"jinguashi",bobo)
	refuse(last,OLD,Goals.CLAIM_ACTION,bobo,"bobo:4","「祖父的礦車」已經領過了。","after reload: the claim stays claimed")

# ----------------------------------------------------------------- snapshot --

func test_snapshot()->void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=World.new()
	var w=session.world
	w.add_player(ALPHA,"甲")
	w.add_player(BETA,"乙")
	bond(w,ALPHA,int(Bond.THRESHOLDS[3]))
	bond(w,BETA,int(Bond.THRESHOLDS[3]))
	var bobo:=bobo_cell(w)
	var stops:Array=Ore.STOPS
	go(w,ALPHA,"jinguashi",bobo)
	go(w,BETA,"jinguashi",bobo)
	session.peers={1:ALPHA,2:BETA}
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.has(OWN) and int(snap[OWN])==0 and typeof(snap[OWN])==TYPE_INT,"in jinguashi without a record the snapshot carries own_bobo_empty_cart = 0")
	expect(bool(start(w,ALPHA).get("ok",false)),"session world: alpha starts")
	for at in range(1,3):
		stand(w,ALPHA,stops[at-1])
		expect(bool(push(w,ALPHA,stops[at-1]).get("ok",false)),"session world: alpha push %d"%at)
	session._send_snapshot(1)
	snap=session.snapshot
	expect(snap.has(OWN) and snap[OWN]==3 and typeof(snap[OWN])==TYPE_INT,"alpha's own snapshot carries only the integer 3")
	expect(Cart.stage(snap)==3 and Cart.active(snap) and Cart.cart_cell(snap)==stops[2] and Cart.label(snap)==Cart.LABEL_PUSH%2,"client accessors read alpha's snapshot (stage 3, STOPS[2], label)")
	var text:=JSON.stringify(snap)
	expect(not text.contains("\"%s\""%FIELD),"alpha's whole snapshot never names the stored field")
	var players:Dictionary=snap.get("players",{})
	var clean:=not players.is_empty()
	for id in players:
		if (players[id] as Dictionary).has(FIELD):clean=false
	expect(clean and not JSON.stringify(players).contains(ALPHA),"snapshot players entries (alpha's own too) carry no cart field and no token")
	expect(pl(w,ALPHA).get(FIELD)==3,"publishing does not strip the live record")
	# Beta, standing in the same place, sees nothing of it.
	session.peers={1:BETA,2:ALPHA}
	session._send_snapshot(1)
	snap=session.snapshot
	expect(snap.has(OWN) and snap[OWN]==0 and Cart.stage(snap)==0 and not Cart.active(snap),"beta's own snapshot says 0 while alpha is at stage 3")
	expect(not JSON.stringify(snap).contains("\"%s\""%FIELD),"beta's whole snapshot never names the stored field")
	var beta_players:Dictionary=snap.get("players",{})
	var beta_clean:=true
	for id in beta_players:
		if (beta_players[id] as Dictionary).has(FIELD):beta_clean=false
	expect(beta_clean,"beta's view of alpha has no cart field")
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		var public_text:=JSON.stringify(public)
		expect(not public_text.contains("\"%s\""%FIELD) and not public_text.contains("\"%s\""%OWN),"public_state(%s) carries no cart stage"%region)
	# Out of jinguashi the key is not sent at all.
	session.peers={1:ALPHA,2:BETA}
	pl(w,ALPHA)["region"]="home"
	session._send_snapshot(1)
	snap=session.snapshot
	expect(not snap.has(OWN) and not JSON.stringify(snap).contains("\"%s\""%FIELD),"at home alpha's snapshot has no own_bobo_empty_cart")
	expect(Cart.stage(snap)==0,"without the key the client reads no cart")
	session.world=null
	session.queue_free()
	await process_frame
