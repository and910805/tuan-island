extends SceneTree
const World=preload("res://scripts/world.gd")
const Life=World.LANYANG_LIFE
const UI=preload("res://scripts/lanyang_ui.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func visible(control:Control)->bool:
	if control==null or not control.is_visible_in_tree():return false
	var parent:=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(control.get_global_rect()):return false
		parent=parent.get_parent()
	return true
func run()->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.menu.hide();app.hud.show()
	var world:=World.new()
	world.add_player("tester","島民")
	world.state.players.tester.region="lanyang"
	app.session.own_id="tester"
	for extent in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=extent
		for stage in ["clear","donate","repaired","start","waiting","ready","remote"]:
			world.state.lanyang_life=Life.fresh()
			world.state.players.tester.x=32.5;world.state.players.tester.y=29.5
			world.state.players.tester.inventory={"wood":20,"stone":20,"plank":6,"resin":3,"fiber":8,"sapling":4}
			if stage=="clear":world.state.players.tester.y=22.5
			else:
				for tile in Life.BLOCKAGES:world.state.lanyang_life.cleared[World.key(tile)]=true
			if stage not in ["clear","donate"]:
				world.state.lanyang_life.repaired=true
				world.state.lanyang_life.donations=Life.REPAIR_COST.duplicate()
			world.state.time=100.0
			app.session.snapshot=world.region_snapshot("lanyang")
			app.session.snapshot.lanyang_life["own_job"]={"ready":120.0} if stage=="waiting" else ({"ready":100.0} if stage=="ready" else {})
			if stage=="remote":app.session.snapshot.players.tester.x=12.5
			UI.open(app,"clear" if stage=="clear" else ("canal" if stage in ["donate","repaired"] else "nursery"),Life.BLOCKAGES[0])
			for i in range(5):await process_frame
			app._layout_preview();await process_frame
			check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(app.modal.get_global_rect()),stage+" modal fits "+str(extent))
			for control in app.modal.find_children("*","Button",true,false):
				check(visible(control),stage+" button fully visible: "+control.text)
			var names:={"clear":"ClearBlockage","donate":"CanalDonate","start":"NurseryStart","waiting":"NurseryTime","ready":"NurseryClaim","remote":"NurseryStart"}
			if names.has(stage):
				var target:Control=app.modal.find_child(names[stage],true,false)
				check(visible(target),stage+" primary information visible")
				if target is Button:check(target.disabled==(stage=="remote"),stage+" distance guard matches")
			var before:Dictionary=app.session.snapshot.duplicate(true)
			UI.refresh(app)
			check(app.session.snapshot==before,"Viewing does not mutate progress")
	app._close_modal();app.queue_free();await process_frame
	print("GARDEN_UI_TEST checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
