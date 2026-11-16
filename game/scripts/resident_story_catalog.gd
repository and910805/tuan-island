extends RefCounted
## T054/T066 resident story catalog: data + validation only.
##
## Six identifiable residents across chapters 1-3, each beat tied to local work
## the player actually performs, the materials they actually obtain, and (where
## available) a regional-history source the player can actually open in game.
##
## STATUS: proposal data. Nothing here is wired into world.gd, save_schema.gd or
## any UI yet. Every `hook` names an existing script + symbol where a later
## integration would attach; no hook has been implemented by this file.
## Pure static rules: no IO, no wall clock, no random, no state mutation.
## Must NOT be preloaded by world.gd/regions.gd/transit.gd without re-checking
## preload cycles (this file preloads chapter_one/tea_ceramics/flower_nursery).
##
## History honesty:
## - Only `lanyang_wanchangchun_1813` is cited in game (history_ui source link).
##   It was recorded as checked on 2026-11-13 in history_story.gd; this task did
##   NOT re-fetch it. Lines marked `sourced_paraphrase` only restate its FACTS.
## - Maokong tea, Yingge ceramics and Tianwei flower sources exist only in the
##   design doc (or as an uncited travel note). They are NOT verified here and
##   NOT player-accessible as citations, so every line touching them is
##   `fictional` personal dialogue and carries an explicit `flag`.

const ChapterOne=preload("res://scripts/chapter_one.gd")
const TeaCeramics=preload("res://scripts/tea_ceramics.gd")
const FlowerNursery=preload("res://scripts/flower_nursery.gd")

const CATALOG_VERSION:=1
const INSPECTED_ON:="2026-11-14"
const CHAPTERS:=[1,2,3]

## Regions this catalog may reference (subset of Regions.ALL / Transit.ROUTE).
const KNOWN_REGIONS:=["home","lanyang","toucheng","ruifang","maokong","yingge","tianwei"]

const LINE_STATUSES:=["fictional","sourced_paraphrase"]
const HISTORY_STATUSES:=["in_game_cited","in_game_uncited","unverified_candidate"]

## Prerequisite kinds -> required params and whether the underlying state is
## shared by the whole world (affects absence/catch-up rules).
const PREREQ_KINDS:={
	"world_flag":{"params":["key"],"scope":"shared","allowed":["board","picnic"]},
	"chapter_one_flag":{"params":["key"],"scope":"shared","allowed":["shipped","watered"]},
	"chapter_one_complete":{"params":[],"scope":"shared"},
	"lanyang_repaired":{"params":[],"scope":"shared"},
	"flower_garden_complete":{"params":[],"scope":"shared"},
	"history_completed":{"params":[],"scope":"personal"},
	"visited":{"params":["region"],"scope":"personal"},
	"tea_flag":{"params":["key"],"scope":"personal","allowed":["intro","potter","reused","tea_discussed","potter_story","comparison_complete"]},
	"flower_phase_at_least":{"params":["phase"],"scope":"personal"},
}

## Shortest in-game route from the ferry to each region, as Transit.CONNECTIONS
## edges (home->lanyang is the home region exit, world.gd travel action).
## Southbound to Tianwei goes Yingge -> Tianwei directly; no Taipei detour.
const ROUTES:={
	"home":{"path":["home"],"gate":[],"gate_hook":{"script":"res://scripts/world.gd","symbol":"add_player"}},
	"lanyang":{"path":["home","lanyang"],"gate":[],"gate_hook":{"script":"res://scripts/world.gd","symbol":"REGIONS.LANYANG"},"note":"從風鈴渡口搭交通船渡海到蘭陽試作田（遊戲合併航程），無劇情門檻。"},
	"toucheng":{"path":["home","toucheng"],"gate":[{"kind":"world_flag","key":"picnic"}],"gate_hook":{"script":"res://scripts/transit.gd","symbol":"route_options"},"note":"Transit.options 需要 picnic。"},
	"ruifang":{"path":["home","toucheng","ruifang"],"gate":[{"kind":"world_flag","key":"picnic"}],"gate_hook":{"script":"res://scripts/transit.gd","symbol":"route_options"}},
	"maokong":{"path":["home","toucheng","ruifang","maokong"],"gate":[{"kind":"chapter_one_complete"}],"gate_hook":{"script":"res://scripts/transit.gd","symbol":"tea_unlocked"},"note":"瑞芳鐵路門經臺北轉乘（遊戲合併轉乘）。"},
	"yingge":{"path":["home","toucheng","ruifang","maokong","yingge"],"gate":[{"kind":"chapter_one_complete"}],"gate_hook":{"script":"res://scripts/transit.gd","symbol":"tea_unlocked"}},
	"tianwei":{"path":["home","toucheng","ruifang","maokong","yingge","tianwei"],"gate":[{"kind":"flower_phase_at_least","phase":"travel"}],"gate_hook":{"script":"res://scripts/flower_nursery.gd","symbol":"route_open"},"note":"鶯歌經縱貫線南下轉地方接駁；花圃接駁點為虛構站名。"},
}

