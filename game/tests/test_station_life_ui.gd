extends SceneTree
const World=preload("res://scripts/world.gd")
const Life=World.STATION_LIFE
var app
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func frames()->void:
	for i in range(6):await process_frame
	app._layout_preview();await process_frame
func visible(control:Control)->bool:
	if not control.is_visible_in_tree() or not root.get_visible_rect().encloses(control.get_global_rect()):return false
	var parent=control.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(control.get_global_rect()):return false
		parent=parent.get_parent()
	return true
func layout()->void:
	await frames()
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Station dialogue fits viewport")
	for control in app.modal.find_children("*","Control",true,false):
		if (control is Button or control is Label) and control.is_visible_in_tree():check(visible(control),"Visible station control "+str(control.name))
	check(not app.preview_toolbar.visible,"Dialogue hides unnecessary toolbar")
func press(id:String)->void:
	var button=app.modal.find_child(id,true,false)
	check(button is Button,"Button exists "+id)
	if not button is Button:return
	check(not button.disabled and visible(button),"Button usable "+id)
	if button.disabled:return
	await create_timer(0.13).timeout
	button.pressed.emit();await frames()
func stand(region:String)->void:
	var person:Dictionary=app.session.world.state.players[app.session.profile.token]
	person.region=region;person.travel_book.visited[region]=true
	var cell:Vector2i=Life.RESIDENTS[region].cell
	person.x=cell.x+0.5;person.y=cell.y+1.5
	app.session._send_snapshot(1)
func run()->void:
	var path:=OS.get_environment("TEMP").path_join("station-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"沿線旅人",path)!=OK:check(false,"Host starts");quit(1);return
	var world=app.session.world
	var id:String=app.session.profile.token
	for dimensions in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions;world.state.station_life=Life.fresh();world.state.picnic=true
		var person:Dictionary=world.state.players[id]
		person.inventory.plank=6;person.inventory.stone=6;person.inventory.bread=1
		var coins:=int(person.coins);var saplings:=int(person.inventory.get("sapling",0))
		stand("toucheng");app._interact();await layout()
		check(app.modal.get_meta("station_region","")=="toucheng","Nearest NPC opens its own dialogue")
		check(app.view.interaction_focus()=="station_resident:toucheng","World prompt matches actual interact target")
		var first=app.modal.find_child("StationStory",true,false);first.grab_focus()
		app.session._send_snapshot(1);await frames()
		check(root.gui_get_focus_owner()==first,"Unchanged snapshots preserve button focus")
		await press("StationStory")
		check(Life.story(world.state,id).stage==1,"Accept route note through live UI")
		await press("StationRepair")
		check(world.state.station_life.repairs.toucheng,"Toucheng shared repair committed")
		stand("ruifang");app._interact();await layout()
		check(app.modal.find_child("StationStory",true,false).disabled,"Repair prerequisite visible and enforced")
		check(app.modal.find_child("StationMaterial_plank",true,false).text=="4/2","Repair material count is live")
		person.x=10;app.session._send_snapshot(1);await frames()
		check(app.modal.find_child("StationRepair",true,false).disabled,"Walking away disables remote repair")
		stand("ruifang");await press("StationRepair");await layout()
		check(not app.modal.find_child("StationStory",true,false).disabled,"Repair enables next dialogue without reopening")
		await press("StationStory")
		stand("jiufen");app._interact();await layout()
		check(app.modal.find_child("StationBreadCount",true,false).text.contains("1 / 1"),"Bread counter uses actual inventory")
		person.inventory.bread=0;app.session._send_snapshot(1);await frames()
		check(app.modal.find_child("StationStory",true,false).disabled,"Missing bread disables handoff")
		person.inventory.bread=1;app.session._send_snapshot(1);await frames()
		await press("StationStory");await press("StationRepair")
		check(person.inventory.bread==0 and person.inventory.plank==0 and person.inventory.stone==0,"Actual UI consumes exact bread and three repairs")
		stand("toucheng");app._interact();await layout()
		person.travel_book.visited.erase("jinguashi");app.session._send_snapshot(1);await frames()
		check(app.modal.find_child("StationStory",true,false).disabled,"No personal mine visit means no final reward")
		person.travel_book.visited.jinguashi=true;app.session._send_snapshot(1);await frames()
		await press("StationStory");await layout()
		check(Life.story(world.state,id).stage==4 and person.coins==coins+80 and int(person.inventory.sapling)==saplings+1,"Completion grants exact reward")
		check(app.modal.find_child("StationStory",true,false)==null,"Completed dialogue cannot claim again")
		check(app.modal.find_child("StationRewardReceipt",true,false).text.contains("80"),"Completed dialogue confirms the exact reward")
		await press("StationMemory");await layout()
		check(app.modal_feedback.text.contains("4 / 4"),"Journal exposes completed story and can be reread")
		check(app.modal.find_children("*","Label",true,false).any(func(l):return l.text.contains("祖") or l.text.contains("金瓜石")),"Journal includes route memory")
		var event:=InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=true
		app._unhandled_input(event);await frames()
		check(app.modal==null and app.preview_toolbar.visible,"Escape restores world HUD")
		app._journal();await frames()
		check(app.modal.find_child("NorthJourneyBookmark",true,false)!=null,"Resident handbook provides lasting story entry")
		app.modal.find_child("NorthJourneyBookmark",true,false).pressed.emit();await layout()
		app._close_modal()
	app.session.shutdown();await create_timer(0.3).timeout;app.queue_free();await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("STATION_LIFE_UI_TESTS checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))
