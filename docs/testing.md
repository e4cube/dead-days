# 启动、检查与验证记录

从 `D:\github\dead-days` 执行，推荐 Godot 4 Compatibility 渲染。尚未打包独立 exe。

## 启动

```powershell
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --editor --import --quit
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path godot
```

或用 Godot 导入 `godot/project.godot` 后运行主场景。首次启动前必须先导入 GLB。引擎不在该位置时替换可执行文件路径。

- WASD：世界 X/Z 方向移动；Shift：跑步并消耗体力、制造声音；空格：近战攻击。
- E：附近门开关；屋内靠近柜子时搜刮可携带物资。先离开门洞才能关门。
- I：背包，点击按钮使用物品；关闭面板后也可按1食物/2水/3绷带，4装备已持有的木棍。
- J：真实事件日志；输入文字、选择心情、点击写入，或导出 Markdown。
- F5：保存新快照；Esc：关闭面板，或保存回菜单。窗口关闭前也保存。
- C：据点工事与制作；站在门旁显示修门/加固，站在据点内显示烹饪热餐/裁制绷带。制作期间移动或空格停手，材料退还。
- E（别墅工事）：站到院子门/别墅门/泳池旁按 E。未装＝开工（需带齐材料），已装的门＝开/关，泳池＝接一瓶水；靠近别墅时 C 面板顶部列出三处工事状态。
- G：把当前所在的室内地点设为据点（街道住宅、别墅、市集、工厂均可；别墅二层与一层同属一个据点）。
- 面板打开时暂停整个世界。C2新档08:00开始；R短休、夜间T睡到黎明，移动或T起身。

新档与导出位于 `%APPDATA%/DeadDaysRebuild/` 的 saves/ 和 exports/；测试使用 tests/，不接触正式 saves/。继续游戏选择最近有效快照。

## 自动化检查

需要 Python 3.12+ 与 pygame（旧版测试依赖）。本机 PATH 的 python 是占位程序，使用实际运行时：

```powershell
& 'C:\Users\11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/run_checks.py --godot 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --visual
```

去掉 --visual 则全部无头。总入口检查退出码、成功标记与 SCRIPT ERROR/ERROR 输出，每个子进程有90秒超时。图形运行截图写入忽略的 work/playthrough.png，日志可用 `> work/checks.log 2>&1` 保留。

单项：

```powershell
# 旧版原有测试（现已隔离真实存档）
python main.py --selftest
# 新工程规则/存档
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/test_rules.gd
# GLB尺寸和Y轴
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/test_assets.gd
# 实际物理操作闭环
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path godot --script res://tests/test_playthrough.gd
```

## 阶段 A/B 实测（2026-10-19，历史基线）

- Blender 5.2.2 LTS：后台 bpy 脚本成功；保存 .blend 并导出2040字节 GLB。
- Godot 4.7.2：无头导入/脚本运行成功；图形窗口 OpenGL 3.3 Compatibility / GTX1650 完成端到端操作，截图已检查。
- LEGACY_SAFETY_OK：旧自检完整运行，哨兵存档不被修改或删除，导出不落在真实 exports；异常路径恢复全局路径与随机数状态。真实旧存档/exports 清单与哈希前后一致。
- RULES_OK：有限库存、重复搜刮、物品真实消耗和属性恢复、缺失物品拒绝、负重与溢出保留、首次进入去重、心情导出、不可变快照、完整往返、损坏最新档回退、缺档不破坏内存、错误类型/负数/超重拒绝。
- ASSET_IMPORT_OK：Godot 中箱子网格数1，尺寸1.2×1×0.7米，坐标轴转换正确。
- PLAYTHROUGH_OK：菜单按钮开始；Input action驱动 CharacterBody3D 从门外行走，验证关门阻挡；E开门入屋、搜刮；背包按钮使用食物；日志按钮手写/心情和实际Markdown导出；出屋关门、携物走到诊所、开门入屋取得绷带；Esc保存回菜单、继续按钮恢复整个状态。
- ALL_CHECKS_OK：以上通过才打印总成功标记。

