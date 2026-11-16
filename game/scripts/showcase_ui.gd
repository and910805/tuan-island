extends RefCounted
## T071 「家園布置題」 client: activity page, world prompts / targeting, HUD tracker
## text and the art helpers shared with world_view.gd. Rules live in showcase.gd; this
## file only reads snapshot.own_showcase (personal view) and snapshot.showcase (public:
## pieces "x,y"->kind, participants keyed by the public player id). Every change goes
## through Session.perform(showcase_start / join / leave / place / remove / finish);
## server replies reach app.modal_feedback / the toast via app._notice like the
## harvest relay and fishing meet pages (harvest_relay_ui.gd / fishing_meet_ui.gd,
## which this file mirrors).
##
## Selected prop: purely client-local (world_view.showcase_kind, default 小花盆); the
## palette on the page changes it, nothing is sent to the server until a placement.
##
## Plot targeting (interact key, no new binding) — plot_target():
##   only while I am joined in an active round at home and the plot is available;
##   1. the cell under the mouse / controller aim (view.show_target) when it is a plot
##      cell within PLACE_REACH (the same pointer target building and tools use);
##   2. otherwise the cell I am facing, when it is a plot cell within reach — facing
##      the sign instead yields no plot target, so the sign keeps its prompt;
##   3. otherwise the plot cell I stand on;
##   4. otherwise the nearest plot cell within reach (row-major on ties).
##   The interact key places the selected prop on an empty target and removes the
##   piece on an occupied one; the world prompt says exactly which (「擺上 紙燈籠」 /
##   「收起 長木椅」). A left click (or controller X) on a plot cell does the same
##   for that cell while joined (main._use_selected_at), rejections come back as the
##   server message.
##
## Art (no new PNGs): sign = assets/ui-life/furniture.png "sign" with a runtime-drawn
## 16 px house glyph on its board and a small rose flag on the LEFT post (豐收接力:
## radish above the board; 河岸釣魚會: carp on the board + blue pennant on the right).
## Plot = warm tint + static cream dashed border with wooden corner stakes (static in
## every motion mode); blocked cells get a red frame. The 8 props are runtime-painted
## 32×32 pixel images (piece_texture), used both on the plot and in the page palette.
##
## HUD priority: 豐收接力 first, then 河岸釣魚會, then this tracker (only writes when
## neither of the other two is tracking).
const World=preload("res://scripts/world.gd")
const Show=preload("res://scripts/showcase.gd")
const HarvestUI=preload("res://scripts/harvest_relay_ui.gd")
const FishMeetUI=preload("res://scripts/fishing_meet_ui.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const TITLE:="家園布置題"
const POINT:="showcase:sign"
const PLOT_POINT:="showcase:plot"
const NO_CELL:=Vector2i(-1,-1)
const DEFAULT_KIND:="flower_pot"
const RULE:="1～8 人、10 分鐘：照本輪主題，在告示牌東邊的展示地塊擺上布置道具，一起完成。用「島民招呼」交流，沒有人會被淘汰。"
const BAG_NOTE:="布置道具只在活動裡使用：不進背包、不花鈴幣、數量不限。中途離開背包維持原樣，這一輪結算時仍會拿到參加紀念票。"
const TICKET_RULE:="參加 1 張、主題完成 +1、滿版 16 件 +1"
const WALK:="請走到渡口西南草地的家園布置題告示牌前（3 格內）再%s。"
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const ROW_HEIGHT:=26
## Plot marker colours.
const PLOT_TINT:=Color(1.0,0.9,0.62,0.17)
const PLOT_EDGE:=Color("fff1c9")
const PLOT_SHADE:=Color(0.36,0.26,0.15,0.55)
const STAKE:=Color("8a6a3e")
const BLOCKED:=Color("d8553f")
const FLAG:=Color("d9667f")
const SHADOW:=Color(0.18,0.13,0.08,0.3)
## Opacity of tree crowns that overlap the sign or the plot (world_view.showcase_tree_alpha).
const TREE_ALPHA:=0.4
static var art_cache:Dictionary={}

# ------------------------------------------------------------------ state --

static func own(s:Dictionary)->Dictionary:
	var found:Variant=s.get("own_showcase",{})
	return found if found is Dictionary else {}

static func public_show(s:Dictionary)->Dictionary:
	var found:Variant=s.get("showcase",{})
	return found if found is Dictionary else {}

static func at_home(s:Dictionary)->bool:
	return str(s.get("region_id","home"))=="home"

## The sign is drawn (and opens the page) at home after the picnic while its cell is free.
static func sign_shown(s:Dictionary)->bool:
	return at_home(s) and Show.unlocked(s) and Show.cell_free(s,Show.SIGN)

## The plot outline (and every piece on it) is drawn at home after the picnic.
static func plot_shown(s:Dictionary)->bool:
	return at_home(s) and Show.unlocked(s)

## Start / join / place / remove / finish are possible (unlocked and all 25 cells free).
static func on_field(s:Dictionary)->bool:
	return at_home(s) and Show.available(s)

## The HUD tracker and plot targeting follow the round only while I am joined in it at home.
static func tracking(s:Dictionary)->bool:
	var m:=own(s)
	return at_home(s) and bool(m.get("active",false)) and bool(m.get("joined",false))

static func position_of(s:Dictionary,id:String)->Variant:
	var person:Variant=s.get("players",{}).get(id)
	if not person is Dictionary:return null
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0)))

