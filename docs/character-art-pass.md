# 人物美术与奔跑动作增量

日期：2026-10-22。沿用现有 Blender 后台 Python 管线与16骨骼，不需要 Blender MCP。

## 本轮改动

- 玩家和僵尸扩大头部、增加耳朵、嘴部和发束，肩胸轮廓更宽；未改变身高比例对应的碰撞规则。
- 玩家补充衣领、拉链、背包肩带、背包盖片和腰扣；僵尸增加非对称破袖、膝部破损及脸部伤痕。
- 玩家1492三角面、两个蒙皮网格；僵尸1152三角面、一个蒙皮网格，仍低于已有2000面上限。沿用共享调色板，无新增贴图。
- 玩家新增独立 run 循环：20帧周期、较大步幅、屈膝、身体前倾及起伏。原 move 为32帧。实际平面速度超过 walk_speed+0.5 时使用 run；攻击、受伤、死亡仍优先。
- 僵尸保持原五个动作、速度和感知规则。碰撞、近战判定、库存与存档格式不改。

## 文件与复现

生成器 tools/generate_assets.py；原始工程 art/source/player.blend、zombie.blend；游戏资产 godot/assets/player.glb、zombie.glb。完整生成同步更新 manifest.json。

```powershell
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_assets.py
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --editor --import --quit
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path godot
```

WASD行走，Shift奔跑，空格攻击；室内镜头、灯光、搜刮和休息仍用原操作。生成器会覆盖其管理的源工程，手工修改前应另存副本。

## 已验证

完整 tools/run_checks.py --godot <路径> --blender <路径> --visual 得到 ALL_CHECKS_OK。12个GLB与清单后台重生成字节一致；旧版保护、骨架蒙皮/动作、规则、AI、时间、休息、搜刮、脱离追击、过夜及住宅八方向试玩均通过。正式存档与导出文件指纹保持不变。

新增 test_character_motion.gd 用实际方向键和奔跑输入验证行走→奔跑→站立→攻击，断言实际速度、体力、声音以及腿骨连续变化，输出 CHARACTER_MOTION_OK。资产测试核对 run 导出与循环标志。

work/c3-poses.png 为实际 Godot 渲染的11个动作采样实例，不代替可播放动画；work/house-interior.png 为实际住宅试玩中的新人物。渲染使用 Compatibility/GTX1650，未进行稳定帧率基准。

## 仍待改进

当前仍是分段刚性蒙皮，尚无脚部IK、表情、手指、混合过渡和卧床姿态。奔跑无根位移，移动距离由物理规则驱动，未解决精确脚步落地与滑步。人物只完成一轮轮廓和细节改善，未宣称达到参考图品质。下一轮优先住宅尺度和更清晰的房间动线，再扩展场景密度。
