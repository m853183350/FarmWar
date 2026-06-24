# EffectManager（效果管理器）

管理效果注册表和执行流程的 RefCounted 类。由 [PropManager] 创建和持有，负责效果实例的注册、运行时上下文构建、条件评估和效果执行。

## 用途

- 维护效果类型 → 效果实例的注册表
- 在效果执行时动态构建运行时上下文（服务引用 + 触发数据）
- 统一评估效果触发条件（冷却、概率等）
- 支持堆叠执行（持有 n 个道具 → 执行 n 次）
- 支持复合效果（一个道具配置多个效果，依次执行）
- 区分效果类别（即时 / 修饰 / 持续），分别处理

## 依赖

| 依赖 | 说明 |
|------|------|
| `PropEffectBase` | 效果基类，所有效果实例必须继承它 |
| `PropData` | 道具定义数据类，提供 effects 配置列表 |
| 上下文提供器（Callable） | 由 PropManager 注入，返回服务引用 Dictionary |

## 公开 API

### 变量

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `registry` | `Dictionary` | `{}` | 效果注册表 `{effect_type: PropEffectBase}` |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `set_context_provider(provider: Callable)` | `void` | 设置上下文提供器（无参 Callable，返回 Dictionary） |
| `register_effect(effect_type: StringName, effect: PropEffectBase)` | `void` | 注册效果实例，同名覆盖 |
| `unregister_effect(effect_type: StringName)` | `void` | 取消注册 |
| `has_effect(effect_type: StringName)` | `bool` | 检查是否已注册 |
| `get_registered_types()` | `Array[StringName]` | 获取所有已注册的效果类型列表 |
| `execute(prop_data: RefCounted, count: int, trigger_context: Dictionary)` | `void` | 执行道具的所有效果（主入口） |

## 执行流程

```
EffectManager.execute(prop_data, count, trigger_context)
  ├── 1. 从 prop_data.effects 获取效果配置列表
  ├── 2. _build_context(trigger_context)
  │     ├── 调用 _context_provider() 获取服务引用 {"storage": ..., ...}
  │     └── 合并 trigger_context {"signal_name": ..., "crop_node": ..., ...}
  ├── 3. 遍历每个 effect_entry
  │     ├── _execute_single_effect(effect_entry, count, context, prop_data)
  │     │   ├── 从 registry 查找 effect_instance
  │     │   ├── _evaluate_conditions(effect_instance, params, context, prop_data)
  │     │   │   └── effect_instance.can_trigger(params, context)
  │     │   └── match effect_instance.get_category():
  │     │       ├── INSTANT  → effect.execute(params, context) × count
  │     │       ├── MODIFIER → effect.on_apply(params, context)
  │     │       └── DURATION → effect.on_apply(params, context)
```

## 运行时上下文结构

每次执行效果时构建的 `context: Dictionary` 包含：

```gdscript
{
    # ---- 服务引用（由 _context_provider 提供） ----
    "storage": Storage,           # 仓库引用
    # 未来可扩展： "unit_manager", "farmland_manager", "pathfinding_manager" 等

    # ---- 触发数据（由 trigger_context 合并） ----
    "trigger_signal": StringName,  # 哪个 EventBus 信号触发了效果
    "crop_node": Node2D,           # 触发信号携带的参数（以 crop_matured 为例）
    "grid_pos": Vector2i,
    "crop_id": String,
    # 不同信号携带不同参数
}
```

## 使用示例

### 在 PropManager 中初始化

```gdscript
func _setup_effect_manager() -> void:
    _effect_manager = EffectManagerClass.new()
    _effect_manager.set_context_provider(_provide_effect_context)

    # 注册效果类型
    _effect_manager.register_effect(&"add_storage_item", AddStorageItemEffect.new())
    # 未来新增效果：
    # _effect_manager.register_effect(&"heal_unit", HealUnitEffect.new())
    # _effect_manager.register_effect(&"stat_modifier", StatModifierEffect.new())

func _provide_effect_context() -> Dictionary:
    return {
        "storage": _storage,
        # "unit_manager": _unit_manager,  # 未来
    }
```

### 触发执行

```gdscript
# 在 PropManager 的信号处理中
func _on_crop_matured(crop_node: Node2D, grid_pos: Vector2i, crop_id: String) -> void:
    var trigger_context: Dictionary = {
        "trigger_signal": &"crop_matured",
        "crop_node": crop_node,
        "grid_pos": grid_pos,
        "crop_id": crop_id,
    }
    _process_trigger(&"crop_matured", trigger_context)

func _process_trigger(signal_name: StringName, trigger_context: Dictionary) -> void:
    # ... 查找绑定道具 ...
    _effect_manager.execute(prop_data, count, trigger_context)
```

### 编写新效果

```gdscript
class_name HealUnitEffect extends PropEffectBase

func execute(params: Dictionary, context: Dictionary) -> void:
    var amount: float = params.get("amount", 0.0)
    var unit_manager = context.get("unit_manager")
    if unit_manager:
        unit_manager.heal_all(amount)
```

## 效果类别说明

| 类别 | 枚举值 | 执行行为 | 适用场景 |
|------|--------|---------|---------|
| INSTANT | `EffectCategory.INSTANT` | 每次触发执行 `execute()` count 次 | 添加资源、生成实体、单次伤害/治疗 |
| MODIFIER | `EffectCategory.MODIFIER` | 首次持有调用 `on_apply()`，移除时调用 `on_remove()` | 属性加成、生长加速、价格折扣 |
| DURATION | `EffectCategory.DURATION` | 生效时调用 `on_apply()`，到期后外部调用 `on_remove()` | 限时 buff/debuff |

## 关联文档

- [7.1道具和buff系统.md](7.1道具和buff系统.md) — 系统设计总览
- [prop_manager.md](prop_manager.md) — PropManager API
- [effects/prop_effect_base.md](effects/prop_effect_base.md) — 效果基类 API
- [effects/add_storage_item_effect.md](effects/add_storage_item_effect.md) — 添加物品效果
