extends RefCounted
const Workshop=preload("res://scripts/bobo_workshop.gd")
const DAY:=1440.0
const NPCS:={
	"bobo":{"name":"波波","cell":Workshop.NPC_CELL,"region":"jinguashi","hello":"這塊怪石很像祖父的礦車把手。等我把它整理好再給你看。","color":"b68a63"},
	"aru":{"name":"阿榆","cell":Vector2i(38,29),"hello":"木頭有自己的紋路，小島也有。我們慢慢把它住起來。","color":"91a879"},
	"milu":{"name":"米露","cell":Vector2i(44,31),"hello":"我記得煮湯、烤麵包……啊，還沒吃飯。你要一起嗎？","color":"d6a17e"},
	"xiaoli":{"name":"小栗","cell":Vector2i(43,29),"hello":"種子在左，貨單在右。你的名字我寫在中間，這樣兩邊都找得到。","color":"cba35f"}
}
const QUESTS:={
	"bobo":[
		{"title":"祖父留下的礦車","goal":"交給波波木板 2、銅接頭 1。","items":{"plank":2,"copper_joint":1},"coins":40,"reward":{},"line":"阿榆的木板能補車底，接頭剛好固定把手。我把祖父刻的記號留下來。"},
		{"title":"怪石有自己的格子","goal":"在整理桌依標籤分類，並領取一份收藏樣本。","items":{},"sorting":true,"coins":50,"reward":{},"line":"大中小是整理標籤。看外形可不能鑑定礦石裡有什麼。"},
		{"title":"礦車的回信","goal":"完成一單礦料寄運，送入私人箱或到公告板領回。","items":{},"freight":true,"coins":70,"reward":{},"line":"貨到渡口，我就知道這台車真的走完一趟。展示架的圖樣你拿去吧。"},
		{"title":"怪石旁的烤薯","goal":"在金瓜石放一座自己的礦樣展示架，帶一份烤馬鈴薯。","items":{"baked_potato":1},"object":"ore_display","coins":90,"reward":{},"line":"我以前總把怪石收進抽屜。現在大家可以邊吃烤薯，邊猜哪一塊最像礦車。"}
	],
	"aru":[
		{"title":"有點歪的第一塊板","goal":"放一張自己的小床，再帶來木材 10。","items":{"wood":10},"object":"bed","coins":60,"reward":{"carrot_seed":3},"line":"先讓你今晚有個落腳處，筆直的事明天再說。"},
		{"title":"長椅少了一隻腳","goal":"修好渡口，再帶來木材 18、石材 8。","items":{"wood":18,"stone":8},"board":true,"coins":80,"reward":{},"unlock":"long_bench","line":"師父總坐左邊，說右邊要留給還沒回來的人。長椅的圖樣也交給你了。"},
		{"title":"留下新的刮痕","goal":"替島上放一張自己的雙人長椅和一盞木燈。","items":{},"object":"long_bench","second_object":"lamp","coins":90,"reward":{"tomato_seed":3},"unlock":"sign","line":"這道痕就是我們今天留下的。木頭記得的，比我以為的多。"},
		{"title":"有人坐的地方","goal":"完成渡口野餐，並親手種下至少兩棵樹苗。","items":{},"picnic":true,"counter":"trees_planted","target":2,"coins":120,"reward":{},"unlock":"sofa","line":"這回我想坐右邊試試。左邊不是誰的專屬座位了，誰累了都能坐。"}
	],
	"milu":[
		{"title":"忘記吃飯的人","goal":"帶兩個蘿蔔來，幫米露準備今天的湯。","items":{"radish":2},"coins":65,"reward":{"potato_seed":3},"line":"湯我記得煮了，忘的是自己還沒吃。這些馬鈴薯種子送你，改天一起烤。"},
		{"title":"沾到麵粉的頁角","goal":"帶來小麥麵包 1、菜園沙拉 2。","items":{"bread":1,"salad":2},"coins":150,"reward":{},"unlock":"planter","line":"這頁不是被風吹走，是我拿去墊鍋了。看不見字的地方，我們用味道找回來。"},
		{"title":"不是同一道湯","goal":"帶來烤馬鈴薯 2、香煎鯽魚 1。","items":{"baked_potato":2,"grilled_fish":1},"coins":150,"reward":{"wheat_seed":5},"line":"味道和以前不同，卻有人還想再添。食譜最後一行，不一定要寫得一模一樣。"},
		{"title":"替自己留一碗","goal":"完成渡口野餐，親手領取至少三次完成料理。","items":{},"picnic":true,"counter":"cooked","target":3,"coins":160,"reward":{"carrot_seed":3,"tomato_seed":3},"line":"今天這一碗，我先盛給自己。剩下的位置都空著，你們隨時可以來。"}
	],
	"xiaoli":[
		{"title":"貨單上沒寫的味道","goal":"親手採收至少一次，再帶一個蘿蔔給小栗。","items":{"radish":1},"counter":"harvests","target":1,"coins":35,"reward":{"lettuce_seed":2},"line":"原來你喜歡蘿蔔脆一點。這欄本來寫進貨價，我先把你的口味記在旁邊。"},
		{"title":"橋那頭也有熟客","goal":"修好渡口，再帶來萵苣 2、小麥 2。","items":{"lettuce":2,"wheat":2},"board":true,"coins":70,"reward":{"carrot_seed":2},"line":"橋一開，熟客就從兩邊來了。米露的萵苣要嫩葉，阿榆的小麥要磨粗，我現在不用翻帳本。"},
		{"title":"把貨單翻過來","goal":"帶來小麥麵包 1、菜園沙拉 1。","items":{"bread":1,"salad":1},"coins":90,"reward":{"tomato_seed":2},"line":"這張貨單背面還空著，正好寫邀請卡。麵包給大家分，沙拉擺中間。你也來，這行我已經寫好了。"},
		{"title":"收攤以後的位置","goal":"完成渡口野餐，並親手種下至少兩棵樹苗。","items":{},"picnic":true,"counter":"trees_planted","target":2,"coins":100,"reward":{"sapling":1},"line":"野餐那天我早早收了攤，本來還怕沒地方坐。你替我挪了個位置。這棵樹苗種哪都好，反正下回我會知道往哪裡回來。"}
	]
}
const ORDERS:=[
	{"id":"radish","name":"渡口的家常湯","items":{"radish":3},"coins":90},
	{"id":"fish","name":"小栗的魚貨籃","items":{"carp":1,"minnow":1},"coins":55},
	{"id":"bread","name":"午后的麵包香","items":{"bread":2},"coins":120}
]
static func ensure_player(p:Dictionary) -> void:
	if not p.has("stories"):p.stories={"aru":0,"milu":0,"xiaoli":0,"bobo":0}
	elif p.stories is Dictionary and not p.stories.has("xiaoli"):p.stories.xiaoli=0
	if not p.has("orders"):p.orders={"day":-1,"done":[]}
	if not p.has("trees_planted"):p.trees_planted=0
	if not p.has("cooked"):p.cooked=0
