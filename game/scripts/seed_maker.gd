extends RefCounted
## Manual processing recipes. Replanting the output cannot return more produce
## than was consumed, even after every harvest of a regrowing crop.

const PROCESS_SECONDS := 60.0
const NURSERY_CROPS := ["bluebell","orange_blossom","chime_herb"]

static func recipes(crops: Dictionary, include_retired:=false) -> Dictionary:
	var result := {}
	for kind: String in crops:
		if not include_retired and kind in NURSERY_CROPS:continue
		var crop: Dictionary = crops[kind]
		var lifetime_yield := int(crop.yield) * int(crop.get("cycles", 1))
		result[kind + "_seed"] = {
			"station": "seed_maker",
			"ingredients": {kind: lifetime_yield, "charcoal": 1},
			"time": PROCESS_SECONDS,
			"yield": 1,
		}
	return result

## Save validation uses the same recipes without the station metadata.
static func queue_recipes() -> Dictionary:
	var catalog := recipes(preload("res://scripts/crop_catalog.gd").CROPS,true)
	for recipe: Dictionary in catalog.values():
		recipe.erase("station")
	return catalog
