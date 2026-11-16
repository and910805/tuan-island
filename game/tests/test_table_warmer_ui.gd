extends SceneTree
## T067 共餐桌保溫底座 UI test (headless) at 1024×640 and 1280×800. Same harness as
## test_souvenir_exchange_ui.gd: real Session host, real snapshot round trips.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true
##    is set here (the runner passes no flag for this suite);
##  * state.board=true, state.picnic=true and state.community={"table":"39,30"} written
##    directly; state.table_warmer is ERASED directly before each size (un-install);
##    community dishes are erased directly when a step needs an empty table;
##  * BAGS ARE WRITTEN DIRECTLY: warm_stone / copper_joint / stone / trout_hotpot /
##    watermelon_platter counts are set per step (short: 2/1/4; ready: 6/2/4; hotpot 4
##    or 6; watermelon_platter 4); no mining, cooking or crafting is played here;
##  * the local player is teleported by writing region/x/y (no walking): TABLE_SPOT
##    (39.5,31.6) south of the table; mine_12 rest station for the source check, with
##    state.mine_depths={"unlocked":13,...,"hoist":true} written directly;
##  * session rate buckets / action_clock are cleared between my own actions.
## REALLY EXERCISED (local player):
##  * the fresh host's 望安 arrival card is closed by a first real KEY_E (as in play);
##  * KEY_E through root.push_input -> main._unhandled_input -> _interact at the table
##    opens the page; KEY_ESCAPE closes it; KEY_UP / DOWN / LEFT / RIGHT move focus;
##    KEY_ENTER on the focused 加裝保溫底座 / 保溫上桌六份 / 領一份 sends the action;
##    the plain 上桌四份 / 領一份 presses grab focus and emit `pressed`. Every action is a
##    real Session.perform -> World -> snapshot -> main._state_changed -> page update;
##  * the backpack detail (InventoryPanel.select_item) for 暖岩片;
##  * the mine rest-station card (MineUI.open(app,"rest")) on B12/B13.
## NOT COVERED HERE: world pixels (test_table_warmer_scene.gd); gamepad input (only the
## focus neighbours it uses are exercised through the arrow keys); the non-preview layout.
const World=preload("res://scripts/world.gd")
const Warmer=preload("res://scripts/table_warmer.gd")
const UI=preload("res://scripts/community_ui.gd")
const MineUI=preload("res://scripts/mine_ui.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const TABLE:=Vector2i(39,30)
const TABLE_SPOT:=Vector2(39.5,31.6)
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
	print("TABLE_WARMER_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE TABLE_WARMER_UI "+message)

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

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

func set_bag(values:Dictionary)->void:
	for item:String in values:bag()[item]=int(values[item])  # PRESET
	await refresh()

func hotpot()->Dictionary:
	return w.state.community.get("hotpot",{})

# ------------------------------------------------------------------- layout --

## Page inside the viewport, no outer scrolling, every visible label / button / icon
## inside the page and whole, the 保溫底座 controls inside their card.
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
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect):continue
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the page (%s) %s"%[c.name,label,rect_info(c)])
		if outer!=null and outer.is_ancestor_of(c):check(outer.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the visible scroll area (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not texts().contains("…"),"No ellipsis anywhere in the page (%s)"%label)
	var card:=control("WarmerCard")
	check(card!=null and card.is_visible_in_tree(),"保溫底座 card shown (%s)"%label)
	if card!=null:
		for name in ["WarmerIcon","WarmerTitle","WarmerStatus","WarmerRule","WarmerInstall","WarmerSource","WarmerReason","WarmerMaterials"]:
			var c:=control(name)
			if c!=null and c.is_visible_in_tree():check(card.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the 保溫底座 card (%s) %s"%[name,label,rect_info(c)])
	for name in ["DishMain_hotpot","HotpotWarm","DishMain_watermelon"]:
		var row:=control("Dish_hotpot" if name!="DishMain_watermelon" else "Dish_watermelon")
		var b:=control(name)
		if b!=null and b.is_visible_in_tree() and row!=null:check(row.get_combined_minimum_size().x<=row.size.x+0.5 and row.get_global_rect().grow(0.5).encloses(b.get_global_rect()),"%s inside its dish row (%s)"%[name,label])
	for route in ["渡口來信","生活訂單","風鈴接力","公共廚房"]:
		var found:=false
		for node in modal.find_children("*","Button",true,false):
			if (node as Button).text==route and (node as Control).is_visible_in_tree():found=true
		check(found,"Route %s still on the page (%s)"%[route,label])
	var icon:=control("WarmerIcon") as TextureRect
	check(icon!=null and icon.texture!=null and icon.texture.get_size()==Vector2(32,32),"暖岩片 icon is a 32×32 picture (%s)"%label)

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and owner.is_visible_in_tree(),"Keyboard focus is on a visible button inside the page (%s): %s"%[label,focused_name()])

func materials_ok(label:String,have:Dictionary)->void:
	for item:String in Warmer.COST_ORDER:
		var want:="%s %d／%d"%[Warmer.ITEM_NAMES[item],int(have.get(item,0)),int(Warmer.INSTALL_COST[item])]
		check(label_text("WarmerMat_"+item)==want,"Material line 「%s」 (%s): %s"%[want,label,label_text("WarmerMat_"+item)])
		var pic:=control("WarmerMatIcon_"+item) as TextureRect
		check(pic!=null and pic.texture!=null and pic.is_visible_in_tree(),"Material icon %s shown (%s)"%[item,label])

# --------------------------------------------------------------------- flows --

func reset()->void:
	await close_page()
	w.state.erase("table_warmer")  # PRESET: un-install between sizes
	w.state.community={"table":World.COMMUNITY.cell_key(TABLE)}  # PRESET
	for item in ["warm_stone","copper_joint","stone","trout_hotpot","watermelon_platter"]:bag()[item]=0  # PRESET
	await refresh()

func size_flow(label:String)->void:
	await reset()
	check(World.COMMUNITY.table_cell(app.session.snapshot)==TABLE,"Table at (39,30) (%s)"%label)
	await stand(TABLE_SPOT)
	check(str(app.view.interaction_focus())=="community","Standing south of the table focuses it (%s): %s"%[label,str(app.view.interaction_focus())])
	# ---- not installed, short.
	await set_bag({"warm_stone":2,"copper_joint":1,"stone":4})
	await interact_key()
	check(page_open(),"E at the table opens 渡口的共餐桌 (%s): %s"%[label,texts().left(60).replace("\n"," | ")])
	if not page_open():return
	check(not app._world_keyboard_allowed(),"World keys blocked while the page is open (%s)"%label)
	focus_ok("short "+label)
	check(label_text("WarmerTitle")=="保溫底座" and label_text("WarmerStatus")==UI.STATUS_OPEN,"Card says 保溫底座 · 尚未加裝 (%s): %s"%[label,label_text("WarmerStatus")])
	check(label_text("WarmerRule")==UI.WARMER_RULE,"Short explanation (%s)"%label)
	check(label_text("WarmerSource").contains("第 12、13 層") and label_text("WarmerSource").contains("暖岩片") and shown("WarmerSource"),"Where 暖岩片 comes from (%s): %s"%[label,label_text("WarmerSource")])
	materials_ok("short "+label,{"warm_stone":2,"copper_joint":1,"stone":4})
	var short_reason:=Warmer.SHORT%"暖岩片 4、銅接頭 1"
	var install:=button("WarmerInstall")
	check(install!=null and install.text=="加裝保溫底座" and install.disabled and install.tooltip_text==short_reason,"加裝保溫底座 disabled with the shortfall (%s): %s"%[label,install.tooltip_text if install else "missing"])
	check(label_text("WarmerReason")==short_reason and shown("WarmerReason"),"Reason line 「%s」 (%s): %s"%[short_reason,label,label_text("WarmerReason")])
	check(not shown("HotpotWarm"),"No 保溫上桌六份 before installing (%s)"%label)
	check(button("DishMain_hotpot").text=="上桌四份" and button("DishMain_hotpot").disabled,"Plain 上桌四份 present, disabled with no hotpot (%s)"%label)
	check(label_text("DishText_hotpot")=="雪點鱒魚火鍋 · 還沒上桌・背包 0 份","Hotpot row text (%s): %s"%[label,label_text("DishText_hotpot")])
	layout_ok("not installed short "+label)
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the page (%s)"%label)
	# ---- plain serve before installing still works (4 portions, claim -> 3 / 4).
	await set_bag({"trout_hotpot":4})
	await interact_key()
	check(page_open(),"Page reopens (%s)"%label)
	check(focused_name()=="DishMain_hotpot","Focus starts on 上桌四份 when it is the only action (%s): %s"%[label,focused_name()])
	if await press("DishMain_hotpot","plain serve before install "+label):
		check(int(hotpot().get("portions",0))==4 and not hotpot().has("total"),"Plain serve puts 4 portions without total (%s): %s"%[label,str(hotpot())])
		check(label_text("DishText_hotpot")=="雪點鱒魚火鍋 · 剩 4 / 4 份","Shows 剩 4 / 4 份 (%s): %s"%[label,label_text("DishText_hotpot")])
		check(page_open() and feedback().contains("上桌了"),"Page stays open with the server reply (%s): %s"%[label,feedback()])
		check(button("DishMain_hotpot").text=="領一份" and focused_name()=="DishMain_hotpot","Same button now says 領一份 and keeps focus (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(int(hotpot().get("portions",0))==3 and int(bag().get("trout_hotpot",0))==1,"KEY_ENTER on 領一份 claims (%s): %s"%[label,str(hotpot())])
	check(label_text("DishText_hotpot")=="雪點鱒魚火鍋 · 剩 3 / 4 份・你已領過" and button("DishMain_hotpot").disabled,"Shows 剩 3 / 4 份・你已領過 (%s): %s"%[label,label_text("DishText_hotpot")])
	await close_page()
	w.state.community.erase("hotpot")  # PRESET: clear the plain round
	bag()["trout_hotpot"]=0
	# ---- not installed, ready.
	await set_bag({"warm_stone":6,"copper_joint":2,"stone":4})
	await interact_key()
	check(page_open(),"Page reopens ready (%s)"%label)
	materials_ok("ready "+label,{"warm_stone":6,"copper_joint":2,"stone":4})
	install=button("WarmerInstall")
	check(install!=null and not install.disabled and not shown("WarmerReason"),"加裝保溫底座 enabled, no reason line (%s)"%label)
	check(focused_name()=="WarmerInstall","Focus starts on 加裝保溫底座 (%s): %s"%[label,focused_name()])
	layout_ok("not installed ready "+label)
	# Arrow keys walk the page: install -> routes -> install -> watermelon -> hotpot -> 關閉.
	await key(KEY_DOWN)
	check(focused_name()=="Route_letter","KEY_DOWN from 加裝 reaches 渡口來信 (%s): %s"%[label,focused_name()])
	await key(KEY_RIGHT)
	check(focused_name()=="Route_journal","KEY_RIGHT along the routes (%s): %s"%[label,focused_name()])
	await key(KEY_UP)
	check(focused_name()=="WarmerInstall","KEY_UP back to 加裝 (%s): %s"%[label,focused_name()])
	await key(KEY_UP)
	check(focused_name()=="DishMain_watermelon","KEY_UP to the watermelon row (%s): %s"%[label,focused_name()])
	await key(KEY_UP)
	check(focused_name()=="DishMain_hotpot","KEY_UP to the hotpot row (%s): %s"%[label,focused_name()])
	await key(KEY_UP)
	var up:=root.gui_get_focus_owner() as Button
	check(up!=null and up.text.contains("關閉"),"KEY_UP from the first row reaches 關閉 (%s): %s"%[label,up.text if up else "none"])
	await key(KEY_DOWN)
	check(focused_name()=="DishMain_hotpot","KEY_DOWN from 關閉 returns to the table (%s): %s"%[label,focused_name()])
	await key(KEY_DOWN);await key(KEY_DOWN)
	check(focused_name()=="WarmerInstall","Back on 加裝 (%s): %s"%[label,focused_name()])
	# KEY_ENTER installs through the server.
	await act_key(KEY_ENTER)
	check(Warmer.installed(w.state) and w.state.table_warmer=={"installed":true},"KEY_ENTER on 加裝保溫底座 installs (%s): %s"%[label,str(w.state.get("table_warmer"))])
	check(int(bag().warm_stone)==0 and int(bag().copper_joint)==0 and int(bag().stone)==0,"Install took 6 / 2 / 4 (%s): %s"%[label,str(bag())])
	check(Warmer.installed(app.session.snapshot),"Client snapshot has table_warmer (%s)"%label)
	check(feedback()==Warmer.INSTALLED_OK,"Server reply shown in the page (%s): %s"%[label,feedback()])
	# ---- installed, idle.
	check(page_open(),"Page stays open after installing (%s)"%label)
	check(label_text("WarmerStatus")==UI.STATUS_DONE and label_text("WarmerRule")==UI.WARMER_DONE,"Card shows 已加裝 (%s): %s / %s"%[label,label_text("WarmerStatus"),label_text("WarmerRule")])
	check(not shown("WarmerInstall") and not shown("WarmerMaterials") and not shown("WarmerSource"),"Install row gone once installed (%s)"%label)
	var warm:=button("HotpotWarm")
	check(warm!=null and warm.is_visible_in_tree() and warm.text=="保溫上桌六份" and warm.disabled and warm.tooltip_text==Warmer.HOTPOT_SHORT,"保溫上桌六份 shown, disabled with 「%s」 (%s): %s"%[Warmer.HOTPOT_SHORT,label,warm.tooltip_text if warm else "missing"])
	check(label_text("WarmerReason")==Warmer.HOTPOT_SHORT,"Reason line explains the six hotpots (%s): %s"%[label,label_text("WarmerReason")])
	check(shown("DishMain_hotpot") and button("DishMain_hotpot").text=="上桌四份","上桌四份 still beside it (%s)"%label)
	focus_ok("after install "+label)
	check(focused_name()=="Route_letter","Hidden 加裝 hands focus to the first available action (%s): %s"%[label,focused_name()])
	layout_ok("installed idle "+label)
	# Arrow keys in the installed layout (no install row).
	await key(KEY_UP)
	check(focused_name()=="DishMain_watermelon","KEY_UP from the routes to the watermelon row (%s): %s"%[label,focused_name()])
	await key(KEY_UP);await key(KEY_RIGHT)
	check(focused_name()=="HotpotWarm","KEY_RIGHT from 上桌四份 to 保溫上桌六份 (%s): %s"%[label,focused_name()])
	await key(KEY_LEFT)
	check(focused_name()=="DishMain_hotpot","KEY_LEFT back (%s): %s"%[label,focused_name()])
	# ---- warm serve: six hotpots (and a platter for later).
	await set_bag({"trout_hotpot":6,"watermelon_platter":4})
	warm=button("HotpotWarm")
	check(warm!=null and not warm.disabled and not shown("WarmerReason"),"保溫上桌六份 enabled with six hotpots (%s)"%label)
	await key(KEY_RIGHT)
	check(focused_name()=="HotpotWarm","Focus on 保溫上桌六份 (%s): %s"%[label,focused_name()])
	await act_key(KEY_ENTER)
	check(hotpot()=={"portions":6,"claimed":{},"total":6} and int(bag().trout_hotpot)==0,"KEY_ENTER serves a warm round of six (%s): %s"%[label,str(hotpot())])
	check(feedback()==Warmer.WARM_SERVED,"Warm serve reply shown (%s): %s"%[label,feedback()])
	check(label_text("DishText_hotpot")=="雪點鱒魚火鍋 · 剩 6 / 6 份","Shows 剩 6 / 6 份 (%s): %s"%[label,label_text("DishText_hotpot")])
	check(button("DishMain_hotpot").text=="領一份" and not button("DishMain_hotpot").disabled,"領一份 offered (%s)"%label)
	check(button("HotpotWarm").disabled and button("HotpotWarm").tooltip_text==Warmer.STILL_SERVING and label_text("WarmerReason")==Warmer.STILL_SERVING,"保溫上桌六份 waits while the pot is out (%s): %s"%[label,label_text("WarmerReason")])
	check(focused_name()=="DishMain_hotpot","Focus moves to 領一份 after the warm serve (%s): %s"%[label,focused_name()])
	layout_ok("installed with a 6-portion round "+label)
	await act_key(KEY_ENTER)
	check(int(hotpot().get("portions",0))==5 and int(hotpot().get("total",0))==6 and int(bag().trout_hotpot)==1,"Claim leaves 5 of 6 (%s): %s"%[label,str(hotpot())])
	check(label_text("DishText_hotpot")=="雪點鱒魚火鍋 · 剩 5 / 6 份・你已領過","Shows 剩 5 / 6 份 (%s): %s"%[label,label_text("DishText_hotpot")])
	check(button("DishMain_hotpot").disabled,"No second claim this round (%s)"%label)
	focus_ok("after claim "+label)
	# ---- both dishes on the table (watermelon by the plain path).
	if await press("DishMain_watermelon","watermelon serve "+label):
		check(int(w.state.community.get("watermelon",{}).get("portions",0))==4,"Watermelon served 4 (%s)"%label)
		check(label_text("DishText_watermelon")=="夏日西瓜盤 · 剩 4 / 4 份","Watermelon shows 剩 4 / 4 份 (%s): %s"%[label,label_text("DishText_watermelon")])
		check(label_text("DishText_hotpot")=="雪點鱒魚火鍋 · 剩 5 / 6 份・你已領過","Hotpot round untouched (%s)"%label)
	layout_ok("both dishes on the table "+label)
	# ---- plain 上桌四份 still works after installing.
	await close_page()
	w.state.community.erase("hotpot")  # PRESET: clear the warm round
	await set_bag({"trout_hotpot":4})
	await interact_key()
	check(page_open(),"Page reopens installed (%s)"%label)
	if await press("DishMain_hotpot","plain serve after install "+label):
		check(hotpot()=={"portions":4,"claimed":{}},"Plain serve after installing still makes 4 (%s): %s"%[label,str(hotpot())])
		check(label_text("DishText_hotpot")=="雪點鱒魚火鍋 · 剩 4 / 4 份","Shows 剩 4 / 4 份 (%s): %s"%[label,label_text("DishText_hotpot")])
		check(button("HotpotWarm").disabled and button("HotpotWarm").tooltip_text==Warmer.STILL_SERVING,"Warm serve waits for the plain round (%s)"%label)
	layout_ok("installed plain round "+label)
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the installed page (%s)"%label)
	# ---- backpack: 暖岩片 detail and icon.
	await set_bag({"warm_stone":3})
	app._inventory()
	await settle()
	check(app.modal is InventoryPanel,"Backpack opens (%s)"%label)
	if app.modal is InventoryPanel:
		var panel=app.modal
		panel.select_item("warm_stone")
		await settle()
		check(panel.detail_name.text=="暖岩片" and panel.detail_count.text=="持有 3","暖岩片 name and count (%s): %s %s"%[label,panel.detail_name.text,panel.detail_count.text])
		check(panel.detail_use.text.contains("第 12、13 層") and panel.detail_use.text.contains("保溫底座"),"暖岩片 description names the floors and the use (%s): %s"%[label,panel.detail_use.text])
		check(not_cut(panel.detail_use) and (panel as Control).get_global_rect().grow(0.5).encloses(panel.detail_use.get_global_rect()),"暖岩片 description whole (%s)"%label)
		var tex:Texture2D=panel.detail_icon.texture
		check(tex!=null and tex.get_size()==Vector2(32,32) and tex==Items.icon("warm_stone"),"暖岩片 detail icon is the 32px warm stone (%s)"%label)
		check(tex!=Items.icon("stone") and tex!=Items.icon("ochre_earth"),"暖岩片 icon is not the stone / ochre icon (%s)"%label)
	await close_page()
	# ---- sources: B12 / B13 rest-station card lists 暖岩片 and its use.
	w.state.mine_depths={"unlocked":13,"ready":{},"pumped":24,"hoist":true}  # PRESET
	for depth in [12,13]:
		await stand(Vector2(World.MINES.REST)+Vector2(0.5,0.5),"mine_%d"%depth)
		MineUI.open(app,"rest")
		await settle()
		var finds:=control("MineFinds") as Label
		check(finds!=null and finds.is_visible_in_tree() and finds.text.contains("暖岩片") and finds.text.contains("共餐桌保溫底座"),"B%d rest card lists 暖岩片 and its use (%s): %s"%[depth,label,finds.text if finds else "missing"])
		if finds!=null:check(not_cut(finds) and (app.modal as Control).get_global_rect().grow(0.5).encloses(finds.get_global_rect()),"B%d finds line whole (%s)"%[depth,label])
		var outer:=control("ModalScroll") as ScrollContainer
		if outer!=null:check(not outer.get_v_scroll_bar().visible,"B%d rest card needs no scrolling (%s)"%[depth,label])
		await close_page()
	check(MineUI.finds_text(12)=="敲礦另得：石材、暖岩片（共餐桌保溫底座用）","B12 finds text: %s"%MineUI.finds_text(12))
	check(MineUI.finds_text(13)=="敲礦另得：含金礦料、暖岩片（共餐桌保溫底座用）","B13 finds text: %s"%MineUI.finds_text(13))
	check(not MineUI.finds_text(11).contains("暖岩片") and not MineUI.finds_text(14).contains("暖岩片"),"Only B12/B13 list 暖岩片")
	await stand(TABLE_SPOT)

func run()->void:
	create_timer(170.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 170 s")
		finish())
	var started:=Time.get_ticks_msec()
	path=OS.get_environment("TEMP").path_join("table-warmer-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"保溫旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	if not app.playing:note("app.playing was false after host; set true for key input");app.playing=true
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	# A fresh host shows the 望安 arrival card; the first E closes it (main.gd:1332),
	# exactly as for a player, so close it with a real E before the table flow.
	await refresh()
	if WanganUI.card_open(app):
		await key(KEY_E)
		check(not WanganUI.card_open(app),"First E closes the arrival card")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		await size_flow(tag)
		note("size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
