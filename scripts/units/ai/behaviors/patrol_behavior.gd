## 巡逻行为 — 在指定区域内游荡巡逻。
##
## 自主模式的可选行为。单位在巡逻中心点周围的半径范围内随机移动，
## 到达巡逻点后短暂等待，然后选取下一个巡逻点。
## 发现敌方单位时切换到追击行为。
class_name PatrolBehavior
extends BaseBehavior

# ============================================================
# 2. 枚举
# ============================================================

enum PatrolState {
	PICK_POINT,    ## 选取下一个巡逻点
	MOVING,        ## 向巡逻点移动中
	WAITING,       ## 到达巡逻点后等待
}

# ============================================================
# 5. 公开变量
# ============================================================

## 巡逻中心点（世界坐标）。默认在 enter 时设置为单位当前位置。
var patrol_center: Vector2 = Vector2.ZERO

## 巡逻半径（格数）。巡逻点在此范围内随机选取。
@export var patrol_radius: float = 5.0

## 到达巡逻点后的等待时间（tick 数）。
@export var wait_ticks: int = 40

# ============================================================
# 6. 私有变量
# ============================================================

var _state: PatrolState = PatrolState.PICK_POINT
var _current_patrol_target: Vector2 = Vector2.ZERO
var _wait_counter: int = 0

# ============================================================
# 8. 生命周期
# ============================================================

func _ready() -> void:
	behavior_name = "Patrol"

# ============================================================
# 9. 公开方法
# ============================================================

func enter(unit: CombatUnitBase) -> void:
	patrol_center = unit.grid_position
	_state = PatrolState.PICK_POINT
	_wait_counter = 0

func exit(_unit: CombatUnitBase) -> void:
	pass

func update(unit: CombatUnitBase, _delta: float) -> void:
	# 检查是否有敌人
	var h: HatredSystem = hatred()
	if h and h.has_threat_target():
		var target: CombatUnitBase = h.get_primary_target()
		if target != null:
			unit.set_target(target)
			switch_to(unit, "Chase")
			return

	# 巡逻状态机
	match _state:
		PatrolState.PICK_POINT:
			_pick_patrol_point(unit)
		PatrolState.MOVING:
			_check_arrival(unit)
		PatrolState.WAITING:
			_wait_counter += 1
			if _wait_counter >= wait_ticks:
				_state = PatrolState.PICK_POINT

func _pick_patrol_point(unit: CombatUnitBase) -> void:
	# 在半径范围内随机选点
	var angle: float = randf() * TAU
	var radius: float = randf() * patrol_radius * unit.TILE_SIZE
	_current_patrol_target = patrol_center + Vector2(cos(angle), sin(angle)) * radius

	# 设置移动目标
	unit.set_move_target_world(_current_patrol_target)
	unit._set_combat_state(CombatUnitBase.CombatState.CHASE)  # 使用 CHASE 状态驱动移动
	_state = PatrolState.MOVING

func _check_arrival(unit: CombatUnitBase) -> void:
	var dist: float = unit.grid_position.distance_to(_current_patrol_target)
	if dist < 4.0:
		# 到达巡逻点
		unit.target_velocity = Vector2.ZERO
		unit._set_combat_state(CombatUnitBase.CombatState.IDLE)
		_state = PatrolState.WAITING
		_wait_counter = 0
