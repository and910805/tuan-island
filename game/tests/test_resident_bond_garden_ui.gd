extends SceneTree
## T066 第六批居民好感 UI test: 點點 (diandian, 插畫家 on the west bank of the 映星池
## in 星芽庭園, region star_garden, fixed cell 20,21, no gate — same model as 暖暖 in
## jiaoxi). Covers region separation (no 點點 point in the home region), distance and
## wrong-cell refusals, the REAL interaction path (app._interact()), the bond dialogue
## (BondSummary / BondTalk / BondGift / BondEvents, no BondSiteBack), the gift chooser,
## the events modal and its 「返回居民回憶」, and 居民回憶's BondEvents_diandian, at
## 1024×640 and 1280×800. Same harness as test_resident_bond_coast_ui.gd (headless).
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); the real profile is never used;
##  * app.village_art_preview=true is set by the test itself (as the coast/ranch tests do);
##  * world time is moved forward by two whole days (time-of-day kept) so that the
##    stage-4 preset's talk_day/gift_day 0 are valid past days;
##  * player.bonds is erased before each viewport size;
##  * the backpack is written directly: every item giftable to 點點 set to 0, then
##    star_mushroom 2, bluebell 1 (liked), radish 2 (common), wood 5 (not giftable);
##  * the player is teleported by writing region/x/y: 0.9 tile south of her cell for
##    the E key (east of her is the 映星池), (14.5,25.5) — the trail arrival point,
##    ~6.9 tiles away — for the distance refusal, and the same 20,22.4 spot in the home
##    region for the region check. Region "star_garden" is entered by writing
##    player.region (no train/trail ride and no garden unlock is exercised);
##  * stage-4 preset: player.bonds.diandian={points:24,talk_day:0,gift_day:0}.
## REALLY EXERCISED:
##  * app._interact() (the E-key handler) opens 和點點聊聊;
##  * WorldView.interaction_focus() is read for the focus checks;
##  * BondTalk, BondGift, BondGift_<item>, 「回到點點身邊」, BondEvents, 「返回居民回憶」,
##    ResidentMemories and BondEvents_diandian are pressed by emitting `pressed`
##    (real Session.perform -> World -> snapshot trip);
##  * Session.perform("resident_talk"/"resident_gift") is called directly only for the
##    negative cases (home region, far away, wrong cell, 暖暖 from the garden).
## LAYOUT POLICY (same as the coast test):
##  * bond dialogue: every control fully visible inside the modal WITHOUT scrolling;
##  * gift chooser: no scrolling at all;
##  * events modal (tabbed, one stage per page): NO outer scrolling, on the default
##    tab and after pressing each of the four tabs; every Label/Button fully on
##    view and not cut, the stage's title + lines (or the locked line, lines
##    hidden) inside BondEventCard.
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const GARDEN_CELL:=Vector2i(20,21)
const GARDEN_REGION:="star_garden"
const FAR_SPOT:=Vector2(14.5,25.5)
const WRONG_CELL:=Vector2i(21,21)
const CONFIG:={
	"diandian":{"stock":{"star_mushroom":2,"bluebell":1},"first":"star_mushroom","second":"bluebell"},
}
var app
var w
var id:String=""
var rid:String="diandian"
var path:String=""
var checks:=0
var failures:=0
var finished:=false

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("RESIDENT_BOND_GARDEN_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE RESIDENT_BOND_GARDEN "+message)

