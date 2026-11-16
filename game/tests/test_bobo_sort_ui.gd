extends SceneTree
const World=preload("res://scripts/world.gd")
var app
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func visible(control:Control)->bool:
	if not control.is_visible_in_tree() or not root.get_visible_rect().encloses(control.get_global_rect()):return false
	var parent:=control.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(control.get_global_rect()):return false
		parent=parent.get_parent()
	return true
func frames()->void:
	for i in range(5):await process_frame
	app._layout_preview();await process_frame
func layout()->void:
	await frames()
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Panel fits viewport")
	for control in app.modal.find_children("*","Control",true,false):
		if control is BaseButton or control is Label:check(visible(control),"Readable control "+str(control.name))
func press(id:String)->void:
	var button=app.modal.find_child(id,true,false)
	check(button!=null,"Action exists "+id)
	if button==null:return
	check(not button.disabled and visible(button),"Action accessible "+id)
	if button.disabled:return
	await create_timer(0.13).timeout
	button.pressed.emit();await frames()
func run()->void:
	var path:=OS.get_environment("TEMP").path_join("bobo-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"礦樣旅人",path)!=OK:check(false,"Host starts");quit(1);return
	var w=app.session.world
	var id:String=app.session.profile.token
	for dimensions in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions
		w.state.bobo_workshop=World.BOBO_WORKSHOP.fresh()
		var p:Dictionary=w.state.players[id]
		p.region="jinguashi"
		var table:Vector2i=World.BOBO_WORKSHOP.sites(w.state).table
		p.x=table.x+0.5;p.y=table.y+1.5
		p.inventory.gold_ore=6;p.inventory.gold_sample=0
		p.stories.bobo=1
		app.session._send_snapshot(1)
		app._interact();await frames()
		check(app.modal!=null and app.modal.get_meta("life_modal_layout","")=="bobo_sort","Nearest table opens sorting instead of home NPC")
		await layout()
		check(app.modal.find_child("SortInventoryCount",true,false).text.contains("持有 6"),"Count reflects actual inventory")
		await press("SortStart")
		check(int(p.inventory.gold_ore)==3,"Start consumes exactly three")
		await layout()
		await press("SortBin_2")
		check(int(w.state.bobo_workshop.jobs[id].step)==0 and int(p.inventory.gold_ore)==3,"Wrong answer consumes nothing and stays on same round")
		app.modal.find_child("SortBin_0",true,false).grab_focus()
		await press("SortBin_0")
		check(int(w.state.bobo_workshop.jobs[id].step)==1,"Correct first answer advances once")
		check(root.gui_get_focus_owner()!=null and root.gui_get_focus_owner().name=="SortBin_0","Keyboard focus survives snapshot refresh")
		app._close_modal();app._bobo_sort_menu();await frames()
		check(int(w.state.bobo_workshop.jobs[id].step)==1,"Closing and reopening retains progress")
		await press("SortBin_1");await press("SortBin_2")
		await layout()
		check(app.modal.find_child("SortBin_0",true,false)==null,"Completed round cannot submit another answer")
		await press("SortClaim")
		check(int(p.inventory.gold_sample)==1 and w.state.bobo_workshop.done.get(id,false),"Claim produces one actual sample and story completion")
		app._refresh_hud()
		check(app.objective.text.contains("回波波身邊"),"HUD points to quest turn-in after sample claim")
		check(not w.state.bobo_workshop.jobs.has(id),"Claim removes live work")
		await press("SortStart");await press("SortCancel")
		check(int(p.inventory.gold_ore)==3 and not w.state.bobo_workshop.jobs.has(id),"Cancel refunds exact input")
		p.x=12.5;p.y=20.5;app.session._send_snapshot(1);await frames()
		check(app.modal.find_child("SortStart",true,false).disabled,"Remote table operations disabled")
		app._close_modal()
		p.region="home";p.x=22.5;p.y=21.5;app.session._send_snapshot(1)
		app._interact();await frames()
		check(app.modal==null,"Gold region NPC not available at matching home coordinates")
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("BOBO_SORT_UI_TESTS checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))
