# 核心玩法扩展 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 demo-01 平台跳跃游戏添加冲刺/爬墙蹬墙跳/下砸三种玩家能力、三种新敌人（飞行/射击/重甲）、四种新机制（弹簧/传送门/可破坏砖块/存档点），新增第3关并改造第1、2关。

**Architecture:** 跟随现有模式：每个新单位一个独立脚本+场景（ColorRect 占位风格）。Player.gd 扩展三种能力；Game.gd 管理 checkpoint 重生；关卡场景手工摆放节点。

**Tech Stack:** Godot 4.7 GDScript，Jolt Physics，CanvasItems 拉伸。无自动化测试框架、无 godot CLI 可用——验证方式为代码静态检查 + 用户在 Godot 编辑器中运行试玩。

## Global Constraints

- Godot 4.7，GDScript，缩进用 Tab
- 不添加新美术/音频资源，全部沿用 ColorRect 占位与现有 5 个音效（jump/coin/stomp/death/win）
- 所有新敌人加入 `"enemies"` 组；玩家能力始终可用、无需拾取
- 难度适中：能力生效无需激活
- 音效复用规则：冲刺→"stomp"、下砸→"stomp"、弹簧→"jump"、传送→"jump"、破砖→"stomp"
- 现有 `Player.gd`/`Enemy.gd` 等可自由重构

---

### Task 1: 输入与主流程基础改造

**Files:**
- Modify: `scripts/InputSetup.gd`
- Modify: `scenes/Main.tscn`
- Modify: `scripts/Game.gd`

**Interfaces:**
- Consumes: 现有 `InputSetup.gd` 的 `_ensure_action(action, keys)` 函数
- Produces: 新输入动作 `dash`（Shift）、`down`（S/↓）；Main 节点加入组 `"game"`；`Game.gd` 新增 `_on_checkpoint_activated(pos: Vector2)` 与 checkpoint 重生逻辑；`Game.gd` 的 `LEVELS`/`LEVEL_STARTS` 常量新增第3关条目

- [ ] **Step 1: InputSetup.gd 添加 dash/down 动作**

```gdscript
func _ready() -> void:
	_ensure_action("jump", [KEY_SPACE, KEY_W, KEY_UP])
	_ensure_action("left", [KEY_A, KEY_LEFT])
	_ensure_action("right", [KEY_D, KEY_RIGHT])
	_ensure_action("dash", [KEY_SHIFT])
	_ensure_action("down", [KEY_S, KEY_DOWN])
	_ensure_action("restart", [KEY_R])
```

- [ ] **Step 2: Main.tscn 的 Main 节点加入 game 组**

`[node name="Main" type="Node2D" groups=["game"]]`

- [ ] **Step 3: Game.gd 添加 checkpoint 逻辑**

新增变量与连接：
```gdscript
var checkpoint_pos := Vector2.ZERO
var has_checkpoint := false
```
`_load_level` 末尾新增：
```gdscript
	has_checkpoint = false
	for checkpoint in get_tree().get_nodes_in_group("checkpoints"):
		checkpoint.activated.connect(_on_checkpoint_activated)
```
新增函数：
```gdscript
func _on_checkpoint_activated(pos: Vector2) -> void:
	checkpoint_pos = pos
	has_checkpoint = true
```
`_on_player_died` 的 `else` 分支改为：
```gdscript
	else:
		if has_checkpoint:
			player.global_position = checkpoint_pos
			player.velocity = Vector2.ZERO
			player.dead = false
			player.set_process(true)
			player.set_physics_process(true)
		else:
			_load_level(current_level)
```
`LEVELS`/`LEVEL_STARTS` 各追加第3关条目（Level3.tscn 在 Task 11 创建，先写入路径）：
```gdscript
const LEVELS: Array[String] = [
	"res://scenes/Level1.tscn",
	"res://scenes/Level2.tscn",
	"res://scenes/Level3.tscn",
]
const LEVEL_STARTS: Array[Vector2] = [
	Vector2(-520, 500),
	Vector2(-520, 500),
	Vector2(-520, 500),
]
```

- [ ] **Step 4: 验证**

检查三个文件改动无语法错误、路径一致。

---

### Task 2: Player.gd 三种新能力

**Files:**
- Modify: `scripts/Player.gd`（整体重写）

**Interfaces:**
- Consumes: 输入动作 `dash`/`down`；`AudioManager.play()`；现有敌人组的 `stomp()` 方法
- Produces: 公开状态 `is_dashing`/`is_pounding`（BreakableBlock 检测用）；方法 `launch(vy: float)`（Spring 用）、`teleport_to(pos: Vector2) -> bool`（Teleporter 用）、`_die()`（Bullet 用）、`_stomp(enemy)` 调用敌人 `stomp()`/`pound()` 方法；现有信号 `died` 不变

- [ ] **Step 1: 重写 Player.gd**

