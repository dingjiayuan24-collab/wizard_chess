extends Node2D

@export var human_scenes: Array[PackedScene]
@export var demon_scenes: Array[PackedScene]

## 与 Piece.Type 顺序一致：王、后、车、象、马、兵（编辑器数组被清空或错位时使用）
const _FALLBACK_HUMAN_SCENES: Array[PackedScene] = [
	preload("res://scenes/king_human.tscn"),
	preload("res://scenes/queen_human.tscn"),
	preload("res://scenes/rook_human.tscn"),
	preload("res://scenes/bishop_human.tscn"),
	preload("res://scenes/knight_human.tscn"),
	preload("res://scenes/pawn_human.tscn"),
]
const _FALLBACK_DEMON_SCENES: Array[PackedScene] = [
	preload("res://scenes/king_demon.tscn"),
	preload("res://scenes/queen_demon.tscn"),
	preload("res://scenes/rook_demon.tscn"),
	preload("res://scenes/bishop_demon.tscn"),
	preload("res://scenes/knight_demon.tscn"),
	preload("res://scenes/pawn_demon.tscn"),
]
const SKILL_FIREBALL_SCENE: PackedScene = preload("res://scenes/skill_fire_ball.tscn")
const SKILL_SHIELD_SCENE: PackedScene = preload("res://scenes/skill_arcane_shield.tscn")
const SKILL_TIME_LOCK_SCENE: PackedScene = preload("res://scenes/skill_time_lock.tscn")
const MAX_ENERGY := 5
const START_ENERGY := 3
const SKILL_FIREBALL_COST := 2
const SKILL_SHIELD_COST := 1
const SKILL_TIMELOCK_COST := 2
const SKILL_FIREBALL_CD := 4
const SKILL_SHIELD_CD := 2
const SKILL_TIMELOCK_CD := 3

enum SkillType { NONE, FIREBALL, SHIELD, TIME_LOCK }
## 棋盘格左上角（与棋盘贴图对齐；256×256 图、8 格时为 (-128,-128)）
@export var grid_top_left: Vector2 = Vector2(-128, -128)
## 单格边长（像素）；256 宽÷8 格 = 32
@export var cell_size: float = 32.0
## 在贴图仍对不齐时微调整体偏移
@export var grid_offset: Vector2 = Vector2.ZERO
## 棋子素材帧高度（用于把 48px 棋子缩放到与格子匹配）
@export var piece_sprite_base_size: float = 48.0
## 棋子落在格子上后的额外偏移（像素），用于微调“脚底”对齐
@export var piece_anchor_offset: Vector2 = Vector2.ZERO
@export var move_duration: float = 0.38
const INVALID_EP := Vector2i(-1, -1)

const KNIGHT_DELTAS: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
	Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1),
]
const KING_DELTAS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const ROOK_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const BISHOP_DIRS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const QUEEN_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

const BACK_ROW = [
	Piece.Type.ROOK, Piece.Type.KNIGHT, Piece.Type.BISHOP,
	Piece.Type.QUEEN, Piece.Type.KING,
	Piece.Type.BISHOP, Piece.Type.KNIGHT, Piece.Type.ROOK
]

var board: Array = []
var selected: Piece = null
var current_team: Piece.Team = Piece.Team.HUMAN
var legal_moves: Array = []
var highlight_nodes: Array = []
var en_passant_square: Vector2i = INVALID_EP
var busy: bool = false
var game_over: bool = false
var selected_skill: SkillType = SkillType.NONE
var shield_nodes: Dictionary = {} # key: piece instance_id, value: Node2D
var time_lock_turns: Dictionary = {} # key: piece instance_id, value: int
var human_energy: int = START_ENERGY
var demon_energy: int = START_ENERGY
var human_cooldowns: Dictionary = {}
var demon_cooldowns: Dictionary = {}
var skill_used_this_turn: bool = false
var hover_bp: Vector2i = INVALID_EP

@onready var status_label: Label = $"../../UI/StatusStrip/StatusLabel"
@onready var human_energy_bar: ProgressBar = $"../../UI/LeftPanel/MarginRoot/MainColumn/EnergyBlock/HumanRow/HumanEnergyBar"
@onready var demon_energy_bar: ProgressBar = $"../../UI/LeftPanel/MarginRoot/MainColumn/EnergyBlock/DemonRow/DemonEnergyBar"
@onready var fire_cd_bar: ProgressBar = $"../../UI/LeftPanel/MarginRoot/MainColumn/CooldownBlock/FireRow/FireCdBar"
@onready var shield_cd_bar: ProgressBar = $"../../UI/LeftPanel/MarginRoot/MainColumn/CooldownBlock/ShieldRow/ShieldCdBar"
@onready var time_cd_bar: ProgressBar = $"../../UI/LeftPanel/MarginRoot/MainColumn/CooldownBlock/TimeRow/TimeCdBar"
@onready var cast_status_label: Label = $"../../UI/LeftPanel/MarginRoot/MainColumn/CooldownBlock/CastStatusLabel"
@onready var fire_btn: Button = $"../../UI/RightPanel/MarginRoot/Column/ButtonVBox/FireballButton"
@onready var shield_btn: Button = $"../../UI/RightPanel/MarginRoot/Column/ButtonVBox/ShieldButton"
@onready var lock_btn: Button = $"../../UI/RightPanel/MarginRoot/Column/ButtonVBox/TimeLockButton"
@onready var cancel_btn: Button = $"../../UI/RightPanel/MarginRoot/Column/ButtonVBox/CancelSkillButton"

