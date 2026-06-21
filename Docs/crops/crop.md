# Crop（作物基类）

所有作物（小麦、水稻等）的抽象基类，定义生长阶段系统、TickSystem 驱动、视觉帧切换和收获接口。
内置环境修正系统（水分/肥力/温度），自动从所在地块读取属性并计算生长速度和产量修正值。

> 所有作物脚本都必须继承本类。参考 `BaseTile` 的抽象基类设计模式。

## 用途

- 统一作物的生命周期管理（种植 → 生长 → 成熟 → 收获/枯萎）
- 通过 TickSystem 驱动生长进度，与帧率解耦
- 通过 `region_rect` 切换 sprite sheet 帧实现阶段视觉变化
- 自动读取所在地块的水分、肥力、温度属性，计算环境影响
- 提供可覆写的阶段数据、收获产物和土壤需求接口
- 预留独立修正值接口，供道具/Buff 系统扩展

## 依赖

| 依赖 | 说明 |
|------|------|
| `TickSystem` | Autoload，每 tick 推进生长进度 |
| `resources/materials/crops/crops1x1.tres` | 作物通用 ShaderMaterial |
| `BaseTile` | 地块引用（通过 `plant()` 设置），提供水分/肥力/温度属性 |

## 公开 API

### 信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `stage_changed` | `old_stage: int, new_stage: int` | 生长阶段变化 |
| `harvested` | `yields: Array` | 作物被收获，yields 为产物数组 |
| `withered` | — | 作物枯萎/死亡 |

### EventBus 信号（作物在关键阶段发出）

作物在生长和收获过程中通过 EventBus 广播事件，供 FarmlandManager 等其他系统监听：

| EventBus 信号 | 发出时机 | 参数 |
|------|---------|------|
| `crop_stage_changed` | `_advance_stage()` 每次阶段推进 | `crop_node, grid_pos, crop_id, old_stage, new_stage, is_mature` |
| `crop_matured` | 进入最终阶段（`is_mature() == true`） | `crop_node, grid_pos, crop_id` |
| `crop_harvested` | `harvest()` 执行完成 | `yields, crop_id` |

> 这些并非 Crop 自身定义的信号，而是通过 `EventBus.emit()` 广播的全局事件。FarmlandManager 监听 `crop_matured` 自动创建收获任务，监听 `crop_harvested` 作为兜底实现手动收获后自动补种。

### 变量

#### 状态变量

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `growth_stage` | `int` | `0` | 当前生长阶段索引 |
| `growth_progress` | `float` | `0.0` | 当前阶段内进度 (0.0~1.0) |
| `health` | `float` | `1.0` | 生命值 (0.0=死亡) |
| `tile` | `Node2D` | `null` | 所在地块引用 |
| `last_harvest_yields` | `Array` | `[]` | 最近一次收获的产物列表 |

#### 环境修正值变量

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `moisture_modifier` | `float` | `1.0` | 湿度修正值。由地块湿度和作物土壤需求计算 |
| `temperature_modifier` | `float` | `1.0` | 温度修正值。由地块温度和作物温度需求计算 |
| `fertility_modifier` | `float` | `1.0` | 肥力修正值 = sqrt(肥力系数 × 地块肥力) |
| `independent_speed_modifier` | `float` | `1.0` | 独立速度修正值。供道具/Buff 系统外部设置 |
| `independent_yield_modifier` | `float` | `1.0` | 独立产量修正值。供道具/Buff 系统外部设置 |
| `speed_modifier` | `float` | `1.0` | 综合速度修正值 = 湿度 × 温度 × 独立速度 |
| `yield_modifier` | `float` | `1.0` | 综合产量修正值 = 1 × 肥力 × 独立产量 |

### 常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `MOISTURE_DECAY_STRENGTH` | `2.0` | 湿度衰减强度（过湿时倒数衰减系数） |
| `FRAME_WIDTH` | `8` | Sprite sheet 每帧宽度 |
| `FRAME_HEIGHT` | `16` | Sprite sheet 每帧高度 |

### 方法

#### 生命周期

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `plant(target_tile)` | `void` | 放置到地块上，注册为内容物，连接地块信号并首次计算修正值 |
| `harvest()` | `Array` | 收获作物，返回产量修正后的产物数组，释放自身 |
| `destroy()` | `void` | 强制销毁（无产出） |

#### 查询

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `is_mature()` | `bool` | 是否处于可收获的成熟阶段 |
| `get_growth_speed()` | `float` | 获取当前综合速度修正值 |
| `get_yield_multiplier()` | `float` | 获取当前综合产量倍率 |

#### 外部注入（供道具/Buff 系统）

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `set_independent_speed_modifier(value)` | `void` | 设置独立速度修正值，自动重算综合值 |
| `set_independent_yield_modifier(value)` | `void` | 设置独立产量修正值，自动重算综合值 |

