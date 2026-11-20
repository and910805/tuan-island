extends RefCounted

const World=preload("res://scripts/world.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const PixelTheme=preload("res://scripts/inventory_pixel_theme.gd")
const LifeTasks=preload("res://scripts/life_ui_tasks.gd")

const LAYOUT:="rounded_table"
const META:="rounded_table_ui"
const SLOTS:=World.INDUSTRY.ROUNDED_CAPACITY

static func open(app,cell:Vector2i) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var anchor:=World.station_anchor(snapshot.get("objects",{}),cell)
	var tile:=World.key(anchor)
	var table:Dictionary=snapshot.get("objects",{}).get(tile,{})
	if table.get("type")!=World.INDUSTRY.ROUNDED_TABLE:return
	var own:bool=table.get("owner")==app.session.own_id
	var page:VBoxContainer=app._open_modal("圓角木桌")
	app.modal.set_meta("life_modal_layout",LAYOUT)
	page.add_theme_constant_override("separation",8)
	# --- public display: two slots side by side ---
	var display:=LifeTasks.card(page)
	var hint:Label=LifeTasks.line(app,display,"",14)
	var slots_row:=HBoxContainer.new()
	slots_row.add_theme_constant_override("separation",12)
	slots_row.alignment=BoxContainer.ALIGNMENT_CENTER
	display.add_child(slots_row)
	var slots:Array[Dictionary]=[]
	for index in SLOTS:
		var box:=PanelContainer.new()
		box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		box.custom_minimum_size=Vector2(0,140)
		box.add_theme_stylebox_override("panel",PixelTheme.paper_style())
		slots_row.add_child(box)
		var col:=VBoxContainer.new()
		col.add_theme_constant_override("separation",4)
		box.add_child(col)
		var icon:=TextureRect.new()
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size=Vector2(56,56)
		icon.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		col.add_child(icon)
		var name_label:Label=LifeTasks.line(app,col,"",15)
		name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var buttons:=HBoxContainer.new()
		buttons.alignment=BoxContainer.ALIGNMENT_CENTER
		buttons.add_theme_constant_override("separation",6)
		col.add_child(buttons)
		var eat:Button=app.button("享用",func():_eat(app,tile,anchor,index))
		eat.name="RoundedTableEat%d"%index
		buttons.add_child(eat)
		var take:Button=null
		if own:
			take=app.button("取回",func():_take(app,tile,anchor,index))
			take.name="RoundedTableTake%d"%index
			buttons.add_child(take)
		# optional compact flower swap, owner only, shown only for vases
		var bloom:OptionButton=null
		var swap:Button=null
		if own:
			var flowers:=HBoxContainer.new()
			flowers.add_theme_constant_override("separation",6)
			flowers.visible=false
			col.add_child(flowers)
			bloom=OptionButton.new()
			bloom.name="RoundedTableBloom%d"%index
			bloom.clip_text=true
			bloom.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			for flower:String in World.INDUSTRY.TABLE_VASE_BLOOMS.values():
				bloom.add_icon_item(ItemArt.icon(flower),World.NAMES.get(flower,flower))
				bloom.set_item_metadata(bloom.item_count-1,flower)
			flowers.add_child(bloom)
			swap=app.button("換花",func():_swap(app,tile,anchor,index))
			swap.name="RoundedTableSwap%d"%index
			flowers.add_child(swap)
		slots.append({"icon":icon,"name":name_label,"eat":eat,"take":take,"bloom":bloom,"swap":swap})
	# --- owner-only inventory picker ---
	var picker:OptionButton=null
	var put:Button=null
	if own:
		var actions:=HBoxContainer.new()
		actions.add_theme_constant_override("separation",8)
		display.add_child(actions)
		picker=OptionButton.new()
		picker.name="RoundedTablePick"
		picker.clip_text=true
		picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		picker.custom_minimum_size=Vector2(0,40)
		actions.add_child(picker)
		put=app.button("擺上桌面",func():
			if picker.selected<0:return
			var item:Variant=picker.get_item_metadata(picker.selected)
			if item is String:app.session.perform(World.INDUSTRY.SHELL_PUT,anchor,item))
		put.name="RoundedTablePut"
		actions.add_child(put)
	LifeTasks.tea_set_emote_row(app,page)
	app.modal.set_meta(META,{"region":snapshot.get("region_id","home"),"tile":tile,"anchor":anchor,"own":own,"hint":hint,"slots":slots,"picker":picker,"put":put,"bag":{}})
	refresh(app)

static func _item_at(app,tile:String,index:int) -> String:
	var shown:=World.INDUSTRY.rounded_table_slots(app.session.snapshot.get("objects",{}).get(tile,{}).get("items",{}))
	return shown[index] if index<shown.size() else ""

static func _eat(app,tile:String,anchor:Vector2i,index:int) -> void:
	var id:=_item_at(app,tile,index)
	if not id.is_empty() and World.INDUSTRY.shareable_meal(id,World.RECIPES):
		app.session.perform(World.INDUSTRY.ROUNDED_EAT,anchor,id)

static func _take(app,tile:String,anchor:Vector2i,index:int) -> void:
	var id:=_item_at(app,tile,index)
	if not id.is_empty():app.session.perform(World.INDUSTRY.SHELL_TAKE,anchor,id)

static func _swap(app,tile:String,anchor:Vector2i,index:int) -> void:
	var ui:Dictionary=app.modal.get_meta(META,{})
	if ui.is_empty():return
	var slot:Dictionary=ui.slots[index]
	var bloom:OptionButton=slot.bloom
	var vase:String=_item_at(app,tile,index)
	if bloom==null or bloom.selected<0 or not World.INDUSTRY.TABLE_VASE_BLOOMS.has(vase):return
	var flower:Variant=bloom.get_item_metadata(bloom.selected)
	if flower is String:
		app.session.perform(World.INDUSTRY.TABLE_VASE_SWAP,anchor,"%s:%s"%[vase,flower])

## An item can only be put on the table if it is a shareable meal or a valid display item.
static func _placeable(id:String) -> bool:
	if not World.ITEM_CATALOG.is_known(id):return false
	return World.INDUSTRY.rounded_table_item(id,World.RECIPES)

static func refresh(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta(META):return
	var ui:Dictionary=app.modal.get_meta(META)
	var snapshot:Dictionary=app.session.snapshot
	var table:Dictionary=snapshot.get("objects",{}).get(ui.tile,{})
	if table.get("type")!=World.INDUSTRY.ROUNDED_TABLE or snapshot.get("region_id","home")!=ui.region or (table.get("owner")==app.session.own_id)!=ui.own:
		app._close_modal()
		return
	var shown:=World.INDUSTRY.rounded_table_slots(table.get("items",{}))
	LifeTasks.refresh_tea_set_emotes(app,table)
	var inventory:Dictionary=LifeTasks.player(app).get("inventory",{})
	ui.hint.text="上桌 %d／%d · 所有來客都能享用料理"%[shown.size(),SLOTS]
	for index in SLOTS:
		var slot:Dictionary=ui.slots[index]
		var id:String=shown[index] if index<shown.size() else ""
		slot.icon.texture=ItemArt.icon(id if not id.is_empty() else "seashell")
		slot.icon.modulate.a=1.0 if not id.is_empty() else 0.25
		slot.name.text=World.NAMES.get(id,id) if not id.is_empty() else "空位"
		slot.name.modulate.a=1.0 if not id.is_empty() else 0.55
		var food:=not id.is_empty() and World.INDUSTRY.shareable_meal(id,World.RECIPES)
		slot.eat.visible=food
		if slot.take!=null:slot.take.visible=not id.is_empty()
		_refresh_bloom(slot,id,inventory)
	if ui.picker==null:return
	var picker:OptionButton=ui.picker
	var available:Dictionary={}
	for item:String in inventory:
		if int(inventory[item])>0 and _placeable(item):available[item]=int(inventory[item])
	if ui.bag!=available or picker.item_count==0:
		var prior:Variant=picker.get_item_metadata(picker.selected) if picker.selected>=0 else null
		var keys:=available.keys()
		keys.sort()
		picker.clear()
		for item:String in keys:
			picker.add_icon_item(ItemArt.icon(item),"%s ×%d"%[World.NAMES.get(item,item),available[item]])
			picker.set_item_metadata(picker.item_count-1,item)
			if item==prior:picker.select(picker.item_count-1)
		if keys.is_empty():picker.add_item("背包裡沒有可擺上桌的物品")
		elif picker.selected<0:picker.select(0)
		ui.bag=available
	var full:=shown.size()>=SLOTS
	picker.get_parent().visible=not full
	picker.disabled=available.is_empty()
	ui.put.disabled=full or picker.disabled

static func _refresh_bloom(slot:Dictionary,id:String,inventory:Dictionary) -> void:
	var bloom:OptionButton=slot.bloom
	if bloom==null:return
	var current:String=World.INDUSTRY.TABLE_VASE_BLOOMS.get(id,"")
	bloom.get_parent().visible=not current.is_empty()
	if current.is_empty():return
	var first:=-1
	for i in bloom.item_count:
		var flower:String=bloom.get_item_metadata(i)
		var amount:=int(inventory.get(flower,0))
		var blocked:=flower==current or amount<=0
		bloom.set_item_disabled(i,blocked)
		bloom.set_item_text(i,"%s · 瓶中"%World.NAMES.get(flower,flower) if flower==current else "%s ×%d"%[World.NAMES.get(flower,flower),amount])
		if not blocked and first<0:first=i
	if bloom.selected<0 or bloom.is_item_disabled(bloom.selected):
		if first>=0:bloom.select(first)
	bloom.disabled=first<0
	slot.swap.disabled=first<0
