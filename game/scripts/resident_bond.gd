extends RefCounted
## T066：阿榆、米露、小栗、波波（第一批）與茶茶、星禾（第二批）的好感四階
## 與可重看的關係事件。
##
## 規劃書第 17 章：好感分認識、熟悉、信任、好友四階，每階一個可重看事件；
## 送禮每天只計第一次主要好感，重複送仍會收下；對話與完成委託也增加進度；
## 好感不隨時間下降；多人各自有關係進度。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數。每位玩家的紀錄存在自己的
## player.bonds（第一次聊天或送禮才寫入），委託進度的好感由 player.stories
## 即時換算，舊存檔不需遷移。所有事件皆為遊戲原創情節，沒有物品或鈴幣獎勵。
const Village=preload("res://scripts/village.gd")

const ACTIONS:=["resident_talk","resident_gift"]
const RESIDENTS:=["aru","milu","xiaoli","bobo","chacha","xinghe","mianmian","achao","nuannuan","luoluo","lingpopo","diandian"]
## 第二批：不在 Village.NPCS 的地方居民。名字與所在地寫在這裡；站位由
## World.bond_place 依各地區腳本判定（茶茶在貓空茶園，星禾在蘭陽木橋旁）。
## 第三批：棉棉在渡口牛羊飼料站旁，完成渡口野餐（牧場開放）後才出現。
## 第四批：阿潮在風鈴渡口碼頭旁，碼頭修好第一段（dock_stage>=1）後才出現；
## 暖暖在礁溪暖泉溪畔，到得了暖泉高地就能見到。
## 第五批：洛洛（郵差）在家園出貨箱一帶，鈴婆婆（鐘匠）在渡口廣場北側草地（風鈴樹以北兩格）；
## 兩位都在完成渡口野餐後出現。
## 第六批：點點（插畫家）在星芽庭園映星池西岸，到得了庭園就能見到。
const LOCAL_NAMES:={"chacha":"茶茶","xinghe":"星禾","mianmian":"棉棉","achao":"阿潮","nuannuan":"暖暖","luoluo":"洛洛","lingpopo":"鈴婆婆","diandian":"點點"}
const LOCAL_PLACES:={"chacha":"貓空合作茶園","xinghe":"蘭陽水圳木橋旁","mianmian":"渡口牛羊飼料站旁","achao":"風鈴渡口碼頭旁","nuannuan":"礁溪暖泉溪畔","luoluo":"家園出貨箱附近","lingpopo":"渡口廣場北側草地","diandian":"星芽庭園映星池西岸"}
## 沒有其他對話頁、走近按互動鍵直接開好感頁的居民。
const WALK_UP:=["mianmian","achao","nuannuan","luoluo","lingpopo","diandian"]
## 棉棉的站位候選（家園座標）。第一格被建物、作物或樹佔用時依序往後找，
## 全被佔用時仍用第一格。伺服器與介面共用 ranch_cell。
## 第二格原為 (51,33)，其正下方 (51,34) 有一棵固定的裝飾樹會遮住下半身，
## 第四批改為本身與正下方都沒有固定樹石的 (48,33)。
const RANCH_CELLS:=[Vector2i(49,33),Vector2i(48,33),Vector2i(47,33),Vector2i(49,37)]
const RANCH_LOCKED:="完成渡口野餐後，棉棉才會到牧場來。"
## 阿潮的站位候選（家園座標，渡口轉乘點 (47,30) 東側）；遞補規則同棉棉。
## 四格本身與正下方都沒有固定的樹或石頭。
const DOCK_CELLS:=[Vector2i(49,30),Vector2i(50,30),Vector2i(49,31),Vector2i(50,31)]
const DOCK_LOCKED:="渡口碼頭修好後，阿潮才會到渡口來修船。"
## 暖暖的站位（礁溪暖泉高地，暖泉溪南岸；該地區不能建造，固定一格）。
const SPRING_REGION:="jiaoxi"
const SPRING_CELL:=Vector2i(20,22)
## 點點的站位（星芽庭園，映星池 (23..28,19..23) 西岸外兩格的草地）。該地區是
## 垂釣保護區不能建造，固定一格；不在步道 (y=25,26) 上，距步道口 (13,25) 七格以上。
const GARDEN_REGION:="star_garden"
const GARDEN_CELL:=Vector2i(20,21)
## 洛洛的站位候選（家園座標，出貨箱 (42,31) 東南側）；遞補規則同棉棉。
## 不用出貨箱正下方（玩家出貨站的位置）與出生點 (39,33) 東側的第一批建地
## （許多工作台、爐子放在 (40,33)、(41,34)）；前三格距出生點 4 格，站在出生點
## 不會誤觸；(44,33) 緊鄰糯米雞 (45,34)，不列入。四格本身與正下方都沒有固定的
## 樹或石頭，也不在保留地。
const POST_CELLS:=[Vector2i(43,33),Vector2i(43,34),Vector2i(43,35),Vector2i(42,33)]
const POST_LOCKED:="完成渡口野餐後，洛洛才會到出貨箱附近收信。"
## 鈴婆婆的站位候選（家園座標，風鈴樹 (41,28) 北側兩格）；遞補規則同棉棉。
## 不用樹的東側 (45,28)：緊鄰風鈴節訪客 (44,28) 與到站點 (46,30)；也不用
## 樹正上方 (41,27)：樹冠會遮住她。四格本身與正下方都沒有固定的樹或石頭
## （(40,26) 是固定石頭，因此不列入），也不在保留地。
const BELL_CELLS:=[Vector2i(41,26),Vector2i(42,26),Vector2i(41,25),Vector2i(43,26)]
const BELL_LOCKED:="完成渡口野餐後，鈴婆婆才會到廣場北側的草地修鈴。"
## 地方居民沒有 Village.QUESTS；以本人紀錄上既有的完成旗標換算委託好感。
## 星禾：「冬天也開花」回報（player.greenhouse_reported）。茶茶的茶陶進度
## 不在玩家紀錄上，本批不換算。
const STORY_FLAGS:={"xinghe":["greenhouse_reported"]}
const STAGES:=["認識","熟悉","信任","好友"]
const THRESHOLDS:=[1,6,14,24]
const LIMIT:=24
const TALK_POINTS:=1
const GIFT_POINTS:=1
const LIKED_POINTS:=3
## 每完成一段居民委託換算的好感（由 player.stories 推得，不另存）。
const STORY_POINTS:=3

