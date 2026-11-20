extends RefCounted

const EdgeGrid:=preload("res://scripts/edge_grid.gd")

const CHIME:="ceramic_eave_chime"
const LIGHT:="warm_lamp_niche"
const LIFEBUOY:="wall_lifebuoy"
const BARK_FRAME:="bark_picture_frame"
const HOME_SIGN:="handcarved_home_sign"
const TOOL_BOARD:="wall_tool_board"
const TOOL_BOARD_WRITE:="tool_board_write"
const TOOL_BOARD_FIELD:="tool_board_tools"
const TOOL_BOARD_SUPPORT:="請在自己相連的兩段木牆南面掛上工具板。"
const TOOL_LOOKS:={"":"空掛鉤","hoe":"鋤頭","axe":"斧頭","pick":"十字鎬","water":"澆水壺","fish":"釣竿","seed":"種子袋"}
const BAMBOO_CURTAIN:="bamboo_curtain"
## Manual-only wind chime: ringing it never changes the world state or the bag.
const WATER_LISTENING_CHIME:="water_listening_chime"
const WATER_CHIME_RING:="water_chime_ring"
const WATER_CHIME_REACH:=3.2
const KINDS:=[CHIME,LIGHT,LIFEBUOY,BARK_FRAME,HOME_SIGN,TOOL_BOARD,BAMBOO_CURTAIN,WATER_LISTENING_CHIME]
const SUPPORT_MESSAGE:="請放在自己木牆的南面。"
const REMOVE_MESSAGE:="請先拆下掛在這面牆上的家具。"
const CURTAIN_SUPPORT_MESSAGE:="請掛在自己窗戶的南面。"
const CURTAIN_REMOVE_MESSAGE:="請先取下掛在這扇窗上的竹簾。"
## Fixtures hang on the wall by default; the bamboo curtain hangs on a window instead
## (the window stays in place, the curtain is its own object on the cell south of it).
const SUPPORT_TYPES:={BAMBOO_CURTAIN:"window"}

static func support_type(kind:String="") -> String:
	return str(SUPPORT_TYPES.get(kind,"wall"))

static func support_message(kind:String="") -> String:
	return CURTAIN_SUPPORT_MESSAGE if kind==BAMBOO_CURTAIN else SUPPORT_MESSAGE

static func remove_message(kind:String="") -> String:
	return CURTAIN_REMOVE_MESSAGE if kind==BAMBOO_CURTAIN else REMOVE_MESSAGE

## True when `kind` hangs on the support type `support_kind` (wall or window).
static func hangs_on(kind:String,support_kind:String) -> bool:
	return kind in KINDS and support_type(kind)==support_kind

## Canonical id of the edge on the north side of `at` (the same string EdgeGrid.key(at,SIDE_N) emits).
static func north_edge_id(at:Vector2i) -> String:
	return "%d,%d,%s"%[at.x,at.y,EdgeGrid.SIDE_LETTERS[EdgeGrid.SIDE_N]]

## `kind` selects the support type; the default keeps the ordinary wall rule.
## Support is either the legacy tile north of `at`, or the edge row on the north edge of `at`
## (edge_wall, or edge_window for bamboo curtains), in both cases with the same owner.
static func has_support(objects:Dictionary,at:Vector2i,owner:String,kind:String="",edges:Dictionary={}) -> bool:
	var support=objects.get("%d,%d"%[at.x,at.y-1])
	if support is Dictionary and support.get("type")==support_type(kind) and support.get("owner")==owner:return true
	var row=edges.get(north_edge_id(at))
	return row is Dictionary and row.get("type")=="edge_"+support_type(kind) and row.get("owner")==owner

## Both halves need a wall support; legacy tile and edge supports may be mixed.
static func has_tool_board_support(objects:Dictionary,anchor:Vector2i,owner:String,edges:Dictionary={})->bool:
	return has_support(objects,anchor,owner,"",edges) and has_support(objects,anchor+Vector2i.RIGHT,owner,"",edges)

## Reason (empty when fine) why removing `edge_id` would strand a mounted prop. `edges` must still
## contain the edge being removed. Only a north (horizontal) edge can carry a prop, which sits on the
## cell south of it; every record there (both halves of a tool board each have their own) is judged.
## A legacy tile of the same support type and owner north of the cell is a substitute.
static func removal_problem(objects:Dictionary,edges:Dictionary,edge_id:String)->String:
	var decoded:=EdgeGrid.decode(edge_id,Vector2i(1000000,1000000))
	if decoded.is_empty() or decoded.side!=EdgeGrid.SIDE_N:return ""
	var row=edges.get(edge_id)
	if not row is Dictionary:return ""
	var cell:Vector2i=decoded.cell
	var prop=objects.get("%d,%d"%[cell.x,cell.y])
	if not prop is Dictionary:return ""
	var kind=prop.get("type")
	if not kind is String or not kind in KINDS:return ""
	if row.get("type")!="edge_"+support_type(kind) or row.get("owner")!=prop.get("owner"):return ""
	var tile=objects.get("%d,%d"%[cell.x,cell.y-1])
	if tile is Dictionary and tile.get("type")==support_type(kind) and tile.get("owner")==prop.get("owner"):return ""
	return remove_message(kind)

static func valid_tool_board_tools(tools:Variant)->bool:
	if not tools is Array or tools.size()!=2:return false
	for tool:Variant in tools:
		if not tool is String or not TOOL_LOOKS.has(tool):return false
	return true
