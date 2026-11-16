extends RefCounted
## T066「一起做的事」第一批：關係事件的目標玩法。
##
## 內容設定集 N01–N12 為每位居民的四階事件各寫了一項「行動」與「成果」。這一批
## 把其中十七項能用現有物品與站位完成的行動接到好感四階上：好感到了那一階，
## 就能在居民身邊做那件事（交材料、在等價的選項裡選一個、依圖示或任意順序完成
## 三個步驟）。完成後手帳記下一件紀念。
##
## 與設定集的差距（實作選擇）：
## - 紀念只是手帳上的一行字，沒有對應的圖樣、配方、家具或功能。
## - 沒有硬木、銅錠、竹材物品，改用木板、銅接頭、纖維；數量照設定集或略減。
## - 完成不加好感、不給鈴幣與物品；不做的話好感與既有事件照常。
## - 其餘行動（拍照、種植紀錄、找紙角、布置客房等）尚未接入。
##
## 第二批（共 28 項）：再接入 11 項，其中 6 項有「前提」（needs，見 NEEDS）——
## 讀既有的世界紀錄（自己放的小床、燒過溫室玻璃、市集結算過一輪、風鈴接力辦過、
## 認識三位居民、當天沒下雨），不新增存檔欄位；其餘 5 項只用材料或等價選項。
## 小栗第一階使用本人的作物販售與當季購種順序；棉棉第一階使用本人的首次餵食時間。選項文字（紀念牌、店名、信上的一句話、椅子）為實作補寫。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數。紀錄只寫本人的
## player.bond_goals={居民:{"階數":"選項 id 或空字串"}}（第一次完成才寫入），
## 舊存檔不需遷移。台詞取自設定集，皆為遊戲原創情節，不陳述地方史實。
const Bond=preload("res://scripts/resident_bond.gd")
const Weather=preload("res://scripts/weather.gd")

const ACTION:="resident_goal"
const ROUTE_ACTION:="achao_route_mark"
const ROUTE_KEY:="achao_route_marks"
const ROUTE_MASK:=7
const ROUTE_SIGNS:={
	"board":{"bit":1,"name":"渡口公告板","hint":"廣場中央，小栗的攤子西側"},
	"ferry":{"bit":2,"name":"渡口轉乘牌","hint":"從廣場沿路往東，到交通船轉乘處"},
	"river":{"bit":4,"name":"河岸釣魚會告示牌","hint":"沿河走到河灣橋南岸"},
}
const SKETCH_ACTION:="sketch_crop"
const SKETCH_KEY:="crop_sketches"
const SKETCH_TARGET:=3
const SKETCH_ANIMALS:={"chicken":"糯米雞","cow":"奶糖牛","sheep":"雲朵羊"}
const APRON_ACTION:="milu_apron"
const APRON_KEY:="milu_apron"
const RECORD_KEY:="bond_goals"
## 步驟一律三個；每個步驟只做一次。
const STEP_COUNT:=3
const CROP_TRADE_KEY:="first_crop_trade"
const CROP_SOLD:=1
const SEED_BOUGHT:=2
const SHARED_MEAL_EVENT:="shared_meal"
const CHICKEN_FED_KEY:="first_chicken_feed_at"
const CHICKEN_APPROACH_SECONDS:=5.0

