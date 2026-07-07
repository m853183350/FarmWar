# AI 行为模组

## 概述

行为模组是 AI 系统的**可插拔组件**，挂载在 `BehaviorFSM` 下。每个模组实现一种特定的 AI 行为。
所有模组继承 `BaseBehavior`，通过 JSON 配置决定哪些单位挂载哪些模组。

**基类文件：** `scripts/units/ai/behaviors/base_behavior.gd`
**行为目录：** `scripts/units/ai/behaviors/`

## BaseBehavior — 抽象基类

所有行为的公共接口和便捷访问器。

### 虚方法（子类必须/可选覆写）

| 方法 | 说明 |
|------|------|
| `enter(unit: CombatUnitBase)` | 进入行为时调用 |
| `exit(unit: CombatUnitBase)` | 退出行为时调用（切换到其他行为前） |
| `update(unit: CombatUnitBase, delta: float)` | 每 tick 更新 |

### 访问器

| 方法 | 返回 | 说明 |
|------|------|------|
| `fsm()` | `Node` | 获取 BehaviorFSM 引用 |
| `controller()` | `Node` | 获取 AIController 引用 |
| `hatred()` | `HatredSystem` | 获取仇恨系统 |
| `skill_selector()` | `SkillSelector` | 获取技能选择器 |
| `switch_to(unit, name)` | — | 便捷方法，委托给 BehaviorFSM.switch_to() |

---

## GuardBehavior — 原地警戒

**文件：** `guard_behavior.gd`
**适用场景：** 所有单位（自主模式默认行为）

行为：站立不动，周期性扫描敌人。发现敌方 → 切 Chase。

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `look_around_interval` | 40 | 翻转朝向的间隔（tick），模拟警戒张望 |

**典型配置：**
```json
{"behaviors": ["Guard"]}
```

---

## PatrolBehavior — 区域巡逻

**文件：** `patrol_behavior.gd`
**适用场景：** 游荡型侦察单位

行为：在巡逻中心点半径内随机选点 → 移动 → 到达后等待 → 选下一点。发现敌方 → 切 Chase。

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `patrol_radius` | 5.0 | 巡逻半径（格） |
| `wait_ticks` | 40 | 到达巡逻点后等待 tick 数 |

**典型配置：**
```json
{"behaviors": ["Guard", "Patrol", "Flee"]}
```

---

## ChaseBehavior — 追击

**文件：** `chase_behavior.gd`
**适用场景：** 攻击型单位

行为：向仇恨目标移动，定期更新路径。进入技能射程 → 切 Combat。目标丢失 → 切 Guard。

| 常量 | 默认值 | 说明 |
|------|--------|------|
| `PATH_UPDATE_INTERVAL` | 10 | 路径更新间隔（tick） |
| `ARRIVAL_THRESHOLD` | 4.0 | 到达判定距离（像素） |

**典型配置：**
```json
{"behaviors": ["Guard", "Chase", "Combat"]}
```

---

## CombatBehavior — 战斗

**文件：** `combat_behavior.gd`
**适用场景：** 有技能的攻击型单位

行为：停止移动 → 用 SkillSelector 选技能 → 施放 → 等待完成 → 选下一个。目标死亡/脱离射程 → 切 Chase。

无配置参数。

**典型配置：**
```json
{"behaviors": ["Guard", "Chase", "Combat", "Flee"]}
```

---

## FleeBehavior — 逃跑

**文件：** `flee_behavior.gd`
**适用场景：** 有生命值的单位（HP < 阈值时触发）

行为：计算远离所有仇恨目标的平均方向 → 移动 → 安全后切回 Guard。

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `flee_duration_ticks` | 60 | 最大逃跑持续 tick |
| `safe_distance` | 12.0 | 安全距离（格），大于此距离视为安全 |

**触发条件（由 AIController 判断）：**
- `current_hp / max_hp <= flee_hp_ratio`（默认 0.25）
- 有仇恨目标存在

**典型配置：**
```json
{"ai": {"behaviors": ["Guard", "Flee"], "flee_hp_ratio": 0.25}}
```

---

## LootBehavior — 战利品采集

**文件：** `loot_behavior.gd`
**适用场景：** 需要收集掉落物的单位（Phase 3 新增）

行为：战斗结束后（仇恨清空）自动扫描附近 `loot` group 节点 → 移动到最近战利品 → 采集 → 扫描下一个 → 无战利品时切回 Guard。

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `loot_range` | 15.0 | 采集范围（格） |
| `collect_ticks` | 10 | 采集单个战利品所需 tick |
| `loot_during_combat` | false | 是否在战斗中也采集 |

**触发条件（由 AIController 判断）：**
- Chase/Combat 结束，仇恨列表为空
- 单位配置了 "Loot" 行为模组

**战利品节点要求：**
- 加入 `loot` group
- 实现 `collect(unit)` 或 `pick_up(unit)` 方法
- 类型为 Node2D 或子类

**Signal：** `EventBus.loot_collected(unit_id, loot_name)`

**典型配置：**
```json
{"behaviors": ["Guard", "Chase", "Combat", "Flee", "Loot"]}
```

---

## ExecuteTaskBehavior — 任务执行

**文件：** `execute_task_behavior.gd`
**适用场景：** 可接收 CommandSystem 指令的单位

行为：读取 `current_task.target_position` → 移动到目标 → 到达后 `current_task = null`，切 Guard。
途中遇敌触发自卫（5 格内敌人才还击，不主动索敌）。

**当前状态：** Phase 3 基础框架，Phase 4 完整实现。
**CombatTask 类型：** Phase 4 实现，当前通过 duck-typing 访问 `target_position`。

| 常量 | 默认值 | 说明 |
|------|--------|------|
| `ARRIVAL_THRESHOLD` | 8.0 | 到达判定距离（像素） |
| `PATH_UPDATE_INTERVAL` | 20 | 路径更新间隔（tick） |

**典型配置：**
```json
{"behaviors": ["Guard", "ExecuteTask", "Chase", "Combat", "Flee", "Loot"]}
```

---

## 模块化配置速查

| 单位类型 | behaviors |
|---------|-----------|
| 攻击型近战兵 | `["Guard", "Chase", "Combat", "Flee", "Loot"]` |
| 远程射手 | `["Guard", "Chase", "Combat", "Flee"]` |
| 游荡侦察兵 | `["Guard", "Patrol", "Flee"]` |
| 纯防守守卫 | `["Guard", "Flee"]` |
| 指挥官单位 | `["Guard", "ExecuteTask", "Chase", "Combat", "Flee", "Loot"]` |

## 相关文档

- [AI 控制器](ai_controller.md)
- [行为状态机](behavior_fsm.md)
- [仇恨系统](hatred_system.md)
- [技能选择器](skill_selector.md)
