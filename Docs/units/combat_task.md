# CombatTask — 战斗任务数据结构

## 概述

`CombatTask` 描述一个玩家发出的战斗指令，包含目标位置、任务类型、状态等。与 `TaskData`（FarmWorker 用）不同，使用世界坐标、单任务模式、可被全局指令覆盖。

**文件：** `scripts/units/combat_task.gd`
**类型：** `class_name CombatTask extends RefCounted`

## 枚举

### CombatTaskType

| 值 | 说明 |
|----|------|
| `EXPLORE` | 探索指定区域 → 巡逻游荡 → 自主索敌 |
| `GUARD` | 守卫指定位置 → 原地警戒 → 自动攻击 |
| `ATTACK` | 攻击指定目标/区域 → 清除敌人 |
| `RALLY` | 全体集合（全局覆盖） |
| `RETREAT` | 全体撤退（全局覆盖） |
| `HOLD` | 原地待命（全局覆盖） |

### CombatTaskStatus

| 值 | 说明 |
|----|------|
| `PENDING` | 等待执行 |
| `IN_PROGRESS` | 执行中 |
| `COMPLETED` | 已完成 |
| `FAILED` | 失败（路径不通等） |
| `OVERRIDDEN` | 被全局指令覆盖 |

## 公开属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `task_id` | `int` | 自增唯一 ID |
| `task_type` | `CombatTaskType` | 任务类型 |
| `target_position` | `Vector2` | 目标位置（世界坐标） |
| `patrol_radius` | `float` | 巡逻半径（格） |
| `attack_target_id` | `StringName` | 指定攻击目标 |
| `status` | `CombatTaskStatus` | 任务状态 |
| `priority` | `int` | 优先级（100 = 全局覆盖） |
| `created_tick` | `int` | 创建时的游戏 tick |
| `assigned_unit_id` | `StringName` | 所属单位 |
| `squad_id` | `StringName` | 小队 ID（空 = 非小队） |
| `task_center` | `Vector2` | 小队任务中心 |
| `loot_radius` | `float` | 战利品收集半径（格） |

## 公开方法

### 静态工厂

```gdscript
static func create(task_type, position, unit_id, params = {}) -> CombatTask
```

### 状态管理

| 方法 | 说明 |
|------|------|
| `mark_in_progress()` | 标记为执行中 |
| `mark_completed()` | 标记为已完成 |
| `mark_failed()` | 标记为失败 |
| `mark_overridden()` | 标记为被覆盖 |

### 查询

| 方法 | 说明 |
|------|------|
| `is_squad_task() -> bool` | 是否为小队任务 |
| `is_global_override() -> bool` | 是否为全局覆盖指令 |
| `get_type_name() -> String` | 返回任务类型中文名 |
| `get_status_name() -> String` | 返回任务状态中文名 |

## 使用示例

```gdscript
# 创建守卫任务
var task: CombatTask = CombatTask.create(
    CombatTask.CombatTaskType.GUARD,
    Vector2(300, 200),
    unit.unit_id
)
unit.current_task = task

# 创建小队任务
var squad_task: CombatTask = CombatTask.create(
    CombatTask.CombatTaskType.ATTACK,
    position,
    unit.unit_id,
    {
        "squad_id": "assault_1",
        "task_center": position,
        "loot_radius": 10.0,
        "patrol_radius": 5.0,
    }
)
```

## 与 TaskData 的差异

| 维度 | TaskData | CombatTask |
|------|----------|------------|
| 用途 | 农场工人地块操作 | 战斗单位战略指令 |
| 坐标 | `target_tile: Vector2i` | `target_position: Vector2` |
| 队列 | FIFO 队列排多个 | 单任务 |
| 覆盖 | 不可抢占 | 可被全局指令 OVERRIDDEN |
| 小队 | 无 | 有 squad_id |
| 共享状态 | 父子任务 | SquadTaskTracker 追踪 |

## 依赖

- `TickSystem` — 获取创建时的 tick 计数

## 关联文档

- [CombatTaskFactory](../scripts/units/combat_task_factory.gd)
- [CommandSystem](command_system.md)
- [TaskData](../scripts/units/task_data.gd) — FarmWorker 任务