## 鍵為階數 1–4（對應 Bond.STAGES）。欄位：
## title 設定集標題；task 要做的事；items 要交的物品；options 等價選項
## （id、label，可帶各自要交的 items）；steps 三個步驟的名稱；order 有指定順序時
## 的步驟索引（沒有這個鍵就是任意順序）；quote 完成時的兩句台詞；keepsake 紀念。
const GOALS:={
	"aru":{
		1:{"title":"有點歪的第一塊板","task":"在家園放一張自己的小床，再交給阿榆 10 根木材。",
			"items":{"wood":10},"needs":["own_bed"],
			"quote":["這塊板有點歪？很好，我們就知道它是哪一塊了。","先讓你今晚有個落腳處，筆直的事明天再說。"],"keepsake":"有點歪的第一塊板"},
		2:{"title":"長椅少了一隻腳","task":"檢查舊長椅的三處接點，再交給阿榆 4 塊木板。接點先看哪一處都可以。",
			"items":{"plank":4},"steps":["左邊的椅腳","椅背的橫木","右邊的椅腳"],
			"quote":["師父總坐左邊，說右邊要留給還沒回來的人。","我修了好幾次，總覺得空著的那邊也得修一修。"],"keepsake":"師父長椅的鉛筆圖樣"},
	},
	"milu":{
		1:{"title":"忘記吃飯的人","task":"替米露端一碗蘿蔔湯來。",
			"items":{"soup":1},
			"quote":["湯我記得加鹽了，麵包也翻面了，還有什麼忘了？","喔，是我自己還沒吃。你要不要一起？"],"keepsake":"米露的廚房便條"},
		3:{"title":"不是同一道湯","task":"帶兩碗湯來辦一場小試吃。蘿蔔湯或胡蘿蔔濃湯都可以。",
			"options":[{"id":"soup","label":"蘿蔔湯","items":{"soup":2}},{"id":"carrot_soup","label":"胡蘿蔔濃湯","items":{"carrot_soup":2}}],
			"quote":["味道和以前不同，卻有人喝完還想再添。","原來食譜最後一行，不一定得寫得一模一樣。"],"keepsake":"試吃會的空碗"},
		4:{"title":"記得替自己留一碗","task":"親手把至少四份料理擺上渡口共餐桌，再找米露回報。一個人也能完成。",
			"needs":["shared_meal"],
			"quote":["今天這一碗，我先盛給自己。","剩下的位置都空著，你們隨時可以來。"],"keepsake":"米露的共餐食譜"},
	},
	"bobo":{
		1:{"title":"口袋裡的小山","task":"交給波波 8 塊石材，看他把石頭排成一座小島。",
			"items":{"stone":8},
			"quote":["這顆像你的帽子，這顆像一隻正在裝睡的雞。","不是所有石頭都要送進爐子裡啦。"],"keepsake":"排成小島的石頭"},
		2:{"title":"動不了的礦車","task":"交 2 個銅接頭和 2 塊木板，再替礦車選一個停下來修的位置。三個位置都可以修。",
			"items":{"copper_joint":2,"plank":2},
			"options":[{"id":"entrance","label":"坑口的平地"},{"id":"siding","label":"岔道的側線"},{"id":"shed","label":"工具棚旁"}],
			"quote":["祖父說，會停下來的車才算修好了。","所以我們先修煞車，再想它能跑多快。"],"keepsake":"礦車的舊煞車片"},
		4:{"title":"最後一趟空車","task":"陪波波把空礦車推到展覽的位置，再替紀念牌選一句話。三句都可以。",
			"options":[{"id":"home","label":"不用載滿也能回家"},{"id":"rest","label":"辛苦了，慢慢停"},{"id":"name","label":"只刻祖父的名字"}],
			"quote":["不用載滿也能回家。","這句話我想刻在車上，比金屬還結實。"],"keepsake":"紀念牌的拓印"},
	},
	"chacha":{
		2:{"title":"漏下來的一束光","task":"檢查茶亭遮簾的三處，再交 8 份纖維和 2 塊布料。先看哪一處都可以。",
			"items":{"fiber":8,"cotton_cloth":2},"steps":["靠山的那一幅","中間的那一幅","靠路的那一幅"],
			"quote":["這裡少一片竹，光線每天都落在不同位置。","我還沒決定，它算不算一個缺點。"],"keepsake":"換下來的舊竹片"},
		3:{"title":"一場沒有流程的茶會","task":"替茶會排三個話題的順序。怎麼排都可以，沒有比較好的答案。",
			"steps":["今年的茶","山上的天氣","最近學會的事"],
			"quote":["茶涼了，可是大家還在說話。","也許茶會不一定要在最後一口喝完時結束。"],"keepsake":"沒照流程走的茶會筆記"},
	},
	"achao":{
		1:{"title":"打不開的繩結","task":"照阿潮畫的圖示鬆開三段繩：先鬆船尾，再鬆中段，最後鬆船頭。不限時間，順序不對可以重來。",
			"steps":["船頭那一段","中段","船尾那一段"],"order":[2,1,0],
			"quote":["拉得更用力，不一定會更快。","先看看是哪一端在等你鬆手。"],"keepsake":"鬆開的舊繩結"},
		2:{"title":"褪色的航線","task":"走訪渡口公告板、轉乘牌和河岸釣魚會告示牌，各記下一處方向，再回來找阿潮。",
			"needs":["route_marks"],
			"quote":["這張圖上的空白，不是沒有地方。","是還沒有人替我們畫回來。"],"keepsake":"阿潮的手繪群島地圖"},
	},
	"mianmian":{
		1:{"title":"先讓牠聞聞","task":"親手餵糯米雞一份飼料，等牠自己靠近，再回來找棉棉。",
			"needs":["chicken_fed"],
			"quote":["牠不是不喜歡你，只是還在認識你的鞋子。","我們等一下，牠自己會走過來。"],"keepsake":"糯米雞的偏好筆記"},
		3:{"title":"一個不太完美的玩具","task":"交 3 塊布料和 4 份纖維，再選玩具的樣子。兩種牠都會喜歡。",
			"items":{"cotton_cloth":3,"fiber":4},
			"options":[{"id":"ball","label":"布球"},{"id":"doll","label":"布偶"}],
			"quote":["縫線有一點歪，可是牠抱得很緊。","我想牠在意的，可能不是縫線。"],"keepsake":"縫線有點歪的玩具"},
		4:{"title":"自己走出屋簷","task":"挑一個渡口沒下雨的日子，陪棉棉看小羊自己跨出屋簷。",
			"needs":["fair_weather"],
			"quote":["我們沒有把牠拉出來。","所以這一步，完完整整是牠自己的。"],"keepsake":"棉棉的照料手札"},
	},
	"xinghe":{
		3:{"title":"不必把冬天趕走","task":"自己燒過溫室玻璃之後，交 2 片溫室玻璃和 2 個銅接頭，幫星禾搭一座小溫室。哪個季節來都可以。",
			"items":{"glass":2,"copper_joint":2},"needs":["glass_crafted"],
			"quote":["溫室不是讓冬天消失。","是替想慢慢長大的孩子，多留一個選擇。"],"keepsake":"小溫室的銅框邊料"},
		2:{"title":"空花圃的圖紙","task":"替四格花圃選兩種花，各帶 2 朵來。",
			"options":[
				{"id":"bluebell_orange","label":"鈴蘭藍花與蜜橙花","items":{"bluebell":2,"orange_blossom":2}},
				{"id":"bluebell_chime","label":"鈴蘭藍花與風鈴香草","items":{"bluebell":2,"chime_herb":2}},
				{"id":"orange_chime","label":"蜜橙花與風鈴香草","items":{"orange_blossom":2,"chime_herb":2}}],
			"quote":["圖紙上每一格都有名字，只有這裡還空著。","這格留給意料之外長出來的東西。"],"keepsake":"留了一格空白的花圃圖紙"},
	},
	"lingpopo":{
		2:{"title":"分不清的節拍","task":"照鈴婆婆畫的圖案排三枚鈴：△、○、□。只看圖案就好，不用聽音高；排錯可以重來。",
			"steps":["○ 圓鈴","△ 角鈴","□ 方鈴"],"order":[1,0,2],
			"quote":["你照圖案排就好，我來聽。","每個人都有自己好用的耳朵，眼睛有時候也算。"],"keepsake":"畫著三個圖案的紙片"},
		3:{"title":"最後一枚鈴","task":"交 2 個銅接頭、2 片溫室玻璃，再帶一道家常菜。哪一道都可以。",
			"items":{"copper_joint":2,"glass":2},
			"options":[{"id":"soup","label":"蘿蔔湯","items":{"soup":1}},{"id":"carrot_soup","label":"胡蘿蔔濃湯","items":{"carrot_soup":1}},
				{"id":"salad","label":"沙拉","items":{"salad":1}},{"id":"baked_potato","label":"烤馬鈴薯","items":{"baked_potato":1}}],
			"quote":["這枚鈴，我想留一點你的顏色。","等我老得記不得名字，還認得這個顏色。"],"keepsake":"留著你的顏色的鈴"},
		4:{"title":"不用等風來","task":"島上辦完一次風鈴接力之後，來陪鈴婆婆親手敲一下鈴。當時不在場的人也可以。",
			"needs":["festival_done"],
			"quote":["你看，沒有風也能響。","有時候，我們自己伸手就好了。"],"keepsake":"親手敲響的那一聲"},
	},
	"xiaoli":{
		1:{"title":"今天先賣一點點","task":"在種子攤或出貨箱賣出一份作物，再找小栗買一包當季種子。",
			"needs":["crop_sold","seed_after_sale"],
			"quote":["不用一次把背包賣空。","留一點給晚餐，也留一點給明天的計畫。"],"keepsake":"小栗的第一筆交易"},
		2:{"title":"輪子停在哪裡","task":"交 12 根木材和 2 塊布料，再替攤車選一個停下來的地方。三個地方都可以。",
			"items":{"wood":12,"cotton_cloth":2},
			"options":[{"id":"tree","label":"風鈴樹下"},{"id":"dock","label":"渡口路邊"},{"id":"plaza","label":"廣場西側"}],
			"quote":["我每次說再找個地方，其實是還不敢停下來。","你覺得這裡，會有人記得來嗎？"],"keepsake":"攤車的木輪擋"},
		3:{"title":"第一位回頭客","task":"在廣場的市集攤位開張、結算過一輪之後，來告訴小栗客人說了什麼。",
			"needs":["market_round"],
			"quote":["他說上次那罐果醬很好吃。","原來人會因為一小罐甜甜的東西，記得一條路。"],"keepsake":"回頭客留下的空果醬罐"},
		4:{"title":"明天也在這裡","task":"交 2 塊木板，替小栗的固定小店掛上招牌。店名可以先不取。",
			"items":{"plank":2},
			"options":[{"id":"none","label":"先不取店名"},{"id":"chestnut","label":"小栗的種子舖"},{"id":"tomorrow","label":"明天也在"}],
			"quote":["明天不用問我會停在哪裡了。","我就在這裡，等你帶新的收成來。"],"keepsake":"招牌的試寫木片"},
	},
	"luoluo":{
		2:{"title":"沒有地址的信","task":"先認識洛洛以外的三位居民，再回來和洛洛一起問問，那片壓乾的葉子是哪棵樹的。",
			"needs":["known_three"],
			"quote":["信上沒有地址，可是有一片壓乾的葉子。","說不定收信的人，記得那棵樹。"],"keepsake":"壓乾的葉子"},
		3:{"title":"想說卻沒送出的話","task":"洛洛有一段話想告訴收信的人。陪他選一種方式，兩種都一樣好。",
			"options":[{"id":"aloud","label":"陪他親口念出來"},{"id":"letter","label":"陪他把信交給對方讀"}],
			"quote":["我可以不用當著大家的面念嗎？","你說可以，那我想我還是願意走過去。"],"keepsake":"摺了又攤開的信稿"},
		4:{"title":"第一封寫給自己的信","task":"陪洛洛寫一封給以後的自己的信。要不要寫下一句話都可以。",
			"options":[{"id":"blank","label":"先留白"},{"id":"stay","label":"希望那時候還住在這裡"},{"id":"thanks","label":"謝謝現在的自己"}],
			"quote":["今天沒有誰等著收這封信。","可是以後的我，應該會很高興。"],"keepsake":"寫給以後的信封"},
	},
	"diandian":{
		1:{"title":"帽沿底下的顏色","task":"在渡口記下三種不同的動物或作物。靠近後從照料或農田面板畫速寫，不必捕捉或採收。",
			"needs":["crop_sketches"],
			"quote":["你走得慢一點，我就看見帽沿的影子了。","影子也是你的顏色。"],"keepsake":"點點的菜園貼紙"},
		2:{"title":"沒畫好的手","task":"在池邊陪點點坐一會兒，選一個姿勢讓她參考。哪一個都可以。",
			"options":[{"id":"knees","label":"手放在膝上"},{"id":"grass","label":"手撐著草地"},{"id":"cup","label":"捧著一只杯子"}],
			"quote":["我總把手畫得太僵。","可能因為我忘了，它們也會在不知道做什麼時放鬆。"],"keepsake":"畫著放鬆的手的速寫"},
	},
	"nuannuan":{
		1:{"title":"一直沒亮的門牌","task":"幫暖暖清理門口，交 8 塊石材和 8 根木材。",
			"items":{"stone":8,"wood":8},
			"quote":["我每天都擦門牌，只是很久沒有把燈打開。","今天開一下吧，亮著比較像有人在家。"],"keepsake":"亮起來的門牌"},
		2:{"title":"池邊的裂縫","task":"標記池邊的三處裂縫，再交 8 份陶土和 12 塊石材。先標哪一處都可以。",
			"items":{"clay":8,"stone":12},"steps":["靠溪的那一道","池角的那一道","台階旁的那一道"],
			"quote":["水漏得很慢，慢得我總說明天再修。","謝謝你把明天，往今天移了一點。"],"keepsake":"標過裂縫的粉筆頭"},
		4:{"title":"第一位住下的主人","task":"在溪畔選一張椅子，陪暖暖坐下來休息。哪一張都可以。",
			"options":[{"id":"stream","label":"靠溪的藤椅"},{"id":"porch","label":"門廊的長椅"},{"id":"pool","label":"池邊的矮凳"}],
			"quote":["今天我不是來檢查熱水的。","我也是來休息的客人。"],"keepsake":"暖暖的房間名牌"},
	},
}

