extends SceneTree
## C13 麵粉磨坊 and conveyor logistics. Pure World.step, no scene.
## Run: godot --headless --path game --script res://tests/test_mill_c13_logistics.gd
##
## Pins: a belt touching ANY of the nine cells (or the walkable entrance) delivers into the one wheat buffer that
## lives on the anchor; a belt behind ANY cell pulls the one flour stack; automatic wheat -> flour runs once per
## mill (never once per cell); caps, filters and owners behave like the legacy 1x1 mill; a legacy 1x1 mill keeps
## working on the very same code path.
const World=preload("res://scripts/world.gd")
const I=World.INDUSTRY
const L=World.LOGISTICS
const Fx=preload("res://tests/mill_c13_fixture.gd")
const A:=Fx.A
const B:=Fx.B
const ANCHOR:=Fx.ANCHOR
## Independent copy: belts around the 3x3 as [offset from the anchor, dir INTO the mill, dir OUT of the mill].
## dir: 0 up, 1 right, 2 down, 3 left.
const RING:=[
	[Vector2i(0,-1),2,0],[Vector2i(1,-1),2,0],[Vector2i(2,-1),2,0],
	[Vector2i(0,3),0,2],[Vector2i(1,3),0,2],[Vector2i(2,3),0,2],
	[Vector2i(-1,0),1,3],[Vector2i(-1,1),1,3],[Vector2i(-1,2),1,3],
	[Vector2i(3,0),3,1],[Vector2i(3,1),3,1],[Vector2i(3,2),3,1],
]
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
	deliver_from_every_side()
	delivery_rules()
	automatic_processing_once()
	pull_from_every_side()
	legacy_mill_still_works()
	print("MILL_C13_LOGISTICS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

func belt(w:World,tile:Vector2i,direction:int,items:Dictionary,filter:="wheat",owner:=A)->void:
	w.state.objects[World.key(tile)]={"type":"conveyor","owner":owner,"items":items.duplicate(),"enabled":true,"dir":direction,"filter":filter}

func mill_world(facing:int)->World:
	var w:=Fx.world()
	Fx.place(w,ANCHOR,facing)
	return w

## Sum of one item over every cell of the mill: the conservation check that catches a duplicated buffer.
func buffers(w:World,field:String)->int:
	var total:=0
	for tile in Fx.cells(ANCHOR):total+=int(Fx.obj(w,tile).get(field,0))
	return total

func flour_total(w:World)->int:
	var total:=0
	for tile in Fx.cells(ANCHOR):total+=int(Fx.obj(w,tile).get("items",{}).get("flour",0))
	for key in w.state.objects:
		var piece:Dictionary=w.state.objects[key]
		if piece.get("type")=="conveyor":total+=int(piece.items.get("flour",0))
	return total

func deliver_from_every_side()->void:
	for facing in 4:
		for row in RING:
			var w:=mill_world(facing)
			var at:Vector2i=ANCHOR+row[0]
			belt(w,at,row[1],{"wheat":1})
			expect(w.step(2,true),"facing %d belt %s: the tick commits"%[facing,str(row[0])])
			expect(Fx.obj(w,at).items.is_empty(),"facing %d belt %s: the belt handed its wheat over"%[facing,str(row[0])])
			expect(int(Fx.obj(w,ANCHOR).input_wheat)==1 and buffers(w,"input_wheat")==1,"facing %d belt %s: exactly one wheat, in the anchor's buffer"%[facing,str(row[0])])
	# Two belts into two different cells in the same tick: both land, once each, in the one buffer.
	var w:=mill_world(0)
	belt(w,ANCHOR+Vector2i(0,-1),2,{"wheat":1})
	belt(w,ANCHOR+Vector2i(3,2),3,{"wheat":1})
	expect(w.step(2,true) and int(Fx.obj(w,ANCHOR).input_wheat)==2 and buffers(w,"input_wheat")==2,"two belts into different cells fill the same buffer (conserved)")
	# The walkable entrance is a door, not a hole: a belt facing it delivers like any other cell.
	w=mill_world(1)
	belt(w,Fx.front(ANCHOR,1),1,{"wheat":1})
	expect(w.step(2,true) and int(Fx.obj(w,ANCHOR).input_wheat)==1,"a belt facing the entrance delivers to the anchor")

func delivery_rules()->void:
	# Buffer cap (32): a full mill keeps the item on the belt.
	var w:=mill_world(2)
	w.state.objects[World.key(ANCHOR)].input_wheat=32
	var at:=ANCHOR+Vector2i(2,3)
	belt(w,at,0,{"wheat":1})
	expect(w.step(2,true) and Fx.obj(w,at).items.get("wheat",0)==1 and int(Fx.obj(w,ANCHOR).input_wheat)==32,"a full wheat buffer pushes back on the belt")
	# One short of the cap accepts exactly one more.
	w.state.objects[World.key(ANCHOR)].input_wheat=31
	expect(w.step(2,true) and int(Fx.obj(w,ANCHOR).input_wheat)==32 and Fx.obj(w,at).items.is_empty(),"31 + 1 reaches the cap and no further")
	# Wrong filter: only wheat goes in.
	w=mill_world(0)
	belt(w,ANCHOR+Vector2i(-1,1),1,{"wood":1},"wood")
	expect(w.step(2,true) and Fx.obj(w,ANCHOR+Vector2i(-1,1)).items.get("wood",0)==1 and buffers(w,"input_wheat")==0,"a wood belt cannot feed the mill")
	# Another player's belt does not feed this player's mill.
	w=mill_world(0)
	belt(w,ANCHOR+Vector2i(1,-1),2,{"wheat":1},"wheat",B)
	expect(w.step(2,true) and Fx.obj(w,ANCHOR+Vector2i(1,-1)).items.get("wheat",0)==1 and buffers(w,"input_wheat")==0,"a foreign belt cannot feed the mill")
	# Disabled belts do nothing.
	w=mill_world(0)
	belt(w,ANCHOR+Vector2i(1,-1),2,{"wheat":1})
	w.state.objects[World.key(ANCHOR+Vector2i(1,-1))].enabled=false
	expect(w.step(2,true) and buffers(w,"input_wheat")==0,"a disabled belt does not move")
	# Offline ticks do not move anything either.
	w=mill_world(0)
	belt(w,ANCHOR+Vector2i(1,-1),2,{"wheat":1})
	expect(w.step(2,false) and buffers(w,"input_wheat")==0,"an offline tick pauses the belt")

func automatic_processing_once()->void:
	var w:=mill_world(3)
	var head:Dictionary=w.state.objects[World.key(ANCHOR)]
	head.input_wheat=4
	head.auto_enabled=true
	expect(w.step(2,true),"the tick that starts the job commits")
	head=Fx.obj(w,ANCHOR)
	expect(head.has("job") and head.job.auto==true and head.job.kind=="flour" and int(head.input_wheat)==2,"auto mode takes one batch (2 wheat) into one job on the anchor")
	for tile in Fx.cells(ANCHOR).slice(1):
		expect(not Fx.obj(w,tile).has("job") and int(Fx.obj(w,tile).get("input_wheat",0))==0,"cell %s never starts a job or holds wheat"%World.key(tile))
	expect(buffers(w,"input_wheat")==2,"the buffer total is conserved across the nine cells")
	expect(w.step(61,true),"the finishing tick commits")
	expect(flour_total(w)>=1 and int(Fx.obj(w,ANCHOR).items.get("flour",0))>=1,"the finished job puts flour on the anchor")
	for tile in Fx.cells(ANCHOR).slice(1):
		expect(Fx.obj(w,tile).items.is_empty(),"cell %s holds no flour of its own"%World.key(tile))
	# Run until the whole buffer is processed: 4 wheat make exactly 2 flour, never 2 x 9.
	for tick in 4:w.step(61,true)
	expect(flour_total(w)==2 and int(Fx.obj(w,ANCHOR).input_wheat)==0,"4 wheat made exactly 2 flour (never one batch per cell): flour %d"%flour_total(w))
	# Manual queue stations are advanced by the queue only: a mill with a queue ignores auto mode and the buffer.
	var queued:=mill_world(0)
	var manual:Dictionary=queued.state.objects[World.key(ANCHOR)]
	manual.processing={"active":{},"waiting":[],"ready":[]}
	manual.input_wheat=4
	manual.auto_enabled=true
	queued.step(2,true)
	expect(not Fx.obj(queued,ANCHOR).has("job"),"a mill carrying a manual queue never gets an automatic job")

func pull_from_every_side()->void:
	for row in RING:
		var w:=mill_world(0)
		w.state.objects[World.key(ANCHOR)].items={"flour":1}
		var at:Vector2i=ANCHOR+row[0]
		belt(w,at,row[2],{},"flour")
		expect(w.step(2,true),"belt %s: the pull tick commits"%str(row[0]))
		expect(Fx.obj(w,at).items.get("flour",0)==1 and Fx.obj(w,ANCHOR).items.is_empty(),"belt %s behind the mill pulls the flour off the anchor"%str(row[0]))
		expect(flour_total(w)==1,"belt %s: one flour in the world, not duplicated"%str(row[0]))
	# Two belts behind two different cells claim the one stack only once.
	var w:=mill_world(0)
	w.state.objects[World.key(ANCHOR)].items={"flour":1}
	belt(w,ANCHOR+Vector2i(0,-1),0,{},"flour")
	belt(w,ANCHOR+Vector2i(2,-1),0,{},"flour")
	expect(w.step(2,true) and flour_total(w)==1 and Fx.obj(w,ANCHOR).items.is_empty(),"two belts pulling the same mill take one flour in total")
	# A foreign belt cannot take another player's flour.
	w=mill_world(0)
	w.state.objects[World.key(ANCHOR)].items={"flour":1}
	belt(w,ANCHOR+Vector2i(1,-1),0,{},"flour",B)
	expect(w.step(2,true) and int(Fx.obj(w,ANCHOR).items.get("flour",0))==1,"a foreign belt cannot pull from the mill")
	# A belt pulling only the wheat filter finds nothing in a mill that holds flour.
	w=mill_world(0)
	w.state.objects[World.key(ANCHOR)].items={"flour":1}
	belt(w,ANCHOR+Vector2i(1,-1),0,{},"wheat")
	expect(w.step(2,true) and int(Fx.obj(w,ANCHOR).items.get("flour",0))==1,"a wheat belt leaves the flour alone")

func legacy_mill_still_works()->void:
	var w:=Fx.world()
	w.state.objects[World.key(ANCHOR)]={"type":"mill","owner":A,"items":{},"input_wheat":0,"auto_enabled":false}
	belt(w,ANCHOR+Vector2i(-1,0),1,{"wheat":1})
	expect(w.step(2,true) and int(Fx.obj(w,ANCHOR).input_wheat)==1,"a belt feeds a legacy 1x1 mill")
	w.state.objects[World.key(ANCHOR)].input_wheat=2
	w.state.objects[World.key(ANCHOR)].auto_enabled=true
	w.step(2,true)
	expect(Fx.obj(w,ANCHOR).has("job") and int(Fx.obj(w,ANCHOR).input_wheat)==0,"a legacy mill still turns its buffer into an automatic job")
	w.step(61,true)
	expect(int(Fx.obj(w,ANCHOR).items.get("flour",0))==1,"and finishes with one flour")
	# Only the one cell exists: the cells that would belong to a 3x3 stay empty.
	expect(not w.state.objects.has(World.key(ANCHOR+Vector2i.RIGHT)) and not w.state.objects.has(World.key(ANCHOR+Vector2i.DOWN)),"a legacy mill never grows extra cells")
	belt(w,ANCHOR+Vector2i(0,-1),0,{},"flour")
	expect(w.step(2,true) and Fx.obj(w,ANCHOR+Vector2i(0,-1)).items.get("flour",0)==1,"a belt behind a legacy mill pulls its flour")
