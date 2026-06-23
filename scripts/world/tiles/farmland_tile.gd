## 农田地块 — "土质农田"变种。
##
## 挂载在 [code]farmland_1.tscn[/code] 上。
## 由 DIRT（草地 / 普通土壤）通过"耕作"转化而来。不可自然生成。
## 是种植作物的唯一地块类型。
class_name FarmlandTile extends BaseTile

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	if tile_type == -1:
		tile_type = TileInfo.TileType.FARMLAND
	if variant.is_empty():
		variant = "soil_farmland"
	if display_name.is_empty():
		display_name = "土质农田"
	super._ready()

# ============================================================
# 9. 公开方法 — 地块交互
# ============================================================

## 已是农田，不可重复耕作。
func can_be_plowed() -> bool:
	return false

## 农田不可挖掘（可退耕转化为 DIRT）。
func can_be_dug() -> bool:
	return false
