# 交接文档

写给下一个接手这个项目的人（也可能是我自己隔几个月回来）。
目标：**十五分钟内跑起来，知道东西都在哪，知道哪里是坑。**
细节文档不在这里重复，正文会指过去。

最后更新：2026-11-02。存档 schema **8**，世界数据 revision **5**，检查标记 **45** 个。

---

## 1. 五分钟跑起来

```bash
# 1) 有改动资源后，先让 Godot 建导入缓存（不开窗口）
D:/GameDev/Godot_v4.7.2-stable_win64.exe --headless --path godot --import --quit

# 2) 开游戏（主场景 res://locations/integrated_world.tscn，整张地图）
D:/GameDev/Godot_v4.7.2-stable_win64.exe --path godot
```

最省事是双击根目录 `play.bat`（里面只写了一行 Godot 路径，换机器改那一行）。

**必须 Godot 4.7.x**。4.6 及以前不能直接跑（导入参数与 `gltf/embedded_image_*` 行为不同）。

跑全套检查（约 5–8 分钟，最后要看到 `ALL_CHECKS_OK`）：

```bash
# 注意两点：--godot 必须传 Windows 路径；python 必须是用装了 pygame 的那个
C:/Users/11/.workbuddy/binaries/python/envs/default/Scripts/python.exe \
  tools/run_checks.py --godot "D:/GameDev/Godot_v4.7.2-stable_win64.exe"
```

- 传 `D:/...` 而不是 `/d/...`：Git Bash 风格路径 Windows 版 Python 的 `subprocess` 找不到文件。
- 必须用带 `pygame` 的 Python：`run_checks.py` 第一条检查会 import 旧版 `main.py` 跑自检哨兵。
- 加 `--visual` 会开真窗口抓截图到 `work/`；加 `--blender` 会重放资产管线验字节一致（需要 Blender）。

