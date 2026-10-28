# 街区美术首轮（2026-10-22）

采用“概念图 → Blender 几何 → Godot 实景验证”。内置 image_gen 以原游戏布局截图为输入，生成一张街区目标图；输入、概念图及完整提示词保存在 `art/concepts/`。生成图仅为设计参考，没有作为游戏贴图或运行证明。

## 实际交付

新增六套原创程序化资源，每套保留 `.blend` 与 GLB：废弃汽车924三角面、路灯220、木围栏484、垃圾桶156、草丛72、碎石纸屑116。总资源种类由12增至18。住宅增加屋顶接缝、脊线和立面收边，诊所/商店增加通风口，统一为较低饱和度材质。

`godot/data/street_art.json` 定义19处摆件及275丛草。汽车、围栏和垃圾桶的简化实体碰撞进入原寻路数据；草采用共享 MultiMesh、关闭投影并在45米裁剪。两盏路灯跟随现有昼夜规则，局部光不启用阴影。房屋内外遮挡和既有生存机制继续使用原实现。

## 重建与运行

在仓库根目录执行，生成器会重建对应生成资产，手工修改前应另存副本：

```powershell
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_assets.py
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_house_details.py
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_street_art.py
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --editor --import --quit
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path godot
```

## 真实验证与限制

Blender 5.2.2 LTS 后台重放18份GLB及清单逐字节一致。完整检查通过：旧版自检隔离、库存存取与承重、导入与骨架、碰撞导航、AI追击脱离、安全休息到第二天、住宅进出/剖面/搜刮/灯光/存读档。生产存档和导出文件指纹未变。

新增 `test_street_art.gd` 检查资源预算、草批次、汽车碰撞及绕行、昼夜路灯。`preview_street.gd` 用真实移动输入走到街道中央，输出 `work/street-day-gameplay.png`；夜景 `work/street-night-lighting-fixture.png` 为明确设置22:00的灯光夹具，不能代表整夜试玩。原睡眠端到端测试另行验证真实时间推进。

实际渲染采用 Godot 4.7.2 Compatibility / GTX1650；截图窗口请求1920×1080，实际输出尺寸以PNG为准。没有稳定帧率或集显性能结论。

当前画面仍比概念图简化：缺少丰富树冠、建筑旧化、地面材质分层与最终UI。地图仍为27×19米；120米区域、加油站、复杂建造尚未实现。下一轮优先改善住宅周边地表、植被轮廓和室内材质，再按区域逐张制作概念图与模块，避免一次生成整座城市。
