## 战斗单位基类 — Tick+Physics 双层架构的核心实现。
##
## 继承 [UnitBase]，覆写移动系统为 Physics 驱动，实现完整的技能执行流程。
## 所有战斗单位（友方/敌方，近战/远程）都是本类的实例，差异由组件和配置决定。
##
## 架构概要：
##   - Tick 层 (20Hz): AI 决策、技能阶段推进、冷却计时、Buff 管理、伤害结算
##   - Physics 帧 (60Hz): 移动执行 (move_and_slide)、碰撞检测、Hitbox/Hurtbox 检测
##   - 单向数据流: Tick 写入指令 (target_velocity/pending_knockback/hitbox_active)
##     → Physics 执行并回传事件 (hitbox_hit/collision_occurred)
##
## 属性计算管道 ([method get_effective_stat]):
##   第 1 层: 全局被动 (ModifierRegistry → "unit" 域)
##   第 2 层: Buff 加算 (stat_modifiers 求和)
##   第 3 层: Buff 倍率加成求和 (1.0 + Σ stat_multipliers 加成值)
##
## 使用方式：
##   var unit: CombatUnitBase = COMBAT_UNIT_SCENE.instantiate()
##   unit.init_from_config(json_data)
##   unit.current_target = enemy
##   unit.start_skill(basic_attack)
class_name CombatUnitBase
extends UnitBase

# ============================================================
# 1. 信号
# ============================================================

## 技能施放开始时发出。
signal skill_cast_started(skill_id: StringName, target_id: StringName)

## 技能施放完成时发出。
signal skill_cast_finished(skill_id: StringName)

## 单位死亡时发出。
signal combat_unit_died(unit_id: StringName, killer_id: StringName)

# ============================================================
# 2. 枚举
# ============================================================

## 战斗单位状态扩展。
## IDLE 和 DEAD 与 [enum UnitBase.UnitState] 保持兼容。
enum CombatState {
	IDLE = 0,        ## 空闲，站立不动，周期性扫描敌人
	CHASE = 10,      ## 追击目标，向目标移动
	CASTING = 11,    ## 施放技能（含普攻）
	RETURN = 12,     ## 返回出生点/守卫位置
	FLEE = 13,       ## 低血量逃跑
	STUNNED = 14,    ## 被控制，无法行动
	DEAD = 99,       ## 死亡
}

# ============================================================
# 3. 常量 — 技能阶段
# ============================================================

## 无技能执行中。
const SKILL_PHASE_NONE: int = -1

## 前摇阶段 — 施放动作，可被打断。
const SKILL_PHASE_WINDUP: int = 0

## 判定帧阶段 — hitbox 激活，可造成伤害。
const SKILL_PHASE_ACTIVE: int = 1

## 后摇阶段 — 收招动作。
const SKILL_PHASE_RECOVERY: int = 2

# ============================================================
# 3. 常量
# ============================================================

## 战斗单位场景模板路径。
const COMBAT_UNIT_SCENE: PackedScene = preload("res://scenes/units/combat_unit_base.tscn")

## Skill 类引用。
const SkillClass = preload("res://scripts/units/skill.gd")

## BuffData 类引用。
const BuffDataClass = preload("res://scripts/units/buff_data.gd")

## CombatSystem 类引用。
const CombatSystemClass = preload("res://scripts/units/combat_system.gd")

## 默认加速度（格/秒²）。
const DEFAULT_ACCELERATION: float = 20.0

## 默认减速度（格/秒²）。
const DEFAULT_DECELERATION: float = 20.0

## 默认暴击率。
const DEFAULT_CRIT_CHANCE: float = 0.05

## 默认暴击倍率。
const DEFAULT_CRIT_MULTIPLIER: float = 1.5

## 受击后无敌持续时间（tick 数）。
const HURT_INVULNERABLE_TICKS: int = 3

# ============================================================
# 5. 公开变量 — 基础战斗属性
# ============================================================

## 护甲值（减免物理伤害）。
var armor: float = 0.0

## 魔抗值（减免魔法伤害）。
var magic_resist: float = 0.0

## 暴击率（0.0 ~ 1.0）。
var crit_chance: float = DEFAULT_CRIT_CHANCE

## 暴击倍率。
var crit_multiplier: float = DEFAULT_CRIT_MULTIPLIER

## 攻击力。实际伤害 = 技能.base_damage × 技能.damage_multiplier × attack_power × buff 加成。
## 不同兵种通过此值区分输出能力，共用同一个 basic_attack 技能。
var attack_power: float = 1.0

