# CommandSystem — 指令系统

## 概述

`CommandSystem` 是玩家高层指令的入口和编排中枢。挂载在 `GameRoot` 下，负责：接收指令 → 选兵 → 创建任务 → 分发。支持三种指令类型：小队指令、通用指令、全局覆盖指令。

**文件：** `scripts/game/command_system.gd`
**类型：** `class_name CommandSystem extends Node`

## 信号

| 信号 | 说明 |
|------|------|
| `command_issued(command_type, params)` | 指令发出（本地通知） |
| `squad_command_issued(squad_id, position, count)` | 小队指令发出 |

## 公开方法

### issue_squad_command

```gdscript
func issue_squad_command(squad_id: StringName, position: Vector2) -> int
```

**小队指令**（主要玩家入口 — "派遣部队"流程）：
1. 从 SquadManager 查找小队配置
2. 调用 UnitSelection.select_for_squad 自动选兵
3. 调用 CombatTaskFactory.create_for_squad 创建任务
4. 分发任务到各单位
5. 注册到 SquadTaskTracker（非内置小队）
6. 发出 EventBus 信号

**返回**选中的单位数量。0 表示无可用单位或小队不存在。

### issue_command

```gdscript
func issue_command(
    command_type: CombatTask.CombatTaskType,
    position: Vector2,
    unit_count: int = -1,
    unit_type_filter: StringName = &""
) -> int
```

**通用指令**（EXPLORE / GUARD / ATTACK）：
1. 调用 UnitSelection.select_units 选兵
2. 为每个选中单位创建独立 CombatTask
3. 分发并发出信号

### issue_global_override

```gdscript
func issue_global_override(
    command_type: CombatTask.CombatTaskType,
    position: Vector2 = Vector2.ZERO
) -> void
```

**全局覆盖指令**（RALLY / RETREAT / HOLD）：
不通过选兵机制——直接通过 EventBus 信号广播：
- RALLY → `EventBus.command_override_rally.emit(position)`
- RETREAT → `EventBus.command_override_retreat.emit(position)`
- HOLD → `EventBus.command_override_hold.emit()`

所有友方单位的 AIController 收到信号后覆盖当前任务。

## 数据流

```
玩家操作（地块 Popup → "派遣部队" → 选择小队）
  ↓
CommandSystem.issue_squad_command("assault_1", tile_pos)
  ↓
SquadManager.get_squad("assault_1")          # 获取小队配置
  ↓
UnitSelection.select_for_squad(config, pos)   # 自动选兵
  ↓
CombatTaskFactory.create_for_squad(...)       # 创建任务
  ↓
_distribute_tasks(tasks, units)               # 分发到单位
  ↓
SquadTaskTracker.register_squad(...)          # 追踪完成
  ↓
EventBus.command_issued.emit(...)             # 广播通知
  ↓
单位 AIController → ExecuteTaskBehavior → 移动/巡逻/战斗
```

## 全局覆盖指令流程

```
CommandSystem.issue_global_override(RALLY, position)
  ↓
EventBus.command_override_rally.emit(position)
  ↓
所有友方 AIController._on_rally_command(position):
  1. 标记旧任务为 OVERRIDDEN
  2. 创建全局覆盖 CombatTask (priority=100)
  3. BehaviorFSM.switch_to("ExecuteTask")
```

## 依赖

- `SquadManager` — 兄弟节点，小队查询
- `SquadTaskTracker` — 兄弟节点，小队追踪
- `UnitSelection` — 静态工具类，自动选兵
- `CombatTaskFactory` — 静态工厂，任务创建
- `EventBus` — 信号广播
- `UnitManager` — 战斗单位查询

## 配置

默认参数从 `config/command/command_params.json` 读取，由 CombatTaskFactory 管理。

## 关联文档

- [3.5 指令与任务系统](3.5指令与任务系统.md)
- [UnitSelection 工具](unit_selection.md)
- [CombatTask 数据结构](combat_task.md)
- [AIController](ai/ai_controller.md) — 全局覆盖响应
