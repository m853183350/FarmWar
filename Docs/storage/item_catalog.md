# 物品目录配置

`config/items/item_catalog.json` 定义游戏中所有物品的元数据，供 [Storage] 查找物品名称和分区归属。

## 文件路径

`res://config/items/item_catalog.json`

## JSON 格式

```json
{
    "item_id": {
        "display_name": "人类可读名称",
        "category": "类别标识"
    }
}
```

### 字段说明

| 字段 | 类型 | 必须 | 说明 |
|------|------|------|------|
| `item_id` | `String` | 是 | JSON 键，物品唯一标识，与作物收获产物中的 `item_id` 对应 |
| `display_name` | `String` | 是 | 控制台打印时使用的人类可读名称 |
| `category` | `String` | 是 | 物品类别，决定存入哪个分区 |

## 类别与分区映射

| category | 分区 |
|----------|------|
| `farm_product` | `farm_products`（农场产品） |
| `seed` | `items`（道具） |
| `material` | `items`（道具） |
| `consumable` | `pending_1`（待定1） |
| 其他/未知 | `items`（默认） |

## 当前物品

| item_id | display_name | category |
|---------|-------------|----------|
| `wheat_grain` | 小麦粒 | farm_product |
| `wheat_seed` | 小麦种子 | farm_product |
| `straw` | 秸秆 | farm_product |

## 新增物品

新增作物时，在 JSON 中添加对应条目即可，无需改代码：

```json
"rice_grain": {
    "display_name": "稻谷",
    "category": "farm_product"
}
```

## 关联文档

- [storage.md](storage.md) — Storage 类实现
- [6.1仓库系统.md](6.1仓库系统.md) — 仓库系统设计
- [Docs/crops/crop.md](../crops/crop.md) — 作物收获产物
