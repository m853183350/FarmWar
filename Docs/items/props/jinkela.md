# Jinkela（金坷垃）✅ 已实现

被动持有型 MODIFIER 道具。全局增加所有耕地（farmland）的肥力修正值1（`fertility_modifier_1`），提升作物产量。通过 [ModifierRegistry] + [Domain] 实现，持有期间持续生效，地块在计算肥力时被动查询聚合值。

> 实施日期：2026-06-25 | Phase 0 + Phase 1

## 属性

| 属性 | 值 | 说明 |
|------|-----|------|
| `prop_id` | `jinkela` | 唯一标识符 |
| `prop_name` | 金坷垃 | 显示名称 |
| `description` | 全局增加所有耕地肥力 0.3。金坷垃，亩产一千八！ | 风味文字 |
| `rarity` | `uncommon` | 非普通稀有度 |
| `icon_path` | （空） | 暂无图标 |
| `max_stack` | `10` | 最多持有 10 个 |
| `prop_category` | `modifier` | **MODIFIER 类别**（非 INSTANT） |
| `modifier.target_domains` | `["tile"]` | 影响地块领域 |
| `modifier.stat` | `fertility_modifier_1` | 修改肥力修正值1 |
| `modifier.value` | `0.3` | 每个持有数增加的量 |
| `modifier.priority` | `100` | 排序优先级 |
| `modifier.tags` | `["flat"]` | 固定值加成（result += value） |
| `modifier.target_filter` | `{"tile_type": "farmland"}` | **仅对 farmland 地块生效** |
| `tags` | `["farmland", "fertility", "economy"]` | 分类标签 |

## 配置文件

文件路径：`config/items/props/jinkela.json`

```json
{
    "prop_id": "jinkela",
    "prop_name": "金坷垃",
    "description": "全局增加所有耕地肥力 0.3。金坷垃，亩产一千八！",
    "rarity": "uncommon",
    "max_stack": 10,
    "prop_category": "modifier",
    "modifier": {
        "target_domains": ["tile"],
        "stat": "fertility_modifier_1",
        "value": 0.3,
        "priority": 100,
        "tags": ["flat"],
        "target_filter": { "tile_type": "farmland" }
    },
    "requires": [],
    "conflicts_with": [],
    "tags": ["farmland", "fertility", "economy"]
}
```

## 效果机制

金坷垃属于 **MODIFIER** 类别，与 sunshine_coin 的 INSTANT 类别不同——它不在游戏事件触发时执行，而是注册到 [ModifierRegistry] 的 "tile" [Domain] 中，地块计算肥力时被动查询聚合值。

### 生效流程

```
PropManager.add_prop("jinkela")
  → match prop_category: "modifier"
    → _apply_modifier(data, count)
      → ModifierRegistry.register_modifier(modifier_config, "jinkela", count)
        → _ensure_domain("tile")
        → Domain.add_modifier(modifier_config, "jinkela", count)
          → value = 0.3 × count, 加入 _chain
      → _notify_modifiers_changed()
        → EventBus.tile_modifiers_changed.emit()
          → 所有 BaseTile._on_modifiers_changed()
            → update_properties()
              → _calculate_fertility()
```

### 查询时（地块肥力计算）

```
BaseTile._calculate_fertility()
  → _build_modifier_context()  →  {"tile_type": "farmland"}
  → _query_modifier("fertility_modifier_1", 0.0)
    → PropManager.query_modifier("tile", "fertility_modifier_1", 0.0, context)
      → ModifierRegistry.calculate("tile", "fertility_modifier_1", 0.0, context)
        → Domain.calculate("fertility_modifier_1", 0.0, context)
          → _matches_filter() → tile_type == "farmland" ✓
          → flat: result += 0.3 × count
          → return 0.3 × count
    → mod1 = 0.3 × count
  → fertility = (fertility_base + mod1) × mult + mod2
```

### 肥力计算公式

```
fertility = (fertility_base + fertility_modifier_1) × fertility_multiplier + fertility_modifier_2
```

金坷垃修改的是 `fertility_modifier_1`，即与地块基础值相加后再乘以修正倍率。
例如 farmland 的 `fertility_base = 0.8`，持 1 个金坷垃时：
- `fertility_modifier_1 = 0.0 + 0.3 = 0.3`
- `fertility = (0.8 + 0.3) × 1.0 + 0.0 = 1.1`

### target_filter 过滤

金坷垃的 `target_filter: {"tile_type": "farmland"}` 确保：
- farmland 地块 → 获得加成 ✅
- dirt / stone / ocean 地块 → 不受影响 ✅

过滤由 [Domain._matches_filter()] 在计算时根据 BaseTile 传入的 context 自动完成。

## 堆叠行为

- 持 1 个 → `fertility_modifier_1` +0.3 → farmland 肥力 = 1.1
- 持 3 个 → `fertility_modifier_1` +0.9 → farmland 肥力 = 1.7
- 持 10 个（上限）→ `fertility_modifier_1` +3.0 → farmland 肥力 = 3.8

## 对作物的影响链

```
地块 fertility 增加
  → BaseTile.update_properties() 更新 fertility
    → Crop._on_tile_data_changed() 重新计算生长速度
      → 收获时 yield_modifier 基于 fertility 计算
```

## 实现状态

| 依赖项 | 状态 | 说明 |
|--------|------|------|
| Domain 类 | ✅ 已实现 | `scripts/items/domain.gd` |
| ModifierRegistry 类 | ✅ 已实现 | `scripts/items/modifier_registry.gd` |
| PropData 扩展 | ✅ 已实现 | 新增 `prop_category`、`modifier` 等字段 |
| PropManager MODIFIER 路由 | ✅ 已实现 | `add_prop`/`remove_prop` 中的 `match category` 分支 |
| target_filter 机制 | ✅ 已实现 | Domain 链全链路透传 context 过滤 |
| BaseTile 接入 | ✅ 已实现 | `_calculate_fertility()` 查询 ModifierRegistry |
| tile_modifiers_changed 信号 | ✅ 已实现 | 修饰器变更后触发地块重算 |
| DebugUI 展示 | ✅ 已实现 | F3 面板显示活跃修饰器 |
| 新地块自动应用 | ✅ 已实现 | `update_properties()` 调用时实时查询 |
| 已存在地块动态更新 | ✅ 已实现 | EventBus 信号触发重算 |

## 关联文档

- [7.1道具和buff系统.md](../7.1道具和buff系统.md) — 系统设计总览
- [../prop_manager.md](../prop_manager.md) — PropManager API
- [../modifier_registry.md](../modifier_registry.md) — ModifierRegistry API
- [../domain.md](../domain.md) — Domain API
- [../effect_manager.md](../effect_manager.md) — EffectManager API
- [sunshine_coin.md](sunshine_coin.md) — 阳光硬币（INSTANT 类别参考）
- [../../world/tiles/base_tile.gd](../../scripts/world/tiles/base_tile.gd) — 地块肥力计算公式
- [../../0624效果系统优化方案.md](../../0624效果系统优化方案.md) — 系统设计文档
