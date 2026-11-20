extends RefCounted
## Server rules for building, removing and toggling edge walls / doors / windows (C02-C04).
## Pure rules over a World instance: this file never preloads world.gd (World preloads it), so it
## only calls members that already exist on World and on the helpers below. It does not run the
## transaction, undo capture, roof reconcile or save; World.act owns all of that.
##
## Wire contract (World.act wires it, this file defines it):
##   "build_edge"  extra "<type>|<side>"   type in TYPES, side one ASCII digit 0..3 (N,E,S,W of cell p)
##   "remove_edge" extra "<side>"          targeted removal, owner only, exact refund
##   "toggle_edge" extra "<side>"          open/close an existing edge_door, any ordinary player in reach
## The side is read from cell `p` (EdgeGrid.SIDE_*), so (p,S) and (p+down,N) name the same edge.
##
## State writes (only after every check passed, so a reject leaves the world untouched):
##   state.edges[id] = {"type","owner"} (+ "open":false for a door), actor inventory, actor builds.
##   remove: erases state.edges[id] and refunds the OWNER's inventory (the owner is the actor).
##   toggle: flips state.edges[id].open.
##
## Existing World members relied on (all present in world.gd today):
##   World.SIZE, World.NAMES, World.PUBLIC_BUILD_DENIED, world.state (ITEM_CAP mirrors the literal
##   1000000000 used by World's refund/build caps and BLUEPRINT_ITEM_CAP),
##   world._region (read, like plot_permissions.gd does), world.is_land(), world.water(),
##   world.protected(), world.allows_public_build(), world.regional_tokens(), world.give() (static),
##   World.essential_cell_reason() (static, same "essential site" list as pavilion_site_problem),
##   World.ok()/fail() (static), PLOT_PERMISSIONS.can_place/kitchen_locked, INDUSTRY.is_mill_front /
##   is_mill_entrance / FOOT_BOX, EDGE_FOOT_SWEEP.can_stand, EdgeGrid.

const EdgeGrid := preload("res://scripts/edge_grid.gd")
const EDGE_FOOT_SWEEP := preload("res://scripts/edge_foot_sweep.gd")
const INDUSTRY := preload("res://scripts/industry.gd")
const PLOT_PERMISSIONS := preload("res://scripts/plot_permissions.gd")
const PUBLIC_KITCHEN := preload("res://scripts/public_kitchen.gd")
const WALL_FIXTURES := preload("res://scripts/wall_fixtures.gd")

const BUILD := "build_edge"
const REMOVE := "remove_edge"
const TOGGLE := "toggle_edge"
const ACTIONS := [BUILD, REMOVE, TOGGLE]
const TYPES := ["edge_wall", "edge_door", "edge_window"]
## Plan prices. Order and amounts are the contract; refunds return exactly these.
const COSTS := {
	"edge_wall": {"wood": 3},
	"edge_door": {"wood": 6, "fiber": 2},
	"edge_window": {"wood": 4, "glass": 1},
}
const NAMES := {"edge_wall": "木牆", "edge_door": "木門", "edge_window": "木窗"}
## Same reach as every ordinary build (World._apply: distance > 3.2 from the tile centre fails).
const REACH := 3.2
const ITEM_CAP := 1000000000

const MSG_BAD := "無法辨識這道牆的位置或種類"
const MSG_REACH := "請靠近這道牆再操作。"
const MSG_RIM := "牆的兩側都要在地圖內。"
const MSG_LAND := "牆的兩側都需要是可施工的陸地。"
const MSG_SITE := "這裡是公共通道或重要地點，請換個位置。"
const MSG_MILL := "磨坊入口前的通道要保持暢通，不能在這裡蓋牆。"
const MSG_TAKEN := "這裡已經有牆、門或窗了。"
const MSG_PERSON := "有人站在這道牆的位置，請先讓開。"
const MSG_NONE := "這裡沒有牆、門或窗。"
const MSG_NOT_DOOR := "這裡不是門。"
const MSG_OWNER := "只能拆除自己蓋的牆。"
const MSG_FULL := "背包中的物品已達上限"
const MSG_BUILDS := "施工紀錄已達上限，這次沒有施工"

