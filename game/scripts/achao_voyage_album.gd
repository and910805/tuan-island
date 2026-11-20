extends RefCounted
## 阿潮〈船上合照〉（N05-4）相簿：只讀取既有的最新一張本機 PNG，不寫檔、不改伺服器狀態。
## 入口：報告前由碼頭面板、報告後由關係日誌開啟。
## 照片缺失或無法讀取時只顯示友善說明，絕不畫出假的「已拍攝」照片。
## 已完成阿潮第 4 階（自己快照 resident_goals.achao 第 4 階 state=="done"）才顯示
## 既有紀念木槳與「預覽」按鈕；預覽只開啟工坊建造預覽，不補發、不領取。

const Goals=preload("res://scripts/resident_goals.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const KeepsakeArt=preload("res://scripts/resident_keepsake_art.gd")

const RESIDENT:="achao"
const STAGE:=4
const KIND:="keepsake_achao_oar"
const FONT_MAX:=20  # 1024×640 原生視窗的字級上限
const PHOTO_HEIGHT:=256

static func earned(snapshot:Dictionary) -> bool:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return false
	var own:Variant=goals.get(RESIDENT)
	if not own is Dictionary:return false
	var entry:Variant=own.get(str(STAGE),own.get(STAGE))
	return entry is Dictionary and str(entry.get("state"))=="done"

static func load_photo(path:String) -> Image:
	if path.is_empty() or not FileAccess.file_exists(path):return null
	var image:=Image.load_from_file(path)
	if image==null or image.is_empty():return null
	return image

static func open(app,path:String,back:Callable,back_text:String="返回") -> void:
	var snapshot:Dictionary=app.session.snapshot
	var image:=load_photo(path)
	var body:VBoxContainer=app._open_modal("河灣上的合照")
	app.modal.name="AchaoAlbum"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","achao_album")
	body.add_theme_constant_override("separation",8)

	if image!=null:
		body.add_child(photo_frame(image))
		var caption:=line(app,body,"「我替船留了多一個位置。」——阿潮",15)
		caption.name="AchaoAlbumCaption"
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_color_override("font_color",Color("5a6042"))
	else:
		body.add_child(empty_frame(app))

	var owned:=earned(snapshot)
	if owned:
		body.add_child(oar_card(app,snapshot))

	# 固定頁尾：預覽（若已獲得）與返回，與提示文字同列。
	var actions:=HBoxContainer.new()
	actions.name="AchaoAlbumFooter"
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
	if owned:
		var preview:Button=app.button("預覽紀念木槳",func():app.life_panels.build_menu(app,KIND))
		preview.name="AchaoAlbumOar"
		actions.add_child(preview)
	var close:Button=app.button(back_text,back)
	close.name="AchaoAlbumBack"
	actions.add_child(close)
	close.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func photo_frame(image:Image) -> Control:
	var outer:=PanelContainer.new()
	outer.name="AchaoAlbumFrame"
	outer.custom_minimum_size.x=520
	outer.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	outer.add_theme_stylebox_override("panel",frame_box(Color("6b4a2e"),Color("3a2616"),6))
	var mat:=PanelContainer.new()
	mat.add_theme_stylebox_override("panel",frame_box(Color("f4ecd6"),Color("c9b98f"),10))
	outer.add_child(mat)
	var preview:=TextureRect.new()
	preview.name="AchaoAlbumPhoto"
	preview.texture=ImageTexture.create_from_image(image)
	preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size.y=PHOTO_HEIGHT
	preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	mat.add_child(preview)
	return outer

static func empty_frame(app) -> Control:
	var outer:=PanelContainer.new()
	outer.name="AchaoAlbumEmpty"
	outer.add_theme_stylebox_override("panel",frame_box(Color("ece3c8"),Color("a89870"),14))
	var box:=VBoxContainer.new()
	box.custom_minimum_size.y=PHOTO_HEIGHT-28
	box.alignment=BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation",8)
	outer.add_child(box)
	var title:=line(app,box,"這台裝置還沒有河灣合照",18)
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var hint:=line(app,box,"等你下次出海，在船上按下相機，河灣的風景就會收進這裡。",15)
	hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color",Color("5a6042"))
	return outer

static func oar_card(app,snapshot:Dictionary) -> Control:
	var keepsake:Dictionary=Goals.KEEPSAKES[KIND]
	var paper:=PanelContainer.new()
	paper.name="AchaoAlbumOarCard"
	paper.add_theme_stylebox_override("panel",Pixel.paper_style())
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	paper.add_child(row)
	row.add_child(Shell.picture(KeepsakeArt.icon(Goals.keepsake_item(KIND)),48))
	var info:=VBoxContainer.new()
	info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation",3)
	row.add_child(info)
	line(app,info,str(keepsake.name),16)
	var person:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var held:int=int(person.get("inventory",{}).get(Goals.keepsake_item(KIND),0))
	var note:=line(app,info,"從家園工坊的「生活」放置。背包 %d 件"%held,14)
	note.name="AchaoAlbumOarNote"
	note.add_theme_color_override("font_color",Color("37573e") if held>0 else Color("5a6042"))
	return paper

static func frame_box(fill:Color,edge:Color,margin:int) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new()
	box.bg_color=fill
	box.border_color=edge
	box.set_border_width_all(3)
	box.set_content_margin_all(margin)
	box.set_corner_radius_all(0)
	return box

static func line(app,parent:Container,copy:String,extent:int) -> Label:
	var label:Label=app.label(copy,min(extent,FONT_MAX))
	if parent is VBoxContainer:
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(label)
	return label
