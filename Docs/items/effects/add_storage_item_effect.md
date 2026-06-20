# AddStorageItemEffect（添加物品效果）

向仓库添加指定物品的效果实现。

## 用途

当道具触发时，向 [Storage] 添加指定数量的物品。目前用于 `sunshine_coin` 添加 `money`。

## 继承

`PropEffectBase` → `AddStorageItemEffect`

## 参数格式

```json
{
    "item_id": "money",
    "amount": 1.0
}
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `item_id` | String | 要添加的物品 ID |
| `amount` | float | 添加数量 |

## 实现

```gdscript
func execute(params: Dictionary) -> void:
    storage.add_item(params["item_id"], params["amount"])
```

[member storage] 由 [PropEffectBase.init] 注入，在 [PropManager._init_effects] 时完成。

## 关联文档

- [prop_effect_base.md](prop_effect_base.md) — 基类
- [../prop_manager.md](../prop_manager.md) — PropManager（效果注册）
