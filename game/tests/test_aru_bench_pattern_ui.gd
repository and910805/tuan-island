extends SceneTree

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

func button(id:String) -> Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func press(id:String) -> void:
	var node:=button(id)
	expect(node!=null and not node.disabled,"Enabled action: "+id)
	if node!=null and not node.disabled:node.pressed.emit()
	await process_frame
	await process_frame

var tag:=""

## A spent step must stay disabled; pressing it again must change nothing.
func press_disabled(id:String) -> void:
	var node:=button(id)
	expect(node!=null and node.disabled,"Spent step is disabled: "+id)
	if node!=null:node.pressed.emit()
	await process_frame

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var named:=file_name.get_basename()+"-"+tag+"."+file_name.get_extension()
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(named))==OK,"Capture "+named)

func inspection() -> Control:
	return app.modal.find_child("AruBenchInspection",true,false) as Control if is_instance_valid(app.modal) else null

func finding() -> String:
	var label:=app.modal.find_child("AruBenchFinding",true,false) as Label if is_instance_valid(app.modal) else null
	return label.text if label!=null else ""

func count() -> int:
	var art:=inspection()
	return int(art.call("inspected_count")) if art!=null and art.has_method("inspected_count") else -1

func click_point(index:int) -> void:
	var target:=button("BondGoalStep_%d"%index)
	expect(target!=null,"The inspection has a real button for point %d"%index)
	if target==null:return
	var at:=target.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new()
	motion.position=at
	motion.global_position=at
	root.push_input(motion,true)
	for pressed in [true,false]:
		var click:=InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT
		click.position=at
		click.global_position=at
		click.pressed=pressed
		click.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(click,true)
		await process_frame
	await process_frame

func step_state(index:int) -> String:
	var step:=button("BondGoalStep_%d"%index)
	return "missing" if step==null else ("%s|%s"%[step.disabled,step.text])

func accept_focused() -> void:
	for pressed in [true,false]:
		var event:=InputEventAction.new()
		event.action=&"ui_accept"
		event.pressed=pressed
		root.push_input(event,true)
		await process_frame
	await process_frame

## Points sit inside the drawn backdrop, the backdrop is on screen, and no two points overlap.
func check_geometry() -> void:
	var art:=inspection()
	var picture:=art.get_node_or_null("AruBenchSketchArt") as TextureRect if art!=null else null
	expect(picture!=null and picture.is_visible_in_tree(),"The bench drawing is visible (%s)"%tag)
	if picture==null:return
	var backdrop:=picture.get_global_rect()
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	expect(backdrop.size.x>1.0 and backdrop.size.y>1.0,"Backdrop has a real box (%s)"%tag)
	expect(art.get_global_rect().grow(1.0).encloses(backdrop),"Backdrop stays inside the inspection control (%s)"%tag)
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	expect(scroll==null or not scroll.get_v_scroll_bar().visible,"Inspecting the bench needs no scrollbar (%s)"%tag)
	expect(screen.encloses(backdrop),"Backdrop is on screen (%s)"%tag)
	var rects:Array[Rect2]=[]
	for index in 3:
		var target:=button("BondGoalStep_%d"%index)
		expect(target!=null,"Point %d exists (%s)"%[index,tag])
		if target==null:return
		var rect:=target.get_global_rect()
		rects.append(rect)
		expect(rect.size.x>=24.0 and rect.size.y>=24.0,"Point %d is a usable target (%s)"%[index,tag])
		expect(backdrop.grow(1.0).encloses(rect),"Point %d is inside the actual backdrop (%s)"%[index,tag])
	for a in 3:
		for b in range(a+1,3):expect(not rects[a].intersects(rects[b]),"Points %d and %d do not overlap (%s)"%[a,b,tag])

