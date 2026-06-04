# CameraController

挂载在 `world` 场景的 `Camera2D` 子节点上，提供鼠标驱动的视角控制。

## 用途

- **边缘滚动**：鼠标移到窗口边缘时平滑移动摄像机
- **滚轮缩放**：鼠标滚轮放大/缩小，带平滑过渡
- **地块点击**：左键点击地块生成 tick 计数器标签

## 依赖

| 依赖 | 说明 |
|------|------|
| `res://scripts/ui/tick_counter_label.gd` | 点击地块时创建的计数标签脚本 |
| `TickSystem` | 行间依赖，具体由 TickCounterLabel 使用 |

## 公开 API

### @export 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `edge_margin` | `int` | `20` | 触发边缘滚动的像素宽度 |
| `max_scroll_speed` | `float` | `600.0` | 边缘滚动最大速度（像素/秒） |
| `scroll_acceleration` | `float` | `2000.0` | 滚动加速度（像素/秒²） |
| `min_zoom` | `float` | `0.3` | 最小缩放值 |
| `max_zoom` | `float` | `4.0` | 最大缩放值 |
| `zoom_step` | `float` | `0.1` | 每格滚轮缩放量 |
| `zoom_smoothness` | `float` | `10.0` | 缩放平滑系数（越大越快） |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `set_tile_size(size: int)` | `void` | 设置地块像素大小（从 TerrainGenerator 同步） |

## 操作说明

| 操作 | 效果 |
|------|------|
| 鼠标移到窗口边缘 20px | 摄像机向该方向平滑移动 |
| 鼠标滚轮 ↑ | 放大（最大 4.0x） |
| 鼠标滚轮 ↓ | 缩小（最小 0.3x） |
| 左键点击地块 | 在地块中心创建计数标签 |

## 工作原理

### 边缘滚动

每帧检查鼠标位置是否在边缘区域内 → 计算目标速度 → `move_toward` 平滑过渡。滚动速度除以 `zoom` 值，确保放大后滚动更精细。

### 缩放

每帧 `lerpf` 从当前 zoom 向目标值插值，接近目标时直接设为精确值避免抖动。

### 地块点击

屏幕坐标 → `get_global_mouse_position()` 转世界坐标 → 除以 `tile_size` 得网格坐标 → 查找 `tile_X_Y` 节点 → 实例化 Label 并挂载 `tick_counter_label.gd` 脚本。

## 使用示例

```gdscript
# 在编辑器中调整 Camera2D 节点的 @export 属性即可

# 运行时动态调整
var cam: Camera2D = $Camera2D
cam.edge_margin = 30
cam.max_scroll_speed = 800.0
cam.min_zoom = 0.2
```

## 关联文档

- [Docs/ui/tick_counter_label.md](../ui/tick_counter_label.md)
- [Docs/整体设计.md](../整体设计.md) — 底层逻辑章节