## 喜歡的禮物（對應規劃書「喜歡的事物」中已存在於遊戲的物品）。
const LIKES:={
	"aru":["tea_light","tea_deep","mist_tea_brew"],
	"milu":["soup","carrot_soup","trout_hotpot","star_mushroom"],
	"xiaoli":["strawberry_jam","strawberry_toast"],
	"bobo":["crystal_sand","baked_potato","roasted_sweet_potato"],
	"chacha":["tea_leaf","tea_light","tea_deep"],
	"xinghe":["bluebell","orange_blossom","chime_herb","sapling","bluebell_seed","orange_blossom_seed","chime_herb_seed"],
	"mianmian":["feed","wool","wool_cloth"],
	# 規劃書「魚料理、繩結」：繩結沒有對應物品，以編繩用的纖維代替。
	"achao":["grilled_fish","salt_grilled_fish","trout_hotpot","fiber"],
	# 規劃書「薑茶、陶杯」：沒有薑茶與陶杯物品，以暖泉薑與現有熱茶代替。
	"nuannuan":["ginger","tea_light","tea_deep","mist_tea_brew","ginger_tea"],
	# 規劃書「飯糰、地圖」：沒有飯糰與地圖物品，以送信路上好帶的點心代替。
	"luoluo":["bread","garden_cookie","roasted_sweet_potato"],
	# 規劃書「簡單家常菜」：對應現有的家常湯與菜。
	"lingpopo":["soup","carrot_soup","salad","baked_potato"],
	# 規劃書「圖鑑紀錄、花材」：圖鑑紀錄不是物品，以可入畫的三種花與星夜菇（蘑菇森林主題）對應。
	"diandian":["bluebell","orange_blossom","chime_herb","star_mushroom"],
}
const LIKE_TEXT:={
	"diandian":"可以入畫的花材和菇（鈴蘭藍花、蜜橙花、風鈴香草、星夜菇）",
	"luoluo":"送信路上好帶的點心（麵包、花園餅乾、烤地瓜）",
	"lingpopo":"簡單的家常菜（蘿蔔湯、胡蘿蔔濃湯、沙拉、烤馬鈴薯）",
	"achao":"魚料理和編繩的材料（香煎鯽魚、香煎溪魚、雪點鱒魚火鍋、纖維）",
	"nuannuan":"薑和熱茶（暖泉薑、淺焙茶、深焙茶、霧竹茶飲）",
	"mianmian":"飼料和柔軟的布料（飼料、羊毛、羊毛布）",
	"chacha":"茶葉（新鮮茶葉、淺焙茶、深焙茶）",
	"xinghe":"花和種苗（鈴蘭藍花、蜜橙花、風鈴香草與它們的種子、小樹苗）",
	"aru":"熱茶（淺焙茶、深焙茶、霧竹茶飲）",
	"milu":"菇和熱湯（星夜菇、蘿蔔湯、胡蘿蔔濃湯、雪點鱒魚火鍋）",
	"xiaoli":"果醬（草莓果醬）",
	"bobo":"晶砂和烤薯（晶砂、烤馬鈴薯、烤地瓜）",
}
## 每位居民都會收下的一般禮物（作物、花與家常料理）。
const COMMON_GIFTS:=["radish","lettuce","wheat","carrot","potato","tomato","egg","milk","bread","salad","grilled_fish","pumpkin_pie","garden_cookie","bluebell","orange_blossom","chime_herb","strawberry_toast"]

