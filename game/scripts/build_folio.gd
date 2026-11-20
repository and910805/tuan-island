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
const WorkshopLayouts=preload("res://scripts/workshop_layouts.gd")
const WORKSHOP_TOPICS=WorkshopLayouts.TOPICS

const LAYOUT := "build_folio"
const TABS := ["全部", "基礎", "家具", "生活"]
const LOG_CABIN_COLLECTION := [
	World.INDUSTRY.CEDAR_BED, World.INDUSTRY.ROUNDED_TABLE, World.INDUSTRY.WOOD_CHAIR,
	World.RESIDENT_GOALS.MASTER_BENCH, World.RESIDENT_GOALS.COTTON_SOFA, World.WALL_FIXTURES.TOOL_BOARD,
	World.INDUSTRY.GRID_BOOKCASE, World.RESIDENT_GOALS.FOREST_WARDROBE, "lamp",
	World.INDUSTRY.BRAIDED_RUG, World.INDUSTRY.TABLE_VASE, World.WALL_FIXTURES.HOME_SIGN,
]
const TABLETOP_RECIPES := [World.INDUSTRY.TABLE_VASE, World.INDUSTRY.TEA_SET] + World.INDUSTRY.SHELL_BOTTLES
const TEA_COLLECTION := [World.INDUSTRY.BAMBOO_TEA_TABLE,World.RESIDENT_GOALS.BAMBOO_BENCH,World.INDUSTRY.INDIGO_CUSHION,World.WALL_FIXTURES.BAMBOO_CURTAIN,World.INDUSTRY.PAPER_TEA_LAMP,World.INDUSTRY.TEA_DISPLAY_CABINET,World.INDUSTRY.TEA_SET,World.INDUSTRY.RIVERSIDE_SCREEN,World.WALL_FIXTURES.WATER_LISTENING_CHIME,World.INDUSTRY.BAMBOO_LOUNGER,World.INDUSTRY.TEA_SNACK_SHELF,World.INDUSTRY.IMPERFECT_TEA_PAVILION]
const COAST_COLLECTION := [World.INDUSTRY.COAST_CART,World.INDUSTRY.COAST_REGISTER,World.INDUSTRY.COAST_AWNING,World.INDUSTRY.COAST_FISH_COUNTER,World.INDUSTRY.BEACH_CHAIR,World.INDUSTRY.SHELL_TABLE,World.RESIDENT_GOALS.COAST_WARDROBE,World.WALL_FIXTURES.LIFEBUOY,World.POSTCARDS.RACK]+World.INDUSTRY.SHELL_BOTTLES+[World.OAR_SIGN.KIND,"rope_rack"]
const INN_COLLECTION := ["inn_quilt_bed","inn_stone_footbath","inn_lattice_wardrobe","inn_fabric_screen",
	"inn_tea_table","spring_stone_bench","towel_rack","ceramic_eave_chime","warm_lamp_niche",
	"inn_luggage_rack","spring_pebble_path","inn_welcome_sign"]
