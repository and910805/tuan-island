extends RefCounted
## 望安開場的用戶端呈現：下船卡、左上角第一株作物指引、小栗留的田的地面標記。
## 只讀快照，不送出任何動作，也不寫入存檔。
const Opening=preload("res://scripts/wangan_opening.gd")
const ChapterOne=preload("res://scripts/chapter_one.gd")
const Art=preload("res://scripts/life_ui_theme.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const ArrivalScene=preload("res://scripts/wangan_arrival_scene.gd")
const CARD:="WanganArrival"
const CARD_WIDTH:=520.0
const CTA_DOCK:="去小栗留的田"
const CTA_AWAY:="回小栗留的田"
const ROPE:=Color("c9a46a")
const ROPE_SHADE:=Color("6f5236")
const STAKE:=Color("a8794a")
const STAKE_CAP:=Color("e0b97f")
const STAKE_OUTLINE:=Color("4a3626")
const SOIL_HINT:=Color(0.55,0.38,0.22,0.16)
const DOCK_ROUTE:=[Vector2i(52,30),Vector2i(52,29),Vector2i(52,28),Vector2i(52,27),Vector2i(51,27),Vector2i(50,27),Vector2i(49,27),Vector2i(48,27)]
const EdgeSweep=preload("res://scripts/edge_foot_sweep.gd")

# ---------- 下船卡 ----------

static func card(app) -> PanelContainer:
	if app==null or not is_instance_valid(app.hud):return null
	return app.hud.get_node_or_null(CARD) as PanelContainer

static func card_open(app) -> bool:
	var node:=card(app)
	return node!=null and not node.is_queued_for_deletion()

## Shown by main._entered for a brand-new arrival (Opening.is_new_arrival).
## A non-modal HUD card: the world keeps running, movement keys still walk,
## nothing grabs focus. Interact / confirm / Esc or the button close it.
static func show_arrival(app) -> void:
	dismiss(app)
	# The card replaces the generic entry toast (the life HUD hides it; the legacy
	# HUD falls back to its usual movement hint on the next frame).
	app.toast_time=0.0
	if app.village_art_preview and is_instance_valid(app.toast):app.toast.hide()
	var panel:=PanelContainer.new()
	panel.name=CARD
	panel.add_theme_stylebox_override("panel",Pixel.paper_style())
	panel.mouse_filter=Control.MOUSE_FILTER_STOP
	panel.focus_mode=Control.FOCUS_NONE
	var body:=VBoxContainer.new()
	body.add_theme_constant_override("separation",6)
	panel.add_child(body)
	var heading:=HBoxContainer.new()
	heading.add_theme_constant_override("separation",10)
	body.add_child(heading)
	var place:Label=app.label(Opening.PLACE,26)
	place.name="ArrivalPlace"
	place.autowrap_mode=TextServer.AUTOWRAP_OFF
	place.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	heading.add_child(place)
	var scene:Label=app.label(Opening.SCENE,17)
	scene.name="ArrivalScene"
	scene.autowrap_mode=TextServer.AUTOWRAP_OFF
	scene.size_flags_vertical=Control.SIZE_SHRINK_END
	scene.add_theme_color_override("font_color",Color("6d5a3c"))
	heading.add_child(scene)
	var arrival:Label=app.label(Opening.ARRIVAL,15)
	arrival.name="ArrivalBoat"
	body.add_child(arrival)
	var illustration:=ArrivalScene.new()
	illustration.name="ArrivalIllustration"
	illustration.motion=app.sound!=null and not app.sound.reduced_motion
	body.add_child(illustration)
	var quote_row:=HBoxContainer.new()
	quote_row.add_theme_constant_override("separation",10)
	body.add_child(quote_row)
	var portrait:=Art.icon("xiaoli")
	if portrait:
		var picture:=TextureRect.new()
		picture.name="ArrivalPortrait"
		picture.texture=portrait
		picture.custom_minimum_size=Vector2(40,40)
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
		picture.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		quote_row.add_child(picture)
	var quote:Label=app.label("「"+Opening.line_for(app.session.snapshot).replace("。先","。\n先")+"」",16)
	quote.name="ArrivalLine"
	quote.custom_minimum_size.x=260
	quote_row.add_child(quote)
	var footer:=HBoxContainer.new()
	footer.add_theme_constant_override("separation",8)
	body.add_child(footer)
	var hint:Label=app.label(close_hint(app),15)
	hint.name="ArrivalHint"
	hint.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	footer.add_child(hint)
	var go:Button=app.button(cta_text(app),func():dismiss(app))
	go.name="ArrivalClose"
	go.focus_mode=Control.FOCUS_NONE
	go.custom_minimum_size=Vector2(0,36)
	go.add_theme_font_size_override("font_size",15)
	footer.add_child(go)
	app.hud.add_child(panel)
	if app.village_art_preview:app.preview_controls.append(panel)
	# Wrapped labels report a tall minimum before they get their width; refit once
	# it settles so the card never stays taller than its text (and never swallows
	# world clicks below it).
	var refit:=func():
		if is_instance_valid(panel) and not panel.is_queued_for_deletion() and panel.is_inside_tree():
			layout(app,app.get_viewport().get_visible_rect().size)
	panel.minimum_size_changed.connect(refit,CONNECT_DEFERRED)
	layout(app,app.get_viewport().get_visible_rect().size)
	refit.call_deferred()
	if app.sound and not app.sound.reduced_motion:
		panel.modulate.a=0.0
		var tween:=panel.create_tween()
		tween.tween_property(panel,"modulate:a",1.0,0.2).set_trans(Tween.TRANS_SINE)

## The card button names the plot, not 小栗: the first step only needs the player
## beside the plot. Away from the starting dock (e.g. a card shown at World.SPAWN)
## it says 回 instead of 去.
static func cta_text(app) -> String:
	var person:Dictionary=app.session.snapshot.get("players",{}).get(app.session.own_id,{})
	return CTA_AWAY if not person.is_empty() and not ChapterOne.at_starting_dock(person) else CTA_DOCK

static func close_hint(app) -> String:
	return "%s／Esc 收起這張卡"%app.binding_label("interact")

## Closes the card; true when one was open (so the key that closed it does nothing else).
static func dismiss(app) -> bool:
	var node:=card(app)
	if node==null:return false
	var was_open:=not node.is_queued_for_deletion()
	app.preview_controls.erase(node)
	app.hud.remove_child(node)
	node.queue_free()
	return was_open

## Top centre, between the place title / tracker (left) and the weather badge
## (right); above the local player. Hidden with the rest of the HUD under modals.
static func layout(app,bounds:Vector2) -> void:
	var node:=card(app)
	if node==null:return
	var side:=260.0 if app.village_art_preview else 310.0
	var right:=bounds.x-side
	if app.village_art_preview and is_instance_valid(app.preview_top):
		right=minf(right,app.preview_top.position.x-12.0)
	var width:=clampf(right-side,320.0,CARD_WIDTH)
	node.custom_minimum_size=Vector2(width,0)
	node.size=Vector2(width,0)
	node.position=Vector2(floorf((side+right-node.size.x)/2.0),18.0 if app.village_art_preview else 100.0)
	var hint:=node.find_child("ArrivalHint",true,false) as Label
	if hint:hint.text=close_hint(app)

## Called with each HUD refresh: the card closes by itself once the player is
## no longer a fresh arrival (tilled, planted, built, travelled…).
static func refresh(app) -> void:
	if not card_open(app):return
	if not app.playing or not Opening.is_new_arrival(app.session.snapshot,app.session.own_id):dismiss(app)

# ---------- 左上角指引 ----------

static func personal_step(app)->Dictionary:
	var snapshot:Dictionary=app.session.snapshot
	var player:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	if not snapshot.get("chapter_one",{}).get("shipped",false) or not player.get(ChapterOne.PERSONAL_START,false):return {}
	return ChapterOne.first_crop_step(snapshot,app.session.own_id)

static func show_personal_help(app)->void:
	var step:=personal_step(app)
	if step.is_empty():return
	var body:VBoxContainer=app._open_modal("島民第一課")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	body.add_child(app.label(tracker_text(app,step),17))
	var steps:Label=app.label("用 {hoe} 鋤地、{seed} 播種、{water} 澆水，成熟後用 {harvest} 採收。帶著自己採收過的作物到村裡的出貨箱，靠近按 {interact}。",16)
	steps.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(steps)

static func tracker_text(app,step:Dictionary) -> String:
	var text:=str(step.get("text",""))
	var heading:=Opening.heading(app.session.snapshot)
	match str(step.get("id","")):
		"find":return "%s\n%s"%[heading,text]
		"till":return "%s\n%s\n%s 鋤頭 · 點草地"%[heading,text,app.binding_label("hoe")]
		"buy_seed":return "%s\n%s\n靠近種子攤按 %s"%[heading,text,app.binding_label("interact")]
		"sow":
			var seed:=str(step.get("seed","radish"))
			if seed!=str(app.crop):
				var name:String=ChapterOne.STARTER_CROPS.get(seed,preload("res://scripts/crop_catalog.gd").CROPS[seed].name)
				return "%s\n先按 %s 選%s種子\n%s 播種 · 點翻好的土"%[heading,app.binding_label("seeds"),name,app.binding_label("seed")]
			return "%s\n%s\n%s 播種 · %s 換種子"%[heading,text,app.binding_label("seed"),app.binding_label("seeds")]
		"water":return "%s\n%s\n%s 澆水 · 點那一格"%[heading,text,app.binding_label("water")]
		"wait":return "%s\n%s\n成熟前可以先逛逛"%[heading,text]
		"harvest":return "%s\n%s\n%s 採收 · 點成熟的作物"%[heading,text,app.binding_label("harvest")]
		"ship":return "✓ 第一株收成了\n%s\n靠近出貨箱按 %s"%[text,app.binding_label("interact")]
	return ""

# ---------- 地面標記 ----------

## Corner stakes, a twine rope and the 「小栗留的田」 tag, drawn on the ground
## layer (before props and people, after crops), static in every motion mode.
static func draw_plot(view,s:Dictionary,owner:String,step:Dictionary) -> Rect2:
	if step.is_empty():return Rect2()
	if Opening.plot_usable(s,owner):draw_plot_fence(view,s)
	if not view.photograph_mode and not view.hide_interaction_prompt and view.label_hide_rects.is_empty():
		draw_dock_directions(view,dock_directions(s,owner,step))
	if step.get("id","")=="buy_seed":return Rect2()
	return draw_step_cue(view,step)

static func dock_directions(snapshot:Dictionary,owner:String,step:Dictionary)->Array[Vector2i]:
	var markers:Array[Vector2i]=[]
	if step.get("id")!="find":return markers
	var person:Dictionary=snapshot.get("players",{}).get(owner,{})
	if person.is_empty():return markers
	var at:=Vector2(person.x,person.y)
	var closest:=-1
	var distance:=1.8
	for index in DOCK_ROUTE.size()-1:
		var center:=Vector2(DOCK_ROUTE[index])+Vector2(0.5,0.5)
		var span:=at.distance_to(center)
		if span<distance:
			closest=index
			distance=span
	if closest<0:return markers
	var objects:Dictionary=snapshot.get("objects",{})
	var forest:Dictionary=snapshot.get("forest",{})
	var edges:Dictionary=snapshot.get("edges",{})
	var world=preload("res://scripts/world.gd")
	for index in range(closest,DOCK_ROUTE.size()-1):
		var a:Vector2i=DOCK_ROUTE[index]
		var b:Vector2i=DOCK_ROUTE[index+1]
		var tile:=world.key(b)
		var start:=Vector2(a)+Vector2(0.5,0.5)
		var end:=Vector2(b)+Vector2(0.5,0.5)
		if objects.has(tile) or forest.has(tile) or EdgeSweep.blocks_axis(start,end,edges,world.SIZE,world.INDUSTRY.FOOT_BOX):return []
	for index in range(closest,mini(closest+4,DOCK_ROUTE.size())):
		markers.append(DOCK_ROUTE[index])
	return markers

static func draw_dock_directions(view,markers:Array[Vector2i])->void:
	for tile:Vector2i in markers:
		var index:=DOCK_ROUTE.find(tile)
		if index==-1 or index>=DOCK_ROUTE.size()-1:continue
		var forward:=Vector2(DOCK_ROUTE[index+1]-tile)
		var side:=forward.orthogonal()
		var at:Vector2=view.screen(Vector2(tile)+Vector2(0.5,0.65)).round()
		var arrow:=PackedVector2Array([at-forward*2.0+side*4.0,at+forward*3.0,at-forward*2.0-side*4.0])
		view.draw_polyline(arrow,STAKE_OUTLINE,4.0)
		view.draw_polyline(arrow,Color("#f6d88a"),2.0)

static func draw_step_cue(view,step:Dictionary) -> Rect2:
	if view.photograph_mode or view.hide_interaction_prompt:return Rect2()
	var target:=step_target(step)
	if target==ChapterOne.NO_PLOT_CELL:return Rect2()
	var at:Vector2=view.screen(Vector2(target)).round()
	var bounds:=Rect2(at,Vector2(32,32))
	var step_id:String=step.get("id","")
	if step_id in ["buy_seed","works","starter_kit","tea_intro"]:
		bounds=Rect2(at+Vector2(-8,-21),Vector2(48,54))
	var inner:=bounds.grow(-3.0)
	var corners:=[inner.position,Vector2(inner.end.x,inner.position.y),Vector2(inner.position.x,inner.end.y),inner.end]
	# The ripe-crop sparkle occupies the top-right corner of the tile.
	if step_id=="harvest":corners.remove_at(1)
	for start:Vector2 in corners:
		var direction:Vector2=(inner.get_center()-start).sign()
		for offset in [Vector2(direction.x*6,0),Vector2(0,direction.y*6)]:
			view.draw_line(start+Vector2.ONE,start+Vector2.ONE+offset,STAKE_OUTLINE,2.0)
			view.draw_line(start,start+offset,Color("fff0ad"),2.0)
	return bounds

static func step_target(step:Dictionary) -> Vector2i:
	if step.get("id","") in ["find","till","buy_seed","sow","water","harvest","ship","works","starter_kit","tea_intro"]:
		return step.get("cell",ChapterOne.NO_PLOT_CELL)
	return ChapterOne.NO_PLOT_CELL

static func draw_plot_fence(view,s:Dictionary) -> void:
	var cells:=Opening.plot_rect()
	for cell in ChapterOne.starter_plot_free(s):
		var at:Vector2=view.screen(Vector2(cell))
		view.draw_rect(Rect2(at+Vector2(3,3),Vector2(26,26)),SOIL_HINT)
	var rect:=Rect2(view.screen(Vector2(cells.position)),Vector2(cells.size)*32.0).grow(-1.0)
	var corners:=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	for i in 4:
		var a:Vector2=(corners[i] as Vector2).round()
		var b:Vector2=(corners[(i+1)%4] as Vector2).round()
		view.draw_line(a+Vector2(0,1),b+Vector2(0,1),ROPE_SHADE,1.0)
		view.draw_line(a,b,ROPE,1.0)
		var middle:=((a+b)/2.0).round()
		view.draw_rect(Rect2(middle-Vector2(1,1),Vector2(3,3)),ROPE_SHADE)
	for corner in corners:
		var foot:=(corner as Vector2).round()
		view.draw_rect(Rect2(foot+Vector2(-3,-10),Vector2(6,13)),STAKE_OUTLINE)
		view.draw_rect(Rect2(foot+Vector2(-2,-9),Vector2(4,11)),STAKE)
		view.draw_rect(Rect2(foot+Vector2(-2,-9),Vector2(4,2)),STAKE_CAP)
	view.world_label(view.screen(Vector2(float(cells.position.x)+float(cells.size.x)/2.0,float(cells.position.y)))+Vector2(0,-12),Opening.PLOT_TAG,Opening.PLOT_LABEL_ID)
