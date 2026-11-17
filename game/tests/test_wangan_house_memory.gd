extends SceneTree

const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const Memory=World.WANGAN_MEMORY
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(condition:bool,message:String)->void:
	checks+=1
	if condition:return
	failures+=1
	push_error(message)

func capture(file_name:String)->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func run()->void:
	var app=Main.instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640)
	await process_frame
	app.session.profile.token=Crypto.new().generate_random_bytes(24).hex_encode()
	var path:="user://wangan-memory-%d.json"%OS.get_process_id()
	if app.session.host(0,"花宅訪客",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	expect(not world.act(token,"outside-visit","wangan_house_record",Memory.SITE,Memory.ANSWER).ok,"From far away the activity refuses to collect")
	var person:Dictionary=world.state.players[token]
	var dock:=World.RESIDENT_BOND.dock_cell(world.state)
	person.x=dock.x+0.5
	person.y=dock.y+0.5
	expect(not world.act(token,"closed-dock-log",Memory.LOG_ACTION,dock).ok,"The harbor story waits for the repaired pier")
	world.state.dock_stage=1
	expect(not world.act(token,"missing-memories",Memory.LOG_ACTION,dock).ok,"Both observations are required before the harbor story")
	person.x=Memory.SITE.x+0.5
	person.y=Memory.SITE.y+0.5
	expect(world.can_stand(Vector2(person.x,person.y)),"The pier site is reachable")
	app.session._send_snapshot(1)
	app.WanganUI.dismiss(app)
	app._interact()
	await process_frame
	var option:Button=app.modal.find_child("WanganAnswer_"+Memory.ANSWER,true,false) if is_instance_valid(app.modal) else null
	expect(option!=null,"The world observation sign opens the playable history page")
	expect(not world.act(token,"wrong-answer",Memory.ACTION,Memory.SITE,"granite_marble").ok
		and not person.has(Memory.KEY),"Wrong material does not count")
	await capture("wangan-house-memory.png")
	app._close_modal()
	var wall:=Memory.COURT.position
	var wall_key:=World.key(wall)
	expect(world.blocked(wall) and world.protected(Memory.COURT_SIGN),"The old house has collision and the public yard cannot be built on")
	world.state.ground[wall_key]={"type":"floor"}
	expect(not Memory.courtyard_available(world.state) and not world.blocked(wall) and not world.protected(Memory.COURT_SIGN),"An older player's floor takes priority over the new public yard")
	world.state.ground.erase(wall_key)
	var sign_center:=Vector2(Memory.COURT_SIGN)+Vector2(0.5,0.5)
	person.x=sign_center.x
	person.y=sign_center.y-1.0
	world.move_player(token,Vector2.DOWN,0.25/3.6)
	expect(world.can_stand(Vector2(person.x,person.y)),"A character saved under the new house can walk out")
	person.x=sign_center.x-2.0
	person.y=sign_center.y
	for step in 8:
		world.move_player(token,Vector2.RIGHT,0.25/3.6)
	expect(Vector2(person.x,person.y).is_equal_approx(sign_center),"Walk from the west lane into the old house yard")
	app.session._send_snapshot(1)
	await create_timer(0.35).timeout
	await capture("wangan-courtyard.png")
	app._interact()
	await process_frame
	option=app.modal.find_child("WanganAnswer_"+Memory.ANSWER,true,false) if is_instance_valid(app.modal) else null
	expect(option!=null,"The stone samples in the yard open the history page")
	if option:option.pressed.emit()
	await process_frame
	expect(app.session.snapshot.get("own_wangan_house",false) and not app.session.snapshot.players[app.session.own_id].has(Memory.KEY),"The record appears only through the viewer's personal summary")
	expect(not world.act(token,"duplicate-answer",Memory.ACTION,Memory.SITE,Memory.ANSWER).ok,"The completed memory is recorded once")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.players.get(token,{}).get(Memory.KEY,false),"The memory survives loading a new world")
	person.x-=2.0
	expect(not world.act(token,"weir-too-far",Memory.WEIR_ACTION,Memory.WEIR_SITE,"high").ok,"The tide record needs an on-site visit")
	person.x=Memory.WEIR_SITE.x+0.5
	person.y=Memory.WEIR_SITE.y+0.5
	expect(world.can_stand(Vector2(person.x,person.y)),"The weir observation point is reachable")
	app._close_modal()
	var coast:=World.WANGAN_COAST
	world.state.time=coast.TIDE_SECONDS*0.75-1.1
	app.session._send_snapshot(1)
	app._interact()
	await process_frame
	var observe:Button=app.modal.find_child("WanganWeirObserve",true,false) if is_instance_valid(app.modal) else null
	expect(observe!=null and observe.text=="記下漲潮" and observe.disabled,"At low tide the first observation stays disabled")
	var clock:Label=app.modal.find_child("WanganWeirTideClock",true,false) if is_instance_valid(app.modal) else null
	expect(clock!=null and clock.text=="漲潮 0:02 後","The field page shows the next transition")
	expect(world.step(1.0,true),"The game clock advances while the field page is open")
	app.session._send_snapshot(1)
	await process_frame
	expect(is_instance_valid(clock) and clock.text=="漲潮 0:01 後" and observe==app.modal.find_child("WanganWeirObserve",true,false),"Countdown ticks without rebuilding the controls")
	expect(not world.act(token,"high-during-low",Memory.WEIR_ACTION,Memory.WEIR_SITE,"high").ok and not person.has(Memory.WEIR_KEY),"The server rejects high-tide recording while the stones are exposed")
	await capture("wangan-weir-waiting.png")
	expect(world.step(0.2,true),"The world clock crosses back into high tide")
	app.session._send_snapshot(1)
	await process_frame
	observe=app.modal.find_child("WanganWeirObserve",true,false)
	expect(observe!=null and not observe.disabled,"The open panel enables the first entry when the tide rises")
	clock=app.modal.find_child("WanganWeirTideClock",true,false)
	expect(clock!=null and clock.text=="退潮 2:00 後","The forecast wraps into the next tide cycle")
	expect(not world.act(token,"reverse-tide",Memory.WEIR_ACTION,Memory.WEIR_SITE,"low").ok,"The server rejects low tide before high tide")
	await capture("wangan-weir-high.png")
	if observe:observe.pressed.emit()
	await process_frame
	expect(int(app.session.snapshot.get("own_wangan_weir",0))==1,"High tide advances the personal observation")
	expect(loaded.load_world(path) and int(loaded.state.players.get(token,{}).get(Memory.WEIR_KEY,0))==1,"A partial tide observation survives restart")
	app._close_modal()
	person.x=Memory.WEIR_LOOKOUT.x+0.5
	person.y=50.5
	for step in 14:
		world.move_player(token,Vector2.DOWN,0.14)
	expect(Vector2i(Vector2(person.x,person.y))==Memory.WEIR_LOOKOUT,"Movement reaches the new southern end of the boardwalk")
	expect(not World.original_home_land(Memory.WEIR_LOOKOUT) and world.protected(Memory.WEIR_LOOKOUT),"The new dry land is a public observation area")
	expect(world.blocked(Vector2i(50,59)) and world.blocked(Vector2i(55,55)),"The sea and downstream water still block walking")
	expect(not world.act(token,"build-over-lookout","build",Memory.WEIR_LOOKOUT,"floor").ok,"Private construction cannot cover the new lookout")
	app.session._send_snapshot(1)
	await create_timer(0.35).timeout
	app.toast.hide()
	await capture("wangan-south-shore.png")
	expect(is_equal_approx(coast.tide_height(0.0),1.0) and is_zero_approx(coast.tide_height(coast.TIDE_SECONDS/2.0))
		and is_equal_approx(coast.tide_height(coast.TIDE_SECONDS),1.0),"The coast returns to high tide at a complete cycle")
	expect(not world.act(token,"low-during-high",Memory.WEIR_ACTION,Memory.WEIR_LOOKOUT,"low").ok and person.get(Memory.WEIR_KEY)==1,"The server rejects low-tide recording while the weir is submerged")
	world.state.time=coast.TIDE_SECONDS*1.5
	app.session._send_snapshot(1)
	await capture("wangan-south-shore-low.png")
	app._interact()
	await process_frame
	var local_tide:Label=app.modal.find_child("WanganWeirLiveTide",true,false) if is_instance_valid(app.modal) else null
	expect(local_tide!=null and "偏低" in local_tide.text,"The lookout shows the actual low tide")
	observe=app.modal.find_child("WanganWeirObserve",true,false)
	expect(observe!=null and observe.text=="觀察退潮" and not observe.disabled,"The lookout can continue the same observation at low tide")
	if observe:observe.pressed.emit()
	await process_frame
	expect(int(app.session.snapshot.get("own_wangan_weir",0))==2 and not app.session.snapshot.players[app.session.own_id].has(Memory.WEIR_KEY),"The completed record is personal")
	var replay:Button=app.modal.find_child("WanganWeirReplayHigh",true,false)
	var caption:Label=app.modal.find_child("WanganWeirCaption",true,false)
	expect(caption!=null and caption.text.begins_with("退潮") and replay!=null,"Completion shows the low-tide drawing and replay controls")
	await capture("wangan-weir-low.png")
	if replay:replay.pressed.emit()
	expect(caption!=null and caption.text.begins_with("漲潮") and int(app.session.snapshot.get("own_wangan_weir",0))==2,"Replay switches the illustration without losing completion")
	var shell_at:=coast.SHELL_CELL
	person.x=shell_at.x+0.5
	person.y=shell_at.y+0.5
	world.state.time=coast.TIDE_SECONDS*2.0
	expect(not world.act(token,"shell-high",coast.SHELL_POINT,shell_at).ok,"High tide rejects shell gathering on the server")
	world.state.time=coast.TIDE_SECONDS*2.5
	app._close_modal()
	app.session._send_snapshot(1)
	await create_timer(0.35).timeout
	app.toast.hide()
	await capture("wangan-shell-foraging.png")
	expect(world.act(token,"shell-low",coast.SHELL_POINT,shell_at).ok,"Low tide permits shell gathering")
	var due:=float(world.state.wangan_shell_ready)
	expect(not world.act(token,"shell-empty",coast.SHELL_POINT,shell_at).ok,"There is a shared time before another shell appears")
	expect(loaded.load_world(path) and float(loaded.state.wangan_shell_ready)==due and loaded.state.players[token].inventory.get(coast.SHELL_ITEM)==1,"Shell item and regrowth survive reload")
	person.x=dock.x+0.5
	person.y=dock.y+0.5
	app._close_modal()
	app.session._send_snapshot(1)
	app._interact()
	await process_frame
	var story:Button=app.modal.find_child("WanganHarborLog",true,false) if is_instance_valid(app.modal) else null
	expect(story!=null,"The harbor log is available through Ah Chao's actual dialogue")
	if story:story.pressed.emit()
	await process_frame
	var finish:Button=app.modal.find_child("WanganHarborLogFinish",true,false) if is_instance_valid(app.modal) else null
	expect(finish!=null and not finish.disabled,"Both completed observations unlock the log action")
	if finish:finish.pressed.emit()
	await process_frame
	expect(app.session.snapshot.get("own_wangan_log",false) and app.modal.find_child("WanganHarborLogComplete",true,false)!=null,
		"The story is completed and the closing dialogue appears in the journal")
	expect(not world.act(token,"duplicate-harbor-log",Memory.LOG_ACTION,dock).ok,"The harbor log is collected once")
	expect(loaded.load_world(path) and loaded.state.players.get(token,{}).get(Memory.LOG_KEY,false),"The completed harbor log survives saving")
	await capture("wangan-harbor-log.png")
	var shipping:=World.SHIPPING.cell_for(world.state)
	person.x=shipping.x+0.5
	person.y=shipping.y+1.5
	var coins:=int(person.coins)
	expect(world.act(token,"ship-shell","ship",shipping,JSON.stringify([[[coast.SHELL_ITEM,1]],18])).ok and int(person.coins)==coins+18,"The shipping box pays eighteen coins for a shell")
	expect(person.collection.shore.get(coast.SHELL_ITEM,false) and int(person.inventory.get(coast.SHELL_ITEM,0))==0,"Selling the shell keeps the personal discovery")
	expect(loaded.load_world(path) and loaded.state.island_shore_discoveries[coast.SHELL_ITEM].name==person.name
		and loaded.state.players[token].shore_discoveries[coast.SHELL_ITEM].day==1,"The island first and personal discovery survive reload")
	app._close_modal()
	app.session._send_snapshot(1)
	app._collection_menu()
	await process_frame
	var tab:=app.modal.find_child("CollectionTab4",true,false) as Button
	expect(tab!=null and tab.text=="海岸","The collection book has a coastal tab")
	if tab:
		for pressed in [true,false]:
			var click:=InputEventMouseButton.new()
			click.button_index=MOUSE_BUTTON_LEFT
			click.pressed=pressed
			click.position=tab.get_global_rect().get_center()
			root.push_input(click,true)
	await process_frame
	expect(tab!=null and tab.button_pressed,"The coastal tab is highlighted when clicked")
	var visible_entries:=[]
	for label_node:Node in app.modal.find_children("*","Label",true,false):
		if label_node.is_visible_in_tree():visible_entries.append(label_node.text)
	expect("✓ 潮紋貝殼" in visible_entries and "○ 海苔" in visible_entries and "個人首次 望安南岸・第 1 日" in visible_entries,
		"The coastal tab shows the sold shell as found, the missing seaweed and the first discovery date")
	await capture("wangan-shore-collection.png")
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WANGAN_MEMORY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
