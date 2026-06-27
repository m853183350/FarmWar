# GameRoot — 游戏场景根节点控制器

## 用途

挂载在 `game.tscn` 根节点上，负责游戏启动初始化和调试工具加载。

## 依赖

- `TickSystem` Autoload — 显式调用 `start()` 启动逻辑时钟
- `EventBus` Autoload — 发射 `game_state_changed(&"playing")` 信号
- `Debugger` (`scripts/utils/debugger.gd`) — 调试版本中动态创建

## 与 main.tscn 的差异

| 项 | main.tscn (旧) | game.tscn (新) |
|----|---------------|----------------|
| 根脚本 | 无 | `game_root.gd` |
| TickSystem 启动 | `auto_start=true`（Autoload 阶段） | `auto_start=false`，由 `GameRoot._ready()` 显式启动 |
| 调试工具 | 无条件加载为场景子节点 | `OS.is_debug_build()` 守卫，动态实例化 |
| 根级 Camera2D | 存在但 `current_enabled=false`（死代码） | 已移除 |
| 入口 | `main.tscn`（项目直接加载） | 由主菜单通过场景切换加载 |
