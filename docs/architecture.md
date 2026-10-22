# 重构架构与规则审计

## 范围与当前成果

阶段 A 已建立独立 Godot 4 工程、数据与逻辑边界、旧版保护、可执行检查、Blender/GLB 导入验证。
阶段 B 实施搜刮与日志闭环：主菜单 → 实体门 → 入屋 → 有限物资容器 → 负重背包 → 使用食物 → 手写与自动日志 → 跨建筑搬运 → 保存退出 → 继续。阶段 C1 的增量见 [AI与战斗](c1-threats.md)，C2见 [时钟与休息](c2-survival-time.md)；C3的首批资产契约见 [Blender资源](assets.md)，仍未完成整张需求清单。

| 文件/模块 | 责任 |
| --- | --- |
| `main.py`、`legacy/README.md` | v0.3 对照入口，只有自检安全修复 |
| `godot/data/rules.json` | 物品效果与重量、容量、建筑身份与初始库存、移动/体力数值 |
| `godot/scripts/survival.gd` | 纯状态模型、库存事务、物品效果、结构化事件、输入存档校验、Markdown |
| `godot/scripts/save_store.gd` | 独立用户目录、不可变快照、临时文件提交、有效快照回退 |
| `godot/scripts/game.gd` | 小型场景生成、CharacterBody3D、相机、交互距离/空间校验、UI、输入；后续扩张前应拆出场景生成器与面板 |
| `godot/scripts/zombie.gd`、`navigation.gd` | 物理感知与有限记忆AI、实际角色移动、A*与门更新 |
| `godot/scripts/survival_time.gd`、`rest.gd` | 游戏分钟、生理/每日总结、休息资格与计划；加速世界由game.gd协调 |
| `tools/generate_assets.py`、`check_asset_pipeline.py` | 后台生成10个源工程/GLB、骨架动作、清单与独立重放检查 |
| `godot/scripts/character_visual.gd`、`asset_library.gd` | 真实蒙皮动作按模拟时间采样、装备显示、建筑外观/室内剖面，GLB不拥有玩法碰撞 |
| `godot/tests/`、`tools/run_checks.py` | 规则、导入、真实物理操作链及旧存档哨兵回归 |

Godot 是实际引擎。Blender 仅为离线资产生产工具。资源、UI、碰撞只消费规则状态；容器的物资转移发生在模型中，不能再次刷出。背包装满时剩余物品继续保留在容器内。使用物品同时减少数量与恢复对应属性；满值时拒绝消耗。场景负责验证靠近且在屋内，再允许搜刮。

## 世界与遮挡

一条街道、住宅/诊所/杂货店三个 5.5m 宽的房间。C3提供完整外观/屋顶，玩家进入对应建筑时隐藏该屋顶及前/东完整墙，并显示低剖面；保留完整碰撞和AI视线。其他建筑继续显示完整外观。每栋门关闭时有门洞碰撞，开启后清空门洞并启用旋转门板的碰撞。门口有人时不允许关门。柜子有独立碰撞。街区边界阻止离开测试区域。相机为正交等距，WASD 当前对应世界 X/Z 方向，非屏幕方向。

## 状态与存档

新版本仅使用 `%APPDATA%/DeadDaysRebuild/`，不读取/迁移/覆盖根目录 save.json。`saves/` 内每次保存新建唯一名称快照，先写 .tmp、flush、close，再 rename；旧快照不清理。读档按名称由新到旧检验，跳过截断 JSON 与不支持的 schema，全部失败时保留内存状态与磁盘文件。

当前 schema 4 包括天数/分钟、位置、属性、库存、门状态、各容器剩余物资、首次进入集合、完整事件，以及 combat、zombies、noises、noise_sequence、seen_horde、calendar/rest。containers 保留建筑柜子的原ID，新增 home_fridge 等家具容器ID。数值、容器/物品身份、重量均先验证；schema4缺少家具库存时拒绝，不能通过删字段重新补货。schema1在内存添加威胁状态，schema1/2添加时钟/休息，schema1/2/3最后补入家具库存升级到4，旧文件不改；已有库存不覆盖。schema1添加敌人时跳过距玩家4米内刷点。未知schema拒绝。临时文件不参与继续游戏。没有持久化场景 Node 或 GLB 内部结构。测试使用唯一 `user://tests/` 子目录，绝不使用正式 saves/。

不可变快照目前会持续占用磁盘；保留策略、多存档槽选择、异常恢复界面是后续工作。该方案降低中断写入风险，不宣称提供断电硬件事务保证。关闭窗口或 Esc 保存失败时留在当前游戏。

## 事件与日志

事件有 id、kind、day、minutes、text、mood、payload。类型包括 started、door、entered、looted、used、manual，以及 equipped、first_zombies、injured、near_death、killed、died、escaped、migrated，以及C2的need_warning、need_empty、rest_started、rest_finished、rest_interrupted、sleep_danger、daily_summary。文本对应已发生的状态变化；loot payload 保存获得的具体物品数量。首次进入去重，手写保留五种心情。支持实际 Markdown 文件导出。C2统一推进时间，午夜从真实事件生成每日总结，支持睡到第二天与中途存档；时钟/休息规则在独立模块管理。

## v0.3 审计：可复用设计与限制

- 原世界为 120×120 逻辑格，以 seed 重建；搜刮状态按容器列表索引保存。重建后顺序变化会破坏映射，新工程改用稳定建筑/容器 ID。
- 原档保存 seed、day、minutes、player、inv、looted、journal、stats，缺少 schema、校验、原子写入。没有保存僵尸状态、首次发现状态、每日计数器；读档后僵尸清空，日统计重置。
- 原规则：一天现实360秒；饥饿100/600秒、口渴100/480秒、精力100/1400秒衰减；跑步额外6/秒；饥渴归零掉血，饱食时回血。迁移时作为平衡参考，不直接硬搬。
- 三类消耗品与拳头/棒球棍/砍刀可以继承物品意图；原版无重量容量，搜刮时才随机决定物品，新版采用预先存在的有限库存。
- 原近战有冷却、角度范围、伤害、击退；僵尸仅以距离索敌，跑步扩大索敌距离，撞墙后随机转向。没有墙体视线检测、真正的声音事件、路径搜索、记忆状态，因此不能直接认定为目标 AI。
- 原睡眠检查半径150内僵尸，跳到黎明、恢复精力、减少饥渴、回血；25% 概率生成两个僵尸。其“拍门惊醒”文字并无门受击事件支持，迁移后必须基于真实世界威胁。
- 原首次击杀、受伤、低血量、首次见僵尸、黄昏、黎明总结触发条件可复用；文案中的虚构细节与自动随机心情应按真实事件重写。手写、心情标签、每日总结和 Markdown 导出是保留方向。
- 原正常游戏死亡删档属于原有规则，本次不改；原自检无隔离才是优先修复的问题。
