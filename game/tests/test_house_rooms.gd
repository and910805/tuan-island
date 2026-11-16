extends SceneTree
const World=preload("res://scripts/world.gd")
const Rooms=preload("res://scripts/house_rooms.gd")
var checks:=0
var failures:=0
const DOOR:=Vector2i(11,9)
const BED:=Vector2i(13,13)
const INNER:=Vector2i(11,10)

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

static func k(p:Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

# 4x4 interior (10..13,10..13) ringed by walls (9..14), door top, bed bottom-right, fully roofed.
func house(owner:="alice",wall_owner:="",reversed:=false) -> Dictionary:
	var wo:=owner if wall_owner=="" else wall_owner
	var ground:={};var objects:={};var roofs:={}
	var ys:=range(9,15);var xs:=range(9,15)
	if reversed:ys.reverse();xs.reverse()
	for y in ys:
		for x in xs:
			var p:=Vector2i(x,y)
			if x==9 or x==14 or y==9 or y==14:
				objects[k(p)]={"type":"wall","owner":wo,"items":{}}
			else:
				ground[k(p)]={"type":"floor","owner":owner,"items":{}}
				roofs[k(p)]={"type":"roof","owner":owner,"items":{}}
	objects[k(DOOR)]={"type":"door","owner":wo,"items":{},"open":false}
	objects[k(BED)]={"type":"bed","owner":owner,"items":{}}
	return {"ground":ground,"objects":objects,"roofs":roofs,"players":{}}

func has_reason(r:Dictionary,fragment:String) -> bool:
	for m in r.missing:
		if fragment in m:return true
	return false

func run() -> void:
	# Use a known clear starter-farm tile to compare every actual construction type.
	var actual:=World.new()
	var tile:=Vector2i(41,34)
	for kind in World.BUILD:
		if kind in ["floor","path","roof","door"]:continue
		actual.state.objects[World.key(tile)]={"type":kind,"owner":"alice","items":{}}
		expect(Rooms._walkable({tile:true},actual.state.objects,tile)==not actual.blocked(tile),"Room path matches world collision for "+kind)
	# Complete house.
	var s:=house()
	var r:=Rooms.inspect(s,Vector2i(12,12))
	expect(r.found and r.complete,"complete house recognised")
	expect(r.area==16 and r.cells.size()==16 and r.cells[0]==Vector2i(10,10) and r.cells[15]==Vector2i(13,13),"area and sorted cells")
	expect(r.door_count==1 and r.gap_count==0 and r.roof_missing==0 and r.bed_count==1 and r.reachable_bed,"all structural counts")
	expect(r.contributors==["alice"] and r.missing.is_empty(),"single contributor, nothing missing")
	expect(r.cells is Array and r.contributors is Array and r.missing is Array,"result arrays present")
	# Non-mutation.
	var before:=s.duplicate(true)
	Rooms.inspect(s,Vector2i(12,12));Rooms.inspect(s,Vector2i(0,0));Rooms.inspect(s,DOOR)
	expect(s==before,"inspect does not mutate snapshot")
	# Insertion order independence.
	var rev:=Rooms.inspect(house("alice","",true),Vector2i(12,12))
	expect(rev.cells==r.cells and rev.complete and rev.contributors==r.contributors,"result independent of dictionary insertion order")
	# Wall gap, then rebuild.
	s.objects.erase(k(Vector2i(9,11)))
	r=Rooms.inspect(s,Vector2i(12,12))
	expect(r.found and not r.complete and r.gap_count==1 and has_reason(r,"缺口"),"removed wall leaves gap")
	s.objects[k(Vector2i(9,11))]={"type":"wall","owner":"alice","items":{}}
	expect(Rooms.inspect(s,Vector2i(12,12)).complete,"rebuilt wall restores house")
	# Window counts as boundary.
	s=house();s.objects[k(Vector2i(14,11))]={"type":"window","owner":"alice","items":{}}
	expect(Rooms.inspect(s,Vector2i(12,12)).complete,"window is boundary")
	# Missing roof.
	s=house();s.roofs.erase(k(Vector2i(12,12)))
	r=Rooms.inspect(s,Vector2i(12,12))
	expect(not r.complete and r.roof_missing==1 and has_reason(r,"屋頂缺 1 格"),"missing roof reported")
	# No door.
	s=house();s.objects[k(DOOR)]={"type":"wall","owner":"alice","items":{}}
	r=Rooms.inspect(s,Vector2i(12,12))
	expect(not r.complete and r.door_count==0 and r.gap_count==0 and has_reason(r,"門"),"missing door reported")
	# No bed.
	s=house();s.objects.erase(k(BED))
	r=Rooms.inspect(s,Vector2i(12,12))
	expect(not r.complete and r.bed_count==0 and not r.reachable_bed and has_reason(r,"床"),"missing bed reported")
	# Open door still boundary.
	s=house();s.objects[k(DOOR)].open=true
	r=Rooms.inspect(s,Vector2i(12,12))
	expect(r.complete and r.door_count==1 and r.gap_count==0,"open door counts as boundary")
	# Bed blocking inner side of the only door.
	s=house();s.objects.erase(k(BED));s.objects[k(INNER)]={"type":"bed","owner":"alice","items":{}}
	r=Rooms.inspect(s,Vector2i(12,12))
	expect(not r.complete and r.bed_count==1 and not r.reachable_bed and has_reason(r,"走不到床邊"),"bed blocking inner door fails")
	expect(r.area==16,"furniture tiles stay in floor area")
	# Furniture wall cutting off the bed.
	s=house()
	for p in [Vector2i(10,12),Vector2i(11,12),Vector2i(12,12),Vector2i(13,12)]:s.objects[k(p)]={"type":"chest","owner":"alice","items":{}}
	r=Rooms.inspect(s,Vector2i(11,11))
	expect(not r.reachable_bed and not r.complete,"furniture row blocks path to bed")
	# Two owners.
	s=house("alice","bob")
	r=Rooms.inspect(s,Vector2i(12,12))
	expect(r.complete and r.contributors==["alice","bob"],"two owners deduplicated and sorted")
	s.roofs[k(Vector2i(10,10))].owner="carol";s.objects["30,30"]={"type":"wall","owner":"zed","items":{}}
	expect(Rooms.inspect(s,Vector2i(12,12)).contributors==["alice","bob","carol"],"roof owner counts, unrelated object does not")
	# Deterministic nearest seed.
	s=house()
	r=Rooms.inspect(s,Vector2i(11,7))
	expect(r.found and r.complete and r.area==16,"seed from outside door within 8 tiles")
	r=Rooms.inspect(s,DOOR)
	expect(r.found and r.area==16,"seed from door cell")
	expect(not Rooms.inspect(s,Vector2i(30,30)).found,"no floor within 8 tiles")
	var tie:={"ground":{"7,5":{"type":"floor","owner":"b"},"5,5":{"type":"floor","owner":"a"},"6,6":{"type":"floor","owner":"d"},"6,4":{"type":"floor","owner":"c"}}}
	r=Rooms.inspect(tie,Vector2i(6,5))
	expect(r.found and r.cells==[Vector2i(6,4)],"tie-break prefers smaller y then x")
	tie.ground.erase("6,4")
	expect(Rooms.inspect(tie,Vector2i(6,5)).cells==[Vector2i(5,5)],"same-row tie prefers smaller x")
	# Disconnected floors.
	s=house();s.ground["20,20"]={"type":"floor","owner":"bob","items":{}};s.ground["10,16"]={"type":"floor","owner":"bob","items":{}}
	r=Rooms.inspect(s,Vector2i(12,12))
	expect(r.complete and r.area==16 and r.contributors==["alice"],"outside floors not joined")
	r=Rooms.inspect(s,Vector2i(20,20))
	expect(r.found and not r.complete and r.area==1 and r.gap_count==4 and has_reason(r,"至少需要 4 格"),"lone floor reports area and gaps")
	# Path ground type is not floor.
	s=house();s.ground[k(Vector2i(12,12))]={"type":"path","owner":"alice","items":{}}
	r=Rooms.inspect(s,Vector2i(11,11))
	expect(not r.complete and r.area==15 and r.gap_count==4 and not (Vector2i(12,12) in r.cells),"path excluded from floor and counted as gap")
	# Other-region data in snapshot is ignored.
	s=house();s["regions"]={"other":{"ground":{"30,30":{"type":"floor","owner":"x"}}}}
	expect(not Rooms.inspect(s,Vector2i(30,30)).found,"saved other-region layers not scanned")
	# Empty and invalid snapshots.
	r=Rooms.inspect({},Vector2i.ZERO)
	expect(not r.found and not r.complete and r.area==0 and r.missing.size()==1 and r.cells.is_empty(),"empty snapshot safe")
	r=Rooms.inspect({"ground":5,"objects":"x","roofs":[]},Vector2i.ZERO)
	expect(not r.found and not r.missing.is_empty(),"invalid layer types safe")
	r=Rooms.inspect({"ground":{"0,0":"floor","1,0":{"type":7},"a,b":{"type":"floor"}},"objects":{"0,0":3}},Vector2i.ZERO)
	expect(not r.found,"malformed entries ignored")
	# Large open floor is bounded.
	var big:={"ground":{}}
	for y in range(30):
		for x in range(30):big.ground[k(Vector2i(x,y))]={"type":"floor","owner":"a"}
	r=Rooms.inspect(big,Vector2i(15,15))
	expect(r.found and not r.complete and r.area==Rooms.MAX_CELLS,"oversized component capped")
	print("HOUSE_ROOMS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