func run() -> void:
	for size:Vector2i in [Vector2i(1024,640),Vector2i(1280,800)]:
		tag="%dx%d"%[size.x,size.y]
		root.size=size
		await journey()
	print("ARU_BENCH_PATTERN_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func journey() -> void:
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.sound.reduced_motion=tag=="1280x800"
	var path:="user://aru-bench-pattern-%s-%d.json"%[tag,OS.get_process_id()]
	if app.session.host(0,"學木工的島民",path)!=OK:
		expect(false,"Host the island (%s)"%tag)
		app=null
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var aru:=World.Village.resident_cell(world.state,"aru")
	var spot:=Vector2i(38,34)
	person.bonds={"aru":{"points":6,"talk_day":-1,"gift_day":-1}}
	person.inventory.wood=14
	person.inventory.fiber=4
	person.inventory.plank=4
	stand(spot)
	expect(not world.act(token,"locked-bench","build",spot,"long_bench").ok,"The bench is locked before either unlock route")
	var orchard:=[Vector2i(37,32),Vector2i(38,32)]
	for tile:Vector2i in orchard:
		stand(tile+Vector2i(0,1))
		app._perform_build_action("plant_tree",tile)
		await process_frame
		expect(world.state.forest.has(World.key(tile)),"Plant a starter sapling at %s"%str(tile))
	expect(world.step(World.TREE_TIME-1.0,true),"Grow the trees using the world clock")
	stand(orchard[0]+Vector2i(0,1))
	expect(not world.act(token,"too-young","axe",orchard[0]).ok,"A seedling cannot grant early hardwood")
	expect(world.step(1.5,true),"Finish growing the two saplings")
	for tile:Vector2i in orchard:
		stand(tile+Vector2i(0,1))
		for swing in 3:
			app.session.rates[1].clear()
			app._perform_build_action("axe",tile)
			await process_frame
		var drop:Dictionary=world.region_snapshot(World.REGIONS.HOME).gather_drops.get(World.key(tile),{})
		expect(int(drop.get("items",{}).get("hardwood",0))==World.HARDWOOD_YIELD,"Each mature tree drops hardwood in the world")
		world.move_player(token,Vector2.UP,0.1)
		expect(world.step(World.GATHER_DROP_DELAY+0.1,true),"Walk into pickup range to collect the drop")
		app.session._send_snapshot(1)
	expect(int(person.inventory.get("hardwood",0))==4 and person.inventory.sapling==2,"Two mature trees yield four hardwood and return the two saplings")
	await capture("00-hardwood-harvest.png")
	var checkpoint:=World.new()
	expect(checkpoint.load_world(path) and int(checkpoint.state.players[token].inventory.get("hardwood",0))==4,"The harvested hardwood is present after reopening the saved world")
	person.inventory.wood=14
	person.inventory.fiber=4
	stand(aru)
	Tasks.bond_goal(app,"aru",2)
	await process_frame
	var steps:Array=Goals.goal("aru",2).steps
	expect(steps.size()==3,"The bench event has three joints to inspect")
	check_geometry()
	var prompt:=finding()
	expect(not prompt.is_empty() and count()==0,"Nothing is inspected at first and the finding label prompts")
	expect(button("BondGoalDo").disabled and button("BondGoalDo").tooltip_text==Tasks.GOAL_NEED_STEPS,"Finish is gated before any inspection")
	await capture("01a-bench-start.png")
	# Any order; a point click is the same link as the step button.
	await click_point(2)
	var clues:={2:finding()}
	expect(inspection().call("is_animating")==not app.sound.reduced_motion,"Reduced motion shows the check without a ripple")
	expect(count()==1 and step_state(2).begins_with("true|1."),"Clicking the right-leg point picks the same step first")
	expect(clues[2]!=prompt and not clues[2].is_empty(),"The first inspection updates the clue")
	expect(step_state(0).begins_with("false|") and step_state(1).begins_with("false|"),"Other joints stay open")
	await capture("01b-bench-selected.png")
	expect(button("BondGoalStep_0").has_focus(),"Focus advances to the first unchecked joint")
	await accept_focused()
	clues[0]=finding()
	expect(count()==2 and step_state(0).begins_with("true|2.") and clues[0]!=clues[2] and not clues[0].is_empty(),"Pressing a step marks its point and gives a different clue")
	await click_point(2)
	await press_disabled("BondGoalStep_2")
	expect(count()==2 and step_state(2).begins_with("true|1."),"The same joint cannot be inspected twice by mouse or button")
	expect(button("BondGoalDo").disabled and button("BondGoalDo").tooltip_text==Tasks.GOAL_NEED_STEPS,"Two joints still do not open finish")
	await press("BondGoalStepsReset")
	expect(count()==0 and finding()==prompt and step_state(0).begins_with("false|") and step_state(1).begins_with("false|") and step_state(2).begins_with("false|"),"Reset clears marks and returns the prompt")
	expect(button("BondGoalDo").disabled,"Reset re-gates finish")
	check_geometry()
	await click_point(1)
	clues[1]=finding()
	await press("BondGoalStep_2")
	clues[2]=finding()
	await press("BondGoalStep_0")
	clues[0]=finding()
	expect(clues[0]!=clues[1] and clues[1]!=clues[2] and clues[0]!=clues[2] and not clues[0].is_empty() and not clues[1].is_empty(),"Each joint has its own meaningful clue")
	expect(count()==3 and step_state(1).begins_with("true|1.") and step_state(2).begins_with("true|2.") and step_state(0).begins_with("true|3."),"Mouse and press mix in any order, numbered as inspected")
	check_geometry()
	await capture("01c-bench-complete.png")
	await capture("01-hardwood-request.png")
	await press("BondGoalDo")
	expect(int(person.stories.aru)==0 and int(person.inventory.hardwood)==0 and int(person.inventory.plank)==4,"The relationship event consumes hardwood and leaves old planks and errand progress alone")
	expect(World.Village.unlocked(person,"long_bench"),"Reporting unlocks the same double bench as the errand")
	Tasks.bond_goal(app,"aru",2)
	await process_frame
	await press("AruBenchPattern")
	var sketch:=app.modal.find_child("AruBenchSketch",true,false) as TextureRect
	expect(sketch!=null and sketch.texture!=null,"The island journal has an illustrated pattern")
	await capture("01-bench-pattern.png")
	await press("AruBenchPatternBuild")
	expect(button("BuildPlace")!=null and not button("BuildPlace").disabled,"The normal workshop opens with the unlocked item selected")
	await capture("02-bench-workshop.png")
	await press("BuildPlace")
	expect(app.building==Goals.MASTER_BENCH and app.selected=="build","Normal build tool is holding the two-tile bench")
	person.inventory.hardwood=4
	stand(spot+Vector2i(0,1))
	expect(not world.act(token,"protected-second-tile","build",Vector2i(38,33),Goals.MASTER_BENCH).ok,"Protected second tile refuses the whole bench")
	app._perform_build_action("build",spot,Goals.MASTER_BENCH)
	await process_frame
	expect(world.state.objects.get(World.key(spot),{}).get("type")==Goals.MASTER_BENCH and int(person.inventory.wood)==0 and int(person.inventory.hardwood)==0,"Construction places the bench and pays the normal cost")
	expect(world.blocked(spot) and world.blocked(spot+Vector2i.RIGHT),"Both bench tiles have collision")
	expect(not world.act(token,"on-second-tile","build",spot+Vector2i.RIGHT,"lamp").ok,"A second object cannot occupy the right half")
	stand(spot+Vector2i(0,1))
	app._interact()
	await process_frame
	await press("MasterBenchSeat_0")
	expect(person.get(Goals.MASTER_BENCH_SEAT,{}).get("side",-1)==0,"Player sits in the left seat from normal interaction")
	var buddy:="master-bench-buddy"
	world.add_player(buddy,"朋友")
	var guest:Dictionary=world.state.players[buddy]
	guest.x=spot.x+1.5
	guest.y=spot.y+1.5
	guest.blue_outfit=true
	expect(not world.act(buddy,"taken-seat",Goals.MASTER_BENCH_SIT,spot).ok,"An occupied seat rejects another player")
	expect(world.act(buddy,"sit-right",Goals.MASTER_BENCH_SIT,spot+Vector2i.RIGHT).ok,"A friend can occupy the right seat")
	app.session.peers[200]=buddy
	app.session._send_snapshot(1)
	await capture("03-two-seats.png")
	app.session.peers.erase(200)
	world.move_player(token,Vector2.DOWN,0.1)
	expect(not person.has(Goals.MASTER_BENCH_SEAT),"Movement stands the player up")
	person.bonds.aru.points=14
	person[Goals.RECORD_KEY].aru["3"]=""
	stand(spot)
	expect(world.act(token,"carve-from-right",Goals.INSCRIBE_ACTION,spot+Vector2i.RIGHT,"留個位子").ok and world.state.objects[World.key(spot)].inscription=="留個位子","Carving from either side updates the anchor")
	var moved:=spot+Vector2i(2,0)
	stand(spot+Vector2i(1,1))
	expect(world.act(token,"move-bench","move_object",spot+Vector2i.RIGHT,World.key(moved)).ok,"Move the whole bench by its right tile")
	expect(not world.state.objects.has(World.key(spot)) and not world.state.objects.has(World.key(spot+Vector2i.RIGHT)) and not guest.has(Goals.MASTER_BENCH_SEAT),"Old footprint and seats clear together")
	expect(world.state.objects.get(World.key(moved),{}).get("inscription")=="留個位子","Inscription travels with the bench")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(World.Village.unlocked(loaded.state.players[token],"long_bench") and loaded.state.objects.get(World.key(moved),{}).get("type")==Goals.MASTER_BENCH and loaded.state.objects.get(World.key(moved+Vector2i.RIGHT),{}).get("bench_end",false),"The recipe and placed bench survive reload")
	var saved_player:Dictionary=loaded.state.players[token]
	saved_player.x=moved.x+0.5
	saved_player.y=moved.y+1.5
	expect(loaded.act(token,"remove-both","remove",moved+Vector2i.RIGHT).ok,"Dismantle from the right tile")
	expect(not loaded.state.objects.has(World.key(moved)) and not loaded.state.objects.has(World.key(moved+Vector2i.RIGHT)) and saved_player.inventory.hardwood==4,"Both tiles disappear and materials return only once")
	var undo:=loaded.undo_summary(token)
	expect(undo.available and loaded.act(token,"undo-paired-removal",World.UNDO_ACTION,Vector2i.ZERO,undo.id).ok,"Undo restores the two-tile bench")
	expect(loaded.blocked(moved) and loaded.blocked(moved+Vector2i.RIGHT) and saved_player.inventory.hardwood==0,"Undo restores collision and reverses the one material refund")
	var legacy:Dictionary={"stories":{"aru":2}}
	expect(World.Village.unlocked(legacy,"long_bench"),"The older errand unlock still works")
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	app.queue_free()
	await process_frame
