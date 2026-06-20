# Player（玩家实体）

玩家根容器节点，承载仓库等子系统的空 Node。

## 用途

- 作为玩家系统的根节点，统一管理所有玩家子组件
- 注册到 `"player"` group，供其他系统查找
- 启动时自动创建 [Storage] 子节点

## 依赖

| 依赖 | 说明 |
|------|------|
| `Storage` | 在 `_ready()` 中以代码方式创建 |
| `PropManager` | 在 `_ready()` 中以代码方式创建 |

## 公开 API

### 变量

暂无。

### 方法

暂无。

### Group

| Group | 说明 |
|-------|------|
| `"player"` | 注册到此 group，可通过 `get_tree().get_nodes_in_group("player")` 查找 |

## 场景树结构

```
Player (Node)
  ├── Storage (Storage)
  │     ├── contents: Dictionary
  │     └── catalog: Dictionary
  └── PropManager (PropManager)
        ├── props: Dictionary
        ├── prop_library: Dictionary
        └── _signal_bindings: Dictionary
```

## 后续扩展

- PlayerController（输入控制）
- PlayerInventory（快捷栏）
- 经济数据（金币等）

## 关联文档

- [Docs/storage/storage.md](../storage/storage.md) — 仓库实现
- [Docs/storage/6.1仓库系统.md](../storage/6.1仓库系统.md) — 仓库系统设计
