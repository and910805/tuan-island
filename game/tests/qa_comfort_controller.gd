extends SceneTree
## 舒適設定手把驗收（特大字 125%）：B 開選單、方向鍵與 A 進設定，上下串過整個捲動區，
## 選單（鏡頭／文字大小／釣魚）開啟與選取、A 切換減少動態並保存、B 返回、重讀保存檔。
## 不使用任何人工 grab_focus。
## 執行：Godot --path game --resolution WxH --script res://tests/qa_comfort_controller.gd -- <輸出資料夾>
const ORDER:=["CameraMode","MasterVolume","MusicVolume","AmbienceVolume","ActionVolume","InterfaceVolume","ActivityCaptions","ReduceDecorativeMotion","ZoomNear","TextScale","DisplayCompatibility","FishingMode","SaveComfort"]
var failures:Array[String]=[]
var checks:=0

func _initialize()->void:
	create_timer(150.0).timeout.connect(func():print("COMFORT_QA timeout");quit(2))
	run.call_deferred()

func check(name:String,ok:bool)->void:
	checks+=1
	print("QA %s %s"%["PASS" if ok else "FAIL",name])
	if not ok:failures.append(name)

func joy(button:JoyButton,pressed:bool)->InputEventJoypadButton:
	var event:=InputEventJoypadButton.new()
	event.device=0;event.button_index=button;event.pressed=pressed
	event.pressure=1.0 if pressed else 0.0
	return event

## 手把事件送給目前有焦點的視窗：下拉選單展開時是它的彈出視窗，否則是主視窗
## （原生視窗下 OS 就是這樣分送）。
func target_window()->Window:
	var owner:=focus()
	if owner is OptionButton and (owner as OptionButton).get_popup().visible:return (owner as OptionButton).get_popup()
	return root

func tap(button:JoyButton)->void:
	var window:=target_window()
	if window==root:
		root.push_input(joy(button,true))
		root.push_input(joy(button,false))
	else:
		# 彈出選單開著：走正式輸入管線（與實體手把相同），由焦點視窗接手。
		Input.parse_input_event(joy(button,true))
		await process_frame
		Input.parse_input_event(joy(button,false))
	await process_frame
	await process_frame

func settle(frames:=3)->void:
	for i in frames:await process_frame

func focus()->Control:
	return root.gui_get_focus_owner()

func label(control:Control)->String:
	if control==null:return "none"
	if control is BaseButton and control.get_parent() is VBoxContainer and control.get_parent().get_parent() is HBoxContainer and control.get_parent().get_parent().get_child_count()==2 and control.name!="SaveComfort" and control.get_node_or_null("ToolArt")!=null:
		return "ZoomNear" if control.get_parent().get_index()==0 else "ZoomFar"
	return str(control.name)

func in_view(scroll:ScrollContainer,control:Control)->bool:
	return scroll.get_global_rect().grow(1.0).encloses(control.get_global_rect())

