extends SceneTree
## T066 N04-2: Chacha's 〈漏下來的一束光〉 (stage 2) end to end through the real UI.
## Inspect the three curtain panels (any order, reset), pay 8 bamboo + 2 cotton cloth, report, receive the
## original keepsake, then read the reward page and open the existing folio on the bamboo curtain.
## Cooking and world placement are covered by their own suites; saving/reloading is deliberately not asserted here.
## Optional user args: --capture-dir=DIR (native only), --size=WxH, --large-text.

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")

const CURTAIN:="bamboo_curtain"
const KEEPSAKE_KIND:="keepsake_chacha"

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

func keepsake_item() -> String:
	return Goals.keepsake_item(KEEPSAKE_KIND)

func goal_done(stage:int) -> bool:
	return Goals.done(person,"chacha").has(stage)

## A named control exists, is visible and has a real box (layout may scroll, so no on-screen test here).
func check_box(id:String,tag:String) -> void:
	var target:=node(id) as Control
	expect(target!=null and target.is_visible_in_tree(),"%s is visible (%s)"%[id,tag])
	if target!=null:expect(target.get_global_rect().size.x>1.0 and target.get_global_rect().size.y>1.0,"%s has a real box (%s)"%[id,tag])

func entry_present() -> bool:
	return node("ChachaCurtainRewardEntry")!=null

## Reward page: art preview and both buttons are fixed, visible, comfortable and on screen.
func check_reward_page(tag:String) -> void:
	var preview:=button("ChachaCurtainBuiltPreview")
	var back:=button("ChachaCurtainRewardBack")
	expect(preview!=null and preview.is_visible_in_tree() and not preview.disabled,"Built preview is an enabled button ("+tag+")")
	expect(back!=null and back.is_visible_in_tree() and not back.disabled,"Reward back is visible and enabled ("+tag+")")
	if preview!=null and back!=null:
		var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
		var preview_rect:=preview.get_global_rect()
		var back_rect:=back.get_global_rect()
		expect(preview_rect.size.x>=44.0 and preview_rect.size.y>=32.0 and back_rect.size.x>=44.0 and back_rect.size.y>=32.0,"Preview and back are comfortable targets (%s)"%tag)
		expect(screen.encloses(back_rect),"Back stays on screen (%s)"%tag)
		expect(not preview_rect.intersects(back_rect.grow(-1.0)),"Preview and back do not overlap (%s)"%tag)
	for candidate:Node in app.modal.find_children("*","Label",true,false):
		var label:=candidate as Label
		if not label.is_visible_in_tree() or label.text.strip_edges().is_empty():continue
		expect(label.size.x>1.0 and label.size.y>1.0,"Visible text has a real box (%s): %s"%[tag,label.text.left(20)])
	var text:=visible_text(app.modal)
	var recipe:Dictionary=World.BUILD[CURTAIN]
	expect(int(recipe.get("bamboo",0))==6 and int(recipe.get("fiber",0))==2,"Fixture knows the real recipe: bamboo 6, fiber 2")
	expect(text.contains(str(recipe.name)),"Reward names the bamboo curtain (%s)"%tag)
	expect(text.contains("%s ×%d"%[World.NAMES.bamboo,int(recipe.bamboo)]) and text.contains("%s ×%d"%[World.NAMES.fiber,int(recipe.fiber)]),"Reward states the real build materials (%s)"%tag)
	var pudding:Dictionary=World.stove_recipes(World.INDUSTRY.KITCHEN_STOVE).tea_pudding
	for item:String in pudding.ingredients:
		expect(text.contains("%s ×%d"%[World.NAMES[item],pudding.ingredients[item]]),"Reward shows the public stove ingredient "+item)
	expect(text.contains("120 秒") and text.contains("3 份") and text.contains("公共廚房"),"Reward shows the correct cooking location, duration and yield")
	var scroll:=node("ModalScroll") as ScrollContainer
	expect(scroll!=null and not scroll.get_v_scroll_bar().visible,"Reward fits without scrolling (%s)"%tag)
	expect(not text.contains("%s") and not text.contains("null") and not text.contains("{"),"No raw placeholders in reward text (%s)"%tag)

