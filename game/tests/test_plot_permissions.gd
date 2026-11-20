extends SceneTree
## T057: operation-specific plot permission checks (place / take / harvest /
## dismantle). Wherever the live action is reachable from spawn, the module's
## verdict is compared with World.act (same ok, same message on denial, state
## untouched on denial), so the module cannot silently drift from world.gd.
const World=preload("res://scripts/world.gd")
const Perm=preload("res://scripts/plot_permissions.gd")
const Membership=preload("res://scripts/world_membership.gd")
const StoneStation=preload("res://tests/stone_station_fixture.gd")
const Session=preload("res://scripts/session.gd")
var checks:=0
var failures:=0
var seq:=0
var w

func expect(value:bool,description:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+description)

func act(token:String,action:String,p:Vector2i,extra:="") -> Dictionary:
	seq+=1
	return w.act(token,"perm-%d"%seq,action,p,extra)

func parity(check:Dictionary,token:String,action:String,p:Vector2i,extra:String,label:String) -> void:
	var before:Dictionary=w.state.duplicate(true)
	var live:=act(token,action,p,extra)
	expect(check.ok==live.ok,"%s: module ok=%s, world ok=%s (%s)"%[label,check.ok,live.ok,live.message])
	if not check.ok:
		expect(check.message==live.message,"%s: module '%s' vs world '%s'"%[label,check.message,live.message])
		expect(w.state==before,"%s: denial leaves state unchanged"%label)

