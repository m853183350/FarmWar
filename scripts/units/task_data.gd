## 任务数据类 + 任务相关枚举。
##
## TaskData 描述一个待完成的原子操作，包含目标地块、参数、状态和进度。
## 使用 RefCounted 而非 Resource，因为任务只在运行时创建、不需要序列化。
##
## 支持父子任务关系：[member child_tasks] 和 [member parent_task]
## 父任务在其所有子任务完成前不会标记为 COMPLETED。
class_name TaskData
extends RefCounted

# ============================================================
# 2. 枚举 — 任务类型
# ============================================================

## 任务类型枚举。
enum TaskType {
	MOVE,        ## 移动到目标地块（不执行地块操作）
	PLOW,        ## 翻耕地块（DIRT → FARMLAND）
	PLANT,       ## 种植作物（需在 [member params] 中指定 crop_id）
	HARVEST,     ## 收获已成熟的作物
	DIG,         ## 挖掘地块（STONE → DIRT）
	GATHER,      ## 通用采集（砍树、钓鱼等非种植类操作）
	WAIT,        ## 原地等待 N tick（用于时序控制，预留）
}

# ============================================================
# 2. 枚举 — 任务状态
# ============================================================

## 任务状态枚举。
enum TaskStatus {
	PENDING,       ## 等待执行（在队列中排队）
	IN_PROGRESS,   ## 执行中（正在移动或工作）
	COMPLETED,     ## 已完成
	FAILED,        ## 执行失败（地块不可操作、路径不通等）
	CANCELLED,     ## 被取消（玩家手动取消或全局清空）
}

# ============================================================
# 3. 常量
# ============================================================

## 静态自增 ID 计数器。
static var _next_id: int = 0

# ============================================================
# 5. 公开变量
# ============================================================

## 任务唯一 ID（自动分配）。
var task_id: int = 0

## 任务类型。
var task_type: TaskType = TaskType.MOVE

## 目标地块坐标（网格坐标）。
var target_tile: Vector2i = Vector2i.ZERO

## 额外参数（如 crop_id、duration_ticks 等）。
## 不同 TaskType 所需字段见文档 4.4 节。
var params: Dictionary = {}

## 任务状态。
var status: TaskStatus = TaskStatus.PENDING

## 执行进度（0.0 ~ 1.0）。用于需要多 tick 的操作。
var progress: float = 0.0

## 所需总 tick 数。
var total_ticks: int = 0

## 当前已消耗 tick 数。
var elapsed_ticks: int = 0

## 优先级（0 = 普通，数字越大越优先。预留字段）。
var priority: int = 0

## 创建时的游戏 tick 序号。
var created_tick: int = 0

# ============================================================
# 5. 公开变量 — 父子任务
# ============================================================

## 子任务列表。若不为空，父任务需等待所有子任务完成后才算完成。
var child_tasks: Array[TaskData] = []

## 父任务引用。为 null 表示此任务是顶级任务。
var parent_task: TaskData = null

# ============================================================
# 9. 公开方法
# ============================================================

## 创建一个新任务实例。
## [param type] 任务类型。
## [param tile] 目标地块坐标。
## [param task_params] 额外参数字典（可选）。
static func create(type: TaskType, tile: Vector2i, task_params: Dictionary = {}) -> TaskData:
	var task: TaskData = TaskData.new()
	_next_id += 1
	task.task_id = _next_id
	task.task_type = type
	task.target_tile = tile
	task.params = task_params
	task.created_tick = TickSystem.get_tick_count() if TickSystem else 0
	return task

## 添加子任务并设置父子关系。
func add_child_task(child: TaskData) -> void:
	child_tasks.append(child)
	child.parent_task = self

## 检查所有子任务是否都已完成。
func are_child_tasks_completed() -> bool:
	for child: TaskData in child_tasks:
		if child.status != TaskStatus.COMPLETED:
			return false
	return true

## 返回任务类型的可读名称。
func get_type_name() -> String:
	match task_type:
		TaskType.MOVE:
			return "移动"
		TaskType.PLOW:
			return "翻耕"
		TaskType.PLANT:
			return "种植"
		TaskType.HARVEST:
			return "收获"
		TaskType.DIG:
			return "挖掘"
		TaskType.GATHER:
			return "采集"
		TaskType.WAIT:
			return "等待"
		_:
			return "未知"

## 返回任务状态的字符串表示。
func _to_string() -> String:
	return "TaskData(id=%d, type=%s, tile=%s, status=%d, progress=%.2f)" % [
		task_id, get_type_name(), target_tile, status, progress
	]
