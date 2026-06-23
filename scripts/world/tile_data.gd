## 地块数据资源。
## 描述单个地块的类型、通行性和可建造性等属性。
## 所有默认属性值从 [code]config/terrain_config.json[/code] 注入，
## 由 [TerrainGenerator] 在创建地块实例时传入配置字典。
class_name TileInfo extends Resource

# ============================================================
# 2. 枚举
# ============================================================

## 地块大类。
enum TileType {
	DIRT,        ## 土质地面 — 默认可耕种
	STONE,       ## 石质地面 — 可清理后建造
	OCEAN,       ## 水域 — 不可通行
	FARMLAND,    ## 农田 — 由 DIRT 耕作转化，不可自然生成
	SLOPE,       ## 斜坡（预留）
	ROUGH,       ## 崎岖地块（预留）
	SPECIAL,     ## 特殊地块（预留）
}

# ============================================================
# 5. 公开变量
# ============================================================

## 地块在地图网格中的坐标。
var grid_position: Vector2i = Vector2i.ZERO

## 地块大类。
var tile_type: TileType = TileType.DIRT

## 地块细分变种名称（如 "soil"、"hard_stone"、"deep" 等）。
var variant: String = ""

## 地块人类可读名称。
var variant_name: String = ""

## 是否可以通行。
var passable: bool = true

## 是否可以建造。
var buildable: bool = true

## 是否可耕种/已是农田。
var farmland: bool = false

## 肥力值（0.0 ~ 5.0）。最终计算值，由 update_properties 填充。
var fertility: float = 0.0

## 湿度值（0.0 ~ 5.0）。最终计算值，由 update_properties 填充。
var moisture: float = 0.0

## 硬度值，影响建造/挖掘耗时。
var hardness: int = 1

## 温度值（摄氏度）。最终计算值，由 update_properties 填充。
var temperature: float = 25.0

## 水深（0.0 ~ 1.0）。仅水域有意义。
var depth: float = 0.0

## 是否可钓鱼。仅水域有意义。
var fishable: bool = false

## 资源类型（地块可能产出的资源种类）。
var resource_type: int = 0

## 地块标签数组（如 water_source、hot_source 等）。
## 拥有特定标签的地块可能触发周围地块属性传播更新。
var tags: Array[String] = []

# -------- 基础值字段（由 apply_defaults 按配置中的类型/变种设置） --------

## 湿度基础倍率（地块倍率）。根据地块类型/变种设置，用于湿度计算公式。
var moisture_base_rate: float = 1.0

## 肥力基础值（地块基础值）。根据地块类型/变种设置，用于肥力计算公式。
var fertility_base: float = 0.0

# -------- 修正值字段 --------
# 由外部系统（道具、建筑、Buff 等）修改，参与最终属性计算。
# 公式见 Docs/地块系统/1.1地块系统.md

## 湿度修正值1 — 加在系数括号内（与水面修正值同位置）。
var moisture_modifier_1: float = 0.0

## 湿度修正值2 — 加在最终值上。
var moisture_modifier_2: float = 0.0

## 肥力修正值1 — 与地块基础值相加后再乘以修正倍率。
var fertility_modifier_1: float = 0.0

## 肥力修正值2 — 加在最终值上。
var fertility_modifier_2: float = 0.0

## 肥力修正倍率 — 与 (基础值 + 肥力修正值1) 相乘。
var fertility_multiplier: float = 1.0

## 温度修正值1 — 预留，待季节气候系统实现。
var temperature_modifier_1: float = 0.0

## 温度修正值2 — 预留，待季节气候系统实现。
var temperature_modifier_2: float = 0.0

# ============================================================
# 9. 公开方法
# ============================================================

## 根据配置文件中的类型默认值和变种覆盖值设置地块属性。
##
## [param config] 由 [TerrainGenerator] 从 [code]terrain_config.json[/code]
## 合并后的配置字典，应包含以下键：
##   - passable, buildable, farmland, hardness, depth, fishable,
##     resource_type, tags（类型级默认值）
##   - moisture_base_rate, fertility_base, variant_name（变种级数据）
##
## 变种级字段会覆盖类型级同名字段。
func apply_defaults(config: Dictionary) -> void:
	# -------- 类型级默认属性 --------
	passable = config.get("passable", true)
	buildable = config.get("buildable", true)
	farmland = config.get("farmland", false)
	hardness = config.get("hardness", 1)
	depth = config.get("depth", 0.0)
	fishable = config.get("fishable", false)
	resource_type = config.get("resource_type", 0)
	# JSON 解析出的 Array 不是强类型，需逐元素转换再赋值给 Array[String]
	var raw_tags: Array = config.get("tags", [])
	tags.clear()
	for t in raw_tags:
		tags.append(t as String)

	# -------- 变种级属性 --------
	moisture_base_rate = config.get("moisture_base_rate", 1.0)
	fertility_base = config.get("fertility_base", 0.0)
	variant_name = config.get("variant_name", "")

	# -------- 重置计算值（由 BaseTile.update_properties 填充） --------
	moisture = 0.0
	fertility = 0.0

## 根据当前 [member tile_type] 同步标签。
## 作为兜底方法，当 config 未提供 tags 时使用。
## 仅修改 [member tags]，不触及其他字段。
func sync_tags() -> void:
	match tile_type:
		TileType.OCEAN:
			tags = ["water_source"]
		_:
			tags.clear()

## 返回人类可读的类型名称。
func get_type_name() -> String:
	return variant_name
	# match tile_type:
	# 	TileType.DIRT:
	# 		return "土质地面"
	# 	TileType.STONE:
	# 		return "石质地面"
	# 	TileType.OCEAN:
	# 		return "水域"
	# 	TileType.FARMLAND:
	# 		return "农田"
	# 	_:
	# 		return "未知"

## 该地块是否可被耕作（转化为农田）。
func can_be_plowed() -> bool:
	return tile_type == TileType.DIRT and not farmland

## 该地块是否可被挖掘（转化为普通土壤）。
func can_be_dug() -> bool:
	return tile_type == TileType.STONE
