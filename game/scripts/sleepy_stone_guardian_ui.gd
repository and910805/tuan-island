extends RefCounted
## 打瞌睡石像 menu, hum playback and interact points. Static module in the style of
## mine_survey_ui.gd; `main` is the main.gd node. Depends only on the pure Guardian rules
## and the bell audio module, so the helpers load without World/Session.
##
## The hum order is never computed here: it only ever comes from the host's private
## `guardian_listen` result. Nothing here stores or shows a player id or token.
##
## State lives in main.set_meta(META, {...}). The last-heard notes and echo progress are kept
## while the player stays in mine_4 (so walking between bells needs no memory); everything
## is dropped on leaving the region, and playback stops when the panel closes.

const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
const Bell=preload("res://scripts/sleepy_stone_guardian_audio.gd")
const Trial=preload("res://scripts/stone_guardian_trial.gd")

const META:="sleepy_guardian_ui"
## Optional test clock (seconds) on main; real play uses Time.get_ticks_msec().
const CLOCK_META:="sleepy_guardian_clock"
const BODY_META:="guardian_body"
const LAYOUT:="sleepy_guardian"
const POINT:="mine_guardian"
const BELL_POINT:="mine_guardian_bell_"
const STEP_ON:=0.6
const STEP_GAP:=0.2
const FLASH:=0.6
## The panel closes when the player ends up farther than this from every guardian cell.
const LEAVE_DISTANCE:=4.5
const INK:=Color("3b2f2a")
const NEAR_HINT:="（走近一點）"
const Art=preload("res://scripts/sleepy_stone_guardian_art.gd")

## Small cave portrait: the statue (original atlas, 3x) beside the three bell stands (1x).
## Pure decoration; every fact it shows is also in the labels and buttons.
class Scene extends Control:
	const SIZE_PX:=Vector2(204,124)
	var frame:=0
	var lit:=-1
	var reduced:=false
	func _init() -> void:
		name="GuardianScene"
		custom_minimum_size=SIZE_PX
		size_flags_vertical=Control.SIZE_SHRINK_CENTER
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		clip_contents=true
		if "accessibility_name" in self:set("accessibility_name","石像與三個風鈴")
	func show_state(new_frame:int,new_lit:int,new_reduced:bool) -> void:
		if frame==new_frame and lit==new_lit and reduced==new_reduced:return
		frame=new_frame
		lit=new_lit
		reduced=new_reduced
		queue_redraw()
	func _draw() -> void:
		var back:=StyleBoxFlat.new()
		back.bg_color=Color("4a4038")
		back.border_color=Color("2b2028")
		back.set_border_width_all(2)
		back.set_corner_radius_all(8)
		draw_style_box(back,Rect2(Vector2.ZERO,size))
		var floor_rect:=Rect2(2,size.y-30,size.x-4,28)
		draw_rect(floor_rect,Color("6b5a47"))
		draw_rect(Rect2(floor_rect.position,Vector2(floor_rect.size.x,2)),Color("86745c"))
		draw_set_transform(Vector2(8,size.y-124+2),0.0,Vector2(3,3))
		Art.draw_guardian(self,Vector2(Guardian.FOOT),frame,0.0,reduced)
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
		for i in Guardian.BELLS.size():
			Art.draw_bell(self,Vector2(124+i*30,size.y-6),i,i==lit,0.0,reduced)

# ---------------------------------------------------------------------------
# Pure helpers (unit-tested in tests/test_sleepy_stone_guardian_ui_logic.gd)
# ---------------------------------------------------------------------------

## Which note is lit `elapsed` seconds into a hum: STEP_ON lit, STEP_GAP dark, repeat.
## -1 before the start, in gaps, after the end, and always with reduced motion.
static func playback_step(notes_count:int,elapsed:float,reduced_motion:bool=false) -> int:
	if reduced_motion or notes_count<=0 or not is_finite(elapsed) or elapsed<0.0:return -1
	var slot:=STEP_ON+STEP_GAP
	var index:=int(floor(elapsed/slot))
	if index>=notes_count:return -1
	return index if elapsed-index*slot<STEP_ON else -1

