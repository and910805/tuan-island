extends SceneTree
## Tea arrangement event end to end, plus the basic tea set blueprint page offered after the report.
## Optional user args: --capture-dir=DIR (native only), --size=WxH, --large-text.

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const Folio:=preload("res://scripts/build_folio.gd")

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
	return is_instance_valid(app.modal) and app.modal.find_child("ChachaTeaPatternEntry",true,false)!=null

func page_present() -> bool:
	return is_instance_valid(app.modal) and app.modal.find_child("ChachaTeaPatternArt",true,false)!=null

## Blueprint page layout and content: art, materials, build and back are visible, sized and on screen.
func check_pattern_page(tag:String) -> void:
	var art:=app.modal.find_child("ChachaTeaPatternArt",true,false) as Control
	var back:=button("ChachaTeaPatternBack")
	var build:=button("ChachaTeaPatternBuild")
	expect(art!=null and art.is_visible_in_tree(),"Pattern art is visible ("+tag+")")
	expect(back!=null and back.is_visible_in_tree() and not back.disabled,"Pattern back is visible and enabled ("+tag+")")
	expect(build!=null and build.is_visible_in_tree() and not build.disabled,"Pattern build is visible and enabled ("+tag+")")
	if art==null or back==null or build==null:return
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	var art_rect:=art.get_global_rect()
	var back_rect:=back.get_global_rect()
	var build_rect:=build.get_global_rect()
	expect(art_rect.size.x>=160.0 and art_rect.size.y>=96.0,"Pattern art has usable size, got %s (%s)"%[str(art_rect.size),tag])
	expect(back_rect.size.x>=44.0 and back_rect.size.y>=32.0 and build_rect.size.x>=44.0 and build_rect.size.y>=32.0,"Buttons are comfortable targets (%s)"%tag)
	expect(screen.encloses(art_rect) and screen.encloses(back_rect) and screen.encloses(build_rect),"Art and buttons stay on screen (%s)"%tag)
	expect(not art_rect.intersects(back_rect.grow(-1.0)) and not art_rect.intersects(build_rect.grow(-1.0)),"Buttons do not cover the art (%s)"%tag)
	expect(not back_rect.intersects(build_rect.grow(-1.0)),"Back and build do not overlap (%s)"%tag)
	var modal_rect:=(app.modal as Control).get_global_rect().grow(1.0) if app.modal is Control else screen
	expect(modal_rect.encloses(back_rect) and modal_rect.encloses(build_rect),"Buttons sit inside the page (%s)"%tag)
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroll!=null:
		expect(not scroll.is_ancestor_of(back) and not scroll.is_ancestor_of(build),"Buttons stay fixed when text scrolls (%s)"%tag)
		expect(not scroll.get_v_scroll_bar().visible,"Pattern content fits without scrolling (%s)"%tag)
	for candidate:Node in app.modal.find_children("*","Label",true,false):
		var label:=candidate as Label
		if not label.is_visible_in_tree() or label.text.strip_edges().is_empty():continue
		expect(label.size.x>1.0 and label.size.y>1.0,"Visible text has a real box (%s): %s"%[tag,label.text.left(20)])
	var text:=visible_text(app.modal)
	expect(text.strip_edges().length()>=8,"Pattern page explains the tea set in words (%s)"%tag)
	var cost:Dictionary=World.BUILD[Goals.BASIC_TEA_SET]
	expect(int(cost.get("wood",0))==3 and int(cost.get("clay",0))==2,"Fixture knows the real recipe: wood 3, clay 2")
	expect(text.contains("%s ×%d"%[World.NAMES.wood,int(cost.wood)]) and text.contains("%s ×%d"%[World.NAMES.clay,int(cost.clay)]),"Pattern shows the real build cost (%s)"%tag)
	expect(text.contains(str(cost.name)),"Pattern names the basic tea set (%s)"%tag)
	expect(not text.contains("%s") and not text.contains("null") and not text.contains("{"),"No raw placeholders in page text (%s)"%tag)