func _initialize() -> void:
	w=World.new()
	w.add_player("alice","阿米")
	w.add_player("bob","小豆")
	mirrors()
	harvest_and_plot()
	placed_objects()
	public_areas()
	floors()
	regional_sowing()
	ferry_access()
	public_build_grants()
	personal_floor_access()
	furniture_removal_access()
	shared_chest_floor_access()
	print("PLOT_PERMISSIONS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func shared_chest_floor_access() -> void:
	w=World.new()
	var actors:=["floor-owner","box-owner","other-member"]
	var site:=Vector2i(40,24)
	var station:=site+Vector2i.RIGHT
	var tile:=World.key(site)
	var history:=World.SAVE_SCHEMA.CHEST_HISTORY.READ_ACTION
	for actor:String in actors:
		w.add_player(actor,actor,Vector2(39.5,25.5))
		w.state.players[actor].inventory.wood=70
	w.state.removed[tile]=true
	expect(act(actors[0],"build",site,"floor").ok and act(actors[1],"build",site,"chest").ok,"Different members can place the floor and box")
	expect(act(actors[2],"deposit_exact",site,"wood:2").ok and act(actors[2],history,site).ok,"All members use a shared box on a default floor")
	# A legacy workbench fixture keeps material access independent of today's bench footprint.
	w.state.objects[World.key(station)]={"type":"bench","owner":actors[0],"items":{}}
	var prepared:=act(actors[2],"prepare_material_box",station,tile)
	expect(prepared.ok and not str(prepared.get("source_id","")).is_empty(),"A member prepares the shared box before the floor is locked")
	expect(act(actors[0],"floor_placement_access",site,"owner").ok,"Floor owner restricts the plot after box placement")
	expect(act(actors[2],"deposit_exact",site,"wood:1").message==Perm.MSG_SHARED_CHEST_FLOOR,"The floor setting prevents another member depositing")
	expect(act(actors[2],"withdraw_all",site,"wood").message==Perm.MSG_SHARED_CHEST_FLOOR,"The floor setting prevents another member withdrawing")
	expect(not act(actors[2],history,site).ok and not act(actors[2],"prepare_material_box",station,tile).ok,"The restricted box exposes neither history nor a new material quote")
	var prior_quote:=World.MATERIAL_SOURCES.encode("plank",tile,str(prepared.get("source_id","")),"0123456789abcdef")
	expect(act(actors[2],"craft",station,prior_quote).message==Perm.MSG_SHARED_CHEST_FLOOR,"A previously prepared box cannot be used after access is revoked")
	var session:=Session.new()
	session.world=w
	var view:=session.public_state("home",actors[2])
	var box:Dictionary=view.objects[tile]
	expect(box.locked and box.items.is_empty() and not box.has("box_id"),"Restricted snapshots omit the contents and material-source identity")
	var projected:=session.public_state("home",actors[2],{"layers":["ground"],"rect":Rect2i(0,0,1,1),"own":actors[2]})
	expect(not projected.ground.has(tile) and projected.objects[tile].items.is_empty() and projected.objects[tile].locked,
		"With ground outside the subscription, visible chest rows stay redacted")
	expect(World.MATERIAL_SOURCES.candidates(view.objects,actors[2].sha256_text().left(16),station).is_empty(),"The workbench omits the restricted box from its source options")
	for actor in actors.slice(0,2):
		expect(act(actor,history,site).ok and int(session.public_state("home",actor).objects[tile].items.wood)==2,"Floor owner and box owner both retain access")
	expect(act(actors[0],"floor_placement_access",site,"island").ok,"The floor owner restores shared access")
	expect(not session.public_state("home",actors[2]).objects[tile].has("locked") and act(actors[2],"withdraw_all",site,"wood").ok,"Restored access reveals the same box and authorizes withdrawal")
	session.free()

func furniture_removal_access() -> void:
	w=World.new()
	w.add_player("owner","Owner")
	w.add_player("guest","Guest")
	for visitor in w.state.players.values():
		visitor.x=39.5
		visitor.y=26.5
	var target:=Vector2i(40,24)
	var tile:=World.key(target)
	var path:=OS.get_environment("TEMP").path_join("guest-removal-"+Membership.new_character()+".json")
	w.save_path=path
	expect(act("owner","build",target,"chair").ok,"Owner places a chair")
	expect(not act("guest","furniture_remove_access",target,"island").ok,"Visitor cannot change removal policy")
	expect(act("guest","remove",target).message==Perm.MSG_FOREIGN_OBJECT,"Furniture removal defaults to owner only")
	expect(act("owner","furniture_remove_access",target,"island").ok,"Owner grants removal")
	expect(act("guest","move_object",target,"41,24").message==Perm.MSG_FOREIGN_MOVE,"Removal grant does not permit relocation")
	expect(act("owner","furniture_remove_access",target,"owner").ok and not act("guest","remove",target).ok,"Owner can revoke grant")
	expect(act("owner","furniture_remove_access",target,"island").ok and w.load_world(path) and w.state.objects[tile].guest_remove,"Removal grant survives reload")
	var before:Dictionary=w.state.duplicate(true)
	w.save_path=path.path_join("missing").path_join("world.json")
	expect(not act("guest","remove",target).ok and w.state==before,"Failed save rolls back removal and owner's refund")
	w.save_path=path
	w.active_tokens.erase("owner")
	expect(act("guest","remove",target).ok and not w.state.objects.has(tile),"Visitor removes shared furniture with owner offline")
	expect(w.state.players.owner.inventory.wood==12 and w.state.players.guest.inventory.wood==12,"Refund credits the owner, visitor receives nothing")
	expect(not w.undo_summary("guest").available,"Visitor cannot reverse another resident's refund")
	expect(not act("guest","remove",target).ok and w.load_world(path) and w.state.players.owner.inventory.wood==12,"Retry cannot pay twice and refund survives reload")
	w.state.players.owner.inventory.wood=100
	expect(act("owner","build",target,"private_chest").ok and not act("owner","furniture_remove_access",target,"island").ok,"Private chests cannot be shared for demolition")
	for file in [path,path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)

func personal_floor_access() -> void:
	w=World.new()
	w.add_player("owner","Owner")
	w.add_player("guest","Guest")
	var site:=Vector2i(40,24)
	var outside:=site+Vector2i.LEFT
	var tile:=World.key(site)
	for visitor in w.state.players.values():
		visitor.x=39.5
		visitor.y=26.5
		visitor.inventory.wood=100
	w.save_path=OS.get_environment("TEMP").path_join("personal-floor-"+Membership.new_character()+".json")
	expect(act("owner","build",site,"floor").ok,"Owner lays a personalized floor")
	expect(not act("guest","floor_placement_access",site,"island").ok,"Guest cannot edit placement permission")
	expect(act("guest","build",outside,"chair").ok,"Guest builds a chair beside the floor")
	expect(act("owner","floor_placement_access",site,"owner").ok,"Owner locks the floor")
	var plan:={"version":1,"name":"Chair","width":1,"height":1,"pieces":[{"kind":"chair","x":0,"y":0}]}
	var before:Dictionary=w.state.players.guest.inventory.duplicate()
	expect(act("guest","build",site,"chair").message==Perm.MSG_PRIVATE_FLOOR,"Locked floor rejects manual furniture")
	expect(act("guest","move_object",outside,tile).message==Perm.MSG_PRIVATE_FLOOR,"Locked floor rejects incoming move")
	expect(not w.quote_blueprint("guest",plan,site).ok and w.state.players.guest.inventory==before,"Locked floor rejects blueprint and leaves materials")
	expect(w.load_world(w.save_path) and w.state.ground[tile].placement_access=="owner","Lock survives world reload")
	expect(act("owner","floor_placement_access",site,"island").ok,"Owner opens shared placement")
	expect(w.quote_blueprint("guest",plan,site).ok,"Shared floor permits a normally valid blueprint")
	expect(act("guest","move_object",outside,tile).ok,"Guest can move own chair onto shared floor")
	expect(act("guest","remove",site).ok and w.state.ground.has(tile),"Removing guest furniture leaves owner floor")
	expect(act("owner","floor_placement_access",site,"legacy").ok and not w.state.ground[tile].has("placement_access"),"Restore original compatibility behavior")
	expect(not w.quote_blueprint("guest",plan,site).ok and act("guest","build",site,"chair").ok,"Default remains manual-only for guests")
	for path in [w.save_path,w.save_path+".bak"]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)

