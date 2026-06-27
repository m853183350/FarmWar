# LoadingScreen — 加载界面

## 用途

在主菜单确认开始游戏后，显示加载进度条，同时在后台预加载游戏场景资源。

## 依赖

- `EventBus` Autoload — 发射 `game_state_changed(&"loading")` 信号
- `ResourceLoader` — 后台线程加载 `game.tscn`

## 加载流程

1. `_ready()`: 构建 UI，调用 `ResourceLoader.load_threaded_request("game.tscn")`
2. `_process()`: 轮询 `load_threaded_get_status()`，更新进度条和状态文本
3. 加载完成: 延迟 0.3s 后 `change_scene_to_file("game.tscn")`
4. 回退: 如果后台加载失败，直接切换场景

## 场景结构

```
CanvasLayer (LoadingScreen, layer=100000)
├── ColorRect (全屏深色背景)
└── Panel (居中)
    └── VBoxContainer
        ├── Label ("正在加载...")
        ├── ProgressBar
        └── Label (状态文本)
```

## 已知限制

- 进度条显示的是 `game.tscn` 及其 `ext_resource` 的加载进度，不包括 `TerrainGenerator.generate()` 的同步阻塞时间。
- 未来可将地形生成改为协程跨帧执行，实现真正的平滑加载。
