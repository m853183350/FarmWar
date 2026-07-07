# BehaviorFSM — 行为状态机

## 概述

管理 AI 行为模组的生命周期和切换。支持从配置动态加载行为模组，不同单位类型可挂载不同的行为组合。

**文件：** `scripts/units/ai/behavior_fsm.gd`
**类型：** `class_name BehaviorFSM extends Node`

## 设计原则

- **动态加载：** 行为模组不硬编码在场景中，通过 `load_behaviors()` 从配置加载
- **可插拔：** 单位需要哪个模组就加载哪个，不加载不需要的
- **统一接口：** 所有行为继承 `BaseBehavior`，实现 `enter(unit)` / `exit(unit)` / `update(unit, delta)`

## 行为注册表

```gdscript
const BEHAVIOR_SCRIPTS: Dictionary = {
    "Guard":       "res://scripts/units/ai/behaviors/guard_behavior.gd",
    "Patrol":      "res://scripts/units/ai/behaviors/patrol_behavior.gd",
    "Chase":       "res://scripts/units/ai/behaviors/chase_behavior.gd",
    "Combat":      "res://scripts/units/ai/behaviors/combat_behavior.gd",
    "Flee":        "res://scripts/units/ai/behaviors/flee_behavior.gd",
    "Loot":        "res://scripts/units/ai/behaviors/loot_behavior.gd",
    "ExecuteTask": "res://scripts/units/ai/behaviors/execute_task_behavior.gd",
}
```

## 行为切换流程

```
switch_to(unit, "Chase")
  → current_behavior.exit(unit)     # 退出旧行为
  → current_behavior = behaviors["Chase"]
  → current_behavior.enter(unit)    # 进入新行为
```

每 tick：
```
update(unit, delta)
  → current_behavior.update(unit, delta)
```

## 公开方法

| 方法 | 说明 |
|------|------|
| `load_behaviors(names, default_name) -> int` | 从名称列表动态加载行为模组，返回加载数量 |
| `start(unit)` | 启动状态机，进入默认行为 |
| `switch_to(unit, name)` | 切换到指定行为（安全：已存在/已当前则跳过） |
| `update(unit, delta)` | 每 tick 委托给当前行为 |
| `has_behavior(name) -> bool` | 是否有指定行为 |
| `get_current_behavior_name() -> String` | 调试用 |
| `get_loaded_behaviors() -> Array[String]` | 调试用 |

## 配置示例

```json
{
  "ai": {
    "default_behavior": "Guard",
    "behaviors": ["Guard", "Chase", "Combat", "Flee", "Loot"]
  }
}
```

加载：
```gdscript
behavior_fsm.load_behaviors(config["behaviors"], config["default_behavior"])
behavior_fsm.start(unit)
```

## 依赖

- `BaseBehavior` — 行为基类
- 所有具体行为脚本（按需动态加载）

## 相关文档

- [AI 控制器](ai_controller.md)
- [行为模组](behaviors.md)
