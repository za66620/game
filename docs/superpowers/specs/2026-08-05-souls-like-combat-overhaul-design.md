# 类魂战斗手感重做设计文档

日期：2026-08-05
项目：demo-01（Godot 4.7 2D 平台动作游戏）

## 目标

在现有战斗系统（攻击/冲刺/格挡/弹反/体力）基础上，做一次类魂化改造：

- 攻击、闪避的**打击手感**全面强化（顿帧、震屏、粒子、残影、受击反馈）
- Boss 从"僵硬"改为**有前摇提示、连招、受击硬直、姿态破防、二阶段**的高质量战斗
- 操作不变（J 攻击 / L 冲刺 / S 格挡 / Space 跳），不动关卡布局

## 现有代码结构（改造前）

- `scripts/Player.gd`：CharacterBody2D，攻击（0.44s 动画+判定窗）、冲刺（0.23s 无敌）、格挡/弹反、下砸、体力条
- `scripts/Boss.gd`：简单状态机 CHASE→WINDUP→ATTACK→RECOVER→STAGGERED，3 变体共用，无阶段/连招/受击硬直
- `scripts/Game.gd`：主流程，HUD（血/体力/灵魂/Boss 血条）、存档点重生、死亡扣 25% 灵魂
- `scripts/Enemy.gd` / `FlyingEnemy.gd` / `ShootingEnemy.gd` / `HeavyEnemy.gd`：小怪
- `scripts/InputSetup.gd`：输入映射（autoload）
- 风格：ColorRect 占位、无新美术资源、现有 5 个音效（jump/coin/stomp/death/win）

## 1. 手感基础设施：GameFeel 管理器（autoload）

新增 `scripts/GameFeel.gd`，在 `project.godot` 注册 autoload。所有手感元素集中于此，参数一处可调。

| 接口 | 作用 | 实现 |
|---|---|---|
| `hitstop(duration: float)` | 命中顿帧 | `Engine.time_scale = 0`，用 `Time.get_ticks_msec()` 真实时间恢复；嵌套调用取最长时长 |
| `shake(intensity: float, duration: float)` | 震屏 | 持有 Main 上的 Camera2D（组 `"camera"`），`offset` 逐帧随机偏移按时间衰减 |
| `burst(pos: Vector2, color: Color, count: int)` | 命中粒子 | 实例化预载 `HitBurst.tscn`（一次性 CPUParticles2D，one_shot，爆完自毁） |
| `slow_mo(factor: float, duration: float)` | 慢动作 | `Engine.time_scale = factor`，真实时间恢复为 1.0 |
| `flash_red()` | 全屏红闪 | Main 上全屏 ColorRect 覆盖层，透明度渐隐 |
| `ghost_trail(pos: Vector2, color: Color)` | 残影 | 生成渐隐半透明方块（1 帧后自毁），冲刺/挥击连放 |

**改动文件**：
- `project.godot`：`[autoload]` 加 `GameFeel`
- `scenes/Main.tscn`：加 Camera2D（组 `"camera"`）、全屏红闪覆盖层
- 新增 `scripts/GameFeel.gd`、`scenes/HitBurst.tscn`

**玩家手感接入点**（Player.gd）：

| 事件 | 反馈 |
|---|---|
| 攻击命中敌人 | 顿帧 0.07s + 震屏(4, 0.15) + 粒子(敌位, 白/金) + 玩家后坐(反向 -80) + 音效 stomp |
| 击杀敌人 | 顿帧 0.12s + 震屏(6, 0.2) + 粒子爆发 |
| 挥击激活帧 | 剑弧残影（激活帧期间每帧 ghost_trail） |
| 冲刺 | 全程残影，结束小尘粒 |
| 弹反成功 | 金色粒子 + 顿帧 0.12s + slow_mo(0.3, 0.4) |
| 受击 | flash_red + 震屏(8, 0.3) + 顿帧 0.1s |

## 2. Boss 重做（Boss.gd 重写状态机）

### 状态机