## 攻击速度。仅影响普攻（is_basic_attack = true）的冷却和施法阶段。
## 实际冷却 = skill.cooldown_ticks / attack_speed，实际前摇后摇同理。
## 1.0 = 正常速度，2.0 = 两倍速。
var attack_speed: float = 1.0

## 冷却缩减。仅影响非普攻技能（is_basic_attack = false）的冷却时间。
## 实际冷却 = skill.cooldown_ticks × (1.0 - cooldown_reduction)。
## 取值范围 0.0 ~ 1.0（0.0 = 无缩减，0.5 = 冷却减半）。
var cooldown_reduction: float = 0.0

## 最大法力值（0 = 无法力系统）。
var max_mana: float = 0.0

## 当前法力值。
var current_mana: float = 0.0

## 法力恢复（/秒）。
var mana_regen: float = 0.0

## 生命恢复（/秒）。
var health_regen: float = 0.0

## 当前攻击目标。
var current_target: CombatUnitBase = null

# ============================================================
# 5. 公开变量 — 移动系统覆写
# ============================================================

## Tick 层设定的期望速度（AI 写入，Normalized 方向）。
var target_velocity: Vector2 = Vector2.ZERO

## Physics 层实际速度（move_and_slide 使用）。
var current_velocity: Vector2 = Vector2.ZERO

## 移动加速度（格/秒²）。
var acceleration: float = DEFAULT_ACCELERATION

## 移动减速度（格/秒²）。
var deceleration: float = DEFAULT_DECELERATION

## 击退抗性（0.0 ~ 1.0，1.0 = 免疫击退）。
var knockback_resistance: float = 0.0

## 待执行的击退向量（Tick 写入，Physics 消费）。
var pending_knockback: Vector2 = Vector2.ZERO

# ============================================================
# 5. 公开变量 — 技能系统
# ============================================================

## 拥有的技能列表。至少含 1 个 [member Skill.is_basic_attack] = true 的普攻技能。
var skills: Array[Skill] = []

## 技能冷却剩余 tick 数。{技能ID: 剩余tick}
var skill_cooldowns: Dictionary = {}

## 当前正在执行的技能。null = 无。
var active_skill: Skill = null

## 当前技能执行阶段。SKILL_PHASE_NONE / WINDUP / ACTIVE / RECOVERY。
## [br]-1 = 无, 0 = 前摇, 1 = 判定帧, 2 = 后摇。
var active_skill_phase: int = SKILL_PHASE_NONE

## 当前阶段剩余 tick 数。
var skill_phase_remaining_ticks: int = 0

## 本次技能施放已命中的目标列表（防重复命中）。
var hit_targets_this_cast: Array[CombatUnitBase] = []

## 本次技能施放是否已发射弹射物。
var projectile_spawned_this_cast: bool = false

# ============================================================
# 5. 公开变量 — Buff 系统
# ============================================================

## 当前生效的 Buff 列表。
var active_buffs: Array[BuffData] = []

# ============================================================
# 5. 公开变量 — 控制器组件（组合模式）
# ============================================================

## 当前正在执行的任务。null = 无任务，进入自主 AI 模式。
## Phase 4 实现，当前为 null 预留。
var current_task: RefCounted = null

# ============================================================
# 6. 私有变量
# ============================================================

## 出生点（世界坐标），用于 RETURN 状态。
var _spawn_position: Vector2 = Vector2.ZERO

## 道具管理器缓存引用（通过 group 查找）。
var _prop_manager: Node = null

## 眩晕剩余 tick 数。
var _stun_remaining: int = 0

# ============================================================
# 7. @onready 变量
# ============================================================

@onready var hitbox: Hitbox = $Hitbox as Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox as Hurtbox
@onready var mana_bar: ProgressBar = $ManaBar as ProgressBar
@onready var ai_controller: Node = $AIController as Node

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 记录出生点
	_spawn_position = global_position

	# 调用父类 _ready（连接 TickSystem、PathfindingManager 等）
	super._ready()

	# 设置 Hitbox/Hurtbox 碰撞层
	hitbox.setup_layers(faction)
	hurtbox.setup_layers(faction)

	# 连接 Hitbox 命中信号
	hitbox.hit_detected.connect(_on_hitbox_hit)

	# 初始化法力条
	if mana_bar:
		mana_bar.max_value = max_mana if max_mana > 0.0 else 100.0
		mana_bar.value = current_mana
		mana_bar.visible = max_mana > 0.0

	# 加载战斗配置
	_load_combat_config()

	# 缓存 PropManager 引用（通过 group 查找，非 Autoload）
	_prop_manager = get_tree().get_first_node_in_group("prop_manager")

	# 初始化碰撞层
	collision_layer = hitbox.CollisionLayer.PLAYER_UNIT_BODY if faction == 0 else hitbox.CollisionLayer.ENEMY_UNIT_BODY
	collision_mask = (1 << (hitbox.CollisionLayer.WORLD - 1)) | (1 << (hitbox.CollisionLayer.PLAYER_UNIT_BODY - 1)) | (1 << (hitbox.CollisionLayer.ENEMY_UNIT_BODY - 1))

	# 注册到 UnitManager（供 UnitSelection / CommandSystem 查询）
	if UnitManager:
		UnitManager.register_combat_unit(self)

