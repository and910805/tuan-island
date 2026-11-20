extends RefCounted
## A greenhouse interior is one connected glass ceiling with no exposed edge.

const XINGHE_ROOF:="xinghe_greenhouse_roof"
const LEGACY_ROOF:="greenhouse_roof"
const DIRS:=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]

static func is_glass(kind:String)->bool:
	return kind==LEGACY_ROOF or kind==XINGHE_ROOF

static func covered(snapshot:Dictionary,key:String,memo:Variant=null)->bool:
	var roofs:Dictionary=snapshot.get("roofs",{})
	var kind:String=roofs.get(key,{}).get("type","")
	if kind==LEGACY_ROOF:return true
	if kind!=XINGHE_ROOF:return false
	if memo is Dictionary and memo.has(key):return bool(memo[key])
	var objects:Dictionary=snapshot.get("objects",{})
	if objects.get(key,{}).get("type","") in ["wall","window","door"]:return false
	var coords:=key.split(",")
	if coords.size()!=2 or not coords[0].is_valid_int() or not coords[1].is_valid_int():return false
	var queue:Array[Vector2i]=[Vector2i(int(coords[0]),int(coords[1]))]
	var visited:Dictionary={key:true}
	var head:=0
	var sealed:=true
	while head<queue.size():
		var tile:=queue[head]
		head+=1
		for direction:Vector2i in DIRS:
			var neighbor:=tile+direction
			var next:="%d,%d"%[neighbor.x,neighbor.y]
			if visited.has(next):continue
			var obj:Dictionary=objects.get(next,{})
			match obj.get("type",""):
				"wall","window":continue
				"door":
					if obj.get("open",false):sealed=false
					continue
			if not is_glass(roofs.get(next,{}).get("type","")):
				sealed=false
				continue
			visited[next]=true
			queue.append(neighbor)
	if memo is Dictionary:
		for tile:String in visited:memo[tile]=sealed
	return sealed
