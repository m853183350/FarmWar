# TickCounterLabel

挂载在 `Label` 节点上，监听 `TickSystem.tick_elapsed` 信号，每次 tick 计数 +1 并更新显示文本。

## 用途

- 验证 Tick 系统是否正常工作
- 点击地块时由 `CameraController` 创建实例，显示从 0 开始的递增数字
- 在 `_exit_tree` 时自动断开信号，防止内存泄漏

## 依赖

| 依赖 | 说明 |
|------|------|
| `TickSystem` | 监听 `tick_elapsed` 信号 |

## 公开 API

无公开方法或属性。脚本完整封装，创建后自动运行。

### 内部变量

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `_count` | `int` | `0` | 当前计数值 |

### 信号连接

| 信号 | 回调 | 时机 |
|------|------|------|
| `TickSystem.tick_elapsed` | `_on_tick(delta)` | 每个 tick，计数值 +1 |
| — | `_exit_tree()` | 节点移除时断开连接 |

## 使用示例

```gdscript
# 方式一：由 CameraController 自动创建（点击地块）
# 无需手动代码

# 方式二：手动创建计数标签
var label := Label.new()
label.set_script(preload("res://scripts/ui/tick_counter_label.gd"))
label.position = Vector2(32, 24)
label.z_index = 100
some_node.add_child(label)
# 标签自动连接 TickSystem，从 0 开始计数
```

## 外观

- 白色字体 + 黑色描边
- 字号 14
- z_index = 100（渲染在 tile 上层）
- 位置：地块中心偏上

## 关联文档

- [Docs/autoload/tick_system.md](../autoload/tick_system.md)
- [Docs/world/camera_controller.md](camera_controller.md)