var highlight_layer: Node2D


func _ready() -> void:
	highlight_layer = get_node_or_null("HighlightLayer") as Node2D
	if highlight_layer == null:
		highlight_layer = Node2D.new()
		highlight_layer.name = "HighlightLayer"
		add_child(highlight_layer)
	highlight_layer.z_index = 20
	if fire_btn and not fire_btn.pressed.is_connected(_on_fireball_btn_pressed):
		fire_btn.pressed.connect(_on_fireball_btn_pressed)
	if shield_btn and not shield_btn.pressed.is_connected(_on_shield_btn_pressed):
		shield_btn.pressed.connect(_on_shield_btn_pressed)
	if lock_btn and not lock_btn.pressed.is_connected(_on_time_lock_btn_pressed):
		lock_btn.pressed.connect(_on_time_lock_btn_pressed)
	if cancel_btn and not cancel_btn.pressed.is_connected(_on_cancel_btn_pressed):
		cancel_btn.pressed.connect(_on_cancel_btn_pressed)
	init_board()
	spawn_pieces()
	_refresh_status()
	_refresh_skill_ui()


func _on_fireball_btn_pressed() -> void:
	_choose_skill(SkillType.FIREBALL)


func _on_shield_btn_pressed() -> void:
	_choose_skill(SkillType.SHIELD)


func _on_time_lock_btn_pressed() -> void:
	_choose_skill(SkillType.TIME_LOCK)


func _on_cancel_btn_pressed() -> void:
	selected_skill = SkillType.NONE
	clear_highlights()
	_refresh_status()
	_refresh_skill_ui()


func _choose_skill(skill: SkillType) -> void:
	if game_over or busy:
		return
	if selected_skill == skill:
		selected_skill = SkillType.NONE
		clear_highlights()
		_refresh_status()
		_refresh_skill_ui()
		return
	if not _can_use_skill(skill):
		_refresh_status()
		_refresh_skill_ui()
		return
	selected_skill = skill
	deselect()
	_update_skill_hover_preview()
	_refresh_status()
	_refresh_skill_ui()


func _current_energy() -> int:
	return human_energy if current_team == Piece.Team.HUMAN else demon_energy


func _set_current_energy(v: int) -> void:
	if current_team == Piece.Team.HUMAN:
		human_energy = v
	else:
		demon_energy = v


func _get_cd_map(team: Piece.Team) -> Dictionary:
	return human_cooldowns if team == Piece.Team.HUMAN else demon_cooldowns


func _skill_cost(skill: SkillType) -> int:
	match skill:
		SkillType.FIREBALL:
			return SKILL_FIREBALL_COST
		SkillType.SHIELD:
			return SKILL_SHIELD_COST
		SkillType.TIME_LOCK:
			return SKILL_TIMELOCK_COST
		_:
			return 0


func _skill_cooldown(skill: SkillType) -> int:
	match skill:
		SkillType.FIREBALL:
			return SKILL_FIREBALL_CD
		SkillType.SHIELD:
			return SKILL_SHIELD_CD
		SkillType.TIME_LOCK:
			return SKILL_TIMELOCK_CD
		_:
			return 0


func _skill_name(skill: SkillType) -> String:
	match skill:
		SkillType.FIREBALL:
			return "Fireball"
		SkillType.SHIELD:
			return "Shield"
		SkillType.TIME_LOCK:
			return "TimeLock"
		_:
			return "-"


func _current_skill_cd(skill: SkillType) -> int:
	var cds := _get_cd_map(current_team)
	return int(cds.get(int(skill), 0))


func _can_use_skill(skill: SkillType) -> bool:
	if skill == SkillType.NONE:
		return true
	if skill_used_this_turn:
		return false
	if _current_energy() < _skill_cost(skill):
		return false
	if _current_skill_cd(skill) > 0:
		return false
	return true


func _spend_skill(skill: SkillType) -> void:
	_set_current_energy(maxi(0, _current_energy() - _skill_cost(skill)))
	var cds := _get_cd_map(current_team)
	cds[int(skill)] = _skill_cooldown(skill)
	if current_team == Piece.Team.HUMAN:
		human_cooldowns = cds
	else:
		demon_cooldowns = cds
	skill_used_this_turn = true
	_refresh_skill_ui()


func _tick_cooldowns_for_team(team: Piece.Team) -> void:
	var cds := _get_cd_map(team)
	var keys := cds.keys()
	for k in keys:
		var left := int(cds[k]) - 1
		if left <= 0:
			cds.erase(k)
		else:
			cds[k] = left
	if team == Piece.Team.HUMAN:
		human_cooldowns = cds
	else:
		demon_cooldowns = cds


