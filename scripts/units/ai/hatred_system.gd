## 仇恨系统 — 管理战斗单位的仇恨列表和威胁评估。
##
## 作为 [AIController] 的子节点挂载在战斗单位上。
## 周期性扫描范围内的敌方单位，计算威胁值并按优先级排序。
## 为 AIController 的自主战斗行为提供目标选择依据。
##
## 威胁值计算因素：
##   - 距离：越近威胁越高（1/distance × 10）
##   - 血量比例：血量越高威胁越高（hp_ratio × 5）
##   - 正在攻击我：威胁翻倍
##   - 正在攻击友方：威胁 × 1.3
class_name HatredSystem
extends Node

# ============================================================
# 2. 内部类
# ============================================================

## 仇恨条目，记录一个敌方目标及其威胁评估数据。
class HatredEntry:
	var target: CombatUnitBase = null
	var threat: float = 0.0
	var distance: float = 0.0
	var last_seen_tick: int = 0

	func _to_string() -> String:
		return "HatredEntry(target=%s, threat=%.1f, dist=%.1f)" % [
			target.unit_id if target else "null", threat, distance
		]

# ============================================================
# 3. 常量
# ============================================================

## 距离权重系数。威胁 += (1 / max(distance, 0.1)) × DISTANCE_WEIGHT
const DISTANCE_WEIGHT: float = 10.0

## 血量比例权重系数。威胁 += (current_hp / max_hp) × HEALTH_WEIGHT
const HEALTH_WEIGHT: float = 5.0

## 目标正在攻击我时的威胁倍率。
const ATTACKING_ME_MULTIPLIER: float = 2.0

## 目标正在攻击友方时的威胁倍率。
const ATTACKING_ALLY_MULTIPLIER: float = 1.3

# ============================================================
# 5. 公开变量
# ============================================================

## 扫描间隔（tick 数）。每 N tick 扫描一次，避免每 tick 全图扫描。
@export var scan_interval_ticks: int = 5

## 警戒范围（格数）。在此范围内的敌方单位会被加入仇恨列表。
@export var alert_range: float = 10.0

## 追击范围（格数）。超过此范围的仇恨目标将被移除（放弃追击）。
@export var chase_range: float = 20.0

## 最大仇恨列表条目数。
@export var max_hatred_entries: int = 10

# ============================================================
# 6. 私有变量
# ============================================================

## 距上次扫描已过的 tick 数。
var _ticks_since_scan: int = 0

## 仇恨列表（按威胁值降序排列）。
var _hatred_list: Array[HatredEntry] = []

# ============================================================
# 8. 生命周期
# ============================================================

func _ready() -> void:
	_ticks_since_scan = scan_interval_ticks  # 首次 tick 立即扫描

# ============================================================
# 9. 公开方法
# ============================================================

## 更新仇恨系统（由 AIController 每 tick 调用）。
## [param unit] 拥有此仇恨系统的战斗单位。
## [param current_tick] 当前游戏 tick 编号（用于记录最后发现时间）。
func update_hatred(unit: CombatUnitBase, current_tick: int) -> void:
	_ticks_since_scan += 1

	# 清除已死亡或无效的目标
	_cleanup_dead_targets()

	if _ticks_since_scan >= scan_interval_ticks:
		_ticks_since_scan = 0
		_scan_enemies(unit, current_tick)

## 获取当前最高威胁目标。
## 返回 null 表示无仇恨目标。
func get_primary_target() -> CombatUnitBase:
	if _hatred_list.is_empty():
		return null
	return _hatred_list[0].target

## 是否有仇恨目标。
func has_threat_target() -> bool:
	return not _hatred_list.is_empty()

## 获取仇恨列表（调试用，返回副本）。
func get_hatred_list() -> Array[HatredEntry]:
	return _hatred_list.duplicate()

## 获取仇恨列表中的目标数量。
func get_hatred_count() -> int:
	return _hatred_list.size()

## 手动添加一个仇恨目标（例如被攻击时）。
## [param target] 目标单位。
## [param base_threat] 基础威胁值。
func add_hatred_target(target: CombatUnitBase, base_threat: float = 50.0) -> void:
	if target == null:
		return

	# 检查是否已存在
	for entry: HatredEntry in _hatred_list:
		if entry.target == target:
			entry.threat += base_threat
			_sort_by_threat()
			return

	# 新增条目
	var entry: HatredEntry = HatredEntry.new()
	entry.target = target
	entry.threat = base_threat
	entry.distance = 0.0
	entry.last_seen_tick = 0  # 手动添加的不记录 tick
	_hatred_list.append(entry)
	_sort_by_threat()

	# 超过上限时移除最低威胁
	while _hatred_list.size() > max_hatred_entries:
		_hatred_list.pop_back()

## 清空仇恨列表。
func clear_hatred() -> void:
	_hatred_list.clear()

# ============================================================
# 10. 私有方法
# ============================================================

