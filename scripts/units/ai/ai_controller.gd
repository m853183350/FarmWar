## AI 控制器 — 所有战斗单位的决策中枢，采用模块化架构。
##
## 作为 [CombatUnitBase] 的子节点挂载。
## 通过配置动态组装子模块（仇恨系统、技能选择器、行为模组），
## 而非在场景中硬编码所有模块。不同单位类型可拥有不同的 AI 模组组合。
##
## 架构：
##   AIController (Node)
##   ├── HatredSystem (Node)           ← 可选：攻击型单位需要，纯防守型可省略
##   ├── SkillSelector (Node)          ← 可选：有技能的单位需要
##   └── BehaviorFSM (Node)            ← 必需：行为模组动态加载
##       ├── GuardBehavior             ← 警戒（通用）
##       ├── ChaseBehavior             ← 追击（攻击型）
##       ├── CombatBehavior            ← 战斗（攻击型）
##       ├── FleeBehavior              ← 逃跑（有 HP 的单位）
##       ├── PatrolBehavior            ← 巡逻（游荡型）
##       └── ExecuteTaskBehavior       ← 任务执行（可接收指令的单位）
##
## 模组配置示例（JSON）：
##   {
##     "ai": {
##       "default_behavior": "Guard",
##       "behaviors": ["Guard", "Chase", "Combat", "Flee"],
##       "enable_hatred": true,
##       "enable_skill_selector": true,
##       "flee_hp_ratio": 0.25,
##       "hatred_alert_range": 10.0,
##       "hatred_chase_range": 20.0
##     }
##   }
class_name AIController
extends Node

# ============================================================
# 3. 常量
# ============================================================

## 默认配置。
const DEFAULT_CONFIG: Dictionary = {
	"default_behavior": "Guard",
	"behaviors": ["Guard", "Chase", "Combat", "Flee"],
	"enable_hatred": true,
	"enable_skill_selector": true,
	"flee_hp_ratio": 0.25,
	"hatred_alert_range": 10.0,
	"hatred_chase_range": 20.0,
	"hatred_scan_interval": 5,
}

## HatredSystem 脚本路径。
const HATRED_SCRIPT: String = "res://scripts/units/ai/hatred_system.gd"

## SkillSelector 脚本路径。
const SKILL_SELECTOR_SCRIPT: String = "res://scripts/units/ai/skill_selector.gd"

## BehaviorFSM 脚本路径。
const BEHAVIOR_FSM_SCRIPT: String = "res://scripts/units/ai/behavior_fsm.gd"

## TickSystem 引用。
const TickSystemClass = preload("res://scripts/autoload/tick_system.gd")

## CombatTask 枚举引用（用于全局覆盖指令类型匹配）。
const CombatTaskClass = preload("res://scripts/units/combat_task.gd")

## CombatTaskFactory 引用。
const TaskFactoryClass = preload("res://scripts/units/combat_task_factory.gd")

# ============================================================
# 5. 公开变量
# ============================================================

## AI 配置（运行时加载）。
var config: Dictionary = {}

## 触发逃跑的生命值比例（当前 HP / 最大 HP）。0 表示不逃跑。
var flee_hp_ratio: float = 0.25

# ============================================================
# 6. 私有变量
# ============================================================

## 当前游戏 tick 编号。
var _current_tick: int = 0

## 是否已完成初始化。
var _initialized: bool = false

## 单位引用（在第一次 update 时缓存）。
var _unit: CombatUnitBase = null

# ============================================================
# 7. @onready 变量
# ============================================================

@onready var hatred_system: HatredSystem = _find_child_of_type("HatredSystem")
@onready var skill_selector: SkillSelector = _find_child_of_type("SkillSelector")
@onready var behavior_fsm: BehaviorFSM = _find_child_of_type("BehaviorFSM")

# ============================================================
# 8. 生命周期
# ============================================================

func _ready() -> void:
	_ensure_modules()
	_connect_tick()
	_connect_global_commands()

func _exit_tree() -> void:
	if TickSystem and TickSystem.tick_elapsed.is_connected(_on_tick):
		TickSystem.tick_elapsed.disconnect(_on_tick)
	_disconnect_global_commands()

# ============================================================
# 9. 公开方法
# ============================================================

