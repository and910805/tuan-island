extends RefCounted

const World=preload("res://scripts/world.gd")
const Postcards=World.POSTCARDS
const Art=preload("res://scripts/travel_postcard_art.gd")

static func open(app,cell:Vector2i)->void:
	var body:VBoxContainer=app._open_modal("海風明信片架")
	app.modal.set_meta("life_modal_layout","postcard_rack")
	app.modal.set_meta("postcard_rack",{"cell":cell,"region":app.session.snapshot.get("region_id","home"),"body":body,"rendered":[]})
	refresh(app)

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("postcard_rack"):return
	var ui:Dictionary=app.modal.get_meta("postcard_rack")
	var snapshot:Dictionary=app.session.snapshot
	var rack:Dictionary=snapshot.get("objects",{}).get(World.key(ui.cell),{})
	if rack.get("type")!=Postcards.RACK or snapshot.get("region_id","home")!=ui.region:
		app._close_modal()
		return
	var shown:Array=rack.get(Postcards.SLOTS,[])
	var own:bool=rack.get("owner","")==app.session.own_id
	var earned:Array=snapshot.get("own_postcards",[]) if own else []
	var values:=[shown,own,earned]
	if values==ui.rendered:return
	ui.rendered=values.duplicate(true)
	var page:VBoxContainer=ui.body
	for child:Node in page.get_children():
		page.remove_child(child)
		child.queue_free()
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	page.add_child(row)
	for index in Postcards.CAPACITY:
		var body:VBoxContainer=app.LifeTasks.card(row)
		(body.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var id:String=shown[index] if index<shown.size() else ""
		var picture:=TextureRect.new()
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		picture.custom_minimum_size=Vector2(106,66)
		picture.texture=Art.texture(id)
		body.add_child(picture)
		var caption:Label=app.LifeTasks.line(app,body,Postcards.CARDS.get(id,"空展示位"),16)
		caption.name="PostcardLabel_"+str(index)
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		if own and id!="":
			var clear:Button=app.button("收起",func():app.session.perform(Postcards.TAKE,ui.cell,id))
			clear.name="PostcardClear_"+id
			body.add_child(clear)
	if not own:return
	var available:=earned.filter(func(id):return id not in shown and Postcards.CARDS.has(id))
	app.LifeTasks.line(app,page,"旅行收藏 %d／%d"%[earned.size(),Postcards.CARDS.size()],14)
	if shown.size()>=Postcards.CAPACITY:return
	if available.is_empty():
		if earned.is_empty():app.LifeTasks.line(app,page,"搭船或轉乘到新地方，就能收藏明信片。",15)
		return
	var actions:=HBoxContainer.new()
	page.add_child(actions)
	var picker:=OptionButton.new()
	picker.name="PostcardPicker"
	picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for id:String in available:
		picker.add_item(Postcards.CARDS[id])
		picker.set_item_metadata(picker.item_count-1,id)
	actions.add_child(picker)
	var put:Button=app.button("擺上架",func():
		if picker.selected>=0:app.session.perform(Postcards.PUT,ui.cell,str(picker.get_item_metadata(picker.selected))))
	put.name="PostcardPlace"
	actions.add_child(put)