static func playback_duration(notes_count:int) -> float:
	return 0.0 if notes_count<=0 else notes_count*(STEP_ON+STEP_GAP)-STEP_GAP

static func note_bell(note) -> int:
	var bell:=-1
	if note is Dictionary and (note.get("bell") is int or note.get("bell") is float):bell=int(note.bell)
	elif note is int or note is float:bell=int(note)
	return bell if bell>=0 and bell<Guardian.BELLS.size() else -1

static func bell_text(bell:int,spaced:bool=true) -> String:
	if bell<0 or bell>=Guardian.BELLS.size():return ""
	return Guardian.SHAPES[bell]+(" " if spaced else "")+Guardian.BELL_NAMES[bell]

## Text-only equivalent of the hum: "● 低音鈴 → 【▲ 中音鈴】 → ■ 高音鈴".
static func sequence_text(notes:Array,lit_index:int) -> String:
	var parts:PackedStringArray=[]
	for i in notes.size():
		var word:=bell_text(note_bell(notes[i]))
		if word.is_empty():continue
		parts.append("【"+word+"】" if i==lit_index else word)
	return " → ".join(parts)

## Static, numbered form used with reduced motion: "1 ● 低音鈴　2 ▲ 中音鈴".
static func numbered_text(notes:Array) -> String:
	var parts:PackedStringArray=[]
	for i in notes.size():
		var word:=bell_text(note_bell(notes[i]))
		if not word.is_empty():parts.append("%d %s"%[i+1,word])
	return "　".join(parts)

static func bell_of(id:String) -> int:
	if not id.begins_with(BELL_POINT):return -1
	var tail:=id.trim_prefix(BELL_POINT)
	if not tail.is_valid_int():return -1
	var bell:=int(tail)
	return bell if bell>=0 and bell<Guardian.BELLS.size() else -1

## Interact point id -> cell centre. Exactly the statue and the three bells, only on an open B4.
static func points(state:Dictionary,_player:Dictionary,region:String,unlocked:int) -> Dictionary:
	if not Guardian.available(region,unlocked) or trial_active(state):return {}
	var out:Dictionary={POINT:Vector2(Guardian.GUARDIAN)+Vector2(0.5,0.5)}
	for i in Guardian.BELLS.size():out[BELL_POINT+str(i)]=Vector2(Guardian.BELLS[i])+Vector2(0.5,0.5)
	return out

static func trial_active(snapshot:Dictionary)->bool:
	var phase:=int(snapshot.get(Trial.KEY,{}).get("phase",-1))
	return phase in [Trial.Phase.WARNING,Trial.Phase.IMPACT]

static func observe_trial(main,snapshot:Dictionary)->void:
	if not main.playing or not snapshot.has(Trial.KEY):return
	var state:Dictionary=snapshot[Trial.KEY]
	var old:Dictionary=main.view.data.get(Trial.KEY,{})
	var phase:=int(state.get("phase",-1))
	if phase==int(old.get("phase",-1)) and state.get("strike_at")==old.get("strike_at"):return
	match phase:
		Trial.Phase.WARNING:
			main.sound.cancel_pending_action()
			main.sound.play_cue("guardian_raise",true)
			if main.sound.activity_captions:main._caption("石像舉掌，退到標記外。",2)
		Trial.Phase.IMPACT:main.sound.play_cue("guardian_drop",true)
		Trial.Phase.MISSED:
			main._notice("落掌時還在標記內，靠近石像可以再試。",false)
			main.sound.play_cue("guardian_drop",true)

## Short in-world label per point id.
static func label(id:String,record:Dictionary) -> String:
	var bell:=bell_of(id)
	if bell>=0:return bell_text(bell,false)
	if id!=POINT:return ""
	if not Guardian.awake(record):return Guardian.NAME
	return "醒著的石像" if bool(record.get("claimed",false)) else "石像 · 有謝禮"

