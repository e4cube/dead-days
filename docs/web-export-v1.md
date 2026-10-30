# 网页版导出（Web 导出链路 v1）

目标：把 Godot 工程按「能在浏览器里打开、能开局、能存档」的标准导出一次，并把整条链路固化成脚本，避免每次手工点导出面板。

本轮结论：**Web 版可用**——Godot 4.7.2 在 Chromium 里启动、画布 1280×720 正常渲染、中文界面完整、可以点开新游戏、可以走动、F5 存档写进 `localStorage`。同时记录一条已知的控制台噪声（不影响画面与玩法，见文末）。

## 一、导出链路

`tools/build_web_fixed.py` 一次跑完四步：

1. `--headless --editor --import --quit`：刷新导入缓存（**必须**，见「已知坑」）。
2. `--headless --script res://tests/test_rules.gd`：规则冒烟测试，防止导出明显跑不起来的包。
3. `--headless --script res://compress_web_assets.gd`：把 `.godot/imported/*.scn` 用 `ResourceSaver.FLAG_COMPRESS` 原地重存。
4. `--headless --export-release "Web Validation" ../web/index.html`：出包到 `web/`。

导出前先建目录：`Path('web').mkdir(exist_ok=True)`。Godot 导出器**不会自己创建输出目录**，目录不存在时只报「目标文件夹不存在或无法访问」，容易误判成权限问题。

产物（本次实测）：

| 文件 | 体积 |
| --- | --- |
| `web/index.wasm` | 39.5 MB |
| `web/index.pck` | 20.3 MB |
| `web/index.js` | 280 KB |
| 合计 `web/` | 57.4 MB |

第 3 步的收益是决定性的：未经压缩的 `.scn` 合计 90.1 MB，压完 9.9 MB。不做这一步，pck 会从 20 MB 涨到约 100 MB。

## 二、为 Web 改的四处工程配置

1. **单线程模板**：`godot/export_templates/web_nothreads_release.zip`（10 MB，随仓库提交），`export_presets.cfg` 里指向 `res://export_templates/web_nothreads_release.zip`。
   单线程包不需要 COOP/COEP 跨域隔离头，普通静态服务器（含 `python -m http.server`）就能跑；多线程包缺少 `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` 时会直接启动失败。
   *本机 `%APPDATA%\Godot\export_templates\` 是空的，没有系统模板可依赖，所以模板必须跟着仓库走。*
2. **中文界面字体**：`godot/fonts/NotoSansSC-subset.ttf`（163 KB，OFL）由 `tools/subset_font.py` 生成——扫 `scripts/`、`data/` 里出现过的全部非 ASCII 字符，走 Google Fonts 的 `text=` 子集接口取回，再写进 `project.godot` 的 `[gui] theme/custom_font`。
   不做子集直接挂全量思源黑体会让 pck 膨胀十几 MB；不做这一步则浏览器里中文全是豆腐块。
3. **存档走 `localStorage`**：`godot/scripts/save_store.gd` 在 `OS.has_feature("web")` 时，除照常写 `user://` 文件外，额外用 `JavaScriptBridge.eval` 把 `model.state` 的 JSON 写进 `localStorage`，键名 `deaddays:snapshot:<存档目录>`；读取时优先读它并过 `model.valid()`，不合法才回落到文件。
   原因：`user://` 在 Web 上依赖 IndexedDB 持久化，无痕模式、iframe 三方 Cookie 受限等场景会静默丢档。
4. **日志导出**：`game.gd` 的 `export_journal()` 在 Web 下改走 `JavaScriptBridge.download_buffer()`，因为浏览器里没有可写的真实路径。

## 三、验收记录（2026-10-30）

导出后用 `python -m http.server 8777 --directory web` 起静态服务，再用无头 Chromium 走真实点击链路：

