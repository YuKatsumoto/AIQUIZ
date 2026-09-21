extends Node

func _ready() -> void:
	# The coordinator outlives this scene until the menu has rendered.
	var loading: CanvasLayer = load("res://scripts/ui/startup_loading.gd").new()
	loading.name = "StartupLoading"
	GameManager.add_child(loading)
