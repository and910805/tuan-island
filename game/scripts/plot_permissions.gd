extends RefCounted
## T057 plot permissions: one read-only check per operation
##   place     -> can_place(world, token, p, kind, blueprint=false)
##   take      -> can_take(token, box)              (deposit/withdraw/box config)
##   harvest   -> can_harvest(world, token, plot, machine=false)
##   dismantle -> can_dismantle(world, token, p, move=false)
## Each returns {"ok":bool,"message":String}. Messages are byte-identical to the
## inline world.gd branches they mirror, so integration is a drop-in swap.
## Pure reads of a World instance (state, _region, water/protected/key,
## greenhouse_covers, _remove_layer, can_harvest_plot); never mutates anything.
##
## Scope: ownership / public-area policy ONLY. Callers keep their own existence,
## unlock, level, reach, material, occupancy, busy and contents guards, and must
## call these at the same point the inline check sits today (after the region
## allow-lists and the reach gate in World._apply).
##
## Harvest policy already lives in World.can_harvest_plot (world.gd ~630, also
## used by harvester.gd:23). can_harvest() delegates to it; nothing is copied.
##
## ---------------------------------------------------------------------------
## ROLES preserved (no new role is introduced):
##   plot owner        crops[k].owner            -- sow (tea/nursery), restore, greenhouse
##   harvest grantee   crops[k].harvest_access   -- "owner" | "island" | "friend" (+harvest_friend)
##   placer            objects/ground/roofs[k].owner -- dismantle/move, private boxes, roof on floor
##   tree planter      forest[k].owner           -- lift sapling back
##   salt-lot holder   salt_pan.lots[i].owner    -- chest socket placement in Beimen
##   world owner/member (world_membership.gd:41,129): World grants the world owner
##     NO plot override today, so ROLE_OVERRIDES stays empty. An admin role is the
##     undecided part of T057 and must be added deliberately, not here.
##
## EXPLICIT PUBLIC AREAS preserved:
##   World.water(p) or World.protected(p) (world.gd:302,310): paths, ferry stall
##   cells, spawn/exit (only while empty), Jinguashi Bobo sites, regional
##   REGIONS.protected, and donated public-kitchen cells.
##   place      : rejected on any public cell (_apply gate, build_area, _blueprint_piece).
##   dismantle  : protected() is deliberately BYPASSED for remove (_apply gate);
##                only the donated public kitchen stays locked (remove, move_object).
##   take/harvest: no public-area rule.
##
## LEGACY DEFAULTS (fields missing from older saves) -- see LEGACY_DEFAULTS:
##   crops.harvest_access missing -> "island" by hand, "owner" by harvester.
##   crops.owner missing          -> home: sowable by anyone; tea garden / flower
##                                   nursery: nobody may sow; empty plot may be
##                                   restored by anyone (get("owner",token)).
##   forest/objects/ground/roofs owner missing -> denied (world.gd uses `.owner`
##                                   dot access there, which would raise; this
##                                   module denies instead of crashing).
##   private box owner missing    -> denied to everyone.
##
## ---------------------------------------------------------------------------
## INTEGRATION MAP. world.gd is edited concurrently and its line numbers drift
## (they moved +16 during this task), so each branch is anchored by its function
## / action and the exact message it returns. Lines are a 2026-11-14 snapshot.
## | op        | world.gd branch (anchor message)                         | ~line | module call
## | place     | _apply gate "這裡是水域或公共通道，請換個位置"            | 2125  | public_area() (skip for remove)
## | place     | build_area "範圍包含水域或公共通道…" / "整片屋頂都需要自己的木地板…" | 1860,1862 | public_area(), roof floor owner
## | place     | _build_piece `if _region==SALT_PAN.REGION` → SALT_SOCKET_MSG | 2322-2325 | can_place (salt lot holder)
## | place     | _build_piece "請在自己的農田上蓋溫室玻璃棚"              | 2338  | can_place(kind="greenhouse_roof")
## | place     | _build_piece "只能在自己的地板上蓋屋頂"                  | 2342  | can_place(kind="roof")
## | place     | _blueprint_piece public gate / "物件不能放在他人的地板上" | 2594,2598 | can_place(..., blueprint=true)
## | place     | action "seed": "只有茶圃田主能播種" / FOREIGN_PLOT_MESSAGE | 2170,2171 | can_place(kind="seed:<crop>")
## | place     | move_object destination "新位置不是可用空地…"           | 1893  | public_area() part of that line only
## | take      | deposit/withdraw "這是另一位島民的私人箱"               | 2103  | can_take
## | take      | _salt_cfg_chest `box.type=="private_chest"`             | 2300  | can_take (equivalent: Beimen only
## |           |                                                          |       |   allows SALT_BOXES, never supply_box)
## | harvest   | action "harvest" `not can_harvest_plot(crop,token)`     | 2203  | can_harvest (already shared helper)
## | harvest   | harvester.gd plan() "沒有採收權限"                       | h:23  | can_harvest(machine=true) (already shared)
## | dismantle | action "remove": MSG_LOCKED / "只能移回自己種下的樹苗" / "只能恢復自己開墾的農田" / "只能拆除自己放置的物件" | 2217,2219,2228,2237 | can_dismantle
## | dismantle | move_object source: MSG_LOCKED / "只能搬自己放置的家具"  | 1877,1879 | can_dismantle(move=true)
## Order caveat for integration: in "remove" world.gd checks "田裡還有作物" BEFORE
## the plot owner; keep that guard ahead of can_dismantle to preserve messages.
## Not routed through this module (left as-is, documented for T057 review):
##   action "hoe" (~2155) and till_area tiller.gd:20 -- any member may till
##     unclaimed land; tiller also respects public_area.
##   action "water" (~2180) -- any member may water any plot (auto sprinklers only
##     water their owner's plots, ~646).
##   action "seed" at home (~2164) -- any member may sow any empty home plot,
##     while seed_area (seeder.gd:23) is stricter: own plots only.
##   action "plot_harvest_access" (~2184) -- owner-only, one inline check.
##   per-device operate checks (mine_drill, waterworks, tank/pump, sprinkler,
##     logistics, forester, processing): owner-only, outside plot rights.
## ---------------------------------------------------------------------------