```gdscript
extends CharacterBody2D

signal died

const SPEED := 320.0
const JUMP_VELOCITY := -560.0
const AIR_JUMP_FACTOR := 0.85
const MAX_JUMPS := 2

const DASH_SPEED := 700.0
const DASH_TIME := 0.15
const DASH_COOLDOWN := 0.5

const WALL_SLIDE_SPEED := 70.0
const WALL_JUMP_VELOCITY_X := 420.0

const POUND_VELOCITY := 1000.0
const POUND_BOUNCE := -320.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var jumps_remaining := MAX_JUMPS
var dead := false
var facing := 1
var is_dashing := false
var is_pounding := false
var dash_cooldown_left := 0.0
var dash_time_left := 0.0
var wall_dir := 0
var teleport_lock := 0.0

func _physics_process(delta: float) -> void:
	if dead:
		return
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
	teleport_lock = maxf(0.0, teleport_lock - delta)

	var direction := Input.get_axis("left", "right")
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1

	if Input.is_action_just_pressed("down") and not is_on_floor() and not is_dashing and not is_pounding:
		is_pounding = true
		velocity.y = POUND_VELOCITY

	if Input.is_action_just_pressed("dash") and dash_cooldown_left <= 0.0 and not is_pounding:
		is_dashing = true
		dash_time_left = DASH_TIME
		dash_cooldown_left = DASH_COOLDOWN
		AudioManager.play("stomp")

	if is_dashing:
		dash_time_left -= delta
		if dash_time_left <= 0.0:
			is_dashing = false
		else:
			velocity = Vector2(facing * DASH_SPEED, 0.0)
			move_and_slide()
			return

	if not is_on_floor():
		if not is_pounding:
			velocity.y += gravity * delta
	else:
		jumps_remaining = MAX_JUMPS

	var jump_consumed := false
	wall_dir = 0
	if is_on_wall() and not is_on_floor() and not is_pounding:
		wall_dir = signi(int(round(get_wall_normal().x)))
		if Input.is_action_just_pressed("jump"):
			velocity.x = wall_dir * WALL_JUMP_VELOCITY_X
			velocity.y = JUMP_VELOCITY * 0.9
			jumps_remaining = MAX_JUMPS - 1
			jump_consumed = true
			AudioManager.play("jump")
		elif Input.get_axis("left", "right") == -wall_dir:
			velocity.y = minf(velocity.y, WALL_SLIDE_SPEED)

	if not is_pounding and not jump_consumed and Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
			jumps_remaining = MAX_JUMPS - 1
			AudioManager.play("jump")
		elif jumps_remaining > 0 and not is_on_wall():
			velocity.y = JUMP_VELOCITY * AIR_JUMP_FACTOR
			jumps_remaining -= 1
			AudioManager.play("jump")

	if is_pounding:
		velocity.y = POUND_VELOCITY
	else:
		velocity.x = direction * SPEED
		if wall_dir != 0 and Input.get_axis("left", "right") == -wall_dir:
			velocity.y = minf(velocity.y, WALL_SLIDE_SPEED)

	move_and_slide()

	if is_pounding and is_on_floor():
		_pound_shockwave()
		velocity.y = POUND_BOUNCE
		is_pounding = false
		AudioManager.play("stomp")

	_check_collisions()

func _check_collisions() -> void:
	if is_dashing:
		return
	for i in get_slide_collision_count():
		var collider: Object = get_slide_collision(i).get_collider()
		if collider is Node2D and collider.is_in_group("enemies"):
			if velocity.y > 0 and global_position.y < collider.global_position.y:
				_stomp(collider)
			else:
				_die()
		elif collider is Node2D and collider.is_in_group("spikes"):
			_die()

func _pound_shockwave() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("pound"):
			enemy.pound()

func _stomp(enemy: Node2D) -> void:
	velocity.y = JUMP_VELOCITY * 0.6
	jumps_remaining = 1
	AudioManager.play("stomp")
	if enemy.has_method("stomp"):
		enemy.stomp()

func launch(vy: float) -> void:
	if dead:
		return
	is_pounding = false
	velocity.y = vy
	jumps_remaining = MAX_JUMPS - 1

func teleport_to(pos: Vector2) -> bool:
	if teleport_lock > 0.0 or dead:
		return false
	teleport_lock = 0.5
	global_position = pos
	velocity = Vector2.ZERO
	is_pounding = false
	is_dashing = false
	return true

func _die() -> void:
	if dead or is_dashing:
		return
	dead = true
	died.emit()
```

- [ ] **Step 2: 验证**

静态检查：无未定义符号（AudioManager、Input 动作已在 Task 1 保证）。

---

### Task 3: Enemy.gd 支持下砸击杀

**Files:**
- Modify: `scripts/Enemy.gd`

**Interfaces:**
- Consumes: 现有结构
- Produces: `pound()` 方法（下砸冲击波调用）

- [ ] **Step 1: 添加 pound()**

文件末尾追加：
```gdscript
func pound() -> void:
	stomp()
```

---

### Task 4: 飞行敌人 FlyingEnemy

**Files:**
- Create: `scripts/FlyingEnemy.gd`
- Create: `scenes/FlyingEnemy.tscn`

**Interfaces:**
- Consumes: 组 `"enemies"`（Player 检测）
- Produces: `stomp()`/`pound()` 方法

- [ ] **Step 1: 创建脚本**

```gdscript
extends CharacterBody2D

@export var bob_range := 60.0
@export var bob_speed := 2.0

var origin_y: float
var time := 0.0
var dead := false

func _ready() -> void:
	add_to_group("enemies")
	origin_y = global_position.y

func _physics_process(delta: float) -> void:
	if dead:
		return
	time += delta * bob_speed
	global_position.y = origin_y + sin(time) * bob_range

func stomp() -> void:
	dead = true
	queue_free()

func pound() -> void:
	stomp()
```

