extends SceneTree
## C13 麵粉磨坊 through the REAL World.act path (build / collision / interaction / remove / move / undo / save).
## Pure World, no scene. Run: godot --headless --path game --script res://tests/test_mill_c13_world.gd
##
## Pins: explicit "mill:<0-3>" builds the 3x3 with that facing; a plain "mill" keeps the legacy kit meaning while a
## mill_kit is held (1x1, one kit) and otherwise builds a facing-0 3x3; the entrance is the one walkable cell and
## the cell in front of it must stay open (build, move, undo, solid placement, saplings); every action on any of the
## nine cells acts on the anchor exactly once; remove / move / undo treat the nine cells as one piece; refunds are
## exact and once; the legacy 1x1 mill is unchanged.
const World=preload("res://scripts/world.gd")
const I=World.INDUSTRY
const Sources=preload("res://scripts/material_sources.gd")
const Fx=preload("res://tests/mill_c13_fixture.gd")
const A:=Fx.A
const B:=Fx.B
const ANCHOR:=Fx.ANCHOR
const FAR_CELL:=Vector2i(42,35)
var checks:=0
var failures:=0
var paths:Array[String]=[]

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)

func run()->void:
	build_four_facings()
	legacy_and_default_meaning()
	build_refusals()
	front_guard()
	interaction_from_every_cell()
	chest_sources()
	remove_and_refund()
	move_scenarios()
	undo_scenarios()
	save_and_reload()
	for path in paths:
		for suffix in ["",".bak",".tmp",".staged",".writer-lock",".corrupt"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("MILL_C13_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

func snap(w:World)->String:
	return var_to_str(w.state)

func refuse(w:World,token:String,verb:String,tile:Vector2i,extra:String,label:String,needle:="")->Dictionary:
	var before:=snap(w)
	var result:=Fx.act(w,token,verb,tile,extra)
	expect(result.get("ok",true)==false and str(result.get("message","")).length()>0,label+": refused with a reason, got "+str(result))
	expect(snap(w)==before,label+": nothing charged, nothing changed")
	if needle!="":expect(str(result.get("message","")).contains(needle),label+": the reason names '%s': %s"%[needle,str(result.get("message",""))])
	return result

func built(facing:int,at:=ANCHOR)->World:
	var w:=Fx.world()
	var result:=Fx.act(w,A,"build",at,"mill:%d"%facing)
	expect(result.get("ok",false)==true,"fixture: build facing %d: %s"%[facing,str(result.get("message",""))])
	return w

func clear_site_geometry()->void:
	var w:=Fx.world()
	for anchor:Vector2i in [ANCHOR,Fx.DEST,Fx.SHIFT]:
		var spots:Array=[]
		spots.append_array(Fx.cells(anchor))
		for facing in 4:spots.append(Fx.front(anchor,facing))
		for tile:Vector2i in spots:
			expect(w.is_land(tile) and not w.water(tile) and not w.protected(tile) and w.resource(tile)=="" and not w.state.objects.has(World.key(tile)) and not w.blocked(tile),"fixture site cell %s is clear land"%World.key(tile))
	expect(w.can_stand(Fx.WEST) and w.can_stand(Fx.MOVER) and w.can_stand(Fx.PARK),"fixture standing spots are walkable")
	expect(w.kitchen_opened(),"fixture: the public kitchen counts as opened")

# ------------------------------------------------------------------- build --

func build_four_facings()->void:
	clear_site_geometry()
	for facing in 4:
		var w:=Fx.world()
		var wood:=Fx.bag(w,"wood")
		var stone:=Fx.bag(w,"stone")
		var parts:=Fx.bag(w,"woodwork_parts")
		var builds:=int(w.state.players[A].builds)
		var result:=Fx.act(w,A,"build",ANCHOR,"mill:%d"%facing)
		expect(result.get("ok",false)==true,"facing %d: build: %s"%[facing,str(result.get("message",""))])
		expect(Fx.parts_ok(w,ANCHOR,facing),"facing %d: nine parts, same owner and facing, buffers only on the anchor"%facing)
		expect(Fx.bag(w,"wood")==wood-25 and Fx.bag(w,"stone")==stone-15 and Fx.bag(w,"woodwork_parts")==parts-4,"facing %d: cost exactly 25 wood + 15 stone + 4 woodwork_parts"%facing)
		expect(int(w.state.players[A].builds)==builds+1,"facing %d: one build counted"%facing)
		var head:Dictionary=Fx.obj(w,ANCHOR)
		expect(int(head.input_wheat)==0 and head.auto_enabled==false and not head.has("job") and not head.has("processing"),"facing %d: a new mill is idle with an empty wheat buffer"%facing)
		expect(not head.has("input_wood") and not head.has("mill_kit"),"facing %d: no wood buffer, no kit marker"%facing)
		var door:=Fx.entrance(ANCHOR,facing)
		var list:=Fx.cells(ANCHOR)
		for tile in list:
			var walkable:bool=tile==door
			var solid:bool=not walkable
			expect(w.blocked(tile)==solid and w.can_stand(Fx.centre(tile))==walkable,"facing %d: cell %s %s"%[facing,World.key(tile),"is the walkable entrance" if walkable else "blocks"])
		expect(not w.blocked(Fx.front(ANCHOR,facing)) and w.can_stand(Fx.centre(Fx.front(ANCHOR,facing))),"facing %d: the cell in front of the entrance is open"%facing)
		# The entrance leads out: walk from the doorway to the open cell in front with the same foot box.
		expect(w.can_stand(Fx.centre(door)) and w.can_stand(Fx.centre(Fx.front(ANCHOR,facing))),"facing %d: a person fits in the doorway and on the front cell"%facing)
		expect(Fx.valid(w),"facing %d: the world validates with the mill"%facing)
		# One person standing in the doorway never blocked the build and is never trapped by it.
	# A person standing exactly in the doorway does not block placement.
	for facing in 4:
		var w:=Fx.world()
		Fx.put(w,B,Fx.centre(Fx.entrance(ANCHOR,facing)))
		expect(Fx.act(w,A,"build",ANCHOR,"mill:%d"%facing).get("ok",false)==true,"facing %d: someone standing in the doorway does not block the build"%facing)
		expect(w.can_stand(Vector2(w.state.players[B].x,w.state.players[B].y)),"facing %d: that person stands on a walkable cell afterwards"%facing)

func legacy_and_default_meaning()->void:
	# 1. A held mill_kit keeps the old meaning of a plain "mill": one 1x1 mill, one kit, no materials.
	var w:=Fx.world()
	w.state.players[A].inventory["mill_kit"]=1
	var wood:=Fx.bag(w,"wood")
	var result:=Fx.act(w,A,"build",ANCHOR,"mill")
	expect(result.get("ok",false)==true,"kit held: a plain mill build succeeds: "+str(result.get("message","")))
	var legacy:=Fx.obj(w,ANCHOR)
	expect(legacy.get("type")=="mill" and not legacy.has("mill_part") and not legacy.has("mill_facing") and int(legacy.get("input_wheat",-1))==0,"kit held: the result is a legacy 1x1 mill")
	expect(Fx.bag(w,"mill_kit")==0 and Fx.bag(w,"wood")==wood and Fx.bag(w,"stone")==200 and Fx.bag(w,"woodwork_parts")==20,"kit held: exactly the kit was consumed, no materials")
	expect(not w.state.objects.has(World.key(ANCHOR+Vector2i.RIGHT)) and not w.state.objects.has(World.key(ANCHOR+Vector2i.DOWN)),"kit held: no other cell was written")
	expect(w.blocked(ANCHOR) and not w.can_stand(Fx.centre(ANCHOR)),"the legacy mill blocks its one cell")
	expect(Fx.valid(w),"a world with a legacy mill validates")
	var removed:=Fx.act(w,A,"remove",ANCHOR,"")
	expect(removed.get("ok",false)==true and Fx.bag(w,"mill_kit")==1 and Fx.bag(w,"wood")==wood and Fx.bag(w,"woodwork_parts")==20 and not w.state.objects.has(World.key(ANCHOR)),"removing a legacy mill refunds exactly its kit")
	# 2. No kit: a plain "mill" is the new facing-0 mill.
	w=Fx.world()
	expect(Fx.bag(w,"mill_kit")==0,"fixture: no kit")
	result=Fx.act(w,A,"build",ANCHOR,"mill")
	expect(result.get("ok",false)==true and Fx.parts_ok(w,ANCHOR,0),"no kit: a plain mill build is the new 3x3 facing 0: "+str(result.get("message","")))
	expect(Fx.bag(w,"wood")==275 and Fx.bag(w,"woodwork_parts")==16,"no kit: it paid the new materials")
	# 3. An explicit facing never consumes a held kit.
	w=Fx.world()
	w.state.players[A].inventory.mill_kit=2
	result=Fx.act(w,A,"build",ANCHOR,"mill:3")
	expect(result.get("ok",false)==true and Fx.parts_ok(w,ANCHOR,3) and Fx.bag(w,"mill_kit")==2 and Fx.bag(w,"stone")==185,"an explicit facing builds the 3x3 from materials and keeps the kits")
	# 4. Removing a new mill never refunds a kit; the kit count of a legacy backpack is untouched.
	var removed_new:=Fx.act(w,A,"remove",ANCHOR+Vector2i(1,1),"")
	expect(removed_new.get("ok",false)==true and Fx.bag(w,"mill_kit")==2 and Fx.bag(w,"stone")==200 and Fx.bag(w,"wood")==300 and Fx.bag(w,"woodwork_parts")==20,"removing a new mill refunds its materials and no kit")
	# 5. Both shapes can stand side by side.
	w=Fx.world()
	w.state.players[A].inventory["mill_kit"]=1
	expect(Fx.act(w,A,"build",Fx.DEST,"mill").get("ok",false)==true,"fixture: legacy mill at DEST")
	expect(Fx.act(w,A,"build",ANCHOR,"mill:0").get("ok",false)==true and Fx.parts_ok(w,ANCHOR,0) and not Fx.obj(w,Fx.DEST).has("mill_part"),"a new mill and a legacy mill coexist")
	expect(Fx.valid(w),"a world with both shapes validates")

func build_refusals()->void:
	var w:=Fx.world()
	for text in ["mill:4","mill:-1","mill:","mill:x","mill:01","mill:1.0"]:
		refuse(w,A,"build",ANCHOR,text,"facing %s"%text)
	refuse(w,A,"build",ANCHOR,"mill:0@nope","unknown style")
	# Kitchen gate (new shape and legacy shape).
	w=Fx.world()
	w.state.public_kitchen=World.SAVE_SCHEMA.public_kitchen_fresh()
	refuse(w,A,"build",ANCHOR,"mill:0","new mill before the kitchen opens",World.MILL_LOCKED_MSG)
	w.state.players[A].inventory.mill_kit=1
	refuse(w,A,"build",ANCHOR,"mill","legacy mill before the kitchen opens",World.MILL_LOCKED_MSG)
	# Materials: each one short on its own.
	for item in ["wood","stone","woodwork_parts"]:
		w=Fx.world()
		w.state.players[A].inventory[item]=int(Fx.COST[item])-1
		refuse(w,A,"build",ANCHOR,"mill:0","one %s short"%item,"材料不足")
	# Out of reach.
	w=Fx.world()
	Fx.put(w,A,Vector2(49.5,39.5))
	refuse(w,A,"build",ANCHOR,"mill:0","out of reach")
	# A clipped footprint (an object inside any of the nine cells), whole refusal.
	for part in [0,4,8]:
		w=Fx.world()
		var inside:Vector2i=Fx.cells(ANCHOR)[part]
		w.state.objects[World.key(inside)]={"type":"chest","owner":A,"items":{}}
		refuse(w,A,"build",ANCHOR,"mill:0","object in cell %d"%part)
	# A blocked front for every facing: a wall, a closed door and a chest each wall the entrance in.
	for facing in 4:
		for kind in ["wall","chest"]:
			w=Fx.world()
			w.state.objects[World.key(Fx.front(ANCHOR,facing))]={"type":kind,"owner":A,"items":{}}
			refuse(w,A,"build",ANCHOR,"mill:%d"%facing,"%s in front of facing %d"%[kind,facing],"入口")
		w=Fx.world()
		w.state.objects[World.key(Fx.front(ANCHOR,facing))]={"type":"door","owner":A,"items":{},"open":false}
		refuse(w,A,"build",ANCHOR,"mill:%d"%facing,"closed door in front of facing %d"%facing,"入口")
		w=Fx.world()
		w.state.objects[World.key(Fx.front(ANCHOR,facing))]={"type":"door","owner":A,"items":{},"open":true}
		expect(Fx.act(w,A,"build",ANCHOR,"mill:%d"%facing).get("ok",false)==true,"an open door in front of facing %d leaves the entrance walkable"%facing)
	# A passable object in front does not block (a sign), but every other facing's front is irrelevant.
	w=Fx.world()
	w.state.objects[World.key(Fx.front(ANCHOR,0))]={"type":"sign","owner":A,"items":{}}
	expect(Fx.act(w,A,"build",ANCHOR,"mill:0").get("ok",false)==true,"a walkable object in front of the entrance does not block")
	# Someone inside a solid cell: refused whole. The actor counts too.
	for part in [0,4,6]:
		w=Fx.world()
		Fx.put(w,B,Fx.centre(Fx.cells(ANCHOR)[part]))
		refuse(w,A,"build",ANCHOR,"mill:0","a player stands in solid cell %d"%part,"人")
	w=Fx.world()
	Fx.put(w,A,Fx.centre(ANCHOR+Vector2i(1,1)))
	refuse(w,A,"build",ANCHOR,"mill:0","the builder stands in the middle")
	# A guest cannot build on the owner's floor, and the public kitchen cells stay out of reach of the footprint.
	w=Fx.world()
	refuse(w,A,"build",Vector2i(36,33),"mill:0","the public kitchen site is protected")

func front_guard()->void:
	for facing in 4:
		var w:=built(facing)
		w.state.players[A].stories["aru"]=3
		var door_front:=Fx.front(ANCHOR,facing)
		# Stand one cell beyond the front cell (outside the footprint, within reach of the front cell).
		Fx.put(w,A,Fx.centre(door_front+(door_front-Fx.entrance(ANCHOR,facing))))
		for kind in ["chest","wall","private_chest","table"]:
			refuse(w,A,"build",door_front,kind,"%s on the front cell of facing %d"%[kind,facing],"入口")
		var sign_result:=Fx.act(w,A,"build",door_front,"sign")
		expect(sign_result.get("ok",false)==true and not w.blocked(door_front),"facing %d: a walkable sign may stand in front"%facing)
		expect(w.tree_planting_problem(A,door_front).contains("入口"),"facing %d: a sapling may not take the front cell"%facing)
	# A second mill whose footprint would cover the first mill's front cell.
	var first:=built(0)
	var overlap:=Vector2i(40,36)
	Fx.put(first,A,Vector2(39.5,36.5))
	refuse(first,A,"build",overlap,"mill:0","a second mill covering the first mill's front cell","入口")
	# A legacy kit mill is solid too: it may not stand on the front cell.
	var legacy:=built(0)
	legacy.state.players[A].inventory.mill_kit=1
	refuse(legacy,A,"build",Fx.front(ANCHOR,0),"mill","a legacy mill on the front cell","入口")

# ------------------------------------------------------------- interaction --

func interaction_from_every_cell()->void:
	var list:=Fx.cells(ANCHOR)
	for part in list.size():
		var w:=built(part%4)
		var click:Vector2i=list[part]
		var wheat:=Fx.bag(w,"wheat")
		var queued:=Fx.act(w,A,"queue_processing",click,"flour")
		expect(queued.get("ok",false)==true,"queue flour by clicking cell %d: %s"%[part,str(queued.get("message",""))])
		expect(Fx.bag(w,"wheat")==wheat-2,"cell %d: exactly two wheat taken, once"%part)
		expect(Fx.obj(w,ANCHOR).has("processing") and Fx.parts_ok(w,ANCHOR,part%4),"cell %d: the queue lives on the anchor"%part)
		for other in range(1,list.size()):
			expect(not Fx.obj(w,list[other]).has("processing") and not Fx.obj(w,list[other]).has("job"),"cell %d click: extension cell %d holds no queue"%[part,other])
		w.state.time=float(w.state.time)+61.0
		var other_cell:Vector2i=list[(part+4)%9]
		var claimed:=Fx.act(w,A,"claim_processing",other_cell,"")
		expect(claimed.get("ok",false)==true and Fx.bag(w,"flour")==1,"cell %d: claimed through cell %d, one flour"%[part,(part+4)%9])
		var again:=Fx.act(w,A,"claim_processing",click,"")
		expect(again.get("ok",true)==false and Fx.bag(w,"flour")==1,"cell %d: a second claim cannot duplicate flour"%part)
		expect(Fx.valid(w),"cell %d: the world validates after a processed job"%part)
	# Feed, switch, take back (the buffer actions) from an extension cell; only the anchor changes.
	var w:=built(0)
	var wheat:=Fx.bag(w,"wheat")
	expect(Fx.act(w,A,"feed_processing",FAR_CELL,"").get("ok",false)==true,"feed wheat from a far cell")
	expect(int(Fx.obj(w,ANCHOR).input_wheat)==4 and Fx.bag(w,"wheat")==wheat-4,"four wheat entered the anchor buffer, once")
	for other in range(1,9):
		expect(not Fx.obj(w,Fx.cells(ANCHOR)[other]).has("input_wheat"),"feeding never writes a buffer on cell %d"%other)
	expect(Fx.act(w,A,"toggle_auto_processing",FAR_CELL,"").get("ok",false)==true and Fx.obj(w,ANCHOR).auto_enabled==true,"the auto switch flips on the anchor")
	expect(not Fx.obj(w,FAR_CELL).has("auto_enabled"),"the switch never lands on an extension cell")
	expect(Fx.act(w,A,"toggle_auto_processing",ANCHOR,"").get("ok",false)==true,"switch it off again")
	expect(Fx.act(w,A,"unload_processing_input",FAR_CELL,"").get("ok",false)==true and int(Fx.obj(w,ANCHOR).input_wheat)==0 and Fx.bag(w,"wheat")==wheat,"unloading from a far cell returns the wheat once")
	refuse(w,A,"collect_processing_output",FAR_CELL,"","nothing to collect")
	# The direct entry points resolve an extension key too (defence in depth).
	var direct:=w.operate_logistics(A,World.key(FAR_CELL),"feed_processing","")
	expect(direct.get("ok",false)==true and int(Fx.obj(w,ANCHOR).input_wheat)==4 and not Fx.obj(w,FAR_CELL).has("input_wheat"),"operate_logistics on an extension key acts on the anchor")
	# Owner only: a guest cannot queue on the owner's mill from any cell.
	Fx.put(w,B,Fx.WEST+Vector2(-0.5,0.0))
	refuse(w,B,"queue_processing",FAR_CELL,"flour","a guest queues on the owner's mill")
	# Out of reach is measured to the nearest cell.
	Fx.put(w,A,Vector2(46.5,38.5))
	refuse(w,A,"queue_processing",ANCHOR,"flour","queueing from beyond reach")

func chest_sources()->void:
	var w:=built(0)
	w.state.objects[World.key(Vector2i(39,33))]={"type":"chest","owner":A,"items":{"wheat":2}}
	w.state.objects[World.key(Vector2i(43,35))]={"type":"chest","owner":A,"items":{}}
	w.state.objects[World.key(Fx.front(ANCHOR,0))]={"type":"chest","owner":A,"items":{}}
	var list:=Sources.candidates(w.state.objects,A,ANCHOR)
	var cells:Array=[]
	for entry:Dictionary in list:cells.append(str(entry.cell))
	expect(cells.has("39,33") and cells.has("43,35"),"chests touching the 3x3 are material sources: "+str(cells))
	expect(not cells.has(World.key(Fx.front(ANCHOR,0))),"the cell in front of the entrance is never a source")
	expect(Sources.candidates(w.state.objects,A,FAR_CELL).is_empty(),"an extension cell is not a station of its own")
	expect(Sources.candidates(w.state.objects,B,ANCHOR).is_empty(),"the mill is owner-only")
	var prepared:=Fx.act(w,A,"prepare_material_box",FAR_CELL,"39,33")
	expect(prepared.get("ok",false)==true,"prepare resolves a clicked extension cell to the anchor: "+str(prepared.get("message","")))
	# A legacy 1x1 mill keeps its four cardinal neighbours.
	var old:=Fx.world()
	old.state.objects[World.key(ANCHOR)]={"type":"mill","owner":A,"items":{},"input_wheat":0,"auto_enabled":false}
	old.state.objects[World.key(ANCHOR+Vector2i.UP)]={"type":"chest","owner":A,"items":{}}
	old.state.objects[World.key(ANCHOR+Vector2i.ONE)]={"type":"chest","owner":A,"items":{}}
	var old_cells:Array=[]
	for entry:Dictionary in Sources.candidates(old.state.objects,A,ANCHOR):old_cells.append(str(entry.cell))
	expect(old_cells==[World.key(ANCHOR+Vector2i.UP)],"a legacy mill only reaches its four cardinal neighbours: "+str(old_cells))

# ------------------------------------------------------------------ remove --

func remove_and_refund()->void:
	for part in 9:
		var w:=Fx.world()
		var before:Dictionary=Fx.world().state.players[A].inventory.duplicate(true)
		expect(Fx.act(w,A,"build",ANCHOR,"mill:%d"%(part%4)).get("ok",false)==true,"fixture: build for remove %d"%part)
		var click:Vector2i=Fx.cells(ANCHOR)[part]
		var result:=Fx.act(w,A,"remove",click,"")
		expect(result.get("ok",false)==true,"remove by clicking cell %d: %s"%[part,str(result.get("message",""))])
		for tile in Fx.cells(ANCHOR):
			expect(not w.state.objects.has(World.key(tile)),"cell %d click: %s is gone"%[part,World.key(tile)])
		expect(w.state.players[A].inventory==before,"cell %d click: every material came back, exactly once"%part)
		var second:=Fx.act(w,A,"remove",click,"")
		expect(second.get("ok",true)==false and w.state.players[A].inventory==before,"cell %d click: a second remove cannot refund again"%part)
		expect(w.can_stand(Fx.centre(click)),"cell %d click: the footprint is walkable again"%part)
	# Busy mills refuse (buffer, job, queue, auto), and a refusal leaves the whole piece.
	for setup in ["buffer","auto","queue"]:
		var w:=built(0)
		match setup:
			"buffer":w.state.objects[World.key(ANCHOR)].input_wheat=3
			"auto":w.state.objects[World.key(ANCHOR)].auto_enabled=true
			"queue":Fx.act(w,A,"queue_processing",ANCHOR,"flour")
		var before_world:=snap(w)
		var result:=Fx.act(w,A,"remove",FAR_CELL,"")
		expect(result.get("ok",true)==false and snap(w)==before_world and Fx.parts_ok(w,ANCHOR,0),"remove refused while the mill has %s"%setup)
	# Refund cap: a full backpack refuses the whole removal.
	var capped:=built(0)
	capped.state.players[A].inventory.wood=1000000000-10
	var capped_before:=snap(capped)
	var cap_result:=Fx.act(capped,A,"remove",ANCHOR,"")
	expect(cap_result.get("ok",true)==false and str(cap_result.get("message","")).contains("上限") and snap(capped)==capped_before and Fx.parts_ok(capped,ANCHOR,0),"a full backpack refuses the refund and leaves the mill standing")
	# The owner is refunded when somebody else removes it is covered by PlotPermissions; here only the owner path.
	var stranger:=built(0)
	Fx.put(stranger,B,Fx.WEST+Vector2(-0.5,0.0))
	var stranger_before:=snap(stranger)
	var guest:=Fx.act(stranger,B,"remove",FAR_CELL,"")
	if guest.get("ok",false)==true:
		expect(Fx.bag(stranger,"wood",A)==300 and Fx.bag(stranger,"wood",B)==300 and not stranger.state.objects.has(World.key(ANCHOR)),"a guest dismantle refunds the owner, not the guest, and clears the nine cells")
	else:
		expect(snap(stranger)==stranger_before,"a refused guest dismantle changes nothing")

# -------------------------------------------------------------------- move --

func move_scenarios()->void:
	for facing in 4:
		var w:=built(facing)
		Fx.put(w,A,Fx.MOVER)
		var before_inventory:Dictionary=w.state.players[A].inventory.duplicate(true)
		var result:=Fx.act(w,A,"move_object",FAR_CELL,"%d,%d"%[Fx.DEST.x,Fx.DEST.y])
		expect(result.get("ok",false)==true,"facing %d: move: %s"%[facing,str(result.get("message",""))])
		expect(Fx.parts_ok(w,Fx.DEST,facing),"facing %d: the nine parts and the facing arrived"%facing)
		for tile in Fx.cells(ANCHOR):expect(not w.state.objects.has(World.key(tile)),"facing %d: old cell %s is gone"%[facing,World.key(tile)])
		expect(w.state.players[A].inventory==before_inventory,"facing %d: moving costs and refunds nothing"%facing)
		expect(w.blocked(Fx.cells(Fx.DEST)[0]) and not w.blocked(Fx.entrance(Fx.DEST,facing)),"facing %d: collision followed the move"%facing)
		expect(Fx.valid(w),"facing %d: the world validates after the move"%facing)
	# Overlapping move (one row down); the old front cell is part of the old footprint and does not block.
	var w:=built(2)
	Fx.put(w,A,Vector2(43.5,34.5))
	var shifted:=Fx.act(w,A,"move_object",ANCHOR,"%d,%d"%[Fx.SHIFT.x,Fx.SHIFT.y])
	expect(shifted.get("ok",false)==true and Fx.parts_ok(w,Fx.SHIFT,2),"an overlapping move works: "+str(shifted.get("message","")))
	for tile in Fx.cells(ANCHOR):
		if not Fx.cells(Fx.SHIFT).has(tile):expect(not w.state.objects.has(World.key(tile)),"the vacated cell %s is empty"%World.key(tile))
	# Refusals: a blocked front, a clipped footprint, someone inside, a busy machine, out of reach.
	w=built(2)
	Fx.put(w,A,Fx.MOVER)
	var dest_text:="%d,%d"%[Fx.DEST.x,Fx.DEST.y]
	w.state.objects[World.key(Fx.front(Fx.DEST,2))]={"type":"wall","owner":A,"items":{}}
	refuse(w,A,"move_object",FAR_CELL,dest_text,"destination front is walled","入口")
	w.state.objects.erase(World.key(Fx.front(Fx.DEST,2)))
	w.state.objects[World.key(Fx.DEST+Vector2i(2,2))]={"type":"chest","owner":A,"items":{}}
	refuse(w,A,"move_object",FAR_CELL,dest_text,"destination footprint clipped")
	w.state.objects.erase(World.key(Fx.DEST+Vector2i(2,2)))
	Fx.put(w,B,Fx.centre(Fx.DEST+Vector2i(1,1)))
	refuse(w,A,"move_object",FAR_CELL,dest_text,"someone stands inside the destination","人")
	Fx.put(w,B,Fx.PARK)
	w.state.objects[World.key(ANCHOR)].input_wheat=2
	refuse(w,A,"move_object",FAR_CELL,dest_text,"buffer not empty")
	w.state.objects[World.key(ANCHOR)].input_wheat=0
	Fx.put(w,A,Vector2(46.5,38.5))
	refuse(w,A,"move_object",FAR_CELL,dest_text,"out of reach")
	Fx.put(w,A,Fx.MOVER)
	expect(Fx.act(w,A,"move_object",FAR_CELL,dest_text).get("ok",false)==true,"after the obstacles are gone the same move works")
	# A solid piece may not be moved onto a mill's entrance front.
	w=built(0)
	w.state.objects["46,34"]={"type":"chest","owner":A,"items":{}}
	Fx.put(w,A,Vector2(44.5,35.5))
	var front_cell:=Fx.front(ANCHOR,0)
	refuse(w,A,"move_object",Vector2i(46,34),"%d,%d"%[front_cell.x,front_cell.y],"a chest moved onto the entrance front","入口")

# -------------------------------------------------------------------- undo --

func undo_scenarios()->void:
	# Undo of a build: all nine cells and the exact materials go away.
	var w:=Fx.world()
	var before:Dictionary=w.state.players[A].inventory.duplicate(true)
	expect(Fx.act(w,A,"build",ANCHOR,"mill:1").get("ok",false)==true,"fixture: build for undo")
	var id:=str(w.undo_summary(A).get("id",""))
	expect(id!="" and w.undo_summary(A).get("available")==true,"the build is undoable")
	var undone:=Fx.act(w,A,"undo_build",ANCHOR,id)
	expect(undone.get("ok",false)==true,"undo of a build: "+str(undone.get("message","")))
	for tile in Fx.cells(ANCHOR):expect(not w.state.objects.has(World.key(tile)),"undo build: %s is gone"%World.key(tile))
	expect(w.state.players[A].inventory==before,"undo build: materials returned exactly")
	# Undo of a remove: the whole mill returns with part, facing and the entrance still walkable.
	w=built(3)
	expect(Fx.act(w,A,"remove",FAR_CELL,"").get("ok",false)==true,"fixture: remove for undo")
	id=str(w.undo_summary(A).get("id",""))
	var after_remove:Dictionary=w.state.players[A].inventory.duplicate(true)
	undone=Fx.act(w,A,"undo_build",ANCHOR,id)
	expect(undone.get("ok",false)==true and Fx.parts_ok(w,ANCHOR,3),"undo of a remove restores nine parts with facing 3: "+str(undone.get("message","")))
	expect(w.blocked(ANCHOR) and not w.blocked(Fx.entrance(ANCHOR,3)) and w.can_stand(Fx.centre(Fx.entrance(ANCHOR,3))),"undo remove: the entrance is still the one walkable cell")
	expect(w.state.players[A].inventory!=after_remove,"undo remove: the refund was taken back")
	expect(Fx.valid(w),"undo remove: the world validates")
	# Undo of a remove is refused while someone stands in a solid cell or the entrance front is walled in.
	w=built(0)
	expect(Fx.act(w,A,"remove",ANCHOR,"").get("ok",false)==true,"fixture: remove for blocked undo")
	id=str(w.undo_summary(A).get("id",""))
	Fx.put(w,B,Fx.centre(ANCHOR+Vector2i(1,1)))
	var blocked_by_person:=snap(w)
	var refused:=Fx.act(w,A,"undo_build",ANCHOR,id)
	expect(refused.get("ok",true)==false and snap(w)==blocked_by_person,"undo remove refused while a person stands where a solid cell returns")
	Fx.put(w,B,Fx.PARK)
	w.state.objects[World.key(Fx.front(ANCHOR,0))]={"type":"wall","owner":A,"items":{}}
	var blocked_by_wall:=snap(w)
	refused=Fx.act(w,A,"undo_build",ANCHOR,id)
	expect(refused.get("ok",true)==false and snap(w)==blocked_by_wall,"undo remove refused while a wall closes the entrance front")
	w.state.objects.erase(World.key(Fx.front(ANCHOR,0)))
	Fx.put(w,B,Fx.centre(Fx.entrance(ANCHOR,0)))
	expect(Fx.act(w,A,"undo_build",ANCHOR,id).get("ok",false)==true and Fx.parts_ok(w,ANCHOR,0),"someone standing in the doorway does not block the undo")
	# Undo of a move puts the whole mill back where it was.
	w=built(2)
	Fx.put(w,A,Fx.MOVER)
	expect(Fx.act(w,A,"move_object",FAR_CELL,"%d,%d"%[Fx.DEST.x,Fx.DEST.y]).get("ok",false)==true,"fixture: move for undo")
	id=str(w.undo_summary(A).get("id",""))
	undone=Fx.act(w,A,"undo_build",Fx.DEST,id)
	expect(undone.get("ok",false)==true and Fx.parts_ok(w,ANCHOR,2),"undo of a move restores the nine cells at the old site: "+str(undone.get("message","")))
	for tile in Fx.cells(Fx.DEST):expect(not w.state.objects.has(World.key(tile)),"undo move: the destination cell %s is empty again"%World.key(tile))
	# The kitchen gate also closes the restore.
	w=built(0)
	expect(Fx.act(w,A,"remove",ANCHOR,"").get("ok",false)==true,"fixture: remove for gated undo")
	id=str(w.undo_summary(A).get("id",""))
	w.state.public_kitchen=World.SAVE_SCHEMA.public_kitchen_fresh()
	var gated:=snap(w)
	refused=Fx.act(w,A,"undo_build",ANCHOR,id)
	expect(refused.get("ok",true)==false and snap(w)==gated,"a restored mill still needs the opened kitchen")

# --------------------------------------------------------------- save/load --

func save_and_reload()->void:
	var w:=Fx.world()
	var path:="user://mill-c13-%d.json"%Time.get_ticks_usec()
	paths.append(path)
	expect(Fx.act(w,A,"build",ANCHOR,"mill:2").get("ok",false)==true,"fixture: build before saving")
	w.state.players[A].inventory.mill_kit=1
	expect(Fx.act(w,A,"build",Fx.DEST,"mill").get("ok",false)==true,"fixture: a legacy mill next to it")
	expect(Fx.act(w,A,"feed_processing",FAR_CELL,"").get("ok",false)==true,"fixture: wheat in the new mill's buffer")
	# The mills are built; swap the directly-written kitchen for a schema-valid one, then really save.
	Fx.quiet_kitchen(w.state)
	w.save_path=path
	expect(w.save(),"the world with both mills saves: "+w.save_error)
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"the world with both mills reloads from its primary save")
	expect(Fx.parts_ok(loaded,ANCHOR,2) and int(Fx.obj(loaded,ANCHOR).input_wheat)==4,"the new mill reloads whole: nine parts, facing 2, the buffer on the anchor")
	expect(not Fx.obj(loaded,Fx.DEST).has("mill_part") and loaded.blocked(Fx.DEST),"the legacy mill reloads as a legacy 1x1")
	expect(loaded.blocked(ANCHOR) and not loaded.blocked(Fx.entrance(ANCHOR,2)),"collision survives the reload")
	expect(snap(loaded)==snap(w) or Fx.valid(loaded),"the reloaded world validates")
