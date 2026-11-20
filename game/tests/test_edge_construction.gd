extends SceneTree
## Edge construction rules (build_edge / remove_edge / toggle_edge), tested through the World.act
## contract. Not run by the author (no shell in the authoring session): Codex runs it, AFTER wiring
## World.act/_apply to EdgeConstruction.apply and the auto-roof hooks for the three edge actions.
## Until that wiring exists every act() scenario fails by design; test_decode is pure and runs now.
##
## SEEDED FIXTURES (disclosed): worlds are real World instances with real players; the only
## hand-written state is (a) inventories/builds counters, (b) a mill anchor object, (c) a ground
## piece's `placement_access`, (d) `public_build_access`, (e) player positions and active_tokens.
## Saves go to an isolated user:// directory that is removed afterwards.
## NOT covered: the donated public kitchen cells (PUBLIC_KITCHEN.shape_ok needs a full registered
## kitchen); that gate is PLOT_PERMISSIONS.kitchen_locked / World.protected, both existing code.
const World=preload("res://scripts/world.gd")
const REGIONS=preload("res://scripts/regions.gd")
const EC=preload("res://scripts/edge_construction.gd")
const EdgeGrid=preload("res://scripts/edge_grid.gd")
const Industry=preload("res://scripts/industry.gd")
const Session=preload("res://scripts/session.gd")
const A:="tok-edgecon-alice"
const B:="tok-edgecon-bob"
const PARK:=World.SPAWN
const HOME:=REGIONS.HOME
const BOUNDS:=Vector2i(80,60)
const CAP:=1000000000

var checks:=0
var failures:=0
var serial:=0
var dir:=""

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize()->void:call_deferred("run")

# ---------------------------------------------------------------- fixtures --

func new_world()->World:
	var w:=World.new()
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	for t in [A,B]:w.state.players[t].inventory={"wood":500,"stone":100,"fiber":300,"glass":20}
	serial+=1
	w.save_path=dir+"/world-%d.json"%serial
	return w

func cell_clear(w:World,c:Vector2i)->bool:
	if not w.is_land(c) or w.water(c) or w.protected(c):return false
	if World.essential_cell_reason(w.state,HOME,c)!="":return false
	var k:=World.key(c)
	for field in ["objects","ground","roofs","crops","forest"]:
		if w.state[field].has(k):return false
	return true

## Origin of a clear `size` interior with a clear 3-cell ring all around, away from spawn/landing/exit
## and the public plot. Trees and rocks inside the found box are removed (prepared world).
func find_site(w:World,size:Vector2i)->Vector2i:
	var avoid:Array[Vector2i]=[Vector2i(World.SPAWN),World.WANGAN_COAST.FERRY_LANDING,Vector2i(REGIONS.spawn(HOME)),REGIONS.exit_cell(HOME)]
	var found:=Vector2i(-1,-1)
	for oy in range(8,50):
		for ox in range(8,70):
			var box:=Rect2i(Vector2i(ox-3,oy-3),size+Vector2i(6,6))
			if box.intersects(World.PUBLIC_BUILD_PLOT) or avoid.any(func(p:Vector2i)->bool:return box.has_point(p)):continue
			var good:=true
			for y in range(box.position.y,box.end.y):
				for x in range(box.position.x,box.end.x):
					if not cell_clear(w,Vector2i(x,y)):
						good=false
						break
				if not good:break
			if good:
				found=Vector2i(ox,oy)
				break
		if found.x>=0:break
	expect(found.x>=0,"found a legal empty site")
	if found.x>=0:
		for y in range(found.y-3,found.y+size.y+3):
			for x in range(found.x-3,found.x+size.x+3):
				var c:=Vector2i(x,y)
				if w.resource(c)!="":w.state.removed[World.key(c)]=true
	return found

func centre(c:Vector2i)->Vector2:
	return Vector2(c)+Vector2(0.5,0.5)

func pose(w:World,token:String,at:Vector2,others:Dictionary={})->void:
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:Vector2=at if t==token else (others[t] if others.has(t) else PARK)
		person.x=spot.x
		person.y=spot.y

func do(w:World,token:String,action:String,p:Vector2i,extra:="",at=null,others:Dictionary={})->Dictionary:
	pose(w,token,centre(p) if at==null else at,others)
	serial+=1
	var r:Dictionary=w.act(token,"edge-%d"%serial,action,p,extra)
	expect(w._region==HOME,"home orientation after "+action)
	return r

