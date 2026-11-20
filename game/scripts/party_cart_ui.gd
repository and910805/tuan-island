extends RefCounted
## P06 礦車搬運 client: one compact panel (open(app,point)). Rules live in party_cart.gd; this file
## only reads snapshot.party_cart / snapshot.own_party_cart and sends every action through
## session.perform(ACTION, cell, payload):
##   sign: "start" | "join:<round>" | "leave:<round>"
##   cart/dock: "push:<round>", "unload:<round>"   junction: "switch:<round>" (+ push)
##   rocks: "clear:<round>:north|south"
## Widgets rebuild only when phase, round, point, membership, cart stop/target, branch or rocks
## change. Delivered count, score, players, timer (<=10s only) and the schematic update in place,
## so the changing departed/arrives/remaining timestamps never rebuild the panel.
const Rules=preload("res://scripts/party_cart.gd")
const HarvestUI=preload("res://scripts/harvest_relay_ui.gd")
const CookUI=preload("res://scripts/cooking_relay_ui.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const LAYOUT:="party_cart"
const ACTION:="party_cart"
const TITLE:="礦車搬運"
const POINTS:=["sign","cart","junction","north","south"]
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const LAST_SECONDS:=10.0
const MAP_SIZE:=Vector2(236,104)
const BOXES:=Rules.CRATES

# ------------------------------------------------------------------ state --

static func public_view(s:Dictionary)->Dictionary:
	var found:Variant=s.get("party_cart",{})
	return found if found is Dictionary else {}

static func own(s:Dictionary)->Dictionary:
	var found:Variant=s.get("own_party_cart",{})
	return found if found is Dictionary else {}

static func phase_of(p:Dictionary)->String:
	var phase:=str(p.get("phase","idle"))
	return phase if phase in ["idle","run","results"] else "idle"

static func stop_of(p:Dictionary)->int:
	return clampi(int(p.get("stop",0)),0,Rules.STOPS.size()-1)

static func moving(p:Dictionary)->bool:
	return int(p.get("to",-1))>=0

static func branch_of(p:Dictionary)->String:
	return "south" if str(p.get("branch","north"))=="south" else "north"

static func rocks_of(p:Dictionary)->Dictionary:
	var r:Variant=p.get("rocks",{})
	var d:Dictionary=r if r is Dictionary else {}
	return {"north":bool(d.get("north",false)),"south":bool(d.get("south",false))}

static func branch_name(b:String)->String:
	return "南線" if b=="south" else "北線"

static func total_of(p:Dictionary)->int:
	var t:=int(p.get("total",BOXES))
	return t if t>0 else BOXES

static func time_text(p:Dictionary)->String:
	if phase_of(p)!="run":return ""
	var left:=float(p.get("remaining",0.0))
	if left>LAST_SECONDS:return ""
	return "剩 %d 秒"%HarvestUI.whole_seconds(left)

static func progress_text(p:Dictionary)->String:
	return "已送達 %d / %d 箱・%d 分"%[int(p.get("delivered",0)),total_of(p),int(p.get("score",0))]

static func players_text(p:Dictionary)->String:
	return "%d 人一起推車"%int(p.get("players",0))

static func phase_text(p:Dictionary,m:Dictionary)->String:
	var r:=int(p.get("round",0))
	match phase_of(p):
		"run":return ("進行中・第 %d 輪" if bool(m.get("joined",false)) else "旁觀中・第 %d 輪")%r
		"results":return "第 %d 輪結算"%r
	return "目前沒有進行中的一輪"

static func cart_text(p:Dictionary)->String:
	if phase_of(p)=="idle":return "礦車停在起點"
	if moving(p):return "礦車行駛中，往第 %d 站"%(int(p.get("to",0))+1)
	var st:=stop_of(p)
	if st==Rules.DOCK:return "礦車到卸貨站了"
	if st==Rules.JUNCTION:return "礦車停在岔路口"
	return "礦車停在第 %d 站"%(st+1)

static func route_text(p:Dictionary)->String:
	var rocks:=rocks_of(p)
	var b:=branch_of(p)
	var t:="道岔：%s"%branch_name(b)
	var blocked:Array[String]=[]
	if rocks["north"]:blocked.append("北線")
	if rocks["south"]:blocked.append("南線")
	t+="　"+("落石：%s"%"、".join(blocked) if not blocked.is_empty() else "軌道暢通")
	if rocks[b]:t+="（目前線路被擋）"
	return t

## Prompt lines depend on the situation, so the three hints are always the next useful steps.
static func prompts(p:Dictionary)->Array[String]:
	var out:Array[String]=[]
	var phase:=phase_of(p)
	if phase!="run":
		out.append("1　在坑道告示牌開始")
		out.append("2　推車到岔路，選擇一條路線")
		out.append("3　送到卸貨站，每箱都算分")
		return out
	var rocks:=rocks_of(p)
	var b:=branch_of(p)
	out.append("1　%s"%("到礦車旁，按一下推車" if not moving(p) else "車在滑行，可以先清路"))
	if rocks[b]:out.append("2　%s被石頭擋住，先清掉或改道"%branch_name(b))
	elif rocks["north" if b=="south" else "south"]:out.append("2　另一線有落石，維持%s"%branch_name(b))
	else:out.append("2　到岔路口扳道岔，選暢通的線")
	out.append("3　抵達卸貨站後按卸貨")
	return out

static func cell_for(p:Dictionary,point:String)->Vector2i:
	match point:
		"cart":return Rules.STOPS[stop_of(p)]
		"junction":return Rules.STOPS[Rules.JUNCTION]
		"north":return Rules.ROCKS["north"]
		"south":return Rules.ROCKS["south"]
	return Rules.SIGN

static func point_of(app)->String:
	var v:Variant=app.modal.get_meta("partycart_point","sign") if is_instance_valid(app.modal) else "sign"
	return str(v) if str(v) in POINTS else "sign"

# ---------------------------------------------------------------- panel --

static func open(app,point:String="sign")->void:
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.name="PartyCartPanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("partycart_body",body)
	app.modal.set_meta("partycart_point",point if point in POINTS else "sign")
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
	modal.size.x=minf(520.0,bounds.x-32.0)
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var body:=modal.find_child("ModalContent",true,false) as Control
	var height:=400.0
	if outer and body:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=chrome+body.get_combined_minimum_size().y+2.0
	modal.size.y=minf(height,bounds.y-24.0)
	modal.position=((bounds-modal.size)/2.0).floor()

static func is_open(app)->bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("partycart_body")

static func focus_first(app)->void:
	if not is_open(app):return
	var body:Control=app.modal.get_meta("partycart_body")
	for node in body.find_children("*","BaseButton",true,false):
		var b:=node as BaseButton
		if b.is_visible_in_tree() and not b.disabled and b.focus_mode!=Control.FOCUS_NONE:
			b.grab_focus()
			return
	var close:=_close_button(app)
	if close!=null:close.grab_focus()

static func _close_button(app)->BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("partycart_body") if app.modal.has_meta("partycart_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func refresh(app)->void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var p:=public_view(s)
	var m:=own(s)
	var point:=point_of(app)
	var body:VBoxContainer=app.modal.get_meta("partycart_body")
	_update_footer(app)
	var signature:=JSON.stringify([phase_of(p),int(p.get("round",0)),point,bool(m.get("joined",false)),stop_of(p),int(p.get("to",-1)),branch_of(p),rocks_of(p)])
	if str(app.modal.get_meta("partycart_signature",""))==signature:
		_update_live(body,p)
		return
	app.modal.set_meta("partycart_signature",signature)
	var focused:Control=body.get_viewport().gui_get_focus_owner() if body.is_inside_tree() else null
	var focus_name:String=str(focused.name) if is_instance_valid(focused) and body.is_ancestor_of(focused) else ""
	for child in body.get_children():body.remove_child(child);child.queue_free()
	build(app,body,p,m,point)
	_update_live(body,p)
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
static func _update_live(body:Control,p:Dictionary)->void:
	var progress:=body.find_child("PartyCartProgress",true,false) as Label
	if progress:progress.text=progress_text(p)+"・"+players_text(p)
	var timer:=body.find_child("PartyCartTime",true,false) as Label
	if timer:timer.text=time_text(p)
	var map:=body.find_child("PartyCartMap",true,false) as Control
	if map:
		var key:=JSON.stringify([phase_of(p),stop_of(p),int(p.get("to",-1)),branch_of(p),rocks_of(p),int(p.get("delivered",0))])
		if str(map.get_meta("map_key",""))!=key:
			map.set_meta("map_key",key)
			map.set_meta("stop",stop_of(p))
			map.set_meta("moving",moving(p))
			map.set_meta("to",int(p.get("to",-1)))
			map.set_meta("branch",branch_of(p))
			map.set_meta("rocks",rocks_of(p))
			map.set_meta("active",phase_of(p)=="run")
			map.queue_redraw()

# ---------------------------------------------------------------- build --

static func build(app,body:VBoxContainer,p:Dictionary,m:Dictionary,point:String)->void:
	var phase:=phase_of(p)
	var rid:=str(int(p.get("round",0)))
	var joined:=bool(m.get("joined",false))
	var running:=phase=="run"
	var head:=HBoxContainer.new();head.name="PartyCartHeader";head.add_theme_constant_override("separation",12);body.add_child(head)
	var status:=HarvestUI.text(app,head,phase_text(p,m),16,WARN);status.name="PartyCartPhase"
	status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	HarvestUI.text(app,head,"",16,WARN).name="PartyCartTime"
	if phase!="idle":HarvestUI.text(app,body,"",15,GOOD).name="PartyCartProgress"
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);body.add_child(row)
	var left:=VBoxContainer.new();left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;left.custom_minimum_size.x=190;row.add_child(left)
	if phase=="results":
		HarvestUI.wrapped(app,left,"本輪送達 %d / %d 箱，得 %d 分。"%[int(p.get("delivered",0)),total_of(p),int(p.get("score",0))],16,GOOD)
	else:
		for line in prompts(p):HarvestUI.wrapped(app,left,line,15,INK)
	row.add_child(make_map())
	if phase!="idle":
		HarvestUI.wrapped(app,body,cart_text(p),14,INK).name="PartyCartCart"
		HarvestUI.wrapped(app,body,route_text(p),14,WARN if rocks_of(p)[branch_of(p)] else MUTED).name="PartyCartRoute"
	else:
		HarvestUI.wrapped(app,body,"送達一箱得 2 分。",13,MUTED)
	var bar:=HBoxContainer.new();bar.name="PartyCartActions";bar.add_theme_constant_override("separation",10);body.add_child(bar)
	var cell:=cell_for(p,point)
	var buttons:Array[Button]=[]
	var visitor:Dictionary=app.session.snapshot.get("players",{}).get(app.session.own_id,{})
	var close:=not visitor.is_empty() and Vector2(visitor.x,visitor.y).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=Rules.REACH
	var at_cart:=running and joined and not moving(p) and close
	match point:
		"sign":
			var can_start:=not running
			buttons.append(_btn(app,bar,"PartyCartStart","開始搬運",func():app.session.perform(ACTION,cell,"start"),can_start and close,"到坑道告示牌開始。"))
			var can_join:=running and not joined
			buttons.append(_btn(app,bar,"PartyCartJoin","加入",func():app.session.perform(ACTION,cell,"join:"+rid),can_join and close,"到坑道告示牌加入。"))
			buttons.append(_btn(app,bar,"PartyCartLeave","離開",func():app.session.perform(ACTION,cell,"leave:"+rid),joined,"你還沒加入。"))
			buttons[0].visible=can_start
			buttons[1].visible=can_join
			buttons[2].visible=joined
		"cart":
			var here:=stop_of(p)
			if here==Rules.DOCK:
				buttons.append(_btn(app,bar,"PartyCartUnload","卸貨",func():app.session.perform(ACTION,cell,"unload:"+rid),at_cart,_why(running,joined,moving(p),"靠近卸貨台。")))
			else:
				buttons.append(_btn(app,bar,"PartyCartPush","推車",func():app.session.perform(ACTION,cell,"push:"+rid),at_cart,_why(running,joined,moving(p),"靠近礦車。")))
		"junction":
			var there:=at_cart and stop_of(p)==Rules.JUNCTION
			var why:=_why(running,joined,moving(p),"礦車還沒到岔路口。" if stop_of(p)!=Rules.JUNCTION else "")
			var target:="切到南線" if branch_of(p)=="north" else "切到北線"
			buttons.append(_btn(app,bar,"PartyCartSwitch",target,func():app.session.perform(ACTION,cell,"switch:"+rid),there,why))
			var blocked:bool=rocks_of(p)[branch_of(p)]
			buttons.append(_btn(app,bar,"PartyCartPush","推車",func():app.session.perform(ACTION,cell,"push:"+rid),there and not blocked,"先清除目前路線的落石。" if blocked else why))
		"north","south":
			var blocked:bool=rocks_of(p)[point]
			var tag:=point
			var why:="這裡沒有落石。" if not blocked else _why(running,joined,false,"")
			buttons.append(_btn(app,bar,"PartyCartClear","清除%s落石"%branch_name(point),func():app.session.perform(ACTION,cell,"clear:%s:%s"%[rid,tag]),running and joined and blocked and close,why))
	for b in buttons:b.custom_minimum_size.x=108
	CookUI.link_focus(app,buttons)

static func _btn(app,bar:Control,id:String,title:String,cb:Callable,enabled:bool,reason:String)->Button:
	return HarvestUI.action(app,bar,id,title,cb,enabled,reason)

static func _why(running:bool,joined:bool,is_moving:bool,extra:String)->String:
	if not running:return "現在沒有進行中的一輪。"
	if not joined:return "先到告示牌加入。"
	if is_moving:return "礦車行駛中。"
	return extra

## Draw-only route schematic: content comes from meta, so it is redrawn but never rebuilt.
static func make_map()->Control:
	var map:=Control.new()
	map.name="PartyCartMap"
	map.custom_minimum_size=MAP_SIZE
	map.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	map.set_meta("stop",0)
	map.set_meta("branch","north")
	map.set_meta("rocks",{"north":false,"south":false})
	map.draw.connect(func():draw_map(map))
	return map

static func _node_pos(map:Control,idx:int)->Vector2:
	var lo:=Vector2(1e9,1e9)
	var hi:=Vector2(-1e9,-1e9)
	for c in Rules.STOPS:
		lo=Vector2(minf(lo.x,c.x),minf(lo.y,c.y))
		hi=Vector2(maxf(hi.x,c.x),maxf(hi.y,c.y))
	var pad:=Vector2(22,20)
	var span:=hi-lo
	var c:Vector2i=Rules.STOPS[idx]
	var u:=Vector2((c.x-lo.x)/maxf(span.x,1.0),(c.y-lo.y)/maxf(span.y,1.0))
	return pad+u*(map.size-pad*2.0)

static func draw_map(map:Control)->void:
	var font:=ThemeDB.fallback_font
	var rocks:Dictionary=map.get_meta("rocks",{})
	var branch:String=map.get_meta("branch","north")
	var stops:Array=Rules.STOPS
	var pos:Array[Vector2]=[]
	for i in stops.size():pos.append(_node_pos(map,i))
	map.draw_rect(Rect2(Vector2.ZERO,map.size),Color("e9e2c8"))
	map.draw_rect(Rect2(Vector2.ZERO,map.size),INK,false,2.0)
	# track segments: trunk, north loop (1-2-4), south loop (1-3-4), exit (4-5)
	var segs:=[[0,1,""],[1,2,"north"],[2,4,"north"],[1,3,"south"],[3,4,"south"],[4,5,""]]
	for s in segs:
		var side:String=s[2]
		var live:=side=="" or side==branch
		var col:=INK if live else MUTED
		map.draw_line(pos[s[0]],pos[s[1]],col,4.0 if live else 2.0)
	# rocks sit on the branch (square + ✕ so it reads without colour)
	for side in ["north","south"]:
		if not bool(rocks.get(side,false)):continue
		var at:=(pos[2] if side=="north" else pos[3]).lerp(pos[Rules.JUNCTION],0.5)
		map.draw_rect(Rect2(at-Vector2(8,8),Vector2(16,16)),Color("8a7a66"))
		map.draw_rect(Rect2(at-Vector2(8,8),Vector2(16,16)),WARN,false,2.0)
		map.draw_string(font,at+Vector2(-5,5),"✕",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("fff7db"))
	for i in stops.size():
		var r:=7.0 if i==Rules.JUNCTION or i==Rules.DOCK else 4.5
		map.draw_circle(pos[i],r,Color("fff3d6"))
		map.draw_arc(pos[i],r,0,TAU,16,INK,2.0)
	map.draw_string(font,pos[Rules.JUNCTION]+Vector2(-8,-12),"岔",HORIZONTAL_ALIGNMENT_LEFT,-1,12,INK)
	map.draw_string(font,pos[Rules.DOCK]+Vector2(-8,-12),"卸",HORIZONTAL_ALIGNMENT_LEFT,-1,12,INK)
	map.draw_string(font,pos[2]+Vector2(-6,-8),"北",HORIZONTAL_ALIGNMENT_LEFT,-1,12,GOOD if branch=="north" else MUTED)
	map.draw_string(font,pos[3]+Vector2(-6,16),"南",HORIZONTAL_ALIGNMENT_LEFT,-1,12,GOOD if branch=="south" else MUTED)
	# cart: filled square; between stops it is drawn halfway along the segment
	var st:int=clampi(int(map.get_meta("stop",0)),0,stops.size()-1)
	var at_cart:=pos[st]
	if bool(map.get_meta("moving",false)):
		var to:int=clampi(int(map.get_meta("to",st)),0,stops.size()-1)
		at_cart=pos[st].lerp(pos[to],0.5)
	map.draw_rect(Rect2(at_cart-Vector2(8,6),Vector2(16,12)),Color("286590"))
	map.draw_rect(Rect2(at_cart-Vector2(8,6),Vector2(16,12)),Color("fff7db"),false,2.0)