func _exit_tree() -> void:
	if hitbox and hitbox.hit_detected.is_connected(_on_hitbox_hit):
		hitbox.hit_detected.disconnect(_on_hitbox_hit)
	# 从 UnitManager 注销
	if UnitManager:
		UnitManager.unregister_combat_unit(unit_id)
	super._exit_tree()

# ============================================================
# 8. 生命周期方法 — Tick 层覆写
# ============================================================

## Tick 回调。覆写父类逻辑，不再执行 UnitBase 的移动步进。
## 改为：Buff 更新 → 恢复 → 冷却 → 技能阶段推进 → 控制器委托。
func _on_tick(_delta: float) -> void:
	if state == CombatState.DEAD:
		return

	_update_buffs(_delta)
	_update_regen(_delta)
	_update_skill_cooldowns()
	_update_skill_cast()
	_update_hurtbox_invulnerability()
	_update_controller(_delta)

# ============================================================
# 8. 生命周期方法 — Physics 层
# ============================================================

func _physics_process(_delta: float) -> void:
	if state == CombatState.DEAD:
		return

	# 加速度平滑移动
	if state in [CombatState.CHASE, CombatState.RETURN, CombatState.FLEE]:
		var target_vel: Vector2 = target_velocity * move_speed * TILE_SIZE
		current_velocity = current_velocity.move_toward(target_vel, acceleration * TILE_SIZE * _delta)
	elif state == CombatState.STUNNED:
		# 眩晕时减速到 0（但仍可被击退推动）
		current_velocity = current_velocity.move_toward(Vector2.ZERO, deceleration * TILE_SIZE * _delta)
	else:
		# IDLE / CASTING — 减速到 0
		current_velocity = current_velocity.move_toward(Vector2.ZERO, deceleration * TILE_SIZE * _delta)

	# 施加待处理的击退
	if pending_knockback.length() > 0.01:
		var effective_knockback: Vector2 = pending_knockback * (1.0 - knockback_resistance)
		current_velocity += effective_knockback
		pending_knockback = Vector2.ZERO

	# 利用 Godot 物理引擎执行移动（含碰撞检测与响应）
	velocity = current_velocity
	move_and_slide()

	# 同步 grid_position（供 Tick 层和其他系统读取）
	grid_position = global_position
	_prev_tick_position = grid_position
	_next_tick_position = grid_position

	# 更新朝向
	if velocity.x != 0.0:
		facing_direction = Vector2(signf(velocity.x), 0.0)

	update_z_index()

# ============================================================
# 9. 公开方法 — 状态
# ============================================================

## 覆写 [method UnitBase.is_alive]，使用 [enum CombatState.DEAD] 判定。
func is_alive() -> bool:
	return state != CombatState.DEAD

## 覆写 [method UnitBase.is_idle]，使用 [enum CombatState.IDLE] 判定。
func is_idle() -> bool:
	return state == CombatState.IDLE

## 设置战斗状态并发出 [signal state_changed] 信号。
## 由 AI 行为模块调用以更新单位的战斗状态（IDLE/CHASE/CASTING 等）。
func set_combat_state(new_state: int) -> void:
	if state == new_state:
		return
	var old_state: int = state
	state = new_state
	state_changed.emit(old_state, new_state)

## 获取当前战斗状态名称（调试用）。
func get_combat_state_name() -> String:
	match state:
		CombatState.IDLE:
			return "空闲"
		CombatState.CHASE:
			return "追击"
		CombatState.CASTING:
			return "施法"
		CombatState.RETURN:
			return "返回"
		CombatState.FLEE:
			return "逃跑"
		CombatState.STUNNED:
			return "眩晕"
		CombatState.DEAD:
			return "死亡"
		_:
			return "未知(%d)" % state

# ============================================================
# 9. 公开方法 — 属性计算
# ============================================================

