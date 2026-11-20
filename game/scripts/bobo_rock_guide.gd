extends RefCounted
## T066 N03-1〈口袋裡的小山〉之後的「礦石辨識頁」：只讀的圖鑑小頁，不碰任何遊戲狀態
## （不改背包、不消耗物品、不寫存檔、不送網路動作）。
##
## 解鎖：本人快照 snapshot.resident_goals.bobo[1].state=="done"。
## Goals.view() 產生的階數鍵是字串 "1"（JSON 往返後也一樣），本頁同時接受整數 1。
## open(app,return_to,show_scene)：先檢查資格；show_scene 時先播排石頭的故事圖，再「翻開礦石辨識頁」。
## 延用遊戲的紙面外框和 ModalScroll，大字級時可捲動。
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Art=preload("res://scripts/bobo_rock_story_art.gd")

const RESIDENT:="bobo"
const STAGE:=1
const LAYOUT:="bobo_rock_guide"
const TITLE:="波波的礦石辨識頁"
const STORY_LINE:="波波把口袋裡的石頭一顆顆排開：「不是所有石頭都要送進爐子裡啦。」"
const SCENE_ID:="BoboRockStory"
const MET_BODY:="bobo_rock_body"
const START_ID:="stone"

## 來源與用途對照遊戲內實際內容（inventory_panel、mine_depths、mine_expansion_catalog、
## gold_panning、table_warmer）。層數是合作礦場的層（B＝第幾層）。
const SAMPLES:=[
	{"id":"stone","name":"石材","look":"灰灰的、沒有色斑，最常見。",
		"contrast":"灰白面沒有金屬或結晶斑紋。",
		"source":"十字鎬敲島上的岩石；合作礦場第 1、3、7、9、15 層也是石材礦。",
		"use":"建造用，也能捐給渡口的共同工程。"},
	{"id":"copper_ore","name":"銅礦","look":"灰石面上帶著銅色斑點，轉個角度才看得清楚。",
		"contrast":"斑點是銅色；含金礦料的亮痕偏暖黃。",
		"source":"渡口運入的練習礦料，或金瓜石礦點；要強化石鎬或公用鎬。",
		"use":"工作台做銅接頭；加木炭熔成銅錠。"},
	{"id":"iron_ore","name":"鐵礦","look":"深色又沉的礦塊，沒有亮痕。",
		"contrast":"比銅礦暗，沒有銅色斑點。",
		"source":"合作礦場第 4、6 層，敲礦時另外得到的伴生礦。",
		"use":"和木炭一起熔成鐵錠。"},
	{"id":"gold_ore","name":"含金礦料","look":"灰暗石面夾著一小道暖色亮痕。",
		"contrast":"亮痕偏暖黃，不是銅色斑點。",
		"source":"金瓜石西岸淘砂處淘一盤得 1 份；合作礦場第 5、11、12、14 層也有。",
		"use":"3 份可在波波的整理桌整理成金工收藏樣本。"},
	{"id":"ochre_earth","name":"赭土","look":"紅褐色的黏土，像舊鐵欄杆的鏽痕。",
		"contrast":"軟土，不是硬石塊。",
		"source":"合作礦場第 6、7 層，敲礦時另外得到。",
		"use":"可交給出貨箱出售。"},
	{"id":"vein_quartz","name":"脈石英","look":"晶洞裡的石英塊，透亮帶稜角。",
		"contrast":"是整塊的透亮晶體，不是粒狀的晶砂。",
		"source":"合作礦場第 9、10 層的晶洞，敲礦時另外得到。",
		"use":"玻璃爐可熔碎成晶砂，再做溫室玻璃。"},
	{"id":"warm_stone","name":"暖岩片","look":"摸起來微溫的橙褐色岩片。",
		"contrast":"比石材亮、比赭土乾，手感是溫的。",
		"source":"合作礦場第 12、13 層，敲礦時另外得到。",
		"use":"鋪成風鈴渡口共餐桌的保溫底座。"},
]

# ------------------------------------------------------------ eligibility --

static func _key_is_stage(key:Variant) -> bool:
	if key is int:return key==STAGE
	if key is float:return is_finite(key) and key==float(STAGE)
	if key is String or key is StringName:return str(key)==str(STAGE)
	return false

## True only when 本人 resident_goals.bobo 的第 1 階（字串 "1" 或整數 1）state 是 "done"。
static func available(snapshot:Dictionary) -> bool:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return false
	var own:Variant=(goals as Dictionary).get(RESIDENT)
	if not own is Dictionary:return false
	for key in (own as Dictionary):
		if not _key_is_stage(key):continue
		var entry:Variant=(own as Dictionary)[key]
		if entry is Dictionary:
			var state:Variant=(entry as Dictionary).get("state")
			if (state is String or state is StringName) and str(state)=="done":return true
	return false

static func _snapshot(app) -> Dictionary:
	if app==null or not is_instance_valid(app):return {}
	var session:Variant=app.get("session")
	if session==null:return {}
	var snap:Variant=session.get("snapshot")
	return snap if snap is Dictionary else {}

# ------------------------------------------------------------------- open --

static func open(app,return_to:Callable=Callable(),show_scene:=false) -> void:
	if not available(_snapshot(app)):return
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("suppress_world_prompts",true)
	app.modal.set_meta(MET_BODY,body)
	body.add_theme_constant_override("separation",8)
	if show_scene:_story_page(app,body,return_to)
	else:
		_guide_page(app,body,return_to,START_ID)
		_focus.call_deferred(app,body,"BoboRockSample_"+START_ID)
	app._layout_preview.call_deferred()

static func _clear(body:Control) -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()