func _regen_energy_for_team(team: Piece.Team) -> void:
	if team == Piece.Team.HUMAN:
		human_energy = mini(MAX_ENERGY, human_energy + 1)
	else:
		demon_energy = mini(MAX_ENERGY, demon_energy + 1)


func _refresh_skill_ui() -> void:
	if human_energy_bar:
		human_energy_bar.max_value = MAX_ENERGY
		human_energy_bar.value = human_energy
	if demon_energy_bar:
		demon_energy_bar.max_value = MAX_ENERGY
		demon_energy_bar.value = demon_energy
	var cds := _get_cd_map(current_team)
	var fb_cd := int(cds.get(int(SkillType.FIREBALL), 0))
	var sh_cd := int(cds.get(int(SkillType.SHIELD), 0))
	var tl_cd := int(cds.get(int(SkillType.TIME_LOCK), 0))
	var side := "Human" if current_team == Piece.Team.HUMAN else "Demon"
	var sel_name := _skill_name(selected_skill)
	var cast_state := "USED" if skill_used_this_turn else "READY"
	if fire_cd_bar:
		fire_cd_bar.max_value = SKILL_FIREBALL_CD
		fire_cd_bar.value = fb_cd
	if shield_cd_bar:
		shield_cd_bar.max_value = SKILL_SHIELD_CD
		shield_cd_bar.value = sh_cd
	if time_cd_bar:
		time_cd_bar.max_value = SKILL_TIMELOCK_CD
		time_cd_bar.value = tl_cd
	if cast_status_label:
		cast_status_label.text = "Turn: %s | Cast: %s | Selected: %s" % [side, cast_state, sel_name]
	if fire_btn:
		var fb_sel := ">" if selected_skill == SkillType.FIREBALL else ""
		fire_btn.text = "%s1 Fireball (%dE)" % [fb_sel, SKILL_FIREBALL_COST]
		fire_btn.disabled = not _can_use_skill(SkillType.FIREBALL)
	if shield_btn:
		var sh_sel := ">" if selected_skill == SkillType.SHIELD else ""
		shield_btn.text = "%s2 Shield (%dE)" % [sh_sel, SKILL_SHIELD_COST]
		shield_btn.disabled = not _can_use_skill(SkillType.SHIELD)
	if lock_btn:
		var tl_sel := ">" if selected_skill == SkillType.TIME_LOCK else ""
		lock_btn.text = "%s3 Time Lock (%dE)" % [tl_sel, SKILL_TIMELOCK_COST]
		lock_btn.disabled = not _can_use_skill(SkillType.TIME_LOCK)


func init_board() -> void:
	board = []
	for _r in 8:
		var row: Array = []
		row.resize(8)
		board.append(row)


func board_to_pixel(bp: Vector2i) -> Vector2:
	var cs := cell_size
	return grid_top_left + grid_offset + Vector2(
		bp.x * cs + cs * 0.5,
		bp.y * cs + cs * 0.5
	)


func piece_cell_pos(bp: Vector2i) -> Vector2:
	return board_to_pixel(bp) + piece_anchor_offset


func _piece_scale() -> float:
	return cell_size / maxf(piece_sprite_base_size, 1.0)


func _apply_piece_scale(p: Piece) -> void:
	var s := _piece_scale()
	p.scale = Vector2(s, s)


func pixel_to_board(px: Vector2) -> Vector2i:
	var rel := px - grid_top_left - grid_offset
	var cs := cell_size
	return Vector2i(int(rel.x / cs), int(rel.y / cs))


func in_bounds(bp: Vector2i) -> bool:
	return bp.x >= 0 and bp.x < 8 and bp.y >= 0 and bp.y < 8


func spawn_pieces() -> void:
	for c in 8:
		spawn(BACK_ROW[c], Piece.Team.DEMON, Vector2i(c, 0))
		spawn(Piece.Type.PAWN, Piece.Team.DEMON, Vector2i(c, 1))
		spawn(Piece.Type.PAWN, Piece.Team.HUMAN, Vector2i(c, 6))
		spawn(BACK_ROW[c], Piece.Team.HUMAN, Vector2i(c, 7))


func _resolve_piece_scene(team: Piece.Team, t: Piece.Type) -> PackedScene:
	var idx := int(t)
	var arr: Array = human_scenes if team == Piece.Team.HUMAN else demon_scenes
	if arr != null and idx < arr.size() and arr[idx] != null:
		return arr[idx]
	var fb: Array[PackedScene] = _FALLBACK_HUMAN_SCENES if team == Piece.Team.HUMAN else _FALLBACK_DEMON_SCENES
	return fb[idx]


func spawn(type: Piece.Type, team: Piece.Team, bp: Vector2i) -> void:
	var scene: PackedScene = _resolve_piece_scene(team, type)
	var p: Piece = scene.instantiate()
	p.type = type
	p.team = team
	p.board_pos = bp
	p.has_moved = false
	_apply_piece_scale(p)
	p.position = piece_cell_pos(bp)
	add_child(p)
	board[bp.y][bp.x] = p


