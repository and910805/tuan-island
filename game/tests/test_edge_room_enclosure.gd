extends SceneTree
const Enclosure=preload("res://scripts/room_enclosure.gd")
const EdgeGrid=preload("res://scripts/edge_grid.gd")
const RoofPlan=preload("res://scripts/auto_roof_plan.gd")
const RoofVisibility=preload("res://scripts/roof_visibility.gd")
const HouseRooms=preload("res://scripts/house_rooms.gd")
var checks:=0
var failures:=0

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

static func k(p:Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

func floors(o:Vector2i,w:int,h:int,ground:Dictionary) -> void:
	for y in range(o.y,o.y+h):
		for x in range(o.x,o.x+w):
			ground[k(Vector2i(x,y))]={"type":"floor","owner":"alice","items":{}}

# Edge keys around the w x h rectangle at o, in a fixed order: top, bottom, left, right.
func ring(o:Vector2i,w:int,h:int) -> Array[String]:
	var out:Array[String]=[]
	for x in range(o.x,o.x+w):out.append(EdgeGrid.key(Vector2i(x,o.y),EdgeGrid.SIDE_N))
	for x in range(o.x,o.x+w):out.append(EdgeGrid.key(Vector2i(x,o.y+h-1),EdgeGrid.SIDE_S))
	for y in range(o.y,o.y+h):out.append(EdgeGrid.key(Vector2i(o.x,y),EdgeGrid.SIDE_W))
	for y in range(o.y,o.y+h):out.append(EdgeGrid.key(Vector2i(o.x+w-1,y),EdgeGrid.SIDE_E))
	return out

func wall() -> Dictionary:
	return {"type":"edge_wall"}

func snap(ground:Dictionary,objects:Dictionary,edges:Dictionary) -> Dictionary:
	return {"ground":ground,"objects":objects,"edges":edges}

func shape_ok(r:Dictionary) -> bool:
	for key in ["cells","boundary","doors"]:
		if not r.has(key) or not (r[key] is Array) or r[key].get_typed_builtin()!=TYPE_VECTOR2I:return false
	for key in ["edge_boundary","edge_doors"]:
		if not r.has(key) or not (r[key] is Array) or r[key].get_typed_builtin()!=TYPE_STRING:return false
	return typeof(r.area)==TYPE_INT and typeof(r.gap_count)==TYPE_INT and typeof(r.truncated)==TYPE_BOOL and typeof(r.sealed)==TYPE_BOOL

func run() -> void:
	var O:=Vector2i(10,10)
	var MID:=Vector2i(11,11)
	var ground:={}
	floors(O,4,4,ground)
	var keys:=ring(O,4,4)
	expect(keys.size()==16,"ring has 16 edges")

	# 1. Pure edge room with one edge door.
	var edges:={}
	for e in keys:edges[e]=wall()
	var door_key:=keys[1]
	edges[door_key]={"type":"edge_door","open":false}
	var s:=snap(ground,{},edges)
	var r:=Enclosure.analyze(s,MID)
	expect(shape_ok(r),"result shape with typed edge arrays")
	expect(r.sealed and r.area==16 and r.gap_count==0 and not r.truncated,"edge ring with door sealed")
	expect(r.boundary.is_empty() and r.doors.is_empty(),"legacy vectors empty for edge-only room")
	expect(r.edge_boundary.size()==16 and r.edge_doors==[door_key],"edge boundary 16, one edge door")
	expect(door_key in r.edge_boundary,"edge doors subset of edge boundary")

	# 2. Open door is still a barrier for flood and keeps the room sealed.
	var s_open:=s.duplicate(true)
	s_open.edges[door_key]={"type":"edge_door","open":true}
	var r2:=Enclosure.analyze(s_open,MID)
	expect(r2.sealed and r2.area==16 and r2.edge_doors==[door_key],"open edge door still barrier")

	# 3. Window edge counts as boundary, not door.
	var s_win:=s.duplicate(true)
	s_win.edges[keys[0]]={"type":"edge_window"}
	var r3:=Enclosure.analyze(s_win,MID)
	expect(r3.sealed and r3.edge_boundary.size()==16 and r3.edge_doors==[door_key],"edge window is boundary only")

	# 4. Gap: remove one edge wall.
	var s_gap:=s.duplicate(true)
	s_gap.edges.erase(keys[5])
	var r4:=Enclosure.analyze(s_gap,MID)
	expect(r4.gap_count==1 and not r4.sealed and r4.edge_boundary.size()==15,"missing edge is one gap")

	# 5. No door: not sealed, and an unrelated door elsewhere never helps.
	var s_nodoor:=s.duplicate(true)
	s_nodoor.edges[door_key]=wall()
	var far_objects:={k(Vector2i(40,40)):{"type":"door","open":false}}
	s_nodoor.objects=far_objects
	s_nodoor.edges[EdgeGrid.key(Vector2i(50,50),EdgeGrid.SIDE_N)]={"type":"edge_door"}
	var r5:=Enclosure.analyze(s_nodoor,MID)
	expect(not r5.sealed and r5.gap_count==0 and r5.edge_doors.is_empty() and r5.doors.is_empty(),"unrelated doors do not seal")

	# 6. Invalid rows and unknown types are not barriers.
	var s_bad:=s.duplicate(true)
	s_bad.edges[keys[5]]={"type":"edge_foo"}
	s_bad.edges[keys[6]]="edge_wall"
	s_bad.edges["bogus"]=wall()
	var r6:=Enclosure.analyze(s_bad,MID)
	expect(r6.gap_count==2 and not r6.sealed,"invalid edge rows ignored")

	# 7. Edge divider inside floor (floor on both sides) splits the flood.
	var s_split:=s.duplicate(true)
	for y in range(10,14):s_split.edges[EdgeGrid.key(Vector2i(12,y),EdgeGrid.SIDE_W)]=wall()
	var ra:=Enclosure.analyze(s_split,Vector2i(10,10))
	var rb:=Enclosure.analyze(s_split,Vector2i(13,13))
	expect(ra.area==8 and rb.area==8 and ra.gap_count==0 and rb.gap_count==0,"edge divider splits floor")
	expect(ra.edge_boundary.size()==12 and rb.edge_boundary.size()==12,"divider counted in both halves")
	expect(not Vector2i(12,10) in ra.cells and Vector2i(12,10) in rb.cells,"halves disjoint")
	expect(ra.edge_doors==[door_key] and rb.edge_doors.is_empty() and ra.sealed and not rb.sealed,"door belongs to its own room only")

	# 8. Adjacent separate rooms sharing an open edge door.
	var g2:={}
	floors(Vector2i(10,10),4,4,g2)
	floors(Vector2i(14,10),4,4,g2)
	var e2:={}
	for e in ring(Vector2i(10,10),4,4):e2[e]=wall()
	for e in ring(Vector2i(14,10),4,4):e2[e]=wall()
	var shared:=EdgeGrid.key(Vector2i(13,11),EdgeGrid.SIDE_E)
	expect(shared==EdgeGrid.key(Vector2i(14,11),EdgeGrid.SIDE_W),"shared edge key identical from both cells")
	e2[shared]={"type":"edge_door","open":true}
	var s2:=snap(g2,{},e2)
	var left:=Enclosure.analyze(s2,Vector2i(11,11))
	var right:=Enclosure.analyze(s2,Vector2i(15,11))
	expect(left.area==16 and right.area==16 and left.sealed and right.sealed,"both adjacent rooms sealed")
	expect(left.edge_doors==[shared] and right.edge_doors==[shared],"both rooms see the shared door")
	expect(shared in left.edge_boundary and shared in right.edge_boundary,"shared edge in both boundaries")
	expect(left.edge_boundary.size()==16 and right.edge_boundary.size()==16,"shared edge deduplicated")
	var overlap:=false
	for c in left.cells:
		if c in right.cells:overlap=true
	expect(not overlap,"cells of adjacent rooms disjoint")
	# Without the door, neither room is sealed.
	var s2n:=s2.duplicate(true)
	s2n.edges[shared]=wall()
	expect(not Enclosure.analyze(s2n,Vector2i(11,11)).sealed and not Enclosure.analyze(s2n,Vector2i(15,11)).sealed,"no door, no seal")

	# 9. Mixed: legacy wall/window/door on three sides, edges on top.
	var g3:={}
	floors(O,4,4,g3)
	var o3:={}
	for i in range(10,14):
		o3[k(Vector2i(i,14))]={"type":"wall","items":{}}
		o3[k(Vector2i(9,i))]={"type":"wall","items":{}}
		o3[k(Vector2i(14,i))]={"type":"wall","items":{}}
	o3[k(Vector2i(11,14))]={"type":"window","items":{}}
	o3[k(Vector2i(14,12))]={"type":"door","open":false,"items":{}}
	var e3:={}
	for x in range(10,14):e3[EdgeGrid.key(Vector2i(x,10),EdgeGrid.SIDE_N)]=wall()
	var s3:=snap(g3,o3,e3)
	var r9:=Enclosure.analyze(s3,MID)
	expect(r9.sealed and r9.area==16 and r9.gap_count==0,"mixed room sealed by legacy door")
	expect(r9.boundary.size()==12 and r9.doors==[Vector2i(14,12)] and r9.edge_boundary.size()==4 and r9.edge_doors.is_empty(),"mixed boundaries separated")
	# Mixed with edge door only: legacy door downgraded to wall.
	var s3b:=s3.duplicate(true)
	s3b.objects[k(Vector2i(14,12))]={"type":"wall","items":{}}
	var r9b:=Enclosure.analyze(s3b,MID)
	expect(not r9b.sealed and r9b.doors.is_empty(),"no door, mixed room not sealed")
	s3b.edges[EdgeGrid.key(Vector2i(11,10),EdgeGrid.SIDE_N)]={"type":"edge_door"}
	var r9c:=Enclosure.analyze(s3b,MID)
	expect(r9c.sealed and r9c.doors.is_empty() and r9c.edge_doors.size()==1,"edge door alone seals mixed room")
	# Missing the top edge in a legacy room leaves a gap.
	var s3c:=s3.duplicate(true)
	s3c.edges.erase(EdgeGrid.key(Vector2i(12,10),EdgeGrid.SIDE_N))
	expect(Enclosure.analyze(s3c,MID).gap_count==1,"mixed room gap counted")
	# Edge takes priority over a legacy wall on the same side.
	var s3d:=s3.duplicate(true)
	s3d.edges[EdgeGrid.key(Vector2i(10,10),EdgeGrid.SIDE_W)]=wall()
	var r9d:=Enclosure.analyze(s3d,MID)
	expect(r9d.edge_boundary.size()==5 and r9d.boundary.size()==11 and not Vector2i(9,10) in r9d.boundary,"edge counted before legacy wall")

	# 10. Missing or non-dictionary edges layer behaves like legacy.
	var legacy:=snap(g3,o3,{})
	legacy.erase("edges")
	var r10:=Enclosure.analyze(legacy,MID)
	expect(shape_ok(r10) and r10.edge_boundary.is_empty() and r10.gap_count==4,"no edges layer ok")
	legacy["edges"]=[]
	expect(Enclosure.analyze(legacy,MID).gap_count==4,"non-dictionary edges layer ignored")
	expect(shape_ok(Enclosure.analyze(s,Vector2i(0,0))) and Enclosure.analyze(s,Vector2i(0,0)).area==0,"non-floor seed gives empty typed result")

	# 11. Read-only.
	var before:=s3.duplicate(true)
	Enclosure.analyze(s3,MID)
	Enclosure.analyze(s2,Vector2i(15,11))
	expect(s3==before,"snapshot not mutated")

	verify_roof_and_furniture()
	print("test_edge_room_enclosure: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)

func verify_roof_and_furniture() -> void:
	var origin:=Vector2i(10,10)
	var ground:={}
	floors(origin,8,4,ground)
	var edges:={}
	for edge in ring(origin,4,4)+ring(origin+Vector2i(4,0),4,4):
		edges[edge]={"type":"edge_wall","owner":"builder"}
	var shared:=EdgeGrid.key(Vector2i(14,11),EdgeGrid.SIDE_W)
	edges[shared]={"type":"edge_door","owner":"builder","open":true}
	var bed:=Vector2i(12,12)
	var finished:=snap(ground,{k(bed):{"type":"bed","owner":"alice"}},edges)
	var incomplete:=finished.duplicate(true)
	incomplete.edges.erase(shared)
	var affected:Array[Vector2i]=[Vector2i(13,11),Vector2i(14,11)]
	var recipe:={"wood":1,"fiber":3}
	var plan:=RoofPlan.reconcile(incomplete,finished,affected,"builder",recipe)
	expect(plan.ok and plan.add.size()==32 and plan.cost=={"wood":32,"fiber":96},"closing two rooms settles exactly their floor area")
	finished.roofs=plan.add
	var house:=HouseRooms.inspect(finished,origin)
	expect(house.complete and house.door_count==1 and house.reachable_bed and "builder" in house.contributors,"inspector counts the door and reaches the bed")
	finished.players={"alice":{"x":11.5,"y":12.5}}
	var fade:=RoofVisibility.faded(finished,"alice")
	expect(fade.has("10,10") and not fade.has("16,12"),"roof shelter fades only the occupied room across an open door")
	var reopened:=finished.duplicate(true)
	reopened.edges.erase(shared)
	var removed:=RoofPlan.reconcile(finished,reopened,affected,"alice",recipe)
	expect(removed.ok and removed.remove.size()==32 and removed.refunds=={"builder":{"wood":32,"fiber":96}},"removing the last qualifying door refunds both roofs to their payer")
