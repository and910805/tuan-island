extends SceneTree
## T072 blueprint data module, first segment (docs/blueprint-integration.md).
## Expected values below are hand-worked from the contract and the real
## World.BUILD / World.NAMES tables, never recomputed with the module's own
## logic. The snapshot fixture mirrors how world.gd:1607-1619 shapes live
## structures. No persistence: World is only preloaded for its constants.
const World=preload("res://scripts/world.gd")
const LOGISTICS=preload("res://scripts/logistics.gd")
const MINE_DRILL=preload("res://scripts/mine_drill.gd")
const FORESTRY=preload("res://scripts/forestry.gd")
const WATERWORKS=preload("res://scripts/waterworks.gd")
const MODULE_PATH:="res://scripts/blueprint_design.gd"
const API:=["validate","capture","rotate","base_cost"]
const SECTIONS:=["hand_worked_validate_and_cost","all_build_kinds","layer_capacity_boundary","same_cell_duplicates","invalid_validate_inputs","rotation","capture_integration","capture_rejections","base_cost_rejections"]
## Hand-worked copy of the current World.BUILD kind list (30 kinds).
const ALL_KINDS:=["jam_pot","flower_pot","ore_display","floor","wall","path","chest","bench","bed","lamp","door","window","roof","table","chair","stove","private_chest","long_bench","planter","sign","sofa","sprinkler","water_pipe","water_tank","mine_drill","waterworks","water_pump","sawmill","charcoal_kiln","forester","conveyor","mill","seed_maker","loom","glass_furnace","greenhouse_roof","greenhouse_rack","medium_sprinkler","master_flower_bed","rope_rack","sketch_easel","fish_display","author_sign","author_shelf","supply_box","expedition_tent","veg_basket_rack","relay_crate_stack","carp_banner","float_garland","lantern_post","flower_arch","trio_keepsake","water_share_plaque","diversion_gate","mine_lantern","tea_ware","salt_basket","water_tower","keepsake_aru","keepsake_milu","keepsake_bobo","keepsake_chacha","keepsake_achao","keepsake_mianmian","keepsake_xinghe","keepsake_lingpopo","keepsake_xiaoli","keepsake_luoluo","keepsake_diandian","keepsake_nuannuan"]

var checks:=0
var failures:=0
var started:=false
var finished:=false
var bp
var R:Dictionary=World.BUILD
var N:Dictionary=World.NAMES

