# EventBus

Autoload 全局单例。全局事件总线，用于各个游戏系统之间的解耦通信。

## 用途

- 替代直接的跨系统引用，通过信号实现发布-订阅模式
- 系统 A 发出事件，系统 B/C/D 监听，互不依赖
- 降低系统间耦合度，便于测试和维护

## 依赖

- 无外部依赖

## 公开 API

### 信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `terrain_generated` | — | 地形生成完成，地图可用 |
| `game_state_changed` | `new_state: StringName` | 游戏状态变化（如 `paused`、`playing`） |
| `tile_clicked` | `tile: Node2D` | 地块被点击，传递地块节点引用 |
| `tiles_selected` | `tiles: Array` | 地块框选完成，传递网格坐标数组 |
| `tile_action_triggered` | `action: StringName, tiles: Array` | 地块操作菜单项被点击（action: "plow"/"dig"） |
| `tile_action_completed` | `action: StringName, tiles: Array, count: int` | 地块操作完成，count 为成功转化数 |
| `debug_command_executed` | `command: String` | 调试指令被执行 |

## 使用示例

```gdscript
# 发出事件
EventBus.terrain_generated.emit()

# 监听事件
func _ready() -> void:
    EventBus.game_state_changed.connect(_on_game_state_changed)

func _on_game_state_changed(new_state: StringName) -> void:
    match new_state:
        &"paused":
            _pause_all_units()
        &"playing":
            _resume_all_units()

# 清理（如果需要）
func _exit_tree() -> void:
    EventBus.game_state_changed.disconnect(_on_game_state_changed)
```

## 扩展指南

新增跨系统事件时，在此文件添加信号声明即可，无需修改其他代码：

```gdscript
## 作物收获完成。
signal crop_harvested(crop_type: int, amount: int)
```

## 关联文档

- [Docs/整体设计.md](../整体设计.md)
- [Docs/autoload/tick_system.md](tick_system.md)