## 第二批：行動的前提「needs」——讀既有的世界紀錄，不新增存檔欄位。
## 每項只在完成當下檢查一次；完成之後紀錄再變（例如開始下一輪風鈴接力）不影響。
##   own_bed       家園 state.objects 有一張 owner 為本人的小床（type "bed"）
##   glass_crafted 本人 player.greenhouse_glass_crafted（自己燒過溫室玻璃）
##   market_round  本人 player.market.report 不是空的（市集攤位結算過一輪）
##   festival_done state.festival 至少完成過一輪（全島紀錄，當時不在場也算）
##   known_three   本人對洛洛以外的居民，至少三位好感已到「認識」
##   fair_weather  今天渡口（家園）沒有下雨
const NEEDS:={
	"route_marks":"記下渡口的三處路標方向",
	"crop_sketches":"記錄三種不同動物或作物的色彩",
	"shared_meal":"親手上一輪共享料理",
	"crop_sold":"在種子攤或出貨箱賣出一份作物",
	"seed_after_sale":"賣出作物後，買一包當季種子",
	"chicken_fed":"親手餵一次糯米雞，等牠靠近",
	"own_bed":"家園裡有一張你放的小床",
	"glass_crafted":"自己燒過一次溫室玻璃",
	"market_round":"你的市集攤位結算過一輪",
	"festival_done":"島上完成過一次風鈴接力",
	"known_three":"認識洛洛以外的三位居民",
	"fair_weather":"今天渡口沒有下雨",
}
const KNOWN_NEEDED:=3