const TALK_LINES:={
	"aru":["今天刨了半塊板，木屑的味道很好。你那邊的屋子住得還習慣嗎？","渡口的風往東吹，晾木頭正好。慢慢來，木頭不催人。","我在想長椅旁要不要再放一張小桌。你覺得呢？"],
	"milu":["湯剛滾，我又忘了自己那碗。你吃過了嗎？","今天的麵團發得比我記得的快。大概是天氣暖了。","有人說想喝上回那鍋湯，可是我每回煮的都不太一樣。"],
	"xiaoli":["今天的貨單只寫了一半，另一半留給還沒到的貨。","有熟客問起你種的菜。我說，等你有空再送就好。","攤子的招牌有點褪色了。等收攤我再描一次。"],
	"bobo":["這塊石頭敲起來的聲音不一樣，你聽聽。","祖父說礦車走得慢才看得到岩壁上的紋路。","今天坑口的風很涼，下去記得多帶一份吃的。"],
	"chacha":["今天這批葉子炒得有點急，香氣跑了一些。我記下來了，下回慢半拍。","茶單我又重抄了一遍。字要寫得讓收貨的人一眼看懂。","山上起霧的時候，我就不催茶。你也別催自己。"],
	"xinghe":["今天有一盤苗長得特別慢。我沒有換掉它，只多寫了一張標籤。","水圳的水聲變了一點，大概是上游下過雨。我記在手記裡了。","你那邊的樹苗還好嗎？長歪了也沒關係，告訴我它歪向哪一邊。"],
	"mianmian":["奶糖牛今天吃得很慢，我就陪牠慢慢嚼。你吃過了嗎？","雲朵羊的毛又厚了一點。摸的時候順著毛，牠會把頭靠過來。","我把飼料槽擦過了。牠們不會說謝謝，可是會多看我一眼。"],
	"achao":["今天的浪腳短，船板晾得快。你出門前看過風向了嗎？","繩子我又重編了一段。舊的沒壞，只是我想記得手怎麼動。","船不急著下水。先讓它在岸上多聽幾天潮聲。"],
	"nuannuan":["今天的泉水比昨天燙一點，我多兌了半桶涼的。你的手冷不冷？","薑我切得厚，煮久一點才出味。等的時候可以先坐。","有客人問泡腳池什麼時候開。我說，等我修好一個角。"],
	"luoluo":["啊，你、你好。今天的信我數了三遍，一封都沒少。","出貨箱的蓋子我順手擦過了。這樣貨單放進去不會沾到露水。","我走路的時候會背門牌。背錯了也沒關係，再走一次就記得了。"],
	"lingpopo":["今天的風從渡口來，鈴聲比昨天低半個音。你聽得出來嗎？","鈴舌我磨得慢。磨快了聲音會急，掛在樹上跟別的鈴合不來。","樹上的鈴我每天數一遍。不是怕少，是想跟它們打聲招呼。"],
	"diandian":["今天池面的顏色，我調了三次都不對……後來發現少的是一點灰。","你走過來的時候，草先彎了一下。我把那一下畫下來了。","這一頁我只畫了一半。另一半……等它自己想好要長什麼樣子。"],
}

