# EffectManager（效果管理器）

管理 INSTANT 效果注册表和执行流程的 RefCounted 类。由 [PropManager] 创建和持有，负责效果实例的注册、运行时上下文构建、条件评估和效果执行。

> **注意：** EffectManager 当前只处理 **INSTANT** 类别效果。MODIFIER 类别效果由 [ModifierRegistry] 接管，DURATION 类别待 Phase 4 实现。

## 用途

- 维护 INSTANT 效果类型 → 效果实例的注册表
- 在效果执行时动态构建运行时上下文（服务引用 + 触发数据）
- 统一评估效果触发条件（冷却、概率等）
- 支持堆叠执行（持有 n 个道具 → 执行 n 次）
- 支持复合效果（一个道具配置多个效果，依次执行）

## 依赖

| 依赖 | 说明 |
|------|------|
| `PropEffectBase` | 效果基类，所有效果实例必须继承它 |
| `PropData` | 道具定义数据类，提供 effects 配置列表（仅 INSTANT 道具） |
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
| `execute(prop_data: RefCounted, count: int, trigger_context: Dictionary)` | `void` | 执行道具的所有 INSTANT 效果（主入口） |

## 执行流程

```
EffectManager.execute(prop_data, count, trigger_context)
  ├── 1. 从 prop_data.effects 获取效果配置列表
  ├── 2. _build_context(trigger_context)
  │     ├── 调用 _context_provider() 获取服务引用 {"storage": ..., ...}
  │     └── 合并 trigger_context {"signal_name": ..., "crop_node": ..., ...}
  ├── 3. 遍历每个 effect_entry
  │     └── _execute_single_effect(effect_entry, count, context, prop_data)
  │         ├── 从 registry 查找 effect_instance
  │         ├── _evaluate_conditions()
  │         │   └── effect_instance.can_trigger(params, context)
  │         └── match effect_instance.get_category():
  │             ├── INSTANT  → effect.execute(params, context) × count
  │             ├── MODIFIER → effect.on_apply(params, context)   # 预留
  │             └── DURATION → effect.on_apply(params, context)   # 预留
```

## 运行时上下文结构

```gdscript
{
    # 服务引用（由 _context_provider 提供）
    "storage": Storage,

    # 触发数据（由 trigger_context 合并）
    "trigger_signal": StringName,
    "crop_node": Node2D,
    "grid_pos": Vector2i,
    "crop_id": String,
}
```

## 效果类别说明

| 类别 | 枚举值 | 执行行为 | 处理方式 | 示例 |
|------|--------|---------|---------|------|
| INSTANT | `EffectCategory.INSTANT` | 每次触发执行 `execute()` count 次 | EffectManager | sunshine_coin |
| MODIFIER | `EffectCategory.MODIFIER` | 持有期间持续生效，被动查询 | **ModifierRegistry** | jinkela |
| DURATION | `EffectCategory.DURATION` | 限时生效，on_apply → on_remove | 待 Phase 4 | — |

## 与 ModifierRegistry 的关系

```
PropManager
├── EffectManager        ← INSTANT 效果（event-driven）
│   └── execute()        → 事件发生 → 执行效果
│
└── ModifierRegistry     ← MODIFIER 效果（state-driven）
    └── calculate()      → 属性查询 → 返回聚合值
```

两者在 PropManager 中并行存在，互不干扰：
- INSTANT 道具通过 `trigger_signal` → EventBus → EffectManager 执行
- MODIFIER 道具通过 `prop_category: "modifier"` → ModifierRegistry 注册
- 外部系统（如 BaseTile）在需要时调用 `PropManager.query_modifier()` 查询聚合值

## 关联文档

- [7.1道具和buff系统.md](7.1道具和buff系统.md) — 系统设计总览
- [prop_manager.md](prop_manager.md) — PropManager API
- [modifier_registry.md](modifier_registry.md) — ModifierRegistry API
- [domain.md](domain.md) — Domain API
- [effects/prop_effect_base.md](effects/prop_effect_base.md) — 效果基类 API
- [effects/add_storage_item_effect.md](effects/add_storage_item_effect.md) — 添加物品效果
