# 轻量单空间场景 V1：田径场 / 市集 / 别墅

按“不要太复杂、一个空间就够”的要求，新增三个独立场景。推荐这三个是因为它们分别覆盖三种不同的关卡构成：

1. **田径场**：开阔、低遮挡，适合验证道路、围栏、跑道、看台和远距离尺度；
2. **市集**：中近距离、高密度摊位，适合验证货架、雨棚、杂物和行走通道；
3. **别墅**：建筑立面、可进入的室内、庭院、泳池和围墙，适合验证建筑、室内外过渡与景观边界。

三个场景都各自只有一个可活动空间，没有任务链，也没有接入现有街区或存档。现在另有 [District 07](district-07-v1.md) 把三者放进同一个独立街区。

## 启动

```powershell
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path 'D:\GitHub\dead-days\godot' res://locations/track_field.tscn
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path 'D:\GitHub\dead-days\godot' res://locations/market_square.tscn
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path 'D:\GitHub\dead-days\godot' res://locations/villa_courtyard.tscn
```

操作：`WASD` 移动，`Shift` 奔跑，`Q/E` 环绕，滚轮缩放，`R` 回到入口，`Esc` 退出。

## 场景内容

### 田径场

- 约 56 × 46 m 的学校/社区田径场；
- 6 米左右宽、带圆角的 6 道红色跑道，白色分道线、内外边线、起跑线；
- 中间草坪足球场：边线、中线、中圈、禁区线、两组球门；
- 五排混凝土看台与木凳、中央通道、侧边栏杆；
- 外围铁丝网、南侧入口、入口标牌、四角灯杆；
- 看台后方记分牌、树木和场外草地；
- 场景统计：13,996 三角面，14 个简化碰撞体。

### 市集

- 约 32 × 26 m 的街边小市集；
- 6 个独立摊位：立柱、双色条纹雨棚、木柜台、货箱、果蔬、价签；
- 后方三间开放前脸店铺：可走入的室内、柜台、货架、货箱、遮阳篷和招牌；
- 中央沥青通道、木质串灯杆、下垂灯串与灯泡；
- 花箱、长椅、散放木箱、两棵树；
- 低矮边界墙和前后入口；
- 场景统计：32,162 三角面，35 个简化碰撞体。它是三个场景中道具密度最高的一个，但仍是单空间。

### 别墅

- 约 34 × 26 m 的现代别墅庭院与可进入双层住宅；
- 两层主宅体量加侧向单层车库，平屋顶、混凝土檐口、入口雨棚、二层阳台；
- 大面积深色玻璃、竖向木格栅、开放门洞、车库卷帘门、门牌；
- 一层包含客厅沙发、地毯、茶几、电视墙、书架、落地灯、餐桌椅、厨房柜体、水槽、灶台、冰箱、吧台、双人床、床头柜、衣柜和绿植；
- 二层为开放 Loft：楼梯、玻璃栏板、双人床、床头板、衣柜、书桌、书架、休闲椅、地毯、灯具和绿植；
- 前院泳池、池边铺装、两张躺椅、遮阳伞、户外桌椅；
- 车行道、入户小径、草坪、树、绿篱、花箱；
- 1.55 m 围墙、车辆入口和步行入口；
- 进入室内自动隐藏屋顶、前墙和东墙；一层隐藏上层组；楼梯有连续斜面碰撞，可直接走上去；
- 场景统计：12,888 三角面、5 个分组网格（主体/屋顶/前墙/东墙/上层）、47 个简化碰撞体。

## 文件

| 内容 | 文件 |
| --- | --- |
| 生成器 | `tools/generate_simple_locations.py` |
| 场景数据 | `godot/data/simple_locations.json`、`godot/data/district_layout.json` |
| 合并街区场景 | `godot/locations/district_07.tscn` |
| 区内道路/入口设施 | `godot/assets/district_commons.glb` |
| 共享查看器 | `godot/scripts/location_viewer.gd` |
| 田径场场景 | `godot/locations/track_field.tscn` |
| 市集场景 | `godot/locations/market_square.tscn` |
| 别墅场景 | `godot/locations/villa_courtyard.tscn` |
| 运行 GLB | `godot/assets/track_field.glb`、`market_square.glb`、`villa_courtyard.glb` |
| 可编辑源 | `art/source/track_field.blend`、`market_square.blend`、`villa_courtyard.blend` |
| 结构测试 | `godot/tests/test_simple_locations.gd` |
| 实机截图脚本 | `godot/tests/preview_simple_locations.gd` |
| 实机截图 | `work/locations/01-track-field.png` 等 3 张 |

## 设计与技术边界

- 复用现有共享 PBR 材质库、原始玩家模型、同名 16 骨骼和 `character_visual.gd`；
- 玩家只负责行走/奔跑展示，不接入战斗、僵尸、搜刮、库存、门、睡眠或存档；
- 碰撞由 `simple_locations.json` 中的 AABB 显式建立；别墅的 GLB 拆成主体、屋顶、前墙、东墙和上层五个网格，以支持进入室内后的分层剖切；
- 没有改动 `game.gd`、`rules.json`、主场景、现有街区或存档；
- **上一轮的玩家/丧尸重建已经撤销**，`player.glb` 与 `zombie.glb` 已恢复原版；
- 三个场景均为独立入口，不替换 `visual_slice_v1.tscn`。

## 实际验证

- `SIMPLE_LOCATIONS_OK`：三份布局、三份 GLB、三个场景、相机、玩家落地、碰撞体数量与重置位置全部通过；
- 实机渲染：田径场、市集、别墅各一张 1920 × 1080 截图；
- 现有人物资源已恢复并通过 `ASSET_IMPORT_OK`。

## 复现

```powershell
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_simple_locations.py
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --editor --import --quit
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --script res://tests/test_simple_locations.gd
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path godot --resolution 1920x1080 --script res://tests/preview_simple_locations.gd
```

## 已知限制

- 它们是展示型单空间，不是完整的玩法地图；没有导航网格、敌人、物资、声音和存档接线。
- 市集店铺是开放式店面，没有完整室内屋顶或可关的门；别墅主宅可以进入，二层通过楼梯的连续斜面碰撞走上去。
- 模型是低多边形程序化几何，没有 LOD、遮挡剔除和帧率验收。
- 截图保存在 `work/locations/`；按项目惯例 `work/` 被 `.gitignore` 忽略，提交时需 `git add -f`。
