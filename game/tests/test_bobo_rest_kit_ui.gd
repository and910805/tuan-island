extends SceneTree
## Exercises the mine doors, both station jobs, reporting, crafting and building in a local host.
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const Folio:=preload("res://scripts/build_folio.gd")
const Pattern:=preload("res://scripts/bobo_rest_box_pattern.gd")
const BENCH:=Vector2i(48,24)

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

func button(node_name:String) -> Button:
	if not is_instance_valid(app.modal):return null
	return app.modal.find_child(node_name,true,false) as Button

func press(node_name:String) -> void:
	var choice:=button(node_name)
	expect(choice!=null and not choice.disabled,"Enabled action: "+node_name)
	if choice!=null and not choice.disabled:choice.pressed.emit()
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

func visible_text(node:Node) -> String:
	var lines:PackedStringArray=[]
	for candidate:Node in node.find_children("*","Label",true,false):
		if (candidate as Label).is_visible_in_tree() and not (candidate as Label).text.strip_edges().is_empty():lines.append((candidate as Label).text)
	for candidate:Node in node.find_children("*","RichTextLabel",true,false):
		if (candidate as RichTextLabel).is_visible_in_tree() and not (candidate as RichTextLabel).get_parsed_text().strip_edges().is_empty():lines.append((candidate as RichTextLabel).get_parsed_text())
	return "\n".join(lines)

func entry_present() -> bool:
	return is_instance_valid(app.modal) and app.modal.find_child("BoboRestPatternEntry",true,false)!=null

