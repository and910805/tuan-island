extends SceneTree
## T066「一起做的事」regression suite for res://scripts/resident_goals.gd and its
## World, SaveSchema and in-process Session integration: catalog integrity, every
## one of the 28 goals (stage gate, missing items, every option, every step order,
## prerequisites ("needs") and check order, exact inventory deltas, record,
## repeat), World-layer refusals (region, cell, reach, unknown resident, residents
## not yet present, malformed extra), the six needs ids at need_met level and
## through World.act, needs checked only once (undone afterwards), two
## independent players, request-id replay, save/reload, legacy saves, schema
## tampering and snapshot privacy (including other players' needs rows).
##
## REAL ACTIONS (through World.act): every resident_goal request, the
## resident_talk / resident_gift done after a goal, every refusal.
## WRITTEN DIRECTLY INTO STATE (disclosed PRESET): bond points
## (player.bonds[resident]={points,talk_day:-1,gift_day:-1}, never earned by
## talking here), inventory counts, player region/x/y (standing spots, no travel
## action), state.picnic and state.dock_stage (resident presence gates), the
## legacy and tampered save files, and the batch-2 prerequisites:
##   own_bed       state.objects["x,y"]={type:"bed"|"chest",owner:token,items:{}}
##                 at off-map keys (-200-n,-200), and removing such beds again;
##   glass_crafted player.greenhouse_glass_crafted (true/false/1/"true"/erased);
##   market_round  player.market (MarketStall.fresh() with open_day 0 and a
##                 zero-sale day-0 report, fresh() alone, a string) or erased;
##   festival_done state.festival = Festival.fresh() with round/active replaced;
##   known_three   bonds of achao, chacha, diandian at 1 point (or erased);
##   fair_weather  state.time moved FORWARD by whole days (time of day kept) to
##                 the next rainy / non-rainy day of weather.gd's cycle; the save
##                 test also sets state.time once to day 1. This is the only
##                 time change; nothing ticks.
## Every outdoor region shares one weather cycle, so "only home's weather
## matters" is shown with an indoor (never-raining) player region. Nothing
## depends on the real clock or on randomness (temp file names only).
##
## Batch 3 (keepsakes): every keepsake kit and every player.bond_keepsakes entry
## checked after a completion or claim was produced THROUGH World.act
## (resident_goal / resident_keepsake). FIXTURES written directly (disclosed at
## each site): "old completions" (player.bond_goals written with a goal done and
## no bond_keepsakes / no kit), tampered bond_goals / bond_keepsakes values,
## kit counts at MAX_ITEM or MAX_ITEM-1, a kit set to 0 ("lost"), and the
## batch-2 / tampered save files (bond_keepsakes and kits erased or altered).
const World=preload("res://scripts/world.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const Weather=preload("res://scripts/weather.gd")
const Festival=preload("res://scripts/festival.gd")
const MarketStall=preload("res://scripts/market_stall.gd")
## World.gd literals: bond place gate and the generic 3.2-tile reach gate.
const MSG_PLACE:="請走到這位居民身邊。"
const MSG_FAR:="靠近一點，才能和它互動"
## resident_goals.gd literals.
const MSG_REOPEN:="請重新打開關係事件。"
const MSG_NO_GOAL:="這一階還沒有可以一起做的事。"
const MSG_PICK:="請先選一個做法。"
const MSG_STEPS:="三個步驟都要做過一次。"
const PERMS:=["012","021","102","120","201","210"]
const BAD_STEPS:=["","0","01","0123","001","011","000","013","300","0a1","a01","-01","01 "]
const TWELVE:=["achao","aru","bobo","chacha","diandian","lingpopo","luoluo","mianmian","milu","nuannuan","xiaoli","xinghe"]
const ALLOWED_FIELDS:=["title","task","items","options","steps","order","needs","quote","keepsake","layout"]
const ALL_GOALS:=["achao 1","achao 2","achao 3","achao 4","aru 1","aru 2","aru 3","aru 4","bobo 1","bobo 2","bobo 3","bobo 4","chacha 1","chacha 2","chacha 3","chacha 4","diandian 1","diandian 2","diandian 3","diandian 4","lingpopo 1","lingpopo 2","lingpopo 3","lingpopo 4",
	"luoluo 1","luoluo 2","luoluo 3","luoluo 4","mianmian 1","mianmian 2","mianmian 3","mianmian 4","milu 1","milu 2","milu 3","milu 4","nuannuan 1","nuannuan 2","nuannuan 3","nuannuan 4",
	"xiaoli 1","xiaoli 2","xiaoli 3","xiaoli 4","xinghe 1","xinghe 2","xinghe 3","xinghe 4"]
const WANT_NEEDS:={"xinghe 4":["shared_garden"],"achao 4":["achao_photo"],"achao 3":["achao_voyage"],"aru 4":["aru_park_photo"],"aru 3":["aru_rest"],"mianmian 2":["sheep_comfort"],"chacha 4":["tea_chair"],"chacha 1":["tea_setup"],"diandian 4":["public_mural"],"diandian 2":["diandian_seated"],"diandian 3":["painting_invites"],"xinghe 1":["growth_record"],"luoluo 1":["address_delivered"],"nuannuan 1":["inn_entrance"],"nuannuan 2":["inn_cracks"],"nuannuan 3":["guest_room"],"lingpopo 1":["bell_inspected"],"bobo 3":["rest_kit"],"achao 2":["route_marks"],"diandian 1":["crop_sketches"],"milu 2":["recipe_pages"],"milu 4":["shared_meal"],"xiaoli 1":["crop_sold","seed_after_sale"],"mianmian 1":["chicken_fed"],"aru 1":["own_bed"],"mianmian 4":["sheep_step"],"xinghe 3":["glass_crafted"],"lingpopo 4":["festival_done"],
	"xiaoli 2":["xiaoli_first_trade"],"xiaoli 3":["xiaoli_cart_plan","market_round"],"xiaoli 4":["xiaoli_return_guest"],"luoluo 2":["known_three","postcard_clues"],"luoluo 3":["postcard_reported"],"luoluo 4":["memory_shared"],"bobo 4":["bobo_cart_arrived"]}
## N03-4 (protocol 53): bobo 4 needs the story cart to have arrived (literal label copy).
const CART_NEED:="bobo_cart_arrived"
const CART_NEED_TEXT:="在金瓜石把祖父的空礦車推到展覽位"
const CART_FIELD:="bobo_empty_cart_stage"
const CART_KIND:="keepsake_bobo_cart"
const CART_ITEM:="keepsake_bobo_cart_kit"
const CART_NAME:="祖父的礦車"
## Literal copies of resident_goals.gd NEEDS (labels the player reads).
const NEED_TEXT:={
	"tea_chair":"替貓空茶亭放一張其他風格的椅子",
	"shared_garden":"讓三位居民或島民各挑一盆花",
	"achao_photo":"出航後拍一張船上合照",
	"achao_voyage":"修好碼頭燈並完成一趟小船試航",
	"aru_park_photo":"在公共長椅地塊拍下長椅與木燈",
	"aru_rest":"坐下陪阿榆歇一會兒",
	"diandian_seated":"在映星池邊和點點一起坐下",
	"sheep_comfort":"為雲朵羊搭遮雨棚與鋪纖維墊",
	"tea_setup":"在貓空排好茶桌與兩只茶杯",
	"public_mural":"在渡口展出合畫，或在展出中的合畫留下落款",
	"painting_invites":"邀請三位不同的居民入畫",
	"growth_record":"記下同一株作物的幼苗與成熟",
	"address_delivered":"把洛洛的信交給正確的收件人",
	"inn_entrance":"清理旅舍門口",
	"inn_cracks":"到公共泡腳池標記三處裂縫",
	"guest_room":"在家園登記有床、燈和椅子的客房",
	"bell_inspected":"查看風鈴樹與裂開的小鈴",
	"rest_kit":"在第一層休息站做好路標與補給箱",
	"recipe_pages":"找齊三片食譜紙角",
	"route_marks":"記下渡口的三處路標方向",
	"crop_sketches":"記錄三種不同動物或作物的色彩",
	"shared_meal":"親手上一輪共享料理",
	"crop_sold":"在種子攤或出貨箱賣出一份作物",
	"seed_after_sale":"賣出作物後，買一包當季種子",
	"chicken_fed":"親手餵一次糯米雞，等牠靠近",
	"own_bed":"家園裡有一張你放的小床",
	"glass_crafted":"自己燒過一次溫室玻璃",
	"market_round":"你的市集攤位結算過一輪",
	"xiaoli_first_trade":"和小栗完成〈今天先賣一點點〉",
	"xiaoli_cart_plan":"和小栗完成〈輪子停在哪裡〉",
	"xiaoli_return_guest":"和小栗完成〈第一位回頭客〉",
	"festival_done":"島上完成過一次風鈴接力",
	"known_three":"認識洛洛以外的三位居民",
	"postcard_clues":"向已認識的居民詢問線索",
	"postcard_reported":"完成洛洛的〈沒有地址的信〉",
	"memory_shared":"完成洛洛的〈想說卻沒送出的話〉",
	"fair_weather":"今天渡口沒有下雨",
	"sheep_step":"安靜看小羊自己跨出屋簷",
}
## Literal copy of the batch-3 keepsake goals ("resident stage" -> kind).
const KEEPSAKE_GOALS:={"lingpopo 4":"keepsake_lingpopo_memorial","xinghe 4":"keepsake_xinghe_sign","achao 4":"keepsake_achao_oar","aru 4":"keepsake_aru_bird","aru 1":"keepsake_aru","milu 3":"keepsake_milu","bobo 1":"keepsake_bobo","chacha 2":"keepsake_chacha",
	"achao 1":"keepsake_achao","mianmian 3":"keepsake_mianmian","xinghe 2":"keepsake_xinghe","lingpopo 3":"keepsake_lingpopo",
	"xiaoli 4":"keepsake_xiaoli","luoluo 4":"keepsake_luoluo","diandian 2":"keepsake_diandian","nuannuan 1":"keepsake_nuannuan","nuannuan 4":"keepsake_nuannuan_room","bobo 4":CART_KIND}
## resident_goals.gd batch-3 literals.
const MSG_KEEPSAKE_TAIL:="紀念小物也放進背包了，在家園工坊的「生活」頁可以擺到家園。"
const MSG_RECORD_BAD:="關係紀錄有誤。"
const MSG_NO_KEEPSAKE:="這件事的紀念收在手帳裡，沒有可以領的小物。"
## Residents used to satisfy known_three (none of them has a needs goal).
const KNOWN_OTHERS:=["achao","chacha","diandian"]
## Luoluo stage 2 second need: three distinct clue residents in the player's own string array (literal copies).
const CLUES_KEY:="luoluo_postcard_clues"
const CLUES_NEED:="postcard_clues"
const CLUES_TEXT:="向已認識的居民詢問線索（目前 %d／3 位）"
const WATCHER:="goal-watcher-token-5c1a"
const PRIVATE_A:="goal-private-alpha-token-77e2"
const PRIVATE_B:="goal-private-beta-token-0f93"
const SAM:="goal-save-sam-token-41bd"
const KIM:="goal-needs-kim-token-93aa"
var checks:=0
var failures:=0
var serial:=0
var flows:=0
var _cleanup:Array[String]=[]

func expect(value:bool,message:String)->bool:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)
	return value

