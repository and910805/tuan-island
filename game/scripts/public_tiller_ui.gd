extends RefCounted
## T064 公用耕田機：地圖農機架的畫法、互動點與登記頁。規則都在 public_tiller.gd。
const Loan=preload("res://scripts/public_tiller.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const FurnitureArt=preload("res://scripts/furniture_sprite_art.gd")
const POINT:=Loan.POINT

static func person(snapshot:Dictionary,id:String) -> Dictionary:
	return snapshot.get("players",{}).get(id,{})

## 互動點：農機架在渡口出現時才有（main.gd 與 world_view.gd 共用，順序要一致）。
static func points(snapshot:Dictionary) -> Dictionary:
	var rack:=Loan.site(snapshot)
	return {} if rack==Loan.NO_SITE else {POINT:Vector2(rack)+Vector2(0.5,0.5)}

## 農機架圖的實際範圍（腳底對齊格子底邊、水平置中）；畫圖與標籤避讓共用。
static func rack_rect(at:Vector2) -> Rect2:
	var art:=Loan.texture()
	var size:=art.get_size() if art!=null else Vector2(32,32)
	return Rect2(at+Vector2((32.0-size.x)*0.5,32.0-size.y),size)

## 畫在農機架那一格。圖檔還沒到位時，用既有的告示牌加耕田機道具圖，不中斷畫面。
static func draw_rack(canvas:CanvasItem,at:Vector2) -> void:
	var art:=Loan.texture()
	if art!=null:
		# 腳底對齊格子底邊、水平置中；允許比一格高的圖。
		canvas.draw_texture(art,rack_rect(at).position)
		return
	FurnitureArt.draw_sprite(canvas,at,"sign")
	var icon:=ItemArt.icon(Loan.ITEM)
	if icon!=null:canvas.draw_texture_rect(icon,Rect2(at+Vector2(6,10),Vector2(20,20)),false)

static func near(app,cell:Vector2i) -> bool:
	var own:=Tasks.player(app)
	if own.is_empty() or app.session.snapshot.get("region_id","home")!="home":return false
	return Vector2(own.get("x",0),own.get("y",0)).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=Loan.REACH

## 說明與登記按鈕，登記頁與生活技能的「後來到島上的居民」卡片共用。
static func add_loan(app,parent:Container,close_after:=true) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var own:=Tasks.player(app)
	if not Loan.open(snapshot):
		Tasks.line(app,parent,Loan.LOCKED,15)
		return
	if Loan.owns(own):
		Tasks.line(app,parent,"你已有自己的手推耕田機。公用耕田機留給還沒有機器的島民。",15)
		return
	if Loan.borrowed(own):
		Tasks.line(app,parent,"你已登記公用耕田機。這是使用資格，不會進背包。每次成功整地耗自己的 1 份木炭。",15)
		return
	var cell:=Loan.loan_cell(snapshot)
	var at_desk:=cell==Loan.DESK
	Tasks.line(app,parent,"還沒有耕田機的島民可以登記借用。登記後一次最多開 9 格田，每次成功整地耗自己的 1 份木炭；播種機和收割機要自己製作。",15)
	var borrow:Button=app.button("登記借用公用耕田機",func():
		app.session.perform(Loan.ACTION,cell)
		if close_after:app._close_modal())
	borrow.name="PublicTillerBorrow"
	borrow.disabled=not near(app,cell)
	parent.add_child(borrow)
	if borrow.disabled:
		if snapshot.get("region_id","home")=="home":
			var directions:Button=app.button("在地圖找借用處",func():
				app._map_menu(Tasks.skill_book.bind(app),"返回生活技能")
				app.map_view.select_home_route("tiller")
			)
			directions.name="PublicTillerDirections"
			parent.add_child(directions)
			Tasks.line(app,parent,"走近渡口公告板後，就能登記。" if at_desk else "走近廣場東南的農機架後，就能登記。",15)
		else:Tasks.line(app,parent,"回到風鈴渡口後，可從周邊地圖找到借用處。",15)

## 世界標籤的 y 偏移：讓標籤底邊落在農機架屋頂上方（圖比一格高時往上推）。
static func label_offset_y() -> float:
	var art:=Loan.texture()
	var height:=art.get_size().y if art!=null else 32.0
	return minf(-12.0,29.0-height)

static func open(app) -> void:
	var body:VBoxContainer=app._open_modal("公用耕田機")
	app.modal.set_meta("life_modal_layout","public_tiller")
	var card:=Tasks.card(body)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	card.add_child(row)
	# 左：農機架圖（2 倍放大、最近鄰）；右：精簡說明與登記按鈕。
	var art:=Loan.texture()
	var picture:=TextureRect.new()
	picture.texture=art if art!=null else ItemArt.icon(Loan.ITEM)
	picture.custom_minimum_size=Vector2(104,120)
	picture.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(picture)
	var details:=VBoxContainer.new()
	details.add_theme_constant_override("separation",8)
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(details)
	Tasks.line(app,details,"渡口的手推耕田機。借的是使用資格，不進背包，也不能出售或交易。",15)
	add_loan(app,details)
	var own:=Tasks.player(app)
	if Loan.can_till(own):
		var charcoal:=int(own.get("inventory",{}).get("charcoal",0))
		Tasks.line(app,details,app.binding_text("木炭 %d 份。"%charcoal+("到炭窯燒木炭後就能整地。" if charcoal<1 else "按 {till_area} 拿起耕田機。")),15)
