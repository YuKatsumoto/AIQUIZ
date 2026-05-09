extends RefCounted
class_name ItemSystem

## 2Pモード用アイテムシステムの中核ロジック
## アイテムボックスの出現・取得・ストック管理・使用・エフェクト管理を担う

# ─── アイテム種別 ───
enum ItemType {
	NONE = 0,
	THUNDER = 1,   # 相手の移動速度を50%に低下
	FREEZE = 2,    # 相手を一定時間操作不能にする
	REVERSE = 3,   # 相手の左右操作を反転
	GHOST = 4,     # 相手の壁の選択肢テキストを非表示
	DASH = 5,      # 自分の移動速度を2倍に加速
	SHIELD = 6,    # 次に間違ったドアに当たっても1回だけ死なない
	BOMB = 7,      # 自分の前方に爆弾を設置
}

# ─── シグナル ───
signal item_picked_up(player_num: int, item_type: int)
signal item_used(player_num: int, item_type: int, target_num: int)
signal item_effect_started(player_num: int, effect_name: String)
signal item_effect_ended(player_num: int, effect_name: String)
signal bomb_placed(player_num: int, world_z: float, world_x: float)
signal bomb_triggered(victim_num: int)

# ─── 設定定数 ───
const ITEM_BOX_SPACING: float = 30.0  # 壁の間隔と同じ (壁の中間に配置)
const ITEM_BOX_OFFSET_Z: float = 15.0 # 壁からのオフセット (壁の中間)
const ITEM_PICKUP_RADIUS_X: float = 2.0  # X方向の取得判定半径
const ITEM_PICKUP_RADIUS_Z: float = 1.5  # Z方向の取得判定半径
const ITEM_BOX_Y: float = 1.5            # ボックスの浮遊高さ

# アイテム効果の持続時間 (秒)
const THUNDER_DURATION: float = 3.0
const FREEZE_DURATION: float = 1.5
const REVERSE_DURATION: float = 4.0
const DASH_DURATION: float = 3.0
const BOMB_LIFETIME: float = 10.0
const BOMB_TRIGGER_RADIUS: float = 1.5
const BOMB_FREEZE_DURATION: float = 2.0

# 速度補正値
const THUNDER_SPEED_MULT: float = 0.5
const DASH_SPEED_MULT: float = 2.0

# ─── プレイヤーごとの状態 ───
# アイテムストック (1個制限)
var p1_item: int = ItemType.NONE
var p2_item: int = ItemType.NONE

# アクティブエフェクト (被害を受けている側のタイマー)
var _p1_effects: Dictionary = {}  # { "thunder": 残り秒, "freeze": 残り秒, ... }
var _p2_effects: Dictionary = {}

# シールド (使用者側に付与)
var _p1_shield: bool = false
var _p2_shield: bool = false

# ゴースト (被害を受けている側)
var _p1_ghost: bool = false
var _p2_ghost: bool = false

# ボム (ワールド座標)
var _active_bombs: Array[Dictionary] = []  # [{owner: int, x: float, z: float, timer: float}]

# アイテムボックスの取得済みフラグ (壁インデックスベース)
var _picked_up_boxes: Dictionary = {}  # { wall_index: true }

# ─── チューニング参照 ───
var _wall_start_z: float = 22.0
var _wall_spacing: float = 30.0
var _enabled: bool = false

func setup(wall_start_z: float, wall_spacing: float) -> void:
	_wall_start_z = wall_start_z
	_wall_spacing = wall_spacing
	_enabled = true

func is_enabled() -> bool:
	return _enabled

func reset() -> void:
	"""ゲーム開始時にリセット"""
	p1_item = ItemType.NONE
	p2_item = ItemType.NONE
	_p1_effects.clear()
	_p2_effects.clear()
	_p1_shield = false
	_p2_shield = false
	_p1_ghost = false
	_p2_ghost = false
	_active_bombs.clear()
	_picked_up_boxes.clear()

# ─── 毎フレーム更新 ───
func update(dt: float) -> void:
	if not _enabled:
		return
	_tick_effects(_p1_effects, 1, dt)
	_tick_effects(_p2_effects, 2, dt)
	_tick_bombs(dt)

func _tick_effects(effects: Dictionary, player_num: int, dt: float) -> void:
	var expired: Array[String] = []
	for key: String in effects.keys():
		effects[key] -= dt
		if effects[key] <= 0.0:
			expired.append(key)
	for key: String in expired:
		effects.erase(key)
		_on_effect_expired(player_num, key)