func public_build_grants() -> void:
	w=World.new()
	w.add_player("builder","Builder")
	# C11: new smelters need the station, otherwise its refusal would mask the footprint/plot rule below.
	StoneStation.install(w,"builder")
	var user:Dictionary=w.state.players.builder
	user.x=39.5
	user.y=26.5
	user.inventory.wood=100
	user.inventory.fiber=40
	var path:=OS.get_environment("TEMP").path_join("public-plot-"+Membership.new_character()+".json")
	var roster:=Membership.new()
	expect(roster.initialize(path,"Test Island","owner","Owner","room-owner"),"Authenticated roster created")
	expect(roster.link_legacy("owner","worker","Builder","builder"),"Member matches in-world character")
	var target:=Membership.management_id("builder")
	w.public_build_access=roster.can_build_public
	var site:=World.PUBLIC_BUILD_PLOT.position
	var outside:=site+Vector2i.LEFT
	var short_plan:={"version":1,"name":"Chair","width":1,"height":1,"pieces":[{"kind":"chair","x":0,"y":0}]}
	var denied:=World.PUBLIC_BUILD_DENIED
	expect(act("builder","build",site,"chair").message==denied,"Unapproved placement denied")
	expect(act("builder","build_area",outside,"floor|40|24").message==denied and w.state.ground.is_empty(),"Batch cannot cross into unapproved plot")
	expect(act("builder","build",outside,World.INDUSTRY.SMELTER).message==denied,"Multi-cell object footprint cannot cross into unapproved plot")
	var quote:Dictionary=w.quote_blueprint("builder",short_plan,site)
	expect(not quote.ok and quote.problems.any(func(problem):return problem.reason==denied),"Blueprint simulation enforces public access")
	expect(not roster.set_public_builder("worker",target,true),"Member cannot self-grant")
	expect(roster.link_legacy("owner","manager","Manager","plot-manager")
		and roster.set_admin("owner",Membership.management_id("plot-manager"),true),"Appoint public works manager")
	expect(roster.set_public_builder("manager",target,true) and roster.open(path),"Manager grant survives roster reload")
	expect(w.quote_blueprint("builder",short_plan,site).ok,"Approved blueprint quote passes")
	expect(act("builder","build",site,"chair").ok,"Approved member can build")
	expect(roster.set_public_builder("owner",target,false),"Authority revokes permission")
	var adjoining:=site+Vector2i.RIGHT
	expect(act("builder","move_object",site,"%d,%d"%[adjoining.x,adjoining.y]).message==denied,"Revoked member cannot move furniture into another public cell")
	expect(act("builder","remove",site).ok,"Original builder can clear previous furniture after revocation")
	expect(roster.read("owner").management_history.map(func(row):return row.action)==["admin_grant","public_build_grant","public_build_revoke"],"Both changes appear in owner audit")
	DirAccess.remove_absolute(path)

