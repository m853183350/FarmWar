# Jinkela（金坷垃）

被动持有型道具。全局增加所有耕地（farmland）的肥力基础值，提升作物产量。属于 MODIFIER 类效果——持有期间持续生效，移除时自动复原。

## 属性

| 属性 | 值 | 说明 |
|------|-----|------|
| `prop_id` | `jinkela` | 唯一标识符 |
| `prop_name` | 金坷垃 | 显示名称 |
| `description` | 全局增加所有耕地肥力 0.3。金坷垃，亩产一千八！ | 风味文字 |
| `rarity` | `uncommon` | 非普通稀有度 |
| `icon_path` | （空） | 暂无图标 |
| `max_stack` | `5` | 最多持有 5 个 |
| `trigger_signal` | `prop_acquired` | 道具获取/失去时触发 |
| `effect_type` | `modify_tile_stat` | 修改地块属性（MODIFIER 类别） |
| `effect_params` | `{"target_tile_type": "farmland", "stat": "fertility_modifier_1", "delta_per_stack": 0.3}` | 每个持有数增加 farmland 地块的 fertility_modifier_1 0.3 |
| `tags` | `["farmland", "fertility", "economy"]` | 农田类 + 肥力类 + 经济类标签 |

## 效果机制

金坷垃属于 **MODIFIER**（修饰效果）类别，与 sunshine_coin 的 INSTANT 类别不同——它不在游戏事件触发时执行，而是在道具持有期间持续对地块属性生效。

### 肥力计算公式（来自 `BaseTile._calculate_fertility()`）

```
fertility = (fertility_base + fertility_modifier_1) × fertility_multiplier + fertility_modifier_2
```

金坷垃修改的是 `fertility_modifier_1`，即与地块基础值相加后再乘以修正倍率。这意味着**地块自身的 `fertility_multiplier` 越高，金坷垃的收益越大**。

### 生效流程

```
PropManager.add_prop("jinkela")
  → EffectManager 识别 effect_type == "modify_tile_stat"（MODIFIER 类别）
    → 调用 ModifyTileStatEffect.on_apply(params, context)
      → 遍历 world 中所有 tile_type == "farmland" 的地块
        → tile.tile_data.fertility_modifier_1 += 0.3
          → tile.update_properties()  // 重新计算 fertility
            → tile.tile_data_changed.emit()  // 通知作物重新计算环境修正值

PropManager.remove_prop("jinkela")
  → EffectManager 识别 MODIFIER 类别
    → 调用 ModifyTileStatEffect.on_remove(params, context)
      → 遍历所有 farmland 地块
        → tile.tile_data.fertility_modifier_1 -= 0.3
          → tile.update_properties()
```

### 对作物的影响链

```
地块 fertility 增加
  → BaseTile.tile_data_changed 信号
    → Crop._on_tile_data_changed()
      → Crop._recalc_modifiers()
        → fertility_modifier = sqrt(fertility_factor × tile_fertility)
          → yield_modifier = 1.0 × fertility_modifier × independent_yield_modifier
            → 收获时实际产出 = base_amount × yield_modifier
```

## 堆叠行为

- 每持有一个 `jinkela`，所有 farmland 地块的 `fertility_modifier_1` 增加 `0.3`
- 持有 3 个 → 每个 farmland 地块 +0.9 玩家肥力修正值1
- 最大堆叠数 10 → 最多 +3 玩家肥力修正值1

## 对新地块的自动应用

当玩家持有金坷垃时，新转化/生成的 farmland 地块也需要自动应用修正值。这通过以下机制实现：

1. **地块转化时**（如 DIRT → FARMLAND）：`TileActions` 调用 `update_properties()` 之前，检查 PropManager 中持有 jinkela 并预先设置 `fertility_modifier_1`
2. **地块生成时**：`TerrainGenerator` 创建完地块后，由 PropManager 统一遍历应用

## 配置文件

文件路径：`config/items/props/jinkela.json`

```json
{
    "prop_id": "jinkela",
    "prop_name": "金坷垃",
    "description": "全局增加所有耕地肥力 0.3。金坷垃，亩产一千八！",
    "rarity": "uncommon",
    "icon_path": "",
    "max_stack": 10,
    "trigger_signal": "prop_acquired",
    "trigger_condition": {},
    "effect_type": "modify_tile_stat",
    "effect_params": {
        "target_tile_type": "farmland",
        "stat": "fertility_modifier_1",
        "delta_per_stack": 0.3
    },
    "tags": ["farmland", "fertility", "economy"]
}
```

## 实现状态

**当前状态：已规划，待实现。**

实现此道具依赖以下工作：

| 依赖项 | 状态 | 说明 |
|--------|------|------|
| `ModifyTileStatEffect` 效果类 | ❌ 待创建 | 需要在 `scripts/items/effects/` 中创建，继承 `PropEffectBase`，类别为 MODIFIER |
| `prop_acquired` 信号 | ❌ 待添加 | PropManager 需要在添加/移除 MODIFIER 类道具时触发 apply/remove |
| 新地块自动应用 | ❌ 待实现 | 地块转化/生成时需检查已持有的 MODIFIER 道具 |
| MODIFIER 效果生命周期 | ⚠️ 基类已支持 | `PropEffectBase.on_apply()` / `on_remove()` 已定义，需 EffectManager 调度 |

### 效果类骨架（待实现）

```gdscript
# scripts/items/effects/modify_tile_stat_effect.gd
class_name ModifyTileStatEffect extends PropEffectBase

func get_category() -> EffectCategory:
    return EffectCategory.MODIFIER

func on_apply(params: Dictionary, context: Dictionary) -> void:
    var target_type: String = params.get("target_tile_type", "")
    var stat: String = params.get("stat", "")
    var delta: float = params.get("delta_per_stack", 0.0)
    # 遍历所有匹配地块，修改 tile_data[stat] += delta
    # 调用 tile.update_properties()
    # 缓存已修改的地块列表，供 on_remove 使用

func on_remove(params: Dictionary, context: Dictionary) -> void:
    # 反向操作：tile_data[stat] -= delta
    # 调用 tile.update_properties()
```

## 关联文档

- [7.1道具和buff系统.md](../7.1道具和buff系统.md) — 系统设计总览
- [../prop_manager.md](../prop_manager.md) — PropManager API
- [../effect_manager.md](../effect_manager.md) — EffectManager API
- [../effects/prop_effect_base.md](../effects/prop_effect_base.md) — 效果基类（含 MODIFIER 类别定义）
- [props/sunshine_coin.md](sunshine_coin.md) — 阳光硬币（INSTANT 类别参考）
- [../../world/base_tile.md](../../world/base_tile.md) — BaseTile 肥力计算公式
- [../../crops/crop.md](../../crops/crop.md) — 作物环境修正值计算
