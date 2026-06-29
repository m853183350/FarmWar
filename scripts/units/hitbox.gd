## 攻击判定区组件 — 检测技能是否命中目标。
##
## 挂载在 [CombatUnitBase] 下作为 Area2D 子节点。
## 由 Tick 层控制激活/停用（[member active]），在 Physics 帧通过 [signal area_entered] 检测目标。
##
## 使用方式：
##   # Tick 层 — 技能判定帧开始时
##   hitbox.activate()
##   # Tick 层 — 技能判定帧结束时
##   hitbox.deactivate()
##
## 碰撞层设计（在场景中配置）：
##   - [member Area2D.collision_layer] = 4 (player_hitbox) 或 5 (enemy_hitbox)
##   - [member Area2D.collision_mask] = 7 (enemy_hurtbox) 或 6 (player_hurtbox)
##   — 根据 [member owner_faction] 在初始化时自动设置。
class_name Hitbox
extends Area2D

# ============================================================
# 1. 信号
# ============================================================

## 攻击命中有效目标时发出。
## [param target] 被命中的单位节点（CombatUnitBase）。
signal hit_detected(target: Node2D)

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

## 所属单位的阵营。0 = 玩家/友方，1+ = 敌方。
## 用于自动设置碰撞层/掩码。
var owner_faction: int = 0

## 是否处于激活状态（Tick 层控制）。
var active: bool = false

# ============================================================
# 6. 私有变量
# ============================================================

## 本次技能施放已命中的目标列表（防止重复命中）。
## 由 CombatUnitBase 在技能施放开始时清空。
var _hit_targets: Array[Node2D] = []

## 是否已初始化碰撞层。
var _layers_initialized: bool = false

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 默认禁用（等待 Skill 施放时激活）
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	area_entered.connect(_on_area_entered)

func _exit_tree() -> void:
	if area_entered.is_connected(_on_area_entered):
		area_entered.disconnect(_on_area_entered)

# ============================================================
# 9. 公开方法
# ============================================================

## 根据阵营设置碰撞层和掩码。
## 0 = 玩家阵营：hitbox 在 layer 4，检测 layer 7 (enemy_hurtbox)
## 1+ = 敌方阵营：hitbox 在 layer 5，检测 layer 6 (player_hurtbox)
func setup_layers(p_faction: int) -> void:
	owner_faction = p_faction
	if owner_faction == 0:
		collision_layer = 1 << (CollisionLayer.PLAYER_HITBOX - 1)
		collision_mask = 1 << (CollisionLayer.ENEMY_HURTBOX - 1)
	else:
		collision_layer = 1 << (CollisionLayer.ENEMY_HITBOX - 1)
		collision_mask = 1 << (CollisionLayer.PLAYER_HURTBOX - 1)
	_layers_initialized = true

## 激活 Hitbox（技能判定帧开始时调用）。
## 重置已命中列表并开始检测重叠。
func activate() -> void:
	_hit_targets.clear()
	active = true
	monitoring = true

## 停用 Hitbox（技能判定帧结束时调用）。
func deactivate() -> void:
	active = false
	monitoring = false

## 检查目标是否已在本次施放中被命中。
func has_hit_target(target: Node2D) -> bool:
	return target in _hit_targets

## 获取本次施放已命中的目标数量。
func get_hit_count() -> int:
	return _hit_targets.size()

## 清空已命中列表（技能施放开始时由 CombatUnitBase 调用）。
func clear_hit_targets() -> void:
	_hit_targets.clear()

# ============================================================
# 10. 私有方法
# ============================================================

## Area2D 重叠检测回调。
## 仅在 [member active] = true 且目标尚未被命中时处理。
func _on_area_entered(area: Area2D) -> void:
	if not active:
		return

	# 确保目标是一个 Hurtbox
	if not area is Hurtbox:
		return

	var hurtbox: Hurtbox = area as Hurtbox

	# 检查目标是否处于无敌状态
	if hurtbox.invulnerable:
		return

	# 获取目标所属单位
	var target: Node2D = hurtbox.owner_unit
	if target == null:
		return

	# 防止重复命中同一目标
	if target in _hit_targets:
		return

	_hit_targets.append(target)
	hit_detected.emit(target)
