# 住宅室内与镜头完善（2026-10-22）

住宅模型由共享布局的71个部件增加到152个，保留原8个碰撞体和全部通路。新增厨房棋盘砖、木板分色与横向接缝、地毯内边、沙发靠垫、毯子条纹、橱柜门板/拉手、水龙头、杯子及踢脚线。它们均为 Blender 可编辑几何；细节位于现有地面、墙面或家具表面，不添加无碰撞的独立障碍物。

`godot/data/house_layout.json` 统一保存几何、室内材质颜色与镜头配置，`tools/generate_house_details.py` 读取并生成 `art/source/house_details.blend` 与 `godot/assets/house_details.glb`。叶片及其他源工程不变，总资源种类仍为19。

进屋后相机以住宅中心为主，混入28%人物位置，视角更高，正交尺寸采用用户缩放值的62%并限于8.5–17.5米。焦点及缩放按真实帧时间平滑过渡，出屋恢复用户选定的室外缩放；Q/V八方向旋转与滚轮保留。镜头配置在实例创建时读取，不在每帧访问磁盘。

进屋后隐藏常驻场景文字，交互对象名称、库存及床边操作仍由底部上下文提示提供；出屋恢复建筑标签。屋顶/墙体继续依镜头方向剖切，碰撞、视线、伤害及存档格式不变。本轮没有制作新的UI布局、自由俯仰、手柄或多层建筑镜头。

## 启动与验证

```powershell
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_house_details.py
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --editor --import --quit
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path godot
```

完整检查命令见 [美术第二轮](street-art-polish.md)。本轮 `work/interior-final-checks.log` 输出 ALL_CHECKS_OK：19份GLB重放一致，规则/背包/存取/承重、AI引敌脱离、安全休息跨日、住宅实际进出/搜刮/灯光/存读档全部通过，生产存档和导出指纹不变。

住宅测试新增八方向投影检查：人物保持在避开边缘UI的区域、地板四角位于画幅内；另验证室内滚轮缩放、出屋恢复缩放及常驻标签恢复。额外以960×540与1920×1080请求窗口运行相同的真实输入流程，结果与实景截图保存在 `work/interior-<resolution>.log/png`；实际PNG尺寸可能受桌面窗口限制。测试使用独立存档目录，不修改玩家快照。

未宣称全部缩放极限都容纳整栋房屋，手动拉近时允许观察局部；完整房屋构图测试使用默认缩放。当前仍是简单粗糙材质，没有贴图旧化、软装物理或自动隐藏所有场外植被，性能数据仅来自GTX1650 Compatibility环境。
