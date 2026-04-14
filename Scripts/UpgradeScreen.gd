extends Control

@export var game_scene: PackedScene

@onready var resource_label: Label = $RootMargin/MainVBox/HeaderRow/ResourceLabel
@onready var debug_buy_all_button: Button = $RootMargin/MainVBox/HeaderRow/DebugBuyAllButton
@onready var tech_tree_area: Control = $RootMargin/MainVBox/CenterRow/TechTreePanel/TechTreeArea
@onready var continue_button: Button = $RootMargin/MainVBox/FooterRow/ContinueButton
@onready var save_quit_button: Button = $RootMargin/MainVBox/FooterRow/SaveQuitButton
@onready var world_select_button: Button = $RootMargin/MainVBox/FooterRow/WorldSelectButton
@onready var hover_tooltip: Control = get_node_or_null("HoverTooltip")

var _upgrade_buttons: Dictionary = {}
var _connections: Array = []
var _hovered_upgrade_key: String = ""
var _hovered_mouse_pos: Vector2 = Vector2.ZERO
const TUTORIAL_UPGRADE_SCREEN := "upgrade_screen_intro_seen"

func _ready() -> void:
	continue_button.pressed.connect(continue_game)
	save_quit_button.pressed.connect(_on_save_and_quit_pressed)
	world_select_button.pressed.connect(_on_back_to_world_select_pressed)
	MusicManager.play_music(preload("res://sounds/Music/Orbital Standby.mp3"), "menu_theme")
	if debug_buy_all_button:
		debug_buy_all_button.pressed.connect(_on_debug_buy_all_pressed)

	if tech_tree_area != null:
		tech_tree_area.owner_screen = self

	if hover_tooltip:
		hover_tooltip.visible = false

	_build_tree()
	_refresh_view()
	_show_upgrade_tutorial_if_needed()


func _build_tree() -> void:
	_upgrade_buttons.clear()
	_connections.clear()

	var defs: Dictionary = GameManager.get_upgrade_definitions_world_1()

	for child in tech_tree_area.get_children():
		if not is_instance_valid(child):
			continue
		if not child.has_method("set_state"):
			continue
		if not ("upgrade_key" in child):
			continue

		var upgrade_key: String = String(child.upgrade_key)
		if upgrade_key == "":
			continue
		if not defs.has(upgrade_key):
			continue
		if not GameManager.is_upgrade_available_in_world(upgrade_key, GameManager.current_world):
			if child is CanvasItem:
				(child as CanvasItem).visible = false
			continue

		if _upgrade_buttons.has(upgrade_key):
			push_warning("Duplicate upgrade_key found in TechTreeArea: %s" % upgrade_key)
			continue

		_upgrade_buttons[upgrade_key] = child

		if child.has_signal("pressed"):
			var pressed_callable := Callable(self, "_buy_upgrade")
			if not child.pressed.is_connected(pressed_callable):
				child.pressed.connect(pressed_callable)

		if child.has_signal("hover_started"):
			var hover_start_callable := Callable(self, "_on_upgrade_hover_started")
			if not child.hover_started.is_connected(hover_start_callable):
				child.hover_started.connect(hover_start_callable)

		if child.has_signal("hover_ended"):
			var hover_end_callable := Callable(self, "_on_upgrade_hover_ended")
			if not child.hover_ended.is_connected(hover_end_callable):
				child.hover_ended.connect(hover_end_callable)

	for key in _upgrade_buttons.keys():
		var upgrade_key: String = String(key)
		var def: Dictionary = defs[upgrade_key]
		var requires: Array = def.get("requires", [])

		for req in requires:
			var req_key: String = String(req.get("upgrade", ""))
			if req_key == "":
				continue
			if _upgrade_buttons.has(req_key):
				_connections.append({
					"from": req_key,
					"to": upgrade_key
				})

	tech_tree_area.queue_redraw()


func _refresh_view() -> void:
	resource_label.text = "Scrap: %d" % GameManager.player_resources

	var defs: Dictionary = GameManager.get_upgrade_definitions_world_1()

	for key in _upgrade_buttons.keys():
		var node: Node = _upgrade_buttons[key]
		if not defs.has(key):
			if node is CanvasItem:
				(node as CanvasItem).visible = false
			continue

		var def: Dictionary = defs[key]
		var level: int = GameManager.get_upgrade_level(key)
		var max_level: int = int(def.get("max_level", 1))
		var is_hidden: bool = _should_hide_upgrade(key, defs)

		if node is CanvasItem:
			(node as CanvasItem).visible = not is_hidden

		if is_hidden:
			continue

		var can_buy: bool = GameManager.can_buy_upgrade(key)
		var is_maxed: bool = level >= max_level
		var is_purchased: bool = level > 0

		var state := "locked"
		if is_maxed:
			state = "maxed"
		elif is_purchased:
			state = "purchased"
		elif can_buy:
			state = "available"

		if node.has_method("set_state"):
			node.set_state(state)
		if node.has_method("set_disabled_state"):
			node.set_disabled_state(not can_buy)

	tech_tree_area.queue_redraw()


