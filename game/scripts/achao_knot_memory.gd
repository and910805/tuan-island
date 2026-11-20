extends RefCounted
## 阿潮〈打不開的繩結〉（第 1 階）完成後的回憶小頁：純閱讀，不發獎勵、不改任何解鎖。
## 閘門：自己快照的 resident_goals.achao 第 1 階 state=="done"（字串 "1" 或整數 1 都接受）。
## 插畫：achao_knot_art.gd 的 make(reduced_motion) 畫出整理好的繩子，sync(picks) 帶入
## 這一階的正確鬆繩順序（來自 resident_goals.gd，不另存一份）。
## 紀念小物由伺服器已經給過一份；這裡只說明怎麼擺（工坊「生活」頁）並可直接預覽，
## 不領取、不補發、不暗示其他解鎖。

const World=preload("res://scripts/world.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const KeepsakeArt=preload("res://scripts/resident_keepsake_art.gd")
const Art=preload("res://scripts/achao_knot_art.gd")

const RESIDENT:="achao"
const STAGE:=1
const KIND:="keepsake_achao"
const FONT_MAX:=20  # 小尺寸 1024×640 原生視窗的字級上限

static func available(snapshot:Dictionary) -> bool:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return false
	var own:Variant=goals.get(RESIDENT)
	if not own is Dictionary:return false
	var entry:Variant=own.get(str(STAGE),own.get(STAGE))
	return entry is Dictionary and str(entry.get("state"))=="done"

static func open(app,back:Callable) -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not available(snapshot):return
	var entry:Dictionary=Goals.goal(RESIDENT,STAGE)
	var keepsake:Dictionary=Goals.KEEPSAKES[KIND]
	var body:VBoxContainer=app._open_modal("鬆開的舊繩結")
	app.modal.name="AchaoKnotMemory"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","achao_knot_memory")
	body.add_theme_constant_override("separation",8)

	var order:Array=entry.order
	var art:Control=Art.make(true)
	art.name="AchaoKnotMemoryArt"
	body.add_child(art)
	art.call("sync",order)

	var steps:=HBoxContainer.new()
	steps.add_theme_constant_override("separation",8)
	body.add_child(steps)
	for index in range(order.size()-1,-1,-1):
		var row:=line(app,steps,"%d · %s"%[index+1,entry.steps[order[index]]],15)
		row.name="AchaoKnotMemoryStep_%d"%(index+1)
		row.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER

	var paper:=PanelContainer.new()
	paper.add_theme_stylebox_override("panel",Pixel.paper_style())
	body.add_child(paper)
	var note:=HBoxContainer.new()
	note.add_theme_constant_override("separation",10)
	paper.add_child(note)
	note.add_child(Shell.picture(KeepsakeArt.icon(Goals.keepsake_item(KIND)),52))
	var info:=VBoxContainer.new()
	info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation",4)
	note.add_child(info)

	var story:=line(app,info,"「%s」——阿潮"%str(entry.quote[0]),15)
	story.name="AchaoKnotMemoryStory"
	story.add_theme_color_override("font_color",Color("5a6042"))
	var place:=line(app,info,"從家園工坊的「生活」放置%s。拆下可收回背包。"%str(keepsake.name),15)
	place.name="AchaoKnotMemoryPlacement"
	var person:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var held:int=int(person.get("inventory",{}).get(Goals.keepsake_item(KIND),0))
	var count:=line(app,info,"背包 %d 件"%held,14)
	count.name="AchaoKnotMemoryBag"
	count.add_theme_color_override("font_color",Color("37573e") if held>0 else Color("5a6042"))

	# 固定頁尾：預覽與返回（與提示文字同列）。
	var actions:=HBoxContainer.new()
	actions.alignment=BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation",8)
	if is_instance_valid(app.modal_feedback) and app.modal.is_ancestor_of(app.modal_feedback):
		var footer:Label=app.modal_feedback
		footer.get_parent().add_child(actions)
		footer.reparent(actions,false)
		footer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		footer.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	else:
		body.add_child(actions)
	var preview:Button=app.button("在工坊預覽",func():app.life_panels.build_menu(app,KIND))
	preview.name="AchaoKnotMemoryPreview"
	actions.add_child(preview)
	var close:Button=app.button("返回關係事件",back)
	close.name="AchaoKnotMemoryBack"
	actions.add_child(close)
	close.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func line(app,parent:Container,copy:String,extent:int) -> Label:
	var label:Label=app.label(copy,min(extent,FONT_MAX))
	if parent is VBoxContainer:
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(label)
	return label
