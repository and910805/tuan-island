extends SceneTree
## Focused, standalone test: preloads only pure RefCounted scripts (no World/Session).

const Shy=preload("res://scripts/shy_mushroom.gd")
const Layout=preload("res://scripts/mine_layout.gd")
const Depths=preload("res://scripts/mine_depths.gd")
const Survey=preload("res://scripts/mine_survey.gd")
const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
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
	check_gentle_failures()
	check_record()
	check_atlas()
	print("SHY_MUSHROOM_TESTS checks=%d failures=%d"%[checks,failures])
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
			if seen.has(to) or to in blocked or not Layout.land(to,Shy.DEPTH):continue
			seen[to]=true
			queue.append(to)
	return seen

func check_cells() -> void:
	var cell:=Shy.MUSHROOM
	expect(Shy.REGION=="mine_2" and Depths.depth_of(Shy.REGION)==Shy.DEPTH,"Bound to mine_2, depth 2")
	expect(Shy.DEPTH<Guardian.DEPTH,"Earlier than the B4 guardian room")
	expect(Layout.land(cell,Shy.DEPTH),"Mushroom stands on B2 floor")
	expect(not Layout.BASE_RECT.has_point(cell),"Mushroom is in the side cave, not the main room")
	expect(Layout.side_caves(Shy.DEPTH)[2].has_point(cell),"Mushroom is in the end nook of the B2 cave")
	var occupied:Array=[Depths.ENTRY,Depths.UP,Depths.DOWN,Depths.REST,Depths.SERVICE,Depths.LIFT,Depths.MUD_GATE,Depths.MUD_REWARD,
		Survey.POINTS[Shy.DEPTH]]
	occupied.append_array(Depths.NODES)
	for nearby:Vector2i in occupied:
		expect(nearby!=cell,"Mushroom does not sit on %s"%nearby)
	expect(not Depths.POOL.has_point(cell),"Mushroom is outside the water pool")
	expect(not (cell in Guardian.BELLS) and cell!=Guardian.GUARDIAN,"Mushroom does not reuse guardian cells")
	var point:Vector2i=Survey.POINTS[Shy.DEPTH]
	expect(centre(point).distance_to(centre(cell))>=2.5,"Survey point keeps a visible gap from the mushroom")
	expect(not Shy.near(centre(point)),"Standing on the survey point does not reach the mushroom, so no input crowding")
	# The mushroom is optional: with its cell solid, the cave mouth, survey point and a stand cell stay connected.
	var open:=reachable(Vector2i(40,21),[cell])
	expect(open.has(point),"Survey point reachable with the mushroom cell solid")
	var stand:=0
	for c:Vector2i in open:
		if Shy.near(centre(c)) and c!=cell:stand+=1
	expect(stand>=3,"At least three walkable cells within reach of the mushroom (found %d)"%stand)
	var base:=reachable(Vector2i(40,21),[])
	expect(base.size()-open.size()==1,"Blocking the mushroom cell removes only that cell from the cave")
	expect(not Shy.available("mine_7",15) and not Shy.available("mine_13",15),"B7/B13 reuse the cave shape but stay excluded")
	expect(not Shy.available("mine_1",1) and not Shy.available(Shy.REGION,1) and Shy.available(Shy.REGION,2),"Appears only once B2 is unlocked")
	expect(Shy.ACTIONS==["shy_wait","shy_claim"] and Shy.WATER_ACTION=="water","Documented action names")

func check_flow() -> void:
	var stand:=centre(Shy.MUSHROOM)+Vector2(-1.0,0.0)
	var record:=Shy.fresh()
	var started:=Shy.wait(record,{},stand,100.0)
	expect(started.ok and started.outcome=="start" and started.remaining==Shy.WAIT_SECONDS,"First interact starts the wait")
	expect(Shy.CUE_RUSTLE in started.cues,"Wait start gives a rustle sound cue")
	expect(Shy.progress(started.watch,100.0)==0.0 and is_equal_approx(Shy.progress(started.watch,102.0),0.5),"Stillness ring fills linearly")
	var early:=Shy.wait(record,started.watch,stand,101.0)
	expect(early.ok and early.outcome=="waiting" and is_equal_approx(early.remaining,3.0) and early.record==record,"Too early only reports time left")
	var tiny:=Shy.wait(record,started.watch,stand+Vector2(0.5,0.0),102.0)
	expect(tiny.outcome=="waiting","Small drift within tolerance keeps the wait")
	var wandered:=Shy.wait(record,started.watch,stand+Vector2(0.0,-1.4),103.0)
	expect(wandered.ok and wandered.outcome=="start" and wandered.record==record,"Walking off just restarts, no penalty")
	var peek:=Shy.wait(record,started.watch,stand,104.0)
	expect(peek.ok and peek.outcome=="peek" and int(peek.record.stage)==1 and peek.watch.is_empty(),"After the wait it peeks out")
	expect(Shy.CUE_PEEK in peek.cues,"Peek has its own sound cue")
	expect(Shy.watch_hold(started.watch,stand+Vector2(0.4,0.0))==started.watch,"Tick keeps the anchor while still")
	expect(Shy.watch_hold(started.watch,stand+Vector2(2.0,0.0)).is_empty(),"Tick clears the anchor after walking off")
	expect(Shy.wait(record,started.watch,stand,50.0).outcome=="start","A rewound clock restarts instead of passing")
	var again:=Shy.wait(peek.record,{},stand,105.0)
	expect(again.ok and again.outcome=="peeking" and again.record==peek.record,"Interacting again while peeking changes nothing")
	var water:=Shy.water(peek.record,stand)
	expect(water.ok and water.consume_water and int(water.record.stage)==2 and water.outcome=="water","Watering a peeking mushroom opens it")
	expect(Shy.CUE_SPLASH in water.cues and Shy.CUE_OPEN in water.cues,"Watering gives splash and open cues")
	expect(Shy.frame(water.record,true)==Shy.FRAME_WATER and Shy.frame(water.record)==Shy.FRAME_OPEN,"Water-response frame then open frame")
	var gift:=Shy.claim(water.record,stand)
	expect(gift.ok and gift.reward=={"item":"fiber","count":4} and gift.record.claimed,"Claim returns the limited reward")
	expect(not Shy.claim(gift.record,stand).ok and Shy.claim(gift.record,stand).outcome=="claimed","Reward is one-time")
	expect(not Shy.water(gift.record,stand).ok and not Shy.water(gift.record,stand).consume_water,"No water spent on an open mushroom")
	expect(Shy.wait(record,started.watch,stand,104.0)==Shy.wait(record,started.watch,stand,104.0),"Same input gives identical output (replay safe)")
	expect(record==Shy.fresh() and started.watch.has("since"),"Inputs were not mutated")

