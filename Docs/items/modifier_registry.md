# ModifierRegistry（修饰器注册中心）

管理所有领域和活跃 MODIFIER 效果的 RefCounted 类。由 [PropManager] 创建和持有，负责领域管理、修饰器注册/注销、属性值查询。

## 用途

- 管理多个 [Domain] 实例（按需创建，按 `domain_name` 索引）
- 提供 `register_modifier()` / `unregister_modifier()` 供 PropManager 在道具增删时调用
- 提供 `calculate()` 供游戏系统（如 BaseTile、Crop）查询某领域某属性的聚合值
- 维护活跃修饰器列表用于调试面板展示

## 依赖

| 依赖 | 说明 |
|------|------|
| [Domain] | 领域类，每个领域一个实例，维护修饰器链 |
| [PropManager] | 创建者，在 `_ready()` 中初始化 ModifierRegistry |

## 设计原则

- **被动查询** — 修饰器不主动修改对象属性；游戏系统在需要时调用 `calculate()` 获取聚合值
- **与 INSTANT 效果分离** — ModifierRegistry 只处理 MODIFIER/DURATION 类别；INSTANT 效果继续走 [EffectManager]
- **玩家级别** — 每个 [PropManager] 持有自己的 ModifierRegistry 实例（非全局 Autoload），支持多人模式

## 公开 API

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `register_modifier(modifier_data: Dictionary, prop_id: String, count: int)` | `void` | 注册修饰器到对应领域。支持跨领域：`target_domains` 可包含多个领域名称 |
| `unregister_modifier(prop_id: String)` | `void` | 注销指定道具的所有修饰器（遍历所有领域） |
| `calculate(domain_name: String, stat_name: String, base_value: float, context: Dictionary = {})` | `float` | 查询某领域某属性的聚合值。context 用于 target_filter 匹配 |
| `recalculate_all()` | `void` | 重排序所有领域（值计算是实时的，主要重排序） |
| `get_active_modifiers()` | `Array[Dictionary]` | 获取活跃修饰器列表（用于调试） |
| `get_domain_count()` | `int` | 获取当前领域数量 |
| `get_domain_chain(domain_name: String)` | `Array[Dictionary]` | 获取指定领域的修饰器链（用于调试） |

## 数据结构

### _domains

```gdscript
{
    "tile": <Domain#1>,    # 地块领域
    "player": <Domain#2>,  # 玩家领域（未来）
    # 按需创建
}
```

### _active_modifiers

```gdscript
[
    {
        "prop_id": "jinkela",
        "count": 2,
        "modifier_data": {
            "target_domains": ["tile"],
            "stat": "fertility_modifier_1",
            "value": 0.3,
            "priority": 100,
            "tags": ["flat"],
            "target_filter": {"tile_type": "farmland"}
        }
    }
]
```

## 数据流

### 注册（道具添加时）

```
PropManager.add_prop("jinkela")
  → _apply_modifier(data, count)
    → ModifierRegistry.register_modifier(modifier_config, "jinkela", count)
      → _ensure_domain("tile")
      → domain.add_modifier(modifier_config, "jinkela", count)
      → _active_modifiers.append(...)
```

### 查询（地块计算肥力时）

```
BaseTile.update_properties()
  → _calculate_fertility()
    → _query_modifier("fertility_modifier_1", 0.0)
      → _build_modifier_context()  →  {"tile_type": "farmland"}
      → PropManager.query_modifier("tile", "fertility_modifier_1", 0.0, context)
        → ModifierRegistry.calculate("tile", "fertility_modifier_1", 0.0, context)
          → domain.calculate("fertility_modifier_1", 0.0, context)
            → 遍历链：跳过 stat 不匹配的 → 跳过 target_filter 不匹配的
            → flat: result += value  → 0.0 + 0.3×2 = 0.6
            → return 0.6
    → fertility = (0.8 + 0.6) × 1.0 + 0.0 = 1.4
```

### 变更广播（修饰器变化后触发地块重算）

```
PropManager._apply_modifier() / _remove_modifier()
  → _notify_modifiers_changed()
    → EventBus.tile_modifiers_changed.emit()
      → BaseTile._on_modifiers_changed()
        → update_properties()
```

## 使用示例

```gdscript
# 外部系统查询示例（在游戏系统代码中）
func _calculate_fertility() -> float:
    var pm: Node = get_tree().get_first_node_in_group("prop_manager")
    var mult: float = 1.0
    if pm and pm.has_method("query_modifier"):
        mult = pm.query_modifier("tile", "fertility_multiplier", 1.0, {"tile_type": "farmland"})
    return (base + mod1) * mult + mod2
```

## 关联文档

- [domain.md](domain.md) — Domain API
- [prop_manager.md](prop_manager.md) — PropManager API（创建者）
- [effect_manager.md](effect_manager.md) — EffectManager API（处理 INSTANT 效果）
- [0624效果系统优化方案.md](../0624效果系统优化方案.md) — 系统设计文档