func visible(c:Control)->bool:
	if c==null or not c.is_visible_in_tree() or not root.get_visible_rect().encloses(c.get_global_rect()):return false
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().encloses(c.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func inside_modal(c:Control)->bool:
	return c!=null and is_instance_valid(app.modal) and (app.modal as Control).get_global_rect().grow(0.5).encloses(c.get_global_rect())

func shown_inside_modal(c:Control)->bool:
	if c==null or not is_instance_valid(app.modal):return false
	var rect:=c.get_global_rect()
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer:rect=rect.intersection((parent as Control).get_global_rect())
		parent=parent.get_parent()
	return (app.modal as Control).get_global_rect().grow(0.5).encloses(rect)

func scrolled_out(c:Control)->bool:
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().intersects(c.get_global_rect()):return true
		parent=parent.get_parent()
	return false

func not_cut(l:Label)->bool:
	if l==null:return false
	if l.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	if l.get_visible_line_count()<l.get_line_count():return false
	if l.autowrap_mode==TextServer.AUTOWRAP_OFF or l.clip_text:
		var font:Font=l.get_theme_font("font")
		var font_size:int=l.get_theme_font_size("font_size")
		for part:String in l.text.split("\n"):
			if font.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>l.size.x+1.0:return false
	return true

func button_not_cut(b:Button)->bool:
	if b==null:return false
	if b.clip_text or b.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	return b.size.x+0.5>=b.get_combined_minimum_size().x

func control(name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(name,true,false) as Control

func find_button(prefix:String)->Button:
	if not is_instance_valid(app.modal):return null
	for node in (app.modal as Node).find_children("*","Button",true,false):
		var b:=node as Button
		if b!=null and b.is_visible_in_tree() and b.text.begins_with(prefix):return b
	return null

func find_label(text:String)->Label:
	if not is_instance_valid(app.modal):return null
	for node in (app.modal as Node).find_children("*","Label",true,false):
		var l:=node as Label
		if l!=null and l.is_visible_in_tree() and l.text==text:return l
	return null

func texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

func body_scroll()->ScrollContainer:
	return control("ModalScroll") as ScrollContainer

func layout_meta()->String:
	if not is_instance_valid(app.modal):return ""
	return str((app.modal as Node).get_meta("life_modal_layout",""))

func rect_info(c:Control)->String:
	var modal_rect:="none"
	if is_instance_valid(app.modal):modal_rect=str((app.modal as Control).get_global_rect())
	var own:="null"
	if c!=null:own=str(c.get_global_rect())
	return "modal=%s control=%s"%[modal_rect,own]

func settle()->void:
	for i in range(6):await process_frame
	app._layout_preview();await process_frame

func refresh()->void:
	app.session._send_snapshot(1)
	if app.view!=null and app.view.has_method("_process"):app.view._process(0.0)
	await settle()

## Teleport the player (PRESET) to a float position in a region.
func stand(region:String,at:Vector2)->void:
	var person:Dictionary=w.state.players[id]
	person.region=region
	person.x=at.x;person.y=at.y
	await refresh()

func home_region()->String:
	return World.REGIONS.HOME

func region_of(resident:String)->String:
	return str(World.bond_place(app.session.snapshot,resident)[0])

## 0.9 tile south of the cell centre (east of her lies the 映星池).
func near(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(0.5,1.4)

func place()->Vector2i:
	return World.bond_place(app.session.snapshot,rid)[1]

func inventory()->Dictionary:
	return w.state.players[id].inventory

func held(item:String)->int:
	return int(inventory().get(item,0))

func bond()->Dictionary:
	var all:Variant=app.session.snapshot.get("resident_bonds",{})
	if not all is Dictionary:return {}
	var found:Variant=(all as Dictionary).get(rid,{})
	return found if found is Dictionary else {}

func record()->Dictionary:
	return Bond.record(w.state.players[id],rid)

func today()->int:
	return Bond.day(float(w.state.time))

func clear_toast()->void:
	if app.toast==null or not is_instance_valid(app.toast):return
	var toast_label:Label=app.toast
	toast_label.text=""

func toast_text()->String:
	if app.toast==null or not is_instance_valid(app.toast):return ""
	return str((app.toast as Label).text)

func press(name:String)->bool:
	var button:=control(name) as BaseButton
	check(button!=null and not button.disabled,"Enabled "+name)
	if button==null or button.disabled:return false
	clear_toast()
	await create_timer(0.12).timeout
	button.pressed.emit()
	await settle()
	return true

func press_button(b:BaseButton,label:String)->bool:
	check(b!=null and not b.disabled,"Enabled button: "+label)
	if b==null or b.disabled:return false
	clear_toast()
	await create_timer(0.12).timeout
	b.pressed.emit()
	await settle()
	return true

func close()->void:
	app._close_modal()
	await settle()

## The real E-key handler.
func interact()->void:
	await close()
	clear_toast()
	app._interact()
	await settle()

func focus()->String:
	if app.view==null or not app.view.has_method("interaction_focus"):return "?"
	return str(app.view.interaction_focus())

func needs_scroll()->bool:
	var scroll:=body_scroll()
	if scroll==null:return false
	var bar:=scroll.get_v_scroll_bar()
	return bar.max_value>bar.page+1.0

func scroll_top()->void:
	var scroll:=body_scroll()
	if scroll!=null and scroll.scroll_vertical!=0:
		scroll.scroll_vertical=0
		await settle()

func reach(c:Control,label:String)->bool:
	if c==null:return false
	if visible(c) and inside_modal(c):return true
	var scroll:=body_scroll()
	if scroll!=null and scroll.is_ancestor_of(c):
		scroll.ensure_control_visible(c)
		await settle()
		note("%s reachable only after scrolling the modal body (%s)"%[c.name,label])
	return visible(c) and inside_modal(c)

func labels_ok(label:String)->void:
	for node in (app.modal as Node).find_children("*","Label",true,false):
		var l:=node as Label
		if not l.is_visible_in_tree() or scrolled_out(l):continue
		check(shown_inside_modal(l),"Caption inside the card: %s (%s) %s"%[l.text,label,rect_info(l)])
		check(not_cut(l),"Caption not cut or ellipsized: %s (%s)"%[l.text,label])

func buttons_on_view_ok(label:String)->void:
	for node in (app.modal as Node).find_children("*","BaseButton",true,false):
		var b:=node as Control
		if not b.is_visible_in_tree() or scrolled_out(b):continue
		check(shown_inside_modal(b),"Button on view stays inside the modal: %s (%s) %s"%[b.name,label,rect_info(b)])

func row_fits(row:Control,label:String)->void:
	check(row!=null,"Button row exists (%s)"%label)
	if row==null:return
	check(inside_modal(row),"Button row inside the modal (%s) %s"%[label,rect_info(row)])
	var parent:=row.get_parent() as Control
	if parent!=null:
		check(parent.get_global_rect().grow(0.5).encloses(row.get_global_rect()),"Button row stays inside its parent (%s) row=%s parent=%s"%[label,str(row.get_global_rect()),str(parent.get_global_rect())])
	check(row.get_combined_minimum_size().x<=row.size.x+0.5,"Button row does not overflow horizontally (%s) min=%.0f size=%.0f"%[label,row.get_combined_minimum_size().x,row.size.x])
	for child in row.get_children():
		var c:=child as Control
		if c==null or not c.is_visible_in_tree():continue
		check(row.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"Row child %s inside the row (%s) %s"%[c.name,label,rect_info(c)])

# --------------------------------------------------------------- presets --

func stock()->Dictionary:
	return CONFIG[rid].stock

func stock_bag()->void:
	var inv:Dictionary=inventory()
	for item in inv.keys():
		if Bond.giftable(rid,str(item)):inv[item]=0
	for item in stock():inv[item]=int(stock()[item])
	inv["radish"]=2;inv["wood"]=5
	app.session._send_snapshot(1)

# ---------------------------------------------------------- bond dialogue --

func npc()->String:
	return Bond.name_of(rid)

func dialogue_open()->bool:
	return is_instance_valid(app.modal) and layout_meta()=="community_board" and find_label("和%s聊聊"%npc())!=null and control("BondSummary")!=null

func summary_text()->String:
	var summary:=control("BondSummary") as Label
	return summary.text if summary!=null else ""

## Stand next to the resident, press the real interaction key handler.
func open_by_interact(label:String,cell:Vector2i=Vector2i(-1,-1))->bool:
	if cell==Vector2i(-1,-1):cell=place()
	await stand(region_of(rid),near(cell))
	check(focus()==rid,"World focus is %s next to %s (%s): %s"%[npc(),str(cell),label,focus()])
	await interact()
	var ok:=dialogue_open()
	check(ok,"E next to %s opens 和%s聊聊 (%s) modal_title=%s"%[npc(),npc(),label,texts().left(40).replace("\n"," | ")])
	return ok

func dialogue_layout(label:String)->void:
	if not dialogue_open():return
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Bond dialogue fits the viewport (%s) %s"%[label,rect_info(null)])
	if needs_scroll():note("bond dialogue body scrolls (%s %s)"%[rid,label])
	var all:=texts()
	check(all.contains("%s・%s"%[npc(),str(Bond.LOCAL_PLACES[rid])]),"Dialogue shows the place line %s・%s (%s)"%[npc(),Bond.LOCAL_PLACES[rid],label])
	check(all.contains("%s喜歡：%s"%[npc(),str(Bond.LIKE_TEXT[rid])]),"Dialogue shows the like line of %s (%s)"%[npc(),label])
	var title:=find_label("和%s聊聊"%npc())
	check(title!=null and visible(title) and not_cut(title),"Dialogue title readable (%s)"%label)
	for name in ["BondSummary","BondTalk","BondGift","BondEvents"]:
		var c:=control(name)
		check(c!=null,"%s exists (%s)"%[name,label])
		if c==null:continue
		check(visible(c) and inside_modal(c),"%s fully visible inside the dialogue without scrolling (%s) %s"%[name,label,rect_info(c)])
		if c is Button:check(button_not_cut(c as Button),"%s caption not cut (%s)"%[name,label])
		elif c is Label:check(not_cut(c as Label),"%s not cut (%s)"%[name,label])
	check(control("BondSiteBack")==null,"%s's dialogue has no BondSiteBack (%s)"%[npc(),label])
	var talk:=control("BondTalk")
	if talk!=null:row_fits(talk.get_parent() as Control,"dialogue actions "+label)
	buttons_on_view_ok("dialogue "+label)
	labels_ok("dialogue "+label)
	var footer:Label=null
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Label).text.begins_with("每個世界日第一次聊天"):footer=node as Label
	check(footer!=null and footer.text.contains("要站在%s身邊"%npc()),"Dialogue footer names %s (%s)"%[npc(),label])
	if footer!=null:
		var shown:bool=await reach(footer,"dialogue footer "+label)
		check(shown and not_cut(footer),"Dialogue footer readable (%s) %s"%[label,rect_info(footer)])
	await scroll_top()

func events_button_text(stage:int)->String:
	return "關係事件  %d／%d"%[stage,Bond.STAGES.size()]

# ------------------------------------------------------------ gift chooser --

func gift_layout(label:String)->bool:
	var ok:bool=is_instance_valid(app.modal) and control("BondGiftList")!=null
	check(ok,"Gift chooser open: "+label)
	if not ok:return false
	check(find_label("送給%s的禮物"%npc())!=null,"Gift chooser titled 送給%s的禮物 (%s)"%[npc(),label])
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Gift chooser fits viewport: "+label)
	var scroll:=body_scroll()
	if scroll:check(not scroll.get_v_scroll_bar().visible,"Gift chooser fits without scrolling: "+label)
	for node in (app.modal as Node).find_children("*","BaseButton",true,false):
		var b:=node as Control
		if not b.is_visible_in_tree():continue
		check(visible(b) and inside_modal(b),"Button fully visible inside the card: %s (%s) %s"%[b.name,label,rect_info(b)])
		if b is Button:check(button_not_cut(b as Button),"Button caption not cut: %s (%s)"%[b.name,label])
	labels_ok(label)
	return true

## Exactly the held giftable items, liked ones marked, non-held and wood absent.
func gift_list_ok(label:String)->void:
	var list:=control("BondGiftList")
	if list==null:return
	var expected:=PackedStringArray()
	for item:String in Bond.gift_items(rid):
		if held(item)>0:expected.append("BondGift_"+item)
	var names:=PackedStringArray()
	for child in list.get_children():names.append(str(child.name))
	check(names==expected,"Gift list holds exactly the held giftable items (%s): got %s want %s"%[label,", ".join(names),", ".join(expected)])
	check(control("BondGift_wood")==null,"Wood is not offered (%s)"%label)
	for item in ["orange_blossom","chime_herb","carrot"]:
		check(held(item)==0 and control("BondGift_"+item)==null,"Non-held %s is not offered (%s)"%[item,label])
	for item:String in stock():
		if held(item)<1:
			check(control("BondGift_"+item)==null,"Used-up %s is no longer offered (%s)"%[item,label])
			continue
		var b:=control("BondGift_"+item) as Button
		var want:="喜歡・%s ×%d"%[World.NAMES[item],held(item)]
		check(b!=null and b.text==want,"%s reads %s (%s): %s"%[item,want,label,b.text if b else "?"])
	var radish:=control("BondGift_radish") as Button
	check(radish!=null and radish.text=="%s ×%d"%[World.NAMES["radish"],held("radish")],"radish is a plain gift (%s): %s"%[label,radish.text if radish else "?"])

# ------------------------------------------------------------ events modal --

func events_open()->bool:
	return is_instance_valid(app.modal) and find_label("%s的關係事件"%npc())!=null and control("BondSummary")==null

func events_layout(stage:int,label:String)->void:
	var ok:=events_open()
	check(ok,"%s的關係事件 open (%s)"%[npc(),label])
	if not ok:return
	var scroll:=body_scroll()
	var back:=control("BondEventsBack") as Button
	check(back!=null and back.text=="返回居民回憶" and visible(back) and inside_modal(back) and button_not_cut(back),"BondEventsBack reads 「返回居民回憶」 on view (%s)"%label)
	var first_button:Button=null
	var body_root:Node=scroll if scroll!=null else app.modal
	for node in body_root.find_children("*","Button",true,false):
		if (node as Button).is_visible_in_tree():first_button=node as Button;break
	check(first_button!=null and first_button.text=="返回居民回憶","First body button of the events modal is 返回居民回憶 (%s): %s"%[label,first_button.text if first_button else "?"])
	check(find_button("返回島民手帳")==null,"Events modal for %s has no 「返回島民手帳」 (%s)"%[npc(),label])
	var all:=texts()
	check(all.contains(Bond.stage_name(stage)),"Events summary names the stage (%s)"%label)
	if stage>=Bond.STAGES.size():check(all.contains("四階事件都已展開"),"Events summary says 四階事件都已展開 (%s)"%label)
	await event_tabs(rid,stage,label)

# ------------------------------------------------- T066 tabbed events page --
## The 關係事件 page shows one stage at a time: BondEventsBack + BondEventsSummary,
## four toggle tabs BondEventTab_0..3, one BondEventCard and the footer hint.
## HARD rule at every tab: no outer scrolling, every Label/Button fully on view
## inside the modal and not cut; the selected stage's title and lines (or the
## locked 「尚未展開（好感 N）」 line) sit fully inside the card.
const EVENTS_FOOTER:="聊天、送禮和完成委託都會增加好感。好感不會因為沒上線而下降，朋友的進度也不影響你。"

func tab_find_label(text:String)->Label:
	if not is_instance_valid(app.modal):return null
	for node in (app.modal as Node).find_children("*","Label",true,false):
		var l:=node as Label
		if l!=null and l.is_visible_in_tree() and l.text==text:return l
	return null

func tab_not_cut(l:Label)->bool:
	if l==null or l.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	if l.get_visible_line_count()<l.get_line_count():return false
	if l.size.y+0.5<l.get_combined_minimum_size().y:return false
	if l.autowrap_mode==TextServer.AUTOWRAP_OFF or l.clip_text:
		var font:Font=l.get_theme_font("font")
		var font_size:int=l.get_theme_font_size("font_size")
		for part:String in l.text.split("\n"):
			if font.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>l.size.x+1.0:return false
	return true

func tab_button_not_cut(b:Button)->bool:
	if b==null or b.clip_text or b.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	return b.size.x+0.5>=b.get_combined_minimum_size().x and b.size.y+0.5>=b.get_combined_minimum_size().y

## No outer scrolling; every Label/Button on the page fully on view and not cut.
func tab_page_fits(label:String)->void:
	var ok:=is_instance_valid(app.modal)
	check(ok,"Events modal open (%s)"%label)
	if not ok:return
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Events modal fits the viewport (%s)"%label)
	check(str((app.modal as Node).get_meta("life_modal_layout",""))=="community_board","Events modal keeps the community_board layout (%s)"%label)
	var scroll:=control("ModalScroll") as ScrollContainer
	check(scroll!=null and scroll.get_child_count()>0,"Events modal has its ModalScroll body (%s)"%label)
	if scroll==null or scroll.get_child_count()==0:return
	var content:=scroll.get_child(0) as Control
	var need:float=content.get_combined_minimum_size().y
	var bar:=scroll.get_v_scroll_bar()
	print("RESIDENT_BOND_DIAG events-fit %s content=%.0f view=%.0f spare=%.0f"%[label,need,scroll.size.y,scroll.size.y-need])
	check(need<=scroll.size.y+0.5 and not bar.visible and scroll.scroll_vertical==0,"Events page needs no outer scrolling (%s) content=%.0f view=%.0f"%[label,need,scroll.size.y])
	check(tab_find_label(EVENTS_FOOTER)!=null,"Events footer hint shown (%s)"%label)
	for node in (app.modal as Node).find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree():continue
		if c is Label:
			check(visible(c) and inside_modal(c),"Caption fully on view inside the modal: %s (%s)"%[(c as Label).text,label])
			check(tab_not_cut(c as Label),"Caption not cut or ellipsized: %s (%s)"%[(c as Label).text,label])
		elif c is Button:
			check(visible(c) and inside_modal(c),"Button fully on view inside the modal: %s (%s)"%[c.name,label])
			check(tab_button_not_cut(c as Button),"Button caption not cut: %s (%s)"%[c.name,label])

## Tabs reflect the selection; the card holds exactly the selected stage.
func tab_card(resident:String,stage:int,index:int,label:String)->void:
	var card:=control("BondEventCard")
	check(card!=null and visible(card) and inside_modal(card),"BondEventCard fully on view (%s)"%label)
	for i in range(Bond.STAGES.size()):
		var tab:=control("BondEventTab_%d"%i) as Button
		check(tab!=null and tab.toggle_mode and tab.button_pressed==(i==index),"BondEventTab_%d %s (%s)"%[i,"selected" if i==index else "not selected",label])
		if tab==null:continue
		check(not tab.disabled and tab.focus_mode==Control.FOCUS_ALL,"BondEventTab_%d enabled and focusable (%s)"%[i,label])
		check(tab.text.ends_with(str(Bond.STAGES[i])) and tab.text.begins_with("✓" if i<stage else "○"),"BondEventTab_%d reads %s with its marker (%s): %s"%[i,Bond.STAGES[i],label,tab.text])
	var event:Dictionary=Bond.EVENTS[resident][index]
	var wanted:Array=[]
	if index<stage:
		wanted.append("%s・%s"%[str(Bond.STAGES[index]),str(event.title)])
		for t in event.lines:wanted.append(str(t))
	else:wanted.append("%s・尚未展開（好感 %d）"%[str(Bond.STAGES[index]),int(Bond.THRESHOLDS[index])])
	for text:String in wanted:
		var l:=tab_find_label(text)
		check(l!=null and card!=null and card.is_ancestor_of(l),"BondEventCard shows 「%s」 (%s)"%[text,label])
		if l==null or card==null:continue
		check(visible(l) and card.get_global_rect().grow(0.5).encloses(l.get_global_rect()) and tab_not_cut(l),"「%s」 fully readable inside BondEventCard (%s)"%[text,label])
	var shown:=0
	if card!=null:
		for node in card.find_children("*","Label",true,false):
			if (node as Control).is_visible_in_tree():shown+=1
	check(shown==wanted.size(),"BondEventCard holds only stage %d (%s): %d labels, want %d"%[index+1,label,shown,wanted.size()])
	if index>=stage:
		for t in event.lines:check(tab_find_label(str(t))==null,"Locked tab %d hides the lines of 〈%s〉 (%s)"%[index+1,event.title,label])
	for j in range(Bond.STAGES.size()):
		if j==index:continue
		var other:Dictionary=Bond.EVENTS[resident][j]
		check(tab_find_label("%s・%s"%[str(Bond.STAGES[j]),str(other.title)])==null and tab_find_label("%s・尚未展開（好感 %d）"%[str(Bond.STAGES[j]),int(Bond.THRESHOLDS[j])])==null,"Stage %d is not on the page while tab %d is open (%s)"%[j+1,index+1,label])
	var back:=control("BondEventsBack") as Button
	check(back!=null and visible(back) and inside_modal(back),"BondEventsBack on view (%s)"%label)

## Default tab = newest unlocked stage (stage 1 when none); then every tab is
## focused and pressed (emitting `pressed`), and re-checked.
func event_tabs(resident:String,stage:int,label:String)->void:
	var first:=clampi(stage-1,0,Bond.STAGES.size()-1)
	tab_page_fits("default tab %s"%label)
	tab_card(resident,stage,first,"default tab %s"%label)
	for index in range(Bond.STAGES.size()):
		var tab:=control("BondEventTab_%d"%index) as Button
		check(tab!=null,"BondEventTab_%d exists (%s)"%[index,label])
		if tab==null:continue
		tab.grab_focus()
		await create_timer(0.12).timeout
		tab.pressed.emit()
		await settle()
		check(is_instance_valid(tab) and root.gui_get_focus_owner()==tab,"Focus stays on BondEventTab_%d after pressing it (%s)"%[index,label])
		tab_page_fits("tab %d %s"%[index+1,label])
		tab_card(resident,stage,index,"tab %d %s"%[index+1,label])
	for index in range(Bond.STAGES.size()-1):
		var a:=control("BondEventTab_%d"%index)
		var b:=control("BondEventTab_%d"%(index+1))
		check(a!=null and b!=null and a.find_valid_focus_neighbor(SIDE_RIGHT)==b,"Right from BondEventTab_%d reaches the next tab (%s)"%[index,label])

func memories_open()->bool:
	return is_instance_valid(app.modal) and layout_meta()=="community_board" and find_label("居民回憶")!=null and find_button("返回島民手帳")!=null

func memories_button_ok(stage:int,label:String)->void:
	var b:=control("BondEvents_"+rid) as Button
	if stage<1:
		check(b==null,"居民回憶 hides BondEvents_%s at stage 0 (%s)"%[rid,label])
		check(not texts().contains("%s的關係事件"%npc()),"居民回憶 has no 「%s的關係事件」 at stage 0 (%s)"%[npc(),label])
		return
	check(b!=null,"居民回憶 lists BondEvents_%s at stage %d (%s)"%[rid,stage,label])
	if b==null:return
	check(b.text=="%s的關係事件  %d／%d"%[npc(),stage,Bond.STAGES.size()],"BondEvents_%s caption (%s): %s"%[rid,label,b.text])
	var shown:bool=await reach(b,"memories "+label)
	check(shown,"BondEvents_%s fully visible (%s) %s"%[rid,label,rect_info(b)])
	check(button_not_cut(b),"BondEvents_%s caption not cut (%s)"%[rid,label])
	await scroll_top()
	buttons_on_view_ok("memories "+label)
	labels_ok("memories "+label)

## Journal -> ResidentMemories bookmark (real press).
func open_memories(label:String)->bool:
	await close()
	app._journal("xinghe")
	await settle()
	var memories:=control("ResidentMemories") as Button
	check(memories!=null,"Journal offers 居民回憶 (%s)"%label)
	if memories==null:return false
	await reach(memories,"journal "+label)
	if not await press_button(memories,"居民回憶 "+label):return false
	var ok:=memories_open()
	check(ok,"居民回憶 opens (%s)"%label)
	return ok

# --------------------------------------------------------------- flows --

func untouched(label:String)->void:
	var raw:=record()
	check(int(raw.points)==0 and int(raw.talk_day)==-1 and int(raw.gift_day)==-1,"Rejected action leaves 點點's record untouched (%s): %s"%[label,str(raw)])
	check(int(bond().get("points",-1))==0,"Rejected action leaves the snapshot view at 0 (%s)"%label)

## 點點 lives only in star_garden; far away / wrong cell / home region are refused.
func region_separation_flow(label:String)->void:
	rid="diandian"
	check(region_of(rid)==GARDEN_REGION and place()==GARDEN_CELL,"點點 is placed in star_garden at %s (%s): %s %s"%[str(GARDEN_CELL),label,region_of(rid),str(place())])
	check(Bond.present(app.session.snapshot,rid) and Bond.locked_reason(app.session.snapshot,rid).is_empty(),"點點 has no gate (%s)"%label)
	check(World.land(GARDEN_CELL,GARDEN_REGION) and not World.REGIONS.StarGarden.POOL.has_point(GARDEN_CELL),"Her cell is garden land, not the pool (%s)"%label)
	# Same cell numbers in the home region: no 點點 point.
	await stand(home_region(),near(GARDEN_CELL))
	check(focus()!=rid,"No 點點 focus in the home region at 20,21 (%s): %s"%[label,focus()])
	await interact()
	check(not dialogue_open(),"E at 20,21 in the home region opens no 和點點聊聊 (%s)"%label)
	await close()
	clear_toast()
	app.session.perform("resident_talk",GARDEN_CELL,rid)
	await settle()
	check(toast_text().contains("請走到這位居民身邊"),"Talking to 點點 from the home region is rejected (%s): %s"%[label,toast_text()])
	untouched("home region "+label)
	# In the garden but far away (trail arrival point).
	await stand(GARDEN_REGION,FAR_SPOT)
	check(focus()!=rid,"No 點點 focus from the trail arrival point (%s): %s"%[label,focus()])
	await interact()
	check(not dialogue_open(),"E at the trail arrival point opens no 和點點聊聊 (%s)"%label)
	await close()
	clear_toast()
	app.session.perform("resident_talk",GARDEN_CELL,rid)
	await settle()
	check(not toast_text().contains("點點："),"Talking to 點點 from far away is rejected (%s): %s"%[label,toast_text()])
	check(toast_text().contains("靠近一點"),"Far-away talk says 靠近一點 (%s): %s"%[label,toast_text()])
	clear_toast()
	app.session.perform("resident_gift",GARDEN_CELL,rid+":star_mushroom")
	await settle()
	check(held("star_mushroom")==int(stock().star_mushroom),"Far-away gift keeps the star_mushroom (%s): %s"%[label,toast_text()])
	untouched("far away "+label)
	# Next to her, but naming the wrong cell.
	await stand(GARDEN_REGION,near(GARDEN_CELL))
	check(focus()==rid,"Focus is 點點 next to her in star_garden (%s): %s"%[label,focus()])
	clear_toast()
	app.session.perform("resident_talk",WRONG_CELL,rid)
	await settle()
	check(toast_text().contains("請走到這位居民身邊"),"Wrong-cell talk says 請走到這位居民身邊 (%s): %s"%[label,toast_text()])
	untouched("wrong cell "+label)
	# 暖暖 is not reachable from the garden.
	clear_toast()
	var nuan_before:=Bond.record(w.state.players[id],"nuannuan")
	app.session.perform("resident_talk",Bond.SPRING_CELL,"nuannuan")
	await settle()
	note("talk to 暖暖 from star_garden answered: %s (%s)"%[toast_text(),label])
	check(not toast_text().contains("暖暖："),"Talking to 暖暖 from star_garden is rejected (%s): %s"%[label,toast_text()])
	check(Bond.record(w.state.players[id],"nuannuan")==nuan_before,"Rejected garden talk leaves 暖暖's record untouched (%s)"%label)

## Walk-up flow: stage 0 dialogue, talk, gifts, events, 居民回憶.
func main_flow(label:String)->void:
	var cfg:Dictionary=CONFIG[rid]
	var first:String=cfg.first
	var second:String=cfg.second
	if await open_memories("stage 0 %s %s"%[rid,label]):await memories_button_ok(0,"stage 0 %s %s"%[rid,label])
	if not await open_by_interact("stage 0 "+label):return
	await dialogue_layout("stage 0 %s %s"%[rid,label])
	var expected_summary:=Tasks.bond_text(bond())
	check(summary_text()==expected_summary and summary_text()=="好感・尚未認識  0／%d"%int(Bond.THRESHOLDS[0]),"BondSummary shows 尚未認識 0／1 for %s (%s): %s"%[npc(),label,summary_text()])
	var talk:=control("BondTalk") as Button
	check(talk!=null and not talk.disabled and talk.text=="聊聊近況","BondTalk enabled before talking (%s %s)"%[rid,label])
	var gift_button:=control("BondGift") as Button
	check(gift_button!=null and gift_button.text=="送禮物","BondGift reads 送禮物 (%s %s)"%[rid,label])
	var events_button:=control("BondEvents") as Button
	check(events_button!=null and events_button.text==events_button_text(0),"BondEvents shows 0／4 (%s %s)"%[rid,label])
	# Talk.
	var lines:Array=Bond.TALK_LINES[rid]
	var line_text:=str(lines[posmod(today(),lines.size())])
	if not await press("BondTalk"):return
	check(not is_instance_valid(app.modal),"Talking closes the dialogue (%s %s)"%[rid,label])
	check(toast_text().contains(npc()) and toast_text().contains(line_text),"Toast shows %s's talk line (%s): %s"%[npc(),label,toast_text()])
	var raw:=record()
	check(int(raw.points)==Bond.TALK_POINTS and int(raw.talk_day)==today(),"World record: +1 point, talk_day today (%s %s): %s"%[rid,label,str(raw)])
	check(int(bond().get("stage",-1))==1 and int(bond().get("points",-1))==1 and bool(bond().get("talked_today",false)),"Snapshot reaches 認識 with 1 point (%s %s)"%[rid,label])
	if not await open_by_interact("after talk "+label):return
	await dialogue_layout("after talk %s %s"%[rid,label])
	check(summary_text()==Tasks.bond_text(bond()) and summary_text().begins_with("好感・認識"),"BondSummary shows 認識 after talking (%s %s): %s"%[rid,label,summary_text()])
	talk=control("BondTalk") as Button
	check(talk!=null and talk.disabled and talk.text=="今天聊過了","BondTalk disabled as 今天聊過了 (%s %s)"%[rid,label])
	# A second talk the same day through the real Session path adds nothing.
	clear_toast()
	app.session.perform("resident_talk",place(),rid)
	await settle()
	check(int(record().points)==Bond.TALK_POINTS,"Second talk the same day adds no points (%s %s): %s %s"%[rid,label,str(record()),toast_text()])
	if not dialogue_open():
		if not await open_by_interact("after second talk "+label):return
	# Gift chooser.
	if not await press("BondGift"):return
	if not gift_layout("gift %s %s"%[rid,label]):return
	gift_list_ok("gift %s %s"%[rid,label])
	check(not texts().contains("今天已經送過禮物"),"Gift page before gifting has no 今天已經送過禮物 (%s %s)"%[rid,label])
	var gift_back:=find_button("回到%s身邊"%npc())
	if await press_button(gift_back,"回到%s身邊 %s"%[npc(),label]):
		check(dialogue_open(),"「回到%s身邊」 returns to the bond dialogue (%s)"%[npc(),label])
	if not dialogue_open():
		if not await open_by_interact("gift retry "+label):return
	if not await press("BondGift"):return
	var points_before:=int(record().points)
	var others:={}
	for item in stock():
		if item!=first:others[item]=held(item)
	others["radish"]=held("radish");others["wood"]=held("wood")
	var first_before:=held(first)
	if not await press("BondGift_"+first):return
	check(held(first)==first_before-1,"Gift removes exactly one %s (%s %s): %d -> %d"%[first,rid,label,first_before,held(first)])
	for item in others:check(held(item)==int(others[item]),"Gift leaves %s alone (%s %s)"%[item,rid,label])
	raw=record()
	check(int(raw.points)==points_before+Bond.LIKED_POINTS and int(raw.gift_day)==today(),"Liked gift adds %d points, gift_day today (%s %s): %s"%[Bond.LIKED_POINTS,rid,label,str(raw)])
	check(int(bond().get("points",0))==points_before+Bond.LIKED_POINTS and bool(bond().get("gifted_today",false)),"Snapshot shows the liked gift (%s %s)"%[rid,label])
	check(toast_text().contains("很喜歡"),"Toast shows the liked-gift line (%s %s): %s"%[rid,label,toast_text()])
	# Second gift on the same day.
	if not await open_by_interact("second gift "+label):return
	if not await press("BondGift"):return
	if not gift_layout("gift after gifting %s %s"%[rid,label]):return
	gift_list_ok("gift after gifting %s %s"%[rid,label])
	check(texts().contains("今天已經送過禮物"),"Gift page shows 今天已經送過禮物 after the first gift (%s %s)"%[rid,label])
	var points_mid:=int(record().points)
	var second_before:=held(second)
	if not await press("BondGift_"+second):return
	check(held(second)==second_before-1,"Second gift still removes one %s (%s %s)"%[second,rid,label])
	check(int(record().points)==points_mid,"Second gift the same day adds no points (%s %s): %d -> %d"%[rid,label,points_mid,int(record().points)])
	check(toast_text().contains("好感明天再算"),"Toast says 好感明天再算 (%s %s): %s"%[rid,label,toast_text()])
	# The used-up bluebell disappears from the chooser.
	if await open_by_interact("used-up gift "+label):
		if await press("BondGift"):
			if gift_layout("gift after bluebell used up %s %s"%[rid,label]):gift_list_ok("gift after bluebell used up %s %s"%[rid,label])
	# Events from the dialogue.
	if not await open_by_interact("events "+label):return
	var points_now:=int(bond().get("points",0))
	check(summary_text()=="好感・認識  %d／%d"%[points_now,int(Bond.THRESHOLDS[1])],"BondSummary shows points／next after the gifts (%s %s): %s"%[rid,label,summary_text()])
	events_button=control("BondEvents") as Button
	check(events_button!=null and events_button.text==events_button_text(1),"BondEvents shows 1／4 (%s %s)"%[rid,label])
	if await press("BondEvents"):
		await events_layout(1,"stage 1 %s %s"%[rid,label])
		if await press_button(find_button("返回居民回憶"),"返回居民回憶 %s %s"%[rid,label]):
			check(memories_open(),"「返回居民回憶」 opens 居民回憶 (%s %s)"%[rid,label])
			await memories_button_ok(1,"stage 1 %s %s"%[rid,label])
			if control("BondEvents_"+rid)!=null:
				if await press("BondEvents_"+rid):await events_layout(1,"memories stage 1 %s %s"%[rid,label])
	await close()

func max_stage_flow(label:String)->void:
	var person:Dictionary=w.state.players[id]
	var bonds:Dictionary=person.get("bonds",{})
	bonds[rid]={"points":Bond.LIMIT,"talk_day":0,"gift_day":0}  # PRESET stage 4
	person.bonds=bonds
	check(Bond.valid(person.bonds.duplicate(true),float(w.state.time)),"Stage-4 preset is a valid save record (%s)"%rid)
	await refresh()
	check(int(bond().get("stage",0))==Bond.STAGES.size(),"Preset reaches 好友 (%s %s)"%[rid,label])
	if not await open_by_interact("stage 4 "+label):return
	await dialogue_layout("stage 4 %s %s"%[rid,label])
	check(summary_text()=="好感・好友（四階事件都已展開）","BondSummary shows the max-stage text (%s %s): %s"%[rid,label,summary_text()])
	var events_button:=control("BondEvents") as Button
	check(events_button!=null and events_button.text==events_button_text(4),"BondEvents shows 4／4 (%s %s)"%[rid,label])
	if await press("BondEvents"):
		await events_layout(Bond.STAGES.size(),"stage 4 %s %s"%[rid,label])
		if await press_button(find_button("返回居民回憶"),"返回居民回憶 stage 4 %s %s"%[rid,label]):
			check(memories_open(),"「返回居民回憶」 opens 居民回憶 at stage 4 (%s %s)"%[rid,label])
			await memories_button_ok(4,"stage 4 %s %s"%[rid,label])
	await close()

# ---------------------------------------------------------------- run --

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	path=OS.get_environment("TEMP").path_join("bond-garden-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"庭園好感旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.time=float(w.state.time)+Village.DAY*2.0  # PRESET: two whole days later
	check(today()>=2,"World day is past day 1 (talk_day 0 is a past day)")
	check("diandian" in Bond.RESIDENTS and Bond.RESIDENTS.size()==12,"點點 is the twelfth bond resident")
	check(Bond.name_of("diandian")=="點點" and "diandian" in Bond.WALK_UP,"點點 is a walk-up bond resident")
	check(Bond.LOCAL_PLACES.diandian=="星芽庭園映星池西岸","點點's place text")
	check(Bond.GARDEN_CELL==GARDEN_CELL and Bond.GARDEN_REGION==GARDEN_REGION,"Expected garden cell")
	check(Bond.LIKES.diandian==["bluebell","orange_blossom","chime_herb","star_mushroom"],"點點's likes")
	check(Bond.EVENTS.diandian.size()==Bond.STAGES.size(),"點點 has four events")
	check(w.state.regions.has(GARDEN_REGION),"World keeps a star_garden layer")
	for item in ["star_mushroom","bluebell","orange_blossom","chime_herb","radish","wood","carrot"]:check(World.NAMES.has(item),"Item name exists: "+item)
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		var person:Dictionary=w.state.players[id]
		person.erase("bonds")  # PRESET: fresh relationship per size
		rid="diandian"
		stock_bag()
		await region_separation_flow(tag)
		rid="diandian"
		await main_flow(tag)
		await max_stage_flow(tag)
		await stand(home_region(),Vector2(46.5,30.5))
		await close()
		note("size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