## 统一属性计算入口。
## 按固定层级汇集所有修改来源，返回最终有效值。
## [param stat_name] 属性名（如 "attack_power", "move_speed", "armor"）。
## [param base_value] 基础值（来自单位配置）。
func get_effective_stat(stat_name: String, base_value: float) -> float:
	var result: float = base_value

	# 第 1 层：全局被动（ModifierRegistry → "unit" 域）
	if _prop_manager and _prop_manager.has_method("query_modifier"):
		result = _prop_manager.query_modifier("unit", stat_name, result, _build_stat_context())

	# 第 2 层：Buff 加算修改（按 priority 排序）
	var sorted_buffs: Array[BuffData] = _get_sorted_buffs()
	for buff: BuffData in sorted_buffs:
		result += buff.get_stat_modifier(stat_name)

	# 第 3 层：Buff 倍率加成求和 → 统一乘算
	# final_multiplier = 1.0 + Σ(bonus_i)
	# 例：+30%, +20%, -15% → 1.0 + 0.30 + 0.20 + (-0.15) = 1.35
	var total_mult: float = 1.0
	for buff: BuffData in sorted_buffs:
		total_mult += buff.get_stat_multiplier_bonus(stat_name)
	result *= total_mult

	return result

## 便捷方法：获取当前有效攻击力。
## 实际伤害 = 技能.base_damage × 技能.damage_multiplier × get_attack_power() × crit × 抗性。
func get_attack_power() -> float:
	return get_effective_stat("attack_power", attack_power)

## 便捷方法：获取当前有效移动速度。
func get_effective_move_speed() -> float:
	return get_effective_stat("move_speed", move_speed)

## 便捷方法：获取当前有效护甲。
func get_effective_armor() -> float:
	return get_effective_stat("armor", armor)

## 便捷方法：获取当前有效魔抗。
func get_effective_magic_resist() -> float:
	return get_effective_stat("magic_resist", magic_resist)

## 选择战斗中使用的最优技能。
##
## 默认实现委托给 [SkillSelector] 组件。子类（如 WheatSoldier、Aphid）
## 可覆写此方法以实现完全不同的技能选择逻辑（如优先攻击后排、斩杀判定等）。
##
## [param available] 当前可用的技能列表（已过滤冷却/蓝量）。
## [param target] 当前攻击目标。
## [return] 被选中的技能，null 表示无可释放的技能。
func select_combat_skill(available: Array[Skill], target: CombatUnitBase) -> Skill:
	if ai_controller and ai_controller.get("skill_selector") != null:
		var ss: SkillSelector = ai_controller.skill_selector as SkillSelector
		if ss.has_method("select_skill"):
			return ss.select_skill(self, target)
	return available[0] if not available.is_empty() else null

## 获取技能的实际冷却 tick 数，已应用攻击速度或冷却缩减。
##
## - 普攻（is_basic_attack = true）：冷却 / 前摇 / 后摇均由 [member attack_speed] 加速。
## - 其他技能：冷却由 [member cooldown_reduction] 缩短，前摇后摇不变。
##
## [param skill] 目标技能。
## [return] 应用单位属性后的有效冷却 tick 数。
func get_effective_skill_cooldown(skill: Skill) -> int:
	var base: int = skill.cooldown_ticks
	if skill.is_basic_attack and attack_speed > 0.0:
		return maxi(1, int(ceil(float(base) / attack_speed)))
	elif not skill.is_basic_attack:
		return maxi(1, int(ceil(float(base) * (1.0 - cooldown_reduction))))
	return base

## 获取技能的有效阶段 tick 数（前摇/判定帧/后摇）。
## 仅普攻受 [member attack_speed] 影响。
func get_effective_skill_phase_ticks(skill: Skill, base_ticks: int) -> int:
	if skill.is_basic_attack and attack_speed > 0.0:
		return maxi(1, int(ceil(float(base_ticks) / attack_speed)))
	return base_ticks

# ============================================================
# 9. 公开方法 — 技能系统
# ============================================================

## 检查技能是否可用。
## [param skill] 要检查的技能。
func can_use_skill(skill: Skill) -> bool:
	if skill_cooldowns.get(skill.skill_id, 0) > 0:
		return false
	if current_mana < skill.mana_cost:
		return false
	if active_skill != null:
		return false  # 正在执行其他技能
	if state == CombatState.STUNNED:
		return false
	return true

## 获取所有可用技能（按 AI 优先级排序）。
func get_available_skills() -> Array[Skill]:
	var available: Array[Skill] = []
	for skill: Skill in skills:
		if can_use_skill(skill):
			available.append(skill)
	available.sort_custom(func(a: Skill, b: Skill): return a.ai_priority > b.ai_priority)
	return available

