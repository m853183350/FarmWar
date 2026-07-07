## 技能选择器 — 从可用技能中为 AI 选出最优技能执行。
##
## 作为 [AIController] 的子节点挂载在战斗单位上。
## 由 AIController / CombatBehavior 调用，每 tick 仅当无技能执行中时触发。
##
## 选择策略：
##   1. 过滤：射程内 + 冷却完成 + 法力足够
##   2. 排序：ai_priority 降序 → 普攻优先 → 法力消耗低优先
##   3. 斩杀：目标血量 < 阈值时优先使用普攻节约法力
class_name SkillSelector
extends Node

# ============================================================
# 3. 常量
# ============================================================

## 斩杀阈值。目标血量低于此值（绝对值）时优先使用普攻。
const EXECUTE_THRESHOLD: float = 20.0

# ============================================================
# 5. 公开变量
# ============================================================

## 是否启用斩杀逻辑（低血量时优先普攻节约法力）。
@export var enable_execute_logic: bool = true

## 斩杀时是否要求普攻的预期伤害足够斩杀目标。
@export var require_lethal_for_execute: bool = false

# ============================================================
# 9. 公开方法
# ============================================================

## 从可用技能中选择最优技能执行。
##
## [param unit] 施放技能的战斗单位。
## [param target] 攻击目标。
## [return] 选中的技能，无可用技能返回 null。
func select_skill(unit: CombatUnitBase, target: CombatUnitBase) -> Skill:
	if unit == null or target == null:
		return null

	var available: Array[Skill] = unit.get_available_skills()
	if available.is_empty():
		return null

	# 计算到目标的距离
	var dist: float = unit.grid_position.distance_to(target.grid_position)

	# 过滤：只保留射程内的技能
	var candidates: Array[Skill] = []
	for skill: Skill in available:
		if dist <= skill.range * unit.TILE_SIZE:
			candidates.append(skill)

	if candidates.is_empty():
		return null  # 所有技能都打不到，需要靠近目标

	# 斩杀逻辑：目标血量很低时优先普攻
	if enable_execute_logic and target.current_health <= EXECUTE_THRESHOLD:
		for skill: Skill in candidates:
			if not skill.is_basic_attack:
				continue
			if require_lethal_for_execute:
				# 计算预期伤害是否足够斩杀
				var attack_power: float = unit.get_attack_power()
				var expected: float = (skill.base_damage + attack_power) * skill.damage_multiplier
				if expected >= target.current_health:
					return skill
			else:
				return skill

	# 排序：ai_priority 降序 → 普攻优先 → 法力消耗低优先
	candidates.sort_custom(func(a: Skill, b: Skill) -> bool:
		if a.ai_priority != b.ai_priority:
			return a.ai_priority > b.ai_priority
		# 同优先级时普攻优先（省蓝）
		if a.is_basic_attack != b.is_basic_attack:
			return a.is_basic_attack
		# 都普攻或都技能时，法力消耗低的优先
		return a.mana_cost < b.mana_cost
	)

	return candidates[0]

## 获取射程内可用的技能列表（不过滤优先级，用于调试）。
func get_skills_in_range(unit: CombatUnitBase, target: CombatUnitBase) -> Array[Skill]:
	if unit == null or target == null:
		return []

	var dist: float = unit.grid_position.distance_to(target.grid_position)
	var result: Array[Skill] = []
	for skill: Skill in unit.get_available_skills():
		if dist <= skill.range * unit.TILE_SIZE:
			result.append(skill)
	return result

## 获取距离目标最近的可用技能射程。
## 返回射程（格数），无可用技能时返回 -1。
func get_closest_range(unit: CombatUnitBase) -> float:
	if unit == null:
		return -1.0

	var closest: float = INF
	var available: Array[Skill] = unit.get_available_skills()
	for skill: Skill in available:
		if skill.range < closest:
			closest = skill.range
	return closest if closest < INF else -1.0
