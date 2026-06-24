## 道具管理器 — 管理玩家持有道具的 Node。
##
## 挂载在 [Player] 节点下，负责加载道具定义库、维护持有状态、
## 动态订阅 [EventBus] 信号并在触发时委托 [EffectManager] 执行道具效果。
##
## 设计参考 roguelike 游戏的道具系统：
##   - 数据驱动：道具定义存放在 [code]config/items/props/*.json[/code]
##   - 事件触发：通过 EventBus 信号驱动效果执行
##   - 动态绑定：仅连接已持有道具所需的信号，节省开销
##   - 堆叠机制：max_stack 控制持有上限，持有多个时效果叠加
##   - 效果分离：效果逻辑由 [EffectManager] 独立管理
class_name PropManager extends Node

const JsonConfigLoader = preload("res://scripts/utils/json_loader.gd")
const PropDataClass = preload("res://scripts/items/prop_data.gd")
const EffectManagerClass = preload("res://scripts/items/effect_manager.gd")
const AddStorageItemEffectClass = preload("res://scripts/items/effects/add_storage_item_effect.gd")

# ============================================================
# 1. 信号
# ============================================================

## 道具数量增加时发出。
signal prop_added(prop_id: String, count: int)

## 道具数量减少时发出。
signal prop_removed(prop_id: String, count: int)

# ============================================================
# 3. 常量
# ============================================================

## 道具定义配置目录路径。
const PROP_CONFIG_DIR: String = "res://config/items/props/"

## 支持的触发信号常量。
const TRIGGER_CROP_MATURED: StringName = &"crop_matured"
const TRIGGER_CROP_HARVESTED: StringName = &"crop_harvested"
const TRIGGER_CROP_STAGE_CHANGED: StringName = &"crop_stage_changed"

# ============================================================
# 5. 公开变量
# ============================================================

## 运行时道具持有量。[br]
## 结构：[code]{ prop_id: int_count }[/code]
var props: Dictionary = {}

## 道具定义缓存。[br]
## 结构：[code]{ prop_id: RefCounted }[/code] — 每个值是 [PropData] 实例。
var prop_library: Dictionary = {}

# ============================================================
# 6. 私有变量
# ============================================================

## 仓库引用，在 [method _ready] 中从 Player 父节点获取并缓存。[br]
## 一场游戏中 Storage 位置不会变化，缓存避免每次效果执行时重复查找。
var _storage: Storage = null

## 效果管理器，负责效果注册、条件评估和执行。
var _effect_manager: RefCounted = null

## 信号绑定追踪。[br]
## 结构：[code]{ signal_name: Array[String] }[/code] — 每个信号关联的道具 ID 列表。
var _signal_bindings: Dictionary = {}

## 已连接信号的追踪。[br]
## 结构：[code]{ signal_name: bool }[/code]
var _connected_signals: Dictionary = {}

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	_cache_storage()
	_setup_effect_manager()
	_load_prop_library()
	_register_debug_info()
	print("PropManager: 初始化完成，已加载 %d 个道具定义，%d 个效果类型" % [prop_library.size(), _effect_manager.registry.size()])

func _exit_tree() -> void:
	_disconnect_all_signals()

# ============================================================
# 9. 公开方法 — 道具管理
# ============================================================

## 添加一个道具到玩家持有集合。[br]
## 首次添加该道具时自动连接对应的 EventBus 信号。[br]
## 当持有数量达到最大堆叠上限时拒绝添加。[br]
## 返回 [code]true[/code] 表示添加成功。
func add_prop(prop_id: String) -> bool:
	if not prop_library.has(prop_id):
		push_error("PropManager: 未知道具 '%s'，无法添加" % prop_id)
		return false

	var data: RefCounted = prop_library[prop_id] as RefCounted
	if data == null:
		return false

	var max_stack: int = data.get("max_stack") as int
	var current_count: int = props.get(prop_id, 0) as int

	# 检查堆叠上限
	if max_stack > 0 and current_count >= max_stack:
		push_warning("PropManager: 道具 '%s' 已达堆叠上限 %d" % [prop_id, max_stack]) #TODO:道具上限后的处理
		return false

	# 增加计数
	var new_count: int = current_count + 1
	props[prop_id] = new_count

	# 首次添加时连接信号
	if current_count == 0:
		var trigger_signal: StringName = data.get("trigger_signal") as StringName
		_ensure_signal_connected(trigger_signal, prop_id)

	prop_added.emit(prop_id, new_count)
	_update_debug_info()
	var prop_name: String = data.get("prop_name") as String
	print("PropManager: 获得道具 '%s'（%d/%d）" % [prop_name, new_count, max_stack if max_stack > 0 else -1])
	return true

