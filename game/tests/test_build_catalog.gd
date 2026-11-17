extends SceneTree

const World = preload("res://scripts/world.gd")
const TILE := Vector2i(38, 34)
const MATERIALS := ["acorn_ornament_kit","seashell","animal_collector_kit","woodwork_parts","iron_ingot","copper_ingot","clay","rope","flower_pot","cotton_cloth","wool_cloth","supply_box_kit", "wood", "stone", "fiber", "hardwood", "copper_ore", "sprinkler_kit","pipe_kit","tank_kit","pump_kit","sawmill_kit","kiln_kit","forester_kit","conveyor_kit","gold_sample","waterworks_kit","mine_drill_kit","mill_kit","plank","copper_joint","glass","ochre_earth","veg_basket_rack_kit","relay_crate_stack_kit","carp_banner_kit","float_garland_kit","lantern_post_kit","flower_arch_kit","trio_keepsake_kit","water_share_plaque_kit","diversion_gate_kit","mine_lantern_kit","tea_ware_kit","salt_basket_kit","water_tower_kit","keepsake_aru_kit","keepsake_milu_kit","keepsake_bobo_kit","keepsake_chacha_kit","keepsake_achao_kit","keepsake_mianmian_kit","keepsake_xinghe_kit","keepsake_lingpopo_kit","keepsake_xiaoli_kit","keepsake_luoluo_kit","keepsake_diandian_kit","keepsake_nuannuan_kit","keepsake_nuannuan_room_kit","keepsake_aru_bird_kit","keepsake_achao_oar_kit","keepsake_xinghe_sign_kit","keepsake_lingpopo_memorial_kit"]
# Expected placement layer and closed-state collision for each catalog entry.
const PLACEMENT := {
	"acorn_ornament": ["objects", false],
	"floor": ["ground", false], "path": ["ground", false], "spring_pebble_path": ["ground", false], "roof": ["roofs", false], "greenhouse_roof": ["roofs", false], "greenhouse_rack": ["objects", true], "master_flower_bed": ["objects", true], "fish_display": ["objects", true], "rope_rack": ["objects", true], "sketch_easel": ["objects", true], "guest_wardrobe": ["objects", true], "inn_lattice_wardrobe": ["objects", true], "inn_fabric_screen": ["objects", true], "wood_mailbox": ["objects", true], "basic_tea_set": ["objects", false], "supply_box": ["objects", true], "expedition_tent": ["objects", true], "author_sign": ["objects", true], "author_shelf": ["objects", true],
	"wall": ["objects", true], "window": ["objects", true], "door": ["objects", true],
	"chest": ["objects", true], "private_chest": ["objects", true], "bench": ["objects", true],
	"bed": ["objects", true], "inn_quilt_bed": ["objects", true], "inn_stone_footbath": ["objects", true], "table": ["objects", true], "stove": ["objects", true],
	"flower_pot": ["objects", true], "clay_kiln": ["objects", true], "dye_table": ["objects", true], "assembly_table": ["objects", true], "animal_collector": ["objects", true], "jam_pot": ["objects", true], "long_bench": ["objects", true], "planter": ["objects", true], "sofa": ["objects", true],
	"lamp": ["objects", false], "chair": ["objects", false], "sign": ["objects", false],
	"sprinkler": ["objects", true], "medium_sprinkler": ["objects", true], "large_sprinkler": ["objects", true],
	"water_pipe": ["objects", false], "water_tank": ["objects", true], "water_pump": ["objects", true],
	"sawmill": ["objects", true], "charcoal_kiln": ["objects", true],
	"forester": ["objects", true],
	"conveyor": ["objects", false],
	"ore_display": ["objects", true],
	"waterworks": ["objects", true],
	"mine_drill": ["objects", true],
	"mill": ["objects", true],
	"seed_maker": ["objects", true], "loom": ["objects", true], "glass_furnace": ["objects", true],
	"veg_basket_rack": ["objects", false], "relay_crate_stack": ["objects", false], "carp_banner": ["objects", false],
	"float_garland": ["objects", false], "lantern_post": ["objects", false], "flower_arch": ["objects", false], "trio_keepsake": ["objects", false],
	"water_share_plaque": ["objects", false], "diversion_gate": ["objects", false],
	"mine_lantern": ["objects", false],
	"tea_ware": ["objects", false],
	"salt_basket": ["objects", false],
	"keepsake_aru": ["objects", false], "keepsake_milu": ["objects", false], "keepsake_bobo": ["objects", false], "keepsake_chacha": ["objects", false],
	"keepsake_achao": ["objects", false], "keepsake_mianmian": ["objects", false], "keepsake_xinghe": ["objects", false], "keepsake_lingpopo": ["objects", false],
	"keepsake_xiaoli": ["objects", false], "keepsake_luoluo": ["objects", false], "keepsake_diandian": ["objects", false], "keepsake_nuannuan": ["objects", false], "keepsake_nuannuan_room": ["objects", false],
	"festival_memorial_bell": ["objects", false], "ceramic_eave_chime": ["objects", false], "shell_chime": ["objects", false], "warm_lamp_niche": ["objects", false], "towel_rack": ["objects", true], "inn_welcome_sign": ["objects", false], "inn_tea_table": ["objects", true], "inn_luggage_rack": ["objects", true], "keepsake_aru_bird": ["objects", false], "keepsake_achao_oar": ["objects", false], "keepsake_xinghe_sign": ["objects", false], "keepsake_lingpopo_memorial": ["objects", false],
	"master_bench": ["objects", true], "spring_stone_bench": ["objects", true],
	"small_smelter": ["objects", true],
	"water_tower": ["objects", true],
}