func _should_hide_upgrade(key: String, defs: Dictionary) -> bool:
	if not defs.has(key):
		return true

	var def: Dictionary = defs[key]
	var requires: Array = def.get("requires", [])

	if requires.is_empty():
		return false

	for req in requires:
		var req_key: String = String(req.get("upgrade", ""))
		var min_level: int = int(req.get("min_level", 1))
		if req_key == "":
			continue
		if GameManager.get_upgrade_level(req_key) >= min_level:
			return false

	return true


func _buy_upgrade(upgrade_key: String) -> void:
	GameManager.try_buy_upgrade(upgrade_key)
	_refresh_view()

	if _hovered_upgrade_key == upgrade_key:
		if _upgrade_buttons.has(upgrade_key):
			var node: Node = _upgrade_buttons[upgrade_key]
			if node is CanvasItem and (node as CanvasItem).visible:
				_show_tooltip_for_upgrade(upgrade_key)
			else:
				_on_upgrade_hover_ended()
		else:
			_on_upgrade_hover_ended()


func _on_debug_buy_all_pressed() -> void:
	_debug_buy_all_upgrades()


func _debug_buy_all_upgrades() -> void:
	var defs: Dictionary = GameManager.get_upgrade_definitions_world_1()
	var real_resources: int = GameManager.player_resources
	var fake_resources: int = 999999999
	var bought_any := true

	while bought_any:
		bought_any = false

		for key in defs.keys():
			var upgrade_key: String = String(key)

			if not GameManager.is_upgrade_available_in_world(upgrade_key, GameManager.current_world):
				continue

			while GameManager.can_buy_upgrade(upgrade_key):
				GameManager.player_resources = fake_resources
				var bought := GameManager.try_buy_upgrade(upgrade_key)
				GameManager.player_resources = real_resources

				if not bought:
					break

				bought_any = true

	GameManager.player_resources = real_resources
	_refresh_view()

	if _hovered_upgrade_key != "":
		if _upgrade_buttons.has(_hovered_upgrade_key):
			var hovered_node: Node = _upgrade_buttons[_hovered_upgrade_key]
			if hovered_node is CanvasItem and (hovered_node as CanvasItem).visible:
				_show_tooltip_for_upgrade(_hovered_upgrade_key)
			else:
				_on_upgrade_hover_ended()
		else:
			_on_upgrade_hover_ended()


func _on_upgrade_hover_started(upgrade_key: String, global_mouse_pos: Vector2) -> void:
	_hovered_upgrade_key = upgrade_key
	_hovered_mouse_pos = global_mouse_pos
	_show_tooltip_for_upgrade(upgrade_key)


func _show_tooltip_for_upgrade(upgrade_key: String) -> void:
	if hover_tooltip == null:
		return

	var defs: Dictionary = GameManager.get_upgrade_definitions_world_1()
	if not defs.has(upgrade_key):
		return
	if not _upgrade_buttons.has(upgrade_key):
		return

	var def: Dictionary = defs[upgrade_key]
	var level: int = GameManager.get_upgrade_level(upgrade_key)
	var max_level: int = int(def.get("max_level", 1))
	var base_cost: int = int(def.get("base_cost", 1))
	var path_rate: String = String(def.get("path_rate", GameManager.PATH_MEDIUM))
	var cost: int = GameManager.get_upgrade_cost(base_cost, level, path_rate)
	var display_name: String = String(def.get("display_name", upgrade_key))
	var description: String = String(def.get("description", ""))

	var cost_text := "Cost %d" % cost
	if level >= max_level:
		cost_text = "MAX"

	var node: Control = _upgrade_buttons[upgrade_key] as Control
	var icon: Texture2D = null
	if "icon_texture" in node:
		icon = node.icon_texture

	var icon_top_center_global := node.global_position + Vector2(node.size.x * 0.5, 0.0)

	if hover_tooltip.has_method("show_upgrade_tooltip"):
		hover_tooltip.show_upgrade_tooltip(
			display_name,
			description,
			level,
			max_level,
			cost_text,
			icon_top_center_global,
			icon,
			node.size
		)
	else:
		hover_tooltip.visible = true
		hover_tooltip.global_position = icon_top_center_global