## Blueprint page layout: art and back are visible, sized, on screen, and do not overlap.
func check_pattern_layout(tag:String) -> void:
	var art:=app.modal.find_child("BoboRestPatternArt",true,false) as Control
	var back:=button("BoboRestPatternBack")
	expect(art!=null and art.is_visible_in_tree(),"Pattern art is visible ("+tag+")")
	expect(back!=null and back.is_visible_in_tree() and not back.disabled,"Pattern back is visible and enabled ("+tag+")")
	if art==null or back==null:return
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	var art_rect:=art.get_global_rect()
	var back_rect:=back.get_global_rect()
	expect(art_rect.size.x>=160.0 and art_rect.size.y>=96.0,"Pattern art has usable size, got %s (%s)"%[str(art_rect.size),tag])
	expect(back_rect.size.x>=44.0 and back_rect.size.y>=32.0,"Back is a comfortable target, got %s (%s)"%[str(back_rect.size),tag])
	expect(screen.encloses(art_rect) and screen.encloses(back_rect),"Art and back stay on screen (%s)"%tag)
	expect(not art_rect.intersects(back_rect.grow(-1.0)),"Back does not cover the art (%s)"%tag)
	var modal_rect:=(app.modal as Control).get_global_rect().grow(1.0) if app.modal is Control else screen
	expect(modal_rect.encloses(back_rect),"Back sits inside the page (%s)"%tag)
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroll!=null:
		expect(not scroll.is_ancestor_of(back),"Back stays fixed when text scrolls (%s)"%tag)
		expect(not scroll.get_v_scroll_bar().visible,"Pattern content fits without scrolling (%s)"%tag)
	for candidate:Node in app.modal.find_children("*","Label",true,false):
		var label:=candidate as Label
		if not label.is_visible_in_tree() or label.text.strip_edges().is_empty():continue
		expect(label.size.x>1.0 and label.size.y>1.0,"Visible text has a real box (%s): %s"%[tag,label.text.left(20)])
	var text:=visible_text(app.modal)
	expect(text.strip_edges().length()>=8,"Pattern page explains the box in words (%s)"%tag)
	expect(text.contains("木板 ×4") and text.contains("纖維 ×2"),"Pattern shows the real crafting cost (%s)"%tag)
	expect(not text.contains("%s") and not text.contains("null") and not text.contains("{"),"No raw placeholders in page text (%s)"%tag)

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
	var path:="user://bobo-rest-kit-%d.json"%OS.get_process_id()
	if app.session.host(0,"礦場旅人",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.board=true
	world.state.picnic=true
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	person.region="jinguashi"
	var bobo:Vector2i=World.bond_place(world.state,"bobo")[1]
	stand(bobo)
	expect(not world.act(token,"early-kit",Goals.REST_KIT_ACTION,bobo,"sign").ok,"Cannot work outside B1")
	stand(World.MINES.ENTRY)
	app._interact()
	await process_frame
	await press("MineEnter")
	expect(world.player_region(token)=="mine_1","Mine entrance enters floor one")
	app._close_modal()
	stand(World.MINES.REST)
	expect(not world.act(token,"no-trust",Goals.REST_KIT_ACTION,World.MINES.REST,"sign").ok,"Unmet trust blocks both jobs")
	person.bonds={"bobo":{"points":14,"talk_day":-1,"gift_day":-1}}
	person.inventory.merge({"wood":2,"plank":0,"fiber":0},true)
	stand(World.MINES.REST)
	app._interact()
	await process_frame
	var crate:=button("BoboRest_box")
	expect(crate!=null and crate.disabled,"Box shows its material gate")
	expect(button("MineRest")!=null,"Existing rest action stays available")
	expect(not world.act(token,"no-materials",Goals.REST_KIT_ACTION,World.MINES.REST,"box").ok,"Server refuses an empty inventory")
	await press("BoboRest_sign")
	expect(int(person.inventory.wood)==0 and int(app.session.snapshot.own_bobo_rest_kit)==1,"Wood and first step are recorded exactly once")
	expect(int(app.session.snapshot.bobo_rest_fixtures)==1 and not app.session.snapshot.players[app.session.own_id].has(Goals.REST_KIT_KEY),"Fixtures are shared without exposing the player's personal record")
	expect(not world.act(token,"repeat-sign",Goals.REST_KIT_ACTION,World.MINES.REST,"sign").ok,"Repeated sign is denied")
	expect(not World.supply_box_unlocked(person),"Supply box still requires the event report")
	person.inventory.merge({"plank":6,"fiber":3},true)
	stand(World.MINES.REST)
	await capture("01-rest-station.png")
	await press("BoboRest_box")
	expect(person.inventory.plank==4 and person.inventory.fiber==2 and int(app.session.snapshot.own_bobo_rest_kit)==3,"Box consumes exactly its materials")
	expect(int(app.session.snapshot.bobo_rest_fixtures)==3,"Both station fixtures are shared")
	app._close_modal()
	var arrival:=app.hud.find_child("TravelArrival",true,false) as Control
	if arrival!=null:
		for candidate:Node in arrival.find_children("*","Button",true,false):
			if candidate.text=="略過":candidate.pressed.emit()
	await process_frame
	await capture("02-trail-fixtures.png")
	stand(World.MINES.UP)
	app._interact()
	await process_frame
	await press("MineUp")
	expect(world.player_region(token)=="jinguashi","B1 return reaches Jinguashi")
	app._close_modal()
	stand(bobo)
	Tasks.bond_goal(app,"bobo",3)
	await process_frame
	expect(button("BondGoalDo")!=null and not entry_present(),"Pattern entry is absent before the real goal report")
	expect(person.inventory.plank==4 and person.inventory.fiber==2,"Fixture holds the planks and fiber left by the built box")
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.bobo["3"].state=="done","Bobo accepts completed work")
	expect(World.exploration_level(World.exploration_points(person))<World.SUPPLY_BOX_LEVEL and World.supply_box_unlocked(person),"The event is an independent blueprint unlock")
	await capture("03-blueprint.png")
	app._close_modal()
	# Completed stage 3 offers the pattern page without mutating the player or world.
	var before_items:Dictionary=person.inventory.duplicate(true)
	var before_objects:Dictionary=world.state.objects.duplicate(true)
	var before_kit:=int(person.get(Goals.REST_KIT_KEY,0))
	Tasks.bond_goal(app,"bobo",3)
	await process_frame
	expect(entry_present() and button("BondGoalDo")==null,"Pattern entry appears on the completed goal page")
	await press("BoboRestPatternEntry")
	check_pattern_layout(suffix_tag)
	await capture("03b-bobo-rest-pattern-%s.png"%suffix_tag)
	expect(person.inventory==before_items and world.state.objects==before_objects and int(person.get(Goals.REST_KIT_KEY,0))==before_kit,"Opening the pattern page changes no items, objects or progress")
	await press("BoboRestPatternBack")
	expect(app.modal.find_child("BoboRestPatternArt",true,false)==null and entry_present(),"Back returns to the completed goal page")
	await press("BoboRestPatternEntry")
	await press("BoboRestPatternBack")
	expect(person.inventory==before_items and world.state.objects==before_objects,"Repeated visits stay side-effect free")
	app._close_modal()
	person.region=World.REGIONS.HOME
	world.state.objects[World.key(BENCH)]={"type":"bench","owner":token,"items":{}}
	stand(BENCH)
	app.automation_ui.workbench(app,BENCH)
	await process_frame
	var recipe:Button
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		if candidate.text==World.CRAFT.supply_box_kit.name:recipe=candidate
	expect(recipe!=null,"Portable box recipe is on the workbench")
	if recipe!=null:recipe.pressed.emit()
	await process_frame
	await press("CraftRecipe")
	expect(int(person.inventory.get("supply_box_kit",0))==1,"Workbench crafts the newly unlocked box")
	var view:Dictionary=app.session.snapshot.players[app.session.own_id]
	expect(Folio.unlocked(app,view,"supply_box"),"The build catalogue also knows the blueprint")
	expect(not Pattern.available({"players":{"another":app.session.snapshot.resident_goals}}),"Only the viewer's own goals unlock the page")
	var spot:=BENCH+Vector2i(1,0)
	expect(world.act(token,"place-box","build",spot,"supply_box").ok,"Build action accepts the newly unlocked box")
	expect(world.state.objects.get(World.key(spot),{}).get("type")=="supply_box","Portable box is placed")
	stand(spot)
	expect(world.act(token,"deposit-stone","deposit",spot,"stone").ok,"Placed box stores supplies")
	expect(not world.act(token,"pack-full","remove",spot,"").ok,"Box must be empty to pack it")
	expect(world.act(token,"withdraw-stone","withdraw",spot,"stone").ok,"Owner can collect the supplies")
	expect(world.act(token,"pack-empty","remove",spot,"").ok and int(person.inventory.get("supply_box_kit",0))==1,"Packing an empty box returns the kit")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(int(loaded.state.players[token].get(Goals.REST_KIT_KEY,0))==Goals.REST_KIT_MASK,"Station steps survive reload")
	expect(World.supply_box_unlocked(loaded.state.players[token]),"Blueprint survives reload")
	expect(Pattern.available({"resident_goals":Goals.view(loaded.state.players[token],loaded.state,token)}),"Reloaded goals still offer the pattern")
	expect(int(loaded.state.players[token].inventory.get("supply_box_kit",0))==1,"Packed kit survives reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("BOBO_REST_KIT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
