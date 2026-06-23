## 土质地面地块 — "普通土壤"变种。
##
## 挂载在 [code]dirt_1.tscn[/code] 上。
## 最常见的可耕作地块，各项属性均衡，是转化为农田的基础原料。
class_name DirtTile extends BaseTile

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	if tile_type == -1:
		tile_type = TileInfo.TileType.DIRT
	if variant.is_empty():
		variant = "soil"
	if display_name.is_empty():
		display_name = "普通土壤"
	super._ready()

# ============================================================
# 9. 公开方法 — 地块交互
# ============================================================

## DIRT 可被耕作转化为农田。
func can_be_plowed() -> bool:
	return true

## DIRT 不可被挖掘（只有 STONE 可挖掘）。
func can_be_dug() -> bool:
	return false
