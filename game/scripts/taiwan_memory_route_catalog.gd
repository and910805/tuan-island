extends RefCounted
## Taiwan memory-route catalog: two short, playable "memory visits" staged at
## the real in-game Yingge (鶯歌合作陶坊) and Maokong (貓空合作茶園) work sites.
##
## STATUS: standalone story content + pure rules. NOT wired into world.gd,
## save_schema.gd, session or any UI. No IO, no wall clock, no random, and no
## state mutation: every function reads `state` and returns new data.
##
## Playable shape: each visit is three ordered steps. A step fires only when the
## caller reports the player standing on that step's real work-site cell (taken
## live from TeaCeramics.SITES, so it cannot drift from the map) and carrying the
## items that site actually produces. The caller owns the per-token progress
## integer (see PROPOSED_SAVE_SHAPE); this file never stores it.
##
## Honesty rules (enforced by validate_data):
## - Every scene is an ORIGINAL, FICTIONAL memory of the game's own characters
##   (陶師、茶茶). Every displayed line is prefixed with FICTION_LABEL.
## - Scene text may only restate game rules that exist in repo code
##   (`game_rule` facts, each pointing at a script+symbol).
## - Real-world place facts are listed separately. `repo_doc_cited` means
##   docs/tea-ceramics-geography.md lists an external source (recorded there as
##   checked 2026-11-14); THIS task did not re-fetch it, and it is not shown as
##   an in-game citation, so those facts stay `needs_in_game_citation`.
##   `needs_external_source` facts have no source in the repo at all and must
##   not appear in scene text (FORBIDDEN_TERMS guards the obvious ones).
## - No rewards: visits grant no items/coins, so the economy is untouched.

const TeaCeramics=preload("res://scripts/tea_ceramics.gd")

const CATALOG_VERSION:=1
const INSPECTED_ON:="2026-11-14"
const FICTION_LABEL:="【虛構回憶】"
const FICTION_NOTICE:="以下是遊戲原創角色的想像回憶，不是真實人物、工坊或歷史紀錄。"
const KNOWN_REGIONS:=["maokong","yingge"]
const PREREQ_KINDS:={
	"visited":{"params":["region"]},
	"tea_flag":{"params":["key"],"allowed":["intro","potter","potter_story","tea_discussed","reused","comparison_complete"]},
}
const FACT_STATUSES:=["game_rule","repo_doc_cited","needs_external_source"]
## Scene text must not slip unsourced history/product claims in.
const FORBIDDEN_TERMS:=["鐵觀音","包種","清代","清朝","日治","日據","百年","世紀","老街","博物館","第一","最早","正宗","傳統工法"]

## Proposed (NOT implemented) per-token storage. Needs a save_schema bump,
## migration and validation owned by the save owner.
const PROPOSED_SAVE_SHAPE:={"memory_route":{"players":{"<token>":{"<visit_id>":0}}}}