```
INTRO(进场) → CHASE → WINDUP → ATTACK → [COMBO 续招] → RECOVER → CHASE
                     ↘ HITSTUN(被打断) → CHASE
STAGGERED(姿态破防) ← 姿态值攒满
PHASE_TRANSITION(50% 血) → 狂暴版循环
```

### 攻击表（数据驱动，每变体一套）

| 变体 | 招式 | 二阶段追加 | 提示弧颜色 |
|---|---|---|---|
| 0 投石蜗牛 | 单发弹 | 双发弹、跃起砸地 | 黄=远程 |
| 1 赤刃守卫 | 1 连快斩 | 2 连（二阶段 3 连）、冲锋斩 | 红=近战 |
| 2 龙兽 | 单火球 | 三连火球、俯冲扑击 | 黄=远程 |

攻击表字段：前摇时长、攻击帧时长、伤害、射程、弹速/弹数、连招上限、提示色。

### 机制

1. **前摇分级提示**：蓄力弧按攻击类型染色+脉动；Boss 蓄力时自身闪白；起手瞬间音效（复用 stomp）。玩家能区分"要躲"与"要贴身打"。
2. **受击硬直**：`hit()` 命中 → 若处于 WINDUP 则打断进 HITSTUN(0.25s) → 回 CHASE。打前摇是类魂核心奖励。
3. **姿态破防**：姿态值每刀 +20，满 100 → STAGGERED(1.5s 白打窗口) + 顿帧/震屏；弹反直接触发完整硬直（Player 现有 `stagger()` 调用链保留）。
4. **二阶段（≤50% 血）**：`PHASE_TRANSITION` 1.2s（slow_mo 0.3 + 震屏 + 红闪 + HUD 提示"已进入狂暴"），之后：前摇 -20%、移速 +15%、伤害 +4、连招上限 +1、永久红色微光。
5. **追击改进**：按下一招决定站位——近战贴脸追，远程保持距离；不无脑穿人。
6. **数值**：玩家 24 伤 vs Boss 140/180/230 血（约 6-10 刀）；Boss 伤害维持 3 刀内击杀玩家。

### 改动文件

- `scripts/Boss.gd`：重写状态机
- `scripts/Game.gd`：二阶段 HUD 提示消息

## 2.1 Boss 击败状态持久化（不复活）

**现象**：玩家击杀 Boss 后死亡，关卡重建导致 Boss 满血复活（与类魂设定冲突）。

**根因**：`Game.gd._on_player_died()` 调用 `_load_level()` 重新实例化整个关卡，Boss 无持久状态。

**修复**：
- `Game.gd` 新增 `bosses_defeated: Array[bool]`（按关卡索引）
- `_on_boss_defeated()` 记录 `bosses_defeated[current_level] = true`
- `_load_level()` 末尾：若该关 Boss 已击败 → 移除生成的 Boss、隐藏 Boss 血条、解锁 Goal（`monitoring = true` + 白色）
- 跨关推进（`_on_goal_reached` 下一关）不受影响；重开新游戏（R 重载）清空记录

## 3. 小怪统一命中反馈

Enemy / FlyingEnemy / ShootingEnemy / HeavyEnemy 统一接入 GameFeel：
- 被打：小顿帧 0.05s + 粒子 + 击退（velocity 反向推）+ 白闪（已有）
- 被击杀：顿帧 0.08s + 粒子爆发
- HeavyEnemy 撞墙眩晕同样接入

## 范围外（YAGNI）

- 不动关卡布局、不改玩家键位、不加新音效/美术资源、不做伤害数字、不加闪避后的攻击惩罚

## 成功标准

- 攻击命中有明显断点感（顿帧）、震屏、粒子；挥空不顿帧
- 弹反有慢动作高光时刻；受击有红闪强反馈
- Boss 每招前摇可读（颜色/闪光/音效），打前摇能打断
- 姿态破防窗口可稳定白打一轮
- 二阶段转场有仪式感，之后明显变快变凶
- 三关 Boss 全部可通关、无脚本报错

## 验证方式

项目无 Godot CLI 与自动化测试框架：静态检查（Tab 缩进、引用一致性、load_steps、组名、信号连接）+ 用户在 Godot 编辑器试玩。
