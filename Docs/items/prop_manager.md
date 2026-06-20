# PropManager（道具管理器）

管理玩家持有道具的 Node，挂载在 Player 节点下。负责加载道具定义、维护道具持有状态、动态订阅 EventBus 信号并在触发时执行效果。

## 用途

- 管理玩家拥有的所有道具及其数量
- 从 `config/items/props/` 加载道具定义库
- 根据持有道具的 `trigger_signal` 动态连接/断开 EventBus 信号
- 信号触发时分发到对应道具的效果执行方法
- 提供增删查接口供调试命令、商店等系统调用

## 依赖

| 依赖 | 说明 |
|------|------|
| `EventBus` | Autoload，动态订阅/取消订阅信号 |
| `PropData` | RefCounted，道具定义数据类 |
| `Storage` | 通过 player group 查找，效果目标（如 `add_storage_item`） |
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
| `add_prop(prop_id: String)` | `bool` | 添加一个道具，首次添加时连接对应 EventBus 信号。返回 true 表示成功 |
| `remove_prop(prop_id: String)` | `bool` | 移除一个道具，数量归零时断开信号。返回 true 表示成功 |
| `has_prop(prop_id: String)` | `bool` | 检查是否持有该道具（数量 > 0） |
| `get_prop_count(prop_id: String)` | `int` | 获取道具当前持有数量 |
| `get_all_props()` | `Array[Dictionary]` | 获取所有持有道具的列表 `[{prop_id, count, data}]` |

## 数据结构

### props

```gdscript
{
    "sunshine_coin": 3,   # 持有 3 个阳光硬币
    # 每个成熟作物触发时获得 3 个 money（堆叠效果）
}
```

### prop_library（道具定义缓存）

```gdscript
{
    "sunshine_coin": <PropData#...>,  # PropData 实例
}
```

### _signal_bindings（信号 → 道具映射）

```gdscript
{
    "crop_matured": ["sunshine_coin"],  # crop_matured 信号触发时检查的道具列表
}
```

## 信号连接策略

PropManager 维护 `_signal_bindings` 字典，记录每个 EventBus 信号关联了哪些道具。

- **添加道具时**：如果该道具的 `trigger_signal` 尚无绑定，则连接到对应的 EventBus 信号
- **移除道具时**：如果该 `trigger_signal` 关联的道具列表为空，则断开信号连接
- **退出场景时**：`_exit_tree()` 中清理所有动态连接

这种策略避免了为未持有的道具浪费信号处理开销。

## 效果执行

`_execute_effect(prop_data: PropData, signal_args: Array)` 根据 `effect_type` 分发：

```gdscript
match prop_data.effect_type:
    "add_storage_item":
        # 从 signal_args 无需取值（crop_matured 只传递事件通知）
        # 直接使用 effect_params 中的 item_id 和 amount
        var item_id: String = prop_data.effect_params["item_id"]
        var amount: float = prop_data.effect_params["amount"]
        _get_storage().add_item(item_id, amount)
```

当前仅实现 `add_storage_item`，后续扩展通过添加新的 match 分支。

## 关联文档

- [7.1道具和buff系统.md](7.1道具和buff系统.md) — 系统设计总览
- [props/sunshine_coin.md](props/sunshine_coin.md) — 阳光硬币
- [Docs/storage/storage.md](../storage/storage.md) — Storage API
- [Docs/autoload/event_bus.md](../autoload/event_bus.md) — EventBus 信号
