## 玩家实体 — 根容器节点。
##
## 承载玩家的所有子系统和组件（仓库、道具管理器等）。
## 当前初始化 [Storage] 和 [PropManager] 子节点，其他功能待后续扩展。
##
## 在游戏启动时由 [code]main.tscn[/code] 创建。
class_name Player extends Node

# ============================================================
# 3. 常量
# ============================================================

const _PropDataScript = preload("res://scripts/items/prop_data.gd")
const _PropManagerScript = preload("res://scripts/items/prop_manager.gd")

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	add_to_group("player")
	_create_storage()
	_create_prop_manager()

# ============================================================
# 10. 私有方法
# ============================================================

## 创建并添加仓库子节点。[br]
## 使用 [code]Storage.new()[/code] 以代码方式创建，无需场景文件。
func _create_storage() -> void:
	var storage: Storage = Storage.new()
	storage.name = "Storage"
	add_child(storage)

## 创建并添加道具管理器子节点。[br]
## 使用 [code]PropManager.new()[/code] 以代码方式创建，无需场景文件。
func _create_prop_manager() -> void:
	var prop_manager: PropManager = PropManager.new()
	prop_manager.name = "PropManager"
	add_child(prop_manager)
