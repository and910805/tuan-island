extends SceneTree
## 第 40 章風鈴節廣場「地方記憶展」UI test (headless) at 1024×640 and 1280×800. Same harness as
## test_souvenir_exchange_ui.gd / test_lanyang_revisit_ui.gd: real Session host, real snapshot
## round trips.
##
## PRESET / FIXTURE (direct writes, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true is set
##    here (the runner passes no flag for this suite);
##  * state.board / state.picnic / chapter_one.shipped+watered written true;
##  * state.festival_story_open WRITTEN DIRECTLY (false for the locked checks, true after);
##  * UNLOCK FIXTURE written directly as test_lanyang_revisit_ui: lanyang_life cleared ×3 +
##    donations + repaired, history_memory {players:{me:{seen ×3, round 3, completed}},
##    plaque:true} (latecomer: seen [], round 0, completed:false; revisit-locked: plaque:false);
##  * COMPLETED 蘭陽回訪 written directly: state.lanyang_revisit = {gates:[3,2], day:1,
##    checked:[upstream,middle,tail], completed:true, claimed:{} or {me:true}} (the earned
##    path is test_lanyang_revisit_journey); state.time stays on day 1 (spring);
##  * player.memory_exhibit erased before each flow (and once more for the journal check);
##  * the local player is teleported by writing region/x/y (no walking);
##  * the paused state writes three lamp objects onto the stand candidates;
##  * session rate buckets / action_clock are cleared between my own actions;
##  * the tracker slot: tea guidance always overrides the home tracker after chapter one
##    (main._refresh_hud), so the memory-exhibit tracker line is checked by calling
##    LifeShell.refresh_hud once more after app._refresh_hud (the slot it writes), and
##    tracker_text() directly; one diversion_gate_kit is written into the bag so the
##    higher-priority 分流閘 home hint steps aside.
## REALLY EXERCISED (local player):
##  * KEY_E through root.push_input -> main._unhandled_input -> _interact at the stand opens
##    the page (and does not before the festival); KEY_ESCAPE closes; KEY_LEFT / RIGHT / UP /
##    DOWN focus; KEY_ENTER on the cards, 翻閱回顧, 下一頁 / 看完了, 上一頁;
##  * reaching the last recap page at the stand sends exhibit_view through Session.perform ->
##    World -> snapshot; exactly once (counted with session.counter and the saved record);
##  * the 地方記憶展 entries on 渡口派對 · 風鈴接力 (preview festival page), the 公告板 and the
##    島嶼近況 journal line (pressed), their overflow before/after.
## NOT COVERED HERE: world pixels (test_memory_exhibit_scene.gd); gamepad input (only the
## focus neighbours it uses, through the arrow keys); the non-preview layout (no entries there).
const World=preload("res://scripts/world.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const UI=preload("res://scripts/memory_exhibit_ui.gd")
const STAND:=Vector2i(39,26)
const NEAR:=Vector2(39.5,27.5)     # 1.0 from the stand centre; 公告板 / 鈴婆婆 2.24, booth 2.83
const FAR:=Vector2(39.5,33.5)      # 7.0 from the stand: label visible, not focused
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
	print("MEMORY_EXHIBIT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE MEMORY_EXHIBIT_UI "+message)

# ------------------------------------------------------------------ helpers --

func control(name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(name,true,false) as Control

func button(name:String)->Button:
	return control(name) as Button

func label_text(name:String)->String:
	var l:=control(name) as Label
	return l.text if l!=null else ""

func shown(name:String)->bool:
	var c:=control(name)
	return c!=null and c.is_visible_in_tree()

func page_open()->bool:
	return is_instance_valid(app.modal) and str((app.modal as Node).get_meta("life_modal_layout",""))==UI.LAYOUT

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

func snap()->Dictionary:
	return app.session.snapshot

func person()->Dictionary:
	return w.state.players[id]

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func focus()->String:
	return str(app.view.interaction_focus())

func focused_name()->String:
	var owner:=root.gui_get_focus_owner()
	return str(owner.name) if owner!=null else "none"

func stand(at:Vector2)->void:
	var p:Dictionary=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	await settle()

func key(code:Key)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		root.push_input(e)
	await settle()

func interact_key()->void:
	app.session.rates[1].clear()
	await key(KEY_E)
	await refresh()

## Enter on the focused control, then a snapshot round trip.
func enter()->void:
	app.action_clock=0
	app.session.rates[1].clear()
	await key(KEY_ENTER)
	await refresh()

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

func seen_record()->Array:
	var rec:Variant=person().get(Exhibit.RECORD_KEY)
	return (rec.get("seen",[]) as Array) if rec is Dictionary else []

# ------------------------------------------------------------------- layout --

## No outer scrolling, everything inside the page and the viewport, nothing cut.
func layout_ok(label:String)->void:
	if not page_open():
		check(false,"Page open for layout: "+label)
		return
	var modal:Control=app.modal
	var view_rect:=root.get_visible_rect()
	check(view_rect.encloses(modal.get_global_rect()),"Page fits the viewport (%s) %s"%[label,rect_info(null)])
	var outer:=control("ModalScroll") as ScrollContainer
	check(outer!=null,"Outer scroll container found (%s)"%label)
	if outer!=null:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Outer page needs no scrolling (%s) max=%.0f page=%.0f"%[label,bar.max_value,bar.page])
		note("%s modal %s content min %.0f page %.0f"%[label,str(modal.get_global_rect()),bar.max_value,bar.page])
	var visible_count:=0
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect):continue
		visible_count+=1
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the page (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:
			check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
			# Labels inside a card button stay inside that button.
			var card:=c.get_parent()
			while card!=null and not (card is Button) and card!=modal:card=card.get_parent()
			if card is Button and card!=modal:check((card as Control).get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside its card (%s) %s"%[c.name,label,rect_info(card as Control)])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(visible_count>0,"Page has visible controls (%s)"%label)
	check(not texts().contains("…"),"No ellipsis anywhere in the page (%s)"%label)
	for row_name in ["MemoryCards","MemoryLower","MemoryActions"]:
		var row:=control(row_name)
		if row!=null and row.is_visible_in_tree():check(row.get_combined_minimum_size().x<=row.size.x+0.5,"%s does not overflow (%s)"%[row_name,label])

func focus_in_page(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton,"Keyboard focus is on a button inside the page (%s): %s"%[label,focused_name()])

## The entry adds no outer scrolling (overflow with the entry equals the overflow with it
## removed), its row does not overflow and every caption stays whole.
func entry_fits(page:String)->void:
	if not is_instance_valid(app.modal):
		check(false,"Page open: "+page)
		return
	var modal:Control=app.modal
	var outer:=control("ModalScroll") as ScrollContainer
	var entry:=button("MemoryExhibitEntry")
	check(entry!=null,"%s lists 地方記憶展"%page)
	if outer!=null and entry!=null:
		var bar:=outer.get_v_scroll_bar()
		var with_entry:=maxf(0.0,bar.max_value-bar.page)
		var parent:=entry.get_parent()
		var index:=entry.get_index()
		parent.remove_child(entry)
		await settle()
		var without:=maxf(0.0,bar.max_value-bar.page)
		var row_without:=(parent as Control).get_combined_minimum_size().x
		parent.add_child(entry)
		parent.move_child(entry,index)
		await settle()
		var row_with:=(parent as Control).get_combined_minimum_size().x
		note("%s outer overflow with entry %.0f px, without %.0f px (delta %.0f); row min width %.0f -> %.0f of %.0f"%[page,with_entry,without,with_entry-without,row_without,row_with,(parent as Control).size.x])
		check(with_entry<=without+1.0,"The 地方記憶展 entry adds no outer scrolling (%s): %.0f vs %.0f"%[page,with_entry,without])
		check(row_with<=(parent as Control).size.x+0.5,"The entry row does not overflow (%s): %.0f vs %.0f"%[page,row_with,(parent as Control).size.x])
	if entry!=null:
		# The 公告板 is an ordinary scrolling page: scroll to each target the way keyboard
		# focus / the wheel does, then require the whole control (and its text, not
		# trimmed) inside the actual scroll viewport and the page.
		if outer!=null:
			outer.ensure_control_visible(entry)
			await settle()
			check(outer.get_global_rect().grow(0.5).encloses(entry.get_global_rect()),"地方記憶展 entry reachable by scrolling inside the visible scroll area (%s) %s"%[page,rect_info(entry)])
		check(modal.get_global_rect().grow(0.5).encloses(entry.get_global_rect()) and button_not_cut(entry),"地方記憶展 entry whole inside the page (%s)"%page)
		for other in ["SouvenirEntry","HarvestRelayEntry","HarvestRelayBoardEntry","FishingMeetEntry","ShowcaseEntry"]:
			var b:=button(other)
			if b!=null:
				if outer!=null:
					outer.ensure_control_visible(b)
					await settle()
					check(outer.get_global_rect().grow(0.5).encloses(b.get_global_rect()),"%s reachable by scrolling inside the visible scroll area (%s) %s"%[other,page,rect_info(b)])
				check(button_not_cut(b) and modal.get_global_rect().grow(0.5).encloses(b.get_global_rect()),"%s caption still whole (%s)"%[other,page])

func entry_opens(page:String,locked:bool)->void:
	var entry:=button("MemoryExhibitEntry")
	var want:=UI.ENTRY_LOCKED if locked else UI.ENTRY_OPEN
	check(entry!=null and entry.text==want,"%s entry caption 「%s」: %s"%[page,want,entry.text if entry else "missing"])
	if entry!=null and locked:check(entry.tooltip_text==Exhibit.LOCKED,"%s locked entry tooltip gives the reason"%page)
	await entry_fits(page)
	entry=button("MemoryExhibitEntry")
	if entry==null:return
	entry.pressed.emit()
	await settle()
	check(page_open(),"%s entry opens the 地方記憶展 page"%page)
	if locked:
		check(label_text("MemoryState")==Exhibit.LOCKED and shown("MemoryState"),"Locked page from %s shows the reason: %s"%[page,label_text("MemoryState")])
		check(not shown("MemoryCards") and not shown("MemoryLower"),"Locked page shows no exhibits (%s)"%page)
		await settle()
		focus_in_page("locked from "+page)
		layout_ok("locked from "+page)

# ------------------------------------------------------------------- fixture --

func k(c:Vector2i)->String:
	return World.key(c)

## Disclosed unlock fixture (see header). mode: "ready" / "late" / "revisit_locked".
func write_unlock(mode:String)->void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true  # PRESET
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()  # PRESET
	life.repaired=true  # PRESET
	var ready:=mode=="ready"
	var seen:=[]
	if ready:
		for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{id:{"seen":seen,"round":3 if ready else 0,"gates":[0,0],"completed":ready}},"plaque":mode!="revisit_locked"}  # PRESET

func write_completed(claimed:bool)->void:
	w.state[Revisit.STATE_KEY]={"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true,"claimed":{id:true} if claimed else {}}  # PRESET

func base(open_festival:bool)->void:
	await close_page()
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	w.state.chapter_one.shipped=true  # PRESET
	w.state.chapter_one.watered=true  # PRESET
	w.state.festival_story_open=open_festival  # PRESET
	w.state.time=30.0  # PRESET: day 1, spring
	w.state.erase(Revisit.STATE_KEY)  # PRESET
	person().erase(Exhibit.RECORD_KEY)  # PRESET
	(person().inventory as Dictionary).erase("diversion_gate_kit")  # PRESET
	for cell:Vector2i in Exhibit.CANDIDATES:w.state.objects.erase(k(cell))
	write_unlock("ready")
	await refresh()

# --------------------------------------------------------------------- flows --

func locked_flow(tag:String)->void:
	await base(false)
	check(not UI.stand_shown(snap()) and not snap().has(Exhibit.STATE_KEY),"Locked before the festival: no stand, no public block (%s)"%tag)
	await stand(NEAR)
	check(focus()!=UI.POINT,"No stand focus before the festival (%s): %s"%[tag,focus()])
	check((await world_label(UI.POINT)).is_empty(),"No stand label before the festival (%s)"%tag)
	await interact_key()
	check(not page_open(),"E at the stand spot before the festival opens no 地方記憶展 (%s)"%tag)
	await close_page()
	check(UI.tracker_text(snap())=="" and UI.news_line(snap())=="","No tracker / journal line before the festival (%s)"%tag)
	app._festival_menu()
	await settle()
	await entry_opens("風鈴接力活動頁 locked "+tag,true)
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the locked page (%s)"%tag)
	app._board()
	await settle()
	await entry_opens("公告板 locked "+tag,true)
	await close_page()
	app.LifeTasks.island_news(app)
	await settle()
	check(control("MemoryExhibitNews")==null,"島嶼近況 has no 地方記憶展 line before the festival (%s)"%tag)
	await close_page()

func empty_flow(tag:String)->void:
	await base(true)
	var block:Variant=snap().get(Exhibit.STATE_KEY)
	check(block is Dictionary and block.get("cell")==STAND and block.get("paused")==false and (block.get("on_display") as Array).is_empty(),"Public block: stand at (39,26), nothing on display (%s): %s"%[tag,str(block)])
	check(UI.stand_cell(snap())==STAND and w.blocked(STAND) and w.protected(STAND),"Stand cell blocks and is protected (%s)"%tag)
	await stand(FAR)
	var idle:=await world_label(UI.POINT)
	check(str(idle.get("title",""))==UI.TITLE,"Stand label 「地方記憶展」 from afar, no 新 (%s): %s"%[tag,str(idle)])
	check(focus()!=UI.POINT,"Not focused from 7 tiles (%s)"%tag)
	await stand(NEAR)
	check(focus()==UI.POINT,"Standing south of the stand focuses it (%s): %s"%[tag,focus()])
	var focused:=await world_label(UI.POINT)
	check(str(focused.get("title",""))=="看"+UI.TITLE,"Focused prompt 「看地方記憶展」 (%s): %s"%[tag,str(focused)])
	await interact_key()
	check(page_open(),"E at the stand opens 地方記憶展 (%s) %s"%[tag,texts().left(60).replace("\n"," | ")])
	if not page_open():return
	check(not app._world_keyboard_allowed(),"World keys blocked while the page is open (%s)"%tag)
	await settle()
	check(focused_name()=="MemoryCard_lanyang","Focus starts on the 分水木牌 card (%s): %s"%[tag,focused_name()])
	check(label_text("MemoryState")==UI.NONE_ON_DISPLAY,"Nothing on display: honest line (%s): %s"%[tag,label_text("MemoryState")])
	for ex:String in Exhibit.EXHIBIT_ORDER:
		check(label_text("MemoryStatus_"+ex)==UI.STATUS_EMPTY and not shown("MemoryBadge_"+ex),"%s card: 展台空著, no badge (%s)"%[ex,tag])
		check(label_text("MemoryName_"+ex)==str(Exhibit.EXHIBITS[ex].name) and label_text("MemoryRegion_"+ex)==str(Exhibit.EXHIBITS[ex].region),"%s card name / region (%s)"%[ex,tag])
	check(label_text("MemoryEmpty")==Exhibit.EMPTY_LINE and button("MemoryRecap").disabled and not shown("MemoryDisclaimer"),"Empty pedestal detail, 翻閱回顧 disabled (%s)"%tag)
	check(label_text("MemorySeenCount")=="目前沒有展出中的展品","Seen count line with nothing on display (%s): %s"%[tag,label_text("MemorySeenCount")])
	check(label_text("MemoryHint")==Exhibit.HINT_NOT_DONE and label_text("MemoryFirstShare").begins_with("✓"),"Ready, revisit not done: HINT_NOT_DONE (%s): %s"%[tag,label_text("MemoryHint")])
	layout_ok("nothing on display "+tag)
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the page (%s)"%tag)
	# Latecomer hints before the revisit is done (written directly, see header).
	for case:Array in [["late",Exhibit.HINT_NOT_DONE_NOT_READY],["revisit_locked",Exhibit.HINT_REVISIT_LOCKED]]:
		write_unlock(case[0])
		await refresh()
		await interact_key()
		check(page_open() and label_text("MemoryHint")==case[1],"Hint for %s (%s): %s"%[case[0],tag,label_text("MemoryHint")])
		check(label_text("MemoryFirstShare").begins_with("○") and label_text("MemoryPlaque").begins_with("○"),"Latecomer progress lines (%s %s)"%[case[0],tag])
		layout_ok("latecomer %s %s"%[case[0],tag])
		await close_page()
	write_unlock("ready")
	await refresh()
	check(UI.tracker_text(snap())=="","No tracker line with nothing on display (%s)"%tag)
	check(UI.news_line(snap())=="地方記憶展：0 件展出・0 件還沒看","Journal line with nothing on display (%s): %s"%[tag,UI.news_line(snap())])
	# Entries after the festival.
	app._festival_menu()
	await settle()
	await entry_opens("風鈴接力活動頁 "+tag,false)
	await close_page()
	app._board()
	await settle()
	await entry_opens("公告板 "+tag,false)
	await close_page()

func display_flow(tag:String)->void:
	await base(true)
	write_unlock("late")
	write_completed(false)
	await refresh()
	check((snap().get(Exhibit.STATE_KEY,{}) as Dictionary).get("on_display",[])==["lanyang"],"分水木牌 on display (%s)"%tag)
	await stand(FAR)
	var idle:=await world_label(UI.POINT)
	check(str(idle.get("title",""))==UI.TITLE+"・新","Unread: label 「地方記憶展・新」 (%s): %s"%[tag,str(idle)])
	check(UI.tracker_text(snap())==UI.TRACKER%1,"Tracker text for one unread (%s): %s"%[tag,UI.tracker_text(snap())])
	# The 分流閘 home hint outranks the exhibit line until the player holds a gate kit.
	person().inventory["diversion_gate_kit"]=1  # PRESET
	await refresh()
	var me:Dictionary=snap().players[app.session.own_id]
	app.LifeShell.refresh_hud(app,snap(),me)
	check(str(app.objective.text)==UI.TRACKER%1,"LifeShell writes the exhibit line in the home tracker slot (%s): %s"%[tag,str(app.objective.text)])
	await refresh()
	note("%s tracker after the full _refresh_hud (tea guidance outranks): %s"%[tag,str(app.objective.text).replace("\n"," | ")])
	# Journal line opens the page from afar; reading the recap there does not mark it seen.
	app.LifeTasks.island_news(app)
	await settle()
	var news:=button("MemoryExhibitNews")
	check(news!=null and news.text=="地方記憶展：1 件展出・1 件還沒看","島嶼近況 line (%s): %s"%[tag,news.text if news else "missing"])
	if news!=null:
		news.pressed.emit()
		await settle()
	check(page_open() and label_text("MemoryState")==UI.WALK,"Journal opens the page; far away the walk hint shows (%s): %s"%[tag,label_text("MemoryState")])
	var counter:int=app.session.counter
	button("MemoryRecap").grab_focus()
	await enter()
	for i in 3:await enter()
	check(label_text("MemoryPageTitle").begins_with("回顧 4／4") and app.session.counter==counter and seen_record().is_empty(),"Far away: last page reached, nothing sent (%s): %s %d"%[tag,label_text("MemoryPageTitle"),app.session.counter-counter])
	check(feedback()==UI.NOT_NEAR_DONE,"Far away: page foot explains (%s): %s"%[tag,feedback()])
	layout_ok("far last page "+tag)
	await close_page()
	# At the stand.
	await stand(NEAR)
	await interact_key()
	check(page_open(),"E opens the page (%s)"%tag)
	if not page_open():return
	await settle()
	check(focused_name()=="MemoryCard_lanyang","Focus on the unread 分水木牌 (%s): %s"%[tag,focused_name()])
	check(label_text("MemoryBadge_lanyang")==UI.BADGE_NEW and shown("MemoryBadge_lanyang") and label_text("MemoryStatus_lanyang")==UI.STATUS_ON,"Badge 新 and 展出中 (%s)"%tag)
	check(not shown("MemoryState"),"No page-wide line at the stand (%s): %s"%[tag,label_text("MemoryState")])
	check(label_text("MemoryBlurb")==Revisit.PLAQUE_BLURB and label_text("MemorySource").contains(Revisit.PLAQUE_SOURCE) and label_text("MemorySource").contains(Revisit.PLAQUE_PROJECT),"Detail: blurb, source, project (%s)"%tag)
	check(label_text("MemoryDay").begins_with("完成那天：第 1 日") and label_text("MemoryDemand")=="三塊田需要：上游 6／中段 4／田尾 2 份" and label_text("MemoryGates")=="岔口的閘：上游閘 3 檔、中段閘 2 檔","Detail: day, demand, gates (%s): %s / %s / %s"%[tag,label_text("MemoryDay"),label_text("MemoryDemand"),label_text("MemoryGates")])
	check(label_text("MemoryDisclaimer")==Revisit.DISCLAIMER,"Disclaimer shown (%s)"%tag)
	check(label_text("MemoryHint")==Exhibit.HINT_NOT_READY,"Latecomer after completion: HINT_NOT_READY (%s): %s"%[tag,label_text("MemoryHint")])
	check(label_text("MemorySeenCount")=="看過 0／1 件展出中的展品","Seen 0／1 (%s)"%tag)
	layout_ok("one unread "+tag)
	# Focus grid.
	await key(KEY_RIGHT)
	check(focused_name()=="MemoryCard_jinguashi","KEY_RIGHT to 礦燈 (%s): %s"%[tag,focused_name()])
	await key(KEY_LEFT)
	await key(KEY_LEFT)
	check(focused_name()=="MemoryCard_beimen","KEY_LEFT wraps to 鹽籃 (%s): %s"%[tag,focused_name()])
	await key(KEY_UP)
	var up:=root.gui_get_focus_owner() as Button
	check(up!=null and up.text.contains("關閉"),"KEY_UP from the cards reaches 關閉 (%s): %s"%[tag,up.text if up else "none"])
	await key(KEY_DOWN)
	check(focused_name()=="MemoryCard_lanyang","KEY_DOWN from 關閉 returns to the selected card (%s): %s"%[tag,focused_name()])
	await key(KEY_DOWN)
	check(focused_name()=="MemoryRecap","KEY_DOWN to 翻閱回顧 (%s): %s"%[tag,focused_name()])
	await key(KEY_UP)
	check(focused_name()=="MemoryCard_lanyang","KEY_UP back to the selected card (%s): %s"%[tag,focused_name()])
	# Enter on an empty pedestal.
	await key(KEY_RIGHT)
	await enter()
	check(label_text("MemoryDetailName")=="礦燈" and label_text("MemoryEmpty")==Exhibit.EMPTY_LINE and button("MemoryRecap").disabled and not shown("MemoryDisclaimer"),"Enter on 礦燈 shows the empty pedestal (%s): %s"%[tag,label_text("MemoryDetailName")])
	check(focused_name()=="MemoryCard_jinguashi" and (button("MemoryCard_jinguashi") as Button).button_pressed and not (button("MemoryCard_lanyang") as Button).button_pressed,"Focus stays on the chosen card (%s): %s"%[tag,focused_name()])
	layout_ok("empty selected "+tag)
	await key(KEY_LEFT)
	await enter()
	check(label_text("MemoryDetailName")=="分水木牌","Enter back on 分水木牌 (%s)"%tag)
	# Recap pager.
	await key(KEY_DOWN)
	await enter()
	check(shown("MemoryPager") and not shown("MemoryInfo") and label_text("MemoryPageTitle")=="回顧 1／4・回訪的緣由","Pager on page 1 (%s): %s"%[tag,label_text("MemoryPageTitle")])
	check(focused_name()=="MemoryNext" and button("MemoryPrev").disabled and button("MemoryNext").text==UI.NEXT,"Focus on 下一頁, 上一頁 disabled (%s): %s"%[tag,focused_name()])
	layout_ok("recap page 1 "+tag)
	var card_node:=control("MemoryCard_lanyang")
	var card_rect:=card_node.get_global_rect()
	counter=app.session.counter
	await enter()
	await enter()
	check(label_text("MemoryPageTitle")=="回顧 3／4・怎麼調閘" and app.session.counter==counter,"Page 3, nothing sent yet (%s): %s"%[tag,label_text("MemoryPageTitle")])
	check(label_text("MemoryPageLines").contains("大家依序巡看了上游的田、中段的田、田尾的田"),"Page 3 tells the order (%s): %s"%[tag,label_text("MemoryPageLines")])
	layout_ok("recap page 3 "+tag)
	await enter()
	check(app.session.counter==counter+1,"Reaching page 4 sends exactly one action (%s): %d"%[tag,app.session.counter-counter])
	check(seen_record()==["lanyang"],"Server recorded 分水木牌 as seen (%s): %s"%[tag,str(seen_record())])
	check(feedback()==Exhibit.VIEW_OK%"分水木牌","Server reply at the page foot (%s): %s"%[tag,feedback()])
	check(label_text("MemoryPageTitle")=="回顧 4／4・帶回家的紀念" and button("MemoryNext").text==UI.DONE,"Last page: 看完了 (%s)"%tag)
	check(focused_name()=="MemoryNext","Focus stays on the pager button (%s): %s"%[tag,focused_name()])
	check(label_text("MemoryBadge_lanyang")==UI.BADGE_SEEN and label_text("MemorySeenCount")=="看過 1／1 件展出中的展品","Badge clears in place to 已看過 (%s): %s"%[tag,label_text("MemoryBadge_lanyang")])
	check(control("MemoryCard_lanyang")==card_node and card_node.get_global_rect()==card_rect,"The cards do not move after the update (%s)"%tag)
	check(UI.tracker_text(snap())=="" and UI.news_line(snap())=="地方記憶展：1 件展出・0 件還沒看","Tracker line gone, journal line 0 unread (%s)"%tag)
	layout_ok("recap last page "+tag)
	await key(KEY_LEFT)
	check(focused_name()=="MemoryPrev","KEY_LEFT to 上一頁 (%s): %s"%[tag,focused_name()])
	await enter()
	await key(KEY_RIGHT)
	await enter()
	check(label_text("MemoryPageTitle").begins_with("回顧 4／4") and app.session.counter==counter+1,"Back to page 4 again: no second send (%s): %d"%[tag,app.session.counter-counter])
	await enter()
	check(shown("MemoryInfo") and not shown("MemoryPager") and focused_name()=="MemoryRecap","看完了 returns to the exhibit, focus on 翻閱回顧 (%s): %s"%[tag,focused_name()])
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes (%s)"%tag)
	# Re-reading after it is seen: client side only.
	await interact_key()
	check(page_open() and label_text("MemoryBadge_lanyang")==UI.BADGE_SEEN,"Reopened: 已看過 (%s)"%tag)
	counter=app.session.counter
	button("MemoryRecap").grab_focus()
	await enter()
	for i in 3:await enter()
	check(label_text("MemoryPageTitle").begins_with("回顧 4／4") and app.session.counter==counter,"Re-reading sends nothing (%s): %d"%[tag,app.session.counter-counter])
	world_seen_once(tag)
	await stand(FAR)
	check(str((await world_label(UI.POINT)).get("title",""))==UI.TITLE,"World label drops 新 (%s)"%tag)
	await stand(NEAR)
	# Personal hints update in place (written directly).
	await close_page()
	await interact_key()
	var hint_node:=control("MemoryHint")
	write_unlock("ready")
	await refresh()
	check(control("MemoryHint")==hint_node and label_text("MemoryHint")==Exhibit.HINT_UNCLAIMED and label_text("MemoryFirstShare").begins_with("✓"),"Hint updates in place to HINT_UNCLAIMED (%s): %s"%[tag,label_text("MemoryHint")])
	write_completed(true)
	await refresh()
	check(control("MemoryHint")==hint_node and label_text("MemoryHint")==Exhibit.HINT_CLAIMED and label_text("MemoryPlaque").begins_with("✓"),"Hint updates in place to HINT_CLAIMED (%s): %s"%[tag,label_text("MemoryHint")])
	layout_ok("claimed "+tag)
	await close_page()
	# Journal line updates in place while 島嶼近況 is open.
	person().erase(Exhibit.RECORD_KEY)  # PRESET
	await refresh()
	app.LifeTasks.island_news(app)
	await settle()
	news=button("MemoryExhibitNews")
	check(news!=null and news.text.ends_with("1 件還沒看"),"Journal: 1 unread again (%s)"%tag)
	app.session.rates[1].clear()
	app.session.perform(Exhibit.VIEW_ACTION,STAND,"lanyang")
	await refresh()
	check(button("MemoryExhibitNews")==news and news.text=="地方記憶展：1 件展出・0 件還沒看","Journal line updates in place (%s): %s"%[tag,news.text])
	await close_page()

func world_seen_once(tag:String)->void:
	check(seen_record()==["lanyang"],"Exactly one seen entry after re-reading (%s): %s"%[tag,str(seen_record())])

func paused_flow(tag:String)->void:
	await base(true)
	write_completed(false)
	for cell:Vector2i in Exhibit.CANDIDATES:w.state.objects[k(cell)]={"type":"lamp","owner":id,"items":{}}  # PRESET
	await refresh()
	check(not UI.stand_shown(snap()) and Exhibit.paused(snap()),"Paused: no stand (%s)"%tag)
	check((await world_label(UI.POINT)).is_empty(),"No stand label while paused (%s)"%tag)
	await stand(NEAR)
	check(focus()!=UI.POINT,"No stand focus while paused (%s): %s"%[tag,focus()])
	app._festival_menu()
	await settle()
	button("MemoryExhibitEntry").pressed.emit()
	await settle()
	check(page_open(),"Paused page opens from the festival page (%s)"%tag)
	var line:=label_text("MemoryState")
	check(line.contains("(39,26)") and line.contains("(41,23)") and line.contains("(37,22)"),"Paused page lists the cells to clear (%s): %s"%[tag,line])
	layout_ok("paused "+tag)
	var counter:int=app.session.counter
	button("MemoryRecap").grab_focus()
	await enter()
	for i in 3:await enter()
	check(app.session.counter==counter and seen_record().is_empty(),"Paused: reading the recap sends nothing (%s)"%tag)
	layout_ok("paused recap "+tag)
	await close_page()
	for cell:Vector2i in Exhibit.CANDIDATES:w.state.objects.erase(k(cell))
	await refresh()
	check(UI.stand_cell(snap())==STAND,"Stand back after clearing (%s)"%tag)

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	path=OS.get_environment("TEMP").path_join("memory-exhibit-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"看展旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	if not app.playing:note("app.playing was false after host; set true for key input");app.playing=true
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		await locked_flow(tag)
		await empty_flow(tag)
		await display_flow(tag)
		await paused_flow(tag)
		note("size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
