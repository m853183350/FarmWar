## 受击判定区组件 — 被敌方 Hitbox 或弹射物检测。
##
## 挂载在 [CombatUnitBase] 下作为 Area2D 子节点。
## 由 Tick 层控制无敌状态，在 Physics 帧被敌对 Hitbox 检测。
##
## 使用方式：
##   # 设置拥有者（在 CombatUnitBase._ready 中）
##   hurtbox.owner_unit = self
##   # 临时无敌（如受到伤害后）
##   hurtbox.set_invulnerable(true, 10)
##
## 碰撞层设计（在场景中配置）：
##   - [member Area2D.collision_layer] = 6 (player_hurtbox) 或 7 (enemy_hurtbox)
##   - [member Area2D.collision_mask] = 0（不主动检测，只被检测）
##   — 根据 [member owner_faction] 在初始化时自动设置。
class_name Hurtbox
extends Area2D

# ============================================================
# 1. 信号
# ============================================================

## 受到有效伤害时发出（由 Hitbox 或 Projectile 触发）。
## [param source] 伤害来源节点（Hitbox 或 Projectile）。
## [param amount] 受到的伤害量。
signal hurt_received(source: Node2D, amount: float)

# ============================================================
# 2. 枚举
# ============================================================

## 碰撞层映射（与项目设置中的物理层对应）。
enum CollisionLayer {
	WORLD = 1,
	PLAYER_UNIT_BODY = 2,
	ENEMY_UNIT_BODY = 3,
	PLAYER_HITBOX = 4,
	ENEMY_HITBOX = 5,
	PLAYER_HURTBOX = 6,
	ENEMY_HURTBOX = 7,
	PROJECTILE = 8,
}

# ============================================================
# 5. 公开变量
# ============================================================

## 所属的战斗单位节点引用。
## 由 CombatUnitBase 在 _ready 中设置。
var owner_unit: Node2D = null

## 所属单位的阵营。0 = 玩家/友方，1+ = 敌方。
var owner_faction: int = 0

## 是否处于无敌状态（受伤后短暂无敌、技能效果等）。
var invulnerable: bool = false

# ============================================================
# 6. 私有变量
# ============================================================

## 无敌剩余 tick 数。> 0 表示自动无敌计时中。
var _invulnerable_ticks: int = 0

## 是否已初始化碰撞层。
var _layers_initialized: bool = false

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# Hurtbox 只被检测，不主动检测
	set_deferred("monitoring", false)
	set_deferred("monitorable", true)

# ============================================================
# 9. 公开方法
# ============================================================

## 根据阵营设置碰撞层。
## 0 = 玩家阵营：hurtbox 在 layer 6（被 enemy_hitbox 检测）
## 1+ = 敌方阵营：hurtbox 在 layer 7（被 player_hitbox 检测）
func setup_layers(p_faction: int) -> void:
	owner_faction = p_faction
	if owner_faction == 0:
		collision_layer = 1 << (CollisionLayer.PLAYER_HURTBOX - 1)
	else:
		collision_layer = 1 << (CollisionLayer.ENEMY_HURTBOX - 1)
	collision_mask = 0  # Hurtbox 不检测其他 Area
	_layers_initialized = true

## 设置无敌状态。
## [param p_invulnerable] 是否无敌。
## [param duration_ticks] 自动无敌持续 tick 数（0 = 手动控制）。
func set_invulnerable(p_invulnerable: bool, duration_ticks: int = 0) -> void:
	invulnerable = p_invulnerable
	_invulnerable_ticks = duration_ticks
	# 无敌时禁用被检测能力
	monitorable = not invulnerable

## 每 tick 更新无敌计时。
## 由 CombatUnitBase 的 Tick 层调用。
func tick_invulnerable() -> void:
	if _invulnerable_ticks > 0:
		_invulnerable_ticks -= 1
		if _invulnerable_ticks <= 0:
			invulnerable = false
			monitorable = true

## 收到伤害通知（由伤害计算系统通过回调调用）。
## 发出 [signal hurt_received] 信号供 UI 等系统使用。
func notify_hurt(source: Node2D, amount: float) -> void:
	hurt_received.emit(source, amount)

## 返回无敌剩余 tick 数。
func get_invulnerable_ticks() -> int:
	return _invulnerable_ticks
