# 幸存者模型精修 V1（2026-10-25）

## 头部结构重做（2026-10-26）

球形头部和独立鼻球替换为连续下颌、颧骨、眼窝及鼻梁网格；增加闭合渐细发束，并缩短正前方刘海以露出眉眼。当前6952三角面，沿用既有头骨权重和全部动作。新增 `character-portrait-review.png` 是真实游戏街道内暂停模拟、正交尺寸2.1的低角度检查机位，不修改正式游玩镜头。截图条件均在 `capture-conditions.json`。

正面检查曾发现头皮露缝和刘海挡眼，已修正覆盖及长度。发束仍偏硬，面部仍为简化造型，服装厚度和自然褶皱仍未达标；此次属于结构改进，不宣称完成定妆图品质。完整验证记录为 `work/visual-slice/character-head-checks.log`。

## 2026-10-26 增量

发色改为集中配置的 `survivor_hair`（#24201c、粗糙度0.86），Blender与Godot使用相同映射；发线、后颈及分缝轮廓做不对称调整。去掉独立凸起的脸颊块，加强肘膝处压缩褶皱的轮廓。当前6936三角面，骨架和动作不变。实际正面仍有帽状轮廓和简化脸部，不能视为定妆照质量达标；下一轮应重新设计发束及脸部拓扑，而不是继续堆小配件。此次完整验证记录为 `work/visual-slice/character-v2-checks.log`，截图仍由实际游戏生成。

依据用户的 `art/references/user-character-sheet.png` 定妆方向，保留橄榄外套、棕色帆布背包、深灰裤和实用靴。此次只升级玩家，不改变街道、镜头、碰撞体、武器规则或僵尸外观。

## 实际改动

- 收窄下颌并调整下巴与面颊，保留此前用户确认的整体头部尺寸。
- 去除头发的均匀条纹，额前发线直接接在头皮网格上。
- 折叠衣领、内搭、胸袋、口袋翻盖、袖口；肘与膝处有克制的压缩褶皱。
- 缩短原有整块手掌，增加四指和拇指；仍绑定已有手骨，没有新增手指动画。
- 背包增加下袋、侧袋、扣带、扣件、包边与提手；裤侧袋及靴带补足轮廓层次。
- 细节使用已有共享 PBR 材质，保留 16 骨架和 stand/move/run/attack/hurt/death 六个动作。

生成入口仍为 `tools/generate_assets.py`，新增 `tools/refine_survivor.py` 为局部造型模块。`--only player` 现在同步更新已有清单中的该资产记录，保留其他条目。可编辑源为 `art/source/player.blend`，运行资产为 `godot/assets/player.glb`。最终清单记录 7024 三角面、3 个网格对象（身体与两种装备），低于玩家 8000 三角面预算。

## 重复执行

```powershell
& D:\Blender\blender.exe --background --factory-startup --python tools/generate_assets.py -- --only player
python tools/run_visual_slice.py import
python tools/run_visual_slice.py capture
python tools/run_checks.py --godot D:\GameDev\Godot_v4.7.2-stable_win64.exe --blender D:\Blender\blender.exe --visual
```

截图为实际 Godot 游戏场景，1920×1080、10:00、正交尺寸4。`character-before-refinement.png` 是修改前背面；`character-closeup.png` 是相同构图的新版背面；`character-front-refined.png` 在暂停模拟时仅将人物视觉节点转180度，用于正面造型审查，不冒充玩家操作。其他连续探索截图通过实际输入产生。没有使用生成图片替代实机。

## 质量判断与限制

背包、口袋、手部已比原版更易辨认；并非定妆图的最终工艺水平。面部仍为简化造型，发型仍需进一步设计，外套大面积布褶与磨损不足，靴子仍偏棱角。此次没有面部表情、手指骨骼、布料模拟或新的贴图绘制，不宣称已达到最终产品级人物品质。

源文件、GLB、骨架、共享材质和生成器可复用到其他 Godot 项目；其他引擎需重新接线材质与动画控制。运行时生存与战斗逻辑不嵌入模型。新增几何为项目原创程序化制作，没有引入外部素材。

验证日志：`work/visual-slice/character-generate.log`、`character-full-checks.log`、`capture.log`；性能条件与结果保存在同目录 `gameplay-performance.json` 与 `performance.json`。测试通过只证明导出和玩法契约，不代替上述视觉质量判断。

完整回归已返回 `ALL_CHECKS_OK`，生产存档/导出指纹不变。最后只调整头发网格的贴合位置，随后再次完成资源重跑核对、实机连续流程和 `CHARACTER_MOTION_OK`；分别保留 `character-replay.log`、`capture.log` 与 `character-final-motion.log`。GTX 1650 / Compatibility / 1080p / VSync开启，住宅外静止且模拟运行的240帧短样本约60 FPS；这不是长期战斗最低帧率保证。
