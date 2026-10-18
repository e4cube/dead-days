# 阶段 A：本机检查与保护（2026-10-19）

- 仓库：`D:\github\dead-days`（Windows 实际显示 `D:\GitHub\dead-days`）。
- 初始分支 `main`，初始提交 `33c9d31`，标记 v0.3；初始工作区干净，无待保护的未提交修改。
- origin fetch/push 均为 `https://github.com/jin123yi123-sudo/dead-days.git`。
- 本地跟踪信息显示 `origin/main [gone]`；未执行 fetch/push，因此不据此判断服务器上的分支是否存在。
- 开发分支 `feature/dead-days-rebuild`。`main` 保持 v0.3；另建立本地 `legacy-v0.3` 标签。
- 未发现适用的 AGENTS.md；未改动仓库外的项目文件。
- Blender：`D:\Blender\blender.exe`，后台执行返回 **5.2.2 LTS**，`bpy` 可用。
- Godot：初次 PATH 检查未发现；后续递归扫描找到 `D:\GameDev\Godot_v4.7.2-stable_win64.exe`，本机 `--headless --version` 返回 **4.7.2.stable.official.ed1daf0bf**。这是本机二进制的报告值。
- 发现引擎前下载过官方 GitHub 的 Godot 4.5.1 便携包，保存在忽略的 `work/godot/`，不安装、不加入交付、不用于最终测试。
- 实际图形运行：OpenGL 3.3 / Compatibility，NVIDIA GeForce GTX 1650；不能据此声称已经在集显笔记本上完成性能验证。
- PATH 中 `python.exe` 是 WindowsApps 占位程序。实际测试使用 Codex bundled Python 3.12.14；该运行时原无 pygame，本次安装 pygame 2.6.1。根目录 requirements.txt 仍为旧项目依赖约束。

## 已修复的真实风险

原 `selftest()` 直接使用根目录 `save.json` 和 `exports/`。测试先保存，随后调用 `die()`，后者删除 SAVE_FILE；因此会覆盖并删除真实玩家存档。现公共自检入口先创建 TemporaryDirectory，重定向存档与导出，再运行原测试，finally 恢复路径和随机数状态。固定测试随机种子，消除地图与战斗随机性引起的偶发失败；正常游戏仍使用原来的随机逻辑。

`tools/run_checks.py` 使用独立哨兵存档验证正常自检与故意抛异常的路径恢复；并比较真实旧存档及 exports 文件清单与 SHA-256。检查前根目录没有 save.json；检查后仍不存在。原有 exports 未改变。普通旧版游戏的永久死亡删档规则没有修改；本次只修复自检隔离。
