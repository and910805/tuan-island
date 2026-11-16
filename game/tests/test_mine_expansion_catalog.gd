extends SceneTree
## Invariants for scripts/mine_expansion_catalog.gd (T067 depths B6–B15).
## Pure data checks; does not construct a World or touch saves.

const Catalog=preload("res://scripts/mine_expansion_catalog.gd")
const World=preload("res://scripts/world.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Layout=preload("res://scripts/mine_layout.gd")
const Survey=preload("res://scripts/mine_survey.gd")
const Freight=preload("res://scripts/mine_freight.gd")
const Warmer=preload("res://scripts/table_warmer.gd")
const MIN_EXPECTED_CHECKS:=150

var checks:=0
var failures:=0

func expect(condition:bool,detail:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(detail)

func _initialize() -> void:
	check_existing_mirror()
	check_zones()
	check_depths()
	check_commissions()
	check_exits()
	check_lift_station()
	check_resources()
	check_fiction_vs_history()
	check_no_combat(Catalog.DEPTHS,"DEPTHS")
	check_no_combat(Catalog.ZONES,"ZONES")
	check_no_combat(Catalog.HAZARDS,"HAZARDS")
	check_no_combat(Catalog.COMMISSIONS,"COMMISSIONS")
	check_helpers()
	expect(checks>=MIN_EXPECTED_CHECKS,"ran %d checks, expected at least %d"%[checks,MIN_EXPECTED_CHECKS])
	print("MINE_EXPANSION_CATALOG_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func check_existing_mirror() -> void:
	# T067 wired: mine_depths now ships all fifteen floors; B1–B5 stay the original five.
	expect(Mines.IDS.size()==Catalog.MAX_DEPTH,"mine_depths ships B1–B15")
	expect(Catalog.EXISTING.size()==Catalog.FIRST_NEW_DEPTH-1,"EXISTING mirrors the five original depths")
	expect(Mines.SHALLOW_DEPTH==Catalog.FIRST_NEW_DEPTH-1 and Mines.MAX_DEPTH==Catalog.MAX_DEPTH,"mine_depths depth bounds match catalog")
	for depth in range(1,Catalog.FIRST_NEW_DEPTH):
		expect(Mines.IDS[depth-1]==Catalog.region_id(depth),"B%d region id matches mine_depths"%depth)
		expect(Catalog.EXISTING[depth].ore==Mines.ORES[depth-1],"B%d ore mirror matches mine_depths.ORES"%depth)
	expect(Mines.COSTS.size()==Catalog.MAX_DEPTH-1,"mine_depths.COSTS opens B2–B15")
	var original_costs:=[{"wood":6},{"stone":8},{},{"plank":6,"copper_joint":2}]
	for i in range(4):expect(Mines.COSTS[i]==original_costs[i],"B%d commission cost unchanged"%(i+1))
	for depth in range(Catalog.FIRST_NEW_DEPTH-1,Catalog.MAX_DEPTH):
		expect(Mines.COSTS[depth-1]==Catalog.COMMISSIONS[depth].cost,"B%d commission cost comes from catalog"%depth)
	for depth in range(Catalog.FIRST_NEW_DEPTH,Catalog.MAX_DEPTH+1):
		expect(Mines.ORES[depth-1]==Catalog.DEPTHS[depth].ore and Mines.YIELDS[depth-1]==int(Catalog.DEPTHS[depth].yield),"B%d ore/yield wired from catalog"%depth)
	for depth in range(1,Catalog.FIRST_NEW_DEPTH):
		expect(Survey.entry(depth).get("title","")==Survey.ENTRIES[depth-1].title,"B%d survey page is the shipped page"%depth)

func check_zones() -> void:
	var covered:={}
	for zone_id in Catalog.ZONES:
		var zone:Dictionary=Catalog.ZONES[zone_id]
		expect(not str(zone.name).is_empty() and not str(zone.summary).is_empty(),"zone %s has name and summary"%zone_id)
		expect(zone.fiction=="gameplay_geology","zone %s is labelled fictional geology"%zone_id)
		var span:Array=zone.depths
		expect(span.size()==2 and int(span[0])<=int(span[1]),"zone %s span is [first,last]"%zone_id)
		for depth in range(int(span[0]),int(span[1])+1):
			expect(not covered.has(depth),"B%d belongs to exactly one zone"%depth)
			covered[depth]=zone_id
			expect(Catalog.zone_of(depth)==zone_id,"B%d zone_of agrees with zone span %s"%[depth,zone_id])
	for depth in range(1,Catalog.MAX_DEPTH+1):
		expect(covered.has(depth),"B%d is covered by a zone"%depth)

func check_depths() -> void:
	expect(Catalog.DEPTHS.size()==Catalog.MAX_DEPTH-Catalog.FIRST_NEW_DEPTH+1,"DEPTHS covers B6–B15 exactly")
	var titles:={}
	var survey_titles:={}
	for existing_depth in range(1,Catalog.FIRST_NEW_DEPTH):survey_titles[Survey.ENTRIES[existing_depth-1].title]=true
	for depth in range(Catalog.FIRST_NEW_DEPTH,Catalog.MAX_DEPTH+1):
		expect(Catalog.DEPTHS.has(depth),"B%d defined"%depth)
		if not Catalog.DEPTHS.has(depth):continue
		var d:Dictionary=Catalog.DEPTHS[depth]
		expect(Catalog.ZONES.has(d.zone),"B%d zone exists"%depth)
		expect(not titles.has(d.title),"B%d title unique"%depth)
		titles[d.title]=true
		expect(d.ore in Freight.ITEMS,"B%d primary ore %s is freightable"%[depth,d.ore])
		expect(d.ore in World.NAMES,"B%d primary ore is an existing item"%depth)
		expect(int(d.yield)>=1 and int(d.yield)<=8,"B%d yield in 1..8"%depth)
		expect(Catalog.HAZARDS.has(d.hazard),"B%d hazard defined"%depth)
		var template:=int(d.layout_template)
		expect(template>=1 and template<=Layout.SIDE_CAVES.size(),"B%d layout template indexes SIDE_CAVES"%depth)
		if template>=1 and template<=Layout.SIDE_CAVES.size():
			var point:Vector2i=Survey.POINTS[template]
			expect(Layout.land(point,template) and not Layout.BASE_RECT.has_point(point),"B%d survey point lies in reused side cave"%depth)
		var page:Dictionary=d.survey
		for key in ["title","text","hint","icon"]:
			expect(page.has(key) and not str(page[key]).is_empty(),"B%d survey has %s"%[depth,key])
		expect(page.icon in World.NAMES,"B%d survey icon %s is an existing item"%[depth,page.icon])
		expect(not survey_titles.has(page.title),"B%d survey title unique across B1–B15"%depth)
		survey_titles[page.title]=true
		expect(str(page.hint).contains("第"),"B%d survey hint names the floor"%depth)

func check_commissions() -> void:
	var expected:=range(Catalog.FIRST_NEW_DEPTH-1,Catalog.MAX_DEPTH)
	expect(Catalog.COMMISSIONS.size()==expected.size(),"commissions exist for B5..B14 only")
	expect(not Catalog.COMMISSIONS.has(Catalog.MAX_DEPTH),"deepest floor has no commission")
	for depth in expected:
		var c:Dictionary=Catalog.commission_from(depth)
		expect(not c.is_empty() and not str(c.get("title","")).is_empty(),"B%d commission titled"%depth)
		var cost:Dictionary=c.get("cost",{})
		expect(not cost.is_empty(),"B%d commission has a cost"%depth)
		for item in cost:
			expect(item in World.NAMES,"B%d commission item %s exists"%[depth,item])
			expect(not Catalog.PROPOSED_ITEMS.has(item),"B%d commission avoids proposed item %s"%[depth,item])
			expect(int(cost[item])>=1 and int(cost[item])<=40,"B%d commission qty for %s in 1..40"%[depth,item])

func check_exits() -> void:
	# Graph: existing chain (mine_ui "up" goes to depth-1, B1 up → surface) plus catalog exits.
	var up_graph:={}
	for depth in range(1,Catalog.FIRST_NEW_DEPTH):
		up_graph[Catalog.region_id(depth)]=[Catalog.SURFACE if depth==1 else Catalog.region_id(depth-1)]
	for depth in range(Catalog.FIRST_NEW_DEPTH,Catalog.MAX_DEPTH+1):
		var exits:Dictionary=Catalog.DEPTHS[depth].exits
		expect(exits.size()==3 and exits.has("up") and exits.has("down") and exits.has("lift"),"B%d exits are exactly up/down/lift"%depth)
		expect(exits.up==Catalog.region_id(depth-1),"B%d up returns to B%d"%[depth,depth-1])
		var down:String=exits.down
		if depth==Catalog.MAX_DEPTH:expect(down=="","B%d is the terminus"%depth)
		else:expect(down==Catalog.region_id(depth+1),"B%d down leads to B%d"%[depth,depth+1])
		expect(exits.lift==Catalog.SURFACE,"B%d lift returns straight to the surface"%depth)
		for target in exits.values():
			expect(target is String,"B%d exit targets are plain region ids"%depth)
		up_graph[Catalog.region_id(depth)]=[exits.up,exits.lift]
	# From every floor, ascending-only moves reach the surface; new floors in one hop.
	for region in up_graph:
		var seen:={region:0}
		var queue:=[region]
		while not queue.is_empty():
			var at:String=queue.pop_front()
			for nxt in up_graph.get(at,[]):
				if not seen.has(nxt):
					seen[nxt]=seen[at]+1
					queue.append(nxt)
		expect(seen.has(Catalog.SURFACE),"%s reaches the surface without descending"%region)
		if Catalog.depth_of(region)>=Catalog.FIRST_NEW_DEPTH:
			expect(int(seen.get(Catalog.SURFACE,99))==1,"%s is one lift ride from the surface"%region)
	# Down chain reaches every floor from the surface.
	var reach:=[Catalog.SURFACE,Catalog.region_id(1)]
	for depth in range(1,Catalog.MAX_DEPTH):
		var nxt:String=Catalog.region_id(depth+1) if depth<Catalog.FIRST_NEW_DEPTH else Catalog.DEPTHS[depth].exits.down
		reach.append(nxt)
	expect(reach.size()==Catalog.MAX_DEPTH+1 and reach[-1]==Catalog.region_id(Catalog.MAX_DEPTH),"descending chain visits every floor")
	# Lift landings.
	var landings:Array=Catalog.LIFT_LANDINGS
	expect(landings[0]==Catalog.FIRST_NEW_DEPTH and landings[-1]==Catalog.MAX_DEPTH,"lift landings start at B6 and end at B15")
	for i in range(1,landings.size()):expect(int(landings[i])>int(landings[i-1]),"lift landings ascend")
	expect(Catalog.lift_landing(5)==0 and Catalog.lift_landing(9)==6 and Catalog.lift_landing(15)==15,"lift_landing never exceeds unlocked depth")

func check_lift_station() -> void:
	var lift:Vector2i=Catalog.LIFT
	expect(Mines.LIFT==lift and Mines.LIFT_LANDINGS==Catalog.LIFT_LANDINGS,"mine_depths lift station and landings match catalog")
	expect(Layout.BASE_RECT.has_point(lift),"lift tile in the shared base cavern")
	var taken:=[Mines.ENTRY,Mines.UP,Mines.DOWN,Mines.REST,Mines.SERVICE,Vector2i(12,20),Freight.LOAD_CELL]+Mines.NODES
	expect(lift not in taken,"lift tile clear of stations, nodes and protected cell")
	expect(not Mines.POOL.has_point(lift),"lift tile outside the B3 pool")
	for template in range(1,Layout.SIDE_CAVES.size()+1):
		for span:Rect2i in Layout.side_caves(template):
			expect(not span.has_point(lift),"lift tile not inside side cave template %d"%template)

func check_resources() -> void:
	for depth in Catalog.DEPTHS:
		var d:Dictionary=Catalog.DEPTHS[depth]
		for item in d.finds:
			expect(item in World.NAMES,"B%d find %s is an existing item"%[depth,item])
			expect(not Catalog.PROPOSED_ITEMS.has(item),"B%d existing finds exclude proposed ids"%depth)
		for item in d.proposed:
			expect(Catalog.PROPOSED_ITEMS.has(item),"B%d proposed find %s is catalogued"%[depth,item])
	for item in Catalog.PROPOSED_ITEMS:
		var p:Dictionary=Catalog.PROPOSED_ITEMS[item]
		expect(not World.NAMES.has(item),"proposed %s not yet in World.NAMES (move to finds once integrated)"%item)
		expect(p.status=="proposed" and not str(p.intended_use).is_empty(),"proposed %s has status and intended use"%item)
	var primary_ores:={}
	for depth in Catalog.DEPTHS:primary_ores[Catalog.DEPTHS[depth].ore]=true
	var used:={}
	for use:Dictionary in Catalog.RESOURCE_USES:
		var item:String=use.item
		used[item]=true
		expect(item in World.NAMES,"resource use item %s exists"%item)
		match use.via:
			"craft":
				expect(World.CRAFT.has(use.product) and World.CRAFT[use.product].ingredients.has(item),"%s is an ingredient of craft %s"%[item,use.product])
			"recipe":
				expect(World.RECIPES.has(use.product) and World.RECIPES[use.product].ingredients.has(item),"%s is an ingredient of recipe %s"%[item,use.product])
			"freight":
				expect(item in Freight.ITEMS,"%s is accepted by mine freight"%item)
			"build":
				expect(World.BUILD.has(use.product) and World.BUILD[use.product].has(item) and item!="name","%s is a build cost of %s"%[item,use.product])
			"process":
				expect(World.INDUSTRY.PROCESS.has(use.product) and World.INDUSTRY.PROCESS[use.product].ingredients.has(item),"%s is an ingredient of processing %s"%[item,use.product])
			"table_warmer":
				expect(use.product==Warmer.INSTALL_ACTION and Warmer.INSTALL_COST.has(item) and int(Warmer.INSTALL_COST[item])>0 and Warmer.INSTALL_ACTION in Warmer.ACTIONS,"%s is a cost of the shared table warmer %s"%[item,use.product])
			_:
				expect(false,"unknown resource use channel %s"%use.via)
	for ore in primary_ores:expect(used.has(ore),"primary ore %s has at least one documented use"%ore)
	for depth in Catalog.DEPTHS:
		for item in Catalog.DEPTHS[depth].finds:expect(used.has(item),"B%d find %s has a documented use"%[depth,item])
	# T067 deep-mine quest sources: integrated, no longer proposed.
	expect(World.NAMES.get("ochre_earth")=="赭土" and World.NAMES.get("vein_quartz")=="脈石英","new minerals are named in World.NAMES")
	# T067 warm_stone 暖岩片 integrated too (B12/B13 finds, table_warmer.gd): nothing stays proposed.
	expect(Catalog.PROPOSED_ITEMS.is_empty() and World.NAMES.get("warm_stone")=="暖岩片","warm_stone integrated; no proposed items remain")
	var expected_finds:={6:["stone","ochre_earth"],7:["copper_ore","ochre_earth"],9:["crystal_sand","vein_quartz"],10:["crystal_sand","vein_quartz"],12:["stone","warm_stone"],13:["gold_ore","warm_stone"]}
	for depth in expected_finds:
		expect(Catalog.DEPTHS[depth].finds==expected_finds[depth] and Catalog.DEPTHS[depth].proposed.is_empty(),"B%d finds carry the new mineral"%depth)
		expect(Mines.finds(depth)==expected_finds[depth],"mine_depths.finds(B%d) reads the catalog"%depth)
	expect(Catalog.DEPTHS[11].finds==["crystal_sand"] and Catalog.DEPTHS[14].finds==["crystal_sand"],"B11/B14 finds unchanged")
	for depth in Catalog.DEPTHS:expect(Catalog.DEPTHS[depth].proposed.is_empty(),"B%d has no proposed finds left"%depth)

func check_fiction_vs_history() -> void:
	var texts:=[]
	for zone in Catalog.ZONES.values():texts.append_array([zone.name,zone.summary])
	for hazard in Catalog.HAZARDS.values():texts.append_array([hazard.name,hazard.note])
	for c in Catalog.COMMISSIONS.values():texts.append(c.title)
	for depth in Catalog.DEPTHS:
		var d:Dictionary=Catalog.DEPTHS[depth]
		texts.append(d.title)
		texts.append_array(d.survey.values())
		var key:String=d.history
		expect(key.is_empty() or Catalog.HISTORY_NOTES.has(key),"B%d history key resolves"%depth)
	var year:=RegEx.create_from_string("\\d{4}")
	for text in texts:
		var s:=str(text)
		expect(year.search(s)==null,"fictional text has no year: %s"%s)
		for term in Catalog.HISTORY_ONLY_TERMS:
			expect(not s.contains(term),"fictional text avoids history term %s: %s"%[term,s])
	for key in Catalog.HISTORY_NOTES:
		var note:Dictionary=Catalog.HISTORY_NOTES[key]
		expect(note.status in ["needs_source_check","verified"],"history %s has known status"%key)
		expect(note.display_ok==(note.status=="verified"),"history %s displayable only once verified"%key)
		expect(not str(note.text).is_empty() and not str(note.flag).is_empty(),"history %s has text and flag"%key)
		expect(str(note.text).contains("現實") or str(note.text).contains("遺址"),"history %s is framed as real-world"%key)

func check_no_combat(value,path:String) -> void:
	if value is Dictionary:
		for key in value:
			expect(str(key).to_lower() not in Catalog.COMBAT_KEYS,"%s has no combat key %s"%[path,key])
			check_no_combat(value[key],"%s.%s"%[path,key])
	elif value is Array:
		for i in value.size():check_no_combat(value[i],"%s[%d]"%[path,i])
	elif value is String:
		for word in ["戰鬥","攻擊","怪物","敵人","傷害"]:
			expect(not value.contains(word),"%s text has no combat wording %s"%[path,word])

func check_helpers() -> void:
	expect(Catalog.region_ids().size()==10 and Catalog.region_ids()[0]=="mine_6" and Catalog.region_ids()[-1]=="mine_15","region_ids lists mine_6..mine_15")
	expect(Catalog.depth_of("mine_12")==12 and Catalog.depth_of("mine_16")==0 and Catalog.depth_of("jinguashi")==0 and Catalog.depth_of("mine_x")==0,"depth_of parses and bounds")
	expect(Catalog.region_ids()==Mines.IDS.slice(Catalog.FIRST_NEW_DEPTH-1,Catalog.MAX_DEPTH),"catalog region ids equal Mines.IDS[5..14]")
	for depth in Catalog.DEPTHS:
		var m:=Catalog.energy_multiplier(depth)
		expect(m>=1.0 and m<=Catalog.MAX_ENERGY_MULTIPLIER,"B%d energy multiplier within [1,%.1f]"%[depth,Catalog.MAX_ENERGY_MULTIPLIER])
	expect(Catalog.energy_multiplier(Catalog.MAX_DEPTH)==1.0,"terminus hall is calm")
