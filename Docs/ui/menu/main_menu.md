# MainMenu — 主菜单

## 用途

游戏启动后第一个加载的场景。提供通向所有局外系统的导航入口。

## 依赖

- `EventBus` Autoload — 发射 `game_state_changed(&"main_menu")` 信号
- `MenuStyle` — 静态样式工厂类

## 公开 API

### 信号

无。场景切换使用 `get_tree().change_scene_to_file()`。

### 按钮行为

| 按钮 | 行为 |
|------|------|
| 开始游戏 | 弹出确认对话框，确认后切换到 `loading_screen.tscn` |
| 加载游戏 | Toast 提示"功能尚未实现" |
| 成就 | Toast 提示"功能尚未实现" |
| 设置 | Toast 提示"功能尚未实现" |
| 退出游戏 | `get_tree().quit()` |

## 场景结构

```
CanvasLayer (MainMenu, layer=100000)
├── ColorRect (全屏深色背景)
└── VBoxContainer (居中)
    ├── Label (标题 "Farm War", 金色)
    ├── HSeparator
    ├── Button ×5 (开始游戏 / 加载游戏 / 成就 / 设置 / 退出游戏)
    ├── HSeparator
    └── Label (版本号)
```

确认对话框为动态创建的 Control 子树（遮罩 + Panel），位于 CanvasLayer 内。

## 入场动画

按钮从左侧滑入并淡入，依次错开 80ms 延迟。版本号最后淡入。