func finish()->void:
	for file in _cleanup:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("RESIDENT_GOAL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_catalog()
	test_keepsake_catalog()
	for resident:String in Goals.GOALS:
		for stage:int in Goals.GOALS[resident]:
			goal_flow(resident,stage)
	expect(flows==48,"goal_flow ran for all 48 goals (%d)"%flows)
	test_world_rejections()
	test_gates()
	test_need_rules()
	test_crop_sketches()
	test_animal_sketches()
	test_milu_shared_meal()
	test_xiaoli_trade()
	test_chicken_goal()
	test_needs_through_world()
	test_needs_once_and_save()
	test_players_and_replay()
	test_keepsake_claim()
	test_save_reload_and_schema()
	await test_session_snapshot()
	finish()

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String)->String:
	var path:=OS.get_environment("TEMP").path_join("resident-goal-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])
	_cleanup.append(path)
	return path

static func canon(value:Variant)->Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			out[k]=canon(value[k] if value.has(k) else value[StringName(k)])
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(canon(item))
		return list
	if value is float and is_equal_approx(value,roundf(value)) and absf(value)<9.0e15:return int(value)
	if value is StringName:return str(value)
	return value

static func same(a:Variant,b:Variant)->bool:
	return var_to_bytes(canon(a))==var_to_bytes(canon(b))

static func rec(points:int,talk:int,gift:int)->Dictionary:
	return {"points":points,"talk_day":talk,"gift_day":gift}

static func pl(w,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

static func cell_of(w,resident:String)->Vector2i:
	var state:Dictionary=w.state
	var place:Array=World.bond_place(state,resident)
	var found:Vector2i=place[1]
	return found

static func region_of(w,resident:String)->String:
	var state:Dictionary=w.state
	var place:Array=World.bond_place(state,resident)
	return str(place[0])

static func go(w,token:String,region:String,cell:Vector2i)->void:
	var p:Dictionary=pl(w,token)
	p["region"]=region
	stand(w,token,cell)

static func stand(w,token:String,cell:Vector2i)->void:
	var p:Dictionary=pl(w,token)
	p["x"]=float(cell.x)+0.5
	p["y"]=float(cell.y)+1.5

## PRESET: writes the bond record directly (no talk/gift).
static func set_points(w,token:String,resident:String,points:int)->void:
	var p:Dictionary=pl(w,token)
	var bonds:Dictionary={}
	if p.get("bonds") is Dictionary:bonds=p.bonds
	bonds[resident]=rec(points,-1,-1)
	p["bonds"]=bonds

## PRESET: every item of `cost` set to cost+more.
static func fill(w,token:String,cost:Dictionary,more:int)->void:
	var inv:Dictionary=pl(w,token).inventory
	for item in cost:inv[item]=int(cost[item])+more

static func set_item(w,token:String,item:String,count:int)->void:
	var inv:Dictionary=pl(w,token).inventory
	inv[item]=count

static func goals_of(w,token:String)->Variant:
	var p:Dictionary=pl(w,token)
	if not p.has(Goals.RECORD_KEY):return null
	var value:Variant=p[Goals.RECORD_KEY]
	if value is Dictionary:
		var copy:Dictionary=value.duplicate(true)
		return copy
	return value

static func view_row(w,token:String,resident:String,stage:int)->Dictionary:
	var v:Dictionary=Goals.view(pl(w,token))
	var own:Dictionary=v.get(resident,{})
	var row:Dictionary=own.get(str(stage),{})
	return row

static func extra_of(resident:String,stage:int,option:String,steps:String)->String:
	return "%s:%d:%s:%s"%[resident,stage,option,steps]

static func option_ids(e:Dictionary)->Array:
	var out:Array=[]
	var options:Array=e.get("options",[])
	for found in options:
		var o:Dictionary=found
		out.append(str(o.get("id","")))
	if out.is_empty():out.append("")
	return out

static func right_steps(e:Dictionary)->String:
	if not e.has("steps"):return ""
	if not e.has("order"):return "012"
	var text:=""
	var order:Array=e.order
	for index in order:text+=str(index)
	return text

static func stage_msg(resident:String,stage:int)->String:
	return "和%s的關係到「%s」之後，才能一起做這件事。"%[Bond.name_of(resident),Bond.stage_name(stage)]

static func done_msg(e:Dictionary)->String:
	return "〈%s〉已經一起完成了，手帳可以重看。"%str(e.get("title",""))

static func order_msg(resident:String)->String:
	return "順序不太對。%s說不急，再看一次圖示。"%Bond.name_of(resident)

static func short_msg(item:String,held:int,needed:int)->String:
	return "還差%s %d／%d。"%[str(World.NAMES.get(item,item)),held,needed]

static func success_msg(resident:String,e:Dictionary)->String:
	var quote:Array=e.get("quote",["",""])
	var message:="%s：「%s」你們一起完成了〈%s〉，手帳記下紀念「%s」。"%[Bond.name_of(resident),str(quote[0]),str(e.get("title","")),str(e.get("keepsake",""))]
	if resident=="nuannuan" and e.get("title")=="一直沒亮的門牌":message+="旅舍迎賓牌圖樣已加入家園工坊的「暖泉旅舍」頁。"
	if resident=="nuannuan" and e.get("title")=="池邊的裂縫":message+="暖石泡腳池圖樣已加入家園工坊的「暖泉旅舍」頁。"
	if resident=="chacha" and e.get("title")=="一場沒有流程的茶會":message+="不完美的茶亭圖樣已加入家園工坊的「茶屋」頁。"
	if resident=="xiaoli" and e.get("title")=="輪子停在哪裡":message+="小栗把選址和招牌攤車圖樣一起留在關係事件裡。"
	if resident=="xiaoli" and e.get("title")=="第一位回頭客":message+="栗棕攤布與栗果招牌已加入市集攤位的布置選單。"
	if resident=="lingpopo" and e.get("title")=="最後一枚鈴":message+="風鈴節紀念鐘圖樣已加入家園工坊的「家具」頁。"
	return message

## Batch 3: success message of `resident stage`, with the keepsake sentence
## appended only on the twelve keepsake goals.
static func goal_msg(resident:String,stage:int)->String:
	var base:=success_msg(resident,Goals.goal(resident,stage))
	return base if ks_kind(resident,stage).is_empty() else base+MSG_KEEPSAKE_TAIL

static func ks_kind(resident:String,stage:int)->String:
	return str(KEEPSAKE_GOALS.get("%s %d"%[resident,stage],""))

## Catalog name of the keepsake (Goals.KEEPSAKES name): the goal's own text, except
## the story cart whose item is named 祖父的礦車.
static func ks_name(resident:String,stage:int)->String:
	if resident=="bobo" and stage==4:return CART_NAME
	return str(Goals.goal(resident,stage).get("keepsake",""))

## Expected view entry "keepsake" of a keepsake goal.
static func want_keepsake(resident:String,stage:int,claimed:bool)->Dictionary:
	var kind:=ks_kind(resident,stage)
	return {"kind":kind,"item":kind+"_kit","name":ks_name(resident,stage),"claimed":claimed}

## `row` plus the expected keepsake entry when the goal has one.
static func with_keepsake(row:Dictionary,resident:String,stage:int,claimed:bool)->Dictionary:
	var out:Dictionary=row.duplicate(true)
	if not ks_kind(resident,stage).is_empty():out["keepsake"]=want_keepsake(resident,stage,claimed)
	return out

static func claim_msg(resident:String,stage:int)->String:
	return "%s把紀念小物「%s」交給你，已放進背包。在家園工坊的「生活」頁選它就能擺到家園。"%[Bond.name_of(resident),ks_name(resident,stage)]

static func claimed_msg(resident:String,stage:int)->String:
	return "「%s」已經領過了。"%ks_name(resident,stage)

static func not_done_claim_msg(resident:String,stage:int)->String:
	return "先和%s一起完成〈%s〉，才有紀念小物。"%[Bond.name_of(resident),str(Goals.goal(resident,stage).get("title",""))]

static func cap_msg(resident:String,stage:int)->String:
	return "背包裡的「%s」已經放不下了，先整理背包。"%ks_name(resident,stage)

## {kit item: int count} for every keepsake kit key present in the inventory.
static func kit_counts(person:Dictionary)->Dictionary:
	var out:={}
	var held:Variant=person.get("inventory")
	if not held is Dictionary:return out
	for item:String in Goals.keepsake_items():
		if held.has(item):out[item]=int(held[item])
	return out

static func msg(r:Dictionary)->String:
	return str(r.get("message",""))

func act(w,token:String,action:String,cell:Vector2i,extra:String,request:String="")->Dictionary:
	serial+=1
	var id:String=request if not request.is_empty() else "goal-req-%d"%serial
	var r:Dictionary=w.act(token,id,action,cell,extra)
	return r

func do_goal(w,token:String,cell:Vector2i,extra:String,request:String="")->Dictionary:
	return act(w,token,Goals.ACTION,cell,extra,request)

## Rejected (with the exact message unless `message` is empty) and the whole
## world state byte-identical after canonicalisation.
func refuse(w,token:String,cell:Vector2i,extra:String,message:String,label:String)->void:
	refuse_act(w,token,Goals.ACTION,cell,extra,message,label)

## Same as refuse() for any action (used for resident_keepsake).
func refuse_act(w,token:String,action:String,cell:Vector2i,extra:String,message:String,label:String)->void:
	var before:=var_to_bytes(canon(w.state))
	var r:=act(w,token,action,cell,extra)
	expect(not bool(r.get("ok",true)) and (message.is_empty() or msg(r)==message),"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),msg(r)])
	expect(var_to_bytes(canon(w.state))==before,"%s: whole world state byte-identical"%label)

func write_fixture(path:String,data:Variant)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func validates(data:Variant)->bool:
	var parsed:Variant=JSON.parse_string(JSON.stringify(data))
	if not parsed is Dictionary:return false
	return Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

static func items_ok(items:Variant)->bool:
	if not items is Dictionary or items.is_empty():return false
	for item in items:
		if not item is String or not World.NAMES.has(item):return false
		var count:Variant=items[item]
		if not count is int or int(count)<=0:return false
	return true

# ------------------------------------------------------------- needs helpers --

## True when `text` names no need id (quoted) and no need label.
static func no_need_rows(text:String)->bool:
	for id:String in all_needs():
		if text.contains("\"%s\""%id) or text.contains(need_text(id)):return false
	return true

## Every need id: the literal table plus the story-cart need.
static func all_needs()->Array:
	var ids:Array=NEED_TEXT.keys()
	ids.append(CART_NEED)
	return ids

static func need_text(id:String)->String:
	if id==CART_NEED:return CART_NEED_TEXT
	return str(NEED_TEXT.get(id,id))

static func need_msg(label:String)->String:
	return "還不能一起做這件事：要先「%s」。"%label

## Independent expectation of need_label: literal text, known_three with the
## count of residents other than luoluo at stage >= 1, capped at 3.
static func want_label(need:String,person:Dictionary)->String:
	if need=="known_three":
		var count:=0
		for other:String in Bond.RESIDENTS:
			if other!="luoluo" and Bond.stage(person,other)>=1:count+=1
		return "%s（目前 %d 位）"%[str(NEED_TEXT["known_three"]),mini(3,count)]
	if need==CLUES_NEED:return CLUES_TEXT%clue_count(person)
	return need_text(need)

## Independent expectation of the clue progress: distinct strings of the field, capped at 3.
static func clue_count(person:Dictionary)->int:
	var seen:Dictionary={}
	var field:Variant=person.get(CLUES_KEY,[])
	if field is Array:
		for entry:Variant in field:
			if entry is String:seen[entry]=true
	return mini(3,seen.size())

## Expected needs rows of `e`; every need met unless `met` says otherwise.
static func want_rows(e:Dictionary,person:Dictionary,met:Dictionary)->Array:
	var rows:Array=[]
	var needs:Array=e.get("needs",[])
	for need:String in needs:
		rows.append({"id":need,"label":want_label(need,person),"met":bool(met.get(need,seat_default(need,person)))})
	return rows

## Default met value of a need row: true, except diandian_seated which also needs
## the flag, a done stage 1 and bond stage >= 2 on the viewed player.
static func seat_default(need:String,person:Dictionary)->bool:
	if need!="diandian_seated":return true
	var record:Variant=person.get(Goals.RECORD_KEY)
	var own:Variant=record.get("diandian") if record is Dictionary else null
	return person.get(Goals.DIANDIAN_SEAT_KEY)==true and own is Dictionary and own.has("1") and Bond.stage(person,"diandian")>=2

## Expected open/locked view row: needs rows only on goals that have needs.
static func want_row(e:Dictionary,person:Dictionary,state_name:String,met:Dictionary)->Dictionary:
	var row:Dictionary={"state":state_name,"choice":""}
	if e.has("needs"):row["needs"]=want_rows(e,person,met)
	return row

## Locked row shape: needs key (with the goal's need ids) iff the goal has needs;
## batch 3: an unclaimed keepsake entry iff the goal has a keepsake.
static func locked_row_ok(resident:String,key:String,row:Dictionary)->bool:
	if str(row.get("state",""))!="locked" or str(row.get("choice","?"))!="":return false
	var e:Dictionary=Goals.goal(resident,int(key))
	var has_ks:=not ks_kind(resident,int(key)).is_empty()
	var want_size:=2+(1 if e.has("needs") else 0)+(1 if has_ks else 0)
	if row.size()!=want_size:return false
	if has_ks:
		var ks_found:Variant=row.get("keepsake")
		if not ks_found is Dictionary or not same(ks_found,want_keepsake(resident,int(key),false)):return false
	if not e.has("needs"):return true
	if not row.get("needs") is Array:return false
	var rows:Array=row["needs"]
	var ids:Array=[]
	for found in rows:
		if not found is Dictionary:return false
		var d:Dictionary=found
		ids.append(str(d.get("id","")))
	var want:Array=e["needs"]
	return ids==want

## Goals.view with the world state and the player's token (as Session sends it).
static func view_at(w,token:String,resident:String,stage:int)->Dictionary:
	var state:Dictionary=w.state
	var v:Dictionary=Goals.view(pl(w,token),state,token)
	var own:Dictionary=v.get(resident,{})
	var row:Dictionary=own.get(str(stage),{})
	return row

static func market_with_report()->Dictionary:
	var m:Dictionary=MarketStall.fresh()
	m["open_day"]=0
	m["report"]={"day":0,"visitors":0,"stalls":0,"theme":MarketStall.theme_of(0),"sold":{},"coins":0}
	return m

static func festival_at(number:int,active:bool)->Dictionary:
	var f:Dictionary=Festival.fresh()
	f["round"]=number
	f["active"]=active
	return f

## PRESET: moves state.time forward by whole days to the next day (possibly
## today) whose home weather is rainy / not rainy.
static func move_weather(w,rainy:bool)->void:
	var now:float=float(w.state.time)
	for k in range(0,15):
		var t:float=now+float(k)*Weather.DAY_SECONDS
		if Weather.rains(Weather.day_index(t),"home")==rainy:
			w.state["time"]=t
			return

## PRESET: an object of `kind` owned by `owner` at an off-map key.
func put_object(w,owner:String,kind:String)->String:
	serial+=1
	var k:String=World.key(Vector2i(-200-serial,-200))
	var objects:Dictionary=w.state.objects
	objects[k]={"type":kind,"owner":owner,"items":{}}
	return k

static func clear_beds(w,owner:String)->void:
	var objects:Dictionary=w.state.objects
	for k in objects.keys():
		var obj:Variant=objects[k]
		if obj is Dictionary and str(obj.get("type",""))=="bed" and str(obj.get("owner",""))==owner:objects.erase(k)

## PRESET: makes one prerequisite hold (met) or not hold for `token`.
func set_need(w,token:String,need:String,met:bool)->void:
	var p:Dictionary=pl(w,token)
	match need:
		"tea_chair":
			if met:p[Goals.TEA_CHAIR_KEY]="coast"
			else:p.erase(Goals.TEA_CHAIR_KEY)
		"shared_garden":
			if met:w.state[Goals.GARDEN_KEY]=[{"npc":false,"author":token,"flower":"bluebell"},{"npc":true,"author":"xinghe","flower":"chime_herb"},{"npc":true,"author":"milu","flower":"orange_blossom"}]
			else:w.state.erase(Goals.GARDEN_KEY)
		"achao_photo":
			if met:p[Goals.VOYAGE_PHOTO]=true
			else:p.erase(Goals.VOYAGE_PHOTO)
		"achao_voyage":
			if met:
				w.state.dock_stage=2
				w.state[Goals.DOCK_LIGHT]=true
				p[Goals.VOYAGE_DONE]=true
			else:p.erase(Goals.VOYAGE_DONE)
		"aru_park_photo":
			if met:p[Goals.ARU_PHOTO_KEY]=true
			else:p.erase(Goals.ARU_PHOTO_KEY)
		"aru_rest":
			if met:p[Goals.ARU_REST_KEY]=float(w.state.time)
			else:p.erase(Goals.ARU_REST_KEY)
		"diandian_seated":
			# PRESET: the private seated flag. met also seeds the stage-1 record and a stage-2 bond (need_met requires both);
			# unmet only removes the flag, so the bare stage-1 record stays seeded for the other rules.
			if met:
				p[Goals.DIANDIAN_SEAT_KEY]=true
				var seat_prior:Dictionary=p.get(Goals.RECORD_KEY,{})
				var seat_own:Dictionary=seat_prior.get("diandian",{})
				seat_own["1"]=""
				seat_prior["diandian"]=seat_own
				p[Goals.RECORD_KEY]=seat_prior
				if Bond.stage(p,"diandian")<2:set_points(w,token,"diandian",int(Bond.THRESHOLDS[1]))
			else:p.erase(Goals.DIANDIAN_SEAT_KEY)
		"sheep_comfort":
			if met:p[Goals.SHEEP_SHELTER_KEY]=Goals.SHEEP_COMFORT_MASK
			else:p.erase(Goals.SHEEP_SHELTER_KEY)
		"tea_setup":
			if met:p[Goals.TEA_SETUP_KEY]="horizontal"
			else:p.erase(Goals.TEA_SETUP_KEY)
		"public_mural":
			if met:
				if not w.state.has(Goals.MURAL_KEY):
					var author:=WATCHER if w.state.players.has(WATCHER) else token
					w.state[Goals.MURAL_KEY]={"author":author,"author_name":pl(w,author).name,"subjects":["aru","milu","xiaoli"],"signatures":{}}
				if w.state[Goals.MURAL_KEY].author!=token:w.state[Goals.MURAL_KEY].signatures[token]=p.name
			elif w.state.has(Goals.MURAL_KEY):
				if w.state[Goals.MURAL_KEY].author==token:w.state.erase(Goals.MURAL_KEY)
				else:w.state[Goals.MURAL_KEY].signatures.erase(token)
		"painting_invites":
			if met:p[Goals.PAINT_INVITES_KEY]=["aru","milu","xiaoli"]
			else:p.erase(Goals.PAINT_INVITES_KEY)
		"growth_record":
			if met:p[Goals.GROWTH_LOG_KEY]={"radish":true}
			else:p.erase(Goals.GROWTH_LOG_KEY)
		"address_delivered":
			if met:p[Goals.ADDRESS_KEY]=Goals.ADDRESS_DELIVERED
			else:p.erase(Goals.ADDRESS_KEY)
		"inn_cracks":
			if met:p[World.WARM_SPRINGS.CRACK_KEY]=World.WARM_SPRINGS.CRACK_MASK
			else:p.erase(World.WARM_SPRINGS.CRACK_KEY)
		"inn_entrance":
			if met:p[Goals.INN_CLEAR_KEY]=true
			else:p.erase(Goals.INN_CLEAR_KEY)
		"guest_room":
			if met:p[Goals.GUEST_ROOM_KEY]=true
			else:p.erase(Goals.GUEST_ROOM_KEY)
		"bell_inspected":
			if met:p[Goals.BELL_INSPECT_KEY]=Goals.BELL_INSPECT_MASK
			else:p.erase(Goals.BELL_INSPECT_KEY)
		"rest_kit":
			if met:p[Goals.REST_KIT_KEY]=Goals.REST_KIT_MASK
			else:p.erase(Goals.REST_KIT_KEY)
		"bobo_cart_arrived":
			# PRESET: the private arrived stage (the real pushes are in test_bobo_empty_cart.gd).
			if met:p[CART_FIELD]=7
			else:p.erase(CART_FIELD)
		"recipe_pages":
			if met:p[Goals.RECIPE_PAGE_KEY]=Goals.RECIPE_PAGE_MASK
			else:p.erase(Goals.RECIPE_PAGE_KEY)
		"route_marks":
			if met:p[Goals.ROUTE_KEY]=Goals.ROUTE_MASK
			else:p.erase(Goals.ROUTE_KEY)
		"crop_sketches":
			if met:p[Goals.SKETCH_KEY]={"radish":true,"lettuce":true,"wheat":true}
			else:p.erase(Goals.SKETCH_KEY)
		"shared_meal":
			if met:p.resident_participation={"shared_meal":true}
			else:p.erase("resident_participation")
		"crop_sold","seed_after_sale":
			if met:p[Goals.CROP_TRADE_KEY]=Goals.SEED_BOUGHT
			elif need=="seed_after_sale":p[Goals.CROP_TRADE_KEY]=Goals.CROP_SOLD
			else:p.erase(Goals.CROP_TRADE_KEY)
		"sheep_step":
			if met:p[Goals.SHEEP_STEP_KEY]=float(w.state.time)-Goals.SHEEP_STEP_SECONDS
			else:p.erase(Goals.SHEEP_STEP_KEY)
		"chicken_fed":
			if met:p[Goals.CHICKEN_FED_KEY]=float(w.state.time)-Goals.CHICKEN_APPROACH_SECONDS
			else:p.erase(Goals.CHICKEN_FED_KEY)
		"own_bed":
			clear_beds(w,token)
			if met:put_object(w,token,"bed")
		"glass_crafted":
			p["greenhouse_glass_crafted"]=met
		"market_round":
			if met:p["market"]=market_with_report()
			else:p.erase("market")
		"xiaoli_first_trade","xiaoli_cart_plan","xiaoli_return_guest":
			var prior:Dictionary=p.get(Goals.RECORD_KEY,{})
			var xiaoli:Dictionary=prior.get("xiaoli",{})
			var step:String={"xiaoli_first_trade":"1","xiaoli_cart_plan":"2","xiaoli_return_guest":"3"}[need]
			if met:xiaoli[step]="tree" if step=="2" else ""
			else:xiaoli.erase(step)
			if xiaoli.is_empty():prior.erase("xiaoli")
			else:prior["xiaoli"]=xiaoli
			if prior.is_empty():p.erase(Goals.RECORD_KEY)
			else:p[Goals.RECORD_KEY]=prior
		"festival_done":
			w.state["festival"]=festival_at(1 if met else 0,false)
		"known_three":
			for other:String in KNOWN_OTHERS:
				if met:
					set_points(w,token,other,int(Bond.THRESHOLDS[0]))
				elif p.get("bonds") is Dictionary:
					var bonds:Dictionary=p["bonds"]
					bonds.erase(other)
		"postcard_clues":
			if met:p[CLUES_KEY]=KNOWN_OTHERS.duplicate()
			else:p.erase(CLUES_KEY)
		"postcard_reported":
			# FIXTURE: luoluo 2 written as done directly (the real completion is in test_needs_through_world).
			var luoluo_prior:Dictionary=p.get(Goals.RECORD_KEY,{})
			var luoluo_own:Dictionary=luoluo_prior.get("luoluo",{})
			if met:luoluo_own["2"]=""
			else:luoluo_own.erase("2")
			if luoluo_own.is_empty():luoluo_prior.erase("luoluo")
			else:luoluo_prior["luoluo"]=luoluo_own
			if luoluo_prior.is_empty():p.erase(Goals.RECORD_KEY)
			else:p[Goals.RECORD_KEY]=luoluo_prior
		"memory_shared":
			# FIXTURE: luoluo 3 written as done directly (stage 3 only; the real completion is in test_needs_once_and_save).
			var memory_prior:Dictionary=p.get(Goals.RECORD_KEY,{})
			var memory_own:Dictionary=memory_prior.get("luoluo",{})
			if met:memory_own["3"]="aloud"
			else:memory_own.erase("3")
			if memory_own.is_empty():memory_prior.erase("luoluo")
			else:memory_prior["luoluo"]=memory_own
			if memory_prior.is_empty():p.erase(Goals.RECORD_KEY)
			else:p[Goals.RECORD_KEY]=memory_prior
		"fair_weather":
			move_weather(w,not met)
		_:
			expect(false,"unknown need "+need)

## A player standing at `resident` at exactly `stage`, holding the exact cost.
func ready_player(w,token:String,resident:String,stage:int,option:String)->Vector2i:
	w.add_player(token,"丁")
	var cell:Vector2i=cell_of(w,resident)
	go(w,token,region_of(w,resident),cell)
	set_points(w,token,resident,int(Bond.THRESHOLDS[stage-1]))
	fill(w,token,Goals.cost(Goals.goal(resident,stage),option),0)
	return cell

# ------------------------------------------------------------------ catalog --

func test_catalog()->void:
	expect(Goals.ACTION=="resident_goal" and Goals.RECORD_KEY=="bond_goals" and Goals.STEP_COUNT==3,"ACTION resident_goal, RECORD_KEY bond_goals, STEP_COUNT 3")
	expect(World.RESIDENT_GOALS.ACTION==Goals.ACTION,"World wires the same RESIDENT_GOALS module")
	expect(Goals.ACTION not in Bond.ACTIONS,"resident_goal is not one of the bond talk/gift actions")
	var keys:Array=Goals.GOALS.keys()
	keys.sort()
	expect(keys==TWELVE,"GOALS covers exactly the twelve bond residents (%s)"%str(keys))
	var count:=0
	var ordered:Array=[]
	var tags:Array=[]
	var with_needs:Dictionary={}
	for resident in Goals.GOALS:
		expect(resident is String and resident in Bond.RESIDENTS,"GOALS resident %s is in Bond.RESIDENTS"%str(resident))
		var stages:Dictionary=Goals.GOALS[resident]
		expect(not stages.is_empty(),"%s has at least one goal"%str(resident))
		for stage in stages:
			count+=1
			var tag:="%s %s"%[str(resident),str(stage)]
			tags.append(tag)
			expect(stage is int and int(stage)>=1 and int(stage)<=4,tag+": stage is an int within 1..4")
			var e:Dictionary=stages[stage]
			for field in e:
				expect(field in ALLOWED_FIELDS,"%s: field %s is a known goal field"%[tag,str(field)])
			for field in ["title","task","keepsake"]:
				expect(e.get(field) is String and not str(e.get(field)).strip_edges().is_empty(),"%s: %s is a non-empty string"%[tag,field])
			var quote:Variant=e.get("quote")
			var quote_ok:bool=quote is Array and quote.size()==2
			if quote_ok:
				for line in quote:
					if not line is String or str(line).strip_edges().is_empty():quote_ok=false
			expect(quote_ok,tag+": quote has exactly 2 non-empty lines")
			expect(Goals.has_goal(str(resident),int(stage)) and Goals.goal(str(resident),int(stage))==e,tag+": has_goal/goal find it")
			expect(e.has("items") or e.has("options") or e.has("steps") or e.has("needs"),tag+": asks for items, a choice, steps or a prerequisite")
			if e.has("needs"):
				var needs:Variant=e.get("needs")
				var needs_ok:bool=needs is Array and not (needs as Array).is_empty()
				var seen:Array=[]
				if needs_ok:
					for need in needs:
						if not need is String or not Goals.NEEDS.has(need) or need in seen:needs_ok=false
						seen.append(need)
				expect(needs_ok,tag+": needs is a non-empty list of unique known need ids (%s)"%str(needs))
				with_needs[tag]=needs
			if e.has("items"):
				expect(items_ok(e.get("items")),tag+": items are known item ids with positive int counts")
			if e.has("options"):
				var opts:Variant=e.get("options")
				var opts_ok:bool=opts is Array and opts.size()>=2
				var ids:Array=[]
				if opts_ok:
					for o in opts:
						if not o is Dictionary:
							opts_ok=false
							continue
						var option:Dictionary=o
						var id:Variant=option.get("id")
						if not id is String or str(id).is_empty() or str(id).contains(":") or id in ids:opts_ok=false
						ids.append(id)
						if not option.get("label") is String or str(option.get("label")).strip_edges().is_empty():opts_ok=false
						for field in option:
							if field not in ["id","label","items"]:opts_ok=false
						if option.has("items") and not items_ok(option.get("items")):opts_ok=false
				expect(opts_ok,tag+": at least two options, unique non-empty ids, labels, valid per-option items (%s)"%str(ids))
			if e.has("steps"):
				var steps:Variant=e.get("steps")
				var steps_ok:bool=steps is Array and steps.size()==3
				if steps_ok:
					for step_name in steps:
						if not step_name is String or str(step_name).strip_edges().is_empty():steps_ok=false
				expect(steps_ok,tag+": exactly 3 non-empty steps")
			if e.has("order"):
				ordered.append(tag)
				expect(e.has("steps"),tag+": order only on a goal with steps")
				var order:Variant=e.get("order")
				var perm_ok:bool=order is Array and order.size()==3
				if perm_ok:
					for index in order:
						if not index is int:perm_ok=false
					var sorted_order:Array=(order as Array).duplicate()
					sorted_order.sort()
					if sorted_order!=[0,1,2]:perm_ok=false
				expect(perm_ok,tag+": order is a permutation of 0..2 (%s)"%str(order))
	expect(count==48 and Goals.total()==48,"48 goals in total (counted %d, total() %d)"%[count,Goals.total()])
	tags.sort()
	expect(tags==ALL_GOALS,"the 48 goals match the published list (%s)"%str(tags))
	expect(same(with_needs,WANT_NEEDS),"exactly the published goals carry needs, bobo 4 needs only bobo_cart_arrived (%s)"%str(with_needs))
	var needs_wo_cart:Dictionary=Goals.NEEDS.duplicate()
	var cart_label:Variant=needs_wo_cart.get(CART_NEED)
	needs_wo_cart.erase(CART_NEED)
	expect(needs_wo_cart==NEED_TEXT,"NEEDS has exactly the published ids with their labels, plus the cart need (%s)"%str(Goals.NEEDS))
	expect(cart_label==CART_NEED_TEXT and Goals.NEEDS.size()==NEED_TEXT.size()+1,"NEEDS[bobo_cart_arrived] is the published label (%s)"%str(cart_label))
	expect(Goals.KNOWN_NEEDED==3,"KNOWN_NEEDED is 3")
	ordered.sort()
	expect(ordered==["achao 1","lingpopo 2"],"only achao 1 and lingpopo 2 have a fixed order (%s)"%str(ordered))
	expect(right_steps(Goals.goal("achao",1))=="210" and right_steps(Goals.goal("lingpopo",2))=="102","fixed orders: achao 210, lingpopo 102")
	# Batch 2 costs.
	expect(Goals.cost(Goals.goal("aru",1),"")=={"wood":10},"cost aru 1 = 10 wood")
	expect(Goals.cost(Goals.goal("mianmian",1),"").is_empty(),"mianmian 1 uses actual feeding with no second charge")
	expect(Goals.cost(Goals.goal("xinghe",3),"")=={"glass":2,"copper_joint":2},"cost xinghe 3 = 2 glass + 2 copper joints")
	for option_id:String in ["none","chestnut","tomorrow"]:
		expect(Goals.cost(Goals.goal("xiaoli",4),option_id)=={"plank":2},"cost xiaoli 4 %s = 2 planks"%option_id)
	for costless:Array in [["bobo",4,"home"],["mianmian",4,""],["lingpopo",4,""],["xiaoli",3,""],["luoluo",2,""],["luoluo",4,"blank"],["luoluo",4,"write"],["nuannuan",4,"pool"]]:
		expect(Goals.cost(Goals.goal(str(costless[0]),int(costless[1])),str(costless[2])).is_empty(),"%s %d costs nothing"%[str(costless[0]),int(costless[1])])
	for bad:Array in [["tom",1],["aru",0],["aru",5],["xinghe",5],["",1]]:
		expect(not Goals.has_goal(str(bad[0]),int(bad[1])) and Goals.goal(str(bad[0]),int(bad[1])).is_empty(),"no goal for %s %d"%[str(bad[0]),int(bad[1])])
	# sequence()
	expect(Goals.sequence("012")==[0,1,2] and Goals.sequence("210")==[2,1,0] and Goals.sequence("102")==[1,0,2],"sequence parses permutations in order")
	for bad:String in BAD_STEPS:
		expect(Goals.sequence(bad).is_empty(),"sequence('%s') is rejected"%bad)
	# cost()
	expect(Goals.cost(Goals.goal("bobo",2),"siding")=={"copper_ingot":4,"woodwork_parts":2},"cost bobo 2 siding = 4 copper ingots + 2 woodwork parts")
	expect(Goals.cost(Goals.goal("lingpopo",3),"salad")=={"copper_ingot":4,"glass":2,"salad":1},"cost lingpopo 3 salad = shared items + the dish")
	expect(Goals.cost(Goals.goal("milu",3),"carrot_soup")=={"carrot_soup":2},"cost milu 3 carrot_soup = per-option items only")
	expect(Goals.cost(Goals.goal("xinghe",2),"bluebell_chime")=={"bluebell":2,"chime_herb":2},"cost xinghe 2 bluebell_chime")
	expect(Goals.cost(Goals.goal("chacha",3),"").is_empty() and Goals.cost(Goals.goal("luoluo",3),"aloud").is_empty(),"chacha 3 and luoluo 3 cost nothing")
	var scratch:Dictionary=Goals.cost(Goals.goal("aru",2),"")
	scratch["hardwood"]=99
	expect(Goals.cost(Goals.goal("aru",2),"")=={"hardwood":4},"cost() returns a copy (mutating it does not change the catalog)")
	# done() / completed() / view()
	expect(Goals.done({},"milu").is_empty() and Goals.done({"bond_goals":[]},"milu").is_empty() and Goals.done({"bond_goals":{"milu":"1"}},"milu").is_empty(),"done() tolerates missing/odd records")
	expect(Goals.done({"bond_goals":{"milu":{"1":"","3":"soup"}}},"milu")=={1:"",3:"soup"},"done() maps stage strings to ints")
	expect(Goals.completed({"bond_goals":{"milu":{"1":"","3":"soup"},"bobo":{"2":"shed"}}})==3,"completed() counts every done goal")
	var fresh:Dictionary=Goals.view({})
	var fresh_keys:Array=fresh.keys()
	fresh_keys.sort()
	expect(fresh_keys==TWELVE,"view lists all twelve residents")
	var all_locked:=true
	for resident:String in Goals.GOALS:
		var own:Dictionary=fresh.get(resident,{})
		var want:Array=[]
		for stage:int in Goals.GOALS[resident]:want.append(str(stage))
		var got:Array=own.keys()
		got.sort()
		want.sort()
		if got!=want:all_locked=false
		for key in own:
			if not own[key] is Dictionary or not locked_row_ok(resident,str(key),own[key]):all_locked=false
	expect(all_locked,"fresh view: every goal stage listed and locked; needs rows exactly on goals with needs")
	var stateless:Dictionary=fresh.get("luoluo",{})
	expect(stateless.get("2",{})=={"state":"locked","choice":"","needs":[{"id":"known_three","label":str(NEED_TEXT["known_three"])+"（目前 0 位）","met":false},{"id":CLUES_NEED,"label":CLUES_TEXT%0,"met":false}]},
		"view(person) without state: needs rows present with met=false, no crash (%s)"%str(stateless.get("2")))
	var no_state_rows:=true
	for resident:String in fresh:
		var own:Dictionary=fresh[resident]
		for key in own:
			var row:Dictionary=own[key]
			if row.has("needs"):
				for need_row in row["needs"]:
					if not need_row is Dictionary or need_row.get("met")!=false:no_state_rows=false
	expect(no_state_rows,"view(person) without state: every needs row has met=false")
	# Batch 3: milu 3 carries a keepsake entry; done via a direct record (no bond_keepsakes) -> unclaimed.
	var some:Dictionary=Goals.view({"bonds":{"milu":rec(14,-1,-1)},"bond_goals":{"milu":{"3":"soup"}}})
	expect(some.get("milu",{})=={"1":{"state":"open","choice":""},"2":{"state":"open","choice":"","needs":[{"id":"recipe_pages","label":"找齊三片食譜紙角","met":false}]},"3":with_keepsake({"state":"done","choice":"soup"},"milu",3,false),"4":{"state":"locked","choice":"","needs":[{"id":"shared_meal","label":"親手上一輪共享料理","met":false}]}},"view: milu 1 open, 3 done with its choice and an unclaimed keepsake (%s)"%str(some.get("milu")))

# --------------------------------------------------------- the 28 goal flows --

func goal_flow(resident:String,stage:int)->void:
	flows+=1
	var e:Dictionary=Goals.goal(resident,stage)
	var tag:="%s %d"%[resident,stage]
	var w:=World.new()
	w.state["picnic"]=true  # PRESET: residents gated by the picnic are present
	w.state["dock_stage"]=1  # PRESET: achao is present
	var token:="goal-main-%s-%d"%[resident,stage]
	w.add_player(token,"甲")
	w.add_player(WATCHER,"乙")
	var region:=region_of(w,resident)
	var cell:=cell_of(w,resident)
	go(w,token,region,cell)
	go(w,WATCHER,region,cell)
	var threshold:=int(Bond.THRESHOLDS[stage-1])
	set_points(w,WATCHER,resident,threshold)
	var opts:=option_ids(e)
	var first:String=str(opts[0])
	var steps:=right_steps(e)
	var good:=extra_of(resident,stage,first,steps)
	var shop_name_action:=resident=="xiaoli" and stage==4
	var stray_action_extra:="店\n名" if shop_name_action else "012"
	var stray_action_message:=World.XIAOLI_SHOP.BAD_NAME if shop_name_action else MSG_REOPEN
	var cost:Dictionary=Goals.cost(e,first)
	# Batch 3: "" for the 16 goals without a keepsake.
	var kind:=ks_kind(resident,stage)
	var kit:=kind+"_kit" if not kind.is_empty() else ""
	var claim_extra:="%s:%d"%[resident,stage]
	expect(Goals.keepsake_kind(resident,stage)==kind,"%s: keepsake_kind is '%s'"%[tag,kind])
	# 0. PRESET: every prerequisite of this goal holds for both players.
	var needs:Array=e.get("needs",[])
	for need:String in needs:
		set_need(w,token,need,true)
		set_need(w,WATCHER,need,true)
		expect(Goals.need_met(need,w.state,token) and Goals.need_met(need,w.state,WATCHER),"%s: preset makes %s hold for both players"%[tag,need])
	var initial:Dictionary=pl(w,token).get(Goals.RECORD_KEY,{}).duplicate(true)
	# 1. One stage short.
	set_points(w,token,resident,threshold-1)
	fill(w,token,cost,1)
	expect(Bond.stage(pl(w,token),resident)==stage-1,tag+": preset bond is exactly one stage short")
	expect(str(view_row(w,token,resident,stage).get("state",""))=="locked",tag+": view shows locked")
	var full:=view_at(w,token,resident,stage)
	expect(full==with_keepsake(want_row(e,pl(w,token),"locked",{}),resident,stage,false),"%s: locked view row with state (needs rows iff the goal has needs, unclaimed keepsake iff it has one) (%s)"%[tag,str(full)])
	refuse(w,token,cell,good,stage_msg(resident,stage),tag+": one stage short")
	# 2. Reach the stage.
	set_points(w,token,resident,threshold)
	expect(Bond.stage(pl(w,token),resident)==stage,tag+": preset bond reaches the stage exactly")
	expect(str(view_row(w,token,resident,stage).get("state",""))=="open",tag+": view shows open")
	full=view_at(w,token,resident,stage)
	expect(full==with_keepsake(want_row(e,pl(w,token),"open",{}),resident,stage,false),"%s: open view row with state, needs all met (%s)"%[tag,str(full)])
	expect(full.has("keepsake")!=kind.is_empty(),"%s: view row has a keepsake key iff the goal has a keepsake"%tag)
	# 2b. Claim (through World.act) before the goal is done.
	if kind.is_empty():refuse_act(w,token,Goals.CLAIM_ACTION,cell,claim_extra,MSG_NO_KEEPSAKE,tag+": claim on a goal without a keepsake (open)")
	else:refuse_act(w,token,Goals.CLAIM_ACTION,cell,claim_extra,not_done_claim_msg(resident,stage),tag+": claim before the goal is done")
	# 3. Option and step validation.
	if e.has("options"):
		refuse(w,token,cell,extra_of(resident,stage,"nope",steps),MSG_PICK,tag+": invalid option id")
		refuse(w,token,cell,extra_of(resident,stage,"",steps),MSG_PICK,tag+": empty option")
		refuse(w,token,cell,extra_of(resident,stage,first.to_upper(),steps),MSG_PICK,tag+": option id in the wrong case")
		refuse(w,token,cell,extra_of(resident,stage,first+" ",steps),MSG_PICK,tag+": option id with a trailing space")
	else:
		refuse(w,token,cell,extra_of(resident,stage,"soup",steps),MSG_REOPEN,tag+": option on an option-less goal")
		refuse(w,token,cell,extra_of(resident,stage,"x",steps),MSG_REOPEN,tag+": option 'x' on an option-less goal")
	if e.has("steps"):
		for bad:String in BAD_STEPS:
			refuse(w,token,cell,extra_of(resident,stage,first,bad),MSG_STEPS,"%s: steps '%s'"%[tag,bad])
		if e.has("order"):
			for perm:String in PERMS:
				if perm!=steps:refuse(w,token,cell,extra_of(resident,stage,first,perm),order_msg(resident),"%s: wrong order %s"%[tag,perm])
	else:
		refuse(w,token,cell,extra_of(resident,stage,first,stray_action_extra),stray_action_message,tag+": invalid trailing input")
		if not shop_name_action:refuse(w,token,cell,extra_of(resident,stage,first,"0"),MSG_REOPEN,tag+": one step on a step-less goal")
	# 3b. Each prerequisite unmet (everything else satisfied), and check order.
	for need:String in needs:
		var ntag:="%s %s"%[tag,need]
		set_need(w,token,need,false)
		fill(w,token,cost,1)
		expect(not Goals.need_met(need,w.state,token),ntag+": preset makes the prerequisite fail")
		var unmet_msg:=need_msg(want_label(need,pl(w,token)))
		expect(Goals.need_label(need,w.state,token)==want_label(need,pl(w,token)),ntag+": need_label is the literal label")
		full=view_at(w,token,resident,stage)
		var unmet:Dictionary={need:false}
		if need=="crop_sold":unmet["seed_after_sale"]=false
		expect(full==with_keepsake(want_row(e,pl(w,token),"open",unmet),resident,stage,false),"%s: view row shows the need unmet (%s)"%[ntag,str(full)])
		refuse(w,token,cell,good,unmet_msg,ntag+": unmet with stage, option, steps and items satisfied")
		# Stage comes first.
		set_points(w,token,resident,threshold-1)
		refuse(w,token,cell,good,stage_msg(resident,stage),ntag+": stage short and need unmet -> stage message")
		set_points(w,token,resident,threshold)
		# Option comes before needs.
		if e.has("options"):
			refuse(w,token,cell,extra_of(resident,stage,"",steps),MSG_PICK,ntag+": option missing and need unmet -> option message")
		else:
			refuse(w,token,cell,extra_of(resident,stage,"soup",steps),MSG_REOPEN,ntag+": stray option and need unmet -> reopen message")
		# Steps come before needs.
		if e.has("steps"):
			refuse(w,token,cell,extra_of(resident,stage,first,"0"),MSG_STEPS,ntag+": steps incomplete and need unmet -> steps message")
			if e.has("order"):
				for perm:String in PERMS:
					if perm!=steps:
						refuse(w,token,cell,extra_of(resident,stage,first,perm),order_msg(resident),"%s: wrong order %s and need unmet -> order message"%[ntag,perm])
						break
		else:
			refuse(w,token,cell,extra_of(resident,stage,first,stray_action_extra),stray_action_message,ntag+": invalid trailing input and need unmet")
		# Needs come before items.
		for item:String in cost:
			fill(w,token,cost,1)
			var short_inv:Dictionary=pl(w,token).inventory
			short_inv.erase(item)
			refuse(w,token,cell,good,unmet_msg,"%s: %s absent and need unmet -> need message"%[ntag,item])
		if not cost.is_empty():
			var empty_inv:Dictionary=pl(w,token).inventory
			for item:String in cost:empty_inv.erase(item)
			refuse(w,token,cell,good,unmet_msg,ntag+": every cost item absent and need unmet -> need message")
		fill(w,token,cost,1)
		set_need(w,token,need,true)
		expect(Goals.need_met(need,w.state,token),ntag+": preset restores the prerequisite")
	# 4. Missing items: each cost item one short, then absent.
	if cost.is_empty():
		expect(not e.has("items"),tag+": no cost means no items field")
	for item:String in cost:
		var needed:=int(cost[item])
		fill(w,token,cost,0)
		set_item(w,token,item,needed-1)
		refuse(w,token,cell,good,short_msg(item,needed-1,needed),"%s: %s one short"%[tag,item])
		var inv:Dictionary=pl(w,token).inventory
		inv.erase(item)
		refuse(w,token,cell,good,short_msg(item,0,needed),"%s: %s absent"%[tag,item])
	expect(pl(w,token).get(Goals.RECORD_KEY,{})==initial,tag+": no refusal changes existing goals")
	expect(not pl(w,token).has(Goals.KEEPSAKE_KEY) and kit_counts(pl(w,token)).is_empty(),tag+": no refusal wrote bond_keepsakes or a keepsake kit")
	# 5. Success: only the cost items change, by exactly the cost (plus one kit on the 12 keepsake goals).
	fill(w,token,cost,1)
	set_item(w,token,"radish",3)
	var p:Dictionary=pl(w,token)
	if not kind.is_empty():
		var open_ks:Dictionary=view_at(w,token,resident,stage).get("keepsake",{})
		expect(open_ks.get("claimed")==false,"%s: keepsake claimed=false before completing (%s)"%[tag,str(open_ks)])
	var inv_before:Dictionary=p.inventory.duplicate(true)
	var bonds_before:Dictionary=(p.bonds as Dictionary).duplicate(true)
	var stories_before:Variant=p.get("stories",{})
	if stories_before is Dictionary:stories_before=(stories_before as Dictionary).duplicate(true)
	var coins_before:=int(p.get("coins",0))
	var bond_view:Dictionary=Bond.view(p,float(w.state.time))
	var watcher_before:=var_to_bytes(canon(pl(w,WATCHER)))
	var r:=do_goal(w,token,cell,good)
	expect(bool(r.get("ok",false)),"%s: completes with option '%s' steps '%s' (got '%s')"%[tag,first,steps,msg(r)])
	expect(msg(r)==goal_msg(resident,stage),"%s: exact success message (got '%s')"%[tag,msg(r)])
	expect(msg(r).contains(str(e.title)) and msg(r).contains(str(e.keepsake)),tag+": message names the title and the keepsake")
	if kind.is_empty():
		expect(msg(r)==success_msg(resident,e) and not msg(r).contains(MSG_KEEPSAKE_TAIL),tag+": no keepsake -> message unchanged from batch 2")
	else:
		expect(msg(r).ends_with(MSG_KEEPSAKE_TAIL) and msg(r)==success_msg(resident,e)+MSG_KEEPSAKE_TAIL,tag+": message ends with the keepsake sentence")
	p=pl(w,token)
	var expected:Dictionary=inv_before.duplicate(true)
	for item:String in cost:expected[item]=int(inv_before[item])-int(cost[item])
	if not kind.is_empty():
		expect(not inv_before.has(kit),tag+": no kit held before completing")
		expected[kit]=1
	expect(p.inventory==expected,"%s: inventory changed by exactly %s%s (got %s)"%[tag,str(cost),"" if kind.is_empty() else " and +1 "+kit,str(p.inventory)])
	var kit_total:=0
	for item:String in Goals.keepsake_items():kit_total+=int(p.inventory.get(item,0))
	expect(kit_total==(0 if kind.is_empty() else 1),"%s: exactly %d keepsake kit(s) of any kind held"%[tag,0 if kind.is_empty() else 1])
	if kind.is_empty():
		expect(not p.has(Goals.KEEPSAKE_KEY),tag+": no keepsake -> no bond_keepsakes key created")
	else:
		expect(p.get(Goals.KEEPSAKE_KEY)=={kind:true},"%s: bond_keepsakes is exactly {%s:true} (got %s)"%[tag,kind,str(p.get(Goals.KEEPSAKE_KEY))])
		expect(Goals.valid_keepsakes(p.get(Goals.KEEPSAKE_KEY),p),tag+": the granted record passes valid_keepsakes")
	if "diandian_seated" in needs:expect(not p.has(Goals.DIANDIAN_SEAT_KEY),tag+": completion removes the diandian_seated field")
	if "diandian_seated" in needs:expect(pl(w,WATCHER).has(Goals.DIANDIAN_SEAT_KEY),tag+": the other player's seated flag is untouched")
	var want_record:=initial.duplicate(true)
	var expected_resident:Dictionary=want_record.get(resident,{})
	expected_resident[str(stage)]=first
	want_record[resident]=expected_resident
	expect(p.get(Goals.RECORD_KEY)==want_record,"%s: bond_goals is exactly %s (got %s)"%[tag,str(want_record),str(p.get(Goals.RECORD_KEY))])
	expect(Goals.done(p,resident).get(stage)==first and Goals.completed(p)==expected_resident.size(),tag+": done()/completed() see the new goal")
	expect(p.bonds==bonds_before and Bond.view(p,float(w.state.time))==bond_view,tag+": bond points, stage and daily flags unchanged")
	expect(p.get("stories",{})==stories_before and int(p.get("coins",0))==coins_before,tag+": stories and coins unchanged")
	expect(var_to_bytes(canon(pl(w,WATCHER)))==watcher_before,tag+": the other player's whole record is byte-identical")
	var row:=view_row(w,token,resident,stage)
	expect(str(row.get("state",""))=="done" and str(row.get("choice","?"))==first,"%s: view shows done with choice '%s' (%s)"%[tag,first,str(row)])
	full=view_at(w,token,resident,stage)
	var expected_view:Dictionary={"state":"done","choice":first}
	if resident=="chacha" and stage==3:expected_view["topics"]=steps
	expect(full==with_keepsake(expected_view,resident,stage,true),"%s: done view carries the completed event's fields and no needs key (%s)"%[tag,str(full)])
	if not kind.is_empty():
		var done_ks:Dictionary=full.get("keepsake",{})
		expect(done_ks.get("claimed")==true,"%s: keepsake claimed flipped to true"%tag)
		var watcher_ks:Dictionary=view_at(w,WATCHER,resident,stage).get("keepsake",{})
		expect(watcher_ks.get("claimed")==false,tag+": the other player's keepsake stays unclaimed")
	expect(str(view_row(w,WATCHER,resident,stage).get("state",""))=="open",tag+": the other player's view stays open")
	# 6. Repeat refused, even with items in hand.
	fill(w,token,cost,1)
	refuse(w,token,cell,good,done_msg(e),tag+": repeat")
	if opts.size()>1:refuse(w,token,cell,extra_of(resident,stage,str(opts[1]),steps),done_msg(e),tag+": repeat with another option")
	# 6b. Claim (through World.act) after a batch-3 completion: already granted / nothing to claim.
	if kind.is_empty():refuse_act(w,token,Goals.CLAIM_ACTION,cell,claim_extra,MSG_NO_KEEPSAKE,tag+": claim on a done goal without a keepsake")
	else:refuse_act(w,token,Goals.CLAIM_ACTION,cell,claim_extra,claimed_msg(resident,stage),tag+": claim after a batch-3 completion -> already claimed")
	# 7. Talk still works and only changes the bond record.
	var points_before:=int(Bond.record(pl(w,token),resident).points)
	r=act(w,token,"resident_talk",cell,resident)
	expect(bool(r.get("ok",false)),"%s: talk after the goal still works (got '%s')"%[tag,msg(r)])
	expect(int(Bond.record(pl(w,token),resident).points)==mini(Bond.LIMIT,points_before+1),tag+": talk adds its one point (capped at the bond limit)")
	expect(pl(w,token).get(Goals.RECORD_KEY)==want_record,tag+": talk leaves bond_goals unchanged")
	# 8. Every other option and every free order on separate players.
	for i in range(1,opts.size()):
		solo(w,e,resident,stage,region,cell,str(opts[i]),steps,"%s option %s"%[tag,str(opts[i])])
	if e.has("steps") and not e.has("order"):
		for perm:String in PERMS:
			if perm!=steps:solo(w,e,resident,stage,region,cell,first,perm,"%s free order %s"%[tag,perm])
	# 9. The watcher completes the same goal on their own.
	if resident=="nuannuan" and stage==4:w.move_player(token,Vector2.DOWN,0.1)
	fill(w,WATCHER,cost,0)
	var main_before:=var_to_bytes(canon(pl(w,token)))
	r=do_goal(w,WATCHER,cell,good)
	expect(bool(r.get("ok",false)),"%s: the other player completes the same goal (got '%s')"%[tag,msg(r)])
	expect(pl(w,WATCHER).get(Goals.RECORD_KEY)==want_record,tag+": the other player's own record")
	if kind.is_empty():
		expect(not pl(w,WATCHER).has(Goals.KEEPSAKE_KEY) and kit_counts(pl(w,WATCHER)).is_empty(),tag+": the other player gets no keepsake either")
	else:
		expect(pl(w,WATCHER).get(Goals.KEEPSAKE_KEY)=={kind:true} and kit_counts(pl(w,WATCHER))=={kit:1},tag+": the other player gets their own kit and record")
	expect(var_to_bytes(canon(pl(w,token)))==main_before,tag+": the first player's whole record unchanged by the second")
	# 10. Needs are checked once: undoing them leaves both records done and valid.
	if not needs.is_empty():
		for need:String in needs:
			set_need(w,token,need,false)
			set_need(w,WATCHER,need,false)
			expect(not Goals.need_met(need,w.state,token) and not Goals.need_met(need,w.state,WATCHER),"%s: %s undone for both players"%[tag,need])
		for who:String in [token,WATCHER]:
			full=view_at(w,who,resident,stage)
			expect(full==with_keepsake({"state":"done","choice":first},resident,stage,true),"%s: still done without a needs key after the prerequisite is undone (%s)"%[tag,str(full)])
			expect(Goals.valid(goals_of(w,who),pl(w,who)),"%s: the record still passes Goals.valid after undo (%s)"%[tag,str(goals_of(w,who))])
		fill(w,token,cost,1)
		refuse(w,token,cell,good,done_msg(e),tag+": repeat with the prerequisite undone -> already-done message")

## A fresh player in the same world completes the goal with `option`/`steps`.
func solo(w,e:Dictionary,resident:String,stage:int,region:String,cell:Vector2i,option:String,steps:String,label:String)->void:
	serial+=1
	var token:="goal-solo-%d"%serial
	w.add_player(token,"丙")
	go(w,token,region,cell)
	set_points(w,token,resident,int(Bond.THRESHOLDS[stage-1]))
	var needs:Array=e.get("needs",[])
	for need:String in needs:set_need(w,token,need,true)
	var cost:Dictionary=Goals.cost(e,option)
	fill(w,token,cost,0)
	set_item(w,token,"radish",1)
	var before:Dictionary=pl(w,token).inventory.duplicate(true)
	# N10-4: only luoluo 4 "write" takes a message (4th field); every other option/step keeps the caller's text.
	var tail:=steps
	if resident=="luoluo" and stage==4 and option=="write":tail="洛洛，謝謝你一直在。"
	var r:=do_goal(w,token,cell,extra_of(resident,stage,option,tail))
	expect(bool(r.get("ok",false)),"%s: accepted (got '%s')"%[label,msg(r)])
	var expected:Dictionary=before.duplicate(true)
	for item:String in cost:expected[item]=int(before[item])-int(cost[item])
	var kind:=ks_kind(resident,stage)
	if not kind.is_empty():expected[kind+"_kit"]=1  # batch 3: one kit granted
	expect(pl(w,token).inventory==expected,"%s: charged exactly %s%s"%[label,str(cost),"" if kind.is_empty() else " (+1 kit)"])
	var want:Dictionary={resident:{str(stage):option}}
	if "xiaoli_first_trade" in needs:want.xiaoli["1"]=""
	if "xiaoli_return_guest" in needs:want.xiaoli["3"]=""
	if "postcard_reported" in needs:want.luoluo["2"]=""
	if "memory_shared" in needs:want.luoluo["3"]="aloud"  # FIXTURE seeded by set_need
	if "diandian_seated" in needs:want.diandian["1"]=""  # FIXTURE: bare stage-1 record seeded by set_need
	if "diandian_seated" in needs:expect(not pl(w,token).has(Goals.DIANDIAN_SEAT_KEY),label+": completion removes the diandian_seated field")
	expect(pl(w,token).get(Goals.RECORD_KEY)==want,"%s: record %s (got %s)"%[label,str(want),str(pl(w,token).get(Goals.RECORD_KEY))])
	if kind.is_empty():expect(not pl(w,token).has(Goals.KEEPSAKE_KEY),label+": no bond_keepsakes key")
	else:expect(pl(w,token).get(Goals.KEEPSAKE_KEY)=={kind:true},label+": bond_keepsakes {%s:true}"%kind)
	expect(msg(r)==goal_msg(resident,stage),"%s: exact success message (got '%s')"%[label,msg(r)])

# ------------------------------------------------------ World-layer refusals --

func test_world_rejections()->void:
	var w:=World.new()
	var t:="goal-reject-token"
	w.add_player(t,"甲")
	var aru:=cell_of(w,"aru")
	var milu:=cell_of(w,"milu")
	go(w,t,"home",aru)
	set_points(w,t,"aru",6)
	set_item(w,t,"hardwood",5)
	var good:="aru:2::012"
	refuse(w,t,aru+Vector2i.RIGHT,good,MSG_PLACE,"aimed at the tile beside aru")
	refuse(w,t,aru+Vector2i.DOWN,good,MSG_PLACE,"aimed at the tile below aru")
	stand(w,t,milu)
	refuse(w,t,milu,good,MSG_PLACE,"aru's goal aimed at milu's cell")
	var p:Dictionary=pl(w,t)
	p["x"]=float(aru.x)+0.5
	p["y"]=float(aru.y)+5.5
	refuse(w,t,aru,good,MSG_FAR,"five tiles away from aru")
	stand(w,t,aru)
	for unknown:String in ["tom:2::012","Aru:2::012",":2::012","","::",":::"]:
		refuse(w,t,aru,unknown,MSG_PLACE,"unknown resident '%s'"%unknown)
	for malformed:String in ["aru","aru:2","aru:2:","aru:2::012:","aru:2::012:x","aru:x::012","aru:::012","aru:2.0::012","aru:two::012"]:
		refuse(w,t,aru,malformed,MSG_REOPEN,"malformed extra '%s'"%malformed)
	for nogoal:String in ["aru:0::","aru:5::","aru:-2::","aru:99::012"]:
		refuse(w,t,aru,nogoal,MSG_NO_GOAL,"stage without a goal '%s'"%nogoal)
	# aru 1 is a batch-2 goal now (needs own_bed; this player has no bed).
	refuse(w,t,aru,"aru:1::012",MSG_REOPEN,"aru 1 with steps is malformed")
	refuse(w,t,aru,"aru:1::",need_msg(str(NEED_TEXT["own_bed"])),"aru 1 without an own bed -> need message")
	# Wrong region: a player elsewhere aimed at the resident's coordinates.
	p=pl(w,t)
	p["region"]="jinguashi"
	refuse(w,t,aru,good,"","jinguashi player aimed at aru's home cell")
	set_points(w,t,"bobo",1)
	set_points(w,t,"nuannuan",1)
	set_points(w,t,"chacha",14)
	set_points(w,t,"diandian",6)
	set_points(w,t,"xinghe",6)
	set_item(w,t,"stone",8)
	set_item(w,t,"wood",8)
	set_item(w,t,"bluebell",2)
	set_item(w,t,"orange_blossom",2)
	for spec:Array in [["bobo","bobo:1::"],["nuannuan","nuannuan:1::"],["chacha","chacha:3::012"],["diandian","diandian:2:knees:"],["xinghe","xinghe:2:bluebell_orange:"]]:
		var target:=cell_of(w,str(spec[0]))
		go(w,t,"home",target)
		refuse(w,t,target,str(spec[1]),MSG_PLACE,"home player aimed at %s's %s cell"%[str(spec[0]),region_of(w,str(spec[0]))])
	go(w,t,"lanyang",cell_of(w,"bobo"))
	refuse(w,t,cell_of(w,"bobo"),"bobo:1::","","lanyang player aimed at bobo's cell")
	go(w,t,"maokong",cell_of(w,"xinghe"))
	refuse(w,t,cell_of(w,"xinghe"),"xinghe:2:bluebell_orange:","","maokong player aimed at xinghe's cell")
	expect(not pl(w,t).has(Goals.RECORD_KEY),"no World-layer refusal wrote bond_goals")
	go(w,t,"home",aru)
	var r:=do_goal(w,t,aru,good)
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"aru":{"2":""}},"after all refusals the right aru request succeeds (got '%s')"%msg(r))

# Residents not yet present (PRESET flags on a fresh world: picnic false, dock_stage 0).
func test_gates()->void:
	var specs:Array=[["mianmian",3,"ball",Bond.RANCH_LOCKED,"picnic"],["luoluo",3,"letter",Bond.POST_LOCKED,"picnic"],
		["lingpopo",2,"",Bond.BELL_LOCKED,"picnic"],["lingpopo",3,"salad",Bond.BELL_LOCKED,"picnic"],["achao",1,"",Bond.DOCK_LOCKED,"dock_stage"]]
	for spec:Array in specs:
		var resident:=str(spec[0])
		var stage:=int(spec[1])
		var option:=str(spec[2])
		var gate:=str(spec[3])
		var tag:="gate %s %d"%[resident,stage]
		var e:Dictionary=Goals.goal(resident,stage)
		var w:=World.new()
		var t:="goal-gate-token"
		w.add_player(t,"甲")
		expect(w.state.get("picnic",false)!=true and int(w.state.get("dock_stage",0))==0,tag+": fresh world has no picnic and no dock repair")
		var region:=region_of(w,resident)
		var cell:=cell_of(w,resident)
		go(w,t,region,cell)
		set_points(w,t,resident,int(Bond.THRESHOLDS[stage-1]))
		var cost:Dictionary=Goals.cost(e,option)
		fill(w,t,cost,0)
		var good:=extra_of(resident,stage,option,right_steps(e))
		refuse(w,t,cell,good,gate,tag+": before the gate opens")
		if str(spec[4])=="picnic":w.state["dock_stage"]=1
		else:w.state["picnic"]=true
		cell=cell_of(w,resident)
		go(w,t,region,cell)
		refuse(w,t,cell,good,gate,tag+": the other gate does not open it")
		if str(spec[4])=="picnic":w.state["picnic"]=true
		else:w.state["dock_stage"]=1
		cell=cell_of(w,resident)
		go(w,t,region,cell)
		# PRESET: luoluo 3 waits for 〈沒有地址的信〉 (postcard_reported); the gate test is about presence only.
		var gate_needs:Array=e.get("needs",[])
		for need:String in gate_needs:set_need(w,t,need,true)
		var want_gate:Dictionary={resident:{str(stage):option}}
		if "postcard_reported" in gate_needs:want_gate["luoluo"]["2"]=""
		var r:=do_goal(w,t,cell,good)
		expect(bool(r.get("ok",false)) and same(pl(w,t).get(Goals.RECORD_KEY),want_gate),"%s: once present the same request succeeds (got '%s')"%[tag,msg(r)])

# ------------------------------------------- needs: need_met / need_label --

func test_need_rules()->void:
	var me:="goal-need-self"
	var other:="goal-need-other"
	# own_bed
	var objects:Dictionary={}
	var s:Dictionary={"players":{me:{},other:{}},"objects":objects}
	expect(not Goals.need_met("own_bed",s,me),"own_bed: no bed -> false")
	objects["3,4"]={"type":"bed","owner":other,"items":{}}
	expect(not Goals.need_met("own_bed",s,me),"own_bed: a bed owned by another token -> false")
	expect(Goals.need_met("own_bed",s,other),"own_bed: that bed counts for its owner")
	objects["5,4"]={"type":"chest","owner":me,"items":{}}
	objects["6,4"]={"type":"bench","owner":me,"items":{}}
	expect(not Goals.need_met("own_bed",s,me),"own_bed: own objects that are not a bed -> false")
	objects["7,4"]={"type":"bed","owner":me,"items":{}}
	expect(Goals.need_met("own_bed",s,me),"own_bed: own bed -> true")
	expect(not Goals.need_met("own_bed",{"players":{me:{}}},me),"own_bed: no objects layer -> false")
	expect(not Goals.need_met("own_bed",{"players":{"":{}},"objects":{"1,1":{"type":"bed","owner":""}}},""),"own_bed: an empty token never matches")
	# glass_crafted
	for sample:Array in [[{},"missing"],[{"greenhouse_glass_crafted":false},"false"],[{"greenhouse_glass_crafted":1},"int 1"],[{"greenhouse_glass_crafted":"true"},"string 'true'"]]:
		expect(not Goals.need_met("glass_crafted",{"players":{me:sample[0]}},me),"glass_crafted: %s -> false"%str(sample[1]))
	expect(Goals.need_met("glass_crafted",{"players":{me:{"greenhouse_glass_crafted":true}}},me),"glass_crafted: true -> true")
	expect(not Goals.need_met("glass_crafted",{"players":{other:{"greenhouse_glass_crafted":true}}},me),"glass_crafted: another player's glass does not count")
	expect(not Goals.need_met("glass_crafted",{},me),"glass_crafted: no players table -> false")
	# market_round
	for sample:Array in [[{},"no market"],[{"market":MarketStall.fresh()},"fresh market, empty report"],[{"market":{"report":{}}},"empty report"],
			[{"market":"open"},"market not a dictionary"],[{"market":{"report":[1]}},"report a list"],[{"market":{"report":"x"}},"report a string"],[{"market":{}},"market without report"]]:
		expect(not Goals.need_met("market_round",{"players":{me:sample[0]}},me),"market_round: %s -> false"%str(sample[1]))
	expect(Goals.need_met("market_round",{"players":{me:{"market":market_with_report()}}},me),"market_round: non-empty report -> true")
	expect(Goals.need_met("market_round",{"players":{me:{"market":{"report":{"day":0}}}}},me),"market_round: any non-empty report dictionary -> true")
	expect(not Goals.need_met("market_round",{"players":{other:{"market":market_with_report()}}},me),"market_round: another player's report does not count")
	# festival_done (island-wide; the token need not be a player)
	expect(not Goals.need_met("festival_done",{"players":{me:{}}},me),"festival_done: missing festival -> false")
	expect(not Goals.need_met("festival_done",{"festival":"done"},me),"festival_done: festival not a dictionary -> false")
	expect(not Goals.need_met("festival_done",{"festival":festival_at(0,false)},me),"festival_done: round 0 -> false")
	expect(not Goals.need_met("festival_done",{"festival":festival_at(1,true)},me),"festival_done: round 1 still active -> false")
	expect(Goals.need_met("festival_done",{"festival":festival_at(1,false)},me),"festival_done: round 1 finished -> true")
	expect(Goals.need_met("festival_done",{"festival":festival_at(2,true)},me),"festival_done: round 2 active (round 1 finished before) -> true")
	expect(Goals.need_met("festival_done",{"festival":festival_at(3,false)},"someone-absent"),"festival_done: counts for a token that is not even a player")
	# known_three
	var person:Dictionary={"bonds":{"luoluo":rec(24,-1,-1)}}
	var ks:Dictionary={"players":{me:person}}
	var known_label:=str(NEED_TEXT["known_three"])
	expect(not Goals.need_met("known_three",ks,me) and Goals.known_count(person,"luoluo")==0,"known_three: luoluo's own bond does not count")
	expect(Goals.need_label("known_three",ks,me)==known_label+"（目前 0 位）","known_three label with luoluo only: 0 (%s)"%Goals.need_label("known_three",ks,me))
	var bonds:Dictionary=person["bonds"]
	bonds["aru"]=rec(1,-1,-1)
	bonds["milu"]=rec(1,-1,-1)
	bonds["achao"]=rec(0,-1,-1)
	expect(not Goals.need_met("known_three",ks,me),"known_three: two others (plus one at 0 points) -> false")
	expect(Goals.need_label("known_three",ks,me)==known_label+"（目前 2 位）","known_three label: 2 (%s)"%Goals.need_label("known_three",ks,me))
	bonds["bobo"]=rec(1,-1,-1)
	expect(Goals.need_met("known_three",ks,me),"known_three: three others -> true")
	expect(Goals.need_label("known_three",ks,me)==known_label+"（目前 3 位）","known_three label: 3 (%s)"%Goals.need_label("known_three",ks,me))
	bonds["chacha"]=rec(6,-1,-1)
	bonds["diandian"]=rec(24,-1,-1)
	expect(Goals.need_met("known_three",ks,me) and Goals.known_count(person,"luoluo")==5,"known_three: five others -> true (known_count 5)")
	expect(Goals.need_label("known_three",ks,me)==known_label+"（目前 3 位）","known_three label is capped at 3 (%s)"%Goals.need_label("known_three",ks,me))
	expect(Goals.need_label("known_three",{},me)==known_label+"（目前 0 位）","known_three label without state: 0")
	expect(not Goals.need_met("known_three",{"players":{other:person}},me),"known_three: another player's bonds do not count")
	# postcard_clues: only the own string array counts (0..3, distinct), independent of the bonds above.
	expect(Goals.POSTCARD_CLUES_KEY==CLUES_KEY,"POSTCARD_CLUES_KEY is luoluo_postcard_clues")
	expect(not Goals.need_met(CLUES_NEED,ks,me) and Goals.need_label(CLUES_NEED,ks,me)==CLUES_TEXT%0,"postcard_clues: no field -> 0 (%s)"%Goals.need_label(CLUES_NEED,ks,me))
	var clue_sets:Array=[[[],0],[["aru"],1],[["aru","aru"],1],[["aru","milu"],2],[["aru","milu","bobo"],3],[["aru","milu","bobo","chacha"],3]]
	for sample:Array in clue_sets:
		var cs:Dictionary={"players":{me:{CLUES_KEY:sample[0],"bonds":{}}}}
		var n:int=int(sample[1])
		expect(Goals.need_label(CLUES_NEED,cs,me)==CLUES_TEXT%n and Goals.need_met(CLUES_NEED,cs,me)==(n>=3),"postcard_clues: %s -> %d (%s)"%[str(sample[0]),n,Goals.need_label(CLUES_NEED,cs,me)])
	expect(not Goals.need_met(CLUES_NEED,{"players":{me:{CLUES_KEY:"aru"}}},me) and not Goals.need_met(CLUES_NEED,{"players":{other:{CLUES_KEY:["aru","milu","bobo"]}}},me),"postcard_clues: wrong type / another player's field -> false")
	expect(not Goals.need_met(CLUES_NEED,{},me) and Goals.need_label(CLUES_NEED,{},me)==CLUES_TEXT%0,"postcard_clues: no state -> 0")
	# postcard_reported: only the own record of luoluo stage 2 counts; false without an own player.
	var report_need:="postcard_reported"
	expect(Goals.NEEDS.get(report_need)==NEED_TEXT[report_need] and Goals.need_label(report_need,{},me)==need_text(report_need),"postcard_reported: the published label")
	expect(not Goals.need_met(report_need,{"players":{me:{"bond_goals":{"luoluo":{"1":""}}}}},me),"postcard_reported: luoluo stage 1 only -> false")
	expect(not Goals.need_met(report_need,{"players":{me:{"bond_goals":{"luoluo":{"3":"aloud"}}}}},me),"postcard_reported: stage 3 alone -> false")
	expect(not Goals.need_met(report_need,{"players":{me:{"bond_goals":{"aru":{"2":""}}}}},me),"postcard_reported: another resident's stage 2 -> false")
	expect(Goals.need_met(report_need,{"players":{me:{"bond_goals":{"luoluo":{"2":""}}}}},me),"postcard_reported: own luoluo stage 2 done -> true")
	expect(not Goals.need_met(report_need,{"players":{other:{"bond_goals":{"luoluo":{"2":""}}}}},me),"postcard_reported: another player's stage 2 does not count")
	expect(not Goals.need_met(report_need,{"players":{}},me) and not Goals.need_met(report_need,{},me),"postcard_reported: no own player -> false")
	# fair_weather: only state.time and the home region's weather matter.
	var rainy_day:=-1
	var dry_day:=-1
	for d in range(0,14):
		if Weather.rains(float(d),"home"):
			if rainy_day<0:rainy_day=d
		elif dry_day<0:dry_day=d
	if expect(rainy_day>=0 and dry_day>=0,"weather.gd cycle has a rainy and a dry home day (%d, %d)"%[rainy_day,dry_day]):
		var rainy_time:float=float(rainy_day)*Weather.DAY_SECONDS+30.0
		var dry_time:float=float(dry_day)*Weather.DAY_SECONDS+30.0
		expect(not Goals.need_met("fair_weather",{"players":{me:{"region":"home"}},"time":rainy_time},me),"fair_weather: rainy day -> false")
		expect(Goals.need_met("fair_weather",{"players":{me:{"region":"home"}},"time":dry_time},me),"fair_weather: non-rainy day -> true")
		expect(Goals.need_met("fair_weather",{"time":int(dry_time)},me),"fair_weather: int time works")
		expect(not Goals.need_met("fair_weather",{"players":{me:{}}},me),"fair_weather: no time -> false")
		expect(not Goals.need_met("fair_weather",{"time":"0"},me),"fair_weather: time not a number -> false")
		expect(not Weather.rains(float(rainy_day),"mine_1"),"control: mine_1 is indoor and never rains on the rainy day")
		expect(not Goals.need_met("fair_weather",{"players":{me:{"region":"mine_1"}},"time":rainy_time},me),"fair_weather: a player indoors still sees the home rain -> false")
		expect(Goals.need_met("fair_weather",{"players":{me:{"region":"mine_1"}},"time":dry_time},me),"fair_weather: player region does not matter on a dry day -> true")
	# Labels, unknown ids, needs_view.
	# bobo_cart_arrived: only the private integer 7 counts; own record only.
	var cart_state:Dictionary={"players":{me:{CART_FIELD:7},other:{CART_FIELD:0}}}
	expect(Goals.need_met(CART_NEED,cart_state,me),"bobo_cart_arrived: own stage 7 -> true")
	expect(not Goals.need_met(CART_NEED,cart_state,other),"bobo_cart_arrived: another player's arrival does not count")
	for stage_value:Variant in [0,1,3,6,8,-1,"7",true,null,[7]]:
		expect(not Goals.need_met(CART_NEED,{"players":{me:{CART_FIELD:stage_value}}},me),"bobo_cart_arrived: stage %s -> false"%str(stage_value))
	expect(not Goals.need_met(CART_NEED,{"players":{me:{}}},me) and not Goals.need_met(CART_NEED,{},me),"bobo_cart_arrived: absent stage / no players -> false")
	# diandian_seated: own bool true + own stage-1 record + bond stage >= 2; every piece is required.
	var seat_bonds:Dictionary={"diandian":rec(int(Bond.THRESHOLDS[1]),-1,-1)}
	var seat_ok:Dictionary={Goals.DIANDIAN_SEAT_KEY:true,"bonds":seat_bonds,"bond_goals":{"diandian":{"1":""}}}
	expect(Goals.DIANDIAN_SEAT_KEY=="diandian_seated","diandian_seated: the player field name")
	expect(Goals.need_met("diandian_seated",{"players":{me:seat_ok}},me),"diandian_seated: flag + stage 1 record + stage 2 -> true")
	expect(not Goals.need_met("diandian_seated",{"players":{me:seat_ok,other:{}}},other),"diandian_seated: another player's flag does not count")
	for seat_flag:Variant in [false,1,"true",null,[true]]:
		var odd_flag:Dictionary=seat_ok.duplicate(true)
		odd_flag[Goals.DIANDIAN_SEAT_KEY]=seat_flag
		expect(not Goals.need_met("diandian_seated",{"players":{me:odd_flag}},me),"diandian_seated: flag %s -> false"%str(seat_flag))
	var seat_no_record:Dictionary=seat_ok.duplicate(true)
	seat_no_record.erase("bond_goals")
	expect(not Goals.need_met("diandian_seated",{"players":{me:seat_no_record}},me),"diandian_seated: no stage 1 record -> false")
	var seat_short:Dictionary=seat_ok.duplicate(true)
	seat_short["bonds"]={"diandian":rec(int(Bond.THRESHOLDS[0]),-1,-1)}
	expect(not Goals.need_met("diandian_seated",{"players":{me:seat_short}},me),"diandian_seated: bond stage 1 only -> false")
	var seat_flagless:Dictionary=seat_ok.duplicate(true)
	seat_flagless.erase(Goals.DIANDIAN_SEAT_KEY)
	expect(not Goals.need_met("diandian_seated",{"players":{me:seat_flagless}},me),"diandian_seated: no flag -> false")
	# Existing saved diandian 2 (done, no flag) stays valid.
	expect(Goals.valid({"diandian":{"1":"","2":"knees"}},{"bonds":{"diandian":rec(24,-1,-1)},"bond_goals":{"diandian":{"1":"","2":"knees"}}}),"diandian_seated: an existing saved diandian 2 without the flag stays valid")
	for id:String in all_needs():
		if id!="known_three" and id!=CLUES_NEED:
			expect(Goals.need_label(id,{},me)==need_text(id),"need_label(%s) is the label"%id)
		expect(not Goals.need_met(id,{},me),"need_met(%s) with an empty state -> false"%id)
	expect(Goals.need_label("nope",{},me)=="nope" and not Goals.need_met("nope",s,me),"unknown need id: label is the id, never met")
	expect(Goals.needs_view(Goals.goal("aru",1),s,me)==[{"id":"own_bed","label":str(NEED_TEXT["own_bed"]),"met":true}],"needs_view aru 1 with an own bed")
	expect(Goals.needs_view(Goals.goal("aru",1),s,"goal-need-nobody")==[{"id":"own_bed","label":str(NEED_TEXT["own_bed"]),"met":false}],"needs_view aru 1 for a token without a bed")
	expect(Goals.needs_view(Goals.goal("milu",1),s,me).is_empty(),"needs_view of a goal without needs is empty")
	# view(): open/locked rows with needs reflect the state; done rows and goals without needs have no needs key.
	var viewer:Dictionary={"bonds":{"aru":rec(1,-1,-1),"luoluo":rec(6,-1,-1),"milu":rec(14,-1,-1)},"bond_goals":{"milu":{"1":""}}}
	var vs:Dictionary={"players":{me:viewer},"objects":{"9,9":{"type":"bed","owner":me,"items":{}}},"festival":festival_at(1,false),"time":dry_day*Weather.DAY_SECONDS+1.0}
	var v:Dictionary=Goals.view(viewer,vs,me)
	expect(v["aru"]["1"]==with_keepsake({"state":"open","choice":"","needs":[{"id":"own_bed","label":str(NEED_TEXT["own_bed"]),"met":true}]},"aru",1,false),"view: aru 1 open, own_bed met, keepsake unclaimed (%s)"%str(v["aru"]["1"]))
	expect(v["luoluo"]["2"]=={"state":"open","choice":"","needs":[{"id":"known_three","label":known_label+"（目前 2 位）","met":false},{"id":CLUES_NEED,"label":CLUES_TEXT%0,"met":false}]},"view: luoluo 2 open, known_three unmet with count 2, clues 0 (%s)"%str(v["luoluo"]["2"]))
	expect(v["lingpopo"]["4"]=={"state":"locked","choice":"","needs":[{"id":"festival_done","label":str(NEED_TEXT["festival_done"]),"met":true}],"keepsake":Goals.keepsake_view({},Goals.FESTIVAL_BELL_REWARD)},"view: lingpopo 4 locked, festival_done met (%s)"%str(v["lingpopo"]["4"]))
	expect(v["mianmian"]["4"]=={"state":"locked","choice":"","needs":[{"id":"sheep_step","label":str(NEED_TEXT["sheep_step"]),"met":false}]},"view: mianmian 4 locked, sheep_step unmet")
	expect(v["xinghe"]["3"]=={"state":"locked","choice":"","needs":[{"id":"glass_crafted","label":str(NEED_TEXT["glass_crafted"]),"met":false}]},"view: xinghe 3 locked, glass_crafted unmet")
	expect(v["xiaoli"]["3"]=={"state":"locked","choice":"","needs":[{"id":"xiaoli_cart_plan","label":str(NEED_TEXT["xiaoli_cart_plan"]),"met":false},{"id":"market_round","label":str(NEED_TEXT["market_round"]),"met":false}]},"view: xiaoli 3 locked, cart plan and market_round unmet")
	expect(v["milu"]["1"]=={"state":"done","choice":""} and v["milu"]["3"]==with_keepsake({"state":"open","choice":""},"milu",3,false) and v["aru"]["2"]=={"state":"locked","choice":""},"view: goals without needs carry no needs key")
	# FIXTURE: aru 1 written as done directly (no bond_keepsakes) -> keepsake unclaimed.
	viewer["bond_goals"]={"aru":{"1":""},"milu":{"1":""}}
	v=Goals.view(viewer,vs,me)
	expect(v["aru"]["1"]==with_keepsake({"state":"done","choice":""},"aru",1,false),"view: a done goal with needs carries no needs key (%s)"%str(v["aru"]["1"]))
	# apply() directly: state omitted -> needs unmet; need before items.
	var solo_person:Dictionary={"bonds":{"aru":rec(1,-1,-1)}}
	var inv:Dictionary={"wood":10}
	var parts:=PackedStringArray(["aru","1","",""])
	var r:Dictionary=Goals.apply(solo_person,inv,parts,World.NAMES)
	expect(not bool(r.get("ok",true)) and msg(r)==need_msg(str(NEED_TEXT["own_bed"])),"apply without state: needs unmet (got '%s')"%msg(r))
	expect(inv=={"wood":10} and not solo_person.has(Goals.RECORD_KEY),"apply refusal changes neither inventory nor record")
	var bed_state:Dictionary={"players":{"goal-need-tk":solo_person},"objects":{"1,1":{"type":"bed","owner":"goal-need-tk","items":{}}}}
	var empty_inv:Dictionary={}
	r=Goals.apply(solo_person,empty_inv,parts,World.NAMES,{"players":{"goal-need-tk":solo_person}},"goal-need-tk")
	expect(not bool(r.get("ok",true)) and msg(r)==need_msg(str(NEED_TEXT["own_bed"])),"apply: need unmet and wood missing -> need message (got '%s')"%msg(r))
	r=Goals.apply(solo_person,empty_inv,parts,World.NAMES,bed_state,"goal-need-tk")
	expect(not bool(r.get("ok",true)) and msg(r)==short_msg("wood",0,10),"apply: need met, wood missing -> items message (got '%s')"%msg(r))
	r=Goals.apply(solo_person,inv,parts,World.NAMES,bed_state,"goal-need-tk")
	expect(bool(r.get("ok",false)) and inv=={"wood":0,"keepsake_aru_kit":1} and solo_person.get(Goals.RECORD_KEY)=={"aru":{"1":""}},"apply with state and an own bed succeeds, granting the aru kit (got '%s', %s)"%[msg(r),str(inv)])
	expect(solo_person.get(Goals.KEEPSAKE_KEY)=={"keepsake_aru":true} and msg(r)==goal_msg("aru",1),"apply aru 1: bond_keepsakes written and keepsake sentence appended")

# ---------------------------------------------- needs through World.act --

func test_animal_sketches()->void:
	var w:=World.new()
	w.save_path=temp_path("animal-sketches")
	w.add_player(KIM,"畫家")
	set_points(w,KIM,"diandian",1)
	var cow:Vector2i=World.LIVESTOCK.ANIMALS.cow.cell
	go(w,KIM,"home",cow)
	expect(not w.act(KIM,"locked-cow",Goals.SKETCH_ACTION,cow,"cow").ok,"Pasture animal requires the opened pasture")
	w.state.picnic=true
	w.state.community={"table":World.COMMUNITY.choose_table(w.state)}
	expect(not w.act(KIM,"wrong-tile",Goals.SKETCH_ACTION,cow,"chicken").ok,"An animal sketch must target the right animal")
	expect(not w.act(KIM,"unknown-animal",Goals.SKETCH_ACTION,cow,"dog").ok,"Unknown animals cannot enter the journal")
	expect(not w.act(KIM,"empty-cow",Goals.SKETCH_ACTION,cow,"cow").ok,"An unadopted cow cannot be observed")
	expect(w.act(KIM,"adopt-cow", "livestock_adopt", cow,"cow").ok,"Adoption brings the cow to the shared station")
	var animal_records:Dictionary=w.state.livestock.duplicate(true)
	for id:String in ["chicken","cow","sheep"]:
		var at:Vector2i=World.CHICKEN_CELL if id=="chicken" else World.LIVESTOCK.ANIMALS[id].cell
		go(w,KIM,"home",at)
		var before:Dictionary=pl(w,KIM).inventory.duplicate(true)
		expect(w.act(KIM,"sketch-"+id,Goals.SKETCH_ACTION,at,id).ok,"Observe "+id)
		expect(not w.act(KIM,"repeat-"+id,Goals.SKETCH_ACTION,at,id).ok,"The same animal counts once")
		expect(pl(w,KIM).inventory==before,"Observation does not spend feed or grant a product")
	var duck:Vector2i=World.LIVESTOCK.ANIMALS.duck.cell
	go(w,KIM,"home",duck)
	expect(not w.act(KIM,"fourth-sketch",Goals.SKETCH_ACTION,duck,"duck").ok,"A fourth subject cannot exceed the sketchbook cap")
	var alternate:=World.new()
	alternate.add_player(KIM,"畫家")
	set_points(alternate,KIM,"diandian",1)
	alternate.state.picnic=true
	go(alternate,KIM,"home",duck)
	expect(alternate.act(KIM,"sketch-duck",Goals.SKETCH_ACTION,duck,"duck").ok
		and pl(alternate,KIM).get(Goals.SKETCH_KEY,{})=={"duck":true},"The river duck can count as one of the three subjects")
	expect(w.save() and w.load_world(w.save_path),"The animal-only record reloads")
	expect(Goals.need_met("crop_sketches",w.state,KIM),"Three animals meet the same goal")
	expect(int(w.state.animal.bond)==0 and same(w.state.livestock,animal_records),"Observation preserves animal care state across reload")

func test_crop_sketches()->void:
	var w:=World.new()
	w.save_path=temp_path("crop-sketches")
	w.add_player(KIM,"畫家")
	w.add_player(SAM,"農夫")
	var target:=Vector2i(38,34)
	go(w,KIM,"home",target)
	expect(not w.act(KIM,"not-known",Goals.SKETCH_ACTION,target).ok,"Sketching is unlocked by meeting Diandian")
	set_points(w,KIM,"diandian",1)
	expect(not w.act(KIM,"empty-plant",Goals.SKETCH_ACTION,target).ok,"Bare ground does not count as a crop")
	go(w,SAM,"home",target)
	for kind:String in ["radish","lettuce","wheat"]:
		expect(w.act(SAM,"till-"+kind,"hoe",target).ok,"The farmer tills a plot")
		expect(w.act(SAM,"seed-"+kind,"seed",target,kind).ok,"The farmer plants "+kind)
		expect(w.act(KIM,"draw-"+kind,Goals.SKETCH_ACTION,target).ok,"A neighbor can draw the living seedling")
		expect(not w.act(KIM,"again-"+kind,Goals.SKETCH_ACTION,target).ok,"The same species cannot be counted twice")
		expect(not pl(w,SAM).has(Goals.SKETCH_KEY),"Drawing does not grant the planter progress")
		expect(w.state.crops[World.key(target)].kind==kind,"Drawing leaves the crop intact")
		target+=Vector2i.RIGHT
	expect(w.save() and w.load_world(w.save_path),"The three observations survive reload")
	expect(Goals.need_met("crop_sketches",w.state,KIM),"Three different observations meet Diandian's goal")
	var at:=cell_of(w,"diandian")
	go(w,KIM,"star_garden",at)
	expect(do_goal(w,KIM,at,"diandian:1::").ok,"Player can show the drawings to Diandian")

func test_milu_shared_meal()->void:
	var w:=World.new()
	w.save_path=temp_path("shared-meal")
	w.state.picnic=true
	w.state.community={"table":World.COMMUNITY.choose_table(w.state)}
	var table:=World.COMMUNITY.table_cell(w.state)
	for token in [KIM,SAM]:
		w.add_player(token,token)
		set_points(w,token,"milu",24)
		go(w,token,"home",table+Vector2i.DOWN)
	set_item(w,KIM,"corn_chowder",3)
	expect(not w.act(KIM,"short","serve_chowder",table).ok and not Goals.need_met("shared_meal",w.state,KIM),"Three servings cannot complete the milestone")
	set_item(w,KIM,"corn_chowder",4)
	expect(w.act(KIM,"serve","serve_chowder",table).ok and Goals.need_met("shared_meal",w.state,KIM),"Personally setting four bowls on the table counts")
	expect(w.act(SAM,"claim","claim_chowder",table).ok and not Goals.need_met("shared_meal",w.state,SAM),"Someone who only claims a bowl gets no serving credit")
	expect(w.load_world(w.save_path),"Meal participation survives a save and reload")
	var at:=cell_of(w,"milu")
	go(w,KIM,"home",at)
	expect(do_goal(w,KIM,at,"milu:4::").ok and Goals.done(pl(w,KIM),"milu").has(4),"A single player can finish without other seats filled")
	go(w,SAM,"home",at)
	expect(not do_goal(w,SAM,at,"milu:4::").ok,"The guest cannot complete the host's goal")
	expect(not w.act(SAM,"apron-locked",Goals.APRON_ACTION,at).ok,"The guest cannot equip the host's reward")
	expect(w.act(KIM,"apron-equip",Goals.APRON_ACTION,at).ok and pl(w,KIM).get(Goals.APRON_KEY,false),"Finishing the goal unlocks an opt-in outfit")
	expect(w.load_world(w.save_path) and pl(w,KIM).get(Goals.APRON_KEY,false),"Apron remains equipped after loading")
	var damaged:Dictionary=w.state.duplicate(true)
	damaged.players[SAM][Goals.APRON_KEY]=true
	expect(not World.SAVE_SCHEMA.validate(damaged,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Save rejects an equipped apron with no unlock")
	expect(w.act(KIM,"apron-unequip",Goals.APRON_ACTION,at).ok and not pl(w,KIM).has(Goals.APRON_KEY),"Unequip the apron without losing its unlock")

func test_xiaoli_trade()->void:
	var w:=World.new()
	w.save_path=temp_path("xiaoli-trade")
	var stall:=Vector2i(43,29)
	for token in [KIM,SAM]:
		w.add_player(token,token)
		set_points(w,token,"xiaoli",1)
		go(w,token,"home",stall)
		set_item(w,token,"radish",1)
	expect(w.act(KIM,"early-seed","buy",stall,"radish").ok,"Buy a seed before selling")
	expect(not Goals.need_met("seed_after_sale",w.state,KIM),"Early seed cannot satisfy the trade")
	expect(w.act(KIM,"crop-sale","sell",stall,"radish").ok,"Sell a crop at Xiaoli's stall")
	expect(Goals.need_met("crop_sold",w.state,KIM) and not Goals.need_met("seed_after_sale",w.state,KIM),"Sale unlocks only step one")
	expect(w.act(KIM,"off-season","buy",stall,"tomato").ok,"The shop still sells out-of-season seeds")
	expect(not Goals.need_met("seed_after_sale",w.state,KIM),"Out-of-season seed does not finish the event")
	expect(w.load_world(w.save_path),"Reload the completed sale")
	expect(w.act(KIM,"in-season","buy",stall,"radish").ok and Goals.need_met("seed_after_sale",w.state,KIM),"A seasonal seed after the sale completes step two")
	expect(not Goals.need_met("crop_sold",w.state,SAM),"Other players have their own trade progress")
	var ship:=World.SHIPPING.cell_for(w.state)
	go(w,SAM,"home",ship)
	expect(w.act(SAM,"box-sale","ship",ship,JSON.stringify([[["radish",1]],24])).ok and Goals.need_met("crop_sold",w.state,SAM),"Shipping a crop also counts")
	var at:=cell_of(w,"xiaoli")
	go(w,KIM,"home",at)
	expect(do_goal(w,KIM,at,"xiaoli:1::").ok,"Xiaoli records the completed trade")

func test_chicken_goal()->void:
	var w:=World.new()
	w.save_path=temp_path("hen")
	w.state.picnic=true
	for token in [KIM,SAM]:
		w.add_player(token,token)
		set_points(w,token,"mianmian",1)
		go(w,token,"home",World.CHICKEN_CELL)
	set_item(w,KIM,"feed",1)
	expect(not w.act(SAM,"no-feed","feed",World.CHICKEN_CELL).ok,"The chicken refuses a player without feed")
	expect(w.act(KIM,"real-feed","feed",World.CHICKEN_CELL).ok,"Feed the real chicken through World.act")
	expect(not Goals.need_met("chicken_fed",w.state,KIM),"The chicken does not approach immediately")
	var at:=cell_of(w,"mianmian")
	go(w,KIM,"home",at)
	expect(not do_goal(w,KIM,at,"mianmian:1::").ok,"Reporting too early leaves the event unfinished")
	expect(w.step(Goals.CHICKEN_APPROACH_SECONDS,true),"Wait for the chicken to approach")
	expect(w.save() and w.load_world(w.save_path),"Feeding and approach progress survive a reload")
	expect(Goals.need_met("chicken_fed",w.state,KIM) and not Goals.need_met("chicken_fed",w.state,SAM),"Feeding only counts for the player who fed it")
	go(w,KIM,"home",at)
	expect(do_goal(w,KIM,at,"mianmian:1::").ok,"Report back to Mianmian without another bag of feed")
	expect(int(pl(w,KIM).inventory.get("feed",0))==0,"The single feeding used only one bag")

func test_needs_through_world()->void:
	var w:=World.new()
	w.state["picnic"]=true  # PRESET
	w.state["dock_stage"]=1  # PRESET
	# own_bed (aru 1)
	var t:="goal-act-bed"
	var o:="goal-act-bed-other"
	var cell:=ready_player(w,t,"aru",1,"")
	var bed_msg:=need_msg(str(NEED_TEXT["own_bed"]))
	refuse(w,t,cell,"aru:1::",bed_msg,"act own_bed: no bed")
	w.add_player(o,"乙")
	put_object(w,o,"bed")
	refuse(w,t,cell,"aru:1::",bed_msg,"act own_bed: only another player's bed")
	put_object(w,t,"chest")
	put_object(w,t,"bench")
	refuse(w,t,cell,"aru:1::",bed_msg,"act own_bed: own chest and bench, no bed")
	put_object(w,t,"bed")
	var r:=do_goal(w,t,cell,"aru:1::")
	expect(bool(r.get("ok",false)) and msg(r)==goal_msg("aru",1),"act own_bed: own bed -> accepted (got '%s')"%msg(r))
	expect(pl(w,t).get(Goals.RECORD_KEY)=={"aru":{"1":""}} and int(pl(w,t).inventory.get("wood",-1))==0,"act own_bed: record written, 10 wood paid")
	# The other player's bed counts for them.
	go(w,o,"home",cell)
	set_points(w,o,"aru",1)
	set_item(w,o,"wood",10)
	r=do_goal(w,o,cell,"aru:1::")
	expect(bool(r.get("ok",false)),"act own_bed: the other player's own bed counts for them (got '%s')"%msg(r))
	# glass_crafted (xinghe 3)
	t="goal-act-glass"
	cell=ready_player(w,t,"xinghe",3,"")
	var glass_msg:=need_msg(str(NEED_TEXT["glass_crafted"]))
	var p:Dictionary=pl(w,t)
	p.erase("greenhouse_glass_crafted")
	refuse(w,t,cell,"xinghe:3::",glass_msg,"act glass_crafted: missing")
	for bad:Variant in [false,1,"true"]:
		p["greenhouse_glass_crafted"]=bad
		refuse(w,t,cell,"xinghe:3::",glass_msg,"act glass_crafted: %s"%str(bad))
	p["greenhouse_glass_crafted"]=true
	r=do_goal(w,t,cell,"xinghe:3::")
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"xinghe":{"3":""}},"act glass_crafted: true -> accepted (got '%s')"%msg(r))
	# market_round (xiaoli 3)
	t="goal-act-market"
	cell=ready_player(w,t,"xiaoli",3,"")
	set_need(w,t,"xiaoli_cart_plan",true)
	var market_msg:=need_msg(str(NEED_TEXT["market_round"]))
	p=pl(w,t)
	p.erase("market")
	refuse(w,t,cell,"xiaoli:3::",market_msg,"act market_round: no market")
	p["market"]=MarketStall.fresh()
	refuse(w,t,cell,"xiaoli:3::",market_msg,"act market_round: empty report")
	p["market"]="open"
	refuse(w,t,cell,"xiaoli:3::",market_msg,"act market_round: market not a dictionary")
	p["market"]=market_with_report()
	r=do_goal(w,t,cell,"xiaoli:3::")
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"xiaoli":{"2":"tree","3":""}},"act market_round: non-empty report -> accepted (got '%s')"%msg(r))
	# festival_done (lingpopo 4)
	t="goal-act-festival"
	cell=ready_player(w,t,"lingpopo",4,"")
	var festival_msg:=need_msg(str(NEED_TEXT["festival_done"]))
	w.state["festival"]=festival_at(0,false)
	refuse(w,t,cell,"lingpopo:4::",festival_msg,"act festival_done: round 0")
	w.state["festival"]=festival_at(1,true)
	refuse(w,t,cell,"lingpopo:4::",festival_msg,"act festival_done: round 1 active")
	w.state["festival"]=festival_at(1,false)
	r=do_goal(w,t,cell,"lingpopo:4::")
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"lingpopo":{"4":""}},"act festival_done: round 1 finished -> accepted (got '%s')"%msg(r))
	var t2:="goal-act-festival-two"
	cell=ready_player(w,t2,"lingpopo",4,"")
	w.state["festival"]=festival_at(2,true)
	r=do_goal(w,t2,cell,"lingpopo:4::")
	expect(bool(r.get("ok",false)) and pl(w,t2).get(Goals.RECORD_KEY)=={"lingpopo":{"4":""}},"act festival_done: round 2 active -> accepted (got '%s')"%msg(r))
	# known_three (luoluo 2)
	t="goal-act-known"
	cell=ready_player(w,t,"luoluo",2,"")
	var known_label:=str(NEED_TEXT["known_three"])
	refuse(w,t,cell,"luoluo:2::",need_msg(known_label+"（目前 0 位）"),"act known_three: only luoluo known")
	set_points(w,t,"aru",1)
	set_points(w,t,"milu",1)
	set_points(w,t,"achao",0)
	refuse(w,t,cell,"luoluo:2::",need_msg(known_label+"（目前 2 位）"),"act known_three: two others known")
	set_points(w,t,"bobo",1)
	var clue_msg:=need_msg(CLUES_TEXT%0)
	refuse(w,t,cell,"luoluo:2::",clue_msg,"act postcard_clues: three known but no clues")
	pl(w,t)[CLUES_KEY]=["aru","aru"]
	refuse(w,t,cell,"luoluo:2::",need_msg(CLUES_TEXT%1),"act postcard_clues: duplicate clue counts once")
	pl(w,t)[CLUES_KEY]=["aru","milu"]
	refuse(w,t,cell,"luoluo:2::",need_msg(CLUES_TEXT%2),"act postcard_clues: two clues")
	pl(w,t)[CLUES_KEY]=["aru","milu","bobo"]
	r=do_goal(w,t,cell,"luoluo:2::")
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"luoluo":{"2":""}},"act postcard_clues: three known + three clues -> accepted (got '%s')"%msg(r))
	# postcard_reported (luoluo 3): option/steps syntax first, then the need, then the (free) completion.
	t="goal-act-report"
	cell=ready_player(w,t,"luoluo",3,"aloud")
	var report_msg:=need_msg(need_text("postcard_reported"))
	refuse(w,t,cell,"luoluo:3:nope:",MSG_PICK,"act postcard_reported: bad option and need unmet -> option message")
	refuse(w,t,cell,"luoluo:3:aloud:012",MSG_REOPEN,"act postcard_reported: stray steps and need unmet -> reopen message")
	refuse(w,t,cell,"luoluo:3:aloud:",report_msg,"act postcard_reported: valid option before luoluo 2 is done -> need message")
	refuse(w,t,cell,"luoluo:3:letter:",report_msg,"act postcard_reported: the other valid option before luoluo 2 is done -> need message")
	set_need(w,t,"postcard_reported",true)
	r=do_goal(w,t,cell,"luoluo:3:aloud:")
	expect(bool(r.get("ok",false)) and same(pl(w,t).get(Goals.RECORD_KEY),{"luoluo":{"2":"","3":"aloud"}}),"act postcard_reported: luoluo 2 done -> accepted at no cost (got '%s')"%msg(r))
	# sheep_step (mianmian 4): needs the player's own watch, six world seconds old.
	t="goal-act-sheep"
	cell=ready_player(w,t,"mianmian",4,"")
	var sheep_msg:=need_msg(str(NEED_TEXT["sheep_step"]))
	refuse(w,t,cell,"mianmian:4::",sheep_msg,"act sheep_step: not watched")
	pl(w,t)[Goals.SHEEP_STEP_KEY]=float(w.state.time)
	refuse(w,t,cell,"mianmian:4::",sheep_msg,"act sheep_step: watched just now")
	pl(w,t)[Goals.SHEEP_STEP_KEY]=float(w.state.time)-Goals.SHEEP_STEP_SECONDS
	cell=cell_of(w,"mianmian")
	go(w,t,"home",cell)
	r=do_goal(w,t,cell,"mianmian:4::")
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"mianmian":{"4":""}},"act sheep_step: watched six seconds ago -> accepted (got '%s')"%msg(r))
	# bobo_cart_arrived (bobo 4): only the arrived stage 7 opens it; the option and cost rules are unchanged (PRESET stage).
	t="goal-act-cart"
	cell=ready_player(w,t,"bobo",4,"home")
	var cart_msg:=need_msg(need_text(CART_NEED))
	refuse(w,t,cell,"bobo:4:home:",cart_msg,"act bobo_cart_arrived: no stage")
	for stage_value:int in [1,4,6]:
		pl(w,t)[CART_FIELD]=stage_value
		refuse(w,t,cell,"bobo:4:home:",cart_msg,"act bobo_cart_arrived: still pushing at stage %d"%stage_value)
	pl(w,t)[CART_FIELD]=7
	refuse(w,t,cell,"bobo:4::",MSG_PICK,"act bobo_cart_arrived: arrived but no inscription chosen")
	refuse(w,t,cell,"bobo:4:nope:",MSG_PICK,"act bobo_cart_arrived: arrived but an unknown inscription")
	var cart_coins:=int(pl(w,t).get("coins",0))
	r=do_goal(w,t,cell,"bobo:4:name:")
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"bobo":{"4":"name"}},"act bobo_cart_arrived: arrived + inscription 'name' -> accepted (got '%s')"%msg(r))
	expect(kit_counts(pl(w,t))=={CART_ITEM:1} and pl(w,t).get(Goals.KEEPSAKE_KEY)=={CART_KIND:true} and int(pl(w,t).get("coins",0))==cart_coins,"act bobo_cart_arrived: one cart kit, no coins")
