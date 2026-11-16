extends SceneTree
## T066 居民好感 UI test for the two LOCAL residents that are not in Village.NPCS:
## 茶茶 (chacha, 貓空茶園 host page) and 星禾 (xinghe, 蘭陽水圳 canal page).
## Covers the site-page 「BondOpen」 buttons, the bond dialogue (BondSummary /
## BondTalk / BondGift / BondEvents / BondSiteBack), the gift chooser, the
## four-stage events modal and its back buttons, the 星禾 journal page
## 「關係事件」 button and the 居民回憶 BondEvents_chacha / BondEvents_xinghe
## buttons, at 1024×640 and 1280×800. Same harness as test_resident_bond_ui.gd.
## Run with `-- --profile=isolated-regression --village-art-preview` (headless).
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); the real profile is never used;
##  * world time is moved forward by two whole days (time-of-day kept) so that the
##    stage-4 preset's talk_day/gift_day 0 are valid past days;
##  * player.bonds is erased before each viewport size (fresh 尚未認識 state);
##    player.greenhouse_reported is forced false (it would add 星禾 story points);
##  * the backpack is written directly per resident: every item giftable to that
##    resident is set to 0, then the liked gift ×1 (茶茶: tea_leaf, 星禾: sapling),
##    radish ×2 (common gift) and wood ×5 (not giftable);
##  * the player is teleported by writing region/x/y onto the cell returned by
##    World.bond_place (one tile below it); "far" = same region, 12/8 tiles away;
##  * tea record: first absent (no 介紹信 intro), then a FRESH record with
##    intro=true (TeaDiscuss shown) is written to state.tea_ceramics.players;
##  * 蘭陽 canal: first fresh (three route buttons), then a consistent repaired
##    state (three blockages cleared, full donations, repaired=true: four route
##    buttons); restored to LANYANG_LIFE.fresh() afterwards;
##  * stage-4 preset: player.bonds = {chacha/xinghe: points 24, talk_day 0, gift_day 0}.
## REALLY EXERCISED:
##  * site pages are opened with app._tea_host() / app._gardener_menu();
##  * BondOpen, BondTalk, BondGift, BondGift_<item>, 「回到X身邊」, BondEvents,
##    「返回居民回憶」/「返回島民手帳」, BondSiteBack, ResidentMemories and
##    BondEvents_<id> are pressed by emitting `pressed`, i.e. the real
##    Session.perform("resident_talk"/"resident_gift") -> World -> snapshot trip;
##  * the journal is opened with app._journal("xinghe").
## LAYOUT POLICY:
##  * tea host page: fixed tea_height, so no scrolling at all (same rule as
##    test_tea_ceramics_ui inspect_worksite); every Button/Label/TextureRect must
##    be fully visible inside the modal and the actions row must not overflow;
##  * 蘭陽 canal page, bond dialogue, 居民回憶, journal: controls must be fully
##    visible; when one is only reachable by scrolling the body this is printed
##    as a `NOTE RESIDENT_BOND_LOCAL ...` line and checked after scrolling;
##  * gift chooser: no scrolling at all (same rule as test_resident_bond_ui);
##  * events modal (tabbed, one stage per page): NO outer scrolling, on the default
##    tab and after pressing each of the four tabs; every Label/Button fully on
##    view and not cut, the stage's title + lines (or the locked line) inside
##    BondEventCard.
## KNOWN GAP (reported, not asserted): World only checks region + cell argument
## for resident_talk, not the player's distance; the far-away same-region talk is
## printed as a NOTE line with the observed result.
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const LIKED:={"chacha":"tea_leaf","xinghe":"sapling"}
var app
var w
var id:String=""
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
	print("RESIDENT_BOND_LOCAL_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE RESIDENT_BOND_LOCAL "+message)