## 开始施放技能。
## 进入前摇阶段，设置阶段计时器，播放前摇动画。
## [param skill] 要施放的技能。
func start_skill(skill: Skill) -> void:
	if not can_use_skill(skill):
		return

	active_skill = skill
	active_skill_phase = SKILL_PHASE_WINDUP
	skill_phase_remaining_ticks = get_effective_skill_phase_ticks(skill, skill.windup_ticks)
	hit_targets_this_cast.clear()
	projectile_spawned_this_cast = false

	var anim_duration: float = float(skill.windup_ticks) * TickSystem.tick_interval
	if skill.anim_windup != &"":
		animation_controller.play_work(skill.anim_windup, anim_duration)

	set_combat_state(CombatState.CASTING)
	skill_cast_started.emit(skill.skill_id, current_target.unit_id if current_target else &"")

## 强制中断当前技能施放。
## 在受到眩晕/沉默等控制效果时调用。
func interrupt_skill() -> void:
	if active_skill == null:
		return
	hitbox.deactivate()
	active_skill = null
	active_skill_phase = SKILL_PHASE_NONE
	skill_phase_remaining_ticks = 0
	hit_targets_this_cast.clear()
	projectile_spawned_this_cast = false

# ============================================================
# 9. 公开方法 — Buff 系统
# ============================================================

## 应用一个 Buff 到单位上。
## 根据 [member BuffData.stack_policy] 处理叠加逻辑。
func apply_buff(buff: BuffData) -> void:
	# 查找是否已有同名 Buff（按 buff_id 匹配）
	var existing: BuffData = _find_buff_by_id(buff.buff_id)
	if existing != null:
		match existing.stack_policy:
			BuffData.StackPolicy.NONE:
				# 刷新持续时间
				existing.refresh_duration()
				if EventBus:
					EventBus.unit_buff_applied.emit(unit_id, buff.buff_id)
				return
			BuffData.StackPolicy.STACK:
				if existing.add_stack():
					if EventBus:
						EventBus.unit_buff_applied.emit(unit_id, buff.buff_id)
					return
				# 已达最大层数，仍然刷新持续时间
				existing.refresh_duration()
				return
			BuffData.StackPolicy.INDEPENDENT:
				# 创建独立实例
				pass

	active_buffs.append(buff)
	if EventBus:
		EventBus.unit_buff_applied.emit(unit_id, buff.buff_id)

## 移除指定 Buff。
func remove_buff(buff: BuffData) -> void:
	var idx: int = active_buffs.find(buff)
	if idx >= 0:
		active_buffs.remove_at(idx)
		if EventBus:
			EventBus.unit_buff_expired.emit(unit_id, buff.buff_id)

## 移除所有匹配 buff_id 的 Buff。
func remove_buffs_by_id(buff_id: StringName) -> void:
	var removed: Array[BuffData] = []
	for buff: BuffData in active_buffs:
		if buff.buff_id == buff_id:
			removed.append(buff)
	for buff: BuffData in removed:
		remove_buff(buff)

# ============================================================
# 9. 公开方法 — 伤害与治疗
# ============================================================

## 对目标造成伤害。
## 计算完整伤害公式（攻击力 → 暴击 → 抗性减免）后应用。
## [param skill] 使用的技能。
## [param target] 目标单位。
func deal_damage_to(skill: Skill, target: CombatUnitBase) -> void:
	var attack_power: float = get_attack_power()
	var result: Dictionary = CombatSystemClass.calculate_damage(
		skill,
		attack_power,
		crit_chance,
		crit_multiplier,
		target.get_effective_armor(),
		target.get_effective_magic_resist()
	)

	var effective: float = result["effective_damage"] as float
	var is_crit: bool = result["is_crit"] as bool

	target.take_damage(effective)

	if EventBus:
		EventBus.skill_hit.emit(unit_id, target.unit_id, skill.skill_id, effective, is_crit)

## 覆写 [method UnitBase.take_damage]，添加战斗级事件发射。
func take_damage(amount: float) -> void:
	var old_health: float = current_health
	super.take_damage(amount)
	if EventBus:
		EventBus.unit_health_changed.emit(unit_id, old_health, current_health)

	# 受击后短暂无敌
	if hurtbox and current_health > 0.0:
		hurtbox.set_invulnerable(true, HURT_INVULNERABLE_TICKS)

