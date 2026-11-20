extends SceneTree
## T066 N05-1: Achao's stage-1 rope event end to end through the real UI on a local host.
## Wrong order resets, the authoritative order opens finish, completion hands over exactly one original kit
## (and takes nothing), then the completed page offers the memory guide whose preview opens the existing folio.
## Optional user args: --capture-dir=DIR (native only), --size=WxH, --large-text.
## Wording is read from the game's own data and constants, never retyped here.

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Bond:=World.RESIDENT_BOND
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const MEMORY_PATH:="res://scripts/achao_knot_memory.gd"
const ART_PATH:="achao_knot_art.gd"

const RESIDENT:="achao"
const STAGE:=1
const KIND:="keepsake_achao"
const ORDER:=[2,1,0]
const WRONG_ORDERS:=["012","021","102","120","201"]
const MALFORMED:=["","2","21","2100","211","22a","-10"]

var app
var world:World
var token:String
var person:Dictionary
var dock:Vector2i
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

func node(id:String) -> Node:
	return app.modal.find_child(id,true,false) if is_instance_valid(app.modal) else null

func button(id:String) -> Button:
	return node(id) as Button

func press(id:String) -> void:
	var target:=button(id)
	expect(target!=null and not target.disabled,"Enabled action: "+id)
	if target!=null and not target.disabled:target.pressed.emit()
	await process_frame
	await process_frame

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

## --size=WxH (default 1024x640); malformed or tiny values fall back to the default.
func window_size() -> Vector2i:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--size="):continue
		var parts:=arg.trim_prefix("--size=").to_lower().split("x")
		if parts.size()==2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var wanted:=Vector2i(int(parts[0]),int(parts[1]))
			if wanted.x>=640 and wanted.y>=480:return wanted
	return Vector2i(1024,640)

func visible_text(root_node:Node) -> String:
	var lines:PackedStringArray=[]
	for candidate:Node in root_node.find_children("*","Label",true,false):
		if (candidate as Label).is_visible_in_tree() and not (candidate as Label).text.strip_edges().is_empty():lines.append((candidate as Label).text)
	for candidate:Node in root_node.find_children("*","RichTextLabel",true,false):
		if (candidate as RichTextLabel).is_visible_in_tree() and not (candidate as RichTextLabel).get_parsed_text().strip_edges().is_empty():lines.append((candidate as RichTextLabel).get_parsed_text())
	return "\n".join(lines)

func kit_item() -> String:
	return Goals.keepsake_item(KIND)

func goal_done() -> bool:
	return Goals.done(person,RESIDENT).has(STAGE)

func digits(picks:Array) -> String:
	var text:=""
	for index in picks:text+=str(index)
	return text

func report_extra(picks:String) -> String:
	return "%s:%d::%s"%[RESIDENT,STAGE,picks]

## The rope diagram wherever Codex mounted it: by its own node name first, then by its script.
func knot_art() -> Control:
	var named:=node("AchaoKnotArt") as Control
	if named!=null:return named
	if not is_instance_valid(app.modal):return null
	for candidate:Node in app.modal.find_children("*","Control",true,false):
		var script:Script=candidate.get_script()
		if script!=null and str(script.resource_path).ends_with(ART_PATH):return candidate as Control
	return null

func check_art(tag:String) -> void:
	var art:=knot_art()
	expect(art!=null and art.is_visible_in_tree(),"Rope diagram is visible ("+tag+")")
	if art==null:return
	var box:=art.get_global_rect()
	expect(box.size.x>1.0 and box.size.y>1.0,"Rope diagram has a real box ("+tag+")")
	expect(box.size.y<=140.0,"Rope diagram stays compact (%s): %.0f"%[tag,box.size.y])
	expect(Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0).encloses(box) or _scrolls(),"Rope diagram is reachable on screen ("+tag+")")

func _scrolls() -> bool:
	var scroll:=node("ModalScroll") as ScrollContainer
	return scroll!=null and scroll.get_v_scroll_bar().visible

