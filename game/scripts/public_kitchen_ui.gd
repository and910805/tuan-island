extends RefCounted
## 渡口公共廚房（section 18 Q04 / T042）— 兩頁式社區食譜與故事剪貼簿。
##
## Display + intent only. Everything shown is derived from Session.snapshot and
## every change goes through Session.perform; this script never writes snapshot,
## World, inventory or save data. World stays the only authority (ownership,
## region, reach, path, busy stove, distinct seats, range).
##
## Wire intents (docs/public-kitchen-contract.json):
## - kitchen_register   p=chosen stove, extra="x,y|x,y" (two unique seat cells,
##                      string-sorted, joined by "|"). Sent only from the explicit
##                      KitchenRegister button after the permanent-donation box is
##                      ticked. Nothing is ever chosen or submitted automatically.
## - kitchen_contribute p=registered stove, extra="".
## The public cooker button opens the existing app._cook_menu(stove) workbench.
##
## Acknowledgement: Session.action_completed matched on sequence AND action. While
## a request is pending the selections are frozen and every action is disabled.
## Never retried automatically. Unsupported actions are refused before sending;
## a remote timeout reports an unknown outcome instead of inferring success
## from a snapshot change caused by another member.
##
## Snapshot query API (pure, read-only; used when the core helper is absent or
## takes a World rather than a state Dictionary):
##   Query.candidate_stoves(snapshot, own_id) -> Array[String]
##   Query.candidate_seats(snapshot, own_id, stove:Vector2i) -> Array[String]
##   Query.events(snapshot) -> Array[{id,title,lines:Array[{npc,text}]}]
## When res://scripts/public_kitchen.gd exists and its function's first argument
## is a state Dictionary (named state/snapshot or typed Dictionary), its result is
## used instead. The pure query mirrors the contract on public data only (owner
## hashes in the snapshot equal Session.own_id); the World re-validates.