端到端验证是**图形窗口内的自动化试玩**，菜单通过 pressed 信号、交互通过真实处理入口、移动通过 Input action 和实际物理帧；并非人工键鼠试玩，也未验证僵尸追击、睡眠到第二天等尚不存在的功能。自动化不传送玩家越过门墙。尚未进行长时运行、集显性能和独立导出包测试。

## 本轮发现并修正的验证问题

- 原自检随机战斗曾偶发失败：入口固定种子并在finally恢复随机状态。
- GDScript 动态值类型推断错误：明确标注类型后重跑。
- JSON 数字解析为浮点；往返测试按JSON语义比较，不比较原始数值字符串格式。
- 关门用例开始仍在门洞：调整真实行走距离后验证关门，保留“不能夹住玩家”的限制。
- .blend 放入 res:// 引发依赖 Blender 编辑器路径的导入失败：源工程移到 art/source，Godot 只导入 GLB 后重新跑完整验证。


## 阶段 C1 增量验证（2026-10-19）

相同的总入口现在额外运行THREATS_OK与ESCAPE_PLAYTHROUGH_OK；--visual会用真实OpenGL窗口运行原搜刮闭环和新追击脱离闭环。新规则测试包含schema1迁移和schema2活跃敌人存档。完整测试通过后打印 `ALL_CHECKS_OK / legacy and Godot production saves/exports unchanged`。

```powershell
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/test_threats.gd
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path godot --script res://tests/test_escape.gd
```

本轮通过：原自检保护、原搜刮闭环、扩展规则与存档、GLB导入、物理AI/战斗fixture，以及实际图形窗口追击/关门/搜索中存读档/脱离/日志。截图检查还发现并修复VBox背景被布局器压为零高的问题，日志与背包现在有完整深色底板。

没有验证睡眠、第二天与每日总结，因为它们仍未实现。AI/战斗单项fixture会摆放角色来隔离边界情形；端到端test_escape从开局到结束不进行传送。全部为自动化试玩，非人工键鼠操作。


## 阶段 C2 增量验证（2026-10-21）

总入口新增TIME_RULES_OK、REST_SAFETY_OK和SLEEP_PLAYTHROUGH_OK。--visual会实际运行“入屋→床→夜晚→睡眠中存读档→第二天→每日总结与导出”，生成work/c2-*.png。运行时世界持续模拟，危险中断另有物理fixture。

本轮Codex bundled Python的pygame依赖已不再存在；把测试依赖安装到忽略的work/test_dependencies，不再依赖修改全局运行时：

```powershell
& 'C:\Users\11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m pip install --target work/test_dependencies pygame==2.6.1
$env:PYTHONPATH = (Resolve-Path work/test_dependencies).Path
& 'C:\Users\11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/run_checks.py --godot 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --visual
```

如果使用自行建立并已安装requirements.txt的Python环境，无需PYTHONPATH。原Python入口不会自动安装依赖。


## 阶段 C3 增量验证（2026-10-21）

```powershell
$env:PYTHONPATH = (Resolve-Path work/test_dependencies).Path
& 'C:\Users\11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/run_checks.py --godot 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --blender 'D:\Blender\blender.exe' --visual
```

--blender可选，用独立work目录重建并核对GLB字节，不改正式资源。ASSET_IMPORT_OK扩展到全部10个资产与16骨骼/五动作/蒙皮采样；VISUAL_INTEGRATION_OK验证屋顶剖面、开门板碰撞、家具旧位置修复、真实动作选择。--visual额外生成work/c3-poses.png，原搜刮、C1追击和C2睡眠图形试玩同步使用新模型。