## Normalised copy of a (possibly JSON-floated, possibly absent) player record.
static func clean_record(raw) -> Dictionary:
	var out:=Guardian.fresh()
	if not raw is Dictionary:return out
	for key in ["round","calm"]:
		var value=raw.get(key)
		if (value is int or value is float) and is_finite(value):out[key]=int(value)
	out.round=clampi(int(out.round),0,Guardian.ROUNDS)
	out.calm=clampi(int(out.calm),0,Guardian.CALM_NEEDED)
	out.claimed=_yes(raw.get("claimed"))
	return out

static func record_of(snapshot:Dictionary,own_id:String) -> Dictionary:
	var people=snapshot.get("players",{})
	if not people is Dictionary:return Guardian.fresh()
	var person=people.get(own_id,{})
	return clean_record(person.get("sleepy_guardian") if person is Dictionary else null)

static func phrase_length(record:Dictionary) -> int:
	return int(record.get("round",0))+2

static func progress_text(record:Dictionary,entered:int) -> String:
	if Guardian.awake(record):return ""
	return "已接上 %d／%d　·　陪伴 %d／%d"%[clampi(entered,0,phrase_length(record)),phrase_length(record),int(record.get("calm",0)),Guardian.CALM_NEEDED]

static func status_text(record:Dictionary) -> String:
	if Guardian.awake(record):
		if bool(record.get("claimed",false)):return "石像醒著，安心地看著你。謝禮已經收下了。"
		return "石像醒了，眨著琥珀色的眼睛，讓出身後的凹槽。謝禮想拿再拿，不拿也沒關係。"
	if int(record.get("round",0))>=1:return "牠的呼嚕聲變小了，想再哼一段長一點的。牠哼什麼，就照順序敲什麼鈴。"
	return "石像在凹槽裡打瞌睡，哼著一段哼不完的調子。牠哼什麼，就照順序敲什麼鈴。不用急，也沒有時間限制。"

## Ordered option descriptors [{id,label,action,cell,focus}]. `near_bell` is the bell whose
## interact point opened the menu (-1 for the statue); it only marks the default focus.
static func menu_options(record:Dictionary,near_bell:int) -> Array:
	var out:Array=[]
	if not Guardian.awake(record):
		out.append({"id":"listen","label":"聽石像哼","action":"guardian_listen","cell":Guardian.GUARDIAN,"focus":near_bell<0 or near_bell>=Guardian.BELLS.size()})
		for i in Guardian.BELLS.size():
			out.append({"id":"ring_%d"%i,"label":"敲 "+bell_text(i,false),"action":"guardian_ring","cell":Guardian.BELLS[i],"focus":i==near_bell})
		out.append({"id":"sit","label":"靜靜陪牠","action":"guardian_sit","cell":Guardian.GUARDIAN,"focus":false})
	elif not bool(record.get("claimed",false)):
		out.append({"id":"claim","label":"收下謝禮","action":"guardian_claim","cell":Guardian.GUARDIAN,"focus":true})
	out.append({"id":"leave","label":"離開","action":"","cell":Guardian.GUARDIAN,"focus":out.is_empty()})
	return out

## Mirrors the host's per-target range check; the leave option is always usable.
static func option_enabled(option:Dictionary,pos:Vector2) -> bool:
	return str(option.get("action",""))=="" or Guardian.near(pos,option.cell)

static func _yes(value) -> bool:
	return value is bool and value

static func button_name(id:String) -> String:
	return "Guardian"+id.capitalize().replace(" ","")

static func nearest_distance(pos:Vector2) -> float:
	var best:=pos.distance_to(Vector2(Guardian.GUARDIAN)+Vector2(0.5,0.5))
	for cell:Vector2i in Guardian.BELLS:best=minf(best,pos.distance_to(Vector2(cell)+Vector2(0.5,0.5)))
	return best

# ---------------------------------------------------------------------------
# State on main
# ---------------------------------------------------------------------------

static func _state(main) -> Dictionary:
	if not main.has_meta(META):
		main.set_meta(META,{"notes":[],"play_start":-1.0,"played":-1,"rung":-1,"rung_at":-1000.0,
			"message":"","entered":0,"focus":-1,"round":-1,"fingerprint":"","options":""})
	return main.get_meta(META)

