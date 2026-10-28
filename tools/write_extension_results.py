"""Index actual extension evidence after the graphical checks complete."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

def main():
    log = (ROOT / 'work/extension-checks.log').read_text(encoding='utf-8')
    for marker in ['ALL_CHECKS_OK', 'ASSET_REPLAY_OK', 'EAST_EXTENSION_OK',
                   'GROUND_DROPS_OK', 'GAME_AUDIO_OK']:
        assert marker in log, marker
    evidence = []
    for name in ['pantry_home', 'end_home', 'street']:
        path = ROOT / f'work/clinic-extension-{name}.png'
        with Image.open(path) as picture:
            assert picture.size == (1920, 1080)
        evidence.append({
            'file': path.relative_to(ROOT).as_posix(),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'resolution': [1920, 1080],
            'source': 'Actual Godot viewport from test_east_extension.gd; input-driven route, enemies disabled; room shots after loot, lights on and save/load; street after leaving both rooms. Time advances during walking; HUD records capture time. Production orthographic camera follows player.'
        })
    for name in ['step', 'melee', 'impact', 'gunshot']:
        path = ROOT / f'work/audio-v2/{name}.wav'
        assert path.stat().st_size > 44
        evidence.append({
            'file': path.relative_to(ROOT).as_posix(),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'source': 'Runtime synthesizer PCM exported by test_game_audio.gd; audition sample, not gameplay recording or human listening acceptance.'
        })
    (ROOT / 'work/extension-evidence.json').write_text(
        json.dumps(evidence, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('EXTENSION_EVIDENCE_OK', len(evidence))

if __name__ == '__main__':
    main()
