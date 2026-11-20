extends RefCounted

const HANGING_POT:="hanging_flower_pot"
const SUPPORT_MESSAGE:="吊掛花盆需要掛在自己的屋頂下。"
const REMOVE_MESSAGE:="請先移下吊掛花盆，再拆除它上方的屋頂。"

static func supported(roof:Variant,owner:String) -> bool:
	return roof is Dictionary and roof.get("owner","") == owner and not owner.is_empty()
