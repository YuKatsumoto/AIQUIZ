class_name StageConstants
extends RefCounted

## メニュープレビューと本編ゲームで共有するステージ（床・コンベア・海・環境）の定数。
## game_world.gd / menu_wall_background_preview.gd に重複していた値の単一ソース。

const BG_COLOR := Color(0.82, 0.85, 0.90)
const FLOOR_COLOR := Color(0.35, 0.35, 0.35)

## 床上面の Y。プレイヤー・壁・ゴール等の Y 基準。
const FLOOR_TOP_Y: float = -1.2
## 床ボックス（厚み16）の中心 Y。上面が FLOOR_TOP_Y に来るよう -9.2。
const FLOOR_CENTER_Y: float = -9.2
const FLOOR_WIDTH: float = 24.0
const FLOOR_THICKNESS: float = 16.0
const FLOOR_HALF_WIDTH: float = 12.0

const FLOOR_RAIL_HEIGHT: float = 0.26
const FLOOR_RAIL_WIDTH: float = 0.16
const FLOOR_RAIL_INSET: float = 0.06

const CONVEYOR_BELT_BASE_COLOR := Color(0.40, 0.41, 0.42, 1.0)
const CONVEYOR_BELT_STRIPE_COLOR := Color(0.34, 0.345, 0.35, 1.0)
const CONVEYOR_BELT_SIDE_COLOR := Color(0.33, 0.34, 0.35, 1.0)
const CONVEYOR_ROLLER_RADIUS: float = 0.48
const CONVEYOR_ROLLER_LENGTH: float = 23.4
const CONVEYOR_RETURN_BELT_THICKNESS: float = 0.10
const CONVEYOR_RETURN_BELT_GAP: float = 0.03
const CONVEYOR_SIDE_FRAME_WIDTH: float = 0.24
const CONVEYOR_SIDE_FRAME_HEIGHT: float = 1.05
const CONVEYOR_SIDE_FRAME_OVERHANG: float = 1.2
const CONVEYOR_SIDE_FRAME_TOP_CLEARANCE: float = 0.26

const OCEAN_SHADER: Shader = preload("res://shaders/ocean.gdshader")

## 海面描画と落下・沈下演出の共通基準。
const OCEAN_SURFACE_Y: float = -9.2
const OCEAN_ENTRY_Y: float = -8.0
const OCEAN_FLOAT_Y: float = OCEAN_SURFACE_Y + 0.25
const OCEAN_SINK_Y: float = -11.8
const OCEAN_SINK_SPEED: float = 1.9
const OCEAN_CENTER_Z: float = 150.0
const OCEAN_SIZE: Vector2 = Vector2(4000.0, 4000.0)

## 本編 GameTuning / game_state と揃えた床・壁基準
const FLOOR_BACK_Z: float = -12.5
const GAME_FLOOR_CENTER_Z: float = 4.0
const GAME_FLOOR_LENGTH: float = 160.0
const WALL_START_Z: float = 22.0
const WALL_SPACING: float = 30.0

## メニュープレビュー壁ループ（本編座標系）
const MENU_WALL_DESPAWN_Z: float = 8.0
const MENU_WALL_INITIAL_SPAWN_Z: float = WALL_START_Z - WALL_SPACING * 2.0