func _input(event: InputEvent) -> void:
	if busy or game_over:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_skill_hotkey(event)
		return
	if event is InputEventMouseMotion:
		hover_bp = pixel_to_board(get_local_mouse_position())
		if selected_skill != SkillType.NONE:
			_update_skill_hover_preview()
	if event is InputEventMouseButton and event.pressed:
		var bp := pixel_to_board(get_local_mouse_position())
		if not in_bounds(bp):
			return
		handle_click(bp)


func _handle_skill_hotkey(event: InputEventKey) -> void:
	match event.keycode:
		KEY_1:
			_choose_skill(SkillType.FIREBALL)
		KEY_2:
			_choose_skill(SkillType.SHIELD)
		KEY_3:
			_choose_skill(SkillType.TIME_LOCK)
		KEY_ESCAPE, KEY_0:
			selected_skill = SkillType.NONE
			clear_highlights()
			_refresh_status()
			_refresh_skill_ui()
		_:
			return


func handle_click(bp: Vector2i) -> void:
	var target: Piece = board[bp.y][bp.x]
	if selected_skill != SkillType.NONE:
		await _handle_skill_click(bp, target)
		return

	if selected == null:
		if target != null and target.team == current_team:
			selected = target
			selected.modulate = Color(1.22, 1.22, 1.08)
			selected.set_state("run")
			legal_moves = get_legal_moves(selected)
			show_highlights(legal_moves)
	else:
		var chosen: Dictionary = _move_to_square(bp)
		if not chosen.is_empty():
			await _execute_move(selected, chosen)
		else:
			deselect()
			if target != null and target.team == current_team:
				selected = target
				selected.modulate = Color(1.22, 1.22, 1.08)
				selected.set_state("run")
				legal_moves = get_legal_moves(selected)
				show_highlights(legal_moves)


func _is_skill_target_valid(skill: SkillType, bp: Vector2i, target: Piece) -> bool:
	match skill:
		SkillType.FIREBALL:
			return target != null and target.team != current_team and target.type != Piece.Type.KING
		SkillType.SHIELD:
			return target != null and target.team == current_team and not _has_shield(target)
		SkillType.TIME_LOCK:
			return target != null and target.team != current_team and target.type != Piece.Type.KING
		_:
			return false


func _update_skill_hover_preview() -> void:
	clear_highlights()
	if selected_skill == SkillType.NONE:
		return
	if not _can_use_skill(selected_skill):
		return
	for y in 8:
		for x in 8:
			var bp := Vector2i(x, y)
			var t: Piece = board[y][x]
			if _is_skill_target_valid(selected_skill, bp, t):
				_add_cell_highlight(bp, Color(0.46, 0.57, 0.62, 0.14))
	if in_bounds(hover_bp):
		var hv_t: Piece = board[hover_bp.y][hover_bp.x]
		var ok := _is_skill_target_valid(selected_skill, hover_bp, hv_t)
		_add_cell_highlight(hover_bp, Color(0.43, 0.76, 0.5, 0.3) if ok else Color(0.75, 0.43, 0.43, 0.3))


func _handle_skill_click(bp: Vector2i, target: Piece) -> void:
	if not _can_use_skill(selected_skill):
		_refresh_status()
		_refresh_skill_ui()
		_update_skill_hover_preview()
		return
	var cast_ok := false
	match selected_skill:
		SkillType.FIREBALL:
			cast_ok = await _cast_fireball(bp, target)
		SkillType.SHIELD:
			cast_ok = await _cast_shield(target)
		SkillType.TIME_LOCK:
			cast_ok = await _cast_time_lock(bp, target)
		_:
			cast_ok = false
	if not cast_ok:
		_update_skill_hover_preview()
		return
	_spend_skill(selected_skill)
	selected_skill = SkillType.NONE
	deselect()
	switch_turn()
	_end_game_check()
	if not game_over:
		_refresh_status()
	_refresh_skill_ui()


func _cast_fireball(bp: Vector2i, target: Piece) -> bool:
	if target == null or target.team == current_team or target.type == Piece.Type.KING:
		return false
	busy = true
	await _play_skill_vfx_once(SKILL_FIREBALL_SCENE, board_to_pixel(bp))
	if _has_shield(target):
		_consume_shield(target)
	else:
		board[bp.y][bp.x] = null
		_clear_piece_effects(target)
		await target.die()
	busy = false
	return true


func _cast_shield(target: Piece) -> bool:
	if target == null or target.team != current_team or _has_shield(target):
		return false
	busy = true
	var id := target.get_instance_id()
	var fx: Node2D = SKILL_SHIELD_SCENE.instantiate()
	fx.z_index = 2
	target.add_child(fx)
	fx.position = Vector2.ZERO
	var sprite := fx.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite:
		sprite.play("shield")
	shield_nodes[id] = fx
	busy = false
	return true


func _cast_time_lock(bp: Vector2i, target: Piece) -> bool:
	if target == null or target.team == current_team or target.type == Piece.Type.KING:
		return false
	busy = true
	await _play_skill_vfx_once(SKILL_TIME_LOCK_SCENE, board_to_pixel(bp))
	time_lock_turns[target.get_instance_id()] = 1
	target.modulate = Color(0.78, 0.9, 1.0, 1.0)
	busy = false
	return true


