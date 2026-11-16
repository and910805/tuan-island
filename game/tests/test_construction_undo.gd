extends SceneTree
# Independent behavioural tests for the pure construction-undo module.
# The record returned by capture() is treated as opaque throughout.
const Undo=preload("res://scripts/construction_undo.gd")

const A:="tok-alice-SECRET"
const B:="tok-bob-SECRET"
const C:="tok-carol-SECRET"
const D:="tok-dave-SECRET"
const LIMIT:=1000000000
const KEY:="home:construction"
const G:={"home:construction":7}
# Recipes used by fixtures (mirrors the game's build table values).
const R_FLOOR:={"wood":2}
const R_CHEST:={"wood":20}
const R_DOOR:={"wood":6,"fiber":2}
const R_ROOF:={"wood":1,"fiber":3}

var checks:=0
var failures:=0

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

static func k(x:int,y:int) -> String:
	return "%d,%d"%[x,y]

func snap(v) -> String:
	return var_to_str(v)

func obj(type:String,owner:String,extra:Dictionary={}) -> Dictionary:
	var o:={"type":type,"owner":owner,"items":{}}
	o.merge(extra,true)
	return o

func S(ground:Dictionary,objects:Dictionary,roofs:Dictionary,players:Dictionary) -> Dictionary:
	return {"ground":ground.duplicate(true),"objects":objects.duplicate(true),"roofs":roofs.duplicate(true),"players":players.duplicate(true)}

func base_players() -> Dictionary:
	# Carol and Dave are offline: only their persisted records exist.
	return {
		A:{"name":"A","coins":50,"inventory":{"wood":40,"stone":10,"fiber":30},"builds":3},
		B:{"name":"B","inventory":{"wood":0,"fiber":0,"tea_leaf":4}},
		C:{"inventory":{"stone":2}},
		D:{"inventory":{"wood":5}},
	}

func add(inv:Dictionary,delta:Dictionary,sign:int) -> void:
	for item in delta:inv[item]=int(inv.get(item,0))+sign*int(delta[item])

func times(r:Dictionary,n:int) -> Dictionary:
	var out:={}
	for item in r:out[item]=int(r[item])*n
	return out

# Inventories compared ignoring zero-valued entries (zero keys may or may not be kept).
func inv_eq(a,b) -> bool:
	if not (a is Dictionary and b is Dictionary):return false
	for item in a:
		if int(a[item])!=int(b.get(item,0)):return false
	for item in b:
		if int(b[item])!=int(a.get(item,0)):return false
	return true

# ---- Call wrappers that also assert input immutability ---------------------
func cap(before,after,actor:String,guard,label:String) -> Dictionary:
	var s:=[snap(before),snap(after),snap(guard)]
	var r:Dictionary=Undo.capture(before,after,actor,guard)
	expect([snap(before),snap(after),snap(guard)]==s,label+": capture inputs unmodified")
	return r

func prep(current,actor:String,record,revisions,label:String) -> Dictionary:
	var s:=[snap(current),snap(record),snap(revisions)]
	var r:Dictionary=Undo.prepare(current,actor,record,revisions)
	expect([snap(current),snap(record),snap(revisions)]==s,label+": prepare inputs unmodified")
	return r

func msg_ok(r:Dictionary,label:String) -> void:
	var m=r.get("message")
	expect(typeof(m)==TYPE_STRING and m!="",label+": has message")
	expect(typeof(m)==TYPE_STRING and not m.contains("SECRET") and not m.contains("tok-"),label+": no token in message")

func cap_fail(r:Dictionary,label:String) -> void:
	expect(r.get("ok")==false,label+": capture should fail")
	msg_ok(r,label)
	var rec=r.get("record")
	expect(rec==null or ((rec is Dictionary or rec is Array) and rec.is_empty()),label+": no usable record on failure")

func prep_fail(r:Dictionary,label:String) -> void:
	expect(r.get("ok")==false,label+": prepare should fail")
	msg_ok(r,label)
	var l=r.get("layers");var i=r.get("inventories")
	expect(l==null or (l is Dictionary and l.is_empty()),label+": nothing staged in layers")
	expect(i==null or (i is Dictionary and i.is_empty()),label+": nothing staged in inventories")

func cap_ok(before,after,actor:String,label:String):
	var r:=cap(before,after,actor,G,label)
	expect(r.get("ok")==true,label+": capture ok")
	if r.get("ok")==true:msg_ok(r,label)
	return r.get("record")

