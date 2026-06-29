## 战斗计算工具类，提供伤害公式、暴击判定等静态方法。
##
## 所有方法均为纯函数，不依赖任何外部状态。
## 可在 Tick 层和 Physics 层安全调用。
##
## 使用方式：
##   var result: Dictionary = CombatSystem.calculate_damage(skill, attack_power, crit_chance, crit_multiplier, armor, magic_resist)
class_name CombatSystem
extends RefCounted

# ============================================================
# 3. 常量
# ============================================================

## 护甲减免公式的分母常量。
## 护甲减伤比例 = ARMOR_FACTOR_BASE / (ARMOR_FACTOR_BASE + armor)
## 100 意味着 100 护甲 = 50% 减伤。
const ARMOR_FACTOR_BASE: float = 100.0

## 默认暴击倍率。
const DEFAULT_CRIT_MULTIPLIER: float = 1.5

# ============================================================
# 9. 公开方法 — 伤害计算
# ============================================================

## 计算一次技能攻击的完整伤害结果。
##
## [param skill] 使用的技能 Resource。
## [param attack_power] 攻击者的攻击力（含 Buff 加成后的值）。
## [param crit_chance] 攻击者的暴击率（0.0 ~ 1.0）。
## [param crit_multiplier] 攻击者的暴击倍率（默认 1.5）。
## [param armor] 防御者的护甲值。
## [param magic_resist] 防御者的魔抗值。
##
## 返回 Dictionary：
##   - "raw_damage": float — 暴击/倍率计算后的原始伤害
##   - "effective_damage": float — 经过抗性减免后的最终伤害
##   - "is_crit": bool — 是否暴击
##   - "damage_type": int — 使用的伤害类型
##   - "armor_reduction": float — 护甲减免的伤害量
static func calculate_damage(
	skill: Skill,
	attack_power: float,
	crit_chance: float = 0.05,
	crit_multiplier: float = DEFAULT_CRIT_MULTIPLIER,
	armor: float = 0.0,
	magic_resist: float = 0.0
) -> Dictionary:
	# 1. 原始伤害 = (技能基础伤害 + 攻击力) × 技能倍率
	var raw_damage: float = (skill.base_damage + attack_power) * skill.damage_multiplier

	# 2. 暴击判定
	var is_crit: bool = false
	if crit_chance > 0.0:
		is_crit = randf() < crit_chance
	if is_crit:
		raw_damage *= crit_multiplier

	# 3. 抗性减免
	var effective_damage: float = raw_damage
	var armor_reduction: float = 0.0

	match skill.damage_type:
		Skill.DamageType.PHYSICAL:
			effective_damage = _apply_armor(raw_damage, armor)
			armor_reduction = raw_damage - effective_damage
		Skill.DamageType.MAGIC:
			effective_damage = _apply_armor(raw_damage, magic_resist)
			armor_reduction = raw_damage - effective_damage
		Skill.DamageType.TRUE:
			# 真实伤害无视抗性
			effective_damage = raw_damage
			armor_reduction = 0.0

	# 确保最少造成 1 点伤害（除非原始伤害为 0）
	if raw_damage > 0.0:
		effective_damage = maxf(1.0, effective_damage)

	return {
		"raw_damage": raw_damage,
		"effective_damage": effective_damage,
		"is_crit": is_crit,
		"damage_type": skill.damage_type,
		"armor_reduction": armor_reduction,
	}

## 计算护甲/魔抗减免。
## 公式：damage × ARMOR_FACTOR_BASE / (ARMOR_FACTOR_BASE + resistance)
## [param damage] 减免前的伤害。
## [param resistance] 抗性值（护甲或魔抗）。
static func _apply_armor(damage: float, resistance: float) -> float:
	if resistance < 0.0:
		# 负抗性 → 伤害加深
		return damage * (1.0 + absf(resistance) / ARMOR_FACTOR_BASE)
	return damage * ARMOR_FACTOR_BASE / (ARMOR_FACTOR_BASE + resistance)

# ============================================================
# 9. 公开方法 — 辅助计算
# ============================================================

## 计算护甲减免比例（0.0 ~ 1.0）。
static func get_armor_reduction_ratio(armor: float) -> float:
	if armor <= 0.0:
		return 0.0
	return 1.0 - ARMOR_FACTOR_BASE / (ARMOR_FACTOR_BASE + armor)

## 计算有效生命值（考虑抗性后的等效 HP）。
## effective_hp = hp × (1 + resistance / ARMOR_FACTOR_BASE)
static func get_effective_hp(hp: float, armor: float, magic_resist: float = 0.0) -> float:
	var phys_factor: float = 1.0 + armor / ARMOR_FACTOR_BASE
	var magic_factor: float = 1.0 + magic_resist / ARMOR_FACTOR_BASE
	# 取物理和魔法有效生命的平均值
	return hp * (phys_factor + magic_factor) / 2.0

## 判定一次独立概率事件。
## [param probability] 概率（0.0 ~ 1.0）。
static func roll_chance(probability: float) -> bool:
	if probability <= 0.0:
		return false
	if probability >= 1.0:
		return true
	return randf() < probability

## 计算暴击期望伤害。
## expected = base_damage × (1 + crit_chance × (crit_multiplier - 1))
static func get_expected_damage(base_damage: float, crit_chance: float, crit_multiplier: float = DEFAULT_CRIT_MULTIPLIER) -> float:
	return base_damage * (1.0 + crit_chance * (crit_multiplier - 1.0))
