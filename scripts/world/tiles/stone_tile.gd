## 石质地面地块 — "坚硬石质"变种。
##
## 挂载在 [code]stone_1.tscn[/code] 上。
## 坚硬的岩石地表，需要高级工具清理。清理后转化为普通土壤，产出石材资源。
class_name StoneTile extends BaseTile

# ============================================================
# 3. 常量 — 子类特有属性
# ============================================================

## 清理后可产出的石材数量范围。
const PRODUCE_STONE_MIN: int = 5
const PRODUCE_STONE_MAX: int = 10

## 是否可能产出稀有矿物。
const CAN_PRODUCE_MINERAL: bool = true

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	tile_type = TileInfo.TileType.STONE
	variant = "hard_stone"
	display_name = "坚硬石质"
	super._ready()

# ============================================================
# 9. 公开方法 — 地块交互
# ============================================================

## 石质地面不可耕作（需先挖掘转化为 DIRT）。
func can_be_plowed() -> bool:
	return false

## 可被挖掘，转化为普通土壤并产出石材。
func can_be_dug() -> bool:
	return true

# ============================================================
# 9. 公开方法 — 子类特有
# ============================================================

## 获取挖掘后的石材产出（随机值）。
func get_dig_produce() -> int:
	return randi_range(PRODUCE_STONE_MIN, PRODUCE_STONE_MAX)
