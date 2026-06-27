# TickSystem

Autoload 全局单例。管理游戏逻辑时钟，使用独立线程运行 tick 循环，与画面渲染分离，以固定间隔驱动所有逻辑系统更新。

## 用途

- 提供帧率无关的定时逻辑更新
- 各游戏系统监听 `tick_elapsed` 信号，在回调中执行逻辑（作物生长、单位移动、Buff 计时等）
- 可暂停/恢复，支持运行时修改间隔
- **内置性能仪表**：追踪每次 tick 的计算耗时，支持实时/1秒平均/5秒最大值

## 架构

| 组件 | 线程 | 说明 |
|------|------|------|
| 计时循环 | 工作线程 | 以 `tick_interval` 为周期休眠，到期后通过 `call_deferred` 调度主线程处理 |
| 信号发射 | 主线程 | `_on_tick_deferred` 中发射 `tick_elapsed`，所有监听器在主线程执行 |
| 背压控制 | 跨线程 | `_tick_pending` 标志 + `Mutex`，防止 tick 在主线程堆积 |
| 性能仪表 | 主线程 | 环形缓冲区记录每次 tick 耗时，实时计算统计指标 |

## 依赖

- 无外部依赖
- 使用 Godot 内置 `Thread`、`Mutex`、`OS.delay_msec`、`Time.get_ticks_usec`

## 公开 API

### 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `tick_interval` | `float` | `0.05` | 当前 tick 间隔（秒） |
| `auto_start` | `bool` | `false` | 启动时是否自动开始 tick（@export）。设为 `false`，由 [GameRoot](../../scripts/game/game_root.gd) 在游戏场景加载后显式调用 `start()` |
| `tick_computation_time_ms` | `float` | `0.0` | **性能仪表**：上一次 tick 计算耗时（毫秒） |
| `tick_avg_time_ms` | `float` | `0.0` | **性能仪表**：最近 1 秒内平均耗时（毫秒） |
| `tick_max_time_5s_ms` | `float` | `0.0` | **性能仪表**：最近 5 秒内最大耗时（毫秒） |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `start()` | `void` | 启动 tick 循环（创建并运行工作线程） |
| `stop()` | `void` | 停止 tick 循环并等待线程结束 |
| `pause()` | `void` | 暂停 tick（线程继续运行但不触发信号） |
| `resume()` | `void` | 恢复 tick |
| `set_tick_interval(interval: float)` | `void` | 修改间隔，范围 0.01~1.0 秒 |
| `get_tick_count()` | `int` | 返回已执行 tick 总数 |
| `is_paused()` | `bool` | 返回是否暂停 |

### 信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `tick_elapsed` | `delta: float` | 每次 tick 触发，传递实际间隔（秒）。在主线程发射 |

## 常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `DEFAULT_TICK_INTERVAL` | `0.05` | 默认 50ms，即每秒 20 tick |
| `MIN_TICK_INTERVAL` | `0.01` | 最小 10ms |
| `MAX_TICK_INTERVAL` | `1.0` | 最大 1 秒 |
| `AVG_WINDOW_SECONDS` | `1.0` | 平均耗时滑动窗口大小 |
| `MAX_WINDOW_SECONDS` | `5.0` | 最大耗时滑动窗口大小 |
| `THREAD_SLEEP_STEP_MSEC` | `10` | 线程休眠步长（毫秒） |

## 背压机制

当一次 tick 的处理时间超过 `tick_interval` 时，下一次线程循环将检测到 `_tick_pending` 仍为 `true`，自动跳过本次 tick。这避免了 `call_deferred` 调度堆积导致的级联帧丢失。被跳过的 tick 不会补发。

## 性能仪表使用

```gdscript
# 在 DebugOverlay 中显示 tick 性能
DebugOverlay.set_entry("tick_ms", "%.2f" % TickSystem.tick_computation_time_ms)
DebugOverlay.set_entry("tick_avg_1s", "%.2f" % TickSystem.tick_avg_time_ms)
DebugOverlay.set_entry("tick_max_5s", "%.2f" % TickSystem.tick_max_time_5s_ms)
```

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
