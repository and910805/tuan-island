extends SceneTree

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const Music:=preload("res://scripts/scene_music.gd")

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

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
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

func settle() -> void:
	for i in 3:await process_frame

func capture_settled(file_name:String) -> void:
	await settle()
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func modal_node(id:String) -> Node:
	return app.modal.find_child(id,true,false) if is_instance_valid(app.modal) else null

func modal_text() -> String:
	var lines:PackedStringArray=[]
	if not is_instance_valid(app.modal):return ""
	for candidate:Node in app.modal.find_children("*","Label",true,false):
		var label:=candidate as Label
		if label.is_visible_in_tree():lines.append(label.text)
	for candidate:Node in app.modal.find_children("*","RichTextLabel",true,false):
		var rich:=candidate as RichTextLabel
		if rich.is_visible_in_tree():lines.append(rich.get_parsed_text())
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		var target:=candidate as Button
		if target.is_visible_in_tree():lines.append(target.text)
	return "\n".join(lines)

func check_fit(tag:String) -> void:
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	expect(is_instance_valid(app.modal) and screen.encloses(app.modal.get_global_rect()),"Panel stays inside the window ("+tag+")")
	if not is_instance_valid(app.modal):return
	var scroll:=modal_node("ModalScroll") as ScrollContainer
	if scroll!=null:expect(not scroll.get_h_scroll_bar().visible,"No sideways scrolling ("+tag+")")
	var needs_scroll:=scroll!=null and scroll.get_v_scroll_bar().visible
	for candidate:Node in app.modal.find_children("*","Label",true,false):
		var label:=candidate as Label
		if not label.is_visible_in_tree() or label.text.strip_edges().is_empty():continue
		expect(label.size.x>1.0 and label.size.y>1.0,"Text has a real box (%s): %s"%[tag,label.text.left(12)])
		expect(label.get_visible_line_count()>=label.get_line_count(),"Text is not truncated (%s): %s"%[tag,label.text.left(12)])
		if not needs_scroll:expect(screen.encloses(label.get_global_rect()),"Text is on screen (%s): %s"%[tag,label.text.left(12)])
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		var target:=candidate as Button
		if not target.is_visible_in_tree():continue
		expect(target.size.x+1.0>=target.get_combined_minimum_size().x,"Button is not squeezed (%s): %s"%[tag,str(target.name)])
		if not needs_scroll:expect(screen.encloses(target.get_global_rect()),"Button is on screen (%s): %s"%[tag,str(target.name)])

## First real texture under the entry (TextureRect texture or any Control named *Art* with a box).
func check_reward_art(entry:Node,tag:String) -> void:
	var found:=false
	for candidate:Node in entry.find_children("*","Control",true,false):
		var control:=candidate as Control
		if not control.is_visible_in_tree():continue
		var real:=false
		if control is TextureRect:real=(control as TextureRect).texture!=null and (control as TextureRect).texture.get_width()>1
		elif str(control.name).contains("Art"):real=true
		if not real:continue
		found=true
		var box:=control.get_global_rect()
		expect(box.size.x>1.0 and box.size.y>1.0,"Reward art has a real box ("+tag+")")
		var scroll:=modal_node("ModalScroll") as ScrollContainer
		var scrolls:=scroll!=null and scroll.get_v_scroll_bar().visible
		expect(scrolls or Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0).encloses(box),"Reward art fits on screen ("+tag+")")
		expect(app.modal.get_global_rect().grow(1.0).encloses(box),"Reward art stays inside the panel ("+tag+")")
		break
	expect(found,"Reward entry shows real art ("+tag+")")

## Both existing stoves show their own recipe in the reward.
func check_reward_entry(tag:String) -> void:
	var entry:=modal_node("AchaoVoyageRewardArt")
	expect(entry!=null and (entry as Control).is_visible_in_tree(),"Completed N05-3 shows the voyage reward entry ("+tag+")")
	if entry==null:return
	var text:=modal_text()
	var scroll_area:=modal_node("ModalScroll") as ScrollContainer
	expect(scroll_area!=null and not scroll_area.get_v_scroll_bar().visible,"Both recipes and paint cards fit without scrolling ("+tag+")")
	for kind:String in ["stove",World.INDUSTRY.KITCHEN_STOVE]:
		var recipe:Dictionary=World.stove_recipes(kind)[Goals.SEAFOOD_RICE]
		expect(text.contains(str(recipe.name)),"Entry names the dish ("+tag+")")
		for item:String in recipe.ingredients:
			expect(text.contains(str(World.NAMES[item])),"Entry lists %s (%s)"%[item,tag])
		expect(text.contains(str(int(recipe.time))) and text.contains(str(int(recipe.yield))),"Entry shows timing and yield (%s)"%kind)
	expect(not text.contains("%s") and not text.contains("null") and not text.contains("{"),"No raw placeholders ("+tag+")")
	check_reward_art(app.modal,tag)
	var back:=button("AchaoVoyageRewardBack")
	var dock_button:=button("AchaoVoyageRewardDock")
	expect(back!=null and back.is_visible_in_tree() and not back.disabled,"Back is available ("+tag+")")
	expect(dock_button!=null and dock_button.is_visible_in_tree() and not dock_button.disabled,"Dock action is available at the dock ("+tag+")")
	if back!=null and dock_button!=null:
		var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
		var scroll:=modal_node("ModalScroll") as ScrollContainer
		if scroll==null or not scroll.get_v_scroll_bar().visible:expect(screen.encloses(back.get_global_rect()) and screen.encloses(dock_button.get_global_rect()),"Back and dock are on screen ("+tag+")")
		expect(back.size.x>=44.0 and back.size.y>=32.0 and dock_button.size.x>=44.0 and dock_button.size.y>=32.0,"Back and dock are comfortable targets ("+tag+")")
		expect(not back.get_global_rect().intersects(dock_button.get_global_rect().grow(-1.0)),"Back and dock do not overlap ("+tag+")")
	check_fit(tag)

