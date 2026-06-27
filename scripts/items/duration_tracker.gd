## DURATION 效果的调度层 — 管理所有限时效果的计时和到期。
##
## 由 [EffectManager] 创建和持有，负责：
##   - 注册限时效果（记录 prop_id、effect_instance、params、context、剩余 tick）
##   - 每 [member TickSystem.tick_elapsed] 递减所有活跃效果的剩余 tick
##   - 到期时调用 [method PropEffectBase.on_remove] 并清理
##   - 支持按 prop_id 批量清理（道具被移除时）
##
## 设计原则：
##   - 懒惰连接：有活跃效果时才连接 TickSystem，清空时断开（节省开销）
##   - 只负责计时 + 到期通知，不关心效果的具体逻辑
##   - instance_id 自增，支持精确追踪/取消单个效果实例
class_name DurationTracker extends RefCounted

# ============================================================
# 1. 信号
# ============================================================

## DURATION 效果到期时发出。
signal duration_expired(prop_id: String, instance_id: int)

## DURATION 效果被注册时发出（用于 UI 更新等）。
signal duration_registered(prop_id: String, total_ticks: int)

# ============================================================
# 5. 公开变量
# ============================================================

## 活跃 DURATION 效果列表。[br]
## 每个条目：[code]{ instance_id, prop_id, effect_type, effect_instance, params, context, remaining_ticks, total_ticks }[/code]
var active_effects: Array[Dictionary] = []

# ============================================================
# 6. 私有变量
# ============================================================

## 自增 ID 计数器。
var _next_instance_id: int = 0

## 是否已连接到 TickSystem。
var _tick_connected: bool = false

## 修饰器变更通知回调。[br]
## 由 [EffectManager] 设置，在自然到期时调用以通知外部系统重算。[br]
## 注意：主动清理（unregister_by_prop）时不调用，由调用者负责通知。
var _notify_callback: Callable = Callable()

# ============================================================
# 9. 公开方法 — 注册/注销
# ============================================================

## 设置修饰器变更通知回调。[br]
## [param cb] 无参 Callable，在效果自然到期时调用以通知外部系统重算。
func set_notify_callback(cb: Callable) -> void:
	_notify_callback = cb

## 注册一个限时效果。[br]
## 若 [param duration_ticks] <= 0，直接调用 [method PropEffectBase.on_remove] 并返回 -1。[br]
## [param effect_instance] 效果实例（到期时调用其 [method PropEffectBase.on_remove]）。[br]
## [param params] 效果参数（含 [code]modifier_config[/code]、[code]duration_ticks[/code] 等）。[br]
## [param context] 触发时的运行时上下文。[br]
## [param duration_ticks] 持续 tick 数。[br]
## [param prop_id] 来源道具 ID。[br]
## 返回 instance_id（可用于精确取消），失败返回 -1。
func register(effect_instance: PropEffectBase, params: Dictionary, context: Dictionary, duration_ticks: int, prop_id: String) -> int:
	if duration_ticks <= 0:
		push_warning("DurationTracker: duration_ticks <= 0，道具 '%s' 效果立即到期" % prop_id)
		effect_instance.on_remove(params, context)
		return -1

	var instance_id: int = _next_instance_id
	_next_instance_id += 1

	active_effects.append({
		"instance_id": instance_id,
		"prop_id": prop_id,
		"effect_type": params.get("type", ""),
		"effect_instance": effect_instance,
		"params": params,
		"context": context,
		"remaining_ticks": duration_ticks,
		"total_ticks": duration_ticks,
	})

	_ensure_tick_connected()
	duration_registered.emit(prop_id, duration_ticks)
	print("DurationTracker: 注册 DURATION 效果 #%d — prop=%s, ticks=%d" % [instance_id, prop_id, duration_ticks])
	return instance_id

## 提前终止指定效果实例。[br]
## 调用 [method PropEffectBase.on_remove] 后从活跃列表移除。[br]
## 返回 [code]true[/code] 表示找到并移除成功。
func unregister(instance_id: int) -> bool:
	for i: int in range(active_effects.size()):
		var entry: Dictionary = active_effects[i]
		if entry["instance_id"] == instance_id:
			_call_on_remove(entry)
			active_effects.remove_at(i)
			_check_empty()
			return true
	return false

