extends SceneTree
## 第 40 章家園「水塔」UI test (headless) at 1024×640 and 1280×800. Same harness as
## test_lanyang_revisit_ui.gd: real Session host, real snapshot round trips.
##
## PRESET / FIXTURE (direct writes, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true
##    is set here (the runner passes no flag for this suite);
##  * UNLOCK FIXTURE written directly: lanyang_life cleared ×3 + donations + repaired,
##    history_memory {me: seen ×3, round 3, completed} + plaque, and (for the unlocked
##    part only) state.lanyang_revisit = {completed:true, checked ×3, gates [3,2]}; the
##    locked part ERASES state.lanyang_revisit. The earned path is covered by
##    test_lanyang_revisit / test_water_tower_journey;
##  * the local player is teleported by writing region/x/y (no walking);
##  * home: a bench (51,28) and a small network written as objects:
##      y=24:  S_A(44)  P1(45)  TOWER(46)  GATE(47)  S_N(48)  TANK(49)
##    (tank water 48, sprinklers enabled with 0 water, tower water 0 / enabled, gate open)
##    plus another player's tower (46,28) with water 30 / 只蓄水; a second player
##    "鄰居阿岸" is added with World.add_player; state.removed on tiles with a base resource;
##  * the tank is ERASED directly once to show the "no tank" refill wording;
##  * bag counts of water_tower_kit are written for the inventory and placement checks;
##  * session rate buckets / action_clock are cleared between my own actions;
##  * the network refill runs through a real World.step after writing
##    state.next_network_check = state.time (the session's physics step is off).
## REALLY EXERCISED (local player):
##  * KEY_E through root.push_input -> main._unhandled_input -> _interact opens the tower
##    page (mine / the neighbour's / the one I placed) and the gate page; KEY_ESCAPE closes;
##    KEY_UP / KEY_DOWN move focus; KEY_ENTER on the focused toggle sends tower_toggle
##    through Session.perform -> World -> snapshot -> in-place update + reply line;
##  * gate_mode (low / closed / open) and remove (the tower) are real Session.perform calls;
##  * workbench (KEY_E at the bench) and build folio lock reasons before the revisit;
##  * placing a tower: build folio -> 「生活」 tab -> slot -> BuildPlace (real mouse clicks)
##    -> real world click;
##  * the backpack detail (InventoryPanel.select_item) of water_tower_kit.
## NOT COVERED HERE: world pixels (test_water_tower_scene.gd); gamepad input (only the
## focus neighbours it uses, through the arrow keys); the non-preview (legacy) layout; a
## second connected client (the visitor page is driven by the local player looking at a
## tower another player owns).
const World=preload("res://scripts/world.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Industry=preload("res://scripts/industry.gd")
const TowerUI=preload("res://scripts/water_tower_ui.gd")
const GateUI=preload("res://scripts/diversion_gate_ui.gd")
const Art=preload("res://scripts/water_tower_art.gd")
const AutomationUI=preload("res://scripts/automation_ui.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const OTHER:="tower-ui-neighbour-58e2"
const S_A:=Vector2i(44,24)
const P1:=Vector2i(45,24)
const TOWER:=Vector2i(46,24)
const GATE:=Vector2i(47,24)
const S_N:=Vector2i(48,24)
const TANK:=Vector2i(49,24)
const OTHER_TOWER:=Vector2i(46,28)
const BENCH:=Vector2i(51,28)
const BENCH_SPOT:=Vector2(51.5,29.4)
const TOWER_SPOT:=Vector2(46.3,25.6)
const GATE_SPOT:=Vector2(47.6,25.7)
const OTHER_SPOT:=Vector2(46.5,29.4)
const BUILD_SPOT:=Vector2(42.5,34.5)
const BUILD_CELL:=Vector2i(43,34)
const BUILT_SPOT:=Vector2(43.5,35.6)
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
	print("WATER_TOWER_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE WATER_TOWER_UI "+message)

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
	return layout_name()==TowerUI.LAYOUT

func texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

func consumer_lines()->Array:
	var out:=[]
	var list:=control("TowerConsumers")
	if list==null:return out
	for child in list.get_children():
		if child is Label and not (child as Node).is_queued_for_deletion() and child.name.begins_with("TowerConsumer_"):out.append((child as Label).text)
	out.sort()
	return out

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

func perform(action:String,cell:Vector2i,extra:String="")->void:
	app.action_clock=0
	app.session.rates[1].clear()
	app.session.perform(action,cell,extra)
	await refresh()

func mouse_at(point:Vector2)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		event.position=point
		event.global_position=point
		root.push_input(event,true)
		await process_frame

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

func k(c:Vector2i)->String:
	return World.key(c)

func obj(c:Vector2i)->Dictionary:
	return w.state.objects.get(k(c),{})

## Disclosed unlock fixture (see header).
func write_unlock(done:bool)->void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()
	life.repaired=true
	var seen:=[]
	for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{id:{"seen":seen,"round":3,"gates":[0,0],"completed":true}},"plaque":true}
	if done:w.state[Revisit.STATE_KEY]={"gates":[3,2],"day":0,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}}
	else:w.state.erase(Revisit.STATE_KEY)

