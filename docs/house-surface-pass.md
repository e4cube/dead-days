# 住宅厨房与客厅材质/结构增量

本轮围绕同一组家具改善结构和材质，不扩地图或新增生存规则。住宅由155增至166个布局模块，保留原8个家具碰撞与通路。

## 实际改动

- 橱柜移除水槽下方的实心占位体，改为背板、侧板、底板、踢脚、前框和分隔板；原门板、拉手继续复用。
- 水槽保留真实凹盆，新增排水口；直柱加方块的龙头改为有厚度的弯管几何。
- 沙发新增4个接触地面的支脚，座垫、靠背和扶手保持原圆角几何；没有改变碰撞或加入坐下功能。
- 八份共享材质配方区分横向/竖向木纹、织物、瓷面及拉丝金属。程序细纹在近景可见，利用像素导数逐渐淡出高频细节，减少远处闪烁；不使用额外灯光或屏幕后期。

配方保存在 `godot/data/house_layout.json` 的 `surface_profiles`，每个模块用 `surface` 引用。Blender生成器同步写入基础颜色、粗糙度与金属度；GLB保留这些基础材质，细纹由Godot的 `shaders/interior_surface.gdshader` 和 `scripts/interior_surfaces.gd` 应用。细纹没有烘焙进GLB贴图，因此在Blender或通用GLB查看器中不会完全复现运行时细节。

室内细纹为项目自行编写的程序材质，没有引入外部图片。已审核的GameVado/Poly Haven室外地表、原图和许可记录不改动；也未替换道路、角色或诊所/商店材质。

## 重建与运行

```powershell
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_house_details.py
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --editor --import --quit
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path godot
```

继续原有室外等距/室内近颈后镜头，W/S前后、A/D转向、E搜刮、B存取、L灯光。材质和模型不写入存档格式。

## 验证与截图性质

`test_interior_surfaces.gd` 检查8份共享配方实际载入、50个以上导入部件使用材质、4个沙发支脚和水槽深度、实心占位块已移除，并确认预览不替换导航碰撞。图形运行会生成：

- `work/surface-kitchen-detail-preview.png`
- `work/surface-living-detail-preview.png`

这两张是实际Godot渲染的**家具细节预览**，使用固定相机并隐藏角色和HUD，不冒充玩家操作镜头。真实移动/进出/搜刮仍由 `test_house_slice.gd` 等端到端测试覆盖，操作镜头截图为 `work/house-kitchen.png` 等。

完整检查命令沿用 `tools/run_checks.py --godot ... --blender ... --visual`，本轮日志 `work/surface-final-checks.log`。检查包含21份GLB重放、素材许可/哈希、地表渲染、原规则/AI/跨日睡眠、三栋建筑与室内灯光，测试继续使用隔离存档和生产文件指纹保护。

实际结果：ALL_CHECKS_OK，包含新增 INTERIOR_SURFACES_OK；生产存档/导出指纹未变。本阶段完成后按用户2026-10-23授权，将素材库接回提交和本轮改动一并推送到原开发分支。

尚未加入真实污渍贴图、破损网格、柜门开合、水流、烹饪或家具使用动画；程序纹理仍是简化材质，未声称已达到参考作品美术精度，也没有普通集显帧率结论。
