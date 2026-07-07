## 行为状态机 — 管理 AI 行为模块的生命周期和切换。
##
## 作为 [AIController] 的子节点，管理一组 [BaseBehavior] 子节点。
## 行为模块通过配置动态加载，不在场景中硬编码。
## 不同单位类型可挂载不同的行为模组组合。
##
## 行为切换流程：
##   1. 调用 [method switch_to] 切换到目标行为
##   2. 如当前有行为 → 调用 [method BaseBehavior.exit]
##   3. 设置新行为为当前 → 调用 [method BaseBehavior.enter]
##   4. 每 tick 调用 [method update] 委托给当前行为
##
## 使用方式：
##   # 在 AIController._ready 中动态加载
##   behavior_fsm.load_behaviors(["Guard", "Chase", "Combat", "Flee"])
##   behavior_fsm.start("Guard", unit)
class_name BehaviorFSM
extends Node

# ============================================================
# 3. 常量
# ============================================================

## 行为脚本路径映射。行为名 → 脚本路径。
const BEHAVIOR_SCRIPTS: Dictionary = {
	"Guard": "res://scripts/units/ai/behaviors/guard_behavior.gd",
	"Patrol": "res://scripts/units/ai/behaviors/patrol_behavior.gd",
	"Chase": "res://scripts/units/ai/behaviors/chase_behavior.gd",
	"Combat": "res://scripts/units/ai/behaviors/combat_behavior.gd",
	"Flee": "res://scripts/units/ai/behaviors/flee_behavior.gd",
	"Loot": "res://scripts/units/ai/behaviors/loot_behavior.gd",
	"ExecuteTask": "res://scripts/units/ai/behaviors/execute_task_behavior.gd",
}

# ============================================================
# 5. 公开变量
# ============================================================

## AIController 引用（由 AIController 在初始化时设置）。
var controller: Node = null

## 当前激活的行为。
var current_behavior: BaseBehavior = null

## 已加载的行为字典 {行为名: BaseBehavior}。
var behaviors: Dictionary = {}

# ============================================================
# 6. 私有变量
# ============================================================

## 默认行为名（无目标时自动回退到此行为）。
var _default_behavior_name: String = "Guard"

# ============================================================
# 9. 公开方法
# ============================================================

## 从配置加载指定行为模块。
##
## [param behavior_names] 要加载的行为名列表（如 ["Guard", "Chase", "Combat", "Flee"]）。
## [param default_name] 默认行为名（无目标时回退到此行为）。
## [return] 成功加载的行为数量。
func load_behaviors(behavior_names: Array[String], default_name: String = "Guard") -> int:
	# 清除已有行为节点
	for child: Node in get_children():
		if child is BaseBehavior:
			remove_child(child)
			child.queue_free()
	behaviors.clear()

	_default_behavior_name = default_name
	var loaded_count: int = 0

	for name: String in behavior_names:
		if not BEHAVIOR_SCRIPTS.has(name):
			push_warning("BehaviorFSM: 未知行为 '%s'，跳过" % name)
			continue

		var script_path: String = BEHAVIOR_SCRIPTS[name]
		if not ResourceLoader.exists(script_path):
			push_warning("BehaviorFSM: 行为脚本不存在 '%s'" % script_path)
			continue

		var script: Script = load(script_path) as Script
		var behavior_node: Node = Node.new()
		behavior_node.set_script(script)
		behavior_node.name = name
		add_child(behavior_node)

		var behavior: BaseBehavior = behavior_node as BaseBehavior
		behaviors[name] = behavior
		loaded_count += 1

	return loaded_count

## 启动状态机，进入默认行为。
## [param unit] 拥有此状态机的战斗单位。
func start(unit: CombatUnitBase) -> void:
	if behaviors.has(_default_behavior_name):
		switch_to(unit, _default_behavior_name)
	elif not behaviors.is_empty():
		var first_key: String = behaviors.keys()[0]
		switch_to(unit, first_key)

## 切换到指定行为。
## [param unit] 战斗单位。
## [param behavior_name] 目标行为名。
func switch_to(unit: CombatUnitBase, behavior_name: String) -> void:
	if not behaviors.has(behavior_name):
		push_warning("BehaviorFSM: 行为 '%s' 未加载" % behavior_name)
		return

	var target: BaseBehavior = behaviors[behavior_name] as BaseBehavior
	if current_behavior == target:
		return  # 已经是当前行为

	# 退出当前行为
	if current_behavior != null:
		current_behavior.exit(unit)

	# 进入新行为
	current_behavior = target
	current_behavior.enter(unit)

## 每 tick 委托给当前行为。
func update(unit: CombatUnitBase, delta: float) -> void:
	if current_behavior != null:
		current_behavior.update(unit, delta)

## 是否有指定行为模块。
func has_behavior(behavior_name: String) -> bool:
	return behaviors.has(behavior_name)

## 获取当前行为名（调试用）。
func get_current_behavior_name() -> String:
	if current_behavior != null:
		return current_behavior.behavior_name
	return "None"

## 获取所有已加载的行为名列表。
func get_loaded_behaviors() -> Array[String]:
	var result: Array[String] = []
	for key: String in behaviors.keys():
		result.append(key)
	return result
