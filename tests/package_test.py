"""Verify both release archive inventories, contents and version fields."""

from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / 'WhoWho'
TOC = 'WhoWho/WhoWho.toc'
MANUAL = 'WhoWho/ManualAddressBook.lua'
expected = {path.relative_to(ROOT).as_posix(): path.read_bytes()
            for path in ADDON.rglob('*') if path.is_file()}
source_toc = expected[TOC].decode('utf-8').splitlines()
version_header = next(line for line in source_toc if line.startswith('## Version:'))
source_version = version_header.removeprefix('## Version:').strip()
assert '## Title: WhoWho' in source_toc
assert r'## IconTexture: Interface\AddOns\WhoWho\Media\MascotMain' in source_toc

command = [sys.executable, str(ROOT / 'tools/package.py')]
with TemporaryDirectory(prefix='whowho-package-') as output:
    for tag in ('v1.0.0-rc.1', 'v1.0.0'):
        subprocess.run([*command, tag, '--output', output], check=True, capture_output=True)
        version = tag.removeprefix('v')
        with ZipFile(Path(output) / f'WhoWho-{version}.zip') as package:
            names = package.namelist()
            assert len(names) == len(expected) and set(names) == set(expected)
            for name, data in expected.items():
                if name == TOC:
                    lines = [f'## Version: {version}' if line == version_header else line
                             for line in source_toc]
                    data = ('\n'.join(lines) + '\n').encode('utf-8')
                if name == MANUAL:
                    data = data.replace(f'P.version = "{source_version}"'.encode(),
                                        f'P.version = "{version}"'.encode())
                assert package.read(name) == data, name

    invalid = subprocess.run([*command, 'v1.0.0-rc.0', '--output', output], capture_output=True)
    assert invalid.returncode != 0
print(f'WhoWho RC and production ZIPs: {len(expected)} exact entries each')
