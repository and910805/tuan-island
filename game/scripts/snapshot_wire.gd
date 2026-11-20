extends RefCounted

const OFFER := "tuan-snapshot=zstd1"
const DELTA_OFFER := "tuan-delta=keyframe1"
const CELL_OFFER := "tuan-cells=keyframe1"
const COMPRESSED := "_wire_zstd"
const RAW_SIZE := "_wire_size"
const FRAME := "_wire_frame"
const SET := "_wire_set"
const ERASE := "_wire_erase"
const CELLS := "_wire_cells"
const CELL_LAYERS := ["crops","objects","ground","roofs","edges","forest","removed","damage"]
const KEYFRAME_INTERVAL := 20
const MAX_RAW_BYTES := 4 * 1024 * 1024

static func offer(address:String) -> String:
	if address.contains("#"):return address
	var parts:=address.split("?",true,1)
	var path:=parts[0]
	if path.find("/",path.find("://")+3)<0:path+="/"
	if parts.size()==1 or parts[1].is_empty():return path+"?"+OFFER
	return path+"?"+parts[1]+("&"+OFFER if not accepts(address) else "")

static func accepts(requested_url:String) -> bool:
	var parts:=requested_url.split("?",true,1)
	return parts.size()==2 and OFFER in parts[1].split("&")

static func offer_delta(address:String) -> String:
	var offered:=offer(address)
	if offered.contains("#") or accepts_delta(offered):return offered
	return offered+"&"+DELTA_OFFER

static func accepts_delta(requested_url:String) -> bool:
	var parts:=requested_url.split("?",true,1)
	return parts.size()==2 and OFFER in parts[1].split("&") and DELTA_OFFER in parts[1].split("&")

static func offer_cells(address:String) -> String:
	var offered:=offer_delta(address)
	return offered if offered.contains("#") or accepts_cells(offered) else offered+"&"+CELL_OFFER

static func accepts_cells(requested_url:String) -> bool:
	var parts:=requested_url.split("?",true,1)
	return accepts_delta(requested_url) and CELL_OFFER in parts[1].split("&")

# Deltas refer to a fixed keyframe. Skipping a delta never affects the next one.
static func keyframe(snapshot:Dictionary,frame:int) -> Dictionary:
	var packet:=snapshot.duplicate()
	packet[FRAME]=frame
	return packet

static func difference(snapshot:Dictionary,base:Dictionary,frame:int,cell_deltas:=false) -> Dictionary:
	var fields:Dictionary={}
	var removed:Array[String]=[]
	var cells:Dictionary={}
	for field:String in snapshot:
		if base.has(field) and base[field]==snapshot[field]:continue
		var current:Variant=snapshot[field]
		var previous:Variant=base.get(field)
		if cell_deltas and field in CELL_LAYERS and current is Dictionary and previous is Dictionary:
			var patch:=_cell_difference(current,previous)
			if patch[SET].size()+patch[ERASE].size()+2<current.size():
				cells[field]=patch
				continue
		fields[field]=current
	for field:String in base:
		if not snapshot.has(field):removed.append(field)
	var packet:Dictionary={FRAME:frame,SET:fields,ERASE:removed}
	if not cells.is_empty():packet[CELLS]=cells
	return packet

static func _cell_difference(current:Dictionary,previous:Dictionary) -> Dictionary:
	var changed:Dictionary={}
	var removed:Array=[]
	for cell:Variant in current:
		if not previous.has(cell) or current[cell]!=previous[cell]:changed[cell]=current[cell]
	for cell:Variant in previous:
		if not current.has(cell):removed.append(cell)
	return {SET:changed,ERASE:removed}

static func restore(packet:Dictionary,base:Dictionary,frame:int) -> Dictionary:
	if frame<1 or packet.get(FRAME)!=frame or packet.size()!=(4 if packet.has(CELLS) else 3):return {}
	if not packet.get(SET) is Dictionary or not packet.get(ERASE) is Array:return {}
	var cells:Variant=packet.get(CELLS,{})
	if not cells is Dictionary:return {}
	var result:=base.duplicate(true)
	for field:Variant in packet[ERASE]:
		if not field is String:return {}
		result.erase(field)
	for field:Variant in packet[SET]:
		if not field is String or field in [FRAME,SET,ERASE,CELLS]:return {}
		result[field]=packet[SET][field]
	for field:Variant in cells:
		if field not in CELL_LAYERS or packet[SET].has(field) or packet[ERASE].has(field):return {}
		if not result.get(field) is Dictionary:return {}
		var patch:Variant=cells[field]
		if not patch is Dictionary or patch.size()!=2 or not patch.get(SET) is Dictionary or not patch.get(ERASE) is Array:return {}
		var layer:Dictionary=result[field]
		for cell:Variant in patch[ERASE]:
			layer.erase(cell)
		layer.merge(patch[SET],true)
	return result if result.get("players") is Dictionary else {}

static func encode(snapshot:Dictionary) -> Dictionary:
	var raw:=var_to_bytes(snapshot)
	if raw.size()>MAX_RAW_BYTES:return snapshot
	var compressed:=raw.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.is_empty() or compressed.size()+64>=raw.size():return snapshot
	return {COMPRESSED:compressed,RAW_SIZE:raw.size()}

# An empty result indicates an invalid compressed packet. The caller keeps the last snapshot.
static func decode(packet:Dictionary) -> Dictionary:
	if not packet.has(COMPRESSED):return packet
	var payload:Variant=packet.get(COMPRESSED)
	var size:Variant=packet.get(RAW_SIZE)
	if packet.size()!=2 or not payload is PackedByteArray or not size is int:return {}
	if size<1 or size>MAX_RAW_BYTES or payload.is_empty() or payload.size()>=size:return {}
	var raw:PackedByteArray=payload.decompress(size,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=size:return {}
	var snapshot:Variant=bytes_to_var(raw)
	return snapshot if snapshot is Dictionary and (snapshot.get("players") is Dictionary or snapshot.has(SET)) else {}
