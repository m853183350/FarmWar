## 战斗行为 — 在射程内对目标施放技能。
##
## 从追击行为切换进入。使用 SkillSelector 选择最优技能并施放。
## 在技能施放期间等待其完成（前摇→判定→后摇），完成后继续选择下一个技能。
## 目标死亡或脱离射程时退出。
class_name CombatBehavior
extends BaseBehavior

# ============================================================
# 6. 私有变量
# ============================================================

## 上一 tick 选择的技能（用于检测是否需要重新选择）。
var _last_chosen_skill: Skill = null

# ============================================================
# 8. 生命周期
# ============================================================

func _ready() -> void:
	behavior_name = "Combat"

# ============================================================
# 9. 公开方法
# ============================================================

func enter(unit: CombatUnitBase) -> void:
	# 停止移动
	unit.target_velocity = Vector2.ZERO
	unit._set_combat_state(CombatUnitBase.CombatState.IDLE)
	_last_chosen_skill = null

func exit(_unit: CombatUnitBase) -> void:
	_last_chosen_skill = null

func update(unit: CombatUnitBase, _delta: float) -> void:
	var target: CombatUnitBase = unit.current_target

	# 目标无效 → 回到警戒
	if target == null or not is_instance_valid(target) or not target.is_alive():
		unit.clear_target()
		switch_to(unit, "Guard")
		return

	# 正在施放技能中 → 等待完成
	if unit.active_skill != null:
		# 面向目标
		var dir: Vector2 = target.grid_position - unit.grid_position
		if dir.x != 0.0:
			unit.facing_direction = Vector2(signf(dir.x), 0.0)
		return

	# 检查目标是否还在射程内
	var ss: SkillSelector = skill_selector()
	if ss == null:
		switch_to(unit, "Chase")
		return

	var closest_range: float = ss.get_closest_range(unit)
	if closest_range < 0.0:
		# 没有可用技能，回到追击
		switch_to(unit, "Chase")
		return

	var dist: float = unit.grid_position.distance_to(target.grid_position)
	if dist > closest_range * unit.TILE_SIZE:
		# 目标脱离射程，回到追击
		switch_to(unit, "Chase")
		return

	# 选择技能并施放
	var chosen: Skill = ss.select_skill(unit, target)
	if chosen == null:
		# 无可施放技能（可能在冷却/无蓝），等待或切换到追击
		switch_to(unit, "Chase")
		return

	# 面向目标
	var to_target: Vector2 = target.grid_position - unit.grid_position
	if to_target.x != 0.0:
		unit.facing_direction = Vector2(signf(to_target.x), 0.0)

	# 开始施放技能
	unit.start_skill(chosen)
	_last_chosen_skill = chosen