static func near_sign(s:Dictionary,id:String)->bool:
	var at:Variant=position_of(s,id)
	return at_home(s) and at is Vector2 and (at as Vector2).distance_to(Vector2(Show.SIGN)+Vector2(0.5,0.5))<=Show.SIGN_REACH

static func whole_seconds(value:Variant)->int:
	return HarvestUI.whole_seconds(value)

## Kind of the piece on a plot cell ("" when empty), from the public snapshot.
static func piece_at(s:Dictionary,cell:Vector2i)->String:
	var pieces:Variant=public_show(s).get("pieces",{})
	if not pieces is Dictionary:return ""
	var kind:=str((pieces as Dictionary).get(Show.cell_key(cell),""))
	return kind if Show.KINDS.has(kind) else ""

static func pieces(s:Dictionary)->Dictionary:
	var found:Variant=public_show(s).get("pieces",{})
	return found if found is Dictionary else {}

## The client-local selected prop (world_view.showcase_kind).
static func selected_kind(app)->String:
	var kind:=str(app.view.showcase_kind) if app.view!=null else DEFAULT_KIND
	return kind if Show.KINDS.has(kind) else DEFAULT_KIND

static func _reach(pos:Vector2,cell:Vector2i)->bool:
	return pos.distance_to(Vector2(cell)+Vector2(0.5,0.5))<=Show.PLACE_REACH+0.0001

## See the header: pointer cell, facing cell, own cell, nearest cell within reach.
static func plot_target(s:Dictionary,id:String,facing:Vector2i,pointer:Vector2i)->Vector2i:
	if not tracking(s) or not on_field(s):return NO_CELL
	var at:Variant=position_of(s,id)
	if not at is Vector2:return NO_CELL
	var pos:Vector2=at
	if pointer!=NO_CELL and Show.in_plot(pointer) and _reach(pos,pointer):return pointer
	var cell:=Vector2i(pos.floor())
	var front:=cell+facing
	if front==Show.SIGN:return NO_CELL
	if facing!=Vector2i.ZERO and Show.in_plot(front) and _reach(pos,front):return front
	if Show.in_plot(cell):return cell
	var best:=NO_CELL
	var best_distance:=INF
	for c:Vector2i in Show.plot_cells():
		var d:=pos.distance_to(Vector2(c)+Vector2(0.5,0.5))
		if d<=Show.PLACE_REACH+0.0001 and d<best_distance-0.0001:
			best=c
			best_distance=d
	return best

## plot_target for a world_view (its snapshot, facing and pointer target).
static func view_target(view)->Vector2i:
	var s:Dictionary=view.data
	if s.is_empty():return NO_CELL
	var pointer:Vector2i=view.target if view.show_target else NO_CELL
	return plot_target(s,str(view.player_id),view.facings.get(view.player_id,Vector2i.DOWN),pointer)

## What the interact key does on a plot cell, word for word.
static func prompt(s:Dictionary,cell:Vector2i,kind:String)->String:
	var there:=piece_at(s,cell)
	if not there.is_empty():return "收起 "+Show.kind_name(there)
	return "擺上 "+Show.kind_name(kind if Show.KINDS.has(kind) else DEFAULT_KIND)

## World label of the sign. Focused: what the interact key does. Unfocused it stays
## the short name (the sign sits near the top-left tracker when viewed from the plot).
static func sign_title(_s:Dictionary,focused:bool)->String:
	return TITLE+"・打開活動" if focused else TITLE

# ------------------------------------------------------------- actions --

## Place the selected prop on an empty cell, or remove the piece on an occupied one.
static func act(app,cell:Vector2i)->void:
	var s:Dictionary=app.session.snapshot
	var round_id:=int(own(s).get("round",0))
	if piece_at(s,cell).is_empty():
		app.session.perform("showcase_place",cell,"%d|%s"%[round_id,selected_kind(app)])
	else:
		app.session.perform("showcase_remove",cell,str(round_id))

## main._interact (at home, before the ordinary interaction points).
static func interact(app)->bool:
	if app.view==null:return false
	var cell:=view_target(app.view)
	if cell==NO_CELL:return false
	act(app,cell)
	return true

## main._use_selected_at: a click / controller X on a plot cell while joined.
static func click(app,cell:Vector2i)->bool:
	if not tracking(app.session.snapshot) or not Show.in_plot(cell):return false
	act(app,cell)
	return true

static func select_kind(app,kind:String)->void:
	if not Show.KINDS.has(kind) or app.view==null:return
	app.view.showcase_kind=kind
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text="已選好「%s」：站到展示地塊旁按 %s 擺上。"%[Show.kind_name(kind),app.binding_label("interact")]
	refresh(app)

# -------------------------------------------------------------------- art --

static func _rect(img:Image,x:int,y:int,w:int,h:int,c:Color)->void:
	img.fill_rect(Rect2i(x,y,w,h).intersection(Rect2i(0,0,img.get_width(),img.get_height())),c)

static func _boxed(img:Image,x:int,y:int,w:int,h:int,fill:Color,edge:Color)->void:
	_rect(img,x,y,w,h,edge)
	_rect(img,x+1,y+1,w-2,h-2,fill)

static func _px(img:Image,x:int,y:int,c:Color)->void:
	if x>=0 and y>=0 and x<img.get_width() and y<img.get_height():img.set_pixel(x,y,c)

