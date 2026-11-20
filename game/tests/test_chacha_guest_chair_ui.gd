extends SceneTree
## Chacha guest chairs end to end, plus the upgraded handwritten tea menu reached from the completed
## stage button, the NPC page and the journal bookmark.
## Optional user args: --capture-dir=DIR (native only), --size=WxH, --large-text.

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const TeaMenu:=preload("res://scripts/chacha_handwritten_menu.gd")

const ITEMS:=["tea_light","tea_deep","tea_pudding"]
const ITEM_NAMES:={"tea_light":"淺焙茶","tea_deep":"深焙茶","tea_pudding":"茶香布丁"}

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

## Waits for layout and animation to settle before saving a native capture.
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

func contains_text(value:String) -> bool:
	return visible_text(app.modal).contains(value)

func visible_text(node:Node) -> String:
	var lines:PackedStringArray=[]
	if not is_instance_valid(node):return ""
	for candidate:Node in node.find_children("*","Label",true,false):
		if (candidate as Label).is_visible_in_tree() and not (candidate as Label).text.strip_edges().is_empty():lines.append((candidate as Label).text)
	for candidate:Node in node.find_children("*","RichTextLabel",true,false):
		if (candidate as RichTextLabel).is_visible_in_tree() and not (candidate as RichTextLabel).get_parsed_text().strip_edges().is_empty():lines.append((candidate as RichTextLabel).get_parsed_text())
	for candidate:Node in node.find_children("*","Button",true,false):
		if (candidate as Button).is_visible_in_tree():lines.append((candidate as Button).text)
	return "\n".join(lines)

func node_text(node:Node) -> String:
	if node is Label:return (node as Label).text
	if node is RichTextLabel:return (node as RichTextLabel).get_parsed_text()
	return visible_text(node)

func page_present() -> bool:
	return is_instance_valid(app.modal) and app.modal.find_child("ChachaMenuArt",true,false)!=null

func entry_present() -> bool:
	return button("ChachaMenuGoalEntry")!=null

## Full state a read-only page must leave untouched.
func snapshot_state() -> Dictionary:
	return {"person":person.duplicate(true),"objects":world.state.objects.duplicate(true),"chairs":app.session.snapshot.chacha_tea_chairs.duplicate(true),"goals":app.session.snapshot.resident_goals.duplicate(true)}

func detail_text() -> String:
	var detail:Node=app.modal.find_child("ChachaMenuDetail",true,false)
	return node_text(detail).strip_edges() if detail!=null else ""

## Menu page layout: art, three item buttons, detail and back are visible, sized and on screen.
func check_menu_page(tag:String) -> void:
	var art:=app.modal.find_child("ChachaMenuArt",true,false) as Control
	var detail:=app.modal.find_child("ChachaMenuDetail",true,false) as Control
	var back:=button("ChachaMenuBack")
	expect(art!=null and art.is_visible_in_tree(),"Menu art is visible (%s)"%tag)
	expect(detail!=null and detail.is_visible_in_tree(),"Menu detail is visible (%s)"%tag)
	expect(back!=null and back.is_visible_in_tree() and not back.disabled,"Menu back is visible and enabled (%s)"%tag)
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	var rects:Array[Rect2]=[]
	for id:String in ITEMS:
		var item:=button("ChachaMenuItem_"+id)
		expect(item!=null and item.is_visible_in_tree() and not item.disabled,"Menu item is visible and enabled: %s (%s)"%[id,tag])
		if item==null:continue
		var item_rect:=item.get_global_rect()
		expect(item_rect.size.x>=44.0 and item_rect.size.y>=32.0,"Menu item is a comfortable target: %s (%s)"%[id,tag])
		expect(screen.encloses(item_rect),"Menu item stays on screen: %s (%s)"%[id,tag])
		for other in rects:expect(not other.intersects(item_rect.grow(-1.0)),"Menu items do not overlap (%s)"%tag)
		rects.append(item_rect)
	if art==null or detail==null or back==null:return
	var art_rect:=art.get_global_rect()
	var detail_rect:=detail.get_global_rect()
	var back_rect:=back.get_global_rect()
	expect(art_rect.size.x>=120.0 and art_rect.size.y>=64.0,"Menu art has usable size, got %s (%s)"%[str(art_rect.size),tag])
	expect(back_rect.size.x>=44.0 and back_rect.size.y>=32.0,"Back is a comfortable target (%s)"%tag)
	expect(screen.encloses(art_rect) and screen.encloses(detail_rect) and screen.encloses(back_rect),"Art, detail and back stay on screen (%s)"%tag)
	expect(not art_rect.intersects(back_rect.grow(-1.0)) and not detail_rect.intersects(back_rect.grow(-1.0)),"Back does not cover art or detail (%s)"%tag)
	var modal_rect:=(app.modal as Control).get_global_rect().grow(1.0) if app.modal is Control else screen
	expect(modal_rect.encloses(back_rect),"Back sits inside the page (%s)"%tag)
	for candidate:Node in app.modal.find_children("*","Label",true,false):
		var label:=candidate as Label
		if not label.is_visible_in_tree() or label.text.strip_edges().is_empty():continue
		expect(label.size.x>1.0 and label.size.y>1.0,"Visible text has a real box (%s): %s"%[tag,label.text.left(20)])
	var text:=visible_text(app.modal)
	for id:String in ITEMS:expect(text.contains(ITEM_NAMES[id]),"Menu names %s (%s)"%[ITEM_NAMES[id],tag])
	expect(not text.contains("%s") and not text.contains("null") and not text.contains("{"),"No raw placeholders in page text (%s)"%tag)

