extends SceneTree
## T071 紀念品交換攤 UI test (headless) at 1024×640 and 1280×800. Same harness as
## test_showcase_ui.gd: real Session host, real snapshot round trips.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true
##    is set here (the runner passes no flag for this suite);
##  * state.board=true and state.picnic written directly (false for the locked checks);
##  * TICKETS ARE SEEDED BY DIRECT WRITES: player.harvest_relay / fish_meet / showcase
##    records are replaced by {"tickets":N,"rounds":N,"best":0,"paid_round":1} (no
##    activity round is played; the save is never reloaded here). player.souvenir, the
##    seven *_kit items and every souvenir object are erased before each size;
##  * the local player is teleported by writing region/x/y (no walking);
##  * the paused page writes three lamp objects onto the booth candidates directly;
##  * the long-balance check writes 999999 tickets (rounds 999999) and 12345 kits of
##    one kind into my bag directly;
##  * session rate buckets / action_clock are cleared between my own actions.
## REALLY EXERCISED (local player):
##  * KEY_E through root.push_input -> main._unhandled_input -> _interact at the booth
##    opens the page (and does nothing before the picnic); Esc closes; KEY_UP / DOWN /
##    LEFT / RIGHT focus navigation; KEY_ENTER on a focused 兌換 button redeems; the
##    other 兌換 presses grab focus and emit `pressed` (as the sibling suites) —
##    every redemption is a real Session.perform -> World -> snapshot -> page update;
##  * the 紀念品交換攤 entries on 渡口派對 · 風鈴接力 and the 公告板 (pressed), the
##    「我的紀錄」 note on the three activity pages, the backpack detail of a kit;
##  * placing a redeemed decoration: build folio (app._build_menu) -> 「生活」 tab ->
##    the decoration's slot -> BuildPlace (all `pressed`) -> a real left click on a
##    world cell through root.push_input -> build action -> world object.
## NOT COVERED HERE: world pixels (test_souvenir_exchange_scene.gd); gamepad input
## (the focus neighbours it uses are checked); the non-preview layout.
const World=preload("res://scripts/world.gd")
const Souv=preload("res://scripts/souvenir_exchange.gd")
const SouvUI=preload("res://scripts/souvenir_exchange_ui.gd")
const HarvestUI=preload("res://scripts/harvest_relay_ui.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const BOOTH:=Vector2i(37,25)
const BOOTH_SPOT:=Vector2(37.5,27.5)   # 2.0 from the booth, nothing else closer
const FAR_SPOT:=Vector2(37.5,29.7)     # 4.2 from the booth: label visible, not focused
const BUILD_SPOT:=Vector2(42.5,34.5)
const BUILD_CELL:=Vector2i(43,34)
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
	print("SOUVENIR_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE SOUVENIR_UI "+message)

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
	return is_instance_valid(app.modal) and str((app.modal as Node).get_meta("life_modal_layout",""))==SouvUI.LAYOUT

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
	return SouvUI.own(app.session.snapshot)

func person()->Dictionary:
	return w.state.players[id]

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func toast()->String:
	return str((app.toast as Label).text) if app.toast!=null and is_instance_valid(app.toast) else ""

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

func press(name:String,label:String)->bool:
	var b:=control(name) as BaseButton
	check(b!=null and not b.disabled,"Enabled %s (%s)"%[name,label])
	if b==null or b.disabled:return false
	app.session.rates[1].clear()
	b.grab_focus()
	await create_timer(0.05).timeout
	b.pressed.emit()
	await settle()
	await refresh()
	return true

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

func kit(entry:String)->int:
	return int((person().inventory as Dictionary).get(Souv.item_of(entry),0))

func balance(activity:String)->int:
	return int((own().get("balance",{}) as Dictionary).get(activity,-1))

# ------------------------------------------------------------------- layout --

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
	var names:=["SouvenirRule","SouvenirPlaceHint"]
	for activity:String in Souv.ACTIVITIES:names.append_array(["SouvenirGroupName_"+activity,"SouvenirBalance_"+activity,"SouvenirLedger_"+activity])
	for entry:String in Souv.ENTRY_ORDER:
		for part in ["SouvenirIcon_","SouvenirName_","SouvenirBlurb_","SouvenirCost_","SouvenirCounts_","SouvenirState_","SouvenirRedeem_"]:names.append(part+entry)
	for name in names:
		var c:=control(name)
		check(c!=null and c.is_visible_in_tree(),"%s present (%s)"%[name,label])
		if c==null:continue
		check(view_rect.encloses(c.get_global_rect()) and modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside viewport and page (%s) %s"%[name,label,rect_info(c)])
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect):continue
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the page (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not texts().contains("…"),"No ellipsis anywhere in the page (%s)"%label)
	for activity in Souv.ACTIVITIES+["trio"]:
		var row:=control("SouvenirRow_"+activity)
		check(row!=null and row.get_combined_minimum_size().x<=row.size.x+0.5,"Row %s does not overflow (%s)"%[activity,label])
	# Cards of one row never overlap and every icon is a real 32×32 picture.
	for entry:String in Souv.ENTRY_ORDER:
		var icon:=control("SouvenirIcon_"+entry) as TextureRect
		check(icon!=null and icon.texture!=null and icon.texture.get_size()==Vector2(32,32),"%s icon is a 32×32 picture (%s)"%[entry,label])

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton,"Keyboard focus is on a button inside the page (%s): %s"%[label,focused_name()])

