extends RefCounted

## "cycles"：再生作物的收成次數。"regrow"：首熟之後每次再長出來要的秒數——規劃書第 09 章
## 「首熟後每 2 天一次」，換成這種作物自己的秒數（time ÷ 規劃書成長天數 × 2）。
const CROPS := {
	"radish": {"name": "奶白蘿蔔", "time": 90.0, "price": 24, "seed_price": 12, "yield": 1},
	"lettuce": {"name": "圓葉萵苣", "time": 75.0, "price": 28, "seed_price": 14, "yield": 1},
	"wheat": {"name": "星點小麥", "time": 120.0, "price": 19, "seed_price": 18, "yield": 2},
	"carrot":{"name":"糖心胡蘿蔔","time":105.0,"price":42,"seed_price":20,"yield":1},
	"potato":{"name":"小馬鈴薯","time":150.0,"price":30,"seed_price":25,"yield":2},
	"tomato":{"name":"太陽番茄","time":120.0,"price":28,"seed_price":55,"yield":2,"cycles":3,"regrow":60.0},
	"pumpkin":{"name":"琥珀南瓜","time":270.0,"price":150,"seed_price":70,"yield":1},
	"cauliflower":{"name":"雲朵花椰菜","time":210.0,"price":95,"seed_price":45,"yield":1},
	"sweet_corn":{"name":"甜玉米","time":210.0,"price":35,"seed_price":60,"yield":2},
	"strawberry":{"name":"蜜香草莓","time":210.0,"price":36,"seed_price":70,"yield":2,"cycles":3,"regrow":84.0},
	"cucumber":{"name":"波點黃瓜","time":120.0,"price":22,"seed_price":40,"yield":2,"cycles":3,"regrow":80.0},
	"cabbage":{"name":"雪白高麗菜","time":210.0,"price":94,"seed_price":44,"yield":1},
	"sugar_beet":{"name":"霜糖甜菜","time":165.0,"price":66,"seed_price":30,"yield":1},
	"star_mushroom":{"name":"星夜菇","time":165.0,"price":36,"seed_price":36,"yield":2},
	"sweet_potato":{"name":"栗香地瓜","time":165.0,"price":34,"seed_price":32,"yield":2},
	"eggplant":{"name":"紫絨茄子","time":165.0,"price":27,"seed_price":48,"yield":2,"cycles":3,"regrow":82.5},
	"rice":{"name":"月牙稻米","time":165.0,"price":29,"seed_price":28,"yield":2},
	"watermelon":{"name":"小圓西瓜","time":270.0,"price":135,"seed_price":65,"yield":1},
	"ginger":{"name":"暖泉薑","time":210.0,"price":48,"seed_price":45,"yield":2},
	"cotton":{"name":"棉球花","time":210.0,"price":42,"seed_price":40,"yield":2},
	"mist_tea":{"name":"霧竹茶","time":210.0,"price":38,"seed_price":65,"yield":2,"cycles":3,"regrow":84.0},
	# Chapter 3 Tianwei flowers (= FlowerNursery.CROPS). seed_price/yield/price are
	# the source-plan §09 values; time is a provisional current-clock seconds value.
	# Seasons are in World.CROP_SEASONS (bluebell, orange_blossom); the Tianwei
	# nursery beds grow all three year-round (World.nursery_grows_year_round).
	"bluebell":{"name":"鈴蘭藍花","time":150.0,"price":28,"seed_price":28,"yield":2},
	"orange_blossom":{"name":"蜜橙花","time":150.0,"price":28,"seed_price":28,"yield":2},
	"chime_herb":{"name":"風鈴香草","time":120.0,"price":48,"seed_price":24,"yield":1}
}