func _play_skill_vfx_once(scene: PackedScene, world_pos: Vector2) -> void:
	var fx: Node2D = scene.instantiate()
	fx.z_index = 35
	add_child(fx)
	fx.position = world_pos
	var sprite := fx.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite:
		sprite.play()
		var duration := _sprite_animation_duration(sprite)
		await get_tree().create_timer(duration).timeout
	else:
		await get_tree().create_timer(0.45).timeout
	fx.queue_free()


func _sprite_animation_duration(sprite: AnimatedSprite2D) -> float:
	var frames := sprite.sprite_frames
	if frames == null:
		return 0.45
	var anim := sprite.animation
	var count := frames.get_frame_count(anim)
	var speed := maxf(frames.get_animation_speed(anim), 1.0)
	return maxf(float(count) / speed, 0.35)


func _has_shield(p: Piece) -> bool:
	return shield_nodes.has(p.get_instance_id())


func _consume_shield(p: Piece) -> void:
	var id := p.get_instance_id()
	var fx: Node2D = shield_nodes.get(id, null)
	if is_instance_valid(fx):
		fx.queue_free()
	shield_nodes.erase(id)


func _clear_piece_effects(p: Piece) -> void:
	if p == null:
		return
	_consume_shield(p)
	time_lock_turns.erase(p.get_instance_id())


func _move_to_square(bp: Vector2i) -> Dictionary:
	for m in legal_moves:
		if m["to"] == bp:
			return m
	return {}


func deselect() -> void:
	if selected:
		selected.modulate = Color.WHITE
		selected.set_state("idle")
		selected = null
	legal_moves = []
	clear_highlights()


func show_highlights(moves: Array) -> void:
	clear_highlights()
	if selected:
		_add_cell_highlight(selected.board_pos, Color(0.72, 0.64, 0.48, 0.22))
	for m in moves:
		var bp: Vector2i = m["to"]
		var occupant: Piece = board[bp.y][bp.x]
		var col := Color(0.62, 0.42, 0.38, 0.24) if occupant else Color(0.42, 0.55, 0.48, 0.2)
		_add_cell_highlight(bp, col)


func _add_cell_highlight(bp: Vector2i, col: Color) -> void:
	var h := ColorRect.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := cell_size
	h.size = Vector2(cs, cs)
	h.position = board_to_pixel(bp) - Vector2(cs * 0.5, cs * 0.5)
	h.color = col
	h.z_index = 0
	highlight_layer.add_child(h)
	highlight_nodes.append(h)


func clear_highlights() -> void:
	for h in highlight_nodes:
		h.queue_free()
	highlight_nodes.clear()


func _execute_move(piece: Piece, move: Dictionary) -> void:
	busy = true
	var from: Vector2i = piece.board_pos
	var to: Vector2i = move["to"]
	var castle: int = move.get("castle", 0)
	var is_ep: bool = move.get("ep", false)

	if castle != 0:
		await _animate_castle(piece, move)
		en_passant_square = INVALID_EP
		deselect()
		switch_turn()
		_end_game_check()
		if not game_over:
			_refresh_status()
		busy = false
		return

	var victim: Piece = null
	var victim_pos: Vector2i = Vector2i.ZERO
	if is_ep:
		victim_pos = Vector2i(to.x, from.y)
		victim = board[victim_pos.y][victim_pos.x]
	elif board[to.y][to.x] != null:
		victim = board[to.y][to.x]

	if victim != null and _has_shield(victim):
		await piece.play_attack()
		_consume_shield(victim)
		deselect()
		switch_turn()
		_end_game_check()
		if not game_over:
			_refresh_status()
		busy = false
		return

	board[from.y][from.x] = null

	if victim != null:
		await piece.tween_to_position(piece_cell_pos(to), move_duration)
		await piece.play_attack()
		if is_ep:
			board[victim_pos.y][victim_pos.x] = null
		_clear_piece_effects(victim)
		await victim.die()
		_place_piece(piece, to)
	else:
		await piece.tween_to_position(piece_cell_pos(to), move_duration)
		_place_piece(piece, to)

	if piece.type == Piece.Type.PAWN and abs(to.y - from.y) == 2:
		en_passant_square = Vector2i(from.x, (from.y + to.y) / 2)
	else:
		en_passant_square = INVALID_EP

	if piece.type == Piece.Type.PAWN and _is_promotion_rank(piece.team, to):
		_promote_pawn_at(piece, to)
	else:
		piece.has_moved = true

	deselect()
	switch_turn()
	_end_game_check()
	if not game_over:
		_refresh_status()
	busy = false


func _place_piece(piece: Piece, to: Vector2i) -> void:
	board[to.y][to.x] = piece
	piece.board_pos = to
	piece.position = piece_cell_pos(to)
	piece.set_state("idle")


