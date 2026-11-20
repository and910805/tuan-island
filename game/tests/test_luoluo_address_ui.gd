extends SceneTree

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const Folio:=preload("res://scripts/build_folio.gd")
const MemoryScene:=preload("res://scripts/luoluo_letter_scene.gd")
const FUTURE_WORDS:="給未來的我：如果還住在渡口，就記得去老樹下看看。"

var app
var world:World
var token:String
var person:Dictionary
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func button(id:String) -> Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func press(id:String) -> void:
	var node:=button(id)
	expect(node!=null and not node.disabled,"Enabled action: "+id)
	if node!=null and not node.disabled:node.pressed.emit()
	await process_frame
	await process_frame

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func visit_postcard_story(post:Vector2i) -> void:
	app._close_modal()
	person.bonds.luoluo.points=6
	for resident:String in ["aru","milu","xiaoli"]:
		person.bonds[resident]={"points":1,"talk_day":-1,"gift_day":-1}
	stand(post)
	Tasks.bond_goal(app,"luoluo",2)
	await process_frame
	var submit:=button("BondGoalDo")
	expect(submit!=null and submit.disabled,"Acquaintance alone does not complete the story")
	await press("LuoluoPostcardNotebook")
	var progress:=app.modal.find_child("LuoluoPostcardProgress",true,false) as Label
	expect(progress!=null and progress.text.ends_with("0／3"),"Notebook starts empty")
	await press("LuoluoPostcardNotebookBack")
	app._close_modal()
	for resident:String in ["aru","milu","xiaoli"]:
		stand(World.bond_place(world.state,resident)[1])
		app._interact()
		await process_frame
		if resident=="xiaoli":await press("XiaoliShopChat")
		await press("LuoluoAskPostcardClue")
		expect(resident in app.session.snapshot.own_luoluo_postcard_clues,"A clue from "+resident+" is recorded")
		app._close_modal()
	expect(app.session.snapshot.own_luoluo_postcard_clues==["aru","milu","xiaoli"],"Clue order is preserved")
	app._journal()
	await press("LuoluoPostcardBookmark")
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	for id:String in ["aru","milu","xiaoli"]:
		var note:=app.modal.find_child("PostcardClue_"+id,true,false) as Control
		expect(note!=null and note.get_global_rect().end.y<=scroll.get_global_rect().end.y,"The full note for "+id+" fits")
	await capture("04-postcard-notebook.png")
	stand(post)
	Tasks.bond_goal(app,"luoluo",2)
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.luoluo["2"].state=="done","Reporting the three clues unlocks the rack")
	Tasks.bond_goal(app,"luoluo",2)
	await press("LuoluoPostcardPattern")
	var title:=app.modal.find_child("BuildTitle",true,false) as Label
	expect(title!=null and title.text==World.BUILD[World.POSTCARDS.RACK].name,"The story opens the sea-breeze postcard rack recipe")
	await capture("05-postcard-rack.png")

