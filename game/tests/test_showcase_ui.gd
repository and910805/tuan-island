extends SceneTree
## T071 家園布置題 UI test (headless) at 1024×640 and 1280×800. Same harness as
## test_fishing_meet_ui.gd / test_harvest_relay_ui.gd: real Session host, real
## snapshot round trips.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true
##    is set here (the runner passes no flag for this suite);
##  * state.board=true and state.picnic written directly (false for the locked checks);
##  * state.showcase / harvest_relay / fish_meet and every player's records of them are
##    erased before each size (fresh activities, no cooldown);
##  * the local player is teleported by writing region/x/y; my facing is set directly
##    on world_view (facings + interpolation snapped to the new position) instead of
##    walking a step — the plot target follows that facing like in play;
##  * teammates are fake online players: World.add_player + a fake session.peers entry
##    (as the sibling suites), positioned by writing x/y; their join / place actions
##    are sent with World.act (they are other people). The 8-participant page uses
##    seven such fake players;
##  * world clock: to time out a round state.time is set past `ends` and the normal
##    World.step(1.0) tick settles it; the cooldown is skipped by setting state.time
##    past `ready`; session rate buckets are cleared between my own actions;
##  * the paused page writes a lamp object onto plot cell (28,45) directly;
##  * my joins of 豐收接力 / 河岸釣魚會 (tracker priority) are sent with World.act after
##    teleporting next to their signs (those pages are tested by their own suites);
##  * after the first pick, later prop choices are made by pressing the palette button
##    of the page (same code path), or written to world_view.showcase_kind where noted.
## REALLY EXERCISED (local player):
##  * KEY_E through root.push_input -> main._unhandled_input -> _interact: at the sign
##    opens the page; on plot tiles places / removes pieces (server state + prompts);
##  * left clicks on plot tiles through root.push_input (place / far rejection);
##  * Esc closes; KEY_UP / KEY_DOWN / KEY_RIGHT focus navigation through push_input;
##  * 開始一場 / 完成展示 / 離開活動 / palette / 島民招呼 pressed by emitting `pressed`
##    after grabbing focus (real Session.perform -> World -> snapshot -> page refresh);
##  * the entries on 渡口派對 · 風鈴接力 (activity page), the 公告板 and the HUD tracker.
## NOT COVERED HERE: world pixels (see test_showcase_scene.gd).
const World=preload("res://scripts/world.gd")
const Show=preload("res://scripts/showcase.gd")
const Relay=preload("res://scripts/harvest_relay.gd")
const Meet=preload("res://scripts/fishing_meet.gd")
const ShowUI=preload("res://scripts/showcase_ui.gd")
const FRIENDS:=["小麥","阿豆","青青","米果","小柚","阿蔥","土豆"]
const SIGN_SPOT:=Vector2(25.5,45.5)   # west of the sign: 1.0 away, no plot cell within 1.6
const FAR_SPOT:=Vector2(29.5,48.5)    # 4.2 from the sign
const PLOT_SPOT:=Vector2(29.5,46.5)   # plot cell (29,46)
const FRIEND_SPOTS:=[Vector2(27.5,45.5),Vector2(27.5,44.5),Vector2(27.5,46.5),Vector2(28.5,44.5),Vector2(28.5,47.5),Vector2(26.5,47.5),Vector2(25.5,44.5)]
const AWAY:=Vector2(46.5,36.5)
var app
var w
var id:String=""
var path:String=""
var checks:=0
var failures:=0
var finished:=false
var friends:Array[String]=[]
var peer_seq:=900

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("SHOWCASE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE SHOWCASE_UI "+message)

# ------------------------------------------------------------------ helpers --