func _animate_castle(king: Piece, move: Dictionary) -> void:
	var to: Vector2i = move["to"]
	var row: int = 7 if king.team == Piece.Team.HUMAN else 0
	var kside: bool = move.get("castle", 0) == 1
	var rook_from := Vector2i(7, row) if kside else Vector2i(0, row)
	var rook_to := Vector2i(5, row) if kside else Vector2i(3, row)
	var rook: Piece = board[rook_from.y][rook_from.x]
	board[king.board_pos.y][king.board_pos.x] = null
	board[rook_from.y][rook_from.x] = null
	var tw_k := king.create_tween()
	var tw_r := rook.create_tween()
	tw_k.set_trans(Tween.TRANS_QUAD)
	tw_k.set_ease(Tween.EASE_OUT)
	tw_r.set_trans(Tween.TRANS_QUAD)
	tw_r.set_ease(Tween.EASE_OUT)
	king.set_state("run")
	rook.set_state("run")
	tw_k.tween_property(king, "position", piece_cell_pos(to), move_duration)
	tw_r.tween_property(rook, "position", piece_cell_pos(rook_to), move_duration)
	await tw_k.finished
	king.board_pos = to
	rook.board_pos = rook_to
	king.position = piece_cell_pos(to)
	rook.position = piece_cell_pos(rook_to)
	board[to.y][to.x] = king
	board[rook_to.y][rook_to.x] = rook
	king.has_moved = true
	rook.has_moved = true
	king.set_state("idle")
	rook.set_state("idle")


func _is_promotion_rank(team: Piece.Team, to: Vector2i) -> bool:
	return (team == Piece.Team.HUMAN and to.y == 0) or (team == Piece.Team.DEMON and to.y == 7)


func _promote_pawn_at(pawn: Piece, bp: Vector2i) -> void:
	var team := pawn.team
	var q_scene: PackedScene = _resolve_piece_scene(team, Piece.Type.QUEEN)
	var q: Piece = q_scene.instantiate()
	q.type = Piece.Type.QUEEN
	q.team = team
	q.board_pos = bp
	q.has_moved = true
	_apply_piece_scale(q)
	q.position = piece_cell_pos(bp)
	board[bp.y][bp.x] = null
	_clear_piece_effects(pawn)
	pawn.queue_free()
	add_child(q)
	board[bp.y][bp.x] = q
	q.set_state("idle")


func switch_turn() -> void:
	_consume_time_lock_for_team(current_team)
	current_team = Piece.Team.DEMON if current_team == Piece.Team.HUMAN else Piece.Team.HUMAN
	skill_used_this_turn = false
	selected_skill = SkillType.NONE
	_tick_cooldowns_for_team(current_team)
	_regen_energy_for_team(current_team)
	_refresh_skill_ui()


func _consume_time_lock_for_team(team: Piece.Team) -> void:
	var remove_ids: Array = []
	for y in 8:
		for x in 8:
			var p: Piece = board[y][x]
			if p == null or p.team != team:
				continue
			var id := p.get_instance_id()
			if not time_lock_turns.has(id):
				continue
			var left: int = int(time_lock_turns[id]) - 1
			if left <= 0:
				time_lock_turns.erase(id)
				if _has_shield(p):
					p.modulate = Color(1.0, 1.0, 1.0, 1.0)
				remove_ids.append(id)
			else:
				time_lock_turns[id] = left
	for id in remove_ids:
		for y2 in 8:
			for x2 in 8:
				var p2: Piece = board[y2][x2]
				if p2 != null and p2.get_instance_id() == id and not _has_shield(p2):
					p2.modulate = Color.WHITE


func _refresh_status() -> void:
	if not is_instance_valid(status_label):
		return
	if game_over:
		return
	var side := "Human" if current_team == Piece.Team.HUMAN else "Demon"
	var check := is_king_in_check(current_team)
	status_label.text = "%s Play%s" % [side, " (Check!)" if check else ""]


func _end_game_check() -> void:
	var in_check := is_king_in_check(current_team)
	var any_move := _side_has_legal_move(current_team)
	if in_check and not any_move:
		game_over = true
		var winner := "Demon" if current_team == Piece.Team.HUMAN else "Human"
		if status_label:
			status_label.text = "Checkmate! %s wins" % winner
	elif not in_check and not any_move:
		game_over = true
		if status_label:
			status_label.text = "Stalemate — Draw"


func _side_has_legal_move(team: Piece.Team) -> bool:
	for y in 8:
		for x in 8:
			var p: Piece = board[y][x]
			if p != null and p.team == team and not get_legal_moves(p).is_empty():
				return true
	return false


func find_king(team: Piece.Team) -> Piece:
	for y in 8:
		for x in 8:
			var p: Piece = board[y][x]
			if p != null and p.team == team and p.type == Piece.Type.KING:
				return p
	return null


func is_king_in_check(team: Piece.Team) -> bool:
	var k := find_king(team)
	if k == null:
		return true
	var opp := Piece.Team.DEMON if team == Piece.Team.HUMAN else Piece.Team.HUMAN
	return square_attacked(k.board_pos, opp)


func square_attacked(sq: Vector2i, by_team: Piece.Team) -> bool:
	for y in 8:
		for x in 8:
			var p: Piece = board[y][x]
			if p != null and p.team == by_team and attacks_square(p, sq):
				return true
	return false


