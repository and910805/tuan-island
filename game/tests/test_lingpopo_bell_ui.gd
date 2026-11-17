extends SceneTree
## Plays both island-history events through ordinary interaction controls with audio muted.
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")

var app
var world:World
var token:String
var person:Dictionary
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func press(node_name:String) -> void:
	var target:=app.modal.find_child(node_name,true,false) as Button if is_instance_valid(app.modal) else null
	expect(target!=null and not target.disabled,"Enabled action: "+node_name)
	if target!=null and not target.disabled:target.pressed.emit()
	await process_frame
	await process_frame

func contains_text(value:String) -> bool:
	if not is_instance_valid(app.modal):return false
	for label:Node in app.modal.find_children("*","Label",true,false):
		if label.text.contains(value):return true
	return false

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func run() -> void:
	root.size=Vector2i(1024,640)
	AudioServer.set_bus_mute(0,true)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://lingpopo-bell-%d.json"%OS.get_process_id()
	if app.session.host(0,"風鈴島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.board=true
	world.state.picnic=true
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	var tree:=World.Festival.TREE_CELL
	var elder:=World.RESIDENT_BOND.bell_cell(world.state)
	stand(tree)
	expect(not world.act(token,"before-intro",Goals.BELL_INSPECT_ACTION,tree,"tree").ok,"Needs first meeting")
	stand(elder)
	app._interact()
	await process_frame
	await press("BondTalk")
	expect(World.RESIDENT_BOND.stage(person,"lingpopo")==1,"First conversation unlocks the event")
	expect(not world.act(token,"wrong-site",Goals.BELL_INSPECT_ACTION,elder,"tree").ok,"Cannot submit tree evidence from the bell")
	var supplies:Dictionary=person.inventory.duplicate(true)
	app._close_modal()
	stand(elder)
	app._interact()
	await process_frame
	await press("LingpopoBrokenBell")
	expect(contains_text("鈴口裂了一道"),"Crack clue is shown as text")
	await capture("01-broken-bell.png")
	await press("LingpopoRecordClue")
	expect(int(app.session.snapshot.own_lingpopo_bell)==Goals.BELL_CRACK_BIT,"Can inspect the cracked bell first")
	expect(not world.act(token,"too-soon",Goals.ACTION,elder,"lingpopo:1::").ok,"One clue cannot complete the event")
	stand(tree)
	app._interact()
	await process_frame
	expect(contains_text("一截空繩"),"World tree interaction opens the visual clue")
	await press("LingpopoRecordClue")
	expect(int(app.session.snapshot.own_lingpopo_bell)==Goals.BELL_INSPECT_MASK,"Both clues sync to the player")
	expect(not app.session.snapshot.players[app.session.own_id].has(Goals.BELL_INSPECT_KEY),"Private clues are omitted from public player rows")
	expect(not world.act(token,"repeated-tree",Goals.BELL_INSPECT_ACTION,tree,"tree").ok,"Cannot record the tree twice")
	stand(elder)
	Tasks.bond_goal(app,"lingpopo",1)
	await process_frame
	await press("BondGoalDo")
	expect(Tasks.bell_history_unlocked(app,1) and not Tasks.bell_history_unlocked(app,2),"First event unlocks page one")
	Tasks.bond_goal(app,"lingpopo",1)
	await process_frame
	await press("LingpopoHistoryPage")
	expect(contains_text("低枝上的空繩"),"Page one can be read immediately")
	await capture("02-history-page-one.png")
	person.bonds.lingpopo.points=6
	stand(elder)
	Tasks.bond_goal(app,"lingpopo",2)
	await process_frame
	for index in [1,0,2]:await press("BondGoalStep_%d"%index)
	await press("BondGoalDo")
	expect(Tasks.bell_history_unlocked(app,2),"The existing shape puzzle unlocks page two")
	expect(person.inventory==supplies,"Neither activity spends or gives inventory")
	Tasks.journal(app)
	await process_frame
	await press("LingpopoIslandHistory")
	expect(contains_text("低枝上的空繩"),"Resident handbook reopens the collection")
	var next:Button
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		if candidate.text=="翻到第二頁":next=candidate
	expect(next!=null,"Unlocked pages can be turned")
	if next!=null:next.pressed.emit()
	await process_frame
	expect(contains_text("三枚不同的鈴"),"Page two can be reread")
	await capture("03-history-page-two.png")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	var record:Dictionary=loaded.state.players[token]
	expect(int(record.get(Goals.BELL_INSPECT_KEY,0))==Goals.BELL_INSPECT_MASK,"Both clues survive reload")
	expect(Goals.done(record,"lingpopo").has_all([1,2]),"Both pages survive reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("LINGPOPO_BELL_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
