# GameVado 美术素材库 V1

内部作者资产库，位于仓库根目录，禁止移入 `public/` 或作为素材包发布。
Python 3.11+，零第三方依赖。不修改现有游戏，也不自动下载、转换或部署。

## 使用

在仓库根目录执行：

```sh
python art-library/scripts/library.py check
python art-library/scripts/library.py build
python art-library/scripts/library.py search --style realistic --category Textures --license CC0-1.0 --format PNG
python art-library/scripts/library.py search --status REVIEW_REQUIRED --query zombie
python -m unittest discover -s art-library/tests -v
```

`check`：检查结构、许可证门禁、人工审核字段、证据及 SHA256；非零退出表示损坏元数据、孤立文件或无效 APPROVED。
合法的 REVIEW_REQUIRED/BLOCKED 记录可以保留在库内，不会使检查失败，但绝不进入 approved.json。
`build`：每次重新审核所有记录，输出完整目录、可用索引、署名清单和授权台账；即使有错误也会移除旧的可用条目并非零退出。
`search`：实时审核后组合筛选；默认只显示 APPROVED，风格/类别/许可/格式为精确匹配，query 为文本包含。
索引为内部数据文件，不能直接当作公开发布清单或打包许可；V1 不提供导出/复制命令。

## 目录与接入

- assets/{Characters,Environments,Props,Animations,Textures,UI,VFX,Audio}/<id>/：每项素材独立 metadata.json、文件与 evidence/。
- templates/metadata.json：默认 UNKNOWN + REVIEW_REQUIRED；填完整后再审核。空模板本身不是有效素材。
- projects/：Dead-Days、万朝、GameVado 小游戏需求清单；selected_asset_ids 默认空，不声称已接入游戏。
- sources/platforms.json：一期 OpenGameArt、itch.io、Poly Haven，二期 Fab、Sketchfab 禁用。
- index/：生成索引、LICENSE_LEDGER.md、ATTRIBUTIONS.txt。

支持 GLB、GLTF、FBX、OBJ、BLEND、PNG、WEBP、SVG、WAV、OGG，另支持 JPG、EXR。
这表示收录和筛选支持，不代表引擎可直接读取：Godot/Three.js 优先 GLB；Blender 使用 BLEND/FBX/OBJ；
GLTF 必须登记 .bin、外部贴图等依赖后再接入（V1 尚未提供依赖解析，建议先转自包含 GLB 并重新审核）。
文件转换必须保留来源，注明修改并更新哈希；不自动复制到已有 public/assets 或游戏工程。

## 授权流程

1. 人工在原始发布页面筛选少量候选。不得绕过登录、验证码、反爬或下载限制；403 后停止该访问方式。
2. 记录作者、版本/原页、许可证原文链接、权限及证据。未经完整审核不扩大下载规模。
3. 下载最少文件，记录实际日期、公开下载 URL、SHA256；保存证据（原文快照或明确标注的审核摘要）。
4. 查看实际内容，记录来源真实性、商标、肖像、第三方内容风险，填写 reviewer/date/notes。
5. CC0 仍需全部审核；CC BY 3.0/4.0 需署名全文含标题/作者/原页/许可、修改说明、版权声明及展示位置。
6. GPL、CC BY-SA、自定义或其他版本一律 REVIEW_REQUIRED，另行形成适配项目的评估方案；V1 没有覆盖开关。
   NC、ND、UNKNOWN 或明确拒绝任一所需权限，一律 BLOCKED，不得自动进入公开游戏。
7. 只有明确 APPROVED 且所有门禁通过才进入 approved.json。手填 APPROVED 不能绕过检查。
8. 游戏发布前负责人复核署名展示、转换产物及新风险；本库批准只针对列出且校验一致的文件。

SHA256 用于发现内容变更，不保证证据真实性；审核记录需要代码评审。辅助审核不是法律意见或人类签字。
示例仅一项 Poly Haven 地表 Diffuse PNG；它不是完整 PBR 材质，不能代替 normal/roughness。
证据明确标为官方页面阅读摘要；页面 HTTP 抓取被拒绝后未绕过。示例通过来源与逐图辅助审核，项目负责人仍可降级。
不将现有游戏资源追溯性标记为 APPROVED。公开仓库提交/推送和公开游戏部署需另行授权。
