## 效果：向仓库添加物品。
##
## 参数：[code]{ item_id: String, amount: float }[/code]
##
## 示例：
##   [code]{ "item_id": "money", "amount": 1.0 }[/code] — 每次触发添加 1 金币
##
## 运行时从 [code]context["storage"][/code] 获取 [Storage] 引用。
class_name AddStorageItemEffect extends PropEffectBase

# ============================================================
# 9. 公开方法
# ============================================================

## 向仓库添加指定物品。[br]
## [param params] 效果参数，必须包含 [code]item_id[/code] 和 [code]amount[/code]。[br]
## [param context] 运行时上下文，必须包含 [code]storage[/code]（[Storage] 引用）。
func execute(params: Dictionary, context: Dictionary) -> void:
	var item_id: String = params.get("item_id", "") as String
	if item_id.is_empty():
		push_error("AddStorageItemEffect: 缺少 item_id 参数")
		return

	var amount: float = params.get("amount", 0.0) as float
	if amount <= 0.0:
		return

	var storage: Storage = context.get("storage", null) as Storage
	if storage == null:
		push_error("AddStorageItemEffect: context 中缺少 storage 引用，效果执行失败")
		return

	storage.add_item(item_id, amount)
