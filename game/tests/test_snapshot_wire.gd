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
	print("SNAPSHOT_WIRE_TEST checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
