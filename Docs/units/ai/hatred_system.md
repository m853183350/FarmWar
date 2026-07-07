# HatredSystem — 仇恨系统

## 概述

管理战斗单位的仇恨列表和威胁评估。周期性扫描范围内的敌方单位，计算威胁值并按优先级排序，为 AI 的自主战斗行为提供目标选择依据。

**文件：** `scripts/units/ai/hatred_system.gd`
**类型：** `class_name HatredSystem extends Node`

## 内部数据结构

### HatredEntry

```gdscript
class HatredEntry:
    var target: CombatUnitBase   # 目标单位
    var threat: float            # 威胁值（越高越优先攻击）
    var distance: float          # 距离
    var last_seen_tick: int      # 最后被扫描到的 tick
```

## 威胁值计算公式

```
threat = 0
threat += (1 / max(distance, 0.1)) × DISTANCE_WEIGHT(10.0)   # 距离越近威胁越高
threat += (current_hp / max_hp) × HEALTH_WEIGHT(5.0)          # 血量比例越高威胁越高

if target.current_target == self:
    threat ×= 2.0    # 正在攻击我，威胁翻倍
elif target 正在攻击友方:
    threat ×= 1.3    # 攻击友方，略微加威胁
```

## 配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `scan_interval_ticks` | 5 | 扫描间隔（避免每 tick 全图扫描） |
| `alert_range` | 10.0 | 警戒范围（格），范围内的敌人才加入仇恨 |
| `chase_range` | 20.0 | 追击范围（格），超出则放弃追击 |
| `max_hatred_entries` | 10 | 最大仇恨条目数 |

## 公开方法

| 方法 | 说明 |
|------|------|
| `update_hatred(unit, current_tick)` | 每 tick 由 AIController 调用 |
| `get_primary_target() -> CombatUnitBase` | 获取最高威胁目标，无则返回 null |
| `has_threat_target() -> bool` | 是否有仇恨目标 |
| `add_hatred_target(target, base_threat)` | 手动添加仇恨（如被攻击时） |
| `clear_hatred()` | 清空仇恨列表 |
| `get_hatred_list() -> Array[HatredEntry]` | 调试用，返回副本 |

## 扫描机制

1. 通过 `UnitManager.workers` 查找已注册的战斗单位（`is CombatUnitBase`）
2. 递归扫描场景树中的 `CombatUnitBase` 实例（兜底方案，后续 EnemyManager 替代）
3. 过滤：不同阵营 + 存活 + 在 alert_range 内
4. 计算威胁值 → 更新或新增条目 → 按威胁值降序排列
5. 移除超出 chase_range 或连续多次未扫描到的条目
6. 自动清理已死亡/无效的目标

## 依赖

- `UnitManager` — Autoload，查询已注册单位
- `CombatUnitBase` — 目标类型

## 相关文档

- [AI 控制器](ai_controller.md)
- [行为状态机](behavior_fsm.md)
