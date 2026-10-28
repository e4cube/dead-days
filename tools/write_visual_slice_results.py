"""Append verified raw-run results, never infer aesthetic acceptance from test success."""
from pathlib import Path
import hashlib,json
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'work/visual-slice'
def read(name):return json.loads((OUT/name).read_text(encoding='utf-8'))
def main():
    checks=(OUT/'full-checks.log').read_text(encoding='utf-8')
    capture=(OUT/'capture.log').read_text(encoding='utf-8')
    assert 'ALL_CHECKS_OK' in checks and 'ASSET_REPLAY_OK' in checks and 'MATERIAL_LIBRARY_V1_OK' in checks
    assert 'VISUAL_SLICE_V1_OK' in capture
    assert 'OK' in (OUT/'asset-library-tests.log').read_text(encoding='utf-8')
    active=read('gameplay-performance.json');paused=read('performance.json');safety=read('save-safety.json')
    assert safety['unchanged'] and paused['failures']==0
    evidence=[]
    for directory in [OUT,OUT/'before']:
        for path in sorted(directory.glob('*.png')):
            with Image.open(path) as image:
                assert image.size==(1920,1080),str(path)
            source='Actual Godot game viewport; explicit camera/time fixtures in capture-conditions.json'
            if path.name.startswith('firearm-'):
                source='Actual Godot controlled gameplay test; firearms-capture-conditions.json; combat targets are fixtures, not natural encounters'
            if path.name.startswith('zombie-'):
                source='Actual Godot street paused appearance lineup; zombie-capture-conditions.json; HUD/player hidden, not natural encounter footage'
            if path.name.startswith('east-'):
                source='Actual input-driven expanded-block playthrough; east-capture-conditions.json; enemies disabled to isolate geometry and interaction'
            if path.name.startswith('drops-'):
                source='Actual movement and production backpack/storage callbacks; drops-capture-conditions.json; enemies disabled; reused crate marker'
            if path.name.startswith('door-'):
                source='Actual Godot AI door damage, collision and navigation test; door-capture-conditions.json; explicit entrance enemy and weakened door fixtures, not natural encounter'
            if path.name=='character-before-refinement.png':
                source='Actual previous player GLB, saved before refinement; 1080p daytime orthographic size 4 back view'
            if path.name=='character-front-refined.png':
                source='Actual Godot street with simulation paused; player visual rotated 180 degrees for front inspection; not movement evidence'
            if path.name=='character-portrait-review.png':
                source='Actual Godot street paused model inspection; lower orthographic camera size 2.1, not the gameplay camera; capture-conditions.json'
            evidence.append({'file':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'size':[1920,1080],'source':source})
    (OUT/'evidence-manifest.json').write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8')
    path=ROOT/'docs/visual-slice-v1-report.md'
    text=path.read_text(encoding='utf-8').split('<!-- VERIFIED_RUN_RESULTS -->')[0].rstrip()
    text+='\n\n<!-- VERIFIED_RUN_RESULTS -->\n## 最终运行记录\n\n'
    text+='- Godot '+active['godot']+'，'+active['driver']+' / Compatibility；Blender 5.2.2 LTS。\n'
    text+='- Windows 11 Pro 10.0.22631；AMD Ryzen 7 4800H；OS可见内存16,505,966,592字节；'+active['gpu']+'。\n'
    text+=f'- 实际视口1920×1080，VSync模式{active["vsync"]}。实时世界采样：预热60帧、采样240帧，人物在住宅外静止、3只活僵尸，平均{active["mean_fps"]:.2f} FPS，P95帧间隔{active["p95_frame_ms"]:.3f}ms，世界推进{active["minutes_advanced"]:.2f}游戏分钟。\n'
    text+=f'- 另存暂停模拟的渲染采样：平均{paused["mean_fps"]:.2f} FPS，P95 {paused["p95_frame_ms"]:.3f}ms；末帧{int(paused["draw_calls"])} draw calls、{int(paused["objects"])}渲染对象。该统计含阴影等提交，不等于模型数量。\n'
    text+='- 垂直同步锁帧、短时静止采样没有证明渲染余量，也不是长时间移动/战斗最低帧率；GPU帧耗时、显存、温度及更低规格设备未测。提交数偏高，后续优化需保留库存显示和切换对象的语义。\n'
    map_count=len(json.loads((ROOT/'godot/assets/materials_v1/manifest.json').read_text(encoding='utf-8'))['maps'])
    text+=f'- 完整回归 `ALL_CHECKS_OK`；{map_count}份原始表面贴图及清单、21份GLB/清单重跑字节一致；25项素材库单元测试通过。连续实机输入流程 `VISUAL_SLICE_V1_OK`，{safety["protected_file_count"]}个受保护存档/导出文件的指纹不变。\n'
    text+='\n真实截图：`street-day.png`、`street-night.png`、`house-interior.png`、`character-closeup.png`；流程证据 `01-street-exploration.png` 至 `07-encounter-zombie.png`，均位于 `work/visual-slice/`。同目录保留原始日志、性能JSON、截图条件和SHA清单；`before/`为旧基线同路径实机对照。没有生成视频替代游戏录屏。\n'
    text+='\n本轮阶段提交仅在独立本地分支保留；未合并main、未推送或发布。技术通过不覆盖上表仍未完成的美术门禁。\n'
    path.write_text(text,encoding='utf-8')
    print('VISUAL_RESULTS_VERIFIED',len(evidence),'real viewport images')
if __name__=='__main__':main()
