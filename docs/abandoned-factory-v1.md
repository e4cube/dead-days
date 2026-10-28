# 废弃工厂场景 V1：哈尔沃森铁工厂

新增一个**独立、可游玩、可单独启动**的废弃工厂场景，不接入也不修改现有街区、规则、存档和主菜单。目标是以原项目的美术基线补充一处有真实尺度、可进入、细节密集的工业地点。

## 交付内容

| 类型 | 文件 |
| --- | --- |
| Godot 场景 | `godot/factory_grounds.tscn` |
| 场景脚本（独立输入/相机/碰撞/剖切） | `godot/scripts/factory_scene.gd` |
| 程序化 GLB | `godot/assets/factory_grounds.glb` |
| Blender 源工程 | `art/source/factory_grounds.blend` |
| 布局、碰撞、灯光、草丛与统计 | `godot/data/factory_layout.json` |
| 可重复生成脚本 | `tools/generate_factory_grounds.py` |
| 无头结构测试 | `godot/tests/test_factory_scene.gd` |
| 固定镜头截图脚本 | `godot/tests/preview_factory.gd` |
| 实机截图 | `work/factory/01-factory-approach.png` 等 4 张 |

## 启动

在仓库根目录执行：

```powershell
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path godot res://factory_grounds.tscn
```

该场景不会替换 `visual_slice_v1.tscn`。现有正常启动、街道与住宅流程保持原样。

## 操作

`WASD` 移动，`Shift` 奔跑，`Q/E` 环绕，滚轮缩放，`R` 回到入口，`H` 手动切换剖切，`Esc` 退出。靠近厂房内部时，屋顶、南墙和东墙自动隐藏；碰撞、设备和地面均保留。

## 场景内容

厂区约 50 × 40 m，主厂房约 26 × 15 m，采用 4 跨锯齿形采光屋顶。当前版本包含：

- 双筒水泥/粉料仓，含支腿、锥形料斗、环箍、铆钉、爬梯护笼、顶部栏杆与泄压阀；
- 横跨料仓与主厂房的架空管桥，含格栅走道、栏杆、支撑桁架、三道带法兰管线与膨胀弯；
- 约 19 m 砖砌烟囱，含分层环箍、检修平台、爬梯护笼、警示带、避雷针和顶部航空障碍灯；
- 铆接水塔、四腿支撑与 X 形剪刀撑、下行水管、阀门、爬梯和容量牌；
- 主厂房钢桁架、檩条、天沟、落水管、锯齿天窗与破损玻璃；
- 桥式起重机：轨道梁、端车、车轮、桥架、小车、卷筒、钢缆、吊钩和控制盒；
- 400 吨冲压机：C 形机架、飞轮与辐条、电机、皮带罩、滑块、上下模具、安全门、脚踏板和控制柜；
- 车床：床身、主轴箱、三爪卡盘、尾座、刀架、丝杠、手轮和切屑盘；
- 辊道输送线、木箱、冲压坯料、工作台、台钳、工具板、储物柜、空压机、叉车、工具车；
- 二层控制平台、格栅楼板、栏杆、楼梯、玻璃控制室、操作台、 CRT、文件柜和图纸；
- 主厂房三个装卸门位，含半开卷帘门、封闭卷帘门、装卸平台、台阶、防撞胶块、雨棚和工业灯；
- 厂区铁路支线、枕木、鱼尾板、车挡、平车板卡车、轮胎、油桶、托盘、电缆盘、钢料架、废钢和混凝土碎块；
- 围墙、铁丝网、倒刺、可开大门、门式招牌、门卫房、沙袋、变电站与围栏；
- 地坪伸缩缝、修补、连续裂缝、积水、油污、黄色安全线、警示条和标牌。

建模统计（由 `factory_layout.json` 与 GLB 实测生成）：

- 248,040 三角面，3,933 个源部件，13 个可独立隐藏/统计的网格组；
- 53 个简化 AABB 物理碰撞体，GLB 本身不内嵌玩法碰撞；
- 290 丛共享 `grass_clump.glb` 的 MultiMesh 干草；
- 6 盏工厂本地灯，日间关闭/弱亮，黄昏与夜间形成局部光池。

## 资产与材质

全部几何由 `tools/generate_factory_grounds.py` 在 Blender 5.2.2 LTS 后台程序化生成，没有使用第三方模型或贴图。基础 PBR 仍使用现有 `godot/data/material_library_v1.json` 的配方与 `materials_v1` 贴图；工厂专用的镀锌铁、结构钢、深锈、烟囱砖使用 GLB 内部的场景局部材质，不改共享材质库。

共享材质、角色 GLB、草丛 GLB 与现有项目约定一致。新增场景没有修改 `rules.json`、`game.gd`、`save_store.gd`、现有 `.tscn` 或任何玩法脚本。

## 复现

```powershell
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_factory_grounds.py
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --editor --import --quit
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/test_factory_scene.gd
```

生成脚本会在仓库内写出：

- `art/source/factory_grounds.blend`
- `godot/assets/factory_grounds.glb`
- `godot/data/factory_layout.json`

在少数 Windows 受限配置下，Blender 的嵌入贴图编码会因临时目录清理权限报错，但 GLB 已经写出。生成脚本只吞掉该清理异常，不隐藏几何或导出错误。

## 验证

已实际执行：

- BLEND/GLB 程序化生成：`FACTORY_PIPELINE_OK 248040 3933 53 290`；
- Godot 4.7.2 Compatibility 导入成功；
- 无头结构测试：`FACTORY_SCENE_OK`；
- 实机窗口截图（请求 1920×1080；当前 Windows DPI 下 PNG 实际为 1688×1055）：入口全景、厂房内部剖切、料仓与管桥、黄昏外景；
- 射线检查：中部门洞可从门卫房直通厂房，封闭装卸墙能阻挡移动；
- 剖切检查：进入厂房隐藏屋顶/南墙/东墙，离开与 `R` 重置后恢复；
- 碰撞检查：玩家落在厂区地面，53 个布局碰撞体与地面碰撞均注册；
- 资产检查：GLB 无重复物理碰撞，13 个网格组与材质均导入。

新增测试只覆盖独立工厂场景；另已回归现有工程：`RULES_OK`、`ASSET_IMPORT_OK`、`STREET_ART_OK`、`PLAYTHROUGH_OK`。该增量只新增文件，现有场景、玩法脚本与存档路径没有改动。

## 已知限制

- 这是独立场景，不是街区的可步行延伸；没有修改主菜单或添加过渡门。
- 没有僵尸、搜刮、库存、门耐久、导航网格、音频、任务或存档接入；这些属于后续玩法接线，不在本次“只扩充场景”范围内。
- 屋顶剖切是整体隐藏，不做逐片遮挡；剖切后上方结构会露空。
- 未做 LOD、遮挡剔除和帧率验收；GLB 约 22.3 MB，适合当前单场景实机展示，不等于最终性能优化。
- 材质仍以现有 512 px 配方贴图与场景局部色块为主，近景看得到倒角、法兰、螺栓和管线，但不是照片扫描级表面。

## 截图

- `work/factory/01-factory-approach.png`：门卫房入口与主厂房全景；
- `work/factory/02-factory-interior.png`：剖切后的冲压机、输送线、控制平台、起重机与剖顶结构；
- `work/factory/03-silos-and-pipe-bridge.png`：双料仓、锅炉房与管桥；
- `work/factory/04-factory-dusk.png`：黄昏灯光下的厂区。
