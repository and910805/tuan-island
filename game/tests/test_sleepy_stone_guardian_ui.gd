extends SceneTree
## 打瞌睡石像：真實主場景 UI 測試（走 main._interact 與實際按鈕 → Session → World.act）。
## 參數：--size=WxH（預設 1024x640）、--large-text、--reduced-motion、--route=sit（改走靜靜陪牠）、
##       --capture-dir=<資料夾>（非 headless 才截圖）。
## 本測試不驗證聲音聽起來如何；只驗證畫面上的形狀、文字、依序亮起與實際動作結果。

const World=preload("res://scripts/world.gd")
const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
const GuardianUI=preload("res://scripts/sleepy_stone_guardian_ui.gd")
## Standing spots (tile coordinates) whose nearest interact point is the intended one.
const STAND_GUARDIAN:=Vector2(34.5,11.2)
## Beside the statue in the nook: captures show it unobstructed while it stays the focus.
const CAVE_VIEW:=Vector2(33.4,10.6)
const STAND_BELLS:=[Vector2(33.2,11.5),Vector2(35.5,12.2),Vector2(36.8,12.5)]
var app
var world
var actor:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func has_arg(flag:String)->bool:
	return flag in OS.get_cmdline_user_args()

func arg(prefix:String,fallback:String)->String:
	for item in OS.get_cmdline_user_args():
		if item.begins_with(prefix):return item.trim_prefix(prefix)
	return fallback

func capture(file_name:String)->void:
	var dir:=arg("--capture-dir=","")
	if dir.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(dir)
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(dir.path_join(file_name))==OK,"Capture "+file_name)

## World capture with the statue, all three bells and the survey point unobstructed.
func cave_capture(file_name:String)->void:
	stand(CAVE_VIEW)
	await settle()
	await create_timer(0.8).timeout
	check(app.view.interaction_focus()==GuardianUI.POINT,"Beside the statue it is the focused point for "+file_name)
	await capture(file_name)

func stand(at:Vector2)->void:
	var person:Dictionary=world.state.players[actor]
	person.region=Guardian.REGION
	person.x=at.x
	person.y=at.y
	app.session._send_snapshot(1)

func settle()->void:
	for i in range(5):await process_frame
	app._layout_preview()
	await process_frame

func control(id:String)->Control:
	return app.modal.find_child(id,true,false) as Control if is_instance_valid(app.modal) else null