## Module copies of World constants must not drift.
func mirrors() -> void:
	expect(Perm.PRIVATE_BOXES==World.PRIVATE_BOXES,"PRIVATE_BOXES mirrors World")
	expect(Perm.SALT_BOXES==World.SALT_BOXES,"SALT_BOXES mirrors World")
	expect(Perm.MSG_SALT_SOCKET==World.SALT_SOCKET_MSG,"salt socket message mirrors World")
	expect(Perm.LEGACY_DEFAULTS.crop_owner_sowable_owner_only_regions==[World.REGIONS.Bamboo.REGION,World.FLOWER_NURSERY.REGION],"owner-only sowing regions mirror World")
	expect(Perm.ROLE_OVERRIDES.is_empty(),"no world-owner/admin plot override exists yet")

func harvest_and_plot() -> void:
	var plot:=Vector2i(38,34)
	var k:=World.key(plot)
	expect(act("alice","hoe",plot).ok,"alice tills a plot")
	# place: greenhouse only on own plot (world.gd:2322, before material checks).
	expect(Perm.can_place(w,"alice",plot,"greenhouse_roof").ok,"owner may roof own plot with glass")
	parity(Perm.can_place(w,"bob",plot,"greenhouse_roof"),"bob","build",plot,"greenhouse_roof","guest greenhouse on owner's plot")
	expect(not act("bob","plot_sow_access",plot,"owner").ok,"Guest cannot change another player's sowing access")
	expect(act("alice","plot_sow_access",plot,"owner").ok,"Owner can lock manual sowing")
	expect(Perm.can_place(w,"alice",plot,"seed:radish").ok,"Owner may still sow on the locked field")
	parity(Perm.can_place(w,"bob",plot,"seed:radish"),"bob","seed",plot,"radish","locked plot refuses guest sowing")
	expect(Perm.can_harvest(w,"bob",w.state.crops[k]).ok,"Sowing lock does not change harvest access")
	expect(act("alice","plot_sow_access",plot,"island").ok and not w.state.crops[k].has("owner_sow"),"Owner can restore the legacy sharing setting")
	# place(seed): legacy home sowing is open to any member (world.gd:2148).
	parity(Perm.can_place(w,"bob",plot,"seed:radish"),"bob","seed",plot,"radish","guest sows owner's empty home plot")
	expect(not act("bob","plot_water_access",plot,"owner").ok,"Guest cannot change watering access")
	expect(act("alice","plot_water_access",plot,"owner").ok and not w.state.crops[k].has("owner_sow"),"Owner locks only manual watering")
	parity(Perm.can_water(w,"bob",w.state.crops[k]),"bob","water",plot,"","guest cannot water the locked plot")
	expect(act("alice","water",plot).ok and w.state.crops[k].wet,"Owner can still water the crop")
	expect(act("alice","plot_water_access",plot,"island").ok and not w.state.crops[k].has("owner_water"),"Owner restores shared watering")
	parity(Perm.can_water(w,"bob",w.state.crops[k]),"bob","water",plot,"","guest can water again after reopening")
	# harvest: helper semantics incl. legacy defaults (policy stays in World).
	var crop:Dictionary=w.state.crops[k]
	crop.growth=float(World.CROPS.radish.time)
	crop.wet=true
	expect(not crop.has("harvest_access"),"fixture is a legacy plot without harvest_access")
	expect(Perm.harvest_access(crop)=="island" and Perm.harvest_access(crop,true)=="owner","legacy access defaults")
	expect(Perm.can_harvest(w,"bob",crop).ok,"legacy: guest may hand-harvest")
	expect(Perm.can_harvest(w,"bob",crop,true).message==Perm.MSG_HARVEST_MACHINE,"legacy: guest harvester refused")
	expect(Perm.can_harvest(w,"alice",crop,true).ok,"owner harvester always allowed")
	crop.harvest_access="friend"
	crop.harvest_friend="carol"
	expect(not Perm.can_harvest(w,"bob",crop).ok,"friend grant excludes other players")
	expect(Perm.can_harvest(w,"carol",crop,true).ok,"friend grant covers the harvester too")
	crop.harvest_access="owner"
	crop.erase("harvest_friend")
	parity(Perm.can_harvest(w,"bob",w.state.crops[k]),"bob","harvest",plot,"","owner-locked harvest")
	w.state.crops[k].harvest_access="island"
	parity(Perm.can_harvest(w,"bob",w.state.crops[k]),"bob","harvest",plot,"","island harvest by guest")
	# dismantle: plot restore is owner-only; ownerless legacy plot is open.
	w.state.crops[k].kind=""
	parity(Perm.can_dismantle(w,"bob",plot),"bob","remove",plot,"","guest restores owner's empty plot")
	w.state.crops[k].erase("owner")
	expect(Perm.can_dismantle(w,"bob",plot).ok,"legacy ownerless empty plot is restorable by anyone")
	parity(Perm.can_dismantle(w,"bob",plot),"bob","remove",plot,"","legacy ownerless plot restore")
	expect(not w.state.crops.has(k),"legacy plot was restored to grass")

