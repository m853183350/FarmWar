# PropEffectBase（道具效果基类）

所有道具效果的抽象基类。效果通过 `context` 字典在运行时获取所需服务引用（而非构造时注入），子类必须覆写 `execute()` 实现具体逻辑。

## 用途

- 将效果逻辑从 PropManager 和 EffectManager 中分离，保持核心文件精简
- 新增效果只需创建子类 + 在 EffectManager 中注册一行，无需修改任何核心逻辑
- 支持条件触发（`can_trigger()` 钩子）
- 支持多种效果类别（即时 / 修饰 / 持续）

## 依赖

效果不持有任何固定依赖。所有服务引用通过 `execute(params, context)` 的 `context` 参数在运行时传入。

## 公开 API

### 枚举

| 枚举 | 值 | 说明 |
|------|------|------|
| `EffectCategory.INSTANT` | 0 | 即时效果 — 触发时一次性执行 |
| `EffectCategory.MODIFIER` | 1 | 修饰效果 — 持有期间持续生效 |
| `EffectCategory.DURATION` | 2 | 持续效果 — 限时 buff/debuff |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `get_category()` | `EffectCategory` | 返回效果类别，默认 INSTANT。子类按需覆写 |
| `can_trigger(params, context)` | `bool` | 条件钩子，默认 true。子类覆写以实现条件触发 |
| `execute(params, context)` | `void` | 执行效果（子类必须覆写） |
| `on_apply(params, context)` | `void` | 修饰/持续效果生效时调用（子类按需覆写） |
| `on_remove(params, context)` | `void` | 修饰/持续效果移除时调用（子类按需覆写） |

### context 字典结构

```gdscript
{
    # ---- 服务引用（由 EffectManager._context_provider 提供） ----
    "storage": Storage,

    # ---- 触发数据（由 PropManager 信号处理传入） ----
    "trigger_signal": StringName,   # 如 &"crop_matured"
    "crop_node": Node2D,
    "grid_pos": Vector2i,
    "crop_id": String,
    # ... 更多信号特定参数
}
```

## 子类

| 类 | 文件 | 说明 |
|----|------|------|
| `AddStorageItemEffect` | `add_storage_item_effect.gd` | 向仓库添加物品 |

## 关联文档

- [../effect_manager.md](../effect_manager.md) — EffectManager（效果注册与调度）
- [../prop_manager.md](../prop_manager.md) — PropManager（道具持有与信号桥接）
- [add_storage_item_effect.md](add_storage_item_effect.md) — 首个效果实现
