extends RefCounted
## Read-only examples backed by the same blueprint schema/build costs as play.
const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const STARTER_IRRIGATION:=3
const FIRST_HOUSE:=4
const TITLES:=["河岸小田","木材變木板","木炭回家","入門灌溉","第一間小屋"]
const TOPICS:={"water_pump":0,"water_pipe":0,"water_tank":0,"sprinkler":0,"forester":1,"sawmill":1,"charcoal_kiln":2,"conveyor":2,"private_chest":2,
	"floor":FIRST_HOUSE,"stone_floor":FIRST_HOUSE,"wall":FIRST_HOUSE,"door":FIRST_HOUSE,"window":FIRST_HOUSE,"roof":FIRST_HOUSE,"bed":FIRST_HOUSE}
const HOUSE_FLOOR:=[Vector2i(1,1),Vector2i(2,1),Vector2i(1,2),Vector2i(2,2)]
const HOUSE_DOOR:=Vector2i(1,3)
const HOUSE_BED:=Vector2i(2,1)

static func piece(kind:String,x:int,y:int,dir:int=-1,item:String="")->Dictionary:
	var result:={"kind":kind,"x":x,"y":y}
	if dir>=0:result.settings={"dir":dir,"filter":item}
	return result

## One focused action per stage. `placed` is how many of the design pieces are
## on the board, `from` how many were already there before this action (the
## preview reveals the difference one by one). `flows` are preview-only item
## paths in cell coordinates, `marks` are preview-only stage overlays.
static func stage(heading:String,lines:Array,placed:int,from:int,focus:Array,flows:Array=[],marks:Array=[])->Dictionary:
	return {"heading":heading,"lines":lines,"placed":placed,"from":from,"focus":focus,"flows":flows,"marks":marks}

static func flow(item:String,path:Array)->Dictionary:
	return {"item":item,"path":path}

