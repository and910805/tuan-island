extends SceneTree

const Wire=preload("res://scripts/snapshot_wire.gd")
var checks:=0
var failures:=0

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)

func _initialize() -> void:
	for address in ["ws://127.0.0.1:123", "wss://island.example", "wss://island.example/room?ref=invite", "wss://[::1]:443/"]:
		var offered:=Wire.offer(address)
		expect(Wire.accepts(offered) and offered==Wire.offer(offered),"Offer is exact and idempotent for "+address)
	expect(Wire.offer("wss://island.example")=="wss://island.example/?"+Wire.OFFER,"Root address supplies a request path")
	expect(Wire.offer("wss://island.example/room?ref=invite")=="wss://island.example/room?ref=invite&"+Wire.OFFER,"Existing path and query stay intact")
	expect(not Wire.accepts("/room?note="+Wire.OFFER) and not Wire.accepts("/room?"+Wire.OFFER+"2"),"Other query values do not opt in")
	var snapshot:={"players":{"self":{"name":"島民","coins":3,"position":Vector2(2,3)}},"tile":Vector2i(7,9),"hint":"望安".repeat(1000)}
	var encoded:=Wire.encode(snapshot)
	expect(encoded.has(Wire.COMPRESSED),"Repetitive snapshot is compressed")
	expect(Wire.decode(encoded)==snapshot,"Typed positions, integers, Unicode and private fields survive")
	expect(Wire.decode(snapshot)==snapshot,"Legacy plain packet still decodes")
	expect(Wire.encode({"players":{}})=={"players":{}},"Tiny packets remain plain")
	var oversized:Dictionary=encoded.duplicate()
	oversized[Wire.RAW_SIZE]=Wire.MAX_RAW_BYTES+1
	expect(Wire.decode(oversized).is_empty(),"Oversized declaration rejected")
	var inconsistent:Dictionary=encoded.duplicate()
	inconsistent[Wire.RAW_SIZE]+=1
	expect(Wire.decode(inconsistent).is_empty(),"Incorrect uncompressed count rejected")
	var invalid:Dictionary=encoded.duplicate()
	invalid[Wire.COMPRESSED]="not bytes"
	expect(Wire.decode(invalid).is_empty(),"Wrong envelope type rejected")
	var offered:=Wire.offer_delta("wss://island.example/room?ref=invite")
	expect(Wire.accepts(offered) and Wire.accepts_delta(offered) and offered==Wire.offer_delta(offered),"Delta negotiation retains the legacy compression offer and is idempotent")
	expect(not Wire.accepts_delta(Wire.offer("wss://island.example")) and not Wire.accepts_delta("/room?"+Wire.DELTA_OFFER),"Old clients and partial offers keep using full snapshots")
	var base:Dictionary={"region_id":"home","players":{"self":{"name":"小栗","coins":3}},"map_signals":[Vector2i(3,4)],"crops":{}}
	for i in range(80):
		base.crops["%d,2"%i]={"kind":"tomato","growth":float(i),"wet":i%2==0}
	var first:Dictionary=base.duplicate(true)
	first.players.self.coins=7
	first.erase("map_signals")
	first["time"]=12.0
	var later:Dictionary=base.duplicate(true)
	later["time"]=13.0
	var delta:=Wire.difference(first,base,1)
	var packet:=Wire.encode(delta)
	expect(var_to_bytes(packet).size()*2<var_to_bytes(Wire.encode(Wire.keyframe(first,1))).size(),"A changing player and clock with stable crops uses less than half of a keyframe")
	var restored:=Wire.restore(Wire.decode(packet),base,1)
	expect(restored==first and not restored.has("map_signals"),"Wire round-trip adds, updates and removes fields")
	expect(Wire.restore(delta,base,2).is_empty(),"A previous-region or missing keyframe is rejected")
	restored.crops.clear()
	expect(Wire.restore(Wire.difference(later,base,1),base,1)==later,"A later delta works independently, restores reverted fields and preserves the base from UI mutation")
	var large_delta:=Wire.difference({"players":{},"notice":"渡口".repeat(1000)},{"players":{}},1)
	var packed_delta:=Wire.encode(large_delta)
	expect(packed_delta.has(Wire.COMPRESSED) and Wire.decode(packed_delta)==large_delta,"Compressed delta envelopes decode without a player update")
	var cells_url:=Wire.offer_cells("wss://island.example/room?ref=invite")
	expect(Wire.accepts_cells(cells_url) and Wire.offer_cells(cells_url)==cells_url,"Cell updates negotiate separately without changing older offers")
	expect(not Wire.accepts_cells(offered) and not Wire.accepts_cells("/room?"+Wire.CELL_OFFER),"Cell updates require base delta and compression offers")
	var harvest:=base.duplicate(true)
	harvest.crops.erase("0,2")
	harvest.crops["45,2"].wet=true
	harvest.crops["80,2"]={"kind":"radish","growth":0.0,"wet":false}
	var patched:=Wire.difference(harvest,base,1,true)
	var old_delta:=Wire.difference(harvest,base,1)
	var patched_data:=Wire.restore(Wire.decode(Wire.encode(patched)),base,1)
	var crop_patch:Dictionary=patched.get(Wire.CELLS,{}).get("crops",{})
	print("CELL_PAYLOAD previous=%d patched=%d"%[var_to_bytes(Wire.encode(old_delta)).size(),var_to_bytes(Wire.encode(patched)).size()])
	expect(crop_patch.get(Wire.SET,{}).size()==2 and crop_patch.get(Wire.ERASE,[])==["0,2"],"One plot's changes omit all unrelated crops")
	expect(not old_delta.has(Wire.CELLS) and old_delta[Wire.SET].crops.size()==80,"Older peers still receive ordinary keyframe deltas")
	expect(patched_data==harvest and var_to_bytes(Wire.encode(patched)).size()<var_to_bytes(Wire.encode(old_delta)).size(),"Negotiated compressed update is smaller and restores exactly")
	patched_data.crops["1,2"].wet=true
	expect(not base.crops["1,2"].wet and Wire.restore(Wire.difference(later,base,1,true),base,1)==later,"A later update works independently and keeps the keyframe intact")
	var cleared:=base.duplicate(true)
	cleared.crops.clear()
	expect(Wire.restore(Wire.difference(cleared,base,1,true),base,1)==cleared,"Mass removals can replace the layer with an empty one")
	var invalid_patch:=patched.duplicate(true)
	invalid_patch[Wire.CELLS]["players"]=invalid_patch[Wire.CELLS]["crops"]
	expect(Wire.restore(invalid_patch,base,1).is_empty(),"Cell patches cannot change personal or global fields")
	var overlap:=patched.duplicate(true)
	overlap[Wire.SET]["crops"]={}
	expect(Wire.restore(overlap,base,1).is_empty(),"A cell patch cannot overlap a full replacement")
	print("SNAPSHOT_WIRE_TEST checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
