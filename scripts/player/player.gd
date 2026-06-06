## 玩家实体 — 空的根容器节点。
##
## 承载玩家的所有子系统和组件（仓库、控制器等）。
## 当前仅初始化 [Storage] 子节点，其他功能待后续扩展。
##
## 在游戏启动时由 [code]main.tscn[/code] 创建。
class_name Player extends Node

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	add_to_group("player")
	_create_storage()

# ============================================================
# 10. 私有方法
# ============================================================

## 创建并添加仓库子节点。[br]
## 使用 [code]Storage.new()[/code] 以代码方式创建，无需场景文件。
func _create_storage() -> void:
	var storage: Storage = Storage.new()
	storage.name = "Storage"
	add_child(storage)
