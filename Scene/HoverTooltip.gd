extends PanelContainer

@onready var icon_texture: TextureRect = $MarginContainer/VBoxContainer/TopRow/IconTexture
@onready var name_label: Label = $MarginContainer/VBoxContainer/TopRow/NameLabel
@onready var desc_label: Label = $MarginContainer/VBoxContainer/DescLabel
@onready var level_label: Label = $MarginContainer/VBoxContainer/LevelLabel
@onready var cost_label: Label = $MarginContainer/VBoxContainer/CostLabel

@export var screen_padding: float = 12.0
@export var gap_above_icon: float = 8.0
@export var gap_below_icon: float = 8.0
@export var max_tooltip_width: float = 320.0

func _ready() -> void:
	visible = false
	_apply_style()

	custom_minimum_size.x = max_tooltip_width

	if desc_label:
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size.x = max_tooltip_width - 24.0


func show_upgrade_tooltip(
	display_name: String,
	description: String,
	level: int,
	max_level: int,
	cost_text: String,
	icon_top_center_global: Vector2,
	icon: Texture2D = null,
	icon_size: Vector2 = Vector2(64, 64)
) -> void:
	if name_label:
		name_label.text = display_name
	if desc_label:
		desc_label.text = description
	if level_label:
		level_label.text = "Lv. %d / %d" % [level, max_level]
	if cost_label:
		cost_label.text = cost_text

	if icon_texture:
		icon_texture.texture = icon
		icon_texture.visible = icon != null

	visible = true
	call_deferred("_position_tooltip_relative_to_icon", icon_top_center_global, icon_size)


func hide_tooltip() -> void:
	visible = false


func _position_tooltip_relative_to_icon(icon_top_center_global: Vector2, icon_size: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	var tooltip_size := size

	if tooltip_size.x <= 0.0 or tooltip_size.y <= 0.0:
		tooltip_size = get_combined_minimum_size()

	var x := icon_top_center_global.x - (tooltip_size.x * 0.5)

	# Available vertical spaces
	var space_above := icon_top_center_global.y - gap_above_icon - screen_padding
	var icon_bottom_y := icon_top_center_global.y + icon_size.y
	var space_below := viewport_size.y - screen_padding - (icon_bottom_y + gap_below_icon)

	# Ideal positions
	var y_above := icon_top_center_global.y - gap_above_icon - tooltip_size.y
	var y_below := icon_bottom_y + gap_below_icon

	var fits_above := tooltip_size.y <= space_above
	var fits_below := tooltip_size.y <= space_below

	var y: float

	if fits_above:
		y = y_above
	elif fits_below:
		y = y_below
	else:
		# Neither fits fully. Choose the side with more room and pin it there
		# without crossing into the icon area.
		if space_above >= space_below:
			y = maxf(screen_padding, icon_top_center_global.y - gap_above_icon - tooltip_size.y)
		else:
			y = minf(viewport_size.y - screen_padding - tooltip_size.y, icon_bottom_y + gap_below_icon)

	# Clamp horizontally only.
	if x + tooltip_size.x > viewport_size.x - screen_padding:
		x = viewport_size.x - tooltip_size.x - screen_padding
	if x < screen_padding:
		x = screen_padding

	global_position = Vector2(x, y)


func _apply_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.45, 0.75, 1.0, 1.0)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	add_theme_stylebox_override("panel", sb)