func attacks_square(p: Piece, sq: Vector2i) -> bool:
	var from := p.board_pos
	match p.type:
		Piece.Type.PAWN:
			var dir := -1 if p.team == Piece.Team.HUMAN else 1
			return sq == from + Vector2i(-1, dir) or sq == from + Vector2i(1, dir)
		Piece.Type.KNIGHT:
			for d in KNIGHT_DELTAS:
				if from + d == sq:
					return true
			return false
		Piece.Type.KING:
			for d in KING_DELTAS:
				if from + d == sq:
					return true
			return false
		Piece.Type.ROOK:
			return _slide_attacks(from, sq, ROOK_DIRS)
		Piece.Type.BISHOP:
			return _slide_attacks(from, sq, BISHOP_DIRS)
		Piece.Type.QUEEN:
			return _slide_attacks(from, sq, QUEEN_DIRS)
	return false


func _slide_attacks(from: Vector2i, sq: Vector2i, dirs: Array[Vector2i]) -> bool:
	for d in dirs:
		var cur := from + d
		while in_bounds(cur):
			if cur == sq:
				return true
			if board[cur.y][cur.x] != null:
				break
			cur += d
	return false


func get_legal_moves(piece: Piece) -> Array:
	if piece.team == current_team and time_lock_turns.has(piece.get_instance_id()):
		return []
	var pseudo := get_pseudo_moves(piece)
	var out: Array = []
	for m in pseudo:
		if not _move_leaves_king_in_check(piece, m):
			out.append(m)
	return out


func _move_leaves_king_in_check(piece: Piece, move: Dictionary) -> bool:
	_simulate_move(piece, move)
	var chk := is_king_in_check(piece.team)
	_unsimulate_move(piece, move)
	return chk


var _sim_from: Vector2i
var _sim_captured: Piece = null
var _sim_ep_victim: Piece = null
var _sim_ep_pos: Vector2i = Vector2i.ZERO
var _sim_cleanup_promo: bool = false


func get_pseudo_moves(piece: Piece) -> Array:
	var moves: Array = []
	match piece.type:
		Piece.Type.PAWN:
			moves = _pawn_pseudo(piece)
		Piece.Type.ROOK:
			moves = _slide_pseudo(piece, ROOK_DIRS)
		Piece.Type.BISHOP:
			moves = _slide_pseudo(piece, BISHOP_DIRS)
		Piece.Type.QUEEN:
			moves = _slide_pseudo(piece, QUEEN_DIRS)
		Piece.Type.KING:
			moves = _king_pseudo(piece)
		Piece.Type.KNIGHT:
			moves = _knight_pseudo(piece)
	return moves


func _slide_pseudo(piece: Piece, dirs: Array[Vector2i]) -> Array:
	var moves: Array = []
	for d in dirs:
		var cur := piece.board_pos + d
		while in_bounds(cur):
			var occ: Piece = board[cur.y][cur.x]
			if occ == null:
				moves.append({"to": cur, "ep": false, "castle": 0})
			elif occ.team != piece.team:
				moves.append({"to": cur, "ep": false, "castle": 0})
				break
			else:
				break
			cur += d
	return moves


func _pawn_dir(team: Piece.Team) -> int:
	return -1 if team == Piece.Team.HUMAN else 1


func _pawn_pseudo(piece: Piece) -> Array:
	var moves: Array = []
	var dir := _pawn_dir(piece.team)
	var start_row := 6 if piece.team == Piece.Team.HUMAN else 1
	var fwd := piece.board_pos + Vector2i(0, dir)

	if in_bounds(fwd) and board[fwd.y][fwd.x] == null:
		moves.append({"to": fwd, "ep": false, "castle": 0})
		if piece.board_pos.y == start_row:
			var fwd2 := piece.board_pos + Vector2i(0, dir * 2)
			if in_bounds(fwd2) and board[fwd2.y][fwd2.x] == null:
				moves.append({"to": fwd2, "ep": false, "castle": 0})

	for dx in [-1, 1]:
		var atk := piece.board_pos + Vector2i(dx, dir)
		if not in_bounds(atk):
			continue
		var occ: Piece = board[atk.y][atk.x]
		if occ != null and occ.team != piece.team:
			moves.append({"to": atk, "ep": false, "castle": 0})

	if en_passant_square != INVALID_EP:
		for dx in [-1, 1]:
			var ep_to := piece.board_pos + Vector2i(dx, dir)
			if ep_to != en_passant_square:
				continue
			if board[ep_to.y][ep_to.x] != null:
				continue
			var vic_pos := Vector2i(ep_to.x, piece.board_pos.y)
			var vic: Piece = board[vic_pos.y][vic_pos.x]
			if vic != null and vic.type == Piece.Type.PAWN and vic.team != piece.team:
				moves.append({"to": ep_to, "ep": true, "castle": 0})
	return moves


