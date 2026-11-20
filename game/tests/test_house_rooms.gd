extends SceneTree
const World=preload("res://scripts/world.gd")
const Rooms=preload("res://scripts/house_rooms.gd")
const Session=preload("res://scripts/session.gd")
const Industry=preload("res://scripts/industry.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const WallFixtures=preload("res://scripts/wall_fixtures.gd")
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
	check_guest_furnishing()
	check_visit_permissions()
	check_outdoor_visit_permissions()
	print("HOUSE_ROOMS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

## Puts every cell of a real multi-cell piece (part i at station_cells[i]) into the snapshot.
func place(s:Dictionary,kind:String,anchor:Vector2i,owner:="alice",vertical:=false,skip:=-1) -> void:
	var field:=Industry.square_part_field(kind)
	# Plain single-tile kinds must not fall back to Industry's SQUARE_CELLS footprint.
	var cells:Array=[Vector2i.ZERO] if field.is_empty() else Industry.station_cells(kind,vertical)
	for i in cells.size():
		if i==skip:continue
		var piece:={"type":kind,"owner":owner,"items":{}}
		if not field.is_empty():piece[field]=i
		if vertical:piece[Industry.vertical_field(kind)]=true
		s.objects[k(anchor+cells[i])]=piece

func guest(s:Dictionary,owner:="alice") -> Dictionary:
	return Rooms.guest_room(s,Rooms.inspect(s,Vector2i(12,12)),Vector2i(12,12),owner)

func check_guest_furnishing() -> void:
	var lamp_spot:=Vector2i(10,10)
	var seat_spot:=Vector2i(13,10)
	# Cedar bed + paper tea lamp + generic chair.
	var s:=house();s.objects.erase(k(BED))
	place(s,Industry.CEDAR_BED,Vector2i(12,13))
	place(s,Industry.PAPER_TEA_LAMP,lamp_spot);place(s,"chair",seat_spot)
	var r:=Rooms.inspect(s,Vector2i(12,12))
	var g:=guest(s)
	expect(r.complete and r.bed_count==1 and r.reachable_bed,"cedar bed counts as one reachable house bed")
	expect(g.ready and g.furnished.bed and g.furnished.lamp and g.furnished.chair and g.contributed and g.inside,"cedar + paper lamp + chair is a ready guest room")
	expect(g.keys().size()==4 and g.furnished.keys().size()==3,"guest_room result keys preserved")
	# Vertical quilt bed + spore lamp + copper garden chair.
	s=house();s.objects.erase(k(BED))
	place(s,Industry.INN_BED,Vector2i(10,12),"alice",true)
	place(s,Industry.SPORE_LAMP,lamp_spot);place(s,Goals.GARDEN_CHAIR,seat_spot)
	r=Rooms.inspect(s,Vector2i(12,12));g=guest(s)
	expect(r.complete and r.bed_count==1 and g.ready,"vertical quilt bed + spore lamp + copper chair ready")
	# Wall lamp + hollow bed (four cells) + mushroom stool.
	s=house();s.objects.erase(k(BED))
	place(s,Industry.HOLLOW_BED,Vector2i(12,12))
	place(s,WallFixtures.LIGHT,Vector2i(12,10));place(s,Industry.MUSHROOM_STOOL,seat_spot)
	r=Rooms.inspect(s,Vector2i(12,12));g=guest(s)
	expect(r.bed_count==1 and r.reachable_bed and g.ready,"hollow bed + wall lamp + mushroom stool ready")
	# Plain styled bed/chair/lamp remain the same types.
	s=house();s.objects[k(BED)].style="oak"
	place(s,"lamp",lamp_spot);place(s,"chair",seat_spot);s.objects[k(seat_spot)].style="oak"
	expect(guest(s).ready,"styled generic bed, lamp and chair count")
	for lamp in [Industry.PAPER_TEA_LAMP,Industry.SPORE_LAMP,"star_garden_lamp",WallFixtures.LIGHT]:
		s=house();place(s,lamp,lamp_spot);place(s,"chair",seat_spot)
		expect(guest(s).ready,"lamp type counts: "+lamp)
	for seat in [Industry.WOOD_CHAIR,Goals.GARDEN_CHAIR,Industry.MUSHROOM_STOOL,Industry.INDIGO_CUSHION,"sofa"]:
		s=house();place(s,"lamp",lamp_spot);place(s,seat,seat_spot)
		expect(guest(s).ready,"seat type counts: "+seat)
	# Two-seat bench needs both ends inside the room.
	s=house();place(s,"lamp",lamp_spot)
	s.objects[k(seat_spot)]={"type":Goals.BAMBOO_BENCH,"owner":"alice","items":{}}
	expect(not guest(s).furnished.chair,"bench anchor on the wall edge is incomplete")
	s.objects[k(seat_spot+Vector2i.LEFT)]={"type":Goals.BAMBOO_BENCH,"owner":"alice","items":{},"bench_end":true}
	expect(not guest(s).furnished.chair,"bench end on the left of its anchor is an orphan")
	s.objects.erase(k(seat_spot));s.objects[k(seat_spot+Vector2i.LEFT)].erase("bench_end")
	s.objects[k(seat_spot)]={"type":Goals.BAMBOO_BENCH,"owner":"alice","items":{},"bench_end":true}
	expect(guest(s).ready,"whole two-seat bench counts")
	# Own contribution: someone else's furniture does not qualify the viewer.
	s=house("alice","alice");s.objects.erase(k(BED))
	place(s,Industry.CEDAR_BED,Vector2i(12,13),"bob");place(s,"lamp",lamp_spot,"bob");place(s,"chair",seat_spot,"bob")
	g=guest(s,"alice")
	expect(g.furnished.bed and g.furnished.lamp and g.furnished.chair and not g.contributed and not g.ready,"furnished by others is not own contribution")
	expect(guest(s,"bob").ready,"the furnishing owner contributes")
	# One own piece is enough once the room is fully furnished.
	place(s,"lamp",lamp_spot,"alice")
	expect(guest(s,"alice").ready,"own lamp alone provides contribution")
	# Incomplete footprints: missing filler, orphan filler, cut by wall.
	s=house();s.objects.erase(k(BED))
	place(s,"lamp",lamp_spot);place(s,"chair",seat_spot)
	place(s,Industry.CEDAR_BED,Vector2i(12,13),"alice",false,1)
	r=Rooms.inspect(s,Vector2i(12,12));g=guest(s)
	expect(r.bed_count==0 and not g.furnished.bed and not g.ready and has_reason(r,"床"),"cedar anchor without filler is not a bed")
	s=house();s.objects.erase(k(BED))
	place(s,Industry.CEDAR_BED,Vector2i(12,13),"alice",false,0)
	r=Rooms.inspect(s,Vector2i(12,12))
	expect(r.bed_count==0 and not r.reachable_bed and not guest(s).furnished.bed,"orphan bed filler is rejected")
	s=house();s.objects.erase(k(BED))
	place(s,Industry.HOLLOW_BED,Vector2i(12,12),"alice",false,3)
	expect(Rooms.inspect(s,Vector2i(12,12)).bed_count==0,"three of four hollow bed cells is incomplete")
	s=house();s.objects.erase(k(BED))
	place(s,Industry.CEDAR_BED,Vector2i(13,13))
	r=Rooms.inspect(s,Vector2i(12,12))
	expect(r.bed_count==0 and not guest(s).furnished.bed,"bed footprint crossing the wall does not count")
	s=house();s.objects.erase(k(BED))
	s.objects[k(BED)]={"type":Industry.INN_BED,"owner":"alice","items":{}}
	expect(Rooms.inspect(s,Vector2i(12,12)).bed_count==0,"legacy single-cell quilt bed without filler is incomplete")
	# Every side of a multi-cell bed is a valid approach, including the filler side.
	s=house();s.objects.erase(k(BED))
	place(s,Industry.CEDAR_BED,Vector2i(12,13))
	for p in [Vector2i(11,13),Vector2i(12,12)]:s.objects[k(p)]={"type":"chest","owner":"alice","items":{}}
	r=Rooms.inspect(s,Vector2i(12,12))
	expect(r.bed_count==1 and r.reachable_bed,"bed reachable only from the filler side")
	s.objects[k(Vector2i(13,12))]={"type":"chest","owner":"alice","items":{}}
	r=Rooms.inspect(s,Vector2i(12,12))
	expect(r.bed_count==1 and not r.reachable_bed and not r.complete,"fully walled-in bed is unreachable")

func check_visit_permissions() -> void:
	var world:=World.new()
	world.add_player("alice","Owner")
	world.add_player("bob","Visitor")
	var offset:=Vector2i(18,12)
	var doorway:=DOOR+offset
	var inside:=INNER+offset
	var approach:=Vector2(doorway)+Vector2(0.5,-0.5)
	var fixture:=house()
	for layer in ["ground","objects"]:
		for tile in fixture[layer]:
			var point:=World.cell(tile)+offset
			world.state[layer][World.key(point)]=fixture[layer][tile]
			if not World.base_resource(point).is_empty():world.state.removed[World.key(point)]=true
	if not World.base_resource(doorway+Vector2i.UP).is_empty():
		world.state.removed[World.key(doorway+Vector2i.UP)]=true
	world.state.players.alice.x=inside.x+0.5
	world.state.players.alice.y=inside.y+1.5
	world.state.players.bob.x=approach.x
	world.state.players.bob.y=approach.y
	var path:=OS.get_environment("TEMP").path_join("visit-room-"+str(Time.get_ticks_usec())+".json")
	world.save_path=path
	expect(not world.act("bob","visitor-policy","room_visit_access",inside,"owner").ok,"Visitor cannot change room access")
	expect(world.act("alice","open-door","door",doorway).ok,"Shared room door opens normally")
	for step in 40:world.move_player("bob",Vector2.DOWN,1.0/60.0)
	expect(world.state.players.bob.y>inside.y,"Open room admits visitors")
	expect(world.act("alice","owner-only","room_visit_access",inside,"owner").ok,"Owner can restrict own enclosed room")
	expect(world.load_world(path) and world.state.ground[World.key(inside)].owner_visit,"Room setting survives reload")
	for step in 40:world.move_player("bob",Vector2.UP,1.0/60.0)
	expect(world.state.players.bob.y<doorway.y,"Already present visitor can leave after room becomes private")
	for step in 40:world.move_player("bob",Vector2.DOWN,1.0/60.0)
	expect(world.state.players.bob.y<inside.y,"Visitor cannot walk back in through the open door")
	var inner_pos:=Vector2(inside)+Vector2(0.5,0.5)
	expect(world.safe_arrival(inner_pos,"bob")!=inner_pos and world.safe_arrival(inner_pos,"alice")==inner_pos,"Arrival respects room access with no owner restriction")
	world.add_player("third","Visitor",approach)
	var guest_public:="bob".sha256_text().left(16)
	expect(not world.act("alice","fake-guest","room_visit_access",inside,"friend:fake").ok,"Unknown visitor reference is rejected")
	expect(world.act("alice","invite-guest","room_visit_access",inside,"friend:"+guest_public).ok
		and world.load_world(path),"Named guest grant persists after loading")
	var floor_key:=World.key(inside)
	var session:=Session.new()
	session.world=world
	expect(session.public_state("home","alice").ground[floor_key].visit_guest==guest_public
		and session.public_state("home","bob").ground[floor_key].visit_guest==guest_public
		and not session.public_state("home","third").ground[floor_key].has("visit_guest"),
		"Only owner and named guest receive projected visitor reference")
	session.free()
	for step in 40:
		world.move_player("bob",Vector2.DOWN,1.0/60.0)
		world.move_player("third",Vector2.DOWN,1.0/60.0)
	expect(world.state.players.bob.y>inside.y and world.state.players.third.y<inside.y,"Only designated visitor enters despite another visitor with same name")
	expect(world.act("alice","revoke-guest","room_visit_access",inside,"owner").ok
		and not world.state.ground[floor_key].has("visit_guest"),"Owner can revoke just the named visitor")
	for step in 70:world.move_player("bob",Vector2.UP,1.0/60.0)
	expect(world.state.players.bob.y<doorway.y,"Revoked visitor can still leave")
	expect(world.act("alice","reopen-room","room_visit_access",inside,"island").ok,"Owner reopens visitation")
	for step in 40:world.move_player("third",Vector2.DOWN,1.0/60.0)
	expect(world.state.players.third.y>inside.y,"Any visitor can enter after reopening")
	for file in [path,path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)

func check_outdoor_visit_permissions() -> void:
	var world:=World.new()
	world.add_player("alice","Owner")
	world.add_player("bob","Visitor")
	var site:=Vector2i(27,21)
	var second:=site+Vector2i.RIGHT
	for tile in [site,second,site+Vector2i.LEFT]:
		if not World.base_resource(tile).is_empty():world.state.removed[World.key(tile)]=true
	for tile in [site,second]:
		world.state.ground[World.key(tile)]={"type":"floor","owner":"alice","items":{}}
	world.state.players.alice.x=site.x+0.5
	world.state.players.alice.y=site.y+0.5
	world.state.players.bob.x=site.x-0.5
	world.state.players.bob.y=site.y+0.5
	var room:=World.ROOM_ENCLOSURE.analyze(world.state,site)
	expect(not room.sealed and room.area==2,"Outdoor visit fixture has two connected floor tiles and no walls")
	expect(world.act("alice","outdoor-private","room_visit_access",site,"owner").ok and world.state.ground[World.key(second)].owner_visit,"Outdoor restriction includes the connected owner's deck")
	for step in 20:world.move_player("bob",Vector2.RIGHT,1.0/60.0)
	expect(world.state.players.bob.x<site.x,"Outdoor boundary stops uninvited visitor")
	expect(world.act("alice","outdoor-public","room_visit_access",second,"island").ok,"Owner reopens the whole connected outdoor deck")
	for step in 20:world.move_player("bob",Vector2.RIGHT,1.0/60.0)
	expect(world.state.players.bob.x>site.x,"Visitor walks onto reopened outdoor area")
	world.state.ground[World.key(second)].owner="bob"
	expect(not world.act("alice","outdoor-mixed","room_visit_access",site,"owner").ok and not world.state.ground[World.key(site)].has("owner_visit"),"Mixed ownership rejects the entire change")
	var public_cell:=World.PUBLIC_BUILD_PLOT.position
	world.state.players.alice.x=public_cell.x+0.5
	world.state.players.alice.y=public_cell.y+0.5
	world.state.ground[World.key(public_cell)]={"type":"floor","owner":"alice","items":{}}
	expect(not world.act("alice","private-public","room_visit_access",public_cell,"owner").ok,"Public construction ground cannot be marked private")
	for x in range(11,37):
		world.state.ground[World.key(Vector2i(x,15))]={"type":"floor","owner":"alice","items":{}}
	world.state.players.alice.x=20.5
	world.state.players.alice.y=15.5
	expect(not world.act("alice","too-large","room_visit_access",Vector2i(20,15),"owner").ok,"Outdoor deck over 25 tiles cannot be restricted")
