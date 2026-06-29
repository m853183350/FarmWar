## 技能数据结构，普攻和特殊技能统一由此 Resource 描述。
##
## 技能数据由 JSON 配置加载：[code]config/skills/*.json[/code]。
## 普攻也是一种技能（[member is_basic_attack] = true），与特殊技能共用同一套执行流程。
##
## 使用方式：
##   var skill: Skill = Skill.from_dict(json_data)
##   if skill.range > 1.5: ... # 远程技能
class_name Skill
extends Resource

# ============================================================
# 2. 枚举
# ============================================================

## 伤害类型。
enum DamageType {
	PHYSICAL,    ## 物理伤害，受护甲减免
	MAGIC,       ## 魔法伤害，受魔抗减免
	TRUE,        ## 真实伤害，无视抗性
}

## Hitbox 形状类型。
enum HitboxShape {
	POINT,       ## 点（单体目标）
	CIRCLE,      ## 圆形范围
	ARC,         ## 扇形范围（近战横扫）
	RECT,        ## 矩形范围（直线冲锋/突刺）
}

# ============================================================
# 4. @export 变量 — 基础信息
# ============================================================

## 技能唯一 ID（如 "basic_slash", "fireball"）。
@export var skill_id: StringName = &""

## 技能显示名称（如 "斩击", "火球术"）。
@export var display_name: String = ""

## 是否为普攻。true = 普攻，AI 会优先使用；false = 特殊技能。
@export var is_basic_attack: bool = false

# ============================================================
# 4. @export 变量 — 伤害
# ============================================================

## 伤害类型。
@export var damage_type: DamageType = DamageType.PHYSICAL

## 基础伤害值。可为 0，此时伤害完全来自单位的 Buff 加成。
@export var base_damage: float = 0.0

## 伤害倍率。最终伤害 = (unit_attack_power + base_damage) × damage_multiplier。
@export var damage_multiplier: float = 1.0

# ============================================================
# 4. @export 变量 — 射程与消耗
# ============================================================

## 技能射程（格数）。≤1.5 = 近战，>1.5 = 远程。
@export var range: float = 1.5

## 冷却时间（tick 数，20 tick = 1 秒）。
@export var cooldown_ticks: int = 20

## 法力消耗。
@export var mana_cost: float = 0.0

# ============================================================
# 4. @export 变量 — 技能阶段
# ============================================================

## 前摇 tick 数（施放动作，可被打断）。
@export var windup_ticks: int = 5

## 判定帧持续 tick 数（hitbox 激活期间）。
@export var active_ticks: int = 3

## 后摇 tick 数（收招动作）。
@export var recovery_ticks: int = 8

# ============================================================
# 4. @export 变量 — 弹射物
# ============================================================

## 弹射物 ID。空字符串 = 无弹射物（近战），非空 = 远程弹射物。
@export var projectile_id: StringName = &""

## 弹射物速度（格/秒），仅远程有效。
@export var projectile_speed: float = 10.0

# ============================================================
# 4. @export 变量 — Hitbox
# ============================================================

## Hitbox 形状类型。
@export var hitbox_shape: HitboxShape = HitboxShape.POINT

## Hitbox 参数（半径、角度、宽高等，由 hitbox_shape 决定）。
@export var hitbox_params: Dictionary = {}

# ============================================================
# 4. @export 变量 — 动画
# ============================================================

## 前摇动画名。
@export var anim_windup: StringName = &""

## 判定帧动画名。
@export var anim_active: StringName = &""

## 后摇动画名。
@export var anim_recovery: StringName = &""

# ============================================================
# 4. @export 变量 — AI
# ============================================================

## AI 使用权重。越高越优先，0 = AI 不使用该技能。
@export var ai_priority: int = 1

# ============================================================
# 3. 常量
# ============================================================