func run()->void:
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	var args:=OS.get_cmdline_user_args()
	var directory:=args[args.size()-1]
	var app=load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	await settle()
	app.settings_path=directory.path_join("comfort-%d.cfg"%OS.get_process_id())
	app.session.profile.token="comfort-controller-qa"
	if app.session.host(0,"Comfort QA",directory.path_join("comfort-%d.json"%OS.get_process_id()))!=OK:
		quit(1);return
	await create_timer(0.35).timeout
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	if is_instance_valid(app.modal):app._close_modal()
	app.controller_navigation=true
	app.sound.preferred_text_scale=3
	app._apply_font_scale_tree()
	await settle(6)
	var size:=root.get_visible_rect().size
	print("QA window=%s scale=%.2f"%[size,app.TEXT_SCALE_FACTORS[3]])
	var before_motion:bool=app.sound.reduced_motion

	await tap(JOY_BUTTON_B)
	await settle(9)
	var pause:Control=app.modal
	check("B opens pause",pause!=null)
	var comfort:=pause.find_child("PauseComfort",true,false) as Button
	await tap(JOY_BUTTON_DPAD_RIGHT)
	await tap(JOY_BUTTON_DPAD_RIGHT)
	await tap(JOY_BUTTON_DPAD_DOWN)
	check("d-pad reaches comfort settings",focus()==comfort)
	await tap(JOY_BUTTON_A)
	await settle(10)
	var panel:Control=app.modal
	check("A opens comfort settings",panel!=null and panel!=pause)
	var scroll:=panel.find_children("*","ScrollContainer",true,false).front() as ScrollContainer
	var named:=func(n:String)->Control:return panel.find_child(n,true,false)
	var camera:=named.call("CameraMode") as OptionButton
	var scale_choice:=named.call("TextScale") as OptionButton
	var display_mode:=named.call("DisplayCompatibility") as CheckBox
	var fishing:=named.call("FishingMode") as OptionButton
	var motion:=named.call("ReduceDecorativeMotion") as CheckBox
	var save:=named.call("SaveComfort") as Button

	# 向下：整條路徑依序走過，且每一步都在捲動視窗內。
	var down:Array[String]=[]
	var visible_all:=true
	for attempt in 30:
		var owner:=focus()
		if owner==null or not panel.is_ancestor_of(owner):
			await tap(JOY_BUTTON_DPAD_DOWN)
			continue
		var name:=label(owner)
		if not down.has(name):
			down.append(name)
			await settle(3)
			if scroll.is_ancestor_of(owner) and not in_view(scroll,owner):visible_all=false
		if owner==save:break
		await tap(JOY_BUTTON_DPAD_DOWN)
	print("QA down route=%s"%str(down))
	var expected:=ORDER.duplicate()
	var skin_present:=down.has("CheckBox") or down.has("森林工具外觀")
	check("down route covers every setting in order",down.filter(func(n):return n in ORDER)==expected)
	check("every focused control scrolled into view",visible_all)
	# 向上：反向路徑。
	var up:Array[String]=[]
	for attempt in 30:
		var name:=label(focus())
		if not up.has(name):up.append(name)
		if focus()==camera:break
		await tap(JOY_BUTTON_DPAD_UP)
	print("QA up route=%s"%str(up))
	var reversed:=ORDER.duplicate()
	reversed.reverse()
	check("up route is the reverse path",up.filter(func(n):return n in ORDER)==reversed)
	check("focus ends on first setting",focus()==camera)
	await shot("%s-comfort-top.png"%directory.path_join(str(size.x)))

	# 滑桿：左右仍調整數值，焦點不離開；上下才換列。
	var master:=named.call("MasterVolume") as HSlider
	await tap(JOY_BUTTON_DPAD_DOWN)
	check("down from camera reaches master volume",focus()==master)
	var previous_volume:=master.value
	var first_direction:=JOY_BUTTON_DPAD_LEFT if previous_volume>master.min_value else JOY_BUTTON_DPAD_RIGHT
	var last_direction:=JOY_BUTTON_DPAD_RIGHT if first_direction==JOY_BUTTON_DPAD_LEFT else JOY_BUTTON_DPAD_LEFT
	await tap(first_direction)
	var adjusted_volume:=master.value
	check("horizontal input changes master volume while retaining focus",focus()==master and absf(adjusted_volume-previous_volume)==master.step)
	await tap(last_direction)
	check("opposite direction restores master volume without moving focus",focus()==master and master.value==previous_volume)
	await tap(first_direction)
	check("edited volume is retained before saving",focus()==master and master.value==adjusted_volume)
	await tap(JOY_BUTTON_DPAD_UP)
	check("up from master returns to camera",focus()==camera)

	# 選單：鏡頭。
	var camera_before:=camera.selected
	await tap(JOY_BUTTON_A)
	await settle(4)
	check("A opens camera selector",camera.get_popup().visible)
	await tap(JOY_BUTTON_DPAD_DOWN)
	await tap(JOY_BUTTON_A)
	await settle(4)
	check("selector choose changes camera mode and closes",camera.selected!=camera_before and not camera.get_popup().visible and focus()==camera)

	# 近景／遠景：左右仍在這一對之間。
	var near:Control=null
	for attempt in 30:
		if label(focus())=="ZoomNear":near=focus();break
		await tap(JOY_BUTTON_DPAD_DOWN)
	check("reached zoom pair via vertical path",near!=null)
	await tap(JOY_BUTTON_DPAD_RIGHT)
	check("zoom pair right moves to far",label(focus())=="ZoomFar")
	await tap(JOY_BUTTON_A)
	check("A selects far zoom",focus() is BaseButton and (focus() as BaseButton).button_pressed)
	await tap(JOY_BUTTON_DPAD_DOWN)
	check("down from far zoom reaches text scale",focus()==scale_choice)
	await tap(JOY_BUTTON_DPAD_UP)
	check("returning to zoom focuses the latest selection",label(focus())=="ZoomFar")
	if label(focus())!="ZoomFar":await tap(JOY_BUTTON_DPAD_RIGHT)
	await tap(JOY_BUTTON_DPAD_LEFT)
	check("zoom pair left moves back to near",label(focus())=="ZoomNear")
	await tap(JOY_BUTTON_DPAD_DOWN)
	check("down from zoom reaches text scale",focus()==scale_choice)

	# 選單：文字大小（選別項再選回特大）。
	await tap(JOY_BUTTON_A)
	await settle(4)
	check("A opens text scale selector",scale_choice.get_popup().visible)
	await tap(JOY_BUTTON_DPAD_UP)
	await tap(JOY_BUTTON_A)
	await settle(4)
	check("text scale selector picks 大",scale_choice.get_selected_id()==2 and not scale_choice.get_popup().visible and focus()==scale_choice)
	await tap(JOY_BUTTON_A)
	await settle(4)
	await tap(JOY_BUTTON_DPAD_DOWN)
	await tap(JOY_BUTTON_A)
	await settle(4)
	check("text scale selector picks 特大 again",scale_choice.get_selected_id()==3 and focus()==scale_choice)

	# 顯示相容模式與釣魚模式。
	await tap(JOY_BUTTON_DPAD_DOWN)
	check("display compatibility is visible and focused",focus()==display_mode and in_view(scroll,display_mode))
	var previous_display:=display_mode.button_pressed
	await tap(JOY_BUTTON_A)
	check("A toggles display compatibility",display_mode.button_pressed!=previous_display)
	await shot(directory.path_join("display-mode.png"))
	await tap(JOY_BUTTON_DPAD_DOWN)
	if label(focus())!="FishingMode":await tap(JOY_BUTTON_DPAD_DOWN)
	check("reached fishing mode",focus()==fishing)
	check("focused fishing selector is completely visible",in_view(scroll,fishing))
	var fishing_before:=fishing.selected
	await tap(JOY_BUTTON_A)
	await settle(4)
	await tap(JOY_BUTTON_DPAD_DOWN)
	await tap(JOY_BUTTON_A)
	await settle(4)
	check("fishing selector chooses other mode",fishing.selected!=fishing_before and focus()==fishing)

	# 減少裝飾動態：A 切換。
	for attempt in 3:
		if focus()==motion:break
		await tap(JOY_BUTTON_DPAD_UP)
	if focus()!=motion:
		for attempt in 12:
			if focus()==motion:break
			await tap(JOY_BUTTON_DPAD_UP)
	check("up path reaches reduce motion",focus()==motion)
	await settle(8)
	check("reduce motion is in view",in_view(scroll,motion))
	await tap(JOY_BUTTON_A)
	check("A toggles reduce motion",motion.button_pressed!=before_motion)
	await shot("%s-comfort-motion.png"%directory.path_join(str(size.x)))

	# 存檔。
	for attempt in 30:
		if focus()==save:break
		await tap(JOY_BUTTON_DPAD_DOWN)
	check("down path reaches save",focus()==save)
	await tap(JOY_BUTTON_A)
	await settle(8)
	check("save applies motion",app.sound.reduced_motion!=before_motion and app.view.reduced_motion!=before_motion)
	check("save applies compatibility to the renderer",app.sound.display_compatibility and DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED and Engine.max_fps==60)
	var stored=app.sound.get_script().new()
	stored.load_preferences(app.settings_path)
	check("reread saved settings",stored.reduced_motion==app.sound.reduced_motion and stored.preferred_text_scale==3 and stored.fixed_area_camera==(camera.selected==1) and stored.standard_fishing==(fishing.selected==1))
	check("reread adjusted master volume",is_equal_approx(stored.master_volume,adjusted_volume/100.0))
	check("reread selected far zoom",stored.preferred_zoom==1 and app.view.zoom==1.0)
	check("reread display compatibility",stored.display_compatibility)
	stored.free()
	await tap(JOY_BUTTON_B)
	await settle(4)
	check("B returns to the island",not is_instance_valid(app.modal))

	print("COMFORT_QA checks=%d failures=%d window=%s"%[checks,failures.size(),size])
	app.session.shutdown()
	quit(1 if not failures.is_empty() else 0)

func shot(path:String)->void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