const VISITS:={
	"yingge_first_mend":{
		"title":"鶯歌・缺口的第一只罐",
		"region":"yingge",
		"place_label":"鶯歌合作陶坊（遊戲虛構工坊，位於新北市鶯歌的縮尺示意地圖）",
		"route_note":"經臺北轉乘到新北鶯歌；交通以遊戲合併轉乘呈現。",
		"route_hook":{"script":"res://scripts/travel_ui.gd","symbol":"經臺北轉乘到新北鶯歌"},
		"local_activity":"陶罐修補：待修陶罐＋陶土入製罐窯，修好可再用三次。",
		"prerequisites":[{"kind":"visited","region":"yingge"},{"kind":"tea_flag","key":"potter_story"}],
		"steps":[
			{"id":"potter_desk","action":"tea_potter_story","site_title":"陶師的工作桌",
			"requires_any":[],
			"text":"陶師把一只缺了口的罐子推到你面前：「我學做罐的頭一年，燒出來的罐子總在口沿裂。師姐說，先別丟，去備土台摸摸土。」"},
			{"id":"clay_table","action":"tea_clay","site_title":"備土台",
			"requires_any":["clay"],
			"text":"你握著工坊備好的陶土。回憶裡的陶師也握著一樣的土，被提醒：「土是工坊備的，不從街上或古蹟去挖。」這句話她一直記到現在。"},
			{"id":"kiln_mend","action":"tea_repair","site_title":"製罐窯",
			"requires_any":["tea_spent_jar","tea_jar"],
			"text":"窯口的熱氣裡，陶師想起那只補過的罐：只用一份陶土補上缺口，又陪人走了三趟。「罐子缺口，表示它真的走過路。」"},
		],
		"facts":[
			{"claim":"鶯歌合作陶坊與陶師為既有原創設定；陶師的師姐為本回憶新增的原創角色。","status":"game_rule","used_in_text":true,
			"evidence":{"script":"res://docs/tea-ceramics-geography.md","symbol":"茶茶、陶師、小栗的合作訂單、工坊位置"}},
			{"claim":"陶土由合作工坊供應，不在街道或古蹟採挖。","status":"game_rule","used_in_text":true,
			"evidence":{"script":"res://scripts/travel_ui.gd","symbol":"陶土由工坊供應，不在街道或古蹟採挖"}},
			{"claim":"修補需要一只待修陶罐與一份陶土。","status":"game_rule","used_in_text":true,
			"evidence":{"script":"res://scripts/tea_ceramics.gd","symbol":"修補需要一只待修陶罐與一份陶土"}},
			{"claim":"修好的陶罐可再用三次。","status":"game_rule","used_in_text":true,
			"evidence":{"script":"res://scripts/tea_ceramics.gd","symbol":"陶罐已修好，可再用三次"}},
			{"claim":"鶯歌位於新北市，地圖概略位置 121.35E／24.95N 僅為縮尺示意。","status":"repo_doc_cited","used_in_text":false,
			"evidence":{"script":"res://docs/tea-ceramics-geography.md","symbol":"鶯歌合作陶坊定位於新北市鶯歌"},
			"flag":"needs_in_game_citation：文件列有來源但本任務未重新查核，遊戲內亦未附來源。"},
			{"claim":"鶯歌有製陶、原料與運輸的發展歷史。","status":"repo_doc_cited","used_in_text":false,
			"evidence":{"script":"res://docs/tea-ceramics-geography.md","symbol":"國立臺北大學海山學研究中心記載鶯歌製陶"},
			"flag":"needs_in_game_citation：場景文字刻意不陳述；若要寫入需加遊戲內來源頁。"},
			{"claim":"鶯歌陶業的具體年代、人物、窯種或工法。","status":"needs_external_source","used_in_text":false,
			"flag":"需外部查核來源；repo 內無任何已查核資料，不得寫入場景。"},
		],
	},
	"maokong_roast_wait":{
		"title":"貓空・烘焙台邊的等待",
		"region":"maokong",
		"place_label":"貓空合作茶園（遊戲虛構茶園，位於臺北市文山區貓空的縮尺示意地圖）",
		"route_note":"經臺北轉乘到文山貓空；交通以遊戲合併轉乘呈現。",
		"route_hook":{"script":"res://scripts/travel_ui.gd","symbol":"經臺北轉乘到文山貓空"},
		"local_activity":"採茶與烘焙：茶叢每次採兩份並需冷卻，烘焙台淺焙8秒、深焙12秒。",
		"prerequisites":[{"kind":"visited","region":"maokong"},{"kind":"tea_flag","key":"tea_discussed"}],
		"steps":[
			{"id":"host_table","action":"tea_discuss","site_title":"茶茶的合作茶園",
			"requires_any":[],
			"text":"茶茶翻開一本舊茶單：「小時候我最沒耐心，葉子還沒長好就想再採。阿公說，去茶叢那邊看看就懂了。」"},
			{"id":"tea_bush","action":"tea_pick","site_title":"茶叢",
			"requires_any":["tea_leaf","tea_light","tea_deep"],
			"text":"你手裡有剛採的茶葉。回憶裡的小茶茶站在同一排茶叢前，看著採過的枝頭慢慢冒出新葉。「每叢採兩份，就讓它歇一會兒。」"},
			{"id":"roaster_wait","action":"tea_take","site_title":"茶葉烘焙台",
			"requires_any":["tea_light","tea_deep"],
			"text":"烘焙台前，茶茶笑說她現在會算時間了：淺焙等一下，深焙多等一會兒。「等，也是茶的一部分。這批要走多遠，就決定要等多久。」"},
		],
		"facts":[
			{"claim":"貓空合作茶園與茶茶為既有原創設定；茶茶的阿公為本回憶新增的原創角色。","status":"game_rule","used_in_text":true,
			"evidence":{"script":"res://docs/tea-ceramics-geography.md","symbol":"茶茶、陶師、小栗的合作訂單、工坊位置"}},
			{"claim":"每叢茶一次採得兩份茶葉，之後需冷卻才能再採。","status":"game_rule","used_in_text":true,
			"evidence":{"script":"res://scripts/tea_ceramics.gd","symbol":"採得兩份茶葉"}},
			{"claim":"淺焙8秒、深焙12秒（遊戲簡化，非製茶教學）。","status":"game_rule","used_in_text":true,
			"evidence":{"script":"res://scripts/tea_ceramics.gd","symbol":"ROAST_SECONDS:={\"light\":8.0,\"deep\":12.0}"}},
			{"claim":"貓空位於臺北市文山區，地圖概略位置 121.59E／24.97N 僅為縮尺示意。","status":"repo_doc_cited","used_in_text":false,
			"evidence":{"script":"res://docs/tea-ceramics-geography.md","symbol":"貓空合作茶園定位於臺北市文山區貓空"},
			"flag":"needs_in_game_citation：文件列有來源但本任務未重新查核，遊戲內亦未附來源。"},
			{"claim":"貓空有茶山與製茶環境。","status":"repo_doc_cited","used_in_text":false,
			"evidence":{"script":"res://docs/tea-ceramics-geography.md","symbol":"臺北市政府農業主題網介紹貓空的茶山與製茶環境"},
			"flag":"needs_in_game_citation：場景文字只描述遊戲茶叢規則，不作產地陳述。"},
			{"claim":"貓空茶種、品名（如特定烏龍品項）、栽培或烘焙工法與歷史。","status":"needs_external_source","used_in_text":false,
			"flag":"需外部查核來源；repo 內無已查核資料，不得寫入場景。"},
		],
	},
}

