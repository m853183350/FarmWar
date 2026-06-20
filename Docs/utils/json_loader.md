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

## 静态方法

### `load_config_file(path: String, caller: String = "") -> Dictionary`

从文件路径加载并解析 JSON 配置文件。

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | `String` | JSON 文件路径（如 `"res://config/units/farm_worker.json"`） |
| `caller` | `String` | 调用类名，用于错误信息前缀。留空时不输出前缀 |

**返回值**：解析后的 `Dictionary`；加载或解析失败时返回空 `Dictionary`。

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
