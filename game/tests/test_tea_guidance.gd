extends SceneTree

const Guide=preload("res://scripts/tea_guidance.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
var checks:=0
var failures:=0

func expect(ok:bool,detail:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(detail)

func step(progress:Dictionary={},inventory:Dictionary={},region:String="home") -> Dictionary:
	var record:=Tea.FRESH.duplicate(true)
	record.merge(progress,true)
	var snapshot:={"region_id":region,"time":20.0,"players":{"mine":{"inventory":inventory},"other":{"inventory":{"tea_deep":1,"tea_jar":1}}},"tea_ceramics":{"own_record":record}}
	var before:=snapshot.duplicate(true)
	var result:=Guide.next_step(snapshot,"mine")
	expect(snapshot==before and result.size()==5,"Guide is read-only and returns its five-field contract")
	return result

func _initialize() -> void:
	var basic:={"intro":true,"potter":true}
	expect(Guide.next_step({},"").is_empty(),"No guidance without local actor")
	expect(step().site=="home" and step().cell==Tea.RECEIVER,"Introduction points to Xiao Li")
	var potter:=step({"intro":true},{"fiber":10})
	expect(potter.site=="potter" and potter.region==Tea.YINGGE and potter.text.contains("鶯歌合作陶坊"),"Main route introduces the potter and names the remote destination")
	expect(step(basic,{"clay":2,"fiber":10}).site=="kiln","Two clay leads to firing the first jar")
	var starter:={"wood":12,"stone":4,"fiber":10}
	expect(step({"intro":true},starter).site=="potter","Starter fiber still allows the introduction to pottery")
	starter.clay=2
	expect(step(basic,starter,Tea.YINGGE).site=="kiln","After the first clay grant, the starter bag leads to the kiln")
	starter.clay=0
	starter.tea_jar=1
	expect(step(basic,starter,Tea.YINGGE).site=="pick","After collecting the jar, the starter bag leads to the tea plants")
	expect(step(basic,{"stone":2}).site=="clay","Stone can fund replacement clay")
	var ready_jar:=step({"intro":true,"potter":true,"kiln":{"ready":20.0}})
	expect(ready_jar.site=="kiln" and ready_jar.title=="取出陶罐","A ready kiln job can be collected")
	var harvest:=step({"intro":true,"potter":true,"harvest_ready":{"0":21.0}},{"tea_jar":1},Tea.MAOKONG)
	expect(harvest.site=="pick" and harvest.cell==Tea.TEA_NODES[1] and not harvest.text.begins_with("前往"),"Choose an available tea plant and omit redundant travel")
	expect(step(basic,{"tea_leaf":2,"tea_jar":1}).site=="roast","Available leaves can be roasted")
	for style in ["light","deep"]:
		var ready_tea:=step({"intro":true,"roast":{"ready":20.0,"style":style}})
		expect(ready_tea.site=="roast" and ready_tea.title.contains("淺焙" if style=="light" else "深焙"),"Ready roast identifies its style")
	expect(step(basic,{"tea_light":1,"fiber":1}).title=="用纖維包裝","Fiber route can package without any jar")
	expect(step(basic,{"tea_deep":1}).title=="準備包材","Missing wrapping gives a concrete alternative")
	expect(step(basic,{"tea_deep":1,"stone":2}).title=="到備土台交換黏土","Ready clay exchange does not show a zero-second cooldown")
	expect(step(basic,{"tea_deep":1,"clay":2,"stone":2}).site=="kiln","Owned clay points to firing instead of another exchange")
	var cooling:=step({"intro":true,"potter":true,"clay_ready":25.0},{"tea_deep":1,"stone":2},Tea.YINGGE)
	expect(cooling.title=="備土台補貨中" and cooling.text.contains("5 秒"),"Actual clay cooldown is shown when wrapping must wait")
	expect(step(basic,{"tea_deep":1,"tea_returned_jar":1}).title=="用回收罐裝茶","Returned jar can be used for the new batch")
	var packed:={"style":"light","wrap":"fiber"}
	expect(step({"intro":true,"packed":packed,"returning":{"ready":30.0}}).title=="把茶寄給小栗","Waiting return does not block shipping")
	expect(step({"intro":true,"returning":{"ready":20.0},"outbound":{"ready":30.0}}).title=="領回空陶罐","Waiting tea does not mask ready jar return")
	var sold:=step({"intro":true,"returning":{"ready":21.0},"outbound":{"ready":20.0,"style":"deep","wrap":"jar"}})
	expect(sold.title=="向小栗收款" and sold.text.contains("56"),"Ready tea shipment takes priority over a waiting return")
	expect(step({"intro":true,"empties":1}).title=="寄回空陶罐","Manual empty return is guided")
	expect(step({"intro":true,"returning":{"ready":22.0}},{"tea_leaf":2}).title=="開始烘焙","Waiting return does not prevent roasting available leaves")
	var all_cooling:={"0":21.0,"1":22.0,"2":23.0}
	var wait:=step({"intro":true,"potter":true,"returning":{"ready":22.4},"harvest_ready":all_cooling},{"fiber":1})
	expect(wait.title=="空罐正在回程" and wait.text.contains("3 秒"),"When there is no other work, show the remaining return time")
	expect(step({"intro":true,"potter":true,"reused":true},{"tea_returned_jar":1}).title=="採茶，開始下一批","Completed return leads to another batch")
	print("TEA_GUIDANCE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