## JSON 字段 → Skill 属性映射表。
## 用于 [method from_dict] 将 JSON 键映射到 Skill 属性。
const JSON_FIELD_MAP: Dictionary = {
	"skill_id": "skill_id",
	"display_name": "display_name",
	"is_basic_attack": "is_basic_attack",
	"damage_type": "damage_type",
	"base_damage": "base_damage",
	"damage_multiplier": "damage_multiplier",
	"range": "range",
	"cooldown_ticks": "cooldown_ticks",
	"mana_cost": "mana_cost",
	"windup_ticks": "windup_ticks",
	"active_ticks": "active_ticks",
	"recovery_ticks": "recovery_ticks",
	"projectile_id": "projectile_id",
	"projectile_speed": "projectile_speed",
	"hitbox_shape": "hitbox_shape",
	"hitbox_params": "hitbox_params",
	"anim_windup": "anim_windup",
	"anim_active": "anim_active",
	"anim_recovery": "anim_recovery",
	"ai_priority": "ai_priority",
}

## DamageType 字符串 → 枚举值映射。
const DAMAGE_TYPE_MAP: Dictionary = {
	"PHYSICAL": DamageType.PHYSICAL,
	"MAGIC": DamageType.MAGIC,
	"TRUE": DamageType.TRUE,
	"physical": DamageType.PHYSICAL,
	"magic": DamageType.MAGIC,
	"true": DamageType.TRUE,
}

## HitboxShape 字符串 → 枚举值映射。
const HITBOX_SHAPE_MAP: Dictionary = {
	"POINT": HitboxShape.POINT,
	"CIRCLE": HitboxShape.CIRCLE,
	"ARC": HitboxShape.ARC,
	"RECT": HitboxShape.RECT,
	"point": HitboxShape.POINT,
	"circle": HitboxShape.CIRCLE,
	"arc": HitboxShape.ARC,
	"rect": HitboxShape.RECT,
}

# ============================================================
# 9. 公开方法
# ============================================================

## 从 JSON 字典创建 Skill 实例。
## 将 JSON 中的字符串枚举值自动转换为 GDScript 枚举。
static func from_dict(data: Dictionary) -> Skill:
	var skill: Skill = Skill.new()
	for json_key: String in data:
		if not JSON_FIELD_MAP.has(json_key):
			push_warning("Skill.from_dict: 未知字段 '%s'" % json_key)
			continue
		var prop_name: String = JSON_FIELD_MAP[json_key]
		var value = data[json_key]

		match prop_name:
			"damage_type":
				skill.damage_type = DAMAGE_TYPE_MAP.get(value, DamageType.PHYSICAL)
			"hitbox_shape":
				skill.hitbox_shape = HITBOX_SHAPE_MAP.get(value, HitboxShape.POINT)
			_:
				skill.set(prop_name, value)
	return skill

## 返回技能射程是否属于近战范围。
func is_melee() -> bool:
	return range <= 1.5

## 返回技能是否为远程技能（有弹射物或射程 > 1.5）。
func is_ranged() -> bool:
	return range > 1.5 or projectile_id != &""

## 返回伤害类型名称（用于 UI 显示）。
func get_damage_type_name() -> String:
	match damage_type:
		DamageType.PHYSICAL:
			return "物理"
		DamageType.MAGIC:
			return "魔法"
		DamageType.TRUE:
			return "真实"
		_:
			return "未知"

## 返回 Hitbox 形状名称（用于调试）。
func get_hitbox_shape_name() -> String:
	match hitbox_shape:
		HitboxShape.POINT:
			return "点"
		HitboxShape.CIRCLE:
			return "圆形"
		HitboxShape.ARC:
			return "扇形"
		HitboxShape.RECT:
			return "矩形"
		_:
			return "未知"

## 返回技能阶段总 tick 数（前摇 + 判定帧 + 后摇）。
func get_total_cast_ticks() -> int:
	return windup_ticks + active_ticks + recovery_ticks

## 返回技能总施放时间（秒）。
func get_total_cast_time() -> float:
	return float(get_total_cast_ticks()) * 0.05  # 20 tick/s

## 返回技能的字符串表示。
func _to_string() -> String:
	return "Skill(id=%s, name=%s, basic=%s, range=%.1f, dmg=%.0f x%.1f)" % [
		skill_id, display_name, is_basic_attack, range, base_damage, damage_multiplier
	]
