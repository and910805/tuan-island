extends SceneTree
## Focused, standalone test: preloads only pure RefCounted scripts (no World/Session).

const Crab=preload("res://scripts/stone_shelled_crab.gd")
const Layout=preload("res://scripts/mine_layout.gd")
const Depths=preload("res://scripts/mine_depths.gd")
const Survey=preload("res://scripts/mine_survey.gd")
const Freight=preload("res://scripts/mine_freight.gd")
const AutoFreight=preload("res://scripts/mine_auto_freight.gd")
const Drill=preload("res://scripts/mine_drill.gd")
const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
const Shy=preload("res://scripts/shy_mushroom.gd")
const CAVE_MOUTH:=Vector2i(40,24)
var checks:=0
var failures:=0

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _initialize() -> void:
	check_cells()
	check_flow()
	check_materials()
	check_gentle_failures()
	check_record()
	check_atlas()
	print("STONE_SHELLED_CRAB_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func centre(cell:Vector2i) -> Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

func reachable(from:Vector2i,blocked:Array) -> Dictionary:
	var seen:={from:true}
	var queue:=[from]
	while not queue.is_empty():
		var at:Vector2i=queue.pop_back()
		for step:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var to:=at+step
			if seen.has(to) or to in blocked or not Layout.land(to,Crab.DEPTH):continue
			seen[to]=true
			queue.append(to)
	return seen

func check_cells() -> void:
	var cells:Array=Crab.footprint()
	expect(cells==[Crab.CART,Crab.CRAB,Crab.CRAB_REST] and cells.size()==3,"Footprint lists cart, crab and rest cells")
	expect(Crab.CART!=Crab.CRAB and Crab.CART!=Crab.CRAB_REST and Crab.CRAB!=Crab.CRAB_REST,"Three distinct cells")
	expect(Crab.REGION=="mine_5" and Depths.depth_of(Crab.REGION)==Crab.DEPTH,"Bound to mine_5, depth 5")
	expect(Crab.DEPTH==Depths.SHALLOW_DEPTH,"B5 is the last shallow floor")
	expect(Crab.REGION in AutoFreight.REGIONS and Crab.REGION in Drill.REGIONS,"B5 shares the rail/freight story floor")
	expect(Crab.REGION!=Shy.REGION and Crab.REGION!=Guardian.REGION and Crab.REGION!=Depths.MUD_REGION,"Different floor from the mushroom, guardian and mud encounters")
	var inner:Rect2i=Layout.side_caves(Crab.DEPTH)[2]
	var nook:Rect2i=Layout.side_caves(Crab.DEPTH)[3]
	expect(inner==Rect2i(45,22,3,5) and nook==Rect2i(46,27,2,2),"B5 east cave spans are the documented ones")
	var occupied:Array=[Depths.ENTRY,Depths.UP,Depths.DOWN,Depths.REST,Depths.SERVICE,Depths.LIFT,Depths.MUD_GATE,Depths.MUD_REWARD,
		Vector2i(12,20),Survey.POINTS[Crab.DEPTH],Freight.LOAD_CELL,Drill.NODE,Shy.MUSHROOM,Guardian.GUARDIAN]
	occupied.append_array(Depths.NODES)
	occupied.append_array(Guardian.BELLS)
	for direction:Vector2i in Drill.DIRECTIONS:
		occupied.append(Drill.NODE-direction)
	var point:Vector2i=Survey.POINTS[Crab.DEPTH]
	for cell:Vector2i in cells:
		expect(Layout.land(cell,Crab.DEPTH),"%s is B5 floor"%cell)
		expect(not Layout.BASE_RECT.has_point(cell),"%s is in the side cave, not the main room"%cell)
		expect(inner.has_point(cell) and cell.y==inner.position.y,"%s is on the back-wall row of the inner span"%cell)
		expect(not Layout.land(cell+Vector2i.UP,Crab.DEPTH),"%s has rock behind it"%cell)
		expect(not Depths.POOL.has_point(cell),"%s is outside the pool rectangle"%cell)
		expect(not (cell in occupied),"%s is not an existing ladder/rest/service/node/drill/survey/encounter cell"%cell)
		expect(centre(point).distance_to(centre(cell))>=2.0,"%s keeps a visible gap from the survey point"%cell)
		expect(not Crab.near(centre(point),cell),"Standing on the survey point does not reach %s"%cell)
		expect(centre(Depths.SERVICE).distance_to(centre(cell))>=8.0,"%s is far from the mainline freight cart"%cell)
	expect(absi(Crab.CART.x-Crab.CRAB.x)==2 and Crab.CART.y==Crab.CRAB.y,"Crab waits two cells beside the cart")
	expect(Crab.CRAB_REST.x==Crab.CART.x+1 and Crab.CRAB_REST.y==Crab.CART.y,"Crab settles right next to the mended cart")
	expect(absi(Crab.CRAB.x-Crab.CRAB_REST.x)==1 and Crab.CRAB.y==Crab.CRAB_REST.y,"The move is a one-cell sidestep")
	# Optional encounter: even with the cart and the crab solid, everything else stays connected.
	var base:=reachable(CAVE_MOUTH,[])
	expect(base.has(point) and base.has(Depths.UP) and base.has(Depths.DOWN) and base.has(Depths.SERVICE),"B5 is connected from the cave mouth")
	for crab_at:Vector2i in [Crab.CRAB,Crab.CRAB_REST]:
		var open:=reachable(CAVE_MOUTH,[Crab.CART,crab_at])
		expect(base.size()-open.size()==2,"Blocking cart+%s removes only those two cells"%crab_at)
		expect(open.has(point),"Survey point reachable with cart+%s solid"%crab_at)
		for y in range(nook.position.y,nook.end.y):
			for x in range(nook.position.x,nook.end.x):
				expect(open.has(Vector2i(x,y)),"Nook cell (%d,%d) reachable with cart+%s solid"%[x,y,crab_at])
		var by_cart:=0
		var by_crab:=0
		for c:Vector2i in open:
			if Crab.near(centre(c),Crab.CART):by_cart+=1
			if Crab.near(centre(c),crab_at):by_crab+=1
		expect(by_cart>=3 and by_crab>=3,"At least three stand cells by the cart (%d) and the crab at %s (%d)"%[by_cart,crab_at,by_crab])
	var worst:=reachable(CAVE_MOUTH,cells)
	expect(base.size()-worst.size()==3,"Even all three cells solid cut off nothing else")
	expect(Layout.side_caves(10)==Layout.side_caves(5) and Layout.side_caves(15)==Layout.side_caves(5),"B10/B15 reuse the cave shape")
	expect(not Crab.available("mine_10",15) and not Crab.available("mine_15",15),"B10/B15 stay excluded")
	expect(not Crab.available("mine_4",5) and not Crab.available(Crab.REGION,4) and Crab.available(Crab.REGION,5) and Crab.available(Crab.REGION,15),"Appears only on B5 once B5 is unlocked")
	expect(Crab.ACTIONS==["crab_survey","crab_repair","crab_claim"] and Crab.ACTIONS==[Crab.SURVEY_ACTION,Crab.REPAIR_ACTION,Crab.CLAIM_ACTION],"Documented action names")
	for action:String in Crab.ACTIONS:
		expect(not (action in Survey.ACTIONS) and not (action in Freight.ACTIONS) and not (action in AutoFreight.ACTIONS)
			and not (action in Drill.ACTIONS) and not (action in Guardian.ACTIONS) and not (action in Shy.ACTIONS) and action!=Shy.WATER_ACTION,
			"Action %s does not clash with existing mine actions"%action)

func bag() -> Dictionary:
	return {"plank":5,"copper_joint":3,"stone":9}

func check_flow() -> void:
	var by_crab:=centre(Crab.CRAB)+Vector2(0.0,1.0)
	var by_cart:=centre(Crab.CART)+Vector2(0.0,1.0)
	var between:=centre(Vector2i(46,23))
	expect(Layout.land(Vector2i(46,23),Crab.DEPTH) and Layout.land(Crab.CRAB+Vector2i.DOWN,Crab.DEPTH) and Layout.land(Crab.CART+Vector2i.DOWN,Crab.DEPTH),"Stand cells used by the flow are real floor")
	expect(Crab.near(between,Crab.CART) and Crab.near(between,Crab.CRAB) and Crab.near(between,Crab.CRAB_REST),"One stand cell reaches cart and crab")
	var record:=Crab.fresh()
	expect(Crab.crab_cell(record)==Crab.CRAB and Crab.frame(record)==Crab.FRAME_TUCKED and Crab.cart_frame(record)==Crab.CART_BROKEN,"Starts tucked beside a broken cart")
	var look:=Crab.survey(record,by_crab)
	expect(look.ok and look.outcome=="look" and int(look.record.stage)==1 and Crab.CUE_CLACK in look.cues,"Looking makes it alert, with a clack cue")
	expect(look.consume.is_empty() and look.missing.is_empty() and not look.has("reward"),"Looking is free")
	expect(Crab.frame(look.record)==Crab.FRAME_ALERT and Crab.cart_frame(look.record)==Crab.CART_BROKEN and Crab.crab_cell(look.record)==Crab.CRAB,"Alert frame, cart still broken, crab has not moved")
	var again:=Crab.survey(look.record,by_crab)
	expect(again.ok and again.outcome=="alert" and again.record==look.record,"Looking again only repeats the hint")
	var inventory:=bag()
	var fix:=Crab.repair(look.record,by_cart,inventory)
	expect(fix.ok and fix.outcome=="repair" and int(fix.record.stage)==2 and not fix.record.claimed,"Repair settles the crab")
	expect(fix.consume=={"plank":2,"copper_joint":1} and fix.consume==Crab.REPAIR_COST and fix.missing.is_empty(),"Repair reports exactly the cost to spend")
	expect(inventory==bag(),"The module never touches the inventory itself")
	expect(Crab.CUE_HAMMER in fix.cues and Crab.CUE_WHEEL in fix.cues and Crab.CUE_SCUTTLE in fix.cues,"Repair gives hammer, wheel and scuttle cues")
	for cue:String in look.cues+fix.cues:
		expect(cue in Crab.CUES,"Cue %s is declared"%cue)
	expect(Crab.frame(fix.record,true)==Crab.FRAME_SIDESTEP and Crab.frame(fix.record)==Crab.FRAME_RELAXED,"Sidestep frame, then relaxed frame")
	expect(Crab.cart_frame(fix.record)==Crab.CART_MENDED and Crab.crab_cell(fix.record)==Crab.CRAB_REST and Crab.settled(fix.record),"Cart mended and crab moved beside it")
	var twice:=Crab.repair(fix.record,by_cart,inventory)
	expect(not twice.ok and twice.outcome=="settled" and twice.consume.is_empty() and twice.record==fix.record,"A second repair spends nothing")
	var calm:=Crab.survey(fix.record,between)
	expect(calm.ok and calm.outcome=="settled" and calm.record==fix.record,"Looking at the settled crab changes nothing")
	var gift:=Crab.claim(fix.record,between)
	expect(gift.ok and gift.outcome=="claim" and gift.reward=={"item":"gold_ore","count":2} and gift.record=={"stage":2,"claimed":true},"Claim returns the limited reward")
	expect(gift.consume.is_empty() and Crab.CUE_CHIME in gift.cues,"Claim costs nothing and chimes")
	var repeat:=Crab.claim(gift.record,between)
	expect(not repeat.ok and repeat.outcome=="claimed" and not repeat.has("reward") and repeat.record==gift.record,"Reward is one-time")
	var total:=0
	var walk:=Crab.fresh()
	for step in 6:
		var res:Dictionary
		match step%3:
			0:res=Crab.survey(walk,between)
			1:res=Crab.repair(walk,between,bag())
			_:res=Crab.claim(walk,between)
		if res.has("reward"):total+=int(res.reward.count)
		if res.ok:walk=res.record
	expect(total==Crab.REWARD_COUNT and walk=={"stage":2,"claimed":true},"Running the whole ladder twice pays once")
	expect(not Crab.repair(gift.record,by_cart,bag()).ok and Crab.repair(gift.record,by_cart,bag()).consume.is_empty(),"Nothing can be spent after the claim")
	expect(Crab.repair(look.record,by_cart,bag())==Crab.repair(look.record,by_cart,bag()) and Crab.claim(fix.record,between)==gift,"Same input gives identical output (replay safe)")
	expect(record==Crab.fresh() and look.record=={"stage":1,"claimed":false} and fix.record=={"stage":2,"claimed":false},"Inputs were not mutated")
	expect(Crab.valid(look.record) and Crab.valid(fix.record) and Crab.valid(gift.record),"Every step yields a valid record")

func check_materials() -> void:
	var by_cart:=centre(Crab.CART)+Vector2(-1.0,0.0)
	var alert:={"stage":1,"claimed":false}
	expect(Crab.REPAIR_COST=={"plank":2,"copper_joint":1},"Documented repair cost")
	var unlock:Dictionary=Depths.COSTS[Crab.DEPTH-2]
	for item:String in Crab.REPAIR_COST:
		expect(unlock.has(item) and int(unlock[item])>=int(Crab.REPAIR_COST[item]),"%s is already needed (in a larger amount) to open B5"%item)
	expect(Crab.missing(bag()).is_empty() and Crab.missing({"plank":2,"copper_joint":1}).is_empty(),"Enough materials")
	expect(Crab.missing({})=={"plank":2,"copper_joint":1} and Crab.missing({"plank":1,"copper_joint":4})=={"plank":1},"Shortfall is itemised")
	expect(Crab.missing({"plank":"9","copper_joint":NAN})=={"plank":2,"copper_joint":1} and Crab.missing({"plank":-3,"copper_joint":1})=={"plank":2},"Odd counts are treated as nothing held")
	for short:Dictionary in [{},{"plank":2},{"copper_joint":1},{"plank":1,"copper_joint":1},{"plank":2,"copper_joint":0},{"wood":99,"copper_ore":99}]:
		var before:=short.duplicate(true)
		var res:=Crab.repair(alert,by_cart,short)
		expect(not res.ok and res.outcome=="short" and res.record==alert,"Shortfall %s refuses and keeps the stage"%str(short))
		expect(res.consume.is_empty() and not res.missing.is_empty() and short==before,"Shortfall %s consumes nothing"%str(short))
		expect(res.cues.is_empty() and not res.has("reward") and "木板" in res.message and "銅接頭" in res.message,"Shortfall %s names what is needed"%str(short))
	var exact:=Crab.repair(alert,by_cart,{"plank":2,"copper_joint":1})
	expect(exact.ok and exact.consume==Crab.REPAIR_COST,"Exact materials are enough")
	exact.consume["plank"]=99
	expect(Crab.REPAIR_COST=={"plank":2,"copper_joint":1},"Returned cost is a copy")
	# Simulated host: commit only when consume is non-empty; a retry after topping up succeeds once.
	var held:={"plank":1,"copper_joint":1}
	var record:=alert.duplicate()
	for attempt in 4:
		if attempt==2:held.plank+=3
		var res:=Crab.repair(record,by_cart,held)
		for item:String in res.consume:held[item]-=int(res.consume[item])
		if res.ok:record=res.record
	expect(held=={"plank":2,"copper_joint":0} and record=={"stage":2,"claimed":false},"Host loop spends the cost exactly once")

func check_gentle_failures() -> void:
	var by_cart:=centre(Crab.CART)+Vector2(0.0,1.0)
	var by_crab:=centre(Crab.CRAB)+Vector2(0.0,1.0)
	var far:=Vector2(10,10)
	var record:=Crab.fresh()
	var early:=Crab.repair(record,by_cart,bag())
	expect(not early.ok and early.outcome=="too_early" and early.consume.is_empty() and early.record==record,"Repair before looking: hint only, nothing spent")
	expect(Crab.survey(record,far).outcome=="far" and Crab.repair(record,far,bag()).outcome=="far" and Crab.claim(record,far).outcome=="far","Distance is checked by the module itself")
	expect(Crab.repair({"stage":1,"claimed":false},far,bag()).consume.is_empty(),"Too far spends nothing")
	expect(Crab.claim(record,by_crab).outcome=="waiting" and Crab.claim({"stage":1,"claimed":false},by_crab).outcome=="waiting","Cannot claim before the repair")
	var moved:={"stage":2,"claimed":false}
	var old_side:=centre(Crab.CRAB)+Vector2(0.0,1.6)
	expect(Crab.near(old_side,Crab.CRAB) and not Crab.near(old_side,Crab.CRAB_REST),"Fixture stands by the old spot only")
	expect(Crab.claim(moved,old_side).outcome=="far" and Crab.survey(moved,old_side).outcome=="far","After the sidestep the crab is reached at its new cell")
	for result:Dictionary in [early,Crab.survey(record,by_crab),Crab.claim(record,by_crab),Crab.repair({"stage":1,"claimed":false},by_cart,{})]:
		expect(result.keys()==["ok","message","record","outcome","cues","consume","missing"],"Result shape is stable")
		for forbidden:String in ["hp","damage","timer","deadline","fail_count","penalty","remaining"]:
			expect(not result.has(forbidden) and not result.record.has(forbidden),"No %s field"%forbidden)
		expect(result.message!="" and not "失敗" in result.message,"Messages stay gentle")

func check_record() -> void:
	expect(Crab.valid(Crab.fresh()) and Crab.valid({"stage":2,"claimed":true}) and Crab.valid({"stage":1.0,"claimed":false}) and Crab.valid({"stage":2,"claimed":false}),"Valid records")
	for bad in [null,{},{"stage":0},{"claimed":false},{"stage":3,"claimed":false},{"stage":-1,"claimed":false},{"stage":0.5,"claimed":false},
			{"stage":INF,"claimed":false},{"stage":NAN,"claimed":false},{"stage":"1","claimed":false},{"stage":true,"claimed":false},
			{"stage":0,"claimed":1},{"stage":0,"claimed":"false"},{"stage":0,"claimed":true},{"stage":1,"claimed":true},
			{"stage":0,"claimed":false,"extra":1},{"stage":2,"repaired":true},[0,false],"stage",7]:
		expect(not Crab.valid(bad),"Rejects %s"%str(bad))
	var parsed=JSON.parse_string(JSON.stringify({"stage":2,"claimed":true}))
	expect(Crab.valid(parsed) and Crab.settled(parsed) and Crab.crab_cell(parsed)==Crab.CRAB_REST,"Survives a JSON round trip (float stage)")
	expect(Crab.valid(JSON.parse_string(JSON.stringify(Crab.fresh()))),"Fresh record survives a JSON round trip")
	expect(Crab.fresh().keys()==Shy.fresh().keys(),"Same record shape as the shy mushroom")
	var gift:=Crab.claim({"stage":2,"claimed":false},centre(Crab.CRAB_REST)+Vector2(0.0,1.0))
	var shy_gift:=Shy.claim({"stage":2,"claimed":false},centre(Shy.MUSHROOM)+Vector2(-1.0,0.0))
	var guardian_gift:=Guardian.claim({"round":2,"calm":0,"claimed":false})
	expect(gift.reward.keys()==shy_gift.reward.keys() and gift.reward.keys()==guardian_gift.reward.keys(),"Same reward shape as the mushroom and the guardian")
	expect(Crab.REWARD_ITEM in Freight.ITEMS and Crab.REWARD_COUNT==Depths.YIELDS[Crab.DEPTH-1] and Depths.ORES[Crab.DEPTH-1]==Crab.REWARD_ITEM,"Reward is one ordinary B5 strike of the floor's own ore")

func opaque(image:Image,rect:Rect2i) -> Dictionary:
	var cell:=image.get_region(rect)
	var solid:=0
	var lowest:=-1
	for y in rect.size.y:
		for x in rect.size.x:
			if cell.get_pixel(x,y).a>0.5:
				solid+=1
				lowest=maxi(lowest,y)
	return {"solid":solid,"lowest":lowest}

func check_atlas() -> void:
	expect(Crab.ATLAS_PATH=="res://assets/mine/stone-shelled-crab.png" and Crab.ATLAS_SIZE==Vector2i(64,80),"Crab atlas constants match the art brief")
	expect(Crab.CART_ATLAS_PATH=="res://assets/mine/stone-crab-cart.png" and Crab.CART_ATLAS_SIZE==Vector2i(96,40),"Cart atlas constants match the art brief")
	expect(Crab.frame_rect(0)==Rect2i(0,0,32,40) and Crab.frame_rect(1)==Rect2i(32,0,32,40) and Crab.frame_rect(2)==Rect2i(0,40,32,40) and Crab.frame_rect(3)==Rect2i(32,40,32,40),"Row-major crab frames")
	expect(Crab.cart_rect(Crab.CART_BROKEN)==Rect2i(0,0,48,40) and Crab.cart_rect(Crab.CART_MENDED)==Rect2i(48,0,48,40),"Cart frames: broken left, mended right")
	expect(Crab.FOOT==Vector2i(16,38) and Crab.CART_FOOT==Vector2i(24,38),"Foot points (16,38) and (24,38)")
	expect([Crab.FRAME_TUCKED,Crab.FRAME_ALERT,Crab.FRAME_SIDESTEP,Crab.FRAME_RELAXED]==[0,1,2,3],"Frame order tucked/alert/sidestep/relaxed")
	var image:=Image.load_from_file(ProjectSettings.globalize_path(Crab.ATLAS_PATH))
	expect(image!=null and image.get_size()==Crab.ATLAS_SIZE,"Crab atlas file is 64x80")
	if image!=null and image.get_size()==Crab.ATLAS_SIZE:
		for index in 4:
			var info:=opaque(image,Crab.frame_rect(index))
			expect(int(info.solid)>150,"Crab frame %d has a figure (%d opaque px)"%[index,info.solid])
			expect(int(info.lowest)>=Crab.FOOT.y-4 and int(info.lowest)<=Crab.FOOT.y+1,"Crab frame %d stands near the foot line (lowest opaque row %d)"%[index,info.lowest])
		var differing:=0
		for a in 4:
			for b in range(a+1,4):
				if image.get_region(Crab.frame_rect(a)).get_data()!=image.get_region(Crab.frame_rect(b)).get_data():differing+=1
		expect(differing==6,"All four crab frames are distinct")
	var cart:=Image.load_from_file(ProjectSettings.globalize_path(Crab.CART_ATLAS_PATH))
	expect(cart!=null and cart.get_size()==Crab.CART_ATLAS_SIZE,"Cart atlas file is 96x40")
	if cart!=null and cart.get_size()==Crab.CART_ATLAS_SIZE:
		for index in 2:
			var info:=opaque(cart,Crab.cart_rect(index))
			expect(int(info.solid)>300,"Cart frame %d has a cart (%d opaque px)"%[index,info.solid])
			expect(int(info.lowest)>=Crab.CART_FOOT.y-4 and int(info.lowest)<=Crab.CART_FOOT.y+1,"Cart frame %d stands near the foot line (lowest opaque row %d)"%[index,info.lowest])
		expect(cart.get_region(Crab.cart_rect(0)).get_data()!=cart.get_region(Crab.cart_rect(1)).get_data(),"Broken and mended cart frames differ")