## 覆写 [method UnitBase.heal]，添加法力恢复和事件发射。
func heal(amount: float) -> void:
	var old_health: float = current_health
	super.heal(amount)
	if EventBus:
		EventBus.unit_health_changed.emit(unit_id, old_health, current_health)

## 恢复法力值。
func restore_mana(amount: float) -> void:
	var old_mana: float = current_mana
	current_mana = minf(max_mana, current_mana + amount)
	if EventBus:
		EventBus.unit_mana_changed.emit(unit_id, old_mana, current_mana)

## 设置当前攻击目标。
func set_target(target: CombatUnitBase) -> void:
	current_target = target

## 清除当前攻击目标。
func clear_target() -> void:
	current_target = null

# ============================================================
# 9. 公开方法 — 击退
# ============================================================

## 施加击退冲量。
## [param direction] 击退方向（Normalized）。
## [param strength] 击退力度（像素/秒冲量）。
func apply_knockback(direction: Vector2, strength: float) -> void:
	if knockback_resistance >= 1.0:
		return
	pending_knockback += direction.normalized() * strength * (1.0 - knockback_resistance)

# ============================================================
# 9. 公开方法 — 眩晕
# ============================================================

## 进入眩晕状态。
## [param duration_ticks] 眩晕持续时间（tick 数）。
func stun(duration_ticks: int) -> void:
	if state == CombatState.DEAD:
		return
	interrupt_skill()
	set_combat_state(CombatState.STUNNED)
	# 眩晕计时由 _update_controller 或 AIController 管理（Phase 3）
	# 当前预留：在 _on_tick 中通过计数器自动恢复
	_stun_remaining = duration_ticks

# ============================================================
# 10. 私有方法 — 状态管理
# ============================================================

# ============================================================
# 10. 私有方法 — Tick 更新
# ============================================================

## 更新所有 Buff 的计时，移除已过期的 Buff。
func _update_buffs(_delta: float) -> void:
	var expired: Array[BuffData] = []
	for buff: BuffData in active_buffs:
		if buff.tick():
			expired.append(buff)
	for buff: BuffData in expired:
		remove_buff(buff)

## 更新生命/法力恢复（每 tick）。
func _update_regen(_delta: float) -> void:
	if health_regen > 0.0:
		var regen_amount: float = health_regen * TickSystem.tick_interval
		heal(regen_amount)
	if mana_regen > 0.0 and max_mana > 0.0:
		var regen_amount: float = mana_regen * TickSystem.tick_interval
		restore_mana(regen_amount)

## 更新所有技能冷却（每 tick -1）。
func _update_skill_cooldowns() -> void:
	for skill_id: StringName in skill_cooldowns.keys():
		var remaining: int = skill_cooldowns[skill_id] as int
		if remaining > 0:
			skill_cooldowns[skill_id] = remaining - 1

## 推进当前技能的执行阶段。
func _update_skill_cast() -> void:
	# 如果当前有技能在执行，继续推进阶段
	if active_skill != null:
		_advance_skill_phase()
		return

	# 技能选择委托给 AIController（Phase 3）
	# 当前预留：不做自动技能选择

## 推进技能施放阶段。
func _advance_skill_phase() -> void:
	if active_skill == null:
		return

	skill_phase_remaining_ticks -= 1
	if skill_phase_remaining_ticks > 0:
		return

	match active_skill_phase:
		SKILL_PHASE_WINDUP:
			# 前摇结束 → 进入判定帧
			_enter_active_phase()

		SKILL_PHASE_ACTIVE:
			# 判定帧结束 → 进入后摇
			_enter_recovery_phase()

		SKILL_PHASE_RECOVERY:
			# 后摇结束 → 技能完成
			_finish_skill()

## 进入技能判定帧阶段。
func _enter_active_phase() -> void:
	active_skill_phase = SKILL_PHASE_ACTIVE
	skill_phase_remaining_ticks = get_effective_skill_phase_ticks(active_skill, active_skill.active_ticks)

	# 激活 Hitbox
	hitbox.activate()

	# 播放判定帧动画
	var anim_duration: float = float(active_skill.active_ticks) * TickSystem.tick_interval
	if active_skill.anim_active != &"":
		animation_controller.play_work(active_skill.anim_active, anim_duration)

	# 远程技能：尝试发射弹射物
	_try_spawn_projectile()

## 进入技能后摇阶段。
func _enter_recovery_phase() -> void:
	active_skill_phase = SKILL_PHASE_RECOVERY
	skill_phase_remaining_ticks = get_effective_skill_phase_ticks(active_skill, active_skill.recovery_ticks)

	# 停用 Hitbox
	hitbox.deactivate()

	# 播放后摇动画
	var anim_duration: float = float(active_skill.recovery_ticks) * TickSystem.tick_interval
	if active_skill.anim_recovery != &"":
		animation_controller.play_work(active_skill.anim_recovery, anim_duration)