func sprinkler()->Dictionary:
	return {"type":"sprinkler","owner":id,"items":{},"water":0,"enabled":true,"next_water":0.0,"last_water":-1.0}

func clear_tile(c:Vector2i)->void:
	if World.base_resource(c)!="":w.state.removed[k(c)]=true  # PRESET

func write_network()->void:
	var o:Dictionary=w.state.objects
	for c:Vector2i in [S_A,P1,TOWER,GATE,S_N,TANK,OTHER_TOWER]:clear_tile(c)
	o[k(S_A)]=sprinkler();o[k(S_N)]=sprinkler()
	o[k(P1)]={"type":"water_pipe","owner":id,"items":{}}
	o[k(TOWER)]={"type":"water_tower","owner":id,"items":{},"water":0,"enabled":true}
	o[k(GATE)]={"type":"diversion_gate","owner":id,"items":{},"mode":"open"}
	o[k(TANK)]={"type":"water_tank","owner":id,"items":{},"water":48}
	o[k(OTHER_TOWER)]={"type":"water_tower","owner":OTHER,"items":{},"water":30,"enabled":false}

func erase_home()->void:
	for c:Vector2i in [S_A,P1,TOWER,GATE,S_N,TANK,OTHER_TOWER,BUILD_CELL]:w.state.objects.erase(k(c))

# ------------------------------------------------------------------- layout --

## Page inside the viewport, no outer scrolling, every visible label / button / icon
## inside the page and whole, no ellipsis.
func layout_ok(label:String,expected:String=TowerUI.LAYOUT)->void:
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
		if not (c is BaseButton or c is Label or c is TextureRect or c is ProgressBar):continue
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the page (%s) %s"%[c.name,label,rect_info(c)])
		if outer!=null and outer.is_ancestor_of(c):check(outer.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the visible scroll area (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not texts().contains("…"),"No ellipsis anywhere in the page (%s)"%label)

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and owner.is_visible_in_tree(),"Keyboard focus is on a visible button inside the page (%s): %s"%[label,focused_name()])

# --------------------------------------------------------------------- flows --

func reset()->void:
	await close_page()
	write_unlock(false)
	erase_home()
	bag()[Industry.TOWER_KIT]=0  # PRESET
	w.state.objects[k(BENCH)]={"type":"bench","owner":id,"items":{}}  # PRESET
	clear_tile(BENCH)
	await refresh()

func find_recipe(name:String)->Button:
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Button).text==name and (node as Button).toggle_mode:return node
	return null

func bench_recipe(label:String,locked:bool)->void:
	await stand(BENCH_SPOT)
	await interact_key()
	check(layout_name()=="automation_workbench","E at the bench opens the workbench (%s): %s"%[label,layout_name()])
	if layout_name()!="automation_workbench":return
	var entry:=find_recipe(World.CRAFT[Industry.TOWER_KIT].name)
	check(entry!=null,"水塔 recipe listed (%s)"%label)
	if entry!=null:
		entry.pressed.emit()
		await settle()
	var use:=label_text("RecipeUse")
	var craft:=button("CraftRecipe")
	if locked:
		check(use==Industry.TOWER_LOCKED,"Locked recipe explains the revisit (%s): %s"%[label,use])
		check(craft!=null and craft.disabled and craft.text=="完成旱日分流後解鎖" and craft.tooltip_text==Industry.TOWER_LOCKED,"製作 disabled with the lock (%s): %s"%[label,craft.text if craft else "missing"])
	else:
		check(use==AutomationUI.recipe_use(Industry.TOWER_KIT,app) and use!=Industry.TOWER_LOCKED,"Unlocked recipe shows its use (%s): %s"%[label,use])
		check(craft!=null and craft.text!="完成旱日分流後解鎖" and craft.tooltip_text.is_empty(),"No lock on 製作 after the revisit (%s): %s"%[label,craft.text if craft else "missing"])
	check(not_cut(control("RecipeUse") as Label),"Recipe use text whole (%s)"%label)
	await close_page()

