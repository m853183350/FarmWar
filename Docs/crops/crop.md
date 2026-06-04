# Crop（作物基类）

所有作物（小麦、水稻等）的抽象基类，定义生长阶段系统、TickSystem 驱动、视觉帧切换和收获接口。

> 所有作物脚本都必须继承本类。参考 `BaseTile` 的抽象基类设计模式。

## 用途

- 统一作物的生命周期管理（种植 → 生长 → 成熟 → 收获/枯萎）
- 通过 TickSystem 驱动生长进度，与帧率解耦
- 通过 `region_rect` 切换 sprite sheet 帧实现阶段视觉变化
- 提供可覆写的阶段数据和收获产物接口

## 依赖

| 依赖 | 说明 |
|------|------|
| `TickSystem` | Autoload，每 tick 推进生长进度 |
| `resources/materials/crops/crops1x1.tres` | 作物通用 ShaderMaterial |
| `BaseTile` | 地块引用（通过 `plant()` 设置） |

## 公开 API

### 信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `stage_changed` | `old_stage: int, new_stage: int` | 生长阶段变化 |
| `harvested` | `yields: Array` | 作物被收获，yields 为产物数组 |
| `withered` | — | 作物枯萎/死亡 |

### 变量

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `growth_stage` | `int` | `0` | 当前生长阶段索引 |
| `growth_progress` | `float` | `0.0` | 当前阶段内进度 (0.0~1.0) |
| `health` | `float` | `1.0` | 生命值 (0.0=死亡) |
| `tile` | `Node2D` | `null` | 所在地块引用 |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `plant(target_tile)` | `void` | 放置到地块上，注册为内容物 |
| `harvest()` | `Array` | 收获作物，返回产物数组，释放自身 |
| `is_mature()` | `bool` | 是否处于可收获的成熟阶段 |
| `destroy()` | `void` | 强制销毁（无产出） |

### 子类必须覆写

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `_get_crop_info()` | `Dictionary` | 作物身份信息 |
| `_get_stage_data()` | `Array` | 生长阶段数据 |
| `_get_harvest_yields()` | `Array` | 收获产物定义 |

### 阶段数据格式

每个阶段为 Dictionary：

| 键 | 类型 | 说明 |
|-----|------|------|
| `name` | `String` | 阶段名称 |
| `tick_duration` | `int` | 持续 tick 数（-1 = 最终阶段） |
| `frame_x` | `int` | sprite sheet 中的 x 偏移（px） |
| `passable` | `bool` | 此阶段是否可通行 |

### 产物数据格式

```gdscript
{ "item_id": "wheat_grain", "base_amount": 0.1, "probability": 1.0 }
```

## 生长流程

```
plant(tile) ──→ growth_stage=0, 连接到 TickSystem
    │
    ▼
TickSystem.tick_elapsed ──→ _on_tick()
    │
    ├── growth_progress += 1/duration
    │
    └── progress >= 1.0 ──→ _advance_stage()
            │
            ├── growth_stage += 1
            ├── _apply_stage_visuals()（更新 region_rect）
            ├── stage_changed.emit(old, new)
            │
            └── 若为最终阶段 → 停止生长，等待 harvest()
```

## 关联文档

- [2.1作物系统.md](2.1作物系统.md) — 作物系统总览
- [2.2小麦.md](2.2小麦.md) — WheatTier1 需求文档
- [Docs/world/base_tile.md](../world/base_tile.md) — BaseTile 基类（设计参考）
- [Docs/autoload/material_manager.md](../autoload/material_manager.md) — 材质系统