## 四階事件：原創情節，承接各居民既有的四段委託故事。
const EVENTS:={
	"aru":[
		{"title":"刨花裡的名字","lines":["阿榆把一小塊刨平的木片遞給你，上面用鉛筆寫著你的名字。","「工具架上每個人都有一格。你的這格，我先替你留著。」"]},
		{"title":"師父的鉛筆線","lines":["長椅底下還看得到師父畫的鉛筆線，歪歪的。","「我以前想把它磨掉。後來發現，照著歪的線鋸，坐起來反而剛好。」","他把鉛筆削好，放回你手邊。"]},
		{"title":"借你一把鑿子","lines":["阿榆從工具箱最底層拿出一把舊鑿子，握柄磨得發亮。","「這把我從不借人。不是怕弄壞，是怕別人不知道它該慢慢用。」","「你知道。所以借你。」"]},
		{"title":"長椅的右邊","lines":["傍晚的渡口，阿榆坐在長椅右邊，左邊空著。","「師父的位置我坐了好多年。今天換你坐坐看，風景不太一樣。」","你們沒再多說什麼，一起把茶喝完。"]},
	],
	"milu":[
		{"title":"多盛的一碗","lines":["米露把湯勺遞過來，才發現自己盛了兩碗。","「啊，這碗本來是我的……算了，你先喝，我再盛。」","結果她又忘了盛自己那碗。"]},
		{"title":"頁角的油漬","lines":["米露翻開舊食譜，頁角有一圈油漬。","「這是我第一次把湯煮焦那天留下的。我一直沒擦，想記得那個味道不要再來一次。」","她笑著把那一頁折了個角。"]},
		{"title":"交給你試味道","lines":["米露把鍋鏟塞進你手裡，自己退到一旁。","「鹽放多少，你決定。我想知道別人的手煮出來是什麼樣子。」","她嚐了一口，認真地點頭：「這個我要記下來。」"]},
		{"title":"坐下來吃完的一餐","lines":["這一回，米露沒有站在灶邊。她拉了張椅子，坐在你對面。","「我今天要把這碗吃完才起來。你幫我看著。」","碗見底的時候，她自己先笑了。"]},
	],
	"xiaoli":[
		{"title":"貨單邊的小記號","lines":["小栗在貨單邊緣畫了一個小小的記號，像一片葉子。","「這是你的記號。以後看到它，我就知道這批貨是誰送來的。」"]},
		{"title":"多留的一包種子","lines":["收攤前，小栗從櫃台下拿出一包沒標價的種子。","「這包不賣。我每季都留一包，給我覺得會好好種的人。」","「種出來以後，記得來跟我說是什麼味道。」"]},
		{"title":"畫在紙上的店","lines":["小栗攤開一張紙，上面畫著一間小店，門口有兩階樓梯。","「我想要一間不用每天收的攤子。這件事我還沒跟別人說過。」","「門要開在哪一邊，你幫我想想。」"]},
		{"title":"招牌上的第二個名字","lines":["小栗重新描好的招牌角落，多了一行小字。","「我把常來幫忙的人都寫上去了。你的名字在第二個，第一個是我自己。」","「等固定的小店開張，這塊招牌要掛在門口。」"]},
	],
	"bobo":[
		{"title":"口袋裡的小石頭","lines":["波波從口袋掏出一顆圓圓的小石頭放到你手心。","「這顆不值錢，可是握起來剛好。送你，下坑的時候帶著。」"]},
		{"title":"祖父的記號","lines":["波波指著礦車把手內側的一道刻痕。","「祖父每修一次就刻一道。我數過，一共十一道。」","「第十二道是上回我們一起修的那次。」"]},
		{"title":"不外借的那一格","lines":["展示架最上層有一格用布蓋著。波波掀開布，裡面是一塊普通的灰石頭。","「這是我自己敲下來的第一塊。它什麼礦都不是，我卻最喜歡。」","「別人問我都說還沒整理好。只有你看過。」"]},
		{"title":"一起猜的那一塊","lines":["波波把一塊新敲下來的怪石放在兩人中間。","「你猜它像什麼？我先不說。」","你們各猜了一個，誰也沒猜中，卻都笑了很久。"]},
	],
	# 茶茶與星禾的事件皆為原創人物情節，不陳述貓空、蘭陽或田尾的地方史實。
	"chacha":[
		{"title":"多擺的一只杯子","lines":["茶茶在茶桌上多擺了一只杯子，杯沿有一小塊釉沒上勻。","「這只我本來要收起來。你來了，就先用它。」"]},
		{"title":"沒寫進茶單的那一批","lines":["茶茶從櫃子深處拿出一小包沒貼標籤的茶。","「這批火候過了頭，我沒寫進茶單。」","「可是我自己常喝它。苦一點，倒也醒神。」"]},
		{"title":"歪了一點的竹簾","lines":["茶亭的竹簾掛歪了。茶茶盯著看了很久，最後沒有去扶。","「以前我會花整個下午調它。」","「今天有客人。簾子歪著，也能喝茶。」"]},
		{"title":"照實寫的茶單","lines":["茶茶把茶單翻到最後一頁，上面多了一行：今日茶況，照實寫。","「好的壞的我都寫上去，來的人自己挑。」","她替你倒了一杯。這一回，她沒有先嚐過才遞給你。"]},
	],
	"xinghe":[
		{"title":"寫著你名字的標籤","lines":["星禾在一盤苗旁插上新標籤，上面是你的名字和今天的日期。","「這樣我就記得，這一盤是從哪一天開始的。」"]},
		{"title":"手記裡的空白頁","lines":["星禾翻開手記，有一頁只畫了格子。","「這頁留給我還看不懂的事。比如同一盤苗，為什麼有的先醒。」","「你要是看到了什麼，也可以寫在這裡。」"]},
		{"title":"沒發芽的那一格","lines":["育苗盤的角落有一格一直空著。","「這顆種子沒發芽，我一直沒補。我想記得，不是每一顆都會長。」","「這件事我沒跟別人說過，怕他們以為我偷懶。」"]},
		{"title":"下一輪的標籤","lines":["星禾遞給你一疊空白標籤和一枝削好的筆。","「下一輪的標籤，換你寫。字醜也沒關係，苗認得就好。」","你寫下第一張，她把它插在水邊最前面的那一盤。"]},
	],
	# 棉棉的事件承接規劃書「安置怕雷的小羊」，皆為原創情節，不涉及地方史實。
	"mianmian":[
		{"title":"口袋裡的一把飼料","lines":["棉棉從圍裙口袋抓出一小把飼料，放進你手心。","「先讓牠們聞聞你。手攤平，不要急。」","雲朵羊嗅了嗅，輕輕吃掉了。"]},
		{"title":"怕雷的那一隻","lines":["遠處的雲有點低。雲朵羊把頭埋在飼料槽後面，不肯出來。","「牠怕打雷。不是膽小，是耳朵比我們好。」","棉棉沒有去拉牠，只在旁邊坐下，慢慢摺手上的布。"]},
		{"title":"鋪在角落的舊布","lines":["棉棉在棚子最裡面的角落鋪了一塊洗軟的舊布。","「我以前都跟牠說不要怕。後來想想，我自己也怕過，誰說不要怕都沒有用。」","「所以現在我只說：這裡有個角落，你可以來。」"]},
		{"title":"雨停以前","lines":["外頭下著雨。雲朵羊窩在那塊舊布上，眼睛半閉。","棉棉把布的另一角遞給你：「幫我拉著。等雨停，我們再一起摺。」","雨停的時候，牠先站了起來，回頭看了你們一眼。"]},
	],
	# 阿潮的事件承接規劃書「找回失散航線的路標」，皆為原創情節，不涉及地方史實。
	"achao":[
		{"title":"多打的一個結","lines":["阿潮把一截繩子遞給你，上面已經打好一個結。","「拉這一頭會鬆，拉那一頭會緊。你先記住，哪一頭是回家的。」"]},
		{"title":"漂回來的路標","lines":["碼頭邊靠著一塊褪色的木牌，字只剩一半。","「以前出航的人靠這些路標認方向。浪大那年漂走了幾塊，這塊是自己漂回來的。」","他沒有重漆，只把它擦乾，立在船邊。"]},
		{"title":"沒畫完的航線圖","lines":["阿潮攤開一張航線圖，有幾段只用鉛筆點了虛線。","「這幾段我沒走過，不敢畫實。別人問，我都說圖還在晾。」","「你要是到過那些地方，回來告訴我水是什麼顏色。」"]},
		{"title":"立回去的那一塊","lines":["阿潮把修好的路標扛到碼頭盡頭，要你扶著另一邊。","「字我沒補全。缺的那一半，留給下一個找到路的人寫。」","路標立穩的時候，船身輕輕碰了一下碼頭，像是應了一聲。"]},
	],
	# 暖暖的事件承接規劃書「修好多年未開的泡腳池」，皆為原創情節，不陳述礁溪的地方史實。
	"nuannuan":[
		{"title":"多燒的一壺水","lines":["暖暖把一只冒著熱氣的杯子推到你面前。","「水我總是多燒一壺。有人來就剛好，沒人來我就自己喝兩杯。」"]},
		{"title":"蓋著木板的池子","lines":["溪邊有一方蓋著木板的小池，板縫裡長了草。","「這是泡腳池，很久沒開了。不是壞得多厲害，是我一直覺得要全部修好才能掀開。」","她蹲下來，只拔了板縫裡的一根草。"]},
		{"title":"先修一個角","lines":["暖暖掀開了一塊木板，底下的石頭還是溫的。","「我想先修一個角就好。夠一個人坐，也算開了。」","「這話我沒跟客人說過，怕他們等。你不催我，所以告訴你。」"]},
		{"title":"兩雙鞋","lines":["池邊擺著兩雙脫下來的鞋。水只放了一半，剛好淹過腳踝。","「還有三個角沒修。可是今天的水是熱的。」","你們坐到水涼了才起來。她說，下回再修下一個角。"]},
	],
	# 洛洛的事件承接規劃書「第一次親自送出無地址的信」，皆為原創情節，不涉及地方史實。
	"luoluo":[
		{"title":"放在箱邊的信","lines":["洛洛把一封信放在出貨箱邊，退了兩步才開口。","「這、這封是你的。我本來想放了就走……可是你剛好在。」"]},
		{"title":"郵包最底下的那一封","lines":["洛洛的郵包底下壓著一封邊角磨軟的信，信封上沒有地址。","「這封我帶了很久。上面只寫了『給還記得渡口的人』。」","「我不知道該交給誰，就一直帶著走。」"]},
		{"title":"在門口練習的那句話","lines":["洛洛站在一扇門前，嘴裡小聲唸著什麼，唸完又退回來。","「我每次都把信放在門口就走。親手交給人的那句話，我練了很多遍還是說不好。」","「這件事我沒跟別人說過。你先聽我說一遍，好不好？」"]},
		{"title":"親手交出去的信","lines":["洛洛拿著那封沒有地址的信，在渡口等到一位正要上船的人。","「這封信……我想，是給還記得這裡的人。請、請收下。」","對方笑著收下了。洛洛回頭看你，郵包輕了一點，肩膀也鬆了一點。"]},
	],
	# 鈴婆婆的事件承接規劃書「為風鈴樹修好最後一枚鈴」，皆為原創情節，不陳述地方史實。
	"lingpopo":[
		{"title":"借你聽一聲","lines":["鈴婆婆從圍兜裡拿出一枚小鈴，在你耳邊輕輕晃了一下。","「每個來島上的人，我都讓他先聽一聲。記住這個音，以後迷路了就往它走。」"]},
		{"title":"不響的那一枚","lines":["樹上有一枚鈴，風再大也不響。鈴婆婆抬頭看了它很久。","「它的鈴舌掉了很多年。我做過好幾個新的，掛上去聲音都不對。」","「不是手藝的事。是我還沒想起來，它原本是什麼聲音。」"]},
		{"title":"抽屜裡的舊鈴舌","lines":["鈴婆婆拉開工具箱最下面的抽屜，裡面是一排大小不一的鈴舌。","「這些都是沒做成的。我沒丟，每一個都離那個聲音近一點。」","「別人只看到樹上少一聲。只有你看過這個抽屜。」"]},
		{"title":"最後一枚鈴","lines":["鈴婆婆把新磨好的鈴舌交到你手上，自己扶著梯子。","「你來掛。我的耳朵記得聲音，手已經構不著那麼高了。」","風過來的時候，整棵樹第一次一起響。她閉著眼睛聽完，說：「對，就是這一聲。」"]},
	],
	# 點點的事件沿用規劃書 N11 的四段標題與台詞，其餘敘述為原創情節，不陳述田尾的地方史實。
	"diandian":[
		{"title":"帽沿底下的顏色","lines":["點點抬頭看了你一會兒，鉛筆在紙上輕輕動了幾下。","「你走得慢一點，我就看見帽沿的影子了。」","「影子也是你的顏色。」"]},
		{"title":"沒畫好的手","lines":["畫本上有好幾頁只畫了手，每一隻都握得緊緊的。","「我總把手畫得太僵。可能因為我忘了，它們也會在不知道做什麼時放鬆。」","她看了看你垂在身邊的手，重新起了一筆。"]},
		{"title":"畫面外的位置","lines":["點點把畫紙攤在草地上，人已經畫到了紙的邊緣。","「我想把每個人都畫進去，紙卻不夠大。這件事我沒跟別人說過，怕他們以為我在挑人。」","「那就再接一張。家也常常是這樣慢慢變大的。」她把膠帶的一頭遞給你。"]},
		{"title":"把空白留給下一位","lines":["接起來的畫上有渡口、茶園、鹽田，還有池邊的你。右下角留著一塊沒上色的地方。","「這裡先不要畫滿。總會有人帶著新的顏色來。」","她在空白旁邊，小小地簽上你們兩個的名字。"]},
	],
}

