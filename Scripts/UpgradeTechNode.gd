@tool
extends PanelContainer
class_name UpgradeTechNode

signal pressed(upgrade_key: String)
signal hover_started(upgrade_key: String, global_mouse_pos: Vector2)
signal hover_ended()

@export var upgrade_key: String = ""

var _icon_texture: Texture2D = null

@export var icon_texture: Texture2D:
	get:
		return _icon_texture
	set(value):
		_icon_texture = value
		_update_icon()

@onready var icon_texture_rect: TextureRect = $IconTexture
@onready var click_area: Button = $ClickArea

var is_disabled: bool = false


func _ready() -> void:
	if click_area and not click_area.pressed.is_connected(_on_pressed):
		click_area.pressed.connect(_on_pressed)
	if click_area and not click_area.mouse_entered.is_connected(_on_mouse_entered):
		click_area.mouse_entered.connect(_on_mouse_entered)
	if click_area and not click_area.mouse_exited.is_connected(_on_mouse_exited):
		click_area.mouse_exited.connect(_on_mouse_exited)

	mouse_filter = Control.MOUSE_FILTER_PASS
	_apply_base_style()
	_update_icon()


func _enter_tree() -> void:
	_update_icon()


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY \
	or what == NOTIFICATION_ENTER_TREE \
	or what == NOTIFICATION_EDITOR_PRE_SAVE:
		_update_icon()


func _update_icon() -> void:
	if not is_inside_tree():
		return

	if icon_texture_rect:
		icon_texture_rect.texture = _icon_texture
		icon_texture_rect.visible = _icon_texture != null


func set_state(state: String) -> void:
	_apply_state_style(state)


func set_disabled_state(disabled: bool) -> void:
	is_disabled = disabled


func _on_pressed() -> void:
	if is_disabled:
		return
	emit_signal("pressed", upgrade_key)


func _on_mouse_entered() -> void:
	emit_signal("hover_started", upgrade_key, get_global_mouse_position())


func _on_mouse_exited() -> void:
	emit_signal("hover_ended")


func _apply_base_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.16, 0.96)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.35, 0.55, 0.75, 1.0)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", sb)


func _apply_state_style(state: String) -> void:
	var sb := get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var style := sb as StyleBoxFlat

		match state:
			"available":
				style.bg_color = Color(0.12, 0.16, 0.24, 1.0)
				style.border_color = Color(0.45, 0.85, 1.0, 1.0)
			"purchased":
				style.bg_color = Color(0.10, 0.20, 0.12, 1.0)
				style.border_color = Color(0.35, 1.0, 0.55, 1.0)
			"maxed":
				style.bg_color = Color(0.20, 0.18, 0.08, 1.0)
				style.border_color = Color(1.0, 0.85, 0.35, 1.0)
			"locked":
				style.bg_color = Color(0.10, 0.12, 0.16, 0.96)
				style.border_color = Color(0.45, 0.45, 0.45, 0.85)
			_:
				style.bg_color = Color(0.10, 0.12, 0.16, 0.96)
				style.border_color = Color(0.45, 0.45, 0.45, 0.85)
