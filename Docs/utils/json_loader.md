# JSON 配置加载工具 (JsonConfigLoader)

`JsonConfigLoader` 是 JSON 配置文件加载的统一工具类，封装文件存在性检查、解析、错误日志等完整流程。避免各处重复编写相同的 JSON 加载/解析代码。

---

## 文件位置

- **脚本**：`scripts/utils/json_loader.gd`
- **类型**：`RefCounted`（纯静态工具，无需实例化）

---

## 使用方式

```gdscript
const JsonConfigLoader = preload("res://scripts/utils/json_loader.gd")

# 加载配置文件，错误信息前缀为 "FarmWorker"
var config: Dictionary = JsonConfigLoader.load_config_file("res://config/units/farm_worker.json", "FarmWorker")

# 加载配置文件，无类名前缀
var config: Dictionary = JsonConfigLoader.load_config_file("res://config/game_settings.json")
```

---

## 缓存机制

`JsonConfigLoader` 内部维护一个静态字典缓存（`_cache: Dictionary`），key 为文件路径，value 为解析后的配置字典。首次加载时将结果存入缓存，后续请求同一路径时直接返回缓存，避免重复的 IO 和 JSON 解析开销。大部分配置文件在游戏过程中不会被修改，因此缓存是安全的。

## 静态方法

### `load_config_file(path: String, caller: String = "") -> Dictionary`

从文件路径加载并解析 JSON 配置文件（**带缓存**）。

首次加载时从磁盘读取并解析，结果存入缓存。后续请求同一 `path` 时直接返回缓存。

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | `String` | JSON 文件路径（如 `"res://config/units/farm_worker.json"`） |
| `caller` | `String` | 调用类名，用于错误信息前缀。留空时不输出前缀 |

**返回值**：解析后的 `Dictionary`；加载或解析失败时返回空 `Dictionary`。

**内部逻辑**：
1. 检查缓存是否命中，命中则直接返回
2. 缓存未命中则执行磁盘读取流程（见 `_read_config_file`）
3. 成功后将结果存入缓存

### `reload_config_file(path: String, caller: String = "") -> Dictionary`

强制重新读取配置文件并刷新缓存。

始终从磁盘重新读取，并用新数据覆盖缓存。适用于配置文件可能被动态修改的场景。

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | `String` | JSON 文件路径 |
| `caller` | `String` | 调用类名，用于错误信息前缀。留空时不输出前缀 |

**返回值**：重新解析后的 `Dictionary`；失败时保留旧缓存不变，返回空 `Dictionary`。

### `clear_cache(path: String = "") -> void`

清除指定路径的缓存，或清除全部缓存。

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | `String` | 要清除的配置文件路径。留空时清除所有缓存 |

### `_read_config_file(path: String, caller: String) -> Dictionary`（私有）

实际从磁盘读取并解析 JSON 文件的内部方法，不涉及缓存逻辑。

**内部逻辑**：
1. 检查文件存在性（`FileAccess.file_exists`）
2. 打开文件并读取全部文本
3. 通过 `JSON.parse()` 解析
4. 校验顶层数据类型为 `Dictionary`

任一环节失败时输出带 `caller` 前缀的 `push_error` 并返回空字典。

---

## 引用方

| 文件 | 配置文件 |
|------|----------|
| `scripts/units/player_units/farm_worker.gd` | `res://config/units/farm_worker.json` |
| `scripts/crops/plants/wheat_tier1.gd` | `res://config/crops/wheat_tier1.json` |
| `scripts/world/camera_controller.gd` | `res://config/camera.json` |

---

## 相关文件

- [[texture_loader]] — 纹理加载工具（同为 `scripts/utils/` 下的静态工具类）