static func _line(img:Image,a:Vector2i,b:Vector2i,c:Color,thick:=1)->void:
	var steps:=maxi(absi(b.x-a.x),absi(b.y-a.y))
	for i in steps+1:
		var t:=float(i)/maxf(1.0,float(steps))
		var p:=Vector2(a).lerp(Vector2(b),t).round()
		_rect(img,int(p.x),int(p.y),thick,thick,c)

## Runtime-painted 32×32 pixel prop (cached). Feet on the tile's lower edge.
static func piece_texture(kind:String)->Texture2D:
	if art_cache.has("piece:"+kind):return art_cache["piece:"+kind]
	var img:=Image.create(32,32,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	match kind:
		"flower_pot":
			_rect(img,9,29,14,2,SHADOW)
			for stem:Array in [[13,12,7],[16,8,11],[19,13,6]]:_rect(img,stem[0],stem[1],1,stem[2],Color("4f8a36"))
			_rect(img,14,15,2,1,Color("6aa84a"));_rect(img,17,13,2,1,Color("6aa84a"));_rect(img,17,17,2,1,Color("6aa84a"))
			for bloom:Array in [[11,9,"e0505a","ffe08a"],[14,5,"f29cb8","fff4d8"],[18,10,"f2cf4a","c0653f"]]:
				_boxed(img,bloom[0],bloom[1],5,5,Color(bloom[2]),Color(bloom[2]).darkened(0.35))
				_px(img,bloom[0]+2,bloom[1]+2,Color(bloom[3]))
			_boxed(img,11,21,10,9,Color("c0653f"),Color("5e3322"))
			_boxed(img,9,19,14,4,Color("dc8a5c"),Color("5e3322"))
			_rect(img,12,23,2,5,Color("d9805a"))
		"flower_box":
			_rect(img,3,29,27,2,SHADOW)
			for x in [4,8,12,16,20,24]:
				_rect(img,x,15,4,6,Color("4f8a36"))
				_rect(img,x+1,14,2,2,Color("7fbf5a"))
			for bloom:Array in [[5,"fff4d8"],[10,"9a7fd0"],[15,"fff4d8"],[20,"9a7fd0"],[25,"fff4d8"]]:
				_boxed(img,bloom[0],11,3,3,Color(bloom[1]),Color(bloom[1]).darkened(0.4))
			_boxed(img,3,20,26,10,Color("a8743f"),Color("5a3d24"))
			_rect(img,4,21,24,1,Color("5b4030"))
			_rect(img,4,25,24,1,Color("8a5c30"))
			_rect(img,6,27,3,1,Color("5a3d24"));_rect(img,23,27,3,1,Color("5a3d24"))
		"fern":
			_rect(img,9,29,14,2,SHADOW)
			var base:=Vector2i(16,21)
			for tip:Vector2i in [Vector2i(3,10),Vector2i(6,4),Vector2i(12,1),Vector2i(20,1),Vector2i(26,4),Vector2i(29,10),Vector2i(16,0)]:
				_line(img,base,tip,Color("2f6a32"),2)
				var steps:=maxi(absi(tip.x-base.x),absi(tip.y-base.y))
				for i in range(3,steps,3):
					var p:=Vector2(base).lerp(Vector2(tip),float(i)/float(steps)).round()
					_rect(img,int(p.x)-1,int(p.y),3,1,Color("77b55a"))
			_boxed(img,11,22,10,8,Color("6f8fa8"),Color("34495a"))
			_boxed(img,10,20,12,3,Color("8fb0c6"),Color("34495a"))
			_rect(img,12,24,2,4,Color("8fb0c6"))
		"stool":
			_rect(img,8,29,17,2,SHADOW)
			_rect(img,9,19,3,10,Color("6b4a2f"));_rect(img,10,19,1,10,Color("8d6440"))
			_rect(img,20,19,3,10,Color("6b4a2f"));_rect(img,21,19,1,10,Color("8d6440"))
			_rect(img,15,20,2,7,Color("7a5232"))
			_rect(img,11,25,10,1,Color("6b4a2f"))
			_boxed(img,7,13,18,7,Color("d9a866"),Color("6b4a2f"))
			_rect(img,8,14,16,1,Color("efc98f"))
			_rect(img,7,13,1,1,Color(0,0,0,0));_rect(img,24,13,1,1,Color(0,0,0,0))
		"bench":
			_rect(img,1,29,31,2,SHADOW)
			_rect(img,3,6,3,16,Color("4a2f1b"));_rect(img,26,6,3,16,Color("4a2f1b"))
			_boxed(img,2,7,28,4,Color("9c6a3e"),Color("4a2f1b"))
			_boxed(img,2,12,28,4,Color("9c6a3e"),Color("4a2f1b"))
			_boxed(img,0,17,32,6,Color("c08a52"),Color("4a2f1b"))
			_rect(img,1,18,30,1,Color("dcaa70"))
			_rect(img,3,23,3,7,Color("5d3c22"));_rect(img,26,23,3,7,Color("5d3c22"))
		"cushion":
			_rect(img,4,28,26,3,SHADOW)
			_rect(img,3,15,26,14,Color("7a2c2a"))
			for y in range(16,28):
				for x in range(4,28):
					var on_x:=((x-4)/4)%2==0
					var on_y:=((y-16)/4)%2==0
					var c:=Color("fff3e6")
					if on_x and on_y:c=Color("c9423f")
					elif on_x or on_y:c=Color("ec9a8f")
					img.set_pixel(x,y,c)
			for corner:Vector2i in [Vector2i(1,13),Vector2i(27,13),Vector2i(1,27),Vector2i(27,27)]:_boxed(img,corner.x,corner.y,4,4,Color("f0c048"),Color("8a5c30"))
		"lantern":
			_boxed(img,3,27,9,4,Color("9a9a8c"),Color("4d4a40"))
			_rect(img,6,2,3,26,Color("4a3626"))
			_rect(img,6,2,14,2,Color("4a3626"))
			_rect(img,18,4,1,3,Color("4a3626"))
			_rect(img,14,7,9,2,Color("3a2a1e"))
			_rect(img,12,10,13,10,Color("6e1f1a"))
			_rect(img,13,9,11,12,Color("6e1f1a"))
			_rect(img,13,10,11,10,Color("d8453a"))
			_rect(img,14,9,9,12,Color("d8453a"))
			_rect(img,15,10,1,10,Color("b53a30"));_rect(img,21,10,1,10,Color("b53a30"))
			_rect(img,17,11,2,7,Color("ff9a6a"))
			_rect(img,14,9,9,1,Color("f0c048"));_rect(img,14,20,9,1,Color("f0c048"))
			_rect(img,15,21,7,2,Color("3a2a1e"))
			_rect(img,18,23,1,4,Color("f0c048"))
		"string_lights":
			_rect(img,0,29,6,2,SHADOW);_rect(img,26,29,6,2,SHADOW)
			_rect(img,2,5,2,25,Color("6b4a2f"));_rect(img,28,5,2,25,Color("6b4a2f"))
			_rect(img,1,4,4,2,Color("4a3626"));_rect(img,27,4,4,2,Color("4a3626"))
			var wire:={}
			for x in range(4,28):
				var y:=6+int(round(8.0*sin(PI*float(x-4)/23.0)))
				wire[x]=y
				_px(img,x,y,Color("3a2a1e"))
			var colours:=["ffd84a","5ec4c0","f58fb0","f5a04a","ffd84a"]
			var index:=0
			for x in [7,11,15,19,23]:
				var y:int=wire[x]
				_px(img,x,y+1,Color("3a2a1e"))
				_boxed(img,x-1,y+2,3,4,Color(colours[index]),Color(colours[index]).darkened(0.45))
				_px(img,x,y+3,Color(colours[index]).lightened(0.45))
				index+=1
	var result:=ImageTexture.create_from_image(img)
	art_cache["piece:"+kind]=result
	return result

## 16×16 house glyph painted on the sign's board.
static func home_glyph()->Texture2D:
	if art_cache.has("home"):return art_cache["home"]
	var img:=Image.create(16,16,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	for r in 7:
		_rect(img,7-r,1+r,2+2*r,1,Color("5e3322"))
		if r>0:_rect(img,8-r,1+r,2*r,1,Color("d0583f"))
	_boxed(img,2,8,12,7,Color("fff1d6"),Color("5e3322"))
	_rect(img,7,10,3,5,Color("8a5c30"))
	_rect(img,3,10,3,2,Color("5ec4c0"))
	_rect(img,11,10,2,2,Color("f2cf4a"))
	var result:=ImageTexture.create_from_image(img)
	art_cache["home"]=result
	return result

## Screen rect (world px, unzoomed) of the whole plot.
static func plot_rect(view)->Rect2:
	return Rect2(view.screen(Vector2(Show.PLOT.position)),Vector2(Show.PLOT.size)*32.0)

## Screen rect (world px, unzoomed) of the sign sprite + flag, for label checks.
static func sign_rect(view)->Rect2:
	var at:Vector2=view.screen(Vector2(Show.SIGN))
	return Rect2(at+Vector2(-8,-2),Vector2(40,34))

## Ground layer: warm tint, static cream dashed border and corner stakes; blocked
## cells framed in red; the targeted cell gets the usual cream target frame.
static func draw_plot(view,s:Dictionary,target:Vector2i)->void:
	var r:=plot_rect(view)
	view.draw_rect(r,PLOT_TINT)
	var inner:=r.grow(-2.0)
	var corners:=[inner.position,Vector2(inner.end.x,inner.position.y),inner.end,Vector2(inner.position.x,inner.end.y)]
	for i in 4:
		var a:Vector2=corners[i]
		var b:Vector2=corners[(i+1)%4]
		var length:=a.distance_to(b)
		var dir:=(b-a)/maxf(length,1.0)
		var t:=4.0
		while t<length-4.0:
			var e:=minf(t+6.0,length-4.0)
			view.draw_line((a+dir*t).round()+Vector2(1,1),(a+dir*e).round()+Vector2(1,1),PLOT_SHADE,2.0)
			view.draw_line((a+dir*t).round(),(a+dir*e).round(),PLOT_EDGE,2.0)
			t+=10.0
	for c:Vector2 in corners:
		var stake:=(c-Vector2(2,3)).round()
		view.draw_rect(Rect2(stake,Vector2(4,6)),Color("4a3626"))
		view.draw_rect(Rect2(stake+Vector2(1,1),Vector2(2,4)),STAKE)
	for cell:Vector2i in Show.blocked_cells(s):
		if not Show.in_plot(cell):continue
		var at:Vector2=view.screen(Vector2(cell))
		view.draw_rect(Rect2(at+Vector2(2,2),Vector2(28,28)),BLOCKED,false,2.0)
		view.draw_line(at+Vector2(6,6),at+Vector2(26,26),BLOCKED,2.0)
	if target!=NO_CELL:
		var at:Vector2=view.screen(Vector2(target))
		view.draw_rect(Rect2(at+Vector2.ONE,Vector2(30,30)),Color(1,0.98,0.78,0.22))
		view.draw_rect(Rect2(at+Vector2.ONE,Vector2(30,30)),Color("fff4c2"),false,2.0)

static func draw_piece(view,at:Vector2,kind:String)->void:
	var texture:=piece_texture(kind)
	if texture:view.draw_texture(texture,at)

## Sign: the shared sign sprite, a house glyph on its board and a rose flag on the
## left post, so it reads differently from the 豐收接力 and 河岸釣魚會 signs.
static func draw_sign(view,at:Vector2,furniture)->void:
	furniture.draw_sprite(view,at,"sign")
	view.draw_rect(Rect2(at+Vector2(1,-2),Vector2(2,12)),Color("6b4a2f"))
	view.draw_colored_polygon(PackedVector2Array([at+Vector2(1,-2),at+Vector2(-7,1),at+Vector2(1,4)]),FLAG)
	view.draw_texture_rect(home_glyph(),Rect2(at+Vector2(8,3),Vector2(16,16)),false)

# ------------------------------------------------------------------ HUD --

## main._refresh_hud, after HarvestUI / FishMeetUI.refresh_hud: while I am joined in an
## active round (and neither of the other two activities is tracking) the tracker
## follows this round.
static func refresh_hud(app,s:Dictionary)->void:
	if not tracking(s) or HarvestUI.tracking(s) or FishMeetUI.tracking(s):return
	app.objective.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	app.objective.text=hud_text(own(s),selected_kind(app),app.binding_label("interact"))
	var heading:=app.hud.find_child("TrackerHeading",true,false) as Button
	if heading:heading.text=TITLE+"  ▾"
	var next:=app.hud.find_child("TrackerNext",true,false) as Button
	if next:next.text="查看家園布置題  →"

## Three short lines so the 202 px tracker never wraps mid-number.
static func hud_text(m:Dictionary,kind:String,key:String)->String:
	var parts:=PackedStringArray()
	for row:Dictionary in requirement_rows(m):
		parts.append("%s %d/%d%s"%[str(row.get("name","")),int(row.get("have",0)),int(row.get("need",0)),"✓" if bool(row.get("met",false)) else ""])
	return "%s %s\n%s\n剩 %d 秒 · %s 擺%s"%[TITLE,str(m.get("theme_name",""))," ".join(parts),whole_seconds(m.get("seconds_left",0.0)),key,Show.kind_name(kind)]

# ---------------------------------------------------------------- panel --

static func open(app)->void:
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.name="ShowcasePanel"
	app.modal.set_meta("life_modal_layout","showcase")
	app.modal.set_meta("showcase_body",body)
	if app.village_art_preview:
		app.modal.theme=Pixel.make(app.hud.theme)
		app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.26
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上 · 布置道具不會進背包"
	body.add_theme_constant_override("separation",7)
	refresh(app)
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

## main._layout_preview: wide like the harvest panel, as tall as its content.
static func layout(app,bounds:Vector2)->void:
	HarvestUI.layout(app,bounds)

static func is_open(app)->bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("showcase_body")

## First enabled main action (開始／加入／完成展示／離開), else the selected prop.
static func focus_first(app)->void:
	if not is_open(app):return
	var body:Control=app.modal.get_meta("showcase_body")
	for id in ["ShowcaseStart","ShowcaseJoin","ShowcaseFinish","ShowcaseLeave"]:
		var b:=body.find_child(id,true,false) as BaseButton
		if b!=null and b.is_visible_in_tree() and not b.disabled:
			b.grab_focus()
			return
	var chosen:=body.find_child("ShowcaseKind_"+selected_kind(app),true,false) as BaseButton
	if chosen!=null and chosen.is_visible_in_tree():
		chosen.grab_focus()
		return
	var close:=close_button(app)
	if close!=null:close.grab_focus()

## The 「關閉  Esc」 button of the modal heading (outside the body).
static func close_button(app)->BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("showcase_body") if app.modal.has_meta("showcase_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func refresh(app)->void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var id:String=app.session.own_id
	var m:=own(s)
	var body:VBoxContainer=app.modal.get_meta("showcase_body")
	# seconds_left changes every tick: update it in place instead of rebuilding.
	var signature:=JSON.stringify([m.duplicate(true).merged({"seconds_left":0,"cooldown":0},true),at_home(s),on_field(s),near_sign(s,id),whole_seconds(m.get("cooldown",0.0)),selected_kind(app)])
	if str(app.modal.get_meta("showcase_signature",""))==signature:
		var time_label:=body.find_child("ShowcaseTime",true,false) as Label
		if time_label:time_label.text=time_text(m)
		return
	app.modal.set_meta("showcase_signature",signature)
	var focused:Control=body.get_viewport().gui_get_focus_owner() if body.is_inside_tree() else null
	var focus_name:String=str(focused.name) if is_instance_valid(focused) and body.is_ancestor_of(focused) else ""
	for child in body.get_children():body.remove_child(child);child.queue_free()
	if not bool(m.get("unlocked",false)):
		HarvestUI.wrapped(app,body,Show.LOCKED,17).name="ShowcaseLocked"
		HarvestUI.wrapped(app,body,RULE,14,MUTED).name="ShowcaseRule"
		app._layout_preview.call_deferred()
		return
	build(app,body,s,id,m)
	if not focus_name.is_empty():
		var next:=body.find_child(focus_name,true,false) as BaseButton
		if next!=null and not next.disabled:next.grab_focus.call_deferred()
		else:focus_first.call_deferred(app)
	app._layout_preview.call_deferred()

static func time_text(m:Dictionary)->String:
	if bool(m.get("active",false)):return "剩 %d 秒"%whole_seconds(m.get("seconds_left",0.0))
	var wait:=whole_seconds(m.get("cooldown",0.0))
	return "整理地塊・約 %d 秒"%wait if wait>0 else "可以開始"

## Text of the paused line: which cells must be cleared.
static func blocked_text(m:Dictionary)->String:
	var names:=PackedStringArray()
	for cell in blocked_list(m):
		var c:Vector2i=cell
		names.append(("告示牌 (%d,%d)" if c==Show.SIGN else "地塊 (%d,%d)")%[c.x,c.y])
	return "需要清理的格子：%s。拿走上面的物件、地板、屋頂、作物或樹，活動就會恢復。"%"、".join(names)

static func blocked_list(m:Dictionary)->Array:
	var found:Variant=m.get("blocked_cells",[])
	return found if found is Array else []

static func requirement_rows(m:Dictionary)->Array:
	var found:Variant=m.get("requirements",[])
	return found if found is Array else []

static func missing_text(m:Dictionary)->String:
	var parts:=PackedStringArray()
	for row:Dictionary in requirement_rows(m):
		if not bool(row.get("met",false)):parts.append("%s %d"%[str(row.get("name","")),int(row.get("need",0))-int(row.get("have",0))])
	return "、".join(parts)

static func kind_button(app,parent:Node,kind:String,selected:bool)->Button:
	var b:Button=app.button(Show.kind_name(kind),func():select_kind(app,kind))
	b.name="ShowcaseKind_"+kind
	b.icon=piece_texture(kind)
	b.add_theme_constant_override("icon_max_width",22)
	b.add_theme_constant_override("h_separation",3)
	b.custom_minimum_size=Vector2(0,30)
	b.add_theme_font_size_override("font_size",13)
	b.toggle_mode=true
	b.button_pressed=selected
	b.focus_mode=Control.FOCUS_ALL
	b.tooltip_text="%s（%s）"%[Show.kind_name(kind),Show.CATEGORY_NAMES[Show.category_of(kind)]]
	if selected:b.add_theme_color_override("font_color",GOOD)
	parent.add_child(b)
	return b

static func build(app,body:VBoxContainer,s:Dictionary,id:String,m:Dictionary)->void:
	var active:=bool(m.get("active",false))
	var round_id:=int(m.get("round",0))
	var finished:=not active and round_id>0
	var kind:=selected_kind(app)
	# 1. Header: round, pieces, time.
	var header:=HBoxContainer.new();header.name="ShowcaseHeader";header.add_theme_constant_override("separation",14);body.add_child(header)
	header.add_child(Shell.picture(home_glyph(),32))
	HarvestUI.text(app,header,"第 %d 輪進行中"%round_id if active else "目前沒有進行中的一輪",17).name="ShowcaseStatus"
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(spacer)
	HarvestUI.text(app,header,("上一輪 " if finished else "")+"展示 %d 件 · 滿版 %d 件"%[int(m.get("pieces_count",0)),Show.FULL_GOAL],16).name="ShowcaseProgress"
	HarvestUI.text(app,header,time_text(m),16,WARN if active else MUTED).name="ShowcaseTime"
	HarvestUI.wrapped(app,body,RULE,14,MUTED).name="ShowcaseRule"
	# 2. Theme checklist + prop palette (left), participants (right).
	var columns:=HBoxContainer.new();columns.name="ShowcaseColumns";columns.add_theme_constant_override("separation",12);body.add_child(columns)
	var left:=HarvestUI.paper(columns,"ShowcaseThemeCard")
	left.get_parent().size_flags_stretch_ratio=1.15
	var theme:=str(m.get("theme","")) if active else Show.theme_of(round_id+1)
	var title:="本輪主題「%s」"%Show.theme_name(theme) if active else "下一輪主題「%s」"%Show.theme_name(theme)
	HarvestUI.text(app,left,title,17).name="ShowcaseThemeTitle"
	HarvestUI.wrapped(app,left,str(Show.THEMES[theme].blurb) if Show.THEMES.has(theme) else "",13,MUTED).name="ShowcaseBlurb"
	var rows:Array=requirement_rows(m) if active else Show.requirements(theme,{})
	var palette:Array=[]
	for row:Dictionary in rows:
		var category:=str(row.get("category",""))
		var line:=HBoxContainer.new();line.name="ShowcaseNeed_"+category;line.add_theme_constant_override("separation",5);left.add_child(line)
		var met:=active and bool(row.get("met",false))
		var check:=HarvestUI.text(app,line,"%s %d／%d%s"%[str(row.get("name","")),int(row.get("have",0)),int(row.get("need",0))," ✓" if met else ""],15,GOOD if met else INK)
		check.name="ShowcaseCheck_"+category
		check.custom_minimum_size.x=88
		var group:Array[Button]=[]
		for k:String in Show.KIND_ORDER:
			if Show.category_of(k)==category:group.append(kind_button(app,line,k,k==kind))
		palette.append(group)
	var chosen:=HarvestUI.wrapped(app,left,"選好的道具：%s · 地塊旁按 %s 擺上；對著已擺的道具按 %s 收起。"%[Show.kind_name(kind),app.binding_label("interact"),app.binding_label("interact")],13,INK)
	chosen.name="ShowcaseSelected"
	HarvestUI.wrapped(app,left,BAG_NOTE,13,GOOD).name="ShowcaseBagNote"
	var right:=HarvestUI.paper(columns,"ShowcasePeopleCard")
	var people_head:=HBoxContainer.new();right.add_child(people_head)
	var people_title:=HarvestUI.text(app,people_head,"參加者",17);people_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	HarvestUI.text(app,people_head,"%d／%d 人在場"%[int(m.get("joined_count",0)),int(m.get("max_players",Show.MAX_PLAYERS))],14).name="ShowcasePeopleCount"
	var people:=VBoxContainer.new();people.name="ShowcasePeople";people.add_theme_constant_override("separation",2);right.add_child(people)
	var list:Array=(m.get("participants",[]) as Array).duplicate() if m.get("participants",[]) is Array else []
	# Me first, then the others who are in (server order is stable), then those who left.
	var ordered:Array=list.filter(func(e):return bool(e.get("me",false)))+list.filter(func(e):return bool(e.get("joined",false)) and not bool(e.get("me",false)))+list.filter(func(e):return not bool(e.get("joined",false)) and not bool(e.get("me",false)))
	if ordered.is_empty():HarvestUI.text(app,people,"還沒有人參加。" if not active else "還沒有人加入這一輪。",14,MUTED).name="ShowcasePeopleEmpty"
	for index in mini(ordered.size(),Show.MAX_PLAYERS):
		var entry:Dictionary=ordered[index]
		var row:=HBoxContainer.new();row.name="ShowcasePerson_%d"%index;row.add_theme_constant_override("separation",6)
		row.custom_minimum_size.y=ROW_HEIGHT;people.add_child(row)
		var here:=bool(entry.get("joined",false))
		var who:=HarvestUI.text(app,row,str(entry.get("name","島民"))+("（我）" if bool(entry.get("me",false)) else ""),15,INK if here or not active else MUTED)
		who.custom_minimum_size.x=124
		var state:="在場" if here else "已離開"
		if not active:state="本輪結束"
		HarvestUI.text(app,row,"%s · 地塊上 %d 件 · 擺過 %d 次"%[state,int(entry.get("shown",0)),int(entry.get("placed",0))],14,INK if here or not active else MUTED).name="ShowcasePersonDetail_%d"%index
	if ordered.size()>Show.MAX_PLAYERS:
		HarvestUI.text(app,people,"另有 %d 位曾參加這一輪。"%(ordered.size()-Show.MAX_PLAYERS),13,MUTED).name="ShowcasePeopleMore"
	# 3. Actions + the one reason line (+ the cells to clear while paused).
	var reasons:=action_reasons(s,id,m)
	var bar:=HBoxContainer.new();bar.name="ShowcaseActions";bar.add_theme_constant_override("separation",10);body.add_child(bar)
	var round_text:=str(round_id)
	var buttons:Array[Button]=[]
	buttons.append(HarvestUI.action(app,bar,"ShowcaseStart","開始一場",func():app.session.perform("showcase_start",Show.SIGN,round_text),reasons.start.is_empty(),reasons.start))
	buttons.append(HarvestUI.action(app,bar,"ShowcaseJoin","加入",func():app.session.perform("showcase_join",Show.SIGN,round_text),reasons.join.is_empty(),reasons.join))
	buttons.append(HarvestUI.action(app,bar,"ShowcaseLeave","離開活動",func():app.session.perform("showcase_leave",Show.SIGN,""),reasons.leave.is_empty(),reasons.leave))
	buttons.append(HarvestUI.action(app,bar,"ShowcaseFinish","完成展示",func():app.session.perform("showcase_finish",Show.SIGN,round_text),reasons.finish.is_empty(),reasons.finish))
	buttons.append(HarvestUI.action(app,bar,"ShowcaseEmote","島民招呼",func():app._emote_menu(),true))
	for b in buttons:b.custom_minimum_size.x=118
	var hint:=HarvestUI.wrapped(app,body,hint_text(app,m,reasons),14,WARN if not reasons.hint_ok else GOOD)
	hint.name="ShowcaseHint"
	if not blocked_list(m).is_empty():
		HarvestUI.wrapped(app,body,blocked_text(m),14,WARN).name="ShowcaseBlocked"
	palette.append(buttons)
	link_focus(app,palette)
	# 4. Last round (clearly the previous one) + my record.
	var bottom:=HBoxContainer.new();bottom.name="ShowcaseBottom";bottom.add_theme_constant_override("separation",12);body.add_child(bottom)
	var last_box:=HarvestUI.paper(bottom,"ShowcaseLastCard")
	var last:Dictionary=m.get("last",{}) if m.get("last",{}) is Dictionary else {}
	HarvestUI.text(app,last_box,"上一輪成果（已結束）",15).name="ShowcaseLastTitle"
	if last.is_empty():
		HarvestUI.text(app,last_box,"還沒有完成的一輪",14,MUTED).name="ShowcaseLast"
	else:
		var why:="提早完成展示" if str(last.get("reason",""))=="goal" else "時間到"
		var result:="主題完成" if bool(last.get("met",false)) else "主題未完成"
		if bool(last.get("full",false)):result+=" · 滿版"
		HarvestUI.text(app,last_box,"第 %d 輪「%s」· %s · %s"%[int(last.get("round",0)),Show.theme_name(str(last.get("theme",""))),why,result],14).name="ShowcaseLast"
		HarvestUI.text(app,last_box,"展示 %d 件 · %d 人參加 · 每人 %d 張紀念票"%[int(last.get("pieces",0)),int(last.get("players",0)),int(last.get("tickets",0))],14).name="ShowcaseLastTickets"
	var record_box:=HarvestUI.paper(bottom,"ShowcaseRecordCard")
	HarvestUI.souvenir_note(app,record_box,"Showcase")
	HarvestUI.text(app,record_box,"紀念票 %d 張 · 參加 %d 場 · 最佳 %d 件"%[int(m.get("tickets",0)),int(m.get("rounds",0)),int(m.get("best",0))],14).name="ShowcaseRecord"
	HarvestUI.text(app,record_box,TICKET_RULE,13,MUTED).name="ShowcaseTicketRule"

## Why each button is disabled ("" = enabled) plus whether the hint is good news.
static func action_reasons(s:Dictionary,id:String,m:Dictionary)->Dictionary:
	var active:=bool(m.get("active",false))
	var joined:=bool(m.get("joined",false))
	var near:=near_sign(s,id)
	var out:={"start":"","join":"","leave":"","finish":"","hint_ok":false}
	var wait:=whole_seconds(m.get("cooldown",0.0))
	var field:=""
	if not at_home(s):field=Show.WRONG_REGION
	elif not bool(m.get("available",false)):field=Show.UNAVAILABLE
	if not field.is_empty():out.start=field
	elif active:out.start="這一輪正在進行，按「加入」就能一起布置。"
	elif wait>0:out.start=Show.COOLDOWN_MSG%wait
	elif not near:out.start=WALK%"開始"
	if not field.is_empty():out.join=field
	elif not active:out.join="目前沒有進行中的一輪。"
	elif joined:out.join=Show.ALREADY_JOINED
	elif int(m.get("joined_count",0))>=int(m.get("max_players",Show.MAX_PLAYERS)):out.join=Show.FULL%Show.MAX_PLAYERS
	elif not near:out.join=WALK%"加入"
	if not at_home(s):out.leave=Show.WRONG_REGION
	elif not active or not joined:out.leave="還沒有加入這一輪。"
	if not field.is_empty():out.finish=field
	elif not active:out.finish="目前沒有進行中的一輪。"
	elif not joined:out.finish="先加入這一輪才能完成展示。"
	elif not bool(m.get("theme_met",false)):out.finish="主題還沒完成：還差 %s。"%missing_text(m)
	elif not bool(m.get("can_finish",false)):out.finish=Show.ENDING
	return out

static func hint_text(app,m:Dictionary,reasons:Dictionary)->String:
	var active:=bool(m.get("active",false))
	var joined:=bool(m.get("joined",false))
	var key:String=app.binding_label("interact")
	if not active:
		if reasons.start.is_empty():
			reasons.hint_ok=true
			return "可以開始：按「開始一場」，其他人在告示牌前按「加入」。"
		return str(reasons.start)
	if not joined:
		if reasons.join.is_empty():
			reasons.hint_ok=true
			return "按「加入」一起布置；中途也能加入或離開。"
		return str(reasons.join)
	if str(reasons.finish).begins_with("主題還沒完成"):
		reasons.hint_ok=true
		return "完成展示要先達成主題：還差 %s。選好道具，站到地塊旁按 %s 擺上。"%[missing_text(m),key]
	if reasons.finish.is_empty():
		reasons.hint_ok=true
		return "主題完成了！按「完成展示」結算，或繼續擺到 %d 件（三類都有）多拿 1 張。"%Show.FULL_GOAL
	return str(reasons.finish)

## Explicit keyboard/gamepad neighbours over a grid of rows (palette rows, then the
## action bar): left/right wrap inside a row, up/down move between rows (column
## clamped), up from the first row reaches 「關閉」, down from 「關閉」 returns to the
## first enabled button of the first row; Tab follows the flattened order.
static func link_focus(app,rows:Array)->void:
	var grid:Array=[]
	for row in rows:
		var enabled:Array[Button]=[]
		for b:Button in row:
			if not b.disabled:enabled.append(b)
		if not enabled.is_empty():grid.append(enabled)
	var flat:Array[Button]=[]
	for row in grid:flat.append_array(row)
	var close:=close_button(app)
	for r in grid.size():
		var row:Array=grid[r]
		for i in row.size():
			var b:Button=row[i]
			b.focus_neighbor_left=b.get_path_to(row[(i-1+row.size())%row.size()])
			b.focus_neighbor_right=b.get_path_to(row[(i+1)%row.size()])
			if r>0:b.focus_neighbor_top=b.get_path_to(grid[r-1][mini(i,grid[r-1].size()-1)])
			elif close!=null:b.focus_neighbor_top=b.get_path_to(close)
			b.focus_neighbor_bottom=b.get_path_to(grid[r+1][mini(i,grid[r+1].size()-1)] if r+1<grid.size() else b)
			var at:=flat.find(b)
			b.focus_next=b.get_path_to(flat[(at+1)%flat.size()])
			b.focus_previous=b.get_path_to(flat[(at-1+flat.size())%flat.size()])
	if close!=null and not flat.is_empty():
		close.focus_neighbor_bottom=close.get_path_to(flat[0])
		close.focus_next=close.get_path_to(flat[0])
