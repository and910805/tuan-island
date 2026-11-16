extends RefCounted
## T071 第五個合作活動「家園布置題」（1～8 人，10 分鐘）：在渡口西南邊的臨時展示
## 地塊上，用活動專用的布置道具一起完成本輪主題；結束時發紀念票。
##
## 規劃書第 19 章：家園布置題｜1～8 人，10 分鐘｜在臨時展示地塊完成主題｜以表情交流，
## 不淘汰。活動區內工具暫時替換為活動道具，離開後還原；背包未被清空，退出或斷線也可
## 恢復。獎勵以一次性參與記錄發放。T071 驗收：退出活動後背包維持原樣，且獎勵不重發。
## 布置道具只存在 state.showcase.pieces（不進任何背包、不花錢、不限數量）；紀念票只是
## player.showcase 裡的計數，不是背包物品、也不是鈴幣，與豐收接力／河岸釣魚會的紀念票
## 分開計算。任何動作都不碰 player.inventory／coins／工具或其他欄位。
## 表情交流：沿用既有的「島民招呼」表情（Session.EMOTES，perform("emote",…)），本模組
## 不新增表情狀態；介面從活動頁面打開既有的表情選單即可。不淘汰：沒有失敗或出局，時間
## 到一定結算，每位參加者至少 1 張票。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；同樣的 state 與動作永遠得到同樣結果；
## 失敗時 state 完全不變（先在副本上操作，成功才寫回）。
##
## ── 場地（家園座標，渡口野餐後解鎖，只在風鈴渡口）──────────────────────────
## 出生點 (39,33) 西南方約 15 格、廣場石板外的一片空草地：
##   展示地塊 PLOT = Rect2i(27,44,6,4)：x 27..32、y 44..47 共 24 格（列優先 plot_cells()）。
##   告示牌 SIGN = (26,45)：緊貼地塊西側第二列。
## 這 25 格都是陸地、不是河、沒有 base_resource 固定樹／石／草；不碰（含 8 鄰格）任何
## 既有互動點、居民站位與備用站位（resident_bond 的 RANCH/DOCK/POST/BELL）、出生點、
## 渡口出入口與轉乘點、市集攤位候選、出貨箱／共餐桌候選、公告板、種子攤、節慶點、
## 豐收接力五格、河岸釣魚會告示牌與岸邊站位、河灣橋、採石點、銅礦與牧場站；也遠離
## 出生點旁玩家與測試慣用的建地（41..43,34..37、34..37,33..37、46..51,22..29）。
## 唯一重疊的既有測試座標是 test_world 的批次建造 (27..33,39..44)，那個世界沒有野餐
## （未解鎖時不保留任何格子），所以不受影響。
## 佔用處理：告示牌或任一地塊格的 objects/ground/roofs/crops/forest 有東西時活動
## 「暫停」（available()==false：開始／加入／放置／收起／完成都回 UNAVAILABLE，離開
## 仍可用；step 仍照常結算）。解鎖後空著的格子各自保留：告示牌與地塊格都
## World.protected（不能建造、耕作、種樹）；只有告示牌 World.blocked（不能穿越），
## 地塊格照樣可以走。已有東西的格子不保留，所以舊存檔不會失效，清掉後就被保留。
## blocked_cells(snapshot) 列出需要清理的格子。
##
## ── 共用回合 state.showcase（可省略；舊存檔視為 fresh()，第一次成功開始才寫入）
##   {"round":int, "active":bool, "started":float, "ends":float(=started+DURATION),
##    "theme":String（round>=1 時 = theme_of(round)；round 0 時 ""）,
##    "pieces":{"x,y":{"kind":布置道具 id, "by":token}}（只在 PLOT 內，每格最多一件）,
##    "participants":{token:{"placed":int(本輪累計放置次數), "joined":bool}},
##    "last":{} 或 {"round","theme","pieces"(件數),"met":bool,"full":bool,"players",
##             "tickets","reason":"goal"/"time","finished"},
##    "ready":float(上一輪結束時間＋COOLDOWN)}
##   participants 保留到下一輪開始；pieces 在結算後繼續展示，冷卻結束時由 step() 清空
##   （或下一輪開始時清空），地塊恢復原狀。
## ── 個人紀錄 player.showcase（可省略；只在結算時寫入）
##   {"tickets":int, "rounds":int, "best":int(結算時最多件數), "paid_round":int}
##
## ── 規則 ──
## 主題（無亂數）：theme_of(round)=THEME_ORDER[posmod(round-1,4)]，第 1 輪花園茶會、
## 第 2 輪海風小攤、第 3 輪暖燈夜、第 4 輪豐收角落，之後循環。
## 每個主題對三個分類各有需求件數（THEMES[id].need）；地塊上該分類的件數 >= 需求即該
## 分類達成，三個分類都達成＝主題達成（theme_met）。
## 布置道具（KINDS，8 種、3 類）：花草 flower_pot 小花盆／flower_box 花草長箱／fern
## 蕨葉盆栽；座位 stool 木頭小凳／bench 長木椅／cushion 野餐坐墊；燈飾 lantern 紙燈籠／
## string_lights 小串燈。不花任何東西、數量不限、不會擋路或碰撞。
## 放置 showcase_place：已加入進行中的一輪、p 在 PLOT 內、該格沒有道具、玩家中心距
## 該格中心 <= PLACE_REACH(1.6)（站在格上、上下左右或斜角相鄰都可以）、已知種類。
## 收起 showcase_remove：任何已加入的參加者都能收起任何一件（合作布置），同樣的距離。
## 本人展示件數 shown＝目前地塊上由他放的件數；placed＝本輪累計放置次數。
## 完成 showcase_finish：任何已加入的參加者在主題達成後可提早結算（reason "goal"）；
## 否則 step() 在 time>=ends 時結算（reason "time"）。主題達成不會自動結算（可以繼續
## 布置爭取滿版加成）。
## 結算：每位參加者（含中途離開、離線、一件都沒放的人）得 tickets_for(met,full)=
## 1+(主題達成 ?1:0)+(滿版 ?1:0) 張紀念票，滿版＝地塊上 >= FULL_GOAL(16) 件且三類都有；
## 每輪只發一次（paid_round 防重發），rounds+1，best=max(best,件數)。
## 離開／斷線／出遠門：entry.joined=false，放好的道具留在地塊上，貢獻保留，可再加入
## 同一輪。斷線：Session 呼叫 World.showcase_disconnect → drop()（隨後存檔）；step()
## 每次也把不在線或不在家園的參加者設為 joined=false。
## 時間到但 step 還沒跑時，除了離開以外的動作回 ENDING（state 不變）。
##
## ── 公開 API（伺服器與介面共用）──
##   const ACTIONS=["showcase_start","showcase_join","showcase_leave","showcase_place",
##         "showcase_remove","showcase_finish"], HOME, NO_CELL, SIGN(26,45),
##         PLOT=Rect2i(27,44,6,4), CATEGORIES=["flower","seat","light"],
##         CATEGORY_NAMES{id->名稱}, KINDS{id->{"name","category"}}, KIND_ORDER,
##         THEMES{id->{"name","blurb","need":{category->int}}}, THEME_ORDER, FULL_GOAL=16,
##         DURATION=600.0, COOLDOWN=60.0, MAX_PLAYERS=8, MAX_ENTRIES=32, SIGN_REACH=3.2,
##         PLACE_REACH=1.6, MAX_BONUS=2, MAX_PLACED, MAX_TICKETS, MAX_ROUNDS, MAX_ROUND,
##         訊息常數（LOCKED, WRONG_REGION, UNAVAILABLE, WRONG_SIGN, TOO_FAR_SIGN, STALE,
##         ALREADY_ACTIVE, COOLDOWN_MSG(%d), NOT_ACTIVE, ENDING, ALREADY_JOINED, FULL(%d),
##         TOO_MANY, NOT_JOINED, OUTSIDE_PLOT, TOO_FAR_TILE, TILE_TAKEN, NO_PIECE,
##         UNKNOWN_KIND, NOT_MET, BAD_EXTRA, NO_PLAYER）
##   static func unlocked(snapshot) -> bool                 # state.picnic==true
##   static func cell_free(snapshot,cell:Vector2i) -> bool
##   static func cells() -> Array                           # [SIGN]+plot_cells()（25 格）
##   static func plot_cells() -> Array                      # PLOT 的 24 格（列優先）
##   static func in_plot(p:Vector2i) -> bool
##   static func cell_key(p:Vector2i) -> String            # "x,y"（pieces 的鍵）
##   static func available(snapshot) -> bool                # 已解鎖且 25 格都空
##   static func blocked_cells(snapshot) -> Array           # 被占住、要清理的格子
##   static func reserved(snapshot,p) -> bool               # 解鎖後空著的告示牌／地塊格
##   static func blocks(snapshot,p) -> bool                 # 只有保留中的告示牌擋路
##   static func theme_of(round:int) -> String              # round<1 時 ""
##   static func theme_name(theme:String) -> String
##   static func kind_name(kind) / category_of(kind) -> String
##   static func category_counts(pieces) -> Dictionary      # {category:int}
##   static func requirements(theme,pieces) -> Array        # [{"category","name","need","have","met"}]
##   static func requirement_text(theme) -> String          # 「花草 4、座位 3、燈飾 1」
##   static func theme_met(theme,pieces) -> bool
##   static func full_display(pieces) -> bool               # >=FULL_GOAL 件且三類都有
##   static func tickets_for(met:bool,full:bool) -> int
##   static func fresh() / fresh_record() / fresh_entry() -> Dictionary
##   static func round_state(state) -> Dictionary           # 唯讀，沒有時 fresh()
##   static func record(person) -> Dictionary               # 唯讀，沒有時 fresh_record()
##   static func view(state,token) -> Dictionary            # 本人用（data.own_showcase）
##   static func public(state) -> Dictionary                # 公開快照（data.showcase，無 token）
##   static func apply(state,token,action,p,extra,at_home:bool) -> Dictionary  # {"ok","message"}
##   static func step(state,online:Dictionary) -> bool
##   static func drop(state,token) -> bool
##   static func valid(s:Dictionary) -> bool                # 存檔檢查（兩個欄位）
## World 另有 World.showcase_available(snapshot)、World.showcase_view(token)、
## World.showcase_disconnect(token) 包裝。
##
## view(state,token) 的鍵（data.own_showcase）：
##   unlocked, available, blocked_cells(Array[Vector2i]), sign(Vector2i),
##   plot_rect(Rect2i), plot_cells(Array[Vector2i]), sign_reach, place_reach,
##   round, active, seconds_left, theme(id 或 ""), theme_name, theme_blurb,
##   requirements[{"category","name","need","have","met"}]（固定 CATEGORIES 順序）,
##   theme_met, full_goal, full, pieces{"x,y":kind}（不含 token）, pieces_count,
##   categories[{"id","name","count"}], kinds[{"id","name","category","category_name"}]
##   （固定 KIND_ORDER 順序）, joined, placed(本人累計), shown(本人目前在地塊上的件數),
##   participants[{"name","placed","shown","joined","me"}]（依 token 排序，不含 token）,
##   joined_count, max_players, cooldown, can_start, can_finish, last,
##   tickets, rounds, best
## public(state)（快照 data.showcase）：round, active, started, ends, seconds_left,
##   theme, theme_name, requirements, theme_met, full_goal, full, pieces{"x,y":kind},
##   pieces_count, ready, last,
##   participants{sha256(token).left(16):{"name","placed","shown","joined"}}
##   （last 只含數字／字串，沒有 token）。
##
## 動作的 p 與 extra：
##   showcase_start、showcase_join：p 必須是 SIGN（距離 <= SIGN_REACH），extra 必須是
##     目前的 round 字串（view.round），防止重複開始或加入到不同輪。
##   showcase_leave：extra 必須是空字串（p 不看）。
##   showcase_place：p＝地塊格，extra＝"<round>|<kind>"，例如 "3|lantern"。
##   showcase_remove：p＝有道具的地塊格，extra＝"<round>"。
##   showcase_finish：extra＝"<round>"（p 不看，在家園即可）。