func control(name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(name,true,false) as Control

func button(name:String)->Button:
	return control(name) as Button

func label_text(name:String)->String:
	var l:=control(name) as Label
	return l.text if l!=null else ""

func page_open()->bool:
	return is_instance_valid(app.modal) and str((app.modal as Node).get_meta("life_modal_layout",""))=="showcase"

func texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

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

func rect_info(c:Control)->String:
	var modal_rect:="none"
	if is_instance_valid(app.modal):modal_rect=str((app.modal as Control).get_global_rect())
	return "modal=%s control=%s"%[modal_rect,str(c.get_global_rect()) if c!=null else "null"]

func settle()->void:
	for i in range(6):await process_frame
	app._layout_preview();await process_frame

func refresh()->void:
	app.session._send_snapshot(1)
	if app.view!=null and app.view.has_method("_process"):app.view._process(0.0)
	app._refresh_hud()
	await settle()

func own()->Dictionary:
	return ShowUI.own(app.session.snapshot)

func person()->Dictionary:
	return w.state.players[id]

func toast()->String:
	return str((app.toast as Label).text) if app.toast!=null and is_instance_valid(app.toast) else ""

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func focus()->String:
	return str(app.view.interaction_focus())

func stand(at:Vector2)->void:
	var p:Dictionary=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	await refresh()

## PRESET: my facing, with the walk interpolation snapped to the new position.
func face(dir:Vector2i)->void:
	var v=app.view
	var me:String=app.session.own_id  # world_view keys players by their public id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	v.stride_stop.erase(me)
	v.facings[me]=dir
	await settle()

func key(code:Key)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		root.push_input(e)
	await settle()

## The interact key in the world (rate bucket cleared first).
func interact_key()->void:
	app.session.rates[1].clear()
	await key(KEY_E)
	await refresh()

## Left click on a world cell, as test_fishing_input.gd does.
func click(cell:Vector2i)->void:
	app.action_clock=0
	app.session.rates[1].clear()
	var point:Vector2=app.view.screen(Vector2(cell)+Vector2(0.5,0.5))*app.view.view_zoom()
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	event.position=point
	event.global_position=point
	root.push_input(event,true)
	event=event.duplicate()
	event.pressed=false
	root.push_input(event,true)
	await process_frame
	await refresh()

func press(name:String,label:String,stay_open:=true)->bool:
	var b:=control(name) as BaseButton
	check(b!=null and not b.disabled,"Enabled %s (%s)"%[name,label])
	if b==null or b.disabled:return false
	app.session.rates[1].clear()
	b.grab_focus()  # as a keyboard/controller press would
	await create_timer(0.05).timeout
	b.pressed.emit()
	await settle()
	if stay_open:check(page_open(),"Page stays open after %s (%s)"%[name,label])
	return true

func disabled_with_reason(name:String,label:String,contains:String="")->void:
	var b:=button(name)
	check(b!=null and b.disabled and not b.tooltip_text.is_empty() and (contains.is_empty() or b.tooltip_text.contains(contains)),"%s disabled with a reason (%s): %s"%[name,label,b.tooltip_text if b else "missing"])

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

func world_label(id_value:String)->Dictionary:
	app.view.queue_redraw()
	await process_frame
	await process_frame
	for entry in app.view.world_labels:
		if str(entry.id)==id_value:return entry
	return {}

func piece(cell:Vector2i)->String:
	var pieces:Dictionary=w.state.get("showcase",{}).get("pieces",{})
	return str(pieces.get(Show.cell_key(cell),{}).get("kind",""))

## Choose a prop on the page palette (opened programmatically, closed with Esc).
func choose(kind:String,label:String)->void:
	app._showcase_menu()
	await settle()
	await press("ShowcaseKind_"+kind,label)
	check(str(app.view.showcase_kind)==kind,"Palette selects %s (%s)"%[kind,label])
	await key(KEY_ESCAPE)

## Prompt and real KEY_E on the targeted plot cell.
func key_on_plot(cell:Vector2i,expect_prompt:String,label:String)->void:
	check(ShowUI.view_target(app.view)==cell,"Plot target is %s (%s): %s"%[str(cell),label,str(ShowUI.view_target(app.view))])
	check(focus()==ShowUI.PLOT_POINT,"Plot focus (%s): %s"%[label,focus()])
	var prompt:=await world_label(ShowUI.PLOT_POINT)
	check(str(prompt.get("title",""))==expect_prompt,"Prompt 「%s」 (%s): %s"%[expect_prompt,label,str(prompt.get("title","none"))])
	await interact_key()
	check(not page_open(),"E on the plot does not open a page (%s)"%label)

# ------------------------------------------------------------------- layout --

func layout_ok(label:String)->void:
	if not page_open():
		check(false,"Page open for layout: "+label)
		return
	var modal:Control=app.modal
	var view_rect:=root.get_visible_rect()
	check(view_rect.encloses(modal.get_global_rect()),"Page fits the viewport (%s) %s"%[label,rect_info(null)])
	var outer:=control("ModalScroll") as ScrollContainer
	if outer!=null:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Outer page needs no scrolling (%s) max=%.0f page=%.0f"%[label,bar.max_value,bar.page])
	var names:=["ShowcaseStatus","ShowcaseProgress","ShowcaseTime","ShowcaseRule","ShowcaseThemeTitle","ShowcaseBlurb","ShowcaseSelected","ShowcaseBagNote","ShowcasePeopleCount","ShowcasePeople","ShowcaseStart","ShowcaseJoin","ShowcaseLeave","ShowcaseFinish","ShowcaseEmote","ShowcaseHint","ShowcaseLastTitle","ShowcaseLast","ShowcaseRecord","ShowcaseTicketRule"]
	for category:String in Show.CATEGORIES:names.append("ShowcaseCheck_"+category)
	for kind:String in Show.KIND_ORDER:names.append("ShowcaseKind_"+kind)
	for name in names:
		var c:=control(name)
		check(c!=null and c.is_visible_in_tree(),"%s present (%s)"%[name,label])
		if c==null:continue
		check(view_rect.encloses(c.get_global_rect()) and modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside viewport and page (%s) %s"%[name,label,rect_info(c)])
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect):continue
		check(view_rect.encloses(c.get_global_rect()),"%s inside the viewport (%s) %s"%[c.name,label,rect_info(c)])
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the page (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not texts().contains("…"),"No ellipsis anywhere in the page (%s)"%label)
	for name in ["ShowcaseHeader","ShowcaseColumns","ShowcaseActions","ShowcaseBottom"]:
		var row:=control(name)
		if row!=null:check(row.get_combined_minimum_size().x<=row.size.x+0.5,"%s does not overflow (%s)"%[name,label])
	var all:=texts()
	check(all.contains("1～8 人") and all.contains("10 分鐘") and all.contains("不進背包") and all.contains(ShowUI.TICKET_RULE) and all.contains("沒有人會被淘汰"),"Rule, backpack note, no-elimination and ticket rule shown (%s)"%label)

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and not (owner as BaseButton).disabled,"Keyboard focus is on an enabled button inside the page (%s): %s"%[label,str(owner.name) if owner else "none"])

