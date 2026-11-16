extends SceneTree
## 第 40 章「茶陶上桌」card on the 渡口的共餐桌 page (community_ui.gd), headless at
## 1024×640 and 1280×800. Same harness as test_table_warmer_ui.gd: real Session host,
## real snapshot round trips.
##
## PRESET / FIXTURE (written directly, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true is
##    set here (the runner passes no flag for this suite);
##  * state.board=true, state.picnic=true and state.community={"table":"39,30"};
##    state.table_warmer, state.tea_service and state.tea_revisit are ERASED before each
##    size; the 貓空與鶯歌回訪 is marked done by writing state.tea_revisit = a completed
##    record (6 jars, 3 light + 3 deep filled, day 1, done_day 1) — the order itself is
##    not played here (test_tea_revisit_ui does that);
##  * BAGS ARE WRITTEN DIRECTLY: tea_ware_kit / tea_light / tea_deep for the local player
##    and for the fixture lender; warmer materials and dishes are zeroed;
##  * six fixture islanders are added with World.add_player ("tea-lender" and five
##    "tea-guest-N"), placed by writing x/y beside the table; their place / brew / sip
##    actions go through World.act (the real rules, but not through a client);
##  * the local player is teleported by writing region/x/y (no walking) to TABLE_SPOT;
##  * session rate buckets / action_clock are cleared between my own actions;
##  * WORLD CLOCK (cold tea, sections J/K): to reach the next world day, state.time is
##    WRITTEN to half a second before the coming midnight, then one real
##    World.step(1.0, true) tick crosses it (same pattern as test_market_stall_ui);
##    nobody waits a real day. Every tea round in this suite is brewed through the
##    rules (World.act or my buttons) — no round dictionary is ever written directly;
##  * cold-tea fixture actions through World.act: the lender brews deep, a guest sips,
##    a guest's cold sip is refused with COLD, the lender takes the set back while cold
##    cups remain.
## REALLY EXERCISED (local player):
##  * the fresh host's 望安 arrival card is closed by a first real KEY_E;
##  * KEY_E through root.push_input -> main._unhandled_input -> _interact at the table
##    opens the page; KEY_ESCAPE closes it; KEY_UP / DOWN / LEFT / RIGHT move focus;
##    KEY_ENTER on the focused 擺上茶陶組 / 泡淺焙茶 / 喝一杯 sends the action; 泡深焙茶 /
##    喝一杯 / 收回茶陶組 are also pressed by grabbing focus and emitting `pressed`
##    (a click). Every action is a real Session.perform -> World -> snapshot ->
##    main._state_changed -> in-place page update, with the server reply in the footer;
##  * cold tea (隔夜茶): chip 茶涼了, status_text sentence, COLD reason, 喝一杯 disabled;
##    a click on 泡淺焙茶 re-brews the cold pot (fresh six, new day); as lender, KEY_RIGHT
##    to and a click on 收回茶陶組 with cold cups left; as non-lender no 收回茶陶組;
##  * the backpack detail (InventoryPanel.select_item) for 茶陶組.
## NOT COVERED HERE: world pixels; gamepad input (only the focus neighbours it uses are
## exercised through the arrow keys); the non-preview layout; the build folio card text
## (the 生活 note is checked as the BUILD_NOTES constant).
const World=preload("res://scripts/world.gd")
const Tea=preload("res://scripts/tea_service.gd")
const TeaArt=preload("res://scripts/tea_revisit_art.gd")
const UI=preload("res://scripts/community_ui.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const Panels=preload("res://scripts/life_ui_panels.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const Weather=preload("res://scripts/weather.gd")
const TABLE:=Vector2i(39,30)
const TABLE_SPOT:=Vector2(39.5,31.6)
const LENDER:="tea-lender"
const GUESTS:=["tea-guest-1","tea-guest-2","tea-guest-3","tea-guest-4","tea-guest-5"]
const TEA_IDS:=["TeaIcon","TeaTitle","TeaChip","TeaStatus","TeaNote","TeaDisclaimer","TeaReason","TeaPlace","TeaBrew_light","TeaBrew_deep","TeaSip","TeaTake"]
var app
var w
var id:=""
var path:=""
var checks:=0
var failures:=0
var finished:=false
var request:=0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("TEA_SERVICE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE TEA_SERVICE_UI "+message)

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

func held(item:String)->int:
	return int(bag().get(item,0))

func snap()->Dictionary:
	return app.session.snapshot

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func focused_name()->String:
	var owner:=root.gui_get_focus_owner()
	return str(owner.name) if owner!=null else "none"

func stand(at:Vector2,region:String=World.REGIONS.HOME)->void:
	var p:Dictionary=person()
	p.region=region  # PRESET
	p.x=at.x;p.y=at.y  # PRESET
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
	app.action_clock=0
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

## A fixture islander acts through World.act (real rules); returns the server reply.
func other_try(token:String,action:String,extra:String="")->Dictionary:
	request+=1
	var p:Dictionary=w.state.players[token]
	p.region=World.REGIONS.HOME  # PRESET
	p.x=TABLE_SPOT.x;p.y=TABLE_SPOT.y  # PRESET (beside the table)
	var result:Dictionary=w.act(token,"tea-ui-fixture-%d"%request,action,TABLE,extra)
	return result

## A fixture islander acts through World.act (real rules) and must succeed.
func other_act(token:String,action:String,extra:String="")->bool:
	var result:Dictionary=other_try(token,action,extra)
	check(bool(result.get("ok",false)),"Fixture %s %s %s: %s"%[token,action,extra,str(result.get("message",""))])
	return bool(result.get("ok",false))

## Next world day: state.time is WRITTEN to half a second before the coming midnight
## (PRESET clock), then one real World.step(1.0) tick crosses it; my snapshot refreshes.
## Returns the new day (one-based, tea_service.today).
func next_day(label:String)->int:
	var before:int=Tea.today(w.state)
	w.state.time=float(before)*Weather.DAY_SECONDS-0.5  # PRESET clock
	check(w.step(1.0,true),"World tick across midnight (%s): %s"%[label,str(w.step_error)])
	await refresh()
	check(Tea.today(w.state)==before+1 and Tea.today(snap())==before+1,"World and snapshot on day %d (%s): %d / %d"%[before+1,label,Tea.today(w.state),Tea.today(snap())])
	return before+1

func guests_sip(count:int)->void:
	for i in range(count):other_act(str(GUESTS[i]),Tea.SIP_ACTION)
	await refresh()

func completed_revisit()->Dictionary:
	return {"jars":{"tea_returned_jar":3,"tea_worn_jar":3},"filled":{"light":3,"deep":3},"day":1,"completed":true,"done_day":1,"claimed":{}}

func record()->Dictionary:
	var found:Variant=w.state.get(Tea.STATE_KEY)
	return found if found is Dictionary else {}

func in_rows(name:String)->bool:
	for row:Array in UI.focus_rows(app):
		for b:Button in row:
			if str(b.name)==name:return true
	return false

func reasons(parts:Array)->String:
	return "　".join(PackedStringArray(parts))

# ------------------------------------------------------------------- layout --

## Page inside the viewport, no outer scrolling, every visible label / button / icon
## inside the page and whole, the tea controls inside their card.
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
	var card:=control("TeaCard")
	check(card!=null and card.is_visible_in_tree(),"茶陶上桌 card shown (%s)"%label)
	if card!=null:
		for name:String in TEA_IDS:
			var c:=control(name)
			if c!=null and c.is_visible_in_tree():check(card.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the 茶陶上桌 card (%s) %s"%[name,label,rect_info(c)])
		var head:=control("TeaHead")
		if head!=null:check(head.get_combined_minimum_size().x<=head.size.x+0.5,"Tea title row not wider than the card (%s)"%label)
		var info:=control("TeaInfo")
		if info!=null:check(info.get_combined_minimum_size().x<=info.size.x+0.5,"Tea info row not wider than the card (%s)"%label)
	var warmer:=control("WarmerCard")
	check(warmer!=null and warmer.is_visible_in_tree(),"保溫底座 card still shown (%s)"%label)
	if warmer!=null and card!=null:check(warmer.get_global_rect().end.y<=card.get_global_rect().position.y+0.5,"茶陶上桌 card sits below the 保溫底座 card (%s)"%label)
	var routes:=control("CommunityRoutes")
	if routes!=null and card!=null:check(card.get_global_rect().end.y<=routes.get_global_rect().position.y+0.5,"茶陶上桌 card sits above the other entries (%s)"%label)
	for route in ["渡口來信","生活訂單","風鈴接力","公共廚房"]:
		var found:=false
		for node in modal.find_children("*","Button",true,false):
			if (node as Button).text==route and (node as Control).is_visible_in_tree():found=true
		check(found,"Route %s still on the page (%s)"%[route,label])
	var icon:=control("TeaIcon") as TextureRect
	check(icon!=null and icon.texture==TeaArt.teaware_texture() and icon.texture.get_size()==Vector2(32,32),"茶陶組 icon is the 32×32 tea ware art (%s)"%label)
	check(label_text("TeaTitle")=="茶陶上桌","Card title 茶陶上桌 (%s)"%label)
	check(label_text("TeaDisclaimer")==Tea.DISCLAIMER and shown("TeaDisclaimer"),"Disclaimer shown (%s)"%label)
	var disclaimer:=control("TeaDisclaimer") as Label
	if disclaimer!=null:check(disclaimer.get_theme_font_size("font_size")<=13,"Disclaimer is small text (%s)"%label)
	check(label_text("TeaStatus")==Tea.status_text(snap()) and shown("TeaStatus"),"Status line is status_text (%s): %s"%[label,label_text("TeaStatus")])

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and owner.is_visible_in_tree(),"Keyboard focus is on a visible button inside the page (%s): %s"%[label,focused_name()])

func expect_focus(name:String,label:String)->void:
	check(focused_name()==name,"Focus on %s (%s): %s"%[name,label,focused_name()])

func expect_button(name:String,caption:String,enabled:bool,tip:String,label:String)->void:
	var b:=button(name)
	check(b!=null and b.is_visible_in_tree(),"%s shown (%s)"%[name,label])
	if b==null:return
	check(b.text==caption,"%s caption 「%s」 (%s): %s"%[name,caption,label,b.text])
	check(b.disabled!=enabled,"%s %s (%s)"%[name,"enabled" if enabled else "disabled",label])
	if not tip.is_empty():check(b.tooltip_text==tip,"%s tooltip 「%s」 (%s): %s"%[name,tip,label,b.tooltip_text])

func expect_reason(want:String,label:String)->void:
	if want.is_empty():
		check(not shown("TeaReason"),"No reason line (%s): %s"%[label,label_text("TeaReason")])
	else:
		check(shown("TeaReason") and label_text("TeaReason")==want,"Reason line 「%s」 (%s): %s"%[want,label,label_text("TeaReason")])

# --------------------------------------------------------------------- flows --

func reset()->void:
	await close_page()
	w.state.erase("table_warmer")  # PRESET
	w.state.erase(Tea.STATE_KEY)  # PRESET
	w.state.erase("tea_revisit")  # PRESET (revisit not done)
	w.state.community={"table":World.COMMUNITY.cell_key(TABLE)}  # PRESET
	for item in ["tea_ware_kit","tea_light","tea_deep","warm_stone","copper_joint","stone","trout_hotpot","watermelon_platter"]:bag()[item]=0  # PRESET
	for token in [LENDER]+GUESTS:
		var inv:Dictionary=w.state.players[token].inventory
		for item in ["tea_ware_kit","tea_light","tea_deep"]:inv[item]=0  # PRESET
	await refresh()

func size_flow(label:String)->void:
	await reset()
	check(World.COMMUNITY.table_cell(snap())==TABLE,"Table at (39,30) (%s)"%label)
	await stand(TABLE_SPOT)
	check(str(app.view.interaction_focus())=="community","Standing south of the table focuses it (%s): %s"%[label,str(app.view.interaction_focus())])
	# ---- A: revisit not finished.
	await interact_key()
	check(page_open(),"E at the table opens 渡口的共餐桌 (%s): %s"%[label,texts().left(60).replace("\n"," | ")])
	if not page_open():return
	check(not app._world_keyboard_allowed(),"World keys blocked while the page is open (%s)"%label)
	focus_ok("revisit not done "+label)
	check(label_text("TeaChip")==UI.TEA_CHIP_NONE,"Chip says 未擺上 (%s): %s"%[label,label_text("TeaChip")])
	check(label_text("TeaStatus")=="共餐桌上還沒有茶陶組。","Status: no set yet (%s)"%label)
	check(label_text("TeaNote")==UI.TEA_RULE and shown("TeaNote"),"One-sentence rule shown (%s)"%label)
	expect_button("TeaPlace","擺上茶陶組",false,Tea.NOT_DONE,"revisit not done "+label)
	expect_reason(Tea.NOT_DONE,"revisit not done "+label)
	for name in ["TeaBrew_light","TeaBrew_deep","TeaSip","TeaTake"]:check(not shown(name),"%s hidden before a set is placed (%s)"%[name,label])
	check(not in_rows("TeaPlace"),"A lone disabled 擺上茶陶組 is not in arrow-key navigation (%s)"%label)
	layout_ok("revisit not done "+label)
	var place_node:=button("TeaPlace")
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the page (%s)"%label)
	await interact_key()
	check(page_open(),"Page reopens (%s)"%label)
	place_node=button("TeaPlace")
	# ---- B: revisit done, no kit (page updates in place).
	w.state.tea_revisit=completed_revisit()  # PRESET
	await refresh()
	check(page_open() and button("TeaPlace")==place_node,"Same page and button updated in place (%s)"%label)
	check(Tea.TEA_REVISIT.completed(snap()),"Client snapshot sees the finished revisit (%s)"%label)
	expect_button("TeaPlace","擺上茶陶組",false,Tea.NO_KIT,"no kit "+label)
	expect_reason(Tea.NO_KIT,"no kit "+label)
	layout_ok("done but no kit "+label)
	# ---- C: can place.
	await set_bag({"tea_ware_kit":1})
	expect_button("TeaPlace","擺上茶陶組",true,"","can place "+label)
	expect_reason("","can place "+label)
	check(in_rows("TeaPlace"),"Enabled 擺上茶陶組 joins arrow-key navigation (%s)"%label)
	layout_ok("can place "+label)
	# Arrow keys: routes -> tea row -> 保溫底座 -> tea row.
	button("Route_letter").grab_focus();await settle()
	await key(KEY_UP)
	expect_focus("TeaPlace","KEY_UP from the routes "+label)
	await key(KEY_UP)
	expect_focus("WarmerInstall","KEY_UP to 加裝保溫底座 "+label)
	await key(KEY_DOWN)
	expect_focus("TeaPlace","KEY_DOWN back to 擺上茶陶組 "+label)
	await key(KEY_DOWN)
	expect_focus("Route_letter","KEY_DOWN to the routes "+label)
	await key(KEY_UP)
	expect_focus("TeaPlace","Back on 擺上茶陶組 "+label)
	await act_key(KEY_ENTER)
	check(record()=={"lender":id},"KEY_ENTER on 擺上茶陶組 places the set (%s): %s"%[label,str(record())])
	check(held("tea_ware_kit")==0,"Kit left the bag (%s)"%label)
	check(feedback()==Tea.PLACED_OK,"Server reply in the page footer (%s): %s"%[label,feedback()])
	check(page_open() and Tea.placed(snap()) and Tea.lender_own(snap()),"Page open; snapshot says placed and mine (%s)"%label)
	# ---- D: placed, empty pot, lender, no tea.
	check(not shown("TeaPlace"),"擺上茶陶組 hidden once placed (%s)"%label)
	check(label_text("TeaChip")==UI.TEA_CHIP_EMPTY and label_text("TeaStatus")=="茶陶組擺在共餐桌上，茶壺還是空的。","Empty pot chip and status (%s): %s / %s"%[label,label_text("TeaChip"),label_text("TeaStatus")])
	check(label_text("TeaNote")==UI.TEA_OWN_NOTE,"Lender note (%s): %s"%[label,label_text("TeaNote")])
	expect_button("TeaBrew_light","泡淺焙茶・有 0",false,Tea.NO_TEA%"淺焙茶","empty pot "+label)
	expect_button("TeaBrew_deep","泡深焙茶・有 0",false,Tea.NO_TEA%"深焙茶","empty pot "+label)
	expect_button("TeaSip","喝一杯",false,Tea.NO_ROUND,"empty pot "+label)
	expect_button("TeaTake","收回茶陶組",true,"","empty pot lender "+label)
	expect_reason(reasons([Tea.NO_TEA%"淺焙茶",Tea.NO_TEA%"深焙茶",Tea.NO_ROUND]),"empty pot, no tea "+label)
	focus_ok("after placing "+label)
	expect_focus("TeaBrew_light","Hidden 擺上 hands focus to the tea row, not to 收回 "+label)
	layout_ok("placed empty pot, no tea "+label)
	await key(KEY_RIGHT)
	expect_focus("TeaBrew_deep","KEY_RIGHT along the tea row "+label)
	await key(KEY_RIGHT)
	expect_focus("TeaSip","KEY_RIGHT to 喝一杯 "+label)
	await key(KEY_RIGHT)
	expect_focus("TeaTake","KEY_RIGHT reaches 收回茶陶組 "+label)
	await key(KEY_RIGHT)
	expect_focus("TeaBrew_light","KEY_RIGHT wraps "+label)
	await key(KEY_UP)
	expect_focus("WarmerInstall","KEY_UP from the tea row "+label)
	await key(KEY_DOWN)
	expect_focus("TeaBrew_light","KEY_DOWN into the tea row "+label)
	await key(KEY_DOWN)
	expect_focus("Route_letter","KEY_DOWN from the tea row to the routes "+label)
	# ---- E: tea in the bag; brew light with Enter.
	await set_bag({"tea_light":2,"tea_deep":1})
	expect_button("TeaBrew_light","泡淺焙茶・有 2",true,"","with tea "+label)
	expect_button("TeaBrew_deep","泡深焙茶・有 1",true,"","with tea "+label)
	expect_reason(Tea.NO_ROUND,"empty pot with tea "+label)
	layout_ok("placed empty pot, with tea "+label)
	await key(KEY_UP)
	expect_focus("TeaBrew_light","KEY_UP from the routes into the tea row "+label)
	await act_key(KEY_ENTER)
	check(record().get("round",{})=={"style":"light","portions":6,"claimed":{},"day":Tea.today(w.state)},"KEY_ENTER brews a light round of six (%s): %s"%[label,str(record())])
	check(held("tea_light")==1,"One 淺焙茶 used (%s)"%label)
	check(feedback()==Tea.BREWED_OK%"淺焙茶","Brew reply shown (%s): %s"%[label,feedback()])
	# ---- F: mid-round, not sipped.
	check(label_text("TeaChip")=="淺焙茶 6／6 杯","Chip shows cups n／6 with the style (%s): %s"%[label,label_text("TeaChip")])
	check(label_text("TeaStatus")=="桌上有一壺淺焙茶，還剩 6／6 杯。","Status mid-round (%s): %s"%[label,label_text("TeaStatus")])
	expect_button("TeaBrew_light","泡淺焙茶・有 1",false,Tea.TEA_LEFT_BREW,"mid-round "+label)
	expect_button("TeaBrew_deep","泡深焙茶・有 1",false,Tea.TEA_LEFT_BREW,"mid-round "+label)
	expect_button("TeaSip","喝一杯",true,"","mid-round "+label)
	expect_button("TeaTake","收回茶陶組",false,Tea.TEA_LEFT,"mid-round "+label)
	expect_reason(reasons([Tea.TEA_LEFT_BREW,Tea.TEA_LEFT]),"mid-round "+label)
	expect_focus("TeaSip","Focus moves to 喝一杯 after brewing "+label)
	layout_ok("mid-round not sipped "+label)
	# ---- G: sip with Enter.
	await act_key(KEY_ENTER)
	check(int(record().get("round",{}).get("portions",0))==5 and record().round.claimed.has(id),"KEY_ENTER on 喝一杯 sips (%s): %s"%[label,str(record())])
	check(feedback()==Tea.SIP_OK%["淺焙茶",5],"Sip reply shown (%s): %s"%[label,feedback()])
	check(Tea.sipped_own(snap()),"Snapshot says I sipped (%s)"%label)
	check(label_text("TeaChip")=="淺焙茶 5／6 杯","Chip 5／6 (%s): %s"%[label,label_text("TeaChip")])
	expect_button("TeaSip","喝一杯",false,Tea.SIPPED,"sipped "+label)
	expect_reason(reasons([Tea.TEA_LEFT_BREW,Tea.SIPPED,Tea.TEA_LEFT]),"sipped "+label)
	expect_focus("TeaSip","Focus stays on the now-disabled 喝一杯 "+label)
	layout_ok("sipped "+label)
	# ---- H: the other five finish the pot.
	await guests_sip(5)
	check(int(record().round.portions)==0,"Pot finished by five fixture islanders (%s): %s"%[label,str(record())])
	check(label_text("TeaChip")==UI.TEA_CHIP_DONE and label_text("TeaStatus")=="上一壺淺焙茶已經喝完了。","Finished chip and status (%s): %s / %s"%[label,label_text("TeaChip"),label_text("TeaStatus")])
	expect_button("TeaSip","喝一杯",false,Tea.EMPTY,"finished "+label)
	expect_button("TeaBrew_light","泡淺焙茶・有 1",true,"","finished "+label)
	expect_button("TeaBrew_deep","泡深焙茶・有 1",true,"","finished "+label)
	expect_button("TeaTake","收回茶陶組",true,"","finished "+label)
	expect_reason(Tea.EMPTY,"finished "+label)
	focus_ok("finished "+label)
	layout_ok("finished round "+label)
	await key(KEY_LEFT)
	expect_focus("TeaBrew_deep","KEY_LEFT reaches 泡深焙茶 "+label)
	await key(KEY_LEFT)
	expect_focus("TeaBrew_light","KEY_LEFT reaches 泡淺焙茶 "+label)
	await key(KEY_LEFT)
	expect_focus("TeaTake","KEY_LEFT wraps to 收回茶陶組 "+label)
	# Click 泡深焙茶.
	if await press("TeaBrew_deep","brew deep "+label):
		check(record().get("round",{})=={"style":"deep","portions":6,"claimed":{},"day":Tea.today(w.state)},"Click brews a deep round (%s): %s"%[label,str(record())])
		check(held("tea_deep")==0 and feedback()==Tea.BREWED_OK%"深焙茶","Deep tea used, reply shown (%s): %s"%[label,feedback()])
		check(label_text("TeaChip")=="深焙茶 6／6 杯","Chip shows the deep round (%s): %s"%[label,label_text("TeaChip")])
		expect_focus("TeaSip","Focus moves to 喝一杯 after the click brew "+label)
		expect_button("TeaSip","喝一杯",true,"","new round "+label)
	# Click 喝一杯, the others finish, then the deep tea is gone from my bag.
	await press("TeaSip","sip deep "+label)
	await guests_sip(5)
	check(int(record().get("round",{}).get("portions",-1))==0,"Deep round finished (%s): %s"%[label,str(record())])
	expect_button("TeaBrew_deep","泡深焙茶・有 0",false,Tea.NO_TEA%"深焙茶","no deep tea "+label)
	expect_button("TeaBrew_light","泡淺焙茶・有 1",true,"","light left "+label)
	expect_reason(reasons([Tea.NO_TEA%"深焙茶",Tea.EMPTY]),"no deep tea, finished "+label)
	layout_ok("finished, no deep tea "+label)
	# Click 收回茶陶組.
	if await press("TeaTake","take back "+label):
		check(not w.state.has(Tea.STATE_KEY) and held("tea_ware_kit")==1,"Take returns the kit and clears the table (%s): %s"%[label,str(w.state.get(Tea.STATE_KEY))])
		check(feedback()==Tea.TAKEN_OK,"Take reply shown (%s): %s"%[label,feedback()])
		check(not Tea.placed(snap()) and label_text("TeaChip")==UI.TEA_CHIP_NONE and label_text("TeaNote")==UI.TEA_RULE,"Card back to the empty table (%s)"%label)
		for name in ["TeaBrew_light","TeaBrew_deep","TeaSip","TeaTake"]:check(not shown(name),"%s hidden after taking back (%s)"%[name,label])
		expect_button("TeaPlace","擺上茶陶組",true,"","after take "+label)
		expect_focus("TeaPlace","Hidden 收回 hands focus to 擺上茶陶組 "+label)
		layout_ok("taken back "+label)
	# ---- I: another islander lends the set; I hold no tea.
	await set_bag({"tea_light":0,"tea_deep":0})
	var lender_bag:Dictionary=w.state.players[LENDER].inventory
	lender_bag["tea_ware_kit"]=1  # PRESET
	lender_bag["tea_light"]=1  # PRESET
	other_act(LENDER,Tea.PLACE_ACTION)
	other_act(LENDER,Tea.BREW_ACTION,"light")
	await refresh()
	check(page_open() and Tea.placed(snap()) and not Tea.lender_own(snap()),"Snapshot: placed by someone else (%s)"%label)
	check(not shown("TeaTake") and not shown("TeaPlace"),"No 收回茶陶組 for a non-lender (%s)"%label)
	check(label_text("TeaNote")==UI.TEA_OTHER_NOTE and shown("TeaNote"),"Non-lender line (%s): %s"%[label,label_text("TeaNote")])
	expect_button("TeaBrew_light","泡淺焙茶・有 0",false,Tea.TEA_LEFT_BREW,"non-lender "+label)
	expect_button("TeaSip","喝一杯",true,"","non-lender "+label)
	expect_reason(Tea.TEA_LEFT_BREW,"non-lender mid-round "+label)
	expect_focus("TeaSip","Hidden 擺上 hands focus to 喝一杯 "+label)
	layout_ok("non-lender mid-round "+label)
	await key(KEY_RIGHT)
	expect_focus("TeaBrew_light","KEY_RIGHT wraps in the three-button row "+label)
	await key(KEY_LEFT)
	expect_focus("TeaSip","KEY_LEFT back to 喝一杯 "+label)
	await act_key(KEY_ENTER)
	check(int(record().round.portions)==5 and record().round.claimed.has(id),"Non-lender sips through the server (%s): %s"%[label,str(record())])
	check(feedback()==Tea.SIP_OK%["淺焙茶",5],"Sip reply shown (%s): %s"%[label,feedback()])
	expect_button("TeaSip","喝一杯",false,Tea.SIPPED,"non-lender sipped "+label)
	# Worst-case reason line: finished pot, no tea of either kind.
	await guests_sip(5)
	expect_reason(reasons([Tea.NO_TEA%"淺焙茶",Tea.NO_TEA%"深焙茶",Tea.EMPTY]),"non-lender finished, no tea "+label)
	check(not shown("TeaTake"),"Still no 收回茶陶組 for a non-lender (%s)"%label)
	focus_ok("non-lender finished "+label)
	layout_ok("non-lender finished, no tea "+label)
	# ---- J: cold tea (隔夜茶), non-lender. The lender brews deep, one guest sips, the day turns.
	lender_bag["tea_deep"]=1  # PRESET
	other_act(LENDER,Tea.BREW_ACTION,"deep")
	other_act(str(GUESTS[0]),Tea.SIP_ACTION)
	await set_bag({"tea_light":1,"tea_deep":0})
	var brewed_day:int=Tea.today(w.state)
	check(int(record().get("round",{}).get("day",0))==brewed_day and int(record().get("round",{}).get("portions",0))==5,"Warm deep round of the day, 5 left (%s): %s"%[label,str(record())])
	check(label_text("TeaChip")=="深焙茶 5／6 杯","Warm chip 5／6 (%s): %s"%[label,label_text("TeaChip")])
	expect_button("TeaSip","喝一杯",true,"","warm deep, non-lender "+label)
	expect_button("TeaBrew_light","泡淺焙茶・有 1",false,Tea.TEA_LEFT_BREW,"warm deep, non-lender "+label)
	button("TeaSip").grab_focus();await settle()
	var cold_day:int=await next_day("non-lender cold "+label)
	var now:Dictionary=Tea.current_round(snap())
	check(now.get("cold",false)==true and int(now.get("left",0))==5 and int(now.get("portions",-1))==0 and int(now.get("day",0))==brewed_day,"Snapshot round is cold with 5 cups left (%s): %s"%[label,str(now)])
	check(label_text("TeaChip")==UI.TEA_CHIP_COLD,"Chip says 茶涼了 (%s): %s"%[label,label_text("TeaChip")])
	var chip:=control("TeaChip") as Label
	if chip!=null:check(chip.get_theme_color("font_color")==UI.WARN,"Cold chip uses the warning colour (%s)"%label)
	check(label_text("TeaStatus")==Tea.status_text(snap()) and label_text("TeaStatus")=="前一天泡的深焙茶已經涼了，可以重新泡一壺。","Cold status sentence (%s): %s"%[label,label_text("TeaStatus")])
	expect_button("TeaSip","喝一杯",false,Tea.COLD,"cold, non-lender "+label)
	expect_button("TeaBrew_light","泡淺焙茶・有 1",true,"","cold, non-lender "+label)
	expect_button("TeaBrew_deep","泡深焙茶・有 0",false,Tea.NO_TEA%"深焙茶","cold, non-lender "+label)
	check(not shown("TeaTake") and not shown("TeaPlace"),"Still no 收回茶陶組 for a non-lender with cold tea (%s)"%label)
	check(Tea.take_block(snap(),bag())==Tea.NOT_LENDER,"Module still refuses take to a non-lender (%s)"%label)
	expect_reason(reasons([Tea.NO_TEA%"深焙茶",Tea.COLD]),"cold, non-lender "+label)
	check(texts().contains(Tea.COLD),"COLD reason visible on the page (%s)"%label)
	focus_ok("cold, non-lender "+label)
	expect_focus("TeaSip","Focus stays on the now-disabled 喝一杯 when the tea goes cold "+label)
	layout_ok("cold, non-lender "+label)
	var refused:Dictionary=other_try(str(GUESTS[1]),Tea.SIP_ACTION)
	check(not bool(refused.get("ok",true)) and str(refused.get("message",""))==Tea.COLD and int(record().round.portions)==5,"Server refuses a cold sip (%s): %s / %s"%[label,str(refused),str(record())])
	# Re-brew the cold pot through the real button.
	if await press("TeaBrew_light","re-brew cold "+label):
		check(cold_day==brewed_day+1 and record().get("round",{})=={"style":"light","portions":6,"claimed":{},"day":cold_day},"Click re-brews the cold pot: fresh six, new day (%s): %s"%[label,str(record())])
		check(held("tea_light")==0 and feedback()==Tea.BREWED_OK%"淺焙茶","Light tea used, reply shown (%s): %s"%[label,feedback()])
		check(not Tea.current_round(snap()).get("cold",true) and Tea.portions(snap())==6,"Fresh round is warm (%s): %s"%[label,str(Tea.current_round(snap()))])
		check(label_text("TeaChip")=="淺焙茶 6／6 杯" and label_text("TeaStatus")=="桌上有一壺淺焙茶，還剩 6／6 杯。","Fresh chip and status (%s): %s / %s"%[label,label_text("TeaChip"),label_text("TeaStatus")])
		expect_button("TeaSip","喝一杯",true,"","re-brewed "+label)
		expect_button("TeaBrew_light","泡淺焙茶・有 0",false,Tea.TEA_LEFT_BREW,"re-brewed "+label)
		expect_focus("TeaSip","Focus moves to 喝一杯 after re-brewing "+label)
		layout_ok("re-brewed after cold "+label)
	# The fresh pot goes cold untouched; still no take for me, the lender takes it back.
	await next_day("cold six, non-lender "+label)
	check(label_text("TeaChip")==UI.TEA_CHIP_COLD and not shown("TeaTake"),"Cold six: chip 茶涼了, no 收回 for a non-lender (%s): %s"%[label,label_text("TeaChip")])
	expect_reason(reasons([Tea.NO_TEA%"淺焙茶",Tea.NO_TEA%"深焙茶",Tea.COLD]),"cold six, no tea "+label)
	layout_ok("cold six, no tea "+label)
	other_act(LENDER,Tea.TAKE_ACTION)
	await refresh()
	check(not w.state.has(Tea.STATE_KEY) and int((w.state.players[LENDER].inventory as Dictionary).get("tea_ware_kit",0))==1,"Lender takes the set back with cold cups left (%s): %s"%[label,str(w.state.get(Tea.STATE_KEY))])
	check(label_text("TeaChip")==UI.TEA_CHIP_NONE,"Card back to 未擺上 (%s)"%label)
	focus_ok("lender took it back "+label)
	# ---- K: cold tea, I am the lender (place, brew, sip through the real buttons).
	await set_bag({"tea_ware_kit":1,"tea_light":1,"tea_deep":1})
	await press("TeaPlace","place for cold "+label)
	check(record()=={"lender":id},"I lend the set (%s): %s"%[label,str(record())])
	await press("TeaBrew_light","brew for cold "+label)
	await press("TeaSip","sip for cold "+label)
	check(int(record().get("round",{}).get("portions",0))==5 and int(record().get("round",{}).get("day",0))==Tea.today(w.state),"My round of today, 5 left (%s): %s"%[label,str(record())])
	expect_button("TeaTake","收回茶陶組",false,Tea.TEA_LEFT,"warm, lender "+label)
	expect_focus("TeaSip","Focus on the disabled 喝一杯 after sipping "+label)
	await next_day("lender cold "+label)
	check(label_text("TeaChip")==UI.TEA_CHIP_COLD,"Lender chip 茶涼了 (%s): %s"%[label,label_text("TeaChip")])
	check(label_text("TeaStatus")==Tea.status_text(snap()) and label_text("TeaStatus")=="前一天泡的淺焙茶已經涼了，可以重新泡一壺。","Lender cold status (%s): %s"%[label,label_text("TeaStatus")])
	expect_button("TeaSip","喝一杯",false,Tea.COLD,"cold, lender "+label)
	expect_button("TeaBrew_light","泡淺焙茶・有 0",false,Tea.NO_TEA%"淺焙茶","cold, lender "+label)
	expect_button("TeaBrew_deep","泡深焙茶・有 1",true,"","cold, lender "+label)
	expect_button("TeaTake","收回茶陶組",true,"把茶陶組收回背包","cold, lender "+label)
	expect_reason(reasons([Tea.NO_TEA%"淺焙茶",Tea.COLD]),"cold, lender "+label)
	focus_ok("cold, lender "+label)
	expect_focus("TeaSip","Focus stays on 喝一杯 when the lender's tea goes cold "+label)
	await key(KEY_RIGHT)
	expect_focus("TeaTake","KEY_RIGHT to the enabled 收回茶陶組 "+label)
	await key(KEY_LEFT)
	expect_focus("TeaSip","KEY_LEFT back to 喝一杯 "+label)
	layout_ok("cold, lender "+label)
	if await press("TeaTake","take back cold "+label):
		check(not w.state.has(Tea.STATE_KEY) and held("tea_ware_kit")==1,"Take back with cold cups left returns the kit (%s): %s"%[label,str(w.state.get(Tea.STATE_KEY))])
		check(feedback()==Tea.TAKEN_OK,"Take reply shown (%s): %s"%[label,feedback()])
		check(label_text("TeaChip")==UI.TEA_CHIP_NONE,"Card back to 未擺上 (%s)"%label)
		expect_focus("TeaPlace","Hidden 收回 hands focus to 擺上茶陶組 "+label)
		layout_ok("cold taken back "+label)
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the page (%s)"%label)
	# ---- backpack: 茶陶組 description mentions the table.
	await set_bag({"tea_ware_kit":1})
	app._inventory()
	await settle()
	check(app.modal is InventoryPanel,"Backpack opens (%s)"%label)
	if app.modal is InventoryPanel:
		var panel=app.modal
		panel.select_item("tea_ware_kit")
		await settle()
		var use:String=panel.detail_use.text
		check(use.begins_with("紀念物・") and use.contains("只是裝飾") and use.contains("渡口共餐桌") and use.contains("「生活」") and use.contains(app.binding_label("build_menu")) and not use.contains("上菜"),"茶陶組 description mentions home decoration and the 渡口共餐桌 (%s): %s"%[label,use])
		check(not_cut(panel.detail_use) and (panel as Control).get_global_rect().grow(0.5).encloses(panel.detail_use.get_global_rect()),"茶陶組 description whole (%s)"%label)
	await close_page()

func run()->void:
	create_timer(240.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 240 s")
		finish())
	var started:=Time.get_ticks_msec()
	path=OS.get_environment("TEMP").path_join("tea-service-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"茶陶旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	if not app.playing:note("app.playing was false after host; set true for key input");app.playing=true
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	w.add_player(LENDER,"茶友")  # FIXTURE islander
	for i in range(GUESTS.size()):w.add_player(str(GUESTS[i]),"茶客%d"%(i+1))  # FIXTURE islanders
	await refresh()
	if WanganUI.card_open(app):
		await key(KEY_E)
		check(not WanganUI.card_open(app),"First E closes the arrival card")
	var note_text:String=str(Panels.BUILD_NOTES.get("tea_ware",""))
	check(note_text.contains("茶壺和茶杯擺在木托盤上") and note_text.contains("只是裝飾") and note_text.contains("渡口共餐桌") and not note_text.contains("上菜"),"生活 note for 茶陶組 mentions decoration and the 渡口共餐桌: %s"%note_text)
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		await size_flow(tag)
		note("size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
