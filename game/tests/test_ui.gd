extends SceneTree
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0
var main
func expect(value:bool,text:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+text)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	expect(main.name_input.size.y<60,"name field stays one line")
	expect(main.name_input.global_position.y>200,"name field appears below title")
	expect(main.menu.visible and not main.hud.visible,"menu is initial screen")
	check_bounds(main.menu)
	var path:="user://ui-test-%d.json"%Time.get_ticks_usec()
	var err:int=main.session.host(0,"測試島民",path)
	expect(err==OK,"menu can enter world")
	await process_frame
	expect(main.playing and not main.menu.visible,"game replaces menu")
	var id:String=main.session.own_id
	var first:Dictionary=main.session.snapshot.duplicate(true)
	main.view.update_snapshot(first,id)
	main.view._process(0.1)
	var start:Vector2=main.view.display_positions[id]
	first.players[id].x+=1.0
	main.view.update_snapshot(first,id)
	main.view._process(0.05)
	expect(absf(main.view.display_positions[id].x-start.x-0.5)<0.01,"movement interpolates between snapshots")
	main.view._process(0.05)
	expect(absf(main.view.display_positions[id].x-start.x-1.0)<0.01,"movement finishes without endless trailing")
	main._select_tool("seed")
	expect(main.selected_label.text.contains("奶白蘿蔔"),"selected seed visible")
	main._build_menu()
	await process_frame
	check_bounds(main.modal)
	expect(main.modal!=null,"build panel opens")
	main._close_modal()
	main._inventory()
	await process_frame
	check_bounds(main.modal)
	main._close_modal()
	main._help()
	await process_frame
	check_bounds(main.modal)
	main._close_modal()
	main._shop()
	await process_frame
	check_bounds(main.modal)
	main._close_modal()
	# A real built rope rack opens Achao's private story pages through interact.
	var rack_world=main.session.world
	var rack_owner:Dictionary=rack_world.state.players[main.session.profile.token]
	var rack_cell:=Vector2i(38,34)
	rack_owner.inventory.rope=3
	main.session.rates[1].clear()
	main.session.perform("build",rack_cell,"rope_rack")
	expect(main.session.snapshot.objects.get("38,34",{}).get("type")=="rope_rack","Rope rack is placed through Session")
	main._interact()
	await process_frame
	expect(main.modal!=null and trade_book_contains("阿潮的關係事件"),"Using the rack opens Achao's event book")
	main._close_modal()
	main.session.perform("remove",rack_cell)
	expect(not main.session.snapshot.objects.has("38,34"),"Rope rack can be dismantled")
	main.session.rates[1].clear()
	# Perform a complete short farming loop through the same Session used by UI.
	main.session.perform("hoe",Vector2i(38,34))
	main.session.perform("seed",Vector2i(38,34),"radish")
	main.session.perform("water",Vector2i(38,34))
	main.session.world.step(91,true)
	main.session.perform("harvest",Vector2i(38,34))
	main._refresh_hud()
	expect(main.objective.text.contains("✓"),"harvest advances visible objective")
	main.session.perform("build",Vector2i(38,33),"floor")
	expect(main.session.snapshot.ground.has("38,33"),"build becomes visible snapshot")
	var w=main.session.world
	w.add_player("private-test-neighbor","鄰居")
	w.state.players["private-test-neighbor"].inventory.wood=30
	w.act("private-test-neighbor","private-build","build",Vector2i(37,33),"private_chest")
	w.act("private-test-neighbor","private-put","deposit",Vector2i(37,33),"wood")
	main.session._send_snapshot(1)
	expect(main.session.snapshot.objects["37,33"].items.is_empty(),"private chest contents are absent from another player's snapshot")
	expect(main.session.snapshot.objects["37,33"].locked,"private box is marked locked")
	expect(w.state.objects["37,33"].items.wood==1,"privacy filtering does not erase stored items")
	w.act(main.session.profile.token,"plant-ui","plant_tree",Vector2i(40,34))
	main.session._send_snapshot(1)
	expect(main.session.snapshot.forest["40,34"].owner==id,"tree ownership uses public identifier")
	expect(main.session.snapshot.crops["38,34"].owner==id,"crop ownership does not expose profile token")
	main._seed_menu()
	await process_frame
	check_bounds(main.modal)
	main._close_modal()
	main._select_tool("plant_tree")
	expect(main.selected_label.text.contains("樹苗"),"tree tool explains planting")
	main._map_menu()
	await process_frame
	check_bounds(main.modal)
	expect(main.map_view.data.players.has(id),"map includes own authoritative position")
	expect(main.map_view.get_global_rect().end.y<main.modal.get_global_rect().end.y,"map fits inside panel")
	main._close_modal()
	expect(main.map_view==null,"closing map releases its update reference")
	for resident in ["aru","milu"]:
		main._resident_menu(resident)
		await process_frame
		check_bounds(main.modal)
		main._close_modal()
	main._journal()
	await process_frame
	check_bounds(main.modal)
	main._close_modal()
	main._orders_menu()
	await process_frame
	check_bounds(main.modal)
	main._close_modal()
	main._cook_menu(Vector2i(38,33))
	await process_frame
	check_bounds(main.modal)
	main._close_modal()
	w.state.players[main.session.profile.token].inventory.wood=100
	main.session._send_snapshot(1);main.view._process(0.1)
	main.building="floor";main._select_tool("build")
	main.view.show_target=true;main.action_clock=0
	var press:=InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.shift_pressed=true
	press.position=main.view.screen(Vector2(37.5,35.5))*main.view.zoom
	main._unhandled_input(press)
	expect(main.area_drag,"shift press starts construction preview")
	var release:=InputEventMouseButton.new()
	release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false
	release.position=main.view.screen(Vector2(38.5,35.5))*main.view.zoom
	main._input(release)
	expect(not main.area_drag and w.state.ground.has("37,35") and w.state.ground.has("38,35"),"drag release places two tiles through session")
	expect(w.state.players[main.session.profile.token].inventory.wood==96,"drag charges exactly its tile count")
	main.action_clock=0;main._unhandled_input(press)
	release.position=Vector2(100,400);main._input(release)
	expect(not main.area_drag and w.state.players[main.session.profile.token].inventory.wood==96,"release over HUD cancels without charging or sticking")
	main.area_drag=true;main._inventory()
	expect(not main.area_drag,"opening a panel cancels drag")
	main._close_modal()
	w.state.picnic=true;w.state.board=true
	w.state.players[main.session.profile.token].x=40.5;w.state.players[main.session.profile.token].y=30.5
	main.session._send_snapshot(1)
	main._board()
	await process_frame
	check_bounds(main.modal)
	var fund_button:=main.modal.find_child("FundDonate10",true,false) as Button
	expect(fund_button!=null and not fund_button.disabled,"The board offers a ten-coin donation")
	if fund_button!=null and not fund_button.disabled:
		main.session.rates[1].clear()
		fund_button.pressed.emit()
		expect(main.session.snapshot.get("public_fund",{}).get("own_given",0)==10,"Board donation appears in the member snapshot")
		expect(not main.session.snapshot.public_fund.has("contributors"),"Snapshot omits private contribution keys")
	else:
		main._close_modal()
	main.session.perform("festival_start",Vector2i(40,29),"0")
	var bell:Vector2i=main.Festival.target(w.state.festival)
	w.state.players[main.session.profile.token].x=bell.x+0.5;w.state.players[main.session.profile.token].y=bell.y+0.5
	main.session._send_snapshot(1)
	main._interact()
	expect(w.state.festival.collected==1,"E collects nearby party bell through real session action")
	expect(main.session.snapshot.festival.contributors.has(id),"party contribution uses public identifier")
	expect(not main.session.snapshot.festival.contributors.has(main.session.profile.token),"party never reveals bearer identity")
	main._festival_menu()
	await process_frame
	check_bounds(main.modal)
	expect(main.modal.find_child("FestivalWatermelon",true,false)==null,"Relay food entry waits for the finish")
	main._close_modal()
	var party_player:Dictionary=w.state.players[main.session.profile.token]
	w.state.community={"table":World.COMMUNITY.choose_table(w.state)}
	while w.state.festival.active:
		bell=main.Festival.target(w.state.festival)
		party_player.x=bell.x+0.5
		party_player.y=bell.y+0.5
		w.state.time+=1.0
		var collected:Dictionary=w.act(main.session.profile.token,"relay-test-%d"%int(w.state.festival.collected),"festival_collect",bell,main.Festival.ticket(w.state.festival))
		expect(collected.ok,"Finish the relay through its normal collection action")
		if not collected.ok:break
	var table:=World.COMMUNITY.table_cell(w.state)
	party_player.x=table.x+0.5
	party_player.y=table.y+1.5
	party_player.inventory["watermelon_platter"]=4
	party_player.inventory["trout_hotpot"]=4
	party_player.inventory["corn_chowder"]=3
	main.session.rates[1].clear()
	main.session._send_snapshot(1)
	main._festival_menu()
	await process_frame
	var food:=main.modal.find_child("FestivalWatermelon",true,false) as Button
	expect(food!=null and not food.disabled and food.text=="上桌四份","Completed relay permits serving food at the table")
	if food!=null:food.pressed.emit()
	expect(w.state.community.get("watermelon",{}).get("portions",0)==4,"Serving from the relay uses the shared table")
	main._festival_menu()
	await process_frame
	food=main.modal.find_child("FestivalWatermelon",true,false) as Button
	expect(food!=null and not food.disabled and food.text=="領一片","Completed relay shows the claim action")
	if food!=null:food.pressed.emit()
	expect(w.state.community.get("watermelon",{}).get("portions",0)==3,"Claiming from the relay consumes only one portion")
	main._festival_menu()
	await process_frame
	var hotpot:=main.modal.find_child("FestivalHotpot",true,false) as Button
	expect(hotpot!=null and not hotpot.disabled,"Completed relay also offers hotpot serving")
	if hotpot!=null:hotpot.pressed.emit()
	expect(w.state.community.hotpot.portions==4 and w.state.community.watermelon.portions==3,"Relay shares two independent dishes with the dining table")
	main._festival_menu()
	await process_frame
	var chowder:=main.modal.find_child("FestivalChowder",true,false) as Button
	expect(chowder!=null and chowder.disabled,"Relay chowder requires four servings")
	main._close_modal()
	party_player.inventory.corn_chowder=4
	main.session._send_snapshot(1)
	main._festival_menu()
	await process_frame
	chowder=main.modal.find_child("FestivalChowder",true,false) as Button
	expect(chowder!=null and not chowder.disabled and chowder.text=="上桌四份","Relay offers chowder with four servings")
	if chowder!=null:chowder.pressed.emit()
	expect(w.state.community.get("chowder",{}).get("portions",0)==4 and int(party_player.inventory.get("corn_chowder",0))==0,"Serving moves four portions to the shared table")
	main._festival_menu()
	await process_frame
	chowder=main.modal.find_child("FestivalChowder",true,false) as Button
	expect(chowder!=null and not chowder.disabled and chowder.text=="領一碗","Relay offers one bowl once served")
	if chowder!=null:chowder.pressed.emit()
	expect(w.state.community.get("chowder",{}).get("portions",0)==3 and int(party_player.inventory.get("corn_chowder",0))==1,"Claim grants exactly one serving")
	main._festival_menu()
	await process_frame
	chowder=main.modal.find_child("FestivalChowder",true,false) as Button
	expect(chowder!=null and chowder.disabled and chowder.text=="已領取","Relay prevents a second claim")
	main._close_modal()
	main._pause_menu()
	await process_frame
	check_bounds(main.modal)
	main._close_modal()
	for zoom_value in [1.0,2.0]:
		main.view.zoom=zoom_value
		main.view._process(0.1)
		var screen_point:Vector2=main.view.screen(Vector2(38.5,34.5))*zoom_value
		expect(main.view.to_cell(screen_point)==Vector2i(38,34),"cursor matches grid at both fixed zoom levels")
	main._collection_menu()
	await process_frame
	check_bounds(main.modal)
	var locked:Button=find_button(main.modal,"再發現一些，慢慢來")
	if main.village_art_preview:
		expect(find_button(main.modal,"領取里程碑獎勵")==null,"incomplete milestones offer no reward action")
	else:expect(locked!=null and locked.disabled,"collection milestones initially show locked actions")
	main._close_modal()
	w.state.players[main.session.profile.token].collection.crops={"radish":true,"lettuce":true,"wheat":true}
	var coins_before:int=w.state.players[main.session.profile.token].coins
	main.session._send_snapshot(1)
	main._collection_menu()
	await process_frame
	var claim:Button=find_button(main.modal,"領取里程碑獎勵")
	expect(claim!=null and not claim.disabled,"eligible milestone exposes claim button")
	if claim:claim.pressed.emit()
	expect(main.modal==null,"claim closes panel while authoritative response is delivered")
	expect(w.state.players[main.session.profile.token].coins==coins_before+60,"UI milestone pays one exact reward through session")
	main._collection_menu()
	await process_frame
	var claimed:Button=find_button(main.modal,"✓ 已領取")
	if main.village_art_preview:
		var stamped:=false
		for control in main.modal.find_children("*","Label",true,false):
			if control.text=="✓ 已領取":stamped=true
		expect(stamped and find_button(main.modal,"領取里程碑獎勵")==null,"claimed milestone stamped and offers no repeat action")
	else:expect(claimed!=null and claimed.disabled,"completed milestone cannot be clicked again")
	main._close_modal()
	main._settings_menu()
	await process_frame
	check_bounds(main.modal)
	expect(find_button(main.modal,"保存偏好 · 試聽" if main.village_art_preview else "儲存設定並試聽")!=null,"comfort panel exposes deliberate save and preview")
	main._close_modal()
	await check_milu_cookbook()
	await check_trade_book()
	var good_path:String=main.session.world.save_path
	main.session.world.save_path="user://missing-ui-test-dir/sub/world.json"
	main.session._register(123,"failed-new-registration","測試")
	expect(not main.session.world.active_tokens.has("failed-new-registration"),"failed registration does not leave a ghost active player")
	expect(not main.session.shutdown(),"save failure does not silently close the world")
	expect(main.session.world!=null and not main.session.shutting_down,"world remains available for save retry")
	main.session.world.save_path=good_path
	expect(main.session.shutdown(),"retry can save and close normally")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	main.sound.close()
	await create_timer(0.15).timeout
	print("UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
func check_milu_cookbook() -> void:
	var w=main.session.world
	var token:String=main.session.profile.token
	var player:Dictionary=w.state.players[token]
	var at:Vector2i=World.bond_place(w.state,"milu")[1]
	player.x=at.x+1.5
	player.y=at.y+0.5
	if not player.has("bonds"):player.bonds={}
	player.bonds.milu={"points":24,"talk_day":-1,"gift_day":-1}
	main.session._send_snapshot(1)
	main._resident_menu("milu")
	await process_frame
	expect(main.modal.find_child("MiluCookbook",true,false)==null,"Milu's recipe book starts locked")
	main._close_modal()
	expect(w.act(token,"milu-book","resident_goal",at,"milu:4::").ok,"Earlier festival serving counts for Milu's event")
	main.session._send_snapshot(1)
	main._resident_menu("milu")
	await process_frame
	var entry:=main.modal.find_child("MiluCookbook",true,false) as Button
	expect(entry!=null,"Milu offers her cookbook after her final goal")
	if entry!=null:
		entry.pressed.emit()
		await process_frame
		expect(trade_book_contains("玉米濃湯") and trade_book_contains("甜玉米 ×2"),"Cookbook shows current recipe ingredients")
		await capture_trade_book("milu-cookbook")
		check_bounds(main.modal)
	main._close_modal()
	main._resident_menu("milu")
	await process_frame
	var apron:=main.modal.find_child("MiluApron",true,false) as Button
	expect(apron!=null and apron.text=="穿上米露的圍裙","Milu offers the apron after completion")
	if apron!=null:
		main.session.rates[1].clear()
		apron.pressed.emit()
		await process_frame
		expect(main.session.snapshot.players[main.session.own_id].get(World.RESIDENT_GOALS.APRON_KEY,false),"Apron appears in the player snapshot")
		await capture_trade_book("milu-apron")
	main._close_modal()

func check_trade_book() -> void:
	var w=main.session.world
	var player_token:String=main.session.profile.token
	expect(not main.session.snapshot.has("own_shop_history"),"Trade book starts locked")
	var stall:=Vector2i(43,29)
	var player:Dictionary=w.state.players[player_token]
	var neighbor:Dictionary=w.state.players["private-test-neighbor"]
	for person in [player,neighbor]:
		person.x=stall.x+0.5
		person.y=stall.y+0.5
		person.coins=500
	player.inventory.radish=1
	neighbor.inventory.pumpkin=1
	if not player.has("bonds"):player.bonds={}
	player.bonds.xiaoli={"points":1,"talk_day":-1,"gift_day":-1}
	expect(w.act("private-test-neighbor","secret-sale","sell",stall,"pumpkin").ok,"Neighbor makes a separate transaction")
	expect(w.act(player_token,"book-sell","sell",stall,"radish").ok,"Sale is journaled")
	expect(w.act(player_token,"book-buy","buy",stall,"potato").ok,"Seed purchase is journaled")
	var place:Vector2i=World.bond_place(w.state,"xiaoli")[1]
	player.x=place.x+0.5
	player.y=place.y+0.5
	expect(w.act(player_token,"book-unlock","resident_goal",place,"xiaoli:1::").ok,"Reporting to Xiaoli unlocks the book")
	main.session._send_snapshot(1)
	await process_frame
	var history:Array=main.session.snapshot.get("own_shop_history",[])
	expect(history.size()==2,"Only own sales and purchases appear in the book")
	if history.size()==2:
		expect(history[0].action=="buy" and int(history[0].coins)==-25 and history[0].items=={"potato_seed":1},"Recent purchase shows the exact price and seed")
		expect(history[1].action=="sell" and int(history[1].coins)==24 and history[1].items=={"radish":-1},"Older sale shows the exact proceeds and crop")
	main._shop()
	await process_frame
	var entry:=main.modal.find_child("ShopTradeBook",true,false) as Button
	expect(entry!=null,"The stall exposes the unlocked trade book")
	if entry==null:
		main._close_modal()
		return
	entry.pressed.emit()
	await process_frame
	expect(trade_book_contains("種子 12") and trade_book_contains("收成售價 24"),"Price page shows live catalog values")
	await capture_trade_book("prices")
	var history_tab:=main.modal.find_child("ShopTradeHistory",true,false) as Button
	expect(history_tab!=null,"Price page links to transaction history")
	if history_tab!=null:history_tab.pressed.emit()
	await process_frame
	expect(trade_book_contains("+24 鈴幣") and trade_book_contains("-25 鈴幣"),"History shows positive and negative money deltas")
	expect(not trade_book_contains("南瓜"),"The neighbor's crop never appears")
	await capture_trade_book("history")
	check_bounds(main.modal)
	main._close_modal()

func capture_trade_book(section:String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trade-book-capture=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var path:=arg.trim_prefix("--trade-book-capture=").path_join(section+".png")
			expect(root.get_texture().get_image().save_png(path)==OK,"Capture the trade book "+section)

func trade_book_contains(fragment:String) -> bool:
	for node in main.modal.find_children("*","Label",true,false):
		if node.text.contains(fragment):return true
	return false

func check_bounds(node:Node) -> void:
	if node is CanvasItem and not node.is_visible_in_tree():
		return
	if node is ScrollContainer:
		var bounds := Rect2(0, 0, 1281, 801)
		var scroll_rect: Rect2 = node.get_global_rect()
		var parent := node.get_parent()
		while parent != null:
			if parent is PanelContainer:
				bounds = bounds.intersection(parent.get_global_rect())
				break
			parent = parent.get_parent()
		expect(bounds.encloses(scroll_rect),"scroll viewport fits display and its containing panel: %s" % scroll_rect)
		return
	if node is Control and node.visible:
		var r:Rect2=node.get_global_rect()
		# Ignore decorative backgrounds and dynamic labels with unconstrained width.
		if node is Button or node is LineEdit or node is PanelContainer:
			expect(r.position.x>=0 and r.position.y>=0 and r.end.x<=1281 and r.end.y<=801,"control fits 1280x800: %s %s" % [node.name, r])
	for child in node.get_children():check_bounds(child)

func find_button(node:Node,text:String) -> Button:
	if node is Button and node.text==text:return node
	for child in node.get_children():
		var found:=find_button(child,text)
		if found:return found
	return null
