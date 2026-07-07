## 战利品采集行为 — 战斗结束后自动收集附近的掉落物。
##
## 可插拔模组。挂载此模组的单位在击败敌人后会扫描周围区域的
## 战利品掉落物（资源、道具等），移动到最近掉落物并采集，
## 然后继续寻找下一个，直至范围内无更多战利品。
##
## 典型流程：
##   Chase/Combat 行为中目标死亡 → HatredSystem 仇恨清空
##   → AIController 无仇恨目标 → 检测单位挂载了 Loot 模组
##   → 切换到 Loot → 采集完所有战利品 → 回到 Guard
class_name LootBehavior
extends BaseBehavior

# ============================================================
# 2. 枚举
# ============================================================

enum LootState {
	SCAN,          ## 扫描范围内战利品
	MOVING,        ## 向最近战利品移动中
	COLLECTING,    ## 采集中
}

# ============================================================
# 3. 常量
# ============================================================

## 默认采集范围（格数）。
const DEFAULT_LOOT_RANGE: float = 15.0

## 到达战利品判定距离（像素）。
const ARRIVAL_THRESHOLD: float = 8.0

## 采集所需 tick 数。
const COLLECT_TICKS: int = 10

## 两次扫描之间最小间隔（tick 数）。
const SCAN_INTERVAL: int = 20

# ============================================================
# 5. 公开变量
# ============================================================

## 采集范围（格数）。超出此范围的战利品不予理会。
@export var loot_range: float = DEFAULT_LOOT_RANGE

## 采集单个战利品所需 tick 数。模拟弯腰拾取的动作时间。
@export var collect_ticks: int = COLLECT_TICKS

## 是否在战斗中也会尝试采集（false = 只在非战斗状态下采集）。
@export var loot_during_combat: bool = false

# ============================================================
# 6. 私有变量
# ============================================================

var _state: LootState = LootState.SCAN
var _current_loot_target: Node2D = null
var _collect_progress: int = 0
var _ticks_since_scan: int = SCAN_INTERVAL
var _collect_range_sq: float = 0.0

# ============================================================
# 8. 生命周期
# ============================================================

func _ready() -> void:
	behavior_name = "Loot"
	_collect_range_sq = loot_range * 64.0
	_collect_range_sq *= _collect_range_sq

# ============================================================
# 9. 公开方法
# ============================================================

func enter(unit: CombatUnitBase) -> void:
	_state = LootState.SCAN
	_current_loot_target = null
	_collect_progress = 0
	_ticks_since_scan = SCAN_INTERVAL

func exit(_unit: CombatUnitBase) -> void:
	_current_loot_target = null

func update(unit: CombatUnitBase, _delta: float) -> void:
	# 战斗中不采集（除非显式允许）
	if not loot_during_combat:
		var h: HatredSystem = hatred()
		if h and h.has_threat_target():
			# 有敌人，中断采集，切换回战斗
			var target: CombatUnitBase = h.get_primary_target()
			if target != null:
				unit.set_target(target)
				switch_to(unit, "Chase")
				return

	match _state:
		LootState.SCAN:
			_scan_for_loot(unit)
		LootState.MOVING:
			_move_to_loot(unit)
		LootState.COLLECTING:
			_do_collect(unit)

func _scan_for_loot(unit: CombatUnitBase) -> void:
	_ticks_since_scan += 1
	if _ticks_since_scan < SCAN_INTERVAL:
		# 避免每 tick 扫描，减少性能开销
		unit.target_velocity = Vector2.ZERO
		return
	_ticks_since_scan = 0

	# 搜索范围内最近的战利品节点（通过 group "loot" 查找）
	var nearest: Node2D = _find_nearest_loot(unit)
	if nearest == null:
		# 无战利品，回到警戒
		switch_to(unit, "Guard")
		return

	_current_loot_target = nearest
	unit.set_move_target_world(nearest.global_position)
	_state = LootState.MOVING

func _move_to_loot(unit: CombatUnitBase) -> void:
	if _current_loot_target == null or not is_instance_valid(_current_loot_target):
		_state = LootState.SCAN
		return

	var target_pos: Vector2 = _current_loot_target.global_position
	var dist: float = unit.grid_position.distance_to(target_pos)

	if dist < ARRIVAL_THRESHOLD:
		# 到达战利品位置，开始采集
		unit.target_velocity = Vector2.ZERO
		unit._set_combat_state(CombatUnitBase.CombatState.IDLE)
		_collect_progress = 0
		_state = LootState.COLLECTING
		return

	# 向战利品移动
	var dir: Vector2 = target_pos - unit.grid_position
	unit.target_velocity = dir.normalized()
	unit._set_combat_state(CombatUnitBase.CombatState.CHASE)

	if dir.x != 0.0:
		unit.facing_direction = Vector2(signf(dir.x), 0.0)

func _do_collect(unit: CombatUnitBase) -> void:
	if _current_loot_target == null or not is_instance_valid(_current_loot_target):
		_state = LootState.SCAN
		return

	_collect_progress += 1
	if _collect_progress < collect_ticks:
		return

	# 采集完成
	_collect_loot_item(unit, _current_loot_target)
	_current_loot_target = null
	_ticks_since_scan = SCAN_INTERVAL  # 立即扫描下一个
	_state = LootState.SCAN

func _find_nearest_loot(unit: CombatUnitBase) -> Node2D:
	var my_pos: Vector2 = unit.grid_position
	var nearest: Node2D = null
	var nearest_dist_sq: float = _collect_range_sq

	# 通过 group "loot" 查找所有战利品节点
	var loot_nodes: Array[Node] = unit.get_tree().get_nodes_in_group(&"loot")
	for node: Node in loot_nodes:
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var loot: Node2D = node as Node2D
		var dist_sq: float = my_pos.distance_squared_to(loot.global_position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = loot

	return nearest

func _collect_loot_item(unit: CombatUnitBase, loot: Node2D) -> void:
	# 调用战利品的采集方法（duck-typing：战利品节点需实现 collect(collector) 方法）
	if loot.has_method("collect"):
		loot.collect(unit)
	elif loot.has_method("pick_up"):
		loot.pick_up(unit)

	# 发出事件供 UI / Storage 等系统响应
	if EventBus:
		EventBus.loot_collected.emit(unit.unit_id, loot.name if loot else &"")
