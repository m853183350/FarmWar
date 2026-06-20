## 道具效果基类 — 所有道具效果必须继承本类。
##
## 每个效果实例持有 [Storage] 引用，在构造时注入。
## 子类必须覆写 [method execute] 实现具体效果逻辑。
##
## 设计原则：
##   - 效果与 PropManager 解耦，效果逻辑放在独立文件中
##   - 新增效果只需创建子类并注册即可，无需修改 PropManager
class_name PropEffectBase extends RefCounted

## 仓库引用，由 PropManager 在初始化时注入。
var storage: Storage

# ============================================================
# 9. 公开方法
# ============================================================

## 初始化效果实例。[br]
## [param _storage] 仓库节点引用，供效果执行时使用。
func init(_storage: Storage) -> void:
	storage = _storage

## 执行道具效果。[br]
## 子类必须覆写此方法。
## [param params] 效果参数字典，内容取决于效果类型。
func execute(_params: Dictionary) -> void:
	push_error("PropEffectBase: execute() 必须由子类覆写")