const BLUEPRINT_DESIGN = preload("res://scripts/blueprint_design.gd")
const FLOWER_NURSERY = preload("res://scripts/flower_nursery.gd")
const PUBLIC_KITCHEN = preload("res://scripts/public_kitchen.gd")
const REGIONS = preload("res://scripts/regions.gd")
const SALT_PAN = preload("res://scripts/salt_pan.gd")

## Empty on purpose: world owner has no plot override today (see header).
const ROLE_OVERRIDES := {}
const LEGACY_DEFAULTS := {
	"harvest_access_hand":"island",
	"harvest_access_machine":"owner",
	"crop_owner_restorable_by_anyone":true,
	"crop_owner_sowable_home":true,
	# = [REGIONS.Bamboo.REGION, FLOWER_NURSERY.REGION]; asserted by the test.
	"crop_owner_sowable_owner_only_regions":["bamboo_grove","tianwei"],
	"placed_owner_missing":"deny",
	"private_box_owner_missing":"deny",
}
## Mirrors of World constants (test_plot_permissions asserts they stay equal).
const PRIVATE_BOXES := ["private_chest","supply_box"]
const SALT_BOXES := ["chest","private_chest"]
const MSG_PUBLIC := "這裡是水域或公共通道，請換個位置"
const MSG_SALT_SOCKET := "只有這塊鹽田區的認領人，可以在收鹽箱位置放箱子。"
const MSG_FOREIGN_BOX := "這是另一位島民的私人箱"
const MSG_ROOF_FLOOR := "只能在自己的地板上蓋屋頂"
const MSG_GREENHOUSE := "請在自己的農田上蓋溫室玻璃棚"
const MSG_BLUEPRINT_FLOOR := "物件不能放在他人的地板上"
const MSG_PRIVATE_FLOOR := "這格地板只開放地板主人放置物件。"
const FLOOR_ACCESS := ["legacy","owner","island"]
const SHARED_REMOVAL_FURNITURE := ["chair","table","sofa","bed","bench","long_bench","lamp","planter","flower_pot","rope_rack","towel_rack"]
const MSG_TEA_SEED := "只有茶圃田主能播種"
const MSG_FOREIGN_TREE := "只能移回自己種下的樹苗"
const MSG_FOREIGN_PLOT := "只能恢復自己開墾的農田"
const MSG_SOW_OWNER := "這塊農田只開放田主播種。"
const MSG_WATER_OWNER := "這塊農田只開放田主手動澆水。"
const MSG_FOREIGN_OBJECT := "只能拆除自己放置的物件"
const MSG_FOREIGN_MOVE := "只能搬自己放置的家具"
const MSG_HARVEST := "你沒有這塊田的採收權限。"
const MSG_HARVEST_MACHINE := "沒有採收權限"

