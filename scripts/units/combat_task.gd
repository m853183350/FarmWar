## 战斗任务数据类 + 任务相关枚举。
##
## CombatTask 描述一个玩家发出的战斗指令，包含目标位置、任务类型、状态。
## 与 [TaskData] 不同，CombatTask 使用世界坐标（而非网格坐标），且是单任务模式
## （一个单位同一时刻只持有一个 CombatTask），可被全局指令覆盖。
##
## 使用 [RefCounted] 而非 [Resource]，因为任务只在运行时创建、不需要序列化。
##
## 使用方式：
##   var task: CombatTask = CombatTask.create(CombatTask.CombatTaskType.GUARD, position, unit_id)
##   unit.current_task = task
class_name CombatTask
extends RefCounted

# ============================================================
# 2. 枚举 — 任务类型
# ============================================================

## 战斗任务类型枚举。
enum CombatTaskType {
	EXPLORE,     ## 探索指定区域 → 移动到区域中心 → 巡逻游荡 → 自主索敌
	GUARD,       ## 守卫指定位置 → 移动到守卫点 → 原地警戒 → 自动攻击
	ATTACK,      ## 攻击指定目标/区域 → 移动到目标 → 优先攻击 → 清除敌人
	RALLY,       ## 全体集合（全局覆盖）→ 全部移动到集结点 → 待命
	RETREAT,     ## 全体撤退（全局覆盖）→ 全部移动到撤退点 → 途中只还击
	HOLD,        ## 原地待命（全局覆盖）→ 停止当前任务 → 不主动索敌
}

# ============================================================
# 2. 枚举 — 任务状态
# ============================================================

## 战斗任务状态枚举。
enum CombatTaskStatus {
	PENDING,       ## 等待执行
	IN_PROGRESS,   ## 执行中
	COMPLETED,     ## 已完成
	FAILED,        ## 失败（路径不通等）
	OVERRIDDEN,    ## 被全局指令覆盖
}

# ============================================================
# 3. 常量
# ============================================================

## 全局覆盖指令优先级。
const PRIORITY_GLOBAL_OVERRIDE: int = 100

## 普通任务优先级。
const PRIORITY_NORMAL: int = 0

# ============================================================
# 5. 公开变量
# ============================================================

## 任务唯一 ID（静态自增）。
var task_id: int = 0

## 任务类型。
var task_type: CombatTaskType = CombatTaskType.GUARD

## 目标位置（世界坐标）。
var target_position: Vector2 = Vector2.ZERO

## 巡逻半径（EXPLORE / 小队任务中的巡逻范围）。
var patrol_radius: float = 5.0

## 指定攻击目标 ID（ATTACK 模式下可选，空 = 区域内所有敌人）。
var attack_target_id: StringName = &""

## 任务状态。
var status: CombatTaskStatus = CombatTaskStatus.PENDING

## 优先级（0 = 普通，100 = 全局覆盖）。
var priority: int = PRIORITY_NORMAL

## 创建时的游戏 tick 序号。
var created_tick: int = 0

## 所属单位 ID。
var assigned_unit_id: StringName = &""

## 小队 ID（空 = 非小队任务）。
var squad_id: StringName = &""

## 小队任务中心点（世界坐标）。
var task_center: Vector2 = Vector2.ZERO

## 战利品收集半径（小队任务中战利品收集范围）。
var loot_radius: float = 0.0

# ============================================================
# 6. 私有变量
# ============================================================

## 静态自增 ID 计数器。
static var _next_id: int = 0

# ============================================================
# 9. 公开方法 — 静态工厂
# ============================================================

## 创建一个新的战斗任务。
##
## [param task_type] 任务类型。
## [param position] 目标位置（世界坐标）。
## [param unit_id] 所属单位 ID。
## [param params] 额外参数字典（可选键：patrol_radius, attack_target_id, squad_id,
##   task_center, loot_radius, priority）。
static func create(task_type: CombatTaskType, position: Vector2, unit_id: StringName, params: Dictionary = {}) -> CombatTask:
	var task: CombatTask = CombatTask.new()
	_next_id += 1
	task.task_id = _next_id
	task.task_type = task_type
	task.target_position = position
	task.assigned_unit_id = unit_id
	task.created_tick = TickSystem.get_tick_count() if TickSystem else 0

	# 可选参数
	task.patrol_radius = params.get("patrol_radius", 5.0) as float
	task.attack_target_id = params.get("attack_target_id", &"") as StringName
	task.squad_id = params.get("squad_id", &"") as StringName
	task.task_center = params.get("task_center", position) as Vector2
	task.loot_radius = params.get("loot_radius", 0.0) as float
	task.priority = params.get("priority", PRIORITY_NORMAL) as int

	return task

# ============================================================
# 9. 公开方法 — 状态管理
# ============================================================

## 标记任务为执行中。
func mark_in_progress() -> void:
	status = CombatTaskStatus.IN_PROGRESS

## 标记任务为已完成。
func mark_completed() -> void:
	status = CombatTaskStatus.COMPLETED

## 标记任务为失败。
func mark_failed() -> void:
	status = CombatTaskStatus.FAILED

## 标记任务为被全局指令覆盖。
func mark_overridden() -> void:
	status = CombatTaskStatus.OVERRIDDEN

# ============================================================
# 9. 公开方法 — 查询
# ============================================================

## 是否为小队任务。
func is_squad_task() -> bool:
	return squad_id != &""

## 是否为全局覆盖指令。
func is_global_override() -> bool:
	return priority >= PRIORITY_GLOBAL_OVERRIDE

## 返回任务类型名称（调试用）。
func get_type_name() -> String:
	match task_type:
		CombatTaskType.EXPLORE:
			return "探索"
		CombatTaskType.GUARD:
			return "守卫"
		CombatTaskType.ATTACK:
			return "攻击"
		CombatTaskType.RALLY:
			return "集合"
		CombatTaskType.RETREAT:
			return "撤退"
		CombatTaskType.HOLD:
			return "待命"
		_:
			return "未知"

## 返回任务状态名称（调试用）。
func get_status_name() -> String:
	match status:
		CombatTaskStatus.PENDING:
			return "等待"
		CombatTaskStatus.IN_PROGRESS:
			return "执行中"
		CombatTaskStatus.COMPLETED:
			return "已完成"
		CombatTaskStatus.FAILED:
			return "失败"
		CombatTaskStatus.OVERRIDDEN:
			return "被覆盖"
		_:
			return "未知"

## 返回任务可读字符串（调试用）。
func _to_string() -> String:
	return "CombatTask(id=%d, type=%s, status=%s, unit=%s, pos=(%.0f,%.0f))" % [
		task_id, get_type_name(), get_status_name(), assigned_unit_id,
		target_position.x, target_position.y
	]
