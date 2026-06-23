## 采集动作判定器 — 全局 Autoload。
##
## 根据地块类型和内容物判定适用的采集动作，生成 TaskData。
## 采集规则从 [code]config/terrain_config.json[/code] 的 [code]gather_actions[/code] 键加载，
## 与地形配置放在一起便于维护。
##
## 使用方式：
##   [code]GatherActions.determine_and_create_tasks(tiles)[/code]   — 判定采集动作并生成任务
##
## 通过 Autoload 全局访问：[code]GatherActions[/code]
extends Node

const WorldUtils := preload("res://scripts/utils/world_utils.gd")

# ============================================================
# 3. 常量
# ============================================================

## 地形配置文件路径。
const CONFIG_PATH: String = "res://config/terrain_config.json"

# ============================================================
# 6. 私有变量
# ============================================================

## 地形配置缓存（tile_type → terrain_key）。
var _terrain_by_tile_type: Dictionary = {}

## 匹配规则缓存（terrain_key → rules）。
var _rules_by_terrain: Dictionary = {}

## 配置是否已加载。
var _config_loaded: bool = false

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	_load_config()

# ============================================================
# 9. 公开方法
# ============================================================

## 判定所选地块的采集动作，生成 TaskData 数组。
##
## 遍历每个地块，按地形类型匹配采集规则，为匹配成功的地块创建任务。
## 无法匹配任何规则的地块被跳过。
##
## [param tiles] 网格坐标数组（[Array] of [Vector2i]）。
## 返回 [Array] of [TaskData]。
func determine_and_create_tasks(tiles: Array[Vector2i]) -> Array[TaskData]:
	var tasks: Array[TaskData] = []
	var world: Node2D = WorldUtils.get_world()
	if world == null:
		push_error("GatherActions: 无法获取 world 节点")
		return tasks

	for grid_pos: Vector2i in tiles:
		var tile: Node2D = WorldUtils.find_tile(world, grid_pos)
		if tile == null:
			continue
		var rule: Dictionary = _match_rule(tile)
		if rule.is_empty():
			continue
		var task_type: int = _parse_task_type(rule.get("task_type", "GATHER"))
		var params: Dictionary = {
			"gather_action": rule.get("gather_action", ""),
			"rule_id": rule.get("id", ""),
		}
		tasks.append(TaskData.create(task_type, grid_pos, params))

	# 发出采集触发事件（供 UI 反馈/音效）
	if not tasks.is_empty() and EventBus:
		for task: TaskData in tasks:
			var action: StringName = task.params.get("gather_action", "")
			if not action.is_empty():
				EventBus.gather_action_triggered.emit(action, tiles)
				break

	return tasks

# ============================================================
# 10. 私有方法 — 配置加载
# ============================================================

## 加载 terrain_config.json，提取 gather_actions 构建匹配规则。
func _load_config() -> void:
	if _config_loaded:
		return

	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("GatherActions: 配置文件不存在: %s" % CONFIG_PATH)
		_config_loaded = true
		return

	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("GatherActions: 无法打开配置文件: %s" % CONFIG_PATH)
		_config_loaded = true
		return

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("GatherActions: JSON 解析失败 (行 %d): %s" % [json.get_error_line(), json.get_error_message()])
		_config_loaded = true
		return

	var data: Variant = json.data
	if not data is Dictionary:
		push_error("GatherActions: 配置文件顶层应为 JSON 对象")
		_config_loaded = true
		return

	var config: Dictionary = data as Dictionary

	# 新格式：地块类型在 "tiles" 键下
	var tiles_raw: Variant = config.get("tiles", {})
	var tiles_dict: Dictionary = {}
	if tiles_raw is Dictionary:
		tiles_dict = tiles_raw as Dictionary
	else:
		# 兼容旧格式（无 "tiles" 包裹）
		tiles_dict = config

	for terrain_key: String in tiles_dict:
		var terrain_data: Variant = tiles_dict[terrain_key]
		if not terrain_data is Dictionary:
			continue
		var terrain_dict: Dictionary = terrain_data as Dictionary

		# 建立 tile_type → terrain_key 的反向映射（兼容 TSCN 和程序化地块）
		var tile_type: int = int(terrain_dict.get("tile_type", -1))
		if tile_type >= 0:
			_terrain_by_tile_type[tile_type] = terrain_key

		# 提取 gather_actions 规则
		var actions: Array = []
		var raw_actions: Variant = terrain_dict.get("gather_actions", [])
		if raw_actions is Array:
			actions = raw_actions as Array
		_rules_by_terrain[terrain_key] = actions

	_config_loaded = true