## 使用配置字典初始化 AI 控制器（在 [method CombatUnitBase._load_combat_config] 中调用）。
##
## [param ai_config] AI 配置字典，字段与 DEFAULT_CONFIG 一致。
##   未提供的字段使用默认值。
func init_from_config(ai_config: Dictionary = {}) -> void:
	# 合并配置
	config = DEFAULT_CONFIG.duplicate()
	for key: String in ai_config:
		config[key] = ai_config[key]

	# 读取逃跑阈值
	flee_hp_ratio = config.get("flee_hp_ratio", 0.25) as float

	# 配置 HatredSystem
	_configure_hatred(config)

	# 配置 BehaviorFSM：动态加载行为模组
	var behavior_names: Array[String] = []
	var raw_behaviors = config.get("behaviors", ["Guard", "Chase", "Combat", "Flee"])
	for b in raw_behaviors:
		behavior_names.append(b as String)
	var default_behavior: String = config.get("default_behavior", "Guard") as String

	if behavior_fsm:
		behavior_fsm.controller = self
		behavior_fsm.load_behaviors(behavior_names, default_behavior)

	_initialized = true

## 每 tick 由 [method CombatUnitBase._update_controller] 调用。
func update(unit: CombatUnitBase, _delta: float) -> void:
	if not _initialized:
		return

	_unit = unit

	# 死亡不思考
	if not unit.is_alive():
		return

	# 模式判断
	if unit.current_task != null:
		_update_task_mode(unit)
	else:
		_update_autonomous_mode(unit)

## 获取当前行为名（调试用）。
func get_current_behavior_name() -> String:
	if behavior_fsm:
		return behavior_fsm.get_current_behavior_name()
	return "Uninitialized"

# ============================================================
# 10. 私有方法 — Tick
# ============================================================

## Tick 系统回调（更新 tick 计数，用于仇恨系统的扫描计时）。
func _on_tick(_delta: float) -> void:
	_current_tick += 1

# ============================================================
# 10. 私有方法 — 初始化
# ============================================================

## 确保必要的子模块节点存在，不存在则动态创建。
func _ensure_modules() -> void:
	# BehaviorFSM 是必需的
	if behavior_fsm == null:
		var fsm: Node = Node.new()
		fsm.set_script(load(BEHAVIOR_FSM_SCRIPT) as Script)
		fsm.name = "BehaviorFSM"
		add_child(fsm)
		behavior_fsm = fsm as BehaviorFSM

	# HatredSystem — 根据配置决定是否启用
	if hatred_system == null and config.get("enable_hatred", true):
		var h: Node = Node.new()
		h.set_script(load(HATRED_SCRIPT) as Script)
		h.name = "HatredSystem"
		add_child(h)
		hatred_system = h as HatredSystem

	# SkillSelector — 根据配置决定是否启用
	if skill_selector == null and config.get("enable_skill_selector", true):
		var s: Node = Node.new()
		s.set_script(load(SKILL_SELECTOR_SCRIPT) as Script)
		s.name = "SkillSelector"
		add_child(s)
		skill_selector = s as SkillSelector

## 配置 HatredSystem 参数。
func _configure_hatred(cfg: Dictionary) -> void:
	if hatred_system == null:
		return
	hatred_system.alert_range = cfg.get("hatred_alert_range", 10.0) as float
	hatred_system.chase_range = cfg.get("hatred_chase_range", 20.0) as float
	hatred_system.scan_interval_ticks = cfg.get("hatred_scan_interval", 5) as int

## 连接到 TickSystem。
func _connect_tick() -> void:
	if TickSystem:
		TickSystem.tick_elapsed.connect(_on_tick)

# ============================================================
# 10. 私有方法 — 模式处理
# ============================================================

## 任务模式：优先执行任务，途中自卫。
func _update_task_mode(unit: CombatUnitBase) -> void:
	if not behavior_fsm:
		return

	# 如果当前不在 ExecuteTask 行为，或行为被战斗中断后恢复
	var current_name: String = behavior_fsm.get_current_behavior_name()
	if current_name == "ExecuteTask":
		# 已在执行任务，继续
		behavior_fsm.update(unit, 0.0)
	elif current_name in ["Chase", "Combat"]:
		# 战斗中（任务途中的自卫），检查战斗是否结束
		if hatred_system and not hatred_system.has_threat_target():
			# 战斗结束，恢复任务
			behavior_fsm.switch_to(unit, "ExecuteTask")
		else:
			# 继续战斗
			behavior_fsm.update(unit, 0.0)
	else:
		# 切换到任务执行
		if behavior_fsm.has_behavior("ExecuteTask"):
			behavior_fsm.switch_to(unit, "ExecuteTask")

	# 任务模式不逃跑（除非全局撤退指令）
	# HP 检查已在 BehaviorFSM 层面处理

