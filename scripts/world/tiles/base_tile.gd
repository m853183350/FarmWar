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
# 3. 常量
# ============================================================

const ZIndexConfig = preload("res://scripts/utils/z_index_config.gd")
const WorldUtils = preload("res://scripts/utils/world_utils.gd")

# -------- 湿度计算参数 --------

## 水面修正值上限 y（水源能提供的最大湿度修正）。
const WATER_SOURCE_MAX_Y: float = 1.0

## 水面距离倍率 t — 每单位曼哈顿距离衰减量。
const WATER_SOURCE_DISTANCE_FACTOR: float = 0.3

## 湿度计算结果下限。
const MOISTURE_MIN: float = 0.0

## 湿度计算结果上限。
const MOISTURE_MAX: float = 5.0

# -------- 温度计算参数 --------

## 热源修正值上限 y（热源能提供的最大温度修正）。
const HOT_SOURCE_MAX_Y: float = 500.0

## 热源距离倍率 t — 每单位曼哈顿距离衰减量。
const HOT_SOURCE_DISTANCE_FACTOR: float = 50

## 默认环境温度（摄氏度），待季节气候系统实现后替换。
const DEFAULT_AMBIENT_TEMPERATURE: float = 25.0

# -------- 肥力计算参数 --------

## 肥力计算结果下限。
const FERTILITY_MIN: float = 0.0

## 肥力计算结果上限。
const FERTILITY_MAX: float = 5.0

# -------- 传播参数 --------

## 各标签对应的 BFS 传播深度（曼哈顿距离）。
const TAG_PROPAGATION_DEPTH := {
	"water_source": 6,
	"hot_source": 6,
}

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
	# 按地块位置计算并设置渲染排序 z_index
	update_z_index()
	# 监听 MODIFIER 道具变更，动态重新计算地块属性
	if EventBus:
		EventBus.tile_modifiers_changed.connect(_on_modifiers_changed)

func _exit_tree() -> void:
	if EventBus:
		EventBus.tile_modifiers_changed.disconnect(_on_modifiers_changed)

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
# 9. 公开方法 — 渲染排序
# ============================================================

## 获取渲染层优先级。
## 地块始终返回 [enum ZIndexConfig.RenderLayer.GROUND]。
func get_render_layer() -> int:
	return ZIndexConfig.RenderLayer.GROUND

## 获取视觉高度（世界像素）。
##
## 使用 [method ZIndexConfig.get_sprite_visual_height] 从精灵纹理和缩放计算。
## 子类可覆写以支持多格地块。
func get_visual_height() -> float:
	return ZIndexConfig.get_sprite_visual_height(self)

## 获取排序锚点 y 值 = [member CanvasItem.global_position].y + [method get_visual_height]。
func get_sorting_y() -> float:
	return global_position.y + get_visual_height()

## 根据当前排序锚点更新 [member CanvasItem.z_index]。
## 地块不移动，通常在 [method _ready] 中调用一次即可。
func update_z_index() -> void:
	z_index = ZIndexConfig.calc_z_index(get_sorting_y(), get_render_layer())

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

## 获取温度值（摄氏度）。默认25°C，待季节/气候系统实现后替换为动态值。
func get_temperature() -> float:
	if _tile_data:
		return _tile_data.temperature
	return 25.0

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

## 获取地块标签数组。
func get_tags() -> Array[String]:
	if _tile_data:
		return _tile_data.tags
	return []

## 检查地块是否拥有指定标签。
func has_tag(tag: String) -> bool:
	if _tile_data:
		return tag in _tile_data.tags
	return false

# ============================================================
# 9. 公开方法 — 属性更新
# ============================================================

## 根据当前地块类型重新同步标签。
## 应在 tile_type / variant 变化后调用。仅修改 [member TileInfo.tags]，不重置其他字段。
func update_tags() -> void:
	if not _tile_data:
		return
	_tile_data.sync_tags()

## 响应 MODIFIER 道具变更事件，重新计算地块属性。[br]
## 由 [signal EventBus.tile_modifiers_changed] 触发。
func _on_modifiers_changed() -> void:
	update_properties()

