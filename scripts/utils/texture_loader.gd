## 纹理加载工具函数。
##
## 提供从路径加载纹理的统一入口，加载失败时自动生成棋盘格占位符，
## 避免各处重复编写降级逻辑。
##
## 使用方式：
##   [code]const TextureLoader = preload("res://scripts/utils/texture_loader.gd")[/code]
##   [code]var tex: Texture2D = TextureLoader.load_texture("res://path/to/icon.png", 48)[/code]
extends RefCounted

# ============================================================
# 3. 常量
# ============================================================

## 默认占位符纹理尺寸（像素），当未显式指定 size 时使用。
const DEFAULT_PLACEHOLDER_SIZE: int = 64

# ============================================================
# 9. 静态方法 — 纹理加载
# ============================================================

## 从文件路径加载纹理，失败时返回棋盘格占位符。
##
## 优先使用 [method ResourceLoader.exists] 检查资源是否存在，
## 再通过 [method ResourceLoader.load] 加载；若路径为空、
## 资源不存在或返回值不是 [Texture2D]，则生成占位符。
##
## [param path] 纹理资源路径（如 [code]"res://assets/icon.png"[/code]）。
## [param size]  占位符尺寸（仅在加载失败时生效），默认 [member DEFAULT_PLACEHOLDER_SIZE]。
##
## 返回加载成功的 [Texture2D] 或自动生成的 [ImageTexture] 占位符。
static func load_texture(path: String, size: int = DEFAULT_PLACEHOLDER_SIZE) -> Texture2D:
	if not path.is_empty() and ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			return res as Texture2D

	return create_placeholder(size)

## 生成棋盘格占位纹理，用于标识缺失的图标资源。
##
## 使用深浅交错的方格填充，尺寸为 [param size] × [param size]，
## 便于在开发阶段快速识别未加载到纹理的 UI 元素。
##
## [param size] 占位符正方形边长（默认 [member DEFAULT_PLACEHOLDER_SIZE]）。
static func create_placeholder(size: int = DEFAULT_PLACEHOLDER_SIZE) -> Texture2D:
	var s: int = maxi(size, 1)
	var img: Image = Image.create(s, s, false, Image.FORMAT_RGBA8)
	var cell: int = maxi(s / 4, 1)

	for y: int in range(s):
		var row_checker: bool = (y / cell) % 2 == 0
		for x: int in range(s):
			var col_checker: bool = (x / cell) % 2 == 0
			var is_checker: bool = row_checker == col_checker
			var c: Color = Color(0.3, 0.3, 0.4, 1.0) if is_checker else Color(0.4, 0.4, 0.5, 1.0)
			img.set_pixel(x, y, c)

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	return tex as Texture2D
