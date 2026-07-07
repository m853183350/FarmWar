## AI 行为基类 — 所有具体行为（Guard/Patrol/Chase/Combat/Flee/ExecuteTask）的抽象基类。
##
## 作为 [BehaviorFSM] 的子节点挂载。
## 定义 enter / exit / update 虚方法，子类必须覆写。
##
## 行为通过 [member fsm] 访问 BehaviorFSM 以触发状态切换，
## 通过 [member controller] 访问 AIController 以使用 HatredSystem / SkillSelector。
class_name BaseBehavior
extends Node

# ============================================================
# 5. 公开变量
# ============================================================

## 行为显示名称（调试用，子类应在 _ready 中设置）。
var behavior_name: String = "Base"

# ============================================================
# 6. 私有变量
# ============================================================

## 缓存的 BehaviorFSM 引用。
var _fsm: Node = null

## 缓存的 AIController 引用。
var _controller: Node = null

# ============================================================
# 9. 公开方法 — 生命周期
# ============================================================

## 进入行为时调用。
## [param unit] 拥有此行为的战斗单位。
func enter(_unit: CombatUnitBase) -> void:
	pass

## 退出行为时调用（切换到其他行为前）。
## [param unit] 拥有此行为的战斗单位。
func exit(_unit: CombatUnitBase) -> void:
	pass

## 每 tick 更新行为逻辑。
## [param unit] 拥有此行为的战斗单位。
## [param _delta] tick 间隔（秒）。
func update(_unit: CombatUnitBase, _delta: float) -> void:
	pass

# ============================================================
# 9. 公开方法 — 访问器
# ============================================================

## 获取 BehaviorFSM 引用（延迟初始化，因为 _ready 顺序不定）。
func fsm() -> Node:
	if _fsm == null:
		_fsm = get_parent()
	return _fsm

## 获取 AIController 引用。
func controller() -> Node:
	if _controller == null:
		var f: Node = fsm()
		if f and f.get_parent():
			_controller = f.get_parent()
	return _controller

## 切换到另一个行为。便捷方法，委托给 BehaviorFSM。
func switch_to(unit: CombatUnitBase, behavior_name: String) -> void:
	var f: Node = fsm()
	if f and f.has_method("switch_to"):
		f.switch_to(unit, behavior_name)

## 获取 HatredSystem 引用。
func hatred() -> HatredSystem:
	var ctrl: Node = controller()
	if ctrl and ctrl.get("hatred_system") != null:
		return ctrl.hatred_system as HatredSystem
	return null

## 获取 SkillSelector 引用。
func skill_selector() -> SkillSelector:
	var ctrl: Node = controller()
	if ctrl and ctrl.get("skill_selector") != null:
		return ctrl.skill_selector as SkillSelector
	return null
