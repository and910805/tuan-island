extends SceneTree
## Headless unit test for the pure material supply helper (res://scripts/material_supply.gd).
## Helper foundation only (NOT live gameplay): no World, networking, chests or UI.
## Expected debits/afters below are hand-computed, not derived from the helper.
## Run: godot --headless --path game --script res://tests/test_material_supply.gd

const M=preload("res://scripts/material_supply.gd")
const Q=preload("res://scripts/cooking_queue.gd")
const CAP:=1000000000
const JOB_ID:="0123456789abcdef0123456789abcdef"
const OK_KEYS:="backpack_after,chest_after,from_backpack,from_chest,missing,ok,supplied_inventory"
const SHORT_KEYS:="from_backpack,from_chest,message,missing,ok"
const POOL:=["fiber","herb","radish","salt","wheat","wood"]

var checks:=0
var failures:=0

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize()->void:
	call_deferred("run")

func run()->void:
	test_mixed_multi_ingredient()
	test_backpack_priority()
	test_exhausted_or_empty_chest()
	test_insufficient_no_mutation()
	test_near_cap_aggregate()
	test_exact_splits()
	test_unrelated_and_zero_preserved()
	test_alias_isolation()
	test_json_whole_floats()
	test_lexical_determinism()
	test_invalid_inputs()
	test_property(20261114,20)
	test_property(7,20)
	print("MATERIAL_SUPPLY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

# ---------------------------------------------------------------- helpers

## Key-order-insensitive but type-sensitive text (5 vs 5.0 differ).
func canon(v:Variant)->String:
	if v is Dictionary:
		var d:Dictionary=v
		var keys:Array=d.keys()
		keys.sort()
		var parts:=PackedStringArray()
		for k:Variant in keys:parts.append(var_to_str(k)+":"+canon(d[k]))
		return "{"+",".join(parts)+"}"
	return var_to_str(v)

func same(a:Variant,b:Variant)->bool:
	return canon(a)==canon(b)

func key_list(d:Dictionary)->String:
	var keys:Array=d.keys()
	keys.sort()
	return ",".join(PackedStringArray(keys))

func all_int(d:Dictionary)->bool:
	for k:Variant in d:
		if typeof(d[k])!=TYPE_INT:return false
	return true

func enqueue(cost:Dictionary,inventory:Dictionary)->Dictionary:
	var recipes:={"test_stew":{"ingredients":cost.duplicate(true),"time":5.0,"yield":1}}
	return Q.enqueue(Q.empty_state(),recipes,0.0,"tester","test_stew",JOB_ID,inventory)

func expect_ok(r:Dictionary,fb:Dictionary,fc:Dictionary,bag_after:Dictionary,box_after:Dictionary,supplied:Dictionary,label:String)->void:
	expect(r.get("ok")==true and key_list(r)==OK_KEYS,label+" ok shape "+str(r))
	if r.get("ok")!=true:return
	expect(same(r.from_backpack,fb) and same(r.from_chest,fc) and same(r.missing,{}),label+" debits "+canon(r.from_backpack)+canon(r.from_chest))
	expect(same(r.backpack_after,bag_after),label+" backpack_after "+canon(r.backpack_after))
	expect(same(r.chest_after,box_after),label+" chest_after "+canon(r.chest_after))
	expect(same(r.supplied_inventory,supplied),label+" supplied "+canon(r.supplied_inventory))

func expect_short(r:Dictionary,missing:Dictionary,fb:Dictionary,fc:Dictionary,label:String)->void:
	expect(r.get("ok")==false and key_list(r)==SHORT_KEYS,label+" short shape "+str(r))
	if r.get("ok")!=false or not r.has("missing"):return
	expect(r.message==M.MSG_SHORT,label+" message")
	expect(same(r.missing,missing),label+" missing "+canon(r.missing))
	expect(same(r.from_backpack,fb) and same(r.from_chest,fc),label+" planned debits")

func expect_invalid(r:Dictionary,message:String,label:String)->void:
	expect(r.size()==2 and r.get("ok")==false and r.get("message")==message,label+" -> "+str(r))

# ---------------------------------------------------------------- tests

func test_mixed_multi_ingredient()->void:
	var cost:={"wheat":3,"fiber":2,"radish":4}
	var bag:={"wheat":5,"fiber":1,"radish":0,"stone":7}
	var box:={"fiber":4,"radish":9,"wood":2,"wheat":10}
	var r:=M.plan(cost,bag,box)
	expect_ok(r,{"wheat":3,"fiber":1},{"fiber":1,"radish":4},
		{"wheat":2,"fiber":0,"radish":0,"stone":7},
		{"fiber":3,"radish":5,"wood":2,"wheat":10},
		{"wheat":5,"fiber":2,"radish":4,"stone":7},"mixed")
	# The backpack alone cannot pay; the supplied inventory can and lands on backpack_after.
	expect(enqueue(cost,bag).get("ok")==false,"mixed backpack alone is short for enqueue")
	var q:=enqueue(cost,r.supplied_inventory)
	expect(q.get("ok")==true and same(q.inventory,r.backpack_after),"mixed enqueue lands on backpack_after "+str(q))

func test_backpack_priority()->void:
	var r:=M.plan({"wheat":2},{"wheat":2},{"wheat":50})
	expect_ok(r,{"wheat":2},{},{"wheat":0},{"wheat":50},{"wheat":2},"priority exact bag")
	r=M.plan({"wheat":2,"salt":1},{"wheat":9,"salt":1},{"wheat":9,"salt":9})
	expect_ok(r,{"wheat":2,"salt":1},{},{"wheat":7,"salt":0},{"wheat":9,"salt":9},{"wheat":9,"salt":1},"priority surplus bag")
	# Chest only tops up the remainder after the backpack is drained.
	r=M.plan({"wheat":5},{"wheat":3},{"wheat":50})
	expect_ok(r,{"wheat":3},{"wheat":2},{"wheat":0},{"wheat":48},{"wheat":5},"priority remainder")

func test_exhausted_or_empty_chest()->void:
	expect_short(M.plan({"radish":3},{"radish":1},{}),{"radish":2},{"radish":1},{},"empty chest")
	expect_short(M.plan({"radish":3},{"radish":1},{"radish":0}),{"radish":2},{"radish":1},{},"exhausted chest")
	expect_short(M.plan({"radish":3},{},{"radish":0,"wheat":4}),{"radish":3},{},{},"empty bag exhausted chest")
	expect_ok(M.plan({"radish":3},{"radish":3}),{"radish":3},{},{"radish":0},{},{"radish":3},"default chest ok")
	expect_short(M.plan({"radish":3},{"radish":2}),{"radish":1},{"radish":2},{},"default chest short")
	# A chest emptied by this plan stays listed with zero.
	expect_ok(M.plan({"herb":4},{"herb":1},{"herb":3}),{"herb":1},{"herb":3},{"herb":0},{"herb":0},{"herb":4},"chest drained to zero")

func test_insufficient_no_mutation()->void:
	var cost:={"a":5,"b":2,"c":1}
	var bag:={"a":2,"b":2,"keep":1}
	var box:={"a":1,"c":0,"z":3}
	var before:=var_to_str([cost,bag,box])
	var r:=M.plan(cost,bag,box)
	expect_short(r,{"a":2,"c":1},{"a":2,"b":2},{"a":1},"insufficient")
	expect(var_to_str([cost,bag,box])==before,"insufficient leaves inputs untouched")
	expect(not r.has("backpack_after") and not r.has("chest_after") and not r.has("supplied_inventory"),"insufficient has no after outputs")

func test_near_cap_aggregate()->void:
	# Combined stock 1.5e9 exceeds the cap but each source is individually valid.
	var cost:={"gem":CAP}
	var bag:={"gem":600000000}
	var box:={"gem":900000000}
	var r:=M.plan(cost,bag,box)
	expect_ok(r,{"gem":600000000},{"gem":400000000},{"gem":0},{"gem":500000000},{"gem":CAP},"near cap split")
	var q:=enqueue(cost,r.supplied_inventory)
	expect(q.get("ok")==true and same(q.inventory,{"gem":0}),"near cap enqueue "+str(q))
	r=M.plan({"gem":CAP},{"gem":CAP},{"gem":CAP})
	expect_ok(r,{"gem":CAP},{},{"gem":0},{"gem":CAP},{"gem":CAP},"cap bag covers")
	# A full unrelated stack in the bag is not touched by a chest top-up of another item.
	r=M.plan({"salt":2},{"gem":CAP,"salt":1},{"salt":CAP,"gem":CAP})
	expect_ok(r,{"salt":1},{"salt":1},{"gem":CAP,"salt":0},{"salt":CAP-1,"gem":CAP},{"gem":CAP,"salt":2},"full unrelated stack")
	expect_short(M.plan({"gem":CAP},{"gem":CAP-2},{"gem":1}),{"gem":1},{"gem":CAP-2},{"gem":1},"near cap short by one")

func test_exact_splits()->void:
	# [need, bag, chest, from_bag, from_chest, short]
	var rows:=[[5,5,0,5,0,0],[5,0,5,0,5,0],[5,2,3,2,3,0],[5,4,1,4,1,0],[5,7,7,5,0,0],
		[1,0,1,0,1,0],[5,2,2,2,2,1],[5,0,0,0,0,5],[12,0,30,0,12,0]]
	for row:Array in rows:
		var fb:Dictionary={}
		var fc:Dictionary={}
		if row[3]>0:fb["x"]=row[3]
		if row[4]>0:fc["x"]=row[4]
		var r:=M.plan({"x":row[0]},{"x":row[1]},{"x":row[2]})
		var label:="split "+str(row)
		if row[5]==0:
			expect_ok(r,fb,fc,{"x":row[1]-row[3]},{"x":row[2]-row[4]},{"x":row[1]+row[4]},label)
		else:
			expect_short(r,{"x":row[5]},fb,fc,label)

func test_unrelated_and_zero_preserved()->void:
	var bag:={"apple":0,"wheat":4,"tool":1,"seed":12}
	var box:={"plank":0,"wheat":6,"ore":3}
	var r:=M.plan({"wheat":7,"seed":2},bag,box)
	expect_ok(r,{"wheat":4,"seed":2},{"wheat":3},
		{"apple":0,"wheat":0,"tool":1,"seed":10},{"plank":0,"wheat":3,"ore":3},
		{"apple":0,"wheat":7,"tool":1,"seed":12},"unrelated preserved")
	var q:=enqueue({"wheat":7,"seed":2},r.supplied_inventory)
	expect(q.get("ok")==true and same(q.inventory,r.backpack_after),"unrelated enqueue matches")

func test_alias_isolation()->void:
	var cost:={"wheat":3}
	var bag:={"wheat":1,"tool":1}
	var box:={"wheat":5}
	var r:=M.plan(cost,bag,box)
	var outs:=["from_backpack","from_chest","missing","backpack_after","chest_after","supplied_inventory"]
	var distinct:=true
	for i:int in outs.size():
		for src:Dictionary in [cost,bag,box]:
			if is_same(r[outs[i]],src):distinct=false
		for j:int in range(i+1,outs.size()):
			if is_same(r[outs[i]],r[outs[j]]):distinct=false
	expect(distinct,"outputs are distinct objects from inputs and each other")
	var out_before:=canon(r)
	cost["wheat"]=99;bag["wheat"]=0;bag["new"]=1;box.clear()
	expect(canon(r)==out_before,"mutating inputs does not change outputs")
	var cost2:={"wheat":3}
	var bag2:={"wheat":1,"tool":1}
	var box2:={"wheat":5}
	var r2:=M.plan(cost2,bag2,box2)
	var in_before:=var_to_str([cost2,bag2,box2])
	for k:String in outs:
		var out:Dictionary=r2[k]
		out["wheat"]=-7
	var after2:Dictionary=r2.backpack_after
	after2["tool"]=0
	expect(var_to_str([cost2,bag2,box2])==in_before,"mutating outputs does not change inputs")
	# Passing one store as both sources would double count; distinct equal stores are fine.
	var shared:={"wheat":2}
	expect_invalid(M.plan({"wheat":3},shared,shared),M.MSG_SAME_SOURCE,"same dict as bag and chest")
	expect_ok(M.plan({"wheat":3},{"wheat":2},{"wheat":2}),{"wheat":2},{"wheat":1},{"wheat":0},{"wheat":1},{"wheat":3},"equal but distinct stores")

func test_json_whole_floats()->void:
	var cost:Variant=JSON.parse_string("{\"radish\":2.0,\"wheat\":1}")
	var bag:Variant=JSON.parse_string("{\"radish\":1.0,\"wheat\":3,\"tool\":0}")
	var box:Variant=JSON.parse_string("{\"radish\":4.0,\"gem\":1000000000.0}")
	var r:=M.plan(cost,bag,box)
	expect_ok(r,{"radish":1,"wheat":1},{"radish":1},{"radish":0,"wheat":2,"tool":0},
		{"radish":3,"gem":CAP},{"radish":2,"wheat":3,"tool":0},"json floats")
	if r.get("ok")==true:
		var typed:=true
		for k:String in ["from_backpack","from_chest","backpack_after","chest_after","supplied_inventory"]:
			typed=typed and all_int(r[k])
		expect(typed,"json floats normalise to int everywhere")
		var q:=enqueue(cost,r.supplied_inventory)
		expect(q.get("ok")==true and same(q.inventory,r.backpack_after),"json enqueue matches")

func test_lexical_determinism()->void:
	var cost:={"zest":1,"apple":1,"melon":1}
	var bag:={"melon":1,"zest":1,"apple":1}
	var a:=M.plan(cost,bag,{})
	var b:=M.plan({"apple":1,"melon":1,"zest":1},{"apple":1,"melon":1,"zest":1},{})
	expect(a.get("ok")==true and (a.from_backpack as Dictionary).keys()==["apple","melon","zest"],"debits listed in lexical order")
	expect(var_to_str(a.from_backpack)==var_to_str(b.from_backpack),"debit text independent of cost order")
	expect(var_to_str(M.plan(cost,bag,{"zest":2}))==var_to_str(M.plan(cost,bag,{"zest":2})),"repeat calls identical")
	var s:=M.plan({"zest":3,"apple":3},{},{})
	expect(s.get("ok")==false and (s.missing as Dictionary).keys()==["apple","zest"],"missing listed in lexical order")

func test_invalid_inputs()->void:
	var bad_counts:Array=[NAN,INF,-INF,1.5,0.25,-1,-1.0,true,false,"2",null,CAP+1,float(CAP)+1.0,[1],{}]
	for v:Variant in bad_counts:
		expect_invalid(M.plan({"wheat":v},{"wheat":9}),M.MSG_COST,"cost value "+var_to_str(v))
		expect_invalid(M.plan({"wheat":1},{"wheat":v}),M.MSG_BACKPACK,"bag value "+var_to_str(v))
		expect_invalid(M.plan({"wheat":1},{"wheat":1},{"wheat":v}),M.MSG_CHEST,"chest value "+var_to_str(v))
	expect_invalid(M.plan({"wheat":0},{"wheat":9}),M.MSG_COST,"cost zero")
	expect_invalid(M.plan({"wheat":0.0},{"wheat":9}),M.MSG_COST,"cost zero float")
	expect_invalid(M.plan({"wheat":1,"salt":0},{"wheat":9}),M.MSG_COST,"cost one zero entry")
	var long_key:="k".repeat(65)
	var bad_keys:Array=["",long_key,7,1.0,&"wheat",null]
	for k:Variant in bad_keys:
		var d:={}
		d[k]=1
		expect_invalid(M.plan(d,{}),M.MSG_COST,"cost key "+var_to_str(k))
		expect_invalid(M.plan({"wheat":1},d),M.MSG_BACKPACK,"bag key "+var_to_str(k))
		expect_invalid(M.plan({"wheat":1},{"wheat":1},d),M.MSG_CHEST,"chest key "+var_to_str(k))
	var ok_key:="k".repeat(64)
	expect(M.plan({ok_key:1},{ok_key:1}).get("ok")==true,"64-char key accepted")
	for v:Variant in [null,[],"wheat",5,{}]:
		expect_invalid(M.plan(v,{"wheat":1}),M.MSG_COST,"cost container "+var_to_str(v))
	for v:Variant in [null,[],"wheat",5]:
		expect_invalid(M.plan({"wheat":1},v),M.MSG_BACKPACK,"bag container "+var_to_str(v))
		expect_invalid(M.plan({"wheat":1},{"wheat":1},v),M.MSG_CHEST,"chest container "+var_to_str(v))
	var wide:={}
	for i:int in 65:wide["item%02d"%i]=1
	expect_invalid(M.plan(wide,wide.duplicate()),M.MSG_COST,"65 cost entries")
	wide.erase("item64")
	expect(M.plan(wide,wide.duplicate()).get("ok")==true,"64 cost entries accepted")
	# A malformed field elsewhere never yields a partial success.
	var bag:={"wheat":5,"junk":1.5}
	var before:=var_to_str(bag)
	expect_invalid(M.plan({"wheat":1},bag,{"wheat":1}),M.MSG_BACKPACK,"unrelated bad bag entry")
	expect(var_to_str(bag)==before,"invalid input not mutated")

## Seeded property test: conservation, backpack priority, and the
## supplied_inventory -> CookingQueue.enqueue round trip.
func test_property(seed_value:int,rounds:int)->void:
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value
	var oks:=0
	for round_index:int in rounds:
		var cost:={}
		var bag:={}
		var box:={}
		var as_float:=rng.randi_range(0,3)==0
		for item:String in POOL:
			if rng.randi_range(0,9)<4:cost[item]=rng.randi_range(1,12)
			if rng.randi_range(0,2)>0:
				var held:int=rng.randi_range(0,10)
				bag[item]=held
				if as_float:bag[item]=float(held) # JSON-style whole float
			if rng.randi_range(0,2)>0:box[item]=rng.randi_range(0,10)
		if cost.is_empty():cost["wheat"]=rng.randi_range(1,12)
		bag["keepsake"]=rng.randi_range(0,3)
		box["lantern"]=rng.randi_range(0,3)
		var label:="seed %d round %d"%[seed_value,round_index]
		var before:=var_to_str([cost,bag,box])
		var expected_ok:=true
		for item:String in cost:
			if int(bag.get(item,0))+int(box.get(item,0))<int(cost[item]):expected_ok=false
		var r:=M.plan(cost,bag,box)
		expect(r.get("ok")==expected_ok and var_to_str([cost,bag,box])==before,label+" verdict/no mutation")
		if r.get("ok")!=expected_ok:continue
		var fb:Dictionary=r.from_backpack
		var fc:Dictionary=r.from_chest
		var priority:=true
		for item:String in cost:
			var want:int=cost[item]
			var held:int=int(bag.get(item,0))
			var take_b:int=int(fb.get(item,0))
			var take_c:int=int(fc.get(item,0))
			if take_b!=mini(want,held):priority=false
			if take_c>0 and take_b!=held:priority=false
			if take_b+take_c>want or take_c>int(box.get(item,0)):priority=false
		for item:Variant in fb:
			if not cost.has(item) or int(fb[item])<=0:priority=false
		for item:Variant in fc:
			if not cost.has(item) or int(fc[item])<=0:priority=false
		expect(priority,label+" backpack-first positive debits")
		if not expected_ok:
			var missing:={}
			for item:String in cost:
				var short:int=int(cost[item])-int(bag.get(item,0))-int(box.get(item,0))
				if short>0:missing[item]=short
			expect(key_list(r)==SHORT_KEYS and same(r.missing,missing),label+" missing "+canon(r.missing))
			continue
		oks+=1
		var bag_after:Dictionary=r.backpack_after
		var box_after:Dictionary=r.chest_after
		var conserved:=key_list(r)==OK_KEYS and (r.missing as Dictionary).is_empty()
		var keys:={}
		for d:Dictionary in [cost,bag,box]:
			for k:Variant in d:keys[k]=true
		for item:Variant in keys:
			var spent:int=int(cost.get(item,0))
			var total_before:int=int(bag.get(item,0))+int(box.get(item,0))
			var total_after:int=int(bag_after.get(item,0))+int(box_after.get(item,0))
			if total_before!=total_after+spent:conserved=false
			if int(fb.get(item,0))+int(fc.get(item,0))!=spent:conserved=false
			if bag.has(item) and not bag_after.has(item):conserved=false
			if box.has(item)!=box_after.has(item):conserved=false
			if bag_after.has(item) and not (bag.has(item) or cost.has(item)):conserved=false
		expect(conserved,label+" conservation and key preservation")
		var q:=enqueue(cost,r.supplied_inventory)
		var supplied_ok:=all_int(r.supplied_inventory) and all_int(bag_after) and all_int(box_after)
		for item:Variant in r.supplied_inventory:
			if int(r.supplied_inventory[item])>CAP:supplied_ok=false
		expect(supplied_ok and q.get("ok")==true and same(q.inventory,bag_after),label+" enqueue(supplied) == backpack_after "+str(q.get("message","")))
	expect(oks>0 and oks<rounds,"seed %d covers both outcomes (ok=%d/%d)"%[seed_value,oks,rounds])
