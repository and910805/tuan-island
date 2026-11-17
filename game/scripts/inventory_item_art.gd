extends RefCounted

# Display-only atlas mapping. World.NAMES and stored inventory IDs are unchanged.
const IDS:=["wood","stone","fiber","radish","lettuce","wheat",
	"radish_seed","lettuce_seed","wheat_seed","carp","minnow","redfish",
	"loach","egg","feed","soup","bread","sapling",
	"carrot","potato","tomato","carrot_seed","potato_seed","tomato_seed",
	"salad","baked_potato","grilled_fish","carrot_soup","backpack","coins"]
const PATH:="res://assets/ui-inventory/items.png"
const Squirrel=preload("res://scripts/woodland_squirrel.gd")
const Duck=preload("res://scripts/river_duck.gd")
static var cache:Dictionary={}

static func icon(id:String) -> Texture2D:
	if id in [Squirrel.ACORN,Squirrel.KIT]:return Squirrel.texture(id)
	if id.begins_with("quality_"):return icon(id.trim_prefix("quality_"))
	if id==Duck.EGG:return Duck.texture(true)
	match id:
		"festival_memorial_bell":return preload("res://assets/ui-inventory/memorial-bell-copper.png")
		"iron_ore":return preload("res://assets/ui-inventory/iron-ore.png")
		"large_sprinkler":return preload("res://assets/automation/large-sprinkler-icon.png")
		"animal_collector_kit":return preload("res://assets/automation/animal-collector-kit.png")
		"field_sprinkler_kit":return preload("res://assets/automation/field-sprinkler-kit.png")
		"medium_sprinkler_kit":return preload("res://assets/automation/medium-sprinkler-kit.png")
		"large_sprinkler_kit":return preload("res://assets/automation/large-sprinkler-kit.png")
		"orange_dye":return preload("res://assets/bakery/orange-dye.png")
		"fired_brick":return preload("res://assets/bakery/fired-brick.png")
		"woodwork_parts":return preload("res://assets/automation/woodwork-parts.png")
		"iron_ingot":return preload("res://assets/ui-inventory/iron-ingot.png")
		"copper_ingot":return preload("res://assets/ui-inventory/copper-ingot.png")
		"hardwood":return preload("res://assets/ui-inventory/hardwood.png")
		"egg_basket":return preload("res://scripts/salt_revisit_art.gd").empty_basket_texture()
		"rope":return preload("res://assets/ui-inventory/rope.png")
		"flower_pot":return preload("res://assets/ui-inventory/flower-pot.png")
		"cotton_cloth":return preload("res://assets/ui-inventory/cotton-cloth.png")
		"wool_cloth":return preload("res://assets/ui-inventory/wool-cloth.png")
		"milk":return preload("res://assets/ui-inventory/fresh-milk.png")
		"wool":return preload("res://assets/ui-inventory/sheep-wool.png")
		"watermelon_platter":return preload("res://assets/ui-inventory/summer-watermelon-platter.png")
		"corn_chowder":return chowder_icon()
		"tea_pudding":return preload("res://assets/ui-inventory/tea-pudding.png")
		"seaweed":return preload("res://assets/ui-inventory/shore-seaweed.png")
		"seashell":return preload("res://assets/ui-inventory/wangan-shell.png")
		"star_rice_ball":return preload("res://assets/ui-inventory/star-rice-ball.png")
		"strawberry_toast":return preload("res://assets/ui-inventory/strawberry-toast.png")
		"mist_tea":return icon("tea_leaf")
		"mist_tea_seed":return icon("sapling")
		"mist_tea_brew":return icon("tea_light")
		"ginger_tea":return preload("res://assets/ui-inventory/ginger-tea.png")
		"watermelon":return icon("pumpkin")
		"watermelon_seed":return icon("pumpkin_seed")
		"ginger":return icon("potato")
		"ginger_seed":return icon("potato_seed")
		"cotton":return icon("bluebell")
		"cotton_seed":return icon("bluebell_seed")
		"seafood_rice":return preload("res://assets/ui-inventory/seafood-rice.png")
		"eggplant_rice":return icon("salad")
		"rice":return icon("wheat")
		"rice_seed":return icon("wheat_seed")
		"roasted_sweet_potato":return icon("baked_potato")
		"sweet_potato":return icon("potato")
		"sweet_potato_seed":return icon("potato_seed")
		"eggplant":return icon("tomato")
		"eggplant_seed":return icon("tomato_seed")
		"star_mushroom":return icon("potato")
		"star_mushroom_seed":return icon("potato_seed")
		"trout_hotpot":return preload("res://assets/ui-inventory/snow-trout-hotpot.png")
		"warm_stone":return warm_stone_icon()
		# 第 40 章：程式繪製的 32px 圖示（lanyang_revisit_art.gd；分水木牌與世界圖同一張，
		# 分流閘是餘水模式的閘框加兩端銅管接頭）。
		"water_share_plaque_kit","diversion_gate_kit":return preload("res://scripts/lanyang_revisit_art.gd").icon(id)
		# 第 40 章水塔：程式繪製的 32px 縮小水塔＋銅管接頭（water_tower_art.gd）。
		"water_tower_kit":return preload("res://scripts/water_tower_art.gd").icon(id)
		# 第 40 章礦燈（金瓜石回訪）：程式繪製的 32px 礦燈圖（jinguashi_revisit_art.gd；與世界圖同一張）。
		"mine_lantern_kit":return preload("res://scripts/jinguashi_revisit_art.gd").icon(id)
		# 第 40 章茶陶組（貓空與鶯歌回訪）：程式繪製的 32px 茶壺茶杯木托盤圖（tea_revisit_art.gd；與世界圖同一張）。
		"tea_ware_kit":return preload("res://scripts/tea_revisit_art.gd").icon(id)
		# 第 40 章鹽籃（臺南北門回訪）：程式繪製的 32px 竹編鹽籃圖（salt_revisit_art.gd；與世界圖同一張）。
		"salt_basket_kit":return preload("res://scripts/salt_revisit_art.gd").icon(id)
		"cabbage":return icon("lettuce")
		"cabbage_seed":return icon("lettuce_seed")
		"sugar_beet":return icon("radish")
		"sugar_beet_seed":return icon("radish_seed")
		"strawberry_jam":return preload("res://assets/ui-inventory/strawberry-jam.png")
		"cucumber_salad":return icon("salad")
		"strawberry":return icon("tomato")
		"cucumber":return icon("lettuce")
		"strawberry_seed":return icon("tomato_seed")
		"cucumber_seed":return icon("lettuce_seed")
		"cauliflower":return icon("lettuce")
		"sweet_corn":return icon("wheat")
		"cauliflower_seed":return icon("lettuce_seed")
		"sweet_corn_seed":return icon("wheat_seed")
	if id=="star_spot":return preload("res://assets/ui-inventory/star-spot.png")
	if id=="bamboo_ayu":return preload("res://assets/ui-inventory/bamboo-ayu.png")
	if id=="glass_shrimp":return preload("res://assets/ui-inventory/glass-shrimp.png")
	if id=="snow_trout":return preload("res://assets/ui-inventory/snow-trout.png")
	if id=="supply_box_kit":return preload("res://assets/bakery/supply-box.png")
	if id=="moon_squid":return preload("res://assets/bakery/moon-squid.png")
	if id=="gold_shrimp":return preload("res://assets/bakery/gold-shrimp.png")
	if id=="sardine":return preload("res://assets/bakery/sardine.png")
	if id=="flounder":return preload("res://assets/bakery/flounder.png")
	if id=="glass":return preload("res://assets/bakery/glass.png")
	if id=="crystal_sand":return preload("res://assets/bakery/crystal-sand.png")
	if id=="ochre_earth":return preload("res://assets/ui-inventory/ochre-earth.png")
	if id=="vein_quartz":return preload("res://assets/ui-inventory/vein-quartz.png")
	if id in ["tea_worn_jar","tea_spent_jar"]:
		if cache.has(id):return cache[id]
		var wear:=AtlasTexture.new()
		wear.atlas=load("res://assets/tea-ceramics/wear.png")
		wear.region=Rect2(0 if id=="tea_worn_jar" else 32,0,32,32)
		wear.filter_clip=true
		cache[id]=wear
		return wear
	var tea_ids:={"tea_leaf":0,"clay":1,"tea_jar":2,"tea_returned_jar":2,"tea_light":3,"tea_deep":4}
	if tea_ids.has(id):
		if cache.has(id):return cache[id]
		var tea:=AtlasTexture.new()
		tea.atlas=load("res://assets/tea-ceramics/items.png")
		tea.region=Rect2(int(tea_ids[id])*32,0,32,32)
		tea.filter_clip=true
		cache[id]=tea
		return tea
	if id in ["pumpkin","pumpkin_seed","flour","pumpkin_pie","mill_kit","mill"]:
		return preload("res://scripts/bakery_art.gd").icon(id)
	# Tianwei flower nursery items (9 IDs). Missing art returns null, no substitute.
	if preload("res://scripts/flower_art.gd").has_item(id):
		return preload("res://scripts/flower_art.gd").item_texture(id)
	# Beimen salt items (4 IDs). Missing art returns null, no substitute.
	if preload("res://scripts/salt_art.gd").has_item(id):
		return preload("res://scripts/salt_art.gd").item_texture(id)
	# T071 紀念票兌換品（七個 *_kit）：程式繪製的 32px 圖示（與世界圖同一張）。
	if preload("res://scripts/souvenir_art.gd").has_item(id):return preload("res://scripts/souvenir_art.gd").icon(id)
	# T066 居民紀念小物（十二個 keepsake_*_kit）：程式繪製的 32px 圖示（與世界圖同一張）。
	if preload("res://scripts/resident_keepsake_art.gd").has_item(id):return preload("res://scripts/resident_keepsake_art.gd").icon(id)
	if id=="mine_drill_kit":return preload("res://scripts/mine_drill_art.gd").icon(id)
	if id=="waterworks_kit":return preload("res://scripts/waterworks_art.gd").icon(id)
	if id=="gold_ore":return preload("res://scripts/mine_art.gd").ore_icon()
	if id=="gold_sample":return preload("res://scripts/mine_art.gd").refined_sample_icon()
	if id=="harvester":
		var path:="res://scripts/harvester_art.gd"
		if ResourceLoader.exists(path):return load(path).icon(id)
	if id=="seeder":
		var path:="res://scripts/seeder_art.gd"
		if ResourceLoader.exists(path):return load(path).icon(id)
	if id=="tiller":
		var path:="res://scripts/tiller_art.gd"
		if ResourceLoader.exists(path):return load(path).icon(id)
	if id=="conveyor_kit":
		var path:="res://scripts/logistics_art.gd"
		if ResourceLoader.exists(path):return load(path).icon(id)
	if id=="forester_kit":
		var path:="res://scripts/forestry_art.gd"
		if ResourceLoader.exists(path):return load(path).icon(id)
	if id in ["plank","resin","charcoal","pipe_kit","tank_kit","pump_kit","sawmill_kit","kiln_kit"]:
		var path:="res://scripts/industry_art.gd"
		if ResourceLoader.exists(path):return load(path).icon(id)
	if id in ["reinforced_pick","copper_ore","copper_joint","sprinkler_kit"]:
		var path:="res://scripts/automation_art.gd"
		if ResourceLoader.exists(path):return load(path).icon(id)
	if cache.has(id):return cache[id]
	var index:=IDS.find(id)
	if index<0 or not ResourceLoader.exists(PATH):return null
	var result:=AtlasTexture.new()
	result.atlas=load(PATH) as Texture2D
	result.region=Rect2((index%6)*32,(index/6)*32,32,32)
	result.filter_clip=true
	cache[id]=result
	return result

