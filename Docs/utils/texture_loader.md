# 纹理加载工具 (TextureLoader)

`TextureLoader` 是纹理加载的统一工具类，提供从路径加载纹理并自动降级为棋盘格占位符的能力。避免各处重复编写加载失败处理逻辑。

---

## 文件位置

- **脚本**：`scripts/utils/texture_loader.gd`
- **类型**：`RefCounted`（纯静态工具，无需实例化）

---

## 使用方式

```gdscript
const TextureLoader = preload("res://scripts/utils/texture_loader.gd")

# 加载纹理，失败时自动生成 48×48 棋盘格占位符
var tex: Texture2D = TextureLoader.load_texture("res://assets/icon.png", 48)

# 仅生成占位符（例如用于未配置图标的兜底场景）
var placeholder: Texture2D = TextureLoader.create_placeholder(64)
```

---

## 静态方法

### `load_texture(path: String, size: int = 64) -> Texture2D`

从文件路径加载纹理。

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | `String` | 纹理资源路径（如 `"res://assets/icon.png"`） |
| `size` | `int` | 占位符尺寸，仅加载失败时生效，默认 64 |

**返回值**：加载成功的 `Texture2D`，或自动生成的棋盘格 `ImageTexture` 占位符。

**内部逻辑**：
1. 若 `path` 非空且 `ResourceLoader.exists(path)` 为真 → `load(path)` 并校验类型
2. 若步骤 1 失败 → 调用 `create_placeholder(size)` 返回兜底纹理

### `create_placeholder(size: int = 64) -> Texture2D`

生成棋盘格占位纹理，用于标识缺失的图标资源。

| 参数 | 类型 | 说明 |
|------|------|------|
| `size` | `int` | 占位符正方形边长，默认 64 |

**棋盘格样式**：深色 `(0.3, 0.3, 0.4)` 与浅色 `(0.4, 0.4, 0.5)` 交替，4×4 单元格排布，便于在开发阶段快速识别未正确加载的纹理。

---

## 引用方

| 文件 | 使用场景 |
|------|----------|
| `scripts/ui/mode_selector.gd` | 加载模式图标（`_load_icon_texture`、`_create_placeholder_texture`） |
| `scripts/ui/popup/crop_picker.gd` | 加载作物列表中的作物图标 |

---

## 相关文件

- [[mode_selector]] — 模式选择器 UI
- [[crop_picker]] — 作物选择器弹出 UI
