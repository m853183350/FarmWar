## 小队任务完成追踪器 — 追踪小队共享任务的完成状态。
##
## 作为 [GameRoot] 的子节点挂载，连接到 [TickSystem] 以定期轮询
## 所有活跃小队的任务完成条件。
##
## 小队任务完成条件（全部满足）：
##   1. 小队未被外部中断（RALLY/RETREAT/HOLD 未覆盖所有成员）
##   2. 所有成员仇恨列表为空（无威胁目标）
##   3. 任务中心 + loot_radius 范围内无 LootItem 节点
##   4. 所有成员已到达目标区域
##
## 轮询策略：每 N tick 扫描一次（默认 10 tick），非每 tick 全图扫描。
class_name SquadTaskTracker
extends Node

# ============================================================
# 3. 常量
# ============================================================

## 轮询间隔（tick 数）。
const SCAN_INTERVAL_TICKS: int = 10

## 到达目标判定距离（像素）。
const ARRIVAL_THRESHOLD: float = 32.0

# ============================================================
# 5. 公开变量
# ============================================================

## 活跃小队追踪记录。{ squad_id: SquadTrackingData }
var active_squads: Dictionary = {}

# ============================================================
# 6. 私有变量
# ============================================================

## 距离上次扫描的 tick 计数器。
var _tick_counter: int = 0

# ============================================================
# 7. @onready 变量
# ============================================================

@onready var _world: Node2D = get_tree().get_first_node_in_group("world") as Node2D

# ============================================================
# 8. 生命周期
# ============================================================

func _ready() -> void:
	if TickSystem:
		TickSystem.tick_elapsed.connect(_on_tick)

func _exit_tree() -> void:
	if TickSystem and TickSystem.tick_elapsed.is_connected(_on_tick):
		TickSystem.tick_elapsed.disconnect(_on_tick)

# ============================================================
# 9. 公开方法
# ============================================================

## 注册一个小队任务。
func register_squad(squad_id: StringName, tasks: Array) -> void:
	if squad_id == &"" or tasks.is_empty():
		return

	var data: SquadTrackingData = SquadTrackingData.new()
	data.squad_id = squad_id
	data.task_ids = []
	for task in tasks:
		data.task_ids.append(task.task_id)

	# 从第一个任务获取共享参数
	var first = tasks[0]
	data.task_center = first.task_center
	data.loot_radius = first.loot_radius
	data.patrol_radius = first.patrol_radius

	active_squads[squad_id] = data

## 注销一个小队。
func unregister_squad(squad_id: StringName) -> void:
	active_squads.erase(squad_id)

## 检查指定小队是否仍在活跃。
func is_squad_active(squad_id: StringName) -> bool:
	return active_squads.has(squad_id)

# ============================================================
# 10. 私有方法 — Tick 轮询
# ============================================================

func _on_tick(_delta: float) -> void:
	_tick_counter += 1
	if _tick_counter < SCAN_INTERVAL_TICKS:
		return
	_tick_counter = 0

	var completed_squads: Array[StringName] = []

	for squad_id: StringName in active_squads.keys():
		var data = active_squads[squad_id] as SquadTrackingData
		if data == null:
			completed_squads.append(squad_id)
			continue

		if _check_squad_complete(data):
			completed_squads.append(squad_id)

	for sid: StringName in completed_squads:
		active_squads.erase(sid)
		if EventBus:
			EventBus.squad_task_completed.emit(sid)

# ============================================================
# 10. 私有方法 — 条件检查
# ============================================================

func _check_squad_complete(data: SquadTrackingData) -> bool:
	if not _all_tasks_active(data):
		return false
	if not _all_members_no_hatred(data):
		return false
	if not _loot_in_range_cleared(data):
		return false
	if not _all_members_arrived(data):
		return false
	return true

func _all_tasks_active(data: SquadTrackingData) -> bool:
	for task_id: int in data.task_ids:
		var task = _find_task_by_id(task_id)
		if task == null:
			continue
		if task.status == CombatTask.CombatTaskStatus.OVERRIDDEN:
			return false
	return true

func _all_members_no_hatred(data: SquadTrackingData) -> bool:
	for task_id: int in data.task_ids:
		var unit = _find_unit_by_task_id(task_id)
		if unit == null:
			continue
		var ai: Node = unit.get_node_or_null("AIController") as Node
		if ai != null and ai.get("hatred_system") != null:
			var hatred: Node = ai.hatred_system as Node
			if hatred.has_method("has_threat_target") and hatred.has_threat_target():
				return false
	return true

func _loot_in_range_cleared(data: SquadTrackingData) -> bool:
	if data.loot_radius <= 0.0:
		return true
	if _world == null:
		return true

	var loot_items: Array[Node] = get_tree().get_nodes_in_group("loot_item")
	for loot: Node2D in loot_items:
		if not is_instance_valid(loot):
			continue
		var dist: float = loot.global_position.distance_to(data.task_center)
		if dist <= data.loot_radius * 64.0:
			return false
	return true

func _all_members_arrived(data: SquadTrackingData) -> bool:
	for task_id: int in data.task_ids:
		var unit = _find_unit_by_task_id(task_id)
		if unit == null:
			continue
		var dist: float = unit.grid_position.distance_to(data.task_center)
		if dist > data.patrol_radius * 64.0 + ARRIVAL_THRESHOLD:
			return false
	return true

# ============================================================
# 10. 私有方法 — 辅助查询
# ============================================================

func _find_task_by_id(task_id: int):
	for unit in UnitManager.get_combat_units():
		if unit.current_task != null and unit.current_task is CombatTask:
			var t = unit.current_task as CombatTask
			if t.task_id == task_id:
				return t
	return null

func _find_unit_by_task_id(task_id: int):
	for unit in UnitManager.get_combat_units():
		if unit.current_task != null and unit.current_task is CombatTask:
			var t = unit.current_task as CombatTask
			if t.task_id == task_id:
				return unit
	return null


# ============================================================
# SquadTrackingData — 小队追踪数据
# ============================================================

class SquadTrackingData extends RefCounted:
	var squad_id: StringName = &""
	var task_ids: Array[int] = []
	var task_center: Vector2 = Vector2.ZERO
	var loot_radius: float = 0.0
	var patrol_radius: float = 5.0
