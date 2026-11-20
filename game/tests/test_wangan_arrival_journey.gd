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
func direction_is(d:Vector2,sent_after:int=-1)->bool:
	for i in 80:
		if Vector2(app.session.directions.get(1,Vector2(9,9)))==d and int(app.session.last_movement.get(1,0))>sent_after:return true
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
		var last_packet:=int(app.session.last_movement.get(1,0))
		hold(move_key(d))
		# Let the client refresh held input during long walks even when the simulated clock advances faster.
		await process_frame
		var handed:bool=await direction_is(Vector2(d),last_packet)
		if not check(handed,"%s: held %s reached the session as %s"%[label,OS.get_keycode_string(move_key(d)),str(d)]):
			release()
			return false
		for s in 4:tick(STEP_DT)
		cells_walked+=1
		var want:=Vector2(path_cells[index])+Vector2(0.5,0.5)
		if not check(pos().distance_to(want)<=0.001,"%s: cell %d is %s (at %s)"%[label,index,str(path_cells[index]),str(pos())]):
			release()
			return false
		# The final synthetic step may land between broadcasts. Publish that state
		# without advancing one more movement step past the cell centre.
		if snap_pos().distance_to(want)>0.001:app.session._send_snapshot(1)
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
	w.switch_region(w.player_region(tok))
	var cells:=route(goals)
	w.switch_region(World.REGIONS.HOME)
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
	var map_script=preload("res://scripts/island_map.gd")
	for stop in map_script.WANGAN_STOPS:
		if not await walk_to([stop[0]],str(stop[1])):
			break
		if stop[0]==World.WANGAN_COAST.SHELL_CELL:
			await key(bound("interact"))
			check(int(snap_bag().get(World.WANGAN_COAST.SHELL_ITEM,0))==1,"Low tide lets the player collect one shell")
			await key(bound("interact"))
			check(int(snap_bag().get(World.WANGAN_COAST.SHELL_ITEM,0))==1,"An immediate second gather does not grant a shell")
	if Vector2i(pos())==World.SEAWEED_CELL:
		var seaweed_before:=int(snap_bag().get("seaweed",0))
		await key(bound("interact"))
		check(int(snap_bag().get("seaweed",0))==seaweed_before+1,"Pressing the interaction key adds seaweed to the inventory")
		await key(bound("interact"))
		check(int(snap_bag().get("seaweed",0))==seaweed_before+1,"Pressing again during regrowth does not grant another frond")
		if await walk_to([Vector2i(50,58)],"南岸拋竿"):
			app.sound.standard_fishing=false
			if await tool_click("fish",Vector2i(50,59)):
				check(person().has("fishing"),"Clicking the south shore water casts the line")
				tick(3.1)
				await key(bound("fish_catch"))
				check(int(snap_bag().get("sardine",0))==1 and "sardine" in person().collection.fish,"Reeling lands a sardine and records it in the collection")
	await star_shore()
	if snap().get("wangan_star_walk",false):
		await dock_orders()
		await coastal_greenhouse()
	time_now=float(w.state.time)
	finish()

func dock_orders()->void:
	var coast:=World.WANGAN_COAST
	var pool:=coast.STAR_POOL.end-Vector2i.ONE
	if await tool_click("fish",pool):
		tick(3.1)
		await key(bound("fish_catch"))
	check(int(snap_bag().get("gold_shrimp",0))==2 and int(snap_bag().get("seaweed",0))==1,"Two tidepool casts and a shore gather supply the dock order")
	if not await walk_to([coast.DOCK_ORDERS],"回望安碼頭交貨"):return
	await key(bound("interact"))
	var card:Node=app.modal.find_child("DockOrder_dock_shrimp",true,false) if is_instance_valid(app.modal) else null
	if not check(card!=null,"Interacting with the dock opens its own order board"):return
	var accept:=card.find_child("OrderAccept",true,false) as Button
	if not check(accept!=null and not accept.disabled,"The dock order is available after the repair"):return
	accept.pressed.emit()
	await frames(3)
	card=app.modal.find_child("DockOrder_dock_shrimp",true,false) if is_instance_valid(app.modal) else null
	var deliver:=card.find_child("OrderDeliver",true,false) as Button if card else null
	if not check(deliver!=null and not deliver.disabled,"Accept stays on the dock board and stocked seafood enables delivery"):return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dock-orders-shot="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--dock-orders-shot="))==OK,"Capture the dock order board")
	var before:=int(person().coins)
	deliver.pressed.emit()
	await frames(3)
	check(int(person().coins)==before+110 and int(snap_bag().get("gold_shrimp",0))==0 and int(snap_bag().get("seaweed",0))==0,
		"The dock accepts the actual catch and pays the displayed reward")

