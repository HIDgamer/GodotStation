class_name ManualVendorItem
extends Resource

@export var item_path: String = ""
@export var display_name: String = ""
@export var initial_stock: int = 1
@export var max_stock: int = 10
@export var price: int = 0
@export var category: String = "General"

func _init(path: String = "", name: String = "", stock: int = 1, max: int = 10, cost: int = 0):
	item_path = path
	display_name = name
	initial_stock = stock
	max_stock = max
	price = cost
