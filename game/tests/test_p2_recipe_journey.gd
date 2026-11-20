extends "res://tests/test_bakery_journey.gd"

const SkillBook=preload("res://scripts/island_skill_book.gd")
const SLICE_RECIPES := [
	"soup", "bread", "feed", "salad", "baked_potato", "grilled_fish", "carrot_soup",
	"plank", "charcoal", "flour", "copper_joint", "woodwork_parts",
]

func after_chapter() -> void:
	super.after_chapter()
	if not failed:
		finish_slice_meals()
	if not failed:
		finish_slice_processing()
	if not failed:
		verify_earned_skills()
	var completed := earned.duplicate()
	completed.merge(bk_made)
	for recipe_id in SLICE_RECIPES:
		var produced := int(completed.get(recipe_id, 0))
		expect(produced > 0, "P2 recipe yielded real output: " + recipe_id)
		print("P2_RECIPE %s produced=%d" % [recipe_id, produced])
	print("P2_RECIPE_JOURNEY_TESTS checks=%d failures=%d" % [checks, failures])

func verify_earned_skills() -> void:
	# Put the spare copper and resin to use as expansion pipes for the starter field.
	bk_craft("pipe_kit", held("pipe_kit") + 4)
	if failed:return
	var levels:=SkillBook.core_levels(person())
	expect(levels.x>=3 and levels.y>=3 and levels.z>=3,"A fresh resident earned all three first unlocks: %s"%str(levels))
	var reloaded:=World.new()
	expect(reloaded.load_world(world.save_path) and not reloaded.recovered_from_backup,"Read the progression from its primary save")
	if failed:return
	var resident:Dictionary=reloaded.state.players[TOKEN]
	expect(SkillBook.core_levels(resident)==levels,"Naturally earned personal levels survived saving")
	expect(resident.get("crafted_reinforced_pick",false) and held("reinforced_pick")==1 and int(resident.inventory.get("reinforced_pick",0))==1,"The earned reinforced pick and its recipe history survived too")
	print("P2_EARNED_SKILLS farming=%d gathering=%d crafting=%d"%[levels.x,levels.y,levels.z])

func finish_slice_meals() -> void:
	for meal in ["baked_potato", "carrot_soup", "grilled_fish"]:
		if failed:
			return
		for item in World.RECIPES[meal].ingredients:
			var required := int(World.RECIPES[meal].ingredients[item])
			if held(item) >= required:
				continue
			if item == "carp":
				catch_river_carp()
				continue
			var crop: Dictionary = World.CROPS[item]
			var plots := ceili(float(required - held(item)) / float(crop["yield"]))
			bk_ensure_coins(int(crop.seed_price) * maxi(0, plots - held(item + "_seed")))
			bk_buy(item, plots)
			bk_harvest(bk_sow(item, plots), "P2 ingredient")
		if not failed:
			queue_slice_meal(meal)

func queue_slice_meal(meal: String) -> void:
	var recipe: Dictionary = World.RECIPES[meal]
	var before := bag().duplicate(true)
	bk_run("queue_cook", stove, meal)
	if failed:
		return
	expect_delta(before, negate(recipe.ingredients), "Queued " + meal)
	var active: Dictionary = bk_obj(stove).cooking.active
	var job_id: String = active.id
	bk_probe("claim_cook", stove, job_id, "Claiming %s before it is cooked" % meal, "秒")
	bk_step(float(recipe.time), "cook " + meal)
	before = bag().duplicate(true)
	bk_run("claim_cook", stove, job_id)
	if failed:
		return
	var amount := int(recipe["yield"])
	expect_delta(before, {meal: amount}, "Claimed " + meal)
	bk_count(bk_made, meal, amount)

func catch_river_carp() -> void:
	var river := Vector2i(55, 20)
	for _attempt in range(8):
		if failed or held("carp") > 0:
			break
		bk_run("fish_start", river)
		bk_step(3.1, "wait for the river bite")
		bk_run("fish_catch", river)
	expect(held("carp") > 0, "An ordinary river catch supplied the grilled fish")

func finish_slice_processing() -> void:
	bk_gather("stone", 8, ["rock"])
	bk_gather("wood", 8, ["tree"])
	bk_craft("kiln_kit", 1)
	if failed:
		return
	var reserved := bk_reserved()
	var kiln := hoe_cell(reserved)
	expect(kiln != BK_NONE, "Found reachable ground for the kiln")
	if failed:
		return
	bk_build(kiln, "charcoal_kiln")
	process_slice_recipe(kiln, "charcoal")
	if failed:
		return
	var tree := hoe_cell(reserved)
	expect(tree != BK_NONE and world.tree_planting_problem(TOKEN, tree).is_empty(), "Found reachable ground for an earned sapling")
	if failed:
		return
	var before := bag().duplicate(true)
	bk_run("plant_tree", tree)
	if failed:
		return
	expect_delta(before, {"sapling": -1}, "Planted an earned sapling")
	bk_step(World.TREE_TIME + 0.1, "grow the hardwood tree")
	for _hit in range(3):
		bk_run("axe", tree)
	if failed:
		return
	collect_gathered(tree)
	expect(held("hardwood") == int(before.get("hardwood", 0)) + World.HARDWOOD_YIELD, "Mature tree dropped hardwood and the player collected it")
	if held("plank") < 2 and not failed:
		process_slice_recipe(bk_sawmill, "plank")
	bk_craft("woodwork_parts", int(World.CRAFT.woodwork_parts["yield"]))

func process_slice_recipe(machine: Vector2i, recipe_id: String) -> void:
	var recipe: Dictionary = World.INDUSTRY.PROCESS[recipe_id]
	var before := bag().duplicate(true)
	bk_run("queue_processing", machine, recipe_id)
	if failed:
		return
	expect_delta(before, negate(recipe.ingredients), "Queued " + recipe_id)
	bk_probe("claim_processing", machine, "", "Claiming %s before processing finishes" % recipe_id, "還要")
	bk_step(float(recipe.time), "process " + recipe_id)
	before = bag().duplicate(true)
	bk_run("claim_processing", machine)
	if failed:
		return
	var amount := int(recipe["yield"])
	expect_delta(before, {recipe_id: amount}, "Claimed " + recipe_id)
	bk_count(bk_made, recipe_id, amount)