## 第三批：紀念小物——每位居民各有一項行動的紀念做成可以擺在家園的小物（共 12 件）。
## 完成那一項行動時背包多 1 個 "<kind>_kit"，經既有的建造動作 build（extra=<kind>，
## World.BUILD[<kind>]={"name",<kind>_kit:1}）擺到家園；不擋路，拆除退回 kit、可搬移、
## 可放箱子；沒有價目，不能出貨、出售、上市集，也不能交易（World.trade_items() 排除）。
## 只是裝飾，沒有其他功能。第三批之前就完成的行動，回到居民身邊用 CLAIM_ACTION 補領
## 一次。領過的紀錄在本人的 player.bond_keepsakes={kind:true}（可省略；第一次領到才
## 寫入，舊存檔不需遷移）；每件每人只發一次，丟失不補發。
## 其餘 16 項行動的紀念仍只是手帳文字。名稱沿用該行動的 keepsake；blurb 為實作補寫。
const KEEPSAKE_KEY:="bond_keepsakes"
const CLAIM_ACTION:="resident_keepsake"
const ACTIONS:=[ACTION,CLAIM_ACTION]
const KIT_SUFFIX:="_kit"
const MAX_ITEM:=1000000000
const KEEPSAKES:={
	"keepsake_aru":{"resident":"aru","stage":1,"name":"有點歪的第一塊板","blurb":"阿榆留下來的第一塊板，釘在兩根短樁上，看得出有點歪。"},
	"keepsake_milu":{"resident":"milu","stage":3,"name":"試吃會的空碗","blurb":"小試吃會喝完的幾只空碗，洗乾淨疊在小凳上。"},
	"keepsake_bobo":{"resident":"bobo","stage":1,"name":"排成小島的石頭","blurb":"波波把口袋裡的石頭排成一座小島，最上面那顆像一頂帽子。"},
	"keepsake_chacha":{"resident":"chacha","stage":2,"name":"換下來的舊竹片","blurb":"茶亭遮簾換下來的舊竹片，用麻繩串起來掛在小木架上。"},
	"keepsake_achao":{"resident":"achao","stage":1,"name":"鬆開的舊繩結","blurb":"鬆開之後重新盤好的舊纜繩，掛在一根繫船樁上。"},
	"keepsake_mianmian":{"resident":"mianmian","stage":3,"name":"縫線有點歪的玩具","blurb":"和棉棉一起縫的布玩具，縫線有點歪，放在小竹籃裡。"},
	"keepsake_xinghe":{"resident":"xinghe","stage":2,"name":"留了一格空白的花圃圖紙","blurb":"釘在畫板上的四格花圃圖紙，三格畫了花，一格留著空白。"},
	"keepsake_lingpopo":{"resident":"lingpopo","stage":3,"name":"留著你的顏色的鈴","blurb":"鈴婆婆做的一枚小鈴，掛在木架上，鈴身留著一圈你帶來的顏色。只是裝飾，不會響。"},
	"keepsake_xiaoli":{"resident":"xiaoli","stage":4,"name":"招牌的試寫木片","blurb":"小栗掛招牌之前試寫的木片，上面的筆畫還看得出重描過。"},
	"keepsake_luoluo":{"resident":"luoluo","stage":4,"name":"寫給以後的信封","blurb":"洛洛寫給以後的自己的信，收在一只小信箱裡，露出信封的一角。"},
	"keepsake_diandian":{"resident":"diandian","stage":2,"name":"畫著放鬆的手的速寫","blurb":"點點在池邊畫的速寫，夾在小畫架上，畫的是一雙放鬆的手。"},
	"keepsake_nuannuan":{"resident":"nuannuan","stage":1,"name":"亮起來的門牌","blurb":"暖暖門口那塊門牌的複製品，立在短柱上，旁邊點著一盞小燈。只是裝飾，不會照明。"},
}
const KEEPSAKE_ORDER:=["keepsake_aru","keepsake_milu","keepsake_bobo","keepsake_chacha","keepsake_achao","keepsake_mianmian","keepsake_xinghe","keepsake_lingpopo","keepsake_xiaoli","keepsake_luoluo","keepsake_diandian","keepsake_nuannuan"]

