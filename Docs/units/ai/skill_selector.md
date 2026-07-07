# SkillSelector — 技能选择器

## 概述

从战斗单位的可用技能列表中为 AI 选出最优技能执行。由 `AIController` / `CombatBehavior` 调用。

**文件：** `scripts/units/ai/skill_selector.gd`
**类型：** `class_name SkillSelector extends Node`

## 选择策略

### 1. 过滤（硬条件）

- 射程内：`distance_to(target) <= skill.range × TILE_SIZE`
- 冷却完成：`skill_cooldowns[skill_id] <= 0`
- 法力足够：`current_mana >= skill.mana_cost`
- 无技能执行中：`active_skill == null`
- 非眩晕状态

### 2. 排序

1. `ai_priority` 降序（AI 权重高的优先）
2. `is_basic_attack` = true 优先（省蓝）
3. `mana_cost` 升序（法力消耗低的优先）

### 3. 斩杀逻辑

目标血量 ≤ `EXECUTE_THRESHOLD`（默认 20.0）时，优先使用普攻：
- `enable_execute_logic = true`：启用斩杀
- `require_lethal_for_execute = false`：只要有普攻就选（不验证伤害）
- `require_lethal_for_execute = true`：验证普攻预期伤害 ≥ 目标当前血量

## 配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `enable_execute_logic` | true | 是否启用斩杀逻辑 |
| `require_lethal_for_execute` | false | 斩杀时是否验证伤害足够 |

## 公开方法

| 方法 | 说明 |
|------|------|
| `select_skill(unit, target) -> Skill` | 选择最优技能，无则返回 null |
| `get_skills_in_range(unit, target) -> Array[Skill]` | 获取射程内可用技能（调试用） |
| `get_closest_range(unit) -> float` | 获取最近可用技能的射程，无则返回 -1 |

## 使用示例

```gdscript
# 在 CombatBehavior.update() 中
var ss: SkillSelector = skill_selector()
var chosen: Skill = ss.select_skill(unit, target)
if chosen != null:
    unit.start_skill(chosen)
```

## 依赖

- `CombatUnitBase` — 通过 `get_available_skills()` 获取技能列表
- `Skill` — 技能 Resource

## 相关文档

- [AI 控制器](ai_controller.md)
- [战斗行为](behaviors.md#combatbehavior)
- [Skill 数据结构](../skill.md)