## 扫描范围内的敌方单位并更新仇恨列表。
func _scan_enemies(unit: CombatUnitBase, current_tick: int) -> void:
	if not is_instance_valid(unit):
		return

	var my_faction: int = unit.faction
	var my_pos: Vector2 = unit.grid_position

	# 获取所有可能的战斗单位（从 UnitManager 查询）
	# 当前项目只有 FarmWorker，后续 EnemyManager 接入后会包含敌方战斗单位
	var all_units: Array[Node] = []
	if UnitManager:
		# 获取所有注册的工人
		for worker in UnitManager.workers.values():
			if is_instance_valid(worker) and worker is CombatUnitBase:
				all_units.append(worker)

	# 也从场景树获取（后续敌方单位可能不在 UnitManager 中）
	var world: Node2D = unit.get_tree().get_first_node_in_group(&"world") if unit.is_inside_tree() else null
	if world:
		_scan_tree_for_combat_units(world, all_units)

	# 处理每个候选单位
	var seen_targets: Array[CombatUnitBase] = []
	for candidate: Node in all_units:
		var target: CombatUnitBase = candidate as CombatUnitBase
		if target == null or target == unit:
			continue
		if not target.is_alive():
			continue
		# 只扫描敌对阵营
		if target.faction == my_faction:
			continue

		var dist: float = my_pos.distance_to(target.grid_position)
		if dist > alert_range * unit.TILE_SIZE:
			continue  # 不在警戒范围内

		seen_targets.append(target)
		var threat: float = _calc_threat(target, unit, dist)
		_update_or_add_entry(target, threat, dist, current_tick)

	# 移除长时间未扫描到的目标（超出追击范围或不在警戒范围）
	_remove_unseen_targets(seen_targets, current_tick)

## 从场景树递归搜索战斗单位。
func _scan_tree_for_combat_units(node: Node, result: Array[Node]) -> void:
	for child: Node in node.get_children():
		if child is CombatUnitBase:
			result.append(child)
		_scan_tree_for_combat_units(child, result)

## 计算目标威胁值。
func _calc_threat(target: CombatUnitBase, unit: CombatUnitBase, distance: float) -> float:
	var threat: float = 0.0

	# 距离因子：越近威胁越高
	if distance > 0.0:
		threat += (1.0 / maxf(distance, 0.1)) * DISTANCE_WEIGHT * unit.TILE_SIZE

	# 血量比例因子：血量越高威胁越高（残血敌人威胁低）
	if target.max_health > 0.0:
		threat += (target.current_health / target.max_health) * HEALTH_WEIGHT

	# 目标正在攻击我 → 威胁翻倍
	if target.current_target == unit:
		threat *= ATTACKING_ME_MULTIPLIER

	# 目标正在攻击友方（faction 相同但不是我）→ 略微加威胁
	elif target.current_target != null and target.current_target is CombatUnitBase:
		var target_of_target: CombatUnitBase = target.current_target as CombatUnitBase
		if target_of_target.faction == unit.faction:
			threat *= ATTACKING_ALLY_MULTIPLIER

	return threat

## 更新已有条目或添加新条目。
func _update_or_add_entry(target: CombatUnitBase, threat: float, distance: float, current_tick: int) -> void:
	for entry: HatredEntry in _hatred_list:
		if entry.target == target:
			entry.threat = threat
			entry.distance = distance
			entry.last_seen_tick = current_tick
			_sort_by_threat()
			return

	# 新条目
	var entry: HatredEntry = HatredEntry.new()
	entry.target = target
	entry.threat = threat
	entry.distance = distance
	entry.last_seen_tick = current_tick
	_hatred_list.append(entry)
	_sort_by_threat()

	# 超过上限时移除最低威胁
	while _hatred_list.size() > max_hatred_entries:
		_hatred_list.pop_back()

## 移除本次扫描未看到的目标（超时或超出追击范围）。
func _remove_unseen_targets(seen: Array[CombatUnitBase], current_tick: int) -> void:
	var to_remove: Array[HatredEntry] = []
	for entry: HatredEntry in _hatred_list:
		if entry.target in seen:
			continue
		# 保留手动添加的条目（last_seen_tick == 0 表示手动添加）
		if entry.last_seen_tick == 0:
			continue
		# 如果超过追击范围或长时间未扫描到，移除
		if entry.distance > chase_range * 64.0:
			to_remove.append(entry)
			continue
		# 连续多次未扫描到也移除（扫描间隔 × 3）
		if current_tick - entry.last_seen_tick > scan_interval_ticks * 3:
			to_remove.append(entry)

	for entry: HatredEntry in to_remove:
		_hatred_list.erase(entry)

## 清除已死亡或无效的目标。
func _cleanup_dead_targets() -> void:
	var to_remove: Array[HatredEntry] = []
	for entry: HatredEntry in _hatred_list:
		if not is_instance_valid(entry.target) or not entry.target.is_alive():
			to_remove.append(entry)
	for entry: HatredEntry in to_remove:
		_hatred_list.erase(entry)

## 按威胁值降序排列仇恨列表。
func _sort_by_threat() -> void:
	_hatred_list.sort_custom(func(a: HatredEntry, b: HatredEntry): return a.threat > b.threat)
