extends SceneTree
## 第 40 章「回訪・旱日分流」＋家園「分流閘」＋「分水木牌」UI test (headless) at 1024×640
## and 1280×800. Same harness as test_table_warmer_ui.gd: real Session host, real
## snapshot round trips.
##
## PRESET / FIXTURE (direct writes, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true
##    is set here (the runner passes no flag for this suite);
##  * UNLOCK FIXTURE written directly: lanyang_life cleared ×3 + donations + repaired,
##    history_memory = {players:{me:{seen ×3, round 3, completed:true}}, plaque:true}
##    (for the not-ready check: seen [], round 0, completed:false); the earned path is
##    covered by test_lanyang_revisit / test_history_journey;
##  * state.lanyang_revisit is ERASED before each size; state.time is set to day 1
##    (spring, dry) or day 3 (rainy in Lanyang);
##  * the local player is teleported by writing region/x/y (no walking or travel);
##  * home: a bench (51,28), a small water network (tank, pipes, three of my gates
##    open / low / closed, three sprinklers) and another player's gate (46,28) are
##    written as objects (state.removed on their tiles where a base resource sits);
##    a second player "鄰居阿岸" is added with World.add_player;
##  * bag counts of the two kits are written for the inventory check;
##  * session rate buckets / action_clock are cleared between my own actions.
## REALLY EXERCISED (local player):
##  * KEY_E through root.push_input -> main._unhandled_input -> _interact at 岔口,
##    上游, 中段/星禾 and 田尾 opens the page (or 觀察水路 / 水圳手記 when it should);
##    KEY_ESCAPE closes; KEY_LEFT / RIGHT / UP / DOWN move focus; KEY_ENTER on the
##    focused gate / 巡看 / 領取 buttons sends revisit_gate / revisit_check /
##    revisit_claim through Session.perform -> World -> snapshot -> in-place update;
##  * the gate, check and claim rules are the server's (no direct revisit writes after
##    the reset): wrong split replies, completion, the plaque in the bag;
##  * home: KEY_E at the bench (recipe lock reason before / after), at my gate (mode
##    buttons with KEY_RIGHT/LEFT + KEY_ENTER -> gate_mode), at the other player's gate
##    (read-only), at the placed plaque (card); placing the plaque: build folio ->
##    「生活」 tab -> slot -> BuildPlace (real mouse clicks) -> real world click;
##  * the backpack detail (InventoryPanel.select_item) of both kits.
## NOT COVERED HERE: world pixels (test_lanyang_revisit_scene.gd); gamepad input (only
## the focus neighbours it uses, through the arrow keys); the non-preview layout; a
## second connected client (the plaque card is the same page for any visitor).
const World=preload("res://scripts/world.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Industry=preload("res://scripts/industry.gd")
const UI=preload("res://scripts/lanyang_revisit_ui.gd")
const GateUI=preload("res://scripts/diversion_gate_ui.gd")
const Art=preload("res://scripts/lanyang_revisit_art.gd")
const AutomationUI=preload("res://scripts/automation_ui.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const OTHER:="revisit-ui-neighbour-7c21"
const DAY:=1440.0
## Standing spots one tile west of each Lanyang cell (as the rules tests).
const GATE_SPOT:=Vector2(32.5,25.5)
const UP_SPOT:=Vector2(32.5,22.5)
const MID_SPOT:=Vector2(32.5,29.5)
const TAIL_SPOT:=Vector2(32.5,32.5)
## Home network: tank T, pipes, gates A (open) / B (low) / C (closed), sprinklers.
const S_A:=Vector2i(46,24)
const G_A:=Vector2i(47,24)
const P_A:=Vector2i(48,24)
const TANK:=Vector2i(49,24)
const P_B:=Vector2i(50,24)
const G_B:=Vector2i(51,24)
const S_B:=Vector2i(52,24)
const P_C:=Vector2i(49,25)
const G_C:=Vector2i(49,26)
const S_C:=Vector2i(49,27)
const OTHER_GATE:=Vector2i(46,28)
const BENCH:=Vector2i(51,28)
const BENCH_SPOT:=Vector2(51.5,29.4)
const GATE_A_SPOT:=Vector2(47.5,25.9)
const OTHER_SPOT:=Vector2(46.5,29.4)
const BUILD_SPOT:=Vector2(42.5,34.5)
const BUILD_CELL:=Vector2i(43,34)
const PLAQUE_SPOT:=Vector2(43.5,35.6)
var app
var w
var id:=""
var path:=""
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
	print("LANYANG_REVISIT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE LANYANG_REVISIT_UI "+message)

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

func layout_name()->String:
	return str((app.modal as Node).get_meta("life_modal_layout","")) if is_instance_valid(app.modal) else ""

func page_open()->bool:
	return layout_name()==UI.LAYOUT

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

func person()->Dictionary:
	return w.state.players[id]

func bag()->Dictionary:
	return person().inventory

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func focused_name()->String:
	var owner:=root.gui_get_focus_owner()
	return str(owner.name) if owner!=null else "none"

func stand(at:Vector2,region:String=World.REGIONS.HOME)->void:
	var p:Dictionary=person()
	p.region=region
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

func act_key(code:Key)->void:
	app.action_clock=0
	app.session.rates[1].clear()
	await key(code)
	await refresh()

func interact_key()->void:
	app.session.rates[1].clear()
	await key(KEY_E)
	await refresh()

func press(name:String,label:String)->bool:
	var b:=button(name)
	check(b!=null and not b.disabled and b.is_visible_in_tree(),"Enabled %s (%s)"%[name,label])
	if b==null or b.disabled:return false
	app.session.rates[1].clear()
	b.grab_focus()
	await create_timer(0.05).timeout
	b.pressed.emit()
	await settle()
	await refresh()
	return true

func mouse_at(point:Vector2)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		event.position=point
		event.global_position=point
		root.push_input(event,true)
		await process_frame

## A real left click in the middle of a control.
func click_control(c:Control)->void:
	if c==null:return
	await mouse_at(c.get_global_rect().get_center())
	await settle()

func click_cell(cell:Vector2i)->void:
	app.action_clock=0
	app.session.rates[1].clear()
	await mouse_at(app.view.screen(Vector2(cell)+Vector2(0.5,0.5))*app.view.view_zoom())
	await refresh()

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

func world_label(id_value:String)->String:
	app.view._process(0.0)
	app.view.queue_redraw()
	await process_frame
	await process_frame
	for entry in app.view.world_labels:
		if str(entry.id)==id_value:return str(entry.title)
	return ""

func tracker()->String:
	return str(app.objective.text) if app.objective!=null else ""

func set_day(day_index:int)->void:
	w.state.time=float(day_index)*DAY+30.0  # PRESET

func k(c:Vector2i)->String:
	return World.key(c)

## Disclosed unlock fixture (see header).
func write_unlock(ready:bool)->void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()
	life.repaired=true
	var seen:=[]
	if ready:
		for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{id:{"seen":seen,"round":3 if ready else 0,"gates":[0,0],"completed":ready}},"plaque":true}

func sprinkler()->Dictionary:
	return {"type":"sprinkler","owner":id,"items":{},"water":0,"enabled":true,"next_water":0.0,"last_water":-1.0}

func clear_tile(c:Vector2i)->void:
	if World.base_resource(c)!="":w.state.removed[k(c)]=true  # PRESET

func write_network()->void:
	var o:Dictionary=w.state.objects
	for c:Vector2i in [S_A,G_A,P_A,TANK,P_B,G_B,S_B,P_C,G_C,S_C,OTHER_GATE]:clear_tile(c)
	o[k(S_A)]=sprinkler();o[k(S_B)]=sprinkler();o[k(S_C)]=sprinkler()
	for c:Vector2i in [P_A,P_B,P_C]:o[k(c)]={"type":"water_pipe","owner":id,"items":{}}
	o[k(TANK)]={"type":"water_tank","owner":id,"items":{},"water":20}
	o[k(G_A)]={"type":"diversion_gate","owner":id,"items":{},"mode":"open"}
	o[k(G_B)]={"type":"diversion_gate","owner":id,"items":{},"mode":"low"}
	o[k(G_C)]={"type":"diversion_gate","owner":id,"items":{},"mode":"closed"}
	o[k(OTHER_GATE)]={"type":"diversion_gate","owner":OTHER,"items":{},"mode":"closed"}

func erase_home()->void:
	for c:Vector2i in [S_A,G_A,P_A,TANK,P_B,G_B,S_B,P_C,G_C,S_C,OTHER_GATE,BUILD_CELL]:w.state.objects.erase(k(c))

# ------------------------------------------------------------------- layout --

## Page inside the viewport, no outer scrolling, every visible label / button / icon
## inside the page and whole, no ellipsis.
func layout_ok(label:String,expected:String=UI.LAYOUT)->void:
	if layout_name()!=expected:
		check(false,"Page %s open for layout: %s (got %s)"%[expected,label,layout_name()])
		return
	var modal:Control=app.modal
	var view_rect:=root.get_visible_rect()
	check(view_rect.encloses(modal.get_global_rect()),"Page fits the viewport (%s) %s"%[label,rect_info(null)])
	var outer:=control("ModalScroll") as ScrollContainer
	check(outer!=null,"Outer scroll container found (%s)"%label)
	if outer!=null:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Outer page needs no scrolling (%s) max=%.0f page=%.0f"%[label,bar.max_value,bar.page])
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect):continue
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the page (%s) %s"%[c.name,label,rect_info(c)])
		if outer!=null and outer.is_ancestor_of(c):check(outer.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the visible scroll area (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not texts().contains("…"),"No ellipsis anywhere in the page (%s)"%label)
	if expected==UI.LAYOUT:
		check(label_text("RevisitDisclaimer")==Revisit.DISCLAIMER and shown("RevisitDisclaimer"),"Fiction disclaimer shown (%s)"%label)

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and owner.is_visible_in_tree(),"Keyboard focus is on a visible button inside the page (%s): %s"%[label,focused_name()])

