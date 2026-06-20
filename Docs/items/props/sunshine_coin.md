# SunshineCoin（阳光硬币）

第一个实现的道具。每当有作物成熟时，为玩家的仓库添加 1 个金币（`money`）。

## 属性

| 属性 | 值 | 说明 |
|------|-----|------|
| `prop_id` | `sunshine_coin` | 唯一标识符 |
| `prop_name` | 阳光硬币 | 显示名称 |
| `description` | 每当有作物成熟时，获得1枚金币。阳光照耀下，硬币闪闪发光。 | 风味文字 |
| `rarity` | `common` | 常见稀有度 |
| `icon_path` | （空） | 暂无图标 |
| `max_stack` | `10` | 最多持有 10 个 |
| `trigger_signal` | `crop_matured` | 监听作物成熟事件 |
| `effect_type` | `add_storage_item` | 向仓库添加物品 |
| `effect_params` | `{"item_id": "money", "amount": 1.0}` | 添加 1 个 money |
| `tags` | `["economy", "crop"]` | 经济类 + 作物类标签 |

## 触发机制

```
Crop 进入最终生长阶段
  → EventBus.crop_matured.emit(crop_node, grid_pos, crop_id)
    → PropManager 查找 trigger_signal == "crop_matured" 的道具
      → 找到 sunshine_coin
        → 执行 add_storage_item 效果
          → Storage.add_item("money", 1.0)
```

## 堆叠行为

- 每持有一个 `sunshine_coin`，每次作物成熟时都触发一次效果（获得 1 money）
- 持有 3 个 → 每次成熟获得 3 money
- 最大堆叠数 10 → 最多每次成熟获得 10 money

## 配置文件

文件路径：`config/items/props/sunshine_coin.json`

```json
{
    "prop_id": "sunshine_coin",
    "prop_name": "阳光硬币",
    "description": "每当有作物成熟时，获得1枚金币。阳光照耀下，硬币闪闪发光。",
    "rarity": "common",
    "icon_path": "",
    "max_stack": 10,
    "trigger_signal": "crop_matured",
    "trigger_condition": {},
    "effect_type": "add_storage_item",
    "effect_params": {
        "item_id": "money",
        "amount": 1.0
    },
    "tags": ["economy", "crop"]
}
```

## 涉及物品

`money`（金币）需要在物品目录中注册：

```json
// config/items/item_catalog.json
"money": {
    "display_name": "金币",
    "category": "currency"
}
```

## 关联文档

- [7.1道具和buff系统.md](../7.1道具和buff系统.md) — 系统设计总览
- [../prop_manager.md](../prop_manager.md) — PropManager API
- [../../storage/storage.md](../../storage/storage.md) — Storage（效果目标）