const ACTIONS:=["showcase_start","showcase_join","showcase_leave","showcase_place","showcase_remove","showcase_finish"]
const HOME:="home"
const NO_CELL:=Vector2i(-1,-1)
const SIGN:=Vector2i(26,45)
const PLOT:=Rect2i(27,44,6,4)
const CATEGORIES:=["flower","seat","light"]
const CATEGORY_NAMES:={"flower":"花草","seat":"座位","light":"燈飾"}
const KINDS:={
	"flower_pot":{"name":"小花盆","category":"flower"},
	"flower_box":{"name":"花草長箱","category":"flower"},
	"fern":{"name":"蕨葉盆栽","category":"flower"},
	"stool":{"name":"木頭小凳","category":"seat"},
	"bench":{"name":"長木椅","category":"seat"},
	"cushion":{"name":"野餐坐墊","category":"seat"},
	"lantern":{"name":"紙燈籠","category":"light"},
	"string_lights":{"name":"小串燈","category":"light"},
}
const KIND_ORDER:=["flower_pot","flower_box","fern","stool","bench","cushion","lantern","string_lights"]
const THEMES:={
	"garden_tea":{"name":"花園茶會","blurb":"午後的小茶會：花草多一些，留幾個位子，再點一盞燈。","need":{"flower":4,"seat":3,"light":1}},
	"sea_breeze":{"name":"海風小攤","blurb":"吹著海風的小攤：座位要夠，旁邊擺些花草和燈。","need":{"flower":2,"seat":4,"light":2}},
	"warm_night":{"name":"暖燈夜","blurb":"夜裡的暖燈角落：燈要多，坐下來慢慢聊。","need":{"flower":1,"seat":2,"light":5}},
	"harvest_corner":{"name":"豐收角落","blurb":"收成後的歇腳處：花草、座位和燈都均衡一點。","need":{"flower":3,"seat":3,"light":2}},
}
const THEME_ORDER:=["garden_tea","sea_breeze","warm_night","harvest_corner"]
const FULL_GOAL:=16
const DURATION:=600.0
const COOLDOWN:=60.0
const MAX_PLAYERS:=8
const MAX_ENTRIES:=32
const SIGN_REACH:=3.2
const PLACE_REACH:=1.6
const MAX_BONUS:=2
const MAX_PLACED:=100000
const MAX_TICKETS:=999999
const MAX_ROUNDS:=999999
const MAX_ROUND:=1000000000
const KEYS:=["active","ends","last","participants","pieces","ready","round","started","theme"]
const ENTRY_KEYS:=["joined","placed"]
const PIECE_KEYS:=["by","kind"]
const LAST_KEYS:=["finished","full","met","pieces","players","reason","round","theme","tickets"]
const RECORD_KEYS:=["best","paid_round","rounds","tickets"]
const EPSILON:=0.01