## Every entry shows its name, blurb, cost text and counts; the state line and the
## 兌換 button agree with the server view.
func entries_ok(label:String,expect_reason:String="")->void:
	var m:=own()
	for e:Dictionary in m.get("entries",[]):
		var entry:=str(e.id)
		check(label_text("SouvenirName_"+entry)==str(Souv.ENTRIES[entry].name),"%s name (%s)"%[entry,label])
		check(label_text("SouvenirBlurb_"+entry)==str(Souv.ENTRIES[entry].blurb),"%s blurb (%s)"%[entry,label])
		check(label_text("SouvenirCost_"+entry)==Souv.cost_text(entry),"%s cost text (%s): %s"%[entry,label,label_text("SouvenirCost_"+entry)])
		var counts:="背包 %d・已擺 %d・換過 %d"%[int(e.held),int(e.placed),int(e.redeemed)]
		check(label_text("SouvenirCounts_"+entry)==counts,"%s counts 「%s」 (%s): %s"%[entry,counts,label,label_text("SouvenirCounts_"+entry)])
		var b:=button("SouvenirRedeem_"+entry)
		if b==null:
			check(false,"%s button present (%s)"%[entry,label])
			continue
		check(b.text=="兌換","%s button says 兌換 (%s)"%[entry,label])
		var short:Dictionary=e.short
		if not short.is_empty():
			var want:=SouvUI.short_text(short)
			check(b.disabled and b.tooltip_text==want and label_text("SouvenirState_"+entry)==want,"%s disabled with 「%s」 (%s): %s / %s"%[entry,want,label,b.tooltip_text,label_text("SouvenirState_"+entry)])
		elif not expect_reason.is_empty():
			check(b.disabled and b.tooltip_text==expect_reason and label_text("SouvenirState_"+entry)=="票數足夠","%s disabled with the page reason (%s): %s"%[entry,label,b.tooltip_text])
		else:
			check(not b.disabled and label_text("SouvenirState_"+entry)=="票數足夠","%s enabled, 票數足夠 (%s): %s"%[entry,label,b.tooltip_text])
	for row:Dictionary in m.get("activities",[]):
		var activity:=str(row.id)
		check(label_text("SouvenirBalance_"+activity)=="剩 %d 張"%int(row.balance),"%s balance 剩 %d 張 (%s): %s"%[activity,int(row.balance),label,label_text("SouvenirBalance_"+activity)])
		check(label_text("SouvenirLedger_"+activity)=="獲得 %d・已用 %d"%[int(row.earned),int(row.spent)],"%s ledger (%s): %s"%[activity,label,label_text("SouvenirLedger_"+activity)])