# ---------------------------------------------------------------- harness

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _process(_delta:float)->bool:
	if not started:
		started=true
		run()
	if not finished:
		expect(false,"test run aborted by a script error before completing")
	if checks==0:
		expect(false,"no checks executed")
	print("BLUEPRINT_DESIGN_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
	return true

func run()->void:
	if load_module():
		for section in SECTIONS:
			expect(call(section)==true,"section %s ran to completion"%section)
	finished=true

## A missing or unparsable module is a counted failure with nonzero exit,
## never a skip.
func load_module()->bool:
	if not ResourceLoader.exists(MODULE_PATH):
		expect(false,"blueprint module missing at "+MODULE_PATH)
		return false
	var script=load(MODULE_PATH)
	if not (script is GDScript) or not script.can_instantiate():
		expect(false,"blueprint module failed to parse/load: "+MODULE_PATH)
		return false
	var depends_on_world:=false
	for value in script.get_script_constant_map().values():
		if value is Script and String(value.resource_path).ends_with("/world.gd"):depends_on_world=true
	expect(not depends_on_world,"module does not preload World (avoids future cyclic preload)")
	bp=script.new()
	expect(bp is RefCounted and not (bp is Node),"module is a plain RefCounted")
	var complete:=true
	for method in API:
		var present:bool=bp.has_method(method)
		expect(present,"API exposes "+method)
		complete=complete and present
	return complete

# ---------------------------------------------------------------- helpers

## Strict deep equality: types must match (int 2 != float 2.0).
func same(a,b)->bool:
	if typeof(a)!=typeof(b):return false
	match typeof(a):
		TYPE_DICTIONARY:
			if a.size()!=b.size():return false
			for key in a:
				if not b.has(key) or not same(a[key],b[key]):return false
			return true
		TYPE_ARRAY:
			if a.size()!=b.size():return false
			for i in a.size():
				if not same(a[i],b[i]):return false
			return true
		TYPE_FLOAT:
			return a==b or (is_nan(a) and is_nan(b))
		_:
			return a==b

func brief(value)->String:
	return str(value).left(400)

func accepted(r,message:String)->bool:
	var good:bool=r is Dictionary and typeof(r.get("ok"))==TYPE_BOOL and r.ok and typeof(r.get("reason"))==TYPE_STRING
	expect(good,message+("" if good else " (got %s)"%brief(r)))
	return good

func rejected(r,message:String)->void:
	var good:bool=r is Dictionary and typeof(r.get("ok"))==TYPE_BOOL and not r.ok and typeof(r.get("reason"))==TYPE_STRING and not String(r.reason).is_empty()
	if good:
		for field in ["blueprint","cost"]:
			var leaked=r.get(field)
			if leaked is Dictionary and not leaked.is_empty():good=false
	expect(good,message+("" if good else " (got %s)"%brief(r)))

func accepted_as(r,expected:Dictionary,field:String,message:String)->void:
	if accepted(r,message+" succeeds"):
		expect(same(r.get(field),expected),message+" exact %s (got %s)"%[field,brief(r.get(field))])

func is_success(r)->bool:
	return r is Dictionary and typeof(r.get("ok"))==TYPE_BOOL and r.ok

func val(raw,recipes:Dictionary=World.BUILD,names:Dictionary=World.NAMES):
	return bp.validate(raw,recipes,names)

func cost(raw,recipes:Dictionary=World.BUILD,names:Dictionary=World.NAMES):
	return bp.base_cost(raw,recipes,names)

func turn(raw,quarter_turns:int,recipes:Dictionary=World.BUILD,names:Dictionary=World.NAMES):
	return bp.rotate(raw,quarter_turns,recipes,names)

func grab(snapshot,owner:String,area:Rect2i,name:String,recipes:Dictionary=World.BUILD,names:Dictionary=World.NAMES):
	return bp.capture(snapshot,owner,area,name,recipes,names)

## Strictly earlier in contract order: layer rank, then y, then x.
func ordered_before(p:Dictionary,q:Dictionary)->bool:
	var a:=[rank(p.kind),int(p.y),int(p.x)]
	var b:=[rank(q.kind),int(q.y),int(q.x)]
	for i in 3:
		if a[i]!=b[i]:return a[i]<b[i]
	return false

func piece(kind,x,y,settings=null)->Dictionary:
	var p:={"kind":kind,"x":x,"y":y}
	if settings!=null:p["settings"]=settings
	return p

func design(name,width,height,pieces:Array)->Dictionary:
	return {"version":1,"name":name,"width":width,"height":height,"pieces":pieces}

func k(x:int,y:int)->String:
	return World.key(Vector2i(x,y))

func materials(kind:String)->Dictionary:
	var out:={}
	for item in World.BUILD[kind]:
		if item!="name":out[item]=World.BUILD[kind][item]
	return out

## Contract layer rank: floor/path ground, roof roofs, everything else objects.
func rank(kind:String)->int:
	if kind in ["floor","path"]:return 0
	if kind in ["roof","greenhouse_roof"]:return 2
	return 1

## Same shape world.gd gives a freshly built structure (lines 1607-1616).
func structure(kind:String,owner:String)->Dictionary:
	var obj:={"type":kind,"owner":owner,"items":{}}
	if kind=="sprinkler":obj.merge({"water":0,"enabled":false,"next_water":4000.0,"last_water":-1.0})
	if kind=="conveyor":obj.merge(LOGISTICS.fresh())
	if kind in LOGISTICS.PROCESSORS:obj.merge({"input_wood":0,"auto_enabled":false})
	if kind=="forester":obj.merge(FORESTRY.fresh(4000.0))
	if kind=="mine_drill":obj.merge(MINE_DRILL.fresh(1),true)
	if kind=="waterworks":obj.merge(WATERWORKS.fresh(),true)
	if kind=="water_tank":obj["water"]=0
	if kind=="water_pump":obj["enabled"]=false
	if kind=="door":obj["open"]=false
	return obj

func auto_roof(owner:String)->Dictionary:
	var roof:=structure("roof",owner)
	roof["auto"]=true
	return roof

# ---------------------------------------------------------------- sections

func hand_worked_validate_and_cost()->bool:
	# Premises: the real recipe numbers the hand totals below rely on.
	expect(same(materials("floor"),{"wood":2}) and same(materials("path"),{"stone":2}) and same(materials("roof"),{"wood":1,"fiber":3}),"premise: floor/path/roof recipes")
	expect(same(materials("ore_display"),{"wood":4,"gold_sample":1}),"premise: ore_display consumes a gold_sample")
	expect(same(materials("conveyor"),{"conveyor_kit":1}) and same(materials("mine_drill"),{"mine_drill_kit":1}) and same(materials("waterworks"),{"waterworks_kit":1}),"premise: devices consume kits")
	# Unsorted input, JSON-style integral floats, padded name.
	var raw:=design("  茶屋一號  ",3.0,2,[
		piece("roof",0,0),
		piece("waterworks",0.0,1),
		piece("conveyor",1,0,{"dir":1.0,"filter":"plank"}),
		piece("path",2,1.0),
		piece("mine_drill",2,0),
		piece("floor",1,0),
		piece("ore_display",0,0),
		piece("floor",0,0),
	])
	var expected:=design("茶屋一號",3,2,[
		piece("floor",0,0),piece("floor",1,0),piece("path",2,1),
		piece("ore_display",0,0),piece("conveyor",1,0,{"dir":1,"filter":"plank"}),piece("mine_drill",2,0),piece("waterworks",0,1),
		piece("roof",0,0),
	])
	var expected_cost:={"wood":9,"stone":2,"fiber":3,"gold_sample":1,"conveyor_kit":1,"mine_drill_kit":1,"waterworks_kit":1}
	var raw_before:=raw.duplicate(true)
	var r=val(raw)
	accepted_as(r,expected,"blueprint","hand-worked validate: ground->objects->roofs, y/x order, ints, trimmed name")
	expect(same(raw,raw_before),"validate leaves the raw input untouched (floats stay floats)")
	if r is Dictionary and r.get("blueprint") is Dictionary and r.blueprint.get("pieces") is Array and r.blueprint.pieces.size()==8:
		var normalized:Dictionary=r.blueprint
		accepted_as(val(normalized),expected,"blueprint","validate(normalized) is idempotent")
		r.blueprint.pieces[4]["settings"]["dir"]=3
		r.blueprint.pieces[0]["x"]=99
		expect(same(raw,raw_before),"mutating the returned blueprint does not reach the raw input")
	accepted_as(cost(raw),expected_cost,"cost","hand-worked base_cost incl gold_sample and device kits")
	accepted_as(cost(expected),expected_cost,"cost","base_cost of normalized form")
	# JSON roundtrip: every number comes back as float.
	var parsed=JSON.parse_string(JSON.stringify(expected))
	expect(parsed is Dictionary and typeof(parsed.get("width"))==TYPE_FLOAT,"premise: JSON roundtrip really yields floats")
	accepted_as(val(parsed),expected,"blueprint","JSON roundtrip validates back to the exact int blueprint")
	accepted_as(cost(parsed),expected_cost,"cost","JSON roundtrip base_cost")
	# Defaults must be explicit so rotating a bare belt rotates its direction too.
	var bare:=design("帶",1,1,[piece("conveyor",0,0)])
	accepted_as(val(bare),design("帶",1,1,[piece("conveyor",0,0,{"dir":0,"filter":"wood"})]),"blueprint","conveyor defaults normalize explicitly")
	accepted_as(turn(bare,1),design("帶",1,1,[piece("conveyor",0,0,{"dir":1,"filter":"wood"})]),"blueprint","bare conveyor rotates clockwise from UP to RIGHT")
	# Boundary names: 32 chars accepted, also after trimming.
	accepted_as(val(design("小".repeat(32),1,1,[piece("lamp",0,0)])),design("小".repeat(32),1,1,[piece("lamp",0,0)]),"blueprint","32-character name accepted")
	accepted_as(val(design("  "+"a".repeat(32)+" ",1,1,[piece("lamp",0,0)])),design("a".repeat(32),1,1,[piece("lamp",0,0)]),"blueprint","name trimmed before the 32 limit")
	return true

func all_build_kinds()->bool:
	var real:=World.BUILD.keys()
	var mine:=ALL_KINDS.duplicate()
	real.sort()
	mine.sort()
	expect(same(real,mine),"premise: hand-worked kind table matches World.BUILD (update totals if recipes changed)")
	for item in ["gold_sample","mine_drill_kit","waterworks_kit","conveyor_kit","forester_kit","sprinkler_kit","pipe_kit","tank_kit","pump_kit","sawmill_kit","kiln_kit","wood","stone","fiber"]:
		expect(N.has(item),"premise: World.NAMES knows "+item)
	for kind in World.BUILD:
		var single:=design("單件",1,1,[piece(kind,0,0)])
		var expected_single:=single.duplicate(true)
		if kind=="conveyor":expected_single.pieces[0]["settings"]={"dir":0,"filter":"wood"}
		accepted_as(val(single),expected_single,"blueprint","every real kind validates alone: "+kind)
		accepted_as(cost(single),materials(kind),"cost","single-piece base_cost equals recipe materials: "+kind)
	var pieces:=[]
	for i in ALL_KINDS.size():
		pieces.append(piece(ALL_KINDS[i],i%16,i/16))
	var all:=design("全部",16,5,pieces)
	var r=val(all)
	if accepted(r,"one of every kind validates"):
		var out:Array=r.blueprint.pieces
		expect(out.size()==ALL_KINDS.size(),"all catalog pieces kept")
		var ordered:=true
		for i in range(1,out.size()):
			if not ordered_before(out[i-1],out[i]):ordered=false
		expect(ordered,"output is ordered ground->objects->roofs then y then x")
		expect(out.size()>2 and out[0].kind=="floor" and out[1].kind=="path" and out[out.size()-1].kind=="greenhouse_roof","floor/path first, roof last")
		var settings_correct:=true
		for p in out:
			if p.kind=="conveyor":settings_correct=settings_correct and p.get("settings",{})=={"dir":0,"filter":"wood"}
			elif p.has("settings"):settings_correct=false
		expect(settings_correct,"only conveyor receives normalized default configuration")
	accepted_as(cost(all),{"wood":187,"stone":56,"fiber":29,"plank":49,"copper_joint":10,"rope":3,"flower_pot":1,"ochre_earth":4,"cotton_cloth":2,"wool_cloth":2,"glass":5,"supply_box_kit":1,"gold_sample":1,"sprinkler_kit":2,"pipe_kit":1,"tank_kit":1,"mine_drill_kit":1,"waterworks_kit":1,"pump_kit":1,"sawmill_kit":1,"kiln_kit":1,"forester_kit":1,"conveyor_kit":1,"mill_kit":1,"veg_basket_rack_kit":1,"relay_crate_stack_kit":1,"carp_banner_kit":1,"float_garland_kit":1,"lantern_post_kit":1,"flower_arch_kit":1,"trio_keepsake_kit":1,"water_share_plaque_kit":1,"diversion_gate_kit":1,"mine_lantern_kit":1,"tea_ware_kit":1,"salt_basket_kit":1,"water_tower_kit":1,"keepsake_aru_kit":1,"keepsake_milu_kit":1,"keepsake_bobo_kit":1,"keepsake_chacha_kit":1,"keepsake_achao_kit":1,"keepsake_mianmian_kit":1,"keepsake_xinghe_kit":1,"keepsake_lingpopo_kit":1,"keepsake_xiaoli_kit":1,"keepsake_luoluo_kit":1,"keepsake_diandian_kit":1,"keepsake_nuannuan_kit":1},"cost","hand-summed base_cost of every real kind")
	var missing:=World.BUILD.duplicate(true)
	missing.erase("conveyor")
	rejected(val(design("帶",1,1,[piece("conveyor",0,0)]),missing),"kind absent from passed recipes rejected")
	return true

func layer_capacity_boundary()->bool:
	var pieces:=[]
	for y in 16:
		for x in 16:
			pieces.append(piece("roof",x,y))
			pieces.append(piece("chair",x,y))
			pieces.append(piece("floor",x,y))
	var full:=design("滿",16,16,pieces)
	var r=val(full)
	if accepted(r,"768 pieces (16x16x3 layers) accepted"):
		expect(r.blueprint.pieces.size()==768,"all 768 kept")
		expect(r.blueprint.pieces[0].kind=="floor" and r.blueprint.pieces[255].kind=="floor" and r.blueprint.pieces[256].kind=="chair" and r.blueprint.pieces[767].kind=="roof","768 layout ordered by layer")
	accepted_as(cost(full),{"wood":2304,"fiber":768},"cost","768-piece base_cost (256x(2+6+1) wood, 256x3 fiber)")
	var over:=pieces.duplicate(true)
	over.append(piece("lamp",0,0))
	rejected(val(design("滿",16,16,over)),"769 pieces rejected")
	var huge:=[]
	huge.resize(200000)
	huge.fill(piece("floor",0,0))
	var t0:=Time.get_ticks_msec()
	rejected(val(design("巨",16,16,huge)),"200000-entry piece list rejected")
	rejected(cost(design("巨",16,16,huge)),"200000-entry piece list rejected by base_cost")
	expect(Time.get_ticks_msec()-t0<3000,"huge list rejected promptly (bounded work)")
	return true

func same_cell_duplicates()->bool:
	rejected(val(design("重",2,2,[piece("floor",0,0),piece("floor",0,0)])),"two floors on one cell rejected")
	rejected(val(design("重",2,2,[piece("floor",1,1),piece("path",1,1)])),"floor+path share ground layer: rejected")
	rejected(val(design("重",2,2,[piece("wall",0,1),piece("chest",0,1)])),"two objects on one cell rejected")
	rejected(val(design("重",2,2,[piece("conveyor",0,0,{"dir":0,"filter":"wood"}),piece("conveyor",0,0)])),"two conveyors on one cell rejected")
	rejected(val(design("重",2,2,[piece("roof",1,0),piece("roof",1,0)])),"two roofs on one cell rejected")
	rejected(val(design("重",2,2,[piece("floor",0,0),piece("floor",0.0,0.0)])),"duplicate detected after float normalization")
	var stacked:=design("疊",1,1,[piece("roof",0,0),piece("chest",0,0),piece("floor",0,0)])
	accepted_as(val(stacked),design("疊",1,1,[piece("floor",0,0),piece("chest",0,0),piece("roof",0,0)]),"blueprint","ground+object+roof on one cell allowed")
	accepted_as(cost(stacked),{"wood":23,"fiber":3},"cost","stacked cell base_cost (2+20+1 wood, 3 fiber)")
	return true

func good()->Dictionary:
	return design("小屋",2,2,[piece("floor",0,0),piece("conveyor",1,1,{"dir":2,"filter":"wood"})])

func with_field(field:String,value)->Dictionary:
	var d:=good()
	d[field]=value
	return d

func without(field:String)->Dictionary:
	var d:=good()
	d.erase(field)
	return d

func with_piece(field:String,value)->Dictionary:
	var d:=good()
	d.pieces[0][field]=value
	return d

func without_piece(field:String)->Dictionary:
	var d:=good()
	d.pieces[0].erase(field)
	return d

func with_settings(settings)->Dictionary:
	var d:=good()
	d.pieces[1]["settings"]=settings
	return d

func invalid_validate_inputs()->bool:
	accepted(val(good()),"baseline for invalid cases validates")
	accepted(val(with_field("width",16)),"width 16 boundary accepted")
	accepted(val(design("角",16,16,[piece("lamp",15,15)])),"16x16 with far corner piece accepted")
	var cases:=[
		["null raw",null],["array raw",[]],["string raw","blueprint"],["int raw",1],
		["version 2",with_field("version",2)],["version 0",with_field("version",0)],["version bool",with_field("version",true)],
		["version string",with_field("version","1")],["version fraction",with_field("version",1.5)],["version nan",with_field("version",NAN)],["version missing",without("version")],
		["empty name",with_field("name","")],["blank name",with_field("name","   ")],["33 ascii",with_field("name","a".repeat(33))],
		["33 cjk",with_field("name","小".repeat(33))],["newline in name",with_field("name","a\nb")],["tab inside name",with_field("name","a\tb")],
		["bell in name",with_field("name","\u0007x")],["del in name",with_field("name","x\u007f")],["name int",with_field("name",5)],["name null",with_field("name",null)],["name missing",without("name")],
		["width 0",with_field("width",0)],["width -1",with_field("width",-1)],["width 17",with_field("width",17)],["width bool",with_field("width",true)],
		["width fraction",with_field("width",1.5)],["width nan",with_field("width",NAN)],["width inf",with_field("width",INF)],["width -inf",with_field("width",-INF)],
		["width 1e300",with_field("width",1e300)],["width 2^40",with_field("width",1<<40)],["width string",with_field("width","2")],["width null",with_field("width",null)],["width missing",without("width")],
		["height 0",with_field("height",0)],["height 17",with_field("height",17)],["height bool",with_field("height",false)],["height fraction",with_field("height",2.5)],
		["height inf",with_field("height",INF)],["height huge int",with_field("height",9223372036854775807)],["height missing",without("height")],
		["unknown top seed",with_field("seed",1)],["unknown top owner",with_field("owner","alice")],["unknown top time",with_field("time",3.0)],
		["pieces string",with_field("pieces","x")],["pieces dict",with_field("pieces",{})],["pieces empty",with_field("pieces",[])],["pieces null",with_field("pieces",null)],["pieces missing",without("pieces")],
		["piece int",with_field("pieces",[5])],["piece null",with_field("pieces",[null])],["piece array",with_field("pieces",[["floor",0,0]])],
		["kind unknown",with_piece("kind","castle")],["kind empty",with_piece("kind","")],["kind case",with_piece("kind","Floor")],
		["kind int",with_piece("kind",5)],["kind null",with_piece("kind",null)],["kind missing",without_piece("kind")],
		["x true",with_piece("x",true)],["x false",with_piece("x",false)],["x nan",with_piece("x",NAN)],["x inf",with_piece("x",INF)],["x -inf",with_piece("x",-INF)],
		["x fraction",with_piece("x",0.5)],["x -1",with_piece("x",-1)],["x == width",with_piece("x",2)],["x 1e20",with_piece("x",1e20)],
		["x 2^40",with_piece("x",1<<40)],["x string",with_piece("x","0")],["x null",with_piece("x",null)],["x missing",without_piece("x")],
		["y true",with_piece("y",true)],["y fraction",with_piece("y",1.25)],["y nan",with_piece("y",NAN)],["y == height",with_piece("y",2)],["y -1",with_piece("y",-1)],["y missing",without_piece("y")],
		["piece owner",with_piece("owner","alice")],["piece items",with_piece("items",{})],["piece auto",with_piece("auto",true)],
		["piece type",with_piece("type","floor")],["piece rot",with_piece("rot",1)],
		["settings on floor",with_piece("settings",{"dir":0,"filter":"wood"})],
		["settings array",with_settings([])],["settings string",with_settings("x")],
		["dir 4",with_settings({"dir":4,"filter":"wood"})],["dir -1",with_settings({"dir":-1,"filter":"wood"})],
		["dir bool",with_settings({"dir":true,"filter":"wood"})],["dir fraction",with_settings({"dir":1.5,"filter":"wood"})],
		["dir nan",with_settings({"dir":NAN,"filter":"wood"})],["dir string",with_settings({"dir":"1","filter":"wood"})],
		["filter unknown",with_settings({"dir":0,"filter":"no_such_item"})],["filter int",with_settings({"dir":0,"filter":5})],
		["filter empty",with_settings({"dir":0,"filter":""})],["filter null",with_settings({"dir":0,"filter":null})],
		["settings enabled",with_settings({"dir":0,"filter":"wood","enabled":true})],["settings items",with_settings({"dir":0,"filter":"wood","items":{"wood":3}})],
	]
	for c in cases:
		rejected(val(c[1]),"validate rejects "+c[0])
	for c in [["width 17",with_field("width",17)],["x nan",with_piece("x",NAN)],["piece owner",with_piece("owner","alice")],["dir 4",with_settings({"dir":4,"filter":"wood"})]]:
		rejected(cost(c[1]),"base_cost also rejects invalid blueprint: "+c[0])
		rejected(turn(c[1],1),"rotate also rejects invalid blueprint: "+c[0])
	return true

func rotation()->bool:
	var raw:=design("Rect",3,2,[piece("floor",0,0),piece("wall",2,0),piece("chair",1,1),piece("conveyor",2,1,{"dir":3,"filter":"wood"}),piece("roof",0,1)])
	var raw_before:=raw.duplicate(true)
	# (x,y)->(h-1-y,x) by hand, h=2 then 3 then 2.
	var rot0:=design("Rect",3,2,[piece("floor",0,0),piece("wall",2,0),piece("chair",1,1),piece("conveyor",2,1,{"dir":3,"filter":"wood"}),piece("roof",0,1)])
	var rot1:=design("Rect",2,3,[piece("floor",1,0),piece("chair",0,1),piece("conveyor",0,2,{"dir":0,"filter":"wood"}),piece("wall",1,2),piece("roof",0,0)])
	var rot2:=design("Rect",3,2,[piece("floor",2,1),piece("conveyor",0,0,{"dir":1,"filter":"wood"}),piece("chair",1,0),piece("wall",0,1),piece("roof",2,0)])
	var rot3:=design("Rect",2,3,[piece("floor",0,2),piece("wall",0,0),piece("conveyor",1,0,{"dir":2,"filter":"wood"}),piece("chair",1,1),piece("roof",1,2)])
	accepted_as(turn(raw,0),rot0,"blueprint","rotate 0 returns normalized original")
	accepted_as(turn(raw,1),rot1,"blueprint","rotate 90 cw on 3x2: dims swap, cells and conveyor dir 3->0")
	accepted_as(turn(raw,2),rot2,"blueprint","rotate 180 on 3x2")
	accepted_as(turn(raw,3),rot3,"blueprint","rotate 270 cw on 3x2")
	expect(same(raw,raw_before),"rotate leaves the input untouched")
	var chained=raw
	for i in 4:
		var step=turn(chained,1)
		if not accepted(step,"chained rotate step %d"%(i+1)):
			break
		chained=step.blueprint
		if i==1:expect(same(chained,rot2),"two 90-degree turns equal one 180")
	expect(same(chained,rot0),"four 90-degree turns restore the original")
	accepted_as(val(rot1),rot1,"blueprint","rotated blueprint re-validates unchanged")
	accepted_as(cost(rot1),{"wood":12,"fiber":3,"conveyor_kit":1},"cost","rotation does not change base_cost (2+3+6+1 wood)")
	var strip:=design("條",16,1,[piece("floor",15,0),piece("lamp",0,0)])
	accepted_as(turn(strip,1),design("條",1,16,[piece("floor",0,15),piece("lamp",0,0)]),"blueprint","16x1 strip becomes 1x16")
	var json_rot=JSON.parse_string(JSON.stringify(raw))
	accepted_as(turn(json_rot,1),rot1,"blueprint","rotate accepts JSON-roundtripped input")
	for bad in [-1,4,5,-4,100]:
		rejected(turn(raw,bad),"rotate rejects quarter_turns %d (no silent mod)"%bad)
	var missing:=World.BUILD.duplicate(true)
	missing.erase("chair")
	rejected(turn(raw,1,missing),"rotate rejects kinds absent from recipes")
	return true

## Integration-shaped current-region snapshot owned mostly by alice.
func tea_snapshot()->Dictionary:
	var ground:={}
	var objects:={}
	var roofs:={}
	ground[k(10,20)]=structure("floor","alice")
	ground[k(11,20)]=structure("floor","alice")
	ground[k(13,22)]=structure("path","alice")
	var chest:=structure("chest","alice")
	chest["items"]={"wood":7,"gold_sample":1}
	objects[k(10,20)]=chest
	var door:=structure("door","alice")
	door["open"]=true
	objects[k(11,20)]=door
	var forester:=structure("forester","alice")
	forester["enabled"]=true
	forester["fuel"]=9
	forester["saplings"]=4
	forester["job"]={"kind":"plank","owner":"alice","ready":4100.0}
	objects[k(13,20)]=forester
	var belt:=structure("conveyor","alice")
	belt["dir"]=2
	belt["enabled"]=true
	belt["filter"]="charcoal"
	belt["items"]={"charcoal":3}
	objects[k(12,21)]=belt
	var drill:=structure("mine_drill","alice")
	drill["enabled"]=true
	drill["fuel"]=5
	drill["items"]={"gold_ore":2}
	objects[k(12,22)]=drill
	roofs[k(10,20)]=auto_roof("alice")
	roofs[k(11,20)]=structure("roof","alice")
	# Foreign neighbours just outside the area (right/bottom edges exclusive).
	objects[k(9,20)]=structure("wall","bob")
	objects[k(14,20)]=structure("wall","bob")
	objects[k(10,23)]=structure("lamp","bob")
	objects[k(13,19)]=structure("lamp","bob")
	ground[k(14,22)]=structure("floor","bob")
	roofs[k(9,20)]=auto_roof("bob")
	# Far-away junk: only reachable by a whole-layer scan.
	objects[k(60,60)]="garbage"
	ground[k(70,10)]={"type":42}
	return {
		"time":4321.5,"seed":99,
		"players":{"alice":{"x":11.5,"y":21.5,"inventory":{"wood":3}},"bob":{"x":12.5,"y":20.5}},
		"crops":{k(12,20):{"type":"radish","owner":"bob","planted":4000.0}},
		"regions":{"far":{"objects":{k(11,21):structure("wall","bob")}}},
		"ground":ground,"objects":objects,"roofs":roofs,
	}

const TEA_AREA:=Rect2i(10,20,4,3)

func tea_expected()->Dictionary:
	return design("茶屋",4,3,[
		piece("floor",0,0),piece("floor",1,0),piece("path",3,2),
		piece("chest",0,0),piece("door",1,0),piece("forester",3,0),
		piece("conveyor",2,1,{"dir":2,"filter":"charcoal"}),
		piece("mine_drill",2,2),
		piece("roof",1,0),
	])

func capture_integration()->bool:
	var snapshot:=tea_snapshot()
	expect(World.is_auto_roof(snapshot.roofs[k(10,20)]) and not World.is_auto_roof(snapshot.roofs[k(11,20)]),"premise: fixture roofs match World.is_auto_roof")
	var before:=snapshot.duplicate(true)
	var r=grab(snapshot,"alice",TEA_AREA,"  茶屋 ")
	accepted_as(r,tea_expected(),"blueprint","capture: relative coords, conveyor settings, own auto roof omitted, edges/crops/regions/far junk ignored")
	expect(same(snapshot,before),"capture leaves the snapshot deeply untouched")
	if is_success(r) and r.get("blueprint") is Dictionary:
		var omitted=r.get("auto_roofs_omitted")
		expect((typeof(omitted)==TYPE_INT and omitted==1) or (omitted is Array and omitted.size()==1),"capture reports exactly one omitted auto roof (got %s)"%brief(omitted))
		var blueprint:Dictionary=r.blueprint
		var keys:=blueprint.keys()
		keys.sort()
		expect(same(keys,["height","name","pieces","version","width"]),"blueprint carries only version-1 fields")
		var clean:=true
		for p in blueprint.get("pieces",[]):
			if not (p is Dictionary):
				clean=false
				continue
			for key in p:
				if not key in ["kind","x","y","settings"]:clean=false
			if p.has("settings"):
				if not (p.settings is Dictionary):
					clean=false
					continue
				var s_keys:Array=p.settings.keys()
				s_keys.sort()
				if p.kind!="conveyor" or not same(s_keys,["dir","filter"]):clean=false
		expect(clean,"pieces carry only kind/x/y (+conveyor dir/filter); mine_drill dir not copied")
		var text:=JSON.stringify(blueprint)
		for secret in ["alice","bob","owner","items","fuel","job","enabled","open","saplings","seed","time","4321","auto","gold_ore","ready"]:
			expect(not text.contains(secret),"captured blueprint does not leak '%s'"%secret)
		accepted_as(val(blueprint),tea_expected(),"blueprint","captured blueprint re-validates unchanged")
		accepted_as(cost(blueprint),{"wood":31,"stone":2,"fiber":5,"forester_kit":1,"conveyor_kit":1,"mine_drill_kit":1},"cost","captured base_cost excludes the omitted auto roof (2+2+20+6+1 wood)")
		blueprint.pieces[6]["settings"]["filter"]="wood"
		blueprint.pieces[0]["x"]=3
		expect(same(snapshot,before),"mutating the captured blueprint does not reach the snapshot")
		var r2=grab(snapshot,"alice",TEA_AREA,"茶屋")
		snapshot.objects[k(12,21)]["dir"]=0
		snapshot.objects[k(12,21)]["filter"]="wood"
		if accepted(r2,"second capture succeeds"):
			expect(same(r2.blueprint,tea_expected()),"later snapshot edits do not reach an earlier capture result")
	var fresh_belt:={"objects":{k(3,4):structure("conveyor","alice")}}
	accepted_as(grab(fresh_belt,"alice",Rect2i(3,4,1,1),"帶"),design("帶",1,1,[piece("conveyor",0,0,{"dir":0,"filter":"wood"})]),"blueprint","fresh conveyor captured with its dir/filter")
	var negative:={"ground":{k(-3,-2):structure("floor","alice")},"objects":{k(-2,-1):structure("lamp","alice")},"roofs":{}}
	accepted_as(grab(negative,"alice",Rect2i(-3,-2,2,2),"負座標"),design("負座標",2,2,[piece("floor",0,0),piece("lamp",1,1)]),"blueprint","negative world coordinates map to relative cells")
	var lone:={"objects":{k(5,5):structure("lamp","alice")}}
	accepted_as(grab(lone,"alice",Rect2i(5,5,1,1),"單燈"),design("單燈",1,1,[piece("lamp",0,0)]),"blueprint","missing ground/roofs layers treated as empty")
	var corner:={"objects":{k(0,0):structure("lamp","alice")}}
	accepted_as(grab(corner,"alice",Rect2i(0,0,16,16),"大"),design("大",16,16,[piece("lamp",0,0)]),"blueprint","16x16 area boundary accepted")
	return true

func tea_with_field(layer:String,x:int,y:int,value)->Dictionary:
	var s:=tea_snapshot()
	s[layer][k(x,y)]=value
	return s

func capture_rejections()->bool:
	var bob_chest:=structure("chest","bob")
	var bad_belt:=structure("conveyor","alice")
	bad_belt["dir"]=7
	var bad_filter:=structure("conveyor","alice")
	bad_filter["filter"]="no_such_item"
	var cases:=[
		["foreign furniture inside",tea_with_field("objects",12,20,structure("lamp","bob"))],
		["foreign chest on own floor",tea_with_field("objects",10,20,bob_chest)],
		["foreign floor inside",tea_with_field("ground",12,20,structure("floor","bob"))],
		["foreign manual roof inside",tea_with_field("roofs",12,21,structure("roof","bob"))],
		["foreign auto roof inside",tea_with_field("roofs",12,21,auto_roof("bob"))],
		["foreign auto roof over own floor",tea_with_field("roofs",11,20,auto_roof("bob"))],
		["owner missing",tea_with_field("objects",12,20,{"type":"lamp","items":{}})],
		["owner int",tea_with_field("objects",12,20,{"type":"lamp","owner":5,"items":{}})],
		["unknown type",tea_with_field("objects",12,20,{"type":"castle","owner":"alice","items":{}})],
		["type missing",tea_with_field("objects",12,20,{"owner":"alice","items":{}})],
		["type int",tea_with_field("objects",12,20,{"type":7,"owner":"alice","items":{}})],
		["entry string",tea_with_field("objects",12,20,"junk")],
		["entry null",tea_with_field("objects",12,20,null)],
		["entry array",tea_with_field("roofs",12,20,[])],
		["own conveyor dir 7",tea_with_field("objects",12,20,bad_belt)],
		["own conveyor unknown filter",tea_with_field("objects",12,20,bad_filter)],
	]
	for c in cases:
		rejected(grab(c[1],"alice",TEA_AREA,"茶屋"),"capture rejects "+c[0])
	var bad_objects:=tea_snapshot()
	bad_objects["objects"]=[]
	rejected(grab(bad_objects,"alice",TEA_AREA,"茶屋"),"capture rejects non-Dictionary objects layer")
	var bad_ground:=tea_snapshot()
	bad_ground["ground"]="x"
	rejected(grab(bad_ground,"alice",TEA_AREA,"茶屋"),"capture rejects non-Dictionary ground layer")
	var bad_roofs:=tea_snapshot()
	bad_roofs["roofs"]=7
	rejected(grab(bad_roofs,"alice",TEA_AREA,"茶屋"),"capture rejects non-Dictionary roofs layer")
	rejected(grab([],"alice",TEA_AREA,"茶屋"),"capture rejects array snapshot")
	rejected(grab(null,"alice",TEA_AREA,"茶屋"),"capture rejects null snapshot")
	rejected(grab(tea_snapshot(),"bob",TEA_AREA,"茶屋"),"capture as bob rejects alice's structures")
	rejected(grab(tea_snapshot(),"",TEA_AREA,"茶屋"),"capture with empty owner rejected")
	rejected(grab(tea_snapshot(),"alice",Rect2i(30,30,3,3),"空"),"empty area rejected")
	rejected(grab({"roofs":{k(0,0):auto_roof("alice")}},"alice",Rect2i(0,0,1,1),"空"),"area with only own auto roof is empty: rejected")
	rejected(grab({"roofs":{k(0,0):auto_roof("bob")}},"alice",Rect2i(0,0,1,1),"空"),"area with only foreign auto roof rejected")
	rejected(grab(tea_snapshot(),"alice",TEA_AREA,""),"capture rejects empty name")
	rejected(grab(tea_snapshot(),"alice",TEA_AREA,"a\nb"),"capture rejects control-char name")
	rejected(grab(tea_snapshot(),"alice",TEA_AREA,"a".repeat(33)),"capture rejects 33-char name")
	var missing:=World.BUILD.duplicate(true)
	missing.erase("forester")
	rejected(grab(tea_snapshot(),"alice",TEA_AREA,"茶屋",missing),"capture rejects type absent from passed recipes")
	rejected(grab(tea_snapshot(),"alice",Rect2i(10,20,0,3),"茶屋"),"zero-width area rejected")
	rejected(grab(tea_snapshot(),"alice",Rect2i(10,20,4,0),"茶屋"),"zero-height area rejected")
	rejected(grab(tea_snapshot(),"alice",Rect2i(14,23,-4,-3),"茶屋"),"negative-size area rejected")
	var corner:={"objects":{k(0,0):structure("lamp","alice")}}
	rejected(grab(corner,"alice",Rect2i(0,0,17,1),"寬"),"17-wide area rejected")
	rejected(grab(corner,"alice",Rect2i(0,0,1,17),"高"),"17-tall area rejected")
	var t0:=Time.get_ticks_msec()
	rejected(grab(corner,"alice",Rect2i(0,0,100000,100000),"巨"),"enormous area rejected")
	expect(Time.get_ticks_msec()-t0<1000,"enormous area rejected without scanning it")
	rejected(grab({"objects":{k(10001,0):structure("lamp","alice")}},"alice",Rect2i(10001,0,1,1),"遠"),"area beyond +10000 rejected")
	rejected(grab({"objects":{k(-10001,5):structure("lamp","alice")}},"alice",Rect2i(-10001,5,1,1),"遠"),"area beyond -10000 rejected")
	return true

func base_cost_rejections()->bool:
	var floors:=design("地",2,2,[piece("floor",0,0),piece("floor",1,0),piece("floor",0,1),piece("floor",1,1)])
	var pair:=design("地",2,1,[piece("floor",0,0),piece("floor",1,0)])
	for c in [["unknown material",{"name":"x","unobtainium":2}],["zero",{"name":"x","wood":0}],["negative",{"name":"x","wood":-2}],
			["fraction",{"name":"x","wood":1.5}],["string amount",{"name":"x","wood":"2"}],["bool amount",{"name":"x","wood":true}],
			["nan",{"name":"x","wood":NAN}],["inf",{"name":"x","wood":INF}],["null amount",{"name":"x","wood":null}],
			["recipe array",[]],["recipe string","floor"]]:
		var recipes:=World.BUILD.duplicate(true)
		recipes["floor"]=c[1]
		var recipes_before:=recipes.duplicate(true)
		rejected(cost(pair,recipes),"base_cost rejects bad recipe: "+c[0])
		expect(same(recipes,recipes_before),"base_cost does not mutate recipes: "+c[0])
	var big:=World.BUILD.duplicate(true)
	big["floor"]={"name":"x","wood":500000000}
	accepted_as(cost(pair,big),{"wood":1000000000},"cost","total of exactly 1e9 accepted")
	big["floor"]={"name":"x","wood":600000000}
	rejected(cost(pair,big),"total above 1e9 rejected")
	big["floor"]={"name":"x","wood":2000000000}
	rejected(cost(design("地",1,1,[piece("floor",0,0)]),big),"single recipe above 1e9 rejected")
	big["floor"]={"name":"x","wood":4611686018427387904}
	rejected(cost(floors,big),"4 x 2^62 (wraps to 0 in int64) rejected")
	var names:=World.NAMES.duplicate(true)
	names.erase("gold_sample")
	rejected(cost(design("架",1,1,[piece("ore_display",0,0)]),R,names),"material absent from passed item_names rejected")
	accepted_as(cost(design("架",1,1,[piece("ore_display",0,0)])),{"wood":4,"gold_sample":1},"cost","ore_display base_cost with real tables")
	return true
