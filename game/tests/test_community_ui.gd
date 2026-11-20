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
		check(deliver==null or deliver.disabled,"Unaccepted order cannot be delivered")
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
	await verify_festival_motion(app)
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
	await verify_live_project_news(app)
	await verify_live_story_news(app)
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
	# T046 phase 2: structure tools ask for the whole island, farm tools do not.
	app.selected="hoe"
	var farm_view:bool=app._structure_view_needed()
	app.selected="remove"
	var remove_view:bool=app._structure_view_needed()
	app.selected="build"
	check(not farm_view and remove_view and app._structure_view_needed(),"Build and remove tools hold the complete home view; a farm tool keeps the projection")
	var sent_before:int=app.session.counter
	var modal_before:Variant=app.modal
	app.session.snapshot["view_rect"]=[0,0,8,8]
	app.session.snapshot["view_full"]=false
	app.session.snapshot["view_level"]=2
	app._perform_build_action("build",floor_tile+Vector2i(1,0),"floor")
	check(app.session.counter==sent_before and is_same(app.modal,modal_before),"A build is not quoted or sent while ground, roofs and edges are still a projection")
	for mark in ["view_rect","view_full","view_level"]:app.session.snapshot.erase(mark)
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

func verify_live_project_news(app) -> void:
	var journal:Control=app.modal
	var world:World=app.session.world
	var local:Control=journal.find_child("LocalProjectNews",true,false)
	var public_read:=button_at(journal,"公共工程標為已讀")
	var local_read:=button_at(journal,"地方工程標為已讀")
	check(not local.is_visible_in_tree() and public_read.is_visible_in_tree(),"Only the bridge is visible on entry")
	var partner:Dictionary=world.state.players.partner
	var site:=World.RESIDENT_BOND.SPRING_CELL
	partner.region=World.RESIDENT_BOND.SPRING_REGION
	partner.x=site.x+0.5
	partner.y=site.y+1.5
	partner.bonds={"nuannuan":{"points":6,"talk_day":-1,"gift_day":-1}}
	partner.inventory.stone=12
	partner.inventory.clay=8
	partner[World.WARM_SPRINGS.CRACK_KEY]=World.WARM_SPRINGS.CRACK_MASK # The route is exercised in the dedicated pool test.
	var repaired:=world.act("partner","project-news-live",World.RESIDENT_GOALS.ACTION,site,"nuannuan:2::")
	check(repaired.ok,"The other resident completes the real remote bath repair: "+str(repaired.message))
	app.session._send_snapshot(1)
	check(app.modal==journal and local.is_visible_in_tree() and not local_read.disabled,"New local project appears while the same journal stays open")
	check(app.session.snapshot.region_id=="home" and not app.session.snapshot.players.has("partner".sha256_text().left(16)),"News arrives while the repairer remains in another region")
	var completed:=int(app.session.snapshot.island_news.completed)
	var public_bits:=completed & World.ISLAND_NOTES.project_mask()
	var local_bits:=completed & ~World.ISLAND_NOTES.project_mask()
	check(public_bits==1 and local_bits==(4<<World.ISLAND_NOTES.PROJECTS.size()),"Both regions supply the expected progress bits")
	app.session.rates[1]=[]
	public_read.pressed.emit()
	check(app.modal==journal and public_read.disabled and not local_read.disabled,"Acknowledging public news keeps the journal open and the local project unread")
	check(int(app.session.snapshot.island_news.seen)==public_bits,"Only the displayed public category was marked")
	var directory:String=app.arg_value("project-news-preview","")
	if not directory.is_empty() and DisplayServer.get_name()!="headless":
		var scroll:=local_read.get_parent().get_parent().get_parent().get_parent() as ScrollContainer
		for extent in [Vector2i(1024,640),Vector2i(1280,800)]:
			root.size=extent
			app._layout_preview()
			await process_frame
			await process_frame
			if scroll!=null:scroll.ensure_control_visible(local_read)
			await process_frame
			await RenderingServer.frame_post_draw
			check(fully_visible(local_read),"Local read control can be reached without cropping at %s"%str(extent))
			check(root.get_texture().get_image().save_png(directory.path_join("local-news-%d.png"%extent.x))==OK,"Capture the open journal at %s"%str(extent))
	local_read.pressed.emit()
	check(app.modal==journal and local_read.disabled and int(app.session.snapshot.island_news.seen)==completed,"Local acknowledgment applies in place")
	check(int(world.state.players.partner.get("news_seen",0))==0,"The other resident's read marker is independent")
	var path:="user://project-news-%d.json"%Time.get_ticks_usec()
	world.save_path=path
	var reopened:=World.new()
	check(world.save() and reopened.load_world(path) and int(reopened.state.players.tester.news_seen)==completed,"The two acknowledgments survive reloading the actual save")
	world.save_path=""
	DirAccess.remove_absolute(path)