func placed_objects() -> void:
	# dismantle: saplings.
	var tree:=Vector2i(39,34)
	w.state.forest[World.key(tree)]={"growth":0.0,"mature":false,"owner":"alice"}
	parity(Perm.can_dismantle(w,"bob",tree),"bob","remove",tree,"","guest lifts owner's sapling")
	parity(Perm.can_dismantle(w,"alice",tree),"alice","remove",tree,"","owner lifts own sapling")
	w.state.forest["0,0"]={"growth":0.0,"mature":false}
	expect(not Perm.can_dismantle(w,"alice",Vector2i(0,0)).ok,"legacy ownerless sapling is denied, not crashed on")
	w.state.forest.erase("0,0")
	# dismantle + take: boxes.
	var box:=Vector2i(37,34)
	var bk:=World.key(box)
	w.state.objects[bk]={"type":"private_chest","owner":"alice","items":{"wood":1}}
	parity(Perm.can_dismantle(w,"bob",box),"bob","remove",box,"","guest dismantles owner's chest")
	parity(Perm.can_dismantle(w,"bob",box,true),"bob","move_object",box,"37,35","guest moves owner's chest")
	expect(Perm.can_dismantle(w,"alice",box,true).ok,"owner may move own chest")
	parity(Perm.can_take("bob",w.state.objects[bk]),"bob","withdraw",box,"wood","guest withdraws from private chest")
	parity(Perm.can_take("bob",w.state.objects[bk]),"bob","deposit",box,"wood","guest deposits into private chest")
	parity(Perm.can_take("alice",w.state.objects[bk]),"alice","withdraw",box,"wood","owner withdraws from private chest")
	w.state.objects[bk]={"type":"chest","owner":"alice","items":{"wood":1}}
	parity(Perm.can_take("bob",w.state.objects[bk]),"bob","withdraw",box,"wood","shared chest is open to guests")
	expect(Perm.can_take("bob",{"type":"supply_box","owner":"alice","items":{}}).message==Perm.MSG_FOREIGN_BOX,"supply box is private")
	expect(not Perm.can_take("alice",{"type":"private_chest","items":{}}).ok,"legacy ownerless private chest is denied")
	expect(Perm.can_dismantle(w,"bob",Vector2i(36,36)).ok,"empty cell: nothing for ownership to refuse")

