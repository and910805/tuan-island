extends SceneTree
## True edge pieces in blueprints (v2). Expected values are hand-worked from the contract.
const World=preload("res://scripts/world.gd")
const EdgeConstruction=preload("res://scripts/edge_construction.gd")
const BP=preload("res://scripts/blueprint_design.gd")
var checks:=0
var failures:=0
var R:Dictionary=World.BUILD
var N:Dictionary=World.NAMES

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize()->void:call_deferred("run")

func run()->void:
	api()
	capture_geometry()
	capture_rejections()
	v1_unchanged()
	rotation()
	cost()
	validation()
	full_capacity()
	print("EDGE_BLUEPRINT_DESIGN_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func ep(kind:String,x:int,y:int,side:int)->Dictionary:
	return {"kind":kind,"x":x,"y":y,"settings":{"side":side}}

func v2(pieces:Array,w:int=3,h:int=3)->Dictionary:
	return {"version":2,"name":"e","width":w,"height":h,"pieces":pieces}

func norm(raw:Variant)->Dictionary:return BP.validate(raw,R,N)

func api()->void:
	expect(BP.SIZE_MAX==16 and BP.MAX_PIECES==768 and BP.MAX_PIECES_EDGE==1312,"caps")
	for kind in ["edge_wall","edge_door","edge_window"]:
		expect(BP.is_edge_kind(kind),"is_edge_kind "+kind)
		expect(BP.edge_recipe(kind)==EdgeConstruction.COSTS[kind],"recipe matches plan "+kind)
	for bad in ["wall","door","",null,3,"edge_fence"]:
		expect(not BP.is_edge_kind(bad) and BP.edge_recipe(bad).is_empty(),"non edge "+str(bad))
	expect(BP.edge_recipe("edge_door")=={"wood":6,"fiber":2} and BP.edge_recipe("edge_window")=={"wood":4,"glass":1} and BP.edge_recipe("edge_wall")=={"wood":3},"hand prices")
	var copy:=BP.edge_recipe("edge_wall");copy.wood=99
	expect(BP.edge_recipe("edge_wall").wood==3,"recipe is a copy")
	expect(BP.edge_side(ep("edge_wall",0,0,3))==3 and BP.edge_side({"kind":"wall"})==-1 and BP.edge_side(ep("edge_wall",0,0,4))==-1 and BP.edge_side(5)==-1,"edge_side")

func snap_edges(edges:Dictionary)->Dictionary:
	return {"ground":{},"objects":{},"roofs":{},"edges":edges}

func row(kind:String,owner:String,open:Variant=null)->Dictionary:
	var r:={"type":kind,"owner":owner}
	if open!=null:r.open=open
	return r

func capture_geometry()->void:
	var area:=Rect2i(5,5,3,3)
	var edges:={
		"5,5,N":row("edge_wall","alice"),     # north rim of (5,5)
		"8,5,W":row("edge_door","alice",true),# east rim of (7,5), open door
		"6,6,W":row("edge_window","alice"),   # interior, both cells inside
		"5,8,N":row("edge_wall","alice"),     # south rim of (5,7)
		"4,5,W":row("edge_wall","bob"),       # touches no in-area cell: ignored
		"9,9,N":row("edge_wall","bob"),
	}
	var snap:=snap_edges(edges)
	var before:=snap.duplicate(true)
	var r:=BP.capture(snap,"alice",area,"room",R,N)
	expect(r.ok,"edge capture ok: "+str(r.reason))
	if not r.ok:return
	var b:Dictionary=r.blueprint
	expect(b.version==2 and b.width==3 and b.height==3,"v2 header")
	expect(b.pieces==[ep("edge_wall",0,0,0),ep("edge_door",2,0,1),ep("edge_window",1,1,3),ep("edge_wall",0,2,2)],"canonical tiles and order: "+str(b.pieces))
	expect(snap==before,"snapshot untouched")
	for p in b.pieces:expect(p.size()==4 and not p.has("style") and not p.has("owner") and not p.has("open"),"edge piece has only kind,x,y,settings")
	# Mixed with tiles: tiles first, version 2.
	var s2:=snap_edges({"6,5,W":row("edge_wall","alice")})
	s2.objects["5,5"]={"type":"wall","owner":"alice"}
	var m:=BP.capture(s2,"alice",area,"mix",R,N)
	expect(m.ok and m.blueprint.version==2 and m.blueprint.pieces[0].kind=="wall" and m.blueprint.pieces[1]==ep("edge_wall",1,0,3),"mixed capture")
	# Capture then rotate round trip returns to the same bytes.
	var cur:=b
	for i in 4:
		var t:=BP.rotate(cur,1,R,N)
		expect(t.ok,"rotate step")
		cur=t.blueprint
	expect(var_to_str(cur)==var_to_str(b),"four quarter turns restore")

func capture_rejections()->void:
	var area:=Rect2i(5,5,3,3)
	var r:=BP.capture(snap_edges({"6,6,W":row("edge_wall","bob")}),"alice",area,"x",R,N)
	expect(not r.ok and not r.has("blueprint"),"foreign edge rejected")
	var s:=snap_edges({"4,5,W":row("edge_wall","bob")})
	expect(not BP.capture(s,"alice",area,"x",R,N).ok,"no pieces at all")
	s.objects["5,5"]={"type":"wall","owner":"alice"}
	expect(BP.capture(s,"alice",area,"x",R,N).ok,"foreign edge outside area ignored")
	for bad in [row("edge_fence","alice"),row("edge_wall",""),{"type":"edge_wall"},"junk",row("edge_door","alice","yes")]:
		expect(not BP.capture(snap_edges({"5,5,N":bad}),"alice",area,"x",R,N).ok,"corrupt edge row "+str(bad))
	expect(not BP.capture({"edges":[]},"alice",area,"x",R,N).ok,"edges must be dictionary")

func v1_unchanged()->void:
	var snap:=snap_edges({"1,1,N":row("edge_wall","bob")})
	snap.objects["5,5"]={"type":"wall","owner":"alice"}
	var r:=BP.capture(snap,"alice",Rect2i(5,5,2,2),"v1",R,N)
	expect(r.ok and r.blueprint.version==1 and r.blueprint.pieces==[{"kind":"wall","x":0,"y":0}],"edge-free capture stays v1")
	var raw:={"version":1,"name":"v1","width":2,"height":2,"pieces":[{"kind":"wall","x":0,"y":0}]}
	expect(norm(raw).ok and hash(var_to_str(norm(raw).blueprint))==hash(var_to_str(raw)),"v1 payload identical")
	var many:Array=[]
	for i in 769:many.append({"kind":"floor","x":0,"y":0})
	expect(not norm({"version":1,"name":"v","width":16,"height":16,"pieces":many}).ok,"v1 cap unchanged")

func rotation()->void:
	var b:=norm(v2([ep("edge_wall",0,0,0),ep("edge_door",2,0,1),ep("edge_window",1,1,3),ep("edge_wall",0,2,2)]))
	expect(b.ok,"fixture")
	var r:=BP.rotate(b.blueprint,1,R,N)
	var expected:=[ep("edge_wall",0,0,3),ep("edge_wall",2,0,1),ep("edge_window",1,1,0),ep("edge_door",2,2,2)]
	expect(r.ok and JSON.stringify(r.blueprint.pieces)==JSON.stringify(expected),"one turn hand-worked: "+str(r.get("blueprint")))
	var two:=BP.rotate(r.blueprint,1,R,N)
	var direct:=BP.rotate(b.blueprint,2,R,N)
	expect(two.ok and direct.ok and var_to_str(two.blueprint)==var_to_str(direct.blueprint),"turns compose")
	expect(var_to_str(BP.rotate(b.blueprint,0,R,N).blueprint)==var_to_str(b.blueprint),"zero turns identity")
	# Non-square box: 4x2 rotated gives 2x4 and keeps the physical edge count.
	var wide:=norm(v2([ep("edge_wall",3,1,1),ep("edge_wall",0,0,3),ep("edge_wall",1,0,2)],4,2))
	var rw:=BP.rotate(wide.blueprint,1,R,N)
	expect(rw.ok and rw.blueprint.width==2 and rw.blueprint.height==4 and rw.blueprint.pieces.size()==3,"non-square rotate")
	expect(not BP.rotate(b.blueprint,4,R,N).ok,"bad turns")

func cost()->void:
	var b:=norm(v2([ep("edge_wall",0,0,0),ep("edge_door",1,0,0),ep("edge_window",2,0,0)]))
	var c:=BP.base_cost(b.blueprint,R,N)
	expect(c.ok and c.cost=={"fiber":2,"glass":1,"wood":13},"edge cost 3+6+2+4+1: "+str(c))
	var tile:=norm(v2([ep("edge_wall",0,0,0),{"kind":"wall","x":1,"y":1}]))
	var mixed:=BP.base_cost(tile.blueprint,R,N)
	var only_tile:=BP.base_cost({"version":1,"name":"t","width":3,"height":3,"pieces":[{"kind":"wall","x":1,"y":1}]},R,N)
	expect(mixed.ok and only_tile.ok and int(mixed.cost.get("wood",0))==3+int(only_tile.cost.get("wood",0)),"mixed cost adds the tile recipe to the edge price")

func validation()->void:
	var good:=[ep("edge_wall",0,0,0)]
	expect(norm(v2(good)).ok,"valid v2")
	# Non-canonical but equal edge normalises to the canonical tile.
	var n:=norm(v2([ep("edge_wall",1,0,3)]))
	expect(n.ok and n.blueprint.pieces==[ep("edge_wall",1,0,3)],"W side stays at owner")
	var n3:=norm(v2([ep("edge_wall",2,0,3),ep("edge_wall",1,2,2)]))
	expect(n3.ok,"interior mix")
	var e_in:=norm(v2([ep("edge_wall",0,0,1)]))
	expect(e_in.blueprint.pieces==[ep("edge_wall",1,0,3)],"E of (0,0) canonicalises to W of (1,0)")
	var s_in:=norm(v2([ep("edge_wall",0,0,2)]))
	expect(s_in.blueprint.pieces==[ep("edge_wall",0,1,0)],"S of (0,0) canonicalises to N of (0,1)")
	expect(norm(v2([ep("edge_wall",2,2,2)])).blueprint.pieces==[ep("edge_wall",2,2,2)],"bottom rim keeps inside tile")
	expect(norm(v2([ep("edge_wall",2,0,1)])).blueprint.pieces==[ep("edge_wall",2,0,1)],"east rim keeps inside tile")
	# Duplicates: same edge from either side, even with another kind.
	expect(not norm(v2([ep("edge_wall",0,0,1),ep("edge_door",1,0,3)])).ok,"physical duplicate rejected")
	expect(not norm(v2([ep("edge_wall",0,0,0),ep("edge_wall",0,0,0)])).ok,"exact duplicate rejected")
	# Strictness.
	var bads:Array=[]
	bads.append(["v1 with edge",{"version":1,"name":"e","width":3,"height":3,"pieces":good}])
	bads.append(["v2 without edge",v2([{"kind":"wall","x":0,"y":0}])])
	bads.append(["v3",{"version":3,"name":"e","width":3,"height":3,"pieces":good}])
	bads.append(["side 4",v2([ep("edge_wall",0,0,4)])])
	bads.append(["side -1",v2([ep("edge_wall",0,0,-1)])])
	bads.append(["side string",v2([{"kind":"edge_wall","x":0,"y":0,"settings":{"side":"N"}}])])
	bads.append(["side bool",v2([{"kind":"edge_wall","x":0,"y":0,"settings":{"side":true}}])])
	bads.append(["side float",v2([{"kind":"edge_wall","x":0,"y":0,"settings":{"side":0.5}}])])
	bads.append(["extra settings key",v2([{"kind":"edge_wall","x":0,"y":0,"settings":{"side":0,"open":true}}])])
	bads.append(["empty settings",v2([{"kind":"edge_wall","x":0,"y":0,"settings":{}}])])
	bads.append(["no settings",v2([{"kind":"edge_wall","x":0,"y":0}])])
	bads.append(["settings not dict",v2([{"kind":"edge_wall","x":0,"y":0,"settings":0}])])
	bads.append(["style",v2([{"kind":"edge_wall","x":0,"y":0,"settings":{"side":0},"style":"x"}])])
	bads.append(["owner",v2([{"kind":"edge_wall","x":0,"y":0,"settings":{"side":0},"owner":"a"}])])
	bads.append(["open key",v2([{"kind":"edge_door","x":0,"y":0,"settings":{"side":0},"open":true}])])
	bads.append(["x out of box",v2([ep("edge_wall",3,0,0)])])
	bads.append(["y negative",v2([ep("edge_wall",0,-1,0)])])
	bads.append(["unknown edge kind",v2([ep("edge_fence",0,0,0)])])
	bads.append(["empty v2",v2([])])
	bads.append(["extra top key",{"version":2,"name":"e","width":3,"height":3,"pieces":good,"extra":1}])
	for case in bads:
		var res:=norm(case[1])
		expect(not res.ok and not res.has("blueprint"),"rejected: "+case[0])
	# Edge pieces do not occupy tile slots.
	expect(norm(v2([ep("edge_wall",0,0,0),{"kind":"wall","x":0,"y":0}])).ok,"edge and tile share a cell")

func full_capacity()->void:
	var pieces:Array=[]
	for y in 16:
		for x in 16:
			pieces.append({"kind":"floor","x":x,"y":y})
			pieces.append({"kind":"wall","x":x,"y":y})
			pieces.append({"kind":"roof","x":x,"y":y})
			pieces.append(ep("edge_wall",x,y,0))
			pieces.append(ep("edge_door" if x%2==0 else "edge_window",x,y,3))
			if x==15:pieces.append(ep("edge_wall",x,y,1))
			if y==15:pieces.append(ep("edge_wall",x,y,2))
	expect(pieces.size()==1312,"fixture size %d"%pieces.size())
	var res:=norm({"version":2,"name":"full","width":16,"height":16,"pieces":pieces})
	expect(res.ok and res.blueprint.pieces.size()==1312,"full 16x16 edges+tiles valid: "+str(res.get("reason")))
	if res.ok:
		var rot:=BP.rotate(res.blueprint,1,R,N)
		expect(rot.ok and rot.blueprint.pieces.size()==1312,"full rotate")
		expect(BP.base_cost(res.blueprint,R,N).ok,"full cost")
	pieces.append(ep("edge_wall",0,0,0))
	expect(not norm({"version":2,"name":"full","width":16,"height":16,"pieces":pieces}).ok,"over cap rejected")
