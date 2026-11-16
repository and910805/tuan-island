extends SceneTree
## Validates taiwan_memory_route_catalog.gd against live sites, items, regions,
## transit stations and repo docs, then plays both memory visits end to end using
## the real TeaCeramics.perform actions to earn each required item.
## In-memory only: World.save_path stays empty, so no save file is written.
const Catalog=preload("res://scripts/taiwan_memory_route_catalog.gd")
const World=preload("res://scripts/world.gd")
const Transit=preload("res://scripts/transit.gd")
const Regions=preload("res://scripts/regions.gd")
const TeaCeramics=preload("res://scripts/tea_ceramics.gd")

var checks:=0
var failures:=0
var sources:={}

func expect(value:bool,label:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func source_has(hook:Dictionary)->bool:
	var path:=str(hook.script)
	if not sources.has(path):
		sources[path]=FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	return not sources[path].is_empty() and sources[path].contains(str(hook.symbol))

func has_error(data:Dictionary,needle:String)->bool:
	for e in Catalog.validate_data(data):
		if str(e).contains(needle):return true
	return false

func patched_step(visit_id:String,index:int,field:String,value:Variant)->Dictionary:
	var data:=Catalog.catalog().duplicate(true)
	data.visits[visit_id].steps[index][field]=value
	return data

func act(record:Dictionary,player:Dictionary,action:String,p:Vector2i,extra:String,now:float)->void:
	var r:=TeaCeramics.perform(record,player,action,p,extra,now)
	expect(r.get("ok",false),"perform %s ok: %s"%[action,str(r)])

func _initialize()->void:
	# ---------------------------------------------------- structure
	var errors:=Catalog.validate()
	expect(errors.is_empty(),"catalog validates: %s"%str(errors))
	expect(Catalog.VISITS.size()==2,"two visits")

	# ---------------------------------------------------- live cross-checks
	for vid in Catalog.VISITS:
		var v:Dictionary=Catalog.VISITS[vid]
		expect(v.region in Regions.ALL,"%s region in Regions.ALL"%vid)
		expect(Transit.STATIONS.has(v.region),"%s region is a transit station"%vid)
		expect(source_has(v.route_hook),"%s route hook real"%vid)
		var cells:={}
		for step in v.steps:
			expect(TeaCeramics.SITES.has(step.action),"%s action %s exists"%[vid,step.action])
			expect(Catalog.site_region(step.action)==v.region,"%s step %s staged in its region"%[vid,step.id])
			expect(not Catalog.site_cells(step.action).is_empty(),"%s step %s has a real cell"%[vid,step.id])
			cells[str(Catalog.site_cells(step.action))]=true
			for item in step.requires_any:
				expect(World.NAMES.has(item),"%s step %s item %s is real"%[vid,step.id,item])
		expect(cells.size()==v.steps.size(),"%s steps move between distinct work sites"%vid)
		for f in v.facts:
			if f.has("evidence"):expect(source_has(f.evidence),"%s fact evidence %s contains %s"%[vid,f.evidence.script,f.evidence.symbol])
		for i in v.steps.size():
			expect(Catalog.display_text(vid,i).begins_with(Catalog.FICTION_LABEL),"%s step %d labelled fictional"%[vid,i])
		expect(Catalog.intro_text(vid).contains(Catalog.FICTION_NOTICE),"%s intro carries fiction notice"%vid)
	expect(Catalog.display_text("yingge_first_mend",9)=="","out-of-range step text empty")

	# ---------------------------------------------------- negative validation
	expect(has_error(patched_step("yingge_first_mend",0,"text","這是清代留下的窯。"),"unsourced claim"),"rejects forbidden history term")
	expect(has_error(patched_step("maokong_roast_wait",1,"text","1980年的茶叢。"),"year claim"),"rejects year claim")
	expect(has_error(patched_step("maokong_roast_wait",2,"action","tea_fire"),"not a maokong work site"),"rejects step at another region's site")
	var bad:=Catalog.catalog().duplicate(true)
	bad.visits.yingge_first_mend.place_label="鶯歌陶坊"
	expect(has_error(bad,"must say the site is fictional"),"rejects unlabelled place")
	bad=Catalog.catalog().duplicate(true)
	bad.visits.maokong_roast_wait.facts[3].used_in_text=true
	expect(has_error(bad,"only game_rule facts"),"rejects doc-only fact used in text")
	bad=Catalog.catalog().duplicate(true)
	bad.visits.maokong_roast_wait.facts=bad.visits.maokong_roast_wait.facts.filter(func(f):return f.status!="needs_external_source")
	expect(has_error(bad,"needing external sourcing"),"requires an external-sourcing flag")
	bad=Catalog.catalog().duplicate(true)
	bad.visits.yingge_first_mend.prerequisites=[{"kind":"tea_flag","key":"potter_story"}]
	expect(has_error(bad,"must require visiting"),"rejects visit without travel prerequisite")
	bad=Catalog.catalog().duplicate(true)
	for step in bad.visits.yingge_first_mend.steps:step.requires_any=[]
	expect(has_error(bad,"no step is linked"),"rejects visit with no item link")
	bad=Catalog.catalog().duplicate(true)
	bad.visits.erase("maokong_roast_wait")
	expect(has_error(bad,"no visit staged in maokong"),"rejects missing maokong visit")

	# ---------------------------------------------------- live play-through
	var world:=World.new()
	world.add_player("alpha","Alpha")
	world.add_player("beta","Beta")
	var s:Dictionary=world.state
	var alpha:Dictionary=s.players.alpha
	expect(Catalog.available_visits(s,"alpha").is_empty(),"fresh world: no visits")
	expect(Catalog.available_visits(s,"ghost").is_empty(),"unknown token: no visits")
	var record:Dictionary=TeaCeramics.FRESH.duplicate(true)
	s.tea_ceramics.players.alpha=record

	# Yingge: intro -> potter clay -> potter story; visit still locked until travel.
	act(record,alpha,"tea_intro",TeaCeramics.RECEIVER,"",0.0)
	act(record,alpha,"tea_potter",TeaCeramics.POTTER,"",0.0)
	act(record,alpha,"tea_potter_story",TeaCeramics.POTTER,"",0.0)
	var y:="yingge_first_mend"
	expect(not Catalog.visit_available(s,"alpha",y),"yingge memory waits for a real visit")
	alpha.travel_book.visited.yingge=true
	expect(Catalog.available_visits(s,"alpha")==[y],"yingge memory opens after visit + potter story")
	expect(Catalog.available_visits(s,"beta").is_empty(),"alpha progress does not leak to beta")
	var before:=var_to_bytes(s)
	var r:=Catalog.try_step(s,"alpha",y,"yingge",TeaCeramics.KILN,0)
	expect(not r.ok and r.progress==0,"wrong site does not advance")
	expect(var_to_bytes(s)==before,"try_step is read-only")
	r=Catalog.try_step(s,"alpha",y,"maokong",TeaCeramics.POTTER,0)
	expect(not r.ok,"same cell in another region does not advance")
	r=Catalog.try_step(s,"alpha",y,"yingge",TeaCeramics.POTTER,0)
	expect(r.ok and r.progress==1 and r.message.begins_with(Catalog.FICTION_LABEL),"potter desk step plays")
	r=Catalog.try_step(s,"alpha",y,"yingge",TeaCeramics.CLAY,1)
	expect(r.ok and r.progress==2,"clay step plays while holding workshop clay")
	act(record,alpha,"tea_fire",TeaCeramics.KILN,"",0.0)
	expect(int(alpha.inventory.get("clay",0))==0 and int(alpha.inventory.get("tea_jar",0))==0,"clay in kiln, no jar yet")
	r=Catalog.try_step(s,"alpha",y,"yingge",TeaCeramics.KILN,2)
	expect(not r.ok and r.progress==2,"kiln step needs a jar")
	act(record,alpha,"tea_fire_take",TeaCeramics.KILN,"",TeaCeramics.KILN_SECONDS)
	r=Catalog.try_step(s,"alpha",y,"yingge",TeaCeramics.KILN,2)
	expect(r.ok and r.progress==3 and r.complete,"kiln step completes yingge memory")
	r=Catalog.try_step(s,"alpha",y,"yingge",TeaCeramics.KILN,3)
	expect(not r.ok and r.complete,"finished memory is replay-only")
	expect(not Catalog.try_step(s,"alpha",y,"yingge",TeaCeramics.KILN,7).ok,"bad progress rejected")

	# Maokong: discuss -> pick -> roast/take.
	var m:="maokong_roast_wait"
	alpha.travel_book.visited.maokong=true
	expect(not Catalog.visit_available(s,"alpha",m),"maokong memory waits for tea discussion")
	act(record,alpha,"tea_discuss",TeaCeramics.TEA_NPC,"",0.0)
	expect(Catalog.visit_available(s,"alpha",m),"maokong memory opens after discussion")
	r=Catalog.try_step(s,"alpha",m,"maokong",TeaCeramics.TEA_NPC,0)
	expect(r.ok and r.progress==1,"host step plays")
	r=Catalog.try_step(s,"alpha",m,"maokong",TeaCeramics.TEA_NODES[1],1)
	expect(not r.ok,"bush step needs tea in hand")
	act(record,alpha,"tea_pick",TeaCeramics.TEA_NODES[1],"",0.0)
	r=Catalog.try_step(s,"alpha",m,"maokong",TeaCeramics.TEA_NODES[2],1)
	expect(r.ok and r.progress==2,"any real tea bush works")
	act(record,alpha,"tea_roast",TeaCeramics.ROASTER,"light",0.0)
	r=Catalog.try_step(s,"alpha",m,"maokong",TeaCeramics.ROASTER,2)
	expect(not r.ok,"roaster step waits for roasted tea")
	act(record,alpha,"tea_take",TeaCeramics.ROASTER,"",TeaCeramics.ROAST_SECONDS.light)
	expect(int(alpha.inventory.get("tea_light",0))==1,"real light roast earned")
	r=Catalog.try_step(s,"alpha",m,"maokong",TeaCeramics.ROASTER,2)
	expect(r.ok and r.complete,"roaster step completes maokong memory")
	expect(Catalog.available_visits(s,"beta").is_empty(),"beta still has no visits")
	expect(not Catalog.try_step(s,"beta",m,"maokong",TeaCeramics.TEA_NPC,0).ok,"beta cannot play alpha's memory")

	print("TAIWAN_MEMORY_ROUTE_CATALOG_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