## Build folio -> 生活 tab -> 水塔 slot by real clicks. Returns the BuildPlace button.
func folio_tower(label:String)->Button:
	app._build_menu()
	await settle()
	var tab:=button("BuildTab3")
	check(tab!=null and tab.text=="生活","Build folio has the 生活 tab (%s)"%label)
	await click_control(tab)
	var slot:=button("BuildSlot_water_tower_3")
	check(slot!=null and slot.is_visible_in_tree(),"水塔 on the 生活 page (%s)"%label)
	if slot==null:return null
	var shelf:Node=slot.get_parent()
	while shelf!=null and not shelf is ScrollContainer:shelf=shelf.get_parent()
	if shelf!=null:
		(shelf as ScrollContainer).ensure_control_visible(slot)
		await settle()
		check((shelf as Control).get_global_rect().grow(0.5).encloses(slot.get_global_rect()),"水塔 slot scrolled into view (%s)"%label)
	await click_control(slot)
	check(label_text("BuildTitle")=="水塔","Recipe card shows 水塔 after a click (%s): %s"%[label,label_text("BuildTitle")])
	return button("BuildPlace")

func locked_flow(label:String)->void:
	await bench_recipe("locked "+label,true)
	await stand(BUILD_SPOT)
	var place:=await folio_tower("locked "+label)
	check(place!=null and place.disabled and place.text=="完成旱日分流","工坊 BuildPlace locked (%s): %s"%[label,place.text if place else "missing"])
	check(label_text("BuildDescription")==Industry.TOWER_LOCKED,"工坊 lock reason (%s): %s"%[label,label_text("BuildDescription")])
	await close_page()

