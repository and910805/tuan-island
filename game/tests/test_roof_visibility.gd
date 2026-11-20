extends SceneTree
## Roof see-through contract for res://scripts/roof_visibility.gd
##   static func faded(snapshot:Dictionary, player_id:String) -> Dictionary  (roof tile key => true)
##
## Geometry is derived from the real draw code (verified below against source text):
##   world_view.gd     const TILE:=32.0; roof_sprite draws Rect2(at+Vector2(0,-8),Vector2(32,32)),
##                     at = tile*TILE - camera  -> roof (rx,ry) covers world px [32rx,32rx+32) x [32ry-8,32ry+24)
##   world_view.gd     players drawn at screen(visual_position).round() (feet = position*TILE)
##   character_sprite_art.gd  frame drawn at foot.round()-FOOT, size FRAME_SIZE; body = union of
##                     the farmer frames' opaque used_rect (fallback: world_pixel_art.person farmer extents)
##   world.gd can_stand foot box +-0.22 x, +-0.17 y; walls/closed doors block; walls may stand on floor,
##                     roofs need own floor, so a roof may legally cover a wall cell.

const World=preload("res://scripts/world.gd")
const CharArt=preload("res://scripts/character_sprite_art.gd")
const ROOF_PATH:="res://scripts/roof_visibility.gd"
const TILE:=32.0
const ROOF_OFFSET:=Vector2(0,-8)
const ROOF_SIZE:=Vector2(32,32)
const FOOT_BOX:=[Vector2(-0.22,-0.17),Vector2(0.22,-0.17),Vector2(-0.22,0.17),Vector2(0.22,0.17)]
# world_pixel_art.person, farmer style, worst case over facing (head shifts +-2) and walk lift (1px).
const FALLBACK_BODY:=Rect2(-14,-38,28,43)

var checks:=0
var failures:=0
var Roof:GDScript
var body:=FALLBACK_BODY

func _initialize() -> void:
	call_deferred("run")

