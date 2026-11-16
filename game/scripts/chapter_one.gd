extends RefCounted

const STARTER_CELL := Vector2i(38,29)
const STARTER_COST := {"wood":12,"stone":8,"fiber":4}
const STARTER_ITEMS := {"sprinkler_kit":1,"pipe_kit":2,"tank_kit":1}

const MAX_TRACKED := 1000000000
const STEPS := {
	"grow": {"npc": "xiaoli", "cell": Vector2i(43, 29), "line": "先種一批吧。自己採下來的菜，我才知道下次向誰訂。", "action": "種下作物並親手採收"},
	"ship": {"npc": "xiaoli", "cell": Vector2i(43, 29), "line": "留一些給米露，剩下的我收。下一批種子就用今天的收入買。", "action": "在出貨箱售出已有採收紀錄的同類作物"},
	"works": {"npc": "aru", "cell": Vector2i(40, 29), "line": "貨有了，先把橋和公告板修起來，大家才知道去哪裡交貨。", "action": "到公告板完成公共工程"},
	"water": {"npc": "aru", "cell": Vector2i(38, 29), "line": "下一批田不能總等人有空。讓灑水器真的澆到一格乾田，我們再開飯。", "action": "讓灑水器用管網供水澆濕一格乾田"},
	"meal": {"npc": "milu", "cell": Vector2i(40, 29), "line": "有兩份蘿蔔湯和一份麵包，我就能替大家留個位子。", "action": "把料理送到公告板完成渡口野餐"},
	"complete": {"npc": "xiaoli", "cell": Vector2i(43, 29), "line": "給北部工坊的朋友：渡口有新夥伴了。這一籃菜讓大家又坐在一起。下回，我想借你們的陶罐，帶湯去找你。", "action": "讀小栗的介紹信"},
}
const DETAILS := {
	"grow":"用鋤頭開墾，播種並澆水，成熟後用採收籃。先種三株蘿蔔、一株小麥（一株收兩份）。留兩份蘿蔔、兩份小麥做野餐，也留一包種子測試灑水器。",
	"ship":"到渡口出貨箱寄出一份自己採收過的作物。小栗攤位的直接出售不算出貨。留兩份蘿蔔、兩份小麥做野餐；賣完了可用剩餘種子補種，或到小栗攤位買種子。",
	"works":"用斧頭採木、十字鎬採石，再到公告板捐入木材30和石材10。捐款可分次，朋友也能一起準備。",
	"water":"帶木材12、石材8、纖維4找阿榆換設備，或沿用既有管網。把自己的儲水桶、水管和灑水器沿上下左右接起來，再在灑水器上下左右任一格自己的乾田播種。補滿儲水桶，啟用灑水器後等它澆水。直接補給灑水器的水不算；若已補滿，拆除重放後再接管。",
	"meal":"建一座小石灶（木材12、石材15）。用蘿蔔2煮出湯2，小麥2烤出麵包1；料理完成後領取，再交到公告板。舊世界已辦過的野餐會保留。",
	"complete":"找小栗收下茶陶介紹信。從渡口搭交通船，經頭城轉乘到瑞芳，在鐵路門選經臺北轉乘至貓空，再到鶯歌合作陶坊製罐。先試寄一罐茶，讓空罐回來，往後就能帶湯去拜訪朋友。M 可查看旅圖與免費回程。",
}
const PLACES := {"grow":"小栗種子攤東北邊的田", "ship":"渡口出貨箱", "works":"村中央公告板", "water":"阿榆與你的農田", "meal":"小石灶與公告板", "complete":"小栗的種子攤"}

## 望安開場：小栗在種子攤 (43,29) 東北邊留給新島民的一小塊田（3×2）。
## 只是指引，不是保留地：沒有預先開墾、沒有額外種子、誰都可以在這裡建造或種田。
## 六格在新世界都是草地：(45,26..27) 在村中心無樹石區 (35..45,27..37) 或其北側
## 且雜湊不出樹石，(46..47,26..27) 在渡口東北的空地 (46..51,22..29) 內。
## 不在保護區 (38..44,28..31)、出貨箱候選、市集攤位候選、公告板、阿榆起始格 (38,29)、
## 風鈴樹 (41,28)、風鈴節訪客 (43..44,28)、鈴婆婆／洛洛／阿潮／棉棉站位、
## 渡口轉乘點 (47,30) 與到站點 (46,30)、出生點 (39,33)、糯米雞 (45,34) 上。
const STARTER_PLOT: Array[Vector2i] = [Vector2i(45,26),Vector2i(46,26),Vector2i(47,26),Vector2i(45,27),Vector2i(46,27),Vector2i(47,27)]
const FIRST_CROP_STEPS: Array[String] = ["find","till","sow","water","wait","harvest","ship"]
## 距離田地最近一格中心超過這個距離時，第一步是「去找小栗與田地」。
const FIND_REACH := 3.5
const NO_PLOT_CELL := Vector2i(-1,-1)

