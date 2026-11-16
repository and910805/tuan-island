extends SceneTree
## Behavioural tests for the pure automatic roofing planner.
## Snapshots use the real region layout: ground/objects/roofs keyed by World.key.
const World=preload("res://scripts/world.gd")
const Plan=preload("res://scripts/auto_roof_plan.gd")
var checks:=0
var failures:=0
const O:=Vector2i(10,10)
const DOOR:=Vector2i(10,9)
const GAP:=Vector2i(9,11)

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

static func k(p:Vector2i) -> String:
	return World.key(p)

func recipe() -> Dictionary:
	return World.BUILD["roof"].duplicate(true)

func pts(list:Array) -> Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for p in list:out.append(p)
	return out

func snap() -> Dictionary:
	return {"ground":{},"objects":{},"roofs":{},"players":{}}

func wall(owner:="alice",type:="wall") -> Dictionary:
	var w:={"type":type,"owner":owner,"items":{}}
	if type=="door":w.open=false
	return w

# Interior origin o, size, wall ring around it (existing ring objects are kept, so rooms can share walls).
func add_room(s:Dictionary,o:Vector2i,size:Vector2i,doors:Array,owner:="alice",wall_owner:="alice") -> Array:
	var cells:=[]
	for y in range(o.y-1,o.y+size.y+1):
		for x in range(o.x-1,o.x+size.x+1):
			var p:=Vector2i(x,y)
			if x>=o.x and x<o.x+size.x and y>=o.y and y<o.y+size.y:
				s.ground[k(p)]={"type":"floor","owner":owner,"items":{}}
				cells.append(p)
			elif not s.objects.has(k(p)):
				s.objects[k(p)]=wall(wall_owner)
	for d in doors:s.objects[k(d)]=wall(wall_owner,"door")
	return cells

func roof_cells(s:Dictionary,cells:Array,owner:String,auto:=true) -> void:
	for p in cells:
		var r:={"type":"roof","owner":owner,"items":{}}
		if auto:r.auto=true
		s.roofs[k(p)]=r

func keyset(cells:Array) -> Array:
	var out:=[]
	for p in cells:out.append(k(p))
	out.sort()
	return out

func sorted(values:Array) -> Array:
	var out:=values.duplicate()
	out.sort()
	return out

func norm(d) -> Dictionary:
	var out:={}
	if not d is Dictionary:return {"<not a dictionary>":1}
	for item in d:
		if int(d[item])!=0:out[item]=int(d[item])
	return out

func expected(n:int) -> Dictionary:
	var out:={}
	var r:=recipe()
	for item in r:
		if item!="name" and int(r[item])*n!=0:out[item]=int(r[item])*n
	return out

func auto_roof(actor:String) -> Dictionary:
	return {"type":"roof","owner":actor,"items":{},"auto":true}

func reconcile(before:Dictionary,after:Dictionary,touched:Array,actor:String,rec:Dictionary={}) -> Dictionary:
	return Plan.reconcile(before,after,pts(touched),actor,recipe() if rec.is_empty() else rec)

func apply(s:Dictionary,plan:Dictionary) -> Dictionary:
	var out:=s.duplicate(true)
	for key in plan.add:out.roofs[key]=plan.add[key].duplicate(true)
	for key in plan.remove:out.roofs.erase(key)
	return out

func shape_ok(r:Dictionary) -> bool:
	return r.get("ok") is bool and r.get("message") is String and r.get("add") is Dictionary and r.get("remove") is Array and r.get("cost") is Dictionary and r.get("refunds") is Dictionary

func nothing(r:Dictionary) -> bool:
	return r.ok and r.add.is_empty() and r.remove.is_empty() and norm(r.cost).is_empty() and r.refunds.is_empty()

func rejected(r:Dictionary) -> bool:
	return shape_ok(r) and not r.ok and r.add.is_empty() and r.remove.is_empty() and r.cost.is_empty() and r.refunds.is_empty()

func adds_exact(r:Dictionary,cells:Array,actor:String) -> bool:
	if sorted(r.add.keys())!=keyset(cells):return false
	for key in r.add:
		if r.add[key]!=auto_roof(actor):return false
	return true