## Strict parse. {} for anything malformed, otherwise
##   {id: canonical edge key, kind: build type ("" for remove/toggle), cells: [Vector2i, Vector2i]
##    (the two cells the edge separates, N->S or W->E, EdgeGrid.cells_of order; one may be off-map on
##    the rim), side: canonical EdgeGrid.SIDE_N or SIDE_W, midpoint: Vector2 world position}.
## `p` must be an in-map cell; extra must be exactly the documented text (no spaces, signs, zeros,
## non-ASCII digits or extra fields).
static func decode(action: String, p: Vector2i, extra: String, bounds: Vector2i) -> Dictionary:
	if bounds.x < 1 or bounds.y < 1 or not EdgeGrid.in_bounds(p, bounds):return {}
	var kind := ""
	var side_text := extra
	if action == BUILD:
		var parts := extra.split("|", true)
		if parts.size() != 2 or parts[0] not in TYPES:return {}
		kind = parts[0]
		side_text = parts[1]
	elif action != REMOVE and action != TOGGLE:
		return {}
	if side_text.length() != 1:return {}
	var code := side_text.unicode_at(0)
	if code < 48 or code > 51:return {}
	var side := code - 48
	var canon := EdgeGrid.canonical(p, side, bounds)
	var id := EdgeGrid.key(p, side, bounds)
	if canon.is_empty() or id == "":return {}
	var owner_cell: Vector2i = canon.cell
	var midpoint := Vector2(owner_cell.x + 0.5, owner_cell.y) if canon.side == EdgeGrid.SIDE_N else Vector2(owner_cell.x, owner_cell.y + 0.5)
	return {"id": id, "kind": kind, "cells": EdgeGrid.cells_of(id, bounds), "side": canon.side, "midpoint": midpoint}

static func apply(world, actor: String, action: String, p: Vector2i, extra: String) -> Dictionary:
	var bounds: Vector2i = world.SIZE
	var edge := decode(action, p, extra, bounds)
	if edge.is_empty():return world.fail(MSG_BAD)
	if not world.state.players.has(actor):return world.fail(MSG_BAD)
	var edges: Variant = world.state.get("edges")
	if not edges is Dictionary:return world.fail(MSG_BAD)
	var person: Dictionary = world.state.players[actor]
	var midpoint: Vector2 = edge.midpoint
	if Vector2(float(person.x), float(person.y)).distance_to(midpoint) > REACH:return world.fail(MSG_REACH)
	if action == BUILD:return _build(world, actor, person, edges, edge, bounds)
	if action == REMOVE:return _remove(world, actor, edges, edge)
	return _toggle(world, actor, edges, edge, bounds)

# ------------------------------------------------------------------ build --

static func stage_blueprint(world, actor:String, edge:Dictionary) -> String:
	if edge.is_empty():return MSG_BAD
	var result:=_build(world,actor,world.state.players[actor],world.state.edges,edge,world.SIZE,true)
	return "" if result.ok else str(result.message)

static func _build(world, actor: String, person: Dictionary, edges: Dictionary, edge: Dictionary, bounds: Vector2i, blueprint:=false) -> Dictionary:
	var id: String = edge.id
	var kind: String = edge.kind
	if edges.has(id):return world.fail(MSG_TAKEN)
	var cells: Array = edge.cells
	for cell: Vector2i in cells:
		if not EdgeGrid.in_bounds(cell, bounds):return world.fail(MSG_RIM)
	for cell: Vector2i in cells:
		if not world.is_land(cell) or world.water(cell):return world.fail(MSG_LAND)
	# Same first gate as World._build_piece, so the public plot message wins over site messages.
	for cell: Vector2i in cells:
		if not world.allows_public_build(actor, cell):return world.fail(world.PUBLIC_BUILD_DENIED)
	for cell: Vector2i in cells:
		if world.protected(cell) or PLOT_PERMISSIONS.kitchen_locked(world, cell):return world.fail(MSG_SITE)
		if not str(world.essential_cell_reason(world.state, world._region, cell)).is_empty():return world.fail(MSG_SITE)
		if _mill_route(world, cell):return world.fail(MSG_MILL)
		var permission: Dictionary = PLOT_PERMISSIONS.can_place(world, actor, cell, kind, blueprint)
		if not permission.ok:return world.fail(permission.message)
	# Placed closed (walls and windows always block, a new door starts shut).
	if _someone_straddles(world, id, _row(kind, actor, false), bounds):return world.fail(MSG_PERSON)
	var inventory: Dictionary = person.inventory
	var recipe: Dictionary = COSTS[kind]
	if int(person.get("builds", 0)) + 1 > ITEM_CAP:return world.fail(MSG_BUILDS)
	if not blueprint:
		for item: String in recipe:
			if int(inventory.get(item, 0)) < int(recipe[item]):
				return world.fail("材料不足，需要%s %d" % [world.NAMES.get(item, item), int(recipe[item])])
		for item: String in recipe:world.give(inventory, item, -int(recipe[item]))
	edges[id] = _row(kind, actor, false)
	person.builds = int(person.get("builds", 0)) + 1
	return world.ok("放好了%s，家園又多了一點你的心意" % NAMES[kind])