func reject(w:World,token:String,action:String,p:Vector2i,extra:String,needle:String,label:String,at=null,others:Dictionary={})->void:
	pose(w,token,centre(p) if at==null else at,others)
	var snap:=var_to_str(w.state)
	serial+=1
	var r:Dictionary=w.act(token,"edge-bad-%d"%serial,action,p,extra)
	expect(not r.ok,label+": rejected, got "+str(r))
	if not needle.is_empty():expect(str(r.get("message","")).contains(needle),label+": message has '"+needle+"', got "+str(r.get("message","")))
	expect(var_to_str(w.state)==snap,label+": world exactly unchanged")

func inv(w:World,token:String)->Dictionary:
	return w.state.players[token].inventory.duplicate(true)

func layers(w:World)->String:
	return var_to_str([w.state.objects,w.state.ground,w.state.crops,w.state.forest])

func auto_count(w:World)->int:
	var n:=0
	for roof in w.state.roofs.values():
		if roof.get("auto",false)==true:n+=1
	return n

func edge_key(c:Vector2i,side:int)->String:
	return EdgeGrid.key(c,side,BOUNDS)

# ------------------------------------------------------------------ decode --

func test_decode()->void:
	var c:=Vector2i(10,10)
	var n:=EC.decode("build_edge",c,"edge_wall|0",BOUNDS)
	expect(n.get("id")=="10,10,N" and n.kind=="edge_wall" and n.side==EdgeGrid.SIDE_N and n.midpoint==Vector2(10.5,10.0),"north decode")
	expect(n.cells.size()==2 and n.cells[0]==Vector2i(10,9) and n.cells[1]==Vector2i(10,10),"north cells")
	var e:=EC.decode("build_edge",c,"edge_door|1",BOUNDS)
	expect(e.get("id")=="11,10,W" and e.kind=="edge_door" and e.side==EdgeGrid.SIDE_W and e.midpoint==Vector2(11.0,10.5),"east is the canonical west edge of the next cell")
	expect(e.cells[0]==Vector2i(10,10) and e.cells[1]==Vector2i(11,10),"east cells")
	var s:=EC.decode("build_edge",c,"edge_window|2",BOUNDS)
	expect(s.get("id")=="10,11,N" and s.kind=="edge_window" and s.midpoint==Vector2(10.5,11.0),"south decode")
	var w:=EC.decode("build_edge",c,"edge_wall|3",BOUNDS)
	expect(w.get("id")=="10,10,W" and w.midpoint==Vector2(10.0,10.5),"west decode")
	var other:=EC.decode("build_edge",Vector2i(10,11),"edge_wall|0",BOUNDS)
	expect(other.get("id")==s.id,"the same physical edge has one id from either cell")
	var r:=EC.decode("remove_edge",c,"2",BOUNDS)
	expect(r.get("id")=="10,11,N" and r.kind=="" and r.side==EdgeGrid.SIDE_N,"remove decode has no kind")
	var t:=EC.decode("toggle_edge",c,"3",BOUNDS)
	expect(t.get("id")=="10,10,W" and t.kind=="","toggle decode has no kind")
	for bad in ["","edge_wall","edge_wall|","edge_wall|4","edge_wall|-1","edge_wall|00","edge_wall|0|","edge_wall|0|1","edge_roof|0","wall|0","EDGE_WALL|0"," edge_wall|0","edge_wall |0","edge_wall| 0","edge_wall|0 ","edge_wall|０","|0","edge_wall:0","edge_wall|N","edge_wall|0\n","edge_wall|+1","0","3"]:
		expect(EC.decode("build_edge",c,bad,BOUNDS).is_empty(),"malformed build extra '%s' decodes to {}"%bad.c_escape())
	for bad in ["","00","4","-1","+1"," 0","0 ","N","０","edge_wall|0","0|0","-","0\n"]:
		expect(EC.decode("remove_edge",c,bad,BOUNDS).is_empty(),"malformed remove extra '%s' decodes to {}"%bad.c_escape())
		expect(EC.decode("toggle_edge",c,bad,BOUNDS).is_empty(),"malformed toggle extra '%s' decodes to {}"%bad.c_escape())
	for action in ["","build","remove","door","build_edges","Build_Edge","toggle"]:
		expect(EC.decode(action,c,"edge_wall|0",BOUNDS).is_empty() and EC.decode(action,c,"0",BOUNDS).is_empty(),"unknown action '%s' decodes to {}"%action)
	for off in [Vector2i(-1,0),Vector2i(0,-1),Vector2i(80,0),Vector2i(0,60),Vector2i(80,60)]:
		expect(EC.decode("build_edge",off,"edge_wall|0",BOUNDS).is_empty(),"off-map cell %s decodes to {}"%off)
	expect(EC.decode("build_edge",Vector2i(5,5),"edge_wall|0",Vector2i(5,5)).is_empty(),"cell outside smaller bounds")
	expect(EC.decode("build_edge",Vector2i(4,4),"edge_wall|0",Vector2i(5,5)).get("id")=="4,4,N","cell inside smaller bounds")
	expect(EC.decode("build_edge",c,"edge_wall|0",Vector2i.ZERO).is_empty(),"empty bounds decode to {}")
	# Rim edges are well formed (placement rejects them separately, the save schema allows them).
	expect(EC.decode("build_edge",Vector2i(0,0),"edge_wall|0",BOUNDS).get("id")=="0,0,N","north rim")
	expect(EC.decode("build_edge",Vector2i(0,0),"edge_wall|3",BOUNDS).get("id")=="0,0,W","west rim")
	expect(EC.decode("build_edge",Vector2i(79,59),"edge_wall|2",BOUNDS).get("id")=="79,60,N","south rim")
	expect(EC.decode("build_edge",Vector2i(79,59),"edge_wall|1",BOUNDS).get("id")=="80,59,W","east rim")
	expect(EC.COSTS=={"edge_wall":{"wood":3},"edge_door":{"wood":6,"fiber":2},"edge_window":{"wood":4,"glass":1}},"plan prices")