func public_areas() -> void:
	var path:=Vector2i(40,30)
	expect(Perm.public_area(w,path),"fixture: (40,30) is a public path")
	parity(Perm.can_place(w,"alice",path,"chest"),"alice","build",path,"chest","build on public path")
	expect(Perm.can_place(w,"alice",Vector2i(55,40),"floor").message==Perm.MSG_PUBLIC,"river rejects placement")
	expect(Perm.can_place(w,"alice",path,"chest",true).message==Perm.MSG_PUBLIC,"blueprint rejects public path")
	expect(Perm.can_place(w,"alice",path,"seed:radish").message==Perm.MSG_PUBLIC,"sowing rejects public path")
	# remove bypasses protected(): an owned piece on a public tile can be lifted.
	var legacy:=Vector2i(40,31)
	w.state.ground[World.key(legacy)]={"type":"path","owner":"alice","items":{}}
	expect(Perm.public_area(w,legacy),"fixture: (40,31) is public")
	parity(Perm.can_dismantle(w,"bob",legacy),"bob","remove",legacy,"","guest removes owner's piece on public tile")
	parity(Perm.can_dismantle(w,"alice",legacy),"alice","remove",legacy,"","owner removes own piece on public tile")

func ferry_access() -> void:
	w=World.new()
	w.add_player("alice","阿米")
	w.add_player("bob","小豆",World.WANGAN_COAST.FERRY_LANDING)
	var lane:Rect2i=World.WANGAN_COAST.FERRY_ACCESS
	for x in range(lane.position.x,lane.end.x):
		var tile:=Vector2i(x,lane.position.y)
		expect(w.protected(tile) and w.can_stand(Vector2(tile)+Vector2(0.5,0.5)),"Ferry access is protected and walkable at "+str(tile))
		var builder:String="alice" if x%2==0 else "bob"
		var player:Dictionary=w.state.players[builder]
		player.x=x+0.5
		player.y=31.5
		player.inventory.wood=40
		var before:Dictionary=w.state.duplicate(true)
		expect(not act(builder,"build",tile,"wall").ok and w.state==before,"No member can wall off ferry access at "+str(tile))
	var target:=Vector2i(50,30)
	var blueprint:={"version":1,"name":"渡口測試牆","width":1,"height":1,"pieces":[{"kind":"wall","x":0,"y":0}]}
	w.state.players.alice.x=50.5
	w.state.players.alice.y=31.5
	var quote:Dictionary=w.quote_blueprint("alice",blueprint,target)
	expect(not quote.ok and quote.get("problems",[]).any(func(problem):return problem.reason==Perm.MSG_PUBLIC),"Blueprint preview rejects walls because the ferry lane is public")
	var legacy:=Vector2i(49,30)
	w.state.objects[World.key(legacy)]={"type":"chest","owner":"alice","items":{}}
	w.state.players.bob.x=48.5
	w.state.players.bob.y=31.5
	expect(act("bob","remove",legacy).message==Perm.MSG_FOREIGN_OBJECT,"A neighboring player cannot dismantle an older owner's chest")
	expect(act("alice","remove",legacy).ok and w.protected(legacy),"Owner can clear an older object and the lane stays protected")
	var movable:=Vector2i(49,31)
	w.state.objects[World.key(movable)]={"type":"chest","owner":"alice","items":{}}
	var before_move:Dictionary=w.state.duplicate(true)
	expect(not act("alice","move_object",movable,World.key(legacy)).ok and w.state==before_move,
		"Moving furniture onto the lane is refused without moving the source")
	var old_plot:=Vector2i(50,30)
	w.state.crops[World.key(old_plot)]={"kind":"radish","growth":90.0,"wet":false,"remaining":1,"owner":"alice"}
	expect(act("alice","water",old_plot).ok and act("alice","harvest",old_plot).ok,"An older crop can finish its current cycle on the lane")
	expect(not act("alice","seed",old_plot,"radish").ok and act("alice","remove",old_plot).ok,"The old plot can be cleared without reopening the lane to planting")
	w.state.players.bob.x=World.WANGAN_COAST.FERRY_LANDING.x
	w.state.players.bob.y=World.WANGAN_COAST.FERRY_LANDING.y
	for step in 32:w.move_player("bob",Vector2.LEFT,0.25/3.6)
	expect(w.state.players.bob.x==44.5,"New arrival can walk from the landing to the public square")

