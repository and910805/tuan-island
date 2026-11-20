extends RefCounted
## P08 共享沙灘活動「海灘尋寶」— 告示牌卡（spot 為空）與地點站卡（spot = a..f）。
##
## Display + intent only. Everything shown is derived from Session.snapshot
## (beach_treasure, own_beach_treasure, players) and every change goes through
## Session.perform(ACTION, cell, payload). This script never writes snapshot,
## World, inventory or save data; the rules/world stay the only authority.
##
## Wire intents (res://scripts/beach_treasure.gd ACTION/KEY "beach_treasure"):
## - "start"            at SIGN
## - "join:<round>"     at SIGN
## - "leave:<round>"    at SIGN
## - "mark:<round>"     at the exact SPOTS[spot].cell
## - "dig:<round>"      at the exact SPOTS[spot].cell
## <round> is read from the snapshot at the moment of the click.
##
## Behaviour notes
## - Buttons are shown/enabled by phase (idle/search/results), membership and the
##   player's presence next to the sign / station. A disabled button always has a
##   visible reason line; nothing is sent automatically or retried.
## - The countdown number is never shown except as a warning in the last 10 s.
##   Results are terminal and show no timer at all.
## - refresh() updates widgets in place (clue rows rebuild only when their text
##   changes) so keyboard focus is kept; if the focused button goes away, focus
##   moves to the next usable action.
## - The window never captures walking: closing it (Esc / close button, owned by
##   main.gd) is what returns control to the player.

