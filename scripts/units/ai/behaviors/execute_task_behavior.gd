## 任务执行行为 — 执行 [CombatTask] 指定的目标。
##
## 所有任务模式下的最高优先级行为。
## 当 [member CombatUnitBase.current_task] 不为 null 时，
## AIController 会自动切换到本行为。
##
## 支持两种任务模式：
##   - 普通任务：到达目标 → 标记完成 → 切 Guard
##   - 小队任务（有 squad_id）：
##     到达目标 → 巡逻 task_center + patrol_radius → 主动索敌战斗 →
##     战斗结束 → 收集战利品 → 检查完成条件 → 完成后切 Guard
##
## Phase 4 完整实现，替换 Phase 3 的 duck-typing 访问。
class_name ExecuteTaskBehavior
extends BaseBehavior

# ============================================================
# 3. 常量
# ============================================================

## 到达目标判定距离（像素）。
const ARRIVAL_THRESHOLD: float = 8.0

## 路径更新间隔（tick 数）。
const PATH_UPDATE_INTERVAL: int = 20

## 小队模式自卫距离（格）。普通任务在此距离内遇敌才自卫。
const SELF_DEFENSE_RANGE: float = 5.0

## 小队模式索敌范围（格）。巡逻状态下主动索敌。
const PATROL_ALERT_RANGE: float = 10.0

## 小队模式下巡逻方向变更间隔（tick）。
const PATROL_DIRECTION_CHANGE_INTERVAL: int = 60

# ============================================================
# 6. 私有变量
# ============================================================

var _ticks_since_path_update: int = 0
var _target_position: Vector2 = Vector2.ZERO
var _task: CombatTask = null

## 小队模式状态。
var _squad_arrived: bool = false
var _patrol_direction: Vector2 = Vector2.ZERO
var _patrol_ticks: int = 0

# ============================================================
# 8. 生命周期
# ============================================================

func _ready() -> void:
	behavior_name = "ExecuteTask"

# ============================================================
# 9. 公开方法
# ============================================================

func enter(unit: CombatUnitBase) -> void:
	_ticks_since_path_update = PATH_UPDATE_INTERVAL
	_squad_arrived = false
	_patrol_ticks = 0
	_patrol_direction = Vector2.ZERO

	# 获取正式的 CombatTask
	_task = unit.current_task as CombatTask
	if _task == null:
		# 无有效任务，回到 Guard
		switch_to(unit, "Guard")
		return

	_target_position = _task.target_position

	# HOLD 指令：目标就是当前位置
	if _task.task_type == CombatTask.CombatTaskType.HOLD:
		_target_position = unit.grid_position

func exit(_unit: CombatUnitBase) -> void:
	_task = null

func update(unit: CombatUnitBase, _delta: float) -> void:
	# 任务无效
	if unit.current_task == null:
		_complete_and_switch(unit, "Guard")
		return

	_task = unit.current_task as CombatTask
	if _task == null:
		_complete_and_switch(unit, "Guard")
		return

	# 任务已被覆盖
	if _task.status == CombatTask.CombatTaskStatus.OVERRIDDEN:
		switch_to(unit, "Guard")
		return

	# HOLD：原地停留，自卫但不移动
	if _task.task_type == CombatTask.CombatTaskType.HOLD:
		_update_hold(unit)
		return

	# RETREAT：向撤退点移动，途中只自卫
	if _task.task_type == CombatTask.CombatTaskType.RETREAT:
		_update_move_to_target(unit, _target_position, true)
		return

	# 小队任务已到达 → 巡逻模式
	if _task.is_squad_task() and _squad_arrived:
		_update_squad_patrol(unit)
		return

	# 检查到达目标
	var dist: float = unit.grid_position.distance_to(_target_position)
	if dist < ARRIVAL_THRESHOLD:
		_on_arrived_at_target(unit)
		return

	# 移动阶段：途中遇敌处理
	var h: HatredSystem = hatred()
	var is_retreating: bool = _task.task_type == CombatTask.CombatTaskType.RETREAT

	if h and h.has_threat_target():
		if is_retreating:
			# 撤退：只自卫（很近才还击）
			if _is_enemy_in_self_defense_range(unit, h):
				var target: CombatUnitBase = h.get_primary_target()
				if target != null:
					unit.set_target(target)
					switch_to(unit, "Chase")
					return
		elif _task.is_squad_task():
			# 小队任务：主动索敌
			var target: CombatUnitBase = h.get_primary_target()
			if target != null:
				unit.set_target(target)
				switch_to(unit, "Chase")
				return
		else:
			# 普通任务：自卫（很近才还击）
			if _is_enemy_in_self_defense_range(unit, h):
				var target: CombatUnitBase = h.get_primary_target()
				if target != null:
					unit.set_target(target)
					switch_to(unit, "Chase")
					return

	# 继续移动
	_update_move_to_target(unit, _target_position, is_retreating)

# ============================================================
# 10. 私有方法 — 移动
# ============================================================

