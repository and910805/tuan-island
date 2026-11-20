extends SceneTree
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const A:="undo-schema-owner"
const AT:=Vector2i(50,26)
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func valid(s:Dictionary)->bool:
	return Schema.validate(s,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)
func _initialize()->void:run.call_deferred()
func run()->void:
	var world:=World.new()
	world.add_player(A,"保存試作")
	world.undo_clock_utc=func():return 1800000000.0
	world.undo_clock_ticks=func():return 1000
	world.state.players[A].x=48.5
	world.state.players[A].y=26.5
	world.state.players[A].inventory.wood=100
	check(world.act(A,"build","build",AT,"floor").ok,"real construction creates history")
	check(world.undo_summary(A).available,"fixture undo available")
	var baseline:Dictionary=JSON.parse_string(JSON.stringify(world.state))
	check(valid(baseline.duplicate(true)),"live history JSON validates")
	var tile:=World.key(AT)
	var mutations:Array[Callable]=[
		func(s):s.construction=null,
		func(s):s.construction={"serial":1},
		func(s):s.construction.serial=-1,
		func(s):s.construction.serial=1.5,
		func(s):s.construction.serial=true,
		func(s):s.construction.last=[],
		func(s):s.construction.last["ghost"]=s.construction.last[A],
		func(s):s.construction.last[A].id="c999",
		func(s):s.construction.last[A].id="c01",
		func(s):s.construction.last[A].region="unknown",
		func(s):s.construction.last[A].expires_utc+=60,
		func(s):s.construction.last[A].created_utc=-1,
		func(s):s.construction.last[A].status="whatever",
		func(s):s.construction.last[A].builds=0,
		func(s):s.construction.last[A].record.actor="ghost",
		func(s):s.construction.last[A].watch.clear(),
		func(s):s.construction.last[A].watch["f:"+tile]="not-a-hash",
		func(s):s.construction.last[A].record.inventory_deltas[A].wood=1.5,
		func(s):s.construction.last[A].record.inventory_deltas[A].wood=1000000001,
		func(s):s.construction.last[A].record.inventory_deltas[A]["imaginary_item"]=1,
		func(s):s.construction.last[A].record.changes.ground[tile].after.type="sawmill",
		func(s):s.construction.last[A].record.changes.ground[tile].after.owner="ghost",
		func(s):s.construction.last[A].record.changes.ground[tile].after.items.wood=-1,
		func(s):s.construction.last[A].record.changes.ground[tile].after.auto=true,
	]
	for i in mutations.size():
		var candidate:Dictionary=baseline.duplicate(true)
		mutations[i].call(candidate)
		check(not valid(candidate),"malformed history rejected #%d"%i)
	check(world.state.construction.last[A].status=="live","schema checks never touched live world")
	var old:=baseline.duplicate(true)
	old.version=17;old.erase("public_kitchen")
	old.erase("flower_nursery")
	old.regions.erase("tianwei")
	old.erase("salt_pan")
	old.regions.erase("beimen")
	old.erase("construction")
	var old_objects:Dictionary=old.objects.duplicate(true)
	var old_ground:Dictionary=old.ground.duplicate(true)
	check(valid(old) and old.version==preload("res://scripts/save_schema.gd").VERSION,"v17 migration")
	check(old.construction.last.is_empty(),"migration invents no history")
	check(old.objects==old_objects and old.ground==old_ground,"migration preserves construction layers")
	var id:String=world.undo_summary(A).id
	check(world.act(A,"undo","undo_build",AT,id).ok,"consume fixture")
	var consumed:Dictionary=JSON.parse_string(JSON.stringify(world.state))
	check(valid(consumed),"consumed history roundtrips")
	check(not world.act(A,"undo-again","undo_build",AT,id).ok,"consumed record not reusable")
	print("CONSTRUCTION_UNDO_SCHEMA_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
