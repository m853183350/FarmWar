# PropEffectBase（道具效果基类）

所有道具效果的抽象基类。每个效果实例持有 [Storage] 引用（由 PropManager 注入），子类必须覆写 [method execute] 实现具体逻辑。

## 用途

- 将效果逻辑从 [PropManager] 中分离，保持 PropManager 文件精简
- 新增效果只需创建子类 + 在 PropManager 中注册，无需修改 PropManager 核心逻辑

## 依赖

| 依赖 | 说明 |
|------|------|
| `Storage` | 由 PropManager 在构造后通过 `init()` 注入 |

## 公开 API

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `init(storage: Storage)` | `void` | 注入 Storage 引用（由 PropManager 调用） |
| `execute(params: Dictionary)` | `void` | 执行效果（子类必须覆写） |

## 子类

| 类 | 文件 | 说明 |
|----|------|------|
| `AddStorageItemEffect` | `add_storage_item_effect.gd` | 向仓库添加物品 |

## 关联文档

- [../prop_manager.md](../prop_manager.md) — PropManager（效果注册与调度）
- [add_storage_item_effect.md](add_storage_item_effect.md) — 首个效果实现
