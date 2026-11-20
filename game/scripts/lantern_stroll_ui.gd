extends RefCounted

const Rules=preload("res://scripts/lantern_stroll.gd")
const UI=preload("res://scripts/harvest_relay_ui.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Lamp=preload("res://assets/ui-life/paper-tea-lamp.png")
const LAYOUT:="lantern_stroll"
const INK:=Color("4b4231")
const GREEN:=Color("3a6949")
const WARM:=Color("895337")

static func open(app,site:="sign") -> void:
	var title:String="燈籠散步" if site=="sign" else Rules.SITES[site].name
	var contents:VBoxContainer=app._open_modal(title)
	app.modal.name="LanternStrollPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("stroll_contents",contents)
	app.modal.set_meta("stroll_site",site)
	if app.village_art_preview:
		app.modal.theme=Pixel.make(app.hud.theme)
		app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.25
	refresh(app)
	app._layout_preview.call_deferred()

static func layout(app,bounds:Vector2) -> void:
	var panel:Control=app.modal
	panel.size.x=minf(635.0,bounds.x-28.0)
	var scroll:=panel.find_child("ModalScroll",true,false) as Control
	var content:Control=panel.get_meta("stroll_contents")
	var chrome:float=panel.get_combined_minimum_size().y-scroll.get_combined_minimum_size().y if scroll else 126.0
	panel.size.y=minf(chrome+content.get_combined_minimum_size().y+8.0,bounds.y-24.0)
	panel.position=((bounds-panel.size)/2.0).floor()

static func refresh(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("stroll_contents"):return
	var snapshot:Dictionary=app.session.snapshot
	var public:Dictionary=snapshot.get(Rules.KEY,{})
	var own:Dictionary=snapshot.get(Rules.VIEW_KEY,{})
	var body:VBoxContainer=app.modal.get_meta("stroll_contents")
	var site:String=app.modal.get_meta("stroll_site")
	var player:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var here:Vector2i=Rules.SIGN if site=="sign" else Rules.SITES[site].cell
	var close:=not player.is_empty() and Rules.near(player,here)
	var signature:=str([public.get("phase"),public.get("round"),public.get("blessings"),public.get("count"),own,app.view.stroll_dim,close])
	if signature!=app.modal.get_meta("stroll_signature",""):
		app.modal.set_meta("stroll_signature",signature)
		var focus:Control=body.get_viewport().gui_get_focus_owner()
		var name_to_keep:=str(focus.name) if is_instance_valid(focus) and body.is_ancestor_of(focus) else ""
		for child:Node in body.get_children():
			body.remove_child(child)
			child.queue_free()
		build(app,body,public,own,site,close)
		var target:=body.find_child(name_to_keep,true,false) as BaseButton if not name_to_keep.is_empty() else null
		if target==null or target.disabled:
			for node in body.find_children("*","Button",true,false):
				if not node.disabled:
					target=node
					break
		if target and not target.disabled:target.grab_focus.call_deferred()
		app._layout_preview.call_deferred()
	var map:=body.find_child("StrollMap",true,false) as Control
	if map:
		var current:=Vector2i(Vector2(player.x,player.y).floor()) if not player.is_empty() else Vector2i(-10,-10)
		if map.get_meta("player_cell",Vector2i(-10,-10))!=current:
			map.set_meta("player_cell",current)
			map.queue_redraw()
	var time:=body.find_child("StrollTime",true,false) as Label
	var remaining:=int(public.get("remaining",0))
	if time:time.text="本輪剩 %d 秒"%remaining if public.get("phase")=="run" and remaining<=10 else ""

static func _send(app,id:String,cell:Vector2i,payload:String,bar:Control,title:String,allowed:=true,reason:="") -> void:
	UI.action(app,bar,id,title,func():app.session.perform(Rules.ACTION,cell,payload),allowed,reason)

static func build(app,body:VBoxContainer,public:Dictionary,own:Dictionary,site:String,close:bool) -> void:
	var phase:String=public.get("phase","idle")
	var rid:=str(int(public.get("round",0)))
	var stamps:Dictionary=own.get("stamps",{})
	var tickets:=int(own.get("tickets",0))
	var joined:bool=own.get("joined",false)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	body.add_child(row)
	var text:=VBoxContainer.new()
	text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	text.custom_minimum_size.x=190
	text.add_theme_constant_override("separation",5)
	row.add_child(text)
	UI.wrapped(app,text,"路線印章  %d／3  ·  裝飾票 %d"%[stamps.size(),tickets],17,GREEN)
	UI.text(app,text,"",14,WARM).name="StrollTime"
	for id:String in Rules.ORDER:
		var label:String=("✓  " if stamps.has(id) else "○  ")+str(Rules.SITES[id].name)
		UI.wrapped(app,text,label,15,GREEN if stamps.has(id) else INK)
	var map:=Control.new()
	map.name="StrollMap"
	map.custom_minimum_size=Vector2(276,122)
	map.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	map.draw.connect(func():draw_map(map,stamps,public.get("route",[])))
	row.add_child(map)
	var cell:Vector2i=Rules.SIGN if site=="sign" else Rules.SITES[site].cell
	if site!="sign":
		if stamps.has(site):
			UI.wrapped(app,body,"這一站的印章已收好。 "+str(Rules.WISHES[stamps[site]]),15,GREEN)
		elif joined:
			UI.wrapped(app,body,"選一句祝福，蓋上這站的印章。",15,INK)
			for wish:String in Rules.WISHES:
				_send(app,"StrollWish_"+wish,cell,"stamp:%s:%s:%s"%[rid,site,wish],body,Rules.WISHES[wish],close)
		else:
			var last:String=public.get("blessings",{}).get(site,"")
			if not last.is_empty():UI.wrapped(app,body,Rules.WISHES[last],15,GREEN)
			if phase=="run":_send(app,"StrollJoin",cell,"join:"+rid,body,"加入散步",close)
		return
	var line:="借一盞燈籠，到三個景點各留一句祝福。" if phase!="results" else "這一輪散步已結束。裝飾票可留到下次用。"
	UI.wrapped(app,body,line,15,INK)
	var actions:=HBoxContainer.new()
	actions.add_theme_constant_override("separation",7)
	body.add_child(actions)
	if phase!="run":_send(app,"StrollStart",cell,"start",actions,"開始散步",close,"請靠近散步告示牌。")
	elif not joined:_send(app,"StrollJoin",cell,"join:"+rid,actions,"加入散步",close,"請靠近散步告示牌。")
	else:
		_send(app,"StrollLeave",cell,"leave:"+rid,actions,"歸還燈籠")
		if int(public.get("count",0))==1:
			_send(app,"StrollCompanion",cell,"companion:"+rid,actions,"跟阿燈道別" if own.get("companion",false) else "邀阿燈同行")
	if tickets>0:_send(app,"StrollRedeem",cell,"redeem",actions,"換紙燈籠柱",close,"請靠近散步告示牌。")
	UI.action(app,actions,"StrollDim","恢復暖光" if app.view.stroll_dim else "調弱燈光",func():app._set_stroll_dim(not app.view.stroll_dim),true)

static func draw_map(map:Control,stamps:Dictionary,path_cells:Array) -> void:
	var area:=Rect2(Vector2.ZERO,map.size)
	map.draw_rect(area,Color("e5ead0"))
	map.draw_rect(area.grow(-1),Color("9d8254"),false,1.0)
	var cells:Array[Vector2i]=[Rules.SIGN]
	for id:String in Rules.ORDER:cells.append(Rules.SITES[id].cell)
	var path:Array[Vector2i]=[]
	for raw:String in path_cells:
		var parts:=raw.split(",")
		path.append(Vector2i(int(parts[0]),int(parts[1])))
	var top_left:=cells[0]
	var bottom_right:=cells[0]
	for cell:Vector2i in cells+path:
		top_left=top_left.min(cell)
		bottom_right=bottom_right.max(cell)
	var span:=Vector2(bottom_right-top_left).max(Vector2.ONE)
	var scale:Vector2=(map.size-Vector2(38,36))/span
	var coords:=func(cell:Vector2i)->Vector2:
		return Vector2(19,18)+Vector2(cell-top_left)*scale
	var gate:Vector2=coords.call(Rules.SIGN)
	if not path.is_empty():
		var lines:=PackedVector2Array()
		for cell:Vector2i in path:lines.append(coords.call(cell))
		map.draw_polyline(lines,Color("a67d4e"),3.0,false)
	map.draw_texture_rect(Lamp,Rect2(gate-Vector2(7,11),Vector2(14,18)),false)
	var font:=ThemeDB.fallback_font
	for index in Rules.ORDER.size():
		var site:String=Rules.ORDER[index]
		var pos:Vector2=coords.call(cells[index+1])
		map.draw_circle(pos,10.0,GREEN if stamps.has(site) else WARM)
		map.draw_circle(pos,8.0,Color("fff0c2") if not stamps.has(site) else Color("dcecd1"))
		map.draw_string(font,pos+Vector2(-4,5),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,13,INK)
	var actual:Vector2i=map.get_meta("player_cell",Vector2i(-10,-10))
	var dot:Vector2=coords.call(actual)+Vector2(9,7)
	if area.grow(-6).has_point(dot):
		map.draw_circle(dot,5.0,Color("fff7e3"))
		map.draw_circle(dot,3.0,Color("325c88"))
