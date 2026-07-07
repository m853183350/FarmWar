## 警戒行为 — 原地站立并周期性扫描敌人。
##
## 自主模式的默认行为。单位站在当前位置，每 tick 检查仇恨系统。
## 一旦发现敌方单位，立即切换到追击行为。
class_name GuardBehavior
extends BaseBehavior

# ============================================================
# 5. 公开变量
# ============================================================

## 警戒时面朝方向刷新的最小间隔（tick 数）。
@export var look_around_interval: int = 40

# ============================================================
# 6. 私有变量
# ============================================================

var _ticks_elapsed: int = 0

# ============================================================
# 8. 生命周期
# ============================================================

func _ready() -> void:
	behavior_name = "Guard"

# ============================================================
# 9. 公开方法
# ============================================================

func enter(unit: CombatUnitBase) -> void:
	unit.target_velocity = Vector2.ZERO
	unit.set_target(null)
	_ticks_elapsed = 0

func exit(_unit: CombatUnitBase) -> void:
	pass

func update(unit: CombatUnitBase, _delta: float) -> void:
	# 保持静止
	unit.target_velocity = Vector2.ZERO

	# 周期性左右张望（模拟警戒姿态）
	_ticks_elapsed += 1
	if _ticks_elapsed >= look_around_interval:
		_ticks_elapsed = 0
		# 翻转朝向
		unit.facing_direction = -unit.facing_direction

	# 检查仇恨系统是否有目标
	var h: HatredSystem = hatred()
	if h and h.has_threat_target():
		var target: CombatUnitBase = h.get_primary_target()
		if target != null:
			unit.set_target(target)
			switch_to(unit, "Chase")
