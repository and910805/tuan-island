extends SceneTree
const Enclosure=preload("res://scripts/room_enclosure.gd")
var checks:=0
var failures:=0
const KEYS:=["cells","boundary","doors","area","gap_count","truncated","sealed"]

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

static func k(p:Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

# Interior w x h starting at o, ringed by walls; one door on the ring (if given).
func room(o:Vector2i,w:int,h:int,door=null,owner:="alice",wall_owner:="",reversed:=false) -> Dictionary:
	var wo:=owner if wall_owner=="" else wall_owner
	var ground:={};var objects:={}
	var ys:=range(o.y-1,o.y+h+1);var xs:=range(o.x-1,o.x+w+1)
	if reversed:ys.reverse();xs.reverse()
	for y in ys:
		for x in xs:
			var p:=Vector2i(x,y)
			if x==o.x-1 or x==o.x+w or y==o.y-1 or y==o.y+h:
				objects[k(p)]={"type":"wall","owner":wo,"items":{}}
			else:
				ground[k(p)]={"type":"floor","owner":owner,"items":{}}
	if door is Vector2i:objects[k(door)]={"type":"door","owner":wo,"items":{},"open":false}
	return {"ground":ground,"objects":objects}

func shape_ok(r:Dictionary) -> bool:
	if r.size()!=KEYS.size():return false
	for key in KEYS:
		if not r.has(key):return false
	for key in ["cells","boundary","doors"]:
		if not (r[key] is Array) or r[key].get_typed_builtin()!=TYPE_VECTOR2I:return false
	return typeof(r.area)==TYPE_INT and typeof(r.gap_count)==TYPE_INT and typeof(r.truncated)==TYPE_BOOL and typeof(r.sealed)==TYPE_BOOL

func is_empty_result(r:Dictionary) -> bool:
	return shape_ok(r) and r.cells.is_empty() and r.boundary.is_empty() and r.doors.is_empty() and r.area==0 and r.gap_count==0 and not r.truncated and not r.sealed

func sorted_yx(a:Array) -> bool:
	for i in range(1,a.size()):
		var p:Vector2i=a[i-1];var q:Vector2i=a[i]
		if not (p.y<q.y or (p.y==q.y and p.x<q.x)):return false
	return true

func shifted(a:Array,off:Vector2i) -> Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for p in a:out.append(p+off)
	return out

const O:=Vector2i(10,10)
const DOOR:=Vector2i(11,9)
const MID:=Vector2i(12,12)

func run() -> void:
	# Closed 4x4 room.
	var s:=room(O,4,4,DOOR)
	var r:=Enclosure.analyze(s,MID)
	expect(shape_ok(r),"result shape and typed arrays")
	expect(r.sealed and r.area==16 and r.cells.size()==16 and r.gap_count==0 and not r.truncated,"closed room sealed")
	expect(r.cells[0]==Vector2i(10,10) and r.cells[15]==Vector2i(13,13) and sorted_yx(r.cells),"cells sorted y then x")
	expect(r.boundary.size()==16 and sorted_yx(r.boundary) and not (Vector2i(9,9) in r.boundary),"boundary deduplicated, sorted, no diagonal corners")
	expect(r.doors==[DOOR] and DOOR in r.boundary,"doors subset of boundary")
	expect(Enclosure.MIN_AREA==4 and Enclosure.MAX_CELLS==400,"constants")
	# Exact seed only: no nearest search.
	expect(is_empty_result(Enclosure.analyze(s,DOOR)),"door seed yields empty result")
	expect(is_empty_result(Enclosure.analyze(s,Vector2i(11,8))),"seed just outside door yields empty result")
	expect(is_empty_result(Enclosure.analyze(s,Vector2i(9,12))),"wall seed yields empty result")
	expect(is_empty_result(Enclosure.analyze(s,Vector2i(40,40))),"far seed yields empty result")
	var corner:=Enclosure.analyze(s,Vector2i(10,10))
	expect(corner.sealed and corner.cells==r.cells,"any interior seed finds the same room")
	# Open door and shut door both count.
	s.objects[k(DOOR)].open=true
	r=Enclosure.analyze(s,MID)
	expect(r.sealed and r.doors==[DOOR] and r.gap_count==0,"open door counts as boundary and door")
	# Window is boundary.
	s=room(O,4,4,DOOR);s.objects[k(Vector2i(14,11))]={"type":"window","owner":"alice","items":{}}
	r=Enclosure.analyze(s,MID)
	expect(r.sealed and Vector2i(14,11) in r.boundary and r.doors.size()==1,"window is boundary, not a door")
	# Open room: wall removed.
	s=room(O,4,4,DOOR);s.objects.erase(k(Vector2i(9,11)))
	r=Enclosure.analyze(s,MID)
	expect(not r.sealed and r.gap_count==1 and r.boundary.size()==15 and r.area==16,"missing wall is one gap")
	s.objects.erase(k(Vector2i(14,12)))
	expect(Enclosure.analyze(s,MID).gap_count==2,"two missing walls two gaps")
	# Corner gap at a convex corner exposes two edges.
	s=room(O,1,1,Vector2i(10,9));s.objects.erase(k(Vector2i(11,10)))
	expect(Enclosure.analyze(s,O).gap_count==1,"single-cell exposed edge counted")
	# No door.
	s=room(O,4,4,null)
	r=Enclosure.analyze(s,MID)
	expect(not r.sealed and r.doors.is_empty() and r.gap_count==0 and r.area==16 and r.boundary.size()==16,"no door not sealed")
	# Doors on outside (diagonal) corners don't qualify.
	for c in [Vector2i(9,9),Vector2i(14,9),Vector2i(9,14),Vector2i(14,14)]:
		s.objects[k(c)]={"type":"door","owner":"alice","items":{},"open":true}
	s.objects["11,7"]={"type":"door","owner":"alice","items":{}}
	r=Enclosure.analyze(s,MID)
	expect(not r.sealed and r.doors.is_empty() and r.boundary.size()==16 and not (Vector2i(9,9) in r.boundary),"corner/detached doors do not qualify")
	# Separated rooms sharing a wall column x=14.
	s=room(O,4,4,DOOR)
	var b:=room(Vector2i(15,10),4,4,Vector2i(16,14),"bob")
	for key in b.ground:s.ground[key]=b.ground[key]
	for key in b.objects:
		if not s.objects.has(key):s.objects[key]=b.objects[key]
	var ra:=Enclosure.analyze(s,MID)
	var rb:=Enclosure.analyze(s,Vector2i(17,12))
	expect(ra.sealed and rb.sealed and ra.area==16 and rb.area==16,"two separated rooms both sealed")
	expect(ra.doors==[DOOR] and rb.doors==[Vector2i(16,14)],"each room has its own door")
	var overlap:=false
	for c in ra.cells:
		if c in rb.cells:overlap=true
	expect(not overlap and Vector2i(14,12) in ra.boundary and Vector2i(14,12) in rb.boundary,"no shared cells; shared wall in both boundaries")
	# Internal door between rooms joins nothing; it is a door for both.
	s.objects[k(Vector2i(14,12))]={"type":"door","owner":"bob","items":{},"open":true}
	ra=Enclosure.analyze(s,MID);rb=Enclosure.analyze(s,Vector2i(17,12))
	expect(ra.area==16 and rb.area==16 and Vector2i(14,12) in ra.doors and Vector2i(14,12) in rb.doors,"shared door separates and counts for both")
	# Missing floor inside room.
	s=room(O,4,4,DOOR);s.ground.erase(k(MID))
	r=Enclosure.analyze(s,Vector2i(11,11))
	expect(not r.sealed and r.area==15 and r.gap_count==4 and not (MID in r.cells) and not (MID in r.boundary),"missing floor is a hole with four gaps")
	expect(is_empty_result(Enclosure.analyze(s,MID)),"seed on missing floor empty")
	# Path is not floor.
	s=room(O,4,4,DOOR);s.ground[k(MID)]={"type":"path","owner":"alice","items":{}}
	r=Enclosure.analyze(s,Vector2i(11,11))
	expect(not r.sealed and r.area==15 and r.gap_count==4,"path tile counts as gap")
	# Floor under walls/windows/doors is excluded.
	s=room(O,4,4,DOOR)
	for key in s.objects:s.ground[key]={"type":"floor","owner":"alice","items":{}}
	s.ground["11,8"]={"type":"floor","owner":"alice","items":{}}
	r=Enclosure.analyze(s,MID)
	expect(r.sealed and r.area==16 and r.boundary.size()==16 and r.doors==[DOOR],"floor under boundary excluded and not leaked through door")
	expect(is_empty_result(Enclosure.analyze(s,Vector2i(9,12))) and is_empty_result(Enclosure.analyze(s,DOOR)),"floored boundary seeds empty")
	r=Enclosure.analyze(s,Vector2i(11,8))
	expect(r.area==1 and Vector2i(11,9) in r.doors and r.gap_count==3 and not r.sealed,"outside floor touching door is its own region")
	# Mixed owners; bed/roof/furniture are irrelevant.
	s=room(O,4,4,DOOR,"alice","bob")
	s.objects[k(DOOR)].owner="carol"
	s.ground[k(MID)].owner="dave"
	s.objects[k(Vector2i(10,10))]={"type":"chest","owner":"erin","items":{}}
	r=Enclosure.analyze(s,MID)
	expect(r.sealed and r.area==16 and Vector2i(10,10) in r.cells,"mixed owners, no roof, no bed, furniture floor still sealed")
	s["roofs"]="garbage";s["players"]=null
	expect(Enclosure.analyze(s,MID).sealed,"roof/player layers ignored")
	s=room(O,4,4,DOOR);s.objects[k(Vector2i(13,13))]={"type":"bed","owner":"alice","items":{}}
	s["roofs"]={}
	expect(Enclosure.analyze(s,MID).sealed,"bed is neither required nor blocking")
	# Area threshold.
	s=room(O,3,1,Vector2i(11,9))
	r=Enclosure.analyze(s,O)
	expect(not r.sealed and r.area==3 and r.gap_count==0 and r.doors.size()==1,"area 3 not sealed")
	s=room(O,2,2,Vector2i(10,9))
	r=Enclosure.analyze(s,O)
	expect(r.sealed and r.area==4,"area 4 sealed")
	# Max cap.
	s=room(Vector2i(0,0),20,20,Vector2i(5,-1))
	r=Enclosure.analyze(s,Vector2i(7,7))
	expect(r.sealed and r.area==400 and not r.truncated,"exactly MAX_CELLS room sealed, not truncated")
	s=room(Vector2i(0,0),21,20,Vector2i(5,-1))
	r=Enclosure.analyze(s,Vector2i(7,7))
	expect(r.truncated and not r.sealed and r.area==400 and r.cells.size()==400 and sorted_yx(r.cells),"over-cap enclosed room truncated, never sealed")
	var big:={"ground":{}}
	for y in range(30):
		for x in range(30):big.ground[k(Vector2i(x,y))]={"type":"floor"}
	r=Enclosure.analyze(big,Vector2i(15,15))
	expect(r.truncated and not r.sealed and r.area==Enclosure.MAX_CELLS,"open field capped")
	expect(Enclosure.analyze(big,Vector2i(15,15)).cells==r.cells,"truncated result deterministic")
	# Immutability.
	s=room(O,4,4,DOOR)
	var before:=s.duplicate(true)
	r=Enclosure.analyze(s,MID)
	Enclosure.analyze(s,DOOR);Enclosure.analyze(s,Vector2i(0,0));Enclosure.analyze(s,Vector2i(9,9))
	expect(s==before,"analyze does not mutate snapshot")
	r.cells.clear();r.boundary.clear();r.doors.clear();r.area=0
	r=Enclosure.analyze(s,MID)
	expect(r.area==16 and r.cells.size()==16 and r.boundary.size()==16 and s==before,"mutating a result does not affect snapshot or next call")
	# Insertion order independence.
	var base:=Enclosure.analyze(room(O,4,4,DOOR),MID)
	var rev:=Enclosure.analyze(room(O,4,4,DOOR,"alice","",true),MID)
	expect(rev==base,"result independent of dictionary insertion order")
	# Translated coordinates, including negatives.
	var off:=Vector2i(-37,-52)
	var t:=Enclosure.analyze(room(O+off,4,4,DOOR+off),MID+off)
	expect(t.sealed and t.area==base.area and t.gap_count==base.gap_count,"translated room sealed")
	expect(t.cells==shifted(base.cells,off) and t.boundary==shifted(base.boundary,off) and t.doors==shifted(base.doors,off),"translated arrays match shifted original")
	# Current-region layers only.
	s={"regions":{"other":{"ground":{"30,30":{"type":"floor"}}}},"ground":{},"objects":{}}
	expect(is_empty_result(Enclosure.analyze(s,Vector2i(30,30))),"other-region layers not scanned")
	# Null / malformed layers and values.
	expect(is_empty_result(Enclosure.analyze({},Vector2i.ZERO)),"empty snapshot safe")
	expect(is_empty_result(Enclosure.analyze({"ground":null,"objects":null},Vector2i.ZERO)),"null layers safe")
	expect(is_empty_result(Enclosure.analyze({"ground":5,"objects":"x"},Vector2i.ZERO)),"wrong-type layers safe")
	r=Enclosure.analyze({"ground":{"0,0":"floor","1,0":{"type":7},"0,1":null,"a,b":{"type":"floor"},Vector2i.ZERO:{"type":"floor"}}},Vector2i.ZERO)
	expect(is_empty_result(r),"malformed ground entries ignored")
	r=Enclosure.analyze({"ground":{"0,0":{"type":null},"1,0":{}}},Vector2i.ZERO)
	expect(is_empty_result(r),"null/missing type safe")
	s=room(O,4,4,DOOR);s.objects["9,11"]=3;s.objects["14,11"]={"type":null};s.objects["10,13"]=[1]
	r=Enclosure.analyze(s,MID)
	expect(shape_ok(r) and not r.sealed and r.gap_count==2 and r.area==16,"malformed objects are not boundary")
	s=room(O,4,4,DOOR);s.objects[k(DOOR)]={"type":"door","open":"yes"}
	expect(Enclosure.analyze(s,MID).sealed,"odd door open value still a door")
	s={"ground":{"0,0":{"type":"floor"}},"objects":null}
	r=Enclosure.analyze(s,Vector2i.ZERO)
	expect(shape_ok(r) and r.area==1 and r.gap_count==4 and not r.sealed,"single floor with null objects")
	print("ROOM_ENCLOSURE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
