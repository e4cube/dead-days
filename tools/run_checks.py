"""Repeatable checks; all new-game tests use unique user://tests subdirectories."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def run(command, marker=None, timeout=90):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                            encoding='utf-8', errors='replace', timeout=timeout)
    output = result.stdout + result.stderr
    print(output)
    if result.returncode or 'SCRIPT ERROR' in output or '\nERROR:' in output or (marker and marker not in output):
        raise RuntimeError(f'Check failed: {command}')
    return output


def legacy_safety():
    # Import the patched entry point, then point it at a sentinel player sandbox.
    # The public selftest must redirect both globals and restore them even on failure.
    import importlib.util
    os.environ['SDL_VIDEODRIVER'] = 'dummy'
    os.environ['SDL_AUDIODRIVER'] = 'dummy'
    spec = importlib.util.spec_from_file_location('dead_days_legacy', ROOT / 'main.py')
    legacy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(legacy)
    legacy.pygame.init()
    try:
        with tempfile.TemporaryDirectory(prefix='dd-save-sentinel-') as folder:
            sentinel = Path(folder) / 'save.json'
            sentinel.write_bytes(b'PLAYER SAVE SENTINEL: do not overwrite or delete')
            original = sentinel.read_bytes()
            legacy.SAVE_FILE = str(sentinel)
            legacy.EXPORT_DIR = str(Path(folder) / 'exports')
            assert legacy.selftest() == 0
            assert sentinel.read_bytes() == original
            assert legacy.SAVE_FILE == str(sentinel)
            assert not Path(legacy.EXPORT_DIR).exists()
            real_test = legacy._selftest_isolated
            def fail():
                raise RuntimeError('deliberate failure')
            legacy._selftest_isolated = fail
            try:
                legacy.selftest()
            except RuntimeError:
                pass
            else:
                raise AssertionError('expected failure')
            legacy._selftest_isolated = real_test
            assert legacy.SAVE_FILE == str(sentinel) and sentinel.read_bytes() == original
        print('LEGACY_SAFETY_OK')
    finally:
        legacy.pygame.quit()


def fingerprint():
    result = {}
    paths = [ROOT / 'save.json']
    protected = [ROOT / 'exports']
    if os.environ.get('APPDATA'):
        data_root = Path(os.environ['APPDATA']) / 'DeadDaysRebuild'
        protected.extend([data_root / 'saves', data_root / 'exports'])
    for directory in protected:
        if directory.exists():
            paths.extend(p for p in directory.rglob('*') if p.is_file())
    for path in paths:
        result[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--blender', help='Also regenerate a separate asset pack and verify byte-identical GLBs')
    parser.add_argument('--visual', action='store_true', help='Run real renderer; capture playthrough, C1 pursuit and C2 sleep screenshots in work/')
    args = parser.parse_args()
    (ROOT / "work").mkdir(exist_ok=True)
    before = fingerprint()
    try:
        legacy_safety()
        if args.blender:
            run([sys.executable, 'tools/check_asset_pipeline.py', '--blender', args.blender], 'ASSET_REPLAY_OK')
        run([args.godot, '--headless', '--path', 'godot', '--editor', '--import', '--quit'])
        run([args.godot, '--headless', '--path', 'godot', '--script', 'res://tests/test_rules.gd'], 'RULES_OK')
        run([args.godot, '--headless', '--path', 'godot', '--script', 'res://tests/test_containers.gd'], 'CONTAINERS_OK')
        run([args.godot, '--headless', '--path', 'godot', '--script', 'res://tests/test_storage.gd'], 'STORAGE_OK')
        run([args.godot, '--headless', '--path', 'godot', '--script', 'res://tests/test_assets.gd'], 'ASSET_IMPORT_OK')
        run([args.godot, '--headless', '--path', 'godot', '--script', 'res://tests/test_visual_integration.gd'], 'VISUAL_INTEGRATION_OK')
        run([args.godot, '--headless', '--path', 'godot', '--script', 'res://tests/test_threats.gd'], 'THREATS_OK')
        run([args.godot, '--headless', '--path', 'godot', '--script', 'res://tests/test_time.gd'], 'TIME_RULES_OK')
        run([args.godot, '--headless', '--path', 'godot', '--script', 'res://tests/test_rest_safety.gd'], 'REST_SAFETY_OK')
        command = [args.godot] + ([] if args.visual else ['--headless'])
        run(command + ['--path', 'godot', '--script', 'res://tests/test_character_motion.gd'], 'CHARACTER_MOTION_OK')
        run(command + ['--path', 'godot', '--script', 'res://tests/test_playthrough.gd'], 'PLAYTHROUGH_OK')
        run(command + ['--path', 'godot', '--script', 'res://tests/test_escape.gd'], 'ESCAPE_PLAYTHROUGH_OK')
        run(command + ['--path', 'godot', '--script', 'res://tests/test_sleep_playthrough.gd'], 'SLEEP_PLAYTHROUGH_OK')
        run(command + ['--path', 'godot', '--script', 'res://tests/test_house_slice.gd'], 'HOUSE_SLICE_OK')
        if args.visual:
            run(command + ['--path', 'godot', '--script', 'res://tests/preview_assets.gd'], 'ASSET_GALLERY_OK')
    finally:
        assert fingerprint() == before, 'Protected player files changed!'
    print('ALL_CHECKS_OK / legacy and Godot production saves/exports unchanged')

if __name__ == '__main__':
    main()
