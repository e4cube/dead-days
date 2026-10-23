# GameVado 素材库接入 Dead-Days

后续交接记录（2026-10-23）：`10e2d75` 已安全接回原仓库，文件与生产存档指纹未变。本阶段用户另行授权完成后推送GitHub；下文“不推送”描述的是最初接入时的范围。

接入范围：室外地表底色。只使用先前经过来源及图像辅助审核的一张 Poly Haven 1K PNG，未新增网络下载。
建筑、角色、道路图集、碰撞、导航、存档格式均沿用已有实现。

## 工程与使用

- 启动 `godot/project.godot`，新游戏或继续游戏都会为 `OutdoorGround` 设置贴图。
- `godot/scripts/ground_material.gd` 创建地表材质，用世界空间三平面映射每 6 米重复，开启 mipmap 过滤。
- 原图未修改；颜色调整在 Godot 材质中完成。只使用 base color，粗糙度固定为 1，不伪造完整 PBR。
- 原有 GLB 源工程及生成脚本不改动，Blender 重建不会覆盖这次运行时材质。
- 道路和建筑地板在地表上方，继续使用各自材质。

## 授权与复用

`art-library/` 从 GameVado V1 本地提交 `513eb4b` 引入；其中原有 REPOSITORY_AUDIT.md 与 TEST_REPORT.md
记录的是素材库初建过程（miniplay 基线），本文件才是本次 Dead-Days 接入记录。

- 许可证：CC0-1.0；作者 Rob Tuytel；来源 https://polyhaven.com/a/aerial_grass_rock 。
- 元数据及证据：`art-library/assets/Textures/polyhaven-aerial-grass-rock/`。
- 台账：`art-library/index/LICENSE_LEDGER.md`。
- 引擎文件映射：`art-library/projects/dead-days-runtime.json`。
- `python tools/check_gamevado_assets.py` 会重新审核来源元数据，并确认运行时 PNG 与获批原图 SHA256 一致。
- 常规 `tools/run_checks.py` 已加入上述检查和 Godot 材质专项测试。
- 新素材先放进素材库完成审核，再登记映射；不把未审核文件直接复制到 Godot 目录。

该贴图不满足僵尸、车辆、家具、建筑模型等需求；这些条目继续 OPEN。
本次不推送、不发布游戏、不导出素材下载包。

## 验证与环境限制

素材库 25 项单元测试通过；授权门禁及运行时文件哈希通过。
实际 Godot OpenGL 渲染已截图，验证 1K 贴图加载、三平面映射、原碰撞尺寸和建筑材质隔离。
完整回归通过：规则、容器、存取、原有 GLB 导入、街景、视觉集成、威胁、时间、休息安全、
角色动作、端到端搜刮、脱离追击、跨日睡眠、三栋建筑、独立照明及两套视觉预览。
测试完成标记：`ALL_CHECKS_OK / legacy and Godot production saves/exports unchanged`。
原始日志见 `work/gamevado-full-checks.log`。本次未重建 Blender GLB，因为其源文件和导出文件没有变更。

本机沙箱无法读取 Windows 根证书仓库，Godot 启动会报固定的证书存储错误。
验证包装器仅过滤这一条已知环境错误及其栈位置，保留原始日志；其他引擎错误、缺失断言标记或非零退出仍会失败。
测试编辑器使用临时便携副本以隔离设置，存取测试使用 `user://tests/`，并检查生产存档/导出指纹不变。