func verify_live_story_news(app) -> void:
	var journal:Control=app.modal
	var world:World=app.session.world
	var original_picnic:bool=world.state.picnic
	var original_dock:int=world.state.get("dock_stage",0)
	var original_opened:bool=world.state.get("festival_story_open",false)
	world.state.picnic=true
	world.state.dock_stage=1
	app.session._send_snapshot(1)
	var entries:VBoxContainer=journal.find_child("FerryNewsEntries",true,false)
	var read:=journal.find_child("FerryNewsRead",true,false) as Button
	check(app.modal==journal and read.is_visible_in_tree() and entries.get_child(0).text=="新消息・渡口碼頭修好了","Open journal shows the new ferry milestone immediately")
	world.state.dock_stage=2
	world.state.festival_story_open=true
	app.session._send_snapshot(1)
	var replay:=journal.find_child("NewsFestivalReplay",true,false) as Button
	check(app.modal==journal and replay.is_visible_in_tree() and entries.get_meta("recap_entries").any(func(row):return row.id=="festival_opening" and row.new),"The festival notice and replay appear without reopening the journal")
	app.session.rates[1]=[]
	read.pressed.emit()
	check(app.modal==journal and not read.is_visible_in_tree() and int(world.state.players.tester.ferry_recap_seen)==World.ISLAND_STORY_RECAP.marker(world.state),"Mark the latest milestones read without closing the journal")
	check(not world.state.players.partner.has("ferry_recap_seen"),"The other player's ferry milestones are still unread")
	var directory:String=app.arg_value("project-news-preview","")
	if not directory.is_empty() and DisplayServer.get_name()!="headless":
		var scroll:=journal.find_child("ModalScroll",true,false) as ScrollContainer
		await process_frame
		await process_frame
		if scroll:scroll.ensure_control_visible(entries)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory.path_join("ferry-story-live.png"))==OK,"Capture live ferry stories")
	replay.pressed.emit()
	check(app.modal.find_child("FestivalScenePage",true,false).text.begins_with("1 /"),"Replay opens the first opening scene directly")
	button_at(app.modal,"下一幕").pressed.emit()
	check(app.modal.find_child("FestivalScenePage",true,false).text.begins_with("2 /"),"Advance the replay from the news page")
	button_at(app.modal,"返回島嶼近況").pressed.emit()
	check(app.modal.has_meta("live_island_news"),"The replay can return to the same news section")
	preload("res://scripts/life_ui_tasks.gd").return_news(app,app.session.snapshot)
	button_at(app.modal,"重看風鈴節開幕").pressed.emit()
	button_at(app.modal,"返回回島近況").pressed.emit()
	check(app.modal.get_meta("life_modal_layout","")=="return_news","The welcome card has a direct replay and return path")
	world.state.picnic=original_picnic
	world.state.dock_stage=original_dock
	world.state.festival_story_open=original_opened
	world.state.players.tester.erase("ferry_recap_seen")
	app.session._send_snapshot(1)

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

