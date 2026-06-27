## 通用限时修饰器效果 — 桥接 EventBus 触发事件和 ModifierRegistry 临时修饰。
##
## 适用于所有"事件触发 → 临时属性加成 → 自动到期"的场景。
## 不同道具通过 JSON 配置的 [code]modifier_config[/code] 区分，
## 不需要每个道具写一个 GDScript 文件。
##
## 效果类别：[enum PropEffectBase.EffectCategory.DURATION]
##
## JSON 配置示例：
##   {
##     "type": "apply_timed_modifier",
##     "params": {
##       "modifier_config": {
##         "target_domains": ["tile"],
##         "stat": "growth_speed_mod",
##         "value": 1.0,
##         "priority": 50,
##         "tags": ["multiplicative"]
##       },
##       "duration_ticks": 60
##     }
##   }
class_name ApplyTimedModifierEffect extends PropEffectBase

# ============================================================
# 9. 公开方法 — 类别
# ============================================================

## 返回效果类别：[enum EffectCategory.DURATION]
func get_category() -> EffectCategory:
	return EffectCategory.DURATION

# ============================================================
# 9. 公开方法 — 条件钩子
# ============================================================

## 检查触发条件。[br]
## 默认返回 true（条件由 [PropManager] 层的 [code]trigger_condition[/code] 过滤）。
func can_trigger(_params: Dictionary, _context: Dictionary) -> bool:
	return true

# ============================================================
# 9. 公开方法 — 生命周期
# ============================================================

## 效果生效。[br]
## 从 [param context] 获取 [PropManager] 引用，将 [param params] 中的
## [code]modifier_config[/code] 临时注册到 [ModifierRegistry]。[br]
## [param params] 需包含：[code]modifier_config[/code]（修饰器配置）、
## [code]prop_id[/code]（来源道具 ID）、[code]count[/code]（堆叠次数）。
func on_apply(params: Dictionary, context: Dictionary) -> void:
	var pm: PropManager = context.get("prop_manager") as PropManager
	if pm == null:
		push_error("ApplyTimedModifierEffect: context 中缺少 prop_manager 引用")
		return

	var modifier_config: Dictionary = params.get("modifier_config", {}) as Dictionary
	if modifier_config.is_empty():
		push_error("ApplyTimedModifierEffect: params 中缺少 modifier_config")
		return

	var prop_id: String = params.get("prop_id", "") as String
	if prop_id.is_empty():
		push_error("ApplyTimedModifierEffect: params 中缺少 prop_id")
		return

	var count: int = params.get("count", 1) as int

	# 先清理旧的同名修饰器（刷新策略），再注册新的
	var mr: ModifierRegistry = pm.get_modifier_registry()
	mr.unregister_modifier(prop_id)
	mr.register_modifier(modifier_config, prop_id, count)

	# 注意：不在此处通知外部系统重算，由 EffectManager 在完整流程结束后统一通知

	print("ApplyTimedModifierEffect: 临时修饰器生效 — prop=%s, stat=%s, value=%.2f" % [prop_id, modifier_config.get("stat", "?"), modifier_config.get("value", 0.0)])

## 效果到期/移除。[br]
## 从 [ModifierRegistry] 注销临时修饰器，通知外部系统重算。
func on_remove(params: Dictionary, context: Dictionary) -> void:
	var pm: PropManager = context.get("prop_manager") as PropManager
	if pm == null:
		return

	var prop_id: String = params.get("prop_id", "") as String
	if prop_id.is_empty():
		return

	var mr: ModifierRegistry = pm.get_modifier_registry()
	mr.unregister_modifier(prop_id)
	# 注意：不在此处通知外部系统重算，由 EffectManager/DurationTracker 在合适时机统一通知

	print("ApplyTimedModifierEffect: 临时修饰器移除 — prop=%s" % prop_id)

## INSTANT 类别不适用本效果。
func execute(_params: Dictionary, _context: Dictionary) -> void:
	push_error("ApplyTimedModifierEffect: 不支持 execute()，请使用 on_apply/on_remove")
