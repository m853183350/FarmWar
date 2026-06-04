# BaseTile（地块抽象基类）

所有地块类型的抽象基类，定义地块的必备属性访问器、内容物管理和通用接口。

> 所有地块脚本（`DirtTile`、`StoneTile`、`OceanTile`、`FarmlandTile` 等）都必须继承本类。

## 用途

- 为所有地块提供统一的行为契约，确保新增地块类型不会遗漏关键属性
- 集中管理内容物（`occupants`），避免各子类重复实现
- 提供一致的数据访问接口，外部系统（建筑、作物、战斗等）通过 `BaseTile` 即可查询任意地块

## 依赖

| 依赖 | 说明 |
|------|------|
| `TileInfo` | 地块数据资源类，存储地块的运行时属性 |
| `Sprite2D` | Godot 原生 2D 精灵节点（本类继承自它） |

## 公开 API

### 信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `tile_data_changed` | — | 地块数据资源变更时发出 |
| `occupant_added` | `occupant: Node` | 内容物添加时发出 |
| `occupant_removed` | `occupant: Node` | 内容物移除时发出 |

### 枚举

| 枚举 | 值 | 说明 |
|------|-----|------|
| `ResourceType.NONE` | 0 | 无资源 |
| `ResourceType.STONE` | 1 | 石材 |
| `ResourceType.IRON` | 2 | 铁矿 |
| `ResourceType.GOLD` | 3 | 金矿 |
| `ResourceType.WOOD` | 4 | 木材 |
| `ResourceType.FISH` | 5 | 鱼类 |

### @export 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `tile_type` | `int` | `-1` | 地块大类（子类在 `_ready()` 中赋值） |
| `variant` | `String` | `""` | 变种名称 |
| `display_name` | `String` | `""` | 人类可读名称 |

### 数据访问方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `get_tile_data()` | `TileInfo` | 获取地块数据资源，未设置返回 `null` |
| `set_tile_data(data: TileInfo)` | `void` | 设置地块数据，同步到 metadata 并发出信号 |
| `get_grid_position()` | `Vector2i` | 获取网格坐标，无数据时返回 `(0, 0)` |

### 通行与建造（必备属性访问器）

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `is_passable()` | `bool` | 是否可通行，优先读 TileInfo，无数据时默认 `true` |
| `is_buildable()` | `bool` | 是否可建造，无数据时默认 `true` |
| `is_farmland()` | `bool` | 是否农田/可耕种，无数据时默认 `false` |
| `get_resource_type()` | `int` | 资源类型（`ResourceType` 枚举值） |

### 地块交互（虚方法，子类覆写）

| 方法 | 返回值 | 默认值 | 说明 |
|------|--------|--------|------|
| `can_be_plowed()` | `bool` | `false` | 是否可耕作转化为农田 |
| `can_be_dug()` | `bool` | `false` | 是否可挖掘 |

### 内容物管理

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `add_occupant(node: Node)` | `void` | 添加内容物，去重，发出 `occupant_added` |
| `remove_occupant(node: Node)` | `void` | 移除内容物，发出 `occupant_removed` |
| `has_occupant_of_type(klass_name: String)` | `bool` | 是否有指定类的实例 |
| `get_all_occupants()` | `Array[Node]` | 获取内容物副本 |

### 可选属性访问器

| 方法 | 返回值 | 默认值 | 说明 |
|------|--------|--------|------|
| `get_fertility()` | `float` | `0.0` | 肥力值 (0.0 ~ 5.0) |
| `get_moisture()` | `float` | `0.0` | 湿度值 (0.0 ~ 5.0) |
| `get_hardness()` | `int` | `1` | 硬度 |
| `get_depth()` | `float` | `0.0` | 水深 (0.0 ~ 1.0) |
| `is_fishable()` | `bool` | `false` | 是否可钓鱼 |

### 调试方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `get_type_name()` | `String` | 中文类型名（通过 TileInfo 获取） |
| `get_description()` | `String` | "变种名 (类型名)" 格式的描述 |

## 子类实现要求

每个继承 `BaseTile` 的子类必须：

1. 在 `_ready()` 中设置 `tile_type`、`variant`、`display_name`，然后调用 `super._ready()`
2. 覆写 `can_be_plowed()` 和 `can_be_dug()`
3. 如需特有方法（如 `StoneTile.get_dig_produce()`），声明在子类中

示例（DirtTile）：

```gdscript
class_name DirtTile extends BaseTile

func _ready() -> void:
	tile_type = TileInfo.TileType.DIRT
	variant = "soil"
	display_name = "普通土壤"
	super._ready()

func can_be_plowed() -> bool:
	return true

func can_be_dug() -> bool:
	return false
```

## 类继承关系

```
Sprite2D
└── BaseTile（抽象基类 — 本类）
    ├── DirtTile    — 土质地面
    ├── StoneTile   — 石质地面
    ├── OceanTile   — 水域
    └── FarmlandTile — 农田
```

## 关联文档

- [Docs/地块系统/1.1地块系统.md](../地块系统/1.1地块系统.md) — 地块系统架构
- [Docs/地块系统/1.2主要地块类型.md](../地块系统/1.2主要地块类型.md) — 地块类型与属性
- [Docs/world/tile_data.md](tile_data.md) — TileInfo 数据类
- [Docs/world/terrain_generator.md](terrain_generator.md) — 地形生成器