func visit_memory_letter(post:Vector2i,choice:String) -> void:
	app._close_modal()
	person.bonds.luoluo.points=14
	app.sound.reduced_motion="--reduced-motion" in OS.get_cmdline_user_args()
	stand(post)
	Tasks.bond_goal(app,"luoluo",3)
	await process_frame
	expect(button("LuoluoMemoryLetter")==null,"The reward is hidden before completion")
	await press("BondGoalOption_"+choice)
	await press("BondGoalDo")
	var record:Dictionary=app.session.snapshot.resident_goals.luoluo["3"]
	expect(record.state=="done" and record.choice==choice,"The host records the selected way to deliver the letter")
	await press("LuoluoMemoryLetter")
	var scene:=app.modal.find_child("LuoluoLetterScene",true,false) as MemoryScene
	var message:=app.modal.find_child("LuoluoMemoryMessage",true,false) as Label
	expect(scene!=null and scene.handed==(choice=="letter"),"The replay uses the saved route")
	expect(message!=null and message.text.contains("你陪我坐了一會兒"),"Both routes can read the full letter")
	if app.sound.reduced_motion:
		expect(scene.beat==2 and not scene.is_processing(),"Reduced motion shows the final moment immediately")
	else:
		await create_timer(0.78).timeout
		expect(scene.beat==1 and scene.is_processing(),"The scene reaches its animated delivery beat")
	await capture("06-luoluo-memory-letter.png")
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	var return_button:=button("LuoluoMemoryBack")
	expect(scroll!=null and return_button!=null and return_button.get_global_rect().end.y<=scroll.get_global_rect().end.y,"The whole letter and its actions fit")
	await press("LuoluoMemoryReplay")
	expect(scene.beat==(2 if app.sound.reduced_motion else 0),"Replay starts the same presentation locally")
	expect(world.state.get("island_notes",[]).is_empty(),"Completing and replaying the story leaves the public board untouched")
	await press("LuoluoMemoryOpenNotes")
	var draft:=app.modal.find_child("IslandNoteDraft",true,false) as LineEdit
	expect(draft!=null and draft.text.is_empty(),"The public board opens with an empty draft")
	if draft!=null:draft.text="下次一起在老樹下等船。"
	await press("IslandNoteSubmit")
	expect(world.state.get("island_notes",[]).size()==1,"Only deliberate posting shares a message")
	await press("IslandNotesBack")
	expect(button("LuoluoMemoryReplay")!=null,"Back from the board returns to the memory letter")
	await press("LuoluoMemoryBack")
	expect(button("LuoluoMemoryLetter")!=null,"Back from the memory letter returns to the relationship event")
	app._journal()
	await press("LuoluoMemoryBookmark")
	expect(button("LuoluoMemoryOpenNotes")!=null,"Personal handbook can reopen the finished memory")

func visit_future_book(post:Vector2i,choice:String) -> void:
	app._close_modal()
	person.bonds.luoluo.points=24
	stand(post)
	Tasks.bond_goal(app,"luoluo",4)
	expect(button("LuoluoFutureBook")==null,"The future book is a completion reward")
	await press("BondGoalOption_write")
	var field:=app.modal.find_child("LuoluoFutureInput",true,false) as LineEdit
	expect(field!=null and field.is_visible_in_tree() and button("BondGoalDo").disabled,"Writing requires a message")
	if choice=="write":
		field.text=FUTURE_WORDS
		field.text_changed.emit(field.text)
		await capture("07-writing-future-letter.png")
	else:
		await press("BondGoalOption_blank")
		expect(not field.is_visible_in_tree(),"The blank route skips the editor")
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.luoluo["4"].get("choice")==choice,"The chosen route was saved")
	expect(int(person.inventory.get("keepsake_luoluo_kit",0))==1,"Keepsake still arrives once")
	await press("LuoluoFutureBook")
	var words:=app.modal.find_child("LuoluoFutureWords",true,false) as Label
	expect(words!=null and words.text==(FUTURE_WORDS if choice=="write" else "這封信留了一張空白的紙。"),"Private book shows the exact letter or deliberate blank")
	expect(app.session.snapshot.island_notes.size()==1 and not str(app.session.snapshot.island_notes).contains(FUTURE_WORDS),"Opening the personal book leaves public messages untouched")
	await press("LuoluoCourierCapToggle")
	expect(person.get(Goals.COURIER_CAP_KEY,false) and button("LuoluoCourierCapToggle").text=="脫下信差帽","The reward is visibly equipped")
	await capture("08-future-book.png")
	await press("LuoluoCourierCapToggle")
	expect(not person.has(Goals.COURIER_CAP_KEY),"The hat can be removed")
	await press("LuoluoCourierCapToggle")
	app._close_modal()
	await capture("09-courier-cap.png")
	app._journal()
	await press("LuoluoFutureBookmark")
	expect(button("LuoluoCourierCapToggle")!=null,"The island handbook can reopen the personal book")

