## 指令系统 — 玩家高层指令的入口和编排中枢。
##
## 作为 [GameRoot] 的子节点挂载。负责：
##   1. 接收玩家指令（小队指令 / 通用指令 / 全局覆盖）
##   2. 调用 [UnitSelection] 自动选兵
##   3. 调用 [CombatTaskFactory] 创建任务
##   4. 分发任务到单位
##   5. 发出 EventBus 信号供其他系统（UI、音效等）响应
##
## 使用方式：
##   # 从 UI 调用
##   command_system.issue_squad_command("assault_1", tile_position)
##   command_system.issue_global_override(CombatTask.CombatTaskType.RALLY, position)
class_name CommandSystem
extends Node

# ============================================================
# 3. 常量
# ============================================================

## SquadConfig 类引用。
const SquadConfigClass = preload("res://scripts/game/squad_config.gd")

## CombatTaskFactory 引用。
const TaskFactoryClass = preload("res://scripts/units/combat_task_factory.gd")

# ============================================================
# 1. 信号
# ============================================================

## 指令发出时广播（本地通知，供 UI 反馈使用）。
signal command_issued(command_type: int, params: Dictionary)

## 小队指令发出时广播。
signal squad_command_issued(squad_id: StringName, position: Vector2, unit_count: int)

# ============================================================
# 7. @onready 变量
# ============================================================

@onready var _squad_manager: SquadManager = _find_sibling("SquadManager") as SquadManager
@onready var _squad_task_tracker: SquadTaskTracker = _find_sibling("SquadTaskTracker") as SquadTaskTracker

# ============================================================
# 9. 公开方法 — 小队指令
# ============================================================

## 发出小队指令（主要玩家入口 — 对应 "派遣部队" 流程）。
##
## 流程：查找小队配置 → 选兵 → 创建任务 → 分发 → 追踪。
## [param squad_id] 小队 ID（内置或自定义）。
## [param position] 目标位置（世界坐标）。
## [return] 选中的单位数量。返回 0 表示无可用单位或小队不存在。
func issue_squad_command(squad_id: StringName, position: Vector2) -> int:
	# 查找小队配置
	var squad_config: SquadConfig = null
	if _squad_manager:
		squad_config = _squad_manager.get_squad(squad_id)
	if squad_config == null:
		push_warning("CommandSystem: 小队 '%s' 不存在" % squad_id)
		return 0

	# 自动选兵
	var selected: Array[CombatUnitBase] = UnitSelection.select_for_squad(squad_config, position, 0)
	if selected.is_empty():
		return 0

	# 创建小队任务
	var tasks: Array[CombatTask] = TaskFactoryClass.create_for_squad(squad_config, position, selected)

	# 分发任务到单位
	_distribute_tasks(tasks, selected)

	# 注册小队追踪（非内置小队才追踪完成条件）
	if not squad_config.is_builtin and _squad_task_tracker:
		_squad_task_tracker.register_squad(squad_id, tasks)

	# 广播信号
	if EventBus:
		EventBus.command_issued.emit(CombatTask.CombatTaskType.ATTACK, {
			"position": position,
			"count": selected.size(),
			"squad_id": squad_id,
		})

	squad_command_issued.emit(squad_id, position, selected.size())
	return selected.size()

# ============================================================
# 9. 公开方法 — 通用指令
# ============================================================

## 发出通用高层指令。
##
## [param command_type] 指令类型（EXPLORE / GUARD / ATTACK）。
## [param position] 目标位置（世界坐标）。
## [param unit_count] 所需兵力数量（-1 = 所有可用）。
## [param unit_type_filter] 单位类型过滤（"" = 所有战斗单位）。
## [return] 选中的单位数量。
func issue_command(
	command_type: CombatTask.CombatTaskType,
	position: Vector2,
	unit_count: int = -1,
	unit_type_filter: StringName = &""
) -> int:
	# 自动选兵
	var selected: Array[CombatUnitBase] = UnitSelection.select_units(
		position, unit_count, unit_type_filter, 0, true, true
	)
	if selected.is_empty():
		return 0

	# 为每个选中单位创建任务
	var tasks: Array[CombatTask] = []
	for unit: CombatUnitBase in selected:
		var task: CombatTask = TaskFactoryClass.create(command_type, position, unit.unit_id)
		tasks.append(task)

	# 分发
	_distribute_tasks(tasks, selected)

	# 广播信号
	if EventBus:
		EventBus.command_issued.emit(command_type, {
			"position": position,
			"count": selected.size(),
			"unit_type_filter": unit_type_filter,
		})

	command_issued.emit(command_type, {"position": position, "count": selected.size()})
	return selected.size()

# ============================================================
# 9. 公开方法 — 全局覆盖指令
# ============================================================

## 发出全局覆盖指令（RALLY / RETREAT / HOLD）。
##
## 不通过选兵机制——通过 EventBus 信号广播，所有友方单位的
## AIController 收到信号后覆盖当前任务。
## [param command_type] 指令类型（RALLY / RETREAT / HOLD）。
## [param position] 目标位置（HOLD 时忽略）。
func issue_global_override(command_type: CombatTask.CombatTaskType, position: Vector2 = Vector2.ZERO) -> void:
	assert(command_type in [CombatTask.CombatTaskType.RALLY,
		CombatTask.CombatTaskType.RETREAT,
		CombatTask.CombatTaskType.HOLD],
		"全局覆盖只支持 RALLY/RETREAT/HOLD，收到 %d" % command_type)

	match command_type:
		CombatTask.CombatTaskType.RALLY:
			if EventBus:
				EventBus.command_override_rally.emit(position)
		CombatTask.CombatTaskType.RETREAT:
			if EventBus:
				EventBus.command_override_retreat.emit(position)
		CombatTask.CombatTaskType.HOLD:
			if EventBus:
				EventBus.command_override_hold.emit()

	if EventBus:
		EventBus.command_issued.emit(command_type, {"position": position})

	command_issued.emit(command_type, {"position": position})

# ============================================================
# 10. 私有方法 — 任务分发
# ============================================================

## 分发任务到选中的单位。
func _distribute_tasks(tasks: Array[CombatTask], units: Array[CombatUnitBase]) -> void:
	for i: int in range(tasks.size()):
		var task: CombatTask = tasks[i]
		var unit: CombatUnitBase = units[i]

		# 覆盖单位当前任务（如果有）
		if unit.current_task != null:
			var old_task: CombatTask = unit.current_task as CombatTask
			old_task.mark_overridden()
			if EventBus:
				EventBus.combat_task_overridden.emit(unit.unit_id, old_task.task_id)

		# 分配新任务
		task.mark_in_progress()
		unit.current_task = task

		if EventBus:
			EventBus.combat_task_assigned.emit(unit.unit_id, task.task_id)

# ============================================================
# 10. 私有方法 — 辅助
# ============================================================

## 在兄弟节点中查找指定类型。
func _find_sibling(type_name: String) -> Node:
	var parent: Node = get_parent()
	if parent == null:
		return null
	for child: Node in parent.get_children():
		if child is SquadManager and type_name == "SquadManager":
			return child
		if child is SquadTaskTracker and type_name == "SquadTaskTracker":
			return child
	return null
