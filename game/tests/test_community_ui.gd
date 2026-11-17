extends SceneTree
const UI=preload("res://scripts/community_ui.gd")
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0
func _initialize()->void:
	run.call_deferred()
func check(ok:bool, label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func button_at(node:Node, caption:String)->Button:
	if node==null:return null
	if node is Button and node.text==caption:return node
	for child in node.get_children():
		var found:=button_at(child,caption)
		if found!=null:return found
	return null
func fully_visible(control:Control)->bool:
	if control==null or not control.is_visible_in_tree():return false
	var parent:=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(control.get_global_rect()):return false
		parent=parent.get_parent()
	return true
func run()->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.menu.hide()
	app.hud.show()
	var world:=World.new()
	world.add_player("tester","島民")
	app.session.own_id="tester"
	app.session.snapshot=world.state
	UI.open(app)
	check(app.modal==null,"No dining UI before picnic")
	world.state.picnic=true
	world.state.board=true
	var saved_state:=world.state.duplicate(true)
	for size in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=size
		await process_frame
		UI.open(app)
		app._layout_preview()
		await process_frame
		await process_frame
		check(app.modal.get_meta("life_modal_layout")=="community_table" and Rect2(Vector2.ZERO,Vector2(size)).encloses(app.modal.get_global_rect()),"Community modal fits viewport")
		for route in ["渡口來信","生活訂單","風鈴接力","公共廚房"]:
			check(fully_visible(button_at(app.modal,route)),"Route is fully visible: "+route)
		app._close_modal()
		check(app.modal==null,"Closing returns to island")
		app.session.snapshot=world.state.duplicate(true)
		app.session.snapshot.order_board=world.order_board("tester")
		app._orders_menu()
		app._layout_preview()
		await process_frame
		await process_frame
		check(app.modal.get_meta("life_modal_layout")=="orders_board" and Rect2(Vector2.ZERO,Vector2(size)).encloses(app.modal.get_global_rect()),"Order board fits viewport")
		var accept:=button_at(app.modal,"接單")
		var deliver:=button_at(app.modal,"交件")
		check(fully_visible(accept) and not accept.disabled,"Open order exposes an enabled accept button")
		check(fully_visible(deliver) and deliver.disabled,"Unaccepted order cannot be delivered")
		app._close_modal()
		app.session.snapshot=world.state
	check(saved_state==world.state,"Viewing does not change inventory or world")
	app.session.snapshot.resident_memories=["xiaoli_c1_ledger"]
	app._journal()
	var memories:=button_at(app.modal,"居民回憶")
	check(memories!=null,"Journal exposes resident memories")
	if memories!=null:memories.pressed.emit()
	check(button_at(app.modal,"返回島民手帳")!=null,"Resident memories opens from the journal")
	check(button_at(app.modal,"重看風鈴節開幕")==null,"Unopened festival does not reveal the finale")
	app._close_modal()
	app.session.snapshot.festival_story={"opened":true}
	preload("res://scripts/life_ui_tasks.gd").resident_memories(app)
	var finale:=button_at(app.modal,"重看風鈴節開幕")
	check(finale!=null,"Late arrivals can replay the world finale in the journal")
	if finale!=null:finale.pressed.emit()
	check(button_at(app.modal,"返回居民回憶")!=null,"Finale replay returns to memories")
	var story_before:Dictionary=app.session.snapshot.duplicate(true)
	for step in range(3):
		var next:=button_at(app.modal,"下一幕")
		check(next!=null,"Festival replay offers its next scene")
		if next!=null:next.pressed.emit()
		var page:=app.modal.find_child("FestivalScenePage",true,false) as Label
		check(page!=null and page.text=="%d / 4"%[step+2],"Replay shows the position among all four scenes")
	check(button_at(app.modal,"下一幕")==null and button_at(app.modal,"上一幕")!=null,"Final scene ends the replay and allows previous scene")
	var previous:=button_at(app.modal,"上一幕")
	if previous:previous.pressed.emit()
	var restored_page:=app.modal.find_child("FestivalScenePage",true,false) as Label
	check(restored_page!=null and restored_page.text=="3 / 4" and button_at(app.modal,"下一幕")!=null,
		"Previous returns from the deer's epilogue to Xiaoli's scene")
	check(app.session.snapshot==story_before,"Replaying and paging through the finale do not modify the world")
	app._close_modal()
	app.session.snapshot.erase("festival_story")
	var preparation:Dictionary=app.session.snapshot.duplicate(true)
	preparation.festival_story={"opened":false,"projects":World.ISLAND_NOTES.project_mask(),"meal":false,"lights":1}
	app.session.receive_state(preparation,"tester")
	preload("res://scripts/life_ui_almanac.gd").festival_story(app)
	check(button_at(app.modal,"在公告板宣布開幕").disabled,"Festival remains unavailable while preparations are missing")
	var ready:=preparation.duplicate(true)
	ready.festival_story.meal=true
	ready.festival_story.lights=2
	app.session.receive_state(ready,"tester")
	check(button_at(app.modal,"在公告板宣布開幕").disabled,"Festival waits for Chapter Four")
	ready=ready.duplicate(true)
	ready.festival_story.boat_ready=true
	app.session.receive_state(ready,"tester")
	check(not button_at(app.modal,"在公告板宣布開幕").disabled,"Live preparation updates enable opening")
	var opened:=ready.duplicate(true)
	opened.festival_story.opened=true
	app.session.receive_state(opened,"tester")
	check(button_at(app.modal,"下一幕")!=null,"Receiving the opening update starts the first scene")
	app._close_modal()
	app.session.snapshot=world.state
	app.session.snapshot.dock_stage=1
	app._journal()
	var news:=button_at(app.modal,"島嶼近況")
	check(news!=null,"Journal exposes island news")
	if news!=null:news.pressed.emit()
	check(button_at(app.modal,"渡口近況標為已讀")!=null,"Unread ferry progress exposes an acknowledgment")
	check(button_at(app.modal,"居民回憶 · 1 段")!=null,"Island news links to the player's unlocked memories")
	var dock:=button_at(app.modal,"查看群島來信")
	check(dock!=null,"Island news links to the fourth chapter after the picnic")
	if dock!=null:dock.pressed.emit()
	check(button_at(app.modal,"交付這期工程材料")!=null,"Island news leads to the existing dock project")
	var back_to_news:=button_at(app.modal,"返回島嶼近況")
	check(back_to_news!=null,"Dock project can return to the originating panel")
	if back_to_news!=null:back_to_news.pressed.emit()
	check(button_at(app.modal,"居民回憶 · 1 段")!=null,"Returning restores the island news panel")
	app._close_modal()
	app.session.snapshot.erase("resident_memories")
	app.session.snapshot=world.state.duplicate(true)
	app.session.snapshot.players.tester.inventory.wood=24
	app.session.snapshot.players.tester.inventory.stone=13
	app.session.snapshot.players.tester.inventory.radish=6
	app.view.update_snapshot(app.session.snapshot,"tester")
	app.session.snapshot.players.other={"name":"米粒","x":42.5,"y":31.5}
	app.session.snapshot.own_trade={"id":"fixture","partner":"other","revision":1,
		"mine":{"items":{"wood":2,"radish":3},"coins":0},"theirs":{"items":{"stone":4},"coins":12},
		"i_confirmed":false,"they_confirmed":true}
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		await process_frame
		app._trade_menu()
		await process_frame
		await process_frame
		var confirm:=button_at(app.modal,"確認這版內容")
		check(fully_visible(confirm) and not confirm.disabled,"Trade with contents can be confirmed")
		await capture_trade("review-%d"%size.x)
		var edit:=button_at(app.modal,"修改交換內容")
		check(fully_visible(edit),"Trade has a visible edit entry")
		if edit!=null:edit.pressed.emit()
		await process_frame
		await process_frame
		check(fully_visible(button_at(app.modal,"送出交換內容")),"Trade editor opens with visible submit")
		await capture_trade("edit-%d"%size.x)
		var quantity:SpinBox=app.modal.find_children("*","SpinBox",true,false)[0]
		quantity.get_line_edit().grab_focus()
		var pad:=InputEventJoypadButton.new()
		pad.pressed=true
		pad.button_index=JOY_BUTTON_DPAD_RIGHT
		app.playing=true
		app._input(pad)
		check(quantity.value==1,"Controller increases focused trade coins")
		pad.button_index=JOY_BUTTON_DPAD_LEFT
		app._input(pad)
		check(quantity.value==0,"Controller decreases focused trade coins")
		pad.button_index=JOY_BUTTON_DPAD_DOWN
		app._input(pad)
		var item_field:Control=root.gui_get_focus_owner()
		check(item_field!=quantity.get_line_edit() and item_field.has_meta("trade_quantity"),"Controller moves from coins to an item quantity")
		var item_quantity:=item_field.get_parent() as SpinBox
		var initial:=item_quantity.value
		pad.button_index=JOY_BUTTON_DPAD_RIGHT
		app._input(pad)
		check(item_quantity.value==initial+1,"Controller changes the item quantity")
		pad.button_index=JOY_BUTTON_Y
		app._input(pad)
		check(root.gui_get_focus_owner().name=="TradeSubmit","Controller jumps from quantity to submit")
		app.playing=false
		app._close_modal()
	await verify_trade_submission(app)
	var actor: String=app.session.own_id
	app.session.perform("emote",Vector2i.ZERO,"hello")
	check(app.view.player_emotes.get(actor,{}).get("caption")=="你好！","Session displays the accepted emote")
	app.session.perform("emote",Vector2i.ZERO,"help")
	check(app.view.player_emotes.get(actor,{}).get("caption")=="你好！","Rapid emotes cannot replace the first")
	app.view.player_emotes.clear()
	app.mute_emotes=true
	app.session.receive_emote(actor,"home","thanks")
	check(app.view.player_emotes.is_empty(),"Muted emotes stay hidden")
	app.playing=true
	app._chat_menu()
	var field:=app.modal.find_child("IslandChatInput",true,false) as LineEdit
	check(root.gui_get_focus_owner()==field and app.movement_direction()==Vector2.ZERO,"Chat input owns focus and suspends movement")
	var tool: String=app.selected
	var shortcut:=InputEventKey.new()
	shortcut.keycode=KEY_8
	shortcut.physical_keycode=KEY_8
	shortcut.pressed=true
	app._unhandled_input(shortcut)
	check(app.selected==tool,"Typing a tool shortcut in chat leaves the tool unchanged")
	field.text_submitted.emit("一起修橋吧")
	check(app.island_messages.size()==1 and app.island_messages[0].ends_with("一起修橋吧"),"Chat reaches the local session with original text")
	app.session.perform("island_chat",Vector2i.ZERO,"再一則")
	check(app.island_messages.size()==1,"Fast repeat message is throttled")
	app.mute_chat=true
	app.session.receive_island_chat("home","米粒","測試靜音")
	check(app.island_messages.size()==1,"Muted chat does not enter history")
	app._close_modal()
	preload("res://scripts/life_ui_tasks.gd").island_notes(app)
	var draft:=app.modal.find_child("IslandNoteDraft",true,false) as LineEdit
	var notes:=app.modal.find_child("IslandNoteList",true,false) as VBoxContainer
	draft.text="下次一起修橋"
	draft.text_submitted.emit(draft.text)
	check(draft.text.is_empty() and notes.get_child_count()==1,"Confirmed note clears the draft and refreshes the board")
	draft.text="這則請保留"
	draft.text_submitted.emit(draft.text)
	check(draft.text=="這則請保留" and notes.get_child_count()==1,"Rate-limited note preserves the draft")
	app._close_modal()
	app.session.returning_peers[1]=true
	app.session.world.state.board=true
	app.session.world.state[World.WARM_SPRINGS.BATH_KEY]=true
	app.session.world.state.players.tester.x=46.5
	app.blueprint_join_scope="join:community-ui-return-test"
	app.session._send_snapshot(1)
	app._entered()
	check(app.modal!=null and app.modal.get_meta("life_modal_layout","")=="return_news","A returning resident with a new note sees the welcome digest")
	var preview_path:String=app.arg_value("return-news-preview","")
	if not preview_path.is_empty() and DisplayServer.get_name()!="headless":
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(preview_path)==OK,"Return digest preview saved")
	var details:=button_at(app.modal,"島嶼近況")
	if details!=null:details.pressed.emit()
	check(app.modal!=null and app.modal.find_child("LocalProjectNews",true,false)!=null,"The news board shows a completed local project")
	var read_projects:=button_at(app.modal,"標為已讀")
	if read_projects!=null:read_projects.pressed.emit()
	check(app.session.snapshot.island_news.seen==app.session.snapshot.island_news.completed,"Acknowledging news includes the local project without changing the festival checklist")
	preload("res://scripts/life_ui_tasks.gd").return_news(app,app.session.snapshot)
	var read_notes:=button_at(app.modal,"讀留言")
	if read_notes!=null:read_notes.pressed.emit()
	var acknowledge:=button_at(app.modal,"將這批留言標為已讀")
	check(acknowledge!=null and acknowledge.visible,"Return digest opens the live unread notes")
	if acknowledge!=null:acknowledge.pressed.emit()
	check(app.session.snapshot.island_news.notes_unread==0 and acknowledge!=null and not acknowledge.visible,"Acknowledgement updates the open board")
	app._close_modal()
	app.playing=false
	app.session.snapshot=World.new().state
	app.session.snapshot.chapter_one.merge({"shipped":true,"watered":true},true)
	app.session.snapshot.board=true
	app.session.snapshot.picnic=true
	app.session.snapshot.flower_nursery.garden.complete=true
	app.session.snapshot.can_start_large_projects=false
	app.LifeTasks.dock_project(app)
	check(button_at(app.modal,"宣布碼頭工程開工")==null and button_at(app.modal,"交付這期工程材料").disabled,"Member waits for dock launch")
	app.session.snapshot.can_start_large_projects=true
	app.LifeTasks.dock_project(app)
	check(not button_at(app.modal,"宣布碼頭工程開工").disabled,"Manager can launch dock with prerequisites")
	app.session.snapshot.can_start_large_projects=false
	app.session.snapshot.dock_project_started=true
	app.LifeTasks.dock_project(app)
	check(not button_at(app.modal,"交付這期工程材料").disabled,"Member can contribute after dock launch")
	app._close_modal()
	var placement_world:=World.new()
	placement_world.add_player("tester","島民")
	placement_world.state.players.tester.x=26.5
	placement_world.state.players.tester.y=22.5
	var floor_tile:=Vector2i(27,21)
	placement_world.state.ground[World.key(floor_tile)]={"type":"floor","owner":"tester","items":{},"placement_access":"owner"}
	app.session.snapshot=placement_world.state
	app.session.own_id="tester"
	app.selected="build"
	app.target=floor_tile
	app.view.show_target=true
	app._interact()
	var lock_floor:=button_at(app.modal,"只限地板主人")
	var share_floor:=button_at(app.modal,"開放同島玩家")
	check(lock_floor!=null and lock_floor.disabled and share_floor!=null and not share_floor.disabled,"Owned target opens the floor mode panel with current selection")
	var restrict_visit:=button_at(app.modal,"將戶外地塊設為僅屋主可進")
	check(restrict_visit!=null and not restrict_visit.disabled,"Outdoor floor opens plot visit controls")
	app._close_modal()
	placement_world.state.ground[World.key(floor_tile)].owner_visit=true
	app.view.show_target=true
	app._interact()
	var reopen_visit:=button_at(app.modal,"開放戶外地塊參觀")
	check(reopen_visit!=null and not reopen_visit.disabled,"Owner can release an outdoor plot restriction")
	app._close_modal()
	for y in range(20,24):
		for x in range(26,30):
			var cell_key:=World.key(Vector2i(x,y))
			if x in [26,29] or y in [20,23]:
				placement_world.state.objects[cell_key]={"type":"door" if x==27 and y==23 else "wall","owner":"tester","items":{}}
			elif cell_key!=World.key(floor_tile):
				placement_world.state.ground[cell_key]={"type":"floor","owner":"tester","items":{}}
	placement_world.add_player("guest-123456","同名")
	placement_world.add_player("guest-654321","同名")
	placement_world.state.ground[World.key(floor_tile)].visit_guest="guest-123456"
	app.view.show_target=true
	app._interact()
	var current_guest:=button_at(app.modal,"指定訪客 · 同名（123456）")
	var next_guest:=button_at(app.modal,"指定訪客 · 同名（654321）")
	check(current_guest!=null and current_guest.disabled and next_guest!=null and not next_guest.disabled
		and button_at(app.modal,"收回指定訪客權限")!=null,"Room UI distinguishes matching names and shows the selected visitor")
	app._close_modal()
	placement_world.state.objects[World.key(floor_tile)]={"type":"chair","owner":"tester","items":{}}
	app.selected="remove"
	app.view.show_target=true
	app._interact()
	check(button_at(app.modal,"開放同島玩家拆除")!=null,"Demolition mode opens the furniture permissions panel")
	app._close_modal()
	app.queue_free()
	await process_frame
	print("COMMUNITY_UI_TEST checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_trade_submission(app) -> void:
	var world:=World.new()
	world.add_player("tester","島民")
	world.add_player("partner","米粒")
	world.state.players.tester.inventory.wood=4
	var tile:=Vector2i.ZERO
	app.session.world=world
	app.session.peers[1]="tester"
	app.session.peers[2]="partner"
	app.session.sequences[1]=0
	app.session.rates[1]=[]
	app.session._send_snapshot(1)
	app.playing=true
	app.controller_navigation=true
	var pad:=InputEventJoypadButton.new()
	pad.pressed=true
	pad.button_index=JOY_BUTTON_START
	app._input(pad)
	await process_frame
	await process_frame
	var trade:Button=app.modal.find_child("PauseTrade",true,false)
	check(trade!=null,"Controller opens a pause menu with the trade entry")
	if trade==null:return
	for index in [JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_DOWN]:
		pad.button_index=index
		app._input(pad)
	check(root.gui_get_focus_owner()==trade,"Three D-pad presses reach island exchange in the pause grid")
	pad.button_index=JOY_BUTTON_A
	app._input(pad)
	var invite:=button_at(app.modal,"邀請 米粒 交換")
	check(invite!=null,"Trade lists the nearby partner")
	if invite==null:return
	await process_frame
	check(root.gui_get_focus_owner()==invite,"Trade list focuses the available invitation")
	app._input(pad)
	check(not world.trade_view("tester").is_empty(),"Controller A sends a trade invitation through Session")
	app._close_modal()
	pad.button_index=JOY_BUTTON_BACK
	app._input(pad)
	var edit:=button_at(app.modal,"修改交換內容")
	check(edit!=null,"Controller View opens the current exchange")
	if edit==null:return
	await process_frame
	check(root.gui_get_focus_owner()==edit,"Trade review starts on edit")
	pad.button_index=JOY_BUTTON_A
	app._input(pad)
	check(button_at(app.modal,"送出交換內容")!=null,"Controller A opens edit from review")
	pad.button_index=JOY_BUTTON_DPAD_RIGHT
	app._input(pad)
	pad.button_index=JOY_BUTTON_Y
	app._input(pad)
	pad.button_index=JOY_BUTTON_A
	app._input(pad)
	var updated:Dictionary=world.trade_view("tester")
	check(updated.mine.coins==1,"Controller submission reaches the local server")
	var confirm:=button_at(app.modal,"確認這版內容")
	await process_frame
	pad.button_index=JOY_BUTTON_DPAD_RIGHT
	app._input(pad)
	check(root.gui_get_focus_owner()==confirm,"D-pad moves from edit to confirm")
	pad.button_index=JOY_BUTTON_A
	app._input(pad)
	check(world.trade_view("tester").i_confirmed,"Controller confirms the edited revision")
	var payload:=JSON.stringify({"offer":updated.id,"revision":updated.revision})
	check(world.act("partner","pad-partner","trade_confirm",tile,payload).ok,"Partner confirmation settles the controller offer")
	check(world.state.players.tester.coins==119 and world.state.players.partner.coins==121,"Settlement transfers exactly the submitted amount")
	app._close_modal()
	app.playing=false

func capture_trade(stage: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--trade-capture="):continue
		await RenderingServer.frame_post_draw
		var path := arg.trim_prefix("--trade-capture=").path_join(stage+".png")
		check(root.get_texture().get_image().save_png(path)==OK,"Captured "+stage)
