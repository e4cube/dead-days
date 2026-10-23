# V1 测试报告

日期：2026-10-22（Asia/Shanghai）。环境：Windows / Python 3.13.14 / Git 2.53.0。

## 验证结果

| 验证 | 结果 |
|---|---|
| `python -m unittest discover -s art-library/tests -v` | 25 项全部通过 |
| `python art-library/scripts/library.py check` | 1 项记录，1 项 APPROVED，0 错误 |
| `python art-library/scripts/library.py build` | 成功生成 catalog、approved、署名清单及授权台账 |
| 按 realistic + Textures + CC0-1.0 + PNG 搜索 | 仅返回该地表贴图 |
| 不匹配风格筛选 | 返回空列表 |
| 重复 build | 生成内容一致，不依赖网络 |
| 已有游戏资源 | Git 树校验与变更路径检查，均未修改 |

25 项测试覆盖：合法 CC0、版本字段、二期平台禁用、无明确批准不放行、全部风险检查必填、
NC/ND/UNKNOWN 阻断、GPL/SA/自定义单独评估、未知权限、拒绝权限、字符串布尔值、
素材/证据篡改、缺失证据、许可 URL 不符、路径穿越、文件缺失、未来日期、
CC BY 完整署名、显式阻断、损坏 JSON/孤立文件、错误字段类型、重复 ID 双向降级、
旧可用索引撤销、组合检索和失败退出码、Windows 管道 UTF-8 JSON 输出。

## 验证范围

未修改网站或游戏运行时代码，未执行 Next.js build 或原有浏览器游戏测试。
未声称完成 Blender/Godot/Three.js 导入；V1 的兼容是元数据收录/筛选与接入需求说明。
示例为单张颜色贴图，尚未完成 PBR 配套。未实现 GLTF 外部依赖解析或格式转换。
授权证据为官方页面阅读摘要及实际图像审查，非完整页面快照或人类法务签字。
未批量下载、未公开发布、未提供素材包下载。
