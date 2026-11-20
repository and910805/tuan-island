extends RefCounted
## T046: optional home-island projection of the persistent cell layers.
##
## A client opts in by sending `view_interest` with extra == OPT_IN (phase 1:
## crops, forest, removed) or OPT_IN_2 (phase 2: also ground, roofs, edges).
## The server then marks every home snapshot for that peer with
##   view_rect  = [x,y,w,h]   cells the packet is authoritative for
##   view_full  = true|false  true: the layers are complete (seed, refresh, whole-island request)
##                            false: the layers hold only what `inside` accepts for view_rect,
##                            plus the recipient's own rows anywhere (always exact, see `exact`)
##   view_level = 2           only on phase 2 packets; absent means phase 1
## `view_full` is the only full/projected signal; never infer it from the rectangle.
## Snapshots without `view_full` are legacy packets and are never composed.
##
## The client keeps the last known far cells and composes them back into each
## projected snapshot, so whole-island readers see old data and never a gap.
## `objects` is never projected here (phase 3).
const OPT_IN := "layers1"
const OPT_IN_2 := "layers2"
const ADVERT := "view_layers"
const RECT := "view_rect"
const FULL := "view_full"
const LEVEL := "view_level"
const MAX_LEVEL := 2
const LAYERS := ["crops","forest","removed"]
const STRUCTURE_LAYERS := ["ground","roofs","edges"]
## Layers whose rows carry `owner`: the recipient's own rows are sent wherever they are.
const OWNED_LAYERS := ["crops","ground","roofs","edges"]
const REFRESH_MS := 30000

static func level_of(extra:String) -> int:
	return 1 if extra==OPT_IN else 2 if extra==OPT_IN_2 else 0

static func opt_in(level:int) -> String:
	return "" if level<1 else OPT_IN if level==1 else OPT_IN_2

## Highest level a server offers: phase 1 servers advertise `true`, later ones their level.
static func offered_level(advert:Variant) -> int:
	if advert is bool:return 1 if advert else 0
	return clampi(advert,0,MAX_LEVEL) if advert is int else 0

static func layers(level:int) -> Array:
	return LAYERS+STRUCTURE_LAYERS if level>=2 else LAYERS

static func cell(key:Variant) -> Vector2i:
	var text:=str(key)
	return Vector2i(int(text.get_slice(",",0)),int(text.get_slice(",",1)))

## Whether a projection for `rect` is authoritative for this key.
## Cell layers: the cell lies in the rectangle.
## Edges use canonical keys "x,y,N" / "x,y,W" (edge_grid.gd), written from the cell
## south or east of the boundary. An edge belongs to both cells it separates, so it
## is eligible when either of them lies in the rectangle: every cell in the window
## then has all four of its sides, including rim edges whose owner cell is off-map.
## A key that is not a canonical edge is treated as eligible, so it is always sent
## and never kept from an older packet.
static func inside(layer:String,key:Variant,rect:Rect2i) -> bool:
	if layer!="edges":return rect.has_point(cell(key))
	var text:=str(key)
	if text.get_slice_count(",")!=3:return true
	var owner:=cell(text)
	var side:=text.get_slice(",",2)
	if side=="N":return rect.has_point(owner) or rect.has_point(owner+Vector2i(0,-1))
	if side=="W":return rect.has_point(owner) or rect.has_point(owner+Vector2i(-1,0))
	return true

## Rows sent exactly wherever they are: the recipient's own crops, and from phase 2
## the recipient's own ground, roofs and edges. A player's whole own structure
## therefore stays current, and so do the per-owner fields its ground carries
## (room privacy, leaf-mat parts and shades).
static func exact(layer:String,value:Variant,own:String) -> bool:
	return layer in OWNED_LAYERS and not own.is_empty() and value is Dictionary and str(value.get("owner",""))==own

static func packet_rect(data:Dictionary) -> Rect2i:
	var rect:Variant=data.get(RECT)
	if not rect is Array or rect.size()!=4:return Rect2i()
	for part:Variant in rect:
		if not part is int:return Rect2i()
	return Rect2i(rect[0],rect[1],rect[2],rect[3])

## 1 or 2 for a marked packet, 0 when the level is not one this build composes.
static func packet_level(data:Dictionary) -> int:
	var level:Variant=data.get(LEVEL,1)
	return level if level is int and level>=1 and level<=MAX_LEVEL else 0

## True when the persistent layers of this snapshot are complete as sent by the
## server: a legacy, host or full packet. False for a composed projection, whose
## far cells may be up to one refresh old.
static func complete(data:Dictionary) -> bool:
	return data.get(FULL)!=false

