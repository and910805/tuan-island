extends SceneTree
## C13 麵粉磨坊 pure rules (no World mutation, no scene). Run:
##   godot --headless --path game --script res://tests/test_mill_c13.gd
##
## Contract pinned here (content bible C13: 3x3, 25 wood / 15 stone / 4 woodwork_parts, flour and feed, one
## cleared passable directional entrance):
##   - id `mill` is kept. A legacy placed mill (kit, no `mill_part`) is one cell forever; a new mill is 3x3,
##     row-major, part 0 = north-west anchor, every cell carries `mill_part` 0..8 + the same `mill_facing` 0..3.
##   - facing 0 = entrance on the south side, then clockwise: 1 west, 2 north, 3 east. The entrance is the
##     middle cell of that side (part 7 / 3 / 1 / 5) and is the ONLY walkable cell of the nine.
##   - the cell in front of the entrance is MILL_FRONT_OFFSETS[facing] and must stay open.
##   - the mill is NOT in ORIENTABLE_FOOTPRINTS / FIXED_SQUARE_STATIONS (that would make every legacy mill 3x3).
const World=preload("res://scripts/world.gd")
const I=World.INDUSTRY
const Fx=preload("res://tests/mill_c13_fixture.gd")
## Independent copies of the geometry (not read from industry.gd): facing -> [entrance part, entrance cell, front cell].
const SPEC:={
	0:[7,Vector2i(1,2),Vector2i(1,3)],
	1:[3,Vector2i(0,1),Vector2i(-1,1)],
	2:[1,Vector2i(1,0),Vector2i(1,-1)],
	3:[5,Vector2i(2,1),Vector2i(3,1)],
}
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)