const FOREST_COLLECTION := [World.INDUSTRY.HOLLOW_BED,World.INDUSTRY.MUSHROOM_TABLE,World.INDUSTRY.MUSHROOM_STOOL,World.INDUSTRY.LEAF_MAT,World.INDUSTRY.SPORE_LAMP,World.INDUSTRY.ACORN_CABINET,World.INDUSTRY.HEDGEHOG_BASKET,World.WALL_FIXTURES.BARK_FRAME,World.INDUSTRY.FOREST_ARCH,World.INDUSTRY.LEAF_DESK,World.INDUSTRY.MUSHROOM_POST,World.INDUSTRY.QUIET_BIRDHOUSE]
const GREENHOUSE_COLLECTION := [World.GREENHOUSE_GLASS.XINGHE_ROOF,World.ROOF_FIXTURES.HANGING_POT,World.NURSERY_BOX.KIND,World.INDUSTRY.POT_RACK,World.INDUSTRY.VINE_ARCH,World.INDUSTRY.GLASS_FLOWER_TABLE,World.RESIDENT_GOALS.GARDEN_CHAIR,World.INDUSTRY.SEED_CABINET,World.INDUSTRY.AQUARIUM,World.STAR_GARDEN_LAMP,"garden_basin",World.INDUSTRY.OBSERVATION_DESK,"greenhouse_rack","greenhouse_roof"]
const TAB_ICONS := ["backpack", "wood", "fiber", "stone"]
const INK := Color("354334")
const INK_SOFT := Color("5d634a")
const SHORT := Color("a4452c")
const READY := Color("3f6a3a")
const PLACEMENT_NOTES := {
	World.RESIDENT_GOALS.FESTIVAL_BELL:"把鐘放在家園空地，走近按互動鍵就能敲響。靜音時也能看到鐘旁的亮光。",
	World.INDUSTRY.COAST_AWNING:"占三格寬、兩格深。可從布棚下走過，在海邊留一片陰影。",
	World.INDUSTRY.QUIET_BIRDHOUSE:"白天會有小鳥停在屋旁。開啟「減少裝飾動態」後，小鳥會安靜停著。",
	World.INDUSTRY.MUSHROOM_POST:"收取寄給你的島上信件。每封信附的包裹只能領一次。",
	World.INDUSTRY.LEAF_DESK:"在書桌前寫一份私人草稿，或直接翻開島民手冊。草稿會跟著你，從別張落葉書桌也能繼續寫。",
	World.INDUSTRY.FOREST_ARCH:"占三格，兩側是木柱，中間是永遠敞開的通道。可用藍圖旋轉方向。",
	World.WALL_FIXTURES.BARK_FRAME:"掛在自家木牆的南面，可展示點點的速寫或已拍好的島上照片。",
	World.INDUSTRY.HEDGEHOG_BASKET:"放在刺蝟食盤旁六格內。觀察過來訪的蘑菇刺蝟後，牠會到最近的籃子打盹。",
	World.INDUSTRY.ACORN_CABINET:"可收納 16 種物品。預設只有櫃主能存取，櫃主可以開放同島共用。",
	World.INDUSTRY.PAPER_TEA_LAMP:"占一格，可走過。黃昏後亮起穩定的暖光，不閃動。靠近自己的茶燈按互動鍵即可開關。",
	World.INDUSTRY.SPORE_LAMP:"木底玻璃罩裡養著兩朵星夜菇。入夜後會在腳邊亮起柔和的青綠光。",
	World.INDUSTRY.LEAF_MAT:"鋪在 2×2 的空地上，可以走過。站在地墊上按互動鍵即可免費換色。",
	World.INDUSTRY.BRAIDED_RUG:"放在 2×2 的空地、木地板或石地板上。可以走過，搬移或收起地墊都會保留底下的地板。",
	World.INDUSTRY.INDIGO_CUSHION:"一格地面坐墊。靠近即可坐下，其他玩家能走過這一格；再互動或走動能起身。",
	World.INDUSTRY.MUSHROOM_STOOL:"一格的矮座。靠近即可坐下，再互動或走動能起身。",
	World.INDUSTRY.MUSHROOM_TABLE:"占 2×2 格。有四個共餐座位，屋主可擺四份料理，坐下的人可以享用。",
	World.INDUSTRY.BAMBOO_TEA_TABLE:"占兩格。四邊都能入座，桌主最多可擺四份茶點，坐下後即可享用。",
	World.INDUSTRY.TEA_DISPLAY_CABINET:"占兩格，有三個展示位。每位放一份茶，同種茶可擺多份。櫃主能取回茶葉，訪客可參觀。",
	World.INDUSTRY.RIVERSIDE_SCREEN:"占兩格，展開時會擋路。屋主可折起屏風，讓兩格都能通行。展開前需等玩家離開占地範圍。",
	World.INDUSTRY.BAMBOO_LOUNGER:"占一格寬、兩格長，可用藍圖旋轉成橫放。屋主和訪客都能躺下休息，一次一人；只是休息姿勢，不恢復體力、不跳時間。走動或再互動就能起身，只有屋主能搬移或拆除。",
	World.INDUSTRY.TEA_SNACK_SHELF:"占一格，有上下兩層，各自存放真正的料理（最多三種、每種 99 份），只收可以吃的點心。預設只有主人能存取，主人可開放同島共用；搬移會保留點心，要先取空才能拆除。藍圖不會複製點心。",
	World.INDUSTRY.IMPERFECT_TEA_PAVILION:"占 3×3 格的開放式遮棚，四邊與棚下都能走過，不擋路。走到棚邊按互動鍵，可重讀茶茶那場沒有流程的茶會。不能蓋住步道、出入口和互動位置，拆除會退回全部建材。",
	World.INDUSTRY.HOLLOW_BED:"占 2×2 格。可躺下恢復體力，也能在午夜後使用休息到清晨的功能。",
	World.INDUSTRY.COAST_CART:"占 2×2 格。渡口野餐後，可為自家攤位上架、開張和領取營收。等午夜結算後就能搬動。",
	World.INDUSTRY.COAST_REGISTER:"占兩格。渡口野餐後，靠近收銀櫃便能上架、開張與領取自己攤位的營收。放在風鈴渡口的家園。",
	World.INDUSTRY.SHELL_TABLE:"占一格。桌面有一個展示位，兩側各有一個座位。",
	World.INDUSTRY.BEACH_CHAIR:"占一格寬、兩格深。可以坐下休息，收起時前方可通行。等座位空了再搬移或收起。",
	"stove":"放在田邊或住家旁的空地。靠近互動後選擇料理，做好再領取。渡口野餐需要兩份蘿蔔湯和一份麵包。",
	World.INDUSTRY.KITCHEN_STOVE:"占 2×2 格，從任一側都能使用。可當自家的灶台，也能捐給渡口的公共廚房。靠近互動後從十六道基礎料理中選擇，做好再領取；舊的小石灶與它的料理排程都不受影響。",
	"floor":"從地板開始規劃小屋。選擇後可按住範圍操作鍵拖曳，成片鋪設。",
	"stone_floor":"一格平整石面，可拖曳成片鋪設。適合戶外庭院，也可搭配門、牆和屋頂圍出室內。",
	"wall":"沿地板外圍圍起房間，記得留下門的位置；封閉房間會一併計算自動屋頂材料。",
	"door":"替小屋留一個出入口。放好後靠近互動，即可開門或關門。",
	"window":"替木牆添一扇透光的窗，也能和木門一起圍出房間。",
	"bench":"木桌可直接建造。木工台占兩格，兩端都可製作木工配方，也能從相鄰的箱子取料。",
	World.INDUSTRY.STONE_WORKBENCH:"占兩格，可從任一端使用，可用藍圖旋轉。完成公告板修復即可建造，不需要礦洞金屬。台邊可做河灣橋的橋基，石地板、小熔爐與石材家具也從這裡接到施工。",
	"roof":"新房間圍好後會自動加蓋；這張圖樣可用來補蓋既有地板上的屋頂。",
	World.TERRACOTTA_ROOF.KIND:"用陶窯燒的紅陶屋瓦鋪成，每格一片，可拖曳成片鋪設。能直接改鋪在草編屋頂上，原本的木材與纖維會退還。",
	"bed":"為屋內留一個休息角落。小屋檢查會確認床是否能從門口走到。",
	"lamp":"黃昏後亮起穩定的暖光。靠近自己的落地燈按互動鍵，每盞可獨立開關。",
	World.INDUSTRY.WOOD_CHAIR:"一人座。靠近後可坐下，也能坐著發出島民招呼。移動或再次互動可起身。",
	World.RESIDENT_GOALS.COTTON_SOFA:"兩格寬的棉布沙發，左右各有一個座位。屋主和訪客都能坐，等大家起身後再搬移。",
	World.RESIDENT_GOALS.BAMBOO_BENCH:"兩格寬的竹長椅，左右各有一個座位，互不影響。屋主和訪客都能坐，等大家起身後再搬移。",
	World.INDUSTRY.ROUNDED_TABLE:"兩格寬的圓角木桌，桌面有兩個擺放位置。屋主能擺小物或上菜，來訪的居民也能享用料理。",
	World.INDUSTRY.GRID_BOOKCASE:"占前後兩格。靠近即可重讀自己完成的故事、居民回憶和地方記憶。",
	World.INDUSTRY.CEDAR_BED:"家園的兩格木床。床主可設成個人休息處，在床邊恢復探索體力。",
	World.RESIDENT_GOALS.FOREST_WARDROBE:"家園的一格衣櫃。免費更換已取得的工作服配色，來訪的島民也可使用。",
	"path":"沿常走的路鋪上石板。選擇後可拖曳成片鋪設。",
	"spring_pebble_path":"以石材與陶土鋪出暖泉風卵石路，可拖曳成片施工。",
	"garden_basin":"星砂溫室的陶盆與卵石底座，占一格。適合窗邊或花徑轉角。",
	World.STAR_GARDEN_LAMP:"占一格，可走過。黃昏後在腳邊亮起一小圈淡黃光，適合沿花徑布置。",
	World.RESIDENT_GOALS.GARDEN_CHAIR:"庭園裡的單人座位，占一格。靠近即可坐下，再互動或走動就能起身。",
	World.INDUSTRY.SEED_CABINET:"占兩格，可展示三種已登錄的種子標本。收成後會登錄到菜園圖鑑，展示不消耗背包物品。",
	World.INDUSTRY.AQUARIUM:"占兩格，可放一尾紅尾小鯉。牠會在水裡游動，隨時可以取回。",
	World.INDUSTRY.GLASS_FLOWER_TABLE:"透過淡綠色桌面能看見下方的地板。桌腳占兩格，布置時記得留一條走道。",
	World.INDUSTRY.VINE_ARCH:"兩側柱子占地，中央可通行。靠近可挑選三種花色。",
	World.INDUSTRY.POT_RACK:"占兩格。用三個位置展示陶花盆或已採收的花，隨時可整盆取回。",
	World.ROOF_FIXTURES.HANGING_POT:"掛在自己的屋頂下，一格一盆。可以從下方走過，拆屋頂前先移下花盆。",
	World.NURSERY_BOX.KIND:"兩格寬的四格育苗床。每格分開播種、澆水和採收；放進封閉溫室可跨季栽種。",
	World.INDUSTRY.COAST_FISH_COUNTER:"占兩格，最多展示三種漁獲。可隨時取回；展示期間不會消耗，也無須補冰。",
	World.GREENHOUSE_GLASS.XINGHE_ROOF:"用牆、窗和關好的門圍起農田，再用玻璃鋪滿室內。圍好後作物可跨季生長，仍需澆水。",
	World.INDUSTRY.OBSERVATION_DESK:"占兩格。走到桌邊就能翻閱自己的作物圖鑑和種植紀錄。",
	"ceramic_eave_chime":"放在自己的木牆南面。互動時輕響一聲，受環境聲音量控制。",
	"shell_chime":"把望安退潮時撿到的貝殼串成風鈴。可放在小徑旁，靠近互動即可聽到聲音。",
	"acorn_ornament":"在望安西側林邊向松鼠交換的橡果掛飾，可以擺在家園。",
	"warm_lamp_niche":"裝在自己木牆南面的玻璃壁燈，發出穩定的暖光。",
	World.WALL_FIXTURES.LIFEBUOY:"掛在自己木牆的南面。海邊小屋的牆面裝飾，玩家可以從前方走過。",
	"towel_rack":"用摺好的浴巾布置旅舍。占一格地面。",
	"inn_welcome_sign":"寫下旅舍名稱和兩行歡迎語，路過的島民可以讀。",
	World.WALL_FIXTURES.HOME_SIGN:"掛在自己的木牆南面。可刻 12 字家名與兩行歡迎語，訪客也看得到建造者署名。",
	World.WALL_FIXTURES.TOOL_BOARD:"掛在相連的兩段自家木牆上。可挑選兩個工具外觀，背包裡的工具與材料照常使用。",
	World.WALL_FIXTURES.BAMBOO_CURTAIN:"掛在自己窗戶的南面，窗戶仍保留。人在屋內、屋頂淡化時，竹簾也會跟著更透明。竹簾還掛著時，不能拆窗。",
	World.WALL_FIXTURES.WATER_LISTENING_CHIME:"掛在自己木牆的南面。靠近就能敲一下，鈴聲隨環境聲音量調整。",
	"inn_tea_table":"有兩個茶杯展示位，可擺放或收回暖薑茶與霧竹茶飲。",
	"inn_luggage_rack":"可手動從背包挑選兩件物品展示，只有主人可以取回。",
	"spring_stone_bench":"占兩格的旅舍長凳，可和另一位島民同坐。",
	"chest":"把常用材料收在一起。共用木箱有 16 格，每種物品占一格，可供島上夥伴存取。",
	"private_chest":"放在自己的工作角落，收好私人用品。私人木箱有 16 格，每種物品占一格。",
	"rope_rack":"掛起阿潮的紀念繩結。靠近互動可翻閱他的關係事件。",
	"basic_tea_set":"把茶屋的一席茶帶回家，木托盤上放著兩只杯子。",
	"wood_mailbox":"放在家門口，靠近後可翻閱自己的送信紀錄。",
	World.POSTCARDS.RACK:"可擺三張旅行明信片。到過的地方會留下明信片，收起展示時仍保留旅行收藏。",
	World.OAR_SIGN.KIND:"在周邊地圖選一處陸地，木牌會指向那裡。路標是方向提示，所有島民都能查看。",
	"guest_wardrobe":"放在客房，靠近後可以換上或收起已解鎖的圍裙。",
	"inn_lattice_wardrobe":"在家園免費換穿已取得的原色、藍染工作服與米露的圍裙。",
	World.RESIDENT_GOALS.COAST_WARDROBE:"設在家園的單格更衣棚。靠近就能換上已取得的工作服或圍裙，來訪的島民也可使用。",
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
	# T12: the person's own persisted stage-3 record (works for older saves); the snapshot summary agrees.
	if id==World.INDUSTRY.IMPERFECT_TEA_PAVILION:result=World.PAVILION.unlocked(person) or app.session.snapshot.get("resident_goals",{}).get("chacha",{}).get("3",{}).get("state")=="done"
	if id=="wood_mailbox":result=app.session.snapshot.get("resident_goals",{}).get("luoluo",{}).get("1",{}).get("state")=="done"
	if id==World.POSTCARDS.RACK:result=app.session.snapshot.get("resident_goals",{}).get("luoluo",{}).get("2",{}).get("state")=="done"
	if id=="guest_wardrobe":result=app.session.snapshot.get("resident_goals",{}).get("nuannuan",{}).get("3",{}).get("state")=="done"
	if id==World.WELCOME_SIGN.KIND:result=app.session.snapshot.get("resident_goals",{}).get("nuannuan",{}).get("1",{}).get("state")=="done"
	if id==World.INDUSTRY.FOOT_BATH:result=app.session.snapshot.get("resident_goals",{}).get("nuannuan",{}).get("2",{}).get("state")=="done"
	if id=="sketch_easel":result=app.session.snapshot.get("resident_goals",{}).get("diandian",{}).get("1",{}).get("state")=="done"
	if id==World.WALL_FIXTURES.BARK_FRAME:result=app.session.snapshot.get("resident_goals",{}).get("diandian",{}).get("2",{}).get("state")=="done"
	if id in [World.GREENHOUSE_GLASS.XINGHE_ROOF,World.NURSERY_BOX.KIND]:result=app.session.snapshot.get("resident_goals",{}).get("xinghe",{}).get("3",{}).get("state")=="done"
	if id == "fish_display":result = World.Collections.angling_level(person) >= World.Collections.FISH_DISPLAY_LEVEL
	if id == "master_flower_bed":result = World.farming_level(person) >= World.MASTER_FARMING_LEVEL
	if id == "greenhouse_rack":result = World.RESIDENT_GOALS.flower_rack_unlocked(person)
	if id == "animal_collector":result = app.session.snapshot.get("picnic",false)
	if id == "assembly_table":result = person.get("workshop_upgraded",false)
	# C11: the station needs the Q03 board flag; new stone floors / small smelters need the station
	# (the server re-checks both; this only mirrors it for the shelf).
	if id == World.INDUSTRY.STONE_WORKBENCH:result = app.session.snapshot.get("board",false)==true
	if id in World.STONE_WORKSHOP.STATION_BUILDS:result = result and stone_station_ready(app)
	if id == "dye_table":result = app.session.snapshot.get("flower_nursery",{}).get("garden",{}).get("complete",false)
	if id == "jam_pot":result = World.MARKET.unlocked(app.session.snapshot)
	if id==World.INDUSTRY.COAST_CART:result=World.MARKET.unlocked(app.session.snapshot) and app.session.snapshot.get("region_id","home")==World.REGIONS.HOME
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

## C11: the server includes the home station's availability even in away-region snapshots.
static func stone_station_ready(app) -> bool:
	var snapshot:Dictionary = app.session.snapshot
	if snapshot.has("stone_workshop_ready"):return snapshot.stone_workshop_ready==true
	return World.STONE_WORKSHOP.has_station(snapshot.get("objects",{}))

## Exact recipe materials (every key except name), in the shelf's usual order.
static func materials(id: String, order: Array, inventory:Dictionary={}) -> Array:
	var recipe:=recipe_cost(id,inventory)
	var result: Array = []
	for item in order:
		if recipe.has(item):result.append(item)
	for item in recipe:
		if item != "name" and not item in result:result.append(item)
	return result

static func recipe_cost(id:String,inventory:Dictionary) -> Dictionary:
	return World.CRAFT[id].ingredients if id in TABLETOP_RECIPES else World.build_recipe(id,inventory)

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
	if id==World.INDUSTRY.IMPERFECT_TEA_PAVILION:return World.PAVILION.lock_text()
	if id=="wood_mailbox":return ["完成洛洛的第一封信後解鎖。","完成洛洛的送信"]
	if id==World.POSTCARDS.RACK:return [World.POSTCARDS.UNLOCK_MESSAGE,"沒有地址的信"]
	if id=="guest_wardrobe":return ["回報暖暖的客房布置後解鎖。","完成暖暖的客房"]
	if id==World.WELCOME_SIGN.KIND:return ["在礁溪完成暖暖的〈一直沒亮的門牌〉後解鎖。","一直沒亮的門牌"]
	if id==World.INDUSTRY.FOOT_BATH:return ["在礁溪完成暖暖的〈池邊的裂縫〉後解鎖。","池邊的裂縫"]
	if id=="sketch_easel":return ["回報點點的三張速寫後解鎖。","完成點點的速寫"]
	if id==World.WALL_FIXTURES.BARK_FRAME:return [World.RESIDENT_GOALS.BARK_FRAME_LOCK,"完成點點的手勢速寫"]
	if id in [World.GREENHOUSE_GLASS.XINGHE_ROOF,World.NURSERY_BOX.KIND]:return [World.NURSERY_BOX.UNLOCK_MESSAGE,"不必把冬天趕走"]
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
	if id == World.INDUSTRY.STONE_WORKBENCH:return [World.STONE_WORKSHOP.LOCKED_MSG,"完成公告板修復"]
	if id in World.STONE_WORKSHOP.STATION_BUILDS:return [World.STONE_WORKSHOP.STATION_MSG,"先建造石工台"]
	if id==World.INDUSTRY.COAST_CART:return ["完成渡口野餐後，可在風鈴渡口的家園放置。","完成渡口野餐"]
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
	var tabletop_art:TextureRect=panels.item_picture(null,96)
	tabletop_art.name="BuildTabletopPreview"
	tabletop_art.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	tabletop_art.custom_minimum_size.y=large.custom_minimum_size.y
	tabletop_art.hide()
	stage.add_child(tabletop_art)
	# Area the art may use: the stage's content box at its guaranteed height.
	var stage_room := Vector2(STAGE_W - linen_style.get_minimum_size().x, large.custom_minimum_size.y)
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
	var mill_direction := HBoxContainer.new()
	mill_direction.name = "BuildMillDirection"
	mill_direction.add_child(app.label("入口", 15))
	var mill_picker := OptionButton.new()
	mill_picker.name = "BuildMillFacing"
	mill_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for direction in ["朝南", "朝西", "朝北", "朝東"]:
		mill_picker.add_item(direction)
	mill_picker.item_selected.connect(func(_index: int): panels.refresh(app))
	mill_direction.add_child(mill_picker)
	details.add_child(mill_direction)
	mill_direction.hide()
	var occupy_tile := CheckButton.new()
	occupy_tile.name="BuildOccupyTile"
	occupy_tile.text="整格施工"
	occupy_tile.tooltip_text="沿用整格牆面，擺放既有牆飾或延伸原本的房屋。"
	var guide:Dictionary=data.get("guide",{})
	occupy_tile.button_pressed=int(guide.get("topic",-1))==WorkshopLayouts.FIRST_HOUSE
	occupy_tile.toggled.connect(func(_on:bool):panels.refresh(app))
	occupy_tile.hide()
	details.add_child(occupy_tile)

	var place: Button = app.button("", func():
		if catalog.selected in TABLETOP_RECIPES:return
		app.building = catalog.selected
		app.mill_build_facing = -1 if catalog.selected == World.INDUSTRY.MILL and mill_picker.selected == 4 else mill_picker.selected
		var style_id:=style_id_for_page(int(catalog.page))
		app.building_style = style_id if not StyleCatalog.entry(style_id+"."+catalog.selected).is_empty() else ""
		app.building_on_edge = occupy_tile.visible and not occupy_tile.button_pressed and app.building_style.is_empty()
		app.edge_controller_side = 0
		app._select_tool("build")
		app._close_modal()
	)
	place.name = "BuildPlace"
	place.tooltip_text = "手把 Y 跳到選擇配方，A 確定"
	var place_actions:=HBoxContainer.new()
	details.add_child(place_actions)
	place.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	place_actions.add_child(place)
	var diagram:Button=app.button("圖解",func():
		if not guide.is_empty() and catalog.selected==data.get("guide_piece",""):
			app._workshop_guide(int(guide.topic),guide)
		else:
			app._workshop_guide(int(WORKSHOP_TOPICS.get(catalog.selected,0)))
	)
	diagram.name="BuildWorkshopGuide"
	diagram.tooltip_text="查看這件物品的施工、用料與操作步驟"
	place_actions.add_child(diagram)
	if not guide.is_empty() and app.controller_navigation:
		(func():
			if not is_instance_valid(diagram) or not diagram.is_visible_in_tree():return
			diagram.grab_focus()
			var modal_scroll:=diagram.find_parent("ModalScroll") as ScrollContainer
			if modal_scroll!=null:modal_scroll.ensure_control_visible(diagram)
		).call_deferred()
	details.move_child(desc_scroll,details.get_child_count()-1)

	# --- tabs -----------------------------------------------------------------
	var style_ids := StyleCatalog.style_ids()
	var labels := TABS.duplicate()
	for style_id: String in style_ids:labels.append(StyleCatalog.style(style_id).name)
	var tea_page:=TABS.size()+style_ids.find("tea_house")
	var coast_page:=TABS.size()+style_ids.find("coast")
	var inn_page:=labels.size()
	labels.append("暖泉旅舍")
	var greenhouse_page:=labels.size()
	labels.append("星砂溫室")
	var forest_page:=labels.size()
	labels.append("蘑菇森林")
	var log_cabin_page:=labels.size()
	labels.append("原木小屋")
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
		var recipe:=recipe_cost(id,bag)
		for item in materials(id, order, bag):
			parts.append("%s %d／%d" % [World.NAMES.get(item, item), int(bag.get(item, 0)), int(recipe[item])])
		return " · ".join(parts)
	var slots: Array = []
	for kind in World.BUILD.keys()+TABLETOP_RECIPES:
		var tabletop:bool=kind in TABLETOP_RECIPES
		var pages:Array=[]
		if not tabletop:
			pages=[0,category(kind,foundations,furniture)]
			for index in style_ids.size():
				if kind in StyleCatalog.kinds(style_ids[index]):pages.append(TABS.size()+index)
		if kind in TEA_COLLECTION and tea_page not in pages:pages.append(tea_page)
		if kind in COAST_COLLECTION:pages.append(coast_page)
		if kind in INN_COLLECTION:pages.append(inn_page)
		if kind in GREENHOUSE_COLLECTION:pages.append(greenhouse_page)
		if kind in FOREST_COLLECTION:pages.append(forest_page)
		if kind in LOG_CABIN_COLLECTION:pages.append(log_cabin_page)
		var name:String=World.NAMES[kind] if tabletop else World.BUILD[kind].name
		for page in pages:
			var entry := BuildSlot.new()
			entry.name = "BuildSlot_%s_%d" % [kind, page]
			if tabletop:entry.set_meta("tabletop_recipe",kind)
			entry.theme_type_variation = &"BuildSlot"
			entry.custom_minimum_size = SLOT_MIN
			entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			entry.toggle_mode = true
			entry.clip_contents = true
			entry.tooltip_text = name
			entry.set("accessibility_name", name)
			entry.describe = func() -> String:
				var person: Dictionary = person_of.call()
				var lines := PackedStringArray([name, "持有／所需  " + cost_line.call(kind, person)])
				if tabletop:lines.append("木工台製作")
				elif not unlocked(app, person, kind):lines.append(lock_text(app, kind)[1])
				return "\n".join(lines)
			var slot_page: int = page
			entry.pressed.connect(func(): panels.select_entry(app, catalog, slot_page, kind))
			catalog.pages[page].add_child(entry)
			catalog.entries[page][kind] = entry
			# Caption stays child 0 (select_entry recolours it).
			var caption := Label.new()
			caption.text = name
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
			var frame:Control
			if tabletop:
				frame=panels.item_picture(ItemArt.icon(kind),64)
				frame.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
				entry.add_child(frame)
			else:
				frame=panels.build_picture(entry,kind,THUMB_ZOOM)
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
	for index in TEA_COLLECTION.size():
		var entry:Control=catalog.entries[tea_page][TEA_COLLECTION[index]]
		catalog.pages[tea_page].move_child(entry,index)
	for index in COAST_COLLECTION.size():
		var entry:Control=catalog.entries[coast_page][COAST_COLLECTION[index]]
		catalog.pages[coast_page].move_child(entry,index)
	for index in INN_COLLECTION.size():
		var entry:Control=catalog.entries[inn_page][INN_COLLECTION[index]]
		catalog.pages[inn_page].move_child(entry,index)
	for index in GREENHOUSE_COLLECTION.size():
		var entry:Control=catalog.entries[greenhouse_page][GREENHOUSE_COLLECTION[index]]
		catalog.pages[greenhouse_page].move_child(entry,index)

	for index in FOREST_COLLECTION.size():
		var entry:Control=catalog.entries[forest_page][FOREST_COLLECTION[index]]
		catalog.pages[forest_page].move_child(entry,index)
	for index in LOG_CABIN_COLLECTION.size():
		var entry:Control=catalog.entries[log_cabin_page][LOG_CABIN_COLLECTION[index]]
		catalog.pages[log_cabin_page].move_child(entry,index)

	# --- live refresh -----------------------------------------------------------
	panels.updates.append(func(person: Dictionary):
		var id: String = catalog.selected
		var tabletop:=id in TABLETOP_RECIPES
		if not tabletop and not World.BUILD.has(id):return
		diagram.visible=WORKSHOP_TOPICS.has(id)
		diagram.text="回圖解" if not guide.is_empty() and id==data.get("guide_piece","") else "圖解"
		var open_plan := tabletop or unlocked(app, person, id)
		var bag: Dictionary = person.get("inventory", {})
		var is_mill := id == World.INDUSTRY.MILL
		occupy_tile.visible = id in ["wall","door","window"] and style_id_for_page(int(catalog.page)).is_empty() and bool(app.session.snapshot.get("edge_construction",false))
		var legacy_mill := int(bag.get("mill_kit", 0)) > 0
		mill_direction.visible = is_mill and open_plan
		if legacy_mill and mill_picker.item_count==4:
			mill_picker.add_item("使用舊單格磨坊組件")
		elif not legacy_mill and mill_picker.item_count==5:
			if mill_picker.selected==4:mill_picker.select(0)
			mill_picker.remove_item(4)
		var uses_legacy_kit := is_mill and mill_picker.selected == 4
		var recipe: Dictionary = World.LEGACY_MILL_COST if uses_legacy_kit else recipe_cost(id,bag)
		var enough := true
		var preview_facing := -1 if uses_legacy_kit else mill_picker.selected
		large.visible=not tabletop
		tabletop_art.visible=tabletop
		if tabletop:
			tabletop_art.texture=ItemArt.icon(id)
		elif sprite.kind != id or (is_mill and sprite.mill_preview_facing != preview_facing):
			sprite.kind = id
			sprite.mill_preview_facing = preview_facing
			sprite.queue_redraw()
		# Whole-number scale with the complete art inside the stage: oversized art
		# (48px machines, the two-seat bench, tall furniture) is refitted and centred.
		# Both helpers are static on the thumbnail script, reached through the stage's own sprite.
		if not tabletop:
			var artwork_fit: Dictionary = sprite.stage_fit(sprite.art_bounds(id), large.custom_minimum_size, stage_room, PREVIEW_ZOOM)
			sprite.scale = Vector2.ONE * int(artwork_fit.zoom)
			sprite.position = artwork_fit.position
		catalog.title.text = World.NAMES[id].replace("・","\n") if tabletop else recipe.name
		var needed: Array = ["mill_kit"] if uses_legacy_kit else materials(id, order, bag)
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
		place.visible=not tabletop
		place.disabled = tabletop or not open_plan
		if tabletop:
			status.text="木工台製作"
			status.add_theme_color_override("font_color",INK_SOFT)
			if id==World.INDUSTRY.TEA_SET:
				catalog.description.text="做好後，擺在自己的木桌、圓角木桌或低腳竹茶桌上。"
			elif id==World.INDUSTRY.TABLE_VASE:
				catalog.description.text="做好後，靠近自己的木桌、圓角木桌或貝殼圓桌擺上。花材可以換回背包。"
			else:
				catalog.description.text="做好後，靠近自己的木桌或貝殼圓桌擺上。"
		elif open_plan:
			# T066 居民紀念小物：說明取自 RESIDENT_GOALS.KEEPSAKES 的 blurb。
			if World.RESIDENT_GOALS.is_keepsake_kind(id):catalog.description.text = "和%s一起做的事的紀念。%s不擋路，拆除會收回背包。" % [World.RESIDENT_BOND.name_of(str(World.RESIDENT_GOALS.KEEPSAKES[id].resident)), str(World.RESIDENT_GOALS.KEEPSAKES[id].blurb)]
			else:catalog.description.text = notes.get(id, PLACEMENT_NOTES.get(id,"選好位置，替島上的生活添一件喜歡的物件。放置前可先查看地面的施工預覽。"))
			if occupy_tile.visible:
				catalog.description.text += "\n以整格施工，牆、窗或門占一格。" if occupy_tile.button_pressed else "\n沿格線放置，保留房間內可走的地板。"
			if is_mill:
				catalog.description.text = "放下手上原有的單格磨坊組件。" if uses_legacy_kit else "占地 3×3。從入口進出，可磨麵粉或加工飼料，也能連接輸送帶。"
			if id=="sprinkler":
				catalog.description.text = "每天澆一次上下左右的自家作物，牆與關閉的門會擋水。可手動補水或接水管。"
			place.text = "選擇配方" if enough else "材料不足，仍可選擇"
			status.text = "材料齊全" if enough else "材料不足"
			status.add_theme_color_override("font_color", READY if enough else SHORT)
		else:
			var lock := lock_text(app, id)
			catalog.description.text = lock[0]
			place.text = lock[1]
			status.text = "圖樣未解鎖"
			status.add_theme_color_override("font_color", INK_SOFT)
		if id==World.INDUSTRY.COAST_CART:
			var goals:Dictionary=app.session.snapshot.get("resident_goals",{}).get("xiaoli",{})
			var site:Dictionary=World.RESIDENT_GOALS.XIAOLI_CART_SITES.get(goals.get("2",{}).get("choice",""),{})
			if not site.is_empty():catalog.description.text+="\n選址手記：%s。自己的攤車可放在符合施工條件的家園空地。"%site.name
		if open_plan and id==World.INDUSTRY.ROUNDED_TABLE and int(catalog.page)==log_cabin_page:
			catalog.description.text="占兩格，可擺兩樣小物或料理。\n桌邊花瓶可在木工台製作，完成後靠近自家的桌子擺上。"
		var style_id:=style_id_for_page(int(catalog.page))
		if not StyleCatalog.entry(style_id+"."+id).is_empty():
			var style := StyleCatalog.preview_spec(style_id+"."+id)
			catalog.description.text += "\n%s · %s（搭配建議）" % [style.style_name,style.note]
		for slot in slots:
			var slot_kind: String = slot[2]
			var gated := slot_kind not in TABLETOP_RECIPES and not unlocked(app, person, slot_kind)
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