func run() -> void:
	root.size=Vector2i(1024,640)
	if "--wide" in OS.get_cmdline_user_args():root.size=Vector2i(1280,800)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	if "--large-text" in OS.get_cmdline_user_args():
		app.sound.preferred_text_scale=3
		app._apply_font_scale_tree()
	var path:="user://luoluo-letter-%d.json"%OS.get_process_id()
	if app.session.host(0,"送信島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.board=true
	world.state.picnic=true
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	var post:Vector2i=World.bond_place(world.state,"luoluo")[1]
	stand(post)
	expect(not world.act(token,"before-intro",Goals.ADDRESS_ACTION,post,"take").ok,"Letter needs introduction")
	app._interact()
	await process_frame
	await press("BondTalk")
	expect(World.RESIDENT_BOND.stage(person,"luoluo")==1,"Meet Luoluo through normal dialogue")
	app._close_modal()
	stand(post)
	app._interact()
	await process_frame
	await press("LuoluoTakeLetter")
	expect(app.session.snapshot.own_luoluo_address==Goals.ADDRESS_CARRIED,"Letter is recorded on the host")
	expect(not app.session.snapshot.players[app.session.own_id].has(Goals.ADDRESS_KEY),"Player's letter is private")
	expect(not world.act(token,"duplicate-letter",Goals.ADDRESS_ACTION,post,"take").ok,"Only one pending letter is issued")
	expect(not world.act(token,"early-report",Goals.ACTION,post,"luoluo:1::").ok,"Cannot report before delivering")
	var checkpoint:=World.new()
	expect(checkpoint.load_world(path) and checkpoint.state.players[token].get(Goals.ADDRESS_KEY)==Goals.ADDRESS_CARRIED,"A carried letter survives reload")
	var mailbox:=Vector2i(50,24)
	var blueprint:={"version":1,"name":"門口的信箱","width":1,"height":1,"pieces":[{"kind":Goals.MAILBOX_KIND,"x":0,"y":0}]}
	world.state.removed[World.key(mailbox)]=true
	stand(mailbox+Vector2i(1,0))
	var locked:=world.quote_blueprint(token,blueprint,mailbox)
	var supplies:Dictionary=person.inventory.duplicate(true)
	var refused:=world.apply_blueprint(token,"000000000000000000000000000000ab",blueprint,mailbox,0,locked.hash)
	expect(not locked.ok and not refused.ok and person.inventory==supplies and not world.state.objects.has(World.key(mailbox)),"Locked mailbox is refused by both blueprint paths without charging")
	stand(post)
	app._interact()
	await process_frame
	await press("LuoluoReadLetter")
	var clue:=app.modal.find_child("AddressClue1",true,false) as Label
	var initial:=clue.get_theme_font_size("font_size")
	var zoom:=app.modal.find_child("LuoluoAddressZoom",true,false) as CheckButton
	expect(zoom!=null and app.modal.find_child("AddressClue3",true,false)!=null,"Letter shows all three clues and a personal zoom control")
	if zoom!=null:zoom.button_pressed=true
	await process_frame
	expect(clue.get_theme_font_size("font_size")>initial,"Clue zoom enlarges the text")
	var area:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	var third:=app.modal.find_child("AddressClue3",true,false) as Label
	expect(area!=null and third!=null and area.get_global_rect().encloses(third.get_global_rect()),"All enlarged clues fit on the letter page")
	await capture("01-enlarged-letter.png")
	Tasks.address_letter(app)
	await process_frame
	clue=app.modal.find_child("AddressClue1",true,false) as Label
	zoom=app.modal.find_child("LuoluoAddressZoom",true,false) as CheckButton
	expect(zoom!=null and zoom.button_pressed and clue.get_theme_font_size("font_size")>initial,"The zoom is remembered on reopening the envelope")
	if zoom!=null:zoom.button_pressed=false
	expect(clue.get_theme_font_size("font_size")==initial,"Zoom can also be reset")
	app._close_modal()
	var milu:Vector2i=World.bond_place(world.state,"milu")[1]
	stand(milu)
	app._interact()
	await process_frame
	await press("LuoluoDeliverLetter")
	expect(app.session.snapshot.own_luoluo_address==Goals.ADDRESS_CARRIED,"Wrong recipient leaves the letter intact")
	expect(not world.act(token,"spoof-delivery",Goals.ADDRESS_ACTION,milu,"aru").ok,"Server checks the actual recipient's position")
	var aru:Vector2i=World.bond_place(world.state,"aru")[1]
	stand(aru)
	app._interact()
	await process_frame
	await press("LuoluoDeliverLetter")
	expect(app.session.snapshot.own_luoluo_address==Goals.ADDRESS_DELIVERED,"The intended recipient accepts")
	stand(post)
	Tasks.bond_goal(app,"luoluo",1)
	await process_frame
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.luoluo["1"].state=="done","Report unlocks the mailbox")
	await capture("03-mailbox-pattern.png")
	await press("LuoluoReplayLetter")
	expect(app.modal.find_child("AddressClue3",true,false)!=null,"The story can reopen the delivered letter")
	await press("LuoluoAddressBack")
	await press("LuoluoMailboxPattern")
	var recipe:=app.modal.find_child("BuildTitle",true,false) as Label
	expect(recipe!=null and recipe.text==World.BUILD[Goals.MAILBOX_KIND].name,"The shortcut selects the real mailbox recipe")
	await press("BuildPlace")
	stand(mailbox+Vector2i(1,0))
	expect(Folio.unlocked(app,app.session.snapshot.players[app.session.own_id],Goals.MAILBOX_KIND),"Mailbox unlocked in furniture catalogue")
	app._perform_build_action("build",mailbox,Goals.MAILBOX_KIND)
	await process_frame
	expect(world.state.objects.get(World.key(mailbox),{}).get("type")==Goals.MAILBOX_KIND and world.blocked(mailbox),"Built mailbox has normal collision")
	stand(mailbox+Vector2i(1,0))
	app._interact()
	await process_frame
	expect(app.modal.find_child("AddressClue1",true,false)!=null,"World mailbox reopens the completed letter")
	await capture("02-mailbox-letter.png")
	var second:=mailbox+Vector2i(0,2)
	world.state.removed[World.key(second)]=true
	stand(second+Vector2i(1,0))
	var open_quote:=world.quote_blueprint(token,blueprint,second)
	var nonce:="000000000000000000000000000000ac"
	var applied:=world.apply_blueprint(token,nonce,blueprint,second,0,open_quote.hash)
	expect(open_quote.ok and applied.ok and world.state.objects.get(World.key(second),{}).get("type")==Goals.MAILBOX_KIND,"Unlocked mailbox is installed by a normal blueprint")
	var charged:Dictionary=person.inventory.duplicate(true)
	expect(world.apply_blueprint(token,nonce,blueprint,second,0,open_quote.hash)==applied and person.inventory==charged,"Retrying the blueprint does not charge again")
	await visit_postcard_story(post)
	var memory_choice:="letter" if "--memory-letter" in OS.get_cmdline_user_args() else "aloud"
	await visit_memory_letter(post,memory_choice)
	var future_choice:="blank" if "--blank-future" in OS.get_cmdline_user_args() else "write"
	await visit_future_book(post,future_choice)
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	var record:Dictionary=loaded.state.players[token]
	expect(record.get(Goals.ADDRESS_KEY,0)==Goals.ADDRESS_DELIVERED and Goals.done(record,"luoluo").has(1),"Letter and completion survive reload")
	expect(Goals.postcard_clues(record)==["aru","milu","xiaoli"] and Goals.done(record,"luoluo").has(2),"Interview notebook and completion survive reload")
	expect(Goals.done(record,"luoluo").get(3)==memory_choice and loaded.state.island_notes.size()==1,"The delivery choice and explicit public message survive reload")
	expect(Goals.done(record,"luoluo").get(4)==future_choice and Goals.future_note(record)==(FUTURE_WORDS if future_choice=="write" else "") and record.get(Goals.COURIER_CAP_KEY,false),"The exact private letter and equipped hat survive reload")
	expect(loaded.state.objects.get(World.key(mailbox),{}).get("type")==Goals.MAILBOX_KIND,"Mailbox survives reload")
	record.erase(Goals.ADDRESS_KEY)
	record.erase(Goals.POSTCARD_CLUES_KEY)
	expect(loaded.save(),"Save a legacy completion without a separate letter flag")
	var legacy:=World.new()
	expect(legacy.load_world(path) and Goals.address_progress(legacy.state.players[token])==Goals.ADDRESS_DELIVERED,"The legacy completion shows an already delivered letter")
	expect(Goals.done(legacy.state.players[token],"luoluo").has(2),"A legacy completion keeps the rack unlocked without fabricating interviews")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("LUOLUO_ADDRESS_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
