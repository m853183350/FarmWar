## 地块抽象基类。
##
## 所有地块类型（DIRT、STONE、OCEAN、FARMLAND 等）都必须继承本类。
## 定义了地块的必备属性访问器、内容物管理和通用接口，
## 确保所有地块类型具有一致的行为契约。
##
## 子类必须：
##   - 在 [method _ready] 中设置 [member tile_type]、[member variant]、[member display_name]
##   - 覆写 [method can_be_plowed] 和 [method can_be_dug]
class_name BaseTile extends Sprite2D

# ============================================================
# 1. 信号
# ============================================================

## 地块数据资源变更时发出。
signal tile_data_changed()

## 内容物添加时发出。
signal occupant_added(occupant: Node)

## 内容物移除时发出。
signal occupant_removed(occupant: Node)

# ============================================================
# 2. 枚举
# ============================================================

## 资源类型（地块可能产出或蕴含的资源种类）。
enum ResourceType {
	NONE,         ## 无资源
	STONE,        ## 石材
	IRON,         ## 铁矿
	GOLD,         ## 金矿
	WOOD,         ## 木材
	FISH,         ## 鱼类
}

# ============================================================
# 4. @export 变量 — 子类身份标识
# ============================================================

## 地块大类（对应 [enum TileInfo.TileType]）。
## 子类必须在 [method _ready] 中设置有效值。
@export var tile_type: int = -1

## 地块细分变种名称（如 "soil"、"hard_stone"、"deep" 等）。
@export var variant: String = ""

## 地块人类可读名称。
@export var display_name: String = ""

# ============================================================
# 5. 公开变量 — 必备属性（来自 Docs/地块系统/1.1地块系统.md）
# ============================================================

## 地块上附着的内容物列表。
var occupants: Array[Node] = []

# ============================================================
# 6. 私有变量
# ============================================================

var _tile_data: TileInfo = null

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 同步 metadata 中可能已存在的 tile_data（兼容直接 set_meta 的旧代码路径）
	if _tile_data == null:
		var meta_data: TileInfo = get_meta("tile_data", null) as TileInfo
		if meta_data:
			_tile_data = meta_data
	_validate_constants()

# ============================================================
# 9. 公开方法 — 数据访问
# ============================================================

## 获取地块数据资源。
## 返回 [code]null[/code] 表示数据尚未设置。
func get_tile_data() -> TileInfo:
	return _tile_data

## 设置地块数据资源，同步到节点 metadata 并发出 [signal tile_data_changed]。
func set_tile_data(data: TileInfo) -> void:
	_tile_data = data
	if data:
		set_meta("tile_data", data)
	tile_data_changed.emit()

## 获取地块在地图网格中的坐标。
func get_grid_position() -> Vector2i:
	if _tile_data:
		return _tile_data.grid_position
	return Vector2i.ZERO

# ============================================================
# 9. 公开方法 — 通行与建造（必备属性）
# ============================================================

## 是否可通行。
func is_passable() -> bool:
	if _tile_data:
		return _tile_data.passable
	return true

## 是否可建造。
func is_buildable() -> bool:
	if _tile_data:
		return _tile_data.buildable
	return true

## 是否是农田 / 可耕种。
func is_farmland() -> bool:
	if _tile_data:
		return _tile_data.farmland
	return false

## 获取资源类型。
func get_resource_type() -> int:
	if _tile_data:
		return _tile_data.resource_type
	return ResourceType.NONE

# ============================================================
# 9. 公开方法 — 地块交互（子类覆写）
# ============================================================

## 该地块是否可被耕作（转化为农田）。
## 默认返回 [code]false[/code]，子类按需覆写。
func can_be_plowed() -> bool:
	return false

## 该地块是否可被挖掘。
## 默认返回 [code]false[/code]，子类按需覆写。
func can_be_dug() -> bool:
	return false

# ============================================================
# 9. 公开方法 — 内容物管理
# ============================================================

## 添加内容物到地块。
func add_occupant(node: Node) -> void:
	if node and node not in occupants:
		occupants.append(node)
		occupant_added.emit(node)

## 从地块移除内容物。
func remove_occupant(node: Node) -> void:
	if node in occupants:
		occupants.erase(node)
		occupant_removed.emit(node)

## 地块上是否有指定类的实例。
##
## 检查顺序：
##   1. 先使用 [method Object.is_class] 检查引擎内置类（如 Node2D、Sprite2D 等）
##   2. 若失败，遍历脚本继承链，通过 [method Script.get_global_name] 匹配自定义 class_name
##      这样即使 Godot 的 is_class 对继承链中的自定义类名失效，也能正确识别。
func has_occupant_of_type(klass_name: String) -> bool:
	for occ: Node in occupants:
		if not is_instance_valid(occ):
			continue
		# 1. 优先使用引擎内置的 is_class
		if occ.is_class(klass_name):
			return true
		# 2. 兜底：遍历脚本继承链，匹配自定义 class_name
		var scr: Script = occ.get_script() as Script
		while scr != null:
			if scr.get_global_name() == klass_name:
				return true
			scr = scr.get_base_script()
	return false

## 获取地块上所有内容物。
func get_all_occupants() -> Array[Node]:
	return occupants.duplicate()

# ============================================================
# 9. 公开方法 — 可选属性访问器
# ============================================================

## 获取肥力值（0.0 ~ 5.0）。
func get_fertility() -> float:
	if _tile_data:
		return _tile_data.fertility
	return 0.0

## 获取湿度值（0.0 ~ 5.0）。
func get_moisture() -> float:
	if _tile_data:
		return _tile_data.moisture
	return 0.0

## 获取硬度值（影响建造 / 挖掘耗时）。
func get_hardness() -> int:
	if _tile_data:
		return _tile_data.hardness
	return 1

## 获取水深（0.0 ~ 1.0）。仅水域有意义。
func get_depth() -> float:
	if _tile_data:
		return _tile_data.depth
	return 0.0

## 是否可钓鱼。仅水域有意义。
func is_fishable() -> bool:
	if _tile_data:
		return _tile_data.fishable
	return false

# ============================================================
# 9. 公开方法 — 调试与显示
# ============================================================

## 返回人类可读的类型名称。
func get_type_name() -> String:
	if _tile_data:
		return _tile_data.get_type_name()
	return "未知"

## 返回人类可读的地块描述（变种 + 类型）。
func get_description() -> String:
	return "%s (%s)" % [display_name, get_type_name()]

# ============================================================
# 10. 私有方法 — 校验
# ============================================================

## 校验子类是否设置了有效的身份标识。
func _validate_constants() -> void:
	if tile_type == -1:
		push_error("BaseTile: 子类 %s 未设置 tile_type，请在 _ready() 中赋值" % get_script().resource_path)
	if variant == "":
		push_warning("BaseTile: 子类 %s 未设置 variant，请在 _ready() 中赋值" % get_script().resource_path)
	if display_name == "":
		push_warning("BaseTile: 子类 %s 未设置 display_name，请在 _ready() 中赋值" % get_script().resource_path)