## 完成技能施放。
func _finish_skill() -> void:
	# 设置冷却
	skill_cooldowns[active_skill.skill_id] = get_effective_skill_cooldown(active_skill)

	# 消耗法力
	current_mana = maxf(0.0, current_mana - active_skill.mana_cost)
	if EventBus and max_mana > 0.0:
		EventBus.unit_mana_changed.emit(unit_id, current_mana + active_skill.mana_cost, current_mana)

	var finished_skill_id: StringName = active_skill.skill_id

	# 重置技能状态
	active_skill = null
	active_skill_phase = SKILL_PHASE_NONE
	hit_targets_this_cast.clear()
	projectile_spawned_this_cast = false

	skill_cast_finished.emit(finished_skill_id)

	# 回到空闲状态（后续由 AIController 接管）
	if is_alive():
		set_combat_state(CombatState.IDLE)

## 尝试发射弹射物。
func _try_spawn_projectile() -> void:
	if active_skill == null:
		return
	if projectile_spawned_this_cast:
		return
	if active_skill.projectile_id == &"":
		return

	projectile_spawned_this_cast = true

	# 弹射物生成委托给 ProjectileManager（Phase 5）
	if EventBus:
		EventBus.projectile_fired.emit(active_skill.projectile_id, active_skill.skill_id, unit_id)

## 更新 Hurtbox 无敌计时。
func _update_hurtbox_invulnerability() -> void:
	if hurtbox:
		hurtbox.tick_invulnerable()

# ============================================================
# 10. 私有方法 — 控制器委托
# ============================================================

## 委托给 AIController 进行决策。
func _update_controller(_delta: float) -> void:
	# 眩晕状态自动计时恢复
	if state == CombatState.STUNNED:
		_stun_remaining -= 1
		if _stun_remaining <= 0:
			set_combat_state(CombatState.IDLE)
		return

	# 委托给 AIController（Phase 3）
	if ai_controller and ai_controller.has_method("update"):
		ai_controller.update(self, _delta)

# ============================================================
# 10. 私有方法 — 属性计算辅助
# ============================================================

## 获取按 [member BuffData.priority] 排序的 Buff 列表。
func _get_sorted_buffs() -> Array[BuffData]:
	var sorted: Array[BuffData] = active_buffs.duplicate()
	sorted.sort_custom(func(a: BuffData, b: BuffData): return a.priority < b.priority)
	return sorted

## 构建传递给 ModifierRegistry 的单位上下文（用于 target_filter 匹配）。
func _build_stat_context() -> Dictionary:
	return {
		"unit_type": unit_type,
		"faction": faction,
		"unit_id": unit_id,
	}

# ============================================================
# 10. 私有方法 — Buff 查询
# ============================================================

## 按 buff_id 查找现有 Buff。
func _find_buff_by_id(buff_id: StringName) -> BuffData:
	for buff: BuffData in active_buffs:
		if buff.buff_id == buff_id:
			return buff
	return null

# ============================================================
# 10. 私有方法 — 碰撞检测响应
# ============================================================

## Hitbox 命中目标回调。
## Physics 层 → Tick 层：收到 hitbox 检测结果后在 Tick 层计算伤害。
func _on_hitbox_hit(target: Node2D) -> void:
	if active_skill == null:
		return
	if not target is CombatUnitBase:
		return

	var target_unit: CombatUnitBase = target as CombatUnitBase

	# 防止重复命中
	if target_unit in hit_targets_this_cast:
		return
	hit_targets_this_cast.append(target_unit)

	# 造成伤害
	deal_damage_to(active_skill, target_unit)

# ============================================================
# 10. 私有方法 — 生命值覆写
# ============================================================

## 覆写 [method UnitBase._die]，添加战斗级死亡处理。
func _die() -> void:
	# 停用 Hitbox
	if hitbox:
		hitbox.deactivate()

	# 清除目标和技能状态
	current_target = null
	interrupt_skill()

	# 清除所有 Buff
	active_buffs.clear()

	# 设置死亡状态
	set_combat_state(CombatState.DEAD)

	# 发射死亡信号
	if EventBus:
		EventBus.unit_killed.emit(unit_id, &"")
	combat_unit_died.emit(unit_id, &"")

# ============================================================
# 9. 公开方法 — 配置加载
# ============================================================