## The folio must be the existing build folio, showing the basic tea set as the selected entry.
func check_folio_selected(tag:String) -> void:
	expect(is_instance_valid(app.modal) and app.modal.find_child("BuildFolio",true,false)!=null,"Build opens the existing folio ("+tag+")")
	expect(not page_present(),"The pattern page is replaced by the folio ("+tag+")")
	var title:=app.modal.find_child("BuildTitle",true,false) as Label
	expect(title!=null and title.is_visible_in_tree() and title.text.contains(str(World.BUILD[Goals.BASIC_TEA_SET].name)),"Folio title is the basic tea set ("+tag+")")
	var preview:=app.modal.find_child("BuildPreview",true,false) as Control
	expect(preview!=null and preview.is_visible_in_tree() and preview.get_global_rect().size.x>1.0,"Folio preview is visible ("+tag+")")
	var materials:=app.modal.find_child("BuildMaterials",true,false) as Control
	expect(materials!=null and materials.is_visible_in_tree(),"Folio lists materials ("+tag+")")
	var chosen:Array[Button]=[]
	var wrong:=0
	for candidate:Node in app.modal.find_children("BuildSlot_*","Button",true,false):
		var slot:=candidate as Button
		if not slot.button_pressed or not slot.is_visible_in_tree():continue
		if str(slot.name).begins_with("BuildSlot_"+Goals.BASIC_TEA_SET+"_"):chosen.append(slot)
		else:wrong+=1
	expect(chosen.size()==1 and wrong==0,"Only the basic tea set slot is selected (%s)"%tag)
	if chosen.size()==1:
		var scroll:=app.modal.find_child("BuildShelfScroll",true,false) as ScrollContainer
		expect(scroll!=null and scroll.get_global_rect().grow(2).encloses(chosen[0].get_global_rect()),"Selected tea set slot is completely inside the visible shelf (%s)"%tag)
	expect(app.modal.find_child("BuildPlace",true,false)!=null,"Folio keeps its place button ("+tag+")")

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
	var path:="user://chacha-tea-setup-%d.json"%OS.get_process_id()
	if app.session.host(0,"茶席島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var site:=World.TEA_CERAMICS.TEA_NPC
	stand(site)
	expect(not world.act(token,"wrong-region",Goals.TEA_SETUP_ACTION,site,"horizontal:2").ok,"Tea arrangement needs the actual teahouse")
	person.region=World.TEA_CERAMICS.MAOKONG
	stand(site)
	expect(not world.act(token,"not-known",Goals.TEA_SETUP_ACTION,site,"horizontal:2").ok,"Meet Chacha first")
	app._interact()
	await process_frame
	await press("BondOpen")
	await press("BondTalk")
	expect(World.RESIDENT_BOND.stage(person,"chacha")==1,"Ordinary conversation starts the event")
	stand(site)
	app._interact()
	await process_frame
	await press("BondOpen")
	app.sound.reduced_motion=false
	await press("ChachaArrangement")
	expect(button("TeaPlaceCup").disabled and button("TeaConfirmArrangement").disabled,"The cups need a table first")
	var preview=app.modal.find_child("TeaArrangementPreview",true,false)
	await press("TeaAxis_horizontal")
	expect(not preview.is_animating(),"Turning the table does not animate an empty seat")
	button("TeaPlaceCup").pressed.emit()
	expect(preview.is_animating(),"The placement button starts a cup animation")
	preview.reduced_motion=true
	expect(not preview.is_animating() and not preview.is_processing(),"Reduced motion immediately stops the placement animation")
	preview.reduced_motion=false
	expect(button("TeaConfirmArrangement").disabled,"One cup cannot complete the arrangement")
	await press("TeaAxis_vertical")
	button("TeaPlaceCup").pressed.emit()
	expect(preview.is_animating(),"The second cup animates too")
	await create_timer(0.30).timeout
	expect(not preview.is_animating() and not preview.is_processing(),"The cup settles and stops processing")
	expect(button("TeaPlaceCup").disabled and not button("TeaConfirmArrangement").disabled,"Exactly two cups fit")
	expect(preview.axis=="vertical" and preview.cups==2,"The preview shows the current arrangement")
	await capture("01-tea-table.png")
	await press("TeaConfirmArrangement")
	expect(app.session.snapshot.own_chacha_tea_setup=="vertical","The preferred table direction saves")
	expect(not app.session.snapshot.players[app.session.own_id].has(Goals.TEA_SETUP_KEY),"Personal arrangement is not broadcast")
	expect(not world.act(token,"repeat",Goals.TEA_SETUP_ACTION,site,"horizontal:2").ok,"Duplicate confirmed arrangement cannot overwrite the record")
	Tasks.bond_goal(app,"chacha",1)
	await process_frame
	# Before the report there is no blueprint page, entry or build route.
	expect(button("BondGoalDo")!=null and not entry_present() and not page_present(),"Pattern entry is absent before the real goal report")
	expect(button("ChachaTeaPatternBuild")==null and button("ChachaTeaPatternBack")==null,"No pattern buttons exist before the report")
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.chacha["1"].state=="done","Report unlocks basic tea set")
	await capture("02-report-done.png")
	app._close_modal()

	# Completed stage 1 offers the blueprint page without mutating the player or world.
	var before_items:Dictionary=person.inventory.duplicate(true)
	var before_objects:Dictionary=world.state.objects.duplicate(true)
	var before_setup:Variant=person.get(Goals.TEA_SETUP_KEY)
	Tasks.bond_goal(app,"chacha",1)
	await process_frame
	var entry:=button("ChachaTeaPatternEntry")
	expect(entry!=null and entry.is_visible_in_tree() and not entry.disabled and button("BondGoalDo")==null,"Pattern entry appears on the completed goal page")
	expect(entry==null or entry.get_global_rect().size.x>1.0 and entry.get_global_rect().size.y>1.0,"Pattern entry has a real box")
	await capture("02b-completed-goal-%s.png"%suffix_tag)
	await press("ChachaTeaPatternEntry")
	expect(page_present() and not entry_present(),"Entry opens the blueprint page")
	var pattern_art:Control=app.modal.find_child("ChachaTeaPatternArt",true,false)
	var arrangement=pattern_art.get_child(0)
	expect(arrangement.axis=="vertical" and arrangement.cups==2 and not arrangement.is_animating(),"The saved pattern shows the player's arrangement without moving")
	check_pattern_page(suffix_tag)
	await capture("02c-basic-tea-set-pattern-%s.png"%suffix_tag)
	expect(person.inventory==before_items and world.state.objects==before_objects and person.get(Goals.TEA_SETUP_KEY)==before_setup,"Opening the pattern page changes no items, objects or progress")
	await press("ChachaTeaPatternBack")
	expect(not page_present() and entry_present() and button("BondGoalDo")==null,"Back returns to the completed goal page")
	await press("ChachaTeaPatternEntry")
	await press("ChachaTeaPatternBack")
	expect(person.inventory==before_items and world.state.objects==before_objects,"Repeated visits stay side-effect free")

	# Build leads to the existing folio, already selected on the basic tea set.
	await press("ChachaTeaPatternEntry")
	await press("ChachaTeaPatternBuild")
	await process_frame
	await process_frame
	check_folio_selected(suffix_tag)
	await capture("02d-folio-basic-tea-set-%s.png"%suffix_tag)
	expect(person.inventory==before_items and world.state.objects==before_objects,"Opening the folio places and spends nothing")
	app._close_modal()

	person.region=World.REGIONS.HOME
	var tile:=Vector2i(50,24)
	world.state.removed[World.key(tile)]=true
	person.inventory.clay=2
	stand(tile+Vector2i.RIGHT)
	expect(Folio.unlocked(app,app.session.snapshot.players[app.session.own_id],Goals.BASIC_TEA_SET),"Home workshop catalogue unlocks the tea set")
	Tasks.bond_goal(app,"chacha",1)
	await process_frame
	await press("ChachaTeaPatternEntry")
	await press("ChachaTeaPatternBuild")
	await press("BuildPlace")
	expect(app.building==Goals.BASIC_TEA_SET and app.selected=="build","The folio selects the right object for placement")
	var wood_before:=int(person.inventory.wood)
	app._use_selected_at(tile)
	await process_frame
	await process_frame
	expect(world.state.objects.get(World.key(tile),{}).get("type")==Goals.BASIC_TEA_SET and not world.blocked(tile),"New tea set is placed and does not block movement")
	expect(int(person.inventory.clay)==0 and int(person.inventory.wood)==wood_before-3,"Placement debits the specified clay and wood")
	await capture("03-placed-tea-set-%s.png"%suffix_tag)
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(loaded.state.players[token].get(Goals.TEA_SETUP_KEY)=="vertical" and Goals.done(loaded.state.players[token],"chacha").has(1),"Arrangement and recipe unlock survive reload")
	expect(loaded.state.objects.get(World.key(tile),{}).get("type")==Goals.BASIC_TEA_SET,"Tea set survives reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("CHACHA_TEA_ARRANGEMENT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