var checks := 0
var failures := 0
var sequence := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func act(world, action: String, kind: String = "", who: String = "builder") -> Dictionary:
	sequence += 1
	var tile:=Vector2i(53,24) if kind=="water_pump" or world.state.objects.has("53,24") else TILE
	if world.player_region(who)=="mine_4":tile=World.MINE_DRILL.NODE+Vector2i.DOWN
	return world.act(who, "catalog-%d" % sequence, action, tile, kind)

func verify_entry(kind: String) -> void:
	if not PLACEMENT.has(kind):
		expect(false, kind + " has no expected layer or collision")
		return
	var world = World.new()
	world.add_player("builder", "島民")
	var player: Dictionary = world.state.players.builder
	var tile:=Vector2i(53,24) if kind=="water_pump" else TILE
	if kind in World.WALL_FIXTURES.KINDS:
		world.state.objects[World.key(tile+Vector2i.UP)]={"type":"wall","owner":"builder","items":{}}
	if kind=="mine_drill":
		tile=World.MINE_DRILL.NODE+Vector2i.DOWN
		world.state.mine_depths.unlocked=5
		world.state.mine_depths.pumped=24
		player.region="mine_4"
		player.x=tile.x+0.5
		player.y=tile.y+1.5
		verify_mine_drill(world, tile)
		return
	if kind=="water_pump":
		player.x=tile.x+0.5
		player.y=tile.y+1.5
		world.state.removed[World.key(tile)]=true
	if kind=="waterworks":world.state.mine_depths.unlocked=4
	if kind in ["author_sign","author_shelf"]:
		player.crafting_points=184
		expect(not act(world,"build",kind).ok,"Author furniture requires crafting level ten")
		player.crafting_points=185
	if kind=="expedition_tent":
		player.explored_regions={}
		for region in World.REGIONS.ALL.slice(1,14):player.explored_regions[region]=true
		expect(not act(world,"build",kind).ok,"Tent needs fourteen discoveries")
		player.explored_regions[World.REGIONS.ALL[-1]]=true
	if kind=="supply_box":
		expect(not act(world,"build",kind).ok,"Supply box requires exploration six")
		player.explored_regions={}
		for region in World.REGIONS.ALL.slice(1,9):player.explored_regions[region]=true
	if kind=="basic_tea_set":
		expect(not act(world,"build",kind).ok,"Tea set is locked before the arrangement")
		player["bonds"]={"chacha":{"points":1,"talk_day":-1,"gift_day":-1}}
		player["bond_goals"]={"chacha":{"1":""}}
	if kind=="wood_mailbox":
		expect(not act(world,"build",kind).ok,"Mailbox is locked before the letter")
		player["bonds"]={"luoluo":{"points":1,"talk_day":-1,"gift_day":-1}}
		player["bond_goals"]={"luoluo":{"1":""}}
	if kind=="guest_wardrobe":
		expect(not act(world,"build",kind).ok,"Wardrobe is locked before the guest room")
		player["bonds"]={"nuannuan":{"points":14,"talk_day":-1,"gift_day":-1}}
		player["bond_goals"]={"nuannuan":{"3":""}}
	if kind==World.WELCOME_SIGN.KIND:
		expect(not act(world,"build",kind).ok,"Welcome sign is locked before the first inn event")
		player["bonds"]={"nuannuan":{"points":1,"talk_day":-1,"gift_day":-1}}
		player["bond_goals"]={"nuannuan":{"1":""}}
	if kind==World.INDUSTRY.FOOT_BATH:
		expect(not act(world,"build",kind).ok,"Footbath is locked before the crack repair")
		player["bonds"]={"nuannuan":{"points":6,"talk_day":-1,"gift_day":-1}}
		player["bond_goals"]={"nuannuan":{"2":""}}
	if kind=="sketch_easel":
		expect(not act(world,"build",kind).ok,"Easel is locked before the sketch quest")
		player["bonds"]={"diandian":{"points":1,"talk_day":-1,"gift_day":-1}}
		player["bond_goals"]={"diandian":{"1":""}}
	if kind=="master_bench":
		player.bonds={"aru":{"points":6,"talk_day":-1,"gift_day":-1}}
		player.bond_goals={"aru":{"2":""}}
	if kind=="festival_memorial_bell":
		expect(not act(world,"build",kind).ok,"Festival bell is locked before Lingpopo's event")
		player.bonds={"lingpopo":{"points":14,"talk_day":-1,"gift_day":-1}}
		player.bond_goals={"lingpopo":{"3":"soup"}}
	if kind=="rope_rack":
		expect(not act(world,"build",kind).ok,"A rack needs three ropes")
		player.inventory.fiber=3*World.ROPE_FIBER_COST
		for i in range(3):expect(act(world,"handcraft_rope").ok,"Handcraft the rope before placing its rack")
	if kind=="fish_display":
		player.fish_caught=154
		expect(not act(world,"build",kind).ok,"Display requires angling level ten")
		player.fish_caught=155
	if kind=="master_flower_bed":
		player.harvests=184
		expect(not act(world,"build",kind).ok,"Flower bed requires level ten")
		player.harvests=185
	if kind=="greenhouse_rack":
		expect(not act(world,"build",kind).ok,"flower rack requires Xinghe report")
		player.greenhouse_glass_crafted=true
		player.greenhouse_cross_season_crop="pumpkin"
		player.greenhouse_reported=true
	if kind=="large_sprinkler":
		player.harvests=109
		expect(not act(world,"build",kind).ok,"Large sprinkler requires level eight")
		player.harvests=110
	if kind=="medium_sprinkler":
		player.harvests=54
		expect(not act(world,"build",kind).ok,"Medium sprinkler requires level six")
		player.harvests=55
	if kind=="seed_maker":
		player.harvests=World.FARMING_LEVEL_THRESHOLDS[World.SEED_MAKER_LEVEL-1]-1
		expect(World.farming_level(player)==2,"Previous harvest history puts player just below level three")
		expect(not act(world,"build",kind).ok, "seed maker requires harvest progress")
		player.harvests+=1
		expect(World.farming_level(player)==3,"Farming level three unlocks the recipe")
	if kind=="glass_furnace":
		expect(not act(world,"build",kind).ok,"glass furnace requires the repaired Jinguashi hoist")
		# Labelled catalogue fixture (B6 open, Q07 hoist repaired); earned unlock is
		# tested in test_mine_hoist_quest / test_mine_deep_journey.
		world.state.mine_depths={"unlocked":6,"ready":{},"pumped":24,"hoist":true}
	if kind in ["jam_pot","animal_collector"]:world.state.picnic=true
	if kind=="dye_table":world.state.flower_nursery.garden.complete=true
	if kind=="assembly_table":player.workshop_upgraded=true
	if kind=="mill":
		# Labelled catalogue fixture; earned unlock is tested separately.
		world.state.picnic=true
		world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
		for part in [["37,33","stove"],["36,33","long_bench"],["36,34","long_bench"]]:
			world.state.objects[part[0]]={"type":part[1],"owner":"builder","items":{}}
		world.state.public_kitchen={"stove":"37,33","seats":["36,33","36,34"],"meals":{"soup":4,"bread":2,"salad":2},"opened":true}
	player.stories = {"aru": 4, "milu": 4, "bobo": 3}
	for material in MATERIALS:
		if kind!="rope_rack" or material!="rope":player.inventory[material] = 100
	var key: String = World.key(tile)
	var center := Vector2(tile) + Vector2(0.5, 0.5)
	expect(world.can_stand(center), kind + " starts on walkable ground")
	if kind == "greenhouse_roof":
		expect(not act(world,"build",kind).ok,"greenhouse requires farmland")
		expect(act(world,"hoe").ok,"greenhouse is built over tilled soil")
	if kind == "roof":
		expect(not act(world, "build", kind).ok, "roof requires a wood floor")
		world.add_player("neighbor", "鄰居")
		expect(act(world, "build", "floor", "neighbor").ok, "neighbor lays a wood floor")
		expect(not act(world, "build", kind).ok, "roof rejects another player's floor")
		expect(act(world, "remove", "", "neighbor").ok, "neighbor removes own floor")
		expect(act(world, "build", "floor").ok, "builder lays own wood floor")
	var before_inventory: Dictionary = player.inventory.duplicate(true)
	var before_layers := {}
	for layer in ["objects", "ground", "roofs"]:
		before_layers[layer] = world.state[layer].duplicate(true)
	var expected_layer: String = PLACEMENT[kind][0]
	var result := act(world, "build", kind)
	expect(result.ok, "%s placement (%s)" % [kind, result.message])
	if not result.ok:
		return
	for layer in before_layers:
		var expected: Dictionary = before_layers[layer].duplicate(true)
		if layer == expected_layer:
			expected[key] = {"type": kind, "owner": "builder", "items": {}}
			if kind=="small_smelter":
				for index in range(1,4):expected[World.key(tile+World.INDUSTRY.SMELTER_CELLS[index])]={"type":kind,"owner":"builder","items":{},"smelter_part":index}
			if kind=="master_bench":expected[World.key(tile+Vector2i.RIGHT)]={"type":kind,"owner":"builder","items":{},"bench_end":true}
			if kind in ["author_sign","author_shelf","expedition_tent"]:expected[key].author=player.name
			if kind == "door":
				expected[key].open = false
			if World.INDUSTRY.SPRINKLER_CAPACITIES.has(kind):
				expected[key].merge({"water":0,"enabled":false,"next_water":0.0,"last_water":-1.0})
			if World.INDUSTRY.SPRINKLER_CAPACITIES.has(kind):expected[key].sprinkler_daily=true
			if kind=="jam_pot":expected[key].ceramic_pot=true
			if kind=="seed_maker":expected[key].joinery_seed_maker=true
			if kind=="assembly_table":
				expected[key].assembly_part=0
				expected[World.key(tile+Vector2i.RIGHT)]={"type":kind,"owner":"builder","items":{},"assembly_part":1}
			if kind=="inn_fabric_screen":
				expected[key].screen_part=0
				expected[World.key(tile+Vector2i.RIGHT)]={"type":kind,"owner":"builder","items":{},"screen_part":1}
			if kind=="inn_luggage_rack":
				expected[key].luggage_part=0
				expected[World.key(tile+Vector2i.RIGHT)]={"type":kind,"owner":"builder","items":{},"luggage_part":1}
			if kind=="inn_stone_footbath":
				expected[key].bath_part=0
				var cells:=World.INDUSTRY.station_cells(kind)
				for part in range(1,cells.size()):
					expected[World.key(tile+cells[part])]={"type":kind,"owner":"builder","items":{},"bath_part":part}
			if kind=="inn_quilt_bed":
				expected[key].inn_bed_part=0
				expected[key].inn_bed_vertical=true
				expected[World.key(tile+Vector2i.DOWN)]={"type":kind,"owner":"builder","items":{},"inn_bed_part":1,"inn_bed_vertical":true}
			if kind=="spring_stone_bench":
				expected[World.key(tile+Vector2i.RIGHT)]={"type":kind,"owner":"builder","items":{},"bench_end":true}
			if kind=="dye_table":
				expected[key].dye_part=0
				expected[World.key(tile+Vector2i.RIGHT)]={"type":kind,"owner":"builder","items":{},"dye_part":1}
			if kind=="clay_kiln":
				expected[key].kiln_part=0
				for index in range(1,4):expected[World.key(tile+World.INDUSTRY.SQUARE_CELLS[index])]={"type":kind,"owner":"builder","items":{},"kiln_part":index}
			if kind=="glass_furnace":
				expected[key].iron_furnace=true
				expected[key].furnace_part=0
				for index in range(1,4):expected[World.key(tile+World.INDUSTRY.SQUARE_CELLS[index])]={"type":kind,"owner":"builder","items":{},"furnace_part":index}
			if kind=="loom":
				expected[key].joinery_loom=true
				expected[key].loom_part=0
				for index in range(1,4):expected[World.key(tile+World.INDUSTRY.SQUARE_CELLS[index])]={"type":kind,"owner":"builder","items":{},"loom_part":index}
			if kind == "water_tank":expected[key].water=0
			if kind == "water_pump":expected[key].enabled=false
			if kind == "diversion_gate":expected[key].mode="open"
			if kind == "water_tower":expected[key].merge({"water":0,"enabled":true})
			if kind == "waterworks":expected[key].merge(World.WATERWORKS.fresh())
			if kind == "forester":expected[key].merge(World.FORESTRY.fresh(0.0))
			if kind == "conveyor":expected[key].merge(World.LOGISTICS.fresh())
			if kind in World.LOGISTICS.PROCESSORS:expected[key].merge({("input_wheat" if kind=="mill" else "input_wood"):0,"auto_enabled":false})
		expect(world.state[layer] == expected, "%s contents of %s" % [kind, layer])
	var expected_inventory := before_inventory.duplicate(true)
	for material in MATERIALS:
		expected_inventory[material] -= World.BUILD[kind].get(material, 0)
	expect(player.inventory == expected_inventory, kind + " consumes exactly its catalog materials")
	var blocked: bool = PLACEMENT[kind][1]
	expect(world.blocked(tile) == blocked and world.can_stand(center) != blocked, kind + " collision matches placement rules")
	if kind == "door":
		expect(act(world, "door").ok, "door opens")
		expect(not world.blocked(TILE) and world.can_stand(center), "open door allows passage")
		expect(act(world, "door").ok, "door closes")
		expect(world.blocked(TILE) and not world.can_stand(center), "closed door blocks passage again")
	expect(act(world, "remove").ok, kind + " can be removed by its owner")
	expect(player.inventory == before_inventory, kind + " returns exactly its catalog materials")
	for layer in before_layers:
		expect(world.state[layer] == before_layers[layer], "%s removal restores %s" % [kind, layer])
	expect(world.can_stand(center), kind + " removal restores passage")

