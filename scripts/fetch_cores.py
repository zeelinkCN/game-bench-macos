#!/usr/bin/env python3
"""Fetch official Apple Silicon libretro builds, keeping a provenance manifest."""
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / '.cache' / 'cores'
BASE = 'https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/'
CORES = ['fceumm', 'snes9x', 'gambatte', 'genesis_plus_gx', 'fbneo']

def fetch(name):
    filename = name + '_libretro.dylib'
    target = DEST / filename
    meta = DEST / (name + '.json')
    if target.exists() and meta.exists():
        entry = json.loads(meta.read_text())
        if hashlib.sha256(target.read_bytes()).hexdigest() == entry['sha256']:
            print(name + ': cached', flush=True)
            return entry
    url = BASE + filename + '.zip'
    with urllib.request.urlopen(url, timeout=90) as response:
        archive = response.read()
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        matches = [n for n in z.namelist() if Path(n).name == filename]
        if len(matches) != 1:
            raise ValueError('Unexpected core archive: ' + name)
        data = z.read(matches[0])
    target.write_bytes(data)
    entry = dict(name=name, url=url, sha256=hashlib.sha256(data).hexdigest())
    meta.write_text(json.dumps(entry, indent=2) + '\n')
    print(name + ': downloaded', flush=True)
    return entry

if __name__ == '__main__':
    DEST.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        result = list(pool.map(fetch, CORES))
    (DEST / 'manifest.json').write_text(json.dumps(result, indent=2) + '\n')