# ----------------------------------------------------------------- access

static func catalog() -> Dictionary:
	return {"visits":VISITS}

static func visit(visit_id:String) -> Dictionary:
	return VISITS.get(visit_id,{}).duplicate(true)

## Real cells for a step, read live from TeaCeramics.SITES.
static func site_cells(action:String) -> Array:
	var site:Variant=TeaCeramics.SITES.get(action)
	if not site is Array or site.size()<2:return []
	return site[1].duplicate() if site[1] is Array else [site[1]]

static func site_region(action:String) -> String:
	var site:Variant=TeaCeramics.SITES.get(action)
	return str(site[0]) if site is Array and not site.is_empty() else ""

## Every displayed line carries the fiction label.
static func display_text(visit_id:String,index:int) -> String:
	var steps:Array=VISITS.get(visit_id,{}).get("steps",[])
	if index<0 or index>=steps.size():return ""
	return FICTION_LABEL+str(steps[index].text)

static func intro_text(visit_id:String) -> String:
	var v:Dictionary=VISITS.get(visit_id,{})
	if v.is_empty():return ""
	return "%s%s\n%s\n%s"%[FICTION_LABEL,v.title,FICTION_NOTICE,v.place_label]

# --------------------------------------------------------- prerequisites

static func prereq_met(state:Dictionary,token:String,prereq:Dictionary) -> bool:
	var person:Variant=state.get("players",{}).get(token)
	if not person is Dictionary:return false
	match str(prereq.get("kind","")):
		"visited":
			var book:Variant=person.get("travel_book")
			return book is Dictionary and book.get("visited") is Dictionary and book.visited.get(str(prereq.region),false)==true
		"tea_flag":
			var tea:Variant=state.get("tea_ceramics")
			if not tea is Dictionary or not tea.get("players") is Dictionary:return false
			return TeaCeramics.own_record(state,token).get(str(prereq.key),false)==true
	return false

static func visit_available(state:Dictionary,token:String,visit_id:String) -> bool:
	if not VISITS.has(visit_id):return false
	for prereq:Dictionary in VISITS[visit_id].prerequisites:
		if not prereq_met(state,token,prereq):return false
	return true

static func available_visits(state:Dictionary,token:String) -> Array:
	var result:=[]
	for vid in VISITS:
		if visit_available(state,token,vid):result.append(vid)
	return result

# ------------------------------------------------------------- playable

## Attempt the next step. `progress` = steps already seen (caller-owned).
## Returns {ok, message, progress, complete}. Never mutates `state`.
static func try_step(state:Dictionary,token:String,visit_id:String,region:String,cell:Vector2i,progress:int) -> Dictionary:
	if not VISITS.has(visit_id):return _result(false,"沒有這段回憶。",progress,false)
	var steps:Array=VISITS[visit_id].steps
	if progress<0 or progress>steps.size():return _result(false,"回憶進度不正確。",progress,false)
	if progress==steps.size():return _result(false,"這段回憶已看完，可從手帳重看。",progress,true)
	if not visit_available(state,token,visit_id):return _result(false,"先完成這裡的合作工作，再來聽這段回憶。",progress,false)
	var step:Dictionary=steps[progress]
	if region!=str(VISITS[visit_id].region) or not site_cells(step.action).has(cell):
		return _result(false,"到「%s」旁邊再回想。"%step.site_title,progress,false)
	var inventory:Variant=state.players[token].get("inventory")
	if not step.requires_any.is_empty():
		var held:=false
		for item in step.requires_any:
			if inventory is Dictionary and int(inventory.get(item,0))>0:held=true
		if not held:return _result(false,"帶著在這裡做出的東西，回憶才接得上。",progress,false)
	var next:=progress+1
	return _result(true,display_text(visit_id,progress),next,next==steps.size())

