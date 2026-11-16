extends SceneTree
## 第四章外圍配對委託（霧竹溪谷／暖泉高地）純規則測試。只用手寫的最小 state，
## 不讀寫存檔、不啟動 session。

const OC=preload("res://scripts/outlying_commissions.gd")
const WORLD=preload("res://scripts/world.gd")
const BAMBOO=preload("res://scripts/bamboo_grove.gd")
const SPRINGS=preload("res://scripts/warm_springs.gd")
const TRANSIT=preload("res://scripts/transit.gd")
const A="outlying-alpha-token"
const B="outlying-beta-token"
var checks:=0
var failures:=0

func expect(condition:bool,detail:String)->void:
	checks+=1
	if not condition:
		failures+=1
		push_error(detail)

func bytes(v:Variant)->PackedByteArray:
	return var_to_bytes(v)

func person(region:String,inv:Dictionary,coins:Variant=0)->Dictionary:
	return {"region":region,"coins":coins,"inventory":inv,"travel_book":{"visited":{OC.REGION_BAMBOO:true,OC.REGION_SPRINGS:true}}}

func base_state()->Dictionary:
	return {"dock_stage":0,"players":{
		A:person(OC.REGION_BAMBOO,{"mist_tea":2,"bamboo_ayu":1,"glass_shrimp":1,"stone":5},10),
		B:person(OC.REGION_SPRINGS,{"glass_shrimp":2,"stone":3},0)}}

func auth(token:String)->Dictionary:
	return {"apply":true,"auth":token}

func test_catalog()->void:
	expect(OC.REGION_BAMBOO==BAMBOO.REGION,"bamboo region const drift")
	expect(OC.REGION_SPRINGS==SPRINGS.REGION,"springs region const drift")
	expect(TRANSIT.boat_open({"dock_stage":OC.BOAT_DOCK_STAGE}) and not TRANSIT.boat_open({"dock_stage":OC.BOAT_DOCK_STAGE-1}),"boat threshold drift")
	expect(OC.ids()==["bamboo_tea_rest","springs_footbath"],"two commissions in order")
	var regions:={}
	for id:String in OC.ids():
		var def:Dictionary=OC.DEFS[id]
		regions[def.region]=true
		expect(int(def.reward_coins)>0 and int(def.reward_coins)<=200,"small reward "+id)
		expect((def.needs as Dictionary).size()>=1 and (def.needs as Dictionary).size()<=3,"small ask "+id)
		for item:String in def.needs:
			expect(WORLD.NAMES.has(item),"existing item id "+item)
			expect(OC.ITEM_NAMES.get(item)==WORLD.NAMES.get(item),"display name matches world "+item)
			expect(int(def.needs[item])>=1 and int(def.needs[item])<=5,"small quantity "+item)
		expect(str(def.fiction_note).contains("原創"),"fiction note "+id)
		for key in ["ask","hint","thanks","title","fact_note","fiction_note"]:
			var text:=str(def[key])
			for banned in ["史實","歷史上","年建","創立於","真實人物"]:
				expect(not text.contains(banned),"no historical claim %s.%s"%[id,key])
	expect(regions.has(OC.REGION_BAMBOO) and regions.has(OC.REGION_SPRINGS),"paired regions")
	# 原料在遊戲內可取得：魚在對應地區的釣點、茶在溪谷茶圃。
	expect(BAMBOO.POOLS.brook.fish=="bamboo_ayu","ayu caught at bamboo brook")
	expect(SPRINGS.POOLS.spring.fish=="glass_shrimp","glass shrimp at warm spring")
	expect(WORLD.RECIPES.has("mist_tea_brew") and WORLD.RECIPES.mist_tea_brew.ingredients.has("mist_tea"),"mist_tea is the raw leaf id")

func test_pure_source()->void:
	var src:=FileAccess.get_file_as_string("res://scripts/outlying_commissions.gd")
	expect(not src.is_empty(),"source readable")
	for banned in ["FileAccess","DirAccess","HTTPRequest","StreamPeer","WebSocket","OS.","preload(","load(","ResourceSaver","ProjectSettings","print("]:
		expect(not src.contains(banned),"no I/O or coupling: "+banned)