static func name_of(resident:String) -> String:
	if LOCAL_NAMES.has(resident):return str(LOCAL_NAMES[resident])
	return str(Village.NPCS.get(resident,{}).get("name",resident))

## 候選格中第一個沒有建物、作物或樹的格子；全被佔用時用第一格。
static func free_cell(state:Dictionary,cells:Array) -> Vector2i:
	for cell:Vector2i in cells:
		var tile:="%d,%d"%[cell.x,cell.y]
		var taken:=false
		for layer:String in ["objects","crops","forest"]:
			var found:Variant=state.get(layer)
			if found is Dictionary and found.has(tile):taken=true
		if not taken:return cell
	return cells[0]

## 棉棉目前的站位。
static func ranch_cell(state:Dictionary) -> Vector2i:
	return free_cell(state,RANCH_CELLS)

## 阿潮目前的站位。
static func dock_cell(state:Dictionary) -> Vector2i:
	return free_cell(state,DOCK_CELLS)

## 洛洛目前的站位。
static func post_cell(state:Dictionary) -> Vector2i:
	return free_cell(state,POST_CELLS)

## 鈴婆婆目前的站位。
static func bell_cell(state:Dictionary) -> Vector2i:
	return free_cell(state,BELL_CELLS)

## 居民尚未出現時的說明；已出現回傳空字串。伺服器與介面共用。
static func locked_reason(state:Dictionary,resident:String) -> String:
	if resident=="mianmian" and state.get("picnic",false)!=true:return RANCH_LOCKED
	if resident=="achao" and int(state.get("dock_stage",0))<1:return DOCK_LOCKED
	if resident=="luoluo" and state.get("picnic",false)!=true:return POST_LOCKED
	if resident=="lingpopo" and state.get("picnic",false)!=true:return BELL_LOCKED
	return ""

