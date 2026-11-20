extends SceneTree
const Edge=preload("res://scripts/edge_grid.gd")
var checks:=0
var failures:=0

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var W:=Edge.MAP_SIZE.x
	var H:=Edge.MAP_SIZE.y
	expect(Edge.MAP_SIZE==preload("res://scripts/world.gd").SIZE,"edge bounds follow the home world")
	# Side constants and helpers.
	expect(Edge.SIDE_N==0 and Edge.SIDE_E==1 and Edge.SIDE_S==2 and Edge.SIDE_W==3,"side order N E S W")
	for s in 4:
		expect(Edge.is_side(s),"side %d valid"%s)
		expect(Edge.opposite(Edge.opposite(s))==s,"opposite involution %d"%s)
		expect(Edge.neighbor(Vector2i(5,5),s)==Vector2i(5,5)+Edge.DIRS[s],"neighbor %d"%s)
	expect(Edge.neighbor(Vector2i(5,5),Edge.SIDE_N)==Vector2i(5,4),"north is y-1")
	expect(Edge.neighbor(Vector2i(5,5),Edge.SIDE_E)==Vector2i(6,5),"east is x+1")
	expect(Edge.neighbor(Vector2i(5,5),Edge.SIDE_S)==Vector2i(5,6),"south is y+1")
	expect(Edge.neighbor(Vector2i(5,5),Edge.SIDE_W)==Vector2i(4,5),"west is x-1")
	for bad in [-1,4,99,1.0,"N",true,null,Vector2i(1,1)]:
		expect(not Edge.is_side(bad),"is_side rejects %s"%str(bad))
	expect(Edge.opposite(7)==-1 and Edge.opposite(-1)==-1,"opposite of bad side")

	# Canonical keys: all four sides of an interior cell.
	var c:=Vector2i(10,20)
	expect(Edge.key(c,Edge.SIDE_N)=="10,20,N","N key")
	expect(Edge.key(c,Edge.SIDE_W)=="10,20,W","W key")
	expect(Edge.key(c,Edge.SIDE_S)=="10,21,N","S key is next row N")
	expect(Edge.key(c,Edge.SIDE_E)=="11,20,W","E key is next column W")
	# Independence from the querying cell.
	for s in 4:
		var o:=Edge.neighbor(c,s)
		expect(Edge.key(c,s)==Edge.key(o,Edge.opposite(s)),"same key from both cells side %d"%s)
	# edges_of_cell: N E S W order, 4 distinct keys; adjacent cells share exactly one.
	var ec:=Edge.edges_of_cell(c)
	expect(ec==["10,20,N","11,20,W","10,21,N","10,20,W"],"edges_of_cell order")
	var er:=Edge.edges_of_cell(Vector2i(11,20))
	var shared:=0
	for k in ec:
		if er.has(k):shared+=1
	expect(shared==1 and er[3]==ec[1],"adjacent cells share exactly the E/W edge")
	expect(Edge.edges_of_cell(Vector2i(-1,0)).is_empty() and Edge.edges_of_cell(Vector2i(W,0)).is_empty(),"off-map cell has no edges")
	expect(Edge.edges_of_cell("x").is_empty(),"non-cell edges_of_cell")

	# Reversible decoding: every side of a sample of cells including all rim cells.
	var cells:Array[Vector2i]=[Vector2i(0,0),Vector2i(W-1,0),Vector2i(0,H-1),Vector2i(W-1,H-1),Vector2i(60,50),Vector2i(1,H-2)]
	for x in W:
		cells.append(Vector2i(x,0));cells.append(Vector2i(x,H-1))
	for y in H:
		cells.append(Vector2i(0,y));cells.append(Vector2i(W-1,y))
	var seen:={}
	for cell in cells:
		for s in 4:
			var k:=Edge.key(cell,s)
			expect(k!="","rim/interior key valid %s %d"%[str(cell),s])
			var d:=Edge.decode(k)
			expect(not d.is_empty() and (d.side==Edge.SIDE_N or d.side==Edge.SIDE_W),"decode canonical %s"%k)
			if d.is_empty():continue
			expect(Edge.key(d.cell,d.side)==k,"round trip %s"%k)
			expect(Edge.is_valid_key(k),"valid %s"%k)
			var pair:=Edge.cells_of(k)
			expect(pair.size()==2 and (pair[0]==cell or pair[1]==cell),"cells_of includes asking cell %s"%k)
			expect(Edge.in_bounds(pair[0]) or Edge.in_bounds(pair[1]),"edge touches map %s"%k)
			seen[k]=true
	# Rim extremes exist; one past them does not.
	expect(Edge.is_valid_key("0,0,N") and Edge.is_valid_key("0,0,W"),"origin edges")
	expect(Edge.is_valid_key("0,%d,N"%H),"south outer rim edge")
	expect(Edge.is_valid_key("%d,0,W"%W),"east outer rim edge")
	expect(Edge.is_valid_key("%d,%d,N"%[W-1,H]) and Edge.is_valid_key("%d,%d,W"%[W,H-1]),"far rim edges")
	expect(not Edge.is_valid_key("0,%d,N"%(H+1)),"past south rim")
	expect(not Edge.is_valid_key("%d,0,W"%(W+1)),"past east rim")
	expect(not Edge.is_valid_key("%d,0,N"%W),"N edge at x==W touches no cell")
	expect(not Edge.is_valid_key("0,%d,W"%H),"W edge at y==H touches no cell")
	expect(Edge.key(Vector2i(W-1,H-1),Edge.SIDE_S)=="%d,%d,N"%[W-1,H],"S of last cell")
	expect(Edge.key(Vector2i(W-1,H-1),Edge.SIDE_E)=="%d,%d,W"%[W,H-1],"E of last cell")
	# Edge count for a full map: N edges W*(H+1) plus W edges (W+1)*H.
	var total:=0
	for y in H+1:
		for x in W+1:
			if Edge.is_valid_key("%d,%d,N"%[x,y]):total+=1
			if Edge.is_valid_key("%d,%d,W"%[x,y]):total+=1
	expect(total==W*(H+1)+(W+1)*H,"total valid edge count %d"%total)

	# Negative / off-map cells and bad arguments.
	expect(Edge.key(Vector2i(-1,5),Edge.SIDE_N)=="","negative x cell N")
	expect(Edge.key(Vector2i(5,-1),Edge.SIDE_W)=="","negative y cell W")
	expect(Edge.key(Vector2i(5,-1),Edge.SIDE_N)=="","N edge of off-map row -1 touches no cell... y=-1 owner")
	expect(Edge.key(Vector2i(-1,-1),Edge.SIDE_S)=="","corner outside")
	expect(Edge.key(Vector2i(-1,5),Edge.SIDE_E)=="0,5,W","E side of x=-1 is rim W edge of x=0")
	expect(Edge.key(Vector2i(5,-1),Edge.SIDE_S)=="5,0,N","S side of y=-1 is rim N edge of y=0")
	expect(Edge.key(Vector2i(W,5),Edge.SIDE_W)=="%d,5,W"%W,"W side of x=W is rim edge")
	expect(Edge.key(Vector2i(W+1,5),Edge.SIDE_W)=="","two past east")
	expect(Edge.key(Vector2i(0,0),4)=="" and Edge.key(Vector2i(0,0),-1)=="","bad side numbers")
	expect(Edge.key(Vector2i(0,0),1.0)=="" and Edge.key(Vector2i(0,0),"N")=="","non-int side")
	expect(Edge.key("0,0",0)=="" and Edge.key(null,0)=="" and Edge.key([0,0],0)=="","non-Vector2i cell")
	expect(Edge.canonical(Vector2i(0,0),9).is_empty(),"canonical bad side")
	expect(Edge.canonical(Vector2i(3,3),Edge.SIDE_S)=={"cell":Vector2i(3,4),"side":Edge.SIDE_N},"canonical S")
	expect(Edge.canonical(Vector2i(3,3),Edge.SIDE_E)=={"cell":Vector2i(4,3),"side":Edge.SIDE_W},"canonical E")
	expect(Edge.canonical(Vector2i(3,3),Edge.SIDE_N)=={"cell":Vector2i(3,3),"side":Edge.SIDE_N},"canonical N")
	# Custom limits (blueprint-sized box).
	var lim:=Vector2i(4,4)
	expect(Edge.key(Vector2i(3,3),Edge.SIDE_S,lim)=="3,4,N" and Edge.key(Vector2i(4,0),Edge.SIDE_N,lim)=="","custom limits")

	# Malformed keys are never valid.
	var bad_keys:Array=["","0,0","0,0,","0,0,N,","0,0,N,N",",0,N","0,,N","0,0,,N","0, 0,N"," 0,0,N","0,0,N ","0,0,n","0,0,w",
		"0,0,S","0,0,E","0,0,X","0,0,NW","0,0,0","1,2,S","1,2,E","-1,0,N","0,-1,W","-0,0,N","+1,0,N","01,2,N","1,02,N","00,0,N",
		"1.0,2,N","1e1,2,N","0x1,2,N","1,2.0,N","a,b,N","١,2,N","1,２,N","1;2;N","1 2 N","1,2|N","x,y,N","999999,0,N","1000000,0,N",
		"1,2,N\n","1\n,2,N","1,2,\tN","120,0,N","0,101,N","0,100,W","121,0,W","9999999999999999999,0,N","0000001,0,N"]
	for bk in bad_keys:
		expect(not Edge.is_valid_key(bk),"malformed key rejected: %s"%str(bk).c_escape())
		expect(Edge.decode(bk).is_empty(),"decode empty: %s"%str(bk).c_escape())
		expect(Edge.cells_of(bk).is_empty(),"cells_of empty: %s"%str(bk).c_escape())
		expect(Edge.touching(bk).is_empty(),"touching empty: %s"%str(bk).c_escape())
		expect(Edge.rotate_key(bk,4,4,1)=="","rotate_key empty: %s"%str(bk).c_escape())
	for nonstr in [null,5,1.5,true,Vector2i(0,0),["0,0,N"],{"a":1},&"0,0,N"]:
		expect(not Edge.is_valid_key(nonstr),"non-string key rejected (incl. StringName) %s"%str(nonstr))
	expect(Edge.decode(5).is_empty() and Edge.decode(null).is_empty(),"decode non-strings")

	# Neighbors via cells_of: N is above, W is left.
	var north_cells:Array[Vector2i]=[Vector2i(5,4),Vector2i(5,5)]
	var west_cells:Array[Vector2i]=[Vector2i(4,5),Vector2i(5,5)]
	expect(Edge.cells_of("5,5,N")==north_cells,"cells_of N")
	expect(Edge.cells_of("5,5,W")==west_cells,"cells_of W")
	expect(Edge.cells_of("0,0,N")[0]==Vector2i(0,-1),"rim cells_of keeps off-map cell")
	# touching: six neighbours at corners, deterministic and canonical.
	var t:=Edge.touching("5,5,N")
	var touching_north:Array[String]=["4,5,N","5,4,W","5,5,W","6,4,W","6,5,N","6,5,W"]
	expect(t==touching_north,"touching N exact: %s"%str(t))
	var tw:=Edge.touching("5,5,W")
	expect(tw.size()==6 and not tw.has("5,5,W"),"touching W size, excludes self")
	for k in t:
		expect(Edge.is_valid_key(k) and not Edge.touching(k).is_empty() and Edge.touching(k).has("5,5,N"),"touching symmetric %s"%k)
	for k in tw:
		expect(Edge.touching(k).has("5,5,W"),"touching symmetric W %s"%k)
	# Corner-sharing check: ring around a 1x1 cell touches pairwise.
	var ring:=Edge.edges_of_cell(Vector2i(5,5))
	for k in ring:
		var tk:=Edge.touching(k)
		var around:=0
		for o in ring:
			if o!=k and tk.has(o):around+=1
		expect(around==2,"each cell edge touches the two perpendicular cell edges only: %s"%k)
	expect(Edge.touching("0,0,N").size()<6,"rim edge touching drops off-map keys")

	# Side rotation: all sides x all turns.
	for s in 4:
		for turns in range(-8,9):
			expect(Edge.rotate_side(s,turns)==posmod(s+turns,4),"rotate_side %d by %d"%[s,turns])
	expect(Edge.rotate_side(Edge.SIDE_N,1)==Edge.SIDE_E and Edge.rotate_side(Edge.SIDE_E,1)==Edge.SIDE_S,"clockwise sides")
	expect(Edge.rotate_side(Edge.SIDE_S,1)==Edge.SIDE_W and Edge.rotate_side(Edge.SIDE_W,1)==Edge.SIDE_N,"clockwise wrap")
	expect(Edge.rotate_side(Edge.SIDE_N,-1)==Edge.SIDE_W,"counter-clockwise")
	expect(Edge.rotate_side(9,1)==-1 and Edge.rotate_side(0,1.0)==-1 and Edge.rotate_side(0,"1")==-1,"rotate_side bad args")
	# Cell rotation matches BlueprintDesign.rotate: (x,y)->(h-1-y,x), w/h swap.
	var r1:=Edge.rotate_cell(Vector2i(0,0),4,3,1)
	expect(r1.cell==Vector2i(2,0) and r1.w==3 and r1.h==4,"rotate_cell top-left 4x3")
	expect(Edge.rotate_cell(Vector2i(3,0),4,3,1).cell==Vector2i(2,3),"rotate_cell top-right")
	expect(Edge.rotate_cell(Vector2i(1,2),4,3,4).cell==Vector2i(1,2),"four turns identity")
	expect(Edge.rotate_cell(Vector2i(1,2),4,3,0).cell==Vector2i(1,2),"zero turns identity")
	expect(Edge.rotate_cell(Vector2i(1,2),4,3,-1)==Edge.rotate_cell(Vector2i(1,2),4,3,3),"negative turns")
	expect(Edge.rotate_cell(Vector2i(0,0),0,3,1).is_empty() and Edge.rotate_cell(Vector2i(0,0),3,-1,1).is_empty(),"rotate_cell bad box")
	expect(Edge.rotate_cell("a",3,3,1).is_empty() and Edge.rotate_cell(Vector2i(0,0),3,3,1.5).is_empty(),"rotate_cell bad args")
	# Edge rotation: single known case. 4x3 box, N edge of (0,0) -> E edge of (2,0) = "3,0,W".
	var re:=Edge.rotate_edge(Vector2i(0,0),Edge.SIDE_N,4,3,1)
	expect(re=={"cell":Vector2i(3,0),"side":Edge.SIDE_W},"north of top-left becomes east rim edge")
	expect(Edge.rotate_key("0,0,N",4,3,1)=="3,0,W","rotate_key N one turn")
	# Property over a whole box: every edge, 0..3 turns.
	for dims in [Vector2i(4,4),Vector2i(5,3),Vector2i(1,1),Vector2i(16,16)]:
		var bw:int=dims.x;var bh:int=dims.y
		var box:Array[String]=[]
		for y in bh+1:
			for x in bw+1:
				for side in [Edge.SIDE_N,Edge.SIDE_W]:
					var k:=Edge.key(Vector2i(x,y),side)
					if k!="" and _in_box(k,bw,bh):box.append(k)
		expect(box.size()==bw*(bh+1)+(bw+1)*bh,"box edge count %s -> %d"%[str(dims),box.size()])
		for k in box:
			var cur:=k;var cw:=bw;var ch:=bh
			for turn in range(1,5):
				var step:=Edge.rotate_key(cur,cw,ch,1)
				expect(step!="","rotate step valid %s turn %d"%[k,turn])
				var direct:=Edge.rotate_key(k,bw,bh,turn)
				expect(step==direct,"incremental == direct %s turn %d"%[k,turn])
				var t2:=cw;cw=ch;ch=t2
				expect(_in_box(step,cw,ch),"stays inside rotated box %s turn %d"%[k,turn])
				cur=step
			expect(cur==k,"four turns return %s in %s"%[k,str(dims)])
			expect(Edge.rotate_key(k,bw,bh,-1)==Edge.rotate_key(k,bw,bh,3),"neg turn %s"%k)
			expect(Edge.rotate_key(k,bw,bh,5)==Edge.rotate_key(k,bw,bh,1),"turn 5 == 1 %s"%k)
		# Rotation preserves adjacency: edges that touch still touch afterwards.
		for k in box:
			var rk:=Edge.rotate_key(k,bw,bh,1)
			var rt:=Edge.touching(rk)
			for o in Edge.touching(k):
				if _in_box(o,bw,bh):
					expect(rt.has(Edge.rotate_key(o,bw,bh,1)),"rotation preserves touching %s~%s"%[k,o])
	# Rotating via either adjacent cell gives the same edge (non-canonical entry).
	for s in 4:
		var a:=Edge.rotate_edge(Vector2i(1,1),s,4,4,1)
		var b:=Edge.rotate_edge(Edge.neighbor(Vector2i(1,1),s),Edge.opposite(s),4,4,1)
		expect(not a.is_empty() and a==b,"rotation independent of querying cell side %d"%s)
	# Each rotation of a cell's four sides gives the rotated cell's four sides.
	var rc:Vector2i=Edge.rotate_cell(Vector2i(1,2),4,5,1).cell
	var want:=Edge.edges_of_cell(rc)
	var got:Array[String]=[]
	for k in Edge.edges_of_cell(Vector2i(1,2)):got.append(Edge.rotate_key(k,4,5,1))
	got.sort();want.sort()
	expect(got==want,"cell edges rotate onto rotated cell edges")
	expect(Edge.rotate_edge(Vector2i(0,0),Edge.SIDE_N,4,4,1.0).is_empty() and Edge.rotate_edge(Vector2i(0,0),7,4,4,1).is_empty(),"rotate_edge bad args")
	expect(Edge.rotate_key("0,0,N",0,4,1)=="" and Edge.rotate_key("0,0,N",4,4,"1")=="","rotate_key bad args")

	print("edge_grid checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

# True when canonical key k lies on the outline or inside a bw x bh box of cells at the origin.
func _in_box(k:String,bw:int,bh:int) -> bool:
	var d:=Edge.decode(k)
	if d.is_empty():return false
	var c:Vector2i=d.cell
	if d.side==Edge.SIDE_N:return c.x>=0 and c.x<bw and c.y>=0 and c.y<=bh
	return c.x>=0 and c.x<=bw and c.y>=0 and c.y<bh