# ------------------------------------------------------------- placement --

func test_placement_and_costs()->void:
	var w:=new_world()
	var o:=find_site(w,Vector2i(4,4))
	var t:=o+Vector2i(1,1)
	var before:=inv(w,A)
	var other_before:=inv(w,B)
	var builds:=int(w.state.players[A].builds)
	var frozen:=layers(w)
	var r:=do(w,A,"build_edge",t,"edge_wall|0")
	expect(r.ok,"wall placed: "+str(r.get("message","")))
	var id:=edge_key(t,0)
	expect(w.state.edges.get(id)=={"type":"edge_wall","owner":A},"wall row is exactly type+owner")
	var after:=inv(w,A)
	expect(int(after.wood)==int(before.wood)-3 and int(after.fiber)==int(before.fiber) and int(after.glass)==int(before.glass) and int(after.stone)==int(before.stone),"wall costs exactly 3 wood")
	expect(int(w.state.players[A].builds)==builds+1,"one build counted")
	expect(layers(w)==frozen and w.state.roofs.is_empty(),"no other layer changed")
	expect(inv(w,B)==other_before,"nobody else paid")
	# Door: closed, 6 wood + 2 fiber.
	before=inv(w,A)
	r=do(w,A,"build_edge",t,"edge_door|3")
	expect(r.ok,"door placed: "+str(r.get("message","")))
	expect(w.state.edges.get(edge_key(t,3))=={"type":"edge_door","owner":A,"open":false},"door row starts closed with exactly three keys")
	after=inv(w,A)
	expect(int(after.wood)==int(before.wood)-6 and int(after.fiber)==int(before.fiber)-2 and int(after.glass)==int(before.glass),"door costs 6 wood + 2 fiber")
	# Window: 4 wood + 1 glass, built by the other player with exactly one glass.
	w.state.players[B].inventory.glass=1
	before=inv(w,B)
	r=do(w,B,"build_edge",t,"edge_window|2")
	expect(r.ok,"window placed: "+str(r.get("message","")))
	expect(w.state.edges.get(edge_key(t,2))=={"type":"edge_window","owner":B},"window row is owned by its builder")
	after=inv(w,B)
	expect(int(after.wood)==int(before.wood)-4 and int(after.glass)==0 and int(after.fiber)==int(before.fiber),"window costs 4 wood + 1 glass")
	expect(w.state.edges.size()==3,"three rows")
	# Same physical edge from the other cell is already taken; nothing is charged.
	reject(w,A,"build_edge",t+Vector2i.DOWN,"edge_wall|0",EC.MSG_TAKEN,"duplicate through the neighbour cell")
	reject(w,A,"build_edge",t,"edge_wall|0",EC.MSG_TAKEN,"duplicate edge")
	# Materials.
	var east:=t+Vector2i.RIGHT
	w.state.players[A].inventory.wood=2
	reject(w,A,"build_edge",east,"edge_wall|0","材料不足","wall needs 3 wood")
	w.state.players[A].inventory.wood=5
	w.state.players[A].inventory.fiber=1
	reject(w,A,"build_edge",east,"edge_door|0","材料不足","door needs wood and 2 fiber")
	w.state.players[A].inventory.wood=10
	w.state.players[A].inventory.glass=0
	reject(w,A,"build_edge",east,"edge_window|0","材料不足","window needs glass")
	w.state.players[A].inventory.wood=3
	expect(do(w,A,"build_edge",east,"edge_wall|0").ok and int(w.state.players[A].inventory.wood)==0,"exactly 3 wood is enough for a wall")