## 這一項行動的紀念小物種類（= World.BUILD 的種類）；沒有時為 ""。
static func keepsake_kind(resident:String,stage:int) -> String:
	for kind:String in KEEPSAKE_ORDER:
		if str(KEEPSAKES[kind].resident)==resident and int(KEEPSAKES[kind].stage)==stage:return kind
	return ""

static func keepsake_item(kind:String) -> String:
	return kind+KIT_SUFFIX if KEEPSAKES.has(kind) else ""

static func is_keepsake_kind(kind:String) -> bool:
	return KEEPSAKES.has(kind)

static func is_keepsake_item(item:String) -> bool:
	return item.ends_with(KIT_SUFFIX) and KEEPSAKES.has(item.trim_suffix(KIT_SUFFIX))

## 十二個背包物品 id（KEEPSAKE_ORDER 順序）。
static func keepsake_items() -> Array:
	var out:=[]
	for kind:String in KEEPSAKE_ORDER:out.append(keepsake_item(kind))
	return out

static func keepsake_claimed(person:Dictionary,kind:String) -> bool:
	var found:Variant=person.get(KEEPSAKE_KEY)
	return found is Dictionary and found.get(kind)==true

## 本人摘要用：{"kind","item","name","claimed"}。
static func keepsake_view(person:Dictionary,kind:String) -> Dictionary:
	return {"kind":kind,"item":keepsake_item(kind),"name":str(KEEPSAKES[kind].name),"claimed":keepsake_claimed(person,kind)}

