extends RefCounted
## A permanently viewable journal page unlocked when 阿榆's 〈有點歪的第一塊板〉 (stage 1) is reported (T066 N01-1).
## Gate: the own snapshot's resident_goals.aru stage 1 state is "done" (string or int stage key). No saved key of its own,
## so every old save that already completed the story can open it. Nothing here changes build, economy or the task gate.
## Page: three planks, one per basic build kind. Name, pixel preview, cost and backpack count all come from the real
## World.BUILD / build-folio preview API; each plank opens the real build folio at its exact kind.

const World=preload("res://scripts/world.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const BoardScene=preload("res://scripts/aru_first_board_art.gd")
const NOTES:={"bed":"放在房裡，留一處休息的角落。","table":"桌面可擺茶具與小物。","chair":"靠近可坐下，移動即可起身。"}
const INK:=Color("4a3524")
const MUTED:=Color("6b5436")
const GOOD:=Color("37573e")
const SHORT:=Color("8a3d2e")

static func available(snapshot:Dictionary) -> bool:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return false
	var aru:Variant=goals.get("aru")
	if not aru is Dictionary:return false
	var event:Variant=aru.get("1",aru.get(1))
	return event is Dictionary and event.get("state")=="done"

static func open(app,back:Callable,back_label:="返回關係事件") -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not available(snapshot):return
	var body:VBoxContainer=app._open_modal("原木床桌椅基礎圖樣")
	app.modal.name="AruFirstFurniture"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	# Reuses the existing 688-wide pattern-page size; main.gd is untouched.
	app.modal.set_meta("life_modal_layout","bobo_rest_pattern")
	body.add_theme_constant_override("separation",8)

	var head:=line(app,body,"〈有點歪的第一塊板〉留下三張圖樣。挑一張，到家園工坊看看。",16)
	head.name="AruFirstFurnitureHead"
	head.add_theme_color_override("font_color",MUTED)

	var person:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var inventory:Dictionary=person.get("inventory",{})
	var row:=HBoxContainer.new()
	row.name="AruFirstFurnitureBoards"
	row.add_theme_constant_override("separation",10)
	body.add_child(row)
	var first_build:Button=null
	for kind:String in NOTES:
		var build:=plank(app,row,kind,inventory)
		if first_build==null:first_build=build

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
	var story:Button=app.button("重看第一塊板",open_story.bind(app,open.bind(app,back,back_label)))
	story.name="AruFirstFurnitureStory"
	actions.add_child(story)
	var close:Button=app.button(back_label,back)
	close.name="AruFirstFurnitureBack"
	actions.add_child(close)
	(first_build if first_build!=null else close).grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func open_story(app,back:Callable) -> void:
	var body:VBoxContainer=app._open_modal("有點歪的第一塊板")
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.set_meta("life_modal_layout","bobo_rest_pattern")
	var scene:=BoardScene.new()
	scene.name="AruFirstBoardScene"
	scene.reduced_motion=app.sound.reduced_motion
	scene.board_placed.connect(app.sound.defer_action.bind("build_set"))
	scene.custom_minimum_size=Vector2(560,224)
	scene.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	body.add_child(scene)
	var dialogue:Dictionary=World.RESIDENT_GOALS.goal("aru",1)
	for quote:String in dialogue.quote:
		line(app,body,quote,16)
	var buttons:=HBoxContainer.new()
	buttons.alignment=BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation",8)
	body.add_child(buttons)
	var replay:Button=app.button("再看一次",scene.replay)
	replay.name="AruFirstBoardReplay"
	replay.visible=not scene.reduced_motion
	buttons.add_child(replay)
	var close:Button=app.button("返回木工圖樣",back)
	close.name="AruFirstBoardBack"
	buttons.add_child(close)
	close.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

## One plank shows the actual furniture art, recipe costs and workshop link.
static func plank(app,parent:Container,kind:String,inventory:Dictionary) -> Button:
	var board:=PanelContainer.new()
	board.name="AruFirstFurniturePlank_"+kind
	board.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var wood:=StyleBoxFlat.new()
	wood.bg_color=Color("e0c493")
	wood.border_color=Color("8a6a43")
	wood.set_border_width_all(2)
	wood.border_width_bottom=5
	wood.set_corner_radius_all(2)
	wood.set_content_margin_all(8)
	board.add_theme_stylebox_override("panel",wood)
	parent.add_child(board)
	var col:=VBoxContainer.new()
	col.add_theme_constant_override("separation",5)
	board.add_child(col)

	var stage:=PanelContainer.new()
	stage.name="AruFirstFurnitureArt_"+kind
	stage.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	stage.mouse_filter=Control.MOUSE_FILTER_IGNORE
	stage.add_theme_stylebox_override("panel",Pixel.paper_style())
	col.add_child(stage)
	app.life_panels.build_picture(stage,kind,2)

	var recipe:Dictionary=World.BUILD[kind]
	var title:=line(app,col,str(recipe.get("name",kind)),18)
	title.name="AruFirstFurnitureName_"+kind
	title.add_theme_color_override("font_color",INK)
	var note:=line(app,col,NOTES[kind],14)
	note.name="AruFirstFurnitureNote_"+kind
	note.add_theme_color_override("font_color",MUTED)
	note.custom_minimum_size.y=44

	var costs:=VBoxContainer.new()
	costs.custom_minimum_size.y=52
	costs.add_theme_constant_override("separation",2)
	col.add_child(costs)
	for item:String in recipe:
		if item=="name":continue
		var need:=int(recipe[item])
		var held:=int(inventory.get(item,0))
		var cost:=HBoxContainer.new()
		cost.name="AruFirstFurnitureCost_%s_%s"%[kind,item]
		cost.add_theme_constant_override("separation",6)
		costs.add_child(cost)
		cost.add_child(Shell.picture(Items.icon(item),24))
		var need_label:=line(app,cost,World.NAMES.get(item,item),15)
		need_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		need_label.add_theme_color_override("font_color",INK)
		var count:=line(app,cost,"%d／%d"%[held,need],15)
		count.add_theme_color_override("font_color",GOOD if held>=need else SHORT)

	var build:Button=app.button("到工坊",func():app.life_panels.build_menu(app,kind))
	build.name="AruFirstFurnitureBuild_"+kind
	build.size_flags_vertical=Control.SIZE_SHRINK_END
	col.add_child(build)
	return build

static func line(app,parent:Container,copy:String,extent:int) -> Label:
	var label:Label=app.label(copy,extent)
	if parent is VBoxContainer:label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(label)
	return label
