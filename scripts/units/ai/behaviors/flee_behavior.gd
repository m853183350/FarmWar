## 逃跑行为 — 低血量时远离威胁目标。
##
## 在单位生命值低于阈值时由 AIController 触发。
## 计算安全方向（远离仇恨列表中所有敌人），移动指定时间/距离后回到警戒。
class_name FleeBehavior
extends BaseBehavior

# ============================================================
# 5. 公开变量
# ============================================================

## 逃跑持续时间（tick 数）。到期后自动回到警戒。
@export var flee_duration_ticks: int = 60

## 安全距离（格数）。逃到此距离外视为安全。
@export var safe_distance: float = 12.0

# ============================================================
# 6. 私有变量
# ============================================================

var _flee_counter: int = 0
var _flee_direction: Vector2 = Vector2.ZERO

# ============================================================
# 8. 生命周期
# ============================================================

func _ready() -> void:
	behavior_name = "Flee"

# ============================================================
# 9. 公开方法
# ============================================================

func enter(unit: CombatUnitBase) -> void:
	_flee_counter = 0
	_flee_direction = _calculate_flee_direction(unit)

	# 停止正在进行的技能施放
	if unit.active_skill != null:
		unit.interrupt_skill()

func exit(_unit: CombatUnitBase) -> void:
	_flee_direction = Vector2.ZERO

func update(unit: CombatUnitBase, _delta: float) -> void:
	_flee_counter += 1

	# 到期或已到达安全距离 → 回到警戒
	var h: HatredSystem = hatred()
	var all_safe: bool = _is_safe_from_threats(unit, h)

	if _flee_counter >= flee_duration_ticks or all_safe:
		unit.target_velocity = Vector2.ZERO
		unit.set_combat_state(CombatUnitBase.CombatState.IDLE)
		switch_to(unit, "Guard")
		return

	# 持续向安全方向移动
	unit.target_velocity = _flee_direction
	unit.set_combat_state(CombatUnitBase.CombatState.FLEE)

func _calculate_flee_direction(unit: CombatUnitBase) -> Vector2:
	var h: HatredSystem = hatred()
	if h == null:
		return Vector2(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0).normalized()

	# 远离所有仇恨目标的平均方向
	var away_dir: Vector2 = Vector2.ZERO
	var count: int = 0
	for entry: HatredSystem.HatredEntry in h.get_hatred_list():
		if entry.target == null or not is_instance_valid(entry.target):
			continue
		var from_target: Vector2 = unit.grid_position - entry.target.grid_position
		if from_target.length() > 0.01:
			away_dir += from_target.normalized()
			count += 1

	if count > 0:
		return (away_dir / float(count)).normalized()

	# 没有威胁目标时随机方向
	return Vector2(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0).normalized()

func _is_safe_from_threats(unit: CombatUnitBase, h: HatredSystem) -> bool:
	if h == null:
		return true
	for entry: HatredSystem.HatredEntry in h.get_hatred_list():
		if entry.target == null or not is_instance_valid(entry.target):
			continue
		var dist: float = unit.grid_position.distance_to(entry.target.grid_position)
		if dist < safe_distance * unit.TILE_SIZE:
			return false
	return true
