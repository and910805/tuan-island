extends RefCounted
## C16 陶窯「磚瓦」: the kilned roof tile and the terracotta house roof laid with it.
##
## Rules only (no drawing, no World access); art lives in terracotta_roof_art.gd.
##
## * TILE (`roof_tile` 紅陶屋瓦) is a new inventory item. Its only source is the
##   Industry.PROCESS recipe at the clay kiln, so the roof needs no gate of its
##   own: whoever can run a clay kiln can lay it.
## * KIND (`terracotta_roof` 紅陶瓦屋頂) is a new entry of the `roofs` layer. It is
##   always a MANUAL roof (never carries `auto`), sits on the builder's own
##   structural floor exactly like the thatch roof `roof`, and is refunded in
##   tiles by the ordinary `remove`.
## * Re-tiling: a sealed room is thatched automatically, so the terracotta roof
##   may be laid over an existing thatch roof (see replaceable()). The thatch is
##   refunded to whoever paid for it, in the same transaction, and construction
##   undo restores it exactly.
##
## The automatic roof planner keeps its own material (thatch): it only ever
## creates/removes `roof` entries with auto=true and leaves manual roofs alone.

const KIND := "terracotta_roof"
const NAME := "紅陶瓦屋頂"
const TILE := "roof_tile"
const TILE_NAME := "紅陶屋瓦"
const THATCH := "roof"
## Roof kinds that are a house roof over structural floor (not greenhouse glass).
const HOUSE_ROOFS: Array[String] = [THATCH, KIND]
## Kinds the hold-and-drag area build can lay on the roofs layer.
const AREA_ROOFS: Array[String] = [THATCH, KIND]

const MSG_OCCUPIED := "這裡已經是紅陶瓦屋頂"
const MSG_OTHER_ROOF := "這裡的屋頂不能改鋪紅陶瓦"
const MSG_FLOOR := "先鋪地板，再鋪上紅陶瓦"
const MSG_HANGER := "請先移下吊掛花盆，再改鋪紅陶瓦。"
const MSG_PAYER := "找不到原屋頂出資者的背包。"
const MSG_FULL := "原屋頂的材料退不回背包，這次沒有改鋪"
const MSG_AREA := "整片紅陶瓦都需要自己的地板，且只能改鋪草編屋頂"

static func is_house_roof(kind) -> bool:
	return kind is String and kind in HOUSE_ROOFS

## True when `existing` (a roofs-layer entry) may be re-tiled by `token`: a
## thatch roof that is automatic (any recorded payer) or was laid by `token`.
static func replaceable(existing, token: String) -> bool:
	if not existing is Dictionary or existing.get("type") != THATCH:return false
	var owner = existing.get("owner")
	if not owner is String or owner.is_empty():return false
	var flag = existing.get("auto")
	return (flag is bool and flag) or owner == token
