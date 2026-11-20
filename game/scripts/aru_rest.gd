extends RefCounted
## T066 N01-3 〈留下新的刮痕〉：阿榆長椅上的真實同坐場景（只讀、純表現）。
## 伺服器在 home snapshot 放 aru_bench_scene：{} 閒置，或 {"anchor":"x,y","sitters":{public_id:slot}}。
## 場景是暫時的，不寫入存檔；舊伺服器沒有這個欄位時，一切視為閒置。

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS

const FIELD:="aru_bench_scene"
## 與 Goals.ARU_REST_ACTION 成對的「起身」動作（空 extra）。
const LEAVE_ACTION:=Goals.ARU_REST_LEAVE
const BENCH_ART:=preload("res://assets/ui-life/master-bench.png")

## 回傳 {anchor:Vector2i, sitters:{id:int}}；欄位缺漏、格式錯誤或沒人坐時回傳 {}。
static func scene(snapshot:Dictionary) -> Dictionary:
	var raw:Variant=snapshot.get(FIELD,{})
	if not raw is Dictionary or raw.is_empty() or not raw.has("anchor") or not raw.get("sitters") is Dictionary:return {}
	var anchor_key:=str(raw.anchor)
	if not anchor_key.contains(","):return {}
	var sitters:={}
	for id:Variant in raw.sitters:
		var slot:=int(raw.sitters[id])
		if slot in [0,1]:sitters[str(id)]=slot
	if sitters.is_empty():return {}
	return {"anchor":World.cell(anchor_key),"sitters":sitters}

static func active(snapshot:Dictionary) -> bool:
	return not scene(snapshot).is_empty()

static func slot_of(snapshot:Dictionary,id:String) -> int:
	return int(scene(snapshot).get("sitters",{}).get(id,-1))

static func seated(snapshot:Dictionary,id:String) -> bool:
	return slot_of(snapshot,id)>=0

## 長椅有空位、而且主位已有人坐著：朋友才能選擇加入。
static func joinable(snapshot:Dictionary,id:String) -> bool:
	var current:=scene(snapshot)
	if current.is_empty() or seated(snapshot,id):return false
	var sitters:Dictionary=current.sitters
	return sitters.values().has(0) and not sitters.values().has(1)

## 長椅本身加上阿榆（slot 之外的固定位）與所有同坐者，依 slot 由左到右畫，整組落在 anchor 這一列。
## view 是 world_view；數據只讀 snapshot 與 view.character_art。
static func draw_scene(view,data:Dictionary,current:Dictionary) -> void:
	var anchor:Vector2i=current.anchor
	view.draw_texture(BENCH_ART,view.screen(Vector2(anchor))+Vector2(0,-7))
	var art:Variant=view.character_art
	var npc_at:Vector2=view.screen(World.ARU_BENCH.npc_feet(anchor)).round()
	if art:art.draw_seated(view,npc_at,false,"aru")
	else:view.person_sprite(npc_at,Color(World.Village.NPCS.aru.color),"aru",Vector2i.DOWN,0.0,false,false,false,0.0,true)
	if current.sitters.has(view.player_id):
		var local_at:Vector2=view.screen(World.ARU_BENCH.feet(anchor,int(current.sitters[view.player_id]))).round()
		view.world_label(local_at+Vector2(0,-40),"起身","aru")
	else:
		view.world_label(npc_at+Vector2(0,-47),World.Village.NPCS.aru.name,"aru")
	var order:Array=[]
	for id:String in current.sitters:
		if data.get("players",{}).has(id):order.append(id)
	order.sort_custom(func(a:String,b:String) -> bool:return int(current.sitters[a])<int(current.sitters[b]))
	for id:String in order:
		var person:Dictionary=data.players[id]
		var at:Vector2=view.screen(World.ARU_BENCH.feet(anchor,int(current.sitters[id]))).round()
		if art:view.draw_seated_player(at,person)
		else:view.person_sprite(at,Color("d88f73"),"farmer" if id==view.player_id else "guest")
		view.world_label(at+Vector2(0,-40),str(person.get("name","")),"")

## 與伺服器動作用的座標：一律是阿榆實際所在格，不是長椅 anchor。
static func aru_cell(snapshot:Dictionary) -> Vector2i:
	return World.Village.resident_cell(snapshot,"aru")

## 本機狀態變化時的簡短回饋（只在伺服器確認後才有字）。prev/next 為前後兩份 snapshot。
static func transition_notice(previous:Dictionary,next:Dictionary,id:String) -> String:
	var before:=slot_of(previous,id)
	var after:=slot_of(next,id)
	if before<0 and after==0:return "你坐到長椅上。阿榆：「這道痕，就是我們今天留下的。」（互動鍵或移動起身）"
	if before<0 and after==1:return "你在阿榆身旁坐下。（互動鍵或移動起身）"
	if before>=0 and after<0:return "你起身離開長椅。"
	if before==0 and after==0:
		var count_before:int=scene(previous).get("sitters",{}).size()
		var count_after:int=scene(next).get("sitters",{}).size()
		if count_after>count_before:return "有朋友在身旁坐下了。"
	return ""