static func _alive(app,body:Control) -> bool:
	return is_instance_valid(app) and is_instance_valid(body) and is_instance_valid(app.modal) and app.modal.get_meta(MET_BODY,null)==body

static func _focus(app,body:Control,name_text:String) -> void:
	if not _alive(app,body):return
	var target:=body.find_child(name_text,true,false) as BaseButton
	if target!=null and target.is_visible_in_tree() and not target.disabled:target.grab_focus()

static func _text(app,parent:Node,line:String,extent:int=16) -> Label:
	var result:Label=app.label(line,extent)
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(result)
	return result

static func _back_button(app,parent:Node,return_to:Callable) -> Button:
	var back:Button=app.button("返回" if return_to.is_valid() else "關閉",
		return_to if return_to.is_valid() else Callable(app,"_close_modal"))
	back.name="BoboRockBack"
	back.size_flags_horizontal=Control.SIZE_SHRINK_END
	parent.add_child(back)
	return back

# ------------------------------------------------------------------ story --

static func _story_page(app,body:VBoxContainer,return_to:Callable) -> void:
	_clear(body)
	app.modal.name="BoboRockStory"
	var story:=VBoxContainer.new()
	story.name=SCENE_ID
	story.add_theme_constant_override("separation",8)
	story.custom_minimum_size.x=580
	story.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	story.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(story)
	var sound:Variant=app.get("sound")
	var reduced:bool=true if sound==null else bool(sound.get("reduced_motion"))
	var art:Control=Art.make(reduced)
	art.name="BoboRockStoryArt"
	art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	if art.custom_minimum_size==Vector2.ZERO:art.custom_minimum_size=Vector2(580,190)
	story.add_child(art)
	_text(app,story,STORY_LINE,17)
	var row:=HBoxContainer.new()
	row.alignment=BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation",12)
	story.add_child(row)
	var read:Button=app.button("翻開礦石辨識頁",func():
		if not _alive(app,body):return
		_guide_page(app,body,return_to,START_ID)
		_focus.call_deferred(app,body,"BoboRockSample_"+START_ID))
	read.name="BoboRockRead"
	row.add_child(read)
	_back_button(app,row,return_to)
	_focus.call_deferred(app,body,"BoboRockRead")
	app._layout_preview.call_deferred()

# ------------------------------------------------------------------ guide --

static func _sample(id:String) -> Dictionary:
	for entry:Dictionary in SAMPLES:
		if entry.id==id:return entry
	return SAMPLES[0]

static func _guide_page(app,body:VBoxContainer,return_to:Callable,selected:String) -> void:
	_clear(body)
	app.modal.name="BoboRockGuide"
	var head:=HBoxContainer.new()
	head.add_theme_constant_override("separation",12)
	body.add_child(head)
	head.add_child(Shell.picture(Items.icon("stone"),48))
	var intro:=VBoxContainer.new()
	intro.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	head.add_child(intro)
	_text(app,intro,"點一塊樣本，看波波怎麼認它",19)
	_text(app,intro,"看顏色、軟硬和手感，再想它在哪裡、能拿來做什麼。",15)

	var grid:=GridContainer.new()
	grid.name="BoboRockSamples"
	grid.columns=4
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	body.add_child(grid)
	var group:=ButtonGroup.new()
	var buttons:Dictionary={}

	var card:=PanelContainer.new()
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	card.size_flags_vertical=Control.SIZE_EXPAND_FILL

	var detail:=HBoxContainer.new()
	detail.add_theme_constant_override("separation",14)
	card.add_child(detail)
	var picture:=Shell.picture(Items.icon(selected),72)
	detail.add_child(picture)
	var lines:=VBoxContainer.new()
	lines.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation",4)
	detail.add_child(lines)
	var name_label:=_text(app,lines,"",20)
	name_label.name="BoboRockName"
	var look:=_text(app,lines,"",16)
	look.name="BoboRockLook"
	var contrast:=_text(app,lines,"",15)
	contrast.name="BoboRockContrast"
	var source:=_text(app,lines,"",16)
	source.name="BoboRockSource"
	var use:=_text(app,lines,"",16)
	use.name="BoboRockUse"

	var show:=func(id:String) -> void:
		var entry:=_sample(id)
		picture.texture=Items.icon(id)
		name_label.text=entry.name
		look.text="外觀：%s"%entry.look
		contrast.text="對比：%s"%entry.contrast
		source.text="來源：%s"%entry.source
		use.text="用途：%s"%entry.use
		body.set_meta("rock_selected",id)

	for entry:Dictionary in SAMPLES:
		var id:String=entry.id
		var pick:Button=app.button(entry.name,func():
			if _alive(app,body):show.call(id))
		pick.name="BoboRockSample_"+id
		pick.icon=Items.icon(id)
		pick.expand_icon=true
		pick.alignment=HORIZONTAL_ALIGNMENT_LEFT
		pick.toggle_mode=true
		pick.button_group=group
		pick.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		pick.custom_minimum_size=Vector2(0,46)
		pick.add_theme_constant_override("icon_max_width",32)
		pick.tooltip_text=entry.name
		grid.add_child(pick)
		buttons[id]=pick

	body.add_child(card)
	(buttons[selected] as Button).set_pressed_no_signal(true)
	show.call(selected)

	var row:=HBoxContainer.new()
	row.alignment=BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation",12)
	body.add_child(row)
	var replay:Button=app.button("重看排石頭",func():
		if not _alive(app,body):return
		_story_page(app,body,return_to))
	replay.name="BoboRockReplay"
	row.add_child(replay)
	_back_button(app,row,return_to)
	app._layout_preview.call_deferred()