# ------------------------------ needs checked once, batch-2 save round trip --

func test_needs_once_and_save()->void:
	var path:=temp_path("needs")
	var w:=World.new()
	w.save_path=path
	w.state["picnic"]=true  # PRESET
	w.state["time"]=Weather.DAY_SECONDS+100.0  # PRESET: day 1 (a day-0 market report is then valid)
	move_weather(w,false)
	w.add_player(KIM,"金")
	var p:Dictionary=pl(w,KIM)
	var home_x:float=float(p.x)
	var home_y:float=float(p.y)
	for pair:Array in [["aru",1],["xinghe",14],["xiaoli",24],["lingpopo",24],["luoluo",24],["mianmian",24],["bobo",24],["nuannuan",24]]:
		set_points(w,KIM,str(pair[0]),int(pair[1]))
	for pair:Array in [["wood",10],["glass",2],["copper_joint",2],["plank",2],["feed",1]]:
		set_item(w,KIM,str(pair[0]),int(pair[1]))
	for need:String in all_needs():
		if need=="diandian_seated":continue # No diandian goal is done in this save fixture; its bare stage-1 seed would alter the expected records.
		if need in ["xiaoli_return_guest","postcard_reported","memory_shared"]:continue # The story events below earn these prerequisites (luoluo 3 is a real spec before luoluo 4).
		set_need(w,KIM,need,true)
		expect(Goals.need_met(need,w.state,KIM),"save preset: %s holds"%need)
	var specs:Array=[["aru",1,""],["mianmian",4,""],["mianmian",1,""],["xinghe",3,""],["xiaoli",3,""],["xiaoli",4,"chestnut"],
		["lingpopo",4,""],["luoluo",2,""],["luoluo",3,"aloud"],["luoluo",4,"stay"],["bobo",4,"rest"],["nuannuan",4,"porch"]]
	var want:Dictionary={"xiaoli":{"1":"","2":"tree"}}
	for spec:Array in specs:
		var resident:=str(spec[0])
		var stage:=int(spec[1])
		var option:=str(spec[2])
		var cell:=cell_of(w,resident)
		go(w,KIM,region_of(w,resident),cell)
		var r:=do_goal(w,KIM,cell,extra_of(resident,stage,option,""))
		expect(bool(r.get("ok",false)),"save: %s %d '%s' done (got '%s')"%[resident,stage,option,msg(r)])
		var own:Dictionary=want.get(resident,{})
		own[str(stage)]=option
		want[resident]=own
	p=pl(w,KIM)
	p["region"]="home"
	p["x"]=home_x
	p["y"]=home_y
	expect(same(goals_of(w,KIM),want),"all eleven batch-2 goals recorded (%s)"%str(goals_of(w,KIM)))
	var held:Dictionary=p.inventory
	expect(int(held.get("wood",-1))==0 and int(held.get("glass",-1))==0 and int(held.get("copper_joint",-1))==0 and int(held.get("plank",-1))==0 and int(held.get("feed",-1))==1,"batch-2 costs paid exactly; no extra charge for feed")
	# Batch 3 (granted through World.act above): aru 1, xiaoli 4 and luoluo 4 carry keepsakes.
	var want_kits:Dictionary={"keepsake_aru_kit":1,"keepsake_xiaoli_kit":1,"keepsake_luoluo_kit":1,"keepsake_lingpopo_memorial_kit":1,"keepsake_nuannuan_room_kit":1,CART_ITEM:1}
	var want_keepsakes:Dictionary={"keepsake_aru":true,"keepsake_xiaoli":true,"keepsake_luoluo":true,"keepsake_lingpopo_memorial":true,"keepsake_nuannuan_room":true,CART_KIND:true}
	expect(kit_counts(p)==want_kits,"exactly the six earned kits granted, bobo 4 gives the cart kit (%s)"%str(kit_counts(p)))
	expect(same(p.get(Goals.KEEPSAKE_KEY),want_keepsakes),"bond_keepsakes holds exactly those six kinds (%s)"%str(p.get(Goals.KEEPSAKE_KEY)))
	# Undo every prerequisite: remove the bed, start a new festival round, rainy day, etc.
	clear_beds(w,KIM)
	p["greenhouse_glass_crafted"]=false
	p.erase("market")
	p.erase(Goals.CHICKEN_FED_KEY)
	p.erase(Goals.SHEEP_STEP_KEY)
	p.erase(Goals.CROP_TRADE_KEY)
	p.erase("resident_participation")
	p.erase(Goals.SKETCH_KEY)
	p.erase(Goals.ROUTE_KEY)
	p.erase(Goals.RECIPE_PAGE_KEY)
	p.erase(Goals.REST_KIT_KEY)
	p.erase(CART_FIELD)
	p.erase(CLUES_KEY)
	p.erase(Goals.BELL_INSPECT_KEY)
	p.erase(Goals.GUEST_ROOM_KEY)
	p.erase(Goals.INN_CLEAR_KEY)
	p.erase(World.WARM_SPRINGS.CRACK_KEY)
	p.erase(Goals.ADDRESS_KEY)
	p.erase(Goals.GROWTH_LOG_KEY)
	p.erase(Goals.PAINT_INVITES_KEY)
	w.state.erase(Goals.GARDEN_KEY)
	p.erase(Goals.VOYAGE_PHOTO)
	p.erase(Goals.VOYAGE_DONE)
	p.erase(Goals.ARU_PHOTO_KEY)
	p.erase(Goals.ARU_REST_KEY)
	p.erase(Goals.SHEEP_SHELTER_KEY)
	p.erase(Goals.TEA_SETUP_KEY)
	p.erase(Goals.TEA_CHAIR_KEY)
	w.state.erase(Goals.MURAL_KEY)
	w.state["festival"]=festival_at(2,true)
	var bonds:Dictionary=p.bonds
	for other:String in KNOWN_OTHERS:bonds.erase(other)
	move_weather(w,true)
	for need:String in all_needs():
		# known_three cannot be undone here: the completed goals themselves require bonds
		# with seven residents other than 洛洛 (removing them would invalidate the save).
		# postcard_reported reads the done luoluo 2 record itself, which stays.
		if need in ["festival_done","known_three","postcard_reported","memory_shared","xiaoli_first_trade","xiaoli_cart_plan","xiaoli_return_guest"]:continue
		expect(not Goals.need_met(need,w.state,KIM),"after undo: %s no longer holds"%need)
	expect(Goals.need_met("known_three",w.state,KIM),"after undo: known_three still holds through the bonds the done goals need")
	# A new active round keeps festival_done true (round 1 was finished before).
	expect(Goals.need_met("festival_done",w.state,KIM),"after undo: festival round 2 active still counts as done")
	for spec:Array in specs:
		var row:=view_at(w,KIM,str(spec[0]),int(spec[1]))
		expect(row==with_keepsake({"state":"done","choice":str(spec[2])},str(spec[0]),int(spec[1]),true),"after undo: %s %d still done, no needs key (%s)"%[str(spec[0]),int(spec[1]),str(row)])
	expect(Goals.valid(goals_of(w,KIM),pl(w,KIM)),"after undo: Goals.valid still accepts %s"%str(goals_of(w,KIM)))
	for spec:Array in specs:
		if not Goals.goal(str(spec[0]),int(spec[1])).has("needs"):continue
		var cell:=cell_of(w,str(spec[0]))
		go(w,KIM,region_of(w,str(spec[0])),cell)
		refuse(w,KIM,cell,extra_of(str(spec[0]),int(spec[1]),"",""),done_msg(Goals.goal(str(spec[0]),int(spec[1]))),"after undo: repeat %s %d -> already done"%[str(spec[0]),int(spec[1])])
	p=pl(w,KIM)
	p["region"]="home"
	p["x"]=home_x
	p["y"]=home_y
	var live_view:Dictionary=Goals.view(pl(w,KIM),w.state,KIM)
	expect(w.save(),"needs world saves")
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(parsed is Dictionary,"needs save parses"):return
	expect(validates(parsed),"save with batch-2 goals done and prerequisites undone passes SaveSchema")
	var restored:=World.new()
	if not expect(restored.load_world(path),"needs save reloads"):return
	expect(same(goals_of(restored,KIM),want),"batch-2 bond_goals survive reload (%s)"%str(goals_of(restored,KIM)))
	expect(same(pl(restored,KIM).get(Goals.KEEPSAKE_KEY),want_keepsakes) and kit_counts(pl(restored,KIM))==want_kits,"bond_keepsakes and kits survive reload")
	var restored_state:Dictionary=restored.state
	expect(same(Goals.view(pl(restored,KIM),restored_state,KIM),live_view),"reloaded view with state equals the live view")
	var aru:=cell_of(restored,"aru")
	stand(restored,KIM,aru)
	set_item(restored,KIM,"wood",10)
	refuse(restored,KIM,aru,"aru:1::",done_msg(Goals.goal("aru",1)),"after reload: aru 1 still done")

