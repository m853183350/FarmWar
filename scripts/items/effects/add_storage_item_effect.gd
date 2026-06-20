## 效果：向仓库添加物品。
##
## 参数：[code]{ item_id: String, amount: float }[/code]
##
## 示例：
##   [code]{ "item_id": "money", "amount": 1.0 }[/code] — 每次触发添加 1 金币
class_name AddStorageItemEffect extends PropEffectBase

# ============================================================
# 9. 公开方法
# ============================================================

## 向 [member storage] 添加指定物品。
func execute(params: Dictionary) -> void:
	var item_id: String = params.get("item_id", "") as String
	if item_id.is_empty():
		push_error("AddStorageItemEffect: 缺少 item_id 参数")
		return

	var amount: float = params.get("amount", 0.0) as float
	if amount <= 0.0:
		return

	if storage == null:
		push_error("AddStorageItemEffect: Storage 引用为空，效果执行失败")
		return

	storage.add_item(item_id, amount)