func _knight_pseudo(piece: Piece) -> Array:
	var moves: Array = []
	for d in KNIGHT_DELTAS:
		var t := piece.board_pos + d
		if not in_bounds(t):
			continue
		var occ: Piece = board[t.y][t.x]
		if occ == null or occ.team != piece.team:
			moves.append({"to": t, "ep": false, "castle": 0})
	return moves


func _king_pseudo(piece: Piece) -> Array:
	var moves: Array = []
	for d in KING_DELTAS:
		var t := piece.board_pos + d
		if not in_bounds(t):
			continue
		var occ: Piece = board[t.y][t.x]
		if occ == null or occ.team != piece.team:
			moves.append({"to": t, "ep": false, "castle": 0})

	if not piece.has_moved and piece.type == Piece.Type.KING:
		var row := 7 if piece.team == Piece.Team.HUMAN else 0
		if _can_castle_kingside(piece, row):
			moves.append({"to": Vector2i(6, row), "ep": false, "castle": 1})
		if _can_castle_queenside(piece, row):
			moves.append({"to": Vector2i(2, row), "ep": false, "castle": 2})
	return moves


func _can_castle_kingside(king: Piece, row: int) -> bool:
	var rook: Piece = board[row][7]
	if rook == null or rook.type != Piece.Type.ROOK or rook.team != king.team or rook.has_moved:
		return false
	if board[row][5] != null or board[row][6] != null:
		return false
	if is_king_in_check(king.team):
		return false
	var opp := Piece.Team.DEMON if king.team == Piece.Team.HUMAN else Piece.Team.HUMAN
	if square_attacked(Vector2i(5, row), opp) or square_attacked(Vector2i(6, row), opp):
		return false
	return true


func _can_castle_queenside(king: Piece, row: int) -> bool:
	var rook: Piece = board[row][0]
	if rook == null or rook.type != Piece.Type.ROOK or rook.team != king.team or rook.has_moved:
		return false
	if board[row][1] != null or board[row][2] != null or board[row][3] != null:
		return false
	if is_king_in_check(king.team):
		return false
	var opp := Piece.Team.DEMON if king.team == Piece.Team.HUMAN else Piece.Team.HUMAN
	if square_attacked(Vector2i(2, row), opp) or square_attacked(Vector2i(3, row), opp):
		return false
	return true


func _simulate_move(piece: Piece, move: Dictionary) -> void:
	_sim_from = piece.board_pos
	var to: Vector2i = move["to"]
	var castle: int = move.get("castle", 0)
	var is_ep: bool = move.get("ep", false)
	_sim_captured = null
	_sim_cleanup_promo = false

	board[_sim_from.y][_sim_from.x] = null

	if castle != 0:
		var row: int = 7 if piece.team == Piece.Team.HUMAN else 0
		var kside: bool = castle == 1
		var rook_from := Vector2i(7, row) if kside else Vector2i(0, row)
		var rook_to := Vector2i(5, row) if kside else Vector2i(3, row)
		var rook: Piece = board[rook_from.y][rook_from.x]
		board[rook_from.y][rook_from.x] = null
		board[to.y][to.x] = piece
		piece.board_pos = to
		board[rook_to.y][rook_to.x] = rook
		rook.board_pos = rook_to
		return

	if is_ep:
		_sim_ep_pos = Vector2i(to.x, _sim_from.y)
		_sim_ep_victim = board[_sim_ep_pos.y][_sim_ep_pos.x]
		board[_sim_ep_pos.y][_sim_ep_pos.x] = null
		board[to.y][to.x] = piece
		piece.board_pos = to
	else:
		_sim_captured = board[to.y][to.x]
		board[to.y][to.x] = piece
		piece.board_pos = to

	if piece.type == Piece.Type.PAWN and _is_promotion_rank(piece.team, to):
		piece.type = Piece.Type.QUEEN
		_sim_cleanup_promo = true


func _unsimulate_move(piece: Piece, move: Dictionary) -> void:
	var to: Vector2i = move["to"]
	var castle: int = move.get("castle", 0)
	var is_ep: bool = move.get("ep", false)

	if _sim_cleanup_promo:
		piece.type = Piece.Type.PAWN
		_sim_cleanup_promo = false

	if castle != 0:
		var row: int = 7 if piece.team == Piece.Team.HUMAN else 0
		var kside: bool = castle == 1
		var rook_from := Vector2i(7, row) if kside else Vector2i(0, row)
		var rook_to := Vector2i(5, row) if kside else Vector2i(3, row)
		var rook: Piece = board[rook_to.y][rook_to.x]
		board[to.y][to.x] = null
		board[rook_to.y][rook_to.x] = null
		piece.board_pos = Vector2i(4, row)
		board[row][4] = piece
		rook.board_pos = rook_from
		board[rook_from.y][rook_from.x] = rook
		return

	if is_ep:
		board[to.y][to.x] = null
		piece.board_pos = _sim_from
		board[_sim_from.y][_sim_from.x] = piece
		board[_sim_ep_pos.y][_sim_ep_pos.x] = _sim_ep_victim
		_sim_ep_victim = null
		return

	board[to.y][to.x] = _sim_captured
	piece.board_pos = _sim_from
	board[_sim_from.y][_sim_from.x] = piece