# ----------------------------------------- two players, replay, talk and gift --

func test_players_and_replay()->void:
	var w:=World.new()
	var a:="goal-pair-alpha"
	var b:="goal-pair-beta"
	w.add_player(a,"甲")
	w.add_player(b,"乙")
	var milu:=cell_of(w,"milu")
	for t:String in [a,b]:
		stand(w,t,milu)
		set_points(w,t,"milu",1)
		set_item(w,t,"soup",3)
		set_item(w,t,"radish",2)
	var b_before:=var_to_bytes(canon(pl(w,b)))
	var r:=do_goal(w,a,milu,"milu:1::","goal-replay-milu-1")
	expect(bool(r.get("ok",false)) and int(pl(w,a).inventory.soup)==2,"A completes milu 1 and pays one soup (got '%s')"%msg(r))
	expect(var_to_bytes(canon(pl(w,b)))==b_before,"A's goal leaves B's whole record byte-identical")
	expect(str(view_row(w,b,"milu",1).get("state",""))=="open","B's milu 1 is still open")
	var state_before:=var_to_bytes(canon(w.state))
	var replay:=do_goal(w,a,milu,"milu:1::","goal-replay-milu-1")
	expect(replay==r,"replayed request id returns the stored receipt")
	expect(var_to_bytes(canon(w.state))==state_before and int(pl(w,a).inventory.soup)==2,"replay applies nothing (soup charged once, world byte-identical)")
	refuse(w,a,milu,"milu:1::",done_msg(Goals.goal("milu",1)),"A repeats milu 1 with a new request id")
	var a_before:=var_to_bytes(canon(pl(w,a)))
	r=do_goal(w,b,milu,"milu:1::")
	expect(bool(r.get("ok",false)) and pl(w,b).get(Goals.RECORD_KEY)=={"milu":{"1":""}} and int(pl(w,b).inventory.soup)==2,"B completes the same goal independently (got '%s')"%msg(r))
	expect(var_to_bytes(canon(pl(w,a)))==a_before,"B's goal leaves A's whole record byte-identical")
	# Talk and gift still work afterwards; bond progress unaffected by the goal.
	var today:=Bond.day(float(w.state.time))
	r=act(w,a,"resident_gift",milu,"milu:radish")
	expect(bool(r.get("ok",false)) and pl(w,a).bonds=={"milu":rec(2,-1,today)},"A's common gift after the goal adds its point (got '%s')"%msg(r))
	r=act(w,a,"resident_talk",milu,"milu")
	expect(bool(r.get("ok",false)) and pl(w,a).bonds=={"milu":rec(3,today,today)},"A's talk after the goal adds its point")
	expect(pl(w,a).get(Goals.RECORD_KEY)=={"milu":{"1":""}},"talk and gift leave bond_goals unchanged")
	set_item(w,a,"soup",4)
	refuse(w,a,milu,"milu:3:soup:",stage_msg("milu",3),"A's milu 3 still needs the 信任 stage (a goal adds no points)")