## An entry page gains no outer scrolling from the new entry (overflow with the entry
## equals the overflow with it removed) and every entry caption stays whole.
func page_fits(label:String)->void:
	if not is_instance_valid(app.modal):
		check(false,"Page open: "+label)
		return
	var modal:Control=app.modal
	check(root.get_visible_rect().encloses(modal.get_global_rect()),"Entry page fits the viewport (%s)"%label)
	var outer:=control("ModalScroll") as ScrollContainer
	var entry:=button("SouvenirEntry")
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
		check(with_entry<=without+1.0,"The 紀念品交換攤 entry adds no outer scrolling (%s): %.0f vs %.0f"%[label,with_entry,without])
	if entry!=null:
		# The 公告板 is an ordinary scrolling page: scroll to each target the way keyboard
		# focus / the wheel does, then require the whole control (and its text, not
		# trimmed) inside the actual scroll viewport and the page.
		if outer!=null:
			outer.ensure_control_visible(entry)
			await settle()
			check(outer.get_global_rect().grow(0.5).encloses(entry.get_global_rect()),"紀念品交換攤 entry reachable by scrolling inside the visible scroll area (%s) %s"%[label,rect_info(entry)])
		check(modal.get_global_rect().grow(0.5).encloses(entry.get_global_rect()) and button_not_cut(entry),"紀念品交換攤 entry whole inside the page (%s)"%label)
		for other in ["HarvestRelayEntry","HarvestRelayBoardEntry","FishingMeetEntry","ShowcaseEntry"]:
			var b:=button(other)
			if b!=null:
				if outer!=null:
					outer.ensure_control_visible(b)
					await settle()
					check(outer.get_global_rect().grow(0.5).encloses(b.get_global_rect()),"%s reachable by scrolling inside the visible scroll area (%s) %s"%[other,label,rect_info(b)])
				check(button_not_cut(b) and modal.get_global_rect().grow(0.5).encloses(b.get_global_rect()),"%s caption still whole (%s)"%[other,label])

func entry_opens(page:String,label:String,locked:bool)->void:
	var entry:=button("SouvenirEntry")
	var expect_text:=SouvUI.ENTRY_LOCKED if locked else SouvUI.ENTRY_OPEN
	check(entry!=null and entry.text==expect_text,"%s lists 紀念品交換攤%s (%s): %s"%[page,"（鎖定）" if locked else "",label,entry.text if entry else "missing"])
	if entry==null:return
	await page_fits(page+" "+label)
	entry=button("SouvenirEntry")
	entry.pressed.emit()
	await settle()
	check(page_open(),"%s entry opens the 紀念品交換攤 page (%s)"%[page,label])
	if locked:
		check(label_text("SouvenirLocked")==Souv.LOCKED and control("SouvenirRedeem_veg_basket_rack")==null,"Locked page from %s shows the lock (%s): %s"%[page,label,label_text("SouvenirLocked")])
		check(label_text("SouvenirRule")==SouvUI.RULE,"Locked page explains the booth (%s)"%label)

# ------------------------------------------------------------------- fixture --

func reset()->void:
	var p:Dictionary=person()
	p.erase("souvenir")  # PRESET
	for item:String in Souv.items():(p.inventory as Dictionary).erase(item)
	for k in (w.state.objects as Dictionary).keys():
		if Souv.is_kind(str(w.state.objects[k].get("type",""))) or World.cell(str(k)) in Souv.CANDIDATES:w.state.objects.erase(k)

## PRESET: tickets by direct write (see the header).
func seed_tickets(n:int)->void:
	for field in ["harvest_relay","fish_meet","showcase"]:
		if n<=0:person().erase(field)
		else:person()[field]={"tickets":n,"rounds":n,"best":0,"paid_round":1}
	await refresh()

func set_picnic(on:bool)->void:
	w.state.board=true  # PRESET
	w.state.picnic=on   # PRESET
	await refresh()

# --------------------------------------------------------------------- flows --