- 引擎日志：`Godot Engine v4.7.2.stable`、`OpenGL ES 3.0 (WebGL 2.0)`、`Emscripten 4.0.20, single-threaded`。
- 画布：1 个 canvas，1280×720，WebGL2 上下文可用；`localStorage` 可读写。
- 标题页：`新游戏（保留所有已有快照）` / `继续最近有效存档` / `画质` / `退出` 全部正常显示，中文字体无缺字。
- 点「新游戏」后进入灰湾街区，HUD 显示 `第1天 08:00 · 生命100 饱腹65 饮水65 体力100 负重0.0/5.0kg`。
- 按 W 走动：时间推进到 `08:11`，靠近住宅门后提示变为 `[E] 开门/住宅 · 门耐久120/120 · [C] 修门/加固`。
- 按 F5 存档：`localStorage` 出现 `deaddays:snapshot:user://saves/east_expanse_v1`，31415 字节（另一次 33171 字节）。
- 页面级 JS 异常（`errors`）为 0。

截图存于 `docs/shots/`：`web-smoke.png`（标题页）、`web-ingame.png`（开局画面）、`web-moved.png`（走动 + 门交互提示）。

### 点击坐标怎么算

Godot 的 UI 全部画在 canvas 里，DOM 里只有一个 `<canvas>`，可访问性树看不到按钮，只能按坐标点。工程 `1152×720`、`stretch/canvas_items`、默认 aspect `keep`，在 1280×720 视口下左右各留 64px 黑边、像素比 1:1。
菜单 `VBoxContainer` 起始于内部坐标 `(395,200)`，所以「新游戏」这一行的中心在 **画布 (633, 301)**——注意要在整个按钮高度内点，点在两个按钮之间的缝里不会触发，也不报错。

## 四、已知坑

### 1. 导入缓存过期会刷 `texture_set_size_override` 报错

现象：进游戏瞬间控制台刷出上百条

```
ERROR: Parameter "texture" is null.
   at: texture_set_size_override (drivers/gles3/storage/texture_storage.cpp:1864)
```

排查结论：这个报错**和 Web 无关**，原生 GL Compatibility 和 Forward+（Vulkan）都一样；回溯指向 `asset_library.gd:4` 的 `load("...glb").instantiate()`，每个 glb 按材质数量报 3 的倍数条。

- 干净的 `.godot/imported`（`--import` 重新导入后）：**0 条**。
- 陈旧缓存：135 条。
- 把 `gltf/embedded_image_handling` 从 `2`（Basis 嵌入）改成 `3`（非压缩嵌入）也能归零，但 `.scn` 从 10.5 MB 涨到 88 MB，**不要这么做**；改成 `1`（抽取纹理）同样归零，代价是往仓库里塞 559 个 PNG（约 78 MB）。两者都比「重新导入一次」差。

所以日常只要保证导出前跑过 `--import`。

### 2. 场景压缩会让它回来（接受，不修）

`compress_web_assets.gd` 用 `FLAG_COMPRESS` 重存 `.scn` 之后，上面那 135 条又会出现在浏览器控制台。原因是重存后的 `PortableCompressedTexture2D`（glTF 的 Basis 嵌入纹理）在实例化时，`set_size_override` 先于纹理 RID 创建被调用，属于引擎侧的时序问题，GDScript 层改不了。

**它只是噪声，不是画面问题**，有对照证据：同一机位 960×540 截帧，未压缩 vs 压缩后逐像素比较——518400 个像素里只有 328 个不同，均值差 0.044、最大 146，肉眼无法分辨；而且玩法、存档、读档全部正常。

取舍：保留压缩（pck 20 MB），接受控制台噪声；不为了消噪把 pck 换成 100 MB 或往仓库塞 78 MB PNG。若将来要彻底消掉，正确方向是让 glTF 走「抽取纹理 + 纹理按平台做 VRAM 压缩导入」，而不是现在的 Basis 嵌入。

## 五、复现命令

```bash
python tools/build_web_fixed.py                      # 出包到 web/
python -m http.server 8777 --directory web           # 本地起服务
# 浏览器打开 http://127.0.0.1:8777/
```

若改了脚本或 `data/` 里的中文文案，先跑 `python tools/subset_font.py` 重新生成字体子集，否则新出现的汉字会缺字。
