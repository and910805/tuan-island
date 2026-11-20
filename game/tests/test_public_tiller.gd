extends SceneTree
## T064 公用耕田機（public tiller loan）規則測試。
## 全部透過 world.act() 走正式的伺服器動作；以下是直接寫入 state 的測試夾具（fixtures）：
##  - state.picnic=true（開放階段）；玩家的 x / y / region（站位）；
##  - 背包的 charcoal、wood、tiller 數量（「擁有自製耕田機」與燃料的前置條件）；
##  - 第 9 節用 state.crops/objects/roofs/forest 直接占住農機架候選格（模擬舊存檔的私人物件）；
##  - 冷卻以 world.step(1,true) 推進 state.time；
##  - 第 10 節把存檔 JSON 讀出、改欄位後另存成暫存檔再 load_world（結束時刪除）。
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const PT=preload("res://scripts/public_tiller.gd")
const Tiller=preload("res://scripts/tiller.gd")
const CENTER:=Vector2i(42,36)
const NEED_SEEDER:="先在工作台製作手推播種機"
const NEED_HARVESTER:="先在工作台製作手推收割機"
const TOO_FAR:="靠近一點，才能和它互動"
var checks:=0
var failures:=0
var seq:=0
var temp_paths:Array[String]=[]

func expect(value:bool,note:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+note)
		print("FAIL "+note)

func make(tokens:Array,picnic:bool) -> World:
	var w:=World.new()
	for token:String in tokens:w.add_player(token,token)
	w.state.picnic=picnic
	return w

func who(w:World,token:String) -> Dictionary:
	return w.state.players[token]

## 站在目標格正下方一格（距離 1），或指定的偏移。
func stand(w:World,token:String,cell:Vector2i,offset:Vector2=Vector2(0.5,1.5)) -> void:
	var person:Dictionary=who(w,token)
	person.x=cell.x+offset.x
	person.y=cell.y+offset.y

func go(w:World,token:String,action:String,cell:Vector2i,extra:String="") -> Dictionary:
	seq+=1
	return w.act(token,"pt-%d"%seq,action,cell,extra)

func till(w:World,token:String,center:Vector2i=CENTER) -> Dictionary:
	stand(w,token,center,Vector2(0.5,0.5))
	return go(w,token,"till_area",center)