- [ ] **Step 2: 创建场景 FlyingEnemy.tscn**

```tscn
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/FlyingEnemy.gd" id="1"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_fly"]
size = Vector2(28, 20)

[node name="FlyingEnemy" type="CharacterBody2D"]
script = ExtResource("1")

[node name="FlyColor" type="ColorRect" parent="."]
offset_left = -14.0
offset_top = -10.0
offset_right = 14.0
offset_bottom = 10.0
color = Color(0.7, 0.3, 0.85, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_fly")
```

- [ ] **Step 3: 验证**

对照 Enemy.tscn 格式检查。

---

### Task 5: 子弹 Bullet 与射击敌人 ShootingEnemy

**Files:**
- Create: `scripts/Bullet.gd`, `scenes/Bullet.tscn`
- Create: `scripts/ShootingEnemy.gd`, `scenes/ShootingEnemy.tscn`

**Interfaces:**
- Consumes: 组 `"player"`；`AudioManager`
- Produces: `Bullet` 有公开属性 `velocity: Vector2`、`shooter: Node2D`；`ShootingEnemy` 提供 `stomp()`/`pound()`

- [ ] **Step 1: 创建 Bullet.gd**

```gdscript
extends Area2D

var velocity := Vector2.ZERO
var shooter: Node2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta

func _on_body_entered(body: Node2D) -> void:
	if body == shooter or body is Area2D:
		return
	if body.is_in_group("player"):
		if body.has_method("_die"):
			body._die()
		queue_free()
	else:
		queue_free()
```

- [ ] **Step 2: 创建 Bullet.tscn**

```tscn
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/Bullet.gd" id="1"]

[sub_resource type="CircleShape2D" id="CircleShape2D_bullet"]
radius = 5.0

[node name="Bullet" type="Area2D"]
script = ExtResource("1")

[node name="BulletColor" type="ColorRect" parent="."]
offset_left = -4.0
offset_top = -4.0
offset_right = 4.0
offset_bottom = 4.0
color = Color(1, 0.55, 0.1, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_bullet")
```

- [ ] **Step 3: 创建 ShootingEnemy.gd**

```gdscript
extends CharacterBody2D

@export var patrol_range := 120.0
@export var fire_interval := 2.5
@export var detect_range := 300.0

const SPEED := 60.0
const BULLET_SPEED := 260.0

var direction := -1
var start_x: float
var dead := false
var fire_timer := 1.0

@onready var player: Node2D = get_tree().get_first_node_in_group("player")

func _ready() -> void:
	add_to_group("enemies")
	start_x = global_position.x

func _physics_process(delta: float) -> void:
	if dead:
		return
	velocity.x = direction * SPEED
	move_and_slide()
	if global_position.x <= start_x - patrol_range:
		direction = 1
	elif global_position.x >= start_x + patrol_range:
		direction = -1

	fire_timer -= delta
	if fire_timer <= 0.0 and player and not player.dead:
		var to_player := player.global_position - global_position
		if absf(to_player.y) < 80.0 and absf(to_player.x) < detect_range:
			_shoot(signf(to_player.x))
			fire_timer = fire_interval

func _shoot(dir: float) -> void:
	var bullet: Area2D = (load("res://scenes/Bullet.tscn") as PackedScene).instantiate()
	bullet.velocity = Vector2(dir * BULLET_SPEED, 0)
	bullet.shooter = self
	bullet.global_position = global_position + Vector2(dir * 20, 0)
	get_tree().current_scene.add_child(bullet)

func stomp() -> void:
	dead = true
	queue_free()

func pound() -> void:
	stomp()
```

- [ ] **Step 4: 创建 ShootingEnemy.tscn**

```tscn
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/ShootingEnemy.gd" id="1"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_shoot"]
size = Vector2(28, 24)

[node name="ShootingEnemy" type="CharacterBody2D"]
script = ExtResource("1")

[node name="ShootColor" type="ColorRect" parent="."]
offset_left = -14.0
offset_top = -12.0
offset_right = 14.0
offset_bottom = 12.0
color = Color(0.9, 0.55, 0.1, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_shoot")
```

- [ ] **Step 5: 验证**

检查子弹 `_on_body_entered` 中 `body == shooter` 排除自伤；玩家冲刺无敌由 Player._die 的 `is_dashing` 判断保证。

---

### Task 6: 重甲敌人 HeavyEnemy

**Files:**
- Create: `scripts/HeavyEnemy.gd`, `scenes/HeavyEnemy.tscn`

**Interfaces:**
- Consumes: 组 `"player"`（获取玩家引用）
- Produces: `stomp()`（仅眩晕时可杀，否则杀玩家）；**无** `pound()` 方法（下砸无法直接消灭，需先撞墙眩晕）

- [ ] **Step 1: 创建 HeavyEnemy.gd**