## Nothing is clipped: no truncated wrapped text, no squeezed buttons, no sideways scrolling, and the
## panel stays inside the window. When the page fits without a scroll bar every control is on screen too.
func check_fit(tag:String) -> void:
	expect(is_instance_valid(app.modal),"A page is open ("+tag+")")
	if not is_instance_valid(app.modal):return
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	expect(screen.encloses(app.modal.get_global_rect()),"Panel stays inside the window ("+tag+")")
	var scroll:=node("ModalScroll") as ScrollContainer
	var needs_scroll:=scroll!=null and scroll.get_v_scroll_bar().visible
	if scroll!=null:expect(not scroll.get_h_scroll_bar().visible,"No sideways scrolling ("+tag+")")
	expect(not needs_scroll,"All instructions and actions fit without scrolling ("+tag+")")
	for candidate:Node in app.modal.find_children("*","Label",true,false):
		var label:=candidate as Label
		if not label.is_visible_in_tree() or label.text.strip_edges().is_empty():continue
		expect(label.size.x>1.0 and label.size.y>1.0,"Visible text has a real box (%s): %s"%[tag,label.text.left(12)])
		expect(label.get_visible_line_count()>=label.get_line_count(),"Text is not truncated (%s): %s"%[tag,label.text.left(12)])
		if not needs_scroll:expect(screen.encloses(label.get_global_rect()),"Text is on screen (%s): %s"%[tag,label.text.left(12)])
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		var target:=candidate as Button
		if not target.is_visible_in_tree():continue
		expect(target.size.x+1.0>=target.get_combined_minimum_size().x,"Button is not squeezed (%s): %s"%[tag,str(target.name)])
		if not needs_scroll:expect(screen.encloses(target.get_global_rect()),"Button is on screen (%s): %s"%[tag,str(target.name)])

func entry_present() -> bool:
	return node("AchaoKnotMemoryEntry")!=null

func cost_rows() -> int:
	var count:=0
	for candidate:Node in app.modal.find_children("BondGoalCost_*","",true,false):count+=1
	return count

func step_numbers(expected:Array) -> bool:
	for index in 3:
		var step:=button("BondGoalStep_%d"%index)
		if step==null:return false
		var at:=expected.find(index)
		if at>=0 and not step.text.begins_with("%d."%(at+1)):return false
		if at<0 and (step.text.begins_with("1.") or step.text.begins_with("2.") or step.text.begins_with("3.")):return false
	return true

func steps_open_and_clear() -> bool:
	for index in 3:
		var step:=button("BondGoalStep_%d"%index)
		if step==null or step.disabled or step.text.begins_with("%d."%(index+1)):return false
	return true

## Memory page: art, preview and back are fixed, visible, comfortable and on screen; nothing is promised beyond the kit.
func check_memory_page(tag:String) -> void:
	var preview:=button("AchaoKnotMemoryPreview")
	var back:=button("AchaoKnotMemoryBack")
	var art:=node("AchaoKnotMemoryArt") as Control
	expect(art!=null and art.is_visible_in_tree() and art.get_global_rect().size.x>1.0 and art.get_global_rect().size.y>1.0,"Memory art is visible with a real box ("+tag+")")
	expect(preview!=null and preview.is_visible_in_tree() and not preview.disabled,"Preview is an enabled button ("+tag+")")
	expect(back!=null and back.is_visible_in_tree() and not back.disabled,"Back is visible and enabled ("+tag+")")
	if preview!=null and back!=null:
		var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
		var preview_rect:=preview.get_global_rect()
		var back_rect:=back.get_global_rect()
		expect(preview_rect.size.x>=44.0 and preview_rect.size.y>=32.0 and back_rect.size.x>=44.0 and back_rect.size.y>=32.0,"Preview and back are comfortable targets ("+tag+")")
		expect(screen.encloses(back_rect) and screen.encloses(preview_rect),"Footer stays on screen ("+tag+")")
		expect(not preview_rect.intersects(back_rect.grow(-1.0)),"Preview and back do not overlap ("+tag+")")
	check_fit("memory "+tag)
	var text:=visible_text(app.modal)
	var recipe:Dictionary=World.BUILD[KIND]
	expect(text.contains(str(Goals.KEEPSAKES[KIND].name)) or text.contains(str(recipe.get("name",""))),"Memory names the original keepsake ("+tag+")")
	expect(button("BondGoalDo")==null and button("BondGoalClaim")==null,"Memory page offers no payment or second claim ("+tag+")")
	expect(not text.contains("%s") and not text.contains("null") and not text.contains("{"),"No raw placeholders in memory text ("+tag+")")
	if not (OS.get_cmdline_user_args().has("--large-text")):
		var scroll:=node("ModalScroll") as ScrollContainer
		expect(scroll==null or not scroll.get_v_scroll_bar().visible,"Memory fits without scrolling at normal text ("+tag+")")

