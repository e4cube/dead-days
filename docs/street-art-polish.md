# 街区美术第二轮完善

本轮在原有街区上继续制作真实模型，未扩张地图或替换生存系统。

- 新增 `street_ground.blend/glb`：52块人行道板、破损路肩、23处路面修补及分叉裂缝，共2076三角面、1网格，按材质分表面。为低高度视觉几何，不添加台阶或改变碰撞；门洞与家具导航保持原规则。
- 重做 `tree_oak.blend/glb`：三根分叉枝干、六簇非对称树冠、三色橄榄绿共享叶材质，替换原蓝绿色大球。仍为18棵，无透明叶片、风动或额外灯光。
- 三栋建筑增加石脚、基础色差和窗户修补木板。住宅974三角面，诊所656，商店704；修补部件遵守原前后遮挡命名，进屋后随对应立面隐藏。

所有源工程可编辑，生成脚本和重建命令沿用 [街区美术报告](street-art-pass.md)。总计19份源工程/GLB。旧文档中的18份为上一轮数量。

## 验证

在 Blender 5.2.2 LTS / Godot 4.7.2 Compatibility / GTX1650 实测：

```powershell
$env:PYTHONPATH = (Join-Path (Get-Location) 'work\test_dependencies')
python tools/run_checks.py --godot 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --blender 'D:\Blender\blender.exe' --visual
```

`work/polish-checks.log` 输出 ALL_CHECKS_OK：19份GLB及清单重放一致，旧版保护、物品事务与承重、街区碰撞与绕行、进屋剖面/搜刮/灯光/存读档、跑步引敌与脱离、危险中断睡眠、真实跨日休息通过。生产存档/导出指纹未变。

实际截图为 `work/street-day-gameplay.png`、`work/house-interior.png`、`work/house-exit.png`。`street-night-lighting-fixture.png` 是22:00灯光夹具，仅证明渲染；睡眠测试独立验证真实时间推进。截图由实际Godot窗口输出，未用生成图片替代。

仍缺少地面植被过渡、建筑污渍/破损材质、更丰富室内软装和最终UI；本轮不是最终美术或性能验收。树冠增加了几何细节，但没有低端设备帧率数据。后续先处理住宅室内材质与镜头构图，再扩展新区域。
