extends RefCounted

const CHIME:="ceramic_eave_chime"
const LIGHT:="warm_lamp_niche"
const KINDS:=[CHIME,LIGHT]
const SUPPORT_MESSAGE:="請放在自己木牆的南面。"
const REMOVE_MESSAGE:="請先拆下掛在這面牆上的家具。"

static func has_support(objects:Dictionary,at:Vector2i,owner:String) -> bool:
	var wall=objects.get("%d,%d"%[at.x,at.y-1])
	return wall is Dictionary and wall.get("type")=="wall" and wall.get("owner")==owner