# ------------------------------------------- batch 3: keepsake catalog --

func test_keepsake_catalog()->void:
	expect(Goals.KEEPSAKE_KEY=="bond_keepsakes" and Goals.CLAIM_ACTION=="resident_keepsake" and Goals.KIT_SUFFIX=="_kit" and Goals.MAX_ITEM==1000000000,
		"KEEPSAKE_KEY bond_keepsakes, CLAIM_ACTION resident_keepsake, KIT_SUFFIX _kit, MAX_ITEM 1e9")
	expect(Goals.ACTIONS==[Goals.ACTION,Goals.CLAIM_ACTION] and World.RESIDENT_GOALS.CLAIM_ACTION==Goals.CLAIM_ACTION,"ACTIONS is [resident_goal, resident_keepsake]; World wires the same claim action")
	expect(Goals.CLAIM_ACTION not in Bond.ACTIONS,"resident_keepsake is not a bond talk/gift action")
	var kinds:Array=Goals.KEEPSAKES.keys()
	kinds.sort()
	var ordered:Array=Goals.KEEPSAKE_ORDER.duplicate()
	ordered.sort()
	var want_kinds:Array=KEEPSAKE_GOALS.values()
	want_kinds.sort()
	expect(want_kinds.size()==18 and kinds==want_kinds and ordered==want_kinds and Goals.KEEPSAKE_ORDER.size()==18,
		"KEEPSAKES and KEEPSAKE_ORDER hold exactly the eighteen kinds once each (%s)"%str(Goals.KEEPSAKE_ORDER))
	expect(Goals.KEEPSAKE_ORDER.back()==CART_KIND and Goals.KEEPSAKES.get(CART_KIND,{}).get("name")==CART_NAME,"the cart keepsake is appended last and named 祖父的礦車")
	var want_items:Array=[]
	for kind:String in Goals.KEEPSAKE_ORDER:want_items.append(kind+"_kit")
	expect(Goals.keepsake_items()==want_items,"keepsake_items() lists kind+_kit in KEEPSAKE_ORDER order (%s)"%str(Goals.keepsake_items()))
	var trade:Dictionary=World.trade_items()
	var residents_seen:Array=[]
	for kind:String in Goals.KEEPSAKE_ORDER:
		var entry:Dictionary=Goals.KEEPSAKES[kind]
		var resident:=str(entry.get("resident",""))
		var stage:=int(entry.get("stage",0))
		var tag:="%s %d"%[resident,stage]
		var item:=kind+"_kit"
		var fields:Array=entry.keys()
		fields.sort()
		expect(fields==["blurb","name","resident","stage"],"%s: fields are resident, stage, name, blurb (%s)"%[kind,str(fields)])
		expect(entry.get("stage") is int and str(KEEPSAKE_GOALS.get(tag,""))==kind,"%s: points at %s, one of the thirteen keepsake goals"%[kind,tag])
		expect(Goals.has_goal(resident,stage),"%s: its goal %s exists"%[kind,tag])
		expect(kind=="keepsake_"+resident or (kind=="keepsake_aru_bird" and tag=="aru 4") or (kind=="keepsake_achao_oar" and tag=="achao 4") or (kind=="keepsake_xinghe_sign" and tag=="xinghe 4") or (kind=="keepsake_lingpopo_memorial" and tag=="lingpopo 4") or (kind=="keepsake_nuannuan_room" and tag=="nuannuan 4") or (kind==CART_KIND and tag=="bobo 4"),"%s: stable keepsake id for its resident and stage"%kind)
		residents_seen.append(resident)
		if kind==CART_KIND:expect(str(entry.get("name",""))==CART_NAME,"%s: the cart keepsake is named 祖父的礦車 (the goal text may differ)"%kind)
		else:expect(str(entry.get("name",""))==str(Goals.goal(resident,stage).get("keepsake","?")),"%s: name equals the goal's keepsake text"%kind)
		expect(entry.get("blurb") is String and not str(entry.get("blurb")).strip_edges().is_empty(),"%s: non-empty blurb"%kind)
		expect(Goals.keepsake_kind(resident,stage)==kind,"%s: keepsake_kind(%s) finds it"%[kind,tag])
		expect(Goals.keepsake_item(kind)==item and Goals.is_keepsake_item(item) and Goals.is_keepsake_kind(kind),"%s: keepsake_item / is_keepsake_item / is_keepsake_kind agree"%kind)
		expect(not Goals.is_keepsake_item(kind) and not Goals.is_keepsake_kind(item) and Goals.keepsake_item(item).is_empty(),"%s: kind and item ids are not interchangeable"%kind)
		var recipe:Variant=World.BUILD.get(kind)
		expect(recipe is Dictionary and recipe=={"name":str(entry.get("name","")),item:1},"%s: World.BUILD recipe is exactly {name, %s:1} (%s)"%[kind,item,str(recipe)])
		expect(str(World.NAMES.get(item,""))==str(entry.get("name","")),"%s: World.NAMES[%s] is the keepsake name"%[kind,item])
		expect(not trade.has(item),"%s: trade_items() excludes the kit"%kind)
		expect(not World.OTHER_SALES.has(item) and not World.CROPS.has(item) and not World.OTHER_SALES.has(kind) and not World.CROPS.has(kind),"%s: no sale price (OTHER_SALES / CROPS)"%kind)
	expect(trade.has("wood") and trade.has("plank"),"control: trade_items() still lists ordinary materials")
	var with_kind:Array=[]
	for tag:String in ALL_GOALS:
		var parts:=tag.split(" ")
		var found:=Goals.keepsake_kind(str(parts[0]),int(parts[1]))
		expect(found==str(KEEPSAKE_GOALS.get(tag,"")),"%s: keepsake_kind is '%s' (got '%s')"%[tag,str(KEEPSAKE_GOALS.get(tag,"")),found])
		if not found.is_empty():with_kind.append(tag)
	expect(with_kind.size()==18 and ALL_GOALS.size()-with_kind.size()==30,"18 goals carry a keepsake, 30 do not (%s)"%str(with_kind))
	for bad:Array in [["aru",2],["tom",1],["",1],["aru",0],["milu",1],["xiaoli",3]]:
		expect(Goals.keepsake_kind(str(bad[0]),int(bad[1])).is_empty(),"no keepsake for %s %d"%[str(bad[0]),int(bad[1])])
	for bad:String in ["","keepsake_tom","keepsake_aru_kit","trio_keepsake","Keepsake_aru"]:
		expect(Goals.keepsake_item(bad).is_empty() and not Goals.is_keepsake_kind(bad),"'%s' is not a keepsake kind"%bad)
	for bad:String in ["","_kit","keepsake_tom_kit","keepsake_aru","keepsake_aru_kit_kit","trio_keepsake_kit","keepsake_aru_Kit"]:
		expect(not Goals.is_keepsake_item(bad),"'%s' is not a keepsake item"%bad)
	# valid_keepsakes() directly (FIXTURE persons written here).
	var done_aru:Dictionary={"bonds":{"aru":rec(1,-1,-1)},"bond_goals":{"aru":{"1":""}}}
	expect(Goals.valid_keepsakes({"keepsake_aru":true},done_aru),"valid_keepsakes accepts a done goal's kind")
	var bad_records:Array=[{},[],"keepsake_aru",null,true,{"keepsake_aru":false},{"keepsake_aru":1},{"keepsake_aru":"true"},
		{"keepsake_milu":true},{"keepsake_tom":true},{"keepsake_aru_kit":true},{"keepsake_aru":true,"keepsake_milu":true}]
	for bad:Variant in bad_records:
		expect(not Goals.valid_keepsakes(bad,done_aru),"valid_keepsakes rejects %s"%str(bad))
	expect(not Goals.valid_keepsakes({"keepsake_aru":true},{"bonds":{"aru":rec(1,-1,-1)}}),"valid_keepsakes rejects a kind when bond_goals is absent")

