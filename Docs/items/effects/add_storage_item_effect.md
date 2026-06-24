# AddStorageItemEffect（添加物品效果）

向仓库添加指定物品的效果实现。

## 用途

当道具触发时，向 Storage 添加指定数量的物品。目前用于 `sunshine_coin` 添加 `money`。

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

## 运行时依赖

通过 `context["storage"]` 获取 Storage 引用（由 EffectManager 在每次执行时注入）。

## 实现

```gdscript
func execute(params: Dictionary, context: Dictionary) -> void:
    var storage: Storage = context.get("storage", null) as Storage
    if storage == null:
        push_error("AddStorageItemEffect: context 中缺少 storage 引用")
        return
    storage.add_item(params["item_id"], params["amount"])
```

## 关联文档

- [prop_effect_base.md](prop_effect_base.md) — 基类
- [../effect_manager.md](../effect_manager.md) — EffectManager（效果注册与执行）
- [../prop_manager.md](../prop_manager.md) — PropManager（道具持有与触发）
