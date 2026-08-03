extends Node2D

@export_range(1, 3) var level_id := 1

const COIN_SCENE := preload("res://scenes/Coin.tscn")
const GOAL_SCENE := preload("res://scenes/Goal.tscn")
const CHECKPOINT_SCENE := preload("res://scenes/Checkpoint.tscn")
const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")
const FLYING_ENEMY_SCENE := preload("res://scenes/FlyingEnemy.tscn")
const SHOOTING_ENEMY_SCENE := preload("res://scenes/ShootingEnemy.tscn")
const HEAVY_ENEMY_SCENE := preload("res://scenes/HeavyEnemy.tscn")

const GROUND_TILE := preload("res://assets/external/kenney_pixel-platformer/Tiles/tile_0001.png")
const PLANT_TILE := preload("res://assets/external/kenney_pixel-platformer/Tiles/tile_0125.png")
const CACTUS_TILE := preload("res://assets/external/kenney_pixel-platformer/Tiles/tile_0127.png")
const MUSHROOM_TILE := preload("res://assets/external/kenney_pixel-platformer/Tiles/tile_0128.png")
const BACKGROUND_SHEET := preload("res://assets/external/kenney_pixel-platformer/Tilemap/tilemap-backgrounds_packed.png")

var terrain := Node2D.new()
var decorations := Node2D.new()
var enemies := Node2D.new()
var collectibles := Node2D.new()

func _ready() -> void:
	terrain.name = "Terrain"
	decorations.name = "Decorations"
	enemies.name = "Enemies"
	collectibles.name = "Collectibles"
	add_child(terrain)
	add_child(decorations)
	add_child(enemies)
	add_child(collectibles)
	_build_background()
	match level_id:
		1:
			_build_meadow()
		2:
			_build_ruins()
		_:
			_build_fortress()

func _build_background() -> void:
	var backdrop := CanvasLayer.new()
	backdrop.name = "Backdrop"
	backdrop.layer = -10
	add_child(backdrop)

	var sky := ColorRect.new()
	sky.position = Vector2(-200, -200)
	sky.size = Vector2(2400, 1400)
	sky.color = [Color("#8ed7e8"), Color("#e0b27e"), Color("#657494")][level_id - 1]
	backdrop.add_child(sky)

	var region_x := [144.0, 96.0, 48.0][level_id - 1]
	for i in range(-1, 6):
		var atlas := AtlasTexture.new()
		atlas.atlas = BACKGROUND_SHEET
		atlas.region = Rect2(region_x, 24, 24, 24)
		var horizon := TextureRect.new()
		horizon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		horizon.texture = atlas
		horizon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		horizon.stretch_mode = TextureRect.STRETCH_SCALE
		horizon.position = Vector2(i * 480.0, 330.0)
		horizon.size = Vector2(482.0, 390.0)
		horizon.modulate = Color(1, 1, 1, 0.72)
		backdrop.add_child(horizon)

	var haze := ColorRect.new()
	haze.position = Vector2(-200, 650)
	haze.size = Vector2(2400, 500)
	haze.color = Color(0.05, 0.12, 0.18, 0.18)
	backdrop.add_child(haze)

func _add_platform(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	terrain.add_child(body)

	var shape := RectangleShape2D.new()
	shape.size = size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)

	var earth := ColorRect.new()
	earth.position = -size * 0.5
	earth.size = size
	earth.color = [Color("#8d5f45"), Color("#755c52"), Color("#4a4554")][level_id - 1]
	body.add_child(earth)

	var tiled_top := TextureRect.new()
	tiled_top.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tiled_top.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	tiled_top.texture = GROUND_TILE
	tiled_top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tiled_top.stretch_mode = TextureRect.STRETCH_TILE
	tiled_top.position = Vector2(-size.x * 0.5, -size.y * 0.5)
	tiled_top.size = Vector2(size.x, minf(22.0, size.y))
	tiled_top.modulate = [Color.WHITE, Color("#e6c19c"), Color("#c3c7d9")][level_id - 1]
	body.add_child(tiled_top)

func _add_decoration(pos: Vector2, texture: Texture2D, scale_value := 2.0) -> void:
	var sprite := Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = texture
	sprite.position = pos
	sprite.scale = Vector2.ONE * scale_value
	decorations.add_child(sprite)

func _spawn(scene: PackedScene, pos: Vector2, parent: Node2D, properties := {}) -> Node2D:
	var instance := scene.instantiate() as Node2D
	instance.position = pos
	for property_name in properties:
		instance.set(property_name, properties[property_name])
	parent.add_child(instance)
	return instance

