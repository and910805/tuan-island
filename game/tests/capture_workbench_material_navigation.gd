extends "res://tests/capture_workbench_material_hints.gd"
## Native source-recipe lookup, return, real component craft and parent craft.
func run()->void:
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	directory=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="material-navigation-qa"
	assert(app.session.host(0,"配方銜接測試",directory.path_join("world.json"))==OK)
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	var world=app.session.world
	var person:Dictionary=world.state.players[app.session.peers[1]]
	person.x=40.5
	person.y=34.5
	world.state.objects[World.key(BENCH)]={"owner":app.session.peers[1],"type":"bench","items":{}}
	for extent in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=extent
		person.inventory.merge({"wood":20,"copper_ore":4,"copper_joint":0,"plank":2,"charcoal":2},true)
		app.session._send_snapshot(1)
		app.automation_ui.workbench(app,BENCH)
		expect(select_recipe(app.modal,"pump_kit"),"Choose parent pump recipe")
		var controller=app.modal.find_child("WorkbenchController",true,false)
		var back:Button=app.modal.find_child("RecipeBack",true,false)
		var forward:Button=app.modal.find_child("MaterialRecipe",true,false)
		expect(not back.visible and not forward.visible,"Navigation stays hidden before selecting a material")
		var hint:Button=app.modal.find_child("MaterialHint_copper_joint",true,false)
		hint.pressed.emit()
		expect(forward.visible and forward.tooltip_text.contains("銅接頭"),"Ingredient hint exposes its actual recipe link")
		var before:Dictionary=person.inventory.duplicate(true)
		var sequence:int=app.session.counter
		await shot("%d_parent"%extent.x)
		forward.pressed.emit()
		expect(controller.picker.recipe_id=="copper_joint" and back.visible,"Recipe link opens actual component on the same bench")
		expect(back.tooltip_text.contains("河水泵"),"Return target remains named")
		expect(person.inventory==before and app.session.counter==sequence,"Looking up a source recipe performs no world action")
		await shot("%d_component"%extent.x)
		var craft:Button=app.modal.find_child("CraftRecipe",true,false)
		for part in 2:
			expect(not craft.disabled,"Actual component recipe can be crafted")
			craft.pressed.emit()
			await create_timer(0.3).timeout
		expect(int(person.inventory.copper_joint)==2 and int(person.inventory.copper_ore)==0,"Two component crafts consume original ore cost")
		back.pressed.emit()
		expect(controller.picker.recipe_id=="pump_kit" and not back.visible,"Back restores original equipment recipe")
		await shot("%d_returned"%extent.x)
		var old:int=person.inventory.get("pump_kit",0)
		expect(not craft.disabled,"Parent crafting becomes available with crafted components")
		craft.pressed.emit()
		await create_timer(0.3).timeout
		expect(int(person.inventory.get("pump_kit",0))==old+1 and int(person.inventory.copper_joint)==0,"Original parent craft consumes the two components once")
		# Pending-state fixture: no request is sent, but arrows must respect busy().
		hint.pressed.emit()
		controller.pending={"host":false,"at":Time.get_ticks_msec()}
		app.automation_ui.refresh(app)
		expect(forward.disabled,"Lookup is disabled while awaiting a craft result")
		forward.pressed.emit()
		expect(controller.picker.recipe_id=="pump_kit","Callback also refuses navigation during pending request")
		controller.pending={}
		app.automation_ui.refresh(app)
		forward.pressed.emit()
		expect(controller.picker.recipe_id=="copper_joint","Lookup resumes after pending state clears")
		expect(select_recipe(app.modal,"sawmill_kit"),"Manual recipe browsing remains available")
		expect(not back.visible,"Manual browsing clears the previous lookup trail")
		app._close_modal()
	print("WORKBENCH_MATERIAL_NAVIGATION checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