func layers_are(r:Dictionary,want:Dictionary,label:String) -> void:
	var l=r.get("layers")
	expect(l is Dictionary,label+": layers dictionary")
	if not (l is Dictionary):return
	for name in ["ground","objects","roofs"]:
		expect(l.get(name)==want[name],label+": staged "+name+" correct")

# ---- Fixtures ---------------------------------------------------------------
# w x h floor interior at (ox,oy) ringed by A's walls; door cell optional.
func room(ox:int,oy:int,w:int,h:int,door:String,with_door:bool) -> Dictionary:
	var ground:={};var objects:={}
	for y in range(oy-1,oy+h+1):
		for x in range(ox-1,ox+w+1):
			if x==ox-1 or x==ox+w or y==oy-1 or y==oy+h:objects[k(x,y)]=obj("wall",A)
			else:ground[k(x,y)]=obj("floor",A)
	objects.erase(door)
	if with_door:objects[door]=obj("door",A,{"open":false})
	return {"ground":ground,"objects":objects}

func run() -> void:
	# =========================================================================
	# Single build (chest) inverse
	# =========================================================================
	var p0:=base_players()
	var before:=S({},{},{},p0)
	var after:=S({},{k(3,3):obj("chest",A)},{},p0)
	add(after.players[A].inventory,R_CHEST,-1)
	var rec=cap_ok(before,after,A,"single build")
	var current:=after.duplicate(true)
	var r:=prep(current,A,rec,G,"single build")
	expect(r.get("ok")==true,"single build undo ok")
	msg_ok(r,"single build undo")
	layers_are(r,before,"single build undo")
	expect(inv_eq(r.get("inventories",{}).get(A),before.players[A].inventory),"single build: chest cost refunded to actor")
	expect(not r.get("inventories",{}).has(B) and not r.get("inventories",{}).has(C),"single build: unrelated owners not staged")
	# Pure: repeated call gives same result.
	var r2:=prep(current,A,rec,G,"single build repeat")
	expect(snap(r2)==snap(r),"prepare is deterministic")
	# Staged results are copies.
	if r.get("ok")==true:
		r.layers.objects[k(0,0)]=obj("wall",A)
		r.inventories[A]["wood"]=12345
		expect(not current.objects.has(k(0,0)) and int(current.players[A].inventory.wood)==20,"staged data does not alias current")

	# Subsequent unrelated inventory gains / layer edits preserved.
	current=after.duplicate(true)
	current.players[A].inventory.wood=25          # gained 5 wood since
	current.players[A].inventory["tea_leaf"]=3    # gained a new item
	current.ground[k(9,9)]=obj("floor",B)
	current.objects[k(8,8)]=obj("lamp",B)
	current.roofs[k(9,9)]=obj("roof",B,{"auto":true})
	var revs:={KEY:7,"other:unrelated":99}
	r=prep(current,A,rec,revs,"unrelated edits")
	expect(r.get("ok")==true,"undo ok despite unrelated later edits")
	layers_are(r,{"ground":{k(9,9):obj("floor",B)},"objects":{k(8,8):obj("lamp",B)},"roofs":{k(9,9):obj("roof",B,{"auto":true})}},"unrelated edits")
	expect(inv_eq(r.get("inventories",{}).get(A),{"wood":45,"stone":10,"fiber":30,"tea_leaf":3}),"later gains kept, refund applied on top")

	# Overflow on refund.
	current=after.duplicate(true)
	current.players[A].inventory.wood=LIMIT-20
	r=prep(current,A,rec,G,"refund exact cap")
	expect(r.get("ok")==true and int(r.get("inventories",{}).get(A,{}).get("wood",-1))==LIMIT,"refund to exactly the cap allowed")
	current.players[A].inventory.wood=LIMIT-19
	prep_fail(prep(current,A,rec,G,"refund overflow"),"refund overflow")

	# Changed after: container now holds items / object replaced / object gone.
	current=after.duplicate(true)
	current.objects[k(3,3)].items={"wood":1}
	prep_fail(prep(current,A,rec,G,"chest filled"),"chest filled after build")
	current=after.duplicate(true)
	current.objects[k(3,3)]=obj("chest",B)
	current.players[A].inventory.wood=40
	prep_fail(prep(current,A,rec,G,"chest replaced"),"object replaced by another owner")
	current=after.duplicate(true)
	current.objects[k(3,3)]=obj("table",A)
	prep_fail(prep(current,A,rec,G,"object type changed"),"object type changed")
	current=after.duplicate(true)
	current.objects.erase(k(3,3))
	prep_fail(prep(current,A,rec,G,"object gone"),"built object already gone")

	# Revision guards: missing / mismatch / ABA.
	current=after.duplicate(true)
	prep_fail(prep(current,A,rec,{},"no revisions"),"missing revisions")
	prep_fail(prep(current,A,rec,{"other:unrelated":7},"missing dep"),"missing dependency key")
	prep_fail(prep(current,A,rec,{KEY:6},"older rev"),"mismatched older revision")
	prep_fail(prep(current,A,rec,{KEY:8},"ABA"),"ABA: identical state but revision advanced")
	for bad in ["7",7.5,NAN,INF,-1,true,null,[7]]:
		prep_fail(prep(current,A,rec,{KEY:bad},"bad rev"),"malformed revision value "+var_to_str(bad))

	# Unauthorized actors / invalid records.
	prep_fail(prep(current,B,rec,G,"other actor"),"non-matching actor")
	prep_fail(prep(current,"",rec,G,"empty actor"),"empty actor")
	prep_fail(prep(current,"tok-ghost-SECRET",rec,G,"ghost actor"),"actor not persisted")
	prep_fail(prep(current,A,{},G,"empty record"),"empty record")
	var big:="tok-"+"x".repeat(5000)
	var cur_big:=current.duplicate(true);cur_big.players[big]={"inventory":{"wood":1}}
	prep_fail(prep(cur_big,big,rec,G,"oversized actor prepare"),"oversized actor in prepare")

	# =========================================================================
	# Batch build inverse
	# =========================================================================
	p0=base_players()
	var path:={k(0,0):obj("path",A)}
	before=S(path,{},{},p0)
	var g2:=path.duplicate(true)
	for x in [1,2,3]:g2[k(x,1)]=obj("floor",A)
	after=S(g2,{},{},p0)
	add(after.players[A].inventory,times(R_FLOOR,3),-1)
	rec=cap_ok(before,after,A,"batch build")
	r=prep(after.duplicate(true),A,rec,G,"batch build")
	expect(r.get("ok")==true,"batch undo ok")
	layers_are(r,before,"batch undo")
	expect(inv_eq(r.get("inventories",{}).get(A),p0[A].inventory),"batch: all floor costs refunded")
	# One cell of the batch changed blocks the whole undo.
	current=after.duplicate(true)
	current.ground[k(2,1)]=obj("path",A)
	prep_fail(prep(current,A,rec,G,"batch partial change"),"batch with one changed cell")

	# =========================================================================
	# Remove restores (door with extra fields)
	# =========================================================================
	p0=base_players()
	var door:=obj("door",A,{"open":false})
	before=S({},{k(4,4):door},{},p0)
	after=S({},{},{},p0)
	add(after.players[A].inventory,R_DOOR,1)
	rec=cap_ok(before,after,A,"remove")
	r=prep(after.duplicate(true),A,rec,G,"remove")
	expect(r.get("ok")==true,"remove undo ok")
	layers_are(r,before,"remove undo")
	expect(r.get("layers",{}).get("objects",{}).get(k(4,4))==door,"removed object restored with its fields")
	expect(inv_eq(r.get("inventories",{}).get(A),p0[A].inventory),"remove undo charges the refund back")
	# Insufficient reverse resources.
	current=after.duplicate(true)
	current.players[A].inventory.wood=5
	prep_fail(prep(current,A,rec,G,"insufficient wood"),"insufficient wood to re-place")
	current=after.duplicate(true)
	current.players[A].inventory.fiber=1
	prep_fail(prep(current,A,rec,G,"insufficient fiber"),"insufficient fiber to re-place")
	current=after.duplicate(true)
	current.players[A].inventory.erase("fiber")
	prep_fail(prep(current,A,rec,G,"missing item"),"reverse item absent")
	# Cell occupied since.
	current=after.duplicate(true)
	current.objects[k(4,4)]=obj("lamp",B)
	prep_fail(prep(current,A,rec,G,"cell reoccupied"),"removed cell reoccupied")

	# =========================================================================
	# Move inverse
	# =========================================================================
	p0=base_players()
	var chair:=obj("chair",A)
	before=S({},{k(2,2):chair},{},p0)
	after=S({},{k(5,2):chair},{},p0)
	rec=cap_ok(before,after,A,"move")
	current=after.duplicate(true)
	r=prep(current,A,rec,G,"move")
	expect(r.get("ok")==true,"move undo ok")
	layers_are(r,before,"move undo")
	var mi:Dictionary=r.get("inventories",{}) if r.get("inventories") is Dictionary else {}
	expect(inv_eq(mi.get(A,current.players[A].inventory),current.players[A].inventory),"move undo leaves inventory unchanged")
	for owner in mi:expect(inv_eq(mi[owner],current.players[owner].inventory),"move undo stages no inventory delta")
	current=after.duplicate(true)
	current.objects[k(2,2)]=obj("lamp",B)
	prep_fail(prep(current,A,rec,G,"move origin occupied"),"move origin occupied")
	current=after.duplicate(true)
	current.objects[k(5,2)]=obj("chair",B)
	prep_fail(prep(current,A,rec,G,"moved object changed"),"moved object changed owner")

	# =========================================================================
	# Roofs: closing build adds actor roofs
	# =========================================================================
	var dk:=k(9,11)
	var open_room:=room(10,10,2,3,dk,false)
	var closed_room:=room(10,10,2,3,dk,true)
	var cells:=[k(10,10),k(11,10),k(10,11),k(11,11),k(10,12),k(11,12)]
	p0=base_players()
	var roofs_a:={}
	for c in cells:roofs_a[c]=obj("roof",A,{"auto":true})
	before=S(open_room.ground,open_room.objects,{},p0)
	after=S(closed_room.ground,closed_room.objects,roofs_a,p0)
	add(after.players[A].inventory,R_DOOR,-1)
	add(after.players[A].inventory,times(R_ROOF,6),-1)
	rec=cap_ok(before,after,A,"close room")
	r=prep(after.duplicate(true),A,rec,G,"close room")
	expect(r.get("ok")==true,"close-room undo ok")
	layers_are(r,before,"close-room undo")
	expect(inv_eq(r.get("inventories",{}).get(A),p0[A].inventory),"door + roof costs refunded")

	# =========================================================================
	# Roofs: opening removes mixed-owner roofs, refunding offline owners
	# =========================================================================
	p0=base_players()
	var owners:=[B,C,B,C,B,C]
	var roofs_m:={}
	for i in cells.size():roofs_m[cells[i]]=obj("roof",owners[i],{"auto":true})
	before=S(closed_room.ground,closed_room.objects,roofs_m,p0)
	after=S(open_room.ground,open_room.objects,{},p0)
	add(after.players[A].inventory,R_DOOR,1)
	add(after.players[B].inventory,times(R_ROOF,3),1)
	add(after.players[C].inventory,times(R_ROOF,3),1)
	rec=cap_ok(before,after,A,"open room mixed owners")
	r=prep(after.duplicate(true),A,rec,G,"open room")
	expect(r.get("ok")==true,"open-room undo ok")
	layers_are(r,before,"open-room undo")
	var oi=r.get("inventories",{})
	expect(inv_eq(oi.get(A),p0[A].inventory),"actor pays door back")
	expect(inv_eq(oi.get(B),p0[B].inventory),"bob's roof refund reversed")
	expect(inv_eq(oi.get(C),p0[C].inventory),"offline carol's roof refund reversed")
	expect(not oi.has(D),"unaffected dave not staged")
	# Later unrelated gain by an offline owner kept.
	current=after.duplicate(true)
	current.players[B].inventory.tea_leaf=10
	r=prep(current,A,rec,G,"owner later gain")
	expect(r.get("ok")==true and inv_eq(r.get("inventories",{}).get(B),{"wood":0,"fiber":0,"tea_leaf":10}),"owner's later gain kept")
	# No borrowing: bob spent part of his refund; rich actor cannot cover.
	current=after.duplicate(true)
	current.players[B].inventory.fiber=8
	current.players[A].inventory.wood=500;current.players[A].inventory.fiber=500
	prep_fail(prep(current,A,rec,G,"no borrowing bob"),"owner refund reversal cannot borrow from actor")
	current=after.duplicate(true)
	current.players[C].inventory.wood=2
	current.players[D].inventory.wood=99
	prep_fail(prep(current,A,rec,G,"no borrowing carol"),"offline owner short; others cannot cover")
	# A roof changed since blocks.
	current=after.duplicate(true)
	current.roofs[cells[0]]=obj("roof",B,{"auto":true})
	prep_fail(prep(current,A,rec,G,"roof reappeared"),"roof cell changed since")

	# =========================================================================
	# Capture rejections
	# =========================================================================
	p0=base_players()
	var b0:=S({},{},{},p0)
	var a0:=S({},{k(3,3):obj("chest",A)},{},p0)
	add(a0.players[A].inventory,R_CHEST,-1)
	expect(cap(b0,a0,A,G,"baseline").get("ok")==true,"capture baseline ok")
	# Zero changes: nothing undoable.
	var z:=cap(b0,b0.duplicate(true),A,G,"zero changes")
	if z.get("ok")==true:
		var zr:=prep(b0.duplicate(true),A,z.get("record"),G,"zero changes prepare")
		expect(zr.get("ok")!=true or (zr.layers.ground==b0.ground and zr.layers.objects==b0.objects and zr.layers.roofs==b0.roofs and zr.get("inventories",{}).is_empty()),"zero-change record cannot change anything")
	else:
		cap_fail(z,"zero changes")
	# Unauthorized actor / foreign non-roof change.
	cap_fail(cap(b0,a0,B,G,"wrong actor"),"capture by actor who did not make the change")
	cap_fail(cap(b0,a0,"",G,"empty actor"),"capture empty actor")
	cap_fail(cap(b0,a0,"tok-ghost-SECRET",G,"ghost actor"),"capture actor not persisted")
	var bf:=S({},{k(5,5):obj("wall",B)},{},p0)
	var af:=S({},{k(3,3):obj("chest",A)},{},p0)
	add(af.players[A].inventory,R_CHEST,-1)
	add(af.players[B].inventory,{"wood":3},1)
	cap_fail(cap(bf,af,A,G,"foreign object removed"),"foreign non-roof object change")
	bf=S({k(6,6):obj("floor",B)},{},{},p0)
	af=S({k(6,6):obj("path",A)},{},{},p0)
	add(af.players[A].inventory,{"stone":2},-1)
	cap_fail(cap(bf,af,A,G,"foreign ground replaced"),"foreign ground change")
	# Oversized actor.
	var pb:=base_players();pb[big]={"inventory":{"wood":40}}
	var bb:=S({},{},{},pb)
	var ab:=S({},{k(3,3):obj("chest",big)},{},pb)
	ab.players[big].inventory.wood=20
	cap_fail(cap(bb,ab,big,G,"oversized actor"),"oversized actor")
	# Invalid guards.
	for guard in [{},{"":7},{1:7},{KEY:-1},{KEY:1.5},{KEY:NAN},{KEY:INF},{KEY:"7"},{KEY:true},{KEY:null},{KEY:[7]}]:
		cap_fail(cap(b0,a0,A,guard,"bad guard"),"invalid guard "+var_to_str(guard))

	# Malformed snapshots (applied to before and to after).
	var mutations:=[
		func(s):s.erase("ground"),
		func(s):s.erase("players"),
		func(s):s.objects=[],
		func(s):s.roofs=null,
		func(s):s.players=[],
		func(s):s.objects[k(7,7)]="chest",
		func(s):s.objects[k(7,7)]={"owner":A,"items":{}},
		func(s):s.objects[k(7,7)]={"type":5,"owner":A,"items":{}},
		func(s):s.objects[k(7,7)]={"type":"lamp","owner":7,"items":{}},
		func(s):s.objects[k(7,7)]={"type":"lamp","owner":"","items":{}},
		func(s):s.objects[k(7,7)]={"type":"lamp","items":{}},
		func(s):s.roofs[k(7,7)]={"type":"roof","owner":"tok-ghost-SECRET","items":{},"auto":true},
		func(s):s.players[A]=null,
		func(s):s.players[A]={"name":"no inventory"},
		func(s):s.players[A].inventory=[],
	]
	for i in mutations.size():
		var mb:=b0.duplicate(true);mutations[i].call(mb)
		cap_fail(cap(mb,a0,A,G,"malformed before #%d"%i),"malformed before #%d"%i)
		var ma:=a0.duplicate(true);mutations[i].call(ma)
		cap_fail(cap(b0,ma,A,G,"malformed after #%d"%i),"malformed after #%d"%i)
	var bads:=[-1,-1.0,1.5,NAN,INF,-INF,true,"3",null,[1],{},LIMIT+1]
	for bad in bads:
		var label:=var_to_str(bad)
		var mb:=b0.duplicate(true);mb.players[A].inventory.stone=bad
		var ma:=a0.duplicate(true);ma.players[A].inventory.stone=bad
		cap_fail(cap(mb,ma,A,G,"bad count"),"capture bad actor count "+label)
		var mo:=b0.duplicate(true);mo.players[A].inventory.wood=bad
		cap_fail(cap(mo,a0,A,G,"bad before wood"),"capture bad before wood "+label)

	# Malformed current state in prepare (fresh valid record).
	rec=cap(b0,a0,A,G,"prepare malformed baseline").get("record")
	expect(prep(a0.duplicate(true),A,rec,G,"prepare baseline").get("ok")==true,"prepare baseline ok")
	for i in mutations.size():
		var mc:=a0.duplicate(true);mutations[i].call(mc)
		prep_fail(prep(mc,A,rec,G,"malformed current #%d"%i),"malformed current #%d"%i)
	for bad in bads:
		var mc:=a0.duplicate(true);mc.players[A].inventory.wood=bad
		prep_fail(prep(mc,A,rec,G,"bad current count"),"prepare bad actor count "+var_to_str(bad))
		mc=a0.duplicate(true);mc.players[A].inventory.stone=bad
		prep_fail(prep(mc,A,rec,G,"bad current unrelated count"),"prepare bad unrelated actor count "+var_to_str(bad))

	persistence_checks()
	print("CONSTRUCTION_UNDO_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

# Root verification: the save format is JSON, so current snapshots and undo
# records may each be loaded (floating whole numbers) or still live integers.
func persistence_checks()->void:
	var before:=S({},{},{},base_players())
	var after:=before.duplicate(true)
	after.objects["3,3"]=obj("chest",A)
	add(after.players[A].inventory,R_CHEST,-1)
	var captured:=cap(before,after,A,{KEY:0},"zero revision capture")
	expect(captured.ok,"revision zero accepted")
	if not captured.ok:return
	var record:Dictionary=captured.record
	var path:=OS.get_environment("TEMP").path_join("tuan-undo-roundtrip-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	expect(file!=null,"open isolated persistence fixture")
	if file==null:return
	file.store_string(JSON.stringify({"snapshot":after,"record":record,"guard":{KEY:0}}))
	file.close()
	var loaded=JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(path)
	expect(loaded is Dictionary,"reload actual JSON file")
	if not loaded is Dictionary:return
	for current in [after,loaded.snapshot]:
		for saved_record in [record,loaded.record]:
			var result:=prep(current,A,saved_record,loaded.guard,"JSON/live cross product")
			expect(result.ok,"JSON types do not invalidate unchanged entry")
			if result.ok:
				expect(result.layers.objects.is_empty(),"JSON inverse removes only placed chest")
				expect(inv_eq(result.inventories[A],before.players[A].inventory),"JSON inverse refund exact")
	var spent:Dictionary=loaded.snapshot.duplicate(true)
	spent.players[A].inventory.tea_leaf=6
	var result:=prep(spent,A,loaded.record,loaded.guard,"new runtime StringName key")
	expect(result.ok and result.inventories[A].get("tea_leaf")==6,"runtime item gains survive loaded undo")
	prep_fail(prep(loaded.snapshot,A,loaded.record,{KEY:1},"JSON ABA"),"JSON ABA blocks")
	# JSON's numeric conversion must not coerce bool flags into whole revisions.
	var broken:Dictionary=loaded.record.duplicate(true)
	broken.version=true
	prep_fail(prep(loaded.snapshot,A,broken,loaded.guard,"boolean version"),"boolean version rejected")
	var bad_after:=after.duplicate(true)
	bad_after.objects["3,3"].open=true
	var good_after:=after.duplicate(true)
	good_after.objects["3,3"].open=1
	var numeric_record:Dictionary=cap(before,good_after,A,G,"numeric fixture").get("record",{})
	prep_fail(prep(bad_after,A,numeric_record,G,"boolean is not integer"),"bool field cannot match number")