const LOCKED:="完成渡口野餐後，渡口西南草地的家園布置題才會開放。"
const WRONG_REGION:="家園布置題在風鈴渡口西南邊的展示地塊，請回到渡口再參加。"
const UNAVAILABLE:="家園布置題的展示地塊或告示牌被占住了，先把那些格子整理乾淨。"
const WRONG_SIGN:="請走到家園布置題的告示牌前開始或加入。"
const TOO_FAR_SIGN:="再靠近家園布置題的告示牌一點。"
const STALE:="活動已更新，請重新打開活動面板。"
const ALREADY_ACTIVE:="家園布置題已經開始了，在告示牌前按加入就能一起布置。"
const COOLDOWN_MSG:="展示地塊正在整理，約 %d 秒後能再開始。"
const NOT_ACTIVE:="現在沒有進行中的家園布置題，先在告示牌開始一輪。"
const ENDING:="這一輪的時間到了，正在結算。"
const ALREADY_JOINED:="你已經在這一輪裡了。"
const FULL:="這一輪已經有 %d 位島民，等下一輪再加入吧。"
const TOO_MANY:="這一輪的參加名單已滿，等下一輪再加入吧。"
const NOT_JOINED:="先在告示牌加入家園布置題。"
const OUTSIDE_PLOT:="布置道具只能放在展示地塊裡。"
const TOO_FAR_TILE:="走近那一格再布置。"
const TILE_TAKEN:="那一格已經有布置道具了，換一格或先收起來。"
const NO_PIECE:="那一格沒有布置道具。"
const UNKNOWN_KIND:="找不到這種布置道具，請重新打開活動面板。"
const NOT_MET:="主題還沒完成，照著主題需求再布置一下吧。"
const BAD_EXTRA:="請重新操作家園布置題。"
const NO_PLAYER:="請重新加入世界再參加家園布置題。"