static func npc_region(id:String)->String:
	return NPCS.get(id,{}).get("region","home")

const FESTIVAL_SPOTS := {"aru":Vector2i(40,28),"milu":Vector2i(42,28)}

static func resident_cell(state:Dictionary,id:String)->Vector2i:
	if id=="bobo":return Workshop.sites(state).npc
	if state.get("festival_story_open",false) and FESTIVAL_SPOTS.has(id):return FESTIVAL_SPOTS[id]
	return NPCS[id].cell

static func ids_for_region(region:String)->Array:
	return NPCS.keys().filter(func(id):return npc_region(id)==region)

static func unlocked(p:Dictionary,kind:String) -> bool:
	var thresholds:={"long_bench":["aru",2],"sign":["aru",3],"sofa":["aru",4],"planter":["milu",2],"ore_display":["bobo",3]}
	if not thresholds.has(kind):return true
	var rule:Array=thresholds[kind]
	return int(p.get("stories",{}).get(rule[0],0))>=int(rule[1])
static func owns(s:Dictionary,token:String,kind:String) -> bool:
	for obj in s.objects.values():
		if obj.owner==token and obj.type==kind:return true
	return false
static func blocked_reason(s:Dictionary,p:Dictionary,token:String,q:Dictionary) -> String:
	var workshop:Dictionary=s.get("bobo_workshop",{})
	if q.get("sorting",false) and not workshop.get("own_done",workshop.get("done",{}).get(token,false)):return "先到整理桌完成三輪並領取樣本"
	var freight:Dictionary=s.get("mine_freight",{})
	if q.get("freight",false) and freight.get("own_job",freight.get("jobs",{}).get(token,{})).get("status")!="delivered":return "完成一單寄運或在公告板領回待領貨物"
	if q.get("board",false) and not s.board:return "先一起修好渡口公告板"
	if q.get("picnic",false) and not s.picnic:return "先到公告板完成渡口野餐"
	for field in ["object","second_object"]:
		if q.has(field) and not owns(s,token,q[field]):return "先放置委託需要的家具（必須是你放的）"
	if q.has("counter") and int(p.get(q.counter,0))<int(q.target):return "還差 %d 次，慢慢完成就好"%(int(q.target)-int(p.get(q.counter,0)))
	return ""