func valid(s:Dictionary) -> bool:
	return Schema.validate(s,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func owned_by(w:World,keys:Array,token:String) -> bool:
	for k in keys:
		if not w.state.crops.has(k) or w.state.crops[k].get("owner","")!=token:return false
	return true

func _initialize() -> void:
	section_locked()
	section_rack()
	section_borrow()
	section_owner()
	section_use()
	section_not_loaned()
	section_no_value()
	section_two_players()
	section_occupied()
	section_save()
	cleanup()
	print("PUBLIC_TILLER_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# 1. 野餐前：不開放、不改任何狀態、候選格不保留。
func section_locked() -> void:
	var w:=make(["ann"],false)
	who(w,"ann").inventory.charcoal=3
	stand(w,"ann",PT.SITES[0])
	var before:Dictionary=w.state.duplicate(true)
	var r:Dictionary=go(w,"ann",PT.ACTION,PT.SITES[0])
	expect(not r.ok and r.message==PT.LOCKED,"1 before picnic borrow refused with LOCKED (got: %s)"%str(r.get("message","")))
	expect(w.state==before,"1 refused early borrow leaves the whole state unchanged")
	expect(who(w,"ann")==before.players.ann and who(w,"ann").inventory==before.players.ann.inventory,"1 player dict and inventory unchanged")
	expect(not who(w,"ann").has(PT.FIELD),"1 no flag before picnic")
	expect(PT.site(w.state)==PT.NO_SITE and PT.loan_cell(w.state)==PT.NO_SITE,"1 site and loan cell are NO_SITE before picnic")
	for cell:Vector2i in PT.SITES:
		expect(not PT.reserved(w.state,cell),"1 %s not reserved before picnic"%str(cell))
		expect(not w.protected(cell),"1 %s not protected before picnic"%str(cell))
		expect(not w.blocked(cell),"1 %s not blocked before picnic (resource there: '%s')"%[str(cell),w.resource(cell)])
		expect(World.essential_cell_reason(w.state,"home",cell).is_empty(),"1 %s not essential before picnic"%str(cell))
	r=till(w,"ann")
	expect(not r.ok and r.message==PT.NEED_MACHINE and w.state.crops.is_empty() and who(w,"ann").inventory.charcoal==3,"1 no machine, no loan: NEED_MACHINE and nothing spent")
	# 對照組：野餐前候選格是普通空地，可以正常蓋東西。
	var control:=make(["ann"],false)
	who(control,"ann").inventory.merge({"wood":100,"stone":50},true)
	stand(control,"ann",PT.SITES[0])
	var built:Dictionary=go(control,"ann","build",PT.SITES[0],"wall")
	expect(built.ok,"1 control: wall can be built on SITES[0] before picnic (got: %s)"%str(built.get("message","")))

# 2. 野餐後：農機架在 SITES[0]，保留、擋路、不可施工。
func section_rack() -> void:
	var w:=make(["ann"],true)
	var rack:Vector2i=PT.SITES[0]
	var rack_key:String=World.key(rack)
	expect(PT.site(w.state)==rack and PT.loan_cell(w.state)==rack,"2 rack is SITES[0] on a fresh world")
	expect(PT.reserved(w.state,rack) and w.protected(rack),"2 rack cell protected")
	expect(w.blocked(rack),"2 rack cell blocked")
	expect(not World.essential_cell_reason(w.state,"home",rack).is_empty(),"2 rack cell has an essential reason")
	for i in range(1,PT.SITES.size()):
		expect(not PT.reserved(w.state,PT.SITES[i]),"2 SITES[%d] not reserved"%i)
		expect(not w.protected(PT.SITES[i]) and not w.blocked(PT.SITES[i]),"2 SITES[%d] stays ordinary ground"%i)
	who(w,"ann").inventory.merge({"wood":100,"stone":50,"tiller":1,"charcoal":5},true)
	stand(w,"ann",rack)
	var before:Dictionary=w.state.duplicate(true)
	var r:Dictionary=go(w,"ann","hoe",rack)
	expect(not r.ok and not str(r.message).is_empty() and w.state==before,"2 hoe on rack refused without mutation")
	r=go(w,"ann","build",rack,"wall")
	expect(not r.ok and not str(r.message).is_empty() and w.state==before,"2 build on rack refused without mutation")
	var plan:Dictionary=Tiller.plan(w,"ann",rack)
	expect(plan.skipped.get(rack_key,"")=="公共通道" and rack_key not in plan.cells,"2 tiller preview skips the rack as public (got: %s)"%str(plan.skipped.get(rack_key,"")))
	r=go(w,"ann","till_area",rack)
	expect(not w.state.crops.has(rack_key),"2 tiller pass around the rack never tills the rack cell")
	expect(not w.state.objects.has(rack_key) and not w.state.ground.has(rack_key),"2 rack cell stays empty")
	expect(PT.site(w.state)==rack,"2 rack stays on SITES[0] after neighbours are tilled")
	# 農機架旁的非保留候選格仍可使用（拒絕來自保留，而不是整區封鎖）。
	var free:=make(["ann"],true)
	stand(free,"ann",PT.SITES[1])
	r=go(free,"ann","hoe",PT.SITES[1])
	expect(r.ok and PT.site(free.state)==rack,"2 unreserved candidate SITES[1] can still be hoed and the rack does not move (got: %s)"%str(r.get("message","")))

# 3. 登記：距離、格子、區域、只寫旗標、不可重複。
func section_borrow() -> void:
	var w:=make(["ann"],true)
	var rack:Vector2i=PT.SITES[0]
	stand(w,"ann",CENTER,Vector2(0.5,0.5))
	var before:Dictionary=w.state.duplicate(true)
	var r:Dictionary=go(w,"ann",PT.ACTION,rack)
	expect(not r.ok and w.state==before,"3 too far refused without mutation")
	expect(r.message==TOO_FAR,"3 too far uses the generic reach message (got: %s)"%str(r.message))
	stand(w,"ann",rack)
	before=w.state.duplicate(true)
	r=go(w,"ann",PT.ACTION,PT.SITES[1])
	expect(not r.ok and r.message==PT.WRONG_PLACE and w.state==before,"3 neighbouring candidate cell refused with WRONG_PLACE (got: %s)"%str(r.message))
	stand(w,"ann",PT.DESK)
	before=w.state.duplicate(true)
	r=go(w,"ann",PT.ACTION,PT.DESK)
	expect(not r.ok and r.message==PT.WRONG_PLACE and w.state==before,"3 notice board refused while the rack exists (got: %s)"%str(r.message))
	# 其他區域：同座標站在金瓜石。
	stand(w,"ann",rack)
	who(w,"ann").region="jinguashi"
	before=w.state.duplicate(true)
	r=go(w,"ann",PT.ACTION,rack)
	expect(not r.ok and w.state==before and not who(w,"ann").has(PT.FIELD),"3 other region refused without mutation (message: %s)"%str(r.message))
	expect(PT.problem(w.state,who(w,"ann"),"jinguashi",rack)==PT.WRONG_PLACE,"3 problem() names the place for another region")
	who(w,"ann").region="home"
	before=w.state.duplicate(true)
	var loan:Dictionary=w.act("ann","loan-ann",PT.ACTION,rack)
	var ann:Dictionary=who(w,"ann")
	expect(loan.ok and loan.message==PT.OPENED and ann.get(PT.FIELD)==true,"3 borrow succeeds and sets the flag (got: %s)"%str(loan.get("message","")))
	expect(ann.inventory==before.players.ann.inventory,"3 inventory identical after borrowing")
	expect(not ann.inventory.has(PT.ITEM),"3 no tiller item in the inventory")
	expect(int(ann.coins)==int(before.players.ann.coins),"3 coins unchanged")
	var changed:Array=[]
	for field in ann:
		if field!="receipts" and (not before.players.ann.has(field) or before.players.ann[field]!=ann[field]):changed.append(field)
	for field in before.players.ann:
		if not ann.has(field):changed.append("-"+str(field))
	expect(changed==[PT.FIELD],"3 the flag is the only player field written (changed: %s)"%str(changed))
	var rest:Dictionary=w.state.duplicate(true)
	rest.players.ann=before.players.ann
	rest.committed=before.committed
	expect(rest==before,"3 nothing else in the world changes on borrow")
	expect(PT.site(w.state)==rack and w.protected(rack),"3 rack stays in place for the next islander")
	var committed:int=int(w.state.committed)
	expect(w.act("ann","loan-ann",PT.ACTION,rack)==loan and int(w.state.committed)==committed,"3 same request id returns the stored receipt")
	before=w.state.duplicate(true)
	r=go(w,"ann",PT.ACTION,rack)
	expect(not r.ok and r.message==PT.ALREADY and w.state==before,"3 repeat borrow refused with ALREADY (got: %s)"%str(r.message))

# 4. 已有自製耕田機不能借；借用者之後取得耕田機照常使用。
func section_owner() -> void:
	var w:=make(["maker","ann"],true)
	var rack:Vector2i=PT.SITES[0]
	who(w,"maker").inventory.merge({"tiller":1,"charcoal":2},true)
	stand(w,"maker",rack)
	var before:Dictionary=w.state.duplicate(true)
	var r:Dictionary=go(w,"maker",PT.ACTION,rack)
	expect(not r.ok and r.message==PT.OWNED and w.state==before and not who(w,"maker").has(PT.FIELD),"4 tiller owner refused with OWNED (got: %s)"%str(r.message))
	expect(till(w,"maker").ok and who(w,"maker").inventory.charcoal==1,"4 owner still tills with the crafted machine")
	stand(w,"ann",rack)
	expect(go(w,"ann",PT.ACTION,rack).ok,"4 setup: borrower registers")
	who(w,"ann").inventory.merge({"tiller":1,"charcoal":2},true)
	r=till(w,"ann",Vector2i(45,36))
	expect(r.ok and who(w,"ann").inventory.charcoal==1 and who(w,"ann").get(PT.FIELD)==true and who(w,"ann").inventory.tiller==1,
		"4 borrower who later holds a tiller keeps working, flag and item intact (got: %s)"%str(r.message))
	stand(w,"ann",rack)
	r=go(w,"ann",PT.ACTION,rack)
	expect(not r.ok,"4 borrower who now owns a tiller cannot register again")

# 5. 使用：自己的木炭、冷卻、歸屬。
func section_use() -> void:
	var w:=make(["ann","zed"],true)
	var rack:Vector2i=PT.SITES[0]
	stand(w,"ann",rack)
	expect(go(w,"ann",PT.ACTION,rack).ok,"5 setup: borrow")
	var before:Dictionary=w.state.duplicate(true)
	stand(w,"ann",CENTER,Vector2(0.5,0.5))
	before=w.state.duplicate(true)
	var r:Dictionary=go(w,"ann","till_area",CENTER)
	expect(not r.ok and str(r.message).contains("木炭") and w.state==before,"5 no charcoal: refused without mutation (got: %s)"%str(r.message))
	expect(w.state.crops.is_empty() and who(w,"ann").get(PT.FIELD)==true,"5 no charcoal: nothing tilled, flag kept")
	who(w,"ann").inventory.charcoal=2
	var plan:Dictionary=Tiller.plan(w,"ann",CENTER)
	expect(plan.cells.size()==9,"5 setup: nine clear cells at CENTER (got %d, skipped %s)"%[plan.cells.size(),str(plan.skipped)])
	var bag:Dictionary=who(w,"ann").inventory.duplicate(true)
	r=go(w,"ann","till_area",CENTER)
	expect(r.ok and w.state.crops.size()==plan.cells.size(),"5 borrower tills the planned cells (got: %s)"%str(r.message))
	expect(who(w,"ann").inventory.charcoal==1,"5 exactly one charcoal spent")
	bag.charcoal=1
	expect(who(w,"ann").inventory==bag and not who(w,"ann").inventory.has(PT.ITEM),"5 nothing else in the inventory changes")
	expect(owned_by(w,plan.cells,"ann"),"5 new plots belong to the borrower")
	for crop:Dictionary in w.state.crops.values():
		expect(crop.kind=="" and not crop.wet and crop.owner=="ann","5 loan plots match ordinary hoe data")
	before=w.state.duplicate(true)
	var other:=Vector2i(45,36)
	stand(w,"ann",other,Vector2(0.5,0.5))
	var moved:Dictionary=w.state.duplicate(true)
	r=go(w,"ann","till_area",other)
	expect(not r.ok and str(r.message).contains("稍候") and w.state==moved and who(w,"ann").inventory.charcoal==1,"5 second pass inside COOLDOWN refused, no charcoal spent (got: %s)"%str(r.message))
	w.step(1,true)
	expect(float(w.state.time)-float(who(w,"ann").last_till.at)>=Tiller.COOLDOWN,"5 setup: cooldown elapsed")
	stand(w,"ann",CENTER,Vector2(0.5,0.5))
	before=w.state.duplicate(true)
	r=go(w,"ann","till_area",CENTER)
	expect(not r.ok and str(r.message).contains("未消耗木炭") and w.state==before and who(w,"ann").inventory.charcoal==1,"5 pass with no tillable cells spends no charcoal (got: %s)"%str(r.message))
	stand(w,"ann",other,Vector2(0.5,0.5))
	plan=Tiller.plan(w,"ann",other)
	expect(not plan.cells.is_empty(),"5 setup: second field has clear cells")
	var count:int=w.state.crops.size()
	r=go(w,"ann","till_area",other)
	expect(r.ok and who(w,"ann").inventory.charcoal==0 and w.state.crops.size()==count+plan.cells.size() and owned_by(w,plan.cells,"ann"),"5 after the cooldown the loan works again (got: %s)"%str(r.message))
	w.step(1,true)
	before=w.state.duplicate(true)
	r=go(w,"ann","till_area",Vector2i(45,39))
	expect(not r.ok and w.state==before,"5 out of charcoal again: refused")
	# 沒有機器也沒有借用資格。
	who(w,"zed").inventory.charcoal=4
	stand(w,"zed",Vector2i(38,36),Vector2(0.5,0.5))
	before=w.state.duplicate(true)
	r=go(w,"zed","till_area",Vector2i(38,36))
	expect(not r.ok and r.message==PT.NEED_MACHINE and w.state==before,"5 neither tiller nor loan: NEED_MACHINE without mutation (got: %s)"%str(r.message))
	expect(not PT.can_till(who(w,"zed")) and PT.can_till(who(w,"ann")),"5 can_till matches eligibility")

# 6. 播種機、收割機不外借。
func section_not_loaned() -> void:
	var w:=make(["ann"],true)
	var rack:Vector2i=PT.SITES[0]
	stand(w,"ann",rack)
	expect(go(w,"ann",PT.ACTION,rack).ok,"6 setup: borrow")
	who(w,"ann").inventory.charcoal=5
	expect(till(w,"ann").ok,"6 setup: borrower tills own plots")
	w.step(1,true)
	var before:Dictionary=w.state.duplicate(true)
	var r:Dictionary=go(w,"ann","seed_area",CENTER,"radish")
	expect(not r.ok and r.message==NEED_SEEDER and w.state==before,"6 seed_area still needs the borrower's own seeder (got: %s)"%str(r.message))
	for k in w.state.crops:w.state.crops[k].merge({"kind":"radish","growth":World.CROPS.radish.time,"wet":true,"remaining":1},true)
	before=w.state.duplicate(true)
	r=go(w,"ann","harvest_area",CENTER)
	expect(not r.ok and r.message==NEED_HARVESTER and w.state==before,"6 harvest_area still needs the borrower's own harvester (got: %s)"%str(r.message))
	expect(who(w,"ann").inventory.charcoal==4 and not who(w,"ann").inventory.has("seeder") and not who(w,"ann").inventory.has("harvester"),"6 no fuel spent, no machines granted")

# 7. 借用資格不能變成可賣、可存、可交易的東西。
func section_no_value() -> void:
	var w:=make(["ann","bob"],true)
	var rack:Vector2i=PT.SITES[0]
	stand(w,"ann",rack)
	expect(go(w,"ann",PT.ACTION,rack).ok,"7 setup: borrow")
	expect(not who(w,"ann").inventory.has(PT.ITEM),"7 borrower holds no tiller item")
	expect(not World.trade_items().has(PT.ITEM),"7 trade_items() excludes the tiller")
	# 出貨箱
	var box:Vector2i=World.SHIPPING.cell_for(w.state)
	stand(w,"ann",box)
	var coins:int=int(who(w,"ann").coins)
	var bag:Dictionary=who(w,"ann").inventory.duplicate(true)
	var r:Dictionary=go(w,"ann","ship",box,JSON.stringify([[[PT.ITEM,1]],1]))
	expect(not r.ok and int(who(w,"ann").coins)==coins and who(w,"ann").inventory==bag,"7 shipping a tiller the borrower does not hold is refused (got: %s)"%str(r.get("message","")))
	r=go(w,"ann","ship",box,JSON.stringify([[["wood",1]],World.SHIPPING.MATERIAL_PRICES.wood]))
	expect(r.ok and int(who(w,"ann").coins)==coins+World.SHIPPING.MATERIAL_PRICES.wood,"7 control: the same shipping box accepts real goods (got: %s)"%str(r.get("message","")))
	# 小栗的攤位
	var stall:=Vector2i(43,29)
	stand(w,"ann",stall)
	coins=int(who(w,"ann").coins)
	bag=who(w,"ann").inventory.duplicate(true)
	r=go(w,"ann","sell",stall,PT.ITEM)
	expect(not r.ok and int(who(w,"ann").coins)==coins and who(w,"ann").inventory==bag,"7 selling a tiller at the stall is refused (got: %s)"%str(r.get("message","")))
	# 市集攤位
	var market:Vector2i=World.MARKET.cell_for(w.state)
	stand(w,"ann",market)
	for extra:String in [PT.ITEM,PT.ITEM+":1",JSON.stringify({"item":PT.ITEM,"count":1,"price":5})]:
		var listed:Dictionary=go(w,"ann","market_stock",market,extra)
		expect(not listed.ok and who(w,"ann").inventory==bag and int(who(w,"ann").coins)==coins,"7 market stall refuses stocking a tiller ('%s' -> %s)"%[extra,str(listed.get("message",""))])
	# 箱子
	who(w,"ann").inventory.wood=100
	var chest:=Vector2i(38,33)
	stand(w,"ann",chest)
	r=go(w,"ann","build",chest,"chest")
	expect(r.ok,"7 setup: build a chest (got: %s)"%str(r.get("message","")))
	expect(go(w,"ann","deposit",chest,"wood").ok,"7 control: chest accepts a real item")
	bag=who(w,"ann").inventory.duplicate(true)
	for move:String in ["deposit","deposit_all"]:
		r=go(w,"ann",move,chest,PT.ITEM)
		expect(not r.ok and who(w,"ann").inventory==bag,"7 %s of a tiller the borrower does not hold is refused (got: %s)"%[move,str(r.get("message",""))])
	expect(not w.state.objects[World.key(chest)].items.has(PT.ITEM),"7 no tiller appears in the chest")
	# 玩家交易
	who(w,"bob").x=who(w,"ann").x
	who(w,"bob").y=who(w,"ann").y
	var opened:Dictionary=w.act("ann","pt-trade",  "trade_open",Vector2i.ZERO,"bob")
	expect(opened.ok,"7 setup: open a trade (got: %s)"%str(opened.get("message","")))
	bag=who(w,"ann").inventory.duplicate(true)
	var bob_bag:Dictionary=who(w,"bob").inventory.duplicate(true)
	r=go(w,"ann","trade_edit",Vector2i.ZERO,JSON.stringify({"offer":"pt-trade","items":[[PT.ITEM,1]],"coins":0}))
	expect(not r.ok and who(w,"ann").inventory==bag and who(w,"bob").inventory==bob_bag,"7 a tiller cannot be put into a trade offer (got: %s)"%str(r.get("message","")))
	r=go(w,"ann","trade_edit",Vector2i.ZERO,JSON.stringify({"offer":"pt-trade","items":[["wood",1]],"coins":0}))
	expect(r.ok,"7 control: the same offer accepts a real item (got: %s)"%str(r.get("message","")))
	expect(not who(w,"bob").has(PT.FIELD) and not who(w,"bob").inventory.has(PT.ITEM) and who(w,"ann").get(PT.FIELD)==true,"7 the flag stays with the borrower only")

# 8. 兩位玩家各自登記、農田各自歸屬。
func section_two_players() -> void:
	var w:=make(["ann","bob"],true)
	var rack:Vector2i=PT.SITES[0]
	for token:String in ["ann","bob"]:who(w,token).inventory.charcoal=5
	stand(w,"ann",rack)
	stand(w,"bob",rack)
	expect(go(w,"ann",PT.ACTION,rack).ok,"8 A borrows")
	expect(not PT.borrowed(who(w,"bob")) and not who(w,"bob").has(PT.FIELD),"8 B's flag stays unset")
	var before:Dictionary=w.state.duplicate(true)
	stand(w,"bob",CENTER,Vector2(0.5,0.5))
	before=w.state.duplicate(true)
	var r:Dictionary=go(w,"bob","till_area",CENTER)
	expect(not r.ok and r.message==PT.NEED_MACHINE and w.state==before,"8 B cannot till on A's loan (got: %s)"%str(r.message))
	var a_plan:Dictionary=Tiller.plan(w,"ann",CENTER)
	stand(w,"ann",CENTER,Vector2(0.5,0.5))
	a_plan=Tiller.plan(w,"ann",CENTER)
	expect(go(w,"ann","till_area",CENTER).ok and owned_by(w,a_plan.cells,"ann") and who(w,"ann").inventory.charcoal==4,"8 A tills own plots")
	expect(who(w,"bob").inventory.charcoal==5,"8 A's pass never touches B's charcoal")
	stand(w,"bob",rack)
	r=go(w,"bob",PT.ACTION,rack)
	expect(r.ok and who(w,"bob").get(PT.FIELD)==true and PT.site(w.state)==rack,"8 B borrows independently at the same rack (got: %s)"%str(r.message))
	var shifted:=CENTER+Vector2i(1,0)
	stand(w,"bob",shifted,Vector2(0.5,0.5))
	var b_plan:Dictionary=Tiller.plan(w,"bob",shifted)
	var overlap:=false
	for k in b_plan.cells:
		if k in a_plan.cells:overlap=true
	expect(not b_plan.cells.is_empty() and not overlap,"8 B's preview only offers cells that are not A's plots (cells: %s)"%str(b_plan.cells))
	r=go(w,"bob","till_area",shifted)
	expect(r.ok and owned_by(w,b_plan.cells,"bob") and owned_by(w,a_plan.cells,"ann"),"8 overlapping pass: B owns only the new cells, A's plots keep their owner (got: %s)"%str(r.message))
	expect(w.state.crops.size()==a_plan.cells.size()+b_plan.cells.size(),"8 no plot is created twice")
	expect(who(w,"bob").inventory.charcoal==4 and who(w,"ann").inventory.charcoal==4,"8 each borrower pays own charcoal")
	w.step(1,true)
	stand(w,"ann",shifted,Vector2(0.5,0.5))
	before=w.state.duplicate(true)
	r=go(w,"ann","till_area",shifted)
	expect(not r.ok and w.state==before and owned_by(w,b_plan.cells,"bob") and who(w,"ann").inventory.charcoal==4,"8 A cannot till over B's plots and spends nothing (got: %s)"%str(r.message))

# 9. 候選格被占用：農機架依序後移；全滿改在公告板登記。
func section_occupied() -> void:
	expect(PT.site({"picnic":true,"ground":{World.key(PT.SITES[0]):{}}})==PT.SITES[1],"9 ground on SITES[0] moves the rack")
	expect(PT.site({"picnic":true,"roofs":{World.key(PT.SITES[0]):{}},"forest":{World.key(PT.SITES[1]):{}}})==PT.SITES[2],"9 roofs and planted trees also count as occupied")
	var w:=make(["ann"],false)
	stand(w,"ann",PT.SITES[0])
	expect(go(w,"ann","hoe",PT.SITES[0]).ok,"9 setup: a private plot on SITES[0] before picnic")
	w.state.picnic=true
	expect(PT.site(w.state)==PT.SITES[1] and PT.loan_cell(w.state)==PT.SITES[1],"9 rack moves to SITES[1]")
	expect(w.protected(PT.SITES[1]) and w.blocked(PT.SITES[1]) and not PT.reserved(w.state,PT.SITES[0]) and not w.blocked(PT.SITES[0]),"9 only the active rack cell is reserved")
	expect(not World.essential_cell_reason(w.state,"home",PT.SITES[1]).is_empty() and World.essential_cell_reason(w.state,"home",PT.SITES[0]).is_empty(),"9 essential cell follows the rack")
	var before:Dictionary=w.state.duplicate(true)
	var r:Dictionary=go(w,"ann",PT.ACTION,PT.SITES[0])
	expect(not r.ok and r.message==PT.WRONG_PLACE and w.state==before,"9 occupied SITES[0] no longer lends (got: %s)"%str(r.message))
	r=go(w,"ann",PT.ACTION,PT.SITES[1])
	expect(r.ok and who(w,"ann").get(PT.FIELD)==true,"9 borrowing works at the moved rack (got: %s)"%str(r.message))
	expect(w.state.crops[World.key(PT.SITES[0])].owner=="ann","9 the private plot is untouched")
	# 四格全滿
	var full:=make(["ann","bob"],false)
	full.state.crops[World.key(PT.SITES[0])]={"kind":"","growth":0.0,"wet":false,"owner":"bob"}
	full.state.objects[World.key(PT.SITES[1])]={"type":"chair","owner":"bob","items":{}}
	full.state.roofs[World.key(PT.SITES[2])]={"type":"roof","owner":"bob","items":{}}
	full.state.forest[World.key(PT.SITES[3])]={"owner":"bob","mature":false,"growth":10}
	full.state.picnic=true
	expect(PT.site(full.state)==PT.NO_SITE and PT.loan_cell(full.state)==PT.DESK,"9 all four occupied: no rack, loan moves to the notice board")
	for cell:Vector2i in PT.SITES:
		expect(not PT.reserved(full.state,cell) and not full.protected(cell),"9 %s not reserved when no rack exists"%str(cell))
	stand(full,"ann",PT.SITES[0])
	before=full.state.duplicate(true)
	r=go(full,"ann",PT.ACTION,PT.SITES[0])
	expect(not r.ok and r.message==PT.WRONG_PLACE_DESK and full.state==before,"9 rack cell refused with WRONG_PLACE_DESK (got: %s)"%str(r.message))
	before=full.state.duplicate(true)
	r=go(full,"ann",PT.ACTION,PT.DESK)
	expect(not r.ok and full.state==before,"9 notice board out of reach refused (got: %s)"%str(r.message))
	stand(full,"ann",PT.DESK,Vector2(0.5,2.5))
	var bag:Dictionary=who(full,"ann").inventory.duplicate(true)
	r=go(full,"ann",PT.ACTION,PT.DESK)
	expect(r.ok and r.message==PT.OPENED and who(full,"ann").get(PT.FIELD)==true and who(full,"ann").inventory==bag,"9 borrowing works at the notice board (got: %s)"%str(r.message))
	who(full,"ann").inventory.charcoal=1
	expect(till(full,"ann").ok and who(full,"ann").inventory.charcoal==0,"9 the notice-board loan tills like the rack loan")
	expect(full.state.crops[World.key(PT.SITES[0])].owner=="bob" and full.state.objects.has(World.key(PT.SITES[1])),"9 the occupying private objects are untouched")

func write_variant(text:String,mode:String) -> World:
	var data:Dictionary=JSON.parse_string(text)
	var person:Dictionary=data.players.saver
	match mode:
		"legacy":person.erase(PT.FIELD)
		"string":person[PT.FIELD]="true"
		"number":person[PT.FIELD]=1
		"null":person[PT.FIELD]=null
		"no_picnic_true":data.picnic=false
		"no_picnic_false":
			data.picnic=false
			person[PT.FIELD]=false
		"no_picnic_missing":
			data.picnic=false
			person.erase(PT.FIELD)
	var path:="user://public-tiller-%s-%d.json"%[mode,Time.get_ticks_usec()]
	temp_paths.append(path)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var w:=World.new()
	w.set_meta("loaded",w.load_world(path))
	return w

# 10. 存檔與舊存檔。
func section_save() -> void:
	var w:=make(["saver"],true)
	var rack:Vector2i=PT.SITES[0]
	who(w,"saver").inventory.charcoal=3
	stand(w,"saver",rack)
	var path:="user://public-tiller-main-%d.json"%Time.get_ticks_usec()
	temp_paths.append(path)
	w.save_path=path
	var r:Dictionary=go(w,"saver",PT.ACTION,rack)
	expect(r.ok and FileAccess.file_exists(path),"10 borrow commits and saves (got: %s)"%str(r.get("message","")))
	var text:String=FileAccess.get_file_as_string(path)
	var stored:Dictionary=JSON.parse_string(text)
	expect(stored.players.saver.get(PT.FIELD)==true and not stored.players.saver.inventory.has(PT.ITEM),"10 the save stores the flag as a bool and no tiller item")
	var loaded:=World.new()
	var load_ok:bool=loaded.load_world(path)
	expect(load_ok and loaded.state.players.get("saver",{}).get(PT.FIELD)==true,"10 loan survives save and reload")
	if load_ok:
		expect(not who(loaded,"saver").inventory.has(PT.ITEM),"10 reload does not turn the loan into an item")
		expect(PT.site(loaded.state)==rack and loaded.protected(rack),"10 rack is still reserved after reload")
		r=till(loaded,"saver")
		expect(r.ok and who(loaded,"saver").inventory.charcoal==2 and loaded.state.crops.size()==9,"10 reloaded borrower can still till (got: %s)"%str(r.message))
		var again:=World.new()
		expect(again.load_world(path) and again.state.crops.size()==9 and again.state.players.saver.get(PT.FIELD)==true,"10 plots tilled on the loan persist")
		r=go(loaded,"saver",PT.ACTION,rack)
		expect(not r.ok,"10 reloaded borrower cannot register twice")
	var same:World=write_variant(text,"same")
	expect(same.get_meta("loaded"),"10 control: an unmodified copy of the save loads")
	var legacy:World=write_variant(text,"legacy")
	expect(legacy.get_meta("loaded"),"10 legacy save without the field loads")
	if legacy.get_meta("loaded"):
		expect(not PT.borrowed(who(legacy,"saver")) and not PT.can_till(who(legacy,"saver")),"10 legacy player reads as not borrowed")
		r=till(legacy,"saver")
		expect(not r.ok and r.message==PT.NEED_MACHINE,"10 legacy player has no tiller access (got: %s)"%str(r.message))
		stand(legacy,"saver",rack)
		r=go(legacy,"saver",PT.ACTION,rack)
		expect(r.ok and who(legacy,"saver").get(PT.FIELD)==true,"10 legacy player can register after loading (got: %s)"%str(r.message))
	for mode:String in ["string","number","null"]:
		expect(not write_variant(text,mode).get_meta("loaded"),"10 non-bool flag rejected on load: "+mode)
	expect(not write_variant(text,"no_picnic_true").get_meta("loaded"),"10 flag=true before picnic rejected on load")
	var early:World=write_variant(text,"no_picnic_false")
	expect(early.get_meta("loaded"),"10 flag=false without picnic accepted")
	if early.get_meta("loaded"):
		expect(not PT.borrowed(who(early,"saver")) and PT.site(early.state)==PT.NO_SITE,"10 flag=false without picnic reads as not borrowed, no rack")
	expect(write_variant(text,"no_picnic_missing").get_meta("loaded"),"10 control: the same save without picnic and without the field loads")
	# 同樣的規則直接問 schema（不經檔案）。
	# 這裡用沒有夾具木炭的世界：直接塞進背包、未經正式取得的木炭會讓「未經 JSON 的」
	# 記憶體狀態被 schema 的圖鑑檢查拒絕（與 T064 無關），所以不拿上面的 w 來驗。
	var plain:=make(["saver"],true)
	stand(plain,"saver",rack)
	expect(go(plain,"saver",PT.ACTION,rack).ok,"10 setup: borrow in a world without fixture items")
	var base:Dictionary=plain.state.duplicate(true)
	expect(valid(base.duplicate(true)),"10 schema accepts the live borrowed state")
	for bad in ["true",1,1.0,null,[],{}]:
		var broken:Dictionary=base.duplicate(true)
		broken.players.saver[PT.FIELD]=bad
		expect(not valid(broken),"10 schema rejects non-bool flag: "+var_to_str(bad))
	var broken_stage:Dictionary=base.duplicate(true)
	broken_stage.picnic=false
	expect(not valid(broken_stage),"10 schema rejects flag=true with picnic=false")
	broken_stage=base.duplicate(true)
	broken_stage.picnic=false
	broken_stage.players.saver[PT.FIELD]=false
	expect(valid(broken_stage),"10 schema accepts flag=false with picnic=false")
	broken_stage=base.duplicate(true)
	broken_stage.players.saver.erase(PT.FIELD)
	expect(valid(broken_stage),"10 schema accepts a player without the field")
	expect(PT.valid({},{}) and PT.valid({PT.FIELD:false},{}) and not PT.valid({PT.FIELD:true},{}) and PT.valid({PT.FIELD:true},{"picnic":true}),"10 valid() truth table")

func cleanup() -> void:
	for name:String in DirAccess.get_files_at("user://"):
		if name.begins_with("public-tiller-"):DirAccess.remove_absolute("user://"+name)
	for path:String in temp_paths:
		for suffix:String in ["",".bak",".tmp",".bak.staged"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	var left:=0
	for name:String in DirAccess.get_files_at("user://"):
		if name.begins_with("public-tiller-"):left+=1
	expect(left==0,"cleanup removed every temporary save")
