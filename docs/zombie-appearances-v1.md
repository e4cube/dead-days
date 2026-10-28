# 僵尸外观分型 V1

按用户定妆照方向制作普通、工人、警员三种轻量外观；不是复制参考图资产，也不是五种独立行为AI。当前仍是可辨认的功能美术增量，面部、破衣边缘、伤口和帽檐细节尚需精修。

## 已接入游戏

|稳定ID|表现|玩法差异|
|--|--|--|
|civilian|原破损便服，胸前伤口部件独立显隐|无|
|worker|橙褐工作背心、浅色高可见条、椭圆安全帽及帽顶加强条|无；安全帽不额外提供防御|
|police|深色制服、椭圆帽冠与帽檐、腰带装备、简单原创胸牌|无；不自动携枪或掉落弹药|

原三只街区僵尸出生规则依次设置三种外观，数量、出生位置、碰撞、导航、血量、视觉/声音感知、追击、攻击和死亡规则不变。原有手枪逐发消耗、声音吸引与存档规则继续回归。

## 制作与资源

- 复用同一套16骨骼、五套动作和主体蒙皮，`tools/generate_assets.py` 在同一个可编辑源工程中生成服装与头部附件。帽子随头骨、背心及腰带随躯干骨变换。
- 文件仍为 `art/source/zombie.blend` 与 `godot/assets/zombie.glb`，GLB包含主体及三个 `DD_Variant_<id>_Outfit` 节点，未另建三套重复骨架。普通胸前部件与职业服装互斥，避免穿过背心。
- 集中材质库增加 `safety_vest`、`hard_hat`，使用原表面图生成器；警员制服复用 `denim`，浅色条复用 `linen`。没有新增外部图片或专有徽章。材质库现23份定义、54张原始PNG，包含研究图与共享法线，不等于54种独立材质。
- 完整资源清单和源/GLB哈希仍由 `tools/snapshot_visual_slice.py` 更新。
- GLB单独导入其他项目时包含所有服装节点，需要按稳定ID选中一个；直接显示全部节点会叠穿。Godot内由 `zombie_appearance.gd` 统一选择，`CharacterVisual.setup("zombie")` 默认普通外观。

## 存档

新僵尸记录具有 `appearance` 字段，保持与规则、材质配置及节点命名一致。`zombie_appearances.json` 是外观ID与共享材质映射的入口。非法ID拒绝加载。

旧快照可以没有该字段；仅在内存补 `civilian`，保留原位置、血量、死亡和感知状态，不重新抽取外观、不补怪、不覆盖原存档。新存档恢复后，工人仍为工人；倒地也不会换外观或复活。

## 验证

- `test_zombie_appearances.gd`：三种出生外观、服装互斥、所有五套动作切换、死亡工人的存读档、未知ID拒绝、旧档保持死亡状态。
- `test_assets.gd`：所有导出网格保留真实归一化蒙皮，原骨架与动作契约保留。
- `preview_zombie_appearances.gd`：在真实游戏街道中排列三只角色，暂停AI、隐藏玩家和HUD用于外观检查；实际1920×1080截图 `work/visual-slice/zombie-appearances.png`，条件记录 `zombie-capture-conditions.json`。这是受控外观实机展示，不是自然遭遇截图。
- 已加入 `tools/run_checks.py`；完整玩法回归、重复生成字节检查、素材库测试及保护存档指纹继续运行。正式操作流程由独立连续试玩覆盖。

复查命令（PowerShell，仓库根目录）：

```powershell
python tools/generate_surface_maps.py
python tools/run_visual_slice.py generate
python tools/run_visual_slice.py import
python tools/run_checks.py --godot D:\GameDev\Godot_v4.7.2-stable_win64.exe --blender D:\Blender\blender.exe --visual
python tools/run_visual_slice.py capture
```

后续：女性、肥胖等不同体型需要新的轮廓与动作/碰撞验证，不宜只换颜色；职业外观掉落若接入，应是每个个体有限库存。扩充街区前先解除固定建筑ID耦合，持续使用已有建筑和陈设资产，不用扩图掩盖当前质量问题。
