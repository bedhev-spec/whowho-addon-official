"""Build the versioned WhoWho ZIP from the installable addon directory."""

import argparse
from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / 'WhoWho'
TAG = re.compile(r'v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-rc\.[1-9][0-9]*)?)')


def build(tag, output):
    match = TAG.fullmatch(tag)
    if not match:
        raise ValueError('Expected vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-rc.N (N starts at 1)')
    version = match[1]
    toc = ADDON / 'WhoWho.toc'
    lines = toc.read_text(encoding='utf-8').splitlines()
    version_lines = [index for index, line in enumerate(lines) if line.startswith('## Version:')]
    if len(version_lines) != 1:
        raise ValueError('WhoWho.toc must have exactly one Version field')
    source_version = lines[version_lines[0]].removeprefix('## Version:').strip()
    lines[version_lines[0]] = f'## Version: {version}'
    manual = ADDON / 'ManualAddressBook.lua'
    media = ADDON / 'Media'
    if ADDON.is_symlink() or media.is_symlink():
        raise ValueError('WhoWho/ and WhoWho/Media/ must be ordinary directories')

    files = [toc, ADDON / 'LICENSE']
    for line in lines:
        entry = line.strip()
        if not entry or entry.startswith('#'):
            continue
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*\.lua', entry):
            raise ValueError(f'Invalid TOC entry {entry!r}')
        files.append(ADDON / entry)
    files.extend(sorted(media.iterdir()))
    if len(set(files)) != len(files):
        raise ValueError('Duplicate addon file')
    for path in files:
        if path.is_symlink() or not path.is_file():
            raise ValueError(f'Expected regular file {path.relative_to(ROOT)}')
        if path.parent.name == 'Media' and path.suffix not in {'.tga', '.ttf', '.txt'}:
            raise ValueError(f'Unsupported addon media {path.name}')
    if set(files) != {path for path in ADDON.rglob('*') if not path.is_dir()}:
        raise ValueError('Unexpected file in WhoWho/')

    manual_source = manual.read_bytes()
    old_version = f'P.version = "{source_version}"'.encode('utf-8')
    if manual not in files or not source_version or manual_source.count(old_version) != 1:
        raise ValueError('ManualAddressBook.lua must declare the same version as WhoWho.toc')
    overrides = {
        toc: ('\n'.join(lines) + '\n').encode('utf-8'),
        manual: manual_source.replace(old_version, f'P.version = "{version}"'.encode()),
    }
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f'WhoWho-{version}.zip'
    with ZipFile(archive, 'x') as package:
        for path in files:
            data = overrides[path] if path in overrides else path.read_bytes()
            # Use a fixed timestamp and regular-file mode for reproducible archive entries.
            entry = ZipInfo(path.relative_to(ROOT).as_posix())
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            package.writestr(entry, data, compress_type=ZIP_DEFLATED)
    return archive


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    try:
        print(build(args.tag, args.output))
    except (OSError, ValueError) as error:
        parser.exit(1, f'{error}\n')
