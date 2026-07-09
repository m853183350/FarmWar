## 追击行为 — 向当前目标移动并尝试进入技能射程。
##
## 当仇恨系统返回有效目标时进入此行为。
## 持续向目标位置移动，检测是否已进入可用技能的射程。
## 进入射程后切换到战斗行为，目标丢失则回到警戒行为。
class_name ChaseBehavior
extends BaseBehavior

# ============================================================
# 3. 常量
# ============================================================

## 路径更新间隔（tick 数）。避免每 tick 重新寻路。
const PATH_UPDATE_INTERVAL: int = 10

## 到达目标判定距离（像素）。
const ARRIVAL_THRESHOLD: float = 4.0

# ============================================================
# 6. 私有变量
# ============================================================

var _ticks_since_path_update: int = 0

# ============================================================
# 8. 生命周期
# ============================================================

func _ready() -> void:
	behavior_name = "Chase"

# ============================================================
# 9. 公开方法
# ============================================================

func enter(unit: CombatUnitBase) -> void:
	_ticks_since_path_update = PATH_UPDATE_INTERVAL  # 立即更新路径

func exit(_unit: CombatUnitBase) -> void:
	pass

func update(unit: CombatUnitBase, _delta: float) -> void:
	var target: CombatUnitBase = unit.current_target

	# 目标无效 → 回到警戒
	if target == null or not is_instance_valid(target) or not target.is_alive():
		unit.clear_target()
		switch_to(unit, "Guard")
		return

	# 检查仇恨系统中目标是否已超出追击范围
	var h: HatredSystem = hatred()
	if h:
		var primary: CombatUnitBase = h.get_primary_target()
		if primary != target:
			# 有更高威胁的目标，切换
			unit.set_target(primary)
			target = primary
		if not h.has_threat_target():
			# 目标已不在仇恨列表中（超出追击范围）
			unit.clear_target()
			switch_to(unit, "Guard")
			return

	# 检查是否已进入技能射程
	var ss: SkillSelector = skill_selector()
	if ss:
		var closest_range: float = ss.get_closest_range(unit)
		if closest_range > 0.0:
			var dist: float = unit.grid_position.distance_to(target.grid_position)
			if dist <= closest_range * unit.TILE_SIZE:
				# 进入射程，切换到战斗
				switch_to(unit, "Combat")
				return

	# 更新移动目标（定期重新寻路）
	_ticks_since_path_update += 1
	if _ticks_since_path_update >= PATH_UPDATE_INTERVAL:
		_ticks_since_path_update = 0
		# 设置移动目标为敌方当前位置
		unit.set_move_target_world(target.grid_position)

	# 移到敌人位置（直接向目标移动）
	# CombatUnitBase 的 physics 层会通过 target_velocity 执行移动
	var dir: Vector2 = target.grid_position - unit.grid_position
	var dist_to_target: float = dir.length()
	if dist_to_target > ARRIVAL_THRESHOLD:
		unit.target_velocity = dir.normalized()
	else:
		unit.target_velocity = Vector2.ZERO

	# 设置战斗状态为 CHASE（驱动 Physics 层移动）
	unit.set_combat_state(CombatUnitBase.CombatState.CHASE)

	# 面向目标
	if dir.x != 0.0:
		unit.facing_direction = Vector2(signf(dir.x), 0.0)
