extends SceneTree
## 第 40 章金瓜石初訪「河邊淘砂金」頁 UI test (headless) at 1024×640 and 1280×800. Same harness as
## test_salt_brine_ui.gd / test_jinguashi_revisit_ui.gd: real main scene, real Session host, real
## snapshot round trips.
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true is set
##    here (the runner passes no flag for this suite);
##  * before each size: state.gold_panning ERASED, my bag's gold_ore set to 0, state.time = day 1
##    (30.0) — the whole run stays inside that one world day, so the daily count is real;
##  * the local player is teleported by writing region/x/y (no walking or travel): home, the
##    Jinguashi bank next to SITE (BANK_SPOT) and a Jinguashi spot out of reach (FAR_SPOT);
##  * session rate buckets / action_clock are cleared before each of my own actions.
## REALLY EXERCISED (local player):
##  * main._interact() (the normal interaction entry, called directly) on the bank opens the page;
##    world_view.interaction_focus() names the 淘砂處 point there;
##  * every GpAction press is a `pressed` signal emission on the real Button -> GoldPanUI ->
##    Session.perform(gold_pan, SITE, next step) -> World -> snapshot -> in-place refresh; every
##    stage / count / total / bag change after the reset is the server's (three whole pans, one
##    of them interrupted at stage 3, closed and reopened);
##  * the server replies in the page footer (modal_feedback).
## NO real mouse, keyboard or gamepad input drives the page (only the template's harness step of
## one KEY_E push to dismiss a possible Wangan arrival card before the flows start).
## NOT COVERED HERE: the world sprite / focus label pixels of the site (art suite); a second
## connected client; gamepad / arrow-key focus travel; the non-preview layout; day rollover.
const World=preload("res://scripts/world.gd")
const Gold=preload("res://scripts/gold_panning.gd")
const UI=preload("res://scripts/gold_panning_ui.gd")
const GoldPanArt=preload("res://scripts/gold_panning_art.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
## On the bank (land starts at x=6), 1.0 tile east of SITE's centre (reach 3.2).
const BANK_SPOT:=Vector2(6.5,26.5)
## Jinguashi land about 7.1 tiles from SITE, away from every other interaction point.
const FAR_SPOT:=Vector2(12.5,27.5)
## Home spot (walkable, used by test_jinguashi_revisit_ui as BUILD_SPOT).
const HOME_SPOT:=Vector2(42.5,34.5)
## Hand-written expected step chips: CHIPS[stage] in Gold.STEP_IDS order (scoop, sift, swirl, pick).
const CHIPS:=[
	["▶ 舀砂","○ 揀石礫","○ 搖盤","○ 揀金砂"],
	["✓ 舀砂","▶ 揀石礫","○ 搖盤","○ 揀金砂"],
	["✓ 舀砂","✓ 揀石礫","▶ 搖盤 1／3","○ 揀金砂"],
	["✓ 舀砂","✓ 揀石礫","▶ 搖盤 2／3","○ 揀金砂"],
	["✓ 舀砂","✓ 揀石礫","▶ 搖盤 3／3","○ 揀金砂"],
	["✓ 舀砂","✓ 揀石礫","✓ 搖盤","▶ 揀金砂"],
]
## Hand-written expected button captions per stage.
const CAPTION_TABLE:=["舀一盤河砂","揀掉石礫","搖盤（還要 3 次）","搖盤（還要 2 次）","搖盤（還要 1 次）","揀起金砂"]
const AWAY_LITERAL:="請站到山城西側水邊的淘砂處旁（5,26）再淘砂。"
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
	print("GOLD_PANNING_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE GOLD_PANNING_UI "+message)

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

func snap()->Dictionary:
	return app.session.snapshot

func person()->Dictionary:
	return w.state.players[id]

func bag()->Dictionary:
	return person().inventory

func ore()->int:
	return int(bag().get(Gold.ITEM,0))

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func focused_name()->String:
	var owner:=root.gui_get_focus_owner()
	return str(owner.name) if owner!=null else "none"

func server_stage()->int:
	return Gold.stage(w.state,id)

func server_count()->int:
	return Gold.count_today(w.state,id)

func server_total()->int:
	return Gold.total(w.state,id)

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

## The normal interaction entry (main._interact), no key event.
func interact()->void:
	app.session.rates[1].clear()
	app._interact()
	await settle()
	await refresh()

## Press GpAction through its `pressed` signal (no mouse / key event).
func press_action(label:String)->bool:
	var b:=button("GpAction")
	check(b!=null and not b.disabled and b.is_visible_in_tree(),"GpAction enabled before pressing (%s)"%label)
	if b==null or b.disabled:return false
	app.action_clock=0
	app.session.rates[1].clear()
	b.pressed.emit()
	await settle()
	await refresh()
	return true

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

# ------------------------------------------------------------------- layout --

## Page inside the viewport, no outer scrolling, every visible label / button / picture inside
## the page and whole, no ellipsis.
func layout_ok(label:String)->void:
	if not page_open():
		check(false,"Page %s open for layout: %s (got %s)"%[UI.LAYOUT,label,layout_name()])
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
	check(label_text("GpDisclaimer")==Gold.DISCLAIMER and shown("GpDisclaimer"),"Fiction disclaimer shown (%s)"%label)
	check(label_text("GpBlurb")==Gold.BLURB and shown("GpBlurb"),"Blurb shown (%s)"%label)
	for name in ["GpHeader","GpCount","GpPanCard","GpPan","GpStage","GpSteps","GpAction","GpBag"]:
		check(shown(name),"%s shown (%s)"%[name,label])

func focus_on_action(label:String)->void:
	check(focused_name()=="GpAction" and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(root.gui_get_focus_owner()),"Keyboard focus on GpAction (%s): %s"%[label,focused_name()])

## Everything on the page that follows the pan record, against the helpers and hand tables.
func pan_is(stage:int,count:int,total:int,label:String)->void:
	check(server_stage()==stage and server_count()==count and server_total()==total,"Server record stage %d count %d total %d (%s): %d %d %d"%[stage,count,total,label,server_stage(),server_count(),server_total()])
	var own:Dictionary=snap().get(Gold.OWN_KEY,{})
	check(int(own.get("stage",-1))==stage and int(own.get("count",-1))==count and int(own.get("total",-1))==total,"Snapshot own_gold_panning (%s): %s"%[label,str(own)])
	check(label_text("GpStage")==Gold.stage_text(stage) and shown("GpStage"),"Stage text %d (%s): %s"%[stage,label,label_text("GpStage")])
	var pic:=control("GpPan") as TextureRect
	check(pic!=null and pic.texture==GoldPanArt.pan_texture(stage),"Pan picture is stage %d's (%s)"%[stage,label])
	for i in Gold.STEP_IDS.size():
		var step:String=Gold.STEP_IDS[i]
		var chip:String=UI.chip_text(stage,step)
		var want:String=CHIPS[stage][i]
		check(label_text("GpStep_"+step)==want and chip==want,"Chip %s at stage %d 「%s」 (%s): %s"%[step,stage,want,label,label_text("GpStep_"+step)])
	var b:=button("GpAction")
	var caption:String=UI.action_caption(stage)
	check(b!=null and b.text==CAPTION_TABLE[stage] and caption==CAPTION_TABLE[stage],"GpAction caption 「%s」 (%s): %s"%[CAPTION_TABLE[stage],label,b.text if b!=null else "none"])
	var count_line:String=UI.count_text(snap())
	check(label_text("GpCount")=="今天 %d／3 盤・累計 %d 盤"%[count,total] and label_text("GpCount")==count_line,"Count line (%s): %s"%[label,label_text("GpCount")])
	check(label_text("GpBag")=="背包：含金礦料 %d"%ore(),"Bag line (%s): %s"%[label,label_text("GpBag")])

## Enabled: no reason line, tooltip is the blurb. Disabled: reason line, tooltip, still focusable.
func action_state(enabled:bool,reason:String,label:String)->void:
	var b:=button("GpAction")
	check(b!=null and b.is_visible_in_tree() and b.disabled==not enabled,"GpAction %s (%s)"%["enabled" if enabled else "disabled",label])
	if b==null:return
	if enabled:
		check(b.tooltip_text==Gold.BLURB,"Enabled tooltip is the blurb (%s): %s"%[label,b.tooltip_text])
		check(not shown("GpReason"),"No reason line while enabled (%s): %s"%[label,label_text("GpReason")])
	else:
		check(b.tooltip_text==reason,"GpAction tooltip 「%s」 (%s): %s"%[reason,label,b.tooltip_text])
		check(b.focus_mode==Control.FOCUS_ALL,"GpAction stays focusable while disabled (%s)"%label)
		check(shown("GpReason") and label_text("GpReason")==reason,"Reason line 「%s」 (%s): %s"%[reason,label,label_text("GpReason")])
	var me:Dictionary=UI.person_of(snap(),str(app.session.own_id))
	var expected:String=UI.action_reason(snap(),me)
	check(expected==reason,"action_reason on the live snapshot 「%s」 (%s): %s"%[reason,label,expected])

## One press; checks the server's reply and the in-place update.
func step_once(label:String)->void:
	var stage:=server_stage()
	var count:=server_count()
	var total:=server_total()
	var ore_before:=ore()
	var modal_before:Node=app.modal
	var card_before:=control("GpPanCard")
	var expected_msg:=""
	match stage:
		0:expected_msg=Gold.SCOOP_OK
		1:expected_msg=Gold.SIFT_OK
		2,3:expected_msg=Gold.SWIRL_OK%Gold.swirls_left(stage+1)
		4:expected_msg=Gold.SWIRL_LAST
		5:expected_msg=Gold.PICK_OK%(count+1)
	var tag:="%s, press at stage %d"%[label,stage]
	if not await press_action(tag):return
	check(page_open() and app.modal==modal_before and control("GpPanCard")==card_before,"Page stays open and is updated in place (%s)"%tag)
	check(feedback()==expected_msg,"Server reply in the footer 「%s」 (%s): %s"%[expected_msg,tag,feedback()])
	if stage==5:
		pan_is(0,count+1,total+1,tag)
		check(ore()==ore_before+1,"Pick adds one %s (%s): %d -> %d"%[Gold.ITEM_NAME,tag,ore_before,ore()])
	else:
		pan_is(stage+1,count,total,tag)
		check(ore()==ore_before,"Bag unchanged before the pick (%s)"%tag)
	focus_on_action(tag)

# --------------------------------------------------------------------- flows --

func reset()->void:
	await close_page()
	w.state.erase(Gold.STATE_KEY)  # PRESET
	bag()[Gold.ITEM]=0  # PRESET
	w.state.time=30.0  # PRESET (day 1)
	await refresh()

func open_on_bank(label:String)->void:
	await close_page()
	await stand(BANK_SPOT,Gold.REGION)
	check(str(app.view.interaction_focus())==UI.POINT,"淘砂處 is the focused point on the bank (%s): %s"%[label,str(app.view.interaction_focus())])
	await interact()
	check(page_open(),"Interaction on the bank opens the page (%s): %s"%[label,layout_name()])

func away_from_jinguashi_flow(label:String)->void:
	await close_page()
	await stand(HOME_SPOT,World.REGIONS.HOME)
	check(not snap().has(Gold.OWN_KEY),"No own_gold_panning outside Jinguashi (%s)"%label)
	check(not snap().has(Gold.STATE_KEY),"Public snapshot never carries state.gold_panning (%s)"%label)
	UI.open(app)
	await settle()
	check(not UI.is_open(app) and not page_open(),"open() does nothing outside Jinguashi (%s): %s"%[label,layout_name()])
	await close_page()

func open_flow(label:String)->void:
	await open_on_bank("open "+label)
	if not page_open():return
	check(UI.is_open(app),"is_open (%s)"%label)
	check(str((app.modal as Node).name)=="GoldPanningPanel","Modal node name (%s): %s"%[label,str((app.modal as Node).name)])
	check((app.modal as Node).has_meta("gp_body"),"gp_body meta (%s)"%label)
	check(texts().contains(UI.PAGE_TITLE) and UI.PAGE_TITLE==Gold.TITLE,"Page title 「%s」 shown (%s)"%[Gold.TITLE,label])
	check(snap().has(Gold.OWN_KEY) and not snap().has(Gold.STATE_KEY),"Own record only in the Jinguashi snapshot (%s)"%label)
	check(feedback()==UI.KEY_HINT,"Key hint in the footer (%s): %s"%[label,feedback()])
	focus_on_action("open "+label)
	var preferred:Control=UI.preferred(app)
	check(preferred!=null and preferred==button("GpAction"),"preferred() is GpAction (%s)"%label)
	var close:BaseButton=UI.close_button(app)
	check(close!=null and close.is_visible_in_tree() and not (app.modal.get_meta("gp_body") as Node).is_ancestor_of(close),"close_button() outside the body (%s)"%label)
	pan_is(0,0,0,"fresh "+label)
	action_state(true,"","fresh "+label)
	layout_ok("fresh "+label)

func first_pan_flow(label:String)->void:
	if not page_open():return
	for i in range(6):
		await step_once("pan 1 "+label)
		action_state(true,"","after press %d pan 1 %s"%[i+1,label])
		if i==1 or i==3 or i==5:layout_ok("pan 1 press %d %s"%[i+1,label])
	check(ore()==1,"One 含金礦料 after the first pan (%s): %d"%[label,ore()])

func far_flow(label:String)->void:
	if not page_open():return
	var modal_before:Node=app.modal
	await stand(FAR_SPOT,Gold.REGION)
	check(page_open() and app.modal==modal_before,"Page stays open while moving away (%s)"%label)
	var me:Dictionary=UI.person_of(snap(),str(app.session.own_id))
	check(not UI.near(snap(),me),"near() false at FAR_SPOT (%s)"%label)
	action_state(false,UI.away_text(),"too far "+label)
	focus_on_action("too far "+label)
	layout_ok("too far "+label)
	await stand(BANK_SPOT,Gold.REGION)
	check(page_open() and app.modal==modal_before,"Same page after walking back (%s)"%label)
	action_state(true,"","back near "+label)
	pan_is(0,1,1,"back near "+label)

func partial_flow(label:String)->void:
	if not page_open():return
	for i in range(3):await step_once("pan 2 "+label)
	pan_is(3,1,1,"left at stage 3 "+label)
	await close_page()
	check(not is_instance_valid(app.modal) and not UI.is_open(app),"Page closed (%s)"%label)
	await open_on_bank("reopen "+label)
	if not page_open():return
	pan_is(3,1,1,"reopened at stage 3 "+label)
	action_state(true,"","reopened "+label)
	focus_on_action("reopened "+label)
	check(feedback()==UI.KEY_HINT,"Key hint again on reopening (%s): %s"%[label,feedback()])
	layout_ok("reopened stage 3 "+label)
	for i in range(3):await step_once("pan 2 finish "+label)
	pan_is(0,2,2,"second pan done "+label)
	check(ore()==2,"Two 含金礦料 after the second pan (%s): %d"%[label,ore()])

func daily_flow(label:String)->void:
	if not page_open():return
	for i in range(6):await step_once("pan 3 "+label)
	pan_is(0,3,3,"daily limit "+label)
	check(ore()==3,"Three 含金礦料 after three pans (%s): %d"%[label,ore()])
	check(feedback()==Gold.PICK_OK%3,"Third pick reply (%s): %s"%[label,feedback()])
	action_state(false,Gold.DAILY_DONE,"daily limit "+label)
	focus_on_action("daily limit "+label)
	layout_ok("daily limit "+label)
	# The rule's reason wins over the position.
	var modal_before:Node=app.modal
	await stand(FAR_SPOT,Gold.REGION)
	check(app.modal==modal_before,"Same page far away at the limit (%s)"%label)
	action_state(false,Gold.DAILY_DONE,"daily limit far "+label)
	await stand(BANK_SPOT,Gold.REGION)
	await close_page()

func size_flow(label:String)->void:
	await reset()
	await away_from_jinguashi_flow(label)
	await open_flow(label)
	await first_pan_flow(label)
	await far_flow(label)
	await partial_flow(label)
	await daily_flow(label)

# ---------------------------------------------------------------- pure checks --

func fake(stage:int,count:int,total:int)->Dictionary:
	return {"time":30.0,"region_id":Gold.REGION,Gold.OWN_KEY:{"stage":stage,"count":count,"total":total}}

func pure_checks()->void:
	check(UI.LAYOUT=="gold_panning" and UI.POINT=="gold_pan" and UI.PAGE_TITLE==Gold.TITLE,"Contract constants")
	for stage in range(6):
		var caption:String=UI.action_caption(stage)
		check(caption==CAPTION_TABLE[stage],"action_caption(%d) 「%s」: %s"%[stage,CAPTION_TABLE[stage],caption])
		for i in Gold.STEP_IDS.size():
			var chip:String=UI.chip_text(stage,Gold.STEP_IDS[i])
			check(chip==CHIPS[stage][i],"chip_text(%d,%s) 「%s」: %s"%[stage,Gold.STEP_IDS[i],CHIPS[stage][i],chip])
	var counted:String=UI.count_text(fake(2,1,7))
	check(counted=="今天 1／3 盤・累計 7 盤","count_text: %s"%counted)
	var empty_count:String=UI.count_text({"region_id":Gold.REGION})
	check(empty_count=="今天 0／3 盤・累計 0 盤","count_text without a record: %s"%empty_count)
	var away:String=UI.away_text()
	check(away==AWAY_LITERAL and away==UI.AWAY%[Gold.SITE.x,Gold.SITE.y],"away_text: %s"%away)
	check(UI.region_of({"region_id":"jinguashi"})=="jinguashi","region_of")
	var me:Dictionary={"x":BANK_SPOT.x,"y":BANK_SPOT.y,"inventory":{}}
	var far:Dictionary={"x":FAR_SPOT.x,"y":FAR_SPOT.y,"inventory":{}}
	var people:Dictionary={"players":{"me":me}}
	check(UI.person_of(people,"me")==me,"person_of finds the own player")
	var s0:Dictionary=fake(0,0,0)
	check(UI.near(s0,me) and not UI.near(s0,far),"near on the bank, not at FAR_SPOT")
	var edge:Dictionary={"x":Gold.SITE.x+0.5+Gold.REACH-0.05,"y":Gold.SITE.y+0.5,"inventory":{}}
	var beyond:Dictionary={"x":Gold.SITE.x+0.5+Gold.REACH+0.05,"y":Gold.SITE.y+0.5,"inventory":{}}
	check(UI.near(s0,edge) and not UI.near(s0,beyond),"near follows Gold.REACH")
	check(not UI.near({"region_id":"home"},me),"Not near outside Jinguashi")
	var reason:String=UI.action_reason(s0,far)
	check(reason==away,"Far away: away_text: %s"%reason)
	for stage in range(6):
		reason=UI.action_reason(fake(stage,0,0),me)
		check(reason.is_empty(),"Near at stage %d: no reason: %s"%[stage,reason])
		reason=UI.action_reason(fake(stage,0,0),far)
		check(reason==away,"Far at stage %d: away_text: %s"%[stage,reason])
	reason=UI.action_reason(fake(0,3,3),me)
	check(reason==Gold.DAILY_DONE,"Daily limit near: DAILY_DONE: %s"%reason)
	reason=UI.action_reason(fake(0,3,3),far)
	check(reason==Gold.DAILY_DONE,"Daily limit far: rules first: %s"%reason)
	reason=UI.action_reason(fake(3,3,5),me)
	check(reason.is_empty(),"A started pan can be finished at the limit: %s"%reason)
	var full:Dictionary={"x":BANK_SPOT.x,"y":BANK_SPOT.y,"inventory":{Gold.ITEM:Gold.LIMIT}}
	reason=UI.action_reason(fake(5,0,0),full)
	check(reason==Gold.BAG_FULL,"Bag full at stage 5: BAG_FULL: %s"%reason)
	reason=UI.action_reason(fake(4,0,0),full)
	check(reason.is_empty(),"Bag full does not block a swirl: %s"%reason)
	# Art: one distinct 64×64 picture per stage, cached.
	var all_ok:=true
	for a in range(6):
		var tex:Texture2D=GoldPanArt.pan_texture(a)
		all_ok=all_ok and tex!=null and tex.get_width()==64 and tex.get_height()==64 and tex==GoldPanArt.pan_texture(a)
		for b in range(a+1,6):
			all_ok=all_ok and GoldPanArt.pan_image(a).get_data()!=GoldPanArt.pan_image(b).get_data()
	check(all_ok,"Six distinct cached 64×64 pan pictures")

# ------------------------------------------------------------------------ run --

func run()->void:
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	var started:=Time.get_ticks_msec()
	pure_checks()
	path=OS.get_environment("TEMP").path_join("gold-panning-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"淘砂旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	if not app.playing:note("app.playing was false after host; set true");app.playing=true
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