## 重新计算并更新地块的温度、湿度、肥力属性。
##
## 计算公式见 Docs/地块系统/1.1地块系统.md。
## - 湿度：基于最近 water_source 标签地块的曼哈顿距离 + 修正值
## - 肥力：基于地块基础值 + 修正值
## - 温度：基于最近 hot_source 标签地块的曼哈顿距离 + 环境温度（预留）
func update_properties() -> void:
	if not _tile_data:
		return
	var world := WorldUtils.get_world()
	if not world:
		return

	_tile_data.moisture = _calculate_moisture(world, _tile_data.grid_position)
	_tile_data.fertility = _calculate_fertility()
	_tile_data.temperature = _calculate_temperature(world, _tile_data.grid_position)

## 当具有特定标签的地块发生变化时，通过 BFS 传播更新周围地块的属性。
##
## 传播规则（来自设计文档）：
##   传播深度每增加 1（即曼哈顿距离 +1），计数器 -1，直到计数器归 0。
## [param tag] 触发传播的标签（如 "water_source"、"hot_source"）。
## [param center_pos] 发生变化的地块网格坐标。
## [param world_node]  世界节点，用于查找地块。
static func propagate_tag_update(tag: String, center_pos: Vector2i, world_node: Node2D) -> void:
	if not world_node:
		return
	var depth: int = TAG_PROPAGATION_DEPTH.get(tag, 0)
	if depth <= 0:
		return

	# BFS + 计数器传播
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [center_pos]
	visited[center_pos] = true

	for layer: int in range(depth):
		var next_queue: Array[Vector2i] = []

		for pos: Vector2i in queue:
			var tile := WorldUtils.find_tile(world_node, pos)
			if tile and tile is BaseTile:
				(tile as BaseTile).update_properties()

			for dir: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var neighbor := pos + dir
				if not visited.has(neighbor):
					visited[neighbor] = true
					next_queue.append(neighbor)

		queue = next_queue
		if queue.is_empty():
			break

## 获取指定标签的默认传播深度（曼哈顿距离）。
static func get_propagation_depth_for_tag(tag: String) -> int:
	return TAG_PROPAGATION_DEPTH.get(tag, 0)

# ============================================================
# 10. 私有方法 — 属性计算
# ============================================================

## 根据水面修正公式计算地块湿度。
##
## 公式：[code](1 + 水面修正值 + moisture_modifier_1) * moisture_base_rate + moisture_modifier_2[/code]
## 其中：[code]水面修正值 = max((y - t * distance_to_nearest_water_source), -1)[/code]
func _calculate_moisture(world: Node2D, grid_pos: Vector2i) -> float:
	if not _tile_data:
		return 0.0

	# 如果自身就是水源，直接返回最大值
	if "water_source" in _tile_data.tags:
		return MOISTURE_MAX

	var water_mod := _calc_tag_proximity_modifier(world, grid_pos, "water_source", WATER_SOURCE_MAX_Y, WATER_SOURCE_DISTANCE_FACTOR)
	var result := (1.0 + water_mod + _tile_data.moisture_modifier_1) * _tile_data.moisture_base_rate + _tile_data.moisture_modifier_2
	return clampf(result, MOISTURE_MIN, MOISTURE_MAX)

## 根据肥力公式计算地块肥力。
##
## 公式：[code](fertility_base + mod1) * mult + mod2[/code]
## 其中 mod1、mult、mod2 先取 [member TileInfo] 的静态值作为基础，
## 再叠加 [PropManager] 中活跃 MODIFIER 道具的动态加成（通过 [ModifierRegistry] 查询）。
func _calculate_fertility() -> float:
	if not _tile_data:
		return 0.0

	var mod1: float = _query_modifier("fertility_modifier_1", _tile_data.fertility_modifier_1)
	var mult: float = _query_modifier("fertility_multiplier", _tile_data.fertility_multiplier)
	var mod2: float = _query_modifier("fertility_modifier_2", _tile_data.fertility_modifier_2)

	var result := (_tile_data.fertility_base + mod1) * mult + mod2
	return clampf(result, FERTILITY_MIN, FERTILITY_MAX)