func run()->void:
	cost_and_catalog()
	footprint_and_entrances()
	legacy_is_one_cell()
	passage_rules()
	front_lookup()
	print("MILL_C13_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

func materials(recipe:Dictionary)->Dictionary:
	var out:={}
	for item in recipe:
		if str(item)!="name":out[str(item)]=int(recipe[item])
	return out

func cost_and_catalog()->void:
	expect(materials(World.BUILD.mill)==Fx.COST,"BUILD.mill is exactly 25 wood + 15 stone + 4 woodwork_parts: "+str(World.BUILD.mill))
	expect(str(World.BUILD.mill.name)=="麵粉磨坊","BUILD.mill keeps its player-facing name")
	expect(not World.CRAFT.has("mill_kit"),"mill_kit is no longer a bench recipe")
	expect(World.NAMES.has("mill_kit"),"the legacy mill_kit item still exists for old backpacks")
	expect(materials(World.LEGACY_MILL_COST)=={"mill_kit":1},"a legacy 1x1 mill is built from / refunds exactly one mill_kit")
	expect("mill" in World.KITCHEN_GATED,"the mill stays gated on the opened public kitchen")
	expect("mill" in World.UNDO_SOLID,"the mill is a solid type (its entrance is the one passage exception)")
	expect("mill" not in I.ORIENTABLE_FOOTPRINTS and "mill" not in I.FIXED_SQUARE_STATIONS and "mill" not in I.EXPANDABLE_STATIONS,"the mill must not join a table that gives every legacy mill a footprint")
	expect(World.LOGISTICS.PROCESSORS.has("mill") and World.LOGISTICS.input_field("mill")=="input_wheat","wheat -> flour processing still uses the input_wheat buffer")
	expect(I.PROCESS.flour.station=="mill" and I.PROCESS.feed.station=="mill","flour and feed are still processed at the mill")
	expect(World.processing_recipes("mill").keys()==["flour","feed"],"the mill still offers flour and feed")

func footprint_and_entrances()->void:
	var list:=I.station_cells("mill")
	expect(list.size()==9 and list==I.mill_cells(),"the footprint is nine cells")
	var seen:={}
	for index in list.size():
		var spot:Vector2i=list[index]
		var row_index:=floori(index/3.0)
		expect(spot==Vector2i(index%3,row_index),"cell %d is row-major (%d,%d)"%[index,index%3,row_index])
		seen[spot]=true
	expect(seen.size()==9,"nine distinct cells")
	expect(I.square_part_field("mill")=="mill_part" and I.MILL_FACING=="mill_facing","field names are mill_part / mill_facing")
	for facing in 4:
		var row:Array=SPEC[facing]
		expect(I.MILL_ENTRANCE_PARTS[facing]==row[0],"facing %d: entrance is part %d"%[facing,row[0]])
		expect(I.mill_entrance_offset(facing)==row[1] and list[row[0]]==row[1],"facing %d: entrance cell %s"%[facing,str(row[1])])
		expect(I.mill_front_offset(facing)==row[2],"facing %d: the open front cell is %s"%[facing,str(row[2])])
		var step:Vector2i=row[2]-row[1]
		expect(absi(step.x)+absi(step.y)==1 and not list.has(row[2]),"facing %d: the front cell touches the entrance and lies outside the footprint"%facing)
		expect(row[0] not in [0,2,4,6,8],"facing %d: the entrance is never a corner or the centre, so the anchor is always solid"%facing)
	# Clockwise: one quarter turn (x,y) -> (2-y,x) carries each facing's entrance onto the next facing's.
	for facing in 4:
		var now:Vector2i=I.mill_entrance_offset(facing)
		var turned:=Vector2i(2-now.y,now.x)
		expect(turned==I.mill_entrance_offset((facing+1)%4),"a clockwise quarter turn maps facing %d onto facing %d"%[facing,(facing+1)%4])

func legacy_is_one_cell()->void:
	var legacy:={"type":"mill","owner":Fx.A,"items":{},"input_wheat":0,"auto_enabled":false}
	expect(I.square_part(legacy)==-1 and not I.is_new_mill(legacy) and not I.is_mill_extension(legacy) and not I.is_mill_entrance(legacy),"a mill without mill_part is a legacy 1x1")
	expect(not I.is_folded_passage(legacy),"a legacy mill stays solid")
	expect(not I.is_vertical(legacy),"a mill is never vertical")
	var broken:={"type":"mill","owner":Fx.A,"items":{},"mill_part":"x"}
	expect(I.square_part(broken)==-1,"a non-numeric mill_part reads as legacy (save validation rejects it)")
	var anchor:={"type":"mill","owner":Fx.A,"items":{},"mill_part":0,"mill_facing":2}
	expect(I.square_part(anchor)==0 and I.is_new_mill(anchor) and not I.is_mill_extension(anchor),"part 0 is the new mill's anchor")
	expect(I.mill_facing(anchor)==2,"facing is read back")
	expect(I.mill_facing({"type":"mill","mill_part":0})==0,"a missing facing reads as 0")
	var other:={"type":"stove","owner":Fx.A,"items":{},"mill_part":3}
	expect(not I.is_new_mill(other),"only the mill type can be a mill part")

func passage_rules()->void:
	for facing in 4:
		var open_cells:=0
		for part in 9:
			var piece:Dictionary={"type":"mill","owner":Fx.A,"items":{},"mill_part":part,"mill_facing":facing}
			var passable:=I.is_folded_passage(piece)
			expect(passable==(part==SPEC[facing][0]),"facing %d part %d: passable only on the entrance"%[facing,part])
			expect(I.is_mill_entrance(piece)==passable,"facing %d part %d: is_mill_entrance matches"%[facing,part])
			expect(I.is_mill_extension(piece)==(part>0),"facing %d part %d: cells 1..8 are extensions"%[facing,part])
			if passable:open_cells+=1
		expect(open_cells==1,"facing %d: exactly one of the nine cells is walkable"%facing)

func front_lookup()->void:
	var objects:={}
	var anchor:=Vector2i(10,10)
	for facing in 4:
		objects.clear()
		objects[World.key(anchor)]={"type":"mill","owner":Fx.A,"items":{},"mill_part":0,"mill_facing":facing}
		var spot:Vector2i=anchor+SPEC[facing][2]
		expect(I.is_mill_front(objects,spot),"facing %d: the front cell is recognised"%facing)
		expect(not I.is_mill_front(objects,spot,anchor),"facing %d: a mill being moved ignores its own front"%facing)
		for other in 4:
			if other!=facing:expect(not I.is_mill_front(objects,anchor+SPEC[other][2]),"facing %d does not claim facing %d's front"%[facing,other])
		expect(not I.is_mill_front(objects,anchor+Vector2i(1,1)),"the middle of the footprint is not a front cell")
	# A legacy mill and a non-anchor cell never claim a front.
	objects.clear()
	objects[World.key(anchor)]={"type":"mill","owner":Fx.A,"items":{}}
	expect(not I.is_mill_front(objects,anchor+Vector2i(1,3)),"a legacy 1x1 mill has no entrance front")
	objects.clear()
	objects[World.key(anchor)]={"type":"mill","owner":Fx.A,"items":{},"mill_part":1,"mill_facing":0}
	expect(not I.is_mill_front(objects,anchor+Vector2i(1,3)),"only the anchor claims a front")