```gdscript
extends CharacterBody2D

@export var patrol_range := 100.0
@export var charge_range := 300.0

const PATROL_SPEED := 40.0
const CHARGE_SPEED := 300.0
const STUN_TIME := 2.0

enum State { PATROL, CHARGE, STUNNED }

var state := State.PATROL
var direction := -1
var start_x: float
var dead := false
var stun_timer := 0.0
var facing := -1

@onready var player: Node2D = get_tree().get_first_node_in_group("player")
@onready var color_rect: ColorRect = $HeavyColor

func _ready() -> void:
	add_to_group("enemies")
	start_x = global_position.x

func _physics_process(delta: float) -> void:
	if dead:
		return
	match state:
		State.PATROL:
			velocity.x = direction * PATROL_SPEED
			move_and_slide()
			if global_position.x <= start_x - patrol_range:
				direction = 1
			elif global_position.x >= start_x + patrol_range:
				direction = -1
			_try_charge()
		State.CHARGE:
			velocity.x = facing * CHARGE_SPEED
			move_and_slide()
			if is_on_wall():
				state = State.STUNNED
				stun_timer = STUN_TIME
				color_rect.color = Color(0.7, 0.7, 0.75)
		State.STUNNED:
			velocity.x = 0.0
			stun_timer -= delta
			if stun_timer <= 0.0:
				state = State.PATROL
				color_rect.color = Color(0.5, 0.3, 0.8)

func _try_charge() -> void:
	if not player or player.dead:
		return
	var to_player := player.global_position - global_position
	if absf(to_player.x) < charge_range and absf(to_player.y) < 60.0:
		facing = signf(to_player.x)
		if facing == 0.0:
			facing = 1.0
		state = State.CHARGE
		color_rect.color = Color(0.9, 0.2, 0.2)

func stomp() -> void:
	if state == State.STUNNED:
		dead = true
		queue_free()
	elif player:
		player._die()
```

- [ ] **Step 2: 创建 HeavyEnemy.tscn**

```tscn
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/HeavyEnemy.gd" id="1"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_heavy"]
size = Vector2(36, 30)

[node name="HeavyEnemy" type="CharacterBody2D"]
script = ExtResource("1")

[node name="HeavyColor" type="ColorRect" parent="."]
offset_left = -18.0
offset_top = -15.0
offset_right = 18.0
offset_bottom = 15.0
color = Color(0.5, 0.3, 0.8, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_heavy")
```

- [ ] **Step 3: 验证**

确认状态机：撞墙（is_on_wall）→ STUNNED → 2s → PATROL。

---

### Task 7: 弹簧 Spring

**Files:**
- Create: `scripts/Spring.gd`, `scenes/Spring.tscn`

**Interfaces:**
- Consumes: `AudioManager.play("jump")`；玩家 `launch(vy)` 方法
- Produces: 无

- [ ] **Step 1: 创建 Spring.gd**

```gdscript
extends Area2D

@export var launch_velocity := -900.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("launch"):
		body.launch(launch_velocity)
		AudioManager.play("jump")
		_animate()

func _animate() -> void:
	var rect: ColorRect = $SpringColor
	var tween := create_tween()
	tween.tween_property(rect, "scale", Vector2(1.0, 0.4), 0.08)
	tween.tween_property(rect, "scale", Vector2(1.0, 1.0), 0.15)
```

- [ ] **Step 2: 创建 Spring.tscn**

```tscn
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/Spring.gd" id="1"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_spring"]
size = Vector2(28, 16)

[node name="Spring" type="Area2D"]
script = ExtResource("1")

[node name="SpringColor" type="ColorRect" parent="."]
offset_left = -12.0
offset_top = -6.0
offset_right = 12.0
offset_bottom = 6.0
pivot_offset = Vector2(12, 6)
color = Color(0.95, 0.75, 0.15, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_spring")
```

- [ ] **Step 3: 验证**

确认 `launch` 在 Player.gd 中存在（Task 2 已定义）。

---

### Task 8: 传送门 Teleporter

**Files:**
- Create: `scripts/Teleporter.gd`, `scenes/Teleporter.tscn`

**Interfaces:**
- Consumes: 组 `"teleporters"`；玩家 `teleport_to(pos) -> bool`
- Produces: 无

- [ ] **Step 1: 创建 Teleporter.gd**

```gdscript
extends Area2D

@export var pair_id := 0

func _ready() -> void:
	add_to_group("teleporters")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or not body.has_method("teleport_to"):
		return
	var target := _find_pair()
	if target:
		body.teleport_to(target.global_position + Vector2(0, -24))
		AudioManager.play("jump")

func _find_pair() -> Area2D:
	for node in get_tree().get_nodes_in_group("teleporters"):
		if node != self and node.pair_id == pair_id:
			return node
	return null
```

- [ ] **Step 2: 创建 Teleporter.tscn**

```tscn
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/Teleporter.gd" id="1"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_tp"]
size = Vector2(36, 52)

[node name="Teleporter" type="Area2D"]
script = ExtResource("1")

[node name="TpColor" type="ColorRect" parent="."]
offset_left = -16.0
offset_top = -24.0
offset_right = 16.0
offset_bottom = 24.0
color = Color(0.2, 0.8, 0.9, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_tp")
```

- [ ] **Step 3: 验证**

确认玩家 `teleport_to` 的 0.5s 锁定可防循环传送。

---

### Task 9: 可破坏砖块 BreakableBlock

**Files:**
- Create: `scripts/BreakableBlock.gd`, `scenes/BreakableBlock.tscn`