func coastal_greenhouse()->void:
	var bench:=Vector2i(41,36)
	if not await walk_to([bench+Vector2i.DOWN],"帶晶砂回家園工作台"):return
	person().inventory.wood=20
	person().inventory.stone=5
	person().inventory.charcoal=1
	person().inventory.copper_joint=1
	app.session._send_snapshot(1)
	if not await choose_build("bench"):return
	await click(bench)
	if not check(w.state.objects.get(World.key(bench),{}).get("type")=="bench","A workbench is built through the normal build tool"):return
	await key(bound("interact"))
	var recipe:=modal_button("溫室玻璃")
	if not check(recipe!=null,"The workbench offers the greenhouse glass recipe"):return
	recipe.pressed.emit()
	await frames(3)
	var craft:=app.modal.find_child("CraftRecipe",true,false) as Button
	if not check(craft!=null and not craft.disabled,"Shore sand and charcoal enable glass production"):return
	craft.pressed.emit()
	await frames(4)
	check(int(snap_bag().get("glass",0))==2 and int(snap_bag().get("crystal_sand",0))==0 and bool(person().get("greenhouse_glass_crafted",false)),
		"The craft consumes the coastal sand and registers two glass and Xinghe's milestone")
	await close_modal_with_esc("coastal glass workbench")
	var farm:=Vector2i(-1,-1)
	for tile in Chapter.STARTER_PLOT:
		if w.state.crops.get(World.key(tile),{}).get("owner","")==tok:farm=tile;break
	if not check(farm.x>=0,"The early farming plot still belongs to this player"):return
	if not await walk_to(beside(farm),"回自己的農田搭玻璃棚"):return
	if not await choose_build("greenhouse_roof"):return
	await click(farm)
	check(w.state.roofs.get(World.key(farm),{}).get("type")=="greenhouse_roof" and int(snap_bag().get("glass",0))==0,
		"Placing the greenhouse canopy spends the crafted glass on the player's plot")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shore-glass-shot="):
			if not await walk_to([Vector2i(49,28)],"離開屋頂的剖面範圍"):return
			await create_timer(0.35).timeout
			app.activity_caption.hide()
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--shore-glass-shot="))==OK,"Capture the greenhouse made with coastal sand")
	await winter_harvest(farm)

func winter_harvest(farm:Vector2i)->void:
	var winter:=3*World.WEATHER.DAYS_PER_SEASON*World.WEATHER.DAY_SECONDS+480.0
	w.state.time=winter
	app.session._send_snapshot(1)
	check(not World.crop_grows_in_season("radish","home",farm,winter),"Winter is outside the uncovered radish growing season")
	if not await walk_to(beside(farm),"回到冬天的玻璃棚"):return
	app.crop="radish"
	if not await tool_click("seed",farm):return
	check(w.state.crops[World.key(farm)].kind=="radish","The new canopy accepts a radish seed during winter")
	if not await tool_click("water",farm):return
	tick(float(World.CROPS.radish.time)+0.1)
	if not await tool_click("harvest",farm):return
	check(person().get("greenhouse_cross_season_crop")=="radish" and int(snap_bag().get("radish",0))==1,"Harvest keeps the radish and records the protected winter crop")
	# Unlock the existing ferry without replaying the picnic and bridge projects.
	w.state.board=true
	w.state.picnic=true
	app.session._send_snapshot(1)
	if not await walk_to([Transit.STATIONS.home.cell],"到渡口準備去蘭陽"):return
	app._travel_menu()
	await frames(3)
	var depart:=app.modal.find_child("TravelDepart",true,false) as Button
	if not check(depart!=null and not depart.disabled,"The existing ferry can sail to Lanyang"):return
	depart.pressed.emit()
	await frames(5)
	if not check(snap().get("region_id")=="lanyang","The normal ticket brings the player to Lanyang"):return
	var service:=World.LANYANG_LIFE.SERVICE
	if not await walk_to([service+Vector2i.LEFT,service+Vector2i.RIGHT],"走到星禾的水圳"):return
	await key(bound("interact"))
	var report:=app.modal.find_child("GreenhouseReport",true,false) as Button if is_instance_valid(app.modal) else null
	if not check(report!=null and not report.disabled,"Xinghe accepts the actual winter harvest record"):return
	report.pressed.emit()
	await frames(4)
	check(person().get("greenhouse_reported",false),"Reporting marks the letter complete")
	check(int(snap_bag().get("radish",0))==1,"Sharing the record leaves the harvested radish with the player")
	var saved:=World.new()
	check(saved.load_world(path) and not saved.recovered_from_backup and saved.state.players[tok].get("greenhouse_reported",false),"Xinghe's letter remains complete after reopening the save")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--winter-report-shot="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--winter-report-shot="))==OK,"Capture Xinghe's response")
	await restore_canal()

