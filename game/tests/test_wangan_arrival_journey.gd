extends SceneTree
## 澎湖・望安 arrival acceptance journey (headless, real app, one fresh save, one player):
## 「從新存檔核對抵達地名、田地位置、首株蘿蔔到出貨箱，以及保留修碼頭、合作小船與風鈴節路線」.
##
## SETUP (not game state): the real main.tscn is instanced at 1280×800 with
## app.village_art_preview=true (the runner passes no preview flag for this suite)
## and hosts an isolated save in %TEMP% (deleted at the end). The player token is
## the runner's --profile. Nothing in this file writes inventory, coins, flags,
## chapter fields, position or world time.
##
## HOW EACH PART IS DRIVEN
##  * Real input through the viewport (root.push_input -> main._input /
##    _unhandled_input): the interact key that closes the arrival card and opens
##    the shipping bin / notice board, the tool keys (hoe/seed/water/harvest), left
##    clicks on world cells (main -> _use_selected_at -> session.perform), Esc,
##    the festival key and the map key.
##  * Walking: the movement key is held with Input.parse_input_event; main._process
##    (running normally) reads it and calls Session.input_direction. The engine's
##    physics tick is switched off for the session and replaced by explicit calls
##    of the same Session._physics_process(dt) with a fixed dt=0.25/3.6, four per
##    cell, so every step is exactly one cell (World.move_player at 3.6 tiles/s).
##    Walking therefore costs real world time (World.step inside that tick).
##  * Waiting for the radish: the same Session._physics_process tick, 1.0 s per
##    call with no key held (World.step(1.0,true) inside it), until ripe.
##  * Panel buttons (shipping bin slot / ＋ / 核對 / 確認, 台灣旅圖, a travel route
##    button) are pressed by emitting their pressed signal, like the other UI tests.
##  * session.perform is used directly exactly once: the "ship before any harvest"
##    refusal, because the bin panel never lets a player put a radish they do not
##    hold into the basket (that UI guard is asserted first); the payload is the
##    panel's own wire format.
##  * One direct read-only UI call: LifeTasks.dock_project(app) to look at the
##    stage-0 dock page, which has no entry point before the 渡口野餐 (asserted).
## Retained routes are only looked at here; completing them is covered by
## test_chapter_journey (chapter one / picnic), test_transit_journey (boat/ferry
## routes) and test_festival_earned_journey (風鈴節).
const World=preload("res://scripts/world.gd")
const Chapter=preload("res://scripts/chapter_one.gd")
const Opening=preload("res://scripts/wangan_opening.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const TravelUI=preload("res://scripts/travel_ui.gd")
const Transit=preload("res://scripts/transit.gd")
const Shipping=preload("res://scripts/shipping.gd")
const ShippingPanel=preload("res://scripts/shipping_panel.gd")
const LifeTasks=preload("res://scripts/life_ui_tasks.gd")
const STEP_DT:=0.25/3.6
const WAIT_TICK:=1.0
const NEIGHBORS:=[Vector2i(0,1),Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1)]
const HEADING:="第一件事・種一株蘿蔔"

var app
var w
var tok:=""
var me:=""
var path:=""
var paths:Array[String]=[]
var checks:=0
var failures:=0
var finished:=false
var notices:Array=[]
var held_key:=KEY_NONE
var cells_walked:=0
var actions:=0
var rejections:=0
var time_start:=0.0
var time_now:=0.0
var coins_before:=0
var coins_after:=0
var grow_seconds:=0.0
var started_ms:=0
var trace:Array=[]
var tracing:=false

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->bool:
	checks+=1
	if not value:
		failures+=1
		push_error("WANGAN_JOURNEY FAIL: "+message)
	return value

func note(message:String)->void:
	print("WANGAN_JOURNEY "+message)

