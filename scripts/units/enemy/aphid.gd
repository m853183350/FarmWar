## 蚜虫 — 敌方基础近战单位。
##
## 继承 [CombatUnitBase]，覆写 [method _load_combat_config] 加载专属 JSON 配置。
## 仅拥有普攻技能 "basic_aphid_bite"，无特殊技能。
## 阵营固定为 faction=1（敌方），由 [EnemyManager] 批量生成和管理。
##
## 属性、技能、AI 参数全部由 [code]config/ai/enemy_templates/aphid.json[/code] 定义。
class_name Aphid
extends CombatUnitBase

# ============================================================
# 3. 常量
# ============================================================

const CONFIG_PATH: String = "res://config/ai/enemy_templates/aphid.json"

# ============================================================
# 11. 虚方法 — 配置加载
# ============================================================

func _load_combat_config() -> void:
	init_from_file(CONFIG_PATH)