func floors() -> void:
	var roof_cell:=Vector2i(40,34)
	w.state.ground[World.key(roof_cell)]={"type":"floor","owner":"bob","items":{}}
	parity(Perm.can_place(w,"alice",roof_cell,"roof"),"alice","build",roof_cell,"roof","roof on another player's floor")
	parity(Perm.can_place(w,"bob",roof_cell,"roof"),"bob","build",roof_cell,"roof","roof on own floor")
	# Manual build keeps today's rule: objects may sit on someone else's floor.
	var furniture:=Vector2i(41,34)
	w.state.ground[World.key(furniture)]={"type":"floor","owner":"bob","items":{}}
	w.state.players.alice.inventory.wood=100
	parity(Perm.can_place(w,"alice",furniture,"chest"),"alice","build",furniture,"chest","manual chest on foreign floor")
	# Blueprint-only rule (world.gd:2582).
	var bp:=Vector2i(42,34)
	w.state.ground[World.key(bp)]={"type":"floor","owner":"bob","items":{}}
	expect(Perm.can_place(w,"alice",bp,"chest",true).message==Perm.MSG_BLUEPRINT_FLOOR,"blueprint object refused on foreign floor")
	expect(Perm.can_place(w,"bob",bp,"chest",true).ok,"blueprint object allowed on own floor")
	expect(Perm.can_place(w,"alice",bp,"floor",true).ok,"blueprint ground kinds skip the floor-owner rule")

## Tea garden and flower nursery: sowing/harvest are owner-only; ownerless
## legacy beds cannot be sown by anyone. Module-only (no live travel here).
func regional_sowing() -> void:
	for spec in [[World.REGIONS.Bamboo.REGION,World.REGIONS.Bamboo.TEA_BEDS.position,Perm.MSG_TEA_SEED],
			[World.FLOWER_NURSERY.REGION,World.FLOWER_NURSERY.NURSERY_BEDS.position,World.FLOWER_NURSERY.FOREIGN_PLOT_MESSAGE]]:
		var region:String=spec[0]
		var p:Vector2i=spec[1]
		var k:=World.key(p)
		w.switch_region(region)
		expect(not Perm.public_area(w,p),"%s fixture bed is not public"%region)
		w.state.crops[k]={"kind":"","growth":0.0,"wet":false,"owner":"alice","harvest_access":"island"}
		expect(Perm.can_place(w,"alice",p,"seed:bluebell").ok,"%s owner sows"%region)
		expect(Perm.can_place(w,"bob",p,"seed:bluebell").message==spec[2],"%s guest sowing refused"%region)
		var harvest_ok:bool=Perm.can_harvest(w,"bob",w.state.crops[k]).ok
		expect(harvest_ok==(region!=World.FLOWER_NURSERY.REGION),"%s guest harvest follows can_harvest_plot"%region)
		w.state.crops[k].erase("owner")
		expect(not Perm.can_place(w,"alice",p,"seed:bluebell").ok and not Perm.can_place(w,"bob",p,"seed:bluebell").ok,"%s legacy ownerless bed cannot be sown"%region)
		w.state.crops.erase(k)
		w.switch_region(World.REGIONS.HOME)