# Accept any of the common deterministic orders: string, row-major (y,x) or column-major (x,y).
func is_sorted_any(keys:Array) -> bool:
	if keys==sorted(keys):return true
	var ps:=[]
	for key in keys:
		var parts:PackedStringArray=str(key).split(",")
		ps.append(Vector2i(int(parts[0]),int(parts[1])))
	var row:=ps.duplicate();row.sort_custom(func(a,b):return a.y<b.y or (a.y==b.y and a.x<b.x))
	var col:=ps.duplicate();col.sort_custom(func(a,b):return a.x<b.x or (a.x==b.x and a.y<b.y))
	return ps==row or ps==col

func reorder(s:Dictionary) -> Dictionary:
	var out:={}
	for field in s:
		var layer=s[field]
		if layer is Dictionary:
			var keys:Array=layer.keys();keys.reverse()
			var d:={}
			for key in keys:d[key]=layer[key].duplicate(true) if layer[key] is Dictionary else layer[key]
			out[field]=d
		else:out[field]=layer
	return out

# Sealed 4x4 room at origin o with door above the top-left cell; before has a gap in the left wall, after closes it.
func closure(o:=O,actor_wall:="alice") -> Dictionary:
	var before:=snap()
	var cells:=add_room(before,o,Vector2i(4,4),[o+Vector2i(0,-1)])
	var gap:=o+Vector2i(-1,1)
	before.objects.erase(k(gap))
	var after:=before.duplicate(true)
	after.objects[k(gap)]=wall(actor_wall)
	return {"before":before,"after":after,"cells":cells,"gap":gap}

# Sealed 4x4 room with existing roofs; after opens it by removing a right-wall segment.
func opening(o:=O) -> Dictionary:
	var before:=snap()
	var cells:=add_room(before,o,Vector2i(4,4),[o+Vector2i(0,-1)])
	var alice_cells:=[];var bob_cells:=[];var carol_cells:=[]
	for p in cells:
		var row:int=p.y-o.y
		if row==0 or (row==3 and p.x-o.x<2):alice_cells.append(p)
		elif row==1:bob_cells.append(p)
		elif row==2:carol_cells.append(p)
	roof_cells(before,alice_cells,"alice")
	roof_cells(before,bob_cells,"bob")
	roof_cells(before,carol_cells,"carol",false)
	var hole:=o+Vector2i(4,2)
	var after:=before.duplicate(true)
	after.objects.erase(k(hole))
	return {"before":before,"after":after,"cells":cells,"alice":alice_cells,"bob":bob_cells,"carol":carol_cells,"hole":hole}

