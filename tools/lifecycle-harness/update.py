#!/usr/bin/env python3
"""Production updater with owned bundles and controlled network/launch boundaries."""
from pathlib import Path
import hashlib, json, os, subprocess, sys, tarfile, tempfile, threading, plistlib, re

repo = Path(__file__).resolve().parents[2]
root = Path(tempfile.mkdtemp(prefix='mls-update-lifecycle.', dir='/tmp'))
source = Path(os.environ.get('MLS_UPDATE_SCRIPT', repo/'tools/self-update.sh'))
raw = source.read_text()
log_assignment = re.search(r'^LOG="\$HOME/Library/Logs/[^"\n]+"$', raw, re.M).group()
script = root/'self-update-fixture.sh'
script.write_text(raw.replace(log_assignment, 'LOG="$MLS_FIXTURE_LOG"'))
(root/'source-self-update.sh').write_text(raw)
results = []
scenarios = sys.argv[1:] or ['offline', 'invalid_archive', 'build_fail', 'copy_fail', 'install_fail',
                           'launch_fail', 'rollback_fail', 'success', 'wait_for_exit', 'parent_timeout',
                           'untrusted_cleanup_path', 'owned_cleanup_path', 'relaunch_fail', 'log_failure', 'log_open_failure', 'installed_stable', 'installed_missing_identity',
                           'candidate_stable', 'candidate_missing_identity', 'candidate_wrong_executable',
                           'candidate_downgrade', 'candidate_same_version', 'candidate_unsigned']
for scenario in scenarios:
    d = root/scenario; d.mkdir()
    app = d/"Mac's $(touch UNEXPECTED) Layout Switcher.app"
    exe = app/'Contents/MacOS/MacLayoutSwitcher'
    exe.parent.mkdir(parents=True); exe.write_text('old working binary'); exe.chmod(0o755)
    def identity(bundle_id='space.alimp.maclayoutswitcher.next', version='1.5.0', executable='MacLayoutSwitcher'):
        return dict(CFBundleIdentifier=bundle_id, CFBundleShortVersionString=version,
                    CFBundleExecutable=executable, CFBundlePackageType='APPL')
    installed_identity = identity(bundle_id='space.alimp.maclayoutswitcher' if scenario == 'installed_stable' else 'space.alimp.maclayoutswitcher.next')
    if scenario != 'installed_missing_identity':
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps(installed_identity))
    sentinel = d/'preserve.txt'; sentinel.write_text('unrelated user file')
    bindir = d/'bin'; bindir.mkdir()
    calls = d/'open.calls'
    (bindir/'open').write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
exe = Path(args[0])/'Contents/MacOS/MacLayoutSwitcher'
body = exe.read_text() if exe.is_file() else None
scenario = os.environ['MLS_FIXTURE_SCENARIO']
failed = (scenario == 'launch_fail' and body == 'new working binary') or (scenario == 'relaunch_fail' and body is not None)
try: os.kill(int(os.environ['MLS_FIXTURE_PARENT']), 0); alive = True
except (KeyError, ProcessLookupError): alive = False
with open(os.environ['MLS_FIXTURE_CALLS'], 'a') as f:
    f.write(json.dumps(dict(args=args, bundle=body, accepted=not failed, parent_alive=alive))+"\\n")
sys.exit(74 if failed else 0)
''')
    src = d/'src/mac-layout-switcher-next-main'; src.mkdir(parents=True)
    build = '#!/bin/bash\nexit 71\n' if scenario == 'build_fail' else '''#!/bin/bash
mkdir -p dist/MacLayoutSwitcherNext.app/Contents/MacOS
printf 'new working binary' > dist/MacLayoutSwitcherNext.app/Contents/MacOS/MacLayoutSwitcher
chmod +x dist/MacLayoutSwitcherNext.app/Contents/MacOS/MacLayoutSwitcher
'''
    candidate = identity(version='1.4.99' if scenario == 'candidate_downgrade' else '1.5.0' if scenario == 'candidate_same_version' else '1.5.1',
                         bundle_id='space.alimp.maclayoutswitcher' if scenario == 'candidate_stable' else 'space.alimp.maclayoutswitcher.next',
                         executable='Other' if scenario == 'candidate_wrong_executable' else 'MacLayoutSwitcher')
    if scenario != 'candidate_missing_identity':
        (src/'candidate.plist').write_bytes(plistlib.dumps(candidate))
        build += 'cp candidate.plist dist/MacLayoutSwitcherNext.app/Contents/Info.plist\n'
    (src/'build.sh').write_text(build)
    (bindir/'codesign').write_text('#!/bin/bash\nexit ' + ('76' if scenario == 'candidate_unsigned' else '0') + '\n')
    archive = d/'source.tar.gz'
    if scenario == 'invalid_archive': archive.write_text('bad archive')
    else:
        with tarfile.open(archive, 'w:gz') as f: f.add(src, arcname='mac-layout-switcher-next-main')
    curl = '#!/bin/bash\nexit 6\n' if scenario in ['offline', 'relaunch_fail'] else '''#!/bin/bash