func visible(c:Control)->bool:
	if c==null or not c.is_visible_in_tree() or not root.get_visible_rect().encloses(c.get_global_rect()):return false
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().encloses(c.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func inside_modal(c:Control)->bool:
	return c!=null and is_instance_valid(app.modal) and (app.modal as Control).get_global_rect().grow(0.5).encloses(c.get_global_rect())

## Like inside_modal, but only for the part a scrolling body actually shows.
func shown_inside_modal(c:Control)->bool:
	if c==null or not is_instance_valid(app.modal):return false
	var rect:=c.get_global_rect()
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer:rect=rect.intersection((parent as Control).get_global_rect())
		parent=parent.get_parent()
	return (app.modal as Control).get_global_rect().grow(0.5).encloses(rect)

## True when an ancestor ScrollContainer clips c entirely.
func scrolled_out(c:Control)->bool:
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().intersects(c.get_global_rect()):return true
		parent=parent.get_parent()
	return false

## No ellipsis, no clipped text, no hidden wrapped lines.
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

## Rects for failure messages.
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
	await settle()

func place(region:String,p:Vector2i)->void:
	var person:Dictionary=w.state.players[id]
	person.region=region
	person.x=p.x+0.5;person.y=p.y+1.5
	await refresh()

func spot(resident:String)->Array:
	return World.bond_place(app.session.snapshot,resident)

func go_to(resident:String)->void:
	var where:Array=spot(resident)
	var cell:Vector2i=where[1]
	await place(str(where[0]),cell)

func inventory()->Dictionary:
	return w.state.players[id].inventory

func held(item:String)->int:
	return int(inventory().get(item,0))

func bond(resident:String)->Dictionary:
	var all:Variant=app.session.snapshot.get("resident_bonds",{})
	if not all is Dictionary:return {}
	var found:Variant=(all as Dictionary).get(resident,{})
	return found if found is Dictionary else {}

## Raw world record (server side), not the snapshot view.
func record(resident:String)->Dictionary:
	return Bond.record(w.state.players[id],resident)

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

## Fully visible inside the modal; if only the body scroll can bring it on view,
## scroll there, print a NOTE and check again. Caller resets the scroll.
func reach(c:Control,label:String)->bool:
	if c==null:return false
	if visible(c) and inside_modal(c):return true
	var scroll:=body_scroll()
	if scroll!=null and scroll.is_ancestor_of(c):
		scroll.ensure_control_visible(c)
		await settle()
		note("%s reachable only after scrolling the modal body (%s)"%[c.name,label])
	return visible(c) and inside_modal(c)

func scroll_top()->void:
	var scroll:=body_scroll()
	if scroll!=null and scroll.scroll_vertical!=0:
		scroll.scroll_vertical=0
		await settle()

func needs_scroll()->bool:
	var scroll:=body_scroll()
	if scroll==null:return false
	var bar:=scroll.get_v_scroll_bar()
	return bar.max_value>bar.page+1.0

## Every visible Label on view sits inside the modal and is not cut.
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

## A button row: inside the modal, within its parent and not wider than itself.
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

func stock_bag(resident:String)->void:
	var inv:Dictionary=inventory()
	for item in inv.keys():
		if Bond.giftable(resident,str(item)):inv[item]=0
	inv[str(LIKED[resident])]=1;inv["radish"]=2;inv["wood"]=5
	app.session._send_snapshot(1)

func tea_intro(on:bool)->void:
	var players:Dictionary=w.state.tea_ceramics.players
	if on:
		var fresh:Dictionary=World.TEA_CERAMICS.FRESH.duplicate(true)
		fresh.intro=true
		players[id]=fresh
	else:players.erase(id)
	await refresh()

func lanyang_repaired(on:bool)->void:
	var life:Dictionary=World.LANYANG_LIFE.fresh()
	if on:
		for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[World.LANYANG_LIFE.key(cell)]=true
		life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate(true)
		life.repaired=true
	w.state.lanyang_life=life
	await refresh()

# ------------------------------------------------------------ site pages --

func site_open(resident:String)->bool:
	if not is_instance_valid(app.modal) or control("BondOpen")==null:return false
	if resident=="chacha":return str((app.modal as Node).get_meta("tea_site",""))=="host"
	return layout_meta()=="lanyang_garden" and str((app.modal as Node).get_meta("garden_mode",""))=="canal"

func open_site(resident:String,label:String)->bool:
	await close()
	if resident=="chacha":app._tea_host()
	else:app._gardener_menu()
	await settle()
	var ok:=site_open(resident)
	check(ok,"Site page for %s opens with BondOpen (%s)"%[resident,label])
	return ok

## Tea host page: fixed height, strict no-scroll rule.
func tea_site_layout(intro:bool,label:String)->void:
	if not await open_site("chacha",label):return
	var modal_rect:=(app.modal as Control).get_global_rect()
	var height:=float((app.modal as Node).get_meta("tea_height",0.0))
	check(root.get_visible_rect().encloses(modal_rect),"Tea host fits the viewport (%s) %s"%[label,str(modal_rect)])
	var scroll:=body_scroll()
	if scroll!=null:
		var bar:=scroll.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Tea host fits without scrolling (%s) tea_height=%.0f content=%.0f page=%.0f modal=%s"%[label,height,bar.max_value,bar.page,str(modal_rect)])
	var names:Array=["BondOpen","TeaJournal"]
	if intro:names.push_front("TeaDiscuss")
	check((control("TeaDiscuss")!=null)==intro,"TeaDiscuss present only with the intro record (%s)"%label)
	for name in names:
		var b:=control(name) as Button
		check(b!=null,"Tea host offers %s (%s)"%[name,label])
		if b==null:continue
		check(visible(b) and inside_modal(b),"%s fully visible inside the tea host page (%s) %s"%[name,label,rect_info(b)])
		check(button_not_cut(b),"%s caption not cut (%s): %s"%[name,label,b.text])
	var open:=control("BondOpen") as Button
	if open!=null:
		check(open.text=="和茶茶聊聊" and not open.disabled,"BondOpen reads 和茶茶聊聊 and is enabled (%s)"%label)
		var journal:=control("TeaJournal")
		check(journal!=null and journal.get_parent()==open.get_parent(),"BondOpen shares the actions row with TeaJournal (%s)"%label)
		row_fits(open.get_parent() as Control,"tea host actions "+label)
	# No pre-existing control is pushed outside the fixed-height page.
	for node in (app.modal as Node).find_children("*","Control",true,false):
		var c:=node as Control
		if not (c is Button or c is Label or c is TextureRect) or not c.is_visible_in_tree():continue
		check(visible(c) and inside_modal(c),"Tea host control fully inside the page: %s (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Tea host caption not cut: %s (%s)"%[(c as Label).text,label])
		elif c is Button:check(button_not_cut(c as Button),"Tea host button not cut: %s (%s)"%[c.name,label])

func lanyang_site_layout(repaired:bool,label:String)->void:
	if not await open_site("xinghe",label):return
	var modal_rect:=(app.modal as Control).get_global_rect()
	check(root.get_visible_rect().encloses(modal_rect),"Canal page fits the viewport (%s) %s"%[label,str(modal_rect)])
	if needs_scroll():note("canal page body scrolls (%s) modal=%s"%[label,str(modal_rect)])
	var open:=control("BondOpen") as Button
	var routes:Array=[open,find_button("看看育苗盤"),find_button("看地圖找水口")]
	var history:=find_button("地方記憶・舊分水板")
	check((history!=null)==repaired,"地方記憶 route present only when repaired (%s)"%label)
	if repaired:routes.append(history)
	check(open!=null and open.text=="和星禾聊聊" and not open.disabled,"BondOpen reads 和星禾聊聊 and is enabled (%s)"%label)
	for target in routes:
		var b:=target as Button
		check(b!=null,"Canal route button exists (%s)"%label)
		if b==null:continue
		check(open!=null and b.get_parent()==open.get_parent(),"%s sits in the routes row (%s)"%[b.text,label])
		var shown:bool=await reach(b,label)
		check(shown,"%s fully visible inside the canal page (%s) %s"%[b.text,label,rect_info(b)])
		check(button_not_cut(b),"%s caption not cut (%s)"%[b.text,label])
	if open!=null:row_fits(open.get_parent() as Control,"canal routes "+label)
	await scroll_top()
	buttons_on_view_ok("canal "+label)
	labels_ok("canal "+label)

# ---------------------------------------------------------- bond dialogue --

func dialogue_open(resident:String)->bool:
	return is_instance_valid(app.modal) and layout_meta()=="community_board" and control("BondSiteBack")!=null and find_label("和%s聊聊"%Bond.name_of(resident))!=null

func summary_text()->String:
	var summary:=control("BondSummary") as Label
	return summary.text if summary!=null else ""

func open_dialogue_from_site(resident:String,label:String)->bool:
	if not await open_site(resident,label):return false
	if not await press("BondOpen"):return false
	var ok:=dialogue_open(resident)
	check(ok,"BondOpen opens 和%s聊聊 (%s)"%[Bond.name_of(resident),label])
	return ok

func open_dialogue_direct(resident:String,label:String)->bool:
	await close()
	app._resident_bond_menu(resident)
	await settle()
	var ok:=dialogue_open(resident)
	check(ok,"app._resident_bond_menu opens 和%s聊聊 (%s)"%[Bond.name_of(resident),label])
	return ok

func dialogue_layout(resident:String,label:String)->void:
	if not dialogue_open(resident):return
	var npc:=Bond.name_of(resident)
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Bond dialogue fits the viewport (%s)"%label)
	if needs_scroll():note("bond dialogue body scrolls (%s)"%label)
	var all:=texts()
	check(all.contains("%s・%s"%[npc,str(Bond.LOCAL_PLACES[resident])]),"Dialogue shows the place line (%s)"%label)
	check(all.contains("%s喜歡：%s"%[npc,str(Bond.LIKE_TEXT[resident])]),"Dialogue shows the like line (%s)"%label)
	var title:=find_label("和%s聊聊"%npc)
	check(title!=null and visible(title) and not_cut(title),"Dialogue title readable (%s)"%label)
	for name in ["BondSummary","BondTalk","BondGift","BondEvents","BondSiteBack"]:
		var c:=control(name)
		check(c!=null,"%s exists for %s (%s)"%[name,resident,label])
		if c==null:continue
		var shown:bool=await reach(c,label)
		check(shown,"%s fully visible inside the dialogue (%s) %s"%[name,label,rect_info(c)])
		if c is Button:check(button_not_cut(c as Button),"%s caption not cut (%s)"%[name,label])
		elif c is Label:check(not_cut(c as Label),"%s not cut (%s)"%[name,label])
	await scroll_top()
	var back:=control("BondSiteBack") as Button
	check(back!=null and back.text==("回到茶園" if resident=="chacha" else "回到水圳手記"),"BondSiteBack caption (%s): %s"%[label,back.text if back else "?"])
	buttons_on_view_ok("dialogue "+label)
	labels_ok("dialogue "+label)

func events_button_text(stage:int)->String:
	return "關係事件  %d／%d"%[stage,Bond.STAGES.size()]

# ------------------------------------------------------------ gift chooser --

func gift_layout(label:String)->bool:
	var ok:bool=is_instance_valid(app.modal) and control("BondGiftList")!=null
	check(ok,"Gift chooser open: "+label)
	if not ok:return false
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

# ------------------------------------------------------------ events modal --

func back_text(resident:String)->String:
	return "返回居民回憶" if resident=="chacha" else "返回島民手帳"

func events_open(resident:String)->bool:
	return is_instance_valid(app.modal) and find_label("%s的關係事件"%Bond.name_of(resident))!=null

func events_layout(resident:String,stage:int,label:String)->void:
	var ok:=events_open(resident)
	check(ok,"%s的關係事件 open (%s)"%[Bond.name_of(resident),label])
	if not ok:return
	var back:=control("BondEventsBack") as Button
	check(back!=null and back.text==back_text(resident) and visible(back) and inside_modal(back) and button_not_cut(back),"BondEventsBack reads 「%s」 on view (%s)"%[back_text(resident),label])
	var other:="返回島民手帳" if resident=="chacha" else "返回居民回憶"
	check(find_button(other)==null,"Events modal for %s has no 「%s」 (%s)"%[resident,other,label])
	var all:=texts()
	var stage_word:String=str(Bond.STAGES[stage-1]) if stage>0 else "尚未認識"
	check(all.contains(stage_word),"Events summary names the stage (%s)"%label)
	if stage>=Bond.STAGES.size():check(all.contains("四階事件都已展開"),"Events summary says 四階事件都已展開 (%s)"%label)
	await event_tabs(resident,stage,label)

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

func journal_xinghe_open()->bool:
	if not is_instance_valid(app.modal) or layout_meta()!="resident_journal":return false
	var bookmark:=control("XingheBookmark") as Button
	return bookmark!=null and bookmark.button_pressed and control("BondEvents")!=null

## Press the events modal's back button and check where it lands.
func events_back(resident:String,label:String)->void:
	if not await press_button(find_button(back_text(resident)),back_text(resident)+" "+label):return
	if resident=="chacha":
		check(memories_open() and control("BondEvents_chacha")!=null,"「返回居民回憶」 opens 居民回憶 listing 茶茶 (%s)"%label)
	else:
		check(journal_xinghe_open(),"「返回島民手帳」 returns to 星禾's journal page (%s)"%label)

# ------------------------------------------------------------ journal side --

func open_journal_xinghe(label:String)->bool:
	await close()
	app._journal("xinghe")
	await settle()
	var ok:=journal_xinghe_open()
	check(ok,"島民手冊 opens on 星禾 with BondEvents (%s)"%label)
	return ok

func journal_flow(stage:int,label:String)->void:
	if not await open_journal_xinghe(label):return
	var events:=control("BondEvents") as Button
	check(events.text.contains("%d／%d"%[stage,Bond.STAGES.size()]),"Journal BondEvents shows %d／4 (%s): %s"%[stage,label,events.text])
	var shown:bool=await reach(events,"journal "+label)
	check(shown,"Journal BondEvents fully visible (%s) %s"%[label,rect_info(events)])
	check(button_not_cut(events),"Journal BondEvents caption not cut (%s)"%label)
	if not await press_button(events,"journal BondEvents "+label):return
	await events_layout("xinghe",stage,"journal stage %d %s"%[stage,label])
	await events_back("xinghe","journal "+label)
	await close()

func open_memories(label:String)->bool:
	if not await open_journal_xinghe("memories "+label):return false
	var memories:=control("ResidentMemories") as Button
	check(memories!=null,"Journal offers 居民回憶 (%s)"%label)
	if memories==null:return false
	var shown:bool=await reach(memories,"journal "+label)
	check(shown,"居民回憶 bookmark visible (%s)"%label)
	if not await press_button(memories,"居民回憶 "+label):return false
	var ok:=memories_open()
	check(ok,"居民回憶 opens (%s)"%label)
	return ok

## 居民回憶 lists BondEvents_<id> only for residents at stage >= 1.
func memories_flow(label:String)->void:
	if not await open_memories(label):return
	for resident:String in ["chacha","xinghe"]:
		var stage:=int(bond(resident).get("stage",0))
		var b:=control("BondEvents_"+resident) as Button
		if stage<1:
			check(b==null,"居民回憶 hides BondEvents_%s at stage 0 (%s)"%[resident,label])
			continue
		check(b!=null,"居民回憶 lists BondEvents_%s at stage %d (%s)"%[resident,stage,label])
		if b==null:continue
		check(b.text=="%s的關係事件  %d／%d"%[Bond.name_of(resident),stage,Bond.STAGES.size()],"BondEvents_%s caption (%s): %s"%[resident,label,b.text])
		var shown:bool=await reach(b,"memories "+label)
		check(shown,"BondEvents_%s fully visible (%s) %s"%[resident,label,rect_info(b)])
		check(button_not_cut(b),"BondEvents_%s caption not cut (%s)"%[resident,label])
		await scroll_top()
	buttons_on_view_ok("memories "+label)
	labels_ok("memories "+label)
	for resident:String in ["chacha","xinghe"]:
		var stage:=int(bond(resident).get("stage",0))
		if stage<1:continue
		if not memories_open():
			if not await open_memories(label):return
		if not await press("BondEvents_"+resident):continue
		await events_layout(resident,stage,"memories %s %s"%[resident,label])
		await events_back(resident,"memories "+label)
	await close()

# --------------------------------------------------------------- flows --

## Talking / site back from the home region: the server rejects, state unchanged.
func home_negative_flow(label:String)->void:
	await place(World.REGIONS.HOME,Village.NPCS["aru"].cell)
	for resident:String in ["chacha","xinghe"]:
		if not await open_dialogue_direct(resident,"home "+label):continue
		check(summary_text().contains("尚未認識"),"%s starts at 尚未認識 (%s): %s"%[resident,label,summary_text()])
		if not await press("BondTalk"):continue
		# 目標格離玩家超過 3.2 格時，World 的一般距離檢查會先回「靠近一點」。
		check(toast_text().contains("請走到這位居民身邊") or toast_text().contains("靠近一點"),"Talk from home is rejected for %s (%s): %s"%[resident,label,toast_text()])
		var raw:=record(resident)
		check(int(raw.points)==0 and int(raw.talk_day)==-1,"Rejected talk leaves %s's world record untouched (%s)"%[resident,label])
		check(int(bond(resident).get("points",-1))==0 and not bool(bond(resident).get("talked_today",true)),"Rejected talk leaves %s's snapshot at 0 (%s)"%[resident,label])
	# BondSiteBack away from the site: 茶茶 -> tea host page, 星禾 -> journal page.
	if await open_dialogue_direct("chacha","home site back "+label):
		if await press("BondSiteBack"):check(site_open("chacha"),"「回到茶園」 opens the tea host page from home (%s)"%label)
	if await open_dialogue_direct("xinghe","home site back "+label):
		if await press("BondSiteBack"):check(journal_xinghe_open(),"「回到水圳手記」 falls back to 星禾's journal page outside 蘭陽 (%s)"%label)
	await close()

func resident_flow(resident:String,label:String)->void:
	var npc:=Bond.name_of(resident)
	var liked:=str(LIKED[resident])
	var tag:="%s %s"%[resident,label]
	stock_bag(resident)
	await go_to(resident)
	# 1. Site page layout (both page variants).
	if resident=="chacha":
		await tea_intro(false)
		await tea_site_layout(false,"no intro "+tag)
		await tea_intro(true)
		await tea_site_layout(true,"intro "+tag)
	else:
		await lanyang_repaired(true)
		await lanyang_site_layout(true,"repaired "+tag)
		await lanyang_repaired(false)
		await lanyang_site_layout(false,"fresh "+tag)
	# 2. BondOpen -> dialogue at stage 0.
	if not await open_dialogue_from_site(resident,tag):return
	await dialogue_layout(resident,"before talk "+tag)
	check(summary_text()=="好感・尚未認識  0／1","BondSummary shows stage 0 (%s): %s"%[tag,summary_text()])
	var talk:=control("BondTalk") as Button
	check(talk!=null and not talk.disabled and talk.text=="聊聊近況","BondTalk enabled before talking (%s)"%tag)
	var events_button:=control("BondEvents") as Button
	check(events_button!=null and events_button.text==events_button_text(0),"BondEvents shows 0／4 (%s)"%tag)
	# 3. Talk through the real button.
	var lines:Array=Bond.TALK_LINES[resident]
	var line_text:=str(lines[posmod(today(),lines.size())])
	if not await press("BondTalk"):return
	check(not is_instance_valid(app.modal),"Talking closes the dialogue (%s)"%tag)
	check(toast_text().contains(npc) and toast_text().contains(line_text),"Toast shows %s's talk line (%s): %s"%[npc,tag,toast_text()])
	var raw:=record(resident)
	check(int(raw.points)==1 and int(raw.talk_day)==today(),"World record: 1 point, talk_day today (%s): %s"%[tag,str(raw)])
	check(int(bond(resident).get("stage",-1))==1 and int(bond(resident).get("points",-1))==1 and bool(bond(resident).get("talked_today",false)),"Snapshot reaches 認識 with 1 point (%s)"%tag)
	if not await open_dialogue_from_site(resident,"after talk "+tag):return
	await dialogue_layout(resident,"after talk "+tag)
	check(summary_text().begins_with("好感・認識"),"BondSummary shows 認識 after talking (%s): %s"%[tag,summary_text()])
	talk=control("BondTalk") as Button
	check(talk!=null and talk.disabled and talk.text=="今天聊過了","BondTalk disabled as 今天聊過了 (%s)"%tag)
	# 4. Gift chooser.
	if not await press("BondGift"):return
	if not gift_layout("gift "+tag):return
	check(find_label("送給%s的禮物"%npc)!=null,"Gift chooser titled 送給%s的禮物 (%s)"%[npc,tag])
	var list:=control("BondGiftList")
	var names:=PackedStringArray()
	for child in list.get_children():names.append(str(child.name))
	check(names.size()==2 and names.has("BondGift_"+liked) and names.has("BondGift_radish"),"Gift list holds exactly %s + radish (%s): %s"%[liked,tag,", ".join(names)])
	check(control("BondGift_wood")==null,"Wood is not offered (%s)"%tag)
	var liked_button:=control("BondGift_"+liked) as Button
	var radish:=control("BondGift_radish") as Button
	check(liked_button!=null and liked_button.text.begins_with("喜歡・") and liked_button.text.ends_with("×1"),"%s marked 喜歡・ ×1 (%s): %s"%[liked,tag,liked_button.text if liked_button else "?"])
	check(radish!=null and not radish.text.begins_with("喜歡・") and radish.text.ends_with("×2"),"radish is a plain gift ×2 (%s): %s"%[tag,radish.text if radish else "?"])
	var gift_back:=find_button("回到%s身邊"%npc)
	if await press_button(gift_back,"回到%s身邊 %s"%[npc,tag]):
		check(dialogue_open(resident),"「回到%s身邊」 returns to the bond dialogue (%s)"%[npc,tag])
	if not dialogue_open(resident):
		if not await open_dialogue_direct(resident,tag):return
	if not await press("BondGift"):return
	var points_before:=int(record(resident).points)
	if not await press("BondGift_"+liked):return
	check(held(liked)==0,"Gift removes exactly one %s (%s)"%[liked,tag])
	check(held("radish")==2 and held("wood")==5,"Gift leaves radish and wood alone (%s)"%tag)
	raw=record(resident)
	check(int(raw.points)==points_before+Bond.LIKED_POINTS and int(raw.gift_day)==today(),"Liked gift adds %d points, gift_day today (%s): %s"%[Bond.LIKED_POINTS,tag,str(raw)])
	check(int(bond(resident).get("points",0))==points_before+Bond.LIKED_POINTS and bool(bond(resident).get("gifted_today",false)),"Snapshot shows the liked gift (%s)"%tag)
	check(toast_text().contains("很喜歡"),"Toast shows the liked-gift line (%s): %s"%[tag,toast_text()])
	# 5. Events from the dialogue.
	if not await open_dialogue_from_site(resident,"after gift "+tag):return
	var points_now:=int(bond(resident).get("points",0))
	check(summary_text()=="好感・認識  %d／%d"%[points_now,int(Bond.THRESHOLDS[1])],"BondSummary shows points／next after the gift (%s): %s"%[tag,summary_text()])
	events_button=control("BondEvents") as Button
	check(events_button!=null and events_button.text==events_button_text(1),"BondEvents shows 1／4 (%s)"%tag)
	if await press("BondEvents"):
		await events_layout(resident,1,"dialogue "+tag)
		await events_back(resident,"dialogue "+tag)
	# 6. BondSiteBack reopens the site page.
	if await open_dialogue_from_site(resident,"site back "+tag):
		if await press("BondSiteBack"):
			check(site_open(resident),"BondSiteBack reopens the site page with BondOpen (%s)"%tag)
	await close()

## Same region, far away: printed, not asserted (see KNOWN GAP in the header).
func far_note(label:String)->void:
	var person:Dictionary=w.state.players[id]
	person.erase("bonds")  # PRESET: talk not used yet today
	var where:Array=spot("chacha")
	var cell:Vector2i=where[1]
	await place(str(where[0]),cell+Vector2i(12,8))
	if not await open_dialogue_direct("chacha","far "+label):return
	if not await press("BondTalk"):return
	var raw:=record("chacha")
	var accepted:=int(raw.points)>0
	note("far same-region talk for chacha (%s): accepted=%s points=%d toast=%s"%[label,str(accepted),int(raw.points),toast_text()])
	await close()

func max_stage_flow(label:String)->void:
	var person:Dictionary=w.state.players[id]
	person.bonds={"chacha":{"points":24,"talk_day":0,"gift_day":0},"xinghe":{"points":24,"talk_day":0,"gift_day":0}}  # PRESET stage 4
	check(Bond.valid(person.bonds.duplicate(true),float(w.state.time)),"Stage-4 preset is a valid save record")
	await go_to("chacha")
	for resident:String in ["chacha","xinghe"]:
		check(int(bond(resident).get("stage",0))==Bond.STAGES.size(),"Preset reaches 好友 for %s (%s)"%[resident,label])
		if not await open_dialogue_direct(resident,"stage 4 "+label):continue
		await dialogue_layout(resident,"stage 4 %s %s"%[resident,label])
		check(summary_text()=="好感・好友（四階事件都已展開）","BondSummary shows the max-stage text for %s (%s): %s"%[resident,label,summary_text()])
		var talk:=control("BondTalk") as Button
		check(talk!=null and not talk.disabled,"Stage-4 preset can still talk today (%s)"%label)
		var events_button:=control("BondEvents") as Button
		check(events_button!=null and events_button.text==events_button_text(4),"BondEvents shows 4／4 (%s)"%label)
		if await press("BondEvents"):
			await events_layout(resident,Bond.STAGES.size(),"stage 4 %s %s"%[resident,label])
			await events_back(resident,"stage 4 "+label)
	await journal_flow(Bond.STAGES.size(),"stage 4 "+label)
	await memories_flow("stage 4 "+label)

# ---------------------------------------------------------------- run --

func run()->void:
	create_timer(170.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 170 s")
		finish())
	path=OS.get_environment("TEMP").path_join("bond-local-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"地方好感旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.time=float(w.state.time)+Village.DAY*2.0  # PRESET: two whole days later
	check(today()>=2,"World day is past day 1 (talk_day 0 is a past day)")
	var chacha_spot:Array=World.bond_place(app.session.snapshot,"chacha")
	var xinghe_spot:Array=World.bond_place(app.session.snapshot,"xinghe")
	check(str(chacha_spot[0])=="maokong" and chacha_spot[1]==World.TEA_CERAMICS.TEA_NPC,"茶茶 lives at the tea host cell in 貓空")
	check(str(xinghe_spot[0])=="lanyang" and xinghe_spot[1]==World.LANYANG_LIFE.SERVICE,"星禾 lives at the canal service cell in 蘭陽")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		var person:Dictionary=w.state.players[id]
		person.erase("bonds")  # PRESET: fresh relationship per size
		if bool(person.get("greenhouse_reported",false)):person.greenhouse_reported=false
		await lanyang_repaired(false)
		await tea_intro(false)
		check(int(bond("chacha").get("points",-1))==0 and int(bond("xinghe").get("points",-1))==0,"Both local residents start at 0 points (%s)"%tag)
		await memories_flow("stage 0 "+tag)
		await journal_flow(0,"stage 0 "+tag)
		await home_negative_flow(tag)
		await resident_flow("chacha",tag)
		await resident_flow("xinghe",tag)
		await journal_flow(1,"stage 1 "+tag)
		await memories_flow("stage 1 "+tag)
		await far_note(tag)
		await max_stage_flow(tag)
		await close()
	await lanyang_repaired(false)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