func test_readonly()->void:
	var s:=base_state()
	var before:=bytes(s)
	var st:=OC.status(s,A,"bamboo_tea_rest",{"arrival":{"region":OC.REGION_BAMBOO,"mode":"步道"}})
	expect(st.stage=="ready" and st.can_complete,"ready at grove")
	OC.status(s,B,"springs_footbath")
	OC.journal(s,A)
	OC.arrival_text(s,"bamboo_tea_rest",{"mode":OC.BOAT_MODE,"region":OC.REGION_BAMBOO})
	var dry:=OC.complete(s,A,"bamboo_tea_rest")
	expect(dry.ok and not dry.applied,"default complete is dry-run")
	expect(dry.coins==120 and dry.consume=={"mist_tea":2,"bamboo_ayu":1},"dry-run plan")
	var dry2:=OC.complete(s,A,"bamboo_tea_rest",{"apply":false,"auth":A})
	expect(dry2.ok and not dry2.applied,"apply false stays dry")
	expect(bytes(s)==before,"no mutation by default")
	expect(not s.has(OC.STATE_KEY),"no state key created by reads")

func test_gating()->void:
	var s:=base_state()
	expect(OC.status(s,A,"nope").stage=="unknown","unknown id")
	expect(not OC.complete(s,A,"nope",auth(A)).ok,"unknown id complete")
	expect(OC.status(s,"","bamboo_tea_rest").stage=="no_player","empty token")
	expect(OC.status(s,"x".repeat(OC.MAX_TOKEN_LENGTH+1),"bamboo_tea_rest").stage=="no_player","long token")
	expect(OC.status(s,123,"bamboo_tea_rest").stage=="no_player","non-string token")
	expect(OC.status(s,"ghost","bamboo_tea_rest").stage=="no_player","missing player")
	expect(OC.status(null,A,"bamboo_tea_rest").stage=="no_player","null state")
	expect(OC.status(s,A,"springs_footbath").stage=="elsewhere","A is at grove, not springs")
	s.players[A].travel_book.visited.erase(OC.REGION_BAMBOO)
	expect(OC.status(s,A,"bamboo_tea_rest").stage=="not_visited","must have arrived via transit")
	var before:=bytes(s)
	expect(not OC.complete(s,A,"bamboo_tea_rest",auth(A)).ok,"not visited rejects apply")
	expect(bytes(s)==before,"failed apply leaves state untouched")
	s.players[A].travel_book.visited[OC.REGION_BAMBOO]="true"
	expect(OC.status(s,A,"bamboo_tea_rest").stage=="not_visited","string true is not visited")

func test_auth_and_once()->void:
	var s:=base_state()
	var before:=bytes(s)
	expect(not OC.complete(s,A,"bamboo_tea_rest",{"apply":true}).ok,"apply without auth")
	expect(not OC.complete(s,A,"bamboo_tea_rest",auth(B)).ok,"apply with other token")
	expect(not OC.complete(s,A,"bamboo_tea_rest",{"apply":"true","auth":A}).applied,"string apply is not apply")
	expect(bytes(s)==before,"auth failures do not mutate")
	var r:=OC.complete(s,A,"bamboo_tea_rest",auth(A))
	expect(r.ok and r.applied,"authenticated completion")
	var inv:Dictionary=s.players[A].inventory
	expect(inv.mist_tea==0 and inv.bamboo_ayu==0,"materials consumed exactly")
	expect(inv.glass_shrimp==1 and inv.stone==5,"other materials untouched")
	expect(s.players[A].coins==130,"reward paid once")
	expect(OC.done(s,A,"bamboo_tea_rest"),"done recorded")
	expect(OC.status(s,A,"bamboo_tea_rest").stage=="done","status done")
	inv.mist_tea=9
	inv.bamboo_ayu=9
	var mid:=bytes(s)
	var again:=OC.complete(s,A,"bamboo_tea_rest",auth(A))
	expect(not again.ok and not again.applied,"one-time completion")
	expect(bytes(s)==mid,"repeat attempt does not mutate")
	expect(not OC.done(s,B,"bamboo_tea_rest"),"completion is per player")
	# B 在暖泉高地，獨立完成。
	var rb:=OC.complete(s,B,"springs_footbath",auth(B))
	expect(rb.ok and rb.applied,"B completes springs")
	expect(s.players[B].inventory.glass_shrimp==1 and s.players[B].inventory.stone==0 and s.players[B].coins==110,"B ledger")
	expect(OC.done(s,A,"bamboo_tea_rest") and not OC.done(s,A,"springs_footbath"),"A record kept")
	var j:=OC.journal(s,B)
	expect(j.size()==2 and j[1].done and not j[0].done,"journal per player")

