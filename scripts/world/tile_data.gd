## 地块数据资源。
## 描述单个地块的类型、通行性和可建造性等属性。
## 由 [TerrainGenerator] 在生成地形时为每个地块实例赋值。
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

## 肥力值（0.0 ~ 5.0）。对农田有实际影响，非农田为参考值。
var fertility: float = 0.0

## 湿度值（0.0 ~ 5.0）。
var moisture: float = 0.0

## 硬度值，影响建造/挖掘耗时。
var hardness: int = 1

## 水深（0.0 ~ 1.0）。仅水域有意义。
var depth: float = 0.0

## 是否可钓鱼。仅水域有意义。
var fishable: bool = false

## 资源类型（地块可能产出的资源种类）。
var resource_type: int = 0

# ============================================================
# 9. 公开方法
# ============================================================

## 根据 [member tile_type] 和 [member variant] 设置默认属性。
func apply_defaults() -> void:
	match tile_type:
		TileType.DIRT:
			_apply_dirt_defaults()
		TileType.STONE:
			_apply_stone_defaults()
		TileType.OCEAN:
			_apply_ocean_defaults()
		TileType.FARMLAND:
			_apply_farmland_defaults()

## 返回人类可读的类型名称。
func get_type_name() -> String:
	match tile_type:
		TileType.DIRT:
			return "土质地面"
		TileType.STONE:
			return "石质地面"
		TileType.OCEAN:
			return "水域"
		TileType.FARMLAND:
			return "农田"
		_:
			return "未知"

## 该地块是否可被耕作（转化为农田）。
func can_be_plowed() -> bool:
	return tile_type == TileType.DIRT and not farmland

## 该地块是否可被挖掘（转化为普通土壤）。
func can_be_dug() -> bool:
	return tile_type == TileType.STONE

# ============================================================
# 10. 私有方法 — 类型默认值
# ============================================================

func _apply_dirt_defaults() -> void:
	passable = true
	buildable = true
	farmland = false
	moisture = 0.3
	fertility = 0.8
	hardness = 1
	depth = 0.0
	fishable = false

	match variant:
		"grassland":
			variant_name = "草地"
			moisture = 0.8
			fertility = 0.8
		"soil":
			variant_name = "普通土壤"
			moisture = 0.8
			fertility = 0.8
		"sand":
			variant_name = "沙地"
			moisture = 0.1
			fertility = 0.2
			farmland = true
		"wetland":
			variant_name = "湿地"
			moisture = 1.8
			fertility = 1.0
		_:
			variant_name = "普通土壤"
			moisture = 0.8
			fertility = 0.8

func _apply_stone_defaults() -> void:
	passable = true
	buildable = true
	farmland = false
	moisture = 0.1
	fertility = 0.0
	depth = 0.0
	fishable = false
	resource_type = 1  # STONE

	match variant:
		"gravel":
			variant_name = "碎石地"
			hardness = 2
		"pebble":
			variant_name = "卵石地"
			hardness = 3
		"hard_stone":
			variant_name = "坚硬石质"
			hardness = 5
		_:
			variant_name = "坚硬石质"
			hardness = 5

func _apply_ocean_defaults() -> void:
	passable = false
	buildable = false
	farmland = false
	moisture = 10.0
	fertility = 0.0
	fishable = true
	resource_type = 5  # FISH

	match variant:
		"shallow":
			variant_name = "浅水"
			depth = 0.3
		"deep":
			variant_name = "深海"
			depth = 1.0
		"river":
			variant_name = "河流"
			depth = 0.5
		_:
			variant_name = "深海"
			depth = 1.0

func _apply_farmland_defaults() -> void:
	passable = true
	buildable = false
	farmland = true
	hardness = 1
	depth = 0.0
	fishable = false
	# fertility 和 moisture 由转化的源 DIRT 继承，此处设默认值

	match variant:
		"soil_farmland":
			variant_name = "土质农田"
			moisture = 0.8
			fertility = 0.8
		"silt_farmland":
			variant_name = "淤泥农田"
			moisture = 1.8
			fertility = 1.0
		_:
			variant_name = "土质农田"
			moisture = 0.8
			fertility = 0.8
