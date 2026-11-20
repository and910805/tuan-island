extends "res://tests/test_wangan_arrival_journey.gd"
## 望安第一件公共修繕 (headless, real app, one clean save, one player):
## 首次出貨後，玩家實際走到附近的樹與石頭、用斧頭／十字鎬敲到移除、走近撿起掉落物，
## 再到公告板用互動鍵開啟面板，先捐起始材料（部分），之後補足 30 木材／10 石材。
##
## SETUP only: the parent's open_app()/arrival()/first_radish()/ship_radish()/reload()
## are reused unchanged. Nothing here grants materials, coins, flags or positions, and
## no world state is written directly. Gathering uses the parent's walk_to + tool_click
## (held movement key, explicit Session ticks, real left clicks); donating presses the
## real interact key and emits pressed on the board's BoardDonateBridge button.
## Screenshots go to --capture-dir=<dir> (app.arg_value) and are skipped when headless.
const BOARD_STANDS:=[Vector2i(40,30),Vector2i(41,30),Vector2i(39,30)]
const NEED_WOOD:=30
const NEED_STONE:=10
const SEARCH_RADIUS:=16
const MAX_CANDIDATES:=30
const MAX_HITS:=6
const MAX_NODES:=6
const DONE_NOTICE:="公告板修好了"
const PARTIAL_NOTICE:="材料已捐入，謝謝你一起建設小島"
const DROP_NOTICE:="材料掉到地上了，走近就能撿起"

func open_app()->bool:
	if not await super.open_app():return false
	if app.arg_value("compact","")=="true":
		root.size=Vector2i(1024,640)
		await frames(5)
	return true

func run()->void:
	started_ms=Time.get_ticks_msec()
	create_timer(170.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 170 s")
		finish())
	path=OS.get_environment("TEMP").path_join("wangan-repair-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not check(not FileAccess.file_exists(path),"Save path is new"):
		finish()
		return
	paths.append(path)
	if not await open_app():
		finish()
		return
	time_start=float(w.state.time)
	coins_before=int(person().coins)
	check(not bool(w.state.board) and int(w.state.donations.wood)==0 and int(w.state.donations.stone)==0 and not w.state.has("gather_drops"),"Clean start: board unrepaired, no donations, no drops")
	await shot("01-arrival")
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
	await first_repair()
	time_now=float(w.state.time)
	finish()

## Saves an isolated frame of the real window; skipped headless or without --capture-dir.
func shot(name:String)->void:
	var dir:=str(app.arg_value("capture-dir",""))
	if dir.is_empty() or DisplayServer.get_name()=="headless":
		note("screenshot %s skipped"%name)
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await create_timer(0.35).timeout
	app.toast.hide()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(dir.path_join(name+".png"))==OK,"Capture "+name)

func open_board(label:String)->bool:
	if not await walk_to(BOARD_STANDS,"to the notice board "+label):return false
	await key(bound("interact"))
	await hud_tick()
	return check(is_instance_valid(app.modal) and str(app.modal.get_meta("life_modal_layout",""))=="community_board","Interact key opens the works board "+label)

func board_button()->Button:
	return app.modal.find_child("BoardDonateBridge",true,false) as Button if is_instance_valid(app.modal) else null

## Nearest tree/rock (by straight distance) that has a walkable neighbour; {} when none.
func find_target(kind:String)->Dictionary:
	var here:=Vector2i(pos())
	var found:Array=[]
	for y in range(here.y-SEARCH_RADIUS,here.y+SEARCH_RADIUS+1):
		for x in range(here.x-SEARCH_RADIUS,here.x+SEARCH_RADIUS+1):
			var c:=Vector2i(x,y)
			if w.resource(c)==kind and not w.water(c) and not w.protected(c):found.append(c)
	found.sort_custom(func(a:Vector2i,b:Vector2i):return Vector2(a-here).length_squared()<Vector2(b-here).length_squared())
	for i in mini(found.size(),MAX_CANDIDATES):
		var goals:=beside(found[i])
		if not goals.is_empty() and not route(goals).is_empty():return {"cell":found[i],"goals":goals}
	return {}