## The folio must be the existing build folio with the bamboo curtain as the only selected entry.
func check_folio_selected(tag:String) -> void:
	expect(is_instance_valid(app.modal) and node("BuildFolio")!=null,"Preview opens the existing folio ("+tag+")")
	expect(node("ChachaCurtainBuiltPreview")==null and node("ChachaCurtainRewardBack")==null,"The reward page is replaced by the folio ("+tag+")")
	var title:=node("BuildTitle") as Label
	expect(title!=null and title.is_visible_in_tree() and title.text.contains(str(World.BUILD[CURTAIN].name)),"Folio title is the bamboo curtain ("+tag+")")
	var chosen:=0
	var wrong:=0
	for candidate:Node in app.modal.find_children("BuildSlot_*","Button",true,false):
		var slot:=candidate as Button
		if not slot.button_pressed or not slot.is_visible_in_tree():continue
		if str(slot.name).begins_with("BuildSlot_"+CURTAIN+"_"):chosen+=1
		else:wrong+=1
	expect(chosen==1 and wrong==0,"Only the bamboo curtain slot is selected (%s)"%tag)
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
	var path:="user://chacha-curtain-story-%d.json"%OS.get_process_id()
	if app.session.host(0,"遮簾島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var site:=World.TEA_CERAMICS.TEA_NPC
	person.region=World.TEA_CERAMICS.MAOKONG
	# Fixture: 熟悉 (6 points) opens stage 2; stage 1 and 3 stay untouched.
	person.bonds={"chacha":{"points":6,"talk_day":-1,"gift_day":-1}}
	person.inventory.bamboo=7
	person.inventory.cotton_cloth=2
	app.sound.reduced_motion=false
	stand(site)
	expect(World.RESIDENT_BOND.stage(person,"chacha")==2,"Fixture friendship reaches the second stage")
	var entry:Dictionary=Goals.goal("chacha",2)
	var cost:=Goals.cost(entry,"")
	expect(int(cost.get("bamboo",0))==8 and int(cost.get("cotton_cloth",0))==2 and cost.size()==2,"Fixture knows the real cost: bamboo 8, cotton cloth 2")
	expect(entry.get("steps",[]).size()==3,"The event has three curtain panels to check")
	var kept_item:=keepsake_item()
	expect(not kept_item.is_empty() and int(person.inventory.get(kept_item,0))==0,"No keepsake before the report")

	# Open event: the reward is closed and the inspection artwork shows.
	Tasks.bond_goal(app,"chacha",2)
	await settle()
	expect(is_instance_valid(app.modal) and node("BondGoalSteps")!=null,"Event page offers the inspection steps")
	expect(not entry_present() and button("ChachaCurtainRewardBack")==null and button("ChachaCurtainBuiltPreview")==null,"Reward is closed before the report")
	check_box("ChachaCurtainInspection","open event "+suffix_tag)
	for index in 3:
		var step:=button("BondGoalStep_%d"%index)
		expect(step!=null and step.is_visible_in_tree() and not step.disabled,"Panel %d can be checked"%index)
		if step!=null:expect(step.text.contains(str(entry.steps[index])),"Panel %d keeps its own name"%index)
	var finish:=button("BondGoalDo")
	expect(finish!=null and finish.disabled and finish.tooltip_text==Tasks.GOAL_NEED_STEPS,"Finish is gated until all panels are checked")
	var text:=visible_text(app.modal)
	expect(text.contains("%s %d／%d"%[World.NAMES.bamboo,7,8]) and text.contains("%s %d／%d"%[World.NAMES.cotton_cloth,2,2]),"Cost rows show held and needed materials")
	await capture("01-open-event-%s.png"%suffix_tag)

	# Arbitrary order, then reset.
	await press("BondGoalStep_1")
	var clue:=node("ChachaCurtainFinding") as Label
	expect(clue!=null and clue.text.contains("日光"),"Inspecting the middle blind tells the player where the light falls")
	var art=node("ChachaCurtainInspection")
	expect(art.inspected_count()==1 and art.is_animating(),"The inspected blind plays its light animation")
	art.advance(1.0)
	expect(not art.is_animating() and not art.is_processing(),"The light settles without an idle animation")
	art.set_reduced_motion(true)
	expect(button("BondGoalStep_1").disabled and button("BondGoalStep_1").text.begins_with("1."),"The middle panel can be checked first")
	expect(not button("BondGoalStep_0").disabled and not button("BondGoalStep_2").disabled and button("BondGoalDo").disabled,"Other panels stay open and finish stays gated")
	await press("BondGoalStep_0")
	expect(art.inspected_count()==2 and not art.is_animating(),"Reduced motion displays the new clue immediately")
	expect(button("BondGoalStep_0").text.begins_with("2.") and button("BondGoalDo").disabled,"Two panels are not enough")
	await press("BondGoalStepsReset")
	var cleared:=true
	for index in 3:
		var step:=button("BondGoalStep_%d"%index)
		cleared=cleared and step!=null and not step.disabled and not step.text.begins_with("%d."%(index+1))
	expect(cleared and button("BondGoalDo").disabled and button("BondGoalDo").tooltip_text==Tasks.GOAL_NEED_STEPS,"Reset clears the checks and re-gates finish")
	expect(node("ChachaCurtainInspection")!=null and node("ChachaCurtainInspection").is_visible_in_tree(),"Inspection artwork survives a reset")
	for index in [2,0,1]:await press("BondGoalStep_%d"%index)
	var step_text:=""
	for index in 3:step_text+=button("BondGoalStep_%d"%index).text
	expect(button("BondGoalStep_2").text.begins_with("1.") and button("BondGoalStep_0").text.begins_with("2.") and button("BondGoalStep_1").text.begins_with("3."),"Any order is accepted, numbered as checked")
	expect(not step_text.is_empty(),"Panels keep readable labels")

	# One bamboo short: all panels checked is not enough.
	finish=button("BondGoalDo")
	expect(finish!=null and finish.disabled,"Finish stays disabled while a material is short")
	expect(finish!=null and finish.tooltip_text.contains(str(World.NAMES.bamboo)) and finish.tooltip_text.contains("7／8"),"Finish explains the bamboo shortage: %s"%(finish.tooltip_text if finish!=null else ""))
	var reason:=node("BondGoalReason") as Label
	expect(reason!=null and reason.visible and reason.text.contains("7／8"),"The reason line names the shortage")
	var inspection_scroll:=node("ModalScroll") as ScrollContainer
	expect(inspection_scroll!=null and not inspection_scroll.get_v_scroll_bar().visible,"Inspection, shortage and actions fit together (%s)"%suffix_tag)
	await capture("02-short-bamboo-%s.png"%suffix_tag)
	var snapshot_before:Dictionary=person.inventory.duplicate(true)
	expect(not world.act(token,"short-curtain",Goals.ACTION,site,"chacha:2::012").ok,"The server also refuses a short hand-in")
	expect(person.inventory==snapshot_before and not goal_done(2),"A refused hand-in spends nothing")

	# Top up: the picks survive the snapshot refresh and finish opens.
	person.inventory.bamboo=8
	stand(site)
	await settle()
	finish=button("BondGoalDo")
	expect(button("BondGoalStep_2")!=null and button("BondGoalStep_2").text.begins_with("1."),"Checked panels survive the snapshot refresh")
	expect(finish!=null and not finish.disabled and finish.tooltip_text.is_empty(),"Finish enables with all panels and materials")
	await capture("03-ready-%s.png"%suffix_tag)

	# Confirm through the UI.
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.chacha["2"].state=="done","The report is confirmed by the server")
	expect(goal_done(2) and not goal_done(1) and not goal_done(3) and not goal_done(4),"Only the second event is recorded")
	expect(int(person.inventory.bamboo)==0 and int(person.inventory.cotton_cloth)==0,"The report takes exactly 8 bamboo and 2 cotton cloth")
	expect(int(person.inventory.get(kept_item,0))==1,"The original keepsake is handed over once")
	expect(Goals.keepsake_claimed(person,KEEPSAKE_KIND) and person.get(Goals.KEEPSAKE_KEY,{}).get(KEEPSAKE_KIND)==true,"Keepsake claim is recorded privately")
	expect(not world.act(token,"repeat-curtain",Goals.ACTION,site,"chacha:2::012").ok and int(person.inventory.get(kept_item,0))==1,"A second report cannot repeat or duplicate the keepsake")
	await capture("04-reported-%s.png"%suffix_tag)
	app._close_modal()

	# Completed page: keepsake line, reward entry, no second payment.
	var before_items:Dictionary=person.inventory.duplicate(true)
	var before_objects:Dictionary=world.state.objects.duplicate(true)
	var before_goals:Variant=person.get(Goals.RECORD_KEY).duplicate(true)
	Tasks.bond_goal(app,"chacha",2)
	await settle()
	expect(node("BondGoalDone")!=null and button("BondGoalDo")==null,"Completed page cannot be paid again")
	expect(node("BondGoalSteps")==null and node("BondGoalStepsReset")==null,"Completed page does not offer the steps again")
	var keep_text:=node("BondGoalKeepsakeText") as Label
	var done_text:=visible_text(app.modal)
	expect((keep_text!=null and keep_text.text.contains(str(Goals.KEEPSAKES[KEEPSAKE_KIND].name))) or done_text.contains(str(entry.keepsake)),"Completed page names the original keepsake")
	var reward_entry:=button("ChachaCurtainRewardEntry")
	expect(reward_entry!=null and reward_entry.is_visible_in_tree() and not reward_entry.disabled,"Completed page offers the reward entry")
	if reward_entry!=null:expect(reward_entry.get_global_rect().size.x>1.0 and reward_entry.get_global_rect().size.y>1.0,"Reward entry has a real box")
	await capture("05-completed-%s.png"%suffix_tag)

	# Reward page.
	await press("ChachaCurtainRewardEntry")
	expect(not entry_present() and button("ChachaCurtainBuiltPreview")!=null and button("ChachaCurtainRewardBack")!=null,"Entry opens the reward page")
	check_reward_page(suffix_tag)
	expect(person.inventory==before_items and world.state.objects==before_objects and person.get(Goals.RECORD_KEY)==before_goals,"Opening the reward page changes no items, objects or progress")
	await capture("06-reward-%s.png"%suffix_tag)
	await press("ChachaCurtainRewardBack")
	expect(node("BondGoalDone")!=null and entry_present() and button("ChachaCurtainBuiltPreview")==null and button("BondGoalDo")==null,"Back returns to the completed page")
	await press("ChachaCurtainRewardEntry")
	await press("ChachaCurtainRewardBack")
	expect(person.inventory==before_items and world.state.objects==before_objects,"Repeated visits stay side-effect free")

	# Built preview leads to the existing folio, selected on the bamboo curtain.
	await press("ChachaCurtainRewardEntry")
	await press("ChachaCurtainBuiltPreview")
	await settle()
	check_folio_selected(suffix_tag)
	await capture("07-folio-bamboo-curtain-%s.png"%suffix_tag)
	expect(person.inventory==before_items and world.state.objects==before_objects,"Opening the folio places and spends nothing")
	app._close_modal()

	person.region=World.REGIONS.HOME
	world.switch_region(World.REGIONS.HOME)
	expect(app.session.shutdown(),"Save and close the island")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the island from disk")
	expect(Goals.done(loaded.state.players.get(token,{}),"chacha").has(2),"The completed inspection is saved")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("CHACHA_CURTAIN_STORY_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