## 清理指定道具的所有活跃 DURATION 效果。[br]
## 当道具被移除时调用。返回清理的数量。
func unregister_by_prop(prop_id: String) -> int:
	var removed: int = 0
	var i: int = active_effects.size() - 1
	while i >= 0:
		var entry: Dictionary = active_effects[i]
		if entry["prop_id"] == prop_id:
			_call_on_remove(entry)
			active_effects.remove_at(i)
			removed += 1
		i -= 1
	if removed > 0:
		_check_empty()
	return removed

# ============================================================
# 9. 公开方法 — 查询
# ============================================================

## 查询指定道具的活跃 DURATION 效果列表（调试用）。
func get_active_for_prop(prop_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in active_effects:
		if entry["prop_id"] == prop_id:
			result.append(entry)
	return result

## 获取所有活跃 DURATION 效果（调试面板用）。
func get_all_active() -> Array[Dictionary]:
	return active_effects

## 检查是否有活跃的 DURATION 效果。
func has_active() -> bool:
	return not active_effects.is_empty()

# ============================================================
# 10. 私有方法 — TickSystem 回调
# ============================================================

## TickSystem.tick_elapsed 回调。[br]
## 递减所有活跃效果的 [code]remaining_ticks[/code]，到期时调用 [method _expire]。
func _on_tick(_delta: float) -> void:
	var i: int = active_effects.size() - 1
	while i >= 0:
		var entry: Dictionary = active_effects[i]
		var remaining: int = entry["remaining_ticks"] as int - 1
		if remaining <= 0:
			_expire(entry)
			active_effects.remove_at(i)
		else:
			entry["remaining_ticks"] = remaining
		i -= 1
	_check_empty()

# ============================================================
# 10. 私有方法 — 到期处理
# ============================================================

## 到期处理：调用 [method PropEffectBase.on_remove]、发射信号、通知外部系统重算。
func _expire(entry: Dictionary) -> void:
	var prop_id: String = entry["prop_id"] as String
	var instance_id: int = entry["instance_id"] as int
	print("DurationTracker: 效果 #%d 到期 — prop=%s" % [instance_id, prop_id])
	_call_on_remove(entry)
	duration_expired.emit(prop_id, instance_id)
	# 通知外部系统修饰器已变更
	if _notify_callback.is_valid():
		_notify_callback.call()

# ============================================================
# 10. 私有方法 — 连接管理
# ============================================================

## 确保已连接 TickSystem（懒连接）。
func _ensure_tick_connected() -> void:
	if _tick_connected:
		return
	if TickSystem:
		TickSystem.tick_elapsed.connect(_on_tick)
		_tick_connected = true
		print("DurationTracker: 已连接 TickSystem.tick_elapsed")

## 当活跃列表清空时断开 TickSystem（节省开销）。
func _check_empty() -> void:
	if active_effects.is_empty() and _tick_connected:
		_disconnect_tick()

## 断开 TickSystem 连接（供外部在销毁前调用）。
func disconnect_tick() -> void:
	_disconnect_tick()

# ============================================================
# 10. 私有方法 — 安全包装
# ============================================================

## 安全调用效果实例的 [method PropEffectBase.on_remove]。[br]
## 当前没有 try/catch，直接调用。后续可加返回值检查。
func _call_on_remove(entry: Dictionary) -> void:
	var effect_instance: PropEffectBase = entry["effect_instance"] as PropEffectBase
	var params: Dictionary = entry["params"] as Dictionary
	var context: Dictionary = entry["context"] as Dictionary
	effect_instance.on_remove(params, context)

## 断开 TickSystem 连接。
func _disconnect_tick() -> void:
	if TickSystem and _tick_connected:
		TickSystem.tick_elapsed.disconnect(_on_tick)
		_tick_connected = false
		print("DurationTracker: 活跃列表为空，已断开 TickSystem")