# ------------------------------------- batch 3: claim through World.act --

func test_keepsake_claim()->void:
	var w:=World.new()
	w.state["picnic"]=true  # PRESET
	w.state["dock_stage"]=1  # PRESET
	var t:="goal-claim-old"
	w.add_player(t,"甲")
	var aru:=cell_of(w,"aru")
	var milu:=cell_of(w,"milu")
	var aru_region:=region_of(w,"aru")
	var milu_region:=region_of(w,"milu")
	set_points(w,t,"aru",6)
	set_points(w,t,"milu",1)
	set_item(w,t,"radish",2)
	# FIXTURE (written directly): aru 1 and milu 1 completed before batch 3 —
	# bond_goals only, no bond_keepsakes and no kit.
	var p:Dictionary=pl(w,t)
	p[Goals.RECORD_KEY]={"aru":{"1":""},"milu":{"1":""}}
	expect(Goals.valid(goals_of(w,t),pl(w,t)) and not pl(w,t).has(Goals.KEEPSAKE_KEY) and kit_counts(pl(w,t)).is_empty(),"claim fixture: valid old completion without keepsake record or kit")
	var row:=view_at(w,t,"aru",1)
	expect(row==with_keepsake({"state":"done","choice":""},"aru",1,false),"old completion: aru 1 done, keepsake unclaimed (%s)"%str(row))
	# Refusals (all through World.act); each leaves the whole world byte-identical.
	go(w,t,milu_region,milu)
	refuse_act(w,t,Goals.CLAIM_ACTION,milu,"aru:1",MSG_PLACE,"claim: aru's keepsake aimed at milu's cell")
	go(w,t,aru_region,aru)
	refuse_act(w,t,Goals.CLAIM_ACTION,aru+Vector2i.RIGHT,"aru:1",MSG_PLACE,"claim: aimed at the tile beside aru")
	p=pl(w,t)
	p["x"]=float(aru.x)+0.5
	p["y"]=float(aru.y)+5.5
	refuse_act(w,t,Goals.CLAIM_ACTION,aru,"aru:1",MSG_FAR,"claim: five tiles away from aru")
	stand(w,t,aru)
	p["region"]="jinguashi"
	refuse_act(w,t,Goals.CLAIM_ACTION,aru,"aru:1","","claim: jinguashi player aimed at aru's home cell")
	p["region"]=aru_region
	for unknown:String in ["tom:1","Aru:1",":1","","milu:3"]:
		refuse_act(w,t,Goals.CLAIM_ACTION,aru,unknown,MSG_PLACE,"claim: wrong resident '%s'"%unknown)
	for malformed:String in ["aru","aru:","aru:x","aru:1:","aru:1::","aru:1.0","aru:one"]:
		refuse_act(w,t,Goals.CLAIM_ACTION,aru,malformed,MSG_REOPEN,"claim: malformed extra '%s'"%malformed)
	for none:String in ["aru:2","aru:3","aru:0","aru:-1","aru:99"]:
		refuse_act(w,t,Goals.CLAIM_ACTION,aru,none,MSG_NO_KEEPSAKE,"claim: no keepsake for '%s'"%none)
	go(w,t,milu_region,milu)
	refuse_act(w,t,Goals.CLAIM_ACTION,milu,"milu:1",MSG_NO_KEEPSAKE,"claim: milu 1 is done but has no keepsake")
	refuse_act(w,t,Goals.CLAIM_ACTION,milu,"milu:3",not_done_claim_msg("milu",3),"claim: milu 3 not done yet")
	expect(not pl(w,t).has(Goals.KEEPSAKE_KEY) and kit_counts(pl(w,t)).is_empty(),"no claim refusal wrote bond_keepsakes or a kit")
	# Success (through World.act).
	go(w,t,aru_region,aru)
	var inv_before:Dictionary=pl(w,t).inventory.duplicate(true)
	var goals_before:Variant=goals_of(w,t)
	var r:=act(w,t,Goals.CLAIM_ACTION,aru,"aru:1")
	expect(bool(r.get("ok",false)) and msg(r)==claim_msg("aru",1),"claim: old aru 1 completion claims its keepsake (got '%s')"%msg(r))
	var expected:Dictionary=inv_before.duplicate(true)
	expected["keepsake_aru_kit"]=1
	expect(pl(w,t).inventory==expected,"claim: inventory gains exactly one keepsake_aru_kit (got %s)"%str(pl(w,t).inventory))
	expect(pl(w,t).get(Goals.KEEPSAKE_KEY)=={"keepsake_aru":true},"claim: bond_keepsakes is exactly {keepsake_aru:true}")
	expect(same(goals_of(w,t),goals_before),"claim leaves bond_goals unchanged")
	row=view_at(w,t,"aru",1)
	expect(row==with_keepsake({"state":"done","choice":""},"aru",1,true),"claim: view shows the aru keepsake claimed (%s)"%str(row))
	expect(Goals.valid_keepsakes(pl(w,t).get(Goals.KEEPSAKE_KEY),pl(w,t)),"claim: the record passes valid_keepsakes")
	# Second claim refused, and still refused after the kit is gone (no re-issue).
	refuse_act(w,t,Goals.CLAIM_ACTION,aru,"aru:1",claimed_msg("aru",1),"claim: second claim")
	expect(int(pl(w,t).inventory.get("keepsake_aru_kit",0))==1,"claim: second claim leaves exactly one kit")
	set_item(w,t,"keepsake_aru_kit",0)  # PRESET: the kit is gone
	refuse_act(w,t,Goals.CLAIM_ACTION,aru,"aru:1",claimed_msg("aru",1),"claim: kit lost, not re-issued")
	# A batch-3 completion (through World.act) grants it; a claim afterwards is refused.
	set_points(w,t,"milu",14)
	set_item(w,t,"soup",2)
	go(w,t,milu_region,milu)
	r=do_goal(w,t,milu,"milu:3:soup:")
	expect(bool(r.get("ok",false)) and msg(r)==goal_msg("milu",3),"claim world: milu 3 completed through resident_goal (got '%s')"%msg(r))
	expect(int(pl(w,t).inventory.get("keepsake_milu_kit",0))==1 and pl(w,t).get(Goals.KEEPSAKE_KEY)=={"keepsake_aru":true,"keepsake_milu":true},"completion adds the milu kit and kind to the existing record")
	refuse_act(w,t,Goals.CLAIM_ACTION,milu,"milu:3",claimed_msg("milu",3),"claim after a batch-3 completion")
	expect(Goals.valid_keepsakes(pl(w,t).get(Goals.KEEPSAKE_KEY),pl(w,t)),"claim world: record with both kinds passes valid_keepsakes")
	# bond_goals not a dictionary (FIXTURE: tampered record).
	var bt:="goal-claim-bad-goals"
	w.add_player(bt,"乙")
	set_points(w,bt,"aru",1)
	var bp:Dictionary=pl(w,bt)
	bp[Goals.RECORD_KEY]="aru"
	go(w,bt,aru_region,aru)
	refuse_act(w,bt,Goals.CLAIM_ACTION,aru,"aru:1",MSG_RECORD_BAD,"claim: bond_goals not a dictionary")
	# bond_keepsakes not a dictionary blocks both claim and apply (FIXTURES: old aru 1
	# completion plus a tampered bond_keepsakes; soup preset for milu 3).
	var nt:="goal-claim-bad-keepsakes"
	w.add_player(nt,"丙")
	set_points(w,nt,"aru",1)
	set_points(w,nt,"milu",14)
	var odd_values:Array=["claimed",[],5,true,null]
	for odd:Variant in odd_values:
		var np:Dictionary=pl(w,nt)
		np[Goals.RECORD_KEY]={"aru":{"1":""}}
		np[Goals.KEEPSAKE_KEY]=odd
		set_item(w,nt,"soup",2)
		go(w,nt,aru_region,aru)
		refuse_act(w,nt,Goals.CLAIM_ACTION,aru,"aru:1",MSG_RECORD_BAD,"claim: bond_keepsakes is %s"%str(odd))
		go(w,nt,milu_region,milu)
		refuse(w,nt,milu,"milu:3:soup:",MSG_RECORD_BAD,"apply milu 3: bond_keepsakes is %s"%str(odd))
		expect(int(pl(w,nt).inventory.get("soup",0))==2 and kit_counts(pl(w,nt)).is_empty() and same(goals_of(w,nt),{"aru":{"1":""}}),"bond_keepsakes %s: nothing consumed, no kit, bond_goals unchanged"%str(odd))
	# Kit count at MAX_ITEM blocks claim and apply; nothing consumed (FIXTURE: old
	# aru 1 completion; PRESET kit counts).
	var ft:="goal-claim-full"
	w.add_player(ft,"丁")
	set_points(w,ft,"aru",1)
	set_points(w,ft,"milu",14)
	var fp:Dictionary=pl(w,ft)
	fp[Goals.RECORD_KEY]={"aru":{"1":""}}
	set_item(w,ft,"keepsake_aru_kit",Goals.MAX_ITEM)
	go(w,ft,aru_region,aru)
	refuse_act(w,ft,Goals.CLAIM_ACTION,aru,"aru:1",cap_msg("aru",1),"claim: kit already at MAX_ITEM")
	expect(not pl(w,ft).has(Goals.KEEPSAKE_KEY),"capped claim writes no bond_keepsakes")
	set_item(w,ft,"keepsake_aru_kit",Goals.MAX_ITEM-1)
	r=act(w,ft,Goals.CLAIM_ACTION,aru,"aru:1")
	expect(bool(r.get("ok",false)) and int(pl(w,ft).inventory.get("keepsake_aru_kit",0))==Goals.MAX_ITEM and pl(w,ft).get(Goals.KEEPSAKE_KEY)=={"keepsake_aru":true},"claim at MAX_ITEM-1 succeeds and reaches the cap (got '%s')"%msg(r))
	set_item(w,ft,"soup",2)
	set_item(w,ft,"keepsake_milu_kit",Goals.MAX_ITEM)
	go(w,ft,milu_region,milu)
	refuse(w,ft,milu,"milu:3:soup:",cap_msg("milu",3),"apply milu 3: kit already at MAX_ITEM")
	expect(int(pl(w,ft).inventory.get("soup",0))==2 and same(goals_of(w,ft),{"aru":{"1":""}}) and pl(w,ft).get(Goals.KEEPSAKE_KEY)=={"keepsake_aru":true},"capped apply consumes nothing and writes no record")
	set_item(w,ft,"keepsake_milu_kit",Goals.MAX_ITEM-1)
	r=do_goal(w,ft,milu,"milu:3:soup:")
	expect(bool(r.get("ok",false)) and int(pl(w,ft).inventory.get("soup",-1))==0 and int(pl(w,ft).inventory.get("keepsake_milu_kit",0))==Goals.MAX_ITEM,"apply at MAX_ITEM-1 succeeds and reaches the cap (got '%s')"%msg(r))
	# Residents not yet present: the claim uses the same presence gate (FIXTURE: old achao 1 completion).
	var g:=World.new()
	var gt:="goal-claim-gate"
	g.add_player(gt,"戊")
	set_points(g,gt,"achao",1)
	var gp:Dictionary=pl(g,gt)
	gp[Goals.RECORD_KEY]={"achao":{"1":""}}
	var achao:=cell_of(g,"achao")
	go(g,gt,region_of(g,"achao"),achao)
	refuse_act(g,gt,Goals.CLAIM_ACTION,achao,"achao:1",Bond.DOCK_LOCKED,"claim: achao not present before the dock repair")
	g.state["dock_stage"]=1  # PRESET
	achao=cell_of(g,"achao")
	go(g,gt,region_of(g,"achao"),achao)
	r=act(g,gt,Goals.CLAIM_ACTION,achao,"achao:1")
	expect(bool(r.get("ok",false)) and kit_counts(pl(g,gt))=={"keepsake_achao_kit":1},"claim: once achao is present the old completion claims its kit (got '%s')"%msg(r))