static func _result(success:bool,message:String,progress:int,complete:bool) -> Dictionary:
	return {"ok":success,"message":message,"progress":progress,"complete":complete}

# ------------------------------------------------------------- validation

static func validate() -> Array:
	return validate_data(catalog())

static func validate_data(data:Dictionary) -> Array:
	var errors:=[]
	var visits:Variant=data.get("visits")
	if not visits is Dictionary:return ["visits section missing"]
	if visits.size()!=2:errors.append("expected 2 visits, got %d"%visits.size())
	var regions_seen:={}
	var step_ids:={}
	for vid in visits:
		var v:Variant=visits[vid]
		if not v is Dictionary:
			errors.append("%s: visit must be dictionary"%vid)
			continue
		for field in ["title","region","place_label","route_note","local_activity"]:
			if str(v.get(field,"")).strip_edges().is_empty():errors.append("%s: %s required"%[vid,field])
		var region:=str(v.get("region",""))
		if region not in KNOWN_REGIONS:errors.append("%s: unknown region"%vid)
		regions_seen[region]=true
		if not str(v.get("place_label","")).contains("虛構"):errors.append("%s: place_label must say the site is fictional"%vid)
		if not str(v.get("route_note","")).contains("合併轉乘"):errors.append("%s: route_note must label compressed transit"%vid)
		if not _hook_ok(v.get("route_hook")):errors.append("%s: route_hook needs script+symbol"%vid)
		var prereqs:Variant=v.get("prerequisites")
		if not prereqs is Array or prereqs.is_empty():errors.append("%s: prerequisites required"%vid)
		else:
			for p in prereqs:
				var problem:=_prereq_problem(p)
				if not problem.is_empty():errors.append("%s: %s"%[vid,problem])
			if not prereqs.any(func(p):return p is Dictionary and p.get("kind")=="visited" and p.get("region")==region):
				errors.append("%s: must require visiting %s"%[vid,region])
		var steps:Variant=v.get("steps")
		if not steps is Array or steps.size()<3:
			errors.append("%s: needs at least 3 steps"%vid)
		else:
			var item_linked:=false
			for step in steps:
				if not step is Dictionary:
					errors.append("%s: step must be dictionary"%vid)
					continue
				var label:="%s/%s"%[vid,step.get("id","")]
				var sid:=str(step.get("id",""))
				if sid.is_empty() or step_ids.has(label):errors.append("%s: missing or duplicate step id"%label)
				step_ids[label]=true
				var action:=str(step.get("action",""))
				if site_region(action)!=region:errors.append("%s: action %s is not a %s work site"%[label,action,region])
				if str(step.get("site_title","")).is_empty():errors.append("%s: site_title required"%label)
				if not step.get("requires_any") is Array:errors.append("%s: requires_any must be array"%label)
				elif not step.requires_any.is_empty():item_linked=true
				var text:=str(step.get("text",""))
				if text.strip_edges().is_empty():errors.append("%s: text required"%label)
				for term in FORBIDDEN_TERMS:
					if text.contains(term):errors.append("%s: text contains unsourced claim term %s"%[label,term])
				var year:=RegEx.create_from_string("[0-9０-９]{3,4}\\s*年")
				if year.search(text)!=null:errors.append("%s: text contains a year claim"%label)
			if not item_linked:errors.append("%s: no step is linked to an existing item"%vid)
		var facts:Variant=v.get("facts")
		if not facts is Array or facts.is_empty():errors.append("%s: facts required"%vid)
		else:
			var needs_external:=false
			for f in facts:
				if not f is Dictionary or str(f.get("claim","")).is_empty():
					errors.append("%s: fact needs claim"%vid)
					continue
				var status:=str(f.get("status",""))
				if status not in FACT_STATUSES:errors.append("%s: bad fact status"%vid)
				if status!="needs_external_source" and not _hook_ok(f.get("evidence")):errors.append("%s: fact '%s' needs evidence hook"%[vid,f.claim])
				if status=="repo_doc_cited" and not (f.get("evidence") is Dictionary and str(f.evidence.get("script","")).begins_with("res://docs/")):errors.append("%s: repo_doc_cited must point at docs"%vid)
				if status!="game_rule":
					if f.get("used_in_text",true)!=false:errors.append("%s: only game_rule facts may be used in scene text"%vid)
					if str(f.get("flag","")).is_empty():errors.append("%s: non-game fact must be flagged"%vid)
				if status=="needs_external_source":needs_external=true
			if not needs_external:errors.append("%s: list at least one claim needing external sourcing"%vid)
	for region in KNOWN_REGIONS:
		if not regions_seen.has(region):errors.append("no visit staged in %s"%region)
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
	return ""