static func unlocked(snapshot:Dictionary) -> bool:
	return snapshot.get("picnic",false)==true

static func cell_free(snapshot:Dictionary,cell:Vector2i) -> bool:
	var tile:="%d,%d"%[cell.x,cell.y]
	for field in ["objects","ground","roofs","crops","forest"]:
		var layer:Variant=snapshot.get(field,{})
		if layer is Dictionary and layer.has(tile):return false
	return true

static func plot_cells() -> Array:
	var out:=[]
	for y in range(PLOT.position.y,PLOT.end.y):
		for x in range(PLOT.position.x,PLOT.end.x):out.append(Vector2i(x,y))
	return out

static func cells() -> Array:
	return [SIGN]+plot_cells()

static func in_plot(p:Vector2i) -> bool:
	return PLOT.has_point(p)

static func cell_key(p:Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

## 已解鎖且告示牌與 24 格地塊都沒有被佔用。
static func available(snapshot:Dictionary) -> bool:
	return unlocked(snapshot) and blocked_cells(snapshot).is_empty()

## 告示牌與地塊中被 objects/ground/roofs/crops/forest 佔住的格子（列優先，告示牌在前）。
static func blocked_cells(snapshot:Dictionary) -> Array:
	var out:=[]
	for cell:Vector2i in cells():
		if not cell_free(snapshot,cell):out.append(cell)
	return out

## 解鎖後仍空著的告示牌或地塊格（World.protected：不能建造、耕作、種樹）。
static func reserved(snapshot:Dictionary,p:Vector2i) -> bool:
	return (p==SIGN or in_plot(p)) and unlocked(snapshot) and cell_free(snapshot,p)

## 只有保留中的告示牌擋路（World.blocked）；地塊格照樣可以走。
static func blocks(snapshot:Dictionary,p:Vector2i) -> bool:
	return p==SIGN and reserved(snapshot,p)

static func theme_of(round_id:int) -> String:
	if round_id<1:return ""
	return str(THEME_ORDER[posmod(round_id-1,THEME_ORDER.size())])

static func theme_name(theme:String) -> String:
	return str(THEMES[theme].name) if THEMES.has(theme) else ""

static func kind_name(kind:String) -> String:
	return str(KINDS[kind].name) if KINDS.has(kind) else ""

static func category_of(kind:String) -> String:
	return str(KINDS[kind].category) if KINDS.has(kind) else ""

static func category_counts(pieces:Variant) -> Dictionary:
	var out:={}
	for category:String in CATEGORIES:out[category]=0
	if pieces is Dictionary:
		for tile in pieces:
			var piece:Variant=pieces[tile]
			if not piece is Dictionary:continue
			var category:=category_of(str(piece.get("kind","")))
			if out.has(category):out[category]=int(out[category])+1
	return out

static func requirements(theme:String,pieces:Variant) -> Array:
	var counts:=category_counts(pieces)
	var need:Dictionary=THEMES[theme].need if THEMES.has(theme) else {}
	var out:=[]
	for category:String in CATEGORIES:
		var want:=int(need.get(category,0))
		var have:=int(counts[category])
		out.append({"category":category,"name":str(CATEGORY_NAMES[category]),"need":want,"have":have,"met":THEMES.has(theme) and have>=want})
	return out

static func requirement_text(theme:String) -> String:
	if not THEMES.has(theme):return ""
	var parts:=PackedStringArray()
	for category:String in CATEGORIES:parts.append("%s %d"%[CATEGORY_NAMES[category],int(THEMES[theme].need[category])])
	return "、".join(parts)

static func _progress_text(theme:String,pieces:Variant) -> String:
	var parts:=PackedStringArray()
	for row:Dictionary in requirements(theme,pieces):parts.append("%s %d/%d"%[row.name,int(row.have),int(row.need)])
	return "、".join(parts)

static func theme_met(theme:String,pieces:Variant) -> bool:
	if not THEMES.has(theme):return false
	for row:Dictionary in requirements(theme,pieces):
		if row.met!=true:return false
	return true

static func full_display(pieces:Variant) -> bool:
	if not pieces is Dictionary or pieces.size()<FULL_GOAL:return false
	var counts:=category_counts(pieces)
	for category:String in CATEGORIES:
		if int(counts[category])<1:return false
	return true

static func tickets_for(met:bool,full:bool) -> int:
	return 1+(1 if met else 0)+(1 if full else 0)

static func fresh() -> Dictionary:
	return {"round":0,"active":false,"started":0.0,"ends":0.0,"theme":"","pieces":{},"participants":{},"last":{},"ready":0.0}

static func fresh_record() -> Dictionary:
	return {"tickets":0,"rounds":0,"best":0,"paid_round":0}

static func fresh_entry() -> Dictionary:
	return {"placed":0,"joined":true}

static func round_state(state:Dictionary) -> Dictionary:
	var found:Variant=state.get("showcase")
	return found if found is Dictionary else fresh()

static func record(person:Dictionary) -> Dictionary:
	var found:Variant=person.get("showcase")
	return found if found is Dictionary else fresh_record()

static func _name_of(state:Dictionary,token:String) -> String:
	var person:Variant=state.get("players",{}).get(token)
	return str(person.get("name","島民")) if person is Dictionary else "島民"

static func _joined_count(show:Dictionary) -> int:
	var count:=0
	for token in show.participants:
		if show.participants[token].get("joined")==true:count+=1
	return count

static func _expired(state:Dictionary,show:Dictionary) -> bool:
	return show.active==true and float(state.get("time",0.0))>=float(show.ends)

## 地塊上由 token 放的件數。
static func _shown(show:Dictionary,token:String) -> int:
	var count:=0
	if show.pieces is Dictionary:
		for tile in show.pieces:
			var piece:Variant=show.pieces[tile]
			if piece is Dictionary and str(piece.get("by",""))==token:count+=1
	return count

## "x,y"->kind（不含放置者 token）。
static func _public_pieces(show:Dictionary) -> Dictionary:
	var out:={}
	if show.pieces is Dictionary:
		var tiles:Array=show.pieces.keys()
		tiles.sort()
		for tile in tiles:
			var piece:Variant=show.pieces[tile]
			if piece is Dictionary:out[str(tile)]=str(piece.get("kind",""))
	return out

static func _theme_fields(show:Dictionary) -> Dictionary:
	var theme:=str(show.theme)
	return {"theme":theme,"theme_name":theme_name(theme),"requirements":requirements(theme,show.pieces),
		"theme_met":theme_met(theme,show.pieces),"full_goal":FULL_GOAL,"full":full_display(show.pieces),
		"pieces":_public_pieces(show),"pieces_count":(show.pieces as Dictionary).size() if show.pieces is Dictionary else 0}

## 只給本人看的摘要（Session 以 data.own_showcase 送給本人）。不含任何 token。
static func view(state:Dictionary,token:String) -> Dictionary:
	var show:=round_state(state)
	var now:=float(state.get("time",0.0))
	var person:Variant=state.get("players",{}).get(token,{})
	var own:=record(person if person is Dictionary else {})
	var entry:Dictionary=show.participants.get(token,{}) if show.participants is Dictionary else {}
	var tokens:Array=show.participants.keys()
	tokens.sort()
	var list:=[]
	for other:String in tokens:
		var e:Dictionary=show.participants[other]
		list.append({"name":_name_of(state,other),"placed":int(e.placed),"shown":_shown(show,other),"joined":e.joined==true,"me":other==token})
	var counts:=category_counts(show.pieces)
	var categories:=[]
	for category:String in CATEGORIES:categories.append({"id":category,"name":str(CATEGORY_NAMES[category]),"count":int(counts[category])})
	var kinds:=[]
	for kind:String in KIND_ORDER:kinds.append({"id":kind,"name":kind_name(kind),"category":category_of(kind),"category_name":str(CATEGORY_NAMES[category_of(kind)])})
	var active:bool=show.active==true
	var cooldown:=0.0 if active else maxf(0.0,float(show.ready)-now)
	var open:=available(state)
	var joined:bool=entry.get("joined",false)==true
	var theme:=_theme_fields(show)
	var out:={"unlocked":unlocked(state),"available":open,"blocked_cells":blocked_cells(state),
		"sign":SIGN,"plot_rect":PLOT,"plot_cells":plot_cells(),"sign_reach":SIGN_REACH,"place_reach":PLACE_REACH,
		"round":int(show.round),"active":active,
		"seconds_left":maxf(0.0,float(show.ends)-now) if active else 0.0,
		"theme_blurb":str(THEMES[theme.theme].blurb) if THEMES.has(theme.theme) else "",
		"categories":categories,"kinds":kinds,
		"joined":joined,"placed":int(entry.get("placed",0)),"shown":_shown(show,token) if not entry.is_empty() else 0,
		"participants":list,"joined_count":_joined_count(show),"max_players":MAX_PLAYERS,
		"cooldown":cooldown,"can_start":open and not active and cooldown<=0.0,
		"can_finish":open and active and not _expired(state,show) and joined and theme.theme_met==true,
		"last":(show.last as Dictionary).duplicate(true),
		"tickets":int(own.tickets),"rounds":int(own.rounds),"best":int(own.best)}
	out.merge(theme)
	return out

## 公開快照（每個區域、每位接收者都一樣）：參加者以 sha256(token) 前 16 碼為鍵，
## 與 Session 公開的 player id 相同；道具只有格子與種類，沒有放置者 token。
static func public(state:Dictionary) -> Dictionary:
	var show:=round_state(state)
	var now:=float(state.get("time",0.0))
	var people:={}
	for token in show.participants:
		var e:Dictionary=show.participants[token]
		people[String(token).sha256_text().left(16)]={"name":_name_of(state,str(token)),"placed":int(e.placed),"shown":_shown(show,str(token)),"joined":e.joined==true}
	var active:bool=show.active==true
	var out:={"round":int(show.round),"active":active,"started":float(show.started),"ends":float(show.ends),
		"seconds_left":maxf(0.0,float(show.ends)-now) if active else 0.0,
		"ready":float(show.ready),"last":(show.last as Dictionary).duplicate(true),"participants":people}
	out.merge(_theme_fields(show))
	return out

static func _distance(person:Dictionary,cell:Vector2i) -> float:
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## 六個活動動作。World 只負責把 actor 是否在家園（at_home）傳進來；
## 失敗時 state 完全不變（先在副本上操作，成功才寫回）。
static func apply(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,at_home:bool) -> Dictionary:
	if not unlocked(state):return _fail(LOCKED)
	if not at_home:return _fail(WRONG_REGION)
	var person:Variant=state.get("players",{}).get(token)
	if not person is Dictionary:return _fail(NO_PLAYER)
	if state.has("showcase") and not state.showcase is Dictionary:return _fail(BAD_EXTRA)
	if action not in ACTIONS:return _fail(BAD_EXTRA)
	if action!="showcase_leave" and not available(state):return _fail(UNAVAILABLE)
	var show:Dictionary=round_state(state).duplicate(true)
	var now:=float(state.get("time",0.0))
	var entry:Dictionary=show.participants.get(token,{})
	var round_text:=str(int(show.round))
	var message:=""
	if action=="showcase_start":
		if p!=SIGN:return _fail(WRONG_SIGN)
		if _distance(person,SIGN)>SIGN_REACH:return _fail(TOO_FAR_SIGN)
		if _expired(state,show):return _fail(ENDING)
		if show.active==true:return _fail(ALREADY_ACTIVE)
		if now<float(show.ready):return _fail(COOLDOWN_MSG%ceili(float(show.ready)-now))
		if extra!=round_text:return _fail(STALE)
		if int(show.round)>=MAX_ROUND:return _fail(STALE)
		show.round=int(show.round)+1
		show.active=true
		show.started=now
		show.ends=now+DURATION
		show.theme=theme_of(int(show.round))
		show.pieces={}
		show.participants={token:fresh_entry()}
		message="第 %d 輪家園布置題開始！本輪主題「%s」：%s。10 分鐘內在展示地塊擺好布置道具；道具只在活動裡使用，背包不會變動。"%[int(show.round),theme_name(show.theme),requirement_text(show.theme)]
	elif action=="showcase_join":
		if p!=SIGN:return _fail(WRONG_SIGN)
		if _distance(person,SIGN)>SIGN_REACH:return _fail(TOO_FAR_SIGN)
		if show.active!=true:return _fail(NOT_ACTIVE)
		if _expired(state,show):return _fail(ENDING)
		if extra!=round_text:return _fail(STALE)
		if entry.get("joined",false)==true:return _fail(ALREADY_JOINED)
		if _joined_count(show)>=MAX_PLAYERS:return _fail(FULL%MAX_PLAYERS)
		if entry.is_empty():
			if show.participants.size()>=MAX_ENTRIES:return _fail(TOO_MANY)
			entry=fresh_entry()
			show.participants[token]=entry
		entry.joined=true
		message="加入第 %d 輪家園布置題！本輪主題「%s」：%s。布置道具只在活動裡使用，背包不會變動。"%[int(show.round),theme_name(show.theme),requirement_text(show.theme)]
	elif action=="showcase_leave":
		if not extra.is_empty():return _fail(BAD_EXTRA)
		if show.active!=true:return _fail(NOT_ACTIVE)
		if entry.get("joined",false)!=true:return _fail(NOT_JOINED)
		entry.joined=false
		message="離開家園布置題。背包沒有變動；你擺的道具會留在地塊上，參與紀錄保留到這一輪結算。"
	elif action=="showcase_place":
		var parts:=extra.split("|")
		if parts.size()!=2:return _fail(BAD_EXTRA)
		if show.active!=true:return _fail(NOT_ACTIVE)
		if _expired(state,show):return _fail(ENDING)
		if parts[0]!=round_text:return _fail(STALE)
		if entry.get("joined",false)!=true:return _fail(NOT_JOINED)
		var kind:=parts[1]
		if not KINDS.has(kind):return _fail(UNKNOWN_KIND)
		if not in_plot(p):return _fail(OUTSIDE_PLOT)
		if _distance(person,p)>PLACE_REACH:return _fail(TOO_FAR_TILE)
		if show.pieces.has(cell_key(p)):return _fail(TILE_TAKEN)
		show.pieces[cell_key(p)]={"kind":kind,"by":token}
		entry.placed=mini(MAX_PLACED,int(entry.placed)+1)
		message="擺上%s。「%s」進度：%s。"%[kind_name(kind),theme_name(show.theme),_progress_text(show.theme,show.pieces)]
		if theme_met(show.theme,show.pieces):message+="主題完成了！可以按「完成展示」結算，或繼續布置到 %d 件。"%FULL_GOAL
	elif action=="showcase_remove":
		if show.active!=true:return _fail(NOT_ACTIVE)
		if _expired(state,show):return _fail(ENDING)
		if extra!=round_text:return _fail(STALE)
		if entry.get("joined",false)!=true:return _fail(NOT_JOINED)
		if not in_plot(p):return _fail(OUTSIDE_PLOT)
		if _distance(person,p)>PLACE_REACH:return _fail(TOO_FAR_TILE)
		var piece:Variant=show.pieces.get(cell_key(p))
		if not piece is Dictionary:return _fail(NO_PIECE)
		show.pieces.erase(cell_key(p))
		message="收起%s。「%s」進度：%s。"%[kind_name(str(piece.kind)),theme_name(show.theme),_progress_text(show.theme,show.pieces)]
	elif action=="showcase_finish":
		if show.active!=true:return _fail(NOT_ACTIVE)
		if _expired(state,show):return _fail(ENDING)
		if extra!=round_text:return _fail(STALE)
		if entry.get("joined",false)!=true:return _fail(NOT_JOINED)
		if not theme_met(show.theme,show.pieces):return _fail(NOT_MET)
		state.showcase=show
		_finish(state,show,"goal")
		var last:Dictionary=show.last
		return {"ok":true,"message":"「%s」布置完成！地塊上共 %d 件，參加者各得 %d 張紀念票。展示會保留到冷卻結束。"%[theme_name(str(last.theme)),int(last.pieces),int(last.tickets)]}
	state.showcase=show
	return {"ok":true,"message":message}

## 結算目前這一輪：每位參加者（含離開、離線、沒放道具的人）各發一次紀念票。只改 state。
## pieces 不清空（展示到冷卻結束）。
static func _finish(state:Dictionary,show:Dictionary,reason:String) -> void:
	var round_id:=int(show.round)
	var count:=(show.pieces as Dictionary).size()
	var met:=theme_met(str(show.theme),show.pieces)
	var full:=full_display(show.pieces)
	var tickets:=tickets_for(met,full)
	var players:Variant=state.get("players",{})
	for token in show.participants:
		var entry:Dictionary=show.participants[token]
		entry.joined=false
		var person:Variant=players.get(token) if players is Dictionary else null
		if not person is Dictionary:continue
		var own:Dictionary=record(person).duplicate(true)
		if int(own.paid_round)>=round_id:continue
		own.tickets=mini(MAX_TICKETS,int(own.tickets)+tickets)
		own.rounds=mini(MAX_ROUNDS,int(own.rounds)+1)
		own.best=maxi(int(own.best),count)
		own.paid_round=round_id
		person.showcase=own
	var now:=float(state.get("time",0.0))
	show.active=false
	show.last={"round":round_id,"theme":str(show.theme),"pieces":count,"met":met,"full":full,
		"players":show.participants.size(),"tickets":tickets,"reason":reason,"finished":now}
	show.ready=now+COOLDOWN

static func _drop_entry(show:Dictionary,token:String) -> bool:
	var entry:Variant=show.participants.get(token)
	if not entry is Dictionary or entry.joined!=true:return false
	entry.joined=false
	return true

## Session 在玩家離線時呼叫（經 World.showcase_disconnect）。有變更時回傳 true。
static func drop(state:Dictionary,token:String) -> bool:
	var show:Variant=state.get("showcase")
	if not show is Dictionary or not show.get("participants") is Dictionary:return false
	return _drop_entry(show,token)

## World.step 每個 tick 呼叫：不在線或不在家園的參加者退出；時間到時結算（含離線
## 者）；冷卻結束後清空展示道具。只改 state，有變更時回傳 true。
static func step(state:Dictionary,online:Dictionary) -> bool:
	var show:Variant=state.get("showcase")
	if not show is Dictionary or not show.get("participants") is Dictionary or not show.get("pieces") is Dictionary:return false
	var changed:=false
	var players:Variant=state.get("players",{})
	for token in show.participants:
		var person:Variant=players.get(token) if players is Dictionary else null
		var away:bool=not online.has(token) or not person is Dictionary or str(person.get("region",HOME))!=HOME
		if away and _drop_entry(show,token):changed=true
	if _expired(state,show):
		_finish(state,show,"time")
		changed=true
	elif show.active!=true and not (show.pieces as Dictionary).is_empty() and float(state.get("time",0.0))>=float(show.ready):
		show.pieces={}
		changed=true
	return changed

# ------------------------------------------------------------------ schema --

## 存檔檢查：state.showcase 與每位 player.showcase 都可省略；存在時檢查型別、上限、
## 已知主題與道具、道具只在地塊內、放置者是參加者、joined 只在進行中、結算摘要與
## 目前展示一致、paid_round、時間不在未來。通過時把 JSON 讀回的浮點整數正規化為 int。
## s.picnic 必須已由 validate_region 補好。
static func valid(s:Dictionary) -> bool:
	var players:Variant=s.get("players")
	if not players is Dictionary:return false
	var now:=float(s.get("time",0.0))
	var has_round:=s.has("showcase")
	var show:Dictionary={}
	if has_round:
		if s.get("picnic")!=true:return false
		if not _valid_round(s.showcase,players,now):return false
		show=s.showcase
	var limit:=0
	if has_round:limit=int(show.round)-(1 if show.active else 0)
	for token in players:
		var person:Variant=players[token]
		if not person is Dictionary or not person.has("showcase"):continue
		if not has_round:return false
		if not _valid_record(person.showcase,limit):return false
	if has_round and int(show.round)>=1 and not show.active:
		for token in show.participants:
			var person:Dictionary=players[token]
			if not person.has("showcase") or int(person.showcase.paid_round)!=int(show.round):return false
	return true

static func _parse_tile(tile:Variant) -> Vector2i:
	if not tile is String:return NO_CELL
	var parts:PackedStringArray=tile.split(",")
	if parts.size()!=2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():return NO_CELL
	var cell:=Vector2i(int(parts[0]),int(parts[1]))
	return cell if cell_key(cell)==tile else NO_CELL

static func _valid_round(show:Variant,players:Dictionary,now:float) -> bool:
	if not show is Dictionary or show.size()!=KEYS.size():return false
	for field in KEYS:
		if not show.has(field):return false
	if not _whole(show.round,0,MAX_ROUND) or not show.active is bool or not show.theme is String:return false
	for field in ["started","ends","ready"]:
		if not _number(show[field],0.0,1.0e12):return false
	var round_id:=int(show.round)
	if show.theme!=theme_of(round_id):return false
	if show.active and round_id<1:return false
	if round_id==0 and (float(show.started)!=0.0 or float(show.ends)!=0.0 or float(show.ready)!=0.0):return false
	if round_id>=1:
		if float(show.started)>now+EPSILON or absf(float(show.ends)-float(show.started)-DURATION)>EPSILON:return false
	var participants:Variant=show.participants
	if not participants is Dictionary or participants.size()>MAX_ENTRIES:return false
	if round_id==0 and not participants.is_empty():return false
	if round_id>=1 and participants.is_empty():return false
	var joined:=0
	for token in participants:
		if not token is String or not players.has(token):return false
		var e:Variant=participants[token]
		if not e is Dictionary or e.size()!=ENTRY_KEYS.size():return false
		for field in ENTRY_KEYS:
			if not e.has(field):return false
		if not e.joined is bool or not _whole(e.placed,0,MAX_PLACED):return false
		if e.joined and not show.active:return false
		if e.joined:joined+=1
	if joined>MAX_PLAYERS:return false
	var pieces:Variant=show.pieces
	if not pieces is Dictionary or pieces.size()>PLOT.get_area():return false
	if round_id==0 and not pieces.is_empty():return false
	var by_count:={}
	for tile in pieces:
		var cell:=_parse_tile(tile)
		if cell==NO_CELL or not in_plot(cell):return false
		var piece:Variant=pieces[tile]
		if not piece is Dictionary or piece.size()!=PIECE_KEYS.size():return false
		for field in PIECE_KEYS:
			if not piece.has(field):return false
		if not piece.kind is String or not KINDS.has(piece.kind):return false
		if not piece.by is String or not participants.has(piece.by):return false
		by_count[piece.by]=int(by_count.get(piece.by,0))+1
	for token in by_count:
		if int(by_count[token])>int(participants[token].placed):return false
	var last:Variant=show.last
	if not last is Dictionary:return false
	var finished_round:=round_id if not show.active else round_id-1
	if finished_round<=0:
		if not last.is_empty():return false
	else:
		if last.size()!=LAST_KEYS.size():return false
		for field in LAST_KEYS:
			if not last.has(field):return false
		if not _whole(last.round,1,MAX_ROUND) or int(last.round)!=finished_round:return false
		if not last.theme is String or last.theme!=theme_of(int(last.round)):return false
		if not _whole(last.pieces,0,PLOT.get_area()) or not last.met is bool or not last.full is bool:return false
		if last.full and int(last.pieces)<FULL_GOAL:return false
		if not _whole(last.players,1,MAX_ENTRIES) or not _whole(last.tickets,1,1+MAX_BONUS):return false
		if int(last.tickets)!=tickets_for(last.met,last.full):return false
		if not last.reason is String or last.reason not in ["goal","time"]:return false
		if last.reason=="goal" and not last.met:return false
		if not _number(last.finished,0.0,now+EPSILON):return false
		if absf(float(show.ready)-float(last.finished)-COOLDOWN)>EPSILON:return false
		if not show.active:
			# The finished round is the current one: roster and (uncleared) display must agree.
			if int(last.players)!=participants.size():return false
			if float(last.finished)+EPSILON<float(show.started):return false
			if last.reason=="time" and float(last.finished)+EPSILON<float(show.ends):return false
			if not pieces.is_empty():
				if int(last.pieces)!=pieces.size() or last.met!=theme_met(str(show.theme),pieces) or last.full!=full_display(pieces):return false
		elif float(show.started)+EPSILON<float(last.finished)+COOLDOWN:
			return false
	show.round=int(show.round)
	for field in ["started","ends","ready"]:show[field]=float(show[field])
	for token in participants:
		var e:Dictionary=participants[token]
		e.placed=int(e.placed)
	if not last.is_empty():
		for field in ["round","pieces","players","tickets"]:last[field]=int(last[field])
		last.finished=float(last.finished)
	return true

static func _valid_record(own:Variant,limit:int) -> bool:
	if not own is Dictionary or own.size()!=RECORD_KEYS.size():return false
	for field in RECORD_KEYS:
		if not own.has(field):return false
	if not _whole(own.rounds,1,MAX_ROUNDS) or not _whole(own.tickets,1,MAX_TICKETS):return false
	if not _whole(own.best,0,PLOT.get_area()) or not _whole(own.paid_round,1,maxi(limit,0)):return false
	if int(own.tickets)<int(own.rounds) or int(own.tickets)>mini(MAX_TICKETS,int(own.rounds)*(1+MAX_BONUS)):return false
	for field in RECORD_KEYS:own[field]=int(own[field])
	return true

static func _number(value:Variant,minimum:float,maximum:float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum

static func _whole(value:Variant,minimum:int,maximum:int) -> bool:
	return _number(value,float(minimum),float(maximum)) and floorf(float(value))==float(value)

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}