static func fresh() -> Dictionary:
	return {"shipped": false, "watered": false, "harvests": {}, "starter_claims": {}}

static func record_harvest(state: Dictionary, owner: String, item: String, quantity: int) -> void:
	var chapter: Dictionary = state.chapter_one
	if chapter.shipped:
		return
	var harvests: Dictionary = chapter.harvests
	if not harvests.has(owner):
		harvests[owner] = {}
	var amounts: Dictionary = harvests[owner]
	amounts[item] = mini(MAX_TRACKED, int(amounts.get(item, 0)) + quantity)

static func record_shipment(state: Dictionary, owner: String, quantities: Dictionary) -> void:
	var chapter: Dictionary = state.chapter_one
	var harvests: Dictionary = chapter.harvests.get(owner, {})
	for item in quantities:
		if int(harvests.get(item, 0)) > 0:
			chapter.shipped = true
			chapter.harvests.clear()
			return

static func record_irrigation(state: Dictionary) -> void:
	if state.chapter_one.shipped and state.board:
		state.chapter_one.watered = true

static func phase(state: Dictionary) -> String:
	var chapter: Dictionary = state.get("chapter_one", fresh())
	if not chapter.shipped:
		return "grow" if chapter.harvests.is_empty() else "ship"
	if not state.board:
		return "works"
	if not chapter.watered:
		return "water"
	return "complete" if state.picnic else "meal"

static func next_step(state: Dictionary) -> Dictionary:
	var id := phase(state)
	var result: Dictionary = STEPS[id].duplicate()
	result.id = id
	result.detail = DETAILS[id]
	result.place = PLACES[id]
	if id == "ship":
		var shipping:Vector2i=preload("res://scripts/shipping.gd").cell_for(state)
		if shipping!=Vector2i(-1,-1):result.cell=shipping
	return result

