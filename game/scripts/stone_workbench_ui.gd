extends RefCounted
## C11 石工台: the compact recipe card opened from either end of the station.
##
## One card per StoneWorkshop.RECIPES entry: product picture, name and role, every material as
## icon + held／needed, and one button. "craft" rows send the authoritative `stone_craft` action
## (橋基 for the Q05 bridge); "build" rows only select the normal build tool, so placement, rotation,
## preview, collision, refund and blueprints stay the ones the Build Folio already uses. Nothing
## here unlocks anything: locked rows only mirror the server rules.

const World=preload("res://scripts/world.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const PixelTheme=preload("res://scripts/inventory_pixel_theme.gd")
const LifeTasks=preload("res://scripts/life_ui_tasks.gd")
const BuildFolio=preload("res://scripts/build_folio.gd")

const LAYOUT:="stone_workbench"
const META:="stone_workbench_ui"
const INK_SOFT:=Color("5d634a")
const SHORT:=Color("a4452c")
const READY:=Color("3f6a3a")
const NOTES:={
	"stone_floor":"庭院與石屋地面，可拖曳鋪設。",
	"small_smelter":"熔煉銅、鐵礦，占 2×2 格。",
	"bridge_foundation":"替全島添一座河灣橋的橋基。",
	"spring_stone_bench":"能與朋友同坐的暖泉長凳。",
	"inn_stone_footbath":"暖泉旅店的石造泡腳池。",
}

static func open(app,cell:Vector2i) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var anchor:=World.station_anchor(snapshot.get("objects",{}),cell)
	var tile:=World.key(anchor)
	var station:Dictionary=snapshot.get("objects",{}).get(tile,{})
	if station.get("type")!=World.INDUSTRY.STONE_WORKBENCH:return
	var page:VBoxContainer=app._open_modal(World.BUILD[World.INDUSTRY.STONE_WORKBENCH].name)
	app.modal.set_meta("life_modal_layout",LAYOUT)
	page.add_theme_constant_override("separation",8)
	var card:=LifeTasks.card(page)
	var summary:Label=LifeTasks.line(app,card,"",15)
	summary.name="StoneWorkbenchSummary"
	var recipes:=GridContainer.new()
	recipes.columns=2
	recipes.add_theme_constant_override("h_separation",8)
	recipes.add_theme_constant_override("v_separation",8)
	card.add_child(recipes)
	var rows:Array[Dictionary]=[]
	for recipe:Dictionary in World.STONE_WORKSHOP.RECIPES:rows.append(_row(app,recipes,recipe,anchor))
	app.modal.set_meta(META,{"region":snapshot.get("region_id","home"),"tile":tile,"anchor":anchor,"summary":summary,"rows":rows})
	refresh(app)

static func _materials(id:String) -> Dictionary:
	if id==World.STONE_WORKSHOP.FOUNDATION:return World.STONE_WORKSHOP.FOUNDATION_COST
	var cost:Dictionary=World.BUILD.get(id,{}).duplicate()
	cost.erase("name")
	return cost

static func _title(id:String) -> String:
	return World.STONE_WORKSHOP.FOUNDATION_NAME if id==World.STONE_WORKSHOP.FOUNDATION else str(World.BUILD.get(id,{}).get("name",id))

static func _row(app,parent:Container,recipe:Dictionary,anchor:Vector2i) -> Dictionary:
	var id:String=recipe.id
	var craft:bool=recipe.route=="craft"
	var panel:=PanelContainer.new()
	panel.name="StoneRecipe_"+id
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",PixelTheme.paper_style())
	parent.add_child(panel)
	var line:=HBoxContainer.new()
	line.add_theme_constant_override("separation",8)
	panel.add_child(line)
	if craft:
		var picture:TextureRect=app.life_panels.item_picture(ItemArt.icon("stone"),40)
		picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		line.add_child(picture)
	else:
		app.life_panels.build_picture(line,id,1)
	var info:=VBoxContainer.new()
	info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation",2)
	line.add_child(info)
	var heading:=HBoxContainer.new()
	heading.add_theme_constant_override("separation",6)
	info.add_child(heading)
	var title:Label=app.label(_title(id),17)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var note:Label=LifeTasks.line(app,info,"",13)
	note.add_theme_color_override("font_color",INK_SOFT)
	var mats:=HBoxContainer.new()
	mats.add_theme_constant_override("separation",10)
	info.add_child(mats)
	var chips:Array[Dictionary]=[]
	var cost:=_materials(id)
	for item:String in cost:
		var chip:=HBoxContainer.new()
		chip.name="Material_"+item
		chip.add_theme_constant_override("separation",3)
		mats.add_child(chip)
		var icon:TextureRect=app.life_panels.item_picture(ItemArt.icon(item),24)
		icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		chip.add_child(icon)
		var count:Label=app.label("",14)
		count.autowrap_mode=TextServer.AUTOWRAP_OFF
		chip.add_child(count)
		chips.append({"item":item,"need":int(cost[item]),"label":count,"chip":chip})
	var button:Button
	if craft:
		button=app.button("製作",func():app.session.perform(World.STONE_WORKSHOP.ACTION,anchor,id))
		button.name="StoneCraft_"+id
	else:
		button=app.button("前往施工",func():
			app.building=id
			app.building_style=""
			app._select_tool("build")
			app._close_modal())
		button.name="StoneRoute_"+id
	button.custom_minimum_size=Vector2(104,34)
	heading.add_child(button)
	return {"id":id,"craft":craft,"note":note,"chips":chips,"button":button}

static func refresh(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta(META):return
	var ui:Dictionary=app.modal.get_meta(META)
	var snapshot:Dictionary=app.session.snapshot
	var station:Dictionary=snapshot.get("objects",{}).get(ui.tile,{})
	if station.get("type")!=World.INDUSTRY.STONE_WORKBENCH or snapshot.get("region_id","home")!=ui.region:
		app._close_modal()
		return
	var person:Dictionary=LifeTasks.player(app)
	var bag:Dictionary=person.get("inventory",{})
	var stone=World.STONE_WORKSHOP
	var project:Variant=snapshot.get(stone.PROJECT_KEY)
	var summary:Label=ui.summary
	if snapshot.get("board",false)!=true:summary.text="公告板修復後，石工台才能製作橋基。"
	elif stone.project_pending(snapshot):summary.text="Q05 河灣橋　橋基 %d／%d　木材 %d／%d　繩索 %d／%d\n橋基在這裡製作；木材與繩索到公告板捐。"%[int(project.get("foundations",0)),stone.FOUNDATIONS_NEEDED,int(project.get("wood",0)),stone.WOOD_NEEDED,int(project.get("rope",0)),stone.ROPE_NEEDED]
	else:summary.text="河灣橋已經開通，往村東過橋探索。"
	for row:Dictionary in ui.rows:
		var id:String=row.id
		var enough:=true
		for chip:Dictionary in row.chips:
			var held:=int(bag.get(chip.item,0))
			var label:Label=chip.label
			label.text="%s %d／%d"%[World.NAMES.get(chip.item,chip.item),held,int(chip.need)]
			label.add_theme_color_override("font_color",READY if held>=int(chip.need) else SHORT)
			chip.chip.tooltip_text="%s  持有 %d／所需 %d"%[World.NAMES.get(chip.item,chip.item),held,int(chip.need)]
			enough=enough and held>=int(chip.need)
		var button:Button=row.button
		var note:Label=row.note
		if row.craft:
			var full:bool=snapshot.get("board",false)==true and stone.project_pending(snapshot) and int(project.get("foundations",0))>=stone.FOUNDATIONS_NEEDED
			var can_craft:bool=snapshot.get("board",false)==true and stone.project_pending(snapshot) and not full
			button.disabled=not can_craft or not enough
			if snapshot.get("board",false)!=true:note.text=stone.BRIDGE_WAIT_MSG
			elif not stone.project_pending(snapshot):note.text=stone.BRIDGE_DONE_MSG
			elif full:note.text="橋基備齊了，還差木材與繩索，到公告板捐。"
			else:note.text=NOTES[id]
			button.text="製作" if can_craft and enough else ("材料不足" if can_craft else ("已備齊" if full else "已完成" if snapshot.get("board",false)==true else "尚未開放"))
		else:
			var unlocked:=BuildFolio.unlocked(app,person,id)
			button.disabled=not unlocked
			note.text=NOTES[id] if unlocked else str(BuildFolio.lock_text(app,id)[0])
			button.text="前往施工" if unlocked else "尚未解鎖"
