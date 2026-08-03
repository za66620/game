# 核心玩法扩展设计文档

日期：2026-08-03
项目：demo-01（Godot 4.7 2D 平台跳跃游戏）

## 目标

在现有平台跳跃 demo 基础上添加核心玩法内容：

- 新玩家能力：冲刺、爬墙+蹬墙跳、下砸
- 新敌人：飞行敌人、射击敌人、重甲敌人
- 新关卡机制：弹簧、传送门、可破坏砖块、存档点
- 新增第3关，并改造现有第1、2关融入新内容
- 难度定位：适中，能力始终可用、无需拾取

## 现有代码结构

- `scripts/Game.gd`：主流程（关卡加载、生命、金币、胜负、HUD）
- `scripts/Player.gd`：CharacterBody2D，二段跳、踩踏敌人
- `scripts/Enemy.gd`：巡逻敌人，可踩踏
- `scripts/Coin.gd` / `Goal.gd` / `MovingPlatform.gd` / `InputSetup.gd` / `AudioManager.gd`
- `scenes/`：Main / Level1 / Level2 / Player / Enemy / Coin / Goal / Spike / MovingPlatform
- 风格：占位图形（ColorRect）、场景直接手工摆放、脚本短小单一职责

## 1. 玩家能力（改造 Player.gd）

| 能力 | 操作 | 规则 |
|---|---|---|
| 冲刺 Dash | Shift | 水平方向快速位移 0.15s（速度约700），冷却 0.5s，冲刺中无敌 |
| 爬墙 | 贴墙按住方向键 | 贴墙时下落速度受控，可反复使用 |
| 蹬墙跳 | 贴墙时按跳 | 向反方向起跳 |
| 下砸 Ground Pound | 空中按 S/↓ | 垂直快速下落，落地产生冲击波击杀周围敌人，随后小弹跳 |

InputSetup.gd 添加 `dash`（Shift）与 `down`（S/↓）动作。

## 2. 新敌人（独立脚本+场景）

- **FlyingEnemy**：空中正弦上下浮动巡逻，可踩踏击杀
- **ShootingEnemy**：地面巡逻，同水平面检测到玩家时周期性发射子弹；子弹撞墙/玩家消失；可踩踏击杀
- **HeavyEnemy**：平时慢速巡逻，玩家进入视野后冲刺；撞墙眩晕 2 秒（期间可踩踏击杀）；撞击玩家则玩家死亡

## 3. 新关卡机制（独立脚本+场景）

- **Spring**：踩上强弹跳（垂直速度约 -900），带压缩动画
- **Teleporter**：成对放置，进入 A 从 B 出现，0.5s 传送冷却防循环
- **BreakableBlock**：被下砸或冲刺击中碎裂，可含金币奖励
- **Checkpoint**：触碰激活（变色），死亡后从最近存档点复活

## 4. 关卡规划

- **Level3.tscn（新增）**：综合关卡，串联所有新机制与三种新敌人，中段放置 checkpoint
- **Level1 改造**：冲刺教学段、一处下砸破砖、1 个飞行敌人、弹簧
- **Level2 改造**：蹬墙跳垂直墙段、射击敌人、传送门解谜段、checkpoint

## 5. 流程与杂项

- `Game.gd`：死亡时若已激活 checkpoint 则回 checkpoint 重生（生命照扣），否则回关卡起点
- 音效：复用现有 jump/coin/stomp/death/win
- 无新美术资源，沿用 ColorRect 占位风格

## 成功标准

- 三种新能力手感正常、互不冲突（二段跳、冲刺、下砸、蹬墙跳）
- 三种新敌人行为符合预期、均可击杀
- 四种新机制功能正确
- 三关均可正常通关
- 项目在 Godot 4.7 中无脚本报错
