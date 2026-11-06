#!/usr/bin/env python3
from pathlib import Path
import urllib.request
import concurrent.futures

root=Path(__file__).resolve().parents[1]/'Resources'/'Licenses'
sources={
 'FCEUmm.txt':['https://raw.githubusercontent.com/libretro/libretro-fceumm/master/Copying','https://raw.githubusercontent.com/libretro/libretro-fceumm/master/LICENSE'],
 'Snes9x.txt':['https://raw.githubusercontent.com/libretro/snes9x/master/LICENSE'],
 'Gambatte.txt':['https://raw.githubusercontent.com/libretro/gambatte-libretro/master/COPYING'],
 'GenesisPlusGX.txt':['https://raw.githubusercontent.com/libretro/Genesis-Plus-GX/master/LICENSE.txt','https://raw.githubusercontent.com/libretro/Genesis-Plus-GX/master/LICENSE'],
 'FBNeo.txt':['https://raw.githubusercontent.com/finalburnneo/FBNeo/master/src/license.txt','https://raw.githubusercontent.com/finalburnneo/FBNeo/master/LICENSE.md'],
}
def fetch(item):
 name,urls=item
 for url in urls:
  try:
   with urllib.request.urlopen(url,timeout=30) as r: data=r.read()
   (root/name).write_bytes(data); print(name,len(data),flush=True); return
  except Exception as e: error=e
 raise RuntimeError(name+': '+str(error))
root.mkdir(parents=True,exist_ok=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool: list(pool.map(fetch,sources.items()))
