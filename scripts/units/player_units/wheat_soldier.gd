## 麦粒小兵 — 基础近战战斗单位。
##
## 继承 [CombatUnitBase]，覆写 [method _load_combat_config] 加载专属 JSON 配置。
## 仅拥有普攻技能 "basic_wheat_slash"，无特殊技能。
##
## 属性、技能、AI 参数全部由 [code]config/units/combat_stats/wheat_soldier.json[/code] 定义。
class_name WheatSoldier
extends CombatUnitBase

# ============================================================
# 3. 常量
# ============================================================

const CONFIG_PATH: String = "res://config/units/combat_stats/wheat_soldier.json"

# ============================================================
# 11. 虚方法 — 配置加载
# ============================================================

func _load_combat_config() -> void:
	init_from_file(CONFIG_PATH)