func expect(condition:bool,description:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL "+description)

static func k(p:Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

# ---------- geometry from draw code ----------

func derive_body() -> void:
	var art:=CharArt.new()
	if not art.setup():
		print("ROOF_VISIBILITY note: character atlas unavailable, using world_pixel_art fallback body")
		return
	var sheet:=art.atlas.get_image()
	var union:=Rect2i()
	var first:=true
	for row in range(4):
		for column in range(3): # farmer idle + both strides, every facing row
			var used:=sheet.get_region(Rect2i(Vector2i(column,row)*CharArt.FRAME_SIZE,CharArt.FRAME_SIZE)).get_used_rect()
			if not used.has_area():continue
			union=used if first else union.merge(used)
			first=false
	if not first:
		body=Rect2(Vector2(union.position-CharArt.FOOT),Vector2(union.size))

func body_rect(feet:Vector2) -> Rect2:
	var foot:=(feet*TILE).round()
	return Rect2(foot+body.position,body.size)

func roof_rect(cell:Vector2i) -> Rect2:
	return Rect2(Vector2(cell)*TILE+ROOF_OFFSET,ROOF_SIZE)

func hides(cell:Vector2i,feet:Vector2) -> bool:
	return roof_rect(cell).intersects(body_rect(feet))

func standable(s:Dictionary,feet:Vector2) -> bool:
	for offset in FOOT_BOX:
		var v:Vector2=feet+offset
		var o=s.get("objects",{}).get(k(Vector2i(floori(v.x),floori(v.y))))
		if o is Dictionary:
			if o.get("type","")=="door" and o.get("open",false):continue
			if o.get("type","") in ["wall","window","door","bed"]:return false
	return true

# ---------- fixtures (all legal per world.gd build rules) ----------

func floor_at(s:Dictionary,p:Vector2i,owner:="alice") -> void:
	s.ground[k(p)]={"type":"floor","owner":owner,"items":{}}

func roof_at(s:Dictionary,p:Vector2i,owner:="alice") -> void:
	s.roofs[k(p)]={"type":"roof","owner":owner,"items":{}}

func obj_at(s:Dictionary,p:Vector2i,kind:String,owner:="alice") -> void:
	var o:={"type":kind,"owner":owner,"items":{}}
	if kind=="door":o.open=false
	s.objects[k(p)]=o

# Two rooms sharing a divider wall. Floor + roof over EVERY cell (walls included), so roofs
# form one continuous sheet and only the walls separate the rooms.
#   x 10..20, y 10..15; outer walls on the border, divider at x=15.
#   Room A interior x11..14 y11..14, door (12,15). Room B interior x16..19 y11..14, door (17,15).
func duplex(o:=Vector2i.ZERO) -> Dictionary:
	var s:={"region_id":"home","ground":{},"objects":{},"roofs":{},"crops":{},"players":{}}
	for y in range(10,16):
		for x in range(10,21):
			var p:=Vector2i(x,y)+o
			floor_at(s,p)
			roof_at(s,p)
			if x==10 or x==20 or x==15 or y==10 or y==15:obj_at(s,p,"wall")
	obj_at(s,Vector2i(12,15)+o,"door")
	obj_at(s,Vector2i(17,15)+o,"door")
	obj_at(s,Vector2i(14,11)+o,"bed")
	obj_at(s,Vector2i(19,11)+o,"bed")
	# Open-sided roof terrace (floor + roof, no walls) well east of the duplex.
	for y in range(10,13):
		for x in range(30,33):
			floor_at(s,Vector2i(x,y)+o)
			roof_at(s,Vector2i(x,y)+o)
	return s

func cells(from:Vector2i,to:Vector2i,o:=Vector2i.ZERO) -> Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for y in range(from.y,to.y+1):
		for x in range(from.x,to.x+1):out.append(Vector2i(x,y)+o)
	return out

func place(s:Dictionary,id:String,feet:Vector2,region:="home") -> void:
	s.players[id]={"name":id,"region":region,"x":feet.x,"y":feet.y,"inventory":{}}

func call_faded(s,id) -> Dictionary:
	var r=Roof.call("faded",s,id)
	expect(r is Dictionary,"faded returns a Dictionary for player '%s'"%str(id))
	return r if r is Dictionary else {}

func well_formed(r:Dictionary,s:Dictionary,label:String) -> void:
	var ok:=true
	for key in r:
		if not (key is String) or not s.get("roofs",{}).has(key) or r[key]!=true:ok=false
	expect(ok,label+": every faded key is an existing roof key mapped to true")

func all_in(r:Dictionary,list:Array[Vector2i]) -> bool:
	for c in list:
		if not r.has(k(c)):return false
	return true

func none_in(r:Dictionary,list:Array[Vector2i]) -> bool:
	for c in list:
		if r.has(k(c)):return false
	return true

# ---------- run ----------

func run() -> void:
	source_contract()
	derive_body()
	print("ROOF_VISIBILITY body rect relative to feet: %s"%body)
	if not ResourceLoader.exists(ROOF_PATH):
		expect(false,"roof_visibility.gd exists at "+ROOF_PATH)
		finish()
		return
	Roof=load(ROOF_PATH)
	expect(Roof!=null,"roof_visibility.gd loads")
	if Roof==null:
		finish()
		return
	safety()
	for o in [Vector2i.ZERO,Vector2i(37,23),Vector2i(-6,41)]:
		indoor_rooms(o)
		south_of_roof(o)
		not_overlapping(o)
		terrace(o)
	translation_equivalence()
	local_player_only()
	interpolated_player()
	region_isolation()
	finish()

func finish() -> void:
	print("ROOF_VISIBILITY checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func source_contract() -> void:
	var view:=FileAccess.get_file_as_string("res://scripts/world_view.gd")
	expect(view.contains("const TILE:=32.0"),"world_view TILE is still 32 (fixture geometry)")
	var sprite_at:=view.find("func roof_sprite(")
	# 620: the thatch rect now follows the terracotta, Xinghe and glass branches (C16 added the first).
	var sprite_body:=view.substr(sprite_at,620) if sprite_at>=0 else ""
	expect(sprite_body.contains("draw_rect(Rect2(at+Vector2(0,-8),Vector2(32,32))"),"roof_sprite still covers at+(0,-8) size 32x32 (fixture geometry)")
	expect(view.contains("var at:=screen(visual_position).round()"),"players still drawn with feet at screen(position).round()")
	expect(CharArt.FOOT==Vector2i(24,44) and CharArt.FRAME_SIZE==Vector2i(48,48),"character frame anchored at FOOT (24,44) in 48x48")
	expect(view.contains("roof_visibility"),"world_view integrates roof_visibility.gd")

func safety() -> void:
	var s:=duplex()
	place(s,"alice",Vector2(12.5,12.5))
	expect(call_faded(s,"ghost").is_empty(),"unknown player fades nothing")
	expect(call_faded(s,"").is_empty(),"empty player id fades nothing")
	expect(call_faded({},"alice").is_empty(),"empty snapshot fades nothing")
	var no_players:=s.duplicate(true);no_players.erase("players")
	expect(call_faded(no_players,"alice").is_empty(),"snapshot without players fades nothing")
	var no_roofs:=s.duplicate(true);no_roofs.erase("roofs")
	expect(call_faded(no_roofs,"alice").is_empty(),"snapshot without roofs fades nothing")
	var no_layers:={"players":s.players.duplicate(true),"roofs":s.roofs.duplicate(true)}
	well_formed(call_faded(no_layers,"alice"),no_layers,"snapshot without ground/objects is safe")
	var no_xy:=s.duplicate(true);no_xy.players.alice={"name":"alice","region":"home"}
	expect(call_faded(no_xy,"alice").is_empty(),"player without position fades nothing")
	# Snapshot must not be mutated by any query.
	var probe:=duplex()
	place(probe,"alice",Vector2(12.5,12.5))
	place(probe,"bob",Vector2(12.5,16.2))
	var before:=probe.duplicate(true)
	for id in ["alice","bob","ghost",""]:call_faded(probe,id)
	expect(probe==before,"faded never mutates the snapshot")
	# Deterministic: same input, same output.
	expect(call_faded(probe,"bob")==call_faded(probe,"bob"),"repeated queries give identical results")

func indoor_rooms(o:Vector2i) -> void:
	var tag:=" @%s"%o
	var room_a:=cells(Vector2i(11,11),Vector2i(14,14),o)
	var room_b:=cells(Vector2i(16,11),Vector2i(19,14),o)
	var s:=duplex(o)
	# Standing in the middle of room A.
	var mid:=Vector2(12.5,12.5)+Vector2(o)
	expect(standable(s,mid),"fixture: room A centre is standable"+tag)
	place(s,"alice",mid)
	var r:=call_faded(s,"alice")
	well_formed(r,s,"indoor A"+tag)
	expect(all_in(r,room_a),"indoors fades the whole enclosed room A, corners included"+tag)
	expect(none_in(r,room_b),"divider wall keeps adjacent room B opaque"+tag)
	expect(none_in(r,cells(Vector2i(30,10),Vector2i(32,12),o)),"unrelated terrace stays opaque while indoors"+tag)
	# Hugging the divider wall from inside A: body still never reaches B's interior pixels.
	var hug:=Vector2(14.7,12.5)+Vector2(o)
	expect(standable(s,hug),"fixture: east edge of room A is standable"+tag)
	var hug_hits_b:=false
	for c in room_b:hug_hits_b=hug_hits_b or hides(c,hug)
	expect(not hug_hits_b,"fixture: body against divider does not overlap room B roofs"+tag)
	place(s,"alice",hug)
	r=call_faded(s,"alice")
	expect(all_in(r,room_a) and none_in(r,room_b),"against the divider: A faded, B opaque (walls stop spill)"+tag)
	# Standing in room B mirrors it.
	var in_b:=Vector2(17.5,13.5)+Vector2(o)
	expect(standable(s,in_b),"fixture: room B is standable"+tag)
	place(s,"alice",in_b)
	r=call_faded(s,"alice")
	expect(all_in(r,room_b) and none_in(r,room_a),"indoors in B fades B, not A"+tag)

func south_of_roof(o:Vector2i) -> void:
	var tag:=" @%s"%o
	var s:=duplex(o)
	# Feet outside, just below the roofed south wall of room A.
	var feet:=Vector2(12.5,16.2)+Vector2(o)
	var foot_cell:=Vector2i(feet.floor())
	expect(standable(s,feet),"fixture: just south of the wall is standable"+tag)
	expect(not s.roofs.has(k(foot_cell)),"fixture: feet are outside any roof"+tag)
	var hiding:=Vector2i(12,15)+o
	expect(hides(hiding,feet),"fixture: roof over the south wall overlaps the body"+tag)
	place(s,"alice",feet)
	var r:=call_faded(s,"alice")
	well_formed(r,s,"south of A"+tag)
	var all_hiding_faded:=true
	for key in s.roofs:
		if hides(World.cell(key),feet) and not r.has(key):all_hiding_faded=false
	expect(r.has(k(hiding)) and all_hiding_faded,"every roof drawn over the body fades even with feet outside"+tag)
	expect(none_in(r,cells(Vector2i(16,11),Vector2i(19,14),o)),"room B interior stays opaque when body is behind A"+tag)
	var far_b:=Vector2i(19,15)+o
	expect(not hides(far_b,feet) and not r.has(k(far_b)),"B's south-wall roof, not over the body, stays opaque (no spill along wall row)"+tag)

func not_overlapping(o:Vector2i) -> void:
	var tag:=" @%s"%o
	var s:=duplex(o)
	# Two rows further south: body top is below the roof's bottom edge.
	var far:=Vector2(12.5,17.6)+Vector2(o)
	var any:=false
	for key in s.roofs:any=any or hides(World.cell(key),far)
	expect(not any,"fixture: body two rows south overlaps no roof"+tag)
	place(s,"alice",far)
	expect(call_faded(s,"alice").is_empty(),"roof not overlapping the body stays opaque (south)"+tag)
	# North of the house: the roof is south of the body and does not cover it.
	var north:=Vector2(12.5,9.55)+Vector2(o)
	any=false
	for key in s.roofs:any=any or hides(World.cell(key),north)
	expect(standable(s,north) and not any,"fixture: body just north of the house overlaps no roof"+tag)
	place(s,"alice",north)
	expect(call_faded(s,"alice").is_empty(),"roof not overlapping the body stays opaque (north)"+tag)
	# Ring-walled house whose walls carry no roof: standing south of the wall is not hidden.
	var ring:={"region_id":"home","ground":{},"objects":{},"roofs":{},"players":{}}
	for y in range(9,15):
		for x in range(9,15):
			var p:=Vector2i(x,y)+o
			if x==9 or x==14 or y==9 or y==14:obj_at(ring,p,"wall")
			else:
				floor_at(ring,p)
				roof_at(ring,p)
	obj_at(ring,Vector2i(11,14)+o,"door")
	var below:=Vector2(11.5,15.2)+Vector2(o)
	any=false
	for key in ring.roofs:any=any or hides(World.cell(key),below)
	expect(standable(ring,below) and not any,"fixture: below an unroofed wall the body overlaps no roof"+tag)
	place(ring,"alice",below)
	expect(call_faded(ring,"alice").is_empty(),"unroofed south wall: roofs stay opaque"+tag)
	place(ring,"alice",Vector2(11.5,11.5)+Vector2(o))
	expect(all_in(call_faded(ring,"alice"),cells(Vector2i(10,10),Vector2i(13,13),o)),"ring house: indoors fades its interior roof"+tag)

func terrace(o:Vector2i) -> void:
	var tag:=" @%s"%o
	var deck:=cells(Vector2i(30,10),Vector2i(32,12),o)
	var s:=duplex(o)
	place(s,"alice",Vector2(31.5,11.5)+Vector2(o))
	var r:=call_faded(s,"alice")
	well_formed(r,s,"terrace"+tag)
	expect(all_in(r,deck),"standing under an open terrace fades the whole terrace roof"+tag)
	expect(none_in(r,cells(Vector2i(11,11),Vector2i(19,14),o)),"terrace does not fade the house"+tag)
	var feet:=Vector2(31.5,13.2)+Vector2(o)
	var hiding:=Vector2i(31,12)+o
	expect(not s.roofs.has(k(Vector2i(feet.floor()))) and hides(hiding,feet),"fixture: just south of terrace, body overlaps its front roof row"+tag)
	place(s,"alice",feet)
	r=call_faded(s,"alice")
	expect(r.has(k(hiding)),"terrace roof drawn over the body fades with feet outside"+tag)
	place(s,"alice",Vector2(31.5,14.6)+Vector2(o))
	expect(call_faded(s,"alice").is_empty(),"terrace roof clear of the body stays opaque"+tag)

func translation_equivalence() -> void:
	var spots:=[Vector2(12.5,12.5),Vector2(14.7,12.5),Vector2(17.5,13.5),Vector2(12.5,16.2),Vector2(12.5,17.6),Vector2(12.5,9.55),Vector2(31.5,11.5),Vector2(31.5,13.2),Vector2(25.5,12.5)]
	for o in [Vector2i(37,23),Vector2i(-6,41),Vector2i(5,-3)]:
		var same:=true
		for spot in spots:
			var base:=duplex()
			place(base,"alice",spot)
			var moved:=duplex(o)
			place(moved,"alice",spot+Vector2(o))
			var expected:={}
			for key in call_faded(base,"alice"):expected[k(World.cell(key)+o)]=true
			if call_faded(moved,"alice")!=expected:same=false
		expect(same,"translating world and player by %s translates the faded set exactly"%o)

func local_player_only() -> void:
	var s:=duplex()
	place(s,"alice",Vector2(12.5,9.55)) # outside, unhidden
	place(s,"bob",Vector2(12.5,12.5))   # inside room A
	place(s,"cara",Vector2(17.5,13.5))  # inside room B
	var r:=call_faded(s,"alice")
	expect(r.is_empty(),"other players indoors do not fade roofs for the local player")
	var rb:=call_faded(s,"bob")
	expect(all_in(rb,cells(Vector2i(11,11),Vector2i(14,14))) and none_in(rb,cells(Vector2i(16,11),Vector2i(19,14))),"bob's view fades only bob's room")
	var rc:=call_faded(s,"cara")
	expect(all_in(rc,cells(Vector2i(16,11),Vector2i(19,14))) and none_in(rc,cells(Vector2i(11,11),Vector2i(14,14))),"cara's view fades only cara's room")
	var solo:=duplex()
	place(solo,"bob",Vector2(12.5,12.5))
	expect(call_faded(solo,"bob")==rb,"presence of other players does not change the local result")

func interpolated_player() -> void:
	var s:=duplex()
	place(s,"alice",Vector2(12.5,17.6))
	var r:Dictionary=Roof.faded(s,"alice",Vector2(12.5,12.5))
	expect(all_in(r,cells(Vector2i(11,11),Vector2i(14,14))),"rendered player still inside: keep room visible despite outside snapshot")
	expect(none_in(r,cells(Vector2i(16,11),Vector2i(19,14))),"interpolation never reveals unrelated room")
	place(s,"alice",Vector2(12.5,12.5))
	expect(Roof.faded(s,"alice",Vector2(12.5,17.6)).is_empty(),"rendered player still outside: do not reveal room early")

func region_isolation() -> void:
	var world:=World.new()
	var home:=duplex()
	for field in ["ground","objects","roofs"]:
		world.state[field]=home[field].duplicate(true)
	# Lanyang has its own roofed shed at the same coordinates as home room A.
	var lanyang:Dictionary=world.state.regions[World.REGIONS.LANYANG]
	lanyang.ground={};lanyang.objects={};lanyang.roofs={}
	var shed:=cells(Vector2i(12,12),Vector2i(13,13))
	for c in shed:
		floor_at(lanyang,c)
		roof_at(lanyang,c)
	world.state.players.alice={"name":"alice","region":"home","x":12.5,"y":12.5,"inventory":{}}
	var snap:=world.region_snapshot("home")
	var r:=call_faded(snap,"alice")
	well_formed(r,snap,"region home")
	expect(all_in(r,cells(Vector2i(11,11),Vector2i(14,14))),"home snapshot: room A fades")
	world.state.players.alice.region=World.REGIONS.LANYANG
	world.state.players.alice.x=20.5
	world.state.players.alice.y=20.5
	snap=world.region_snapshot("home")
	expect(not snap.players.has("alice") and call_faded(snap,"alice").is_empty(),"home snapshot ignores a player who is in another region")
	snap=world.region_snapshot(World.REGIONS.LANYANG)
	expect(call_faded(snap,"alice").is_empty(),"lanyang: home roofs at the same coordinates never fade")
	world.state.players.alice.x=12.5
	world.state.players.alice.y=12.5
	snap=world.region_snapshot(World.REGIONS.LANYANG)
	r=call_faded(snap,"alice")
	well_formed(r,snap,"region lanyang")
	expect(all_in(r,shed) and r.size()==shed.size(),"lanyang: only the current region's roof under the player fades")
