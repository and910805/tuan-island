extends Control
## T066 N01-1 阿榆〈有點歪的第一塊板〉小動畫：阿榆在木工桌旁，把那塊有點歪的板
## （既有紀念小物圖 keepsake_aru）推上桌面，落下一點木屑、板上節疤閃一下。
##
## 全部沿用既有像素資源，沒有新美術檔，也不在 Control 內畫任何文字：
##  * 阿榆：character_sprite_art.gd 的「aru」圖格（朝右）；
##  * 板：resident_keepsake_art.gd 的 keepsake_aru（32×32，與背包／世界圖同一張）；
##  * 桌上的木頭、木板：inventory_item_art.gd 的 wood／plank 圖示；
##  * 桌子沿用木工台的正式像素圖。牆板、工具與木屑使用同一套暖木色票。
##
## 控制契約（給整合者）：
##  * new() 即可用；custom_minimum_size=(280,112)；滑鼠穿透；最近鄰取樣；clip_contents。
##  * 邏輯畫布 280×112。實際尺寸較大時以「整數倍」放大並置中，多出的邊以牆色補滿，
##    所以任何尺寸都不會有半像素。小於 280×112 時裁切，不縮小。
##  * var reduced_motion:=false。進樹時：false → 播放一次（約 2.6 秒）後停在最後的姿勢；
##    true → 直接靜態最後姿勢，不跑 _process。進樹後才設 true 會立刻跳到最後姿勢。
##  * signal finished：只在「動畫播完」那一刻發出一次；減少動態模式不發（本來就已是最後姿勢）。
##  * replay()：重播一次（減少動態模式下只是重畫最後姿勢）。show_final_pose()：立刻跳到最後姿勢。
##  * is_playing() / is_finished() / progress()（0..1）/ advance(seconds)（測試用，確定性步進）。
##  * 最後姿勢＝播放終點，兩種模式畫面完全一致。

signal finished
signal board_placed