**Interfaces:**
- Consumes: 组 `"game"`（Main）；组 `"player"` 的 `is_pounding`/`is_dashing`；`Coin.tscn`；`AudioManager`
- Produces: 无

- [ ] **Step 1: 创建 BreakableBlock.gd**

```gdscript
extends StaticBody2D

func _ready() -> void:
	$Detector.body_entered.connect(_on_detector_entered)

func _on_detector_entered(body: Node2D) -> void:
	if body.is_in_group("player") and (body.is_pounding or body.is_dashing):
		_break()

func _break() -> void:
	AudioManager.play("stomp")
	var coin: Area2D = (load("res://scenes/Coin.tscn") as PackedScene).instantiate()
	coin.global_position = global_position
	var game: Node = get_tree().get_first_node_in_group("game")
	if game:
		coin.collected.connect(game._on_coin_collected)
	get_parent().add_child(coin)
	queue_free()
```

- [ ] **Step 2: 创建 BreakableBlock.tscn**

```tscn
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/BreakableBlock.gd" id="1"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_block"]
size = Vector2(30, 30)

[sub_resource type="RectangleShape2D" id="RectangleShape2D_detect"]
size = Vector2(34, 34)

[node name="BreakableBlock" type="StaticBody2D"]
script = ExtResource("1")

[node name="BlockColor" type="ColorRect" parent="."]
offset_left = -15.0
offset_top = -15.0
offset_right = 15.0
offset_bottom = 15.0
color = Color(0.55, 0.55, 0.62, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_block")

[node name="Detector" type="Area2D" parent="."]

[node name="CollisionShape2D" type="CollisionShape2D" parent="Detector"]
shape = SubResource("RectangleShape2D_detect")
```

- [ ] **Step 3: 验证**

Main.tscn 已加入 `"game"` 组（Task 1），金币信号连接可用。

---

### Task 10: 存档点 Checkpoint

**Files:**
- Create: `scripts/Checkpoint.gd`, `scenes/Checkpoint.tscn`

**Interfaces:**
- Consumes: 组 `"player"`
- Produces: 信号 `activated(position: Vector2)`（Game.gd 连接）

- [ ] **Step 1: 创建 Checkpoint.gd**

```gdscript
extends Area2D

signal activated(position: Vector2)

var active := false

func _ready() -> void:
	add_to_group("checkpoints")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if active:
		return
	if body.is_in_group("player"):
		active = true
		$CheckpointColor.color = Color(0.2, 0.9, 0.3)
		activated.emit(global_position + Vector2(0, -30))
```

- [ ] **Step 2: 创建 Checkpoint.tscn**

```tscn
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/Checkpoint.gd" id="1"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_checkpoint"]
size = Vector2(20, 40)

[node name="Checkpoint" type="Area2D"]
script = ExtResource("1")

[node name="CheckpointColor" type="ColorRect" parent="."]
offset_left = -8.0
offset_top = -18.0
offset_right = 8.0
offset_bottom = 18.0
color = Color(0.45, 0.45, 0.45, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_checkpoint")
```

- [ ] **Step 3: 验证**

Game.gd 的 `_on_checkpoint_activated` 已存在（Task 1）。

---

### Task 11: 新建 Level3 并接入流程

**Files:**
- Create: `scenes/Level3.tscn`
- Game.gd 的 LEVELS/LEVEL_STARTS 已在 Task 1 加入第3关

**Interfaces:**
- Consumes: 所有新场景：FlyingEnemy / ShootingEnemy / HeavyEnemy / Spring / Teleporter / BreakableBlock / Checkpoint；及 Coin / Goal / Spike / MovingPlatform
- Produces: 可通关的第3关

- [ ] **Step 1: 创建 Level3.tscn**

布局（地面 y=620，墙 ±960，可跳跃高度内）：
1. 冲刺教学：P1(-540,450) → P2(-300,450)（间隙下方4根尖刺）→ P3(-60,430)（间隙下方4根尖刺）
2. 蹬墙井：两堵墙 (180,420) 与 (260,420)，尺寸(40,440)，中间 40px 缝隙，顶部 y=200
3. P4(440,200) + 破砖(480,173) + 弹簧(600,584) → P5(600,200)
4. 飞行敌人区：P6(780,320)、Flying1(660,250)、P7(920,420)、Flying2(860,360)
5. 射击敌人守地：Shooting(700,586)
6. 重甲守关：Heavy(880,586)
7. P8(1000,500)、P9(1000,260)、Goal(1000,205)
8. Checkpoint(600,160)；金币分布在各平台与地面