## 向目标位置移动。
func _update_move_to_target(unit: CombatUnitBase, target_pos: Vector2, _retreating: bool) -> void:
	_ticks_since_path_update += 1
	if _ticks_since_path_update >= PATH_UPDATE_INTERVAL:
		_ticks_since_path_update = 0
		unit.set_move_target_world(target_pos)

	var dir: Vector2 = target_pos - unit.grid_position
	if dir.length() > ARRIVAL_THRESHOLD:
		unit.target_velocity = dir.normalized()
		unit._set_combat_state(CombatUnitBase.CombatState.CHASE)

	if dir.x != 0.0:
		unit.facing_direction = Vector2(signf(dir.x), 0.0)

## HOLD 指令：原地不动，减速到零，但会自卫。
func _update_hold(unit: CombatUnitBase) -> void:
	unit.target_velocity = Vector2.ZERO
	unit._set_combat_state(CombatUnitBase.CombatState.IDLE)

	# 自卫：被攻击时还击
	var h: HatredSystem = hatred()
	if h and h.has_threat_target() and _is_enemy_in_self_defense_range(unit, h):
		var target: CombatUnitBase = h.get_primary_target()
		if target != null:
			unit.set_target(target)
			switch_to(unit, "Chase")

# ============================================================
# 10. 私有方法 — 到达处理
# ============================================================

## 到达目标位置时调用。
func _on_arrived_at_target(unit: CombatUnitBase) -> void:
	unit.target_velocity = Vector2.ZERO

	if _task.is_squad_task():
		# 小队任务：进入巡逻模式
		_squad_arrived = true
		unit._set_combat_state(CombatUnitBase.CombatState.IDLE)
		if _patrol_direction == Vector2.ZERO:
			_patrol_direction = Vector2.RIGHT.rotated(randf() * TAU)
	else:
		# 普通任务：到达即完成
		_task.mark_completed()
		if EventBus:
			EventBus.combat_task_completed.emit(unit.unit_id, _task.task_id)
		_complete_and_switch(unit, "Guard")

# ============================================================
# 10. 私有方法 — 小队巡逻
# ============================================================

## 小队任务巡逻模式：在 task_center + patrol_radius 范围内巡逻。
func _update_squad_patrol(unit: CombatUnitBase) -> void:
	# 更新仇恨系统（主动索敌）
	var h: HatredSystem = hatred()
	if h:
		h.update_hatred(unit, 0)

	# 有仇恨目标 → 切换战斗
	if h and h.has_threat_target():
		var target: CombatUnitBase = h.get_primary_target()
		if target != null:
			unit.set_target(target)
			switch_to(unit, "Chase")
			return

	# 检查小队任务完成条件
	if _check_squad_complete(unit):
		_task.mark_completed()
		if EventBus:
			EventBus.combat_task_completed.emit(unit.unit_id, _task.task_id)
		# 先切 Loot（如果有），再切 Guard
		_complete_and_switch(unit, "Guard")
		return

	# 巡逻：沿 patrol_direction 移动
	_patrol_ticks += 1
	if _patrol_ticks >= PATROL_DIRECTION_CHANGE_INTERVAL:
		_patrol_ticks = 0
		# 随机新方向
		_patrol_direction = Vector2.RIGHT.rotated(randf() * TAU)

	# 计算巡逻目标点
	var patrol_target: Vector2 = _task.task_center + _patrol_direction * (_task.patrol_radius * 64.0 * 0.7)
	# 如果巡逻目标超出范围，反方向
	var dist_from_center: float = unit.grid_position.distance_to(_task.task_center)
	if dist_from_center > _task.patrol_radius * 64.0:
		# 超出范围，向中心移动
		patrol_target = _task.task_center

	_update_move_to_target(unit, patrol_target, false)

## 检查小队是否满足完成条件（委托给 SquadTaskTracker）。
func _check_squad_complete(_unit: CombatUnitBase) -> bool:
	if _task == null or not _task.is_squad_task():
		return false

	# 检查核心条件：仇恨为空
	var h: HatredSystem = hatred()
	if h and h.has_threat_target():
		return false

	# 如果 SquadTaskTracker 标记小队已完成
	# （SquadTaskTracker 负责更全面的检查：全部到达 + 战利品清空）
	# 这里只做基本检查避免过度耦合
	return false  # 单靠仇恨无法判断完成，等待 SquadTaskTracker 通知

# ============================================================
# 10. 私有方法 — 辅助
# ============================================================

## 完成任务并切换到指定行为。
func _complete_and_switch(unit: CombatUnitBase, behavior_name: String) -> void:
	unit.current_task = null
	_task = null
	switch_to(unit, behavior_name)

## 敌人是否在自卫范围内（普通任务 / 撤退 / HOLD 用）。
func _is_enemy_in_self_defense_range(unit: CombatUnitBase, h: HatredSystem) -> bool:
	if not h.has_threat_target():
		return false
	var primary: CombatUnitBase = h.get_primary_target()
	if primary == null:
		return false
	var dist: float = unit.grid_position.distance_to(primary.grid_position)
	return dist < SELF_DEFENSE_RANGE * unit.TILE_SIZE