func gates_disabled(reason:String,label:String)->void:
	var all:=true
	for which in ["a","b"]:
		for level in 4:
			var b:=button("RevisitGate_%s_%d"%[which,level])
			all=all and b!=null and b.disabled and b.tooltip_text==reason
	check(all,"All eight gate buttons disabled with 「%s」 (%s)"%[reason,label])
	# The rain reason is shown once, in the weather line at the top.
	if reason==Revisit.RAINY:check(not shown("RevisitGateReason") and label_text("RevisitWeather")==reason and shown("RevisitWeather"),"Rain reason shown once at the top (%s)"%label)
	else:check(label_text("RevisitGateReason")==reason and shown("RevisitGateReason"),"Gate reason line 「%s」 (%s): %s"%[reason,label,label_text("RevisitGateReason")])

# --------------------------------------------------------------------- flows --

func reset()->void:
	await close_page()
	w.state.erase(Revisit.STATE_KEY)  # PRESET
	write_unlock(true)
	set_day(0)
	erase_home()
	for item in [Revisit.PLAQUE_ITEM,Industry.GATE_KIT]:bag()[item]=0  # PRESET
	w.state.objects[k(BENCH)]={"type":"bench","owner":id,"items":{}}  # PRESET
	clear_tile(BENCH)
	await refresh()

