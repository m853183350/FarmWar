# PropManager（道具管理器）

管理玩家持有道具的 Node，挂载在 Player 节点下。负责加载道具定义、维护道具持有状态、根据 `prop_category` 分别路由到 [EffectManager]（INSTANT 效果）或 [ModifierRegistry]（MODIFIER 效果）。

## 用途

- 管理玩家拥有的所有道具及其数量
- 从 `config/items/props/` 加载道具定义库
- 根据 `prop_category` 分派：
  - **INSTANT** 道具（如 sunshine_coin）：动态连接/断开 EventBus 信号，触发时委托 EffectManager 执行
  - **MODIFIER** 道具（如 jinkela）：注册/注销到 ModifierRegistry，地块等系统被动查询
- 提供 `query_modifier()` 公共 API 供外部系统查询聚合修饰值
- 修饰器变更时通过 EventBus 广播 `tile_modifiers_changed` 信号
- 提供增删查接口供调试命令、商店等系统调用

## 依赖

| 依赖 | 说明 |
|------|------|
| `EventBus` | Autoload，动态订阅/取消订阅信号；发射 `tile_modifiers_changed` |
| `PropData` | RefCounted，道具定义数据类（含 `prop_category`、`modifier` 等新字段） |
| `EffectManager` | RefCounted，处理 INSTANT 效果注册和执行 |
| `ModifierRegistry` | RefCounted，管理 MODIFIER 效果的领域计算链 |
| `Storage` | 通过上下文提供器注入 EffectManager |
| `config/items/props/` | 道具定义 JSON 配置文件目录 |

## 公开 API

### 信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `prop_added` | `prop_id: String, count: int` | 道具数量增加时发出 |
| `prop_removed` | `prop_id: String, count: int` | 道具数量减少时发出 |

### 变量

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `props` | `Dictionary` | `{}` | 运行时道具持有量 `{prop_id: int_count}` |
| `prop_library` | `Dictionary` | `{}` | 道具定义缓存 `{prop_id: PropData}` |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `add_prop(prop_id: String)` | `bool` | 添加道具。按 prop_category 分派：INSTANT → 连接信号；MODIFIER → 注册到 ModifierRegistry |
| `remove_prop(prop_id: String)` | `bool` | 移除道具。数量归零时：INSTANT → 断开信号；MODIFIER → 注销修饰器 |
| `has_prop(prop_id: String)` | `bool` | 检查是否持有该道具（数量 > 0） |
| `get_prop_count(prop_id: String)` | `int` | 获取道具当前持有数量 |
| `get_all_props()` | `Array[Dictionary]` | 获取所有持有道具的列表 `[{prop_id, count, data}]` |
| `query_modifier(domain_name: String, stat_name: String, base_value: float, context: Dictionary = {})` | `float` | **新增** — 查询 MODIFIER 效果的聚合值，供外部系统（如 BaseTile）调用 |

## 架构

```
PropManager (Node, 挂 Player 下)
├── props: {prop_id: count}
├── prop_library: {prop_id: PropData}
├── _signal_bindings          ← INSTANT 道具的信号映射
│
├── _effect_manager: EffectManager   ← INSTANT 效果 (不变)
│   ├── registry: {effect_type: PropEffectBase}
│   └── execute(prop_data, count, trigger_context)
│
└── _modifier_registry: ModifierRegistry  ← MODIFIER 效果 (新增)
    ├── _domains: {"tile": Domain, ...}
    ├── register_modifier(...)
    ├── unregister_modifier(...)
    └── calculate(domain, stat, base, context) → float
```

## 道具类别路由

`add_prop()` 和 `remove_prop()` 根据 `PropData.prop_category` 分派：

| prop_category | 添加时 | 移除时 | 示例 |
|---------------|--------|--------|------|
| `"instant"` | `_ensure_signal_connected()` → 连接 EventBus | `_remove_signal_binding()` → 断开 EventBus | sunshine_coin |
| `"modifier"` | `_apply_modifier()` → ModifierRegistry.register_modifier() | `_remove_modifier()` → ModifierRegistry.unregister_modifier() | jinkela |
| `"duration"` | 预留（Phase 4） | 预留 | — |

### MODIFIER 增删逻辑

```gdscript
func add_prop(prop_id: String) -> bool:
    # ... 检查上限、增加计数 ...
    match data.get("prop_category"):
        "modifier":
            if current_count == 0:
                _apply_modifier(data, new_count)   # 首次：注册
            else:
                _update_modifier(data, new_count)  # 叠加：注销→重新注册新值
        "instant", _:
            # 现有逻辑：连接信号 ...

func remove_prop(prop_id: String) -> bool:
    # ...
    match data.get("prop_category"):
        "modifier":
            if new_count <= 0:
                _remove_modifier(prop_id)          # 归零：注销
            else:
                _update_modifier(data, new_count)  # 减少：更新值
```

每次修饰器变更后调用 `_notify_modifiers_changed()` 发射 `EventBus.tile_modifiers_changed` 信号，触发地块重算。

## 上下文服务（当前状态）

上下文提供器目前返回 `{storage: Storage}`。未来（Phase 2）将改为注册模式：

```gdscript
# 注册模式（Phase 2 实现）
func register_context_service(service_name: String, service_ref: Variant) -> void:
    _context_services[service_name] = service_ref

func _provide_effect_context() -> Dictionary:
    return _context_services.duplicate()
```

## Group 注册

PropManager 在 `_ready()` 中通过 `add_to_group("prop_manager")` 注册自身，外部系统（如 BaseTile）通过 `get_tree().get_first_node_in_group("prop_manager")` 查找，无需硬编码路径。

## 调试

F3 调试面板中 PropManager 条目显示：
- 持有道具列表及数量
- 信号绑定状态
- EffectManager 注册效果
- Storage 状态
- **ModifierRegistry 活跃修饰器列表**（新增）

## 关联文档

- [7.1道具和buff系统.md](7.1道具和buff系统.md) — 系统设计总览
- [effect_manager.md](effect_manager.md) — EffectManager API
- [modifier_registry.md](modifier_registry.md) — ModifierRegistry API
- [domain.md](domain.md) — Domain API
- [props/sunshine_coin.md](props/sunshine_coin.md) — 阳光硬币（INSTANT 示例）
- [props/jinkela.md](props/jinkela.md) — 金坷垃（MODIFIER 示例）
- [Docs/autoload/event_bus.md](../autoload/event_bus.md) — EventBus 信号