func restore_canal()->void:
	var canal=World.LANYANG_LIFE
	await close_modal_with_esc("Xinghe's winter report")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--canal-nursery-shot="):
			await key(bound("map"))
			await RenderingServer.frame_post_draw
			var map_path:=arg.trim_prefix("--canal-nursery-shot=").get_base_dir().path_join("lanyang-canal-map.png")
			check(root.get_texture().get_image().save_png(map_path)==OK,"Capture the numbered canal map")
			await close_modal_with_esc("numbered canal map")
	if not await lanyang_water_round(8,true):return
	for cell:Vector2i in canal.BLOCKAGES:
		if not await walk_to([cell+Vector2i.LEFT,cell+Vector2i(2,0)],"走到水口 %s"%str(cell)):return
		await key(bound("interact"))
		var clear:=app.modal.find_child("ClearBlockage",true,false) as Button if is_instance_valid(app.modal) else null
		if not check(clear!=null and not clear.disabled,"The nearest blockage can be cleared from the bank"):return
		clear.pressed.emit()
		await frames(3)
		check(snap().lanyang_life.cleared.has(World.key(cell)),"Clearing updates this exact blockage")
		await close_modal_with_esc("cleared waterway")
	if not await walk_to([canal.SERVICE+Vector2i.LEFT],"帶材料回星禾的水圳"):return
	for item in canal.REPAIR_COST:person().inventory[item]=canal.REPAIR_COST[item]
	for item in canal.NURSERY_COST:person().inventory[item]=canal.NURSERY_COST[item]
	app.session._send_snapshot(1)
	await key(bound("interact"))
	var donate:=app.modal.find_child("CanalDonate",true,false) as Button if is_instance_valid(app.modal) else null
	if not check(donate!=null and not donate.disabled,"Clearing every blockage unlocks the sluice materials hand-in"):return
	donate.pressed.emit()
	await frames(3)
	check(snap().lanyang_life.repaired and int(snap_bag().get("plank",0))==0,"The repaired sluice consumes its materials and updates the shared project")
	var nursery:=modal_button("看看育苗盤")
	if not check(nursery!=null,"The canal page opens the nursery"):return
	nursery.pressed.emit()
	await frames(3)
	var start:=app.modal.find_child("NurseryStart",true,false) as Button
	if not check(start!=null and not start.disabled,"A player can start the nursery with the displayed materials"):return
	start.pressed.emit()
	await frames(3)
	check(int(snap_bag().get("sapling",0))==0 and app.modal.find_child("NurseryTime",true,false)!=null,"The seedling is invested in a timed batch")
	tick(canal.NURSERY_TIME+0.1)
	await frames(3)
	var claim:=app.modal.find_child("NurseryClaim",true,false) as Button
	if not check(claim!=null and not claim.disabled,"The same page offers three seedlings when the timer ends"):return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--canal-nursery-shot="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--canal-nursery-shot="))==OK,"Capture the finished nursery batch")
	claim.pressed.emit()
	await frames(3)
	check(int(snap_bag().get("sapling",0))==3,"Claiming the nursery harvest gives exactly three seedlings")
	await close_modal_with_esc("collected nursery seedlings")
	if await lanyang_water_round(12,false):await lanyang_sprinkler()

func lanyang_water_round(rate:int,place_devices:bool)->bool:
	var pump:=Vector2i(32,23)
	var pipe:=Vector2i(31,23)
	var tank:=Vector2i(30,23)
	if place_devices:
		if not await walk_to([Vector2i(31,22)],"到水圳上游架設河水泵"):return false
		for item in ["pump_kit","pipe_kit","tank_kit"]:person().inventory[item]=1
		app.session._send_snapshot(1)
		for device:Array in [["water_pump",pump],["water_pipe",pipe],["water_tank",tank]]:
			if not await choose_build(device[0]):return false
			await click(device[1])
			if not check(snap().objects.get(World.key(device[1]),{}).get("type")==device[0],"The player places "+device[0]):return false
	if not await walk_to([Vector2i(32,24)],"操作蘭陽河水泵"):return false
	await key(bound("interact"))
	var status:=app.modal.find_child("WaterDeviceStatus",true,false) as Label if is_instance_valid(app.modal) else null
	var toggle:=app.modal.find_child("WaterDeviceOperation",true,false) as Button if is_instance_valid(app.modal) else null
	if not check(status!=null and toggle!=null and "%d 格水"%rate in status.text,"The pump panel displays the actual regional flow rate"):return false
	var before:=int(snap().objects[World.key(tank)].water)
	toggle.pressed.emit()
	await frames(3)
	tick(World.INDUSTRY.INTERVAL+0.1)
	await frames(3)
	var added:=int(snap().objects[World.key(tank)].water)-before
	check(added==rate,"A connected tank receives %d water after one pump round"%rate)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lanyang-pump-shot=") and not place_devices:
			await hud_tick()
			check("已啟用" in status.text and "20／48" in status.text,"The pump panel refreshes to the new tank level")
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--lanyang-pump-shot="))==OK,"Capture the restored canal flow rate")
	toggle.pressed.emit()
	await close_modal_with_esc("water pump panel")
	return true