## 望安開場的第一株作物指引：{id, text, cell}，id 依序為
## find → till → sow → water → wait → harvest → ship；不在這段開場時回傳 {}。
## 只讀既有狀態（本人的作物、背包、位置、第一章紀錄與出貨箱位置），伺服器 state
## （owner = token）與用戶端快照（owner = own_id 公開 id）都適用；別人的作物不會
## 推進我的步驟。純讀取，不修改傳入的字典。
static func first_crop_step(state: Dictionary, owner: String) -> Dictionary:
	var chapter = state.get("chapter_one")
	if not chapter is Dictionary or chapter.get("shipped", true) != false:
		return {}
	if str(state.get("region_id", "home")) != "home":
		return {}
	var people = state.get("players")
	if not people is Dictionary or not people.get(owner) is Dictionary:
		return {}
	var person: Dictionary = people[owner]
	if str(person.get("region", "home")) != "home":
		return {}
	var bag = person.get("inventory", {})
	if not bag is Dictionary:
		bag = {}
	var records = chapter.get("harvests", {})
	var mine = records.get(owner, {}) if records is Dictionary else {}
	if mine is Dictionary and not mine.is_empty():
		var carried := ""
		for item in ["radish"] + mine.keys():
			if int(mine.get(item, 0)) > 0 and int(bag.get(item, 0)) > 0:
				carried = str(item)
				break
		if not carried.is_empty():
			var bin: Vector2i = preload("res://scripts/shipping.gd").cell_for(state)
			var text := "把蘿蔔帶到出貨箱" if carried == "radish" else "把收成帶到出貨箱"
			if bin == NO_PLOT_CELL:
				text = "出貨箱被擋住了，先清出位置"
			return {"id": "ship", "text": text, "cell": bin}
	var crops = state.get("crops", {})
	if not crops is Dictionary:
		crops = {}
	var catalog: Dictionary = preload("res://scripts/crop_catalog.gd").CROPS
	var ready: Array[Vector2i] = []
	var dry: Array[Vector2i] = []
	var growing: Array[Vector2i] = []
	var soil: Array[Vector2i] = []
	for tile in crops:
		var plot = crops[tile]
		if not plot is Dictionary or str(plot.get("owner", "")) != owner:
			continue
		var parts := str(tile).split(",")
		if parts.size() != 2:
			continue
		var at := Vector2i(int(parts[0]), int(parts[1]))
		var kind := str(plot.get("kind", ""))
		if kind.is_empty():
			soil.append(at)
		elif catalog.has(kind) and float(plot.get("growth", 0.0)) >= float(catalog[kind].time):
			ready.append(at)
		elif plot.get("wet", false) == true:
			growing.append(at)
		else:
			dry.append(at)
	if not ready.is_empty():
		return {"id": "harvest", "text": "作物熟了，用採收籃收成", "cell": _closest_to_plot(ready)}
	if not dry.is_empty():
		return {"id": "water", "text": "替剛種下的作物澆水", "cell": _closest_to_plot(dry)}
	if not growing.is_empty():
		return {"id": "wait", "text": "作物正在長大，等它成熟", "cell": _closest_to_plot(growing)}
	if not soil.is_empty():
		var seeds := 0
		for kind in catalog:
			seeds += maxi(0, int(bag.get(str(kind) + "_seed", 0)))
		var sow_text := "在翻好的土播下蘿蔔種子" if int(bag.get("radish_seed", 0)) > 0 else ("在翻好的土播種" if seeds > 0 else "種子用完了，到小栗攤位買種子")
		return {"id": "sow", "text": sow_text, "cell": _closest_to_plot(soil)}
	var free := starter_plot_free(state)
	if free.is_empty():
		return {"id": "till", "text": "小栗留的田被占用了\n到附近任一塊空草地翻土", "cell": NO_PLOT_CELL}
	var position := Vector2(float(person.get("x", 0.0)), float(person.get("y", 0.0)))
	var nearest: Vector2i = free[0]
	for cell in free:
		if position.distance_to(Vector2(cell) + Vector2(0.5, 0.5)) < position.distance_to(Vector2(nearest) + Vector2(0.5, 0.5)):
			nearest = cell
	if position.distance_to(Vector2(nearest) + Vector2(0.5, 0.5)) > FIND_REACH:
		return {"id": "find", "text": "去找小栗：種子攤東北邊的田", "cell": nearest}
	return {"id": "till", "text": "用鋤頭在小栗留的田翻一格土", "cell": nearest}

## Plot cells that are still plain grass in this snapshot (no crop, object, floor,
## roof or planted tree). Read-only; works on server state and client snapshots.
static func starter_plot_free(state: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in STARTER_PLOT:
		var tile := "%d,%d" % [cell.x, cell.y]
		var taken := false
		for field in ["crops", "objects", "ground", "roofs", "forest"]:
			var layer = state.get(field, {})
			if layer is Dictionary and layer.has(tile):
				taken = true
				break
		if not taken:
			result.append(cell)
	return result

static func _closest_to_plot(cells: Array[Vector2i]) -> Vector2i:
	var center := Vector2(46.5, 27.0)
	var best: Vector2i = cells[0]
	for cell in cells:
		var a := Vector2(cell) + Vector2(0.5, 0.5)
		var b := Vector2(best) + Vector2(0.5, 0.5)
		if a.distance_to(center) < b.distance_to(center) or (is_equal_approx(a.distance_to(center), b.distance_to(center)) and (cell.y < best.y or (cell.y == best.y and cell.x < best.x))):
			best = cell
	return best

static func valid(data: Variant, players: Dictionary, crops: Dictionary, board: bool) -> bool:
	if not data is Dictionary or data.size() != 4 or not data.get("shipped") is bool or not data.get("watered") is bool:
		return false
	if not data.get("harvests") is Dictionary or (data.watered and (not data.shipped or not board)) or (data.shipped and not data.harvests.is_empty()):
		return false
	if not data.get("starter_claims") is Dictionary or (not data.starter_claims.is_empty() and (not data.shipped or not board)):
		return false
	for owner in data.starter_claims:
		if not players.has(owner) or data.starter_claims[owner] != true or not data.starter_claims[owner] is bool:
			return false
	for owner in data.harvests:
		var entries = data.harvests[owner]
		if not players.has(owner) or not entries is Dictionary or entries.is_empty() or entries.size() > crops.size():
			return false
		for item in entries:
			var count = entries[item]
			if not crops.has(item) or not (count is int or count is float) or not is_finite(count) or count < 1 or count > MAX_TRACKED or floor(count) != count:
				return false
	return true
