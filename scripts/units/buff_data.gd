## Buff/Debuff 运行时数据结构。
##
## BuffData 描述一个作用于战斗单位的增益或减益效果。
## 由 Tick 层的 Buff 系统驱动计时和叠层管理，通过 [EventBus] 发出应用/过期信号。
##
## 使用 RefCounted 而非 Resource，因为 Buff 只在运行时创建、不需要序列化。
##
## 属性计算顺序（由 CombatUnitBase.get_effective_stat 保证）：
##   1. 全局被动（ModifierRegistry → "unit" 域）
##   2. Buff 加算修改（stat_modifiers 求和）
##   3. Buff 倍率加成求和（1.0 + Σ stat_multipliers 加成值）
##
## 使用方式：
##   var buff: BuffData = BuffData.create("attack_boost", 100, 3, {"attack_power": 10.0}, {"attack_power": 0.30})  # +30%
##   unit.active_buffs.append(buff)
class_name BuffData
extends RefCounted

# ============================================================
# 2. 枚举
# ============================================================

## Buff 类型。
enum BuffType {
	BUFF,        ## 增益效果
	DEBUFF,      ## 减益效果
}

## Buff 叠加策略。
enum StackPolicy {
	NONE,        ## 不可叠加（同名 Buff 刷新持续时间）
	INDEPENDENT, ## 独立叠加（每个 Buff 独立计时）
	STACK,       ## 层数叠加（增加层数，刷新持续时间）
}

# ============================================================
# 3. 常量
# ============================================================

## 静态自增 ID 计数器。
static var _next_id: int = 0

# ============================================================
# 5. 公开变量 — 基础信息
# ============================================================

## 唯一标识（自动分配）。
var instance_id: int = 0

## Buff 配置 ID（如 "attack_boost", "poison"）。
var buff_id: StringName = &""

## 显示名称（如 "攻击提升", "中毒"）。
var display_name: String = ""

## Buff 类型。
var buff_type: BuffType = BuffType.BUFF

# ============================================================
# 5. 公开变量 — 计时与叠层
# ============================================================

## 总持续时间（tick 数）。0 = 永久（手动移除）。
var duration_ticks: int = 0

## 剩余 tick 数。每次 Buff tick 递减，到 0 时过期。
var remaining_ticks: int = 0

## 当前层数。
var stacks: int = 1

## 最大可叠加层数。
var max_stacks: int = 1

## 叠加策略。
var stack_policy: StackPolicy = StackPolicy.NONE

# ============================================================
# 5. 公开变量 — 属性修改
# ============================================================

## 属性修改字典。
## 键为属性名（如 "attack_power", "move_speed", "armor"），值为修改量。
## 正值 = 增加，负值 = 减少。
## 例：{ "attack_power": 10.0, "move_speed": -0.5, "armor": 5.0 }
var stat_modifiers: Dictionary = {}

## 属性倍率修改字典。
## 键为属性名，值为**加成比例**（0.30 = +30%，-0.15 = -15%）。
## 多个 Buff 的倍率加成先求和再应用：final_multiplier = 1.0 + Σ(bonus)。
## 例：Buff A +30%, Buff B +20%, Debuff C -15% → 总倍率 = 1.0 + 0.30 + 0.20 - 0.15 = 1.35。
## 先 [member stat_modifiers] 加算，再 [member stat_multipliers] 求和后乘算。
var stat_multipliers: Dictionary = {}

## 同层内的计算优先级。值越小越先计算，默认 0。
## 当多个 Buff 同时修改同一属性时，可通过 priority 控制先后。
## 例：priority=-1 的 Buff 先于 priority=0 的 Buff 计算。
var priority: int = 0

# ============================================================
# 5. 公开变量 — 特殊效果
# ============================================================

## 是否不可驱散。
var is_undispellable: bool = false

## 施加此 Buff 的单位 ID。
var source_unit_id: StringName = &""

## 图标资源路径（用于 UI 显示）。
var icon_path: String = ""

