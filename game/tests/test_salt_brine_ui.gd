extends SceneTree
## 第 40 章「北門合作鹽田・儲滷槽」頁 UI test (headless) at 1024×640 and 1280×800, plus the
## 儲滷槽 line (SaltBrineLine) on the 鹽籃批次 page. Same harness as test_salt_revisit_ui.gd: real
## Session host, real snapshot round trips, real key / mouse events.
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true is set here;
##  * the chapter 1/2/3 story fixture of test_salt_revisit_ui (picnic / board / chapter_one, tea,
##    flower record + garden, travel_book.visited tianwei + beimen) and my salt_pan record
##    (letter / intro; raked 0, later 1);
##  * the three Beimen gates (gates + repaired_at) — unrepaired for the locked state, then repaired;
##  * salt_pan.lots / apprentice / pans reset to fresh before each size; lot 0 claimed by me
##    (owner, then wheel=true) — the earned claim / wheel install is covered by the salt journey tests;
##  * pans 0 and 1 (my west / east pans) written as empty / brine {p, t=now, f="wheel"} / salt;
##  * state.salt_brine erased, or written as {"level":30} (tank full) and {"level":5} (rain);
##  * state.time: a sunny Beimen day, +96 s for the lazy progress check, a rainy Beimen day;
##  * the local player is teleported by writing region/x/y (no walking or travel);
##  * session rate buckets / action_clock cleared.
## REALLY EXERCISED (local player):
##  * KEY_E through root.push_input -> main._interact next to the tank (TANK_STAND) opens the page;
##    KEY_ESCAPE closes; KEY_LEFT / RIGHT / UP / DOWN move focus; KEY_ENTER on 收滷 and a real mouse
##    click on 放滷 send salt_brine_store / salt_brine_pour through Session.perform -> World ->
##    snapshot -> in-place update (level, tenths); the server's reply in the page footer;
##  * every store / pour is the server's (no salt_brine writes except the full / rain fixtures);
##  * KEY_ENTER on 翻閱鹽田手帳 (not ready) opens the salt journal;
##  * 阿曬 (KEY_E) -> 「臺南北門回訪・鹽籃批次」 (KEY_ENTER) shows SaltBrineLine with the level.
## NOT COVERED HERE: the tank's world sprite / focus label (world_view, art worker's suite); the
## apprentice-shift unit; a second client; gamepad input; the non-preview layout.
const World=preload("res://scripts/world.gd")
const Brine=preload("res://scripts/salt_brine.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const SR=preload("res://scripts/salt_revisit.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const UI=preload("res://scripts/salt_brine_ui.gd")
const RevisitUI=preload("res://scripts/salt_revisit_ui.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const Weather=preload("res://scripts/weather.gd")
const FAR_SPOT:=Vector2(44.5,18.5)  # = SR.WORKER_STAND, about 5.7 tiles from the tank
var app
var w
var id:=""
var path:=""
var checks:=0
var failures:=0
var finished:=false
var sunny_time:=0.0
var rain_time:=0.0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("SALT_BRINE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE SALT_BRINE_UI "+message)

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

func salt_site()->String:
	return str((app.modal as Node).get_meta("salt_site","")) if is_instance_valid(app.modal) else ""

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

func salt_record()->Dictionary:
	return w.state.salt_pan.players[id]

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func focused_name()->String:
	var owner:=root.gui_get_focus_owner()
	return str(owner.name) if owner!=null else "none"

func close_focused()->bool:
	var close:=UI.close_button(app)
	return close!=null and root.gui_get_focus_owner()==close

func stand(at:Vector2,region:String)->void:
	var p:Dictionary=person()
	p.region=region  # PRESET
	p.x=at.x;p.y=at.y  # PRESET
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	var ribbon:Node=app.hud.get_node_or_null("TravelArrival")
	if ribbon!=null:app.hud.remove_child(ribbon);ribbon.queue_free()
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

## Focus a button and press it with a real KEY_ENTER.
func enter_on(name:String,label:String)->bool:
	var b:=button(name)
	check(b!=null and not b.disabled and b.is_visible_in_tree(),"Enabled %s (%s)"%[name,label])
	if b==null or b.disabled:return false
	b.grab_focus()
	await settle()
	await act_key(KEY_ENTER)
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

func click_on(name:String,label:String)->void:
	var b:=button(name)
	check(b!=null and not b.disabled and b.is_visible_in_tree(),"Enabled %s for a click (%s)"%[name,label])
	if b==null:return
	app.action_clock=0
	app.session.rates[1].clear()
	await mouse_at(b.get_global_rect().get_center())
	await settle()
	await refresh()

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

# ------------------------------------------------------------------ fixture --

## Chapter 1/2/3 FIXTURE (as test_salt_revisit_ui.story_fixture) and my Beimen record.
func story_fixture()->void:
	w.state.picnic=true  # PRESET
	w.state.board=true  # PRESET
	w.state.chapter_one.shipped=true  # PRESET
	w.state.chapter_one.watered=true  # PRESET
	var tea:Dictionary=Tea.FRESH.duplicate(true)
	tea.intro=true;tea.potter=true;tea.reused=true;tea.reuse_count=1
	tea.trials={"jar":true,"fiber":true};tea.tea_discussed=true;tea.comparison_complete=true
	w.state.tea_ceramics.players[id]=tea  # PRESET
	var a:Dictionary=Flower.FRESH.duplicate(true)
	a.letter=true;a.intro=true;a.shipped=true;a.complete=true
	for kind in Flower.FLOWERS:
		a.planted[kind]=true;a.harvested[kind]=2;a.saved[kind]=true
	w.state.flower_nursery.players[id]=a  # PRESET
	person().travel_book.visited[Flower.REGION]=true  # PRESET
	person().travel_book.visited[Salt.REGION]=true  # PRESET
	w.state.flower_nursery.garden={"given":{"blue_dye":4,"orange_blossom":4,"chime_herb":2},"contributors":{id:10},"complete":true,"completed_at":0.0}  # PRESET
	var rec:Dictionary=Salt.RECORD.duplicate(true)
	rec.letter=true;rec.intro=true
	w.state.salt_pan.players[id]=rec  # PRESET

func set_gates(repaired:bool)->void:
	for g in Salt.GATE_ROWS.size():
		w.state.salt_pan.gates[g]={"plank":6,"resin":1,"stone":4} if repaired else {"plank":0,"resin":0,"stone":0}  # PRESET
	w.state.salt_pan.repaired_at=1.0 if repaired else -1.0  # PRESET

## Lot 0 is mine (pans 0 = west, 1 = east).
func own_lot(wheel:bool)->void:
	var cfg:Dictionary=Salt.fresh_lot()
	cfg.owner=id;cfg.wheel=wheel
	w.state.salt_pan.lots[0]=cfg  # PRESET

func set_pan(i:int,state:String,p:float=0.0)->void:
	var pan:Dictionary=w.state.salt_pan.pans[i]
	pan.s=state  # PRESET
	match state:
		"brine":pan.p=p;pan.t=float(w.state.time);pan.f="wheel"  # PRESET
		"salt":pan.p=Salt.NEED;pan.t=float(w.state.time);pan.f="wheel"  # PRESET
		_:pan.p=0.0;pan.t=0.0;pan.f=""  # PRESET

func set_level(n:int)->void:
	if n<0:w.state.erase(Brine.STATE_KEY)  # PRESET
	else:w.state[Brine.STATE_KEY]={"level":n}  # PRESET

func level()->int:
	return Brine.level(w.state)

## A sunny Beimen day followed by another sunny one, and a later rainy day.
func find_days()->void:
	for d in range(1,30):
		if Weather.outdoor_id(float(d))=="sunny" and Weather.outdoor_id(float(d+1))=="sunny":
			sunny_time=d*1440.0+30.0
			break
	for d in range(int(sunny_time/1440.0)+1,40):
		if Salt.raining(d*1440.0+30.0):
			rain_time=d*1440.0+30.0
			return

# ------------------------------------------------------------------- layout --

## Page inside the viewport, no outer scrolling, every visible label / button / icon inside
## the page and whole, no ellipsis.
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
		if not (c is BaseButton or c is Label or c is TextureRect or c is ColorRect):continue
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the page (%s) %s"%[c.name,label,rect_info(c)])
		if outer!=null and outer.is_ancestor_of(c):check(outer.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the visible scroll area (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not texts().contains("…"),"No ellipsis anywhere in the page (%s)"%label)
	if expected==UI.LAYOUT:
		check(label_text("SbDisclaimer")==Brine.DISCLAIMER and shown("SbDisclaimer"),"Fiction disclaimer shown (%s)"%label)
		check(label_text("SbBlurb")==Brine.BLURB and shown("SbBlurb"),"Blurb shown (%s)"%label)

func focus_ok(label:String)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and owner.is_visible_in_tree(),"Keyboard focus is on a visible button inside the page (%s): %s"%[label,focused_name()])

func button_state(name:String,enabled:bool,reason:String,label:String)->void:
	var b:=button(name)
	check(b!=null and b.is_visible_in_tree() and b.disabled==not enabled,"%s %s (%s)"%[name,"enabled" if enabled else "disabled",label])
	if b!=null and not enabled:
		check(b.tooltip_text==reason,"%s tooltip 「%s」 (%s): %s"%[name,reason,label,b.tooltip_text])
		check(b.focus_mode==Control.FOCUS_ALL,"%s stays focusable while disabled (%s)"%[name,label])

func caption(name:String,expected:String,label:String)->void:
	var b:=button(name)
	check(b!=null and b.text==expected,"%s caption 「%s」 (%s): %s"%[name,expected,label,b.text if b!=null else "none"])

func state_is(side:String,expected:String,label:String)->void:
	check(label_text("SbState_"+side)==expected,"%s state 「%s」 (%s): %s"%[side,expected,label,label_text("SbState_"+side)])

func reason_is(side:String,expected:String,label:String)->void:
	check(label_text("SbReason_"+side)==expected and (expected.is_empty() or shown("SbReason_"+side)),"%s reason 「%s」 (%s): 「%s」"%[side,expected.replace("\n"," / "),label,label_text("SbReason_"+side).replace("\n"," / ")])

func level_is(n:int,label:String)->void:
	check(label_text("SbLevel")=="槽裡 %d／30 桶"%n,"Level line %d (%s): %s"%[n,label,label_text("SbLevel")])
	var filled:=control("SbBar_%d"%maxi(n-1,0)) as ColorRect
	var empty:=control("SbBar_%d"%mini(n,Brine.CAP-1)) as ColorRect
	if n>0:check(filled!=null and filled.color==UI.BRINE_FILL,"Gauge cell %d filled (%s)"%[n,label])
	if n<Brine.CAP:check(empty!=null and empty.color==UI.EMPTY_FILL,"Gauge cell %d empty (%s)"%[n+1,label])

func block_is(expected:String,label:String)->void:
	check(shown("SbBlock") and label_text("SbBlockText")==expected,"Single reason card 「%s」 (%s): %s"%[expected,label,label_text("SbBlockText")])
	check(not shown("SbCards") and not shown("Sb_store_a") and not shown("Sb_pour_b"),"No pan rows while blocked (%s)"%label)

# --------------------------------------------------------------------- flows --

func reset()->void:
	await close_page()
	var data:Dictionary=w.state.salt_pan
	for i in data.lots.size():data.lots[i]=Salt.fresh_lot()  # PRESET
	data.apprentice=Salt.fresh_apprentice()  # PRESET
	for i in data.pans.size():data.pans[i]=Salt.fresh_pan()  # PRESET
	story_fixture()
	set_gates(false)
	set_level(-1)
	w.state.time=sunny_time  # PRESET (a sunny Beimen day)
	await refresh()

func open_tank(label:String)->void:
	await close_page()
	await stand(Brine.TANK_STAND,Salt.REGION)
	note("view focus next to the tank: %s"%str(app.view.interaction_focus()))
	await interact_key()
	check(page_open(),"E next to the tank opens the 儲滷槽 page (%s): %s"%[label,layout_name()])
	if page_open():check(str((app.modal as Node).get_meta("suppress_world_prompts",false))=="true","Page hides world prompts (%s)"%label)

func locked_flow(label:String)->void:
	await open_tank("locked "+label)
	if not page_open():return
	block_is(Brine.LOCKED,"locked "+label)
	check(not shown("SbNotebook"),"No journal link while locked (%s)"%label)
	level_is(0,"locked "+label)
	var day:=int(sunny_time/1440.0)+1
	check(label_text("SbWeather")=="第 %d 日・北門晴天"%day,"Weather line (%s): %s"%[label,label_text("SbWeather")])
	check(not shown("SbRain"),"No rain line on a sunny day (%s)"%label)
	check(feedback()==UI.KEY_HINT,"Key hint in the footer (%s): %s"%[label,feedback()])
	check(close_focused(),"Nothing to press: focus on 關閉 (%s): %s"%[label,focused_name()])
	layout_ok("locked "+label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes (%s)"%label)

func not_ready_flow(label:String)->void:
	set_gates(true)
	await open_tank("not ready "+label)
	if not page_open():return
	block_is(Brine.NOT_READY,"not ready "+label)
	check(shown("SbNotebook") and focused_name()=="SbNotebook","Journal link shown and focused (%s): %s"%[label,focused_name()])
	layout_ok("not ready "+label)
	await act_key(KEY_ENTER)
	check(layout_name()=="salt_pan" and salt_site()=="journal","Enter opens the salt journal (%s): %s %s"%[label,layout_name(),salt_site()])
	await close_page()

## No unit -> no wheel -> wheel with empty pans, in place on one open page.
func unit_flow(label:String)->void:
	salt_record().raked=1  # PRESET
	await open_tank("no unit "+label)
	if not page_open():return
	var modal_before:Node=app.modal
	block_is(Brine.NO_UNIT,"no unit "+label)
	check(not shown("SbNotebook"),"No journal link once raked (%s)"%label)
	layout_ok("no unit "+label)
	own_lot(false)
	await refresh()
	check(app.modal==modal_before,"Same page after claiming (%s)"%label)
	block_is(Brine.NO_WHEEL,"no wheel "+label)
	layout_ok("no wheel "+label)
	own_lot(true)
	await refresh()
	check(app.modal==modal_before and shown("SbCards") and not shown("SbBlock"),"Pan cards appear in place with a wheel (%s)"%label)
	await empty_checks("in place "+label)
	# Reopen with E: focus rests on the first pan button (nothing can be pressed).
	await open_tank("empty "+label)
	if not page_open():return
	await empty_checks("reopened "+label)
	check(focused_name()=="Sb_store_a","Focus on the first pan button (%s): %s"%[label,focused_name()])
	await key(KEY_RIGHT)
	check(focused_name()=="Sb_pour_a","KEY_RIGHT to 放滷 west (%s): %s"%[label,focused_name()])
	await key(KEY_RIGHT)
	check(focused_name()=="Sb_store_b","KEY_RIGHT to 收滷 east (%s): %s"%[label,focused_name()])
	await key(KEY_RIGHT)
	check(focused_name()=="Sb_pour_b","KEY_RIGHT to 放滷 east (%s): %s"%[label,focused_name()])
	await key(KEY_RIGHT)
	check(focused_name()=="Sb_store_a","KEY_RIGHT wraps (%s): %s"%[label,focused_name()])
	await key(KEY_LEFT)
	check(focused_name()=="Sb_pour_b","KEY_LEFT wraps back (%s): %s"%[label,focused_name()])
	await key(KEY_UP)
	check(close_focused(),"KEY_UP to 關閉 (%s): %s"%[label,focused_name()])
	await key(KEY_DOWN)
	check(focused_name()=="Sb_store_a","KEY_DOWN back to the pans (%s): %s"%[label,focused_name()])
	layout_ok("empty "+label)

func empty_checks(label:String)->void:
	check(label_text("SbName_a")=="西側鹽田（鹽田 1）" and label_text("SbName_b")=="東側鹽田（鹽田 2）","Pan card names (%s): %s / %s"%[label,label_text("SbName_a"),label_text("SbName_b")])
	for side in ["a","b"]:
		state_is(side,UI.STATE_EMPTY,"empty "+label)
		button_state("Sb_store_"+side,false,Brine.PAN_EMPTY,"empty "+label)
		button_state("Sb_pour_"+side,false,Brine.PAN_EMPTY,"empty "+label)
		caption("Sb_store_"+side,"收滷","empty "+label)
		caption("Sb_pour_"+side,"放滷","empty "+label)
		reason_is(side,Brine.PAN_EMPTY,"empty "+label)

## Thin / storable / tank empty, store with Enter, pour with a click, lazy progress.
func brine_flow(label:String)->void:
	set_pan(0,"brine",30.0)
	set_pan(1,"brine",150.0)
	await refresh()
	if not page_open():return
	var modal_before:Node=app.modal
	var card_before:=control("SbCard_b")
	state_is("a","滷水約 0 成","thin "+label)
	button_state("Sb_store_a",false,Brine.THIN%0,"thin "+label)
	button_state("Sb_pour_a",false,Brine.TANK_EMPTY,"tank empty "+label)
	reason_is("a","收滷："+Brine.THIN%0+"\n放滷："+Brine.TANK_EMPTY,"thin "+label)
	state_is("b","滷水約 3 成","storable "+label)
	button_state("Sb_store_b",true,"","storable "+label)
	caption("Sb_store_b","收滷 3 桶","storable "+label)
	var store_tip:String=button("Sb_store_b").tooltip_text if button("Sb_store_b")!=null else ""
	check(store_tip==UI.STORE_TIP%3,"Store tooltip (%s): %s"%[label,store_tip])
	button_state("Sb_pour_b",false,Brine.TANK_EMPTY,"tank empty "+label)
	reason_is("b","放滷："+Brine.TANK_EMPTY,"storable "+label)
	level_is(0,"before store "+label)
	layout_ok("thin / storable "+label)
	# KEY_ENTER on 收滷 3 桶.
	await enter_on("Sb_store_b","store "+label)
	check(level()==3 and feedback()==Brine.STORE_OK%[3,3],"KEY_ENTER stores 3 buckets through the server (%s): %d %s"%[label,level(),feedback()])
	check(app.modal==modal_before and control("SbCard_b")==card_before,"Page updated in place (%s)"%label)
	check(focused_name()=="Sb_store_b","Focus stays on the pressed button (%s): %s"%[label,focused_name()])
	level_is(3,"after store "+label)
	state_is("b","滷水約 0 成","after store "+label)
	button_state("Sb_store_b",false,Brine.THIN%0,"after store "+label)
	caption("Sb_pour_b","放滷 3 桶","after store "+label)
	caption("Sb_pour_a","放滷 3 桶","after store "+label)
	focus_ok("after store "+label)
	layout_ok("after store "+label)
	# A real mouse click on 放滷 3 桶 (west).
	await click_on("Sb_pour_a","pour "+label)
	check(level()==0 and feedback()==Brine.POUR_OK%[3,3,0],"Click pours 3 buckets through the server (%s): %d %s"%[label,level(),feedback()])
	check(app.modal==modal_before,"Still the same page after pouring (%s)"%label)
	level_is(0,"after pour "+label)
	state_is("a","滷水約 3 成","after pour "+label)
	button_state("Sb_pour_a",false,Brine.TANK_EMPTY,"after pour "+label)
	# Lazy progress: 96 s of sun later (no pan writes), both pans read further on.
	w.state.time=float(w.state.time)+96.0  # PRESET (time passes)
	await refresh()
	state_is("a","滷水約 5 成","lazy progress "+label)
	state_is("b","滷水約 2 成","lazy progress "+label)
	check(app.modal==modal_before,"Lazy progress updates in place (%s)"%label)
	layout_ok("lazy progress "+label)

## Tank full (store refused) and a rich pan (pour refused).
func full_flow(label:String)->void:
	set_level(30)
	set_pan(0,"brine",150.0)
	set_pan(1,"brine",470.0)
	await refresh()
	if not page_open():return
	level_is(30,"full "+label)
	button_state("Sb_store_a",false,Brine.TANK_FULL,"full "+label)
	button_state("Sb_pour_a",true,"","full "+label)
	caption("Sb_pour_a","放滷 6 桶","full "+label)
	reason_is("a","收滷："+Brine.TANK_FULL,"full "+label)
	state_is("b","滷水約 9 成","rich "+label)
	button_state("Sb_pour_b",false,Brine.PAN_RICH,"rich "+label)
	reason_is("b","收滷："+Brine.TANK_FULL+"\n放滷："+Brine.PAN_RICH,"rich "+label)
	layout_ok("full / rich "+label)

func salt_flow(label:String)->void:
	set_level(-1)
	set_pan(0,"salt")
	set_pan(1,"empty")
	await refresh()
	if not page_open():return
	state_is("a",UI.STATE_SALT,"salt "+label)
	button_state("Sb_store_a",false,Brine.PAN_SALT,"salt "+label)
	button_state("Sb_pour_a",false,Brine.PAN_SALT,"salt "+label)
	reason_is("a",Brine.PAN_SALT,"salt "+label)
	reason_is("b",Brine.PAN_EMPTY,"salt "+label)
	layout_ok("salt "+label)

## A rainy day: store allowed and performed, pour refused with RAIN_POUR.
func rain_flow(label:String)->void:
	w.state.time=rain_time  # PRESET (a rainy Beimen day)
	set_level(5)
	set_pan(0,"brine",150.0)
	set_pan(1,"brine",100.0)
	await refresh()
	if not page_open():return
	check(Brine.rainy_now(snap()),"Rainy Beimen day (%s)"%label)
	check(shown("SbRain") and label_text("SbRain")==UI.RAIN_LINE,"Rain line (%s): %s"%[label,label_text("SbRain")])
	check(label_text("SbWeather").ends_with("北門小雨"),"Weather says rain (%s): %s"%[label,label_text("SbWeather")])
	button_state("Sb_store_a",true,"","rain store "+label)
	button_state("Sb_pour_a",false,Brine.RAIN_POUR,"rain pour "+label)
	reason_is("a","放滷："+Brine.RAIN_POUR,"rain "+label)
	layout_ok("rain "+label)
	await enter_on("Sb_store_a","rain store "+label)
	check(level()==8 and feedback()==Brine.STORE_OK%[3,8]+Brine.STORE_RAIN_NOTE,"Rainy store through the server (%s): %d %s"%[label,level(),feedback()])
	level_is(8,"rain stored "+label)
	button_state("Sb_pour_a",false,Brine.RAIN_POUR,"rain after store "+label)
	reason_is("a","收滷："+Brine.THIN%0+"\n放滷："+Brine.RAIN_POUR,"rain after store "+label)
	layout_ok("rain stored "+label)

## Rules allow everything, but the player stands too far: say where to stand.
func far_flow(label:String)->void:
	w.state.time=sunny_time  # PRESET
	set_level(3)
	set_pan(0,"brine",150.0)
	set_pan(1,"brine",100.0)
	await refresh()
	if not page_open():return
	for b in UI.ACTION_IDS:button_state(b,true,"","near "+label)
	await stand(FAR_SPOT,Salt.REGION)
	check(page_open(),"Page stays open while moving away (%s)"%label)
	for b in UI.ACTION_IDS:button_state(b,false,UI.away_text(),"too far "+label)
	reason_is("a",UI.away_text(),"too far "+label)
	reason_is("b",UI.away_text(),"too far "+label)
	focus_ok("too far "+label)
	layout_ok("too far "+label)
	await stand(Brine.TANK_STAND,Salt.REGION)
	button_state("Sb_store_a",true,"","back near "+label)
	reason_is("a","","back near "+label)
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes (%s)"%label)

## The 鹽籃批次 page carries the tank level (level 3 from far_flow).
func revisit_flow(label:String)->void:
	await close_page()
	await stand(SR.WORKER_STAND,SR.REGION)
	await interact_key()
	check(layout_name()=="salt_pan" and salt_site()=="worker","E opens 阿曬's page (%s): %s %s"%[label,layout_name(),salt_site()])
	await enter_on("SaltRevisitEntry","revisit "+label)
	check(layout_name()==RevisitUI.LAYOUT,"Entry opens the batch page (%s): %s"%[label,layout_name()])
	if layout_name()!=RevisitUI.LAYOUT:return
	check(label_text("SaltBrineLine")==RevisitUI.BRINE_LINE%3 and shown("SaltBrineLine"),"SaltBrineLine with the level (%s): %s"%[label,label_text("SaltBrineLine")])
	layout_ok("revisit "+label,RevisitUI.LAYOUT)
	await key(KEY_ESCAPE)

func size_flow(label:String)->void:
	await reset()
	await locked_flow(label)
	await not_ready_flow(label)
	await unit_flow(label)
	await brine_flow(label)
	await full_flow(label)
	await salt_flow(label)
	await rain_flow(label)
	await far_flow(label)
	await revisit_flow(label)

func pure_checks()->void:
	check(UI.reason_text("x","x")=="x" and UI.reason_text("","")=="","Same reason once")
	check(UI.reason_text("a","")=="收滷：a" and UI.reason_text("","b")=="放滷：b" and UI.reason_text("a","b")=="收滷：a\n放滷：b","Different reasons, one line each")
	check(UI.state_text({"s":"brine","tenths":4})=="滷水約 4 成" and UI.state_text({"s":"salt"})==UI.STATE_SALT and UI.state_text({})==UI.STATE_EMPTY,"State texts")
	check(UI.store_caption(3)=="收滷 3 桶" and UI.store_caption(0)=="收滷" and UI.pour_caption(2)=="放滷 2 桶","Button captions")
	var s:Dictionary={"time":30.0,"region_id":"beimen","salt_pan":{"repaired":true,"own":{"record":{"raked":1},"unit":{"kind":"","index":-1}}}}
	var me:Dictionary={"x":Brine.TANK_STAND.x,"y":Brine.TANK_STAND.y}
	check(UI.near(s,me) and not UI.near(s,{"x":FAR_SPOT.x,"y":FAR_SPOT.y}),"Near the tank at TANK_STAND, not at 阿曬")
	check(UI.store_reason(s,me,"a")==Brine.NO_UNIT,"Rules reason before position")
	check(RevisitUI.brine_line(s)==RevisitUI.BRINE_LINE%0,"Revisit line at level 0")
	s.salt_pan.repaired=false
	check(RevisitUI.brine_line(s).is_empty(),"No revisit line before the gates")
	s.region_id="home"
	check(not UI.near(s,me),"Not near outside Beimen")
	check(UI.weather_line({})=="第 1 日・北門晴天","Defensive weather line")

func run()->void:
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	var started:=Time.get_ticks_msec()
	pure_checks()
	find_days()
	check(sunny_time>0.0 and rain_time>sunny_time,"Calendar has two sunny Beimen days and a later rainy one: %.0f %.0f"%[sunny_time,rain_time])
	path=OS.get_environment("TEMP").path_join("salt-brine-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"儲滷旅人",path)!=OK:check(false,"Host starts");finish();return
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
	await close_page()
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