func verify_festival_motion(app)->void:
	const Almanac=preload("res://scripts/life_ui_almanac.gd")
	var original:bool=app.sound.reduced_motion
	var original_master:float=app.sound.master_volume
	var original_effects:float=app.sound.volume
	var destination:String=app.arg_value("festival-capture","")
	root.size=Vector2i(1024,640)
	app.sound.reduced_motion=false
	app.sound.master_volume=0.8
	app.sound.volume=0.4
	var expected_cues:=["warm_lantern","meal_serve","journal_page"]
	for index in range(3):
		Almanac.festival_story(app,true,index)
		app._layout_preview()
		await create_timer(0.3).timeout
		var art:=app.modal.find_child("FestivalOpeningArt",true,false) as Control
		check(fully_visible(art) and fully_visible(button_at(app.modal,"下一幕")),"Scene and its paging fit at 1024×640")
		if art==null:continue
		var first:int=art.frame
		check(art.scene_index==index and first<12,"The right moving tableau plays for each resident")
		check(art.voice==null,"No sound before the scene reaches its action")
		var area:=Rect2i(art.get_global_rect())
		var first_pixels:=PackedByteArray()
		var native:=DisplayServer.get_name()!="headless"
		if native:
			await RenderingServer.frame_post_draw
			first_pixels=root.get_texture().get_image().get_region(area).get_data()
		await create_timer(0.45).timeout
		check(art.frame>first,"The local animation advances on its own")
		var voice:AudioStreamPlayer=art.voice
		check(voice!=null and voice.stream==app.sound.sounds[expected_cues[index]],"The scene plays its own sound on the action")
		check(voice!=null and is_equal_approx(db_to_linear(voice.volume_db),0.32),"Story sounds follow master and effects gains")
		if native:
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image()
			check(image.get_region(area).get_data()!=first_pixels,"Animated pixels change inside the tableau")
			if not destination.is_empty():
				check(image.save_png(destination.path_join("opening-%d.png"%(index+1)))==OK,"Captured festival scene")
		var next:=button_at(app.modal,"下一幕")
		if next!=null:next.pressed.emit()
		check(voice!=null and not voice.playing,"Paging stops the outgoing scene sound")
	app.sound.reduced_motion=true
	root.size=Vector2i(1280,800)
	Almanac.festival_story(app,true,0)
	app._layout_preview()
	await create_timer(0.3).timeout
	var static_art:=app.modal.find_child("FestivalOpeningArt",true,false) as Control
	check(fully_visible(static_art) and static_art.reduced_motion and static_art.frame==12,"Reduced motion starts in the finished pose")
	check(static_art!=null and static_art.voice!=null,"Reduced motion still plays the scene cue")
	await create_timer(0.35).timeout
	check(static_art!=null and static_art.frame==12,"Reduced motion stays still")
	Almanac.festival_story(app,true,1)
	var closing_art:=app.modal.find_child("FestivalOpeningArt",true,false) as Control
	var closing_voice:AudioStreamPlayer=closing_art.voice if closing_art!=null else null
	check(closing_voice!=null and closing_voice.playing,"Reopening creates a fresh voice")
	app._close_modal()
	check(closing_voice!=null and not closing_voice.playing,"Closing the replay stops the cue immediately")
	app.sound.volume=0.0
	Almanac.festival_story(app,true,2)
	var muted:=app.modal.find_child("FestivalOpeningArt",true,false) as Control
	check(muted!=null and muted.voice==null,"Effects mute suppresses the scene cue")
	app.sound.reduced_motion=original
	app.sound.master_volume=original_master
	app.sound.volume=original_effects

func capture_trade(stage: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--trade-capture="):continue
		await RenderingServer.frame_post_draw
		var path := arg.trim_prefix("--trade-capture=").path_join(stage+".png")
		check(root.get_texture().get_image().save_png(path)==OK,"Captured "+stage)