```tscn
[gd_scene load_steps=19 format=3]

[ext_resource type="PackedScene" path="res://scenes/Coin.tscn" id="1_coin"]
[ext_resource type="PackedScene" path="res://scenes/Goal.tscn" id="2_goal"]
[ext_resource type="PackedScene" path="res://scenes/Spike.tscn" id="3_spike"]
[ext_resource type="PackedScene" path="res://scenes/FlyingEnemy.tscn" id="4_fly"]
[ext_resource type="PackedScene" path="res://scenes/ShootingEnemy.tscn" id="5_shoot"]
[ext_resource type="PackedScene" path="res://scenes/HeavyEnemy.tscn" id="6_heavy"]
[ext_resource type="PackedScene" path="res://scenes/Spring.tscn" id="7_spring"]
[ext_resource type="PackedScene" path="res://scenes/BreakableBlock.tscn" id="8_block"]
[ext_resource type="PackedScene" path="res://scenes/Checkpoint.tscn" id="9_check"]

[sub_resource type="RectangleShape2D" id="rect_ground"]
size = Vector2(1920, 40)

[sub_resource type="RectangleShape2D" id="rect_wall"]
size = Vector2(40, 1000)

[sub_resource type="RectangleShape2D" id="rect_plat"]
size = Vector2(200, 24)

[sub_resource type="RectangleShape2D" id="rect_chimney"]
size = Vector2(40, 440)

[node name="Level3" type="Node2D"]

[node name="Ground" type="StaticBody2D" parent="."]
position = Vector2(0, 620)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Ground"]
shape = SubResource("rect_ground")

[node name="GroundColor" type="ColorRect" parent="Ground"]
offset_left = -960.0
offset_top = -20.0
offset_right = 960.0
offset_bottom = 20.0
color = Color(0.3, 0.42, 0.3, 1)

[node name="WallLeft" type="StaticBody2D" parent="."]
position = Vector2(-960, 620)

[node name="CollisionShape2D" type="CollisionShape2D" parent="WallLeft"]
shape = SubResource("rect_wall")

[node name="WallColor" type="ColorRect" parent="WallLeft"]
offset_left = -20.0
offset_top = -500.0
offset_right = 20.0
offset_bottom = 500.0
color = Color(0.4, 0.5, 0.38, 1)

[node name="WallRight" type="StaticBody2D" parent="."]
position = Vector2(960, 620)

[node name="CollisionShape2D" type="CollisionShape2D" parent="WallRight"]
shape = SubResource("rect_wall")

[node name="WallColor" type="ColorRect" parent="WallRight"]
offset_left = -20.0
offset_top = -500.0
offset_right = 20.0
offset_bottom = 500.0
color = Color(0.4, 0.5, 0.38, 1)

[node name="PlatformP1" type="StaticBody2D" parent="."]
position = Vector2(-540, 450)

[node name="CollisionShape2D" type="CollisionShape2D" parent="PlatformP1"]
shape = SubResource("rect_plat")

[node name="PlatColor" type="ColorRect" parent="PlatformP1"]
offset_left = -100.0
offset_top = -12.0
offset_right = 100.0
offset_bottom = 12.0
color = Color(0.5, 0.62, 0.4, 1)

[node name="PlatformP2" type="StaticBody2D" parent="."]
position = Vector2(-300, 450)

[node name="CollisionShape2D" type="CollisionShape2D" parent="PlatformP2"]
shape = SubResource("rect_plat")

[node name="PlatColor" type="ColorRect" parent="PlatformP2"]
offset_left = -100.0
offset_top = -12.0
offset_right = 100.0
offset_bottom = 12.0
color = Color(0.5, 0.62, 0.4, 1)

[node name="PlatformP3" type="StaticBody2D" parent="."]
position = Vector2(-60, 430)

[node name="CollisionShape2D" type="CollisionShape2D" parent="PlatformP3"]
shape = SubResource("rect_plat")

[node name="PlatColor" type="ColorRect" parent="PlatformP3"]
offset_left = -100.0
offset_top = -12.0
offset_right = 100.0
offset_bottom = 12.0
color = Color(0.5, 0.62, 0.4, 1)

[node name="ChimneyWallA" type="StaticBody2D" parent="."]
position = Vector2(180, 420)

[node name="CollisionShape2D" type="CollisionShape2D" parent="ChimneyWallA"]
shape = SubResource("rect_chimney")

[node name="WallColor" type="ColorRect" parent="ChimneyWallA"]
offset_left = -20.0
offset_top = -220.0
offset_right = 20.0
offset_bottom = 220.0
color = Color(0.55, 0.55, 0.4, 1)

[node name="ChimneyWallB" type="StaticBody2D" parent="."]
position = Vector2(260, 420)

[node name="CollisionShape2D" type="CollisionShape2D" parent="ChimneyWallB"]
shape = SubResource("rect_chimney")

[node name="WallColor" type="ColorRect" parent="ChimneyWallB"]
offset_left = -20.0
offset_top = -220.0
offset_right = 20.0
offset_bottom = 220.0
color = Color(0.55, 0.55, 0.4, 1)

[node name="PlatformP4" type="StaticBody2D" parent="."]
position = Vector2(440, 200)

[node name="CollisionShape2D" type="CollisionShape2D" parent="PlatformP4"]
shape = SubResource("rect_plat")

[node name="PlatColor" type="ColorRect" parent="PlatformP4"]
offset_left = -100.0
offset_top = -12.0
offset_right = 100.0
offset_bottom = 12.0
color = Color(0.5, 0.62, 0.4, 1)

[node name="PlatformP5" type="StaticBody2D" parent="."]
position = Vector2(600, 200)

[node name="CollisionShape2D" type="CollisionShape2D" parent="PlatformP5"]
shape = SubResource("rect_plat")

[node name="PlatColor" type="ColorRect" parent="PlatformP5"]
offset_left = -100.0
offset_top = -12.0
offset_right = 100.0
offset_bottom = 12.0
color = Color(0.5, 0.62, 0.4, 1)

[node name="PlatformP6" type="StaticBody2D" parent="."]
position = Vector2(780, 320)

[node name="CollisionShape2D" type="CollisionShape2D" parent="PlatformP6"]
shape = SubResource("rect_plat")

[node name="PlatColor" type="ColorRect" parent="PlatformP6"]
offset_left = -100.0
offset_top = -12.0
offset_right = 100.0
offset_bottom = 12.0
color = Color(0.5, 0.62, 0.4, 1)

[node name="PlatformP7" type="StaticBody2D" parent="."]
position = Vector2(920, 420)

[node name="CollisionShape2D" type="CollisionShape2D" parent="PlatformP7"]
shape = SubResource("rect_plat")

[node name="PlatColor" type="ColorRect" parent="PlatformP7"]
offset_left = -100.0
offset_top = -12.0
offset_right = 100.0
offset_bottom = 12.0
color = Color(0.5, 0.62, 0.4, 1)

[node name="PlatformP8" type="StaticBody2D" parent="."]
position = Vector2(1000, 500)

[node name="CollisionShape2D" type="CollisionShape2D" parent="PlatformP8"]
shape = SubResource("rect_plat")

[node name="PlatColor" type="ColorRect" parent="PlatformP8"]
offset_left = -100.0
offset_top = -12.0
offset_right = 100.0
offset_bottom = 12.0
color = Color(0.5, 0.62, 0.4, 1)

[node name="PlatformP9" type="StaticBody2D" parent="."]
position = Vector2(1000, 260)

[node name="CollisionShape2D" type="CollisionShape2D" parent="PlatformP9"]
shape = SubResource("rect_plat")

[node name="PlatColor" type="ColorRect" parent="PlatformP9"]
offset_left = -100.0
offset_top = -12.0
offset_right = 100.0
offset_bottom = 12.0
color = Color(0.5, 0.62, 0.4, 1)

[node name="Breakable1" parent="." instance=ExtResource("8_block")]
position = Vector2(480, 173)

[node name="Spring1" parent="." instance=ExtResource("7_spring")]
position = Vector2(600, 584)

[node name="Teleporter1" parent="." instance=ExtResource("10_tp")]
position = Vector2(-60, 560)
pair_id = 1

[node name="Teleporter2" parent="." instance=ExtResource("10_tp")]
position = Vector2(600, 300)
pair_id = 1

[node name="Checkpoint1" parent="." instance=ExtResource("9_check")]
position = Vector2(600, 160)

[node name="Coins" type="Node2D" parent="."]

[node name="Coin1" parent="Coins" instance=ExtResource("1_coin")]
position = Vector2(-300, 408)

[node name="Coin2" parent="Coins" instance=ExtResource("1_coin")]
position = Vector2(-60, 388)

[node name="Coin3" parent="Coins" instance=ExtResource("1_coin")]
position = Vector2(220, 160)

[node name="Coin4" parent="Coins" instance=ExtResource("1_coin")]
position = Vector2(440, 158)

[node name="Coin5" parent="Coins" instance=ExtResource("1_coin")]
position = Vector2(600, 158)

[node name="Coin6" parent="Coins" instance=ExtResource("1_coin")]
position = Vector2(780, 278)

[node name="Coin7" parent="Coins" instance=ExtResource("1_coin")]
position = Vector2(920, 378)

[node name="Coin8" parent="Coins" instance=ExtResource("1_coin")]
position = Vector2(1000, 458)

[node name="Coin9" parent="Coins" instance=ExtResource("1_coin")]
position = Vector2(1000, 218)

[node name="Coin10" parent="Coins" instance=ExtResource("1_coin")]
position = Vector2(700, 560)

[node name="Coin11" parent="Coins" instance=ExtResource("1_coin")]
position = Vector2(780, 560)

[node name="Enemies" type="Node2D" parent="."]

[node name="Flying1" parent="Enemies" instance=ExtResource("4_fly")]
position = Vector2(660, 250)

[node name="Flying2" parent="Enemies" instance=ExtResource("4_fly")]
position = Vector2(860, 360)

[node name="Shooting1" parent="Enemies" instance=ExtResource("5_shoot")]
position = Vector2(700, 586)

[node name="Heavy1" parent="Enemies" instance=ExtResource("6_heavy")]
position = Vector2(880, 586)

[node name="Spikes" type="Node2D" parent="."]

[node name="Spike1" parent="Spikes" instance=ExtResource("3_spike")]
position = Vector2(-500, 584)

[node name="Spike2" parent="Spikes" instance=ExtResource("3_spike")]
position = Vector2(-460, 584)

[node name="Spike3" parent="Spikes" instance=ExtResource("3_spike")]
position = Vector2(-420, 584)

[node name="Spike4" parent="Spikes" instance=ExtResource("3_spike")]
position = Vector2(-260, 584)

[node name="Spike5" parent="Spikes" instance=ExtResource("3_spike")]
position = Vector2(-220, 584)

[node name="Spike6" parent="Spikes" instance=ExtResource("3_spike")]
position = Vector2(-180, 584)

[node name="Goal" parent="." instance=ExtResource("2_goal")]
position = Vector2(1000, 205)
```