func open_voyage() -> void:
	app._interact()
	await process_frame
	await press("AchaoVoyage")

func check_voyage_audio(aboard:bool)->void:
	if DisplayServer.get_name()=="headless":return
	var snapshot:Dictionary=app.session.snapshot
	var audio=app.sound
	if aboard:
		expect(audio.music.scene_id=="island_voyage" and audio.music.current.playing,"Departure starts the voyage music")
		expect(audio.ambience_kind=="surf" and audio.ambience.playing,"The voyage plays its own swell")
		return
	var track:=Music.local_track(snapshot,"home",snapshot.players[app.session.own_id])
	if track.is_empty():track=Music.track_for("home",float(snapshot.time))
	expect(audio.music.scene_id==track and audio.music.current.playing,"Return resumes the destination music")
	expect(audio.ambience_kind!="surf" and audio.ambience.playing,"Return restores shore ambience")

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
	var tag:=size_tag+("-large" if large_text else "")
	var path:="user://achao-voyage-test-%d.json"%OS.get_process_id()
	if app.session.host(0,"試航島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.dock_stage=1
	var dock:=World.RESIDENT_BOND.dock_cell(world.state)
	stand(dock)
	expect(not world.act(token,"before-trust",Goals.VOYAGE_ACTION,dock,"repair").ok,"Requires trust")
	person.bonds={"achao":{"points":14,"talk_day":-1,"gift_day":-1}}
	expect(not world.act(token,"before-ship",Goals.VOYAGE_ACTION,dock,"repair").ok,"Requires the cooperative dock project")
	world.state.dock_stage=2
	person.inventory.wood=4
	person.inventory.copper_ore=1
	stand(dock)
	await open_voyage()
	await press("AchaoVoyage_repair")
	expect(world.state.get(Goals.DOCK_LIGHT,false) and int(person.inventory.wood)==0 and int(person.inventory.copper_ore)==0,"Repair is shared and charges its exact materials")
	await open_voyage()
	await capture("01-dock-lamp.png")
	await press("AchaoVoyage_depart")
	expect(app.session.snapshot.players[app.session.own_id].get("at_sea",false) and app.voyage_return.visible and not app.hud.visible,"Departure enters sailing mode and keeps the return control accessible")
	check_voyage_audio(true)
	var physical:=Vector2(person.x,person.y)
	world.move_player(token,Vector2.RIGHT,2.0)
	expect(Vector2(person.x,person.y)==physical,"Walking cannot override the route")
	app._cancel_navigation()
	await process_frame
	expect(not person.has(Goals.VOYAGE_START) and not person.has(Goals.VOYAGE_DONE),"Early return lands without granting completion")
	check_voyage_audio(false)
	await open_voyage()
	await press("AchaoVoyage_depart")
	var first:Dictionary=app.session.snapshot.players[app.session.own_id]
	expect(world.step(4.0,true),"Travel advances on the simulation clock")
	app.session._send_snapshot(1)
	await create_timer(0.35).timeout
	var at:Dictionary=app.session.snapshot.players[app.session.own_id]
	expect(float(at.y)>float(first.y) and world.water(Vector2i(int(at.x),int(at.y))),"The animated player is farther down the waterway")
	await capture("02-trial-voyage.png")
	app.session.set_physics_process(true)
	await create_timer(Goals.VOYAGE_SECONDS-3.0).timeout
	app.session.set_physics_process(false)
	expect(person.get(Goals.VOYAGE_DONE,false) and not app.session.snapshot.players[app.session.own_id].get("at_sea",false),"Completed trial automatically returns to dock")
	check_voyage_audio(false)
	expect(not World.has_recipe(person,Goals.SEAFOOD_RICE),"Voyage reward requires reporting")
	Tasks.bond_goal(app,"achao",3)
	await process_frame
	await press("BondGoalDo")
	expect(World.has_recipe(person,Goals.SEAFOOD_RICE),"Reporting unlocks the seafood rice recipe")
	# Completed N05-3 page: reward entry, back and dock, near the dock.
	stand(dock)
	Tasks.bond_goal(app,"achao",3)
	await settle()
	await press("AchaoVoyageRewardEntry")
	check_reward_entry(tag)
	await capture_settled("05-voyage-reward-%s.png"%tag)
	await press("AchaoVoyageRewardBack")
	expect(button("AchaoVoyageRewardBack")==null and not world.state.players[token].has(Goals.VOYAGE_START),"Back leaves the reward page without sailing")
	Tasks.bond_goal(app,"achao",3)
	await settle()
	await press("AchaoVoyageRewardEntry")
	await press("AchaoVoyageRewardDock")
	expect(button("AchaoVoyage_depart")!=null or button("AchaoVoyagePaint")!=null,"Dock action opens the original voyage page")
	await open_voyage()
	await press("AchaoVoyagePaint")
	expect(person.get(Goals.VOYAGE_PAINT,false),"Blue-white hull can be selected")
	await open_voyage()
	await press("AchaoVoyageRewardFromDock")
	expect(modal_node("AchaoVoyageRewardArt")!=null and button("AchaoVoyageRewardDock")==null,"Dock already provides a path back")
	await capture_settled("06-voyage-blue-white-%s.png"%tag)
	await press("AchaoVoyageRewardBack")
	await open_voyage()
	await press("AchaoVoyage_depart")
	expect(world.step(5.0,true),"Blue hull sails the same route")
	app.session._send_snapshot(1)
	await create_timer(0.35).timeout
	await capture("03-blue-white-hull.png")
	app._interact()
	await process_frame
	expect(not person.has(Goals.VOYAGE_START),"Interact also returns to port")
	var stove:=Vector2i(38,32)
	stand(stove)
	Tasks.bond_goal(app,"achao",3)
	await press("AchaoVoyageRewardEntry")
	expect(modal_node("AchaoVoyageRewardArt")!=null and button("AchaoVoyageRewardDock")==null,"Away from the dock the story remains readable without a boat action")
	app._close_modal()
	world.state.objects[World.key(stove)]={"type":"stove","owner":token,"items":{}}
	person.inventory.rice=2
	person.inventory.sardine=1
	person.inventory.seaweed=1
	stand(stove)
	app._interact()
	await process_frame
	expect(button("CookingRecipe_seafood_rice")!=null,"The stone stove shows the unlocked dish")
	await press("CookingRecipe_seafood_rice")
	await capture("04-stone-stove-recipe.png")
	expect(world.act(token,"cook-new-dish","queue_cook",stove,Goals.SEAFOOD_RICE).ok,"Normal stove queue accepts the new recipe")
	expect(world.step(41.0,true),"Dish finishes in the queue")
	var queued:Dictionary=world.state.objects[World.key(stove)].cooking
	expect(world.act(token,"claim-dish","claim_cook",stove,str(queued.ready[0].id)).ok and int(person.inventory.get(Goals.SEAFOOD_RICE,0))==2,"Cook and claim two servings")
	app._close_modal()
	var kitchen:=Vector2i(48,34)
	var kind:=World.INDUSTRY.KITCHEN_STOVE
	for cell:Vector2i in World.KITCHEN_STOVE.cells_at(kitchen):
		world.state.removed[World.key(cell)]=true
	person.inventory.merge({"stone":20,"wood":12,"clay":5,"rice":2,"gold_shrimp":1,"minnow":1},true)
	stand(kitchen+Vector2i(0,2))
	var built:=world.act(token,"build-kitchen","build",kitchen,kind)
	expect(built.ok,"The fixture builds a public kitchen stove: "+str(built.get("message","")))
	if built.ok:
		var dish:=world.act(token,"queue-public-seafood","queue_cook",kitchen,Goals.SEAFOOD_RICE)
		expect(dish.ok and int(person.inventory.rice)==0 and int(person.inventory.gold_shrimp)==0 and int(person.inventory.minnow)==0,"Public stove uses the other ingredient set")
		expect(world.step(121.0,true),"Public stove batch cooks for the full recipe time")
		var ready:Array=world.state.objects[World.key(kitchen)].get("cooking",{}).get("ready",[])
		expect(not ready.is_empty() and world.act(token,"claim-public-seafood","claim_cook",kitchen,str(ready[0].id)).ok and int(person.inventory.get(Goals.SEAFOOD_RICE,0))==5,"Public stove yields three more servings")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	var reloaded:=loaded.load_world(path)
	expect(reloaded,"Reload the saved island")
	if reloaded:
		expect(loaded.state.players[token].get(Goals.VOYAGE_PAINT,false) and World.has_recipe(loaded.state.players[token],Goals.SEAFOOD_RICE),"Boat appearance and recipe survive reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ACHAO_TRIAL_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