## 移除一个道具。数量归零时自动断开对应信号。[br]
## 返回 [code]true[/code] 表示移除成功，[code]false[/code] 表示未持有该道具。
func remove_prop(prop_id: String) -> bool:
	if not props.has(prop_id):
		return false

	var current_count: int = props[prop_id] as int
	var new_count: int = current_count - 1
	var data: RefCounted = prop_library.get(prop_id) as RefCounted

	if new_count <= 0:
		props.erase(prop_id)
		# 断开该道具关联的信号绑定
		if data != null:
			var trigger_signal: StringName = data.get("trigger_signal") as StringName
			if not trigger_signal.is_empty():
				_remove_signal_binding(trigger_signal, prop_id)
	else:
		props[prop_id] = new_count

	prop_removed.emit(prop_id, new_count)
	_update_debug_info()
	var prop_name: String = data.get("prop_name") as String if data != null else prop_id
	print("PropManager: 失去道具 '%s'（剩余 %d）" % [prop_name, new_count])
	return true

# ============================================================
# 9. 公开方法 — 查询
# ============================================================

## 检查是否持有指定道具（数量 > 0）。
func has_prop(prop_id: String) -> bool:
	return props.has(prop_id) and (props[prop_id] as int) > 0

## 获取道具当前持有数量。
func get_prop_count(prop_id: String) -> int:
	return props.get(prop_id, 0) as int

## 获取所有持有道具的列表。[br]
## 返回 [code]Array[Dictionary][/code]，每项包含 [code]prop_id[/code]、[code]count[/code]、[code]data[/code]。
func get_all_props() -> Array:
	var result: Array = []
	for prop_id: String in props:
		var count: int = props[prop_id] as int
		if count > 0:
			result.append({
				"prop_id": prop_id,
				"count": count,
				"data": prop_library.get(prop_id),
			})
	return result

# ============================================================
# 10. 私有方法 — 初始化
# ============================================================

## 缓存 Storage 引用。[br]
## PropManager 由 Player 创建，Storage 是 Player 的直接子节点，[br]
## 一场游戏中 Storage 位置不变，初始化时缓存一次即可。
func _cache_storage() -> void:
	var player: Node = get_parent()
	if player == null:
		push_error("PropManager: 获取父节点失败，无法缓存 Storage 引用")
		return

	_storage = player.get_node_or_null("Storage") as Storage
	if _storage == null:
		push_error("PropManager: 未找到 Storage 子节点")

## 初始化 [EffectManager]。[br]
## 创建 EffectManager 实例、设置上下文提供器、注册所有效果类型。[br]
## 新增效果只需在此方法中添加一行 [method EffectManager.register_effect] 调用。
func _setup_effect_manager() -> void:
	_effect_manager = EffectManagerClass.new()

	# 设置上下文提供器 — 返回效果执行时需要的服务引用
	_effect_manager.set_context_provider(_provide_effect_context)

	# 注册效果类型 — 新增效果在此注册
	var add_item_effect: RefCounted = AddStorageItemEffectClass.new()
	_effect_manager.register_effect(&"add_storage_item", add_item_effect)

## 上下文提供器 — 返回服务引用 [Dictionary]。[br]
## 由 [EffectManager] 在每次执行效果前调用，确保获取最新的服务引用。
func _provide_effect_context() -> Dictionary:
	return {
		"storage": _storage,
	}

