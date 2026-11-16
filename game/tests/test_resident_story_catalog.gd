extends SceneTree
## T054/T066: validates resident_story_catalog.gd data against the live roster,
## item names, transit graph, history source, and real world-state progression.
## In-memory only: World.save_path stays empty, so no save file is written.
const Catalog=preload("res://scripts/resident_story_catalog.gd")
const World=preload("res://scripts/world.gd")
const Transit=preload("res://scripts/transit.gd")
const Regions=preload("res://scripts/regions.gd")
const Village=preload("res://scripts/village.gd")
const HistoryStory=preload("res://scripts/history_story.gd")
const TeaCeramics=preload("res://scripts/tea_ceramics.gd")
const FlowerNursery=preload("res://scripts/flower_nursery.gd")

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

## Deep copy of the catalog with fields of one beat replaced.
func patched(beat_id:String,changes:Dictionary)->Dictionary:
	var data:=Catalog.catalog().duplicate(true)
	for rid in data.residents:
		for entry in data.residents[rid].beats:
			if entry.id==beat_id:
				for field in changes:entry[field]=changes[field]
	return data

func without_visit(beat_id:String)->Array:
	var kept:=[]
	for p in Catalog.beat(beat_id).prerequisites:
		if p.kind!="visited":kept.append(p)
	return kept

func sorted(a:Array)->Array:
	var b:=a.duplicate()
	b.sort()
	return b

