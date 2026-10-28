"""Inspect exported GLB portability without loading Dead Days gameplay code."""
from pathlib import Path
import hashlib
import json
import struct
import argparse
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', help='Also import and instantiate in a gameplay-free temporary Godot project')
    args = parser.parse_args()
    assets = []
    for path in sorted((ROOT / 'godot/assets').glob('*.glb')):
        raw = path.read_bytes()
        magic, version, length = struct.unpack_from('<4sII', raw)
        assert (magic, version, length) == (b'glTF', 2, len(raw)), path.name
        chunk_length, chunk_type = struct.unpack_from('<II', raw, 12)
        assert chunk_type == 0x4E4F534A, path.name
        data = json.loads(raw[20:20 + chunk_length])
        # A reference PNG is not portable merely because it exists on this machine.
        external = [v['uri'] for key in ('buffers', 'images')
                    for v in data.get(key, [])
                    if 'uri' in v and not v['uri'].startswith('data:')]
        assert not external, (path.name, external)
        source = ROOT / 'art/source' / (path.stem + '.blend')
        assert source.exists(), source
        assets.append(dict(id=path.stem, glb=str(path.relative_to(ROOT)).replace('\\', '/'),
                           sha256=hashlib.sha256(raw).hexdigest(),
                           embedded_images=len(data.get('images', [])),
                           meshes=len(data.get('meshes', [])),
                           skins=len(data.get('skins', [])),
                           animations=[a.get('name', '') for a in data.get('animations', [])],
                           external_file_dependencies=external))
    report = dict(scope='GLB container dependency audit; not an external-engine visual or license acceptance',
                  assets=assets, count=len(assets),
                  excluded=['art/references', 'production saves', 'third-party asset library'])
    out = ROOT / 'work/visual-slice/asset-reuse-audit.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(f'ASSET_REUSE_AUDIT_OK / {len(assets)} GLBs, no external buffer/image paths')
    if args.godot:
        project = ROOT / 'work/asset-reuse-project'
        project.mkdir(parents=True, exist_ok=True)
        (project / 'project.godot').write_text(
            'config_version=5\n[application]\nconfig/name="Asset reuse verification"\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
        for asset in assets:
            shutil.copy2(ROOT / asset['glb'], project / (asset['id'] + '.glb'))
        names = json.dumps([asset['id'] for asset in assets])
        script = ('extends SceneTree\nfunc _initialize():\n    call_deferred("verify")\n'
                  'func verify():\n    var count := 0\n'
                  f'    for id in {names}:\n'
                  '        var scene = load("res://" + id + ".glb")\n'
                  '        if scene == null:\n            quit(1)\n            return\n'
                  '        var node = scene.instantiate()\n        root.add_child(node)\n'
                  '        if node.find_children("*", "MeshInstance3D", true, false).is_empty():\n'
                  '            quit(2)\n            return\n'
                  '        count += 1\n        node.queue_free()\n'
                  f'    assert(count == {len(assets)})\n'
                  '    print("ASSET_REUSE_IMPORT_OK / ", count, " standalone GLBs")\n    quit(0)\n')
        (project / 'verify.gd').write_text(script, encoding='utf-8')
        logs = []
        for flags in [['--editor', '--import'], ['--script', 'res://verify.gd']]:
            result = subprocess.run([args.godot, '--headless', '--path', str(project), *flags],
                                    capture_output=True, timeout=180)
            logs.append(result.stdout + result.stderr)
            (out.parent / 'asset-reuse-import.log').write_bytes(b'\n'.join(logs))
            assert result.returncode == 0, 'Standalone import failed; see asset-reuse-import.log'
        assert b'ASSET_REUSE_IMPORT_OK' in logs[-1]
        print('ASSET_REUSE_IMPORT_OK / isolated project contains GLBs only, no gameplay dependencies')


if __name__ == '__main__':
    main()
