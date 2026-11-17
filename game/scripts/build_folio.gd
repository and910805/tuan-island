extends RefCounted
## 家園工坊 builder folio (village_art_preview only).
##
## A construction-specific layout, separate from the shared shop/seed/cook/chest
## catalog_shell: a wood-framed forest-green linen shelf of compact object slots
## on the left (BuildShelf) and a warm recipe card on the right (BuildRecipe)
## with a 3x object preview, material icons and held／required counts, and the
## place button (BuildPlace). Everything sits inside BuildFolio. The style-tab
## row (BuildStyles) also carries the BlueprintBook button, which opens the
## blueprint book through app._blueprint_menu(), leaving the tab/undo/HouseCheck
## toolbar untouched.
##
## The returned dictionary keeps the catalog contract used by the existing
## build logic and by life_ui_panels.select_entry:
##   pages / buttons / entries / selected / page / details / icon / title /
##   description / fit
## Data is read-only here: choosing a recipe only sets app.building and the
## build tool, exactly like the previous catalog.

const World = preload("res://scripts/world.gd")
const Village = preload("res://scripts/village.gd")
const LifeTheme = preload("res://scripts/life_ui_theme.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const HouseUI = preload("res://scripts/house_ui.gd")
const StyleCatalog = preload("res://scripts/build_style_catalog.gd")
const WORKSHOP_TOPICS=preload("res://scripts/workshop_layouts.gd").TOPICS

const LAYOUT := "build_folio"
const TABS := ["全部", "基礎", "家具", "生活"]
const INN_COLLECTION := ["inn_quilt_bed","inn_stone_footbath","inn_lattice_wardrobe","inn_fabric_screen",
	"inn_tea_table","spring_stone_bench","towel_rack","ceramic_eave_chime","warm_lamp_niche",
	"inn_luggage_rack","spring_pebble_path","inn_welcome_sign"]
const TAB_ICONS := ["backpack", "wood", "fiber", "stone"]
const INK := Color("354334")
const INK_SOFT := Color("5d634a")
const SHORT := Color("a4452c")
const READY := Color("3f6a3a")
const PLACEMENT_NOTES := {
	"stove":"放在田邊或住家旁的空地。靠近互動後選擇料理，做好再領取。渡口野餐需要兩份蘿蔔湯和一份麵包。",
	"floor":"從地板開始規劃小屋。選擇後可按住範圍操作鍵拖曳，成片鋪設。",
	"wall":"沿地板外圍圍起房間，記得留下門的位置；封閉房間會一併計算自動屋頂材料。",
	"door":"替小屋留一個出入口。放好後靠近互動，即可開門或關門。",
	"window":"替牆面添一扇採光窗，也能作為房間的邊界。",
	"roof":"新房間圍好後會自動加蓋；這張圖樣可用來補蓋既有地板上的屋頂。",
	"bed":"為屋內留一個休息角落。小屋檢查會確認床是否能從門口走到。",
	"path":"沿常走的路鋪上石板。選擇後可拖曳成片鋪設。",
	"spring_pebble_path":"以石材與陶土鋪出暖泉風卵石路，可拖曳成片施工。",
	"ceramic_eave_chime":"放在自己的木牆南面。互動時輕響一聲，受環境聲音量控制。",
	"shell_chime":"把望安退潮時撿到的貝殼串成風鈴。可放在小徑旁，靠近互動即可聽到聲音。",
	"acorn_ornament":"在望安西側林邊向松鼠交換的橡果掛飾，可以擺在家園。",
	"warm_lamp_niche":"裝在自己木牆南面的玻璃壁燈，發出穩定的暖光。",
	"towel_rack":"用摺好的浴巾布置旅舍。占一格地面。",
	"inn_welcome_sign":"寫下旅舍名稱和兩行歡迎語，路過的島民可以讀。",
	"inn_tea_table":"有兩個茶杯展示位，可擺放或收回暖薑茶與霧竹茶飲。",
	"inn_luggage_rack":"可手動從背包挑選兩件物品展示，只有主人可以取回。",
	"spring_stone_bench":"占兩格的旅舍長凳，可和另一位島民同坐。",
	"chest":"把常用材料收在一起。共用箱可供島上夥伴存取。",
	"private_chest":"放在自己的工作角落，收好私人用品。",
	"rope_rack":"掛起阿潮的紀念繩結。靠近互動可翻閱他的關係事件。",
	"basic_tea_set":"把茶屋的一席茶帶回家，木托盤上放著兩只杯子。",
	"wood_mailbox":"放在家門口，靠近後可翻閱自己的送信紀錄。",
	"guest_wardrobe":"放在客房，靠近後可以換上或收起已解鎖的圍裙。",
	"inn_lattice_wardrobe":"在家園免費換穿已取得的原色、藍染工作服與米露的圍裙。",
	"inn_fabric_screen":"用木框與織布隔開房間。預覽會標出兩個有碰撞的地格。",
	"inn_quilt_bed":"厚厚的羊毛被可以染色。靠近休息可補滿自己的探索體力。",
	"inn_stone_footbath":"占 3×2 格，四位島民可一起坐下泡腳。",
	"sketch_easel":"把速寫放在家園。靠近互動可開啟自己的菜園圖鑑。",
}

## Slot geometry: 32x48 thumbnails at integer scale 2 (64x96) sit entirely
## inside the slot, with a caption strip underneath.
const THUMB_ZOOM := 2
const THUMB := Vector2(32, 48) * THUMB_ZOOM
const SLOT_PAD := 6.0
const SLOT_LIFT := 2.0
const CAPTION_H := 22.0
const SLOT_MIN := Vector2(112, SLOT_PAD + 96 + 2 + CAPTION_H + 4)
## Column choice: 4 columns once a slot can be at least this wide, else 3.
const SLOT_TARGET := 120.0
const GRID_GAP := 8
const SCROLLBAR_RESERVE := 14.0
## Recipe card widths: the narrower viewport gets the wider card so the shelf
## drops to three columns and the recipe text wraps less.
const NARROW_VIEW := 1152.0
const RECIPE_BASE := 316.0
const RECIPE_WIDE := 352.0
const PREVIEW_ZOOM := 3
const WIDE_OBJECTS := ["waterworks", "mine_drill", "ore_display"]
const STAGE_W := 132.0
const DESC_MIN := 40.0
const BODY_GAP := 14
const FOLIO_GAP := 10

## Slot whose tooltip_text stays the exact recipe name (existing lookups rely on
## it) while the hover tooltip itself is a richer, styled caption.
class BuildSlot extends Button:
	var describe: Callable
	func _make_custom_tooltip(for_text: String) -> Object:
		var text := for_text
		if describe.is_valid():
			text = str(describe.call())
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", LifeTheme.badge_style())
		var label := Label.new()
		label.text = text
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", INK)
		panel.add_child(label)
		return panel

static func category(kind: String, foundations: Array, furniture: Array) -> int:
	return 1 if kind in foundations else (2 if kind in furniture else 3)

static func style_id_for_page(page: int) -> String:
	var offset:=page-TABS.size()
	var styles:=StyleCatalog.style_ids()
	return str(styles[offset]) if offset>=0 and offset<styles.size() else ""

## Same gating as before: resident stories via Village, mine depth for the two
## Jinguashi machines.
static func unlocked(app, person: Dictionary, id: String) -> bool:
	var result := Village.unlocked(person, id)
	if id==World.RESIDENT_GOALS.MASTER_BENCH:result=app.session.snapshot.get("resident_goals",{}).get("aru",{}).get("2",{}).get("state")=="done" and app.session.snapshot.get("region_id","home")==World.REGIONS.HOME
	if id=="long_bench" and app.session.snapshot.get("resident_goals",{}).get("aru",{}).get("2",{}).get("state")=="done":result=true
	if id == "expedition_tent":result = World.exploration_level(int(person.get("exploration_points",0))) >= World.EXPEDITION_TENT_LEVEL
	if id == "supply_box":result = World.supply_box_unlocked(person,app.session.snapshot.get("resident_goals",{}).get("bobo",{}).get("3",{}).get("state")=="done")
	if id in ["author_sign","author_shelf"]:result = World.crafting_level(person)>=10
	if id==World.RESIDENT_GOALS.FESTIVAL_BELL:result=app.session.snapshot.get("resident_goals",{}).get("lingpopo",{}).get("3",{}).get("state")=="done"
	if id=="basic_tea_set":result=app.session.snapshot.get("resident_goals",{}).get("chacha",{}).get("1",{}).get("state")=="done"
	if id=="wood_mailbox":result=app.session.snapshot.get("resident_goals",{}).get("luoluo",{}).get("1",{}).get("state")=="done"
	if id=="guest_wardrobe":result=app.session.snapshot.get("resident_goals",{}).get("nuannuan",{}).get("3",{}).get("state")=="done"
	if id==World.WELCOME_SIGN.KIND:result=app.session.snapshot.get("resident_goals",{}).get("nuannuan",{}).get("1",{}).get("state")=="done"
	if id==World.INDUSTRY.FOOT_BATH:result=app.session.snapshot.get("resident_goals",{}).get("nuannuan",{}).get("2",{}).get("state")=="done"
	if id=="sketch_easel":result=app.session.snapshot.get("resident_goals",{}).get("diandian",{}).get("1",{}).get("state")=="done"
	if id == "fish_display":result = World.Collections.angling_level(person) >= World.Collections.FISH_DISPLAY_LEVEL
	if id == "master_flower_bed":result = World.farming_level(person) >= World.MASTER_FARMING_LEVEL
	if id == "greenhouse_rack":result = person.get("greenhouse_reported",false)
	if id == "animal_collector":result = app.session.snapshot.get("picnic",false)
	if id == "assembly_table":result = person.get("workshop_upgraded",false)
	if id == "dye_table":result = app.session.snapshot.get("flower_nursery",{}).get("garden",{}).get("complete",false)
	if id == "jam_pot":result = World.MARKET.unlocked(app.session.snapshot)
	if id == "large_sprinkler":result = World.farming_level(person) >= World.LARGE_SPRINKLER_LEVEL
	if id == "medium_sprinkler":result = World.farming_level(person) >= World.MEDIUM_SPRINKLER_LEVEL
	if id == "seed_maker":result = World.farming_level(person) >= World.SEED_MAKER_LEVEL
	if id == "waterworks":result = int(app.session.snapshot.get("mine_depths",{}).get("unlocked",1)) >= 4
	if id == "mine_drill":result = int(app.session.snapshot.get("mine_depths",{}).get("unlocked",1)) >= 5
	if id == "glass_furnace":
		var depths = app.session.snapshot.get("mine_depths",{})
		result = depths is Dictionary and World.MINES.hoist_ready(depths)
	if id in World.KITCHEN_GATED:result = bool(app.session.snapshot.get("public_kitchen",{}).get("opened",false))
	if id in [World.INDUSTRY.GATE_KIND, World.INDUSTRY.TOWER_KIND]:result = World.LANYANG_REVISIT.tech_unlocked(app.session.snapshot)
	return result

## Exact recipe materials (every key except name), in the shelf's usual order.
static func materials(id: String, order: Array, inventory:Dictionary={}) -> Array:
	var recipe: Dictionary = World.build_recipe(id,inventory)
	var result: Array = []
	for item in order:
		if recipe.has(item):result.append(item)
	for item in recipe:
		if item != "name" and not item in result:result.append(item)
	return result

static func reduced_motion(app) -> bool:
	var sound = app.get("sound")
	return sound != null and bool(sound.get("reduced_motion"))

static func lock_text(app, id: String) -> Array:
	if id==World.RESIDENT_GOALS.MASTER_BENCH:return ["完成阿榆的長椅修繕關係事件後，可在家園放置。","阿榆的長椅圖樣"]
	if id=="long_bench":return ["完成阿榆的長椅修繕委託或關係事件後解鎖。","長椅圖樣"]
	if id == "expedition_tent":return ["探索達到十級後解鎖。", "探索十級解鎖"]
	if id == "supply_box":return ["探索六級，或完成波波的休息站事件後解鎖。", "探索六級／波波"]
	if id in ["author_sign","author_shelf"]:return ["手作達到十級後解鎖。", "手作十級解鎖"]
	if id==World.RESIDENT_GOALS.FESTIVAL_BELL:return ["完成鈴婆婆的〈最後一枚鈴〉後解鎖。","最後一枚鈴"]
	if id=="basic_tea_set":return ["回報茶茶的茶桌布置後解鎖。","完成茶茶的第一席茶"]
	if id=="wood_mailbox":return ["完成洛洛的第一封信後解鎖。","完成洛洛的送信"]
	if id=="guest_wardrobe":return ["回報暖暖的客房布置後解鎖。","完成暖暖的客房"]
	if id==World.WELCOME_SIGN.KIND:return ["在礁溪完成暖暖的〈一直沒亮的門牌〉後解鎖。","一直沒亮的門牌"]
	if id==World.INDUSTRY.FOOT_BATH:return ["在礁溪完成暖暖的〈池邊的裂縫〉後解鎖。","池邊的裂縫"]
	if id=="sketch_easel":return ["回報點點的三張速寫後解鎖。","完成點點的速寫"]
	if id == "fish_display":return ["漁獵觀察達到十級後解鎖。", "漁獵觀察十級解鎖"]
	if id == "master_flower_bed":return ["農耕達到十級後解鎖。", "農耕十級解鎖"]
	if id == "greenhouse_rack":return ["向宜蘭水圳的星禾回報跨季收成後解鎖。", "完成冬天也開花"]
	if id == "large_sprinkler":return ["農耕八級後解鎖。每天澆灌周圍二十四格，不穿牆。","農耕八級解鎖"]
	if id == "medium_sprinkler":return ["農耕六級後解鎖。每天澆灌周圍八格，不穿牆。", "農耕六級解鎖"]
	if id == "seed_maker":return ["農耕三級後解鎖。銅錠可用小熔爐熔製，木工零件可在工作臺製作。", "農耕三級解鎖"]
	if id == "waterworks":return ["完成金瓜石第三層抽水工程後解鎖。", "先完成抽水工程"]
	if id == "mine_drill":return ["完成金瓜石第四層工程、開通第五層後解鎖。", "先開通第五層"]
	if id == "glass_furnace":return ["修好金瓜石升降台後解鎖。鐵礦可用小熔爐熔成鐵錠。", "完成卡住的升降台"]
	if id == "animal_collector":return ["渡口野餐後可放置。在裝配桌製作組件，再準備一個收集籃。","完成渡口野餐"]
	if id == "assembly_table":return ["手作六級後可在工作台升級工坊，再建造裝配桌。","先升級工坊"]
	if id == "dye_table":return ["完成田尾公共花園後，可在家園用花材提染。","完成田尾公共花園"]
	if id == "jam_pot":return ["渡口野餐後開放。陶土可在鶯歌取得，銅錠可在小熔爐熔製。", "完成渡口野餐"]
	if id == World.INDUSTRY.GATE_KIND:return [World.INDUSTRY.GATE_LOCKED, "完成旱日分流"]
	if id == World.INDUSTRY.TOWER_KIND:return [World.INDUSTRY.TOWER_LOCKED, "完成旱日分流"]
	if id in World.KITCHEN_GATED:return ["公共廚房開張後解鎖：先登記公共廚房，再和大家備齊蘿蔔湯 4、麵包 2、菜園沙拉 2。", "公共廚房開張後解鎖"]
	var resident_name: String = {"planter": "米露", "ore_display": "波波"}.get(id, "阿榆")
	return ["完成%s的故事後解鎖（%s）" % [resident_name, app.binding_label("journal")], "圖樣尚未解鎖"]

static func slot_theme(theme: Theme) -> void:
	theme.set_type_variation("BuildSlot", "Button")
	# Resting objects sit directly on the linen shelf. Only interaction states
	# get a textured frame, so repeated cards do not dominate the scene.
	var normal := StyleBoxEmpty.new()
	var hover := PixelTheme.texture_style("hover", 3, 0)
	var chosen := LifeTheme.badge_style()
	var focus := PixelTheme.texture_style("focus", 3, 0)
	theme.set_stylebox("normal", "BuildSlot", normal)
	theme.set_stylebox("disabled", "BuildSlot", normal)
	theme.set_stylebox("hover", "BuildSlot", hover)
	theme.set_stylebox("pressed", "BuildSlot", chosen)
	theme.set_stylebox("hover_pressed", "BuildSlot", chosen)
	theme.set_stylebox("focus", "BuildSlot", focus)

static func open(panels, app, data: Dictionary) -> Dictionary:
	var notes: Dictionary = data.get("notes", {})
	var foundations: Array = data.get("foundations", [])
	var furniture: Array = data.get("furniture", [])
	var order: Array = data.get("materials", [])
	var content: VBoxContainer = panels.begin(app, "家園工坊")
	var modal: Control = app.modal
	modal.set_meta("catalog", true)
	modal.set_meta("life_modal_layout", LAYOUT)
	modal.theme = PixelTheme.make(modal.theme if modal.theme else app.theme())
	slot_theme(modal.theme)
	modal.add_theme_stylebox_override("panel", PixelTheme.frame_style())
	modal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var outer := content.get_parent() as ScrollContainer
	var shell := content.get_parent().get_parent()
	if outer != null and shell is VBoxContainer:
		shell.add_theme_constant_override("separation",6)
		for child in shell.get_children():
			if child is Label:
				child.autowrap_mode = TextServer.AUTOWRAP_OFF
			elif child is HBoxContainer:
				for heading in child.get_children():
					if heading is Label:heading.autowrap_mode = TextServer.AUTOWRAP_OFF

	var folio := VBoxContainer.new()
	folio.name = "BuildFolio"
	folio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folio.add_theme_constant_override("separation", FOLIO_GAP)
	content.add_child(folio)

	# --- toolbar: four tabs, then undo status/entry and HouseCheck ------------
	var bar := HBoxContainer.new()
	bar.name = "BuildFolioBar"
	bar.add_theme_constant_override("separation", 8)
	folio.add_child(bar)
	var style_bar := HBoxContainer.new()
	style_bar.name = "BuildStyles"
	folio.add_child(style_bar)

	# --- body: shelf (left) + recipe card (right) ------------------------------
	var body := HBoxContainer.new()
	body.name = "BuildFolioBody"
	body.add_theme_constant_override("separation", BODY_GAP)
	folio.add_child(body)

	var shelf := PanelContainer.new()
	shelf.name = "BuildShelf"
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.add_theme_stylebox_override("panel", LifeTheme.toolbar_style())
	body.add_child(shelf)
	var linen := PanelContainer.new()
	linen.name = "BuildShelfLinen"
	var linen_style := PixelTheme.texture_style("button_pressed", 3, 8)
	linen_style.modulate_color = Color(0.88, 0.92, 0.86)
	linen.add_theme_stylebox_override("panel", linen_style)
	shelf.add_child(linen)
	var scroll := ScrollContainer.new()
	scroll.name = "BuildShelfScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	linen.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)

	var recipe_card := PanelContainer.new()
	recipe_card.name = "BuildRecipe"
	recipe_card.custom_minimum_size.x = RECIPE_BASE
	recipe_card.add_theme_stylebox_override("panel", LifeTheme.panel_style())
	body.add_child(recipe_card)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	recipe_card.add_child(details)
	# Kept for the catalog contract; the folio shows the 3x object stage instead.
	var icon: TextureRect = panels.item_picture(null, 32)
	icon.hide()
	details.add_child(icon)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	details.add_child(head)
	var stage := PanelContainer.new()
	stage.name = "BuildPreview"
	stage.clip_contents = true
	stage.custom_minimum_size.x = STAGE_W
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_theme_stylebox_override("panel", linen_style)
	head.add_child(stage)
	var large: Control = panels.build_picture(stage, "floor", PREVIEW_ZOOM)
	large.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sprite: Node2D = large.get_child(0)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	head.add_child(info)
	var title: Label = app.label("", 21)
	title.name = "BuildTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(title)
	var status: Label = app.label("", 14)
	status.name = "BuildStatus"
	# Wraps to a second line on the narrower recipe card instead of ending in "…".
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.max_lines_visible = 2
	info.add_child(status)
	var material_list := VBoxContainer.new()
	material_list.name = "BuildMaterials"
	material_list.add_theme_constant_override("separation", 4)
	info.add_child(material_list)
	var most := 1
	for kind in World.BUILD:
		most = maxi(most, materials(kind, order).size())
	var rows: Array = []
	for index in most:
		var row := HBoxContainer.new()
		row.name = "BuildMaterial%d" % index
		row.add_theme_constant_override("separation", 6)
		material_list.add_child(row)
		var picture: TextureRect = panels.item_picture(null, 32)
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(picture)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 0)
		row.add_child(words)
		var item_name: Label = app.label("", 13)
		item_name.add_theme_color_override("font_color", INK_SOFT)
		words.add_child(item_name)
		var count: Label = app.label("", 16)
		count.autowrap_mode = TextServer.AUTOWRAP_OFF
		words.add_child(count)
		rows.append([row, picture, item_name, count])
	var desc_scroll := ScrollContainer.new()
	desc_scroll.name = "BuildNotes"
	desc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	desc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_scroll.custom_minimum_size.y = DESC_MIN
	details.add_child(desc_scroll)
	var description: Label = app.label("", 15)
	description.name = "BuildDescription"
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_scroll.add_child(description)

	var catalog := {"pages": [], "buttons": [], "entries": [], "selected": "", "page": 0,
		"details": details, "icon": icon, "title": title, "description": description,
		"caption_selected": INK, "caption_normal": Color("f4e6bf"), "build_scroll":scroll,
		"reveal_slot":reveal_shelf_slot.bind(scroll)}

	var place: Button = app.button("", func():
		app.building = catalog.selected
		app.building_style = style_id_for_page(int(catalog.page))
		app._select_tool("build")
		app._close_modal()
	)
	place.name = "BuildPlace"
	place.tooltip_text = "手把 Y 跳到選擇配方，A 確定"
	var place_actions:=HBoxContainer.new()
	details.add_child(place_actions)
	place.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	place_actions.add_child(place)
	var diagram:Button=app.button("圖解",func():app._workshop_guide(int(WORKSHOP_TOPICS.get(catalog.selected,0))))
	diagram.name="BuildWorkshopGuide"
	diagram.tooltip_text="查看這類設備的接線、用料與操作步驟"
	place_actions.add_child(diagram)

	# --- tabs -----------------------------------------------------------------
	var style_ids := StyleCatalog.style_ids()
	var labels := TABS.duplicate()
	for style_id: String in style_ids:labels.append(StyleCatalog.style(style_id).name)
	var inn_page:=labels.size()
	labels.append("暖泉旅舍")
	for index in labels.size():
		var page := GridContainer.new()
		page.name = "BuildPage%d" % index
		page.columns = 4
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("h_separation", GRID_GAP)
		page.add_theme_constant_override("v_separation", GRID_GAP)
		page.visible = index == 0
		stack.add_child(page)
		catalog.pages.append(page)
		catalog.entries.append({})
		var tab: Button = app.button(labels[index], func():
			var options: Dictionary = catalog.entries[index]
			var id: String = catalog.selected if options.has(catalog.selected) else options.keys()[0]
			panels.select_entry(app, catalog, index, id)
			scroll.set_deferred("scroll_vertical", 0)
		)
		tab.name = "BuildTab%d" % index
		tab.toggle_mode = true
		if index<TABS.size():tab.icon = ItemArt.icon(TAB_ICONS[index])
		tab.add_theme_constant_override("icon_max_width", 24)
		tab.custom_minimum_size.x = 84
		var tab_row := bar if index<TABS.size() else style_bar
		tab_row.add_child(tab)
		catalog.buttons.append(tab)
	var tab_spacer := Control.new()
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(tab_spacer)
	# The spacious style row shares the undo status and the blueprint book.
	style_bar.add_theme_constant_override("separation", 8)
	var book: Button = app.button("藍圖冊", func(): app._blueprint_menu())
	book.name = "BlueprintBook"
	book.icon = ItemArt.icon("stone")
	book.add_theme_constant_override("icon_max_width", 24)
	book.custom_minimum_size = Vector2(132, 40)
	book.tooltip_text = "框選整組建築存成藍圖，再放到地圖上報價、確認施工"
	style_bar.add_child(book)

	# --- fit: body height follows the modal; recipe width follows the viewport --
	var fit := func():
		if not is_instance_valid(body) or not is_instance_valid(outer):return
		var view: Vector2 = folio.get_viewport_rect().size if folio.is_inside_tree() else Vector2(1280, 800)
		var wide := RECIPE_WIDE if view.x < NARROW_VIEW or app.font_scale_factor() >= 1.2 else RECIPE_BASE
		if absf(recipe_card.custom_minimum_size.x - wide) > 0.5:recipe_card.custom_minimum_size.x = wide
		var floor_height := recipe_card.get_combined_minimum_size().y
		var available := maxf(floor_height, floorf(outer.size.y - body.position.y - 2.0))
		if absf(body.custom_minimum_size.y - available) > 1.0:
			body.custom_minimum_size.y = available
	catalog["fit"] = fit
	if outer != null:
		outer.resized.connect(fit)
		bar.resized.connect(func():fit.call_deferred())
		style_bar.resized.connect(func():fit.call_deferred())
	var viewport:Viewport = app.get_viewport()
	if viewport != null:
		viewport.size_changed.connect(fit)
		folio.tree_exiting.connect(func():
			if is_instance_valid(viewport) and viewport.size_changed.is_connected(fit):
				viewport.size_changed.disconnect(fit)
		)
	fit.call_deferred()

	var columns := func():
		if not is_instance_valid(scroll):return
		var width := scroll.size.x - SCROLLBAR_RESERVE
		var count := clampi(int(floorf((width + GRID_GAP) / (SLOT_TARGET + GRID_GAP))), 3, 4)
		for page in catalog.pages:
			if page.columns != count:page.columns = count
	scroll.resized.connect(columns)

	# Undo entry + status in the same toolbar as HouseCheck; its confirmation
	# strip slides in between the toolbar and the folio body.
	app.undo_ui.attach(app, bar, folio, bar.get_index() + 1, func(_shown: bool):
		fit.call_deferred()
	)
	var undo_status:Label=app.undo_ui.status
	undo_status.reparent(style_bar)
	style_bar.move_child(undo_status,book.get_index())
	undo_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	undo_status.text_overrun_behavior=TextServer.OVERRUN_NO_TRIMMING
	undo_status.clip_text=false
	var house_check: Button = app.button(HouseUI.TITLE, func(): HouseUI.open(app))
	house_check.name = "HouseCheck"
	house_check.icon = ItemArt.icon("wood")
	house_check.add_theme_constant_override("icon_max_width", 24)
	house_check.tooltip_text = "檢查身邊小屋的地板、牆、門、床與屋頂（不建造、不扣材料）"
	bar.add_child(house_check)

	# --- shelf slots ------------------------------------------------------------
	var person_of := func() -> Dictionary:
		return app.session.snapshot.get("players", {}).get(app.session.own_id, {})
	var cost_line := func(id: String, person: Dictionary) -> String:
		var bag: Dictionary = person.get("inventory", {})
		var parts := PackedStringArray()
		var recipe:=World.build_recipe(id,bag)
		for item in materials(id, order, bag):
			parts.append("%s %d／%d" % [World.NAMES.get(item, item), int(bag.get(item, 0)), int(recipe[item])])
		return " · ".join(parts)
	var slots: Array = []
	for kind in World.BUILD:
		var pages := [0, category(kind, foundations, furniture)]
		for index in style_ids.size():
			if kind in StyleCatalog.kinds(style_ids[index]):pages.append(TABS.size()+index)
		if kind in INN_COLLECTION:pages.append(inn_page)
		for page in pages:
			var entry := BuildSlot.new()
			entry.name = "BuildSlot_%s_%d" % [kind, page]
			entry.theme_type_variation = &"BuildSlot"
			entry.custom_minimum_size = SLOT_MIN
			entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			entry.toggle_mode = true
			entry.clip_contents = true
			entry.tooltip_text = World.BUILD[kind].name
			entry.set("accessibility_name", World.BUILD[kind].name)
			entry.describe = func() -> String:
				var person: Dictionary = person_of.call()
				var lines := PackedStringArray([World.BUILD[kind].name, "持有／所需  " + cost_line.call(kind, person)])
				if not unlocked(app, person, kind):lines.append(lock_text(app, kind)[1])
				return "\n".join(lines)
			var slot_page: int = page
			entry.pressed.connect(func(): panels.select_entry(app, catalog, slot_page, kind))
			catalog.pages[page].add_child(entry)
			catalog.entries[page][kind] = entry
			# Caption stays child 0 (select_entry recolours it).
			var caption := Label.new()
			caption.text = World.BUILD[kind].name
			caption.add_theme_font_size_override("font_size", 15)
			caption.add_theme_color_override("font_color", Color("f4e6bf"))
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
			entry.add_child(caption)
			caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			caption.offset_left = 4
			caption.offset_right = -4
			caption.offset_bottom = -4
			var caption_height:=func():
				var line:=caption.get_theme_font("font").get_height(caption.get_theme_font_size("font_size"))
				var width:=maxf(SLOT_MIN.x,entry.size.x)-8.0
				var needed:=caption.get_theme_font("font").get_string_size(caption.text,HORIZONTAL_ALIGNMENT_LEFT,-1,caption.get_theme_font_size("font_size")).x
				var height:=ceilf(line)*(1.0 if needed<=width else ceilf(needed/width))+4.0
				caption.offset_top=-(height+4.0)
				entry.custom_minimum_size.y=SLOT_MIN.y+maxf(0.0,height-CAPTION_H)
			caption.theme_changed.connect(caption_height)
			entry.resized.connect(caption_height)
			caption_height.call()
			var frame: Control = panels.build_picture(entry, kind, THUMB_ZOOM)
			frame.set_anchors_preset(Control.PRESET_CENTER_TOP)
			frame.offset_left = -THUMB.x / 2
			frame.offset_right = THUMB.x / 2
			frame.offset_top = SLOT_PAD
			frame.offset_bottom = SLOT_PAD + THUMB.y
			if kind in WIDE_OBJECTS:
				# These sprites really occupy 48 pixels across, not a 32px tile.
				frame.custom_minimum_size.x = 96
				frame.offset_left = -48
				frame.offset_right = 48
				frame.get_child(0).position = Vector2(16, -16 if kind=="mine_drill" else 0)
			slots.append([entry, frame, kind])
			_hover_lift(app, entry, frame)
	for index in INN_COLLECTION.size():
		var entry:Control=catalog.entries[inn_page][INN_COLLECTION[index]]
		catalog.pages[inn_page].move_child(entry,index)

	# --- live refresh -----------------------------------------------------------
	panels.updates.append(func(person: Dictionary):
		var id: String = catalog.selected
		if id.is_empty() or not World.BUILD.has(id):return
		diagram.visible=WORKSHOP_TOPICS.has(id)
		var open_plan := unlocked(app, person, id)
		var bag: Dictionary = person.get("inventory", {})
		var recipe:=World.build_recipe(id,bag)
		var enough := true
		if sprite.kind != id:
			sprite.kind = id
			sprite.queue_redraw()
		# Keep a whole-number scale and the entire 48px machine within the stage.
		sprite.scale = Vector2.ONE * (2 if id in WIDE_OBJECTS else PREVIEW_ZOOM)
		sprite.position = Vector2(16, 8 if id=="mine_drill" else 24) if id in WIDE_OBJECTS else Vector2.ZERO
		catalog.title.text = recipe.name
		var needed := materials(id, order, bag)
		for index in rows.size():
			var row: Array = rows[index]
			row[0].visible = index < needed.size()
			if index >= needed.size():continue
			var item: String = needed[index]
			var need: int = recipe[item]
			var held: int = bag.get(item, 0)
			row[1].texture = ItemArt.icon(item)
			row[2].text = World.NAMES.get(item, item)
			row[3].text = "%d／%d" % [held, need]
			row[3].add_theme_color_override("font_color", READY if held >= need else SHORT)
			row[0].tooltip_text = "%s  持有 %d／所需 %d" % [World.NAMES.get(item, item), held, need]
			enough = enough and held >= need
		place.disabled = not open_plan
		if open_plan:
			# T066 居民紀念小物：說明取自 RESIDENT_GOALS.KEEPSAKES 的 blurb。
			if World.RESIDENT_GOALS.is_keepsake_kind(id):catalog.description.text = "和%s一起做的事的紀念。%s不擋路，拆除會收回背包。" % [World.RESIDENT_BOND.name_of(str(World.RESIDENT_GOALS.KEEPSAKES[id].resident)), str(World.RESIDENT_GOALS.KEEPSAKES[id].blurb)]
			else:catalog.description.text = notes.get(id, PLACEMENT_NOTES.get(id,"選好位置，替島上的生活添一件喜歡的物件。放置前可先查看地面的施工預覽。"))
			if id=="sprinkler":
				catalog.description.text = "工作台套件款每 %d 秒檢查相鄰四格自家作物。可手動補水，或接水管從自己的桶取水。"%World.SPRINKLER_INTERVAL if recipe.has("sprinkler_kit") else "每天澆一次相鄰四格，不穿牆。可手動補水或接水管。"
			place.text = "選擇配方" if enough else "材料不足，仍可選擇"
			status.text = "材料齊全" if enough else "材料不足"
			status.add_theme_color_override("font_color", READY if enough else SHORT)
		else:
			var lock := lock_text(app, id)
			catalog.description.text = lock[0]
			place.text = lock[1]
			status.text = "圖樣未解鎖"
			status.add_theme_color_override("font_color", INK_SOFT)
		var style_id:=style_id_for_page(int(catalog.page))
		if not style_id.is_empty():
			var style := StyleCatalog.preview_spec(style_id+"."+id)
			catalog.description.text += "\n%s · %s（搭配建議）" % [style.style_name,style.note]
		for slot in slots:
			var slot_kind: String = slot[2]
			var gated := not unlocked(app, person, slot_kind)
			slot[1].modulate = Color(0.66, 0.68, 0.64) if gated else Color.WHITE
			slot[0].set("accessibility_description", ("尚未解鎖 · " if gated else "") + cost_line.call(slot_kind, person))
	)
	panels.select_entry(app, catalog, 0, "floor")
	app._layout_preview.call_deferred()
	return catalog