func lanyang_sprinkler()->void:
	var crop_cell:=Vector2i(28,23)
	var sprinkler:=crop_cell+Vector2i.RIGHT
	if not await walk_to([Vector2i(30,22)],"把水管接到農田灑水器"):return
	person().inventory.field_sprinkler_kit=1
	person().inventory.potato_seed=1
	app.session._send_snapshot(1)
	if not await choose_build("sprinkler"):return
	await click(sprinkler)
	if not await tool_click("hoe",crop_cell):return
	app.crop="potato"
	if not await tool_click("seed",crop_cell):return
	var crop_key:=World.key(crop_cell)
	if not check(not snap().crops.get(crop_key,{}).get("wet",false),"The new potato plot starts dry"):return
	if not await walk_to([Vector2i(29,22)],"啟用小型灑水器"):return
	await key(bound("interact"))
	var enable:=modal_button("啟用")
	if not check(enable!=null and not enable.disabled,"The installed sprinkler can be turned on from the device panel"):return
	enable.pressed.emit()
	await frames(3)
	tick(World.INDUSTRY.INTERVAL+0.1)
	await frames(3)
	check(snap().crops.get(crop_key,{}).get("wet",false),"Stored water reaches the sprinkler and waters the potato plot")
	await lanyang_forestry()

func lanyang_forestry()->void:
	await close_modal_with_esc("working sprinkler")
	var tree:=Vector2i(26,23)
	var saw:=Vector2i(25,23)
	if not await walk_to([Vector2i(26,22)],"到蘭陽的林地種樹"):return
	check(app.view.tree_planting_preview(tree).is_empty() and not app.view.tree_planting_preview(Vector2i(28,23)).is_empty(),
		"Planting preview distinguishes empty ground from the neighboring potato plot")
	if not await tool_click("plant_tree",tree):return
	check(snap().forest.has(World.key(tree)) and int(snap_bag().get("sapling",0))==2,"One of Xinghe's seedlings is planted")
	tick(World.TREE_TIME+0.1)
	await frames(3)
	check(snap().forest.get(World.key(tree),{}).get("mature",false),"The seedling grows into harvestable timber")
	var wood_before:=int(snap_bag().get("wood",0))
	var resin_before:=int(snap_bag().get("resin",0))
	var hardwood_before:=int(snap_bag().get("hardwood",0))
	for strike in 3:
		if not await tool_click("axe",tree):return
	if not await walk_to([tree],"走到樹旁撿起掉落木料"):return
	tick(World.GATHER_DROP_DELAY+0.1)
	await frames(3)
	check(not snap().forest.has(World.key(tree)) and int(snap_bag().get("wood",0))==wood_before+6
		and int(snap_bag().get("resin",0))==resin_before+1 and int(snap_bag().get("hardwood",0))==hardwood_before+World.HARDWOOD_YIELD,
		"Harvesting the tree yields wood, resin and hardwood")
	person().inventory.sawmill_kit=1
	app.session._send_snapshot(1)
	if not await choose_build("sawmill"):return
	await click(saw)
	if not await walk_to([Vector2i(25,22)],"到鋸木台加工蘭陽木材"):return
	await key(bound("interact"))
	var enqueue:=app.modal.find_child("ProcessingEnqueue",true,false) as Button if is_instance_valid(app.modal) else null
	if not check(enqueue!=null and not enqueue.disabled,"The sawmill accepts the harvested timber"):return
	enqueue.pressed.emit()
	await frames(3)
	tick(float(World.INDUSTRY.PROCESS.plank.time)+0.1)
	await hud_tick()
	var claim:=app.modal.find_child("ProcessingClaim",true,false) as Button
	if not check(claim!=null and not claim.disabled,"The cut planks are ready to collect"):return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lanyang-sawmill-shot="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--lanyang-sawmill-shot="))==OK,"Capture the completed sawmill batch")
	var planks_before:=int(snap_bag().get("plank",0))
	claim.pressed.emit()
	await frames(3)
	check(int(snap_bag().get("plank",0))==planks_before+2 and int(snap_bag().get("wood",0))==wood_before+2,
		"The sawmill converts four harvested wood into two planks")
	await lanyang_forester()