## Regional-history material. `player_access` describes what the player can
## really open; `usable_facts` is the only text a sourced line may restate.
const HISTORY:={
	"lanyang_wanchangchun_1813":{
		"title":"萬長春圳・二結圳文化景觀",
		"publisher":"文化部文化資產局",
		"url":"https://nchdb.boch.gov.tw/assets/overview/culturalLandscape/20061215000003",
		"status":"in_game_cited",
		"player_access":"修好蘭陽水圳後，水圳回憶頁（history_ui）顯示來源連結與免責說明。",
		"hook":{"script":"res://scripts/history_story.gd","symbol":"SOURCE_URL"},
		"checked":"2026-11-13（history_story.gd 既有紀錄；本任務未重新連線查核）",
		"usable_facts":[
			"1813年，長慶源圳與邱吳成圳合併，改用「萬長春」圳號。",
			"兩圳共用水源，合併涉及旱時競水及維修成本。",
			"二結圳也曾是附近居民洗滌、育苗等日常生活的場所。",
		],
	},
	"maokong_tea":{
		"title":"貓空茶園（候選資料）",
		"publisher":"臺北市政府（設計文件所列，未查核）",
		"url":"https://wsdo.gov.taipei/News_Content.aspx?n=C2339A8CEBE6FB41&s=02AD888D921B27B1",
		"status":"unverified_candidate",
		"player_access":"無。只在 docs/taiwan-life-design.json，遊戲內未顯示。",
		"hook":{"script":"res://docs/taiwan-life-design.json","symbol":"貓空茶園"},
		"checked":"未查核",
		"usable_facts":[],
	},
	"yingge_ceramics":{
		"title":"鶯歌陶瓷（候選資料）",
		"publisher":"臺北旅遊網（設計文件所列，未查核；網域與新北行政區不一致，需另找新北或博物館來源）",
		"url":"https://travel.taipei/en/attraction/details/670",
		"status":"unverified_candidate",
		"player_access":"無。只在 docs/taiwan-life-design.json，遊戲內未顯示。",
		"hook":{"script":"res://docs/taiwan-life-design.json","symbol":"鶯歌陶瓷"},
		"checked":"未查核",
		"usable_facts":[],
	},
	"tianwei_flowers":{
		"title":"田尾花卉（候選資料）",
		"publisher":"彰化縣田尾鄉公所（設計文件所列，未查核）",
		"url":"https://www.chcg.gov.tw/TSO/tianwei/01local/local01.aspx",
		"status":"in_game_uncited",
		"player_access":"旅圖說明有「田尾以花卉苗木聞名」一句，但未附來源。",
		"hook":{"script":"res://scripts/travel_ui.gd","symbol":"田尾以花卉苗木聞名"},
		"checked":"未查核",
		"usable_facts":[],
	},
}

## Absence / catch-up rules. No beat is missable and nothing has a real-time
## deadline (design rule: 必要故事不設現實時間期限).
const ABSENCE_RULES:={
	"shared_once_personal_replay":{
		"summary":"共享成果只結算一次；缺席的島民之後見到居民，改聽 catch_up_line，再照常進入個人段落。",
		"requires_catch_up_line":true,
		"settles":"world",
	},
	"personal_progress":{
		"summary":"段落只依本人紀錄（旅行、茶陶、花圃、回憶）開放；他人進度不能代領，也不會讓本人錯過。",
		"requires_catch_up_line":false,
		"settles":"token",
	},
}
## Policy applied to every beat regardless of rule.
const CATCH_UP_POLICY:={
	"missable":false,
	"realtime_deadline":false,
	"stale_beats":"若玩家進度已超過數段，居民只說最新可用段落；較早段落直接列入手帳可重看，不強制補聽。",
	"replay":"已見段落可由手帳重看，重看不改任何狀態、不重複給物品。",
	"rewards":"本目錄所有段落皆無物品或鈴幣獎勵，避免改動既有經濟；若之後加獎勵，背包滿時比照阿蕾「先保管」處理。",
}
## Proposed (NOT implemented) per-token storage for seen beats. Adding it needs
## a save_schema version bump, migration and validation owned elsewhere.
const PROPOSED_SAVE_SHAPE:={"resident_story":{"players":{"<token>":{"seen":["<beat_id>"]}}}}

