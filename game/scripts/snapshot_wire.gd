extends RefCounted

const OFFER := "tuan-snapshot=zstd1"
const COMPRESSED := "_wire_zstd"
const RAW_SIZE := "_wire_size"
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
	return snapshot if snapshot is Dictionary and snapshot.get("players") is Dictionary else {}
