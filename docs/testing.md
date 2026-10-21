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
