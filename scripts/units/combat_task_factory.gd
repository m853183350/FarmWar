## CombatTask 静态工厂 — 按指令类型创建战斗任务。
##
## 提供统一的 CombatTask 创建入口，自动从 [code]config/command/command_params.json[/code]
## 读取默认参数。所有方法均为静态方法，无需实例化。
##
## 使用方式：
##   var task: CombatTask = CombatTaskFactory.create(CombatTask.CombatTaskType.GUARD, pos, unit_id)
##   var tasks: Array[CombatTask] = CombatTaskFactory.create_for_squad(squad, pos, units)
class_name CombatTaskFactory
extends RefCounted

# ============================================================
# 3. 常量
# ============================================================

## 默认参数配置文件路径。
const DEFAULT_PARAMS_PATH: String = "res://config/command/command_params.json"

## JSON Loader 引用。
const JSONLoader = preload("res://scripts/utils/json_loader.gd")

# ============================================================
# 6. 私有变量（静态）
# ============================================================

## 缓存的默认参数字典。首次访问时从 JSON 加载。
static var _cached_params: Dictionary = {}
static var _params_loaded: bool = false

# ============================================================
# 9. 公开方法 — 静态工厂
# ============================================================

## 创建单个战斗任务。
##
## [param task_type] 任务类型。
## [param position] 目标位置（世界坐标）。
## [param unit_id] 所属单位 ID。
## [param extra_params] 额外参数字典（会与默认参数合并，显式传入的值优先）。
## [return] 新创建的 CombatTask 实例。
static func create(task_type: CombatTask.CombatTaskType, position: Vector2, unit_id: StringName, extra_params: Dictionary = {}) -> CombatTask:
	_load_params()
	var params: Dictionary = _build_params(task_type, position, extra_params)
	return CombatTask.create(task_type, position, unit_id, params)

## 为小队创建战斗任务。
##
## 同一小队的所有成员共享 squad_id 和 task_center。
## [param squad_config] 小队配置（SquadConfig）。
## [param position] 任务目标位置（世界坐标）。
## [param units] 选中的单位数组。
## [return] 创建好的 CombatTask 数组，与 units 一一对应。
static func create_for_squad(squad_config: Resource, position: Vector2, units: Array[CombatUnitBase]) -> Array[CombatTask]:
	_load_params()
	var tasks: Array[CombatTask] = []
	var squad_id: StringName = squad_config.squad_id as StringName

	# 从默认参数读取 loot_radius
	var loot_radius: float = _cached_params.get("loot_radius", 10.0) as float
	var patrol_radius: float = _cached_params.get("patrol_radius", 5.0) as float

	for unit: CombatUnitBase in units:
		var params: Dictionary = {
			"squad_id": squad_id,
			"task_center": position,
			"loot_radius": loot_radius,
			"patrol_radius": patrol_radius,
		}
		var task: CombatTask = CombatTask.create(CombatTask.CombatTaskType.ATTACK, position, unit.unit_id, params)
		tasks.append(task)

	return tasks

## 创建全局覆盖指令任务。
##
## [param task_type] 任务类型（RALLY / RETREAT / HOLD）。
## [param position] 目标位置（HOLD 时可传 unit.grid_position）。
## [param unit_id] 所属单位 ID。
static func create_global_override(task_type: CombatTask.CombatTaskType, position: Vector2, unit_id: StringName) -> CombatTask:
	assert(task_type in [CombatTask.CombatTaskType.RALLY, CombatTask.CombatTaskType.RETREAT, CombatTask.CombatTaskType.HOLD],
		"全局覆盖只支持 RALLY/RETREAT/HOLD")

	var params: Dictionary = {
		"priority": CombatTask.PRIORITY_GLOBAL_OVERRIDE,
	}
	return create(task_type, position, unit_id, params)

# ============================================================
# 10. 私有方法 — 静态辅助
# ============================================================

## 加载默认参数配置（仅一次，缓存结果）。
static func _load_params() -> void:
	if _params_loaded:
		return
	_params_loaded = true

	if not FileAccess.file_exists(DEFAULT_PARAMS_PATH):
		push_warning("CombatTaskFactory: 默认参数文件不存在 %s" % DEFAULT_PARAMS_PATH)
		return

	var file: FileAccess = FileAccess.open(DEFAULT_PARAMS_PATH, FileAccess.READ)
	if file == null:
		push_warning("CombatTaskFactory: 无法读取 %s" % DEFAULT_PARAMS_PATH)
		return

	var data: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()
	if data != null:
		_cached_params = data

## 构建参数字典（默认值 + 额外参数，显式传入的优先）。
static func _build_params(task_type: CombatTask.CombatTaskType, position: Vector2, extra: Dictionary) -> Dictionary:
	var params: Dictionary = _cached_params.duplicate()

	# 覆盖显式传入的参数
	for key: String in extra:
		params[key] = extra[key]

	# 确保 task_center 默认值
	if not params.has("task_center"):
		params["task_center"] = position

	return params
