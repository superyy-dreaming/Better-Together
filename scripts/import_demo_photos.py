#!/usr/bin/env python3
"""Import the approved synthetic demo archive without changing source pixels."""

import argparse
import hashlib
import io
import json
from pathlib import Path
from zipfile import ZipFile

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    args = parser.parse_args()
    destination = Path(__file__).resolve().parents[1] / 'app/assets/demo/test-photos'
    names = [
        f'{category}-{number:02d}.jpg'
        for category, count in [('food', 5), ('life', 4), ('sport', 6), ('study', 5)]
        for number in range(1, count + 1)
    ]
    payloads = {}
    manifest = []
    with ZipFile(args.archive) as archive:
        entries = archive.infolist()
        if len({item.filename for item in entries}) != len(entries):
            raise ValueError('Archive contains duplicate entries')
        for name in names:
            info = archive.getinfo(name)
            if info.file_size > 20 * 1024 * 1024:
                raise ValueError(f'Image too large: {name}')
            raw = archive.read(name)
            with Image.open(io.BytesIO(raw)) as image:
                if image.format != 'JPEG' or max(image.size) > 8192:
                    raise ValueError(f'Unexpected image format or dimensions: {name}')
                size = list(image.size)
                image.verify()
            payloads[name] = raw
            manifest.append({
                'file': name,
                'size': size,
                'sha256': hashlib.sha256(raw).hexdigest(),
                'bytes': len(raw),
            })
        readmes = [item for item in entries if item.filename.lower().endswith('.md')]
        if len(readmes) != 1 or readmes[0].file_size > 64 * 1024:
            raise ValueError('Expected one small source description')
        # ZIP filename encoding differs by archiver; preserve its UTF-8 contents
        # under a stable ASCII filename. Never execute archive content.
        payloads['README.md'] = archive.read(readmes[0]).decode('utf-8').encode('utf-8')

    destination.mkdir(parents=True, exist_ok=True)
    for name, raw in payloads.items():
        (destination / name).write_bytes(raw)
    (destination / 'manifest.json').write_text(json.dumps({
        'source': 'better-together-test-photos.zip',
        'synthetic': True,
        'images': manifest,
    }, ensure_ascii=False, indent=2) + '\n')
    print(f'Imported {len(names)} verified JPEGs; original bytes and metadata preserved.')


if __name__ == '__main__':
    main()
