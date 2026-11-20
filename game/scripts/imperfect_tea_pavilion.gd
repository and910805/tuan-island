extends RefCounted
## T12 不完美的茶亭 (內容設定集 家具・茶屋): 3×3 open shelter, 竹材 30／木材 10／布料 8.
##
## Pure rules, no file or clock access. The pattern is unlocked by the player's OWN persisted
## chacha stage-3 goal (N04-3 信任・一場沒有流程的茶會): `player.bond_goals.chacha["3"]`, read through
## RESIDENT_GOALS.done(). Nothing new is stored, so saves that completed the goal earlier unlock
## automatically. Tea notes and the stage-4 chair behaviour are untouched.
##
## Inspecting the built structure (E) only shows a themed line: no materials, no teleport, no time.
const Goals=preload("res://scripts/resident_goals.gd")
const Industry=preload("res://scripts/industry.gd")

const KIND:=Industry.IMPERFECT_TEA_PAVILION
const RESIDENT:="chacha"
const STAGE:=3
const NAME:="不完美的茶亭"
const STORY_TITLE:="一場沒有流程的茶會"
## How close (in tiles, to a part's centre) the avatar must be for E to fall back to the pavilion.
const FOCUS_REACH:=1.4
const LOCK_MESSAGE:="完成茶茶的〈一場沒有流程的茶會〉後，才能建造不完美的茶亭。"
const LOCK_DETAIL:="和茶茶的關係到「信任」後，到貓空和茶茶一起完成〈一場沒有流程的茶會〉，就能取得不完美的茶亭圖樣。"
const LOCK_SHORT:="完成〈沒有流程的茶會〉"
const UNLOCK_NOTE:=Goals.PAVILION_UNLOCK_NOTE
const BUILD_NOTE:="占 3×3 格的開放式遮棚，竹材 30、木材 10、布料 8；四邊都能走進走出。不能蓋住步道、出入口和互動位置。"
const NEUTRAL_MEMENTO:="竹片之間漏下的光不太整齊，這座茶亭好像不趕著把茶會結束。"
const ESSENTIAL_MESSAGE:="這裡是步道、出入口或互動位置，茶亭要留給大家走過。"
const BLOCKED_MESSAGE:="茶亭的 3×3 範圍需要整片空地。"

## Own stage-3 completion. Works for any save that already holds the record.
static func unlocked(person:Variant) -> bool:
	if not person is Dictionary:return false
	return Goals.done(person as Dictionary,RESIDENT).has(STAGE)

## [長說明, 短標籤] for the builder's locked card.
static func lock_text() -> Array:
	return [LOCK_DETAIL,LOCK_SHORT]

## The viewer's own memento. Only a viewer who finished the goal sees the quote and the
## keepsake name; everybody else gets a neutral line that spoils nothing.
static func memento_message(person:Variant) -> String:
	var entry:Dictionary=Goals.goal(RESIDENT,STAGE)
	if not unlocked(person) or entry.is_empty():return NEUTRAL_MEMENTO
	var quote:Array=entry.get("quote",[])
	var lines:PackedStringArray=PackedStringArray()
	for line:Variant in quote:lines.append("「%s」"%str(line))
	var keepsake:String=str(entry.get("keepsake",""))
	return "茶亭的柱腳刻著一小段話：%s——〈%s〉，手帳收著「%s」。"%["".join(lines),str(entry.get("title",STORY_TITLE)),keepsake]

## Footprint rectangle in tile units (anchor = north-west part).
static func footprint(anchor:Vector2i) -> Rect2:
	return Rect2(Vector2(anchor),Vector2(Industry.PAVILION_SIZE,Industry.PAVILION_SIZE))

## E fallback: the key of the pavilion part nearest to `pos`, or "" when none is within reach.
## Callers use it ONLY when no other interaction target exists, so the shelter never hides
## a chest, resident, sign or any other point inside or beside it.
static func focus(objects:Dictionary,pos:Vector2) -> String:
	var best:String=""
	var best_distance:float=FOCUS_REACH
	var reach:=Vector2.ONE*FOCUS_REACH
	var end_offset:=Vector2(0.5,0.5)
	var lower:=Vector2i((pos-reach-end_offset).ceil())
	var upper:=Vector2i((pos+reach-end_offset).floor())
	for y in range(lower.y,upper.y+1):
		for x in range(lower.x,upper.x+1):
			var key:="%d,%d"%[x,y]
			var object:Dictionary=objects.get(key,{})
			if object.get("type")!=KIND:continue
			var center:=Vector2(x,y)+end_offset
			var distance:=pos.distance_to(center)
			if distance<=best_distance:
				best=key
				best_distance=distance
	return best