func test_rejections()->void:
	var w:=new_world()
	var o:=find_site(w,Vector2i(4,4))
	var t:=o+Vector2i(1,1)
	for bad in ["edge_wall|9","edge_wall","edge_roof|0","edge_wall|01"," edge_wall|0"]:
		reject(w,A,"build_edge",t,bad,EC.MSG_BAD,"malformed '%s'"%bad)
	reject(w,A,"remove_edge",t,"edge_wall|0",EC.MSG_BAD,"remove with build extra")
	reject(w,A,"toggle_edge",t,"9",EC.MSG_BAD,"toggle with bad side")
	# Reach 3.2 from the edge MIDPOINT (not the tile centre).
	reject(w,A,"build_edge",t,"edge_wall|0",EC.MSG_REACH,"too far east",Vector2(t.x+0.5+3.6,t.y+0.0))
	reject(w,A,"build_edge",t,"edge_wall|0",EC.MSG_REACH,"too far south",Vector2(t.x+0.5,t.y+3.6))
	expect(do(w,A,"build_edge",t+Vector2i(2,0),"edge_wall|0",Vector2(t.x+2.5,t.y+3.0)).ok,"3.0 from the midpoint is within reach")
	# Rim edges touch an off-map cell.
	for rim in [[Vector2i(0,0),"edge_wall|0"],[Vector2i(0,0),"edge_wall|3"],[Vector2i(79,59),"edge_wall|1"],[Vector2i(79,59),"edge_wall|2"]]:
		reject(w,A,"build_edge",rim[0],rim[1],EC.MSG_RIM,"rim edge %s %s"%[rim[0],rim[1]])
	# Water: a land cell whose east neighbour is water.
	var shore:=Vector2i(-1,-1)
	for y in range(1,59):
		for x in range(1,78):
			var c:=Vector2i(x,y)
			if w.is_land(c) and not w.water(c) and w.water(c+Vector2i.RIGHT):
				shore=c
				break
		if shore.x>=0:break
	expect(shore.x>=0,"found a shoreline")
	if shore.x>=0:reject(w,A,"build_edge",shore,"edge_wall|1",EC.MSG_LAND,"edge into water")
	reject(w,A,"build_edge",Vector2i(0,0),"edge_wall|1",EC.MSG_LAND,"edge on ocean corner")
	# Protected public cell (the ferry-side board cell is always protected at home).
	reject(w,A,"build_edge",Vector2i(38,29),"edge_wall|0",EC.MSG_SITE,"protected cell")
	reject(w,A,"build_edge",Vector2i(38,30),"edge_wall|0",EC.MSG_SITE,"edge next to a protected cell")

func test_mill_route()->void:
	var w:=new_world()
	var o:=find_site(w,Vector2i(4,4))
	w.state.objects[World.key(o)]={"type":Industry.MILL,"owner":A,"items":{},Industry.MILL_PART:0,Industry.MILL_FACING:0}
	var front:=o+Industry.mill_front_offset(0)
	expect(Industry.is_mill_front(w.state.objects,front),"fixture: the cell in front of the entrance")
	for side in 4:reject(w,A,"build_edge",front,"edge_wall|%d"%side,EC.MSG_MILL,"edge touching the mill front side %d"%side)
	reject(w,A,"build_edge",front,"edge_door|0",EC.MSG_MILL,"even a door (placed closed)")
	expect(do(w,A,"build_edge",o+Vector2i(0,-1),"edge_wall|3").ok,"edges away from the entrance route are fine")
	w.state.objects.erase(World.key(o))
	var entrance:=o+Industry.mill_entrance_offset(0)
	expect(do(w,A,"build_edge",entrance,"edge_wall|2").ok,"place a wall before choosing the mill site")
	expect(w._mill_site_problem(o,0)==Industry.MILL_ENTRANCE_BLOCKED,"a later mill cannot face into an existing wall")

