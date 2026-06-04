# MaterialManager（材质管理器）

全局单例（待实现），统一管理游戏中所有的 ShaderMaterial 和 gdshader 资源，提供加载、缓存和应用接口。

> 通过 Autoload 全局访问：`MaterialManager`

## 用途

- 集中管理所有 ShaderMaterial 资源，避免各自加载导致重复编译
- 提供材质缓存机制，同类型对象共享同一 shader 实例
- 提供便捷的运行时效果接口（生长进度、受伤闪烁、选中高亮等）
- 从配置文件加载材质索引，新增材质只需 JSON + shader 文件，无需改代码

## 依赖

| 依赖 | 说明 |
|------|------|
| `resources/shaders/` | `.gdshader` 着色器源码 |
| `resources/materials/` | `.material` / `.tres` 材质资源文件 |
| `config/material_index.json` | 材质索引配置（规划） |

## 公开 API（规划）

### 材质获取

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `get_material(id: StringName)` | `ShaderMaterial` | 按 ID 获取缓存的材质，不存在则加载 |
| `preload_materials(id_list: Array)` | `void` | 预加载一组材质（启动时调用避免运行时卡顿） |
| `reload_material(id: StringName)` | `ShaderMaterial` | 强制重新加载（热重载/调试用） |

### 效果应用

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `apply_to(node: Node2D, material_id: StringName, params: Dictionary)` | `void` | 给节点应用材质并设置参数 |
| `set_param(node: Node2D, param: StringName, value)` | `void` | 修改已应用材质的单个参数 |
| `remove_from(node: Node2D)` | `void` | 移除节点上的 ShaderMaterial（恢复默认白色纹理） |

## 材质索引配置

`config/material_index.json`（规划）：

```json
{
  "crops": {
    "crop_grow": {
      "shader": "res://resources/shaders/crops/crop_grow.gdshader",
      "material": "res://resources/materials/crops/crop_grow.tres"
    },
    "crop_wither": {
      "shader": "res://resources/shaders/crops/crop_wither.gdshader",
      "material": "res://resources/materials/crops/crop_wither.tres"
    }
  },
  "units": {
    "unit_highlight": {
      "shader": "res://resources/shaders/units/unit_highlight.gdshader",
      "material": "res://resources/materials/units/unit_highlight.tres"
    }
  }
}
```

## 已创建的资源

### Shaders

| 文件 | 类型 | 用途 | 状态 |
|------|------|------|------|
| `resources/crops1x1.gdshader` | `canvas_item` | 1×1 格作物通用着色器 | ✅ 已完成 |

### Materials

| 文件 | 引用 Shader | 用途 | 状态 |
|------|------------|------|------|
| `resources/materials/crops/crops1x1.tres` | `crops1x1.gdshader` | 通用作物材质（默认参数） | ✅ 已完成 |

## crops1x1.gdshader — uniform 参数

所有参数均为 `@export`，在编辑器的 ShaderMaterial 面板中可直接修改。

| uniform | 类型 | 默认值 | 说明 |
|---------|------|--------|------|
| `custom_texture` | `sampler2D` | — | 自定义纹理（勾选 `use_custom_tex` 后替代节点纹理） |
| `use_custom_tex` | `bool` | `false` | 是否启用自定义纹理 |
| `offset_px` | `vec2` | `(0, 0)` | 纹理像素偏移量（单位：px），正值向右/下 |
| `texture_size` | `vec2` | `(32, 16)` | 纹理的实际像素尺寸，用于将 offset_px 转为 UV |
| `scale_mult` | `float` | `1.0` | UV 缩放倍率（0.1~10.0），居中缩放 |
| `modulate_color` | `vec4` | `(1, 1, 1, 1)` | 颜色/透明度调制（RGBA 叠加乘法） |

**渲染特性：**
- `filter_nearest` — 像素完美，无模糊
- `canvas_item` — 不受 3D 光照影响
- 透明像素完整保留（纹理 alpha × modulate_color.a）

### 使用示例

```gdscript
# 加载材质资源
const CROP_MATERIAL: ShaderMaterial = preload("res://resources/materials/crops/crops1x1.tres")

# 实例化后应用材质（.duplicate() 确保每个实例独立控制参数）
var crop: Sprite2D = wheat_scene.instantiate()
crop.material = CROP_MATERIAL.duplicate()

# 生长阶段 0 → 2，逐帧切换纹理区域
crop.material.set_shader_parameter("offset_px", Vector2(16, 0))

# 缩放放大 1.5 倍
crop.material.set_shader_parameter("scale_mult", 1.5)

# 红色调闪烁
crop.material.set_shader_parameter("modulate_color", Color(1, 0.3, 0.3, 1))

# 淡出消失
var tween := create_tween()
tween.tween_method(
    func(v: float):
        crop.material.set_shader_parameter("modulate_color", Color(1, 1, 1, v)),
    1.0, 0.0, 0.5
)
```

## 关联文档

- [Docs/整体设计.md](../整体设计.md) — 材质系统定位与设计
- [Docs/目录结构.md](../目录结构.md) — 资源目录结构
- [Docs/crops/2.2小麦.md](../crops/2.2小麦.md) — 小麦作物（首个使用材质系统的对象）
