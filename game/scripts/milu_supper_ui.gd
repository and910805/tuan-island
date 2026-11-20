extends RefCounted
## N02-4 invitation planning at the common table and its illustrated memory.

const World=preload("res://scripts/world.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const People=preload("res://scripts/life_ui_theme.gd")
const Scene=preload("res://scripts/milu_supper_scene.gd")
const REACH:=3.2
const INK:=Color("493020")
const GREEN:=Color("385740")
const MUTED:=Color("735842")

static func story(snapshot:Dictionary) -> Dictionary:
	return snapshot.get("resident_goals",{}).get("milu",{}).get("4",{})

static func done(snapshot:Dictionary) -> bool:
	return story(snapshot).get("state")=="done"

static func near_table(app,snapshot:Dictionary) -> bool:
	if snapshot.get("region_id")!=World.REGIONS.HOME:return false
	var cell:=World.COMMUNITY.table_cell(snapshot)
	if cell==World.COMMUNITY.NO_CELL:return false
	var person:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	return not person.is_empty() and Vector2(float(person.x),float(person.y)).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=REACH

static func served(snapshot:Dictionary) -> bool:
	for need:Dictionary in story(snapshot).get("needs",[]):
		if need.get("id")=="shared_meal":return bool(need.get("met",false))
	return false

static func table_entry(app,holder:Container,back:Callable) -> void:
	var button:Button=app.button("安排共餐座位",open_plan.bind(app,back,"回到共餐桌"))
	button.name="MiluSupperPlanEntry"
	button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	holder.add_child(button)
	sync_table_entry(app)

static func sync_table_entry(app) -> void:
	var button:=app.modal.find_child("MiluSupperPlanEntry",true,false) as Button
	if button==null:return
	var snapshot:Dictionary=app.session.snapshot
	button.visible=story(snapshot).get("state")=="open" and near_table(app,snapshot)

static func open_plan(app,back:Callable,back_label:String) -> void:
	if story(app.session.snapshot).get("state")!="open" or not near_table(app,app.session.snapshot):return
	var body:=open_page(app,"和米露一起留一桌","MiluSupperPlan","milu_supper_plan")
	var description:=line(app,body,"你和米露各留一個位子，另外兩個位子可以邀居民來坐。",17,GREEN)
	description.name="MiluSupperPlanDescription"
	var guests:=HBoxContainer.new()
	guests.add_theme_constant_override("separation",10)
	body.add_child(guests)
	for id:String in World.MILU_SUPPER.INVITEES:
		var column:=VBoxContainer.new()
		column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		column.alignment=BoxContainer.ALIGNMENT_CENTER
		guests.add_child(column)
		var portrait:=Shell.picture(People.icon("milu" if id=="lingpopo" else id),64)
		if id=="lingpopo":portrait.modulate=Scene.LINGPOPO_TINT
		portrait.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		column.add_child(portrait)
		var button:Button=app.button("",invite.bind(app,id))
		button.name="MiluSupperInvite_"+id
		button.toggle_mode=true
		column.add_child(button)
	var progress:=line(app,body,"",16,INK)
	progress.name="MiluSupperPlanStatus"
	var row:=actions(app,body)
	add_back(app,row,back,back_label,"MiluSupperPlanBack")
	refresh(app)
	app._layout_preview.call_deferred()

static func invite(app,id:String) -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not near_table(app,snapshot):return
	app.session.perform(World.MILU_SUPPER.ACTION,World.COMMUNITY.table_cell(snapshot),id)
	refresh(app)

static func refresh(app) -> void:
	if not is_instance_valid(app.modal) or app.modal.name!="MiluSupperPlan":return
	var snapshot:Dictionary=app.session.snapshot
	var open:bool=story(snapshot).get("state")=="open"
	var at_table:=near_table(app,snapshot)
	var has_served:=served(snapshot)
	var guests:Array=snapshot.get("own_milu_supper",{}).get("guests",[])
	for id:String in World.MILU_SUPPER.INVITEES:
		var button:=app.modal.find_child("MiluSupperInvite_"+id,true,false) as Button
		var chosen:=id in guests
		var present:=World.RESIDENT_BOND.present(snapshot,id)
		button.text=(("已邀請 " if chosen else "邀請 ") if present or chosen else "稍後邀請 ")+World.RESIDENT_BOND.name_of(id)
		button.set_pressed_no_signal(chosen)
		button.tooltip_text="取消這位居民的邀請" if chosen else ""
		button.disabled=not open or not at_table or not has_served or (not chosen and (not present or guests.size()>=World.MILU_SUPPER.MAX_GUESTS))
	var status:=app.modal.find_child("MiluSupperPlanStatus",true,false) as Label
	if not open:status.text="這場共餐已記進手帳。"
	elif not at_table:status.text="走到渡口共餐桌旁，就能安排座位。"
	elif not has_served:status.text="先親手端四份料理上桌，就可以邀居民。"
	else:status.text="已邀請 %d／2 位。準備好了就去找米露，也可以只和米露一起吃。"%guests.size()

static func open_book(app,back:Callable,back_label:String) -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not done(snapshot):return
	var record:Dictionary=snapshot.get("own_milu_supper",{})
	var body:=open_page(app,"米露的共餐食譜","MiluSupperBook","milu_supper_book")
	var spread:=HBoxContainer.new()
	spread.add_theme_constant_override("separation",14)
	body.add_child(spread)
	var scene:=Scene.new()
	scene.name="MiluSupperScene"
	scene.dish=str(record.get("dish",""))
	scene.guests.assign(record.get("guests",[]))
	scene.reduced_motion=app.sound.reduced_motion
	scene.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	spread.add_child(scene)
	var cover:=VBoxContainer.new()
	cover.add_theme_constant_override("separation",7)
	cover.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	cover.alignment=BoxContainer.ALIGNMENT_CENTER
	spread.add_child(cover)
	line(app,cover,"記得替自己留一碗",20,GREEN)
	for quote:String in World.RESIDENT_GOALS.goal("milu",4).quote:
		line(app,cover,"「%s」"%quote,15,INK)
	var names:=PackedStringArray()
	for id:String in scene.guests:names.append(World.RESIDENT_BOND.name_of(id))
	if not names.is_empty():line(app,cover,"一起入席的居民  %s"%"、".join(names),14,MUTED)
	var group:=HBoxContainer.new()
	group.add_theme_constant_override("separation",8)
	body.add_child(group)
	var recipes:Dictionary=World.stove_recipes(World.KITCHEN_STOVE.KIND)
	for item:String in World.COMMUNITY.DISHES.values():
		var recipe:Dictionary=recipes[item]
		var tile:=PanelContainer.new()
		tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tile.custom_minimum_size.x=160
		tile.add_theme_stylebox_override("panel",paper())
		group.add_child(tile)
		var column:=VBoxContainer.new()
		tile.add_child(column)
		var icon:=Shell.picture(Items.icon(item),40)
		icon.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		column.add_child(icon)
		line(app,column,str(recipe.name),16,GREEN).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var ingredients:=PackedStringArray()
		for ingredient:String in recipe.ingredients:
			ingredients.append("%s ×%d"%[World.NAMES[ingredient],int(recipe.ingredients[ingredient])])
		line(app,column,"、".join(ingredients),14,INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		line(app,column,"%d 份 · %d 秒"%[int(recipe.yield),int(recipe.time)],14,MUTED).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	line(app,body,"米露的圍裙可在渡口找她試穿，也可在家園的更衣櫃更換。",15,GREEN)
	var row:=actions(app,body)
	if not scene.reduced_motion:
		var replay:Button=app.button("重播入席",func():
			scene.replay()
			app.sound.defer_action("meal_serve"))
		replay.name="MiluSupperReplay"
		row.add_child(replay)
	add_back(app,row,back,back_label,"MiluSupperBack")
	app._layout_preview.call_deferred()

static func open_page(app,title:String,identity:String,layout:String) -> VBoxContainer:
	var body:VBoxContainer=app._open_modal(title)
	app.modal.name=identity
	app.modal.set_meta("life_modal_layout",layout)
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_theme_constant_override("separation",12)
	return body

static func actions(app,body:VBoxContainer) -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.alignment=BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation",8)
	if is_instance_valid(app.modal_feedback) and app.modal.is_ancestor_of(app.modal_feedback):
		var footer:Label=app.modal_feedback
		footer.get_parent().add_child(row)
		footer.reparent(row,false)
		footer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		footer.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	else:
		body.add_child(row)
	return row

static func add_back(app,row:HBoxContainer,back:Callable,copy:String,identity:String) -> void:
	var button:Button=app.button(copy,back)
	button.name=identity
	row.add_child(button)
	button.grab_focus.call_deferred()

static func line(app,parent:Container,copy:String,pixels:int,color:Color) -> Label:
	var text:Label=app.label(copy,pixels)
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color",color)
	parent.add_child(text)
	return text

static func paper() -> StyleBoxFlat:
	var trim:=StyleBoxFlat.new()
	trim.bg_color=Color("ead8b0")
	trim.border_color=Color("aa895b")
	trim.set_border_width_all(1)
	trim.set_content_margin_all(8)
	return trim