static func _now(main) -> float:
	return float(main.get_meta(CLOCK_META)) if main.has_meta(CLOCK_META) else Time.get_ticks_msec()/1000.0

static func _reduced(main) -> bool:
	var sound=main.get("sound")
	return is_instance_valid(sound) and _yes(sound.get("reduced_motion"))

static func _available(snapshot:Dictionary) -> bool:
	var depths=snapshot.get("mine_depths",{})
	return Guardian.available(str(snapshot.get("region_id","home")),int(depths.get("unlocked",1)) if depths is Dictionary else 1)

static func is_open(main) -> bool:
	if not is_instance_valid(main):return false
	var modal=main.get("modal")
	return is_instance_valid(modal) and not modal.is_queued_for_deletion() and modal.has_meta(BODY_META)

static func _own_position(main) -> Vector2:
	var people=main.session.snapshot.get("players",{})
	var person=people.get(main.session.own_id,{}) if people is Dictionary else {}
	if not person is Dictionary or not person.has("x") or not person.has("y"):return Vector2.INF
	return Vector2(float(person.x),float(person.y))

static func _lit_index(main,state:Dictionary) -> int:
	if float(state.play_start)<0.0:return -1
	return playback_step(state.notes.size(),_now(main)-float(state.play_start),_reduced(main))

## -1, or the bell to light in the world: the note being hummed, or a bell that was just rung.
static func lit_bell(main) -> int:
	if not is_instance_valid(main) or not main.has_meta(META):return -1
	var state:Dictionary=main.get_meta(META)
	var since:=_now(main)-float(state.rung_at)
	if int(state.rung)>=0 and since>=0.0 and since<FLASH:return int(state.rung)
	if not is_open(main):return -1
	var index:=_lit_index(main,state)
	return note_bell(state.notes[index]) if index>=0 else -1

# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

## Opens the menu. `focus` is the interact point id ("mine_guardian" / "mine_guardian_bell_N").
static func open(main,focus:String="") -> void:
	var snapshot:Dictionary=main.session.snapshot
	if not _available(snapshot):return
	if focus==POINT and snapshot.get(Trial.KEY,{}).get("phase",-1)==Trial.Phase.SAFE:
		main.session.perform(Trial.KEY,Guardian.GUARDIAN,Trial.FINISH)
		return
	var state:=_state(main)
	state.focus=bell_of(focus)
	state.fingerprint=""
	state.options=""
	state.play_start=-1.0
	var body:VBoxContainer=main._open_modal(Guardian.NAME)
	main.modal.set_meta("life_modal_layout",LAYOUT)
	main.modal.set_meta(BODY_META,body)
	body.add_theme_constant_override("separation",8)
	# Header: the cave scene as a small portrait, with a short status and progress beside it.
	var header:=HBoxContainer.new()
	header.name="GuardianHeader"
	header.add_theme_constant_override("separation",14)
	body.add_child(header)
	var scene:=Scene.new()
	header.add_child(scene)
	var info:=VBoxContainer.new()
	info.name="GuardianInfo"
	info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	info.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation",6)
	header.add_child(info)
	var status:Label=main.label("",16)
	status.name="GuardianStatus"
	info.add_child(status)
	var progress:Label=main.label("",19)
	progress.name="GuardianProgress"
	info.add_child(progress)
	# The numbered note chips are the focus. They are the on-screen hum, also with reduced motion.
	var chips:=HFlowContainer.new()
	chips.name="GuardianSequence"
	chips.alignment=FlowContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("h_separation",10)
	chips.add_theme_constant_override("v_separation",8)
	body.add_child(chips)
	# Exact full-sequence text: shown while there are no chips, otherwise kept for accessibility.
	for id in ["GuardianSequenceText","GuardianMessage"]:
		var line:Label=main.label("",15 if id=="GuardianMessage" else 16)
		line.name=id
		body.add_child(line)
	var options:=VBoxContainer.new()
	options.name="GuardianOptions"
	options.add_theme_constant_override("separation",6)
	body.add_child(options)
	var hint:Label=main.label("走近風鈴再敲。離開畫面會保留音序。",13)
	hint.name="GuardianReachHint"
	body.add_child(hint)
	# Content height follows the panel, so re-fit when the body's needs change.
	if main.has_method("_layout_preview"):body.minimum_size_changed.connect(main._layout_preview.call_deferred)
	var feedback=main.get("modal_feedback")
	if is_instance_valid(feedback):feedback.text="想聽幾次都可以，沒有時間限制。"
	# Self-driven upkeep while the panel is open, so playback never depends on snapshot rate.
	var tree:SceneTree=main.get_tree() if main.is_inside_tree() else null
	var tick:=func():refresh(main)
	if tree!=null:tree.process_frame.connect(tick)
	body.tree_exiting.connect(func():
		if tree!=null and tree.process_frame.is_connected(tick):tree.process_frame.disconnect(tick)
		_closed(main))
	refresh(main)
	if _yes(main.get("controller_navigation")):_focus_default.call_deferred(main)
	if main.has_method("_layout_preview"):main._layout_preview.call_deferred()

