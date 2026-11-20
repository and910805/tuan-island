extends RefCounted
## P05 迷路小雞 client: one compact friendly panel (open(app)). Rules live in lost_chicks.gd;
## this file only reads snapshot.lost_chicks (public, no tokens) and snapshot.own_lost_chicks
## and sends every action through session.perform(ACTION, cell, payload):
##   "start" (at the sign) | "join:<round>" (at the sign) | "leave:<round>"
## The text/buttons rebuild only when the phase, round, mode or membership changes. Counts, the
## last-ten-seconds text and the chick positions update in place; the schematic is a separate
## lightweight draw control that is only redrawn (never rebuilt) when chicks move.
const Rules=preload("res://scripts/lost_chicks.gd")
const HarvestUI=preload("res://scripts/harvest_relay_ui.gd")
const CookUI=preload("res://scripts/cooking_relay_ui.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const LAYOUT:="lost_chicks"
const ACTION:="lost_chicks"
const TITLE:="迷路小雞"
const ANIMALS_PATH:="res://assets/life-art/animals.png"
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const LAST_SECONDS:=10.0
const MAP_SIZE:=Vector2(215,162)

static var _animals:Texture2D

# ------------------------------------------------------------------ state --

static func public_view(s:Dictionary)->Dictionary:
	var found:Variant=s.get("lost_chicks",{})
	return found if found is Dictionary else {}

static func own(s:Dictionary)->Dictionary:
	var found:Variant=s.get("own_lost_chicks",{})
	return found if found is Dictionary else {}

static func phase_of(p:Dictionary)->String:
	var phase:=str(p.get("phase","idle"))
	return phase if phase in ["idle","run","results"] else "idle"

static func chicks_of(p:Dictionary)->Array:
	var c:Variant=p.get("chicks",[])
	return c if c is Array else []

static func time_text(p:Dictionary)->String:
	if phase_of(p)!="run":return ""
	var left:=float(p.get("remaining",0.0))
	if left>LAST_SECONDS:return ""
	return "剩 %d 秒"%HarvestUI.whole_seconds(left)

static func progress_text(p:Dictionary)->String:
	return "已回家 %d / %d 隻"%[int(p.get("returned",0)),int(p.get("total",0))]

static func phase_text(p:Dictionary,m:Dictionary)->String:
	match phase_of(p):
		"run":return "進行中・第 %d 輪"%int(p.get("round",0)) if bool(m.get("joined",false)) else "旁觀中・第 %d 輪"%int(p.get("round",0))
		"results":return "第 %d 輪結算"%int(p.get("round",0))
	return "目前沒有進行中的一輪"

# ---------------------------------------------------------------- panel --

static func open(app)->void:
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.name="LostChicksPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("lostchicks_body",body)
	if app.village_art_preview:
		app.modal.theme=Pixel.make(app.hud.theme)
		app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.26
	body.add_theme_constant_override("separation",8)
	refresh(app)
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

static func layout(app,bounds:Vector2)->void:
	var modal:Control=app.modal
	modal.size.x=minf(560.0,bounds.x-32.0)
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var body:=modal.find_child("ModalContent",true,false) as Control
	var height:=420.0
	if outer and body:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=chrome+body.get_combined_minimum_size().y+2.0
	modal.size.y=minf(height,bounds.y-24.0)
	modal.position=((bounds-modal.size)/2.0).floor()

static func is_open(app)->bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("lostchicks_body")

static func focus_first(app)->void:
	if not is_open(app):return
	var body:Control=app.modal.get_meta("lostchicks_body")
	for node in body.find_children("*","BaseButton",true,false):
		var b:=node as BaseButton
		if b.is_visible_in_tree() and not b.disabled and b.focus_mode!=Control.FOCUS_NONE:
			b.grab_focus()
			return
	var close:=_close_button(app)
	if close!=null:close.grab_focus()

static func _close_button(app)->BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("lostchicks_body") if app.modal.has_meta("lostchicks_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func refresh(app)->void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var p:=public_view(s)
	var m:=own(s)
	var body:VBoxContainer=app.modal.get_meta("lostchicks_body")
	_update_footer(app)
	var signature:=JSON.stringify([phase_of(p),int(p.get("round",0)),str(p.get("mode","")),bool(m.get("unlocked",false)),bool(m.get("joined",false))])
	if str(app.modal.get_meta("lostchicks_signature",""))==signature:
		_update_live(body,p,s.get("players",{}).get(app.session.own_id,{}))
		return
	app.modal.set_meta("lostchicks_signature",signature)
	var focused:Control=body.get_viewport().gui_get_focus_owner() if body.is_inside_tree() else null
	var focus_name:String=str(focused.name) if is_instance_valid(focused) and body.is_ancestor_of(focused) else ""
	for child in body.get_children():body.remove_child(child);child.queue_free()
	if not bool(m.get("unlocked",false)):
		HarvestUI.wrapped(app,body,"迷路小雞尚未開放，之後再來看看。",17).name="LostChicksLocked"
		app._layout_preview.call_deferred()
		return
	build(app,body,p,m)
	_update_live(body,p,s.get("players",{}).get(app.session.own_id,{}))
	if not focus_name.is_empty():
		var next:=body.find_child(focus_name,true,false) as BaseButton
		if next!=null and not next.disabled:next.grab_focus.call_deferred()
		else:focus_first.call_deferred(app)
	app._layout_preview.call_deferred()

static func _update_footer(app)->void:
	if not is_instance_valid(app.modal_feedback):return
	var current:=str(app.modal_feedback.text)
	if current.is_empty() or current.begins_with("Esc 回到島上"):
		app.modal_feedback.text="Esc 回到島上 · 按 %s 開啟或操作"%app.binding_label("interact")

## Cheap per-tick update: counts, timer text and the schematic. No node is created.
static func _update_live(body:Control,p:Dictionary,player:Dictionary)->void:
	var progress:=body.find_child("LostChicksProgress",true,false) as Label
	if progress:progress.text=progress_text(p)+"・%d 分"%int(p.get("score",0))
	var timer:=body.find_child("LostChicksTime",true,false) as Label
	if timer:timer.text=time_text(p)
	var map:=body.find_child("LostChicksMap",true,false) as Control
	if map:
		var chicks:=chicks_of(p)
		var player_cell:=Vector2i(Vector2(player.get("x",-1),player.get("y",-1)).floor())
		var key:=JSON.stringify([chicks,player_cell])
		if str(map.get_meta("chick_key",""))!=key:
			map.set_meta("chick_key",key)
			map.set_meta("chicks",chicks)
			map.set_meta("player_cell",player_cell)
			map.queue_redraw()

# ---------------------------------------------------------------- build --

static func build(app,body:VBoxContainer,p:Dictionary,m:Dictionary)->void:
	var phase:=phase_of(p)
	var rid:=str(int(p.get("round",0)))
	var joined:=bool(m.get("joined",false))
	var head:=HBoxContainer.new();head.name="LostChicksHeader";head.add_theme_constant_override("separation",12);body.add_child(head)
	var status:=HarvestUI.text(app,head,phase_text(p,m),16,WARN);status.name="LostChicksPhase"
	status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	HarvestUI.text(app,head,"",16,WARN).name="LostChicksTime"
	if phase!="idle":HarvestUI.text(app,body,"",16,GOOD).name="LostChicksProgress"
	var route:=HBoxContainer.new()
	route.add_theme_constant_override("separation",14)
	body.add_child(route)
	var steps:=VBoxContainer.new()
	steps.custom_minimum_size.x=192
	steps.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	route.add_child(steps)
	if phase=="results":
		HarvestUI.wrapped(app,steps,"小雞都回家了。每帶回一隻得 2 分。",16,GOOD)
	else:
		HarvestUI.wrapped(app,steps,"1　領取飼料桶\n2　走近一隻小雞\n3　帶著牠走回圍欄",16,INK)
		HarvestUI.wrapped(app,steps,"飼料免費借用。",14,GOOD)
	route.add_child(make_map())
	HarvestUI.wrapped(app,body,"藍點是你・牌是入口・欄是小雞的家",13,MUTED)
	var bar:=HBoxContainer.new();bar.name="LostChicksActions";bar.add_theme_constant_override("separation",10);body.add_child(bar)
	var cell:Vector2i=Rules.SIGN
	var buttons:Array[Button]=[]
	var open_round:=phase!="run"
	var start_reason:="" if open_round else "這一輪還沒結束。"
	buttons.append(HarvestUI.action(app,bar,"LostChicksStart","開始找小雞",func():app.session.perform(ACTION,cell,"start"),open_round,start_reason))
	var join_ok:=phase=="run" and not joined
	var join_reason:=""
	if not join_ok:join_reason="你已經加入了。" if joined else "現在沒有可加入的場次。"
	buttons.append(HarvestUI.action(app,bar,"LostChicksJoin","加入並借飼料桶",func():app.session.perform(ACTION,cell,"join:"+rid),join_ok,join_reason))
	buttons.append(HarvestUI.action(app,bar,"LostChicksLeave","離開",func():app.session.perform(ACTION,cell,"leave:"+rid),joined,"你還沒加入。"))
	buttons[0].visible=open_round
	buttons[1].visible=join_ok
	buttons[2].visible=joined
	for b in buttons:b.custom_minimum_size.x=104
	CookUI.link_focus(app,buttons)

## Small draw-only control; its content comes from meta so it never needs rebuilding.
static func make_map()->Control:
	var map:=Control.new()
	map.name="LostChicksMap"
	map.custom_minimum_size=MAP_SIZE
	map.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	map.set_meta("chicks",[])
	map.draw.connect(func():draw_map(map))
	return map

static func _animal_texture()->Texture2D:
	if _animals==null and ResourceLoader.exists(ANIMALS_PATH):
		_animals=load(ANIMALS_PATH) as Texture2D
	return _animals

static func draw_chick(map:Control,center:Vector2,size:float,status:String)->void:
	var tex:=_animal_texture()
	var box:=Rect2(center-Vector2(size,size)*0.5,Vector2(size,size))
	if tex!=null:map.draw_texture_rect_region(tex,box,Rect2(0,0,32,32))
	else:
		map.draw_circle(center,size*0.4,Color("f2c94c"))
		map.draw_arc(center,size*0.4,0,TAU,16,INK,1.5)
	var mark:="？" if status=="lost" else ("→" if status=="follow" else "✓")
	var font:=ThemeDB.fallback_font
	var fs:=int(maxf(10.0,size*0.55))
	map.draw_string(font,center+Vector2(size*0.3,-size*0.25),mark,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,INK)

static func draw_map(map:Control)->void:
	var area:Rect2i=Rules.AREA
	var cell:float=minf(map.size.x/float(area.size.x),map.size.y/float(area.size.y))
	var origin:=Vector2((map.size.x-cell*area.size.x)/2.0,(map.size.y-cell*area.size.y)/2.0)
	var field:=Rect2(origin,Vector2(cell*area.size.x,cell*area.size.y))
	map.draw_rect(field,Color("e9f0c8"))
	map.draw_rect(field,INK,false,2.0)
	var font:=ThemeDB.fallback_font
	var fs:=int(maxf(11.0,cell*0.6))
	# sign (square) and pen (dashed-looking double frame), distinguishable without colour
	var sign_cell:Vector2i=Rules.SIGN
	var pen_cell:Vector2i=Rules.PEN
	var sign_rect:=Rect2(origin+Vector2(sign_cell-area.position)*cell,Vector2(cell,cell))
	var pen_rect:=Rect2(origin+Vector2(pen_cell-area.position)*cell,Vector2(cell,cell))
	map.draw_rect(sign_rect.grow(-2),Color("c98a4b"))
	map.draw_rect(sign_rect.grow(-2),INK,false,2.0)
	map.draw_string(font,sign_rect.position+Vector2(0,cell*0.75),"牌",HORIZONTAL_ALIGNMENT_CENTER,cell,fs,INK)
	map.draw_rect(pen_rect.grow(-1),Color("fff3d6"))
	map.draw_rect(pen_rect.grow(-1),INK,false,2.0)
	map.draw_rect(pen_rect.grow(-5),INK,false,1.0)
	map.draw_string(font,pen_rect.position+Vector2(0,cell*0.75),"欄",HORIZONTAL_ALIGNMENT_CENTER,cell,fs,INK)
	var player_cell:Vector2i=map.get_meta("player_cell",Vector2i(-1,-1))
	if area.has_point(player_cell):
		var center:=origin+(Vector2(player_cell-area.position)+Vector2(0.5,0.5))*cell
		map.draw_circle(center+Vector2(4,4),4.5,Color("fff7db"))
		map.draw_circle(center+Vector2(4,4),3.0,Color("286590"))
	var chicks:Array=map.get_meta("chicks",[])
	if chicks.is_empty():
		# idle: show a sample lost chick so the goal is clear (solo: relative to sign and pen).
		var sample:=Vector2(Rules.SOLO_SPOTS[0])
		if Rect2i(area).has_point(Vector2i(sample)):
			draw_chick(map,origin+(sample-Vector2(area.position)+Vector2(0.5,0.5))*cell,cell*0.9,"lost")
		return
	for c in chicks:
		if not c is Dictionary:continue
		var at:=Vector2(int(c.get("x",0)),int(c.get("y",0)))
		var local:=at-Vector2(area.position)
		if local.x<0 or local.y<0 or local.x>=area.size.x or local.y>=area.size.y:continue
		draw_chick(map,origin+(local+Vector2(0.5,0.5))*cell,cell*0.9,str(c.get("status","lost")))
