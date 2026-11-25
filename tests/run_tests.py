"""Run the installable addon suites and verify both release ZIP formats."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / 'WhoWho'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runner', type=Path,
                    default=ROOT / 'node_modules/fengari-node-cli/src/lua-cli.js')
runner = parser.parse_args().runner.resolve()
node = shutil.which('node')
if not runner.is_file() or not node:
    parser.error('Node.js and Fengari are required. Run npm ci first.')

env = dict(os.environ, WHOWHO_ADDON_ROOT=str(ADDON),
           WHOWHO_PREVIEW_TOC=(ADDON / 'WhoWho.toc').read_text(encoding='utf-8'))
suites = sorted((ROOT / 'tests/addon').glob('*_spec.lua'))
if not suites:
    sys.exit('No addon suites found')
suites.append(ROOT / 'tests/data/address_book.lua')
markers = {
    'manual_spec.lua': r'manual address book: [1-9]\d* checks passed',
    'address_book.lua': r'address book: [1-9]\d* checks passed',
    'model_spec.lua': r'RESULT pure-model [1-9]\d* passed 0 failed',
}
for path in suites:
    result = subprocess.run([node, str(runner), str(path), '.'], cwd=ROOT, env=env,
                            capture_output=True, encoding='utf-8', errors='replace')
    marker = markers.get(path.name, r'RESULT .+ passed\b.*')
    lines = result.stdout.rstrip().splitlines()
    if (result.returncode != 0 or result.stderr.strip()
            or re.search(r'^FAIL\b', result.stdout, re.MULTILINE)
            or not lines or not re.fullmatch(marker, lines[-1])):
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        sys.exit(f'{path.relative_to(ROOT)}: suite failed or completion marker was missing')
    print(f'{path.relative_to(ROOT)}: {lines[-1]}', flush=True)

subprocess.run([sys.executable, 'tests/package_test.py'], cwd=ROOT, check=True)
print(f'{len(suites)} addon suites and release ZIP checks passed.')
