extends SceneTree
## 望安開場 UI test (headless) at 1024×640 and 1280×800 through the real app.
##
## PRESET / FIXTURE (not human play):
##  * each size hosts its own isolated save in %TEMP% (deleted at the end) and sets
##    app.village_art_preview=true (the runner passes no flag for this suite);
##    app processing and Session physics are off except during the movement check,
##    so world time only moves with the World.step calls below;
##  * after a dismissal the card is shown again with WanganUI.show_arrival(app) to
##    try the next dismissal (Esc, button, Enter);
##  * the player is teleported by writing x/y (to the plot, to the bin, to the
##    harvest-relay sign); the crop is grown with World.step;
##  * override checks write state.festival.active, players[me].region="lanyang",
##    and state.board/picnic=true (needed to start 豐收接力) directly, then restore;
##  * the shipment is sent with session.perform("ship", bin, payload) — the same
##    call the shipping panel makes — instead of driving the panel.
## REALLY EXERCISED: Session.host -> main._entered -> arrival card; KEY_E / Esc /
##  Enter through root.push_input -> main._input/_unhandled_input; the card button's
##  pressed signal; held move_right through Input.parse_input_event -> main._process
##  -> Session movement -> World.move_player; tool keys + left clicks on world cells
##  through root.push_input (hoe, seed, water, harvest); the HUD tracker text after
##  each real action; reconnecting to the same save (returning player).
const World=preload("res://scripts/world.gd")
const Chapter=preload("res://scripts/chapter_one.gd")
const Opening=preload("res://scripts/wangan_opening.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const Relay=preload("res://scripts/harvest_relay.gd")
var app
var w
var id:=""
var me:=""
var path:=""
var paths:Array[String]=[]
var checks:=0
var failures:=0
var finished:=false

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func note(message:String)->void:
	print("NOTE WANGAN_UI "+message)

func finish()->void:
	if finished:return
	finished=true
	for item in paths:
		for suffix in ["",".bak",".tmp",".writer-lock",".bindings"]:
			if FileAccess.file_exists(item+suffix):DirAccess.remove_absolute(item+suffix)
	print("WANGAN_OPENING_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ------------------------------------------------------------------ helpers --

func settle()->void:
	for i in range(5):await process_frame
	app._layout_preview();await process_frame

func refresh()->void:
	app.session._send_snapshot(1)
	app.view._process(0.0)
	app._refresh_hud()
	await settle()

func card()->Control:
	return WanganUI.card(app)

func card_text(name:String)->String:
	var c:=card()
	if c==null:return ""
	var l:=c.find_child(name,true,false) as Label
	return l.text if l!=null else ""

func key(code:int)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		root.push_input(e)
	await settle()

func bound(action:String)->int:
	return int(app.bindings.keys.get(action,KEY_NONE))

func person()->Dictionary:
	return w.state.players[me]

func stand(at:Vector2)->void:
	var p:=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	await refresh()
	var v=app.view
	if v.goals.has(id):
		v.starts[id]=v.goals[id]
		v.display_positions[id]=v.goals[id]
	v._process(0.0)
	await settle()

func click(cell:Vector2i)->void:
	app.action_clock=0
	app.session.rates[1].clear()
	app.view._process(0.0)
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

func tool_click(action:String,cell:Vector2i)->void:
	await key(bound(action))
	check(app.selected==action,"Tool key selects %s: %s"%[action,app.selected])
	await click(cell)

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

func hud_rect(name:String)->Rect2:
	var c:=app.hud.find_child(name,true,false) as Control
	return c.get_global_rect() if c!=null and c.is_visible_in_tree() else Rect2()

## Tracker stays inside the viewport and clear of the toolbar, every line whole.
func tracker_ok(label:String)->void:
	var view_rect:=root.get_visible_rect()
	var tracker:Control=app.preview_tracker
	check(tracker.is_visible_in_tree() and view_rect.encloses(tracker.get_global_rect()),"Tracker inside the viewport (%s) %s"%[label,str(tracker.get_global_rect())])
	check(not tracker.get_global_rect().intersects(app.preview_toolbar.get_global_rect()),"Tracker clear of the toolbar (%s)"%label)
	check(not tracker.get_global_rect().intersects(hud_rect("LifeShortcuts")),"Tracker clear of the shortcuts (%s)"%label)
	check(not_cut(app.objective),"Tracker text not cut (%s): %s"%[label,app.objective.text])
	check(app.objective.get_global_rect().end.x<=tracker.get_global_rect().end.x+0.5 and app.objective.get_global_rect().end.y<=tracker.get_global_rect().end.y+0.5,"Tracker text inside its box (%s)"%label)
	check(tracker.size.x<=246.5,"Tracker keeps its width (%s): %.0f"%[label,tracker.size.x])

func card_ok(label:String)->void:
	var c:=card()
	check(c!=null and c.is_visible_in_tree(),"Arrival card visible (%s)"%label)
	if c==null:return
	var view_rect:=root.get_visible_rect()
	var r:=c.get_global_rect()
	check(view_rect.encloses(r),"Card inside the viewport (%s) %s"%[label,str(r)])
	for other in [app.preview_tracker.get_global_rect(),hud_rect("RegionTitle"),app.preview_top.get_global_rect(),app.preview_toolbar.get_global_rect(),hud_rect("LifeShortcuts")]:
		check(other.size==Vector2.ZERO or not r.intersects(other),"Card does not cover HUD %s (%s) card=%s"%[str(other),label,str(r)])
	var foot:Vector2=app.view.screen(app.view.display_positions.get(id,Vector2(person().x,person().y)))*app.view.view_zoom()
	var body:=Rect2(foot+Vector2(-16,-48)*app.view.view_zoom(),Vector2(32,48)*app.view.view_zoom())
	check(not r.intersects(body),"Card leaves the player visible (%s) body=%s card=%s"%[label,str(body),str(r)])
	for node in c.find_children("*","Control",true,false):
		var item:=node as Control
		if not item.is_visible_in_tree():continue
		check(r.grow(0.5).encloses(item.get_global_rect()),"%s inside the card (%s)"%[item.name,label])
		if item is Label:check(not_cut(item as Label),"Card label whole: %s 「%s」 (%s)"%[item.name,(item as Label).text,label])
		if item is Button:check((item as Button).size.x+0.5>=(item as Button).get_combined_minimum_size().x,"Card button caption whole (%s)"%label)
	check(card_text("ArrivalPlace")=="澎湖・望安","Place name 澎湖・望安 (%s): %s"%[label,card_text("ArrivalPlace")])
	check(card_text("ArrivalScene")=="風鈴渡口","Scene 風鈴渡口 (%s): %s"%[label,card_text("ArrivalScene")])
	check(card_text("ArrivalBoat")=="你搭船來到澎湖・望安，在風鈴渡口下了船。","Came by boat, stepped off at the ferry (%s): %s"%[label,card_text("ArrivalBoat")])
	check(card_text("ArrivalLine").replace("\n","")=="「小栗在渡口旁留了一塊地給你。先種一株蘿蔔，收成後帶到出貨箱。」" and card_text("ArrivalLine").count("\n")==1,"Opening line verbatim, broken only between its two sentences (%s): %s"%[label,card_text("ArrivalLine")])
	var quote:=c.find_child("ArrivalLine",true,false) as Label
	check(quote!=null and quote.get_line_count()==2,"Opening line shows as exactly two lines, 出貨箱 not split (%s): %d"%[label,quote.get_line_count() if quote else -1])
	# Passive world labels never peek out from under the card.
	var zoom:float=app.view.view_zoom()
	for entry in app.view.world_label_placements(Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom)):
		if entry.active:continue
		var box:Rect2=entry.rect
		check(not Rect2(box.position*zoom,box.size*zoom).intersects(r),"Label 「%s」 not under the card (%s)"%[entry.title,label])
	check(card_text("ArrivalHint")=="%s／Esc 收起這張卡"%app.binding_label("interact"),"Hint names the real interact key (%s): %s"%[label,card_text("ArrivalHint")])
	var go:=c.find_child("ArrivalClose",true,false) as Button
	check(go!=null and go.text=="出發去找小栗" and go.focus_mode==Control.FOCUS_NONE,"Card button present and never takes focus (%s)"%label)
	check(root.gui_get_focus_owner()==null,"Nothing holds focus with the card open (%s): %s"%[label,str(root.gui_get_focus_owner())])
	check(app.modal==null and app._world_keyboard_allowed(),"Card is not a modal; world keys stay live (%s)"%label)

func expect_tracker(expected:String,label:String)->void:
	check(str(app.objective.text)==expected,"Tracker (%s): 「%s」 expected 「%s」"%[label,app.objective.text,expected])
	tracker_ok(label)

# --------------------------------------------------------------------- flow --

func open_app(size:Vector2i,save:String)->bool:
	root.size=size
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(save+".bindings")
	if app.session.host(0,"望安旅人",save)!=OK:
		check(false,"Host starts")
		return false
	# No forced relayout here: the card must fit its text on its own (a tall card
	# would swallow world clicks below it).
	for i in 4:await process_frame
	var fresh:=card()
	if fresh!=null:check(fresh.size.y<=fresh.get_combined_minimum_size().y+1.0 and fresh.size.y<=240.0,"Card fits its text without a forced relayout (%dx%d): %s"%[size.x,size.y,str(fresh.size)])
	await settle()
	w=app.session.world;me=app.session.profile.token;id=app.session.own_id
	if not app.playing:app.playing=true
	await refresh()
	return true

func close_app()->void:
	app.session.shutdown()
	await create_timer(0.2).timeout
	app.queue_free()
	await process_frame
	await process_frame

func movement_after_close(label:String)->void:
	var before:=Vector2(person().x,person().y)
	var code:=bound("move_right")
	var press:=InputEventKey.new();press.keycode=code;press.physical_keycode=code;press.pressed=true
	app.set_process(true);app.session.set_physics_process(true)
	Input.parse_input_event(press)
	await create_timer(0.35).timeout
	var release:=InputEventKey.new();release.keycode=code;release.physical_keycode=code;release.pressed=false
	Input.parse_input_event(release)
	await create_timer(0.15).timeout
	app.set_process(false);app.session.set_physics_process(false)
	app.session.input_direction(Vector2.ZERO)
	var after:=Vector2(person().x,person().y)
	check(after.x>before.x+0.2,"Held %s walks after the card closed (%s): %s -> %s"%[app.binding_label("move_right"),label,str(before),str(after)])
	check(root.gui_get_focus_owner()==null,"No control grabbed focus after closing (%s)"%label)
	await refresh()

func size_pass(size:Vector2i)->void:
	var tag:="%dx%d"%[size.x,size.y]
	path=OS.get_environment("TEMP").path_join("wangan-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	paths.append(path)
	if not await open_app(size,path):return
	check(Opening.is_new_arrival(app.session.snapshot,id),"Fresh host player is a new arrival (%s)"%tag)
	card_ok("arrival "+tag)
	check(not app.toast.visible or not str(app.toast.text).contains("歡迎！先用鋤頭"),"Card replaces the generic entry toast (%s): %s"%[tag,app.toast.text])
	var find:=Chapter.first_crop_step(app.session.snapshot,id)
	expect_tracker("第一件事・種一株蘿蔔\n去找小栗：種子攤東北邊的田\n%s 移動"%app.movement_hint(),"find "+tag)
	check(find.get("id","")=="find","Fresh step is find (%s)"%tag)
	# Dismiss by the interact key: nothing else happens.
	await key(bound("interact"))
	check(card()==null,"Interact key closes the card (%s)"%tag)
	check(app.modal==null and not str(app.toast.text).contains("靠近箱子"),"Interact key did only that (%s): %s"%[tag,app.toast.text])
	# Esc: first press closes the card, the next opens the menu as before.
	WanganUI.show_arrival(app);await settle()
	await key(KEY_ESCAPE)
	check(card()==null and app.modal==null,"Esc closes the card without opening the menu (%s)"%tag)
	await key(KEY_ESCAPE)
	check(app.modal!=null,"The next Esc opens the life menu as before (%s)"%tag)
	await key(KEY_ESCAPE)
	check(app.modal==null,"Esc closes the menu (%s)"%tag)
	# Button.
	WanganUI.show_arrival(app);await settle()
	var go:=card().find_child("ArrivalClose",true,false) as Button
	go.pressed.emit()
	await settle()
	check(card()==null and app.modal==null,"The card button closes it (%s)"%tag)
	# Enter (confirm).
	WanganUI.show_arrival(app);await settle()
	await key(KEY_ENTER)
	check(card()==null,"Enter (confirm) closes the card (%s)"%tag)
	# Hidden with the HUD under a modal, restored after.
	WanganUI.show_arrival(app);await settle()
	app._inventory();await settle()
	check(card()!=null and not card().is_visible_in_tree(),"Card hides under a panel (%s)"%tag)
	app._close_modal();await settle()
	check(card()!=null and card().is_visible_in_tree(),"Card comes back after the panel closes (%s)"%tag)
	await key(KEY_ESCAPE)
	await movement_after_close(tag)
	if size.x==1280:await overrides(tag)
	# Tracker through the real first crop.
	WanganUI.show_arrival(app);await settle()
	await stand(Vector2(45.5,28.5))
	check(card()==null,"Card closes by itself once I walked off the landing (%s)"%tag)
	expect_tracker("第一件事・種一株蘿蔔\n用鋤頭在小栗留的田翻一格土\n%s 鋤頭 · 點草地"%app.binding_label("hoe"),"till "+tag)
	await tool_click("hoe",Vector2i(45,27))
	check(w.state.crops.has("45,27"),"Click tilled (45,27) (%s)"%tag)
	expect_tracker("第一件事・種一株蘿蔔\n在翻好的土播下蘿蔔種子\n%s 播種 · %s 換種子"%[app.binding_label("seed"),app.binding_label("seeds")],"sow "+tag)
	await tool_click("seed",Vector2i(45,27))
	check(str(w.state.crops.get("45,27",{}).get("kind",""))=="radish","Click sowed radish (%s)"%tag)
	expect_tracker("第一件事・種一株蘿蔔\n替剛種下的作物澆水\n%s 澆水 · 點那一格"%app.binding_label("water"),"water "+tag)
	await tool_click("water",Vector2i(45,27))
	check(w.state.crops.get("45,27",{}).get("wet",false)==true,"Click watered (%s)"%tag)
	expect_tracker("第一件事・種一株蘿蔔\n作物正在長大，等它成熟\n成熟前可以先逛逛","wait "+tag)
	# A real reconnect mid-crop must resume the current step, not restart hoeing.
	await close_app()
	if not await open_app(size,path):return
	check(card()==null,"Growing crop does not replay arrival (%s)"%tag)
	check(str(app.toast.text)=="歡迎回來！作物正在長大，等它成熟。","Reconnect resumes actual wet-crop step (%s): %s"%[tag,app.toast.text])
	# Reconnection can offer the existing return-news modal; close it as a player
	# would before continuing the tool-input portion of this test.
	app._close_modal()
	await refresh()
	for i in 30:
		if float(w.state.crops["45,27"].growth)>=float(World.CROPS.radish.time):break
		w.step(5.0,true)
	await refresh()
	expect_tracker("第一件事・種一株蘿蔔\n作物熟了，用採收籃收成\n%s 採收 · 點成熟的作物"%app.binding_label("harvest"),"harvest "+tag)
	app._entered()
	check(str(app.toast.text)=="歡迎回來！作物熟了，用採收籃收成。","Entry hint follows mature crop (%s): %s"%[tag,app.toast.text])
	app._close_modal()
	await refresh()
	await tool_click("harvest",Vector2i(45,27))
	check(int(person().inventory.get("radish",0))>=1,"Click harvested a radish (%s)"%tag)
	expect_tracker("✓ 第一株收成了\n把蘿蔔帶到出貨箱\n靠近出貨箱按 %s"%app.binding_label("interact"),"ship "+tag)
	await stand(Vector2(42.5,32.5))
	app.session.rates[1].clear()
	app.session.perform("ship",World.SHIPPING.cell_for(w.state),JSON.stringify([[["radish",1]],int(World.CROPS.radish.price)]))
	await refresh()
	check(bool(w.state.chapter_one.shipped),"Shipment recorded (%s)"%tag)
	check(Chapter.first_crop_step(app.session.snapshot,id).is_empty(),"First-crop steps over after shipping (%s)"%tag)
	check(not str(app.objective.text).begins_with("第一件事") and not str(app.objective.text).begins_with("✓ 第一株"),"Tracker moves on to the chapter (%s): %s"%[tag,app.objective.text])
	tracker_ok("after ship "+tag)
	# Returning player: reconnect to the same save.
	await close_app()
	if not await open_app(size,path):return
	check(card()==null,"Returning player gets no arrival card (%s)"%tag)
	check(str(app.toast.text).begins_with("歡迎回來！"),"Returning player keeps 歡迎回來 (%s): %s"%[tag,app.toast.text])
	await close_app()

## Other trackers keep their priority over the first-crop hint (1280×800 pass).
func overrides(tag:String)->void:
	var base:=str(app.objective.text)
	check(base.begins_with("第一件事"),"Start from the first-crop hint (%s)"%tag)
	w.state.festival.active=true  # PRESET
	await refresh()
	check(str(app.objective.text).begins_with("風鈴接力"),"Festival overrides the first-crop hint (%s): %s"%[tag,app.objective.text])
	w.state.festival.active=false
	person().region="lanyang"  # PRESET
	await refresh()
	check(str(app.objective.text).begins_with("星禾的水圳手記"),"Another region overrides (%s): %s"%[tag,app.objective.text])
	person().region=World.REGIONS.HOME
	await refresh()
	# 豐收接力 (joined round) outranks the first-crop hint.
	w.state.board=true;w.state.picnic=true  # PRESET: the relay opens after the picnic
	await stand(Vector2(Relay.SIGN)+Vector2(0.5,1.5))
	var started:Dictionary=w.act(me,"wangan-relay","harvest_start",Relay.SIGN,str(int(Relay.round_state(w.state).round)))
	await refresh()
	check(bool(started.get("ok",false)),"PRESET: I start 豐收接力 (%s): %s"%[tag,str(started)])
	check(str(app.objective.text).begins_with("豐收接力"),"豐收接力 overrides the first-crop hint (%s): %s"%[tag,app.objective.text])
	w.act(me,"wangan-relay-leave","harvest_leave",Relay.SIGN,"")
	await refresh()
	check(str(app.objective.text).begins_with("第一件事"),"First-crop hint returns after leaving (%s): %s"%[tag,app.objective.text])
	w.state.board=false;w.state.picnic=false  # restore
	for field in ["harvest_relay"]:w.state.erase(field)
	person().erase("harvest_relay")
	await refresh()

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		await size_pass(size)
		note("size %dx%d done at %.1f s"%[size.x,size.y,(Time.get_ticks_msec()-started)/1000.0])
	finish()