func visible(item:Control)->bool:
	if not item or not item.is_visible_in_tree() or not root.get_visible_rect().encloses(item.get_global_rect()):return false
	var parent:=item.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(item.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func press(id:String)->void:
	await settle()
	var button:=control(id) as Button
	check(button!=null and visible(button) and not button.disabled,"Enabled and visible "+id)
	if button and not button.disabled:
		await create_timer(0.1).timeout
		button.pressed.emit()
	for i in range(4):await process_frame

func record()->Dictionary:
	return GuardianUI.clean_record(world.state.players[actor].get("sleepy_guardian"))

func sand()->int:
	return int(world.state.players[actor].inventory.get("crystal_sand",0))

func open_at(at:Vector2,expected:String)->void:
	if is_instance_valid(app.modal):app._close_modal()
	stand(at)
	await settle()
	check(app.view.interaction_focus()==expected,"Standing at %s focuses %s (got %s)"%[at,expected,app.view.interaction_focus()])
	app._interact()
	await settle()
	check(GuardianUI.is_open(app),"World interaction at %s opens the guardian panel"%expected)

func texts_fit(message:String)->void:
	await settle()
	var scroll:=control("ModalScroll") as ScrollContainer
	check(scroll==null or not scroll.get_v_scroll_bar().visible,message+": no scrolling needed")
	for button in app.modal.find_children("Guardian*","Button",true,false):
		check(visible(button),message+": fully shows "+button.name)
	for line in app.modal.find_children("Guardian*","Label",true,false):
		var text_label:=line as Label
		if text_label.text.is_empty() or not text_label.is_visible_in_tree():continue
		check(visible(text_label),message+": fully shows "+text_label.name)
		check(text_label.get_line_count()<=text_label.get_visible_line_count(),message+": no clipped lines in "+text_label.name)

## Presses 聽石像哼 and returns the bell order as the panel itself received it from the host.
func listen()->Array:
	await open_at(STAND_GUARDIAN,GuardianUI.POINT)
	await press("GuardianListen")
	await create_timer(0.2).timeout
	var notes:Array=[]
	for note in app.get_meta(GuardianUI.META).notes:notes.append(int(note.bell))
	return notes

func ring(bell:int)->void:
	await open_at(STAND_BELLS[bell],GuardianUI.BELL_POINT+str(bell))
	await press("GuardianRing%d"%bell)
	await create_timer(0.15).timeout

func run()->void:
	var parts:=arg("--size=","1024x640").to_lower().split("x")
	root.size=Vector2i(int(parts[0]),int(parts[1]))
	var path:=OS.get_environment("TEMP").path_join("guardian-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.session.set_physics_process(false)
	if app.session.host(0,"風鈴旅人",path)!=OK:
		check(false,"Host starts")
		quit(1)
		return
	world=app.session.world
	actor=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	world.state.mine_depths.pumped=24
	if has_arg("--large-text"):
		app.sound.preferred_text_scale=3
		app._apply_font_scale_tree()
		await process_frame
		check(app.font_scale_factor()>=1.2,"Large text is active")
	if has_arg("--reduced-motion"):
		app.sound.reduced_motion=true
		app.view.reduced_motion=true
	var sit_route:=arg("--route=","bells")=="sit"

	# Locked B4: no guardian points, no art entry points.
	world.state.mine_depths.unlocked=3
	stand(STAND_GUARDIAN)
	await settle()
	check(not app.view.interaction_focus().begins_with(GuardianUI.POINT),"Guardian points are absent before B4 is unlocked")
	world.state.mine_depths.unlocked=5
	# A deeper floor reusing the same cave shape has no guardian.
	world.state.players[actor].region="mine_5"
	app.session._send_snapshot(1)
	await settle()
	check(not app.view.interaction_focus().begins_with(GuardianUI.POINT),"Guardian points are absent on other floors")

	stand(STAND_GUARDIAN)
	await settle()
	check(app.view.interaction_focus()==GuardianUI.POINT,"Unlocked B4 offers the guardian interaction")
	await cave_capture("01-cave-asleep.png")
	# The survey point keeps its own interaction.
	stand(Vector2(34.5,13.2))
	await settle()
	check(app.view.interaction_focus()=="mine_survey","Survey point interaction is preserved next to the guardian")

	await open_at(STAND_GUARDIAN,GuardianUI.POINT)
	check(app.modal.get_meta("life_modal_layout","")==GuardianUI.LAYOUT,"Panel declares its layout")
	for id in ["GuardianListen","GuardianRing0","GuardianRing1","GuardianRing2","GuardianSit","GuardianLeave"]:
		check(control(id)!=null,"Asleep panel has "+id)
	check(control("GuardianClaim")==null,"Asleep panel has no reward button")
	check((control("GuardianRing0") as Button).disabled and (control("GuardianRing2") as Button).disabled,"Out-of-reach bells are disabled, not hidden")
	await texts_fit("Asleep panel")
	await capture("02-panel-asleep.png")

	if sit_route:
		for i in Guardian.CALM_NEEDED:
			await open_at(STAND_GUARDIAN,GuardianUI.POINT)
			await press("GuardianSit")
			check(int(record().calm)==i+1 or Guardian.awake(record()),"Sit %d is recorded by the host"%(i+1))
			if i==0:await capture("03-sit-progress.png")
		check(Guardian.awake(record()),"Three quiet sits wake the guardian without any bell")
	else:
		# Round 1: hear it, watch every note light in order, then walk and ring.
		var first:Array=await listen()
		check(first.size()==2,"First hum has two notes (got %d)"%first.size())
		var text:=(control("GuardianSequenceText") as Label).text+" ".join((control("GuardianSequence") as Control).get_children().map(func(c):return c.name))
		check(not text.is_empty(),"Hum is shown on screen")
		await capture("03-listen-first-note.png")
		if not has_arg("--reduced-motion"):
			var seen:Array=[]
			var until:=Time.get_ticks_msec()+int((GuardianUI.playback_duration(first.size())+0.6)*1000.0)
			while Time.get_ticks_msec()<until:
				var lit:int=GuardianUI.lit_bell(app)
				if lit>=0 and (seen.is_empty() or seen[-1]!=lit):seen.append(lit)
				if seen.size()==2 and lit>=0 and app.view.guardian_lit_bell==lit and not has_meta("shot"):
					set_meta("shot",true)
					await capture("04-listen-second-note.png")
				await process_frame
			check(seen==first,"Bells light one by one in the hummed order (lit %s, hummed %s)"%[seen,first])
			check(GuardianUI.lit_bell(app)==-1,"Highlight ends after the hum")
		await texts_fit("Panel after listening")
		await capture("05-after-listen.png")
		var again:Array=await listen()
		check(again==first,"Listening again is free and gives the same hum")
		# Wrong bell: gentle, nothing lost.
		var wrong:=0
		while wrong==int(first[0]):wrong+=1
		await ring(wrong)
		check(record()==Guardian.fresh() or int(record().round)==0,"A wrong bell costs nothing")
		check("翻個身" in (control("GuardianMessage") as Label).text,"Wrong bell shows the gentle message")
		await capture("06-wrong-bell.png")
		for bell in first:await ring(int(bell))
		check(int(record().round)==1,"Echoing two notes completes the first phrase")
		if is_instance_valid(app.modal):app._close_modal()
		await cave_capture("07-cave-round-one.png")
		var second:Array=await listen()
		check(second.size()==3,"Second hum has three notes (got %d)"%second.size())
		await texts_fit("Second phrase panel")
		await capture("08-second-phrase.png")
		for index in second.size():
			await ring(int(second[index]))
			if index==0:
				check("1／3" in (control("GuardianProgress") as Label).text,"Progress shows 1／3 after the first correct bell")
				await capture("09-progress.png")
		check(Guardian.awake(record()),"Echoing three notes wakes the guardian")

	if is_instance_valid(app.modal):app._close_modal()
	await cave_capture("10-cave-awake.png")
	await open_at(STAND_GUARDIAN,GuardianUI.POINT)
	check(control("GuardianClaim")!=null and control("GuardianListen")==null,"Awake panel offers only the reward")
	await texts_fit("Awake panel")
	await capture("11-panel-awake.png")
	# Inventory full: claim refused, still available.
	world.state.players[actor].inventory["crystal_sand"]=1000000000
	app.session._send_snapshot(1)
	await press("GuardianClaim")
	check(not record().claimed and sand()==1000000000,"Full inventory refuses the reward and keeps it available")
	world.state.players[actor].inventory["crystal_sand"]=0
	app.session._send_snapshot(1)
	await open_at(STAND_GUARDIAN,GuardianUI.POINT)
	var before:=sand()
	await press("GuardianClaim")
	check(record().claimed and sand()==before+Guardian.REWARD_COUNT,"Reward is granted exactly once (%d → %d)"%[before,sand()])
	await open_at(STAND_GUARDIAN,GuardianUI.POINT)
	check(control("GuardianClaim")==null,"Claimed panel has no reward button")
	await capture("12-panel-claimed.png")
	app._close_modal()
	check(sand()==before+Guardian.REWARD_COUNT,"No duplicate reward after reopening")

	app.session.shutdown()
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("SLEEPY_STONE_GUARDIAN_UI_REAL_TESTS route=%s size=%s checks=%d failures=%d"%["sit" if sit_route else "bells",root.size,checks,failures])
	quit(int(failures>0))