## Walk beside one resource, hit it with the real tool until gone, walk onto the drop and
## let session ticks pick it up. Returns false on any failure.
func gather_node(kind:String,tool:String)->bool:
	var target:=find_target(kind)
	if not check(not target.is_empty(),"A reachable %s exists near the village"%kind):return false
	var cell:Vector2i=target.cell
	var tile:=World.key(cell)
	var yields:Dictionary={"wood":6,"fiber":2,"sapling":1,"resin":1} if kind=="tree" else {"stone":5}
	if kind=="tree" and bool(w.state.forest.get(tile,{}).get("mature",false)):yields.hardwood=World.HARDWOOD_YIELD
	if not await walk_to(target.goals,"to the %s at %s"%[kind,str(cell)]):return false
	var before:=bag()
	var hits:=0
	for i in MAX_HITS:
		if w.resource(cell)=="":break
		notices.clear()
		if not await tool_click(tool,cell):return false
		hits+=1
		check(last_notice()[1]==true,"Hit %d on %s succeeded: %s"%[hits,str(cell),str(last_notice())])
	if not check(w.resource(cell)=="" and w.state.removed.has(tile),"The %s at %s is removed after %d hits"%[kind,str(cell),hits]):return false
	check(hits==(3 if kind=="tree" else 2),"%s needs %d normal hits (%d)"%[kind,3 if kind=="tree" else 2,hits])
	check(str(last_notice()[0]).get_slice("\n",0)==DROP_NOTICE,"Last hit drops the materials: %s"%str(last_notice()))
	check(w.state.get("gather_drops",{}).get("home",{}).has(tile) and same(bag(),before),"Materials lie on the ground, not yet in the bag")
	if not await walk_to([cell]+beside(cell),"onto the drop at %s"%str(cell)):return false
	for i in 8:
		if not w.state.get("gather_drops",{}).get("home",{}).has(tile):break
		tick(World.GATHER_DROP_DELAY+0.1)
	await frames(3)
	check(not w.state.get("gather_drops",{}).get("home",{}).has(tile),"Drop at %s was picked up by walking near it"%str(cell))
	var want:=plus(before,yields)
	check(same(bag(),want),"%s drop adds exactly %s: %s"%[kind,JSON.stringify(yields),JSON.stringify(bag())])
	check(same(snap_bag(),bag()),"Client bag follows the pickup")
	return true

func first_repair()->void:
	var start_bag:=bag()
	var start_coins:=int(person().coins)
	check(int(start_bag.get("wood",0))==12 and int(start_bag.get("stone",0))==4,"Starter materials are 12 wood and 4 stone: %s"%JSON.stringify(start_bag))
	check(not bool(w.state.board) and not bool(snap().board),"Board still unrepaired after the first sale")
	# --- partial: the starter materials only.
	if not await open_board("(partial)"):return
	var donate:=board_button()
	if not check(donate!=null and not donate.disabled and donate.text=="捐入 木材 12、石材 4","Board offers the starter materials: %s"%(donate.text if donate else "<none>")):return
	notices.clear()
	donate.pressed.emit()
	await frames(3)
	await hud_tick()
	check(notices.size()>=1 and str(last_notice()[0])==PARTIAL_NOTICE and last_notice()[1]==true,"Partial donation accepted: %s"%str(notices))
	check(int(w.state.donations.wood)==12 and int(w.state.donations.stone)==4 and int(snap().donations.wood)==12 and int(snap().donations.stone)==4,"Donations are 12 wood / 4 stone: %s"%str(w.state.donations))
	check(same(bag(),plus(start_bag,{"wood":-12,"stone":-4})) and same(snap_bag(),bag()),"Only 12 wood and 4 stone left the bag: %s"%JSON.stringify(bag()))
	check(not bool(w.state.board) and not bool(snap().board) and int(person().coins)==start_coins,"Board still open for work, coins unchanged")
	donate=board_button()
	check(donate!=null and donate.disabled and donate.text=="捐材料","Donate button waits for more materials: %s"%(donate.text if donate else "<none>"))
	var hint:=app.modal.find_child("BridgeDonationHint",true,false) as Label if is_instance_valid(app.modal) else null
	check(hint!=null and hint.text=="%s 砍樹　%s 敲岩石，走近撿材料。"%[app.binding_label("axe"),app.binding_label("pick")],"Board hints at gathering: %s"%(hint.text if hint else "<none>"))
	await shot("02-partial-donation")
	await close_modal_with_esc("partial donation board")
	var after_partial:=bag()
	# --- gather the remainder by hand.
	var trees:=0
	while int(bag().get("wood",0))<NEED_WOOD-int(w.state.donations.wood) and trees<MAX_NODES:
		if not await gather_node("tree","axe"):return
		trees+=1
	var rocks:=0
	while int(bag().get("stone",0))<NEED_STONE-int(w.state.donations.stone) and rocks<MAX_NODES:
		if not await gather_node("rock","pick"):return
		rocks+=1
	check(trees==3 and rocks==2,"Three trees and two rocks cover the rest (trees %d, rocks %d)"%[trees,rocks])
	var gathered:=bag()
	check(int(gathered.get("wood",0))==18 and int(gathered.get("stone",0))==10,"Gathered 18 wood and 10 stone: %s"%JSON.stringify(gathered))
	check(int(w.state.donations.wood)==12 and int(w.state.donations.stone)==4 and not bool(w.state.board),"Gathering alone changed no donation")
	# --- complete the requirement through the board again.
	if not await open_board("(complete)"):return
	donate=board_button()
	if not check(donate!=null and not donate.disabled and donate.text=="捐入 木材 18、石材 6","Board offers exactly the missing 18 wood and 6 stone: %s"%(donate.text if donate else "<none>")):return
	notices.clear()
	donate.pressed.emit()
	await frames(4)
	await hud_tick()
	check(notices.any(func(n):return str(n[0]).begins_with(DONE_NOTICE) and n[1]==true),"Final donation repairs the board: %s"%str(notices))
	check(int(w.state.donations.wood)==NEED_WOOD and int(w.state.donations.stone)==NEED_STONE and bool(w.state.board) and bool(snap().board),"Donations 30/10, board repaired on server and client")
	var expected_after:=plus(gathered,{"wood":-18,"stone":-6})
	check(same(bag(),expected_after) and same(snap_bag(),expected_after),"Exact cost 18 wood + 6 stone; rest of the bag untouched: %s"%JSON.stringify(bag()))
	check(int(person().coins)==start_coins and int(snap_person().get("coins",-1))==start_coins,"No coin reward or cost (coins %d)"%start_coins)
	for item in start_bag:
		if item!="wood" and item!="stone":check(int(bag().get(item,0))>=int(start_bag[item]),"Starter item %s is kept"%item)
	check(not w.state.get("gather_drops",{}).has("home"),"No drop is left on the ground")
	check(World.STONE_WORKSHOP.project_pending(w.state) and World.STONE_WORKSHOP.project_pending(snap()) and not World.STONE_WORKSHOP.bridge_open(w.state),"River bridge Q05 is still pending, bridge closed")
	check(w.state.events.any(func(e):return str(e).contains("公告板")),"The repair is in the island log")
	check_board_after("right after the repair")
	await shot("03-complete")
	var orders:=app.modal.find_child("BoardOrders",true,false) as Button
	if not check(orders!=null and orders.is_visible_in_tree(),"The repaired board offers an order entry"):return
	orders.pressed.emit()
	await frames(4)
	check(is_instance_valid(app.modal) and app.modal.get_meta("life_modal_layout","")=="orders_board","The new entry opens the real daily order board")
	await shot("04-life-orders")
	await close_modal_with_esc("daily orders")
	await hud_tick()
	check(str(app.objective.text).begins_with("讓農田自己喝水"),"The tracker advances to the irrigation lesson")
	# --- shutdown, real reload, read it back.
	var final_bag:=bag()
	var final_donations:Dictionary=w.state.donations.duplicate(true)
	await close_app()
	var plain:=World.new()
	check(plain.load_world(path) and not plain.recovered_from_backup and bool(plain.state.board) and same(plain.state.donations,final_donations),"Plain load of the saved game keeps the repair")
	if not await open_app():return
	await hud_tick()
	check(bool(w.state.board) and bool(snap().board) and same(w.state.donations,final_donations),"Reloaded app: board repaired, donations 30/10")
	check(same(bag(),final_bag) and same(snap_bag(),final_bag) and int(person().coins)==start_coins,"Reloaded app: bag and coins unchanged")
	check(World.STONE_WORKSHOP.project_pending(w.state) and World.STONE_WORKSHOP.project_pending(snap()),"Reloaded app: Q05 still pending")
	if await open_board("(after reload)"):
		check_board_after("after reload")
		await close_modal_with_esc("reloaded board")

