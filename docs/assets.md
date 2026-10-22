# C3：Blender资产生产与Godot导入（2026-10-21）

近景质量首轮后，玩家6318三角面/2网格，柜子1124三角面/11网格；住宅155模块，商店123模块。数量以清单/数据为准，下文为历史批次。曲面模型和导出稳定化说明见 [质量报告](art-quality-pass.md)。

杂货店增量后当前总计21套，新增 `shop_details` 的120模块/1440三角面由 `tools/generate_shop_details.py` 生成，详见 [杂货店切片](shop-art-slice.md)。下文数量为历次增量记录。

诊所增量后当前总计20套，新增 `clinic_details` 的128模块/1536三角面由 `tools/generate_clinic_details.py` 生成，详见 [诊所切片](clinic-art-slice.md)。下文19套为前一轮记录。

2026-10-22：当前共19套源工程/GLB，下表是原始10类资源。另有住宅细节、树木及七类街区资源，见 [街区美术报告](street-art-pass.md)、[第二轮完善](street-art-polish.md) 与 `godot/assets/street_manifest.json`。当前重放检查覆盖全部19份GLB及两份清单；下文10份描述为最初批次历史记录。

## 可重复生产的首批资源

| 资产 | 三角面 | 网格 | 来源/用途 |
| --- | ---: | ---: | --- |
| player | 6318 | 2 | 16骨骼、身体蒙皮+手部木棍、独立奔跑 |
| zombie | 1152 | 1 | 16骨骼、绿色皮肤、非对称破损衣物 |
| building_home | 974 | 75 | 斜屋顶、山墙、烟囱、住宅 |
| building_clinic | 656 | 44 | 平屋顶、几何十字标志、诊所 |
| building_shop | 704 | 48 | 条纹雨棚、杂货店 |
| door | 112 | 4 | 地面左铰链原点，1.7m宽、2m高 |
| bed | 176 | 4 | 1.1×1.8m床框/床垫/枕头/床头 |
| cabinet | 1124 | 11 | 1.2×0.7m板件柜体、凹进门板和把手 |
| table | 220 | 5 | 1×1m桌面，顶高0.765m |
| loot_crate | 36 | 1 | 1.2×0.7×1m搜刮箱，金属束带 |

以上均为本项目的程序化原创几何；没有复制参考作品的素材。清单由脚本实测生成，位于 `godot/assets/manifest.json`，表中三角面为每个独立资产文件的网格总数，并非整帧渲染统计。角色刚性分段蒙皮、倒角低多边形、平面着色；没有软组织或布料物理、面部表情、IK或贴图。

每项都有 `art/source/<id>.blend` 和 `godot/assets/<id>.glb`。Godot只导入显式GLB；.blend留在工程外，不依赖Godot编辑器的Blender路径设置。游戏实际使用全部10个资产种类，截图不是资源交付的替代品。

## 生成与复验

在仓库根目录执行：

```powershell
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_assets.py
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --editor --import --quit
python tools/check_asset_pipeline.py --blender 'D:\Blender\blender.exe'
```

实测Blender5.2.2 LTS。脚本要求后台执行，每个资产重置空场景；会重建指定的生成源工程与GLB，手工编辑前请另存副本。不会修改玩家存档。脚本输出根目录只能位于仓库内。

局部预览可用：

```powershell
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_assets.py -- --only player,zombie --output-root work/asset-preview
```

局部生成不重写总清单，提交前必须运行完整生成。`check_asset_pipeline.py`在忽略的 `work/asset-replay/`重新生成全部资源，核对10个GLB与清单SHA256/字节，并确认源工程存在；不覆盖正式资产。当前同版本Blender环境重放通过。不同Blender/导出器版本不保证字节相同，升级需重新验证。

生成器使用固定几何、调色板、动作帧，不依赖外部图片或下载模型。调色板按sRGB转线性后写材质，粗糙度0.93。未使用贴图，因此关闭UV导出，避免无意义UV浮点噪声并缩减资源。

## 坐标、比例和命名

- 1单位=1米，Blender Z向上、角色朝-Y；GLB/Godot Y向上、角色朝+Z。
- 角色脚底为原点，总高约1.8m。运行时胶囊仍由actor数据定义（半径0.28m、高1.7m、中心0.9m），视觉脚底补偿胶囊的0.05m偏移。
- 建筑前门中心在原点，住宅后墙Godot z=-7、诊所/商店z=-5，宽5.7m，墙高2.6m；Blender与Godot读取同一个建筑depth字段。
- 家具为地面中心原点；门为左侧地面铰链原点。门网格沿+X展开，运行时朝街道旋转90度。
- `DD_`前缀统一命名。`DD_Hide_`网格用于完整屋顶/立面，`DD_Cut_`用于低剖面墙，`DD_Keep_`始终保留。