## Every item selects its own explanation; visiting is side-effect free.
func check_item_switching(tag:String) -> void:
	var seen:Array[String]=[]
	var before:=snapshot_state()
	for id:String in ITEMS:
		await press("ChachaMenuItem_"+id)
		var art=app.modal.find_child("ChachaMenuArt",true,false)
		expect(art!=null and art.item==id,"The illustrated offering follows the selected item")
		var text:=detail_text()
		expect(text.length()>=8,"%s has an explanation (%s)"%[id,tag])
		expect(not seen.has(text),"%s explains something different from the other items (%s)"%[id,tag])
		seen.append(text)
		var item:=button("ChachaMenuItem_"+id)
		if item!=null and item.toggle_mode:expect(item.button_pressed,"%s shows as selected (%s)"%[id,tag])
		expect(page_present() and button("ChachaMenuBack")!=null,"Selecting %s stays on the menu page (%s)"%[id,tag])
		var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
		expect(scroll!=null and not scroll.get_v_scroll_bar().visible,"Reading %s does not require scrolling (%s)"%[id,tag])
		if id=="tea_pudding":
			expect(text.contains("公共廚房") and text.contains("120 秒") and text.contains("漏下來的一束光"),"Pudding uses the real public recipe and shows the missing event")
			if tag.begins_with("goal-"):await capture("04b-pudding-"+tag.trim_prefix("goal-")+".png")
		else:
			expect(text.contains("烘焙台") and text.contains("8 秒" if id=="tea_light" else "12 秒"),"Roast note has the correct duration")
	expect(seen.size()==3,"Three items give three distinct explanations (%s)"%tag)
	await press("ChachaMenuItem_"+ITEMS[0])
	expect(detail_text()==seen[0],"Returning to an item restores its explanation (%s)"%tag)
	expect(snapshot_state()==before,"Switching items changes no items, objects, chairs or progress (%s)"%tag)

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
	var path:="user://chacha-chair-%d.json"%OS.get_process_id()
	if app.session.host(0,"茶亭島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var host:=World.TEA_CERAMICS.TEA_NPC
	person.region=World.TEA_CERAMICS.MAOKONG
	stand(host)
	expect(not world.act(token,"locked",Goals.TEA_CHAIR_ACTION,Goals.TEA_CHAIRS.coast.cell,"coast").ok,"Not available before friendship")
	person.bonds={"chacha":{"points":24,"talk_day":-1,"gift_day":-1}}
	stand(host)
	expect(not world.act(token,"wrong-spot",Goals.TEA_CHAIR_ACTION,host,"coast").ok,"Requires an actual chair space")
	app._interact()
	await process_frame
	await press("BondOpen")
	# Locked: before the report there is no menu button, entry, page or bookmark anywhere.
	expect(button("ChachaMenu")==null and not page_present() and button("ChachaMenuGoalEntry")==null,"Handwritten menu is locked on the NPC page before the report")
	await press("ChachaGuestSeat")
	expect(button("ChachaChair_wood")!=null and button("ChachaChair_coast")!=null,"Two non-teahouse finishes can be chosen")
	await capture("01-seat-options-%s.png"%suffix_tag)
	await press("ChachaChair_coast")
	expect(app.session.snapshot.own_chacha_tea_chair=="coast","Choice is recorded for its contributor")
	expect(app.session.snapshot.chacha_tea_chairs=={"coast":true} and not app.session.snapshot.players[app.session.own_id].has(Goals.TEA_CHAIR_KEY),"Visitors see the seat without seeing personal records")
	expect(not world.act(token,"repeat",Goals.TEA_CHAIR_ACTION,Goals.TEA_CHAIRS.wood.cell,"wood").ok,"One seat per resident")

	var helper:="chacha-chair-guest"
	world.add_player(helper,"另一個島民")
	var friend_record:Dictionary=world.state.players[helper]
	friend_record.region=World.TEA_CERAMICS.MAOKONG
	friend_record.x=host.x+0.5
	friend_record.y=host.y+0.5
	friend_record.bonds={"chacha":{"points":24,"talk_day":-1,"gift_day":-1}}
	expect(world.act(helper,"wood-choice",Goals.TEA_CHAIR_ACTION,Goals.TEA_CHAIRS.wood.cell,"wood").ok,"A second participant can put down the other finish")
	stand(host)
	await capture("02-both-seats-%s.png"%suffix_tag)
	expect(app.session.snapshot.chacha_tea_chairs.size()==2,"Both seats are shared")
	expect(TeaMenu.chair({"chacha_tea_chairs":{"coast":true}}).is_empty(),"The menu never treats a shared chair as the player's chair")
	app._close_modal()
	app._journal()
	await process_frame
	expect(button("ChachaMenuBookmark")==null,"Journal has no menu bookmark before the report")
	app._close_modal()
	Tasks.bond_goal(app,"chacha",4)
	await process_frame
	expect(button("BondGoalDo")!=null and not entry_present() and not page_present(),"Menu entry is absent on the open stage 4 goal page")
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.chacha["4"].state=="done","Report unlocks the handwritten menu")
	app._close_modal()

	# Route 1: completed stage button.
	var before:=snapshot_state()
	Tasks.bond_goal(app,"chacha",4)
	await process_frame
	var entry:=button("ChachaMenuGoalEntry")
	expect(entry!=null and entry.is_visible_in_tree() and not entry.disabled and button("BondGoalDo")==null,"Menu entry appears on the completed goal page")
	expect(entry==null or entry.get_global_rect().size.x>1.0 and entry.get_global_rect().size.y>1.0,"Menu entry has a real box")
	await capture("03-completed-goal-%s.png"%suffix_tag)
	await press("ChachaMenuGoalEntry")
	expect(page_present() and not entry_present(),"Entry opens the menu page")
	check_menu_page("goal-"+suffix_tag)
	await check_item_switching("goal-"+suffix_tag)
	await capture("04-handwritten-menu-goal-%s.png"%suffix_tag)
	expect(snapshot_state()==before,"Opening the page from the goal changes nothing")
	await press("ChachaMenuBack")
	expect(not page_present() and entry_present() and button("BondGoalDo")==null,"Back returns to the completed goal page")
	await press("ChachaMenuGoalEntry")
	await press("ChachaMenuBack")
	expect(snapshot_state()==before,"Repeated goal visits stay side-effect free")
	app._close_modal()

	# Route 2: existing NPC button.
	stand(host)
	app._interact()
	await process_frame
	await press("BondOpen")
	expect(button("ChachaMenu")!=null and button("ChachaGuestSeat")==null,"NPC page offers the menu instead of the chair prompt")
	await press("ChachaMenu")
	expect(page_present(),"NPC button opens the menu page")
	check_menu_page("npc-"+suffix_tag)
	expect(contains_text("淺焙茶") and contains_text("深焙茶") and contains_text("茶香布丁"),"The handwritten tea menu has three items")
	await check_item_switching("npc-"+suffix_tag)
	await capture("05-handwritten-menu-npc-%s.png"%suffix_tag)
	await press("ChachaMenuBack")
	expect(not page_present() and button("ChachaMenu")!=null,"Back returns to the Chacha page")
	expect(snapshot_state()==before,"Opening the page from the NPC changes nothing")
	app._close_modal()

	# Route 3: journal root bookmark.
	app._journal()
	await process_frame
	var bookmark:=button("ChachaMenuBookmark")
	expect(bookmark!=null and bookmark.is_visible_in_tree() and not bookmark.disabled,"Journal shows the menu bookmark after the report")
	expect(bookmark==null or bookmark.get_global_rect().size.x>1.0 and Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0).encloses(bookmark.get_global_rect()),"Bookmark has a real box on screen")
	await capture("06-journal-bookmark-%s.png"%suffix_tag)
	await press("ChachaMenuBookmark")
	expect(page_present(),"Bookmark opens the menu page")
	check_menu_page("journal-"+suffix_tag)
	await check_item_switching("journal-"+suffix_tag)
	await capture("07-handwritten-menu-journal-%s.png"%suffix_tag)
	await press("ChachaMenuBack")
	expect(not page_present() and button("ChachaMenuBookmark")!=null,"Back returns to the journal root")
	expect(snapshot_state()==before,"Opening the page from the journal changes nothing")
	app._close_modal()

	# The main journal in the home region also links to the same menu.
	person.region=World.REGIONS.HOME
	world.switch_region(World.REGIONS.HOME)
	stand(Vector2i(42,33))
	app._journal()
	await process_frame
	await press("ChachaMenuBookmark")
	expect(page_present() and contains_text("海風木椅"),"Home journal remembers the player's chair")
	await press("ChachaMenuBack")
	expect(button("ChachaMenuBookmark")!=null,"Back returns to the home journal")
	app._close_modal()

	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(loaded.state.players[token].get(Goals.TEA_CHAIR_KEY)=="coast" and loaded.state.players[helper].get(Goals.TEA_CHAIR_KEY)=="wood","Both placings persist")
	expect(Goals.done(loaded.state.players[token],"chacha").has(4),"Tea menu unlock persists")
	expect(loaded.state.objects==before.objects,"Browsing the menu left no saved objects behind")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("CHACHA_GUEST_CHAIR_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