func _add_title(text_value: String, pos: Vector2) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = pos
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color("#f4f0dc"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	decorations.add_child(label)

func _build_meadow() -> void:
	_add_title("第一关 · 翠绿边境", Vector2(-1040, 420))
	_add_platform(Vector2(-750, 620), Vector2(700, 80))
	_add_platform(Vector2(-45, 620), Vector2(560, 80))
	_add_platform(Vector2(650, 620), Vector2(760, 80))
	_add_platform(Vector2(-650, 490), Vector2(220, 34))
	_add_platform(Vector2(-315, 410), Vector2(180, 34))
	_add_platform(Vector2(40, 500), Vector2(220, 34))
	_add_platform(Vector2(380, 430), Vector2(220, 34))
	_add_platform(Vector2(710, 350), Vector2(200, 34))
	_add_platform(Vector2(930, 350), Vector2(140, 34))

	for pos in [Vector2(-650, 440), Vector2(-315, 360), Vector2(40, 450), Vector2(380, 380), Vector2(710, 300), Vector2(930, 300), Vector2(160, 540), Vector2(540, 540)]:
		_spawn(COIN_SCENE, pos, collectibles)
	_spawn(ENEMY_SCENE, Vector2(-120, 565), enemies, {"patrol_range": 120.0})
	_spawn(ENEMY_SCENE, Vector2(520, 565), enemies, {"patrol_range": 110.0})
	_spawn(FLYING_ENEMY_SCENE, Vector2(210, 350), enemies, {"bob_range": 34.0})
	_spawn(CHECKPOINT_SCENE, Vector2(380, 392), self)
	_spawn(GOAL_SCENE, Vector2(930, 301), self)
	_add_decoration(Vector2(-850, 562), PLANT_TILE)
	_add_decoration(Vector2(-455, 562), MUSHROOM_TILE)
	_add_decoration(Vector2(275, 562), CACTUS_TILE)
	_add_decoration(Vector2(790, 562), PLANT_TILE)

func _build_ruins() -> void:
	_add_title("第二关 · 风蚀遗迹", Vector2(-1370, 420))
	_add_platform(Vector2(-1080, 620), Vector2(640, 80))
	_add_platform(Vector2(-365, 620), Vector2(620, 80))
	_add_platform(Vector2(350, 620), Vector2(620, 80))
	_add_platform(Vector2(1080, 620), Vector2(700, 80))
	_add_platform(Vector2(-980, 475), Vector2(210, 34))
	_add_platform(Vector2(-650, 350), Vector2(190, 34))
	_add_platform(Vector2(-300, 470), Vector2(230, 34))
	_add_platform(Vector2(60, 375), Vector2(200, 34))
	_add_platform(Vector2(410, 285), Vector2(200, 34))
	_add_platform(Vector2(760, 410), Vector2(250, 34))
	_add_platform(Vector2(1120, 310), Vector2(250, 34))

	for pos in [Vector2(-980, 425), Vector2(-650, 300), Vector2(-300, 420), Vector2(60, 325), Vector2(410, 235), Vector2(760, 360), Vector2(1120, 260), Vector2(250, 540), Vector2(930, 540)]:
		_spawn(COIN_SCENE, pos, collectibles)
	_spawn(ENEMY_SCENE, Vector2(-1120, 565), enemies, {"patrol_range": 150.0})
	_spawn(SHOOTING_ENEMY_SCENE, Vector2(-300, 440), enemies, {"patrol_range": 70.0})
	_spawn(FLYING_ENEMY_SCENE, Vector2(230, 255), enemies, {"bob_range": 45.0})
	_spawn(ENEMY_SCENE, Vector2(780, 370), enemies, {"patrol_range": 80.0})
	_spawn(CHECKPOINT_SCENE, Vector2(410, 248), self)
	_spawn(GOAL_SCENE, Vector2(1120, 261), self)
	_add_decoration(Vector2(-1220, 562), CACTUS_TILE)
	_add_decoration(Vector2(-520, 562), MUSHROOM_TILE)
	_add_decoration(Vector2(520, 562), CACTUS_TILE)
	_add_decoration(Vector2(1220, 562), PLANT_TILE)

func _build_fortress() -> void:
	_add_title("第三关 · 钢铁城门", Vector2(-1600, 420))
	_add_platform(Vector2(-1240, 620), Vector2(720, 80))
	_add_platform(Vector2(-430, 620), Vector2(700, 80))
	_add_platform(Vector2(390, 620), Vector2(720, 80))
	_add_platform(Vector2(1250, 620), Vector2(800, 80))
	_add_platform(Vector2(-1320, 470), Vector2(220, 36))
	_add_platform(Vector2(-960, 350), Vector2(220, 36))
	_add_platform(Vector2(-570, 460), Vector2(260, 36))
	_add_platform(Vector2(-160, 330), Vector2(220, 36))
	_add_platform(Vector2(240, 455), Vector2(260, 36))
	_add_platform(Vector2(650, 330), Vector2(220, 36))
	_add_platform(Vector2(1030, 430), Vector2(250, 36))
	_add_platform(Vector2(1410, 300), Vector2(280, 36))

	for pos in [Vector2(-1320, 420), Vector2(-960, 300), Vector2(-570, 410), Vector2(-160, 280), Vector2(240, 405), Vector2(650, 280), Vector2(1030, 380), Vector2(1410, 250), Vector2(20, 540), Vector2(830, 540)]:
		_spawn(COIN_SCENE, pos, collectibles)
	_spawn(HEAVY_ENEMY_SCENE, Vector2(-1170, 562), enemies, {"patrol_range": 110.0})
	_spawn(SHOOTING_ENEMY_SCENE, Vector2(-570, 428), enemies, {"patrol_range": 80.0, "fire_interval": 2.0})
	_spawn(FLYING_ENEMY_SCENE, Vector2(-40, 235), enemies, {"bob_range": 38.0})
	_spawn(ENEMY_SCENE, Vector2(250, 418), enemies, {"patrol_range": 90.0})
	_spawn(SHOOTING_ENEMY_SCENE, Vector2(1030, 398), enemies, {"patrol_range": 80.0, "fire_interval": 1.8})
	_spawn(HEAVY_ENEMY_SCENE, Vector2(1220, 562), enemies, {"patrol_range": 130.0})
	_spawn(CHECKPOINT_SCENE, Vector2(650, 292), self)
	_spawn(GOAL_SCENE, Vector2(1410, 250), self)
	_add_decoration(Vector2(-1450, 562), PLANT_TILE)
	_add_decoration(Vector2(-760, 562), MUSHROOM_TILE)
	_add_decoration(Vector2(570, 562), CACTUS_TILE)
	_add_decoration(Vector2(1510, 562), PLANT_TILE)
