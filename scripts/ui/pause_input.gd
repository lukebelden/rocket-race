extends Node
## Listens for the pause key (Esc or P) even while the game is paused, so the same key
## both pauses and resumes. game.gd decides whether pausing is allowed (single player only).

signal toggle


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_ESCAPE or event.physical_keycode == KEY_P):
		get_viewport().set_input_as_handled()
		toggle.emit()