## 从 [constant PROP_CONFIG_DIR] 加载所有道具 JSON 定义文件。
func _load_prop_library() -> void:
	if not DirAccess.dir_exists_absolute(PROP_CONFIG_DIR):
		push_warning("PropManager: 道具配置目录不存在: %s" % PROP_CONFIG_DIR)
		return

	var dir: DirAccess = DirAccess.open(PROP_CONFIG_DIR)
	if dir == null:
		push_error("PropManager: 无法打开道具配置目录: %s" % PROP_CONFIG_DIR)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path: String = PROP_CONFIG_DIR + file_name
			var data: Dictionary = JsonConfigLoader.load_config_file(full_path, "PropManager")
			if data.is_empty():
				push_error("PropManager: 加载道具配置失败: %s" % full_path)
				file_name = dir.get_next()
				continue

			var prop_id: String = data.get("prop_id", "") as String
			if prop_id.is_empty():
				push_error("PropManager: 道具配置缺少 prop_id: %s" % full_path)
				file_name = dir.get_next()
				continue

			if prop_library.has(prop_id):
				push_warning("PropManager: 道具 ID 重复 '%s'，后加载的将覆盖之前的" % prop_id)

			var prop_instance: RefCounted = PropDataClass.new()
			prop_instance.init_from_dict(data)
			prop_library[prop_id] = prop_instance

		file_name = dir.get_next()

	dir.list_dir_end()

# ============================================================
# 10. 私有方法 — 信号管理
# ============================================================

## 确保指定信号已连接，并将 [param prop_id] 加入绑定列表。[br]
## 若信号尚未连接，则调用 [method _connect_signal] 建立连接。
func _ensure_signal_connected(signal_name: StringName, prop_id: String) -> void:
	if signal_name.is_empty():
		return

	# 将 prop_id 加入该信号的绑定列表
	if not _signal_bindings.has(signal_name):
		_signal_bindings[signal_name] = []
	var bindings: Array = _signal_bindings[signal_name] as Array
	if prop_id not in bindings:
		bindings.append(prop_id)

	# 若尚未连接则建立连接
	if not _connected_signals.get(signal_name, false):
		_connect_signal(signal_name)

## 从信号绑定列表中移除 [param prop_id]。[br]
## 若该信号不再关联任何道具，则断开连接。
func _remove_signal_binding(signal_name: StringName, prop_id: String) -> void:
	if signal_name.is_empty() or not _signal_bindings.has(signal_name):
		return

	var bindings: Array = _signal_bindings[signal_name] as Array
	bindings.erase(prop_id)

	if bindings.is_empty():
		_signal_bindings.erase(signal_name)
		_disconnect_signal(signal_name)

## 连接到 EventBus 上的指定信号。
func _connect_signal(signal_name: StringName) -> void:
	if not EventBus:
		push_error("PropManager: EventBus 不可用，无法连接信号 '%s'" % signal_name)
		return

	var handler: Callable = _get_signal_handler(signal_name)
	if handler.is_null():
		push_error("PropManager: 不支持的触发信号: '%s'" % signal_name)
		return

	var err: Error = EventBus.connect(signal_name, handler)
	if err == OK:
		_connected_signals[signal_name] = true
		print("PropManager: 已连接信号 '%s'" % signal_name)
	else:
		push_error("PropManager: 连接信号 '%s' 失败 (err=%d)" % [signal_name, err])

## 从 EventBus 断开指定信号的连接。
func _disconnect_signal(signal_name: StringName) -> void:
	if not EventBus:
		return
	if not _connected_signals.get(signal_name, false):
		return

	var handler: Callable = _get_signal_handler(signal_name)
	if handler.is_null():
		return

	EventBus.disconnect(signal_name, handler)
	_connected_signals.erase(signal_name)
	print("PropManager: 已断开信号 '%s'" % signal_name)

## 断开所有已连接的信号。
func _disconnect_all_signals() -> void:
	for signal_name: StringName in _connected_signals.keys():
		_disconnect_signal(signal_name)
	_signal_bindings.clear()

## 根据信号名返回对应的处理 Callable。
func _get_signal_handler(signal_name: StringName) -> Callable:
	match signal_name:
		TRIGGER_CROP_MATURED:
			return _on_crop_matured
		TRIGGER_CROP_HARVESTED:
			return _on_crop_harvested
		TRIGGER_CROP_STAGE_CHANGED:
			return _on_crop_stage_changed
		_:
			return Callable()

# ============================================================
# 10. 私有方法 — 信号处理
# ============================================================