# ============================================================
# 10. 私有方法 — 规则匹配
# ============================================================

## 遍历规则列表，返回第一个匹配的规则（优先级 = 数组顺序）。
func _match_rule(tile: Node2D) -> Dictionary:
	var terrain_key: String = _resolve_terrain_key(tile)
	if terrain_key.is_empty():
		return {}

	var rules: Array = []
	var raw: Variant = _rules_by_terrain.get(terrain_key, [])
	if raw is Array:
		rules = raw as Array

	for rule: Dictionary in rules:
		if _check_conditions(tile, rule.get("conditions", [])):
			return rule

	return {}

## 通过地块的 tile_type 反向查找地形类型键。
## 兼容 TSCN 实例化和程序化创建的地块（不再依赖 scene_file_path）。
func _resolve_terrain_key(tile: Node2D) -> String:
	# 通过 TileInfo.tile_type 查找
	if tile.has_method("get_tile_data"):
		var td: Resource = tile.get_tile_data()
		if td and _terrain_by_tile_type.has(td.tile_type):
			return _terrain_by_tile_type[td.tile_type]
	elif tile.has_meta("tile_data"):
		var td: Resource = tile.get_meta("tile_data")
		if td and _terrain_by_tile_type.has(td.tile_type):
			return _terrain_by_tile_type[td.tile_type]

	# 降级：scene_file_path 方式（仅兼容尚未迁移的旧地块数据）
	var scene_path: String = tile.scene_file_path
	if not scene_path.is_empty():
		for key: String in _rules_by_terrain:
			if not _terrain_by_tile_type.values().has(key):
				return key

	return ""

## 检查地块是否满足所有条件（AND 逻辑）。
func _check_conditions(tile: Node2D, conditions: Array) -> bool:
	for cond in conditions:
		var cond_dict: Dictionary = cond as Dictionary
		var cond_type: String = cond_dict.get("type", "")
		match cond_type:
			"has_occupant":
				var occupant_class: String = cond_dict.get("value", "")
				if not _has_occupant_of_class(tile, occupant_class):
					return false
			"property":
				var key: String = cond_dict.get("key", "")
				var expected_value: Variant = cond_dict.get("value")
				if not _check_property(tile, key, expected_value):
					return false
	return true

## 检查地块是否有指定类型的 occupants。
func _has_occupant_of_class(tile: Node2D, occupant_class: String) -> bool:
	if not tile.has_method("has_occupant_of_type"):
		return false
	return tile.has_occupant_of_type(occupant_class)

## 检查地块的元数据属性是否匹配期望值。
func _check_property(tile: Node2D, key: String, expected_value: Variant) -> bool:
	var actual: Variant = tile.get_meta(key, null)
	if actual == null:
		return false
	return actual == expected_value

# ============================================================
# 10. 私有方法 — 任务类型解析
# ============================================================

## 将字符串任务类型转换为 TaskData.TaskType 枚举值。
func _parse_task_type(type_str: String) -> int:
	match type_str:
		"GATHER":
			return TaskData.TaskType.GATHER
		"DIG":
			return TaskData.TaskType.DIG
		"CHOP":
			return TaskData.TaskType.GATHER  # 砍伐归为通用采集
		_:
			return TaskData.TaskType.GATHER

# ============================================================
# 10. 私有方法 — 世界与地块查找
# ============================================================

# _resolve_world 和 _find_tile 已迁移至 WorldUtils
