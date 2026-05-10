#extends Area2D
#
## 角色走进碰撞区
#func _on_body_entered(body):
	## 直接用节点名判断，不用组！
	#print(1)
	#if body.name == "character_body_2d":
		## 往上找两层，找到主UI节点Main_ui，调用显示按钮函数
		#var main_ui = get_tree().root.get_node("Main_ui")
		#if main_ui:
			#main_ui.show_interact_button()
			#print("成功调用了显示按钮函数")
#
## 角色离开碰撞区
#func _on_body_exited(body):
	#if body.name == "character_body_2d":
		#get_parent().get_parent().hide_interact_button()
extends Area2D