const Items=preload("res://scripts/inventory_item_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const LAYOUT:="beach_treasure"
const META:="beach_treasure"
const RULES:="res://scripts/beach_treasure.gd"
const DEFAULT_ACTION:="beach_treasure"
const DEFAULT_SIGN:=Vector2i(50,55)
const DEFAULT_REACH:=3.2
const WARN_SECONDS:=10
const INK:=Color("3d422d")
const MUTED:=Color("76694c")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const SAND:=Color("e9d9ae")
const SAND_DARK:=Color("bfa47a")
const WOOD:=Color("8a5a3a")
const SEA:=Color("7fb4c4")

## Entry point: the sign (spot == "") or one search station (spot == a..f).
static func open(app,spot:String="")->void:
	var station:=spot.strip_edges().to_lower()
	var title:="海灘尋寶"
	if not station.is_empty():
		var info:=Rules.spot(station)
		title="海灘尋寶・"+(str(info.get("title","地點 "+station.to_upper())) if not info.is_empty() else "地點 "+station.to_upper())
	var body:VBoxContainer=app._open_modal(title)
	var modal:Control=app.modal
	modal.name="BeachTreasureUI"
	modal.set_meta("life_modal_layout",LAYOUT)
	modal.theme=_theme(app.hud.theme)
	modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",6)
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.3
	if is_instance_valid(app.modal_feedback):app.modal_feedback.hide()
	var controller:=Controller.new()
	controller.name="BeachTreasureController"
	controller.app=app
	controller.spot=station
	modal.set_meta(META,controller)
	modal.add_child(controller)
	controller.build(body)
	controller.refresh()
	controller.fit_now()
	controller.focus_start.call_deferred()

static func refresh(app)->void:
	var controller:=_controller(app)
	if controller:controller.refresh()

static func layout(app,_bounds:Vector2)->void:
	var controller:=_controller(app)
	if controller:controller.fit_now()

static func _controller(app)->Controller:
	if not is_instance_valid(app.modal) or str(app.modal.get_meta("life_modal_layout",""))!=LAYOUT:return null
	var found=app.modal.get_meta(META,null)
	if not is_instance_valid(found) or not found is Controller:return null
	return found

static func _theme(base:Theme)->Theme:
	var theme:=Pixel.make(base)
	var disabled:=Pixel.texture_style("button_normal",3,0)
	disabled.modulate_color=Color(1,1,1,0.55)
	for side in [SIDE_LEFT,SIDE_RIGHT]:disabled.set_content_margin(side,12)
	for side in [SIDE_TOP,SIDE_BOTTOM]:disabled.set_content_margin(side,8)
	theme.set_stylebox("disabled","Button",disabled)
	theme.set_color("font_disabled_color","Button",Color(INK,0.5))
	theme.set_stylebox("background","ProgressBar",Pixel.texture_style("normal",3,2))
	var fill:=StyleBoxFlat.new()
	fill.bg_color=Color("dd8f3e")
	fill.border_color=Color("a65a28")
	fill.set_border_width_all(2)
	fill.anti_aliasing=false
	theme.set_stylebox("fill","ProgressBar",fill)
	theme.set_color("font_color","Label",INK)
	return theme


## Read-only access to the rules script with safe fallbacks (the UI must keep
## working, disabled, if the rules script is missing or a constant changed).
class Rules:
	static func script():
		if not ResourceLoader.exists(RULES):return null
		return load(RULES)

	static func constant(name:String,fallback):
		var helper=script()
		if helper is Script:
			var map:Dictionary=helper.get_script_constant_map()
			if map.has(name):return map[name]
		return fallback

	static func action()->String:
		return str(constant("ACTION",constant("KEY",DEFAULT_ACTION)))

	static func key()->String:
		return str(constant("KEY",DEFAULT_ACTION))

	static func sign_cell()->Vector2i:
		var found=constant("SIGN",DEFAULT_SIGN)
		return found if found is Vector2i else DEFAULT_SIGN

	static func reach()->float:
		for name in ["REACH","RANGE","USE_RANGE"]:
			var found=constant(name,null)
			if found is float or found is int:return float(found)
		return DEFAULT_REACH

	static func spots()->Dictionary:
		var found=constant("SPOTS",{})
		return found if found is Dictionary else {}

	static func spot_ids()->Array:
		var ids:Array=[]
		for id in spots():ids.append(str(id))
		ids.sort()
		return ids

	static func spot(id:String)->Dictionary:
		var all:=spots()
		var entry=all.get(id,all.get(StringName(id),null))
		if not entry is Dictionary:return {}
		var cell=entry.get("cell",null)
		if not cell is Vector2i:return {}
		return {"cell":cell,"title":str(entry.get("title","地點 "+id.to_upper()))}

	static func area()->Rect2i:
		var found=constant("AREA",null)
		if found is Rect2i:return found
		if found is Rect2:return Rect2i(found)
		return Rect2i()


## Pure snapshot reads. Never mutate the snapshot passed in.
class Query:
	static func game(s:Dictionary)->Dictionary:
		var found=s.get(Rules.key(),s.get("beach_treasure",{}))
		return found if found is Dictionary else {}

	static func own(s:Dictionary)->Dictionary:
		var found=s.get("own_beach_treasure",{})
		return found if found is Dictionary else {}

	static func phase(g:Dictionary)->String:
		var text:=str(g.get("phase","idle"))
		return text if text in ["idle","search","results"] else "idle"

	static func flag(table,id:String)->bool:
		if not table is Dictionary:return false
		return bool(table.get(id,table.get(StringName(id),false)))

	static func count(table)->int:
		var n:=0
		if table is Dictionary:
			for id in table:
				if bool(table[id]):n+=1
		return n

	static func clues(g:Dictionary)->Array:
		var out:Array=[]
		var raw=g.get("clues",[])
		if raw is Array:
			for item in raw:
				var text:=str(item).strip_edges()
				if not text.is_empty():out.append(text)
		return out

	static func guests(g:Dictionary)->int:
		var raw=g.get("guests",0)
		if raw is Array or raw is Dictionary:return raw.size()
		return maxi(0,int(raw))

	static func person(s:Dictionary,id:String)->Dictionary:
		var players=s.get("players",{})
		if not players is Dictionary:return {}
		var found=players.get(id,{})
		return found if found is Dictionary else {}

	## null when the position is unknown (then presence is left to the rules).
	static func near(s:Dictionary,id:String,cell:Vector2i):
		var p:=person(s,id)
		if p.is_empty() or not p.has("x") or not p.has("y"):return null
		var at:=Vector2(float(p.x),float(p.y))
		return at.distance_to(Vector2(cell)+Vector2(0.5,0.5))<=Rules.reach()

	## Decorative item art for a clue (the text is the information).
	static func clue_item(text:String,index:int)->String:
		var table:=[
			[["魚","蟹","潮","浪","海水"],"carp"],
			[["木","漂流","枝","船"],"wood"],
			[["草","藤","繩","海藻","網"],"fiber"],
			[["金","寶","幣","箱"],"coins"],
			[["石","岩","礁","沙丘"],"stone"]]
		for entry in table:
			for word in entry[0]:
				if text.contains(word):return str(entry[1])
		return ["stone","wood","fiber"][index%3]


## Small live diagram: search stations, sign, shared marks, finds, you.
class BeachMap extends Control:
	var snapshot:Dictionary={}
	var own_id:=""
	var highlight:=""

	func _ready()->void:
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func show_state(s:Dictionary,own:String,focus:String)->void:
		snapshot=s
		own_id=own
		highlight=focus
		queue_redraw()

	func _bounds()->Rect2:
		var cells:Array[Vector2]=[Vector2(Rules.sign_cell())]
		for id in Rules.spot_ids():cells.append(Vector2(Rules.spot(id).cell))
		var box:=Rect2(cells[0],Vector2.ZERO)
		for c in cells:box=box.expand(c)
		var area:=Rules.area()
		if area.size.x>0 and area.size.y>0:
			box=box.merge(Rect2(Vector2(area.position),Vector2(area.size)))
		return box.grow(1.5)

	func _draw()->void:
		var box:=_bounds()
		if box.size.x<=0.0 or box.size.y<=0.0:return
		var unit:=minf(size.x/box.size.x,size.y/box.size.y)
		if unit<3.0:return
		var extent:=box.size*unit
		var offset:=((size-extent)/2.0).floor()
		draw_rect(Rect2(offset-Vector2(2,2),extent+Vector2(4,4)),WOOD)
		draw_rect(Rect2(offset,extent),SAND)
		draw_rect(Rect2(offset,Vector2(extent.x,minf(extent.y*0.18,extent.y))),Color(SEA,0.55))
		var g:=Query.game(snapshot)
		var found=g.get("found",{})
		var marks=g.get("marks",{})
		var searched=g.get("searched",{})
		var font:=ThemeDB.fallback_font
		var sign_at:=offset+(Vector2(Rules.sign_cell())+Vector2(0.5,0.5)-box.position)*unit
		draw_rect(Rect2(sign_at-Vector2(5,5),Vector2(10,10)),WOOD)
		draw_rect(Rect2(sign_at-Vector2(3,3),Vector2(6,6)),Color("f4e8c4"))
		for id in Rules.spot_ids():
			var at:=offset+(Vector2(Rules.spot(id).cell)+Vector2(0.5,0.5)-box.position)*unit
			var done:=Query.flag(found,id)
			var marked:=Query.flag(marks,id)
			var fill:=Color("d2bd8c")
			if done:fill=Color("6f9c5a")
			elif Query.flag(searched,id):fill=Color("aaa89b")
			elif marked:fill=Color("dd8f3e")
			var radius:=maxf(7.0,unit*0.45)
			if id==highlight:draw_arc(at,radius+4.0,0,TAU,24,WARN,2.0)
			draw_circle(at,radius,WOOD)
			draw_circle(at,radius-2.0,fill)
			if font:
				draw_string(font,at+Vector2(-4,5),id.to_upper(),HORIZONTAL_ALIGNMENT_LEFT,-1,12,INK)
		var p:=Query.person(snapshot,own_id)
		if p.has("x") and p.has("y"):
			var you:=offset+(Vector2(float(p.x),float(p.y))-box.position)*unit
			if Rect2(offset,extent).has_point(you):
				draw_circle(you,3.5,Color("2f5f8a"))


class Controller extends Node:
	const ACK_TIMEOUT_MS:=10000
	const QUIET_MS:=1500
	const BOARD_SIZE:=Vector2(720,540)
	const STATION_SIZE:=Vector2(520,470)
	const MARGIN:=48.0
	var app
	var spot:=""
	var refs:Dictionary={}
	var actions:Array=[]
	var pending:Dictionary={}
	var clue_signature:="\u0001"
	var last_status:=""

	func _ready()->void:
		app.session.action_completed.connect(_on_completed)
		app.session.changed.connect(_on_changed)
		get_viewport().size_changed.connect(fit_now)

	func _exit_tree()->void:
		if app and app.session:
			if app.session.action_completed.is_connected(_on_completed):app.session.action_completed.disconnect(_on_completed)
			if app.session.changed.is_connected(_on_changed):app.session.changed.disconnect(_on_changed)
		var viewport:=get_viewport()
		if viewport and viewport.size_changed.is_connected(fit_now):viewport.size_changed.disconnect(fit_now)

	# ------------------------------------------------------------------ layout

	func target_rect()->Rect2:
		var bounds:=get_viewport().get_visible_rect().size
		var want:=STATION_SIZE if not spot.is_empty() else BOARD_SIZE
		if spot.is_empty() and Query.phase(Query.game(app.session.snapshot))!="search":want.y=474
		var extent:=Vector2(minf(want.x,bounds.x-MARGIN),minf(want.y,bounds.y-MARGIN)).floor()
		return Rect2(((bounds-extent)/2.0).floor(),extent)

	func fit_now()->void:
		var modal:=get_parent() as Control
		if modal==null:return
		var rect:=target_rect()
		modal.size=rect.size
		modal.position=rect.position

	func _process(_delta:float)->void:
		var modal:=get_parent() as Control
		if modal:
			var rect:=target_rect()
			if modal.size!=rect.size or modal.position!=rect.position:fit_now()
		if pending.is_empty():return
		var waited:=Time.get_ticks_msec()-int(pending.at)
		if bool(pending.correlated):
			if waited>ACK_TIMEOUT_MS:
				pending={}
				_status("還沒收到回應，結果未知。重試前請先看頁面狀態是否已更新。",false)
				refresh()
		elif waited>QUIET_MS:
			pending={}
			refresh()

	func focus_start()->void:
		for button in actions:
			if _usable(button):
				button.grab_focus()
				return

	# ------------------------------------------------------------------- build

	func build(body:VBoxContainer)->void:
		var board:=spot.is_empty()
		var info:=Rules.spot(spot)
		if not board and info.is_empty():
			_text(body,"找不到這個尋寶地點，請關閉後再試一次。",15,WARN)
			refs.status=_text(body,"",14)
			return
		var head:=HBoxContainer.new()
		head.name="BeachTreasureHeader"
		head.add_theme_constant_override("separation",8)
		body.add_child(head)
		head.add_child(_picture(Items.icon("stone" if not board else "wood"),40,"BeachTreasureIcon"))
		var head_text:=VBoxContainer.new()
		head_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		head_text.add_theme_constant_override("separation",0)
		head.add_child(head_text)
		refs.phase=_text(head_text,"",18)
		refs.phase.name="BeachTreasurePhase"
		refs.timer=_text(head_text,"",14,WARN)
		refs.timer.name="BeachTreasureTimer"
		refs.timer.visible=false
		var middle:=HBoxContainer.new()
		middle.add_theme_constant_override("separation",8)
		middle.size_flags_vertical=Control.SIZE_EXPAND_FILL
		body.add_child(middle)
		var left:=VBoxContainer.new()
		left.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation",5)
		middle.add_child(left)
		var title:=_text(left,"共用線索",14,MUTED)
		title.name="BeachTreasureClueTitle"
		refs.clue_title=title
		var clues:=VBoxContainer.new()
		clues.name="BeachTreasureClues"
		clues.add_theme_constant_override("separation",4)
		left.add_child(clues)
		refs.clues=clues
		refs.progress=_text(left,"",14)
		refs.progress.name="BeachTreasureProgress"
		var meter:=ProgressBar.new()
		meter.name="BeachTreasureMeter"
		meter.show_percentage=false
		meter.custom_minimum_size.y=8
		meter.mouse_filter=Control.MOUSE_FILTER_IGNORE
		left.add_child(meter)
		refs.meter=meter
		if board:
			refs.result=_card(left,"BeachTreasureResult")
			refs.result_text=_text(refs.result.get_child(0),"",14)
		else:
			refs.station=_card(left,"BeachTreasureStation")
			refs.station_text=_text(refs.station.get_child(0),"",14)
		var map:=BeachMap.new()
		map.name="BeachTreasureMap"
		map.custom_minimum_size=Vector2(190,190) if board else Vector2(150,150)
		map.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
		middle.add_child(map)
		refs.map=map
		var row:=HFlowContainer.new()
		row.name="BeachTreasureActions"
		row.add_theme_constant_override("h_separation",6)
		row.add_theme_constant_override("v_separation",4)
		body.add_child(row)
		if board:
			refs.start=_action(row,"BeachTreasureStart","開始尋寶",_start)
			refs.join=_action(row,"BeachTreasureJoin","加入這一輪",_join)
			refs.leave=_action(row,"BeachTreasureLeave","離開這一輪",_leave)
		else:
			refs.mark=_action(row,"BeachTreasureMark","標記共享",_mark)
			refs.dig=_action(row,"BeachTreasureDig","在這裡挖掘",_dig)
		refs.reason=_text(body,"",13,MUTED)
		refs.reason.name="BeachTreasureReason"
		var foot:=HBoxContainer.new()
		foot.add_theme_constant_override("separation",6)
		body.add_child(foot)
		refs.status=_text(foot,"",14)
		refs.status.name="BeachTreasureStatus"
		refs.status.custom_minimum_size.y=22

	func _card(parent:Node,id:String)->PanelContainer:
		var card:=PanelContainer.new()
		card.name=id
		card.add_theme_stylebox_override("panel",BeachTreasureStyle.card())
		parent.add_child(card)
		var column:=VBoxContainer.new()
		column.add_theme_constant_override("separation",3)
		card.add_child(column)
		return card

	func _text(parent:Node,value:String,size:int=15,color:Color=INK)->Label:
		var label:Label=app.label(value,size)
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color",color)
		parent.add_child(label)
		return label

	func _picture(texture:Texture2D,extent:int,id:String)->TextureRect:
		var picture:=TextureRect.new()
		if not id.is_empty():picture.name=id
		picture.texture=texture
		picture.custom_minimum_size=Vector2(extent,extent)
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
		picture.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		return picture

	func _action(parent:Node,id:String,title:String,callback:Callable)->Button:
		var button:=Button.new()
		button.name=id
		button.text=title
		button.focus_mode=Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size",15)
		button.custom_minimum_size.y=36
		button.pressed.connect(callback)
		button.set_meta("allowed",false)
		button.set_meta("shown",true)
		parent.add_child(button)
		actions.append(button)
		return button

	# ----------------------------------------------------------------- refresh

	func _on_changed(_snapshot:Dictionary,_own:String)->void:
		refresh()

	func refresh()->void:
		if not refs.has("status") or not refs.has("phase"):return
		var s:Dictionary=app.session.snapshot
		var g:=Query.game(s)
		var o:=Query.own(s)
		var phase:=Query.phase(g)
		var own_id:String=str(app.session.own_id)
		_update_header(g,o,phase)
		_update_clues(g,phase)
		_update_progress(g,phase)
		(refs.map as BeachMap).show_state(s,own_id,spot)
		if spot.is_empty():_update_board(s,g,o,phase,own_id)
		else:_update_station(s,g,o,phase,own_id)
		_sync()

	func _update_header(g:Dictionary,o:Dictionary,phase:String)->void:
		var label:Label=refs.phase
		var timer:Label=refs.timer
		timer.visible=false
		match phase:
			"search":
				label.text="第 %d 輪・搜尋中"%int(g.get("round",0))
				# No running countdown: only the final warning seconds are shown.
				var left:=int(g.get("remaining",0))
				if left>0 and left<=WARN_SECONDS:
					timer.text="快結束了：剩 %d 秒"%left
					timer.visible=true
			"results":label.text="第 %d 輪・已結束"%int(g.get("round",0))
			_:label.text="還沒有人在尋寶" if bool(o.get("unlocked",false)) else "海灘尋寶尚未開放"

	func _update_clues(g:Dictionary,phase:String)->void:
		var on:=phase=="search"
		if spot.is_empty():
			var map:BeachMap=refs.map
			map.custom_minimum_size.y=190.0 if on else 132.0
		(refs.clue_title as Label).visible=on
		(refs.clues as VBoxContainer).visible=on
		if not on:return
		var clues:=Query.clues(g)
		var signature:=JSON.stringify([phase,clues])
		if signature==clue_signature:return
		clue_signature=signature
		var box:VBoxContainer=refs.clues
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
		for i in 3:
			var card:=PanelContainer.new()
			card.name="BeachTreasureClue_%d"%i
			card.add_theme_stylebox_override("panel",BeachTreasureStyle.card())
			box.add_child(card)
			var row:=HBoxContainer.new()
			row.add_theme_constant_override("separation",8)
			card.add_child(row)
			var known:=i<clues.size()
			var text:String=clues[i] if known else ("開始後會出現線索" if phase=="idle" else "這條線索還沒出現")
			var icon:=_picture(Items.icon(Query.clue_item(text,i)) if known else Items.icon("backpack"),36,"")
			if not known:icon.modulate=Color(1,1,1,0.45)
			row.add_child(icon)
			_text(row,text,14,INK if known else MUTED)

	func _update_progress(g:Dictionary,phase:String)->void:
		var total:=3
		var found:=Query.count(g.get("found",{}))
		var marked:=Query.count(g.get("marks",{}))
		var meter:ProgressBar=refs.meter
		meter.max_value=total
		meter.value=found
		meter.visible=phase!="idle"
		var progress:Label=refs.progress
		progress.visible=phase!="idle"
		progress.text="已找到 %d / %d　·　共享標記 %d　·　參加 %d 人"%[found,total,marked,Query.guests(g)]

	# ------------------------------------------------------------------- board

	func _update_board(s:Dictionary,g:Dictionary,o:Dictionary,phase:String,own_id:String)->void:
		var unlocked:=bool(o.get("unlocked",false))
		var joined:=bool(o.get("joined",false))
		var completed:=bool(o.get("completed",false))
		var can_start:=bool(o.get("can_start",false))
		var near=Query.near(s,own_id,Rules.sign_cell())
		var busy:=not pending.is_empty()
		var why:=""
		var show_start:=phase!="search"
		var show_join:=phase=="search" and not joined
		var show_leave:=phase=="search" and joined
		var allowed_start:=show_start and unlocked and can_start
		var allowed_join:=show_join and unlocked
		var allowed_leave:=show_leave
		if not unlocked:why="海灘尋寶尚未解鎖。"
		elif (show_start or show_join) and near==false:why="走到告示牌旁就能加入或開一輪。"
		elif busy:why="上一個請求還在等待回應。"
		elif not _online():why="與世界的連線已中斷。"
		elif phase=="idle" and not can_start:why="現在還不能開始尋寶。"
		elif phase=="results" and not can_start:why="這一輪已結束，目前還不能開始新的一輪。"
		var blocked:=not why.is_empty()
		_set_action(refs.start,show_start,allowed_start and not blocked)
		_set_action(refs.join,show_join,allowed_join and not blocked)
		_set_action(refs.leave,show_leave,allowed_leave and not blocked)
		if phase=="search" and unlocked and not blocked:
			why="你已加入這一輪，可去各處地點標記與挖掘。" if joined else "加入後才能在各地點標記與挖掘。"
			(refs.reason as Label).add_theme_color_override("font_color",MUTED)
		else:
			(refs.reason as Label).add_theme_color_override("font_color",WARN if blocked else MUTED)
			if phase=="idle" and not blocked:why="五分鐘內找三處寶物。挖錯會解開更清楚的線索。"
		(refs.reason as Label).text=why
		(refs.start as Button).text="開始新的一輪" if phase=="results" else "開始尋寶"
		var card:PanelContainer=refs.result
		card.visible=phase=="results" or (phase=="idle" and completed)
		var lines:=PackedStringArray()
		if phase=="results":
			lines.append("三處寶物全找到了！" if g.get("reason")=="goal" else "這一輪時間到了。")
			lines.append("本輪共 %d 分"%int(g.get("score",0)))
			if completed:lines.append("尋寶紀念已收錄。")
		elif completed:
			lines.append("你已完成過尋寶，紀念留在你這裡。")
		(refs.result_text as Label).text="\n".join(lines)

	# ----------------------------------------------------------------- station

	func _update_station(s:Dictionary,g:Dictionary,o:Dictionary,phase:String,own_id:String)->void:
		var info:=Rules.spot(spot)
		if info.is_empty():return
		var unlocked:=bool(o.get("unlocked",false))
		var joined:=bool(o.get("joined",false))
		var found:=Query.flag(g.get("found",{}),spot)
		var marked:=Query.flag(g.get("marks",{}),spot)
		var dug:=Query.flag(g.get("searched",{}),spot)
		var near=Query.near(s,own_id,info.cell)
		var busy:=not pending.is_empty()
		var searching:=phase=="search" and unlocked and joined
		var why:=""
		if not unlocked:why="海灘尋寶尚未解鎖。"
		elif phase=="idle":why="還沒有開始。到告示牌開始尋寶後，這裡才能使用。"
		elif phase=="results":why="這一輪已結束，這裡不能再標記或挖掘。"
		elif not joined:why="你還沒加入這一輪，先回告示牌加入。"
		elif near==false:why="走到這個地點旁邊才能操作（目前太遠）。"
		elif busy:why="上一個請求還在等待回應。"
		elif not _online():why="與世界的連線已中斷。"
		var can_mark:=searching and not marked and not found and not dug
		var can_dig:=searching and not found and not dug
		if why.is_empty():
			if found:why="這個地點已經被挖到了，看看其他地點。"
			elif dug:why="隊伍已挖過這裡，可以查看新線索。"
			elif marked:why="這裡已有共享標記；對照線索後可以挖掘。"
			else:why="對照線索：可先標記讓同伴看到，或直接挖掘。"
			(refs.reason as Label).add_theme_color_override("font_color",MUTED)
		else:
			(refs.reason as Label).add_theme_color_override("font_color",WARN)
		var blocked:=not (searching and near!=false and not busy and _online())
		_set_action(refs.mark,true,can_mark and not blocked)
		_set_action(refs.dig,true,can_dig and not blocked)
		(refs.reason as Label).text=why
		var lines:=PackedStringArray()
		lines.append("地點：%s（%s）"%[str(info.title),spot.to_upper()])
		lines.append("共享標記：%s"%("已標記" if marked else "尚未標記"))
		lines.append("挖掘：%s"%("這裡已被挖到" if found else ("隊伍挖過了" if dug else "還沒有人挖到")))
		(refs.station_text as Label).text="\n".join(lines)

	func _set_action(button:Button,shown:bool,allowed:bool)->void:
		button.set_meta("shown",shown)
		button.set_meta("allowed",allowed)

	func _usable(button)->bool:
		return button is Button and is_instance_valid(button) and button.visible and not button.disabled

	func _sync()->void:
		var focused:=get_viewport().gui_get_focus_owner()
		var had_focus:=focused is Button and focused in actions
		for button in actions:
			if button is Button and is_instance_valid(button):
				button.visible=bool(button.get_meta("shown",true))
				button.disabled=not bool(button.get_meta("allowed",false))
		if had_focus and not _usable(focused):
			for button in actions:
				if _usable(button):
					button.grab_focus()
					break

	func _online()->bool:
		if app.session.world!=null:return true
		var peer=app.session.multiplayer.multiplayer_peer
		return peer!=null and peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED

	# ---------------------------------------------------------------- requests

	func _round()->int:
		return int(Query.game(app.session.snapshot).get("round",0))

	func _start()->void:
		submit("start",Rules.sign_cell(),"開始尋寶")

	func _join()->void:
		submit("join:%d"%_round(),Rules.sign_cell(),"加入")

	func _leave()->void:
		submit("leave:%d"%_round(),Rules.sign_cell(),"離開")

	func _mark()->void:
		var info:=Rules.spot(spot)
		if info.is_empty():return
		submit("mark:%d"%_round(),info.cell,"標記")

	func _dig()->void:
		var info:=Rules.spot(spot)
		if info.is_empty():return
		submit("dig:%d"%_round(),info.cell,"挖掘")

	## One explicit intent, never retried. With correlated acknowledgements the
	## buttons stay locked until the matching (sequence, action) completion; on
	## a client without them a short quiet period prevents double-sends.
	func submit(payload:String,cell:Vector2i,intent:String)->void:
		if not pending.is_empty():
			_status("上一個請求還在等待回應，請稍候。",false)
			return
		var session=app.session
		var action:=Rules.action()
		if session.world==null and not _online():
			_status("與世界的連線已中斷，這次沒有送出。",false)
			return
		var correlated:bool=action in _correlated(session)
		pending={"action":action,"sequence":int(session.counter)+1,"at":Time.get_ticks_msec(),"correlated":correlated,"host":session.world!=null}
		_status(intent+"……已送出",true)
		refresh()
		var sequence:int=session.perform(action,cell,payload)
		if pending.is_empty():return # Answered synchronously.
		if sequence<=0:
			pending={}
			_status("世界正在關閉，這次沒有送出。",false)
			refresh()
			return
		pending.sequence=sequence
		if bool(pending.host):
			pending={}
			refresh()

	func _correlated(session)->Array:
		var helper=session.get_script()
		if helper is Script:
			var found=helper.get_script_constant_map().get("CORRELATED_ACTIONS",[])
			if found is Array:return found
		return []

	func _on_completed(sequence:int,action:String,result:Dictionary)->void:
		if pending.is_empty() or sequence!=int(pending.get("sequence",-1)) or action!=str(pending.action):return
		pending={}
		if bool(result.get("ok",false)):_status(str(result.get("message","已完成。")),true)
		else:_status("沒有變更："+str(result.get("message","")),false)
		refresh()

	func _status(message:String,success:bool)->void:
		var label:Label=refs.get("status")
		if label==null:return
		label.text=message
		label.add_theme_color_override("font_color",GOOD if success else WARN)


## Card style lives outside the Controller so inner classes can share it.
class BeachTreasureStyle:
	static func card()->StyleBoxFlat:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("f4e8c4")
		style.border_color=SAND_DARK
		style.set_border_width_all(2)
		style.anti_aliasing=false
		for side in [SIDE_LEFT,SIDE_RIGHT]:style.set_content_margin(side,8)
		for side in [SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(side,6)
		return style