const CharacterArt=preload("res://scripts/character_sprite_art.gd")
const KeepsakeArt=preload("res://scripts/resident_keepsake_art.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const BENCH=preload("res://assets/ui-life/wood-workbench-wide.png")

const VIEW:=Vector2i(280,112)
const DURATION:=2.6
const KIND:="keepsake_aru"

const ARU_FOOT:=Vector2(90,100)
const BENCH_TOP:=78          # y of the bench's top face
const BOARD_X0:=104          # board left edge when it is lowered onto the bench
const BOARD_SLIDE:=42        # px the board slides to the right
const BOARD_Y:=49            # top of the 32px picture when resting on the bench
const CARRY_LIFT:=12
const T_HOLD:=0.45
const T_LOWER:=0.80
const T_SLIDE_END:=1.75
const T_SETTLE_END:=1.95
const T_SPARK_END:=2.35
const GRAVITY:=90.0
const GRAIN_LIFE_TOP:=BENCH_TOP-1

const WALL:=Color("4a3524")
const WALL_LIGHT:=Color("5a4230")
const WALL_SEAM:=Color("33231a")
const FLOOR:=Color("7a5a35")
const FLOOR_SEAM:=Color("5a3d24")
const OUTLINE:=Color("3e2a1a")
const WOOD_DARK:=Color("5a3d24")
const WOOD:=Color("8a6a3e")
const WOOD_LIGHT:=Color("c79a5e")
const POLE:=Color("6b4a2f")
const GRAINS:=[Color("f0d8a8"),Color("dcbc84"),Color("e0b880"),Color("c79a5e")]
const GLINT:=Color("fff6d0")
const GLINT_SOFT:=Color("f6e2a8")

const SAW:=[
	"HHHH.bbbbbbbbbbbbbbbbbbbbb",
	"HhhHbbbbbbbbbbbbbbbbbbbb..",
	"HhhHbbbbbbbbbbbbbbbbbb....",
	"HHHH.bbbbbbbbbbbbbb.......",
	".....gGgGgGgGgGgGg........"
]
const SAW_COLORS:={"H":Color("3e2a1a"),"h":Color("8a6a3e"),"b":Color("a8a8b4"),"g":Color("6e6e78"),"G":Color("4a4a52")}

var reduced_motion:=false:
	set(value):
		reduced_motion=value
		if value and is_node_ready():show_final_pose()

var _t:=0.0
var _playing:=false
var _chars:CharacterArt
var _grains:Array=[]    # [spawn, ox, oy, vx, vy, colour index]

func _init() -> void:
	custom_minimum_size=Vector2(VIEW)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	focus_mode=Control.FOCUS_NONE
	clip_contents=true
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_build_grains()

func _ready() -> void:
	_chars=CharacterArt.new()
	if not _chars.setup():_chars=null
	if reduced_motion:
		show_final_pose()
	else:
		replay()

# ------------------------------------------------------------------ control --

## Restart the single play (reduced motion: just the static final pose).
func replay() -> void:
	if reduced_motion:
		show_final_pose()
		return
	_t=0.0
	_playing=true
	set_process(true)
	queue_redraw()

## Jump to the final pose without emitting `finished`.
func show_final_pose() -> void:
	_t=DURATION
	_playing=false
	set_process(false)
	queue_redraw()

func is_playing() -> bool:
	return _playing

func is_finished() -> bool:
	return _t>=DURATION

func progress() -> float:
	return clampf(_t/DURATION,0.0,1.0)

## Deterministic stepping (automation and _process share this path).
func advance(seconds:float) -> void:
	if not _playing:return
	var before:=_t
	_t=minf(DURATION,_t+maxf(0.0,seconds))
	if before<T_LOWER and _t>=T_LOWER:board_placed.emit()
	if _t>=DURATION:
		_playing=false
		set_process(false)
		finished.emit()
	queue_redraw()

func _process(delta:float) -> void:
	advance(delta)

# ----------------------------------------------------------------- timeline --

func _board_x(t:float) -> int:
	if t<=T_LOWER:return BOARD_X0
	var u:=clampf((t-T_LOWER)/(T_SLIDE_END-T_LOWER),0.0,1.0)
	return BOARD_X0+int(round(float(BOARD_SLIDE)*(1.0-pow(1.0-u,3.0))))

## Pixels the board is held above the bench (steps of 4 while lowering, 1 px bounce on stop).
func _board_lift(t:float) -> int:
	if t<T_HOLD:return CARRY_LIFT
	if t<T_LOWER:
		var u:=(t-T_HOLD)/(T_LOWER-T_HOLD)
		return int(round(float(CARRY_LIFT)*(1.0-u*u)/4.0))*4
	if t>=T_SLIDE_END and t<T_SLIDE_END+0.1:return 1
	return 0

func _lean(t:float) -> float:
	if t<T_SLIDE_END:return 2.0
	if t<T_SETTLE_END:return 1.0
	return 0.0

func _build_grains() -> void:
	_grains.clear()
	# A little puff where the board touches the bench.
	for i in 5:
		_grains.append([T_LOWER,float(BOARD_X0+3+i*3),float(GRAIN_LIFE_TOP),float(-16+i*9),float(-26-(i%2)*10),i%4])
	# A few shavings dropped behind the sliding board.
	for i in 5:
		var spawn:=T_LOWER+0.1+float(i)*0.17
		_grains.append([spawn,float(_board_x(spawn)+2),float(GRAIN_LIFE_TOP),float(-8-(i%3)*5),float(-14-(i%2)*8),(i+1)%4])

# --------------------------------------------------------------------- draw --

func _r(x:float,y:float,w:float,h:float,c:Color) -> void:
	draw_rect(Rect2(x,y,w,h),c)

func _boxed(x:float,y:float,w:float,h:float,fill:Color,edge:Color) -> void:
	_r(x,y,w,h,edge)
	_r(x+1,y+1,w-2,h-2,fill)

func _draw() -> void:
	_r(0,0,size.x,size.y,WALL)
	var zoom:=maxi(1,mini(int(size.x)/VIEW.x,int(size.y)/VIEW.y))
	var origin:=Vector2(maxi(0,(int(size.x)-VIEW.x*zoom)/2),maxi(0,(int(size.y)-VIEW.y*zoom)/2))
	draw_set_transform(origin,0.0,Vector2(zoom,zoom))
	_draw_room()
	_draw_bench()
	_draw_bench_items()
	_draw_grains()
	_draw_aru()
	_draw_board()
	_draw_glint()
	_draw_floor_shavings()
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _draw_room() -> void:
	# Wall planks with seams and a lit top edge each.
	for x in range(0,VIEW.x,20):
		_r(x,0,20,88,WALL)
		_r(x,0,1,88,WALL_SEAM)
		_r(x+1,0,1,88,WALL_LIGHT)
	# Tool rail with a handsaw and a mallet hung on pegs.
	_r(8,12,88,2,WOOD_DARK)
	_r(8,12,88,1,WOOD)
	_pattern(18,16,SAW,SAW_COLORS)
	_px(22,14,OUTLINE)
	_r(204,12,40,2,WOOD_DARK)
	_r(204,12,40,1,WOOD)
	_boxed(212,18,12,7,WOOD,OUTLINE)
	_r(213,19,10,1,WOOD_LIGHT)
	_r(217,25,3,16,POLE)
	_r(218,25,1,16,WOOD_LIGHT)
	_px(218,14,OUTLINE)
	# Floor.
	_r(0,88,VIEW.x,VIEW.y-88,FLOOR)
	_r(0,88,VIEW.x,1,FLOOR_SEAM)
	_r(0,89,VIEW.x,1,WOOD)
	_r(0,100,VIEW.x,1,FLOOR_SEAM)
	_r(0,108,VIEW.x,1,FLOOR_SEAM)
	for x in [30,96,170,236]:_r(x,94,1,6,FLOOR_SEAM)
	for x in [10,64,128,204,258]:_r(x,101,1,7,FLOOR_SEAM)

func _draw_bench() -> void:
	draw_texture_rect(BENCH,Rect2(99,50,128,64),false)

func _draw_bench_items() -> void:
	var wood:=ItemArt.icon("wood")
	var plank:=ItemArt.icon("plank")
	if plank!=null:draw_texture(plank,Vector2(178,BOARD_Y-1))
	if wood!=null:draw_texture(wood,Vector2(200,BOARD_Y-1))

func _draw_aru() -> void:
	if _chars!=null:
		_chars.draw_person(self,ARU_FOOT,Color.WHITE,"aru",Vector2i.RIGHT,0.0,false,true,false,false,_lean(_t))
	else:
		# Plain silhouette if the character atlas is missing.
		_r(ARU_FOOT.x-8,ARU_FOOT.y-36,16,36,WOOD_DARK)
		_r(ARU_FOOT.x-6,ARU_FOOT.y-44,12,10,WOOD_LIGHT)

func _board_rect_pos() -> Vector2:
	return Vector2(_board_x(_t),BOARD_Y-_board_lift(_t))

func _draw_board() -> void:
	var board:=KeepsakeArt.piece(KIND)
	if board!=null:
		draw_texture(board,_board_rect_pos())

func _grain_pos(g:Array,t:float) -> Vector2:
	var age:=maxf(0.0,t-float(g[0]))
	var oy:float=g[2]
	var vy:float=g[4]
	var land:=(-vy+sqrt(vy*vy-4.0*(GRAVITY*0.5)*(oy-float(GRAIN_LIFE_TOP))))/GRAVITY
	age=minf(age,land)
	return Vector2(floorf(float(g[1])+float(g[3])*age),floorf(oy+vy*age+GRAVITY*0.5*age*age))

func _draw_grains() -> void:
	for g:Array in _grains:
		if _t<float(g[0]):continue
		var p:=_grain_pos(g,_t)
		_px(p.x,minf(p.y,float(GRAIN_LIFE_TOP)),GRAINS[int(g[5])])

## A tiny four-point glint on the knot, two sizes, only while the board has just settled.
func _draw_glint() -> void:
	if _t<T_SETTLE_END or _t>=T_SPARK_END:return
	var at:=Vector2(BOARD_X0+BOARD_SLIDE+22,BOARD_Y+14)
	var big:=_t>=T_SETTLE_END+0.15 and _t<T_SPARK_END-0.1
	_px(at.x,at.y,GLINT)
	_px(at.x-1,at.y,GLINT_SOFT);_px(at.x+1,at.y,GLINT_SOFT)
	_px(at.x,at.y-1,GLINT_SOFT);_px(at.x,at.y+1,GLINT_SOFT)
	if big:
		_px(at.x-2,at.y,GLINT);_px(at.x+2,at.y,GLINT)
		_px(at.x,at.y-2,GLINT);_px(at.x,at.y+2,GLINT)

## Resting shavings by the legs and under the bench (same in every pose).
func _draw_floor_shavings() -> void:
	for p:Array in [[84,103,0],[87,104,1],[90,103,2],[78,105,3],[116,106,1],[120,105,0]]:
		_px(p[0],p[1],GRAINS[p[2]])

func _px(x:float,y:float,c:Color) -> void:
	draw_rect(Rect2(x,y,1,1),c)

func _pattern(x:int,y:int,rows:Array,colors:Dictionary) -> void:
	for j in rows.size():
		var row:String=rows[j]
		for i in row.length():
			var key:String=row[i]
			if colors.has(key):_px(x+i,y+j,colors[key])
