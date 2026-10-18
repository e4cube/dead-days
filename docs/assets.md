# Blender → GLB → Godot

本轮只交付可重复管线验证资产：`DD_Prop_LootCrate`。不是角色/僵尸/动画美术包。

```powershell
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_assets.py
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --editor --import --quit
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/test_assets.gd
```

- Blender：米制、1单位=1米、Z向上、物体原点位于接地中心，应用缩放，统一 `DD_` 命名。
- 箱子尺寸 Blender XYZ = 1.2×0.7×1m。GLB 导出 `export_yup=True`，Godot XYZ = 1.2×1×0.7m。自动测试检查导入网格数及包围盒尺寸。
- 材质为单色低多边形、roughness=1，不使用贴图、重度 shader 或高面数。
- `art/source/loot_crate.blend` 为源工程；`godot/assets/loot_crate.glb` 为引擎输入；脚本可重新生成二者。
- .blend 特意保存在 Godot 工程外。直接放在 res:// 会触发 Godot 的 Blender importer，依赖编辑器的 Blender 路径设置；本轮发现并修正此问题。游戏只导入 GLB，不依赖 Godot 编辑器再调用 Blender。
- 资源导入设置 `.glb.import` 和 GDScript `.uid` 提交 Git；`.godot/` 缓存不提交。
- 游戏在三个柜子的位置实例化同一个 GLB，碰撞由 Godot 简单箱形体提供。资产不是截图替代品。
- 脚本只允许 Blender 后台运行，防止清空交互式打开的源工程。每次运行重生成指定箱子源文件与 GLB；手工修改前先另存副本。

下一批应定义人物骨架与动作契约，再生成玩家/僵尸 stand、move、attack、hurt 动作；当前方块人物是明确的占位模型，没有声称具备这些动画。