const RESIDENTS:={
	"xiaoli":{
		"name":"小栗","role":"渡口種子攤・收貨與配送",
		"id_status":"existing_npc",
		"existing_ids":{"npc":"xiaoli","refs":[{"script":"res://scripts/village.gd","symbol":"\"xiaoli\":{\"name\":\"小栗\""}]},
		"home_region":"home",
		"arc":"把手畫收貨簿變成有回程欄的配送網：第一章記誰交貨，第二章記空罐回程，第三章記留種。",
		"beats":[
			{"id":"xiaoli_c1_ledger","chapter":1,"region":"home",
			"prerequisites":[{"kind":"chapter_one_flag","key":"shipped"}],
			"local_work":"在渡口出貨箱寄出自己採收的作物。",
			"materials":[{"item":"radish","source":"渡口農田播種採收","script":"res://scripts/chapter_one.gd","symbol":"先種三株蘿蔔"},{"item":"wheat","source":"渡口農田播種採收","script":"res://scripts/chapter_one.gd","symbol":"一株小麥"}],
			"line":"這本收貨簿的格子是我自己畫的。誰種了什麼、哪天送來，寫下來，下次就知道該向誰訂。",
			"line_status":"fictional","history":"","flag":"",
			"absence":{"rule":"shared_once_personal_replay","catch_up_line":"第一批貨已經有人送來了。簿子上還有空格，等你自己採收的那一批。"},
			"hook":{"script":"res://scripts/community.gd","symbol":"resident_line"}},
			{"id":"xiaoli_c2_return_column","chapter":2,"region":"home",
			"prerequisites":[{"kind":"tea_flag","key":"reused"}],
			"local_work":"把貓空寄來的空陶罐發回並在茶園領回，完成一次回程。",
			"materials":[{"item":"tea_jar","source":"鶯歌製罐窯燒成","script":"res://scripts/tea_ceramics.gd","symbol":"tea_fire_take"},{"item":"tea_returned_jar","source":"陶罐茶售出後的空罐回程","script":"res://scripts/tea_ceramics.gd","symbol":"RETURN_ITEM"}],
			"line":"空罐回來那天，我在簿子上多畫了一欄：「回程」。貨走得出去，也要記得怎麼回來。",
			"line_status":"fictional","history":"","flag":"",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/tea_guidance.gd","symbol":"tea_discuss"}},
			{"id":"xiaoli_c3_seed_shelf","chapter":3,"region":"home",
			"prerequisites":[{"kind":"flower_phase_at_least","phase":"complete"}],
			"local_work":"完成田尾留種與合作訂單，回渡口後攤位開始進花種。",
			"materials":[{"item":"bluebell_seed","source":"田尾留種台／市集；完成後渡口攤位","script":"res://scripts/flower_nursery.gd","symbol":"MARKET_PRICES"},{"item":"chime_herb_seed","source":"同上","script":"res://scripts/flower_nursery.gd","symbol":"MARKET_PRICES"}],
			"line":"攤位多了一格種子架。簿子最後一欄我寫「留下」：每賣一包，就記得還有一包要等明年。",
			"line_status":"fictional","history":"","flag":"",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/flower_nursery.gd","symbol":"HOME_SEED_MESSAGE"}},
		],
	},
	"aru":{
		"name":"阿榆","role":"渡口木作與設備修繕",
		"id_status":"existing_npc",
		"existing_ids":{"npc":"aru","refs":[{"script":"res://scripts/village.gd","symbol":"\"aru\":{\"name\":\"阿榆\""}]},
		"home_region":"home",
		"arc":"從凡事自己修，到把換下來的舊料當成教材，和陶師一樣相信「修好還能再走幾趟」。",
		"beats":[
			{"id":"aru_c1_board_frame","chapter":1,"region":"home",
			"prerequisites":[{"kind":"world_flag","key":"board"}],
			"local_work":"採木採石，捐入公告板公共工程（木材30、石材10）。",
			"materials":[{"item":"wood","source":"斧頭採木","script":"res://scripts/chapter_one.gd","symbol":"用斧頭採木"},{"item":"stone","source":"十字鎬採石","script":"res://scripts/chapter_one.gd","symbol":"十字鎬採石"}],
			"line":"公告板的木框是師父留下的，我只換掉爛掉的兩根。舊的那幾根，紋路還是對得上。",
			"line_status":"fictional","history":"","flag":"",
			"absence":{"rule":"shared_once_personal_replay","catch_up_line":"你不在那天，板子是大家一起釘好的。上頭還留著空位，寫你下回想交什麼貨。"},
			"hook":{"script":"res://scripts/community.gd","symbol":"resident_line"}},
			{"id":"aru_c1_divider_board","chapter":1,"region":"lanyang",
			"prerequisites":[{"kind":"lanyang_repaired"},{"kind":"history_completed"}],
			"local_work":"捐木板、石材、樹脂修好蘭陽水閘，再完成三輪分水回憶。",
			"materials":[{"item":"plank","source":"鋸木台把木材加工成木板","script":"res://scripts/industry.gd","symbol":"\"plank\":{\"station\":\"sawmill\""},{"item":"resin","source":"林務工作站產出","script":"res://scripts/forestry.gd","symbol":"const OUTPUT:="},{"item":"stone","source":"十字鎬採石","script":"res://scripts/lanyang_life.gd","symbol":"\"donations\":{\"plank\":0,\"stone\":0,\"resin\":0}"}],
			"line":"換下來的分水板我沒丟。回憶頁寫著，兩條圳合併以後，旱時怎麼分水、修圳的花費，都得一起商量。這塊板就是那種東西。",
			"line_status":"sourced_paraphrase","history":"lanyang_wanchangchun_1813","paraphrase_of":[1],
			"flag":"分水板與阿榆為原創；只轉述來源的「共用水源、旱時競水、維修成本」。",
			"absence":{"rule":"shared_once_personal_replay","catch_up_line":"水閘早修好了，舊板還在我這。你自己走完一次分水，再來聽我說它的故事。"},
			"hook":{"script":"res://scripts/history_ui.gd","symbol":"Story.AFTER"}},
			{"id":"aru_c2_mending","chapter":2,"region":"home",
			"prerequisites":[{"kind":"visited","region":"yingge"},{"kind":"tea_flag","key":"potter_story"}],
			"local_work":"把待修陶罐帶回鶯歌，向陶師學修補。",
			"materials":[{"item":"tea_spent_jar","source":"陶罐用盡回程次數","script":"res://scripts/tea_ceramics.gd","symbol":"RETURN_ITEM"},{"item":"clay","source":"陶師試作陶土或供土處以石材換","script":"res://scripts/tea_ceramics.gd","symbol":"tea_clay"}],
			"line":"陶師補罐口，我補椅腳。東西壞了先別急著換新，看看它是從哪裡開始累的。",
			"line_status":"fictional","history":"","flag":"",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/community.gd","symbol":"resident_line"}},
		],
	},
	"xinghe":{
		"name":"星禾","role":"蘭陽水圳與育苗・田尾公共花園",
		"id_status":"existing_journal_id",
		"existing_ids":{"journal":"xinghe","refs":[{"script":"res://scripts/life_ui_tasks.gd","symbol":"\"xinghe\""},{"script":"res://scripts/flower_nursery.gd","symbol":"const XINGHE"}]},
		"home_region":"lanyang",
		"arc":"從顧一條水圳到顧下一輪：蘭陽育樹苗、田尾留花種，都是先替以後留一份。",
		"beats":[
			{"id":"xinghe_c1_channel","chapter":1,"region":"lanyang",
			"prerequisites":[{"kind":"lanyang_repaired"}],
			"local_work":"清理三處堵塞、捐料修閘，讓蘭陽水泵提升。",
			"materials":[{"item":"plank","source":"鋸木台","script":"res://scripts/industry.gd","symbol":"\"plank\":{\"station\":\"sawmill\""},{"item":"resin","source":"林務工作站","script":"res://scripts/forestry.gd","symbol":"const OUTPUT:="}],
			"line":"水圳通了。清出來的泥我堆在田埂邊，曬乾了還能墊育苗盤。",
			"line_status":"fictional","history":"","flag":"",
			"absence":{"rule":"shared_once_personal_replay","catch_up_line":"水閘是大家合力修好的。你來得正好，育苗盤還空著一格給你。"},
			"hook":{"script":"res://scripts/lanyang_life.gd","symbol":"nursery"}},
			{"id":"xinghe_c1_wanchangchun","chapter":1,"region":"lanyang",
			"prerequisites":[{"kind":"history_completed"}],
			"local_work":"走完圳頭、岔口、田尾三處觀察，完成三輪分水。",
			"materials":[{"item":"sapling","source":"星禾的育苗盤（蘭陽 SERVICE 格）","script":"res://scripts/lanyang_life.gd","symbol":"nursery"}],
			"line":"回憶頁的資料說，1813年兩條圳合併，改叫萬長春。也提到二結圳曾是附近居民洗滌、育苗的地方。我把育苗盤放在水邊，就是想著那樣的日子。剛才那三輪分水是遊戲裡的練習，不是當年的紀錄。",
			"line_status":"sourced_paraphrase","history":"lanyang_wanchangchun_1813","paraphrase_of":[0,2],
			"flag":"「把育苗盤放在水邊」是星禾的原創動機；年代、圳名與洗滌育苗用途來自來源頁。",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/history_ui.gd","symbol":"Story.SOURCE_URL"}},
			{"id":"xinghe_c3_next_round","chapter":3,"region":"tianwei",
			"prerequisites":[{"kind":"visited","region":"tianwei"},{"kind":"flower_phase_at_least","phase":"complete"}],
			"local_work":"留種、交合作訂單、合力完成公共花園並回報。",
			"materials":[{"item":"bluebell_seed","source":"田尾留種台（一朵成花換一包）","script":"res://scripts/flower_nursery.gd","symbol":"SAVE_SECONDS"},{"item":"orange_blossom_seed","source":"同上","script":"res://scripts/flower_nursery.gd","symbol":"SAVE_SECONDS"}],
			"line":"在蘭陽我育的是樹苗，在這裡阿蕾教你留的是花種。兩邊其實一樣：先替下一輪留一份。",
			"line_status":"fictional","history":"tianwei_flowers",
			"flag":"未查核：不提田尾產業史實；花圃與阿蕾皆為原創。",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/flower_nursery.gd","symbol":"STORY"}},
		],
	},
	"chacha":{
		"name":"茶茶","role":"貓空合作茶園主人",
		"id_status":"proposed_new",
		"existing_ids":{"site":"host","region":"maokong","refs":[{"script":"res://scripts/tea_ceramics_ui.gd","symbol":"\"host\":\"茶茶的合作茶園\""},{"script":"res://scripts/tea_ceramics.gd","symbol":"const TEA_NPC"}]},
		"home_region":"maokong",
		"arc":"從只顧每批品質，到先想「這批茶要走多遠、罐子怎麼回來」。",
		"beats":[
			{"id":"chacha_c2_how_far","chapter":2,"region":"maokong",
			"prerequisites":[{"kind":"visited","region":"maokong"},{"kind":"tea_flag","key":"tea_discussed"}],
			"local_work":"採茶叢、選淺焙或深焙、用陶罐或纖維包裝寄出。",
			"materials":[{"item":"tea_leaf","source":"貓空茶叢（每叢兩份，冷卻後再採）","script":"res://scripts/tea_ceramics.gd","symbol":"tea_pick"},{"item":"tea_light","source":"烘焙台淺焙","script":"res://scripts/tea_ceramics.gd","symbol":"tea_take"},{"item":"fiber","source":"初始背包與林務產出","script":"res://scripts/forestry.gd","symbol":"const OUTPUT:="}],
			"line":"淺焙留香，深焙耐放。我以前只想把每一批做到最好，現在得先問：這批茶要走多遠？",
			"line_status":"fictional","history":"maokong_tea",
			"flag":"未查核：不陳述貓空茶業歷史或品種；烘焙差異只描述遊戲規則（淺焙8秒、深焙12秒）。",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/tea_ceramics.gd","symbol":"tea_discuss"}},
			{"id":"chacha_c2_both_columns","chapter":2,"region":"maokong",
			"prerequisites":[{"kind":"visited","region":"maokong"},{"kind":"tea_flag","key":"comparison_complete"}],
			"local_work":"兩種包裝各送達一批並領回空罐，完成比較。",
			"materials":[{"item":"tea_jar","source":"鶯歌製罐窯","script":"res://scripts/tea_ceramics.gd","symbol":"tea_fire_take"},{"item":"fiber","source":"初始背包與林務產出","script":"res://scripts/world.gd","symbol":"\"fiber\":10"}],
			"line":"纖維包方便，陶罐回得來。我把兩種都寫進茶單，讓收貨的人自己選。",
			"line_status":"fictional","history":"maokong_tea",
			"flag":"未查核：原創人物與茶單，非地方史。",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/tea_guidance.gd","symbol":"tea_discuss"}},
			{"id":"chacha_c3_leave_a_bud","chapter":3,"region":"maokong",
			"prerequisites":[{"kind":"visited","region":"maokong"},{"kind":"flower_phase_at_least","phase":"complete"}],
			"local_work":"完成田尾留種後回訪茶園（茶叢採收冷卻是同一套「留給下一輪」的節奏）。",
			"materials":[{"item":"tea_leaf","source":"貓空茶叢","script":"res://scripts/tea_ceramics.gd","symbol":"tea_pick"}],
			"line":"聽說你在田尾學會留種。茶叢也一樣，採了葉子就讓它歇一會兒，等新葉長出來再來。",
			"line_status":"fictional","history":"maokong_tea",
			"flag":"未查核：只描述遊戲中茶叢冷卻規則，不作農法或歷史主張。",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/tea_guidance.gd","symbol":"hint("}},
		],
	},
	"yingge_potter":{
		"name":"陶師","role":"鶯歌合作陶坊",
		"id_status":"proposed_new",
		"existing_ids":{"site":"potter","region":"yingge","refs":[{"script":"res://scripts/tea_ceramics_ui.gd","symbol":"\"potter\":\"陶師的工作桌\""},{"script":"res://scripts/tea_ceramics.gd","symbol":"const POTTER"}]},
		"home_region":"yingge",
		"arc":"相信罐子缺了口代表它真的走過路；第三章送玩家南下，提醒往田尾不必繞回臺北。",
		"naming_note":"沿用既有顯示名「陶師」；若需個人名需另經使用者同意，避免改動既有台詞。",
		"beats":[
			{"id":"potter_c2_workshop_clay","chapter":2,"region":"yingge",
			"prerequisites":[{"kind":"visited","region":"yingge"},{"kind":"tea_flag","key":"potter"}],
			"local_work":"向陶師領兩份試作陶土；之後在供土處用石材2換陶土1，燒出第一只罐。",
			"materials":[{"item":"clay","source":"陶師試作（2份）與供土處（石材2換1）","script":"res://scripts/tea_ceramics.gd","symbol":"tea_potter"},{"item":"stone","source":"十字鎬採石，供土處交換","script":"res://scripts/tea_ceramics.gd","symbol":"需要兩份石材交換一份陶土"}],
			"line":"陶土工坊備好了，不必到街上或古蹟去挖。拿兩份去，先燒一只能回家的罐。",
			"line_status":"fictional","history":"yingge_ceramics",
			"flag":"未查核：不陳述鶯歌陶業歷史；與旅圖說明「陶土由工坊供應」一致。",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/tea_ceramics.gd","symbol":"tea_potter"}},
			{"id":"potter_c2_chipped_rim","chapter":2,"region":"yingge",
			"prerequisites":[{"kind":"visited","region":"yingge"},{"kind":"tea_flag","key":"potter_story"}],
			"local_work":"把待修陶罐和一份陶土送進製罐窯修補，修好可再用三次。",
			"materials":[{"item":"tea_spent_jar","source":"陶罐回程三次後","script":"res://scripts/tea_ceramics.gd","symbol":"RETURN_ITEM"},{"item":"clay","source":"供土處","script":"res://scripts/tea_ceramics.gd","symbol":"tea_repair"}],
			"line":"罐子回來時缺了口，我反而高興。表示它真的陪人走過路。",
			"line_status":"fictional","history":"yingge_ceramics",
			"flag":"未查核：原創人物感想，非工藝史。",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/tea_ceramics.gd","symbol":"tea_potter_story"}},
			{"id":"potter_c3_southbound","chapter":3,"region":"yingge",
			"prerequisites":[{"kind":"visited","region":"yingge"},{"kind":"flower_phase_at_least","phase":"travel"}],
			"local_work":"收下小栗的花圃介紹信後，經鶯歌南下田尾。",
			"materials":[],
			"line":"要去田尾？從這裡搭縱貫線往南，再轉地方接駁就到了，不必繞回臺北。",
			"line_status":"fictional","history":"",
			"flag":"",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/travel_ui.gd","symbol":"tianwei>yingge"}},
		],
	},
	"alei":{
		"name":"阿蕾","role":"田尾合作花圃花農",
		"id_status":"proposed_new",
		"existing_ids":{"site":"farmer","region":"tianwei","refs":[{"script":"res://scripts/flower_nursery_ui.gd","symbol":"const FARMER_NAME"},{"script":"res://scripts/flower_nursery.gd","symbol":"const FARMER"}]},
		"home_region":"tianwei",
		"arc":"怕把種苗全賣光的花農，教玩家先留種再交貨，最後和大家把公共花園種起來。",
		"beats":[
			{"id":"alei_c3_six_packets","chapter":3,"region":"tianwei",
			"prerequisites":[{"kind":"visited","region":"tianwei"},{"kind":"flower_phase_at_least","phase":"plant"}],
			"local_work":"領三種花各兩包起始種子，在育苗床播種。",
			"materials":[{"item":"bluebell_seed","source":"阿蕾起始種子（各2包）","script":"res://scripts/flower_nursery.gd","symbol":"const STARTER"},{"item":"orange_blossom_seed","source":"同上","script":"res://scripts/flower_nursery.gd","symbol":"const STARTER"},{"item":"chime_herb_seed","source":"同上","script":"res://scripts/flower_nursery.gd","symbol":"const STARTER"}],
			"line":"這六包是上一輪留下來的。花圃規矩只有一條：種下去之前，先想好下一輪。",
			"line_status":"fictional","history":"tianwei_flowers",
			"flag":"未查核：旅圖雖寫田尾以花卉苗木聞名但無來源；阿蕾與花圃為原創。",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/flower_nursery.gd","symbol":"flower_intro"}},
			{"id":"alei_c3_keep_one","chapter":3,"region":"tianwei",
			"prerequisites":[{"kind":"visited","region":"tianwei"},{"kind":"flower_phase_at_least","phase":"ship"}],
			"local_work":"在留種台把三種成花各換一包種子，再準備合作訂單。",
			"materials":[{"item":"bluebell","source":"自己育苗床採收","script":"res://scripts/flower_nursery.gd","symbol":"note_harvest"},{"item":"orange_blossom_seed","source":"留種台","script":"res://scripts/flower_nursery.gd","symbol":"flower_save"}],
			"line":"賣掉的那朵讓我們有飯吃，留下的那包讓明年還有花。兩樣都要。",
			"line_status":"fictional","history":"tianwei_flowers",
			"flag":"未查核：原創台詞，不代表真實花農經驗或產業數據。",
			"absence":{"rule":"personal_progress"},
			"hook":{"script":"res://scripts/flower_nursery.gd","symbol":"flower_save"}},
			{"id":"alei_c3_garden","chapter":3,"region":"tianwei",
			"prerequisites":[{"kind":"visited","region":"tianwei"},{"kind":"flower_garden_complete"}],
			"local_work":"把藍色染料、蜜橙花、風鈴香草分次捐給公共花園。",
			"materials":[{"item":"blue_dye","source":"染色桌（藍花3→染料2）","script":"res://scripts/flower_nursery.gd","symbol":"const DYE"},{"item":"orange_blossom","source":"自己育苗床採收","script":"res://scripts/flower_nursery.gd","symbol":"GARDEN_NEEDS"},{"item":"chime_herb","source":"自己育苗床採收","script":"res://scripts/flower_nursery.gd","symbol":"GARDEN_NEEDS"}],
			"line":"花架上每一朵都是有人分次帶來的。我數過，沒有哪一朵是一個人種完的。",
			"line_status":"fictional","history":"tianwei_flowers",
			"flag":"未查核：原創台詞。",
			"absence":{"rule":"shared_once_personal_replay","catch_up_line":"花園開的那天你不在也沒關係。花架還有位置，下回帶一朵你自己留種種出來的花。"},
			"hook":{"script":"res://scripts/flower_nursery.gd","symbol":"flower_give"}},
		],
	},
}

# ----------------------------------------------------------------- access

static func catalog() -> Dictionary:
	return {"residents":RESIDENTS,"history":HISTORY,"routes":ROUTES,"absence":ABSENCE_RULES}

static func beat(beat_id:String) -> Dictionary:
	for rid in RESIDENTS:
		for entry:Dictionary in RESIDENTS[rid].beats:
			if entry.id==beat_id:
				var result:=entry.duplicate(true)
				result.resident=rid
				return result
	return {}

static func is_shared(entry:Dictionary) -> bool:
	for prereq:Dictionary in entry.get("prerequisites",[]):
		if PREREQ_KINDS.get(prereq.get("kind",""),{}).get("scope","")=="shared":return true
	return false

## Line to show. `took_part` is supplied by the integration (e.g. from the
## proposed seen/contributor record); absent players get the catch-up line.
static func line_for(entry:Dictionary,took_part:bool) -> String:
	var absence:Dictionary=entry.get("absence",{})
	if not took_part and absence.get("rule","")=="shared_once_personal_replay":
		return str(absence.get("catch_up_line",entry.get("line","")))
	return str(entry.get("line",""))

# --------------------------------------------------------- prerequisites

## Reads the real world-state shape through the owning scripts. Read-only.
static func prereq_met(state:Dictionary,token:String,prereq:Dictionary) -> bool:
	var person:Variant=state.get("players",{}).get(token)
	if not person is Dictionary:return false
	match str(prereq.get("kind","")):
		"world_flag":return state.get(str(prereq.key),false)==true
		"chapter_one_flag":
			var chapter:Variant=state.get("chapter_one")
			return chapter is Dictionary and chapter.get(str(prereq.key),false)==true
		"chapter_one_complete":return ChapterOne.phase(state)=="complete"
		"lanyang_repaired":
			var lanyang:Variant=state.get("lanyang_life")
			return lanyang is Dictionary and lanyang.get("repaired",false)==true
		"flower_garden_complete":
			var nursery:Variant=state.get("flower_nursery")
			return nursery is Dictionary and nursery.get("garden") is Dictionary and nursery.garden.get("complete",false)==true
		"history_completed":
			var memory:Variant=state.get("history_memory")
			if not memory is Dictionary or not memory.get("players") is Dictionary:return false
			var record:Variant=memory.players.get(token)
			return record is Dictionary and record.get("completed",false)==true
		"visited":
			var book:Variant=person.get("travel_book")
			return book is Dictionary and book.get("visited") is Dictionary and book.visited.get(str(prereq.region),false)==true
		"tea_flag":
			var tea:Variant=state.get("tea_ceramics")
			if not tea is Dictionary or not tea.get("players") is Dictionary:return false
			return TeaCeramics.own_record(state,token).get(str(prereq.key),false)==true
		"flower_phase_at_least":
			var want:=FlowerNursery.PHASES.find(str(prereq.phase))
			if want<0:return false
			return FlowerNursery.PHASES.find(FlowerNursery.phase(state,token))>=want
	return false

static func beat_available(state:Dictionary,token:String,entry:Dictionary) -> bool:
	for prereq:Dictionary in entry.get("prerequisites",[]):
		if not prereq_met(state,token,prereq):return false
	return true

static func available_beats(state:Dictionary,token:String) -> Array:
	var result:=[]
	for rid in RESIDENTS:
		for entry:Dictionary in RESIDENTS[rid].beats:
			if beat_available(state,token,entry):result.append(entry.id)
	return result

## Latest available beat for one resident (stale-beat policy), or "".
static func latest_beat(state:Dictionary,token:String,resident_id:String) -> String:
	var found:=""
	for entry:Dictionary in RESIDENTS.get(resident_id,{}).get("beats",[]):
		if beat_available(state,token,entry):found=entry.id
	return found

static func participation(state: Dictionary, token: String) -> Dictionary:
	var events: Dictionary = state.get("players",{}).get(token,{}).get("resident_participation",{})
	return {"xiaoli_c1_ledger":events.get("shipment",false),
		"aru_c1_board_frame":events.get("bridge",false),
		"aru_c1_divider_board":events.get("canal",false),
		"xinghe_c1_channel":events.get("canal",false),
		"alei_c3_garden":int(state.get("flower_nursery",{}).get("garden",{}).get("contributors",{}).get(token,0))>0}

static func dialogue(unlocked: Array, resident_id: String, region: String, participated: Dictionary = {}) -> String:
	var line := ""
	for entry: Dictionary in RESIDENTS.get(resident_id,{}).get("beats",[]):
		if entry.region==region and unlocked.has(entry.id):line=line_for(entry,participated.get(entry.id,true))
	return line

# ------------------------------------------------------------- validation

static func validate() -> Array:
	return validate_data(catalog())

## Structural + honesty validation. Returns human-readable errors (empty = ok).
## Cross-checks against World/Transit/Village live in the test, so this stays
## preload-light.
static func validate_data(data:Dictionary) -> Array:
	var errors:=[]
	var residents:Variant=data.get("residents")
	var history:Variant=data.get("history")
	var routes:Variant=data.get("routes")
	var absence:Variant=data.get("absence")
	if not residents is Dictionary or not history is Dictionary or not routes is Dictionary or not absence is Dictionary:
		return ["catalog sections missing"]
	if residents.size()!=6:errors.append("expected 6 residents, got %d"%residents.size())
	for hid in history:
		var h:Dictionary=history[hid]
		if str(h.get("status","")) not in HISTORY_STATUSES:errors.append("history %s: bad status"%hid)
		if str(h.get("url","")).is_empty() or str(h.get("player_access","")).is_empty():errors.append("history %s: url/player_access required"%hid)
		if not h.get("usable_facts") is Array:errors.append("history %s: usable_facts must be array"%hid)
		elif str(h.get("status",""))!="in_game_cited" and not h.usable_facts.is_empty():errors.append("history %s: only in-game cited sources may carry usable facts"%hid)
		if not _hook_ok(h.get("hook")):errors.append("history %s: hook needs script+symbol"%hid)
	for region in routes:
		var route:Dictionary=routes[region]
		if region not in KNOWN_REGIONS:errors.append("route %s: unknown region"%region)
		var path:Variant=route.get("path")
		if not path is Array or path.is_empty() or path[0]!="home" or path[-1]!=region:errors.append("route %s: path must run home..%s"%[region,region])
		for prereq in route.get("gate",[]):
			var problem:=_prereq_problem(prereq)
			if not problem.is_empty():errors.append("route %s gate: %s"%[region,problem])
		if not _hook_ok(route.get("gate_hook")):errors.append("route %s: gate_hook needs script+symbol"%region)
	var seen_ids:={}
	var chapter_cover:={1:{},2:{},3:{}}
	for rid in residents:
		var r:Dictionary=residents[rid]
		for field in ["name","role","id_status","home_region","arc"]:
			if str(r.get(field,"")).is_empty():errors.append("%s: %s required"%[rid,field])
		if str(r.get("id_status","")) not in ["existing_npc","existing_journal_id","proposed_new"]:errors.append("%s: bad id_status"%rid)
		if str(r.get("home_region","")) not in KNOWN_REGIONS:errors.append("%s: unknown home_region"%rid)
		var ids:Variant=r.get("existing_ids")
		if not ids is Dictionary or not ids.get("refs") is Array or ids.refs.is_empty():errors.append("%s: existing_ids.refs required"%rid)
		else:
			for ref in ids.refs:
				if not _hook_ok(ref):errors.append("%s: bad existing_ids ref"%rid)
		var beats:Variant=r.get("beats")
		if not beats is Array or beats.size()<2:
			errors.append("%s: needs at least 2 beats"%rid)
			continue
		var material_count:=0
		for entry in beats:
			if not entry is Dictionary:
				errors.append("%s: beat must be dictionary"%rid)
				continue
			var bid:=str(entry.get("id",""))
			var label:="%s/%s"%[rid,bid]
			if bid.is_empty() or seen_ids.has(bid):errors.append("%s: missing or duplicate beat id"%label)
			seen_ids[bid]=true
			var chapter:Variant=entry.get("chapter")
			if not chapter is int or chapter not in CHAPTERS:errors.append("%s: chapter must be 1..3"%label)
			else:chapter_cover[chapter][rid]=true
			var region:=str(entry.get("region",""))
			if region not in KNOWN_REGIONS:errors.append("%s: unknown region"%label)
			elif not routes.has(region):errors.append("%s: no route documented for %s"%[label,region])
			for field in ["local_work","line"]:
				if str(entry.get(field,"")).strip_edges().is_empty():errors.append("%s: %s required"%[label,field])
			var prereqs:Variant=entry.get("prerequisites")
			if not prereqs is Array or prereqs.is_empty():errors.append("%s: prerequisites required"%label)
			else:
				for prereq in prereqs:
					var problem:=_prereq_problem(prereq)
					if not problem.is_empty():errors.append("%s: %s"%[label,problem])
				# Route honesty: beats away from home/lanyang require a personal visit.
				if region not in ["home","lanyang"] and not prereqs.any(func(p):return p is Dictionary and p.get("kind")=="visited" and p.get("region")==region):
					errors.append("%s: beat in %s must require visiting it"%[label,region])
			var mats:Variant=entry.get("materials")
			if not mats is Array:errors.append("%s: materials must be array"%label)
			else:
				for m in mats:
					if not m is Dictionary or str(m.get("item","")).is_empty() or str(m.get("source","")).is_empty() or not _hook_ok(m):
						errors.append("%s: material needs item/source/script/symbol"%label)
				material_count+=mats.size()
			if not _hook_ok(entry.get("hook")):errors.append("%s: hook needs script+symbol"%label)
			# History honesty.
			var status:=str(entry.get("line_status",""))
			var hid:=str(entry.get("history",""))
			if status not in LINE_STATUSES:errors.append("%s: bad line_status"%label)
			if not hid.is_empty() and not history.has(hid):errors.append("%s: unknown history %s"%[label,hid])
			if status=="sourced_paraphrase":
				if hid.is_empty() or not history.has(hid) or str(history[hid].get("status",""))!="in_game_cited":
					errors.append("%s: sourced_paraphrase needs an in-game cited source"%label)
				else:
					var refs:Variant=entry.get("paraphrase_of")
					if not refs is Array or refs.is_empty():errors.append("%s: paraphrase_of required"%label)
					else:
						for i in refs:
							if not i is int or i<0 or i>=history[hid].usable_facts.size():errors.append("%s: paraphrase_of out of range"%label)
				if str(entry.get("flag","")).is_empty():errors.append("%s: sourced line must flag what is original"%label)
			elif not hid.is_empty() and history.has(hid) and str(history[hid].get("status",""))!="in_game_cited" and str(entry.get("flag","")).is_empty():
				errors.append("%s: unverified history link must be flagged"%label)
			# Absence / catch-up.
			var rule:Variant=entry.get("absence")
			if not rule is Dictionary or not absence.has(str(rule.get("rule",""))):errors.append("%s: absence rule missing/unknown"%label)
			else:
				var shared:=is_shared(entry)
				if shared and rule.rule!="shared_once_personal_replay":errors.append("%s: shared prerequisite needs shared_once_personal_replay"%label)
				if not shared and rule.rule=="shared_once_personal_replay":errors.append("%s: shared_once rule without shared prerequisite"%label)
				if absence[rule.rule].get("requires_catch_up_line",false) and str(rule.get("catch_up_line","")).strip_edges().is_empty():
					errors.append("%s: catch_up_line required"%label)
		if material_count==0:errors.append("%s: no material sources across beats"%rid)
	for chapter in CHAPTERS:
		if chapter_cover[chapter].size()<2:errors.append("chapter %d covered by fewer than 2 residents"%chapter)
	return errors

static func _hook_ok(hook:Variant) -> bool:
	return hook is Dictionary and str(hook.get("script","")).begins_with("res://") and not str(hook.get("symbol","")).is_empty()

static func _prereq_problem(prereq:Variant) -> String:
	if not prereq is Dictionary:return "prerequisite must be dictionary"
	var kind:=str(prereq.get("kind",""))
	if not PREREQ_KINDS.has(kind):return "unknown prerequisite kind '%s'"%kind
	var spec:Dictionary=PREREQ_KINDS[kind]
	if prereq.size()!=1+spec.params.size():return "%s: unexpected params"%kind
	for param in spec.params:
		if str(prereq.get(param,"")).is_empty():return "%s: missing %s"%[kind,param]
	if spec.has("allowed") and str(prereq.key) not in spec.allowed:return "%s: unsupported key %s"%[kind,prereq.key]
	if kind=="visited" and str(prereq.region) not in KNOWN_REGIONS:return "visited: unknown region"
	if kind=="flower_phase_at_least" and str(prereq.phase) not in FlowerNursery.PHASES:return "flower phase unknown"
	return ""
