## 战术小队配置 Resource。
##
## 描述一个战术小队的完整配置：小队 ID、显示名、兵种组成。
## 内置两个默认小队（"idle_all" 和 "all_units"），由 [SquadManager] 维护。
##
## SquadEntry 是嵌套 Resource，描述单个兵种类型和数量。
##
## 使用方式：
##   var config: SquadConfig = SquadConfig.new()
##   config.squad_id = "assault_1"
##   config.display_name = "突击小队"
##   config.add_entry("swordsman", 3)
class_name SquadConfig
extends Resource

# ============================================================
# 5. @export 变量
# ============================================================

## 小队唯一标识（如 "assault_1"）。
@export var squad_id: StringName = &""

## 小队显示名称（如 "突击小队"）。
@export var display_name: String = ""

## 兵种组成列表。
@export var entries: Array[SquadEntry] = []

## UI 排序权重（越大越靠前）。内置小队为 -1。
@export var sort_order: int = 0

## 是否为内置默认小队（true = 不可编辑/删除）。
@export var is_builtin: bool = false

# ============================================================
# 9. 公开方法 — 编辑
# ============================================================

## 添加一个兵种条目。
func add_entry(unit_type: StringName, count: int) -> void:
	var entry: SquadEntry = SquadEntry.new()
	entry.unit_type = unit_type
	entry.count = count
	entries.append(entry)

## 移除指定索引的兵种条目。
func remove_entry(index: int) -> void:
	if index >= 0 and index < entries.size():
		entries.remove_at(index)

## 清空所有兵种条目。
func clear_entries() -> void:
	entries.clear()

## 获取小队总人数。
func get_total_count() -> int:
	var total: int = 0
	for entry: SquadEntry in entries:
		total += entry.count
	return total

## 返回小队可读字符串（调试用）。
func _to_string() -> String:
	var desc: String = "%s (%s): " % [display_name, squad_id]
	var parts: Array[String] = []
	for entry: SquadEntry in entries:
		parts.append("%s×%d" % [entry.unit_type, entry.count])
	if parts.is_empty():
		desc += "空"
	else:
		desc += ", ".join(parts)
	return desc


# ============================================================
# SquadEntry - 小队兵种条目
# ============================================================

## 小队兵种条目 Resource。
##
## 描述小队中一种兵种的数量要求。
class_name SquadEntry
extends Resource

## 兵种类型 ID（如 "swordsman", "archer"）。
@export var unit_type: StringName = &""

## 该兵种的数量。
@export var count: int = 0
