# UnitSelection — 自动选兵工具

## 概述

`UnitSelection` 是纯静态工具类（`RefCounted`），从已注册的战斗单位中按条件自动选取最合适的单位。用于 `CommandSystem` 发出指令时自动选择距离最近、符合条件的空闲单位。

**文件：** `scripts/game/unit_selection.gd`
**类型：** `class_name UnitSelection extends RefCounted`

## 公开方法

### select_for_squad

```gdscript
static func select_for_squad(
    squad_config: Resource,
    from_position: Vector2,
    faction: int = 0
) -> Array[CombatUnitBase]
```

**按战术小队配置选取单位。**

遍历小队的每个 `SquadEntry`，从 `UnitManager` 中按 `unit_type + count` 选取最近的空闲单位。

内置默认小队特殊逻辑：
- `"idle_all"` → 选取所有空闲友方战斗单位
- `"all_units"` → 选取所有友方战斗单位（无视状态和任务）

### select_units

```gdscript
static func select_units(
    from_position: Vector2,
    count: int = -1,
    unit_type_filter: StringName = &"",
    faction: int = 0,
    only_idle: bool = true,
    exclude_tasked: bool = true,
    exclude_ids: Array[StringName] = []
) -> Array[CombatUnitBase]
```

**通用选兵方法：按条件选取 N 个最近的单位。**

参数说明：
- `count: -1` = 不限数量，选取所有符合条件的单位
- `unit_type_filter: ""` = 不限类型
- `only_idle: true` = 只选空闲单位
- `exclude_tasked: true` = 排除已有任务者
- `exclude_ids` = 排除已选中的 ID 列表（避免重复选取）

## 选择策略

1. 从 `UnitManager.get_combat_units(faction)` 获取所有活跃单位
2. 按 faction / unit_type / 空闲状态 / 有无任务 / 排除列表 过滤
3. 按 `from_position` 距离排序（最近优先，使用 `distance_squared_to` 避免开方）
4. 截取所需数量

## 使用示例

```gdscript
# 选取距离 (300, 200) 最近的 3 个空闲剑士
var units: Array[CombatUnitBase] = UnitSelection.select_units(
    Vector2(300, 200),
    3,
    &"swordsman",
    0,      # 友方
    true,   # 只选空闲
    true    # 排除有任务者
)

# 按小队配置选取
var squad_config: SquadConfig = SquadManager.get_squad("assault_1")
var units: Array[CombatUnitBase] = UnitSelection.select_for_squad(
    squad_config,
    Vector2(500, 300)
)

# 选取所有空闲友方单位
var all_idle: Array[CombatUnitBase] = UnitSelection.select_units(
    Vector2.ZERO,
    -1,     # 不限数量
    &"",    # 不限类型
    0
)
```

## 依赖

- `UnitManager` — 提供 `get_combat_units(faction)` 接口
- `CombatUnitBase` — 被选取的单位类型

## 关联文档

- [3.5 指令与任务系统](3.5指令与任务系统.md)
- [CommandSystem](command_system.md)
- [UnitManager](../scripts/units/unit_manager.gd)