func lanyang_forester()->void:
	await close_modal_with_esc("claimed planks")
	var station:=Vector2i(23,23)
	var north:=World.key(station+Vector2i.UP*2)
	var station_key:=World.key(station)
	if not await walk_to([Vector2i(23,22)],"架設蘭陽林務工作站"):return
	person().inventory.forester_kit=1
	person().inventory.charcoal=1
	app.session._send_snapshot(1)
	if not await choose_build("forester"):return
	await click(station)
	await key(bound("interact"))
	var load_seed:=app.modal.find_child("ForestryLoad_sapling",true,false) as Button if is_instance_valid(app.modal) else null
	var load_fuel:=app.modal.find_child("ForestryLoad_charcoal",true,false) as Button if is_instance_valid(app.modal) else null
	if not check(load_seed!=null and load_fuel!=null and not load_seed.disabled and not load_fuel.disabled,"The forestry panel can load the nursery stock and charcoal"):return
	load_seed.pressed.emit()
	load_fuel.pressed.emit()
	var toggle:=modal_button("啟用")
	if not check(toggle!=null and not toggle.disabled,"The forestry station can be enabled from its own panel"):return
	toggle.pressed.emit()
	tick(World.FORESTRY.INTERVAL+0.1)
	check(snap().forest.has(north) and int(snap().objects[station_key].fuel)==1,"The station plants a nursery seedling without burning charcoal")
	tick(World.TREE_TIME+0.1)
	for cycle in 3:tick(World.FORESTRY.INTERVAL+0.1)
	await hud_tick()
	var device:Dictionary=snap().objects[station_key]
	check(int(device.fuel)==0 and int(device.items.get("wood",0))==6 and not snap().forest[north].mature,"Automatic harvest spends one charcoal and replants the tree")
	var collect:=app.modal.find_child("ForestryCollect",true,false) as Button
	if not check(collect!=null and not collect.disabled,"The completed automatic batch can be collected"):return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lanyang-forester-shot="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--lanyang-forester-shot="))==OK,"Capture the automatic forestry harvest")
	var wood_before:=int(snap_bag().get("wood",0))
	collect.pressed.emit()
	await frames(3)
	check(int(snap_bag().get("wood",0))==wood_before+6 and snap().objects[station_key].items.is_empty(),"The automated timber moves from the station to the bag exactly once")
	person().inventory.charcoal=1
	app.session._send_snapshot(1)
	await hud_tick()
	load_fuel.pressed.emit()
	await close_modal_with_esc("refueled forestry station")
	await lanyang_conveyor(station)

func lanyang_conveyor(station:Vector2i)->void:
	var belt:=station+Vector2i.RIGHT
	var saw:=belt+Vector2i.RIGHT
	person().inventory.conveyor_kit=1
	app.session._send_snapshot(1)
	if not await choose_build("conveyor"):return
	await click(belt)
	if not await walk_to([belt+Vector2i.UP],"調整輸送帶往鋸木台"):return
	await key(bound("interact"))
	var east:=modal_button("→")
	var activate:=modal_button("啟用")
	if not check(east!=null and activate!=null,"The conveyor opens with direction and power controls"):return
	east.pressed.emit()
	await hud_tick()
	var endpoints:=app.modal.find_child("ConveyorEndpoints",true,false) as Label
	check(endpoints!=null and "林務工作站" in endpoints.text and "自動加工未啟用" in endpoints.text,
		"The conveyor identifies the forestry source and an idle receiving sawmill")
	activate.pressed.emit()
	await close_modal_with_esc("enabled wood conveyor")
	if not await walk_to([saw+Vector2i.UP],"開啟鋸木台自動緩衝"):return
	await key(bound("interact"))
	var auto_tab:=app.modal.find_child("ProcessingAutoTab",true,false) as Button if is_instance_valid(app.modal) else null
	if not check(auto_tab!=null,"The sawmill offers its automatic processing tab"):return
	auto_tab.pressed.emit()
	await frames(3)
	var auto:=app.modal.find_child("ProcessingToggleAuto",true,false) as Button
	if not check(auto!=null and not auto.disabled,"An empty manual queue allows automatic processing"):return
	auto.pressed.emit()
	await frames(3)
	var wood_before:=int(snap_bag().get("wood",0))
	tick(World.TREE_TIME+0.1)
	for round_index in 4:tick(World.FORESTRY.INTERVAL+0.1)
	for transfer in 18:tick(World.LOGISTICS.INTERVAL+0.1)
	await hud_tick()
	var machine:Dictionary=snap().objects[World.key(saw)]
	check(machine.auto_enabled and int(machine.items.get("plank",0))==2 and int(snap_bag().get("wood",0))==wood_before,
		"Wood moves from the forester into automatic processing without passing through the bag")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lanyang-conveyor-shot="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--lanyang-conveyor-shot="))==OK,"Capture automatic plank production")
	await lanyang_plank_storage(saw)