func bench_recipe(label:String,locked:bool)->void:
	await stand(BENCH_SPOT)
	check(str(app.view.interaction_focus())==k(BENCH),"Bench focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	check(layout_name()=="automation_workbench","E at the bench opens the workbench (%s): %s"%[label,layout_name()])
	if layout_name()!="automation_workbench":return
	var entry:Button=null
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Button).text==World.CRAFT[Industry.GATE_KIT].name and (node as Button).toggle_mode:entry=node
	check(entry!=null,"分流閘 recipe listed (%s)"%label)
	if entry!=null:
		entry.pressed.emit()
		await settle()
	var use:=label_text("RecipeUse")
	var craft:=button("CraftRecipe")
	if locked:
		check(use==Industry.GATE_LOCKED,"Locked recipe explains the revisit (%s): %s"%[label,use])
		check(craft!=null and craft.disabled and craft.text=="完成旱日分流後解鎖" and craft.tooltip_text==Industry.GATE_LOCKED,"製作 disabled with the lock (%s): %s"%[label,craft.text if craft else "missing"])
	else:
		check(use==AutomationUI.recipe_use(Industry.GATE_KIT,app) and use.contains("全開、餘水或關閉"),"Unlocked recipe shows its use (%s): %s"%[label,use])
		check(craft!=null and craft.text!="完成旱日分流後解鎖" and craft.tooltip_text.is_empty(),"No lock on 製作 after the revisit (%s): %s"%[label,craft.text if craft else "missing"])
	var icon:=control("RecipeUse")
	if icon!=null:check(not_cut(icon as Label),"Recipe use text whole (%s)"%label)
	await close_page()