func test_authorization()->void:
	var w:=new_world()
	var o:=find_site(w,Vector2i(4,4))
	# Public plot: denied without authorization with the shared message.
	w.public_build_access=func(token:String)->bool:return token==A
	var plot:=Vector2i(World.PUBLIC_BUILD_PLOT.position)+Vector2i(1,0)
	reject(w,B,"build_edge",plot,"edge_wall|3",World.PUBLIC_BUILD_DENIED,"unauthorized public plot")
	reject(w,B,"build_edge",plot+Vector2i(0,-1),"edge_wall|2",World.PUBLIC_BUILD_DENIED,"unauthorized: only the outer cell is in the plot")
	w.public_build_access=func(token:String)->bool:return false
	reject(w,A,"build_edge",plot,"edge_wall|3",World.PUBLIC_BUILD_DENIED,"public plot closed for everyone")
	# Foreign floor: legacy and island floors allow placement (same as the normal wall), owner-only floors do not.
	var f:=o+Vector2i(2,2)
	expect(do(w,B,"build",f,"floor").ok,"B lays a floor")
	var k:=World.key(f)
	w.state.ground[k].placement_access="owner"
	reject(w,A,"build_edge",f,"edge_wall|0",EC.PLOT_PERMISSIONS.MSG_PRIVATE_FLOOR,"owner-only foreign floor (north edge)")
	reject(w,A,"build_edge",f+Vector2i.UP,"edge_wall|2",EC.PLOT_PERMISSIONS.MSG_PRIVATE_FLOOR,"the same edge from the neighbour cell")
	expect(do(w,B,"build_edge",f,"edge_wall|0").ok,"the floor owner may build")
	w.state.ground[k].placement_access="island"
	expect(do(w,A,"build_edge",f,"edge_wall|1").ok,"island-open floor accepts a neighbour")
	w.state.ground[k].erase("placement_access")
	expect(do(w,A,"build_edge",f,"edge_wall|2").ok,"legacy floor behaves like a normal wall")

func test_foot_and_doors()->void:
	var w:=new_world()
	var o:=find_site(w,Vector2i(4,4))
	var t:=o+Vector2i(1,1)
	var line_mid:=Vector2(t.x,t.y+0.5)
	# An active player straddling the exact segment blocks placement.
	reject(w,A,"build_edge",t,"edge_wall|3","站在","active player on the wall line",null,{B:line_mid})
	reject(w,A,"build_edge",t,"edge_window|3","站在","active player on the window line",null,{B:line_mid})
	reject(w,A,"build_edge",t,"edge_door|3","站在","active player on the door line",null,{B:line_mid})
	# Another segment of the same grid line does not block (foot only overlaps the next segment).
	expect(do(w,A,"build_edge",t,"edge_wall|3",null,{B:Vector2(t.x,t.y+1.5)}).ok,"standing on a different segment of the line is fine")
	var door:=t+Vector2i(0,1)
	expect(do(w,A,"build_edge",door,"edge_door|3",null,{B:Vector2(door.x-0.5,door.y+0.5)}).ok,"standing next to the line is fine")
	var door_id:=edge_key(door,3)
	# Inactive players never block.
	var other:=t+Vector2i(0,2)
	w.active_tokens.erase(B)
	expect(do(w,A,"build_edge",other,"edge_wall|3",null,{B:Vector2(other.x,other.y+0.5)}).ok,"an inactive player on the line does not block")
	w.active_tokens[B]=true
	# Closed door blocks movement; any ordinary player can open it; open door lets people through.
	pose(w,B,Vector2(door.x-0.5,door.y+0.5))
	w.move_player(B,Vector2.RIGHT,1.0/3.6)
	expect(is_equal_approx(float(w.state.players[B].x),door.x-0.5),"closed door blocks the walker")
	var r:=do(w,B,"toggle_edge",door,"3")
	expect(r.ok and w.state.edges[door_id].open==true and w.state.edges[door_id].owner==A,"B opens A's door and the owner stays A: "+str(r.get("message","")))
	pose(w,B,Vector2(door.x-0.5,door.y+0.5))
	w.move_player(B,Vector2.RIGHT,1.0/3.6)
	expect(is_equal_approx(float(w.state.players[B].x),door.x+0.5),"open door lets the walker through")
	# Closing with an active player on the line is refused and changes nothing.
	reject(w,A,"toggle_edge",door,"3","站在","closing on a person",null,{B:Vector2(door.x,door.y+0.5)})
	expect(w.state.edges[door_id].open==true,"door stays open")
	# A person next to the line does not prevent closing; an inactive one on the line does not either.
	r=do(w,A,"toggle_edge",door,"3",null,{B:Vector2(door.x+0.5,door.y+0.5)})
	expect(r.ok and w.state.edges[door_id].open==false,"door closes with nobody on the line")
	expect(do(w,A,"toggle_edge",door,"3").ok and w.state.edges[door_id].open==true,"door opens again")
	w.active_tokens.erase(B)
	expect(do(w,A,"toggle_edge",door,"3",null,{B:Vector2(door.x,door.y+0.5)}).ok and w.state.edges[door_id].open==false,"an inactive person on the line does not block closing")
	w.active_tokens[B]=true
	# Toggle guards.
	reject(w,A,"toggle_edge",t,"3",EC.MSG_NOT_DOOR,"a wall is not a door")
	reject(w,A,"toggle_edge",t,"0",EC.MSG_NONE,"nothing there")
	reject(w,A,"toggle_edge",door,"3",EC.MSG_REACH,"door out of reach",Vector2(door.x+5.0,door.y+0.5))

