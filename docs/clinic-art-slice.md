# 诊所室内切片

第二栋建筑现在有诊疗床、候诊长椅、抬脚凳、棋盘地砖、墙面腰线、药品架、病历图和器械台陈设。新增 `art/source/clinic_details.blend` 与 `godot/assets/clinic_details.glb`，128个可编辑盒体模块、1536三角面；项目总计20份源工程/GLB。

`godot/data/clinic_layout.json` 统一定义模型位置、3个新增家具碰撞与镜头配置。现有药柜和器械桌仍保留原碰撞，器械桌向墙侧移动0.25米，留出柜子右侧和后部的实际通路。诊所进屋后采用住宅同类的中心构图、平滑缩放和常驻文字收起，八方向转动时屋顶/前景立面及墙上陈设按原剖切规则切换。

药柜继续使用原来的 `clinic` 库存和5kg承重，初始仅3份绷带；E搜刮、B存取、3使用绷带、日志与schema4存读档全部复用。柜顶最多显示3个药盒，随真实绷带库存收起/恢复，包括存取面板暂停期间；数量以库存面板为准。墙架上的瓶子和器械属于陈设，没有冒充独立物品。诊疗床尚不能睡眠、自动治疗或提供新交互；无电力、感染、医疗职业等规则。

## 重建与运行

```powershell
& 'D:\Blender\blender.exe' --background --factory-startup --python tools/generate_clinic_details.py
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --headless --path godot --editor --import --quit
& 'D:\GameDev\Godot_v4.7.2-stable_win64.exe' --path godot
```

本轮生成器已接入资源重放检查，支持 `-- --output-root work/asset-replay`，同一环境下全部20份GLB逐字节核对。手工修改生成的源工程前请另存副本。

## 实际验证

`test_clinic_slice.gd` 从初始出生点使用真实输入走到诊所、开门进入、搜刮三份绷带；随后明确通过伤害函数建立30点伤害夹具，使用真实3键消耗一份绷带恢复25生命。这段验证不冒充实际被僵尸击中。测试还覆盖B面板存入/取回与药盒显示、走到药柜后方、八方向旋转、保存继续后库存不补货、实际走出建筑。

完整运行命令同 [室内与镜头报告](interior-camera-pass.md)，本轮日志 `work/clinic-final-checks.log`，实景截图 `work/clinic-treatment.png`、`clinic-rear.png`、`clinic-reverse.png`、`clinic-exit.png`。旧版保护、原住宅进出、追击脱离、真实跨日休息和存读档均纳入回归，生产存档/导出指纹保护仍生效。

现有旧快照只在角色与新增家具相交时使用原有安全位置修正，并记录调整事件，源快照不覆盖。尚未为诊所接入室内灯、前景树冠裁剪或多层结构；当前仍为单层小街区，不代表整个城市阶段完成。