# ============================================================
# 9. 公开方法
# ============================================================

## 创建一个 BuffData 实例。
## [param id] Buff 配置 ID。
## [param duration] 持续时间（tick 数），0 = 永久。
## [param max_stack] 最大叠层数。
## [param modifiers] 属性加算修改字典（可选）。例：{"attack_power": 10.0, "move_speed": -0.5}
## [param multipliers] 属性倍率加成字典（可选）。值为加成比例，如 0.30 = +30%。
## [param p_priority] 同层计算优先级（越小越先），默认 0。
static func create(
	id: StringName,
	duration: int = 100,
	max_stack: int = 1,
	modifiers: Dictionary = {},
	multipliers: Dictionary = {},
	p_priority: int = 0
) -> BuffData:
	var buff: BuffData = BuffData.new()
	_next_id += 1
	buff.instance_id = _next_id
	buff.buff_id = id
	buff.duration_ticks = duration
	buff.remaining_ticks = duration
	buff.max_stacks = max_stack
	buff.stacks = 1
	buff.stat_modifiers = modifiers.duplicate()
	buff.stat_multipliers = multipliers.duplicate()
	buff.priority = p_priority
	if max_stack > 1:
		buff.stack_policy = StackPolicy.STACK
	return buff

## 增加一层叠层（不超过 [member max_stacks]）。
## 成功增加返回 true，已达上限返回 false。
func add_stack() -> bool:
	if stacks >= max_stacks:
		return false
	stacks += 1
	# 刷新持续时间
	remaining_ticks = duration_ticks
	return true

## 移除一层叠层。归零时返回 true（表示 Buff 应被移除）。
func remove_stack() -> bool:
	stacks -= 1
	return stacks <= 0

## 刷新剩余时间到满值。
func refresh_duration() -> void:
	if duration_ticks > 0:
		remaining_ticks = duration_ticks

## 每 tick 递减剩余时间。返回 true 表示 Buff 已过期。
func tick() -> bool:
	if duration_ticks <= 0:
		return false  # 永久 Buff 不过期
	remaining_ticks -= 1
	return remaining_ticks <= 0

## 获取指定属性的总加算修改量（考虑层数）。
func get_stat_modifier(stat_name: String) -> float:
	var base: float = stat_modifiers.get(stat_name, 0.0)
	return base * float(stacks)

## 获取指定属性的倍率加成值（考虑层数）。
## 返回值为加成比例（如 0.30 表示 +30%，-0.15 表示 -15%）。
## 调用者应将所有 Buff 的加成值求和后计算总倍率：
##   final_multiplier = 1.0 + Σ(各 Buff 的加成值)
## 无此属性时返回 0.0（不影响最终倍率）。
func get_stat_multiplier_bonus(stat_name: String) -> float:
	if not stat_multipliers.has(stat_name):
		return 0.0
	var base: float = stat_multipliers[stat_name]
	# 叠层：加成比例 × 层数
	return base * float(stacks)

## 返回 Buff 是否已过期。
func is_expired() -> bool:
	return duration_ticks > 0 and remaining_ticks <= 0

## 返回 Buff 是否为永久效果。
func is_permanent() -> bool:
	return duration_ticks <= 0

## 返回 Buff 类型的可读名称。
func get_type_name() -> String:
	match buff_type:
		BuffType.BUFF:
			return "增益"
		BuffType.DEBUFF:
			return "减益"
		_:
			return "未知"

## 返回叠加策略的可读名称。
func get_stack_policy_name() -> String:
	match stack_policy:
		StackPolicy.NONE:
			return "不叠加"
		StackPolicy.INDEPENDENT:
			return "独立叠加"
		StackPolicy.STACK:
			return "层数叠加"
		_:
			return "未知"

## 返回 Buff 的字符串表示。
func _to_string() -> String:
	return "BuffData(id=%s, stacks=%d/%d, remaining=%d/%d)" % [
		buff_id, stacks, max_stacks, remaining_ticks, duration_ticks
	]
