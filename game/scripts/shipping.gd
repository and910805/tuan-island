extends RefCounted

const CELL := Vector2i(42, 31)
const NO_CELL := Vector2i(-1, -1)
const CANDIDATES := [CELL, Vector2i(41, 31), Vector2i(42, 30)]
const MAX_LINES := 16
const MAX_QUANTITY := 1000000
const MAX_COINS := 1000000000
const MAX_BYTES := 1024
const MATERIAL_PRICES := {"wood": 2, "stone": 2, "fiber": 1, "resin": 4}

static func cell_for(snapshot: Dictionary) -> Vector2i:
	for cell: Vector2i in CANDIDATES:
		var key := "%d,%d" % [cell.x, cell.y]
		var occupied := false
		for field in ["objects", "ground", "roofs", "crops", "forest"]:
			if snapshot.get(field, {}).has(key):
				occupied = true
				break
		if not occupied:
			return cell
	return NO_CELL

static func prices(crops: Dictionary, fish: Dictionary, other: Dictionary) -> Dictionary:
	var result := MATERIAL_PRICES.duplicate()
	for item in crops:
		result[item] = crops[item].price
	for item in fish:
		result[item] = fish[item].price
	result.merge(other)
	return result

static func integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and floor(value) == value and value >= minimum and value <= maximum

static func quote(lines: Variant, inventory: Dictionary, sale_prices: Dictionary) -> Dictionary:
	if not lines is Array or lines.is_empty() or lines.size() > MAX_LINES:
		return {"ok": false, "message": "請選擇要出貨的物品。"}
	var seen := {}
	var total := 0
	for line in lines:
		if not line is Array or line.size() != 2 or not line[0] is String or not integer_in(line[1], 1, MAX_QUANTITY):
			return {"ok": false, "message": "出貨明細無效。"}
		var item: String = line[0]
		var count := int(line[1])
		if seen.has(item) or not integer_in(sale_prices.get(item), 1, MAX_COINS):
			return {"ok": false, "message": "出貨項目重複或無法出售。"}
		if int(inventory.get(item, 0)) < count:
			return {"ok": false, "message": "持有數量已變更，請重新確認。"}
		seen[item] = count
		total += count * int(sale_prices[item])
		if total > MAX_COINS:
			return {"ok": false, "message": "這批出貨金額超出上限。"}
	return {"ok": true, "total": total, "quantities": seen}

static func verify(extra: String, inventory: Dictionary, sale_prices: Dictionary, coins: int) -> Dictionary:
	if extra.to_utf8_buffer().size() > MAX_BYTES:
		return {"ok": false, "message": "出貨明細過長。"}
	var parser := JSON.new()
	if parser.parse(extra) != OK or not parser.data is Array or parser.data.size() != 2 or not integer_in(parser.data[1], 1, MAX_COINS):
		return {"ok": false, "message": "出貨報價無效。"}
	var result := quote(parser.data[0], inventory, sale_prices)
	if not result.ok:
		return result
	if result.total != int(parser.data[1]):
		return {"ok": false, "message": "預覽金額已變更，請重新確認。"}
	if coins > MAX_COINS - result.total:
		return {"ok": false, "message": "鈴幣錢包已達上限。"}
	return result
