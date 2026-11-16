extends SceneTree

## Workbench recipe guidance: every World.CRAFT recipe has explicit, accurate
## use text that matches the real recipe, build catalog and device behaviour.

const World = preload("res://scripts/world.gd")
const AutomationUI = preload("res://scripts/automation_ui.gd")
const LifePanels = preload("res://scripts/life_ui_panels.gd")
const BuildFolio = preload("res://scripts/build_folio.gd")
const Village = preload("res://scripts/village.gd")
const BENCH := Vector2i(38, 34)
const SITE := Vector2i(42, 34)
const MAX_CHARS := 48
const FALSE_EQUIPMENT := ["放置設備", "裝備"]

var checks := 0
var failures := 0
var world

class Keys extends RefCounted:
	func binding_label(action: String) -> String:
		return "〔%s〕" % action

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func near(tile: Vector2i) -> void:
	world.state.players.tester.x = tile.x + 0.5
	world.state.players.tester.y = tile.y + 1.5

var requests := 0

## Every request id is unique so a world retry cache never masks a real result.
func act(tag: String, verb: String, cell: Vector2i, extra := "") -> Dictionary:
	requests += 1
	return world.act("tester", "%s-%d" % [tag, requests], verb, cell, extra)

func build_cost(kind: String) -> Dictionary:
	var cost: Dictionary = World.BUILD[kind].duplicate()
	cost.erase("name")
	return cost