func _on_effect_expired(player_num: int, effect_name: String) -> void:
	item_effect_ended.emit(player_num, effect_name)

func _tick_bombs(dt: float) -> void:
	var expired_indices: Array[int] = []
	for i: int in range(_active_bombs.size()):
		_active_bombs[i]["timer"] -= dt
		if _active_bombs[i]["timer"] <= 0.0:
			expired_indices.append(i)
	# 逆順で削除
	for i: int in range(expired_indices.size() - 1, -1, -1):
		_active_bombs.remove_at(expired_indices[i])

# ─── アイテムボックスの位置計算 ───
func get_item_box_z(wall_index: int) -> float:
	"""指定された壁インデックスに対応するアイテムボックスのZ座標"""
	return _wall_start_z + wall_index * _wall_spacing + ITEM_BOX_OFFSET_Z

func is_box_available(wall_index: int) -> bool:
	return not _picked_up_boxes.has(wall_index)

# ─── アイテム取得判定 ───
func check_item_pickup(player_num: int, px: float, pz: float, current_wall_index: int) -> void:
	"""プレイヤーがアイテムボックスの近くにいるかチェックし、取得処理を行う"""
	if not _enabled:
		return
	# ストックが既にある場合は取得しない
	if player_num == 1 and p1_item != ItemType.NONE:
		return
	if player_num == 2 and p2_item != ItemType.NONE:
		return

	# 現在の壁インデックス周辺のボックスをチェック
	for offset: int in range(-1, 3):
		var box_idx: int = current_wall_index + offset
		if box_idx < 0:
			continue
		if not is_box_available(box_idx):
			continue

		var box_z: float = get_item_box_z(box_idx)
		if absf(pz - box_z) <= ITEM_PICKUP_RADIUS_Z and absf(px) <= ITEM_PICKUP_RADIUS_X + 6.0:
			# ピックアップ成功！
			_picked_up_boxes[box_idx] = true
			var item: int = _roll_random_item()
			if player_num == 1:
				p1_item = item
			else:
				p2_item = item
			item_picked_up.emit(player_num, item)
			return

func _roll_random_item() -> int:
	"""ランダムにアイテムを1つ選出"""
	var pool: Array[int] = [
		ItemType.THUNDER,
		ItemType.FREEZE,
		ItemType.REVERSE,
		ItemType.GHOST,
		ItemType.DASH,
		ItemType.SHIELD,
		ItemType.BOMB,
	]
	return pool[randi() % pool.size()]

# ─── アイテム使用 ───
func use_item(player_num: int) -> void:
	"""ストック中のアイテムを発動する"""
	if not _enabled:
		return
	var item: int
	if player_num == 1:
		item = p1_item
		p1_item = ItemType.NONE
	else:
		item = p2_item
		p2_item = ItemType.NONE

	if item == ItemType.NONE:
		return

	var target_num: int = 2 if player_num == 1 else 1
	item_used.emit(player_num, item, target_num)

	match item:
		ItemType.THUNDER:
			_apply_effect(target_num, "thunder", THUNDER_DURATION)
		ItemType.FREEZE:
			_apply_effect(target_num, "freeze", FREEZE_DURATION)
		ItemType.REVERSE:
			_apply_effect(target_num, "reverse", REVERSE_DURATION)
		ItemType.GHOST:
			_set_ghost(target_num, true)
		ItemType.DASH:
			_apply_effect(player_num, "dash", DASH_DURATION)  # 自分に適用
		ItemType.SHIELD:
			_set_shield(player_num, true)
		ItemType.BOMB:
			pass  # ボム設置はgame_stateから座標を渡して呼ぶ

func place_bomb(player_num: int, world_x: float, world_z: float) -> void:
	"""ボムをワールドに設置"""
	var bomb_z: float = world_z + 8.0  # 前方に設置
	_active_bombs.append({
		"owner": player_num,
		"x": world_x,
		"z": bomb_z,
		"timer": BOMB_LIFETIME,
	})
	bomb_placed.emit(player_num, bomb_z, world_x)