static func reveal_shelf_slot(entry:Control,scroll:ScrollContainer)->void:
	if not is_instance_valid(entry) or not is_instance_valid(scroll):return
	var view:=scroll.get_global_rect()
	if view.encloses(entry.get_global_rect()):return
	var page:=entry.get_parent() as GridContainer
	if page==null:
		scroll.ensure_control_visible(entry)
		return
	var first:=entry.get_index()-entry.get_index()%page.columns
	var top:Control=page.get_child(first)
	# Align the first visible row rather than leaving only its captions visible.
	scroll.scroll_vertical+=roundi(top.get_global_rect().position.y-view.position.y)

## Small hover/focus cue: the thumbnail rises two whole pixels inside its slot.
## Reduced motion keeps the art still (hover/selected/focus styles still differ).
static func _hover_lift(app, entry: Button, frame: Control) -> void:
	var move := func(up: bool):
		if not is_instance_valid(frame):return
		var target := SLOT_PAD - (SLOT_LIFT if up and not reduced_motion(app) else 0.0)
		var previous: Tween = entry.get_meta("lift_tween") if entry.has_meta("lift_tween") else null
		if previous != null and previous.is_valid():previous.kill()
		var place := func(value: float):
			if not is_instance_valid(frame):return
			var top := roundf(value)
			frame.offset_top = top
			frame.offset_bottom = top + THUMB.y
		if reduced_motion(app) or not entry.is_inside_tree():
			place.call(target)
			return
		var tween := entry.create_tween()
		tween.tween_method(place, frame.offset_top, target, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		entry.set_meta("lift_tween", tween)
	var settle := func():
		if is_instance_valid(entry) and entry.is_inside_tree():
			move.call(entry.is_hovered() or entry.has_focus())
	entry.mouse_entered.connect(func(): move.call(true))
	entry.focus_entered.connect(func(): move.call(true))
	entry.mouse_exited.connect(func(): settle.call_deferred())
	entry.focus_exited.connect(func(): settle.call_deferred())
