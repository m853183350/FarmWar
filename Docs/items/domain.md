# Domain（领域）

维护特定领域内所有活跃 MODIFIER 修饰器的有序链。每个 Domain 实例管理一个领域（如 tile、player、warehouse）内的所有生效修饰器，按优先级排序后形成计算链，供游戏系统查询属性最终值。

## 用途

- 按领域分组管理修饰器（一个 Domain = 一个领域，如 "tile"）
- 维护修饰器的有序链（按 priority 升序）
- 提供 `calculate()` 方法，遍历链中匹配 stat 的修饰器，按标签或自定义 Callable 计算聚合值
- 支持 `target_filter` 过滤 — 修饰器可限制生效范围（如只对 farmland 生效）

## 依赖

| 依赖 | 说明 |
|------|------|
| 无外部依赖 | 纯 RefCounted 类，不依赖 Node 或 Autoload |

## 公开 API

### 变量

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `domain_name` | `String` | `""` | 领域名称，如 "tile"、"player"、"warehouse" |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `add_modifier(modifier_data: Dictionary, prop_id: String, count: int)` | `void` | 添加修饰器到链中。`value` 自动乘以 `count` 实现堆叠 |
| `remove_modifier(prop_id: String)` | `void` | 移除指定道具的所有修饰器条目 |
| `calculate(stat_name: String, base_value: float, context: Dictionary = {})` | `float` | 计算指定属性的聚合值，仅 target_filter 匹配 context 的修饰器参与计算 |
| `sort_chain()` | `void` | 按 priority 升序重排修饰器链 |
| `get_chain()` | `Array[Dictionary]` | 获取链中所有修饰器（用于调试） |

## 修饰器链条目结构

```gdscript
{
    "prop_id": "jinkela",         # 道具 ID
    "stat": "fertility_modifier_1", # 影响的属性名
    "value": 0.6,                 # 实际值（modifier_data.value × count）
    "priority": 100,              # 排序优先级（越小越先计算）
    "tags": ["flat"],             # 计算标签
    "calculator": Callable(),     # 自定义计算函数（可选）
    "target_filter": {"tile_type": "farmland"},  # 生效范围过滤
}
```

## 标签计算规则

按优先级顺序遍历链中匹配 stat 的修饰器，依次应用：

| 标签 | 计算方式 | 说明 |
|------|---------|------|
| `flat` | `result += value` | 固定值加成，如 `fertility_modifier_1` |
| `additive` | `result += base_value × value` | 基于基础值的叠加，如 `yield + 20%` |
| `multiplicative` | `result *= 1.0 + value` | 乘算，如 `fertility_multiplier` |
| `override` | `result = max(result, value)` | 取最高值 |

自定义 `calculator: Callable` 优先级高于标签。

## target_filter 匹配逻辑

```gdscript
func _matches_filter(modifier: Dictionary, context: Dictionary) -> bool:
    # 无 filter → 匹配所有
    # 无 context → 匹配所有（向后兼容）
    # 否则 target_filter 的所有键值对必须与 context 完全一致
```

调用者通过 `calculate()` 的 `context` 参数传入当前对象的属性（如 `{"tile_type": "farmland"}`），Domain 自动过滤不匹配的修饰器。

## 示例

```gdscript
var domain := Domain.new()
domain.domain_name = "tile"

# 注册两个修饰器
domain.add_modifier(
    {"stat": "fertility_modifier_1", "value": 0.3, "priority": 100, "tags": ["flat"], "target_filter": {"tile_type": "farmland"}},
    "jinkela", 2  # count = 2，实际 value = 0.6
)
domain.add_modifier(
    {"stat": "fertility_multiplier", "value": 0.15, "priority": 50, "tags": ["multiplicative"]},
    "moonlight_powder", 1
)

# 查询 farmland 地块的 fertility_modifier_1
var mod1: float = domain.calculate("fertility_modifier_1", 0.0, {"tile_type": "farmland"})
# → 0.0 + 0.6 = 0.6

# 查询 dirt 地块的 fertility_modifier_1（不匹配 target_filter）
var mod1_dirt: float = domain.calculate("fertility_modifier_1", 0.0, {"tile_type": "dirt"})
# → 0.0（jinkela 的 target_filter 不匹配，跳过）

# 查询 fertility_multiplier（无 target_filter，对所有地块生效）
var mult: float = domain.calculate("fertility_multiplier", 1.0, {"tile_type": "farmland"})
# → 1.0 × (1.0 + 0.15) = 1.15
```

## 关联文档

- [modifier_registry.md](modifier_registry.md) — ModifierRegistry API
- [prop_manager.md](prop_manager.md) — PropManager API（持有 ModifierRegistry）
- [0624效果系统优化方案.md](../0624效果系统优化方案.md) — 系统设计文档
