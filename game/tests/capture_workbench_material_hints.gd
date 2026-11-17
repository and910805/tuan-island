extends SceneTree
const World=preload("res://scripts/world.gd")
const UI=preload("res://scripts/automation_ui.gd")
const BENCH:=Vector2i(40,33)
var app
var directory:=""
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func select_recipe(node:Node,id:String)->bool:
	if node is Button and node.text==World.CRAFT[id].name:node.pressed.emit();return true
	for child in node.get_children():
		if select_recipe(child,id):return true
	return false
func shot(name:String)->void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
	var scroll:ScrollContainer=app.modal.find_child("ModalScroll",true,false)
	var craft:Button=app.modal.find_child("CraftRecipe",true,false)
	expect(scroll.get_global_rect().encloses(craft.get_global_rect()),"Craft action remains visible while showing source hint")
func run()->void:
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	directory=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="workbench-material-hints-qa"
	assert(app.session.host(0,"材料線索測試",directory.path_join("world.json"))==OK)
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	var world=app.session.world
	var person:Dictionary=world.state.players[app.session.peers[1]]
	person.x=40.5
	person.y=34.5
	world.state.objects[World.key(BENCH)]={"owner":app.session.peers[1],"type":"bench","items":{}}
	for extent in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=extent
		app.session._send_snapshot(1)
		app.automation_ui.workbench(app,BENCH)
		expect(select_recipe(app.modal,"woodwork_parts"),"Select the real joinery recipe")
		var before:Dictionary=person.inventory.duplicate(true)
		var label:Label=app.modal.find_child("RecipeUse",true,false)
		for item in ["hardwood","plank"]:
			var help:Button=app.modal.find_child("MaterialHint_"+item,true,false)
			expect(is_instance_valid(help) and help.visible,"Ingredient source icon is available")
			help.pressed.emit()
			expect(label.text.contains(UI.material_hint(item)),"Source detail matches selected material")
			expect(person.inventory==before,"Reading source never consumes materials")
			await shot("%d_%s"%[extent.x,item])
			help.pressed.emit()
			expect(label.text==UI.recipe_use("woodwork_parts",app),"Pressing again returns to product use")
		expect(select_recipe(app.modal,"pump_kit"),"Select actual pump recipe")
		var coal:Button=app.modal.find_child("MaterialHint_charcoal",true,false)
		coal.pressed.emit()
		expect(label.text.contains("炭窯") and label.text.contains("4") and label.text.contains("2"),"Charcoal source displays actual kiln recipe")
		await shot("%d_charcoal"%extent.x)
		person.inventory.merge({"copper_joint":2,"plank":2,"charcoal":2},true)
		var old:int=person.inventory.get("pump_kit",0)
		app.session._send_snapshot(1)
		await create_timer(0.3).timeout
		var craft:Button=app.modal.find_child("CraftRecipe",true,false)
		expect(not craft.disabled,"Source help preserves valid crafting")
		craft.pressed.emit()
		await create_timer(0.3).timeout
		expect(int(person.inventory.get("pump_kit",0))==old+1,"Original craft action produces exactly one pump kit")
		expect(select_recipe(app.modal,"copper_joint"),"Copper joint keeps its actual recipe")
		var ore:Button=app.modal.find_child("MaterialHint_copper_ore",true,false)
		ore.pressed.emit()
		expect(label.text.contains("渡口") and label.text.contains("金瓜石") and label.text.contains("公用鎬"),"Copper source distinguishes transported practice ore and Taiwan mine location")
		await shot("%d_copper_ore"%extent.x)
		app._close_modal()
	print("WORKBENCH_MATERIAL_HINTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
