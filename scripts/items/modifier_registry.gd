## 修饰器注册中心 — 管理所有领域和活跃 MODIFIER 效果。
##
## 由 [PropManager] 创建和持有，负责：
##   - 领域管理：按需创建和维护 [Domain] 实例
##   - 修饰器注册/注销：道具添加/移除时更新对应领域
##   - 值查询：[method calculate] 供游戏系统查询某领域某属性的最终聚合值
##
## 设计原则：
##   - 修饰器是被动查询的（游戏系统主动调用 [method calculate]）
##   - 与 INSTANT 效果的事件驱动模型分离
##   - 道具级别（非全局），每个 [PropManager] 持有自己的实例
class_name ModifierRegistry extends RefCounted

const DomainClass = preload("res://scripts/items/domain.gd")

# ============================================================
# 6. 私有变量
# ============================================================

## 领域映射。[br]
## 结构：[code]{ domain_name: Domain }[/code]
var _domains: Dictionary = {}

## 活跃修饰器列表（用于查询和调试）。[br]
## 每个元素为 [Dictionary]：{prop_id, count, modifier_data}
var _active_modifiers: Array[Dictionary] = []

# ============================================================
# 9. 公开方法 — 注册
# ============================================================

## 注册一个修饰器到对应领域。[br]
## 支持跨领域：若 [param modifier_data] 的 [code]target_domains[/code] 包含
## 多个领域名称，则每个领域都会收到该修饰器。[br]
## [param modifier_data] 修饰器配置（来自 JSON）。[br]
## [param prop_id] 道具 ID。[br]
## [param count] 堆叠数量。
func register_modifier(modifier_data: Dictionary, prop_id: String, count: int) -> void:
	var target_domains: Array = modifier_data.get("target_domains", []) as Array
	for domain_name: String in target_domains:
		var domain: Domain = _ensure_domain(domain_name)
		domain.add_modifier(modifier_data, prop_id, count)
	_active_modifiers.append({
		"prop_id": prop_id,
		"count": count,
		"modifier_data": modifier_data,
	})

## 注销指定道具的所有修饰器。[br]
## 遍历所有领域，移除该道具的修饰器条目。
func unregister_modifier(prop_id: String) -> void:
	for domain in _domains.values():
		(domain as Domain).remove_modifier(prop_id)
	_active_modifiers = _active_modifiers.filter(
		func(d: Dictionary) -> bool: return d.prop_id != prop_id
	)

# ============================================================
# 9. 公开方法 — 查询
# ============================================================

## 查询某领域某属性的最终聚合值。[br]
## 如果指定领域不存在（无活跃修饰器），直接返回 [param base_value]。[br]
## [param domain_name] 领域名称（如 "tile"、"player"）。[br]
## [param stat_name] 属性名（如 "fertility_modifier_1"）。[br]
## [param base_value] 基础值（无修饰器时的默认值）。[br]
## [param context] 可选：调用者上下文（如 [code]{ "tile_type": "farmland" }[/code]），用于 [member Domain] 的 target_filter 匹配。
func calculate(domain_name: String, stat_name: String, base_value: float, context: Dictionary = {}) -> float:
	var domain: Domain = _domains.get(domain_name, null) as Domain
	if domain == null:
		return base_value
	return domain.calculate(stat_name, base_value, context)

## 重新计算所有领域（当修饰器参数变化时）。[br]
## 目前仅需重排序（值的计算是实时的）。
func recalculate_all() -> void:
	for domain in _domains.values():
		(domain as Domain).sort_chain()

# ============================================================
# 9. 公开方法 — 调试
# ============================================================

## 获取所有活跃修饰器列表（用于调试面板）。
func get_active_modifiers() -> Array[Dictionary]:
	return _active_modifiers

## 获取领域数量。
func get_domain_count() -> int:
	return _domains.size()

## 获取指定领域的所有修饰器链（用于调试）。
func get_domain_chain(domain_name: String) -> Array[Dictionary]:
	var domain: Domain = _domains.get(domain_name, null) as Domain
	if domain == null:
		return []
	return domain.get_chain()

# ============================================================
# 10. 私有方法
# ============================================================

## 确保领域存在，不存在则创建。
func _ensure_domain(domain_name: String) -> Domain:
	if not _domains.has(domain_name):
		var d := Domain.new()
		d.domain_name = domain_name
		_domains[domain_name] = d
	return _domains[domain_name] as Domain
