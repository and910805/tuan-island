extends RefCounted
## Blueprint v2 edge pieces -> edge_construction_art.gd draw calls, shared by the layout ghost
## (blueprint_preview.gd) and the folio thumbnail (blueprint_thumbnail.gd).
##
## A v2 piece is {kind: edge_wall|edge_window|edge_door, x, y, settings: {side, open?}, style?} with
## settings.side 0 N, 1 E, 2 S, 3 W relative to the piece's cell. The art only draws N and W edges,
## so E/S are the neighbour cell's W/N: E -> (x+1, y) W, S -> (x, y+1) N.

const EdgeArt = preload("res://scripts/edge_construction_art.gd")

static func is_edge(piece: Dictionary) -> bool:
	return EdgeArt.is_kind(str(piece.get("kind", "")))

## {cell: Vector2i (blueprint-relative, canonical), side: int (SIDE_N or SIDE_W)}.
static func canonical(piece: Dictionary) -> Dictionary:
	var settings: Variant = piece.get("settings", {})
	var side := int((settings as Dictionary).get("side", 0)) if settings is Dictionary else 0
	var cell := Vector2i(int(piece.get("x", 0)), int(piece.get("y", 0)))
	match side:
		1:
			return {"cell": cell + Vector2i.RIGHT, "side": EdgeArt.SIDE_W}
		2:
			return {"cell": cell + Vector2i.DOWN, "side": EdgeArt.SIDE_N}
		3:
			return {"cell": cell, "side": EdgeArt.SIDE_W}
	return {"cell": cell, "side": EdgeArt.SIDE_N}

## Edge pieces of `pieces` with canonical cell/side, in draw order (y, then x, N before W).
static func collect(pieces: Array) -> Array:
	var rows: Array = []
	for item in pieces:
		if not (item is Dictionary) or not is_edge(item):
			continue
		var piece: Dictionary = item
		var place := canonical(piece)
		var settings: Variant = piece.get("settings", {})
		place["kind"] = str(piece.kind)
		place["open"] = bool((settings as Dictionary).get("open", false)) if settings is Dictionary else false
		place["style"] = str(piece.get("style", ""))
		rows.append(place)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.cell.y != b.cell.y:
			return a.cell.y < b.cell.y
		if a.cell.x != b.cell.x:
			return a.cell.x < b.cell.x
		return a.side < b.side)
	return rows
