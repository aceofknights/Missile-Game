extends RefCounted
class_name BossEntranceUtils


static func play_intro(boss: Node2D, flash_node: Node2D = null) -> void:
	if boss == null or not is_instance_valid(boss):
		return

	var current_scene := boss.get_tree().current_scene
	var prelude_duration: float = 0.0
	if current_scene != null and current_scene.has_method("get_boss_arrival_shake_duration"):
		prelude_duration = current_scene.get_boss_arrival_shake_duration()
	if current_scene != null and current_scene.has_method("start_screen_shake"):
		var prelude_strength: float = 0.0
		if current_scene.has_method("get_boss_arrival_shake_strength"):
			prelude_strength = current_scene.get_boss_arrival_shake_strength()
		current_scene.start_screen_shake(prelude_duration, prelude_strength)

	var viewport := boss.get_viewport_rect().size
	var target_position := boss.global_position
	var from_left := randf() < 0.5
	var side_sign := 1.0 if from_left else -1.0
	var start_offset_x := randf_range(220.0, 360.0)
	var start_position := Vector2(
		-start_offset_x if from_left else viewport.x + start_offset_x,
		clampf(target_position.y + randf_range(-85.0, 70.0), 52.0, maxf(90.0, viewport.y * 0.4))
	)
	var overshoot_position := Vector2(
		target_position.x + randf_range(55.0, 135.0) * side_sign,
		clampf(target_position.y + randf_range(-28.0, 24.0), 52.0, maxf(96.0, viewport.y * 0.42))
	)
	var bank_angle := deg_to_rad(randf_range(9.0, 18.0) * side_sign)
	var drift_angle := deg_to_rad(randf_range(-3.0, 3.0))
	var rush_duration := randf_range(0.78, 1.08)
	var settle_duration := randf_range(0.28, 0.44)
	var hold_duration := randf_range(0.10, 0.20)
	var boss_base_scale := boss.scale
	var intro_scale := boss_base_scale * randf_range(0.9, 0.96)
	var flash_base_scale := flash_node.scale if flash_node != null else Vector2.ONE

	boss.visible = false
	if prelude_duration > 0.0:
		await boss.get_tree().create_timer(prelude_duration, true, false, true).timeout

	boss.global_position = start_position
	boss.scale = intro_scale
	boss.rotation = bank_angle
	boss.visible = true

	if flash_node != null:
		flash_node.scale = flash_base_scale * randf_range(0.96, 1.08)

	var rush_tween := boss.create_tween()
	rush_tween.set_parallel(true)
	rush_tween.tween_property(boss, "global_position", overshoot_position, rush_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rush_tween.tween_property(boss, "rotation", drift_angle, rush_duration * 0.82).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	rush_tween.tween_property(boss, "scale", boss_base_scale * 1.03, rush_duration * 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if flash_node != null:
		rush_tween.tween_property(flash_node, "scale", flash_base_scale * 1.1, rush_duration * 0.62).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await rush_tween.finished

	var settle_tween := boss.create_tween()
	settle_tween.set_parallel(true)
	settle_tween.tween_property(boss, "global_position", target_position, settle_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	settle_tween.tween_property(boss, "rotation", 0.0, settle_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	settle_tween.tween_property(boss, "scale", boss_base_scale, settle_duration).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	if flash_node != null:
		settle_tween.tween_property(flash_node, "scale", flash_base_scale, settle_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await settle_tween.finished

	GameManager.trigger_hit_stop(0.18, 0.05)
	await boss.get_tree().create_timer(hold_duration, true, false, true).timeout
