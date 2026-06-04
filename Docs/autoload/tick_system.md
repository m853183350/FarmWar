# TickSystem

Autoload 全局单例。管理游戏逻辑时钟，与画面渲染分离，以固定间隔驱动所有逻辑系统更新。

## 用途

- 提供帧率无关的定时逻辑更新
- 各游戏系统监听 `tick_elapsed` 信号，在回调中执行逻辑（作物生长、单位移动、Buff 计时等）
- 可暂停/恢复，支持运行时修改间隔

## 依赖

- 无外部依赖
- 使用 Godot 内置 `Timer` 节点

## 公开 API

### 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `tick_interval` | `float` | `0.05` | 当前 tick 间隔（秒） |
| `auto_start` | `bool` | `true` | 启动时是否自动开始 tick（@export） |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `start()` | `void` | 启动 tick 循环 |
| `stop()` | `void` | 停止 tick 循环 |
| `pause()` | `void` | 暂停 tick（计时器继续但不触发信号） |
| `resume()` | `void` | 恢复 tick |
| `set_tick_interval(interval: float)` | `void` | 修改间隔，范围 0.01~1.0 秒 |
| `get_tick_count()` | `int` | 返回已执行 tick 总数 |
| `is_paused()` | `bool` | 返回是否暂停 |

### 信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `tick_elapsed` | `delta: float` | 每次 tick 触发，传递实际间隔（秒） |

## 常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `DEFAULT_TICK_INTERVAL` | `0.05` | 默认 50ms，即每秒 20 tick |
| `MIN_TICK_INTERVAL` | `0.01` | 最小 10ms |
| `MAX_TICK_INTERVAL` | `1.0` | 最大 1 秒 |

## 使用示例

```gdscript
# 监听 tick 信号
func _ready() -> void:
    TickSystem.tick_elapsed.connect(_on_tick)

func _on_tick(delta: float) -> void:
    _growth_timer += delta
    if _growth_timer >= 1.0:
        _advance_growth_stage()

# 运行时加速游戏
TickSystem.set_tick_interval(0.025)  # 40 tick/s

# 暂停/恢复
TickSystem.pause()
TickSystem.resume()
```

## 关联文档

- [Docs/整体设计.md](../整体设计.md) — 底层逻辑章节
- [Docs/代码规范.md](../代码规范.md)