func _initialize()->void:
	# ---------------------------------------------------- structure
	var errors:=Catalog.validate()
	expect(errors.is_empty(),"catalog validates: %s"%str(errors))
	expect(Catalog.RESIDENTS.size()==6,"six residents")

	# ---------------------------------------------------- live cross-checks
	var all_beats:=[]
	for rid in Catalog.RESIDENTS:
		var r:Dictionary=Catalog.RESIDENTS[rid]
		expect(r.home_region in Regions.ALL,"%s home region exists"%rid)
		if r.id_status=="existing_npc":
			expect(Village.NPCS.has(r.existing_ids.npc) and Village.NPCS[r.existing_ids.npc].name==r.name,"%s reuses Village.NPCS id and name"%rid)
		for ref in r.existing_ids.refs:
			expect(source_has(ref),"%s ref %s contains %s"%[rid,ref.script,ref.symbol])
		for entry in r.beats:
			all_beats.append(entry.id)
			expect(entry.region in Regions.ALL,"%s region in Regions.ALL"%entry.id)
			expect(source_has(entry.hook),"%s hook %s contains %s"%[entry.id,entry.hook.script,entry.hook.symbol])
			for m in entry.materials:
				expect(World.NAMES.has(m.item),"%s material %s is a real item"%[entry.id,m.item])
				expect(source_has(m),"%s material source %s contains %s"%[entry.id,m.script,m.symbol])
	expect(all_beats.size()==18,"18 beats")
	# Prerequisite keys exist in the owning records.
	for key in Catalog.PREREQ_KINDS.tea_flag.allowed:
		expect(TeaCeramics.FRESH.has(key) and TeaCeramics.FRESH[key] is bool,"tea flag %s is a bool field"%key)
	for key in Catalog.PREREQ_KINDS.chapter_one_flag.allowed:
		expect(World.CHAPTER_ONE.fresh().has(key),"chapter_one has %s"%key)
	for region in Catalog.KNOWN_REGIONS:
		expect(region in Regions.ALL,"known region %s exists"%region)
	# Routes walk real transit edges (home->lanyang is the home region exit).
	for region in Catalog.ROUTES:
		var route:Dictionary=Catalog.ROUTES[region]
		expect(source_has(route.gate_hook),"route %s gate hook real"%region)
		var path:Array=route.path
		for i in range(1,path.size()):
			var a:String=path[i-1]
			var b:String=path[i]
			var linked:bool=(a=="home" and b=="lanyang") or Transit.CONNECTIONS.get(a,[]).has(b)
			expect(linked,"route %s edge %s->%s exists"%[region,a,b])
	expect(not Catalog.ROUTES.tianwei.path.has("taipei"),"no Taipei detour southbound")
	expect(Catalog.ROUTES.tianwei.path.slice(-2)==["yingge","tianwei"],"tianwei reached from yingge")
	# The only cited history matches the in-game source page verbatim.
	var cited:Dictionary=Catalog.HISTORY.lanyang_wanchangchun_1813
	expect(cited.url==HistoryStory.SOURCE_URL,"cited url equals in-game SOURCE_URL")
	for fact in cited.usable_facts:
		expect(HistoryStory.FACTS.contains(fact),"usable fact appears in history_story FACTS: %s"%fact)
	var cited_count:=0
	for hid in Catalog.HISTORY:
		if Catalog.HISTORY[hid].status=="in_game_cited":cited_count+=1
	expect(cited_count==1,"exactly one in-game cited history source")

	# ---------------------------------------------------- negative validation
	var odd_prereqs:Array=Catalog.beat("chacha_c2_how_far").prerequisites.duplicate(true)
	odd_prereqs.append({"kind":"moon_phase"})
	expect(has_error(patched("chacha_c2_how_far",{"prerequisites":odd_prereqs}),"unknown prerequisite kind"),"rejects unknown prereq kind")
	expect(has_error(patched("chacha_c2_how_far",{"line_status":"sourced_paraphrase","paraphrase_of":[0]}),"in-game cited source"),"rejects sourced line on unverified history")
	expect(has_error(patched("alei_c3_six_packets",{"flag":""}),"must be flagged"),"rejects unflagged unverified history")
	expect(has_error(patched("alei_c3_garden",{"absence":{"rule":"shared_once_personal_replay"}}),"catch_up_line required"),"rejects missing catch-up line")
	expect(has_error(patched("alei_c3_garden",{"absence":{"rule":"personal_progress"}}),"shared prerequisite"),"rejects shared beat without shared rule")
	expect(has_error(patched("chacha_c2_how_far",{"prerequisites":without_visit("chacha_c2_how_far")}),"must require visiting"),"rejects remote beat without visit")
	expect(has_error(patched("xinghe_c1_wanchangchun",{"paraphrase_of":[9]}),"out of range"),"rejects bad paraphrase index")
	expect(has_error(patched("xiaoli_c1_ledger",{"prerequisites":[{"kind":"world_flag","key":"secret"}]}),"unsupported key"),"rejects unsupported flag key")
	var bad_history:=Catalog.catalog().duplicate(true)
	bad_history.history.maokong_tea.usable_facts=["貓空是……"]
	expect(has_error(bad_history,"only in-game cited"),"rejects facts on uncited source")
	var five:=Catalog.catalog().duplicate(true)
	five.residents.erase("alei")
	expect(has_error(five,"expected 6 residents"),"rejects five residents")

	# ---------------------------------------------------- live progression
	var world:=World.new()
	world.add_player("alpha","Alpha")
	world.add_player("beta","Beta")
	var s:Dictionary=world.state
	var alpha:Dictionary=s.players.alpha
	var before:=var_to_bytes(s)
	expect(Catalog.available_beats(s,"alpha").is_empty(),"fresh world: no beats")
	expect(var_to_bytes(s)==before,"evaluation is read-only")
	expect(Catalog.available_beats(s,"ghost").is_empty(),"unknown token sees nothing")

	s.chapter_one.shipped=true
	expect(Catalog.available_beats(s,"alpha")==["xiaoli_c1_ledger"],"shipped opens xiaoli ledger")
	s.board=true
	s.lanyang_life.repaired=true
	var shared_ch1:=["aru_c1_board_frame","xiaoli_c1_ledger","xinghe_c1_channel"]
	expect(sorted(Catalog.available_beats(s,"beta"))==shared_ch1,"shared ch1 beats reach beta")
	s.history_memory.players.alpha={"seen":["33,22","33,25","33,32"],"round":3,"gates":[0,0],"completed":true}
	expect(sorted(Catalog.available_beats(s,"alpha"))==sorted(shared_ch1+["aru_c1_divider_board","xinghe_c1_wanchangchun"]),"history memory opens personal ch1 beats")
	expect(sorted(Catalog.available_beats(s,"beta"))==shared_ch1,"alpha's memory does not leak to beta")

	s.chapter_one.watered=true
	s.picnic=true
	expect(World.CHAPTER_ONE.phase(s)=="complete","chapter one complete")
	var tea:Dictionary=TeaCeramics.FRESH.duplicate(true)
	s.tea_ceramics.players.alpha=tea
	tea.potter=true
	expect(not Catalog.available_beats(s,"alpha").has("potter_c2_workshop_clay"),"potter beat waits for a real visit")
	alpha.travel_book.visited.yingge=true
	expect(Catalog.available_beats(s,"alpha").has("potter_c2_workshop_clay"),"visit + potter opens clay beat")
	tea.potter_story=true
	alpha.travel_book.visited.maokong=true
	tea.tea_discussed=true
	tea.reused=true
	var got:=Catalog.available_beats(s,"alpha")
	for id in ["aru_c2_mending","potter_c2_chipped_rim","chacha_c2_how_far","xiaoli_c2_return_column"]:
		expect(got.has(id),"ch2 beat %s open"%id)
	expect(not got.has("chacha_c2_both_columns"),"comparison beat waits")
	tea.comparison_complete=true
	expect(Catalog.available_beats(s,"alpha").has("chacha_c2_both_columns"),"comparison opens chacha beat")
	expect(FlowerNursery.phase(s,"alpha")=="letter","flower chapter unlocked to letter")

	var flower:Dictionary=FlowerNursery.FRESH.duplicate(true)
	s.flower_nursery.players.alpha=flower
	flower.letter=true
	expect(Catalog.available_beats(s,"alpha").has("potter_c3_southbound"),"letter opens southbound potter beat")
	alpha.travel_book.visited.tianwei=true
	flower.intro=true
	expect(Catalog.available_beats(s,"alpha").has("alei_c3_six_packets"),"intro opens alei beat")
	for kind in FlowerNursery.FLOWERS:
		flower.planted[kind]=true
		flower.harvested[kind]=1
		flower.saved[kind]=1
	expect(FlowerNursery.phase(s,"alpha")=="ship","flower phase ship")
	expect(Catalog.available_beats(s,"alpha").has("alei_c3_keep_one"),"saving opens keep-one beat")
	flower.shipped=true
	s.flower_nursery.garden.complete=true
	expect(Catalog.available_beats(s,"alpha").has("alei_c3_garden"),"garden opens alei garden beat")
	expect(not Catalog.available_beats(s,"beta").has("alei_c3_garden"),"beta must visit tianwei personally")
	flower.complete=true
	var final:=Catalog.available_beats(s,"alpha")
	expect(final.size()==18,"alpha reaches all 18 beats, got %d"%final.size())
	expect(sorted(Catalog.available_beats(s,"beta"))==shared_ch1,"beta still only has shared ch1 beats")
	expect(Catalog.latest_beat(s,"alpha","xiaoli")=="xiaoli_c3_seed_shelf","latest beat follows stale-beat policy")
	expect(Catalog.latest_beat(s,"beta","alei")=="","no alei beat for beta")

	# ---------------------------------------------------- catch-up lines
	var garden:=Catalog.beat("alei_c3_garden")
	expect(garden.resident=="alei","beat lookup carries resident")
	expect(Catalog.line_for(garden,false)==garden.absence.catch_up_line,"absent player hears catch-up line")
	expect(Catalog.line_for(garden,true)==garden.line,"participant hears main line")
	var personal:=Catalog.beat("chacha_c2_how_far")
	expect(Catalog.line_for(personal,false)==personal.line,"personal beats have no catch-up variant")
	expect(Catalog.CATCH_UP_POLICY.missable==false and Catalog.CATCH_UP_POLICY.realtime_deadline==false,"no missable beats or deadlines")

	print("RESIDENT_STORY_CATALOG_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
