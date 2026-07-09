## 麦粒重装兵 — 重装近战战斗单位。
##
## 继承 [CombatUnitBase]，覆写 [method _load_combat_config] 加载专属 JSON 配置。
## 仅拥有普攻技能 "basic_heavy_slam"，无特殊技能。
## 相比麦粒小兵：更高的生命和护甲，更低的移动速度，更大的攻击范围。
##
## 属性、技能、AI 参数全部由 [code]config/units/combat_stats/wheat_heavy.json[/code] 定义。
class_name WheatHeavy
extends CombatUnitBase

# ============================================================
# 3. 常量
# ============================================================

const CONFIG_PATH: String = "res://config/units/combat_stats/wheat_heavy.json"

# ============================================================
# 11. 虚方法 — 配置加载
# ============================================================

func _load_combat_config() -> void:
	init_from_file(CONFIG_PATH)
