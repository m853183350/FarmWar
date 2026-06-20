# Storage（仓库）

分区式物品存储，挂载在 Player 节点下，通过监听 EventBus 事件自动收集收获产物。

## 用途

- 管理玩家拥有的所有物品及其数量（分区存储）
- 通过 `EventBus.crop_harvested` 自动收集作物收获产物
- 提供增删查接口供其他系统（商店、UI 等）调用
- 控制台打印展示仓库内容（后续扩展 UI）

## 依赖

| 依赖 | 说明 |
|------|------|
| `EventBus` | Autoload，监听 `crop_harvested` 信号 |
| `config/items/item_catalog.json` | 物品目录配置 |

## 公开 API

### 信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `contents_changed` | `partition: String` | 任意分区内容变化时发出 |

### 变量

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `contents` | `Dictionary` | `{}` | 分区存储数据，结构见下方 |
| `catalog` | `Dictionary` | `{}` | 物品目录缓存 |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `get_amount(item_id: String)` | `float` | 获取物品在所有分区中的总数量 |
| `has_item(item_id: String, amount: float)` | `bool` | 检查是否拥有足够数量的物品 |
| `add_item(item_id: String, amount: float)` | `void` | 向仓库添加物品（供外部系统调用） |
| `remove_item(item_id: String, amount: float)` | `bool` | 移除指定数量的物品，不足返回 false |
| `print_contents()` | `void` | 在控制台打印仓库当前内容 |

## 数据结构

### contents

```gdscript
{
    "farm_products": {
        "wheat_grain": 2.5,
        "wheat_seed": 4.0,
        "straw": 3.0
    },
    "items": {},
    "pending_1": {},
    "pending_2": {}
}
```

### 分区配置

| 分区键 | 显示名称 | 说明 |
|--------|----------|------|
| `farm_products` | 农场产品 | 作物收获物 |
| `items` | 道具 | 种子、材料、消耗品等 |
| `pending_1` | 待定1 | 预留 |
| `pending_2` | 待定2 | 预留 |

### 物品目录（item_catalog.json）

```json
{
    "wheat_grain": {
        "display_name": "小麦粒",
        "category": "farm_product"
    }
}
```

类别映射：`farm_product` → `farm_products`，`currency` → `items`，其他 → `items`（默认）

## 事件流

```
Crop.harvest()
  → EventBus.crop_harvested.emit(yields, crop_id)
    → Storage._on_crop_harvested(yields, crop_id)
      → _deposit_item() × N（每项产物存入对应分区）
      → print_contents()（控制台输出）
```

## 控制台输出格式

```
══════════════════════════════
  仓库内容
══════════════════════════════
  [农场产品]
    小麦粒                    0.30
    小麦种子                  3.00
    秸秆                      2.00
  [道具]
    (空)
  [待定1]
    (空)
  [待定2]
    (空)
══════════════════════════════
```

## 关联文档

- [6.1仓库系统.md](6.1仓库系统.md) — 仓库系统设计文档
- [item_catalog.md](item_catalog.md) — 物品目录配置说明
- [Docs/autoload/event_bus.md](../autoload/event_bus.md) — EventBus 信号定义
- [Docs/crops/crop.md](../crops/crop.md) — Crop 收获调用链