static func _keepsake_blocked(person:Dictionary,inv:Dictionary,kind:String) -> String:
	if person.has(KEEPSAKE_KEY) and not person[KEEPSAKE_KEY] is Dictionary:return "關係紀錄有誤。"
	if int(inv.get(keepsake_item(kind),0))>=MAX_ITEM:return "背包裡的「%s」已經放不下了，先整理背包。"%str(KEEPSAKES[kind].name)
	return ""

static func _keepsake_grant(person:Dictionary,inv:Dictionary,kind:String) -> void:
	var item:=keepsake_item(kind)
	inv[item]=int(inv.get(item,0))+1
	var record:Dictionary=person.get(KEEPSAKE_KEY,{})
	record[kind]=true
	person[KEEPSAKE_KEY]=record

## 補領紀念小物（第三批之前完成的行動）。呼叫前 World 已確認玩家站在該居民身旁、
## 居民已出現。parts＝[居民, 階數]。失敗時 person 與 inv 完全不變。
static func claim(person:Dictionary,inv:Dictionary,parts:PackedStringArray) -> Dictionary:
	if parts.size()!=2 or not str(parts[1]).is_valid_int():return _fail("請重新打開關係事件。")
	var resident:=str(parts[0])
	var stage:=int(parts[1])
	var kind:=keepsake_kind(resident,stage)
	if kind.is_empty():return _fail("這件事的紀念收在手帳裡，沒有可以領的小物。")
	if person.has(RECORD_KEY) and not person[RECORD_KEY] is Dictionary:return _fail("關係紀錄有誤。")
	var entry:Dictionary=GOALS[resident][stage]
	if not done(person,resident).has(stage):return _fail("先和%s一起完成〈%s〉，才有紀念小物。"%[Bond.name_of(resident),entry.title])
	if keepsake_claimed(person,kind):return _fail("「%s」已經領過了。"%str(KEEPSAKES[kind].name))
	var blocked:=_keepsake_blocked(person,inv,kind)
	if not blocked.is_empty():return _fail(blocked)
	_keepsake_grant(person,inv,kind)
	return {"ok":true,"message":"%s把紀念小物「%s」交給你，已放進背包。在家園工坊的「生活」頁選它就能擺到家園。"%[Bond.name_of(resident),str(KEEPSAKES[kind].name)]}

## 存檔檢查（player.bond_keepsakes）：可省略；存在時只能有已知的紀念小物、值為 true，
## 而且對應的行動已經完成。必須在 valid(bond_goals) 之後呼叫。
static func valid_keepsakes(record:Variant,person:Dictionary) -> bool:
	if not record is Dictionary or record.is_empty() or record.size()>KEEPSAKES.size():return false
	for kind in record:
		if not kind is String or not KEEPSAKES.has(kind) or not record[kind] is bool or record[kind]!=true:return false
		if not done(person,str(KEEPSAKES[kind].resident)).has(int(KEEPSAKES[kind].stage)):return false
	return true

## 本人認識（好感至少第一階）的居民數，不含 except。
static func known_count(person:Dictionary,except:String) -> int:
	var count:=0
	for resident:String in Bond.RESIDENTS:
		if resident!=except and Bond.stage(person,resident)>=1:count+=1
	return count