func focused_name()->String:
	var owner:=root.gui_get_focus_owner()
	return str(owner.name) if owner!=null else "none"

## An entry page gains no outer scrolling from the new entry (overflow with the entry
## equals the overflow with the entry removed) and every entry caption stays whole.
func page_fits(label:String)->void:
	if not is_instance_valid(app.modal):
		check(false,"Page open: "+label)
		return
	var modal:Control=app.modal
	check(root.get_visible_rect().encloses(modal.get_global_rect()),"Entry page fits the viewport (%s)"%label)
	var outer:=control("ModalScroll") as ScrollContainer
	var entry:=button("ShowcaseEntry")
	if outer!=null and entry!=null:
		var bar:=outer.get_v_scroll_bar()
		var with_entry:=maxf(0.0,bar.max_value-bar.page)
		var parent:=entry.get_parent()
		var index:=entry.get_index()
		parent.remove_child(entry)
		await settle()
		var without:=maxf(0.0,bar.max_value-bar.page)
		parent.add_child(entry)
		parent.move_child(entry,index)
		await settle()
		note("%s outer overflow with entry %.0f px, without %.0f px (delta %.0f)"%[label,with_entry,without,with_entry-without])
		check(with_entry<=without+1.0,"The 家園布置題 entry adds no outer scrolling (%s): %.0f vs %.0f"%[label,with_entry,without])
	if entry!=null:
		check(modal.get_global_rect().grow(0.5).encloses(entry.get_global_rect()) and button_not_cut(entry),"家園布置題 entry whole inside the page (%s)"%label)
		for other in ["HarvestRelayEntry","HarvestRelayBoardEntry","FishingMeetEntry"]:
			var b:=button(other)
			if b!=null:check(button_not_cut(b) and modal.get_global_rect().grow(0.5).encloses(b.get_global_rect()),"%s caption still whole (%s)"%[other,label])

## Entry button on the current page: present, captioned, opens the page.
func entry_opens(page:String,label:String,locked:bool)->void:
	var entry:=button("ShowcaseEntry")
	var expect_text:="家園布置題・渡口野餐後開放" if locked else "家園布置題（渡口西南草地）"
	check(entry!=null and entry.text==expect_text,"%s lists 家園布置題%s (%s): %s"%[page,"（鎖定）" if locked else "",label,entry.text if entry else "missing"])
	if entry==null:return
	await page_fits(page+" "+label)
	entry=button("ShowcaseEntry")
	entry.pressed.emit()
	await settle()
	check(page_open(),"%s entry opens the 家園布置題 page (%s)"%[page,label])
	if locked:
		check(label_text("ShowcaseLocked")==Show.LOCKED and control("ShowcaseStart")==null,"Locked page from %s shows the lock (%s): %s"%[page,label,label_text("ShowcaseLocked")])
		check(label_text("ShowcaseRule")==ShowUI.RULE,"Locked page explains the activity (%s)"%label)

# ------------------------------------------------------------------- fixture --

func reset_activity()->void:
	for field in ["showcase","harvest_relay","fish_meet"]:w.state.erase(field)  # PRESET fresh activities
	for token in w.state.players:
		for field in ["showcase","harvest_relay","fish_meet","fishing"]:(w.state.players[token] as Dictionary).erase(field)
	for cell:Vector2i in Show.cells():w.state.objects.erase(Show.cell_key(cell))
	app.view.showcase_kind=ShowUI.DEFAULT_KIND

func set_picnic(on:bool)->void:
	w.state.board=true  # PRESET
	w.state.picnic=on   # PRESET
	await refresh()

## PRESET: a fake online player (other person) standing at `at`.
func friend(index:int,at:Vector2)->String:
	var token:="showcase-friend-%d"%index
	if not w.state.players.has(token):
		w.add_player(token,FRIENDS[index])
		peer_seq+=1
		app.session.peers[peer_seq]=token
		friends.append(token)
	var p:Dictionary=w.state.players[token]
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	return token

func world_act(token:String,action:String,p:Vector2i,extra:String="")->Dictionary:
	var result:Dictionary=w.act(token,"ui-%d"%Time.get_ticks_usec(),action,p,extra)
	await refresh()
	return result

func tracker_heading()->String:
	var heading:=app.hud.find_child("TrackerHeading",true,false) as Button
	return heading.text if heading!=null else ""

# --------------------------------------------------------------------- flows --