## 响应 [signal EventBus.crop_matured] 信号。[br]
## 作物进入成熟阶段（可收获）时调用。[br]
## 注意：成熟不等同于收获，本信号在收获之前发出。
func _on_crop_matured(crop_node: Node2D, grid_pos: Vector2i, crop_id: String) -> void:
	print("PropManager: 收到 crop_matured — crop=%s, pos=(%d,%d)" % [crop_id, grid_pos.x, grid_pos.y])
	var trigger_context: Dictionary = {
		"trigger_signal": TRIGGER_CROP_MATURED,
		"crop_node": crop_node,
		"grid_pos": grid_pos,
		"crop_id": crop_id,
	}
	_process_trigger(TRIGGER_CROP_MATURED, trigger_context)

## 响应 [signal EventBus.crop_harvested] 信号。
func _on_crop_harvested(yields: Array, crop_id: String) -> void:
	print("PropManager: 收到 crop_harvested — crop=%s, yields=%d" % [crop_id, yields.size()])
	var trigger_context: Dictionary = {
		"trigger_signal": TRIGGER_CROP_HARVESTED,
		"yields": yields,
		"crop_id": crop_id,
	}
	_process_trigger(TRIGGER_CROP_HARVESTED, trigger_context)

## 响应 [signal EventBus.crop_stage_changed] 信号。
func _on_crop_stage_changed(crop_node: Node2D, grid_pos: Vector2i, crop_id: String, old_stage: int, new_stage: int, is_mature: bool) -> void:
	var trigger_context: Dictionary = {
		"trigger_signal": TRIGGER_CROP_STAGE_CHANGED,
		"crop_node": crop_node,
		"grid_pos": grid_pos,
		"crop_id": crop_id,
		"old_stage": old_stage,
		"new_stage": new_stage,
		"is_mature": is_mature,
	}
	_process_trigger(TRIGGER_CROP_STAGE_CHANGED, trigger_context)

## 对指定信号关联的所有道具执行效果。[br]
## 委托给 [EffectManager] 处理效果查找、条件评估和执行。[br]
## 持有多个相同道具时效果叠加（执行 count 次）。[br]
## [param trigger_context] 触发时的信号数据，传递给 EffectManager 构建运行时上下文。
func _process_trigger(signal_name: StringName, trigger_context: Dictionary) -> void:
	var bindings: Array = _signal_bindings.get(signal_name, []) as Array
	if bindings.is_empty():
		return

	for prop_id: String in bindings:
		var count: int = props.get(prop_id, 0) as int
		if count <= 0:
			continue

		var data: RefCounted = prop_library.get(prop_id) as RefCounted
		if data == null:
			continue

		var prop_name: String = data.get("prop_name") as String
		print("PropManager: 触发道具 '%s'（信号: %s, 持有: %d）" % [prop_name, signal_name, count])

		# 委托给 EffectManager 执行效果
		_effect_manager.execute(data, count, trigger_context)

# ============================================================
# 10. 私有方法 — 调试
# ============================================================

## 注册调试信息到 [DebugOverlay]。
func _register_debug_info() -> void:
	_update_debug_info()

## 更新调试叠加层中的道具信息。
func _update_debug_info() -> void:
	if not is_inside_tree():
		return

	var debug_str: String = "Props (%d):\n" % props.size()
	if props.is_empty():
		debug_str += "  (none)\n"
	else:
		for prop_id: String in props:
			var count: int = props[prop_id] as int
			var data: RefCounted = prop_library.get(prop_id) as RefCounted
			var name_str: String = data.get("prop_name") as String if data != null else prop_id
			debug_str += "  %s x%d\n" % [name_str, count]

	# Signal bindings info
	debug_str += "\nSignal Bindings:\n"
	if _signal_bindings.is_empty():
		debug_str += "  (none)\n"
	else:
		for signal_name: StringName in _signal_bindings:
			var bindings: Array = _signal_bindings[signal_name] as Array
			debug_str += "  %s: %s\n" % [signal_name, str(bindings)]

	# EffectManager info
	if _effect_manager != null:
		debug_str += "\nEffectManager:\n"
		var registered: Array[StringName] = _effect_manager.get_registered_types()
		if registered.is_empty():
			debug_str += "  (no effects registered)\n"
		else:
			for effect_type: StringName in registered:
				debug_str += "  %s: OK\n" % effect_type
	else:
		debug_str += "\nEffectManager: NULL\n"

	# Storage status
	debug_str += "\nStorage: %s\n" % ("OK" if _storage != null else "NULL")

	DebugOverlay.set_entry("PropManager", debug_str)