存档在 `%APPDATA%\Godot\app_userdata\Dead Days\saves\`，三个槽位各自独立。

---

## 2. 现在到哪了

一句话：**一个能玩的连片小城，生存与威胁已经立起来，但"长期活下去"的循环还没做。**

| 层 | 状态 | 说明 |
| --- | --- | --- |
| 世界 | ✅ 完成 | 街道 + 四栋住宅、杂货店、诊所、市集大厅、废弃工厂、两层别墅，整图一次加载；Tab 地图与备注标记 |
| 移动与镜头 | ✅ 完成 | 斜俯视正交，Q/V 旋转、滚轮缩放；进屋剖顶并收起近侧高墙 |
| 搜刮与搬运 | ✅ 完成 | 有限库存容器、负重、逐件存取（B）、逐件落地（I）、落地物随存档恢复 |
| 生存基础 | ⚠️ 一半 | 饥饿 / 口渴 / 体力 / 生命；**缺疲劳、体温、卫生** |
| 伤势 | ✅ V1 | 抓伤 / 撕裂伤 / 咬伤，独立流血、独立感染判定；消毒→缝合→包扎；不处理会流血致死 |
| 精神 | ❌ 未开始 | 无聊 / 不快 / 压力 / 孤独 / 抑郁，一条都没有 |
| 僵尸 | ✅ 可用 | 视野 + 听力 + 记忆 + A* 绕障 + 隔层衰减；三楼以下能走楼梯追击；三种外观 |
| 战斗 | ⚠️ 一半 | 近战、手枪 6 发弹匣与装填/卸弹、枪声引尸；**缺潜行、爆头、部位伤害** |
| 门与据点 | ✅ V1 | 门耐久、被撞破、修门、加固；据点可设在任意可居住空间；四条配方 |
| 工事 | ✅ V1 | 别墅院子铁门、前门门洞、泳池市政供水，材料从工厂/市集搬回自装 |
| 声音 | ✅ V1 | 距离衰减（3 m 满音量，每翻倍 −7 dB，42 m 外不调度）、隔层 −12 dB；僵尸首次看见/挨打/倒下各有声音 |
| 存档 | ✅ 可靠 | 三槽 + 每槽 8 份轮转 + 手动备份/导出；schema 1→8 全部在内存迁移 |
| 小目标 | ✅ V1 | 四个从存档算出来的目标，不存独立任务字段 |
| 永久死亡 | ⚠️ 半 | 有死亡与 `died` 事件，但死后直接结束，**没有传承机制** |
| 建造 / 停水停电 / 农耕 / 保存 / 畜牧 | ❌ 未开始 | 见 §6 |
| 网页版 | ⚠️ 可跑 | `python tools/build_web_fixed.py` 出包到 `web/`；**产物是旧的，改代码必须重跑** |
| Windows 独立 exe | ❌ 推迟 | 按用户要求等玩法内容完成后再做 |

---

## 3. 代码地图

### 41 个 GDScript（7879 行），按职责

| 文件 | 行 | 干什么 | 什么时候会碰它 |
| --- | --- | --- | --- |
| `scripts/game.gd` | 1404 | 小型场景生成、输入、UI、相机、交互距离校验 | 加按键、加 HUD 行、加交互物 |
| `scripts/integrated_world.gd` | 913 | 整图装配：地板、连接道路、模块挂载、世界边界 | 改地图布局 |
| `scripts/survival.gd` | 839 | **纯状态模型**：库存事务、物品效果、结构化事件、存档校验、Markdown 导出 | 加物品、加状态、改存档结构 |
| `scripts/wounds.gd` | 391 | **纯函数伤势模型**：命中判定、流血、感染、急救顺序、HUD 摘要 | 改伤势数值与规则 |
| `scripts/zombie.gd` | 381 | 物理感知与有限记忆 AI、攻击、发声 | 改 AI 行为 |
| `scripts/navigation.gd` | 256 | 按层分网格的 A*，门开关后重算 | 改寻路 |
| `scripts/crafting.gd` | 200 | 配方、材料先扣后补、耗时走游戏时钟 | 加配方 |
| `scripts/game_audio.gd` | 172 | 播放器池、按真实移动距离触发脚步 | 加音效 |
| `scripts/audio_space.gd` | — | **纯数学**空间衰减 + 楼层隔离，无引擎 3D 衰减 | 调听感 |
| `scripts/save_slots.gd` / `save_store.gd` | 159 / 128 | 三槽、轮转、原子写入、快照回退 | 改存档路径与保留策略 |
| `scripts/survival_time.gd` | — | 游戏分钟、生理推进、每日总结 | 改时间与消耗 |
| `scripts/rest.gd` | — | 短休 / 睡到黎明的资格与计划 | 改休息 |
| `scripts/goals.gd` | 134 | 四个小目标的判定 | 加目标 |
| `scripts/material_library_v1.gd` | 44 | 共享 PBR 材质库，按 ID 缓存 | 加材质 |
| `scripts/*_slice.gd`、`*_scene.gd`、`*_viewer.gd` | — | 各地点/建筑的室内装配与预览 | 改室内 |

**架构铁律**：`survival.gd` / `wounds.gd` / `audio_space.gd` 是纯状态或纯函数，不碰节点。节点层只读模型、写事件。
加玩法时先想"这条规则能不能写成纯函数 + 一条断言"，能就别塞进 `game.gd`。

### 15 份数据（改数值不用改代码）

`rules.json`（物品/容量/建筑/僵尸/伤势表）、`connected_world.json`（各容器库存）、`crafting.json`（配方）、
`material_library_v1.json`（材质配方）、`street_art.json`、`district_layout.json`、`house_layout.json`、
`clinic_layout.json`、`shop_layout.json`、`factory_layout.json`、`simple_locations.json`、`interior_lights.json`、
`audio.json`、`goals.json`、`zombie_appearances.json`。

### 资源

26 个 GLB（共 119 MB，贴图内嵌）+ `assets/materials_v1/` 的程序化表面贴图。
主场景 8 个：`integrated_world`（默认）、`district_07`、`market_square`、`factory_grounds`、
`track_field`、`villa_courtyard`、`main`、`visual_slice_v1`。

---

## 4. 存档：schema 8

当前字段：天数/分钟、位置、五维属性（现有部分）、库存、门状态、各容器剩余、首次进入集合、
完整事件流、`combat`、`zombies`、`noises`、`noise_sequence`、`seen_horde`、`calendar`、`rest`、
`goals`、**`wounds[]` + `hit_seq`**。

**加字段的正确姿势**（照 G1 做过一遍）：

1. 在模块里写 `add_state(model)`，把新字段补上并把 `schema` 升到 N+1；
2. 在 `survival.gd.restore()` 里用"字段存在性"判断迁移，**不要**只判断 schema 数字；
3. `valid()` 里对新字段做严格校验（类型、范围、数量守恒），并在测试里伪造 5 种非法存档证明会被拒；
4. 老档迁移后写一条 `migrated` 事件；
5. 把**所有**断言 schema 数字的旧测试升到新值——这是最容易漏的一步。

**原则**：宁可拒读，也不要读出一个"看起来对但能刷物资"的档。删字段不能变成重新补货。

---

## 5. 检查套件

`tools/run_checks.py` 串 45 个带标记的检查，每个检查是 `godot/tests/test_*.gd`，
最后一句 `print("XXX_OK")`，脚本里用 `run([...], 'XXX_OK')` 断言它出现过。

加检查的三步：

```python
# run_checks.py
run([args.godot, '--headless', '--path', 'godot', '--script', 'res://tests/test_foo.gd'], 'FOO_OK')
```
```gdscript
# godot/tests/test_foo.gd
extends SceneTree
func _init() -> void:
    # 断言用 if not ... : print(FAIL) ; quit(1)
    print("FOO_OK")
    quit(0)
```

约定：
- **纯模型/纯数学** 用 `--headless`；要真物理帧的端到端用窗口模式（`command` 那组）。
- 测试存档一律写 `user://tests/<唯一名>/`，绝不碰正式 `saves/`。
- `run_checks.py` 首尾会哈希玩家存档与导出目录，跑完发现被改动会直接 assert 失败。
- 断言要**故意能红**：G1 里"不处理就会死"那条一开始自己绿了（满血 + 一处咬伤会自愈），
  先把血压到 30 才真测到致死。

---

## 6. 还没做（按用户规格的优先级）

完整对照表在 [`survival-spec-v1.md`](survival-spec-v1.md) §七，这里只排顺序：

1. **五维需求 + 精神五维**（下一块）
   体温、卫生；无聊/不快/压力/孤独/抑郁。读书、听广播、吃东西要有实际作用。
   现状：身体只有饥饿和口渴两条会掉血的线，"活着"的分量还不够。
2. **职业 + 特质 + 数十技能**
   开局选消防员/警察/工程师，正负特质；技能靠读书 + 实践，前期快后期极慢。
   这一步做完，`生存日志` 才有东西可传承。
3. **从零建造 + 停水停电**
   现在只能"借用房子"：修门、加固、装三处工事。要能建围墙、自定义墙/地板/楼梯、多层安全屋。
   停水停电是逼你找发电机、接雨水的开关。
4. **农耕 / 钓鱼 / 狩猎 / 畜牧 + 食物保存**
   `long-survival-v1.md` 已经量出诚实寿命：**水 16.2 天、食物 23.1 天，水是瓶颈**。
   要"活过一个月"，必须让食物与水可持续。烘干 / 烟熏 / 地窖。
5. **生存日志传承**（永久死亡的最后一环）
   皮革条 + 线 + 针做空白日志 → 记录技能/特质/配方 → 死后找回、新角色读取。
   四类日志（磨损/血迹/诅咒/圣诞）、遗忘槽、限领、多人权限、完整沙盒选项。
6. 多人联机与沙盒选项面板 —— 取决于是否真的做联机。

**推迟项（用户已明确）**：Windows 独立 exe 导出、GitHub Pages 正式托管、版本号。

---

## 7. 已知的坑（都是真踩过的）

### 7.1 路面/墙面变成洋红紫格子 —— 网页压缩把导入缓存写坏了

**现象**：街道和建筑表面显示洋红棋盘格，其余一切正常。桌面版和网页版都会中招。

**根因**（已用实验闭环确认，不是猜的）：

1. GLB 的贴图是内嵌的（`images[].bufferView`，没有外部 uri）。为了让导入不吐出几百个散落 PNG，
   所有 `.glb.import` 的 `gltf/embedded_image_handling` 是 **2**，贴图存成 `PortableCompressedTexture2D`，
   直接塞在 `.godot/imported/*.scn` 里（一个正常的 `street_ground.scn` 约 **1.8 MB**）；
2. `godot/compress_web_assets.gd` 为了压 pck，把每个 `.scn` 读出来再用
   `ResourceSaver.save(resource, path, FLAG_COMPRESS)` **原地覆盖**；
3. 这一重存会**丢掉 `PortableCompressedTexture2D` 的像素数据**，`.scn` 从 1.8 MB 缩成 **79 KB**；
4. 但旁边的 `.md5` 时间戳没变，Godot 认为缓存是最新的，**永远不再重建**——于是冷启动也是洋红。

第 3 步的体积变化是可复现的判据：`street_ground.scn` = 79 KB 就是坏的，1.8 MB 就是好的。
网页版那 427 条 `Parameter "texture" is null` 噪声是同一件事的另一面。

**修法**：

- `tools/build_web_fixed.py` 在 `--export-release` **之后**追加一步：删掉所有 `.scn` 及其同名 `.md5`，
  再跑一次 `--import` 从 GLB 重建。网页包已经拿到了压缩件，桌面则拿回完好的贴图。
- `tools/configure_visual_imports.py` **不要**加 `gltf/embedded_image_keep_impressed_compression`
  ——Godot 4.7.2 的二进制里根本没有这个参数名，写了会被静默忽略、并在重写 `.import` 时丢掉（踩过这个坑）。
- **手动救**：删 `.scn` 本身，光删 `.md5` 不够。

```bash
rm godot/.godot/imported/*.scn
D:/GameDev/Godot_v4.7.2-stable_win64.exe --headless --path godot --import --quit
```

**验证**：`godot/tests/probe_materials.gd`（标记 `MATERIAL_TEXTURES_OK`）遍历 12 个主资产的每个表面，
断言"有 albedo 贴图的材质尺寸必须非零"，并打印各资产的 `meshes / surfaces / textured / issues`，
出问题能直接定位到哪个资产。它在 `run_checks.py` 里排在 `VISUAL_INTEGRATION_OK` 之后。

三种导入模式对照，别走回头路：

| `embedded_image_handling` | 结果 |
| --- | --- |
| 0（Extract） | 抽出散落 PNG；PNG 被清掉后引用断开，贴图变 `null` |
| 1（Embed） | 正常，但会在 `godot/assets/` 吐出几百个 PNG + `.import` |
| **2（PortableCompressed）** | ✅ 正常且不吐文件（当前方案），**前提是别让网页压缩原地覆盖它** |

### 7.2 网页版 427 条 `Parameter "texture" is null`

和 §7.1 同源：网页用的是被 `FLAG_COMPRESS` 重存过的 `.scn`，内嵌纹理已经丢了，
所以运行时逐帧刷这条警告。画面本身因为网页版用的是压缩后的场景，实测与桌面版差异极小
（518400 像素中 328 个不同，均值差 0.044），玩法与存档正常。
**去掉场景压缩会让 pck 从 20 MB 涨到约 100 MB**，所以网页侧保留压缩、桌面侧靠重建规避。

### 7.3 `web/` 是构建产物

`.gitignore` 排除了。改完玩法必须重跑 `python tools/build_web_fixed.py`，否则网页版还是旧内容。

### 7.4 本机 `git push` 不通，要走 GitHub API

`git push` / `git fetch` 连 github.com 常年 reset 或 502（代理端口会变），但 `gh api` 是通的。
单文件改动用 Contents API；多 commit 或带二进制用 Git Data API。
现成脚本：`work/api_push_tree.py`（支持 `--dry-run`）。细节见技能 `git-push-via-github-api`。

推完记得 **PATCH 目标分支**，别只推到自己建的分支上（踩过：`API_PUSH_OK` 但 `main` 没动）。

### 7.5 本地仓库没有 `main` 分支

本地只有 `feature/dead-days-visual-slice-v1` 和 `salvage-20261027-rebuild`。
远端 `main` 与本地 HEAD **内容一致**（比对 `HEAD^{tree}` == 远端 commit 的 tree 已验证），
只是历史没有共同祖先（`.git` 曾丢过对象库后重建）。所以：
**不要试图开 PR 或普通合并**，要么按 tree 比对后 API 推送，要么 force 改 ref。

### 7.6 GUI 窗口会被执行环境在 60–100 秒后杀掉

不是游戏 bug。日志停在 `Completed load for integrated_world.tscn` 且无错误，就是被外部清理了。
判断游戏是否真的能跑，用 `--headless --quit-after 200` 看有没有 ERROR。

### 7.7 仓库根有 10 个乱码目录

`ᰀ끗`、`∀끗` 之类，各含一个 `.thumbnails`，2026-10-26 生成，已 gitignore。
**没有删**（等用户点头）。看着碍眼但无害，删之前先确认不是某个工具正在用的缓存。

### 7.8 shell 环境偶尔整个坏掉

`shell-runtime-bash-env.sh: dirname: command not found`，随后 `grep/ls/head` 全没了。
修法：在命令开头手动补 PATH：

```bash
export PATH="/c/Users/11/.workbuddy/binaries/PortableGit/versions/1.2.0/usr/bin:/c/Users/11/.workbuddy/binaries/PortableGit/versions/1.2.0/mingw64/bin:$PATH"
```

---

## 8. 下一个接手者先做这四件事

1. `--headless --import --quit`，再跑全套检查，确认 `ALL_CHECKS_OK`；
2. 双击 `play.bat` 走一遍新手上手顺序（进屋拿木棍 → 诊所拿绷带酒精 → 市集），
   顺手确认路面是**沥青灰**而不是洋红；
3. 读 [`survival-spec-v1.md`](survival-spec-v1.md) §七的对照表，那就是待办清单；
4. 挑"五维需求 + 精神五维"开工，照 G1 的模板来：先写纯函数模块 → 加断言 → 接节点 → 升 schema →
   写 `docs/需求-v1.md` → 更新 `docs/status.md`。

---

## 9. 文档索引

| 想了解 | 看 |
| --- | --- |
| 目标与差距 | [生存基调规格](survival-spec-v1.md) |
| 整条时间线与当前限制 | [状态清单](status.md) |
| 怎么测、踩过什么 | [测试与验证](testing.md) |
| 模块职责与存档约定 | [架构](architecture.md) |
| 伤势规则 | [伤势与流血](wounds-v1.md) |
| 声音空间 | [声音空间](audio-space-v1.md) |
| 十日经济账 | [长时生存](long-survival-v1.md) |
| 存档可靠性 | [存档可靠性](save-slots-v1.md) |
| 网页版 | [网页版导出](web-export-v1.md) |
| 美术标准 | [美术方向](art-direction-v1.md) |