func locked_flow(label:String)->void:
	await close_page()
	reset()
	await seed_tickets(0)
	await set_picnic(false)
	check(not SouvUI.booth_shown(app.session.snapshot) and not bool(own().get("unlocked",true)) and own().get("point")==Souv.NO_CELL,"Locked before the picnic (%s)"%label)
	await stand(BOOTH_SPOT)
	check(focus()!=SouvUI.POINT,"No booth focus before the picnic (%s): %s"%[label,focus()])
	check((await world_label(SouvUI.POINT)).is_empty(),"No booth world label before the picnic (%s)"%label)
	await interact_key()
	check(not page_open(),"E at the booth spot before the picnic opens no 紀念品交換攤 (%s)"%label)
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
	check(SouvUI.booth_shown(app.session.snapshot) and SouvUI.booth_cell(app.session.snapshot)==BOOTH and own().get("point")==BOOTH,"Booth at (37,25) after the picnic (%s)"%label)
	app._festival_menu()
	await settle()
	await entry_opens("風鈴接力活動頁",label,false)
	await close_page()
	app._board()
	await settle()
	await entry_opens("公告板",label,false)
	await close_page()
	# World label and focus.
	await stand(FAR_SPOT)
	var idle:=await world_label(SouvUI.POINT)
	check(str(idle.get("title",""))==SouvUI.TITLE,"Booth world label 「紀念品交換攤」 from afar (%s): %s"%[label,str(idle)])
	check(focus()!=SouvUI.POINT,"Not focused from 4.2 tiles (%s): %s"%[label,focus()])
	await stand(BOOTH_SPOT)
	check(focus()==SouvUI.POINT,"Standing south of the booth focuses it (%s): %s"%[label,focus()])
	var focused:=await world_label(SouvUI.POINT)
	check(str(focused.get("title",""))=="兌換紀念品","Focused booth prompt keeps the action concise (%s): %s"%[label,str(focused)])
	check(World.souvenir_cell(app.session.snapshot)==BOOTH and w.blocked(BOOTH) and w.protected(BOOTH),"Booth cell blocks and is protected (%s)"%label)
	# Nothing affordable.
	await interact_key()
	check(page_open(),"E at the booth opens 紀念品交換攤 (%s) texts=%s"%[label,texts().left(60).replace("\n"," | ")])
	if not page_open():return
	check(not app._world_keyboard_allowed(),"World keys blocked while the page is open (%s)"%label)
	await settle()
	focus_ok("nothing affordable "+label)
	check(focused_name()=="SouvenirRedeem_veg_basket_rack","Focus starts on the first 兌換 (%s): %s"%[label,focused_name()])
	entries_ok("nothing affordable "+label)
	check(label_text("SouvenirState_trio_keepsake")=="還差 豐收接力 3、河岸釣魚會 3、家園布置題 3 張","Mixed entry lists all three shortfalls (%s): %s"%[label,label_text("SouvenirState_trio_keepsake")])
	check(label_text("SouvenirPlaceHint").contains("家園工坊") and label_text("SouvenirPlaceHint").contains("「生活」") and label_text("SouvenirPlaceHint").contains(app.binding_label("build_menu")),"Placing hint names the build folio and 生活 (%s): %s"%[label,label_text("SouvenirPlaceHint")])
	check(not control("SouvenirHint").visible and not control("SouvenirBlocked").visible,"No blocker line at the booth (%s)"%label)
	layout_ok("nothing affordable "+label)
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the page (%s)"%label)
	# Partly affordable: 5 / 3 / 0.
	for field in ["harvest_relay","fish_meet"]:person()[field]={"tickets":5 if field=="harvest_relay" else 3,"rounds":5 if field=="harvest_relay" else 3,"best":0,"paid_round":1}
	await refresh()
	await interact_key()
	entries_ok("partly affordable "+label)
	check(label_text("SouvenirState_relay_crate_stack")=="還差 豐收接力 1 張" and button("SouvenirRedeem_relay_crate_stack").disabled and not button("SouvenirRedeem_veg_basket_rack").disabled,"還差 豐收接力 1 張 on 接力菜箱堆 (%s): %s"%[label,label_text("SouvenirState_relay_crate_stack")])
	await close_page()
	# Everything affordable: 12 / 12 / 12 (exactly enough for all seven once).
	await seed_tickets(12)
	await interact_key()
	check(page_open(),"Page reopens (%s)"%label)
	await settle()
	entries_ok("all affordable "+label)
	layout_ok("all affordable "+label)
	check(focused_name()=="SouvenirRedeem_veg_basket_rack","Focus on the first 兌換 (%s): %s"%[label,focused_name()])
	# Focus grid.
	await key(KEY_RIGHT)
	check(focused_name()=="SouvenirRedeem_relay_crate_stack","KEY_RIGHT inside the 豐收接力 row (%s): %s"%[label,focused_name()])
	await key(KEY_DOWN)
	check(focused_name()=="SouvenirRedeem_float_garland","KEY_DOWN keeps the column (%s): %s"%[label,focused_name()])
	await key(KEY_DOWN)
	check(focused_name()=="SouvenirRedeem_flower_arch","KEY_DOWN to the 家園布置題 row (%s): %s"%[label,focused_name()])
	await key(KEY_DOWN)
	check(focused_name()=="SouvenirRedeem_trio_keepsake","KEY_DOWN to the mixed entry (%s): %s"%[label,focused_name()])
	await key(KEY_UP)
	check(focused_name()=="SouvenirRedeem_lantern_post","KEY_UP clamps to the first column (%s): %s"%[label,focused_name()])
	await key(KEY_LEFT)
	check(focused_name()=="SouvenirRedeem_flower_arch","KEY_LEFT wraps inside the row (%s): %s"%[label,focused_name()])
	await key(KEY_UP);await key(KEY_UP)
	check(focused_name()=="SouvenirRedeem_relay_crate_stack","KEY_UP twice to the first row (%s): %s"%[label,focused_name()])
	await key(KEY_UP)
	var up:=root.gui_get_focus_owner() as Button
	check(up!=null and up.text.contains("關閉"),"KEY_UP from the first row reaches 關閉 (%s): %s"%[label,up.text if up else "none"])
	await key(KEY_DOWN)
	check(focused_name()=="SouvenirRedeem_veg_basket_rack","KEY_DOWN from 關閉 returns to the list (%s): %s"%[label,focused_name()])
	await key(KEY_RIGHT)
	# KEY_ENTER on the focused 接力菜箱堆.
	var card_rect:=control("SouvenirCard_relay_crate_stack").get_global_rect()
	var card_node:=control("SouvenirCard_relay_crate_stack")
	var bag_before:Dictionary=(person().inventory as Dictionary).duplicate(true)
	var coins_before:=int(person().coins)
	app.session.rates[1].clear()
	await key(KEY_ENTER)
	await refresh()
	check(kit("relay_crate_stack")==1 and balance("harvest_relay")==6,"KEY_ENTER on 兌換 redeems 接力菜箱堆 (%s): kit %d balance %d %s"%[label,kit("relay_crate_stack"),balance("harvest_relay"),toast()])
	check(feedback().contains("換到「接力菜箱堆」"),"Result message in the page (%s): %s"%[label,feedback()])
	check(focused_name()=="SouvenirRedeem_relay_crate_stack","Focus stays on the pressed 兌換 (%s): %s"%[label,focused_name()])
	check(control("SouvenirCard_relay_crate_stack")==card_node and control("SouvenirCard_relay_crate_stack").get_global_rect()==card_rect,"The list does not move after redeeming (%s)"%label)
	check(label_text("SouvenirBalance_harvest_relay")=="剩 6 張" and label_text("SouvenirLedger_harvest_relay")=="獲得 12・已用 6","Balance updates to 6 (%s): %s / %s"%[label,label_text("SouvenirBalance_harvest_relay"),label_text("SouvenirLedger_harvest_relay")])
	check(label_text("SouvenirCounts_relay_crate_stack")=="背包 1・已擺 0・換過 1","Counts update (%s): %s"%[label,label_text("SouvenirCounts_relay_crate_stack")])
	check(int(person().coins)==coins_before,"Coins untouched (%s)"%label)
	# Pressing the rest; after 菜籃小架 the crate stack runs short.
	for entry:String in ["veg_basket_rack","carp_banner","float_garland","lantern_post","flower_arch","trio_keepsake"]:
		if not await press("SouvenirRedeem_"+entry,label):continue
		check(kit(entry)==1,"%s redeemed (%s): %s"%[entry,label,feedback()])
		check(feedback().contains("換到「%s」"%str(Souv.ENTRIES[entry].name)),"%s result shown (%s): %s"%[entry,label,feedback()])
		check(focused_name()=="SouvenirRedeem_"+entry,"Focus stays on %s (%s): %s"%[entry,label,focused_name()])
		if entry=="veg_basket_rack":
			check(button("SouvenirRedeem_relay_crate_stack").disabled and label_text("SouvenirState_relay_crate_stack")=="還差 豐收接力 3 張","接力菜箱堆 now short by 3 (%s): %s"%[label,label_text("SouvenirState_relay_crate_stack")])
	for activity:String in Souv.ACTIVITIES:check(balance(activity)==0,"%s balance 0 after all seven (%s)"%[activity,label])
	check(button("SouvenirRedeem_trio_keepsake").disabled and focused_name()=="SouvenirRedeem_trio_keepsake","The pressed button keeps focus even when it becomes disabled (%s): %s"%[label,focused_name()])
	entries_ok("all redeemed "+label)
	layout_ok("all redeemed "+label)
	var bag_after:Dictionary=(person().inventory as Dictionary).duplicate(true)
	for item:String in Souv.items():bag_after.erase(item)
	check(bag_after==bag_before,"Only the seven kits were added to the bag (%s)"%label)
	await key(KEY_ESCAPE)
	# Long balances and a big kit count.
	person().inventory["veg_basket_rack_kit"]=12345  # PRESET
	await seed_tickets(999999)
	await interact_key()
	check(label_text("SouvenirBalance_harvest_relay")=="剩 999987 張" and label_text("SouvenirLedger_fish_meet")=="獲得 999999・已用 12","Long balances shown (%s): %s / %s"%[label,label_text("SouvenirBalance_harvest_relay"),label_text("SouvenirLedger_fish_meet")])
	check(label_text("SouvenirCounts_veg_basket_rack")=="背包 12345・已擺 0・換過 1","Big kit count (%s): %s"%[label,label_text("SouvenirCounts_veg_basket_rack")])
	layout_ok("long balances "+label)
	await close_page()
	person().inventory["veg_basket_rack_kit"]=1
	await seed_tickets(12)
	# Too far: page opened from the board entry, buttons disabled with WALK.
	await stand(FAR_SPOT)
	person().harvest_relay={"tickets":15,"rounds":15,"best":0,"paid_round":1}  # PRESET: 3 harvest left
	await refresh()
	app._board()
	await settle()
	button("SouvenirEntry").pressed.emit()
	await settle()
	check(page_open(),"Board entry opens the page from afar (%s)"%label)
	check(label_text("SouvenirHint")==SouvUI.WALK and control("SouvenirHint").visible,"Hint asks to walk to the booth (%s): %s"%[label,label_text("SouvenirHint")])
	entries_ok("too far "+label,SouvUI.WALK)
	layout_ok("too far "+label)
	await close_page()
	# Paused: all three candidate cells occupied.
	for cell:Vector2i in Souv.CANDIDATES:w.state.objects[World.key(cell)]={"type":"lamp","owner":id,"items":{}}  # PRESET
	await refresh()
	check(not SouvUI.booth_shown(app.session.snapshot) and own().get("point")==Souv.NO_CELL and not bool(own().get("can_redeem",true)),"Paused: booth hidden (%s)"%label)
	check((await world_label(SouvUI.POINT)).is_empty(),"No booth label while paused (%s)"%label)
	await stand(BOOTH_SPOT)
	check(focus()!=SouvUI.POINT,"No booth focus while paused (%s): %s"%[label,focus()])
	app._board()
	await settle()
	button("SouvenirEntry").pressed.emit()
	await settle()
	check(page_open(),"Paused page opens from the board (%s)"%label)
	check(label_text("SouvenirHint")==Souv.NO_POINT,"Paused hint (%s): %s"%[label,label_text("SouvenirHint")])
	var blocked:=label_text("SouvenirBlocked")
	check(control("SouvenirBlocked").visible and blocked.contains("(37,25)") and blocked.contains("(35,26)") and blocked.contains("(39,24)"),"Paused page lists the cells to clear (%s): %s"%[label,blocked])
	entries_ok("paused "+label,Souv.NO_POINT)
	layout_ok("paused "+label)
	await close_page()
	for cell:Vector2i in Souv.CANDIDATES:w.state.objects.erase(World.key(cell))
	await refresh()
	check(SouvUI.booth_shown(app.session.snapshot),"Booth back after clearing (%s)"%label)
	# 「我的紀錄」 note on the three activity pages.
	for page:Array in [["harvest",func():app._harvest_menu(),"HarvestSouvenirNote","harvest_relay"],["fishing meet",func():app._fishmeet_menu(),"FishMeetSouvenirNote","fishing_meet"],["showcase",func():app._showcase_menu(),"ShowcaseSouvenirNote","showcase"]]:
		(page[1] as Callable).call()
		await settle()
		var l:=control(page[2]) as Label
		check(l!=null and l.text==HarvestUI.SOUVENIR_NOTE and l.is_visible_in_tree() and not_cut(l) and (app.modal as Control).get_global_rect().grow(0.5).encloses(l.get_global_rect()),"%s page notes the booth beside 我的紀錄 (%s): %s"%[page[0],label,l.text if l else "missing"])
		var outer:=control("ModalScroll") as ScrollContainer
		if outer!=null:check(outer.get_v_scroll_bar().max_value<=outer.get_v_scroll_bar().page+1.0,"%s page still needs no outer scrolling (%s)"%[page[0],label])
		await close_page()
	# Backpack detail of a kit.
	app._inventory()
	await settle()
	check(app.modal is InventoryPanel,"Backpack opens (%s)"%label)
	if app.modal is InventoryPanel:
		var panel=app.modal
		panel.select_item("lantern_post_kit")
		await settle()
		check(panel.detail_name.text=="紙燈籠柱" and panel.detail_count.text=="持有 1","Kit name and count (%s): %s %s"%[label,panel.detail_name.text,panel.detail_count.text])
		check(panel.detail_use.text=="紀念裝飾・按 %s 打開家園工坊，在「生活」分頁選它擺到家園。不擋路，拆除會收回背包。"%app.binding_label("build_menu"),"Kit usage line (%s): %s"%[label,panel.detail_use.text])
		check(panel.detail_value.text=="紀念票兌換的紀念品 · 不能出售或交易" and not panel.detail_value.text.contains("攤位未收購"),"Kit value line (%s): %s"%[label,panel.detail_value.text])
		check(not_cut(panel.detail_use) and not_cut(panel.detail_value) and (panel as Control).get_global_rect().grow(0.5).encloses(panel.detail_use.get_global_rect()),"Kit texts whole (%s)"%label)
		check(panel.detail_icon.texture!=null and panel.detail_icon.texture.get_size()==Vector2(32,32),"Kit icon in the detail (%s)"%label)
	await close_page()
	# Place a decoration through the build folio and a real click.
	await stand(BUILD_SPOT)
	app._build_menu()
	await settle()
	var tab:=button("BuildTab3")
	check(tab!=null and tab.text=="生活","Build folio has the 生活 tab (%s)"%label)
	if tab!=null:
		tab.pressed.emit()
		await settle()
	var slot:=button("BuildSlot_lantern_post_3")
	check(slot!=null and slot.is_visible_in_tree(),"紙燈籠柱 is on the 生活 page (%s)"%label)
	if slot!=null:
		slot.pressed.emit()
		await settle()
	check(control("BuildTitle")!=null and label_text("BuildTitle")=="紙燈籠柱","Recipe card shows 紙燈籠柱 (%s): %s"%[label,label_text("BuildTitle")])
	var place:=button("BuildPlace")
	check(place!=null and not place.disabled,"BuildPlace enabled (%s)"%label)
	if place!=null:
		place.pressed.emit()
		await settle()
	check(str(app.building)=="lantern_post" and str(app.selected)=="build" and not is_instance_valid(app.modal),"Build tool armed with 紙燈籠柱 (%s): %s %s"%[label,app.building,app.selected])
	await click(BUILD_CELL)
	var obj:Dictionary=w.state.objects.get(World.key(BUILD_CELL),{})
	check(str(obj.get("type",""))=="lantern_post" and str(obj.get("owner",""))==id,"Click placed 紙燈籠柱 at %s (%s): %s %s"%[str(BUILD_CELL),label,str(obj),toast()])
	check(kit("lantern_post")==0 and not w.blocked(BUILD_CELL),"Kit used up; the decoration does not block (%s)"%label)
	var placed_entry:Dictionary={}
	for e:Dictionary in own().get("entries",[]):
		if str(e.id)=="lantern_post":placed_entry=e
	check(int(placed_entry.get("placed",0))==1 and int(placed_entry.get("held",-1))==0,"own_souvenir counts the placed decoration (%s): %s"%[label,str(placed_entry)])
	app._select_tool("hoe")
	await stand(BOOTH_SPOT)
	await interact_key()
	check(label_text("SouvenirCounts_lantern_post")=="背包 0・已擺 1・換過 1","Page shows 已擺 1 (%s): %s"%[label,label_text("SouvenirCounts_lantern_post")])
	await close_page()
	w.state.objects.erase(World.key(BUILD_CELL))

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	path=OS.get_environment("TEMP").path_join("souvenir-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"兌換旅人",path)!=OK:check(false,"Host starts");finish();return
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
