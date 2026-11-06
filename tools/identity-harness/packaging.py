#!/usr/bin/env python3
"""Run production packaging with a controlled Swift compiler and OS signing boundary."""
from pathlib import Path
import os, plistlib, shutil, subprocess, tempfile

repo = Path(__file__).resolve().parents[2]
root = Path(tempfile.mkdtemp(prefix='mls-next-packaging.', dir='/tmp'))
source = root/'source'; source.mkdir()
for name in ['build.sh', 'build-dmg.sh', 'VERSION']:
    shutil.copy2(repo/name, source/name)
shutil.copytree(repo/'Resources', source/'Resources')
(source/'tools').mkdir()
shutil.copy2(repo/'tools/self-update.sh', source/'tools/self-update.sh')
artifacts = root/'artifacts'; artifacts.mkdir()
for name in ['MacLayoutSwitcher', 'SpeechRecognizer']:
    binary = artifacts/name; binary.write_text('#!/bin/sh\nexit 0\n'); binary.chmod(0o755)
for name in ['MacLayoutSwitcher_SwitcherCore.bundle', 'Speech_Dependency.bundle']:
    bundle = artifacts/name; bundle.mkdir(); (bundle/'fixture.json').write_text('{"proof":"copied"}\n')
bindir = root/'bin'; bindir.mkdir()
scripts = {
    'swift': '#!/bin/sh\ncase "$*" in *--show-bin-path*) printf "%s\\n" "$MLS_FIXTURE_BIN";; esac\n',
    'uname': '#!/bin/sh\nprintf "arm64\\n"\n',
    'codesign': '#!/bin/sh\nprintf "%s\\n" "$*" >> "$MLS_FIXTURE_SIGNED"\n',
    'xattr': '#!/bin/sh\nexit 0\n',
    'hdiutil': '''#!/bin/bash
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -srcfolder) cp -R "$2" "$MLS_FIXTURE_STAGE"; shift;;
    -volname) printf '%s' "$2" > "$MLS_FIXTURE_VOLUME"; shift;;
  esac
  last="$1"; shift
done
touch "$last"
'''
}
for name, body in scripts.items():
    path = bindir/name; path.write_text(body); path.chmod(0o755)
env = os.environ.copy()
env.pop('MLS_DISABLE_SPEECH', None)
env.update(PATH=str(bindir)+':/usr/bin:/bin:/usr/sbin:/sbin', MLS_FIXTURE_BIN=str(artifacts),
           MLS_DIST_DIR=str(root/'dist'), MLS_FIXTURE_SIGNED=str(root/'signed'),
           MLS_FIXTURE_STAGE=str(root/'stage'), MLS_FIXTURE_VOLUME=str(root/'volume'))
subprocess.run(['/bin/bash', str(source/'build-dmg.sh'), '--rebuild'], env=env, check=True, capture_output=True)
app = root/'dist/MacLayoutSwitcherNext.app'
assert app.is_dir(), 'separate Next app must be produced'
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'space.alimp.maclayoutswitcher.next'
assert info['CFBundleDisplayName'] == 'Mac Layout Switcher Next'
assert info['CFBundleExecutable'] == 'MacLayoutSwitcher'
assert info['CFBundleShortVersionString'] == (repo/'VERSION').read_text().strip()
assert (app/'Contents/Helpers/SpeechRecognizer').is_file(), 'speech helper must survive packaging'
for bundle in artifacts.glob('*.bundle'):
    assert (app/'Contents/Resources'/bundle.name/'fixture.json').read_bytes() == (bundle/'fixture.json').read_bytes()
assert (app/'Contents/Resources/self-update.sh').read_bytes() == (repo/'tools/self-update.sh').read_bytes()
assert (root/'dist/MacLayoutSwitcherNext.dmg').is_file()
assert (root/'volume').read_text() == 'MacLayoutSwitcherNext'
assert sorted(p.name for p in (root/'stage').iterdir()) == ['Applications', 'MacLayoutSwitcherNext.app']
assert os.readlink(root/'stage/Applications') == '/Applications'
assert not (root/'dist/MacLayoutSwitcher.app').exists()
# A pre-existing renamed stable app must not be packaged as Next either.
info['CFBundleIdentifier'] = 'space.alimp.maclayoutswitcher'
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
refused = subprocess.run(['/bin/bash', str(source/'build-dmg.sh')], env=env, capture_output=True)
assert refused.returncode != 0, 'DMG must reject an existing app from the stable channel'
print('Next packaging PASS (controlled compiler/signing/DMG boundary):', root)