func finish()->void:
	if finished:return
	finished=true
	release()
	if app!=null and is_instance_valid(app) and app.session.world!=null:
		time_now=float(app.session.world.state.time)
		app.session.shutdown()
	for item in paths:
		for suffix in ["",".bak",".tmp",".writer-lock",".bindings"]:
			if FileAccess.file_exists(item+suffix):DirAccess.remove_absolute(item+suffix)
	print("WANGAN_ARRIVAL_JOURNEY actions=%d cells_walked=%d world_seconds=%.1f grow_wait_seconds=%.1f coins_before=%d coins_after=%d rejections=%d runtime_ms=%d"%[actions,cells_walked,time_now-time_start,grow_seconds,coins_before,coins_after,rejections,Time.get_ticks_msec()-started_ms])
	print("WANGAN_ARRIVAL_JOURNEY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ------------------------------------------------------------------ helpers --

static func canon(value:Variant)->Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			var source:Variant=value[k] if value.has(k) else value[StringName(k)]
			out[k]=canon(source)
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(canon(item))
		return list
	if value is float and is_finite(value) and floorf(value)==value:return int(value)
	return value

static func same(a:Variant,b:Variant)->bool:
	return var_to_bytes(canon(a))==var_to_bytes(canon(b))

static func nonzero(inv:Dictionary)->Dictionary:
	var out:={}
	for item in inv:
		if int(inv[item])!=0:out[str(item)]=int(inv[item])
	return out

static func plus(inv:Dictionary,delta:Dictionary)->Dictionary:
	var out:=nonzero(inv)
	for item in delta:
		out[str(item)]=int(out.get(str(item),0))+int(delta[item])
	return nonzero(out)

## Changed top-level keys of the world state; the player record is split per field.
func diff_paths(a:Dictionary,b:Dictionary)->Array:
	var ca:Dictionary=canon(a)
	var cb:Dictionary=canon(b)
	var out:=[]
	var keys:={}
	for k in ca:keys[k]=true
	for k in cb:keys[k]=true
	for k:String in keys:
		if k=="players":
			var pa:Dictionary=ca.get("players",{}).get(tok,{})
			var pb:Dictionary=cb.get("players",{}).get(tok,{})
			var fields:={}
			for f in pa:fields[f]=true
			for f in pb:fields[f]=true
			for f:String in fields:
				if not same(pa.get(f),pb.get(f)):out.append("players."+f)
			if ca.players.size()!=cb.players.size():out.append("players.<count>")
		elif not same(ca.get(k),cb.get(k)):out.append(k)
	out.sort()
	return out

func person()->Dictionary:
	return w.state.players[tok]

func snap()->Dictionary:
	return app.session.snapshot

func snap_person()->Dictionary:
	return snap().get("players",{}).get(me,{})

func pos()->Vector2:
	return Vector2(float(person().x),float(person().y))

func snap_pos()->Vector2:
	var p:Dictionary=snap_person()
	return Vector2(float(p.get("x",-1)),float(p.get("y",-1)))

func bag()->Dictionary:
	return nonzero(person().inventory)

func snap_bag()->Dictionary:
	return nonzero(snap_person().get("inventory",{}))

func bound(action:String)->int:
	return int(app.bindings.keys.get(action,KEY_NONE))

func card()->Control:
	return WanganUI.card(app)

func card_text(name:String)->String:
	var c:=card()
	if c==null:return ""
	var l:=c.find_child(name,true,false) as Label
	return l.text if l!=null else ""

func frames(n:int=4)->void:
	for i in n:await process_frame

## Lets main._process run (HUD refresh every 0.2 s, action_clock 0.16 s) and the
## view interpolate; no world time passes (the session tick is ours).
func hud_tick()->void:
	await create_timer(0.25).timeout
	await frames(2)

func key(code:int)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		root.push_input(e)
	await frames(3)

func hold(code:int)->void:
	if held_key==code:return
	release()
	var e:=InputEventKey.new()
	e.keycode=code;e.physical_keycode=code;e.pressed=true
	Input.parse_input_event(e)
	held_key=code

func release()->void:
	if held_key==KEY_NONE:return
	var e:=InputEventKey.new()
	e.keycode=held_key;e.physical_keycode=held_key;e.pressed=false
	Input.parse_input_event(e)
	held_key=KEY_NONE

## Waits (real time) until main._process has handed the held direction to the Session.
func direction_is(d:Vector2)->bool:
	for i in 80:
		if Vector2(app.session.directions.get(1,Vector2(9,9)))==d:return true
		await create_timer(0.02).timeout
	return false

func move_key(d:Vector2i)->int:
	if d==Vector2i(1,0):return bound("move_right")
	if d==Vector2i(-1,0):return bound("move_left")
	if d==Vector2i(0,1):return bound("move_down")
	return bound("move_up")

func tick(dt:float)->void:
	app.session._physics_process(dt)

func standable(c:Vector2i)->bool:
	return w.can_stand(Vector2(c)+Vector2(0.5,0.5))

## Breadth-first route over standable cells to the first reachable goal cell
## (goals tried in the given order). Read-only on the server world.
func route(goals:Array)->Array:
	for goal in goals:
		var start:=Vector2i(floori(pos().x),floori(pos().y))
		var queue:=[start]
		var prev:={start:start}
		var i:=0
		while i<queue.size():
			var c:Vector2i=queue[i]
			i+=1
			if c==goal:
				var out:=[c]
				while c!=start:
					c=prev[c]
					out.push_front(c)
				return out
			for o in NEIGHBORS:
				var n:Vector2i=c+o
				if prev.has(n) or absi(n.x-start.x)>30 or absi(n.y-start.y)>30 or not standable(n):continue
				prev[n]=c
				queue.append(n)
	return []

## Goal cells beside `target` (south first), standable and not on the starter plot.
func beside(target:Vector2i)->Array:
	var out:=[]
	for o in NEIGHBORS:
		var c:Vector2i=target+o
		if c not in Chapter.STARTER_PLOT and standable(c):out.append(c)
	return out

## Walks path[from..to] with the held movement key and four session ticks per cell.
func walk(path_cells:Array,from:int,to:int,label:String)->bool:
	for index in range(from+1,to+1):
		var d:Vector2i=path_cells[index]-path_cells[index-1]
		hold(move_key(d))
		var handed:bool=await direction_is(Vector2(d))
		if not check(handed,"%s: held %s reached the session as %s"%[label,OS.get_keycode_string(move_key(d)),str(d)]):
			release()
			return false
		for s in 4:tick(STEP_DT)
		cells_walked+=1
		var want:=Vector2(path_cells[index])+Vector2(0.5,0.5)
		if not check(pos().distance_to(want)<=0.001,"%s: cell %d is %s (at %s)"%[label,index,str(path_cells[index]),str(pos())]):
			release()
			return false
		if not check(snap_pos().distance_to(want)<=0.001,"%s: client snapshot follows to %s (snapshot %s)"%[label,str(path_cells[index]),str(snap_pos())]):
			release()
			return false
		if tracing:
			var server_step:=Chapter.first_crop_step(w.state,tok)
			var client_step:=Chapter.first_crop_step(snap(),me)
			check(str(server_step.get("id",""))==str(client_step.get("id","")),"%s: server/client first-crop step agree at %s"%[label,str(path_cells[index])])
			trace.append([path_cells[index],str(client_step.get("id",""))])
	release()
	var stopped:bool=await direction_is(Vector2.ZERO)
	check(stopped,label+": key released, session direction back to zero")
	return true

func walk_to(goals:Array,label:String)->bool:
	var cells:=route(goals)
	if not check(not cells.is_empty(),"%s: route found from %s to %s"%[label,str(pos()),str(goals)]):return false
	var ok:=await walk(cells,0,cells.size()-1,label)
	note("%s: walked %d cells to %s, time=%.2f"%[label,cells.size()-1,str(cells.back()),float(w.state.time)])
	return ok

func click(cell:Vector2i)->void:
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
	await frames(2)

## Tool key, then a left click on the cell. Returns true when exactly one request left.
func tool_click(action:String,cell:Vector2i)->bool:
	await key(bound(action))
	check(app.selected==action,"Tool key %s selects %s (selected %s)"%[app.binding_label(action),action,app.selected])
	await hud_tick()
	var before:int=app.session.counter
	await click(cell)
	var sent:int=int(app.session.counter)-before
	actions+=sent
	return check(sent==1,"Click on %s with %s sent exactly one request (%d)"%[str(cell),action,sent])

func last_notice()->Array:
	return notices.back() if not notices.is_empty() else ["",false]

## A refused click: exact message, whole world state, bag (server + client) unchanged.
func refused_click(action:String,cell:Vector2i,message:String,label:String)->void:
	var state_before:Dictionary=w.state.duplicate(true)
	var bag_before:=bag()
	var snap_before:=snap_bag()
	var step_before:=Chapter.first_crop_step(w.state,tok)
	notices.clear()
	if not await tool_click(action,cell):return
	check(notices.size()==1 and str(last_notice()[0])==message and last_notice()[1]==false,"%s: refused with 「%s」 (got %s)"%[label,message,str(notices)])
	check(same(w.state,state_before),"%s: whole world state unchanged (diff %s)"%[label,str(diff_paths(state_before,w.state))])
	check(same(bag(),bag_before) and same(snap_bag(),snap_before),label+": inventory unchanged on server and client")
	check(same(Chapter.first_crop_step(w.state,tok),step_before),label+": first-crop step unchanged")
	rejections+=1
	note("refusal %d (%s): %s"%[rejections,label,message])

## A successful click: exact message, whole-bag delta, exact set of changed world keys.
func done_click(action:String,cell:Vector2i,message:String,delta:Dictionary,changed:Array,label:String)->void:
	var state_before:Dictionary=w.state.duplicate(true)
	var bag_before:=bag()
	var snap_before:=snap_bag()
	notices.clear()
	if not await tool_click(action,cell):return
	check(notices.size()==1 and str(last_notice()[0])==message and last_notice()[1]==true,"%s: 「%s」 (got %s)"%[label,message,str(notices)])
	check(same(bag(),plus(bag_before,delta)),"%s: server bag %s -> %s, expected delta %s"%[label,JSON.stringify(bag_before),JSON.stringify(bag()),JSON.stringify(delta)])
	check(same(snap_bag(),plus(snap_before,delta)),"%s: client bag follows (%s)"%[label,JSON.stringify(snap_bag())])
	var diff:=diff_paths(state_before,w.state)
	var expected:=changed.duplicate()
	expected.sort()
	check(diff==expected,"%s: changed world keys %s, expected %s"%[label,str(diff),str(expected)])
	note("%s ok: %s changed=%s"%[label,message,str(diff)])

func expect_step(id:String,label:String)->void:
	var server_step:=Chapter.first_crop_step(w.state,tok)
	var client_step:=Chapter.first_crop_step(snap(),me)
	check(str(server_step.get("id",""))==id,"%s: server first_crop_step is %s (got %s)"%[label,id,str(server_step)])
	check(str(client_step.get("id",""))==id,"%s: client first_crop_step is %s (got %s)"%[label,id,str(client_step)])

func expect_tracker(expected:String,label:String)->void:
	await hud_tick()
	check(str(app.objective.text)==expected,"Tracker (%s): 「%s」 expected 「%s」"%[label,str(app.objective.text),expected])

func modal_texts()->Array:
	var out:=[]
	if not is_instance_valid(app.modal):return out
	for node in app.modal.find_children("*","",true,false):
		if node is Label or node is Button:out.append(str(node.text))
	return out

func ticket_labels()->Array:
	var out:=[]
	if not is_instance_valid(app.modal):return out
	var ticket:Node=app.modal.find_child("TravelTicket",true,false)
	if ticket==null:return out
	for node in ticket.find_children("*","Label",true,false):out.append(str((node as Label).text))
	return out

func modal_button(text:String)->Button:
	if not is_instance_valid(app.modal):return null
	for node in app.modal.find_children("*","Button",true,false):
		if str((node as Button).text)==text:return node as Button
	return null

func close_modal_with_esc(label:String)->void:
	await key(KEY_ESCAPE)
	check(app.modal==null,label+": Esc closes the panel")
	await frames(2)

# --------------------------------------------------------------------- app --

func open_app()->bool:
	root.size=Vector2i(1280,800)
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	# The session's engine physics tick is replaced by explicit ticks (see header).
	app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	app.session.notice.connect(func(message:String,success:bool):notices.append([message,success]))
	notices.clear()
	if not check(app.session.host(0,"望安旅人",path)==OK,"Host starts on the isolated save"):return false
	await frames(6)
	w=app.session.world
	tok=str(app.session.profile.token)
	me=str(app.session.own_id)
	return check(w!=null and app.playing and w.state.players.has(tok) and snap().get("players",{}).has(me),"Hosted world has me on server (%s) and client (%s)"%[tok,me])

func close_app()->void:
	release()
	check(app.session.shutdown(),"Session shuts down and saves")
	await create_timer(0.2).timeout
	app.queue_free()
	app=null
	await frames(3)

# --------------------------------------------------------------------- flow --

func run()->void:
	started_ms=Time.get_ticks_msec()
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	path=OS.get_environment("TEMP").path_join("wangan-journey-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not check(not FileAccess.file_exists(path),"Save path is new"):
		finish()
		return
	paths.append(path)
	if not await open_app():
		finish()
		return
	time_start=float(w.state.time)
	coins_before=int(person().coins)
	if not await arrival():
		finish()
		return
	if not await first_radish():
		finish()
		return
	if not await ship_radish():
		finish()
		return
	if not await reload():
		finish()
		return
	await retained_routes()
	time_now=float(w.state.time)
	finish()

## 1 + 2: a brand-new save, the arrival card, its dismissal.
func arrival()->bool:
	var c:=card()
	check(c!=null and c.is_visible_in_tree(),"Arrival card visible on entering a brand-new save")
	check(Opening.is_new_arrival(snap(),me) and Opening.is_new_arrival(w.state,tok),"New arrival on client and server")
	check(card_text("ArrivalPlace")=="澎湖・望安","Place name: 「%s」"%card_text("ArrivalPlace"))
	check(card_text("ArrivalScene")=="風鈴渡口","Scene name: 「%s」"%card_text("ArrivalScene"))
	check(card_text("ArrivalBoat")=="你搭船來到澎湖・望安，在風鈴渡口下了船。","Boat sentence: 「%s」"%card_text("ArrivalBoat"))
	var line:=card_text("ArrivalLine")
	check(line.contains("小栗在渡口旁留了一塊地給你。") and line.contains("先種一株蘿蔔，收成後帶到出貨箱。"),"Both opening-line sentences: 「%s」"%line)
	var title:=app.hud.find_child("RegionTitle",true,false) as Label
	check(title!=null and title.is_visible_in_tree() and title.text=="風鈴渡口","HUD region title 風鈴渡口: 「%s」"%(title.text if title else "<none>"))
	expect_step("find","fresh save")
	await expect_tracker("%s\n去找小栗：種子攤東北邊的田\n%s 移動"%[HEADING,app.movement_hint()],"find")
	check(pos()==World.SPAWN and snap_pos()==World.SPAWN,"Player at SPAWN %s (server %s, client %s)"%[str(World.SPAWN),str(pos()),str(snap_pos())])
	# Expected start values from World.add_player's behaviour on a second fresh World.
	var probe:=World.new()
	probe.add_player("journey-probe","probe")
	var fresh:Dictionary=probe.state.players["journey-probe"]
	check(same(person().inventory,fresh.inventory) and same(snap_person().get("inventory",{}),fresh.inventory),"Starting inventory equals a fresh World.add_player: %s"%JSON.stringify(person().inventory))
	check(int(person().coins)==int(fresh.coins) and int(snap_person().get("coins",-1))==int(fresh.coins),"Starting coins equal a fresh add_player (%d)"%int(fresh.coins))
	check(Vector2(fresh.x,fresh.y)==World.SPAWN,"A fresh add_player also stands on SPAWN")
	check(Chapter.phase(w.state)=="grow" and Chapter.phase(snap())=="grow","Chapter phase grow")
	check(Opening.marker_shown(snap(),me) and Opening.marker_shown(w.state,tok),"Plot marker shown")
	# 2. Interact key closes the card and does nothing else.
	var counter:int=app.session.counter
	notices.clear()
	await key(bound("interact"))
	check(card()==null,"Interact key (%s) closes the card"%app.binding_label("interact"))
	check(app.modal==null and int(app.session.counter)==counter and notices.is_empty(),"Interact key did only that (no panel, no request, no notice)")
	await hud_tick()
	check(card()==null,"Card stays gone after HUD refreshes")
	check(pos()==World.SPAWN,"Still on SPAWN after closing the card")
	return true

## 3 + 4: walk to the plot, till/sow/water/wait/harvest with refusals.
func first_radish()->bool:
	var find:=Chapter.first_crop_step(snap(),me)
	var target:Vector2i=find.get("cell",Vector2i(-1,-1))
	check(target in Chapter.STARTER_PLOT,"Find step points at a starter-plot cell: %s"%str(target))
	# Plot geometry as STARTER_PLOT says.
	var rect:=Opening.plot_rect()
	check(rect==Rect2i(45,26,3,2) and Chapter.STARTER_PLOT.size()==6,"Starter plot is 45..47 × 26..27: %s"%str(rect))
	var stall:Vector2i=Chapter.STEPS.grow.cell
	for cell in Chapter.STARTER_PLOT:
		check(rect.has_point(cell),"Plot cell %s inside the rect"%str(cell))
		check(standable(cell),"Plot cell %s is open grass"%str(cell))
		check(not beside(cell).is_empty() or Chapter.STARTER_PLOT.any(func(o):return (o-cell).length_squared()==1),"Plot cell %s connects to walkable ground"%str(cell))
		check(cell.x>stall.x and cell.y<stall.y and maxi(absi(cell.x-stall.x),absi(cell.y-stall.y))<=4,"Plot cell %s is north-east of the stall %s, within 4 cells"%[str(cell),str(stall)])
	var outside:=0
	for cell in Chapter.STARTER_PLOT:outside+=beside(cell).size()
	check(outside>=6,"The plot has walkable ground around it (%d neighbour cells)"%outside)
	check(Chapter.starter_plot_free(w.state).size()==6,"All six plot cells free on a new save")
	# Walk there; a click on the plot from too far on the way.
	var stand_goals:=beside(target)
	var cells:=route(stand_goals)
	if not check(not cells.is_empty(),"Route from SPAWN to beside %s"%str(target)):return false
	var centre:=Vector2(target)+Vector2(0.5,0.5)
	var early:=-1
	for i in cells.size():
		if (Vector2(cells[i])+Vector2(0.5,0.5)).distance_to(centre)<=5.0:
			early=i
			break
	if not check(early>0,"Route passes a cell within 5 cells of the plot"):return false
	tracing=true
	trace.clear()
	if not await walk(cells,0,early,"to the plot (first leg)"):return false
	var gap:=pos().distance_to(centre)
	check(gap>3.2,"Still out of reach of %s (%.2f)"%[str(target),gap])
	expect_step("find","on the way (%.2f from the plot)"%gap)
	await refused_click("hoe",target,"靠近一點，才能和它互動","till from too far (%.2f cells)"%gap)
	if not await walk(cells,early,cells.size()-1,"to the plot (second leg)"):return false
	tracing=false
	var stand:Vector2i=cells.back()
	note("plot reached: %d cells from SPAWN to %s, trace=%s"%[cells.size()-1,str(stand),str(trace)])
	check(cells_walked==cells.size()-1,"Cells walked SPAWN -> plot: %d"%cells_walked)
	# Tracker find -> till on arrival, exactly once.
	var switched:=-1
	var monotone:=true
	for i in trace.size():
		var id:=str(trace[i][1])
		if id=="till" and switched<0:switched=i
		if switched>=0 and id!="till":monotone=false
		if switched<0 and id!="find":monotone=false
	check(switched>=0 and monotone,"Steps along the walk are find… then till… (%s)"%str(trace))
	if switched>=0:
		var at_cell:Vector2i=trace[switched][0]
		var at:=Vector2(at_cell)+Vector2(0.5,0.5)
		var prior:=World.SPAWN
		if switched>0:
			var prior_cell:Vector2i=trace[switched-1][0]
			prior=Vector2(prior_cell)+Vector2(0.5,0.5)
		var nearest_at:=INF
		var nearest_prior:=INF
		for cell in Chapter.STARTER_PLOT:
			nearest_at=minf(nearest_at,at.distance_to(Vector2(cell)+Vector2(0.5,0.5)))
			nearest_prior=minf(nearest_prior,prior.distance_to(Vector2(cell)+Vector2(0.5,0.5)))
		check(nearest_at<=Chapter.FIND_REACH and nearest_prior>Chapter.FIND_REACH,"Tracker switches to till on reaching %.1f cells of the plot (%.2f, before %.2f)"%[Chapter.FIND_REACH,nearest_at,nearest_prior])
	expect_step("till","arrived beside the plot")
	await expect_tracker("%s\n用鋤頭在小栗留的田翻一格土\n%s 鋤頭 · 點草地"%[HEADING,app.binding_label("hoe")],"till")
	check(pos().distance_to(centre)<=1.0,"Standing right beside %s"%str(target))
	# A second plot cell, still grass, within reach.
	var other:=Vector2i(-1,-1)
	for cell in Chapter.STARTER_PLOT:
		if cell!=target and pos().distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.0:
			other=cell
			break
	check(other!=Vector2i(-1,-1),"Another plot cell within reach: %s"%str(other))
	await refused_click("seed",other,"先用鋤頭開墾一格農田","sow on untilled grass")
	await refused_click("water",other,"請對農田澆水","water untilled grass")
	var k:="%d,%d"%[target.x,target.y]
	await done_click("hoe",target,"農田準備好了，接著選種子播種",{},["committed","crops","players.receipts"],"till")
	check(w.state.crops.has(k) and str(w.state.crops[k].owner)==tok and str(w.state.crops[k].kind)=="","Tilled %s is my empty plot"%k)
	expect_step("sow","after tilling")
	await expect_tracker("%s\n在翻好的土播下蘿蔔種子\n%s 播種 · %s 換種子"%[HEADING,app.binding_label("seed"),app.binding_label("seeds")],"sow")
	check(app.crop=="radish","Seed tool carries radish by default")
	await done_click("seed",target,"種下%s，記得澆水"%str(World.CROPS.radish.name),{"radish_seed":-1},["committed","crops","players.inventory","players.receipts"],"sow radish")
	expect_step("water","after sowing")
	await expect_tracker("%s\n替剛種下的作物澆水\n%s 澆水 · 點那一格"%[HEADING,app.binding_label("water")],"water")
	await done_click("water",target,"水分充足，幼苗會慢慢長大",{},["committed","crops","players.receipts"],"water")
	expect_step("wait","after watering")
	await expect_tracker("%s\n作物正在長大，等它成熟\n成熟前可以先逛逛"%HEADING,"wait")
	var left:=ceili(float(World.CROPS.radish.time)-float(w.state.crops[k].growth))
	await refused_click("harvest",target,"還沒成熟，再等 %d 秒"%left,"harvest an unripe radish")
	# While it grows: try the shipping bin before any harvest.
	var bin:=Shipping.cell_for(w.state)
	check(bin==Shipping.CELL and bin==Shipping.cell_for(snap()),"Shipping bin at %s"%str(bin))
	var t_walk:=float(w.state.time)
	if not await walk_to([bin+Vector2i(0,1)]+beside(bin),"to the bin while it grows"):return false
	check(float(w.state.time)>t_walk,"Walking took world time (%.2f s)"%(float(w.state.time)-t_walk))
	expect_step("wait","at the bin while growing")
	await key(bound("interact"))
	var panel=app.modal
	if check(panel is ShippingPanel,"Interact key at the bin opens the shipping panel (%s)"%str(panel)):
		check(not panel.slots.radish.visible and int(panel.inventory.get("radish",0))==0,"No radish to put in the basket yet")
		panel.tabs[1].pressed.emit()
		await frames(2)
		check(panel.category==1 and panel.empty_label.visible,"田園 tab is empty before any harvest")
		check(panel.cart.is_empty() and panel.confirm_button.disabled,"Nothing to confirm")
		await close_modal_with_esc("bin before harvest")
	# The panel guard holds; the server rule refuses the same wire payload too.
	var price:=int(Shipping.prices(World.CROPS,World.FISH,World.OTHER_SALES).radish)
	check(price==int(World.CROPS.radish.price),"Radish ships for its catalog price %d"%price)
	var state_before:Dictionary=w.state.duplicate(true)
	var bag_before:=bag()
	notices.clear()
	await create_timer(0.1).timeout
	app.session.perform("ship",bin,JSON.stringify([[["radish",1]],price]))
	actions+=1
	await frames(2)
	check(notices.size()==1 and str(last_notice()[0])=="持有數量已變更，請重新確認。" and last_notice()[1]==false,"ship before any harvest refused: %s"%str(notices))
	check(same(w.state,state_before) and same(bag(),bag_before),"ship before any harvest: whole world state unchanged (diff %s)"%str(diff_paths(state_before,w.state)))
	check(int(person().coins)==coins_before,"ship before any harvest: coins unchanged")
	rejections+=1
	note("refusal %d (ship before any harvest)"%rejections)
	# Back to the plot and let it grow.
	if not await walk_to([stand]+beside(target),"back to the plot"):return false
	var t_grow:=float(w.state.time)
	for i in 400:
		if float(w.state.crops[k].growth)>=float(World.CROPS.radish.time):break
		tick(WAIT_TICK)
		grow_seconds+=WAIT_TICK
	note("radish ripe after %.0f s of waiting (time %.1f -> %.1f), growth %.2f"%[grow_seconds,t_grow,float(w.state.time),float(w.state.crops[k].growth)])
	check(float(w.state.crops[k].growth)>=float(World.CROPS.radish.time),"Radish ripened (growth %.1f / %.1f)"%[float(w.state.crops[k].growth),float(World.CROPS.radish.time)])
	check(pos()==Vector2(stand)+Vector2(0.5,0.5),"Waiting did not move me")
	expect_step("harvest","ripe")
	await expect_tracker("%s\n作物熟了，用採收籃收成\n%s 採收 · 點成熟的作物"%[HEADING,app.binding_label("harvest")],"harvest")
	check(Chapter.phase(w.state)=="grow","Phase still grow before the harvest")
	var yield_n:=int(World.CROPS.radish.yield)
	await done_click("harvest",target,"收成了！%s +%d。可以出售或帶去做料理"%[str(World.CROPS.radish.name),yield_n],{"radish":yield_n},["chapter_one","committed","crops","island_crops_discoveries","ledger","players.collection","players.crops_discoveries","players.harvests","players.inventory","players.receipts"],"harvest")
	check(w.state.crops.has(k) and str(w.state.crops[k].kind)=="","Harvested plot stays my empty soil")
	check(int(person().harvests)==1,"One harvest on record")
	expect_step("ship","after the harvest")
	check(Chapter.phase(w.state)=="ship" and Chapter.phase(snap())=="ship","Chapter phase grow -> ship")
	await expect_tracker("✓ 第一株收成了\n把蘿蔔帶到出貨箱\n靠近出貨箱按 %s"%app.binding_label("interact"),"ship")
	check(Opening.marker_shown(snap(),me),"Plot marker still shown until the shipment")
	return true

## 5: the shipping flow.
func ship_radish()->bool:
	var bin:=Shipping.cell_for(w.state)
	if not await walk_to([bin+Vector2i(0,1)]+beside(bin),"to the bin with the radish"):return false
	expect_step("ship","at the bin")
	await key(bound("interact"))
	var panel=app.modal
	if not check(panel is ShippingPanel,"Interact key at the bin opens the shipping panel"):return false
	var price:=int(panel.prices.radish)
	check(price==int(World.CROPS.radish.price),"Panel price %d equals the catalog"%price)
	check(panel.slots.radish.visible,"Radish slot visible")
	var state_before:Dictionary=w.state.duplicate(true)
	var bag_before:=bag()
	var coins:=int(person().coins)
	panel.slots.radish.pressed.emit()
	await frames(2)
	check(panel.selected_id=="radish","Radish selected")
	panel.plus.pressed.emit()
	await frames(2)
	check(int(panel.cart.get("radish",0))==1 and panel.total_label.text=="預計收入  %d"%price,"Basket: radish ×1, %s"%panel.total_label.text)
	panel.confirm_button.pressed.emit()
	await frames(2)
	check(panel.reviewing and panel.confirm_button.text=="確認出貨 · %d 鈴幣"%price,"Review step: %s"%panel.confirm_button.text)
	check(same(w.state,state_before),"Reviewing sends nothing")
	notices.clear()
	await create_timer(0.1).timeout
	var counter:int=app.session.counter
	panel.confirm_button.pressed.emit()
	await frames(3)
	actions+=int(app.session.counter)-counter
	check(int(app.session.counter)==counter+1,"Confirm sent one ship request")
	check(notices.size()==1 and str(last_notice()[0])=="出貨完成，獲得 %d 鈴幣。"%price and last_notice()[1]==true,"Shipped: %s"%str(notices))
	check(not panel.pending and panel.cart.is_empty() and panel.notice.text=="出貨完成，獲得 %d 鈴幣。"%price,"Panel completes: %s"%panel.notice.text)
	coins_after=int(person().coins)
	check(coins_after==coins+price and int(snap_person().coins)==coins+price,"Coins %d -> %d (+%d, paid at once)"%[coins,coins_after,price])
	check(same(bag(),plus(bag_before,{"radish":-1})) and same(snap_bag(),bag()),"Bag: radish −1 only")
	var diff:=diff_paths(state_before,w.state)
	note("ship changed=%s"%str(diff))
	check(diff==["chapter_one","committed","ledger","players.coins","players.inventory","players.receipts","players.resident_participation"],"Ship changed only %s"%str(diff))
	check(bool(w.state.chapter_one.shipped) and Chapter.phase(w.state)=="works" and Chapter.phase(snap())=="works","Chapter phase ship -> works")
	check(Chapter.first_crop_step(w.state,tok).is_empty() and Chapter.first_crop_step(snap(),me).is_empty(),"first_crop_step is {} on server and client")
	check(not Opening.marker_shown(snap(),me) and not Opening.marker_shown(w.state,tok),"Plot marker off")
	await close_modal_with_esc("bin after shipping")
	await expect_tracker("讓渡口重新開飯\n修橋，讓配送重新出發\n木 %d/30 · 石 %d/10"%[int(w.state.donations.wood),int(w.state.donations.stone)],"next chapter step (works)")
	return true

## 6: save, reload in a plain World and in a fresh app; returning player.
func reload()->bool:
	var expected:Dictionary=person().duplicate(true)
	var chapter:Dictionary=w.state.chapter_one.duplicate(true)
	var t:=float(w.state.time)
	await close_app()
	var plain:=World.new()
	if not check(plain.load_world(path) and not plain.recovered_from_backup,"Save loads in a plain in-process World"):return false
	var again:Dictionary=plain.state.players.get(tok,{})
	for field in ["x","y","inventory","coins","harvests","region"]:
		check(same(again.get(field),expected.get(field)),"Plain reload keeps %s"%field)
	check(same(plain.state.chapter_one,chapter) and Chapter.phase(plain.state)=="works","Plain reload keeps the chapter state")
	check(absf(float(plain.state.time)-t)<0.001,"Plain reload keeps world time %.2f"%t)
	if not await open_app():return false
	await hud_tick()
	check(card()==null,"Returning player gets no arrival card")
	check(not Opening.is_new_arrival(snap(),me),"Not a new arrival any more")
	check(str(app.toast.text).begins_with("歡迎回來！"),"Returning player gets 歡迎回來: %s"%app.toast.text)
	for field in ["x","y","inventory","coins","harvests","region"]:
		check(same(person().get(field),expected.get(field)),"App reload keeps %s on the server"%field)
	check(snap_pos()==Vector2(float(expected.x),float(expected.y)) and same(snap_bag(),nonzero(expected.inventory)) and int(snap_person().coins)==int(expected.coins),"App reload: client position, bag and coins")
	check(same(w.state.chapter_one,chapter) and Chapter.phase(snap())=="works","App reload keeps the chapter state")
	await expect_tracker("讓渡口重新開飯\n修橋，讓配送重新出發\n木 %d/30 · 石 %d/10"%[int(w.state.donations.wood),int(w.state.donations.stone)],"after reload")
	return true

## 7: retained routes, read-only, on the same journey state.
func retained_routes()->void:
	check(not bool(w.state.picnic) and not bool(w.state.board),"Before the bridge and the picnic")
	# Notice board (works UI).
	if await walk_to([Vector2i(40,30),Vector2i(41,30),Vector2i(39,30)],"to the notice board"):
		await key(bound("interact"))
		var texts:=modal_texts()
		check(texts.has("渡口的共同工程") and texts.has("渡口修繕") and texts.has("捐入背包裡需要的材料"),"Interact key opens the works board: %s"%str(texts))
		# 群島的來信 (碼頭 / 合作小船) is only offered on the board after the 渡口野餐
		# (life_ui_tasks.board: `if s.get("picnic")`); before it the board has no dock entry.
		check(not texts.has("群島的來信"),"No 群島的來信 entry on the board before the picnic")
		await close_modal_with_esc("works board")
	# Dock repair page, stage 0 (direct read-only UI call: no entry point before the picnic).
	check(int(w.state.get("dock_stage",0))==0 and int(snap().get("dock_stage",0))==0,"dock_stage 0")
	LifeTasks.dock_project(app)
	await frames(3)
	var dock:=modal_texts()
	check(dock.has("第四章・群島的來信") and dock.has("修復渡口碼頭") and dock.has("渡口故事與田尾公共花園完成後，大家就能開始修碼頭。"),"Dock page in its stage-0 form: %s"%str(dock))
	var submit:=modal_button("交付這期工程材料")
	check(submit!=null and submit.disabled,"Stage-0 dock submit is disabled")
	for item in World.DOCK_REPAIRS[0]:check(World.NAMES.has(item),"Stage-0 cost item %s is named"%item)
	await close_modal_with_esc("dock page")
	# Boat / ferry.
	check(not Transit.boat_open(w.state) and not Transit.boat_open(snap()),"Transit.boat_open is false")
	check(TravelUI.HOME_LANYANG_MODE=="交通船" and Transit.HOME_FERRY_MODE=="交通船・轉乘","Route modes 交通船 / 交通船・轉乘")
	await travel_modal()
	# 風鈴節.
	check(not bool(w.state.festival.active) and not bool(snap().festival.active),"Festival not active")
	await key(bound("festival"))
	var fest:=modal_texts()
	check(is_instance_valid(app.modal) and str(app.modal.get_meta("life_modal_layout",""))=="festival_locked","Festival key opens the locked festival card")
	check(fest.has("完成公告板的渡口野餐後，即可開辦派對。") and fest.has("豐收接力・渡口野餐後開放"),"Festival pre-unlock copy: %s"%str(fest))
	await close_modal_with_esc("festival card")
	check(not bool(w.state.festival.active) and int(w.state.get("dock_stage",0))==0 and not bool(w.state.picnic),"Looking changed no route state")

func travel_modal()->void:
	await key(bound("map"))
	var atlas:=modal_button("台灣旅圖")
	if not check(atlas!=null,"Map key opens the local map with a 台灣旅圖 button"):
		if app.modal!=null:await close_modal_with_esc("map")
		return
	atlas.pressed.emit()
	await frames(4)
	if not check(is_instance_valid(app.modal) and app.modal.has_meta("travel_body"),"台灣旅圖 opens the travel modal"):
		if app.modal!=null:await close_modal_with_esc("map")
		return
	if true:
		var lanyang:=app.modal.find_child("SelectRoute_lanyang",true,false) as Button
		check(lanyang!=null and lanyang.text=="蘭陽試作田" and lanyang.button_pressed,"Travel modal lists 蘭陽試作田, selected from home")
		var ticket_texts:=ticket_labels()
		check(ticket_texts.has("交通船 · 這一站的新風景"),"蘭陽 ticket mode 交通船: %s"%str(ticket_texts))
		var status:=app.modal.find_child("DockTravelStatus",true,false) as Label
		check(status!=null and status.text=="碼頭待修 · 到公告板查看工程","Ferry status is the stage-0 copy: %s"%(status.text if status else "<none>"))
		var depart:=app.modal.find_child("TravelDepart",true,false) as Button
		check(depart!=null and depart.disabled,"Departure locked before the picnic")
		check(is_instance_valid(app.modal_feedback) and app.modal_feedback.text=="先完成渡口共餐，居民就會介紹這條路。","Lock message: %s"%(app.modal_feedback.text if is_instance_valid(app.modal_feedback) else "<none>"))
		var toucheng:=app.modal.find_child("SelectRoute_toucheng",true,false) as Button
		if check(toucheng!=null,"Travel modal lists 頭城"):
			toucheng.pressed.emit()
			await frames(3)
			var again:=ticket_labels()
			check(again.has("%s · 這一站的新風景"%Transit.HOME_FERRY_MODE),"頭城 ticket mode %s: %s"%[Transit.HOME_FERRY_MODE,str(again)])
		check(not Transit.boat_open(snap()) and not modal_texts().any(func(t):return str(t).contains("合作小船")),"No 合作小船 route offered at dock stage 0")
		await close_modal_with_esc("travel modal")