func check_bomb_collision(player_num: int, px: float, pz: float) -> void:
	"""プレイヤーがボムに触れたかチェック"""
	if not _enabled:
		return
	for i: int in range(_active_bombs.size() - 1, -1, -1):
		var bomb: Dictionary = _active_bombs[i]
		if bomb["owner"] == player_num:
			continue  # 自分のボムには当たらない
		if absf(px - bomb["x"]) <= BOMB_TRIGGER_RADIUS and absf(pz - bomb["z"]) <= BOMB_TRIGGER_RADIUS:
			# ボム起爆！
			_active_bombs.remove_at(i)
			_apply_effect(player_num, "freeze", BOMB_FREEZE_DURATION)
			bomb_triggered.emit(player_num)
			return

# ─── エフェクト適用 ───
func _apply_effect(player_num: int, effect_name: String, duration: float) -> void:
	var effects: Dictionary = _p1_effects if player_num == 1 else _p2_effects
	# 既にあれば上書き（延長ではなくリセット）
	effects[effect_name] = duration
	item_effect_started.emit(player_num, effect_name)

func _set_shield(player_num: int, enabled: bool) -> void:
	if player_num == 1:
		_p1_shield = enabled
	else:
		_p2_shield = enabled

func _set_ghost(player_num: int, enabled: bool) -> void:
	if player_num == 1:
		_p1_ghost = enabled
	else:
		_p2_ghost = enabled

# ─── 外部から参照するクエリメソッド ───

func get_speed_multiplier(player_num: int) -> float:
	"""プレイヤーの速度補正値を返す（1.0 = 通常）"""
	var effects: Dictionary = _p1_effects if player_num == 1 else _p2_effects
	var mult: float = 1.0
	if effects.has("thunder"):
		mult *= THUNDER_SPEED_MULT
	if effects.has("dash"):
		mult *= DASH_SPEED_MULT
	return mult

func is_input_reversed(player_num: int) -> bool:
	"""入力が反転されているか"""
	var effects: Dictionary = _p1_effects if player_num == 1 else _p2_effects
	return effects.has("reverse")

func is_frozen(player_num: int) -> bool:
	"""フリーズ中か（操作完全不能）"""
	var effects: Dictionary = _p1_effects if player_num == 1 else _p2_effects
	return effects.has("freeze")

func has_shield(player_num: int) -> bool:
	"""シールドが有効か"""
	return _p1_shield if player_num == 1 else _p2_shield

func consume_shield(player_num: int) -> void:
	"""シールドを消費（壁衝突で死亡回避時に呼ぶ）"""
	_set_shield(player_num, false)
	item_effect_ended.emit(player_num, "shield")

func is_text_hidden(player_num: int) -> bool:
	"""ゴーストで選択肢が隠されているか"""
	return _p1_ghost if player_num == 1 else _p2_ghost

func clear_ghost(player_num: int) -> void:
	"""ゴースト効果を解除（壁通過時に呼ぶ）"""
	_set_ghost(player_num, false)
	item_effect_ended.emit(player_num, "ghost")

func has_any_effect(player_num: int) -> bool:
	"""何らかのエフェクトが適用中か"""
	var effects: Dictionary = _p1_effects if player_num == 1 else _p2_effects
	if not effects.is_empty():
		return true
	if player_num == 1:
		return _p1_shield or _p1_ghost
	else:
		return _p2_shield or _p2_ghost

func get_active_effects(player_num: int) -> Array[String]:
	"""アクティブなエフェクト名の配列"""
	var result: Array[String] = []
	var effects: Dictionary = _p1_effects if player_num == 1 else _p2_effects
	for key: String in effects.keys():
		result.append(key)
	if has_shield(player_num):
		result.append("shield")
	if is_text_hidden(player_num):
		result.append("ghost")
	return result

func get_item_name(item_type: int) -> String:
	"""アイテム名を日本語で返す"""
	match item_type:
		ItemType.THUNDER: return "⚡ サンダー"
		ItemType.FREEZE: return "🧊 フリーズ"
		ItemType.REVERSE: return "🌀 リバース"
		ItemType.GHOST: return "👻 オバケ"
		ItemType.DASH: return "🚀 ダッシュ"
		ItemType.SHIELD: return "🛡️ シールド"
		ItemType.BOMB: return "💣 ボム"
		_: return ""

func get_item_emoji(item_type: int) -> String:
	"""アイテムの絵文字を返す"""
	match item_type:
		ItemType.THUNDER: return "⚡"
		ItemType.FREEZE: return "🧊"
		ItemType.REVERSE: return "🌀"
		ItemType.GHOST: return "👻"
		ItemType.DASH: return "🚀"
		ItemType.SHIELD: return "🛡️"
		ItemType.BOMB: return "💣"
		_: return ""