static func allow() -> Dictionary:
	return {"ok":true,"message":""}

static func deny(message: String) -> Dictionary:
	return {"ok":false,"message":message}

## Explicit public area: water, paths, spawn/exit, stalls, donated kitchen.
static func public_area(world, p: Vector2i) -> bool:
	return world.water(p) or world.protected(p)

static func kitchen_locked(world, p: Vector2i) -> bool:
	return world._region == REGIONS.HOME and PUBLIC_KITCHEN.is_site_cell(world.state, p)

## Effective harvest access of a plot, with the legacy default applied.
static func harvest_access(plot: Dictionary, machine := false) -> String:
	var fallback: String = LEGACY_DEFAULTS.harvest_access_machine if machine else LEGACY_DEFAULTS.harvest_access_hand
	return str(plot.get("harvest_access", fallback))

static func _owned_by(entry, token: String) -> bool:
	return entry is Dictionary and typeof(entry.get("owner")) == TYPE_STRING and entry.owner == token

## place: kind is a BUILD id, or "seed:<crop>" for sowing an existing plot.
## blueprint=true adds the blueprint-only foreign-floor rule (world.gd:2582).
static func can_place(world, token: String, p: Vector2i, kind: String, blueprint := false) -> Dictionary:
	if public_area(world, p):return deny(MSG_PUBLIC)
	var k: String = world.key(p)
	var st: Dictionary = world.state
	var region: String = world._region
	if kind.begins_with("seed:"):
		var crop:Dictionary=st.crops.get(k,{})
		var owner := str(crop.get("owner", ""))
		if region == REGIONS.HOME and crop.get("owner_sow",false) and owner != token:return deny(MSG_SOW_OWNER)
		if region == REGIONS.Bamboo.REGION and owner != token:return deny(MSG_TEA_SEED)
		if region == FLOWER_NURSERY.REGION and owner != token:return deny(FLOWER_NURSERY.FOREIGN_PLOT_MESSAGE)
		return allow()
	if region == SALT_PAN.REGION:
		var lot: int = SALT_PAN.chest_socket_lot(p)
		if kind not in SALT_BOXES or lot < 0:return deny(SALT_PAN.REJECT_MESSAGE)
		var lots = st.get("salt_pan", {}).get("lots", [])
		if not lots is Array or lot >= lots.size() or str(lots[lot].get("owner", "")) != token:return deny(MSG_SALT_SOCKET)
	if kind == "greenhouse_roof" and str(st.crops.get(k, {}).get("owner", "")) != token:return deny(MSG_GREENHOUSE)
	if kind == "roof" and st.ground.has(k) and not _owned_by(st.ground[k], token):return deny(MSG_ROOF_FLOOR)
	if blueprint:return blueprint_floor(world, token, p, kind)
	if kind not in BLUEPRINT_DESIGN.GROUND_KINDS and kind not in BLUEPRINT_DESIGN.ROOF_KINDS:
		return placement_floor(world,token,p)
	return allow()

