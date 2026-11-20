extends SceneTree
## C13 麵粉磨坊 blueprints: capture, validation, rotation, cost, authoritative quote / apply / undo.
## Pure data + World, no scene. Run: godot --headless --path game --script res://tests/test_mill_c13_blueprint.gd
##
## Pins: a new mill is one blueprint piece {"kind":"mill","settings":{"facing":0..3}} that needs all nine cells
## inside the layout and rotates by advancing its facing (never a vertical flag); a settings-less mill piece is the
## legacy 1x1 kit mill and keeps costing one mill_kit; the quote/apply path places the real 3x3 with the real
## entrance and front-cell rules.
const World=preload("res://scripts/world.gd")
const I=World.INDUSTRY
const Design=World.BLUEPRINT_DESIGN
const Fx=preload("res://tests/mill_c13_fixture.gd")
const A:=Fx.A
const ANCHOR:=Fx.ANCHOR
const NONCE:="abababababababababababababababab"
var checks:=0
var failures:=0
var serial:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)

func run()->void:
	validation()
	rotation()
	cost()
	capture()
	quote_and_apply()
	print("MILL_C13_BLUEPRINT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

func piece(kind:String,x:int,y:int,settings:Variant=null)->Dictionary:
	var out:={"kind":kind,"x":x,"y":y}
	if settings!=null:out["settings"]=settings
	return out

func design(width:int,height:int,pieces:Array)->Dictionary:
	return {"version":1,"name":"磨坊","width":width,"height":height,"pieces":pieces}

func mill(x:int,y:int,facing:int)->Dictionary:
	return piece("mill",x,y,{"facing":facing})

func good(raw:Dictionary)->Dictionary:
	return Design.validate(raw,World.BUILD,World.NAMES)

func validation()->void:
	for facing in 4:
		var result:=good(design(3,3,[mill(0,0,facing)]))
		expect(result.ok and result.blueprint.pieces[0].settings=={"facing":facing},"facing %d validates as a settings piece"%facing)
	var legacy:=good(design(1,1,[piece("mill",0,0)]))
	expect(legacy.ok and not legacy.blueprint.pieces[0].has("settings"),"a settings-less mill piece stays a legacy 1x1 piece")
	expect(good(design(3,3,[piece("mill",0,0,{"facing":2.0})])).ok,"an integral float facing (JSON) is accepted")
	for bad in [-1,4,1.5,"1",null,true,[1]]:
		expect(not good(design(3,3,[piece("mill",0,0,{"facing":bad})])).ok,"facing %s is rejected"%str(bad))
	for bad in [{},{"vertical":true},{"wide":true},{"facing":1,"vertical":true},{"facing":1,"extra":0}]:
		expect(not good(design(3,3,[piece("mill",0,0,bad)])).ok,"mill settings %s are rejected"%str(bad))
	expect(not good(design(3,3,[piece("mill",0,0,"north")])).ok,"mill settings must be a dictionary")
	# All nine cells have to fit the layout and stay clear of other pieces.
	expect(not good(design(3,3,[mill(1,0,0)])).ok,"a mill hanging out of the right edge is rejected")
	expect(not good(design(3,3,[mill(0,1,0)])).ok,"a mill hanging out of the bottom edge is rejected")
	expect(good(design(4,3,[mill(1,0,0)])).ok,"a mill that exactly fits is accepted")
	expect(not good(design(5,5,[mill(0,0,0),mill(2,2,1)])).ok,"two overlapping mills are rejected")
	expect(good(design(6,3,[mill(0,0,0),mill(3,0,2)])).ok,"two touching mills are accepted")
	expect(not good(design(4,3,[mill(0,0,0),piece("conveyor",1,1)])).ok,"a piece inside the nine cells is rejected")
	expect(good(design(4,3,[mill(0,0,0),piece("conveyor",3,1)])).ok,"a piece right beside the nine cells is accepted")
	# A legacy piece and a new piece may share a layout.
	expect(good(design(4,3,[mill(0,0,1),piece("mill",3,0)])).ok,"a legacy piece beside a new mill is accepted")
	expect(not good(design(4,3,[mill(0,0,1),piece("mill",2,2)])).ok,"a legacy piece inside a new mill is rejected")

func rotation()->void:
	# One mill alone: stays 3x3, the facing advances one step per quarter turn, the position stays (0,0).
	for facing in 4:
		for turns in 4:
			var turned:=Design.rotate(design(3,3,[mill(0,0,facing)]),turns,World.BUILD,World.NAMES)
			expect(turned.ok,"facing %d x %d turns rotates"%[facing,turns])
			if not turned.ok:continue
			var out:Dictionary=turned.blueprint.pieces[0]
			expect(out.x==0 and out.y==0 and out.settings=={"facing":(facing+turns)%4},"facing %d after %d turns is facing %d at (0,0)"%[facing,turns,(facing+turns)%4])
			expect(not out.settings.has("vertical") and turned.blueprint.width==3 and turned.blueprint.height==3,"no vertical flag appears and the layout stays 3x3")
	# In a larger layout the entrance cell travels exactly like the geometry: (x,y) -> (height-1-y, x).
	var base:=design(5,4,[mill(1,0,0),piece("conveyor",0,3,{"dir":0,"filter":"wheat"}),piece("sign",4,3)])
	for turns in range(1,4):
		var rotated:=Design.rotate(base,turns,World.BUILD,World.NAMES)
		expect(rotated.ok,"%d turns of a 5x4 layout rotates"%turns)
		if not rotated.ok:continue
		var width:int=5
		var height:int=4
		var entrance:=Vector2i(1,0)+I.mill_entrance_offset(0)
		var front:=Vector2i(1,0)+I.mill_front_offset(0)
		for _turn in turns:
			entrance=Vector2i(height-1-entrance.y,entrance.x)
			front=Vector2i(height-1-front.y,front.x)
			var swap:=width
			width=height
			height=swap
		var found:Dictionary={}
		for item:Dictionary in rotated.blueprint.pieces:
			if item.kind=="mill":found=item
		expect(not found.is_empty() and found.settings.facing==turns%4,"%d turns: the mill's facing advanced"%turns)
		if found.is_empty():continue
		var anchor:=Vector2i(found.x,found.y)
		expect(anchor+I.mill_entrance_offset(found.settings.facing)==entrance,"%d turns: the entrance cell is where the rotated geometry puts it"%turns)
		expect(anchor+I.mill_front_offset(found.settings.facing)==front,"%d turns: the open front cell is where the rotated geometry puts it"%turns)
		expect(rotated.blueprint.width==width and rotated.blueprint.height==height,"%d turns: width and height swap"%turns)
	var full:=Design.rotate(base,0,World.BUILD,World.NAMES)
	var around:=base
	for _turn in 4:
		var step:=Design.rotate(around,1,World.BUILD,World.NAMES)
		if not step.ok:break
		around=step.blueprint
	expect(full.ok and around==full.blueprint,"four quarter turns bring the layout back unchanged")
	# A legacy piece rotates as a plain cell and never grows settings.
	var old:=Design.rotate(design(2,2,[piece("mill",0,0)]),1,World.BUILD,World.NAMES)
	expect(old.ok and not old.blueprint.pieces[0].has("settings") and old.blueprint.pieces[0].x==1 and old.blueprint.pieces[0].y==0,"a legacy mill piece rotates as one cell with no settings")

func cost()->void:
	var new_cost:=Design.base_cost(design(3,3,[mill(0,0,3)]),World.BUILD,World.NAMES)
	expect(new_cost.ok and new_cost.cost=={"stone":15,"wood":25,"woodwork_parts":4},"a new mill piece costs 25 wood + 15 stone + 4 woodwork_parts: "+str(new_cost))
	var old_cost:=Design.base_cost(design(1,1,[piece("mill",0,0)]),World.BUILD,World.NAMES)
	expect(old_cost.ok and old_cost.cost=={"mill_kit":1},"a legacy mill piece keeps costing one mill_kit: "+str(old_cost))
	var mixed:=Design.base_cost(design(7,3,[mill(0,0,0),mill(3,0,1),piece("mill",6,0)]),World.BUILD,World.NAMES)
	expect(mixed.ok and mixed.cost=={"stone":30,"wood":50,"woodwork_parts":8,"mill_kit":1},"two new mills and a legacy piece add up: "+str(mixed))

func snapshot(w:World)->Dictionary:
	return {"ground":w.state.ground,"objects":w.state.objects,"roofs":w.state.roofs}

func grab(w:World,area:Rect2i)->Dictionary:
	return Design.capture(snapshot(w),A,area,"磨坊",World.BUILD,World.NAMES)

func capture()->void:
	for facing in 4:
		var w:=Fx.world()
		Fx.place(w,ANCHOR,facing)
		var taken:=grab(w,Rect2i(ANCHOR,Vector2i(3,3)))
		expect(taken.ok and taken.blueprint.pieces.size()==1,"facing %d: nine cells capture as one piece: %s"%[facing,str(taken.get("reason",""))])
		if taken.ok:
			var out:Dictionary=taken.blueprint.pieces[0]
			expect(out.kind=="mill" and out.x==0 and out.y==0 and out.settings=={"facing":facing},"facing %d: the piece carries its facing at the anchor"%facing)
		var wide:=grab(w,Rect2i(ANCHOR+Vector2i(-1,-1),Vector2i(5,5)))
		expect(wide.ok and wide.blueprint.pieces.size()==1 and wide.blueprint.pieces[0].x==1 and wide.blueprint.pieces[0].y==1,"facing %d: inside a larger area the piece sits at its offset, once"%facing)
	var w:=Fx.world()
	Fx.place(w,ANCHOR,1)
	for area in [Rect2i(ANCHOR,Vector2i(2,3)),Rect2i(ANCHOR,Vector2i(3,2)),Rect2i(ANCHOR+Vector2i(1,1),Vector2i(2,2)),Rect2i(ANCHOR+Vector2i(1,0),Vector2i(3,3)),Rect2i(ANCHOR+Vector2i(2,2),Vector2i(1,1))]:
		var partial:=grab(w,area)
		expect(not partial.ok,"an area missing part of the mill is refused: %s"%str(area))
	# A legacy mill captures as a settings-less single piece.
	w=Fx.world()
	w.state.objects[World.key(ANCHOR)]={"type":"mill","owner":A,"items":{},"input_wheat":0,"auto_enabled":false}
	var legacy:=grab(w,Rect2i(ANCHOR,Vector2i(1,1)))
	expect(legacy.ok and legacy.blueprint.pieces.size()==1 and not legacy.blueprint.pieces[0].has("settings"),"a legacy mill captures as a plain one-cell piece")
	# Capture then rebuild preserves the shape (round trip through validate).
	w=Fx.world()
	Fx.place(w,ANCHOR,2)
	var again:=grab(w,Rect2i(ANCHOR,Vector2i(3,3)))
	expect(again.ok and good(again.blueprint).ok and good(again.blueprint).blueprint==again.blueprint,"a captured mill piece is already canonical")

func quote_of(w:World,raw:Dictionary,turns:int=0)->Dictionary:
	return w.quote_blueprint(A,raw,ANCHOR,turns)

func quote_and_apply()->void:
	# New mill, every facing, no rotation.
	for facing in 4:
		var w:=Fx.world()
		var raw:=design(3,3,[mill(0,0,facing)])
		var before:Dictionary=w.state.players[A].inventory.duplicate(true)
		var quote:=quote_of(w,raw)
		expect(quote.ok==true and quote.cost=={"stone":15,"wood":25,"woodwork_parts":4},"facing %d: the quote is ok and costs the new materials: %s"%[facing,str(quote.get("message",""))])
		expect(w.state.players[A].inventory==before and not w.state.objects.has(World.key(ANCHOR)),"facing %d: a quote changes nothing"%facing)
		var applied:=w.apply_blueprint(A,NONCE,raw,ANCHOR,0,str(quote.hash))
		expect(applied.get("ok",false)==true,"facing %d: apply: %s"%[facing,str(applied.get("message",""))])
		expect(Fx.parts_ok(w,ANCHOR,facing),"facing %d: the blueprint placed nine real parts with that facing"%facing)
		expect(Fx.bag(w,"wood")==275 and Fx.bag(w,"stone")==185 and Fx.bag(w,"woodwork_parts")==16,"facing %d: exactly the quoted materials were charged"%facing)
		expect(w.blocked(ANCHOR) and not w.blocked(Fx.entrance(ANCHOR,facing)) and not w.blocked(Fx.front(ANCHOR,facing)),"facing %d: solid cells, walkable entrance, open front"%facing)
		expect(Fx.valid(w),"facing %d: the world validates after the blueprint"%facing)
		var id:=str(w.undo_summary(A).get("id",""))
		if id!="":
			var undone:=Fx.act(w,A,"undo_build",ANCHOR,id)
			expect(undone.get("ok",false)==true and w.state.players[A].inventory==before and not w.state.objects.has(World.key(ANCHOR)),"facing %d: one undo removes the whole mill and refunds exactly"%facing)
	# Rotation through the quote: facing 0 rotated once is facing 1 (entrance on the west side).
	var w:=Fx.world()
	var raw:=design(3,3,[mill(0,0,0)])
	var turned:=quote_of(w,raw,1)
	expect(turned.ok==true,"the rotated quote is ok: "+str(turned.get("message","")))
	expect(w.apply_blueprint(A,NONCE,raw,ANCHOR,1,str(turned.hash)).get("ok",false)==true and Fx.parts_ok(w,ANCHOR,1),"a quarter turn places the mill with facing 1")
	# A stale hash requotes without building.
	w=Fx.world()
	var stale:=w.apply_blueprint(A,NONCE,raw,ANCHOR,0,"0".repeat(64))
	expect(stale.get("ok",true)==false and stale.get("requote",false)==true and not w.state.objects.has(World.key(ANCHOR)),"a wrong hash requotes and builds nothing")
	# Short on a material: the quote fails with the shortage and nothing is built.
	w=Fx.world()
	w.state.players[A].inventory.woodwork_parts=3
	var poor:=quote_of(w,raw)
	expect(poor.ok==false and str(poor.message).contains("材料不足"),"3 woodwork_parts: the quote names the shortage: "+str(poor.get("message","")))
	# The entrance front is checked in the simulation: a wall on the front cell refuses the whole blueprint.
	w=Fx.world()
	w.state.objects[World.key(Fx.front(ANCHOR,0))]={"type":"wall","owner":A,"items":{}}
	var walled:=quote_of(w,raw)
	expect(walled.ok==false and walled.problems.size()>=1 and str(walled.problems[0].reason).contains("入口"),"a walled-in entrance is a blueprint problem: "+str(walled.get("message","")))
	# A solid neighbour piece of the same blueprint on the front cell is refused too.
	w=Fx.world()
	var closed:=design(3,4,[mill(0,0,0),piece("wall",1,3)])
	var closed_quote:=quote_of(w,closed)
	expect(closed_quote.ok==false,"a blueprint that walls in its own mill's entrance is refused")
	# A person standing in a solid cell blocks; one in the doorway does not.
	w=Fx.world()
	Fx.put(w,A,Fx.WEST)
	Fx.put(w,Fx.B,Fx.centre(ANCHOR+Vector2i(1,1)))
	expect(quote_of(w,raw).ok==false,"a person inside the nine solid cells blocks the blueprint")
	Fx.put(w,Fx.B,Fx.centre(Fx.entrance(ANCHOR,0)))
	expect(quote_of(w,raw).ok==true,"a person in the doorway does not")
	# Legacy piece: needs a kit in the backpack, places a legacy 1x1, consumes exactly the kit.
	w=Fx.world()
	var old_raw:=design(1,1,[piece("mill",0,0)])
	var no_kit:=quote_of(w,old_raw)
	expect(no_kit.ok==false and no_kit.cost=={"mill_kit":1},"a legacy piece without a kit quotes one mill_kit and is refused: "+str(no_kit.get("message","")))
	w.state.players[A].inventory.mill_kit=1
	var with_kit:=quote_of(w,old_raw)
	expect(with_kit.ok==true and with_kit.cost=={"mill_kit":1},"a legacy piece with a kit quotes ok")
	var placed:=w.apply_blueprint(A,NONCE,old_raw,ANCHOR,0,str(with_kit.hash))
	expect(placed.get("ok",false)==true and not Fx.obj(w,ANCHOR).has("mill_part") and Fx.bag(w,"mill_kit")==0 and Fx.bag(w,"wood")==300,"the legacy piece builds a legacy 1x1 mill from the kit alone")