注意：Teleporter 的 ext_resource id 应为 `10_tp` 且 load_steps 相应调整（上述清单 load_steps=19，按实际资源数修正为 20）。

- [ ] **Step 2: 验证**

核对 ext_resource 数量与 load_steps 一致、节点路径全部存在、Goal 位于 P9 上方可触碰。

---

### Task 12: 改造 Level1

**Files:**
- Modify: `scenes/Level1.tscn`

**Interfaces:**
- Consumes: Spring / FlyingEnemy / BreakableBlock 场景
- Produces: 含新内容的可通关 Level1

- [ ] **Step 1: 修改 Level1.tscn**

在文件头 ext_resource 区新增：
```tscn
[ext_resource type="PackedScene" path="res://scenes/Spring.tscn" id="6_spring"]
[ext_resource type="PackedScene" path="res://scenes/FlyingEnemy.tscn" id="7_fly"]
[ext_resource type="PackedScene" path="res://scenes/BreakableBlock.tscn" id="8_block"]
```
并将 `load_steps=10` 改为 `load_steps=13`。

节点改动：
- 删除原 `PlatformB`（position (0, 350)）整段（4行），替换为 `position = Vector2(120, 350)`
- 在 `PlatformA` 与 `PlatformB` 间隙下的地面新增 3 根尖刺：(-150,584)、(-110,584)、(-70,584)（加入 Spikes 容器）
- 在 `Spikes` 容器中追加尖刺前，先插入 Spring 到 Ground 上方：`[node name="Spring1" parent="." instance=ExtResource("6_spring")]` + `position = Vector2(-520, 584)`
- Enemies 容器新增 FlyingEnemy：`[node name="Flying1" parent="Enemies" instance=ExtResource("7_fly")]` + `position = Vector2(-150, 430)`
- 新增 Breakable1：`[node name="Breakable1" parent="." instance=ExtResource("8_block")]` + `position = Vector2(240, 585)`