func test_remove_and_caps()->void:
	var w:=new_world()
	var o:=find_site(w,Vector2i(4,4))
	var t:=o+Vector2i(1,1)
	var start:=inv(w,A)
	var builds:=int(w.state.players[A].builds)
	expect(do(w,A,"build_edge",t,"edge_wall|0").ok,"wall placed")
	expect(do(w,A,"build_edge",t,"edge_door|1").ok,"door placed")
	expect(do(w,A,"build_edge",t,"edge_window|2").ok,"window placed")
	var placed_builds:=int(w.state.players[A].builds)
	expect(placed_builds==builds+3,"three builds")
	reject(w,B,"remove_edge",t,"0",EC.MSG_OWNER,"only the owner removes")
	reject(w,A,"remove_edge",t,"3",EC.MSG_NONE,"nothing to remove")
	reject(w,A,"remove_edge",t,"0",EC.MSG_REACH,"remove out of reach",Vector2(t.x+9.5,t.y+0.5))
	for spec in [[0,"edge_wall"],[1,"edge_door"],[2,"edge_window"]]:
		expect(do(w,A,"remove_edge",t,str(spec[0])).ok,"remove %s"%spec[1])
		expect(not w.state.edges.has(edge_key(t,spec[0])),"%s row is gone"%spec[1])
	expect(inv(w,A)==start,"exact refund of every price")
	expect(int(w.state.players[A].builds)==placed_builds,"removing does not touch the build counter")
	# Refund cap: nothing is partially refunded.
	expect(do(w,A,"build_edge",t,"edge_door|0").ok,"door for the cap test")
	w.state.players[A].inventory.fiber=CAP-1
	reject(w,A,"remove_edge",t,"0",EC.MSG_FULL,"refund would pass the item cap (fiber)")
	expect(w.state.edges.has(edge_key(t,0)) and int(w.state.players[A].inventory.fiber)==CAP-1,"edge and backpack untouched")
	w.state.players[A].inventory.fiber=CAP-2
	var wood:=int(w.state.players[A].inventory.wood)
	expect(do(w,A,"remove_edge",t,"0").ok and int(w.state.players[A].inventory.fiber)==CAP and int(w.state.players[A].inventory.wood)==wood+6,"refund lands exactly on the cap")
	# Build counter cap.
	w.state.players[A].builds=CAP
	reject(w,A,"build_edge",t,"edge_wall|0",EC.MSG_BUILDS,"build counter at its cap")
	w.state.players[A].builds=CAP-1
	expect(do(w,A,"build_edge",t,"edge_wall|0").ok and int(w.state.players[A].builds)==CAP,"last allowed build reaches the cap")
	# A guest cannot remove a non-owner's edge even though they can toggle doors.
	expect(do(w,B,"build_edge",t+Vector2i.RIGHT,"edge_door|0").ok,"B builds a door")
	reject(w,A,"remove_edge",t+Vector2i.RIGHT,"0",EC.MSG_OWNER,"A cannot remove B's door")
	expect(do(w,A,"toggle_edge",t+Vector2i.RIGHT,"0").ok,"but A can open B's door")

func test_snapshot()->void:
	var w:=new_world()
	var o:=find_site(w,Vector2i(4,4))
	var t:=o+Vector2i(1,1)
	expect(do(w,A,"build_edge",t,"edge_wall|0").ok and do(w,A,"build_edge",t,"edge_door|3").ok and do(w,B,"build_edge",t,"edge_window|2").ok,"three edges")
	var session:=Session.new()
	session.world=w
	var public:=A.sha256_text().left(16)
	var view:Dictionary=session.public_state(HOME,B).edges
	expect(view.size()==3,"snapshot lists all three edges")
	expect(view[edge_key(t,0)]=={"type":"edge_wall","owner":public},"wall in snapshot with public owner id")
	expect(view[edge_key(t,3)]=={"type":"edge_door","owner":public,"open":false},"closed door in snapshot")
	expect(view[edge_key(t,2)]=={"type":"edge_window","owner":B.sha256_text().left(16)},"window in snapshot")
	expect(not var_to_str(view).contains(A) and not var_to_str(view).contains(B),"no raw tokens leak")
	expect(do(w,B,"toggle_edge",t,"3").ok,"toggle")
	expect(session.public_state(HOME,A).edges[edge_key(t,3)].open==true,"snapshot shows the door open")
	expect(do(w,A,"remove_edge",t,"0").ok and not session.public_state(HOME,A).edges.has(edge_key(t,0)),"snapshot drops a removed edge")
	expect(w.state.edges[edge_key(t,3)].owner==A,"building the snapshot never rewrites stored owners")
	session.free()