func test_materials_and_limits()->void:
	var s:=base_state()
	s.players[A].inventory.bamboo_ayu=0
	var st:=OC.status(s,A,"bamboo_tea_rest")
	expect(st.stage=="gathering" and st.missing=={"bamboo_ayu":1},"missing listed")
	expect(st.text.contains("竹影香魚"),"missing shown by name")
	for bad in [-3,true,"5",1.5,NAN,INF,null,[2]]:
		var t:=base_state()
		t.players[A].inventory.mist_tea=bad
		expect(OC.status(t,A,"bamboo_tea_rest").stage=="gathering","bad count %s not usable"%str(bad))
		var b:=bytes(t)
		expect(not OC.complete(t,A,"bamboo_tea_rest",auth(A)).ok and bytes(t)==b,"bad count rejected atomically %s"%str(bad))
	# JSON 讀回的整數浮點可用。
	var f:=base_state()
	f.players[A].inventory.mist_tea=2.0
	f.players[A].inventory.bamboo_ayu=3.0
	f.players[A].coins=10.0
	var rf:=OC.complete(f,A,"bamboo_tea_rest",auth(A))
	expect(rf.applied and f.players[A].inventory.mist_tea==0 and f.players[A].inventory.bamboo_ayu==2 and f.players[A].coins==130,"integral floats accepted")
	# 鈴幣上限
	var c:=base_state()
	c.players[A].coins=OC.LIMIT-119
	var cb:=bytes(c)
	expect(not OC.complete(c,A,"bamboo_tea_rest",auth(A)).ok and bytes(c)==cb,"coin cap rejects atomically")
	c.players[A].coins=OC.LIMIT-120
	expect(OC.complete(c,A,"bamboo_tea_rest",auth(A)).applied and c.players[A].coins==OC.LIMIT,"exactly reaches cap")
	var bc:=base_state()
	bc.players[A].coins=-1
	expect(not OC.complete(bc,A,"bamboo_tea_rest",auth(A)).ok,"negative coins rejected")
	# 損壞的委託資料不覆寫
	var d:=base_state()
	d[OC.STATE_KEY]="broken"
	var db:=bytes(d)
	expect(not OC.complete(d,A,"bamboo_tea_rest",auth(A)).ok and bytes(d)==db,"corrupt store untouched")
	var e:=base_state()
	e[OC.STATE_KEY]={"players":{A:{"springs_footbath":{"done":true}}}}
	expect(OC.complete(e,A,"bamboo_tea_rest",auth(A)).applied,"existing record extended")
	expect(OC.done(e,A,"springs_footbath") and OC.done(e,A,"bamboo_tea_rest"),"prior completion preserved")

func test_arrival()->void:
	var s:=base_state()
	var boat:={"region":OC.REGION_BAMBOO,"mode":OC.BOAT_MODE}
	expect(OC.arrival_kind(s,"bamboo_tea_rest",null)=="unknown","no arrival input")
	expect(OC.arrival_kind(s,"bamboo_tea_rest",boat)=="unverified_boat","boat claimed before dock repaired")
	expect(not OC.arrival_text(s,"bamboo_tea_rest",boat).contains("小船"),"no boat text when unverified")
	s.dock_stage=2
	expect(OC.arrival_kind(s,"bamboo_tea_rest",boat)=="boat","real boat arrival")
	expect(OC.arrival_text(s,"bamboo_tea_rest",boat).contains("合作小船"),"boat text")
	expect(OC.arrival_kind(s,"springs_footbath",boat)=="unverified_boat","boat to other region not trusted")
	expect(OC.arrival_kind(s,"bamboo_tea_rest",{"region":OC.REGION_BAMBOO,"mode":"接駁"})=="land","land arrival")
	expect(OC.arrival_kind(s,"bamboo_tea_rest",{"region":OC.REGION_SPRINGS,"mode":"接駁"})=="unknown","region mismatch")
	expect(OC.arrival_kind(s,"bamboo_tea_rest",{"region":OC.REGION_BAMBOO,"mode":"x".repeat(OC.MAX_MODE_LENGTH+1)})=="unknown","overlong mode")
	expect(OC.arrival_text(s,"bamboo_tea_rest",{}).contains("霧竹溪谷") and not OC.arrival_text(s,"bamboo_tea_rest",{}).contains("小船"),"neutral text")
	var with_boat:=OC.status(s,A,"bamboo_tea_rest",{"arrival":boat})
	var without:=OC.status(s,A,"bamboo_tea_rest")
	expect(with_boat.text.contains("合作小船") and not without.text.contains("合作小船"),"status text reflects arrival")
	var r1:=OC.complete(s.duplicate(true),A,"bamboo_tea_rest",{"apply":true,"auth":A,"arrival":boat})
	var r2:=OC.complete(s.duplicate(true),A,"bamboo_tea_rest",auth(A))
	expect(r1.coins==r2.coins and r1.consume==r2.consume,"arrival does not change reward")

func _initialize()->void:
	test_catalog()
	test_pure_source()
	test_readonly()
	test_gating()
	test_auth_and_once()
	test_materials_and_limits()
	test_arrival()
	print("OUTLYING_COMMISSIONS_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks<100 else 0)