## 某項前提現在是否成立。state 為伺服器的世界狀態；缺欄位一律視為不成立。
static func need_met(id:String,state:Dictionary,token:String) -> bool:
	var players:Variant=state.get("players")
	var found:Variant=players.get(token) if players is Dictionary else null
	var person:Dictionary=found if found is Dictionary else {}
	match id:
		"route_marks":return int(person.get(ROUTE_KEY,0))==ROUTE_MASK
		"crop_sketches":return person.get(SKETCH_KEY,{}).size()>=SKETCH_TARGET
		"shared_meal":return person.get("resident_participation",{}).get(SHARED_MEAL_EVENT,false)==true
		"crop_sold":return int(person.get(CROP_TRADE_KEY,0))>=CROP_SOLD
		"seed_after_sale":return int(person.get(CROP_TRADE_KEY,0))==SEED_BOUGHT
		"chicken_fed":
			var fed:Variant=person.get(CHICKEN_FED_KEY)
			var now:Variant=state.get("time")
			return (fed is float or fed is int) and (now is float or now is int) and float(now)-float(fed)>=CHICKEN_APPROACH_SECONDS
		"own_bed":
			var objects:Variant=state.get("objects")
			if not objects is Dictionary or token.is_empty():return false
			for obj:Variant in objects.values():
				if obj is Dictionary and str(obj.get("type",""))=="bed" and str(obj.get("owner",""))==token:return true
			return false
		"glass_crafted":
			return person.get("greenhouse_glass_crafted") is bool and person.greenhouse_glass_crafted
		"market_round":
			var market:Variant=person.get("market")
			return market is Dictionary and market.get("report") is Dictionary and not market.report.is_empty()
		"festival_done":
			var festival:Variant=state.get("festival")
			if not festival is Dictionary:return false
			return int(festival.get("round",0))-(1 if festival.get("active",false)==true else 0)>=1
		"known_three":
			return known_count(person,"luoluo")>=KNOWN_NEEDED
		"fair_weather":
			var now:Variant=state.get("time")
			if not (now is float or now is int):return false
			return not Weather.rains(Weather.day_index(now),"home")
	return false

## 介面用的說明文字；known_three 附上目前人數。
static func need_label(id:String,state:Dictionary,token:String) -> String:
	if id=="known_three":
		var players:Variant=state.get("players")
		var found:Variant=players.get(token) if players is Dictionary else null
		return "%s（目前 %d 位）"%[str(NEEDS[id]),mini(KNOWN_NEEDED,known_count(found if found is Dictionary else {},"luoluo"))]
	return str(NEEDS.get(id,id))

## 這項行動的前提一覽：[{"id","label","met"}]；沒有前提時為空陣列。
static func needs_view(entry:Dictionary,state:Dictionary,token:String) -> Array:
	var result:=[]
	for id:String in entry.get("needs",[]):
		result.append({"id":id,"label":need_label(id,state,token),"met":need_met(id,state,token)})
	return result

static func has_goal(resident:String,stage:int) -> bool:
	return GOALS.has(resident) and GOALS[resident].has(stage)

static func goal(resident:String,stage:int) -> Dictionary:
	return GOALS[resident][stage] if has_goal(resident,stage) else {}

static func total() -> int:
	var count:=0
	for resident:String in GOALS:count+=GOALS[resident].size()
	return count

static func option(entry:Dictionary,id:String) -> Dictionary:
	for found:Dictionary in entry.get("options",[]):
		if str(found.id)==id:return found
	return {}

## 這項行動（含所選選項）一共要交的物品。
static func cost(entry:Dictionary,option_id:String) -> Dictionary:
	var result:Dictionary=entry.get("items",{}).duplicate()
	for item:String in option(entry,option_id).get("items",{}):
		result[item]=int(result.get(item,0))+int(option(entry,option_id).items[item])
	return result

## 讀取（不寫入）本人完成過的行動：{階數:選項 id}。
static func done(person:Dictionary,resident:String) -> Dictionary:
	var result:={}
	var all:Variant=person.get(RECORD_KEY)
	var own:Variant=all.get(resident) if all is Dictionary else null
	if not own is Dictionary:return result
	for key in own:
		if key is String and key.is_valid_int():result[int(key)]=str(own[key])
	return result

static func valid_sketches(value:Variant,crops:Dictionary) -> bool:
	if not value is Dictionary or value.size()>SKETCH_TARGET:return false
	for kind in value:
		if (not crops.has(kind) and not SKETCH_ANIMALS.has(kind)) or not value[kind] is bool or not value[kind]:return false
	return true

static func apron_unlocked(person:Dictionary) -> bool:
	return done(person,"milu").has(4)

static func completed(person:Dictionary) -> int:
	var count:=0
	for resident:String in GOALS:count+=done(person,resident).size()
	return count

## 步驟字串（例如 "201"）是否為 0..2 各一次。
static func sequence(text:String) -> Array:
	var result:Array=[]
	if text.length()!=STEP_COUNT:return []
	for index in STEP_COUNT:
		var digit:=text.substr(index,1)
		if not digit.is_valid_int() or int(digit)<0 or int(digit)>=STEP_COUNT or int(digit) in result:return []
		result.append(int(digit))
	return result