## As `complete`, for ground, roofs and edges only: a phase 1 projection never trims them.
static func structure_complete(data:Dictionary) -> bool:
	return data.get(FULL)!=false or packet_level(data)==1

# ------------------------------------------------------------------ server --

static func _mark(data:Dictionary,rect:Rect2i,full:bool,level:int) -> void:
	data[RECT]=[rect.position.x,rect.position.y,rect.size.x,rect.size.y]
	data[FULL]=full
	if level>=2:data[LEVEL]=level
	else:data.erase(LEVEL)

static func mark_full(data:Dictionary,world_rect:Rect2i,level:=1) -> void:
	_mark(data,world_rect,true,level)

## Marks a packet whose layers were already chosen with `select` as a projection.
static func mark_projected(data:Dictionary,rect:Rect2i,level:=1) -> void:
	_mark(data,rect,false,level)

## The rows `project` keeps, as a new dictionary in the source order that shares the
## row values with `cells`. It runs before the per-recipient copy and redaction, so
## rows nobody will receive are never copied; `own` must be in the form the rows'
## `owner` has at that point (the raw value before redaction). Never modifies `cells`.
static func select(layer:String,cells:Dictionary,rect:Rect2i,own:String,positions:Variant=null) -> Dictionary:
	var kept:Dictionary={}
	var reuse_positions:=positions is Dictionary and layer!="edges"
	for key:Variant in cells:
		var value:Variant=cells[key]
		var visible:bool
		if reuse_positions:
			if not positions.has(key):positions[key]=cell(key)
			visible=rect.has_point(positions[key])
		else:visible=inside(layer,key,rect)
		if visible or exact(layer,value,own):kept[key]=value
	return kept

## Trims the layers of an already private per-recipient copy. Never touches world state.
## Reference for `select` + `mark_projected`, which must give the same packet.
static func project(data:Dictionary,rect:Rect2i,own:String,level:=1) -> void:
	for layer:String in layers(level):
		var cells:Variant=data.get(layer)
		if not cells is Dictionary:continue
		for key:Variant in cells.keys():
			if not inside(layer,key,rect) and not exact(layer,cells[key],own):cells.erase(key)
	_mark(data,rect,false,level)

# ------------------------------------------------------------------ client --

var _context:=""
var _layers:Dictionary={}
var _parts:Dictionary={}
var _rect:=Rect2i()

func reset() -> void:
	_context=""
	_layers.clear()
	_parts.clear()
	_rect=Rect2i()

## Call only with a snapshot that was fully decoded and restored. Returns the
## snapshot to show: `data` itself for legacy or full packets, otherwise a
## shallow copy whose layers are the projection laid over the last known cells.
## `data` and its layers are never modified, so it stays valid as a delta base.
func compose(data:Dictionary,own:String) -> Dictionary:
	var rect:=packet_rect(data)
	var level:=packet_level(data)
	var players:Variant=data.get("players")
	var player:Variant=players.get(own) if players is Dictionary else null
	if not data.get(FULL) is bool or level<1 or not rect.has_area() or not player is Dictionary:
		reset()
		return data
	var names:=layers(level)
	for layer:String in names:
		if not data.get(layer) is Dictionary:
			reset()
			return data
	# A cache belongs to one stay in one region for one player at one level.
	var context:="%s|%d|%s|%d"%[str(data.get("region_id","")),int(player.get("travel_epoch",0)),own,level]
	if context!=_context:
		reset()
		_context=context
	if data[FULL]:
		for layer:String in names:_layers[layer]=data[layer]
		_parts.clear()
		_rect=Rect2i()
		return data
	var out:=data.duplicate()
	var parts:Dictionary={}
	for layer:String in names:
		var part:Dictionary=data[layer]
		parts[layer]=part
		if rect==_rect and _parts.has(layer) and _layers.has(layer) and _parts[layer]==part:
			# Same window, same cells: the last composition still holds.
			out[layer]=_layers[layer]
			continue
		var merged:Dictionary=_layers.get(layer,{}).duplicate()
		if rect==_rect and _parts.has(layer):
			# Same window: only cells the previous projection held can have gone.
			for key:Variant in _parts[layer]:
				if not part.has(key):merged.erase(key)
		else:
			for key:Variant in merged.keys():
				if inside(layer,key,rect) or exact(layer,merged[key],own):merged.erase(key)
		merged.merge(part,true)
		out[layer]=merged
		_layers[layer]=merged
	_parts=parts
	_rect=rect
	return out
