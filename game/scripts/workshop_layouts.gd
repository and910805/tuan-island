extends RefCounted
## Read-only examples backed by the same blueprint schema/build costs as play.
const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const TITLES:=["河岸小田","木材變木板","木炭回家"]
const TOPICS:={"water_pump":0,"water_pipe":0,"water_tank":0,"sprinkler":0,"forester":1,"sawmill":1,"charcoal_kiln":2,"conveyor":2,"private_chest":2}

static func piece(kind:String,x:int,y:int,dir:int=-1,item:String="")->Dictionary:
	var result:={"kind":kind,"x":x,"y":y}
	if dir>=0:result.settings={"dir":dir,"filter":item}
	return result

static func lesson(index:int)->Dictionary:
	if index<0 or index>=TITLES.size():return {}
	var pieces:Array=[]
	var markers:Array=[]
	var steps:Array[String]=[]
	var startup:Dictionary={}
	var note:=""
	var height:=5
	match index:
		0:
			height=3
			pieces=[piece("water_pump",4,1),piece("water_pipe",3,1),piece("water_tank",2,1),piece("sprinkler",1,1)]
			markers=[{"x":0,"y":1,"icon":"radish_seed","text":"自己的農田"}]
			startup={"radish_seed":1}
			steps=["選河岸陸地。泵離河水兩格內，設備與水管都用自己的。","照圖接泵、管、水桶與灑水器；管線以四向相鄰連通。","靠近互動，分別啟用河水泵與灑水器。泵每%d秒向水桶供水。"%World.INDUSTRY.INTERVAL,"在灑水器相鄰格鋤地播種。看作物變濕，桶開始蓄水；不必另按澆水。"]
			note="種子袋標示農田，不是建築。本圖用工作台套件；建造目錄若顯示銅錠款，會依每日灑水規格運作。實際放置以目錄配方為準。"
		1:
			pieces=[piece("forester",2,2),piece("conveyor",3,2,1,"wood"),piece("sawmill",4,2)]
			for cell in [Vector2i(2,0),Vector2i(0,2),Vector2i(2,4)]:markers.append({"x":cell.x,"y":cell.y,"icon":"sapling","text":"留空給林務種樹"})
			startup={"sapling":3,"charcoal":4}
			steps=["清出標示的三格。林務站只管理自己種的樹，天然樹石要先手動清理。","補入樹苗與木炭後啟用。每%d秒巡查一格，樹約%d秒長成，採伐後原地補種。"%[World.FORESTRY.INTERVAL,World.TREE_TIME],"把輸送帶設為向右、篩選木材，再啟用。鋸木台要開『自動加工』。","木板留在鋸木台領取。纖維與樹脂留在林務站，也記得收；滿庫會停工。"]
			note="右方作業格由鋸木台占用，其餘三格仍可工作。帶一次製作兩段，這裡只放一段。"
		2:
			pieces=[piece("forester",2,2),piece("sawmill",4,2),piece("charcoal_kiln",2,0),piece("private_chest",4,4),piece("conveyor",2,1,0,"wood"),piece("conveyor",3,2,1,"wood"),piece("conveyor",1,0,3,"charcoal"),piece("conveyor",0,0,2,"charcoal"),piece("conveyor",0,1,1,"charcoal"),piece("conveyor",1,1,2,"charcoal"),piece("conveyor",1,2,1,"charcoal"),piece("conveyor",4,3,2,"plank")]
			for cell in [Vector2i(0,2),Vector2i(2,4)]:markers.append({"x":cell.x,"y":cell.y,"icon":"sapling","text":"保留的林務作業格"})
			startup={"sapling":2,"charcoal":3}
			steps=["先保留左方與下方兩個種樹格；北方與右方改放炭窯、鋸木台。補樹苗與起動木炭。","兩條木材帶分別向上、向右送木。鋸木台與炭窯都啟用自動加工。","外圈五段帶篩選木炭，依圖轉彎送回林務站；逐段設定後啟用。","木板帶向下送入私人箱。纖維、樹脂仍要定期領；燃料回送不等於永遠不用照料。"]
			note="箭頭表示各段送出方向。選定設備可在下方開建造目錄；全部完成後仍需手動設定、供料及啟用。"
	var design:={"version":Design.VERSION,"name":TITLES[index],"width":5,"height":height,"pieces":pieces}
	return {"design":design,"markers":markers,"steps":steps,"startup":startup,"note":note}

static func cost(index:int)->Dictionary:
	var data:=lesson(index)
	if data.is_empty():return {}
	var recipes:Dictionary=World.BUILD.duplicate(true)
	# The first lesson is the earned early-workbench route. Use the canonical
	# alternative, not the later ingot/daily recipe or an invented fixed price.
	if index==0:recipes.sprinkler=World.build_recipe("sprinkler",{"sprinkler_kit":1})
	var result:=Design.base_cost(data.design,recipes,World.NAMES)
	return result.get("cost",{}) if result.get("ok",false) else {}
