extends SceneTree
## T022: Exercise every current World.CRAFT recipe through the authoritative
## World.act path, including exact debit/output, item-cap edges and progression
## locks. Fixtures seed only the required player/world unlock state and materials.

const World = preload("res://scripts/world.gd")
const Salt = preload("res://scripts/salt_pan.gd")
const BENCH := Vector2i(48,24)
const OWNER := "recipe-matrix-owner"
const CAP := 1000000000

var checks := 0
var failures := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("RECIPE_MATRIX_FAIL " + label)

func ready_world(unlocked: bool) -> World:
	var w := World.new()
	w.add_player(OWNER,"配方驗證")
	var player: Dictionary = w.state.players[OWNER]
	player.x = float(BENCH.x) + 0.5
	player.y = float(BENCH.y) + 0.5
	w.state.objects[World.key(BENCH)] = {"type":"bench","owner":OWNER,"items":{}}
	if unlocked:
		w.state.mine_depths.unlocked = 5
		player.explored_regions = {"penghu":true,"yilan":true,"jinguashi":true,"mao_kong":true,
			"yingge":true,"beimen":true,"tianwei":true,"tainan":true}
		w.state.public_kitchen = {"stove":"50,24","seats":["49,24","51,24"],
			"meals":{"soup":4,"bread":2,"salad":2},"opened":true}
		var salt_record: Dictionary = Salt.own_record(w.state,OWNER)
		salt_record.raked = 1
		salt_record.wheel_raked = 1
		w.state.salt_pan.players[OWNER] = salt_record
		w.state.lanyang_life = {"repaired":true}
		w.state.history_memory = {"plaque":true}
		w.state.lanyang_revisit = {"completed":true}
	return w

func exact_inventory(ingredients: Dictionary, recipe_id: String, recipe: Dictionary) -> Dictionary:
	var expected: Dictionary = {}
	for item in ingredients:
		var left := int(ingredients[item]) - int(recipe.ingredients.get(item,0))
		expected[item] = left
	var output := int(ingredients.get(recipe_id,0)) + int(recipe.yield)
	if output > 0: expected[recipe_id] = output
	return expected

func run() -> void:
	var ids: Array = World.CRAFT.keys()
	ids.sort()
	expect(ids.size() == 23,"the matrix covers all 23 recipes in World.CRAFT")
	for recipe_id in ids:
		var recipe: Dictionary = World.CRAFT[recipe_id]
		var w := ready_world(true)
		var player: Dictionary = w.state.players[OWNER]
		var materials: Dictionary = recipe.ingredients.duplicate(true)
		player.inventory = materials.duplicate(true)
		player.crafting_points = 4
		var result: Dictionary = w.act(OWNER,"recipe-%s"%recipe_id,"craft",BENCH,recipe_id)
		expect(result.get("ok",false)==true,"%s crafts when unlocked: %s"%[recipe_id,str(result.get("message",""))])
		expect(player.inventory == exact_inventory(materials,recipe_id,recipe),"%s debits exact ingredients and grants exact yield"%recipe_id)
		expect(int(player.crafting_points)==5,"%s awards one crafting point exactly once"%recipe_id)
		if recipe_id=="reinforced_pick":
			player.inventory=materials.duplicate(true)
			var before: Dictionary=player.inventory.duplicate(true)
			var duplicate: Dictionary=w.act(OWNER,"unique-pick-%s"%recipe_id,"craft",BENCH,recipe_id)
			expect(duplicate.get("ok",false)==false and player.inventory==before and
				int(player.crafting_points)==5,"reinforced_pick is unique; repeat craft keeps materials and progress")
			continue
		# Full stack boundary: every output must fit exactly at CAP and reject the
		# next craft without taking any ingredients.
		var full := ready_world(true)
		var full_player: Dictionary = full.state.players[OWNER]
		var boundary: Dictionary = recipe.ingredients.duplicate(true)
		boundary[recipe_id] = CAP-int(recipe.yield)
		full_player.inventory = boundary.duplicate(true)
		var full_result: Dictionary = full.act(OWNER,"exact-cap-%s"%recipe_id,"craft",BENCH,recipe_id)
		expect(full_result.get("ok",false)==true and int(full_player.inventory.get(recipe_id,0))==CAP,
			"%s succeeds exactly at the one-billion output limit"%recipe_id)
		var overflow := ready_world(true)
		var overflow_player: Dictionary = overflow.state.players[OWNER]
		var over: Dictionary = recipe.ingredients.duplicate(true)
		over[recipe_id] = CAP-int(recipe.yield)+1
		overflow_player.inventory = over.duplicate(true)
		var before: Dictionary = overflow_player.inventory.duplicate(true)
		var overflow_result: Dictionary = overflow.act(OWNER,"over-cap-%s"%recipe_id,"craft",BENCH,recipe_id)
		expect(overflow_result.get("ok",false)==false and overflow_player.inventory==before and
			int(overflow_player.get("crafting_points",0))==0,"%s rejects overflow without debit, output or progress"%recipe_id)
	for recipe_id in ["supply_box_kit","mine_drill_kit","waterworks_kit","mill_kit",
		"salt_wheel_kit","salt_rake_kit","diversion_gate_kit","water_tower_kit"]:
		var recipe: Dictionary = World.CRAFT[recipe_id]
		var w := ready_world(false)
		var player: Dictionary = w.state.players[OWNER]
		player.inventory = recipe.ingredients.duplicate(true)
		var before: Dictionary = player.inventory.duplicate(true)
		var result: Dictionary = w.act(OWNER,"locked-%s"%recipe_id,"craft",BENCH,recipe_id)
		expect(result.get("ok",false)==false,"%s stays locked until its progression requirement"%recipe_id)
		expect(player.inventory==before and int(player.get("crafting_points",0))==0,
			"%s locked attempt changes no materials or crafting progress"%recipe_id)
	print("WORKBENCH_RECIPE_MATRIX recipes=%d checks=%d failures=%d"%[ids.size(),checks,failures])
	quit(0 if failures==0 else 1)

func _initialize() -> void:
	call_deferred("run")