static func chowder_icon() -> Texture2D:
	return preload("res://assets/ui-inventory/corn-chowder.png")

## T067 暖岩片 warm_stone: program-drawn 32px slab (warm amber top face, burnt-orange
## front edge, dark-brown outline, pale-gold glowing specks and two heat wisps above).
## Hue ~30°, clearly brighter / more orange than stone (grey), ochre_earth (rust red),
## clay (brown) and charcoal (black).
static func warm_stone_icon() -> Texture2D:
	if cache.has("warm_stone"):return cache["warm_stone"]
	var image:=Image.create(32,32,false,Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,0))
	var top:=Color("eea045")
	var light:=Color("ffc766")
	var front:=Color("a84c22")
	var dark:=Color("6e3014")
	var edge:=Color("4a220e")
	var glow:=Color("fff0a8")
	var seam:=Color("ffb63f")
	var grain:=Color("c27a30")
	var wisp:=Color("ffb84d")
	wisp.a=0.9
	# A chipped rock slab: uneven top edge, top face to row 20, front face rows 21–25.
	var tops:=[3,2,1,1,0,0,0,1,1,0,0,0,0,0,1,0,0,0,1,1,0,1,2,3]
	for i in tops.size():
		var x:=4+i
		var first:=13+int(tops[i])
		var last:=25-(2 if i in [0,23] else (1 if i in [1,22] else 0))
		for y in range(first,last+1):
			var c:=top
			if y==first:c=light
			elif y>=21:c=dark if y==last else front
			image.set_pixel(x,y,c)
	# Glowing cracks across the front face; grain and two bright specks on top.
	for p:Vector2i in [Vector2i(9,21),Vector2i(10,22),Vector2i(10,23),Vector2i(11,24),Vector2i(19,21),Vector2i(18,22),Vector2i(19,23),Vector2i(20,24)]:
		image.set_pixel(p.x,p.y,seam)
	image.set_pixel(10,22,glow)
	image.set_pixel(19,23,glow)
	for p:Vector2i in [Vector2i(8,17),Vector2i(14,18),Vector2i(21,16),Vector2i(24,19),Vector2i(12,20),Vector2i(17,16)]:
		image.set_pixel(p.x,p.y,grain)
	# Outline: every transparent pixel touching the slab becomes edge.
	var body:=image.duplicate() as Image
	for y in range(11,28):
		for x in range(2,30):
			if body.get_pixel(x,y).a>0.0:continue
			for d:Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
				var q:=Vector2i(x,y)+d
				if body.get_pixel(q.x,q.y).a>0.0:
					image.set_pixel(x,y,edge)
					break
	for p:Vector2i in [Vector2i(11,17),Vector2i(22,18)]:image.set_pixel(p.x,p.y,glow)
	# Two short heat wisps rising from the slab.
	for p:Vector2i in [Vector2i(11,10),Vector2i(12,9),Vector2i(12,8),Vector2i(11,7),Vector2i(11,6),Vector2i(12,5),
			Vector2i(19,10),Vector2i(20,9),Vector2i(20,8),Vector2i(19,7),Vector2i(19,6),Vector2i(20,5),Vector2i(20,4)]:
		image.set_pixel(p.x,p.y,wisp)
	cache["warm_stone"]=ImageTexture.create_from_image(image)
	return cache["warm_stone"]