static func _closed(main) -> void:
	if not is_instance_valid(main) or not main.has_meta(META) or is_open(main):return
	var state:Dictionary=main.get_meta(META)
	state.play_start=-1.0
	state.played=-1
	state.fingerprint=""
	state.options=""

static func _focus_default(main) -> void:
	if not is_open(main):return
	var body:VBoxContainer=main.modal.get_meta(BODY_META)
	var wanted:Button=null
	for child in body.find_children("Guardian*","Button",true,false):
		var button:=child as Button
		if button.disabled:continue
		if button.get_meta("guardian_focus",false):
			wanted=button
			break
		if wanted==null:wanted=button
	if wanted!=null:wanted.grab_focus()

## Called where the acting client's action result arrives (session.action_completed).
static func handle_result(main,action:String,result:Dictionary) -> void:
	if action not in Guardian.ACTIONS or not is_instance_valid(main):return
	var state:=_state(main)
	var raw=result.get("guardian")
	var info:Dictionary=raw if raw is Dictionary else {}
	var outcome:=str(info.get("outcome",""))
	var ok:=_yes(result.get("ok"))
	state.message=str(result.get("message",""))
	if info.get("round") is int or info.get("round") is float:
		var stage:=clampi(int(info.round),0,Guardian.ROUNDS)
		if stage!=int(state.round):
			state.round=stage
			state.notes=[]
			state.play_start=-1.0
	if info.get("entered") is int or info.get("entered") is float:state.entered=maxi(0,int(info.entered))
	if outcome in ["wrong","round","awake"]:state.entered=0
	if outcome=="listen" and ok and info.get("notes") is Array:
		var notes:Array=[]
		for note in info.notes:
			var bell:=note_bell(note)
			if bell>=0:notes.append({"bell":bell})
		state.notes=notes
		state.played=-1
		# Free replay: every listen restarts the hum from its first note.
		state.play_start=_now(main) if is_open(main) and not notes.is_empty() else -1.0
	if action=="guardian_ring" and ok and outcome in ["progress","wrong","round","awake"]:
		var rung:=note_bell(info.get("bell"))
		if rung>=0:
			state.rung=rung
			state.rung_at=_now(main)
			state.play_start=-1.0
			Bell.play(main,rung)
	state.fingerprint=""
	refresh(main)

## Idempotent upkeep: safe every frame and every snapshot.
static func refresh(main) -> void:
	if not is_instance_valid(main) or not main.has_meta(META):return
	var state:Dictionary=main.get_meta(META)
	var snapshot:Dictionary=main.session.snapshot
	var open_now:=is_open(main)
	if not _available(snapshot):
		main.remove_meta(META)
		if open_now:main._close_modal()
		return
	var record:=record_of(snapshot,main.session.own_id)
	if int(record.round)!=int(state.round):
		state.round=int(record.round)
		state.notes=[]
		state.entered=0
		state.play_start=-1.0
	if not open_now:return
	var pos:=_own_position(main)
	if not pos.is_finite() or nearest_distance(pos)>LEAVE_DISTANCE:
		main._close_modal()
		return
	_advance(main,state)
	_render(main,state,record,pos)