func lanyang_plank_storage(saw:Vector2i)->void:
	var belt:=saw+Vector2i.RIGHT
	var chest:=belt+Vector2i.RIGHT
	var saw_key:=World.key(saw)
	var belt_key:=World.key(belt)
	var chest_key:=World.key(chest)
	await close_modal_with_esc("automatic sawmill")
	person().inventory.conveyor_kit=1
	person().inventory.wood=20
	app.session._send_snapshot(1)
	if not await choose_build("conveyor"):return
	await click(belt)
	if not await choose_build("private_chest"):return
	await click(chest)
	if not check(snap().objects.get(belt_key,{}).get("type")=="conveyor"
		and snap().objects.get(chest_key,{}).get("type")=="private_chest","The player builds the output belt and private chest"):return
	if not await walk_to([belt+Vector2i.UP],"設定成品輸送帶"):return
	await key(bound("interact"))
	var east:=modal_button("→")
	var plank:=app.modal.find_child("Filter_plank",true,false) as Button if is_instance_valid(app.modal) else null
	if not check(east!=null and plank!=null,"The output belt supports a plank filter"):return
	east.pressed.emit()
	plank.pressed.emit()
	await hud_tick()
	var objects:Dictionary=snap().objects
	check(objects[belt_key].dir==1 and objects[belt_key].filter=="plank","The plank belt points from the sawmill toward the chest")
	var bag_planks:=int(snap_bag().get("plank",0))
	for cycle in 2:tick(World.LOGISTICS.INTERVAL+0.1)
	objects=snap().objects
	check(not objects[belt_key].enabled and objects[belt_key].items.is_empty()
		and int(objects[saw_key].items.get("plank",0))==2 and objects[chest_key].items.is_empty(),
		"The stopped belt leaves both planks in the sawmill")
	var activate:=modal_button("啟用")
	if not check(activate!=null,"The configured plank belt can be enabled"):return
	activate.pressed.emit()
	tick(World.LOGISTICS.INTERVAL+0.1)
	check(int(snap().objects[belt_key].items.get("plank",0))==1,"The enabled belt picks up its first plank")
	for cycle in 4:tick(World.LOGISTICS.INTERVAL+0.1)
	objects=snap().objects
	check(objects[belt_key].items.is_empty() and int(objects[saw_key].items.get("plank",0))==0
		and int(objects[chest_key].items.get("plank",0))==2 and int(snap_bag().get("plank",0))==bag_planks,
		"Exactly two planks transfer to the chest without entering the backpack")
	var persisted:=World.new()
	check(persisted.load_world(path) and not persisted.recovered_from_backup
		and int(persisted.region_snapshot("lanyang").get("objects",{}).get(chest_key,{}).get("items",{}).get("plank",0))==2,
		"The primary save restores both planks in the Lanyang chest")
	await close_modal_with_esc("enabled plank conveyor")
	if not await walk_to([chest+Vector2i.UP],"查看木板入箱"):return
	await key(bound("interact"))
	if not check(is_instance_valid(app.modal) and app.modal.visible,"The player opens the private chest"):return
	var take_all:=app.modal.find_child("ChestWithdrawAll",true,false) as Button
	check(take_all!=null and not take_all.disabled and "2 件" in take_all.tooltip_text,
		"The private chest selects its two stored planks when opened")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lanyang-storage-shot="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--lanyang-storage-shot="))==OK,"Capture automatic plank delivery")
	await lanyang_large_sprinkler(chest)

