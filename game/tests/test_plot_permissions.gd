extends SceneTree
## T057: operation-specific plot permission checks (place / take / harvest /
## dismantle). Wherever the live action is reachable from spawn, the module's
## verdict is compared with World.act (same ok, same message on denial, state
## untouched on denial), so the module cannot silently drift from world.gd.
const World=preload("res://scripts/world.gd")
const Perm=preload("res://scripts/plot_permissions.gd")
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
	print("PLOT_PERMISSIONS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

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
	# place(seed): legacy home sowing is open to any member (world.gd:2148).
	parity(Perm.can_place(w,"bob",plot,"seed:radish"),"bob","seed",plot,"radish","guest sows owner's empty home plot")
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
