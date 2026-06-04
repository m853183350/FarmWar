## 水域地块 — "深海"变种。
##
## 挂载在 [code]ocean_1.tscn[/code] 上。
## 远离海岸的深水区。不可通行、不可建造、不可填平，作为地图天然边界。
class_name OceanTile extends BaseTile

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	tile_type = TileInfo.TileType.OCEAN
	variant = "deep"
	display_name = "深海"
	super._ready()

# ============================================================
# 9. 公开方法 — 地块交互
# ============================================================

## 水域不可耕作。
func can_be_plowed() -> bool:
	return false

## 深水不可挖掘 / 填平。
func can_be_dug() -> bool:
	return false
