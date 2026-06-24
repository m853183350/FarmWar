## 道具效果基类 — 所有道具效果必须继承本类。
##
## 效果通过 [method execute] 接收 [param params]（来自道具配置的 effect_params）
## 和 [param context]（由 [EffectManager] 构建的运行时上下文，包含服务引用和触发数据）。
##
## 设计原则：
##   - 效果与 PropManager 完全解耦，效果逻辑放在独立文件中
##   - 执行时注入上下文（而非构造时），效果可访问任意服务引用
##   - 新增效果只需创建子类并注册即可，无需修改 PropManager 或 EffectManager
##   - 通过 [method can_trigger] 钩子支持条件触发
class_name PropEffectBase extends RefCounted

# ============================================================
# 1. 枚举
# ============================================================

## 效果类别。
enum EffectCategory {
	INSTANT,    ## 即时效果 — 触发时一次性执行，执行完即结束。
	MODIFIER,   ## 修饰效果 — 持有期间持续生效，移除时调用 [method on_remove] 复原。
	DURATION,   ## 持续效果 — 有时限的 buff/debuff，到期自动移除。
}

# ============================================================
# 9. 公开方法
# ============================================================

## 返回本效果的类别。[br]
## 子类应覆写以声明自己的类别，默认返回 [enum EffectCategory.INSTANT]。
func get_category() -> EffectCategory:
	return EffectCategory.INSTANT

## 检查当前条件下是否可以触发。[br]
## 子类可覆写以添加前置条件逻辑（如概率、冷却、目标筛选）。[br]
## [param params] 效果参数（来自道具配置）。[br]
## [param context] 运行时上下文，由 [method EffectManager._build_context] 构建。
func can_trigger(_params: Dictionary, _context: Dictionary) -> bool:
	return true

## 执行道具效果。[br]
## 子类必须覆写此方法实现具体效果逻辑。[br]
## [param params] 效果参数字典，内容取决于效果类型。[br]
## [param context] 运行时上下文字典，包含服务引用和触发数据：
##   - [code]context["storage"][/code] — [Storage] 引用
##   - [code]context["trigger_signal"][/code] — 触发信号名（[StringName]）
##   - [code]context["trigger_data"][/code] — 信号参数（[Dictionary]）
func execute(_params: Dictionary, _context: Dictionary) -> void:
	push_error("PropEffectBase: execute() 必须由子类覆写")

## 修饰效果生效时调用。[br]
## 仅 [enum EffectCategory.MODIFIER] 和 [enum EffectCategory.DURATION] 类型的子类需要覆写。[br]
## [param params] 效果参数。[br]
## [param context] 运行时上下文。
func on_apply(_params: Dictionary, _context: Dictionary) -> void:
	pass

## 修饰效果移除时调用。[br]
## 仅 [enum EffectCategory.MODIFIER] 和 [enum EffectCategory.DURATION] 类型的子类需要覆写。[br]
## 应在该方法中复原 [method on_apply] 所做的修改。[br]
## [param params] 效果参数。[br]
## [param context] 运行时上下文。
func on_remove(_params: Dictionary, _context: Dictionary) -> void:
	pass
