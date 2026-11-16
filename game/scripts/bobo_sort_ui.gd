extends RefCounted
const World=preload("res://scripts/world.gd")
const Art=preload("res://scripts/bobo_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Helpers=preload("res://scripts/freight_ui.gd")
const SHAPES:=["coarse","medium","fine"]
const LABELS:=["大塊礦樣","中塊礦樣","細粒礦樣"]

static func open(app)->void:
	var body:VBoxContainer=app._open_modal("波波的礦樣整理桌")
	app.modal.set_meta("life_modal_layout","bobo_sort")
	app.modal.set_meta("sort_body",body)
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.24
	refresh(app)

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("sort_body"):return
	var snapshot:Dictionary=app.session.snapshot
	var person:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	if person.is_empty():return
	var table:Vector2i=World.BOBO_WORKSHOP.sites(snapshot).table
	var near:bool=str(snapshot.get("region_id","home"))=="jinguashi" and Vector2(person.x,person.y).distance_to(Vector2(table)+Vector2(0.5,0.5))<=3.2
	var job:Dictionary=snapshot.get("bobo_workshop",{}).get("own_job",{})
	var count:=int(person.inventory.get("gold_ore",0))
	var signature:=JSON.stringify([job,count,person.inventory.get("gold_sample",0),near,table,World.JINGUASHI_REVISIT.unlocked(snapshot)])
	if app.modal.get_meta("sort_signature","")==signature:return
	app.modal.set_meta("sort_signature",signature)
	var body:VBoxContainer=app.modal.get_meta("sort_body")
	var focused:=body.get_viewport().gui_get_focus_owner()
	var focus_name:String=focused.name if is_instance_valid(focused) and body.is_ancestor_of(focused) else ""
	for child in body.get_children():body.remove_child(child);child.queue_free()
	var step:=int(job.get("step",0))
	var ready:=not job.is_empty() and step==3
	app.modal.set_meta("sort_height",450 if job.is_empty() else (480 if ready else 530))
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",16);body.add_child(row)
	row.add_child(Shell.picture(Art.icon("portrait"),96))
	var words:=VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(words)
	Helpers.text(app,words,"讓每一塊礦樣，都有自己的位置" if job.is_empty() else ("整理好了，帶一份回去留念吧。" if ready else "第 %d / 3 份  ·  %s"%[step+1,LABELS[step]]),20)
	Helpers.text(app,words,"波波：留住的不是價格，是我們一起整理的這個下午。" if ready else "波波：先看標籤，再放進對應的格子。放錯沒關係，我們再試一次。",15)
	if job.is_empty():
		var recipe:=HBoxContainer.new();recipe.alignment=BoxContainer.ALIGNMENT_CENTER;recipe.add_theme_constant_override("separation",20);body.add_child(recipe)
		recipe.add_child(Shell.picture(Items.icon("gold_ore"),64))
		var amount:=Helpers.text(app,recipe,"含金礦料 ×3\n背包持有 %d"%count,16);amount.name="SortInventoryCount"
		Helpers.text(app,recipe,"→",24)
		recipe.add_child(Shell.picture(Items.icon("gold_sample"),64))
		Helpers.text(app,recipe,"金工收藏樣本 ×1",16)
		var start:=Helpers.action(app,body,"SortStart","攤開礦樣，開始整理",func():app.session.perform("bobo_sort_start",table),near and count>=3)
		start.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	elif ready:
		var result:=HBoxContainer.new();result.alignment=BoxContainer.ALIGNMENT_CENTER;body.add_child(result)
		result.add_child(Shell.picture(Items.icon("gold_sample"),64))
		Helpers.text(app,result,"三份礦樣已整理妥當\n金工收藏樣本 ×1",18)
		var claim:=Helpers.action(app,body,"SortClaim","收好收藏樣本",func():app.session.perform("bobo_sort_claim",table),near and int(person.inventory.get("gold_sample",0))<World.BOBO_WORKSHOP.LIMIT)
		claim.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	else:
		var trays:=HBoxContainer.new();trays.name="SortingTrays";trays.alignment=BoxContainer.ALIGNMENT_CENTER;trays.add_theme_constant_override("separation",16);body.add_child(trays)
		for index in range(3):
			var answer:=str(index)
			var button:=Helpers.action(app,trays,"SortBin_"+answer,"",func():app.session.perform("bobo_sort_answer",table,"%d:%s"%[step,World.BOBO_WORKSHOP.STEPS[int(answer)]]),near)
			button.custom_minimum_size=Vector2(192,174)
			for state in ["normal","hover","pressed","disabled"]:button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
			var tray:=Shell.picture(Art.icon("tray"),192);tray.custom_minimum_size=Vector2.ZERO;tray.size=Vector2(192,144);tray.position=Vector2.ZERO;button.add_child(tray)
			var grain:=Shell.picture(Art.icon(SHAPES[index]),96);grain.custom_minimum_size=Vector2.ZERO;grain.size=Vector2(96,96);grain.position=Vector2(48,16);button.add_child(grain)
			var caption:Label=app.label(LABELS[index],15);caption.position=Vector2(0,144);caption.size=Vector2(192,26);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(caption)
			button.mouse_entered.connect(func():tray.modulate=Color(1.12,1.12,1.02))
			button.mouse_exited.connect(func():tray.modulate=Color.WHITE)
			button.button_down.connect(func():tray.modulate=Color(0.82,0.9,0.82))
			button.button_up.connect(func():tray.modulate=Color.WHITE)
	var controls:=HBoxContainer.new();controls.alignment=BoxContainer.ALIGNMENT_END;body.add_child(controls)
	# 第 40 章金瓜石回訪：分揀、整理桌這一箱與領礦燈都在這裡（升降台修好前按鈕寫明鎖定）。
	controls.add_child(preload("res://scripts/jinguashi_revisit_ui.gd").entry_button(app,"table"))
	Helpers.action(app,controls,"SortSurveyJournal","翻閱礦場探索手帳",func():app._mine_survey_menu(1,"bobo_sort"),true)
	if not job.is_empty():
		Helpers.action(app,controls,"SortCancel","收起原料 ×3",func():app.session.perform("bobo_sort_cancel",table),near and count<=World.BOBO_WORKSHOP.LIMIT-3)
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text="靠近金瓜石整理桌才能操作。" if not near else ("關閉可保留進度；收起原料會取消本次整理。" if not job.is_empty() else "依大小標籤整理收藏樣本；原工作台配方仍可使用。")
	if not focus_name.is_empty():
		var next=body.find_child(focus_name,true,false)
		if not is_instance_valid(next):next=body.find_child("SortClaim" if ready else "SortBin_0",true,false)
		if next is BaseButton and not next.disabled:next.grab_focus.call_deferred()
	app._layout_preview.call_deferred()