## The folio must be the existing build folio with the rope keepsake as the only selected entry.
func check_folio_selected(tag:String) -> void:
	expect(is_instance_valid(app.modal) and node("BuildFolio")!=null,"Preview opens the existing folio ("+tag+")")
	expect(node("AchaoKnotMemoryPreview")==null and node("AchaoKnotMemoryBack")==null,"The memory page is replaced by the folio ("+tag+")")
	var title:=node("BuildTitle") as Label
	expect(title!=null and title.is_visible_in_tree() and title.text.contains(str(World.BUILD[KIND].name)),"Folio title is the rope keepsake ("+tag+")")
	var chosen:=0
	var wrong:=0
	for candidate:Node in app.modal.find_children("BuildSlot_*","Button",true,false):
		var slot:=candidate as Button
		if not slot.button_pressed or not slot.is_visible_in_tree():continue
		if str(slot.name).begins_with("BuildSlot_"+KIND+"_"):chosen+=1
		else:wrong+=1
	expect(chosen==1 and wrong==0,"Only the rope keepsake slot is selected (%s)"%tag)
	expect(node("BuildPlace")!=null,"Folio keeps its place button ("+tag+")")

func run() -> void:
	var size_tag:="%dx%d"%[window_size().x,window_size().y]
	root.size=window_size()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var large_text:="--large-text" in OS.get_cmdline_user_args()
	if large_text:
		app.sound.preferred_text_scale=3
		app._apply_font_scale_tree()
		await process_frame
		expect(app.font_scale_factor()>=1.2,"Large text is active")
	var suffix_tag:=size_tag+("-large" if large_text else "")
	var path:="user://achao-knot-ui-%d.json"%OS.get_process_id()
	if app.session.host(0,"繩結島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	person.region=World.REGIONS.HOME
	world.state.dock_stage=1
	dock=Bond.dock_cell(world.state)
	var spot:Array=World.bond_place(world.state,RESIDENT)
	expect(spot[0]==World.REGIONS.HOME and spot[1]==dock,"The owner stands at the normal home docking")
	# Fixture: the first friendship stage opens stage 1; nothing else is unlocked.
	person.bonds={RESIDENT:{"points":int(Bond.THRESHOLDS[0]),"talk_day":-1,"gift_day":-1}}
	person.inventory.wood=5
	person.inventory.fiber=3
	person.inventory.erase(kit_item())
	app.sound.reduced_motion=large_text
	stand(dock)
	expect(Bond.stage(person,RESIDENT)==STAGE,"Fixture friendship reaches the first stage")
	var entry:Dictionary=Goals.goal(RESIDENT,STAGE)
	expect(entry.get("order",[])==ORDER and entry.get("steps",[]).size()==3,"Fixture knows the authored order and three sections")
	expect(Goals.cost(entry,"").is_empty() and not entry.has("options") and not entry.has("needs"),"The event costs no items and needs no prerequisite")
	var kit:=kit_item()
	expect(kit==KIND+Goals.KIT_SUFFIX and int(person.inventory.get(kit,0))==0 and not Goals.keepsake_claimed(person,KIND),"No kit before the report")
	expect(World.BUILD.has(KIND) and int(World.BUILD[KIND].get(kit,0))==1,"The original keepsake builds from one kit")
	var memory=load(MEMORY_PATH) if ResourceLoader.exists(MEMORY_PATH) else null
	expect(memory!=null,"The memory guide script exists")
	if memory!=null:
		expect(not memory.available(app.session.snapshot),"Memory stays closed before the event is done")
		expect(memory.available({"resident_goals":{RESIDENT:{STAGE:{"state":"done"}}}}) and memory.available({"resident_goals":{RESIDENT:{str(STAGE):{"state":"done"}}}}),"Memory reads a done stage under either key type")
		expect(not memory.available({"resident_goals":{RESIDENT:{str(STAGE):{"state":"open"}}}}) and not memory.available({}),"Memory ignores open or missing records")

	# Open event: guide art and the three sections, no reward entry, no costs.
	Tasks.bond_goal(app,RESIDENT,STAGE)
	await settle()
	expect(is_instance_valid(app.modal) and node("BondGoalSteps")!=null,"Event page offers the section steps")
	expect(not entry_present() and button("AchaoKnotMemoryBack")==null and button("AchaoKnotMemoryPreview")==null,"Memory is closed before the report")
	for index in 3:
		var step:=button("BondGoalStep_%d"%index)
		expect(step!=null and step.is_visible_in_tree() and not step.disabled,"Section %d can be released"%index)
		if step!=null:expect(step.text.contains(str(entry.steps[index])),"Section %d keeps its own name"%index)
	check_art("open "+suffix_tag)
	var finish:=button("BondGoalDo")
	expect(finish!=null and finish.disabled and finish.tooltip_text==Tasks.GOAL_NEED_STEPS,"Finish is gated until every section is released")
	expect(cost_rows()==0 and (node("BondGoalCost")==null or not (node("BondGoalCost") as Control).visible),"No cost rows are shown")
	check_fit("open "+suffix_tag)
	await capture("01-open-event-%s.png"%suffix_tag)

	# A wrong section resets immediately, including after one correct pick.
	for wrong:String in ["0","20"]:
		for char in wrong:await press("BondGoalStep_"+char)
		var note:=node("BondGoalReason") as Label
		expect(steps_open_and_clear(),"Wrong order %s clears every pick"%wrong)
		expect(note!=null and note.visible and note.text==Tasks.GOAL_ORDER_WRONG,"Wrong order %s shows the order note"%wrong)
		expect(button("BondGoalDo").disabled and not goal_done(),"Wrong order %s keeps finish closed"%wrong)
		expect(knot_art()!=null and knot_art().is_visible_in_tree(),"Rope diagram survives the reset")
		if wrong=="0":await capture("02-wrong-order-%s.png"%suffix_tag)
	# A new pick clears the old note; the manual reset button also clears picks.
	await press("BondGoalStep_2")
	expect(not (node("BondGoalReason") as Label).text.contains(Tasks.GOAL_ORDER_WRONG) and step_numbers([2]),"A new pick clears the old note")
	var rope=knot_art()
	expect(rope.released_count()==1 and rope.is_animating()==not app.sound.reduced_motion,"The first rope loosens and respects motion settings")
	await press("BondGoalStep_1")
	expect(step_numbers([2,1]) and button("BondGoalDo").disabled,"Two sections are not enough")
	await press("BondGoalStepsReset")
	expect(steps_open_and_clear() and button("BondGoalDo").disabled and button("BondGoalDo").tooltip_text==Tasks.GOAL_NEED_STEPS,"Reset clears the picks and re-gates finish")
	expect(rope.released_count()==0 and not rope.is_animating(),"Reset restores the drawn rope")

	# The server is the authority: no other sequence or malformed text is ever accepted.
	var before_items:Dictionary=person.inventory.duplicate(true)
	var before_goals:Variant=person.get(Goals.RECORD_KEY,{}).duplicate(true)
	var serial:=0
	for wrong:String in WRONG_ORDERS+MALFORMED:
		serial+=1
		expect(not world.act(token,"wrong-knot-%d"%serial,Goals.ACTION,dock,report_extra(wrong)).ok,"The server refuses sequence '%s'"%wrong)
	expect(not world.act(token,"away-knot",Goals.ACTION,Vector2i(dock.x+6,dock.y),report_extra("210")).ok,"The server refuses the report away from the owner")
	expect(person.inventory==before_items and person.get(Goals.RECORD_KEY,{})==before_goals and not goal_done() and not Goals.keepsake_claimed(person,KIND),"Refused reports change nothing")

	# Right order, with a snapshot refresh in the middle: picks survive and finish opens.
	for index in [2,1]:await press("BondGoalStep_%d"%index)
	expect(button("BondGoalDo").disabled and button("BondGoalDo").tooltip_text==Tasks.GOAL_NEED_STEPS,"Two correct sections still gate finish")
	stand(dock)
	await settle()
	expect(step_numbers([2,1]),"Picks survive the snapshot refresh")
	await press("BondGoalStep_0")
	expect(step_numbers(ORDER),"The authored order is numbered as released")
	expect(rope.released_count()==3,"All three ropes are visibly released")
	finish=button("BondGoalDo")
	expect(finish!=null and not finish.disabled and finish.tooltip_text.is_empty(),"The authored order opens finish")
	var note_after:=node("BondGoalReason") as Label
	expect(note_after==null or not note_after.visible or note_after.text.is_empty(),"No blocking reason remains")
	expect(cost_rows()==0,"Finish needs no items")
	check_art("ready "+suffix_tag)
	check_fit("ready "+suffix_tag)
	await capture("03-ready-%s.png"%suffix_tag)

	# Confirm through the UI: exactly one original kit, nothing taken.
	var coins:=int(person.get("coins",0))
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals[RESIDENT][str(STAGE)].state=="done","The report is confirmed by the server")
	expect(goal_done() and Goals.done(person,RESIDENT).size()==1,"Only the first event is recorded")
	var expected:Dictionary=before_items.duplicate(true)
	expected[kit]=1
	expect(person.inventory==expected,"The report takes nothing and adds exactly one kit")
	expect(int(person.get("coins",0))==coins,"The report charges no coins")
	expect(Goals.keepsake_claimed(person,KIND) and person.get(Goals.KEEPSAKE_KEY,{}).get(KIND)==true,"Keepsake claim is recorded privately")
	expect(not world.act(token,"repeat-knot",Goals.ACTION,dock,report_extra("210")).ok and int(person.inventory.get(kit,0))==1,"A second report cannot repeat or duplicate the kit")
	expect(not world.act(token,"reclaim-knot",Goals.CLAIM_ACTION,dock,"%s:%d"%[RESIDENT,STAGE]).ok and int(person.inventory.get(kit,0))==1,"The claim action cannot duplicate the kit")
	await capture("04-reported-%s.png"%suffix_tag)
	app._close_modal()

	# Completed page: keepsake line, memory entry, no second payment.
	before_items=person.inventory.duplicate(true)
	var before_objects:Dictionary=world.state.objects.duplicate(true)
	before_goals=person.get(Goals.RECORD_KEY).duplicate(true)
	Tasks.bond_goal(app,RESIDENT,STAGE)
	await settle()
	expect(node("BondGoalDone")!=null and button("BondGoalDo")==null,"Completed page cannot be paid again")
	expect(node("BondGoalSteps")==null and node("BondGoalStepsReset")==null,"Completed page does not offer the steps again")
	var keep_text:=node("BondGoalKeepsakeText") as Label
	expect((keep_text!=null and keep_text.text.contains(str(Goals.KEEPSAKES[KIND].name))) or visible_text(app.modal).contains(str(entry.keepsake)),"Completed page names the original keepsake")
	expect(button("BondGoalClaim")==null,"Nothing is left to claim")
	if memory!=null:expect(memory.available(app.session.snapshot),"Memory opens once the event is done")
	var memory_entry:=button("AchaoKnotMemoryEntry")
	expect(memory_entry!=null and memory_entry.is_visible_in_tree() and not memory_entry.disabled,"Completed page offers the memory entry")
	if memory_entry!=null:expect(memory_entry.get_global_rect().size.x>1.0 and memory_entry.get_global_rect().size.y>1.0,"Memory entry has a real box")
	check_fit("completed "+suffix_tag)
	await capture("05-completed-%s.png"%suffix_tag)

	# Memory page.
	await press("AchaoKnotMemoryEntry")
	expect(not entry_present() and button("AchaoKnotMemoryPreview")!=null and button("AchaoKnotMemoryBack")!=null,"Entry opens the memory page")
	check_memory_page(suffix_tag)
	expect(person.inventory==before_items and world.state.objects==before_objects and person.get(Goals.RECORD_KEY)==before_goals,"Opening the memory changes no items, objects or progress")
	await capture("06-memory-%s.png"%suffix_tag)
	await press("AchaoKnotMemoryBack")
	expect(node("BondGoalDone")!=null and entry_present() and button("AchaoKnotMemoryPreview")==null and button("BondGoalDo")==null,"Back returns to the completed page")
	await press("AchaoKnotMemoryEntry")
	await press("AchaoKnotMemoryBack")
	expect(person.inventory==before_items and world.state.objects==before_objects,"Repeated visits stay side-effect free")

	# Preview leads to the existing folio, selected on the rope keepsake.
	await press("AchaoKnotMemoryEntry")
	await press("AchaoKnotMemoryPreview")
	await settle()
	check_folio_selected(suffix_tag)
	await capture("07-folio-keepsake-%s.png"%suffix_tag)
	expect(person.inventory==before_items and world.state.objects==before_objects,"Opening the folio places and spends nothing")

	# The original keepsake can be placed and reclaimed using the normal tools.
	person.region=World.REGIONS.HOME
	world.switch_region(World.REGIONS.HOME)
	var tile:=Vector2i(50,24)
	world.state.removed[World.key(tile)]=true
	stand(tile+Vector2i.RIGHT)
	await press("BuildPlace")
	app._use_selected_at(tile)
	await settle()
	expect(world.state.objects.get(World.key(tile),{}).get("type")==KIND and int(person.inventory.get(kit,0))==0,"Placement uses the original kit")
	await capture("08-placed-keepsake-%s.png"%suffix_tag)
	expect(world.act(token,"pack-keepsake","remove",tile,"").ok and int(person.inventory.get(kit,0))==1,"Removing the keepsake returns the kit")

	expect(app.session.shutdown(),"Save and close the island")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the island from disk")
	var reloaded:Dictionary=loaded.state.players.get(token,{})
	expect(Goals.done(reloaded,RESIDENT).has(STAGE),"The completed event is saved")
	expect(int(reloaded.get("inventory",{}).get(kit,0))==1 and Goals.keepsake_claimed(reloaded,KIND),"The single kit and its claim are saved")
	expect(Goals.valid_keepsakes(reloaded.get(Goals.KEEPSAKE_KEY),reloaded),"The saved claim is valid for the completed event")
	var view:Dictionary=Goals.view(reloaded,loaded.state,token)
	expect(view[RESIDENT][str(STAGE)].state=="done" and view[RESIDENT][str(STAGE)].keepsake.claimed==true,"The reloaded summary shows the finished, claimed event")
	if memory!=null:expect(memory.available({"resident_goals":view}),"Memory is still open after reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ACHAO_KNOT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