func test_auto_roof()->void:
	var w:=new_world()
	var o:=find_site(w,Vector2i(4,4))
	var first:=o+Vector2i(1,1)
	var interior:Array[Vector2i]=[first,first+Vector2i.RIGHT,first+Vector2i.DOWN,first+Vector2i.ONE]
	for c in interior:expect(do(w,A,"build",c,"floor").ok,"floor %s"%c)
	var boundary:Array=[]
	for c in interior:
		for side in 4:
			if EdgeGrid.neighbor(c,side) not in interior:boundary.append([c,side])
	expect(boundary.size()==8,"2x2 room has eight boundary edges")
	var door_spec:Array=[first,3]
	for spec in boundary:
		if spec[0]==door_spec[0] and spec[1]==door_spec[1]:continue
		var r:=do(w,A,"build_edge",spec[0],"edge_wall|%d"%spec[1])
		expect(r.ok,"wall %s: %s"%[spec,str(r.get("message",""))])
		expect(not r.has("roof_add_count"),"no roof while the room has no door")
	expect(auto_count(w)==0,"seven walls and no door: no roof")
	var before_door:=inv(w,A)
	var built:=do(w,A,"build_edge",first,"edge_door|3")
	expect(built.ok,"door closes the room: "+str(built.get("message","")))
	expect(auto_count(w)==4 and int(built.get("roof_add_count",0))==4,"sealed room gets four automatic roofs")
	for c in interior:expect(w.state.roofs.get(World.key(c),{}).get("owner")==A,"roof owner at %s"%c)
	var copied:=World.BLUEPRINT_DESIGN.capture(w.state,A,Rect2i(first,Vector2i(2,2)),"外緣小屋",World.BUILD,World.NAMES)
	expect(copied.ok and copied.blueprint.version==2 and copied.blueprint.pieces.size()==12 and copied.auto_roofs_omitted==4,"capture keeps all eight edges and four floors; automatic roofs are rebuilt")
	var building_undo:=w.undo_summary(A)
	expect(building_undo.available,"door construction has an undo record")
	if building_undo.available:
		expect(do(w,A,World.UNDO_ACTION,first,building_undo.id).ok and auto_count(w)==0 and inv(w,A)==before_door,"undo reverses both the door and the exact roof cost")
		expect(do(w,A,"build_edge",first,"edge_door|3").ok and auto_count(w)==4,"the room can be built again")
	# Toggling the door changes movement only: roofs stay.
	var toggled:=do(w,B,"toggle_edge",first,"3")
	expect(toggled.ok and auto_count(w)==4 and not toggled.has("roof_add_count") and not toggled.has("roof_remove_count"),"opening the door keeps the roofs")
	expect(do(w,B,"toggle_edge",first,"3").ok and auto_count(w)==4,"closing keeps the roofs")
	# Removing the door opens the room: roofs and door are refunded, back to the exact pre-door inventory.
	var removed:=do(w,A,"remove_edge",first,"3")
	expect(removed.ok,"door removed: "+str(removed.get("message","")))
	expect(auto_count(w)==0 and int(removed.get("roof_remove_count",0))==4,"automatic roofs disappear with the door")
	expect(inv(w,A)==before_door,"door and roofs refunded exactly")
	expect(w.state.roofs.is_empty(),"no roof left behind")
	var reopened:=World.new()
	expect(reopened.load_world(w.save_path),"load a persisted edge removal and its history")
	var undo:=reopened.undo_summary(A)
	expect(undo.available,"edge removal can still be undone after loading")
	if undo.available:
		expect(do(reopened,A,World.UNDO_ACTION,first,undo.id).ok and auto_count(reopened)==4 and reopened.state.edges.has(EdgeGrid.key(first,3)),"persisted undo restores the closed door and the roof")
	var destination:=o+Vector2i(4,1)
	if copied.ok:verify_build_from_blueprint(w,copied.blueprint,destination,before_door)
	verify_blueprint_with_attachment(w,first,destination)

