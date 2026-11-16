extends SceneTree
## A persisted JSON receipt must retain the same public totals after a restart.
const Protocol=preload("res://scripts/blueprint_protocol.gd")
var checks:=0
var failures:=0

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func _initialize()->void:
	var names:={"wood":"木材","fiber":"纖維","stone":"石材"}
	var original:={"ok":true,"message":"施工完成","blueprint":true,"pieces":26,
		"roof_add":9,"roof_remove":0,"cost":{"wood":96,"fiber":39,"stone":1},"hash":"a".repeat(64)}
	var loaded:Variant=JSON.parse_string(JSON.stringify(original))
	check(typeof(loaded.pieces)==TYPE_FLOAT,"fixture really has JSON-decoded numeric values")
	var before:Dictionary=Protocol.sanitize(original,names)
	var after:Dictionary=Protocol.sanitize(loaded,names)
	check(after==before,"public receipt totals unchanged after JSON save/reload")
	check(after.pieces==26 and after.roof_add==9 and after.roof_remove==0,"reloaded piece and roof counts preserved")
	check(after.cost=={"wood":96,"fiber":39,"stone":1},"reloaded material costs preserved")
	check(typeof(after.pieces)==TYPE_INT and typeof(after.cost.get("wood"))==TYPE_INT,"wire receipt normalizes whole JSON numbers to integers")
	for invalid in [true,false,-1,1.5,NAN,INF,"26",null,1000000001]:
		var bad:Dictionary=Protocol.sanitize({"ok":true,"message":"test","pieces":invalid,"cost":{"wood":invalid}},names)
		check(bad.pieces==0 and bad.cost.is_empty(),"invalid numeric value rejected: "+str(invalid))
	var private:Dictionary=original.duplicate(true)
	private.owner="private-owner"
	private.sim={"players":{"private-owner":{}}}
	private.cost["private-owner"]=5
	var public:Dictionary=Protocol.sanitize(private,names)
	check(not JSON.stringify(public).contains("private-owner") and not public.has("sim"),"unknown materials and private fields never forwarded")
	public.cost.wood=1
	check(original.cost.wood==96 and private.cost.wood==96,"sanitized result never aliases original receipt")
	print("BLUEPRINT_PROTOCOL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