static func _advance(main,state:Dictionary) -> void:
	if float(state.play_start)<0.0:return
	var notes:Array=state.notes
	var elapsed:=_now(main)-float(state.play_start)
	if notes.is_empty() or elapsed<0.0:
		state.play_start=-1.0
		return
	# Sound follows the same fixed step whether or not the lights animate.
	var due:=mini(notes.size()-1,int(floor(elapsed/(STEP_ON+STEP_GAP))))
	if due>int(state.played):
		state.played=due
		Bell.play(main,note_bell(notes[due]))
	if elapsed>=playback_duration(notes.size()):state.play_start=-1.0

static func _chip(main,index:int,bell:int,lit:bool,echoed:bool) -> PanelContainer:
	var chip:=PanelContainer.new()
	chip.name="GuardianNote%d"%index
	var tone:Color=Guardian.COLORS[bell]
	var style:=StyleBoxFlat.new()
	style.bg_color=tone if lit else tone.lerp(Color.WHITE,0.55)
	style.border_color=INK if lit else tone.darkened(0.25)
	style.set_border_width_all(4 if lit else 2)
	style.set_corner_radius_all(10)
	style.content_margin_left=16
	style.content_margin_right=16
	style.content_margin_top=8
	style.content_margin_bottom=8
	style.shadow_color=Color(0,0,0,0.22)
	style.shadow_size=3 if lit else 0
	chip.add_theme_stylebox_override("panel",style)
	chip.set_meta("guardian_lit",lit)
	var words:Label=main.label("%d  %s%s"%[index+1,bell_text(bell)," ✓" if echoed else ""],23)
	words.autowrap_mode=TextServer.AUTOWRAP_OFF
	words.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	words.add_theme_color_override("font_color",INK)
	chip.add_child(words)
	return chip

## Panel rect for main._layout_preview: a narrow, centred card sized to its content (the body's
## minimum plus the frame around it), so the claimed state shrinks and the scene stays visible.
static func layout(main,bounds:Vector2) -> void:
	var modal:Control=main.modal
	var body=modal.get_meta(BODY_META,null)
	# Large text: use (almost) the whole window so the reach hint is never clipped or scrolled.
	var large:bool=main.has_method("font_scale_factor") and float(main.font_scale_factor())>1.05
	var width:=minf(1180.0 if large else 740.0,bounds.x-(16.0 if large else 48.0))
	var wanted:=500.0
	var limit:=bounds.y-(8.0 if large else 48.0)
	if is_instance_valid(body):
		modal.size=Vector2(width,maxf(modal.size.y,100.0))
		wanted=modal.get_combined_minimum_size().y+(body as Control).get_combined_minimum_size().y
	modal.size=Vector2(width,clampf(wanted,300.0,limit))
	modal.position=(bounds-modal.size)/2.0