## 查询 MODIFIER 道具对指定属性的动态加成。[br]
## 通过 [code]prop_manager[/code] group 找到 [PropManager]，
## 委托其 [method PropManager.query_modifier] 查询 [ModifierRegistry]。[br]
## 传递当前地块的上下文（tile_type 等），用于 target_filter 匹配。[br]
## [param stat_name] 属性名（如 "fertility_modifier_1"）。[br]
## [param default_value] 无活跃修饰器时的默认值（来自 [TileInfo]）。[br]
## 返回聚合后的值。
func _query_modifier(stat_name: String, default_value: float) -> float:
	var pm: Node = get_tree().get_first_node_in_group("prop_manager") if is_inside_tree() else null
	if pm == null:
		return default_value
	if not pm.has_method("query_modifier"):
		return default_value
	# 构建上下文字典，供 Domain 的 target_filter 匹配
	var context: Dictionary = _build_modifier_context()
	return pm.query_modifier("tile", stat_name, default_value, context)

## 构建 MODIFIER 查询上下文字典。[br]
## 包含当前地块的关键属性，供 [member Domain] 的 [code]target_filter[/code] 匹配。[br]
## 当前上下文：[code]{ "tile_type": "farmland" | "dirt" | ... }[/code][br]
## 后续可扩展 crop_id、has_building 等字段。
func _build_modifier_context() -> Dictionary:
	var ctx: Dictionary = {}
	if _tile_data:
		# 将 TileType 枚举 int 值转为小写字符串，与 JSON 中 target_filter 格式一致
		var type_name: String = TileInfo.TileType.find_key(_tile_data.tile_type).to_lower()
		ctx["tile_type"] = type_name
	return ctx

## 根据热源 + 环境温度计算地块温度（预留，待季节气候系统完成后完善）。
##
## 当前使用默认环境温度 + 热源修正。
## 公式（暂定）：[code]环境温度 + 热源修正值（10*一个倍率） + temperature_modifier_1 + temperature_modifier_2[/code]
func _calculate_temperature(world: Node2D, grid_pos: Vector2i) -> float:
	if not _tile_data:
		return DEFAULT_AMBIENT_TEMPERATURE

	# 如果自身就是热源，直接返回较高温度
	if "hot_source" in _tile_data.tags:
		return DEFAULT_AMBIENT_TEMPERATURE + 1000.0

	var hot_mod := _calc_tag_proximity_modifier(world, grid_pos, "hot_source", HOT_SOURCE_MAX_Y, HOT_SOURCE_DISTANCE_FACTOR)
	var result := DEFAULT_AMBIENT_TEMPERATURE + hot_mod * 10.0 + _tile_data.temperature_modifier_1 + _tile_data.temperature_modifier_2
	return result

## 计算指定标签的邻近效应修正值。
##
## 在有效范围 [code](max_y + 1) / distance_factor[/code] 内搜索最近具有指定标签的地块，
## 返回 [code]max((max_y - distance_factor * distance), -1.0)[/code]。
## 若范围内无匹配标签的地块，返回 [code]-1.0[/code]。
func _calc_tag_proximity_modifier(world: Node2D, grid_pos: Vector2i, tag: String, max_y: float, distance_factor: float) -> float:
	var max_range := int(ceil(max_y / distance_factor))
	var nearest_dist := 9999

	for dx: int in range(-max_range, max_range + 1):
		for dy: int in range(-max_range, max_range + 1):
			var dist := absi(dx) + absi(dy)
			if dist > max_range:
				continue
			var check_pos := Vector2i(grid_pos.x + dx, grid_pos.y + dy)
			var tile := WorldUtils.find_tile(world, check_pos)
			if not tile:
				continue
			var td := WorldUtils.get_tile_data(tile)
			if td and tag in td.tags:
				if dist < nearest_dist:
					nearest_dist = dist
					if nearest_dist == 0:
						break

	if nearest_dist >= 9999:
		return 0.0
	return max_y * (1.0 - float(nearest_dist) / float(max_range))

## 校验子类是否设置了有效的身份标识。
func _validate_constants() -> void:
	if tile_type == -1:
		push_error("BaseTile: 子类 %s 未设置 tile_type，请在 _ready() 中赋值" % get_script().resource_path)
	if variant == "":
		push_warning("BaseTile: 子类 %s 未设置 variant，请在 _ready() 中赋值" % get_script().resource_path)
	if display_name == "":
		push_warning("BaseTile: 子类 %s 未设置 display_name，请在 _ready() 中赋值" % get_script().resource_path)