func owner_flow(label:String)->void:
	if not w.state.players.has(OTHER):w.add_player(OTHER,"鄰居阿岸")  # PRESET
	write_network()
	await stand(TOWER_SPOT)
	check(str(app.view.interaction_focus())==k(TOWER),"Tower focused (%s): %s"%[label,str(app.view.interaction_focus())])
	check(await world_label(k(TOWER))=="水塔 · 水 0／96 · 出水","Tower prompt names water and mode (%s): %s"%[label,await world_label(k(TOWER))])
	await interact_key()
	check(page_open(),"E at my tower opens the tower page (%s): %s"%[label,layout_name()])
	if not page_open():return
	check(label_text("TowerWater")=="存水 0／96" and (control("TowerBar") as ProgressBar).value==0.0,"Empty tower (%s): %s"%[label,label_text("TowerWater")])
	check(label_text("TowerMode")=="目前：出水" and button("TowerToggle").text=="改為只蓄水" and not button("TowerToggle").disabled,"Mode and toggle (%s): %s / %s"%[label,label_text("TowerMode"),button("TowerToggle").text])
	check(label_text("TowerOwner")=="你的水塔・接在自己的水管上" and label_text("TowerModeHelp")==TowerUI.MODE_HELP[true],"Owner and mode help (%s)"%label)
	check(label_text("TowerRefill")==TowerUI.REFILL.full and label_text("TowerTanks")=="接通 1 個儲水桶","Refill full zone wording (%s): %s / %s"%[label,label_text("TowerRefill"),label_text("TowerTanks")])
	check(consumer_lines()==["小型灑水器（44,24）","小型灑水器（48,24）"] and not shown("TowerConsumerEmpty"),"Open gate: both sprinklers listed (%s): %s"%[label,str(consumer_lines())])
	check(label_text("TowerAbout")==TowerUI.ABOUT and feedback()=="Esc 回到島上","About text and footer (%s): %s"%[label,feedback()])
	check(focused_name()=="TowerToggle","Focus starts on the toggle (%s): %s"%[label,focused_name()])
	var icon:=control("TowerIcon") as TextureRect
	check(icon!=null and icon.texture==Art.tower_texture(0,true),"Icon shows the empty 出水 tower (%s)"%label)
	layout_ok("owner full "+label)
	# Real refill: World.step moves the tank's leftover water into the tower.
	var modal_before:Node=app.modal
	var water_before:=control("TowerWater")
	w.state.next_network_check=float(w.state.time)  # PRESET (step timing)
	w.step(1.0,true)
	await refresh()
	var stored:=int(obj(TOWER).get("water",-1))
	check(stored==24 and int(obj(S_A).water)==12 and int(obj(S_N).water)==12 and int(obj(TANK).water)==0,"Real step: sprinklers 12 each, tower 24 (%s): tower %d"%[label,stored])
	check(label_text("TowerWater")=="存水 %d／96"%stored and is_equal_approx((control("TowerBar") as ProgressBar).value,float(stored)),"Page follows the refill in place (%s): %s"%[label,label_text("TowerWater")])
	check(app.modal==modal_before and control("TowerWater")==water_before,"Same page and nodes after the step (%s)"%label)
	check(icon.texture==Art.tower_texture(Art.level_of(stored),true),"Icon shows the new level (%s)"%label)
	check(focused_name()=="TowerToggle","Focus kept through the refresh (%s): %s"%[label,focused_name()])
	# KEY_UP to 關閉 and back, then KEY_ENTER toggles through the server.
	await key(KEY_UP)
	var top:=root.gui_get_focus_owner() as Button
	check(top!=null and top.text.contains("關閉"),"KEY_UP from the toggle reaches 關閉 (%s): %s"%[label,top.text if top else "none"])
	await key(KEY_DOWN)
	check(focused_name()=="TowerToggle","KEY_DOWN back to the toggle (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(obj(TOWER).get("enabled")==false,"KEY_ENTER sets 只蓄水 through the server (%s)"%label)
	check(feedback()=="水塔已設為「只蓄水」","Server reply at the bottom (%s): %s"%[label,feedback()])
	check(label_text("TowerMode")=="目前：只蓄水" and button("TowerToggle").text=="改為出水" and label_text("TowerModeHelp")==TowerUI.MODE_HELP[false],"Page shows 只蓄水 (%s): %s"%[label,label_text("TowerMode")])
	check(icon.texture==Art.tower_texture(Art.level_of(stored),false),"Icon switches to the 只蓄水 look (%s)"%label)
	check(app.modal==modal_before and focused_name()=="TowerToggle","Updated in place, focus stays (%s): %s"%[label,focused_name()])
	layout_ok("owner 只蓄水 "+label)
	await act_key(KEY_ENTER)
	check(obj(TOWER).get("enabled")==true and feedback()=="水塔已設為「出水」" and label_text("TowerMode")=="目前：出水","Back to 出水 (%s): %s"%[label,feedback()])
	# Gate 餘水: tower refills only after the tank side; its outflow stops at the gate.
	await perform(Industry.GATE_ACTION,GATE,"low")
	check(str(obj(GATE).mode)=="low","Gate set to 餘水 (%s)"%label)
	check(page_open() and label_text("TowerRefill")==TowerUI.REFILL.low,"Refill low zone wording (%s): %s"%[label,label_text("TowerRefill")])
	check(consumer_lines()==["小型灑水器（44,24）"],"餘水 gate blocks the tower's outflow to 48,24 (%s): %s"%[label,str(consumer_lines())])
	layout_ok("owner low "+label)
	await perform(Industry.GATE_ACTION,GATE,"closed")
	check(label_text("TowerRefill")==TowerUI.REFILL.cut and consumer_lines()==["小型灑水器（44,24）"],"Refill cut wording (%s): %s"%[label,label_text("TowerRefill")])
	layout_ok("owner cut "+label)
	# Empty list caused by the closed gate: the only sprinkler on the tower's side goes away.
	var kept:Dictionary=obj(S_A).duplicate(true)
	w.state.objects.erase(k(S_A))  # PRESET
	await refresh()
	check(consumer_lines().is_empty() and label_text("TowerConsumerEmpty")==TowerUI.NO_CONSUMERS and shown("TowerConsumerEmpty"),"Closed gate, nothing on this side: empty line (%s): %s"%[label,label_text("TowerConsumerEmpty")])
	layout_ok("owner cut empty "+label)
	w.state.objects[k(S_A)]=kept  # PRESET
	await perform(Industry.GATE_ACTION,GATE,"open")
	# No tank on the pipe.
	var tank:Dictionary=obj(TANK).duplicate(true)
	w.state.objects.erase(k(TANK))  # PRESET
	await refresh()
	check(label_text("TowerRefill")==TowerUI.REFILL.none and label_text("TowerTanks")=="接通 0 個儲水桶","Refill none wording (%s): %s"%[label,label_text("TowerRefill")])
	check(consumer_lines()==["小型灑水器（44,24）","小型灑水器（48,24）"],"Without a tank the tower still feeds both (%s): %s"%[label,str(consumer_lines())])
	layout_ok("owner none "+label)
	w.state.objects[k(TANK)]=tank  # PRESET
	await refresh()
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the tower page (%s)"%label)
	# The sprinkler page adds one line for the towers on its pipe.
	await stand(Vector2(44.5,25.6))
	check(str(app.view.interaction_focus())==k(S_A),"Sprinkler focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	var supply:Label=null
	if is_instance_valid(app.modal):
		for node in (app.modal as Node).find_children("*","Label",true,false):
			if (node as Label).text.contains("水塔 1 座"):supply=node
	var expected:="接通 1 桶 · 管網水量 %d／48\n水塔 1 座 · 存水 %d／96"%[int(obj(TANK).water),int(obj(TOWER).water)]
	check(supply!=null and supply.text==expected and supply.is_visible_in_tree() and not_cut(supply),"Sprinkler page tower line (%s): %s"%[label,supply.text if supply else texts().replace("\n"," | ")])
	await key(KEY_ESCAPE)

func gate_flow(label:String)->void:
	await stand(GATE_SPOT)
	check(str(app.view.interaction_focus())==k(GATE),"Gate focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	check(layout_name()==GateUI.LAYOUT,"E at the gate opens the gate page (%s): %s"%[label,layout_name()])
	if layout_name()!=GateUI.LAYOUT:return
	check(shown("GateTowerTitle") and label_text("GateTower_0")=="水塔（46,24）・優先補水","Gate page lists the tower (open) (%s): %s"%[label,label_text("GateTower_0")])
	layout_ok("gate with tower open "+label,GateUI.LAYOUT)
	await key(KEY_RIGHT)
	await act_key(KEY_ENTER)
	check(str(obj(GATE).mode)=="low" and label_text("GateTower_0")=="水塔（46,24）・餘水才補","Tower row follows 餘水 (%s): %s"%[label,label_text("GateTower_0")])
	await key(KEY_RIGHT)
	await act_key(KEY_ENTER)
	check(str(obj(GATE).mode)=="closed" and label_text("GateTower_0")=="水塔（46,24）・補不到水","Tower row follows 關閉 (%s): %s"%[label,label_text("GateTower_0")])
	layout_ok("gate with tower closed "+label,GateUI.LAYOUT)
	await perform(Industry.GATE_ACTION,GATE,"open")
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the gate page (%s)"%label)

func visitor_flow(label:String)->void:
	await stand(OTHER_SPOT)
	check(str(app.view.interaction_focus())==k(OTHER_TOWER),"Neighbour's tower focused (%s): %s"%[label,str(app.view.interaction_focus())])
	check(await world_label(k(OTHER_TOWER))=="水塔 · 水 30／96 · 只蓄水","Neighbour's tower prompt (%s)"%label)
	await interact_key()
	check(page_open(),"Neighbour's tower page opens (%s)"%label)
	if not page_open():return
	var toggle:=button("TowerToggle")
	check(toggle!=null and toggle.disabled and toggle.tooltip_text==TowerUI.NOT_OWNER,"Toggle read-only for a visitor (%s)"%label)
	# The neighbour is not a connected peer, so the public snapshot carries no name for them.
	check(label_text("TowerOwner")=="另一位島民的水塔・只有主人能切換" and feedback()==TowerUI.NOT_OWNER,"Owner and read-only note (%s): %s / %s"%[label,label_text("TowerOwner"),feedback()])
	check(label_text("TowerWater")=="存水 30／96" and label_text("TowerMode")=="目前：只蓄水","Visitor sees water and mode (%s)"%label)
	check(label_text("TowerRefill")==TowerUI.REFILL.none and label_text("TowerConsumerEmpty")==TowerUI.NO_CONSUMERS,"Lone tower: no tank, nothing to supply (%s)"%label)
	focus_ok("visitor "+label)
	layout_ok("visitor "+label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the visitor page (%s)"%label)

func place_flow(label:String)->void:
	bag()[Industry.TOWER_KIT]=1  # PRESET
	await refresh()
	await stand(BUILD_SPOT)
	var place:=await folio_tower("unlocked "+label)
	check(place!=null and not place.disabled,"BuildPlace enabled (%s)"%label)
	await click_control(place)
	check(str(app.building)==Industry.TOWER_KIND and str(app.selected)=="build" and not is_instance_valid(app.modal),"Build tool armed with 水塔 by clicks (%s): %s %s"%[label,app.building,app.selected])
	await click_cell(BUILD_CELL)
	var placed:=obj(BUILD_CELL)
	check(str(placed.get("type",""))==Industry.TOWER_KIND and str(placed.get("owner",""))==id and int(placed.get("water",-1))==0 and placed.get("enabled")==true,"Click placed a 水塔 (%s): %s"%[label,str(placed)])
	check(int(bag().get(Industry.TOWER_KIT,0))==0 and w.blocked(BUILD_CELL),"Kit used; the tower blocks walking (%s)"%label)
	app._select_tool("hoe")
	await stand(BUILT_SPOT)
	check(str(app.view.interaction_focus())==k(BUILD_CELL),"Placed tower focused (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact_key()
	check(page_open() and label_text("TowerWater")=="存水 0／96" and label_text("TowerRefill")==TowerUI.REFILL.none,"Placed tower page (%s): %s"%[label,label_text("TowerRefill")])
	# Remove it while the page is open (real remove action): the page says so in place.
	await perform("remove",BUILD_CELL)
	check(not w.state.objects.has(k(BUILD_CELL)) and int(bag().get(Industry.TOWER_KIT,0))==1,"Removed through the server, kit back (%s)"%label)
	check(page_open() and label_text("TowerWater")==TowerUI.GONE and shown("TowerWater"),"Page shows the removed state (%s): %s"%[label,label_text("TowerWater")])
	check(not shown("TowerToggle") and not shown("TowerBar") and not shown("TowerRefillCard") and not shown("TowerSupplyCard") and feedback().begins_with(TowerUI.GONE),"No toggle / bar / list once removed (%s): %s"%[label,feedback()])
	focus_ok("removed "+label)
	layout_ok("removed "+label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the removed page (%s)"%label)

func inventory_flow(label:String)->void:
	bag()[Industry.TOWER_KIT]=2  # PRESET
	await refresh()
	app._inventory()
	await settle()
	check(app.modal is InventoryPanel,"Backpack opens (%s)"%label)
	if app.modal is InventoryPanel:
		var panel=app.modal
		panel.select_item(Industry.TOWER_KIT)
		await settle()
		check(panel.detail_name.text=="水塔" and panel.detail_count.text=="持有 2","Tower kit name and count (%s): %s %s"%[label,panel.detail_name.text,panel.detail_count.text])
		check(panel.detail_use.text.contains("出水或只蓄水") and panel.detail_use.text.contains("「生活」") and panel.detail_use.text.contains(app.binding_label("interact")) and panel.detail_use.text.contains(app.binding_label("build_menu")),"Tower kit usage line (%s): %s"%[label,panel.detail_use.text])
		check(panel.detail_icon.texture==Items.icon(Industry.TOWER_KIT) and panel.detail_icon.texture!=null and panel.detail_icon.texture!=Items.icon("tank_kit") and panel.detail_icon.texture!=Items.icon(Industry.GATE_KIT),"Tower kit icon is its own art (%s)"%label)
		check(not_cut(panel.detail_use) and (panel as Control).get_global_rect().grow(0.5).encloses(panel.detail_use.get_global_rect()),"Tower kit text whole (%s)"%label)
	await close_page()

func size_flow(label:String)->void:
	await reset()
	await locked_flow(label)
	write_unlock(true)
	await refresh()
	await bench_recipe("unlocked "+label,false)
	await owner_flow(label)
	await gate_flow(label)
	await visitor_flow(label)
	await place_flow(label)
	await inventory_flow(label)

func pure_checks()->void:
	check(Art.level_of(0)==0 and Art.level_of(1)==1 and Art.level_of(48)==2 and Art.level_of(95)==3 and Art.level_of(96)==4,"Water levels: empty / partly / full")
	check(TowerUI.refill_text("bogus")==TowerUI.REFILL.none,"Unknown zone falls back to the no-tank wording")
	check(GateUI.tower_line({"key":"1,2","zone":"low"})=="水塔（1,2）・餘水才補","Gate page tower row text")

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	pure_checks()
	path=OS.get_environment("TEMP").path_join("water-tower-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"水塔旅人",path)!=OK:check(false,"Host starts");finish();return
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
