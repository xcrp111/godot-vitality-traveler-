extends Area2D
@onready var portal = get_node("Area csm1")
 
func _on_body_entered(body):
	if body.name == "fashi.tscn":
		portal.visble = true
		portal.monitoring = true