## 只給本人看的摘要（Session 以 data.resident_goals 附在自己的快照上）：
## {居民:{"階數":{"state":"locked"／"open"／"done","choice":選項 id}}}，只列有行動的階。
## 有前提（needs）而且還沒完成的行動另帶 "needs":[{"id","label","met"}]，
## 需要傳入伺服器的 state 與本人的 token；沒有前提的行動不多這個鍵。
static func view(person:Dictionary,state:Dictionary={},token:String="") -> Dictionary:
	var result:={}
	for resident:String in GOALS:
		var reached:=Bond.stage(person,resident)
		var finished:=done(person,resident)
		var own:={}
		for stage:int in GOALS[resident]:
			if finished.has(stage):own[str(stage)]={"state":"done","choice":str(finished[stage])}
			else:
				own[str(stage)]={"state":"open" if reached>=stage else "locked","choice":""}
				if GOALS[resident][stage].has("needs"):own[str(stage)]["needs"]=needs_view(GOALS[resident][stage],state,token)
			var kind:=keepsake_kind(resident,stage)
			if not kind.is_empty():own[str(stage)]["keepsake"]=keepsake_view(person,kind)
		result[resident]=own
	return result

## 完成一項行動。呼叫前 World 已確認玩家站在該居民身旁、居民已出現。
## parts＝[居民, 階數, 選項 id, 步驟順序]；沒有選項或步驟的行動該欄留空。
## 有前提的行動需要 state 與 token（World 一律傳入）；省略時前提視為不成立。
static func apply(person:Dictionary,inv:Dictionary,parts:PackedStringArray,names:Dictionary,state:Dictionary={},token:String="") -> Dictionary:
	if parts.size()!=4 or not str(parts[1]).is_valid_int():return _fail("請重新打開關係事件。")
	var resident:=str(parts[0])
	var stage:=int(parts[1])
	if not has_goal(resident,stage):return _fail("這一階還沒有可以一起做的事。")
	if person.has(RECORD_KEY) and not person[RECORD_KEY] is Dictionary:return _fail("關係紀錄有誤。")
	var npc_name:=Bond.name_of(resident)
	var entry:Dictionary=GOALS[resident][stage]
	if Bond.stage(person,resident)<stage:return _fail("和%s的關係到「%s」之後，才能一起做這件事。"%[npc_name,Bond.stage_name(stage)])
	if done(person,resident).has(stage):return _fail("〈%s〉已經一起完成了，手帳可以重看。"%entry.title)
	var choice:=str(parts[2])
	if entry.has("options"):
		if option(entry,choice).is_empty():return _fail("請先選一個做法。")
	elif not choice.is_empty():return _fail("請重新打開關係事件。")
	var steps:=str(parts[3])
	if entry.has("steps"):
		var picked:=sequence(steps)
		if picked.is_empty():return _fail("三個步驟都要做過一次。")
		if entry.has("order") and picked!=entry.order:return _fail("順序不太對。%s說不急，再看一次圖示。"%npc_name)
	elif not steps.is_empty():return _fail("請重新打開關係事件。")
	for need:String in entry.get("needs",[]):
		if not need_met(need,state,token):return _fail("還不能一起做這件事：要先「%s」。"%need_label(need,state,token))
	var needed:=cost(entry,choice)
	for item:String in needed:
		if int(inv.get(item,0))<int(needed[item]):
			return _fail("還差%s %d／%d。"%[str(names.get(item,item)),int(inv.get(item,0)),int(needed[item])])
	var kind:=keepsake_kind(resident,stage)
	if not kind.is_empty():
		var blocked:=_keepsake_blocked(person,inv,kind)
		if not blocked.is_empty():return _fail(blocked)
	for item:String in needed:inv[item]=int(inv[item])-int(needed[item])
	var all:Dictionary=person.get(RECORD_KEY,{})
	var own:Dictionary=all.get(resident,{})
	own[str(stage)]=choice
	all[resident]=own
	person[RECORD_KEY]=all
	var message:="%s：「%s」你們一起完成了〈%s〉，手帳記下紀念「%s」。"%[npc_name,entry.quote[0],entry.title,entry.keepsake]
	if not kind.is_empty():
		_keepsake_grant(person,inv,kind)
		message+="紀念小物也放進背包了，在家園工坊的「生活」頁可以擺到家園。"
	return {"ok":true,"message":message}

## 存檔檢查：欄位可省略；存在時只能有已知居民、有行動的階、合法的選項，
## 而且本人的好感必須已經到那一階。
static func valid(goals:Variant,person:Dictionary) -> bool:
	if not goals is Dictionary or goals.is_empty() or goals.size()>GOALS.size():return false
	for resident in goals:
		if not resident is String or not GOALS.has(resident):return false
		var own:Variant=goals[resident]
		if not own is Dictionary or own.is_empty() or own.size()>GOALS[resident].size():return false
		var reached:=Bond.stage(person,resident)
		for key in own:
			if not key is String or key not in ["1","2","3","4"]:return false
			var stage:=int(key)
			if not has_goal(resident,stage) or reached<stage or not own[key] is String:return false
			var entry:Dictionary=GOALS[resident][stage]
			if entry.has("options"):
				if option(entry,str(own[key])).is_empty():return false
			elif not str(own[key]).is_empty():return false
	return true

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}