static func _clear(parent:Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

static func _render(main,state:Dictionary,record:Dictionary,pos:Vector2) -> void:
	var body:VBoxContainer=main.modal.get_meta(BODY_META)
	if not is_instance_valid(body):return
	var notes:Array=state.notes
	var reduced:=_reduced(main)
	var lit:=_lit_index(main,state)
	var asleep:=not Guardian.awake(record)
	var options:=menu_options(record,int(state.focus))
	var snapshot:Dictionary=main.session.snapshot
	if asleep and int(state.focus)<0 and snapshot.has(Trial.KEY):
		var label_text:="再試閃避" if snapshot[Trial.KEY].get("phase",-1)==Trial.Phase.MISSED else "閃避石掌"
		options.insert(0,{"id":"trial","label":label_text,"action":Trial.KEY,"cell":Guardian.GUARDIAN,"focus":false})
	var reach:Array=[]
	for option:Dictionary in options:reach.append(option_enabled(option,pos))
	var flash:=lit_bell(main)
	var fingerprint:=JSON.stringify([record,lit,flash,int(state.entered),str(state.message),notes,reach,reduced])
	if state.fingerprint==fingerprint:return
	state.fingerprint=fingerprint
	(body.get_node("GuardianHeader/GuardianScene") as Scene).show_state(Guardian.frame(record),flash,reduced)
	(body.find_child("GuardianStatus",true,false) as Label).text=status_text(record)
	var chips:=body.get_node("GuardianSequence") as HFlowContainer
	_clear(chips)
	chips.visible=asleep and not notes.is_empty()
	if chips.visible:
		for i in notes.size():chips.add_child(_chip(main,i,note_bell(notes[i]),i==lit,i<int(state.entered)))
	var line:=body.get_node("GuardianSequenceText") as Label
	if notes.is_empty():line.text="還沒聽過這一段。選「聽石像哼」，牠會哼 %d 個音；每個音都會亮出形狀、顏色和名字。"%phrase_length(record)
	elif reduced:line.text="石像哼的順序："+numbered_text(notes)
	else:line.text="石像哼的順序："+sequence_text(notes,lit)
	# The chips already show the whole sequence; keep the exact text for assistive tech, not twice on screen.
	line.visible=asleep and not chips.visible
	if "accessibility_name" in chips:chips.set("accessibility_name",line.text if chips.visible else "")
	var progress:=body.find_child("GuardianProgress",true,false) as Label
	progress.text=progress_text(record,int(state.entered))
	progress.visible=asleep
	var message:=body.get_node("GuardianMessage") as Label
	message.text=str(state.message)
	message.visible=not message.text.is_empty()
	var holder:=body.get_node("GuardianOptions") as VBoxContainer
	var ids:PackedStringArray=[]
	for option:Dictionary in options:ids.append(str(option.id))
	var layout:=",".join(ids)
	if state.options!=layout or holder.get_child_count()==0:
		state.options=layout
		_build_options(main,holder,options)
	var any_far:=false
	for i in options.size():
		var option:Dictionary=options[i]
		var button:=holder.find_child(button_name(str(option.id)),true,false) as Button
		if button==null:continue
		var enabled:bool=reach[i]
		any_far=any_far or not enabled
		button.disabled=not enabled
		button.text=str(option.label)
		button.tooltip_text="" if enabled else "走近一點"
	(body.get_node("GuardianReachHint") as Label).visible=any_far
	if main.has_method("_layout_preview"):main._layout_preview.call_deferred()

static func _build_options(main,holder:VBoxContainer,options:Array) -> void:
	var viewport:=holder.get_viewport()
	var focused:Control=viewport.gui_get_focus_owner() if viewport!=null else null
	var focus_name:String=focused.name if is_instance_valid(focused) and holder.is_ancestor_of(focused) else ""
	_clear(holder)
	var bells:HBoxContainer=null
	var actions:=HBoxContainer.new()
	actions.name="GuardianActions"
	actions.add_theme_constant_override("separation",6)
	for option:Dictionary in options:
		var action:=str(option.action)
		var cell:Vector2i=option.cell
		var callback:Callable=func():main.session.perform(action,cell,"")
		if action.is_empty():callback=func():main._close_modal()
		elif action==Trial.KEY:
			callback=func():
				main._close_modal()
				main.session.perform(Trial.KEY,cell,Trial.START)
		var button:Button=main.button(str(option.label),callback)
		button.name=button_name(str(option.id))
		button.autowrap_mode=TextServer.AUTOWRAP_OFF
		button.set_meta("guardian_focus",option.focus)
		if action=="guardian_ring":
			# The three bells share one row, low to high, like the cave wall.
			if bells==null:
				bells=HBoxContainer.new()
				bells.name="GuardianBells"
				bells.add_theme_constant_override("separation",6)
				holder.add_child(bells)
			button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			bells.add_child(button)
		else:
			# Listen, Sit and Leave (or Claim and Leave) share one compact row.
			button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN if action.is_empty() else Control.SIZE_EXPAND_FILL
			actions.add_child(button)
	if actions.get_child_count()>0:holder.add_child(actions)
	else:actions.free()
	if not focus_name.is_empty():
		var again:=holder.find_child(focus_name,true,false) as Button
		if again!=null:again.grab_focus.call_deferred()
		elif _yes(main.get("controller_navigation")):_focus_default.call_deferred(main)
