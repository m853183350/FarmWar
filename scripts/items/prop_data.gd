## 道具定义数据类 — 纯数据容器（RefCounted）。
##
## 从 JSON 配置解析道具的静态定义数据，包含标识、显示、稀有度、
## 触发条件和效果等全部属性。
##
## 设计参考 roguelike 游戏的道具/遗物系统：
##   - 稀有度分 5 级（COMMON → LEGENDARY）
##   - 被动触发型（监听 EventBus 信号）
##   - 支持堆叠（max_stack 控制上限）
##
## 使用方式（通过 preload 避免跨文件类名引用问题）：
##   [codeblock]
##   const PD = preload("res://scripts/items/prop_data.gd")
##   var p: RefCounted = PD.new()
##   p.init_from_dict(json_data)
##   [/codeblock]
class_name PropData extends RefCounted

# ============================================================
# 5. 公开变量
# ============================================================

## 道具唯一标识符（snake_case）。
var prop_id: String = ""

## 道具显示名称（中文）。
var prop_name: String = ""

## 风味描述文字。
var description: String = ""

## 稀有度等级。[br]
## 可选值：COMMON, UNCOMMON, RARE, EPIC, LEGENDARY
var rarity: String = "common"

## 图标纹理路径（相对于 res://），暂可留空。
var icon_path: String = ""

## 最大持有数量。0 表示无限制。
var max_stack: int = 0

## 触发的 EventBus 信号名称。
var trigger_signal: StringName = &""

## 触发条件配置（预留）。[br]
## 可包含 cooldown_ticks（冷却时间）、probability（触发概率）等。
var trigger_condition: Dictionary = {}

## 效果类型标识。
var effect_type: StringName = &""

## 效果参数字典，内容取决于 effect_type。
var effect_params: Dictionary = {}

## 分类标签数组，用于筛选和分类。
var tags: Array[String] = []

# ============================================================
# 9. 公开方法
# ============================================================

## 从 JSON Dictionary 初始化道具数据。[br]
## 已知字段被填充，未知字段被忽略，缺失字段使用默认值。
func init_from_dict(data: Dictionary) -> void:
	prop_id = data.get("prop_id", "") as String
	prop_name = data.get("prop_name", "") as String
	description = data.get("description", "") as String
	rarity = data.get("rarity", "common") as String
	icon_path = data.get("icon_path", "") as String
	max_stack = data.get("max_stack", 0) as int

	var trigger_signal_str: String = data.get("trigger_signal", "") as String
	trigger_signal = StringName(trigger_signal_str) if not trigger_signal_str.is_empty() else &""

	trigger_condition = data.get("trigger_condition", {}) as Dictionary

	var effect_type_str: String = data.get("effect_type", "") as String
	effect_type = StringName(effect_type_str) if not effect_type_str.is_empty() else &""

	effect_params = data.get("effect_params", {}) as Dictionary

	var tags_raw = data.get("tags", [])
	if tags_raw is Array:
		var tags_arr: Array[String] = []
		for tag in tags_raw:
			tags_arr.append(tag as String)
		tags = tags_arr