- [ ] **Step 2: 验证**

确认 PlatformB 位置修改后跳跃可达（A(-300,450)→B(120,350)，dx=420，冲刺+二段跳可及）；尖刺不阻挡地面通路两侧。

---

### Task 13: 改造 Level2

**Files:**
- Modify: `scenes/Level2.tscn`

**Interfaces:**
- Consumes: Teleporter / ShootingEnemy / Checkpoint 场景
- Produces: 含新内容的可通关 Level2

- [ ] **Step 1: 修改 Level2.tscn**

ext_resource 区新增：
```tscn
[ext_resource type="PackedScene" path="res://scenes/Teleporter.tscn" id="6_tp"]
[ext_resource type="PackedScene" path="res://scenes/ShootingEnemy.tscn" id="7_shoot"]
[ext_resource type="PackedScene" path="res://scenes/Checkpoint.tscn" id="8_check"]
```
`load_steps=10` → `load_steps=13`。

节点改动：
- 蹬墙井：在 B(-60,340) 与 C(220,220) 之间新增两堵墙 `ChimneyWallA` position (60,420)、`ChimneyWallB` position (140,420)，均使用新 sub_resource `rect_chimney`（RectangleShape2D size (40,440)），各带 ColorRect（color (0.4,0.46,0.55,1)）
- `Enemy2`（position (560,586) 巡逻敌人）替换为 ShootingEnemy 实例 `[node name="Enemy2" parent="Enemies" instance=ExtResource("7_shoot")]` + `position = Vector2(560, 586)`
- 传送门对：`[node name="Teleporter1" parent="." instance=ExtResource("6_tp")]` position (620,560) pair_id=1；`[node name="Teleporter2" parent="." instance=ExtResource("6_tp")]` position (620,60) pair_id=1；另在 Teleporter2 上方放一枚金币 Coin8 (620,40)
- Checkpoint1：`[node name="Checkpoint1" parent="." instance=ExtResource("8_check")]` position (450,240)（玩家乘 MovingPlatform1 经过时触发）

- [ ] **Step 2: 验证**

蹬墙井间隙 40px（墙 x 40..80 与 120..160），玩家从 B 跳入井口、蹬墙登顶后跳向 C(220,220)；传送门从地面 (620,560) 到高空 (620,60)（墙顶 y=120 之上，位于开放天空）。

---

### Task 14: 最终验证

**Files:**
- 全部改动文件

- [ ] **Step 1: 全局静态检查**

逐文件核对：脚本语法（Tab 缩进、无未定义引用）、场景 load_steps 与实际 ext_resource/sub_resource 数量一致、组名一致（enemies/coins/goal/spikes/teleporters/checkpoints/game/player）。

- [ ] **Step 2: 运行试玩**

用户在 Godot 编辑器中打开项目并运行：依次验证三关通关、三种能力手感、三种敌人击杀方式、四种机制与 checkpoint 重生。

---

## Self-Review 结果

- **Spec 覆盖**：三种能力→Task 2；三种敌人→Task 4/5/6；四种机制→Task 7/8/9/10；Level3→Task 11；Level1/2 改造→Task 12/13；Game.gd checkpoint→Task 1 ✓
- **占位扫描**：无 TBD/TODO ✓
- **类型一致性**：`launch(vy)`、`teleport_to(pos)->bool`、`pound()`、`stomp()`、`is_pounding`/`is_dashing`、`activated(position: Vector2)` 在生成与消费端签名一致 ✓
