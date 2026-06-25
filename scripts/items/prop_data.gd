## 道具定义数据类 — 纯数据容器（RefCounted）。
##
## 从 JSON 配置解析道具的静态定义数据，包含标识、显示、稀有度、
## 触发条件和效果等全部属性。
##
## 设计参考 roguelike 游戏的道具/遗物系统：
##   - 稀有度分 5 级（COMMON → LEGENDARY）
##   - 被动触发型（监听 EventBus 信号）
##   - 支持堆叠（max_stack 控制上限）
##   - 支持复合效果（一个道具可配置多个效果）
##
## 使用方式（通过 preload 避免跨文件类名引用问题）：
##   [codeblock]
##   const PD = preload("res://scripts/items/prop_data.gd")
##   var p: RefCounted = PD.new()
##   p.init_from_dict(json_data)
##   [/codeblock]
class_name PropData extends RefCounted

# ============================================================
# 3. 常量
# ============================================================

## 稀有度等级。
const RARITY_COMMON: String = "common"
const RARITY_UNCOMMON: String = "uncommon"
const RARITY_RARE: String = "rare"
const RARITY_EPIC: String = "epic"
const RARITY_LEGENDARY: String = "legendary"

## 道具类别常量。
const CATEGORY_INSTANT: String = "instant"
const CATEGORY_MODIFIER: String = "modifier"
const CATEGORY_DURATION: String = "duration"

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
## 可选值：common, uncommon, rare, epic, legendary
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

## 效果配置列表。[br]
## 每个元素为 [Dictionary]：{ type: StringName, params: Dictionary }[br]
## 支持复合效果（一个道具多个效果）和堆叠（持有 n 个执行 n 次）。
var effects: Array[Dictionary] = []

## 道具类别。[br]
## 可选值：[code]"instant"[/code]（默认，事件触发型）、[code]"modifier"[/code]（被动修饰型）、
## [code]"duration"[/code]（限时持续型）。
var prop_category: String = "instant"

## 修饰器配置（仅 MODIFIER 类别道具使用）。[br]
## 包含 target_domains、stat、value、priority、tags、target_filter 等字段。
var modifier: Dictionary = {}

## 全局排序优先级（默认 0）。[br]
## 数值越小越先计算。
var priority: int = 0

## 前置道具 ID 列表。[br]
## 需要持有列表中所有道具后，本道具才能生效。
var requires: Array[String] = []

## 互斥道具 ID 列表。[br]
## 不能与列表中任何道具同时持有。
var conflicts_with: Array[String] = []

## 分类标签数组（不可变），用于筛选和分类。
var tags: Array[String] = []

# ============================================================
# 9. 公开方法
# ============================================================

## 从 JSON Dictionary 初始化道具数据。[br]
## 已知字段被填充，未知字段被忽略，缺失字段使用默认值。[br]
## 兼容旧格式（effect_type + effect_params）自动转换为新 effects 数组格式。
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

	prop_category = data.get("prop_category", "instant") as String
	modifier = data.get("modifier", {}) as Dictionary
	priority = data.get("priority", 0) as int

	var requires_raw = data.get("requires", [])
	if requires_raw is Array:
		var req_arr: Array[String] = []
		for req in requires_raw:
			req_arr.append(req as String)
		requires = req_arr

	var conflicts_raw = data.get("conflicts_with", [])
	if conflicts_raw is Array:
		var conf_arr: Array[String] = []
		for conf in conflicts_raw:
			conf_arr.append(conf as String)
		conflicts_with = conf_arr

	# 解析效果配置 — 兼容新旧两种格式
	_parse_effects(data)

	var tags_raw = data.get("tags", [])
	if tags_raw is Array:
		var tags_arr: Array[String] = []
		for tag in tags_raw:
			tags_arr.append(tag as String)
		tags = tags_arr

# ============================================================
# 9. 公开方法 — 便捷属性
# ============================================================

## 首个效果的效果类型（便捷访问）。[br]
## 对于只有一个效果的道具，可直接通过此属性获取类型。
## 等效于 [code]effects[0].type[/code]。
var effect_type: StringName:
	get:
		if effects.size() > 0:
			return effects[0].get("type", &"") as StringName
		return &""

## 首个效果的效果参数（便捷访问）。[br]
## 等效于 [code]effects[0].params[/code]。
var effect_params: Dictionary:
	get:
		if effects.size() > 0:
			return effects[0].get("params", {}) as Dictionary
		return {}

# ============================================================
# 10. 私有方法
# ============================================================

## 解析效果配置，兼容新旧两种 JSON 格式。[br]
## 新格式：[code]{ "effects": [{"type": "...", "params": {...}}] }[/code][br]
## 旧格式：[code]{ "effect_type": "...", "effect_params": {...} }[/code]
func _parse_effects(data: Dictionary) -> void:
	# 优先使用新格式
	if data.has("effects"):
		var raw: Array = data.get("effects", []) as Array
		for entry in raw:
			if entry is Dictionary:
				var entry_dict: Dictionary = entry as Dictionary
				var effect: Dictionary = {}
				var type_str: String = entry_dict.get("type", "") as String
				effect["type"] = StringName(type_str) if not type_str.is_empty() else &""
				effect["params"] = entry_dict.get("params", {}) as Dictionary
				effects.append(effect)
		return

	# 兼容旧格式：effect_type + effect_params
	var old_type: String = data.get("effect_type", "") as String
	if not old_type.is_empty():
		var effect: Dictionary = {}
		effect["type"] = StringName(old_type)
		effect["params"] = data.get("effect_params", {}) as Dictionary
		effects.append(effect)
