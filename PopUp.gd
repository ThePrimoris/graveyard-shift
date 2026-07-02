extends CanvasLayer

@onready var icon_node = %Icon
@onready var name_label = %ItemName
@onready var amount_label = %ItemAmount
@onready var anim = $AnimationPlayer

func setup(item_name: String, amount: int):
    name_label.text = item_name
    amount_label.text = "+" + str(amount)
    anim.play("pop_up")