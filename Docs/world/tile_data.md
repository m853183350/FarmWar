# TileInfo（原 TileData）

地块数据资源类，描述单个地块的类型、通行性和可建造性等属性。

> 注意：`class_name` 为 `TileInfo`，文件名仍为 `tile_data.gd`。因 Godot 4.x 已有原生类 `TileData`，故改名避免冲突。

## 用途

- 作为地块的数据载体，由 `TerrainGenerator` 在生成地形时为每个地块实例创建
- 通过 `node.set_meta("tile_data", data)` 附加到 tile 节点上
- 供其他系统（建筑、作物、战斗）查询地块属性

## 依赖

- 无外部依赖（纯 Resource 数据类）

## 公开 API

### 枚举

| 枚举 | 值 | 说明 |
|------|-----|------|
| `TileType.DIRT` | — | 土质平地，可耕种 |
| `TileType.STONE` | — | 石质平地，清理后可建造 |
| `TileType.OCEAN` | — | 水域，不可通行 |
| `TileType.SLOPE` | — | 斜坡（预留） |
| `TileType.ROUGH` | — | 崎岖地块（预留） |
| `TileType.SPECIAL` | — | 特殊地块（预留） |

### 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `grid_position` | `Vector2i` | `(0, 0)` | 网格坐标 |
| `tile_type` | `TileType` | `DIRT` | 地块大类 |
| `variant_name` | `String` | `""` | 细分变种名称 |
| `passable` | `bool` | `true` | 是否可通行 |
| `buildable` | `bool` | `true` | 是否可建造 |
| `farmland` | `bool` | `false` | 是否可耕种 |
| `moisture` | `float` | `0.0` | 湿度 (0.0~1.0) |
| `hardness` | `int` | `1` | 硬度，影响建造/挖掘耗时 |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `apply_defaults()` | `void` | 根据 `tile_type` 自动设置通行/建造/耕种等默认值 |
| `get_type_name()` | `String` | 返回中文类型名（泥土/石头/水面/未知） |

### 各类型默认值

| TileType | passable | buildable | farmland | moisture | hardness |
|----------|----------|-----------|----------|----------|----------|
| DIRT | ✓ | ✓ | ✓ | 0.3 | 1 |
| STONE | ✓ | ✓ | ✗ | 0.1 | 3 |
| OCEAN | ✗ | ✗ | ✗ | 1.0 | 999 |

## 使用示例

```gdscript
# 通过 TerrainGenerator 读取
var data: Resource = world.get_tile_data_at(3, 7)
if data and data.farmland:
    _plant_crop_at(3, 7)

# 自行创建
var info := TileInfo.new()
info.grid_position = Vector2i(5, 5)
info.tile_type = TileInfo.TileType.DIRT
info.apply_defaults()

# 在其他脚本中通过 preload 访问枚举
const TileInfoRef: Script = preload("res://scripts/world/tile_data.gd")
if tile_type == TileInfoRef.TileType.OCEAN:
    return  # 海洋不可建造
```

## 关联文档

- [Docs/地块系统/1.1地块系统.md](../地块系统/1.1地块系统.md)
- [Docs/地块系统/1.2主要地块类型.md](../地块系统/1.2主要地块类型.md)
- [Docs/world/terrain_generator.md](terrain_generator.md)
