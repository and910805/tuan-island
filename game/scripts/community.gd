extends RefCounted

const NO_CELL := Vector2i(-1, -1)
const CANDIDATES := [Vector2i(39,30), Vector2i(39,31), Vector2i(40,31)]
const LAYERS := ["objects", "ground", "roofs", "crops", "forest"]
const HOTPOT_PORTIONS := 4
## T067 保溫底座（table_warmer.gd）：保溫上桌一輪六份，meal 另記 "total":6。
const WARM_HOTPOT_PORTIONS := 6
const HOTPOT := "trout_hotpot"
## chowder＝玉米濃湯（規劃書第 14 章的團隊分享餐）：與西瓜盤相同的規則，一輪四份。
const DISHES := {"hotpot":HOTPOT,"watermelon":"watermelon_platter","chowder":"corn_chowder"}
const ACTIONS := ["serve_hotpot","claim_hotpot","serve_watermelon","claim_watermelon","serve_chowder","claim_chowder"]

static func table_cell(state: Dictionary) -> Vector2i:
	var key: String = state.get("community", {}).get("table", "")
	for cell: Vector2i in CANDIDATES:
		if key == cell_key(cell):
			return cell
	return NO_CELL

static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func occupied(state: Dictionary, cell: Vector2i) -> bool:
	for layer in LAYERS:
		if state.get(layer, {}).has(cell_key(cell)):
			return true
	return false

static func choose_table(state: Dictionary, active: Variant = null) -> String:
	for cell: Vector2i in CANDIDATES:
		if occupied(state, cell):
			continue
		var standing := false
		var players:Dictionary=state.get("players",{})
		for token in players:
			if active!=null and not active.has(token):continue
			var player:Dictionary=players[token]
			if player.get("region","home")!="home":continue
			var delta := (Vector2(player.x, player.y) - (Vector2(cell) + Vector2(0.5,0.5))).abs()
			if delta.x < 0.72 and delta.y < 0.67:
				standing = true
				break
		if not standing:
			return cell_key(cell)
	return ""

static func valid(state: Dictionary) -> bool:
	var data = state.get("community")
	if not data is Dictionary or not data.get("table") is String:
		return false
	for key in data:
		if key=="table":continue
		if not DISHES.has(key):return false
		var meal=data[key]
		if data.table.is_empty() or not meal is Dictionary:return false
		# T067: only a warm hotpot round records "total":6. That the warmer is
		# installed is checked once at top level by table_warmer.valid (region
		# projections replace community but shallow-copy the other root fields).
		var total=HOTPOT_PORTIONS
		if meal.has("total"):
			if key!="hotpot" or meal.size()!=3:return false
			total=meal.total
			if not (total is int or total is float) or total!=WARM_HOTPOT_PORTIONS:return false
		elif meal.size()!=2:return false
		var portions=meal.get("portions")
		var claimed=meal.get("claimed")
		if not (portions is int or portions is float) or not claimed is Dictionary:return false
		if portions!=total-claimed.size() or portions<0:return false
		for who in claimed:
			if not state.players.has(who) or claimed[who]!=true:return false
	if data.table.is_empty():
		return true
	var cell := table_cell(state)
	return state.picnic and cell != NO_CELL and not occupied(state, cell)

static func share_dish(state:Dictionary,token:String,action:String,dish:String,title:String)->Dictionary:
	var community:Dictionary=state.community
	var meal:Dictionary=community.get(dish,{})
	var item:String=DISHES[dish]
	var inventory:Dictionary=state.players[token].inventory
	var count:=int(inventory.get(item,0))
	if action.begins_with("serve_"):
		if int(meal.get("portions",0))>0:return {"ok":false,"message":"餐桌上還有"+title+"，先留給晚點回來的島民。"}
		if count<HOTPOT_PORTIONS:return {"ok":false,"message":"需要四份"+title+"才能上桌。"}
		inventory[item]=count-HOTPOT_PORTIONS
		community[dish]={"portions":HOTPOT_PORTIONS,"claimed":{}}
		return {"ok":true,"message":title+"上桌了。四份會留在餐桌，島民可以各領一份。"}
	if int(meal.get("portions",0))<=0:return {"ok":false,"message":title+"已經分完了。"}
	if meal.claimed.has(token):return {"ok":false,"message":"你已領過這一輪，剩下的留給其他島民。"}
	if count>=1000000000:return {"ok":false,"message":"背包中的"+title+"已達上限。"}
	inventory[item]=count+1
	meal.claimed[token]=true
	meal.portions=int(meal.portions)-1
	return {"ok":true,"message":"已領取一份"+title+"。"}

static func resident_line(state: Dictionary, id: String) -> String:
	var kitchen: Dictionary = state.get("public_kitchen", {})
	if not str(kitchen.get("stove", "")).is_empty():
		if kitchen.get("opened", false):
			if id == "milu":return "公共廚房開張了。就算沒趕上那一餐，手帳裡也替你留著大家說過的話。"
			if id == "aru":return "灶和長凳都留在這裡。往後誰先回來，誰就能先替大家開火。"
		else:
			if id == "milu":return "灶已經有了，開張還差湯、麵包和沙拉。公共廚房的備餐頁寫著大家已經準備多少。"
			if id == "aru":return "兩張長凳和石灶都捐作公用了。先把開張那一餐備好，大家再坐下來聊。"
	var chapter: Dictionary = state.get("chapter_one", {})
	match id:
		"aru":
			if state.get("picnic", false): return "桌邊還有空位。坐一會兒，看看橋上來的是誰。"
			if chapter.get("watered", false): return "水已經流到田裡了，下一批菜就有人照看。"
			if state.get("board", false): return "橋和公告板都修好了，下一步讓水流到田裡。"
		"milu":
			if state.get("picnic", false): return "湯和麵包都備好了。先坐下來吃，食譜等會兒再翻。"
			if chapter.get("watered", false): return "乾田終於喝到水了。留兩份湯和一份麵包給渡口的飯桌。"
		"xiaoli":
			if state.get("picnic", false) and chapter.get("watered", false): return "渡口重新開飯了。來，我把北部工坊的介紹信交給你。"
			if state.get("picnic", false): return "大家又在渡口吃飯了。等供水也穩定，就能接下一站的貨。"
			if chapter.get("shipped", false): return "出貨我收到了。下次也記得留些菜給米露。"
	return ""