func verify_build_from_blueprint(w:World,design:Dictionary,destination:Vector2i,source_inventory:Dictionary)->void:
	pose(w,A,centre(destination)+Vector2(0,-1))
	var before:=w.state.duplicate(true)
	var quoted:=w.quote_blueprint(A,design,destination,1)
	if not quoted.ok:
		expect(false,"rotated blueprint has a valid quote: "+str(quoted))
		return
	expect(w.state==before and quoted.roof_add==4 and quoted.undoable,"quote is read-only and prices the automatic roof")
	var nonce:="efd66ce94c7942769f17722a7a82abc0"
	var built:=w.apply_blueprint(A,nonce,design,destination,1,quoted.hash)
	expect(built.ok and built.pieces==12 and auto_count(w)==4,"rotated blueprint builds all floors and edges with one roof settlement")
	var rotated_door:=EdgeGrid.key(destination+Vector2i.RIGHT,0)
	expect(w.state.edges.get(rotated_door,{}).get("type")=="edge_door","west door becomes a north door after clockwise rotation")
	expect(w.state.edges.get(rotated_door,{}).get("open")==false,"copied doors start closed")
	var after:=w.state.duplicate(true)
	expect(w.apply_blueprint(A,nonce,design,destination,1,quoted.hash)==built and w.state==after,"replayed blueprint charges once")
	var history:=w.undo_summary(A)
	expect(history.available and w.state.construction.last[A].action=="edge_blueprint","whole edge blueprint gets one undo record")
	if history.available:
		expect(do(w,A,World.UNDO_ACTION,destination,history.id).ok and not w.state.edges.has(rotated_door) and auto_count(w)==0,"undo restores edge, floor and roof layers")
		expect(inv(w,A)==source_inventory,"undo refunds the full blueprint cost")

func verify_blueprint_with_attachment(w:World,source:Vector2i,destination:Vector2i)->void:
	var sign:=World.WALL_FIXTURES.HOME_SIGN
	if not do(w,A,"build",source,sign).ok:
		expect(false,"build a sign on an existing north-edge wall")
		return
	var copied:=World.BLUEPRINT_DESIGN.capture(w.state,A,Rect2i(source,Vector2i(2,2)),"門牌小屋",World.BUILD,World.NAMES)
	if not copied.ok:
		expect(false,"capture keeps the mounted sign and its edge: "+str(copied))
		return
	pose(w,A,centre(destination)+Vector2(0,-1))
	var quote:=w.quote_blueprint(A,copied.blueprint,destination)
	if not quote.ok:
		expect(false,"staging places supporting edges before fixtures: "+str(quote))
		return
	var built:=w.apply_blueprint(A,"7ab135c5a0114dada1a8ba269fa40308",copied.blueprint,destination,0,quote.hash)
	var loaded:=World.new()
	expect(built.ok and loaded.load_world(w.save_path) and loaded.state.objects.get(World.key(destination),{}).get("type")==sign,"the supporting edge and copied sign survive an actual save")
	if built.ok:
		expect(not do(w,A,"remove_edge",destination,"0").ok,"the copied sign still protects its supporting edge")
		var undo:=w.undo_summary(A)
		expect(undo.available and do(w,A,World.UNDO_ACTION,destination,undo.id).ok,"undo removes the copied fixture and edge together")

func test_sprinkler_edges()->void:
	var w:=new_world()
	var origin:=Vector2i(37,38)
	var across:=origin+Vector2i.RIGHT
	var corner:=across+Vector2i.DOWN
	w.state.objects[World.key(origin)]={"type":"medium_sprinkler","owner":A,"enabled":true,"water":5,"next_water":0,"sprinkler_daily":true}
	for tile in [across,corner]:
		w.state.crops[World.key(tile)]={"kind":"radish","owner":A,"wet":false}
	var line:=EdgeGrid.key(origin,1)
	w.state.edges[line]={"type":"edge_door","owner":A,"open":false}
	expect(w.pending_sprinklers(0,{}).get(World.key(origin),[]).is_empty(),"closed edge blocks daily sprinkler rays including diagonals")
	w.state.edges[line].open=true
	var targets:Array=w.pending_sprinklers(0,{})[World.key(origin)]
	expect(World.key(across) in targets and World.key(corner) in targets,"open door lets sprinkler water through")
	w.state.edges[EdgeGrid.key(across,2)]={"type":"edge_window","owner":A}
	targets=w.pending_sprinklers(0,{})[World.key(origin)]
	expect(World.key(across) in targets and World.key(corner) not in targets,"window at the far side of a corner blocks the diagonal only")

# --------------------------------------------------------------------- run --

func run()->void:
	dir="user://test-edge-construction-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	expect(DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated test directory")
	test_decode()
	test_placement_and_costs()
	test_rejections()
	test_mill_route()
	test_authorization()
	test_foot_and_doors()
	test_remove_and_caps()
	test_snapshot()
	test_auto_roof()
	test_sprinkler_edges()
	for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir+"/"+f)
	DirAccess.remove_absolute(dir)
	print("EDGE_CONSTRUCTION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
