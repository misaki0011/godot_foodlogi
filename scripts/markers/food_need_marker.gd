class_name FoodNeedMarker
extends Node3D

## Ambient world indicator floated above a settlement: a small speech bubble
## holding a food icon (tinted to the food's color) and how much of that
## food the settlement is still short today. Complements SETT-04's popup,
## which needs a click, with an always-visible glance-able signal.

func setup(food: FoodData, amount: float) -> void:
	var icon: MeshInstance3D = $Icon
	var mat := StandardMaterial3D.new()
	mat.albedo_color = food.color
	icon.material_override = mat
	$Label3D.text = str(roundi(amount))
