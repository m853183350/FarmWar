## 小队兵种条目 Resource。
##
## 描述小队中一种兵种的数量要求。
class_name SquadEntry
extends Resource

## 兵种类型 ID（如 "swordsman", "archer"）。
@export var unit_type: StringName = &""

## 该兵种的数量。
@export var count: int = 0