func locked_flow(label:String)->void:
	await close_page()
	reset_activity()
	await set_picnic(false)
	check(not ShowUI.sign_shown(app.session.snapshot) and not ShowUI.plot_shown(app.session.snapshot) and not bool(own().get("unlocked",true)),"Locked before the picnic (%s)"%label)
	await stand(SIGN_SPOT)
	check(focus()!=ShowUI.POINT,"No 家園布置題 focus at the sign spot before the picnic (%s): %s"%[label,focus()])
	check((await world_label(ShowUI.POINT)).is_empty(),"No 家園布置題 world label before the picnic (%s)"%label)
	await interact_key()
	check(not page_open(),"E at the sign spot before the picnic opens no 家園布置題 (%s)"%label)
	await close_page()
	app._festival_menu()
	await settle()
	await entry_opens("風鈴接力活動頁",label,true)
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the locked page (%s)"%label)
	app._board()
	await settle()
	await entry_opens("公告板",label,true)
	await close_page()

func main_flow(label:String)->void:
	await set_picnic(true)
	check(ShowUI.on_field(app.session.snapshot) and ShowUI.sign_shown(app.session.snapshot) and bool(own().get("available",false)),"Activity available after the picnic (%s)"%label)
	check(own().get("sign")==Show.SIGN and own().get("plot_rect")==Show.PLOT,"own_showcase reports the server's cells (%s)"%label)
	app._festival_menu()
	await settle()
	await entry_opens("風鈴接力活動頁",label,false)
	await close_page()
	app._board()
	await settle()
	await entry_opens("公告板",label,false)
	await close_page()
	# Unfocused sign label from 4 tiles away.
	await stand(FAR_SPOT)
	var idle_label:=await world_label(ShowUI.POINT)
	check(str(idle_label.get("title",""))=="家園布置題","Sign world label 「家園布置題」 (%s): %s"%[label,str(idle_label)])
	check(focus()!=ShowUI.PLOT_POINT,"No plot prompt before joining (%s): %s"%[label,focus()])
	# Interact key at the sign opens the page.
	await stand(SIGN_SPOT)
	check(focus()==ShowUI.POINT,"Standing west of the sign focuses it (%s): %s"%[label,focus()])
	var focused_label:=await world_label(ShowUI.POINT)
	check(str(focused_label.get("title",""))=="家園布置題・打開活動","Focused sign prompt says it opens the activity (%s): %s"%[label,str(focused_label)])
	await interact_key()
	check(page_open(),"Interact at the sign opens 家園布置題 (%s) texts=%s"%[label,texts().left(60).replace("\n"," | ")])
	if not page_open():return
	check(not app._world_keyboard_allowed(),"World keys blocked while the page is open (%s)"%label)
	focus_ok("idle "+label)
	check(focused_name()=="ShowcaseStart","開始一場 focused first (%s): %s"%[label,focused_name()])
	layout_ok("idle "+label)
	check(label_text("ShowcaseStatus")=="目前沒有進行中的一輪" and label_text("ShowcaseTime")=="可以開始","Idle status (%s): %s / %s"%[label,label_text("ShowcaseStatus"),label_text("ShowcaseTime")])
	check(label_text("ShowcaseThemeTitle")=="下一輪主題「花園茶會」" and label_text("ShowcaseBlurb")==str(Show.THEMES.garden_tea.blurb),"Idle page names the next theme (%s): %s"%[label,label_text("ShowcaseThemeTitle")])
	check(label_text("ShowcaseCheck_flower")=="花草 0／4" and label_text("ShowcaseCheck_seat")=="座位 0／3" and label_text("ShowcaseCheck_light")=="燈飾 0／1","Idle checklist (%s): %s"%[label,label_text("ShowcaseCheck_flower")])
	check(label_text("ShowcaseLast")=="還沒有完成的一輪" and label_text("ShowcaseLastTitle").contains("上一輪"),"No previous round yet (%s)"%label)
	disabled_with_reason("ShowcaseJoin",label)
	disabled_with_reason("ShowcaseLeave",label)
	disabled_with_reason("ShowcaseFinish",label,"沒有進行中")
	check(button("ShowcaseEmote")!=null and not button("ShowcaseEmote").disabled,"島民招呼 always enabled (%s)"%label)
	# Focus grid: actions row is last; up walks the palette rows, then 關閉.
	await key(KEY_UP)
	check(focused_name()=="ShowcaseKind_lantern","KEY_UP from 開始一場 reaches the 燈飾 row (%s): %s"%[label,focused_name()])
	await key(KEY_UP)
	check(focused_name()=="ShowcaseKind_stool","KEY_UP reaches the 座位 row (%s): %s"%[label,focused_name()])
	await key(KEY_UP)
	check(focused_name()=="ShowcaseKind_flower_pot","KEY_UP reaches the 花草 row (%s): %s"%[label,focused_name()])
	await key(KEY_UP)
	var up:=root.gui_get_focus_owner() as Button
	check(up!=null and up.text.contains("關閉"),"KEY_UP from the first row reaches 關閉 (%s): %s"%[label,up.text if up else "none"])
	await key(KEY_DOWN)
	check(focused_name()=="ShowcaseKind_flower_pot","KEY_DOWN from 關閉 returns to the palette (%s): %s"%[label,focused_name()])
	await key(KEY_RIGHT)
	check(focused_name()=="ShowcaseKind_flower_box","KEY_RIGHT moves along the 花草 row (%s): %s"%[label,focused_name()])
	await key(KEY_DOWN)
	check(focused_name()=="ShowcaseKind_bench","KEY_DOWN keeps the column (%s): %s"%[label,focused_name()])
	await key(KEY_DOWN)
	check(focused_name()=="ShowcaseKind_string_lights","KEY_DOWN reaches 小串燈 (%s): %s"%[label,focused_name()])
	await key(KEY_DOWN)
	check(focused_name()=="ShowcaseEmote","KEY_DOWN reaches the action bar (%s): %s"%[label,focused_name()])
	await key(KEY_RIGHT)
	check(focused_name()=="ShowcaseStart","KEY_RIGHT wraps along enabled actions (%s): %s"%[label,focused_name()])
	check(button("ShowcaseJoin").focus_mode==Control.FOCUS_NONE,"Disabled 加入 is skipped by focus navigation (%s)"%label)
	# Selecting a prop on the palette (client-local; nothing sent).
	var seq_before:=int(app.session.counter)
	await press("ShowcaseKind_lantern",label)
	check(str(app.view.showcase_kind)=="lantern" and int(app.session.counter)==seq_before,"Palette selects 紙燈籠 without a server action (%s)"%label)
	check(button("ShowcaseKind_lantern")!=null and button("ShowcaseKind_lantern").button_pressed and not button("ShowcaseKind_flower_pot").button_pressed,"Selected prop shown pressed (%s)"%label)
	check(label_text("ShowcaseSelected").contains("紙燈籠"),"Selected prop named on the page (%s): %s"%[label,label_text("ShowcaseSelected")])
	check(focused_name()=="ShowcaseKind_lantern","Focus stays on the chosen prop after the rebuild (%s): %s"%[label,focused_name()])
	var bag_before:Dictionary=(person().inventory as Dictionary).duplicate(true)
	var coins_before:=int(person().coins)
	# 開始一場.
	if not await press("ShowcaseStart",label):return
	var round_id:=int(own().get("round",0))
	check(bool(own().active) and bool(own().joined) and round_id==1,"開始一場 starts and joins round 1 (%s): %s"%[label,str(own().get("round"))])
	check(feedback().contains("家園布置題開始"),"Server reply shown in the page (%s): %s"%[label,feedback()])
	check(label_text("ShowcaseStatus")=="第 1 輪進行中" and label_text("ShowcaseTime")=="剩 600 秒","Active status and time (%s): %s %s"%[label,label_text("ShowcaseStatus"),label_text("ShowcaseTime")])
	check(label_text("ShowcaseThemeTitle")=="本輪主題「花園茶會」","Active theme title (%s): %s"%[label,label_text("ShowcaseThemeTitle")])
	disabled_with_reason("ShowcaseStart",label,"加入")
	disabled_with_reason("ShowcaseFinish",label,"主題還沒完成")
	check(button("ShowcaseLeave")!=null and not button("ShowcaseLeave").disabled,"離開活動 enabled once joined (%s)"%label)
	check(label_text("ShowcaseHint").contains("完成展示要先達成主題") and label_text("ShowcaseHint").contains("花草 4"),"Hint explains why 完成展示 waits (%s): %s"%[label,label_text("ShowcaseHint")])
	focus_ok("started "+label)
	layout_ok("started "+label)
	var time_node:=control("ShowcaseTime")
	w.state.time=float(w.state.time)+2.0  # PRESET clock
	await refresh()
	check(control("ShowcaseTime")==time_node and label_text("ShowcaseTime")=="剩 598 秒","Time label updated in place (%s): %s"%[label,label_text("ShowcaseTime")])
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the page (%s)"%label)
	# HUD tracker.
	await refresh()
	check(str(app.objective.text)=="家園布置題 花園茶會\n花草 0/4 座位 0/3 燈飾 0/1\n剩 598 秒 · %s 擺紙燈籠"%app.binding_label("interact"),"HUD tracker shows theme, checklist, time and prop (%s): %s"%[label,app.objective.text])
	check(tracker_heading().begins_with("家園布置題"),"Tracker heading follows 家園布置題 (%s): %s"%[label,tracker_heading()])
	var tracker_next:=app.hud.find_child("TrackerNext",true,false) as Button
	check(tracker_next!=null and tracker_next.text.contains("家園布置題"),"Tracker button names the activity (%s)"%label)
	if tracker_next!=null:
		tracker_next.pressed.emit()
		await settle()
		check(page_open(),"Tracker button opens the page (%s)"%label)
		await close_page()
	# Sign label during the round (from afar).
	await stand(FAR_SPOT)
	check(str((await world_label(ShowUI.POINT)).get("title",""))=="家園布置題","Unfocused sign label keeps the short name during a round (%s)"%label)
	# Real interact presses on plot tiles.
	await stand(PLOT_SPOT)
	await face(Vector2i.UP)
	await key_on_plot(Vector2i(29,45),"擺上 紙燈籠",label+" place lantern")
	check(piece(Vector2i(29,45))=="lantern","E placed 紙燈籠 on (29,45) (%s): %s"%[label,toast()])
	check(toast().contains("擺上紙燈籠"),"Placement reply shown (%s): %s"%[label,toast()])
	check((await world_label(ShowUI.PLOT_POINT)).get("title","")=="收起 紙燈籠","Prompt on the occupied tile says 收起 紙燈籠 (%s)"%label)
	check(str(app.objective.text).contains("燈飾 1/1✓"),"Tracker checklist ticks 燈飾 (%s): %s"%[label,app.objective.text])
	await choose("flower_pot",label)
	await face(Vector2i.LEFT)
	await key_on_plot(Vector2i(28,46),"擺上 小花盆",label+" place pot")
	check(piece(Vector2i(28,46))=="flower_pot","E placed 小花盆 on (28,46) (%s)"%label)
	await choose("bench",label)
	await face(Vector2i.RIGHT)
	await key_on_plot(Vector2i(30,46),"擺上 長木椅",label+" place bench")
	check(piece(Vector2i(30,46))=="bench","E placed 長木椅 on (30,46) (%s)"%label)
	await choose("cushion",label)
	await face(Vector2i.DOWN)
	await key_on_plot(Vector2i(29,47),"擺上 野餐坐墊",label+" place cushion")
	check(piece(Vector2i(29,47))=="cushion","E placed 野餐坐墊 on (29,47) (%s)"%label)
	await face(Vector2i.UP)
	await key_on_plot(Vector2i(29,45),"收起 紙燈籠",label+" remove lantern")
	check(piece(Vector2i(29,45)).is_empty(),"E removed 紙燈籠 from (29,45) (%s): %s"%[label,toast()])
	check(toast().contains("收起紙燈籠"),"Removal reply shown (%s): %s"%[label,toast()])
	check(str(app.objective.text).contains("燈飾 0/1") and not str(app.objective.text).contains("燈飾 0/1✓"),"Tracker checklist drops 燈飾 again (%s)"%label)
	# Mouse click on a plot tile within reach (diagonal) places the selected prop.
	await choose("flower_box",label)
	await click(Vector2i(30,45))
	check(piece(Vector2i(30,45))=="flower_box","Click placed 花草長箱 on (30,45) (%s): %s"%[label,toast()])
	# A click on a far plot tile is rejected with the server message; nothing changes.
	var pieces_before:Dictionary=(w.state.showcase.pieces as Dictionary).duplicate(true)
	await click(Vector2i(32,44))
	check(toast().contains(Show.TOO_FAR_TILE) and w.state.showcase.pieces==pieces_before,"Far click rejected with TOO_FAR_TILE (%s): %s"%[label,toast()])
	check(person().inventory==bag_before and int(person().coins)==coins_before,"Placing and removing never touch the backpack or coins (%s)"%label)
	# Checklist on the page.
	app._showcase_menu()
	await settle()
	check(label_text("ShowcaseCheck_flower")=="花草 2／4" and label_text("ShowcaseCheck_seat")=="座位 2／3" and label_text("ShowcaseCheck_light")=="燈飾 0／1","Checklist counts my pieces (%s): %s %s %s"%[label,label_text("ShowcaseCheck_flower"),label_text("ShowcaseCheck_seat"),label_text("ShowcaseCheck_light")])
	check(label_text("ShowcaseProgress")=="展示 4 件 · 滿版 16 件","Pieces vs full goal (%s): %s"%[label,label_text("ShowcaseProgress")])
	await close_page()
	# A teammate joins and fills the rest; 完成展示 stays disabled until the theme is met.
	var buddy:=friend(0,FRIEND_SPOTS[0])
	var joined:Dictionary=await world_act(buddy,"showcase_join",Show.SIGN,str(round_id))
	check(bool(joined.get("ok",false)),"Teammate joins (%s): %s"%[label,str(joined)])
	for step:Array in [[Vector2i(27,44),"fern"],[Vector2i(28,44),"flower_pot"],[Vector2i(27,45),"stool"]]:
		var placed:Dictionary=await world_act(buddy,"showcase_place",step[0],"%d|%s"%[round_id,step[1]])
		check(bool(placed.get("ok",false)),"Teammate places %s (%s): %s"%[step[1],label,str(placed)])
	app._showcase_menu()
	await settle()
	check(label_text("ShowcaseCheck_flower")=="花草 4／4 ✓" and label_text("ShowcaseCheck_seat")=="座位 3／3 ✓" and label_text("ShowcaseCheck_light")=="燈飾 0／1","Checklist ticks met categories (%s): %s / %s / %s"%[label,label_text("ShowcaseCheck_flower"),label_text("ShowcaseCheck_seat"),label_text("ShowcaseCheck_light")])
	disabled_with_reason("ShowcaseFinish",label,"燈飾 1")
	await close_page()
	var last_piece:Dictionary=await world_act(buddy,"showcase_place",Vector2i(28,45),"%d|lantern"%round_id)
	check(bool(last_piece.get("ok",false)),"Teammate places the lantern (%s)"%label)
	# Eight participants: the page still fits.
	for index in range(1,7):
		var token:=friend(index,FRIEND_SPOTS[index])
		var result:Dictionary=await world_act(token,"showcase_join",Show.SIGN,str(round_id))
		check(bool(result.get("ok",false)),"Participant %d joins (%s): %s"%[index+2,label,str(result)])
	check(int(own().get("joined_count",0))==8,"Eight participants joined (%s): %d"%[label,int(own().get("joined_count",0))])
	app._showcase_menu()
	await settle()
	check(control("ShowcasePeople")!=null and control("ShowcasePeople").get_child_count()==8,"Eight participant rows (%s)"%label)
	check(label_text("ShowcasePeopleCount")=="8／8 人在場","Count 8／8 (%s): %s"%[label,label_text("ShowcasePeopleCount")])
	check(label_text("ShowcasePersonDetail_0")=="在場 · 地塊上 4 件 · 擺過 5 次","Me first with my pieces (%s): %s"%[label,label_text("ShowcasePersonDetail_0")])
	check(label_text("ShowcaseCheck_light")=="燈飾 1／1 ✓" and label_text("ShowcaseHint").contains("主題完成了"),"Theme met on the page (%s): %s"%[label,label_text("ShowcaseHint")])
	check(button("ShowcaseFinish")!=null and not button("ShowcaseFinish").disabled,"完成展示 enabled once the theme is met (%s)"%label)
	layout_ok("8 participants "+label)
	focus_ok("8 participants "+label)
	# 完成展示 (goal).
	if await press("ShowcaseFinish",label):
		var last:Dictionary=own().get("last",{})
		check(str(last.get("reason",""))=="goal" and bool(last.get("met",false)) and not bool(last.get("full",true)) and int(last.get("tickets",0))==2,"Finished by goal with 2 tickets (%s): %s"%[label,str(last)])
		check(feedback().contains("布置完成"),"Finish reply shown (%s): %s"%[label,feedback()])
		check(label_text("ShowcaseLastTitle")=="上一輪成果（已結束）","Result card is labelled as the previous round (%s): %s"%[label,label_text("ShowcaseLastTitle")])
		check(label_text("ShowcaseLast")=="第 1 輪「花園茶會」· 提早完成展示 · 主題完成","Result line (%s): %s"%[label,label_text("ShowcaseLast")])
		check(label_text("ShowcaseLastTickets")=="展示 8 件 · 8 人參加 · 每人 2 張紀念票","Result tickets line (%s): %s"%[label,label_text("ShowcaseLastTickets")])
		check(label_text("ShowcaseRecord")=="紀念票 2 張 · 參加 1 場 · 最佳 8 件","Record line (%s): %s"%[label,label_text("ShowcaseRecord")])
		check(label_text("ShowcaseProgress").begins_with("上一輪 展示 8 件"),"Header marks the shown count as the previous round (%s): %s"%[label,label_text("ShowcaseProgress")])
		disabled_with_reason("ShowcaseStart",label,"整理")
		layout_ok("result goal "+label)
	check(person().inventory==bag_before and int(person().coins)==coins_before,"Whole backpack and coins identical after finishing (%s)"%label)
	w.step(1.0,true)  # another normal tick
	await refresh()
	check(int(own().get("tickets",0))==2 and int(own().get("rounds",0))==1,"Tickets not paid again (%s): %d"%[label,int(own().get("tickets",0))])
	check(not ShowUI.public_show(app.session.snapshot).get("pieces",{}).is_empty(),"Finished display stays during the cooldown (%s)"%label)
	await close_page()
	await refresh()
	check(not str(app.objective.text).begins_with("家園布置題"),"Tracker stops after the round (%s): %s"%[label,app.objective.text])
	# Emote button opens the existing 島民招呼 menu.
	app._showcase_menu()
	await settle()
	await press("ShowcaseEmote",label,false)
	var emote_ok:=false
	if is_instance_valid(app.modal):
		for node in (app.modal as Node).find_children("*","Button",true,false):
			if (node as Button).text==str(app.session.EMOTES.hello):emote_ok=true
	check(emote_ok and not page_open(),"島民招呼 opens the existing emote menu (%s)"%label)
	await close_page()
	# Round 2: start again after the cooldown, tracker priority, leave, time-out.
	w.state.time=float(w.state.showcase.ready)+0.1  # PRESET: cooldown over
	w.step(1.0,true)
	await refresh()
	check(ShowUI.pieces(app.session.snapshot).is_empty(),"Display cleared after the cooldown (%s)"%label)
	await stand(SIGN_SPOT)
	await interact_key()
	check(page_open(),"E at the sign opens the page again (%s)"%label)
	check(label_text("ShowcaseThemeTitle")=="下一輪主題「海風小攤」","Next theme rotates (%s): %s"%[label,label_text("ShowcaseThemeTitle")])
	if not await press("ShowcaseStart",label):return
	var round_two:=int(own().get("round",0))
	check(round_two==2 and bool(own().get("joined",false)),"Round 2 started (%s)"%label)
	await close_page()
	# Tracker priority: 豐收接力 > 河岸釣魚會 > 家園布置題.
	await stand(Vector2(Relay.SIGN)+Vector2(0.5,1.5))
	var harvest:Dictionary=await world_act(id,"harvest_start",Relay.SIGN,str(int(Relay.round_state(w.state).round)))
	check(bool(harvest.get("ok",false)),"PRESET: I also start 豐收接力 (%s): %s"%[label,str(harvest)])
	await stand(Vector2(Meet.SIGN)+Vector2(0.5,1.5))
	var meet:Dictionary=await world_act(id,"fish_meet_start",Meet.SIGN,str(int(Meet.round_state(w.state).round)))
	check(bool(meet.get("ok",false)),"PRESET: I also start 河岸釣魚會 (%s): %s"%[label,str(meet)])
	await stand(PLOT_SPOT)
	check(str(app.objective.text).begins_with("豐收接力") and tracker_heading().begins_with("豐收接力"),"豐收接力 outranks the others on the tracker (%s): %s"%[label,app.objective.text])
	await world_act(id,"harvest_leave",Vector2i(PLOT_SPOT),"")
	check(str(app.objective.text).begins_with("河岸釣魚會") and tracker_heading().begins_with("河岸釣魚會"),"河岸釣魚會 outranks 家園布置題 (%s): %s"%[label,app.objective.text])
	await world_act(id,"fish_meet_leave",Meet.SIGN,"")
	check(str(app.objective.text).begins_with("家園布置題 海風小攤") and tracker_heading().begins_with("家園布置題"),"家園布置題 tracked once the others are left (%s): %s"%[label,app.objective.text])
	var bag_round:Dictionary=(person().inventory as Dictionary).duplicate(true)
	var coins_round:=int(person().coins)
	check(bag_round==bag_before and coins_round==coins_before,"Backpack unchanged by the other activities (%s)"%label)
	# 離開活動.
	app._showcase_menu()
	await settle()
	if await press("ShowcaseLeave",label):
		check(not bool(own().get("joined",true)) and bool(own().get("active",false)),"離開活動 leaves the running round (%s)"%label)
		check(feedback().contains("背包沒有變動"),"Leave reply mentions the backpack (%s): %s"%[label,feedback()])
		check(label_text("ShowcasePersonDetail_0").begins_with("已離開"),"I am listed as 已離開 (%s): %s"%[label,label_text("ShowcasePersonDetail_0")])
		disabled_with_reason("ShowcaseFinish",label,"先加入")
		layout_ok("left "+label)
	check(person().inventory==bag_before and int(person().coins)==coins_before,"Whole backpack and coins identical after leaving (%s)"%label)
	await close_page()
	await refresh()
	check(not str(app.objective.text).begins_with("家園布置題"),"Tracker stops after leaving (%s): %s"%[label,app.objective.text])
	check(focus()!=ShowUI.PLOT_POINT,"No plot prompt after leaving (%s): %s"%[label,focus()])
	# Time-out: participation ticket paid once.
	w.state.time=float(w.state.showcase.ends)+0.1  # PRESET time
	check(w.step(1.0,true),"World tick ends the round (%s)"%label)
	await refresh()
	app._showcase_menu()
	await settle()
	var timed:Dictionary=own().get("last",{})
	check(str(timed.get("reason",""))=="time" and int(timed.get("tickets",0))==1,"Round 2 settled by time (%s): %s"%[label,str(timed)])
	check(label_text("ShowcaseLast")=="第 2 輪「海風小攤」· 時間到 · 主題未完成","Time result line (%s): %s"%[label,label_text("ShowcaseLast")])
	check(label_text("ShowcaseLastTickets")=="展示 0 件 · 1 人參加 · 每人 1 張紀念票","Time result tickets (%s): %s"%[label,label_text("ShowcaseLastTickets")])
	check(int(own().get("tickets",0))==3 and int(own().get("rounds",0))==2 and label_text("ShowcaseRecord")=="紀念票 3 張 · 參加 2 場 · 最佳 8 件","Leaver gets the participation ticket once (%s): %s"%[label,label_text("ShowcaseRecord")])
	layout_ok("result time "+label)
	w.step(1.0,true)
	await refresh()
	check(int(own().get("tickets",0))==3,"Time-out tickets not paid again (%s)"%label)
	check(person().inventory==bag_before and int(person().coins)==coins_before,"Backpack and coins unchanged after settlement (%s)"%label)
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the result page (%s)"%label)
	# Paused: a plot cell is occupied.
	w.state.objects["28,45"]={"type":"lamp","owner":id,"items":{}}  # PRESET occupation
	w.state.showcase.ready=float(w.state.time)  # PRESET: cooldown over
	await refresh()
	check(not ShowUI.on_field(app.session.snapshot) and ShowUI.sign_shown(app.session.snapshot),"Occupied plot: paused but the sign stays (%s)"%label)
	await stand(SIGN_SPOT)
	await interact_key()
	check(page_open(),"E at the sign opens the paused page (%s)"%label)
	disabled_with_reason("ShowcaseStart",label,Show.UNAVAILABLE)
	check(label_text("ShowcaseHint")==Show.UNAVAILABLE,"Hint shows UNAVAILABLE (%s): %s"%[label,label_text("ShowcaseHint")])
	check(label_text("ShowcaseBlocked").contains("地塊 (28,45)") and not label_text("ShowcaseBlocked").contains("告示牌"),"Paused page names the cell to clear (%s): %s"%[label,label_text("ShowcaseBlocked")])
	layout_ok("paused "+label)
	await close_page()
	w.state.objects.erase("28,45")
	for token in friends:
		var p:Dictionary=w.state.players[token]
		p.x=AWAY.x;p.y=AWAY.y

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	path=OS.get_environment("TEMP").path_join("showcase-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"布置題旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	if not app.playing:note("app.playing was false after host; set true for key input");app.playing=true
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		await locked_flow(tag)
		await main_flow(tag)
		note("size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
