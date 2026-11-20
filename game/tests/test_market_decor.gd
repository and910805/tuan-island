extends SceneTree
const Decor=preload("res://scripts/market_decor.gd")
var checks:=0
var failures:=0
func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)
func _initialize() -> void:
	expect(Decor.CLOTH.keys()==["natural","indigo","leaf"] and Decor.SIGN.keys()==["plain","windbell","flower"],"option keys")
	var person:={"coins":5,"name":"米"}
	expect(Decor.style(person)=={"cloth":"natural","sign":"plain"},"defaults")
	expect(Decor.remark(Decor.style(person))=="","default remark empty")
	var before:=person.duplicate(true)
	var r:=Decor.change(person,"cloth|indigo")
	expect(r.ok and r.message!="" and person.market_decor=={"cloth":"indigo","sign":"plain"},"cloth change")
	r=Decor.change(person,"sign|flower")
	expect(r.ok and Decor.style(person)=={"cloth":"indigo","sign":"flower"},"sign change keeps cloth")
	person.erase("market_decor")
	expect(person==before,"no fields beyond market_decor touched")
	person.market_decor={"cloth":"leaf","sign":"windbell"}
	var snap:=person.duplicate(true)
	for bad in ["","cloth","cloth|","|indigo","cloth|plain","sign|leaf","Cloth|indigo","cloth|indigo ","cloth|indigo|x","cloth||indigo","hat|leaf"," cloth|indigo"]:
		r=Decor.change(person,bad)
		expect(not r.ok and r.message!="" and person==snap,"rejects %s without mutation"%bad)
	r=Decor.change(person,"cloth|leaf")
	expect(not r.ok and person==snap,"same choice is not a change")
	expect(Decor.valid({"cloth":"leaf","sign":"flower"}),"valid accepted")
	for bad in [null,1,"x",[],{},{"cloth":"leaf"},{"cloth":"leaf","sign":"flower","x":1},{"cloth":"gold","sign":"plain"},{"cloth":"leaf","sign":"gold"},{"cloth":1,"sign":"plain"},{"cloth":&"leaf","sign":"plain"},{"cloth":"leaf","sign":null}]:
		expect(not Decor.valid(bad),"invalid rejected %s"%str(bad))
	var broken:={"market_decor":{"cloth":"leaf","sign":"nope"}}
	expect(Decor.style(broken)==Decor.default_style(),"invalid saved falls back")
	r=Decor.change(broken,"sign|windbell")
	expect(r.ok and broken.market_decor=={"cloth":"natural","sign":"windbell"},"change repairs invalid saved")
	var seen:={}
	for c in Decor.CLOTH:
		for s in Decor.SIGN:
			var t:=Decor.remark({"cloth":c,"sign":s})
			if c=="natural" and s=="plain":expect(t=="","default combo empty")
			else:
				expect(t!="","remark for %s|%s"%[c,s])
				expect(not seen.has(t),"distinct remark %s|%s"%[c,s])
				seen[t]=true
	expect(Decor.remark({"cloth":"x","sign":"plain"})=="","invalid remark empty")
	var copy:=Decor.style(person)
	copy.cloth="natural"
	expect(person.market_decor.cloth=="leaf","style returns copy")
	var state:={"picnic":true,"time":0.0,"players":{
		"alice":{"name":"小葉","market_decor":{"cloth":"leaf","sign":"flower"},"market":{"open_day":0,"pending":true,"stock":{"wheat":5},"till":123}},
		"bob":{"name":"阿藍","market_decor":{"cloth":"indigo","sign":"windbell"},"market":{"open_day":0,"pending":true,"stock":{"carp":4}}},
	}}
	var first:=Decor.plaza_display(state,{})
	expect(first=={"vendor":"alice".sha256_text().left(16),"name":"小葉","style":{"cloth":"leaf","sign":"flower"},"goods":["wheat"]},"Display publishes only the current vendor's visual sign data")
	state.time=Decor.PLAZA_TURN
	expect(Decor.plaza_display(state,{}).name=="阿藍","Second vendor takes the next world-hour display")
	expect(Decor.plaza_display(state,{"bob":true}).name=="小葉","A vendor already using a personal cart is absent from the shared stall")
	state.time=1440.0
	expect(Decor.plaza_display(state,{}).is_empty(),"Yesterday's booths are absent after the day changes")
	print("MARKET_DECOR_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