static func present(state:Dictionary,resident:String) -> bool:
	return locked_reason(state,resident).is_empty()

static func day(now:float) -> int:
	return floori(now/Village.DAY)

## 讀取（不寫入）某位居民的個人紀錄。
static func record(person:Dictionary,resident:String) -> Dictionary:
	var bonds:Variant=person.get("bonds")
	var found:Variant=bonds.get(resident) if bonds is Dictionary else null
	if not found is Dictionary:return {"points":0,"talk_day":-1,"gift_day":-1}
	return {"points":int(found.get("points",0)),"talk_day":int(found.get("talk_day",-1)),"gift_day":int(found.get("gift_day",-1))}

static func story_count(person:Dictionary,resident:String) -> int:
	if STORY_FLAGS.has(resident):
		var done:=0
		for flag:String in STORY_FLAGS[resident]:
			if person.get(flag,false) is bool and person.get(flag,false):done+=1
		return done
	var stories:Variant=person.get("stories")
	if not stories is Dictionary or not Village.QUESTS.has(resident):return 0
	return clampi(int(stories.get(resident,0)),0,Village.QUESTS[resident].size())

static func points(person:Dictionary,resident:String) -> int:
	return mini(LIMIT,int(record(person,resident).points)+STORY_POINTS*story_count(person,resident))