func verify_mine_drill(world: World, tile: Vector2i) -> void:
	var center := Vector2(tile) + Vector2(0.5, 0.5)
	var player: Dictionary = world.state.players.builder
	player.inventory.mine_drill_kit=1
	expect(world.region_snapshot("mine_4").objects.is_empty(), "drill starts on empty mine ground")
	expect(act(world,"build","mine_drill").ok and int(player.inventory.mine_drill_kit)==0, "drill consumes exactly its kit")
	var expected := {"type":"mine_drill","owner":"builder"}
	expected.merge(World.MINE_DRILL.fresh(0))
	expect(world.region_snapshot("mine_4").objects.get(World.key(tile),{})==expected, "drill uses correct layer and initial state")
	world.switch_region("mine_4")
	expect(world.blocked(tile) and not world.can_stand(center), "drill blocks its footprint")
	world.switch_region("home")
	expect(act(world,"remove").ok and int(player.inventory.mine_drill_kit)==1, "removing an empty disabled drill refunds the kit")
	expect(world.region_snapshot("mine_4").objects.is_empty(), "removing the drill clears its placement layer")
	world.switch_region("mine_4")
	expect(world.can_stand(center), "removing the drill restores passage")
	world.switch_region("home")

func _initialize() -> void:
	expect(PLACEMENT.size() == World.BUILD.size(), "all catalog entries covered")
	for kind in World.BUILD:
		verify_entry(kind)
	print("BUILD_CATALOG_TESTS entries=%d checks=%d failures=%d" % [World.BUILD.size(), checks, failures])
	quit(0 if failures == 0 else 1)