func run() -> void:
	var R:=recipe()
	expect(R.has("name") and R.size()>1,"real roof recipe has a name and at least one material")
	for item in R:
		if item!="name":expect(int(R[item])>0,"real roof recipe material is positive: "+str(item))

	# --- Closure without any bed: exact roofs and exact totals charged to the actor.
	var c:=closure()
	var r:=reconcile(c.before,c.after,[c.gap],"alice")
	expect(shape_ok(r),"result has the documented field types")
	expect(r.ok,"sealed bedless room closure is accepted")
	expect(adds_exact(r,c.cells,"alice"),"closure adds one automatic actor roof on each of the 16 interior cells")
	expect(r.add.size()==16 and r.remove.is_empty() and r.refunds.is_empty(),"closure adds 16, removes and refunds nothing")
	expect(norm(r.cost)==expected(16),"closure cost is 16x the real roof recipe")
	expect(not r.cost.has("name"),"recipe name is never charged")
	expect(is_sorted_any(r.add.keys()),"added keys are in a deterministic sorted order")
	for p in c.cells:expect(c.after.ground.has(k(p)) and not c.after.objects.has(k(p)),"added roof sits on interior floor "+k(p))
	# Windows are boundary too.
	var cw:=closure()
	cw.after.objects[k(Vector2i(14,11))]=wall("alice","window");cw.before.objects[k(Vector2i(14,11))]=wall("alice","window")
	r=reconcile(cw.before,cw.after,[cw.gap],"alice")
	expect(r.ok and r.add.size()==16 and norm(r.cost)==expected(16),"window segment still seals the room")
	# Minimum area: 2x2 qualifies, 3x1 does not.
	var small:=snap();var small_cells:=add_room(small,O,Vector2i(2,2),[DOOR]);small.objects.erase(k(GAP))
	var small_after:=small.duplicate(true);small_after.objects[k(GAP)]=wall()
	r=reconcile(small,small_after,[GAP],"alice")
	expect(r.ok and adds_exact(r,small_cells,"alice") and norm(r.cost)==expected(4),"exactly four cells is roofed")
	var tiny:=snap();add_room(tiny,O,Vector2i(3,1),[DOOR]);tiny.objects.erase(k(Vector2i(9,10)))
	var tiny_after:=tiny.duplicate(true);tiny_after.objects[k(Vector2i(9,10))]=wall()
	r=reconcile(tiny,tiny_after,[Vector2i(9,10)],"alice")
	expect(nothing(r),"three-cell room is too small, nothing charged")

	# --- Incomplete closures charge nothing.
	var two:=closure();two.before.objects.erase(k(Vector2i(9,12)));two.after.objects.erase(k(Vector2i(9,12)))
	r=reconcile(two.before,two.after,[two.gap],"alice")
	expect(nothing(r),"one remaining wall gap: no roofs, no cost")
	var doorless:=closure();doorless.before.objects[k(DOOR)]=wall();doorless.after.objects[k(DOOR)]=wall()
	r=reconcile(doorless.before,doorless.after,[doorless.gap],"alice")
	expect(nothing(r),"sealed ring without a door: no roofs, no cost")
	r=reconcile(c.before,c.before.duplicate(true),[c.gap],"alice")
	expect(nothing(r),"unchanged open room: no roofs, no cost")

	# --- Mixed floor/wall owners: only the actor is charged and owns the new roofs.
	var mixed:=closure(O,"carol")
	var i:=0
	for p in mixed.cells:
		var who:="alice" if i%2==0 else "bob"
		mixed.before.ground[k(p)].owner=who;mixed.after.ground[k(p)].owner=who
		i+=1
	for key in mixed.after.objects:mixed.after.objects[key].owner="carol"
	r=reconcile(mixed.before,mixed.after,[mixed.gap],"bob")
	expect(r.ok and adds_exact(r,mixed.cells,"bob"),"mixed-owner closure roofs are all owned by the actor")
	expect(norm(r.cost)==expected(16) and r.refunds.is_empty(),"mixed-owner closure charges only the actor's single cost")

	# --- Manual mix: existing manual and auto roofs are kept and never re-charged.
	var mm:=closure()
	var manual:=[c.cells[0],c.cells[5]];var prior_auto:=[c.cells[10]]
	for s in [mm.before,mm.after]:
		roof_cells(s,manual,"carol",false)
		roof_cells(s,prior_auto,"dave")
	var missing:=[]
	for p in mm.cells:
		if p not in manual and p not in prior_auto:missing.append(p)
	r=reconcile(mm.before,mm.after,[mm.gap],"bob")
	expect(r.ok and adds_exact(r,missing,"bob"),"only the 13 missing cells are added")
	expect(norm(r.cost)==expected(13) and r.remove.is_empty() and r.refunds.is_empty(),"manual and prior auto roofs are not charged, removed or refunded")

	# --- Idempotence: applying the plan to a copy leaves nothing more to do.
	r=reconcile(c.before,c.after,[c.gap],"alice")
	var applied:=apply(c.after,r)
	expect(applied.roofs.size()==16,"applied copy has 16 roofs")
	expect(nothing(reconcile(c.before,applied,[c.gap],"alice")),"re-planning the same action after applying does not double charge")
	expect(nothing(reconcile(applied,applied,[c.gap],"alice")),"re-planning from the applied state is a no-op")
	expect(nothing(reconcile(applied,applied,[c.gap],"bob")),"another actor touching the roofed room is not charged")

	# --- Opening refunds automatic roofs to their original payers only.
	var op:=opening()
	r=reconcile(op.before,op.after,[op.hole],"erin")
	expect(r.ok and r.add.is_empty() and norm(r.cost).is_empty(),"opening adds and charges nothing")
	expect(sorted(r.remove)==keyset(op.alice+op.bob) and r.remove.size()==10,"opening removes exactly the 10 automatic roofs")
	for p in op.carol:expect(not r.remove.has(k(p)),"manual roof stays after opening "+k(p))
	expect(sorted(r.refunds.keys())==["alice","bob"],"refunds go only to original payers, not to the actor or manual owner")
	expect(norm(r.refunds.get("alice",{}))==expected(6) and norm(r.refunds.get("bob",{}))==expected(4),"refund totals per payer")
	expect(is_sorted_any(r.remove),"removed keys are in a deterministic sorted order")
	var opened:=apply(op.after,r)
	expect(opened.roofs.size()==4 and nothing(reconcile(op.before,opened,[op.hole],"erin")),"opening is idempotent once applied")

	# --- Floor removal: orphaned auto roof and the newly opened remainder are refunded, manual kept.
	var strip:=snap();var strip_cells:=add_room(strip,O,Vector2i(7,1),[DOOR])
	var hole:=Vector2i(13,10)
	roof_cells(strip,strip_cells.slice(0,6),"alice")
	roof_cells(strip,[Vector2i(16,10)],"carol",false)
	var strip_after:=strip.duplicate(true);strip_after.ground.erase(k(hole))
	r=reconcile(strip,strip_after,[hole],"alice")
	expect(r.ok and r.remove.has(k(hole)),"orphan auto roof over removed floor is removed")
	expect(sorted(r.remove)==keyset(strip_cells.slice(0,6)),"both split branches, including far cells, are cleared")
	expect(norm(r.refunds.get("alice",{}))==expected(6) and r.refunds.size()==1,"floor removal refunds the original payer")
	expect(not r.remove.has(k(Vector2i(16,10))) and r.add.is_empty() and norm(r.cost).is_empty(),"manual roof on far branch is kept")
	# Manual roof directly over the removed floor remains.
	var strip2:=snap();var strip2_cells:=add_room(strip2,O,Vector2i(7,1),[DOOR])
	roof_cells(strip2,[hole],"carol",false)
	var strip2_after:=strip2.duplicate(true);strip2_after.ground.erase(k(hole))
	expect(nothing(reconcile(strip2,strip2_after,[hole],"carol")),"manual roof over removed floor is not removed or refunded")
	expect(strip2_cells.size()==7,"strip fixture has 7 cells")

	# --- Divider wall through an auto-roofed room.
	var div:=snap();var div_cells:=add_room(div,O,Vector2i(6,4),[Vector2i(11,9)])
	roof_cells(div,div_cells,"alice")
	var divider:=[Vector2i(12,10),Vector2i(12,11),Vector2i(12,12),Vector2i(12,13)]
	var left:=[];var right:=[]
	for p in div_cells:
		if p.x<12:left.append(p)
		elif p.x>12:right.append(p)
	var div_after:=div.duplicate(true)
	for p in divider:div_after.objects[k(p)]=wall("bob")
	r=reconcile(div,div_after,divider,"bob")
	expect(r.ok and sorted(r.remove)==keyset(divider+right),"divider drops its own roofs and the doorless right room")
	expect(norm(r.refunds.get("alice",{}))==expected(16) and r.refunds.size()==1 and r.add.is_empty() and norm(r.cost).is_empty(),"divider refunds alice for 16 roofs")
	# Second door keeps the right room independently sealed.
	var div2:=div.duplicate(true);div2.objects[k(Vector2i(14,9))]=wall("alice","door")
	var div2_after:=div_after.duplicate(true);div2_after.objects[k(Vector2i(14,9))]=wall("alice","door")
	r=reconcile(div2,div2_after,divider,"bob")
	expect(r.ok and sorted(r.remove)==keyset(divider) and norm(r.refunds.get("alice",{}))==expected(4),"two doors: only the divider roofs are dropped")
	expect(r.add.is_empty() and norm(r.cost).is_empty(),"two doors: both sealed halves keep their roofs at no cost")
	# Unroofed sealed room split into two sealed rooms gets roofs on both halves.
	var div3:=div2.duplicate(true);div3.roofs.clear()
	var div3_after:=div2_after.duplicate(true);div3_after.roofs.clear()
	r=reconcile(div3,div3_after,divider,"bob")
	expect(r.ok and adds_exact(r,left+right,"bob") and norm(r.cost)==expected(20) and r.remove.is_empty(),"divider creates roofs for both newly sealed halves, not on the divider")

	# --- Merging rooms by removing a shared wall that stands on floor.
	var mg:=snap()
	var a_cells:=add_room(mg,O,Vector2i(4,4),[DOOR])
	var b_cells:=add_room(mg,Vector2i(15,10),Vector2i(4,4),[Vector2i(15,9)])
	var seam:=Vector2i(14,11)
	mg.ground[k(seam)]={"type":"floor","owner":"alice","items":{}}
	roof_cells(mg,a_cells,"alice")
	roof_cells(mg,[b_cells[0],b_cells[1]],"carol",false)
	var mg_after:=mg.duplicate(true);mg_after.objects.erase(k(seam))
	r=reconcile(mg,mg_after,[seam],"bob")
	expect(r.ok and adds_exact(r,[seam]+b_cells.slice(2),"bob"),"merged room roofs the seam and the unroofed half")
	expect(norm(r.cost)==expected(15) and r.remove.is_empty() and r.refunds.is_empty(),"merge charges the actor for 15 and keeps existing auto/manual roofs")

	# --- Neighbouring unrelated legacy room never acquires a roof.
	var nb:=closure()
	var legacy:=add_room(nb.before,Vector2i(15,10),Vector2i(4,4),[Vector2i(15,9)])
	add_room(nb.after,Vector2i(15,10),Vector2i(4,4),[Vector2i(15,9)])
	r=reconcile(nb.before,nb.after,[nb.gap],"alice")
	expect(r.ok and adds_exact(r,nb.cells,"alice") and norm(r.cost)==expected(16),"only the closed room is roofed")
	for p in legacy:expect(not r.add.has(k(p)),"legacy neighbour stays unroofed "+k(p))
	var far:=Vector2i(60,60)
	var lone_after:Dictionary=nb.after.duplicate(true);lone_after.objects[k(far)]=wall()
	expect(nothing(reconcile(nb.after,lone_after,[far],"alice")),"unrelated action far from rooms leaves legacy rooms alone")

	# --- Old automatic and manual roofs preserved when a sealed room is touched without change in sealing.
	var old:=snap();var old_cells:=add_room(old,O,Vector2i(4,4),[DOOR])
	roof_cells(old,old_cells.slice(0,8),"alice")
	roof_cells(old,old_cells.slice(8,13),"carol",false)
	var old_after:=old.duplicate(true);old_after.objects[k(Vector2i(12,12))]={"type":"bench","owner":"bob","items":{}}
	r=reconcile(old,old_after,[Vector2i(12,12)],"bob")
	expect(r.ok and adds_exact(r,old_cells.slice(13),"bob") and norm(r.cost)==expected(3),"touched sealed room only fills its 3 missing roofs")
	expect(r.remove.is_empty() and r.refunds.is_empty(),"old automatic roofs by another payer and manual roofs are preserved")

	# --- Invalid actor or recipe: rejected with empty plan, even where roofs/refunds would apply.
	for bad in [{"name":"x","wood":-1,"fiber":3},{"name":"x","wood":"lots"}]:
		expect(rejected(reconcile(c.before,c.after,[c.gap],"alice",bad)),"invalid recipe rejected on closure: "+str(bad))
		expect(rejected(reconcile(op.before,op.after,[op.hole],"erin",bad)),"invalid recipe rejected on opening: "+str(bad))
	expect(rejected(reconcile(c.before,c.after,[c.gap],"")),"empty actor rejected on closure")
	expect(rejected(reconcile(op.before,op.after,[op.hole],"")),"empty actor rejected on opening")

	# --- Size cap: 400 cells is a room, a larger affected component is rejected.
	var cap:=snap();var cap_cells:=add_room(cap,O,Vector2i(20,20),[DOOR]);cap.objects.erase(k(GAP))
	var cap_after:=cap.duplicate(true);cap_after.objects[k(GAP)]=wall()
	r=reconcile(cap,cap_after,[GAP],"alice")
	expect(r.ok and r.add.size()==400 and adds_exact(r,cap_cells,"alice") and norm(r.cost)==expected(400),"400-cell room is roofed at exact cost")
	var big:=snap();add_room(big,O,Vector2i(21,20),[DOOR]);big.objects.erase(k(GAP))
	var big_after:=big.duplicate(true);big_after.objects[k(GAP)]=wall()
	expect(rejected(reconcile(big,big_after,[GAP],"alice")),"420-cell affected room is truncated and rejected")
	var field:=snap()
	for y in range(0,25):
		for x in range(0,25):field.ground[k(Vector2i(x,y))]={"type":"floor","owner":"alice","items":{}}
	var field_after:=field.duplicate(true);field_after.objects[k(Vector2i(12,12))]=wall()
	expect(rejected(reconcile(field,field_after,[Vector2i(12,12)],"alice")),"open floor field over the cap is rejected")

	# --- Translated coordinates (including negative) behave identically.
	var base:=reconcile(c.before,c.after,[c.gap],"alice")
	for shift in [Vector2i(-60,-45),Vector2i(300,1200),Vector2i(-1,-1)]:
		var tc:=closure(O+shift)
		r=reconcile(tc.before,tc.after,[tc.gap],"alice")
		var moved:=[]
		for p in c.cells:moved.append(p+shift)
		expect(r.ok and adds_exact(r,moved,"alice") and norm(r.cost)==norm(base.cost),"translated closure "+str(shift))
		var to:=opening(O+shift)
		r=reconcile(to.before,to.after,[to.hole],"erin")
		expect(r.ok and r.remove.size()==10 and sorted(r.remove)==keyset(to.alice+to.bob) and norm(r.refunds.get("alice",{}))==expected(6) and norm(r.refunds.get("bob",{}))==expected(4),"translated opening "+str(shift))

	# --- Insertion-order independence and deterministic ordering.
	var r1:=reconcile(c.before,c.after,[c.gap],"alice")
	var r2:=reconcile(reorder(c.before),reorder(c.after),[c.gap,c.gap],"alice")
	expect(r1==r2 and r1.add.keys()==r2.add.keys(),"closure result independent of insertion order and duplicate touches")
	var o1:=reconcile(op.before,op.after,[op.hole],"erin")
	var o2:=reconcile(reorder(op.before),reorder(op.after),[op.hole],"erin")
	expect(o1==o2 and o1.remove==o2.remove and o1.refunds.keys()==o2.refunds.keys(),"opening result independent of insertion order")
	var d1:=reconcile(div3,div3_after,divider,"bob")
	var rev_div:=divider.duplicate();rev_div.reverse()
	var d2:=reconcile(reorder(div3),reorder(div3_after),rev_div,"bob")
	expect(d1==d2 and d1.add.keys()==d2.add.keys(),"divider result independent of touched order")

	# --- Immutability of all inputs.
	var ib:Dictionary=op.before.duplicate(true);var ia:Dictionary=op.after.duplicate(true)
	var touched:=pts([op.hole]);var tcopy:=touched.duplicate()
	var rec:=recipe();var rcopy:=rec.duplicate(true)
	r=Plan.reconcile(op.before,op.after,touched,"erin",rec)
	expect(op.before==ib and op.after==ia,"opening does not mutate before/after")
	expect(touched==tcopy and rec==rcopy,"opening does not mutate touched or recipe")
	var cb:Dictionary=c.before.duplicate(true);var ca:Dictionary=c.after.duplicate(true)
	r=Plan.reconcile(c.before,c.after,pts([c.gap]),"alice",rec)
	expect(c.before==cb and c.after==ca and rec==rcopy,"closure does not mutate inputs")
	expect(not c.after.roofs.has(k(c.cells[0])),"planned roofs are not written into after")
	r.add[k(c.cells[0])].items["x"]=1
	expect(reconcile(c.before,c.after,[c.gap],"alice").add[k(c.cells[0])]==auto_roof("alice"),"returned roofs are fresh, not shared state")
	expect(World.BUILD["roof"]==R,"real roof recipe untouched")

	print("AUTO_ROOF_PLAN_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