## 0＝尚未認識；1–4 對應 STAGES。
static func stage_for(value:int) -> int:
	var reached:=0
	for threshold:int in THRESHOLDS:
		if value>=threshold:reached+=1
	return reached

static func stage(person:Dictionary,resident:String) -> int:
	return stage_for(points(person,resident))

static func stage_name(index:int) -> String:
	return "尚未認識" if index<=0 else str(STAGES[mini(index,STAGES.size())-1])

static func liked(resident:String,item:String) -> bool:
	return item in LIKES.get(resident,[])

static func giftable(resident:String,item:String) -> bool:
	return LIKES.has(resident) and (item in COMMON_GIFTS or liked(resident,item))

static func gift_items(resident:String) -> Array:
	var result:Array=LIKES.get(resident,[]).duplicate()
	for item:String in COMMON_GIFTS:
		if item not in result:result.append(item)
	return result

## 只給本人看的摘要（Session 另行附在自己的快照上）。
static func view(person:Dictionary,now:float) -> Dictionary:
	var today:=day(now)
	var result:={}
	for resident:String in RESIDENTS:
		var own:=record(person,resident)
		var total:=mini(LIMIT,int(own.points)+STORY_POINTS*story_count(person,resident))
		var reached:=stage_for(total)
		result[resident]={"points":total,"stage":reached,"stage_name":stage_name(reached),
			"next":int(THRESHOLDS[reached]) if reached<THRESHOLDS.size() else LIMIT,
			"talked_today":int(own.talk_day)>=today,"gifted_today":int(own.gift_day)>=today}
	return result

