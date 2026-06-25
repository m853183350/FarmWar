## 领域类 — 维护特定领域内所有活跃修饰器的有序链。
##
## 每个 Domain 实例管理一个领域（如 tile、player、warehouse）内所有
## 已注册的 MODIFIER 效果。修饰器按 [member priority] 排序后形成计算链，
## 供游戏系统查询属性最终值。
##
## 修饰器的计算方式由标签（tags）决定：
##   - [code]flat[/code]：固定值加成（result += value）
##   - [code]additive[/code]：基于原始值的叠加（result += base_value × value）
##   - [code]multiplicative[/code]：乘算（result *= 1.0 + value）
##   - [code]override[/code]：取最高值（result = max(result, value)）
##
## 标签无法覆盖的复杂场景，可通过 [code]calculator: Callable[/code] 自定义。
##
## 修饰器可通过 [code]target_filter[/code] 字典限制生效范围。
## 例如 [code]{ "tile_type": "farmland" }[/code] 表示只对农田地块生效。
## [method calculate] 接受一个 [param context] 字典，仅当修饰器的
## [code]target_filter[/code] 的所有键值对与 [param context] 匹配时，该修饰器才参与计算。
class_name Domain extends RefCounted

# ============================================================
# 5. 公开变量
# ============================================================

## 领域名称，如 "tile"、"player"、"warehouse"。
var domain_name: String = ""

# ============================================================
# 6. 私有变量
# ============================================================

## 修饰器链。[br]
## 每个元素为 [Dictionary]：{prop_id, stat, value, priority, tags, calculator, target_filter}[br]
## 按 [member priority] 升序排列。
var _chain: Array[Dictionary] = []

# ============================================================
# 9. 公开方法 — 修饰器管理
# ============================================================

## 添加一个修饰器到链中。[br]
## [param modifier_data] 修饰器配置（来自 JSON）。[br]
## [param prop_id] 道具 ID。[br]
## [param count] 堆叠数量，实际 value 为 modifier_data.value × count。
func add_modifier(modifier_data: Dictionary, prop_id: String, count: int) -> void:
	var stat: String = modifier_data.get("stat", "") as String
	var value: float = modifier_data.get("value", 0.0) as float * float(count)
	var priority: int = modifier_data.get("priority", 0) as int
	var tags: Array = modifier_data.get("tags", []) as Array
	var calculator: Callable = modifier_data.get("calculator", Callable()) as Callable
	var target_filter: Dictionary = modifier_data.get("target_filter", {}) as Dictionary

	_chain.append({
		"prop_id": prop_id,
		"stat": stat,
		"value": value,
		"priority": priority,
		"tags": tags,
		"calculator": calculator,
		"target_filter": target_filter,
	})
	sort_chain()

## 移除指定道具的所有修饰器条目。
func remove_modifier(prop_id: String) -> void:
	_chain = _chain.filter(func(d: Dictionary) -> bool: return d.prop_id != prop_id)

# ============================================================
# 9. 公开方法 — 计算
# ============================================================

## 计算指定属性的最终值。[br]
## 遍历链中所有匹配 [param stat_name] 的修饰器，按优先级依次应用。[br]
## [param stat_name] 属性名（如 "fertility_modifier_1"、"yield_multiplier"）。[br]
## [param base_value] 基础值（通常是 0.0 或默认倍率如 1.0）。[br]
## [param context] 可选：调用者提供的上下文（如 [code]{ "tile_type": "farmland" }[/code]）。[br]
## 仅 [code]target_filter[/code] 与 context 匹配的修饰器参与计算。[br]
## 返回聚合后的值。
func calculate(stat_name: String, base_value: float, context: Dictionary = {}) -> float:
	var result: float = base_value
	for modifier: Dictionary in _chain:
		if modifier.stat != stat_name:
			continue

		# 检查 target_filter
		if not _matches_filter(modifier, context):
			continue

		var value: float = modifier.get("value", 0.0) as float
		var tags: Array = modifier.get("tags", []) as Array
		var calculator: Callable = modifier.get("calculator", Callable()) as Callable

		# 自定义 calculator 优先
		if calculator.is_valid():
			result = calculator.call(result)
			continue

		# 标签自动计算
		if "flat" in tags:
			result += value
		elif "additive" in tags:
			result += base_value * value
		elif "multiplicative" in tags:
			result *= (1.0 + value)
		elif "override" in tags:
			result = max(result, value)

	return result

# ============================================================
# 9. 公开方法 — 排序
# ============================================================

## 按 [member priority] 升序重排修饰器链。
func sort_chain() -> void:
	_chain.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = a.get("priority", 0) as int
		var pb: int = b.get("priority", 0) as int
		return pa < pb
	)

# ============================================================
# 9. 公开方法 — 查询
# ============================================================

## 获取链中所有修饰器（用于调试）。
func get_chain() -> Array[Dictionary]:
	return _chain

# ============================================================
# 10. 私有方法
# ============================================================

## 检查修饰器的 [code]target_filter[/code] 是否与调用者上下文匹配。[br]
## 若修饰器无 target_filter（空字典），匹配所有上下文（返回 true）。[br]
## 若 context 为空字典（调用者未提供上下文），也返回 true（向后兼容）。[br]
## 否则，[code]target_filter[/code] 的所有键值对必须与 context 完全一致。
func _matches_filter(modifier: Dictionary, context: Dictionary) -> bool:
	var target_filter: Dictionary = modifier.get("target_filter", {}) as Dictionary
	if target_filter.is_empty():
		return true
	if context.is_empty():
		return true
	for key: String in target_filter:
		var expected = target_filter[key]
		var actual = context.get(key)
		if actual != expected:
			return false
	return true