func run() -> void:
	check_coverage()
	check_guide_against_data()
	check_crafts_and_uses()
	await check_layout()
	print("WORKBENCH_GUIDANCE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check_coverage() -> void:
	var guide_ids: Array = AutomationUI.GUIDE.keys()
	var craft_ids: Array = World.CRAFT.keys()
	guide_ids.sort()
	craft_ids.sort()
	expect(guide_ids == craft_ids, "guide covers exactly the craft recipes: %s vs %s" % [guide_ids, craft_ids])
	for id in World.CRAFT:
		var text: String = AutomationUI.recipe_use(id, Keys.new())
		expect(not text.is_empty() and text != AutomationUI.USE_FALLBACK, "%s has explicit guidance" % id)
		expect(text.length() <= MAX_CHARS, "%s guidance stays short (%d chars)" % [id, text.length()])
		expect(not text.contains("%s"), "%s guidance has no unfilled placeholders" % id)
	expect(AutomationUI.recipe_use("not_a_recipe") == AutomationUI.USE_FALLBACK, "unknown id gets neutral fallback")
	for word in FALSE_EQUIPMENT:
		expect(not AutomationUI.USE_FALLBACK.contains(word), "fallback never promises placement/equipment")

func check_guide_against_data() -> void:
	var consumers: Array = []
	for id in World.CRAFT:
		var guide: Dictionary = AutomationUI.GUIDE.get(id, {})
		var kind: String = guide.get("kind", "")
		var text: String = AutomationUI.recipe_use(id, Keys.new())
		expect(kind in ["place", "collection", "part", "key_tool", "tool", "salt_facility"], "%s has a known kind" % id)
		expect(AutomationUI.PORTABLE_TOOLS.has(id) == (kind == "tool"), "%s is portable equipment exactly when kind is tool" % id)
		if kind != "tool":
			for word in FALSE_EQUIPMENT:
				expect(not text.contains(word), "%s does not claim '%s'" % [id, word])
		if kind in ["place", "collection"]:
			var build: String = guide.get("build", "")
			expect(World.BUILD.has(build), "%s points at a real build item %s" % [id, build])
			var cost := build_cost(build)
			expect(cost.has(id), "%s is really consumed by build %s" % [id, build])
			var tab: String = guide.get("tab", "")
			var page: int = BuildFolio.category(build, LifePanels.FOUNDATIONS, LifePanels.FURNITURE)
			expect(BuildFolio.TABS[page] == tab, "%s build tab %s matches folio %s" % [id, tab, BuildFolio.TABS[page]])
			expect(text.contains("「%s」" % tab), "%s guidance names the build tab" % id)
			if kind == "place":
				expect(cost == {id: 1}, "%s kit places 1:1 as %s" % [id, build])
				expect(World.BUILD[build].name == World.CRAFT[id].name, "%s build name matches recipe" % id)
				expect(id in LifePanels.BUILD_MATERIALS, "%s count is shown in the build folio" % id)
			else:
				expect(text.contains(World.BUILD[build].name), "%s guidance names %s" % [id, World.BUILD[build].name])
				for item in cost:
					expect(text.contains(str(cost[item])), "%s guidance states %s cost %d" % [id, item, cost[item]])
		if kind == "part":
			expect(not text.contains("建造目錄"), "%s part is not sent to the build menu" % id)
			var build_uses: Array = World.BUILD.keys().filter(func(build): return build_cost(build).has(id))
			expect(build_uses == guide.get("used_in_build", []), "%s lists every structure that consumes the part: %s" % [id, build_uses])
			var feeds: Array = guide.get("feeds", []).duplicate()
			var actual: Array = World.CRAFT.keys().filter(func(other): return World.CRAFT[other].ingredients.has(id))
			feeds.sort()
			actual.sort()
			expect(feeds == actual, "%s feeds list matches recipes that consume it: %s" % [id, actual])
			consumers.append(id)
		if kind == "salt_facility":
			expect(id in World.SALT_PAN.KIT_IDS and text.contains("鹽田") and not text.contains("建造目錄"), "%s names its regional installation" % id)
		if kind == "tool":
			var keys: Array = guide.get("keys", [])
			expect(not keys.is_empty() and keys[0] == AutomationUI.PORTABLE_TOOLS[id][0], "%s equips via its own tool action" % id)
			for action in keys:
				expect(text.contains("〔%s〕" % action), "%s guidance shows live binding for %s" % [id, action])
			expect(text.contains(World.NAMES.charcoal), "%s guidance mentions charcoal use" % id)
			expect(not AutomationUI.recipe_use(id).contains("%s"), "%s guidance is safe without an app" % id)
	expect(not consumers.is_empty(), "at least one intermediate part recipe is classified")
	# Concrete numbers quoted in the text come from the device data.
	var plank: Dictionary = World.INDUSTRY.PROCESS.plank
	var charcoal: Dictionary = World.INDUSTRY.PROCESS.charcoal
	expect(AutomationUI.recipe_use("sawmill_kit").contains("木材 %d" % plank.ingredients.wood) and AutomationUI.recipe_use("sawmill_kit").contains("木板 %d" % plank.yield), "sawmill ratio matches")
	expect(AutomationUI.recipe_use("kiln_kit").contains("木材 %d" % charcoal.ingredients.wood) and AutomationUI.recipe_use("kiln_kit").contains("木炭 %d" % charcoal.yield), "kiln ratio matches")
	expect(AutomationUI.recipe_use("tank_kit").contains(str(World.INDUSTRY.TANK_CAPACITY)), "tank capacity matches")
	for item in World.FORESTRY.OUTPUT:
		expect(AutomationUI.recipe_use("forester_kit").contains(World.NAMES[item]), "forester output %s named" % item)
	for item in World.WATERWORKS.INPUTS:
		expect(AutomationUI.recipe_use("waterworks_kit").contains(World.NAMES[item]), "waterworks input %s named" % item)
	for kind in ["water_pump", "water_tank", "waterworks"]:
		expect(kind in World.INDUSTRY.NETWORK and AutomationUI.recipe_use("pipe_kit").contains(World.BUILD[kind].name), "pipe joins %s" % kind)
	expect(not Village.unlocked({"stories": {"bobo": 2}}, "ore_display") and Village.unlocked({"stories": {"bobo": 3}}, "ore_display")
		and AutomationUI.recipe_use("gold_sample").contains("波波三段"), "ore display unlock rule matches guidance")

func check_crafts_and_uses() -> void:
	world = World.new()
	world.add_player("tester", "島民")
	world.state.mine_depths.unlocked = 5
	# Labelled fixture: this suite tests recipe guidance, not earned unlocks.
	# Supply a schema-valid opened kitchen, like the existing mine progress fixture.
	world.state.picnic=true
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	for piece in [["37,33","stove"],["36,33","long_bench"],["36,34","long_bench"]]:
		world.state.objects[piece[0]]={"type":piece[1],"owner":"tester","items":{}}
	world.state.public_kitchen={"stove":"37,33","seats":["36,33","36,34"],"meals":{"soup":4,"bread":2,"salad":2},"opened":true}
	world.state.objects[World.key(BENCH)] = {"type": "bench", "owner": "tester", "items": {}}
	# Seed the two salt harvest milestones for this workbench recipe fixture.
	var salt_record := World.SALT_PAN.own_record(world.state, "tester")
	salt_record.merge({"letter": true, "intro": true, "raked": 2, "wheel_raked": 1}, true)
	world.state.salt_pan.players.tester = salt_record
	# Labelled fixture: chapter 40 diversion gate recipe unlocks with a completed Lanyang
	# revisit (earned path covered by test_lanyang_revisit).
	world.state.lanyang_revisit = {"gates": [3, 2], "day": 1, "checked": ["upstream", "middle", "tail"], "completed": true, "claimed": {}}
	world.state.players.tester.explored_regions={}
	for region in World.REGIONS.ALL.slice(1,9):world.state.players.tester.explored_regions[region]=true
	var inv: Dictionary = world.state.players.tester.inventory
	for id in World.CRAFT:
		near(BENCH)
		var recipe: Dictionary = World.CRAFT[id]
		for item in recipe.ingredients:
			inv[item] = int(recipe.ingredients[item])
		var before := int(inv.get(id, 0))
		var result: Dictionary = act(id, "craft", BENCH, id)
		expect(result.ok and int(inv.get(id, 0)) == before + int(recipe.yield), "%s crafts into the backpack: %s" % [id, result.get("message", "")])
	# Key tool: the pick really enables the action the guidance describes.
	var guide: Dictionary = AutomationUI.GUIDE.reinforced_pick
	near(World.COPPER_CELL)
	var ore := int(inv.get("copper_ore", 0))
	expect(act("pick", guide.action, World.COPPER_CELL).ok, "reinforced pick enables %s" % guide.action)
	var gained := int(inv.get("copper_ore", 0)) - ore
	expect(gained > 0 and AutomationUI.recipe_use("reinforced_pick").contains("每次 %d 個" % gained), "copper yield in guidance matches world (%d)" % gained)
	near(BENCH)
	for item in World.CRAFT.reinforced_pick.ingredients:
		inv[item] = int(World.CRAFT.reinforced_pick.ingredients[item])
	var second_pick := act("pick-again", "craft", BENCH, "reinforced_pick")
	expect(not second_pick.ok and str(second_pick.get("message", "")).contains("已有強化石鎬"), "second pick refused for ownership, not distance or missing materials")
	# Placeable kits at home really place their build item from the backpack.
	for id in ["sprinkler_kit", "pipe_kit", "tank_kit", "sawmill_kit", "kiln_kit", "forester_kit", "conveyor_kit"]:
		var build: String = AutomationUI.GUIDE[id].build
		inv[id] = 1
		near(SITE)
		var placed: Dictionary = act(id, "build", SITE, build)
		expect(placed.ok and world.state.objects.get(World.key(SITE), {}).get("type") == build and int(inv.get(id, 0)) == 0,
			"%s places as %s: %s" % [id, build, placed.get("message", "")])
		world.state.objects.erase(World.key(SITE))
	# Collection sample: locked until Bobo's third story, then builds the display.
	inv.gold_sample = 1
	inv.wood = int(World.BUILD.ore_display.wood)
	near(SITE)
	expect(not act("display-locked", "build", SITE, "ore_display").ok and int(inv.gold_sample) == 1, "ore display needs Bobo's stories first")
	var stories: Dictionary = world.state.players.tester.get("stories", {})
	stories.bobo = 3
	world.state.players.tester.stories = stories
	expect(act("display", "build", SITE, "ore_display").ok and int(inv.gold_sample) == 0 and world.state.objects.get(World.key(SITE), {}).get("type") == "ore_display",
		"gold sample is spent on the ore display")

func find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := find_button(child, caption)
		if found:
			return found
	return null

func check_layout() -> void:
	var app = load("res://main.tscn").instantiate()
	app.village_art_preview = true
	root.add_child(app)
	app.set_process(false)
	app.hud.show()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1024, 640)
	app.session.snapshot = world.state
	app.session.own_id = "tester"
	world.state.objects[World.key(BENCH)] = {"type": "bench", "owner": "tester", "items": {}}
	app.automation_ui.workbench(app, BENCH)
	for id in World.CRAFT:
		var entry := find_button(app.modal, World.CRAFT[id].name)
		expect(entry != null, "recipe button exists for %s" % id)
		if entry == null:
			continue
		entry.pressed.emit()
		for frame in 3:
			await process_frame
		var use: Label = app.modal.find_child("RecipeUse", true, false)
		expect(use != null and use.text == AutomationUI.recipe_use(id, app), "%s shows its guidance in the workbench" % id)
		if use:
			expect(use.get_line_count() <= 4, "%s guidance fits in four lines (%d)" % [id, use.get_line_count()])
		expect(root.get_visible_rect().encloses(app.modal.get_global_rect()), "%s workbench fits 1024x640" % id)
		expect(app.modal.find_child("CraftRecipe", true, false) != null, "craft button keeps its node name")
	app._close_modal()
	app.automation_ui.refresh(app)
	app.queue_free()
	await process_frame
