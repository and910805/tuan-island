extends RefCounted
## T066 N04-3 〈一場沒有流程的茶會〉：完成後可重看的三段對話頁。
## 只讀自己的 resident_goals.chacha["3"]（state=="done"，選填 "topics"＝三位數排列字串）；
## 不寫入、不改任何進度。沒有存下順序的舊存檔只顯示一張簡短回憶，不編造玩家排序。

const World=preload("res://scripts/world.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Art=preload("res://scripts/chacha_tea_gathering_art.gd")

const RESIDENT:="chacha"
const STAGE:=3
const TOPICS:=3
const FONT_MAX:=19

## 依話題編號 0 茶、1 天氣、2 學會的事；每個話題一小段對話。
const BEATS:=[
	["茶茶：「今年的茶，我只敢說比去年更像我想的味道。」","你：「那我再續一杯。」"],
	["你：「山上的雲說來就來，剛剛還看得到對面的山。」","茶茶：「再坐一下吧。說不定喝完這杯，山就回來了。」"],
	["茶茶：「我最近學會了把『還沒好』說出口。」","你：「聽起來比把事情做完還難一點。」"],
]
const ORDINALS:=["先聊","接著聊","最後聊"]
const LEGACY_NOTE:="那天聊了今年的茶、山上的天氣，也聊了最近學會的事。手帳沒有記下聊的先後，只記得大家都沒急著離開。"

static func available(snapshot:Dictionary) -> bool:
	return not _stage(snapshot).is_empty()

## 回傳 [] 表示沒有（或無效的）存下順序；否則是 [a,b,c] 的話題編號。
static func order(snapshot:Dictionary) -> Array:
	var text:Variant=_stage(snapshot).get("topics")
	return Goals.sequence(text) if text is String else []

static func _stage(snapshot:Dictionary) -> Dictionary:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return {}
	var chacha:Variant=goals.get(RESIDENT)
	if not chacha is Dictionary:return {}
	var entry:Variant=chacha.get(str(STAGE),chacha.get(STAGE))
	if not entry is Dictionary:return {}
	if str(entry.get("state"))!="done":return {}
	return entry

static func open(app,back:Callable,back_text:String="返回關係事件") -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not available(snapshot):return
	var goal:Dictionary=Goals.GOALS[RESIDENT][STAGE]
	var body:VBoxContainer=app._open_modal(str(goal.title))
	app.modal.name="ChachaGathering"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","chacha_tea_gathering")
	body.add_theme_constant_override("separation",8)

	var picked:Array=order(snapshot)
	app.modal.set_meta("compact_tea_recollection",picked.is_empty())
	# 有順序：三段對話＋結尾；舊存檔：一張回憶。
	var pages:=picked.size()+1 if not picked.is_empty() else 1
	var state:={"page":0}

	var column:=VBoxContainer.new()
	column.name="ChachaGatheringPage"
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",8)
	body.add_child(column)

	var sound:Variant=app.get("sound")
	var reduced:bool=true if sound==null else bool(sound.get("reduced_motion"))
	var art:Control=Art.make(reduced)
	art.name="ChachaGatheringArt"
	art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	column.add_child(art)

	var holder:=VBoxContainer.new()
	holder.name="ChachaGatheringText"
	holder.add_theme_constant_override("separation",6)
	holder.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(holder)

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
	var previous:=Button.new()
	previous.text="上一段"
	previous.custom_minimum_size.y=42
	previous.name="ChachaGatheringPrevious"
	var next:=Button.new()
	next.text="下一段"
	next.custom_minimum_size.y=42
	next.name="ChachaGatheringNext"
	var close:Button=app.button(back_text,back)
	close.name="ChachaGatheringBack"
	nav.add_child(previous)
	nav.add_child(next)
	nav.add_child(close)
	if pages==1:
		previous.visible=false
		next.visible=false
	previous.disabled=true

	var show:=func() -> void:
		if not is_instance_valid(holder) or not holder.is_inside_tree():return
		for child in holder.get_children():
			holder.remove_child(child)
			child.queue_free()
		var page:int=state.page
		previous.disabled=page<=0
		next.disabled=page>=pages-1
		if picked.is_empty():
			_legacy(app,holder,goal)
		elif page<picked.size():
			var topic:int=picked[page]
			_beat(app,holder,page,topic,goal)
			art.call("show_topic",topic)
		else:
			_ending(app,holder,goal)
		app._layout_preview.call_deferred()
	previous.pressed.connect(func():
		if state.page>0:
			state.page-=1
			show.call()
			if previous.disabled and not next.disabled:next.grab_focus())
	next.pressed.connect(func():
		if state.page<pages-1:
			state.page+=1
			show.call()
			if next.disabled and not previous.disabled:previous.grab_focus())
	show.call()
	(close if pages==1 else next).grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func _beat(app,holder:Container,page:int,topic:int,goal:Dictionary) -> void:
	var steps:Array=goal.steps
	var head:=_text(app,holder,"%s〈%s〉　%d／%d"%[ORDINALS[page],str(steps[topic]),page+1,TOPICS],FONT_MAX)
	head.name="ChachaGatheringTopic"
	var card:=PanelContainer.new()
	card.name="ChachaGatheringBeat"
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	holder.add_child(card)
	var lines:=VBoxContainer.new()
	lines.add_theme_constant_override("separation",6)
	card.add_child(lines)
	for line:String in BEATS[topic]:_text(app,lines,line,17)

static func _legacy(app,holder:Container,goal:Dictionary) -> void:
	var recollection:=_text(app,holder,LEGACY_NOTE,16)
	recollection.name="ChachaGatheringRecollection"
	_quote(app,holder,goal)
	_preview(app,holder)

static func _ending(app,holder:Container,goal:Dictionary) -> void:
	var head:=_text(app,holder,"茶會的最後",FONT_MAX)
	head.name="ChachaGatheringHeading"
	_quote(app,holder,goal)
	_preview(app,holder)

static func _quote(app,holder:Container,goal:Dictionary) -> void:
	var card:=PanelContainer.new()
	card.name="ChachaGatheringQuote"
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	holder.add_child(card)
	var lines:=VBoxContainer.new()
	lines.add_theme_constant_override("separation",4)
	card.add_child(lines)
	for line in goal.get("quote",[]):_text(app,lines,str(line),17)

static func _preview(app,holder:Container) -> void:
	var kind:String=World.INDUSTRY.IMPERFECT_TEA_PAVILION
	if not World.BUILD.has(kind):return
	var row:=HBoxContainer.new()
	row.alignment=BoxContainer.ALIGNMENT_END
	holder.add_child(row)
	var preview:Button=app.button("翻看不完美的茶亭圖樣",func():app.life_panels.build_menu(app,kind))
	preview.name="ChachaGatheringPreview"
	row.add_child(preview)

static func _text(app,parent:Node,copy:String,extent:int) -> Label:
	var label:Label=app.label(copy,min(extent,FONT_MAX))
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(label)
	return label