func not_ready_flow(label:String)->void:
	write_unlock(false)
	await stand(GATE_SPOT,"lanyang")
	check(str(app.view.interaction_focus())=="memory:33,25","岔口 focused (%s): %s"%[label,str(app.view.interaction_focus())])
	check(await world_label("memory:33,25")=="觀察水路","Not-ready prompt stays 觀察水路 (%s)"%label)
	check(tracker().begins_with("回訪・旱日分流\n先完成自己的第一次分水"),"Tracker asks to finish the first memory (%s): %s"%[label,tracker()])
	await interact_key()
	check(layout_name()=="history_memory","Not ready: E at 岔口 still opens 觀察水路 (%s): %s"%[label,layout_name()])
	await close_page()
	await stand(MID_SPOT,"lanyang")
	check(UI.gardener_prompt(app.session.snapshot).is_empty(),"Not ready: 星禾 keeps 園藝服務 (%s)"%label)
	await interact_key()
	check(layout_name()=="lanyang_garden","Not ready: E at 星禾 opens the canal notes (%s): %s"%[label,layout_name()])
	check(shown("RevisitOpen"),"Canal notes offer 回訪・旱日分流 (%s)"%label)
	if await press("RevisitOpen","canal -> revisit "+label):
		check(page_open(),"Revisit page opens from the canal notes (%s)"%label)
		check(shown("RevisitHold") and label_text("RevisitHoldText")==Revisit.NOT_READY,"Catch-up message (%s): %s"%[label,label_text("RevisitHoldText")])
		check(not shown("RevisitFields") and not shown("RevisitGates") and not shown("RevisitActions"),"No controls before your own first 分水 (%s)"%label)
		check(shown("RevisitMemory"),"Link to the memory page (%s)"%label)
		focus_ok("not ready "+label)
		layout_ok("not ready "+label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes (%s)"%label)
	write_unlock(true)
	await refresh()

func rainy_flow(label:String)->void:
	set_day(2)
	await stand(GATE_SPOT,"lanyang")
	check(Revisit.raining(app.session.snapshot),"Day 3 rains in Lanyang (%s)"%label)
	check(await world_label("memory:33,25")=="岔口分流閘・今天有雨","Rainy prompt at 岔口 (%s)"%label)
	check(tracker().begins_with("回訪・旱日分流\n今天有雨"),"Rainy tracker (%s): %s"%[label,tracker()])
	await interact_key()
	check(page_open(),"E at 岔口 opens the revisit page (%s): %s"%[label,layout_name()])
	if not page_open():return
	check(label_text("RevisitWeather")==Revisit.RAINY and shown("RevisitWeather"),"Rainy explanation (%s): %s"%[label,label_text("RevisitWeather")])
	check(label_text("RevisitDay").contains("第 3 日") and label_text("RevisitDay").contains("小雨"),"Season/day/weather line (%s): %s"%[label,label_text("RevisitDay")])
	gates_disabled(Revisit.RAINY,"rainy "+label)
	check(button("RevisitCheck").disabled and button("RevisitCheck").tooltip_text==Revisit.RAINY and not shown("RevisitCheckReason"),"巡看 waits for a dry day (%s)"%label)
	focus_ok("rainy "+label)
	layout_ok("rainy "+label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the rainy page (%s)"%label)
	set_day(0)
	await refresh()

func waiting_flow(label:String)->void:
	set_day(0)
	w.state.history_memory.players[id].completed_day=0  # PRESET: practice finished today.
	await stand(GATE_SPOT,"lanyang")
	check("明天起" in tracker(),"The tracker says when to return (%s)"%label)
	await interact_key()
	if not page_open():
		check(false,"The waiting page opens (%s)"%label)
		return
	var waiting_modal:Node=app.modal
	check(shown("RevisitHold") and label_text("RevisitHoldText")==Revisit.RETURN_TOMORROW
		and not shown("RevisitGates"),"Waiting shows Xinghe's invitation without gate controls (%s)"%label)
	layout_ok("waiting "+label)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wait-shot-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var path_for_image:=arg.trim_prefix("--wait-shot-dir=").path_join("waiting-"+label+".png")
			check(root.get_texture().get_image().save_png(path_for_image)==OK,"Capture the waiting invitation (%s)"%label)
	set_day(1)
	await refresh()
	check(app.modal==waiting_modal and shown("RevisitGates") and not shown("RevisitHold"),
		"The open page unlocks after midnight (%s)"%label)
	await close_page()
	w.state.history_memory.players[id].erase("completed_day")
	set_day(0)
	await refresh()

func dry_flow(label:String)->void:
	# 星禾 / 中段 before anyone set the gates.
	await stand(MID_SPOT,"lanyang")
	check(str(app.view.interaction_focus())=="gardener","星禾 focused (%s): %s"%[label,str(app.view.interaction_focus())])
	check(await world_label("gardener")=="星禾・旱日分流","星禾 prompt (%s)"%label)
	await interact_key()
	check(page_open(),"E at 星禾 opens the revisit page (%s): %s"%[label,layout_name()])
	if not page_open():return
	check(label_text("RevisitDay").begins_with("春季・第 1 日・宜蘭") and not label_text("RevisitDay").contains("小雨"),"Spring day 1 line (%s): %s"%[label,label_text("RevisitDay")])
	check(label_text("RevisitReason")=="星禾　「"+Revisit.REASONS.spring+"」","Resident reason line (%s): %s"%[label,label_text("RevisitReason")])
	check(not shown("RevisitWeather"),"No rain line on a dry day (%s)"%label)
	check(label_text("RevisitFieldShare_upstream")=="目前 0 份／需要 6 份" and label_text("RevisitFieldShare_middle")=="目前 0 份／需要 4 份" and label_text("RevisitFieldShare_tail")=="目前 12 份／需要 2 份","Three fields show 目前／需要 (%s): %s / %s / %s"%[label,label_text("RevisitFieldShare_upstream"),label_text("RevisitFieldShare_middle"),label_text("RevisitFieldShare_tail")])
	check(label_text("RevisitFieldMark_middle")==UI.MARK_OPEN+"・你在這裡" and label_text("RevisitFieldMark_upstream")==UI.MARK_OPEN,"Marks say ○ 還沒巡看 (%s): %s"%[label,label_text("RevisitFieldMark_middle")])
	gates_disabled(Revisit.WRONG_GATE_CELL,"away from 岔口 "+label)
	var check_button:=button("RevisitCheck")
	check(check_button!=null and check_button.text=="巡看中段的田" and not check_button.disabled,"巡看中段的田 offered (%s)"%label)
	check(label_text("RevisitCheckReason")==Revisit.NO_GATES_TODAY,"Predicts no gates today (%s): %s"%[label,label_text("RevisitCheckReason")])
	check(button("RevisitClaim").disabled and label_text("RevisitClaimReason")==Revisit.NOT_DONE,"領取 waits for completion (%s): %s"%[label,label_text("RevisitClaimReason")])
	check(focused_name()=="RevisitCheck","Focus starts on 巡看 (%s): %s"%[label,focused_name()])
	layout_ok("dry before gates "+label)
	await act_key(KEY_ENTER)
	check(page_open() and feedback()==Revisit.NO_GATES_TODAY,"Server reply: no gates today (%s): %s"%[label,feedback()])
	check(focused_name()=="RevisitCheck","Focus stays on 巡看 (%s): %s"%[label,focused_name()])
	check(not w.state.has(Revisit.STATE_KEY),"Refused check wrote nothing (%s)"%label)
	await key(KEY_ESCAPE)
	# At 岔口: gate a to 3 with the arrow keys and Enter.
	await stand(GATE_SPOT,"lanyang")
	check(await world_label("memory:33,25")=="調整岔口分流閘","岔口 prompt (%s)"%label)
	await interact_key()
	check(page_open(),"E at 岔口 opens the page (%s)"%label)
	if not page_open():return
	check(focused_name()=="RevisitGate_a_0","Focus starts on 上游閘 0 檔 at the fork (%s): %s"%[label,focused_name()])
	check(label_text("RevisitGateReason").is_empty() and not button("RevisitGate_a_3").disabled,"Gates enabled at 岔口 (%s)"%label)
	var modal_before:Node=app.modal
	var field_before:=control("RevisitField_upstream")
	for i in 3:await key(KEY_RIGHT)
	check(focused_name()=="RevisitGate_a_3","KEY_RIGHT ×3 reaches 3 檔 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(Revisit.gates(w.state)==[3,0],"KEY_ENTER sets 上游閘 3 through the server (%s): %s"%[label,str(Revisit.gates(w.state))])
	check(feedback()==Revisit.GATE_OK%["上游閘",3,6,0,6],"Gate reply at the bottom (%s): %s"%[label,feedback()])
	check(app.modal==modal_before and control("RevisitField_upstream")==field_before,"Page updated in place (%s)"%label)
	check(focused_name()=="RevisitGate_a_3","Focus stays on the pressed gate (%s): %s"%[label,focused_name()])
	check(button("RevisitGate_a_3").button_pressed and not button("RevisitGate_a_0").button_pressed,"3 檔 shown as current (%s)"%label)
	check(label_text("RevisitFieldShare_upstream")=="目前 6 份／需要 6 份","Upstream now 6／6 (%s): %s"%[label,label_text("RevisitFieldShare_upstream")])
	check(label_text("RevisitSplit").contains("6／0／6"),"Split line (%s): %s"%[label,label_text("RevisitSplit")])
	# Upstream is within reach of the fork: its check is refused because the others are off.
	await key(KEY_DOWN)
	check(focused_name()=="RevisitCheck" and button("RevisitCheck").text=="巡看上游的田","KEY_DOWN to 巡看上游的田 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(feedback()==Revisit.OTHER_WRONG%["上游的田",6],"Wrong-distribution reply (others) (%s): %s"%[label,feedback()])
	check(Revisit.checked_today(w.state).is_empty(),"Nothing checked (%s)"%label)
	layout_ok("gates 3/0 "+label)
	await key(KEY_ESCAPE)
	# 中段 sees its own shortfall.
	await stand(MID_SPOT,"lanyang")
	await interact_key()
	check(page_open() and focused_name()=="RevisitCheck","Page at 中段 with focus on 巡看 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(feedback()==Revisit.WRONG_SHARE%["中段的田",0,4],"Wrong-distribution reply (this field) (%s): %s"%[label,feedback()])
	await key(KEY_ESCAPE)
	# Back at 岔口: 中段閘 to 2.
	await stand(GATE_SPOT,"lanyang")
	await interact_key()
	check(focused_name()=="RevisitGate_a_3","Focus starts on the current 上游閘 level (%s): %s"%[label,focused_name()])
	for i in 3:await key(KEY_RIGHT)
	check(focused_name()=="RevisitGate_b_2","KEY_RIGHT into 中段閘 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(Revisit.gates(w.state)==[3,2] and Revisit.shares(w.state)==[6,4,2],"中段閘 2 gives 6／4／2 (%s): %s"%[label,str(Revisit.shares(w.state))])
	check(feedback()==Revisit.GATE_OK%["中段閘",2,6,4,2],"Second gate reply (%s): %s"%[label,feedback()])
	check(tracker().begins_with("回訪・旱日分流\n巡看三塊田 0／3"),"Tracker moves on to checking (%s): %s"%[label,tracker()])
	await key(KEY_UP)
	var top:=root.gui_get_focus_owner() as Button
	check(top!=null and top.text.contains("關閉"),"KEY_UP from the gates reaches 關閉 (%s): %s"%[label,top.text if top else "none"])
	await key(KEY_DOWN)
	check(focused_name().begins_with("RevisitGate_a"),"KEY_DOWN from 關閉 back to the gates (%s): %s"%[label,focused_name()])
	await key(KEY_DOWN)
	check(focused_name()=="RevisitCheck","KEY_DOWN to 巡看 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(Revisit.checked_today(w.state)==["upstream"],"Upstream checked through the server (%s): %s"%[label,str(Revisit.checked_today(w.state))])
	check(feedback()==Revisit.CHECK_OK%["上游的田",6,1],"Check reply (%s): %s"%[label,feedback()])
	check(label_text("RevisitFieldMark_upstream")==UI.MARK_DONE and label_text("RevisitProgress")=="今天已巡看 1／3 塊田","✓ 已巡看 and progress (%s): %s / %s"%[label,label_text("RevisitFieldMark_upstream"),label_text("RevisitProgress")])
	check(button("RevisitCheck").disabled and label_text("RevisitCheckReason")==Revisit.ALREADY_CHECKED,"Same field cannot be checked twice (%s)"%label)
	focus_ok("after check "+label)
	layout_ok("one checked "+label)
	await key(KEY_ESCAPE)
	# 中段 and 田尾.
	await stand(MID_SPOT,"lanyang")
	await interact_key()
	await act_key(KEY_ENTER)
	check(Revisit.checked_today(w.state)==["upstream","middle"] and feedback()==Revisit.CHECK_OK%["中段的田",4,2],"Middle checked (%s): %s"%[label,feedback()])
	await key(KEY_ESCAPE)
	await stand(TAIL_SPOT,"lanyang")
	check(await world_label("memory:33,32")=="巡看田尾的田","田尾 prompt (%s)"%label)
	await interact_key()
	check(page_open() and focused_name()=="RevisitCheck" and button("RevisitCheck").text=="巡看田尾的田","Page at 田尾 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(Revisit.completed(w.state) and feedback()==Revisit.COMPLETE_OK,"Third check completes (%s): %s"%[label,feedback()])
	check(page_open(),"Page stays open on completion (%s)"%label)
	check(label_text("RevisitStatus")==UI.STATUS_DONE and label_text("RevisitProgress")=="三塊田都巡看過了","Completion state (%s): %s"%[label,label_text("RevisitStatus")])
	for field in Revisit.FIELDS:check(label_text("RevisitFieldMark_"+field)==UI.MARK_DONE,"%s ✓ (%s)"%[field,label])
	gates_disabled(Revisit.ALREADY_DONE,"completed "+label)
	check(not button("RevisitClaim").disabled,"田尾 is within reach of 星禾: 領取 enabled (%s): %s"%[label,label_text("RevisitClaimReason")])
	focus_ok("completed "+label)
	layout_ok("completed "+label)
	await key(KEY_ESCAPE)
	check(tracker().begins_with("旱日分流完成\n到橋邊找星禾領木牌"),"Tracker sends me to 星禾 (%s): %s"%[label,tracker()])
	check(UI.cell_prompt(app.session.snapshot,Revisit.GATE_CELL)=="旱日分流・已完成" and UI.cell_prompt(app.session.snapshot,Revisit.FIELD_CELLS.tail)=="田尾的田・水已配好","Prompts after completion (%s)"%label)
	# Claim at 星禾.
	await stand(MID_SPOT,"lanyang")
	check(await world_label("gardener")=="向星禾領分水木牌","星禾 claim prompt (%s)"%label)
	await interact_key()
	check(page_open() and focused_name()=="RevisitClaim","Focus starts on 領取分水木牌 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(int(bag().get(Revisit.PLAQUE_ITEM,0))==1 and feedback()==Revisit.CLAIM_OK,"Claim through the server (%s): %s"%[label,feedback()])
	check(label_text("RevisitStatus")==UI.STATUS_CLAIMED and button("RevisitClaim").disabled and label_text("RevisitClaimReason")==Revisit.CLAIMED,"Claimed state (%s): %s"%[label,label_text("RevisitClaimReason")])
	focus_ok("claimed "+label)
	layout_ok("claimed "+label)
	await key(KEY_ESCAPE)
	check(tracker().begins_with("旱日分流完成\n工作台可做分流閘了"),"Tracker points to the workbench (%s): %s"%[label,tracker()])
	await interact_key()
	check(layout_name()=="lanyang_garden" and shown("RevisitOpen"),"After claiming, 星禾 opens the canal notes with the revisit link (%s): %s"%[label,layout_name()])
	check("田尾也聽得到水聲了" in texts(),"Xinghe acknowledges the finished work after the plaque is claimed (%s)"%label)
	await close_page()

func gate_flow(label:String)->void:
	if not w.state.players.has(OTHER):w.add_player(OTHER,"鄰居阿岸")  # PRESET
	write_network()
	await stand(GATE_A_SPOT)
	check(str(app.view.interaction_focus())==k(G_A),"Gate A focused (%s): %s"%[label,str(app.view.interaction_focus())])
	check(await world_label(k(G_A))=="分流閘 · 全開","Gate prompt names the mode (%s)"%label)
	await interact_key()
	check(layout_name()==GateUI.LAYOUT,"E at my gate opens the gate page (%s): %s"%[label,layout_name()])
	if layout_name()!=GateUI.LAYOUT:return
	check(label_text("GateMode")=="目前：全開","Current mode (%s): %s"%[label,label_text("GateMode")])
	check(label_text("GateZone_0")=="小型灑水器（46,24）・優先供水" and label_text("GateZone_1")=="小型灑水器（52,24）・餘水" and label_text("GateZone_2")=="小型灑水器（49,27）・已截斷","Zone list (%s): %s / %s / %s"%[label,label_text("GateZone_0"),label_text("GateZone_1"),label_text("GateZone_2")])
	check(label_text("GateTanks")=="接通 1 個儲水桶" and label_text("GatePool")==GateUI.POOL_NOTE,"Shared pool note (%s)"%label)
	for mode in Industry.GATE_MODES:check(label_text("GateHelp_"+mode)==GateUI.MODE_HELP[mode],"Help line %s (%s)"%[mode,label])
	check(focused_name()=="GateMode_open","Focus on the current mode (%s): %s"%[label,focused_name()])
	layout_ok("gate open "+label,GateUI.LAYOUT)
	await key(KEY_RIGHT)
	check(focused_name()=="GateMode_low","KEY_RIGHT to 餘水 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(str(w.state.objects[k(G_A)].mode)=="low" and label_text("GateMode")=="目前：餘水","KEY_ENTER switches to 餘水 (%s): %s"%[label,label_text("GateMode")])
	check(label_text("GateZone_0")=="小型灑水器（46,24）・餘水","Zone list follows (%s): %s"%[label,label_text("GateZone_0")])
	check(focused_name()=="GateMode_low","Focus stays (%s): %s"%[label,focused_name()])
	await key(KEY_RIGHT)
	await act_key(KEY_ENTER)
	check(str(w.state.objects[k(G_A)].mode)=="closed" and label_text("GateZone_0")=="小型灑水器（46,24）・已截斷","關閉 cuts the far sprinkler (%s): %s"%[label,label_text("GateZone_0")])
	layout_ok("gate closed "+label,GateUI.LAYOUT)
	await key(KEY_LEFT);await key(KEY_LEFT)
	check(focused_name()=="GateMode_open","KEY_LEFT back to 全開 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(str(w.state.objects[k(G_A)].mode)=="open","Back to 全開 (%s)"%label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the gate page (%s)"%label)
	# Another player's gate: read-only.
	await stand(OTHER_SPOT)
	check(str(app.view.interaction_focus())==k(OTHER_GATE),"Neighbour's gate focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	check(layout_name()==GateUI.LAYOUT,"Neighbour's gate page opens (%s)"%label)
	var all_disabled:=true
	for mode in Industry.GATE_MODES:all_disabled=all_disabled and button("GateMode_"+mode)!=null and button("GateMode_"+mode).disabled and button("GateMode_"+mode).tooltip_text==GateUI.NOT_OWNER
	check(all_disabled,"Mode buttons read-only for a visitor (%s)"%label)
	check(label_text("GateOwner").ends_with("的分流閘・只有主人能切換") and feedback()==GateUI.NOT_OWNER,"Owner and read-only note (%s): %s"%[label,label_text("GateOwner")])
	check(label_text("GateMode")=="目前：關閉" and label_text("GateZoneEmpty")==GateUI.NO_CONSUMERS,"Visitor still sees the mode and zones (%s)"%label)
	layout_ok("visitor gate "+label,GateUI.LAYOUT)
	await close_page()

func plaque_flow(label:String)->void:
	await stand(BUILD_SPOT)
	app._build_menu()
	await settle()
	var tab:=button("BuildTab3")
	check(tab!=null and tab.text=="生活","Build folio has the 生活 tab (%s)"%label)
	await click_control(tab)
	var gate_slot:=button("BuildSlot_diversion_gate_3")
	check(gate_slot!=null and gate_slot.is_visible_in_tree(),"分流閘 on the 生活 page (%s)"%label)
	var slot:=button("BuildSlot_water_share_plaque_3")
	check(slot!=null and slot.is_visible_in_tree(),"分水木牌 on the 生活 page (%s)"%label)
	# Scroll the shelf to the slot (as the mouse wheel would), then click it.
	var shelf:Node=slot.get_parent() if slot!=null else null
	while shelf!=null and not shelf is ScrollContainer:shelf=shelf.get_parent()
	if shelf!=null:
		(shelf as ScrollContainer).ensure_control_visible(slot)
		await settle()
		check((shelf as Control).get_global_rect().grow(0.5).encloses(slot.get_global_rect()),"分水木牌 slot scrolled into view (%s)"%label)
	await click_control(slot)
	check(label_text("BuildTitle")=="分水木牌","Recipe card shows 分水木牌 after a click (%s): %s"%[label,label_text("BuildTitle")])
	var place:=button("BuildPlace")
	check(place!=null and not place.disabled,"BuildPlace enabled (%s)"%label)
	await click_control(place)
	check(str(app.building)==Revisit.PLAQUE_KIND and str(app.selected)=="build" and not is_instance_valid(app.modal),"Build tool armed with 分水木牌 by clicks (%s): %s %s"%[label,app.building,app.selected])
	await click_cell(BUILD_CELL)
	var obj:Dictionary=w.state.objects.get(k(BUILD_CELL),{})
	check(str(obj.get("type",""))==Revisit.PLAQUE_KIND and str(obj.get("owner",""))==id,"Click placed 分水木牌 (%s): %s"%[label,str(obj)])
	check(int(bag().get(Revisit.PLAQUE_ITEM,0))==0 and not w.blocked(BUILD_CELL),"Kit used; plaque does not block (%s)"%label)
	app._select_tool("hoe")
	await stand(PLAQUE_SPOT)
	check(str(app.view.interaction_focus())==k(BUILD_CELL),"Plaque focused (%s): %s"%[label,str(app.view.interaction_focus())])
	check(await world_label(k(BUILD_CELL))==Revisit.PLAQUE_NAME,"Plaque prompt (%s)"%label)
	await interact_key()
	check(layout_name()==GateUI.PLAQUE_LAYOUT,"E at the plaque opens its card (%s): %s"%[label,layout_name()])
	check(label_text("PlaqueName")==Revisit.PLAQUE_NAME and label_text("PlaqueBlurb")==Revisit.PLAQUE_BLURB and label_text("PlaqueSource")==Revisit.PLAQUE_SOURCE and label_text("PlaqueProject")==Revisit.PLAQUE_PROJECT,"Card texts (%s): %s"%[label,texts().replace("\n"," | ")])
	var pic:=control("PlaqueIcon") as TextureRect
	check(pic!=null and pic.texture==Art.plaque_texture(),"Card shows the plaque art (%s)"%label)
	layout_ok("plaque card "+label,GateUI.PLAQUE_LAYOUT)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the card (%s)"%label)

func inventory_flow(label:String)->void:
	bag()[Revisit.PLAQUE_ITEM]=1  # PRESET
	bag()[Industry.GATE_KIT]=2  # PRESET
	await refresh()
	app._inventory()
	await settle()
	check(app.modal is InventoryPanel,"Backpack opens (%s)"%label)
	if app.modal is InventoryPanel:
		var panel=app.modal
		panel.select_item(Revisit.PLAQUE_ITEM)
		await settle()
		check(panel.detail_name.text=="分水木牌" and panel.detail_count.text=="持有 1","Plaque name and count (%s): %s %s"%[label,panel.detail_name.text,panel.detail_count.text])
		check(panel.detail_use.text.begins_with("紀念物・") and panel.detail_use.text.contains("「生活」") and panel.detail_use.text.contains(app.binding_label("build_menu")),"Plaque usage line (%s): %s"%[label,panel.detail_use.text])
		check(panel.detail_value.text=="紀念物・不能出售或交易","Plaque value line (%s): %s"%[label,panel.detail_value.text])
		check(panel.detail_icon.texture==Items.icon(Revisit.PLAQUE_ITEM) and panel.detail_icon.texture!=Items.icon("plank"),"Plaque icon is its own art (%s)"%label)
		check(not_cut(panel.detail_use) and not_cut(panel.detail_value) and (panel as Control).get_global_rect().grow(0.5).encloses(panel.detail_use.get_global_rect()),"Plaque texts whole (%s)"%label)
		panel.select_item(Industry.GATE_KIT)
		await settle()
		check(panel.detail_name.text=="分流閘" and panel.detail_count.text=="持有 2","Gate kit name and count (%s): %s %s"%[label,panel.detail_name.text,panel.detail_count.text])
		check(panel.detail_use.text.contains("全開、餘水或關閉") and panel.detail_use.text.contains(app.binding_label("interact")),"Gate kit usage line (%s): %s"%[label,panel.detail_use.text])
		check(panel.detail_icon.texture==Items.icon(Industry.GATE_KIT) and panel.detail_icon.texture!=Items.icon("pipe_kit"),"Gate kit icon is its own art (%s)"%label)
		check(not_cut(panel.detail_use),"Gate kit text whole (%s)"%label)
	await close_page()

func size_flow(label:String)->void:
	await reset()
	await bench_recipe("locked "+label,true)
	await not_ready_flow(label)
	await waiting_flow(label)
	await rainy_flow(label)
	await dry_flow(label)
	await bench_recipe("unlocked "+label,false)
	await gate_flow(label)
	await plaque_flow(label)
	await inventory_flow(label)

func pure_checks()->void:
	var s:Dictionary={"time":30.0}
	check(UI.tracker_text(s).is_empty() and UI.cell_prompt(s,Revisit.GATE_CELL).is_empty(),"No tracker / prompt before the plaque")
	check(UI.home_hint({"lanyang_revisit":{"completed":true},"players":{"me":{"inventory":{}}},"objects":{}},"me")==UI.HOME_HINT,"Home hint after completion without a gate")
	check(UI.home_hint({"lanyang_revisit":{"completed":true},"players":{"me":{"inventory":{}}},"objects":{"1,1":{"type":"diversion_gate","owner":"me"}}},"me").is_empty(),"No home hint once a gate is placed")
	check(UI.home_hint({"players":{"me":{"inventory":{}}},"objects":{}},"me").is_empty(),"No home hint before completion")

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	pure_checks()
	path=OS.get_environment("TEMP").path_join("lanyang-revisit-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"分水旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	if not app.playing:note("app.playing was false after host; set true for key input");app.playing=true
	await refresh()
	if WanganUI.card_open(app):
		await key(KEY_E)
		check(not WanganUI.card_open(app),"First E closes the arrival card")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		await size_flow(tag)
		note("size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
		if failures>40:break
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
