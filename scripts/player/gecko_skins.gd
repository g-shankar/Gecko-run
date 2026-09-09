class_name GeckoSkins
extends RefCounted
## Gecko Run — P23 hero skin registry.
##
## One Tripo model, five selectable looks. Skins are albedo_color multiplies
## on the hero mesh's textured material — zero extra model generations.
## The material is duplicated once per MeshInstance3D (cached in metadata)
## so the imported resource is never mutated.
##
## LEARNING NOTES (for Gowrishankar):
## - albedo_color MULTIPLIES the texture: white keeps the original look,
##   orange tint times green scales reads as a warm variant.
## - RefCounted + static funcs = a pure helper, no node needed.

const SKINS: Array = [
	{"name": "Classic Green", "short": "GREEN", "tint": Color(1.0, 1.0, 1.0)},
	{"name": "Sunset Orange", "short": "SUNSET", "tint": Color(1.0, 0.52, 0.22)},
	{"name": "Blue Stripe", "short": "BLUE", "tint": Color(0.38, 0.85, 1.0)},
	{"name": "Gold Dust", "short": "GOLD", "tint": Color(1.0, 0.85, 0.42)},
	{"name": "Midnight", "short": "NIGHT", "tint": Color(0.28, 0.3, 0.38)},
]

const _MAT_META := "__gecko_skin_mat"


static func count() -> int:
	return SKINS.size()


static func skin_name(index: int) -> String:
	return String(SKINS[clampi(index, 0, SKINS.size() - 1)]["name"])


static func skin_short(index: int) -> String:
	return String(SKINS[clampi(index, 0, SKINS.size() - 1)]["short"])


static func skin_tint(index: int) -> Color:
	return SKINS[clampi(index, 0, SKINS.size() - 1)]["tint"] as Color


## Apply a skin to a MeshInstance3D carrying the hero mesh. Safe to call
## repeatedly — the duplicated material is cached on the instance.
static func apply_skin(mi: MeshInstance3D, index: int) -> void:
	if mi == null or mi.mesh == null:
		return
	var i: int = clampi(index, 0, SKINS.size() - 1)
	var mat: StandardMaterial3D = null
	if mi.has_meta(_MAT_META):
		mat = mi.get_meta(_MAT_META) as StandardMaterial3D
	if mat == null:
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src == null:
			return
		mat = src.duplicate() as StandardMaterial3D
		mi.set_meta(_MAT_META, mat)
		mi.set_surface_override_material(0, mat)
	mat.albedo_color = SKINS[i]["tint"] as Color
