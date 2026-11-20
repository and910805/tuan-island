extends SceneTree
## C09 石地板 focused regression (pure World except the last UI section).
## Contract: id `stone_floor`, 2 stone, walkable 1x1 ground, structural floor (room enclosure, roof
## support, floor permissions) exactly like `floor`; `path` / `spring_pebble_path` stay non-floors.
## Not run by the author (no Godot in the authoring session): Codex runs it.
const World=preload("res://scripts/world.gd")
const REGIONS=preload("res://scripts/regions.gd")
const Enclosure=preload("res://scripts/room_enclosure.gd")
const HouseRooms=preload("res://scripts/house_rooms.gd")
const Preview=preload("res://scripts/auto_roof_preview.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const History=preload("res://scripts/construction_history.gd")
const Panels=preload("res://scripts/life_ui_panels.gd")
const Art=preload("res://scripts/stone_floor_art.gd")
const Footsteps=preload("res://scripts/footstep_audio.gd")
const Main=preload("res://main.tscn")
const StoneStation=preload("res://tests/stone_station_fixture.gd")
const KIND:="stone_floor"
const A:="tok-alice"
const B:="tok-bob"
const PARK:=World.SPAWN
const HOME:=REGIONS.HOME

var checks:=0
var failures:=0
var serial:=0
var nonce:=0
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
	for t in [A,B]:w.state.players[t].inventory={"wood":500,"stone":100,"fiber":300}
	# C11: new stone floors need the Q03 board flag and a stone workbench (earned path: test_stone_workbench).
	StoneStation.install(w,A)
	serial+=1
	w.save_path=dir+"/world-%d.json"%serial
	return w

func valid(state:Dictionary)->bool:
	return bool(World.SAVE_SCHEMA.validate(state.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME))

func site_clear(w:World,a:Vector2i,size:Vector2i)->bool:
	for y in range(a.y,a.y+size.y):
		for x in range(a.x,a.x+size.x):
			var c:=Vector2i(x,y)
			var k:=World.key(c)
			if not w.is_land(c) or w.water(c) or w.protected(c):return false
			for field in ["objects","ground","roofs","crops","forest"]:
				if w.state[field].has(k):return false
			var had:bool=w.state.removed.has(k)
			w.state.removed[k]=true
			var b:bool=w.blocked(c)
			if not had:w.state.removed.erase(k)
			if b:return false
	return true

## Legal empty site: interior `size` at the returned origin, with a clear ring and one spare cell beyond,
## away from the public plot, spawn, landing and exit (visit rules reject those).
func find_site(w:World,region:String,size:Vector2i)->Vector2i:
	w.switch_region(region)
	var found:=Vector2i(-1,-1)
	var avoid:Array[Vector2i]=[Vector2i(World.SPAWN),World.WANGAN_COAST.FERRY_LANDING,REGIONS.spawn(HOME),REGIONS.exit_cell(HOME)]
	for oy in range(6,56):
		for ox in range(6,76):
			var box:=Rect2i(Vector2i(ox-3,oy-3),size+Vector2i(6,6))
			var bad:=region==HOME and (box.intersects(World.PUBLIC_BUILD_PLOT) or avoid.any(func(p:Vector2i)->bool:return box.has_point(p)))
			if not bad and site_clear(w,Vector2i(ox-2,oy-2),size+Vector2i(4,4)):
				found=Vector2i(ox,oy)
				break
		if found.x>=0:break
	if found.x>=0:
		for y in range(found.y-2,found.y+size.y+2):
			for x in range(found.x-2,found.x+size.x+2):
				var c:=Vector2i(x,y)
				if w.resource(c)!="":w.state.removed[World.key(c)]=true
	w.switch_region(HOME)
	expect(found.x>=0,"found a legal empty site in "+region)
	return found

func ring(o:Vector2i,size:Vector2i)->Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for x in range(o.x,o.x+size.x):
		out.append(Vector2i(x,o.y-1));out.append(Vector2i(x,o.y+size.y))
	for y in range(o.y,o.y+size.y):
		out.append(Vector2i(o.x-1,y));out.append(Vector2i(o.x+size.x,y))
	return out

func pose(w:World,token:String,at:Vector2)->void:
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:=at if t==token else PARK
		person.x=spot.x;person.y=spot.y

func near(p:Vector2i)->Vector2:
	return Vector2(p)+Vector2(1.5,0.8)

func centre(p:Vector2i)->Vector2:
	return Vector2(p)+Vector2(0.5,0.5)

func do(w:World,token:String,action:String,p:Vector2i,extra:="",at=null)->Dictionary:
	pose(w,token,near(p) if at==null else at)
	serial+=1
	var r:Dictionary=w.act(token,"stone-%d"%serial,action,p,extra)
	expect(w._region==HOME,"home orientation after "+action)
	return r

func inv(w:World,token:String)->Dictionary:
	return w.state.players[token].inventory.duplicate(true)

func gtype(w:World,p:Vector2i)->String:
	return str(w.state.ground.get(World.key(p),{}).get("type",""))

func auto_count(w:World,roofs:Dictionary=Dictionary())->int:
	var layer:Dictionary=roofs if not roofs.is_empty() else w.state.roofs
	var n:=0
	for roof in layer.values():
		if roof.get("auto",false)==true:n+=1
	return n

func unchanged(w:World,token:String,action:String,p:Vector2i,extra:String,needle:String,label:String)->void:
	pose(w,token,near(p))
	var snap:=var_to_str(w.state)
	serial+=1
	var r:Dictionary=w.act(token,"stone-bad-%d"%serial,action,p,extra)
	expect(not r.ok and str(r.message).contains(needle),label+": rejected with '"+needle+"', got "+str(r.message))
	expect(var_to_str(w.state)==snap,label+": world exactly unchanged")

func undo_last(w:World,token:String,at:Vector2i)->Dictionary:
	var summary:=w.undo_summary(token)
	if not bool(summary.get("available",false)):return {"ok":false,"message":"no undo available"}
	return do(w,token,World.UNDO_ACTION,at,str(summary.get("id","")))

func next_nonce()->String:
	nonce+=1
	return ("%02x"%nonce).repeat(16)

## 2x2 interior at o: wood floors on the top row, stone floors on the bottom row, wall ring minus `door`.
func mixed_room(w:World,o:Vector2i,door:Vector2i)->void:
	for c:Vector2i in [o,o+Vector2i.RIGHT]:expect(do(w,A,"build",c,"floor").ok,"wood floor %s"%c)
	for c:Vector2i in [o+Vector2i.DOWN,o+Vector2i.ONE]:expect(do(w,A,"build",c,KIND).ok,"stone floor %s"%c)
	for c in ring(o,Vector2i(2,2)):
		if c!=door:expect(do(w,A,"build",c,"wall").ok,"wall %s"%c)

# --------------------------------------------------------------- scenarios --

func contract_scenario()->void:
	expect(World.BUILD.has(KIND) and World.BUILD[KIND]=={"name":"石地板","stone":2},"stone_floor recipe is 2 stone")
	expect(World.BUILD.floor=={"name":"木地板","wood":2} and World.BUILD.path=={"name":"石板路","stone":2},"wood floor and stone path recipes are unchanged")
	expect(Enclosure.FLOOR_KINDS==["floor","stone_floor"],"one structural floor list")
	for kind in ["floor",KIND]:expect(Enclosure.is_floor_kind(kind) and Enclosure.is_floor_piece({"type":kind}),"%s is a structural floor"%kind)
	for kind in ["path","spring_pebble_path","roof","wall","leaf_floor_mat",""]:expect(not Enclosure.is_floor_kind(kind),"%s is not a structural floor"%kind)
	expect(not Enclosure.is_floor_kind(null) and not Enclosure.is_floor_kind(5) and not Enclosure.is_floor_piece("floor") and not Enclosure.is_floor_piece({}),"malformed values are never floors")
	expect(KIND in Design.GROUND_KINDS and KIND in Panels.FOUNDATIONS,"blueprint ground kinds and the build folio list it")
	expect(KIND in World.AUTO_ROOF_BUILDS and KIND in World.AUTO_ROOF_AREAS and KIND in World.AUTO_ROOF_REMOVES,"automatic roofs watch it")
	expect(KIND in Preview.BUILD_KINDS and KIND in Preview.AREA_KINDS and KIND in Preview.GROUND_KINDS,"construction preview quotes it")
	expect(KIND in History.TOPOLOGY,"history topology watches it")
	expect(Art.PATH=="res://assets/ui-life/stone-floor.png" and Art.has_dedicated_texture()==ResourceLoader.exists(Art.PATH),"art slot uses the agreed 32x32 path (a wrong-sized file is ignored, so this fails loudly)")
	var snap:={"ground":{"4,4":{"type":KIND},"5,4":{"type":"floor"}}}
	expect(Footsteps.surface(snap,"home",{},Vector2(4.5,4.5))=="stone" and Footsteps.surface(snap,"home",{},Vector2(5.5,4.5))=="wood","stone floor sounds like stone, wood floor like wood")

func outdoor_scenario()->void:
	var w:=new_world()
	var o:=find_site(w,HOME,Vector2i(4,4))
	var t:=o+Vector2i(1,1)
	var before:=inv(w,A)
	var builds:=int(w.state.players[A].builds)
	var r:=do(w,A,"build",t,KIND)
	expect(r.ok,"outdoor build: "+str(r.message))
	expect(int(inv(w,A).stone)==int(before.stone)-2 and int(inv(w,A).wood)==int(before.wood) and int(inv(w,A).fiber)==int(before.fiber),"costs exactly 2 stone")
	expect(int(w.state.players[A].builds)==builds+1,"counts one build")
	expect(w.state.ground[World.key(t)]=={"type":KIND,"owner":A,"items":{}},"ground entry shape matches wood floor")
	expect(not w.blocked(t) and w.can_stand(centre(t)),"stone floor is walkable")
	# Walk across it.
	pose(w,A,Vector2(float(t.x)-0.6,float(t.y)+0.5))
	for i in 12:w.move_player(A,Vector2.RIGHT,0.1)
	expect(float(w.state.players[A].x)>float(t.x)+0.8,"a player walks over the stone floor")
	# Outdoors: a lone tile is an open component, no roof appears.
	var room:=Enclosure.analyze(w.state,t)
	expect(room.area==1 and not room.sealed and room.gap_count==4 and w.state.roofs.is_empty(),"outdoor stone floor is open ground with no roof")
	var seen:=HouseRooms.inspect(w.state,t)
	expect(seen.found and seen.area==1 and not seen.complete,"house check sees the stone tile but it is not a house")
	unchanged(w,A,"build",t,KIND,"鋪好","stone floor cannot be laid twice")
	w.state.players[A].inventory.stone=1
	unchanged(w,A,"build",t+Vector2i.RIGHT,KIND,"材料不足","one stone is not enough")
	w.state.players[A].inventory.stone=100
	# Stone path stays a path: not a floor, never joins the component.
	expect(do(w,A,"build",t+Vector2i.RIGHT,"path").ok and gtype(w,t+Vector2i.RIGHT)=="path","stone path still builds as path")
	expect(Enclosure.analyze(w.state,t).area==1 and Enclosure.analyze(w.state,t+Vector2i.RIGHT).area==0,"path never counts as floor")
	expect(not do(w,A,"build",t+Vector2i.RIGHT*2,"roof").ok,"no roof on bare ground")
	# Area build + exact undo.
	var area_at:=o+Vector2i(0,3)
	var stone:=int(inv(w,A).stone)
	var quote:=Preview.quote(w.state,A,"build_area",area_at,"%s|%d|%d"%[KIND,area_at.x+1,area_at.y])
	expect(quote.ok and quote.base_cost=={"stone":4} and not quote.affected,"area quote prices 2 tiles at 4 stone: "+str(quote.get("message","")))
	var area:=do(w,A,"build_area",area_at,"%s|%d|%d"%[KIND,area_at.x+1,area_at.y],Vector2(area_at)+Vector2(1.0,0.5))
	expect(area.ok and gtype(w,area_at)==KIND and gtype(w,area_at+Vector2i.RIGHT)==KIND and int(inv(w,A).stone)==stone-4,"area build lays two stone floors for 4 stone: "+str(area.get("message","")))
	expect(undo_last(w,A,area_at).ok and not w.state.ground.has(World.key(area_at)) and int(inv(w,A).stone)==stone,"undo refunds the area exactly")
	# Single remove refunds the recipe.
	stone=int(inv(w,A).stone)
	expect(do(w,A,"remove",t).ok and not w.state.ground.has(World.key(t)) and int(inv(w,A).stone)==stone+2,"removing refunds 2 stone")

func room_scenario()->void:
	var w:=new_world()
	var o:=find_site(w,HOME,Vector2i(2,2))
	var door:=Vector2i(o.x,o.y-1)
	var cells:Array[Vector2i]=[o,o+Vector2i.RIGHT,o+Vector2i.DOWN,o+Vector2i.ONE]
	mixed_room(w,o,door)
	var open:=Enclosure.analyze(w.state,o)
	expect(open.area==4 and open.gap_count==1 and not open.sealed and auto_count(w)==0,"wood+stone floors form ONE component, still open")
	var quote:=Preview.quote(w.state,A,"build",door,"door")
	expect(quote.ok and quote.plan.add.size()==4 and quote.total_cost=={"wood":10,"fiber":14},"preview quotes door + 4 roofs: "+str(quote.get("message","")))
	var before:=inv(w,A)
	var r:=do(w,A,"build",door,"door")
	expect(r.ok and int(r.get("roof_add_count",0))==4,"door closes the mixed room: "+str(r.message))
	expect(int(before.wood)-int(inv(w,A).wood)==10 and int(before.fiber)-int(inv(w,A).fiber)==14 and int(before.stone)==int(inv(w,A).stone),"server charge equals the quote")
	for c in cells:expect(w.state.roofs.get(World.key(c))=={"type":"roof","owner":A,"items":{},"auto":true},"auto roof over %s"%c)
	for c in ring(o,Vector2i(2,2)):expect(not w.state.roofs.has(World.key(c)),"no roof on boundary %s"%c)
	var sealed:=Enclosure.analyze(w.state,o+Vector2i.ONE)
	expect(sealed.sealed and sealed.area==4,"sealed from a stone cell too")
	var house:=HouseRooms.inspect(w.state,o+Vector2i.DOWN)
	expect(house.found and house.area==4 and house.door_count==1 and house.gap_count==0 and house.roof_missing==0,"house check works from a stone cell")
	expect(valid(w.state),"mixed room validates")
	# Undo the closing door: roofs go, refund exact; redo it.
	expect(undo_last(w,A,door).ok and auto_count(w)==0 and not w.state.objects.has(World.key(door)) and inv(w,A)==before,"undo of the door removes auto roofs and refunds exactly")
	expect(do(w,A,"build",door,"door").ok and auto_count(w)==4,"door rebuilt, roofs return")
	# Removing a stone floor opens the room; undo restores floor + roofs.
	var closed:=inv(w,A)
	var stone_cell:=o+Vector2i.DOWN
	var open_r:=do(w,A,"remove",stone_cell)
	expect(open_r.ok and int(open_r.get("roof_remove_count",0))==4 and auto_count(w)==0 and not w.state.ground.has(World.key(stone_cell)),"removing a stone floor opens the room and refunds roofs: "+str(open_r.message))
	expect(int(inv(w,A).stone)==int(closed.stone)+2 and int(inv(w,A).wood)==int(closed.wood)+4 and int(inv(w,A).fiber)==int(closed.fiber)+12,"refund = 2 stone + 4 roofs")
	expect(undo_last(w,A,stone_cell).ok and gtype(w,stone_cell)==KIND and auto_count(w)==4 and inv(w,A)==closed,"undo restores the stone floor and its roofs")
	# Removing a wood floor behaves the same.
	expect(do(w,A,"remove",o).ok and auto_count(w)==0,"removing a wood floor also opens the room")
	expect(undo_last(w,A,o).ok and gtype(w,o)=="floor" and auto_count(w)==4,"and undoes")
	# Manual roofs on stone floors.
	var spot:=o+Vector2i(0,5)
	expect(do(w,A,"build",spot,KIND).ok,"outside stone floor")
	var roof_before:=inv(w,A)
	expect(do(w,A,"build",spot,"roof").ok and not w.state.roofs[World.key(spot)].has("auto"),"manual roof builds on a stone floor")
	expect(int(roof_before.wood)-int(inv(w,A).wood)==1 and int(roof_before.fiber)-int(inv(w,A).fiber)==3,"manual roof costs the roof recipe")
	expect(undo_last(w,A,spot).ok and not w.state.roofs.has(World.key(spot)) and inv(w,A)==roof_before,"undo of a manual roof refunds exactly")
	expect(do(w,A,"build",spot,"roof").ok and do(w,A,"remove",spot).ok and not w.state.roofs.has(World.key(spot)) and w.state.ground.has(World.key(spot)) and inv(w,A)==roof_before,"manual roof removal keeps the stone floor and refunds")
	expect(do(w,A,"build",spot+Vector2i.RIGHT,"path").ok,"path beside it")
	unchanged(w,A,"build",spot+Vector2i.RIGHT,"roof","先鋪地板","roof on a path is refused")
	# Manual roof first, then close a stone-only room: only the roofless cells are roofed.
	var o2:=find_site(w,HOME,Vector2i(2,2))
	if site_clear(w,o2-Vector2i.ONE,Vector2i(4,4)):
		expect(do(w,A,"build_area",o2,"%s|%d|%d"%[KIND,o2.x+1,o2.y+1],Vector2(o2)+Vector2.ONE).ok,"stone-only room floors")
		expect(do(w,A,"build",o2+Vector2i.ONE,"roof").ok,"manual roof on a stone cell of a future room")
		var door2:=Vector2i(o2.x,o2.y-1)
		for c in ring(o2,Vector2i(2,2)):
			if c!=door2:expect(do(w,A,"build",c,"wall").ok,"wall2 %s"%c)
		var closed2:=do(w,A,"build",door2,"door")
		expect(closed2.ok and int(closed2.get("roof_add_count",0))==3 and not w.state.roofs[World.key(o2+Vector2i.ONE)].has("auto"),"stone-only room adds 3 auto roofs and keeps the manual one")
	else:expect(false,"fixture: second room site is clear")

func owner_scenario()->void:
	var w:=new_world()
	var o:=find_site(w,HOME,Vector2i(2,2))
	var door:=Vector2i(o.x,o.y-1)
	expect(do(w,A,"build_area",o,"floor|%d|%d"%[o.x+1,o.y],Vector2(o)+Vector2(1.0,0.5)).ok,"A lays wood floors")
	expect(do(w,B,"build_area",o+Vector2i.DOWN,"%s|%d|%d"%[KIND,o.x+1,o.y+1],Vector2(o)+Vector2(1.0,1.5)).ok,"B lays stone floors beside them")
	for c in ring(o,Vector2i(2,2)):
		if c!=door:expect(do(w,A,"build",c,"wall").ok,"wall %s"%c)
	var a0:=inv(w,A)
	var b0:=inv(w,B)
	var r:=do(w,B,"build",door,"door")
	expect(r.ok and int(r.get("roof_add_count",0))==4,"B closes the mixed-owner room: "+str(r.message))
	for c in [o,o+Vector2i.RIGHT,o+Vector2i.DOWN,o+Vector2i.ONE]:expect(w.state.roofs[World.key(c)].owner==B,"payer B owns the roof over %s"%c)
	expect(inv(w,A)==a0 and int(b0.wood)-int(inv(w,B).wood)==10 and int(b0.fiber)-int(inv(w,B).fiber)==14,"only B pays door + roofs")
	expect(valid(w.state),"mixed-owner room validates")
	# Auto roof refund goes to the payer when the owner of a stone floor opens the room.
	var b1:=inv(w,B)
	var open_r:=do(w,B,"remove",o+Vector2i.DOWN)
	expect(open_r.ok and int(open_r.get("roof_remove_count",0))==4 and int(inv(w,B).wood)==int(b1.wood)+4 and int(inv(w,B).stone)==int(b1.stone)+2,"B removes own stone floor and gets stone + roofs back")
	expect(undo_last(w,B,o+Vector2i.DOWN).ok and auto_count(w)==4,"B undoes")
	# Manual roof needs your OWN floor, stone included.
	var spot:=o+Vector2i(0,5)
	expect(do(w,A,"build",spot,KIND).ok,"A stone floor outside")
	unchanged(w,B,"build",spot,"roof","自己的地板","B cannot roof A's stone floor")
	expect(do(w,A,"build",spot,"roof").ok,"A roofs own stone floor")
	expect(do(w,A,"remove",spot).ok and w.state.roofs.has(World.key(spot))==false,"removing the roof first")
	# Placement permission on a stone floor.
	unchanged(w,B,"floor_placement_access",spot,"owner","只有家園地板的主人","B cannot change A's stone floor permission")
	expect(do(w,A,"floor_placement_access",spot,"owner").ok and w.state.ground[World.key(spot)].placement_access=="owner","A makes the stone floor owner-only")
	unchanged(w,B,"build",spot,"lamp",World.PLOT_PERMISSIONS.MSG_PRIVATE_FLOOR,"B cannot furnish an owner-only stone floor")
	expect(do(w,A,"floor_placement_access",spot,"island").ok and do(w,B,"build",spot,"lamp").ok,"island access lets B furnish it")
	expect(valid(w.state),"stone floor with placement_access validates")
	# Guest access: private stone room.
	var o2:=find_site(w,HOME,Vector2i(2,2))
	var door2:=Vector2i(o2.x,o2.y-1)
	expect(do(w,A,"build_area",o2,"%s|%d|%d"%[KIND,o2.x+1,o2.y+1],Vector2(o2)+Vector2.ONE).ok,"A stone-only room")
	for c in ring(o2,Vector2i(2,2)):
		if c!=door2:expect(do(w,A,"build",c,"wall").ok,"wall %s"%c)
	expect(do(w,A,"build",door2,"door").ok,"A closes it")
	var visit:=do(w,A,"room_visit_access",o2,"owner")
	expect(visit.ok and w.state.ground[World.key(o2)].get("owner_visit",false)==true,"A makes the stone room private: "+str(visit.get("message","")))
	var inside:=centre(o2)
	expect(not w.can_enter_room_floor(B,inside,centre(door2)+Vector2(0,-1)) and w.can_enter_room_floor(A,inside,centre(door2)),"guest B is kept out, owner A walks in")
	expect(do(w,A,"room_visit_access",o2,"island").ok and w.can_enter_room_floor(B,inside,centre(door2)+Vector2(0,-1)),"island access lets guests in again")
	expect(valid(w.state),"private stone room validates")

func blueprint_scenario()->void:
	var w:=new_world()
	var o:=find_site(w,HOME,Vector2i(2,2))
	mixed_room(w,o,Vector2i(o.x,o.y-1))
	expect(do(w,A,"build",Vector2i(o.x,o.y-1),"door").ok and auto_count(w)==4,"source room roofed")
	var captured:=Design.capture(w.state,A,Rect2i(o-Vector2i.ONE,Vector2i(4,4)),"石屋",World.BUILD,World.NAMES)
	expect(captured.ok and int(captured.auto_roofs_omitted)==4,"capture keeps floors/walls/door and omits auto roofs: "+str(captured.get("reason","")))
	if not captured.ok:return
	var bp:Dictionary=captured.blueprint
	var kinds:={}
	for p in bp.pieces:kinds[p.kind]=int(kinds.get(p.kind,0))+1
	expect(kinds.get("floor",0)==2 and kinds.get(KIND,0)==2 and kinds.get("wall",0)==7 and kinds.get("door",0)==1,"blueprint holds 2 wood + 2 stone floors, 7 walls, a door")
	var turned:=Design.rotate(bp,1,World.BUILD,World.NAMES)
	expect(turned.ok,"rotation accepted")
	if turned.ok:
		var stone_at:Array=[]
		var wood_at:Array=[]
		for p in turned.blueprint.pieces:
			if p.kind==KIND:stone_at.append(Vector2i(p.x,p.y))
			if p.kind=="floor":wood_at.append(Vector2i(p.x,p.y))
		stone_at.sort();wood_at.sort()
		expect(stone_at==[Vector2i(1,1),Vector2i(1,2)] and wood_at==[Vector2i(2,1),Vector2i(2,2)],"a quarter turn keeps stone and wood floors distinct")
		expect(Design.rotate(turned.blueprint,3,World.BUILD,World.NAMES).blueprint.pieces==bp.pieces,"three more turns restore the original")
	# Quote + apply, upright then turned; undo of an apply.
	var site:=find_site(w,HOME,Vector2i(4,4))
	var origin:=site-Vector2i.ONE
	pose(w,A,Vector2(origin)+Vector2(1.5,1.5))
	var before:=inv(w,A)
	var quote:=w.quote_blueprint(A,bp,origin,0)
	expect(quote.ok and quote.cost=={"wood":35,"stone":4,"fiber":14} and int(quote.roof_add)==4,"quote: floors+walls+door+4 auto roofs: "+str(quote))
	var applied:=w.apply_blueprint(A,next_nonce(),bp,origin,0,str(quote.get("hash","")))
	expect(applied.ok,"apply: "+str(applied.get("message","")))
	var room_cell:=origin+Vector2i(1,1)
	expect(gtype(w,room_cell)=="floor" and gtype(w,room_cell+Vector2i.DOWN)==KIND,"applied floors keep their material")
	expect(Enclosure.analyze(w.state,room_cell+Vector2i.DOWN).sealed and auto_count(w)==8,"applied room is sealed and roofed")
	expect(undo_last(w,A,origin).ok and gtype(w,room_cell)=="" and inv(w,A)==before,"undo removes the whole blueprint and refunds exactly")
	var site2:=find_site(w,HOME,Vector2i(4,4))
	var origin2:=site2-Vector2i.ONE
	pose(w,A,Vector2(origin2)+Vector2(1.5,1.5))
	var q2:=w.quote_blueprint(A,bp,origin2,1)
	expect(q2.ok,"turned quote: "+str(q2.get("message","")))
	if q2.ok:
		var a2:=w.apply_blueprint(A,next_nonce(),bp,origin2,1,str(q2.hash))
		expect(a2.ok and gtype(w,origin2+Vector2i(1,1))==KIND and gtype(w,origin2+Vector2i(2,1))=="floor","turned apply puts stone and wood on the rotated cells: "+str(a2.get("message","")))
		expect(Enclosure.analyze(w.state,origin2+Vector2i(1,1)).sealed,"turned room is sealed")

func save_scenario()->void:
	# A pre-C09 style world (wood + path only) must load unchanged.
	var old:=new_world()
	var o:=find_site(old,HOME,Vector2i(2,2))
	var door:=Vector2i(o.x,o.y-1)
	expect(do(old,A,"build_area",o,"floor|%d|%d"%[o.x+1,o.y+1],Vector2(o)+Vector2.ONE).ok,"old: wood floors")
	for c in ring(o,Vector2i(2,2)):
		if c!=door:expect(do(old,A,"build",c,"wall").ok,"old wall")
	expect(do(old,A,"build",door,"door").ok and do(old,A,"build",o+Vector2i(0,4),"path").ok,"old: door, roofs and a stone path")
	var old_ground:Dictionary=old.state.ground.duplicate(true)
	var reloaded:=World.new()
	expect(reloaded.load_world(old.save_path) and reloaded.state.ground==old_ground and auto_count(reloaded,reloaded.state.roofs)==4,"wood-only save reloads identically")
	expect(int(reloaded.state.version)==World.SAVE_SCHEMA.VERSION,"save version unchanged by C09")
	expect(gtype(reloaded,o+Vector2i(0,4))=="path" and not Enclosure.is_floor_kind(gtype(reloaded,o+Vector2i(0,4))),"stone path still a path after reload")
	# History fingerprints: floor entries hash exactly as before, stone differs.
	var layers:={"ground":{"1,1":{"type":"floor","owner":A,"items":{}},"2,1":{"type":KIND,"owner":A,"items":{}}},"objects":{},"roofs":{}}
	expect(History.tile_fingerprint(layers,"t:1,1")=='{"b":"","g":"floor","r":null}'.sha256_text(),"wood floor topology fingerprint is byte-identical to pre-C09")
	expect(History.tile_fingerprint(layers,"t:2,1")=='{"b":"","g":"stone_floor","r":null}'.sha256_text(),"stone floor fingerprint records its own type (material swaps invalidate undo)")
	# Mixed save with a live history entry survives a reload.
	var w:=new_world()
	var m:=find_site(w,HOME,Vector2i(2,2))
	mixed_room(w,m,Vector2i(m.x,m.y-1))
	expect(do(w,A,"build",Vector2i(m.x,m.y-1),"door").ok,"mixed room closed")
	expect(w.save() or FileAccess.file_exists(w.save_path),"world saved")
	var loaded:=World.new()
	var ok:=loaded.load_world(w.save_path)
	expect(ok and loaded.state.ground==w.state.ground and loaded.state.roofs==w.state.roofs,"mixed room reloads identically (ground + roofs)")
	if ok:
		expect(gtype(loaded,m+Vector2i.DOWN)==KIND and auto_count(loaded,loaded.state.roofs)==4,"stone floor and its auto roofs persist")
		expect(bool(loaded.undo_summary(A).get("available",false)),"the live construction history entry still validates after reload")
	# Validator edges.
	var good:=w.state.duplicate(true)
	expect(valid(good),"fixture validates")
	var as_object:=good.duplicate(true);as_object.objects["1,1"]={"type":KIND,"owner":A,"items":{}}
	expect(not valid(as_object),"stone_floor on the objects layer is rejected")
	var on_path:=good.duplicate(true)
	var key:=World.key(m+Vector2i.DOWN)
	on_path.ground[key].type="path"
	expect(not valid(on_path),"an auto roof over a path is rejected (only floors support roofs)")
	var path_access:=good.duplicate(true)
	path_access.ground[World.key(Vector2i(m.x+5,m.y+5))]={"type":"path","owner":A,"items":{},"placement_access":"owner"}
	expect(not valid(path_access),"placement_access on a path is rejected")
	var stone_access:=good.duplicate(true)
	stone_access.ground[key].placement_access="owner"
	expect(valid(stone_access),"placement_access on a stone floor is accepted")
	# Non-home region: layers, roofs and reload.
	var lan:=new_world()
	lan.state.players[A].region=REGIONS.LANYANG
	var lo:=find_site(lan,REGIONS.LANYANG,Vector2i(2,2))
	var ldoor:=Vector2i(lo.x,lo.y+2)
	expect(do(lan,A,"build_area",lo,"%s|%d|%d"%[KIND,lo.x+1,lo.y+1],Vector2(lo)+Vector2.ONE).ok,"Lanyang stone floors")
	for c in ring(lo,Vector2i(2,2)):
		if c!=ldoor:expect(do(lan,A,"build",c,"wall").ok,"Lanyang wall")
	var lr:=do(lan,A,"build",ldoor,"door")
	var lan_layers:Dictionary=lan.state.regions[REGIONS.LANYANG]
	expect(lr.ok and int(lr.get("roof_add_count",0))==4 and auto_count(lan,lan_layers.roofs)==4 and lan.state.roofs.is_empty(),"Lanyang room roofed in Lanyang layers only: "+str(lr.get("message","")))
	var lan_loaded:=World.new()
	expect(lan_loaded.load_world(lan.save_path) and str(lan_loaded.state.regions[REGIONS.LANYANG].ground.get(World.key(lo),{}).get("type",""))==KIND,"Lanyang stone floor survives a reload")

func ui_scenario()->void:
	var app=Main.instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640)
	await process_frame
	var path:="user://stone-floor-%d.json"%OS.get_process_id()
	if app.session.host(0,"石工",path)!=OK:
		expect(false,"UI: local host")
		app.queue_free()
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	StoneStation.install(world,token)
	var first:=Vector2i(41,36)
	person.x=41.5
	person.y=37.5
	person.inventory.stone=10
	app.session._send_snapshot(1)
	app._build_menu()
	await process_frame
	var tab:=app.modal.find_child("BuildTab1",true,false) as Button
	if tab:tab.pressed.emit()
	var slot:=app.modal.find_child("BuildSlot_stone_floor_1",true,false) as Button
	expect(slot!=null and slot.is_visible_in_tree(),"UI: the foundations page lists 石地板")
	if slot:slot.pressed.emit()
	await process_frame
	var title:=app.modal.find_child("BuildTitle",true,false) as Label
	expect(title!=null and title.text.contains("石地板"),"UI: the folio selects 石地板")
	var preview:=app.modal.find_child("BuildPreview",true,false) as Control
	expect(preview!=null and preview.get_child_count()>0,"UI: folio preview renders")
	app._close_modal()
	app.building=KIND
	app._select_tool("build")
	expect(app.selected_label.text.contains("石地板") and app.selected_label.text.contains("拖曳"),"UI: tool hint offers area construction")
	# Controller: right stick marks the start, D-pad moves, X builds the area.
	app.controller_offset=Vector2i.ZERO
	app.action_clock=0
	var pad:=InputEventJoypadButton.new()
	pad.pressed=true
	pad.button_index=JOY_BUTTON_RIGHT_STICK
	app._input(pad)
	expect(app.area_drag,"UI: right stick starts an area drag for 石地板")
	app.area_drag=false
	app._perform_build_action("build_area",first,"%s|%d|%d"%[KIND,first.x+1,first.y])
	for tile in [first,first+Vector2i.RIGHT]:expect(str(world.state.ground.get(World.key(tile),{}).get("type",""))==KIND,"UI: area action laid stone floor at %s"%tile)
	expect(int(person.inventory.stone)==6,"UI: two tiles cost 4 stone")
	app._perform_build_action("build",first+Vector2i.DOWN,KIND)
	expect(str(world.state.ground.get(World.key(first+Vector2i.DOWN),{}).get("type",""))==KIND,"UI: single action laid stone floor")
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func run()->void:
	dir="user://test-stone-floor-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	expect(DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated test directory")
	contract_scenario()
	outdoor_scenario()
	room_scenario()
	owner_scenario()
	blueprint_scenario()
	save_scenario()
	await ui_scenario()
	for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir+"/"+f)
	DirAccess.remove_absolute(dir)
	print("STONE_FLOOR_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
