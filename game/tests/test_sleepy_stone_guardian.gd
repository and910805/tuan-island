extends SceneTree
## Focused, standalone test: preloads only pure RefCounted scripts (no World/Session).

const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
const Layout=preload("res://scripts/mine_layout.gd")
const Depths=preload("res://scripts/mine_depths.gd")
const Survey=preload("res://scripts/mine_survey.gd")
var checks:=0
var failures:=0

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _initialize() -> void:
	check_cells()
	check_phrases()
	check_puzzle()
	check_fallback_and_claim()
	check_record()
	check_atlas()
	print("SLEEPY_STONE_GUARDIAN_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func play(token:String,record:Dictionary) -> Dictionary:
	# Solve with the real hum, one bell at a time, exactly as the host would.
	var state:=record
	var typed:Array=[]
	for bell:int in Guardian.phrase(token,int(state.round)):
		var step:=Guardian.ring(token,state,typed,bell)
		expect(step.ok,"A correct bell is accepted")
		state=step.record
		typed=step.entered
	return state

func check_cells() -> void:
	var cells:Array=Guardian.BELLS.duplicate()
	cells.append(Guardian.GUARDIAN)
	for cell:Vector2i in cells:
		expect(Layout.land(cell,Guardian.DEPTH),"Cell %s is mine floor on B4"%cell)
		expect(Layout.bounds(Guardian.DEPTH).has_point(cell) and not Layout.BASE_RECT.has_point(cell),"Cell %s is inside the north side cave, off the main chamber"%cell)
	for cell:Vector2i in cells:
		expect(cells.count(cell)==1,"Guardian and bells use distinct cells")
		for other:Vector2i in [Survey.POINTS[Guardian.DEPTH],Depths.ENTRY,Depths.UP,Depths.DOWN,Depths.REST,Depths.SERVICE,Depths.LIFT]+Depths.NODES:
			expect(cell!=other,"Cell %s does not overlap existing mine content %s"%[cell,other])
		expect(not Depths.POOL.has_point(cell),"Cell is outside the pump pool")
	expect(Survey.POINTS[Guardian.DEPTH]==Vector2i(34,12),"Survey point is where the design assumed")
	# The cave stays walkable: survey point and every bell are reachable from the cave mouth.
	var reach:=flood(Vector2i(34,15))
	for cell:Vector2i in cells+[Survey.POINTS[Guardian.DEPTH]]:
		expect(reach.has(cell),"Cell %s is reachable from the cave mouth"%cell)
	# Guardian is non-blocking by design: its neighbours stay connected without its own cell.
	var around:=flood(Vector2i(34,15),Guardian.GUARDIAN)
	for cell:Vector2i in Guardian.BELLS+[Survey.POINTS[Guardian.DEPTH]]:
		expect(around.has(cell),"Survey and bells stay reachable even if the statue cell were solid")
	expect(Guardian.available("mine_4",4) and not Guardian.available("mine_4",3) and not Guardian.available("mine_8",8),"Only B4 once it is open")
	expect(Guardian.bell_at(Guardian.BELLS[2])==2 and Guardian.bell_at(Guardian.GUARDIAN)==-1,"Bell lookup by cell")
	expect(Guardian.near(Vector2(34.5,11.5),Guardian.GUARDIAN) and not Guardian.near(Vector2(34.5,13.9),Guardian.GUARDIAN),"Reach check")

func flood(start:Vector2i,blocked:=Vector2i(-99,-99)) -> Dictionary:
	var seen:={start:true}
	var queue:=[start]
	while not queue.is_empty():
		var at:Vector2i=queue.pop_back()
		for step in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var to:Vector2i=at+step
			if to!=blocked and not seen.has(to) and Layout.land(to,Guardian.DEPTH):
				seen[to]=true
				queue.append(to)
	return seen

func check_phrases() -> void:
	for token in ["a","小明","player-2","peer-token-xyz","","測試"]:
		for stage in range(Guardian.ROUNDS):
			var p:=Guardian.phrase(token,stage)
			expect(p.size()==stage+2,"Phrase %d has %d notes"%[stage,stage+2])
			expect(p==Guardian.phrase(token,stage),"Phrase is deterministic")
			for i in p.size():
				expect(int(p[i])>=0 and int(p[i])<3,"Note is a valid bell")
				if i>0:expect(p[i]!=p[i-1],"No immediate repeat")
	var variety:={}
	for i in 30:variety[str(Guardian.phrase("p%d"%i,1))]=true
	expect(variety.size()>=3,"Different players hear different phrases")
	expect(Guardian.PITCH_HZ.size()==3 and Guardian.SHAPES.size()==3 and Guardian.COLORS.size()==3 and Guardian.BELL_NAMES.size()==3,"Each bell has pitch, shape, colour and name")
	expect(Guardian.SHAPES[0]!=Guardian.SHAPES[1] and Guardian.SHAPES[1]!=Guardian.SHAPES[2] and Guardian.SHAPES[0]!=Guardian.SHAPES[2],"Shapes distinguish bells without colour")
	expect(Guardian.PITCH_HZ[0]<Guardian.PITCH_HZ[1] and Guardian.PITCH_HZ[1]<Guardian.PITCH_HZ[2],"Bells rise in pitch low to high")

func check_puzzle() -> void:
	var token:="tester-1"
	var rec:=Guardian.fresh()
	var frozen:=rec.duplicate(true)
	var hum:=Guardian.listen(token,rec)
	expect(hum.ok and hum.notes.size()==2 and hum.record==frozen and rec==frozen,"Listening is free and changes nothing")
	for note:Dictionary in hum.notes:expect(note.has("hz") and note.has("shape") and note.has("name"),"Hum carries sound and non-sound cues")
	var want:=Guardian.phrase(token,0)
	var wrong_bell:=(int(want[0])+1)%3
	var wrong:=Guardian.ring(token,rec,[],wrong_bell)
	expect(wrong.ok and wrong.outcome=="wrong" and wrong.record==frozen and wrong.entered.is_empty(),"A wrong bell restarts the phrase with no penalty")
	var first:=Guardian.ring(token,rec,[],want[0])
	expect(first.outcome=="progress" and first.entered==[want[0]] and first.record==frozen,"Progress is transient, not saved")
	expect(first.hash()==Guardian.ring(token,rec,[],want[0]).hash(),"Same request replays to the same result")
	var wrong_late:=Guardian.ring(token,rec,first.entered,want[0])
	expect(wrong_late.outcome=="wrong","Repeating the first bell is wrong because phrases never repeat a bell")
	var done:=Guardian.ring(token,first.record,first.entered,want[1])
	expect(done.outcome=="round" and int(done.record.round)==1 and done.entered.is_empty(),"First phrase moves the statue to its half-awake frame")
	expect(Guardian.frame(done.record)==2 and Guardian.frame(rec)==0 and Guardian.frame(rec,true)==1,"Frames follow state")
	var longer:=Guardian.listen(token,done.record)
	expect(longer.notes.size()==3,"Second hum is longer")
	var woke:=play(token,done.record)
	expect(Guardian.awake(woke) and Guardian.frame(woke)==3,"Second phrase wakes the statue")
	expect(not Guardian.ring(token,woke,[],0).ok and not Guardian.listen(token,woke).ok,"Awake statue ignores more bells")
	expect(Guardian.ring(token,rec,[],7).outcome=="invalid" and Guardian.ring(token,rec,[],-1).outcome=="invalid","Unknown bell is rejected")
	var overlong:=Guardian.ring(token,rec,[0,1,2,0],want[0])
	expect(overlong.outcome=="progress" and overlong.entered==[want[0]],"Stale over-long input restarts instead of getting stuck")
	# Two players are independent.
	var other:=play("tester-2",Guardian.fresh())
	expect(Guardian.awake(other) or int(other.round)==1,"Second player progresses on their own")
	expect(int(rec.round)==0,"First player's record is untouched by the second")

func check_fallback_and_claim() -> void:
	var rec:=Guardian.fresh()
	expect(not Guardian.claim(rec).ok,"No reward while asleep")
	for i in Guardian.CALM_NEEDED-1:
		var step:=Guardian.sit(rec)
		expect(step.ok and step.outcome=="sit" and not Guardian.awake(step.record),"Sitting is gentle progress")
		rec=step.record
	var last:=Guardian.sit(rec)
	expect(last.outcome=="awake" and Guardian.awake(last.record) and Guardian.valid(last.record),"Three quiet visits wake it without sound, timing or combat")
	expect(not Guardian.sit(last.record).ok,"Sitting stops once awake")
	var claim:=Guardian.claim(last.record)
	expect(claim.ok and claim.reward=={"item":"crystal_sand","count":2} and claim.record.claimed,"Awake statue gives the same optional reward")
	expect(not Guardian.claim(claim.record).ok,"Reward is claimable once")
	expect(Guardian.valid(claim.record),"Claimed record is valid")
	var seen:=Guardian.claim(last.record)
	expect(seen.hash()==claim.hash(),"Replaying the claim with the same record gives the same result")
	for key in ["damage","hp","health","score","timer","penalty"]:expect(not claim.record.has(key) and not claim.has(key),"No combat or failure state: %s"%key)

func check_record() -> void:
	expect(Guardian.valid(Guardian.fresh()),"Fresh record is valid")
	var json=JSON.parse_string(JSON.stringify({"round":2,"calm":1,"claimed":true}))
	expect(Guardian.valid(json),"Record survives a JSON round trip (floats)")
	for bad in [null,{},{"round":3,"calm":0,"claimed":false},{"round":0,"calm":0},{"round":0,"calm":0,"claimed":1},
			{"round":1,"calm":0,"claimed":true},{"round":0,"calm":3,"claimed":false},{"round":-1,"calm":0,"claimed":false},
			{"round":0.5,"calm":0,"claimed":false},{"round":NAN,"calm":0,"claimed":false},{"round":0,"calm":0,"claimed":false,"x":1},"text"]:
		expect(not Guardian.valid(bad),"Rejects malformed record %s"%str(bad))

func check_atlas() -> void:
	var image:=Image.load_from_file(ProjectSettings.globalize_path(Guardian.ATLAS_PATH))
	expect(image!=null and not image.is_empty(),"Atlas loads")
	if image==null or image.is_empty():return
	expect(image.get_size()==Vector2i(64,80),"Atlas is 2x2 of 32x40 (got %s)"%image.get_size())
	image.convert(Image.FORMAT_RGBA8)
	var signatures:={}
	for index in 4:
		var rect:=Guardian.frame_rect(index)
		var opaque:=0
		var low:=-1
		var edge:=0
		var amber:=0
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				var c:=image.get_pixel(x,y)
				if c.a>0.5:
					opaque+=1
					low=maxi(low,y-rect.position.y)
					if x==rect.position.x or x==rect.end.x-1 or y==rect.position.y or y==rect.end.y-1:edge+=1
					if c.r>0.75 and c.g>0.5 and c.g<0.85 and c.b<0.4:amber+=1
		expect(opaque>300,"Frame %d has a drawn sprite"%index)
		expect(edge==0,"Frame %d stays inside its cell"%index)
		expect(low>=Guardian.FOOT.y-2 and low<=Guardian.FOOT.y+1,"Frame %d rests on the foot line (lowest row %d)"%[index,low])
		signatures[index]=amber
	expect(int(signatures[3])>int(signatures[0]),"Awake frame has more amber eye pixels than the sleeping frame")