进屋后仅隐藏当前建筑的屋顶、前/东完整墙和对应装饰，显示低剖面；其他建筑保留完整外观。隐藏属于绘制变化，完整墙体碰撞和AI视线继续存在。没有多人视角、楼层或通用相机遮挡解决器。

## 骨架与动作契约

两类角色共用16骨骼命名：root、pelvis、spine、head，加左右upper_arm/forearm/hand/thigh/shin/foot。身体顶点真实赋权并绑定Armature，木棍独立蒙皮到hand_R；没有用方块Node旋转冒充骨骼资源。

每个GLB包含 `stand`、`move`、`attack`、`hurt`、`death`，全部为姿态动作、无导航根运动。站立/移动循环，其他不循环；死亡采样末帧重建倒地姿态。玩家瞬时近战的动画从击出姿势开始，僵尸动作带前摇；具体命中与伤害仍由玩法规则决定，不交给动画事件重复触发。

2026-10-22人物增量：玩家另含循环 `run`，加大步幅、屈膝、身体前倾和上下起伏，周期20帧，行走仍为32帧。根据物理速度超过 walk_speed+0.5 切换，不按 Shift 键直接播放，避免被墙挡住仍表现为奔跑。攻击、受伤、死亡优先于移动。僵尸不新增奔跑规则或动作。

头部横向扩大至0.46m，增加耳朵、发束、嘴部；玩家增加领口、拉链、背包肩带/盖片和腰扣；僵尸增加破袖、膝部破损和脸部伤痕。保持原骨架关节、胶囊与武器绑定，未改变命中距离或建筑尺度。当前仍为分段刚性蒙皮，没有布料、手指、表情或动画混合。

`character_visual.gd`用AnimationPlayer手动采样模拟时间，休息加速与菜单暂停保持同步。优先级为死亡、受伤、攻击、移动、站立；每次实际攻击重新触发动作，木棍只在真实装备时显示。存档继续保存血量/装备/冷却/前摇，不保存渲染节点或骨骼资源；动画相位在载入时近似重建，尸体直接恢复最终姿态。

当前是硬切换的基础动作，没有行走/奔跑独立循环、连续混合、复杂打击重心、卧床动画或手指动作；休息仍站在床边，属于后续表现完善项。

## 碰撞和存档安全

GLB不包含自动生成碰撞，避免重复阻挡。墙、床、柜、桌和门的简化碰撞由Godot数据/生成器独立建立。开门后既转动可见门板，也启用对应的门板碰撞及导航障碍；关闭时使用门洞碰撞，旧的空门洞穿行规则保持成立。

新增桌子也有碰撞。读旧快照时如角色胶囊与新增家具相交，使用已有A*网格选择附近自由点；只修正必要的内存位置，玩家看到layout_adjusted事件，源快照字节不改。未相交位置保持原JSON数值，避免二次float32转换破坏精确往返测试。此版本没有为装饰资源另升存档schema，仍为3。

## 验证

- ASSET_REPLAY_OK：独立重生成10个GLB和manifest逐字节相同。
- ASSET_IMPORT_OK：10个资源可导入、三角面/网格数、箱子米制尺寸、无重复碰撞、16骨骼、五动作、蒙皮权重、真实骨骼采样变化、移动回站立、倒地末帧、装备可见性、建筑剖面契约。
- VISUAL_INTEGRATION_OK：进出建筑只切当前屋顶，开关门实际碰撞射线，新增桌子位置修复且源档不改，真实攻击/受伤/死亡选择正确动画。
- 原规则/AI、跑步追击脱离、危险打断睡眠、睡到第二天与Markdown/存读档继续全套通过。图形窗口仍使用OpenGL Compatibility/GTX1650；未声称验证普通集显性能。
- `preview_assets.gd`实际渲染十一个动作采样实例（玩家六个、僵尸五个），生成work/c3-poses.png；这是一张采样图，不是完整动作视频。GLB中保留可播放的实际动画。
- CHARACTER_MOTION_OK：用真实输入行走和奔跑，确认速度、体力、声音、奔跑腿骨变化，以及停止/攻击切换，见 tests/test_character_motion.gd。