func lanyang_large_sprinkler(chest:Vector2i)->void:
	await close_modal_with_esc("stocked plank chest")
	var bench:=chest+Vector2i.UP
	var chest_key:=World.key(chest)
	var bag:=person().inventory as Dictionary
	# PRESET: bench supplies, sprinkler metals and glass, a seed, and farm level.
	bag.wood=World.BUILD.bench.wood
	bag.stone=World.BUILD.bench.stone
	bag.iron_ingot=World.BUILD.large_sprinkler.iron_ingot
	bag.glass=World.BUILD.large_sprinkler.glass
	bag.potato_seed=1
	person().harvests=World.FARMING_LEVEL_THRESHOLDS[World.LARGE_SPRINKLER_LEVEL-1]
	app.session._send_snapshot(1)
	if not await walk_to([bench+Vector2i.UP],"到箱子北側設工作台"):return
	if not await choose_build("bench"):return
	await click(bench)
	if not check(snap().objects.get(World.key(bench),{}).get("type")=="bench","A workbench is built next to the plank output"):return
	await key(bound("interact"))
	var recipe:=modal_button("木工零件")
	if not check(recipe!=null,"The local workbench offers woodwork parts"):return
	recipe.pressed.emit()
	await frames(3)
	var craft:=app.modal.find_child("CraftRecipe",true,false) as Button
	if not check(craft!=null and not craft.disabled,"Handmade planks enable the first pair of parts"):return
	craft.pressed.emit()
	await hud_tick()
	if not check(int(snap_bag().get("woodwork_parts",0))==2 and int(snap_bag().get("plank",0))==0 and craft.disabled,
		"The first batch spends the backpack planks and a second batch needs a new source"):return
	var picker:Node=app.modal.find_child("MaterialSourcePicker",true,false)
	if not check(picker!=null and picker.select_cell(chest_key),"The workbench can select its neighboring private chest"):return
	await hud_tick()
	if not check(not craft.disabled and int(snap().objects[chest_key].items.get("plank",0))==2,
		"The chest supplies the missing planks without withdrawing them first"):return
	craft.pressed.emit()
	await hud_tick()
	if not check(int(snap_bag().get("woodwork_parts",0))==4 and int(snap_bag().get("plank",0))==0
		and int(snap().objects[chest_key].items.get("plank",0))==0,"The second batch spends exactly the two machine-made planks"):return
	await close_modal_with_esc("sourced woodworking")
	var sprinkler:=Vector2i(30,24)
	var crop_cell:=Vector2i(30,26)
	if not await walk_to([Vector2i(30,25)],"把木工零件用在蘭陽灌溉"):return
	if not await choose_build("large_sprinkler"):return
	await click(sprinkler)
	var sprinkler_key:=World.key(sprinkler)
	if not check(snap().objects.get(sprinkler_key,{}).get("type")=="large_sprinkler"
		and int(snap_bag().get("woodwork_parts",0))==0,"The four woodwork parts become a large sprinkler"):return
	if not await tool_click("hoe",crop_cell):return
	app.crop="potato"
	if not await tool_click("seed",crop_cell):return
	var crop_key:=World.key(crop_cell)
	if not check(not snap().crops[crop_key].wet,"The new plot two tiles away starts dry"):return
	await key(bound("interact"))
	var enable:=modal_button("啟用")
	if not check(enable!=null and not enable.disabled,"The new sprinkler can be enabled"):return
	enable.pressed.emit()
	tick(World.INDUSTRY.INTERVAL+0.1)
	await hud_tick()
	check(snap().crops[crop_key].wet,"The connected large sprinkler waters the distant potato plot")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lanyang-large-sprinkler-shot="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--lanyang-large-sprinkler-shot="))==OK,"Capture the linked irrigation expansion")

func choose_build(kind:String)->bool:
	app.life_panels.build_menu(app,kind)
	await frames(3)
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	if not check(place!=null and not place.disabled,"The builder can select "+kind):return false
	place.pressed.emit()
	await frames(3)
	return check(app.building==kind and app.selected=="build","The builder selects the correct placement tool")