原源码的碰撞/规则逻辑继续承担因果关系，动画只消费真实状态。当前没有独立exe或普通集显性能结果。资产清单和详细规范见docs/assets.md。
## 阶段 D1 增量验证（2026-10-28）

`SITES_V1_OK` 验证别墅三处工事：负重一趟可达、远处拒绝/门旁允许、材料先扣、半程不生效、完工登记真实门与耐久、`barrier_at` 只在已装+关闭+跨线时成立、开门放行、撞坏失效、修回与加固、泳池按天配额与满负重拒绝、危险中断退款、schema5→6 迁移与拒绝非法组合、读档恢复。

```powershell
& 'D://GameDev//Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/test_sites_v1.gd
```

## 阶段 D2 增量验证（2026-10-29）

`GOALS_V1_OK` 验证小目标：新档四个目标全未完成、背包里的水不算储备、存进据点柜子才算、达到阈值后只写一条日志；2 瓶水存进别墅柜子不会让住宅据点的目标完成（3+2 正好跨门槛，是真实判别条件），改设别墅为据点后同一批物资立刻算数；短途不触发、越过 55m 完成、回家不回退；装好院子门后完成；连续推进不重复写日志、`done` 无重复 id；schema6→7 按字段存在性迁移、写着 7 却缺 `goals` 的快照被拒绝且 `restore` 会补齐；未知 id、重复 id、负距离、超界距离、超前时间戳、`goals` 非字典六种非法状态全部拒绝；完成状态与距离记录读档后保留且不重新播报。

`TWO_DAY_LOOP_OK` 是路线图要求的连续两天验收，用一份存档走完整个循环并中途存读档：确认据点 → 抵达市集触发发现 → 搜刮（件数守恒）→ 挨打记录受伤 → 脱离 → 回屋吃喝治疗 → 存物资（每条 `stored` 对应一件）→ 手写日记 → 推进到夜间 → 睡到黎明进入第 2 天。断言第 1 天 `daily_summary` 恰好一条且 `summary_day`、`searches`、`stored`、`manual` 与实际行动一致；读档后位置、背包、容器、发现记录、目标进度全部一致。第二天再出门、回家、睡第二夜进入第 3 天，`daily_summary` 变成两条，读档状态仍然合法。

```powershell
& 'D://GameDev//Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/test_goals_v1.gd
& 'D://GameDev//Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/test_two_day_loop.gd
```

两个测试都已注册进 `tools/run_checks.py`（`TWO_DAY_LOOP_OK` 超时放宽到 150 秒）。

## 阶段 E1 增量验证（2026-10-30）

Web 导出没法靠单元测试覆盖，只能靠真实浏览器走完点击链路，记录见 [网页版导出](web-export-v1.md) 第三节：无头 Chromium 打开静态服务后确认引擎版本、WebGL2、画布 1280×720、标题页中文完整、点「新游戏」进入街区、按 W 走动让时钟从 08:00 走到 08:11 且门交互提示出现、按 F5 后 `localStorage` 出现 31415 字节快照、页面级 JS 异常为 0。

同时确认一条排查结论：`.godot/imported` 缓存过期时，实例化 glb 会刷 `texture_set_size_override: Parameter "texture" is null`（原生 GL Compatibility、Forward+/Vulkan、Web 三端行为一致，135 条），跑一次 `--import` 重新导入即归零。导出脚本第一步就是 `--import`，因此正式产物不受影响；场景压缩会把它带回来，但已用逐像素对照证明不影响画面。

```powershell
& 'D://GameDev//Godot_v4.7.2-stable_win64.exe' --headless --path godot --editor --import --quit
python tools/build_web_fixed.py
python -m http.server 8777 --directory web
```

## 阶段 F1 增量验证（2026-10-30，存档可靠性）

`SAVE_SLOTS_OK` 覆盖三槽隔离、快照轮转与备份导出，九组断言见 [存档可靠性 v1](save-slots-v1.md) 第六节。一条必须记住的纪律：**测试只能写 `user://tests/`**。

