#!/usr/bin/env python3
"""Link the documentation host to a fresh native debug build (not the app entry point).

First run: swift build --scratch-path .build/native-test
Then run:  python3 scripts/showcase/build.py
SDKROOT may select the same SDK used for the production build.
"""
from pathlib import Path
import os
import subprocess

root = Path(__file__).resolve().parents[2]
os.chdir(root)
scratch = root / '.build/native-test'
out = root / '.build/showcase'
out.mkdir(parents=True, exist_ok=True)
modules = list(scratch.rglob('TrafficLightsPlus.swiftmodule'))
if not modules:
    raise SystemExit('Build the current sources with --scratch-path .build/native-test first.')
module = max(modules, key=lambda path: path.stat().st_mtime)
objects_dir = module.parent
if objects_dir.name == 'Modules':
    objects_dir = objects_dir.parent / 'TrafficLightsPlus.build'
objects = sorted(path for path in objects_dir.glob('*.o')
                 if path.name not in ('TrafficLightsPlusApplication.o', 'TrafficLightsPlusApplication.swift.o'))
if not any('GlassPointerLight' in path.name for path in objects):
    raise SystemExit('The debug objects are stale. Rebuild the current sources first.')
framework = scratch / 'artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64'
sdk = os.environ.get('SDKROOT') or subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
subprocess.run([
    'swiftc', '-parse-as-library', '-sdk', sdk, '-I', str(module.parent),
    '-F', str(framework), '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', str(framework),
    'scripts/showcase/Showcase.swift', *map(str, objects), '-o', str(out / 'showcase')
], check=True)
subprocess.run(['swiftc', '-parse-as-library', 'scripts/showcase/Export.swift', '-o', str(out / 'export')], check=True)
bundles = list(scratch.glob('out/Products/Debug/TrafficLightsPlus_TrafficLightsPlus.bundle'))
bundles += list(scratch.glob('*/debug/TrafficLightsPlus_TrafficLightsPlus.bundle'))
if not bundles:
    raise SystemExit('The native debug build resource bundle is missing.')
subprocess.run(['/usr/bin/ditto', str(bundles[0]), str(out / 'TrafficLightsPlus_TrafficLightsPlus.bundle')], check=True)
print('Documentation host built from the current native debug objects:', out)