const World=preload("res://scripts/world.gd")
const Village=World.Village
const Items=preload("res://scripts/inventory_item_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Art=preload("res://scripts/life_ui_theme.gd")
const Folio=preload("res://scripts/kitchen_folio_art.gd")
const LAYOUT:="public_kitchen"
const META:="public_kitchen"
const FURNITURE:="res://assets/ui-life/furniture.png"
const STOVE_REGION:=Rect2(0,96,32,48)
const BENCH_REGION:=Rect2(32,0,32,48)
const TABLE_REGION:=Rect2(64,48,32,48)
const INK:=Color("3d422d")
const MUTED:=Color("76694c")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")

## Entry point: community table '公共廚房' (page "kitchen") and journal '共餐記憶'
## (page "story"). Both pages are always visible; `page` picks initial focus.
static func open(app,page:String="kitchen")->void:
	var body:VBoxContainer=app._open_modal("渡口公共廚房・共餐剪貼簿")
	var modal:Control=app.modal
	modal.name="PublicKitchenUI"
	modal.set_meta("life_modal_layout",LAYOUT)
	modal.theme=_theme(app.hud.theme)
	modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",4)
	var outer:=body.get_parent() as ScrollContainer
	if outer:
		outer.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		_compact_shell(outer.get_parent() as VBoxContainer)
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.3
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.hide()
	var controller:=Controller.new()
	controller.name="KitchenController"
	controller.app=app
	controller.start_page=page
	modal.set_meta(META,controller)
	modal.add_child(controller)
	controller.build(body)
	controller.refresh()
	controller.fit_now()
	controller.focus_start.call_deferred()

static func refresh(app)->void:
	var controller:=_controller(app)
	if controller:controller.refresh()

static func focus_kitchen_action(app)->bool:
	var controller:=_controller(app)
	if controller==null:return false
	for key in ["contribute","cook"]:
		var action:=controller.refs.get(key) as Button
		if is_instance_valid(action) and action.is_visible_in_tree() and not action.disabled:
			action.grab_focus()
			break
	return true

static func layout(app,_bounds:Vector2)->void:
	var controller:=_controller(app)
	if controller:controller.fit_now()

static func _controller(app)->Controller:
	if not is_instance_valid(app.modal) or str(app.modal.get_meta("life_modal_layout",""))!=LAYOUT:return null
	var found=app.modal.get_meta(META,null)
	if not is_instance_valid(found) or not found is Controller:return null
	return found

## Tighten the generic modal chrome (only inside this modal): smaller cookbook
## title with the stove art, no rule lines, less vertical padding. The close
## button and Esc handling stay owned by main.gd.
static func _compact_shell(shell:VBoxContainer)->void:
	if shell==null:return
	shell.add_theme_constant_override("separation",4)
	for child in shell.get_children():
		if child is HSeparator:child.hide()
	if shell.get_child_count()==0:return
	var heading:=shell.get_child(0) as HBoxContainer
	if heading==null:return
	heading.add_theme_constant_override("separation",8)
	for child in heading.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size",22)
			child.add_theme_color_override("font_color",INK)
			child.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			child.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var mark:=TextureRect.new()
	mark.name="KitchenTitleMark"
	mark.texture=stove_icon()
	mark.custom_minimum_size=Vector2(28,40)
	mark.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mark.mouse_filter=Control.MOUSE_FILTER_IGNORE
	heading.add_child(mark)
	heading.move_child(mark,0)

static func stove_icon()->Texture2D:
	return Art.atlas_region(FURNITURE,STOVE_REGION)

static func bench_icon()->Texture2D:
	return Art.atlas_region(FURNITURE,BENCH_REGION)

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


## Pure snapshot queries. Never mutate the snapshot passed in.
class Query:
	const CORE_PATH:="res://scripts/public_kitchen.gd"
	const MEALS:=["soup","bread","salad"]
	const NEEDS:={"soup":4,"bread":2,"salad":2}
	const STOVE_RANGE:=8.0
	const SEAT_RANGE:=3.0
	const REACH:=3.2
	const SEARCH:=16
	const NO_CELL:=Vector2i(-1,-1)

	static func core():
		if not ResourceLoader.exists(CORE_PATH):return null
		return load(CORE_PATH)

	## True when the core helper's `method` takes a state Dictionary first.
	static func core_takes_state(helper,method:String)->bool:
		if helper==null or not helper is Script:return false
		for entry in helper.get_script_method_list():
			if str(entry.get("name",""))!=method:continue
			var args:Array=entry.get("args",[])
			if args.is_empty():return false
			var first:Dictionary=args[0]
			return str(first.get("name","")) in ["state","snapshot"] or int(first.get("type",TYPE_NIL))==TYPE_DICTIONARY
		return false

	static func needs()->Dictionary:
		var helper=core()
		if helper is Script:
			var found=helper.get_script_constant_map().get("REQUIREMENTS")
			if found is Dictionary:
				var out:={}
				for meal in MEALS:out[meal]=maxi(0,int(found.get(meal,NEEDS[meal])))
				return out
		return NEEDS.duplicate()

	static func kitchen(s:Dictionary)->Dictionary:
		var data=s.get("public_kitchen")
		var out:={"stove":"","seats":[],"meals":{"soup":0,"bread":0,"salad":0},"opened":false}
		if not data is Dictionary:return out
		out.stove=str(data.get("stove",""))
		var seats=data.get("seats",[])
		if seats is Array:
			for seat in seats:out.seats.append(str(seat))
		var meals=data.get("meals",{})
		if meals is Dictionary:
			for meal in MEALS:out.meals[meal]=maxi(0,int(meals.get(meal,0)))
		out.opened=bool(data.get("opened",false))
		return out

	static func registered(k:Dictionary)->bool:
		return parse(str(k.stove))!=null and (k.seats as Array).size()==2

	static func home(s:Dictionary)->bool:
		return str(s.get("region_id","home"))=="home"

	static func table(s:Dictionary)->Vector2i:
		return World.COMMUNITY.table_cell(s)

	## Canonical "x,y" -> Vector2i, else null.
	static func parse(text:String):
		var parts:=text.split(",")
		if parts.size()!=2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():return null
		var cell:=Vector2i(int(parts[0]),int(parts[1]))
		if World.key(cell)!=text:return null
		return cell

	static func person(s:Dictionary,own:String)->Dictionary:
		var found=s.get("players",{}).get(own,{})
		return found if found is Dictionary else {}

	static func near(s:Dictionary,own:String,cell:Vector2i)->bool:
		var p:=person(s,own)
		if p.is_empty():return false
		return Vector2(float(p.get("x",-99)),float(p.get("y",-99))).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=REACH

	static func busy(obj:Dictionary)->bool:
		var job=obj.get("job")
		if job is Dictionary and not job.is_empty():return true
		var queue=obj.get("cooking")
		if queue is Dictionary:
			var active=queue.get("active")
			if active is Dictionary and not active.is_empty():return true
			for lane in ["waiting","ready"]:
				var list=queue.get(lane)
				if list is Array and not list.is_empty():return true
		return false

	## Home-island passability approximation on public data (World decides).
	static func blocked(s:Dictionary,p:Vector2i)->bool:
		if not World.land(p):return true
		if (p.x==55 or p.x==56) and not (bool(s.get("board",false)) and p.y>=29 and p.y<=31):return true
		if p==table(s) or p==World.COPPER_CELL:return true
		if p in [Vector2i(40,29),Vector2i(43,29),Vector2i(38,29),Vector2i(44,31),Vector2i(54,25)]:return true
		if p==World.SHIPPING.cell_for(s):return true
		var k:=World.key(p)
		var planted=s.get("forest",{}).get(k)
		if planted is Dictionary and not planted.is_empty():
			if bool(planted.get("mature",false)):return true
		elif not s.get("removed",{}).has(k) and World.base_resource(p) in ["tree","rock"]:return true
		var obj=s.get("objects",{}).get(k)
		if obj is Dictionary:
			if str(obj.get("type",""))=="door":return not bool(obj.get("open",false))
			return str(obj.get("type","")) in World.UNDO_SOLID
		return false

	## Passable cells reachable by cardinal steps from the shared table.
	## Memoized per snapshot instance (Session replaces it on every update).
	static var cached_snapshot:Dictionary={}
	static var cached_open:Dictionary={}

	static func reachable(s:Dictionary)->Dictionary:
		if is_same(s,cached_snapshot):return cached_open
		cached_snapshot=s
		cached_open=_search(s)
		return cached_open

	static func _search(s:Dictionary)->Dictionary:
		var origin:=table(s)
		var seen:={}
		if origin==NO_CELL:return seen
		var queue:Array=[]
		for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var start:Vector2i=origin+d
			if not blocked(s,start) and not seen.has(start):
				seen[start]=true
				queue.append(start)
		while not queue.is_empty():
			var at:Vector2i=queue.pop_front()
			for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next:Vector2i=at+d
				if seen.has(next) or absi(next.x-origin.x)>SEARCH or absi(next.y-origin.y)>SEARCH:continue
				if blocked(s,next):continue
				seen[next]=true
				queue.append(next)
		return seen

	static func accessible(open:Dictionary,cell:Vector2i)->bool:
		for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if open.has(cell+d):return true
		return false

	static func can_register(s:Dictionary)->bool:
		return home(s) and bool(s.get("picnic",false)) and table(s)!=NO_CELL and not registered(kitchen(s))

	static func candidate_stoves(s:Dictionary,own:String)->Array[String]:
		var out:Array[String]=[]
		if not can_register(s) or own.is_empty():return out
		var helper=core()
		if core_takes_state(helper,"candidate_stoves"):
			var found=helper.call("candidate_stoves",s,own)
			if found is Array:
				for item in found:
					if parse(str(item))!=null:out.append(str(item))
				out.sort()
				return out
		var origin:=table(s)
		var open:=reachable(s)
		for k in s.get("objects",{}):
			var obj=s.objects[k]
			if not obj is Dictionary or str(obj.get("type",""))!="stove" or str(obj.get("owner",""))!=own or busy(obj):continue
			var cell=parse(str(k))
			if cell==null:continue
			if Vector2(cell).distance_to(Vector2(origin))>STOVE_RANGE or not accessible(open,cell):continue
			out.append(str(k))
		out.sort()
		return out

	static func candidate_seats(s:Dictionary,own:String,stove:Vector2i)->Array[String]:
		var out:Array[String]=[]
		if not can_register(s) or own.is_empty():return out
		var helper=core()
		if core_takes_state(helper,"candidate_seats"):
			var found=helper.call("candidate_seats",s,own,stove)
			if found is Array:
				for item in found:
					if parse(str(item))!=null:out.append(str(item))
				out.sort()
				return out
		var open:=reachable(s)
		for k in s.get("objects",{}):
			var obj=s.objects[k]
			if not obj is Dictionary or str(obj.get("type",""))!="long_bench" or str(obj.get("owner",""))!=own:continue
			var cell=parse(str(k))
			if cell==null:continue
			if Vector2(cell).distance_to(Vector2(stove))>SEAT_RANGE or not accessible(open,cell):continue
			out.append(str(k))
		out.sort()
		return out

	## Why own stoves are missing from the list (display only).
	static func survey(s:Dictionary,own:String)->Dictionary:
		var out:={"stoves":0,"busy":0,"far":0,"blocked":0,"benches":0}
		var origin:=table(s)
		var open:=reachable(s)
		for k in s.get("objects",{}):
			var obj=s.objects[k]
			if not obj is Dictionary or str(obj.get("owner",""))!=own:continue
			var cell=parse(str(k))
			if cell==null:continue
			match str(obj.get("type","")):
				"long_bench":out.benches+=1
				"stove":
					out.stoves+=1
					if busy(obj):out.busy+=1
					elif origin==NO_CELL or Vector2(cell).distance_to(Vector2(origin))>STOVE_RANGE:out.far+=1
					elif not accessible(open,cell):out.blocked+=1
		return out

	static func events(s:Dictionary)->Array:
		var helper=core()
		if core_takes_state(helper,"events"):
			var found=helper.call("events",s)
			if found is Array:return clean_events(found)
		return local_events(s)

	static func clean_events(raw:Array)->Array:
		var out:Array=[]
		for entry in raw:
			if not entry is Dictionary or str(entry.get("id","")).is_empty():continue
			var lines:Array=[]
			var source=entry.get("lines",[])
			if source is Array:
				for line in source:
					if line is Dictionary and not str(line.get("text","")).is_empty():
						lines.append({"npc":str(line.get("npc","")),"text":str(line.text)})
			out.append({"id":str(entry.id),"title":str(entry.get("title",entry.id)),"lines":lines})
		return out

	## Immutable story inferred from world milestones; no read flags, no writes.
	static func local_events(s:Dictionary)->Array:
		var out:Array=[]
		if not bool(s.get("picnic",false)):return out
		out.append({"id":"picnic_invitation","title":"渡口野餐的邀請","lines":[
			{"npc":"aru","text":"橋通了，桌子也擺出來了。大家把自己的一點料理端過來，就是一頓飯。"},
			{"npc":"milu","text":"湯我多煮了一鍋，麵包也還溫著。不在的人，我們也替他留一個位子。"},
			{"npc":"aru","text":"下次如果有座灶就在桌邊，煮好的東西就不用一路端過來了。"}]})
		var k:=kitchen(s)
		if registered(k):
			out.append({"id":"kitchen_registration","title":"一起撐起的屋簷","lines":[
				{"npc":"milu","text":"有人把自己的小石灶借給大家了。從今天起，它就是渡口的灶。"},
				{"npc":"aru","text":"長椅也搬不走了，這樣誰來都有地方坐。屋頂和桌子，下次我們一起再補。"},
				{"npc":"xiaoli","text":"湯要四鍋、麵包兩份、沙拉兩盤。誰有多的就放一點，不必一個人撐。"}]})
		if registered(k) and k.opened:
			out.append({"id":"kitchen_opening","title":"公共廚房開伙","lines":[
				{"npc":"milu","text":"開伙了！每一碗都是不同的人準備的，所以每一口味道都不一樣。"},
				{"npc":"xiaoli","text":"吃飽了就有力氣。海那頭蘭陽的水圳和渡口的屋頂，還等著下一批人手。"},
				{"npc":"aru","text":"之後誰回來，都能在這張桌邊找到今天的故事。"}]})
		return out

	## Live recipe tables handed to the core's pure mill_guide (core never
	## preloads World, so quantities flow from here and cannot go stale).
	static func mill_tables()->Dictionary:
		return {"craft":World.CRAFT,"build":World.BUILD,"process":World.INDUSTRY.PROCESS,"recipes":World.RECIPES,"names":World.NAMES}

	## Q05 next steps after opening; [] before opening or without the core helper.
	static func mill_guide(s:Dictionary)->Array:
		var helper=core()
		if core_takes_state(helper,"mill_guide"):
			var found=helper.call("mill_guide",s,mill_tables())
			if found is Array:return found
		return []

	static func correlated(session)->Array:
		var helper=session.get_script()
		if helper is Script:
			var found=helper.get_script_constant_map().get("CORRELATED_ACTIONS",[])
			if found is Array:return found
		return []

	static func npc_name(id:String)->String:
		if Village.NPCS.has(id):return str(Village.NPCS[id].name)
		return "島民"

	static func meal_name(id:String)->String:
		return str(World.NAMES.get(id,id))


## Small read-only site diagram: table, stove range, seats, blocked tiles.
class SiteMap extends Control:
	const CELLS:=15
	const HALF:=7
	var snapshot:Dictionary={}
	var table:=Vector2i(-1,-1)
	var stove=null
	var seats:Array=[]
	var hints:Array=[]
	var atlas:Texture2D

	func _ready()->void:
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists(FURNITURE):atlas=load(FURNITURE) as Texture2D
		resized.connect(queue_redraw)

	func show_site(s:Dictionary,table_cell:Vector2i,stove_cell,seat_cells:Array,hint_cells:Array)->void:
		snapshot=s
		table=table_cell
		stove=stove_cell
		seats=seat_cells
		hints=hint_cells
		queue_redraw()

	func _draw()->void:
		if table==Vector2i(-1,-1):return
		var px:=floorf(minf(size.x,size.y)/CELLS)
		if px<4.0:return
		var center:=Vector2(table)
		if stove is Vector2i:center=(Vector2(table)+Vector2(stove))/2.0
		var origin:=Vector2i(roundi(center.x)-HALF,roundi(center.y)-HALF)
		var offset:=((size-Vector2(px*CELLS,px*CELLS))/2.0).floor()
		draw_rect(Rect2(offset-Vector2(2,2),Vector2(px*CELLS+4,px*CELLS+4)),Color("8a5a3a"))
		draw_rect(Rect2(offset,Vector2(px*CELLS,px*CELLS)),Color("e9d9ae"))
		for y in CELLS:
			for x in CELLS:
				var cell:=origin+Vector2i(x,y)
				if Query.blocked(snapshot,cell) and cell!=table:
					draw_rect(Rect2(offset+Vector2(x,y)*px,Vector2(px,px)).grow(-1),Color("bfa47a"))
		var t:=offset+(Vector2(table-origin)+Vector2(0.5,0.5))*px
		draw_arc(t,Query.STOVE_RANGE*px,0,TAU,48,Color("dd8f3e",0.6),1.0)
		if stove is Vector2i:
			draw_arc(offset+(Vector2(stove-origin)+Vector2(0.5,0.5))*px,Query.SEAT_RANGE*px,0,TAU,32,Color("3e664b",0.7),1.0)
		for cell in hints:
			if cell is Vector2i:draw_rect(Rect2(offset+Vector2(cell-origin)*px,Vector2(px,px)).grow(-1),Color("dd8f3e"),false,1.0)
		_sprite(table,TABLE_REGION,origin,offset,px)
		if stove is Vector2i:_sprite(stove,STOVE_REGION,origin,offset,px)
		for cell in seats:
			if cell is Vector2i:_sprite(cell,BENCH_REGION,origin,offset,px)

	func _sprite(cell:Vector2i,region:Rect2,origin:Vector2i,offset:Vector2,px:float)->void:
		var local:=cell-origin
		if local.x<0 or local.y<0 or local.x>=CELLS or local.y>=CELLS:return
		var w:=px*1.4
		var h:=w*1.5
		var foot:=offset+Vector2(local)*px+Vector2(px*0.5,px)
		var rect:=Rect2(foot-Vector2(w*0.5,h),Vector2(w,h))
		if atlas:draw_texture_rect_region(atlas,rect,region)
		else:draw_rect(rect,Color("8a5a3a"))


class Controller extends Node:
	const ACK_TIMEOUT_MS:=10000
	const WIDTH:=1000.0
	const HEIGHT:=620.0
	const MARGIN:=48.0
	var app
	var start_page:="kitchen"
	var refs:Dictionary={}
	var pending:Dictionary={}
	var stove_choice:=""
	var seat_choices:Array=["",""]
	var mode:=""
	var option_signature:=""
	var story_signature:=""
	var story_id:=""
	var story_shown:=0
	var guide_signature:=""
	var actions:Array=[]

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
		var extent:=Vector2(minf(WIDTH,bounds.x-MARGIN),minf(HEIGHT,bounds.y-MARGIN)).floor()
		return Rect2(((bounds-extent)/2.0).floor(),extent)

	## Main's generic preview layout may resize the modal afterwards; _process
	## re-asserts the kitchen size so no main.gd change is needed.
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
		if not pending.is_empty() and not bool(pending.host) and Time.get_ticks_msec()-int(pending.at)>ACK_TIMEOUT_MS:
			pending={}
			_status("還沒收到回應，結果未知。重試前請先看頁面上的狀態是否已更新，以免重複捐出。",false)
			refresh()

	func focus_start()->void:
		var first=null
		if start_page=="story":
			var tabs:Node=refs.get("story_tabs")
			if tabs and tabs.get_child_count()>0:first=tabs.get_child(tabs.get_child_count()-1)
		if first==null:
			for key in ["stove","contribute","cook"]:
				var control=refs.get(key)
				if control is Control and is_instance_valid(control) and control.is_visible_in_tree() and not (control is BaseButton and control.disabled):
					first=control
					break
		if first==null:first=refs.get("replay")
		if first is Control and is_instance_valid(first):first.grab_focus()

	# ------------------------------------------------------------------- build

	func build(body:VBoxContainer)->void:
		var book:=HBoxContainer.new()
		book.name="KitchenScrapbook"
		book.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		book.size_flags_vertical=Control.SIZE_EXPAND_FILL
		book.add_theme_constant_override("separation",0)
		body.add_child(book)
		# Open cookbook spread: kitchen recipe/setup page | spine | memory page.
		var left:=_page(book,"KitchenRecipePage",1.12)
		var spine:=ColorRect.new()
		spine.name="KitchenSpine"
		spine.color=Color("8a5a3a")
		spine.custom_minimum_size.x=6
		spine.mouse_filter=Control.MOUSE_FILTER_IGNORE
		book.add_child(spine)
		var right:=_page(book,"KitchenStoryPage",0.88)
		# Left page: page ribbon, scrolling recipe body, fixed action footer.
		refs.subtitle=_ribbon(left,"KitchenRecipeRibbon",[[stove_icon_texture(),30,"KitchenHeaderStove"],[Items.icon("soup"),28,""]],"社區食譜本",13)
		var scroll:=ScrollContainer.new()
		scroll.name="KitchenRecipeScroll"
		scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		left.add_child(scroll)
		refs.recipe_scroll=scroll
		var recipe:=VBoxContainer.new()
		recipe.name="KitchenRecipeBody"
		recipe.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		recipe.add_theme_constant_override("separation",6)
		scroll.add_child(recipe)
		refs.recipe=recipe
		# Commit controls never scroll away from their explanation.
		var footer:=VBoxContainer.new()
		footer.name="KitchenActions"
		footer.add_theme_constant_override("separation",4)
		left.add_child(footer)
		refs.footer=footer
		# Right page: the shared story scrapbook.
		var story_sub:=_ribbon(right,"KitchenStoryRibbon",[[Folio.life_icon("journal"),28,""]],"共餐記憶",13)
		story_sub.text="已發生的故事都能反覆重看"
		var tabs:=HFlowContainer.new()
		tabs.name="KitchenStoryTabs"
		tabs.add_theme_constant_override("h_separation",3)
		tabs.add_theme_constant_override("v_separation",3)
		right.add_child(tabs)
		refs.story_tabs=tabs
		var sheet:=PanelContainer.new()
		sheet.name="KitchenStorySheet"
		sheet.size_flags_vertical=Control.SIZE_EXPAND_FILL
		sheet.add_theme_stylebox_override("panel",Folio.story_style())
		right.add_child(sheet)
		var sheet_column:=VBoxContainer.new()
		sheet_column.add_theme_constant_override("separation",4)
		sheet.add_child(sheet_column)
		var story_title:=_text(sheet_column,"",17,WARN)
		story_title.name="KitchenStoryTitle"
		story_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		refs.story_title=story_title
		var story_scroll:=ScrollContainer.new()
		story_scroll.name="KitchenStory"
		story_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
		story_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		sheet_column.add_child(story_scroll)
		refs.story_scroll=story_scroll
		var lines:=VBoxContainer.new()
		lines.name="KitchenStoryLines"
		lines.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		lines.add_theme_constant_override("separation",6)
		story_scroll.add_child(lines)
		refs.story_lines=lines
		var controls:=HBoxContainer.new()
		controls.name="KitchenStoryControls"
		controls.alignment=BoxContainer.ALIGNMENT_END
		controls.add_theme_constant_override("separation",6)
		right.add_child(controls)
		refs.next=_button(controls,"KitchenStoryNext","下一句",_story_next)
		refs.replay=_button(controls,"KitchenStoryReplay","從頭重播",_story_replay)
		# Shared status line under the spread.
		var status_row:=HBoxContainer.new()
		status_row.name="KitchenStatusRow"
		status_row.add_theme_constant_override("separation",6)
		body.add_child(status_row)
		var bell:=Folio.life_icon("bell")
		if bell:status_row.add_child(_picture(bell,20,""))
		var status:=_text(status_row,"",14)
		status.name="KitchenStatus"
		status.custom_minimum_size.y=22
		status.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		refs.status=status

	func stove_icon_texture()->Texture2D:
		return Art.atlas_region(FURNITURE,STOVE_REGION)

	func _page(parent:Control,id:String,ratio:float)->VBoxContainer:
		var frame:=PanelContainer.new()
		frame.name=id
		frame.add_theme_stylebox_override("panel",Folio.page_style())
		frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		frame.size_flags_vertical=Control.SIZE_EXPAND_FILL
		frame.size_flags_stretch_ratio=ratio
		parent.add_child(frame)
		var column:=VBoxContainer.new()
		column.add_theme_constant_override("separation",6)
		frame.add_child(column)
		return column

	## Page-heading ribbon ("page tab"): pictures, title, right-aligned subtitle.
	## icons: Array of [Texture2D, extent:int, node_name:String].
	func _ribbon(parent:Node,id:String,icons:Array,title:String,sub_size:int)->Label:
		var ribbon:=PanelContainer.new()
		ribbon.name=id
		ribbon.add_theme_stylebox_override("panel",Folio.ribbon_style())
		parent.add_child(ribbon)
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",6)
		ribbon.add_child(row)
		for entry in icons:
			if entry[0]!=null:row.add_child(_picture(entry[0],int(entry[1]),str(entry[2])))
		var head:=_text(row,title,18,Folio.RIBBON_INK)
		head.autowrap_mode=TextServer.AUTOWRAP_OFF
		head.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		head.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		var sub:=_text(row,"",sub_size,Color(Folio.RIBBON_INK,0.85))
		sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		sub.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		return sub

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

	func _button(parent:Node,id:String,title:String,callback:Callable)->Button:
		var button:=Button.new()
		button.name=id
		button.text=title
		button.focus_mode=Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size",15)
		button.custom_minimum_size.y=36
		button.pressed.connect(callback)
		parent.add_child(button)
		return button

	func _action(parent:Node,id:String,title:String,callback:Callable)->Button:
		var button:=_button(parent,id,title,callback)
		button.set_meta("allowed",false)
		actions.append(button)
		return button

	func _clear(container:Node)->void:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()

	# ----------------------------------------------------------------- refresh

	func _on_changed(_snapshot:Dictionary,_own:String)->void:
		refresh()

	func _mode(s:Dictionary)->String:
		if not Query.home(s):return "away"
		if not bool(s.get("picnic",false)) or Query.table(s)==Query.NO_CELL:return "locked"
		if not Query.registered(Query.kitchen(s)):return "register"
		return "kitchen"

	func refresh()->void:
		if not refs.has("status"):return
		var s:Dictionary=app.session.snapshot
		var next:=_mode(s)
		# Hold the current layout while a request is pending (selection frozen).
		if next!=mode and pending.is_empty():
			mode=next
			option_signature=""
			_build_mode()
		match mode:
			"register":_update_register(s)
			"kitchen":_update_kitchen(s)
			"away":(refs.subtitle as Label).text="公共廚房在家園島的渡口"
			"locked":(refs.subtitle as Label).text="渡口野餐之後才會開放"
		_update_story(s)
		_sync()

	func _build_mode()->void:
		actions.clear()
		for key in ["stove","seat_a","seat_b","confirm","register","contribute","cook","map","meals","mill","mill_steps","survey","chosen","banner","reason"]:refs.erase(key)
		guide_signature=""
		var body:VBoxContainer=refs.recipe
		var footer:VBoxContainer=refs.footer
		_clear(body)
		_clear(footer)
		var scroll:ScrollContainer=refs.get("recipe_scroll")
		if scroll:scroll.scroll_vertical=0
		match mode:
			"away":
				_notice(body,Folio.life_icon("map"),"你現在不在家園島。回到渡口的共餐桌附近，才能捐出灶與長椅、放料理或使用公共小石灶。右頁的共餐記憶仍可隨時重看。")
			"locked":
				_notice(body,Art.atlas_region(FURNITURE,TABLE_REGION),"先一起修好河灣橋、在渡口辦完野餐，共餐桌擺好之後，公共廚房才能開始募集。")
			"register":_build_register(body,footer)
			"kitchen":_build_kitchen(body,footer)

	## Away / locked page: one illustrated note instead of an empty sheet.
	func _notice(body:VBoxContainer,icon:Texture2D,message:String)->void:
		var card:=PanelContainer.new()
		card.name="KitchenNotice"
		card.add_theme_stylebox_override("panel",Folio.card_style())
		body.add_child(card)
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",10)
		card.add_child(row)
		if icon:row.add_child(_picture(icon,48,""))
		_text(row,message,15)

	func _build_register(body:VBoxContainer,footer:VBoxContainer)->void:
		var intro:=HBoxContainer.new()
		intro.add_theme_constant_override("separation",8)
		body.add_child(intro)
		intro.add_child(_picture(Art.atlas_region(FURNITURE,BENCH_REGION),36,""))
		var intro_text:=VBoxContainer.new()
		intro_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		intro_text.add_theme_constant_override("separation",0)
		intro.add_child(intro_text)
		_text(intro_text,"先完成阿榆的長椅委託，解鎖雙人長椅。到共餐桌附近蓋好自己的小石灶與兩張長椅，再選擇要捐出的設施。",13)
		refs.survey=_text(intro_text,"",12,MUTED)
		refs.survey.name="KitchenSurvey"
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		body.add_child(row)
		var picks:=VBoxContainer.new()
		picks.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		picks.add_theme_constant_override("separation",3)
		row.add_child(picks)
		refs.stove=_option(picks,"KitchenStoveSelect",stove_icon_texture(),"灶：共餐桌 8 格內",_on_stove)
		refs.seat_a=_option(picks,"KitchenSeatA",Art.atlas_region(FURNITURE,BENCH_REGION),"長椅一：灶旁 3 格內",_on_seat.bind(0))
		refs.seat_b=_option(picks,"KitchenSeatB",Art.atlas_region(FURNITURE,BENCH_REGION),"長椅二：另一張",_on_seat.bind(1))
		var map:=SiteMap.new()
		map.name="KitchenSiteMap"
		map.custom_minimum_size=Vector2(140,140)
		map.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
		row.add_child(map)
		refs.map=map
		refs.chosen=_text(body,"",13)
		refs.chosen.name="KitchenChosenSites"
		# Footer: permanent-donation warning, explicit acknowledgement, commit.
		var warning:=PanelContainer.new()
		warning.name="KitchenDonationWarning"
		warning.add_theme_stylebox_override("panel",Folio.warning_style(WARN))
		footer.add_child(warning)
		var warn_row:=HBoxContainer.new()
		warn_row.add_theme_constant_override("separation",6)
		warning.add_child(warn_row)
		warn_row.add_child(_picture(Art.atlas_region(FURNITURE,TABLE_REGION),32,""))
		_text(warn_row,"永久公用捐贈：送出後這座灶和兩張長椅會固定在原地，任何島民都能使用；不能再搬移、拆除或用復原取回，已花的建材也不退還。每個世界只能登記一次。",13,WARN)
		var commit:=HBoxContainer.new()
		commit.name="KitchenCommitRow"
		commit.add_theme_constant_override("separation",8)
		footer.add_child(commit)
		var confirm:=CheckBox.new()
		confirm.name="KitchenConfirm"
		confirm.text="我了解這是永久捐出"
		confirm.focus_mode=Control.FOCUS_ALL
		confirm.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		confirm.add_theme_font_size_override("font_size",14)
		confirm.add_theme_color_override("font_color",INK)
		confirm.toggled.connect(func(_on:bool):refresh())
		commit.add_child(confirm)
		refs.confirm=confirm
		refs.register=_action(commit,"KitchenRegister","捐出成為公共廚房",_submit_register)
		refs.reason=_text(footer,"",13,MUTED)
		refs.reason.name="KitchenReason"

	func _option(parent:Node,id:String,icon:Texture2D,caption:String,callback:Callable)->OptionButton:
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",6)
		parent.add_child(row)
		row.add_child(_picture(icon,32,""))
		var column:=VBoxContainer.new()
		column.add_theme_constant_override("separation",0)
		column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(column)
		_text(column,caption,12,MUTED)
		var option:=OptionButton.new()
		option.name=id
		option.focus_mode=Control.FOCUS_ALL
		option.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		option.add_theme_font_size_override("font_size",14)
		option.clip_text=true
		option.item_selected.connect(callback)
		column.add_child(option)
		return option

	func _build_kitchen(body:VBoxContainer,footer:VBoxContainer)->void:
		# Setup strip: progress headline + donated sites beside the site diagram.
		var site:=HBoxContainer.new()
		site.name="KitchenSiteStrip"
		site.add_theme_constant_override("separation",8)
		body.add_child(site)
		var info:=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation",2)
		site.add_child(info)
		refs.banner=_text(info,"",18)
		refs.banner.name="KitchenBanner"
		refs.chosen=_text(info,"",12,MUTED)
		refs.chosen.name="KitchenSites"
		var map:=SiteMap.new()
		map.name="KitchenSiteMap"
		map.custom_minimum_size=Vector2(76,76)
		map.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
		site.add_child(map)
		refs.map=map
		# Recipe cards: large dish art, exact progress, bag, per-pot ingredients.
		var grid:=GridContainer.new()
		grid.name="KitchenMeals"
		grid.columns=3
		grid.add_theme_constant_override("h_separation",6)
		grid.add_theme_constant_override("v_separation",6)
		body.add_child(grid)
		var meals:={}
		for meal in Query.MEALS:
			var card:=PanelContainer.new()
			card.name="KitchenMeal_"+meal
			card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			card.add_theme_stylebox_override("panel",Folio.card_style())
			grid.add_child(card)
			var column:=VBoxContainer.new()
			column.add_theme_constant_override("separation",3)
			card.add_child(column)
			var top:=HBoxContainer.new()
			top.add_theme_constant_override("separation",4)
			column.add_child(top)
			top.add_child(_picture(Items.icon(meal),64,""))
			var titles:=VBoxContainer.new()
			titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			titles.size_flags_vertical=Control.SIZE_SHRINK_CENTER
			titles.add_theme_constant_override("separation",0)
			top.add_child(titles)
			_text(titles,Query.meal_name(meal),15)
			var have:=_text(titles,"",13)
			var meter:=ProgressBar.new()
			meter.show_percentage=false
			meter.custom_minimum_size.y=8
			meter.mouse_filter=Control.MOUSE_FILTER_IGNORE
			column.add_child(meter)
			var bag:=_text(column,"",12,MUTED)
			var recipe:Dictionary=World.RECIPES[meal]
			var ingredients:=HFlowContainer.new()
			ingredients.name="KitchenIngredients_"+meal
			ingredients.add_theme_constant_override("h_separation",4)
			ingredients.add_theme_constant_override("v_separation",2)
			column.add_child(ingredients)
			for item in recipe.ingredients:
				var ingredient:=HBoxContainer.new()
				ingredient.add_theme_constant_override("separation",0)
				ingredients.add_child(ingredient)
				ingredient.add_child(_picture(Items.icon(item),32,World.NAMES[item]))
				var amount:=_text(ingredient,"×%d"%int(recipe.ingredients[item]),12,MUTED)
				amount.autowrap_mode=TextServer.AUTOWRAP_OFF
				ingredient.tooltip_text="每鍋需要 %s ×%d"%[World.NAMES[item],int(recipe.ingredients[item])]
				amount.size_flags_vertical=Control.SIZE_SHRINK_CENTER
			_text(column,"每鍋 %d 份 · %d 秒"%[int(recipe["yield"]),int(recipe.time)],11,MUTED)
			meals[meal]={"meter":meter,"have":have,"bag":bag}
		refs.meals=meals
		# Opened stage only: data-driven next steps (Query.mill_guide), one row per
		# step with its output art and the exact quantities from World tables.
		var guide:=PanelContainer.new()
		guide.name="KitchenMillGuide"
		guide.add_theme_stylebox_override("panel",Folio.strip_style())
		guide.mouse_filter=Control.MOUSE_FILTER_PASS
		guide.visible=false
		body.add_child(guide)
		var guide_column:=VBoxContainer.new()
		guide_column.add_theme_constant_override("separation",1)
		guide.add_child(guide_column)
		var guide_head:=HBoxContainer.new()
		guide_head.add_theme_constant_override("separation",6)
		guide_column.add_child(guide_head)
		guide_head.add_child(_picture(Items.icon("mill_kit"),24,"KitchenMillIcon"))
		var line:=_text(guide_head,"下一步：工作台做磨坊 → {build_menu}「生活」放置 → 磨麥烤派",13,GOOD)
		line.name="KitchenMillText"
		line.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		var steps:=HBoxContainer.new()
		steps.name="KitchenMillSteps"
		steps.add_theme_constant_override("separation",8)
		guide_column.add_child(steps)
		refs.mill=guide
		refs.mill_steps=steps
		# Footer: commit actions stay in view next to their explanation.
		var row:=HFlowContainer.new()
		row.name="KitchenActionRow"
		row.add_theme_constant_override("h_separation",6)
		row.add_theme_constant_override("v_separation",4)
		footer.add_child(row)
		refs.contribute=_action(row,"KitchenContribute","把背包裡缺的料理放上桌",_submit_contribute)
		refs.cook=_action(row,"KitchenCook","用公共小石灶做菜",_open_cooker)
		refs.reason=_text(footer,"",13,MUTED)
		refs.reason.name="KitchenReason"

	## Rebuild the guide rows only when the data-driven steps change.
	func _fill_guide(steps:Array)->void:
		var list:Node=refs.get("mill_steps")
		if list==null or not is_instance_valid(list):return
		var signature:=JSON.stringify(steps)
		if signature==guide_signature:return
		guide_signature=signature
		_clear(list)
		for i in steps.size():
			var step=steps[i]
			if not step is Dictionary:continue
			var row:=VBoxContainer.new()
			row.name="KitchenMillStep_%d"%i
			row.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			row.add_theme_constant_override("separation",0)
			row.tooltip_text=str(step.get("text",""))
			if app.has_method("binding_text"):row.tooltip_text=app.binding_text(row.tooltip_text)
			list.add_child(row)
			var icon:=_picture(Items.icon(str(step.get("id",""))),64,"")
			icon.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
			row.add_child(icon)
			var title:String=["製作磨坊","擺好磨坊","磨製麵粉","烤南瓜派"][mini(i,3)]
			var text:=_text(row,"%d  %s"%[i+1,title],13)
			text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			text.mouse_filter=Control.MOUSE_FILTER_IGNORE

	# ------------------------------------------------------------ registration

	func _update_register(s:Dictionary)->void:
		var own:String=app.session.own_id
		var stoves:=Query.candidate_stoves(s,own)
		var frozen:=not pending.is_empty()
		if not frozen and not stove_choice.is_empty() and stove_choice not in stoves:
			stove_choice=""
			seat_choices=["",""]
			(refs.confirm as CheckBox).set_pressed_no_signal(false)
			_status("先前選的小石灶已不符合條件，請重新選擇。",false)
		var seats:Array[String]=[]
		var stove_cell=Query.parse(stove_choice)
		if stove_cell!=null:seats=Query.candidate_seats(s,own,stove_cell)
		if not frozen:
			for i in 2:
				if not str(seat_choices[i]).is_empty() and str(seat_choices[i]) not in seats:
					seat_choices[i]=""
					(refs.confirm as CheckBox).set_pressed_no_signal(false)
		var seat_counts:={}
		for cell in stoves:seat_counts[cell]=Query.candidate_seats(s,own,Query.parse(cell)).size()
		var signature:=JSON.stringify([stoves,seat_counts,seats,stove_choice,seat_choices])
		if signature!=option_signature and not frozen:
			option_signature=signature
			_fill_stoves(stoves,seat_counts)
			_fill_seats(seats,stove_cell)
		var survey:=Query.survey(s,own)
		var notes:=PackedStringArray(["你有 %d 座小石灶、%d 張雙人長椅"%[survey.stoves,survey.benches]])
		if survey.busy>0:notes.append("%d 座正在料理或還有成品"%survey.busy)
		if survey.far>0:notes.append("%d 座離共餐桌超過 8 格"%survey.far)
		if survey.blocked>0:notes.append("%d 座從共餐桌走不到"%survey.blocked)
		(refs.survey as Label).text="、".join(notes)+"。"
		(refs.subtitle as Label).text="登記：選一座灶與兩張長椅"
		var table:=Query.table(s)
		var chosen_seats:Array=[]
		for seat in seat_choices:
			var cell=Query.parse(str(seat))
			if cell!=null:chosen_seats.append(cell)
		var hints:Array=[]
		for cell in (seats if stove_cell!=null else stoves):hints.append(Query.parse(cell))
		(refs.map as SiteMap).show_site(s,table,stove_cell,chosen_seats,hints)
		var lines:=PackedStringArray(["共餐桌 %s"%_coords(table)])
		lines.append("灶 "+(_coords(stove_cell) if stove_cell!=null else "未選"))
		var seat_text:=PackedStringArray()
		for seat in seat_choices:seat_text.append(_coords(Query.parse(str(seat))) if Query.parse(str(seat))!=null else "未選")
		lines.append("長椅 "+"、".join(seat_text))
		(refs.chosen as Label).text="選定位置：　"+" · ".join(lines)
		var why:=_register_block(s,stoves,seats)
		var button:Button=refs.register
		button.set_meta("allowed",why.is_empty())
		(refs.reason as Label).text=why if not why.is_empty() else "確認設施與捐贈內容後，再按下捐出。"
		(refs.reason as Label).add_theme_color_override("font_color",MUTED if why.is_empty() else WARN)
		button.text="等待回應……" if not pending.is_empty() else "捐出成為公共廚房"

	func _register_block(s:Dictionary,stoves:Array,seats:Array)->String:
		if not pending.is_empty():return "上一個請求還在等待回應。"
		if stoves.is_empty():return "目前沒有符合條件的小石灶：需要自己的、閒置、離共餐桌 8 格內且走得到。"
		if stove_choice.is_empty():return "請先選一座小石灶。"
		if seats.size()<2:return "這座灶 3 格內沒有兩張你自己的、走得到的雙人長椅。"
		var a:=str(seat_choices[0])
		var b:=str(seat_choices[1])
		if a.is_empty() or b.is_empty():return "請選兩張長椅。"
		if a==b:return "兩張長椅必須是不同位置。"
		if not (refs.confirm as CheckBox).button_pressed:return "請勾選「我了解這是永久捐出」。"
		if not _online():return "與世界的連線已中斷。"
		return ""

	func _fill_stoves(stoves:Array,seat_counts:Dictionary)->void:
		var option:OptionButton=refs.stove
		option.clear()
		option.add_item("選擇自己的閒置小石灶…")
		option.set_item_metadata(0,"")
		var table:=Query.table(app.session.snapshot)
		for cell in stoves:
			var at:Vector2i=Query.parse(cell)
			var text:="小石灶 %s · 離桌 %.1f 格"%[_coords(at),Vector2(at).distance_to(Vector2(table))]
			if int(seat_counts.get(cell,0))<2:text+=" · 附近長椅不足"
			option.add_item(text)
			option.set_item_metadata(option.item_count-1,cell)
		option.select(maxi(0,_index_of(option,stove_choice)))

	func _fill_seats(seats:Array,stove_cell)->void:
		for i in 2:
			var option:OptionButton=refs.seat_a if i==0 else refs.seat_b
			option.clear()
			option.add_item("先選灶" if stove_cell==null else "選擇長椅…")
			option.set_item_metadata(0,"")
			for cell in seats:
				var at:Vector2i=Query.parse(cell)
				option.add_item("雙人長椅 %s · 離灶 %.1f 格"%[_coords(at),Vector2(at).distance_to(Vector2(stove_cell))])
				option.set_item_metadata(option.item_count-1,cell)
				# The other selector's choice is not offered twice.
				if cell==str(seat_choices[1-i]):option.set_item_disabled(option.item_count-1,true)
			option.select(maxi(0,_index_of(option,str(seat_choices[i]))))

	func _index_of(option:OptionButton,value:String)->int:
		if value.is_empty():return 0
		for i in option.item_count:
			if str(option.get_item_metadata(i))==value:return i
		return -1

	func _on_stove(index:int)->void:
		if not pending.is_empty():return
		stove_choice=str((refs.stove as OptionButton).get_item_metadata(index))
		seat_choices=["",""]
		(refs.confirm as CheckBox).set_pressed_no_signal(false)
		refresh()

	func _on_seat(index:int,which:int)->void:
		if not pending.is_empty():return
		var option:OptionButton=refs.seat_a if which==0 else refs.seat_b
		seat_choices[which]=str(option.get_item_metadata(index))
		(refs.confirm as CheckBox).set_pressed_no_signal(false)
		refresh()

	func _submit_register()->void:
		var s:Dictionary=app.session.snapshot
		var own:String=app.session.own_id
		var stoves:=Query.candidate_stoves(s,own)
		var stove_cell=Query.parse(stove_choice)
		var seats:Array[String]=[]
		if stove_cell!=null:seats=Query.candidate_seats(s,own,stove_cell)
		var why:=_register_block(s,stoves,seats)
		if why.is_empty() and (stove_choice not in stoves or str(seat_choices[0]) not in seats or str(seat_choices[1]) not in seats):why="選擇已過期，請重新確認。"
		if not why.is_empty():
			_status(why,false)
			refresh()
			return
		var chosen:Array=[str(seat_choices[0]),str(seat_choices[1])]
		chosen.sort()
		submit("kitchen_register",stove_cell,"|".join(PackedStringArray(chosen)),"登記公共廚房")

	# ----------------------------------------------------------------- kitchen

	func _update_kitchen(s:Dictionary)->void:
		var own:String=app.session.own_id
		var k:=Query.kitchen(s)
		var needs:=Query.needs()
		var stove_cell=Query.parse(str(k.stove))
		var seats:Array=[]
		for seat in k.seats:
			var cell=Query.parse(str(seat))
			if cell!=null:seats.append(cell)
		(refs.map as SiteMap).show_site(s,Query.table(s),stove_cell,seats,[])
		var seat_text:=PackedStringArray()
		for cell in seats:seat_text.append(_coords(cell))
		(refs.chosen as Label).text="公共小石灶 %s · 公共長椅 %s · 共餐桌 %s"%[_coords(stove_cell),"、".join(seat_text),_coords(Query.table(s))]
		var bag:Dictionary=Query.person(s,own).get("inventory",{})
		var give:={}
		var outstanding:=0
		for meal in Query.MEALS:
			var need:=int(needs[meal])
			var have:=mini(int(k.meals[meal]),need)
			var left:=maxi(0,need-have)
			outstanding+=left
			var held:=int(bag.get(meal,0))
			give[meal]=mini(held,left)
			var parts:Dictionary=refs.meals[meal]
			(parts.meter as ProgressBar).max_value=maxi(1,need)
			(parts.meter as ProgressBar).value=have
			(parts.have as Label).text="已上桌 %d／%d"%[have,need]
			(parts.have as Label).add_theme_color_override("font_color",GOOD if left==0 else INK)
			(parts.bag as Label).text="背包 %d · 這次放 %d"%[held,give[meal]]
		var opened:bool=bool(k.opened)
		(refs.banner as Label).text="公共廚房已開伙！" if opened else "還缺 %d 份料理就能開伙"%outstanding
		(refs.banner as Label).add_theme_color_override("font_color",GOOD if opened else INK)
		(refs.subtitle as Label).text="任何島民都能在這裡做菜、放料理"
		var steps:Array=Query.mill_guide(s) if opened else []
		var guide:Control=refs.get("mill")
		if guide:
			guide.visible=not steps.is_empty()
			var tips:=PackedStringArray()
			for i in steps.size():tips.append("%d. %s"%[i+1,str(steps[i].get("text",""))])
			var tip:="\n".join(tips)
			if app.has_method("binding_text"):tip=app.binding_text(tip)
			guide.tooltip_text=tip
			_fill_guide(steps)
		var debit:=PackedStringArray()
		for meal in Query.MEALS:
			if int(give[meal])>0:debit.append("%s×%d"%[Query.meal_name(meal),int(give[meal])])
		var near:bool=stove_cell!=null and Query.near(s,own,stove_cell)
		var stove_present:bool=stove_cell!=null and str(s.get("objects",{}).get(World.key(stove_cell),{}).get("type",""))=="stove"
		var contribute_why:=""
		if opened:contribute_why="已經開伙，不需要再放料理。"
		elif debit.is_empty():contribute_why="背包裡沒有還缺的湯、麵包或沙拉。"
		elif not near:contribute_why="走到公共小石灶身邊三格內才能放料理。"
		elif not _online():contribute_why="與世界的連線已中斷。"
		var contribute:Button=refs.contribute
		contribute.visible=not opened
		contribute.set_meta("allowed",contribute_why.is_empty())
		contribute.text="等待回應……" if not pending.is_empty() else ("把料理放上桌：" +"、".join(debit) if not debit.is_empty() else "放上開張餐點")
		contribute.tooltip_text="只扣這些數量，不給獎勵。\n手把 X 選取 · A 確認" if contribute_why.is_empty() else contribute_why
		var cook_why:=""
		if not stove_present:cook_why="公共小石灶不在目前區域。"
		elif not near:cook_why="走到公共小石灶身邊三格內才能做菜。"
		var cook:Button=refs.cook
		cook.set_meta("allowed",cook_why.is_empty())
		cook.tooltip_text="翻開小石灶食譜，準備下一道料理。" if cook_why.is_empty() else cook_why
		var reasons:=PackedStringArray()
		if not pending.is_empty():reasons.append("上一個請求還在等待回應。")
		elif not contribute_why.is_empty() and not opened:reasons.append(contribute_why)
		if not cook_why.is_empty() and cook_why not in reasons:reasons.append(cook_why)
		(refs.reason as Label).text=" ".join(reasons) if not reasons.is_empty() else "放上桌只扣上面列出的數量；做好的菜可由在場島民領取。"

	func _submit_contribute()->void:
		var k:=Query.kitchen(app.session.snapshot)
		var stove_cell=Query.parse(str(k.stove))
		if stove_cell==null or not bool((refs.contribute as Button).get_meta("allowed",false)):return
		submit("kitchen_contribute",stove_cell,"","把料理放上公共餐桌")

	func _open_cooker()->void:
		if not pending.is_empty():return
		var stove_cell=Query.parse(str(Query.kitchen(app.session.snapshot).stove))
		if stove_cell==null or not bool((refs.cook as Button).get_meta("allowed",false)):return
		app._cook_menu(stove_cell)

	# ------------------------------------------------------------------- story

	func _update_story(s:Dictionary)->void:
		var events:=Query.events(s)
		var parts:Array=[]
		for event in events:parts.append([event.id,event.title,(event.lines as Array).size()])
		var signature:=JSON.stringify(parts)
		if signature==story_signature:return
		story_signature=signature
		var tabs:HFlowContainer=refs.story_tabs
		_clear(tabs)
		var known:=false
		for event in events:known=known or event.id==story_id
		var group:=ButtonGroup.new()
		for event in events:
			var id:String=event.id
			var tab:=Button.new()
			tab.name="KitchenStory_"+id
			tab.text=str(event.title)
			tab.toggle_mode=true
			tab.button_group=group
			tab.focus_mode=Control.FOCUS_ALL
			tab.tooltip_text=str(event.title)
			tab.add_theme_font_size_override("font_size",13)
			Folio.apply_tab(tab)
			tab.pressed.connect(_show_story.bind(id,true))
			tabs.add_child(tab)
		if events.is_empty():
			story_id=""
			_render_story()
			return
		if not known:
			story_id=str(events.back().id)
			story_shown=0
		_show_story(story_id,not known)

	func _event(id:String)->Dictionary:
		for event in Query.events(app.session.snapshot):
			if event.id==id:return event
		return {}

	func _show_story(id:String,restart:bool)->void:
		story_id=id
		for tab in (refs.story_tabs as Node).get_children():
			(tab as Button).set_pressed_no_signal(str(tab.name)=="KitchenStory_"+id)
		if restart:story_shown=1
		var event:=_event(id)
		_render_story()

	func _reduced_motion()->bool:
		return app.sound!=null and bool(app.sound.reduced_motion)

	func _render_story()->void:
		var lines:VBoxContainer=refs.story_lines
		_clear(lines)
		var event:=_event(story_id)
		var next:Button=refs.next
		var replay:Button=refs.replay
		var title:Label=refs.get("story_title")
		if event.is_empty():
			if title:title.text="還沒翻開的一頁"
			var empty:=HBoxContainer.new()
			empty.add_theme_constant_override("separation",8)
			lines.add_child(empty)
			var mark:=Folio.life_icon("letter")
			if mark:empty.add_child(_picture(mark,48,""))
			_text(empty,"野餐之後，渡口的共餐故事會收在這一頁。之後加入的島民也能從頭看到每一段。",14,MUTED)
			next.disabled=true
			replay.disabled=true
			next.text="下一句"
			return
		if title:title.text=str(event.get("title",""))
		var all:Array=event.lines
		story_shown=clampi(story_shown,1,maxi(1,all.size()))
		# One conversational beat per page; no scrolling through stacked text boxes.
		for i in range(story_shown-1,mini(story_shown,all.size())):
			var line:Dictionary=all[i]
			var row:=HBoxContainer.new()
			row.name="KitchenStoryLine_%d"%i
			row.add_theme_constant_override("separation",10)
			lines.add_child(row)
			var portrait:=Art.icon(str(line.npc))
			if portrait:
				var frame:=PanelContainer.new()
				frame.name="KitchenStoryPortrait"
				frame.add_theme_stylebox_override("panel",Folio.portrait_style())
				frame.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
				frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
				frame.add_child(_picture(portrait,96,""))
				row.add_child(frame)
			var bubble:=PanelContainer.new()
			bubble.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			bubble.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
			row.add_child(bubble)
			var column:=VBoxContainer.new()
			column.add_theme_constant_override("separation",2)
			bubble.add_child(column)
			_text(column,Query.npc_name(str(line.npc)),17,GOOD)
			_text(column,"「%s」"%str(line.text),17)
		next.disabled=story_shown>=all.size()
		next.text="下一句  %d／%d"%[mini(story_shown,all.size()),all.size()]
		replay.disabled=false
		var scroll:ScrollContainer=refs.story_scroll
		var last:=lines.get_child(lines.get_child_count()-1) as Control
		if last:scroll.ensure_control_visible.call_deferred(last)

	func _story_next()->void:
		story_shown+=1
		_render_story()

	func _story_replay()->void:
		if story_id.is_empty():return
		story_shown=1
		_render_story()

	# --------------------------------------------------------------- requests

	## One explicit intent; never retried. Selection stays frozen until the
	## matching (sequence, action) completion or an explicitly unknown timeout.
	func submit(action:String,p:Vector2i,extra:String,intent:String)->void:
		if not pending.is_empty():
			_status("上一個請求還在等待回應，請稍候。",false)
			return
		var session=app.session
		var hosting:bool=session.world!=null
		if not hosting and not _online():
			_status("與世界的連線已中斷，這次沒有送出。",false)
			return
		var correlated:bool=action in Query.correlated(session)
		if not correlated:
			_status("目前連線版本不支援公共廚房，請重新加入世界。",false)
			return
		pending={"action":action,"sequence":int(session.counter)+1,"at":Time.get_ticks_msec(),"host":hosting,
			"correlated":correlated,"before":_fingerprint()}
		_status(intent+"……等待回應",true)
		refresh()
		var sequence:int=session.perform(action,p,extra)
		if pending.is_empty():return # Host answered synchronously.
		if sequence<=0:
			pending={}
			_status("世界正在關閉，這次沒有送出。",false)
			refresh()
			return
		pending.sequence=sequence
		if hosting:
			var changed:bool=_fingerprint()!=str(pending.before)
			pending={}
			if correlated:_status("世界暫時不接受操作（可能正在保存），這次沒有變更。",false)
			elif changed:_status("已完成，頁面已更新。",true)
			else:_status("沒有變更；請看狀態提示（這版連線沒有回傳逐筆結果）。",false)
			refresh()

	func _on_completed(sequence:int,action:String,result:Dictionary)->void:
		if pending.is_empty() or sequence!=int(pending.sequence) or action!=str(pending.action):return
		pending={}
		var ok:bool=bool(result.get("ok",false))
		var message:=str(result.get("message","已回覆。"))
		if ok:
			if action=="kitchen_register":
				stove_choice=""
				seat_choices=["",""]
			_status(message,true)
		else:_status("沒有變更："+message,false)
		refresh()

	func _fingerprint()->String:
		var s:Dictionary=app.session.snapshot
		var bag:Dictionary=Query.person(s,app.session.own_id).get("inventory",{})
		var held:Array=[]
		for meal in Query.MEALS:held.append(int(bag.get(meal,0)))
		return JSON.stringify([s.get("public_kitchen",{}),held])

	func _online()->bool:
		if app.session.world!=null:return true
		var peer=app.session.multiplayer.multiplayer_peer
		return peer!=null and peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED

	func _sync()->void:
		var busy:=not pending.is_empty()
		for button in actions:
			if button is Button and is_instance_valid(button):
				button.disabled=busy or not bool(button.get_meta("allowed",false))
		for key in ["stove","seat_a","seat_b"]:
			var option=refs.get(key)
			if option is OptionButton and is_instance_valid(option):
				option.disabled=busy or (key!="stove" and stove_choice.is_empty()) or option.item_count<=1
		var confirm=refs.get("confirm")
		if confirm is CheckBox and is_instance_valid(confirm):confirm.disabled=busy

	func _status(message:String,success:bool)->void:
		var label:Label=refs.get("status")
		if label==null:return
		label.text=message
		label.add_theme_color_override("font_color",GOOD if success else WARN)

	func _coords(cell)->String:
		if not cell is Vector2i or cell==Query.NO_CELL:return "—"
		return "(%d, %d)"%[cell.x,cell.y]