### 子类必须覆写

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `_get_crop_info()` | `Dictionary` | 作物身份信息 |
| `_get_stage_data()` | `Array` | 生长阶段数据 |
| `_get_harvest_yields()` | `Array` | 收获产物定义（base_amount 为修正前基础值） |
| `_get_soil_requirements()` | `Dictionary` | 土壤需求（水分/温度/肥力参数） |

### 土壤需求格式

`_get_soil_requirements()` 返回的 Dictionary 必须包含：

| 键 | 类型 | 说明 |
|-----|------|------|
| `min_moisture` | `float` | 最佳湿度下限。低于此值时生长速度线性递减 |
| `max_moisture` | `float` | 最佳湿度上限。高于此值时生长速度倒数衰减 |
| `min_temperature` | `float` | 最佳温度下限（摄氏度）。低于此值时速度线性递减 |
| `max_temperature` | `float` | 最佳温度上限（摄氏度）。高于此值时速度线性递减 |
| `temperature_tolerance` | `float` | 温度耐受力（°C）。超出最佳范围这么多度后速度归零 |
| `fertility_factor` | `float` | 肥力系数。与地块肥力相乘后开方，影响产量 |

示例（小麦 Tier 1）：
```gdscript
{
	"min_moisture": 0.4,
	"max_moisture": 1.2,
	"min_temperature": 10.0,
	"max_temperature": 30.0,
	"temperature_tolerance": 10.0,
	"fertility_factor": 1.0,
}
```

### 阶段数据格式

每个阶段为 Dictionary：

| 键 | 类型 | 说明 |
|-----|------|------|
| `name` | `String` | 阶段名称 |
| `tick_duration` | `int` | 持续 tick 数（-1 = 最终阶段）。实际耗时受 `speed_modifier` 影响 |
| `frame_x` | `int` | sprite sheet 中的 x 偏移（px） |
| `passable` | `bool` | 此阶段是否可通行 |

### 产物数据格式

```gdscript
{ "item_id": "wheat_grain", "base_amount": 0.1, "probability": 1.0 }
```

实际产出量 = `base_amount` × `yield_modifier`（含肥力和独立产量修正）。

## 环境修正值计算

作物每 tick 重新计算环境修正值。计算公式见 [2.1作物系统.md](2.1作物系统.md)：

```
湿度修正值 = 1（最佳区间内）/ 干旱线性递减 / 过湿倒数衰减
肥力修正值 = sqrt(作物肥力系数 × 地块肥力)
温度修正值 = 1（最佳区间内）/ 超限后线性递减至耐受温度处归零
速度修正值 = 湿度修正值 × 温度修正值 × 独立速度修正值
产量修正值 = 1 × 肥力修正值 × 独立产量修正值
```

修正值计算在以下时机触发：
1. 每 tick（`_on_tick`）自动重算
2. 地块数据变更时（监听 `BaseTile.tile_data_changed` 信号）
3. 外部调用 `set_independent_speed_modifier()` / `set_independent_yield_modifier()` 时

## 生长流程

```
plant(tile) ──→ growth_stage=0, 连接到 TickSystem, 连接地块信号
    │               首次计算环境修正值
    ▼
TickSystem.tick_elapsed ──→ _on_tick()
    │
    ├── _recalc_modifiers()（从地块读取属性，计算 speed_modifier）
    ├── growth_progress += speed_modifier / duration
    │
    └── progress >= 1.0 ──→ _advance_stage()
            │
            ├── growth_stage += 1
            ├── _apply_stage_visuals()（更新 region_rect）
            ├── update_z_index()（阶段变化可能导致渲染层级改变）
            ├── stage_changed.emit(old, new)
            │
            ├── EventBus.crop_stage_changed.emit(self, grid_pos, crop_id, old, new, is_mature)
            │
            └── 若为最终阶段 (is_mature==true)：
                    ├── EventBus.crop_matured.emit(self, grid_pos, crop_id)
                    └── 停止生长，等待 harvest()
                            │
                            ▼
                      harvest() → _roll_yields()（base_amount × yield_modifier）
                                → EventBus.crop_harvested.emit(yields, crop_id)
```

## 关联文档

- [2.1作物系统.md](2.1作物系统.md) — 作物系统总览与环境修正公式
- [2.2小麦.md](2.2小麦.md) — WheatTier1 需求文档
- [Docs/world/base_tile.md](../world/base_tile.md) — BaseTile 基类（提供环境属性访问器）
- [Docs/地块系统/1.1地块系统.md](../地块系统/1.1地块系统.md) — 地块水分/肥力/温度系统
- [Docs/autoload/material_manager.md](../autoload/material_manager.md) — 材质系统
- [../autoload/event_bus.md](../autoload/event_bus.md) — EventBus（crop_stage_changed、crop_matured、crop_harvested）
- [../autoload/farmland_manager.md](../autoload/farmland_manager.md) — FarmlandManager（监听 crop_matured 驱动自动循环）