func _on_upgrade_hover_ended() -> void:
	_hovered_upgrade_key = ""
	_hovered_mouse_pos = Vector2.ZERO

	if hover_tooltip == null:
		return

	if hover_tooltip.has_method("hide_tooltip"):
		hover_tooltip.hide_tooltip()
	else:
		hover_tooltip.visible = false


func _show_upgrade_tutorial_if_needed() -> void:
	if GameManager.has_seen_tutorial(TUTORIAL_UPGRADE_SCREEN):
		return

	var overlay := Control.new()
	overlay.name = "UpgradeTutorialPopup"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 3000
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	panel.add_theme_stylebox_override("panel", _create_upgrade_card_style())
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var eyebrow := Label.new()
	eyebrow.text = "UPGRADE TUTORIAL"
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", Color(0.55, 0.83, 1.0, 0.95))
	content.add_child(eyebrow)

	var title := Label.new()
	title.text = "Turn Scrap Into Better Defenses"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.96, 0.84, 1.0))
	content.add_child(title)

	var body := Label.new()
	body.text = "Shoot down enemy missiles to earn scrap. Spend that scrap here to unlock stronger cannons, faster fire rates, and support systems for the next run."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(450.0, 0.0)
	body.add_theme_font_size_override("font_size", 19)
	body.add_theme_color_override("font_color", Color(0.86, 0.92, 1.0, 0.96))
	content.add_child(body)

	var hint := Label.new()
	hint.text = "Pick an upgrade, then hit Continue when you're ready."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 17)
	hint.add_theme_color_override("font_color", Color(0.72, 0.84, 0.96, 0.9))
	content.add_child(hint)

	var continue_button := Button.new()
	continue_button.text = "Continue"
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	continue_button.focus_mode = Control.FOCUS_NONE
	continue_button.add_theme_color_override("font_color", Color(0.07, 0.1, 0.16, 1.0))
	continue_button.add_theme_color_override("font_hover_color", Color(0.07, 0.1, 0.16, 1.0))
	continue_button.add_theme_color_override("font_pressed_color", Color(0.07, 0.1, 0.16, 1.0))
	continue_button.add_theme_stylebox_override("normal", _create_upgrade_button_style(Color(0.96, 0.84, 0.48, 1.0)))
	continue_button.add_theme_stylebox_override("hover", _create_upgrade_button_style(Color(1.0, 0.89, 0.56, 1.0)))
	continue_button.add_theme_stylebox_override("pressed", _create_upgrade_button_style(Color(0.9, 0.76, 0.42, 1.0)))
	continue_button.pressed.connect(func() -> void:
		if is_instance_valid(overlay):
			overlay.queue_free()
	)
	content.add_child(continue_button)

	panel.modulate.a = 0.0
	panel.scale = Vector2(0.95, 0.95)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.parallel().tween_property(panel, "scale", Vector2.ONE, 0.2)
	GameManager.mark_tutorial_seen(TUTORIAL_UPGRADE_SCREEN)


func _create_upgrade_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.12, 0.94)
	style.border_color = Color(0.38, 0.67, 1.0, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	return style


func _create_upgrade_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	style.set_content_margin(SIDE_LEFT, 18)
	style.set_content_margin(SIDE_TOP, 10)
	style.set_content_margin(SIDE_RIGHT, 18)
	style.set_content_margin(SIDE_BOTTOM, 10)
	return style


func continue_game() -> void:
	GameManager.continue_from_upgrades()


func _on_save_and_quit_pressed() -> void:
	GameManager.save_game()
	get_tree().change_scene_to_file("res://Scene/MainMenu.tscn")


func _on_back_to_world_select_pressed() -> void:
	GameManager.save_game()
	get_tree().change_scene_to_file("res://Scene/WorldSelect.tscn")


func _get_tree_connections() -> Array:
	return _connections


func _get_tree_buttons() -> Dictionary:
	return _upgrade_buttons


func _is_connection_active(from_key: String, to_key: String) -> bool:
	if not _upgrade_buttons.has(from_key) or not _upgrade_buttons.has(to_key):
		return false

	var from_level: int = GameManager.get_upgrade_level(from_key)
	var to_node: Node = _upgrade_buttons[to_key]
	var to_visible: bool = true

	if to_node is CanvasItem:
		to_visible = (to_node as CanvasItem).visible

	return from_level > 0 and to_visible