static func stage_up_text(resident:String,before:int,after:int) -> String:
	if after<=before or after<=0:return ""
	return "你和%s的關係來到「%s」，手帳可重看〈%s〉。"%[name_of(resident),stage_name(after),EVENTS[resident][after-1].title]

## 聊天與送禮。呼叫前 World 已確認玩家站在該居民身旁。
static func apply(person:Dictionary,inv:Dictionary,action:String,parts:PackedStringArray,now:float,names:Dictionary) -> Dictionary:
	var resident:=str(parts[0]) if parts.size()>0 else ""
	if resident not in RESIDENTS:return _fail("這位居民還沒有關係故事。")
	if person.has("bonds") and not person.bonds is Dictionary:return _fail("關係紀錄有誤。")
	var npc_name:=name_of(resident)
	var today:=day(now)
	var before:=stage(person,resident)
	var own:=record(person,resident)
	var message:=""
	if action=="resident_talk":
		if parts.size()!=1:return _fail("請重新和居民交談。")
		if int(own.talk_day)>=today:return _fail("今天已經和%s聊過了，明天再來坐坐。"%npc_name)
		own.talk_day=today
		own.points=mini(LIMIT,int(own.points)+TALK_POINTS)
		var lines:Array=TALK_LINES[resident]
		message="%s：%s"%[npc_name,lines[posmod(today,lines.size())]]
	elif action=="resident_gift":
		if parts.size()!=2:return _fail("請重新選擇禮物。")
		var item:=str(parts[1])
		if not giftable(resident,item):return _fail("%s說這個你先留著用。"%npc_name)
		if int(inv.get(item,0))<1:return _fail("背包裡沒有%s。"%str(names.get(item,"這樣東西")))
		inv[item]=int(inv[item])-1
		var item_name:=str(names.get(item,item))
		if int(own.gift_day)>=today:
			message="%s收下了%s。今天的心意已經記過，好感明天再算。"%[npc_name,item_name]
		else:
			own.gift_day=today
			var favourite:=liked(resident,item)
			own.points=mini(LIMIT,int(own.points)+(LIKED_POINTS if favourite else GIFT_POINTS))
			message=("%s很喜歡%s，小心地收了起來。" if favourite else "%s收下了%s，向你道謝。")%[npc_name,item_name]
	else:
		return _fail("請重新和居民交談。")
	var bonds:Dictionary=person.get("bonds",{})
	bonds[resident]=own
	person.bonds=bonds
	var raised:=stage_up_text(resident,before,stage(person,resident))
	return {"ok":true,"message":message if raised.is_empty() else message+" "+raised}

## 存檔檢查：欄位可省略；存在時只能有已知居民與三個整數欄位，日期不可超過
## 目前世界日。通過時把 JSON 讀回的浮點數正規化為整數。
static func valid(bonds:Variant,now:float) -> bool:
	if not bonds is Dictionary or bonds.size()>RESIDENTS.size():return false
	var today:=day(now)
	for resident in bonds:
		if not resident is String or resident not in RESIDENTS:return false
		var own:Variant=bonds[resident]
		if not own is Dictionary or own.size()!=3:return false
		if not _whole(own.get("points"),0,LIMIT):return false
		for field in ["talk_day","gift_day"]:
			if not _whole(own.get(field),-1,today):return false
		if int(own.points)==0 and int(own.talk_day)<0 and int(own.gift_day)<0:return false
		for field in ["points","talk_day","gift_day"]:own[field]=int(own[field])
	return true

static func _whole(value:Variant,minimum:int,maximum:int) -> bool:
	if not (value is int or value is float) or not is_finite(float(value)):return false
	return floorf(float(value))==float(value) and float(value)>=minimum and float(value)<=maximum

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}