## Checked before the normal build rules when staging a blueprint piece.
static func blueprint_floor(world, token: String, p: Vector2i, kind: String) -> Dictionary:
	if kind not in BLUEPRINT_DESIGN.GROUND_KINDS and kind not in BLUEPRINT_DESIGN.ROOF_KINDS:
		return placement_floor(world,token,p,true)
	return allow()

static func placement_floor(world, token:String, p:Vector2i, blueprint:=false) -> Dictionary:
	var below = world.state.ground.get(world.key(p))
	if not below is Dictionary or _owned_by(below,token):return allow()
	if below.get("type")=="floor":
		var access:String=below.get("placement_access","legacy")
		if access=="owner":return deny(MSG_PRIVATE_FLOOR)
		if access=="island":return allow()
	return deny(MSG_BLUEPRINT_FLOOR) if blueprint else allow()

## take: deposit into / withdraw from / configure a box. Shared chests are open.
static func can_take(token: String, box: Dictionary) -> Dictionary:
	if str(box.get("type", "")) in PRIVATE_BOXES and not _owned_by(box, token):return deny(MSG_FOREIGN_BOX)
	return allow()

static func can_deposit(token:String,box:Dictionary) -> Dictionary:
	if box.get("type")=="private_chest" and box.get("guest_deposit",false):return allow()
	return can_take(token,box)

static func can_withdraw(token:String,box:Dictionary) -> Dictionary:
	if box.get("type")=="private_chest" and box.get("withdraw_guest")==token:return allow()
	return can_take(token,box)

static func can_water(world,token:String,plot:Dictionary) -> Dictionary:
	if world._region==REGIONS.HOME and plot.get("owner_water",false) and not _owned_by(plot,token):
		return deny(MSG_WATER_OWNER)
	return allow()

## harvest: delegates to World.can_harvest_plot (single source of policy).
static func can_harvest(world, token: String, plot: Dictionary, machine := false) -> Dictionary:
	if world.can_harvest_plot(plot, token, machine):return allow()
	if machine:return deny(MSG_HARVEST_MACHINE)
	return deny(FLOWER_NURSERY.FOREIGN_PLOT_MESSAGE if world._region == FLOWER_NURSERY.REGION else MSG_HARVEST)

## dismantle: `remove` (move=false) or `move_object` source (move=true).
## protected() is intentionally NOT applied; only the donated kitchen is locked.
## Ownership only: "nothing here", crops-with-kind, busy and contents guards stay
## in World (returns allow() when there is nothing this rule could refuse).
static func can_dismantle(world, token: String, p: Vector2i, move := false) -> Dictionary:
	if kitchen_locked(world, p):return deny(PUBLIC_KITCHEN.MSG_LOCKED)
	var k: String = world.key(p)
	var st: Dictionary = world.state
	if move:
		return allow() if _owned_by(st.objects.get(k), token) else deny(MSG_FOREIGN_MOVE)
	if st.forest.has(k):
		return allow() if _owned_by(st.forest[k], token) else deny(MSG_FOREIGN_TREE)
	if st.crops.has(k) and not world.greenhouse_covers(k):
		# Legacy: an ownerless empty plot is restorable by anyone.
		return allow() if str(st.crops[k].get("owner", token)) == token else deny(MSG_FOREIGN_PLOT)
	var layer: String = world._remove_layer(k)
	if layer == "":return allow()
	var piece:Dictionary=st[layer][k]
	if layer=="objects" and world._region==REGIONS.HOME and piece.get("guest_remove",false) and piece.get("type") in SHARED_REMOVAL_FURNITURE:
		return allow()
	return allow() if _owned_by(st[layer][k], token) else deny(MSG_FOREIGN_OBJECT)
