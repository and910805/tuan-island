extends SceneTree
const World=preload("res://scripts/world.gd")
const UI=preload("res://scripts/history_ui.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _initialize()->void:run.call_deferred()
func visible(control:Control)->bool:
	if not control.is_visible_in_tree():return false
	var parent:=control.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(control.get_global_rect()):return false
		parent=parent.get_parent()
	return true
func run()->void:
	var app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false);app.menu.hide();app.hud.show()
	var world:=World.new();world.add_player("tester","旅人")
	var life:Dictionary=world.state.lanyang_life
	for cell in World.LANYANG_LIFE.BLOCKAGES:life.cleared[World.key(cell)]=true
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate();life.repaired=true
	world.state.players.tester.region="lanyang";world.state.players.tester.x=32.5;world.state.players.tester.y=29.5
	app.session.own_id="tester"
	for extent in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=extent
		for stage in ["locked","journal","observe","play","remote","completed","sources","replay"]:
			app.session.snapshot=world.region_snapshot("lanyang")
			var record:=World.HISTORY_MEMORY.fresh_record()
			if stage not in ["locked","journal","observe"]:record.seen=["33,22","33,25","33,32"]
			if stage in ["completed","replay"]:record.completed=true;record.round=3
			app.session.snapshot.history_memory["own_memory"]=record
			if stage=="locked":app.session.snapshot.lanyang_life.repaired=false
			if stage=="observe":app.session.snapshot.players.tester.y=22.5
			if stage=="remote":app.session.snapshot.players.tester.x=12.5
			var mode:String="play" if stage in ["play","remote"] else (stage if stage in ["observe","sources"] else "journal")
			UI.open(app,mode,Vector2i(33,22))
			if stage=="replay":UI.open_replay(app)
			for i in range(6):await process_frame
			app._layout_preview();await process_frame
			check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(app.modal.get_global_rect()),stage+" modal fits "+str(extent))
			for control in app.modal.find_children("*","BaseButton",true,false):
				if stage!="sources" or control.is_visible_in_tree():check(visible(control),stage+" button visible: "+control.text)
			if stage=="sources":
				var feature=app.modal.find_child("HistorySourceScene",true,false)
				var next:=app.modal.find_child("HistorySourceNext",true,false) as Button
				var line:=app.modal.find_child("HistorySourceBeatLine",true,false) as Label
				var toggle:=app.modal.find_child("HistorySourceFullToggle",true,false) as Button
				var full:=app.modal.find_child("HistorySourceFull",true,false) as Control
				check(feature!=null and feature.art!=null and visible(feature),"Illustration fits the page")
				check(next!=null and toggle!=null and full!=null and not full.visible,"Short view opens first")
				if feature!=null:
					feature.motion=false
					feature.replay()
					check(not feature.is_processing() and feature.elapsed==feature.REVEAL_SECONDS,"Reduced motion immediately shows the static illustration")
					feature.motion=true
					feature.replay()
					feature._process(0.15)
					check(feature.is_processing() and feature.elapsed>0.0,"The illustrated sequence advances with motion enabled")
				if next!=null and line!=null:
					var first:=line.text
					next.pressed.emit()
					check(line.text!=first,"Next advances the narrated scene")
					next.pressed.emit()
					next.pressed.emit()
					check(line.text==first,"Replay restarts the first beat")
				if toggle!=null and full!=null:
					toggle.button_pressed=true
					check(full.visible and full.find_children("*","LinkButton",true,false).size()==1,"Full text and linked source expand on request")
					toggle.button_pressed=false
			if stage=="replay":
				var replay=app.modal.find_child("MemoryReplay",true,false)
				var return_button:Control=replay.get_parent().get_child(replay.get_index()+1)
				for control in replay.find_children("*","Button",true,false):check(not control.get_global_rect().intersects(return_button.get_global_rect()),"Replay controls do not overlap return button")
			if stage in ["play","remote"]:
				var scene=app.modal.find_child("MemoryScene",true,false)
				check(scene!=null and visible(scene),"Interactive scene visible")
				for control in scene.find_children("*","Button",true,false):check(control.disabled==(stage=="remote"),"Remote scene cannot submit actions")
				app.session.snapshot.history_memory.own_memory.gates=[1,2]
				UI.refresh(app)
				check(app.modal.find_child("MemoryScene",true,false)==scene,"Snapshot retains focusable scene")
				check(scene.levels==[1,2],"Server gate state wins")
			var before:Dictionary=app.session.snapshot.duplicate(true);UI.refresh(app)
			check(before==app.session.snapshot,"Viewing leaves world data untouched")
			if stage=="observe":check(not app.modal.find_child("MemoryObserve",true,false).disabled,"Near observation enabled")
			if stage=="completed":check(not app.modal.find_child("MemoryPlaque",true,false).disabled,"Completed player can place plaque")
	app._close_modal();app.queue_free();await process_frame
	print("HISTORY_UI_TEST checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))