[[ "${@: -1}" == "https://github.com/alimp01/mac-layout-switcher-next/archive/refs/heads/main.tar.gz" ]] || exit 92
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == '-o' ]]; then /bin/cp "$MLS_FIXTURE_ARCHIVE" "$2"; exit; fi
    shift
done
exit 91
'''
    (bindir/'curl').write_text(curl)
    if scenario == 'copy_fail': (bindir/'cp').write_text('#!/bin/bash\nexit 75\n')
    if scenario in ['install_fail', 'rollback_fail']:
        (bindir/'mv').write_text('''#!/bin/bash
if [[ "$1" == */new.app ]]; then exit 72; fi
if [[ "$MLS_FIXTURE_SCENARIO" == rollback_fail && "$1" == */previous.app ]]; then exit 73; fi
exec /bin/mv "$@"
''')
    if scenario == 'parent_timeout': (bindir/'sleep').write_text('#!/bin/bash\nexit 0\n')
    for file in bindir.iterdir(): file.chmod(0o755)
    env = os.environ.copy()
    env.update(PATH=str(bindir)+':/usr/bin:/bin:/usr/sbin:/sbin', MLS_FIXTURE_LOG=str(d/'update.log'),
               MLS_FIXTURE_CALLS=str(calls), MLS_FIXTURE_ARCHIVE=str(archive), MLS_FIXTURE_SCENARIO=scenario)
    if scenario == 'log_open_failure': (d/'update.log').mkdir()
    if scenario == 'log_failure':
        (d/'blocked').write_text('not a directory')
        env['MLS_FIXTURE_LOG'] = str(d/'blocked/update.log')
    args = ['/bin/bash', str(script), str(app)]
    parent = None
    if scenario in ['wait_for_exit', 'parent_timeout']:
        parent = subprocess.Popen(['/bin/sleep', '0.3' if scenario == 'wait_for_exit' else '30'])
        threading.Thread(target=parent.wait, daemon=True).start()
        env['MLS_FIXTURE_PARENT'] = str(parent.pid)
        args += ['', str(parent.pid)]
    if scenario == 'untrusted_cleanup_path': args += [str(d)]
    if scenario == 'owned_cleanup_path':
        own = d/'MacLayoutSwitcherNext-update-owned'; own.mkdir()
        (own/'self-update.sh').write_text(script.read_text())
        args = ['/bin/bash', str(own/'self-update.sh'), str(app), str(own)]
    run = subprocess.run(args, env=env, cwd=d, capture_output=True, text=True, timeout=15)
    if parent is not None and parent.poll() is None: parent.terminate(); parent.wait()
    opened = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
    app_opens = [x for x in opened if x['bundle'] is not None]
    reports = [x for x in opened if '-t' in x['args']]
    success = scenario in ['success', 'wait_for_exit', 'untrusted_cleanup_path', 'owned_cleanup_path']
    expected = 'new working binary' if success else '<missing>' if scenario == 'rollback_fail' else 'old working binary'
    backups = list(d.glob('.MacLayoutSwitcherNext-update.*/previous.app/Contents/MacOS/MacLayoutSwitcher'))
    accepted = [x for x in app_opens if x['accepted']]
    preflight_refused = scenario in ['installed_stable', 'installed_missing_identity']
    expected_accepted = 0 if preflight_refused or scenario in ['rollback_fail', 'parent_timeout', 'relaunch_fail'] else 1
    report_ok = len(reports) == (0 if success or preflight_refused else 1)
    if reports:
        report = Path(reports[0]['args'][1]).read_text()
        report_ok = report_ok and 'Не удалось обновить' in report and 'Подробности:' in report
        if scenario == 'relaunch_fail': report_ok = report_ok and 'Автоматический запуск не удался' in report
        if scenario == 'rollback_fail': report_ok = report_ok and str(backups[0].parents[2]) in report if backups else False
    result = dict(scenario=scenario, exit=run.returncode, installed_text=exe.read_text() if exe.exists() else '<missing>',
                  app_launch_requests=len(app_opens), accepted_launches=len(accepted), reports=len(reports))
    result['passed'] = (result['installed_text'] == expected and len(accepted) == expected_accepted
                        and len(app_opens) == (2 if scenario == 'launch_fail' else 0 if preflight_refused or scenario in ['rollback_fail', 'parent_timeout'] else 1)
                        and (run.returncode == 0 if success else run.returncode != 0)
                        and sentinel.exists() and sentinel.read_text() == 'unrelated user file' and not (d/'UNEXPECTED').exists()
                        and report_ok and all(not x['parent_alive'] and '-n' not in x['args'] for x in app_opens)
                        and (len(backups) == 1 and backups[0].read_text() == 'old working binary' if scenario == 'rollback_fail' else not backups)
                        and (not own.exists() if scenario == 'owned_cleanup_path' else True))
    results.append(result)
print('Updater lifecycle scratch:', root)
print(json.dumps(results, indent=2))
(root/'results.json').write_text(json.dumps(results, indent=2)+'\n')
(root/'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(root))+'\n'
                             for p in sorted(root.rglob('*')) if p.is_file()))
sys.exit(0 if all(r['passed'] for r in results) else 1)