func star_shore()->void:
	var coast:=World.WANGAN_COAST
	check(w.blocked(coast.STAR_SAND) and not snap().get("wangan_star_walk",false),"The unrepaired shore is closed to walking")
	var pool:=coast.STAR_POOL.end-Vector2i.ONE
	if not await walk_to([coast.STAR_REPAIR],"星砂步道工程"):return
	await key(bound("interact"))
	var repair:=app.modal.find_child("StarWalkRepair",true,false) as Button
	check(repair!=null and repair.disabled,"The project rejects an empty plank supply")
	await close_modal_with_esc("unfunded star shore project")
	person().inventory.plank=8
	person().inventory.fiber=4
	app.session._send_snapshot(1)
	await key(bound("interact"))
	repair=app.modal.find_child("StarWalkRepair",true,false) as Button
	if not check(repair!=null and not repair.disabled,"The project can be confirmed with enough materials"):return
	repair.pressed.emit()
	await frames(3)
	check(snap().get("wangan_star_walk",false) and int(snap_bag().get("plank",0))==0 and int(snap_bag().get("fiber",0))==0,"Repair opens the shore and consumes the displayed materials once")
	check(w.water(pool) and w.blocked(pool),"The restored tidepool is water and keeps its walking collision")
	check(not World.INDUSTRY.near_river(w,pool+Vector2i.RIGHT),"A saltwater tidepool does not supply a river pump")
	if not await walk_to([Vector2i(34,56),coast.STAR_SAND],"跨上星砂棧道"):return
	if not await walk_to([coast.STAR_SAND],"走到晶砂採集點"):return
	if not await walk_to([coast.STAR_SAND+Vector2i.LEFT],"潮池邊"):return
	await create_timer(0.35).timeout
	app.toast.hide()
	app.activity_caption.hide()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--star-shore-shot="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--star-shore-shot="))==OK,"Capture the repaired beach")
	await key(bound("interact"))
	check(int(snap_bag().get("crystal_sand",0))==1 and float(snap().wangan_star_sand_ready)>float(snap().time),"Gathering grants glassmaking sand and starts shared regrowth")
	var persisted:=World.new()
	check(persisted.load_world(path) and not persisted.recovered_from_backup,"The coastal project reloads from the primary save")
	check(persisted.state.wangan_star_walk and is_equal_approx(float(persisted.state.wangan_star_sand_ready),float(snap().wangan_star_sand_ready)),"The repair and sand availability survive reload")
	tick(World.WANGAN_COAST.STAR_SAND_RESPAWN)
	await key(bound("interact"))
	check(int(snap_bag().get("crystal_sand",0))==2,"The replenished shore supplies the second glassmaking sand")
	if not await walk_to([pool+Vector2i(2,0)],"星砂潮池拋竿"):return
	if await tool_click("fish",pool):
		check(person().has("fishing"),"The pool accepts a cast from the dry bank")
		tick(3.1)
		await key(bound("fish_catch"))
		check(int(snap_bag().get("gold_shrimp",0))==1 and "gold_shrimp" in person().collection.fish,"The tidepool produces gold shrimp and records it in the collection")

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
	await expect_tracker("%s\n%s"%[HEADING,World.CHAPTER_ONE.FIND_FROM_DOCK],"find")
	var landing:=World.WANGAN_COAST.FERRY_LANDING
	check(pos()==landing and snap_pos()==landing,"Player arrives at the ferry dock in both the server and client")
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
	check(pos()==landing,"Still on the dock after closing the card")
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
		var prior:=World.WANGAN_COAST.FERRY_LANDING
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
	await done_click("water",target,"水分充足 · 照料 1／5",{},["committed","crops","players.crop_care","players.receipts"],"water")
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
	await done_click("harvest",target,"收成了！%s +%d。可以出售或帶去做料理"%[str(World.CROPS.radish.name),yield_n],{"radish":yield_n},["chapter_one","committed","crops","island_crops_discoveries","ledger","players.collection","players.collection_acquired","players.crops_discoveries","players.harvests","players.inventory","players.receipts"],"harvest")
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
	check(diff==["chapter_one","committed","ledger","players.coins","players.first_crop_trade","players.inventory","players.receipts","players.resident_participation","players.wangan_personal_start","players.xiaoli_first_trade"],"Ship changed only the shipping and story fields: %s"%str(diff))
	var first_sale:Dictionary=person().get(World.TRANSACTION_LEDGER.FIRST_SHOP_KEY,{}).get("sale",{})
	check(int(first_sale.get("coins",0))==price and same(first_sale.get("items",{}),{"radish":-1}),"Xiaoli's first-sale receipt keeps the price and the shipped radish")
	check(person().get(World.RESIDENT_GOALS.CROP_TRADE_KEY)==World.RESIDENT_GOALS.CROP_SOLD,"First shipment records the sale for Xiaoli")
	check(bool(w.state.chapter_one.shipped) and Chapter.phase(w.state)=="works" and Chapter.phase(snap())=="works","Chapter phase ship -> works")
	check(Chapter.first_crop_step(w.state,tok).is_empty() and Chapter.first_crop_step(snap(),me).is_empty(),"first_crop_step is {} on server and client")
	check(not Opening.marker_shown(snap(),me) and not Opening.marker_shown(w.state,tok),"Plot marker off")
	await close_modal_with_esc("bin after shipping")
	await expect_tracker("修好渡口公告板\n到公告板按 %s 捐材料\n木材 %d/30 · 石材 %d/10"%[app.binding_label("interact"),int(w.state.donations.wood),int(w.state.donations.stone)],"next chapter step (works)")
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
	await expect_tracker("修好渡口公告板\n到公告板按 %s 捐材料\n木材 %d/30 · 石材 %d/10"%[app.binding_label("interact"),int(w.state.donations.wood),int(w.state.donations.stone)],"after reload")
	return true

## 7: retained routes, read-only, on the same journey state.
func retained_routes()->void:
	check(not bool(w.state.picnic) and not bool(w.state.board),"Before the bridge and the picnic")
	# Notice board (works UI).
	if await walk_to([Vector2i(40,30),Vector2i(41,30),Vector2i(39,30)],"to the notice board"):
		await key(bound("interact"))
		var texts:=modal_texts()
		var donate:Button=app.modal.find_child("BoardDonateBridge",true,false) if is_instance_valid(app.modal) else null
		check(texts.has("渡口的共同工程") and texts.has("渡口修繕") and donate!=null,"Interact key opens the works board: %s"%str(texts))
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
