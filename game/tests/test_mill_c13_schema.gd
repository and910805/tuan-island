extends SceneTree
## C13 麵粉磨坊 save-schema load validation (SaveSchema.validate on hand-built world states).
## Run: godot --headless --path game --script res://tests/test_mill_c13_schema.gd
##
## No version bump: a legacy 1x1 mill (no mill_part) validates exactly as before; a new mill needs all nine cells,
## the same owner and facing on each, `mill_part` 0..8 matching its position, `mill_facing` 0..3, and machine
## state (wheat buffer, auto switch, output, job, queue) on the anchor only. Everything else is rejected whole.
const World=preload("res://scripts/world.gd")
const I=World.INDUSTRY
const Fx=preload("res://tests/mill_c13_fixture.gd")
const A:=Fx.A
const B:=Fx.B
const ANCHOR:=Fx.ANCHOR
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
	accepted_shapes()
	rejected_shapes()
	print("MILL_C13_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

## A schema-valid base world: the mill is written straight into the layer.
func base(facing:int=0)->Dictionary:
	var w:=Fx.world()
	Fx.place(w,ANCHOR,facing)
	var state:Dictionary=w.state.duplicate(true)
	Fx.quiet_kitchen(state)
	return state

func ok(state:Dictionary)->bool:
	return bool(World.SAVE_SCHEMA.validate(state.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME))

func cell(state:Dictionary,part:int)->Dictionary:
	return state.objects[World.key(Fx.cells(ANCHOR)[part])]

func accepted_shapes()->void:
	for facing in 4:
		expect(ok(base(facing)),"facing %d: a complete new mill validates"%facing)
	# JSON round trip turns every number into a float: still valid.
	var state:=base(2)
	var parsed:Variant=JSON.parse_string(JSON.stringify(state))
	expect(parsed is Dictionary and ok(parsed),"a new mill survives the JSON round trip (float numbers)")
	# A busy anchor is fine: wheat, switch, output and a job live on the anchor only.
	state=base(1)
	var head:=cell(state,0)
	head.input_wheat=17
	head.auto_enabled=true
	head.items={"flour":3}
	expect(ok(state),"an anchor with a wheat buffer, auto mode and flour output validates")
	# Legacy 1x1 mills are untouched: no mill_part, no mill_facing, buffers as before.
	var w:=Fx.world()
	w.state.objects[World.key(ANCHOR)]={"type":"mill","owner":A,"items":{},"input_wheat":5,"auto_enabled":true}
	var legacy:Dictionary=w.state.duplicate(true)
	Fx.quiet_kitchen(legacy)
	expect(ok(legacy),"a legacy 1x1 mill validates exactly as before")
	w.state.objects[World.key(ANCHOR)]={"type":"mill","owner":A,"items":{"flour":2},"input_wheat":0,"auto_enabled":false}
	legacy=w.state.duplicate(true)
	Fx.quiet_kitchen(legacy)
	expect(ok(legacy),"a legacy 1x1 mill holding flour validates")
	# A legacy mill beside a new mill is fine.
	state=base(0)
	state.objects[World.key(Fx.DEST)]={"type":"mill","owner":A,"items":{},"input_wheat":0,"auto_enabled":false}
	expect(ok(state),"a legacy mill next to a new mill validates")
	# Two new mills with different facings.
	var both:=Fx.world()
	Fx.place(both,ANCHOR,0)
	Fx.place(both,Fx.DEST,3)
	var pair:Dictionary=both.state.duplicate(true)
	Fx.quiet_kitchen(pair)
	expect(ok(pair),"two new mills with different facings validate")

func rejected_shapes()->void:
	var state:Dictionary
	# Incomplete footprint: every one of the nine cells is required.
	for part in 9:
		state=base(0)
		state.objects.erase(World.key(Fx.cells(ANCHOR)[part]))
		expect(not ok(state),"cell %d missing is rejected"%part)
	# Wrong part numbers.
	for bad in [-1,9,1.5,"2",null,true]:
		state=base(0)
		cell(state,4)[I.MILL_PART]=bad
		expect(not ok(state),"mill_part %s is rejected"%str(bad))
	state=base(0)
	cell(state,5)[I.MILL_PART]=4
	expect(not ok(state),"two cells claiming part 4 are rejected")
	state=base(0)
	var swapped:Variant=cell(state,2)[I.MILL_PART]
	cell(state,2)[I.MILL_PART]=cell(state,3)[I.MILL_PART]
	cell(state,3)[I.MILL_PART]=swapped
	expect(not ok(state),"swapped part numbers are rejected")
	# Facing: out of range, wrong type, missing, or not the same on every cell.
	for bad in [-1,4,1.5,"0",null,true]:
		state=base(1)
		cell(state,0)[I.MILL_FACING]=bad
		expect(not ok(state),"anchor mill_facing %s is rejected"%str(bad))
	for part in [1,4,8]:
		state=base(1)
		cell(state,part)[I.MILL_FACING]=2
		expect(not ok(state),"cell %d with a different facing is rejected"%part)
		state=base(1)
		cell(state,part).erase(I.MILL_FACING)
		expect(not ok(state),"cell %d without a facing is rejected"%part)
	state=base(0)
	cell(state,0).erase(I.MILL_PART)
	expect(not ok(state),"an anchor that lost its part number leaves eight orphans")
	# Fields on the wrong thing.
	state=base(0)
	var legacy_with_facing:={"type":"mill","owner":A,"items":{},"input_wheat":0,"auto_enabled":false,I.MILL_FACING:1}
	state.objects[World.key(Fx.DEST)]=legacy_with_facing
	expect(not ok(state),"mill_facing without mill_part is rejected")
	state=base(0)
	state.objects[World.key(Fx.DEST)]={"type":"stove","owner":A,"items":{},I.MILL_PART:0,I.MILL_FACING:0}
	expect(not ok(state),"mill_part on another type is rejected")
	state=base(0)
	state.objects[World.key(Fx.DEST)]={"type":"stove","owner":A,"items":{},I.MILL_FACING:0}
	expect(not ok(state),"mill_facing on another type is rejected")
	state=base(0)
	state.ground[World.key(Fx.DEST)]={"type":"mill","owner":A,"items":{},I.MILL_PART:0,I.MILL_FACING:0}
	expect(not ok(state),"a mill in the ground layer is rejected")
	# Ownership: one cell owned by somebody else.
	state=base(0)
	cell(state,6)["owner"]=B
	expect(not ok(state),"a cell with another owner is rejected")
	# Machine state on an extension cell: never a second machine.
	for field in [["input_wheat",0],["input_wheat",3],["auto_enabled",false],["auto_enabled",true]]:
		for part in [1,4,7]:
			state=base(0)
			cell(state,part)[field[0]]=field[1]
			expect(not ok(state),"cell %d carrying %s is rejected"%[part,str(field[0])])
	state=base(0)
	cell(state,3).items={"flour":1}
	expect(not ok(state),"flour on an extension cell is rejected")
	state=base(0)
	cell(state,3).job={"kind":"flour","owner":A,"ready":100.0,"ingredients":{"wheat":2},"yield":1}
	expect(not ok(state),"a job on an extension cell is rejected")
	state=base(0)
	cell(state,3).processing={"active":{},"waiting":[],"ready":[]}
	expect(not ok(state),"a queue on an extension cell is rejected")
	# The anchor still needs its own machine state.
	state=base(0)
	cell(state,0).erase("input_wheat")
	expect(not ok(state),"an anchor without its wheat buffer is rejected")
	state=base(0)
	cell(state,0).erase("auto_enabled")
	expect(not ok(state),"an anchor without its auto switch is rejected")
	state=base(0)
	cell(state,0).input_wheat=33
	expect(not ok(state),"a wheat buffer above the cap of 32 is rejected")
	state=base(0)
	cell(state,0).items={"wood":1}
	expect(not ok(state),"output other than flour is rejected")
	# A cell moved off its slot breaks the 3x3 shape.
	state=base(0)
	var piece:Dictionary=state.objects[World.key(Fx.cells(ANCHOR)[8])]
	state.objects.erase(World.key(Fx.cells(ANCHOR)[8]))
	state.objects[World.key(ANCHOR+Vector2i(4,4))]=piece
	expect(not ok(state),"a part displaced from its slot is rejected")
	# The untouched base still validates (no test mutated shared data).
	expect(ok(base(0)),"the pristine base still validates")
