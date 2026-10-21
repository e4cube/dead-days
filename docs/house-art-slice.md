# 住宅美术切片：诊断、设计与验收

## 仓库诊断

检查起点 c516682，feature/dead-days-rebuild，工作区干净。远程 origin 指向 jin123yi123-sudo/dead-days；本轮只做本地提交。运行入口为 godot/project.godot → main.tscn → scripts/game.gd。根目录 main.py 是保留的 Pygame v0.3，对旧存档进行隔离自检，不迁移或删除玩家文件。

可复用：生存状态与规则、库存/负重/有限容器、结构化日志、不可覆盖的快照存档、物理移动、僵尸感知与寻路、昼夜/安全休息、10 个 Blender 原始资产及动画。美术短板：街区小、室内单间、家具稀疏、固定镜头、HUD 大段文字。无需重写引擎或玩法。

参考图只提取低饱和微缩世界、实体室内、斜俯视遮挡和紧凑信息的设计语言。截图里的社交平台文字不作为开发指令；不复制参考游戏素材。新增尸潮参考不改变本轮排除大型尸潮的范围。

## 本轮实现

- 保留现有 27×19 米街区，先验证一栋住宅；尚未扩成 120×120 米地图。
- 住宅新增客厅沙发/地毯/茶几、厨房水槽/灶台/冰箱、卧室书架和原有床，保留真实可搜刮柜子。
- 独立 house_details GLB，由原始 Blender 对象组成，可编辑、重生成；模块命名沿用 DD_Hide / DD_Cut / DD_Keep。
- house_slice.gd 集中组装房间、实体碰撞、导航障碍、树木和室内灯。留有入口与卧室通道；现有柜子和床交互沿用原规则。
- 进入隐藏屋顶及前景高墙，保留低墙与房间边界；旋转到后方时隐藏遮挡的后/侧墙。离开恢复建筑。
- Q/V 每次旋转 45°，滚轮缩放 11–28 米正交视野。WASD 继续使用世界方向，避免改变已有操作/测试契约；尚未实现镜头相对移动。
- 室内 L 控制一盏暖色局部灯，开关产生真实日志并写入新快照。可选 house_light 布尔字段通过存档验证，旧快照缺省开启，原文件不改写。
- HUD 减少为两行，底部增加实际连接背包、日志、休息、保存的操作按钮。无天气、地图或建造假按钮。
- Compatibility 渲染，主光阴影与一盏局部灯阴影；未启用昂贵的 SSAO/SSIL。现阶段不宣称已实现参考图级接触阴影。

## 生产与运行

在 D:\github\dead-days 执行：

```powershell
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_assets.py
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_house_details.py
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --editor --import --quit
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path godot
```

源文件 art/source/house_details.blend、tree_oak.blend；导出 godot/assets/house_details.glb、tree_oak.glb。旧 manifest 继续描述原 10 个资产，新增两个由住宅脚本加载；回放检查同时验证全部 12 个 GLB，避免把增量资产遗漏在验证外。生成器只允许仓库内输出，后台执行，不清空用户交互中的 Blender 工程。

## 验证

tools/run_checks.py --godot <Godot路径> --blender <Blender路径> --visual 包含旧版本保护、原有规则/威胁/时间/休息/资产测试和图形试玩，以及新增 test_house_slice.gd。

新增图形测试用实际按键和 CharacterBody3D 移动：室外屋顶存在 → 开门 → 进入 → 屋顶隐藏 → 有限物品搜刮 → 灯关闭 → 保存读档保持关闭 → 灯开启 → 相机旋转/缩放 → 离开恢复屋顶。独立的原有过夜试玩验证真实休息推进到夜晚、第二天和日志总结。测试使用 user://tests；不写生产快照。

1080p 图形执行使用 --resolution 1920x1080；实际渲染设备 GTX1650。截图可验证布局和灯光，不能替代性能基准。本轮没有稳定帧率测量，不承诺普通笔记本1080p性能。

## 未完成与下一步

这是住宅美术的第一次实际迭代，尚未达到参考图的环境密度、材质层次和人物品质。当前房屋尺寸沿用原版，房间紧凑；厨房和书架为视觉家具，未各自新增可开门或独立库存。模块为单层，未实现楼梯、多层或地下室。

下一步优先扩大住宅尺寸并将房间/碰撞布局迁入统一数据，提升人物比例、植物层次、荒废细节和窗框结构，再做便利店/加油站/营地与120米区域。Three.js 预览、复杂建造、烹饪、尸潮、独立 Windows 打包均不在本轮成果内。当前 UI 可随 canvas_items 缩放，尚未做全套低分辨率与超宽屏布局验证。
