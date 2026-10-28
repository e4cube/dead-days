# 北区 / District 07：三处场景合并街区与可进入别墅

把田径场、市集和别墅放进同一个独立街区，并给别墅补上可以进入的室内、家具和生活杂物。仍不修改现有街区、`game.gd`、`rules.json`、主场景或存档；玩家和丧尸保持原版资产。

## 街区布局

District 07 约 100 × 98 m，四个模块位置如下：

| 模块 | 世界位置 | 内容 |
| --- | --- | --- |
| 田径场 | `(0, 0, -25)` | 北侧，入口朝南 |
| 市集 | `(-23, 0, 8)` | 西南侧，店面朝南 |
| 别墅 | `(24, 0, 8)` | 东南侧，庭院和住宅入口朝南 |
| 街区道路/入口 | `(0, 0, 0)` | 主街、步行街、南门、停车区、路灯、绿化 |

- 东西向主街宽约 7 m，南侧有 8 m 宽入口道路和门牌；
- 市集与别墅之间是一条 10 m 宽的中央步行道，向北直达田径场南门；
- 南门有门架、门柱、路灯和地图牌，道路两侧有树、长椅、垃圾桶、花箱；
- 西南侧有停车区；整个街区由低围墙围合；
- 田径场、市集、别墅保留各自独立的边界、入口、材质和碰撞。

合并后总几何约 70,036 三角面，街区共享层 10,990 三角面。东、西两侧各开了一个车行门洞，接入原街区和工厂联络路。四个模块合计 125 个显式 AABB，加上地面和别墅楼梯斜面共 127 个物理碰撞体。

## 可进入别墅

别墅从原来的封闭外立面改为可进入的双层住宅，主体拆成五个独立网格：

- `DD_Villa_Body`：地面、室内隔墙、一层家具、泳池、庭院；
- `DD_Villa_Roof`：主屋顶和侧屋顶；
- `DD_Villa_FrontWall`：前墙、玻璃、门框、入口雨棚、二层阳台和门牌；
- `DD_Villa_EastWall`：东侧外墙和上层窗；
- `DD_Villa_UpperFloor`：二层楼板、栏杆、隔墙和 Loft 家具。

从街道穿过南侧院门，沿小径到开放前门即可进入。进入室内时自动隐藏屋顶、前墙和东墙；站在一层时上层组也会隐藏，相机聚焦客厅；沿西侧楼梯直接走上二层，上层组显示、相机抬到 Loft；走下来后恢复。楼梯使用连续斜面碰撞，视觉为逐级台阶。碰撞体始终保留，剖切不影响门洞、墙体、家具或行走。

室内物品：

- 客厅：三人沙发、坐垫、地毯、茶几、电视墙、电视、书架、书、落地灯、绿植、边几；
- 餐区：餐桌、四把餐椅、餐桌花瓶；
- 厨房：L 形柜体、台面、四扇柜门、把手、水槽、龙头、灶台、炉头、双门冰箱、吧台和三张吧凳；
- 卧室：双人床、床垫、床头板、两个枕头、被子、两个床头柜、床灯、地毯、三门衣柜；
- 室外：泳池、池边铺装、两张躺椅、遮阳伞、户外桌、庭院树、绿篱和花箱。

别墅局部布局仍然是一个紧凑住宅：一层客厅/厨房/卧室，二层开放 Loft。没有地下室、没有任务链；搜刮点由连片街区场景统一接入。

## 启动

```powershell
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path 'D:\GitHub\dead-days\godot' res://locations/district_07.tscn
```

单人场景仍可分别启动：

```powershell
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path 'D:\GitHub\dead-days\godot' res://locations/track_field.tscn
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path 'D:\GitHub\dead-days\godot' res://locations/market_square.tscn
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path 'D:\GitHub\dead-days\godot' res://locations/villa_courtyard.tscn
```

操作：`WASD` 移动，`Shift` 奔跑，`Q/E` 环绕，滚轮缩放，`R` 回到南门，`Esc` 退出。

## 文件

| 内容 | 文件 |
| --- | --- |
| 合并街区场景 | `godot/locations/district_07.tscn` |
| 街区查看器 | `godot/scripts/district_viewer.gd` |
| 街区布局 | `godot/data/district_layout.json` |
| 三模块局部布局 | `godot/data/simple_locations.json` |
| 街区共享几何 | `godot/assets/district_commons.glb` |
| 别墅几何 | `godot/assets/villa_courtyard.glb` |
| 生成器 | `tools/generate_simple_locations.py` |
| 街区测试 | `godot/tests/test_district_07.gd` |
| 截图脚本 | `godot/tests/preview_district_07.gd` |
| 街区截图 | `work/district/01-district-overview.png` 等 3 张 |

## 验证

- `DISTRICT_07_OK`：四个模块、127 个碰撞体、玩家落地、别墅剖切、上层可见性、物理楼梯、屋顶恢复和 `R` 重置通过；
- 射线检查：街道 → 院门 → 别墅前门可通行，前玻璃会阻挡；
- `SIMPLE_LOCATIONS_OK`：原来的三个独立场景仍可启动，别墅现在为 5 个分组网格；
- `ASSET_IMPORT_OK`、`CHARACTER_MOTION_OK`、`PLAYTHROUGH_OK`：原版人物、动作和原街区继续通过。

## 已知限制

- 这是独立展示街区，不接入原街区地图、导航、AI、搜刮库存、声音或存档。
- 市集后方现在是三间开放前脸店铺，可直接走入，但没有可关的门或完整室内屋顶；别墅二层通过连续斜面楼梯走上去。
- 室内为低多边形程序化家具，没有布料模拟、室内烘焙光照或 LOD。
- 截图在 `work/district/`；按项目惯例 `work/` 被 `.gitignore` 忽略，提交时需 `git add -f`。
