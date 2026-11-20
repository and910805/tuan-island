extends RefCounted
## T066 N04-4 〈留一把不同的椅子〉獎勵：茶茶手寫茶單（純閱讀，不下單、不製作、不改解鎖）。
## 只讀自己的 resident_goals.chacha 第 4 階（字串 "4" 或整數 4，state=="done"）與 own_chacha_tea_chair。
## 舊存檔沒有椅子紀錄時，插畫與文字都用中性說法，不編造選擇。

const World=preload("res://scripts/world.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Tea=World.TEA_CERAMICS
const Art=preload("res://scripts/chacha_handwritten_menu_art.gd")

const RESIDENT:="chacha"
const STAGE:=4
const FONT_MAX:=20  # 16 × 1.25
const ITEMS:=["tea_light","tea_deep","tea_pudding"]
const NOTES:={
	"tea_light":"入口清清的，像剛擦亮的杯沿。尾韻輕，適合一邊聊天一邊慢慢喝。",
	"tea_deep":"焙香厚一點，帶烤過的暖意。適合天色轉暗，或想安靜坐一會兒的時候。",
	"tea_pudding":"布丁軟軟的，茶香留在最後一口。冷熱的茶都能搭，甜味不搶戲。",
}

static func available(snapshot:Dictionary) -> bool:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return false
	var chacha:Variant=goals.get(RESIDENT)
	if not chacha is Dictionary:return false
	var entry:Variant=chacha.get(str(STAGE),chacha.get(STAGE))
	return entry is Dictionary and str(entry.get("state"))=="done"

## 只接受目前版本認得的椅子；其他（含舊存檔缺漏）一律視為未記錄。
static func chair(snapshot:Dictionary) -> String:
	var value:Variant=snapshot.get("own_chacha_tea_chair","")
	if value is String and Goals.TEA_CHAIRS.has(value):return value
	return ""

static func open(app,back:Callable,back_text:String="返回") -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not available(snapshot):return
	var body:VBoxContainer=app._open_modal("茶茶手寫茶單")
	app.modal.name="ChachaHandwrittenMenu"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","chacha_handwritten_menu")
	body.add_theme_constant_override("separation",8)

	var seat:String=chair(snapshot)
	var sound:Variant=app.get("sound")
	var reduced:bool=true if sound==null else bool(sound.get("reduced_motion"))

	# 三張可選的圖示卡。
	var cards:=HBoxContainer.new()
	cards.name="ChachaMenuItems"
	cards.add_theme_constant_override("separation",8)
	body.add_child(cards)
	var group:=ButtonGroup.new()
	var buttons:Array[Button]=[]
	for id:String in ITEMS:
		var card:=Button.new()
		card.name="ChachaMenuItem_"+id
		card.text=World.NAMES[id]
		card.icon=Items.icon(id)
		card.expand_icon=true
		card.add_theme_constant_override("icon_max_width",32)
		card.toggle_mode=true
		card.button_group=group
		card.focus_mode=Control.FOCUS_ALL
		card.custom_minimum_size=Vector2(0,54)
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.add_theme_font_size_override("font_size",FONT_MAX)
		cards.add_child(card)
		buttons.append(card)

	# 下方：左邊一張插畫便條（茶茶＋選的椅子），右邊是這道的小記與做法。
	var page:=HBoxContainer.new()
	page.name="ChachaMenuPage"
	page.add_theme_constant_override("separation",10)
	page.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(page)

	var art:Control=Art.make(seat,reduced)
	art.name="ChachaMenuArt"
	art.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	art.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	page.add_child(art)

	var detail:=PanelContainer.new()
	detail.name="ChachaMenuDetail"
	detail.add_theme_stylebox_override("panel",Pixel.paper_style())
	detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical=Control.SIZE_EXPAND_FILL
	page.add_child(detail)
	var lines:=VBoxContainer.new()
	lines.name="ChachaMenuDetailLines"
	lines.add_theme_constant_override("separation",5)
	detail.add_child(lines)

	var hostline:String=_host_line(seat)
	var caption:=_text(app,body,hostline,15)
	caption.name="ChachaMenuHostNote"
	caption.add_theme_color_override("font_color",Color("5a6042"))

	# 固定頁尾：返回按鈕（與提示文字同列）。
	var nav:=HBoxContainer.new()
	nav.alignment=BoxContainer.ALIGNMENT_END
	nav.add_theme_constant_override("separation",8)
	if is_instance_valid(app.modal_feedback) and app.modal.is_ancestor_of(app.modal_feedback):
		var footer:Label=app.modal_feedback
		footer.get_parent().add_child(nav)
		footer.reparent(nav,false)
		footer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		footer.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	else:
		body.add_child(nav)
	var close:Button=app.button(back_text,back)
	close.name="ChachaMenuBack"
	nav.add_child(close)

	var selection:={"id":""}
	var show:=func(id:String) -> void:
		if selection.id==id or not is_instance_valid(lines) or not lines.is_inside_tree():return
		selection.id=id
		for index in buttons.size():buttons[index].set_pressed_no_signal(ITEMS[index]==id)
		for child in lines.get_children():
			lines.remove_child(child)
			child.queue_free()
		_fill(app,lines,id,snapshot)
		art.call("show_item",id)
		app._layout_preview.call_deferred()
	for index in buttons.size():
		var id:String=ITEMS[index]
		var card:Button=buttons[index]
		card.pressed.connect(func():show.call(id))
		card.focus_entered.connect(func():show.call(id))
		# 左右循環；向下到返回。
		card.focus_neighbor_left=card.get_path_to(buttons[(index+buttons.size()-1)%buttons.size()])
		card.focus_neighbor_right=card.get_path_to(buttons[(index+1)%buttons.size()])
		card.focus_neighbor_bottom=card.get_path_to(close)
		card.focus_next=card.get_path_to(buttons[index+1] if index+1<buttons.size() else close)
		card.focus_previous=card.get_path_to(buttons[index-1] if index>0 else close)
	close.focus_neighbor_top=close.get_path_to(buttons[0])
	close.focus_next=close.get_path_to(buttons[0])
	close.focus_previous=close.get_path_to(buttons[buttons.size()-1])

	show.call(ITEMS[0])
	buttons[0].grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func _host_line(seat:String) -> String:
	if seat.is_empty():
		return "「總有一個座位留給來喝茶的人。」——茶茶"
	var name:String=str(Goals.TEA_CHAIRS[seat].name)
	return "「看到你留下的%s，我就知道有人要來了。」——茶茶"%name

static func _fill(app,lines:Container,id:String,snapshot:Dictionary) -> void:
	var note:=_text(app,lines,"「%s」"%NOTES[id],17)
	note.name="ChachaMenuNote"
	lines.add_child(HSeparator.new())
	for step:String in _where(id,snapshot):_text(app,lines,step,15)

## 做法一律取自倉庫：tea_ceramics.gd（採茶、烘焙台）與 kitchen_stove.gd（灶台食譜）。
static func _where(id:String,snapshot:Dictionary) -> Array[String]:
	if id=="tea_pudding":
		var stove:String=World.INDUSTRY.KITCHEN_STOVE
		var recipe:Dictionary=World.stove_recipes(stove).get(id,{})
		var parts:Array[String]=[]
		var ingredients:Dictionary=recipe.get("ingredients",{})
		for item:String in ingredients:
			parts.append("%s ×%d"%[World.NAMES.get(item,item),int(ingredients[item])])
		var steps:Array[String]=[]
		if not parts.is_empty():
			steps.append("公共廚房灶台 · %s。"%["、".join(parts)])
			steps.append("遊戲內 %d 秒，做成 %d 份。"%[int(recipe.time),int(recipe.yield)])
		if snapshot.get("resident_goals",{}).get(RESIDENT,{}).get("2",{}).get("state")!="done":
			steps.append("先完成茶茶的〈漏下來的一束光〉。")
		return steps
	var style:String="light" if id=="tea_light" else "deep"
	var seconds:int=int(Tea.ROAST_SECONDS.get(style,0.0))
	return [
		"貓空烘焙台 · 每批用 2 份新鮮茶葉。",
		"選%s，遊戲內 %d 秒後可取出一份。"%["淺焙" if style=="light" else "深焙",seconds],
	]

static func _text(app,parent:Node,copy:String,extent:int) -> Label:
	var label:Label=app.label(copy,min(extent,FONT_MAX))
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(label)
	return label