## 从 JSON 字典加载完整战斗单位配置（属性 + 技能 + AI）。
##
## 预期的 JSON 结构：
##   {
##     "unit_type": "wheat_soldier",
##     "display_name": "麦粒小兵",
##     "faction": 0,
##     "stats": { "max_health": 100.0, "move_speed": 3.0, ... },
##     "skills": ["basic_wheat_slash"],
##     "ai": { "default_behavior": "Guard", "behaviors": [...], ... }
##   }
##
## [param data] 从 JSON 解析出的完整配置字典。
func init_from_config(data: Dictionary) -> void:
	# ---- 单位基本信息 ----
	unit_type = data.get("unit_type", unit_type) as StringName
	display_name = data.get("display_name", display_name) as String
	faction = data.get("faction", faction) as int

	# ---- 战斗属性 ----
	var stats: Dictionary = data.get("stats", {})
	if not stats.is_empty():
		max_health = stats.get("max_health", max_health) as float
		current_health = max_health
		move_speed = stats.get("move_speed", move_speed) as float
		armor = stats.get("armor", armor) as float
		magic_resist = stats.get("magic_resist", magic_resist) as float
		crit_chance = stats.get("crit_chance", crit_chance) as float
		crit_multiplier = stats.get("crit_multiplier", crit_multiplier) as float
		attack_power = stats.get("attack_power", attack_power) as float
		attack_speed = stats.get("attack_speed", attack_speed) as float
		cooldown_reduction = stats.get("cooldown_reduction", cooldown_reduction) as float
		max_mana = stats.get("max_mana", max_mana) as float
		current_mana = max_mana
		mana_regen = stats.get("mana_regen", mana_regen) as float
		health_regen = stats.get("health_regen", health_regen) as float
		knockback_resistance = stats.get("knockback_resistance", knockback_resistance) as float
		acceleration = stats.get("acceleration", acceleration) as float
		deceleration = stats.get("deceleration", deceleration) as float

	# ---- 技能列表 ----
	var skill_ids: Array = data.get("skills", [])
	for sid: String in skill_ids:
		var skill: Skill = _load_skill_from_id(sid as StringName)
		if skill != null:
			skills.append(skill)

	# ---- AI 配置 ----
	var ai_config: Dictionary = data.get("ai", {})
	if not ai_config.is_empty():
		init_ai_from_config(ai_config)

	# 初始化法力条显示
	if is_inside_tree() and mana_bar:
		mana_bar.max_value = max_mana if max_mana > 0.0 else 100.0
		mana_bar.value = current_mana
		mana_bar.visible = max_mana > 0.0

## 从 JSON 文件路径加载完整战斗单位配置。
## 便捷方法，内部调用 [method init_from_config]。
func init_from_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("CombatUnitBase: 配置文件不存在 %s" % path)
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CombatUnitBase: 无法读取配置文件 %s" % path)
		return
	var data: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()
	if data == null:
		push_warning("CombatUnitBase: JSON 解析失败 %s" % path)
		return
	init_from_config(data)

# ============================================================
# 11. 虚方法 — 配置加载（子类覆写入口）
# ============================================================

## 加载战斗单位 JSON 配置。
## 子类可覆写以指定不同的配置路径或加载逻辑。
func _load_combat_config() -> void:
	# 子类应覆写此方法以加载专属配置
	# 例如：init_from_file("res://config/units/combat_stats/my_unit.json")
	pass

## 从配置字典初始化 AI 控制器。
## 在 [method init_from_config] 或子类的 [method _load_combat_config] 中调用。
func init_ai_from_config(ai_config: Dictionary) -> void:
	if ai_controller and ai_controller.has_method("init_from_config"):
		ai_controller.init_from_config(ai_config)

## 从 JSON 文件路径加载并初始化 AI 控制器。
func init_ai_from_file(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CombatUnitBase: 无法读取 AI 配置 %s" % path)
		return
	var data: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()
	if data == null:
		return
	var ai_config: Dictionary = data.get("ai", {})
	init_ai_from_config(ai_config)

## 根据技能 ID 从 [code]config/skills/{skill_id}.json[/code] 加载 Skill 实例。
func _load_skill_from_id(skill_id: StringName) -> Skill:
	var path: String = "res://config/skills/%s.json" % skill_id
	if not FileAccess.file_exists(path):
		push_warning("CombatUnitBase: 技能配置文件不存在 %s" % path)
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()
	if data == null:
		push_warning("CombatUnitBase: 技能 JSON 解析失败 %s" % path)
		return null
	return Skill.from_dict(data)
