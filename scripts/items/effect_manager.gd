## 效果管理器 — 管理效果注册表和执行流程。
##
## 由 [PropManager] 创建和持有，负责：
##   - 效果实例注册表（effect_type → PropEffectBase）
##   - 运行时上下文构建（服务引用 + 触发数据）
##   - 条件评估（冷却、概率等）
##   - 效果执行（支持堆叠：持有 n 个道具执行 n 次）
##
## 设计原则：
##   - 效果实例是无状态的单例（一个 effect_type 对应一个实例），状态由外部管理
##   - 上下文在每次执行时动态构建，效果通过 context 访问所有服务
##   - 条件评估在效果执行前统一进行
##   - 支持复合效果（一个道具可配置多个效果）
class_name EffectManager extends RefCounted

const PropEffectBaseClass = preload("res://scripts/items/effects/prop_effect_base.gd")

# ============================================================
# 5. 公开变量
# ============================================================

## 效果注册表。[br]
## 结构：[code]{ effect_type: PropEffectBase }[/code]
var registry: Dictionary = {}

# ============================================================
# 6. 私有变量
# ============================================================

## 上下文提供器（[Callable]）。[br]
## 由 [PropManager] 设置，每次执行效果前调用以获取最新的服务引用。[br]
## 返回值应为 [Dictionary]，如 [code]{ "storage": Storage, ... }[/code]。
var _context_provider: Callable = Callable()

# ============================================================
# 9. 公开方法 — 注册
# ============================================================

## 设置上下文提供器。[br]
## [param provider] 无参 Callable，返回 [Dictionary] 包含服务引用。
func set_context_provider(provider: Callable) -> void:
	_context_provider = provider

## 注册一个效果实例。[br]
## 相同 [param effect_type] 的后续注册会覆盖之前的实例。[br]
## [param effect_type] 效果类型标识（如 [code]&"add_storage_item"[/code]）。[br]
## [param effect] [PropEffectBase] 子类实例。
func register_effect(effect_type: StringName, effect: PropEffectBase) -> void:
	if not effect is PropEffectBaseClass:
		push_error("EffectManager: 注册失败 — '%s' 不是 PropEffectBase 的子类" % effect_type)
		return
	registry[effect_type] = effect

## 取消注册效果类型。
func unregister_effect(effect_type: StringName) -> void:
	registry.erase(effect_type)

## 检查是否已注册指定效果类型。
func has_effect(effect_type: StringName) -> bool:
	return registry.has(effect_type)

## 获取已注册的效果类型列表。
func get_registered_types() -> Array[StringName]:
	var types: Array[StringName] = []
	for key: StringName in registry:
		types.append(key)
	return types

# ============================================================
# 9. 公开方法 — 执行
# ============================================================

## 执行指定道具的所有效果。[br]
## 支持堆叠：若 [param count] > 1，每个效果执行 [param count] 次。[br]
## 支持复合效果：若 [param prop_data] 配置了多个效果，全部依次执行。[br]
## [param prop_data] 道具定义数据（[PropData] 实例）。[br]
## [param count] 道具持有数量（堆叠次数）。[br]
## [param trigger_context] 触发时的信号数据（[Dictionary]），如
##   [code]{ "crop_node": Node2D, "grid_pos": Vector2i, "crop_id": "wheat_tier1" }[/code]。
func execute(prop_data: RefCounted, count: int, trigger_context: Dictionary) -> void:
	# 1. 获取效果配置列表
	var effects: Array = prop_data.get("effects") as Array
	if effects.is_empty():
		push_warning("EffectManager: 道具 '%s' 无效果配置" % prop_data.get("prop_id"))
		return

	# 2. 构建完整上下文（服务引用 + 触发数据）
	var context: Dictionary = _build_context(trigger_context)

	# 3. 逐个执行效果
	for effect_entry in effects:
		var effect_entry_dict: Dictionary = effect_entry as Dictionary
		_execute_single_effect(effect_entry_dict, count, context, prop_data)

# ============================================================
# 10. 私有方法 — 上下文
# ============================================================

## 构建运行时上下文。[br]
## 合并 _context_provider 返回的服务引用和触发时的信号数据。
func _build_context(trigger_context: Dictionary) -> Dictionary:
	var context: Dictionary = {}

	# 从 context_provider 获取服务引用
	if _context_provider.is_valid():
		var services = _context_provider.call()
		if services is Dictionary:
			context.merge(services as Dictionary, true)

	# 合并触发数据
	if not trigger_context.is_empty():
		context.merge(trigger_context, true)

	return context

# ============================================================
# 10. 私有方法 — 条件评估
# ============================================================

## 评估效果的所有前置条件。[br]
## 包括：效果实例的 [method PropEffectBase.can_trigger] 钩子。
func _evaluate_conditions(effect_instance: PropEffectBase, params: Dictionary, context: Dictionary, prop_data: RefCounted) -> bool:
	# 效果实例自身的条件判断
	if not effect_instance.can_trigger(params, context):
		var prop_id: String = prop_data.get("prop_id") as String
		print("EffectManager: 条件不满足，跳过道具 '%s'" % prop_id)
		return false

	return true

# ============================================================
# 10. 私有方法 — 单效果执行
# ============================================================

## 执行单个效果条目。[br]
## [param effect_entry] 效果配置 [Dictionary]，包含 [code]type[/code] 和 [code]params[/code]。[br]
## [param count] 堆叠次数。[br]
## [param context] 运行时上下文。[br]
## [param prop_data] 道具定义（用于日志）。
func _execute_single_effect(effect_entry: Dictionary, count: int, context: Dictionary, prop_data: RefCounted) -> void:
	var effect_type: StringName = effect_entry.get("type", &"") as StringName
	if effect_type.is_empty():
		push_error("EffectManager: 效果条目缺少 type 字段")
		return

	var effect_instance: PropEffectBase = registry.get(effect_type, null) as PropEffectBase
	if effect_instance == null:
		push_warning("EffectManager: 未注册的效果类型 '%s'" % effect_type)
		return

	var params: Dictionary = effect_entry.get("params", {}) as Dictionary

	# 评估条件
	if not _evaluate_conditions(effect_instance, params, context, prop_data):
		return

	# 根据效果类别分别处理
	var category: PropEffectBase.EffectCategory = effect_instance.get_category()

	match category:
		PropEffectBase.EffectCategory.INSTANT:
			# 即时效果：直接执行 count 次
			for _i: int in range(count):
				effect_instance.execute(params, context)

		PropEffectBase.EffectCategory.MODIFIER:
			# 修饰效果：只在首次应用时调用 on_apply，堆叠通过 params 中的 count 字段体现
			effect_instance.on_apply(params, context)

		PropEffectBase.EffectCategory.DURATION:
			# 持续效果：调用 on_apply，到期后由外部调用 on_remove
			effect_instance.on_apply(params, context)
