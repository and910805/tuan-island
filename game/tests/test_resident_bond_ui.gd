extends SceneTree
## T066 居民好感 UI test: resident dialogue bond controls (BondSummary / BondTalk /
## BondGift), the gift chooser, the 島民手冊 「關係事件」 button and the four-stage
## events modal, at 1024×640 and 1280×800. Same harness as test_mine_hoist_ui.gd.
## Run with `-- --profile=isolated-regression --village-art-preview` (headless).
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); the real profile is never used;
##  * world time is moved forward by two whole days (time-of-day kept) so that the
##    stage-4 preset's talk_day/gift_day 0 are valid past days;
##  * picnic / board flags are NOT set; aru/milu/xiaoli/bobo stories stay at 0;
##  * player.bonds is erased before each viewport size (fresh 尚未認識 state);
##  * the backpack is written directly: every giftable item already held is set
##    to 0, then tea_light 1 (阿榆 likes it), radish 2 (common gift), wood 5
##    (not giftable);
##  * the player is teleported next to 阿榆 / 米露 / 小栗 (home) and next to
##    波波 (jinguashi, Village.resident_cell) by writing region/x/y;
##  * stage-4 preset: player.bonds = {"aru":{"points":24,"talk_day":0,"gift_day":0}};
##  * sweep preset: player.bonds = every Bond.RESIDENTS id at 24 points, then erased;
##    the sweep opens each events page with a DIRECT Tasks.bond_events(app,id) call
##    and presses all four BondEventTab_i by emitting `pressed`.
## REALLY EXERCISED:
##  * 阿榆's dialogue is opened through app._interact() next to him (fallback:
##    app._resident_menu("aru"), reported as a failed check);
##  * BondTalk, BondGift, BondGift_tea_light, BondGift_radish, the gift modal's
##    「回到阿榆身邊」, BondEvents and 「返回島民手帳」 are pressed by emitting
##    `pressed`, i.e. the real Session.perform("resident_talk"/"resident_gift")
##    -> World -> snapshot round trip;
##  * the journal is opened with app._journal("aru").
## LAYOUT POLICY:
##  * resident dialogue: the bond controls and 「交付這段委託」/「打開島民手冊」 must
##    be fully visible with the body scroll at the top (no scrolling allowed);
##  * gift chooser: no scrolling at all (same rule as test_mine_hoist_ui fits());
##  * events modal (tabbed, one stage per page): NO outer scrolling at stage 1 and
##    stage 4, on the default tab and after pressing each of the four tabs; every
##    Label/Button fully on view and not cut, the stage's title + lines (or the
##    locked line) inside BondEventCard; content/view heights printed as
##    RESIDENT_BOND_DIAG events-fit lines;
##  * journal: BondEvents must be fully visible after scrolling it into view;
##    whether outer scrolling was needed is printed as a RESIDENT_BOND_DIAG line.
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
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
	print("RESIDENT_BOND_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

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

func settle()->void:
	for i in range(6):await process_frame
	app._layout_preview();await process_frame

func refresh()->void:
	app.session._send_snapshot(1)
	await settle()

func place(region:String,p:Vector2i)->void:
	var person:Dictionary=w.state.players[id]
	person.region=region
	person.x=p.x-0.5;person.y=p.y+0.5
	await refresh()

func inventory()->Dictionary:
	return w.state.players[id].inventory

func held(item:String)->int:
	return int(inventory().get(item,0))

func bond(resident:String)->Dictionary:
	var all:Variant=app.session.snapshot.get("resident_bonds",{})
	if not all is Dictionary:return {}
	var found:Variant=(all as Dictionary).get(resident,{})
	return found if found is Dictionary else {}

func today()->int:
	return Bond.day(float(w.state.time))

func clear_toast()->void:
	if app.toast==null or not is_instance_valid(app.toast):return
	var toast_label:Label=app.toast
	toast_label.text=""

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
	await create_timer(0.12).timeout
	b.pressed.emit()
	await settle()
	return true

func toast_text()->String:
	if app.toast==null or not is_instance_valid(app.toast):return ""
	return str((app.toast as Label).text)

# ------------------------------------------------------------- layouts --

## Every visible Label on view sits inside the card and is not cut.
func labels_ok(label:String)->void:
	for node in (app.modal as Node).find_children("*","Label",true,false):
		var l:=node as Label
		if not l.is_visible_in_tree() or scrolled_out(l):continue
		check(shown_inside_modal(l),"Caption inside the card: %s (%s)"%[l.text,label])
		check(not_cut(l),"Caption not cut or ellipsized: %s (%s)"%[l.text,label])

## Resident dialogue: no scrolling allowed for the bond and quest controls.
## 小栗's dialogue also carries the chapter-letter card and already needed body
## scrolling before the bond controls existed (content 286 > view 214). There the
## controls only have to be reachable by scrolling; this is a known layout gap.
func dialogue_reachable(resident:String,label:String)->void:
	var ok:bool=is_instance_valid(app.modal) and layout_meta()=="resident_dialogue"
	check(ok,"Resident dialogue open: "+label)
	if not ok:return
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Dialogue fits viewport: "+label)
	var scroll:=body_scroll()
	if scroll!=null:print("RESIDENT_BOND_DIAG dialogue %s scrollbar=%s (scrolling allowed)"%[label,str(scroll.get_v_scroll_bar().visible)])
	var targets:Array=[control("BondSummary"),control("BondTalk"),control("BondGift"),find_button("交付這段委託"),find_button("打開島民手冊")]
	for target in targets:
		var c:=target as Control
		check(c!=null,"Dialogue control exists for %s (%s)"%[resident,label])
		if c==null:continue
		if scroll!=null:
			scroll.ensure_control_visible(c)
			await settle()
		check(visible(c) and inside_modal(c),"%s reachable by scrolling (%s)"%[c.name,label])
		if c is Button:check(button_not_cut(c as Button),"%s caption not cut (%s)"%[c.name,label])
		elif c is Label:check(not_cut(c as Label),"%s not cut (%s)"%[c.name,label])
	if scroll!=null:
		scroll.scroll_vertical=0
		await settle()

func dialogue_layout(resident:String,label:String)->bool:
	var ok:bool=is_instance_valid(app.modal) and layout_meta()=="resident_dialogue"
	check(ok,"Resident dialogue open: "+label)
	if not ok:return false
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Dialogue fits viewport: "+label)
	var scroll:=body_scroll()
	if scroll!=null:
		var content:Control=null
		if scroll.get_child_count()>0:content=scroll.get_child(0) as Control
		var content_height:float=content.size.y if content!=null else -1.0
		print("RESIDENT_BOND_DIAG dialogue %s scrollbar=%s content=%.0f view=%.0f"%[label,str(scroll.get_v_scroll_bar().visible),content_height,scroll.size.y])
		check(scroll.scroll_vertical==0,"Dialogue body starts at the top: "+label)
	for name in ["BondSummary","BondTalk","BondGift"]:
		var c:=control(name)
		check(c!=null,"%s exists for %s (%s)"%[name,resident,label])
		check(c!=null and visible(c) and inside_modal(c),"%s fully visible inside the dialogue without scrolling (%s)"%[name,label])
	var summary:=control("BondSummary") as Label
	check(summary!=null and not_cut(summary),"BondSummary not cut (%s)"%label)
	for name in ["BondTalk","BondGift"]:
		check(button_not_cut(control(name) as Button),"%s caption not cut (%s)"%[name,label])
	for prefix in ["交付這段委託","打開島民手冊"]:
		var b:=find_button(prefix)
		check(b!=null,"Dialogue still offers 「%s」 (%s)"%[prefix,label])
		check(b!=null and visible(b) and inside_modal(b),"「%s」 fully visible without scrolling (%s)"%[prefix,label])
		check(button_not_cut(b),"「%s」 caption not cut (%s)"%[prefix,label])
	for node in (app.modal as Node).find_children("*","BaseButton",true,false):
		var b:=node as Control
		if not b.is_visible_in_tree() or scrolled_out(b):continue
		check(shown_inside_modal(b),"Button on view stays inside the dialogue: %s (%s)"%[b.name,label])
	labels_ok(label)
	return true

## Gift chooser: same strict rule as test_mine_hoist_ui fits().
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
		check(visible(b) and inside_modal(b),"Button fully visible inside the card: %s (%s)"%[b.name,label])
		if b is Button:check(button_not_cut(b as Button),"Button caption not cut: %s (%s)"%[b.name,label])
	labels_ok(label)
	return true

## Events modal (tabbed): no outer scrolling at any tab; see event_tabs().
func events_layout(stage:int,label:String)->void:
	var back:=control("BondEventsBack") as Button
	check(back!=null and back.text=="返回島民手帳" and visible(back) and inside_modal(back),"BondEventsBack reads 「返回島民手帳」 on view (%s)"%label)
	check(find_button("返回居民回憶")==null,"阿榆's events page has no 「返回居民回憶」 (%s)"%label)
	var summary:=control("BondEventsSummary") as Label
	check(summary!=null and summary.text==Tasks.bond_text(bond("aru")),"Events summary shows the bond line (%s): %s"%[label,summary.text if summary else "?"])
	await event_tabs("aru",stage,label)

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

# --------------------------------------------------------------- flows --

func dialogue_open()->bool:
	return is_instance_valid(app.modal) and layout_meta()=="resident_dialogue" and control("BondSummary")!=null

func open_dialogue(resident:String)->bool:
	app._resident_menu(resident)
	await settle()
	var ok:=dialogue_open()
	check(ok,"Resident dialogue for %s opens with bond controls"%resident)
	return ok

func summary_text()->String:
	var summary:=control("BondSummary") as Label
	return summary.text if summary!=null else ""

func stock_bag()->void:
	var inv:Dictionary=inventory()
	for item in inv.keys():
		if Bond.giftable("aru",str(item)):inv[item]=0
	inv["tea_light"]=1;inv["radish"]=2;inv["wood"]=5
	app.session._send_snapshot(1)

func aru_flow(tag:String)->void:
	var home:String=World.REGIONS.HOME
	await place(home,Village.NPCS["aru"].cell)
	# 2. Real interact path next to 阿榆.
	app._interact()
	await settle()
	check(dialogue_open() and texts().contains("阿榆的島上日常"),"Interact next to 阿榆 opens his dialogue at "+tag)
	if not dialogue_open():
		if not await open_dialogue("aru"):return
	if not dialogue_layout("aru","aru before talk "+tag):return
	check(summary_text().contains("尚未認識"),"BondSummary shows 尚未認識 before talking at %s: %s"%[tag,summary_text()])
	var talk:=control("BondTalk") as Button
	check(talk!=null and not talk.disabled and talk.text=="聊聊近況","BondTalk enabled before talking at "+tag)
	var gift:=control("BondGift") as Button
	check(gift!=null and not gift.disabled,"BondGift present and enabled at "+tag)
	# 3. Talk through the real button.
	var line_text:String=str(Bond.TALK_LINES["aru"][posmod(today(),Bond.TALK_LINES["aru"].size())])
	if not await press("BondTalk"):return
	check(not is_instance_valid(app.modal),"Talking closes the dialogue at "+tag)
	check(toast_text().contains(line_text),"Toast shows 阿榆's talk line at %s: %s"%[tag,toast_text()])
	check(int(bond("aru").get("stage",-1))==1 and int(bond("aru").get("points",-1))==1,"Snapshot bond reaches 認識 with 1 point at "+tag)
	check(bool(bond("aru").get("talked_today",false)),"Snapshot marks talked_today at "+tag)
	if not await open_dialogue("aru"):return
	dialogue_layout("aru","aru after talk "+tag)
	check(summary_text().begins_with("好感・認識"),"BondSummary shows stage 認識 after talking at %s: %s"%[tag,summary_text()])
	talk=control("BondTalk") as Button
	check(talk!=null and talk.disabled and talk.text=="今天聊過了","BondTalk disabled as 今天聊過了 at "+tag)
	# 4. Gift chooser through the real button.
	if not await press("BondGift"):return
	if not gift_layout("gift first "+tag):return
	var list:=control("BondGiftList")
	var names:=PackedStringArray()
	for child in list.get_children():names.append(str(child.name))
	check(names.size()==2 and names.has("BondGift_tea_light") and names.has("BondGift_radish"),"Gift list holds exactly tea_light + radish at %s: %s"%[tag,", ".join(names)])
	check(control("BondGift_wood")==null,"Wood is not offered as a gift at "+tag)
	var tea:=control("BondGift_tea_light") as Button
	var radish:=control("BondGift_radish") as Button
	check(tea!=null and tea.text.begins_with("喜歡・") and tea.text.ends_with("×1"),"tea_light marked 喜歡・ ×1 at %s: %s"%[tag,tea.text if tea else "?"])
	check(radish!=null and not radish.text.begins_with("喜歡・") and radish.text.ends_with("×2"),"radish is a plain gift ×2 at %s: %s"%[tag,radish.text if radish else "?"])
	check(texts().contains("每天第一份禮物"),"Gift chooser explains the daily first gift at "+tag)
	var points_before:=int(bond("aru").get("points",0))
	var radish_before:=held("radish")
	if not await press("BondGift_tea_light"):return
	check(held("tea_light")==0,"Gift removes exactly one tea_light at "+tag)
	check(held("radish")==radish_before and held("wood")==5,"Gift leaves radish and wood alone at "+tag)
	check(int(bond("aru").get("points",0))==points_before+Bond.LIKED_POINTS,"Liked gift adds %d points at %s"%[Bond.LIKED_POINTS,tag])
	check(bool(bond("aru").get("gifted_today",false)),"Snapshot marks gifted_today at "+tag)
	check(toast_text().contains("很喜歡"),"Toast shows the liked-gift line at %s: %s"%[tag,toast_text()])
	# Reopen: second gift of the day.
	if not await open_dialogue("aru"):return
	if not await press("BondGift"):return
	if not gift_layout("gift second "+tag):return
	check(texts().contains("今天已經送過禮物"),"Gift chooser shows 今天已經送過禮物 at "+tag)
	check(control("BondGift_tea_light")==null,"tea_light no longer offered once given at "+tag)
	# The chooser's back button returns to 阿榆.
	if await press_button(find_button("回到阿榆身邊"),"回到阿榆身邊 "+tag):
		check(dialogue_open(),"「回到阿榆身邊」 reopens the dialogue at "+tag)
	if not dialogue_open():
		if not await open_dialogue("aru"):return
	if not await press("BondGift"):return
	var points_after_first:=int(bond("aru").get("points",0))
	if not await press("BondGift_radish"):return
	check(held("radish")==radish_before-1,"Second gift removes exactly one radish at "+tag)
	check(int(bond("aru").get("points",0))==points_after_first,"Second gift of the day leaves points unchanged at "+tag)
	check(toast_text().contains("好感明天再算"),"Toast explains the repeat gift at %s: %s"%[tag,toast_text()])
	# Reopened dialogue after talk + gifts.
	if not await open_dialogue("aru"):return
	dialogue_layout("aru","aru after talk+gift "+tag)
	check(summary_text()=="好感・認識  %d／%d"%[points_after_first,int(Bond.THRESHOLDS[1])],"BondSummary shows points／next at %s: %s"%[tag,summary_text()])
	app._close_modal();await settle()

## 5./6. Journal button + events modal at the current stage.
func journal_flow(stage:int,tag:String)->void:
	app._journal("aru")
	await settle()
	check(layout_meta()=="resident_journal","島民手冊 opens on 阿榆 (%s)"%tag)
	var events:=control("BondEvents") as Button
	check(events!=null,"Journal offers BondEvents (%s)"%tag)
	if events==null:return
	check(events.text.contains("%d／%d"%[stage,Bond.STAGES.size()]),"BondEvents shows %d／4 (%s): %s"%[stage,tag,events.text])
	var scroll:=body_scroll()
	var needed_scroll:=not visible(events)
	if scroll!=null and needed_scroll:
		scroll.ensure_control_visible(events)
		await settle()
	print("RESIDENT_BOND_DIAG journal %s BondEvents_needs_outer_scroll=%s"%[tag,str(needed_scroll)])
	check(visible(events) and inside_modal(events) and button_not_cut(events),"BondEvents fully visible in the journal (%s)"%tag)
	if not await press_button(events,"BondEvents "+tag):return
	var opened:bool=is_instance_valid(app.modal) and texts().contains("阿榆的關係事件")
	check(opened,"BondEvents opens 阿榆的關係事件 (%s)"%tag)
	if not opened:return
	await events_layout(stage,"events stage %d %s"%[stage,tag])
	if not await press_button(find_button("返回島民手帳"),"返回島民手帳 "+tag):return
	check(layout_meta()=="resident_journal" and control("BondEvents")!=null,"「返回島民手帳」 returns to the journal (%s)"%tag)
	app._close_modal();await settle()

func max_stage_flow(tag:String)->void:
	var person:Dictionary=w.state.players[id]
	person.bonds={"aru":{"points":24,"talk_day":0,"gift_day":0}}  # PRESET stage 4
	check(Bond.valid(person.bonds.duplicate(true),float(w.state.time)),"Stage-4 preset is a valid save record")
	await place(World.REGIONS.HOME,Village.NPCS["aru"].cell)
	check(int(bond("aru").get("stage",0))==Bond.STAGES.size(),"Preset reaches 好友 at "+tag)
	if await open_dialogue("aru"):
		dialogue_layout("aru","aru stage 4 "+tag)
		check(summary_text()=="好感・好友（四階事件都已展開）","BondSummary shows the max-stage text at %s: %s"%[tag,summary_text()])
		var talk:=control("BondTalk") as Button
		check(talk!=null and not talk.disabled,"Stage-4 preset can still talk today at "+tag)
		app._close_modal();await settle()
	await journal_flow(Bond.STAGES.size(),"stage 4 "+tag)

## 8. Tabbed events page for all twelve residents at stage 4 (every tab pressed),
## plus 阿榆's stage-0 page (all four tabs locked). The page is opened with a
## DIRECT call Tasks.bond_events(app,id) (the per-resident suites cover the real
## entry buttons); the back button's label is checked per resident.
func all_residents_flow(tag:String)->void:
	var person:Dictionary=w.state.players[id]
	var preset:={}
	for resident:String in Bond.RESIDENTS:preset[resident]={"points":Bond.LIMIT,"talk_day":0,"gift_day":0}
	person.bonds=preset  # PRESET stage 4 for all twelve
	check(Bond.valid(person.bonds.duplicate(true),float(w.state.time)),"Twelve-resident stage-4 preset is a valid save record")
	await refresh()
	check(Bond.RESIDENTS.size()==12,"Twelve residents have relationship events")
	for resident:String in Bond.RESIDENTS:
		check(int(bond(resident).get("stage",0))==Bond.STAGES.size(),"%s reaches 好友 in the snapshot (%s)"%[resident,tag])
		Tasks.bond_events(app,resident)
		await settle()
		check(is_instance_valid(app.modal) and find_label("%s的關係事件"%Bond.name_of(resident))!=null,"%s的關係事件 opens (%s)"%[Bond.name_of(resident),tag])
		var back:=control("BondEventsBack") as Button
		var want:="返回居民回憶" if resident=="chacha" or resident in Bond.WALK_UP else "返回島民手帳"
		check(back!=null and back.text==want,"%s's BondEventsBack reads 「%s」 (%s): %s"%[resident,want,tag,back.text if back else "?"])
		await event_tabs(resident,Bond.STAGES.size(),"sweep %s stage 4 %s"%[resident,tag])
		app._close_modal();await settle()
	person.erase("bonds")  # PRESET: no relationship at all
	await refresh()
	check(int(bond("aru").get("stage",-1))==0,"阿榆 back at stage 0 (%s)"%tag)
	Tasks.bond_events(app,"aru")
	await settle()
	await event_tabs("aru",0,"sweep aru stage 0 "+tag)
	# Optional third parameter opens a given tab directly.
	Tasks.bond_events(app,"aru",2)
	await settle()
	tab_card("aru",0,2,"aru opened on tab 3 "+tag)
	app._close_modal();await settle()

## 7. Other residents keep the controls inside their dialogue.
func others_flow(tag:String)->void:
	for resident in ["milu","xiaoli"]:
		await place(World.REGIONS.HOME,Village.NPCS[resident].cell)
		if await open_dialogue(resident):
			if resident=="xiaoli":await dialogue_reachable(resident,"%s %s"%[resident,tag])
			else:dialogue_layout(resident,"%s %s"%[resident,tag])
			check(summary_text().contains("尚未認識"),"%s starts at 尚未認識 at %s"%[resident,tag])
		app._close_modal();await settle()
	# 波波 lives in 金瓜石: stand on the cell Village.resident_cell reports.
	await place("jinguashi",Village.NPCS["bobo"].cell)
	var cell:Vector2i=Village.resident_cell(app.session.snapshot,"bobo")
	await place("jinguashi",cell)
	if await open_dialogue("bobo"):
		dialogue_layout("bobo","bobo "+tag)
	app._close_modal();await settle()
	await place(World.REGIONS.HOME,Village.NPCS["aru"].cell)

# ---------------------------------------------------------------- run --

func run()->void:
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	path=OS.get_environment("TEMP").path_join("bond-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"好感旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.time=float(w.state.time)+Village.DAY*2.0  # PRESET: two whole days later
	check(today()>=2,"World day is past day 1 (talk_day 0 is a past day)")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		var person:Dictionary=w.state.players[id]
		person.erase("bonds")  # PRESET: fresh relationship per size
		stock_bag()            # PRESET backpack
		await aru_flow(tag)
		app._close_modal();await settle()
		await journal_flow(1,"stage 1 "+tag)
		await max_stage_flow(tag)
		await others_flow(tag)
		await all_residents_flow(tag)
		await scaled_dialogues(tag)
		await controller_dialogue(tag)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()

func scaled_dialogues(tag:String)->void:
	for scale_index in app.TEXT_SCALE_FACTORS.size():
		app.sound.preferred_text_scale=scale_index
		app._apply_font_scale_tree()
		for resident in ["aru","milu","bobo"]:
			app._close_modal()
			await settle()
			if await open_dialogue(resident):
				await dialogue_layout(resident,"%s scale %d %s"%[resident,scale_index,tag])
	app._close_modal()
	app.sound.preferred_text_scale=1
	app._apply_font_scale_tree()
	await settle()

func tap_controller(button:JoyButton)->void:
	var event:=InputEventJoypadButton.new()
	event.button_index=button
	event.pressed=true
	root.push_input(event,true)
	var release:=event.duplicate() as InputEventJoypadButton
	release.pressed=false
	root.push_input(release,true)
	await settle()

func controller_dialogue(tag:String)->void:
	app.sound.preferred_text_scale=3
	app._apply_font_scale_tree()
	stock_bag()
	await place(World.REGIONS.HOME,Village.NPCS.aru.cell)
	app.controller_navigation=true
	if await open_dialogue("aru"):
		var focus:=root.gui_get_focus_owner() as Button
		check(focus!=null and focus.text.begins_with("交付這段委託"),"Controller starts on the quest action "+tag)
		var found_journal:=false
		for step in 4:
			await tap_controller(JOY_BUTTON_DPAD_RIGHT)
			focus=root.gui_get_focus_owner() as Button
			if focus!=null and focus.text.begins_with("打開島民手冊"):found_journal=true
			if focus==control("BondGift"):break
		check(found_journal and focus!=null and focus==control("BondGift"),"D-pad reaches the journal and gift action "+tag)
		if focus!=null and focus==control("BondGift"):
			await tap_controller(JOY_BUTTON_A)
			var list:=control("BondGiftList")
			focus=root.gui_get_focus_owner() as Button
			check(list!=null and focus!=null and list.is_ancestor_of(focus),"A opens the gifts and focuses an item "+tag)
			if list!=null and focus!=null and list.is_ancestor_of(focus):
				var item:=str(focus.name).trim_prefix("BondGift_")
				var before:=int(inventory().get(item,0))
				await tap_controller(JOY_BUTTON_A)
				check(int(inventory().get(item,0))==before-1,"A sends exactly one gift "+tag)
		app._close_modal()
		if await open_dialogue("aru"):
			await tap_controller(JOY_BUTTON_B)
			check(not is_instance_valid(app.modal),"B returns to the island "+tag)
	app.controller_navigation=false
	app.sound.preferred_text_scale=1
	app._apply_font_scale_tree()
	await settle()