## 自主模式：无任务时由行为状态机自主决策。
func _update_autonomous_mode(unit: CombatUnitBase) -> void:
	if not behavior_fsm:
		return

	# 更新仇恨系统
	if hatred_system:
		hatred_system.update_hatred(unit, _current_tick)

	# 检查逃跑条件
	if _should_flee(unit):
		if behavior_fsm.has_behavior("Flee") and behavior_fsm.get_current_behavior_name() != "Flee":
			behavior_fsm.switch_to(unit, "Flee")
			return

	# 检查仇恨驱动切换
	var current_name: String = behavior_fsm.get_current_behavior_name()

	if hatred_system and hatred_system.has_threat_target():
		var target: CombatUnitBase = hatred_system.get_primary_target()
		# 在 Guard/Patrol 状态中发现敌人 → 切换到追击
		if current_name in ["Guard", "Patrol"] and behavior_fsm.has_behavior("Chase"):
			unit.set_target(target)
			behavior_fsm.switch_to(unit, "Chase")
			return

	# 如果当前是 Chase/Combat 但仇恨列表空了 → 先尝试收集战利品，再回默认
	if current_name in ["Chase", "Combat"]:
		if hatred_system == null or not hatred_system.has_threat_target():
			unit.clear_target()
			# 优先切到 Loot（如果挂载了该模组）
			if behavior_fsm.has_behavior("Loot"):
				behavior_fsm.switch_to(unit, "Loot")
			else:
				var default_name: String = config.get("default_behavior", "Guard") as String
				if behavior_fsm.has_behavior(default_name):
					behavior_fsm.switch_to(unit, default_name)
			return

	# 委托给当前行为
	behavior_fsm.update(unit, 0.0)

## 判断是否应该逃跑。
func _should_flee(unit: CombatUnitBase) -> bool:
	if flee_hp_ratio <= 0.0:
		return false
	if unit.max_health <= 0.0:
		return false
	var hp_ratio: float = unit.current_health / unit.max_health
	if hp_ratio > flee_hp_ratio:
		return false
	# 有威胁目标才逃跑
	if hatred_system and not hatred_system.has_threat_target():
		return false
	return true

# ============================================================
# 10. 私有方法 — 全局覆盖指令
# ============================================================

## 连接 EventBus 的全局覆盖指令信号。
func _connect_global_commands() -> void:
	if not EventBus:
		return
	if not EventBus.command_override_rally.is_connected(_on_rally_command):
		EventBus.command_override_rally.connect(_on_rally_command)
	if not EventBus.command_override_retreat.is_connected(_on_retreat_command):
		EventBus.command_override_retreat.connect(_on_retreat_command)
	if not EventBus.command_override_hold.is_connected(_on_hold_command):
		EventBus.command_override_hold.connect(_on_hold_command)

## 断开全局覆盖指令信号。
func _disconnect_global_commands() -> void:
	if not EventBus:
		return
	if EventBus.command_override_rally.is_connected(_on_rally_command):
		EventBus.command_override_rally.disconnect(_on_rally_command)
	if EventBus.command_override_retreat.is_connected(_on_retreat_command):
		EventBus.command_override_retreat.disconnect(_on_retreat_command)
	if EventBus.command_override_hold.is_connected(_on_hold_command):
		EventBus.command_override_hold.disconnect(_on_hold_command)

## 全体集合指令 — 所有友方单位移动到集结点。
func _on_rally_command(position: Vector2) -> void:
	if _unit == null or _unit.faction != 0:
		return
	_apply_global_override(CombatTask.CombatTaskType.RALLY, position)

## 全体撤退指令 — 所有友方单位移动到撤退点，途中只还击。
func _on_retreat_command(position: Vector2) -> void:
	if _unit == null or _unit.faction != 0:
		return
	_apply_global_override(CombatTask.CombatTaskType.RETREAT, position)

## 全体待命指令 — 所有友方单位原地停止。
func _on_hold_command() -> void:
	if _unit == null or _unit.faction != 0:
		return
	_apply_global_override(CombatTask.CombatTaskType.HOLD, _unit.grid_position)

## 应用全局覆盖指令。
func _apply_global_override(command_type: int, position: Vector2) -> void:
	# 覆盖当前任务
	if _unit.current_task != null:
		if EventBus:
			EventBus.combat_task_overridden.emit(_unit.unit_id, _unit.current_task.task_id)
		# 标记旧任务
		if _unit.current_task is CombatTask:
			var old_task: CombatTask = _unit.current_task as CombatTask
			old_task.mark_overridden()

	# 创建全局覆盖任务
	_unit.current_task = TaskFactoryClass.create_global_override(command_type, position, _unit.unit_id)

	# 切换到任务执行行为
	if behavior_fsm and behavior_fsm.has_behavior("ExecuteTask"):
		behavior_fsm.switch_to(_unit, "ExecuteTask")

# ============================================================
# 10. 私有方法 — 辅助
# ============================================================

## 在子节点中查找指定类型的节点。
func _find_child_of_type(type_name: String) -> Node:
	for child: Node in get_children():
		if child is HatredSystem and type_name == "HatredSystem":
			return child
		if child is SkillSelector and type_name == "SkillSelector":
			return child
		if child is BehaviorFSM and type_name == "BehaviorFSM":
			return child
	return null