func check_gentle_failures() -> void:
	var stand:=centre(Shy.MUSHROOM)+Vector2(-1.0,0.0)
	var far:=Vector2(10,10)
	var record:=Shy.fresh()
	var early:=Shy.water(record,stand)
	expect(not early.ok and early.outcome=="too_early" and not early.consume_water and early.record==record,"Early water: hint only, nothing spent or lost")
	expect(Shy.water(record,far).outcome=="far" and Shy.wait(record,{},far,0.0).outcome=="far" and Shy.claim(record,far).outcome=="far","Distance is checked by the module itself")
	expect(Shy.claim(record,stand).outcome=="hidden" and not Shy.claim(record,stand).ok,"Cannot claim before it opens")
	expect(Shy.wait({"stage":2,"claimed":false},{},stand,0.0).outcome=="open","Waiting at an open mushroom is a no-op")
	for result:Dictionary in [early,Shy.wait(record,{},stand,0.0),Shy.claim(record,stand)]:
		for forbidden:String in ["hp","damage","timer","deadline","fail_count","penalty"]:
			expect(not result.has(forbidden) and not result.record.has(forbidden),"No %s field"%forbidden)
	for message:String in [early.message,Shy.wait(record,{},stand,0.0).message]:
		expect(message!="" and not "失敗" in message,"Messages stay gentle")

func check_record() -> void:
	expect(Shy.valid(Shy.fresh()) and Shy.valid({"stage":2,"claimed":true}) and Shy.valid({"stage":1.0,"claimed":false}),"Valid records")
	for bad in [null,{},{"stage":0},{"stage":3,"claimed":false},{"stage":-1,"claimed":false},{"stage":0.5,"claimed":false},
			{"stage":INF,"claimed":false},{"stage":NAN,"claimed":false},{"stage":"1","claimed":false},{"stage":0,"claimed":1},
			{"stage":1,"claimed":true},{"stage":0,"claimed":false,"extra":1},[0,false]]:
		expect(not Shy.valid(bad),"Rejects %s"%str(bad))
	var parsed=JSON.parse_string(JSON.stringify(Shy.fresh()))
	expect(Shy.valid(parsed),"Survives a JSON round trip")

func check_atlas() -> void:
	expect(Shy.ATLAS_PATH=="res://assets/mine/shy-mushroom.png" and Shy.ATLAS_SIZE==Vector2i(64,80),"Atlas constants match the art brief")
	var image:=Image.load_from_file(ProjectSettings.globalize_path(Shy.ATLAS_PATH))
	expect(image!=null and image.get_size()==Shy.ATLAS_SIZE,"Atlas file is 64x80")
	expect(Shy.frame_rect(0)==Rect2i(0,0,32,40) and Shy.frame_rect(1)==Rect2i(32,0,32,40) and Shy.frame_rect(2)==Rect2i(0,40,32,40) and Shy.frame_rect(3)==Rect2i(32,40,32,40),"Row-major frames")
	expect(Shy.FOOT==Vector2i(16,38),"Foot point (16,38)")
	if image==null:return
	for index in 4:
		var rect:=Shy.frame_rect(index)
		var cell:=image.get_region(rect)
		var solid:=0
		var lowest:=-1
		for y in rect.size.y:
			for x in rect.size.x:
				if cell.get_pixel(x,y).a>0.5:
					solid+=1
					lowest=maxi(lowest,y)
		expect(solid>150,"Frame %d has a figure (%d opaque px)"%[index,solid])
		expect(lowest>=Shy.FOOT.y-4 and lowest<=Shy.FOOT.y+1,"Frame %d stands near the foot line (lowest opaque row %d)"%[index,lowest])
	var differing:=0
	for a in 4:
		for b in range(a+1,4):
			if image.get_region(Shy.frame_rect(a)).get_data()!=image.get_region(Shy.frame_rect(b)).get_data():differing+=1
	expect(differing==6,"All four frames are distinct")