static func lesson(index:int)->Dictionary:
	if index<0 or index>=TITLES.size():return {}
	var guide:Array=[]
	var pieces:Array=[]
	var markers:Array=[]
	var startup:Dictionary={}
	var note:=""
	var width:=5
	var height:=5
	match index:
		0:
			height=3
			pieces=[piece("water_pump",4,1),piece("water_pipe",3,1),piece("water_tank",2,1),piece("sprinkler",1,1)]
			markers=[{"x":0,"y":1,"icon":"radish_seed","text":"自己的農田"}]
			startup={"radish_seed":1}
			note="種子袋標示農田，不是建築。本圖用工作台套件；建造目錄若顯示銅錠款，會依每日灑水規格運作。實際放置以目錄配方為準。"
			guide=[
				stage("靠河放下河水泵",["泵要離河水兩格內。","設備與水管都用自己的。"],1,0,["water_pump"],[flow("water",[Vector2(5.0,1.5),Vector2(4.5,1.5)])]),
				stage("接上管、桶與灑水器",["管線四向相鄰就會連通。","照圖由右往左排。"],4,1,["water_pipe","water_tank","sprinkler"]),
				stage("啟用泵與灑水器",["靠近互動，分別按啟用。","泵每 %d 秒向水桶供水。"%World.INDUSTRY.INTERVAL],4,4,["water_pump","sprinkler"],[flow("water",[Vector2(5.0,1.5),Vector2(4.5,1.5),Vector2(3.5,1.5),Vector2(2.5,1.5),Vector2(1.5,1.5)])]),
				stage("在灑水器旁鋤地播種",["種在相鄰格，作物變濕就成功。","不必另按澆水。"],4,4,["sprinkler"],[flow("water",[Vector2(1.5,1.5),Vector2(0.5,1.5)])],[{"x":0,"y":1,"kind":"wet"}])
			]
		1:
			pieces=[piece("forester",2,2),piece("conveyor",3,2,1,"wood"),piece("sawmill",4,2)]
			for cell in [Vector2i(2,0),Vector2i(0,2),Vector2i(2,4)]:markers.append({"x":cell.x,"y":cell.y,"icon":"sapling","text":"留空給林務種樹"})
			startup={"sapling":3,"charcoal":4}
			note="右方作業格由鋸木台占用，其餘三格仍可工作。帶一次製作兩段，這裡只放一段。"
			guide=[
				stage("清出三格空地",["先清掉標示的三格。","天然樹石要手動清理。"],1,0,["forester"]),
				stage("補樹苗與木炭再啟用",["每 %d 秒巡查一格。"%World.FORESTRY.INTERVAL,"樹約 %d 秒長成。"%World.TREE_TIME],1,1,["forester"],[],[{"x":2,"y":0,"kind":"grow"},{"x":0,"y":2,"kind":"grow"},{"x":2,"y":4,"kind":"grow"}]),
				stage("輸送帶向右送木",["設為向右，篩選木材。","鋸木台要開自動加工。"],3,1,["conveyor","sawmill"],[flow("wood",[Vector2(2.5,2.5),Vector2(3.5,2.5),Vector2(4.5,2.5)])]),
				stage("到鋸木台領木板",["木板留在鋸木台。","纖維與樹脂在林務站，滿庫會停工。"],3,3,["sawmill"],[flow("plank",[Vector2(4.5,2.5),Vector2(4.5,3.5)])])
			]
		2:
			pieces=[piece("forester",2,2),piece("sawmill",4,2),piece("charcoal_kiln",2,0),piece("private_chest",4,4),piece("conveyor",2,1,0,"wood"),piece("conveyor",3,2,1,"wood"),piece("conveyor",1,0,3,"charcoal"),piece("conveyor",0,0,2,"charcoal"),piece("conveyor",0,1,1,"charcoal"),piece("conveyor",1,1,2,"charcoal"),piece("conveyor",1,2,1,"charcoal"),piece("conveyor",4,3,2,"plank")]
			for cell in [Vector2i(0,2),Vector2i(2,4)]:markers.append({"x":cell.x,"y":cell.y,"icon":"sapling","text":"保留的林務作業格"})
			startup={"sapling":2,"charcoal":3}
			note="箭頭表示各段送出方向。選定設備可在下方開建造目錄；全部完成後仍需手動設定、供料及啟用。"
			guide=[
				stage("留兩格種樹，其餘放設備",["左方與下方留給種樹。","北方炭窯，右方鋸木台，右下箱子。"],4,0,["forester","sawmill","charcoal_kiln","private_chest"]),
				stage("兩條木材帶送木",["一條向上送炭窯，一條向右送鋸木台。","兩台都開自動加工。"],6,4,["conveyor"],[flow("wood",[Vector2(2.5,2.5),Vector2(2.5,1.5),Vector2(2.5,0.5)]),flow("wood",[Vector2(2.5,2.5),Vector2(3.5,2.5),Vector2(4.5,2.5)])]),
				stage("木炭沿外圈送回",["五段帶都篩選木炭，依箭頭轉彎。","逐段設定後再啟用。"],11,6,["conveyor"],[flow("charcoal",[Vector2(2.5,0.5),Vector2(1.5,0.5),Vector2(0.5,0.5),Vector2(0.5,1.5),Vector2(1.5,1.5),Vector2(1.5,2.5),Vector2(2.5,2.5)])]),
				stage("木板送進私人箱",["木板帶向下接到箱子。","纖維與樹脂仍要定期領。"],12,11,["conveyor","private_chest"],[flow("plank",[Vector2(4.5,2.5),Vector2(4.5,3.5),Vector2(4.5,4.5)])])
			]
		STARTER_IRRIGATION:
			height=3
			pieces=[piece("water_tank",0,1),piece("water_pipe",1,1),piece("water_pipe",2,1),piece("sprinkler",3,1)]
			markers=[{"x":3,"y":2,"icon":"radish_seed","text":"自己的乾田"}]
			startup={"radish_seed":1}
			note="第一章需要管網送出的水。若已直接補滿灑水器，可拆除重放再接管，或先用完裡面的手動補水。"
			guide=[
				stage("排成一列",["儲水桶、兩段水管、灑水器。","設備與管線由同一人放置。"],4,0,["water_tank","water_pipe","sprinkler"]),
				stage("在灑水器正下方播種",["鋤地後播種，先保持乾燥。","留給灑水器澆。"],4,4,["sprinkler"],[],[{"x":3,"y":2,"kind":"seed"}]),
				stage("補滿水桶並啟用",["對水桶按互動，選「補滿儲水桶」。","在灑水器選「啟用」。"],4,4,["water_tank","sprinkler"],[flow("water",[Vector2(0.5,1.5),Vector2(1.5,1.5),Vector2(2.5,1.5),Vector2(3.5,1.5)])],[{"x":3,"y":2,"kind":"planted"}]),
				stage("看作物變濕",["管網送水後，作物會變濕。","第一章接著去渡口野餐。"],4,4,["sprinkler"],[flow("water",[Vector2(3.5,1.5),Vector2(3.5,2.5)])],[{"x":3,"y":2,"kind":"wet"}])
			]
		FIRST_HOUSE:
			width=4
			var roofs:Array=[]
			for floor_cell:Vector2i in HOUSE_FLOOR:
				pieces.append(piece("floor",floor_cell.x,floor_cell.y))
				roofs.append({"x":floor_cell.x,"y":floor_cell.y,"kind":"auto_roof"})
			var floor_count:=pieces.size()
			for y in 4:
				for x in 4:
					var cell:=Vector2i(x,y)
					if cell not in HOUSE_FLOOR and cell!=HOUSE_DOOR:pieces.append(piece("wall",x,y))
			var wall_count:=pieces.size()
			pieces.append(piece("door",HOUSE_DOOR.x,HOUSE_DOOR.y))
			pieces.append(piece("bed",HOUSE_BED.x,HOUSE_BED.y))
			note="範例用料包括自動加蓋的四格屋頂。門外與床邊各留空一格，從入口才走得到床。"
			var walls:=stage("沿地板的外圈蓋木牆",["木牆用「整格施工」，中間留給家具。","照圖留下一格當木門。"],wall_count,floor_count,["wall"])
			walls.reveal_interval=0.28
			guide=[
				stage("先鋪 2×2 格木地板",["找一塊空草地，四周各留一格圍牆。"],floor_count,0,["floor"]),
				walls,
				stage("木門與屋頂一起施工",["按「確認施工」，一起加蓋四格屋頂。","門外留一格走道，靠近可以開門。"],wall_count+1,wall_count,["door"],[],roofs),
				stage("進屋擺小床",["留一條路從木門走到床邊。","站在屋裡可以打開小屋結構檢查。"],pieces.size(),wall_count+1,["bed"])
			]
	var design:={"version":Design.VERSION,"name":TITLES[index],"width":width,"height":height,"pieces":pieces}
	return {"design":design,"markers":markers,"startup":startup,"note":note,"guide":guide}

static func cost(index:int)->Dictionary:
	var data:=lesson(index)
	if data.is_empty():return {}
	var recipes:Dictionary=World.BUILD.duplicate(true)
	# The first lesson is the earned early-workbench route. Use the canonical
	# alternative, not the later ingot/daily recipe or an invented fixed price.
	if index in [0,STARTER_IRRIGATION]:recipes.sprinkler=World.build_recipe("sprinkler",{"sprinkler_kit":1})
	var result:=Design.base_cost(data.design,recipes,World.NAMES)
	if not result.get("ok",false):return {}
	var total:Dictionary=result.cost
	if index==FIRST_HOUSE:
		for item:String in World.BUILD.roof:
			if item in World.NAMES:total[item]=int(total.get(item,0))+int(World.BUILD.roof[item])*HOUSE_FLOOR.size()
	return total