```powershell
& 'D://GameDev//Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/test_save_slots_v1.gd
python tools/run_checks.py --godot 'D:\GameDev\Godot_v4.7.2-stable_win64.exe'
```

`run_checks.py` 末尾的指纹断言会比对 `save.json`、`user://saves`、`user://exports` 在整轮前后的 SHA-256。第一版槽位测试直接调用了默认导出目录，把七个 `dead-days-slot1_*.json` 写进了玩家真实 `exports/`，于是整轮以 `Protected player files changed!` 失败——断言工作正常，是测试写错了地方。修法是给 `Slots` 加可覆盖的 `export_root`，测试指到自己的临时目录；被污染的文件已移到 `work/test-pollution/exports/` 留档，`exports/` 恢复为空。

顺带两条环境经验：

- 本机 `python`（3.13.12 托管版）没有 pygame，跑 `run_checks.py` 会用
  `C:\Users\11\.workbuddy\binaries\python\envs\default\Scripts\python.exe`（已装 pygame 2.6.1）。
- `git push` 到 github.com:443 仍然不通，提交走 `work/api_push_tree.py`（REST API 直连）。

## 阶段 F2 增量验证（2026-10-30，长时生存）

`LONG_SURVIVAL_OK` 是十日实跑，断言清单见 [长时生存](long-survival-v1.md) 第四节。两个只读测量脚本不进总入口，改数值时手动跑：

```powershell
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/test_long_survival.gd
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/audit_supply.gd
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/audit_containers.gd
```

写这条测试时踩到的两个真问题，都会影响以后写同类型脚本：

- **修门的位置不是睡觉的位置**。床在家宅深处（z≈-3.5，半径 1.7），门在 z=0，站床边点修门会被判"需要站到门旁"。测试里必须真的走过去。
- **破门之后 `toggle_door` 会拒绝**，得先修好才能关。修好的门是开着的，要自己关一次床才可用。这不是 bug，是"不能白送一间安全屋"。
- 出门前别把水和食物塞满背包：5 kg 上限下，3 瓶水 + 2 罐头就是 4.9 kg，当天在工厂就只剩 0.1 kg，锤子和木板一件也拿不回来。测试第一版就是这么红的（第 4 天修门失败：`缺少工具：锤子`）。

## 阶段 F3 增量验证（2026-10-31，声音空间）

```powershell
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/test_audio_space.gd
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path godot --script res://tests/test_game_audio.gd
```

`AUDIO_SPACE_OK` 是纯数学 + 节点行为，无需窗口；`GAME_AUDIO_OK` 在真实场景里补了三条（看见玩家吼、挨打叫、倒下死）。断言清单见 [声音空间](audio-space-v1.md) 第五节。

这一轮踩到的坑：

- **正交相机下不能用引擎的 3D 衰减**。相机吊在 20 m 高空，脚边和 40 m 外到 listen 的距离只差 5 dB，动态范围整个被吃掉。改成 `ATTENUATION_DISABLED` + 自己按平面距离算 `volume_db`，只让 3D 播放器负责左右声像。
- **测试里的僵尸 fixture 会污染后续断言**。`test_game_audio` 前半段为了测空枪把手枪装上并打空，武器就一直停在手枪上；后面再调 `try_attack()` 会静默返回 false（`begin_attack` 因空弹匣拒绝），看起来像"僵尸不叫"。真实原因是**没切回木棍**。写场景测试时，凡是跨段复用的状态（武器、体力、冷却、panel），都要在段落开头显式重置。
- **已经在追击的僵尸永远不会再吼**。`growl` 只在 `mode != chase` 时触发，所以想验三种声音必须**换一只新僵尸**，不能在打过的那只身上接着测。
- 远处被拒的吼叫**不该消耗冷却**：`zombie_voice` 先算能否播出，成功了才记时间戳。否则"远处吼了但你没听见"会白白吃掉下一次。