# ------------------------------------------------ save, reload and schema --

func test_save_reload_and_schema()->void:
	var path:=temp_path("world")
	var fixture:=temp_path("fixture")
	var legacy_path:=temp_path("legacy")
	var w:=World.new()
	w.save_path=path
	w.state["picnic"]=true  # PRESET
	w.add_player(SAM,"山")
	var p:Dictionary=pl(w,SAM)
	var home_x:float=float(p.x)
	var home_y:float=float(p.y)
	set_points(w,SAM,"milu",14)
	set_points(w,SAM,"bobo",6)
	set_points(w,SAM,"xinghe",6)
	set_points(w,SAM,"aru",6)
	for pair:Array in [["soup",1],["carrot_soup",2],["copper_ingot",4],["woodwork_parts",2],["orange_blossom",2],["chime_herb",2],["radish",1]]:
		set_item(w,SAM,str(pair[0]),int(pair[1]))
	var milu:=cell_of(w,"milu")
	go(w,SAM,"home",milu)
	expect(bool(do_goal(w,SAM,milu,"milu:1::").get("ok",false)),"save: milu 1 done")
	expect(bool(do_goal(w,SAM,milu,"milu:3:carrot_soup:").get("ok",false)),"save: milu 3 carrot_soup done")
	go(w,SAM,region_of(w,"bobo"),cell_of(w,"bobo"))
	expect(bool(do_goal(w,SAM,cell_of(w,"bobo"),"bobo:2:siding:").get("ok",false)),"save: bobo 2 siding done in jinguashi")
	go(w,SAM,region_of(w,"xinghe"),cell_of(w,"xinghe"))
	expect(bool(do_goal(w,SAM,cell_of(w,"xinghe"),"xinghe:2:orange_chime:").get("ok",false)),"save: xinghe 2 orange_chime done in lanyang")
	p=pl(w,SAM)
	p["region"]="home"
	p["x"]=home_x
	p["y"]=home_y
	var live:Variant=goals_of(w,SAM)
	var want_live:Dictionary={"milu":{"1":"","3":"carrot_soup"},"bobo":{"2":"siding"},"xinghe":{"2":"orange_chime"}}
	expect(live is Dictionary and same(live,want_live),"live bond_goals before saving (%s)"%str(live))
	# Batch 3 (granted through World.act above): milu 3 and xinghe 2 carry keepsakes, milu 1 and bobo 2 do not.
	var want_keepsakes:Dictionary={"keepsake_milu":true,"keepsake_xinghe":true}
	var want_kits:Dictionary={"keepsake_milu_kit":1,"keepsake_xinghe_kit":1}
	expect(same(pl(w,SAM).get(Goals.KEEPSAKE_KEY),want_keepsakes),"live bond_keepsakes before saving (%s)"%str(pl(w,SAM).get(Goals.KEEPSAKE_KEY)))
	expect(kit_counts(pl(w,SAM))==want_kits,"live kits before saving (%s)"%str(kit_counts(pl(w,SAM))))
	var live_bonds:Dictionary=(pl(w,SAM).bonds as Dictionary).duplicate(true)
	expect(w.save(),"world saves")
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(parsed is Dictionary,"save parses"):return
	var base:Dictionary=parsed
	expect(validates(base),"control: the saved world passes SaveSchema (bond_keepsakes after grants)")
	var restored:=World.new()
	if not expect(restored.load_world(path),"fresh world reloads the save"):return
	var loaded:Variant=goals_of(restored,SAM)
	expect(loaded is Dictionary and var_to_bytes(canon(loaded))==var_to_bytes(canon(live)),"bond_goals survive reload byte-identical after canonicalising (%s)"%str(loaded))
	expect(same(pl(restored,SAM).get(Goals.KEEPSAKE_KEY),want_keepsakes),"bond_keepsakes survive reload (%s)"%str(pl(restored,SAM).get(Goals.KEEPSAKE_KEY)))
	expect(Goals.keepsake_claimed(pl(restored,SAM),"keepsake_milu") and Goals.keepsake_claimed(pl(restored,SAM),"keepsake_xinghe"),"reloaded values are still bool true")
	expect(kit_counts(pl(restored,SAM))==want_kits,"kits survive reload (%s)"%str(kit_counts(pl(restored,SAM))))
	expect(var_to_bytes(canon(pl(restored,SAM).bonds))==var_to_bytes(canon(live_bonds)),"bonds survive reload")
	var milu_loaded:Dictionary=pl(restored,SAM).bonds.milu
	expect(typeof(milu_loaded.points)==TYPE_INT,"reloaded bond points are ints again")
	expect(same(Goals.view(pl(restored,SAM)),Goals.view(pl(w,SAM))),"reloaded goals view equals the live view")
	stand(restored,SAM,milu)
	set_item(restored,SAM,"soup",2)
	refuse(restored,SAM,milu,"milu:1::",done_msg(Goals.goal("milu",1)),"milu 1 still done after reload")
	refuse_act(restored,SAM,Goals.CLAIM_ACTION,milu,"milu:3",claimed_msg("milu",3),"after reload: milu 3 keepsake still claimed")
	var aru:=cell_of(restored,"aru")
	stand(restored,SAM,aru)
	set_item(restored,SAM,"hardwood",4)
	var r:=do_goal(restored,SAM,aru,"aru:2::201")
	expect(bool(r.get("ok",false)),"a new goal after reload succeeds (got '%s')"%msg(r))
	expect(restored.save(),"restored world saves again")
	var again:=World.new()
	expect(again.load_world(path) and same(goals_of(again,SAM),{"milu":{"1":"","3":"carrot_soup"},"bobo":{"2":"siding"},"xinghe":{"2":"orange_chime"},"aru":{"2":""}}),"second reload keeps the old and the new record")
	expect(same(pl(again,SAM).get(Goals.KEEPSAKE_KEY),want_keepsakes) and kit_counts(pl(again,SAM))==want_kits,"second reload keeps bond_keepsakes and kits (aru 2 has no keepsake)")
	# FIXTURE: legacy save without bond_goals (it predates batch 3 too: no bond_keepsakes, no kits).
	var old:Dictionary=base.duplicate(true)
	var old_sam:Dictionary=old.players[SAM]
	old_sam.erase(Goals.RECORD_KEY)
	old_sam.erase(Goals.KEEPSAKE_KEY)
	var old_inv:Dictionary=old_sam["inventory"]
	for item:String in Goals.keepsake_items():old_inv.erase(item)
	expect(validates(old),"legacy save without bond_goals passes SaveSchema")
	expect(write_fixture(legacy_path,old),"write legacy fixture")
	var legacy:=World.new()
	if not expect(legacy.load_world(legacy_path),"legacy save loads"):return
	expect(not pl(legacy,SAM).has(Goals.RECORD_KEY),"loading does not invent bond_goals")
	expect(not pl(legacy,SAM).has(Goals.KEEPSAKE_KEY),"loading does not invent bond_keepsakes")
	expect(str(view_row(legacy,SAM,"milu",1).get("state",""))=="open" and str(view_row(legacy,SAM,"milu",3).get("state",""))=="open","legacy view: milu 1 and 3 open")
	stand(legacy,SAM,milu)
	set_item(legacy,SAM,"soup",1)
	r=do_goal(legacy,SAM,milu,"milu:1::")
	expect(bool(r.get("ok",false)) and pl(legacy,SAM).get(Goals.RECORD_KEY)=={"milu":{"1":""}},"legacy player completes milu 1 (got '%s')"%msg(r))
	expect(not pl(legacy,SAM).has(Goals.KEEPSAKE_KEY) and kit_counts(pl(legacy,SAM)).is_empty(),"legacy milu 1 (no keepsake) creates no bond_keepsakes and no kit")
	# FIXTURE: a batch-2 save — milu 3 and xinghe 2 done, but no bond_keepsakes field and no kits.
	var batch2:Dictionary=base.duplicate(true)
	var b2_sam:Dictionary=batch2.players[SAM]
	b2_sam.erase(Goals.KEEPSAKE_KEY)
	var b2_inv:Dictionary=b2_sam["inventory"]
	for item:String in Goals.keepsake_items():b2_inv.erase(item)
	expect(validates(batch2),"old (batch-2) save: bond_keepsakes absent while keepsake goals are done passes SaveSchema")
	var b2_path:=temp_path("batch2")
	expect(write_fixture(b2_path,batch2),"write batch-2 fixture")
	var b2:=World.new()
	if not expect(b2.load_world(b2_path),"batch-2 save loads"):return
	b2.save_path=b2_path
	expect(not pl(b2,SAM).has(Goals.KEEPSAKE_KEY) and kit_counts(pl(b2,SAM)).is_empty(),"batch-2 load invents neither bond_keepsakes nor kits")
	var b2_row:=view_at(b2,SAM,"milu",3)
	expect(b2_row==with_keepsake({"state":"done","choice":"carrot_soup"},"milu",3,false),"batch-2 view: milu 3 done, keepsake unclaimed (%s)"%str(b2_row))
	# Claim through World.act at milu.
	go(b2,SAM,region_of(b2,"milu"),cell_of(b2,"milu"))
	r=act(b2,SAM,Goals.CLAIM_ACTION,cell_of(b2,"milu"),"milu:3")
	expect(bool(r.get("ok",false)) and msg(r)==claim_msg("milu",3),"batch-2 player claims the milu 3 keepsake (got '%s')"%msg(r))
	expect(kit_counts(pl(b2,SAM))=={"keepsake_milu_kit":1} and pl(b2,SAM).get(Goals.KEEPSAKE_KEY)=={"keepsake_milu":true},"claim grants one milu kit and marks only milu claimed")
	expect(same(goals_of(b2,SAM),want_live),"claim leaves bond_goals unchanged")
	b2_row=view_at(b2,SAM,"milu",3)
	expect(b2_row==with_keepsake({"state":"done","choice":"carrot_soup"},"milu",3,true),"batch-2 view after the claim: milu 3 claimed (%s)"%str(b2_row))
	b2_row=view_at(b2,SAM,"xinghe",2)
	expect(b2_row==with_keepsake({"state":"done","choice":"orange_chime"},"xinghe",2,false),"batch-2 view after the claim: xinghe 2 still unclaimed (%s)"%str(b2_row))
	refuse_act(b2,SAM,Goals.CLAIM_ACTION,cell_of(b2,"milu"),"milu:3",claimed_msg("milu",3),"batch-2 player claims milu 3 twice")
	var b2p:Dictionary=pl(b2,SAM)
	b2p["region"]="home"
	b2p["x"]=home_x
	b2p["y"]=home_y
	expect(b2.save(),"batch-2 world saves after the claim")
	var b2_saved:Variant=JSON.parse_string(FileAccess.get_file_as_string(b2_path))
	expect(b2_saved is Dictionary and validates(b2_saved),"save after a claim passes SaveSchema")
	var b2_again:=World.new()
	expect(b2_again.load_world(b2_path) and pl(b2_again,SAM).get(Goals.KEEPSAKE_KEY)=={"keepsake_milu":true} and kit_counts(pl(b2_again,SAM))=={"keepsake_milu_kit":1},"claimed record and kit survive reload")
	# Tampering: control first, then each case differs only by its field.
	expect(write_fixture(fixture,base),"write control fixture")
	var control:=World.new()
	expect(control.load_world(fixture) and same(goals_of(control,SAM),want_live),"control: the untampered fixture loads with its bond_goals")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:Array=["unknown resident","resident id in the wrong case","stage key without a goal (aru 5)","stage key above the bond level (milu 4)",
		"stage key 0","stage key 5","stage key 01","stage key ' 1'","stage key 1.0","value int","value null","value bool","value list",
		"invalid option id","option id in the wrong case","missing option on an option goal","option of another goal",
		"option on an option-less goal","empty per-resident dict","per-resident string","per-resident list","empty top dict",
		"top list","top string","top number","top null","stage recorded without a bond (xiaoli 2)","stage recorded without a bond (chacha 3)",
		"bond lowered below a recorded stage","bond removed under a recorded stage"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_fixture(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	# Batch 3: player.bond_keepsakes tampering (FIXTURES written directly from the saved base).
	var ks_labels:Array=["keepsakes empty dict","keepsakes list","keepsakes string","keepsakes number","keepsakes null","keepsakes bool",
		"unknown kind","kit id used as kind","kind in the wrong case","value false","value 1","value string 'true'","value null",
		"kind whose goal is not done (bobo 1)","kind whose goal is not done (aru 1)","goal record removed under a keepsake",
		"bond_goals erased under keepsakes"]
	for label:String in ks_labels:
		var bad:=tampered_keepsakes(base,label)
		expect(write_fixture(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects bond_keepsakes: "+label)
		expect(not probe.load_world(fixture),"load_world rejects bond_keepsakes: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	var subset:Dictionary=base.duplicate(true)
	var subset_sam:Dictionary=subset.players[SAM]
	subset_sam[Goals.KEEPSAKE_KEY]={"keepsake_xinghe":true}
	expect(validates(subset),"schema accepts bond_keepsakes naming only some of the done keepsake goals")
	expect(not FileAccess.file_exists(fixture+".bak"),"the tamper fixture never had a backup to fall back to")

func tampered_keepsakes(base:Dictionary,label:String)->Dictionary:
	var s:Dictionary=base.duplicate(true)
	var person:Dictionary=s.players[SAM]
	var record:Dictionary=person[Goals.KEEPSAKE_KEY]
	var goals:Dictionary=person[Goals.RECORD_KEY]
	match label:
		"keepsakes empty dict":person[Goals.KEEPSAKE_KEY]={}
		"keepsakes list":person[Goals.KEEPSAKE_KEY]=["keepsake_milu"]
		"keepsakes string":person[Goals.KEEPSAKE_KEY]="keepsake_milu"
		"keepsakes number":person[Goals.KEEPSAKE_KEY]=1
		"keepsakes null":person[Goals.KEEPSAKE_KEY]=null
		"keepsakes bool":person[Goals.KEEPSAKE_KEY]=true
		"unknown kind":record["keepsake_tom"]=true
		"kit id used as kind":record["keepsake_milu_kit"]=true
		"kind in the wrong case":
			record.erase("keepsake_milu")
			record["Keepsake_milu"]=true
		"value false":record["keepsake_milu"]=false
		"value 1":record["keepsake_milu"]=1
		"value string 'true'":record["keepsake_milu"]="true"
		"value null":record["keepsake_milu"]=null
		"kind whose goal is not done (bobo 1)":record["keepsake_bobo"]=true
		"kind whose goal is not done (aru 1)":record["keepsake_aru"]=true
		"goal record removed under a keepsake":goals.erase("xinghe")
		"bond_goals erased under keepsakes":person.erase(Goals.RECORD_KEY)
		_:expect(false,"unknown keepsake tamper label "+label)
	return s

func tampered(base:Dictionary,label:String)->Dictionary:
	var s:Dictionary=base.duplicate(true)
	var person:Dictionary=s.players[SAM]
	var goals:Dictionary=person[Goals.RECORD_KEY]
	var milu:Dictionary=goals["milu"]
	var bobo:Dictionary=goals["bobo"]
	var bonds:Dictionary=person["bonds"]
	match label:
		"unknown resident":goals["tom"]={"1":""}
		"resident id in the wrong case":goals["Aru"]={"2":""}
		"stage key without a goal (aru 5)":goals["aru"]={"5":""}
		"stage key above the bond level (milu 4)":milu["4"]=""
		"stage key 0":milu["0"]=""
		"stage key 5":milu["5"]=""
		"stage key 01":
			milu.erase("1")
			milu["01"]=""
		"stage key ' 1'":
			milu.erase("1")
			milu[" 1"]=""
		"stage key 1.0":
			milu.erase("1")
			milu["1.0"]=""
		"value int":milu["1"]=1
		"value null":milu["1"]=null
		"value bool":milu["1"]=true
		"value list":milu["1"]=[]
		"invalid option id":milu["3"]="stew"
		"option id in the wrong case":milu["3"]="Carrot_soup"
		"missing option on an option goal":milu["3"]=""
		"option of another goal":bobo["2"]="soup"
		"option on an option-less goal":milu["1"]="soup"
		"empty per-resident dict":goals["aru"]={}
		"per-resident string":goals["aru"]="2"
		"per-resident list":goals["aru"]=["2"]
		"empty top dict":person[Goals.RECORD_KEY]={}
		"top list":person[Goals.RECORD_KEY]=[]
		"top string":person[Goals.RECORD_KEY]="milu"
		"top number":person[Goals.RECORD_KEY]=5
		"top null":person[Goals.RECORD_KEY]=null
		"stage recorded without a bond (xiaoli 2)":goals["xiaoli"]={"2":"tree"}
		"stage recorded without a bond (chacha 3)":goals["chacha"]={"3":""}
		"bond lowered below a recorded stage":
			var m:Dictionary=bonds["milu"]
			m["points"]=13
		"bond removed under a recorded stage":bonds.erase("milu")
		_:expect(false,"unknown tamper label "+label)
	return s

# ------------------------------------------------- in-process Session snapshot --

func test_session_snapshot()->void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=World.new()
	var w=session.world
	w.add_player(PRIVATE_A,"甲")
	w.add_player(PRIVATE_B,"乙")
	var milu:=cell_of(w,"milu")
	stand(w,PRIVATE_A,milu)
	stand(w,PRIVATE_B,milu)
	session.peers={1:PRIVATE_A,2:PRIVATE_B}
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.has("resident_goals"),"recipient snapshot has resident_goals")
	var own:Dictionary=snap.get("resident_goals",{})
	var ws:Dictionary=w.state
	expect(own==Goals.view(pl(w,PRIVATE_A),ws,PRIVATE_A),"fresh: resident_goals equals the recipient's own view (with world state and token)")
	var own_keys:Array=own.keys()
	own_keys.sort()
	expect(own_keys==TWELVE,"resident_goals lists all twelve residents")
	var locked:=true
	for resident in own:
		var stages:Dictionary=own[resident]
		for key in stages:
			if not stages[key] is Dictionary or not locked_row_ok(str(resident),str(key),stages[key]):locked=false
	expect(locked,"fresh: every goal is locked (needs rows exactly on goals with needs)")
	set_points(w,PRIVATE_A,"milu",1)
	session._send_snapshot(1)
	snap=session.snapshot
	own=snap.get("resident_goals",{})
	var m:Dictionary=own.get("milu",{})
	var milu3_locked:=with_keepsake({"state":"locked","choice":""},"milu",3,false)
	expect(own==Goals.view(pl(w,PRIVATE_A),ws,PRIVATE_A) and m=={"1":{"state":"open","choice":""},"2":{"state":"locked","choice":"","needs":[{"id":"recipe_pages","label":"找齊三片食譜紙角","met":false}]},"3":milu3_locked,"4":{"state":"locked","choice":"","needs":[{"id":"shared_meal","label":"親手上一輪共享料理","met":false}]}},"stage 1: milu 1 open, milu 3 locked (%s)"%str(m))
	set_item(w,PRIVATE_A,"soup",1)
	var r:=do_goal(w,PRIVATE_A,milu,"milu:1::")
	expect(bool(r.get("ok",false)),"Session world: alpha completes milu 1 (got '%s')"%msg(r))
	session._send_snapshot(1)
	snap=session.snapshot
	own=snap.get("resident_goals",{})
	m=own.get("milu",{})
	expect(own==Goals.view(pl(w,PRIVATE_A),ws,PRIVATE_A) and m=={"1":{"state":"done","choice":""},"2":{"state":"locked","choice":"","needs":[{"id":"recipe_pages","label":"找齊三片食譜紙角","met":false}]},"3":milu3_locked,"4":{"state":"locked","choice":"","needs":[{"id":"shared_meal","label":"親手上一輪共享料理","met":false}]}},"done: milu 1 done, milu 3 still locked (%s)"%str(m))
	expect(pl(w,PRIVATE_A).has(Goals.RECORD_KEY),"publishing does not strip the live record")
	var players:Dictionary=snap.get("players",{})
	var clean:=true
	for id in players:
		var person:Dictionary=players[id]
		if person.has(Goals.RECORD_KEY) or person.has("resident_goals"):clean=false
	var dump:=JSON.stringify(players)
	expect(clean and not players.is_empty(),"snapshot players entries carry no bond_goals / resident_goals")
	expect(not dump.contains(PRIVATE_A) and not dump.contains(PRIVATE_B),"snapshot players entries contain no token")
	expect(not JSON.stringify(snap).contains("\"bond_goals\""),"the whole snapshot never names bond_goals")
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		var text:=JSON.stringify(public)
		expect(not text.contains("\"bond_goals\"") and not text.contains("\"resident_goals\""),"public_state(%s) carries no goal records"%region)
		expect(not text.contains(PRIVATE_A) and not text.contains(PRIVATE_B),"public_state(%s) carries no token"%region)
	# Batch-2 needs rows: alpha reaches luoluo 2 and knows three other residents.
	set_points(w,PRIVATE_A,"luoluo",6)
	for other:String in KNOWN_OTHERS:set_points(w,PRIVATE_A,other,1)
	pl(w,PRIVATE_A)[CLUES_KEY]=["achao","chacha"] # FIXTURE: two clues, so the need row is partial
	session._send_snapshot(1)
	snap=session.snapshot
	own=snap.get("resident_goals",{})
	var alpha_label:=str(NEED_TEXT["known_three"])+"（目前 3 位）"
	expect(own==Goals.view(pl(w,PRIVATE_A),ws,PRIVATE_A),"needs: alpha's resident_goals equals alpha's view with state")
	var luoluo_rows:Dictionary=own.get("luoluo",{})
	expect(luoluo_rows.get("2",{})=={"state":"open","choice":"","needs":[{"id":"known_three","label":alpha_label,"met":true},{"id":CLUES_NEED,"label":CLUES_TEXT%2,"met":false}]},"needs: alpha's luoluo 2 open with known_three met, clues 2/3 (%s)"%str(luoluo_rows.get("2")))
	var aru_rows:Dictionary=own.get("aru",{})
	expect(aru_rows.get("1",{})==with_keepsake({"state":"locked","choice":"","needs":[{"id":"own_bed","label":str(NEED_TEXT["own_bed"]),"met":false}]},"aru",1,false),"needs: alpha's aru 1 locked with own_bed unmet (%s)"%str(aru_rows.get("1")))
	players=snap.get("players",{})
	dump=JSON.stringify(players)
	# Need ids and labels occur only in resident_goals.gd, so their absence means
	# no needs row leaked ("needs" itself is also a salt-pan public key).
	expect(no_need_rows(dump) and not dump.contains(alpha_label) and not dump.contains(CLUES_KEY),"needs: snapshot players entries carry no needs rows (ids or labels)")
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		var text:=JSON.stringify(public)
		expect(no_need_rows(text) and not text.contains(alpha_label) and not text.contains("\"bond_goals\""),"needs: public_state(%s) carries no needs rows, need labels or bond_goals"%region)
	# Beta's own snapshot.
	session.peers={1:PRIVATE_B,2:PRIVATE_A}
	session._send_snapshot(1)
	snap=session.snapshot
	own=snap.get("resident_goals",{})
	expect(own==Goals.view(pl(w,PRIVATE_B),ws,PRIVATE_B) and own.get("milu",{})=={"1":{"state":"locked","choice":""},"2":{"state":"locked","choice":"","needs":[{"id":"recipe_pages","label":"找齊三片食譜紙角","met":false}]},"3":milu3_locked,"4":{"state":"locked","choice":"","needs":[{"id":"shared_meal","label":"親手上一輪共享料理","met":false}]}},"beta's resident_goals is beta's own (milu locked)")
	expect(own!=Goals.view(pl(w,PRIVATE_A),ws,PRIVATE_A),"beta's resident_goals is not alpha's")
	var beta_luoluo:Dictionary=own.get("luoluo",{})
	expect(beta_luoluo.get("2",{})=={"state":"locked","choice":"","needs":[{"id":"known_three","label":str(NEED_TEXT["known_three"])+"（目前 0 位）","met":false},{"id":CLUES_NEED,"label":CLUES_TEXT%0,"met":false}]},"beta's luoluo 2 row shows beta's own count, not alpha's (%s)"%str(beta_luoluo.get("2")))
	expect(not JSON.stringify(snap).contains(alpha_label),"beta's whole snapshot never contains alpha's needs label")
	expect(not JSON.stringify(snap).contains("\"bond_goals\""),"beta's whole snapshot never names bond_goals")
	players=snap.get("players",{})
	dump=JSON.stringify(players)
	expect(not dump.contains("\"bond_goals\"") and not dump.contains(PRIVATE_A) and not dump.contains(PRIVATE_B),"beta's snapshot of alpha has no bond_goals and no token")
	expect(no_need_rows(dump),"beta's snapshot of alpha carries no needs rows")
	# Batch 3: alpha earns the milu 3 keepsake through World.act; bond_keepsakes stays private.
	set_points(w,PRIVATE_A,"milu",14)
	set_item(w,PRIVATE_A,"soup",2)
	stand(w,PRIVATE_A,milu)
	r=do_goal(w,PRIVATE_A,milu,"milu:3:soup:")
	expect(bool(r.get("ok",false)) and pl(w,PRIVATE_A).get(Goals.KEEPSAKE_KEY)=={"keepsake_milu":true},"Session world: alpha completes milu 3 and gets the keepsake (got '%s')"%msg(r))
	session.peers={1:PRIVATE_A,2:PRIVATE_B}
	session._send_snapshot(1)
	snap=session.snapshot
	own=snap.get("resident_goals",{})
	m=own.get("milu",{})
	expect(own==Goals.view(pl(w,PRIVATE_A),ws,PRIVATE_A) and m.get("3",{})==with_keepsake({"state":"done","choice":"soup"},"milu",3,true),"keepsake: alpha's milu 3 done with the keepsake claimed (%s)"%str(m.get("3")))
	expect(not JSON.stringify(snap).contains("\"%s\""%Goals.KEEPSAKE_KEY),"alpha's whole snapshot never names bond_keepsakes")
	expect(pl(w,PRIVATE_A).has(Goals.KEEPSAKE_KEY),"publishing does not strip the live bond_keepsakes")
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		expect(not JSON.stringify(public).contains("\"%s\""%Goals.KEEPSAKE_KEY),"keepsake: public_state(%s) carries no bond_keepsakes"%region)
	session.peers={1:PRIVATE_B,2:PRIVATE_A}
	session._send_snapshot(1)
	snap=session.snapshot
	own=snap.get("resident_goals",{})
	expect(own.get("milu",{})=={"1":{"state":"locked","choice":""},"2":{"state":"locked","choice":"","needs":[{"id":"recipe_pages","label":"找齊三片食譜紙角","met":false}]},"3":milu3_locked,"4":{"state":"locked","choice":"","needs":[{"id":"shared_meal","label":"親手上一輪共享料理","met":false}]}},"keepsake: beta's milu 3 stays locked and unclaimed")
	expect(not JSON.stringify(snap).contains("\"%s\""%Goals.KEEPSAKE_KEY),"beta's whole snapshot never names bond_keepsakes")
	session.world=null
	session.queue_free()
	await process_frame