## Board content once the notice board works: no donate button, a distinct Q05 card.
func check_board_after(label:String)->void:
	if not check(is_instance_valid(app.modal) and str(app.modal.get_meta("life_modal_layout",""))=="community_board","Works board is open "+label):return
	check(app.modal.find_child("BoardDonateBridge",true,false)==null,"No board donation button "+label)
	var card_node:=app.modal.find_child("BridgeProjectCard",true,false) as Control
	check(card_node!=null and card_node.is_visible_in_tree(),"Q05 河灣橋 card is shown "+label)
	var orders:=app.modal.find_child("BoardOrders",true,false) as Button
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	check(orders!=null and card_node!=null and orders.global_position.y<card_node.global_position.y,"The order entry is above the separate bridge project "+label)
	check(orders!=null and scroll!=null and scroll.get_global_rect().grow(1.0).encloses(orders.get_global_rect()),"The order entry is fully visible without scrolling "+label)
	var title:=app.modal.find_child("BridgeProjectTitle",true,false) as Label
	check(title!=null and title.text=="河對岸的鈴聲 · 河灣橋","Q05 card is titled apart from the board: %s"%(title.text if title else "<none>"))
	var note_line:=app.modal.find_child("BridgeFoundationHint",true,false) as Label
	check(note_line!=null and note_line.text.contains("生活訂單") and note_line.text.contains("河灣橋") and note_line.text.begins_with("公告板已修好"),"Board marks orders open and points to the separate bridge: %s"%(note_line.text if note_line else "<none>"))
	check(app.modal.find_child("BridgeProjectWood",true,false)!=null and app.modal.find_child("BridgeProjectRope",true,false)!=null,"Q05 wood and rope meters are present "+label)