# ----------------------------------------------------------------- remove --

static func _remove(world, actor: String, edges: Dictionary, edge: Dictionary) -> Dictionary:
	var id: String = edge.id
	var row: Variant = edges.get(id)
	if not row is Dictionary or str(row.get("type", "")) not in TYPES:return world.fail(MSG_NONE)
	var owner_token: Variant = row.get("owner")
	if typeof(owner_token) != TYPE_STRING or owner_token != actor:return world.fail(MSG_OWNER)
	var cells: Array = edge.cells
	for cell: Vector2i in cells:
		if PLOT_PERMISSIONS.kitchen_locked(world, cell):return world.fail(PUBLIC_KITCHEN.MSG_LOCKED)
	# A mounted prop (curtain, board, frame...) must not lose its only support.
	var stranded: String = WALL_FIXTURES.removal_problem(world.state.get("objects", {}), edges, id)
	if not stranded.is_empty():return world.fail(stranded)
	var refund_inventory: Dictionary = world.state.players[actor].inventory
	var recipe: Dictionary = COSTS[str(row.type)]
	for item: String in recipe:
		if int(refund_inventory.get(item, 0)) + int(recipe[item]) > ITEM_CAP:return world.fail(MSG_FULL)
	for item: String in recipe:world.give(refund_inventory, item, int(recipe[item]))
	edges.erase(id)
	return world.ok("已拆除，建造材料完整退還")

# ----------------------------------------------------------------- toggle --

static func _toggle(world, actor: String, edges: Dictionary, edge: Dictionary, bounds: Vector2i) -> Dictionary:
	var id: String = edge.id
	var row: Variant = edges.get(id)
	if not row is Dictionary or str(row.get("type", "")) not in TYPES:return world.fail(MSG_NONE)
	if row.type != "edge_door":return world.fail(MSG_NOT_DOOR)
	# Legacy `door` toggle has no owner rule: any player who can interact may use any door.
	var opened: Variant = row.get("open")
	var is_open: bool = opened is bool and opened
	if is_open:
		# Closing: nobody may be caught on the line (same fail-closed singleton test the mover uses).
		var cells: Array = edge.cells
		for cell: Vector2i in cells:
			if EdgeGrid.in_bounds(cell, bounds) and _mill_route(world, cell):return world.fail(MSG_MILL)
		if _someone_straddles(world, id, _row("edge_door", str(row.get("owner", actor)), false), bounds):
			return world.fail("有人站在門口，等他通過再關門")
	row.open = not is_open
	return world.ok("門打開了" if row.open else "門關好了")

# ---------------------------------------------------------------- helpers --

static func _row(kind: String, owner_token: String, open: bool) -> Dictionary:
	var row := {"type": kind, "owner": owner_token}
	if kind == "edge_door":row["open"] = open
	return row

## True when `cell` is the open cell in front of a new mill entrance, or is such an entrance cell:
## an edge there would wall the mill in (World._mill_front_claim_problem guards the object side).
static func _mill_route(world, cell: Vector2i) -> bool:
	var objects: Dictionary = world.state.get("objects", {})
	if INDUSTRY.is_mill_front(objects, cell):return true
	var here: Variant = objects.get("%d,%d" % [cell.x, cell.y])
	return here is Dictionary and INDUSTRY.is_mill_entrance(here)

## True when an active player in the actor's region has a foot box straddling this one closed segment.
static func _someone_straddles(world, id: String, closed_row: Dictionary, bounds: Vector2i) -> bool:
	var single := {id: closed_row}
	for token in world.regional_tokens():
		var who: Dictionary = world.state.players.get(token, {})
		if who.is_empty():continue
		var feet := Vector2(float(who.x), float(who.y))
		if not EDGE_FOOT_SWEEP.can_stand(feet, single, bounds, INDUSTRY.FOOT_BOX):return true
	return false
