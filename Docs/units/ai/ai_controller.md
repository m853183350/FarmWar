# AIController — AI 控制器

## 概述

`AIController` 是所有战斗单位的决策中枢，挂载在 `CombatUnitBase` 的子节点上。采用**模块化架构**，通过 JSON 配置动态组装子模块（仇恨系统、技能选择器、行为模组），不同单位类型可拥有不同的 AI 模组组合。

**文件：** `scripts/units/ai/ai_controller.gd`
**类型：** `class_name AIController extends Node`

## 架构

```
AIController (Node)
├── HatredSystem (Node)           ← 可选：攻击型 → 挂载；纯防守型 → 省略
├── SkillSelector (Node)          ← 可选：有技能的单位挂载
└── BehaviorFSM (Node)            ← 必需：行为模组动态加载
    ├── GuardBehavior             ← 警戒（通用）
    ├── ChaseBehavior             ← 追击（攻击型）
    ├── CombatBehavior            ← 战斗（攻击型）
    ├── FleeBehavior              ← 逃跑（有 HP 的）
    ├── PatrolBehavior            ← 巡逻（游荡型）
    ├── LootBehavior              ← 战利品采集（可选）
    └── ExecuteTaskBehavior       ← 任务执行（可接收指令的）
```

## 双模式架构

### 任务模式（`current_task != null`）

单位持有 `CombatTask` 时进入任务模式，优先执行任务目标。途中碰到敌人触发**自卫**（只还击不追击），战斗结束后恢复任务。

### 自主模式（`current_task == null`）

无任务时由行为状态机自主决策：
1. 更新仇恨系统（扫描敌人、更新威胁值）
2. 检查逃跑条件（HP < flee_hp_ratio）
3. 检查仇恨驱动切换（发现敌人 → Chase，战斗结束 → Loot → Guard）
4. 委托给当前行为执行

## 关键 Signal 流

```
CombatUnitBase._update_controller()
  → ai_controller.update(unit, delta)
    → HatredSystem.update_hatred()        # 扫描敌人
    → BehaviorFSM.update()                # 当前行为 tick
    → _should_flee()                      # HP 检查
    → 状态切换逻辑                         # Chase→Combat→Loot→Guard
```

## 配置

### JSON 配置格式

```json
{
  "ai": {
    "default_behavior": "Guard",
    "behaviors": ["Guard", "Chase", "Combat", "Flee", "Loot"],
    "enable_hatred": true,
    "enable_skill_selector": true,
    "flee_hp_ratio": 0.25,
    "hatred_alert_range": 10.0,
    "hatred_chase_range": 20.0,
    "hatred_scan_interval": 5
  }
}
```

### 不同单位类型示例

```json
// 攻击型近战兵：完整战斗 + 战利品
{"behaviors": ["Guard", "Chase", "Combat", "Flee", "Loot"], "enable_hatred": true, "enable_skill_selector": true}

// 纯防守型：只需警戒 + 逃跑
{"behaviors": ["Guard", "Flee"], "enable_hatred": false, "enable_skill_selector": false}

// 游荡侦察兵：巡逻 + 逃跑（不主动战斗）
{"behaviors": ["Guard", "Patrol", "Flee"], "enable_hatred": true, "enable_skill_selector": false}
```

## 公开方法

| 方法 | 说明 |
|------|------|
| `init_from_config(ai_config: Dictionary)` | 从配置字典初始化 AI |
| `update(unit, delta)` | 每 tick 由 CombatUnitBase 调用 |
| `get_current_behavior_name() -> String` | 调试用，返回当前行为名 |

## 依赖

- `TickSystem` — 连接 `tick_elapsed` 信号维护 tick 计数
- `HatredSystem` — 子节点，扫描敌人
- `SkillSelector` — 子节点，选择技能
- `BehaviorFSM` — 子节点，行为管理
- `CombatUnitBase` — 父节点，所有行为操作的目标

## 新增 EventBus 信号（Phase 3）

| 信号 | 发出时机 |
|------|---------|
| `loot_collected(unit_id, loot_name)` | 战利品被采集时（LootBehavior 发出） |

## 相关文档

- [行为状态机](behavior_fsm.md)
- [仇恨系统](hatred_system.md)
- [技能选择器](skill_selector.md)
- [行为模组](behaviors.md)
- [战斗单位基类](../combat_unit_base.md)
